// Auth state observed by views. Account attachment finishes before signed-in
// UI is published. Generation checks prevent stale results restoring accounts.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../aether_prefs.dart';
import '../analytics/pw_analytics.dart';
import '../config/backend_deployment.dart';
import '../util/device_log.dart';
import 'auth_error.dart';
import 'auth_models.dart';
import 'auth_service.dart';
import 'connection_backoff.dart';
import 'unavailable_auth_service.dart';

sealed class CurrentUserState {
  const CurrentUserState();
}

class CurrentUserBootstrapping extends CurrentUserState {
  const CurrentUserBootstrapping();
}

class CurrentUserSignedIn extends CurrentUserState {
  final AuthenticatedUser user;
  const CurrentUserSignedIn(this.user);
}

class CurrentUserSignedOut extends CurrentUserState {
  const CurrentUserSignedOut();
}

/// 登录后端不可用(初始化失败/超时/网络不通)。**不是** signedOut:登录页
/// 不能出现,否则用户会往一个假服务里输真密码(2026-09-07 未命名(18) 事故)。
/// UI 显示失败原因与"重试";重试走 [CurrentUser.retryServiceInit]。
class CurrentUserServiceUnavailable extends CurrentUserState {
  final String reason;
  const CurrentUserServiceUnavailable(this.reason);
}

class CurrentUser extends ChangeNotifier {
  static const Duration idleSignOutInterval = Duration(days: 30);

  CurrentUser({
    required AuthService service,
    BackendDeployment? deployment,
    ConnectionBackoff? initBackoff,
    Future<void> Function(AuthenticatedUser?)? onIdentityChanged,
    void Function()? onIdentityInvalidated,
  }) : _service = service,
       deployment = deployment ?? BackendDeployment.fromBuild(),
       initBackoff = initBackoff ?? ConnectionBackoff(),
       _onIdentityChanged = onIdentityChanged,
       _onIdentityInvalidated = onIdentityInvalidated;

  AuthService _service;
  final BackendDeployment deployment;
  final Future<void> Function(AuthenticatedUser?)? _onIdentityChanged;
  final void Function()? _onIdentityInvalidated;
  CurrentUserState _state = const CurrentUserBootstrapping();
  AuthException? _lastError;
  bool _isPerformingAuthAction = false;
  int _generation = 0;
  // Metadata edits and OTP resends can supersede UI state without revoking
  // the identity established by an otherwise successful login.
  int _identityIntent = 0;
  bool _disposed = false;
  bool _providerRevocationInProgress = false;
  int? _accountDeletionGeneration;
  bool _identityKnown = false;
  InternalUserID? _attachedUserID;

  // Keep provider session mutations in request order: an earlier login must
  // never recreate a session after the later logout has cleared it.
  Future<void> _providerTail = Future<void>.value();
  // Serialize storage attachment and preference writes independently so logout
  // can detach the app while a provider request is still waiting on a network.
  Future<void> _identityTail = Future<void>.value();

  /// main() 挂上的"重新初始化登录后端"动作(解析后端地址 → Supabase.initialize
  /// → 会话恢复 → swapService → bootstrap)。UI 的"重试"按钮和自动重连都只调这个。
  Future<void> Function()? retryInit;
  bool _retryingInit = false;
  bool get isRetryingInit => _retryingInit;

  /// 自动重连退避:抄 gRPC 连接退避协议(1 s ×1.6、±20% 抖动、封顶 120 s、
  /// 成功即复位;B 站 kratos 同参),见 connection_backoff.dart。网络级重试
  /// gotrue 自己做;这里管"后端初始化整体失败"之后的自动再试——大厂 SDK 的
  /// 通用做法(腾讯 IM / 火山 RTC / 微信 Mars 都是断线后 SDK 自动重连,只有
  /// 服务器明确判票据失效/被踢才要用户重新登录)。
  final ConnectionBackoff initBackoff;
  Timer? _autoRetryTimer;
  DateTime? _nextAutoRetryAt;

  /// 下一次自动重试的时刻(不可用态且已排期时非空;供 UI 显示)。
  DateTime? get nextAutoRetryAt => _nextAutoRetryAt;

