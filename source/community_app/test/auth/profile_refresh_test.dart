import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:pocketworld_flutter/auth/supabase_auth_service.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/aether_prefs.dart';
import 'package:pocketworld_flutter/auth/auth_models.dart';
import 'package:pocketworld_flutter/auth/auth_service.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/auth/mock_auth_service.dart';

const _alice = AuthenticatedUser(
  id: InternalUserID('alice'),
  displayName: 'Old',
);
const _renamed = AuthenticatedUser(
  id: InternalUserID('alice'),
  displayName: 'New',
);
const _bob = AuthenticatedUser(id: InternalUserID('bob'), displayName: 'Bob');
const _request = SignInRequest.email(
  email: 'synthetic@example.test',
  password: 'synthetic',
);

class _Service extends MockAuthServiceImpl implements CanonicalProfileReader {
  Future<AuthenticatedUser?> Function()? read;
  AuthenticatedUser? provider = _alice;
  int writes = 0;
  @override
  Future<AuthenticatedUser?> currentUser() async =>
      read == null ? provider : await read!();
  @override
  Future<AuthenticatedUser?> currentCanonicalProfile() => currentUser();
  @override
  Future<AuthenticatedUser> signIn(SignInRequest request) async {
    writes++;
    return provider!;
  }

  @override
  Future<void> signOut() async {
    writes++;
    provider = null;
  }

  @override
  Future<AuthenticatedUser> updateDisplayName(String name) async {
    writes++;
    throw StateError('Unexpected write');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AetherPrefs.setMockInitialValues({}));

  test(
    'a provider without strict canonical reads cannot replace presentation',
    () async {
      final service = MockAuthServiceImpl();
      final user = CurrentUser(service: service);
      addTearDown(user.dispose);
      await user.signIn(_request);
      final original = user.signedInUser;
      expect(original, isNotNull);
      expect(await user.refreshProfile(), false);
      expect(user.signedInUser, original);
    },
  );

  for (final cn in [false, true]) {
    test(
      'Supabase canonical refresh rejects fallback on ${cn ? 'CN' : 'global'}',
      () async {
        const id = '00000000-0000-4000-8000-000000000123';
        var mode = 'approved';
        final requests = <http.Request>[];
        final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
        final claims = base64Url
            .encode(utf8.encode(jsonEncode({'exp': exp})))
            .replaceAll('=', '');
        final client = sb.SupabaseClient(
          cn ? 'https://api.kongye.space' : 'https://example.invalid',
          'synthetic',
          authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((r) async {
            requests.add(r);
            Object? data;
            var status = 200;
            if (r.url.path == '/auth/v1/token') {
              data = {
                'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.synthetic',
                'token_type': 'bearer',
                'refresh_token': 'synthetic-refresh',
                'expires_in': 3600,
                'user': {
                  'id': id,
                  'aud': 'authenticated',
                  'created_at': '2026-10-16T00:00:00Z',
                  'email': 'synthetic@example.test',
                  'user_metadata': {'display_name': 'stale metadata'},
                },
              };
            } else {
              expect(r.method, 'GET');
              expect(
                r.url.path,
                '/rest/v1/${cn ? 'community_author_profiles' : 'profiles'}',
              );
              expect(r.url.queryParameters['id'], 'eq.$id');
              switch (mode) {
                case 'error':
                  data = {'message': 'Unavailable'};
                  status = 403;
                case 'missing':
                  data = null;
                case 'blank':
                  data = {'id': id, 'display_name': ''};
                default:
                  data = {'id': id, 'display_name': mode};
              }
            }
            return http.Response(
              jsonEncode(data),
              status,
              headers: {'content-type': 'application/json'},
              request: r,
            );
          }),
        );
        addTearDown(client.dispose);
        await client.auth.signInWithPassword(
          email: 'synthetic@example.test',
          password: 'synthetic',
        );
        final user = CurrentUser(
          service: SupabaseAuthServiceImpl(client: client),
        );
        addTearDown(user.dispose);
        await user.bootstrap();
        expect(user.signedInUser?.displayName, 'approved');
        requests.clear();
        for (final failure in ['error', 'missing', 'blank']) {
          mode = failure;
          expect(await user.refreshProfile(), false);
          expect(user.signedInUser?.displayName, 'approved');
          expect(client.auth.currentUser?.id, id);
        }
        mode = 'new canonical';
        expect(await user.refreshProfile(), true);
        expect(user.signedInUser?.displayName, 'new canonical');
        expect(requests, hasLength(4));
        expect(requests.every((r) => r.method == 'GET'), true);
      },
    );
  }

  test(
    'canonical refresh changes presentation without account writes or attachment',
    () async {
      final service = _Service();
      var attachments = 0;
      final user = CurrentUser(
        service: service,
        onIdentityChanged: (_) async {
          attachments++;
        },
      );
      addTearDown(user.dispose);
      await user.bootstrap();
      final before = attachments;
      var notified = 0;
      user.addListener(() => notified++);
      service.provider = _renamed;
      expect(await user.refreshProfile(), true);
      expect(user.signedInUser, _renamed);
      expect(attachments, before);
      expect(service.writes, 0);
      expect(notified, 1);
    },
  );

  test(
    'failed, missing or mismatched profile never clears the existing login',
    () async {
      final service = _Service();
      final user = CurrentUser(service: service);
      addTearDown(user.dispose);
      await user.bootstrap();
      for (final read in <Future<AuthenticatedUser?> Function()>[
        () async => throw StateError('Offline'),
        () async => null,
        () async => _bob,
      ]) {
        service.read = read;
        expect(await user.refreshProfile(), false);
        expect(user.signedInUser, _alice);
        expect(user.lastError, null);
      }
      expect(service.writes, 0);
    },
  );

  test('late profile cannot restore a logged-out identity', () async {
    final service = _Service();
    final user = CurrentUser(service: service);
    addTearDown(user.dispose);
    await user.bootstrap();
    final delayed = Completer<AuthenticatedUser?>();
    service.read = () => delayed.future;
    final refreshing = user.refreshProfile();
    await user.signOut();
    delayed.complete(_renamed);
    expect(await refreshing, false);
    expect(user.isSignedIn, false);
    expect(service.writes, 1);
  });

  test('late A profile cannot overwrite a newer B login', () async {
    final service = _Service();
    final user = CurrentUser(service: service);
    addTearDown(user.dispose);
    await user.bootstrap();
    final delayed = Completer<AuthenticatedUser?>();
    service.read = () => delayed.future;
    final refreshing = user.refreshProfile();
    service.provider = _bob;
    await user.signIn(_request);
    delayed.complete(_renamed);
    expect(await refreshing, false);
    expect(user.signedInUser, _bob);
    expect(service.writes, 1);
  });

  test('a newer read supersedes an older delayed read', () async {
    final service = _Service();
    final user = CurrentUser(service: service);
    addTearDown(user.dispose);
    await user.bootstrap();
    final delayed = Completer<AuthenticatedUser?>();
    service.read = () => delayed.future;
    final old = user.refreshProfile();
    service.read = () async => _renamed;
    expect(await user.refreshProfile(), true);
    delayed.complete(_alice);
    expect(await old, false);
    expect(user.signedInUser, _renamed);
  });
}
