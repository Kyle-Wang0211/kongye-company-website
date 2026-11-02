import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';

import '../../l10n/app_localizations.dart';
import 'local_work_viewer_session.dart';

/// Injects the surface only in deterministic widget tests. Product callers use
/// the packaged SharedViewer and its unchanged upstream PLYLoader.
typedef ProductPointViewerBuilder =
    Widget Function(
      SharedViewerController controller,
      VoidCallback onReady,
      ValueChanged<Object> onError,
    );

/// Exact live point snapshots, or the original persisted PLY, rendered by the
/// same packaged renderer as final GLBs. Never crops or budgets input points.
class ProductPointView extends StatefulWidget {
  const ProductPointView({
    super.key,
    required this.xyz,
    required this.rgb,
    this.sourcePath,
    this.finalModelUrl,
    this.waitingForSource = false,
    this.autoRotate = false,
    this.showControls = true,
    this.interactive = true,
    this.maxFps = 60,
    this.background = Colors.black,
    this.controller,
    this.retainedSession,
    this.onLocalSourceLoaded,
    this.viewerBuilder,
    this.onReady,
    this.onFirstFrameReady,
    this.localWork,
    this.localWorkSessions,
    this.onError,
  });

  final LocalWorkViewerBinding? localWork;
  final LocalWorkViewerSessions? localWorkSessions;
  final Float32List xyz;
  final Uint8List rgb;
  final String? sourcePath;

  /// A completed model replaces points atomically on this same renderer/camera.
  final String? finalModelUrl;
  final bool autoRotate, showControls, interactive, waitingForSource;
  final Color background;
  final double maxFps;
  final SharedViewerController? controller;
  final SharedViewerRetainedSession? retainedSession;
  final ValueChanged<LocalWorkLoadedSource>? onLocalSourceLoaded;
  final ProductPointViewerBuilder? viewerBuilder;
  final VoidCallback? onReady, onFirstFrameReady;
  final ValueChanged<Object>? onError;

  @override
  State<ProductPointView> createState() => _ProductPointViewState();
}

class _ProductPointViewState extends State<ProductPointView> {
  late SharedViewerController _controller;
  LocalWorkViewerLease? _localLease;
  bool _controllerReady = false;
  int _preparation = 0;
  bool _preserveRetainedRotation = false;
  VoidCallback? _removeOwnerRevocation;
  bool _ready = false, _loading = false, _loaded = false;
  bool _userTouched = false;
  int _revision = 0, _completedRevision = -1, _loadRun = 0;
  Object? _error;
  Object _sourceEpoch = Object();
  LocalWorkLoadedSource? _lastLocalSource;

  @override
  void initState() {
    super.initState();
    _validateExternalHost();
    _prepareController();
  }

  void _validateExternalHost() {
    final session = widget.retainedSession;
    if (session != null &&
        (widget.controller == null ||
            !identical(session.controller, widget.controller))) {
      throw ArgumentError(
        'Retained host must belong to the supplied controller',
      );
    }
  }

  void _prepareController() {
    final preparation = ++_preparation;
    final binding = widget.localWork;
    // Externally owned capture controllers remain owned by their parent. A
    // later explicit handoff can opt in; never steal/dispose one here.
    if (binding == null ||
        !binding.canRetain ||
        widget.controller != null ||
        !binding.matchesLocalReference(
          widget.finalModelUrl ?? widget.sourcePath,
        )) {
      _installController(null);
      return;
    }
    _removeOwnerRevocation = binding.store.addRevocationListener(() {
      if (mounted) setState(() {});
    });
    unawaited(() async {
      LocalWorkViewerLease? lease;
      try {
        lease =
            await (widget.localWorkSessions ?? LocalWorkViewerSessions.instance)
                .acquire(binding);
      } catch (error) {
        if (mounted &&
            preparation == _preparation &&
            binding.sameSource(widget.localWork)) {
          _onError(error);
        }
        return;
      }
      if (!mounted ||
          preparation != _preparation ||
          !binding.sameSource(widget.localWork)) {
        lease?.release();
        return;
      }
      _installController(lease);
      setState(() {});
    }());
  }

  void _installController(LocalWorkViewerLease? lease) {
    _localLease = lease;
    _controller =
        lease?.controller ?? widget.controller ?? SharedViewerController();
    _controllerReady = true;
    _preserveRetainedRotation = lease?.hasLoadedScene == true;
  }

