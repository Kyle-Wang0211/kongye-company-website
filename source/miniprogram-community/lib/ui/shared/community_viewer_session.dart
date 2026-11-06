import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';

/// Retains only the most recent community scene. The caller supplies the full
/// account/endpoint/work/model identity; this never borrows local-work bindings.
class CommunityViewerSessions with WidgetsBindingObserver {
  CommunityViewerSessions() {
    WidgetsBinding.instance.addObserver(this);
  }

  static final instance = CommunityViewerSessions();
  _CommunityScene? _scene;
  Future<void> _queue = Future<void>.value();
  bool _disposed = false;
  int _epoch = 0;

  /// Lets an awaiting presentation distinguish revocation from unsupported or
  /// busy retention. Revocation must never authorize an unretained fallback.
  int get generation => _epoch;

  Future<CommunityViewerLease?> acquire(String identity) {
    final epoch = _epoch;
    final result = _queue.then((_) => _acquire(identity, epoch));
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<CommunityViewerLease?> _acquire(String identity, int epoch) async {
    bool current() => !_disposed && epoch == _epoch;
    if (!current() || identity.isEmpty) return null;
    var scene = _scene;
    // Manager and native presentation leases must both be idle before reuse or
    // replacement. Never tear down another route to satisfy an acquisition.
    if (scene != null && (scene.leased || scene.host.hasPresentationLease)) {
      return null;
    }
    if (scene != null &&
        (scene.identity != identity ||
            scene.disposed ||
            scene.host.isDisposed ||
            scene.host.error != null)) {
      _scene = null;
      await scene.dispose();
      scene = null;
    }
    if (!current()) return null;
    if (scene == null) {
      final controller = SharedViewerController();
      final host = SharedViewerRetainedSession(controller: controller);
      if (!host.retentionSupported) {
        await host.dispose();
        controller.dispose();
        return null;
      }
      scene = _CommunityScene(identity, controller, host);
      final watched = scene;
      void hostChanged() {
        if (!watched.host.isDisposed && watched.host.error == null) return;
        _invalidate(watched);
      }

      host.addListener(hostChanged);
      scene.removeHostListener = () => host.removeListener(hostChanged);
      _scene = scene;
    }
    scene.leased = true;
    return CommunityViewerLease._(this, scene);
  }

  void _release(_CommunityScene scene) {
    scene.leased = false;
    // SharedViewer's presentation release owns pause and native detach ordering.
    // Releasing this manager lease never destroys a healthy hidden document.
    if (_disposed || scene.host.isDisposed || scene.host.error != null) {
      _invalidate(scene);
    }
  }

  void _invalidate(_CommunityScene scene) {
    if (identical(_scene, scene)) _scene = null;
    unawaited(
      scene.dispose().catchError((Object error) {
        debugPrint(
          '[CommunityViewer] retained cleanup failed (${error.runtimeType})',
        );
      }),
    );
  }

  @override
  void didHaveMemoryPressure() {
    final idle = _scene;
    if (idle != null && !idle.leased && !idle.host.hasPresentationLease) {
      _invalidate(idle);
    }
  }

  /// Sign-out/source invalidation revokes current leases immediately. A load
  /// already dispatched may finish, but cannot republish or resurrect its scene.
  Future<void> clear() {
    _epoch++;
    final scene = _scene;
    _scene = null;
    final previous = _queue;
    final cleanup = scene?.dispose() ?? Future<void>.value();
    final result = Future.wait<void>([previous, cleanup]).then<void>((_) {});
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> dispose() {
    if (!_disposed) {
      _disposed = true;
      WidgetsBinding.instance.removeObserver(this);
      return clear();
    }
    return _queue;
  }
}

class CommunityViewerLease {
  CommunityViewerLease._(this._manager, this._scene);
  final CommunityViewerSessions _manager;
  final _CommunityScene _scene;
  bool _released = false;

  SharedViewerController get controller => _scene.controller;
  SharedViewerRetainedSession get retainedSession => _scene.host;
  bool get isValid => !_released && !_scene.disposed;
  bool get hasLoadedScene => !_scene.disposed && _scene.loaded;
  String? get modelContentSha256 =>
      isValid && _scene.loaded ? _scene.modelContentSha256 : null;

  Future<void> ensureLoaded(
    Future<void> Function() load, {
    Future<String?> Function()? verifiedModelSha256,
  }) {
    if (!isValid) {
      return Future.error(StateError('Community viewer lease revoked'));
    }
    final pending = _scene.loading;
    if (pending != null) return pending;
    if (_scene.loaded) return Future<void>.value();
    late final Future<void> future;
    future = Future<void>.sync(load)
        .then((_) async {
          // Completion belongs to the scene, so a new lease can share an old route's
          // in-flight load. The old route's released flag does not revoke that load.
          if (_scene.disposed) {
            throw StateError('Community viewer scene revoked');
          }
          if (!await _scene.isAlive(SharedModelFormat.glb)) {
            _manager._invalidate(_scene);
            throw StateError('Community viewer scene is not ready');
          }
          // Identity is the load owner's before/after byte verification, not a
          // later route's current disk contents. Retain it on that same scene.
          final identity = await verifiedModelSha256?.call();
          if (_scene.disposed) {
            throw StateError('Community viewer scene revoked');
          }
          _scene.modelContentSha256 =
              identity != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(identity)
              ? identity
              : null;
          _scene.loaded = true;
        })
        .whenComplete(() {
          if (identical(_scene.loading, future)) _scene.loading = null;
        });
    _scene.loading = future;
    return future;
  }

  /// Ask the live renderer; a cached Dart flag does not prove scene survival.
  Future<bool> verifyLoadedScene(SharedModelFormat format) async {
    if (!isValid || !_scene.loaded) return false;
    final valid = await _scene.isAlive(format);
    if (!valid) _manager._invalidate(_scene);
    return isValid && valid;
  }

  void release() {
    if (_released) return;
    _released = true;
    _manager._release(_scene);
  }
}

class _CommunityScene {
  _CommunityScene(this.identity, this.controller, this.host);
  final String identity;
  final SharedViewerController controller;
  final SharedViewerRetainedSession host;
  VoidCallback? removeHostListener;
  bool leased = false, loaded = false, disposed = false;
  Future<void>? loading, _disposing;
  String? modelContentSha256;

  Future<bool> isAlive(SharedModelFormat format) async {
    if (disposed ||
        !controller.isAttached ||
        host.isDisposed ||
        host.error != null) {
      return false;
    }
    try {
      final state = await controller.getState().timeout(
        const Duration(seconds: 1),
      );
      return !disposed &&
          !host.isDisposed &&
          host.error == null &&
          controller.isAttached &&
          state['status'] == 'ready' &&
          state['format'] == format.name &&
          state['disposed'] != true &&
          state['error'] == null;
    } catch (_) {
      return false;
    }
  }

  Future<void> dispose() {
    if (_disposing != null) return _disposing!;
    disposed = true;
    loaded = false;
    modelContentSha256 = null;
    removeHostListener?.call();
    return _disposing = _disposeResources();
  }

  Future<void> _disposeResources() async {
    try {
      // Host disposal notifies synchronously before publishing its cleanup
      // future. Yield when observing that notification to avoid recursive IO.
      if (host.isDisposed) await Future<void>.value();
      await host.dispose();
    } finally {
      controller.dispose();
    }
  }
}
