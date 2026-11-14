import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../auth/auth_error.dart';
import '../../auth/auth_models.dart';
import '../../auth/current_user.dart';
import '../../l10n/app_localizations.dart';
import '../design_system.dart';
import 'auth_minimal_widgets.dart';
import 'auth_shared_widgets.dart';

/// Existing-account SMS login only. Email codes belong to signup and recovery.
class LoginCodeView extends StatefulWidget {
  final CurrentUser currentUser;
  final String target;
  const LoginCodeView({
    super.key,
    required this.currentUser,
    required this.target,
  });
  @override
  State<LoginCodeView> createState() => _LoginCodeViewState();
}

class _LoginCodeViewState extends State<LoginCodeView>
    with SingleTickerProviderStateMixin {
  final _code = TextEditingController();
  final _focus = FocusNode();
  late final AnimationController _shake;
  PhoneVerificationChallenge? _challenge;
  Timer? _timer;
  int _cooldown = 0;
  bool _working = false;
  int? _pendingToken;
  bool _leaving = false;
  bool _sent = false;
  AuthErrorKind? _error;
  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _send();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cancelOwnedSignIn();
    _code.dispose();
    _focus.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _cancelOwnedSignIn() {
    final token = _pendingToken;
    _pendingToken = null;
    if (token != null) widget.currentUser.cancelPendingSignIn(token);
  }

  void _startCooldown() {
    _timer?.cancel();
    _cooldown = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _cooldown--);
      if (_cooldown <= 0) timer.cancel();
    });
  }

  Future<void> _send() async {
    if (_working || _cooldown > 0 || widget.currentUser.isSignedIn) return;
    setState(() {
      _working = true;
      _error = null;
    });
    final challenge = await widget.currentUser.startPhoneVerification(
      widget.target,
      forSignUp: false,
    );
    if (!mounted || _leaving) return;
    _challenge = challenge;
    final ok = challenge != null;
    setState(() {
      _working = false;
      if (ok) {
        _sent = true;
        _code.clear();
        _startCooldown();
      } else {
        _error = widget.currentUser.lastError?.kind ?? AuthErrorKind.unknown;
      }
    });
    widget.currentUser.clearLastError();
  }

  Future<void> _verify() async {
    if (_working ||
        !_sent ||
        _code.text.length != 6 ||
        widget.currentUser.isSignedIn) {
      return;
    }
    final challenge = _challenge;
    if (challenge == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    final operation = widget.currentUser.signIn(
      SignInRequest.phone(
        phoneNumber: widget.target,
        verificationID: challenge.verificationID,
        code: _code.text,
      ),
    );
    _pendingToken = widget.currentUser.pendingSignInToken;
    await operation;
    _pendingToken = null;
    if (!mounted || _leaving) return;
    if (widget.currentUser.isSignedIn) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _working = false;
      _error =
          widget.currentUser.lastError?.kind ??
          AuthErrorKind.invalidVerificationCode;
    });
    widget.currentUser.clearLastError();
    _shake.forward(from: 0);
  }

  String? _errorText(AppL10n l) => switch (_error) {
    null => null,
    AuthErrorKind.invalidCredentials ||
    AuthErrorKind.invalidVerificationCode => l.resetInvalidCode,
    AuthErrorKind.network => l.resetNetworkError,
    AuthErrorKind.rateLimited => l.resetRateLimited,
    _ => l.authLoginCodeFailed,
  };
  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _leaving = true;
          _cancelOwnedSignIn();
        }
      },
      child: Scaffold(
        backgroundColor: AetherColors.bgCanvas,
        body: SafeArea(
          child: Column(
            children: [
              const AuthTopBar(
                leading: AuthTopBarBack(),
                showLanguageToggle: false,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    vertical: AetherSpacing.xl,
                  ),
                  child: AuthFormBody(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AuthHeading(
                          title: l.authLoginCodeTitle,
                          subtitle: widget.target,
                          uppercaseSubtitle: false,
                        ),
                        const SizedBox(height: AetherSpacing.xl),
                        OtpBoxRow(
                          controller: _code,
                          focusNode: _focus,
                          otpLength: 6,
                          shake: _shake,
                          onChanged: (_) => setState(() {}),
                        ),
                        if (_errorText(l) != null)
                          Text(
                            _errorText(l)!,
                            key: const ValueKey('login-code-error'),
                            style: const TextStyle(color: AetherColors.danger),
                          ),
                        const SizedBox(height: AetherSpacing.lg),
                        MinimalCta(
                          key: const ValueKey('login-code-submit'),
                          title: l.authSignIn,
                          enabled: _sent && _code.text.length == 6 && !_working,
                          working: _working,
                          onTap: _verify,
                        ),
                        const SizedBox(height: AetherSpacing.lg),
                        ShadButton.ghost(
                          key: const ValueKey('login-code-resend'),
                          onPressed: _working || _cooldown > 0 ? null : _send,
                          enabled:
                              (_working || _cooldown > 0 ? null : _send) !=
                              null,
                          child: Text(
                            _cooldown > 0
                                ? l.otpResendCooldown(_cooldown)
                                : l.otpResend,
                          ),
                        ),
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
