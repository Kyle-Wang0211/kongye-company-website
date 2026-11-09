import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketworld_flutter/auth/auth_error.dart';
import 'package:pocketworld_flutter/auth/auth_models.dart';
import 'package:pocketworld_flutter/auth/supabase_auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const email = 'synthetic@example.invalid';
const password = ' Original-password123 ';
const userId = '00000000-0000-4000-8000-000000000123';
const user = {
  'id': userId,
  'aud': 'authenticated',
  'created_at': '2026-11-06T00:00:00Z',
  'email': email,
};
Map<String, Object> session() {
  final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  final claims = base64Url.encode(utf8.encode(jsonEncode({'exp': exp})));
  return {
    'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.synthetic',
    'refresh_token': 'synthetic-refresh',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': user,
  };
}

http.Response response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {
    'content-type': 'application/json',
    'x-supabase-api-version': '2024-01-01',
  },
);
SupabaseAuthServiceImpl service(
  Future<http.Response> Function(http.Request) handler, {
  bool ready = true,
}) {
  final client = sb.SupabaseClient(
    'https://synthetic.example.invalid',
    'synthetic-key',
    authOptions: sb.AuthClientOptions(
      autoRefreshToken: false,
      pkceAsyncStorage: _MemoryStorage(),
    ),
    httpClient: MockClient(handler),
  );
  addTearDown(client.dispose);
  return SupabaseAuthServiceImpl(client: client, nativeEmailReady: ready);
}

