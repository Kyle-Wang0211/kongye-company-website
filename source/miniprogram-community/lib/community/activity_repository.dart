import 'package:supabase_flutter/supabase_flutter.dart';

/// A published snapshot. Drafts are never returned by the public RPC.
class CommunityActivity {
  const CommunityActivity({
    required this.id,
    required this.slug,
    required this.revision,
    required this.title,
    required this.coverUrl,
    required this.sortOrder,
    required this.summary,
  });
  final String id;
  final String slug;
  final int revision;
  final String title;
  final String coverUrl;
  final int sortOrder;
  final String summary;

  Uri get destination =>
      Uri.https('kongye.space', '/screen.html', {'activity': slug});
}

bool isTrustedActivityUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443) &&
      const {'kongye.space', 'api.kongye.space'}.contains(uri.host);
}

class ActivityRepository {
  ActivityRepository({SupabaseClient? client}) : _providedClient = client;
  final SupabaseClient? _providedClient;

  Future<List<CommunityActivity>> list() async {
    final client = _providedClient ?? Supabase.instance.client;
    return parse(await client.rpc('list_community_activities'));
  }

  static List<CommunityActivity> parse(Object? response) {
    if (response is! List) throw const FormatException('Invalid activity list');
    final ids = <String>{};
    final slugs = <String>{};
    final entries = <CommunityActivity>[];
    for (final row in response) {
      if (row is! Map || row['content'] is! Map) {
        throw const FormatException('Invalid activity snapshot');
      }
      final content = row['content'] as Map;
      final id = row['id'];
      final slug = row['slug'];
      final title = content['title'];
      final cover = content['cover_url'];
      final revision = row['revision'];
      final order = content['sort_order'];
      final detail = content['detail'];
      if (id is! String ||
          !RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
          ).hasMatch(id) ||
          slug is! String ||
          !RegExp(r'^[a-z0-9][a-z0-9-]{0,79}$').hasMatch(slug) ||
          title is! String ||
          title.trim().isEmpty ||
          title.length > 120 ||
          cover is! String ||
          !isTrustedActivityUrl(cover) ||
          revision is! int ||
          revision < 1 ||
          order is! int ||
          order < 0 ||
          order > 10000 ||
          row['published_at'] is! String ||
          DateTime.tryParse(row['published_at'] as String) == null ||
          !const {
            'article',
            'ceramic',
            'resort',
          }.contains(content['template_key']) ||
          detail is! Map ||
          !ids.add(id) ||
          !slugs.add(slug)) {
        throw const FormatException('Invalid activity snapshot');
      }
      final summary = detail['summary'];
      entries.add(
        CommunityActivity(
          id: id,
          slug: slug,
          revision: revision,
          title: title,
          coverUrl: cover,
          sortOrder: order,
          summary: summary is String ? summary : '',
        ),
      );
    }
    entries.sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      return order == 0 ? a.id.compareTo(b.id) : order;
    });
    return List.unmodifiable(entries);
  }
}
