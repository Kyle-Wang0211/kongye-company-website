import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Repository-provided status. [stage] preserves the backend's stage identity.
class WebPublicationSummary {
  const WebPublicationSummary({
    required this.id,
    required this.title,
    required this.stage,
    this.message,
    this.updatedAt,
    this.canWithdraw = false,
    this.canRestore = false,
  });

  final String id;
  final String title;
  final String stage;
  final String? message;
  final DateTime? updatedAt;
  final bool canWithdraw;
  final bool canRestore;
}

class WebPublicationStatusPage extends StatefulWidget {
  const WebPublicationStatusPage({
    super.key,
    required this.loader,
    this.accountId,
    required this.onOpen,
    this.onRetry,
    this.onWithdraw,
    this.onRestore,
  });

  final String? accountId;
  final Future<List<WebPublicationSummary>> Function() loader;
  final ValueChanged<String> onOpen;
  final Future<void> Function(String id)? onRetry;
  final Future<void> Function(String id)? onWithdraw;
  final Future<void> Function(String id)? onRestore;

  @override
  State<WebPublicationStatusPage> createState() =>
      _WebPublicationStatusPageState();
}

class _WebPublicationStatusPageState extends State<WebPublicationStatusPage> {
  List<WebPublicationSummary>? _items;
  String? _selectedId;
  bool _loading = true;
  bool _loadFailed = false;
  String? _retryingId;
  String? _retryError;
  String? _retryErrorId;
  int _ownerGeneration = 0;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant WebPublicationStatusPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId ||
        (widget.accountId == null && oldWidget.loader != widget.loader)) {
      _ownerGeneration++;
      _retryingId = null;
      _retryError = null;
      _retryErrorId = null;
      _items = null;
      _selectedId = null;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final items = await widget.loader();
      if (!mounted || generation != _generation) return;
      setState(() {
        _retryError = null;
        _retryErrorId = null;
        _items = List.unmodifiable(items);
        _loading = false;
        if (!items.any((item) => item.id == _selectedId)) _selectedId = null;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _retry(WebPublicationSummary item) async {
    final owner = _ownerGeneration;
    final retry = widget.onRetry;
    if (retry == null || _retryingId != null) return;
    setState(() {
      _retryingId = item.id;
      _retryError = null;
    });
    try {
      await retry(item.id);
      if (mounted && owner == _ownerGeneration) await _load();
    } catch (_) {
      if (mounted && owner == _ownerGeneration) {
        setState(() {
          _retryErrorId = item.id;
          _retryError = '重试未确认，请刷新状态后再试。';
        });
      }
    } finally {
      if (mounted && owner == _ownerGeneration) {
        setState(() => _retryingId = null);
      }
    }
  }

  Future<void> _changeVisibility(
    WebPublicationSummary item, {
    required bool restore,
  }) async {
    final action = restore ? widget.onRestore : widget.onWithdraw;
    final allowed = restore ? item.canRestore : item.canWithdraw;
    if (action == null ||
        !allowed ||
        _retryingId != null ||
        _retryError != null) {
      return;
    }
    final owner = _ownerGeneration;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Theme(
        data: Theme.of(dialogContext).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.black,
            dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
          ),
        ),
        child: ShadDialog.alert(
          title: Text(restore ? '恢复发布？' : '撤回发布？'),
          actions: [
            ShadButton.ghost(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            ShadButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(restore ? '确认恢复' : '确认撤回'),
            ),
          ],
          closeIcon: const SizedBox.shrink(),
          child: Text(
            restore ? '恢复后，作品会按服务端审核结果重新提供。' : '撤回后，作品将停止公开提供。审核与争议材料按平台规则保留。',
          ),
        ),
      ),
    );
    if (!mounted ||
        owner != _ownerGeneration ||
        confirmed != true ||
        _retryingId != null) {
      return;
    }
    setState(() {
      _retryingId = item.id;
      _retryError = null;
    });
    try {
      await action(item.id);
      if (mounted && owner == _ownerGeneration) await _load();
    } catch (_) {
      if (mounted && owner == _ownerGeneration) {
        setState(() {
          _retryErrorId = item.id;
          _retryError = '操作结果未确认，请刷新状态后再试。';
        });
      }
    } finally {
      if (mounted && owner == _ownerGeneration) {
        setState(() => _retryingId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final theme = base.copyWith(
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: const Color(0xFF242424),
            dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
          ).copyWith(
            primary: const Color(0xFF242424),
            error: const Color(0xFFB3261E),
            surface: const Color(0xFFFAFAFA),
          ),
      scaffoldBackgroundColor: const Color(0xFFFAFAFA),
    );
    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('我的发布'),
          backgroundColor: const Color(0xFFFAFAFA),
          foregroundColor: const Color(0xFF242424),
          actions: [
            Tooltip(
              message: '刷新状态',
              child: ShadButton.ghost(
                onPressed: _loading || _retryingId != null ? null : _load,
                enabled:
                    (_loading || _retryingId != null ? null : _load) != null,
                width: 40,
                height: 40,
                padding: EdgeInsets.zero,
                child: const Icon(Icons.refresh),
              ),
            ),
          ],
        ),
        body: FocusTraversalGroup(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: _body(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading && (_items == null || _items!.isEmpty)) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: '正在获取发布状态'),
      );
    }
    if (_loadFailed && (_items == null || _items!.isEmpty)) {
      return _notice('暂时无法获取发布记录', '请检查连接后重试。', retry: true);
    }
    final items = _items ?? const <WebPublicationSummary>[];
    if (items.isEmpty) {
      return _notice('还没有发布记录', '提交作品后，可在这里查看处理与审核状态。');
    }
    final selected = items.where((item) => item.id == _selectedId).firstOrNull;
    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_loadFailed)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '刷新失败，以下为上次获取的状态。',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final list = ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) => _tile(items[index]),
              );
              if (constraints.maxWidth >= 768) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: list),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: selected == null
                          ? const Center(child: Text('选择一条记录查看详情'))
                          : SingleChildScrollView(child: _detail(selected)),
                    ),
                  ],
                );
              }
              if (selected == null) return list;
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 16, top: 8),
                      child: ShadButton.ghost(
                        onPressed: () => setState(() => _selectedId = null),
                        leading: const Icon(Icons.arrow_back),
                        child: const Text('返回发布列表'),
                      ),
                    ),
                    _detail(selected),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _notice(String title, String body, {bool retry = false}) =>
      SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_outlined, size: 40),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
            if (retry) ...[
              const SizedBox(height: 16),
              ShadButton.outline(onPressed: _load, child: const Text('重新加载')),
            ],
          ],
        ),
      );

  Widget _tile(WebPublicationSummary item) => Card(
    color: _selectedId == item.id
        ? const Color(0xFFEDEDED)
        : const Color(0xFFFFFFFF),
    clipBehavior: Clip.antiAlias,
    child: ListTile(
      selected: _selectedId == item.id,
      title: Text(item.title.isEmpty ? '未命名作品' : item.title),
      subtitle: Text(_status(item.stage).$1),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => setState(() {
        _selectedId = item.id;
      }),
    ),
  );

  Widget _detail(WebPublicationSummary item) {
    final (label, description) = _status(item.stage);
    final stage = item.stage.toLowerCase();
    final retryable = stage == 'failed' || _technicalFault(stage);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title.isEmpty ? '未命名作品' : item.title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(description),
          if (item.message?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 16),
            Text(item.message!),
          ],
          if (item.updatedAt != null) ...[
            const SizedBox(height: 16),
            Text('状态更新时间：${_time(item.updatedAt!)}'),
          ],
          if (_retryError != null && _retryErrorId == item.id) ...[
            const SizedBox(height: 16),
            Text(
              _retryError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          if (stage == 'published')
            ShadButton(
              onPressed: () => widget.onOpen(item.id),
              leading: const Icon(Icons.open_in_new),
              child: const Text('在社区查看'),
            ),
          if (retryable && widget.onRetry != null)
            ShadButton.outline(
              onPressed: _retryingId == null ? () => _retry(item) : null,
              enabled:
                  (_retryingId == null ? () => _retry(item) : null) != null,
              leading: const Icon(Icons.refresh),
              child: Text(_retryingId == item.id ? '正在提交重试…' : '重试处理'),
            ),
          if (retryable && widget.onRetry == null)
            const Text('暂时无法重试，请稍后刷新状态。'),
          if (item.canWithdraw && widget.onWithdraw != null)
            ShadButton.outline(
              key: ValueKey('withdraw-${item.id}'),
              onPressed: _retryingId == null && _retryError == null
                  ? () => _changeVisibility(item, restore: false)
                  : null,
              enabled:
                  (_retryingId == null && _retryError == null
                      ? () => _changeVisibility(item, restore: false)
                      : null) !=
                  null,
              child: Text(_retryingId == item.id ? '正在处理…' : '撤回发布'),
            ),
          if (item.canRestore && widget.onRestore != null)
            ShadButton.outline(
              key: ValueKey('restore-${item.id}'),
              onPressed: _retryingId == null && _retryError == null
                  ? () => _changeVisibility(item, restore: true)
                  : null,
              enabled:
                  (_retryingId == null && _retryError == null
                      ? () => _changeVisibility(item, restore: true)
                      : null) !=
                  null,
              child: Text(_retryingId == item.id ? '正在处理…' : '恢复发布'),
            ),
        ],
      ),
    );
  }

  String _time(DateTime time) {
    final value = time.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}

