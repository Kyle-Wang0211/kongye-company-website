import '../config/backend_deployment.dart';
import 'auth_models.dart';

/// Maps account input to one credential type without changing the password.
/// A national mobile number has an implicit +86 only in the China deployment.
SignInRequest? passwordSignInRequest({
  required String account,
  required String password,
  required BackendRegion region,
}) {
  if (password.length < 6 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(account)) {
    return null;
  }
  final value = account.trim();
  if (value.contains('@')) {
    if (!RegExp(r'^[^\s@/\\]+@[^\s@/\\]+\.[^\s@/\\]+$').hasMatch(value)) {
      return null;
    }
    return SignInRequest.email(email: value.toLowerCase(), password: password);
  }
  if (!RegExp(r'^[+0-9 ()-]+$').hasMatch(value)) return null;
  var phone = value.replaceAll(RegExp(r'[ ()-]'), '');
  if (phone.startsWith('00')) {
    phone = '+${phone.substring(2)}';
  } else if (region == BackendRegion.china) {
    if (RegExp(r'^1[3-9][0-9]{9}$').hasMatch(phone)) {
      phone = '+86$phone';
    } else if (RegExp(r'^861[3-9][0-9]{9}$').hasMatch(phone)) {
      phone = '+$phone';
    }
  }
  if (phone.startsWith('+86') &&
      !RegExp(r'^\+861[3-9][0-9]{9}$').hasMatch(phone)) {
    return null;
  }
  if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(phone)) return null;
  return SignInRequest.phonePassword(phoneNumber: phone, password: password);
}
