import 'frame_transport.dart';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'dense_binding_contract.dart' show VersionN, VersionD;
import 'native_downstream.dart' show Arena, NativeSlot;
import 'request.dart' show hashFile;
import 'vendor/dart_pipeline/lib/pw38_geometry_ffi.dart' show Pw38NativeMemory, Pw38SystemMemory;
import 'vendor/dart_pipeline/lib/pw38_pipeline.dart' show checkedRelativePath;

const pw38SceneImageHeaderSha256 =
    '646cd08078255e7007da0bde347accc63f327d24421bf99e064399b7c8d87dc2';
const pw38Original1920CommandSha256 =
    'c0fc95f636fc5d70e16e9c71ef6588ab0f3d73c92ac865619bdb58b2b066128e';
const pw38OfficialOpenCv411Arm64Sha256 =
    '5a142d12dfe767b216cfca4a8d09a95ec7e020ee621c837208671e1027300bc4';
const pw38SceneImageSymbols = <String>{
  'pw38_scene_image_abi_version', 'pw38_scene_images_prepare',
  'pw38_scene_images_last_error', 'pw38_scene_images_opencv_version',
  'pw38_scene_images_build_information',
};
typedef SceneImagesPrepareN = Int32 Function(Pointer<Pointer<Char>>,
    Pointer<Pointer<Char>>, Uint64, Pointer<Char>, Pointer<Char>, Pointer<Char>, Pointer<Uint64>);
typedef SceneImagesPrepareD = int Function(Pointer<Pointer<Char>>,
    Pointer<Pointer<Char>>, int, Pointer<Char>, Pointer<Char>, Pointer<Char>, Pointer<Uint64>);
typedef SceneImageTextN = Pointer<Char> Function();
typedef SceneImageTextD = Pointer<Char> Function();

String _nativeText(Pointer<Char> pointer, int limit) {
  if (pointer == nullptr) throw StateError('Missing native image producer text');
  final bytes = <int>[];
  for (var i = 0; i < limit; i++) {
    final b = (pointer.cast<Uint8>() + i).value;
    if (b == 0) return utf8.decode(bytes);
    bytes.add(b);
  }
  throw StateError('Native image producer text exceeded bound');
}

Pointer<Char> _text(Arena arena, String value) {
  if (value.contains('\u0000')) throw StateError('Embedded NUL in native argument');
  final bytes = utf8.encode(value);
  final out = arena.bytes(bytes.length + 1);
  out.asTypedList(bytes.length).setAll(0, bytes);
  return out.cast<Char>();
}

String _relative(Directory root, String path) {
  if (!path.startsWith('${root.path}/')) throw StateError('Image artifact outside immutable IO root');
  return checkedRelativePath(path.substring(root.path.length + 1));
}

bool _sha(Object? value) => value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

final class ProductionImageReceipt {
  const ProductionImageReceipt(this.file, this.sha256, this.document, this.nativeCall);
  final File file;
  final String sha256;
  final Map<String, dynamic> document;
  final Map<String, Object?> nativeCall;
}

/// Open and invoke inside the reconstruction worker isolate. Native also rejects
/// the main thread. This bridge returns image-only evidence; CAM and combined
/// material completion remain separately measured by the coordinating caller.
final class ProductionImageBinding {
  ProductionImageBinding._(this.slot, this.memory, this.buildInformation);
  final NativeSlot slot;
  final Pw38NativeMemory memory;
  final String buildInformation;