  /// [manual] = 用户点了"重试":走一次引导态让闪屏文案动起来;自动重连保持
  /// 不可用态静默进行,只把按钮置灰,避免每次退避都闪一下。
  Future<void> retryServiceInit({bool manual = true}) async {
    final r = retryInit;
    if (r == null || _retryingInit || _disposed) return;
    _cancelAutoRetry();
    _retryingInit = true;
    if (manual) _state = const CurrentUserBootstrapping();
    notifyListeners();
    try {
      await r();
    } finally {
      _retryingInit = false;
      if (!_disposed && _state is! CurrentUserServiceUnavailable) {
        // 成功(到了 signedIn/signedOut):复位退避——gRPC 的"连接被接受即复位"。
        initBackoff.reset();
      }
      if (!_disposed) notifyListeners();
    }
  }

  /// 登录后端不可用:进入显式失败态(带原因),绝不用假服务顶替;并按退避
  /// 排下一次自动重试。
  void markServiceUnavailable(String reason) {
    if (_disposed) return;
    _identityIntent++;
    final generation = ++_generation;
    _isPerformingAuthAction = false;
    _onIdentityInvalidated?.call();
    DeviceLog.log('CurrentUser', '→ ServiceUnavailable ($reason)');
    _state = CurrentUserServiceUnavailable(reason);
    unawaited(
      _detachIdentity(generation).catchError((Object error) {
        if (_isCurrent(generation)) _recordError(error);
      }),
    );
    _scheduleAutoRetry();
    notifyListeners();
  }

  void _scheduleAutoRetry() {
    _cancelAutoRetry();
    if (retryInit == null) return;
    final delay = initBackoff.next();
    _nextAutoRetryAt = DateTime.now().add(delay);
    DeviceLog.log(
      'CurrentUser',
      'auto-retry #${initBackoff.failures} in ${delay.inMilliseconds} ms',
    );
    _autoRetryTimer = Timer(delay, () {
      _autoRetryTimer = null;
      _nextAutoRetryAt = null;
      unawaited(retryServiceInit(manual: false));
    });
  }

  void _cancelAutoRetry() {
    _autoRetryTimer?.cancel();
    _autoRetryTimer = null;
    _nextAutoRetryAt = null;
  }

  CurrentUserState get state => _state;
  AuthException? get lastError => _lastError;
  bool get isPerformingAuthAction => _isPerformingAuthAction;
  bool get isSignedIn => _state is CurrentUserSignedIn;
  AuthenticatedUser? get signedInUser => switch (_state) {
    CurrentUserSignedIn(:final user) => user,
    _ => null,
  };

  void swapService(AuthService newService) {
    if (_disposed) return;
    _identityIntent++;
    final generation = ++_generation;
    _onIdentityInvalidated?.call();
    _isPerformingAuthAction = false;
    if (_state is CurrentUserSignedIn) {
      _state = const CurrentUserBootstrapping();
    }
    _service = newService;
    unawaited(
      _detachIdentity(generation).catchError((Object error) {
        if (_isCurrent(generation)) _recordError(error);
      }),
    );
  }

  void clearLastError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  Future<void> bootstrap() async {
    final generation = _beginAction(performing: false);
    unawaited(
      PwAnalytics.instance.init().then((_) {
        PwAnalytics.instance.installErrorHandlers();
      }),
    );
    if (_service is UnavailableAuthService) {
      markServiceUnavailable(
        'bootstrap: ${(_service as UnavailableAuthService).reason}',
      );
      await _identityTail;
      return;
    }
    try {
      // Wait for session mutation/cleanup, without queueing the cached read
      // itself: logout must remain able to cancel a slow read.
      await _providerTail;
      if (!_isCurrent(generation)) return;
      final user = await _service.currentUser();
      if (!_isCurrent(generation)) return;
      if (user == null) {
        _publishSignedOut('bootstrap: no session');
        await _detachIdentity(generation);
        return;
      }
      final idleExpired = await _isIdleExpired();
      if (!_isCurrent(generation)) return;
      if (idleExpired) {
        await signOut();
        return;
      }
      await _acceptIdentity(generation, user);
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _publishSignedOut('bootstrap failed');
      await _detachIdentity(generation);
      if (_isCurrent(generation)) _recordError(error);
    } finally {
      _finishAction(generation);
    }
  }

