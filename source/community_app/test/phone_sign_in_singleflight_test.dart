import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/auth/auth_models.dart';
import 'package:pocketworld_flutter/auth/mock_auth_service.dart';
import 'package:pocketworld_flutter/auth/auth_error.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/i18n/locale_notifier.dart';
import 'package:pocketworld_flutter/ui/auth/phone_sign_in_view.dart';
import 'package:pocketworld_flutter/ui/auth/auth_shared_widgets.dart';
import 'package:pocketworld_flutter/ui/community/public_work_entry.dart';

const authenticated = AuthenticatedUser(id: InternalUserID('test-account'));
const challenge = PhoneVerificationChallenge(
  verificationID: 'provider-challenge',
  phoneNumber: '+8613800000000',
);

class PendingProvider extends MockAuthServiceImpl {
  final sends = <String>[];
  final sendGates = <Completer<PhoneVerificationChallenge>>[];
  final verifications = <SignInRequest>[];
  final verifyGates = <Completer<AuthenticatedUser>>[];
  int signOuts = 0;
  AuthenticatedUser? session;
  @override
  Future<AuthenticatedUser?> currentUser() async => session;
  @override
  Future<PhoneVerificationChallenge> startPhoneVerification(String phone) {
    sends.add(phone);
    final gate = Completer<PhoneVerificationChallenge>();
    sendGates.add(gate);
    return gate.future;
  }

  @override
  Future<AuthenticatedUser> signIn(SignInRequest request) async {
    verifications.add(request);
    final gate = Completer<AuthenticatedUser>();
    verifyGates.add(gate);
    return session = await gate.future;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    session = null;
  }
}

