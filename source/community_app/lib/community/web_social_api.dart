// Existing favorites R4 / social activation R4 HTTP and caller-RLS contracts.
// This adapter stores no session: every request reads the current in-memory JWT.
import 'dart:convert';
import 'package:http/http.dart' as http;

class WebSocialUnavailableException implements Exception {
  final String code;
  const WebSocialUnavailableException([this.code = 'unavailable']);
  @override
  String toString() => 'WebSocialUnavailableException($code)';
}

class WebSocialRequestException implements Exception {
  final int status;
  const WebSocialRequestException(this.status);
  @override
  String toString() => 'WebSocialRequestException($status)';
}

class WebFavorite {
  final String workId, authorId, title, savedAt;
  const WebFavorite(this.workId, this.authorId, this.title, this.savedAt);
}

class WebFavoriteCursor {
  final String savedAt, workId;
  const WebFavoriteCursor(this.savedAt, this.workId);
}

class WebFavoritePage {
  final List<WebFavorite> items;
  final WebFavoriteCursor? next;
  const WebFavoritePage(this.items, this.next);
}

/// Only the caller-visible projection is retained; no auth metadata is exposed.
class WebSocialProfile {
  final String id, displayName;
  final String? handle, bio;
  final bool isOwner;
  final int? version;
  final int worksCount, likesCount;
  final List<Map<String, dynamic>> edits;
  const WebSocialProfile({
    required this.id,
    required this.displayName,
    this.handle,
    this.bio,
    required this.isOwner,
    this.version,
    required this.worksCount,
    required this.likesCount,
    required this.edits,
  });
}

class WebSocialWork {
  final String id, userId, title, createdAt, moderationStatus, visibility;
  final bool removed;
  const WebSocialWork(
    this.id,
    this.userId,
    this.title,
    this.createdAt,
    this.moderationStatus,
    this.visibility,
    this.removed,
  );
}

class WebProfileEditReceipt {
  final String editId, status;
  const WebProfileEditReceipt(this.editId, this.status);
}

class WebDmConversation {
  final String id;
  final List<String> memberIds;
  final String createdAt;
  final String? lastMessageAt;
  const WebDmConversation(
    this.id,
    this.memberIds, {
    required this.createdAt,
    this.lastMessageAt,
  });
}

class WebDmMessage {
  final String id, conversationId, senderId, body;
  final String createdAt;
  final String? editedAt;
  const WebDmMessage(
    this.id,
    this.conversationId,
    this.senderId,
    this.body,
    this.createdAt, {
    this.editedAt,
  });
}

enum WebDmState { pending, retry, review, rejected, sent, withdrawn }

class WebDmReceipt {
  final String id;
  final WebDmState state;
  final String? messageId;
  const WebDmReceipt(this.id, this.state, this.messageId);
}

class WebReportReceipt {
  final String reportId;
  final bool duplicate;
  const WebReportReceipt(this.reportId, this.duplicate);
}

class WebReportHistory {
  final Map<String, dynamic> fields;
  WebReportHistory(Map<String, dynamic> fields)
    : fields = Map.unmodifiable(fields);
}

enum WebAccountErasureState { requested, completed }

/// apiOrigin must be the approved regional API, not derived from user input.
/// Feature flags indicate configured contracts, not a promise of server health.
class WebSocialApi {
  final Uri? apiOrigin, supabaseOrigin;
  final String? publishableKey, region, authNamespace;
  final String? Function() accessToken;
  final String? Function() currentUserId;
  final bool favoritesEnabled, profilesEnabled, messagingEnabled;
  final bool reportsEnabled, deletionEnabled;
  final http.Client _http;

  WebSocialApi({
    required this.apiOrigin,
    required this.supabaseOrigin,
    required this.publishableKey,
    required this.region,
    required this.authNamespace,
    required this.accessToken,
    required this.currentUserId,
    this.favoritesEnabled = false,
    this.profilesEnabled = false,
    this.messagingEnabled = false,
    this.reportsEnabled = false,
    this.deletionEnabled = false,
    http.Client? client,
  }) : _http = client ?? http.Client();

  void close() => _http.close();