  Future<void> refreshIdleSession() async {
    if (!isSignedIn) return;
    final generation = _generation;
    final expired = await _isIdleExpired();
    if (!_isCurrent(generation)) return;
    if (expired) {
      await signOut();
    } else {
      await _queueIdentity(() async {
        if (_isCurrent(generation)) await _touchIdleTimestamp();
      });
    }
  }

  Future<void> signIn(SignInRequest request) async {
    await _runUserAction((service) => service.signIn(request));
  }

  Future<void> signUp(SignUpRequest request) async {
    await _runUserAction(
      (service) => service.signUp(request),
      rethrowVerificationPending: true,
    );
  }

  Future<bool> verifySignupOtp({
    required String email,
    required String token,
  }) => _runUserAction(
    (service) => service.verifyEmailSignupOtp(email: email, token: token),
  );

  Future<bool> resendSignupOtp({required String email}) async =>
      await _runValueAction((service) async {
        await service.resendEmailOtp(email: email);
        return true;
      }) ??
      false;

  Future<PhoneVerificationChallenge?> startPhoneVerification(String phone) =>
      _runValueAction((service) => service.startPhoneVerification(phone));

  Future<bool> sendPasswordReset(String email) async =>
      await _runValueAction((service) async {
        await service.sendPasswordReset(email);
        return true;
      }) ??
      false;

  Future<String?> verifyPasswordResetCode({
    required String email,
    required String token,
  }) => _runValueAction(
    (service) => service.verifyPasswordResetCode(email: email, token: token),
  );

  Future<bool> completePasswordReset({
    required String email,
    required String resetToken,
    required String newPassword,
  }) async {
    final generation = _beginAction();
    if (!_isCurrent(generation)) return false;
    try {
      await _queueProvider((service) async {
        await service.completePasswordReset(
          email: email,
          resetToken: resetToken,
          newPassword: newPassword,
        );
        // Reserve local revocation before any newer explicit sign-in queued
        // behind this operation. Recovery itself must never accept an identity.
        await _revokeProviderSession(service);
      });
      if (!_isCurrent(generation)) return false;
      _publishSignedOut('password reset completed', performing: true);
      if (!_isCurrent(generation)) return false;
      await _detachIdentity(generation);
      return _isCurrent(generation);
    } catch (error) {
      if (_isCurrent(generation)) _recordError(error);
      return false;
    } finally {
      _finishAction(generation);
    }
  }

  Future<void> signOut() async {
    _identityIntent++;
    final generation = _beginAction(performing: false, notify: false);
    // A listener can synchronously request another login. Reserve the logout's
    // provider position before publishing any notification it could observe.
    final providerLogout = _queueProvider(_revokeProviderSession);
    _publishSignedOut('signOut');
    try {
      await _detachIdentity(generation);
    } finally {
      await providerLogout;
    }
  }

  /// Revoke local access for provider events without calling signOut again.
  Future<void> handleProviderSignedOut() async {
    if (_providerRevocationInProgress || _disposed) return;
    if (_service is UnavailableAuthService &&
        _state is! CurrentUserServiceUnavailable) {
      markServiceUnavailable(
        'provider signed out: ${(_service as UnavailableAuthService).reason}',
      );
      await _identityTail;
      return;
    }
    _identityIntent++;
    // A deletion never establishes an identity. Keep only that operation's
    // completion valid while still revoking access immediately, including when
    // its provider emits signedOut after an accepted erasure request.
    final generation = _accountDeletionGeneration == _generation
        ? _generation
        : _beginAction(performing: false, notify: false);
    if (_state is CurrentUserServiceUnavailable) {
      // Provider revocation removes local access, but does not make an
      // unavailable backend ready to accept credentials or reset its backoff.
      _onIdentityInvalidated?.call();
      notifyListeners();
    } else {
      _publishSignedOut('provider signed out');
    }
    await _detachIdentity(generation);
  }

