import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/auth/mock_auth_service.dart';
import 'package:pocketworld_flutter/i18n/locale_notifier.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/auth/phone_sign_in_view.dart';

void expectInlineSelector(WidgetTester tester) {
  final fieldFinder = find.byType(TextField).first;
  final field = tester.widget<TextField>(fieldFinder);
  expect(field.decoration!.prefixIcon, isNotNull);
  final selector = find.byKey(const ValueKey('phone-country-selector'));
  expect(find.descendant(of: fieldFinder, matching: selector), findsOneWidget);
  final fieldRect = tester.getRect(fieldFinder);
  final selectorRect = tester.getRect(selector);
  expect(selectorRect.left, greaterThanOrEqualTo(fieldRect.left));
  expect(selectorRect.right, lessThanOrEqualTo(fieldRect.right));
  expect(selectorRect.center.dy, closeTo(fieldRect.center.dy, 1));
  final editable = find.descendant(
    of: fieldFinder,
    matching: find.byType(EditableText),
  );
  expect(tester.getSize(editable).width, greaterThanOrEqualTo(150));
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets(
      'signup country selector is inside phone input at text scale $scale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final user = CurrentUser(service: MockAuthServiceImpl());
        final locale = LocaleNotifier();
        addTearDown(user.dispose);
        addTearDown(locale.dispose);
        await user.bootstrap();
        await tester.pumpWidget(
          LocaleScope(
            notifier: locale,
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppL10n.localizationsDelegates,
              supportedLocales: AppL10n.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: PhoneAuthPage(
                currentUser: user,
                intent: PhoneIntent.signUp,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expectInlineSelector(tester);
        final selector = find.byKey(const ValueKey('phone-country-selector'));
        await tester.ensureVisible(selector);
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('phone-country-search')),
          'Finland',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('phone-country-FI')));
        await tester.pumpAndSettle();
        expectInlineSelector(tester);
        expect(find.textContaining('+358'), findsOneWidget);
        expect(find.text('Finland'), findsNothing);
        expect(find.byTooltip('Finland +358'), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, '401234567');
        await tester.pump();
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          '401234567',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
