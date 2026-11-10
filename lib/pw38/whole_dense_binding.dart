import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'dense_binding_contract.dart';
import 'execution_identity_scope.dart';
import 'memory_policy.dart';
import 'frame_transport.dart';
import 'native_downstream.dart';
import 'request.dart';
import 'whole_dense_live_observer.dart';
import '../dense/pw38_depth_preview.dart';

import 'package:pocketworld_flutter/pw38/vendor/dart_pipeline/lib/pw38_pipeline.dart';
import 'package:pocketworld_flutter/pw38/vendor/dart_texture_integration_v1/lib/pw38_texture_ffi.dart'
    show pw38TextureAbsolutePath;

const wholeDenseProfile = 'whole_mixed_precision_gpu_fusion_pixel1_v1';
const wholeDenseNativeEntry = 'pw38_production_whole_run_v1';
const wholeDenseLastErrorEntry = 'pw38_production_whole_last_error_v1';
typedef _WholeRunN = Int32 Function(Pointer<Char>, Pointer<Char>);
typedef _WholeRunD = int Function(Pointer<Char>, Pointer<Char>);
typedef _LastErrorN = Pointer<Char> Function();
typedef _LastErrorD = Pointer<Char> Function();

/// Checks only the transport receipt. GPU correctness requires real execution.
DenseNativeReceipt validateWholeDenseReceipt(
  Map<String, dynamic> result, {
  required int count,
  required String outputRoot,
  required Map<String, dynamic> fusionPaths,
  Pw38ExecutionIdentityScope identityScope =
      Pw38ExecutionIdentityScope.production,
}) {
  checkedFrameCount(count);
  String output(String key) =>
      '$outputRoot/${checkedRelativePath(string(fusionPaths, key))}';
  final kept = result['kept_total'];
  final peak = result['physical_peak_bytes'];
  for (final key in [
    'status',
    'frames',
    'fused_frames',
    'low_completed',
    'high_completed',
    'inferred',
    'points',
  ]) {
    if (result[key] is! int) {
      throw StateError('Whole integer receipt required: $key');
    }
  }
  if (result['schema'] != 'PW38_PRODUCTION_WHOLE_RESULT_V1' ||
      result['native_entry'] != wholeDenseNativeEntry ||
      result['dense_producer_profile'] != wholeDenseProfile ||
      result['status'] != 0 ||
      result['frames'] != count ||
      result['fused_frames'] != count ||
      result['low_completed'] != count ||
      result['high_completed'] != count ||
      result['inferred'] != 2 * count ||
      kept is! int ||
      kept <= 0 ||
      kept > count * 1536 * 1152 ||
      result['points'] != kept ||
      peak is! int ||
      peak <= 0 ||
      peak > wholeMemoryCapBytes(identityScope) ||
      result['work_dir'] != output('work_dir') ||
      result['out_ply'] !=
          (fusionPaths['out_ply'] == '' ? '' : output('out_ply')) ||
      result['fused_depth_dir'] != output('fused_depth_dir') ||
      result['order_json'] != '${output('fused_depth_dir')}/order.json') {
    throw StateError(
      'Whole dense actual completion/profile/count/paths/physical receipt mismatch',
    );
  }
  final rows = result['stages'];
  if (rows is! List || rows.length != 4) {
    throw StateError('Whole dense requires four actual ordered stage receipts');
  }
  final ms = <Pw38Stage, double>{};
  final stages = pw38StageOrder.take(4).toList();
  for (var i = 0; i < stages.length; i++) {
    final row = object(rows[i]);
    final elapsed = row['elapsed_ms'];
    if (row['stage'] != stages[i].name ||
        row['return_code'] is! int ||
        row['return_code'] != 0 ||
        elapsed is! num ||
        !elapsed.isFinite ||
        elapsed < 0) {
      throw StateError(
        'Whole dense actual stage receipt failed: ${stages[i].name}',
      );
    }
    ms[stages[i]] = elapsed.toDouble();
  }
  return DenseNativeReceipt(0, Map<String, Object?>.from(result), ms);
}

