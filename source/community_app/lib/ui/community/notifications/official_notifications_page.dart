import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../community/comments/comment_repository.dart';
import 'community_comment_case_page.dart';
import 'moderation_ui_support.dart';

class _OfficialNotice {
  _OfficialNotice(Map<String, dynamic> row)
    : id = row['id'] as String,
      payload = Map<String, dynamic>.from(row['payload'] as Map),
      createdAt = DateTime.parse(row['created_at'] as String),
      readAt = DateTime.tryParse(row['read_at'] as String? ?? '');
  final String id;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime? readAt;
  String get subtype => payload['subtype'] as String? ?? '';
  String reason(bool en) {
    if (!en) return payload['reason_text'] as String? ?? '';
    final english = payload['reason_text_en'] as String?;
    if (english != null && english.isNotEmpty) return english;
    return switch (subtype) {
      'publication_submitted' => 'Your work has been submitted for review.',
      'publication_published' => 'Your work is now visible in the community.',
      'publication_rejected' =>
        'Your work did not pass review. Please review its content before submitting again.',
      'publication_failed' =>
        'Publication could not be completed. Please retry from your work.',
      'work_removed' => 'Your work was removed following a report review.',
      'comment_hidden' =>
        'Your comment was hidden after review. Tap to view the case.',
      'comment_restored' => 'Your comment has been restored.',
      'comment_appeal_rejected' =>
        'Your comment appeal was not approved. Tap to view the case.',
      _ => '',
    };
  }

  String title(bool en) {
    final status = switch (subtype) {
      'publication_submitted' => en ? 'Submitted for review' : '送审成功',
      'publication_published' => en ? 'Published successfully' : '发布成功',
      'publication_rejected' => en ? 'Review not approved' : '审核未通过',
      'publication_failed' => en ? 'Publication failed' : '发布失败',
      'work_removed' => en ? 'Work removed' : '作品下架通知',
      'comment_hidden' => en ? 'Comment hidden' : '评论隐藏通知',
      'comment_restored' => en ? 'Comment restored' : '评论恢复通知',
      'comment_appeal_rejected' => en ? 'Comment appeal declined' : '评论申诉结果',
      _ =>
        payload['title'] as String? ?? (en ? 'Official notification' : '官方通知'),
    };
    final work = payload['work_title'] as String?;
    return work == null || work.isEmpty ? status : '《$work》$status';
  }
}

/// All clients read and acknowledge the same recipient-owned notification rows.
class _OfficialInbox {
  _OfficialInbox(this.ownerId);
  final String ownerId;
  SupabaseClient get client => Supabase.instance.client;
  bool get current => client.auth.currentUser?.id == ownerId;
  Future<List<_OfficialNotice>> load() async {
    if (!current) return const [];
    final rows = await client
        .from('notifications')
        .select('id,payload,read_at,created_at')
        .eq('recipient_id', ownerId)
        .eq('type', 'system_announcement')
        .order('created_at', ascending: false)
        .limit(100);
    if (!current) return const [];
    return rows.map(_OfficialNotice.new).toList();
  }

  Future<void> read(String id) async {
    if (!current) return;
    await client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id)
        .eq('recipient_id', ownerId)
        .isFilter('read_at', null);
  }
}

String _noticeTime(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

class OfficialNotificationsTile extends StatefulWidget {
  const OfficialNotificationsTile({super.key, required this.ownerId});
  final String ownerId;
  @override
  State<OfficialNotificationsTile> createState() =>
      _OfficialNotificationsTileState();
}

class _OfficialNotificationsTileState extends State<OfficialNotificationsTile>
    with
        WidgetsBindingObserver,
        ActiveModerationRefresh<OfficialNotificationsTile> {
  List<_OfficialNotice> _items = const [];
  StreamSubscription<AuthState>? _auth;
  bool _loading = false;
  bool _failed = false;
  int _revision = 0;
  bool get _en => Localizations.localeOf(context).languageCode != 'zh';
  @override
  void initState() {
    super.initState();
    startModerationRefresh(const Duration(seconds: 30));
    _auth = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      _revision++;
      _loading = false;
      if (mounted) {
        setState(() {
          _items = const [];
          _failed = false;
        });
      }
      if (_OfficialInbox(widget.ownerId).current) _load();
    });
    _load();
  }

  @override
  void didUpdateWidget(covariant OfficialNotificationsTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerId != widget.ownerId) {
      _revision++;
      _loading = false;
      _items = const [];
      _load();
    }
  }

  @override
  void refreshModeration() => _load();
  Future<void> _load() async {
    if (_loading) return;
    final revision = _revision;
    _loading = true;
    try {
      final rows = await _OfficialInbox(widget.ownerId).load();
      if (mounted && revision == _revision) {
        setState(() {
          _items = rows;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted && revision == _revision) setState(() => _failed = true);
    } finally {
      if (revision == _revision) _loading = false;
    }
  }

  @override
  void dispose() {
    _auth?.cancel();
    stopModerationRefresh();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_OfficialInbox(widget.ownerId).current) return const SizedBox.shrink();
    final unread = _items.where((notice) => notice.readAt == null).length;
    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: Color(0xffeeeeee),
        child: Icon(Icons.notifications_none, color: Colors.black),
      ),
      title: Text(
        _en ? 'Official notifications' : '官方通知',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        _failed
            ? (_en ? 'Tap to reload' : '点击重新加载')
            : _items.isEmpty
            ? (_en ? 'No official notifications' : '暂无官方通知')
            : _items.first.title(_en),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (unread > 0)
            Text(
              '$unread',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
      onTap: () async {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => OfficialNotificationsPage(ownerId: widget.ownerId),
          ),
        );
        if (mounted) _load();
      },
    );
  }
}

