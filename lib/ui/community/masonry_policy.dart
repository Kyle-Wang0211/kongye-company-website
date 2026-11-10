import '../../community/feed_models.dart';

// Community-only values; other screens keep their existing design tokens.
const double kCommunitySideInset = 2;
const double kCommunityCardRadius = 4;
// Every cover occupies one fixed media frame, independent of decoded pixels.
const double kCommunityLoadingCoverAspectRatio = 3 / 4;

double masonryCoverAspectRatio(double? contentAspectRatio) =>
    kCommunityLoadingCoverAspectRatio;

/// Reports source availability only; missing covers still render metadata.
bool hasCommunityPreviewSource(FeedWork work) =>
    work.thumbnailStoragePath?.trim().isNotEmpty == true;

/// An edit to either source invalidates a recycled card's resolved proportions.
String communityCoverSourceKey(FeedWork work) =>
    '${work.userId}\u0000${work.id}\u0000${work.format}\u0000'
    '${work.modelStoragePath}\u0000${work.thumbnailStoragePath}';
