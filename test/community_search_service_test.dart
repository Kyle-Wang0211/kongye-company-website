import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketworld_flutter/community/community_search_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('suggestions use the RDS RPC and preserve its native order', () async {
    final client = SupabaseClient(
      'https://api.kongye.space',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/rest/v1/rpc/community_search');
        expect(jsonDecode(request.body), {
          'p_action': 'suggest',
          'p_query': '中',
        });
        return http.Response(
          jsonEncode({
            'suggestions': ['中国', '中山'],
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);
    expect(await CommunitySearchService(client: client).suggest('中'), [
      '中国',
      '中山',
    ]);
  });

  test(
    'hydration restores backend relevance order and filters through public feed',
    () async {
      final client = SupabaseClient(
        'https://api.kongye.space',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          Object response;
          if (request.url.path.endsWith('/rpc/community_search')) {
            response = {
              'works': [
                {'id': 'b'},
                {'id': 'a'},
              ],
            };
          } else if (request.url.path.endsWith('/works')) {
            expect(request.url.queryParameters['id'], 'in.("b","a")');
            expect(request.url.queryParameters['visibility'], 'eq.public');
            response = [
              {'id': 'a', 'user_id': 'u', 'title': 'A'},
              {'id': 'b', 'user_id': 'u', 'title': 'B'},
            ];
          } else {
            response = [];
          }
          return http.Response(
            jsonEncode(response),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final results = await CommunitySearchService(client: client).search('b');
      expect(results.map((work) => work.id), ['b', 'a']);
    },
  );
}
