import 'package:flutter/material.dart';

import '../design_system.dart';

/// A conversation returned by the signed-in user's messaging repository.
@immutable
class WebConversationSummary {
  const WebConversationSummary({
    required this.id,
    required this.peerId,
    required this.displayName,
    required this.preview,
    required this.updatedAt,
    this.unreadCount = 0,
  });

  final String id;
  final String peerId;
  final String displayName;
  final String preview;
  final DateTime updatedAt;
  final int unreadCount;
}

/// Inbox only: opening a conversation is owned by the containing navigator.
/// A null loader means messaging is unavailable, rather than an empty inbox.
class WebMessagesPage extends StatefulWidget {
  const WebMessagesPage({
    super.key,
    required this.loadConversations,
    required this.onOpen,
    this.isEnglish = false,
  });

  final Future<List<WebConversationSummary>> Function()? loadConversations;
  final ValueChanged<WebConversationSummary> onOpen;
  final bool isEnglish;

  @override
  State<WebMessagesPage> createState() => _WebMessagesPageState();
}

class _WebMessagesPageState extends State<WebMessagesPage> {
  Future<List<WebConversationSummary>>? _request;

  String _text(String zh, String en) => widget.isEnglish ? en : zh;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(WebMessagesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loadConversations != oldWidget.loadConversations) _load();
  }

  void _load() {
    final loader = widget.loadConversations;
    // Future.sync also turns synchronous repository failures into retry UI.
    _request = loader == null
        ? null
        : Future<List<WebConversationSummary>>.sync(loader);
  }

  void _reload() => setState(_load);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AetherColors.bg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AetherSpacing.xl),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: FutureBuilder<List<WebConversationSummary>>(
              future: _request,
              builder: (context, snapshot) {
                final loading =
                    _request != null &&
                    snapshot.connectionState != ConnectionState.done;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _text('私信', 'Messages'),
                            style: AetherTextStyles.displayLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: _text('刷新私信', 'Refresh messages'),
                          onPressed: _request == null || loading
                              ? null
                              : _reload,
                          color: AetherColors.primary,
                          disabledColor: AetherColors.textTertiary,
                          style: IconButton.styleFrom(
                            hoverColor: AetherColors.bgElevated,
                            focusColor: AetherColors.bgElevated,
                            highlightColor: AetherColors.border,
                          ),
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: AetherSpacing.sm),
                    Text(
                      _text('与创作者保持联系。', 'Stay in touch with creators.'),
                      style: AetherTextStyles.bodySm,
                    ),
                    const SizedBox(height: AetherSpacing.xxl),
                    if (_request == null)
                      _status(
                        Icons.chat_bubble_outline_rounded,
                        _text('私信暂不可用', 'Messaging unavailable'),
                        _text(
                          '私信服务尚未连接，请稍后再试。',
                          'Messaging is not connected yet. Please try later.',
                        ),
                      )
                    else if (loading)
                      Padding(
                        padding: const EdgeInsets.all(AetherSpacing.huge),
                        child: Column(
                          children: [
                            const CircularProgressIndicator(
                              color: AetherColors.primary,
                              strokeWidth: 2,
                            ),
                            const SizedBox(height: AetherSpacing.lg),
                            Text(
                              _text('正在加载私信…', 'Loading messages…'),
                              style: AetherTextStyles.bodySm,
                            ),
                          ],
                        ),
                      )
                    else if (snapshot.hasError)
                      _status(
                        Icons.cloud_off_rounded,
                        _text('无法加载私信', 'Could not load messages'),
                        _text(
                          '请检查网络连接后重试。',
                          'Check your connection and try again.',
                        ),
                        retry: true,
                      )
                    else if (snapshot.data?.isNotEmpty != true)
                      _status(
                        Icons.chat_bubble_outline_rounded,
                        _text('暂无私信', 'No messages yet'),
                        _text(
                          '收到的对话会显示在这里。',
                          'Your conversations will appear here.',
                        ),
                      )
                    else
                      ...snapshot.data!.map((row) => _conversation(row)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _status(
    IconData icon,
    String title,
    String detail, {
    bool retry = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AetherSpacing.huge,
        horizontal: AetherSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: AetherColors.bgCanvas,
        border: Border.all(color: AetherColors.border),
        borderRadius: BorderRadius.circular(AetherRadii.md),
      ),
      child: Column(
        children: [
          Icon(icon, color: AetherColors.textSecondary, size: 32),
          const SizedBox(height: AetherSpacing.lg),
          Text(title, textAlign: TextAlign.center, style: AetherTextStyles.h3),
          const SizedBox(height: AetherSpacing.sm),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: AetherTextStyles.bodySm,
          ),
          if (retry) ...[
            const SizedBox(height: AetherSpacing.lg),
            OutlinedButton.icon(
              onPressed: _reload,
              style: OutlinedButton.styleFrom(
                foregroundColor: AetherColors.primary,
                overlayColor: AetherColors.border,
                side: const BorderSide(color: AetherColors.borderStrong),
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(_text('重试', 'Retry')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _conversation(WebConversationSummary row) {
    final name = row.displayName.trim().isEmpty
        ? _text('用户', 'User')
        : row.displayName;
    final unread = row.unreadCount > 0;
    final local = row.updatedAt.toLocal();
    final date =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
    final unreadLabel = _text(
      '${row.unreadCount} 条未读',
      '${row.unreadCount} unread messages',
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AetherSpacing.md),
      child: Material(
        color: AetherColors.bgCanvas,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AetherColors.border),
          borderRadius: BorderRadius.circular(AetherRadii.sm),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('conversation-${row.id}'),
          onTap: () => widget.onOpen(row),
          focusColor: AetherColors.bgElevated,
          hoverColor: AetherColors.bgElevated,
          splashColor: AetherColors.border,
          highlightColor: AetherColors.bgElevated,
          child: Padding(
            padding: const EdgeInsets.all(AetherSpacing.lg),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AetherColors.bgElevated,
                  foregroundColor: AetherColors.textSecondary,
                  child: Icon(Icons.person_outline_rounded),
                ),
                const SizedBox(width: AetherSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AetherTextStyles.h3.copyWith(
                          fontWeight: unread
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: AetherSpacing.xs),
                      Text(
                        row.preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AetherTextStyles.bodySm,
                      ),
                      const SizedBox(height: AetherSpacing.sm),
                      Wrap(
                        spacing: AetherSpacing.sm,
                        runSpacing: AetherSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            date,
                            style: AetherTextStyles.caption.copyWith(
                              color: AetherColors.textSecondary,
                            ),
                          ),
                          if (unread)
                            Semantics(
                              label: unreadLabel,
                              child: ExcludeSemantics(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AetherColors.primary,
                                    borderRadius: BorderRadius.circular(
                                      AetherRadii.pill,
                                    ),
                                  ),
                                  child: Text(
                                    row.unreadCount > 99
                                        ? '99+'
                                        : '${row.unreadCount}',
                                    style: AetherTextStyles.pill,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AetherSpacing.sm),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AetherColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
