import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'community_loading.dart';

import '../design_system.dart';
import 'masonry_policy.dart';

/// Aligned community rows; name retained for existing callers.
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 900 ? 4 : 2;
      final width =
          (constraints.maxWidth - kCommunitySideInset * 2 - (columns - 1) * 4) /
          columns;
      return CustomScrollView(
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
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 6,
                crossAxisSpacing: 4,
                mainAxisExtent:
                    width / kCommunityLoadingCoverAspectRatio +
                    communityInformationHeight(context),
              ),
              delegate: SliverChildBuilderDelegate(
                itemBuilder,
                childCount: itemCount,
              ),
            ),
          ),
          if (footer != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(2, 8, 2, 140),
              sliver: SliverToBoxAdapter(child: footer),
            ),
        ],
      );
    },
  );
}
