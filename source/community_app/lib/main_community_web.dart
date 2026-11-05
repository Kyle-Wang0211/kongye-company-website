// Community-only browser entry. Existing community/auth/viewer widgets are reused.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth/auth_scope.dart';
import 'ui/community/public_work_entry.dart';
import 'ui/community/work_detail_page.dart';
import 'ui/social/web_favorites_page.dart';
import 'ui/social/web_messaging_entry.dart';
import 'ui/social/web_profile_edit_entry.dart';
import 'ui/social/web_account_workflow_repository.dart';
import 'ui/social/web_account_privacy_page.dart';
import 'ui/social/web_publication_status_page.dart';
import 'ui/social/web_report_history_page.dart';
import 'ui/social/web_report_review_page.dart';
import 'community/web_messaging_repository.dart';
import 'community/web_social_api.dart';
import 'community/public_work_repository.dart';
import 'community/community_service.dart';
import 'ui/community/public_work_opening.dart';
import 'ui/community/public_profile_entry.dart';
import 'ui/community/web_publication_page.dart';
import 'ui/community/public_work_exit_stub.dart'
    if (dart.library.js_interop) 'ui/community/public_work_exit_web.dart';
import 'auth/current_user.dart';
import 'auth/unavailable_auth_service.dart';
import 'auth/supabase_auth_service.dart';
import 'auth/cold_start_session_gate.dart';
import 'auth/data_api_readiness_gate.dart';
import 'config/backend_deployment.dart';
import 'config/endpoint_config.dart';
import 'i18n/locale_notifier.dart';
import 'l10n/app_localizations.dart';
import 'ui/auth/auth_root_view.dart';
import 'ui/design_system.dart';
import 'ui/startup_splash_gate.dart';
import 'ui/vault_page.dart';
import 'ui/shared/community_viewer_session.dart';
import 'util/device_log.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final deployment = BackendDeployment.chinaFromBuild();
  final locale = LocaleNotifier();
  final user = CurrentUser(
    service: const UnavailableAuthService(),
    deployment: deployment,
    onIdentityInvalidated: () {
      unawaited(CommunityViewerSessions.instance.clear());
      dataApiReadinessGate.reset();
    },
  );
  user.retryInit = () => _initialize(user, locale);
  // This entry has no native startup animation/archive/capture runtime.
  StartupSplashGate.instance.markDone();
  runApp(CommunityWebApp(user: user, locale: locale));
  unawaited(locale.bootstrap());
  unawaited(_initialize(user, locale));
}

Future<void>? _supabaseInit;
StreamSubscription<AuthState>? _authStateSubscription;
Future<void> _startSupabase(EndpointConfig endpoint) {
  late final Future<void> f;
  f =
      Supabase.initialize(
        url: endpoint.supabaseUrl,
        anonKey: endpoint.supabaseAnonKey,
        debug: false,
        authOptions: FlutterAuthClientOptions(
          localStorage: SharedPreferencesLocalStorage(
            persistSessionKey: 'sb-api-rds20261104-auth-token',
          ),
        ),
        // Official Supabase Flutter browser persistence.
      ).then<void>(
        (_) {},
        onError: (Object e, StackTrace st) {
          if (identical(_supabaseInit, f)) _supabaseInit = null;
          DeviceLog.log('AuthStartup', 'Supabase.initialize error: $e');
          throw e;
        },
      );
  // 超时分支不再等它;它之后若失败已在上面记日志,不要再冒成未捕获异常。
  f.ignore();
  return f;
}

