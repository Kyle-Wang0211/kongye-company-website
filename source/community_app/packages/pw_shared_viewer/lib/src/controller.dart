import 'dart:async';
import 'dart:convert';
import 'point_cloud_transport.dart';
import 'surface_comments.dart';
import 'package:flutter/foundation.dart';

const sharedViewerProtocol = 'PW_SHARED_VIEWER_V1';

enum SharedModelFormat { glb, ply, skp }

typedef SharedViewerTransport = Future<void> Function(
    Map<String, Object?> request);
typedef SharedViewerLocalRegistrar = Future<Uri> Function(String path);
typedef SharedViewerBytesRegistrar = Future<Uri> Function(
    Uint8List bytes, SharedModelFormat format);
typedef SharedViewerResourceReleaser = void Function(Uri uri);

class SharedViewerException implements Exception {
  const SharedViewerException(this.message);
  final String message;
  @override
  String toString() => 'SharedViewerException: $message';
}

/// Message transport only. Renderer, parsers and controls use the same pinned
/// upstream modules; shared framing configuration lives in the JavaScript adapter.
class SharedViewerController extends ChangeNotifier {
  SharedViewerController({this.requestTimeout = const Duration(seconds: 90)});
  // Unique for this Dart isolate, including controller replacements on one host.
  static int _nextControllerSerial = 0;
  final String _requestPrefix = 'pw-${++_nextControllerSerial}-';
  final Duration requestTimeout;
  final Map<String, Completer<Object?>> _pending = {};
  SharedViewerTransport? _transport;
  SharedViewerLocalRegistrar? _registerLocal;
  SharedViewerBytesRegistrar? _registerBytes;
  SharedViewerResourceReleaser? _releaseResource;
  int _nextId = 1;
  bool _disposed = false;
  Map<String, Object?> _state = const {};
  Map<String, Object?> get state => Map.unmodifiable(_state);
  SharedSurfaceAnchor? _pickedSurface;
  SharedSurfaceAnchor? get pickedSurface => _pickedSurface;
  int _surfacePickRevision = 0;
  int get surfacePickRevision => _surfacePickRevision;
  String? _selectedSurfaceMarkerId;
  String? get selectedSurfaceMarkerId => _selectedSurfaceMarkerId;
  int _surfaceMarkerSelectionRevision = 0;
  int get surfaceMarkerSelectionRevision => _surfaceMarkerSelectionRevision;
  SharedSurfaceMarkerLayout? _surfaceMarkerLayout;
  SharedSurfaceMarkerLayout? get surfaceMarkerLayout => _surfaceMarkerLayout;
  int _surfaceMarkerLayoutRevision = 0;
  int get surfaceMarkerLayoutRevision => _surfaceMarkerLayoutRevision;
  bool get isAttached => !_disposed && _transport != null;

  @internal
  void attachTransport(SharedViewerTransport transport,
      {SharedViewerLocalRegistrar? registerLocal,
      SharedViewerBytesRegistrar? registerBytes,
      SharedViewerResourceReleaser? releaseResource}) {
    if (_disposed) throw StateError('Shared Viewer controller is disposed');
    if (_transport != null) throw StateError('Controller already has a host');
    _transport = transport;
    _registerLocal = registerLocal;
    _registerBytes = registerBytes;
    _releaseResource = releaseResource;
  }

  @internal
  void detachTransport() {
    _transport = null;
    _registerLocal = null;
    _registerBytes = null;
    _releaseResource = null;
    final pending = _pending.values.toList();
    _pending.clear();
    for (final request in pending) {
      request.completeError(StateError('Shared Viewer host detached'));
    }
  }

