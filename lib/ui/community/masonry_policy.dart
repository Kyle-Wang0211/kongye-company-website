import '../../community/feed_models.dart';

// Community-only values; other screens keep their existing design tokens.
const double kCommunitySideInset = 2;
const double kCommunityCardRadius = 4;
// Reserved layout for the loading animation only; never a work's actual ratio.
const double kCommunityLoadingCoverAspectRatio = 3 / 4;

/// Published cover pixels define the media frame. The existing masonry widget
/// lays out each natural height; no fixed aspect buckets or forced crop.
double? masonryCoverAspectRatio(double? contentAspectRatio) {
  if (contentAspectRatio == null ||
      !contentAspectRatio.isFinite ||
      contentAspectRatio <= 0) {
    return null;
  }
  return contentAspectRatio;
}

/// Structural eligibility only; actual media still has to load before reveal.
bool hasCommunityPreviewSource(FeedWork work) =>
    work.thumbnailStoragePath?.trim().isNotEmpty == true;

/// An edit to either source invalidates a recycled card's resolved proportions.
String communityCoverSourceKey(FeedWork work) =>
    '${work.userId}\u0000${work.id}\u0000${work.format}\u0000'
    '${work.modelStoragePath}\u0000${work.thumbnailStoragePath}';
