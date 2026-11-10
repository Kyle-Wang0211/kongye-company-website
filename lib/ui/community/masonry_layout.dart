import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../design_system.dart';
import 'masonry_policy.dart';

/// Upstream masonry layout; the existing topic and work-card widgets are reused.
class CommunityMasonry extends StatelessWidget {
  const CommunityMasonry({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.header,
    this.footer,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Widget? header;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
    physics: const AlwaysScrollableScrollPhysics(
      parent: BouncingScrollPhysics(),
    ),
    slivers: [
      if (header != null)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            kCommunitySideInset,
            AetherSpacing.md,
            kCommunitySideInset,
            AetherSpacing.lg,
          ),
          sliver: SliverToBoxAdapter(child: header),
        ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          kCommunitySideInset,
          header == null ? AetherSpacing.md : 0,
          kCommunitySideInset,
          footer == null ? 140 : 12,
        ),
        sliver: SliverMasonryGrid.count(
          crossAxisCount: 2,
          mainAxisSpacing: 6,
          crossAxisSpacing: 4,
          childCount: itemCount,
          itemBuilder: itemBuilder,
        ),
      ),
      if (footer != null)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(2, 8, 2, 140),
          sliver: SliverToBoxAdapter(child: footer),
        ),
    ],
  );
}