  /// Called only after the platform host validates the message source/origin.
  @internal
  void receive(Object? message) {
    if (_disposed) return;
    Object? decoded = message;
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } on FormatException {
        return;
      }
    }
    if (decoded is! Map || decoded['protocol'] != sharedViewerProtocol) return;
    if (decoded['type'] == 'pw-viewer-surface-marker-layout') {
      if (!decoded.containsKey('layout')) return;
      final layout = decoded['layout'];
      if (layout != null && layout is! Map) return;
      try {
        _surfaceMarkerLayout = layout == null
            ? null
            : SharedSurfaceMarkerLayout.fromJson(
                Map<String, Object?>.from(layout));
      } on ArgumentError {
        return;
      } on TypeError {
        return;
      }
      _surfaceMarkerLayoutRevision++;
      notifyListeners();
      return;
    }
    if (decoded['type'] == 'pw-viewer-surface-picked') {
      final anchor = decoded['anchor'];
      if (anchor is! Map) return;
      try {
        _pickedSurface =
            SharedSurfaceAnchor.fromJson(Map<String, Object?>.from(anchor));
      } on ArgumentError {
        return;
      } on TypeError {
        return;
      }
      _surfacePickRevision++;
      notifyListeners();
      return;
    }
    if (decoded['type'] == 'pw-viewer-surface-marker-selected') {
      final id = decoded['id'];
      if (id is! String || id.isEmpty || id.length > 128) return;
      _selectedSurfaceMarkerId = id;
      _surfaceMarkerSelectionRevision++;
      notifyListeners();
      return;
    }
    if (decoded['type'] == 'pw-viewer-state' ||
        decoded['type'] == 'pw-viewer-ready') {
      final state = decoded['state'];
      if (state is Map) {
        _state = state.map((key, value) => MapEntry(key.toString(), value));
        notifyListeners();
      }
      return;
    }
    final id = decoded['id'];
    if (id is! String) return;
    final pending = _pending.remove(id);
    if (pending == null) return;
    if (decoded['ok'] == true) {
      pending.complete(decoded['result']);
    } else {
      final error = decoded['error'];
      pending.completeError(SharedViewerException(
        error is Map
            ? '${error['message'] ?? 'Viewer request failed'}'
            : '$error',
      ));
    }
  }

  Future<Object?> _request(String method,
      [Map<String, Object?> args = const {}]) {
    if (_disposed) throw StateError('Shared Viewer controller is disposed');
    final send = _transport;
    if (send == null) throw StateError('Shared Viewer host is not ready');
    final id = '$_requestPrefix${_nextId++}';
    final completer = Completer<Object?>();
    _pending[id] = completer;
    // Subscribe before dispatch so synchronous responses and transport errors
    // cannot become unhandled asynchronous errors.
    final response = completer.future.timeout(requestTimeout, onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('Shared Viewer $method timed out', requestTimeout);
    });
    try {
      send({'id': id, 'method': method, 'args': args}).then<void>((_) {},
          onError: (Object error, StackTrace stack) {
        if (_pending.remove(id) != null) completer.completeError(error, stack);
      });
    } catch (error, stack) {
      if (_pending.remove(id) != null) completer.completeError(error, stack);
    }
    return response;
  }

  Future<Map<String, Object?>> getState() async {
    final result = await _request('getState');
    return result is Map
        ? result.map((key, value) => MapEntry(key.toString(), value))
        : const {};
  }

  Future<void> load(
      {required Uri url,
      required SharedModelFormat format,
      bool preserveCamera = false}) async {
    if (url.scheme != 'http' && url.scheme != 'https' && url.scheme != 'blob') {
      throw ArgumentError.value(
          url, 'url', 'Expected explicit HTTP(S) or blob URI');
    }
    _pickedSurface = null;
    _selectedSurfaceMarkerId = null;
    _surfaceMarkerLayout = null;
    await _request('load', {
      'url': url.toString(),
      'format': format.name,
      'preserveCamera': preserveCamera
    });
  }

  Future<void> loadLocalFile(String path,
      {required SharedModelFormat format, bool preserveCamera = false}) async {
    final register = _registerLocal;
    if (register == null) {
      throw UnsupportedError('Local files require a native asset host');
    }
    final release = _releaseResource;
    final url = await register(path);
    try {
      // Official load resolves after geometry and texture dependencies finish.
      await load(url: url, format: format, preserveCamera: preserveCamera);
    } finally {
      release?.call(url);
    }
  }

  /// Registers these exact bytes with the current host and releases the resource
  /// after the original renderer finishes all model dependencies, including failure.
  Future<void> loadBytes(Uint8List bytes,
      {required SharedModelFormat format, bool preserveCamera = false}) async {
    final register = _registerBytes, release = _releaseResource;
    if (register == null) {
      throw UnsupportedError('Byte transport requires a binary asset host');
    }
    final uri = await register(bytes, format);
    try {
      await load(url: uri, format: format, preserveCamera: preserveCamera);
    } finally {
      release?.call(uri);
    }
  }

  Future<void> loadPointCloud(
      {required Float32List xyz,
      required Uint8List rgb,
      bool preserveCamera = true}) async {
    final register = _registerBytes, release = _releaseResource;
    if (register == null) {
      throw UnsupportedError('Point transport requires a binary asset host');
    }
    final bytes = encodePointCloudPly(xyz, rgb);
    final uri = await register(bytes, SharedModelFormat.ply);
    try {
      await load(
          url: uri,
          format: SharedModelFormat.ply,
          preserveCamera: preserveCamera);
    } finally {
      release?.call(uri);
    }
  }

  Future<void> configure(
      {bool? interactive,
      bool? autoRotate,
      bool? autoRotateUntilTouched,
      int? background,
      double? autoRotateSpeed,
      double? pointSize,
      double? maxFps}) async {
    await _request('configure', {
      if (interactive != null) 'interactive': interactive,
      if (autoRotate != null) 'autoRotate': autoRotate,
      if (autoRotateUntilTouched != null)
        'autoRotateUntilTouched': autoRotateUntilTouched,
      if (background != null) 'background': background,
      if (autoRotateSpeed != null) 'autoRotateSpeed': autoRotateSpeed,
      if (pointSize != null) 'pointSize': pointSize,
      if (maxFps != null) 'maxFps': maxFps,
    });
  }

  Future<void> setSurfaceCommentMode(bool enabled) async {
    await _request('setSurfaceCommentMode', {'enabled': enabled});
  }

  /// Only pass markers the application has already authorized for this user.
  Future<void> setSurfaceCommentMarkers(
      List<SharedSurfaceMarker> markers) async {
    if (markers.length > 256 ||
        markers.map((m) => m.id).toSet().length != markers.length) {
      throw ArgumentError('Expected at most 256 unique surface markers');
    }
    await _request('setSurfaceCommentMarkers',
        {'markers': markers.map((m) => m.toJson()).toList()});
  }

  Future<void> focusSurfaceComment(SharedSurfaceAnchor anchor) async {
    await _request('focusSurfaceComment', {'anchor': anchor.toJson()});
  }

  Future<void> resetCamera() async {
    await _request('resetCamera');
  }

  Future<void> resize(
      {double? width, double? height, double? pixelRatio}) async {
    await _request('resize', {
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (pixelRatio != null) 'pixelRatio': pixelRatio
    });
  }

  Future<Object?> capture({String type = 'image/png', double? quality}) =>
      _request(
          'capture', {'type': type, if (quality != null) 'quality': quality});
  Future<void> pause() async {
    await _request('pause');
  }

  Future<void> resume() async {
    await _request('resume');
  }

  Future<void> disposeRenderer() async {
    await _request('dispose');
  }

  @override
  void dispose() {
    if (_disposed) return;
    detachTransport();
    _disposed = true;
    super.dispose();
  }
}
