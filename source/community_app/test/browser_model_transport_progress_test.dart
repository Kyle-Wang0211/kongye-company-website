import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pocketworld_flutter/ui/shared/browser_model_transport.dart';

class ChunkClient extends http.BaseClient {
  ChunkClient(this.chunks, this.length);
  final Stream<List<int>> chunks;
  final int? length;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(chunks, 200, contentLength: length);
}

void main() {
  test(
    'delayed chunks report actual 0, partial, 100 before decoding',
    () async {
      final stream = StreamController<List<int>>();
      final decode = Completer<void>();
      final events = <(int, int?)>[];
      Uint8List? loaded;
      final result = loadBrowserModelBytes(
        uri: Uri.parse('https://example.test/model.glb'),
        client: ChunkClient(stream.stream, 8),
        isCurrent: () => true,
        onProgress: (received, total) => events.add((received, total)),
        load: (bytes) {
          loaded = bytes;
          return decode.future;
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, [(0, 8)]);
      stream.add([1, 2]);
      await Future<void>.delayed(Duration.zero);
      expect(events.last, (2, 8));
      stream.add([3, 4, 5, 6, 7, 8]);
      await stream.close();
      await Future<void>.delayed(Duration.zero);
      expect(events, [(0, 8), (2, 8), (8, 8)]);
      expect(loaded, [1, 2, 3, 4, 5, 6, 7, 8]);
      decode.complete();
      expect(await result, sha256.convert(loaded!).toString());
    },
  );

  test(
    'unknown length stays unknown, stale load cannot publish or decode',
    () async {
      final stream = StreamController<List<int>>();
      var current = true;
      var loads = 0;
      final events = <(int, int?)>[];
      final result = loadBrowserModelBytes(
        uri: Uri.parse('https://example.test/model.glb'),
        client: ChunkClient(stream.stream, null),
        isCurrent: () => current,
        onProgress: (received, total) => events.add((received, total)),
        load: (_) async {
          loads++;
        },
      );
      await Future<void>.delayed(Duration.zero);
      stream.add([1, 2]);
      await Future<void>.delayed(Duration.zero);
      expect(events, [(0, null), (2, null)]);
      current = false;
      stream.add([3, 4]);
      expect(await result, isNull);
      await stream.close();
      expect(loads, 0);
      expect(events, [(0, null), (2, null)]);
    },
  );

  test('download failures remain failures', () async {
    final result = loadBrowserModelBytes(
      uri: Uri.parse('https://example.test/model.glb'),
      client: ChunkClient(
        Stream<List<int>>.error(StateError('interrupted')),
        8,
      ),
      isCurrent: () => true,
      onProgress: (_, _) {},
      load: (_) async => fail('partial model must not load'),
    );
    await expectLater(result, throwsStateError);
  });
}
