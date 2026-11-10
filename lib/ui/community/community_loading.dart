import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'masonry_policy.dart';

// The author and like count share line metrics; padding belongs to the
// counted-like row even when enlarged accessibility text exceeds the icon.
const kCommunityMetadataTextStyle = TextStyle(fontSize: 11, height: 1.2);
const kCommunityLikePadding = EdgeInsets.symmetric(horizontal: 4, vertical: 4);
const double kCommunityLikeIconSize = 16;

double communityAuthorRowHeight(BuildContext context) =>
    math.max(
      kCommunityLikeIconSize,
      MediaQuery.textScalerOf(
            context,
          ).scale(kCommunityMetadataTextStyle.fontSize!) *
          kCommunityMetadataTextStyle.height!,
    ) +
    kCommunityLikePadding.vertical;

double communityInformationHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  return 12 + communityAuthorRowHeight(context) + 4 + scaler.scale(10) * 1.2;
}

/// A decorative loading surface. Reduced motion keeps the same static geometry.
class CommunityShimmer extends StatefulWidget {
  const CommunityShimmer({super.key, this.child});
  final Widget? child;
  @override
  State<CommunityShimmer> createState() => _CommunityShimmerState();
}

class _CommunityShimmerState extends State<CommunityShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context)) {
      _animation.stop();
    } else {
      _animation.repeat();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AnimatedBuilder(
      animation: _animation,
      builder: (_, child) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-3 + _animation.value * 6, -1),
            end: Alignment(-1 + _animation.value * 6, 1),
            colors: const [
              Color(0xff242424),
              Color(0xff404040),
              Color(0xff242424),
            ],
          ),
        ),
        child: child,
      ),
      child: widget.child ?? const SizedBox.expand(),
    ),
  );
}

class CommunityCardSkeleton extends StatelessWidget {
  const CommunityCardSkeleton({super.key});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AspectRatio(
            aspectRatio: kCommunityLoadingCoverAspectRatio,
            child: CommunityShimmer(),
          ),
          SizedBox(
            height: communityInformationHeight(context),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: CommunityShimmer(),
            ),
          ),
        ],
      ),
    ),
  );
}
