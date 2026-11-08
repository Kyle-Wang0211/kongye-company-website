import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/aether_prefs.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/auth/mock_auth_service.dart';
import 'package:pocketworld_flutter/i18n/locale_notifier.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/auth/auth_minimal_widgets.dart';
import 'package:pocketworld_flutter/ui/auth/reset_password_view.dart';

class _ResetRecordingService extends MockAuthServiceImpl {
  final resetEmails = <String>[];

  @override
  Future<void> sendPasswordReset(String email) async {
    resetEmails.add(email);
  }
}

void main() {
  for (final locale in [const Locale('zh'), const Locale('en')]) {
    testWidgets(
      'reset displays the sent email unchanged in ${locale.languageCode}',
      (tester) async {
        AetherPrefs.setMockInitialValues({});
        tester.view.physicalSize = const Size(430, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = _ResetRecordingService();
        final user = CurrentUser(service: service);
        final localeNotifier = LocaleNotifier();
        addTearDown(user.dispose);
        addTearDown(localeNotifier.dispose);
        await tester.pumpWidget(
          LocaleScope(
            notifier: localeNotifier,
            child: MaterialApp(
              locale: locale,
              localizationsDelegates: AppL10n.localizationsDelegates,
              supportedLocales: AppL10n.supportedLocales,
              home: ResetPasswordView(currentUser: user),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField),
          '  Member@Example.TEST  ',
        );
        await tester.pump();
        await tester.tap(find.byType(MinimalCta));
        await tester.pumpAndSettle();

        expect(service.resetEmails, ['member@example.test']);
        final expected = locale.languageCode == 'zh'
            ? '我们已向 member@example.test 发送 6 位验证码，请输入验证码继续'
            : 'We sent a 6-digit code to member@example.test. Enter the code to continue.';
        expect(find.text(expected), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                (widget.data?.contains('MEMBER@EXAMPLE.TEST') ?? false),
          ),
          findsNothing,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
