import 'package:supabase_flutter/supabase_flutter.dart';

import 'community_service.dart';
import 'feed_models.dart';

/// The server owns Alibaba OpenSearch credentials and relevance. The client
/// preserves the returned order and never falls back to substring matching.
class CommunitySearchService {
  CommunitySearchService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  Future<Map<String, dynamic>> _request(String action, String query) async {
    final response = await _client.functions.invoke(
      'community-search',
      body: {'action': action, 'query': query.trim()},
    );
    if (response.status != 200 || response.data is! Map) {
      throw const FormatException('Search unavailable');
    }
    return Map<String, dynamic>.from(response.data as Map);
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
