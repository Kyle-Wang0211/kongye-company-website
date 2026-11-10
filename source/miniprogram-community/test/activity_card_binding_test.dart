import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/vault_page.dart';

void main() {
  testWidgets('Mini published cards preserve 16:9 carousel and selected entry', (
    tester,
  ) async {
    int? selected;
    final image = MemoryImage(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 361,
              child: TopicCard(
                activities: [
                  TopicActivity(title: 'First', image: image),
                  TopicActivity(title: 'Second', image: image),
                ],
                onActivityTap: (index) => selected = index,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    final size = tester.getSize(find.byType(TopicCard));
    expect(size.width / size.height, closeTo(16 / 9, .001));
    await tester.tap(find.byType(PageView));
    expect(selected, 0);
    await tester.drag(find.byType(PageView), const Offset(-250, 0));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester.widget<PageView>(find.byType(PageView)).controller!.page,
      closeTo(2, .01),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(PageView));
    await tester.pump(const Duration(milliseconds: 100));
    expect(selected, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'selection follows stable id across same-count reorder, addition and removal',
    (tester) async {
      final image = MemoryImage(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
      var ids = ['a', 'b'];
      String? selected;
      Widget card() => MaterialApp(
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 361,
              child: TopicCard(
                activities: [
                  for (final id in ids)
                    TopicActivity(id: id, title: id, image: image),
                ],
                onActivityTap: (i) => selected = ids[i],
              ),
            ),
          ),
        ),
      );
      Future<void> expectSelected(int index, String id) async {
        await tester.pumpWidget(card());
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        final pager = tester.widget<PageView>(find.byType(PageView));
        expect(pager.controller!.page, closeTo(index + 1, .001));
        await tester.tap(find.byType(PageView));
        await tester.pump();
        expect(selected, id);
      }

      await expectSelected(0, 'a');
      ids = ['b', 'a'];
      await expectSelected(1, 'a');
      ids = ['c', 'b', 'a'];
      await expectSelected(2, 'a');
      ids = ['c', 'a'];
      await expectSelected(1, 'a');
      ids = ['c', 'b'];
      await expectSelected(0, 'c');
      expect(tester.takeException(), isNull);
    },
  );
}
