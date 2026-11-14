import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../design_system.dart';

enum WebChatMessageStatus {
  sent,
  processing,
  retryable,
  pendingReview,
  rejected,
  withdrawn,
}

@immutable
class WebChatMessage {
  const WebChatMessage({
    required this.id,
    required this.text,
    required this.isMine,
    required this.createdAt,
    this.status = WebChatMessageStatus.sent,
  });

  final String id;
  final String text;
  final bool isMine;
  final DateTime createdAt;
  final WebChatMessageStatus status;
}

/// Text-only conversation. Callbacks must return authoritative backend results.
/// A failed send may have reached the server; this page never replays it itself.
/// Use a ValueKey containing the conversation ID when switching recipients.
class WebConversationPage extends StatefulWidget {
  const WebConversationPage({
    super.key,
    required this.peerName,
    this.conversationId,
    required this.loader,
    required this.send,
    this.changes,
    this.idempotentRetry = false,
    this.onMarkRead,
    this.onWithdraw,
    this.onReport,
    this.onBlockPeer,
  });

  /// Stable identity, including the signed-in owner when needed.
  final String? conversationId;
  final String peerName;
  final Future<List<WebChatMessage>> Function() loader;
  final Future<WebChatMessage> Function(String text) send;
  final Stream<void>? changes;
  final bool idempotentRetry;
  final Future<void> Function(String messageId)? onMarkRead;
  final Future<void> Function(String messageId)? onWithdraw;
  final Future<String> Function(String messageId, String reason)? onReport;
  final Future<void> Function(bool blocked)? onBlockPeer;

  @override
  State<WebConversationPage> createState() => _WebConversationPageState();
}