  Future<WebFavoritePage> listFavorites({
    int limit = 30,
    WebFavoriteCursor? before,
  }) async {
    _enabled(favoritesEnabled);
    _limit(limit, 100);
    final data = _map(
      await _request(
        'GET',
        '/api/favorites',
        query: {
          'limit': '$limit',
          if (before != null) ...{
            'before_time': before.savedAt,
            'before_id': _uuid(before.workId),
          },
        },
      ),
    );
    final items = _rows(data['items'])
        .map(
          (x) => WebFavorite(
            _str(x['workId']),
            _str(x['authorId']),
            _str(x['title']),
            _str(x['savedAt']),
          ),
        )
        .toList(growable: false);
    final next = data['next'] == null ? null : _map(data['next']);
    return WebFavoritePage(
      items,
      next == null
          ? null
          : WebFavoriteCursor(_str(next['savedAt']), _str(next['workId'])),
    );
  }

  Future<bool> favoriteState(String workId) => _favorite('GET', workId);
  Future<bool> setFavorite(String workId, bool saved) =>
      _favorite(saved ? 'PUT' : 'DELETE', workId);
  Future<bool> _favorite(String method, String workId) async {
    _enabled(favoritesEnabled);
    final data = _map(
      await _request(method, '/api/favorites/${_uuid(workId)}'),
    );
    if (data['workId'] != workId ||
        data['saved'] is! bool ||
        (method != 'GET' && data['saved'] != (method == 'PUT'))) {
      _invalid();
    }
    return data['saved'] as bool;
  }

  Future<WebSocialProfile> profile(String userId) async {
    _enabled(profilesEnabled);
    final x = _map(
      await _request('GET', '/api/profile', query: {'user_id': _uuid(userId)}),
    );
    return WebSocialProfile(
      id: _str(x['id']),
      displayName: _str(x['display_name']),
      handle: _optionalString(x['handle']),
      bio: _optionalString(x['bio']),
      isOwner: _bool(x['is_owner']),
      version: x['version'] == null ? null : _int(x['version']),
      worksCount: _int(x['works_count']),
      likesCount: _int(x['likes_count']),
      edits: x['edits'] == null ? const [] : _rows(x['edits']),
    );
  }

  Future<List<WebSocialWork>> profileWorks(
    String userId, {
    int limit = 20,
    String? beforeAt,
    String? beforeId,
  }) async {
    _enabled(profilesEnabled);
    _limit(limit, 50);
    if ((beforeAt == null) != (beforeId == null)) {
      throw ArgumentError('Incomplete cursor');
    }
    return _rows(
          await _request(
            'GET',
            '/api/profile/works',
            query: {
              'user_id': _uuid(userId),
              'limit': '$limit',
              'before_at': ?beforeAt,
              if (beforeId != null) 'before_id': _uuid(beforeId),
            },
          ),
        )
        .map(
          (x) => WebSocialWork(
            _str(x['id']),
            _str(x['user_id']),
            _str(x['title']),
            _str(x['created_at']),
            _str(x['moderation_status']),
            _str(x['visibility']),
            _bool(x['removed']),
          ),
        )
        .toList(growable: false);
  }

  Future<WebProfileEditReceipt> editProfile({
    required int version,
    String? displayName,
    String? handle,
    String? bio,
  }) async {
    _enabled(profilesEnabled);
    final patch = {
      'display_name': ?displayName,
      'handle': ?handle,
      'bio': ?bio,
    };
    if (version < 0 || patch.isEmpty) {
      throw ArgumentError('Invalid profile patch');
    }
    final x = _map(
      await _request(
        'POST',
        '/api/profile',
        body: {'patch': patch, 'version': version},
      ),
    );
    final status = _str(x['status']);
    if (![
      'pending',
      'retry',
      'review',
      'rejected',
      'approved',
      'superseded',
    ].contains(status)) {
      _invalid();
    }
    return WebProfileEditReceipt(_str(x['edit_id']), status);
  }

  /// Existing R4 SELECT grants + membership RLS; no fabricated inbox route.
  Future<List<WebDmConversation>> inbox({int limit = 50}) async {
    _enabled(messagingEnabled);
    _limit(limit, 100);
    final initialToken = accessToken();
    final rows = _rows(
      await _request(
        'GET',
        '/rest/v1/conversations',
        supabase: true,
        query: {
          'select': 'id,created_at,last_message_at',
          'type': 'eq.dm',
          'order': 'last_message_at.desc.nullslast,id.desc',
          'limit': '$limit',
        },
      ),
    );
    final result = <WebDmConversation>[];
    for (final row in rows) {
      final id = _uuid(_str(row['id']));
      final members = _rows(
        await _request(
          'GET',
          '/rest/v1/conversation_members',
          supabase: true,
          query: {'select': 'user_id', 'conversation_id': 'eq.$id'},
        ),
      );
      result.add(
        WebDmConversation(
          id,
          members.map((x) => _str(x['user_id'])).toList(growable: false),
          createdAt: _str(row['created_at']),
          lastMessageAt: _optionalString(row['last_message_at']),
        ),
      );
    }
    if (accessToken() != initialToken) {
      throw const WebSocialUnavailableException('session_changed');
    }
    return result;
  }

