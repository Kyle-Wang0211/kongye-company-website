import 'dart:convert';
import 'dart:ffi';

import 'pw38_pipeline.dart';

// EXACT native_geometry/geometry_api.h types. No C++ names are bound.
typedef Pw38MeshoptNative = Int32 Function(
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef Pw38MeshoptDart = int Function(
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Char>,
);
typedef Pw38LagrangeNative = Int32 Function(
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
);
typedef Pw38LagrangeDart = int Function(
  Pointer<Char>,
  Pointer<Char>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
);
typedef Pw38GeometryErrorNative = Pointer<Char> Function();
typedef Pw38GeometryErrorDart = Pointer<Char> Function();

const pw38GeometryHeaderSha256 =
    '05b7bf2af15c5dfc785fd0752e0ca525aaddd7937772c689379351eef9c9dbaa';
const pw38GeometryLibrarySha256 =
    '70c780fa8f0810cd9bb3f6c2d03adbb6166e999c095fb4981bfe9f74ddd42e0b';
const pw38GeometrySymbols = <String>{
  'pw38_meshopt_simplify_files',
  'pw38_lagrange_fill_ply',
  'pw38_geometry_last_error',
};

/// Evidence must come from the root's frozen packaging/hash verifier. Merely
/// loading or finding a symbol is not binary/source identity or algorithm proof.
final class Pw38GeometryEvidence {
  const Pw38GeometryEvidence({
    required this.headerSha256,
    required this.binarySha256,
    required this.sourceInputManifestSha256,
    required this.actualDefinedSymbols,
  });
  final String headerSha256;
  final String binarySha256;
  final String sourceInputManifestSha256;
  final Set<String> actualDefinedSymbols;
  void validate() {
    if (headerSha256 != pw38GeometryHeaderSha256 ||
        binarySha256 != pw38GeometryLibrarySha256 ||
        sourceInputManifestSha256 != pw38SourceInputManifestSha256 ||
        !actualDefinedSymbols.containsAll(pw38GeometrySymbols)) {
      throw StateError('Frozen geometry C ABI/source/binary identity rejected');
    }
  }
}

/// The app owns library path/loading system glue. This file contains no OS
/// choice and no platform-dependent algorithm, model, parameter or fallback.
final class Pw38GeometryBindings {
  Pw38GeometryBindings._(this.meshopt, this.lagrange, this.lastError);
  factory Pw38GeometryBindings.bind(
    DynamicLibrary library,
    Pw38GeometryEvidence evidence,
  ) {
    evidence.validate();
    return Pw38GeometryBindings._(
      library.lookupFunction<Pw38MeshoptNative, Pw38MeshoptDart>(
        'pw38_meshopt_simplify_files',
      ),
      library.lookupFunction<Pw38LagrangeNative, Pw38LagrangeDart>(
        'pw38_lagrange_fill_ply',
      ),
      library.lookupFunction<Pw38GeometryErrorNative, Pw38GeometryErrorDart>(
        'pw38_geometry_last_error',
      ),
    );
  }

  /// Explicit test-only callback bridge. It must never populate a production
  /// stage registry or be described as native algorithm execution.
  factory Pw38GeometryBindings.testCallbacks({
    required Pointer<NativeFunction<Pw38MeshoptNative>> meshopt,
    required Pointer<NativeFunction<Pw38LagrangeNative>> lagrange,
    required Pointer<NativeFunction<Pw38GeometryErrorNative>> lastError,
  }) => Pw38GeometryBindings._(
    meshopt.asFunction<Pw38MeshoptDart>(),
    lagrange.asFunction<Pw38LagrangeDart>(),
    lastError.asFunction<Pw38GeometryErrorDart>(),
  );
  final Pw38MeshoptDart meshopt;
  final Pw38LagrangeDart lagrange;
  final Pw38GeometryErrorDart lastError;
}

abstract interface class Pw38NativeMemory {
  Pointer<Uint8> allocate(int bytes);
  void release(Pointer<Uint8> pointer);
}

typedef _MallocNative = Pointer<Void> Function(UintPtr);
typedef _MallocDart = Pointer<Void> Function(int);
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);

