import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketworld_flutter/auth/auth_error.dart';
import 'package:pocketworld_flutter/auth/supabase_auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

http.Response _json(Map<String, Object?> value, int status) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

(SupabaseAuthServiceImpl, sb.SupabaseClient) _service(
  Future<http.Response> Function(http.Request) handler,
) {
  final client = sb.SupabaseClient(
    'https://cn.example.invalid',
    'synthetic-key',
    authOptions: sb.AuthClientOptions(
      autoRefreshToken: false,
      pkceAsyncStorage: _MemoryPkceStorage(),
    ),
    httpClient: MockClient(handler),
  );
  addTearDown(client.dispose);
  return (SupabaseAuthServiceImpl(client: client), client);
}

Matcher _error(AuthErrorKind kind) => isA<AuthException>().having(
  (error) => error.kind,
  'kind',
  kind,
);

class _MemoryPkceStorage extends sb.GotrueAsyncStorage {
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

void main() {
  test('send uses official recovery with normalized email and no login', () async {
    final requests = <http.Request>[];
    final (service, client) = _service((request) async {
      requests.add(request);
      return _json({}, 200);
    });
    await service.sendPasswordReset('  Member@Example.TEST  ');
    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/auth/v1/recover');
    expect(requests.single.method.toUpperCase(), 'POST');
    expect(jsonDecode(requests.single.body)['email'], 'member@example.test');
    expect(client.auth.currentSession, isNull);
  });

  test('code verification returns only reset authorization, never a login', () async {
    final requests = <http.Request>[];
    final (service, client) = _service((request) async {
      requests.add(request);
      return _json({
        'ok': true,
        'reset_token': 'synthetic-reset-authorization',
        'expires_in': 600,
      }, 200);
    });
    expect(
      await service.verifyPasswordResetCode(
        email: '  Member@Example.TEST ',
        token: '123456',
      ),
      'synthetic-reset-authorization',
    );
    expect(requests, hasLength(1));
    expect(requests.single.method.toUpperCase(), 'POST');
    expect(requests.single.url.path, '/functions/v1/password-recovery-verify');
    expect(jsonDecode(requests.single.body), {
      'email': 'member@example.test',
      'otp': '123456',
    });
    expect(client.auth.currentSession, isNull);
  });

  test('completion preserves password bytes and does not request a session', () async {
    final requests = <http.Request>[];
    final (service, client) = _service((request) async {
      requests.add(request);
      return _json({'ok': true}, 200);
    });
    await service.completePasswordReset(
      email: ' Member@Example.TEST ',
      resetToken: 'synthetic-reset-authorization',
      newPassword: ' New-Password-123 ',
    );
    expect(requests, hasLength(1));
    expect(requests.single.method.toUpperCase(), 'POST');
    expect(requests.single.url.path, '/functions/v1/password-recovery-complete');
    expect(jsonDecode(requests.single.body), {
      'email': 'member@example.test',
      'reset_token': 'synthetic-reset-authorization',
      'new_password': ' New-Password-123 ',
    });
    expect(client.auth.currentSession, isNull);
  });

  test('a malformed successful verification cannot advance recovery', () async {
    final (service, _) = _service((_) async => _json({'ok': true}, 200));
    await expectLater(
      service.verifyPasswordResetCode(email: 'member@example.test', token: '123456'),
      throwsA(_error(AuthErrorKind.providerUnavailable)),
    );
  });

  test('a completion without explicit success is rejected', () async {
    final (service, _) = _service((_) async => _json({}, 200));
    await expectLater(
      service.completePasswordReset(
        email: 'member@example.test',
        resetToken: 'synthetic-reset-authorization',
        newPassword: 'New-Password-123',
      ),
      throwsA(_error(AuthErrorKind.providerUnavailable)),
    );
  });

  test('wrong code stays a verification failure without a login request', () async {
    var count = 0;
    final (service, client) = _service((_) async {
      count++;
      return _json({'error': 'invalid_code'}, 401);
    });
    await expectLater(
      service.verifyPasswordResetCode(email: 'member@example.test', token: '123456'),
      throwsA(_error(AuthErrorKind.invalidVerificationCode)),
    );
    expect(count, 1);
    expect(client.auth.currentSession, isNull);
  });

  for (final status in [401, 410]) {
    test('invalid or expired reset authorization ($status) requires a new flow', () async {
      final (service, _) = _service((_) async => _json(
        {'error': 'invalid_recovery_authorization'}, status,
      ));
      await expectLater(
        service.completePasswordReset(
          email: 'member@example.test',
          resetToken: 'synthetic-reset-authorization',
          newPassword: 'New-Password-123',
        ),
        throwsA(_error(AuthErrorKind.notSignedIn)),
      );
    });
  }

  test('provider outage is explicit rather than a successful reset', () async {
    final (service, _) = _service((_) async => _json({'error': 'provider_unavailable'}, 503));
    await expectLater(
      service.verifyPasswordResetCode(email: 'member@example.test', token: '123456'),
      throwsA(_error(AuthErrorKind.providerUnavailable)),
    );
  });
}