class OfficialNotificationsPage extends StatefulWidget {
  const OfficialNotificationsPage({super.key, required this.ownerId});
  final String ownerId;
  @override
  State<OfficialNotificationsPage> createState() =>
      _OfficialNotificationsPageState();
}

class _OfficialNotificationsPageState extends State<OfficialNotificationsPage>
    with
        WidgetsBindingObserver,
        ActiveModerationRefresh<OfficialNotificationsPage> {
  late Future<List<_OfficialNotice>> _request;
  StreamSubscription<AuthState>? _auth;
  bool get _en => Localizations.localeOf(context).languageCode != 'zh';
  @override
  void initState() {
    super.initState();
    _request = _OfficialInbox(widget.ownerId).load();
    startModerationRefresh(const Duration(seconds: 30));
    _auth = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (mounted) {
        setState(() => _request = Future.value(const []));
        if (_OfficialInbox(widget.ownerId).current) _reload();
      }
    });
  }

  @override
  void refreshModeration() {
    _reload();
  }

  @override
  void dispose() {
    _auth?.cancel();
    stopModerationRefresh();
    super.dispose();
  }

  Future<void> _reload() async {
    final next = _OfficialInbox(widget.ownerId).load();
    setState(() => _request = next);
    await next;
  }

  Future<void> _open(_OfficialNotice notice) async {
    try {
      await _OfficialInbox(widget.ownerId).read(notice.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _en
                  ? 'Could not save read status. Please retry.'
                  : '已读状态保存失败，请重试。',
            ),
          ),
        );
      }
    }
    if (!mounted || !_OfficialInbox(widget.ownerId).current) return;
    final caseId = notice.payload['case_id'];
    if (notice.subtype.startsWith('comment_') &&
        caseId is String &&
        caseId.isNotEmpty) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => CommunityCommentCasePage(
            caseId: caseId,
            repository: SupabaseCommunityCommentModerationRepository(),
            currentUserId: widget.ownerId,
          ),
        ),
      );
    }
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_en ? 'Official notifications' : '官方通知'),
      actions: [
        IconButton(
          tooltip: _en ? 'Refresh' : '刷新',
          onPressed: _reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<List<_OfficialNotice>>(
      future: _request,
      builder: (context, snapshot) {
        if (!_OfficialInbox(widget.ownerId).current) {
          return Center(
            child: Text(_en ? 'Sign in to view notifications' : '请登录后查看通知'),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.grey),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: _reload,
              child: Text(_en ? 'Reload notifications' : '重新加载通知'),
            ),
          );
        }
        final rows = snapshot.data ?? const [];
        if (rows.isEmpty) {
          return Center(
            child: Text(_en ? 'No official notifications' : '暂无官方通知'),
          );
        }
        return RefreshIndicator(
          color: Colors.black,
          onRefresh: _reload,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final notice = rows[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                leading: Icon(
                  notice.readAt == null
                      ? Icons.mark_email_unread_outlined
                      : Icons.drafts_outlined,
                  color: Colors.grey,
                ),
                title: Text(
                  notice.title(_en),
                  style: TextStyle(
                    fontWeight: notice.readAt == null
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  [
                    notice.reason(_en),
                    _noticeTime(notice.createdAt),
                  ].where((text) => text.isNotEmpty).join('\n'),
                ),
                onTap: () => _open(notice),
              );
            },
          ),
        );
      },
    ),
  );
}
