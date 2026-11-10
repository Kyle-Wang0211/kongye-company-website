// Community-only browser entry. Existing community/auth/viewer widgets are reused.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth/auth_scope.dart';
import 'ui/community/public_work_entry.dart';
import 'ui/vault_page.dart';
import 'ui/community/public_work_opening.dart';
import 'ui/community/public_profile_entry.dart';
import 'ui/community/community_navigation_frame.dart';
import 'ui/community/public_work_exit_stub.dart'
    if (dart.library.js_interop) 'ui/community/public_work_exit_web.dart';
import 'auth/current_user.dart';
import 'auth/unavailable_auth_service.dart';
import 'auth/supabase_auth_service.dart';
import 'auth/wechat_sign_in.dart';
import 'auth/cold_start_session_gate.dart';
import 'auth/data_api_readiness_gate.dart';
import 'config/backend_deployment.dart';
import 'config/endpoint_config.dart';
import 'ui/social/community_account_routes.dart';
export 'ui/social/community_account_routes.dart';
import 'i18n/locale_notifier.dart';
import 'l10n/app_localizations.dart';
import 'ui/auth/auth_root_view.dart';
import 'ui/design_system.dart';
import 'ui/startup_splash_gate.dart';
import 'ui/shared/community_viewer_session.dart';
import 'util/device_log.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Consume and remove the native callback before Auth inspects the URL.
  wechatSignInFlow.captureCallback();
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
      final wechatRequest = wechatSignInFlow.consumeCallback(
        signedOut: currentUser.state is CurrentUserSignedOut,
      );
      if (wechatRequest != null) await currentUser.signIn(wechatRequest);
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
  const CommunityWebApp({
    super.key,
    required this.user,
    required this.locale,
    this.onExit = exitCommunityHome,
    this.entryUri,
  });
  final CurrentUser user;
  final LocaleNotifier locale;
  final VoidCallback onExit;
  final Uri? entryUri;

  @override
  State<CommunityWebApp> createState() => _CommunityWebAppState();
}

class _CommunityWebAppState extends State<CommunityWebApp> {
  CurrentUser get user => widget.user;
  LocaleNotifier get locale => widget.locale;
  final _navigationIdentity = CommunityAccountNavigationIdentity();
  // Keep the observer with the account-owned Navigator. Identity changes create
  // a fresh Navigator and must not reuse an observer still attached to the old one.
  Key? _navigatorKey;
  RouteObserver<ModalRoute<void>> _routes = RouteObserver<ModalRoute<void>>();
  CommunitySidebarRouteObserver _sidebarRoutes =
      CommunitySidebarRouteObserver();
  GlobalKey<NavigatorState> _communityNavigator = GlobalKey<NavigatorState>();
  CommunityNavigationController _navigationController =
      CommunityNavigationController();
  late final Uri _entryUri = Uri.base;

  Key _navigationKey() {
    final key = _navigationIdentity.keyFor(user);
    if (_navigatorKey != key) {
      _navigatorKey = key;
      _routes = RouteObserver<ModalRoute<void>>();
      _sidebarRoutes.dispose();
      _sidebarRoutes = CommunitySidebarRouteObserver();
      _communityNavigator = GlobalKey<NavigatorState>();
      _navigationController = CommunityNavigationController();
    }
    return key;
  }

  Future<void> _exitDocument(VoidCallback action) async {
    final controller = _navigationController;
    if (await controller.confirmDocumentExit() &&
        mounted &&
        identical(controller, _navigationController)) {
      action();
    }
  }

