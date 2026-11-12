import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/community/web_publication_service.dart';

class _HeaderPorts implements WebPublicationPorts {
  final calls = <Map<String, dynamic>>[];
  @override
  String get userId => '00000000-0000-4000-8000-000000000001';
  @override
  Uri get apiOrigin => Uri.parse('https://api.kongye.space');
  @override
  Future<Map<String, dynamic>> invoke(Map<String, dynamic> body) async {
    calls.add(body);
    throw StateError('Stop after source validation');
  }

  @override
  Future<void> upload({
    required String path,
    required String token,
    required Uint8List bytes,
    String bucket = 'publication-staging',
    void Function(int sent, int total)? onBytesSent,
  }) async => throw StateError('Upload must remain unreachable');
}

void main() {
  for (final lineEnding in ['\n', '\r\n']) {
    test('PLY header accepts ${lineEnding.codeUnits}', () async {
      final ports = _HeaderPorts();
      final service = WebPublicationService.forTest(ports);
      await expectLater(
        service.submit(
          bytes: Uint8List.fromList(
            utf8.encode(
              'ply${lineEnding}format ascii 1.0${lineEnding}end_header$lineEnding',
            ),
          ),
          format: 'ply',
          title: 'PLY',
          idempotencyKey: '00000000-0000-4000-8000-000000000002',
          onSubmissionCreated: (_) {},
        ),
        throwsA(
          isA<WebPublicationException>().having(
            (e) => e.code,
            'code',
            'submission_unavailable',
          ),
        ),
      );
      expect(ports.calls.single['action'], 'initiate');
      expect(ports.calls.single['format'], 'ply');
    });
  }
}
