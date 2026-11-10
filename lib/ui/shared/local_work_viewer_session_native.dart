import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';

import '../../me/scan_record_store.dart';
import '../scan_record.dart';
import '../final_mesh_thumbnail.dart';

/// Explicit owner/result binding. Remote/community views never create one.
@immutable
class LocalWorkViewerBinding {
  const LocalWorkViewerBinding({
    required this.store,
    required this.localPath,
    required this.generation,
    this.publishedRevision,
  });
  final ScanRecordStore store;
  final String localPath;
  final String generation;
  final ScanResultViewRevision? publishedRevision;
  bool get canRetain => !kIsWeb && store.account != null && store.isActive;

  bool sameSource(LocalWorkViewerBinding? other) =>
      other != null &&
      identical(store, other.store) &&
      localPath == other.localPath &&
      generation == other.generation;

  bool matchesLocalReference(String? reference) {
    String? path(String? value) {
      if (value == null) return null;
      final uri = Uri.tryParse(value);
      if (uri == null || (uri.hasScheme && uri.scheme != 'file')) return null;
      return uri.scheme == 'file' ? uri.toFilePath() : value;
    }

    final expected = path(localPath);
    return expected != null && expected == path(reference);
  }
}

/// The existing detail generation format, shared with capture handoff.
LocalWorkViewerBinding? localWorkViewerBindingFor({
  required ScanRecordStore store,
  required ScanRecord record,
  String? modelUrl,
  String? sparsePath,
}) {
  String? generation;
  if (modelUrl != null) {
    final identity = finalMeshThumbnailIdentity(record, modelUrl: modelUrl);
    generation = 'glb:$modelUrl:${identity?.token}';
  } else if (sparsePath != null) {
    try {
      final stat = File(sparsePath).statSync();
      generation =
          'ply:$sparsePath:${stat.size}:'
          '${stat.modified.microsecondsSinceEpoch}:${stat.changed.microsecondsSinceEpoch}';
    } catch (_) {
      generation = 'ply:$sparsePath';
    }
  }
  final source = modelUrl ?? sparsePath;
  if (source == null || generation == null) return null;
  ScanResultViewRevision? revision;
  if (modelUrl != null && store.isActive) {
    try {
      revision = store.captureResultViewRevision(record);
    } catch (_) {}
  }
  return LocalWorkViewerBinding(
    store: store,
    localPath: source,
    generation: generation,
    publishedRevision: revision,
  );
}

/// Immutable provenance emitted only after the current local load succeeds.
/// The source epoch remains valid across an owner transfer and route disposal;
/// any later load on that controller invalidates it.
class LocalWorkLoadedSource {
  LocalWorkLoadedSource._(
    this.canonicalPath,
    this.fileIdentity,
    this.format,
    this.controller,
    this.retainedSession,
    this._isCurrent,
  );
  final String canonicalPath, fileIdentity;
  final SharedModelFormat format;
  final SharedViewerController controller;
  final SharedViewerRetainedSession retainedSession;
  final bool Function() _isCurrent;
  bool get isCurrent => _isCurrent();
  bool get matchesCurrentFile {
    try {
      return _readLocalFile(canonicalPath)?.signature == fileIdentity;
    } catch (_) {
      return false;
    }
  }
}

/// A pending local load captures identity before dispatch; a changed file cannot
/// acquire provenance merely because its pathname stayed the same.
class LocalWorkPendingSource {
  LocalWorkPendingSource._(
    this._file,
    this.format,
    this.controller,
    this.retainedSession,
    this.isCurrent,
  );
  final _LocalFile _file;
  final SharedModelFormat format;
  final SharedViewerController controller;
  final SharedViewerRetainedSession retainedSession;
  final bool Function() isCurrent;
  static LocalWorkPendingSource? capture({
    required String reference,
    required SharedModelFormat format,
    required SharedViewerController controller,
    required SharedViewerRetainedSession retainedSession,
    required bool Function() isCurrent,
  }) {
    try {
      final file = _readLocalFile(reference);
      if (file == null || !identical(controller, retainedSession.controller)) {
        return null;
      }
      return LocalWorkPendingSource._(
        file,
        format,
        controller,
        retainedSession,
        isCurrent,
      );
    } catch (_) {
      return null;
    }
  }

  LocalWorkLoadedSource? complete() {
    if (!isCurrent()) return null;
    try {
      if (_readLocalFile(_file.path)?.signature != _file.signature) return null;
      return LocalWorkLoadedSource._(
        _file.path,
        _file.signature,
        format,
        controller,
        retainedSession,
        isCurrent,
      );
    } catch (_) {
      return null;
    }
  }
}

class _LocalFile {
  _LocalFile(this.path, this.signature);
  final String path, signature;
}

_LocalFile? _readLocalFile(String reference) {
  final uri = Uri.tryParse(reference);
  if (uri == null || (uri.hasScheme && uri.scheme != 'file')) return null;
  final path = uri.scheme == 'file' ? uri.toFilePath() : reference;
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.file) {
    return null;
  }
  final file = File(path), canonical = File(path).resolveSymbolicLinksSync();
  final stat = file.statSync();
  if (stat.size <= 0) return null;
  return _LocalFile(
    canonical,
    '$canonical:${stat.size}:'
    '${stat.modified.microsecondsSinceEpoch}:${stat.changed.microsecondsSinceEpoch}',
  );
}

