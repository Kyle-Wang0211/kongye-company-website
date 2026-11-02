import 'dart:async';

import 'package:flutter/material.dart';

import '../../../community/comments/comment_moderation_models.dart';
import '../../../community/comments/comment_moderation_repository.dart';
import '../../design_system.dart';
import 'community_comment_case_page.dart';
import 'moderation_ui_support.dart';

typedef _InboxIdentity = ({
  CommunityCommentModerationRepository repository,
  String? userId,
  String? key,
});

class CommunityCommentInboxPage extends StatefulWidget {
  const CommunityCommentInboxPage({
    super.key,
    required this.repository,
    required this.currentUserId,
    this.identityKey,
    this.refreshInterval = const Duration(seconds: 30),
  });
  final CommunityCommentModerationRepository repository;
  final String? currentUserId;
  final String? identityKey;
  final Duration? refreshInterval;

  @override
  State<CommunityCommentInboxPage> createState() =>
      _CommunityCommentInboxPageState();
}

class _CommunityCommentInboxPageState extends State<CommunityCommentInboxPage>
    with
        WidgetsBindingObserver,
        ActiveModerationRefresh<CommunityCommentInboxPage> {
  List<CommunityCommentNotice>? _notices;
  final Set<String> _acknowledgedRead = {};
  final Set<String> _markingRead = {};
  late final ValueNotifier<_InboxIdentity> _identity;
  String? _error;
  int _generation = 0;
  bool _loading = false;
  bool _opening = false;
  bool get _signedIn => widget.currentUserId?.isNotEmpty ?? false;
  _InboxIdentity get _currentIdentity => (
    repository: widget.repository,
    userId: widget.currentUserId,
    key: widget.identityKey,
  );

  @override
  void initState() {
    super.initState();
    _identity = ValueNotifier(_currentIdentity);
    startModerationRefresh(widget.refreshInterval);
    _load();
  }

  @override
  void didUpdateWidget(covariant CommunityCommentInboxPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.currentUserId != widget.currentUserId ||
        oldWidget.identityKey != widget.identityKey) {
      _generation++;
      _notices = null;
      _error = null;
      _loading = false;
      _acknowledgedRead.clear();
      _markingRead.clear();
      // A pushed route has its own lifetime: forward identity invalidation there.
      final generation = _generation;
      scheduleMicrotask(() {
        if (mounted && generation == _generation) {
          _identity.value = _currentIdentity;
        }
      });
      _load();
    }
    if (oldWidget.refreshInterval != widget.refreshInterval) {
      stopModerationRefresh();
      startModerationRefresh(widget.refreshInterval);
    }
  }

  @override
  void refreshModeration() => _load();

  Future<void> _load() async {
    if (!_signedIn || _loading) return;
    final generation = _generation;
    setState(() {
      _loading = true;
    });
    try {
      final rows = await widget.repository.fetchNotices();
      if (!mounted || generation != _generation) return;
      if (rows.any((row) => row.recipientId != widget.currentUserId)) {
        throw const FormatException('Notice ownership mismatch');
      }
      setState(() {
        _notices = rows;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _notices = null;
        _error = moderationError(error);
      });
      if (moderationIdentityChanged(error)) {
        _acknowledgedRead.clear();
        _identity.value = (
          repository: widget.repository,
          userId: null,
          key: widget.identityKey,
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _markRead(CommunityCommentNotice notice) async {
    if (notice.readAt != null ||
        _acknowledgedRead.contains(notice.id) ||
        !_markingRead.add(notice.id)) {
      return;
    }
    final generation = _generation;
    try {
      await widget.repository.markRead(notice.id);
      if (mounted && generation == _generation) {
        setState(() {
          _acknowledgedRead.add(notice.id);
        });
      }
    } catch (error) {
      // Reading the case remains available even if the read receipt fails.
      if (mounted &&
          generation == _generation &&
          moderationIdentityChanged(error)) {
        setState(() {
          _notices = null;
          _error = moderationError(error);
        });
        _identity.value = (
          repository: widget.repository,
          userId: null,
          key: widget.identityKey,
        );
      }
    } finally {
      if (generation == _generation) _markingRead.remove(notice.id);
    }
  }

  Future<void> _open(CommunityCommentNotice notice) async {
    if (_opening || !_signedIn) return;
    _opening = true;
    unawaited(_markRead(notice));
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ValueListenableBuilder<_InboxIdentity>(
            valueListenable: _identity,
            builder: (_, identity, _) => CommunityCommentCasePage(
              caseId: notice.caseId,
              repository: identity.repository,
              currentUserId: identity.userId,
              identityKey: identity.key,
              refreshInterval: widget.refreshInterval,
            ),
          ),
        ),
      );
    } finally {
      _opening = false;
      if (mounted && moderationPageActive) _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    stopModerationRefresh();
    // The route is normally removed together with its inbox owner.
    _identity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notices = _notices;
    return Scaffold(
      backgroundColor: AetherColors.bgCanvas,
      appBar: AppBar(
        title: const Text('系统收件箱'),
        backgroundColor: AetherColors.bgCanvas,
        foregroundColor: AetherColors.textPrimary,
        actions: [
          IconButton(
            tooltip: '刷新通知',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: !_signedIn
          ? const ModerationMessage(message: '请登录后查看审核通知')
          : _error != null
          ? ModerationMessage(message: _error!, retry: _load)
          : notices == null
          ? const Center(
              child: CircularProgressIndicator(color: AetherColors.primary),
            )
          : RefreshIndicator(
              color: AetherColors.primary,
              onRefresh: _load,
              child: notices.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        ModerationMessage(message: '暂无审核通知'),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AetherSpacing.lg,
                        vertical: AetherSpacing.sm,
                      ),
                      itemCount: notices.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: AetherColors.border),
                      itemBuilder: (_, index) => _noticeTile(notices[index]),
                    ),
            ),
    );
  }

  Widget _noticeTile(CommunityCommentNotice notice) {
    final unread =
        notice.readAt == null && !_acknowledgedRead.contains(notice.id);
    final title = switch (notice.kind) {
      CommunityCommentNoticeKind.hidden => '评论已隐藏',
      CommunityCommentNoticeKind.restored => '评论已恢复',
      CommunityCommentNoticeKind.appealRejected => '申诉未通过',
    };
    final icon = switch (notice.kind) {
      CommunityCommentNoticeKind.hidden => Icons.visibility_off_outlined,
      CommunityCommentNoticeKind.restored => Icons.visibility_outlined,
      CommunityCommentNoticeKind.appealRejected => Icons.assignment_outlined,
    };
    return InkWell(
      key: Key('notice-${notice.id}'),
      onTap: () => _open(notice),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AetherSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: AetherColors.primary),
            const SizedBox(width: AetherSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(title, style: AetherTextStyles.h3)),
                      if (unread)
                        Semantics(
                          key: Key('notice-unread-${notice.id}'),
                          container: true,
                          label: '未读',
                          child: const Icon(
                            Icons.circle,
                            size: 7,
                            color: AetherColors.primary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AetherSpacing.sm),
                  Text(notice.reasonText, style: AetherTextStyles.body),
                  const SizedBox(height: AetherSpacing.sm),
                  Text(
                    notice.workTitle ?? '相关作品中的评论',
                    style: AetherTextStyles.bodySm,
                  ),
                  if (notice.commentPreview?.isNotEmpty ?? false)
                    Text(
                      notice.commentPreview!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AetherTextStyles.bodySm,
                    ),
                  const SizedBox(height: AetherSpacing.sm),
                  Text(
                    moderationDate(notice.createdAt),
                    style: AetherTextStyles.caption,
                  ),
                  const SizedBox(height: AetherSpacing.sm),
                  const Text('查看处理详情', style: AetherTextStyles.bodySm),
                ],
              ),
            ),
            const SizedBox(width: AetherSpacing.sm),
            const Icon(
              Icons.chevron_right,
              color: AetherColors.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
