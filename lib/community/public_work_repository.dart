import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/endpoint_config.dart';
import 'feed_models.dart';

String? publicWorkId(Uri location) {
  final id = location.queryParameters['work'];
  return id != null &&
          RegExp(
            r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
          ).hasMatch(id)
      ? id
      : null;
}

/// The same public work and author projection as the homepage, bounded to one ID.
class PublicWorkRepository {
  PublicWorkRepository(this.client);
  final SupabaseClient client;
  // Keep the established API authoritative for callers that toggle likes.
  Future<FeedWork> fetch(String id) async {
    final session = client.auth.currentSession;
    final viewerId = client.auth.currentUser?.id;
    var work = await _readWork(client.rest, id);
    final enrichment = await Future.wait<FeedWork>([
      _readAuthor(client.rest, work).catchError((_) => work),
      fetchLike(work),
    ]);
    work = enrichment[0];
    final liked = enrichment[1];
    if (!identical(client.auth.currentSession, session) ||
        client.auth.currentUser?.id != viewerId) {
      throw StateError('Public work account changed during load');
    }
    return work.copyWith(likedByMe: liked.likedByMe, likeStateKnown: true);
  }

  PostgrestClient _publicClient() {
    final config = EndpointConfigResolver.current;
    // Bind the anonymous key to this client's actual regional endpoint.
    if (config == null ||
        client.rest.url != '${config.supabaseUrl}/rest/v1' ||
        !config.deployment.acceptsApi(
          config.supabaseUrl,
          config.supabaseAnonKey,
        )) {
      throw StateError('Public work endpoint unavailable');
    }
    return PostgrestClient(
      client.rest.url,
      headers: {
        'apikey': config.supabaseAnonKey,
        'Authorization': 'Bearer ${config.supabaseAnonKey}',
      },
    );
  }

  /// The shared route reads public content without waiting for personal auth.
  Future<FeedWork> fetchPublic(String id) async {
    final rest = _publicClient();
    try {
      return await _readWork(rest, id);
    } finally {
      await rest.dispose();
    }
  }

  Future<FeedWork> fetchAuthor(FeedWork work) async {
    final rest = _publicClient();
    try {
      return await _readAuthor(rest, work);
    } finally {
      await rest.dispose();
    }
  }

  Future<FeedWork> _readAuthor(PostgrestClient rest, FeedWork work) async {
    final profile = await rest
        .from('community_author_profiles')
        .select('id,display_name,avatar_url,handle')
        .eq('id', work.userId)
        .maybeSingle()
        .timeout(const Duration(seconds: 15));
    return work.copyWith(
      authorDisplayName: profile?['display_name'] as String?,
      authorAvatarUrl: profile?['avatar_url'] as String?,
      authorHandle: profile?['handle'] as String?,
    );
  }

  Future<FeedWork> fetchLike(FeedWork work) async {
    final session = client.auth.currentSession;
    final viewerId = client.auth.currentUser?.id;
    final row = viewerId == null
        ? null
        : await client
              .from('work_likes')
              .select('work_id')
              .eq('user_id', viewerId)
              .eq('work_id', work.id)
              .maybeSingle()
              .timeout(const Duration(seconds: 15));
    if (!identical(client.auth.currentSession, session) ||
        client.auth.currentUser?.id != viewerId) {
      throw StateError('Public work account changed during load');
    }
    return work.copyWith(likedByMe: row != null, likeStateKnown: true);
  }

  Future<FeedWork> _readWork(PostgrestClient rest, String id) async {
    if (publicWorkId(Uri(queryParameters: {'work': id})) == null) {
      throw const FormatException('作品链接无效');
    }
    final row = await rest
        .from('works')
        .select(
          'id,user_id,title,description,format,model_storage_path,thumbnail_storage_path,initial_view,file_size_bytes,likes_count,comments_count,views_count,published_at,publish_region',
        )
        .eq('id', id)
        .eq('visibility', 'public')
        .eq('moderation_status', 'ok')
        .not('published_at', 'is', null)
        .isFilter('deleted_at', null)
        .maybeSingle()
        .timeout(const Duration(seconds: 15));
    if (row == null) throw StateError('分享的作品暂不可访问，可能已取消公开。');
    return FeedWork(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      title: row['title'] as String? ?? '',
      description: row['description'] as String?,
      format: row['format'] as String? ?? 'glb',
      modelStoragePath: row['model_storage_path'] as String?,
      initialView: row['initial_view'] is Map
          ? Map<String, dynamic>.from(row['initial_view'] as Map)
          : null,
      thumbnailStoragePath: row['thumbnail_storage_path'] as String?,
      fileSizeBytes: (row['file_size_bytes'] as num?)?.toInt(),
      likedByMe: false,
      likeStateKnown: false,
      likesCount: (row['likes_count'] as num?)?.toInt() ?? 0,
      commentCount: (row['comments_count'] as num?)?.toInt() ?? 0,
      viewsCount: (row['views_count'] as num?)?.toInt() ?? 0,
      publishedAt: DateTime.parse(row['published_at'] as String),
      authorDisplayName: '',
      authorAvatarUrl: null,
      authorHandle: null,
      publishRegion: row['publish_region'] as String?,
    );
  }
}