  void _openMyProfile() {
    final navigator = _communityNavigator.currentState;
    if (navigator == null) return;
    final owner = user.signedInUser?.id.rawValue;
    if (owner == null) {
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(builder: (_) => PublicWorkSignIn(user: user)),
        ),
      );
      return;
    }
    if (communityOwnProfileIsTop(
      _entryUri,
      _sidebarRoutes.currentRouteObject?.settings,
      owner,
    )) {
      return;
    }
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(
          settings: const RouteSettings(name: '/profile'),
          builder: (_) => PublicProfileEntry(user: user, userId: owner),
        ),
      ),
    );
  }

  void _openMessages() {
    if (!communityInboxIsTop(_sidebarRoutes.currentRouteObject?.settings)) {
      unawaited(_communityNavigator.currentState?.pushNamed<void>('/messages'));
    }
  }

  @override
  void dispose() {
    _sidebarRoutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LocaleScope(
    notifier: locale,
    child: AnimatedBuilder(
      animation: Listenable.merge([locale, user]),
      builder: (context, _) => MaterialApp(
        key: _navigationKey(),
        navigatorKey: _communityNavigator,
        navigatorObservers: [_routes, _sidebarRoutes],
        title: '窗后城',
        debugShowCheckedModeBanner: false,
        theme: communityWebTheme(),
        locale: locale.locale,
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        builder: (context, child) => AuthScope(
          currentUser: user,
          child: AnimatedBuilder(
            animation: _sidebarRoutes,
            child: child,
            builder: (context, navigator) => CommunityNavigationFrame(
              controller: _navigationController,
              visible: communitySidebarVisible(
                _entryUri,
                _sidebarRoutes.currentRoute,
              ),
              selectedDestination: communitySidebarDestination(
                _entryUri,
                _sidebarRoutes.currentRoute,
                ownerId: user.signedInUser?.id.rawValue,
              ),
              onHome: () => unawaited(_exitDocument(exitPublicWork)),
              onFollowing: () =>
                  unawaited(_exitDocument(openCommunityFollowing)),
              onMyProfile: _openMyProfile,
              onMessages: _openMessages,
              onSettings: () => unawaited(_exitDocument(openCommunitySettings)),
              onOpenFiling: () => unawaited(_exitDocument(openCommunityFiling)),
              child: navigator!,
            ),
          ),
        ),
        onGenerateRoute: (settings) =>
            communityFavoritesRoute(settings, user) ??
            communityMessagingRoute(settings, user) ??
            communityAccountRoute(settings, user),
        home: AnimatedBuilder(
          animation: user,
          builder: (context, _) {
            final state = user.state;
            final query = (widget.entryUri ?? Uri.base).queryParameters;
            final mobileFeed = query['feed'] == '1';
            if (!mobileFeed &&
                !query.containsKey('profile') &&
                !query.containsKey('work') &&
                query['publish'] != '1' &&
                !query.containsKey('auth')) {
              return _WebsiteHomeEntry(routes: _routes, onExit: widget.onExit);
            }
            // Public profiles use the existing mobile page for guests and
            // members, once the shared backend initialization has completed.
            if ((state is CurrentUserSignedIn ||
                    state is CurrentUserSignedOut) &&
                query.containsKey('profile')) {
              return PublicProfileEntry(user: user);
            }
            return switch (state) {
              CurrentUserSignedIn() =>
                query.containsKey('work')
                    ? PublicWorkEntry(user: user)
                    : query['publish'] == '1'
                    ? const _WebPublicationEntry()
                    : mobileFeed
                    ? _mobileCommunityFeed()
                    : _WebsiteHomeEntry(
                        routes: _routes,
                        onExit: widget.onExit,
                        completeAuthentication: query.containsKey('auth'),
                      ),
              CurrentUserSignedOut() =>
                query.containsKey('work')
                    ? PublicWorkEntry(user: user)
                    : mobileFeed &&
                          !query.containsKey('auth') &&
                          query['publish'] != '1'
                    ? _mobileCommunityFeed()
                    : AuthRootView(
                        currentUser: user,
                        initialSignUp: query['auth'] == 'signup',
                      ),
              CurrentUserServiceUnavailable(:final reason) =>
                CommunityServiceUnavailableView(
                  currentUser: user,
                  reason: reason,
                ),
              _ =>
                query.containsKey('work')
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

Widget _mobileCommunityFeed() => VaultPage(
  activities: const [
    TopicActivity(
      title: '瓷影｜器物与日常',
      image: NetworkImage(
        'https://kongye.space/assets/events/porcelain-ink.png',
      ),
    ),
    TopicActivity(
      title: '云栖山庄',
      image: NetworkImage(
        'https://kongye.space/assets/events/landscape-ink.png',
      ),
    ),
    TopicActivity(
      title: '水墨庭院',
      image: NetworkImage(
        'https://kongye.space/assets/events/courtyard-ink.png',
      ),
    ),
  ],
  onActivityTap: (index) => openCommunityActivity(index + 1),
);

/// The website owns the homepage. This blank route is only a return target
/// beneath direct-linked Flutter pages, never a second community feed.
class _WebsiteHomeEntry extends StatefulWidget {
  const _WebsiteHomeEntry({
    required this.routes,
    required this.onExit,
    this.completeAuthentication = false,
  });
  final RouteObserver<ModalRoute<void>> routes;
  final VoidCallback onExit;
  final bool completeAuthentication;

  @override
  State<_WebsiteHomeEntry> createState() => _WebsiteHomeEntryState();
}

class _WebsiteHomeEntryState extends State<_WebsiteHomeEntry> with RouteAware {
  bool _exited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (route != null) widget.routes.subscribe(this, route);
  }

  @override
  void didPush() => _returnHome();

  @override
  void didPopNext() => _returnHome();

  void _returnHome() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _exited) return;
      // Standalone signup/reset forms may still cover a successful auth entry.
      // Replacing the document also closes those authentication routes.
      if (!widget.completeAuthentication &&
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      _exited = true;
      widget.onExit();
    });
  }

  @override
  void dispose() {
    widget.routes.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
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
    await Navigator.of(context).pushNamed<void>('/publish');
    if (mounted) exitPublicWork();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
}
