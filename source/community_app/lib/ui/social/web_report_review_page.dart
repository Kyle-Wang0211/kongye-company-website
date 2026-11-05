import 'package:flutter/material.dart';

class WebReportReviewItem {
  const WebReportReviewItem({
    required this.id,
    required this.reason,
    required this.status,
    required this.targetId,
    this.detail = '',
    this.claimedBy,
    this.sourceWorkId,
  });
  final int id;
  final String reason, status, targetId, detail;
  final String? claimedBy;
  final String? sourceWorkId;
}

class WebReportReviewQueue {
  const WebReportReviewQueue({
    required this.userId,
    required this.role,
    required this.items,
  });
  final String userId, role;
  final List<WebReportReviewItem> items;
}

/// The repository enforces reviewer authorization and ownership on every action.
class WebReportReviewPage extends StatefulWidget {
  const WebReportReviewPage({
    super.key,
    required this.accountId,
    required this.loader,
    required this.onClaim,
    required this.onTransition,
    this.onOpenWork,
  });
  final String accountId;
  final ValueChanged<String>? onOpenWork;
  final Future<WebReportReviewQueue> Function() loader;
  final Future<void> Function(int reportId) onClaim;
  final Future<void> Function(int reportId, String status, String feedback)
  onTransition;
  @override
  State<WebReportReviewPage> createState() => _WebReportReviewPageState();
}

class _WebReportReviewPageState extends State<WebReportReviewPage> {
  late Future<WebReportReviewQueue> _request;
  int _generation = 0;
  int? _busy;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(WebReportReviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId) {
      _generation++;
      _busy = null;
      _error = null;
      _load();
    }
  }

  void _load() {
    _request = Future.sync(widget.loader);
  }

  Future<void> _act(WebReportReviewItem item, String? status) async {
    if (_busy != null) return;
    final generation = _generation;
    String feedback = '';
    if (status != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认处理举报'),
          content: TextField(
            onChanged: (value) => feedback = value.trim(),
            maxLength: 2000,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: '给举报人的处理说明'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认提交'),
            ),
          ],
        ),
      );
      if (!mounted || generation != _generation || confirmed != true) return;
      if (feedback.isEmpty) {
        setState(() => _error = '请填写处理说明后提交。');
        return;
      }
    }
    if (!mounted || generation != _generation || _busy != null) return;
    setState(() {
      _busy = item.id;
      _error = null;
    });
    try {
      if (status == null) {
        await widget.onClaim(item.id);
      } else {
        await widget.onTransition(item.id, status, feedback);
      }
      if (mounted && generation == _generation) setState(_load);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '操作结果未确认，请刷新核对。');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.black,
        dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
      ),
    ),
    child: Scaffold(
      appBar: AppBar(
        title: const Text('人工举报处理'),
        actions: [
          IconButton(
            tooltip: '刷新队列',
            onPressed: _busy == null ? () => setState(_load) : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<WebReportReviewQueue>(
        future: _request,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('无法访问举报队列，请确认处理权限。'),
                  TextButton(
                    onPressed: () => setState(_load),
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }
          final queue = snapshot.data!;
          if (queue.userId != widget.accountId ||
              !['reviewer', 'lead'].contains(queue.role)) {
            return const Center(child: Text('当前账号没有处理权限。'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              if (queue.items.isEmpty) const Text('暂无待处理举报'),
              for (final item in queue.items)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('举报 ${item.id} · ${item.status}'),
                        Text(item.reason),
                        if (item.detail.isNotEmpty) SelectableText(item.detail),
                        SelectableText('对象 ${item.targetId}'),
                        if (item.sourceWorkId != null &&
                            widget.onOpenWork != null)
                          TextButton(
                            onPressed: () =>
                                widget.onOpenWork!(item.sourceWorkId!),
                            child: const Text('查看关联作品'),
                          ),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            if (item.claimedBy == null &&
                                ['pending', 'needs_info'].contains(item.status))
                              OutlinedButton(
                                onPressed: _busy == null
                                    ? () => _act(item, null)
                                    : null,
                                child: const Text('领取处理'),
                              ),
                            if (item.claimedBy == queue.userId) ...[
                              OutlinedButton(
                                onPressed: _busy == null
                                    ? () => _act(item, 'needs_info')
                                    : null,
                                child: const Text('要求补充说明'),
                              ),
                              OutlinedButton(
                                onPressed: _busy == null
                                    ? () => _act(item, 'dismissed')
                                    : null,
                                child: const Text('不予采纳'),
                              ),
                              if (queue.role == 'lead')
                                FilledButton(
                                  onPressed: _busy == null
                                      ? () => _act(item, 'actioned')
                                      : null,
                                  child: const Text('确认采取措施'),
                                ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
