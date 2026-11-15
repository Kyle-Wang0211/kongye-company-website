part of pw_shared_auth_ui;

class PhoneResetPasswordView extends StatefulWidget {
  final CurrentUser currentUser;
  final String? initialPhone;
  final PhoneCountry? initialCountry;

  const PhoneResetPasswordView({
    super.key,
    required this.currentUser,
    this.initialPhone,
    this.initialCountry,
  });

  @override
  State<PhoneResetPasswordView> createState() => _PhoneResetPasswordViewState();
}

enum _PhoneResetStep { phone, code, password }

class _PhoneResetPasswordViewState extends State<PhoneResetPasswordView>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _phone;
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _codeFocus = FocusNode();
  late final AnimationController _shake;
  late PhoneCountry _country;
  PhonePasswordRecovery? _recovery;
  String? _owner;
  String? _target;
  _PhoneResetStep _step = _PhoneResetStep.phone;
  AuthErrorKind? _error;
  bool _working = false;
  bool _leaving = false;
  Timer? _timer;
  int _cooldown = 0;

  @override
  void initState() {
    super.initState();
    _phone = TextEditingController(text: widget.initialPhone ?? '');
    _country = widget.initialCountry ?? phoneCountryForIso('CN');
    _owner = widget.currentUser.signedInUser?.id.rawValue;
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    widget.currentUser.addListener(_accountChanged);
    _codeFocus.addListener(_focusChanged);
  }

  bool get _active =>
      mounted &&
      !_leaving &&
      widget.currentUser.signedInUser?.id.rawValue == _owner &&
      !widget.currentUser.isSignedIn;

  void _focusChanged() {
    if (mounted && !_leaving) setState(() {});
  }

  void _accountChanged() {
    if (widget.currentUser.signedInUser?.id.rawValue == _owner) return;
    _leave();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void didUpdateWidget(covariant PhoneResetPasswordView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser != widget.currentUser) {
      oldWidget.currentUser.removeListener(_accountChanged);
      widget.currentUser.addListener(_accountChanged);
      _leave();
    }
  }

  Future<void> _closeRecovery(PhonePasswordRecovery recovery) async {
    try {
      await recovery.close();
    } catch (_) {
      // Closing an isolated recovery must never surface provider details.
    }
  }

  void _clearSensitive() {
    _phone.clear();
    _code.clear();
    _password.clear();
    _confirmation.clear();
  }

  void _leave() {
    _leaving = true;
    _timer?.cancel();
    _clearSensitive();
    final recovery = _recovery;
    _recovery = null;
    if (recovery != null) unawaited(_closeRecovery(recovery));
  }

  @override
  void dispose() {
    widget.currentUser.removeListener(_accountChanged);
    _leave();
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    _confirmation.dispose();
    _codeFocus.removeListener(_focusChanged);
    _codeFocus.dispose();
    _shake.dispose();
    super.dispose();
  }

  String? get _normalizedPhone =>
      normalizePhoneLogin(_phone.text, country: _country);

  bool get _validCode => RegExp(r'^[0-9]{6}$').hasMatch(_code.text);
  bool get _validPassword =>
      _password.text.length >= 6 && _password.text == _confirmation.text;

  void _startCooldown() {
    _timer?.cancel();
    _cooldown = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_active) {
        timer.cancel();
        return;
      }
      setState(() => _cooldown--);
      if (_cooldown <= 0) timer.cancel();
    });
  }

  Future<void> _perform(
    Future<void> Function(PhonePasswordRecovery) action,
    VoidCallback success,
  ) async {
    if (!_active || _working || widget.currentUser.isPerformingAuthAction)
      return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final recovery = _recovery ??= widget.currentUser
          .createPhonePasswordRecovery();
      await action(recovery);
      if (!_active) return;
      success();
    } on AuthException catch (error) {
      if (!_active) return;
      if (_step == _PhoneResetStep.password &&
          (error.kind == AuthErrorKind.notSignedIn ||
              error.kind == AuthErrorKind.invalidVerificationCode)) {
        _timer?.cancel();
        _code.clear();
        _password.clear();
        _confirmation.clear();
        final recovery = _recovery;
        _recovery = null;
        if (recovery != null) unawaited(_closeRecovery(recovery));
        setState(() {
          _step = _PhoneResetStep.phone;
          _target = null;
          _cooldown = 0;
          _error = AuthErrorKind.notSignedIn;
        });
        return;
      }
      setState(() => _error = error.kind);
      if (_step == _PhoneResetStep.code) {
        _code.clear();
        _codeFocus.requestFocus();
        _shake.forward(from: 0);
      }
    } catch (_) {
      if (_active) setState(() => _error = AuthErrorKind.unknown);
    } finally {
      if (_active) setState(() => _working = false);
    }
  }

  Future<void> _send() async {
    if (_step == _PhoneResetStep.password || _cooldown > 0) return;
    final phone = _step == _PhoneResetStep.phone ? _normalizedPhone : _target;
    if (phone == null) return;
    await _perform((recovery) => recovery.sendCode(phone), () {
      setState(() {
        _target = phone;
        _code.clear();
        _step = _PhoneResetStep.code;
        _startCooldown();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_active) _codeFocus.requestFocus();
      });
    });
  }

  Future<void> _verify() async {
    final phone = _target;
    if (_step != _PhoneResetStep.code || phone == null || !_validCode) return;
    final code = _code.text;
    await _perform(
      (recovery) => recovery.verifyCode(phone: phone, code: code),
      () => setState(() {
        _code.clear();
        _step = _PhoneResetStep.password;
      }),
    );
  }

  Future<void> _reset() async {
    if (_step != _PhoneResetStep.password || !_validPassword) return;
    final password = _password.text;
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

  Future<void> _pickCountry() async {
    if (_working || _step != _PhoneResetStep.phone) return;
    final country = await showPhoneCountryPicker(context);
    if (!_active || country == null) return;
    setState(() {
      _country = country;
      _error = null;
    });
  }

  String? _errorText(AppL10n l) => switch (_error) {
    null => null,
    AuthErrorKind.invalidCredentials ||
    AuthErrorKind.invalidVerificationCode => l.resetInvalidCode,
    AuthErrorKind.weakPassword => l.resetPasswordTooShort,
    AuthErrorKind.rateLimited => l.resetRateLimited,
    AuthErrorKind.network => l.resetNetworkError,
    AuthErrorKind.notSignedIn => l.resetSessionExpired,
    _ => l.resetRequestFailed,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final enabled = _active && !_working;
    final error = _errorText(l);
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: AetherSpacing.xl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 44),
                        AuthHeading(title: l.resetTitle, subtitle: _target),
                        const SizedBox(height: 48),
                        if (_step == _PhoneResetStep.phone)
                          LabeledField(
                            key: const ValueKey('phone-reset-phone'),
                            label: l.authPhoneNumberHint,
                            controller: _phone,
                            leading: PhoneCountryPrefix(
                              country: _country,
                              enabled: enabled,
                              onTap: _pickCountry,
                            ),
                            keyboardType: TextInputType.phone,
                            autofillHints: const [
                              AutofillHints.telephoneNumber,
                            ],
                            onChanged: (_) => setState(() => _error = null),
                            onSubmitted: (_) => _send(),
                          ),
                        if (_step == _PhoneResetStep.code)
                          OtpBoxRow(
                            controller: _code,
                            focusNode: _codeFocus,
                            otpLength: 6,
                            shake: _shake,
                            onChanged: (_) => setState(() => _error = null),
                          ),
                        if (_step == _PhoneResetStep.password) ...[
                          LabeledField(
                            key: const ValueKey('phone-reset-password'),
                            label: l.resetNewPasswordHint,
                            controller: _password,
                            isSecure: true,
                            autofillHints: const [AutofillHints.newPassword],
                            onChanged: (_) => setState(() => _error = null),
                          ),
                          const SizedBox(height: AetherSpacing.lg),
                          LabeledField(
                            key: const ValueKey('phone-reset-confirm-password'),
                            label: l.resetConfirmPasswordHint,
                            controller: _confirmation,
                            isSecure: true,
                            autofillHints: const [AutofillHints.newPassword],
                            onChanged: (_) => setState(() => _error = null),
                            onSubmitted: (_) => _reset(),
                          ),
                        ],
                        if (error != null) ...[
                          const SizedBox(height: AetherSpacing.md),
                          Text(
                            error,
                            key: const ValueKey('phone-reset-error'),
                            style: const TextStyle(color: AetherColors.danger),
                          ),
                        ],
                        const SizedBox(height: 56),
                        MinimalCta(
                          key: const ValueKey('phone-reset-submit'),
                          title: switch (_step) {
                            _PhoneResetStep.phone => l.resetSendCode,
                            _PhoneResetStep.code => l.resetVerifyCode,
                            _PhoneResetStep.password => l.resetConfirm,
                          },
                          enabled:
                              enabled &&
                              (switch (_step) {
                                _PhoneResetStep.phone =>
                                  _normalizedPhone != null,
                                _PhoneResetStep.code => _validCode,
                                _PhoneResetStep.password => _validPassword,
                              }),
                          working: _working,
                          onTap: switch (_step) {
                            _PhoneResetStep.phone => _send,
                            _PhoneResetStep.code => _verify,
                            _PhoneResetStep.password => _reset,
                          },
                        ),
                        if (_step == _PhoneResetStep.code) ...[
                          const SizedBox(height: AetherSpacing.xl),
                          MinimalLink(
                            title: _cooldown > 0
                                ? l.otpResendCooldown(_cooldown)
                                : l.otpResend,
                            emphasis: MinimalLinkEmphasis.faint,
                            onTap: enabled && _cooldown == 0 ? _send : null,
                          ),
                        ],
                        const SizedBox(height: AetherSpacing.xl),
                      ],
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
}
