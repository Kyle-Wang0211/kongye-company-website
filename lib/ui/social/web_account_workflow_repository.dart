import 'package:supabase_flutter/supabase_flutter.dart';

import '../../community/social_profile_repository.dart';
import 'web_account_privacy_page.dart';
import 'web_report_history_page.dart';
import 'web_report_review_page.dart';

typedef WebWorkflowInvoke =
    Future<FunctionResponse> Function(String name, Map<String, dynamic> body);

/// Uses the existing official Supabase Functions client and caller session.
class WebAccountWorkflowRepository {
  WebAccountWorkflowRepository({
    required SupabaseClient client,
    required this.accountId,
    WebWorkflowInvoke? invoke,
    String? Function()? userIdProvider,
  }) : _client = client,
       _userId = userIdProvider ?? (() => client.auth.currentUser?.id),
       _invoke =
           invoke ??
           ((name, body) => client.functions.invoke(name, body: body));
  final SupabaseClient _client;
  final String? Function() _userId;
  final String accountId;
  final WebWorkflowInvoke _invoke;
  void _checkOwner() {
    if (_userId() != accountId) throw StateError('Account changed');
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> body, {
    int status = 200,
  }) async {
    _checkOwner();
    final response = await _invoke(name, body);
    _checkOwner();
    if (response.status != status ||
        response.data is! Map ||
        response.data['ok'] != true) {
      throw StateError('Request not confirmed');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<WebDeletionRequestStatus> requestDeletion() async {
    final data = await _call('delete-account', {'confirm': true}, status: 202);
    if (data['account_erasure_status'] != 'requested' ||
        data['erasure_pending'] != true ||
        data['requested_user_id'] != accountId) {
      throw StateError('Invalid erasure receipt');
    }
    return WebDeletionRequestStatus.pending;
  }

  Future<void> withdraw(String workId) async {
    final data = await _call('publication-review', {
      'action': 'withdraw',
      'work_id': workId,
    });
    if (data['work_id'] != workId ||
        data['status'] != 'withdrawn' ||
        data['physical_erasure'] != 'held' ||
        data['evidence_retained'] != true) {
      throw StateError('Invalid withdrawal receipt');
    }
  }

  Future<List<WebBlockedUser>> blockedUsers() async {
    _checkOwner();
    final rows = await SupabaseSocialProfileRepository(
      client: _client,
    ).fetchBlockedUsers();
    _checkOwner();
    return rows
        .map((row) => WebBlockedUser(id: row.id, displayName: row.displayName))
        .toList();
  }

  Future<void> unblock(String userId) async {
    _checkOwner();
    await SupabaseSocialProfileRepository(client: _client).unblock(userId);
    _checkOwner();
  }

  Future<List<WebReportSummary>> reports() async {
    _checkOwner();
    final rows = await SupabaseSocialProfileRepository(
      client: _client,
    ).fetchMyReports();
    _checkOwner();
    return rows
        .map(
          (row) => WebReportSummary(
            id: row.id,
            targetTitle: row.sourceWorkTitle ?? '',
            kind: row.kind,
            sourceWorkTitle: row.sourceWorkTitle,
            reason: row.reason.code,
            status: row.status.code,
            createdAt: row.createdAt,
            outcome: row.reporterFeedback,
          ),
        )
        .toList();
  }

  Future<WebReportReviewQueue> reviewQueue() async {
    final identity = await _call('admin-reports', {'action': 'whoami'});
    final role = identity['role'];
    if (identity['user_id'] != accountId ||
        !['reviewer', 'lead'].contains(role)) {
      throw StateError('Reviewer access unavailable');
    }
    final items = <WebReportReviewItem>[];
    for (final status in ['pending', 'in_review', 'needs_info', 'actioned']) {
      final response = await _call('admin-reports', {
        'action': 'list',
        'status': status,
      });
      final rows = response['reports'];
      if (rows is! List) throw const FormatException('Invalid queue');
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id'];
        if (id is! int ||
            id <= 0 ||
            row['status'] is! String ||
            row['reason'] is! String ||
            row['target_id'] is! String) {
          throw const FormatException('Invalid report');
        }
        items.add(
          WebReportReviewItem(
            id: id,
            reason: row['reason'],
            status: row['status'],
            targetId: row['target_id'],
            detail: row['detail'] as String? ?? '',
            claimedBy: row['claimed_by'] as String?,
            sourceWorkId: row['source_work_id'] as String?,
          ),
        );
      }
    }
    return WebReportReviewQueue(
      userId: accountId,
      role: role as String,
      items: items,
    );
  }

  Future<void> restoreWork(String workId) async {
    final data = await _call('admin-moderate-work', {
      'work_id': workId,
      'status': 'ok',
    });
    if (data['work_id'] != workId ||
        data['status'] != 'ok' ||
        data['assets_failed'] != 0 ||
        data['failed'] is! List ||
        (data['failed'] as List).isNotEmpty) {
      throw StateError('Restore not confirmed');
    }
  }

  Future<void> claimReport(int id) async {
    await _call('admin-reports', {'action': 'claim', 'report_id': id});
  }

  Future<void> transitionReport(int id, String status, String feedback) async {
    if (!['needs_info', 'dismissed', 'actioned'].contains(status) ||
        feedback.trim().isEmpty) {
      throw ArgumentError('Invalid report transition');
    }
    await _call('admin-reports', {
      'action': 'transition',
      'report_id': id,
      'status': status,
      'reporter_feedback': feedback.trim(),
    });
  }
}
