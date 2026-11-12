import 'package:supabase_flutter/supabase_flutter.dart';

import 'community_service.dart';
import 'feed_models.dart';
import 'social_profile_models.dart';
import 'social_profile_repository.dart';

/// The existing server search owns relevance ordering. Clients preserve it and
/// hydrate works through the same public-feed rules as the community.
class CommunitySearchService {
  CommunitySearchService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;
  late final CommunityService workService = CommunityService(client: _client);
  late final SocialProfileRepository profiles = SupabaseSocialProfileRepository(
    client: _client,
  );

  Future<Map<String, dynamic>> _request(String action, String query) async {
    final response = await _client.rpc(
      'community_search',
      params: {'p_action': action, 'p_query': query.trim()},
    );
    if (response is! Map) {
      throw const FormatException('Search unavailable');
    }
    return Map<String, dynamic>.from(response);
  }

  Future<List<String>> suggest(String query) async {
    if (query.trim().isEmpty) return const [];
    final data = await _request('suggest', query);
    final suggestions = data['suggestions'];
    if (suggestions is! List) {
      throw const FormatException('Invalid suggestions');
    }
    return suggestions.map((item) => item as String).toList(growable: false);
  }

  Future<List<FeedWork>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    final data = await _request('search', query);
    final works = data['works'];
    if (works is! List) throw const FormatException('Invalid search results');
    final ids = works.map((item) => (item as Map)['id'] as String).toList();
    if (ids.isEmpty) return const [];
    final hydrated = await workService.fetchPublicFeed(
      workIds: ids,
      limit: ids.length,
    );
    final byId = {for (final work in hydrated) work.id: work};
    return [
      for (final id in ids)
        if (byId.containsKey(id)) byId[id]!,
    ];
  }

  Future<List<SocialProfile>> users(String query) async {
    if (query.trim().isEmpty) return const [];
    final data = await _request('users', query);
    final rows = data['users'];
    if (rows is! List) throw const FormatException('Invalid user results');
    return rows
        .map((row) {
          if (row is! Map ||
              row['id'] is! String ||
              row['display_name'] is! String ||
              (row['display_name'] as String).trim().isEmpty ||
              (row['avatar_url'] != null && row['avatar_url'] is! String) ||
              row['public_account_number'] is! String ||
              (row['public_account_number'] as String).trim().isEmpty ||
              row['follower_count'] is! int ||
              (row['follower_count'] as int) < 0) {
            throw const FormatException('Invalid public profile');
          }
          return SocialProfile.fromMap({
            'id': row['id'],
            'display_name': row['display_name'],
            'avatar_url': row['avatar_url'],
            'followers_count': row['follower_count'],
            'public_account_number': row['public_account_number'],
          });
        })
        .toList(growable: false);
  }
}
