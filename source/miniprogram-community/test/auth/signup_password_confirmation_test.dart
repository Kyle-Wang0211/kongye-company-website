import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/auth/auth_error.dart';
import 'package:pocketworld_flutter/auth/auth_models.dart';
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
  int sends = 0;
  @override
  Future<PhoneVerificationChallenge> startPhoneVerification(
    String number, {
    bool forSignUp = false,
  }) {
    sends++;
    return super.startPhoneVerification(number, forSignUp: forSignUp);
  }

  @override
  Future<PhoneVerificationChallenge> startPhoneSignup({
    required String phoneNumber,
    required String password,
    String? displayName,
  }) {
    sends++;
    return Future.value(
      PhoneVerificationChallenge(
        verificationID: 'synthetic',
        phoneNumber: phoneNumber,
      ),
    );
  }

  @override
  Future<AuthenticatedUser> signUp(SignUpRequest request) async {
    requests.add(request);
    throw const AuthException(AuthErrorKind.providerUnavailable);
  }
}

class _DelayedSignup extends _Service {
  final pending = Completer<PhoneVerificationChallenge>();
  final starts = <({String phone, String password, String? name})>[];
  @override
  Future<PhoneVerificationChallenge> startPhoneSignup({
    required String phoneNumber,
    required String password,
    String? displayName,
  }) {
    starts.add((phone: phoneNumber, password: password, name: displayName));
    return pending.future;
  }
}

Finder field(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(TextField),
);
Future<void> consent(WidgetTester t) async {
  await t.pump();
  final f = find.byKey(const ValueKey('auth-policy-consent'));
  if (f.evaluate().isNotEmpty) {
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pump();
  }
}

Future<void> _mount(WidgetTester t, _Service service, bool phone) async {
  t.view.physicalSize = const Size(900, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final user = CurrentUser(service: service);
  final locale = LocaleNotifier();
  addTearDown(user.dispose);
  addTearDown(locale.dispose);
  await t.pumpWidget(
    LocaleScope(
      notifier: locale,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: phone
            ? Scaffold(
                body: PhoneSignInView(
                  currentUser: user,
                  intent: PhoneIntent.signUp,
                ),
              )
            : EmailSignUpPage(currentUser: user),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'pending phone signup freezes fields and binds verified credentials',
    (t) async {
      final service = _DelayedSignup();
      await _mount(t, service, true);
      await t.enterText(field('phone-signup-number'), '13800000000');
      await t.enterText(field('phone-signup-nickname'), 'Agreed name');
      await t.enterText(field('signup-password'), 'Agreed-password-123');
      await t.enterText(
        field('signup-confirm-password'),
        'Agreed-password-123',
      );
      await consent(t);
      await t.tap(find.byType(AuthPrimaryButton).first);
      await t.pump();
      expect(service.starts.single, (
        phone: '+8613800000000',
        password: 'Agreed-password-123',
        name: 'Agreed name',
      ));
      for (final key in [
        'phone-signup-number',
        'phone-signup-nickname',
        'signup-password',
        'signup-confirm-password',
      ]) {
        expect(t.widget<TextField>(field(key)).enabled, isFalse);
      }
      final selector = find.byKey(const ValueKey('phone-country-selector'));
      if (selector.evaluate().isNotEmpty) {
        expect(t.widget<TextButton>(selector).onPressed, isNull);
      }
      // Even direct controller changes cannot replace the accepted request payload.
      t.widget<TextField>(field('phone-signup-number')).controller!.text =
          '13900000000';
      t.widget<TextField>(field('phone-signup-nickname')).controller!.text =
          'Changed name';
      t.widget<TextField>(field('signup-password')).controller!.text =
          'Changed-password-123';
      t.widget<TextField>(field('signup-confirm-password')).controller!.text =
          'Changed-password-123';
      service.pending.complete(
        const PhoneVerificationChallenge(
          verificationID: 'synthetic-bound',
          phoneNumber: '+8613800000000',
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, '123456');
      await t.pump();
      await t.tap(find.byType(AuthPrimaryButton).first);
      await t.pumpAndSettle();
      final request = service.requests.single as SignUpRequestPhone;
      expect(request.phoneNumber, '+8613800000000');
      expect(request.password, 'Agreed-password-123');
      expect(request.displayName, 'Agreed name');
    },
  );
  for (final phone in [false, true]) {
    testWidgets(
      '${phone ? 'phone' : 'email'} signup blocks mismatched confirmation and forwards exact password',
      (t) async {
        final service = _Service();
        await _mount(t, service, phone);
        if (phone) {
          await t.enterText(field('phone-signup-number'), '13800000000');
          await t.enterText(field('phone-signup-nickname'), '电话昵称');
        } else {
          await t.enterText(
            find.byType(TextField).first,
            'synthetic@example.invalid',
          );
          await t.enterText(field('signup-nickname'), '测试昵称');
        }
        final password = field('signup-password');
        final confirm = field('signup-confirm-password');
        expect(password, findsOneWidget);
        expect(confirm, findsOneWidget);
        expect(t.widget<TextField>(password).obscureText, isTrue);
        expect(t.widget<TextField>(confirm).obscureText, isTrue);
        await t.enterText(password, ' exact Password-123 ');
        await t.enterText(confirm, 'different-password');
        await consent(t);
        bool enabled() => phone
            ? t
                  .widget<AuthPrimaryButton>(
                    find.byType(AuthPrimaryButton).first,
                  )
                  .isEnabled
            : t.widget<MinimalCta>(find.byType(MinimalCta).first).enabled;
        expect(enabled(), isFalse);
        expect(service.requests, isEmpty);
        expect(service.sends, 0);
        await t.enterText(confirm, ' exact Password-123 ');
        await t.pump();
        expect(enabled(), isTrue);
        await t.tap(
          phone
              ? find.byType(AuthPrimaryButton).first
              : find.byType(MinimalCta).first,
        );
        await t.pumpAndSettle();
        if (phone) {
          expect(service.sends, 1);
          await t.enterText(find.byType(TextField).last, '123456');
          await t.pump();
          await t.tap(find.byType(AuthPrimaryButton).first);
          await t.pumpAndSettle();
        }
        expect(service.requests, hasLength(1));
        expect(
          (service.requests.single as dynamic).password,
          ' exact Password-123 ',
        );
      },
    );
  }
}
