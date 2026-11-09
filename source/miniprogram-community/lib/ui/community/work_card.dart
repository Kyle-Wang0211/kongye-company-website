import 'current_author_name.dart';
// Community cards display only the publisher-selected cover. Model downloads
// and the shared 3D renderer belong to the detail page opened by onTap.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../community/community_service.dart';
import '../../community/feed_models.dart';
import '../design_system.dart';
import '../shared/product_model_view.dart';
import 'first_pair_policy.dart';
import 'masonry_policy.dart';
import 'generated_account_avatar.dart';
import 'published_cover.dart';
import 'community_loading.dart';

class WorkCard extends StatefulWidget {
  const WorkCard({
    super.key,
    required this.work,
    required this.service,
    required this.onTap,
    this.coverAspectRatio,
    this.onCoverAspectRatioChanged,
    this.isFocused = false,
    this.viewerAllowed = true,
    this.onVisibilityChanged,
    this.rotationAllowed = true,
    this.onWorkUpdated,
    this.onAuthorTap,
    this.revealed = true,
    this.onContentReady,
    this.prepareWhileHidden = false,
    this.onPreparationFailed,
    this.onPrepared,
    this.onPreparationInvalidated,
    this.onPreparationStarted,
    this.onPreparationDisposed,
    this.viewerHostBuilderForTesting,
    this.preparedStillBytes,
    this.coverImageForTesting,
    this.showMissingCover = false,
  });

  final FeedWork work;
  final CommunityService service;
  final VoidCallback onTap;
  final double? coverAspectRatio;
  final ValueChanged<double>? onCoverAspectRatioChanged;
  final ValueChanged<double>? onVisibilityChanged;
  final ValueChanged<FeedWork>? onWorkUpdated, onAuthorTap;
  final bool revealed, prepareWhileHidden;
  final bool showMissingCover;
  final VoidCallback? onContentReady, onPreparationInvalidated;
  final ValueChanged<Object>? onPreparationFailed;
  final ValueChanged<CommunityCardMetrics>? onPrepared;
  final ValueChanged<Object>? onPreparationStarted, onPreparationDisposed;

  // Keep existing callers source-compatible. Cover cards never consume model
  // frames, mount a viewer, rotate, or use the renderer test host.
  final bool isFocused, viewerAllowed, rotationAllowed;
  // ignore: invalid_use_of_visible_for_testing_member
  final ProductModelHostBuilder? viewerHostBuilderForTesting;
  final Uint8List? preparedStillBytes;

  @visibleForTesting
  final ImageProvider? coverImageForTesting;

  @override
  State<WorkCard> createState() => _WorkCardState();
}

class _WorkCardState extends State<WorkCard> {
  late FeedWork _work;
  late final TapGestureRecognizer _authorTapRecognizer;
  final _naturalCardKey = GlobalKey();
  bool _likeInFlight = false, _thumbReady = false, _reportedReady = false;
  ImageProvider? _thumbnailProvider;
  ImageStream? _thumbnailStream;
  ImageStreamListener? _thumbnailListener;
  String? _thumbnailKey;
  int _thumbnailEpoch = 0;
  double? _thumbnailAspectRatio;
  CommunityCardMetrics? _lastPreparedMetrics;
  Timer? _coverDeadline;
  bool _coverFailed = false;

  double? get _coverAspectRatio =>
      masonryCoverAspectRatio(_thumbnailAspectRatio ?? widget.coverAspectRatio);

  @override
  void initState() {
    super.initState();
    _work = widget.work;
    _authorTapRecognizer = TapGestureRecognizer()
      ..onTap = () => widget.onAuthorTap?.call(_work);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveThumbnail();
  }

  void _detachThumbnail() {
    _thumbnailEpoch++;
    _coverDeadline?.cancel();
    _coverDeadline = null;
    if (_thumbnailListener != null) {
      _thumbnailStream?.removeListener(_thumbnailListener!);
    }
    _thumbnailStream = null;
    _thumbnailListener = null;
  }

