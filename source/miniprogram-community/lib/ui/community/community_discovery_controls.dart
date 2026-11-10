import 'package:flutter/material.dart';

class CommunityDiscoveryHeader extends StatefulWidget {
  const CommunityDiscoveryHeader({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.controller,
    required this.onSearch,
    required this.onClear,
  });
  final String selected;
  final ValueChanged<String> onChanged, onSearch;
  final TextEditingController controller;
  final VoidCallback onClear;
  @override
  State<CommunityDiscoveryHeader> createState() =>
      _CommunityDiscoveryHeaderState();
}

class _CommunityDiscoveryHeaderState extends State<CommunityDiscoveryHeader> {
  bool _searchOpen = false;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 52,
        child: Row(
          children: [
            for (final entry in const {
              'all': '发现',
              'art': '艺术',
              'life': '生活',
              'scene': '场景',
            }.entries)
              Expanded(
                child: InkWell(
                  onTap: () => widget.onChanged(entry.key),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 7),
                      Text(
                        entry.value,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: widget.selected == entry.key
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: widget.selected == entry.key
                              ? Colors.black
                              : const Color(0xff888888),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Container(
                        width: 24,
                        height: 3,
                        decoration: BoxDecoration(
                          color: widget.selected == entry.key
                              ? Colors.black
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.search, size: 26),
              onPressed: () => setState(() => _searchOpen = !_searchOpen),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
      if (_searchOpen)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: TextField(
            autofocus: true,
            controller: widget.controller,
            textInputAction: TextInputAction.search,
            onSubmitted: widget.onSearch,
            decoration: InputDecoration(
              hintText: '搜索作品关键词',
              filled: true,
              fillColor: const Color(0xfff5f5f5),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '清空搜索',
                    onPressed: widget.onClear,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                  IconButton(
                    tooltip: '搜索',
                    onPressed: () => widget.onSearch(widget.controller.text),
                    icon: const Icon(Icons.search, size: 22),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}
