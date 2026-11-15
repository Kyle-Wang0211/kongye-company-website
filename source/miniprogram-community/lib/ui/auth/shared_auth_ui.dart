// ignore_for_file: unnecessary_library_name
library pw_shared_auth_ui;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../auth/auth_error.dart';
import '../../auth/auth_models.dart';
import '../../auth/auth_service.dart';
import '../../auth/current_user.dart';
import '../../auth/password_sign_in.dart';
import '../../auth/phone_country_catalog.dart';
import '../../auth/phone_number_input.dart';
import '../../config/backend_deployment.dart';
import '../../i18n/locale_notifier.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/phone_country_names.dart';
import '../design_system.dart';
import '../legal/legal_doc_links_row.dart';

part 'package:pw_shared_auth/src/auth_minimal_widgets.dart';
part 'package:pw_shared_auth/src/auth_policy_consent.dart';
part 'package:pw_shared_auth/src/auth_root_view.dart';
part 'package:pw_shared_auth/src/auth_shared_widgets.dart';
part 'package:pw_shared_auth/src/email_sign_in_view.dart';
part 'package:pw_shared_auth/src/login_code_view.dart';
part 'package:pw_shared_auth/src/otp_verification_view.dart';
part 'package:pw_shared_auth/src/phone_country_picker.dart';
part 'package:pw_shared_auth/src/phone_sign_in_view.dart';
part 'package:pw_shared_auth/src/reset_password_view.dart';
part 'package:pw_shared_auth/src/phone_reset_password_view.dart';

bool get _sharedSignupNeedsPassword => true;
String? _sharedPendingPassword(EmailVerificationPending pending) =>
    pending.password;
Future<bool> _sharedVerifySignup(
  CurrentUser user, {
  required String email,
  required String token,
  String? password,
}) =>
    user.verifySignupOtp(email: email, token: token, password: password ?? '');
Future<bool> _sharedResendSignup(
  CurrentUser user, {
  required String email,
  String? password,
}) => user.resendSignupOtp(email: email, password: password ?? '');

bool get _sharedQrAvailable => false;
void _sharedOpenQrLogin(BuildContext context) {}
