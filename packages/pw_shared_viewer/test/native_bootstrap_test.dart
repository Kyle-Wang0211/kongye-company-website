import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pw_shared_viewer/src/native_bootstrap.dart';

void main() {
  const hash =
      '4aebce55e188bc80e89322ce67358fc4cf816aff83da13f12dbae2e269e8fbb4';

  test('ordinary iOS host and other platforms never load the optional bridge',
      () async {
    for (final config in [(true, ''), (false, hash)]) {
      var registrations = 0;
      final bootstrap = NativeWebViewBootstrap(
        isIOS: config.$1,
        expectedRawSha256: config.$2,
        register: (_) async {
          registrations++;
        },
      );
      expect(bootstrap.requiresRegistration, isFalse);
      final controller = await bootstrap.createController(
        create: () => 'existing host',
        isDisposed: () => false,
      );
      expect(controller, 'existing host');
      expect(registrations, 0);
    }
  });

  test('controller creation waits for the registration boundary', () async {
    final gate = Completer<void>();
    final events = <String>[];
    final bootstrap = NativeWebViewBootstrap(
      isIOS: true,
      expectedRawSha256: hash,
      register: (actualHash) {
        expect(actualHash, hash);
        events.add('register');
        return gate.future;
      },
    );
    final controller = bootstrap.createController(
      create: () {
        events.add('controller');
        return 1;
      },
      isDisposed: () => false,
    );
    await Future<void>.delayed(Duration.zero);
    expect(events, ['register']);
    gate.complete();
    expect(await controller, 1);
    expect(events, ['register', 'controller']);
  });

  test('concurrent viewer requests share one outstanding registration',
      () async {
    final gate = Completer<void>();
    var registrations = 0;
    final bootstrap = NativeWebViewBootstrap(
      isIOS: true,
      expectedRawSha256: hash,
      register: (_) {
        registrations++;
        return gate.future;
      },
    );
    final first =
        bootstrap.createController(create: () => 1, isDisposed: () => false);
    final second =
        bootstrap.createController(create: () => 2, isDisposed: () => false);
    expect(registrations, 1);
    gate.complete();
    expect(await Future.wait([first, second]), [1, 2]);
    await bootstrap.ensureRegistered();
    expect(registrations, 2,
        reason: 'Completed success must revalidate the engine.');
  });

  test('registration failure reaches all callers without creating controllers',
      () async {
    final gate = Completer<void>();
    final failure = StateError('reserved unpublished key');
    var creations = 0;
    var registrations = 0;
    final bootstrap = NativeWebViewBootstrap(
      isIOS: true,
      expectedRawSha256: hash,
      register: (_) {
        registrations++;
        return gate.future;
      },
    );
    final first = bootstrap.createController(
        create: () => ++creations, isDisposed: () => false);
    final second = bootstrap.createController(
        create: () => ++creations, isDisposed: () => false);
    final checks = [
      expectLater(first, throwsA(same(failure))),
      expectLater(second, throwsA(same(failure))),
    ];
    gate.completeError(failure);
    await Future.wait(checks);
    expect(creations, 0);
    await expectLater(bootstrap.ensureRegistered(), throwsA(same(failure)));
    expect(registrations, 2, reason: 'Failed request must not poison retries.');
  });

  test('synchronous boundary failures are propagated and retryable', () async {
    var calls = 0;
    final bootstrap = NativeWebViewBootstrap(
      isIOS: true,
      expectedRawSha256: hash,
      register: (_) {
        calls++;
        throw ArgumentError('bad hash');
      },
    );
    await expectLater(bootstrap.ensureRegistered(), throwsArgumentError);
    await expectLater(bootstrap.ensureRegistered(), throwsArgumentError);
    expect(calls, 2);
  });

  test(
      'disposed viewer does not create a controller after pending registration',
      () async {
    final gate = Completer<void>();
    var disposed = false;
    var creations = 0;
    final bootstrap = NativeWebViewBootstrap(
      isIOS: true,
      expectedRawSha256: hash,
      register: (_) => gate.future,
    );
    final controller = bootstrap.createController(
      create: () => ++creations,
      isDisposed: () => disposed,
    );
    disposed = true;
    gate.complete();
    expect(await controller, isNull);
    expect(creations, 0);
  });

  test('native entry rejects an unsupported host before loading a framework',
      () async {
    await expectLater(
      ensureNativeWebViewRegistered(expectedRawSha256: 'bad'),
      // The host test process is non-iOS, so platform validation rejects first.
      throwsUnsupportedError,
    );
  });
}