class _MemoryStorage extends sb.GotrueAsyncStorage {
  final _items = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _items[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    _items[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _items.remove(key);
  }
}

Matcher error(AuthErrorKind kind) =>
    isA<AuthException>().having((e) => e.kind, 'kind', kind);
void main() {
  test('disabled SMTP gate sends no requests for email mutations', () async {
    final svc = service(
      (_) async => fail('network called while disabled'),
      ready: false,
    );
    final actions = <Future<Object?> Function()>[
      () => svc.signUp(
        const SignUpRequest.email(email: email, password: password),
      ),
      () => svc.resendEmailOtp(email: email),
      () => svc.verifyEmailSignupOtp(email: email, token: '123456'),
      () => svc.sendPasswordReset(email),
      () => svc.verifyPasswordResetCode(email: email, token: '123456'),
      () => svc.completePasswordReset(
        email: email,
        resetToken: 'synthetic-capability',
        newPassword: password,
      ),
    ];
    for (final action in actions) {
      await expectLater(
        action(),
        throwsA(error(AuthErrorKind.providerUnavailable)),
      );
    }
  });
  test(
    'signup sends native password and metadata, pending has email only',
    () async {
      final svc = service((request) async {
        expect(request.url.path, '/auth/v1/signup');
        final body = jsonDecode(request.body) as Map;
        expect(body['email'], email);
        expect(body['password'], password);
        expect(body['data'], {'display_name': '测试用户', 'locale': 'en'});
        return response(user);
      });
      await expectLater(
        svc.signUp(
          const SignUpRequest.email(
            email: email,
            password: password,
            displayName: '测试用户',
          ),
        ),
        throwsA(
          isA<EmailVerificationPending>().having(
            (e) => e.email,
            'email',
            email,
          ),
        ),
      );
      expect(await svc.currentUser(), isNull);
    },
  );
  test(
    'native signup OTP establishes session without password login',
    () async {
      var calls = 0;
      final svc = service((request) async {
        if (request.url.path == '/rest/v1/profiles' ||
            request.url.path == '/rest/v1/community_author_profiles') {
          expect(request.url.queryParameters['id'], 'eq.$userId');
          return http.Response(
            jsonEncode([
              {'id': userId, 'display_name': 'canonical'},
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        calls++;
        expect(request.url.path, '/auth/v1/verify');
        expect((jsonDecode(request.body) as Map)['email'], email);
        expect((jsonDecode(request.body) as Map)['token'], '123456');
        expect((jsonDecode(request.body) as Map)['type'], 'email');
        return response(session());
      });
      expect(
        (await svc.verifyEmailSignupOtp(
          email: email,
          token: '123456',
        )).id.rawValue,
        userId,
      );
      expect((await svc.currentUser())?.id.rawValue, userId);
      expect(calls, 1);
    },
  );
  test('resend and recovery start use official endpoints', () async {
    final paths = <String>[];
    final svc = service((request) async {
      paths.add(request.url.path);
      final body = jsonDecode(request.body) as Map;
      expect(body['email'], email);
      expect(body.containsKey('password'), false);
      if (request.url.path.endsWith('/resend')) expect(body['type'], 'signup');
      return response({});
    });
    await svc.resendEmailOtp(email: email);
    await svc.sendPasswordReset(email);
    expect(paths, ['/auth/v1/resend', '/auth/v1/recover']);
  });
  test('recovery verification and completion do not create a login', () async {
    final paths = <String>[];
    final svc = service((request) async {
      paths.add(request.url.path);
      if (request.url.path.endsWith('password-recovery-verify')) {
        expect(jsonDecode(request.body), {'email': email, 'otp': '123456'});
        return response({
          'ok': true,
          'reset_token': 'synthetic-capability',
          'expires_in': 600,
        });
      }
      expect(request.url.path, '/functions/v1/password-recovery-complete');
      expect(jsonDecode(request.body), {
        'email': email,
        'reset_token': 'synthetic-capability',
        'new_password': password,
      });
      return response({'ok': true});
    });
    final capability = await svc.verifyPasswordResetCode(
      email: email,
      token: '123456',
    );
    await svc.completePasswordReset(
      email: email,
      resetToken: capability,
      newPassword: password,
    );
    expect(paths, [
      '/functions/v1/password-recovery-verify',
      '/functions/v1/password-recovery-complete',
    ]);
    expect(await svc.currentUser(), isNull);
  });
  test('password update failure remains signed out', () async {
    final svc = service((request) async {
      expect(request.url.path, '/functions/v1/password-recovery-complete');
      return response({'error': 'weak_password'}, 400);
    });
    await expectLater(
      svc.completePasswordReset(
        email: email,
        resetToken: 'synthetic-capability',
        newPassword: 'weak',
      ),
      throwsA(error(AuthErrorKind.weakPassword)),
    );
    expect(await svc.currentUser(), isNull);
  });
  test('signup honors an explicitly returned native session', () async {
    final svc = service((request) async {
      expect(request.url.path, '/auth/v1/signup');
      return response(session());
    });
    expect(
      (await svc.signUp(
        const SignUpRequest.email(email: email, password: password),
      )).id.rawValue,
      userId,
    );
  });
  for (final kind in ['email', 'recovery']) {
    test('wrong/expired $kind code cannot establish a session', () async {
      final svc = service((request) async {
        expect(
          request.url.path,
          kind == 'email'
              ? '/auth/v1/verify'
              : '/functions/v1/password-recovery-verify',
        );
        return kind == 'email'
            ? response({
                'code': 'otp_expired',
                'msg': 'Token has expired or is invalid',
              }, 403)
            : response({'error': 'invalid_code'}, 401);
      });
      final action = kind == 'email'
          ? svc.verifyEmailSignupOtp(email: email, token: '000000')
          : svc.verifyPasswordResetCode(email: email, token: '000000');
      await expectLater(
        action,
        throwsA(error(AuthErrorKind.invalidVerificationCode)),
      );
      expect(await svc.currentUser(), isNull);
    });
  }
  test('verification missing a reset capability cannot advance', () async {
    final svc = service((request) async {
      expect(request.url.path, '/functions/v1/password-recovery-verify');
      return response({'ok': true});
    });
    await expectLater(
      svc.verifyPasswordResetCode(email: email, token: '123456'),
      throwsA(error(AuthErrorKind.providerUnavailable)),
    );
    expect(await svc.currentUser(), isNull);
  });
  for (final entry in [
    (429, 'over_email_send_rate_limit', AuthErrorKind.rateLimited),
    (422, 'weak_password', AuthErrorKind.weakPassword),
  ]) {
    test('native signup maps ${entry.$2}', () async {
      final svc = service(
        (_) async => response({'code': entry.$2, 'msg': entry.$2}, entry.$1),
      );
      await expectLater(
        svc.signUp(const SignUpRequest.email(email: email, password: password)),
        throwsA(error(entry.$3)),
      );
    });
  }
}