  static Future<ProductionImageBinding> open(Map<String, dynamic> runtimeRow,
      String bundleRoot, {Pw38NativeMemory? memory}) async {
    if (Isolate.current.debugName == 'main') throw StateError('Original image producer requires reconstruction worker');
    final relative = checkedRelativePath(runtimeRow['scene_image_header_bundle_relative_path'] as String);
    if (runtimeRow['scene_image_header_sha256'] != pw38SceneImageHeaderSha256 ||
        await hashFile(File('$bundleRoot/$relative')) != pw38SceneImageHeaderSha256) {
      throw StateError('Exact original image C ABI header bytes required');
    }
    final slot = await NativeSlot.open(runtimeRow, bundleRoot, pw38SceneImageSymbols);
    final evidence = slot.sourceEvidence;
    final exported = (evidence['actual_exported_c_symbols'] as List).cast<String>().toSet();
    if (evidence['scene_image_header_sha256'] != pw38SceneImageHeaderSha256 ||
        evidence['opencv_arm64_archive_sha256'] != pw38OfficialOpenCv411Arm64Sha256 ||
        evidence['opencv_411_symbols_isolated'] != true ||
        exported.length != pw38SceneImageSymbols.length ||
        !exported.containsAll(pw38SceneImageSymbols) ||
        (evidence['unexpected_exported_symbols'] as List).isNotEmpty) {
      throw StateError('Actual image-only exports and isolated official OpenCV4.11 receipt required');
    }
    if (slot.library.lookupFunction<VersionN, VersionD>('pw38_scene_image_abi_version')() != 1 ||
        _nativeText(slot.library.lookupFunction<SceneImageTextN, SceneImageTextD>(
            'pw38_scene_images_opencv_version')(), 64) != '4.11.0') {
      throw StateError('Actual original image ABI/OpenCV runtime mismatch');
    }
    final build = _nativeText(slot.library.lookupFunction<SceneImageTextN, SceneImageTextD>(
        'pw38_scene_images_build_information')(), 65536);
    if (!build.contains('General configuration for OpenCV 4.11.0') ||
        !build.contains('3.0.3-70')) throw StateError('Pinned official image runtime build information mismatch');
    return ProductionImageBinding._(slot, memory ?? Pw38SystemMemory(DynamicLibrary.process()), build);
  }

