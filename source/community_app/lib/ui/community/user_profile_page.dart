import 'generated_account_avatar.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../community/community_service.dart';
import '../../community/feed_models.dart';
import '../../community/social_profile_models.dart';
import '../../community/social_profile_repository.dart';
import '../../l10n/app_localizations.dart';
import '../design_system.dart';
import 'profile_work_grid.dart';
import 'user_report_page.dart';

typedef ProfileWorksLoader = Future<List<FeedWork>> Function(String userId);

enum _ProfileAction { report, block }

class UserProfilePage extends StatefulWidget {
  final String userId;
  final FeedWork? seedWork;
  final SocialProfileRepository? repository;
  final CommunityService? communityService;
  final ProfileWorksLoader? worksLoader;
  final VoidCallback? onReportRequested;
  final Future<void> Function()? onSignIn;
  final VoidCallback? onExit;
  final ValueChanged<FeedWork>? onWorkTap;
  final VoidCallback? onOpenFavorites;
  final VoidCallback? onOpenMessages;
  final VoidCallback? onEditNickname;
  final VoidCallback? onOpenLikes;
  final VoidCallback? onOpenHistory;
  final Future<int> Function(String userId)? receivedLikesLoader;
  final Map<String, VoidCallback> accountActions;
  final ValueChanged<SocialProfile>? onMessage;

  const UserProfilePage({
    super.key,
    required this.userId,
    this.seedWork,
    this.repository,
    this.communityService,
    this.worksLoader,
    this.onReportRequested,
    this.onSignIn,
    this.onExit,
    this.onWorkTap,
    this.onOpenFavorites,
    this.onOpenMessages,
    this.onEditNickname,
    this.onOpenLikes,
    this.onOpenHistory,
    this.receivedLikesLoader,
    this.accountActions = const {},
    this.onMessage,
  });

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  late final SocialProfileRepository _repository;
  CommunityService? _communityService;
  late final ProfileWorksLoader _worksLoader;

  SocialProfile? _profile;
  List<FeedWork> _works = const [];
  Object? _loadError;
  bool _relationshipInFlight = false;
  int? _receivedLikes;
  int _likesRequest = 0;

  bool get _isMine => _repository.currentUserId == widget.userId;

  @override
  void initState() {
    super.initState();
    final needsClient = widget.repository == null || widget.worksLoader == null;
    final client = needsClient ? Supabase.instance.client : null;
    _repository =
        widget.repository ?? SupabaseSocialProfileRepository(client: client!);
    _communityService =
        widget.communityService ??
        (widget.worksLoader == null ? CommunityService(client: client) : null);
    _worksLoader =
        widget.worksLoader ??
        (userId) => _communityService!.fetchPublicFeed(
          authorUserId: userId,
          limit: 100,
        );
    _load();
  }