Future<void> flush(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> mount(WidgetTester tester, CurrentUser user) async {
  final locale = LocaleNotifier();
  addTearDown(locale.dispose);
  await tester.pumpWidget(
    LocaleScope(
      notifier: locale,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(
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

Future<void> enterNumber(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, '13800000000');
  await tester.pump();
}

Future<void> enterCode(WidgetTester tester, PendingProvider provider) async {
  await enterNumber(tester);
  await tester.tap(find.byType(AuthPrimaryButton));
  await flush(tester);
  provider.sendGates.single.complete(challenge);
  await flush(tester);
  await tester.enterText(find.byType(TextField), '123456');
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'two real send taps while provider is pending issue only one OTP challenge',
    (tester) async {
      final provider = PendingProvider();
      // Use the actual CurrentUser scheduler and its queued provider calls.
      final current = CurrentUser(service: provider);
      await current.bootstrap();
      await mount(tester, current);
      await enterNumber(tester);
      await tester.tap(find.byType(AuthPrimaryButton));
      await tester.tap(find.byType(AuthPrimaryButton));
      await flush(tester);
      provider.sendGates.first.complete(challenge);
      await flush(tester);
      expect(provider.sends, ['+8613800000000']);
      expect(find.text('6-digit code'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      current.dispose();
    },
  );
  testWidgets(
    'two real verify taps cannot supersede a successful first session',
    (tester) async {
      final provider = PendingProvider();
      final current = CurrentUser(service: provider);
      await current.bootstrap();
      await mount(tester, current);
      await enterCode(tester, provider);
      await tester.tap(find.byType(AuthPrimaryButton));
      await tester.tap(find.byType(AuthPrimaryButton));
      await flush(tester);
      provider.verifyGates.first.complete(authenticated);
      await flush(tester);
      expect(provider.verifications, hasLength(1));
      expect(provider.signOuts, 0);
      expect(current.isSignedIn, isTrue);
      await tester.tap(find.byType(AuthPrimaryButton));
      await flush(tester);
      expect(provider.verifications, hasLength(1));
      expect(provider.signOuts, 0);
      final sent = provider.verifications.single as SignInRequestPhone;
      expect(sent.phoneNumber, challenge.phoneNumber);
      expect(sent.verificationID, challenge.verificationID);
      expect(sent.code, '123456');
      await tester.pumpWidget(const SizedBox.shrink());
      current.dispose();
    },
  );
  testWidgets('send failure releases the guard for one explicit retry', (
    tester,
  ) async {
    final provider = PendingProvider();
    final current = CurrentUser(service: provider);
    await current.bootstrap();
    await mount(tester, current);
    await enterNumber(tester);
    await tester.tap(find.byType(AuthPrimaryButton));
    await flush(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    provider.sendGates.single.completeError(
      const AuthException(AuthErrorKind.rateLimited),
    );
    await flush(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.byType(AuthPrimaryButton));
    await flush(tester);
    expect(provider.sends, hasLength(2));
    provider.sendGates.last.complete(challenge);
    await flush(tester);
    expect(find.text('6-digit code'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    current.dispose();
  });
  testWidgets(
    'verify failure releases the guard and preserves the exact retry request',
    (tester) async {
      final provider = PendingProvider();
      final current = CurrentUser(service: provider);
      await current.bootstrap();
      await mount(tester, current);
      await enterCode(tester, provider);
      await tester.tap(find.byType(AuthPrimaryButton));
      await flush(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      provider.verifyGates.single.completeError(
        const AuthException(AuthErrorKind.invalidVerificationCode),
      );
      await flush(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.byType(AuthPrimaryButton));
      await flush(tester);
      expect(provider.verifications, hasLength(2));
      final retry = provider.verifications.last as SignInRequestPhone;
      expect(retry.phoneNumber, challenge.phoneNumber);
      expect(retry.verificationID, challenge.verificationID);
      expect(retry.code, '123456');
      provider.verifyGates.last.complete(authenticated);
      await flush(tester);
      expect(current.isSignedIn, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      current.dispose();
    },
  );
  for (final operation in ['send', 'verify']) {
    testWidgets(
      'late $operation completion after form disposal does not update a disposed widget',
      (tester) async {
        final provider = PendingProvider();
        final current = CurrentUser(service: provider);
        await current.bootstrap();
        await mount(tester, current);
        if (operation == 'verify') {
          await enterCode(tester, provider);
        } else {
          await enterNumber(tester);
        }
        await tester.tap(find.byType(AuthPrimaryButton));
        await flush(tester);
        await tester.pumpWidget(const SizedBox.shrink());
        if (operation == 'verify') {
          provider.verifyGates.single.complete(authenticated);
        } else {
          provider.sendGates.single.complete(challenge);
        }
        await flush(tester);
        expect(tester.takeException(), isNull);
        expect(provider.sends, hasLength(1));
        expect(
          provider.verifications,
          hasLength(operation == 'verify' ? 1 : 0),
        );
        current.dispose();
      },
    );
  }
  testWidgets(
    'an already signed-in session cannot send another phone challenge',
    (tester) async {
      final provider = PendingProvider()..session = authenticated;
      final current = CurrentUser(service: provider);
      await current.bootstrap();
      expect(current.isSignedIn, isTrue);
      await mount(tester, current);
      await enterNumber(tester);
      await tester.tap(find.byType(AuthPrimaryButton));
      await flush(tester);
      expect(provider.sends, isEmpty);
      expect(provider.signOuts, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      current.dispose();
    },
  );
  testWidgets(
    'successful verification in the actual nested phone form returns to the original work route',
    (tester) async {
      final provider = PendingProvider();
      final current = CurrentUser(service: provider);
      await current.bootstrap();
      final locale = LocaleNotifier(), navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        LocaleScope(
          notifier: locale,
          child: MaterialApp(
            locale: const Locale('en'),
            navigatorKey: navigator,
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PublicWorkSignIn(user: current),
                    ),
                  ),
                  child: const Text(
                    'original work 12345678-1234-4234-8234-123456789abc',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(
        find.text('original work 12345678-1234-4234-8234-123456789abc'),
      );
      await tester.pumpAndSettle();
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: SingleChildScrollView(
              child: PhoneSignInView(
                currentUser: current,
                intent: PhoneIntent.signIn,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await enterCode(tester, provider);
      await tester.tap(find.byType(AuthPrimaryButton));
      await tester.tap(find.byType(AuthPrimaryButton));
      await flush(tester);
      provider.verifyGates.single.complete(authenticated);
      await tester.pumpAndSettle();
      expect(current.isSignedIn, isTrue);
      expect(provider.verifications, hasLength(1));
      expect(provider.signOuts, 0);
      expect(find.byType(PhoneSignInView), findsNothing);
      expect(find.byType(PublicWorkSignIn), findsNothing);
      expect(
        find.text('original work 12345678-1234-4234-8234-123456789abc'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      current.dispose();
      locale.dispose();
    },
  );
}