  /// Requests account erasure and detaches local access after acceptance.
  /// True means this request was accepted and remains current, not that
  /// physical account or object cleanup has completed.
  Future<bool> deleteAccount() async {
    _identityIntent++;
    final generation = _beginAction();
    if (!_isCurrent(generation)) return false;
    _accountDeletionGeneration = generation;
    try {
      // The network request may fail or receive an independent revocation.
      // Never suppress provider events while waiting for request acceptance.
      await _queueProvider((service) => service.deleteAccount());
      if (!_isCurrent(generation)) return false;
      _publishSignedOut('account erasure request accepted');
      await _detachIdentity(generation);
      return _isCurrent(generation);
    } catch (error) {
      if (_isCurrent(generation)) _recordError(error);
      return false;
    } finally {
      if (_accountDeletionGeneration == generation) {
        _accountDeletionGeneration = null;
      }
      _finishAction(generation);
    }
  }

  Future<bool> updateDisplayName(String displayName) async {
    if (signedInUser == null) return false;
    // Identity is deduplicated by ID, so metadata updates keep the same store.
    return _runUserAction(
      (service) => service.updateDisplayName(displayName),
      createsSession: false,
    );
  }

  Future<bool> updateHandle(String handle) async {
    if (signedInUser == null) return false;
    return await _runValueAction((service) async {
          await service.updateHandle(handle);
          return true;
        }) ??
        false;
  }

  Future<bool> _runUserAction(
    Future<AuthenticatedUser> Function(AuthService) action, {
    bool rethrowVerificationPending = false,
    bool createsSession = true,
  }) async {
    final identityIntent = createsSession ? ++_identityIntent : _identityIntent;
    final generation = _beginAction(notify: false);
    if (createsSession && (_attachedUserID != null || isSignedIn)) {
      _publishSignedOut('replacement authentication', performing: true);
      unawaited(
        _detachIdentity(generation).catchError((Object error) {
          if (_isCurrent(generation)) _recordError(error);
        }),
      );
    } else {
      // The previous hook may still be preparing its workspace before an
      // attached identity exists. Revoke it before starting a new session.
      if (createsSession) _onIdentityInvalidated?.call();
      notifyListeners();
    }
    if (!_isCurrent(generation)) return false;
    try {
      final user = await _queueProvider((service) async {
        try {
          return await action(service);
        } finally {
          if (createsSession && identityIntent != _identityIntent) {
            // The SDK may persist before a later step throws (for example a
            // phone signup's metadata update). Clean both outcomes before the
            // next queued login, without canceling that newer login's intent.
            await _discardCanceledSession(service);
          }
        }
      });
      if (!_isCurrent(generation)) return false;
      return await _acceptIdentity(generation, user);
    } on EmailVerificationPending {
      if (_isCurrent(generation) && rethrowVerificationPending) rethrow;
      return false;
    } catch (error) {
      if (_isCurrent(generation)) _recordError(error);
      return false;
    } finally {
      _finishAction(generation);
    }
  }

  Future<T?> _runValueAction<T>(Future<T> Function(AuthService) action) async {
    final generation = _beginAction();
    if (!_isCurrent(generation)) return null;
    try {
      final value = await _queueProvider(action);
      return _isCurrent(generation) ? value : null;
    } catch (error) {
      if (_isCurrent(generation)) _recordError(error);
      return null;
    } finally {
      _finishAction(generation);
    }
  }

