import 'memory_policy.dart';
import 'frame_transport.dart';

import 'dart:typed_data';

import 'whole_dense_binding.dart'
    show validateWholeDenseReceipt, wholeDenseNativeEntry;
import 'request.dart' show object, string;
import 'execution_identity_scope.dart';
import 'original_retention_io.dart';
import 'vendor/dart_pipeline/lib/pw38_pipeline.dart';

/// Measured output identity, never a predicted hash or an algorithm result.
final class Pw38ObservedOutput {
  Pw38ObservedOutput(Map<String, dynamic> row, String outputRoot)
    : relativePath = checkedRelativePath(string(row, 'path')),
      role = string(row, 'role'),
      bytes = row['bytes'] as int,
      sha256 = string(row, 'sha256'),
      root = outputRoot {
    if (bytes <= 0 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw StateError('Output requires actual positive size and SHA-256');
    }
  }
  final String relativePath, role, sha256, root;
  final int bytes;
  String get path => '$root/$relativePath';
  Map<String, Object?> get row => {
    'path': relativePath,
    'role': role,
    'bytes': bytes,
    'sha256': sha256,
  };
}

sealed class Pw38DenseOutput {
  const Pw38DenseOutput();
}

final class Pw38DensePlyOutput extends Pw38DenseOutput {
  const Pw38DensePlyOutput(this.artifact);
  final Pw38ObservedOutput artifact;
}

/// Retained tuple layout shared by the original and whole GPU producers.
/// This output type makes no claim that their numerical profiles are identical.
final class Pw38OriginalRetainedOutput extends Pw38DenseOutput {
  Pw38OriginalRetainedOutput(
    this.directory,
    List<Pw38ObservedOutput> files,
    this.keptTotal,
  ) : files = List.unmodifiable(files);
  final String directory;
  final List<Pw38ObservedOutput> files;
  final int keptTotal;
}

/// Shared runner and publisher use the same profile-specific output contract.
/// Parsing this receipt does not verify file bytes or establish phone acceptance.
final class Pw38ProductionOutputContract {
  const Pw38ProductionOutputContract._(
    this.glb,
    this.dense,
    this.identityScope,
  );
  final Pw38ExecutionIdentityScope identityScope;
  final Pw38ObservedOutput glb;
  final Pw38DenseOutput dense;

