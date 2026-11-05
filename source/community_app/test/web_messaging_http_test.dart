import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pocketworld_flutter/community/web_messaging_repository.dart';
import 'package:pocketworld_flutter/community/web_social_api.dart';
import 'package:pocketworld_flutter/ui/social/web_conversation_page.dart';

const owner = '11111111-1111-4111-8111-111111111111';
const peer = '22222222-2222-4222-8222-222222222222';
const conversation = '33333333-3333-4333-8333-333333333333';
const nonce = '44444444-4444-4444-8444-444444444444';
const namespace = 'china.cn-primary.https%3A%2F%2Fapi.kongye.space.rds20261104';

WebSocialApi createApi(http.Client client) => WebSocialApi(
  apiOrigin: Uri.https('api.kongye.space'),
  supabaseOrigin: Uri.https('api.kongye.space'),
  publishableKey: 'fixture-public',
  region: 'china',
  authNamespace: namespace,
  accessToken: () => 'fixture-jwt',
  currentUserId: () => owner,
  messagingEnabled: true,
  client: client,
);

void main() {
  test(
    'real adapter keeps nonce and regional RPC binding through 503 retry and sent history',
    () async {
      var status = 'retry';
      var sends = 0;
      final requests = <http.Request>[];
      final api = createApi(
        MockClient((request) async {
          requests.add(request);
          expect(request.headers['authorization'], 'Bearer fixture-jwt');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (request.url.path == '/api/private-messages/send') {
            sends++;
            expect(body, {
              'conversationId': conversation,
              'nonce': nonce,
              'body': 'draft',
            });
            return http.Response(
              jsonEncode({
                'id': 'request',
                'state': status,
                'messageId': status == 'sent' ? 9 : null,
              }),
              status == 'retry' ? 503 : 200,
            );
          }
          expect(body['p_region'], 'china');
          expect(body['p_namespace'], namespace);
          if (request.url.path.endsWith('pw_dm_status')) {
            return http.Response('null', 200);
          }
          expect(request.url.path, '/rest/v1/rpc/pw_dm_history');
          return http.Response(
            jsonEncode([
              {
                'id': 9,
                'conversation_id': conversation,
                'sender_id': owner,
                'body': 'draft',
                'created_at': '2026-11-05T12:00:00Z',
              },
            ]),
            200,
          );
        }),
      );
      final repo = WebMessagingRepository(
        api: api,
        ownerId: owner,
        currentUserId: () => owner,
        createNonce: () => nonce,
      );
      addTearDown(() {
        repo.dispose();
        api.close();
      });
      expect(
        (await repo.send(conversation, 'draft')).status,
        WebChatMessageStatus.retryable,
      );
      status = 'sent';
      expect(
        (await repo.send(conversation, 'draft')).status,
        WebChatMessageStatus.sent,
      );
      expect(sends, 2);
      expect(
        requests.where((r) => r.url.path.endsWith('pw_dm_status')).length,
        2,
      );
    },
  );

  test(
    'official SDK loads every inbox page under caller JWT and membership RLS',
    () async {
      final offsets = <String>[];
      final client = MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer fixture-jwt');
        if (request.url.path == '/rest/v1/conversations') {
          expect(request.url.queryParameters['type'], 'eq.dm');
          expect(
            request.url.queryParameters['select'],
            contains('conversation_members(user_id)'),
          );
          final offset = request.url.queryParameters['offset'] ?? '0';
          offsets.add(offset);
          final start = int.parse(offset);
          return http.Response(
            jsonEncode([
              for (var i = start; i < (start == 0 ? 100 : 101); i++)
                {
                  'id':
                      '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
                  'created_at': '2026-11-05T12:00:00Z',
                  'last_message_at': null,
                  'conversation_members': [
                    {'user_id': owner},
                    {'user_id': peer},
                  ],
                },
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (request.url.path.endsWith('pw_dm_history')) {
          return http.Response('[]', 200);
        }
        if (request.url.path.endsWith('pw_dm_unread')) {
          return http.Response('0', 200);
        }
        throw StateError('Unexpected request ${request.url.path}');
      });
      final sdk = SupabaseClient(
        'https://api.kongye.space',
        'fixture-public',
        httpClient: client,
        accessToken: () async => 'fixture-jwt',
      );
      final api = createApi(client);
      final repo = WebMessagingRepository(
        api: api,
        ownerId: owner,
        currentUserId: () => owner,
        realtimeClient: sdk,
        loadPeerName: (id) async {
          expect(id, peer);
          return 'Actual peer';
        },
      );
      addTearDown(() async {
        repo.dispose();
        api.close();
        await sdk.dispose();
      });
      final inbox = await repo.inbox();
      expect(inbox.length, 101);
      expect(inbox.every((row) => row.displayName == 'Actual peer'), isTrue);
      expect(offsets, ['0', '100']);
    },
  );
}
