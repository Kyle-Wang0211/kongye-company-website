import '../../../frame_transport.dart';
import 'dart:io';

/// IO and stage ownership only. Algorithms and selected parameters stay native.
enum Pw38Stage {
  mvs768,
  mvs1536,
  cer,
  fusionPly,
  tsdf,
  trim,
  meshopt,
  lagrange,
  texture,
  avVisibility,
  avSfmToAbc,
  avNormal,
  glb,
}

const pw38StageOrder = Pw38Stage.values;
const pw38SourceInputManifestSha256 =
    'f6ded2ef12d6fd7d2d08b7e307c7bf9a412e867d3da2ac48e8b84b0b2a100abe';

/// These are source identities and selected-product recipe descriptions, not
/// proof that an ARM binary or full-phone byte gate has passed.
const pw38SelectedRecipe = <String, Object>{
  'ordered_frames': 97,
  'low_grid': [768, 576],
  'high_grid': [1536, 1152],
  'noise': 'original E0, seed 0; lineage gate required',
  'cer_relative_threshold': 0.02,
  'fusion_geo_mask_threshold': 2,
  'fusion_geo_pixel_threshold': 0.125,
  'fusion_geo_depth_threshold': 0.01,
  'fusion_check_all_views': true,
  'fusion_sat_tolerance': 1e-5,
  'fusion_min_tri_angle_degrees': 3.0,
  'fusion_photo_first': false,
  'retained_depth_scale': 5000,
  'meshopt_target_triangles': 100000,
  'lagrange': 'resolve_nonmanifoldness; close_small_holes defaults 16/true',
  'texture_grid': [1920, 1440],
  'texture': 'gmi; gauss_clamping; threads=1; no_intermediate_results',
  'normal': 'AliceVision official entry; textureSide=2048; maxCoresAvailable=1',
  'glb': 'selected Trimesh loader/export; exact original sort-order gate',
};

/// Output roles which must have preregistered artifacts. A role may cover many
/// files; callers register the complete ordered manifest, never sampled output.
const pw38RequiredOutputRoles = <Pw38Stage, Set<String>>{
  Pw38Stage.mvs768: {'depth', 'conf0', 'conf1', 'conf2'},
  Pw38Stage.mvs1536: {'depth', 'conf0', 'conf1', 'conf2'},
  Pw38Stage.cer: {'depth', 'conf0', 'conf1', 'conf2'},
  Pw38Stage.fusionPly: {
    'dense_ply',
    'retained_d16',
    'retained_camera',
    'order',
  },
  Pw38Stage.tsdf: {'mesh_ply'},
  Pw38Stage.trim: {'mesh_ply'},
  Pw38Stage.meshopt: {'positions_f32', 'indices_u32', 'mesh_ply'},
  Pw38Stage.lagrange: {'mesh_ply'},
  Pw38Stage.texture: {'obj', 'mtl', 'color_png'},
  Pw38Stage.avVisibility: {'sfm_json', 'visibility_byte_gate'},
  Pw38Stage.avSfmToAbc: {'sfm_abc'},
  Pw38Stage.avNormal: {'normal_png'},
  Pw38Stage.glb: {'glb'},
};

bool _isHash(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

String checkedRelativePath(String value) {
  final parts = value.split('/');
  if (value.isEmpty ||
      value.startsWith('/') ||
      value.contains('\\') ||
      value.contains('\x00') ||
      parts.any((p) => p.isEmpty || p == '.' || p == '..')) {
    throw FormatException('Noncanonical relative artifact path: $value');
  }
  return value;
}

final class Pw38Artifact {
  Pw38Artifact({
    required this.path,
    required this.role,
    required this.bytes,
    required this.sha256,
  }) {
    checkedRelativePath(path);
    if (role.isEmpty || bytes <= 0 || !_isHash(sha256)) {
      throw const FormatException(
        'Artifact requires a role, positive size and SHA-256',
      );
    }
  }
  final String path;
  final String role;
  final int bytes;
  final String sha256;
}

final class Pw38SourceGates {
  const Pw38SourceGates({
    required this.sourceAccepted,
    required this.originalE0NoiseBytesAccepted,
    required this.platformBytesAccepted,
    required this.vertexColorAccessorBytesAccepted,
  });
  final bool sourceAccepted;
  final bool originalE0NoiseBytesAccepted;
  final bool platformBytesAccepted;
  final bool vertexColorAccessorBytesAccepted;
  bool get accepted =>
      sourceAccepted &&
      originalE0NoiseBytesAccepted &&
      platformBytesAccepted &&
      vertexColorAccessorBytesAccepted;
}

final class Pw38RunContract {
  Pw38RunContract({
    required this.runId,
    required this.sourceInputManifestSha256,
    required this.orderedInputManifestSha256,
    required this.modelManifestSha256,
    required this.environmentManifestSha256,
    required this.sourceGates,
    required List<Pw38Artifact> inputs,
    required Map<Pw38Stage, List<Pw38Artifact>> outputs,
    this.orderedFrames = 97,
    this.denseProducerProfile = originalRetainedLegacyProfile,
  }) : inputs = List.unmodifiable(inputs),
       outputs = Map.unmodifiable(
         outputs.map((k, v) => MapEntry(k, List<Pw38Artifact>.unmodifiable(v))),
       );
  final String runId;
  final String sourceInputManifestSha256;
  final String orderedInputManifestSha256;
  final String modelManifestSha256;
  final String environmentManifestSha256;
  final Pw38SourceGates sourceGates;
  final List<Pw38Artifact> inputs;
  final Map<Pw38Stage, List<Pw38Artifact>> outputs;
  final int orderedFrames;
  final String denseProducerProfile;

  void validate() {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(runId) ||
        orderedFrames != frameTransportCount({'dense_producer_profile': denseProducerProfile}, actualCount: orderedFrames) ||
        sourceInputManifestSha256 != pw38SourceInputManifestSha256 ||
        ![
          orderedInputManifestSha256,
          modelManifestSha256,
          environmentManifestSha256,
        ].every(_isHash) ||
        !sourceGates.accepted ||
        inputs.isEmpty) {
      throw StateError(
        'Selected-38 source/input/model/environment gates unresolved',
      );
    }
    final paths = <String>{};
    for (final stage in pw38StageOrder) {
      final rows = outputs[stage];
      if (rows == null ||
          rows.isEmpty ||
          !rows
              .map((r) => r.role)
              .toSet()
              .containsAll(pw38RequiredOutputRoles[stage]!)) {
        throw StateError('${stage.name} complete output manifest unregistered');
      }
      for (final row in rows) {
        if (!paths.add(row.path))
          throw StateError('Output path reused: ${row.path}');
      }
    }
  }
}

