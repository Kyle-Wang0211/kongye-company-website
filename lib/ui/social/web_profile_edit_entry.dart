import 'community_capabilities.dart';
import '../community/profile_presentation_stub.dart'
    if (dart.library.js_interop) '../community/profile_presentation_web.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/current_user.dart';
import '../../community/web_social_api.dart';
import '../../config/endpoint_config.dart';
import '../community/generated_account_avatar.dart';
import '../design_system.dart';
import 'web_profile_edit_page.dart';

/// Owner-bound entry for the deployed moderated basic-profile API.
class WebProfileEditEntry extends StatefulWidget {
  const WebProfileEditEntry({
    super.key,
    required this.user,
    required this.ownerId,
    this.api,
    this.backendReady = CommunityCapabilities.profiles,
  });
  final CurrentUser user;
  final String ownerId;
  final WebSocialApi? api;
  final bool backendReady;

  @override
  State<WebProfileEditEntry> createState() => _WebProfileEditEntryState();
}

class _WebProfileEditEntryState extends State<WebProfileEditEntry> {
  WebSocialApi? _api;
  WebSocialProfile? _profile;
  WebProfileSaveResult? _result;
  Timer? _poll;
  String? _editId;
  String? _error;
  bool _unknown = false;
  bool _loading = false;
  int _generation = 0;
  bool get _current => widget.user.signedInUser?.id.rawValue == widget.ownerId;

  @override
  void initState() {
    super.initState();
    widget.user.addListener(_accountChanged);
    _configure();
  }

  void _configure() {
    if (!widget.backendReady || !_current) return;
    _api = widget.api;
    if (_api == null) {
      final client = Supabase.instance.client;
      final deployment = widget.user.deployment;
      final endpoint = EndpointConfigResolver.current;
      final origin = Uri.parse(endpoint?.supabaseUrl ?? deployment.supabaseUrl);
      _api = WebSocialApi(
        apiOrigin: origin,
        supabaseOrigin: origin,
        publishableKey: endpoint?.supabaseAnonKey ?? deployment.anonKey,
        region: deployment.region.name,
        authNamespace: deployment.namespace,
        profilesEnabled: true,
        accessToken: () =>
            _current && client.auth.currentUser?.id == widget.ownerId
            ? client.auth.currentSession?.accessToken
            : null,
        currentUserId: () => _current ? widget.ownerId : null,
      );
    }
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(WebProfileEditEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user != widget.user) {
      oldWidget.user.removeListener(_accountChanged);
      widget.user.addListener(_accountChanged);
    }
    if (oldWidget.ownerId != widget.ownerId ||
        oldWidget.user != widget.user ||
        oldWidget.api != widget.api ||
        oldWidget.backendReady != widget.backendReady) {
      _release(oldWidget.api);
      _configure();
    }
  }

  void _release(WebSocialApi? injected) {
    _generation++;
    _poll?.cancel();
    if (injected == null) _api?.close();
    _api = null;
    _profile = null;
    _editId = null;
    _result = null;
    _error = null;
    _unknown = false;
    _loading = false;
  }

  void _accountChanged() {
    if (!_current) _release(widget.api);
    if (_current && _api == null) _configure();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.user.removeListener(_accountChanged);
    _release(widget.api);
    super.dispose();
  }

  bool _valid(int generation) =>
      mounted && _current && generation == _generation;

  WebProfileSaveResult _status(String? status) => switch (status) {
    'approved' => WebProfileSaveResult.approved,
    'pending' => WebProfileSaveResult.pendingReview,
    'retry' => WebProfileSaveResult.retrying,
    'review' => WebProfileSaveResult.review,
    'rejected' => WebProfileSaveResult.rejected,
    'superseded' => WebProfileSaveResult.superseded,
    _ => WebProfileSaveResult.unknown,
  };

