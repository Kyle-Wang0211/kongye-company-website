import 'dart:async';
import 'package:flutter/material.dart';
import '../../community/account_work_library_repository.dart';
import '../design_system.dart';

/// Shared account library surface for native and community-web navigation.
class AccountWorkLibraryPage extends StatefulWidget {
  const AccountWorkLibraryPage({
    super.key,
    required this.accountId,
    required this.kind,
    required this.loadPage,
    required this.onOpen,
    this.thumbnailUrlFor,
  });
  final String accountId;
  final AccountWorkLibraryKind kind;
  final Future<AccountWorkLibraryPageResult> Function(AccountWorkLibraryCursor?)
  loadPage;
  final FutureOr<void> Function(String) onOpen;
  final String Function(String)? thumbnailUrlFor;
  @override
  State<AccountWorkLibraryPage> createState() => _AccountWorkLibraryPageState();
}

class _AccountWorkLibraryPageState extends State<AccountWorkLibraryPage> {
  final _scroll = ScrollController();
  final _items = <AccountWorkLibraryItem>[];
  final _seenCursors = <String>{};
  AccountWorkLibraryCursor? _next;
  bool _loading = false, _failed = false, _ended = false;
  int _generation = 0;
  Object? _opening;
  bool get _likes => widget.kind == AccountWorkLibraryKind.likes;
  String _text(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void didUpdateWidget(AccountWorkLibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId ||
        oldWidget.kind != widget.kind) {
      _reset();
    }
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 400 &&
        !_loading &&
        !_failed &&
        !_ended) {
      _load();
    }
  }

  void _reset() {
    _generation++;
    _items.clear();
    _seenCursors.clear();
    _next = null;
    _ended = false;
    _loading = false;
    _opening = null;
    _load();
  }

  Future<void> _load() async {
    if (_loading || _ended) return;
    final generation = _generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await widget.loadPage(_next);
      if (!mounted || generation != _generation) return;
      final cursor = page.next;
      if (cursor != null &&
          !_seenCursors.add('${cursor.activityAt}:${cursor.workId}')) {
        throw StateError('Repeated library cursor');
      }
      setState(() {
        final ids = _items.map((item) => item.workId).toSet();
        _items.addAll(page.items.where((item) => ids.add(item.workId)));
        _next = cursor;
        _ended = cursor == null;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _generation && _scroll.hasClients) {
          _onScroll();
        }
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
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
      if (mounted && identical(_opening, opening)) {
        _opening = null;
        if (generation == _generation) _reset();
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AetherColors.bgCanvas,
    appBar: AppBar(
      backgroundColor: AetherColors.bgCanvas,
      foregroundColor: AetherColors.primary,
      title: Text(
        _likes ? _text('我的喜欢', 'Liked works') : _text('观看历史', 'Watch history'),
      ),
      actions: [
        IconButton(
          tooltip: _text('刷新', 'Refresh'),
          onPressed: _loading ? null : _reset,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 600
            ? 2
            : constraints.maxWidth < 1000
            ? 3
            : 4;
        return CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: .85,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _card(_items[index]),
                  childCount: _items.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: _loading
                      ? const CircularProgressIndicator(
                          color: AetherColors.primary,
                        )
                      : _failed
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _text('暂时无法加载', 'Unable to load works'),
                              style: AetherTextStyles.body,
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _load,
                              child: Text(_text('重试', 'Retry')),
                            ),
                          ],
                        )
                      : _items.isEmpty
                      ? Text(
                          _likes
                              ? _text('还没有喜欢的作品', 'No liked works yet')
                              : _text('还没有观看历史', 'No watch history yet'),
                          style: AetherTextStyles.body,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _card(AccountWorkLibraryItem item) {
    final path = item.thumbnailStoragePath;
    final url = path == null || path.isEmpty
        ? null
        : widget.thumbnailUrlFor?.call(path);
    const placeholder = Center(
      child: Icon(Icons.view_in_ar_rounded, color: Colors.white54, size: 32),
    );
    return Card(
      key: ValueKey('library-${item.workId}'),
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AetherColors.bgCanvas,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AetherRadii.md),
        side: const BorderSide(color: AetherColors.border),
      ),
      child: InkWell(
        onTap: () => _open(item.workId),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ColoredBox(
                color: Colors.black,
                child: url == null
                    ? placeholder
                    : Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, error, stack) => placeholder,
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title.isEmpty
                        ? _text('未命名作品', 'Untitled work')
                        : item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AetherTextStyles.cardTitle,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.authorDisplayName.isEmpty
                        ? _text('创作者', 'Creator')
                        : item.authorDisplayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AetherTextStyles.bodySm,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