  Future<ProductionImageReceipt> prepare({required File manifestFile,
      required String manifestSha256, required Directory inputRoot,
      required Directory outputDirectory}) async {
    if (Isolate.current.debugName == 'main' || !_sha(manifestSha256) ||
        await hashFile(manifestFile) != manifestSha256) {
      throw StateError('Worker and actual frozen image source manifest required');
    }
    final manifestRelative = _relative(inputRoot, manifestFile.path);
    final outputRelative = _relative(inputRoot, outputDirectory.path);
    if (await FileSystemEntity.type(outputDirectory.path, followLinks: false) != FileSystemEntityType.notFound) {
      throw StateError('Exclusive fresh image directory required; existing partials retained');
    }
    final source = (jsonDecode(await manifestFile.readAsString()) as Map).cast<String, dynamic>();
    if (!{'PW38_PRODUCTION_CAMERA_SOURCE_V1', 'PW38_PRODUCTION_SOURCE_MANIFEST_V1'}.contains(source['schema']) ||
        !_sha(source['dense_frames_sha256'])) throw StateError('Actual production ordered source manifest required');
    final rows = (source['source_jpegs'] as List).map((r) => (r as Map).cast<String, dynamic>()).toList();
    final count = checkedFrameCount(rows.length);
    if (rows.length != count || rows.map((r) => r['path']).toSet().length != count) {
      throw StateError('Exact97 distinct JPEG sources in frozen manifest order required');
    }
    final paths = <String>[];
    for (final row in rows) {
      final path = checkedRelativePath(row['path'] as String), file = File('${inputRoot.path}/$path');
      if (row['role'] != 'source_jpeg' || !_sha(row['sha256']) ||
          await FileSystemEntity.type(file.path, followLinks: false) != FileSystemEntityType.file ||
          await file.length() != row['bytes'] || await hashFile(file) != row['sha256']) {
        throw StateError('Actual ordered JPEG identity changed: $path');
      }
      paths.add(file.path);
    }
    final arena = Arena(memory);
    try {
      final pathArray = arena.bytes(count * sizeOf<Pointer<Char>>()).cast<Pointer<Char>>();
      final hashArray = arena.bytes(count * sizeOf<Pointer<Char>>()).cast<Pointer<Char>>();
      for (var i = 0; i < count; i++) {
        (pathArray + i).value = arena.path(paths[i]);
        (hashArray + i).value = _text(arena, rows[i]['sha256'] as String);
      }
      final completed = arena.bytes(sizeOf<Uint64>()).cast<Uint64>();
      final rc = slot.library.lookupFunction<SceneImagesPrepareN, SceneImagesPrepareD>(
          'pw38_scene_images_prepare')(pathArray, hashArray, count, arena.path(manifestFile.path),
          _text(arena, manifestSha256), arena.path(outputDirectory.path), completed);
      final call = <String, Object?>{
        'native_entry': 'pw38_scene_images_prepare', 'return_code': rc,
        'completed_images': completed.value, 'scene_image_abi_version': 1,
        'image_only': true, 'header_sha256': pw38SceneImageHeaderSha256,
        'binary_sha256': slot.binarySha256, 'opencv_version': '4.11.0',
        'opencv_arm64_archive_sha256': pw38OfficialOpenCv411Arm64Sha256,
        'original_recorded_command_sha256': pw38Original1920CommandSha256,
        'input_manifest_sha256': manifestSha256,
        'actual_defined_symbols': slot.symbols.toList()..sort(),
        'recipe': {'imread_flags': 129, 'width': 1920, 'height': 1440,
          'interpolation': 3, 'jpeg_quality': 95},
        'original_a100_jpeg_cpu_build': 'UNPROVEN', 'a100_byte_parity': 'UNPROVEN',
      };
      if (rc != 0 || completed.value != count) {
        final error = _nativeText(slot.library.lookupFunction<SceneImageTextN, SceneImageTextD>(
            'pw38_scene_images_last_error')(), 2048);
        if (await FileSystemEntity.type(outputDirectory.path, followLinks: false) == FileSystemEntityType.directory) {
          final failure = File('${outputDirectory.path}/image_failure.json');
          if (!await failure.exists()) {
            await failure.writeAsString('${jsonEncode({'schema': 'PW38_PRODUCTION_IMAGE_FAILURE_V1',
              'status': 'failed_images_only', ...call, 'native_error': error})}\n', flush: true);
          }
        }
        throw StateError('Original image producer stopped; partials retained: ${jsonEncode(call)} $error');
      }
      if (await hashFile(manifestFile) != manifestSha256) throw StateError('Source manifest changed during image call');
      final outputs = <Map<String, Object?>>[];
      for (var i = 0; i < count; i++) {
        if (await hashFile(File(paths[i])) != rows[i]['sha256']) throw StateError('Source JPEG changed during image call');
        final name = '${i.toString().padLeft(8, '0')}.jpg';
        final file = File('${outputDirectory.path}/$name');
        if (await FileSystemEntity.type(file.path, followLinks: false) != FileSystemEntityType.file ||
            await file.length() <= 0) throw StateError('Actual numbered JPEG output missing: $name');
        outputs.add({'path': '$outputRelative/$name', 'role': 'texture_image',
          'bytes': await file.length(), 'sha256': await hashFile(file)});
      }
      final commandFile = File('${outputDirectory.path}/image_command.json');
      await commandFile.writeAsString('${jsonEncode({'schema': 'PW38_ACTUAL_IMAGE_COMMAND_V1',
        ...call, 'opencv_build_information': buildInformation})}\n', flush: true);
      final document = <String, dynamic>{
        'schema': 'PW38_PRODUCTION_IMAGE_RECEIPT_V1', 'status': 'complete${count}_images_only',
        'return_code': rc, 'ordered_frames': count, 'completed_images': completed.value,
        'dense_frames_sha256': source['dense_frames_sha256'],
        'input_manifest_sha256': manifestSha256, 'material_outputs': outputs,
        'source_manifest': {'path': manifestRelative, 'role': 'source_manifest',
          'bytes': await manifestFile.length(), 'sha256': manifestSha256},
        'image_producer_command': {'path': '$outputRelative/image_command.json',
          'role': 'image_producer_command', 'bytes': await commandFile.length(),
          'sha256': await hashFile(commandFile)},
        'native_call': call, 'camera_producer_status': 'REQUIRED_SEPARATE_ORIGINAL_CAMERA_RECEIPT',
      };
      final receipt = File('${outputDirectory.path}/image_receipt.json');
      await receipt.writeAsString('${jsonEncode(document)}\n', flush: true);
      final receiptHash = await hashFile(receipt);
      for (final row in outputs) {
        if (await hashFile(File('${inputRoot.path}/${row['path']}')) != row['sha256']) {
          throw StateError('Image output changed before receipt return');
        }
      }
      return ProductionImageReceipt(receipt, receiptHash, document, call);
    } finally { arena.dispose(); }
  }
}
