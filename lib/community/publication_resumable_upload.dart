import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:tusc/tusc.dart';

import 'publication_file_source.dart';

/// Storage callbacks contain only fingerprint -> TUS URL mappings. They must
/// persist a set before returning and must never store authorization headers.
class PublicationTusCheckpointStore {
  const PublicationTusCheckpointStore({
    required this.read,
    required this.write,
    required this.remove,
  });
  final Future<String?> Function(String key) read;
  final Future<void> Function(String key, String value) write;
  final Future<void> Function(String key) remove;
}

/// Credentials are supplied freshly by the server-owned publication flow.
/// This class does not cache them in checkpoint storage or error messages.
class PublicationTusAuthorization {
  const PublicationTusAuthorization({
    required this.signedToken,
    this.accessToken,
    this.apiKey,
  });
  final String signedToken;
  final String? accessToken;
  final String? apiKey;
}

class PublicationUploadPaused implements Exception {
  const PublicationUploadPaused();
  @override
  String toString() => 'Publication upload paused; checkpoint retained';
}

/// Supabase's official TUS workflow through the unchanged pinned tusc SDK.
/// The upstream SDK owns POST/HEAD/PATCH, offsets, retries and URL expiration.
class PublicationResumableUpload {
  PublicationResumableUpload({
    required this.apiOrigin,
    required this.owner,
    required this.bucket,
    required this.path,
    required this.source,
    required this.check,
    required this.authorization,
    required this.checkpoints,
    this.requestTimeout = const Duration(seconds: 90),
    this.httpClientFactory,
  }) {
    if (apiOrigin.scheme != 'https' ||
        apiOrigin.userInfo.isNotEmpty ||
        apiOrigin.hasQuery ||
        apiOrigin.hasFragment ||
        (apiOrigin.path.isNotEmpty && apiOrigin.path != '/') ||
        apiOrigin.host.isEmpty ||
        !RegExp(r'^[a-f0-9-]{36}$').hasMatch(owner) ||
        !const {
          'publication-staging',
          'publication-selection-staging',
        }.contains(bucket) ||
        !RegExp(
          '^${RegExp.escape(owner)}/[a-f0-9-]{36}/source[.]${source.format.extension}\$',
        ).hasMatch(path) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(source.sha256) ||
        source.byteLength < 20 ||
        source.byteLength > 9007199254740991 ||
        requestTimeout <= Duration.zero) {
      throw const FormatException('Invalid resumable publication identity');
    }
  }

  static const chunkBytes = 6 * 1024 * 1024;
  final Uri apiOrigin;
  final String owner, bucket, path;
  final PublicationFileSource source;
  final void Function() check;
  final Future<PublicationTusAuthorization> Function() authorization;
  final PublicationTusCheckpointStore checkpoints;
  final Duration requestTimeout;
  final http.Client Function()? httpClientFactory;
  TusClient? _sdk;
  _PublicationTusHttp? _network;
  bool _paused = false, _disposed = false, _running = false;

  String get fingerprint => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            'pw-publication-signed-tus-v2',
            apiOrigin.origin,
            owner,
            bucket,
            path,
            source.sha256,
            source.byteLength,
          ]),
        ),
      )
      .toString();

  void _check() {
    if (_paused || _disposed) throw const PublicationUploadPaused();
    check();
  }

  void pause() {
    _paused = true;
    _sdk?.pauseUpload();
    _network?.close();
  }

  void dispose() {
    _disposed = true;
    pause();
  }

  Future<void> upload({void Function(int sent, int total)? onProgress}) async {
    if (_disposed || _running) throw const PublicationUploadPaused();
    _paused = false;
    _check();
    _running = true;
    final network = _network = _PublicationTusHttp(
      origin: apiOrigin,
      check: _check,
      authorization: authorization,
      timeout: requestTimeout,
      factory: httpClientFactory ?? http.Client.new,
    );
    final sdk = _sdk = _PublicationTusClient(
      identity: fingerprint,
      file: source.file,
      url: apiOrigin.resolve('/storage/v1/upload/resumable/sign').toString(),
      chunkSize: chunkBytes,
      // The adapter bounds authorization + send + response consumption as one
      // operation, closing its HTTP client before reporting a retryable error.
      // Keep the SDK's secondary timer beyond that complete operation.
      timeout: requestTimeout + const Duration(seconds: 30),
      httpClient: network,
      cache: _PublicationTusCache(
        fingerprint,
        checkpoints,
        network.validate,
        _check,
      ),
      headers: const {'x-upsert': 'false'},
      metadata: {
        'bucketName': bucket,
        'objectName': path,
        'contentType': source.format.contentType,
        'cacheControl': '0',
      },
    );
    try {
      if (await sdk.fileSize != source.byteLength) {
        throw StateError('Publication source changed');
      }
      _check();
      await sdk.startUpload(
        onProgress: (count, total, response) {
          _check();
          // SDK's pre-send progress on web is buffered; report confirmed chunks.
          if (response != null) onProgress?.call(sdk.offset, total);
        },
      );
      _check();
      if (sdk.state != TusUploadState.completed ||
          sdk.offset != source.byteLength) {
        throw StateError('Publication upload not acknowledged');
      }
      onProgress?.call(source.byteLength, source.byteLength);
    } finally {
      sdk.close();
      network.close();
      _sdk = null;
      _network = null;
      _running = false;
    }
  }
}

