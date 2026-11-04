import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketworld_flutter/community/author_feed_priority.dart';
import 'package:pocketworld_flutter/community/community_service.dart';
import 'package:pocketworld_flutter/community/feed_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

FeedWork work(String id, String user, int day) => FeedWork(
  id: id,
  userId: user,
  title: id,
  description: null,
  format: 'glb',
  modelStoragePath: null,
  thumbnailStoragePath: null,
  likesCount: 0,
  viewsCount: 0,
  publishedAt: DateTime.utc(2026, 11, day),
  authorDisplayName: user,
  authorAvatarUrl: null,
  likedByMe: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final other1 = work('other1', 'other', 3);
  final other2 = work('other2', 'other', 2);
  final mine = work('mine', 'me', 1);
  final newest = work('newest', 'me', 3);
  List<String> ids(List<FeedWork> rows) => rows.map((w) => w.id).toList();

  test(
    'only the viewer owns priority; other order is stable and ids dedupe',
    () {
      expect(
        ids(prioritizeAuthorFeed([other1, mine, other2], [newest, mine], 'me')),
        ['newest', 'mine', 'other1', 'other2'],
      );
      expect(
        ids(prioritizeAuthorFeed([other1, mine, other2], [newest], 'other')),
        ['other1', 'other2', 'mine'],
      );
      expect(
        ids(prioritizeAuthorFeed([other1, mine, other2], [newest], null)),
        ['other1', 'mine', 'other2'],
      );
    },
  );

  test(
    'private/cancelled publication adds nothing; no optimistic insertion',
    () {
      expect(ids(prioritizeAuthorFeed([other1, other2], [], 'me')), [
        'other1',
        'other2',
      ]);
    },
  );

  test(
    'owner query reaches outside the public page and enforces public gates',
    () async {
      final requests = <Uri>[];
      final client = SupabaseClient(
        'https://offline.invalid',
        'anon',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request.url);
          var result = <Map<String, dynamic>>[];
          if (request.url.path.endsWith('/works')) {
            expect(request.url.queryParameters['visibility'], 'eq.public');
            expect(request.url.queryParameters['moderation_status'], 'eq.ok');
            expect(request.url.queryParameters['deleted_at'], 'is.null');
            expect(request.url.queryParameters['published_at'], 'not.is.null');
            expect(request.url.queryParameters['user_id'], 'eq.me');
            result = [
              {
                'id': 'outside-page',
                'user_id': 'me',
                'title': 'public',
                'published_at': '2026-11-03T00:00:00Z',
              },
            ];
          }
          return http.Response(
            jsonEncode(result),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await client.auth.setInitialSession(
        jsonEncode({
          'access_token': 'local-test-token',
          'token_type': 'bearer',
          'user': {
            'id': 'me',
            'aud': 'authenticated',
            'app_metadata': {},
            'user_metadata': {},
            'created_at': '2026-11-03T00:00:00Z',
          },
        }),
      );
      final service = CommunityService(client: client);
      expect(ids(await service.fetchOwnPublicFeed()), ['outside-page']);
      expect(requests.where((u) => u.path.endsWith('/works')), hasLength(1));
    },
  );
}
