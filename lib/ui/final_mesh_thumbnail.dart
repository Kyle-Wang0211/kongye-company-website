import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';
import 'package:flutter/scheduler.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../me/scan_record_store.dart';
import 'shared/product_model_view.dart';
import 'shared/product_point_view.dart';
import 'shared/product_preview_cover.dart';
import 'package:image/image.dart' as img;

import 'scan_record.dart';

/// Identity of the actual local GLB generation, independent of cloud/title/seen
/// metadata. This is a presentation cache; original38 proof remains separate.
final class FinalMeshThumbnailIdentity {
  const FinalMeshThumbnailIdentity._(this.value, this.token, this.directory);
  final String value, token, directory;
}

FinalMeshThumbnailIdentity? finalMeshThumbnailIdentity(
  ScanRecord record, {
  String? modelUrl,
}) {
  try {
    final reference = modelUrl ?? record.artifactPath;
    if (reference == null || reference.isEmpty) return null;
    final uri = Uri.parse(reference);
    if (uri.scheme.isNotEmpty && uri.scheme != 'file') return null;
    final path = uri.scheme == 'file' ? uri.toFilePath() : reference;
    final file = File(path);
    if (!path.toLowerCase().endsWith('.glb') ||
        FileSystemEntity.typeSync(path, followLinks: false) !=
            FileSystemEntityType.file) {
      return null;
    }
    final canonical = file.resolveSymbolicLinksSync();
    final stat = file.statSync();
    if (stat.size < 20) return null;
    final input = file.openSync();
    late final Uint8List header;
    try {
      header = input.readSync(12);
    } finally {
      input.closeSync();
    }
    if (header.length != 12) return null;
    final bytes = ByteData.sublistView(header);
    if (bytes.getUint32(0, Endian.little) != 0x46546c67 ||
        bytes.getUint32(4, Endian.little) != 2 ||
        bytes.getUint32(8, Endian.little) != stat.size) {
      return null;
    }
    final capture = record.captureDir;
    final canonicalCapture = capture != null && Directory(capture).existsSync()
        ? Directory(capture).resolveSymbolicLinksSync()
        : capture;
    final value = jsonEncode([
      'pw.final-mesh-cover.v2',
      record.accountNamespace,
      record.id,
      record.pipelineKind.wireName,
      canonicalCapture,
      canonical,
      stat.size,
      stat.modified.microsecondsSinceEpoch,
      stat.changed.microsecondsSinceEpoch,
      stat.mode,
    ]);
    return FinalMeshThumbnailIdentity._(
      value,
      sha256.convert(utf8.encode(value)).toString(),
      '${File(canonical).parent.path}/.pw_final_mesh_thumbs',
    );
  } catch (_) {
    return null;
  }
}

/// Only an image captured from this same owner and GLB generation can replace a
/// sparse cover. A record's generic photo/old sparse thumbnail is never enough.
bool isFinalMeshThumbnailPath(String path) =>
    File(path).parent.path.split('/').last == '.pw_final_mesh_thumbs';

File? finalMeshThumbnailFor(ScanRecord record, {String? modelUrl}) {
  try {
    final identity = finalMeshThumbnailIdentity(record, modelUrl: modelUrl);
    final path = record.thumbnailPath;
    if (identity == null || path == null) return null;
    final file = File(path);
    if (!file.uri.pathSegments.last.startsWith('${identity.token}-') ||
        FileSystemEntity.typeSync(path, followLinks: false) !=
            FileSystemEntityType.file ||
        File(file.resolveSymbolicLinksSync()).parent.path !=
            identity.directory) {
      return null;
    }
    final binding = File('$path.json');
    if (FileSystemEntity.typeSync(binding.path, followLinks: false) !=
            FileSystemEntityType.file ||
        File(binding.resolveSymbolicLinksSync()).parent.path !=
            identity.directory) {
      return null;
    }
    final json = jsonDecode(binding.readAsStringSync());
    if (json is! Map || json['identity'] != identity.value) return null;
    final bytes = file.readAsBytesSync();
    final hash = sha256.convert(bytes).toString();
    if (bytes.isEmpty ||
        json['image_sha256'] != hash ||
        file.uri.pathSegments.last != '${identity.token}-$hash.jpg') {
      return null;
    }
    return file;
  } catch (_) {
    return null;
  }
}

bool _validImage(Uint8List bytes) {
  try {
    return img.decodeImage(bytes) != null;
  } catch (_) {
    return false;
  }
}