class _PublicationTusClient extends TusClient {
  _PublicationTusClient({
    required this.identity,
    required super.file,
    required super.url,
    required super.chunkSize,
    required super.timeout,
    required super.httpClient,
    required super.cache,
    required super.headers,
    required super.metadata,
  });
  final String identity;
  @override
  String generateFingerprint() => identity;
}

class _PublicationTusCache implements TusCache {
  _PublicationTusCache(this.identity, this.store, this.validate, this.check);
  final String identity;
  final PublicationTusCheckpointStore store;
  final void Function(Uri) validate;
  final void Function() check;
  void guard(String fingerprint) {
    check();
    if (fingerprint != identity) {
      throw StateError('Publication checkpoint mismatch');
    }
  }

  @override
  Future<String?> get(String fingerprint) async {
    guard(fingerprint);
    final value = await store.read(identity);
    guard(fingerprint);
    if (value != null) validate(Uri.parse(value));
    return value;
  }

  @override
  Future<void> set(String fingerprint, String url) async {
    guard(fingerprint);
    validate(Uri.parse(url));
    await store.write(identity, url);
    guard(fingerprint);
  }

  @override
  Future<void> remove(String fingerprint) async {
    guard(fingerprint);
    await store.remove(identity);
    guard(fingerprint);
  }

  @override
  Future<void> clear() => throw UnsupportedError('Per-upload removal only');
}

class _PublicationTusHttp extends http.BaseClient {
  _PublicationTusHttp({
    required this.origin,
    required this.check,
    required this.authorization,
    required this.timeout,
    required this.factory,
  });
  final Uri origin;
  final void Function() check;
  final Future<PublicationTusAuthorization> Function() authorization;
  final Duration timeout;
  final http.Client Function() factory;
  final _active = <http.Client>{};
  bool _closed = false;

  void validate(Uri url) {
    const base = '/storage/v1/upload/resumable/sign';
    if (url.origin != origin.origin ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment ||
        (url.path != base && !url.path.startsWith('$base/')) ||
        url.pathSegments.any(
          (s) =>
              s.isEmpty ||
              s == '.' ||
              s == '..' ||
              s.contains('/') ||
              s.contains('\\'),
        )) {
      throw StateError('Untrusted publication upload URL');
    }
  }

  void guard() {
    if (_closed) throw const PublicationUploadPaused();
    check();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    guard();
    validate(request.url);
    if (!const {'POST', 'HEAD', 'PATCH'}.contains(request.method) ||
        (request.contentLength ?? 0) > PublicationResumableUpload.chunkBytes) {
      throw StateError('Invalid publication upload request');
    }
    var expired = false;
    http.Client? client;
    void release() {
      final active = client;
      if (active == null) return;
      client = null;
      _active.remove(active);
      active.close();
    }

    void checkRequest() {
      // Authorization can finish after the deadline. It must never start a
      // late PATCH while upstream is already retrying a timed-out request.
      if (expired) {
        throw http.ClientException('Publication upload request timed out');
      }
      guard();
    }

    Future<http.StreamedResponse> operation() async {
      final auth = await authorization();
      checkRequest();
      if (auth.signedToken.isEmpty ||
          auth.signedToken.contains('\r') ||
          auth.signedToken.contains('\n')) {
        throw StateError('Publication upload authorization unavailable');
      }
      request.headers['x-signature'] = auth.signedToken;
      if (auth.accessToken != null) {
        request.headers['authorization'] = 'Bearer ${auth.accessToken}';
      }
      if (auth.apiKey != null) request.headers['apikey'] = auth.apiKey!;
      request.followRedirects = false;
      final active = client = factory();
      _active.add(active);
      final response = await active.send(request);
      checkRequest();
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw StateError('Publication upload redirect rejected');
      }
      // TUS responses are control data, not file payloads. Consume their small
      // bounded body under the same deadline so no live response stream escapes
      // the operation and its HTTP client is released before SDK retry.
      final body = BytesBuilder(copy: false);
      await for (final bytes in response.stream) {
        checkRequest();
        if (body.length + bytes.length > 65536) {
          throw StateError('Publication upload response too large');
        }
        body.add(bytes);
      }
      checkRequest();
      final bytes = body.takeBytes();
      return http.StreamedResponse(
        Stream.value(bytes),
        response.statusCode,
        contentLength: bytes.length,
        headers: response.headers,
        request: request,
        reasonPhrase: response.reasonPhrase,
      );
    }

    try {
      return await operation().timeout(
        timeout,
        onTimeout: () {
          expired = true;
          release();
          // tusc's unchanged retry policy recognizes ClientException and rereads
          // the server offset before trying another chunk.
          throw http.ClientException('Publication upload request timed out');
        },
      );
    } finally {
      expired = true;
      release();
    }
  }

  @override
  void close() {
    _closed = true;
    for (final client in _active.toList()) {
      client.close();
    }
    _active.clear();
  }
}
