import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/backend_deployment.dart';
import '../../config/endpoint_config.dart';
import 'comment_models.dart';
import 'comment_moderation_models.dart';
import 'comment_moderation_repository.dart'
    show CommunityCommentModerationRepository;

abstract class CommunityCommentRepository {
  Future<CommunityCommentPage> fetch(String workId);
  Future<CommunityComment> submit(CommunityCommentDraft draft);
  Future<void> remove(String workId, String commentId);
  Future<CommunityComment> setLiked(
    String workId,
    String commentId,
    bool liked,
  );
}

abstract class CommunityCommentFeedRepository {
  Future<CommunityCommentPage> fetchSection(
    String workId, {
    required CommunityCommentSection section,
    String? cursor,
  });
}

abstract class CommunityCommentReportRepository {
  Future<String> report(CommunityCommentReportDraft draft);
}

/// Captured before each request and rechecked before consuming any response.
/// Generation must change on a new auth session, even for the same account.
class CommunityCommentIdentity {
  const CommunityCommentIdentity({
    required this.userId,
    required this.regionKey,
    required this.generation,
    this.readRetryScope,
  });
  final String userId;
  final String regionKey;
  final Object generation;

  /// Opaque client/endpoint-credential scope; only read requests may restart
  /// once after the session generation changes within this unchanged scope.
  /// A restarted read discards the old response and rechecks the new snapshot.
  final Object? readRetryScope;
  @override
  bool operator ==(Object other) =>
      other is CommunityCommentIdentity &&
      other.userId == userId &&
      other.regionKey == regionKey &&
      other.generation == generation;
  @override
  int get hashCode => Object.hash(userId, regionKey, generation);
}

class CommunityCommentException implements Exception {
  const CommunityCommentException(this.code);
  final String code;
  String get message => switch (code) {
    'auth_required' => '请登录后发表评论',
    'identity_changed' => '账号或服务区域已变化，请重新打开评论',
    'timeout' => '评论请求超时，请重试',
    'invalid_draft' => '请检查评论文字和图片',
    'invalid_response' => '评论响应无效，请稍后重试',
    _ => '评论服务暂不可用，请稍后重试',
  };
  @override
  String toString() => 'CommunityCommentException($code): $message';
}

typedef CommunityCommentTransport =
    Future<Object?> Function(Map<String, dynamic> body);
typedef CommunityCommentIdentityReader = CommunityCommentIdentity? Function();

class _CommunityCommentGateway {
  _CommunityCommentGateway({
    SupabaseClient? client,
    CommunityCommentTransport? transport,
    CommunityCommentIdentityReader? identity,
    Duration requestTimeout = const Duration(seconds: 30),
  }) : _clientOverride = client,
       _transport = transport,
       _identity = identity,
       _requestTimeout = requestTimeout {
    if (requestTimeout <= Duration.zero ||
        requestTimeout > const Duration(seconds: 30)) {
      throw ArgumentError(
        'Request timeout must be positive and at most 30 seconds',
      );
    }
  }
  final Duration _requestTimeout;
  final SupabaseClient? _clientOverride;
  final CommunityCommentTransport? _transport;
  final CommunityCommentIdentityReader? _identity;

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;
  CommunityCommentIdentity? _readIdentity() {
    if (_identity != null) return _identity();
    final client = _client;
    final config = EndpointConfigResolver.current;
    if (config == null) throw const CommunityCommentException('unavailable');
    config.deployment.validate();
    final origin = BackendDeployment.httpsOrigin(config.supabaseUrl);
    final restUri = Uri.tryParse(client.rest.url);
    if (origin == null ||
        !config.deployment.acceptsApi(
          config.supabaseUrl,
          config.supabaseAnonKey,
        ) ||
        restUri == null ||
        restUri.origin != origin ||
        restUri.path != '/rest/v1' ||
        restUri.hasQuery ||
        restUri.hasFragment ||
        restUri.userInfo.isNotEmpty) {
      throw const CommunityCommentException('unavailable');
    }
    final session = client.auth.currentSession;
    if (session == null || session.isExpired) return null;
    // Client identity partitions regional endpoints. Session object identity also
    // invalidates sign-out/sign-in to the same user and credential refresh.
    return CommunityCommentIdentity(
      userId: session.user.id,
      regionKey: '${config.deployment.namespace}|${config.supabaseUrl}',
      generation: (client, session, config.supabaseAnonKey),
      readRetryScope: (client, config.supabaseAnonKey),
    );
  }

