import 'package:supabase_flutter/supabase_flutter.dart';

enum AccountWorkLibraryKind { likes, history }

class AccountWorkLibraryCursor {
  const AccountWorkLibraryCursor(this.activityAt, this.workId);
  // Preserve Postgres microsecond precision for the composite cursor.
  final String activityAt;
  final String workId;
}

class AccountWorkLibraryItem {
  const AccountWorkLibraryItem({
    required this.workId,
    required this.authorId,
    required this.title,
    required this.authorDisplayName,
    required this.activityAt,
    this.thumbnailStoragePath,
  });
  final String workId, authorId, title, authorDisplayName, activityAt;
  final String? thumbnailStoragePath;

  factory AccountWorkLibraryItem.fromJson(Map<String, dynamic> row) =>
      AccountWorkLibraryItem(
        workId: row['work_id'] as String,
        authorId: row['author_id'] as String,
        title: row['title'] as String? ?? '',
        authorDisplayName: row['author_display_name'] as String? ?? '',
        activityAt: row['activity_at'] as String,
        thumbnailStoragePath: row['thumbnail_storage_path'] as String?,
      );
}

class AccountWorkLibraryPageResult {
  const AccountWorkLibraryPageResult(this.items, this.next);
  final List<AccountWorkLibraryItem> items;
  final AccountWorkLibraryCursor? next;
}

/// Caller-scoped RPCs return only the currently visible works for this account.
class AccountWorkLibraryRepository {
  AccountWorkLibraryRepository({required this.client, required this.ownerId});
  final SupabaseClient client;
  final String ownerId;
  static const pageSize = 30;

  void _requireOwner() {
    if (client.auth.currentUser?.id != ownerId) {
      throw StateError('Account changed');
    }
  }

  Future<AccountWorkLibraryPageResult> load(
    AccountWorkLibraryKind kind, {
    AccountWorkLibraryCursor? before,
  }) async {
    _requireOwner();
    final rows = await client
        .rpc(
          kind == AccountWorkLibraryKind.likes
              ? 'list_my_liked_works'
              : 'list_my_view_history',
          params: {
            'p_limit': pageSize,
            if (before != null) ...{
              'p_before_time': before.activityAt,
              'p_before_id': before.workId,
            },
          },
        )
        .timeout(const Duration(seconds: 15));
    _requireOwner();
    final items = (rows as List)
        .map(
          (row) => AccountWorkLibraryItem.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
    final last = items.isEmpty ? null : items.last;
    return AccountWorkLibraryPageResult(
      items,
      items.length < pageSize || last == null
          ? null
          : AccountWorkLibraryCursor(last.activityAt, last.workId),
    );
  }

  /// Enrich a favorites API page in two bounded queries, preserving API order.
  Future<Map<String, AccountWorkLibraryItem>> visibleWorkSummaries(
    List<String> workIds,
  ) async {
    _requireOwner();
    if (workIds.isEmpty) return const {};
    final rows = await client
        .from('works')
        .select('id,user_id,title,thumbnail_storage_path')
        .inFilter('id', workIds)
        .eq('visibility', 'public')
        .eq('moderation_status', 'ok')
        .not('published_at', 'is', null)
        .isFilter('deleted_at', null)
        .timeout(const Duration(seconds: 15));
    _requireOwner();
    if (rows.isEmpty) return const {};
    final authorIds = rows
        .map((row) => row['user_id'] as String)
        .toSet()
        .toList();
    final profiles = await client
        .from('community_author_profiles')
        .select('id,display_name')
        .inFilter('id', authorIds)
        .timeout(const Duration(seconds: 15));
    _requireOwner();
    final names = {
      for (final profile in profiles)
        profile['id']: profile['display_name'] as String? ?? '',
    };
    return {
      for (final row in rows)
        row['id'] as String: AccountWorkLibraryItem(
          workId: row['id'] as String,
          authorId: row['user_id'] as String,
          title: row['title'] as String? ?? '',
          thumbnailStoragePath: row['thumbnail_storage_path'] as String?,
          authorDisplayName: names[row['user_id']] ?? '',
          activityAt: '',
        ),
    };
  }
}
