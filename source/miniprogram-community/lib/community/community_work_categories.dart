import 'dart:convert';
import 'package:http/http.dart' as http;

/// Uses the same published name-and-cover assignments as the website.
class CommunityWorkCategories {
  static Future<Map<String, String>>? _catalog;
  static Future<List<String>> ids(String category) async {
    final catalog = await (_catalog ??= _load());
    return [
      for (final entry in catalog.entries)
        if (entry.value == category) entry.key,
    ];
  }

  static Future<Map<String, String>> _load() async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'https://kongye.space/community-work-categories.json?v=discovery-20261110-v1',
            ),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw StateError('Category catalogue unavailable');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final assignments = Map<String, String>.from(data['assignments'] as Map);
      if (assignments.entries.any(
        (entry) =>
            !RegExp(
              r'^[0-9a-f-]{36}$',
              caseSensitive: false,
            ).hasMatch(entry.key) ||
            !const {'art', 'life', 'scene'}.contains(entry.value),
      )) {
        throw const FormatException('Invalid published categories');
      }
      return assignments;
    } catch (_) {
      _catalog = null;
      rethrow;
    }
  }
}
