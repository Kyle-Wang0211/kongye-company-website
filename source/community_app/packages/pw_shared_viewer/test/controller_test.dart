import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';

void main() {
  test('responses match IDs independently and unknown messages do not settle',
      () async {
    final sent = <Map<String, Object?>>[];
    final controller = SharedViewerController();
    controller.attachTransport((message) async => sent.add(message));
    final first = controller.getState();
    final second = controller.pause();
    controller.receive(jsonEncode({
      'protocol': sharedViewerProtocol,
      'id': 999,
      'ok': true,
      'result': null
    }));
    controller.receive(jsonEncode({
      'protocol': sharedViewerProtocol,
      'id': sent[1]['id'],
      'ok': true,
      'result': null
    }));
    await second;
    controller.receive(jsonEncode({
      'protocol': sharedViewerProtocol,
      'id': sent[0]['id'],
      'ok': true,
      'result': {'status': 'ready'}
    }));
    expect((await first)['status'], 'ready');
    controller.dispose();
  });
  test('dispose fails pending requests and rejects future commands', () async {
    final controller = SharedViewerController();
    controller.attachTransport((_) async {});
    final pending = controller.getState();
    final expectation = expectLater(pending, throwsStateError);
    controller.dispose();
    await expectation;
    expect(controller.getState(), throwsStateError);
  });
  test('transport errors and bridge errors propagate', () async {
    final controller = SharedViewerController();
    controller.attachTransport((message) async {
      controller.receive(jsonEncode({
        'protocol': sharedViewerProtocol,
        'id': message['id'],
        'ok': false,
        'error': {'message': 'bad model'}
      }));
    });
    await expectLater(
        controller.load(
            url: Uri.parse('https://example.test/model.glb'),
            format: SharedModelFormat.glb),
        throwsA(isA<SharedViewerException>()));
    controller.dispose();
  });
  for (final succeeds in [true, false]) {
    test(
        'local resource is released after ${succeeds ? 'successful' : 'failed'} decode',
        () async {
      final controller = SharedViewerController();
      final releases = <Uri>[];
      final local = Uri.parse('http://127.0.0.1:1234/token/models/1.glb');
      controller.attachTransport((message) async {
        expect(releases, isEmpty);
        controller.receive({
          'protocol': sharedViewerProtocol,
          'id': message['id'],
          'ok': succeeds,
          'result': null,
          'error': {'message': 'bad local GLB'},
        });
      }, registerLocal: (_) async => local, releaseResource: releases.add);
      final load = controller.loadLocalFile('/local/final.glb',
          format: SharedModelFormat.glb);
      if (succeeds) {
        await load;
      } else {
        await expectLater(load, throwsA(isA<SharedViewerException>()));
      }
      expect(releases, [local]);
      controller.dispose();
    });
  }
  test('model load rejects executable schemes', () async {
    final controller = SharedViewerController();
    controller.attachTransport((_) async {});
    await expectLater(
        controller.load(
            url: Uri.parse('file:///etc/passwd'),
            format: SharedModelFormat.ply),
        throwsArgumentError);
    controller.dispose();
  });
  test(
      'transport exception and timeout settle requests without leaking pending IDs',
      () async {
    final controller = SharedViewerController(
        requestTimeout: const Duration(milliseconds: 20));
    controller.attachTransport(
        (_) async => throw const SharedViewerException('transport failed'));
    await expectLater(
        controller.getState(), throwsA(isA<SharedViewerException>()));
    controller.detachTransport();
    controller.attachTransport((_) async {});
    await expectLater(controller.getState(), throwsA(isA<TimeoutException>()));
    controller.dispose();
  });
  test('only strict bridge protocol can complete an ID', () async {
    final controller = SharedViewerController();
    late Map<String, Object?> packet;
    controller.attachTransport((value) async {
      packet = value;
    });
    final pending = controller.getState();
    controller.receive({
      'id': packet['id'],
      'ok': true,
      'result': {'status': 'forged'}
    });
    controller.receive({
      'protocol': sharedViewerProtocol,
      'id': packet['id'],
      'ok': true,
      'result': {'status': 'ready'}
    });
    expect((await pending)['status'], 'ready');
    controller.dispose();
  });
  test('late response from replaced controller never completes new controller',
      () async {
    final oldController = SharedViewerController();
    final nextController = SharedViewerController();
    late Map<String, Object?> oldPacket;
    late Map<String, Object?> nextPacket;
    oldController.attachTransport((value) async {
      oldPacket = value;
    });
    final oldPending = oldController.getState();
    final oldFailure = expectLater(oldPending, throwsStateError);
    oldController.detachTransport();
    await oldFailure;
    nextController.attachTransport((value) async {
      nextPacket = value;
    });
    var completed = false;
    final nextPending = nextController.getState().then((value) {
      completed = true;
      return value;
    });
    // A host reroutes channel messages to its new widget.controller.
    nextController.receive({
      'protocol': sharedViewerProtocol,
      'id': oldPacket['id'],
      'ok': true,
      'result': {'status': 'stale'}
    });
    await Future<void>.delayed(Duration.zero);
    final staleCompletedNewController = completed;
    nextController.receive({
      'protocol': sharedViewerProtocol,
      'id': nextPacket['id'],
      'ok': true,
      'result': {'status': 'current'}
    });
    final result = await nextPending;
    oldController.dispose();
    nextController.dispose();
    expect(staleCompletedNewController, isFalse);
    expect(result['status'], 'current');
  });
}
