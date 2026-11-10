import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:pw_shared_viewer/src/native_bootstrap.dart'
    show nativeWebViewBootstrap;
import '../../l10n/app_localizations.dart';

/// Native OLV executes only bundled assets on a private loopback server.
/// Only the registered COPC source is remote; no full-model byte cache is used.
class StreamingPointCloudView extends StatefulWidget {
  const StreamingPointCloudView({super.key, required this.source});
  final Uri source;
  @override
  State<StreamingPointCloudView> createState() =>
      _StreamingPointCloudViewState();
}

class _StreamingPointCloudViewState extends State<StreamingPointCloudView> {
  static const _assetPrefix = 'assets/pointcloud_viewer/';
  HttpServer? _server;
  WebViewController? _controller;
  Uri? _entry;
  bool _ready = false, _failed = false;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final epoch = ++_epoch;
    await _server?.close(force: true);
    _server = null;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final files = manifest
          .listAssets()
          .where((key) => key.startsWith(_assetPrefix))
          .map((key) => key.substring(_assetPrefix.length))
          .toSet();
      if (!files.contains('index.html'))
        throw StateError('Bundled point-cloud viewer missing');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      if (!mounted || epoch != _epoch) {
        await server.close(force: true);
        return;
      }
      _server = server;
      final token = List.generate(
        24,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      _entry = Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: server.port,
        path: '/$token/index.html',
      );
      server.listen((request) async {
        final response = request.response;
        try {
          final parts = request.uri.pathSegments;
          final key = parts.skip(1).join('/');
          response.headers.set('X-Content-Type-Options', 'nosniff');
          if (request.headers.value(HttpHeaders.hostHeader) !=
                  '127.0.0.1:${server.port}' ||
              parts.length < 2 ||
              parts.first != token ||
              !files.contains(key) ||
              parts.any(
                (part) => part == '..' || part == '.' || part.contains('\\'),
              )) {
            response.statusCode = HttpStatus.notFound;
          } else if (!{'GET', 'HEAD'}.contains(request.method)) {
            response.statusCode = HttpStatus.methodNotAllowed;
          } else {
            final data = await rootBundle.load('$_assetPrefix$key');
            final mime = key.endsWith('.html')
                ? 'text/html; charset=utf-8'
                : key.endsWith('.js') || key.endsWith('.mjs')
                ? 'text/javascript; charset=utf-8'
                : key.endsWith('.wasm')
                ? 'application/wasm'
                : key.endsWith('.css')
                ? 'text/css; charset=utf-8'
                : key.endsWith('.json')
                ? 'application/json'
                : key.endsWith('.svg')
                ? 'image/svg+xml'
                : key.endsWith('.png')
                ? 'image/png'
                : key.endsWith('.jpg') || key.endsWith('.jpeg')
                ? 'image/jpeg'
                : key.endsWith('.woff2')
                ? 'font/woff2'
                : 'application/octet-stream';
            response.headers.contentType = ContentType.parse(mime);
            response.contentLength = data.lengthInBytes;
            if (request.method == 'GET')
              response.add(
                data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              );
          }
        } catch (_) {
          response.statusCode = HttpStatus.notFound;
        } finally {
          await response.close();
        }
      });
      await nativeWebViewBootstrap.ensureRegistered();
      if (!mounted || epoch != _epoch) return;
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black)
        ..addJavaScriptChannel(
          'PWPointCloudStream',
          onMessageReceived: (message) {
            if (!mounted || epoch != _epoch) return;
            try {
              final data = jsonDecode(message.message);
              if (data is! Map ||
                  data['protocol'] != 'PW_POINT_CLOUD_STREAM_V1')
                return;
              if (data['type'] == 'ready')
                setState(() {
                  _ready = true;
                  _failed = false;
                });
              if (data['type'] == 'error')
                setState(() {
                  _ready = false;
                  _failed = true;
                });
            } catch (_) {
              /* Ignore unrelated bridge messages. */
            }
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              final uri = Uri.tryParse(request.url);
              return uri != null &&
                      uri.scheme == 'http' &&
                      uri.host == '127.0.0.1' &&
                      uri.port == _entry?.port
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent;
            },
            onWebResourceError: (error) {
              if (mounted && epoch == _epoch && error.isForMainFrame == true) {
                setState(() => _failed = true);
              }
            },
          ),
        );
      if (!mounted || epoch != _epoch) {
        await server.close(force: true);
        return;
      }
      setState(() => _controller = controller);
      await controller.loadRequest(
        _entry!.replace(queryParameters: {'source': widget.source.toString()}),
      );
    } catch (_) {
      if (mounted && epoch == _epoch) setState(() => _failed = true);
    }
  }

  void _reload() {
    setState(() {
      _ready = false;
      _failed = false;
    });
    final controller = _controller, entry = _entry;
    if (controller != null && entry != null) {
      unawaited(
        controller.loadRequest(
          entry.replace(queryParameters: {'source': widget.source.toString()}),
        ),
      );
    } else {
      unawaited(_start());
    }
  }

  @override
  void didUpdateWidget(covariant StreamingPointCloudView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) _reload();
  }

  @override
  void dispose() {
    _epoch++;
    final controller = _controller;
    if (controller != null) {
      unawaited(controller.runJavaScript('window.stop();').catchError((_) {}));
      unawaited(
        controller
            .loadHtmlString('<html style="background:black"></html>')
            .catchError((_) {}),
      );
    }
    unawaited(_server?.close(force: true));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (_controller != null) WebViewWidget(controller: _controller!),
        if (!_ready)
          ColoredBox(
            color: Colors.black,
            child: Center(
              child: _failed
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          AppL10n.of(context).communityCloudLoadFailed,
                          style: const TextStyle(color: Colors.white54),
                        ),
                        TextButton(
                          onPressed: _reload,
                          child: Text(AppL10n.of(context).communityRetry),
                        ),
                      ],
                    )
                  : const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white54,
                      ),
                    ),
            ),
          ),
      ],
    ),
  );
}
