// AuthRootView — the sign-in page (entry point of the auth stack).
//
// Visual direction (per Figma 2026-04-29 "Login (Ultra-Minimal)"):
//   • Single column on white. No tabs, no card chrome.
//   • Top bar: brand wordmark (centered) + 中/EN toggle (right). Root
//     page so no leading widget. Sign-up + reset-password sub-pages
//     get a back-chevron leading via AuthTopBarBack.
//   • Heading "登录 / SIGN IN" + subtitle "欢迎回来 / WELCOME BACK"
//     in upper third, lots of breathing room.
//   • Two underline-only inputs (label above, no border box).
//   • Primary CTA "登录 → / SIGN IN →" rendered as bold caps text.
//   • Secondary "注册 / SIGN UP" link → pushes EmailSignUpPage.
//   • Tertiary "忘记密码？/ FORGOT PASSWORD" link → pushes
//     ResetPasswordView.
//
// Design widgets live in auth_minimal_widgets.dart so the sign-up and
// reset-password pages share the same look-and-feel.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth/auth_error.dart';
import '../../auth/auth_models.dart';
import '../../auth/current_user.dart';
import '../../auth/password_sign_in.dart';
import '../../auth/phone_country_catalog.dart';
import '../../auth/phone_number_input.dart';
import '../../auth/wechat_sign_in.dart';
import '../../config/backend_deployment.dart';
import '../../l10n/app_localizations.dart';
import '../design_system.dart';
import 'auth_minimal_widgets.dart';
import 'auth_policy_consent.dart';
import 'email_sign_in_view.dart';
import 'phone_country_picker.dart';
import 'reset_password_view.dart';
import 'login_code_view.dart';

enum _LoginMethod { phone, email }

class AuthRootView extends StatefulWidget {
  final CurrentUser currentUser;
  final bool initialSignUp;

  const AuthRootView({
    super.key,
    required this.currentUser,
    this.initialSignUp = false,
  });

  @override
  State<AuthRootView> createState() => _AuthRootViewState();
}

class _AuthRootViewState extends State<AuthRootView> {
  final _phone = TextEditingController();
  final _email = TextEditingController();
  late _LoginMethod _method;
  PhoneCountry _country = phoneCountryForIso('CN');

  bool get _isPhone => _method == _LoginMethod.phone;
  TextEditingController get _account => _isPhone ? _phone : _email;
  final _password = TextEditingController();
  bool _passwordVisible = false;
  bool _codeLogin = false;
  bool _wechatWorking = false;

  bool _policyAccepted = false;
  String? _consentOwner;

