// Password recovery: email, server-verified code, then a new password.
// Recovery never creates a signed-in session.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth/auth_error.dart';
import '../../auth/auth_service.dart';
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
  EmailPasswordRecovery? _recovery;
  String? _owner;
  bool _leaving = false;
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
  static const int _minPasswordLength = 6;

  @override
  void initState() {
    super.initState();
    _owner = widget.currentUser.signedInUser?.id.rawValue;
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _otpFocusNode.addListener(_onExternalChanged);
    widget.currentUser.addListener(_accountChanged);
  }

  @override
  void dispose() {
    _leave();
    _otpFocusNode.removeListener(_onExternalChanged);
    widget.currentUser.removeListener(_accountChanged);
    _emailController.dispose();
    _otpController.dispose();
    _otpFocusNode.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _onExternalChanged() {
    if (_active) setState(() {});
  }

  bool get _active =>
      mounted &&
      !_leaving &&
      !widget.currentUser.isSignedIn &&
      widget.currentUser.signedInUser?.id.rawValue == _owner;

  void _accountChanged() {
    if (widget.currentUser.signedInUser?.id.rawValue == _owner) {
      _onExternalChanged();
      return;
    }
    _leave();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void didUpdateWidget(covariant ResetPasswordView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser != widget.currentUser) {
      oldWidget.currentUser.removeListener(_accountChanged);
      widget.currentUser.addListener(_accountChanged);
      _leave();
    }
  }

  void _clearSensitive() {
    _otpController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
  }

  Future<void> _closeRecovery(EmailPasswordRecovery recovery) async {
    try {
      await recovery.close();
    } catch (_) {
      // Disposal cannot expose provider details or retain the recovery flow.
    }
  }

  void _discardRecovery() {
    _cooldownTimer?.cancel();
    _clearSensitive();
    final recovery = _recovery;
    _recovery = null;
    if (recovery != null) unawaited(_closeRecovery(recovery));
  }

  void _leave() {
    _leaving = true;
    _discardRecovery();
    _emailController.clear();
  }

  String get _normalizedEmail => _emailController.text.trim().toLowerCase();

  bool get _step1CanSubmit => _normalizedEmail.contains('@');
  bool get _working =>
      !_active || _requestInFlight || widget.currentUser.isPerformingAuthAction;
  bool get _step2CanSubmit =>
      RegExp(r'^[0-9]{6}$').hasMatch(_otpController.text);
  bool get _passwordCanSubmit =>
      _newPasswordController.text.length >= _minPasswordLength &&
      _newPasswordController.text == _confirmPasswordController.text;

  _ResetError _serviceError(AuthErrorKind kind) => switch (kind) {
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
      if (!_active) {
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

  Future<void> _perform(
    Future<void> Function(EmailPasswordRecovery) action,
    VoidCallback success,
  ) async {
    if (!_active || _working) return;
    setState(() {
      _requestInFlight = true;
      _error = null;
    });
    try {
      final recovery = _recovery ??= widget.currentUser
          .createEmailPasswordRecovery();
      await action(recovery);
      if (_active) success();
    } on AuthException catch (error) {
      if (!_active) return;
      if (_step == _Step.enterPassword &&
          (error.kind == AuthErrorKind.notSignedIn ||
              error.kind == AuthErrorKind.invalidVerificationCode)) {
        _discardRecovery();
        setState(() {
          _step = _Step.enterEmail;
          _email = '';
          _resendCooldownSec = 0;
          _error = _ResetError.expired;
        });
      } else {
        setState(() => _error = _serviceError(error.kind));
        if (_step == _Step.enterOtp) {
          _otpController.clear();
          _otpFocusNode.requestFocus();
          _shake.forward(from: 0);
        }
      }
    } catch (_) {
      if (_active) setState(() => _error = _ResetError.requestFailed);
    } finally {
      if (_active) setState(() => _requestInFlight = false);
    }
  }

  Future<void> _sendOtp() async {
    if (!_step1CanSubmit || _step != _Step.enterEmail) return;
    final email = _normalizedEmail;
    await _perform((recovery) => recovery.sendCode(email), () {
      setState(() {
        _email = email;
        _step = _Step.enterOtp;
      });
      _startCooldown();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_active) _otpFocusNode.requestFocus();
      });
    });
  }

  Future<void> _resendOtp() async {
    if (_resendCooldownSec > 0 || _email.isEmpty || _step != _Step.enterOtp)
      return;
    await _perform((recovery) => recovery.sendCode(_email), () {
      _otpController.clear();
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppL10n.of(context).otpResendSent),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    });
  }

  Future<void> _verifyCode() async {
    if (!_step2CanSubmit || _step != _Step.enterOtp) return;
    final code = _otpController.text.trim();
    await _perform(
      (recovery) => recovery.verifyCode(email: _email, code: code),
      () {
        _otpFocusNode.unfocus();
        _otpController.clear();
        setState(() => _step = _Step.enterPassword);
      },
    );
  }

  Future<void> _confirmReset() async {
    if (!_active || _working || _step != _Step.enterPassword) return;
    if (!_passwordCanSubmit) {
      setState(
        () => _error = _newPasswordController.text.length < _minPasswordLength
            ? _ResetError.weakPassword
            : _ResetError.mismatch,
      );
      return;
    }
    final password = _newPasswordController.text;
    await _perform((recovery) => recovery.setPassword(password), () {
      _clearSensitive();
      TextInput.finishAutofillContext();
      final l = AppL10n.of(context);
      final message = l.localeName.startsWith('zh')
          ? '密码已重置，请使用新密码登录。'
          : 'Password reset. Sign in with your new password.';
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final working = _working;
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _leave();
      },
      child: Scaffold(
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
                      child: _step == _Step.enterEmail
                          ? _buildStep1(l, working)
                          : _step == _Step.enterOtp
                          ? _buildStep2(l, working)
                          : _buildPasswordStep(l, working),
                    ),
                  ),
                ),
              ],
            ),
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
