import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocketworld_flutter/config/backend_deployment.dart';
import 'package:pocketworld_flutter/i18n/locale_notifier.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/auth/auth_minimal_widgets.dart';
import 'package:pocketworld_flutter/ui/auth/auth_root_view.dart';
import 'package:pocketworld_flutter/ui/auth/phone_sign_in_view.dart';
import 'package:pocketworld_flutter/ui/auth/phone_country_picker.dart';
import 'auth_login_prefix_test.dart' show mountLogin, RecordingProvider;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'actual root SMS route supports phone keyboard and back navigation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await mountLogin(tester, RecordingProvider(), BackendRegion.china);
      final smsLink = find.text('SIGN IN WITH SMS CODE');
      await tester.ensureVisible(smsLink);
      await tester.tap(smsLink);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final form = find.byType(PhoneSignInView);
      expect(form, findsOneWidget);
      expect(
        find.ancestor(of: form, matching: find.byType(Scaffold)),
        findsOneWidget,
      );
      expect(
        find.ancestor(of: form, matching: find.byType(SafeArea)),
        findsOneWidget,
      );
      expect(
        find.ancestor(of: form, matching: find.byType(SingleChildScrollView)),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('+86'), findsNothing);
      expect(
        find.byKey(const ValueKey('phone-country-selector')),
        findsNothing,
      );
      await tester.showKeyboard(find.byType(TextField));
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.enterText(find.byType(TextField), '13800000000');
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(AuthTopBarBack));
      await tester.pumpAndSettle();
      expect(find.byType(PhoneSignInView), findsNothing);
      expect(find.byType(AuthRootView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('country search remains usable in landscape with keyboard', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final locale = LocaleNotifier();
    await locale.set(const Locale('en'));
    addTearDown(locale.dispose);
    await tester.pumpWidget(
      LocaleScope(
        notifier: locale,
        child: AnimatedBuilder(
          animation: locale,
          builder: (_, __) => MaterialApp(
            locale: locale.locale,
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showPhoneCountryPicker(context),
                  child: const Text('Countries'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Countries'));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('phone-country-search'));
    await tester.showKeyboard(search);
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    await tester.enterText(search, 'United States');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final us = find.byKey(const ValueKey('phone-country-US'));
    expect(us, findsOneWidget);
    expect(tester.getRect(us).height, greaterThan(40));
    expect(tester.getCenter(us).dy, lessThan(140));
    await tester.tap(us);
    await tester.pumpAndSettle();
    expect(search, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
