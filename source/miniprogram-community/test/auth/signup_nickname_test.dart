import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/auth/auth_models.dart';
import 'package:pocketworld_flutter/auth/auth_error.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/auth/mock_auth_service.dart';
import 'package:pocketworld_flutter/i18n/locale_notifier.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/auth/auth_minimal_widgets.dart';
import 'package:pocketworld_flutter/ui/auth/auth_shared_widgets.dart';
import 'package:pocketworld_flutter/ui/auth/email_sign_in_view.dart';
import 'package:pocketworld_flutter/ui/auth/phone_sign_in_view.dart';

class _Service extends MockAuthServiceImpl {
  final requests = <SignUpRequest>[];
  @override
  Future<AuthenticatedUser> signUp(SignUpRequest request) {
    requests.add(request);
    throw const AuthException(AuthErrorKind.providerUnavailable);
  }
}

void main() {
  testWidgets('registration requires nickname and passes trimmed name', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _Service();
    final user = CurrentUser(service: service);
    final locale = LocaleNotifier();
    addTearDown(user.dispose);
    addTearDown(locale.dispose);
    await tester.pumpWidget(
      LocaleScope(
        notifier: locale,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: EmailSignUpPage(currentUser: user),
        ),
      ),
    );
    final nickname = find.descendant(
      of: find.byKey(const ValueKey('signup-nickname')),
      matching: find.byType(TextField),
    );
    expect(nickname, findsOneWidget);
    await tester.enterText(
      find.byType(TextField).first,
      'synthetic@example.invalid',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('signup-password')),
        matching: find.byType(TextField),
      ),
      'Synthetic-123',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('signup-confirm-password')),
        matching: find.byType(TextField),
      ),
      'Synthetic-123',
    );
    final consent = find.byKey(const ValueKey('auth-policy-consent'));
    if (consent.evaluate().isNotEmpty) await tester.tap(consent);
    await tester.pump();
    expect(
      tester.widget<MinimalCta>(find.byType(MinimalCta).first).enabled,
      isFalse,
    );
    await tester.enterText(nickname, '  测试昵称  ');
    await tester.pump();
    if (consent.evaluate().isNotEmpty) await tester.tap(consent);
    await tester.pump();
    expect(
      tester.widget<MinimalCta>(find.byType(MinimalCta).first).enabled,
      isTrue,
    );
    await tester.tap(find.byType(MinimalCta).first);
    await tester.pumpAndSettle();
    expect(service.requests, hasLength(1));
    expect((service.requests.single as SignUpRequestEmail).displayName, '测试昵称');
  });

  testWidgets(
    'phone registration requires a nonblank nickname before sending',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final user = CurrentUser(service: _Service());
      final locale = LocaleNotifier();
      addTearDown(user.dispose);
      addTearDown(locale.dispose);
      await tester.pumpWidget(
        LocaleScope(
          notifier: locale,
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            home: Scaffold(
              body: PhoneSignInView(
                currentUser: user,
                intent: PhoneIntent.signUp,
              ),
            ),
          ),
        ),
      );
      final fields = find.byType(TextField);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('phone-signup-number')),
          matching: fields,
        ),
        '13800000000',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('signup-password')),
          matching: fields,
        ),
        'Synthetic-123',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('signup-confirm-password')),
          matching: fields,
        ),
        'Synthetic-123',
      );
      final consent = find.byKey(const ValueKey('auth-policy-consent'));
      await tester.pump();
      if (consent.evaluate().isNotEmpty) await tester.tap(consent);
      await tester.pump();
      expect(
        tester
            .widget<AuthPrimaryButton>(find.byType(AuthPrimaryButton))
            .isEnabled,
        isFalse,
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('phone-signup-nickname')),
          matching: fields,
        ),
        '电话昵称',
      );
      await tester.pump();
      if (consent.evaluate().isNotEmpty) await tester.tap(consent);
      await tester.pump();
      expect(
        tester
            .widget<AuthPrimaryButton>(find.byType(AuthPrimaryButton))
            .isEnabled,
        isTrue,
      );
    },
  );

  testWidgets('verification uses exactly six mobile digit boxes', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    final shake = AnimationController(vsync: tester);
    addTearDown(shake.dispose);
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OtpBoxRow(
            controller: controller,
            focusNode: focus,
            otpLength: 6,
            shake: shake,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.byType(OtpBox), findsNWidgets(6));
    await tester.enterText(find.byType(TextField), '1234567');
    await tester.pump();
    expect(controller.text, '123456');
  });
}
