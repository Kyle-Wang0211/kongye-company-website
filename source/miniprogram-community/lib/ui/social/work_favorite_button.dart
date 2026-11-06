import 'community_capabilities.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pocketworld_flutter/auth/auth_scope.dart';
import 'package:pocketworld_flutter/community/web_social_api.dart';
import 'package:pocketworld_flutter/config/backend_deployment.dart';
import 'package:pocketworld_flutter/config/endpoint_config.dart';

/// Bind the existing Auth scope and API to a public work detail.
class WorkFavoriteEntry extends StatefulWidget {
  const WorkFavoriteEntry({super.key, required this.workId, this.onSignIn});
  final String workId;
  final VoidCallback? onSignIn;

  @override
  State<WorkFavoriteEntry> createState() => _WorkFavoriteEntryState();
}

class _WorkFavoriteEntryState extends State<WorkFavoriteEntry> {
  WebSocialApi? _api;
  String? _identity;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = context
        .dependOnInheritedWidgetOfExactType<AuthScope>()
        ?.notifier;
    final deployment = user?.deployment;
    final owner = user?.signedInUser?.id.rawValue;
    final identity =
        '${deployment?.namespace}:$owner:${user?.isPerformingAuthAction}';
    if (_identity == identity) return;
    _api?.close();
    _api = null;
    _identity = identity;
    if (user == null || owner == null || deployment == null) return;
    final endpoint = EndpointConfigResolver.current;
    final origin = Uri.parse(endpoint?.supabaseUrl ?? deployment.supabaseUrl);
    bool current() => user.signedInUser?.id.rawValue == owner;
    _api = WebSocialApi(
      apiOrigin: origin,
      supabaseOrigin: origin,
      publishableKey: endpoint?.supabaseAnonKey ?? deployment.anonKey,
      region: deployment.region.name,
      authNamespace: deployment.namespace,
      accessToken: () {
        if (!current()) return null;
        final auth = Supabase.instance.client.auth;
        return auth.currentUser?.id == owner
            ? auth.currentSession?.accessToken
            : null;
      },
      currentUserId: () => current() ? owner : null,
      favoritesEnabled: true,
    );
  }

  @override
  void dispose() {
    _api?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!CommunityCapabilities.favorites) {
      return const SizedBox.shrink();
    }
    final user = context
        .dependOnInheritedWidgetOfExactType<AuthScope>()
        ?.notifier;
    final deployment = user?.deployment;
    if (deployment == null ||
        deployment.region != BackendRegion.china ||
        deployment.namespace !=
            'china.cn-primary.https%3A%2F%2Fapi.kongye.space.rds20261104') {
      return const SizedBox.shrink();
    }
    final api = _api;
    return WorkFavoriteButton(
      key: ValueKey('$_identity:${widget.workId}'),
      accountId: user?.signedInUser?.id.rawValue,
      read: () => api!.favoriteState(widget.workId),
      write: (saved) => api!.setFavorite(widget.workId, saved),
      onSignIn: widget.onSignIn,
    );
  }
}

/// Desired-state writes retain their original target across an uncertain failure.
class WorkFavoriteButton extends StatefulWidget {
  const WorkFavoriteButton({
    super.key,
    required this.accountId,
    required this.read,
    required this.write,
    this.onSignIn,
  });
  final String? accountId;
  final Future<bool> Function() read;
  final Future<bool> Function(bool saved) write;
  final VoidCallback? onSignIn;

  @override
  State<WorkFavoriteButton> createState() => _WorkFavoriteButtonState();
}

class _WorkFavoriteButtonState extends State<WorkFavoriteButton> {
  bool? _saved;
  bool? _desired;
  bool _busy = false;
  bool _failed = false;
  bool _authenticationRequired = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(WorkFavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId) {
      _generation++;
      _saved = null;
      _desired = null;
      _busy = false;
      _authenticationRequired = false;
      _read();
    }
  }

  bool get _needsSignIn => widget.accountId == null || _authenticationRequired;

  Future<void> _read() async {
    if (widget.accountId == null) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final saved = await widget.read();
      if (!mounted || generation != _generation) return;
      setState(() => _saved = saved);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _authenticationRequired =
            (error is WebSocialRequestException && error.status == 401) ||
            (error is WebSocialUnavailableException &&
                error.code == 'authentication_required');
      });
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _press() async {
    if (_needsSignIn) {
      widget.onSignIn?.call();
      return;
    }
    if (_busy) return;
    if (_saved == null) {
      await _read();
      return;
    }
    final desired = _desired ?? !_saved!;
    final generation = _generation;
    setState(() {
      _busy = true;
      _failed = false;
      _desired = desired;
    });
    try {
      final confirmed = await widget.write(desired);
      if (confirmed != desired) {
        throw const WebSocialUnavailableException('invalid_response');
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _saved = confirmed;
        _desired = null;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _authenticationRequired =
            (error is WebSocialRequestException && error.status == 401) ||
            (error is WebSocialUnavailableException &&
                error.code == 'authentication_required');
      });
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String label;
    if (_needsSignIn) {
      label = zh ? '登录后收藏' : 'Sign in to save';
    } else if (_busy) {
      label = zh ? '正在确认收藏' : 'Checking favorite';
    } else if (_failed) {
      label = zh ? '重试收藏操作' : 'Retry favorite';
    } else {
      label = _saved == true
          ? (zh ? '取消收藏' : 'Remove favorite')
          : (zh ? '收藏作品' : 'Save favorite');
    }
    return Semantics(
      toggled: _saved == true,
      child: IconButton(
        key: const ValueKey('work-detail-favorite'),
        tooltip: label,
        color: Colors.white70,
        onPressed: _busy ? null : _press,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(_saved == true ? Icons.bookmark : Icons.bookmark_border),
      ),
    );
  }
}
