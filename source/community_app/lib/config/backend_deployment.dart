import 'package:flutter/foundation.dart';

enum BackendRegion { china, international }

/// Build-owned trust, never inferred from locale, network, user input or cache.
/// This does not establish server-side isolation or authorize a live cutover.
@immutable
class BackendDeployment {
  const BackendDeployment({
    required this.region,
    required this.id,
    required this.supabaseUrl,
    required this.anonKey,
    this.configEndpoints = const [],
    this.publicCdnOrigins = const [],
  });

  static const legacyUrl = 'https://tzvwkqmgaourwqrmxbyb.supabase.co';
  static const legacyKey = 'sb_publishable_ur4tTV2iXSV4NsL3YYttyw_SIjFAMST';
  static const legacyGlobal = BackendDeployment(
    region: BackendRegion.international,
    id: 'global-primary',
    supabaseUrl: legacyUrl,
    anonKey: legacyKey,
  );

  final BackendRegion region;
  final String id;
  final String supabaseUrl;
  final String anonKey;
  final List<String> configEndpoints;
  final List<String> publicCdnOrigins;

  /// The CN entrypoint owns the region in source, even if iOS loses defines.
  /// Missing credentials then fail validation instead of selecting global.
  static BackendDeployment chinaFromBuild() {
    const region = String.fromEnvironment(
      'PW_BACKEND_REGION',
      defaultValue: 'china',
    );
    const deploymentId = String.fromEnvironment(
      'PW_DEPLOYMENT_ID',
      defaultValue: 'cn-primary',
    );
    const url = String.fromEnvironment('PW_CN_SUPABASE_URL');
    final matchesChinaPrimary =
        region == 'china' &&
        deploymentId == 'cn-primary' &&
        const String.fromEnvironment('PW_AUTH_NAMESPACE_GENERATION') == 'rds20261104' &&
        httpsOrigin(url) == 'https://api.kongye.space';
    return BackendDeployment(
      region: BackendRegion.china,
      id: matchesChinaPrimary ? deploymentId : '',
      supabaseUrl: url,
      anonKey: const String.fromEnvironment('PW_CN_SUPABASE_ANON_KEY'),
    );
  }

  // iOS define propagation requires a separate signed-build gate before a CN
  // release. These values are not live routing or a runtime region switch.
  static BackendDeployment fromBuild() {
    const region = String.fromEnvironment(
      'PW_BACKEND_REGION',
      defaultValue: 'international',
    );
    if (region == 'china') {
      return chinaFromBuild();
    }
    if (region != 'international') throw StateError('Unknown backend region');
    const url = String.fromEnvironment('SUPABASE_URL');
    const key = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (url.isNotEmpty != key.isNotEmpty) {
      throw StateError(
        'Backend URL and publishable key must be configured together',
      );
    }
    return const BackendDeployment(
      region: BackendRegion.international,
      id: String.fromEnvironment(
        'PW_DEPLOYMENT_ID',
        defaultValue: 'global-primary',
      ),
      supabaseUrl: url == '' ? legacyUrl : url,
      anonKey: key == '' ? legacyKey : key,
    );
  }

  static String? httpsOrigin(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    return uri.origin;
  }

  void validate() {
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$').hasMatch(id) ||
        httpsOrigin(supabaseUrl) == null ||
        anonKey.trim().isEmpty) {
      throw StateError('Incomplete or invalid regional backend configuration');
    }
    if (region == BackendRegion.china &&
        httpsOrigin(supabaseUrl) == legacyUrl) {
      throw StateError('China deployment cannot use the international tenant');
    }
    if (publicCdnOrigins.any((value) => httpsOrigin(value) == null)) {
      throw StateError('Invalid regional CDN origin');
    }
    for (final value in configEndpoints) {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.port != 443 ||
          uri.hasFragment) {
        throw StateError('Invalid regional configuration endpoint');
      }
    }
  }

  bool acceptsApi(String url, String key) =>
      key.trim().isNotEmpty &&
      httpsOrigin(url) != null &&
      httpsOrigin(url) == httpsOrigin(supabaseUrl);
  bool acceptsCdn(String url) =>
      httpsOrigin(url) != null &&
      publicCdnOrigins.any(
        (allowed) => httpsOrigin(allowed) == httpsOrigin(url),
      );
  bool get isLegacyGlobal =>
      region == BackendRegion.international &&
      id == legacyGlobal.id &&
      httpsOrigin(supabaseUrl) == legacyUrl;
  String get namespace =>
      '${region.name}.$id.${Uri.encodeComponent(Uri.parse(supabaseUrl).origin)}'
      '.${const String.fromEnvironment('PW_AUTH_NAMESPACE_GENERATION')}';
}
