import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class ProfileLikesRepository {
  Future<int> fetchReceivedLikes(String userId);
}

/// Counts received likes on the signed-in user's currently public works.
/// Uses the normal caller JWT and existing works RLS; a failed read remains
/// unavailable rather than being presented as a measured zero.
class SupabaseProfileLikesRepository implements ProfileLikesRepository {
  SupabaseProfileLikesRepository({
    required SupabaseClient client,
    String? Function()? viewerIdProvider,
  }) : _client = client,
       _viewerIdProvider =
           viewerIdProvider ?? (() => client.auth.currentUser?.id);

  final SupabaseClient _client;
  final String? Function() _viewerIdProvider;
  static const _pageSize = 500;

  void _requireOwner(String userId) {
    final viewerId = _viewerIdProvider();
    if (viewerId == null) {
      throw StateError('Received likes require a signed-in account.');
    }
    if (userId.isEmpty || viewerId != userId) {
      throw ArgumentError.value(userId, 'userId', 'must be the signed-in user');
    }
  }

  @override
  Future<int> fetchReceivedLikes(String userId) async {
    _requireOwner(userId);
    var total = 0;
    String? afterId;
    while (true) {
      if (_viewerIdProvider() != userId) {
        throw StateError('Account changed while loading received likes.');
      }
      var query = _client
          .from('works')
          .select('id,likes_count')
          .eq('user_id', userId)
          .eq('visibility', 'public')
          .eq('moderation_status', 'ok')
          .isFilter('deleted_at', null)
          .not('published_at', 'is', null);
      if (afterId != null) query = query.gt('id', afterId);
      final rows = await query.order('id', ascending: true).limit(_pageSize);
      if (_viewerIdProvider() != userId) {
        throw StateError('Account changed while loading received likes.');
      }
      for (final row in rows) {
        final id = row['id'];
        final likes = row['likes_count'];
        if (id is! String ||
            id.isEmpty ||
            (afterId != null && id.compareTo(afterId) <= 0) ||
            likes is! int ||
            likes < 0) {
          throw const FormatException('Invalid received-likes work row.');
        }
        afterId = id;
        total += likes;
      }
      if (rows.length < _pageSize) return total;
    }
  }
}
