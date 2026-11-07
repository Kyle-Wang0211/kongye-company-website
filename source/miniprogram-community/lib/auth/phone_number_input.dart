import '../config/backend_deployment.dart';
import 'auth_models.dart';
import 'password_sign_in.dart';
import 'phone_country_catalog.dart';

/// Reuses the existing credential normalizer without transmitting a password.
/// SMS login retains legacy bare mainland numbers; overseas numbers need +/00.
String? normalizePhoneLogin(String input) {
  final request = passwordSignInRequest(
    account: input,
    password: 'unused',
    region: BackendRegion.china,
  );
  return request is SignInRequestPhonePassword ? request.phoneNumber : null;
}

/// Canonical national digits only, not a general-purpose phone parser.
/// Explicit international input must match the selected calling code. National
/// prefixes and significant leading zeroes are never removed or transformed.
String? canonicalSignupNationalNumber(String input, PhoneCountry country) {
  if (input.length > 64) return null;
  if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(input)) return null;
  if (!RegExp(r'^[+0-9 ()-]+$').hasMatch(input.trim())) return null;
  var digits = input.trim().replaceAll(RegExp(r'[ ()-]'), '');
  if (digits.startsWith('00')) digits = '+${digits.substring(2)}';
  if (digits.startsWith('+')) {
    final prefix = '+${country.callingCode}';
    if (!digits.startsWith(prefix)) return null;
    digits = digits.substring(prefix.length);
  }
  if (digits.length > 15) return null;
  return RegExp(r'^[0-9]+$').hasMatch(digits) ? digits : null;
}

/// Validates canonical MOBILE format against pinned upstream metadata.
/// A format match does not establish reachability or SMS delivery support.
String? normalizePhoneSignup(String input, PhoneCountry country) {
  final national = canonicalSignupNationalNumber(input, country);
  if (national == null || country.mobilePattern.isEmpty) return null;
  if (!RegExp('^(?:${country.mobilePattern})\$').hasMatch(national)) {
    return null;
  }
  final phone = '+${country.callingCode}$national';
  return RegExp(r'^\+[1-9][0-9]{0,14}$').hasMatch(phone) ? phone : null;
}
