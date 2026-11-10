import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../aether_prefs.dart';
import 'backend_deployment.dart';

enum EndpointConfigSource { builtin, cache, remote }

@immutable
class EndpointConfig {
  const EndpointConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.source,
    this.assetCdnBase,
    this.maxUploadBytes,
    this.deployment = BackendDeployment.legacyGlobal,
  });

  final String supabaseUrl;
  final String supabaseAnonKey;
  final EndpointConfigSource source;
  final BackendDeployment deployment;
  final String? assetCdnBase;
  // Client preflight only; the server must enforce its own size limits.
  final int? maxUploadBytes;

  /// Only public object URLs may go through a public CDN. Never forward a
  /// private signed URL, auth path or credential-bearing URL to that origin.
  String cdnRewrite(String url) {
    final base = assetCdnBase;
    if (base == null || BackendDeployment.httpsOrigin(base) == null) return url;
    final src = Uri.tryParse(url);
    final origin = Uri.tryParse(supabaseUrl);
    if (src == null ||
        origin == null ||
        !src.hasAuthority ||
        src.userInfo.isNotEmpty ||
        src.hasFragment ||
        src.queryParameters.keys.any((key) => key != 'download') ||
        src.origin != origin.origin ||
        !src.path.startsWith('/storage/v1/object/public/')) {
      return url;
    }
    // Only the public download option is forwarded. Unknown query fields may
    // contain credentials/metadata and remain on the original trusted origin.
    final cdn = Uri.parse(base);
    return src
        .replace(scheme: cdn.scheme, host: cdn.host, port: cdn.port)
        .toString();
  }

  @override
  String toString() =>
      'EndpointConfig(${deployment.region.name}/${deployment.id}, '
      '${Uri.tryParse(supabaseUrl)?.host}, source: ${source.name})';
}

/// Runtime manifests cannot choose a different tenant or regional identity.
/// A same-region tenant migration also requires a separately verified plan.
class EndpointConfigResolver {
  EndpointConfigResolver._();
  static const builtinUrl = BackendDeployment.legacyUrl;
  static const builtinAnonKey = BackendDeployment.legacyKey;
  static const defaultColdTimeout = Duration(milliseconds: 2500);
  static const defaultStaleAfter = Duration(hours: 24);
  // Set at startup. Background refresh affects the next launch, not the
  // running Auth client's identity. No runtime region switch is exposed.
  static EndpointConfig? current;

  static Future<EndpointConfig> resolve({
    BackendDeployment? deployment,
    Duration coldTimeout = defaultColdTimeout,
    Duration staleAfter = defaultStaleAfter,
    int? nowMs,
    Dio? client,
  }) async {
    current = null;
    final target = deployment ?? BackendDeployment.fromBuild();
    target.validate(); // Before reading cache or making requests.
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final cache = await _readCache(target);
    EndpointConfig? result;
    if (target.configEndpoints.isNotEmpty) {
      final fetchedAt = cache?.$2;
      if (cache != null &&
          fetchedAt != null &&
          fetchedAt <= now &&
          now - fetchedAt < staleAfter.inMilliseconds) {
        result = cache.$1;
        unawaited(_refresh(target, client, now, coldTimeout));
      } else {
        result = await _fetch(
          target,
          client,
        ).timeout(coldTimeout, onTimeout: () => null).catchError((_) => null);
        if (result != null) await _persist(result, now);
      }
    }
    result ??=
        cache?.$1 ??
        EndpointConfig(
          supabaseUrl: target.supabaseUrl,
          supabaseAnonKey: target.anonKey,
          source: EndpointConfigSource.builtin,
          deployment: target,
        );
    current = result;
    return result;
  }

  static String _cacheKey(BackendDeployment target) =>
      'endpoint_config.v2.${target.namespace}';

  static EndpointConfig? _decode(
    dynamic data,
    BackendDeployment target,
    EndpointConfigSource source,
  ) {
    if (data is! Map ||
        data['region'] != target.region.name ||
        data['deployment_id'] != target.id) {
      return null;
    }
    final url = data['supabase_url'];
    final key = data['supabase_anon_key'];
    if (url is! String || key is! String || !target.acceptsApi(url, key)) {
      return null;
    }
    final cdn = data['asset_cdn_base'];
    final max = data['max_upload_bytes'];
    return EndpointConfig(
      supabaseUrl: url,
      supabaseAnonKey: key,
      deployment: target,
      source: source,
      assetCdnBase: cdn is String && target.acceptsCdn(cdn) ? cdn : null,
      maxUploadBytes: max is int && max > 0 ? max : null,
    );
  }

