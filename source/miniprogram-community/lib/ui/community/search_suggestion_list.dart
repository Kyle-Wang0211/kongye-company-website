import 'package:flutter/material.dart';

/// Shared search suggestion presentation for the App and Flutter web hosts.
/// Keep the server's relevance order when presenting the first ten entries.
class SearchSuggestionList extends StatelessWidget {
  const SearchSuggestionList({
    super.key,
    required this.suggestions,
    required this.onSearch,
    required this.onFill,
    required this.fillTooltip,
  });

  static const maxResults = 10;

  final List<String> suggestions;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onFill;
  final String fillTooltip;

  @override
  Widget build(BuildContext context) {
    final visible = suggestions.take(maxResults).toList(growable: false);
    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final title = visible[index];
        return ListTile(
          contentPadding: const EdgeInsets.only(left: 24, right: 12),
          minVerticalPadding: 12,
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, color: Colors.black),
          ),
          trailing: IconButton(
            tooltip: fillTooltip,
            onPressed: () => onFill(title),
            icon: const Text(
              '↖\uFE0E',
              style: TextStyle(fontSize: 24, color: Colors.black),
            ),
          ),
          onTap: () => onSearch(title),
        );
      },
    );
  }
}
