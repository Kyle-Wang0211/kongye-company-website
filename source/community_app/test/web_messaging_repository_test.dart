import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/community/web_messaging_repository.dart';
import 'package:pocketworld_flutter/community/web_social_api.dart';
import 'package:pocketworld_flutter/ui/social/web_conversation_page.dart';

class Api extends WebSocialApi {
  Api()
    : super(
        apiOrigin: Uri.https('api.example.test'),
        supabaseOrigin: null,
        publishableKey: null,
        region: null,
        authNamespace: null,
        accessToken: () => 'test-only',
        currentUserId: () => 'owner',
        messagingEnabled: true,
      );
  final posts = <String>[];
  final marks = <String>[];
  List<WebDmMessage> messages = [];
  WebDmReceipt? receipt;
  bool failAfterCommit = false;
  Completer<WebDmReceipt>? pendingSend;
  Completer<List<WebDmMessage>>? pendingHistory;
  int histories = 0;
  @override
  Future<WebDmReceipt?> messageStatus(String nonce) async => receipt;
  @override
  Future<WebDmReceipt> sendMessage({
    required String conversationId,
    required String nonce,
    required String body,
  }) async {
    posts.add(nonce);
    if (pendingSend != null) return pendingSend!.future;
    if (failAfterCommit) {
      throw const WebSocialUnavailableException('transport_unavailable');
    }
    return receipt ?? const WebDmReceipt('request', WebDmState.pending, null);
  }

  @override
  Future<List<WebDmMessage>> conversation(
    String id, {
    String? before,
    int limit = 50,
  }) async {
    histories++;
    return pendingHistory == null ? messages : pendingHistory!.future;
  }

  @override
  Future<String> markRead(String id, String messageId) async {
    marks.add(messageId);
    return messageId;
  }
}

WebDmMessage serverMessage(String id, {String sender = 'owner'}) =>
    WebDmMessage(
      id,
      'conversation',
      sender,
      'server body',
      '2026-11-05T12:00:00Z',
    );

void main() {
  late Api api;
  late WebMessagingRepository repo;
  var actor = 'owner';
  var nonces = 0;
  setUp(() {
    actor = 'owner';
    nonces = 0;
    api = Api();
    repo = WebMessagingRepository(
      api: api,
      ownerId: 'owner',
      currentUserId: () => actor,
      createNonce: () => 'nonce-${++nonces}',
    );
  });
  tearDown(() {
    repo.dispose();
    api.close();
  });

  test(
    'pending, machine retry, review and rejection are distinct from delivery',
    () async {
      for (final entry in const {
        WebDmState.pending: WebChatMessageStatus.processing,
        WebDmState.retry: WebChatMessageStatus.retryable,
        WebDmState.review: WebChatMessageStatus.pendingReview,
        WebDmState.rejected: WebChatMessageStatus.rejected,
      }.entries) {
        api.receipt = WebDmReceipt('request', entry.key, null);
        final message = await repo.send('conversation', 'draft');
        expect(message.status, entry.value);
        expect(message.id, 'request:request');
        expect(message.status, isNot(WebChatMessageStatus.sent));
      }
      expect(api.posts.toSet(), {'nonce-1'});
    },
  );

  test('ambiguous send reconciles same nonce before any second POST', () async {
    api.failAfterCommit = true;
    await expectLater(
      repo.send('conversation', 'draft'),
      throwsA(isA<WebSocialUnavailableException>()),
    );
    api.receipt = const WebDmReceipt('request', WebDmState.sent, '7');
    api.messages = [serverMessage('7')];
    final message = await repo.send('conversation', 'draft');
    expect(api.posts, ['nonce-1']);
    expect(message.id, '7');
    expect(message.text, 'server body');
    expect(message.createdAt, DateTime.parse('2026-11-05T12:00:00Z'));
    expect(message.status, WebChatMessageStatus.sent);
  });

  test(
    'repeat content after confirmed delivery allocates a new nonce',
    () async {
      api.receipt = const WebDmReceipt('request', WebDmState.sent, '7');
      api.messages = [serverMessage('7')];
      await repo.send('conversation', 'draft');
      api.receipt = null;
      await repo.send('conversation', 'draft');
      expect(nonces, 2);
      expect(api.posts, ['nonce-2']);
    },
  );

  test('single-flight send uses only one POST', () async {
    api.pendingSend = Completer<WebDmReceipt>();
    final first = repo.send('conversation', 'draft');
    final second = repo.send('conversation', 'draft');
    await Future<void>.delayed(Duration.zero);
    expect(api.posts, ['nonce-1']);
    api.pendingSend!.complete(
      const WebDmReceipt('request', WebDmState.pending, null),
    );
    expect((await first).id, (await second).id);
  });

  test(
    'history stays read-only until the visible UI advances its read cursor',
    () async {
      api.messages = [
        serverMessage('9'),
        serverMessage('8', sender: 'peer'),
        serverMessage('7', sender: 'peer'),
      ];
      await repo.history('conversation');
      expect(api.marks, isEmpty);
      await repo.markRead('conversation', '8');
      expect(api.marks, ['8']);
      api.marks.clear();
      api.messages = [serverMessage('9')];
      await repo.history('conversation');
      expect(api.marks, isEmpty);
    },
  );

  test(
    'account change discards late private history and prevents send',
    () async {
      api.pendingHistory = Completer<List<WebDmMessage>>();
      final loading = repo.history('conversation');
      actor = 'other';
      api.pendingHistory!.complete([serverMessage('7')]);
      await expectLater(loading, throwsA(isA<WebSocialUnavailableException>()));
      expect(api.marks, isEmpty);
      expect(
        () => repo.send('conversation', 'draft'),
        throwsA(isA<WebSocialUnavailableException>()),
      );
      expect(api.posts, isEmpty);
    },
  );

  test('withdrawal requires the server edit marker and preserves literal user text', () async {
    api.messages = [
      const WebDmMessage(
        '9',
        'conversation',
        'peer',
        '[已撤回]',
        '2026-11-05T12:00:00Z',
        editedAt: '2026-11-05T12:01:00Z',
      ),
      const WebDmMessage(
        '8',
        'conversation',
        'peer',
        '[已撤回]',
        '2026-11-05T11:00:00Z',
      ),
    ];
    final rows = await repo.history('conversation');
    expect(
      rows.singleWhere((row) => row.id == '9').status,
      WebChatMessageStatus.withdrawn,
    );
    expect(
      rows.singleWhere((row) => row.id == '8').status,
      WebChatMessageStatus.sent,
    );
    expect(api.marks, isEmpty);
  });

  test('over-limit draft is rejected before any transport', () {
    expect(
      () => repo.send('conversation', List.filled(601, 'a').join()),
      throwsArgumentError,
    );
    expect(api.posts, isEmpty);
  });

  test(
    'sent receipt without actual history never fabricates delivered text',
    () async {
      api.receipt = const WebDmReceipt('request', WebDmState.sent, '7');
      await expectLater(
        repo.send('conversation', 'draft'),
        throwsA(isA<WebSocialUnavailableException>()),
      );
    },
  );
}
