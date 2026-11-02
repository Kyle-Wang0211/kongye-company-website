// WorkDetailPage — full-screen viewer for a single community work.
//
// Pushed when the user taps a card in the community feed.
//
// ── 2026-08-16 rewrite: point cloud, not GLB ─────────────────────────
//
// This page used to render through AetherCppCardDemo → SceneBridge →
// the aether_cpp scene renderer, because community works were GLB. The
// official capture route ships a sparse point cloud
// (official_sfm_sparse.ply), and the app already has a mature, shipped
// renderer for exactly that: SparseCloudView — the same widget behind
// the capture-time preview overlay and the drafts "查看点云" page. Using
// it here means a work looks identical whether you are looking at your
// own draft or someone else's published scan, and it inherits the point
// size / AgX / exposure controls and octree LOD that were tuned against
// our own clouds.
//
// We embed the VIEW, not SparseCloudViewerPage: that page carries the
// selection-box editing tools and persists a box to disk beside the PLY,
// which is meaningless (and wrong) for a visitor looking at someone
// else's work.
//
// Load path: modelStoragePath → public URL → GlbCache.fetchPath (two-tier
// URL→disk cache, already PLY-aware) → loadSparsePly in a `compute`
// isolate so parsing 100K+ points never blocks the frame.
//
// The Phase 6.4f.10 first-viewer ThumbBaker hook is gone: PublishService
// now uploads the local `official_sparse_thumb.png` at publish time, so
// a work has its thumbnail from the moment it appears in the feed.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';

import '../../community/community_service.dart';
import '../../community/comments/comment_models.dart';
import '../../community/comments/comment_repository.dart';
import '../../community/comments/comment_moderation_repository.dart';
import '../../config/endpoint_config.dart';
import '../../community/feed_models.dart';
import '../../community/glb_cache.dart';
import '../../community/social_profile_models.dart';
import '../../community/social_profile_repository.dart';
import '../../community/thumb_baker.dart';
import '../../l10n/app_localizations.dart';
import '../design_system.dart';
import 'aether_cpp_card_demo.dart';
import 'comments/community_comments_panel.dart';
import 'comment_moderation_routes.dart';
import 'user_report_page.dart';
import 'viewer_impl.dart' show ViewerQuality;
import '../shared/product_model_view.dart';
import '../shared/community_viewer_session.dart';
import '../official_capture/auto_rotating_cloud_view.dart';
import '../official_capture/community_sparse_cloud_data.dart'
    show SparseCloudData, loadSparsePly;

/// [mesh] = GLB/mesh,走五月就跑通的 aether_cpp scene renderer(自带自转 +
/// bounds 驱动取景),它自己从 URL 加载,不经 loadSparsePly。
/// [ready] = 稀疏点云,走 SparseCloudView。
enum _CloudStatus { loading, ready, mesh, unsupported, failed }

class WorkDetailPage extends StatefulWidget {
  final FeedWork work;
  final CommunityService service;
  final SocialProfileRepository? reportRepository;
  final ValueChanged<FeedWork>? onWorkUpdated;
  final CommunityCommentRepository? commentRepository;
  final CommunityViewerSessions? communitySessions;
  final CommunityCommentModerationRepository? commentModerationRepository;
  @visibleForTesting
  final CommunityCommentImagePicker? commentImagePicker;
  @visibleForTesting
  // Forward the shared renderer test seam without exposing a production host.
  // ignore: invalid_use_of_visible_for_testing_member
  final ProductModelHostBuilder? viewerHostBuilder;
  @visibleForTesting
  final Future<String> Function(String)? resolveModelPath;

  final VoidCallback? onSignIn;

  const WorkDetailPage({
    super.key,
    required this.work,
    required this.service,
    this.reportRepository,
    this.onSignIn,
    this.onWorkUpdated,
    this.commentRepository,
    this.communitySessions,
    this.commentModerationRepository,
    this.commentImagePicker,
    this.viewerHostBuilder,
    this.resolveModelPath,
  });

  @override
  State<WorkDetailPage> createState() => _WorkDetailPageState();
}

class _WorkDetailPageState extends State<WorkDetailPage> {
  bool _commentsOpen = false;
  bool _commentsEnabled = false;
  bool _commentsEverOpened = false;
  SharedSurfaceMarkerLayout? _commentLayout;
  String? _dismissedLayoutId;
  String? _selectedCommentId;
  // Spatial cards render in the shared viewer. The full Flutter list is
  // presented only through its explicit all-comments entry.
  bool get _floatingCommentsVisible => !_selectingCommentPoint && _commentsOpen;

