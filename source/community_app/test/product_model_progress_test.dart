// ignore_for_file: invalid_use_of_internal_member
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pw_shared_viewer/pw_shared_viewer.dart';
import 'package:pocketworld_flutter/ui/shared/product_model_view.dart';

class _Client extends http.BaseClient {
  final streams = <StreamController<List<int>>>[];
  int? length = 8;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stream = StreamController<List<int>>();
    streams.add(stream);
    return http.StreamedResponse(stream.stream, 200, contentLength: length);
  }
}

class _Host extends StatefulWidget {
  const _Host(this.controller, this.ready, this.decode);
  final SharedViewerController controller;
  final VoidCallback ready;
  final Future<void> decode;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String? loadId;
  final methods = <String>[];
  @override
  void initState() {
    super.initState();
    widget.controller.attachTransport((request) async {
      methods.add(request['method'] as String);
      if (request['method'] == 'load') {
        loadId = request['id'] as String;
        await widget.decode;
      }
      widget.controller.receive({
        'protocol': sharedViewerProtocol,
        'id': request['id'],
        'ok': true,
        'result': null,
      });
    }, registerBytes: (_, _) async => Uri.parse('blob:test'));
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.ready());
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}

Widget _view(
  _Client client,
  Completer<void> decode, {
  String url = 'https://example.test/one.glb',
  VoidCallback? onFirstFrame,
  ValueChanged<Object>? onError,
  GlobalKey<NavigatorState>? navigatorKey,
  bool trackedDownload = true,
  ValueChanged<ProductViewerCapture>? onViewerReady,
  Map<String, dynamic>? initialView,
}) => MaterialApp(
  navigatorKey: navigatorKey,
  home: ProductModelView(
    modelUrl: url,
    initialView: initialView,
    interactive: true,
    browserModelClient: client,
    onSurfacePicked: trackedDownload ? (_) {} : null,
    onFirstFrameReady: onFirstFrame,
    onViewerReady: onViewerReady,
    onError: onError,
    hostBuilder: (_, controller, ready, _) =>
        _Host(controller, ready, decode.future),
  ),
);

