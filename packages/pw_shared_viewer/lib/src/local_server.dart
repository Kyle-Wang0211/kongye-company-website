import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

typedef SharedViewerAssetReader = Future<Uint8List> Function(String asset);

/// Serves only packaged renderer assets and explicitly registered model files.
/// Authorization of account/work ownership belongs to the embedding caller.
class SharedViewerAssetServer {
  SharedViewerAssetServer._(
      this._server, this._token, this._assets, this._readAsset);
  final HttpServer _server;
  final String _token;
  final Set<String> _assets;
  final SharedViewerAssetReader _readAsset;
  final Map<String, _Model> _models = {};
  final Map<String, Uint8List> _byteModels = {};
  bool _closed = false;
  int _modelId = 0;
  late final StreamSubscription<HttpRequest> _subscription;
  Uri get entryUri => Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: _server.port,
      path: '/$_token/index.html');

  static Future<SharedViewerAssetServer> start(
      {required Set<String> assets,
      required SharedViewerAssetReader readAsset}) async {
    if (!assets.contains('index.html') ||
        assets.any((asset) => !_safeAsset(asset))) {
      throw ArgumentError('Exact relative packaged asset allowlist required');
    }
    final token = List.generate(
            32,
            (_) =>
                Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final host = SharedViewerAssetServer._(
        server, token, Set.unmodifiable(assets), readAsset);
    host._subscription = server.listen(host._serve);
    return host;
  }

  static bool _safeAsset(String path) =>
      !path.startsWith('/') &&
      !path.contains('\\') &&
      !path.contains('\u0000') &&
      path
          .split('/')
          .every((part) => part.isNotEmpty && part != '.' && part != '..');

  Future<Uri> registerModel(String path) async {
    if (_closed) throw StateError('Asset server closed');
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw ArgumentError(
          'Model must be an existing regular file, not a symlink');
    }
    final canonical = await File(path).resolveSymbolicLinks();
    final extension = canonical.toLowerCase().split('.').last;
    if (extension != 'glb' && extension != 'gltf' && extension != 'ply' && extension != 'skp') {
      throw ArgumentError(
          'Only self-contained GLB/glTF, PLY and SKP files are supported');
    }
    final file = File(canonical);
    final stat = await file.stat();
    final key = 'models/${++_modelId}.$extension';
    _models[key] = _Model(file, stat.size, stat.modified);
    return entryUri.resolve(key);
  }

  Future<Uri> registerBytes(Uint8List bytes, String format) async {
    if (_closed) throw StateError('Asset server closed');
    if (!{'glb', 'ply', 'skp'}.contains(format) || bytes.isEmpty) {
      throw ArgumentError('Nonempty supported binary model required');
    }
    final key = 'models/${++_modelId}.$format';
    _byteModels[key] = Uint8List.fromList(bytes);
    return entryUri.resolve(key);
  }

  void unregisterModel(Uri uri) {
    if (uri.origin != entryUri.origin) return;
    final prefix = '/$_token/';
    if (uri.path.startsWith(prefix)) {
      final key = uri.path.substring(prefix.length);
      _models.remove(key);
      _byteModels.remove(key);
    }
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      response.headers.set('X-Content-Type-Options', 'nosniff');
      response.headers.set('Cache-Control', 'no-store');
      final origin = request.headers.value(HttpHeaders.hostHeader);
      final segments = request.uri.pathSegments;
      if (origin != '127.0.0.1:${_server.port}' ||
          segments.length < 2 ||
          segments.first != _token ||
          !_safeAsset(segments.skip(1).join('/'))) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final key = segments.skip(1).join('/');
      final model = _models[key];
      final memory = _byteModels[key];
      if (memory != null) {
        response.headers.contentType = ContentType.parse(key.endsWith('.glb') ? 'model/gltf-binary' : 'application/octet-stream');
        response.contentLength = memory.length;
        if (request.method == 'GET') response.add(memory);
      } else if (model != null) {
        final type =
            await FileSystemEntity.type(model.file.path, followLinks: false);
        final stat = await model.file.stat();
        if (type != FileSystemEntityType.file ||
            stat.type != FileSystemEntityType.file ||
            stat.size != model.size ||
            stat.modified != model.modified) {
          response.statusCode = HttpStatus.conflict;
          return;
        }
        response.headers.contentType = ContentType.parse(key.endsWith('.glb')
            ? 'model/gltf-binary'
            : 'application/octet-stream');
        response.contentLength = model.size;
        if (request.method == 'GET')
          await response.addStream(model.file.openRead());
      } else if (_assets.contains(key)) {
        final bytes = await _readAsset(key);
        response.headers.contentType = ContentType.parse(key.endsWith('.html')
            ? 'text/html; charset=utf-8'
            : key.endsWith('.js') || key.endsWith('.mjs')
                ? 'text/javascript; charset=utf-8'
                : 'application/octet-stream');
        response.contentLength = bytes.length;
        if (request.method == 'GET') response.add(bytes);
      } else {
        response.statusCode = HttpStatus.notFound;
      }
    } catch (_) {
      // A client may close a large streamed response during model replacement.
      // Never leak local file paths or terminate the host on that disconnect.
      try {
        response.statusCode = HttpStatus.internalServerError;
      } catch (_) {}
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _models.clear();
    _byteModels.clear();
    await _server.close(force: true);
    await _subscription.cancel();
  }
}

class _Model {
  const _Model(this.file, this.size, this.modified);
  final File file;
  final int size;
  final DateTime modified;
}
