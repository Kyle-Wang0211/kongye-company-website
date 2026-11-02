import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'controller.dart';
import 'native_bootstrap.dart';
import 'native_retained_session.dart';

/// Same native platform surface, with optional externally owned retention.
/// The default still owns/disposes its native document with the widget.
class SharedViewer extends StatefulWidget {
  const SharedViewer(
      {super.key,
      required this.controller,
      this.onReady,
      this.onError,
      this.active = true,
      this.pointerEventsEnabled = true,
      this.pointerEventsEnabledNotifier,
      this.uiStrings = const {},
      this.webEntryUri,
      this.retainedSession});
  final SharedViewerController controller;
  final VoidCallback? onReady;
  final ValueChanged<Object>? onError;
  final Uri? webEntryUri;
  final bool active;
  final bool pointerEventsEnabled;
  final ValueNotifier<bool>? pointerEventsEnabledNotifier;
  final Map<String, String> uiStrings;
  final SharedViewerRetainedSession? retainedSession;
  @override
  State<SharedViewer> createState() => _SharedViewerState();
}

class _SharedViewerState extends State<SharedViewer>
    with WidgetsBindingObserver {
  SharedViewerRetainedSession? _session;
  bool _owned = false, _dead = false, _leased = false;
  bool _tickerEnabled = true, _readyDelivered = false, _checkingReady = false;
  bool _errorDelivered = false, _presentationDrained = false;
  int _epoch = 0;
  Object? _localError;
  AppLifecycleState _appState =
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connect();
  }

  void _connect() {
    try {
      if (widget.webEntryUri != null) {
        throw ArgumentError('Native hosts always use packaged assets');
      }
      final supplied = widget.retainedSession;
      if (supplied != null &&
          !identical(supplied.controller, widget.controller)) {
        throw StateError(
            'Retained session must use its associated shared controller');
      }
      final session = supplied ??
          SharedViewerRetainedSession(controller: widget.controller);
      _session = session;
      _owned = supplied == null;
      session.acquirePresentation(this);
      session.setUiStrings(this, widget.uiStrings);
      _leased = true;
      final epoch = _epoch;
      unawaited(session.waitForPresentationDrain(this).then((_) {
        if (_dead ||
            !mounted ||
            epoch != _epoch ||
            !session.ownsPresentation(this)) {
          return;
        }
        _presentationDrained = true;
        _sessionChanged();
      }));
      session.addListener(_sessionChanged);
      if (nativeWebViewBootstrap.requiresRegistration) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_dead && identical(_session, session)) {
            unawaited(session.ensureInitialized());
          }
        });
      } else {
        unawaited(session.ensureInitialized());
      }
      _syncActivity();
      _sessionChanged();
    } catch (error) {
      _localError = error;
      _sessionChanged();
    }
  }

  void _sessionChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _dead) return;
      setState(() {});
      final session = _session;
      final error = _localError ??
          session?.error ??
          (session?.isDisposed == true
              ? const SharedViewerException('Viewer session is disposed')
              : null);
      if (error != null && !_errorDelivered) {
        _errorDelivered = true;
        widget.onError?.call(error);
      } else {
        _maybeReady();
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _maybeReady() {
    final session = _session;
    if (_dead ||
        !_leased ||
        !_presentationDrained ||
        _localError != null ||
        _readyDelivered ||
        _checkingReady ||
        session == null ||
        !session.isReady) {
      return;
    }
    _checkingReady = true;
    final epoch = _epoch;
    unawaited(session.validatePresentation(this).then((valid) {
      if (!mounted ||
          _dead ||
          epoch != _epoch ||
          !identical(session, _session)) {
        return;
      }
      _checkingReady = false;
      if (!valid || !session.ownsPresentation(this)) return;
      _readyDelivered = true;
      _syncActivity();
      widget.onReady?.call();
    }));
  }

  void _syncActivity() {
    if (!_leased) return;
    _session?.setPresentationActive(
        this,
        widget.active &&
            _tickerEnabled &&
            _appState == AppLifecycleState.resumed);
  }

  void _disconnect() {
    _epoch++;
    final session = _session;
    if (session != null) {
      session.removeListener(_sessionChanged);
      if (_leased) session.releasePresentation(this);
      if (_owned) {
        unawaited(session.dispose().catchError((Object error) {
          debugPrint('Shared Viewer cleanup failed: $error');
        }));
      }
    }
    _session = null;
    _leased = false;
    _presentationDrained = false;
  }

  @override
  void didUpdateWidget(covariant SharedViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.retainedSession, widget.retainedSession)) {
      _disconnect();
      _readyDelivered = false;
      _checkingReady = false;
      _errorDelivered = false;
      _localError = null;
      _connect();
    } else if (!identical(oldWidget.controller, widget.controller)) {
      if (_owned && _leased) {
        _epoch++;
        _readyDelivered = false;
        _checkingReady = false;
        _session!.rebindUnretainedController(widget.controller);
      } else {
        _localError =
            StateError('Retained session shared controller cannot change');
        _sessionChanged();
      }
    }
    _session?.setUiStrings(this, widget.uiStrings);
    _syncActivity();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncActivity();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appState = state;
    _syncActivity();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (_localError != null ||
        session?.error != null ||
        session?.isDisposed == true) {
      return ColoredBox(
          color: Color(0xff000000),
          child: Center(
              child: Text(
                  widget.uiStrings['failure'] ?? '3D Viewer unavailable',
                  textDirection: TextDirection.ltr)));
    }
    final controller =
        _leased && _presentationDrained ? session?.webViewController : null;
    return controller == null
        ? const ColoredBox(color: Color(0xff000000))
        : WebViewWidget(controller: controller);
  }

  @override
  void dispose() {
    _dead = true;
    WidgetsBinding.instance.removeObserver(this);
    _disconnect();
    super.dispose();
  }
}
