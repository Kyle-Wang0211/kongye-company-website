import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../l10n/app_localizations.dart';

import '../../../community/comments/comment_repository.dart';
import '../../design_system.dart';

/// Timers never issue requests while covered, offstage, or in the background.
mixin ActiveModerationRefresh<T extends StatefulWidget> on State<T>
    implements WidgetsBindingObserver {
  Timer? _refreshTimer;
  bool _foreground = true;
  bool get moderationPageActive =>
      mounted &&
      _foreground &&
      TickerMode.valuesOf(context).enabled &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  void refreshModeration();

  void startModerationRefresh(Duration? interval) {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (interval != null && interval > Duration.zero) {
      _refreshTimer = Timer.periodic(interval, (_) {
        if (moderationPageActive) refreshModeration();
      });
    }
  }

  void stopModerationRefresh() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && moderationPageActive) refreshModeration();
  }
}

String moderationError(AppL10n l, Object error) => switch (error) {
  CommunityCommentException(code: 'identity_changed') =>
    l.moderationIdentityChanged,
  CommunityCommentException(code: 'auth_required') =>
    l.moderationSignInRequired,
  CommunityCommentException(code: 'timeout') ||
  TimeoutException() => l.moderationRequestTimeout,
  _ => l.moderationConnectionFailed,
};

bool moderationIdentityChanged(Object error) =>
    error is CommunityCommentException &&
    (error.code == 'identity_changed' || error.code == 'auth_required');

String moderationDate(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

class ModerationMessage extends StatelessWidget {
  const ModerationMessage({super.key, required this.message, this.retry});
  final String message;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AetherSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, color: AetherColors.textSecondary),
          const SizedBox(height: AetherSpacing.md),
          Text(
            message,
            style: AetherTextStyles.body,
            textAlign: TextAlign.center,
          ),
          if (retry != null)
            ShadButton.ghost(
              onPressed: retry,
              child: Text(AppL10n.of(context).authRetry),
            ),
        ],
      ),
    ),
  );
}