  void _releaseController() {
    if (!_controllerReady) return;
    if (_localLease != null) {
      _localLease!.release();
    } else if (widget.controller == null) {
      _controller.dispose();
    }
    _localLease = null;
    _controllerReady = false;
  }

  @override
  void didUpdateWidget(covariant ProductPointView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _validateExternalHost();
    assert(
      oldWidget.controller == widget.controller,
      'Replace the ProductPointView key to replace its controller',
    );
    final bindingChanged = oldWidget.localWork == null
        ? widget.localWork != null
        : !oldWidget.localWork!.sameSource(widget.localWork) ||
              (_localLease != null &&
                  !widget.localWork!.matchesLocalReference(
                    widget.finalModelUrl ?? widget.sourcePath,
                  ));
    final reloadBinding =
        bindingChanged &&
        (widget.controller == null ||
            (_lastLocalSource != null &&
                !_lastLocalSource!.matchesCurrentFile));
    if (bindingChanged && widget.controller == null) {
      _loadRun++;
      _loading = false;
      _completedRevision = -1;
      _removeOwnerRevocation?.call();
      _releaseController();
      _ready = false;
      _loaded = false;
      _prepareController();
    }
    if (reloadBinding ||
        oldWidget.finalModelUrl != widget.finalModelUrl ||
        oldWidget.waitingForSource != widget.waitingForSource ||
        (widget.finalModelUrl == null &&
            (!identical(oldWidget.xyz, widget.xyz) ||
                !identical(oldWidget.rgb, widget.rgb) ||
                oldWidget.sourcePath != widget.sourcePath))) {
      _revision++;
      _sourceEpoch = Object();
      unawaited(_loadLatest());
    }
    if (oldWidget.autoRotate != widget.autoRotate ||
        oldWidget.interactive != widget.interactive ||
        oldWidget.background != widget.background ||
        oldWidget.maxFps != widget.maxFps) {
      _preserveRetainedRotation = false;
      if (_ready) _configureCurrent();
    }
  }

  void _configureCurrent() {
    final controller = _controller;
    final lease = _localLease;
    final preparation = _preparation;
    final revision = _revision;
    unawaited(
      _configure(controller).catchError((Object error) {
        if (mounted &&
            _controllerReady &&
            preparation == _preparation &&
            revision == _revision &&
            identical(controller, _controller) &&
            identical(lease, _localLease) &&
            (widget.localWork?.store.isActive ?? true) &&
            (lease?.isValid ?? true)) {
          _onError(error);
        }
      }),
    );
  }

  Future<void> _configure([SharedViewerController? controller]) =>
      (controller ?? _controller).configure(
        interactive: widget.interactive,
        autoRotate: _preserveRetainedRotation
            ? null
            : widget.autoRotate && !_userTouched,
        autoRotateUntilTouched: _preserveRetainedRotation
            ? null
            : widget.autoRotate && !_userTouched,
        autoRotateSpeed: 4,
        background: widget.background.toARGB32() & 0xffffff,
        maxFps: widget.maxFps,
      );

  void _onReady() {
    if (!mounted || _ready) return;
    _ready = true;
    widget.onReady?.call();
    unawaited(_loadLatest());
  }

  void _onError(Object error) {
    if (!mounted) return;
    setState(() => _error = error);
    widget.onError?.call(error);
  }

