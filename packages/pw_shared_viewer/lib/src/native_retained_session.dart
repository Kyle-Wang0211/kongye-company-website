import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'controller.dart';
import 'local_server.dart';
import 'native_bootstrap.dart';

/// Optional owner of one native WebView, its document and local asset server.
///
/// The supplied shared [controller] remains caller-owned. Await [dispose] before
/// disposing that controller. A presentation releases only its exclusive lease;
/// it must not destroy this externally owned session on route disposal.
class SharedViewerRetainedSession {
  SharedViewerRetainedSession({required SharedViewerController controller})
      : _controller = controller;

  SharedViewerController _controller;
  SharedViewerController get controller => _controller;
  bool get retentionSupported => true;
  bool get isReady =>
      !_disposed && _error == null && _rendererReady && _ownsTransport;
  bool get isDisposed => _disposed;
  Object? get error => _error;
  bool get hasPresentationLease => _presentation != null;
  WebViewController? get webViewController => _webView;

  final _listeners = <VoidCallback>{};
  Object? _presentation, _error;
  Map<String, String> _uiStrings = const {};
  bool _presentationActive = false, _disposed = false;
  bool _rendererReady = false, _ownsTransport = false;
  bool _webViewDisposed = false, _serverClosed = false;
  int _activityEpoch = 0;
  Timer? _readyDeadline;
  SharedViewerAssetServer? _server;
  WebViewController? _webView;
  Future<void>? _initializing, _disposing;
  Future<void> _presentationDrain = Future<void>.value();
  Future<void> _activityTail = Future<void>.value();

  void addListener(VoidCallback listener) {
    if (_disposed) throw StateError('Retained viewer session is disposed');
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) => _listeners.remove(listener);
  void _notify() {
    for (final listener in List<VoidCallback>.of(_listeners)) {
      try {
        listener();
      } catch (error) {
        debugPrint('Shared Viewer listener: $error');
      }
    }
  }

  @internal
  void acquirePresentation(Object owner) {
    if (_disposed) throw StateError('Retained viewer session is disposed');
    if (_presentation != null && !identical(_presentation, owner)) {
      throw StateError(
          'Retained viewer already has an active presentation lease');
    }
    _presentation = owner;
    _presentationActive = false;
  }

  @internal
  bool ownsPresentation(Object owner) => identical(_presentation, owner);

  @internal
  void setUiStrings(Object owner, Map<String, String> strings) {
    if (!ownsPresentation(owner) || _disposed || mapEquals(_uiStrings, strings)) {
      return;
    }
    _uiStrings = Map<String, String>.unmodifiable(strings);
    unawaited(_sendUiStrings());
  }

  Future<void> _sendUiStrings() async {
    final webView = _webView;
    if (webView == null || _cancelled || _uiStrings.isEmpty) return;
    try {
      final packet = jsonEncode(
          {'type': 'pw-viewer-ui-localization', 'strings': _uiStrings});
      await webView.runJavaScript(
          'window.postMessage($packet, window.location.origin);');
    } catch (error) {
      debugPrint('Shared Viewer UI localization delivery failed: $error');
    }
  }

  @internal
  void releasePresentation(Object owner) {
    if (!ownsPresentation(owner)) return;
    _presentation = null;
    _presentationActive = false;
    // Public platform widgets expose no native-detach acknowledgment. Drain
    // two completed frames before allowing a new wrapper for the same view.
    // This is a conservative ordering barrier, not proof of native completion.
    _presentationDrain = _drainPresentationFrames();
    _syncActivity();
  }

  Future<void> _drainPresentationFrames() async {
    final binding = WidgetsBinding.instance;
    await binding.endOfFrame;
    binding.scheduleFrame();
    await binding.endOfFrame;
  }

  @internal
  Future<void> waitForPresentationDrain(Object owner) async {
    await _presentationDrain;
  }