  int _beginAction({bool performing = true, bool notify = true}) {
    final generation = ++_generation;
    _isPerformingAuthAction = performing;
    _lastError = null;
    if (notify) notifyListeners();
    return generation;
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _finishAction(int generation) {
    if (!_isCurrent(generation)) return;
    _isPerformingAuthAction = false;
    notifyListeners();
  }

  void _recordError(Object error) {
    _lastError = error is AuthException
        ? error
        : AuthException(AuthErrorKind.unknown, error.toString());
  }

  void _publishSignedOut(String reason, {bool performing = false}) {
    _onIdentityInvalidated?.call();
    DeviceLog.log('CurrentUser', '→ SignedOut ($reason)');
    _state = const CurrentUserSignedOut();
    _lastError = null;
    _isPerformingAuthAction = performing;
    notifyListeners();
  }

  Future<void> _discardCanceledSession(AuthService service) async {
    try {
      if (!_disposed) {
        // The old local account is no longer backed by a provider session.
        // Keep a newer action's generation/spinner intact so it can complete.
        if (_state is CurrentUserServiceUnavailable) {
          _onIdentityInvalidated?.call();
        } else {
          _publishSignedOut(
            'canceled authentication',
            performing: _isPerformingAuthAction,
          );
        }
        await _detachIdentity(_generation);
      }
    } finally {
      await _revokeProviderSession(service);
    }
  }

  Future<void> _revokeProviderSession(AuthService service) async {
    _providerRevocationInProgress = true;
    try {
      await service.signOut();
    } catch (_) {
      // The pinned provider clears local session state before network I/O.
    } finally {
      _providerRevocationInProgress = false;
    }
  }

  Future<T> _queueProvider<T>(Future<T> Function(AuthService) action) {
    final service = _service;
    final result = _providerTail.then((_) => action(service));
    _providerTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<T> _queueIdentity<T>(Future<T> Function() action) {
    final result = _identityTail.then((_) => action());
    _identityTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<bool> _acceptIdentity(int generation, AuthenticatedUser user) =>
      _queueIdentity(() async {
        if (!_isCurrent(generation)) return false;
        if (!_identityKnown || _attachedUserID != user.id) {
          try {
            _onIdentityInvalidated?.call();
            if (!_isCurrent(generation)) return false;
            _state = const CurrentUserBootstrapping();
            notifyListeners();
            if (!_isCurrent(generation)) return false;
            await _onIdentityChanged?.call(user);
            _attachedUserID = user.id;
            _identityKnown = true;
          } catch (error) {
            // A hook may partially attach before it fails. Detach before
            // returning an error, and never show signed-in UI for that account.
            _identityKnown = false;
            if (_isCurrent(generation)) {
              if (error is AuthException &&
                  error.kind == AuthErrorKind.providerUnavailable) {
                // Retry an unavailable workspace with the retained provider
                // session instead of presenting a fresh credentials form.
                markServiceUnavailable(error.detail ?? error.message);
              } else {
                _publishSignedOut('identity setup failed');
              }
            }
            try {
              await _onIdentityChanged?.call(null);
              _attachedUserID = null;
              _identityKnown = true;
            } finally {
              await _clearPersistedIdentity();
            }
            rethrow;
          }
        }
        if (!_isCurrent(generation)) return false;
        await _touchIdleTimestamp();
        if (!_isCurrent(generation)) return false;
        final prefs = await AetherPrefs.getInstance();
        if (!_isCurrent(generation)) return false;
        await prefs.setString(
          AuthPersistenceKeys.currentUserIDFor(deployment),
          user.id.rawValue,
        );
        if (!_isCurrent(generation)) return false;
        _state = CurrentUserSignedIn(user);
        return true;
      });

  Future<void> _detachIdentity(int generation) => _queueIdentity(() async {
    try {
      if (!_identityKnown || _attachedUserID != null) {
        await _onIdentityChanged?.call(null);
        _attachedUserID = null;
        _identityKnown = true;
      }
    } finally {
      await _clearPersistedIdentity();
    }
  });

  Future<bool> _isIdleExpired() async {
    final prefs = await AetherPrefs.getInstance();
    final lastMs =
        await prefs.getInt(AuthPersistenceKeys.lastActivityAtFor(deployment)) ??
        0;
    return lastMs > 0 &&
        DateTime.now().millisecondsSinceEpoch - lastMs >
            idleSignOutInterval.inMilliseconds;
  }

  Future<void> _touchIdleTimestamp() async {
    final prefs = await AetherPrefs.getInstance();
    await prefs.setInt(
      AuthPersistenceKeys.lastActivityAtFor(deployment),
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _clearPersistedIdentity() async {
    final prefs = await AetherPrefs.getInstance();
    await prefs.remove(AuthPersistenceKeys.currentUserIDFor(deployment));
    await prefs.remove(AuthPersistenceKeys.lastActivityAtFor(deployment));
  }

  static Future<String?> readPersistedUserID({
    BackendDeployment? deployment,
  }) async {
    final prefs = await AetherPrefs.getInstance();
    return prefs.getString(
      AuthPersistenceKeys.currentUserIDFor(
        deployment ?? BackendDeployment.fromBuild(),
      ),
    );
  }

  @override
  void dispose() {
    _cancelAutoRetry();
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