  Future<void> _loadLatest() async {
    if (!_ready || _loading || !mounted) return;
    _loading = true;
    final run = ++_loadRun;
    final controller = _controller;
    final lease = _localLease;
    bool current() =>
        mounted &&
        run == _loadRun &&
        identical(controller, _controller) &&
        identical(lease, _localLease) &&
        (widget.localWork?.store.isActive ?? true) &&
        (lease?.isValid ?? true);
    var attemptedRevision = _revision;
    try {
      while (current() && _ready && _completedRevision != _revision) {
        final revision = _revision;
        final frameCallback = widget.onFirstFrameReady;
        attemptedRevision = revision;
        final xyz = widget.xyz, rgb = widget.rgb;
        final path = widget.sourcePath;
        final finalModel = widget.finalModelUrl;
        final waiting = widget.waitingForSource;
        final sourceCallback = widget.onLocalSourceLoaded;
        final sourceEpoch = Object();
        _sourceEpoch = sourceEpoch;
        final externalHost = widget.retainedSession;
        final pendingSource =
            externalHost == null || (finalModel ?? path) == null
            ? null
            : LocalWorkPendingSource.capture(
                reference: (finalModel ?? path)!,
                format: finalModel == null
                    ? SharedModelFormat.ply
                    : SharedModelFormat.glb,
                controller: controller,
                retainedSession: externalHost,
                isCurrent: () => identical(_sourceEpoch, sourceEpoch),
              );
        await _configure(controller);
        if (!current() || revision != _revision) return;
        if (waiting && finalModel == null) {
          // Preserve the last real scene while its replacement is unavailable.
          // Do not upload the sparse stand-in as if it were new dense output.
          _completedRevision = revision;
          continue;
        } else if (lease != null) {
          final format = finalModel == null
              ? SharedModelFormat.ply
              : SharedModelFormat.glb;
          final warm =
              lease.hasLoadedScene && await lease.verifyLoadedScene(format);
          if (!current() || revision != _revision) return;
          if (!warm) {
            await lease.ensureLoaded(
              () =>
                  controller.loadLocalFile(lease.canonicalPath, format: format),
            );
          }
        } else if (finalModel != null) {
          final uri = Uri.parse(finalModel);
          if (uri.scheme == 'file' || uri.scheme.isEmpty) {
            await controller.loadLocalFile(
              uri.scheme == 'file' ? uri.toFilePath() : finalModel,
              format: SharedModelFormat.glb,
              preserveCamera: _loaded,
            );
          } else {
            await controller.load(
              url: uri,
              format: SharedModelFormat.glb,
              preserveCamera: _loaded,
            );
          }
        } else if (path != null) {
          await controller.loadLocalFile(
            path,
            format: SharedModelFormat.ply,
            preserveCamera: _loaded,
          );
        } else if (xyz.isNotEmpty) {
          await controller.loadPointCloud(
            xyz: xyz,
            rgb: rgb,
            preserveCamera: _loaded,
          );
        } else {
          // No substitute sparse data is uploaded for a dense-only source.
          _completedRevision = revision;
          continue;
        }
        if (!current()) return;
        _loaded = true;
        _completedRevision = revision;
        // A newer snapshot may have arrived during this load. Do not consume
        // that result's unseen badge until its own model is actually displayed.
        if (revision == _revision) {
          final source = pendingSource?.complete();
          _lastLocalSource = source;
          if (source != null) sourceCallback?.call(source);
          frameCallback?.call();
        }
        if (_error != null) setState(() => _error = null);
      }
    } catch (error) {
      if (current()) {
        _completedRevision = attemptedRevision;
        _onError(error);
      }
    } finally {
      if (run == _loadRun) {
        _loading = false;
        if (current() && _ready && _completedRevision != _revision) {
          unawaited(_loadLatest());
        }
      }
    }
  }

  @override
  void dispose() {
    _preparation++;
    _loadRun++;
    _removeOwnerRevocation?.call();
    _releaseController();
    super.dispose();
  }

  Map<String, String> _viewerUiStrings(BuildContext context) {
    final l = Localizations.of<AppL10n>(context, AppL10n);
    if (l == null) return const {};
    return {
      'locale': l.localeName,
      'title': l.sharedViewerTitle,
      'canvasLabel': l.sharedViewerCanvasLabel,
      'initializing': l.sharedViewerInitializing,
      'loading': l.sharedViewerLoading,
      'failure': l.sharedViewerFailure,
      'skpNotice': l.sharedViewerSkpNotice,
    };
  }

  @override
  Widget build(BuildContext context) =>
      !_controllerReady || !(widget.localWork?.store.isActive ?? true)
      ? ColoredBox(
          color: widget.background,
          child: _error == null
              ? const SizedBox.expand()
              : Center(
                  child: Text(
                    AppL10n.of(context).viewerModelUnavailableDataKept,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
        )
      : Listener(
          onPointerDown: (_) {
            if (_userTouched || !widget.autoRotate) return;
            _userTouched = true;
            if (_ready) _configureCurrent();
          },
          child: ColoredBox(
            color: widget.background,
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.viewerBuilder?.call(_controller, _onReady, _onError) ??
                    SharedViewer(
                      uiStrings: _viewerUiStrings(context),
                      controller: _controller,
                      retainedSession:
                          _localLease?.retainedSession ??
                          widget.retainedSession,
                      onReady: _onReady,
                      onError: _onError,
                    ),
                if (_error != null)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        AppL10n.of(context).viewerModelUnavailableDataKept,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
}
