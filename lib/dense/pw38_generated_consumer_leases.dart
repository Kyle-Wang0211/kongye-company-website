import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Main-isolate readers of generated stage geometry. Registration authorizes
/// leases only: deletion remains owned by GeneratedArtifactRetirement.
final class Pw38GeneratedConsumerLeases {
  static final instance = Pw38GeneratedConsumerLeases();
  final _roots = <String, String>{};
  final _closed = <String>{};
  final _latest = <String, String>{};
  final _retired = <String>{};
  final _pathWaiters = <String, List<Completer<void>>>{};
  final _readers = <String, Map<Object, String>>{};
  final _waiters = <String, List<Completer<void>>>{};
  final _captureReaders = <String, Map<Object, String>>{};

  final _finalCovers = <String, Completer<void>>{};
  final _readyFinalCovers = <String>{};

  String _coverKey(String captureRoot, String artifactIdentity) =>
      jsonEncode([captureRoot, artifactIdentity]);

  /// A successful final-cover notification for one exact GLB identity. The
  /// caller keeps retirement pending without sealing offers while awaiting it;
  /// this must not block the producer's final progress publication.
  Future<void> waitForFinalCover(String captureRoot, String artifactIdentity) {
    final key = _coverKey(captureRoot, artifactIdentity);
    if (_readyFinalCovers.contains(key)) return Future<void>.value();
    return _finalCovers.putIfAbsent(key, () => Completer<void>()).future;
  }

  /// Writer calls only after PNG, JSON, record attach and staging cleanup.
  /// Failure does not notify or seal: the existing display callback can retry.
  void notifyFinalCoverReady(String captureRoot, String artifactIdentity) {
    final key = _coverKey(captureRoot, artifactIdentity);
    _readyFinalCovers.add(key);
    _finalCovers.remove(key)?.complete();
  }

  void offer(String path, {required String workRoot}) {
    if (_retired.contains(path) ||
        _closed.contains(workRoot) ||
        !workRoot.startsWith('/') ||
        workRoot == '/' ||
        !path.startsWith('$workRoot/') ||
        path.split('/').any((s) => s == '.' || s == '..') ||
        Directory(workRoot).resolveSymbolicLinksSync() != workRoot ||
        FileSystemEntity.typeSync(path, followLinks: false) !=
            FileSystemEntityType.file ||
        File(path).resolveSymbolicLinksSync() != path ||
        (_roots[path] != null && _roots[path] != workRoot)) {
      throw StateError('Noncanonical or closed generated consumer offer');
    }
    _roots[path] = workRoot;
    final previous = _latest[workRoot];
    if (!path.endsWith('.glb')) {
      _latest[workRoot] = path;
    } else {
      _latest.remove(workRoot);
    }
    if (previous != null && previous != path) _notifyPath(previous);
  }

  /// Null is intentional for original photos, models and persisted external PLYs.
  Pw38GeneratedReadLease? acquire(String? path, String consumer) {
    final root = _roots[path];
    if (root == null) return null;
    if (_retired.contains(path)) {
      throw StateError('Generated reader already retired: $path');
    }
    if (consumer.isEmpty ||
        _closed.contains(root) ||
        Directory(root).resolveSymbolicLinksSync() != root ||
        FileSystemEntity.typeSync(path!, followLinks: false) !=
            FileSystemEntityType.file ||
        File(path).resolveSymbolicLinksSync() != path) {
      throw StateError('Generated reader after publication closed: $consumer');
    }
    final token = Object();
    (_readers[path] ??= {})[token] = consumer;
    return Pw38GeneratedReadLease._(() {
      _readers[path]?.remove(token);
      _notifyPath(path);
      _notify(root);
    });
  }