/// Standard C runtime allocation is system glue only. The host explicitly
/// chooses the runtime handle; these symbols never implement an algorithm.
final class Pw38SystemMemory implements Pw38NativeMemory {
  Pw38SystemMemory(DynamicLibrary runtime)
    : _malloc = runtime.lookupFunction<_MallocNative, _MallocDart>('malloc'),
      _free = runtime.lookupFunction<_FreeNative, _FreeDart>('free');
  final _MallocDart _malloc;
  final _FreeDart _free;
  @override
  Pointer<Uint8> allocate(int bytes) {
    if (bytes <= 0) throw ArgumentError.value(bytes, 'bytes');
    final pointer = _malloc(bytes).cast<Uint8>();
    if (pointer == nullptr) throw StateError('Native allocation failed');
    return pointer;
  }

  @override
  void release(Pointer<Uint8> pointer) => _free(pointer.cast<Void>());
}

final class _CallArena {
  _CallArena(this.memory);
  final Pw38NativeMemory memory;
  final _owned = <Pointer<Uint8>>[];
  Pointer<Uint8> bytes(int length) {
    final p = memory.allocate(length);
    _owned.add(p);
    p.asTypedList(length).fillRange(0, length, 0);
    return p;
  }

  Pointer<Char> path(String value) {
    if (!value.startsWith('/') ||
        value.length < 2 ||
        value.contains('\x00') ||
        value.contains('\\') ||
        value
            .split('/')
            .skip(1)
            .any((p) => p.isEmpty || p == '.' || p == '..')) {
      throw ArgumentError(
        'Native IO paths must be canonical absolute nonempty paths',
      );
    }
    final encoded = utf8.encode(value);
    final p = bytes(encoded.length + 1);
    p.asTypedList(encoded.length).setAll(0, encoded);
    return p.cast<Char>();
  }

  void dispose() {
    for (final p in _owned.reversed) {
      memory.release(p);
    }
    _owned.clear();
  }
}

String pw38BorrowedUtf8(Pointer<Char> pointer, {int maxBytes = 4096}) {
  if (pointer == nullptr) return '';
  if (maxBytes <= 0) throw ArgumentError.value(maxBytes, 'maxBytes');
  final bytes = <int>[];
  final view = pointer.cast<Uint8>();
  for (var i = 0; i < maxBytes; i++) {
    final value = (view + i).value;
    if (value == 0) return utf8.decode(bytes);
    bytes.add(value);
  }
  throw StateError('Native error exceeds the registered diagnostic bound');
}

final class Pw38GeometryCallResult {
  const Pw38GeometryCallResult(
    this.entryReturnCode,
    this.error, {
    this.inputVertices,
    this.inputFacets,
    this.outputVertices,
    this.outputFacets,
  });
  final int entryReturnCode;
  final String error;
  final int? inputVertices;
  final int? inputFacets;
  final int? outputVertices;
  final int? outputFacets;
}

/// Synchronous methods belong on one worker isolate; no concurrent stage calls.
/// Native text is copied before the next call overwrites thread_local storage.
final class Pw38GeometryFfi {
  Pw38GeometryFfi(this.bindings, this.memory);
  final Pw38GeometryBindings bindings;
  final Pw38NativeMemory memory;

  Pw38GeometryCallResult simplifyFiles({
    required String inputPositionsF32,
    required String inputIndicesU32,
    required String outputPositionsF32,
    required String outputIndicesU32,
  }) {
    final arena = _CallArena(memory);
    try {
      final rc = bindings.meshopt(
        arena.path(inputPositionsF32),
        arena.path(inputIndicesU32),
        arena.path(outputPositionsF32),
        arena.path(outputIndicesU32),
      );
      return Pw38GeometryCallResult(rc, pw38BorrowedUtf8(bindings.lastError()));
    } finally {
      arena.dispose();
    }
  }

  Pw38GeometryCallResult fillPly({
    required String inputPly,
    required String outputPly,
  }) {
    final arena = _CallArena(memory);
    try {
      final input = arena.path(inputPly), output = arena.path(outputPly);
      final counts = arena.bytes(4 * sizeOf<Uint64>()).cast<Uint64>();
      final rc = bindings.lagrange(
        input,
        output,
        counts,
        counts + 1,
        counts + 2,
        counts + 3,
      );
      final error = pw38BorrowedUtf8(bindings.lastError());
      // A failed stage may leave partial native outputs. Do not present its
      // partially written counters as successful mesh statistics.
      return Pw38GeometryCallResult(
        rc,
        error,
        inputVertices: rc == 0 ? counts.value : null,
        inputFacets: rc == 0 ? (counts + 1).value : null,
        outputVertices: rc == 0 ? (counts + 2).value : null,
        outputFacets: rc == 0 ? (counts + 3).value : null,
      );
    } finally {
      arena.dispose();
    }
  }
}