Future<void> _initialize(
  CurrentUser currentUser,
  LocaleNotifier localeNotifier,
) async {
  try {
    // Backend address is resolved at RUNTIME — see
    // lib/config/endpoint_config.dart. It used to be read straight from
    // `String.fromEnvironment` here, but `--dart-define` does not reach
    // this project's iOS xcconfig chain (verified on device
    // 2026-08-09), so the defaults were the shipped values: the backend
    // host was effectively compiled into the binary, and moving it
    // meant cutting a release and waiting for adoption. The resolver
    // falls back to those same constants, so with no config endpoint
    // set this is byte-for-byte the previous behaviour.
    //
    // The anon key is intentionally public — RLS policies on each
    // table do the actual access control.
    final endpoint = await EndpointConfigResolver.resolve(
      deployment: currentUser.deployment,
    );
    debugPrint('[main] backend endpoint resolved: $endpoint');
    const initTimeout = Duration(seconds: 10);
    bool supabaseReady = false;
    try {
      // 重试时复用仍在途的 initialize(超时只是我们不再等,底层还在跑);
      // 只有它真的失败了才允许下一次重试重新发起。
      final inflight = _supabaseInit ??= _startSupabase(endpoint);
      await inflight.timeout(initTimeout);
      supabaseReady = true;
    } catch (e) {
      DeviceLog.log('AuthStartup', 'Supabase.initialize failed/timeout: $e');
      currentUser.markServiceUnavailable('Supabase.initialize: $e');
      return;
    }
    if (supabaseReady) {
      final auth = Supabase.instance.client.auth;
      final restoredSession = auth.currentSession;
      final gateResult = await waitForColdStartSession(
        hasSession: restoredSession != null,
        isExpired: restoredSession?.isExpired ?? false,
        authEvents: auth.onAuthStateChange.map((state) {
          return switch (state.event) {
            AuthChangeEvent.tokenRefreshed => ColdStartAuthEvent.tokenRefreshed,
            AuthChangeEvent.signedOut => ColdStartAuthEvent.signedOut,
            _ => ColdStartAuthEvent.other,
          };
        }),
        fallbackRefresh: () async {
          await auth.refreshSession();
        },
      );
      DeviceLog.log('AuthStartup', 'session gate=$gateResult');
      // [合并自 reporting 线] 令牌刷新/登出时重置 data-api 就绪门,
      // 否则换了身份后仍拿旧的就绪状态。
      await _authStateSubscription?.cancel();
      _authStateSubscription = auth.onAuthStateChange.listen((state) {
        if (state.event == AuthChangeEvent.tokenRefreshed ||
            state.event == AuthChangeEvent.signedOut) {
          dataApiReadinessGate.reset();
        }
        if (state.event == AuthChangeEvent.signedOut) {
          unawaited(currentUser.handleProviderSignedOut());
        }
      });
      // ignore: avoid_print
      print(
        '[AUTH-DEBUG] Supabase.initialize done. '
        'currentSession exists: '
        '${Supabase.instance.client.auth.currentSession != null}',
      );
      currentUser.swapService(
        SupabaseAuthServiceImpl(localeNotifier: localeNotifier),
      );
      await currentUser.bootstrap();
    }
  } catch (e, st) {
    DeviceLog.log('AuthStartup', 'init failed: $e\n$st');
    currentUser.markServiceUnavailable('init: $e');
  }
}

ThemeData communityWebTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: AetherColors.primary,
    dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
    primary: AetherColors.primary,
    secondary: AetherColors.primarySoft,
    error: AetherColors.danger,
  ),
  textSelectionTheme: const TextSelectionThemeData(
    cursorColor: AetherColors.primary,
    selectionColor: Color(0x33111111),
    selectionHandleColor: AetherColors.primary,
  ),
  scaffoldBackgroundColor: AetherColors.bg,
  canvasColor: AetherColors.bg,
  useMaterial3: true,
);

class CommunityWebApp extends StatefulWidget {
  const CommunityWebApp({super.key, required this.user, required this.locale});
  final CurrentUser user;
  final LocaleNotifier locale;

  @override
  State<CommunityWebApp> createState() => _CommunityWebAppState();
}

class _CommunityWebAppState extends State<CommunityWebApp> {
  CurrentUser get user => widget.user;
  LocaleNotifier get locale => widget.locale;
  String? _previousAccount;
  int _navigationEpoch = 0;

  Key _navigationIdentity() {
    final owner = user.signedInUser?.id.rawValue;
    final account = owner == null
        ? null
        : '${user.deployment.namespace}:$owner';
    // A revoked/replaced account must also discard dialogs on the root
    // Navigator. First sign-in preserves the public reading route underneath.
    if (_previousAccount != null && _previousAccount != account) {
      _navigationEpoch++;
    }
    _previousAccount = account;
    return ValueKey(_navigationEpoch);
  }

