import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/community/web_publication_service.dart';

const uid = '11111111-1111-4111-8111-111111111111';
const sid = '22222222-2222-4222-8222-222222222222';
const key = '33333333-3333-4333-8333-333333333333';

class Ports implements WebPublicationPorts {
  String? active = uid;
  @override
  String? get userId => active;
  @override
  Uri get apiOrigin => Uri.parse('https://api.example.test');
  final calls = <Map<String, dynamic>>[];
  bool wrongOrigin = false,
      wrongPath = false,
      uploaded = false,
      swapOnInitiate = false,
      swapOnSeal = false;
  String state = 'processing';
  @override
  Future<Map<String, dynamic>> invoke(Map<String, dynamic> body) async {
    calls.add(body);
    if (body['action'] == 'initiate') {
      if (swapOnInitiate) active = key;
      final bucket = body['selection_box'] == null
          ? 'publication-staging'
          : 'publication-selection-staging';
      final path = '${wrongPath ? key : uid}/$sid/source.glb';
      return {
        'ok': true,
        'submission_id': sid,
        'status': 'uploading',
        'upload': {
          'bucket': bucket,
          'path': path,
          'token': 'token',
          'signed_url':
              '${wrongOrigin ? 'https://wrong.test' : apiOrigin.origin}/storage/v1/object/upload/sign/$bucket/$path?token=token',
        },
      };
    }
    if (body['action'] == 'seal' && swapOnSeal) active = key;
    return {
      'ok': true,
      'submission_id': sid,
      'status': body['action'] == 'seal' ? 'queued' : state,
    };
  }

  @override
  Future<void> upload({
    required String path,
    required String token,
    required Uint8List bytes,
    String bucket = 'publication-staging',
    void Function(int, int)? onBytesSent,
  }) async {
    uploaded = true;
    onBytesSent?.call(bytes.length, bytes.length);
  }
}

Uint8List glb() {
  final b = Uint8List(20);
  b.setAll(0, [0x67, 0x6c, 0x54, 0x46]);
  final d = ByteData.sublistView(b);
  d.setUint32(4, 2, Endian.little);
  d.setUint32(8, b.length, Endian.little);
  return b;
}

void main() {
  Future<WebPublicationStatus> submit(
    WebPublicationService s, {
    Uint8List? bytes,
    String title = '作品',
    String description = '',
    Map<String, dynamic>? box,
    FutureOr<void> Function(String)? created,
  }) => s.submit(
    bytes: bytes ?? glb(),
    title: title,
    description: description,
    idempotencyKey: key,
    selectionBox: box,
    onSubmissionCreated: created ?? (_) {},
  );
  test('real initiate upload seal; queued is not published', () async {
    final p = Ports();
    final s = WebPublicationService.forTest(p);
    final result = await submit(s);
    expect(p.uploaded, true);
    expect(result.status, 'queued');
    expect(result.workId, isNull);
    expect(p.calls.map((c) => c['action']), ['initiate', 'seal']);
    expect(p.calls.first['idempotency_key'], key);
    expect(p.calls.first['source_sha256'], matches(RegExp(r'^[a-f0-9]{64}$')));
  });
  test('selection uses separate private staging', () async {
    final p = Ports();
    await submit(WebPublicationService.forTest(p), box: {'cx': 0});
    expect(p.uploaded, true);
    expect(p.calls.first['selection_box'], {'cx': 0});
  });
  for (final attack in ['origin', 'path']) {
    test('rejects signed upload $attack mismatch', () async {
      final p = Ports()
        ..wrongOrigin = attack == 'origin'
        ..wrongPath = attack == 'path';
      await expectLater(
        submit(WebPublicationService.forTest(p)),
        throwsA(isA<WebPublicationException>()),
      );
      expect(p.uploaded, false);
    });
  }
  test('account change fences initiate response before draft saved', () async {
    final p = Ports()..swapOnInitiate = true;
    var saved = false;
    await expectLater(
      submit(
        WebPublicationService.forTest(p),
        created: (_) {
          saved = true;
        },
      ),
      throwsA(isA<WebPublicationException>()),
    );
    expect(saved, false);
    expect(p.uploaded, false);
  });
  test('account change fences seal status', () async {
    final p = Ports()..swapOnSeal = true;
    await expectLater(
      submit(WebPublicationService.forTest(p)),
      throwsA(isA<WebPublicationException>()),
    );
  });
  test('same service cannot poll submission under new account', () async {
    final p = Ports();
    final s = WebPublicationService.forTest(p);
    p.active = key;
    await expectLater(
      s.getStatus(sid),
      throwsA(isA<WebPublicationException>()),
    );
    expect(p.calls, isEmpty);
  });
  test('rejects malformed GLB before API', () async {
    final p = Ports();
    await expectLater(
      submit(WebPublicationService.forTest(p), bytes: Uint8List(20)),
      throwsA(isA<WebPublicationException>()),
    );
    expect(p.calls, isEmpty);
  });
  test('unicode limits count code points', () async {
    final p = Ports();
    await submit(
      WebPublicationService.forTest(p),
      title: List.filled(100, '😀').join(),
      description: List.filled(30, '😀').join(),
    );
    expect(p.uploaded, true);
  });
  test('overlong title rejected before API', () async {
    final p = Ports();
    await expectLater(
      submit(
        WebPublicationService.forTest(p),
        title: List.filled(101, '字').join(),
      ),
      throwsA(isA<WebPublicationException>()),
    );
    expect(p.calls, isEmpty);
  });
  test('unknown server status fails closed', () async {
    final p = Ports()..state = 'complete';
    await expectLater(
      WebPublicationService.forTest(p).getStatus(sid),
      throwsA(isA<WebPublicationException>()),
    );
  });
  test('cancel uses authenticated owner and exact submission id', () async {
    final ports = Ports()..state = 'cancelled';
    final result = await WebPublicationService.forTest(ports).cancel(sid);
    expect(result.status, 'cancelled');
    expect(ports.calls.single, {'action': 'cancel', 'submission_id': sid});
  });
  test('cancel cannot run under another account', () async {
    final ports = Ports();
    final service = WebPublicationService.forTest(ports);
    ports.active = key;
    await expectLater(
      service.cancel(sid),
      throwsA(isA<WebPublicationException>()),
    );
    expect(ports.calls, isEmpty);
  });
}