  CommunityCommentIdentity? _requestIdentity({required bool allowAnonymous}) {
    final identity = _readIdentity();
    if (identity != null || !allowAnonymous) return identity;
    // An anonymous read is still partitioned by the actual client and endpoint.
    // A login, sign-out, endpoint change or credential rotation invalidates it.
    if (_identity != null) {
      return const CommunityCommentIdentity(
        userId: '',
        regionKey: 'anonymous-test',
        generation: 'anonymous',
      );
    }
    final config = EndpointConfigResolver.current!;
    return CommunityCommentIdentity(
      userId: '',
      regionKey: '${config.deployment.namespace}|${config.supabaseUrl}',
      generation: (_client, config.supabaseAnonKey),
    );
  }

  bool _isCurrent(CommunityCommentIdentity expected) {
    try {
      return _requestIdentity(allowAnonymous: expected.userId.isEmpty) ==
          expected;
    } catch (_) {
      return false;
    }
  }

  bool _canRestartRead(CommunityCommentIdentity expected) {
    if (expected.userId.isEmpty || expected.readRetryScope == null) {
      return false;
    }
    try {
      final current = _requestIdentity(allowAnonymous: false);
      return current != null &&
          current.userId == expected.userId &&
          current.regionKey == expected.regionKey &&
          current.readRetryScope == expected.readRetryScope &&
          current != expected;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _request(
    Map<String, dynamic> body, {
    bool allowReadRetry = true,
  }) async {
    CommunityCommentIdentity? expected;
    try {
      expected = _requestIdentity(allowAnonymous: body['op'] == 'list');
    } catch (_) {
      throw const CommunityCommentException('unavailable');
    }
    if (expected == null || expected.regionKey.isEmpty) {
      throw const CommunityCommentException('auth_required');
    }
    try {
      Object? data;
      if (_transport != null) {
        data = await _transport(body).timeout(_requestTimeout);
      } else {
        final response = await _client.functions
            .invoke(
              'community-comments',
              body: body,
              headers: {
                'Authorization':
                    'Bearer ${expected.userId.isEmpty ? EndpointConfigResolver.current!.supabaseAnonKey : _client.auth.currentSession!.accessToken}',
              },
            )
            .timeout(_requestTimeout);
        if (response.status != 200 && response.status != 202) {
          throw const CommunityCommentException('unavailable');
        }
        data = response.data;
        if (response.status == 202) {
          final comment = data is Map<String, dynamic> ? data['comment'] : null;
          final moderationCase = data is Map<String, dynamic>
              ? data['case']
              : null;
          final acceptedSubmit =
              body['op'] == 'submit' &&
              comment is Map<String, dynamic> &&
              (({'pending', 'review'}.contains(comment['status']) &&
                      comment['is_public'] == false) ||
                  (comment['status'] == 'published' &&
                      comment['is_public'] == true &&
                      comment['moderation_pending'] == true));
          final acceptedAppeal =
              body['op'] == 'appeal' &&
              moderationCase is Map<String, dynamic> &&
              moderationCase['is_hidden'] == true &&
              moderationCase['appeal_status'] == 'submitted';
          if (!acceptedSubmit && !acceptedAppeal) {
            throw const CommunityCommentException('invalid_response');
          }
        }
      }
      if (!_isCurrent(expected)) {
        throw const CommunityCommentException('identity_changed');
      }
      if (data is! Map<String, dynamic> || data['error'] != null) {
        throw const CommunityCommentException('invalid_response');
      }
      return data;
    } on CommunityCommentException {
      if (!_isCurrent(expected)) {
        if (allowReadRetry &&
            body['op'] == 'list' &&
            _canRestartRead(expected)) {
          return _request(body, allowReadRetry: false);
        }
        throw const CommunityCommentException('identity_changed');
      }
      rethrow;
    } on TimeoutException {
      if (!_isCurrent(expected)) {
        throw const CommunityCommentException('identity_changed');
      }
      throw const CommunityCommentException('timeout');
    } catch (_) {
      // Never leak remote error messages, comment content, or authentication data.
      if (!_isCurrent(expected)) {
        throw const CommunityCommentException('identity_changed');
      }
      throw const CommunityCommentException('unavailable');
    }
  }

  void _validateId(String value) {
    if (value.trim().isEmpty) {
      throw const CommunityCommentException('invalid_draft');
    }
  }
}

class SupabaseCommunityCommentRepository extends _CommunityCommentGateway
    implements
        CommunityCommentRepository,
        CommunityCommentFeedRepository,
        CommunityCommentReportRepository {
  SupabaseCommunityCommentRepository({
    super.client,
    super.transport,
    super.identity,
    super.requestTimeout = const Duration(seconds: 30),
  });

  @override
  Future<String> report(CommunityCommentReportDraft draft) async {
    Map<String, dynamic> payload;
    try {
      payload = draft.toJson();
    } catch (_) {
      throw const CommunityCommentException('invalid_draft');
    }
    final result = await _request({'op': 'report', ...payload});
    final id = result['report_id'];
    if (result['status'] != 'submitted' ||
        id is! String ||
        !RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(id) ||
        BigInt.parse(id) > BigInt.parse('9223372036854775807')) {
      throw const CommunityCommentException('invalid_response');
    }
    return id;
  }

  CommunityComment _decodeComment(
    Object? value,
    String workId, {
    String? commentId,
    bool mustOwn = false,
  }) {
    try {
      if (value is! Map<String, dynamic>) throw const FormatException();
      final comment = CommunityComment.fromJson(value);
      final current = _readIdentity();
      if (comment.workId != workId ||
          (commentId != null && comment.id != commentId) ||
          !comment.visibleTo(current?.userId) ||
          (mustOwn && comment.userId != current?.userId)) {
        throw const FormatException();
      }
      return comment;
    } catch (_) {
      throw const CommunityCommentException('invalid_response');
    }
  }

  @override
  Future<CommunityCommentPage> fetch(String workId) async {
    _validateId(workId);
    final data = await _request({'op': 'list', 'work_id': workId});
    return _decodePage(data, workId);
  }

  @override
  Future<CommunityCommentPage> fetchSection(
    String workId, {
    required CommunityCommentSection section,
    String? cursor,
  }) async {
    _validateId(workId);
    if (cursor != null &&
        !RegExp(r'^(?:[a-f0-9]{2}){1,1024}$').hasMatch(cursor)) {
      throw const CommunityCommentException('invalid_draft');
    }
    final request = <String, dynamic>{
      'op': 'list',
      'work_id': workId,
      'section': section.name,
      'limit': communityCommentPageSize,
    };
    if (cursor != null) request['cursor'] = cursor;
    final data = await _request(request);
    if (data['section'] != section.name ||
        data['comments'] is! List ||
        (data['comments'] as List).length > communityCommentPageSize) {
      throw const CommunityCommentException('invalid_response');
    }
    return _decodePage(data, workId);
  }

  CommunityCommentPage _decodePage(Map<String, dynamic> data, String workId) {
    try {
      final revision = data['asset_revision'];
      final assetSha256 = data['asset_sha256'];
      if (assetSha256 != null &&
          (assetSha256 is! String ||
              !RegExp(r'^[a-f0-9]{64}$').hasMatch(assetSha256))) {
        throw const FormatException();
      }
      final canComment = data['can_comment'];
      final publicCount = data['public_count'];
      final rows = data['comments'];
      if (revision is! String ||
          revision.isEmpty ||
          canComment is! bool ||
          publicCount is! int ||
          publicCount < 0 ||
          rows is! List) {
        throw const FormatException();
      }
      final comments = <CommunityComment>[];
      final seen = <String>{};
      for (final value in rows) {
        if (value is! Map<String, dynamic>) throw const FormatException();
        final comment = CommunityComment.fromJson(value);
        if (comment.workId != workId || !seen.add(comment.id)) {
          throw const FormatException();
        }
        if (comment.visibleTo(_readIdentity()?.userId)) comments.add(comment);
      }
      final nextCursor = data['next_cursor'];
      if (nextCursor != null &&
          (nextCursor is! String ||
              !RegExp(r'^(?:[a-f0-9]{2}){1,1024}$').hasMatch(nextCursor))) {
        throw const FormatException();
      }
      final contextRows = data['context_comments'] ?? const [];
      if (contextRows is! List) throw const FormatException();
      final context = <CommunityComment>[];
      for (final row in contextRows) {
        final c = _decodeComment(row, workId);
        if (!seen.add(c.id)) throw const FormatException();
        context.add(c);
      }
      return CommunityCommentPage(
        nextCursor: nextCursor as String?,
        contextComments: context,
        assetRevision: revision,
        assetSha256: assetSha256 as String?,
        comments: comments,
        canComment: _readIdentity() != null && canComment,
        publicCount: publicCount,
      );
    } catch (_) {
      throw const CommunityCommentException('invalid_response');
    }
  }

  @override
  Future<CommunityComment> submit(CommunityCommentDraft draft) async {
    Map<String, dynamic> body;
    try {
      body = draft.toJson();
    } catch (_) {
      throw const CommunityCommentException('invalid_draft');
    }
    final data = await _request({'op': 'submit', ...body});
    return _decodeComment(data['comment'], draft.workId, mustOwn: true);
  }

  @override
  Future<void> remove(String workId, String commentId) async {
    _validateId(workId);
    _validateId(commentId);
    final data = await _request({
      'op': 'remove',
      'work_id': workId,
      'comment_id': commentId,
    });
    if (data['removed'] != true ||
        data['comment_id'] != commentId ||
        data['work_id'] != workId) {
      throw const CommunityCommentException('invalid_response');
    }
  }

  @override
  Future<CommunityComment> setLiked(
    String workId,
    String commentId,
    bool liked,
  ) async {
    _validateId(workId);
    _validateId(commentId);
    final data = await _request({
      'op': 'like',
      'work_id': workId,
      'comment_id': commentId,
      'liked': liked,
    });
    final comment = _decodeComment(
      data['comment'],
      workId,
      commentId: commentId,
    );
    if (!comment.published || comment.likedByMe != liked) {
      throw const CommunityCommentException('invalid_response');
    }
    return comment;
  }
}

/// Uses exactly the comment gateway's auth, regional identity and timeout guards.
class SupabaseCommunityCommentModerationRepository
    extends _CommunityCommentGateway
    implements CommunityCommentModerationRepository {
  SupabaseCommunityCommentModerationRepository({
    super.client,
    super.transport,
    super.identity,
    super.requestTimeout = const Duration(seconds: 30),
  });

  @override
  Future<List<CommunityCommentNotice>> fetchNotices() async {
    final data = await _request({'op': 'inbox'});
    try {
      final rows = data['notifications'];
      if (rows is! List) throw const FormatException();
      final notices = <CommunityCommentNotice>[];
      final seen = <String>{};
      final owner = _readIdentity()?.userId;
      for (final row in rows) {
        if (row is! Map<String, dynamic> ||
            row['recipient_id'] != owner ||
            row['payload'] is! Map<String, dynamic>) {
          throw const FormatException();
        }
        final payload = row['payload'] as Map<String, dynamic>;
        final subtype = payload['subtype'];
        if (subtype is! String || subtype.trim().isEmpty) {
          throw const FormatException();
        }
        // This endpoint may also return unrelated system announcements.
        if (!CommunityCommentNotice.isCommentSubtype(subtype)) continue;
        final notice = CommunityCommentNotice.fromJson(row);
        if (!seen.add(notice.id)) throw const FormatException();
        notices.add(notice);
      }
      return List.unmodifiable(notices);
    } catch (_) {
      throw const CommunityCommentException('invalid_response');
    }
  }

  @override
  Future<void> markRead(String noticeId) async {
    _validateId(noticeId);
    final data = await _request({
      'op': 'mark_notice_read',
      'notice_id': noticeId,
    });
    if (data['read'] != true ||
        data['notice_id'] != noticeId ||
        data['recipient_id'] != _readIdentity()?.userId) {
      throw const CommunityCommentException('invalid_response');
    }
  }

  CommunityCommentModerationCase _decodeCase(Object? value, String caseId) {
    try {
      if (value is! Map<String, dynamic>) throw const FormatException();
      final moderationCase = CommunityCommentModerationCase.fromJson(value);
      if (moderationCase.id != caseId ||
          moderationCase.ownerId != _readIdentity()?.userId) {
        throw const FormatException();
      }
      return moderationCase;
    } catch (_) {
      throw const CommunityCommentException('invalid_response');
    }
  }

  @override
  Future<CommunityCommentModerationCase> fetchCase(String caseId) async {
    _validateId(caseId);
    final data = await _request({'op': 'case', 'case_id': caseId});
    return _decodeCase(data['case'], caseId);
  }

  @override
  Future<CommunityCommentModerationCase> submitAppeal({
    required String caseId,
    required String statement,
    required String clientRequestId,
  }) async {
    _validateId(caseId);
    _validateId(clientRequestId);
    if (statement.trim().isEmpty || statement.length > 1000) {
      throw const CommunityCommentException('invalid_draft');
    }
    final data = await _request({
      'op': 'appeal',
      'case_id': caseId,
      'statement': statement,
      'client_request_id': clientRequestId,
    });
    return _decodeCase(data['case'], caseId);
  }
}