abstract interface class Pw38ArtifactGate {
  Future<void> validateInputs(Pw38RunContract contract);
  Future<void> requireFreshOutputs(Pw38RunContract contract);
  Future<void> verifyOutput(Pw38Stage stage, Pw38Artifact artifact);
}

typedef Pw38FileHash = Future<String> Function(File file);
typedef Pw38FormatGate = Future<void> Function(
  File file,
  Pw38Artifact artifact,
);

/// The host supplies its reviewed streaming SHA-256 and format validators.
/// There is no fallback digest, parser, numeric algorithm or platform branch.
final class Pw38FileArtifactGate implements Pw38ArtifactGate {
  Pw38FileArtifactGate({
    required this.inputRoot,
    required this.runRoot,
    required this.sha256File,
    required this.validateFormat,
  });
  final Directory inputRoot;
  final Directory runRoot;
  final Pw38FileHash sha256File;
  final Pw38FormatGate validateFormat;

  Future<File> _file(Directory root, String relative) async {
    checkedRelativePath(relative);
    var walk = root.absolute.path;
    if (await FileSystemEntity.type(walk, followLinks: false) !=
            FileSystemEntityType.directory ||
        await root.resolveSymbolicLinks() != walk) {
      throw StateError('Artifact root absent, symlinked or noncanonical');
    }
    for (final part in relative.split('/')) {
      walk = '$walk/$part';
      if (await FileSystemEntity.type(walk, followLinks: false) ==
          FileSystemEntityType.link) {
        throw StateError('Symlink artifact rejected');
      }
    }
    return File(walk);
  }

  Future<void> _verify(Directory root, Pw38Artifact a) async {
    final file = await _file(root, a.path);
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.length() != a.bytes ||
        await sha256File(file) != a.sha256) {
      throw StateError('Strict artifact bytes gate failed: ${a.path}');
    }
    await validateFormat(file, a);
  }

  @override
  Future<void> validateInputs(Pw38RunContract contract) async {
    for (final a in contract.inputs) {
      await _verify(inputRoot, a);
    }
  }

  @override
  Future<void> requireFreshOutputs(Pw38RunContract contract) async {
    for (final rows in contract.outputs.values) {
      for (final a in rows) {
        final file = await _file(runRoot, a.path);
        if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw StateError('Refuse output overwrite: ${a.path}');
        }
      }
    }
  }

  @override
  Future<void> verifyOutput(Pw38Stage stage, Pw38Artifact artifact) =>
      _verify(runRoot, artifact);
}

/// Drivers must identify the verified native C ABI entry(s), frozen binary and
/// source evidence. Callables are synchronous native work on a worker isolate.
abstract interface class Pw38StageDriver {
  Pw38Stage get stage;
  String get sourceManifestSha256;
  String get binarySha256;
  List<String> get verifiedCAbiSymbols;
  Future<int> run(Pw38RunContract contract);
}

final class Pw38StageReceipt {
  const Pw38StageReceipt(
    this.stage,
    this.entryReturnCode,
    this.outputGatePassed,
    this.elapsedMicroseconds, [
    this.error,
  ]);
  final Pw38Stage stage;
  final int? entryReturnCode;
  final bool outputGatePassed;
  final int elapsedMicroseconds;
  final String? error;
}