  @internal
  void setPresentationActive(Object owner, bool active) {
    if (!ownsPresentation(owner) || _disposed) return;
    _presentationActive = active;
    _syncActivity();
  }

  @internal
  Future<void> ensureInitialized() {
    if (_disposed) return Future<void>.value();
    return _initializing ??= _initialize();
  }

  bool get _cancelled => _disposed || _error != null;

  Future<void> _initialize() async {
    _readyDeadline = Timer(const Duration(seconds: 35), () {
      if (!_rendererReady) {
        _fail(const SharedViewerException('Renderer did not report readiness'));
      }
    });
    try {
      if (WebViewPlatform.instance == null) {
        throw UnsupportedError('No native WebViewPlatform adapter registered');
      }
      const prefix = 'packages/pw_shared_viewer/web/';
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      if (_cancelled) return;
      final assets = manifest
          .listAssets()
          .where((path) => path.startsWith(prefix))
          .map((path) => path.substring(prefix.length))
          .toSet();
      final server = await SharedViewerAssetServer.start(
          assets: assets,
          readAsset: (path) async {
            final bytes = await rootBundle.load('$prefix$path');
            return bytes.buffer
                .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
          });
      _server = server;
      if (_cancelled) {
        await _disposeResources();
        return;
      }
      final webView = await nativeWebViewBootstrap.createController(
        create: WebViewController.new,
        isDisposed: () => _cancelled,
      );
      if (webView == null) return;
      _webView = webView;
      if (_cancelled) {
        await _disposeResources();
        return;
      }
      await webView.setJavaScriptMode(JavaScriptMode.unrestricted);
      if (_cancelled) return;
      await webView.setBackgroundColor(const Color(0xff000000));
      if (_cancelled) return;
      await webView.setOnConsoleMessage((message) {
        debugPrint(
            'PW_VIEWER_WEB_CONSOLE ${message.level.name}: ${message.message}');
      });
      if (_cancelled) return;
      await webView.addJavaScriptChannel('PWSharedHost',
          onMessageReceived: _message);
      if (_cancelled) return;
      await webView.setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          final target = Uri.tryParse(request.url);
          return !_disposed &&
                  target != null &&
                  target.scheme == 'http' &&
                  target.host == '127.0.0.1' &&
                  target.port == server.entryUri.port
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true ||
              error.errorType ==
                  WebResourceErrorType.webContentProcessTerminated) {
            _fail(SharedViewerException('Main-frame error ${error.errorCode}: '
                '${error.description}; type=${error.errorType}'));
          }
        },
      ));
      if (_cancelled) return;
      // Publish the SAME controller before navigation; a presentation can mount
      // its platform widget while the session, rather than that State, owns IO.
      _notify();
      await webView.loadRequest(server.entryUri);
    } catch (error) {
      _fail(error);
    }
  }

  void _message(JavaScriptMessage message) {
    if (_cancelled) return;
    Object? decoded;
    try {
      decoded = jsonDecode(message.message);
    } on FormatException {
      return;
    }
    if (decoded is! Map || decoded['protocol'] != sharedViewerProtocol) return;
    if (decoded['type'] == 'pw-viewer-ui-localization-ready') {
      unawaited(_sendUiStrings());
      return;
    }
    final state = decoded['state'];
    if (!_rendererReady && state is Map && state['status'] == 'error') {
      _fail(SharedViewerException(
          '${state['error'] ?? 'Renderer initialization failed'}'));
      return;
    }
    final ready = decoded['type'] == 'pw-viewer-ready' ||
        (decoded['id'] == 'host-ready' && decoded['ok'] == true);
    if (ready && !_rendererReady) {
      _rendererReady = true;
      _readyDeadline?.cancel();
      _attachTransport();
    }
    _controller.receive(decoded);
    if (ready) _notify();
  }

  void _attachTransport() {
    if (_ownsTransport || _cancelled || !_rendererReady) return;
    try {
      final webView = _webView!, server = _server!;
      _controller.attachTransport(
        (request) => webView.runJavaScript(
            'window.PWSharedBridge.request(${jsonEncode(request)}).catch(() => {});'),
        registerLocal: server.registerModel,
        registerBytes: (bytes, format) =>
            server.registerBytes(bytes, format.name),
        releaseResource: server.unregisterModel,
      );
      _ownsTransport = true;
      _syncActivity();
    } catch (error) {
      _fail(error);
    }
  }

  /// The default non-retained widget historically permits a controller swap
  /// without reloading its native document. External retained owners never use
  /// this compatibility operation: their controller association stays stable.
  @internal
  void rebindUnretainedController(SharedViewerController replacement) {
    if (identical(replacement, _controller)) return;
    _activityEpoch++;
    if (_ownsTransport) _controller.detachTransport();
    _ownsTransport = false;
    _controller = replacement;
    _attachTransport();
    _notify();
  }

  void _syncActivity() {
    final epoch = ++_activityEpoch;
    _activityTail = _activityTail.then((_) async {
      if (epoch != _activityEpoch || !isReady) return;
      final shouldRun = _presentation != null && _presentationActive;
      await (shouldRun ? _controller.resume() : _controller.pause());
    }).catchError((Object error) {
      if (epoch == _activityEpoch && !_disposed) _fail(error);
    });
  }

  /// A retained document can be reclaimed by WebKit while it has no widget.
  /// Verify the actual live document/context before issuing this lease's ready
  /// callback; a saved Dart boolean is not proof that its JS scene survived.
  @internal
  Future<bool> validatePresentation(Object owner) async {
    if (!ownsPresentation(owner) || !isReady) return false;
    try {
      final result = await _webView!
          .runJavaScriptReturningResult(
            'Boolean(window.pwSharedViewerController && '
            '!window.pwSharedViewerController.getState().disposed && '
            'document.querySelector("#viewer")?.getContext("webgl2") && '
            '!document.querySelector("#viewer").getContext("webgl2").isContextLost())',
          )
          .timeout(const Duration(seconds: 5));
      if (!ownsPresentation(owner) || _disposed) return false;
      if (result != true && result != 'true') {
        throw const SharedViewerException(
            'Retained renderer document or context was lost');
      }
      return isReady;
    } catch (error) {
      if (ownsPresentation(owner) && !_disposed) _fail(error);
      return false;
    }
  }

  void _fail(Object error) {
    if (_disposed || _error != null) return;
    _error = error;
    _rendererReady = false;
    _readyDeadline?.cancel();
    _activityEpoch++;
    if (_ownsTransport) _controller.detachTransport();
    _ownsTransport = false;
    _notify();
  }

  Future<void> _disposeResources() async {
    final webView = _webView;
    if (webView != null && !_webViewDisposed) {
      _webViewDisposed = true;
      try {
        await webView
            .runJavaScript('window.pwSharedViewerController?.dispose();')
            .timeout(const Duration(seconds: 5));
      } catch (_) {/* A reclaimed process may no longer evaluate JavaScript. */}
      try {
        await webView
            .removeJavaScriptChannel('PWSharedHost')
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
      _webView = null;
    }
    final server = _server;
    if (server != null && !_serverClosed) {
      _serverClosed = true;
      await server.close();
      _server = null;
    }
  }

  /// Invalidates immediately; resource cleanup is idempotent and awaitable.
  /// Does not dispose the externally supplied shared controller.
  Future<void> dispose() {
    if (_disposing != null) return _disposing!;
    _disposed = true;
    _rendererReady = false;
    _presentation = null;
    _presentationActive = false;
    _activityEpoch++;
    _readyDeadline?.cancel();
    if (_ownsTransport) _controller.detachTransport();
    _ownsTransport = false;
    _notify();
    _listeners.clear();
    return _disposing = _disposeResources();
  }
}
