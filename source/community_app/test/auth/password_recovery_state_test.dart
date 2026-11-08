import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/aether_prefs.dart';
import 'package:pocketworld_flutter/auth/auth_error.dart';
import 'package:pocketworld_flutter/auth/auth_models.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/auth/mock_auth_service.dart';

class _RecoveryService extends MockAuthServiceImpl {
  int signIns = 0;
  int signOuts = 0;
  bool rejectCode = false;
  Completer<void>? completion;
  final completionStarted = Completer<void>();

  @override
  Future<AuthenticatedUser> signIn(SignInRequest request) async {
    signIns++;
    return super.signIn(request);
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    await super.signOut();
  }

  @override
  Future<String> verifyPasswordResetCode({
    required String email,
    required String token,
  }) async {
    if (rejectCode) {
      throw const AuthException(AuthErrorKind.invalidVerificationCode);
    }
    return 'synthetic-reset-token';
  }

  @override
  Future<void> completePasswordReset({
    required String email,
    required String resetToken,
    required String newPassword,
  }) async {
    completionStarted.complete();
    await completion?.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AetherPrefs.setMockInitialValues({}));

  test('recovery code and password completion never sign in', () async {
    final service = _RecoveryService();
    final user = CurrentUser(service: service);
    addTearDown(user.dispose);
    await user.bootstrap();

    final recovery = user;
    expect(
      await recovery.verifyPasswordResetCode(
        email: 'member@example.test',
        token: '123456',
      ),
      'synthetic-reset-token',
    );
    expect(user.state, isA<CurrentUserSignedOut>());
    expect(
      await recovery.completePasswordReset(
        email: 'member@example.test',
        resetToken: 'synthetic-reset-token',
        newPassword: ' New-Password-123 ',
      ),
      isTrue,
    );
    expect(user.state, isA<CurrentUserSignedOut>());
    expect(service.signIns, 0);
    expect(service.signOuts, 1);
    expect(await CurrentUser.readPersistedUserID(), isNull);
  });

  test('invalid recovery code preserves signed-out state', () async {
    final service = _RecoveryService()..rejectCode = true;
    final user = CurrentUser(service: service);
    addTearDown(user.dispose);
    await user.bootstrap();
    final recovery = user;

    expect(
      await recovery.verifyPasswordResetCode(
        email: 'member@example.test',
        token: '999999',
      ),
      isNull,
    );
    expect(user.lastError?.kind, AuthErrorKind.invalidVerificationCode);
    expect(user.isSignedIn, isFalse);
    expect(service.signIns, 0);
  });

  test('late reset completion cannot sign out a newer explicit login', () async {
    final service = _RecoveryService()..completion = Completer<void>();
    final user = CurrentUser(service: service);
    addTearDown(user.dispose);
    await user.bootstrap();
    final recovery = user;
    final Future<bool> pending = recovery.completePasswordReset(
      email: 'member@example.test',
      resetToken: 'synthetic-reset-token',
      newPassword: 'New-Password-123',
    );
    await service.completionStarted.future;
    final login = user.signIn(
      const SignInRequest.email(
        email: 'other@example.test',
        password: 'Other-Password-123',
      ),
    );
    service.completion!.complete();
    expect(await pending, isFalse);
    await login;
    expect(user.isSignedIn, isTrue);
    expect(user.signedInUser?.email, 'other@example.test');
    expect(service.signIns, 1);
    expect(service.signOuts, 1);
  });
}
