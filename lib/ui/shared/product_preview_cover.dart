import '../../dense/pw38_generated_consumer_leases.dart';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';
import '../scan_record.dart';

/// Immutable owner, run, stage and geometry identity; camera version invalidates
/// older CPU covers that used a different orientation and projection.
final class ProductPreviewCoverSource {
  ProductPreviewCoverSource({
    required this.accountNamespace,
    required this.workId,
    required String captureDir,
    required this.runId,
    required this.stage,
    required this.artifactIdentity,
  }) : captureDir = _canonicalCaptureDir(captureDir);
  final String? accountNamespace;
  final String workId, captureDir, runId, stage, artifactIdentity;
  String get identity => jsonEncode([
    'pw.shared-initial-camera.v2',
    accountNamespace,
    workId,
    captureDir,
    runId,
    stage,
    artifactIdentity,
  ]);
  String get token => sha256.convert(utf8.encode(identity)).toString();
}

/// Observes an existing renderer, once per real producer output. No new WebView
/// or animation loop. Selecting a replacement invalidates older async captures.
final class ProductPreviewCoverWriter {
  String? _selected;
  int _generation = 0;
  final Set<String> _pending = {};
  final Set<String> _attached = {};

  void select(ProductPreviewCoverSource source) {
    if (Pw38GeneratedConsumerLeases.instance.captureOffersClosed(
      source.captureDir,
    )) {
      return;
    }
    if (_selected == source.identity) return;
    _selected = source.identity;
    _generation++;
    // The small durable marker rejects an old run before its first new frame.
    try {
      final capture = Directory(source.captureDir);
      if (capture.resolveSymbolicLinksSync() != capture.absolute.path) return;
      final directory = Directory('${source.captureDir}/.pw_preview_covers');
      if (FileSystemEntity.typeSync(directory.path, followLinks: false) ==
          FileSystemEntityType.link) {
        return;
      }
      directory.createSync(recursive: true);
      final pending = File('${directory.path}/.selection-${source.token}.json');
      pending.writeAsStringSync(
        jsonEncode({'identity': source.identity}),
        flush: true,
      );
      pending.renameSync('${directory.path}/current.json');
    } catch (_) {
      // A missing owner directory cannot authorize any persisted cover.
    }
  }

  void invalidate() {
    _selected = null;
    _generation++;
  }

  bool isSelected(ProductPreviewCoverSource source) =>
      _selected == source.identity;

  Future<String?> capture({
    required ProductPreviewCoverSource source,
    required SharedViewerController controller,
    required bool Function() isCurrent,
    required Future<bool> Function(String path) attach,
  }) async {
    final generation = _generation;
    final identity = source.identity;
    bool current() =>
        generation == _generation && _selected == identity && isCurrent();
    if (!current() ||
        _pending.contains(identity) ||
        _attached.contains(identity)) {
      return null;
    }
    Pw38GeneratedReadLease? read;
    Pw38GeneratedReadLease? captureWrite;
    _pending.add(identity);
    Directory? staged;
    var attached = false;
    var stagingCleaned = false;
    try {
      captureWrite = Pw38GeneratedConsumerLeases.instance.acquireCapture(
        source.captureDir,
        'cover:$identity',
      );
      read = Pw38GeneratedConsumerLeases.instance.acquireIdentity(
        source.artifactIdentity,
        'cover:$identity',
      );
      final result = await controller.capture(
        type: 'image/png',
        canonicalCamera: true,
      );
      if (!current() ||
          result is! String ||
          !result.startsWith('data:image/png;base64,')) {
        return null;
      }
      final bytes = base64Decode(
        result.substring('data:image/png;base64,'.length),
      );
      const signature = [137, 80, 78, 71, 13, 10, 26, 10];
      if (bytes.length < 24 ||
          List.generate(8, (i) => bytes[i] == signature[i]).contains(false)) {
        return null;
      }
      final capture = Directory(source.captureDir);
      if (!current() ||
          !capture.existsSync() ||
          capture.resolveSymbolicLinksSync() != capture.absolute.path) {
        return null;
      }
      final directory = Directory('${capture.path}/.pw_preview_covers');
      if (FileSystemEntity.typeSync(directory.path, followLinks: false) ==
          FileSystemEntityType.link) {
        return null;
      }
      await directory.create(recursive: true);
      if (!current()) return null;
      staged = await directory.createTemp('.pending-');
      final imageHash = sha256.convert(bytes).toString();
      final path = '${directory.path}/${source.token}-$imageHash.png';
      final image = File('${staged.path}/image.png');
      final metadata = File('${staged.path}/identity.json');
      await image.writeAsBytes(bytes, flush: true);
      await metadata.writeAsString(
        jsonEncode({
          'identity': identity,
          'image_sha256': imageHash,
          'camera': 'shared-initial-camera.v2',
          'fit': 'contain',
          'artifact_file': _artifactFileIdentity(
            source.artifactIdentity.lastIndexOf(':') > 0
                ? source.artifactIdentity.substring(
                    0,
                    source.artifactIdentity.lastIndexOf(':'),
                  )
                : null,
          ),
        }),
        flush: true,
      );
      if (!current()) return null;
      await image.rename(path);
      await metadata.rename('$path.json');
      if (!current() || !await attach(path) || !current()) return null;
      attached = true;
      return path;
    } catch (_) {
      debugPrint('[PreviewCover] presentation capture unavailable');
      return null;
    } finally {
      try {
        if (staged != null && staged.existsSync()) {
          await staged.delete(recursive: true);
        }
        stagingCleaned = true;
      } finally {
        read?.release();
        captureWrite?.release();
        _pending.remove(identity);
        if (attached && stagingCleaned) {
          _attached.add(identity);
          if (source.stage == 'glb') {
            Pw38GeneratedConsumerLeases.instance.notifyFinalCoverReady(
              source.captureDir,
              source.artifactIdentity,
            );
          }
        }
      }
    }
  }
}

