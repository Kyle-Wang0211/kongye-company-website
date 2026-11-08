// Password recovery: email, server-verified code, then a new password.
// Recovery never creates a signed-in session.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth/auth_error.dart';
import '../../auth/current_user.dart';
import '../../l10n/app_localizations.dart';
import '../design_system.dart';
import 'auth_minimal_widgets.dart';
import 'auth_shared_widgets.dart';

class ResetPasswordView extends StatefulWidget {
  final CurrentUser currentUser;

  const ResetPasswordView({super.key, required this.currentUser});

  @override
  State<ResetPasswordView> createState() => _ResetPasswordViewState();
}

enum _Step { enterEmail, enterOtp, enterPassword }

enum _ResetError {
  invalidCode,
  requestFailed,
  rateLimited,
  network,
  weakPassword,
  mismatch,
  expired,
}

class _ResetPasswordViewState extends State<ResetPasswordView>
    with SingleTickerProviderStateMixin {
  _Step _step = _Step.enterEmail;
  String _email = '';
  String? _resetToken;
  bool _requestInFlight = false;
  _ResetError? _error;

  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _otpFocusNode = FocusNode();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  late final AnimationController _shake;

  Timer? _cooldownTimer;
  int _resendCooldownSec = 0;

  static const int _resendCooldownSeconds = 60;
  static const int _otpLength = 6;
  static const int _minPasswordLength = 8;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _otpFocusNode.addListener(_onExternalChanged);
    widget.currentUser.addListener(_onExternalChanged);
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _otpFocusNode.removeListener(_onExternalChanged);
    widget.currentUser.removeListener(_onExternalChanged);
    _emailController.dispose();
    _otpController.dispose();
    _otpFocusNode.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _onExternalChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String get _normalizedEmail => _emailController.text.trim().toLowerCase();

  bool get _step1CanSubmit => _normalizedEmail.contains('@');
  bool get _working =>
      _requestInFlight || widget.currentUser.isPerformingAuthAction;
  bool get _step2CanSubmit => _otpController.text.length == _otpLength;
  bool get _passwordCanSubmit =>
      _newPasswordController.text.length >= _minPasswordLength &&
      _newPasswordController.text == _confirmPasswordController.text;

  _ResetError _serviceError() => switch (widget.currentUser.lastError?.kind) {
    AuthErrorKind.invalidVerificationCode => _ResetError.invalidCode,
    AuthErrorKind.weakPassword => _ResetError.weakPassword,
    AuthErrorKind.rateLimited => _ResetError.rateLimited,
    AuthErrorKind.network => _ResetError.network,
    AuthErrorKind.notSignedIn => _ResetError.expired,
    _ => _ResetError.requestFailed,
  };

  String? _errorText(AppL10n l) => switch (_error) {
    _ResetError.invalidCode => l.resetInvalidCode,
    _ResetError.requestFailed => l.resetRequestFailed,
    _ResetError.rateLimited => l.resetRateLimited,
    _ResetError.network => l.resetNetworkError,
    _ResetError.weakPassword => l.resetPasswordTooShort,
    _ResetError.mismatch => l.resetPasswordMismatch,
    _ResetError.expired => l.resetSessionExpired,
    null => null,
  };

  Widget _buildError(AppL10n l) {
    final text = _errorText(l);
    return text == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              text,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldownSec = _resendCooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendCooldownSec--;
        if (_resendCooldownSec <= 0) {
          _resendCooldownSec = 0;
          t.cancel();
        }
      });
    });
  }

  Future<void> _sendOtp() async {
    if (!_step1CanSubmit || _working) return;
    final email = _normalizedEmail;
    setState(() {
      _requestInFlight = true;
      _error = null;
    });
    try {
      final ok = await widget.currentUser
          .sendPasswordReset(email)
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (ok) {
        setState(() {
          _email = email;
          _step = _Step.enterOtp;
        });
        _startCooldown();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _otpFocusNode.requestFocus();
        });
      } else {
        setState(() => _error = _serviceError());
      }
    } catch (_) {
      if (mounted) setState(() => _error = _ResetError.network);
    } finally {
      if (mounted) setState(() => _requestInFlight = false);
    }
  }

  Future<void> _resendOtp() async {
    if (_resendCooldownSec > 0 || _email.isEmpty || _working) return;
    setState(() {
      _requestInFlight = true;
      _error = null;
    });
    try {
      final ok = await widget.currentUser
          .sendPasswordReset(_email)
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (ok) {
        _startCooldown();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppL10n.of(context).otpResendSent),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        setState(() => _error = _serviceError());
      }
    } catch (_) {
      if (mounted) setState(() => _error = _ResetError.network);
    } finally {
      if (mounted) setState(() => _requestInFlight = false);
    }
  }

  Future<void> _verifyCode() async {
    if (!_step2CanSubmit || _working || _step != _Step.enterOtp) return;
    setState(() {
      _requestInFlight = true;
      _error = null;
    });
    try {
      final token = await widget.currentUser
          .verifyPasswordResetCode(
            email: _email,
            token: _otpController.text.trim(),
          )
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (token != null && token.isNotEmpty) {
        _otpFocusNode.unfocus();
        _otpController.clear();
        setState(() {
          _resetToken = token;
          _step = _Step.enterPassword;
        });
      } else {
        _otpController.clear();
        _otpFocusNode.requestFocus();
        _shake.forward(from: 0);
        setState(() => _error = _serviceError());
      }
    } catch (_) {
      if (mounted) setState(() => _error = _ResetError.network);
    } finally {
      if (mounted) setState(() => _requestInFlight = false);
    }
  }

  Future<void> _confirmReset() async {
    if (_working || _step != _Step.enterPassword) return;
    if (!_passwordCanSubmit) {
      setState(
        () => _error = _newPasswordController.text.length < _minPasswordLength
            ? _ResetError.weakPassword
            : _ResetError.mismatch,
      );
      return;
    }
    final resetToken = _resetToken;
    if (resetToken == null || resetToken.isEmpty) return;
    setState(() {
      _requestInFlight = true;
      _error = null;
    });
    try {
      final ok = await widget.currentUser
          .completePasswordReset(
            email: _email,
            resetToken: resetToken,
            newPassword: _newPasswordController.text,
          )
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (ok) {
        _resetToken = null;
        TextInput.finishAutofillContext();
        Navigator.of(context).popUntil((r) => r.isFirst);
      } else {
        setState(() => _error = _serviceError());
      }
    } catch (_) {
      if (mounted) setState(() => _error = _ResetError.network);
    } finally {
      if (mounted) setState(() => _requestInFlight = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final working = _working;
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: AetherSpacing.xl,
                  ),
                  child: _step == _Step.enterEmail
                      ? _buildStep1(l, working)
                      : _step == _Step.enterOtp
                      ? _buildStep2(l, working)
                      : _buildPasswordStep(l, working),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep1(AppL10n l, bool working) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top spacing tuned so the email field underline lines up with
        // the same field on sign-in / sign-up. The "RESET PASSWORD"
        // title wraps to two lines on phone widths whereas "SIGN IN"
        // is one — and we drop the subtitle here per design — so
        // 44 (vs the standard 80) compensates for the taller heading.
        const SizedBox(height: 44),
        AuthHeading(title: l.resetTitle),
        const SizedBox(height: 64),
        LabeledField(
          label: l.authEmailHint,
          controller: _emailController,
          enabled: !working,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.username],
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (_step1CanSubmit && !working) _sendOtp();
          },
        ),
        _buildError(l),
        const SizedBox(height: 56),
        MinimalCta(
          title: l.resetSendCode,
          enabled: _step1CanSubmit && !working,
          working: working,
          onTap: _sendOtp,
        ),
        const SizedBox(height: AetherSpacing.xl),
      ],
    );
  }

  Widget _buildStep2(AppL10n l, bool working) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 56),
        AuthHeading(
          title: l.resetTitle,
          subtitle: l.resetSubtitleEnterCode(_email),
          uppercaseSubtitle: false,
        ),
        const SizedBox(height: 48),
        OtpBoxRow(
          controller: _otpController,
          focusNode: _otpFocusNode,
          otpLength: _otpLength,
          shake: _shake,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AetherSpacing.xl),
        _buildError(l),
        const SizedBox(height: 56),
        MinimalCta(
          title: l.resetVerifyCode,
          enabled: _step2CanSubmit && !working,
          working: working,
          onTap: _verifyCode,
        ),
        const SizedBox(height: AetherSpacing.xxl),
        MinimalLink(
          title: _resendCooldownSec > 0
              ? l.otpResendCooldown(_resendCooldownSec)
              : l.otpResend,
          emphasis: MinimalLinkEmphasis.faint,
          onTap: (_resendCooldownSec > 0 || working) ? null : _resendOtp,
        ),
        const SizedBox(height: AetherSpacing.xl),
      ],
    );
  }

  Widget _buildPasswordStep(AppL10n l, bool working) {
    void passwordChanged(String _) => setState(() {
      _error =
          _confirmPasswordController.text.isNotEmpty &&
              _newPasswordController.text != _confirmPasswordController.text
          ? _ResetError.mismatch
          : _newPasswordController.text.isNotEmpty &&
                _newPasswordController.text.length < _minPasswordLength
          ? _ResetError.weakPassword
          : null;
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 56),
        AuthHeading(
          title: l.resetTitle,
          subtitle: l.resetSubtitleNewPassword,
          uppercaseSubtitle: false,
        ),
        const SizedBox(height: 48),
        LabeledField(
          label: l.resetNewPasswordHint,
          controller: _newPasswordController,
          isSecure: true,
          enabled: !working,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          onChanged: passwordChanged,
        ),
        const SizedBox(height: AetherSpacing.xl),
        LabeledField(
          label: l.resetConfirmPasswordHint,
          controller: _confirmPasswordController,
          isSecure: true,
          enabled: !working,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
          onChanged: passwordChanged,
          onSubmitted: (_) => _confirmReset(),
        ),
        _buildError(l),
        const SizedBox(height: 56),
        MinimalCta(
          title: l.resetConfirm,
          enabled: _passwordCanSubmit && !working,
          working: working,
          onTap: _confirmReset,
        ),
        const SizedBox(height: AetherSpacing.xl),
      ],
    );
  }
}