  Future<String> openConversation(String peerId) async =>
      _str(await _dmRpc('pw_dm_open', {'p_peer': _uuid(peerId)}));

  Future<List<WebDmMessage>> conversation(
    String id, {
    String? before,
    int limit = 50,
  }) async {
    _limit(limit, 100);
    return _rows(
          await _dmRpc('pw_dm_history', {
            'p_conv': _uuid(id),
            'p_before': before,
            'p_limit': limit,
          }),
        )
        .map(
          (x) => WebDmMessage(
            _identifier(x['id']),
            _str(x['conversation_id']),
            _str(x['sender_id']),
            _str(x['body']),
            _str(x['created_at']),
            editedAt: _optionalString(x['edited_at']),
          ),
        )
        .toList(growable: false);
  }

  /// The caller retains the nonce across retries to preserve server idempotency.
  Future<WebDmReceipt> sendMessage({
    required String conversationId,
    required String nonce,
    required String body,
  }) async {
    _enabled(messagingEnabled);
    if (body.trim().isEmpty || body.length > 600) {
      throw ArgumentError('Invalid message');
    }
    return _receipt(
      await _request(
        'POST',
        '/api/private-messages/send',
        body: {
          'conversationId': _uuid(conversationId),
          'nonce': _uuid(nonce),
          'body': body,
        },
        allowRetryReceipt: true,
      ),
    );
  }

  Future<WebDmReceipt?> messageStatus(String nonce) async {
    final data = await _dmRpc('pw_dm_status', {'p_nonce': _uuid(nonce)});
    return data == null ? null : _receipt(data);
  }

  Future<String> markRead(String conversationId, String messageId) async =>
      _identifier(
        await _dmRpc('pw_dm_mark_read', {
          'p_conv': _uuid(conversationId),
          'p_message': messageId,
        }),
      );
  Future<int> unread(String conversationId) async =>
      _int(await _dmRpc('pw_dm_unread', {'p_conv': _uuid(conversationId)}));
  Future<void> withdraw(String messageId) async {
    await _dmRpc('pw_dm_withdraw', {'p_message': messageId});
  }

  Future<String> reportMessage(String messageId, String reason) async {
    if (!['spam', 'abuse', 'sexual', 'fraud', 'other'].contains(reason)) {
      throw ArgumentError('Invalid reason');
    }
    return _str(
      await _dmRpc('pw_dm_report', {
        'p_message': messageId,
        'p_reason': reason,
      }),
    );
  }

  Future<void> blockUser(String peerId, bool blocked) async {
    await _dmRpc('pw_dm_block', {
      'p_peer': _uuid(peerId),
      'p_blocked': blocked,
    });
  }

  Future<WebReportReceipt> reportUser({
    required String targetUserId,
    required String kind,
    required String reason,
    String? detail,
    String? sourceWorkId,
  }) async {
    _enabled(reportsEnabled);
    final x = _map(
      await _request(
        'POST',
        '/functions/v1/submit-report',
        supabase: true,
        body: {
          'target_user_id': _uuid(targetUserId),
          'kind': kind,
          'reason': reason,
          'detail': ?detail,
          if (sourceWorkId != null) 'source_work_id': _uuid(sourceWorkId),
        },
      ),
    );
    if (x['ok'] != true) _invalid();
    return WebReportReceipt(
      _identifier(x['report_id']),
      x['duplicate'] == true,
    );
  }

  Future<List<WebReportHistory>> myReports() async {
    _enabled(reportsEnabled);
    final x = _map(
      await _request('POST', '/functions/v1/my-reports', supabase: true),
    );
    if (x['ok'] != true) _invalid();
    return _rows(
      x['reports'],
    ).map(WebReportHistory.new).toList(growable: false);
  }

