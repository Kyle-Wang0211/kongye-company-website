import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketworld_flutter/auth/auth_error.dart';
import 'package:pocketworld_flutter/auth/auth_models.dart';
import 'package:pocketworld_flutter/auth/supabase_auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _userID = '00000000-0000-4000-8000-000000000123';
const _otherUserID = '00000000-0000-4000-8000-000000000456';
const _proof = {
  'token_hash': 'synthetic-managed-token-hash',
  'type': 'magiclink',
  'user_id': _userID,
};

String _session({
  String userID = _userID,
  String? email,
  Map<String, Object?>? appMetadata,
  Map<String, Object?>? userMetadata,
}) {
  final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  final claims = base64Url
      .encode(utf8.encode(jsonEncode({'exp': exp})))
      .replaceAll('=', '');
  return jsonEncode({
    'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.synthetic',
    'token_type': 'bearer',
    'refresh_token': 'synthetic-refresh',
    'expires_in': 3600,
    'user': {
      'id': userID,
      'aud': 'authenticated',
      'created_at': '2026-10-16T00:00:00Z',
      'email': ?email,
      'app_metadata': ?appMetadata,
      'user_metadata': ?userMetadata,
    },
  });
}

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

sb.SupabaseClient _client(
  Future<http.Response> Function(http.Request) handler,
) {
  final client = sb.SupabaseClient(
    'https://cn.example.invalid',
    'synthetic-key',
    authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient(handler),
  );
  addTearDown(client.dispose);
  return client;
}