final class Pw38RunResult {
  Pw38RunResult({
    required this.exitCode,
    required this.stoppedReason,
    required List<Pw38StageReceipt> receipts,
  }) : receipts = List.unmodifiable(receipts);
  final int exitCode;
  final String? stoppedReason;
  final List<Pw38StageReceipt> receipts;
  bool get full38Complete =>
      exitCode == 0 &&
      stoppedReason == null &&
      receipts.length == pw38StageOrder.length &&
      receipts.every((r) => r.entryReturnCode == 0 && r.outputGatePassed);
}

final class Pw38SharedPipeline {
  Pw38SharedPipeline({
    required Map<Pw38Stage, Pw38StageDriver> drivers,
    required this.artifactGate,
  }) : _drivers = Map.unmodifiable(drivers);
  final Map<Pw38Stage, Pw38StageDriver> _drivers;
  final Pw38ArtifactGate artifactGate;
  bool _running = false;

  /// Missing capabilities fail before IO gates or any native stage call.
  Future<Pw38RunResult> run(Pw38RunContract contract) async {
    if (_running) {
      return Pw38RunResult(
        exitCode: 38,
        stoppedReason: 'Pipeline already has an active run',
        receipts: [],
      );
    }
    _running = true;
    try {
      return await _runOnce(contract);
    } finally {
      _running = false;
    }
  }

  Future<Pw38RunResult> _runOnce(Pw38RunContract contract) async {
    final receipts = <Pw38StageReceipt>[];
    try {
      final missing = pw38StageOrder
          .where((s) => !_drivers.containsKey(s))
          .toList();
      if (missing.isNotEmpty)
        throw UnsupportedError(
          'Native C ABI stages unavailable: ${missing.map((s) => s.name).join(', ')}',
        );
      for (final stage in pw38StageOrder) {
        final driver = _drivers[stage]!;
        if (driver.stage != stage ||
            driver.sourceManifestSha256 != contract.sourceInputManifestSha256 ||
            !_isHash(driver.binarySha256) ||
            driver.verifiedCAbiSymbols.isEmpty) {
          throw StateError(
            '${stage.name} C ABI/source/binary identity unresolved',
          );
        }
      }
      contract.validate();
      await artifactGate.validateInputs(contract);
      await artifactGate.requireFreshOutputs(contract);
    } catch (e) {
      return Pw38RunResult(
        exitCode: 38,
        stoppedReason: e.toString(),
        receipts: receipts,
      );
    }
    for (final stage in pw38StageOrder) {
      final watch = Stopwatch()..start();
      int? rc;
      try {
        rc = await _drivers[stage]!.run(contract);
        if (rc != 0) {
          receipts.add(
            Pw38StageReceipt(
              stage,
              rc,
              false,
              watch.elapsedMicroseconds,
              'Native stage returned nonzero',
            ),
          );
          return Pw38RunResult(
            exitCode: rc,
            stoppedReason: '${stage.name} returned $rc',
            receipts: receipts,
          );
        }
        for (final artifact in contract.outputs[stage]!) {
          await artifactGate.verifyOutput(stage, artifact);
        }
        receipts.add(
          Pw38StageReceipt(stage, rc, true, watch.elapsedMicroseconds),
        );
      } catch (e) {
        receipts.add(
          Pw38StageReceipt(
            stage,
            rc,
            false,
            watch.elapsedMicroseconds,
            e.toString(),
          ),
        );
        return Pw38RunResult(
          exitCode: 38,
          stoppedReason: e.toString(),
          receipts: receipts,
        );
      } finally {
        watch.stop();
      }
    }
    return Pw38RunResult(exitCode: 0, stoppedReason: null, receipts: receipts);
  }
}

/// Current source-prepared registry deliberately has no complete stage driver:
/// meshopt file ABI exists, but stage PLY bridge needs unbuilt Open3D C ABI.
/// No source-only C ABI declaration is promoted to a verified binary binding.
const pw38UnsupportedStages = <Pw38Stage, String>{
  Pw38Stage.mvs768: 'C++ DenseJob/dense_run only; isolated C ABI absent',
  Pw38Stage.mvs1536: 'C++ DenseJob/dense_run only; isolated C ABI absent',
  Pw38Stage.cer: 'C++ pipeline-internal merge only; isolated C ABI absent',
  Pw38Stage.fusionPly:
      'C++ FuseCamera/FuseParams/std::vector only; C ABI absent',
  Pw38Stage.tsdf:
      'Source declarations; dependency/binary/full-phone byte gates held',
  Pw38Stage.trim: 'Open3D source declarations; verified binary unavailable',
  Pw38Stage.meshopt: 'Verified file ABI; complete PLY bridge not verified',
  Pw38Stage.lagrange:
      'Verified file ABI; full selected-input phone bytes not accepted',
  Pw38Stage.texture: 'Source C ABI only; no verified exported library frozen',
  Pw38Stage.avVisibility: 'Source C ABI; original color and byte gates held',
  Pw38Stage.avSfmToAbc: 'Source C ABI; verified binary unavailable',
  Pw38Stage.avNormal: 'Source C ABI; dependency/binary/phone gates held',
  Pw38Stage.glb: 'Declared full entry; original ARM OBJ/sort backend held',
};
