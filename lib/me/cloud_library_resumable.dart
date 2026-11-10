import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path/path.dart' as p;
import 'package:tusc/tusc.dart';

import '../util/device_log.dart';
import 'cloud_library_payload.dart';

/// Immutable destination identity. No bearer, signed URL or original capture
/// path is stored in the checkpoint fingerprint or metadata.
class CloudLibraryUploadRequest {
  const CloudLibraryUploadRequest({
    required this.endpoint,
    required this.accountNamespace,
    required this.owner,
    required this.bucket,
    required this.workId,
    required this.revision,
    required this.asset,
    required this.checkpointRoot,
  });

  final Uri endpoint;
  final String accountNamespace;
  final String owner;
  final String bucket;
  final String workId;
  final String revision;
  final CloudLibraryAsset asset;
  final Directory checkpointRoot;
  String get objectPath => '$owner/$workId/$revision/${asset.key}';
  Uri get creationUrl => endpoint.resolve('/storage/v1/upload/resumable');
  String get fingerprint => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            'pw-library-tus-v1',
            creationUrl.toString(),
            accountNamespace,
            owner,
            bucket,
            workId,
            revision,
            asset.key,
            asset.sha256.toLowerCase(),
            asset.bytes,
          ]),
        ),
      )
      .toString();
}

abstract interface class CloudLibraryUploadTransport {
  Future<void> upload(CloudLibraryUploadRequest request);

  /// Abort the HTTP transfer while retaining the SDK's durable checkpoint.
  void pause();
  void dispose();
}

class CloudLibraryUploadInterrupted implements Exception {
  const CloudLibraryUploadInterrupted();
  @override
  String toString() => 'Cloud upload paused; checkpoint retained';
}

/// The unmodified community tusc 4.0.0 SDK owns the TUS protocol, offsets,
/// retries, stale-URL recovery and persistence. This adapter owns account
/// isolation and HTTP cancellation. Its file reader retains at most one
/// 6 MiB SDK chunk, and the HTTP request forwards that chunk as a stream.
class TusCloudLibraryUploadTransport implements CloudLibraryUploadTransport {
  TusCloudLibraryUploadTransport({
    required this.apiKey,
    required this.accessToken,
    required this.check,
    required this.requireOwnedPath,
    this.requestTimeout = const Duration(seconds: 60),
    this.retryDelays,
    this.testHttpClientFactory,
    this.testFileFactory,
    this.diagnostics,
  });

  static const chunkBytes = 6 * 1024 * 1024;
  static final _activeCachePaths = <String>{};
  final String apiKey;
  final String? Function() accessToken;
  final void Function() check;
  final Future<void> Function(String path) requireOwnedPath;
  final Duration requestTimeout;
  final List<Duration>? retryDelays;

  /// Receives only bounded, adapter-owned fields. Never request/error text.
  /// A missing observer uses the existing release-visible device log.
  final void Function(Map<String, Object?>)? diagnostics;

  /// Loopback HTTP or HTTPS on a fixture port requires a test transport.
  /// Production creates and owns an IOClient for each request.
  final http.Client Function()? testHttpClientFactory;
  final XFile Function(String path)? testFileFactory;
  bool _disposed = false;
  _UploadSession? _session;

  void _check() {
    if (_disposed) throw const CloudLibraryUploadInterrupted();
    check();
  }

  @override
  void pause() {
    final session = _session;
    if (session == null) return;
    session.interrupted = true;
    session.sdk?.pauseUpload();
    session.httpClient?.close();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    pause();
  }

