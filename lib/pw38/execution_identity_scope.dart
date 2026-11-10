import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

/// Execution identity is an IO boundary, never permission to change an engine,
/// texture route, provenance requirement, or algorithm parameter.
final class Pw38ExecutionIdentityScope {
  const Pw38ExecutionIdentityScope._production()
    : isIndependentTest = false,
      bundleRoot = null,
      documentsDirectory = null,
      _infoSha256 = null,
      _packageSha256 = null;

  const Pw38ExecutionIdentityScope._test({
    required this.bundleRoot,
    required this.documentsDirectory,
    required String infoSha256,
    required String packageSha256,
  }) : isIndependentTest = true,
       _infoSha256 = infoSha256,
       _packageSha256 = packageSha256;

  static const production = Pw38ExecutionIdentityScope._production();
  static const _schema = 'PW38_EXECUTION_IDENTITY_SCOPE_V1';
  static const _testProfile = 'independent_product_entry_test_v1';
  static const _testBundle = 'com.kyle.pocketworldOnnxBench.k35476742';
  static const _testBuild = '3811';
  static const _manifest = 'pw38_production/PACKAGE.json';
  final bool isIndependentTest;
  final String? bundleRoot, documentsDirectory;
  final String? _infoSha256, _packageSha256;

  String get bundleId =>
      isIndependentTest ? _testBundle : 'com.kyle.PocketWorld';
  String? get build => isIndependentTest ? _testBuild : null;

  static Future<Pw38ExecutionIdentityScope> independentTest({
    required Directory bundleRoot,
    required Directory documentsDirectory,
  }) async {
    final root = await bundleRoot.resolveSymbolicLinks();
    final documents = await documentsDirectory.resolveSymbolicLinks();
    final info = await _readRegular('$root/Info.plist');
    final manifest = await _readRegular('$root/$_manifest');
    final scope = Pw38ExecutionIdentityScope._test(
      bundleRoot: root,
      documentsDirectory: documents,
      infoSha256: sha256.convert(info).toString(),
      packageSha256: sha256.convert(manifest).toString(),
    );
    await scope.revalidate();
    return scope;
  }

  /// JSON is transport only. Every consumer validates the actual frozen files.
  static Pw38ExecutionIdentityScope fromJson(Map<String, dynamic> value) {
    if (_same(value, production.toJson())) return production;
    const keys = {
      'schema',
      'profile',
      'bundle_id',
      'build',
      'bundle_root',
      'documents_directory',
      'info_plist_sha256',
      'package_sha256',
    };
    if (value.length != keys.length ||
        !keys.every(value.containsKey) ||
        value['schema'] != _schema ||
        value['profile'] != _testProfile ||
        value['bundle_id'] != _testBundle ||
        value['build'] != _testBuild) {
      throw StateError('Unsupported execution identity scope');
    }
    String path(String key) {
      final path = value[key];
      if (path is! String ||
          !path.startsWith('/') ||
          path.endsWith('/') ||
          Uri.directory(path).normalizePath().toFilePath() != '$path/') {
        throw StateError('Canonical absolute identity scope $key required');
      }
      return path;
    }

    String hash(String key) {
      final result = value[key];
      if (result is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(result)) {
        throw StateError('Measured identity scope $key required');
      }
      return result;
    }

    return Pw38ExecutionIdentityScope._test(
      bundleRoot: path('bundle_root'),
      documentsDirectory: path('documents_directory'),
      infoSha256: hash('info_plist_sha256'),
      packageSha256: hash('package_sha256'),
    );
  }

  Map<String, Object?> toJson() => {
    'schema': _schema,
    'profile': isIndependentTest ? _testProfile : 'production',
    'bundle_id': bundleId,
    if (isIndependentTest) ...{
      'build': build,
      'bundle_root': bundleRoot,
      'documents_directory': documentsDirectory,
      'info_plist_sha256': _infoSha256,
      'package_sha256': _packageSha256,
    },
  };

  Future<void> revalidate() async {
    if (!isIndependentTest) return;
    _requireDirectories();
    _requireBytes(
      await _readRegular('$bundleRoot/Info.plist'),
      await _readRegular('$bundleRoot/$_manifest'),
    );
  }

  void _revalidateSync() {
    if (!isIndependentTest) return;
    _requireDirectories();
    _requireBytes(
      _readRegularSync('$bundleRoot/Info.plist'),
      _readRegularSync('$bundleRoot/$_manifest'),
    );
  }

  void _requireDirectories() {
    for (final path in [bundleRoot!, documentsDirectory!]) {
      if (Directory(path).resolveSymbolicLinksSync() != path ||
          FileSystemEntity.typeSync(path, followLinks: false) !=
              FileSystemEntityType.directory) {
        throw StateError('Execution identity directory changed');
      }
    }
  }

