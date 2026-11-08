import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/auth/wechat_binding.dart';

void main() {
  final start = DateTime.utc(2026, 11, 8);
  late DateTime now;
  late String? owner;
  late List<Map<String, Object?>> requests;
  late Future<Object?> Function(Map<String, Object?>) backend;
  late WechatBindingCoordinator coordinator;
  late WechatBindingPending pending;

  WechatBindingCallback callback({String code = 'proof', String? state}) =>
      WechatBindingCallback.parse(
        Uri(
          fragment: Uri(
            queryParameters: {
              'wechat_code': code,
              'wechat_state': state ?? pending.state,
            },
          ).query,
        ),
      )!;

  Matcher error(WechatBindingFailure reason) =>
      isA<WechatBindingException>().having((e) => e.failure, 'failure', reason);

  setUp(() {
    now = start;
    owner = 'original';
    requests = [];
    backend = (body) async {
      requests.add(body);
      return {'status': 'bound', 'user_id': 'original'};
    };
    coordinator = WechatBindingCoordinator(
      currentUserId: () => owner,
      invokeBinding: (body) => backend(body),
      now: () => now,
    );
    pending = coordinator.beginBind(
      userId: 'original',
      now: start,
      secureRandom: Random(12),
    );
  });

  test('32-byte state roundtrips pending without callback secrets', () {
    expect(pending.state, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(
      pending.expiresAt.difference(pending.createdAt),
      const Duration(minutes: 5),
    );
    final restored = WechatBindingPending.fromJson(pending.toJson());
    expect(restored.state, pending.state);
    expect(restored.expectedUserId, 'original');
    expect(restored.expiresAt, pending.expiresAt);
    expect(
      pending.toJson().keys,
      unorderedEquals(['state', 'expectedUserId', 'createdAt', 'expiresAt']),
    );
  });

  test(
    'only code proof reaches backend; callback identity is untrusted',
    () async {
      final value = WechatBindingCallback.parse(
        Uri.parse(
          'https://app.example/#wechat_code=proof&wechat_state=${pending.state}'
          '&user_id=attacker&openid=attacker&appid=attacker&access_token=secret',
        ),
      )!;
      await coordinator.completeBind(pending: pending, callback: value);
      expect(requests, [
        {'code': 'proof'},
      ]);
      expect(owner, 'original');
      await expectLater(
        coordinator.completeBind(pending: pending, callback: value),
        throwsA(error(WechatBindingFailure.consumed)),
      );
    },
  );

  test('ordinary URI and query-only callback ignored', () {
    expect(
      WechatBindingCallback.parse(Uri.parse('https://app/#/home')),
      isNull,
    );
    expect(
      WechatBindingCallback.parse(Uri.parse('https://app/?wechat_code=proof')),
      isNull,
    );
  });

  test('opaque provider proof survives encoded fragment unchanged', () async {
    for (final code in [
      'code&?#/中文',
      'code+/=',
      '%ZZ',
      'proof😀',
      'a' * 1024,
    ]) {
      pending = coordinator.beginBind(userId: 'original', now: start);
      final value = callback(code: code);
      expect(value.code, code);
      await coordinator.completeBind(pending: pending, callback: value);
      expect(requests.last, {'code': code});
    }
  });

  test('Uri canonicalization preserves opaque percent proof', () {
    // Uri.parse repairs the raw percent escape before the coordinator sees it.
    final value = WechatBindingCallback.parse(
      Uri.parse('https://app/#wechat_code=%ZZ&wechat_state=${pending.state}'),
    )!;
    expect(value.code, '%ZZ');
  });

  test('duplicate malformed and oversized callback rejected generically', () {
    for (final fragment in [
      'wechat_code=a&wechat_code=b&wechat_state=${pending.state}',
      'wechat_code=proof&wechat_state=%ZZ',
      'wechat_code=a&wechat_state=short',
      'wechat_code=%20%0A&wechat_state=${pending.state}',
      'wechat_code=%FF&wechat_state=${pending.state}',
      'wechat_code=&wechat_state=${pending.state}',
      'wechat_code=${'a' * 1025}&wechat_state=${pending.state}',
      'wechat_code=a&wechat_state=${pending.state}&wechat_error=wechat_login_failed',
      'wechat_error=raw-secret&wechat_state=${pending.state}',
    ]) {
      expect(
        () => WechatBindingCallback.parse(Uri.parse('https://app/#$fragment')),
        throwsA(error(WechatBindingFailure.invalidCallback)),
      );
    }
  });

  test('wrong state consumes attempt without invoking backend', () async {
    await expectLater(
      coordinator.completeBind(
        pending: pending,
        callback: callback(state: 'a' * 43),
      ),
      throwsA(error(WechatBindingFailure.stateMismatch)),
    );
    await expectLater(
      coordinator.completeBind(pending: pending, callback: callback()),
      throwsA(error(WechatBindingFailure.consumed)),
    );
    expect(requests, isEmpty);
  });

  test('expires at five minutes and rejects future creation', () async {
    now = pending.expiresAt;
    await expectLater(
      coordinator.completeBind(pending: pending, callback: callback()),
      throwsA(error(WechatBindingFailure.expired)),
    );
    expect(requests, isEmpty);
    pending = coordinator.beginBind(userId: 'original', now: start);
    now = start.subtract(const Duration(seconds: 1));
    await expectLater(
      coordinator.completeBind(pending: pending, callback: callback()),
      throwsA(error(WechatBindingFailure.expired)),
    );
  });

  test('provider fixed failure consumes pending', () async {
    final value = WechatBindingCallback.parse(
      Uri.parse(
        'https://app/#wechat_error=wechat_login_failed&wechat_state=${pending.state}',
      ),
    )!;
    await expectLater(
      coordinator.completeBind(pending: pending, callback: value),
      throwsA(error(WechatBindingFailure.providerRejected)),
    );
    expect(requests, isEmpty);
  });

  test('cancel invalidates pending', () async {
    coordinator.cancel(pending);
    await expectLater(
      coordinator.completeBind(pending: pending, callback: callback()),
      throwsA(error(WechatBindingFailure.consumed)),
    );
    expect(requests, isEmpty);
  });

  test('switch or logout before callback cannot bind', () async {
    for (final newOwner in ['other', null]) {
      owner = 'original';
      pending = coordinator.beginBind(userId: 'original', now: start);
      owner = newOwner;
      await expectLater(
        coordinator.completeBind(pending: pending, callback: callback()),
        throwsA(error(WechatBindingFailure.accountChanged)),
      );
    }
    expect(requests, isEmpty);
  });

  test('switch during await cannot report success', () async {
    final response = Completer<Object?>();
    backend = (_) => response.future;
    final result = coordinator.completeBind(
      pending: pending,
      callback: callback(),
    );
    owner = 'other';
    final assertion = expectLater(
      result,
      throwsA(error(WechatBindingFailure.accountChanged)),
    );
    response.complete({'status': 'bound', 'user_id': 'original'});
    await assertion;
  });

  test(
    'concurrent replay and deserialized replay cannot invoke twice',
    () async {
      final response = Completer<Object?>();
      var calls = 0;
      backend = (_) {
        calls++;
        return response.future;
      };
      final result = coordinator.completeBind(
        pending: pending,
        callback: callback(),
      );
      final restored = WechatBindingPending.fromJson(pending.toJson());
      await expectLater(
        coordinator.completeBind(pending: restored, callback: callback()),
        throwsA(error(WechatBindingFailure.consumed)),
      );
      response.complete({'status': 'bound', 'user_id': 'original'});
      await result;
      expect(calls, 1);
    },
  );

  test('expired during await cannot report success', () async {
    final response = Completer<Object?>();
    backend = (_) => response.future;
    final result = coordinator.completeBind(
      pending: pending,
      callback: callback(),
    );
    now = pending.expiresAt;
    final assertion = expectLater(
      result,
      throwsA(error(WechatBindingFailure.expired)),
    );
    response.complete({'status': 'bound', 'user_id': 'original'});
    await assertion;
  });

  test('cancel during await cannot report success', () async {
    final response = Completer<Object?>();
    backend = (_) => response.future;
    final result = coordinator.completeBind(
      pending: pending,
      callback: callback(),
    );
    coordinator.cancel(pending);
    final assertion = expectLater(
      result,
      throwsA(error(WechatBindingFailure.cancelled)),
    );
    response.complete({'status': 'bound', 'user_id': 'original'});
    await assertion;
  });

  test('wrong user or malformed backend response fails', () async {
    for (final response in [
      {'status': 'bound', 'user_id': 'attacker'},
      {'status': 'signed_in', 'user_id': 'original'},
      null,
    ]) {
      pending = coordinator.beginBind(userId: 'original', now: start);
      backend = (_) async => response;
      await expectLater(
        coordinator.completeBind(pending: pending, callback: callback()),
        throwsA(error(WechatBindingFailure.invalidResponse)),
      );
    }
  });

  test('backend exception sanitized and consumes attempt', () async {
    backend = (_) async => throw StateError('secret-token-url');
    try {
      await coordinator.completeBind(pending: pending, callback: callback());
      fail('expected failure');
    } on WechatBindingException catch (e) {
      expect(e.failure, WechatBindingFailure.backendFailed);
      expect(e.toString(), isNot(contains('secret')));
    }
    await expectLater(
      coordinator.completeBind(pending: pending, callback: callback()),
      throwsA(error(WechatBindingFailure.consumed)),
    );
  });
}
