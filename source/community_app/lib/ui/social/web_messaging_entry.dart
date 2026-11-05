import 'community_capabilities.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/current_user.dart';
import '../../community/web_messaging_repository.dart';
import '../../community/social_profile_repository.dart';
import '../../community/web_social_api.dart';
import '../../config/endpoint_config.dart';
import '../design_system.dart';
import 'web_conversation_page.dart';
import 'web_messages_page.dart';

@immutable
class WebMessagingPeer {
  const WebMessagingPeer({required this.id, required this.displayName});
  final String id, displayName;
}

/// Account-owned inbox or profile-originated direct conversation entry.
/// Enable after the matching regional R4 backend has passed live verification.
class WebMessagingEntry extends StatefulWidget {
  const WebMessagingEntry({
    super.key,
    required this.user,
    required this.ownerId,
    this.peerId,
    this.peerName,
    this.repository,
    this.backendReady = CommunityCapabilities.messaging,
  });
  final CurrentUser user;
  final String ownerId;
  final String? peerId, peerName;
  final WebMessagingRepository? repository;
  final bool backendReady;

  @override
  State<WebMessagingEntry> createState() => _WebMessagingEntryState();
}

class _WebMessagingEntryState extends State<WebMessagingEntry> {
  WebMessagingRepository? _repository;
  WebSocialApi? _ownedApi;
  Future<String>? _initialConversation;
  Widget? _initialPage;
  int _inboxRevision = 0;
  bool _opening = false;
  bool get _current => widget.user.signedInUser?.id.rawValue == widget.ownerId;

  @override
  void initState() {
    super.initState();
    widget.user.addListener(_accountChanged);
    _configure();
  }

  void _configure() {
    _repository = widget.repository;
    if (_repository == null && widget.backendReady && _current) {
      final client = Supabase.instance.client;
      final deployment = widget.user.deployment;
      final endpoint = EndpointConfigResolver.current;
      final origin = Uri.parse(endpoint?.supabaseUrl ?? deployment.supabaseUrl);
      _ownedApi = WebSocialApi(
        apiOrigin: origin,
        supabaseOrigin: origin,
        publishableKey: endpoint?.supabaseAnonKey ?? deployment.anonKey,
        region: deployment.region.name,
        authNamespace: deployment.namespace,
        messagingEnabled: true,
        accessToken: () =>
            _current && client.auth.currentUser?.id == widget.ownerId
            ? client.auth.currentSession?.accessToken
            : null,
        currentUserId: () => _current ? widget.ownerId : null,
      );
      _repository = WebMessagingRepository(
        api: _ownedApi!,
        ownerId: widget.ownerId,
        currentUserId: () =>
            _current && client.auth.currentUser?.id == widget.ownerId
            ? widget.ownerId
            : null,
        realtimeClient: client,
        loadPeerName: (peer) async {
          try {
            return (await SupabaseSocialProfileRepository(
              client: client,
            ).fetchProfile(peer)).displayName;
          } on StateError {
            return '名称暂不可用';
          }
        },
      );
    }
    if (widget.peerId != null && _repository?.available == true && _current) {
      _initialConversation = _repository!.openPeer(widget.peerId!);
    }
  }

  @override
  void didUpdateWidget(WebMessagingEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user != widget.user) {
      oldWidget.user.removeListener(_accountChanged);
      widget.user.addListener(_accountChanged);
    }
    if (oldWidget.ownerId != widget.ownerId ||
        oldWidget.peerId != widget.peerId ||
        oldWidget.repository != widget.repository ||
        oldWidget.backendReady != widget.backendReady ||
        oldWidget.user != widget.user) {
      _release(oldWidget.repository);
      _initialConversation = null;
      _initialPage = null;
      _configure();
    }
  }

  void _accountChanged() {
    if (mounted) setState(() {});
  }

  void _release(WebMessagingRepository? injected) {
    if (injected == null) _repository?.dispose();
    _ownedApi?.close();
    _ownedApi = null;
    _repository = null;
  }

  @override
  void dispose() {
    widget.user.removeListener(_accountChanged);
    _release(widget.repository);
    super.dispose();
  }

  Future<void> _open(WebConversationSummary conversation) async {
    if (!_current || _opening) return;
    setState(() => _opening = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => _conversation(
            conversation.id,
            conversation.displayName,
            conversation.peerId,
          ),
        ),
      );
    } finally {
      if (mounted && _current) {
        setState(() {
          _opening = false;
          _inboxRevision++;
        });
      }
    }
  }

  Widget _conversation(String id, String name, String peer) {
    final repository = _repository!;
    final owner = widget.ownerId;
    final user = widget.user;
    final changes = repository.watch(id);
    return AnimatedBuilder(
      animation: user,
      builder: (context, _) {
        if (user.signedInUser?.id.rawValue != owner) return _signedOut();
        return WebConversationPage(
          key: ValueKey('$owner:$id'),
          conversationId: '$owner:$id',
          peerName: name,
          loader: () => repository.history(id),
          send: (text) => repository.send(id, text),
          changes: changes,
          idempotentRetry: true,
          onMarkRead: (messageId) => repository.markRead(id, messageId),
          onWithdraw: repository.withdraw,
          onReport: repository.report,
          onBlockPeer: (blocked) => repository.block(peer, blocked),
        );
      },
    );
  }

  Widget _signedOut() => const Scaffold(
    body: Center(child: Text('会话已结束，请重新登录。', style: AetherTextStyles.body)),
  );

  @override
  Widget build(BuildContext context) {
    if (!_current) return _signedOut();
    final repository = _repository;
    if (widget.peerId != null && repository?.available == true) {
      return FutureBuilder<String>(
        future: _initialConversation,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(title: const Text('私信')),
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('无法开始对话，请稍后重试。'),
                    OutlinedButton(
                      onPressed: () => setState(() {
                        _initialConversation = repository!.openPeer(
                          widget.peerId!,
                        );
                        _initialPage = null;
                      }),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: AetherColors.primary),
              ),
            );
          }
          return _initialPage ??= _conversation(
            snapshot.data!,
            widget.peerName ?? '创作者',
            widget.peerId!,
          );
        },
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('私信')),
      body: WebMessagesPage(
        key: ValueKey('${widget.ownerId}:$_inboxRevision'),
        loadConversations: repository?.available == true
            ? repository!.inbox
            : null,
        onOpen: _open,
        isEnglish: Localizations.localeOf(context).languageCode != 'zh',
      ),
    );
  }
}
