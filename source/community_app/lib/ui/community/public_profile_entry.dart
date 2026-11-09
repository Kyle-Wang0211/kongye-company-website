import 'package:supabase_flutter/supabase_flutter.dart';
import '../social/community_capabilities.dart';
import 'package:flutter/material.dart';

import '../../auth/current_user.dart';
import '../../auth/auth_scope.dart';
import '../../community/social_profile_repository.dart';
import '../../community/community_service.dart';
import '../../community/feed_models.dart';
import 'public_work_entry.dart' show PublicWorkSignIn;
import 'public_work_exit_stub.dart'
    if (dart.library.js_interop) 'public_work_exit_web.dart';
import 'user_profile_page.dart';
import 'community_profile_shell.dart';
import 'community_navigation_frame.dart';
import '../social/community_account_routes.dart' show WebFavoritesAccountEntry;
import '../../community/account_work_library_repository.dart';
import '../../me/profile_likes_repository.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../social/web_messaging_entry.dart';
import 'work_detail_page.dart';

/// Canonical link shared by the website author links and detail-page routes.
/// Public profile links never retain a previous work or auth query.
Uri publicProfileUri(Uri communityUri, String userId) =>
    communityUri.replace(queryParameters: {'profile': userId}, fragment: '');

/// Shared author navigation keeps native injected repositories and services.
Widget communityProfilePage(
  BuildContext context, {
  required String userId,
  FeedWork? seedWork,
  CommunityService? communityService,
  SocialProfileRepository? repository,
}) {
  final user = context.getInheritedWidgetOfExactType<AuthScope>()?.notifier;
  if (user == null) {
    return UserProfilePage(
      userId: userId,
      seedWork: seedWork,
      communityService: communityService,
      repository: repository,
    );
  }
  return PublicProfileEntry(
    user: user,
    userId: userId,
    seedWork: seedWork,
    communityService: communityService,
    repository: repository,
  );
}

/// Browser wiring around the existing mobile profile, repository and work grid.
class PublicProfileEntry extends StatefulWidget {
  const PublicProfileEntry({
    super.key,
    required this.user,
    this.userId,
    this.seedWork,
    this.communityService,
    this.repository,
  });

  final CurrentUser user;
  final String? userId;
  final FeedWork? seedWork;
  final CommunityService? communityService;
  final SocialProfileRepository? repository;

  @override
  State<PublicProfileEntry> createState() => _PublicProfileEntryState();
}

class _PublicProfileEntryState extends State<PublicProfileEntry> {
  late final CommunityService _service =
      widget.communityService ?? CommunityService();
  bool _signInPending = false;
  int _profileRevision = 0;

  Future<void> _signIn() async {
    if (_signInPending || !mounted) return;
    _signInPending = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => PublicWorkSignIn(user: widget.user)),
      );
    } finally {
      _signInPending = false;
      if (mounted) setState(() {});
    }
  }

  void _exit() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      exitPublicWork();
    }
  }

  Future<void> _openAccount(String route) async {
    if (widget.user.signedInUser == null) await _signIn();
    if (!mounted) return;
    final owner = widget.user.signedInUser?.id.rawValue;
    if (owner == null) return;
    await Navigator.of(context).pushNamed(route);
    if (mounted && widget.user.signedInUser?.id.rawValue == owner) {
      setState(() => _profileRevision++);
    }
  }

  Future<void> _signOut() async {
    try {
      await widget.user.signOut();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('退出未完成，请重试。')));
      }
    }
  }

  void _openWork(FeedWork work) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => WorkDetailPage(
          work: work,
          service: _service,
          onSignIn: _signIn,
          onAuthorTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              settings: RouteSettings(
                name: publicProfileUri(Uri(path: '/'), work.userId).toString(),
              ),
              builder: (_) => PublicProfileEntry(
                user: widget.user,
                userId: work.userId,
                seedWork: work,
                communityService: _service,
                repository: widget.repository,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _label(BuildContext context, String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.user,
    builder: (context, _) => _buildProfile(context),
  );

  Widget _buildProfile(BuildContext context) {
    final owner = widget.user.signedInUser?.id.rawValue;
    final target = widget.userId ?? Uri.base.queryParameters['profile'] ?? '';
    final profile = UserProfilePage(
      key: ValueKey('$target:$owner:$_profileRevision'),
      userId: target,
      libraryTabs: {
        if (owner != null && owner == target) ...{
          'likes': (_) => WebFavoritesAccountEntry(
            user: widget.user,
            ownerId: owner,
            kind: AccountWorkLibraryKind.likes,
            embedded: true,
          ),
          'history': (_) => WebFavoritesAccountEntry(
            user: widget.user,
            ownerId: owner,
            kind: AccountWorkLibraryKind.history,
            embedded: true,
          ),
          if (CommunityCapabilities.favorites)
            'favorites': (_) => WebFavoritesAccountEntry(
              user: widget.user,
              ownerId: owner,
              embedded: true,
            ),
        },
      },
      seedWork: widget.seedWork,
      repository: widget.repository,
      communityService: _service,
      onSignIn: _signIn,
      onEditNickname: CommunityCapabilities.profiles
          ? () => _openAccount('/profile-edit')
          : null,
      onExit: _exit,
      onOpenFavorites: CommunityCapabilities.favorites
          ? () => Navigator.of(context).pushNamed('/favorites')
          : null,
      onOpenMessages: () => _openAccount('/messages'),
      onOpenLikes: () => _openAccount('/likes'),
      onOpenHistory: () => _openAccount('/history'),
      receivedLikesLoader:
          widget.user.signedInUser?.id.rawValue ==
              (widget.userId ?? Uri.base.queryParameters['profile'])
          ? SupabaseProfileLikesRepository(
              client: Supabase.instance.client,
            ).fetchReceivedLikes
          : null,
      onMessage: (profile) => Navigator.of(context).pushNamed(
        '/messages',
        arguments: WebMessagingPeer(
          id: profile.id,
          displayName: profile.displayName,
        ),
      ),
      accountActions: {
        if (CommunityCapabilities.profiles)
          _label(context, '编辑资料', 'Edit profile'): () =>
              _openAccount('/profile-edit'),
        _label(context, '发布记录', 'Publications'): () =>
            _openAccount('/publications'),
        _label(context, '我的举报', 'My reports'): () => _openAccount('/reports'),
        _label(context, '账号与隐私', 'Account and privacy'): () =>
            _openAccount('/privacy'),
        _label(context, '举报审核', 'Report review'): () =>
            _openAccount('/report-review'),
        _label(context, '退出登录', 'Sign out'): _signOut,
      },
      onWorkTap: _openWork,
    );
    if (!kIsWeb || CommunityNavigationScope.maybeOf(context) != null) {
      return profile;
    }
    return CommunityProfileShell(
      onHome: exitPublicWork,
      onMyProfile: () {
        final owner = widget.user.signedInUser?.id.rawValue;
        if (owner == null) {
          _signIn();
          return;
        }
        if (owner == widget.userId) {
          setState(() => _profileRevision++);
          return;
        }
        Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) =>
                PublicProfileEntry(user: widget.user, userId: owner),
          ),
        );
      },
      onFollowing: openCommunityFollowing,
      onSettings: openCommunitySettings,
      onOpenFiling: openCommunityFiling,
      onMessages: () => _openAccount('/messages'),
      onPublish: () => _openAccount('/publish'),
      child: profile,
    );
  }
}