/// Called after the SAME shared renderer reports its actual first model frame.
/// [attach] must atomically merge only thumbnailPath into the current store
/// record, rejecting a replaced/deleted result or revoked account. It must not
/// use addOrUpdate with the pre-capture record snapshot.
Future<String?> ensureFinalMeshThumbnail({
  required ScanRecord record,
  required String modelUrl,
  required Future<Uint8List?> Function() capture,
  required bool Function() isCurrent,
  required Future<bool> Function(String path) attach,
}) async {
  final identity = finalMeshThumbnailIdentity(record, modelUrl: modelUrl);
  if (identity == null || !isCurrent()) return null;
  final existing = finalMeshThumbnailFor(record, modelUrl: modelUrl);
  if (existing != null) return existing.path;
  final bytes = await capture();
  if (bytes == null ||
      bytes.isEmpty ||
      !isCurrent() ||
      finalMeshThumbnailIdentity(record, modelUrl: modelUrl)?.token !=
          identity.token ||
      !_validImage(bytes)) {
    return null;
  }
  final imageHash = sha256.convert(bytes).toString();
  final directory = Directory(identity.directory);
  // Reject an unexpected symlink before creating presentation cache files.
  if (FileSystemEntity.typeSync(directory.path, followLinks: false) ==
      FileSystemEntityType.link) {
    return null;
  }
  await directory.create(recursive: true);
  if (!isCurrent() ||
      directory.resolveSymbolicLinksSync() != directory.absolute.path) {
    return null;
  }
  final staged = await directory.createTemp('.pending-');
  try {
    if (!isCurrent()) return null;
    final image = File('${staged.path}/image.jpg');
    final metadata = File('${staged.path}/image.json');
    await image.writeAsBytes(bytes, flush: true);
    await metadata.writeAsString(
      jsonEncode({'identity': identity.value, 'image_sha256': imageHash}),
      flush: true,
    );
    if (!isCurrent() ||
        finalMeshThumbnailIdentity(record, modelUrl: modelUrl)?.token !=
            identity.token) {
      return null;
    }
    final path = '${directory.path}/${identity.token}-$imageHash.jpg';
    await image.rename(path);
    await metadata.rename('$path.json');
    if (!isCurrent() || !await attach(path)) return null;
    return path;
  } finally {
    if (staged.existsSync()) await staged.delete(recursive: true);
  }
}

/// Displays the already saved work immediately; the image is only a cover,
/// never interactive readiness. Real errors and first frames both remove it.
class LocalWorkOpeningPreview extends StatefulWidget {
  const LocalWorkOpeningPreview({
    super.key,
    required this.thumbnail,
    required this.builder,
  });
  final File thumbnail;
  final Widget Function(VoidCallback onFirstFrame, ValueChanged<Object> onError)
  builder;

  @override
  State<LocalWorkOpeningPreview> createState() =>
      _LocalWorkOpeningPreviewState();
}

class _LocalWorkOpeningPreviewState extends State<LocalWorkOpeningPreview> {
  bool _finished = false;
  void _finish() {
    if (!mounted || _finished) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    } else {
      setState(() => _finished = true);
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.builder(_finish, (_) => _finish()),
      if (!_finished)
        IgnorePointer(
          child: ColoredBox(
            color: Colors.black,
            child: Image.file(
              widget.thumbnail,
              key: const ValueKey('local-work-opening-preview'),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox(),
            ),
          ),
        ),
    ],
  );
}

/// One-shot gallery cover backfill. Only a visible owned final model can enter
/// the single bake slot. It uses the existing shared renderer, then unmounts it
/// permanently for this generation once its saved image has been attached.
class FinalMeshThumbnail extends StatefulWidget {
  const FinalMeshThumbnail({
    super.key,
    required this.record,
    required this.fallback,
    this.storeForTesting,
    this.hostBuilderForTesting,
    this.legacySparseSourcePath,
    this.pointViewerBuilderForTesting,
  });
  final ScanRecord record;
  final Widget fallback;
  final ScanRecordStore? storeForTesting;
  final String? legacySparseSourcePath;
  final ProductPointViewerBuilder? pointViewerBuilderForTesting;
  // Forward the existing renderer test seam; production always leaves it null.
  // ignore: invalid_use_of_visible_for_testing_member
  final ProductModelHostBuilder? hostBuilderForTesting;

  @override
  State<FinalMeshThumbnail> createState() => _FinalMeshThumbnailState();
}

