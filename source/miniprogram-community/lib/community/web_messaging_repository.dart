import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../ui/social/web_conversation_page.dart';
import '../ui/social/web_messages_page.dart';
import 'web_social_api.dart';

/// Caller-scoped R4 messaging. The existing API owns transport/auth/RLS binding.
/// Nonces stay in memory until an authoritative terminal receipt is reconciled.
class WebMessagingRepository {
  WebMessagingRepository({
    required this.api,
    required this.ownerId,
    required this.currentUserId,
    this.realtimeClient,
    this.loadPeerName,
    String Function()? createNonce,
  }) : _createNonce = createNonce ?? const Uuid().v4;

  final WebSocialApi api;
  final String ownerId;
  final String? Function() currentUserId;
  final SupabaseClient? realtimeClient;
  final Future<String> Function(String peerId)? loadPeerName;
  final String Function() _createNonce;
  final Map<String, _Submission> _submissions = {};
  final Map<String, Future<WebChatMessage>> _sending = {};
  bool _disposed = false;

  bool get available => api.messagingEnabled;

  void _requireOwner() {
    if (_disposed || currentUserId() != ownerId) {
      throw const WebSocialUnavailableException('session_changed');
    }
  }

  Future<T> _guard<T>(Future<T> Function() operation) async {
    _requireOwner();
    final result = await operation();
    _requireOwner();
    return result;
  }

  Future<List<WebConversationSummary>> inbox() => _guard(() async {
    final rows = await _inboxRows();
    final result = <WebConversationSummary>[];
    for (final row in rows) {
      final peer = row.memberIds.where((id) => id != ownerId).single;
      final latest = await _guard(() => api.conversation(row.id, limit: 1));
      final count = await _guard(() => api.unread(row.id));
      final profile = api.profilesEnabled
          ? await _guard(() => api.profile(peer))
          : null;
      final displayName = loadPeerName != null
          ? await _guard(() => loadPeerName!(peer))
          : profile?.displayName ?? '创作者';
      result.add(
        WebConversationSummary(
          id: row.id,
          peerId: peer,
          displayName: displayName,
          preview: latest.isEmpty ? '' : latest.first.body,
          updatedAt: DateTime.parse(row.lastMessageAt ?? row.createdAt),
          unreadCount: count,
        ),
      );
    }
    return result;
  });

  Future<List<WebDmConversation>> _inboxRows() async {
    final client = realtimeClient;
    if (client == null) return api.inbox(limit: 100);
    final result = <WebDmConversation>[];
    final seen = <String>{};
    for (var offset = 0; ; offset += 100) {
      final page = await _guard(
        () => client
            .from('conversations')
            .select(
              'id,created_at,last_message_at,conversation_members(user_id)',
            )
            .eq('type', 'dm')
            .order('last_message_at', ascending: false, nullsFirst: false)
            .order('id', ascending: false)
            .range(offset, offset + 99),
      );
      for (final row in page) {
        final id = row['id'] as String;
        if (!seen.add(id)) {
          throw const WebSocialUnavailableException('invalid_cursor');
        }
        result.add(
          WebDmConversation(
            id,
            (row['conversation_members'] as List)
                .map((member) => (member as Map)['user_id'] as String)
                .toList(),
            createdAt: row['created_at'] as String,
            lastMessageAt: row['last_message_at'] as String?,
          ),
        );
      }
      if (page.length < 100) return result;
    }
  }

  Future<String> openPeer(String peerId) => _guard(() async {
    if (peerId == ownerId) throw ArgumentError('Cannot message yourself');
    return api.openConversation(peerId);
  });

  Future<List<WebChatMessage>> history(String conversationId) => _guard(
    () async {
      final messages = <WebDmMessage>[];
      final cursors = <String>{};
      String? before;
      while (true) {
        final page = await _guard(
          () => api.conversation(conversationId, before: before, limit: 100),
        );
        messages.addAll(page);
        if (page.length < 100) break;
        before = page.last.id;
        if (!cursors.add(before)) {
          throw const WebSocialUnavailableException('invalid_cursor');
        }
      }
      final pending = _submissions.values
          .where((entry) => entry.conversationId == conversationId)
          .toList();
      final ownPending = <WebChatMessage>[];
      for (final entry in pending) {
        final receipt = await _guard(() => api.messageStatus(entry.nonce));
        if (receipt == null) continue;
        entry.receipt = receipt;
        if (receipt.state == WebDmState.sent ||
            receipt.state == WebDmState.withdrawn) {
          // A receipt can precede the history snapshot. Keep it for the next
          // refresh and never synthesize the delivered message's content/time.
          if (messages.any((message) => message.id == receipt.messageId)) {
            _submissions.remove(entry.key);
          }
        } else {
          ownPending.add(_pendingMessage(entry, receipt));
        }
      }
      return [...messages.map(_message), ...ownPending]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    },
  );