/// One bounded real native scene. The package owns its host lifetime; this
/// manager owns the controller and its account-scoped presentation leases.
class LocalWorkViewerSessions with WidgetsBindingObserver {
  LocalWorkViewerSessions() {
    WidgetsBinding.instance.addObserver(this);
  }
  static final instance = LocalWorkViewerSessions();
  _LocalScene? _scene;
  bool _disposed = false;
  Future<void> _queue = Future<void>.value();

  Future<LocalWorkViewerLease?> adoptLoaded({
    required LocalWorkViewerBinding binding,
    required LocalWorkLoadedSource source,
    required bool Function() isCurrent,
  }) {
    final result = _queue.then((_) => _adoptLoaded(binding, source, isCurrent));
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  bool _publishedBindingCurrent(LocalWorkViewerBinding binding) {
    try {
      final expected = binding.publishedRevision;
      if (expected == null || !binding.canRetain) return false;
      final original = expected.record;
      final current = binding.store.byId(original.id);
      if (current == null ||
          current.accountNamespace != binding.store.account?.namespace ||
          current.accountNamespace != original.accountNamespace ||
          current.pipelineKind != original.pipelineKind ||
          current.captureDir != original.captureDir ||
          current.artifactPath != original.artifactPath ||
          current.cloudLibraryRevision != original.cloudLibraryRevision) {
        return false;
      }
      final revision = binding.store.captureResultViewRevision(current);
      if (revision == null ||
          revision.fileSignature != expected.fileSignature ||
          !revision.readyAt.isAtSameMomentAs(expected.readyAt)) {
        return false;
      }
      final artifact = current.artifactPath;
      if (artifact == null ||
          _readLocalFile(artifact)?.path !=
              _readLocalFile(binding.localPath)?.path) {
        return false;
      }
      final regenerated = localWorkViewerBindingFor(
        store: binding.store,
        record: current,
        modelUrl: binding.localPath,
      );
      return regenerated?.generation == binding.generation &&
          finalMeshThumbnailIdentity(current, modelUrl: binding.localPath) !=
              null;
    } catch (_) {
      return false;
    }
  }

  Future<_LocalFile?> _validateLocalBinding(
    LocalWorkViewerBinding binding,
  ) async {
    if (_disposed || !binding.canRetain || binding.generation.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(binding.localPath);
    if (uri == null || (uri.hasScheme && uri.scheme != 'file')) return null;
    final path = uri.scheme == 'file' ? uri.toFilePath() : binding.localPath;
    await binding.store.requireOwnedPath(path);
    if (_disposed || !binding.store.isActive) return null;
    final file = _readLocalFile(path);
    if (file == null) return null;
    await binding.store.requireOwnedPath(file.path);
    if (_disposed || !binding.store.isActive) return null;
    return _readLocalFile(path)?.signature == file.signature ? file : null;
  }

  Future<LocalWorkViewerLease?> _adoptLoaded(
    LocalWorkViewerBinding binding,
    LocalWorkLoadedSource source,
    bool Function() isCurrent,
  ) async {
    bool eligible() =>
        !_disposed &&
        isCurrent() &&
        binding.canRetain &&
        source.isCurrent &&
        source.matchesCurrentFile &&
        source.format == SharedModelFormat.glb &&
        source.controller.isAttached &&
        source.retainedSession.retentionSupported &&
        identical(source.retainedSession.controller, source.controller) &&
        !source.retainedSession.isDisposed &&
        source.retainedSession.error == null &&
        _publishedBindingCurrent(binding);
    if (!eligible()) return null;
    final file = await _validateLocalBinding(binding);
    if (file == null ||
        file.path != source.canonicalPath ||
        file.signature != source.fileIdentity ||
        !eligible()) {
      return null;
    }
    final existing = _scene;
    if (existing != null &&
        (existing.leased || existing.host.hasPresentationLease)) {
      return null;
    }
    final state = await source.controller.getState().timeout(
      const Duration(seconds: 1),
    );
    if (!eligible() ||
        state['status'] != 'ready' ||
        state['format'] != 'glb' ||
        state['disposed'] == true ||
        state['error'] != null) {
      return null;
    }
    if (existing != null) {
      _scene = null;
      await existing.dispose();
      if (!eligible()) return null;
    }
    final scene =
        _LocalScene(
            binding.store,
            '${file.signature}:${binding.generation}',
            file.path,
            source.controller,
            source.retainedSession,
          )
          ..leased = true
          ..loaded = true
          ..source = source;
    _watchScene(scene);
    _scene = scene;
    return LocalWorkViewerLease._(this, scene);
  }

  void _watchScene(_LocalScene scene) {
    scene.removeRevocation = scene.store.addRevocationListener(() {
      if (identical(_scene, scene)) _scene = null;
      _discard(scene);
    });
    void hostChanged() {
      if (!scene.host.isDisposed && scene.host.error == null) return;
      if (identical(_scene, scene)) _scene = null;
      _discard(scene);
    }

    scene.host.addListener(hostChanged);
    scene.removeHostListener = () => scene.host.removeListener(hostChanged);
  }

  Future<LocalWorkViewerLease?> acquire(LocalWorkViewerBinding binding) {
    final result = _queue.then((_) => _acquire(binding));
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<LocalWorkViewerLease?> _acquire(LocalWorkViewerBinding binding) async {
    final file = await _validateLocalBinding(binding);
    if (file == null) return null;
    final canonical = file.path;
    final identity = '${file.signature}:${binding.generation}';
    var scene = _scene;
    if (scene != null && scene.leased) return null;
    if (scene != null &&
        (!identical(scene.store, binding.store) ||
            scene.identity != identity ||
            scene.host.isDisposed ||
            scene.host.error != null ||
            (scene.source != null && !scene.source!.isCurrent))) {
      _scene = null;
      await scene.dispose();
      scene = null;
    }
    if (_disposed || !binding.store.isActive) return null;
    if (scene == null) {
      final controller = SharedViewerController();
      final host = SharedViewerRetainedSession(controller: controller);
      if (!host.retentionSupported) {
        await host.dispose();
        controller.dispose();
        return null;
      }
      scene = _LocalScene(binding.store, identity, canonical, controller, host);
      _watchScene(scene);
      _scene = scene;
    }
    // A native host already mounted elsewhere may not be re-presented.
    if (scene.host.hasPresentationLease) return null;
    scene.leased = true;
    return LocalWorkViewerLease._(this, scene);
  }

  void _release(_LocalScene scene) {
    scene.leased = false;
    if (_disposed ||
        !scene.store.isActive ||
        scene.host.error != null ||
        (scene.source != null && !scene.source!.isCurrent)) {
      if (identical(_scene, scene)) _scene = null;
      _discard(scene);
    }
  }

  void _discard(_LocalScene scene) {
    unawaited(
      scene.dispose().catchError((Object error) {
        debugPrint(
          '[LocalViewer] retained cleanup failed (${error.runtimeType})',
        );
      }),
    );
  }

  @override
  void didHaveMemoryPressure() {
    final idle = _scene;
    if (idle != null && !idle.leased) {
      _scene = null;
      _discard(idle);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    final scene = _scene;
    _scene = null;
    await scene?.dispose();
  }
}

class LocalWorkViewerLease {
  LocalWorkViewerLease._(this._manager, this._scene);
  final LocalWorkViewerSessions _manager;
  final _LocalScene _scene;
  bool _released = false;
  SharedViewerController get controller => _scene.controller;
  SharedViewerRetainedSession get retainedSession => _scene.host;
  String get canonicalPath => _scene.path;
  bool get isValid => !_released && !_scene.disposed && _scene.store.isActive;
  bool get hasLoadedScene => _scene.loaded;

  /// The old route's in-flight load may finish while hidden. Its actual result
  /// is shared, but its old UI callback is never transferred to the new route.
  Future<void> ensureLoaded(Future<void> Function() load) {
    if (!isValid) return Future.error(StateError('Local viewer lease revoked'));
    final pending = _scene.loading;
    if (pending != null) return pending;
    if (_scene.loaded) return Future<void>.value();
    final future = Future<void>.sync(load).then((_) {
      if (!_scene.disposed && _scene.store.isActive) _scene.loaded = true;
    });
    _scene.loading = future;
    return future.whenComplete(() {
      if (identical(_scene.loading, future)) _scene.loading = null;
    });
  }

  /// Live JS health, never a saved thumbnail or a persisted "ready" flag.
  Future<bool> verifyLoadedScene(SharedModelFormat format) async {
    if (!isValid ||
        !_scene.loaded ||
        !controller.isAttached ||
        retainedSession.isDisposed ||
        retainedSession.error != null) {
      return false;
    }
    try {
      final state = await controller.getState().timeout(
        const Duration(seconds: 1),
      );
      final valid =
          isValid &&
          state['status'] == 'ready' &&
          state['disposed'] != true &&
          state['error'] == null &&
          state['format'] == format.name;
      if (!valid) _scene.loaded = false;
      return valid;
    } catch (_) {
      _scene.loaded = false;
      return false;
    }
  }

  void release() {
    if (_released) return;
    _released = true;
    _manager._release(_scene);
  }
}

class _LocalScene {
  _LocalScene(this.store, this.identity, this.path, this.controller, this.host);
  final ScanRecordStore store;
  final String identity, path;
  final SharedViewerController controller;
  final SharedViewerRetainedSession host;
  VoidCallback? removeRevocation, removeHostListener;
  bool leased = false, loaded = false, disposed = false;
  Future<void>? loading;
  LocalWorkLoadedSource? source;
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    removeRevocation?.call();
    removeHostListener?.call();
    try {
      // Native disposal notifies listeners before publishing its cleanup Future.
      // If this callback observed that disposal, let its synchronous stack finish
      // before joining it; do not recursively start a second native cleanup.
      if (host.isDisposed) await Future<void>.value();
      await host.dispose();
    } finally {
      controller.dispose();
    }
  }
}
