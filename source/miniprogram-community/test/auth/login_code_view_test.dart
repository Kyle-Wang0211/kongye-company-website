import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/auth/auth_error.dart';
import 'package:pocketworld_flutter/auth/auth_models.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/auth/mock_auth_service.dart';
import 'package:pocketworld_flutter/i18n/locale_notifier.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/auth/auth_shared_widgets.dart';
import 'package:pocketworld_flutter/ui/auth/login_code_view.dart';

class _Service extends MockAuthServiceImpl {
  final sends = <String>[];
  final requests = <SignInRequest>[];
  AuthErrorKind fail = AuthErrorKind.invalidVerificationCode;
  Completer<AuthenticatedUser>? pendingLogin;
  @override
  Future<PhoneVerificationChallenge> startPhoneVerification(
    String phone, {
    bool forSignUp = false,
  }) async {
    expect(forSignUp, isFalse);
    sends.add(phone);
    return super.startPhoneVerification(phone, forSignUp: forSignUp);
  }

  @override
  Future<AuthenticatedUser> signIn(SignInRequest request) async {
    requests.add(request);
    if (pendingLogin != null) return pendingLogin!.future;
    throw AuthException(fail);
  }

  @override
  Future<AuthenticatedUser> signUp(SignUpRequest request) async =>
      throw StateError('Login must never sign up');
}

void main() {
  testWidgets('back cancels pending login before reverse transition disposal', (
    t,
  ) async {
    final service = _Service()..pendingLogin = Completer<AuthenticatedUser>();
    final user = CurrentUser(service: service);
    final locale = LocaleNotifier();
    final navigator = GlobalKey<NavigatorState>();
    addTearDown(user.dispose);
    addTearDown(locale.dispose);
    await t.pumpWidget(
      LocaleScope(
        notifier: locale,
        child: MaterialApp(
          navigatorKey: navigator,
          locale: const Locale('en'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: const Scaffold(body: Text('entry')),
        ),
      ),
    );
    navigator.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            LoginCodeView(currentUser: user, target: '+8613800000000'),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '123456');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('login-code-submit')));
    await t.pump();
    expect(user.pendingSignInToken, isNotNull);
    navigator.currentState!.pop();
    await t.pump(const Duration(milliseconds: 16));
    expect(
      find.byType(LoginCodeView, skipOffstage: false),
      findsOneWidget,
      reason: 'The popped route remains mounted during its reverse transition',
    );
    expect(
      user.pendingSignInToken,
      isNull,
      reason: 'Back must cancel before route disposal',
    );
    service.pendingLogin!.complete(
      const AuthenticatedUser(
        id: InternalUserID('synthetic-back-race'),
        phone: '+8613800000000',
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 40));
    expect(user.isSignedIn, isFalse);
    await t.pumpAndSettle();
    expect(find.byType(LoginCodeView, skipOffstage: false), findsNothing);
  });
  testWidgets(
    'leaving login code route cancels only its pending verification',
    (t) async {
      final service = _Service()..pendingLogin = Completer<AuthenticatedUser>();
      final user = CurrentUser(service: service);
      final locale = LocaleNotifier();
      addTearDown(user.dispose);
      addTearDown(locale.dispose);
      await t.pumpWidget(
        LocaleScope(
          notifier: locale,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            home: LoginCodeView(currentUser: user, target: '+8613800000000'),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '123456');
      await t.pump();
      await t.tap(find.byKey(const ValueKey('login-code-submit')));
      await t.pump();
      expect(user.pendingSignInToken, isNotNull);
      await t.pumpWidget(const SizedBox());
      service.pendingLogin!.complete(
        const AuthenticatedUser(
          id: InternalUserID('synthetic-cancelled'),
          phone: '+8613800000000',
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(user.isSignedIn, isFalse);
      expect(user.pendingSignInToken, isNull);
    },
  );
  testWidgets(
    'phone login uses six boxes, immutable target, localized errors and cooldown',
    (t) async {
      t.view.physicalSize = const Size(900, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final service = _Service();
      final user = CurrentUser(service: service);
      final locale = LocaleNotifier();
      addTearDown(user.dispose);
      addTearDown(locale.dispose);
      const target = '+8613800000000';
      await t.pumpWidget(
        LocaleScope(
          notifier: locale,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            home: LoginCodeView(currentUser: user, target: target),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(service.sends, [target]);
      expect(find.text(target), findsOneWidget);
      expect(find.byType(OtpBox), findsNWidgets(6));
      final resend = find.byKey(const ValueKey('login-code-resend'));
      expect(t.widget<TextButton>(resend).onPressed, isNull);
      await t.enterText(find.byType(TextField), '1234567');
      await t.pump();
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        '123456',
      );
      await t.tap(find.byKey(const ValueKey('login-code-submit')));
      await t.pumpAndSettle();
      expect(service.requests, hasLength(1));
      final dynamic request = service.requests.single;
      expect(request.phoneNumber, target);
      expect(request.code, '123456');
      expect(user.isSignedIn, isFalse);
      expect(
        find.text('The code is incorrect or has expired. Please try again.'),
        findsOneWidget,
      );
      await t.pump(const Duration(seconds: 60));
      await t.pump();
      expect(t.widget<TextButton>(resend).onPressed, isNotNull);
      service.fail = AuthErrorKind.network;
      await t.tap(find.byKey(const ValueKey('login-code-submit')));
      await t.pumpAndSettle();
      expect(
        find.text(
          'The request timed out or could not connect. Please try again.',
        ),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
}