  @override
  Future<void> upload(CloudLibraryUploadRequest request) async {
    _check();
    if (_session != null) throw StateError('Cloud file upload already running');
    if (testFileFactory != null && testHttpClientFactory == null) {
      throw StateError('Upload file injection requires a test transport');
    }
    CloudLibraryAsset.fromJson(request.asset.toJson());
    if (request.asset.localPath == null) {
      throw StateError('Missing protected upload snapshot');
    }
    if (request.accountNamespace.isEmpty ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(request.owner) ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(request.bucket) ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(request.workId) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(request.revision)) {
      throw const FormatException('Invalid cloud upload identity');
    }
    final cachePath = p.normalize(request.checkpointRoot.absolute.path);
    if (!_activeCachePaths.add(cachePath)) {
      throw StateError('Cloud account upload already running');
    }
    final diagnostic = _TusDiagnostics(diagnostics);
    final session = _session = _UploadSession();
    void checkSession() {
      _check();
      if (session.interrupted) throw const CloudLibraryUploadInterrupted();
    }

    _OwnedTusCache? cache;
    try {
      final network = session.httpClient = _GuardedTusHttpClient(
        endpoint: request.endpoint,
        apiKey: apiKey,
        accessToken: accessToken,
        check: checkSession,
        requestTimeout: requestTimeout,
        testHttpClientFactory: testHttpClientFactory,
        diagnostic: diagnostic,
        isCancelled: () => session.interrupted || _disposed,
      );
      await requireOwnedPath(request.asset.localPath!);
      checkSession();
      final cacheDirectory = request.checkpointRoot;
      await requireOwnedPath(cacheDirectory.path);
      checkSession();
      await cacheDirectory.create(recursive: true);
      await requireOwnedPath(cacheDirectory.path);
      checkSession();
      cache = _OwnedTusCache(
        cacheDirectory.path,
        check: checkSession,
        requireOwnedPath: requireOwnedPath,
        validateUrl: network.validateUrl,
      );
      final sdk = session.sdk = _IdentityTusClient(
        stableFingerprint: request.fingerprint,
        file:
            testFileFactory?.call(request.asset.localPath!) ??
            XFile(request.asset.localPath!),
        url: request.creationUrl.toString(),
        chunkSize: chunkBytes,
        cache: cache,
        httpClient: network,
        timeout: requestTimeout + const Duration(seconds: 1),
        retryDelays: retryDelays,
        headers: const {'x-upsert': 'false'},
        metadata: {
          'bucketName': request.bucket,
          'objectName': request.objectPath,
          'contentType': 'application/octet-stream',
          'cacheControl': '0',
        },
      );
      if (await sdk.fileSize != request.asset.bytes) {
        throw StateError('Upload snapshot changed');
      }
      checkSession();
      await sdk.startUpload();
      checkSession();
      if (sdk.state != TusUploadState.completed ||
          sdk.offset != request.asset.bytes) {
        throw StateError('Cloud upload is not acknowledged');
      }
      diagnostic.emit({
        'event': 'upload_complete',
        'acknowledged_offset': sdk.offset,
      });
    } catch (error) {
      diagnostic.emit({
        'event': 'upload_error',
        'exception': session.interrupted || _disposed
            ? 'cancelled'
            : _TusDiagnostics.category(error),
      }, failure: true);
      rethrow;
    } finally {
      session.sdk?.close();
      session.httpClient?.close();
      try {
        await cache?.close();
      } finally {
        if (identical(_session, session)) _session = null;
        _activeCachePaths.remove(cachePath);
      }
    }
  }
}

/// Diagnostics cannot alter transport control flow or disclose arbitrary text.
/// At most256 ordinary events plus one failure are emitted per asset attempt.
class _TusDiagnostics {
  _TusDiagnostics(this.observer);
  final void Function(Map<String, Object?>)? observer;
  int _events = 0;
  bool _overflowFailure = false;

  static String category(Object error) {
    if (error is CloudLibraryUploadInterrupted) return 'cancelled';
    if (error is TimeoutException) return 'timeout';
    if (error is SocketException) return 'socket';
    if (error is FileSystemException) return 'filesystem';
    if (error is http.ClientException) return 'client';
    if (error is ProtocolException) return 'protocol';
    if (error is FormatException) return 'format';
    if (error is StateError) return 'state';
    return 'other';
  }

  static int? offset(String? value) {
    if (value == null || !RegExp(r'^[0-9]{1,10}$').hasMatch(value)) return null;
    final parsed = int.tryParse(value);
    return parsed != null && parsed <= CloudLibraryLimits.absoluteMaxBytes
        ? parsed
        : null;
  }

  void emit(Map<String, Object?> fields, {bool failure = false}) {
    if (_events >= 256) {
      if (!failure || _overflowFailure) return;
      _overflowFailure = true;
    }
    _events++;
    try {
      final value = Map<String, Object?>.unmodifiable(fields);
      if (observer != null) {
        observer!(value);
      } else {
        DeviceLog.log('CloudTus', jsonEncode(value));
      }
    } catch (_) {
      // Diagnostic failures must never cancel or change a transfer.
    }
  }
}

