import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/aether_prefs.dart';
import 'package:pocketworld_flutter/auth/auth_error.dart';
import 'package:pocketworld_flutter/auth/auth_models.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/auth/mock_auth_service.dart';
import 'package:pocketworld_flutter/i18n/locale_notifier.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/auth/auth_minimal_widgets.dart';
import 'package:pocketworld_flutter/ui/auth/auth_root_view.dart';
import 'package:pocketworld_flutter/ui/auth/reset_password_view.dart';

class _RecoveryService extends MockAuthServiceImpl {
  final sent = <String>[];
  final verified = <(String, String)>[];
  final completed = <(String, String, String)>[];
  Completer<String>? pendingVerification;
  Completer<void>? pendingCompletion;
  AuthException? verifyError;
  AuthException? completeError;
  AuthException? sendError;
  int signIns = 0;
  int legacyResets = 0;

  @override
  Future<void> sendPasswordReset(String email) async {
    sent.add(email);
    if (sendError case final error?) throw error;
  }

  @override
  Future<String> verifyPasswordResetCode({
    required String email,
    required String token,
  }) async {
    verified.add((email, token));
    if (verifyError case final error?) throw error;
    if (pendingVerification case final pending?) return await pending.future;
    return 'synthetic-recovery-capability';
  }

  @override
  Future<void> completePasswordReset({
    required String email,
    required String resetToken,
    required String newPassword,
  }) async {
    completed.add((email, resetToken, newPassword));
    if (completeError case final error?) throw error;
    await pendingCompletion?.future;
  }

  @override
  Future<AuthenticatedUser> signIn(SignInRequest request) async {
    signIns++;
    throw StateError('Recovery must never sign in');
  }

  Future<AuthenticatedUser> resetPasswordWithOtp({
    required String email,
    required String token,
    required String newPassword,
  }) async {
    legacyResets++;
    throw StateError('Legacy combined reset must never be used');
  }
}

final _secureFields = find.byWidgetPredicate(
  (w) => w is TextField && w.obscureText,
);

Future<CurrentUser> _mount(
  WidgetTester tester,
  _RecoveryService service, {
  String language = 'en',
  bool realAuthRoot = false,
}) async {
  AetherPrefs.setMockInitialValues({});
  tester.view.physicalSize = const Size(430, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final user = CurrentUser(service: service);
  final notifier = LocaleNotifier();
  addTearDown(user.dispose);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    LocaleScope(
      notifier: notifier,
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: realAuthRoot
            ? AuthRootView(currentUser: user)
            : Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ResetPasswordView(currentUser: user),
                      ),
                    ),
                    child: const Text('Synthetic login'),
                  ),
                ),
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (realAuthRoot) {
    await tester.tap(find.byKey(const ValueKey('auth-forgot-password')));
  } else {
    await tester.tap(find.text('Synthetic login'));
  }
  await tester.pumpAndSettle();
  return user;
}

Future<void> _send(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), '  Member@Example.TEST  ');
  await tester.pump();
  await tester.tap(find.byType(MinimalCta));
  await tester.pumpAndSettle();
}

