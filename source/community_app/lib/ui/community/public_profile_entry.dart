import 'package:flutter/material.dart';

import '../../auth/current_user.dart';
import '../../community/community_service.dart';
import '../../community/feed_models.dart';
import 'public_work_entry.dart' show PublicWorkSignIn;
import 'public_work_exit_stub.dart'
    if (dart.library.js_interop) 'public_work_exit_web.dart';
import 'user_profile_page.dart';
import 'work_detail_page.dart';

/// Canonical link shared by the website author links and detail-page routes.
/// Public profile links never retain a previous work or auth query.
Uri publicProfileUri(Uri communityUri, String userId) => communityUri.replace(
  queryParameters: {'profile': userId},
  fragment: '',
);

/// Browser wiring around the existing mobile profile, repository and work grid.
class PublicProfileEntry extends StatefulWidget {
  const PublicProfileEntry({
    super.key,
    required this.user,
    this.userId,
    this.seedWork,
  });

  final CurrentUser user;
  final String? userId;
  final FeedWork? seedWork;

  @override
  State<PublicProfileEntry> createState() => _PublicProfileEntryState();
}

class _PublicProfileEntryState extends State<PublicProfileEntry> {
  final CommunityService _service = CommunityService();
  bool _signInPending = false;

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
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => UserProfilePage(
    userId: widget.userId ?? Uri.base.queryParameters['profile'] ?? '',
    seedWork: widget.seedWork,
    communityService: _service,
    onSignIn: _signIn,
    onExit: _exit,
    onOpenFavorites: const bool.fromEnvironment('PW_WEB_FAVORITES_ENABLED')
        ? () => Navigator.of(context).pushNamed('/favorites')
        : null,
    onWorkTap: _openWork,
  );
}
