import '../current_author_name.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../community/comments/comment_models.dart';
import '../../../community/comments/comment_visibility_store.dart';
import '../../../config/endpoint_config.dart';
import '../../../community/comments/comment_time.dart';
import '../../../community/comments/comment_repository.dart';
import '../../../l10n/app_localizations.dart';
import 'comment_report_sheet.dart';
import '../../design_system.dart';

/// The picker returns private in-memory drafts. No upload occurs until submission.
typedef CommunityCommentImagePicker =
    Future<List<CommunityCommentImageDraft>> Function(int remaining);

/// Place in a bounded, keyboard-resized area so the model can remain mounted above.
class CommunityCommentsPanel extends StatefulWidget {
  const CommunityCommentsPanel({
    super.key,
    required this.workId,
    required this.repository,
    required this.currentUserId,
    this.onSignIn,
    this.workAuthorId,
    this.selectedAnchor,
    this.expectedAssetSha256,
    this.requireAssetBinding = false,
    this.onPickPoint,
    this.onClearAnchor,
    this.onClose,
    this.onCommentSelected,
    this.onVisibleCommentsChanged,
    this.onCommentSubmitted,
    this.onPublicCountChanged,
    this.onModerationCaseSelected,
    this.refreshInterval = const Duration(seconds: 30),
    this.active = true,
    this.imagePicker,
    this.presentationVisible = true,
  });
  final String workId;
  final CommunityCommentRepository repository;
  final String? currentUserId;
  final String? workAuthorId;
  final VoidCallback? onSignIn;
  final CommunityCommentAnchor? selectedAnchor;
  final String? expectedAssetSha256;
  final bool requireAssetBinding;
  final VoidCallback? onPickPoint;
  final VoidCallback? onClearAnchor;
  final VoidCallback? onClose;
  final ValueChanged<CommunityComment>? onCommentSelected;
  final ValueChanged<List<CommunityComment>>? onVisibleCommentsChanged;
  final void Function(CommunityComment, CommunityCommentAnchor?)?
  onCommentSubmitted;

  /// Server total, independent of loaded pages and personal hiding.
  final ValueChanged<int>? onPublicCountChanged;
  final CommunityCommentImagePicker? imagePicker;
  final ValueChanged<String>? onModerationCaseSelected;

  /// Null disables polling, for static previews and deterministic callers.
  final Duration? refreshInterval;
  final bool active;

  /// Keep feed state for pins without building off-screen media or the composer.
  final bool presentationVisible;

  @override
  State<CommunityCommentsPanel> createState() => _CommunityCommentsPanelState();
}