class _UploadSession {
  bool interrupted = false;
  TusClient? sdk;
  _GuardedTusHttpClient? httpClient;
}

class _IdentityTusClient extends TusClient {
  _IdentityTusClient({
    required this.stableFingerprint,
    required super.file,
    super.url,
    super.chunkSize,
    super.cache,
    super.httpClient,
    super.timeout,
    super.retryDelays,
    super.headers,
    super.metadata,
  });
  final String stableFingerprint;
  @override
  String generateFingerprint() => stableFingerprint;
}

/// tusc 4.0.0 exposes no cache close method. Only the SDK's path-derived box
/// is closed via Hive's public API; process-wide Hive state is never changed.
/// Coupled to lib/src/cache.dart SHA-256
/// 3dbe4b8b356956a6b019da3230e5c4be6e86180c206221a15790e57fa2cdab4a;
/// its box-name formula must be reviewed before changing the SDK pin.
class _OwnedTusCache implements TusCache {
  _OwnedTusCache(
    this.path, {
    required this.check,
    required this.requireOwnedPath,
    required this.validateUrl,
  }) : delegate = TusPersistentCache(path);
  final String path;
  final TusPersistentCache delegate;
  final void Function() check;
  final Future<void> Function(String) requireOwnedPath;
  final void Function(Uri) validateUrl;
  Future<void> _guard() async {
    check();
    final storagePath = p.join(path, 'tus');
    await requireOwnedPath(storagePath);
    final directory = Directory(storagePath);
    if (await directory.exists()) {
      await for (final entry in directory.list(followLinks: false)) {
        await requireOwnedPath(entry.path);
      }
    }
    check();
  }

  @override
  Future<String?> get(String fingerprint) async {
    await _guard();
    final url = await delegate.get(fingerprint);
    check();
    if (url != null) validateUrl(Uri.parse(url));
    return url;
  }

  @override
  Future<void> set(String fingerprint, String url) async {
    validateUrl(Uri.parse(url));
    await _guard();
    await delegate.set(fingerprint, url);
    check();
  }

  @override
  Future<void> remove(String fingerprint) async {
    await _guard();
    await delegate.remove(fingerprint);
    check();
  }

  @override
  Future<void> clear() => throw UnsupportedError('Only per-upload removal');

  Future<void> close() async {
    final storagePath = p.normalize(p.join(path, 'tus'));
    final boxName =
        'tus-persistent-cache-${sha1.convert(utf8.encode(storagePath))}';
    if (Hive.isBoxOpen(boxName)) await Hive.box<String>(boxName).close();
  }
}

class _GuardedTusHttpClient extends http.BaseClient {
  _GuardedTusHttpClient({
    required this.endpoint,
    required this.apiKey,
    required this.accessToken,
    required this.check,
    required this.requestTimeout,
    required this.testHttpClientFactory,
    required this.diagnostic,
    required this.isCancelled,
  }) {
    final loopbackTest =
        testHttpClientFactory != null &&
        (endpoint.scheme == 'http' || endpoint.scheme == 'https') &&
        (endpoint.host == '127.0.0.1' || endpoint.host == '::1');
    if ((!loopbackTest &&
            (endpoint.scheme != 'https' || endpoint.port != 443)) ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        (endpoint.path.isNotEmpty && endpoint.path != '/') ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        requestTimeout <= Duration.zero ||
        apiKey.isEmpty) {
      throw StateError('Invalid cloud upload endpoint');
    }
  }

  final Uri endpoint;
  final String apiKey;
  final String? Function() accessToken;
  final void Function() check;
  final Duration requestTimeout;
  final http.Client Function()? testHttpClientFactory;
  final _TusDiagnostics diagnostic;
  final bool Function() isCancelled;
  final _requests = <_HttpTransfer>{};
  bool _closed = false;

  void validateUrl(Uri url) {
    const basePath = '/storage/v1/upload/resumable';
    if (url.origin != endpoint.origin ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment ||
        (url.path != basePath && !url.path.startsWith('$basePath/')) ||
        url.pathSegments.any(
          (part) =>
              part.isEmpty ||
              part == '.' ||
              part == '..' ||
              part.contains('/') ||
              part.contains('\\'),
        ) ||
        url.toString().contains('%')) {
      throw StateError('Untrusted cloud upload URL');
    }
  }

