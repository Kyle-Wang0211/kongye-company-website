// Supabase implementation of the lib/auth/AuthService contract.
// Replaces the Firebase implementation 2026-04-28. UI layer doesn't
// change — it still talks to AuthService through the sealed
// SignInRequest / SignUpRequest types.
//
// Wiring:
//   • Supabase.initialize(url, anonKey) called once in main.dart before
//     anything else.
//   • CurrentUser holds an instance of this and dispatches to it.
//   • Phone OTP is wired through Supabase's signInWithOtp (channel:sms).
//
// Errors: every failure path maps to AuthException with a typed
// AuthErrorKind. The detail string stays in English (Supabase's
// upstream message) — UI shows the localized message from
// AuthException.message.

// Hide Supabase's own AuthException so our app-level AuthException is
// the only one that compiles into call sites. We catch the underlying
// Supabase errors via AuthApiException (still imported below) and
// re-throw as the app type with a typed AuthErrorKind.
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import '../i18n/locale_notifier.dart';
import 'auth_error.dart';
import 'auth_models.dart';
import 'auth_service.dart';

class SupabaseAuthServiceImpl implements AuthService {
  final SupabaseClient _client;
  final bool _nativeEmailReady;
  // When wired through main.dart, signUp passes the user's current UI
  // locale ('zh' or 'en') in user_metadata.locale so the Supabase email
  // template can branch on `{{ if eq .Data.locale "zh" }}`. Optional so
  // tests can construct without one.
  final LocaleNotifier? _localeNotifier;

  SupabaseAuthServiceImpl({
    SupabaseClient? client,
    LocaleNotifier? localeNotifier,
    bool nativeEmailReady = const bool.fromEnvironment(
      'PW_NATIVE_EMAIL_SMTP_READY',
      defaultValue: false,
    ),
  }) : _client = client ?? Supabase.instance.client,
       _localeNotifier = localeNotifier,
       _nativeEmailReady = nativeEmailReady;

  @override
  Future<AuthenticatedUser?> currentUser() async {
    final session = _client.auth.currentSession;
    // A cached token awaiting recovery is not proof of an active session. Keep
    // the cache intact so a later recovery can still succeed while offline.
    if (session == null || session.isExpired) return null;
    return _hydrateProfile(session.user);
  }

  @override
  Future<AuthenticatedUser> signIn(SignInRequest request) async {
    try {
      switch (request) {
        case SignInRequestEmail(email: final email, password: final pw):
          final res = await _signInWithPasswordWithWarmRetry(
            email: email,
            password: pw,
          );
          final user = res.user;
          if (user == null) {
            throw const AuthException(AuthErrorKind.invalidCredentials);
          }
          return await _hydrateProfile(user);

        case SignInRequestPhonePassword(
          phoneNumber: final phone,
          password: final pw,
        ):
          final res = await _signInWithPasswordWithWarmRetry(
            phone: phone,
            password: pw,
          );
          final user = res.user;
          if (user == null) {
            throw const AuthException(AuthErrorKind.invalidCredentials);
          }
          return await _hydrateProfile(user);

        case SignInRequestPhone(phoneNumber: final phone, code: final code):
          final res = await _client.auth.verifyOTP(
            phone: phone,
            token: code,
            type: OtpType.sms,
          );
          final user = res.user;
          if (user == null) {
            throw const AuthException(AuthErrorKind.invalidVerificationCode);
          }
          return await _hydrateProfile(user);
      }
    } on AuthRetryableFetchException catch (e) {
      throw AuthException(AuthErrorKind.network, e.message);
    } on AuthApiException catch (e) {
      throw AuthException(_mapAuthApi(e), e.message);
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(AuthErrorKind.unknown, e.toString());
    }
  }

  Future<AuthResponse> _signInWithPasswordWithWarmRetry({
    String? email,
    String? phone,
    required String password,
  }) async {
    assert((email == null) != (phone == null));
    try {
      return await _client.auth.signInWithPassword(
        email: email,
        phone: phone,
        password: password,
      );
    } on AuthRetryableFetchException catch (e) {
      debugPrint(
        '[SupabaseAuthService] first signInWithPassword fetch failed; '
        'retrying once: ${e.message}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      return _client.auth.signInWithPassword(
        email: email,
        phone: phone,
        password: password,
      );
    }
  }

