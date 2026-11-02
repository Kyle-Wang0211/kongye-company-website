import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import '../../../community/comments/comment_moderation_repository.dart';
import '../../design_system.dart';
import 'moderation_ui_support.dart';

/// A server-backed unread indicator. Unknown state stays distinct from zero.
class CommunityCommentInboxButton extends StatefulWidget {
  const CommunityCommentInboxButton({
    super.key,
    required this.repository,
    required this.currentUserId,
    required this.onPressed,
    this.identityKey,
    this.refreshInterval = const Duration(seconds: 30),
    this.active = true,
  });
  final CommunityCommentModerationRepository repository;
  final String? currentUserId;
  final String? identityKey;
  final VoidCallback onPressed;
  final Duration? refreshInterval;
  final bool active;
  @override
  State<CommunityCommentInboxButton> createState() =>
      _CommunityCommentInboxButtonState();
}

class _CommunityCommentInboxButtonState
    extends State<CommunityCommentInboxButton>
    with
        WidgetsBindingObserver,
        ActiveModerationRefresh<CommunityCommentInboxButton> {
  int _generation = 0;
  bool _loading = false;
  bool? _unread;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    startModerationRefresh(widget.refreshInterval);
    _load();
  }

  @override
  void didUpdateWidget(covariant CommunityCommentInboxButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.currentUserId != widget.currentUserId ||
        oldWidget.identityKey != widget.identityKey) {
      _generation++;
      _loading = false;
      _unread = null;
      _failed = false;
      _load();
    } else if (!oldWidget.active && widget.active) {
      _load();
    }
    if (oldWidget.refreshInterval != widget.refreshInterval) {
      stopModerationRefresh();
      startModerationRefresh(widget.refreshInterval);
    }
  }

  @override
  void refreshModeration() => _load();

  Future<void> _load() async {
    if (!widget.active ||
        _loading ||
        !(widget.currentUserId?.isNotEmpty ?? false)) {
      return;
    }
    final generation = _generation;
    _loading = true;
    try {
      final notices = await widget.repository.fetchNotices();
      if (!mounted || generation != _generation) return;
      if (notices.any((notice) => notice.recipientId != widget.currentUserId)) {
        throw const FormatException('Notice ownership mismatch');
      }
      setState(() {
        _unread = notices.any((notice) => notice.readAt == null);
        _failed = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _unread = null;
        _failed = true;
      });
    } finally {
      if (generation == _generation) _loading = false;
    }
  }

  @override
  void dispose() {
    _generation++;
    stopModerationRefresh();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: AppL10n.of(context).moderationInbox,
    onPressed: widget.onPressed,
    icon: Semantics(
      label: _failed
          ? AppL10n.of(context).moderationInboxLoadFailedLabel
          : _unread == true
          ? AppL10n.of(context).moderationInboxUnreadLabel
          : _unread == false
          ? AppL10n.of(context).moderationInboxReadLabel
          : AppL10n.of(context).moderationInboxNotLoadedLabel,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(
            Icons.notifications_none_outlined,
            color: AetherColors.primary,
          ),
          if (_unread == true)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                key: const Key('comment-inbox-unread'),
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AetherColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          if (_failed)
            const Positioned(
              right: -3,
              top: -3,
              child: Icon(
                Icons.error_outline,
                size: 11,
                color: AetherColors.textSecondary,
              ),
            ),
        ],
      ),
    ),
  );
}
