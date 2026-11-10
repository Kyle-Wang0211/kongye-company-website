import 'feed_models.dart';

/// Inputs must come from the public feed query, never a local upload draft.
/// Only the viewer's public works move; everyone else's order stays stable.
List<FeedWork> prioritizeAuthorFeed(
  List<FeedWork> publicPage,
  List<FeedWork> ownPublicWorks,
  String? viewerId,
) {
  final seen = <String>{};
  final rows = <FeedWork>[
    ...publicPage.where((w) => seen.add(w.id)),
    if (viewerId != null)
      ...ownPublicWorks.where((w) => w.userId == viewerId && seen.add(w.id)),
  ];
  if (viewerId == null) return rows;
  final own = rows.where((w) => w.userId == viewerId).toList();
  own.sort((a, b) {
    final date = (b.publishedAt ?? DateTime(1970)).compareTo(
      a.publishedAt ?? DateTime(1970),
    );
    return date == 0 ? b.id.compareTo(a.id) : date;
  });
  return [...own, ...rows.where((w) => w.userId != viewerId)];
}