Future<void> _flush(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets(
    'real chunks drive ring and 100 stays until decoded first frame',
    (tester) async {
      final client = _Client();
      final decode = Completer<void>();
      var frames = 0;
      await tester.pumpWidget(
        _view(client, decode, onFirstFrame: () => frames++),
      );
      await _flush(tester);
      expect(find.text('0%'), findsOneWidget);
      client.streams.single.add([1, 2]);
      await _flush(tester);
      expect(find.text('25%'), findsOneWidget);
      expect(
        tester.getCenter(find.text('25%')),
        tester.getCenter(find.byType(CircularProgressIndicator)),
      );
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .value,
        .25,
      );
      client.streams.single.add([3, 4, 5, 6, 7, 8]);
      unawaited(client.streams.single.close());
      await _flush(tester);
      expect(find.text('100%'), findsOneWidget);
      expect(frames, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('100%'), findsOneWidget);
      decode.complete();
      await _flush(tester);
      await _flush(tester);
      expect(frames, 1);
      expect(
        find.byKey(const ValueKey('product-model-download')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('unknown length is honest and disposal ignores late bytes', (
    tester,
  ) async {
    final client = _Client()..length = null;
    final decode = Completer<void>();
    await tester.pumpWidget(_view(client, decode));
    await _flush(tester);
    client.streams.single.add([1, 2]);
    await _flush(tester);
    expect(find.text('—'), findsOneWidget);
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    client.streams.single.add([3]);
    unawaited(client.streams.single.close());
    await _flush(tester);
    expect(tester.takeException(), isNull);
    decode.complete();
  });

  testWidgets(
    'new asset resets progress and stale download cannot overwrite it',
    (tester) async {
      final client = _Client();
      final decode = Completer<void>();
      await tester.pumpWidget(_view(client, decode));
      await _flush(tester);
      final old = client.streams.single;
      old.add([1, 2, 3, 4]);
      await _flush(tester);
      expect(find.text('50%'), findsOneWidget);
      await tester.pumpWidget(
        _view(client, decode, url: 'https://example.test/two.glb'),
      );
      await _flush(tester);
      expect(find.text('0%'), findsOneWidget);
      old.add([5, 6, 7, 8]);
      unawaited(old.close());
      await _flush(tester);
      expect(find.text('0%'), findsOneWidget);
      client.streams.last.add([1, 2]);
      await _flush(tester);
      expect(find.text('25%'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      unawaited(client.streams.last.close());
      decode.complete();
      await _flush(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed download replaces progress with error state', (
    tester,
  ) async {
    final client = _Client();
    final decode = Completer<void>();
    final errors = <Object>[];
    await tester.pumpWidget(_view(client, decode, onError: errors.add));
    await _flush(tester);
    client.streams.single.addError(StateError('download interrupted'));
    await _flush(tester);
    expect(errors, hasLength(1));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    unawaited(client.streams.single.close());
    decode.complete();
  });
  testWidgets('covered route retains loading until first visible frame', (
    tester,
  ) async {
    final client = _Client();
    final decode = Completer<void>();
    final navigator = GlobalKey<NavigatorState>();
    var frames = 0;
    await tester.pumpWidget(
      _view(
        client,
        decode,
        navigatorKey: navigator,
        onFirstFrame: () => frames++,
      ),
    );
    await _flush(tester);
    unawaited(
      navigator.currentState!.push(
        PageRouteBuilder<void>(
          opaque: false,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => const SizedBox(),
        ),
      ),
    );
    await _flush(tester);
    client.streams.single.add([1, 2, 3, 4, 5, 6, 7, 8]);
    unawaited(client.streams.single.close());
    decode.complete();
    await _flush(tester);
    expect(frames, 0);
    expect(
      find.byKey(const ValueKey('product-model-download')),
      findsOneWidget,
    );
    navigator.currentState!.pop();
    await _flush(tester);
    await _flush(tester);
    expect(frames, 1);
    expect(find.byKey(const ValueKey('product-model-download')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'direct URL preserves URL transport and uses correlated byte progress',
    (tester) async {
      final client = _Client();
      final decode = Completer<void>();
      await tester.pumpWidget(_view(client, decode, trackedDownload: false));
      await _flush(tester);
      expect(client.streams, isEmpty);
      expect(find.text('—'), findsOneWidget);
      decode.complete();
      await _flush(tester);
      expect(
        find.byKey(const ValueKey('product-model-download')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('viewer-ready exposes the exact downloaded model identity', (
    tester,
  ) async {
    final client = _Client();
    final decode = Completer<void>();
    String? identity;
    await tester.pumpWidget(
      _view(
        client,
        decode,
        onViewerReady: (viewer) async {
          identity = await viewer.modelContentSha256();
        },
      ),
    );
    await _flush(tester);
    final bytes = [1, 2, 3, 4, 5, 6, 7, 8];
    client.streams.single.add(bytes);
    unawaited(client.streams.single.close());
    decode.complete();
    await _flush(tester);
    await _flush(tester);
    expect(identity, sha256.convert(bytes).toString());
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'server framing applies once only after matching model identity',
    (tester) async {
      final client = _Client();
      final decode = Completer<void>();
      final hash = sha256.convert([1, 2, 3, 4, 5, 6, 7, 8]).toString();
      final initial = <String, dynamic>{
        'schema': 'pw.camera-framing.v1',
        'asset_sha256': hash,
      };
      await tester.pumpWidget(_view(client, decode, initialView: initial));
      await _flush(tester);
      final host = tester.state<_HostState>(find.byType(_Host));
      expect(host.methods.where((m) => m == 'setCameraFraming'), isEmpty);
      client.streams.single.add([1, 2, 3, 4, 5, 6, 7, 8]);
      unawaited(client.streams.single.close());
      decode.complete();
      await _flush(tester);
      await _flush(tester);
      expect(host.methods.where((m) => m == 'setCameraFraming'), hasLength(1));
      await tester.pumpWidget(
        _view(client, decode, initialView: Map.from(initial)),
      );
      await _flush(tester);
      expect(host.methods.where((m) => m == 'setCameraFraming'), hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('mismatched server asset preserves official auto framing', (
    tester,
  ) async {
    final client = _Client();
    final decode = Completer<void>();
    await tester.pumpWidget(
      _view(
        client,
        decode,
        initialView: {
          'schema': 'pw.camera-framing.v1',
          'asset_sha256': '0' * 64,
        },
      ),
    );
    await _flush(tester);
    final host = tester.state<_HostState>(find.byType(_Host));
    client.streams.single.add([1, 2, 3, 4, 5, 6, 7, 8]);
    unawaited(client.streams.single.close());
    decode.complete();
    await _flush(tester);
    await _flush(tester);
    expect(host.methods.where((m) => m == 'setCameraFraming'), isEmpty);
    expect(find.byKey(const ValueKey('product-model-download')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
