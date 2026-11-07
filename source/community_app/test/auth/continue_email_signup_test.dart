import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/auth/auth_models.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/auth/mock_auth_service.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/i18n/locale_notifier.dart';
import 'package:pocketworld_flutter/ui/auth/auth_minimal_widgets.dart';
import 'package:pocketworld_flutter/ui/auth/email_sign_in_view.dart';
import 'package:pocketworld_flutter/ui/auth/otp_verification_view.dart';

class _NoSendingService extends MockAuthServiceImpl {
  int sends = 0;
  @override
  Future<AuthenticatedUser> signUp(SignUpRequest request) async {
    sends++;
    throw StateError('Continuing verification must not sign up');
  }

  @override
  Future<void> resendEmailOtp({required String email}) async {
    sends++;
    throw StateError('Continuing verification must not resend');
  }
}

Widget _app(CurrentUser user) {
  final locale = LocaleNotifier();
  addTearDown(locale.dispose);
  return LocaleScope(
    notifier: locale,
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: EmailSignUpPage(currentUser: user),
    ),
  );
}

void main() {
  testWidgets('continue pending registration opens verifier without sending', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _NoSendingService();
    final user = CurrentUser(service: service);
    addTearDown(user.dispose);
    await tester.pumpWidget(_app(user));
    final link = find.byKey(
      const ValueKey('continue-email-signup-verification'),
    );
    expect(tester.widget<MinimalLink>(link).onTap, isNull);
    await tester.enterText(
      find.byType(TextField).first,
      'synthetic@example.invalid',
    );
    await tester.pump();
    expect(tester.widget<MinimalLink>(link).onTap, isNull);
    await tester.tap(find.byKey(const ValueKey('auth-policy-consent')));
    await tester.pump();
    // No password is entered: this resumes a registration already sent.
    expect(tester.widget<MinimalLink>(link).onTap, isNotNull);
    await tester.tap(link);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final view = tester.widget<OtpVerificationView>(
      find.byType(OtpVerificationView),
    );
    expect(view.email, 'synthetic@example.invalid');
    expect(service.sends, 0);
    expect(view.hasPolicyConsent?.call(), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('changing email revokes consent for continuation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _NoSendingService();
    final user = CurrentUser(service: service);
    addTearDown(user.dispose);
    await tester.pumpWidget(_app(user));
    await tester.enterText(find.byType(TextField).first, 'one@example.invalid');
    await tester.tap(find.byKey(const ValueKey('auth-policy-consent')));
    await tester.pump();
    final link = find.byKey(
      const ValueKey('continue-email-signup-verification'),
    );
    expect(tester.widget<MinimalLink>(link).onTap, isNotNull);
    await tester.enterText(find.byType(TextField).first, 'two@example.invalid');
    await tester.pump();
    expect(tester.widget<MinimalLink>(link).onTap, isNull);
    expect(service.sends, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
