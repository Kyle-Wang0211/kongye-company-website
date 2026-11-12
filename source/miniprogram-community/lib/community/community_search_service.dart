import 'package:supabase_flutter/supabase_flutter.dart';

import 'community_service.dart';
import 'feed_models.dart';

/// RDS PostgreSQL owns candidate retrieval and its installed pg_trgm similarity
/// ordering. Clients preserve that order and hydrate through public-feed rules.
class CommunitySearchService {
  CommunitySearchService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

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
    final hydrated = await CommunityService(
      client: _client,
    ).fetchPublicFeed(workIds: ids, limit: ids.length);
    final byId = {for (final work in hydrated) work.id: work};
    return [
      for (final id in ids)
        if (byId.containsKey(id)) byId[id]!,
    ];
  }
}