  @override
  Future<AuthenticatedUser> signUp(SignUpRequest request) async {
    try {
      switch (request) {
        case SignUpRequestEmail(
          email: final email,
          password: final pw,
          displayName: final name,
        ):
          _requireNativeEmail();
          if (pw.length < 8) {
            throw const AuthException(AuthErrorKind.weakPassword);
          }
          final res = await _client.auth.signUp(
            email: email,
            password: pw,
            data: {
              'display_name': ?name,
              'locale': _localeNotifier?.locale.languageCode ?? 'en',
            },
          );
          if (res.session == null) throw EmailVerificationPending(email);
          final user = res.user;
          if (user == null) {
            throw const AuthException(AuthErrorKind.invalidCredentials);
          }
          return await _hydrateProfile(user);

        case SignUpRequestPhone(
          phoneNumber: final phone,
          code: final code,
          password: final password,
          displayName: final name,
        ):
          if (password.length < 8) {
            throw const AuthException(AuthErrorKind.weakPassword);
          }
          // startPhoneSignup supplied the password before sending this SMS.
          // Verification uses that pending signup; no password mutation follows.
          final res = await _client.auth.verifyOTP(
            phone: phone,
            token: code,
            type: OtpType.sms,
          );
          final user = res.user;
          if (user == null) {
            throw const AuthException(AuthErrorKind.invalidVerificationCode);
          }
          if (name != null) {
            // Metadata changes no longer sync into profiles. Persist through
            // the same authenticated, validated endpoint used for renaming.
            _requireCurrentIdentity(user);
            return await _updateDisplayName(user, name);
          }
          return await _hydrateProfile(user);
      }
    } on AuthRetryableFetchException catch (e) {
      throw AuthException(AuthErrorKind.network, e.message);
    } on AuthWeakPasswordException catch (e) {
      throw AuthException(AuthErrorKind.weakPassword, e.message);
    } on AuthApiException catch (e) {
      throw AuthException(_mapAuthApi(e), e.message);
    } on AuthException {
      rethrow;
    } on EmailVerificationPending {
      rethrow;
    } catch (e) {
      throw AuthException(AuthErrorKind.unknown, e.toString());
    }
  }

  @override
  Future<PhoneVerificationChallenge> startPhoneVerification(
    String phoneNumber, {
    bool forSignUp = false,
  }) async {
    try {
      if (forSignUp) {
        throw const AuthException(AuthErrorKind.providerUnavailable);
      }
      await _client.auth.signInWithOtp(
        phone: phoneNumber,
        shouldCreateUser: false,
      );
      return PhoneVerificationChallenge(
        // Supabase does not return a server-side verification ID; the
        // pair (phone, code) is enough for verifyOTP. Pass the phone
        // back as the handle so callers can keep the same shape as
        // Firebase did.
        verificationID: phoneNumber,
        phoneNumber: phoneNumber,
      );
    } on AuthApiException catch (e) {
      throw AuthException(_mapAuthApi(e), e.message);
    } catch (e) {
      throw AuthException(AuthErrorKind.unknown, e.toString());
    }
  }

  @override
  Future<PhoneVerificationChallenge> startPhoneSignup({
    required String phoneNumber,
    required String password,
    String? displayName,
  }) async {
    if (password.length < 8) {
      throw const AuthException(AuthErrorKind.weakPassword);
    }
    try {
      await _client.auth.signUp(
        phone: phoneNumber,
        password: password,
        data: {
          'display_name': ?displayName,
          'locale': _localeNotifier?.locale.languageCode ?? 'en',
        },
        channel: OtpChannel.sms,
      );
      return PhoneVerificationChallenge(
        verificationID: phoneNumber,
        phoneNumber: phoneNumber,
      );
    } on AuthApiException catch (e) {
      throw AuthException(_mapAuthApi(e), e.message);
    } catch (_) {
      throw const AuthException(AuthErrorKind.network);
    }
  }