bool isProductPreviewCoverPath(String path) =>
    File(path).parent.path.split('/').last == '.pw_preview_covers';

/// Validate a persisted cover against the current owner, work, run and artifact.
File? productPreviewCoverFor(ScanRecord record) {
  try {
    final path = record.thumbnailPath, captureDir = record.captureDir;
    // Retirement persists the original shared-camera PNG and its GLB binding
    // in the account record; capture caches and JSON sidecars are disposable.
    if (record.finalCoverSha256 != null &&
        record.finalCoverGlbSha256 != null &&
        record.finalCoverGlbSha256 == record.finalGlbSha256 &&
        path != null &&
        record.artifactPath != null) {
      final reference = Uri.parse(record.artifactPath!);
      final glb = File(
        reference.scheme == 'file'
            ? reference.toFilePath()
            : record.artifactPath!,
      );
      final image = File(path);
      if (FileSystemEntity.typeSync(path, followLinks: false) !=
              FileSystemEntityType.file ||
          image.resolveSymbolicLinksSync() != image.absolute.path ||
          glb.parent.resolveSymbolicLinksSync() != image.parent.path ||
          image.uri.pathSegments.last != '${record.id}.png' ||
          !glb.existsSync() ||
          glb.lengthSync() != record.finalGlbBytes)
        return null;
      final bytes = image.readAsBytesSync();
      const signature = [137, 80, 78, 71, 13, 10, 26, 10];
      if (bytes.length < 24 ||
          List.generate(8, (i) => bytes[i] == signature[i]).contains(false) ||
          sha256.convert(bytes).toString() != record.finalCoverSha256)
        return null;
      return image;
    }
    if (path == null ||
        captureDir == null ||
        !isProductPreviewCoverPath(path)) {
      return null;
    }
    final capture = Directory(captureDir).resolveSymbolicLinksSync();
    final directory = '$capture/.pw_preview_covers';
    final image = File(path);
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
            FileSystemEntityType.file ||
        image.resolveSymbolicLinksSync() != image.absolute.path ||
        image.parent.path != directory) {
      return null;
    }
    final metadataFile = File('$path.json');
    if (FileSystemEntity.typeSync(metadataFile.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    final metadata = jsonDecode(metadataFile.readAsStringSync()) as Map;
    final identity = metadata['identity'] as String;
    final source = jsonDecode(identity) as List;
    final ownedCaptureSuffix =
        '/accounts/v1/${record.accountNamespace}/captures_official/${record.id}';
    final relocatedFinal =
        record.finalGlbSha256 != null &&
        source.length == 7 &&
        source[3] is String &&
        (source[3] as String).endsWith(ownedCaptureSuffix) &&
        capture.endsWith(ownedCaptureSuffix);
    if (source.length != 7 ||
        source[0] != 'pw.shared-initial-camera.v2' ||
        source[1] != record.accountNamespace ||
        source[2] != record.id ||
        (source[3] != capture && !relocatedFinal) ||
        source[4] is! String ||
        (source[4] as String).isEmpty ||
        source[5] is! String ||
        source[6] is! String) {
      return null;
    }
    final selected = File('$directory/current.json');
    if (FileSystemEntity.typeSync(selected.path, followLinks: false) !=
            FileSystemEntityType.file ||
        jsonDecode(selected.readAsStringSync())['identity'] != identity) {
      return null;
    }
    final token = sha256.convert(utf8.encode(identity)).toString();
    final imageHash = sha256.convert(image.readAsBytesSync()).toString();
    if (metadata['image_sha256'] != imageHash ||
        image.uri.pathSegments.last != '$token-$imageHash.png') {
      return null;
    }
    final artifact = source[6] as String;
    final separator = artifact.lastIndexOf(':');
    final artifactPath = separator > 0
        ? artifact.substring(0, separator)
        : null;
    if (!relocatedFinal &&
        metadata['artifact_file'] != null &&
        _artifactFileIdentity(artifactPath) != metadata['artifact_file']) {
      return null;
    }
    if (record.artifactPath != null) {
      final reference = Uri.parse(record.artifactPath!);
      final finalPath = reference.scheme == 'file'
          ? reference.toFilePath()
          : record.artifactPath!;
      if (source[5] != 'glb' ||
          artifactPath == null ||
          !File(finalPath).existsSync() ||
          (!(relocatedFinal &&
                  artifact.endsWith(':${record.finalGlbSha256}') &&
                  artifactPath.endsWith(
                    '/accounts/v1/${record.accountNamespace}/scans_official/${record.id}.glb',
                  ) &&
                  File(finalPath).resolveSymbolicLinksSync().endsWith(
                    '/accounts/v1/${record.accountNamespace}/scans_official/${record.id}.glb',
                  )) &&
              File(finalPath).resolveSymbolicLinksSync() !=
                  File(artifactPath).resolveSymbolicLinksSync()) ||
          metadata['artifact_file'] == null) {
        return null;
      }
    }
    return image;
  } catch (_) {
    return null;
  }
}

/// Capture order is the persisted frame order, never filename or filesystem time.
File? productCaptureFirstPhotoFor(ScanRecord record) {
  try {
    final capturePath = record.captureDir;
    if (capturePath == null) return null;
    final capture = Directory(capturePath).resolveSymbolicLinksSync();
    final manifestPath =
        record.captureManifestPath ?? '$capture/official_photo_bundle.json';
    final manifest = File(manifestPath);
    if (!manifest.resolveSymbolicLinksSync().startsWith('$capture/'))
      return null;
    final document = jsonDecode(manifest.readAsStringSync()) as Map;
    final frames = document['frames'] as List;
    if (frames.isEmpty || frames.first is! Map) return null;
    final first = frames.first as Map;
    final name = first['highresFilename'] ?? first['image_file'];
    if (name is! String ||
        name.isEmpty ||
        name.contains('/') ||
        name.contains('\\') ||
        name == '..')
      return null;
    final directory = record.photosDir ?? '$capture/photos_highres';
    final image = File('$directory/$name');
    if (FileSystemEntity.typeSync(image.path, followLinks: false) !=
            FileSystemEntityType.file ||
        !image.resolveSymbolicLinksSync().startsWith('$capture/') ||
        image.lengthSync() <= 0)
      return null;
    return image;
  } catch (_) {
    return null;
  }
}

String? _artifactFileIdentity(String? path) {
  if (path == null) return null;
  try {
    final file = File(path);
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
            FileSystemEntityType.file ||
        FileSystemEntity.typeSync(
              file.resolveSymbolicLinksSync(),
              followLinks: false,
            ) !=
            FileSystemEntityType.file) {
      return null;
    }
    final stat = file.statSync();
    return jsonEncode([
      file.resolveSymbolicLinksSync(),
      stat.size,
      stat.modified.microsecondsSinceEpoch,
      stat.changed.microsecondsSinceEpoch,
    ]);
  } catch (_) {
    return null;
  }
}