  @override
  void initState() {
    super.initState();
    _method = widget.currentUser.deployment.region == BackendRegion.china
        ? _LoginMethod.phone
        : _LoginMethod.email;
    _consentOwner = widget.currentUser.signedInUser?.id.rawValue;
    widget.currentUser.addListener(_onUserChanged);
    if (widget.initialSignUp) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pushSignUp();
      });
    }
  }

  @override
  void didUpdateWidget(covariant AuthRootView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser != widget.currentUser) {
      oldWidget.currentUser.removeListener(_onUserChanged);
      widget.currentUser.addListener(_onUserChanged);
      _consentOwner = widget.currentUser.signedInUser?.id.rawValue;
      _policyAccepted = false;
    }
  }

  @override
  void dispose() {
    widget.currentUser.removeListener(_onUserChanged);
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _onUserChanged() {
    final owner = widget.currentUser.signedInUser?.id.rawValue;
    if (owner != _consentOwner) {
      _consentOwner = owner;
      _policyAccepted = false;
    }
    final err = widget.currentUser.lastError;
    if (err != null && mounted && ModalRoute.of(context)?.isCurrent != false) {
      _showErrorDialog(err);
    }
    if (mounted) setState(() {});
  }

  Future<void> _showErrorDialog(AuthException err) async {
    final message = err.message;
    widget.currentUser.clearLastError();
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: AetherColors.bgCanvas,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AetherRadii.lg),
        ),
        title: Text(
          AppL10n.of(context).authErrorDialogTitle,
          style: AetherTextStyles.h2,
        ),
        content: Text(message, style: AetherTextStyles.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: AetherColors.primary),
            child: Text(
              AppL10n.of(context).commonOk,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  SignInRequest? get _passwordRequest {
    final account = _isPhone
        ? normalizePhoneLogin(_phone.text, country: _country)
        : _email.text;
    if (account == null) return null;
    final request = passwordSignInRequest(
      account: account,
      password: _password.text,
      region: widget.currentUser.deployment.region,
    );
    return (_isPhone && request is SignInRequestPhonePassword) ||
            (!_isPhone && request is SignInRequestEmail)
        ? request
        : null;
  }

  bool get _canSubmit => _policyAccepted && _passwordRequest != null;

  Future<void> _selectCountry() async {
    final country = await showPhoneCountryPicker(context);
    if (country == null ||
        !mounted ||
        widget.currentUser.isPerformingAuthAction ||
        widget.currentUser.isSignedIn) {
      return;
    }
    setState(() {
      _country = country;
      _policyAccepted = false;
    });
  }

  Widget _methodOption(_LoginMethod method, String label, bool working) {
    final selected = _method == method;
    return Expanded(
      child: Semantics(
        selected: selected,
        child: TextButton(
          key: ValueKey('auth-method-${method.name}'),
          onPressed: working
              ? null
              : () => setState(() {
                  _method = method;
                  _codeLogin = false;
                  _policyAccepted = false;
                }),
          style: TextButton.styleFrom(
            foregroundColor: selected
                ? AetherColors.textPrimary
                : AetherColors.textTertiary,
            minimumSize: const Size(0, 48),
            shape: const RoundedRectangleBorder(),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected
                      ? AetherColors.textPrimary
                      : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }

  String? get _codeTarget =>
      _isPhone ? normalizePhoneLogin(_phone.text, country: _country) : null;
  void _openCodeLogin() {
    final target = _codeTarget;
    if (!_isPhone ||
        target == null ||
        widget.currentUser.isPerformingAuthAction ||
        widget.currentUser.isSignedIn) {
      return;
    }
    if (!_policyAccepted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            LoginCodeView(currentUser: widget.currentUser, target: target),
      ),
    );
  }

  Future<void> _submit() async {
    final request = _passwordRequest;
    if (!_policyAccepted ||
        request == null ||
        widget.currentUser.isPerformingAuthAction ||
        widget.currentUser.isSignedIn) {
      return;
    }
    await widget.currentUser.signIn(request);
    if (widget.currentUser.isSignedIn) TextInput.finishAutofillContext();
  }

  Future<void> _beginWechat() async {
    if (!_policyAccepted ||
        _wechatWorking ||
        widget.currentUser.isSignedIn ||
        widget.currentUser.isPerformingAuthAction) {
      return;
    }
    setState(() => _wechatWorking = true);
    final started = wechatSignInFlow.begin();
    if (mounted) setState(() => _wechatWorking = false);
    if (!started && mounted) {
      await _showErrorDialog(
        const AuthException(AuthErrorKind.providerUnavailable),
      );
    }
  }

  void _pushSignUp() {
    setState(() => _policyAccepted = false);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmailSignUpPage(currentUser: widget.currentUser),
      ),
    );
  }

  void _pushReset() {
    setState(() => _policyAccepted = false);
    // Plain push (no fullscreenDialog) so iOS edge-swipe-back works,
    // matching the sign-up page's behavior. The previous fullscreenDialog
    // presented this as a modal sheet from the bottom which iOS
    // intentionally disables swipe-back for.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ResetPasswordView(currentUser: widget.currentUser),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final working = widget.currentUser.isPerformingAuthAction || _wechatWorking;
    return Scaffold(
      backgroundColor: AetherColors.bgCanvas,
      body: SafeArea(
        child: AutofillGroup(
          onDisposeAction: AutofillContextAction.cancel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AuthTopBar(showLanguageToggle: false),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.zero,
                  child: AuthFormBody(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 80),
                        AuthHeading(
                          title: l.authSignIn,
                          subtitle: l.authWelcomeBack,
                        ),
                        const SizedBox(height: 32),
                        Row(
                          children: [
                            _methodOption(
                              _LoginMethod.phone,
                              l.authPhonePasswordLogin,
                              working,
                            ),
                            _methodOption(
                              _LoginMethod.email,
                              l.authEmailPasswordLogin,
                              working,
                            ),
                          ],
                        ),
                        const SizedBox(height: AetherSpacing.lg),
                        LabeledField(
                          key: ValueKey(
                            _isPhone ? 'auth-phone-input' : 'auth-email-input',
                          ),
                          label: _isPhone
                              ? l.authPhoneNumberHint
                              : l.authEmailHint,
                          labelFontSize: 14,
                          controller: _account,
                          enabled: !working,
                          leading: _isPhone
                              ? PhoneCountryPrefix(
                                  country: _country,
                                  enabled: !working,
                                  onTap: _selectCountry,
                                )
                              : null,
                          keyboardType: _isPhone
                              ? TextInputType.phone
                              : TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: _isPhone
                              ? const [
                                  AutofillHints.telephoneNumberNational,
                                  AutofillHints.username,
                                ]
                              : const [
                                  AutofillHints.username,
                                  AutofillHints.email,
                                ],
                          onChanged: (_) =>
                              setState(() => _policyAccepted = false),
                        ),
                        const SizedBox(height: AetherSpacing.xl),
                        if (_isPhone)
                          Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  key: const ValueKey('auth-use-password'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: !_codeLogin
                                        ? AetherColors.textPrimary
                                        : AetherColors.textTertiary,
                                  ),
                                  onPressed: working
                                      ? null
                                      : () =>
                                            setState(() => _codeLogin = false),
                                  child: Text(l.authPasswordLogin),
                                ),
                              ),
                              Expanded(
                                child: TextButton(
                                  key: const ValueKey('auth-use-code'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: _codeLogin
                                        ? AetherColors.textPrimary
                                        : AetherColors.textTertiary,
                                  ),
                                  onPressed: working
                                      ? null
                                      : () => setState(() => _codeLogin = true),
                                  child: Text(l.authCodeLogin),
                                ),
                              ),
                            ],
                          ),
                        if (!_codeLogin) ...[
                          LabeledField(
                            label: l.authPasswordHint,
                            labelFontSize: 14,
                            controller: _password,
                            enabled: !working,
                            isSecure: true,
                            obscureText: !_passwordVisible,
                            trailing: IconButton(
                              tooltip: _passwordVisible
                                  ? l.authHidePassword
                                  : l.authShowPassword,
                              onPressed: working
                                  ? null
                                  : () => setState(
                                      () =>
                                          _passwordVisible = !_passwordVisible,
                                    ),
                              icon: Icon(
                                _passwordVisible
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 20,
                                color: AetherColors.textTertiary,
                              ),
                            ),
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) {
                              if (_canSubmit && !working) _submit();
                            },
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              key: const ValueKey('auth-forgot-password'),
                              onPressed: working ? null : _pushReset,
                              style: TextButton.styleFrom(
                                foregroundColor: AetherColors.textTertiary,
                                minimumSize: const Size(0, 44),
                                padding: EdgeInsets.zero,
                              ),
                              child: Text(
                                l.authForgotPassword
                                    .replaceAll('?', '')
                                    .replaceAll('？', ''),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                        AuthPolicyConsent(
                          value: _policyAccepted,
                          enabled: !working,
                          onChanged: (value) =>
                              setState(() => _policyAccepted = value),
                        ),
                        const SizedBox(height: AetherSpacing.lg),
                        MinimalCta(
                          title: _codeLogin
                              ? l.authPhoneSendCode
                              : l.authSignIn,
                          enabled:
                              (_codeLogin
                                  ? _policyAccepted && _codeTarget != null
                                  : _canSubmit) &&
                              !working,
                          working: working,
                          onTap: _codeLogin ? _openCodeLogin : _submit,
                        ),
                        if (wechatSignInFlow.available) ...[
                          const SizedBox(height: AetherSpacing.xl),
                          MinimalCta(
                            title:
                                Localizations.localeOf(context).languageCode ==
                                    'zh'
                                ? '微信登录'
                                : 'SIGN IN WITH WECHAT',
                            enabled: _policyAccepted && !working,
                            working: _wechatWorking,
                            onTap: _beginWechat,
                          ),
                        ],
                        const SizedBox(height: AetherSpacing.xxl),
                        MinimalLink(
                          title: l.authSignUp,
                          emphasis: MinimalLinkEmphasis.medium,
                          onTap: working ? null : _pushSignUp,
                        ),
                        const SizedBox(height: AetherSpacing.xl),
                        const SizedBox(height: AetherSpacing.xl),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