  @override
  Widget build(BuildContext context) => LocaleScope(
    notifier: locale,
    child: AnimatedBuilder(
      animation: Listenable.merge([locale, user]),
      builder: (context, _) => MaterialApp(
        key: _navigationIdentity(),
        title: 'PocketWorld',
        debugShowCheckedModeBanner: false,
        theme: communityWebTheme(),
        locale: locale.locale,
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        builder: (context, child) =>
            AuthScope(currentUser: user, child: child!),
        onGenerateRoute: (settings) =>
            communityFavoritesRoute(settings, user) ??
            communityMessagingRoute(settings, user) ??
            communityAccountRoute(settings, user),
        home: AnimatedBuilder(
          animation: user,
          builder: (context, _) {
            final state = user.state;
            // Public profiles use the existing mobile page for guests and
            // members, once the shared backend initialization has completed.
            if ((state is CurrentUserSignedIn ||
                    state is CurrentUserSignedOut) &&
                Uri.base.queryParameters.containsKey('profile')) {
              return PublicProfileEntry(user: user);
            }
            return switch (state) {
              CurrentUserSignedIn() =>
                Uri.base.queryParameters.containsKey('work')
                    ? PublicWorkEntry(user: user)
                    : Uri.base.queryParameters['publish'] == '1'
                    ? const _WebPublicationEntry()
                    : const VaultPage(),
              CurrentUserSignedOut() =>
                Uri.base.queryParameters.containsKey('work')
                    ? PublicWorkEntry(user: user)
                    : AuthRootView(
                        currentUser: user,
                        initialSignUp:
                            Uri.base.queryParameters['auth'] == 'signup',
                      ),
              CurrentUserServiceUnavailable(:final reason) =>
                _ServiceUnavailableView(currentUser: user, reason: reason),
              _ =>
                Uri.base.queryParameters.containsKey('work')
                    ? PublicWorkOpening()
                    : const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      ),
            };
          },
        ),
      ),
    ),
  );
}

/// Private account destination remains behind the current Auth startup state.
Route<void>? communityFavoritesRoute(RouteSettings settings, CurrentUser user) {
  if (settings.name != '/favorites' ||
      !const bool.fromEnvironment('PW_WEB_FAVORITES_ENABLED')) {
    return null;
  }
  return MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => AnimatedBuilder(
      animation: user,
      builder: (context, _) {
        final state = user.state;
        if (state case CurrentUserServiceUnavailable(:final reason)) {
          return _ServiceUnavailableView(currentUser: user, reason: reason);
        }
        final owner = user.signedInUser?.id.rawValue;
        if (owner == null) {
          return state is CurrentUserSignedOut
              ? AuthRootView(currentUser: user)
              : const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
        }
        return WebFavoritesAccountEntry(
          key: ValueKey('${user.deployment.namespace}:$owner:favorites'),
          user: user,
          ownerId: owner,
        );
      },
    ),
  );
}

/// Reuses the account startup gate for inbox and profile-originated messages.
Route<void>? communityMessagingRoute(
  RouteSettings settings,
  CurrentUser user, {
  WebMessagingRepository? repository,
}) {
  if (settings.name != '/messages') return null;
  final peer = settings.arguments is WebMessagingPeer
      ? settings.arguments as WebMessagingPeer
      : null;
  return MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => AnimatedBuilder(
      animation: user,
      builder: (context, _) {
        final state = user.state;
        if (state case CurrentUserServiceUnavailable(:final reason)) {
          return _ServiceUnavailableView(currentUser: user, reason: reason);
        }
        final owner = user.signedInUser?.id.rawValue;
        if (owner == null) {
          return state is CurrentUserSignedOut
              ? AuthRootView(currentUser: user)
              : const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
        }
        return WebMessagingEntry(
          key: ValueKey(
            '${user.deployment.namespace}:$owner:messages:${peer?.id ?? ''}',
          ),
          user: user,
          ownerId: owner,
          peerId: peer?.id,
          peerName: peer?.displayName,
          repository: repository,
        );
      },
    ),
  );
}

/// Account pages remain behind the same live Auth state as inbox and favorites.
Route<void>? communityAccountRoute(
  RouteSettings settings,
  CurrentUser user, {
  Widget Function(BuildContext context, String ownerId)? pageBuilder,
}) {
  if (!const {
    '/profile-edit',
    '/publications',
    '/reports',
    '/privacy',
    '/report-review',
  }.contains(settings.name)) {
    return null;
  }
  return MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => AnimatedBuilder(
      animation: user,
      builder: (context, _) {
        final state = user.state;
        if (state case CurrentUserServiceUnavailable(:final reason)) {
          return _ServiceUnavailableView(currentUser: user, reason: reason);
        }
        final owner = user.signedInUser?.id.rawValue;
        if (owner == null) {
          return state is CurrentUserSignedOut
              ? AuthRootView(currentUser: user)
              : const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
        }
        return KeyedSubtree(
          key: ValueKey('${user.deployment.namespace}:$owner:${settings.name}'),
          child:
              pageBuilder?.call(context, owner) ??
              _WebAccountDestination(
                user: user,
                ownerId: owner,
                destination: settings.name!,
              ),
        );
      },
    ),
  );
}