/// Separate source-bound whole runtime. Its synchronous C call runs only inside
/// the existing reconstruction worker. Never reopens, retries or closes a failed
/// owner; the reconstruction journal retains the pending native call.
final class WholeDenseMainline implements Pw38DenseMainline {
  WholeDenseMainline(
    this.slot,
    this.bundleRoot,
    this.headerSha256,
    Map<String, dynamic> wholeProfile,
    this.identityScope,
  ) : wholeProfile = Map<String, dynamic>.unmodifiable(wholeProfile);
  final Pw38ExecutionIdentityScope identityScope;
  final NativeSlot slot;
  final String bundleRoot;
  final Map<String, dynamic> wholeProfile;
  @override
  final String headerSha256;
  @override
  String get binarySha256 => slot.binarySha256;
  @override
  List<String> get actualDefinedSymbols => slot.symbols.toList();

  @override
  Future<DenseNativeReceipt> run(
    Pw38RequestTransport request, {
    void Function(String, int, int)? onProgress,
  }) async {
    if (Isolate.current.debugName == 'main') {
      throw StateError('Whole dense requires existing reconstruction worker');
    }
    if (request.json['dense_producer_profile'] != wholeDenseProfile) {
      throw StateError('Explicit whole producer profile required');
    }
    final count = checkedFrameCount(request.frames.length);
    if (request.json['ordered_frames'] != count) {
      throw StateError('Whole dense actual frame count mismatch');
    }
    final dense = object(request.json['dense_inputs']);
    final root = string(dense, 'input_root');
    pw38TextureAbsolutePath(root);
    pw38TextureAbsolutePath(bundleRoot);
    if (root != request.ioRoots.durableInputRoot) {
      throw StateError('Whole dense immutable input root mismatch');
    }
    final rows = (dense['frames'] as List).map(object).toList();
    if (rows.length != count) {
      throw StateError('Whole actual frame rows absent');
    }
    final artifacts = (dense['artifacts'] as List).map(artifact).toList();
    final byPath = <String, Pw38Artifact>{};
    for (final a in artifacts) {
      final relative = checkedRelativePath(a.path);
      if (byPath.containsKey(relative)) {
        throw StateError('Duplicate whole input artifact');
      }
      byPath[relative] = a;
      final f = File('$root/$relative');
      if (await f.resolveSymbolicLinks() != f.path ||
          await FileSystemEntity.type(f.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await f.length() != a.bytes ||
          await hashFile(f) != a.sha256) {
        throw StateError('Whole immutable input changed: $relative');
      }
    }
    void requireArtifact(String key, int? bytes) {
      final path = checkedRelativePath(string(dense, key));
      final a = byPath[path];
      if (a == null || (bytes != null && a.bytes != bytes)) {
        throw StateError(
          'Whole actual input artifact missing/shape mismatch: $key',
        );
      }
    }

    requireArtifact('cameras_f32', cameraTableBytes(count));
    requireArtifact('neighbors_i32', neighborTableBytes(count));
    requireArtifact('low_noise_f32', lowNoiseBytes(count));
    requireArtifact('high_noise_f32', highNoiseBytes(count));
    requireArtifact('sparse_xyz_f32', null);
    final noise = object(request.json['noise_identity']);
    validateNoisePrefixIdentity(noise, count);
    if (noise['low_sha256'] != byPath[dense['low_noise_f32']]?.sha256 ||
        noise['high_sha256'] != byPath[dense['high_noise_f32']]?.sha256 ||
        noise['ordered_input_manifest_sha256'] !=
            request.json['ordered_input_manifest_sha256']) {
      throw StateError('Whole E0 noise actual artifact identity mismatch');
    }
    for (var i = 0; i < count; i++) {
      final row = rows[i];
      final frame = row['frame_id'];
      if (frame is! num || !frame.isFinite) {
        throw StateError('Actual frame identity absent');
      }
      final bits = ByteData(8)..setFloat64(0, frame.toDouble(), Endian.big);
      if (bits.getUint64(0, Endian.big).toRadixString(16).padLeft(16, '0') !=
              request.frames[i].frameIdF64Bits ||
          !byPath.containsKey(checkedRelativePath(string(row, 'jpeg_path')))) {
        throw StateError('Whole real frame order/JPEG identity mismatch');
      }
    }
    final fusion = object(request.paths['fusionPly']);
    final outputRoot = request.ioRoots.downstreamOutputRoot;
    pw38TextureAbsolutePath(outputRoot);
    final work =
        '$outputRoot/${checkedRelativePath(string(fusion, 'work_dir'))}';
    // Native owns work creation. Transport files live in its existing parent;
    // never delete a previous result or silently rerun a pending owner.
    final requestFile = File('$work.whole-request.json');
    final resultFile = File('$work.whole-result.json');
    for (final f in [requestFile, resultFile]) {
      if (await FileSystemEntity.type(f.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StateError(
          'Whole native pending/result already exists: ${f.path}',
        );
      }
    }
    await requestFile.parent.create(recursive: true);
    await requestFile.writeAsString(
      jsonEncode({
        'schema': 'PW38_PRODUCTION_WHOLE_REQUEST_V1',
        'identity_scope': identityScope.toJson(),
        'dense_producer_profile': wholeDenseProfile,
        'run_id': request.runId,
        'bundle_root': bundleRoot,
        'request': request.json,
        'whole_profile': wholeProfile,
        'io_roots': {
          'durable_input_root': request.ioRoots.durableInputRoot,
          'downstream_output_root': outputRoot,
          'texture_scene_root': request.ioRoots.textureSceneRoot,
        },
      }),
      flush: true,
    );
    final arena = Arena(DownstreamNative(request, bundleRoot).memory);
    final observer = await WholeDenseLiveObserver.start({
      'trace': wholeProfile['m0_trace_path'],
      'm0_run_id': wholeProfile['m0_run_id'],
      'pid': pid,
      'count': count,
      'mvs_root': '$outputRoot/whole_prefix_${request.runId}/mvs',
      'camera_path':
          '$root/${checkedRelativePath(string(dense, 'cameras_f32'))}',
      'visuals': WholeDenseLiveObserver.visuals,
    });
    var nativeValidated = false;
    try {
      final rc = slot.library.lookupFunction<_WholeRunN, _WholeRunD>(
        wholeDenseNativeEntry,
      )(arena.path(requestFile.path), arena.path(resultFile.path));
      if (rc != 0) {
        final error = slot.library.lookupFunction<_LastErrorN, _LastErrorD>(
          wholeDenseLastErrorEntry,
        )();
        final bytes = <int>[];
        if (error != nullptr) {
          for (var i = 0; i < 4096; i++) {
            final value = (error + i).value & 255;
            if (value == 0) break;
            bytes.add(value);
          }
        }
        throw StateError(
          'Whole native pending rc=$rc: ${utf8.decode(bytes, allowMalformed: true)}',
        );
      }
      if (await FileSystemEntity.type(resultFile.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await resultFile.resolveSymbolicLinks() != resultFile.path ||
          await resultFile.length() > 4 * 1024 * 1024) {
        throw StateError(
          'Whole native result not a bounded regular JSON manifest',
        );
      }
      final result = object(jsonDecode(await resultFile.readAsString()));
      final receipt = validateWholeDenseReceipt(
        result,
        count: count,
        outputRoot: outputRoot,
        fusionPaths: fusion,
        identityScope: identityScope,
      );
      await verifyWholeDenseRetention(request, result);
      nativeValidated = true;
      onProgress?.call('whole_fusion', count, count);
      // Retention validation above is the real producer completion gate. Display
      // samples only the final filtered frame; no extra fusion or GPU work.
      if (WholeDenseLiveObserver.visuals &&
          WholeDenseLiveObserver.eventPort != null &&
          WholeDenseLiveObserver.workRoot != null) {
        final dir = result['fused_depth_dir'] as String;
        final stem = (count - 1).toString().padLeft(8, '0');
        final preview = await writeWholeDepthPreview(
          depthPath: '$dir/$stem.d16',
          cameraPath: '$dir/$stem.camera.f64le',
          colorPath: '$dir/$stem.col.u8',
          retained: true,
          frameIndex: count - 1,
          frameCount: count,
          width: 1536,
          height: 1152,
          outputPath:
              '${WholeDenseLiveObserver.workRoot}/display_observations/dense.ply',
        );
        if (preview != null) {
          WholeDenseLiveObserver.eventPort!.send({
            'kind': 'preview',
            'work_root': WholeDenseLiveObserver.workRoot,
            'value': preview.toJson(),
          });
        }
      }
      return receipt;
    } finally {
      try {
        await observer?.stop();
        if (nativeValidated) {
          final mvsRoot = '$outputRoot/whole_prefix_${request.runId}/mvs';
          await WholeDenseLiveObserver.onDepthReadersDrained?.call({
            'schema': 'PW38_DEPTH_READERS_DRAINED_V1',
            'run_id': request.runId,
            'mvs_root': mvsRoot,
            'depth_paths': [
              '$mvsRoot/low/depth.f32',
              '$mvsRoot/high/depth.f32',
            ],
            'observer_started': observer != null,
            'readers_drained': true,
          });
        }
      } finally {
        arena.dispose(); // Temporary C strings only; never the runtime owner.
      }
    }
  }
}

Future<void> verifyWholeDenseRetention(
  Pw38RequestTransport request,
  Map<String, dynamic> result,
) async {
  final dir = result['fused_depth_dir'] as String;
  Future<File> regular(String path, {int? bytes}) async {
    final f = File(path);
    if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file ||
        await f.resolveSymbolicLinks() != path ||
        (bytes != null && await f.length() != bytes)) {
      throw StateError(
        'Whole real retained output missing/shape mismatch: $path',
      );
    }
    return f;
  }

  final order = object(
    jsonDecode(await (await regular('$dir/order.json')).readAsString()),
  );
  final indices = order['order'];
  final retained = result['retained_frames'];
  final count = request.frames.length;
  if (order.length != 2 ||
      order['kept_total'] != result['kept_total'] ||
      indices is! List ||
      indices.length != count ||
      retained is! List ||
      retained.length != count) {
    throw StateError('Whole original order/kept_total manifest mismatch');
  }
  for (var i = 0; i < count; i++) {
    final stem = i.toString().padLeft(8, '0');
    final meta = object(
      jsonDecode(await (await regular('$dir/$stem.json')).readAsString()),
    );
    final row = object(retained[i]);
    if (indices[i] != i ||
        row['pack_index'] != i ||
        row['original_index'] != i ||
        row['frame_id_f64_bits'] != request.frames[i].frameIdF64Bits ||
        row['d16'] != '$dir/$stem.d16' ||
        row['camera_f64'] != '$dir/$stem.camera.f64le' ||
        meta['schema'] != 1 ||
        meta['pack_index'] != i ||
        meta['original_index'] != i ||
        meta['frame_id_f64_bits'] != request.frames[i].frameIdF64Bits ||
        meta['width'] != 1536 ||
        meta['height'] != 1152 ||
        meta['depth_scale'] != 5000 ||
        meta['d16'] != '$stem.d16' ||
        meta['d16_bytes'] != 3538944 ||
        meta['camera'] != '$stem.camera.f64le' ||
        meta['camera_bytes'] != 200 ||
        meta['camera_layout'] != 'K9_then_E16_row_major_f64le') {
      throw StateError('Whole original retained frame metadata mismatch: $i');
    }
    await regular('$dir/$stem.d16', bytes: 3538944);
    await regular('$dir/$stem.camera.f64le', bytes: 200);
    await regular('$dir/$stem.col.u8', bytes: 5308416);
  }
}

Future<Pw38DenseMainline> openWholeDenseMainline(
  Pw38RequestTransport request,
  String bundleRoot, {
  required Map<String, dynamic> wholeProfile,
  Pw38ExecutionIdentityScope identityScope =
      Pw38ExecutionIdentityScope.production,
}) async {
  requireWholeMemoryPolicy(wholeProfile, identityScope);
  if (request.json['dense_producer_profile'] != wholeDenseProfile) {
    throw StateError('Explicit whole producer profile required');
  }
  final row = object(request.native['whole_dense']);
  final header = string(row, 'header_sha256');
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(header)) {
    throw StateError('Whole ABI header hash absent');
  }
  final slot = await NativeSlot.open(row, bundleRoot, {
    wholeDenseNativeEntry,
    wholeDenseLastErrorEntry,
  });
  if (slot.sourceEvidence['header_sha256'] != header) {
    throw StateError('Whole source receipt ABI header mismatch');
  }
  return WholeDenseMainline(
    slot,
    bundleRoot,
    header,
    wholeProfile,
    identityScope,
  );
}
