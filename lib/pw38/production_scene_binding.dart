import 'frame_transport.dart';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'dense_binding_contract.dart' show VersionN, VersionD;
import 'native_downstream.dart' show Arena, NativeSlot, PairN, PairD;
import 'request.dart' show hashFile;
import 'vendor/dart_pipeline/lib/pw38_geometry_ffi.dart' show Pw38NativeMemory, Pw38SystemMemory;
import 'vendor/dart_pipeline/lib/pw38_pipeline.dart' show checkedRelativePath;

const pw38SceneCameraHeaderSha256 =
    'bfa643e2d5cfb460a4eadbe57348bb12147c756627bbb274de855f605a6e240c';
const pw38SceneCameraSymbols = <String>{
  'pw38_scene_camera_abi_version', 'pw38_scene_cameras_prepare',
  'pw38_scene_cameras_last_error', 'pw38_glb_runtime_initialize',
};
typedef SceneCameraPrepareN = Int32 Function(Pointer<Float>, Uint64,
    Pointer<Char>, Pointer<Char>, Pointer<Char>, Pointer<Char>, Pointer<Char>);
typedef SceneCameraPrepareD = int Function(Pointer<Float>, int,
    Pointer<Char>, Pointer<Char>, Pointer<Char>, Pointer<Char>, Pointer<Char>);
typedef SceneCameraErrorN = Pointer<Char> Function();
typedef SceneCameraErrorD = Pointer<Char> Function();

final class ProductionCameraReceipt {
  const ProductionCameraReceipt(this.file, this.sha256, this.document, this.nativeCall);
  final File file;
  final String sha256;
  final Map<String, dynamic> document;
  final Map<String, Object?> nativeCall;
}

/// Camera-only synchronous bridge. Native borrowed f32 camera bytes pass to the
/// pinned NumPy original producer; Dart performs no camera arithmetic. Caller
/// uses a reconstruction worker and supplies the frozen ordered camera manifest.
final class ProductionCameraBinding {
  ProductionCameraBinding._(this.slot, this.memory);
  final NativeSlot slot;
  final Pw38NativeMemory memory;

  static Future<ProductionCameraBinding> open(Map<String, dynamic> runtimeRow,
      String bundleRoot, {Pw38NativeMemory? memory}) async {
    if (runtimeRow['scene_camera_header_sha256'] != pw38SceneCameraHeaderSha256) {
      throw StateError('Additive original camera header identity mismatch');
    }
    final slot = await NativeSlot.open(runtimeRow, bundleRoot, pw38SceneCameraSymbols);
    if (slot.library.lookupFunction<VersionN, VersionD>('pw38_scene_camera_abi_version')() != 1) {
      throw StateError('Original camera ABI mismatch');
    }
    final ownedMemory = memory ?? Pw38SystemMemory(DynamicLibrary.process());
    final arena = Arena(ownedMemory);
    try {
      final home = checkedRelativePath(runtimeRow['runtime_home_bundle_relative_path'] as String);
      final modules = checkedRelativePath(runtimeRow['native_modules_bundle_relative_path'] as String);
      final rc = slot.library.lookupFunction<PairN, PairD>('pw38_glb_runtime_initialize')(
          arena.path('$bundleRoot/$home'), arena.path('$bundleRoot/$modules'));
      if (rc != 0) throw StateError('Existing pinned CPython runtime initialization failed: $rc');
    } finally {
      arena.dispose();
    }
    return ProductionCameraBinding._(slot, ownedMemory);
  }

  Future<ProductionCameraReceipt> prepare({required Uint8List camerasF32,
      required File manifestFile, required String manifestSha256,
      required Directory inputRoot, required Directory originalCameraDirectory,
      required Directory correctedCameraDirectory, required File receiptFile}) async {
    final manifest = (jsonDecode(await manifestFile.readAsString()) as Map).cast<String, dynamic>();
    final count = checkedFrameCount((manifest['source_jpegs'] as List).length);
    if (Endian.host != Endian.little || camerasF32.length != count * 36 * 4 ||
        await hashFile(manifestFile) != manifestSha256) {
      throw StateError('Actual exact97 native camera bytes and frozen manifest required');
    }
    final arena = Arena(memory);
    try {
      final cameras = arena.bytes(camerasF32.length);
      cameras.asTypedList(camerasF32.length).setAll(0, camerasF32);
      final rc = slot.library.lookupFunction<SceneCameraPrepareN, SceneCameraPrepareD>(
          'pw38_scene_cameras_prepare')(cameras.cast<Float>(), count * 36,
          arena.path(manifestFile.path), arena.path(inputRoot.path),
          arena.path(originalCameraDirectory.path), arena.path(correctedCameraDirectory.path),
          arena.path(receiptFile.path));
      if (rc != 0) {
        final error = slot.library.lookupFunction<SceneCameraErrorN, SceneCameraErrorD>(
            'pw38_scene_cameras_last_error')();
        if (error == nullptr) throw StateError('Original camera producer stopped: $rc');
        final bytes = error.cast<Uint8>().asTypedList(2048);
        final end = bytes.indexOf(0);
        if (end < 0) throw StateError('Original camera error unterminated');
        throw StateError('Original camera producer stopped: $rc ${utf8.decode(bytes.sublist(0, end))}');
      }
      if (await hashFile(manifestFile) != manifestSha256) {
        throw StateError('Camera source manifest changed during native call');
      }
      final receiptHash = await hashFile(receiptFile);
      final document = (jsonDecode(await receiptFile.readAsString()) as Map).cast<String, dynamic>();
      if (await hashFile(receiptFile) != receiptHash ||
          document['schema'] != 'PW38_PRODUCTION_CAMERA_RECEIPT_V1' ||
          document['status'] != 'complete${count}_cameras_only' || document['return_code'] != 0 ||
          document['ordered_frames'] != count || document['input_manifest_sha256'] != manifestSha256 ||
          document['image_producer_status'] != 'REQUIRED_EXTERNAL_ORIGINAL_OPENCV1920') {
        throw StateError('Actual camera-only native receipt required');
      }
      final outputs = (document['material_outputs'] as List)
          .map((r) => (r as Map).cast<String, dynamic>()).toList();
      if (outputs.length != count * 2 || outputs.map((r) => r['path']).toSet().length != count * 2) {
        throw StateError('Exact97 distinct original/corrected CAM pairs required');
      }
      for (final row in [...outputs, document['source_manifest'], document['camera_producer_command']]) {
        final path = checkedRelativePath(row['path'] as String);
        final file = File('${inputRoot.path}/$path');
        if (await file.length() != row['bytes'] || await hashFile(file) != row['sha256']) {
          throw StateError('Actual camera output/evidence bytes changed: $path');
        }
      }
      return ProductionCameraReceipt(receiptFile, receiptHash, document, {
        'native_entry': 'pw38_scene_cameras_prepare', 'return_code': rc,
        'scene_camera_abi_version': 1, 'camera_only': true,
        'header_sha256': pw38SceneCameraHeaderSha256, 'binary_sha256': slot.binarySha256,
        'receipt_sha256': receiptHash, 'input_manifest_sha256': manifestSha256,
        'actual_defined_symbols': slot.symbols.toList()..sort(),
        'image_producer_status': 'REQUIRED_EXTERNAL_ORIGINAL_OPENCV1920',
      });
    } finally {
      arena.dispose();
    }
  }
}