class _CommunityCommentsPanelState extends State<CommunityCommentsPanel>
    with WidgetsBindingObserver {
  AppL10n get _l => AppL10n.of(context);
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _images = <CommunityCommentImageDraft>[];
  final _busyComments = <String>{};
  final _reportRevision = ValueNotifier(0);
  List<CommunityComment> _comments = [];
  final _visibilityStore = const CommentVisibilityStore();
  Set<String> _hiddenCommentIds = {};
  bool _visibilityLoaded = false;
  int _visibilityReadToken = 0;
  String? _visibilityError;
  String get _visibilityScope {
    final config = EndpointConfigResolver.current;
    return jsonEncode([
      config?.deployment.namespace ?? 'local',
      config?.supabaseUrl ?? 'local',
      widget.currentUserId ?? 'anonymous',
      widget.workId,
    ]);
  }

  List<CommunityComment> get _visibleComments => _visibilityLoaded
      ? _comments.where((c) => !_hiddenCommentIds.contains(c.id)).toList()
      : [];

  bool get _chinese => Localizations.localeOf(context).languageCode == 'zh';

  Future<void> _loadVisibility() async {
    final generation = _generation;
    final token = ++_visibilityReadToken;
    final scope = _visibilityScope;
    try {
      final hidden = await _visibilityStore
          .read(scope)
          .timeout(const Duration(seconds: 5));
      if (!_current(generation) ||
          token != _visibilityReadToken ||
          scope != _visibilityScope) {
        return;
      }
      setState(() {
        _hiddenCommentIds = hidden;
        _visibilityLoaded = true;
        _visibilityError = null;
      });
      _notifyVisible();
    } catch (_) {
      if (!_current(generation) ||
          token != _visibilityReadToken ||
          scope != _visibilityScope) {
        return;
      }
      setState(() {
        _visibilityLoaded = false;
        _visibilityError = _chinese
            ? '隐藏偏好读取失败，请重试'
            : 'Could not load hidden comments. Retry.';
      });
    }
  }

  Future<void> _setCommentHidden(CommunityComment comment, bool hidden) async {
    if (_busyComments.contains(comment.id) || !_visibilityLoaded) return;
    final generation = _generation;
    final scope = _visibilityScope;
    setState(() => _busyComments.add(comment.id));
    try {
      await _visibilityStore.setHidden(scope, comment.id, hidden);
      if (!mounted || !_current(generation) || scope != _visibilityScope) {
        return;
      }
      setState(() {
        if (hidden) {
          _hiddenCommentIds.add(comment.id);
          if (_reply?.id == comment.id) _reply = null;
          if (_previewCommentId == comment.id) {
            _previewCommentId = null;
            _previewAttachment = null;
          }
        } else {
          _hiddenCommentIds.remove(comment.id);
        }
      });
      _notifyVisible();
    } catch (_) {
      if (!_current(generation) || scope != _visibilityScope) return;
      setState(
        () => _error = _chinese
            ? '隐藏偏好保存失败，请重试'
            : 'Could not save your preference. Retry.',
      );
    } finally {
      if (_current(generation) && scope == _visibilityScope) {
        setState(() => _busyComments.remove(comment.id));
      }
    }
  }

  final _parentComments = <String, CommunityComment>{};
  final _sectionIds = <CommunityCommentSection, List<String>>{};
  final _sectionCursors = <CommunityCommentSection, String?>{};
  final _sectionErrors = <CommunityCommentSection, String>{};
  final _sectionBusy = <CommunityCommentSection, int>{};
  bool get _paged => widget.repository is CommunityCommentFeedRepository;
  void _resetSections() {
    _parentComments.clear();
    _sectionIds.clear();
    _sectionCursors.clear();
    _sectionErrors.clear();
    _sectionBusy.clear();
  }

  CommunityCommentPage? _page;
  CommunityCommentAnchor? _anchor;
  CommunityComment? _reply;
  CommunityCommentAttachment? _previewAttachment;
  String? _previewCommentId;
  Timer? _refreshTimer;
  bool _routeCurrent = true;
  bool _tickerEnabled = true;
  bool _attached = true;
  bool _pollingEnabled = false;
  int? _inflightLoadToken;
  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  String? _requestId;
  String _previousText = '';
  String? _error;
  String? _loadError;
  bool _snapshotInvalidated = false;

  void _acceptFreshSnapshot() {
    if (!_snapshotInvalidated) return;
    _snapshotInvalidated = false;
    _error = null;
  }

  bool _loading = true;
  bool _refreshing = false;
  bool _sending = false;
  bool _picking = false;
  bool _emojiOpen = false;
  int _generation = 0;
  int _loadToken = 0;
  int _publicCount = 0;
  int? _notifiedPublicCount;
  int _notifiedPublicCountGeneration = -1;
  bool get _canComment =>
      widget.currentUserId != null && _page?.canComment == true;
  bool get _withinTextLimit => CommunityCommentDraft.allowsText(_text.text);
  bool get _hasDraft => _text.text.trim().isNotEmpty || _images.isNotEmpty;
  bool _current(int generation) => mounted && generation == _generation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _anchor = widget.selectedAnchor;
    _text.addListener(_textChanged);
    _loadVisibility();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeCurrent = ModalRoute.isCurrentOf(context) ?? true;
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _syncPolling(refreshNow: state == AppLifecycleState.resumed);
  }

  @override
  void deactivate() {
    _attached = false;
    _syncPolling();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _attached = true;
    _syncPolling(refreshOnEnable: false);
  }

  void _syncPolling({bool refreshNow = false, bool refreshOnEnable = true}) {
    final interval = widget.refreshInterval;
    final allowed =
        mounted &&
        _attached &&
        widget.active &&
        _foreground &&
        _routeCurrent &&
        _tickerEnabled &&
        interval != null &&
        interval > Duration.zero;
    final wasEnabled = _pollingEnabled;
    _pollingEnabled = allowed;
    if (!allowed) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      return;
    }
    _refreshTimer ??= Timer.periodic(interval, (_) => _refresh());
    if (refreshNow || (refreshOnEnable && !wasEnabled && _page != null)) {
      _refresh();
    }
  }

  void _refresh() {
    if (!_pollingEnabled ||
        !_foreground ||
        _sending ||
        _busyComments.isNotEmpty ||
        _inflightLoadToken != null) {
      return;
    }
    _load(refresh: true);
  }

  Future<void> _manualRefresh() async {
    if (_refreshing ||
        _loading ||
        _sending ||
        _busyComments.isNotEmpty ||
        _inflightLoadToken != null) {
      return;
    }
    setState(() => _refreshing = true);
    try {
      await _load(refresh: true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  void didUpdateWidget(CommunityCommentsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workId != widget.workId ||
        oldWidget.currentUserId != widget.currentUserId ||
        oldWidget.repository != widget.repository ||
        oldWidget.expectedAssetSha256 != widget.expectedAssetSha256 ||
        oldWidget.requireAssetBinding != widget.requireAssetBinding) {
      _generation++;
      _text.clear();
      _images.clear();
      _comments = [];
      _hiddenCommentIds = {};
      _visibilityLoaded = false;
      _visibilityError = null;
      _loadVisibility();
      _resetSections();
      _busyComments.clear();
      _page = null;
      _reply = null;
      _previewAttachment = null;
      _previewCommentId = null;
      _requestId = null;
      _error = null;
      _sending = false;
      _picking = false;
      _emojiOpen = false;
      _publicCount = 0;
      _anchor = null;
      final generation = _generation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_current(generation)) widget.onClearAnchor?.call();
      });
      _notifyVisible();
      _load();
    } else if (oldWidget.selectedAnchor != widget.selectedAnchor) {
      _anchor = widget.selectedAnchor;
      _requestId = null;
      _error = null;
    }
    if (oldWidget.refreshInterval != widget.refreshInterval) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
    _syncPolling(refreshOnEnable: false);
  }

  void _textChanged() {
    if (_previousText == _text.text) return;
    _previousText = _text.text;
    _requestId = null;
    if (mounted) setState(() => _error = null);
  }

  bool _clearInvalidIdentity(Object error) {
    if (error is! CommunityCommentException ||
        !{'identity_changed', 'auth_required'}.contains(error.code)) {
      return false;
    }
    _clearPrivateState(error.message);
    return true;
  }

  void _clearPrivateState(String message) {
    setState(() {
      _generation++;
      _loadToken++;
      _text.clear();
      _images.clear();
      _comments = [];
      _resetSections();
      _busyComments.clear();
      _page = null;
      _reply = null;
      _previewAttachment = null;
      _previewCommentId = null;
      _requestId = null;
      _anchor = null;
      _publicCount = 0;
      _sending = false;
      _picking = false;
      _loading = false;
      _emojiOpen = false;
      _error = message;
      _loadError = message;
      _hiddenCommentIds = {};
      _visibilityReadToken++;
      _visibilityLoaded = true;
      _visibilityError = null;
      _snapshotInvalidated = true;
    });
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current(generation)) widget.onClearAnchor?.call();
    });
    _notifyVisible();
    _loadVisibility();
  }

  void _changed(VoidCallback change) {
    setState(() {
      change();
      _requestId = null;
      _error = null;
    });
  }

  void _notifyVisible() {
    _reportRevision.value++;
    final generation = _generation;
    final token = _loadToken;
    final rows = List<CommunityComment>.unmodifiable(_ranked(_visibleComments));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current(generation) && token == _loadToken) {
        widget.onVisibleCommentsChanged?.call(rows);
        if (_current(generation) &&
            _page != null &&
            (_notifiedPublicCountGeneration != generation ||
                _notifiedPublicCount != _publicCount)) {
          _notifiedPublicCountGeneration = generation;
          _notifiedPublicCount = _publicCount;
          widget.onPublicCountChanged?.call(_publicCount);
        }
      }
    });
  }

  Future<void> _load({bool refresh = false}) async {
    final generation = _generation;
    final token = ++_loadToken;
    _inflightLoadToken = token;
    if (_paged && refresh) {
      try {
        await _refreshPagedSnapshot(generation, token);
      } finally {
        if (_inflightLoadToken == token) _inflightLoadToken = null;
      }
      return;
    }
    if (_paged) {
      setState(() {
        _loading = false;
        _loadError = null;
        _resetSections();
        _comments = [];
      });
      _notifyVisible();
      try {
        await Future.wait([
          for (final section in const [CommunityCommentSection.hot])
            _loadSection(section, token: token),
        ]);
      } finally {
        if (_inflightLoadToken == token) _inflightLoadToken = null;
      }
      return;
    }
    setState(() {
      if (!refresh) _loading = true;
      _loadError = null;
    });
    try {
      final page = await widget.repository
          .fetch(widget.workId)
          .timeout(const Duration(seconds: 30));
      if (!_current(generation) || token != _loadToken) return;
      if (widget.requireAssetBinding &&
          (widget.expectedAssetSha256 == null ||
              !RegExp(
                r'^[a-f0-9]{64}$',
              ).hasMatch(widget.expectedAssetSha256!) ||
              page.assetSha256 != widget.expectedAssetSha256)) {
        _clearPrivateState(
          widget.expectedAssetSha256 == null
              ? _l.commentAssetChecking
              : _l.commentAssetUpdated,
        );
        return;
      }
      setState(() {
        _page = page;
        _comments = page.comments
            .where(
              (c) =>
                  c.workId == widget.workId &&
                  c.visibleTo(widget.currentUserId),
            )
            .toList();
        _publicCount = page.publicCount;
        _acceptFreshSnapshot();
        if (_reply != null &&
            !_comments.any((c) => c.id == _reply!.id && c.published)) {
          _reply = null;
          _requestId = null;
        }
        final previewComment = _comments
            .where((c) => c.id == _previewCommentId)
            .firstOrNull;
        if (_previewAttachment != null &&
            (previewComment == null ||
                previewComment.status == CommunityCommentStatus.hidden ||
                !previewComment.attachments.any(
                  (a) =>
                      a.id == _previewAttachment!.id &&
                      a.url == _previewAttachment!.url,
                ))) {
          _previewAttachment = null;
          _previewCommentId = null;
        }
        _loading = false;
      });
      _notifyVisible();
    } catch (error) {
      if (!_current(generation) || token != _loadToken) return;
      if (_clearInvalidIdentity(error)) return;
      setState(() {
        _loading = false;
        _loadError = error is CommunityCommentException
            ? error.message
            : _l.commentLoadFailed;
      });
    } finally {
      if (_inflightLoadToken == token) _inflightLoadToken = null;
    }
  }

  /// Refresh stages the ranked first page without publishing a transient empty feed.
  /// A validated snapshot replaces the old rows once; errors revoke remote
  /// content immediately, and late/stale responses cannot refill it.
  Future<void> _refreshPagedSnapshot(int generation, int token) async {
    setState(() {
      _loadError = null;
      _sectionErrors.clear();
      for (final section in const [CommunityCommentSection.hot]) {
        _sectionBusy[section] = ++_sectionRequest;
      }
    });
    try {
      final pages = await Future.wait([
        for (final section in const [CommunityCommentSection.hot])
          (widget.repository as CommunityCommentFeedRepository)
              .fetchSection(widget.workId, section: section)
              .timeout(const Duration(seconds: 30))
              .then((page) {
                if (widget.requireAssetBinding &&
                    (widget.expectedAssetSha256 == null ||
                        !RegExp(
                          r'^[a-f0-9]{64}$',
                        ).hasMatch(widget.expectedAssetSha256!) ||
                        page.assetSha256 != widget.expectedAssetSha256)) {
                  throw const CommunityCommentException('asset_changed');
                }
                return MapEntry(section, page);
              }),
      ], eagerError: true);
      if (!_current(generation) || token != _loadToken) return;
      if (pages.any(
        (entry) => entry.value.assetRevision != pages.first.value.assetRevision,
      )) {
        throw const CommunityCommentException('asset_changed');
      }
      final rows = <String, CommunityComment>{};
      setState(() {
        _resetSections();
        for (final entry in pages) {
          final page = entry.value;
          final ids = <String>[];
          for (final comment in page.comments) {
            if (comment.workId == widget.workId &&
                comment.visibleTo(widget.currentUserId)) {
              if (!ids.contains(comment.id)) ids.add(comment.id);
              rows[comment.id] = comment;
            }
          }
          _sectionIds[entry.key] = ids;
          _sectionCursors[entry.key] = page.nextCursor;
          for (final parent in page.contextComments) {
            if (parent.workId == widget.workId &&
                parent.visibleTo(widget.currentUserId)) {
              _parentComments[parent.id] = parent;
            }
          }
        }
        _comments = rows.values.toList();
        _page = pages
            .map((entry) => entry.value)
            .firstWhere(
              (page) => !page.canComment,
              orElse: () => pages.last.value,
            );
        _publicCount = _page!.publicCount;
        _acceptFreshSnapshot();
        _loading = false;
        if (_reply != null &&
            !rows.values.any((c) => c.id == _reply!.id && c.published)) {
          _reply = null;
        }
        final preview = rows[_previewCommentId];
        if (_previewAttachment != null &&
            (preview == null ||
                !preview.attachments.any(
                  (image) =>
                      image.id == _previewAttachment!.id &&
                      image.url == _previewAttachment!.url,
                ))) {
          _previewAttachment = null;
          _previewCommentId = null;
        }
      });
      _notifyVisible();
    } catch (error) {
      if (!_current(generation) || token != _loadToken) return;
      if (_clearInvalidIdentity(error)) return;
      if (error is CommunityCommentException && error.code == 'asset_changed') {
        _clearPrivateState(
          widget.expectedAssetSha256 == null
              ? _l.commentAssetChecking
              : _l.commentAssetUpdated,
        );
        return;
      }
      // Keep the user's unsent local draft, but never display stale server
      // content or allow a write after an unavailable/denied refresh.
      setState(() {
        _loadToken++;
        _comments = [];
        _resetSections();
        _page = null;
        _publicCount = 0;
        _reply = null;
        _previewAttachment = null;
        _previewCommentId = null;
        _loading = false;
        _loadError = error is CommunityCommentException
            ? error.message
            : _l.commentLoadFailed;
      });
      _notifyVisible();
    }
  }

  Future<void> _loadSection(
    CommunityCommentSection section, {
    int? token,
  }) async {
    if (_sectionBusy.containsKey(section)) return;
    final generation = _generation;
    final requestToken = token ?? _loadToken;
    final requestId = ++_sectionRequest;
    final cursor = _sectionCursors[section];
    setState(() {
      _sectionBusy[section] = requestId;
      _sectionErrors.remove(section);
    });
    try {
      final page = await (widget.repository as CommunityCommentFeedRepository)
          .fetchSection(widget.workId, section: section, cursor: cursor)
          .timeout(const Duration(seconds: 30));
      if (!_current(generation) || requestToken != _loadToken) return;
      if (widget.requireAssetBinding &&
          (widget.expectedAssetSha256 == null ||
              !RegExp(
                r'^[a-f0-9]{64}$',
              ).hasMatch(widget.expectedAssetSha256!) ||
              page.assetSha256 != widget.expectedAssetSha256)) {
        _clearPrivateState(
          widget.expectedAssetSha256 == null
              ? _l.commentAssetChecking
              : _l.commentAssetUpdated,
        );
        return;
      }
      setState(() {
        _page = page;
        for (final parent in page.contextComments) {
          if (parent.workId == widget.workId &&
              parent.visibleTo(widget.currentUserId)) {
            _parentComments[parent.id] = parent;
          }
        }
        _publicCount = page.publicCount;
        _acceptFreshSnapshot();
        final ids = _sectionIds.putIfAbsent(section, () => []);
        for (final comment in page.comments) {
          if (comment.workId != widget.workId ||
              !comment.visibleTo(widget.currentUserId)) {
            continue;
          }
          if (!ids.contains(comment.id)) ids.add(comment.id);
          _comments.removeWhere((c) => c.id == comment.id);
          _comments.add(comment);
        }
        // A repeated cursor cannot cause an endless load-more loop.
        _sectionCursors[section] = page.nextCursor == cursor
            ? null
            : page.nextCursor;
        if (_reply != null &&
            page.comments.any((c) => c.id == _reply!.id && !c.published)) {
          _reply = null;
        }
        final preview = _comments
            .where((c) => c.id == _previewCommentId)
            .firstOrNull;
        if (_previewAttachment != null &&
            (preview == null ||
                preview.status == CommunityCommentStatus.hidden ||
                !preview.attachments.any(
                  (a) =>
                      a.id == _previewAttachment!.id &&
                      a.url == _previewAttachment!.url,
                ))) {
          _previewAttachment = null;
          _previewCommentId = null;
        }
      });
      _notifyVisible();
    } catch (error) {
      if (!_current(generation) || requestToken != _loadToken) return;
      if (_clearInvalidIdentity(error)) return;
      setState(
        () => _sectionErrors[section] = error is CommunityCommentException
            ? error.message
            : _l.commentLoadRetry,
      );
    } finally {
      if (_current(generation) && _sectionBusy[section] == requestId) {
        setState(() => _sectionBusy.remove(section));
      }
    }
  }

  int _sectionRequest = 0;

  Future<void> _send() async {
    if (!_canComment ||
        !_hasDraft ||
        !_withinTextLimit ||
        _sending ||
        _picking) {
      return;
    }
    final generation = _generation;
    final requestId = _requestId ??= const Uuid().v4();
    final draft = CommunityCommentDraft(
      workId: widget.workId,
      assetRevision: _page!.assetRevision,
      body: _text.text,
      clientRequestId: requestId,
      images: _images,
      anchor: _anchor,
      parentId: _reply?.id,
    );
    ++_loadToken; // A pre-submit list response must not overwrite the new row.
    setState(() {
      _sending = true;
      _loading = false;
      _error = null;
    });
    try {
      draft.validate();
      final comment = await widget.repository.submit(draft);
      if (!_current(generation)) return;
      if (comment.workId != widget.workId ||
          comment.userId != widget.currentUserId ||
          !comment.visibleTo(widget.currentUserId) ||
          comment.status == CommunityCommentStatus.error) {
        throw const CommunityCommentException('invalid_response');
      }
      setState(() {
        final previous = _comments.where((c) => c.id == comment.id).firstOrNull;
        _comments.removeWhere((c) => c.id == comment.id);
        _comments.add(comment);
        if (_paged) {
          final ranked = _sectionIds.putIfAbsent(
            CommunityCommentSection.hot,
            () => [],
          );
          ranked.remove(comment.id);
          ranked.add(comment.id);
        }
        if (comment.published && previous?.published != true) _publicCount++;
        _text.clear();
        _images.clear();
        _reply = null;
        _anchor = null;
        _requestId = null;
        _sending = false;
      });
      widget.onCommentSubmitted?.call(comment, draft.anchor);
      widget.onClearAnchor?.call();
      _notifyVisible();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_current(generation) && _scroll.hasClients) {
          _scroll.animateTo(
            _paged ? 0 : _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (error) {
      if (!_current(generation)) return;
      if (_clearInvalidIdentity(error)) return;
      setState(() {
        _sending = false;
        _error = _l.commentSendFailed;
      });
    }
  }

  Future<List<CommunityCommentImageDraft>> _defaultPick(int remaining) async {
    final l = _l;
    final picked = await ImagePicker().pickMultiImage(
      requestFullMetadata: false,
      limit: remaining > 1 ? remaining : null,
    );
    if (picked.length > remaining) throw FormatException(l.commentImageLimit);
    final drafts = <CommunityCommentImageDraft>[];
    for (final file in picked) {
      if (await file.length() > CommunityCommentImageDraft.maxBytes) {
        throw FormatException(l.commentImageTooLarge);
      }
      final name = file.name;
      final lower = name.toLowerCase();
      final mime =
          file.mimeType ??
          (lower.endsWith('.png')
              ? 'image/png'
              : lower.endsWith('.webp')
              ? 'image/webp'
              : lower.endsWith('.jpg') || lower.endsWith('.jpeg')
              ? 'image/jpeg'
              : '');
      final draft = CommunityCommentImageDraft(
        bytes: await file.readAsBytes(),
        fileName: name,
        mimeType: mime,
      );
      draft.validate();
      drafts.add(draft);
    }
    return drafts;
  }

  Future<void> _pickImages() async {
    if (!_canComment || _sending || _picking || _images.length >= 3) return;
    final generation = _generation;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final remaining = 3 - _images.length;
      final selected = await (widget.imagePicker ?? _defaultPick)(remaining);
      if (!_current(generation)) return;
      if (selected.length > remaining) {
        throw FormatException(_l.commentImageLimit);
      }
      for (final image in selected) {
        if (image.bytes.length > CommunityCommentImageDraft.maxBytes) {
          throw FormatException(_l.commentImageTooLarge);
        }
        image.validate();
      }
      if (selected.isEmpty) {
        setState(() => _picking = false);
      } else {
        _changed(() {
          _images.addAll(selected);
          _picking = false;
        });
      }
    } catch (error) {
      if (!_current(generation)) return;
      setState(() {
        _picking = false;
        _error = error is FormatException
            ? error.message
            : _l.commentImageAddFailed;
      });
    }
  }

  Future<void> _like(CommunityComment comment) async {
    if (widget.currentUserId == null || _busyComments.contains(comment.id)) {
      return;
    }
    final generation = _generation;
    ++_loadToken;
    setState(() {
      _loading = false;
      _busyComments.add(comment.id);
    });
    try {
      final updated = await widget.repository.setLiked(
        widget.workId,
        comment.id,
        !comment.likedByMe,
      );
      if (!_current(generation)) return;
      if (updated.id != comment.id ||
          updated.workId != widget.workId ||
          !updated.published) {
        throw const FormatException();
      }
      setState(() {
        _comments = _comments
            .map((c) => c.id == updated.id ? updated : c)
            .toList();
      });
      _notifyVisible();
    } catch (error) {
      if (!_current(generation) || _clearInvalidIdentity(error)) return;
      setState(() => _error = _l.commentLikeFailed);
    } finally {
      if (_current(generation)) {
        setState(() => _busyComments.remove(comment.id));
      }
    }
  }

  Future<void> _remove(CommunityComment comment) async {
    if (_busyComments.contains(comment.id)) return;
    final generation = _generation;
    ++_loadToken;
    setState(() {
      _loading = false;
      _busyComments.add(comment.id);
    });
    try {
      await widget.repository.remove(widget.workId, comment.id);
      if (!_current(generation)) return;
      setState(() {
        _comments.removeWhere((c) => c.id == comment.id);
        if (comment.published && _publicCount > 0) _publicCount--;
        if (_reply?.id == comment.id) _reply = null;
      });
      _notifyVisible();
    } catch (error) {
      if (!_current(generation) || _clearInvalidIdentity(error)) return;
      setState(() => _error = _l.commentDeleteFailed);
    } finally {
      if (_current(generation)) {
        setState(() => _busyComments.remove(comment.id));
      }
    }
  }

  void _edit(CommunityComment comment) {
    if (_sending || _hasDraft) {
      setState(() => _error = _l.commentEditDraftFirst);
      return;
    }
    _text.text = comment.body;
    _changed(() {
      _reply = comment.parentId == null
          ? null
          : _comments.where((c) => c.id == comment.parentId).firstOrNull;
      _anchor = comment.anchor;
    });
    if (comment.attachments.isNotEmpty) {
      setState(() => _error = _l.commentReselectImages);
    }
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _generation++;
    _reportRevision.value++;
    _reportRevision.dispose();
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _text.removeListener(_textChanged);
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !widget.presentationVisible
      ? const SizedBox.shrink()
      : ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AetherRadii.lg),
          ),
          child: Material(
            color: AetherColors.bgCanvas,
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Column(
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        width: 32,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AetherColors.borderStrong,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 20, right: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _l.commentCount(_publicCount),
                                style: AetherTextStyles.h3,
                              ),
                            ),
                            IconButton(
                              tooltip: _l.commentRefresh,
                              onPressed:
                                  _loading ||
                                      _refreshing ||
                                      _inflightLoadToken != null ||
                                      _sending ||
                                      _busyComments.isNotEmpty
                                  ? null
                                  : _manualRefresh,
                              icon: _refreshing
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.refresh_rounded, size: 20),
                            ),
                            IconButton(
                              tooltip: _l.commentClose,
                              onPressed: widget.onClose,
                              icon: const Icon(Icons.close_rounded, size: 20),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: AetherColors.border),
                      Expanded(child: _list()),
                      const Divider(height: 1, color: AetherColors.border),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: (constraints.maxHeight - 96).clamp(
                            0,
                            double.infinity,
                          ),
                        ),
                        child: SingleChildScrollView(child: _composer()),
                      ),
                    ],
                  ),
                  if (_previewAttachment != null)
                    Positioned.fill(child: _imagePreview()),
                ],
              ),
            ),
          ),
        );

  // The server applies this order to the complete visible set before paging.
  // Keep local mutations in the same order while preserving the server cursor.
  List<CommunityComment> _ranked(Iterable<CommunityComment> comments) =>
      comments.toList()..sort(compareCommunityComments);

  Widget _list() {
    if (_visibilityError != null) {
      return Center(
        child: TextButton(
          onPressed: _loadVisibility,
          child: Text(_visibilityError!),
        ),
      );
    }
    if (!_visibilityLoaded) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_loading && _comments.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AetherColors.primary,
          ),
        ),
      );
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _loadError!,
                style: AetherTextStyles.bodySm,
                textAlign: TextAlign.center,
              ),
              TextButton(onPressed: _load, child: Text(_l.commentReload)),
            ],
          ),
        ),
      );
    }
    if (_paged) {
      return SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: _section(CommunityCommentSection.hot),
      );
    }
    if (_comments.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            _l.commentEmpty,
            style: AetherTextStyles.bodySm,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final rows = _ranked(_comments);
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 20),
      itemBuilder: (_, index) => _comment(rows[index]),
    );
  }

  Widget _section(CommunityCommentSection section) {
    final ids = _sectionIds[section] ?? const <String>[];
    final rows = _ranked(
      ids
          .map((id) => _comments.where((c) => c.id == id).firstOrNull)
          .whereType<CommunityComment>(),
    );
    final busy = _sectionBusy.containsKey(section);
    final error = _sectionErrors[section];
    return Column(
      key: ValueKey('comment-section-${section.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: _comment(row),
          ),
        if (!busy && error == null && rows.isEmpty)
          Text(_l.commentEmpty, style: AetherTextStyles.caption),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        if (error != null) Text(error, style: AetherTextStyles.caption),
        if (error != null || _sectionCursors[section] != null)
          TextButton(
            key: ValueKey('comment-more-${section.name}'),
            onPressed: busy ? null : () => _loadSection(section),
            child: Text(
              error != null
                  ? _l.commentReload
                  : (_l.localeName.startsWith('zh')
                        ? '加载更多评论'
                        : 'Load more comments'),
            ),
          ),
      ],
    );
  }

  Widget _comment(CommunityComment comment) {
    final mine = comment.userId == widget.currentUserId;
    final hidden = comment.status == CommunityCommentStatus.hidden;
    final personalHidden = _hiddenCommentIds.contains(comment.id);
    final parent =
        _comments.where((c) => c.id == comment.parentId).firstOrNull ??
        _parentComments[comment.parentId];
    final privateLabel = switch (comment.status) {
      CommunityCommentStatus.pending ||
      CommunityCommentStatus.review => _l.commentPrivatePending,
      CommunityCommentStatus.rejected => _l.commentPrivateRejected,
      CommunityCommentStatus.error => _l.commentPrivateError,
      _ => null,
    };
    final isReply = comment.parentId != null;
    return Padding(
      padding: EdgeInsets.only(left: isReply ? 42 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: isReply ? 12 : 16,
            backgroundColor: AetherColors.bgElevated,
            foregroundColor: AetherColors.textSecondary,
            foregroundImage: comment.authorAvatarUrl == null
                ? null
                : NetworkImage(comment.authorAvatarUrl!),
            onForegroundImageError: comment.authorAvatarUrl == null
                ? null
                : (_, _) {},
            child: Icon(Icons.person_outline_rounded, size: isReply ? 15 : 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        currentAuthorName(
                          context,
                          comment.userId,
                          comment.authorName,
                        ),
                        style: AetherTextStyles.bodySm.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!hidden &&
                        widget.workAuthorId != null &&
                        widget.workAuthorId!.trim().isNotEmpty &&
                        comment.userId == widget.workAuthorId)
                      Container(
                        key: ValueKey('author-reply-${comment.id}'),
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Center(
                          widthFactor: 1,
                          heightFactor: 1,
                          child: Text(
                            _l.localeName.startsWith('zh') ? '作者' : 'Author',
                            textAlign: TextAlign.center,
                            textHeightBehavior: const TextHeightBehavior(
                              applyHeightToFirstAscent: false,
                              applyHeightToLastDescent: false,
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    if (mine)
                      Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Text(
                          _l.commentMe,
                          style: AetherTextStyles.caption,
                        ),
                      ),
                  ],
                ),
                if (!hidden && !personalHidden && comment.parentId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      _l.commentReplyTo(
                        parent == null
                            ? _l.commentReplyFallback
                            : currentAuthorName(
                                context,
                                parent.userId,
                                parent.authorName,
                              ),
                      ),
                      style: AetherTextStyles.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (hidden) ...[
                  Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(_l.commentHidden, style: AetherTextStyles.body),
                  ),
                  if (comment.moderationReason != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        comment.moderationReason!,
                        style: AetherTextStyles.caption,
                      ),
                    ),
                  if (comment.moderationCaseId != null &&
                      widget.onModerationCaseSelected != null)
                    TextButton(
                      onPressed: () => widget.onModerationCaseSelected!(
                        comment.moderationCaseId!,
                      ),
                      child: Text(_l.commentViewReasonAppeal),
                    ),
                ],
                if (!hidden && personalHidden)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _chinese ? '该评论已隐藏' : 'This comment is hidden',
                      style: AetherTextStyles.body.copyWith(
                        color: AetherColors.textSecondary,
                      ),
                    ),
                  ),
                if (!hidden && !personalHidden && comment.body.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(comment.body, style: AetherTextStyles.body),
                  ),
                if (!hidden &&
                    !personalHidden &&
                    comment.attachments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var i = 0; i < comment.attachments.length; i++)
                          _attachment(comment, comment.attachments[i], i),
                      ],
                    ),
                  ),
                if (!hidden && !personalHidden && comment.anchor != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 36),
                      foregroundColor: AetherColors.primary,
                    ),
                    onPressed: () => widget.onCommentSelected?.call(comment),
                    icon: const Icon(Icons.location_on_outlined, size: 15),
                    label: Text(
                      _l.commentViewPoint,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                if (privateLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        privateLabel,
                        style: AetherTextStyles.caption.copyWith(
                          color:
                              comment.status == CommunityCommentStatus.rejected
                              ? AetherColors.danger
                              : AetherColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                Wrap(
                  spacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _date(comment.createdAt),
                      style: AetherTextStyles.caption,
                    ),
                    if (comment.published && !personalHidden && _canComment)
                      _textAction(_l.commentReply, () {
                        _changed(() => _reply = comment);
                        _focus.requestFocus();
                      }),
                    if (comment.published &&
                        !personalHidden &&
                        !mine &&
                        widget.currentUserId != null &&
                        widget.repository is CommunityCommentReportRepository)
                      _textAction(
                        _l.reportAction,
                        () => _reportComment(comment),
                      ),
                    if (comment.published)
                      InkWell(
                        onTap:
                            _busyComments.contains(comment.id) ||
                                widget.currentUserId == null
                            ? null
                            : () => _like(comment),
                        borderRadius: BorderRadius.circular(12),
                        child: Semantics(
                          label: comment.likedByMe
                              ? _l.commentUnlikeCount(comment.likesCount)
                              : _l.commentLikeCount(comment.likesCount),
                          button: true,
                          enabled:
                              !_busyComments.contains(comment.id) &&
                              widget.currentUserId != null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  comment.likedByMe
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  size: 16,
                                  color:
                                      _busyComments.contains(comment.id) ||
                                          widget.currentUserId == null
                                      ? AetherColors.textSecondary.withValues(
                                          alpha: .4,
                                        )
                                      : comment.likedByMe
                                      ? AetherColors.danger
                                      : AetherColors.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${comment.likesCount}',
                                  style: AetherTextStyles.caption,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (comment.published)
                      IconButton(
                        key: ValueKey('comment-dislike-${comment.id}'),
                        tooltip: personalHidden
                            ? (_chinese ? '恢复此评论' : 'Show this comment')
                            : (_chinese
                                  ? '不喜欢，仅对您隐藏'
                                  : 'Dislike, hide for you'),
                        onPressed: _busyComments.contains(comment.id)
                            ? null
                            : () => _setCommentHidden(comment, !personalHidden),
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 36,
                        ),
                        icon: Icon(
                          personalHidden
                              ? Icons.heart_broken
                              : Icons.heart_broken_outlined,
                          size: 15,
                        ),
                        color: AetherColors.textSecondary,
                      ),
                    if (mine &&
                        (comment.status == CommunityCommentStatus.rejected ||
                            comment.status == CommunityCommentStatus.error))
                      _textAction(_l.commentEditResend, () => _edit(comment)),
                    if (mine)
                      _textAction(
                        _l.meActionDelete,
                        _busyComments.contains(comment.id)
                            ? null
                            : () => _remove(comment),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reportComment(CommunityComment comment) async {
    final repository = widget.repository;
    if (repository is! CommunityCommentReportRepository) return;
    final generation = _generation;
    bool current() =>
        _current(generation) &&
        widget.currentUserId != null &&
        comment.userId != widget.currentUserId &&
        _comments.any(
          (c) => c.id == comment.id && c.workId == widget.workId && c.published,
        );
    if (!current()) return;
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CommunityCommentReportSheet(
        workId: widget.workId,
        commentId: comment.id,
        revision: _reportRevision,
        isCurrent: current,
        submit: (draft) =>
            (repository as CommunityCommentReportRepository).report(draft),
      ),
    );
    if (!mounted || !current() || id == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppL10n.of(context).reportSubmitted)),
    );
  }

  Widget _textAction(String label, VoidCallback? action) => InkWell(
    onTap: action,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        label,
        style: AetherTextStyles.caption.copyWith(
          color: AetherColors.textSecondary,
        ),
      ),
    ),
  );

  Widget _attachment(
    CommunityComment comment,
    CommunityCommentAttachment attachment,
    int index,
  ) => Semantics(
    label: _l.commentImageNumber(index + 1),
    button: true,
    child: InkWell(
      onTap: () => setState(() {
        _previewAttachment = attachment;
        _previewCommentId = comment.id;
      }),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          attachment.url,
          width: 68,
          height: 68,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            width: 68,
            height: 68,
            color: AetherColors.bgElevated,
            child: const Icon(
              Icons.broken_image_outlined,
              color: AetherColors.textTertiary,
            ),
          ),
        ),
      ),
    ),
  );

  // Stay inside the panel: switching identities also removes a private preview.
  Widget _imagePreview() => Semantics(
    scopesRoute: true,
    explicitChildNodes: true,
    namesRoute: true,
    label: _l.commentImagePreview,
    child: Material(
      color: AetherColors.bgCanvas,
      child: Column(
        children: [
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              tooltip: _l.commentCloseImage,
              onPressed: () => setState(() {
                _previewAttachment = null;
                _previewCommentId = null;
              }),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
          Expanded(
            child: Center(
              child: InteractiveViewer(
                child: Image.network(
                  _previewAttachment!.url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(_l.commentImageLoadFailed),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  String _date(DateTime value) =>
      formatCommunityCommentTime(value, locale: _l.localeName);

  Widget _composer() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_reply != null || _anchor != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (_reply != null)
                    _chip(
                      _l.commentReplyTo(
                        currentAuthorName(
                          context,
                          _reply!.userId,
                          _reply!.authorName,
                        ),
                      ),
                      _l.commentCancelReply,
                      () => _changed(() => _reply = null),
                      Icons.reply_rounded,
                    ),
                  if (_anchor != null)
                    _chip(_l.commentPointSelected, _l.commentRemovePoint, () {
                      _changed(() => _anchor = null);
                      widget.onClearAnchor?.call();
                    }, Icons.location_on_outlined),
                ],
              ),
            ),
          if (_images.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                spacing: 6,
                children: [
                  for (var i = 0; i < _images.length; i++)
                    SizedBox(
                      width: 62,
                      height: 62,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                _images[i].bytes,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const ColoredBox(
                                  color: AetherColors.bgElevated,
                                  child: Icon(Icons.image_outlined),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: IconButton(
                                style: IconButton.styleFrom(
                                  backgroundColor: AetherColors.bgCanvas,
                                ),
                                tooltip: _l.commentRemoveImage(i + 1),
                                padding: EdgeInsets.zero,
                                iconSize: 16,
                                onPressed: _sending
                                    ? null
                                    : () => _changed(() => _images.removeAt(i)),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: AetherTextStyles.caption.copyWith(
                    color: AetherColors.danger,
                  ),
                ),
              ),
            ),
          if (widget.currentUserId == null && widget.onSignIn != null)
            TextButton(
              onPressed: widget.onSignIn,
              child: Text(_l.commentSignIn),
            ),
          TextField(
            key: const Key('comment-input'),
            controller: _text,
            focusNode: _focus,
            enabled: _canComment && !_sending,
            minLines: 1,
            maxLines: 3,
            style: AetherTextStyles.body,
            decoration: InputDecoration(
              hintText: widget.currentUserId == null
                  ? _l.commentSignIn
                  : _page == null
                  ? _l.commentServiceUnavailable
                  : !_canComment
                  ? _l.commentUnavailable
                  : _l.commentComposerHint,
              counterText: '',
              filled: true,
              fillColor: AetherColors.bgElevated,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          SizedBox(
            height: 42,
            child: Row(
              children: [
                IconButton(
                  tooltip: _l.commentAddEmoji,
                  onPressed: !_canComment || _sending
                      ? null
                      : () => setState(() => _emojiOpen = !_emojiOpen),
                  icon: const Icon(
                    Icons.sentiment_satisfied_alt_outlined,
                    size: 22,
                  ),
                ),
                IconButton(
                  tooltip: _l.commentAddImage,
                  onPressed:
                      !_canComment ||
                          _sending ||
                          _picking ||
                          _images.length >= 3
                      ? null
                      : _pickImages,
                  icon: _picking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AetherColors.primary,
                          ),
                        )
                      : const Icon(Icons.image_outlined, size: 22),
                ),
                IconButton(
                  tooltip: _l.commentSelectPoint,
                  onPressed: !_canComment || _sending
                      ? null
                      : widget.onPickPoint,
                  icon: const Icon(Icons.add_location_alt_outlined, size: 22),
                ),
                const Spacer(),
                SizedBox(
                  height: 34,
                  child: FilledButton(
                    key: const Key('comment-send'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AetherColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      minimumSize: const Size(62, 34),
                    ),
                    onPressed:
                        _canComment &&
                            _hasDraft &&
                            _withinTextLimit &&
                            !_sending &&
                            !_picking
                        ? _send
                        : null,
                    child: _sending
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _l.commentSend,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          if (_emojiOpen)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final emoji in const [
                    '🙂',
                    '❤️',
                    '👏',
                    '👍',
                    '✨',
                    '😍',
                    '🤔',
                    '🎉',
                  ])
                    TextButton(
                      onPressed: _sending
                          ? null
                          : () {
                              final selection = _text.selection;
                              final start = selection.isValid
                                  ? selection.start
                                  : _text.text.length;
                              final end = selection.isValid
                                  ? selection.end
                                  : _text.text.length;
                              final text = _text.text.replaceRange(
                                start,
                                end,
                                emoji,
                              );
                              if (CommunityCommentDraft.allowsText(text)) {
                                _text.value = TextEditingValue(
                                  text: text,
                                  selection: TextSelection.collapsed(
                                    offset: start + emoji.length,
                                  ),
                                );
                              }
                            },
                      child: Text(emoji, style: const TextStyle(fontSize: 22)),
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Widget _chip(
    String label,
    String tooltip,
    VoidCallback remove,
    IconData icon,
  ) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 280),
    child: Container(
      decoration: BoxDecoration(
        color: AetherColors.bgElevated,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AetherColors.textSecondary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: AetherTextStyles.caption.copyWith(
                color: AetherColors.textSecondary,
              ),
            ),
          ),
          SizedBox(
            width: 30,
            height: 30,
            child: IconButton(
              tooltip: tooltip,
              padding: EdgeInsets.zero,
              iconSize: 14,
              onPressed: _sending ? null : remove,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ),
    ),
  );
}
