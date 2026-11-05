import 'package:flutter/material.dart';

/// Only the signed-in owner's report fields belong in this view model.
/// The loader must enforce ownership before returning records.
@immutable
class WebReportSummary {
  const WebReportSummary({
    required this.id,
    required this.targetTitle,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.outcome,
  });

  final String id;
  final String targetTitle;
  final String reason;
  final String status;
  final DateTime createdAt;
  final String? outcome;
}

class WebReportHistoryPage extends StatefulWidget {
  const WebReportHistoryPage({
    super.key,
    required this.loader,
    this.accountId,
    this.onAppeal,
  });

  final String? accountId;
  final Future<List<WebReportSummary>> Function() loader;

  /// Provide only when the backend supports appeals for this owner.
  /// The backend remains responsible for eligibility and authorization.
  final Future<void> Function(String id, String explanation)? onAppeal;

  @override
  State<WebReportHistoryPage> createState() => _WebReportHistoryPageState();
}

class _WebReportHistoryPageState extends State<WebReportHistoryPage> {
  late Future<List<WebReportSummary>> _reports;
  int _ownerGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(WebReportHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId ||
        (widget.accountId == null && oldWidget.loader != widget.loader)) {
      _ownerGeneration++;
      _load();
    }
  }

  void _load() {
    _reports = Future.sync(widget.loader);
  }

  @override
  Widget build(BuildContext context) {
    final parent = Theme.of(context);
    final colors = ColorScheme.fromSeed(
      seedColor: Colors.black,
      brightness: parent.brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
    );
    return Theme(
      data: parent.copyWith(colorScheme: colors),
      child: Scaffold(
        appBar: AppBar(title: const Text('举报与申诉记录')),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: FutureBuilder<List<WebReportSummary>>(
              future: _reports,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return Center(
                    child: Semantics(
                      label: '正在加载举报记录',
                      child: const CircularProgressIndicator(),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return _message('暂时无法加载举报记录', '请稍后重试。', retry: true);
                }
                final reports = snapshot.data ?? const <WebReportSummary>[];
                if (reports.isEmpty) {
                  return _message('暂无举报记录', '你提交的举报及处理结果会显示在这里。');
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: reports.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text('仅展示你提交的记录。处理结果以平台通知为准。'),
                      );
                    }
                    final report = reports[index - 1];
                    return Card(
                      key: ValueKey(report.id),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        title: Text(report.targetTitle),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${_status(report.status)} · ${_date(report.createdAt)}',
                          ),
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(),
                          SelectableText('举报编号：${report.id}'),
                          const SizedBox(height: 12),
                          SelectableText('举报原因：${report.reason}'),
                          const SizedBox(height: 12),
                          SelectableText(
                            '处理结果：${report.outcome?.trim().isNotEmpty == true ? report.outcome : '暂无处理结果'}',
                          ),
                          const SizedBox(height: 12),
                          if (widget.onAppeal != null)
                            OutlinedButton.icon(
                              onPressed: () => _appeal(report),
                              icon: const Icon(Icons.edit_note),
                              label: const Text('提交申诉'),
                            )
                          else
                            const Text('当前暂不支持在线申诉。'),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _message(String title, String body, {bool retry = false}) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
            if (retry) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => setState(_load),
                child: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _appeal(WebReportSummary report) async {
    final generation = _ownerGeneration;
    final callback = widget.onAppeal;
    if (callback == null) return;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.black,
            brightness: Theme.of(context).brightness,
            dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
          ),
        ),
        child: _AppealDialog(
          onSubmit: (explanation) {
            if (!mounted || generation != _ownerGeneration) {
              throw StateError('Account changed');
            }
            return callback(report.id, explanation);
          },
        ),
      ),
    );
    if (!mounted || generation != _ownerGeneration || submitted != true) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('申诉已提交，处理结果请留意平台通知。')));
    setState(_load);
  }

  static String _date(DateTime value) {
    final local = value.toLocal();
    String pad(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)} ${pad(local.hour)}:${pad(local.minute)}';
  }

  static String _status(String value) => switch (value) {
    'pending' => '待处理',
    'reviewing' || 'in_review' => '处理中',
    'needs_info' => '待补充说明',
    'actioned' => '已采取措施',
    'dismissed' => '未采纳',
    'resolved' => '已处理',
    'rejected' => '未采纳',
    'closed' => '已结束',
    _ => '状态待确认',
  };
}

class _AppealDialog extends StatefulWidget {
  const _AppealDialog({required this.onSubmit});
  final Future<void> Function(String explanation) onSubmit;

  @override
  State<_AppealDialog> createState() => _AppealDialogState();
}

class _AppealDialogState extends State<_AppealDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final explanation = _controller.text.trim();
    if (explanation.isEmpty) {
      setState(() => _error = '请填写申诉说明');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(explanation);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '申诉未能提交，请重试。';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('提交申诉'),
      content: SizedBox(
        width: 440,
        child: TextField(
          controller: _controller,
          autofocus: true,
          enabled: !_busy,
          minLines: 3,
          maxLines: 6,
          maxLength: 2000,
          decoration: InputDecoration(
            labelText: '申诉说明',
            helperText: '请勿填写密码、证件号码等敏感信息。',
            helperMaxLines: 2,
            errorText: _error,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? '提交中…' : '提交'),
        ),
      ],
    ),
  );
}