void main() {
  const nonce = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
  const request = SignInRequest.wechat(code: 'fresh-code', nonce: nonce);

  final alias = '${'a' * 64}@wx.local';
  const trustedMarker = {
    'wechat_miniprogram': {
      'app_id': 'wx0123456789abcdef',
      'open_id': 'synthetic-open-id',
    },
  };
  test('trusted WeChat internal alias is hidden without changing session', () async {
    final client = _client((req) async => fail('must not call'));
    await client.auth.recoverSession(_session(
      email: alias,
      appMetadata: trustedMarker,
      userMetadata: {'display_name': '微信用户'},
    ));
    final before = client.auth.currentSession;
    final user = await SupabaseAuthServiceImpl(client: client).currentUser();
    expect(user!.email, isNull);
    expect(user.displayName, '微信用户');
    expect(client.auth.currentUser!.email, alias);
    expect(client.auth.currentSession, same(before));
  });

  for (final example in <String, Map<String, Object?>>{
    'ordinary real email with trusted metadata': {
      'email': 'real@example.invalid', 'app': trustedMarker,
    },
    'alias without trusted metadata': {'email': alias},
    'forged user metadata': {'email': alias, 'meta': trustedMarker},
    'invalid trusted app ID': {
      'email': alias,
      'app': {'wechat_miniprogram': {'app_id': 'invalid', 'open_id': 'open-id'}},
    },
    'missing trusted open ID': {
      'email': alias,
      'app': {'wechat_miniprogram': {'app_id': 'wx0123456789abcdef'}},
    },
    'invalid trusted open ID': {
      'email': alias,
      'app': {'wechat_miniprogram': {'app_id': 'wx0123456789abcdef', 'open_id': ' '}},
    },
    'different alias domain': {
      'email': '${'a' * 64}@example.invalid', 'app': trustedMarker,
    },
  }.entries) {
    test('email is preserved: ${example.key}', () async {
      final client = _client((req) async => fail('must not call'));
      await client.auth.recoverSession(_session(
        email: example.value['email'] as String,
        appMetadata: example.value['app'] as Map<String, Object?>?,
        userMetadata: example.value['meta'] as Map<String, Object?>?,
      ));
      final user = await SupabaseAuthServiceImpl(client: client).currentUser();
      expect(user!.email, example.value['email']);
    });
  }

  test('first and repeat WeChat login use managed verify and preserve UUID', () async {
    final requests = <http.Request>[];
    final client = _client((req) async {
      requests.add(req);
      if (req.url.path == '/functions/v1/wechat-login') {
        expect(req.method.toUpperCase(), 'POST');
        expect(jsonDecode(req.body), {'code': 'fresh-code'});
        return _json(_proof);
      }
      if (req.url.path == '/auth/v1/logout') return _json({});
      expect(req.url.path, '/auth/v1/verify');
      expect(req.method.toUpperCase(), 'POST');
      expect(req.url.queryParameters, isEmpty);
      final body = jsonDecode(req.body) as Map;
      expect(body['token_hash'], _proof['token_hash']);
      expect(body['type'], 'magiclink');
      for (final key in [
        'email', 'phone', 'password', 'nonce', 'provider', 'id_token',
        'user_id', 'openid', 'unionid', 'link_identity', 'claims',
      ]) {
        expect(body.containsKey(key), isFalse, reason: key);
      }
      return http.Response(_session(), 200);
    });
    final service = SupabaseAuthServiceImpl(client: client);
    expect((await service.signIn(request)).id.rawValue, _userID);
    expect(client.auth.currentSession, isNotNull);
    await service.signOut();
    expect((await service.signIn(request)).id.rawValue, _userID);
    expect(requests, hasLength(5));
    expect(requests.where((r) => r.url.path.endsWith('/verify')), hasLength(2));
  });

  final malformed = <String, Object?>{
    'non-object': ['token'],
    'null': null,
    'missing token hash': {'type': 'magiclink', 'user_id': _userID},
    'empty token hash': {..._proof, 'token_hash': ''},
    'blank token hash': {..._proof, 'token_hash': '   '},
    'non-string token hash': {..._proof, 'token_hash': 7},
    'oversized token hash': {..._proof, 'token_hash': 'a' * 1025},
    'wrong type': {..._proof, 'type': 'signup'},
    'missing user ID': {'token_hash': 'hash', 'type': 'magiclink'},
    'invalid user ID': {..._proof, 'user_id': 'not-a-uuid'},
    'non-string user ID': {..._proof, 'user_id': 7},
    'extra identity claim': {..._proof, 'openid': 'untrusted'},
    'retired custom provider': {
      'provider': 'custom:wechat-miniprogram',
      'id_token': 'synthetic',
      'expires_in': 120,
    },
  };
  for (final entry in malformed.entries) {
    test('malformed response rejects before verify: ${entry.key}', () async {
      var calls = 0;
      final client = _client((req) async {
        calls++;
        expect(req.url.path, '/functions/v1/wechat-login');
        return _json(entry.value);
      });
      await expectLater(
        SupabaseAuthServiceImpl(client: client).signIn(request),
        throwsA(isA<AuthException>()),
      );
      expect(calls, 1);
      expect(client.auth.currentSession, isNull);
    });
  }

  for (final invalid in [
    const SignInRequest.wechat(code: '', nonce: nonce),
    const SignInRequest.wechat(code: '  ', nonce: nonce),
    SignInRequest.wechat(code: 'a' * 1025, nonce: nonce),
    const SignInRequest.wechat(code: 'fresh', nonce: 'bad'),
  ]) {
    test('invalid local input rejects without network: $invalid', () async {
      final client = _client((req) async => fail('must not call'));
      await expectLater(
        SupabaseAuthServiceImpl(client: client).signIn(invalid),
        throwsA(isA<AuthException>()),
      );
    });
  }

  test('existing user is retained and WeChat makes no network call', () async {
    var calls = 0;
    final client = _client((req) async {
      calls++;
      fail('must not call');
    });
    await client.auth.recoverSession(_session());
    final before = client.auth.currentSession;
    await expectLater(
      SupabaseAuthServiceImpl(client: client).signIn(request),
      throwsA(isA<AuthException>()),
    );
    expect(calls, 0);
    expect(client.auth.currentSession, same(before));
  });

  test('server failure rejects without verify', () async {
    var calls = 0;
    final client = _client((req) async {
      calls++;
      expect(req.url.path, '/functions/v1/wechat-login');
      return _json({'error': 'unavailable'}, 503);
    });
    await expectLater(
      SupabaseAuthServiceImpl(client: client).signIn(request),
      throwsA(isA<AuthException>()),
    );
    expect(calls, 1);
    expect(client.auth.currentSession, isNull);
  });

  for (final logoutStatus in [200, 503]) {
    test('returned UUID mismatch clears new session (logout $logoutStatus)', () async {
      final paths = <String>[];
      final client = _client((req) async {
        paths.add(req.url.path);
        if (req.url.path == '/functions/v1/wechat-login') return _json(_proof);
        if (req.url.path == '/auth/v1/verify') {
          return http.Response(_session(userID: _otherUserID), 200);
        }
        expect(req.url.path, '/auth/v1/logout');
        expect(req.url.queryParameters, {'scope': 'local'});
        return _json({}, logoutStatus);
      });
      await expectLater(
        SupabaseAuthServiceImpl(client: client).signIn(request),
        throwsA(isA<AuthException>()),
      );
      expect(paths, [
        '/functions/v1/wechat-login', '/auth/v1/verify', '/auth/v1/logout',
      ]);
      expect(client.auth.currentUser, isNull);
      expect(client.auth.currentSession, isNull);
    });
  }

  test('verify response without session fails closed', () async {
    final client = _client((req) async {
      if (req.url.path == '/functions/v1/wechat-login') return _json(_proof);
      expect(req.url.path, '/auth/v1/verify');
      return _json({'user': jsonDecode(_session())['user']});
    });
    await expectLater(
      SupabaseAuthServiceImpl(client: client).signIn(request),
      throwsA(isA<AuthException>()),
    );
    expect(client.auth.currentSession, isNull);
  });
}