  void _onCommentLayout(SharedSurfaceMarkerLayout? layout) {
    if (!mounted || !_commentsEnabled || _surfaceAssetSha256 == null) return;
    if (layout != null &&
        !_visibleComments.any(
          (c) =>
              c.id == layout.id &&
              c.workId == widget.work.id &&
              c.anchor != null &&
              c.status != CommunityCommentStatus.hidden &&
              c.status != CommunityCommentStatus.removed &&
              c.visibleTo(widget.service.currentUserId),
        )) {
      return;
    }
    setState(() {
      _commentLayout = layout;
      if (layout == null ||
          !layout.expanded ||
          layout.id != _dismissedLayoutId) {
        _dismissedLayoutId = null;
      }
    });
  }

  bool _selectingCommentPoint = false;
  CommunityCommentAnchor? _commentAnchor;
  ProductViewerCapture? _surfaceViewer;
  String? _surfaceAssetSha256;
  List<CommunityComment> _visibleComments = const [];
  late CommunityCommentRepository _commentRepository =
      widget.commentRepository ?? SupabaseCommunityCommentRepository();
  StreamSubscription<AuthState>? _commentAuth;
  int _commentIdentityEpoch = 0;
  String? _lastCommentUser;
  bool get _supportsSurfaceComments =>
      widget.work.format.toLowerCase() == 'glb';
  String get _commentPartition =>
      '${widget.work.id}:${widget.work.modelStoragePath}:${widget.service.currentUserId}:'
      '${EndpointConfigResolver.current?.deployment.namespace}:'
      '${EndpointConfigResolver.current?.supabaseUrl}:$_commentIdentityEpoch';

  void _showComments() {
    setState(() {
      _commentsEverOpened = true;
      _commentsEnabled = true;
      _commentsOpen = true;
      _dismissedLayoutId = null;
    });
    unawaited(_syncCommentMarkers());
  }

  void _toggleComments() {
    setState(() {
      _commentsEnabled = !_commentsEnabled;
      if (_commentsEnabled) _commentsEverOpened = true;
      if (!_commentsEnabled) {
        _selectingCommentPoint = false;
        _commentsOpen = false;
        _commentLayout = null;
        _dismissedLayoutId = null;
        _selectedCommentId = null;
      }
    });
    if (!_commentsEnabled) {
      FocusScope.of(context).unfocus();
      unawaited(_setPicking(false));
    }
    unawaited(_syncCommentMarkers());
  }

  void _onSurfaceMarkerSelected(String id) {
    if (!_commentsEnabled) return;
    final comment = _visibleComments
        .where(
          (comment) =>
              comment.id == id &&
              comment.workId == widget.work.id &&
              comment.anchor != null &&
              comment.status != CommunityCommentStatus.hidden &&
              comment.status != CommunityCommentStatus.removed &&
              comment.visibleTo(widget.service.currentUserId),
        )
        .firstOrNull;
    if (!mounted || _surfaceAssetSha256 == null || comment == null) return;
    setState(() => _selectedCommentId = comment.id);
    unawaited(_syncCommentMarkers());
  }

  void _closeComments() {
    FocusScope.of(context).unfocus();
    setState(() {
      _commentsOpen = false;
      _dismissedLayoutId = _commentLayout?.id;
      _selectingCommentPoint = false;
    });
    unawaited(_setPicking(false));
  }