  Future<void> _loadReceivedLikes() async {
    final request = ++_likesRequest;
    final loader = widget.receivedLikesLoader;
    if (!_isMine || loader == null) return;
    int? count;
    try {
      final value = await loader(widget.userId);
      if (value >= 0) count = value;
    } catch (_) {
      // A failed count must remain unknown, never look like a real zero.
    }
    if (mounted && request == _likesRequest && _isMine) {
      setState(() => _receivedLikes = count);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loadError = null;
      _receivedLikes = null;
    });
    _loadReceivedLikes();
    try {
      final results = await Future.wait<Object>([
        _repository.fetchProfile(widget.userId),
        _worksLoader(widget.userId),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as SocialProfile;
        _works = results[1] as List<FeedWork>;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  Future<bool> _requireSignIn() async {
    if (_repository.currentUserId != null) return true;
    await widget.onSignIn?.call();
    if (!mounted || _repository.currentUserId == null) return false;
    await _load();
    return mounted;
  }

  Future<void> _messageProfile() async {
    if (!await _requireSignIn()) return;
    final profile = _profile;
    if (profile != null && !_isMine) widget.onMessage?.call(profile);
  }

  Future<void> _toggleFollow() async {
    if (!await _requireSignIn()) return;
    final profile = _profile;
    if (profile == null || _relationshipInFlight) return;
    setState(() => _relationshipInFlight = true);
    try {
      if (profile.isFollowing) {
        await _repository.unfollow(profile.id);
      } else {
        await _repository.follow(profile.id);
      }
      if (!mounted) return;
      setState(() {
        _profile = profile.copyWith(
          isFollowing: !profile.isFollowing,
          followersCount:
              (profile.followersCount + (profile.isFollowing ? -1 : 1)).clamp(
                0,
                1 << 31,
              ),
        );
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppL10n.of(context).socialActionFailed)),
      );
    } finally {
      if (mounted) setState(() => _relationshipInFlight = false);
    }
  }

  Future<void> _handleAction(_ProfileAction action) async {
    if (!await _requireSignIn() || !mounted) return;
    switch (action) {
      case _ProfileAction.report:
        final callback = widget.onReportRequested;
        if (callback != null) {
          callback();
        } else {
          final result = await Navigator.of(context).push<UserReportResult>(
            MaterialPageRoute<UserReportResult>(
              builder: (_) => UserReportPage(
                targetUserId: widget.userId,
                sourceWorkId: widget.seedWork?.id,
                repository: _repository,
              ),
            ),
          );
          if (!mounted || result == null) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.failedEvidenceCount == 0
                    ? AppL10n.of(context).reportUserSubmitted
                    : AppL10n.of(context).reportSubmittedPartial,
              ),
            ),
          );
        }
      case _ProfileAction.block:
        await _confirmBlock();
    }
  }

  Future<void> _confirmBlock() async {
    final l = AppL10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.profileBlockTitle),
        content: Text(l.profileBlockBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AetherColors.danger),
            child: Text(l.profileBlockConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.block(widget.userId);
      if (!mounted) return;
      Navigator.of(context).maybePop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.profileBlockFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    return Scaffold(
      backgroundColor: AetherColors.bgCanvas,
      appBar: AppBar(
        backgroundColor: AetherColors.bgCanvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: null,
        leading: IconButton(
          tooltip: l.profileBack,
          onPressed: widget.onExit ?? () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22),
        ),
        actions: [
          if (!_isMine)
            PopupMenuButton<_ProfileAction>(
              key: const Key('profile-overflow'),
              tooltip: l.profileMore,
              position: PopupMenuPosition.under,
              offset: const Offset(0, 4),
              constraints: const BoxConstraints(minWidth: 156),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_horiz, size: 20),
              onSelected: _handleAction,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _ProfileAction.report,
                  child: Text(l.profileReportUser),
                ),
                PopupMenuItem(
                  value: _ProfileAction.block,
                  child: Text(
                    l.profileBlockUser,
                    style: const TextStyle(color: AetherColors.danger),
                  ),
                ),
              ],
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth >= 760 ? _buildDesktopBody(l) : _buildBody(l),
      ),
    );
  }

  Widget _buildBody(AppL10n l) {
    final profile = _profile;
    if (profile == null && _loadError == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (profile == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.profileLoadFailed),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: Text(l.communityRetry)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AetherColors.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GeneratedAccountAvatar(
                      userId: profile.id,
                      readPublic: true,
                      radius: 48,
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _nickname(profile),
                          const SizedBox(height: 8),
                          Text(
                            _identityLine(profile),
                            style: AetherTextStyles.bodySm,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (profile.bio != null) ...[
                  const SizedBox(height: 24),
                  Text(profile.bio!, style: AetherTextStyles.body),
                ],
                if (_isMine && widget.onOpenFavorites != null) ...[
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    key: const ValueKey('profile-favorites-button'),
                    onPressed: widget.onOpenFavorites,
                    icon: const Icon(Icons.bookmark_border),
                    label: Text(
                      Localizations.localeOf(context).languageCode == 'zh'
                          ? '我的收藏'
                          : 'Favorites',
                    ),
                  ),
                ],
                if (_isMine && widget.onOpenMessages != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey('profile-messages-button'),
                    onPressed: widget.onOpenMessages,
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: Text(
                      Localizations.localeOf(context).languageCode == 'zh'
                          ? '我的私信'
                          : 'Messages',
                    ),
                  ),
                ],
                if (_isMine)
                  for (final action in widget.accountActions.entries) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: action.value,
                      child: Text(action.key),
                    ),
                  ],
                if (!_isMine && widget.onMessage != null) ...[
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    key: const ValueKey('profile-message-peer-button'),
                    onPressed: _messageProfile,
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: Text(
                      Localizations.localeOf(context).languageCode == 'zh'
                          ? '私信'
                          : 'Message',
                    ),
                  ),
                ],
                if (!_isMine) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: profile.isFollowing
                        ? OutlinedButton(
                            key: const Key('profile-follow-button'),
                            onPressed: _relationshipInFlight
                                ? null
                                : _toggleFollow,
                            child: Text(l.socialFollowing),
                          )
                        : FilledButton(
                            key: const Key('profile-follow-button'),
                            onPressed: _relationshipInFlight
                                ? null
                                : _toggleFollow,
                            style: FilledButton.styleFrom(
                              backgroundColor: AetherColors.primary,
                              foregroundColor: Colors.white,
                            ),
                            child: Text(l.socialFollow),
                          ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: AetherColors.border),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              children: [
                _ProfileCount(
                  value: profile.publicWorksCount,
                  label: l.socialWorks,
                ),
                _ProfileCount(
                  value: profile.followersCount,
                  label: l.socialFollowers,
                ),
                _ProfileCount(
                  value: profile.followingCount,
                  label: l.socialFollow,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AetherColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
            child: ProfileWorkGrid(
              works: _works,
              service: _communityService,
              onWorkTap: widget.onWorkTap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _nickname(SocialProfile profile) => Row(
    children: [
      Flexible(child: Text(profile.displayName, style: AetherTextStyles.h1)),
      if (_isMine && widget.onEditNickname != null)
        IconButton(
          key: const ValueKey('profile-edit-nickname'),
          tooltip: _label('修改昵称', 'Edit nickname'),
          onPressed: widget.onEditNickname,
          icon: const Icon(Icons.edit_outlined, size: 20),
        ),
    ],
  );

  String _label(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  Widget _desktopStat(Object count, String label) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: '$label  ', style: AetherTextStyles.bodySm),
        TextSpan(text: '$count', style: AetherTextStyles.body),
      ],
    ),
  );

  Widget _buildDesktopBody(AppL10n l) {
    final profile = _profile;
    if (profile == null) return _buildBody(l);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const ValueKey('profile-desktop-content'),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(36, 32, 36, 36),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xfff1f2f4), Color(0xfffafafa)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GeneratedAccountAvatar(
                  userId: profile.id,
                  readPublic: true,
                  radius: 64,
                ),
                const SizedBox(width: 32),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _nickname(profile),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 28,
                        runSpacing: 10,
                        children: [
                          _desktopStat(profile.followingCount, l.socialFollow),
                          _desktopStat(
                            profile.followersCount,
                            l.socialFollowers,
                          ),
                          if (_isMine && widget.receivedLikesLoader != null)
                            _desktopStat(
                              _receivedLikes ?? '—',
                              _label('获赞', 'Likes received'),
                            ),
                        ],
                      ),
                      if (_identityLine(profile).isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          _identityLine(profile),
                          style: AetherTextStyles.bodySm,
                        ),
                      ],
                      if (profile.bio?.isNotEmpty == true) ...[
                        const SizedBox(height: 12),
                        Text(profile.bio!, style: AetherTextStyles.body),
                      ],
                      if (!_isMine) ...[
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            FilledButton(
                              key: const Key('profile-follow-button'),
                              onPressed: _relationshipInFlight
                                  ? null
                                  : _toggleFollow,
                              child: Text(
                                profile.isFollowing
                                    ? l.socialFollowing
                                    : l.socialFollow,
                              ),
                            ),
                            if (widget.onMessage != null)
                              OutlinedButton.icon(
                                key: const ValueKey(
                                  'profile-message-peer-button',
                                ),
                                onPressed: _messageProfile,
                                icon: const Icon(
                                  Icons.chat_bubble_outline,
                                  size: 18,
                                ),
                                label: Text(_label('私信', 'Message')),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (_isMine && widget.accountActions.isNotEmpty)
                  PopupMenuButton<String>(
                    key: const ValueKey('profile-account-menu'),
                    tooltip: _label('更多设置', 'More settings'),
                    icon: const Icon(Icons.more_horiz),
                    onSelected: (label) => widget.accountActions[label]?.call(),
                    itemBuilder: (_) => widget.accountActions.keys
                        .map(
                          (label) =>
                              PopupMenuItem(value: label, child: Text(label)),
                        )
                        .toList(),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Container(
                    key: const ValueKey('profile-works-tab'),
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(width: 3)),
                    ),
                    child: Text(
                      '${l.socialWorks} ${profile.publicWorksCount}',
                      style: AetherTextStyles.body,
                    ),
                  ),
                  if (_isMine && widget.onOpenLikes != null) ...[
                    const SizedBox(width: 28),
                    TextButton.icon(
                      key: const ValueKey('profile-likes-button'),
                      onPressed: widget.onOpenLikes,
                      icon: const Icon(Icons.lock_outline, size: 16),
                      label: Text(_label('喜欢', 'Likes')),
                    ),
                  ],
                  if (_isMine && widget.onOpenFavorites != null) ...[
                    const SizedBox(width: 28),
                    TextButton.icon(
                      key: const ValueKey('profile-favorites-button'),
                      onPressed: widget.onOpenFavorites,
                      icon: const Icon(Icons.lock_outline, size: 16),
                      label: Text(_label('收藏', 'Favorites')),
                    ),
                  ],
                  if (_isMine && widget.onOpenHistory != null) ...[
                    const SizedBox(width: 28),
                    TextButton.icon(
                      key: const ValueKey('profile-history-button'),
                      onPressed: widget.onOpenHistory,
                      icon: const Icon(Icons.lock_outline, size: 16),
                      label: Text(_label('观看历史', 'History')),
                    ),
                  ],
                  if (_isMine && widget.onOpenMessages != null) ...[
                    const SizedBox(width: 28),
                    TextButton(
                      key: const ValueKey('profile-messages-button'),
                      onPressed: widget.onOpenMessages,
                      child: Text(_label('私信', 'Messages')),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: AetherColors.border),
          if (_works.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 100,
                horizontal: 24,
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.view_in_ar_outlined,
                    size: 56,
                    color: AetherColors.textTertiary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _label('暂无公开作品', 'No public works yet'),
                    style: AetherTextStyles.h2,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _label(
                      '发布的公开作品会显示在这里',
                      'Published public works appear here',
                    ),
                    style: AetherTextStyles.bodySm,
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 24, 36, 80),
              child: ProfileWorkGrid(
                works: _works,
                service: _communityService,
                onWorkTap: widget.onWorkTap,
              ),
            ),
        ],
      ),
    );
  }

  String _identityLine(SocialProfile profile) {
    final parts = <String>[
      if (profile.handle != null) '@${profile.handle}',
      if (profile.lastRegion != null) profile.lastRegion!,
    ];
    return parts.join(' · ');
  }
}

class _ProfileCount extends StatelessWidget {
  const _ProfileCount({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text('$value', style: AetherTextStyles.h2),
          const SizedBox(height: 8),
          Text(label, style: AetherTextStyles.bodySm),
        ],
      ),
    );
  }
}
