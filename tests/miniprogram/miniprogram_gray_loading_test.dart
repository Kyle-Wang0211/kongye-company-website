import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/ui/community/community_loading.dart';
import 'package:pocketworld_flutter/ui/community/skeleton_shimmer.dart';

Widget shell({bool reduced = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: const Scaffold(
      body: SizedBox(width: 190, child: CommunityCardSkeleton()),
    ),
  ),
);
Color colorOf(WidgetTester t) => t
    .widgetList<Container>(
      find.descendant(
        of: find.byType(SkeletonBox).first,
        matching: find.byType(Container),
      ),
    )
    .first
    .decoration!
    .letColor;

extension on Decoration {
  Color get letColor => (this as BoxDecoration).color!;
}

void main() {
  testWidgets('community loading reuses the existing gray pulsing card', (
    t,
  ) async {
    await t.pumpWidget(shell());
    expect(find.byType(SkeletonWorkCard), findsOneWidget);
    expect(find.byType(SkeletonBox), findsWidgets);
    final start = colorOf(t);
    expect(start, kSkeletonBase);
    expect(start.computeLuminance(), greaterThan(.5));
    await t.pump();
    await t.pump(const Duration(milliseconds: 900));
    expect(colorOf(t), isNot(start));
    expect(colorOf(t).computeLuminance(), greaterThan(.5));
    final gradients = t
        .widgetList<Container>(
          find.descendant(
            of: find.byType(CommunityCardSkeleton),
            matching: find.byType(Container),
          ),
        )
        .where(
          (w) =>
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).gradient != null,
        );
    expect(gradients, isEmpty);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('reduced motion keeps the same gray card static', (t) async {
    await t.pumpWidget(shell(reduced: true));
    expect(find.byType(SkeletonWorkCard), findsOneWidget);
    expect(
      t
          .widgetList<SkeletonBox>(find.byType(SkeletonBox))
          .every((w) => !w.animate),
      isTrue,
    );
    final before = colorOf(t);
    await t.pump(const Duration(seconds: 3));
    expect(colorOf(t), before);
    expect(t.binding.hasScheduledFrame, isFalse);
    await t.pumpWidget(const SizedBox());
  });
}