  /// Covers can consume an in-memory snapshot or the published GLB outside
  /// the generated work root. Pin their capture writes until attach and staging
  /// cleanup finish, even when there is no generated-path read lease.
  Pw38GeneratedReadLease acquireCapture(String captureRoot, String consumer) {
    if (consumer.isEmpty ||
        _closed.contains(captureRoot) ||
        Directory(captureRoot).resolveSymbolicLinksSync() != captureRoot) {
      throw StateError('Capture consumer after publication closed: $consumer');
    }
    final token = Object();
    (_captureReaders[captureRoot] ??= {})[token] = consumer;
    return Pw38GeneratedReadLease._(() {
      _captureReaders[captureRoot]?.remove(token);
      _notify(captureRoot);
    });
  }

  bool captureOffersClosed(String captureRoot) => _closed.contains(captureRoot);

  Pw38GeneratedReadLease? acquireIdentity(String identity, String consumer) {
    String artifact = identity;
    // Capture uses the existing cover source identity (JSON array whose final
    // entry is the immutable path:SHA); review can supply path:SHA directly.
    try {
      final decoded = jsonDecode(identity);
      if (decoded is List && decoded.isNotEmpty && decoded.last is String) {
        artifact = decoded.last as String;
      }
    } catch (_) {
      /* A plain artifact identity is expected on review pages. */
    }
    if (_roots.containsKey(artifact)) return acquire(artifact, consumer);
    final split = artifact.lastIndexOf(':');
    return acquire(split < 0 ? null : artifact.substring(0, split), consumer);
  }

  /// Completion is the permission to ACK a native last-reader request. Sealing
  /// is atomic with testing no active readers; a later stale UI retry fails.
  Future<void> retireWhenIdle(String path) {
    if (!_roots.containsKey(path)) {
      throw StateError('No generated ownership for retirement ACK: $path');
    }
    if (_retired.contains(path)) return Future<void>.value();
    final done = Completer<void>();
    (_pathWaiters[path] ??= []).add(done);
    _notifyPath(path);
    return done.future;
  }

  void _notifyPath(String path) {
    if (!_pathWaiters.containsKey(path) ||
        _latest[_roots[path]] == path ||
        (_readers[path]?.isNotEmpty ?? false)) {
      return;
    }
    _retired.add(path);
    for (final done in _pathWaiters.remove(path)!) {
      done.complete();
    }
  }

  /// Call after the final progress publication. Already acquired async reads
  /// remain pinned; later UI retries cannot open retired generated geometry.
  void closeOffers(String root) {
    _closed.add(root);
    final latest = _latest.remove(root);
    if (latest != null) _notifyPath(latest);
    _notify(root);
  }

  /// Close only generated roots under one completed capture, including a
  /// pre-manifest retry. No filesystem scan or inference from absent paths.
  Future<void> closeCaptureOffersAndWaitForIdle(String captureRoot) async {
    final roots = _roots.values
        .toSet()
        .where((root) => root.startsWith('$captureRoot/'))
        .toList();
    roots.add(captureRoot);
    for (final root in roots) {
      closeOffers(root);
    }
    await Future.wait(roots.map(waitForIdle));
  }

  Map<String, List<String>> activeConsumers(String root) => {
    for (final entry in _readers.entries)
      if (_roots[entry.key] == root && entry.value.isNotEmpty)
        entry.key: List<String>.unmodifiable(entry.value.values),
  };

  bool _idle(String root) =>
      !(_captureReaders[root]?.isNotEmpty ?? false) &&
      !_readers.entries.any((e) => _roots[e.key] == root && e.value.isNotEmpty);
  Future<void> waitForIdle(String root) {
    if (!_closed.contains(root)) {
      throw StateError('Close generated publication before awaiting readers');
    }
    if (_idle(root)) return Future<void>.value();
    final done = Completer<void>();
    (_waiters[root] ??= []).add(done);
    return done.future;
  }

  void _notify(String root) {
    if (!_closed.contains(root) || !_idle(root)) return;
    for (final done in _waiters.remove(root) ?? <Completer<void>>[]) {
      done.complete();
    }
  }
}

final class Pw38GeneratedReadLease {
  Pw38GeneratedReadLease._(this._release);
  final void Function() _release;
  bool _released = false;
  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}