  factory Pw38ProductionOutputContract.fromReceipt(
    Map<String, Object?> receipt, {
    required String workRoot,
    Pw38ExecutionIdentityScope identityScope =
        Pw38ExecutionIdentityScope.production,
  }) {
    identityScope.requireReceipt(receipt);
    final stages = receipt['stages'];
    final terminal = receipt['terminal_glb_format_validation'];
    final native = receipt['dense_native_result'];
    final profile = receipt['dense_producer_profile'];
    final whole = profile == wholeRetainedTransportProfile;
    final count = frameTransportCount({
      'dense_producer_profile': profile,
      'ordered_frames':
          receipt['ordered_frames'] ??
          (profile == originalRetainedProfile || whole ? null : 97),
    });
    if (receipt['execution_entry'] != 'shared_mainline' ||
        receipt['full38_complete'] != true ||
        receipt['exit_code'] != 0 ||
        receipt['stopped_reason'] != null ||
        stages is! List ||
        stages.length != pw38StageOrder.length ||
        terminal is! Map ||
        terminal['status'] != 'PASS_TERMINAL_GLB_STRUCTURE' ||
        native is! Map ||
        native['status'] != 0 ||
        native['frames'] != count ||
        native['fused_frames'] != count ||
        (profile != null &&
            profile != originalRetained97Profile &&
            profile != originalRetainedProfile &&
            !whole)) {
      throw StateError('Incomplete original38 receipt or unsupported profile');
    }
    for (var i = 0; i < stages.length; i++) {
      final stage = stages[i];
      if (stage is! Map ||
          stage['stage'] != pw38StageOrder[i].name ||
          stage['entry_return_code'] != 0 ||
          (i >= 2 && stage['output_identity_status'] != 'OBSERVED_THIS_RUN')) {
        throw StateError('Original38 stage receipt missing or out of order');
      }
    }
    List<Map<String, dynamic>> rows(int stage) {
      final outputs = object(stages[stage])['outputs'];
      if (outputs is! List) throw StateError('Actual output manifest missing');
      return outputs.map(object).toList();
    }

    Map<String, dynamic> one(List<Map<String, dynamic>> rows, String role) {
      final matches = rows.where((row) => row['role'] == role).toList();
      if (matches.length != 1) throw StateError('Unique actual $role required');
      return matches.single;
    }

    final glbRow = one(rows(12), 'glb');
    final glbRelative = checkedRelativePath(string(glbRow, 'path'));
    final glbPath = string(object(terminal), 'absolute_path');
    if (!glbPath.startsWith('$workRoot/') ||
        !glbPath.endsWith('/$glbRelative')) {
      throw StateError('Terminal GLB is outside this run');
    }
    final outputRoot = glbPath.substring(
      0,
      glbPath.length - glbRelative.length - 1,
    );
    final glb = Pw38ObservedOutput(glbRow, outputRoot);
    final stageFormat = object(stages.last)['terminal_glb_format_validation'];
    if (terminal['file_bytes'] != glb.bytes ||
        stageFormat is! Map ||
        stageFormat['status'] != terminal['status'] ||
        stageFormat['file_bytes'] != glb.bytes) {
      throw StateError('Terminal GLB format and observed bytes disagree');
    }
    final fusionRows = rows(3);
    if (profile == originalRetained97Profile ||
        profile == originalRetainedProfile ||
        whole) {
      if (native['dense_producer_profile'] != profile ||
          native['out_ply'] != '' ||
          native['points'] is! int ||
          (native['points'] as int) <= 0 ||
          (native['points'] as int) > count * 1536 * 1152) {
        throw StateError('Original cache must not claim a dense PLY');
      }
      final order = Pw38ObservedOutput(one(fusionRows, 'order'), outputRoot);
      if (!order.relativePath.endsWith('/order.json')) {
        throw StateError('Original retained order path mismatch');
      }
      final directory = order.relativePath.substring(
        0,
        order.relativePath.length - '/order.json'.length,
      );
      if (native['fused_depth_dir'] != '$outputRoot/$directory' ||
          native['order_json'] != order.path) {
        throw StateError('Original cache native paths mismatch');
      }
      final expected = <String, (String, int?)>{
        '$directory/order.json': ('order', null),
        for (var i = 0; i < count; i++) ...{
          '$directory/${i.toString().padLeft(8, '0')}.d16': (
            'retained_d16',
            3538944,
          ),
          '$directory/${i.toString().padLeft(8, '0')}.camera.f64le': (
            'retained_camera',
            200,
          ),
          '$directory/${i.toString().padLeft(8, '0')}.json': (
            'retained_metadata',
            null,
          ),
          '$directory/${i.toString().padLeft(8, '0')}.col.u8': (
            'retained_color',
            5308416,
          ),
        },
      };
      if (fusionRows.length != expected.length) {
        throw StateError('Complete original97 cache output manifest required');
      }
      final files = <Pw38ObservedOutput>[];
      for (final row in fusionRows) {
        final output = Pw38ObservedOutput(row, outputRoot);
        final spec = expected.remove(output.relativePath);
        if (spec == null ||
            spec.$1 != output.role ||
            (spec.$2 != null && spec.$2 != output.bytes)) {
          throw StateError('Original retained cache shape/role/path mismatch');
        }
        files.add(output);
      }
      if (whole) {
        _validateWholeResult(
          receipt,
          object(native),
          stages,
          count,
          workRoot,
          outputRoot,
          directory,
          identityScope,
        );
      }
      return Pw38ProductionOutputContract._(
        glb,
        Pw38OriginalRetainedOutput(
          '$outputRoot/$directory',
          files,
          native['points'] as int,
        ),
        identityScope,
      );
    }
    if (native['dense_producer_profile'] != null &&
        native['dense_producer_profile'] != 'legacy_native_retained_ply') {
      throw StateError('Legacy receipt and actual dense profile disagree');
    }
    final ply = Pw38ObservedOutput(one(fusionRows, 'dense_ply'), outputRoot);
    if (native['out_ply'] != ply.path) {
      throw StateError('Legacy native dense PLY path mismatch');
    }
    return Pw38ProductionOutputContract._(
      glb,
      Pw38DensePlyOutput(ply),
      identityScope,
    );
  }
}

