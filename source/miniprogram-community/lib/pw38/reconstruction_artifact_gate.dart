import 'dart:io';
import 'request.dart';
import 'vendor/dart_pipeline/lib/pw38_pipeline.dart';

/// Output locations and fixed shape constraints, never predicted output hashes.
final class ReconstructionOutput {
  ReconstructionOutput(this.path, this.role, {this.shapeBytes, this.prefix, this.suffix}) {
    checkedRelativePath(path);
    if (role.isEmpty || (shapeBytes != null && shapeBytes! <= 0) ||
        ((prefix == null) != (suffix == null)) ||
        [prefix, suffix].whereType<String>().any((s) => s.isEmpty || s.contains('/') || s.contains('\\'))) {
      throw FormatException('Invalid reconstruction output declaration');
    }
  }
  final String path, role;
  final int? shapeBytes;
  final String? prefix, suffix;
  bool get fileSet => prefix != null;
  factory ReconstructionOutput.fromJson(Object? value) {
    final j = object(value);
    if (j.containsKey('sha256') || j.containsKey('bytes')) {
      throw FormatException('Reconstruction outputs must not predeclare observed identities');
    }
    if (j['kind'] != 'file' && j['kind'] != 'file_set') throw FormatException('Output kind required');
    return ReconstructionOutput(string(j, 'path'), string(j, 'role'),
        shapeBytes: j['shape_bytes'] as int?,
        prefix: j['kind'] == 'file_set' ? string(j, 'prefix') : null,
        suffix: j['kind'] == 'file_set' ? string(j, 'suffix') : null);
  }
}

final class ObservedReconstructionArtifact {
  const ObservedReconstructionArtifact(this.path,this.role,this.bytes,this.sha256);
  final String path,role,sha256;
  final int bytes;
}

final class ReconstructionArtifactGate {
  ReconstructionArtifactGate(this.inputRoot, this.runRoot, this.outputs);
  final Directory inputRoot, runRoot;
  final Map<Pw38Stage, List<ReconstructionOutput>> outputs;
  final measured = <String, ObservedReconstructionArtifact>{};

  Future<File> regularFile(Directory root, String relative) async {
    checkedRelativePath(relative);
    if (await root.resolveSymbolicLinks() != root.path) throw StateError('Noncanonical artifact root');
    var current = root.path;
    final parts = relative.split('/');
    for (var i = 0; i < parts.length; i++) {
      current = '$current/${parts[i]}';
      final kind = await FileSystemEntity.type(current, followLinks: false);
      if (kind != (i == parts.length - 1 ? FileSystemEntityType.file : FileSystemEntityType.directory)) {
        throw StateError('Missing or nonregular artifact: $relative');
      }
    }
    return File(current);
  }
  Future<void> verifyInput(Pw38Artifact a) async {
    final f = await regularFile(inputRoot, a.path);
    if (await f.length() != a.bytes || await hashFile(f) != a.sha256) {
      throw StateError('Frozen reconstruction input changed: ${a.path}');
    }
  }
  Future<void> requireFresh() async {
    if (await FileSystemEntity.type(runRoot.path, followLinks: false) != FileSystemEntityType.notFound) {
      throw StateError('Fresh reconstruction output root already exists');
    }
  }
  Future<void> prepare(Pw38Stage stage) async {
    if (stage == Pw38Stage.avVisibility) {
      // The frozen original visibility driver exclusively creates its gate.
      // Validate before creating any parents; never delete/reuse an old gate.
      if (await runRoot.resolveSymbolicLinks() != runRoot.path) {
        throw StateError('Noncanonical visibility output root');
      }
      final nativeOwned = outputs[stage]!
          .where((a) => a.role == 'visibility_byte_gate')
          .map((a) => File('${runRoot.path}/${a.path}').parent.path)
          .toSet();
      if (nativeOwned.isEmpty)
        throw StateError('Original visibility gate missing');
      for (final path in nativeOwned) {
        if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw StateError('Original visibility gate must be absent: $path');
        }
        var current = runRoot.path;
        final parentPath = Directory(path).parent.path;
        final parent = parentPath == runRoot.path
            ? ''
            : parentPath.substring(runRoot.path.length + 1);
        for (final part in parent.split('/').where((p) => p.isNotEmpty)) {
          current = '$current/$part';
          final kind = await FileSystemEntity.type(current, followLinks: false);
          if (kind != FileSystemEntityType.notFound &&
              kind != FileSystemEntityType.directory) {
            throw StateError('Noncanonical visibility gate parent: $current');
          }
        }
      }
      for (final a in outputs[stage]!) {
        final directory = a.fileSet
            ? Directory('${runRoot.path}/${a.path}')
            : File('${runRoot.path}/${a.path}').parent;
        await (a.role == 'visibility_byte_gate' ? directory.parent : directory)
            .create(recursive: true);
      }
      return;
    }
    for (final a in outputs[stage]!) {
      final directory = a.fileSet ? Directory('${runRoot.path}/${a.path}') : File('${runRoot.path}/${a.path}').parent;
      await directory.create(recursive: true);
    }
  }
  Future<List<Map<String, Object?>>> observe(Pw38Stage stage) async {
    final result = <Map<String, Object?>>[];
    final seen = <String>{};
    for (final spec in outputs[stage]!) {
      final paths = <String>[];
      if (spec.fileSet) {
        final directory = Directory('${runRoot.path}/${spec.path}');
        if (await directory.resolveSymbolicLinks() != directory.path) throw StateError('Noncanonical output directory');
        await for (final entity in directory.list(followLinks: false)) {
          final name = entity.path.split('/').last;
          if (name.startsWith(spec.prefix!) && name.endsWith(spec.suffix!)) paths.add('${spec.path}/$name');
        }
        paths.sort();
        if (paths.isEmpty) throw StateError('Native stage produced no ${spec.role} files');
      } else {
        paths.add(spec.path);
      }
      for (final path in paths) {
        if (!seen.add(path)) throw StateError('Output observed twice: $path');
        final f = await regularFile(runRoot, path);
        final bytes = await f.length();
        if ((bytes == 0 && spec.role != 'visibility_byte_gate') || (spec.shapeBytes != null && bytes != spec.shapeBytes)) {
          throw StateError('Produced ${spec.role} shape/size mismatch: $path');
        }
        final a = ObservedReconstructionArtifact(path, spec.role, bytes, await hashFile(f));
        if (measured.containsKey(path)) throw StateError('Output reused across stages: $path');
        measured[path] = a;
        result.add({'path': path, 'role': a.role, 'bytes': bytes, 'sha256': a.sha256,
          'format_evidence': 'actual_native_consumers_recorded_in_stage_receipts'});
      }
    }
    return result;
  }
  Future<void> verifyProduced(String relative) async {
    final a = measured[relative];
    if (a == null) throw StateError('Consumer requires this run observed output: $relative');
    final f = await regularFile(runRoot, relative);
    if (await f.length() != a.bytes || await hashFile(f) != a.sha256) {
      throw StateError('Produced consumer input changed: $relative');
    }
  }
}
