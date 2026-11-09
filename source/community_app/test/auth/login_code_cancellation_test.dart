import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/aether_prefs.dart';
import 'package:pocketworld_flutter/auth/auth_models.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/auth/mock_auth_service.dart';

const _alice = AuthenticatedUser(id: InternalUserID('alice'));
const _bob = AuthenticatedUser(id: InternalUserID('bob'));
const _request = SignInRequest.phone(
  phoneNumber: '+8613800000000',
  verificationID: 'synthetic',
  code: '123456',
);

class _Service extends MockAuthServiceImpl {
  Future<AuthenticatedUser> Function()? login;
  int logouts = 0;
  AuthenticatedUser? provider;
  @override
  Future<AuthenticatedUser?> currentUser() async => provider;
  @override
  Future<AuthenticatedUser> signIn(SignInRequest request) async {
    final result = await login!();
    provider ??= result;
    return result;
  }

  @override
  Future<void> signOut() async {
    logouts++;
    provider = null;
    await super.signOut();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AetherPrefs.setMockInitialValues({}));
  test(
    'canceling an in-flight code login prevents late identity publication',
    () async {
      final pending = Completer<AuthenticatedUser>();
      final svc = _Service()..login = () => pending.future;
      final user = CurrentUser(service: svc);
      addTearDown(user.dispose);
      final login = user.signIn(_request);
      final token = user.pendingSignInToken!;
      user.cancelPendingSignIn(token);
      pending.complete(_alice);
      await login;
      expect(user.isSignedIn, false);
      expect(svc.logouts, 1);
      expect(user.pendingSignInToken, null);
    },
  );
  test('stale cancellation token cannot cancel a newer B login', () async {
    final pending = Completer<AuthenticatedUser>();
    var calls = 0;
    final svc = _Service()
      ..login = () => calls++ == 0 ? pending.future : Future.value(_bob);
    final user = CurrentUser(service: svc);
    addTearDown(user.dispose);
    final first = user.signIn(_request);
    final old = user.pendingSignInToken!;
    final second = user.signIn(_request);
    final next = user.pendingSignInToken;
    expect(next, isNot(old));
    user.cancelPendingSignIn(old);
    expect(user.pendingSignInToken, next);
    pending.complete(_alice);
    await Future.wait([first, second]);
    expect(user.signedInUser?.id, _bob.id);
    expect(
      svc.logouts,
      1,
      reason: 'only the superseded A action is revoked before queued B starts',
    );
  });
  test(
    'successful login notification disposal cannot undo committed identity',
    () async {
      final svc = _Service()..login = () async => _alice;
      final user = CurrentUser(service: svc);
      addTearDown(user.dispose);
      var attempted = false;
      int? capturedToken;
      user.addListener(() {
        final token = capturedToken;
        if (user.isSignedIn && token != null) {
          attempted = true;
          user.cancelPendingSignIn(token);
        }
      });
      final signingIn = user.signIn(_request);
      capturedToken = user.pendingSignInToken;
      await signingIn;
      expect(attempted, true);
      expect(user.signedInUser?.id, _alice.id);
      expect(svc.logouts, 0);
    },
  );
  test(
    'canceling A code login cannot revoke an external B provider session',
    () async {
      final pending = Completer<AuthenticatedUser>();
      final svc = _Service()..login = () => pending.future;
      final user = CurrentUser(service: svc);
      addTearDown(user.dispose);
      final signingIn = user.signIn(_request);
      final token = user.pendingSignInToken!;
      svc.provider = _bob;
      user.cancelPendingSignIn(token);
      pending.complete(_alice);
      await signingIn;
      expect(user.isSignedIn, false);
      expect(svc.provider?.id, _bob.id);
      expect(svc.logouts, 0);
    },
  );
  test(
    'cancel during delayed identity attachment revokes A and detaches its workspace',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      AuthenticatedUser? attached;
      final svc = _Service()..login = () async => _alice;
      final user = CurrentUser(
        service: svc,
        onIdentityChanged: (value) async {
          if (value?.id == _alice.id) {
            started.complete();
            await release.future;
          }
          attached = value;
        },
      );
      addTearDown(user.dispose);
      final signingIn = user.signIn(_request);
      final token = user.pendingSignInToken!;
      await started.future;
      expect(svc.provider?.id, _alice.id);
      user.cancelPendingSignIn(token);
      release.complete();
      await signingIn;
      expect(user.isSignedIn, false);
      expect(svc.provider, null);
      expect(attached, null);
      expect(await CurrentUser.readPersistedUserID(), null);
      await user.bootstrap();
      expect(
        user.isSignedIn,
        false,
        reason: 'bootstrap cannot revive the abandoned A session',
      );
    },
  );
  for (final queued in [true, false]) {
    test(
      'late canceled A attachment preserves ${queued ? 'queued' : 'external'} B',
      () async {
        final started = Completer<void>();
        final release = Completer<void>();
        AuthenticatedUser? attached;
        var calls = 0;
        final svc = _Service()
          ..login = () async => calls++ == 0 ? _alice : _bob;
        final user = CurrentUser(
          service: svc,
          onIdentityChanged: (value) async {
            if (value?.id == _alice.id) {
              started.complete();
              await release.future;
            }
            attached = value;
          },
        );
        addTearDown(user.dispose);
        final first = user.signIn(_request);
        final oldToken = user.pendingSignInToken!;
        await started.future;
        user.cancelPendingSignIn(oldToken);
        final second = queued ? user.signIn(_request) : Future<void>.value();
        if (!queued) svc.provider = _bob;
        release.complete();
        await Future.wait([first, second]);
        expect(svc.provider?.id, _bob.id);
        expect(svc.logouts, queued ? 1 : 0);
        if (queued) {
          expect(user.signedInUser?.id, _bob.id);
          expect(attached?.id, _bob.id);
          expect(await CurrentUser.readPersistedUserID(), _bob.id.rawValue);
        } else {
          expect(user.isSignedIn, false);
          expect(
            attached,
            null,
            reason: 'only the abandoned A workspace is detached',
          );
        }
      },
    );
  }
  test(
    'external B arriving during A workspace detach is not revoked',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final svc = _Service()..login = () async => _alice;
      final user = CurrentUser(
        service: svc,
        onIdentityChanged: (value) async {
          if (value?.id == _alice.id) {
            started.complete();
            await release.future;
          } else if (value == null) {
            // A was already revoked. B can arrive while the detach hook runs.
            svc.provider = _bob;
            await Future<void>.delayed(Duration.zero);
          }
        },
      );
      addTearDown(user.dispose);
      final signingIn = user.signIn(_request);
      final token = user.pendingSignInToken!;
      await started.future;
      user.cancelPendingSignIn(token);
      release.complete();
      await signingIn;
      expect(svc.logouts, 1);
      expect(svc.provider?.id, _bob.id);
      expect(user.isSignedIn, false);
    },
  );
}
