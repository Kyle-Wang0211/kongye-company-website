import 'dart:io';

import 'package:crypto/crypto.dart';

/// Legacy pending-token file identity retained for recovery compatibility.
final class CaptureRetirementEntry {
  const CaptureRetirementEntry({
    required this.relativePath,
    required this.bytes,
    required this.sha256,
    this.modifiedMicros,
    this.changedMicros,
    this.mode,
  });
  final String relativePath;
  final int bytes;
  final String sha256;
  final int? modifiedMicros, changedMicros, mode;
}

final class CaptureRetirementResult {
  const CaptureRetirementResult({
    required this.completed,
    required this.deletedPaths,
    required this.alreadyAbsentPaths,
    required this.pendingPaths,
    required this.failures,
    required this.deletedBytes,
  });
  final bool completed;
  final List<String> deletedPaths;
  final List<String> alreadyAbsentPaths;
  final List<String> pendingPaths;
  final Map<String, String> failures;
  final int deletedBytes;
}

/// File lifecycle only: the caller owns account identity, durable publication,
/// GLB format validation, publishing the final cover outside this capture, and
/// closing all capture consumers. The authorization callback must verify those
/// publication prerequisites before deletion. This helper removes the entire
/// capture, including intermediate covers; it does not select a final cover.
/// Authorization must remain valid throughout. Never use against an active run.
final class CaptureArtifactRetirement {
  CaptureArtifactRetirement({
    required this.ownedCaptureRoot,
    required this.publishedGlb,
    required this.expectedGlbSha256,
    required this.expectedGlbBytes,
    required List<CaptureRetirementEntry> manifest,
  }) : manifest = List.unmodifiable(manifest);

  final Directory ownedCaptureRoot;
  final File publishedGlb;
  final String expectedGlbSha256;
  final int expectedGlbBytes;
  final List<CaptureRetirementEntry> manifest;
  bool _busy = false;

  static Future<String> _hash(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
  static final _sha = RegExp(r'^[0-9a-f]{64}$');

  static void _requireRelative(String path) {
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.contains('\\') ||
        path.contains('\u0000') ||
        path.split('/').any((s) => s.isEmpty || s == '.' || s == '..')) {
      throw StateError('Invalid capture retirement relative path: $path');
    }
  }

  static Future<bool> _requireRoot(Directory root) async {
    final parts = root.path.split('/');
    if (!root.path.startsWith('/') ||
        parts.length < 4 ||
        parts.skip(1).any((s) => s.isEmpty || s == '.' || s == '..') ||
        root.parent.uri.pathSegments.where((s) => s.isNotEmpty).last !=
            'captures_official') {
      throw StateError('Expected exact owned captures_official child');
    }
    if (await root.parent.resolveSymbolicLinks() != root.parent.path) {
      throw StateError('Noncanonical capture parent');
    }
    final type = await FileSystemEntity.type(root.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return false;
    if (type != FileSystemEntityType.directory ||
        await root.resolveSymbolicLinks() != root.path) {
      throw StateError('Noncanonical capture root');
    }
    return true;
  }

  Future<void> _requireGlb() async {
    if (expectedGlbBytes < 12 ||
        !_sha.hasMatch(expectedGlbSha256) ||
        !publishedGlb.path.endsWith('.glb') ||
        publishedGlb.path == ownedCaptureRoot.path ||
        publishedGlb.path.startsWith('${ownedCaptureRoot.path}/') ||
        await FileSystemEntity.type(publishedGlb.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await publishedGlb.resolveSymbolicLinks() != publishedGlb.path ||
        await publishedGlb.length() != expectedGlbBytes ||
        await _hash(publishedGlb) != expectedGlbSha256) {
      throw StateError('Published GLB identity/ownership mismatch');
    }
  }

  /// Snapshot only after all capture writers/readers have been closed. The
  /// caller must reuse this exact manifest on retry, never resnapshot a failure.
  static Future<List<CaptureRetirementEntry>> snapshotOwnedCapture(
    Directory root,
  ) async {
    if (!await _requireRoot(root)) return const [];
    final entries = <CaptureRetirementEntry>[];
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is Link || await e.resolveSymbolicLinks() != e.path) {
        throw StateError('Capture contains symbolic link: ${e.path}');
      }
      if (e is File) {
        final relative = e.path.substring(root.path.length + 1);
        _requireRelative(relative);
        final before = await e.stat();
        final digest = await _hash(e);
        final after = await e.stat();
        if (!_sameStat(before, after)) {
          throw StateError('Capture changed during snapshot: $relative');
        }
        entries.add(
          CaptureRetirementEntry(
            relativePath: relative,
            bytes: after.size,
            sha256: digest,
            modifiedMicros: after.modified.microsecondsSinceEpoch,
            changedMicros: after.changed.microsecondsSinceEpoch,
            mode: after.mode,
          ),
        );
      } else if (e is! Directory) {
        throw StateError('Unknown capture entity: ${e.path}');
      }
    }
    entries.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return List.unmodifiable(entries);
  }

