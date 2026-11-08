import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/auth/wechat_sign_in.dart';
import 'package:pocketworld_flutter/auth/wechat_sign_in_port.dart';

class Port implements WechatSignInPort {
  @override
  bool get available => true;
  String? pending;
  String fragment = '';
  String? navigated;
  @override
  String? readPending() => pending;
  @override
  void writePending(String value) {
    pending = value;
  }

  @override
  void clearPending() {
    pending = null;
  }

  @override
  String takeFragment() {
    final value = fragment;
    fragment = '';
    return value;
  }

  @override
  bool navigate(String state) {
    navigated = state;
    return true;
  }
}

void main() {
  late Port port;
  late DateTime now;
  late WechatSignInFlow flow;
  setUp(() {
    port = Port();
    now = DateTime.utc(2026, 11, 8);
    flow = WechatSignInFlow(port: port, now: () => now);
  });
  void callback({String? state}) {
    port.fragment =
        'wechat_code=fresh-code&wechat_state=${state ?? port.navigated}';
    flow.captureCallback();
  }

  test('secure nonce has 32 bytes; only nonce/time persists; consume once', () {
    expect(flow.begin(), isTrue);
    expect(port.navigated, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(base64Url.decode('${port.navigated}='), hasLength(32));
    expect(
      (jsonDecode(port.pending!) as Map).keys,
      unorderedEquals(['nonce', 'createdAt']),
    );
    callback();
    expect(port.fragment, isEmpty);
    expect(port.pending, isNull);
    final request = flow.consumeCallback(signedOut: true)!;
    expect(request.code, 'fresh-code');
    expect(request.nonce, port.navigated);
    expect(flow.consumeCallback(signedOut: true), isNull);
  });
  test('reload recovers pending; callback rejects already logged in', () {
    flow.begin();
    flow = WechatSignInFlow(port: port, now: () => now);
    callback();
    expect(flow.consumeCallback(signedOut: false), isNull);
    expect(flow.consumeCallback(signedOut: true), isNull);
  });
  test(
    'mismatch, expiry, future timestamps and replay do not authenticate',
    () {
      flow.begin();
      callback(state: 'A' * 43);
      expect(flow.consumeCallback(signedOut: true), isNull);
      flow.begin();
      now = now.add(const Duration(minutes: 5));
      callback();
      expect(flow.consumeCallback(signedOut: true), isNull);
      flow.begin();
      now = now.subtract(const Duration(seconds: 1));
      callback();
      expect(flow.consumeCallback(signedOut: true), isNull);
      now = now.add(const Duration(seconds: 2));
      flow.begin();
      callback();
      expect(flow.consumeCallback(signedOut: true), isNotNull);
      callback();
      expect(flow.consumeCallback(signedOut: true), isNull);
    },
  );
  test('logout cancels both stored and captured callbacks', () {
    flow.begin();
    flow.cancel();
    callback();
    expect(flow.consumeCallback(signedOut: true), isNull);
    flow.begin();
    callback();
    flow.cancel();
    expect(flow.consumeCallback(signedOut: true), isNull);
  });
  test(
    'provider errors and malformed duplicate fields are removed and rejected',
    () {
      flow.begin();
      port.fragment =
          'wechat_error=wechat_login_failed&wechat_state=${port.navigated}';
      flow.captureCallback();
      expect(flow.consumeCallback(signedOut: true), isNull);
      expect(port.fragment, isEmpty);
      flow.begin();
      port.fragment =
          'wechat_code=a&wechat_code=b&wechat_state=${port.navigated}';
      flow.captureCallback();
      expect(flow.consumeCallback(signedOut: true), isNull);
      expect(port.pending, isNull);
    },
  );
}