  Future<void> _refresh() async {
    if (_loading || !_current || _api == null) return;
    final generation = _generation;
    _loading = true;
    try {
      final profile = await _api!.profile(widget.ownerId);
      if (!_valid(generation)) return;
      if (!profile.isOwner ||
          profile.id != widget.ownerId ||
          profile.version == null) {
        throw const WebSocialUnavailableException('owner_projection_required');
      }
      setState(() {
        _profile = profile;
        _error = null;
        // A known receipt is the only identity used to follow a submitted edit.
        // Unknown write outcomes never infer acceptance from an unrelated row.
        if (!_unknown) {
          if (_editId == null && profile.edits.isNotEmpty) {
            _editId = profile.edits.first['id'] as String?;
          }
          final rows = profile.edits.where((e) => e['id'] == _editId);
          if (rows.isNotEmpty) {
            _result = _status(rows.first['status'] as String?);
          }
        }
      });
      if (_result == WebProfileSaveResult.approved) {
        final refreshed = await widget.user.refreshProfile();
        if (refreshed && _valid(generation)) {
          notifyProfilePresentationChanged(widget.ownerId);
        }
      }
    } catch (_) {
      if (_valid(generation)) setState(() => _error = '资料或审核状态暂时无法读取，请稍后刷新。');
    } finally {
      if (_valid(generation)) {
        _loading = false;
        _poll?.cancel();
        if (_result == WebProfileSaveResult.pendingReview ||
            _result == WebProfileSaveResult.retrying) {
          _poll = Timer(
            const Duration(seconds: 5),
            () => unawaited(_refresh()),
          );
        }
      }
    }
  }

  Future<WebProfileSaveResult> _save(WebProfileDraft draft) async {
    if (!_current || _unknown || _api == null || _profile?.version == null) {
      throw const WebSocialUnavailableException('session_changed');
    }
    final generation = ++_generation;
    _loading = false;
    _poll?.cancel();
    try {
      final receipt = await _api!.editProfile(
        version: _profile!.version!,
        displayName: draft.displayName,
        bio: draft.bio,
      );
      if (!_valid(generation)) {
        throw const WebSocialUnavailableException('session_changed');
      }
      _editId = receipt.editId;
      _result = _status(receipt.status);
      // Read the published projection even for an immediately approved receipt.
      await _refresh();
      return _result!;
    } on WebSocialRequestException catch (error) {
      if (error.status == 409 && _valid(generation)) await _refresh();
      throw WebProfileSaveFailure(switch (error.status) {
        401 || 403 => '当前会话无法修改资料，请重新登录。',
        409 => '资料已在其他页面更新，已刷新公开资料。请核对草稿后重新提交。',
        422 => '昵称或简介格式不符合要求，请调整后提交。',
        429 => '修改过于频繁或昵称仍在修改间隔内，请稍后再试。',
        _ => '保存失败，请稍后重试。',
      });
    } on WebSocialUnavailableException {
      if (_valid(generation)) {
        setState(() {
          _unknown = true;
          _result = WebProfileSaveResult.unknown;
        });
        unawaited(_refresh());
      }
      return WebProfileSaveResult.unknown;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_current) return _message('会话已结束，请重新登录。');
    if (!widget.backendReady) return _message('个人资料编辑暂未开放。');
    final profile = _profile;
    if (profile == null) {
      return _message(_error, loading: _error == null);
    }
    return WebProfileEditPage(
      key: ValueKey(widget.ownerId),
      initialProfile: WebProfileDraft(
        displayName: profile.displayName,
        bio: profile.bio ?? '',
      ),
      avatarSeed: widget.ownerId,
      avatar: GeneratedAccountAvatar(userId: widget.ownerId, radius: 36),
      save: _save,
      observedResult: _result,
      submissionBlocked: _unknown,
      approvalFromProjection: true,
      statusError: _error,
      onRefresh: () => unawaited(_refresh()),
    );
  }

  Widget _message(String? message, {bool loading = false}) => Scaffold(
    appBar: AppBar(title: const Text('编辑个人资料')),
    body: Center(
      child: loading
          ? const CircularProgressIndicator(color: AetherColors.primary)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message ?? '暂时无法读取个人资料。', style: AetherTextStyles.body),
                if (_current && widget.backendReady)
                  TextButton(
                    onPressed: () => unawaited(_refresh()),
                    child: const Text('重新读取'),
                  ),
              ],
            ),
    ),
  );
}
