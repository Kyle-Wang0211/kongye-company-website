import 'dart:convert';
import 'dart:math';
import '../util/wechat_sign_in_platform.dart';
import 'auth_models.dart';
import 'wechat_binding.dart' show WechatBindingCallback;
import 'wechat_sign_in_port.dart';

final wechatSignInFlow = WechatSignInFlow(port: createWechatSignInPort());

enum WechatSignInFailure {
  unavailable,
  invalidCallback,
  expired,
  cancelled,
  accountPresent,
}

/// A one-shot, five-minute login intention. Only its nonce and timestamp cross
/// a webview reload. Codes and tokens are never persisted or placed in a query.
class WechatSignInFlow {
  WechatSignInFlow({required WechatSignInPort port, DateTime Function()? now})
    : _port = port,
      _now = now ?? DateTime.now;
  final WechatSignInPort _port;
  final DateTime Function() _now;
  SignInRequestWechat? _captured;
  DateTime? _createdAt;
  WechatSignInFailure? lastFailure;
  bool get available => _port.available;

  bool begin() {
    cancel();
    lastFailure = null;
    try {
      if (!available) throw StateError('unavailable');
      final random = Random.secure();
      final nonce = base64Url
          .encode(List<int>.generate(32, (_) => random.nextInt(256)))
          .replaceAll('=', '');
      _port.writePending(
        jsonEncode({
          'nonce': nonce,
          'createdAt': _now().toUtc().toIso8601String(),
        }),
      );
      if (!_port.navigate(nonce)) throw StateError('unavailable');
      return true;
    } catch (_) {
      cancel();
      lastFailure = WechatSignInFailure.unavailable;
      return false;
    }
  }

  void captureCallback() {
    try {
      final fragment = _port.takeFragment();
      if (fragment.isEmpty) return;
      _captured = null;
      final stored = _port.readPending();
      _port.clearPending(); // Consume before validation and before async work.
      if (!available || stored == null) throw const FormatException();
      final data = jsonDecode(stored) as Map;
      final callback = WechatBindingCallback.parse(Uri(fragment: fragment));
      final createdAt = DateTime.parse(data['createdAt'] as String).toUtc();
      final nonce = data['nonce'];
      if (data.length != 2 ||
          callback == null ||
          callback.providerFailed ||
          callback.state != nonce) {
        throw const FormatException();
      }
      if (!_fresh(createdAt)) {
        lastFailure = WechatSignInFailure.expired;
        return;
      }
      _createdAt = createdAt;
      _captured = SignInRequestWechat(
        code: callback.code!,
        nonce: nonce as String,
      );
    } catch (_) {
      _captured = null;
      _createdAt = null;
      try {
        _port.clearPending();
      } catch (_) {}
      lastFailure = WechatSignInFailure.invalidCallback;
    }
  }

  SignInRequestWechat? consumeCallback({required bool signedOut}) {
    final request = _captured;
    final createdAt = _createdAt;
    _captured = null;
    _createdAt = null;
    if (!signedOut) {
      lastFailure = WechatSignInFailure.accountPresent;
      return null;
    }
    if (request == null || createdAt == null) return null;
    if (!_fresh(createdAt)) {
      lastFailure = WechatSignInFailure.expired;
      return null;
    }
    return request;
  }

  bool _fresh(DateTime createdAt) {
    final now = _now().toUtc();
    return !now.isBefore(createdAt) &&
        now.isBefore(createdAt.add(const Duration(minutes: 5)));
  }

  void cancel() {
    _captured = null;
    _createdAt = null;
    try {
      _port.clearPending();
    } catch (_) {}
    lastFailure = WechatSignInFailure.cancelled;
  }
}
