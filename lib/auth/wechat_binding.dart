import 'dart:convert';
import 'dart:math';

enum WechatBindingFailure {
  invalidPending,
  invalidCallback,
  stateMismatch,
  expired,
  consumed,
  cancelled,
  accountChanged,
  providerRejected,
  backendFailed,
  invalidResponse,
}

/// Contains only a fixed reason, never provider text, credentials or URLs.
class WechatBindingException implements Exception {
  const WechatBindingException(this.failure);
  final WechatBindingFailure failure;

  @override
  String toString() => 'WechatBindingException(${failure.name})';
}

final _statePattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

class WechatBindingPending {
  WechatBindingPending({
    required this.state,
    required this.expectedUserId,
    required DateTime createdAt,
    required DateTime expiresAt,
  }) : createdAt = createdAt.toUtc(),
       expiresAt = expiresAt.toUtc() {
    if (!_statePattern.hasMatch(state) ||
        expectedUserId.trim().isEmpty ||
        this.expiresAt.difference(this.createdAt) !=
            const Duration(minutes: 5)) {
      throw const WechatBindingException(WechatBindingFailure.invalidPending);
    }
  }

  final String state;
  final String expectedUserId;
  final DateTime createdAt;
  final DateTime expiresAt;

  /// Suitable for session-scoped storage; no authorization code is persisted.
  Map<String, Object?> toJson() => {
    'state': state,
    'expectedUserId': expectedUserId,
    'createdAt': createdAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
  };

  factory WechatBindingPending.fromJson(Map<String, Object?> json) {
    try {
      return WechatBindingPending(
        state: json['state'] as String,
        expectedUserId: json['expectedUserId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      );
    } catch (_) {
      throw const WechatBindingException(WechatBindingFailure.invalidPending);
    }
  }
}

class WechatBindingCallback {
  const WechatBindingCallback._(this.state, this.code);
  final String state;
  final String? code;
  bool get providerFailed => code == null;

  /// Reads only the native helper's fragment contract. Query parameters are
  /// never callback credentials, and callback identity/session fields are ignored.
  static WechatBindingCallback? parse(Uri uri) {
    final fragment = uri.fragment;
    // Avoid parsing ordinary application routes as OAuth results.
    if (!RegExp(r'(^|&)wechat_(code|state|error)(=|&|$)').hasMatch(fragment)) {
      return null;
    }
    try {
      if (fragment.length > 8192 ||
          RegExp(r'%(?![0-9A-Fa-f]{2})').hasMatch(fragment)) {
        throw const FormatException();
      }
      final fields = Uri.splitQueryString(fragment); // validated again below
      final seen = <String>{};
      for (final pair in fragment.split('&')) {
        final equals = pair.indexOf('=');
        if (equals < 1) throw const FormatException();
        final key = Uri.decodeQueryComponent(pair.substring(0, equals));
        if (!seen.add(key)) throw const FormatException();
      }
      final state = fields['wechat_state'];
      final code = fields['wechat_code'];
      final error = fields['wechat_error'];
      if (state == null ||
          !_statePattern.hasMatch(state) ||
          (code == null) == (error == null) ||
          (code != null && (code.trim().isEmpty || code.length > 1024)) ||
          (error != null && error != 'wechat_login_failed')) {
        throw const FormatException();
      }
      return WechatBindingCallback._(state, code);
    } catch (_) {
      throw const WechatBindingException(WechatBindingFailure.invalidCallback);
    }
  }
}

/// Binds a WeChat proof to the existing account. This never issues sessions or
/// changes the signed-in user. The supplied port authenticates with the existing
/// backend session and receives exactly {'code': proof}.
///
/// Runtime glue must atomically remove persisted pending state before invoking
/// completion, and cancel on auth changes. The in-memory replay guard survives
/// pending serialization but cannot survive a whole page/process restart.
class WechatBindingCoordinator {
  WechatBindingCoordinator({
    required String? Function() currentUserId,
    required Future<Object?> Function(Map<String, Object?> body) invokeBinding,
    DateTime Function()? now,
  }) : _currentUserId = currentUserId,
       _invokeBinding = invokeBinding,
       _now = now ?? DateTime.now;

  final String? Function() _currentUserId;
  final Future<Object?> Function(Map<String, Object?>) _invokeBinding;
  final DateTime Function() _now;
  final Set<String> _consumed = {};
  final Set<String> _cancelled = {};

  WechatBindingPending beginBind({
    required String userId,
    required DateTime now,
    Random? secureRandom,
  }) {
    _requireOwner(userId);
    final random = secureRandom ?? Random.secure();
    final state = base64Url
        .encode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    return WechatBindingPending(
      state: state,
      expectedUserId: userId,
      createdAt: now,
      expiresAt: now.add(const Duration(minutes: 5)),
    );
  }

  void cancel(WechatBindingPending pending) {
    _cancelled.add(pending.state);
    _consumed.add(pending.state);
  }

  Future<void> completeBind({
    required WechatBindingPending pending,
    required WechatBindingCallback callback,
  }) async {
    // Consume before all checks and before awaiting: failure is not retryable.
    if (!_consumed.add(pending.state)) {
      throw const WechatBindingException(WechatBindingFailure.consumed);
    }
    _requireOwner(pending.expectedUserId);
    _requireFresh(pending);
    if (callback.state != pending.state) {
      throw const WechatBindingException(WechatBindingFailure.stateMismatch);
    }
    if (callback.providerFailed) {
      throw const WechatBindingException(WechatBindingFailure.providerRejected);
    }
    Object? response;
    try {
      response = await _invokeBinding({'code': callback.code!});
    } catch (_) {
      throw const WechatBindingException(WechatBindingFailure.backendFailed);
    }
    _requireOwner(pending.expectedUserId);
    if (_cancelled.contains(pending.state)) {
      throw const WechatBindingException(WechatBindingFailure.cancelled);
    }
    _requireFresh(pending);
    if (response is! Map ||
        response['status'] != 'bound' ||
        response['user_id'] != pending.expectedUserId) {
      throw const WechatBindingException(WechatBindingFailure.invalidResponse);
    }
  }

  void _requireOwner(String expected) {
    try {
      if (expected.isNotEmpty && _currentUserId() == expected) return;
    } catch (_) {
      // Getter failures are not evidence that the account is still present.
    }
    throw const WechatBindingException(WechatBindingFailure.accountChanged);
  }

  void _requireFresh(WechatBindingPending pending) {
    final current = _now().toUtc();
    if (current.isBefore(pending.createdAt) ||
        !current.isBefore(pending.expiresAt)) {
      throw const WechatBindingException(WechatBindingFailure.expired);
    }
  }
}
