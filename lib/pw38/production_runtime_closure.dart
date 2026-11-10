import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'request.dart' show hashFile, object, string;
import 'package:pocketworld_flutter/pw38/vendor/dart_pipeline/lib/pw38_pipeline.dart'
    show checkedRelativePath;

/// The same measured closure is checked during discovery, before worker native
/// initialization, and whenever the original producer execution proof is used.
/// Only canonical paths and actual manifest/member bytes confer this identity.
final class ProductionRuntimeClosure {
  ProductionRuntimeClosure._(
    this.bundleRoot,
    this.packageSha256,
    this._packageJson,
    this._roots,
  );
  final String bundleRoot, packageSha256, _packageJson;
  final List<String> _roots;

  static Future<ProductionRuntimeClosure> capture({
    required String bundleRoot,
    required Map<String, dynamic> package,
    required String packageSha256,
    required Map<String, dynamic> provider,
  }) async {
    if (!bundleRoot.startsWith('/') ||
        await Directory(bundleRoot).resolveSymbolicLinks() != bundleRoot) {
      throw StateError('Canonical runtime bundle root required');
    }
    final closure = ProductionRuntimeClosure._(
      bundleRoot,
      packageSha256,
      jsonEncode(package),
      List<String>.unmodifiable([
        for (final key in [
          'runtime_home_bundle_relative_path',
          'native_modules_bundle_relative_path',
        ])
          checkedRelativePath(string(provider, key)),
      ]),
    );
    await closure.revalidate();
    return closure;
  }

  Future<File> _file(String relative) async {
    final file = File('$bundleRoot/${checkedRelativePath(relative)}');
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.resolveSymbolicLinks() != file.path) {
      throw StateError('Regular canonical runtime file required: $relative');
    }
    return file;
  }

  Future<File> _verify(String path, Object? expected, {int? bytes}) async {
    if (expected is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
      throw StateError('Frozen runtime SHA-256 required: $path');
    }
    final file = await _file(path);
    final size = await file.length();
    if ((bytes != null && size != bytes) ||
        await hashFile(file) != expected ||
        await file.length() != size) {
      throw StateError('Packaged runtime bytes changed: $path');
    }
    return file;
  }

  Map<String, String> get identity {
    final package = object(jsonDecode(_packageJson));
    return {
      'runtime_manifest_path': string(package, 'runtime_manifest_path'),
      'runtime_manifest_sha256': string(package, 'runtime_manifest_sha256'),
      'package_sha256': packageSha256,
    };
  }

  void requireProvider(Map<String, dynamic> provider) {
    final roots = [
      string(provider, 'runtime_home_bundle_relative_path'),
      string(provider, 'native_modules_bundle_relative_path'),
    ];
    for (var i = 0; i < _roots.length; i++) {
      if (roots[i] != _roots[i]) {
        throw StateError(
          'Execution provider differs from measured runtime closure',
        );
      }
    }
  }

  Future<Map<String, dynamic>> _frozenJson(String path, String expected) async {
    final file = await _verify(path, expected);
    if (await file.length() > 8 * 1024 * 1024) {
      throw StateError('Oversized runtime identity JSON');
    }
    final bytes = await file.readAsBytes();
    if (sha256.convert(bytes).toString() != expected) {
      throw StateError('Runtime identity JSON changed while parsing');
    }
    return object(jsonDecode(utf8.decode(bytes)));
  }

  Future<void> revalidate() async {
    final package = object(jsonDecode(_packageJson));
    final measured = await _frozenJson(
      'pw38_production/PACKAGE.json',
      packageSha256,
    );
    for (final key in [
      'info_plist_sha256',
      'runtime_manifest_path',
      'runtime_manifest_sha256',
    ]) {
      if (measured[key] != package[key]) {
        throw StateError(
          'Runtime identity is not bound to measured PACKAGE.json: $key',
        );
      }
    }
    requireProvider(object(measured['camera_native_row']));
    await _verify('Info.plist', package['info_plist_sha256']);
    final manifestPath = checkedRelativePath(
      string(package, 'runtime_manifest_path'),
    );
    final manifestHash = string(package, 'runtime_manifest_sha256');
    final manifest = await _frozenJson(manifestPath, manifestHash);
    if (manifest['schema'] != 'PW38_PRODUCTION_RUNTIME_FILES_V1' ||
        manifest['files'] is! List) {
      throw StateError('Runtime exact file closure manifest required');
    }
    final files = <String>{};
    for (final raw in manifest['files'] as List) {
      final row = object(raw),
          path = checkedRelativePath(string(object(raw), 'path'));
      if (!files.add(path) ||
          row['bytes'] is! int ||
          (row['bytes'] as int) < 0) {
        throw StateError('Runtime manifest duplicate/invalid file: $path');
      }
      await _verify(path, row['sha256'], bytes: row['bytes'] as int);
    }
    for (final relative in _roots) {
      final directory = Directory('$bundleRoot/$relative');
      if (await FileSystemEntity.type(directory.path, followLinks: false) !=
              FileSystemEntityType.directory ||
          await directory.resolveSymbolicLinks() != directory.path) {
        throw StateError('Canonical runtime directory required: $relative');
      }
      final actual = <String>{};
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is Directory) continue;
        if (entity is! File) {
          throw StateError('Runtime closure contains a link: ${entity.path}');
        }
        actual.add(entity.path.substring(bundleRoot.length + 1));
      }
      final declared = files
          .where((path) => path.startsWith('$relative/'))
          .toSet();
      if (actual.isEmpty ||
          actual.length != declared.length ||
          !actual.containsAll(declared)) {
        throw StateError('Runtime file closure incomplete: $relative');
      }
    }
    await _verify(manifestPath, manifestHash);
    await _verify('Info.plist', package['info_plist_sha256']);
    await _verify('pw38_production/PACKAGE.json', packageSha256);
  }
}