  void _requireBytes(List<int> info, List<int> manifest) {
    if (sha256.convert(info).toString() != _infoSha256 ||
        sha256.convert(manifest).toString() != _packageSha256) {
      throw StateError('Actual execution Info/PACKAGE bytes changed');
    }
    final xml = XmlDocument.parse(utf8.decode(info));
    final plist = xml.rootElement;
    if (plist.name.qualified != 'plist' ||
        plist.childElements.length != 1 ||
        plist.childElements.single.name.qualified != 'dict') {
      throw StateError('Actual XML Info.plist dictionary required');
    }
    final children = plist.childElements.single.childElements.toList();
    final fields = <String, XmlElement>{};
    if (children.length.isOdd) throw StateError('Malformed plist dictionary');
    for (var i = 0; i < children.length; i += 2) {
      final key = children[i];
      if (key.name.qualified != 'key' ||
          key.childElements.isNotEmpty ||
          fields.containsKey(key.innerText)) {
        throw StateError('Ambiguous XML plist key');
      }
      fields[key.innerText] = children[i + 1];
    }
    String field(String key) {
      final element = fields[key];
      if (element == null ||
          element.name.qualified != 'string' ||
          element.childElements.isNotEmpty) {
        throw StateError('XML plist identity string required: $key');
      }
      return element.innerText;
    }

    if (field('CFBundleIdentifier') != _testBundle ||
        field('CFBundleVersion') != _testBuild) {
      throw StateError('Actual independent bundle/build mismatch');
    }
    final package = jsonDecode(utf8.decode(manifest));
    if (package is! Map ||
        package['schema'] != 'PW38_PRODUCTION_PACKAGE_V1' ||
        package['bundle_id'] != _testBundle ||
        package['build'] != _testBuild ||
        package['info_plist_sha256'] != _infoSha256 ||
        package['platform'] != Platform.operatingSystem) {
      throw StateError('Actual package and XML execution identity disagree');
    }
  }

  void requirePackage(Map<String, dynamic> package) {
    _revalidateSync();
    if (package['bundle_id'] != bundleId ||
        (isIndependentTest &&
            (package['build'] != build ||
                package['info_plist_sha256'] != _infoSha256)) ||
        (!isIndependentTest &&
            package['identity_scope'] != null &&
            !_same(package['identity_scope'], toJson()))) {
      throw StateError('Package is outside this execution identity scope');
    }
  }

  void requireReceipt(Map<String, Object?> receipt) {
    _revalidateSync();
    final declared = receipt['identity_scope'];
    if (receipt['bundle_id'] != bundleId ||
        (isIndependentTest &&
            (receipt['build'] != build || !_same(declared, toJson()))) ||
        (!isIndependentTest &&
            declared != null &&
            !_same(declared, toJson()))) {
      throw StateError('Receipt is outside this execution identity scope');
    }
  }

  /// Bootstrap strings retain measured identity across the preparer's boundary.
  void requireBootstrap(Map<String, String> bootstrap) {
    _revalidateSync();
    if (bootstrap['bundle_id'] != bundleId ||
        (isIndependentTest &&
            (bootstrap['build'] != build ||
                bootstrap['bundle_path'] != bundleRoot ||
                bootstrap['identity_scope'] == null))) {
      throw StateError('Bootstrap is outside this execution identity scope');
    }
    final declared = bootstrap['identity_scope'];
    if (declared != null) {
      if (!_same(jsonDecode(declared), toJson())) {
        throw StateError('Bootstrap scope differs from actual identity');
      }
    }
  }

  void requireCapture(String captureDir) {
    _revalidateSync();
    if (!isIndependentTest) return;
    final capture = Directory(captureDir).resolveSymbolicLinksSync();
    if (Directory(capture).parent.path !=
            '$documentsDirectory/captures_official' ||
        Directory(capture).parent.parent.path != documentsDirectory) {
      throw StateError('Capture is outside measured independent Documents');
    }
  }

  static bool _same(Object? left, Map<String, Object?> right) =>
      left is Map &&
      left.length == right.length &&
      right.entries.every((entry) => left[entry.key] == entry.value);

  static Future<List<int>> _readRegular(String path) async {
    final file = File(path);
    if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.resolveSymbolicLinks() != path ||
        await file.length() > 8 * 1024 * 1024) {
      throw StateError('Canonical regular execution identity file required');
    }
    return file.readAsBytes();
  }

  static List<int> _readRegularSync(String path) {
    final file = File(path);
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
            FileSystemEntityType.file ||
        file.resolveSymbolicLinksSync() != path ||
        file.lengthSync() > 8 * 1024 * 1024) {
      throw StateError('Canonical regular execution identity file required');
    }
    return file.readAsBytesSync();
  }
}
