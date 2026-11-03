// Community-only browser entry. Existing community/auth/viewer widgets are reused.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth/auth_scope.dart';
import 'ui/community/public_work_entry.dart';
import 'ui/community/public_profile_entry.dart';
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
  runApp(_CommunityWeb(user: user, locale: locale));
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

class _CommunityWeb extends StatelessWidget {
  const _CommunityWeb({required this.user, required this.locale});
  final CurrentUser user;
  final LocaleNotifier locale;
  @override
  Widget build(BuildContext context) => LocaleScope(
    notifier: locale,
    child: AnimatedBuilder(
      animation: locale,
      builder: (context, _) => MaterialApp(
        title: 'PocketWorld',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: AetherColors.primary),
          scaffoldBackgroundColor: AetherColors.bg,
          canvasColor: AetherColors.bg,
          useMaterial3: true,
        ),
        locale: locale.locale,
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        builder: (context, child) =>
            AuthScope(currentUser: user, child: child!),
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
                    : const VaultPage(),
              CurrentUserSignedOut() =>
                Uri.base.queryParameters.containsKey('work')
                    ? PublicWorkEntry(user: user)
                    : AuthRootView(currentUser: user, initialSignUp: Uri.base.queryParameters['auth'] == 'signup'),
              CurrentUserServiceUnavailable(:final reason) =>
                _ServiceUnavailableView(currentUser: user, reason: reason),
              _ => const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
            };
          },
        ),
      ),
    ),
  );
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
