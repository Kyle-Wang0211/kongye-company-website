import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketworld_flutter/auth/auth_error.dart';
import 'package:pocketworld_flutter/auth/auth_models.dart';
import 'package:pocketworld_flutter/auth/supabase_auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _id = '00000000-0000-4000-8000-000000000123';
const _phone = '+8613800000000';
String _session({String id = _id}) {
  final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  final claims = base64Url
      .encode(utf8.encode(jsonEncode({'exp': exp})))
      .replaceAll('=', '');
  return jsonEncode({
    'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.synthetic-$id',
    'token_type': 'bearer',
    'refresh_token': 'synthetic-refresh',
    'expires_in': 3600,
    'user': {
      'id': id,
      'aud': 'authenticated',
      'created_at': '2026-10-16T00:00:00Z',
      'phone': _phone,
      'user_metadata': {'display_name': 'stale metadata'},
    },
  });
}

http.Response _json(Object? value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

MockClient _mock(Future<http.Response> Function(http.Request) handler) =>
    MockClient((r) async {
      final response = await handler(r);
      return http.Response.bytes(
        response.bodyBytes,
        response.statusCode,
        headers: response.headers,
        request: r,
      );
    });

void main() {
  for (final cn in [false, true]) {
    test(
      'signin and bootstrap hydrate canonical nickname on ${cn ? 'CN' : 'global'} own profile',
      () async {
        final reads = <http.Request>[];
        final client = sb.SupabaseClient(
          cn ? 'https://api.kongye.space' : 'https://example.invalid',
          'synthetic',
          authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
          httpClient: _mock((r) async {
            if (r.url.path == '/auth/v1/token') {
              return http.Response(
                _session(),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            reads.add(r);
            return _json({'id': _id, 'display_name': 'canonical profile'});
          }),
        );
        addTearDown(client.dispose);
        final service = SupabaseAuthServiceImpl(client: client);
        final user = await service.signIn(
          const SignInRequest.phonePassword(
            phoneNumber: _phone,
            password: 'synthetic',
          ),
        );
        expect(user.displayName, 'canonical profile');
        expect((await service.currentUser())?.displayName, 'canonical profile');
        expect(reads, hasLength(2));
        for (final r in reads) {
          expect(r.method, 'GET');
          expect(
            r.url.path,
            '/rest/v1/${cn ? 'community_author_profiles' : 'profiles'}',
          );
          expect(r.url.queryParameters['id'], 'eq.$_id');
        }
      },
    );
  }
  for (final unchanged in [false, true]) {
    test(
      'rename uses server canonical value, including unchanged=$unchanged',
      () async {
        final requests = <http.Request>[];
        final client = sb.SupabaseClient(
          'https://example.invalid',
          'synthetic',
          authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
          httpClient: _mock((r) async {
            requests.add(r);
            if (r.url.path == '/auth/v1/token') {
              return http.Response(
                _session(),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            if (r.url.path.endsWith('/set-profile-name')) {
              return _json(
                unchanged
                    ? {'ok': true, 'unchanged': true}
                    : {'ok': true, 'display_name': 'normalized name'},
              );
            }
            return _json({'id': _id, 'display_name': 'normalized name'});
          }),
        );
        addTearDown(client.dispose);
        await client.auth.signInWithPassword(
          phone: _phone,
          password: 'synthetic',
        );
        final renamed = await SupabaseAuthServiceImpl(
          client: client,
        ).updateDisplayName(' raw request ');
        expect(renamed.displayName, 'normalized name');
        final write = requests.singleWhere(
          (r) => r.url.path.endsWith('/set-profile-name'),
        );
        expect(jsonDecode(write.body), {'display_name': ' raw request '});
        expect(requests.any((r) => r.method == 'PUT'), isFalse);
      },
    );
  }
  test(
    'phone signup persists nickname with authenticated endpoint, not metadata update',
    () async {
      final writes = <http.Request>[];
      final client = sb.SupabaseClient(
        'https://example.invalid',
        'synthetic',
        authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
        httpClient: _mock((r) async {
          writes.add(r);
          if (r.url.path == '/auth/v1/verify') {
            return http.Response(
              _session(),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (r.url.path.endsWith('/set-profile-name')) {
            return _json({'ok': true, 'display_name': 'chosen name'});
          }
          return _json({'id': _id, 'display_name': 'chosen name'});
        }),
      );
      addTearDown(client.dispose);
      final user = await SupabaseAuthServiceImpl(client: client).signUp(
        const SignUpRequest.phone(
          password: 'synthetic-password',
          phoneNumber: _phone,
          verificationID: _phone,
          code: '123456',
          displayName: 'chosen name',
        ),
      );
      expect(user.displayName, 'chosen name');
      expect(
        writes.where((r) => r.url.path.endsWith('/set-profile-name')),
        hasLength(1),
      );
      expect(writes.any((r) => r.url.path == '/auth/v1/user'), isFalse);
    },
  );
  test(
    'missing rename name and failed readback cannot publish raw request',
    () async {
      final client = sb.SupabaseClient(
        'https://example.invalid',
        'synthetic',
        authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
        httpClient: _mock((r) async {
          if (r.url.path == '/auth/v1/token') {
            return http.Response(
              _session(),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (r.url.path.endsWith('/set-profile-name')) {
            return _json({'ok': true, 'unchanged': true});
          }
          return _json({'message': 'unavailable'}, 503);
        }),
      );
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(
        phone: _phone,
        password: 'synthetic',
      );
      await expectLater(
        SupabaseAuthServiceImpl(client: client).updateDisplayName('unverified'),
        throwsA(isA<AuthException>()),
      );
    },
  );
  test(
    'account switch never sends nickname write using the new principal',
    () async {
      const bob = '00000000-0000-4000-8000-000000000456';
      final pending = Completer<http.Response>();
      final started = Completer<http.Request>();
      var loginId = _id;
      final client = sb.SupabaseClient(
        'https://example.invalid',
        'synthetic',
        authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
        httpClient: _mock((r) async {
          if (r.url.path == '/auth/v1/token') {
            return http.Response(
              _session(id: loginId),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (r.url.path.endsWith('/set-profile-name')) {
            started.complete(r);
            return pending.future;
          }
          return _json({});
        }),
      );
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(
        phone: _phone,
        password: 'synthetic',
      );
      final aliceBearer = client.auth.currentSession!.accessToken;
      final renaming = SupabaseAuthServiceImpl(
        client: client,
      ).updateDisplayName('Alice name');
      final result = expectLater(renaming, throwsA(isA<AuthException>()));
      loginId = bob;
      await client.auth.signInWithPassword(
        phone: '+8613900000000',
        password: 'synthetic',
      );
      final request = await started.future;
      expect(client.auth.currentUser!.id, bob);
      expect(request.headers['Authorization'], 'Bearer $aliceBearer');
      expect(
        request.headers['Authorization'],
        isNot('Bearer ${client.auth.currentSession!.accessToken}'),
      );
      expect(jsonDecode(request.body), {'display_name': 'Alice name'});
      pending.complete(_json({'ok': true, 'display_name': 'Alice name'}));
      await result;
    },
  );
  test('late rename response cannot recreate signed-out identity', () async {
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    final client = sb.SupabaseClient(
      'https://example.invalid',
      'synthetic',
      authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
      httpClient: _mock((r) async {
        if (r.url.path == '/auth/v1/token') {
          return http.Response(
            _session(),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (r.url.path.endsWith('/set-profile-name')) {
          started.complete();
          return pending.future;
        }
        return _json({});
      }),
    );
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(phone: _phone, password: 'synthetic');
    final renaming = SupabaseAuthServiceImpl(
      client: client,
    ).updateDisplayName('next');
    final result = expectLater(renaming, throwsA(isA<AuthException>()));
    await started.future;
    await client.auth.signOut(scope: sb.SignOutScope.local);
    pending.complete(_json({'ok': true, 'display_name': 'next'}));
    await result;
  });
  for (final malformed in [
    null,
    {'error': 'not_saved'},
    {'display_name': 'not_saved'},
  ]) {
    test(
      'malformed HTTP 200 rename response cannot report success: $malformed',
      () async {
        var profileReads = 0;
        final client = sb.SupabaseClient(
          'https://example.invalid',
          'synthetic',
          authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
          httpClient: _mock((r) async {
            if (r.url.path == '/auth/v1/token') {
              return http.Response(
                _session(),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            if (r.url.path.endsWith('/set-profile-name')) {
              return _json(malformed);
            }
            profileReads++;
            return _json({'id': _id, 'display_name': 'old name'});
          }),
        );
        addTearDown(client.dispose);
        await client.auth.signInWithPassword(
          phone: _phone,
          password: 'synthetic',
        );
        await expectLater(
          SupabaseAuthServiceImpl(
            client: client,
          ).updateDisplayName('requested'),
          throwsA(
            isA<AuthException>().having(
              (e) => e.kind,
              'kind',
              AuthErrorKind.providerUnavailable,
            ),
          ),
        );
        expect(profileReads, 0);
      },
    );
  }
}
