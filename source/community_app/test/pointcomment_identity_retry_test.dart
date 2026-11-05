import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pocketworld_flutter/config/endpoint_config.dart';
import 'package:pocketworld_flutter/config/backend_deployment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/community/comments/comment_models.dart';
import 'package:pocketworld_flutter/community/comments/comment_repository.dart';

CommunityCommentIdentity identity(
  Object generation, {
  String user = 'me',
  String region = 'region|https://example.invalid',
  Object? scope = 'same-client-and-key',
}) => CommunityCommentIdentity(
  userId: user,
  regionKey: region,
  generation: generation,
  readRetryScope: scope,
);
Map<String, dynamic> page(String revision) => {
  'section': 'hot',
  'asset_revision': revision,
  'can_comment': true,
  'public_count': 0,
  'comments': <dynamic>[],
  'next_cursor': null,
  'context_comments': <dynamic>[],
};
Matcher get identityChanged => isA<CommunityCommentException>().having(
  (e) => e.code,
  'code',
  'identity_changed',
);

void main() {
  test(
    'actual SDK same-client token refresh restarts successful read with fresh snapshot',
    () async {
      final previousConfig = EndpointConfigResolver.current;
      const deployment = BackendDeployment(
        region: BackendRegion.international,
        id: 'test',
        supabaseUrl: 'https://fixture.invalid',
        anonKey: 'public-fixture-key',
      );
      EndpointConfigResolver.current = const EndpointConfig(
        supabaseUrl: 'https://fixture.invalid',
        supabaseAnonKey: 'public-fixture-key',
        source: EndpointConfigSource.builtin,
        deployment: deployment,
      );
      addTearDown(() => EndpointConfigResolver.current = previousConfig);
      Map<String, Object?> session(String token) => {
        'access_token': token,
        'refresh_token': 'synthetic-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': 'me',
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-11-01T00:00:00Z',
        },
      };
      final client = SupabaseClient(
        'https://fixture.invalid',
        'public-fixture-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/auth/v1/token');
          return http.Response(
            jsonEncode(session('synthetic-after-refresh')),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await client.auth.setInitialSession(
        jsonEncode(session('synthetic-before-refresh')),
      );
      expect(
        identical(client.auth.currentSession, client.auth.currentSession),
        isTrue,
      );
      final before = client.auth.currentSession;
      var calls = 0;
      final repo = SupabaseCommunityCommentRepository(
        client: client,
        transport: (body) async {
          calls++;
          if (calls == 1) {
            await client.auth.refreshSession();
            expect(identical(before, client.auth.currentSession), isFalse);
            return page('stale');
          }
          return page('fresh-sdk-session');
        },
      );
      expect((await repo.fetch('work')).assetRevision, 'fresh-sdk-session');
      expect(calls, 2);
    },
  );

  test(
    'session generation changing during successful read restarts once and discards old response',
    () async {
      var current = identity('session-before-refresh');
      var calls = 0;
      final repo = SupabaseCommunityCommentRepository(
        identity: () => current,
        transport: (body) async {
          calls++;
          if (calls == 1) {
            current = identity('session-after-refresh');
            return page('stale');
          }
          return page('fresh');
        },
      );
      final result = await repo.fetchSection(
        'work',
        section: CommunityCommentSection.hot,
      );
      expect(result.assetRevision, 'fresh');
      expect(calls, 2);
    },
  );
  test(
    'a second session generation change is rejected instead of looping',
    () async {
      var current = identity(0), calls = 0;
      final repo = SupabaseCommunityCommentRepository(
        identity: () => current,
        transport: (body) async {
          current = identity(++calls);
          return page('stale');
        },
      );
      await expectLater(repo.fetch('work'), throwsA(identityChanged));
      expect(calls, 2);
    },
  );
  for (final change in ['account', 'region', 'credentials', 'logout']) {
    test('$change rejects old read without retry', () async {
      CommunityCommentIdentity? current = identity('before');
      var calls = 0;
      final repo = SupabaseCommunityCommentRepository(
        identity: () => current,
        transport: (body) async {
          calls++;
          current = switch (change) {
            'account' => identity('after', user: 'other'),
            'region' => identity('after', region: 'other'),
            'credentials' => identity('after', scope: 'other-client-or-key'),
            _ => null,
          };
          return page('stale');
        },
      );
      await expectLater(repo.fetch('work'), throwsA(identityChanged));
      expect(calls, 1);
    });
  }
  test('session changes never retry a write', () async {
    var current = identity('before'), calls = 0;
    final repo = SupabaseCommunityCommentRepository(
      identity: () => current,
      transport: (body) async {
        calls++;
        current = identity('after');
        return <String, dynamic>{};
      },
    );
    await expectLater(
      repo.submit(
        CommunityCommentDraft(
          workId: 'work',
          assetRevision: 'revision',
          body: 'hello',
          clientRequestId: 'request',
        ),
      ),
      throwsA(identityChanged),
    );
    expect(calls, 1);
  });
  test(
    'legacy identity readers without explicit retry scope stay fail closed',
    () async {
      var current = identity('before', scope: null), calls = 0;
      final repo = SupabaseCommunityCommentRepository(
        identity: () => current,
        transport: (body) async {
          calls++;
          current = identity('after', scope: null);
          return page('stale');
        },
      );
      await expectLater(repo.fetch('work'), throwsA(identityChanged));
      expect(calls, 1);
    },
  );
}