class _FinalMeshThumbnailState extends State<FinalMeshThumbnail>
    with WidgetsBindingObserver {
  static final _waiting = <_FinalMeshThumbnailState>[];
  static _FinalMeshThumbnailState? _active;
  late final ScanRecordStore _store =
      widget.storeForTesting ?? ScanRecordStore.instance;
  late final ProductPreviewCoverSource? _legacySource =
      widget.legacySparseSourcePath == null
      ? null
      : legacySparseCoverSource(widget.record, widget.legacySparseSourcePath!);
  final _legacyWriter = ProductPreviewCoverWriter();
  String? _identityFor(ScanRecord record) =>
      widget.legacySparseSourcePath == null
      ? finalMeshThumbnailIdentity(record)?.token
      : legacySparseCoverSource(record, widget.legacySparseSourcePath!)?.token;
  File? _savedFor(ScanRecord record) => widget.legacySparseSourcePath == null
      ? finalMeshThumbnailFor(record)
      : productPreviewCoverFor(record);
  late final String? _identity = _identityFor(widget.record);
  ScanResultViewRevision? _revision;
  VoidCallback? _removeRevocation;
  String? _savedPath;
  bool _visible = false, _queued = false, _running = false;
  bool _finished = false, _capturing = false, _foreground = true;
  bool _tickerEnabled = true, _routeCurrent = true;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _removeRevocation = _store.addRevocationListener(() => _stop());
  }

  bool get _eligible {
    if (!mounted || !_store.isActive) return false;
    if (_finished ||
        !_visible ||
        !_foreground ||
        !_tickerEnabled ||
        !_routeCurrent ||
        !_store.isActive ||
        _identity == null) {
      return false;
    }
    final current = _store.byId(widget.record.id);
    return current != null &&
        current.accountNamespace == widget.record.accountNamespace &&
        _identityFor(current) == _identity;
  }

  void _release({bool afterFrame = false}) {
    _waiting.remove(this);
    _queued = false;
    void release() {
      if (_active != this) return;
      _active = null;
      _grantNext();
    }

    if (afterFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) => release());
    } else {
      release();
    }
  }

  static void _grantNext() {
    while (_active == null && _waiting.isNotEmpty) {
      final next = _waiting.removeAt(0);
      next._queued = false;
      if (!next._eligible) continue;
      final current = next._store.byId(next.widget.record.id)!;
      final saved = next._savedFor(current);
      if (saved != null) {
        next._savedPath = saved.path;
        next._finished = true;
        next._rebuild();
        continue;
      }
      _active = next;
      try {
        if (next._legacySource != null) {
          unawaited(next._prepareLegacy());
          return;
        }
        next._revision = next._store.captureResultViewRevision(current);
        if (next._revision == null) {
          next._stop();
          return;
        }
        next._attempt++;
        next._capturing = false;
        next._running = true;
        next._rebuild();
      } catch (error) {
        debugPrint('[FinalMeshThumbnail] bake unavailable: $error');
        next._stop();
      }
    }
  }

  Future<void> _prepareLegacy() async {
    try {
      await _store.requireOwnedPath(widget.legacySparseSourcePath!);
      if (!mounted || _active != this || !_eligible) {
        _stop();
        return;
      }
      _legacyWriter.select(_legacySource!);
      _attempt++;
      _capturing = false;
      _running = true;
      _rebuild();
    } catch (_) {
      if (mounted) _stop();
    }
  }

  void _legacyReady(SharedViewerController controller, String? identity) {
    final source = _legacySource;
    final current = _store.byId(widget.record.id);
    if (source == null ||
        identity != source.identity ||
        !_eligible ||
        !_running ||
        current == null) {
      if (mounted) _stop();
      return;
    }
    if (_capturing) return;
    _capturing = true;
    final attempt = _attempt;
    bool valid() => mounted && _eligible && _running && attempt == _attempt;
    unawaited(
      _legacyWriter
          .capture(
            source: source,
            controller: controller,
            isCurrent: valid,
            attach: (path) => _store.attachPreviewThumbnail(
              expected: current,
              thumbnailPath: path,
              isCurrent: valid,
            ),
          )
          .then((path) {
            if (!mounted || attempt != _attempt) return;
            _savedPath = path;
            _stop();
          }),
    );
  }

  void _rebuild() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _stop() {
    _finished = true;
    _attempt++;
    _running = false;
    _release(afterFrame: true);
    _rebuild();
  }

  void _queue() {
    if (!_eligible || _queued || _running) return;
    final current = _store.byId(widget.record.id)!;
    final saved = _savedFor(current);
    if (saved != null) {
      _savedPath = saved.path;
      _finished = true;
      _rebuild();
      return;
    }
    _queued = true;
    _waiting.add(this);
    _grantNext();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _routeCurrent = ModalRoute.isCurrentOf(context) ?? true;
    if ((!_tickerEnabled || !_routeCurrent) && _running) {
      _attempt++;
      _running = false;
      _release(afterFrame: true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _queue();
    });
  }

  void _visibilityChanged(VisibilityInfo info) {
    if (!mounted) return;
    _visible = info.visibleFraction > 0;
    if (_visible) {
      _queue();
    } else if (_running) {
      _attempt++;
      _running = false;
      _release(afterFrame: true);
      _rebuild();
    }
  }

  void _viewerReady(ProductViewerCapture viewer) {
    if (!_store.isActive) return;
    final current = _store.byId(widget.record.id);
    final revision = _revision;
    if (_capturing ||
        !_eligible ||
        !_running ||
        current == null ||
        revision == null) {
      return;
    }
    _capturing = true;
    final attempt = _attempt;
    unawaited(
      ensureFinalMeshThumbnail(
            record: current,
            modelUrl: current.artifactPath!,
            capture: () => viewer.captureThumb(),
            isCurrent: () => _eligible && _running && attempt == _attempt,
            attach: (path) => _store.attachFinalMeshThumbnail(
              revision: revision,
              thumbnailPath: path,
            ),
          )
          .then((path) {
            if (!mounted || attempt != _attempt) return;
            _savedPath = path;
            _stop();
          })
          .catchError((Object error) {
            debugPrint('[FinalMeshThumbnail] cover unavailable: $error');
            if (mounted && attempt == _attempt) _stop();
          }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _queue();
    } else if (_running) {
      _attempt++;
      _running = false;
      _release(afterFrame: true);
      _rebuild();
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = _savedPath == null
        ? widget.record
        : widget.record.copyWith(thumbnailPath: _savedPath);
    final saved = _savedFor(record);
    return VisibilityDetector(
      key: ValueKey(
        'final-mesh-cover-${widget.record.accountNamespace}-${widget.record.id}-$_identity',
      ),
      onVisibilityChanged: _visibilityChanged,
      child: saved != null
          ? Image.file(
              saved,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => widget.fallback,
            )
          : _running
          ? (_legacySource != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ProductPointView(
                        xyz: Float32List(0),
                        rgb: Uint8List(0),
                        sourcePath: widget.legacySparseSourcePath,
                        sourceIdentity: _legacySource.identity,
                        interactive: false,
                        autoRotate: false,
                        onSourceFrameReady: _legacyReady,
                        viewerBuilder: widget.pointViewerBuilderForTesting,
                        onError: (_) => _stop(),
                      ),
                      IgnorePointer(child: widget.fallback),
                    ],
                  )
                : ProductModelView(
                    modelUrl: record.artifactPath!,
                    autoRotate: false,
                    onViewerReady: _viewerReady,
                    onError: (_) => _stop(),
                    // ignore: invalid_use_of_visible_for_testing_member
                    hostBuilder: widget.hostBuilderForTesting,
                  ))
          : widget.fallback,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _removeRevocation?.call();
    _release();
    super.dispose();
  }
}

/// Lazily migrates an old CPU-painted cover through the SAME single gallery
/// bake slot as final models. The old image remains until replacement verifies.
class LegacySparseThumbnail extends StatelessWidget {
  const LegacySparseThumbnail({
    super.key,
    required this.record,
    required this.plyPath,
    required this.fallback,
    this.storeForTesting,
    this.viewerBuilderForTesting,
  });
  final ScanRecord record;
  final String plyPath;
  final Widget fallback;
  final ScanRecordStore? storeForTesting;
  final ProductPointViewerBuilder? viewerBuilderForTesting;
  @override
  Widget build(BuildContext context) {
    final source = legacySparseCoverSource(record, plyPath);
    if (source == null) return fallback;
    return FinalMeshThumbnail(
      key: ValueKey('legacy-sparse-cover-${source.token}'),
      record: record,
      fallback: fallback,
      legacySparseSourcePath: plyPath,
      storeForTesting: storeForTesting,
      pointViewerBuilderForTesting: viewerBuilderForTesting,
    );
  }
}