  Future<WebAccountErasureState> requestAccountDeletion({
    required bool confirmed,
  }) async {
    _enabled(deletionEnabled);
    if (!confirmed) throw ArgumentError('Explicit confirmation required');
    final userId = currentUserId();
    if (userId == null) {
      throw const WebSocialUnavailableException('authentication_required');
    }
    final x = _map(
      await _request(
        'POST',
        '/functions/v1/delete-account',
        supabase: true,
        body: const {'confirm': true},
      ),
    );
    if (x['ok'] != true) _invalid();
    if (x['erasure_pending'] == true &&
        x['account_erasure_status'] == 'requested' &&
        x['requested_user_id'] == userId) {
      return WebAccountErasureState.requested;
    }
    if (x['erasure_pending'] == true ||
        x['account_erasure_status'] == 'requested') {
      _invalid();
    }
    if (x['deleted_user_id'] != userId) _invalid();
    return WebAccountErasureState.completed;
  }

  Future<dynamic> _dmRpc(String name, Map<String, dynamic> args) {
    _enabled(messagingEnabled);
    if (!['china', 'international'].contains(region) ||
        authNamespace == null ||
        !authNamespace!.startsWith('$region.')) {
      throw const WebSocialUnavailableException('configuration_required');
    }
    return _request(
      'POST',
      '/rest/v1/rpc/$name',
      supabase: true,
      body: {'p_region': region, 'p_namespace': authNamespace, ...args},
    );
  }

  Future<dynamic> _request(
    String method,
    String path, {
    bool supabase = false,
    Map<String, String>? query,
    Map<String, dynamic>? body,
    bool allowRetryReceipt = false,
  }) async {
    final origin = supabase ? supabaseOrigin : apiOrigin;
    if (origin == null ||
        origin.scheme != 'https' ||
        origin.userInfo.isNotEmpty ||
        origin.path != '' && origin.path != '/' ||
        origin.hasQuery ||
        origin.hasFragment ||
        (supabase && (publishableKey == null || publishableKey!.isEmpty))) {
      throw const WebSocialUnavailableException('configuration_required');
    }
    final token = accessToken();
    if (token == null || token.isEmpty) {
      throw const WebSocialUnavailableException('authentication_required');
    }
    final request = http.Request(
      method,
      origin.replace(path: path, queryParameters: query),
    );
    request.followRedirects = false;
    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      if (supabase) 'apikey': publishableKey!,
    });
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request),
      ).timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const WebSocialUnavailableException('transport_unavailable');
    }
    if (accessToken() != token) {
      throw const WebSocialUnavailableException('session_changed');
    }
    dynamic data;
    try {
      data = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      throw const WebSocialUnavailableException('invalid_response');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (allowRetryReceipt &&
          response.statusCode == 503 &&
          data is Map &&
          data['state'] == 'retry') {
        return data;
      }
      if ([404, 405, 501, 502, 503, 504].contains(response.statusCode)) {
        throw const WebSocialUnavailableException();
      }
      throw WebSocialRequestException(response.statusCode);
    }
    return data;
  }

  static WebDmReceipt _receipt(dynamic data) {
    final x = _map(data), state = _str(_map(data)['state']);
    final values = WebDmState.values.where((v) => v.name == state);
    if (values.isEmpty) _invalid();
    return WebDmReceipt(
      _str(x['id']),
      values.first,
      x['messageId'] == null ? null : _identifier(x['messageId']),
    );
  }

  static void _enabled(bool enabled) {
    if (!enabled) throw const WebSocialUnavailableException('not_configured');
  }

  static void _limit(int n, int max) {
    if (n < 1 || n > max) throw ArgumentError('Invalid page size');
  }

  static String _uuid(String id) {
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(id)) {
      throw ArgumentError('Invalid ID');
    }
    return id;
  }

  static Never _invalid() =>
      throw const WebSocialUnavailableException('invalid_response');
  static Map<String, dynamic> _map(dynamic x) {
    if (x is! Map<String, dynamic>) _invalid();
    return x;
  }

  static List<Map<String, dynamic>> _rows(dynamic x) {
    if (x is! List) _invalid();
    return x.map(_map).toList(growable: false);
  }

  static String _str(dynamic x) {
    if (x is! String) _invalid();
    return x;
  }

  static String? _optionalString(dynamic x) => x == null ? null : _str(x);
  static String _identifier(dynamic x) {
    if (x is String && x.isNotEmpty) return x;
    if (x is int && x > 0) return '$x';
    _invalid();
  }

  static bool _bool(dynamic x) {
    if (x is! bool) _invalid();
    return x;
  }

  static int _int(dynamic x) {
    if (x is! int) _invalid();
    return x;
  }
}