  void _check() {
    if (_closed) throw const CloudLibraryUploadInterrupted();
    check();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _check();
    validateUrl(request.url);
    final token = accessToken();
    if (token == null || token.isEmpty) {
      throw StateError('Missing upload authentication');
    }
    final method = const {'HEAD', 'POST', 'PATCH'}.contains(request.method)
        ? request.method
        : 'OTHER';
    final requestedOffset = _TusDiagnostics.offset(
      request.headers['upload-offset'],
    );
    final requestBytes = request.contentLength;
    void report(
      String event, {
      int? status,
      int? acknowledgedOffset,
      String? exception,
    }) {
      diagnostic.emit({
        'event': event,
        'method': method,
        'requested_offset': requestedOffset,
        'request_bytes': requestBytes,
        'status': ?status,
        'acknowledged_offset': ?acknowledgedOffset,
        'exception': ?exception,
      }, failure: exception != null || (status != null && status >= 400));
    }

    report('request_start');
    final transfer = _HttpTransfer(testHttpClientFactory?.call() ?? IOClient());
    _requests.add(transfer);
    var timedOut = false;
    final timer = Timer(requestTimeout, () {
      timedOut = true;
      transfer.abort();
    });
    void cleanup() {
      timer.cancel();
      transfer.close();
      _requests.remove(transfer);
    }

    final forwarded =
        http.AbortableStreamedRequest(
            request.method,
            request.url,
            abortTrigger: transfer.abortSignal.future,
          )
          ..followRedirects = false
          ..maxRedirects = 0
          ..contentLength = request.contentLength
          ..headers.addAll(request.headers);
    forwarded.headers.removeWhere(
      (key, _) =>
          key.toLowerCase() == 'authorization' || key.toLowerCase() == 'apikey',
    );
    forwarded.headers['Authorization'] = 'Bearer $token';
    forwarded.headers['apikey'] = apiKey;
    Future<void> forwardBody() async {
      try {
        await forwarded.sink.addStream(
          request.finalize().map((chunk) {
            _check();
            return chunk;
          }),
        );
      } finally {
        unawaited(forwarded.sink.close());
      }
    }

    try {
      final responseFuture = transfer.client.send(forwarded);
      final bodyFuture = forwardBody();
      final results = await Future.wait<Object?>([responseFuture, bodyFuture]);
      final response = results.first! as http.StreamedResponse;
      _check();
      report(
        'response',
        status: response.statusCode,
        acknowledgedOffset: _TusDiagnostics.offset(
          response.headers['upload-offset'],
        ),
      );
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw StateError('Cloud upload redirect refused');
      }
      final location = response.headers['location'];
      if (location != null) {
        if (location.contains(',')) {
          throw StateError('Ambiguous upload Location');
        }
        validateUrl(request.url.resolve(location));
      }
      Stream<List<int>> checkedResponse() async* {
        var bytes = 0;
        try {
          await for (final chunk in response.stream) {
            _check();
            bytes += chunk.length;
            if (bytes > kCloudLibraryJsonMaxBytes) {
              throw StateError('Cloud upload response exceeds metadata limit');
            }
            yield chunk;
          }
          _check();
        } catch (error) {
          report(
            'request_error',
            status: response.statusCode,
            exception: timedOut
                ? 'timeout'
                : isCancelled()
                ? 'cancelled'
                : _TusDiagnostics.category(error),
          );
          rethrow;
        } finally {
          cleanup();
        }
      }

      return http.StreamedResponse(
        checkedResponse(),
        response.statusCode,
        contentLength: response.contentLength,
        request: request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: false,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (error) {
      report(
        'request_error',
        exception: timedOut
            ? 'timeout'
            : isCancelled()
            ? 'cancelled'
            : _TusDiagnostics.category(error),
      );
      cleanup();
      if (timedOut) {
        throw http.ClientException('Cloud upload request timed out');
      }
      _check();
      rethrow;
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    for (final transfer in _requests.toList()) {
      transfer.abort();
    }
  }
}

class _HttpTransfer {
  _HttpTransfer(this.client);
  final http.Client client;
  final abortSignal = Completer<void>();
  bool closed = false;
  void abort() {
    if (!abortSignal.isCompleted) abortSignal.complete();
    close();
  }

  void close() {
    if (closed) return;
    closed = true;
    client.close();
  }
}
