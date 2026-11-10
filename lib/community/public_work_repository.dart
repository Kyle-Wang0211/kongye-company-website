import 'package:supabase_flutter/supabase_flutter.dart';
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
  Future<FeedWork> fetch(String id) async {
    if (publicWorkId(Uri(queryParameters: {'work': id})) == null) {
      throw const FormatException('作品链接无效');
    }
    final viewerId = client.auth.currentUser?.id;
    final row = await client
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
    Future<Map<String, dynamic>?> readLike(String userId) => client
        .from('work_likes')
        .select('work_id')
        .eq('user_id', userId)
        .eq('work_id', id)
        .maybeSingle()
        .timeout(const Duration(seconds: 15));

    Object? likeError;
    StackTrace? likeStack;
    final likeFuture =
        viewerId != null && client.auth.currentUser?.id == viewerId
        ? readLike(viewerId).then<Map<String, dynamic>?>(
            (value) => value,
            onError: (Object error, StackTrace stack) {
              // Preserve profile/auth error priority while this read overlaps.
              likeError = error;
              likeStack = stack;
              return null;
            },
          )
        : null;
    final profile = await client
        .from('community_author_profiles')
        .select('id,display_name,avatar_url,handle')
        .eq('id', row['user_id'])
        .maybeSingle()
        .timeout(const Duration(seconds: 15));
    if (client.auth.currentUser?.id != viewerId) {
      throw StateError('Public work account changed during load');
    }
    var likedByMe = false;
    if (viewerId != null) {
      final like = await (likeFuture ?? readLike(viewerId));
      if (likeError != null) {
        Error.throwWithStackTrace(likeError!, likeStack!);
      }
      if (client.auth.currentUser?.id != viewerId) {
        throw StateError('Public work account changed during load');
      }
      likedByMe = like != null;
    }
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
      likedByMe: likedByMe,
      likesCount: (row['likes_count'] as num?)?.toInt() ?? 0,
      commentCount: (row['comments_count'] as num?)?.toInt() ?? 0,
      viewsCount: (row['views_count'] as num?)?.toInt() ?? 0,
      publishedAt: DateTime.parse(row['published_at'] as String),
      authorDisplayName: profile?['display_name'] as String? ?? 'unknown',
      authorAvatarUrl: profile?['avatar_url'] as String?,
      authorHandle: profile?['handle'] as String?,
      publishRegion: row['publish_region'] as String?,
    );
  }
}