  @override
  Future<void> sendEmailVerification() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException(AuthErrorKind.notSignedIn);
    }
    final email = user.email;
    if (email == null) {
      throw const AuthException(
        AuthErrorKind.unknown,
        'User has no email on file',
      );
    }
    _requireNativeEmail();
    try {
      await _client.auth.resend(type: OtpType.signup, email: email);
    } on AuthApiException catch (e) {
      throw AuthException(_mapAuthApi(e), e.message);
    } catch (e) {
      throw AuthException(AuthErrorKind.unknown, e.toString());
    }
  }

  void _requireNativeEmail() {
    if (!_nativeEmailReady) {
      throw const AuthException(AuthErrorKind.providerUnavailable);
    }
  }

  @override
  Future<void> resendEmailOtp({required String email}) async {
    _requireNativeEmail();
    try {
      await _client.auth.resend(type: OtpType.signup, email: email);
    } on AuthRetryableFetchException catch (e) {
      throw AuthException(AuthErrorKind.network, e.message);
    } on AuthApiException catch (e) {
      throw AuthException(_mapAuthApi(e), e.message);
    } catch (e) {
      throw AuthException(AuthErrorKind.unknown, e.toString());
    }
  }

  @override
  Future<AuthenticatedUser> verifyEmailSignupOtp({
    required String email,
    required String token,
  }) async {
    _requireNativeEmail();
    try {
      final res = await _client.auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.email,
      );
      if (res.user == null || res.session == null) {
        throw const AuthException(AuthErrorKind.invalidVerificationCode);
      }
      return await _hydrateProfile(res.user!);
    } on AuthRetryableFetchException catch (e) {
      throw AuthException(AuthErrorKind.network, e.message);
    } on AuthApiException catch (e) {
      throw AuthException(_mapAuthApi(e), e.message);
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(AuthErrorKind.unknown, e.toString());
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    _requireNativeEmail();
    try {
      await _client.auth
          .resetPasswordForEmail(email.trim().toLowerCase())
          .timeout(const Duration(seconds: 30));
    } on AuthApiException catch (e) {
      throw AuthException(_mapAuthApi(e));
    } on TimeoutException {
      throw const AuthException(AuthErrorKind.network);
    } on http.ClientException {
      throw const AuthException(AuthErrorKind.network);
    } catch (e) {
      throw const AuthException(AuthErrorKind.providerUnavailable);
    }
  }

  @override
  Future<String> verifyPasswordResetCode({
    required String email,
    required String token,
  }) async {
    final data = await _invokePasswordRecovery('password-recovery-verify', {
      'email': email.trim().toLowerCase(),
      'otp': token,
    });
    final resetToken = data['reset_token'];
    if (resetToken is! String || resetToken.isEmpty) {
      throw const AuthException(AuthErrorKind.providerUnavailable);
    }
    return resetToken;
  }

  @override
  Future<void> completePasswordReset({
    required String email,
    required String resetToken,
    required String newPassword,
  }) async {
    await _invokePasswordRecovery('password-recovery-complete', {
      'email': email.trim().toLowerCase(),
      'reset_token': resetToken,
      'new_password': newPassword,
    }, completing: true);
  }

  Future<Map<dynamic, dynamic>> _invokePasswordRecovery(
    String function,
    Map<String, String> body, {
    bool completing = false,
  }) async {
    _requireNativeEmail();
    try {
      final response = await _client.functions
          .invoke(function, body: body)
          .timeout(const Duration(seconds: 30));
      final data = response.data;
      if (data is! Map || data['ok'] != true) {
        throw const AuthException(AuthErrorKind.providerUnavailable);
      }
      return data;
    } on FunctionException catch (e) {
      if (completing && (e.status == 401 || e.status == 410)) {
        throw const AuthException(AuthErrorKind.notSignedIn);
      }
      throw _mapFunctionException(e);
    } on AuthException {
      rethrow;
    } on TimeoutException {
      throw const AuthException(AuthErrorKind.network);
    } on http.ClientException {
      throw const AuthException(AuthErrorKind.network);
    } catch (_) {
      // Do not log server response bodies, recovery credentials or passwords.
      throw const AuthException(AuthErrorKind.providerUnavailable);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      // Pinned gotrue 2.20.0 removes the local session and emits signedOut
      // before its upstream request. Scope.local avoids revoking other devices.
      await _client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // Upstream failure occurs after local session removal in the pinned SDK.
    }
  }

  /// Requests account erasure and clears this local session on acceptance.
  /// A pending 202 receipt does not prove physical account or object removal.
  @override
  Future<void> deleteAccount() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException(AuthErrorKind.notSignedIn);
    }
    try {
      // The privileged delete-account function can complete synchronously (200)
      // or accept an asynchronous erasure request (202). A pending receipt must
      // match this requesting identity before local access is revoked.
      // confirm:true remains required, following the UI confirmation dialog.
      final res = await _client.functions.invoke(
        'delete-account',
        body: const {'confirm': true},
      );
      final data = res.data;
      final pendingRequestAccepted =
          res.status == 202 &&
          data is Map &&
          data.length == 4 &&
          data['ok'] == true &&
          data['account_erasure_status'] == 'requested' &&
          data['erasure_pending'] == true &&
          data['requested_user_id'] == user.id;
      if (res.status != 200 && !pendingRequestAccepted) {
        final code = data is Map ? data['error']?.toString() : null;
        throw AuthException(
          AuthErrorKind.providerUnavailable,
          'Account deletion failed (${res.status}${code == null ? '' : ': $code'}).',
        );
      }
      // Revoke only this local session after the request is accepted. A pending
      // receipt is not proof of completed cleanup. Provider logout remains
      // best-effort so it cannot turn acceptance into a reported failure.
      await signOut();
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(AuthErrorKind.unknown, e.toString());
    }
  }

  @override
  Future<AuthenticatedUser> updateDisplayName(String displayName) async {
    final current = _client.auth.currentUser;
    if (current == null) {
      throw const AuthException(AuthErrorKind.notSignedIn);
    }
    return _updateDisplayName(current, displayName);
  }

  Future<AuthenticatedUser> _updateDisplayName(
    User current,
    String displayName,
  ) async {
    _requireCurrentIdentity(current);
    final session = _client.auth.currentSession!;
    // [NAME-CHOKEPOINT 2026-08-23] 改名从"客户端直写"改为"只调 Edge Function"。
    //
    // 之前这里做两件事,两件都已经不成立:
    //   1. `auth.updateUser({display_name})` —— 写 auth.users.raw_user_meta_data。
    //      这条路 RLS 关不掉(是 Supabase Auth 的内置能力),原先靠迁移
    //      20260510000000 的 SECURITY DEFINER 触发器把它同步进 profiles,
    //      于是任何客户端都能绕过全部校验把任意字符串送进 feed 展示的那一列。
    //      迁移 20260823010000 已删掉那个触发器。
    //   2. `from('profiles').update({display_name})` —— 同一迁移加的列级守卫
    //      guard_profile_identity_columns 会对 authenticated 角色抛 42501。
    //      而旧代码把这一步的异常 catch 成 non-fatal 只 print 一行 ⇒ 用户会看到
    //      "改名成功"而 feed 纹丝不动。这正是必须同批替换掉它的原因。
    //
    // 现在唯一入口是 set-profile-name(service_role),它按固定顺序做:
    //   RFC 8266 enforce → 字素簇长度 → 保留词 → 改名冷却 → 写 profiles
    //   → 同步 auth metadata → 审计
    try {
      final res = await _client.functions.invoke(
        'set-profile-name',
        // Freeze the verified principal before any await. The shared SDK
        // client may switch accounts while preparing the HTTP request.
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
        body: <String, dynamic>{'display_name': displayName},
      );
      _requireCurrentIdentity(current);
      final data = res.data;
      if (data is! Map || data['ok'] != true || data.containsKey('error')) {
        throw const AuthException(AuthErrorKind.providerUnavailable);
      }
      final newName = data['display_name'];
      // An unchanged response can omit display_name. Only a canonical profile
      // read may fill it in; the raw request has not been normalized locally.
      if (newName is! String || newName.isEmpty) {
        return await _hydrateProfile(current, requireName: true);
      }
      return AuthenticatedUser(
        id: InternalUserID(current.id),
        email: current.email,
        phone: current.phone,
        displayName: newName,
      );
    } on FunctionException catch (e) {
      throw _mapSetProfileName(e);
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(AuthErrorKind.unknown, e.toString());
    }
  }

  @override
  Future<void> updateHandle(String handle) async {
    final current = _client.auth.currentUser;
    if (current == null) {
      throw const AuthException(AuthErrorKind.notSignedIn);
    }
    try {
      await _client.functions.invoke(
        'set-profile-name',
        body: <String, dynamic>{'handle': handle},
      );
    } on FunctionException catch (e) {
      throw _mapSetProfileName(e);
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(AuthErrorKind.unknown, e.toString());
    }
  }

  /// 把 set-profile-name 的非 2xx 响应翻译成 UI 能直接显示的话。
  ///
  /// UI 走的是 `l.meDisplayNameUpdateFailed(err)`,err 取自
  /// AuthException.message —— 所以这里的文案会原样出现在用户眼前。
  ///
  /// ⚠️ 文案暂时硬编码在这一层。正确的位置是 l10n,但 app_zh.arb /
  ///    app_en.arb 及其生成物当前有未提交改动(属于另一条工作线),
  ///    不能碰。等那条线落地后把这些串搬进 l10n。
  AuthException _mapSetProfileName(FunctionException e) {
    final d = e.details;
    final code = (d is Map ? d['error']?.toString() : null) ?? '';
    final reason = (d is Map ? d['reason']?.toString() : null) ?? '';
    switch (code) {
      case 'cooldown':
        final ms = (d is Map ? d['retry_after_ms'] : null);
        final days = ms is num ? (ms / 86400000).ceil() : 3;
        return AuthException(AuthErrorKind.rateLimited, '改名太频繁,请 $days 天后再试');
      case 'rate_limited':
        return const AuthException(AuthErrorKind.rateLimited, '操作过于频繁,请稍后再试');
      case 'reserved_name':
        final kind = (d is Map ? d['kind']?.toString() : null) ?? '';
        return AuthException(
          AuthErrorKind.unknown,
          kind == 'impersonation' ? '该名称可能被误认为官方身份' : '该名称需要进一步核验',
        );
      case 'invalid_display_name':
        return AuthException(AuthErrorKind.unknown, switch (reason) {
          'too_long' => '名字太长了',
          'empty_after_enforcement' => '名字不能为空',
          'control_character' ||
          'ignorable_character' ||
          'unassigned_or_surrogate' => '名字含有不可见或非法字符',
          _ => '名字格式不正确',
        });
      case 'invalid_handle':
        return AuthException(AuthErrorKind.unknown, switch (reason) {
          'too_short' => 'ID 太短了',
          'too_long' => 'ID 太长了',
          'bad_charset' => 'ID 只能用小写字母、数字、点和下划线',
          'bad_edge' => 'ID 不能以点或下划线开头/结尾',
          'repeated_punct' => 'ID 不能有连续的点或下划线',
          'looks_like_file' => 'ID 不能像文件名',
          _ => 'ID 格式不正确',
        });
      case 'handle_taken':
        return const AuthException(AuthErrorKind.unknown, '该 ID 已被使用');
      case 'profile_not_found':
        return const AuthException(AuthErrorKind.unknown, '找不到您的资料');
      default:
        return AuthException(
          AuthErrorKind.unknown,
          code.isEmpty ? 'http_${e.status}' : code,
        );
    }
  }

  // ─── helpers ─────────────────────────────────────────────────────

  void _requireCurrentIdentity(User user) {
    final session = _client.auth.currentSession;
    if (session == null || session.isExpired || session.user.id != user.id) {
      throw const AuthException(AuthErrorKind.notSignedIn);
    }
  }

  Future<AuthenticatedUser> _hydrateProfile(
    User user, {
    bool requireName = false,
  }) async {
    _requireCurrentIdentity(user);
    String? displayName;
    try {
      // Reuse the signed-in client's deployment and public projection. Never
      // transfer an account token or profile lookup to another backend.
      final table =
          Uri.parse(_client.rest.url).origin == 'https://api.kongye.space'
          ? 'community_author_profiles'
          : 'profiles';
      final row = await _client
          .from(table)
          .select('id, display_name')
          .eq('id', user.id)
          .maybeSingle();
      if (row == null ||
          row['id'] != user.id ||
          (row['display_name'] != null && row['display_name'] is! String)) {
        throw const AuthException(AuthErrorKind.unknown, 'Profile unavailable');
      }
      displayName = row['display_name'] as String?;
      if (requireName && (displayName == null || displayName.isEmpty)) {
        throw const AuthException(
          AuthErrorKind.unknown,
          'Profile name unavailable',
        );
      }
    } catch (_) {
      _requireCurrentIdentity(user);
      if (requireName) rethrow;
      // Keep session recovery usable offline. A failed profile read must not
      // clear authentication; a successful read always outranks metadata.
      return _wrap(user);
    }
    _requireCurrentIdentity(user);
    return AuthenticatedUser(
      id: InternalUserID(user.id),
      email: user.email,
      phone: user.phone,
      displayName: displayName,
    );
  }

  AuthenticatedUser _wrap(User user) {
    final meta = user.userMetadata ?? const {};
    final display =
        meta['display_name'] as String? ??
        meta['full_name'] as String? ??
        meta['name'] as String?;
    return AuthenticatedUser(
      id: InternalUserID(user.id),
      email: user.email,
      phone: user.phone,
      displayName: display,
    );
  }

  AuthException _mapFunctionException(FunctionException e) {
    final details = e.details;
    String code = '';
    if (details is Map) {
      code = (details['error']?.toString() ?? '').toLowerCase();
    } else if (details is String) {
      code = details.toLowerCase();
    }
    switch (e.status) {
      case 400:
        // password-reset-verify returns 400 weak_password for too-short
        // new passwords; other 400s are validation errors that should
        // never happen given client-side gating.
        if (code == 'weak_password') {
          return const AuthException(AuthErrorKind.weakPassword);
        }
        return AuthException(AuthErrorKind.unknown, 'bad_request: $code');
      case 401:
      case 404:
      case 410:
        // 401 = wrong code, 404 = no pending row (probably reaped),
        // 410 = expired. UI message ("验证码错误或已过期") covers all.
        return AuthException(AuthErrorKind.invalidVerificationCode, code);
      case 409:
        return const AuthException(AuthErrorKind.accountAlreadyExists);
      case 429:
        return const AuthException(AuthErrorKind.rateLimited);
      case 502:
      case 503:
        return AuthException(AuthErrorKind.providerUnavailable, code);
      default:
        return AuthException(
          AuthErrorKind.unknown,
          'edge function ${e.status}${code.isEmpty ? '' : ': $code'}',
        );
    }
  }

  AuthErrorKind _mapAuthApi(AuthApiException e) {
    final code = e.code?.toLowerCase() ?? '';
    final msg = e.message.toLowerCase();
    if (code.contains('invalid_credentials') ||
        msg.contains('invalid login') ||
        msg.contains('invalid password')) {
      return AuthErrorKind.invalidCredentials;
    }
    if (code.contains('user_already_exists') ||
        msg.contains('already registered') ||
        msg.contains('already exists')) {
      return AuthErrorKind.accountAlreadyExists;
    }
    if (code.contains('weak_password') || msg.contains('password')) {
      return AuthErrorKind.weakPassword;
    }
    if (code.contains('over_request_rate_limit') ||
        code.contains('over_email_send_rate_limit') ||
        msg.contains('rate limit') ||
        msg.contains('too many')) {
      return AuthErrorKind.rateLimited;
    }
    if (code.contains('otp') ||
        msg.contains('otp') ||
        msg.contains('expired') ||
        msg.contains('verification code')) {
      return AuthErrorKind.invalidVerificationCode;
    }
    if (code.contains('network') || msg.contains('network')) {
      return AuthErrorKind.network;
    }
    return AuthErrorKind.unknown;
  }
}
