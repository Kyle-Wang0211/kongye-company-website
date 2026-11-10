import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'masonry_policy.dart';
import 'skeleton_shimmer.dart';

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

/// Reuse the shared gray pulsing card; no separate loading animation or palette.
class CommunityCardSkeleton extends StatelessWidget {
  const CommunityCardSkeleton({super.key});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: SkeletonWorkCard(
        animate:
            !MediaQuery.disableAnimationsOf(context) &&
            !MediaQuery.accessibleNavigationOf(context),
        coverAspectRatio: kCommunityLoadingCoverAspectRatio,
      ),
    ),
  );
}
