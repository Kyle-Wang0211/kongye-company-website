// The fixture uses the shared renderer's public testing transport seam.
// ignore_for_file: invalid_use_of_internal_member
import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pocketworld_flutter/ui/shared/product_model_view.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';

class _BodyClient extends http.BaseClient {
  _BodyClient(this.total);
  final int? total;
  final body = StreamController<List<int>>();
  int requests = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    return http.StreamedResponse(body.stream, 200, contentLength: total);
  }
}

class _Renderer {
  SharedViewerController? controller;
  Map<String, Object?>? loadRequest;
  Uint8List? exactBytes;
  int loads = 0, releases = 0, readyCallbacks = 0;
  ProductViewerCapture? capture;
  Widget host(
    BuildContext context,
    SharedViewerController value,
    VoidCallback ready,
    ValueChanged<Object> error,
  ) {
    if (controller == null) {
      controller = value;
      value.attachTransport(
        (request) async {
          if (request['method'] == 'load') {
            loads++;
            loadRequest = request;
          } else {
            acknowledge(request);
          }
        },
        registerBytes: (bytes, format) async {
          exactBytes = Uint8List.fromList(bytes);
          return Uri.parse('blob:https://example.test/exact-model');
        },
        releaseResource: (_) => releases++,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => ready());
    }
    return const SizedBox.expand();
  }

  void acknowledge(Map<String, Object?> request) => controller!.receive({
    'protocol': sharedViewerProtocol,
    'id': request['id'],
    'ok': true,
    'result': null,
  });
  void staleProgress() => controller!.receive({
    'protocol': sharedViewerProtocol,
    'type': 'pw-viewer-download-progress',
    'id': loadRequest!['id'],
    'receivedBytes': 0,
    'totalBytes': null,
  });
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Widget _app(
  _BodyClient client,
  _Renderer renderer,
  ValueNotifier<int> revision,
) => MaterialApp(
  home: ValueListenableBuilder<int>(
    valueListenable: revision,
    builder: (_, value, _) => SizedBox(
      width: 600 + value.toDouble(),
      child: ProductModelView(
        modelUrl: 'https://example.test/model.glb',
        modelSizeBytes: client.total == null ? 100 : 200,
        interactive: true,
        browserModelClient: client,
        onSurfacePicked: (_) {},
        onViewerReady: (capture) {
          renderer.capture = capture;
          renderer.readyCallbacks++;
        },
        hostBuilder: renderer.host,
      ),
    ),
  ),
);

void main() {
  for (final known in [true, false]) {
    testWidgets('real detail bytes: ${known ? 'known total' : 'unknown total'} '
        'preserve ready scene across late progress and same-asset rebuild', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final client = _BodyClient(known ? 100 : null);
      final renderer = _Renderer();
      final revision = ValueNotifier(0);
      await tester.pumpWidget(_app(client, renderer, revision));
      await _flush(tester);
      expect(client.requests, 1);
      expect(find.text('0%'), findsOneWidget);
      client.body.add(List.filled(25, 1));
      await _flush(tester);
      expect(find.text('25%'), findsOneWidget);
      expect(renderer.loads, 0);
      client.body.add(List.filled(75, 2));
      await client.body.close();
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await _flush(tester);
      expect(find.text('99%'), findsOneWidget);
      expect(renderer.loads, 1);
      expect(renderer.readyCallbacks, 0);
      // The blob parser has its own local 0/100% transfer. It must not replace
      // the already observed HTTP body progress while parsing is still pending.
      renderer.staleProgress();
      renderer.controller!.receive({
        'protocol': sharedViewerProtocol,
        'type': 'pw-viewer-download-progress',
        'id': renderer.loadRequest!['id'],
        'receivedBytes': 100,
        'totalBytes': 100,
      });
      await _flush(tester);
      expect(find.text('99%'), findsOneWidget);
      expect(renderer.readyCallbacks, 0);
      final bytes = Uint8List.fromList([
        ...List.filled(25, 1),
        ...List.filled(75, 2),
      ]);
      expect(renderer.exactBytes, bytes);
      renderer.acknowledge(renderer.loadRequest!);
      await _flush(tester);
      expect(
        find.byKey(const ValueKey('product-model-download')),
        findsNothing,
      );
      expect(renderer.readyCallbacks, 1);
      expect(renderer.releases, 1);
      expect(
        await renderer.capture!.modelContentSha256(),
        sha256.convert(bytes).toString(),
      );
      renderer.staleProgress();
      revision.value++;
      await _flush(tester);
      expect(
        find.byKey(const ValueKey('product-model-download')),
        findsNothing,
      );
      expect(renderer.loads, 1);
      expect(client.requests, 1);
      expect(renderer.readyCallbacks, 1);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
      revision.dispose();
      client.close();
    });
  }
}
