import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;
import 'controller.dart';
import 'retained_session_unsupported.dart';

/// Embeds the same offline entrypoint. Browser messages must come from this
/// exact iframe window and same origin; no wildcard postMessage targets.
class SharedViewer extends StatefulWidget {
  const SharedViewer(
      {super.key,
      required this.controller,
      this.onReady,
      this.onError,
      this.active = true,
      this.webEntryUri,
      this.retainedSession});
  final SharedViewerController controller;
  final VoidCallback? onReady;
  final ValueChanged<Object>? onError;
  final Uri? webEntryUri;
  final bool active;
  // Native retention is unsupported here; ordinary web behavior is unchanged.
  final SharedViewerRetainedSession? retainedSession;
  @override
  State<SharedViewer> createState() => _SharedViewerState();
}

class _SharedViewerState extends State<SharedViewer>
    with WidgetsBindingObserver {
  static int _nextView = 0;
  late final String _viewType;
  late final web.HTMLIFrameElement _frame;
  late final String _origin;
  late final JSFunction _messageListener;
  bool _attached = false;
  bool _rendererReady = false;
  bool _dead = false;
  bool _tickerEnabled = true;
  AppLifecycleState _appState = WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
  Object? _error;
  Timer? _readyDeadline;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _viewType = 'pw-shared-viewer-${_nextView++}';
    final entry = widget.webEntryUri ??
        Uri.parse(web.document.baseURI)
            .resolve('assets/packages/pw_shared_viewer/web/index.html');
    _origin = web.window.location.origin;
    if (entry.origin != _origin) {
      _error = ArgumentError(
          'Viewer entrypoint must be same-origin packaged assets');
    }
    _frame = web.HTMLIFrameElement()
      ..title = '3D作品'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = '0'
      ..style.display = 'block'
      ..style.backgroundColor = '#000'
      ..setAttribute('allow', '');
    _messageListener = ((web.MessageEvent event) {
      if (_dead || _error != null ||
          event.origin != _origin ||
          event.source != _frame.contentWindow) return;
      final Object? decoded = event.data.dartify();
      if (decoded is! Map || decoded['protocol'] != sharedViewerProtocol)
        return;
      final state = decoded['state'];
      if (!_rendererReady && state is Map && state['status'] == 'error') {
        _fail(SharedViewerException('${state['error'] ?? 'Renderer initialization failed'}'));
        return;
      }
      if (decoded['type'] == 'pw-viewer-ready') {
        _rendererReady = true;
        _attach();
      }
      widget.controller.receive(decoded);
    }).toJS;
    web.window.addEventListener('message', _messageListener);
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) => _frame);
    if (_error == null) {
      _readyDeadline = Timer(const Duration(seconds: 35), () {
        if (!_rendererReady) _fail(const SharedViewerException('Renderer did not report readiness'));
      });
      _frame.src = entry.toString();
    }
    else
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_dead) widget.onError?.call(_error!);
      });
  }

  void _attach() {
    if (_attached || _dead || !_rendererReady || _error != null) return;
    _readyDeadline?.cancel();
    try {
      widget.controller.attachTransport((request) async {
        _frame.contentWindow?.postMessage(
            {'type': 'pw-shared-request', 'request': request}.jsify(),
            _origin.toJS);
      }, registerBytes: (bytes, format) async {
        final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: format == SharedModelFormat.glb ? 'model/gltf-binary' : 'application/octet-stream'));
        return Uri.parse(web.URL.createObjectURL(blob));
      }, releaseResource: (uri) => web.URL.revokeObjectURL(uri.toString()));
      _attached = true;
      _syncActivity();
      widget.onReady?.call();
    } catch (error) {
      widget.onError?.call(error);
    }
  }

  void _fail(Object error) {
    if (_dead || _error != null) return;
    _readyDeadline?.cancel();
    if (_attached) widget.controller.detachTransport();
    _attached = false; _rendererReady = false;
    setState(() => _error = error);
    widget.onError?.call(error);
  }

  @override
  void didUpdateWidget(covariant SharedViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (_attached) oldWidget.controller.detachTransport();
      _attached = false;
      if (_rendererReady && _error == null) _attach();
    }
    if (oldWidget.active != widget.active) _syncActivity();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncActivity();
  }

  void _syncActivity() {
    if (!_attached || _dead || _error != null) return;
    final shouldRun = widget.active && _tickerEnabled && _appState == AppLifecycleState.resumed;
    unawaited((shouldRun ? widget.controller.resume() : widget.controller.pause()).catchError((Object error) {
      if (!_dead) widget.onError?.call(error);
    }));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appState = state;
    _syncActivity();
  }

  @override
  Widget build(BuildContext context) => _error == null
      ? HtmlElementView(viewType: _viewType)
      : const ColoredBox(
          color: Color(0xff000000),
          child: Center(
              child: Text('3D Viewer unavailable',
                  textDirection: TextDirection.ltr)));
  @override
  void dispose() {
    _dead = true;
    _readyDeadline?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_attached) {
      _frame.contentWindow?.postMessage(
          {
            'type': 'pw-shared-request',
            'request': {
              'id': 'host-dispose',
              'method': 'dispose',
              'args': <String, Object?>{}
            }
          }.jsify(),
          _origin.toJS);
      widget.controller.detachTransport();
    }
    web.window.removeEventListener('message', _messageListener);
    _frame.src = 'about:blank';
    _frame.remove();
    super.dispose();
  }
}