/// Receipt consistency only. The worker's capability and artifact byte checks
/// remain separate authorities; JSON cannot create an execution proof.
void _validateWholeResult(
  Map<String, Object?> receipt,
  Map<String, dynamic> native,
  List stages,
  int count,
  String workRoot,
  String outputRoot,
  String retainedDirectory,
  Pw38ExecutionIdentityScope identityScope,
) {
  final capBytes = wholeMemoryCapBytes(identityScope);
  bool canonical(String path) =>
      path.startsWith('/') &&
      !path.contains('\\') &&
      !path.contains('\u0000') &&
      path
          .substring(1)
          .split('/')
          .every((p) => p.isNotEmpty && p != '.' && p != '..');
  if (!canonical(workRoot) ||
      !canonical(outputRoot) ||
      receipt['schema'] != 'PW38_OFFICIAL_RECONSTRUCTION_RESULT_V1') {
    throw StateError('Whole result requires canonical actual run/output roots');
  }
  final work = native['work_dir'];
  if (work is! String || !canonical(work) || !work.startsWith('$outputRoot/')) {
    throw StateError('Whole dense work path is outside this output run');
  }
  final workRelative = work.substring(outputRoot.length + 1);
  final actual = validateWholeDenseReceipt(
    native,
    count: count,
    outputRoot: outputRoot,
    fusionPaths: {
      'work_dir': workRelative,
      'out_ply': '',
      'fused_depth_dir': retainedDirectory,
    },
    identityScope: identityScope,
  );
  for (var i = 0; i < 4; i++) {
    final row = object(stages[i]);
    final elapsed = row['native_phase_milliseconds'];
    if (row['native_entry'] != wholeDenseNativeEntry ||
        row['grouped_call'] != true ||
        elapsed is! num ||
        !elapsed.isFinite ||
        elapsed < 0 ||
        elapsed != actual.phaseMilliseconds[pw38StageOrder[i]] ||
        (i < 2 &&
            row['output_identity_status'] !=
                'NOT_RETAINED_BY_EXISTING_NATIVE_CALL')) {
      throw StateError(
        'Whole stage journal differs from actual native four-phase receipt',
      );
    }
  }
  final cer = object(stages[2])['outputs'];
  if (cer is! List || cer.length != 4) {
    throw StateError('Four observed whole CER arrays required');
  }
  final roles = <String>{};
  for (final value in cer) {
    final row = Pw38ObservedOutput(object(value), outputRoot);
    if (!{'depth', 'conf0', 'conf1', 'conf2'}.contains(row.role) ||
        !roles.add(row.role) ||
        row.relativePath != '$workRelative/${row.role}.f32' ||
        row.bytes != mergedCerBytes(count)) {
      throw StateError('Whole observed CER path/role/shape mismatch');
    }
  }
  final retained = native['retained_frames'];
  if (retained is! List || retained.length != count) {
    throw StateError('Whole actual retained frame receipt missing');
  }
  double? previous;
  for (var i = 0; i < count; i++) {
    final row = object(retained[i]);
    final bits = row['frame_id_f64_bits'];
    if (bits is! String || !RegExp(r'^[0-9a-f]{16}$').hasMatch(bits)) {
      throw StateError('Whole retained frame identity bits missing');
    }
    final frame =
        (ByteData(8)..setUint64(0, int.parse(bits, radix: 16), Endian.big))
            .getFloat64(0, Endian.big);
    final stem =
        '$outputRoot/$retainedDirectory/${i.toString().padLeft(8, '0')}';
    if (!frame.isFinite ||
        (previous != null && frame <= previous) ||
        row['pack_index'] != i ||
        row['original_index'] != i ||
        row['d16'] != '$stem.d16' ||
        row['camera_f64'] != '$stem.camera.f64le') {
      throw StateError(
        'Whole retained original order/finite identity/path mismatch',
      );
    }
    previous = frame;
  }
  final recipe = receipt['recipe'];
  if (recipe is! Map ||
      recipe['ordered_frames'] != count ||
      recipe['fusion_geo_pixel_threshold'] != 1.0) {
    throw StateError(
      'Whole result must report actual count and selected pixel1 recipe',
    );
  }
  final metadata = receipt['whole_observer_metadata'],
      memory = receipt['whole_app_memory'];
  if (metadata is! Map || memory is! Map) {
    throw StateError('Whole-App actual stopped observer/report missing');
  }
  final process = metadata['m0_pid'], run = metadata['m0_run_id'];
  final peak = memory['physical_peak_bytes'], samples = memory['samples'];
  final trace = '$workRoot/whole_app_m0.jsonl';
  final failures = memory['failures'];
  for (final key in [
    'm0_start_return_code',
    'return_code',
    'm0_initialize_boundary_return_code',
    'm0_finish_boundary_return_code',
    'm0_stop_return_code',
  ]) {
    if (metadata[key] is! int || metadata[key] != 0) {
      throw StateError(
        'Whole-App actual integer native return code missing: $key',
      );
    }
  }
  if (process is! int ||
      process <= 0 ||
      run is! String ||
      !RegExp('^$process-[0-9]+\u0024').hasMatch(run) ||
      memory['m0_run_id'] != run ||
      metadata['m0_trace_path'] != trace ||
      memory['m0_trace_path'] != trace ||
      metadata['m0_start_return_code'] != 0 ||
      metadata['return_code'] != 0 ||
      metadata['m0_initialize_boundary_return_code'] != 0 ||
      metadata['m0_finish_boundary_return_code'] != 0 ||
      metadata['m0_stop_return_code'] != 0 ||
      metadata['m0_interval_ms'] != 100 ||
      metadata['m0_cap_B'] != capBytes ||
      memory['status'] != 'PASS_ACTUAL_WHOLE_APP_OBSERVATIONS' ||
      memory['scope'] != 'ACTUAL_OBSERVER_START_THROUGH_TERMINAL_STOP' ||
      failures is! List ||
      failures.isNotEmpty ||
      peak is! int ||
      peak <= 0 ||
      peak > capBytes ||
      peak < (native['physical_peak_bytes'] as int) ||
      samples is! int ||
      samples < 4 ||
      memory['m0_trace_bytes'] is! int ||
      (memory['m0_trace_bytes'] as int) <= 0 ||
      memory['m0_trace_bytes'] != metadata['m0_trace_bytes'] ||
      memory['m0_trace_sha256'] is! String ||
      !RegExp(r'^[0-9a-f]{64}$')
          .hasMatch(memory['m0_trace_sha256'] as String) ||
      memory['m0_trace_sha256'] != metadata['m0_trace_sha256']) {
    throw StateError(
      'Whole-App current-run stopped M0 identity/physical report mismatch',
    );
  }
}
