import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/auth/mock_auth_service.dart';
import 'package:pocketworld_flutter/i18n/locale_notifier.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/auth/email_sign_in_view.dart';
import 'package:pocketworld_flutter/ui/auth/phone_sign_in_view.dart';
import 'package:pocketworld_flutter/ui/auth/auth_shared_widgets.dart';

Future<void> mount(WidgetTester tester, {required bool signup}) async {
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
        home: signup
            ? EmailSignUpPage(currentUser: user)
            : Scaffold(
                body: SingleChildScrollView(
                  child: PhoneSignInView(
                    currentUser: user,
                    intent: PhoneIntent.signIn,
                  ),
                ),
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('SMS login has a single input and no fixed country selector', (
    tester,
  ) async {
    await mount(tester, signup: false);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byKey(const ValueKey('phone-country-selector')), findsNothing);
    expect(find.text('+86'), findsNothing);
    await tester.enterText(find.byType(TextField), '1' * 100);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text.length,
      64,
    );
    await tester.enterText(find.byType(TextField), '+44 7400 123456');
    await tester.pump();
    expect(
      tester
          .widget<AuthPrimaryButton>(find.byType(AuthPrimaryButton))
          .isEnabled,
      isFalse,
    );
    await tester.enterText(find.byType(TextField), '13800000000');
    await tester.pump();
    expect(
      tester
          .widget<AuthPrimaryButton>(find.byType(AuthPrimaryButton))
          .isEnabled,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'phone signup is reachable with CN default and searchable US selection',
    (tester) async {
      await mount(tester, signup: true);
      final link = find.text('Sign up with phone'.toUpperCase());
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      final selector = find.byKey(const ValueKey('phone-country-selector'));
      expect(selector, findsOneWidget);
      expect(find.textContaining('🇨🇳'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '13800000000');
      await tester.pump();
      expect(
        tester
            .widget<AuthPrimaryButton>(find.byType(AuthPrimaryButton))
            .isEnabled,
        isTrue,
      );
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('phone-country-search')),
        'United States',
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('phone-country-US')), findsOneWidget);
      expect(find.byKey(const ValueKey('phone-country-CN')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('phone-country-US')));
      await tester.pumpAndSettle();
      expect(find.textContaining('🇺🇸'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '+1 201 555 0123');
      await tester.pump();
      expect(
        tester
            .widget<AuthPrimaryButton>(find.byType(AuthPrimaryButton))
            .isEnabled,
        isFalse,
      );
      expect(find.textContaining('not yet available'), findsOneWidget);
      expect(find.textContaining('Mobile number example:'), findsOneWidget);
      expect(find.textContaining('Canonical'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
