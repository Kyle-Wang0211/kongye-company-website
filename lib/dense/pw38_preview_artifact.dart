import 'dart:io';

import '../pw38/request.dart' show hashFile;

/// A viewer is an observer; its failure must never become a numerical failure.
final class Pw38PreviewObserver {
  Pw38PreviewObserver(this.callback);
  final void Function(Pw38PreviewArtifact)? callback;
  final errors = <String>[];
  void emit(Pw38PreviewArtifact artifact) {
    try {
      callback?.call(artifact);
    } catch (error) {
      if (errors.length < 5) errors.add('$error');
    }
  }
}

/// A completed producer's immutable output, observed only for display.
final class Pw38PreviewArtifact {
  const Pw38PreviewArtifact({
    required this.path,
    required this.stage,
    required this.role,
    required this.bytes,
    required this.sha256,
  });
  final String path, stage, role, sha256;
  final int bytes;
  String get identity => '$path:$sha256';
  Map<String, Object?> toJson() => {
    'path': path,
    'stage': stage,
    'role': role,
    'bytes': bytes,
    'sha256': sha256,
  };

  static Future<Pw38PreviewArtifact> verify(
    Object? value, {
    required String workRoot,
  }) async {
    if (value is! Map) throw const FormatException('Preview metadata required');
    final path = value['path'], stage = value['stage'], role = value['role'];
    final bytes = value['bytes'], sha = value['sha256'];
    if (path is! String ||
        stage is! String ||
        role is! String ||
        bytes is! int ||
        bytes <= 0 ||
        sha is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ||
        !const {
          'sparse',
          'depth',
          'dense',
          'tsdf',
          'trim',
          'meshopt',
          'lagrange',
          'glb',
        }.contains(stage) ||
        (role != 'ply' && role != 'glb') ||
        (role == 'glb') != (stage == 'glb') ||
        !path.startsWith('$workRoot/') ||
        path.split('/').any((part) => part == '..' || part == '.') ||
        !path.endsWith('.$role')) {
      throw const FormatException('Invalid original38 preview identity');
    }
    if (await Directory(workRoot).resolveSymbolicLinks() != workRoot ||
        await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file ||
        await File(path).resolveSymbolicLinks() != path) {
      throw const FormatException('Noncanonical original38 preview');
    }
    final file = File(path);
    if (await file.length() != bytes ||
        await hashFile(file) != sha ||
        await file.length() != bytes) {
      throw const FormatException('Original38 preview bytes changed');
    }
    return Pw38PreviewArtifact(
      path: path,
      stage: stage,
      role: role,
      bytes: bytes,
      sha256: sha,
    );
  }
}
