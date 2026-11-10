import 'package:flutter/widgets.dart';
import 'dart:typed_data';

import '../../community/feed_models.dart';
import 'masonry_policy.dart';

/// Actual prepared sizes. Pairing never changes a work's layout or aspect ratio.
class CommunityCardMetrics {
  const CommunityCardMetrics({
    required this.cardSize,
    required this.viewerSize,
    required this.pixelRatio,
    this.readinessToken,
    this.stillFrameBytes,
  });

  final Size cardSize;
  final Size viewerSize;
  final double pixelRatio;
  final Object? readinessToken;
  final Uint8List? stillFrameBytes;

  /// Keep catalogue dimensions without retaining disposed States or images.
  CommunityCardMetrics get layoutOnly => CommunityCardMetrics(
    cardSize: cardSize,
    viewerSize: viewerSize,
    pixelRatio: pixelRatio,
  );

  bool get isValid =>
      pixelRatio.isFinite &&
      pixelRatio > 0 &&
      cardSize.width.isFinite &&
      cardSize.height.isFinite &&
      viewerSize.width.isFinite &&
      viewerSize.height.isFinite &&
      cardSize.width > 0 &&
      viewerSize.width > 0 &&
      viewerSize.height > 0 &&
      cardSize.height >= viewerSize.height;

  /// Equality at the current display's pixel resolution, without resizing.
  (double, int, int, int, int) get pixelDimensions => (
    pixelRatio,
    (cardSize.width * pixelRatio).round(),
    (cardSize.height * pixelRatio).round(),
    (viewerSize.width * pixelRatio).round(),
    (viewerSize.height * pixelRatio).round(),
  );
}

/// Reorder only the selected pair; all remaining raw-order works stay in order.
/// Null means the prepared candidates do not contain a verified matching pair.
List<FeedWork>? communityFirstPairOrder(
  List<FeedWork> works,
  Map<String, CommunityCardMetrics> metrics,
) {
  if (works.length < 2) return List<FeedWork>.unmodifiable(works);
  final bySize = <(double, int, int, int, int), List<int>>{};
  for (var i = 0; i < works.length; i++) {
    final measured = metrics[communityCoverSourceKey(works[i])];
    if (measured == null || !measured.isValid) continue;
    bySize.putIfAbsent(measured.pixelDimensions, () => []).add(i);
  }
  // Map insertion order preserves the earliest raw-order matching group.
  for (final indices in bySize.values) {
    if (indices.length < 2) continue;
    final a = indices[0], b = indices[1];
    return List<FeedWork>.unmodifiable([
      works[a],
      works[b],
      for (var i = 0; i < works.length; i++)
        if (i != a && i != b) works[i],
    ]);
  }
  return null;
}
