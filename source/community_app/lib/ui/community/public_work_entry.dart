import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/current_user.dart';
import '../../l10n/app_localizations.dart';
import '../../community/community_service.dart';
import '../../community/feed_models.dart';
import '../../community/public_work_repository.dart';
import '../auth/auth_root_view.dart';
import 'work_detail_page.dart';
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
  bool _signInPending = false;
  late final service = CommunityService();
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final id = publicWorkId(Uri.base);
    _work = id == null
        ? Future.error(const FormatException('作品链接无效'))
        : PublicWorkRepository(Supabase.instance.client).fetch(id);
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
      if (snapshot.hasData) {
        return WorkDetailPage(
          work: snapshot.data!,
          service: service,
          onSignIn: _signIn,
          onExit: exitPublicWork,
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
