import 'dart:async';

import 'package:flutter/material.dart';

import '../design_system.dart';

@immutable
class WebFavoriteItem {
  const WebFavoriteItem({
    required this.id,
    required this.title,
    required this.author,
    this.thumbnailUrl,
  });

  final String id;
  final String title;
  final String author;
  final String? thumbnailUrl;
}

/// Favorites supplied by the authenticated repository. Mutations are confirmed
/// by the repository before a card is removed from the page.
class WebFavoritesPage extends StatefulWidget {
  const WebFavoritesPage({
    super.key,
    required this.loadFavorites,
    this.accountId,
    required this.onOpen,
    required this.onSetFavorite,
  });

  final String? accountId;
  final Future<List<WebFavoriteItem>> Function() loadFavorites;
  final FutureOr<void> Function(String id) onOpen;
  final Future<void> Function(String id, bool isFavorite) onSetFavorite;

  @override
  State<WebFavoritesPage> createState() => _WebFavoritesPageState();
}

class _WebFavoritesPageState extends State<WebFavoritesPage> {
  List<WebFavoriteItem> _items = const [];
  final Map<String, Object> _pending = {};
  final Set<String> _errors = {};
  bool _loading = true;
  bool _failed = false;
  bool _list = false;
  int _generation = 0;
  Object? _opening;

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';
  String _text(String zh, String en) => _zh ? zh : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(WebFavoritesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId ||
        (widget.accountId == null &&
            oldWidget.loadFavorites != widget.loadFavorites)) {
      _items = const [];
      _opening = null;
      _pending.clear();
      _errors.clear();
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
      _errors.clear();
    });
    try {
      final items = await widget.loadFavorites();
      if (!mounted || generation != _generation) return;
      setState(() {
        // Preserve repository ordering while preventing duplicate mutation keys.
        final seen = <String>{};
        _items = items.where((item) => seen.add(item.id)).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _open(String id) async {
    if (_opening != null) return;
    final opening = Object();
    _opening = opening;
    final generation = _generation;
    try {
      await Future<void>.sync(() => widget.onOpen(id));
    } catch (_) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_text('作品暂不可访问', 'This work is unavailable'))),
        );
      }
    } finally {
      if (mounted && identical(_opening, opening)) _opening = null;
      if (mounted && generation == _generation) await _load();
    }
  }

  Future<void> _remove(WebFavoriteItem item) async {
    final generation = _generation;
    if (_pending.containsKey(item.id)) return;
    final removal = Object();
    _pending[item.id] = removal;
    setState(() => _errors.remove(item.id));
    try {
      await widget.onSetFavorite(item.id, false);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = _items.where((entry) => entry.id != item.id).toList();
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _errors.add(item.id);
      });
    } finally {
      if (mounted && identical(_pending[item.id], removal)) {
        setState(() => _pending.remove(item.id));
        if (generation != _generation) await _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep controls in the Aether grayscale palette even inside another theme.
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: AetherColors.primary,
              dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
            ).copyWith(
              primary: AetherColors.primary,
              onPrimary: Colors.white,
              secondary: AetherColors.primarySoft,
              error: AetherColors.danger,
              surface: AetherColors.bgCanvas,
            ),
      ),
      child: Scaffold(
        backgroundColor: AetherColors.bg,
        appBar: AppBar(
          backgroundColor: AetherColors.bgCanvas,
          foregroundColor: AetherColors.primary,
          title: Text(_text('我的收藏', 'Favorites')),
          actions: [
            IconButton(
              tooltip: _text('刷新收藏', 'Refresh favorites'),
              onPressed: _loading || _pending.isNotEmpty ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: AetherSpacing.sm),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 600;
              return SingleChildScrollView(
                padding: EdgeInsets.all(narrow ? 16 : 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 24,
                          runSpacing: 16,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _text('留住喜欢的世界', 'Worlds worth keeping'),
                                  style: AetherTextStyles.h1,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _text(
                                    '在这里重访您收藏的作品。',
                                    'Revisit the works you have saved.',
                                  ),
                                  style: AetherTextStyles.bodySm,
                                ),
                              ],
                            ),
                            if (!narrow && _items.isNotEmpty)
                              SegmentedButton<bool>(
                                segments: [
                                  ButtonSegment(
                                    value: false,
                                    icon: const Icon(Icons.grid_view_rounded),
                                    label: Text(_text('网格', 'Grid')),
                                  ),
                                  ButtonSegment(
                                    value: true,
                                    icon: const Icon(Icons.view_list_rounded),
                                    label: Text(_text('列表', 'List')),
                                  ),
                                ],
                                selected: {_list},
                                onSelectionChanged: (value) =>
                                    setState(() => _list = value.single),
                              ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        if (_loading)
                          _state(
                            icon: const CircularProgressIndicator(
                              color: AetherColors.primary,
                            ),
                            title: _text('正在加载收藏…', 'Loading favorites…'),
                          )
                        else if (_failed)
                          _state(
                            icon: const Icon(Icons.cloud_off_rounded, size: 40),
                            title: _text(
                              '暂时无法加载收藏',
                              'Favorites are unavailable',
                            ),
                            detail: _text(
                              '请稍后重试，您的收藏不会因此改变。',
                              'Please try again. Your saved works are unchanged.',
                            ),
                            action: FilledButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(_text('重试', 'Retry')),
                            ),
                          )
                        else if (_items.isEmpty)
                          _state(
                            icon: const Icon(
                              Icons.bookmark_border_rounded,
                              size: 44,
                            ),
                            title: _text('还没有收藏作品', 'No favorites yet'),
                            detail: _text(
                              '在社区收藏喜欢的作品，它们会出现在这里。',
                              'Save works from the community to find them here.',
                            ),
                          )
                        else ...[
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _text(
                                '${_items.length} 件收藏',
                                '${_items.length} saved works',
                              ),
                              style: AetherTextStyles.bodySm,
                            ),
                          ),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, space) {
                              final columns = narrow || _list
                                  ? 1
                                  : (space.maxWidth / 280).floor().clamp(1, 4);
                              final width =
                                  (space.maxWidth - (columns - 1) * 20) /
                                  columns;
                              return Wrap(
                                spacing: 20,
                                runSpacing: 20,
                                children: [
                                  for (final item in _items)
                                    SizedBox(
                                      width: width,
                                      child: _card(
                                        item,
                                        compact: _list && !narrow,
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _state({
    required Widget icon,
    required String title,
    String? detail,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      decoration: BoxDecoration(
        color: AetherColors.bgCanvas,
        border: Border.all(color: AetherColors.border),
        borderRadius: BorderRadius.circular(AetherRadii.md),
      ),
      child: Column(
        children: [
          ExcludeSemantics(child: icon),
          const SizedBox(height: 20),
          Text(title, style: AetherTextStyles.h2, textAlign: TextAlign.center),
          if (detail != null) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              style: AetherTextStyles.bodySm,
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...[const SizedBox(height: 24), action],
        ],
      ),
    );
  }

  Widget _card(WebFavoriteItem item, {required bool compact}) {
    final pending = _pending.containsKey(item.id);
    final title = item.title.trim().isEmpty
        ? _text('未命名作品', 'Untitled work')
        : item.title;
    final image = AspectRatio(
      aspectRatio: compact ? 1 : 4 / 3,
      child: ColoredBox(
        color: Colors.black,
        child: item.thumbnailUrl?.trim().isNotEmpty == true
            ? Image.network(
                item.thumbnailUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stack) => _thumbnailPlaceholder(),
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : _thumbnailPlaceholder(),
              )
            : _thumbnailPlaceholder(),
      ),
    );
    final info = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AetherTextStyles.cardTitle,
          ),
          const SizedBox(height: 8),
          Text(
            item.author.trim().isEmpty
                ? _text('作者未提供', 'Author unavailable')
                : item.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AetherTextStyles.bodySm,
          ),
        ],
      ),
    );
    return Card(
      key: ValueKey('favorite-${item.id}'),
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AetherColors.bgCanvas,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AetherColors.border),
        borderRadius: BorderRadius.circular(AetherRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: _text('打开作品：$title', 'Open work: $title'),
            button: true,
            child: InkWell(
              onTap: () => _open(item.id),
              child: compact
                  ? Row(
                      children: [
                        SizedBox(width: 120, child: image),
                        Expanded(child: info),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [image, info],
                    ),
            ),
          ),
          const Divider(height: 1, color: AetherColors.border),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: ValueKey('remove-favorite-${item.id}'),
                onPressed: pending ? null : () => _remove(item),
                icon: pending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AetherColors.textSecondary,
                        ),
                      )
                    : const Icon(Icons.bookmark_remove_outlined, size: 20),
                label: Text(
                  pending
                      ? _text('正在移除…', 'Removing…')
                      : _text('取消收藏', 'Remove favorite'),
                ),
              ),
            ),
          ),
          if (_errors.contains(item.id))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _text(
                    '移除失败，收藏已保留。请重试。',
                    'Could not remove. Your favorite is saved. Try again.',
                  ),
                  style: AetherTextStyles.bodySm.copyWith(
                    color: AetherColors.danger,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _thumbnailPlaceholder() => const Center(
    child: Icon(
      Icons.image_outlined,
      size: 32,
      color: AetherColors.textTertiary,
    ),
  );
}