bool _technicalFault(String stage) =>
    stage.contains('missing_image') ||
    stage.contains('version') ||
    stage.contains('vendor');

(String, String) _status(String raw) {
  final stage = raw.toLowerCase();
  // Technical failures are never relabelled as a human moderation queue.
  if (_technicalFault(stage)) {
    return ('处理遇到问题', '系统处理暂时无法继续，可重试处理。');
  }
  return switch (stage) {
    'uploading' => ('正在上传', '作品文件正在上传。'),
    'queued' => ('排队中', '已提交，等待系统处理。'),
    'preparing' => ('准备中', '系统正在准备作品文件。'),
    'rendering' => ('正在处理', '系统正在生成作品预览。'),
    'moderating' => ('内容审核中', '系统正在进行内容审核。'),
    'awaiting_human' => ('等待人工审核', '作品正在等待人工内容审核。'),
    'published' => ('已发布', '作品已发布，可前往社区查看。'),
    'private' => ('非公开', '作品未向社区公开提供。'),
    'removed' => ('已移除', '作品已停止公开提供。'),
    'withdrawn' => ('已撤回', '作品已撤回，审核与争议材料按平台规则保留。'),
    'rejected' => ('未通过审核', '作品未通过内容审核，请查看说明。'),
    'failed' => ('处理失败', '系统处理未完成，可重试处理。'),
    'cancelled' => ('已取消', '此次发布已取消。'),
    _ => ('处理中', '状态正在更新，请稍后刷新查看。'),
  };
}