  static Future<(EndpointConfig, int?)?> _readCache(
    BackendDeployment target,
  ) async {
    try {
      final prefs = await AetherPrefs.getInstance();
      final raw = await prefs.getString(_cacheKey(target));
      if (raw != null) {
        final decoded = jsonDecode(raw);
        final config = _decode(decoded, target, EndpointConfigSource.cache);
        if (config != null) {
          return (
            config,
            decoded['fetched_at_ms'] is int
                ? decoded['fetched_at_ms'] as int
                : null,
          );
        }
      }
      // Import only the exact legacy global tenant, without deleting its cache.
      if (target.isLegacyGlobal) {
        final config = _decode(
          {
            'region': target.region.name,
            'deployment_id': target.id,
            'supabase_url': await prefs.getString(
              'endpoint_config.supabase_url',
            ),
            'supabase_anon_key': await prefs.getString(
              'endpoint_config.supabase_anon_key',
            ),
            'asset_cdn_base': await prefs.getString(
              'endpoint_config.asset_cdn_base',
            ),
            'max_upload_bytes': await prefs.getInt(
              'endpoint_config.max_upload_bytes',
            ),
          },
          target,
          EndpointConfigSource.cache,
        );
        if (config != null) {
          return (config, await prefs.getInt('endpoint_config.fetched_at_ms'));
        }
      }
    } catch (_) {
      /* Missing/corrupt preferences are not a new trust source. */
    }
    return null;
  }

  static Future<EndpointConfig?> _fetch(
    BackendDeployment target,
    Dio? client,
  ) async {
    final dio =
        client ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 3),
            receiveTimeout: const Duration(seconds: 3),
          ),
        );
    try {
      for (final endpoint in target.configEndpoints) {
        try {
          final response = await dio.get<String>(
            endpoint,
            options: Options(
              responseType: ResponseType.plain,
              followRedirects: false,
            ),
          );
          if (response.statusCode != 200 || response.data == null) continue;
          final config = _decode(
            jsonDecode(response.data!),
            target,
            EndpointConfigSource.remote,
          );
          if (config != null) return config;
        } catch (_) {
          /* Try another explicitly configured manifest origin. */
        }
      }
    } finally {
      if (client == null) dio.close();
    }
    return null;
  }

  static Future<void> _refresh(
    BackendDeployment target,
    Dio? client,
    int now,
    Duration timeout,
  ) async {
    try {
      final config = await _fetch(
        target,
        client,
      ).timeout(timeout, onTimeout: () => null);
      if (config != null) await _persist(config, now);
    } catch (_) {
      /* Keep the last validated regional config. */
    }
  }

  static Future<void> _persist(EndpointConfig config, int now) async {
    try {
      final prefs = await AetherPrefs.getInstance();
      // One value avoids torn URL/key/region cache updates.
      await prefs.setString(
        _cacheKey(config.deployment),
        jsonEncode({
          'region': config.deployment.region.name,
          'deployment_id': config.deployment.id,
          'supabase_url': config.supabaseUrl,
          'supabase_anon_key': config.supabaseAnonKey,
          'asset_cdn_base': config.assetCdnBase,
          'max_upload_bytes': config.maxUploadBytes,
          'fetched_at_ms': now,
        }),
      );
    } catch (_) {
      /* Caching failure does not change this launch's identity. */
    }
  }

  @visibleForTesting
  static bool isAcceptable(String url, String key) =>
      BackendDeployment.fromBuild().acceptsApi(url, key);
  @visibleForTesting
  static bool isAcceptableCdn(String url) =>
      BackendDeployment.fromBuild().acceptsCdn(url);

  static Future<void> clearCache({BackendDeployment? deployment}) async {
    final target = deployment ?? BackendDeployment.fromBuild();
    target.validate();
    final prefs = await AetherPrefs.getInstance();
    await prefs.remove(_cacheKey(target));
    if (target.isLegacyGlobal) {
      for (final suffix in [
        'supabase_url',
        'supabase_anon_key',
        'fetched_at_ms',
        'asset_cdn_base',
        'max_upload_bytes',
      ]) {
        await prefs.remove('endpoint_config.$suffix');
      }
    }
  }
}