  Future<WebChatMessage> send(String conversationId, String text) {
    _requireOwner();
    final body = text.trim();
    if (body.isEmpty || body.length > 600) {
      throw ArgumentError('Messages must contain 1–600 characters');
    }
    final key = '$conversationId:$body';
    if (_submissions[key]?.receipt?.state == WebDmState.rejected) {
      _submissions.remove(key);
    }
    final ongoing = _sending[key];
    if (ongoing != null) return ongoing;
    final operation = _send(conversationId, body, key);
    _sending[key] = operation;
    return operation.whenComplete(() => _sending.remove(key));
  }

  Future<WebChatMessage> _send(
    String conversationId,
    String body,
    String key,
  ) => _guard(() async {
    final entry = _submissions.putIfAbsent(
      key,
      () => _Submission(key, conversationId, body, _createNonce()),
    );
    // Resolve an ambiguous previous POST before repeating the same nonce.
    final previous = await _guard(() => api.messageStatus(entry.nonce));
    final receipt =
        previous != null &&
            previous.state != WebDmState.retry &&
            previous.state != WebDmState.pending
        ? previous
        : await _guard(
            () => api.sendMessage(
              conversationId: conversationId,
              nonce: entry.nonce,
              body: body,
            ),
          );
    if (receipt.state == WebDmState.sent ||
        receipt.state == WebDmState.withdrawn) {
      final history = await _guard(() => api.conversation(conversationId));
      final matches = history.where((row) => row.id == receipt.messageId);
      if (matches.length != 1) {
        throw const WebSocialUnavailableException('delivery_unconfirmed');
      }
      _submissions.remove(key);
      return _message(matches.single);
    }
    entry.receipt = receipt;
    return _pendingMessage(entry, receipt);
  });

  WebChatMessage _message(WebDmMessage row) => WebChatMessage(
    id: row.id,
    text: row.body,
    isMine: row.senderId == ownerId,
    createdAt: DateTime.parse(row.createdAt),
    status: row.editedAt != null && row.body == '[已撤回]'
        ? WebChatMessageStatus.withdrawn
        : WebChatMessageStatus.sent,
  );

  WebChatMessage _pendingMessage(_Submission entry, WebDmReceipt receipt) =>
      WebChatMessage(
        id: 'request:${receipt.id}',
        text: entry.body,
        isMine: true,
        createdAt: entry.submittedAt,
        status: switch (receipt.state) {
          WebDmState.review => WebChatMessageStatus.pendingReview,
          WebDmState.rejected => WebChatMessageStatus.rejected,
          WebDmState.retry => WebChatMessageStatus.retryable,
          _ => WebChatMessageStatus.processing,
        },
      );

  /// Official Supabase channel, identical to the canonical R4 client adapter.
  /// Events are invalidations. Caller refetches history under its current JWT.
  Stream<void> watch(String conversationId) {
    _requireOwner();
    final client = realtimeClient;
    if (client == null) return const Stream.empty();
    RealtimeChannel? channel;
    late final StreamController<void> changes;
    changes = StreamController<void>(
      onListen: () {
        channel = client
            .channel(
              'dm:$conversationId',
              opts: const RealtimeChannelConfig(private: true),
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'messages',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'conversation_id',
                value: conversationId,
              ),
              callback: (payload) {
                if (!_disposed &&
                    currentUserId() == ownerId &&
                    payload.newRecord['conversation_id'] == conversationId) {
                  changes.add(null);
                }
              },
            )
            .subscribe((status, error) {
              if (changes.isClosed) return;
              if (status == RealtimeSubscribeStatus.subscribed) {
                if (!_disposed && currentUserId() == ownerId) changes.add(null);
              } else if (status == RealtimeSubscribeStatus.channelError ||
                  status == RealtimeSubscribeStatus.timedOut) {
                changes.addError(
                  const WebSocialUnavailableException('realtime_unavailable'),
                );
              }
            });
      },
      onCancel: () async {
        if (channel != null) await client.removeChannel(channel!);
      },
    );
    return changes.stream;
  }

  Future<void> markRead(String conversationId, String messageId) =>
      _guard(() async {
        await api.markRead(conversationId, messageId);
      });

  Future<void> block(String peerId, bool blocked) =>
      _guard(() => api.blockUser(peerId, blocked));
  Future<void> withdraw(String messageId) =>
      _guard(() => api.withdraw(messageId));
  Future<String> report(String messageId, String reason) =>
      _guard(() => api.reportMessage(messageId, reason));

  void dispose() {
    _disposed = true;
    _submissions.clear();
    _sending.clear();
  }
}

class _Submission {
  _Submission(this.key, this.conversationId, this.body, this.nonce);
  final String key, conversationId, body, nonce;
  final DateTime submittedAt = DateTime.now();
  WebDmReceipt? receipt;
}