  void _resolveThumbnail() {
    final path = _work.thumbnailStoragePath;
    final width = MediaQuery.sizeOf(context).width - AetherSpacing.lg * 2;
    final cacheWidth = (width * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(64, 1024);
    final url = path == null || path.trim().isEmpty
        ? (_work.format == 'glb'
              ? publishedModelCover(_work.modelStoragePath)
              : null)
        : widget.service.thumbnailUrlFor(path);
    final key = widget.coverImageForTesting != null
        ? 'test-${identityHashCode(widget.coverImageForTesting)}'
        : url == null
        ? 'missing'
        : '$url\u0000$cacheWidth';
    if (key == _thumbnailKey) return;
    _detachThumbnail();
    _thumbnailKey = key;
    _thumbReady = false;
    _coverFailed = false;
    _thumbnailAspectRatio = null;
    _reportedReady = false;
    _lastPreparedMetrics = null;
    _thumbnailProvider =
        widget.coverImageForTesting ??
        (url == null
            ? null
            : ResizeImage.resizeIfNeeded(cacheWidth, null, NetworkImage(url)));
    if (_thumbnailProvider == null) {
      final epoch = _thumbnailEpoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && epoch == _thumbnailEpoch) {
          setState(() => _coverFailed = true);
          widget.onPreparationFailed?.call(
            StateError('Cover image is unavailable'),
          );
        }
      });
      return;
    }
    final epoch = _thumbnailEpoch;
    final provider = _thumbnailProvider!;
    void fail(Object error) {
      if (!mounted || epoch != _thumbnailEpoch || _thumbReady || _coverFailed) {
        return;
      }
      setState(() => _coverFailed = true);
      _coverDeadline?.cancel();
      unawaited(provider.evict());
      widget.onPreparationFailed?.call(error);
    }

    _coverDeadline = Timer(const Duration(seconds: 30), () {
      fail(TimeoutException('Cover image preparation timed out'));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && epoch == _thumbnailEpoch && !_thumbReady) {
        widget.onPreparationStarted?.call(this);
      }
    });
    _thumbnailStream = _thumbnailProvider!.resolve(
      createLocalImageConfiguration(context),
    );
    _thumbnailListener = ImageStreamListener(
      (info, _) {
        final ratio = info.image.width / info.image.height;
        info.dispose();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || epoch != _thumbnailEpoch) return;
          _coverDeadline?.cancel();
          setState(() {
            _thumbnailAspectRatio = ratio;
            _thumbReady = true;
          });
          widget.onCoverAspectRatioChanged?.call(ratio);
        });
        WidgetsBinding.instance.scheduleFrame();
      },
      onError: (Object error, StackTrace? stack) {
        WidgetsBinding.instance.addPostFrameCallback((_) => fail(error));
        WidgetsBinding.instance.scheduleFrame();
      },
    );
    _thumbnailStream!.addListener(_thumbnailListener!);
  }

  @override
  void didUpdateWidget(covariant WorkCard old) {
    super.didUpdateWidget(old);
    final sourceChanged =
        communityCoverSourceKey(widget.work) !=
        communityCoverSourceKey(old.work);
    if (!_likeInFlight || widget.work.id != old.work.id) _work = widget.work;
    if (sourceChanged) {
      _work = widget.work;
      // Let the resolver compare the previous URL against the replacement,
      // including null. Clearing its key early would retain stale ready pixels.
      _reportedReady = false;
      _lastPreparedMetrics = null;
    }
    if (widget.prepareWhileHidden && !old.prepareWhileHidden) {
      _lastPreparedMetrics = null;
    }
    _resolveThumbnail();
  }

  @override
  void dispose() {
    final callback = widget.onPreparationDisposed;
    WidgetsBinding.instance.addPostFrameCallback((_) => callback?.call(this));
    _detachThumbnail();
    _authorTapRecognizer.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    if (_likeInFlight) return;
    final service = widget.service;
    final previous = _work;
    final release = service.tryAcquireLikeRequest(previous.id);
    if (release == null) return;
    final onUpdated = widget.onWorkUpdated;
    final wasLiked = previous.likedByMe;
    var finalWork = previous;
    void publish(bool liked, int count) {
      final updated = previous.copyWith(
        likedByMe: liked,
        likesCount: count < 0 ? 0 : count,
      );
      finalWork = updated;
      if (mounted && widget.work.id == previous.id) {
        setState(() => _work = updated);
      }
      // A refresh may dispose this card before its request completes.
      onUpdated?.call(updated);
    }

    try {
      _likeInFlight = true;
      publish(!wasLiked, previous.likesCount + (wasLiked ? -1 : 1));
      final nowLiked = await service.toggleLike(
        workId: previous.id,
        currentlyLiked: wasLiked,
      );
      if (nowLiked != !wasLiked) {
        publish(nowLiked, previous.likesCount);
      }
    } catch (error) {
      debugPrint('[WorkCard] toggleLike failed: $error');
      publish(wasLiked, previous.likesCount);
    } finally {
      try {
        service.reportLikeResult(finalWork);
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

  @override
  Widget build(BuildContext context) {
    final ratio = _coverAspectRatio;
    final source = communityCoverSourceKey(_work);
    final ready = _thumbReady && !_coverFailed && ratio != null;
    if (ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            source != communityCoverSourceKey(_work) ||
            !_thumbReady) {
          return;
        }
        final size = _naturalCardKey.currentContext?.size;
        final currentRatio = _coverAspectRatio;
        if (size == null || currentRatio == null) return;
        final metrics = CommunityCardMetrics(
          cardSize: size,
          viewerSize: Size(size.width, size.width / currentRatio),
          pixelRatio: MediaQuery.devicePixelRatioOf(context),
          readinessToken: this,
        );
        if (!metrics.isValid) return;
        if (!_reportedReady) {
          _reportedReady = true;
          widget.onContentReady?.call();
        }
        if (_lastPreparedMetrics?.pixelDimensions != metrics.pixelDimensions) {
          _lastPreparedMetrics = metrics;
          widget.onPrepared?.call(metrics);
        }
      });
    }
    return VisibilityDetector(
      key: Key('work-card-${_work.id}'),
      onVisibilityChanged: (info) {
        if (mounted) widget.onVisibilityChanged?.call(info.visibleFraction);
      },
      child: Stack(
        children: [
          Visibility(
            visible: ready && widget.revealed && !widget.prepareWhileHidden,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: GestureDetector(
              onTap: widget.onTap,
              behavior: HitTestBehavior.opaque,
              child: ClipRRect(
                key: _naturalCardKey,
                borderRadius: BorderRadius.circular(kCommunityCardRadius),
                child: ColoredBox(
                  color: AetherColors.bgCanvas,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AspectRatio(
                        key: ValueKey('work-cover-${_work.id}'),
                        aspectRatio: ratio ?? kCommunityLoadingCoverAspectRatio,
                        child: ColoredBox(
                          color: Colors.black,
                          child: _thumbnailProvider == null
                              ? Semantics(
                                  key: ValueKey(
                                    'work-cover-placeholder-${_work.id}',
                                  ),
                                  label: '暂无封面',
                                  child: const SizedBox.expand(),
                                )
                              : Image(
                                  image: _thumbnailProvider!,
                                  fit: BoxFit.contain,
                                  alignment: Alignment.center,
                                  gaplessPlayback: true,
                                  errorBuilder: (_, _, _) =>
                                      const SizedBox.shrink(),
                                ),
                        ),
                      ),
                      KeyedSubtree(
                        key: ValueKey('work-info-${_work.id}'),
                        child: _cardInformation(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (!ready &&
              !_coverFailed &&
              widget.revealed &&
              !widget.prepareWhileHidden)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) => FittedBox(
                  fit: BoxFit.fill,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    child: const CommunityCardSkeleton(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cardInformation() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _work.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: AetherColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              GestureDetector(
                key: ValueKey('work-avatar-${_work.id}'),
                onTap: widget.onAuthorTap == null
                    ? null
                    : () => widget.onAuthorTap!(_work),
                child: GeneratedAccountAvatar(
                  userId: _work.userId,
                  readPublic: true,
                  radius: 8,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: currentAuthorName(
                      context,
                      _work.userId,
                      _work.authorDisplayName,
                    ),
                    recognizer: _authorTapRecognizer,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    color: AetherColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              ValueListenableBuilder<Set<String>>(
                valueListenable: widget.service.pendingLikeWorkIds,
                builder: (_, pending, _) => _LikeButton(
                  liked: _work.likedByMe,
                  count: _work.likesCount,
                  busy: _likeInFlight || pending.contains(_work.id),
                  onTap: _toggleLike,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LikeButton extends StatelessWidget {
  final bool liked;
  final int count;

  /// 请求在飞 —— 禁用点击。五月有这个,我第一版漏了:连点会连发
  /// toggleLike,乐观更新和服务端返回值交错,计数就乱了。
  final bool busy;
  final VoidCallback onTap;

  const _LikeButton({
    required this.liked,
    required this.count,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              liked ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
              size: 16,
              // Keep the existing design-system like colors.
              color: liked ? AetherColors.danger : AetherColors.textPrimary,
            ),
            // [D8 2026-08-23 用户签决] 0 不渲染 —— 不是显示 "0"。
            // 依据:低数字本身就是负向信号。冷启动期公开作品个位数,
            // 一张写着"0 个赞"的卡片比不写更伤。
            // ⚠️ 心形图标**必须保留** —— 它是点赞的可供性,不是计数。
            // 藏掉图标等于把功能藏了,那是另一回事。
            if (count > 0) ...[
              const SizedBox(width: 3),
              Text(
                formatCount(count),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AetherColors.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Keep large counts compact in the author row.
  static String formatCount(int n) {
    if (n < 1000) return '$n';
    if (n < 10000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '${(n / 1000).round()}K';
  }
}