class _WebConversationPageState extends State<WebConversationPage>
    with WidgetsBindingObserver {
  final _draft = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  List<WebChatMessage> _messages = const [];
  bool _loading = true;
  bool _loadFailed = false;
  bool _sending = false;
  bool _confirmingRetry = false;
  bool _sendUnconfirmed = false;
  int _generation = 0;
  StreamSubscription<void>? _subscription;
  bool _liveUnavailable = false;
  bool _actionBusy = false;
  bool _refreshQueued = false;
  bool _markingRead = false;
  bool _readFailed = false;
  String? _readCursor;
  int _readEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_markVisibleRead);
    _load();
    _watch();
  }

  void _watch() {
    _subscription?.cancel();
    _subscription = widget.changes?.listen(
      (_) {
        if (mounted) {
          setState(() => _liveUnavailable = false);
          if (_loading || _sending) {
            _refreshQueued = true;
          } else {
            _load();
          }
        }
      },
      onError: (_) {
        if (mounted) setState(() => _liveUnavailable = true);
      },
    );
  }

  @override
  void didUpdateWidget(covariant WebConversationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        oldWidget.conversationId != widget.conversationId ||
        (widget.conversationId == null &&
            (oldWidget.peerName != widget.peerName ||
                oldWidget.loader != widget.loader ||
                oldWidget.send != widget.send));
    if (changed) {
      _generation++;
      _draft.clear();
      _messages = const [];
      _sending = false;
      _confirmingRetry = false;
      _sendUnconfirmed = false;
      _actionBusy = false;
      _liveUnavailable = false;
      _refreshQueued = false;
      _readEpoch++;
      _readCursor = null;
      _markingRead = false;
      _readFailed = false;
      _load();
    }
    if (changed || widget.changes != oldWidget.changes) _watch();
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _scroll.removeListener(_markVisibleRead);
    _subscription?.cancel();
    _draft.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_sending) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadFailed = false;
      _readFailed = false;
    });
    try {
      final messages = await widget.loader();
      if (!mounted || generation != _generation) return;
      setState(() {
        _messages = List.of(messages)
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _loading = false;
      });
      _scrollToLatest();
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    } finally {
      if (mounted && generation == _generation && _refreshQueued && !_sending) {
        _refreshQueued = false;
        unawaited(_load());
      }
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
        _markVisibleRead();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _markVisibleRead());
    }
  }

  Future<void> _markVisibleRead() async {
    final callback = widget.onMarkRead;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!mounted ||
        callback == null ||
        ModalRoute.of(context)?.isCurrent == false ||
        _loading ||
        _loadFailed ||
        _markingRead ||
        _readFailed ||
        !_scroll.hasClients ||
        _scroll.position.extentAfter > 1 ||
        lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return;
    }
    final received = _messages.where(
      (message) =>
          !message.isMine &&
          (message.status == WebChatMessageStatus.sent ||
              message.status == WebChatMessageStatus.withdrawn),
    );
    if (received.isEmpty || received.last.id == _readCursor) return;
    final id = received.last.id;
    final epoch = _readEpoch;
    _markingRead = true;
    try {
      await callback(id);
      if (!mounted || epoch != _readEpoch) return;
      _readCursor = id;
    } catch (_) {
      if (!mounted || epoch != _readEpoch) return;
      setState(() => _readFailed = true);
    } finally {
      if (mounted && epoch == _readEpoch) {
        _markingRead = false;
        // Reconcile a newer visible message that arrived during the write.
        if (!_readFailed) unawaited(_markVisibleRead());
      }
    }
  }

  Future<void> _send() async {
    if (_sending ||
        _confirmingRetry ||
        _loading ||
        _loadFailed ||
        _draft.text.trim().isEmpty ||
        _draft.text.trim().length > 600) {
      return;
    }
    final generation = _generation;
    if (_sendUnconfirmed && !widget.idempotentRetry) {
      setState(() => _confirmingRetry = true);
      final retry = await showDialog<bool>(
        context: context,
        builder: (context) => Theme(
          data: _theme(context),
          child: ShadDialog.alert(
            title: const Text('确认重试发送？'),
            description: const Text('上次发送结果未确认，消息可能已经送达。建议先刷新核对，重试可能产生重复消息。'),
            actions: [
              ShadButton.ghost(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              ShadButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认重试'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || generation != _generation) return;
      setState(() => _confirmingRetry = false);
      if (retry != true || _sending || _loading || _loadFailed) {
        return;
      }
    }
    final text = _draft.text.trim();
    setState(() => _sending = true);
    try {
      final confirmed = await widget.send(text);
      if (!mounted || generation != _generation) return;
      setState(() {
        _messages = [
          ..._messages.where(
            (message) =>
                message.id != confirmed.id &&
                !(message.id.startsWith('request:') && message.text == text),
          ),
          confirmed,
        ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _sending = false;
        _sendUnconfirmed = false;
        _draft.clear();
      });
      _focus.requestFocus();
      _scrollToLatest();
      if (_refreshQueued) {
        _refreshQueued = false;
        unawaited(_load());
      }
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _sending = false;
        _sendUnconfirmed = true;
      });
      _focus.requestFocus();
    }
  }

  Future<void> _messageAction(WebChatMessage message) async {
    final generation = _generation;
    if (message.isMine) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => ShadDialog.alert(
          title: const Text('撤回这条消息？'),
          actions: [
            ShadButton.ghost(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            ShadButton.ghost(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('撤回'),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted && generation == _generation) {
        await _runAction(() => widget.onWithdraw!(message.id), '消息已撤回');
      }
    } else {
      final reason = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('举报原因'),
          children: [
            for (final entry in const {
              'spam': '垃圾信息',
              'abuse': '辱骂骚扰',
              'sexual': '色情内容',
              'fraud': '诈骗',
              'other': '其他',
            }.entries)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, entry.key),
                child: Text(entry.value),
              ),
          ],
        ),
      );
      if (reason != null && mounted && generation == _generation) {
        await _runAction(() async {
          await widget.onReport!(message.id, reason);
        }, '举报已提交');
      }
    }
  }

  Future<void> _runAction(
    Future<void> Function() operation,
    String success,
  ) async {
    if (_actionBusy) return;
    final generation = _generation;
    setState(() => _actionBusy = true);
    try {
      await operation();
      if (!mounted || generation != _generation) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
      await _load();
    } catch (_) {
      if (!mounted || generation != _generation) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('操作未完成，请稍后重试。')));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  ThemeData _theme(BuildContext context) => Theme.of(context).copyWith(
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: AetherColors.primary,
          dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
        ).copyWith(
          primary: AetherColors.primary,
          error: AetherColors.danger,
          surface: AetherColors.bgCanvas,
          surfaceTint: Colors.transparent,
        ),
    scaffoldBackgroundColor: AetherColors.bg,
  );

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _theme(context),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AetherColors.bgCanvas,
          foregroundColor: AetherColors.textPrimary,
          title: Text(widget.peerName, overflow: TextOverflow.ellipsis),
          actions: [
            Tooltip(
              message: '刷新消息',
              child: ShadButton.ghost(
                onPressed: _loading || _sending ? null : _load,
                child: const Icon(Icons.refresh),
                enabled: !(_loading || _sending),
                width: 48,
                height: 48,
                padding: const EdgeInsets.all(12),
              ),
            ),
            if (widget.onBlockPeer != null)
              PopupMenuButton<bool>(
                tooltip: '对话设置',
                enabled: !_actionBusy,
                onSelected: (blocked) => _runAction(
                  () => widget.onBlockPeer!(blocked),
                  blocked ? '已拉黑此用户' : '已解除拉黑',
                ),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: true, child: Text('拉黑此用户')),
                  PopupMenuItem(value: false, child: Text('解除拉黑')),
                ],
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('私信 · 仅支持文字', style: AetherTextStyles.bodySm),
                    ),
                  ),
                  const Divider(height: 1),
                  if (_liveUnavailable)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        '实时连接暂不可用，请点击刷新查看新消息。',
                        style: AetherTextStyles.bodySm,
                      ),
                    ),
                  if (_readFailed)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        '已读状态暂未同步，请刷新重试。',
                        style: AetherTextStyles.bodySm,
                      ),
                    ),
                  Expanded(child: _history()),
                  if (_sendUnconfirmed)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Semantics(
                        liveRegion: true,
                        child: const Text(
                          '发送结果未确认，草稿已保留。请刷新核对或重试。',
                          style: TextStyle(color: AetherColors.danger),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Semantics(
                            label: '消息',
                            child: ShadInput(
                              key: const ValueKey('conversation-draft'),
                              controller: _draft,
                              focusNode: _focus,
                              readOnly: _sending,
                              minLines: 1,
                              maxLines: 5,
                              maxLength: 600,
                              textInputAction: TextInputAction.newline,
                              top: const Text('消息'),
                              placeholder: const Text('写下您的消息'),
                              decoration: ShadDecoration(
                                hasError: _draft.text.trim().length > 600,
                              ),
                              bottom: _draft.text.trim().length > 600
                                  ? const Text(
                                      '消息过长，请缩短后发送。',
                                      style: TextStyle(
                                        color: AetherColors.danger,
                                      ),
                                    )
                                  : null,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ShadButton(
                          onPressed:
                              _sending ||
                                  _confirmingRetry ||
                                  _loading ||
                                  _loadFailed ||
                                  _draft.text.trim().isEmpty ||
                                  _draft.text.trim().length > 600
                              ? null
                              : _send,
                          child: Text(
                            _sending
                                ? '发送中…'
                                : _sendUnconfirmed
                                ? '重试'
                                : '发送',
                          ),
                          enabled:
                              !(_sending ||
                                  _confirmingRetry ||
                                  _loading ||
                                  _loadFailed ||
                                  _draft.text.trim().isEmpty ||
                                  _draft.text.trim().length > 600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _history() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AetherColors.primary),
      );
    }
    if (_loadFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 32),
              const SizedBox(height: 12),
              const Text('消息暂时无法加载', style: AetherTextStyles.h3),
              const SizedBox(height: 8),
              const Text('请稍后重试，草稿仍保留。'),
              const SizedBox(height: 12),
              ShadButton.outline(onPressed: _load, child: const Text('重新加载')),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('还没有消息\n从一句问候开始吧', textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(20),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final local = message.createdAt.toLocal();
        final time =
            '${local.month}/${local.day} '
            '${local.hour.toString().padLeft(2, '0')}:'
            '${local.minute.toString().padLeft(2, '0')}';
        return Align(
          alignment: message.isMine
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: .86,
            child: Column(
              crossAxisAlignment: message.isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: message.isMine
                        ? AetherColors.primary
                        : AetherColors.bgElevated,
                    borderRadius: BorderRadius.circular(AetherRadii.sm),
                  ),
                  child: SelectableText(
                    message.text,
                    style: TextStyle(
                      color: message.isMine
                          ? Colors.white
                          : AetherColors.textPrimary,
                      height: 1.5,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    switch (message.status) {
                      WebChatMessageStatus.sent => time,
                      WebChatMessageStatus.processing => '$time · 机器审核处理中，尚未送达',
                      WebChatMessageStatus.retryable => '$time · 服务暂不可用，尚未送达',
                      WebChatMessageStatus.pendingReview => '$time · 待审核，仅自己可见',
                      WebChatMessageStatus.rejected => '$time · 未通过内容审核，未送达',
                      WebChatMessageStatus.withdrawn => '$time · 已撤回',
                    },
                    style: AetherTextStyles.caption.copyWith(
                      color: AetherColors.textSecondary,
                    ),
                  ),
                ),
                if (message.isMine &&
                    message.status == WebChatMessageStatus.retryable)
                  ShadButton.ghost(
                    onPressed:
                        _sending || _loading || _draft.text.trim().isNotEmpty
                        ? null
                        : () {
                            _draft.text = message.text;
                            _send();
                          },
                    child: const Text('重试发送'),
                    enabled:
                        !(_sending ||
                            _loading ||
                            _draft.text.trim().isNotEmpty),
                  ),
                if (message.status == WebChatMessageStatus.sent &&
                    (message.isMine
                        ? widget.onWithdraw != null
                        : widget.onReport != null))
                  ShadButton.ghost(
                    onPressed: _actionBusy
                        ? null
                        : () => _messageAction(message),
                    child: Text(message.isMine ? '撤回' : '举报'),
                    enabled: !_actionBusy,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