  static bool _sameStat(FileStat a, FileStat b) =>
      a.type == FileSystemEntityType.file &&
      b.type == FileSystemEntityType.file &&
      a.size == b.size &&
      a.mode == b.mode &&
      a.modified == b.modified &&
      a.changed == b.changed;

  Future<CaptureRetirementResult> retire({
    required Future<void> Function() requirePublicationAndConsumersDrained,
  }) async {
    if (_busy) throw StateError('Capture retirement already running');
    _busy = true;
    try {
      return await _retire(requirePublicationAndConsumersDrained);
    } finally {
      _busy = false;
    }
  }

  Future<CaptureRetirementResult> _retire(
    Future<void> Function() authorize,
  ) async {
    await authorize();
    await _requireGlb();
    final exists = await _requireRoot(ownedCaptureRoot);
    final paths = <String>[];
    var bytes = 0;
    if (exists) {
      // The caller has preserved the final GLB and final cover outside capture.
      // They supersede this entire record-owned temporary capture.
      // Consumers are closed: new ordinary files are part of the same scope,
      // not a reason to reject an old pending manifest. Never follow a link.
      await for (final entity in ownedCaptureRoot.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is Link ||
            await entity.resolveSymbolicLinks() != entity.path) {
          throw StateError('Capture contains symbolic link: ${entity.path}');
        }
        if (entity is File) {
          paths.add(entity.path.substring(ownedCaptureRoot.path.length + 1));
          bytes += await entity.length();
        } else if (entity is! Directory) {
          throw StateError('Unknown capture entity: ${entity.path}');
        }
      }
    }
    paths.sort();
    final failures = <String, String>{};
    try {
      await authorize();
      await _requireGlb();
      if (await _requireRoot(ownedCaptureRoot)) {
        await ownedCaptureRoot.delete(recursive: true);
      }
      await authorize();
      await _requireGlb();
      if (await FileSystemEntity.type(
            ownedCaptureRoot.path,
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound) {
        throw StateError('Owned capture directory still exists');
      }
    } catch (e) {
      failures['@directory'] = e.toString();
    }
    final absent =
        await FileSystemEntity.type(
          ownedCaptureRoot.path,
          followLinks: false,
        ) ==
        FileSystemEntityType.notFound;
    return CaptureRetirementResult(
      completed: failures.isEmpty && absent,
      deletedPaths: absent ? List.unmodifiable(paths) : const [],
      alreadyAbsentPaths: manifest
          .map((e) => e.relativePath)
          .where((p) => !paths.contains(p))
          .toList(growable: false),
      pendingPaths: absent ? const [] : List.unmodifiable(paths),
      failures: Map.unmodifiable(failures),
      deletedBytes: absent ? bytes : 0,
    );
  }
}