String _canonicalCaptureDir(String path) {
  try {
    return Directory(path).resolveSymbolicLinksSync();
  } catch (_) {
    return Directory(path).absolute.path;
  }
}

/// A legacy cover migration observes the original persisted PLY. It is not a
/// reconstruction stage and never replaces an active producer's selection.
ProductPreviewCoverSource? legacySparseCoverSource(
  ScanRecord record,
  String plyPath,
) {
  try {
    if (record.artifactPath != null || record.captureDir == null) return null;
    final capture = Directory(record.captureDir!).resolveSymbolicLinksSync();
    final selected = File('$capture/.pw_preview_covers/current.json');
    if (selected.existsSync()) {
      final prior =
          jsonDecode(jsonDecode(selected.readAsStringSync())['identity'])
              as List;
      if (prior.length != 7 || prior[4] != 'legacy-sparse') return null;
    }
    final canonical = File(plyPath).resolveSymbolicLinksSync();
    if (!canonical.startsWith('$capture/') ||
        FileSystemEntity.typeSync(plyPath, followLinks: false) !=
            FileSystemEntityType.file) {
      return null;
    }
    final identity = _artifactFileIdentity(canonical);
    if (identity == null || File(canonical).lengthSync() <= 0) return null;
    return ProductPreviewCoverSource(
      accountNamespace: record.accountNamespace,
      workId: record.id,
      captureDir: capture,
      runId: 'legacy-sparse',
      stage: 'sparse',
      artifactIdentity: '$canonical:${sha256.convert(utf8.encode(identity))}',
    );
  } catch (_) {
    return null;
  }
}
