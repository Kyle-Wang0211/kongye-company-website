// EmailSignUpPage — Ultra-Minimal sign-up flow.
//
// Pushed by AuthRootView when the user taps "REQUEST NEW ACCESS / 注册".
// Visual conventions identical to AuthRootView (top bar with back
// chevron + wordmark + 中/EN, big caps heading, underline-only inputs,
// caps text CTA). Differs only in copy and the post-submit handler:
// when the strict-confirmation backend returns EmailVerificationPending,
// we push OtpVerificationView (carrying the password forward so the
// OTP page can signInWithPassword once the user is created).
//
// Filename note: this used to also host the sign-IN form. Sign-in
// moved to auth_root_view.dart in the 2026-04-29 redesign. Renaming
// the file would churn git history more than it's worth right now.

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../auth/auth_error.dart';
import '../../auth/auth_models.dart';
import '../../auth/current_user.dart';
import '../../l10n/app_localizations.dart';
import '../design_system.dart';
import 'auth_minimal_widgets.dart';
import 'auth_policy_consent.dart';
import 'otp_verification_view.dart';
import 'phone_sign_in_view.dart';

class EmailSignUpPage extends StatefulWidget {
  final CurrentUser currentUser;

  const EmailSignUpPage({super.key, required this.currentUser});

  @override
  State<EmailSignUpPage> createState() => _EmailSignUpPageState();
}

class _EmailSignUpPageState extends State<EmailSignUpPage> {
  final _displayName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _policyAccepted = false;
  String? _consentOwner;

  @override
  void initState() {
    super.initState();
    _consentOwner = widget.currentUser.signedInUser?.id.rawValue;
    widget.currentUser.addListener(_onUserChanged);
  }

  @override
  void didUpdateWidget(covariant EmailSignUpPage oldWidget) {
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
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _onUserChanged() {
    final owner = widget.currentUser.signedInUser?.id.rawValue;
    if (owner != _consentOwner) {
      _consentOwner = owner;
      _policyAccepted = false;
    }
    final err = widget.currentUser.lastError;
    if (err != null && mounted) {
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
      builder: (_) => ShadDialog.alert(
        backgroundColor: AetherColors.bgCanvas,
        title: Text(
          AppL10n.of(context).authErrorDialogTitle,
          style: AetherTextStyles.h2,
        ),
        actions: [
          ShadButton.ghost(
            onPressed: () => Navigator.of(context).pop(),
            foregroundColor: AetherColors.primary,
            child: Text(
              AppL10n.of(context).commonOk,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
        closeIcon: const SizedBox.shrink(),
        radius: BorderRadius.circular(AetherRadii.lg),
        child: Text(message, style: AetherTextStyles.body),
      ),
    );
  }

  String get _normalizedEmail => _email.text.trim().toLowerCase();
  bool get _canSubmit =>
      _policyAccepted &&
      _displayName.text.trim().isNotEmpty &&
      _normalizedEmail.isNotEmpty &&
      _password.text.length >= 8 &&
      _password.text == _confirmPassword.text;

  Future<void> _submit() async {
    if (!_canSubmit ||
        widget.currentUser.isPerformingAuthAction ||
        widget.currentUser.isSignedIn) {
      return;
    }
    try {
      await widget.currentUser.signUp(
        SignUpRequest.email(
          email: _normalizedEmail,
          password: _password.text,
          displayName: _displayName.text.trim(),
        ),
      );
    } on EmailVerificationPending catch (e) {
      // signup-start has emailed an OTP and stashed the request in
      // pending_signups. The auth.users row doesn't exist yet — it
      // gets created when OtpVerificationView calls verifySignupOtp
      // (which then signInWithPasswords using e.password).
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OtpVerificationView(
            currentUser: widget.currentUser,
            email: e.email,
            password: e.password,
            hasPolicyConsent: () =>
                mounted &&
                _policyAccepted &&
                _normalizedEmail == e.email &&
                _consentOwner == widget.currentUser.signedInUser?.id.rawValue,
          ),
          fullscreenDialog: true,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final working = widget.currentUser.isPerformingAuthAction;
    return Scaffold(
      backgroundColor: AetherColors.bgCanvas,
      body: SafeArea(
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AuthTopBar(leading: AuthTopBarBack()),
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
                          title: l.authSignUp,
                          subtitle: l.authCreateAccount,
                        ),
                        const SizedBox(height: 64),
                        LabeledField(
                          label: l.authEmailHint,
                          labelFontSize: 14,
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.username],
                          onChanged: (_) =>
                              setState(() => _policyAccepted = false),
                        ),
                        const SizedBox(height: AetherSpacing.xl),
                        LabeledField(
                          key: const ValueKey('signup-nickname'),
                          label: l.meDisplayName,
                          labelFontSize: 14,
                          controller: _displayName,
                          enabled: !working,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.nickname],
                          onChanged: (_) =>
                              setState(() => _policyAccepted = false),
                        ),
                        const SizedBox(height: AetherSpacing.xl),
                        LabeledField(
                          key: const ValueKey('signup-password'),
                          label: l.authPasswordHintMin,
                          labelFontSize: 14,
                          controller: _password,
                          isSecure: true,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.newPassword],
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) {
                            if (_canSubmit && !working) _submit();
                          },
                        ),
                        const SizedBox(height: AetherSpacing.xl),
                        LabeledField(
                          key: const ValueKey('signup-confirm-password'),
                          label: l.resetConfirmPasswordHint,
                          labelFontSize: 14,
                          controller: _confirmPassword,
                          enabled: !working,
                          isSecure: true,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.newPassword],
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) {
                            if (_canSubmit && !working) _submit();
                          },
                        ),
                        if (_confirmPassword.text.isNotEmpty &&
                            _confirmPassword.text != _password.text)
                          Padding(
                            padding: const EdgeInsets.only(
                              top: AetherSpacing.sm,
                            ),
                            child: Text(
                              l.resetPasswordMismatch,
                              style: const TextStyle(
                                color: AetherColors.textSecondary,
                              ),
                            ),
                          ),
                        const SizedBox(height: AetherSpacing.lg),
                        AuthPolicyConsent(
                          value: _policyAccepted,
                          enabled: !working,
                          onChanged: (value) =>
                              setState(() => _policyAccepted = value),
                        ),
                        const SizedBox(height: AetherSpacing.lg),
                        MinimalCta(
                          title: l.authSignUp,
                          enabled: _canSubmit && !working,
                          working: working,
                          onTap: _submit,
                        ),
                        const SizedBox(height: AetherSpacing.xxl),
                        MinimalLink(
                          title: l.phoneSignUpWithPhone,
                          emphasis: MinimalLinkEmphasis.medium,
                          onTap: working
                              ? null
                              : () {
                                  setState(() => _policyAccepted = false);
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => PhoneAuthPage(
                                        currentUser: widget.currentUser,
                                        intent: PhoneIntent.signUp,
                                      ),
                                    ),
                                  );
                                },
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
