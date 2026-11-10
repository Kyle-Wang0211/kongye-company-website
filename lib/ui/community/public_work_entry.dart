import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/current_user.dart';
import '../../l10n/app_localizations.dart';
import '../../community/community_service.dart';
import '../../community/feed_models.dart';
import '../../community/public_work_repository.dart';
import '../auth/auth_root_view.dart';
import 'work_detail_page.dart';
import 'public_work_opening.dart';
import 'public_profile_entry.dart';
import 'public_work_exit_stub.dart'
    if (dart.library.js_interop) 'public_work_exit_web.dart';

/// Reuses the production detail, comments and single shared viewer. Logging in
/// opens only the existing auth form; the work route and its URL remain intact.
class PublicWorkEntry extends StatefulWidget {
  const PublicWorkEntry({super.key, required this.user});
  final CurrentUser user;
  @override
  State<PublicWorkEntry> createState() => _PublicWorkEntryState();
}

class _PublicWorkEntryState extends State<PublicWorkEntry> {
  late Future<FeedWork> _work;
  FeedWork? _loadedWork;
  int _workEpoch = 0;
  int _likeEpoch = 0;
  StreamSubscription<AuthState>? _auth;
  late final _repository = PublicWorkRepository(Supabase.instance.client);
  final FeedWork? _openingWork = readOpeningWork();
  bool _signInPending = false;
  late final service = CommunityService();
  @override
  void initState() {
    super.initState();
    _reload();
    _auth = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      final work = _loadedWork;
      if (!mounted || work == null) return;
      setState(() {
        _loadedWork = work.copyWith(likedByMe: false, likeStateKnown: false);
      });
      unawaited(_loadLike(_loadedWork!, _workEpoch));
    });
  }

  void _reload() {
    final epoch = ++_workEpoch;
    _likeEpoch++;
    _loadedWork = null;
    final id = publicWorkId(Uri.base);
    _work = id == null
        ? Future.error(const FormatException('作品链接无效'))
        : _loadWork(id, epoch);
  }

  Future<FeedWork> _loadWork(String id, int epoch) async {
    var work = await _repository.fetchPublic(id);
    final opening = _openingWork;
    if (opening != null &&
        opening.id == work.id &&
        opening.userId == work.userId) {
      work = work.copyWith(
        authorDisplayName: opening.authorDisplayName,
        authorAvatarUrl: opening.authorAvatarUrl,
        authorHandle: opening.authorHandle,
      );
    }
    if (mounted && epoch == _workEpoch) {
      _loadedWork = work;
      unawaited(_loadAuthor(work, epoch));
      unawaited(_loadLike(work, epoch));
    }
    return work;
  }

  Future<void> _loadAuthor(FeedWork work, int epoch) async {
    try {
      final updated = await _repository.fetchAuthor(work);
      if (!mounted || epoch != _workEpoch || _loadedWork?.id != work.id) return;
      setState(() {
        // Merge metadata into the latest row, preserving its model and camera.
        _loadedWork = _loadedWork!.copyWith(
          authorDisplayName: updated.authorDisplayName,
          authorAvatarUrl: updated.authorAvatarUrl,
          authorHandle: updated.authorHandle,
        );
      });
    } catch (_) {
      // The public work remains usable when optional author metadata fails.
    }
  }

  Future<void> _loadLike(FeedWork work, int workEpoch) async {
    final epoch = ++_likeEpoch;
    final session = Supabase.instance.client.auth.currentSession;
    try {
      final updated = await _repository.fetchLike(work);
      if (!mounted ||
          epoch != _likeEpoch ||
          workEpoch != _workEpoch ||
          !identical(Supabase.instance.client.auth.currentSession, session) ||
          _loadedWork?.id != work.id) {
        return;
      }
      setState(() {
        _loadedWork = _loadedWork!.copyWith(
          likedByMe: updated.likedByMe,
          likeStateKnown: true,
        );
      });
    } catch (_) {
      // Unknown stays unknown. A failed read never authorizes a like write.
    }
  }

  @override
  void dispose() {
    _workEpoch++;
    _likeEpoch++;
    unawaited(_auth?.cancel());
    super.dispose();
  }

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

  @override
  Widget build(BuildContext context) => FutureBuilder<FeedWork>(
    future: _work,
    builder: (context, snapshot) {
      if (snapshot.hasData && _loadedWork != null) {
        final work = _loadedWork!;
        return WorkDetailPage(
          work: work,
          service: service,
          onSignIn: _signIn,
          onExit: exitPublicWork,
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
        );
      }
      if (snapshot.hasError) {
        return Scaffold(
          appBar: AppBar(
            title: Text(AppL10n.of(context).publicWorkTitle),
            leading: BackButton(onPressed: exitPublicWork),
          ),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(AppL10n.of(context).publicWorkUnavailable),
                TextButton(
                  onPressed: () => setState(_reload),
                  child: Text(AppL10n.of(context).commentReload),
                ),
              ],
            ),
          ),
        );
      }
      return PublicWorkOpening(work: _openingWork);
    },
  );
}

class PublicWorkSignIn extends StatefulWidget {
  const PublicWorkSignIn({super.key, required this.user});
  final CurrentUser user;
  @override
  State<PublicWorkSignIn> createState() => _WorkSignInState();
}

class _WorkSignInState extends State<PublicWorkSignIn> {
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    widget.user.addListener(_changed);
  }

  void _changed() {
    if (!_closing && widget.user.state is CurrentUserSignedIn) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final navigator = Navigator.of(context);
        final signInRoute = ModalRoute.of(context);
        // Email/phone/reset/sign-up forms can push their own routes. Dismiss
        // that auth stack as well, preserving the original work beneath it.
        navigator.popUntil((route) => identical(route, signInRoute));
        navigator.pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppL10n.of(context).commentSignIn)),
    body: AuthRootView(currentUser: widget.user),
  );
  @override
  void dispose() {
    widget.user.removeListener(_changed);
    super.dispose();
  }
}