Future<void> _verify(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), '123456');
  await tester.pump();
  await tester.tap(find.byType(MinimalCta));
  await tester.pump();
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  for (final language in ['en', 'zh']) {
    testWidgets(
      'real auth root leaves recovery errors to reset route in $language',
      (tester) async {
        final service = _RecoveryService()
          ..verifyError = const AuthException(
            AuthErrorKind.invalidVerificationCode,
          );
        final user = await _mount(
          tester,
          service,
          language: language,
          realAuthRoot: true,
        );
        await _send(tester);
        await _verify(tester);
        await tester.pumpAndSettle();
        final message = language == 'en'
            ? 'The code is incorrect or has expired. Please try again.'
            : '验证码错误或已过期，请重试';
        expect(
          [
            find.byType(AlertDialog).evaluate().length,
            user.lastError?.kind,
            find.text(message).evaluate().length,
          ],
          [0, AuthErrorKind.invalidVerificationCode, 1],
          reason:
              'The covered login route must not show a dialog or consume the reset error',
        );
        expect(find.byType(ResetPasswordView), findsOneWidget);
        expect(_secureFields, findsNothing);
        await _dispose(tester);
      },
    );

    testWidgets(
      'server verification gates separate password page in $language',
      (tester) async {
        final service = _RecoveryService()
          ..pendingVerification = Completer<String>();
        final user = await _mount(tester, service, language: language);
        await _send(tester);
        expect(service.sent, ['member@example.test']);
        expect(_secureFields, findsNothing);
        expect(
          tester.widget<MinimalCta>(find.byType(MinimalCta)).enabled,
          isFalse,
        );
        await _verify(tester);
        // Repeated taps while the server is pending cannot submit twice or advance.
        final cta = tester.widget<MinimalCta>(find.byType(MinimalCta));
        cta.onTap();
        await tester.pump();
        expect(service.verified, [('member@example.test', '123456')]);
        expect(_secureFields, findsNothing);
        expect(user.isSignedIn, isFalse);
        service.pendingVerification!.complete('synthetic-recovery-capability');
        await tester.pumpAndSettle();
        expect(_secureFields, findsNWidgets(2));
        expect(find.byType(TextField), findsNWidgets(2));
        await tester.enterText(_secureFields.at(0), 'short');
        await tester.enterText(_secureFields.at(1), 'short');
        await tester.pump();
        expect(
          tester.widget<MinimalCta>(find.byType(MinimalCta)).enabled,
          isFalse,
        );
        expect(
          find.text(
            language == 'en'
                ? 'Use at least 8 characters for your new password.'
                : '新密码至少需要 8 位',
          ),
          findsOneWidget,
        );
        await tester.enterText(_secureFields.at(0), 'SyntheticPass123');
        await tester.enterText(_secureFields.at(1), 'DifferentPass123');
        await tester.pump();
        expect(
          tester.widget<MinimalCta>(find.byType(MinimalCta)).enabled,
          isFalse,
        );
        expect(
          find.text(
            language == 'en' ? 'The passwords do not match.' : '两次输入的密码不一致',
          ),
          findsOneWidget,
        );
        await tester.enterText(_secureFields.at(1), 'SyntheticPass123');
        await tester.pump();
        await tester.tap(find.byType(MinimalCta));
        await tester.pumpAndSettle();
        expect(service.completed, [
          (
            'member@example.test',
            'synthetic-recovery-capability',
            'SyntheticPass123',
          ),
        ]);
        expect(service.signIns, 0);
        expect(service.legacyResets, 0);
        expect(user.isSignedIn, isFalse);
        expect(find.byType(ResetPasswordView), findsNothing);
        expect(find.text('Synthetic login'), findsOneWidget);
        await _dispose(tester);
      },
    );

    testWidgets(
      'invalid OTP stays before password and localizes error in $language',
      (tester) async {
        final service = _RecoveryService()
          ..verifyError = const AuthException(
            AuthErrorKind.invalidVerificationCode,
          );
        await _mount(tester, service, language: language);
        await _send(tester);
        await _verify(tester);
        await tester.pumpAndSettle();
        expect(_secureFields, findsNothing);
        expect(service.completed, isEmpty);
        expect(
          find.text(
            language == 'en'
                ? 'The code is incorrect or has expired. Please try again.'
                : '验证码错误或已过期，请重试',
          ),
          findsOneWidget,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        await _dispose(tester);
      },
    );
  }

  testWidgets('timeout and late success cannot reveal password page', (
    tester,
  ) async {
    final service = _RecoveryService()
      ..pendingVerification = Completer<String>();
    await _mount(tester, service);
    await _send(tester);
    await _verify(tester);
    await tester.pump(const Duration(seconds: 31));
    await tester.pump();
    expect(_secureFields, findsNothing);
    expect(
      find.text(
        'The request timed out or could not connect. Please try again.',
      ),
      findsOneWidget,
    );
    service.pendingVerification!.complete('late-synthetic-token');
    await tester.pumpAndSettle();
    expect(_secureFields, findsNothing);
    expect(service.completed, isEmpty);
    await _dispose(tester);
  });

  testWidgets('resend respects 60 seconds and cancellation releases timer', (
    tester,
  ) async {
    final service = _RecoveryService();
    await _mount(tester, service);
    await _send(tester);
    final link = find.byType(MinimalLink);
    expect(tester.widget<MinimalLink>(link).onTap, isNull);
    await tester.pump(const Duration(seconds: 59));
    expect(tester.widget<MinimalLink>(link).onTap, isNull);
    await tester.pump(const Duration(seconds: 1));
    tester.widget<MinimalLink>(link).onTap!();
    await tester.pump();
    expect(service.sent, ['member@example.test', 'member@example.test']);
    expect(tester.widget<MinimalLink>(link).onTap, isNull);
    await tester.tap(find.byType(AuthTopBarBack));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic login'), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets(
    'completion failure stays on password page, no sign in or duplicate completion',
    (tester) async {
      final service = _RecoveryService()..pendingCompletion = Completer<void>();
      final user = await _mount(tester, service);
      await _send(tester);
      await _verify(tester);
      await tester.pumpAndSettle();
      await tester.enterText(_secureFields.at(0), 'SyntheticPass123');
      await tester.enterText(_secureFields.at(1), 'SyntheticPass123');
      await tester.pump();
      final cta = tester.widget<MinimalCta>(find.byType(MinimalCta));
      cta.onTap();
      cta.onTap();
      await tester.pump();
      expect(service.completed, hasLength(1));
      service.pendingCompletion!.completeError(
        const AuthException(AuthErrorKind.network),
      );
      await tester.pumpAndSettle();
      expect(_secureFields, findsNWidgets(2));
      expect(
        find.text(
          'The request timed out or could not connect. Please try again.',
        ),
        findsOneWidget,
      );
      expect(service.signIns, 0);
      expect(user.isSignedIn, isFalse);
      await _dispose(tester);
    },
  );

  testWidgets('failed send stays on email step with localized retry error', (
    tester,
  ) async {
    final service = _RecoveryService()
      ..sendError = const AuthException(AuthErrorKind.rateLimited);
    await _mount(tester, service);
    await _send(tester);
    expect(_secureFields, findsNothing);
    expect(
      find.text('Too many requests. Please try again later.'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).keyboardType,
      TextInputType.emailAddress,
    );
    expect(service.verified, isEmpty);
    await _dispose(tester);
  });
  testWidgets('cancelled verification ignores late success', (tester) async {
    final service = _RecoveryService()
      ..pendingVerification = Completer<String>();
    final user = await _mount(tester, service);
    await _send(tester);
    await _verify(tester);
    await tester.tap(find.byType(AuthTopBarBack));
    await tester.pumpAndSettle();
    service.pendingVerification!.complete('late-synthetic-token');
    await tester.pumpAndSettle();
    expect(find.text('Synthetic login'), findsOneWidget);
    expect(find.byType(ResetPasswordView), findsNothing);
    expect(user.isSignedIn, isFalse);
    expect(service.completed, isEmpty);
    await _dispose(tester);
  });
}
