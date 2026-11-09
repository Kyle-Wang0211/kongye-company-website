import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/ui/social/web_profile_edit_page.dart';

void main() {
  Future<void> show(WidgetTester tester, {double width = 900}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: WebProfileEditPage(
          initialProfile: const WebProfileDraft(displayName: '示例', bio: ''),
          save: (_) async => WebProfileSaveResult.pendingReview,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  TextField field(WidgetTester tester, String key) => tester.widget<TextField>(
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField)),
  );

  testWidgets(
    'both fields show backend limits and bio is a boxed multiline area',
    (tester) async {
      await show(tester);
      expect(find.text('2/20'), findsOneWidget);
      expect(find.text('0/160'), findsOneWidget);
      expect(find.text('最多 20 个字符'), findsOneWidget);
      expect(find.text('最多 160 个字符'), findsOneWidget);
      final name = field(tester, 'profile-name');
      final bio = field(tester, 'profile-bio');
      for (final input in [name, bio]) {
        expect(input.decoration!.filled, true);
        expect(input.decoration!.enabledBorder, isA<OutlineInputBorder>());
        expect(input.decoration!.focusedBorder, isA<OutlineInputBorder>());
        expect(
          input.decoration!.floatingLabelBehavior,
          FloatingLabelBehavior.always,
        );
      }
      expect(name.maxLength, 20);
      expect(bio.maxLength, 160);
      expect(bio.minLines, 5);
      expect(bio.maxLines, 5);
      expect(
        tester.getSize(find.byKey(const Key('profile-bio'))).height,
        greaterThan(
          tester.getSize(find.byKey(const Key('profile-name'))).height + 40,
        ),
      );
    },
  );

  testWidgets(
    'live counters and enforcement count graphemes, not emoji code units',
    (tester) async {
      await show(tester);
      const family = '👨‍👩‍👧‍👦';
      await tester.enterText(find.byKey(const Key('profile-name')), '$family李');
      await tester.pump();
      expect(find.text('2/20'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('profile-name')),
        List.filled(21, family).join(),
      );
      await tester.pump();
      expect(
        field(tester, 'profile-name').controller!.text.characters.length,
        20,
      );
      expect(find.text('20/20'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('profile-bio')));
      await tester.enterText(
        find.byKey(const Key('profile-bio')),
        List.filled(161, '汉').join(),
      );
      await tester.pump();
      expect(
        field(tester, 'profile-bio').controller!.text.characters.length,
        160,
      );
      expect(find.text('160/160'), findsOneWidget);
    },
  );

  testWidgets(
    '390px form retains labels, counters and multiline bounds without overflow',
    (tester) async {
      await show(tester, width: 390);
      final name = field(tester, 'profile-name');
      final bio = field(tester, 'profile-bio');
      expect(name.decoration!.labelText, '昵称');
      expect(bio.decoration!.labelText, '个人简介');
      expect(find.text('2/20'), findsOneWidget);
      expect(find.text('0/160'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('profile-bio'))).width,
        lessThanOrEqualTo(390),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