  Future<void> _setPicking(bool enabled) async {
    try {
      await _surfaceViewer?.setSurfaceCommentMode(enabled);
    } catch (_) {
      if (mounted && enabled) {
        setState(() => _selectingCommentPoint = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('点位选择暂不可用，请稍后重试')));
      }
    }
  }

  void _pickCommentPoint() {
    FocusScope.of(context).unfocus();
    setState(() {
      _selectingCommentPoint = !_selectingCommentPoint;
      if (_selectingCommentPoint) _commentsOpen = true;
    });
    unawaited(_setPicking(_selectingCommentPoint));
  }

  void _onSurfacePicked(SharedSurfaceAnchor anchor) {
    if (!mounted ||
        _surfaceAssetSha256 == null ||
        !_commentsOpen ||
        !_selectingCommentPoint) {
      return;
    }
    setState(() {
      _commentAnchor = CommunityCommentAnchor(
        position: anchor.position,
        normal: anchor.normal,
        cameraPosition: anchor.cameraPosition,
        cameraTarget: anchor.cameraTarget,
      );
      _selectingCommentPoint = false;
    });
    unawaited(_setPicking(false));
  }

  SharedSurfaceAnchor _sharedAnchor(CommunityCommentAnchor anchor) =>
      SharedSurfaceAnchor(
        position: anchor.position,
        normal: anchor.normal,
        cameraPosition: anchor.cameraPosition,
        cameraTarget: anchor.cameraTarget,
      );
  void _commentsChanged(List<CommunityComment> comments) {
    if (!mounted) return;
    _visibleComments =
        (_surfaceAssetSha256 == null ? <CommunityComment>[] : comments)
            .where(
              (c) =>
                  c.workId == widget.work.id &&
                  c.visibleTo(widget.service.currentUserId),
            )
            .toList();
    if (_commentLayout != null &&
        !_visibleComments.any(
          (c) =>
              c.id == _commentLayout!.id &&
              c.status != CommunityCommentStatus.hidden &&
              c.status != CommunityCommentStatus.removed,
        )) {
      setState(() {
        _commentLayout = null;
        _dismissedLayoutId = null;
      });
    }
    if (_selectedCommentId != null &&
        !_visibleComments.any(
          (c) =>
              c.id == _selectedCommentId &&
              c.anchor != null &&
              c.status != CommunityCommentStatus.hidden &&
              c.status != CommunityCommentStatus.removed,
        )) {
      _selectedCommentId = null;
    }
    unawaited(_syncCommentMarkers());
  }

  Future<void> _syncCommentMarkers() async {
    final markers = <SharedSurfaceMarker>[];
    for (final comment
        in !_commentsEnabled || _surfaceAssetSha256 == null
            ? <CommunityComment>[]
            : _visibleComments) {
      if (markers.length == 256) break;
      if (!comment.visibleTo(widget.service.currentUserId) ||
          comment.status == CommunityCommentStatus.removed ||
          comment.status == CommunityCommentStatus.hidden ||
          comment.anchor == null) {
        continue;
      }
      try {
        markers.add(
          SharedSurfaceMarker(
            id: comment.id,
            anchor: _sharedAnchor(comment.anchor!),
            number: markers.length + 1,
            selected: comment.id == _selectedCommentId,
            previewText: comment.body,
            previewImages: comment.attachments
                .map((image) => image.url)
                .toList(),
          ),
        );
      } on ArgumentError {
        /* Invalid remote anchors never reach the renderer. */
      }
    }
    try {
      await _surfaceViewer?.setSurfaceCommentMarkers(markers);
    } catch (_) {
      /* Model can be leaving while a private comment request completes. */
    }
  }

  void _focusComment(CommunityComment comment) {
    final anchor = comment.anchor;
    if (_surfaceAssetSha256 == null ||
        anchor == null ||
        comment.workId != widget.work.id ||
        !comment.visibleTo(widget.service.currentUserId) ||
        comment.status == CommunityCommentStatus.hidden ||
        comment.status == CommunityCommentStatus.removed) {
      return;
    }
    setState(() => _selectedCommentId = comment.id);
    unawaited(_syncCommentMarkers());
    try {
      unawaited(
        _surfaceViewer
            ?.focusSurfaceComment(_sharedAnchor(anchor))
            .catchError((_) {}),
      );
    } on ArgumentError {
      /* A malformed anchor cannot move the camera. */
    }
  }

  late int _viewsCount = widget.work.viewsCount;
  late int _likesCount = math.max(0, widget.work.likesCount);
  late bool _liked = widget.work.likedByMe;
  bool _likeInFlight = false;

  void _setLikeState({required bool liked, required int count}) {
    void update() {
      _liked = liked;
      _likesCount = math.max(0, count);
    }

    if (mounted) {
      setState(update);
    } else {
      // The feed must still receive a rollback if its detail route was closed
      // while the existing service request was in flight.
      update();
    }
    widget.onWorkUpdated?.call(
      widget.work.copyWith(
        likedByMe: _liked,
        likesCount: _likesCount,
        viewsCount: _viewsCount,
      ),
    );
  }

  bool _beginToggleLike() {
    if (_likeInFlight) return false;
    final release = widget.service.tryAcquireLikeRequest(widget.work.id);
    if (release == null) return false;
    unawaited(_toggleLike(release));
    return true;
  }

  Future<void> _toggleLike(VoidCallback release) async {
    final wasLiked = _liked;
    final previousCount = _likesCount;
    final service = widget.service;
    final work = widget.work;
    try {
      _likeInFlight = true;
      _setLikeState(
        liked: !wasLiked,
        count: previousCount + (wasLiked ? -1 : 1),
      );
      final nowLiked = await service.toggleLike(
        workId: work.id,
        currentlyLiked: wasLiked,
      );
      if (nowLiked != _liked) {
        _setLikeState(
          liked: nowLiked,
          count:
              previousCount + (nowLiked == wasLiked ? 0 : (nowLiked ? 1 : -1)),
        );
      }
    } catch (error) {
      debugPrint('[WorkDetailPage] toggleLike failed: $error');
      _setLikeState(liked: wasLiked, count: previousCount);
    } finally {
      try {
        service.reportLikeResult(
          work.copyWith(likedByMe: _liked, likesCount: _likesCount),
        );
      } finally {
        release();
        if (mounted) {
          setState(() => _likeInFlight = false);
        } else {
          _likeInFlight = false;
        }
      }
    }
  }

  /// Report / block only make sense on someone else's work.
  bool get _isMine => widget.service.currentUserId == widget.work.userId;

  void _showMoreActions() {
    final l = AppL10n.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AetherColors.bgCanvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AetherRadii.xl),
        ),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isMine)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AetherColors.danger,
                ),
                title: Text(
                  l.workDeleteAction,
                  style: AetherTextStyles.body.copyWith(
                    color: AetherColors.danger,
                  ),
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _confirmDelete();
                },
              )
            else ...[
              ListTile(
                leading: const Icon(
                  Icons.flag_outlined,
                  color: AetherColors.textPrimary,
                ),
                title: Text(l.reportAction, style: AetherTextStyles.body),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _openReport();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.block_rounded,
                  color: AetherColors.danger,
                ),
                title: Text(
                  l.blockAction,
                  style: AetherTextStyles.body.copyWith(
                    color: AetherColors.danger,
                  ),
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _confirmBlock();
                },
              ),
            ],
            const SizedBox(height: AetherSpacing.sm),
          ],
        ),
      ),
    );
  }

  Future<void> _openReport() async {
    final repository =
        widget.reportRepository ??
        SupabaseSocialProfileRepository(client: Supabase.instance.client);
    final result = await Navigator.of(context).push<UserReportResult>(
      MaterialPageRoute<UserReportResult>(
        builder: (_) => UserReportPage(
          targetUserId: widget.work.userId,
          sourceWorkId: widget.work.id,
          repository: repository,
        ),
      ),
    );
    if (result != null && mounted) {
      final l = AppL10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.failedEvidenceCount == 0
                ? l.reportUserSubmitted
                : l.reportSubmittedPartial,
          ),
        ),
      );
    }
  }

  /// "Immediately remove posts from the feed" — the extra requirement
  /// Apple adds to Guideline 1.2 for UGC apps. Deletes the row AND the
  /// storage objects server-side; deleting only the row would leave the
  /// file publicly downloadable (public bucket ⇒ RLS bypassed).
  Future<void> _confirmDelete() async {
    final l = AppL10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AetherColors.bgCanvas,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AetherRadii.lg),
        ),
        title: Text(l.workDeleteDialogTitle, style: AetherTextStyles.h2),
        content: Text(l.workDeleteDialogBody, style: AetherTextStyles.body),
        actions: [
          if (widget.service.currentUserId == null && widget.onSignIn != null)
            TextButton(onPressed: widget.onSignIn, child: const Text('登录')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AetherColors.danger),
            child: Text(
              l.workDeleteConfirm,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.service.deleteMyWork(widget.work.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.workDeleteDone)));
      // The work no longer exists; leave the page. The feed refetches on
      // its next load, and pull-to-refresh is right there.
      Navigator.of(context).maybePop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.workDeleteFailed)));
    }
  }

  Future<void> _confirmBlock() async {
    final l = AppL10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AetherColors.bgCanvas,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AetherRadii.lg),
        ),
        title: Text(l.blockDialogTitle, style: AetherTextStyles.h2),
        content: Text(l.blockDialogBody, style: AetherTextStyles.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AetherColors.danger),
            child: Text(
              l.blockConfirm,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.service.blockUser(widget.work.userId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.blockDone)));
      // Leave the page: its author is now blocked, so keeping their work
      // on screen would contradict the action just taken. The feed
      // re-filters on its next load.
      Navigator.of(context).maybePop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.blockFailed)));
    }
  }

  /// 首访烘缩略图。[2026-08-17 用户签决"恢复 ThumbBaker,给那 3 个老作品补"]
  ///
  /// 这条链此前被删过,理由是"PublishService 发布时就上传缩略图"—— 但那只
  /// 覆盖**新发布**的作品。库里 6 个作品有 3 个(Toy Car / Damaged Helmet /
  /// scan 2026-05-04)是发布链上线前的老数据,永远等不到缩略图,不是焦点卡
  /// 时就只能显示灰渐变。
  ///
  /// 门槛在 ThumbBaker 内部:已有缩略图 / 本进程烘过 / 正在烘 / 未登录 /
  /// 不是作者(RLS 只让作者写)—— 任一命中都安静跳过。
  late final ThumbBaker _thumbBaker = ThumbBaker(service: widget.service);

  _CloudStatus _status = _CloudStatus.loading;
  SparseCloudData? _cloud;

  @override
  void initState() {
    super.initState();
    _lastCommentUser = widget.service.currentUserId;
    try {
      _commentAuth = Supabase.instance.client.auth.onAuthStateChange.listen((
        event,
      ) {
        if (!mounted) return;
        final user = widget.service.currentUserId;
        if (user == _lastCommentUser &&
            event.event != AuthChangeEvent.signedIn) {
          return;
        }
        setState(() {
          _lastCommentUser = user;
          _commentIdentityEpoch++;
          _surfaceAssetSha256 = null;
          _commentAnchor = null;
          _visibleComments = const [];
          _commentLayout = null;
          _dismissedLayoutId = null;
          _selectedCommentId = null;
          _commentsEnabled = false;
          _commentsOpen = false;
          _selectingCommentPoint = false;
        });
        unawaited(_setPicking(false));
        unawaited(_syncCommentMarkers());
        final viewer = _surfaceViewer;
        if (viewer != null) unawaited(_bindSurfaceAsset(viewer));
      });
    } catch (_) {
      /* Tests can provide a repository without the global singleton. */
    }
    widget.service.lastLikeResult.addListener(_onLikeResult);
    // Record a view as soon as the page mounts. The hour-bucket dedup
    // makes this safe to call unconditionally.
    unawaited(_recordView());
    unawaited(_loadCloud());
  }

  void _onLikeResult() {
    final result = widget.service.lastLikeResult.value;
    if (!mounted || result == null || result.id != widget.work.id) return;
    if (result.likedByMe == _liked && result.likesCount == _likesCount) return;
    // Another surface may finish after this route opens. Its outcome concerns
    // likes only: retain this detail's separately recorded view count.
    _setLikeState(liked: result.likedByMe, count: result.likesCount);
  }

  @override
  void didUpdateWidget(covariant WorkDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged =
        oldWidget.work.id != widget.work.id ||
        oldWidget.work.modelStoragePath != widget.work.modelStoragePath;
    if (sourceChanged ||
        oldWidget.commentRepository != widget.commentRepository ||
        !identical(oldWidget.service, widget.service) ||
        _lastCommentUser != widget.service.currentUserId) {
      _commentIdentityEpoch++;
      _lastCommentUser = widget.service.currentUserId;
      _surfaceAssetSha256 = null;
      _commentAnchor = null;
      _visibleComments = const [];
      _commentLayout = null;
      _dismissedLayoutId = null;
      _selectedCommentId = null;
      _commentsEnabled = false;
      _commentsOpen = false;
      _selectingCommentPoint = false;
      _commentRepository =
          widget.commentRepository ?? SupabaseCommunityCommentRepository();
      unawaited(_setPicking(false));
      unawaited(_syncCommentMarkers());
      if (sourceChanged) {
        _surfaceViewer = null;
      } else {
        final viewer = _surfaceViewer;
        if (viewer != null) unawaited(_bindSurfaceAsset(viewer));
      }
    }
    if (!identical(oldWidget.service, widget.service)) {
      oldWidget.service.lastLikeResult.removeListener(_onLikeResult);
      widget.service.lastLikeResult.addListener(_onLikeResult);
    }
  }

  @override
  void dispose() {
    _commentAuth?.cancel();
    unawaited(_setPicking(false));
    widget.service.lastLikeResult.removeListener(_onLikeResult);
    super.dispose();
  }

  Future<void> _recordView() async {
    final updated = await widget.service.recordView(widget.work.id);
    if (!mounted || updated == null) return;
    if (updated != _viewsCount) setState(() => _viewsCount = updated);
  }

  Future<void> _loadCloud() async {
    final storagePath = widget.work.modelStoragePath;
    if (storagePath == null || storagePath.isEmpty) {
      if (mounted) setState(() => _status = _CloudStatus.failed);
      return;
    }
    // ── 格式分派 ────────────────────────────────────────────────────
    //
    // [2026-08-17 用户指认] "稀疏点云只是我的管线还没搭建完,最终产物就是
    // mesh" —— 所以 mesh 不是要淘汰的遗留格式,是**终态**。GLB 走
    // AetherCppCardDemo(五月写好、Phase 6.4b 已 SHIPPED 的 aether_cpp scene
    // renderer:isFocused 驱自转、bounds 驱取景、首帧淡入),点云走
    // SparseCloudView 这条过渡期的路。
    //
    // 此前这里对一切非 ply 直接判 unsupported,于是社区里现存的 mesh 作品全
    // 部只能看到"格式不支持"—— 而它们本来就是这条链天生要渲的东西。
    final format = widget.work.format.toLowerCase();
    if (format == 'glb' || format == 'gltf') {
      if (mounted) setState(() => _status = _CloudStatus.mesh);
      return;
    }
    if (format != 'ply') {
      if (mounted) setState(() => _status = _CloudStatus.unsupported);
      return;
    }
    try {
      final url = widget.service.modelUrlFor(storagePath);
      final localPath = await GlbCache.instance.fetchPath(url);
      final cloud = await compute(loadSparsePly, localPath);
      if (!mounted) return;
      setState(() {
        if (cloud == null || cloud.count == 0) {
          _status = _CloudStatus.failed;
        } else {
          _cloud = cloud;
          _status = _CloudStatus.ready;
        }
      });
    } catch (e) {
      debugPrint('[WorkDetailPage] cloud load failed: $e');
      if (mounted) setState(() => _status = _CloudStatus.failed);
    }
  }

  /// Shared renderer 首帧就绪后，交给 ThumbBaker 判断是否需要生成缩略图。
  void _onViewerReady(ProductViewerCapture viewer) {
    if (!mounted) return;
    setState(() {
      _surfaceViewer = viewer;
      _surfaceAssetSha256 = null;
      _visibleComments = const [];
    });
    unawaited(_syncCommentMarkers());
    unawaited(_bindSurfaceAsset(viewer));
    unawaited(_thumbBaker.maybeBake(work: widget.work, viewer: viewer));
  }

  Future<void> _bindSurfaceAsset(ProductViewerCapture viewer) async {
    final workId = widget.work.id;
    final path = widget.work.modelStoragePath;
    final identityEpoch = _commentIdentityEpoch;
    String? hash;
    try {
      hash = await viewer.modelContentSha256();
    } catch (_) {
      // Unproven model identity cannot authorize surface annotations.
    }
    if (!mounted ||
        widget.work.id != workId ||
        widget.work.modelStoragePath != path ||
        _commentIdentityEpoch != identityEpoch ||
        !identical(viewer, _surfaceViewer)) {
      return;
    }
    final verified = hash != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)
        ? hash
        : null;
    if (_surfaceAssetSha256 == verified) return;
    setState(() => _surfaceAssetSha256 = verified);
  }

  Widget _buildBody() {
    final l = AppL10n.of(context);
    switch (_status) {
      case _CloudStatus.loading:
        return const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white54,
            ),
          ),
        );
      case _CloudStatus.ready:
        final cloud = _cloud!;
        return AutoRotatingCloudView(
          xyz: cloud.xyz,
          rgb: cloud.rgb,
          // Visitors get the same look/feel controls as the drafts
          // viewer, but no editing affordances — `editing` stays false
          // and no selectionBox is threaded in, so nothing is ever
          // written back beside someone else's PLY.
          showControls: true,
          logTag: '社区详情',
        );
      case _CloudStatus.mesh:
        // 详情页 = 自转 + 可手势 + 全质量,三样都要。
        //
        // 五月这一页走的是 LiveModelView(thermion),因为当时
        // AetherCppCardDemo 还没落地 orbit 手势(它头注释里的 G5)。手势现在
        // 有了(interactive:true = 单指 orbit / 双指 pinch),但它和自转本来
        // 是被同一个开关绑死的 —— autoRotateUntilTouched 把这层绑定解开:
        // 打开就转,用户一上手就永久让位给手势。
        return AetherCppCardDemo(
          key: ValueKey('work-mesh-${widget.work.id}'),
          modelUrl: widget.service.modelUrlFor(widget.work.modelStoragePath!),
          communitySessionKey: jsonEncode([
            widget.service.currentUserId,
            widget.work.id,
            widget.work.format,
            widget.work.publishedAt?.toUtc().toIso8601String(),
          ]),
          communitySessions: widget.communitySessions,
          isFocused: true,
          interactive: true,
          autoRotateUntilTouched: true,
          // 契约 kViewerSocialPolicyContract.detailQuality = 'full'。
          // interactive 模式本来就默认 full,这里显式写出来当锚 —— 免得哪天
          // 有人把 interactive 改掉,质量档跟着悄悄掉进 feed 档。
          quality: ViewerQuality.full,
          background: Colors.black,
          onViewerReady: _onViewerReady,
          onSurfacePicked: _onSurfacePicked,
          onSurfaceMarkerSelected: _onSurfaceMarkerSelected,
          onSurfaceMarkerLayoutChanged: _onCommentLayout,
          hostBuilderForTesting: widget.viewerHostBuilder,
          resolveLocalPathForTesting: widget.resolveModelPath,
        );
      case _CloudStatus.unsupported:
        return _EmptyState(
          icon: Icons.view_in_ar_rounded,
          message:
              '${l.communityFormatUnsupported}'
              ' (${widget.work.format.toUpperCase()})',
        );
      case _CloudStatus.failed:
        return _EmptyState(
          icon: Icons.cloud_off_rounded,
          message: l.communityCloudLoadFailed,
          onRetry: () {
            setState(() => _status = _CloudStatus.loading);
            unawaited(_loadCloud());
          },
        );
    }
  }

  Widget _floatingComments(BoxConstraints viewport) {
    final width = math.min(360.0, math.max(0.0, viewport.maxWidth - 24));
    final bottomReserve = viewport.maxHeight < 300 ? 16.0 : 84.0;
    final height = math.min(
      460.0,
      math.max(0.0, viewport.maxHeight - bottomReserve - 8),
    );
    final point = _commentLayout;
    final x = (point?.x ?? .5) * viewport.maxWidth;
    final y = (point?.y ?? .3) * viewport.maxHeight;
    final preferredLeft = x > viewport.maxWidth / 2 ? x - width - 18 : x + 18;
    final left = preferredLeft.clamp(
      12.0,
      math.max(12.0, viewport.maxWidth - width - 12),
    );
    final preferredTop = y + height + 24 <= viewport.maxHeight - 76
        ? y + 12
        : y - height - 12;
    final top = preferredTop.clamp(
      8.0,
      math.max(8.0, viewport.maxHeight - height - bottomReserve),
    );
    return Positioned(
      left: left.toDouble(),
      top: top.toDouble(),
      width: width,
      height: height,
      child: Offstage(
        offstage: !_floatingCommentsVisible,
        child: TickerMode(
          enabled: _commentsOpen || _commentsEnabled,
          child: DecoratedBox(
            key: const ValueKey('floating-surface-comments'),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 20),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: CommunityCommentsPanel(
                key: ValueKey(_commentPartition),
                workId: widget.work.id,
                workAuthorId: widget.work.userId,
                active: _commentsOpen || _commentsEnabled,
                presentationVisible: _floatingCommentsVisible,
                repository: _commentRepository,
                requireAssetBinding: true,
                expectedAssetSha256: _surfaceAssetSha256,
                imagePicker: widget.commentImagePicker,
                currentUserId: widget.service.currentUserId,
                onSignIn: widget.onSignIn,
                selectedAnchor: _commentAnchor,
                onPickPoint:
                    _surfaceViewer == null || _surfaceAssetSha256 == null
                    ? null
                    : _pickCommentPoint,
                onClearAnchor: () => setState(() => _commentAnchor = null),
                onClose: _closeComments,
                onCommentSelected: _focusComment,
                onVisibleCommentsChanged: _commentsChanged,
                onModerationCaseSelected: (caseId) => openCommentModerationCase(
                  context,
                  caseId: caseId,
                  repository: widget.commentModerationRepository,
                  userIdReader: () => widget.service.currentUserId,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Black, matching the drafts viewer and the sparse thumbnail — a
    // point cloud reads far better on black than on white.
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          // Guideline 1.2 wants a report mechanism AND a way to block
          // abusive users; Apple's UGC rejection letters additionally ask
          // for a way for authors to immediately remove their own posts
          // from the feed. All three tables have existed since April but
          // had no client entry point — and this AppBar had no `actions:`
          // at all, so there was nowhere to put one.
          //
          // The menu contents flip by ownership: reporting or blocking
          // yourself is meaningless, and deleting someone else's work
          // isn't yours to do.
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
            tooltip: AppL10n.of(context).workMoreActions,
            onPressed: _showMoreActions,
          ),
        ],
        title: Text(
          widget.work.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, viewport) => Stack(
                    children: [
                      Positioned.fill(child: _buildBody()),
                      if (_commentsEverOpened && _supportsSurfaceComments)
                        _floatingComments(viewport),
                      if (_supportsSurfaceComments)
                        Positioned(
                          right: 16,
                          bottom: 16,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              IconButton.filledTonal(
                                key: const ValueKey(
                                  'work-detail-comment-toggle',
                                ),
                                tooltip: _commentsEnabled ? '关闭模型评论' : '显示模型评论',
                                isSelected: _commentsEnabled,
                                onPressed: _toggleComments,
                                icon: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                ),
                                selectedIcon: const Icon(
                                  Icons.chat_bubble_rounded,
                                ),
                              ),
                              if (_commentsEnabled && !_commentsOpen)
                                TextButton(
                                  onPressed: _showComments,
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('全部评论 / 写评论'),
                                ),
                            ],
                          ),
                        ),
                      if (_selectingCommentPoint)
                        Positioned(
                          left: 20,
                          right: 20,
                          bottom: 76,
                          child: IgnorePointer(
                            child: Center(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: .75),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  child: Text(
                                    '点一下模型表面，选择评论位置',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              ValueListenableBuilder<Set<String>>(
                valueListenable: widget.service.pendingLikeWorkIds,
                builder: (context, pending, _) => _MetaRow(
                  viewsCount: _viewsCount,
                  likesCount: _likesCount,
                  liked: _liked,
                  likeBusy: _likeInFlight || pending.contains(widget.work.id),
                  onLike: _beginToggleLike,
                  author: widget.work.authorDisplayName,
                  description: widget.work.description,
                  onComments: _supportsSurfaceComments ? _showComments : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final int viewsCount;
  final int likesCount;
  final bool liked;
  final bool likeBusy;
  final bool Function() onLike;
  final String author;
  final String? description;
  final VoidCallback? onComments;

  const _MetaRow({
    required this.viewsCount,
    required this.likesCount,
    required this.liked,
    required this.likeBusy,
    required this.onLike,
    required this.author,
    required this.description,
    this.onComments,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(top: BorderSide(color: Colors.white12, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  author,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              _CountChip(
                icon: Icons.remove_red_eye_outlined,
                value: viewsCount,
              ),
              const SizedBox(width: 12),
              if (onComments != null) ...[
                TextButton.icon(
                  key: const ValueKey('work-detail-comments'),
                  onPressed: onComments,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  label: const Text('全部评论', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 4),
              ],
              _DetailLikeButton(
                liked: liked,
                count: likesCount,
                busy: likeBusy,
                onTap: onLike,
              ),
            ],
          ),
          if (description != null && description!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              description!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailLikeButton extends StatefulWidget {
  const _DetailLikeButton({
    required this.liked,
    required this.count,
    required this.busy,
    required this.onTap,
  });

  final bool liked;
  final int count;
  final bool busy;
  final bool Function() onTap;

  @override
  State<_DetailLikeButton> createState() => _DetailLikeButtonState();
}

class _DetailLikeButtonState extends State<_DetailLikeButton> {
  bool _pulsing = false;

  void _tap() {
    if (widget.busy) return;
    if (!widget.onTap()) return;
    setState(() => _pulsing = true);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.liked ? AetherColors.danger : Colors.white54;
    return Semantics(
      button: true,
      toggled: widget.liked,
      enabled: !widget.busy,
      label: AppL10n.of(context).socialLikesReceived,
      child: GestureDetector(
        key: const ValueKey('work-detail-like'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.busy ? null : _tap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                key: const ValueKey('work-detail-like-scale'),
                scale: _pulsing ? 1.2 : 1,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                onEnd: () {
                  if (_pulsing && mounted) setState(() => _pulsing = false);
                },
                child: Icon(
                  widget.liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 18,
                  color: color,
                ),
              ),
              const SizedBox(width: 4),
              AnimatedSwitcher(
                key: const ValueKey('work-detail-like-count'),
                duration: const Duration(milliseconds: 180),
                child: Text(
                  '${widget.count}',
                  key: ValueKey(widget.count),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final IconData icon;
  final int value;
  const _CountChip({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.white54),
        const SizedBox(width: 4),
        Text(
          '$value',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white54,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  const _EmptyState({required this.icon, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.white24),
          const SizedBox(height: AetherSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.white54),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AetherSpacing.md),
            TextButton(
              onPressed: onRetry,
              child: Text(AppL10n.of(context).communityRetry),
            ),
          ],
        ],
      ),
    );
  }
}
