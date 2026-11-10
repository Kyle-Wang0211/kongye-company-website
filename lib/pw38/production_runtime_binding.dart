import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart' hide Arena;

import 'native_downstream.dart';
import 'execution_identity_scope.dart';
import 'memory_policy.dart';
import 'vendor/dart_pipeline/lib/pw38_geometry_ffi.dart' show Pw38SystemMemory;

const pw38RuntimeBootstrapSourceSha256 =
    'ac871da59245e4b8bfa4c2bcc8d0a9181c6eb70b82a42d6318dc4498a296954e';
const pw38RuntimeBootstrapSymbol = 'pw38_normal_preload_bootstrap';
typedef _BootstrapNative = Int32 Function(Pointer<Char>);
typedef _BootstrapDart = int Function(Pointer<Char>);

// The already selected Bench launch environment. These control existing native
// scheduling/storage paths; no algorithm/model/recipe parameter is changed.
const pw38ProductionRuntimeEnvironment = <String, String>{
  'PWDENSE_ORT_MAX_PENDING': '1',
  'PWDENSE_ORT_STORAGE_CACHE': 'disabled',
  'PWDENSE_PIPE_NO_PREFETCH': '1',
};
typedef _SetEnvN = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _SetEnvD = int Function(Pointer<Utf8>, Pointer<Utf8>, int);
typedef _GetEnvN = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _GetEnvD = Pointer<Utf8> Function(Pointer<Utf8>);
final _setenv = DynamicLibrary.process().lookupFunction<_SetEnvN, _SetEnvD>(
  'setenv',
);
final _getenv = DynamicLibrary.process().lookupFunction<_GetEnvN, _GetEnvD>(
  'getenv',
);

void _requireRuntimeWorker() {
  if (Isolate.current.debugName == 'main') {
    throw StateError('Native runtime initialization requires the worker');
  }
}

/// Read libc's current environment, rather than Dart's startup snapshot. This
/// same check is used immediately after setting and is independently testable.
Map<String, String> verifyProductionRuntimeEnvironment({
  Pw38ExecutionIdentityScope identityScope =
      Pw38ExecutionIdentityScope.production,
}) {
  _requireRuntimeWorker();
  final actual = <String, String>{};
  for (final entry in <String, String>{
    ...pw38ProductionRuntimeEnvironment,
    'PW38_MEMORY_POLICY': wholeMemoryPolicy(identityScope),
  }.entries) {
    final name = entry.key.toNativeUtf8();
    try {
      final pointer = _getenv(name);
      final value = pointer == nullptr ? null : pointer.toDartString();
      if (value != entry.value) {
        throw StateError(
          'Native runtime environment readback differs: ${entry.key}',
        );
      }
      actual[entry.key] = value!;
    } finally {
      malloc.free(name);
    }
  }
  return Map<String, String>.unmodifiable(actual);
}

/// Apply the existing selected context before any provider is opened. libc
/// copies the UTF-8 values, using the same setenv(name,value,1) ABI as the app.
Map<String, String> applyProductionRuntimeEnvironment({
  Pw38ExecutionIdentityScope identityScope =
      Pw38ExecutionIdentityScope.production,
}) {
  _requireRuntimeWorker();
  for (final entry in <String, String>{
    ...pw38ProductionRuntimeEnvironment,
    'PW38_MEMORY_POLICY': wholeMemoryPolicy(identityScope),
  }.entries) {
    final name = entry.key.toNativeUtf8(), value = entry.value.toNativeUtf8();
    try {
      if (_setenv(name, value, 1) != 0) {
        throw StateError(
          'Native runtime environment setenv failed: ${entry.key}',
        );
      }
    } finally {
      malloc.free(name);
      malloc.free(value);
    }
  }
  return verifyProductionRuntimeEnvironment(identityScope: identityScope);
}

/// Exact existing test-shell C loader glue, invoked before any producer opens
/// the downstream runtimes. This performs no algorithm or reconstruction step.
Future<Map<String, Object?>> initializeProductionNativeRuntime(
  Map<String, dynamic> row,
  String bundleRoot, {
  Pw38ExecutionIdentityScope identityScope =
      Pw38ExecutionIdentityScope.production,
}) async {
  _requireRuntimeWorker();
  final environment = applyProductionRuntimeEnvironment(
    identityScope: identityScope,
  );
  final slot = await NativeSlot.open(row, bundleRoot, {
    pw38RuntimeBootstrapSymbol,
  });
  if (slot.sourceEvidence['source_sha256'] !=
      pw38RuntimeBootstrapSourceSha256) {
    throw StateError('Original normal runtime loader source identity changed');
  }
  final arena = Arena(Pw38SystemMemory(DynamicLibrary.process()));
  try {
    final rc = slot.library.lookupFunction<_BootstrapNative, _BootstrapDart>(
      pw38RuntimeBootstrapSymbol,
    )(arena.path(bundleRoot));
    // The unchanged C helper retains its handle for this app process. A later
    // capture's worker sees3 after the same pinned package initialized it.
    if (rc != 0 && rc != 3) {
      throw StateError('Original normal runtime preload returned $rc');
    }
    return {
      'classification': 'NATIVE_LOADER_INITIALIZATION_ONLY',
      'native_entry': pw38RuntimeBootstrapSymbol,
      'return_code': rc,
      'source_sha256': pw38RuntimeBootstrapSourceSha256,
      'binary_sha256': slot.binarySha256,
      'process_environment': environment,
      'process_environment_context': 'EXISTING_SELECTED_BENCH_CONTEXT_RESTORED',
      'full38_complete': false,
    };
  } finally {
    arena.dispose();
  }
}