class _WebAccountDestination extends StatefulWidget {
  const _WebAccountDestination({
    required this.user,
    required this.ownerId,
    required this.destination,
  });
  final CurrentUser user;
  final String ownerId, destination;
  @override
  State<_WebAccountDestination> createState() => _WebAccountDestinationState();
}

class _WebAccountDestinationState extends State<_WebAccountDestination> {
  late final WebAccountWorkflowRepository _repository;
  bool get _current =>
      mounted && widget.user.signedInUser?.id.rawValue == widget.ownerId;

  @override
  void initState() {
    super.initState();
    _repository = WebAccountWorkflowRepository(
      client: Supabase.instance.client,
      accountId: widget.ownerId,
    );
  }

  Future<void> _openWork(String id) async {
    if (!_current) return;
    try {
      final work = await PublicWorkRepository(
        Supabase.instance.client,
      ).fetch(id);
      if (!mounted || !_current) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => WorkDetailPage(
            work: work,
            service: CommunityService(),
            onAuthorTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
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
    } catch (_) {
      if (mounted && _current) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('作品暂不可访问，请刷新状态后重试。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => switch (widget.destination) {
    '/profile-edit' => WebProfileEditEntry(
      user: widget.user,
      ownerId: widget.ownerId,
    ),
    '/privacy' => WebAccountPrivacyPage(
      accountId: widget.ownerId,
      accountLabel: widget.user.signedInUser?.displayName,
      loadBlockedUsers: _repository.blockedUsers,
      onUnblock: _repository.unblock,
      onRequestDeletion: _repository.requestDeletion,
    ),
    '/reports' => WebReportHistoryPage(
      accountId: widget.ownerId,
      loader: _repository.reports,
    ),
    '/report-review' => WebReportReviewPage(
      accountId: widget.ownerId,
      loader: _repository.reviewQueue,
      onClaim: _repository.claimReport,
      onTransition: _repository.transitionReport,
      onOpenWork: _openWork,
    ),
    _ => WebPublicationStatusPage(
      accountId: widget.ownerId,
      loader: _loadPublications,
      onOpen: _openWork,
      onWithdraw: _repository.withdraw,
    ),
  };

  Future<List<WebPublicationSummary>> _loadPublications() async {
    if (!_current) throw StateError('Account changed');
    final client = Supabase.instance.client;
    if (client.auth.currentUser?.id != widget.ownerId) {
      throw StateError('Account changed');
    }
    final rows = await client
        .from('works')
        .select(
          'id,user_id,title,moderation_status,visibility,published_at,deleted_at',
        )
        .eq('user_id', widget.ownerId)
        .order('created_at', ascending: false);
    if (!_current || client.auth.currentUser?.id != widget.ownerId) {
      throw StateError('Account changed');
    }
    return rows
        .map((row) {
          final moderation = row['moderation_status'] as String;
          final removed = row['deleted_at'] != null || moderation == 'removed';
          final stage = removed
              ? 'removed'
              : moderation == 'withdrawn'
              ? 'withdrawn'
              : moderation == 'ok'
              ? row['visibility'] == 'public' && row['published_at'] != null
                    ? 'published'
                    : 'private'
              : moderation;
          return WebPublicationSummary(
            id: row['id'] as String,
            title: row['title'] as String? ?? '',
            stage: stage,
            updatedAt: DateTime.tryParse(row['published_at'] as String? ?? ''),
            canWithdraw: !removed && moderation != 'withdrawn',
          );
        })
        .toList(growable: false);
  }
}

class _ServiceUnavailableView extends StatelessWidget {
  const _ServiceUnavailableView({
    required this.currentUser,
    required this.reason,
  });

  final CurrentUser currentUser;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    return Scaffold(
      backgroundColor: AetherColors.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.authServiceUnavailable,
                  textAlign: TextAlign.center,
                  style: AetherTextStyles.body,
                ),
                const SizedBox(height: 24),
                AnimatedBuilder(
                  animation: currentUser,
                  builder: (context, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton(
                        onPressed: currentUser.isRetryingInit
                            ? null
                            : () => unawaited(currentUser.retryServiceInit()),
                        child: Text(l.authRetry),
                      ),
                      if (currentUser.nextAutoRetryAt != null ||
                          currentUser.isRetryingInit) ...[
                        const SizedBox(height: 12),
                        Text(
                          l.authAutoRetrying,
                          textAlign: TextAlign.center,
                          style: AetherTextStyles.caption,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Website publication returns to the website feed, not the native vault feed.
class _WebPublicationEntry extends StatefulWidget {
  const _WebPublicationEntry();
  @override
  State<_WebPublicationEntry> createState() => _WebPublicationEntryState();
}

class _WebPublicationEntryState extends State<_WebPublicationEntry> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const WebPublicationPage()));
    if (mounted) exitPublicWork();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
}

/// Current account binding for the existing favorites API and public work viewer.
class WebFavoritesAccountEntry extends StatefulWidget {
  const WebFavoritesAccountEntry({
    super.key,
    required this.user,
    required this.ownerId,
    this.api,
  });
  final CurrentUser user;
  final String ownerId;
  final WebSocialApi? api;

  @override
  State<WebFavoritesAccountEntry> createState() =>
      _WebFavoritesAccountEntryState();
}

class _WebFavoritesAccountEntryState extends State<WebFavoritesAccountEntry> {
  late final WebSocialApi _api;
  bool get _current =>
      mounted && widget.user.signedInUser?.id.rawValue == widget.ownerId;

  @override
  void initState() {
    super.initState();
    final deployment = widget.user.deployment;
    final endpoint = EndpointConfigResolver.current;
    final origin = Uri.parse(endpoint?.supabaseUrl ?? deployment.supabaseUrl);
    _api =
        widget.api ??
        WebSocialApi(
          apiOrigin: origin,
          supabaseOrigin: origin,
          publishableKey: endpoint?.supabaseAnonKey ?? deployment.anonKey,
          region: deployment.region.name,
          authNamespace: deployment.namespace,
          favoritesEnabled: true,
          accessToken: () {
            if (!_current) return null;
            final auth = Supabase.instance.client.auth;
            return auth.currentUser?.id == widget.ownerId
                ? auth.currentSession?.accessToken
                : null;
          },
          currentUserId: () => _current ? widget.ownerId : null,
        );
  }

  Future<T> _guard<T>(Future<T> Function() operation) async {
    if (!_current) throw const WebSocialUnavailableException('session_changed');
    final result = await operation();
    if (!_current) throw const WebSocialUnavailableException('session_changed');
    return result;
  }

  Future<List<WebFavoriteItem>> _load() => _guard(() async {
    final author = Localizations.localeOf(context).languageCode == 'zh'
        ? '创作者'
        : 'Creator';
    final items = <WebFavoriteItem>[];
    final cursors = <String>{};
    WebFavoriteCursor? cursor;
    do {
      final page = await _guard(
        () => _api.listFavorites(limit: 100, before: cursor),
      );
      items.addAll(
        page.items.map(
          (item) => WebFavoriteItem(
            id: item.workId,
            title: item.title,
            author: author,
          ),
        ),
      );
      cursor = page.next;
      if (cursor != null &&
          !cursors.add('${cursor.savedAt}:${cursor.workId}')) {
        throw const WebSocialUnavailableException('invalid_cursor');
      }
    } while (cursor != null);
    return items;
  });

  Future<void> _open(String id) async {
    try {
      final work = await _guard(
        () => PublicWorkRepository(Supabase.instance.client).fetch(id),
      );
      if (!mounted || !_current) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => WorkDetailPage(
            work: work,
            service: CommunityService(),
            onAuthorTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
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
    } catch (_) {
      if (!mounted || !_current) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localizations.localeOf(context).languageCode == 'zh'
                ? '作品暂不可访问'
                : 'This work is unavailable',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    if (widget.api == null) _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WebFavoritesPage(
    accountId: widget.ownerId,
    loadFavorites: _load,
    onOpen: _open,
    onSetFavorite: (id, saved) => _guard(() async {
      await _api.setFavorite(id, saved);
    }),
  );
}
