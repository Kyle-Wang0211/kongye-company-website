import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/auth_scope.dart';
import '../../community/comments/comment_moderation_repository.dart';
import '../../config/endpoint_config.dart';
import 'notifications/community_comment_case_page.dart';
import 'notifications/community_comment_inbox_button.dart';
import 'notifications/community_comment_inbox_page.dart';

/// Re-evaluates route identity even while the page that opened it is covered.
class CommentModerationAccountGate extends StatefulWidget {
  const CommentModerationAccountGate({
    super.key,
    required this.builder,
    this.userIdReader,
  });
  final Widget Function(BuildContext, String?, String) builder;
  final String? Function()? userIdReader;
  @override
  State<CommentModerationAccountGate> createState() =>
      _CommentModerationAccountGateState();
}

class _CommentModerationAccountGateState
    extends State<CommentModerationAccountGate> {
  StreamSubscription<AuthState>? _auth;
  int _epoch = 0;
  @override
  void initState() {
    super.initState();
    try {
      _auth = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
        // Auth refresh may be delivered while an ancestor is building.
        scheduleMicrotask(() {
          if (mounted) setState(() => _epoch++);
        });
      });
    } catch (_) {
      // Offline widget tests can use AuthScope without the global SDK singleton.
    }
  }

  @override
  void dispose() {
    _auth?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuthScope>();
    final userId = widget.userIdReader != null
        ? widget.userIdReader!()
        : scope?.notifier?.signedInUser?.id.rawValue;
    final endpoint = EndpointConfigResolver.current;
    final identity =
        '$userId|${endpoint?.deployment.namespace}|${endpoint?.supabaseUrl}|$_epoch';
    return widget.builder(context, userId, identity);
  }
}

Future<void> openCommentModerationInbox(
  BuildContext context, {
  CommunityCommentModerationRepository? repository,
  String? Function()? userIdReader,
}) {
  final targetRepository =
      repository ?? SupabaseCommunityCommentModerationRepository();
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => CommentModerationAccountGate(
        userIdReader: userIdReader,
        builder: (_, userId, identity) => CommunityCommentInboxPage(
          repository: targetRepository,
          currentUserId: userId,
          identityKey: identity,
        ),
      ),
    ),
  );
}

Future<void> openCommentModerationCase(
  BuildContext context, {
  required String caseId,
  CommunityCommentModerationRepository? repository,
  String? Function()? userIdReader,
}) {
  final targetRepository =
      repository ?? SupabaseCommunityCommentModerationRepository();
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => CommentModerationAccountGate(
        userIdReader: userIdReader,
        builder: (_, userId, identity) => CommunityCommentCasePage(
          caseId: caseId,
          repository: targetRepository,
          currentUserId: userId,
          identityKey: identity,
        ),
      ),
    ),
  );
}

class CommentModerationInboxShortcut extends StatefulWidget {
  const CommentModerationInboxShortcut({
    super.key,
    this.repository,
    this.active = true,
  });
  final CommunityCommentModerationRepository? repository;
  final bool active;
  @override
  State<CommentModerationInboxShortcut> createState() =>
      _CommentModerationInboxShortcutState();
}

class _CommentModerationInboxShortcutState
    extends State<CommentModerationInboxShortcut> {
  late final _defaultRepository =
      SupabaseCommunityCommentModerationRepository();
  @override
  Widget build(BuildContext context) {
    final repository = widget.repository ?? _defaultRepository;
    return CommentModerationAccountGate(
      builder: (context, userId, identity) => CommunityCommentInboxButton(
        repository: repository,
        currentUserId: userId,
        identityKey: identity,
        active: widget.active,
        onPressed: () =>
            openCommentModerationInbox(context, repository: repository),
      ),
    );
  }
}
