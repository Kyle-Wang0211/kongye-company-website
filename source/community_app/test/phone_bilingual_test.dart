import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/auth/mock_auth_service.dart';
import 'package:pocketworld_flutter/auth/phone_country_catalog.dart';
import 'package:pocketworld_flutter/i18n/locale_notifier.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/auth/auth_minimal_widgets.dart';
import 'package:pocketworld_flutter/ui/auth/phone_sign_in_view.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('all 245 region names are complete in Chinese and English', () {
    expect(phoneCountries, hasLength(245));
    expect(phoneCountryForIso('DE').name(true), '德国');
    expect(phoneCountryForIso('FR').name(true), '法国');
    expect(phoneCountryForIso('AC').name(true), '阿森松岛');
    for (final country in phoneCountries) {
      expect(country.englishName.trim(), isNotEmpty, reason: country.iso);
      expect(country.chineseName.trim(), isNotEmpty, reason: country.iso);
      expect(country.englishName, isNot(country.iso));
      expect(
        RegExp(r'[\u3400-\u9FFF]').hasMatch(country.chineseName),
        isTrue,
        reason: country.iso,
      );
    }
  });
  testWidgets(
    'one global language switch updates picker and preserves form state',
    (tester) async {
      final locale = LocaleNotifier();
      await locale.set(const Locale('en'));
      final user = CurrentUser(service: MockAuthServiceImpl());
      addTearDown(locale.dispose);
      addTearDown(user.dispose);
      await user.bootstrap();
      await tester.pumpWidget(
        LocaleScope(
          notifier: locale,
          child: AnimatedBuilder(
            animation: locale,
            builder: (_, __) => MaterialApp(
              locale: locale.locale,
              localizationsDelegates: AppL10n.localizationsDelegates,
              supportedLocales: AppL10n.supportedLocales,
              home: PhoneAuthPage(
                currentUser: user,
                intent: PhoneIntent.signUp,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '13800000000');
      await tester.tap(find.byKey(const ValueKey('phone-country-selector')));
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('phone-country-search'));
      await tester.enterText(search, 'Germany');
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('phone-country-DE')),
          matching: find.text('Germany'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byType(CompactLanguageToggle));
      await tester.pumpAndSettle();
      expect(locale.locale.languageCode, 'zh');
      expect(find.text('德国'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: search, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        'Germany',
      );
      expect(
        tester.widget<TextField>(search).decoration!.hintText,
        '搜索国家、地区或区号',
      );
      await tester.enterText(search, '法国');
      await tester.pump();
      expect(find.byKey(const ValueKey('phone-country-FR')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('phone-country-FR')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('法国 +33'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '13800000000',
      );
      expect(find.textContaining('手机号示例：'), findsOneWidget);
      await tester.tap(find.byType(CompactLanguageToggle));
      await tester.pumpAndSettle();
      expect(locale.locale.languageCode, 'en');
      expect(find.byTooltip('France +33'), findsOneWidget);
      expect(find.textContaining('Mobile number example:'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '13800000000',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
