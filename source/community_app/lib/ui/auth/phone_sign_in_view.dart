// Dart port of App/Auth/PhoneSignInView.swift.
//
// Two-step flow:
//   1) country code + national number → provider issues verificationID
//   2) enter 6-digit code → sign in / sign up
//
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth/auth_models.dart';
import '../../auth/current_user.dart';
import '../../auth/phone_country_catalog.dart';
import '../../auth/phone_number_input.dart';
import '../design_system.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/phone_country_names.dart';
import 'auth_policy_consent.dart';
import 'auth_shared_widgets.dart';
import 'auth_minimal_widgets.dart';
import 'phone_country_picker.dart';

enum PhoneIntent { signIn, signUp }

/// Page shell shared by the sign-in and sign-up routes. The form below stays
/// embeddable for callers that already provide their own page structure.
class PhoneAuthPage extends StatelessWidget {
  final CurrentUser currentUser;
  final PhoneIntent intent;

  const PhoneAuthPage({
    super.key,
    required this.currentUser,
    required this.intent,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final signingUp = intent == PhoneIntent.signUp;
    return Scaffold(
      backgroundColor: AetherColors.bgCanvas,
      body: SafeArea(
        child: Column(
          children: [
            const AuthTopBar(leading: AuthTopBarBack()),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AetherSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AuthHeading(
                      title: signingUp ? l.authSignUp : l.authPhoneEntry,
                      subtitle: signingUp
                          ? l.authCreateAccount
                          : l.authWelcomeBack,
                    ),
                    const SizedBox(height: AetherSpacing.xl),
                    PhoneSignInView(currentUser: currentUser, intent: intent),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PhoneSignInView extends StatefulWidget {
  final CurrentUser currentUser;
  final PhoneIntent intent;

  const PhoneSignInView({
    super.key,
    required this.currentUser,
    required this.intent,
  });

  @override
  State<PhoneSignInView> createState() => _PhoneSignInViewState();
}

class _PhoneSignInViewState extends State<PhoneSignInView> {
  PhoneCountry _country = phoneCountryForIso('CN');
  final _nationalNumber = TextEditingController();
  final _displayName = TextEditingController();
  final _code = TextEditingController();

  PhoneVerificationChallenge? _challenge;
  bool _operationPending = false;
  bool _policyAccepted = false;
  String? _consentOwner;
  int _formEpoch = 0;

  @override
  void initState() {
    super.initState();
    _consentOwner = widget.currentUser.signedInUser?.id.rawValue;
    widget.currentUser.addListener(_accountChanged);
  }

  void _resetConsent() {
    _policyAccepted = false;
    _challenge = null;
    _code.clear();
    _formEpoch++;
  }

  void _accountChanged() {
    if (!mounted) return;
    final owner = widget.currentUser.signedInUser?.id.rawValue;
    if (owner != _consentOwner) {
      _consentOwner = owner;
      _resetConsent();
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant PhoneSignInView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser != widget.currentUser) {
      oldWidget.currentUser.removeListener(_accountChanged);
      widget.currentUser.addListener(_accountChanged);
    }
    if (oldWidget.currentUser != widget.currentUser ||
        oldWidget.intent != widget.intent) {
      _consentOwner = widget.currentUser.signedInUser?.id.rawValue;
      _resetConsent();
    }
  }

  bool get _blocked =>
      _operationPending ||
      widget.currentUser.isPerformingAuthAction ||
      widget.currentUser.isSignedIn;

  bool _beginOperation() {
    if (!_policyAccepted || _blocked) return false;
    // Capture the intent synchronously, before a provider await or a rebuild.
    setState(() => _operationPending = true);
    return true;
  }

  void _finishOperation() {
    if (mounted) setState(() => _operationPending = false);
  }

  @override
  void dispose() {
    widget.currentUser.removeListener(_accountChanged);
    _nationalNumber.dispose();
    _displayName.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _isSignUp => widget.intent == PhoneIntent.signUp;

  String get _e164 =>
      (_isSignUp
          ? normalizePhoneSignup(_nationalNumber.text, _country)
          : normalizePhoneLogin(_nationalNumber.text)) ??
      '';

  // Provider readiness is separate from metadata coverage. Keep overseas
  // sends disabled until international SMS delivery is explicitly verified.
  bool get _canStart => _e164.isNotEmpty && _e164.startsWith('+86');

  Future<void> _startVerification() async {
    if (!_canStart || !_beginOperation()) return;
    final epoch = _formEpoch;
    try {
      final result = await widget.currentUser.startPhoneVerification(_e164);
      if (!mounted || epoch != _formEpoch) return;
      setState(() => _challenge = result);
    } finally {
      _finishOperation();
    }
  }

  Future<void> _submitCode() async {
    final ch = _challenge;
    if (ch == null || _code.text.length != 6 || !_beginOperation()) return;
    try {
      switch (widget.intent) {
        case PhoneIntent.signIn:
          await widget.currentUser.signIn(
            SignInRequest.phone(
              phoneNumber: ch.phoneNumber,
              verificationID: ch.verificationID,
              code: _code.text,
            ),
          );
        case PhoneIntent.signUp:
          await widget.currentUser.signUp(
            SignUpRequest.phone(
              phoneNumber: ch.phoneNumber,
              verificationID: ch.verificationID,
              code: _code.text,
              displayName: _displayName.text.trim().isEmpty
                  ? null
                  : _displayName.text.trim(),
            ),
          );
      }
    } finally {
      _finishOperation();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final working =
        _operationPending || widget.currentUser.isPerformingAuthAction;
    if (_challenge != null) {
      return _codeEntryStep(l, working);
    }
    return _phoneEntryStep(l, working);
  }

  Future<void> _selectCountry() async {
    final country = await showPhoneCountryPicker(context);
    if (country != null && mounted) {
      setState(() {
        _country = country;
        _policyAccepted = false;
      });
    }
  }

  Widget _countryPrefix(bool working) {
    final l = AppL10n.of(context);
    final countryLabel = l.phoneCountryCallingCodeLabel(
      phoneCountryName(l, _country.iso),
      _country.callingCode,
    );
    return SizedBox(
      width: 116,
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: countryLabel,
              excludeFromSemantics: true,
              child: TextButton(
                key: const ValueKey('phone-country-selector'),
                style: TextButton.styleFrom(
                  foregroundColor: AetherColors.textPrimary,
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                onPressed: working ? null : _selectCountry,
                child: Semantics(
                  label: countryLabel,
                  excludeSemantics: true,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _country.flag,
                          style: const TextStyle(fontSize: 22),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '+${_country.callingCode}',
                          style: const TextStyle(fontSize: 15),
                        ),
                        const Icon(Icons.arrow_drop_down, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            key: const ValueKey('phone-country-inline-separator'),
            width: 1,
            height: 24,
            color: AetherColors.border,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _phoneEntryStep(AppL10n l, bool working) {
    return Column(
      children: [
        AuthField(
          title: l.authPhoneNumberHint,
          controller: _nationalNumber,
          leading: _isSignUp ? _countryPrefix(working) : null,
          inputFormatters: [LengthLimitingTextInputFormatter(64)],
          keyboard: AuthFieldKeyboard.phone,
          onChanged: (_) => setState(() => _policyAccepted = false),
        ),
        if (_isSignUp) ...[
          const SizedBox(height: AetherSpacing.sm),
          Text(
            _country.mobileExample.isEmpty
                ? l.phoneMobileFormatUnavailable
                : l.phoneMobileExample(_country.mobileExample),
            key: const ValueKey('phone-number-format-help'),
            style: const TextStyle(
              fontSize: 12,
              color: AetherColors.textSecondary,
            ),
          ),
          const SizedBox(height: AetherSpacing.sm),
          Text(
            l.phoneOverseasSignupUnavailable,
            style: const TextStyle(
              fontSize: 12,
              color: AetherColors.textSecondary,
            ),
          ),
        ] else ...[
          const SizedBox(height: AetherSpacing.sm),
          Text(
            l.phoneLoginHelp,
            style: const TextStyle(
              fontSize: 12,
              color: AetherColors.textSecondary,
            ),
          ),
        ],
        if (widget.intent == PhoneIntent.signUp) ...[
          const SizedBox(height: AetherSpacing.md),
          AuthField(
            title: l.authPhoneDisplayNameHint,
            controller: _displayName,
          ),
        ],
        const SizedBox(height: AetherSpacing.lg),
        AuthPrimaryButton(
          title: l.authPhoneSendCode,
          isWorking: working,
          isEnabled:
              _policyAccepted && _canStart && !widget.currentUser.isSignedIn,
          onTap: _startVerification,
        ),
        const SizedBox(height: AetherSpacing.md),
        AuthPolicyConsent(
          value: _policyAccepted,
          enabled: !working,
          onChanged: (value) => setState(() => _policyAccepted = value),
        ),
        const SizedBox(height: AetherSpacing.md),
        if (_canStart)
          Text(
            l.authPhoneWillSend(_e164.isEmpty ? l.authPhoneYourNumber : _e164),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AetherColors.textTertiary,
              height: 1.4,
            ),
          ),
      ],
    );
  }

  Widget _codeEntryStep(AppL10n l, bool working) {
    final ch = _challenge!;
    return Column(
      children: [
        Text(
          l.authPhoneCodeSentTo(ch.phoneNumber),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: AetherColors.textSecondary,
          ),
        ),
        const SizedBox(height: AetherSpacing.md),
        AuthField(
          title: l.authPhoneCodeHint,
          controller: _code,
          keyboard: AuthFieldKeyboard.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: AetherSpacing.lg),
        AuthPrimaryButton(
          title: widget.intent == PhoneIntent.signIn
              ? l.authPhoneSubmitSignIn
              : l.authPhoneSubmitSignUp,
          isWorking: working,
          isEnabled:
              _policyAccepted &&
              _code.text.length == 6 &&
              !widget.currentUser.isSignedIn,
          onTap: _submitCode,
        ),
        const SizedBox(height: AetherSpacing.md),
        AuthPolicyConsent(
          value: _policyAccepted,
          enabled: !working,
          onChanged: (value) => setState(() => _policyAccepted = value),
        ),
        GestureDetector(
          onTap: working
              ? null
              : () {
                  if (_blocked) return;
                  setState(() {
                    _resetConsent();
                  });
                },
          child: Text(
            l.authPhoneChangeNumber,
            style: const TextStyle(
              fontSize: 14,
              color: AetherColors.textSecondary,
              decoration: TextDecoration.underline,
              decorationColor: AetherColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
