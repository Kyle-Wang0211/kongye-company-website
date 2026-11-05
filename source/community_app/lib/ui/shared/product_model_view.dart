import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pw_shared_viewer/pw_shared_viewer.dart';

import 'local_work_viewer_session.dart';
import 'community_viewer_session.dart';
import 'model_content_identity.dart';
import 'browser_model_transport.dart';

import '../../community/shared_viewer_model_path.dart';
import '../../util/device_log.dart';
import '../../l10n/app_localizations.dart';

/// Product operations exposed without a platform renderer implementation.
class ProductViewerCapture {
  ProductViewerCapture._(
    this._capture, {
    required Future<void> Function(bool) surfaceMode,
    required Future<void> Function(List<SharedSurfaceMarker>) surfaceMarkers,
    required Future<void> Function(SharedSurfaceAnchor) surfaceFocus,
    required Future<String?> Function() modelIdentity,
  }) : _surfaceMode = surfaceMode,
       _surfaceMarkers = surfaceMarkers,
       _surfaceFocus = surfaceFocus,
       _modelIdentity = modelIdentity;
  final Future<Uint8List?> Function(double quality) _capture;
  final Future<void> Function(bool) _surfaceMode;
  final Future<void> Function(List<SharedSurfaceMarker>) _surfaceMarkers;
  final Future<void> Function(SharedSurfaceAnchor) _surfaceFocus;
  final Future<String?> Function() _modelIdentity;

  Future<Uint8List?> captureThumb({double quality = 0.85}) => _capture(quality);
  Future<void> setSurfaceCommentMode(bool enabled) => _surfaceMode(enabled);
  Future<void> setSurfaceCommentMarkers(List<SharedSurfaceMarker> markers) =>
      _surfaceMarkers(markers);
  Future<void> focusSurfaceComment(SharedSurfaceAnchor anchor) =>
      _surfaceFocus(anchor);
  Future<String?> modelContentSha256() => _modelIdentity();
}

@visibleForTesting
typedef ProductModelHostBuilder =
    Widget Function(
      BuildContext context,
      SharedViewerController controller,
      VoidCallback onReady,
      ValueChanged<Object> onError,
    );

/// Product presentation of the single shared renderer.
///
/// Interactive surfaces display its WebView directly. Feed surfaces present
/// lossless, full-canvas PNG frames from that SAME mounted renderer in Flutter's
/// framebuffer, where the existing glass shader can sample them. No model,
/// texture or normal-map reduction is performed here.
class ProductModelView extends StatefulWidget {
  const ProductModelView({
    super.key,
    required this.modelUrl,
    this.initialView,
    this.interactive = false,
    this.concealRenderSource = false,
    this.autoRotate = false,
    this.autoRotateUntilTouched = false,
    this.background = Colors.black,
    this.active = true,
    this.pointerEventsEnabled = true,
    @visibleForTesting this.webActivityUpdatesForTesting,
    this.pointerEventsEnabledNotifier,
    this.autoRotateSpeed = 0.6,
    this.onFirstFrameReady,
    this.onStillFrame,
    this.localWork,
    this.localWorkSessions,
    this.communitySessionKey,
    this.communitySessions,
    this.onError,
    this.onViewerReady,
    this.onIdealAspectRatio,
    this.onSurfacePicked,
    this.onSurfaceMarkerSelected,
    this.onSurfaceMarkerLayoutChanged,
    @visibleForTesting this.hostBuilder,
    @visibleForTesting this.resolveLocalPath,
    @visibleForTesting this.browserModelClient,
  });

  final LocalWorkViewerBinding? localWork;
  final LocalWorkViewerSessions? localWorkSessions;

  /// Explicit community detail opt-in; feed cards never retain/load models.
  final String? communitySessionKey;
  final CommunityViewerSessions? communitySessions;
  final String modelUrl;
  final Map<String, dynamic>? initialView;
  final bool interactive;

  /// Keep the mounted source out of paint while presenting decoded captures.
  /// Intended for static community feed cards; rotation uses the default path.
  final bool concealRenderSource;
  final bool autoRotate;
  final bool autoRotateUntilTouched;
  final Color background;
  final bool active;
  final bool pointerEventsEnabled;
  @visibleForTesting
  final bool? webActivityUpdatesForTesting;
  final ValueNotifier<bool>? pointerEventsEnabledNotifier;
  final double autoRotateSpeed;
  final VoidCallback? onFirstFrameReady;

  /// A decoded, lossless static frame that remains usable after host disposal.
  final ValueChanged<Uint8List>? onStillFrame;
  final ValueChanged<Object>? onError;
  final ValueChanged<ProductViewerCapture>? onViewerReady;
  final ValueChanged<double>? onIdealAspectRatio;
  final ValueChanged<SharedSurfaceAnchor>? onSurfacePicked;
  final ValueChanged<String>? onSurfaceMarkerSelected;
  final ValueChanged<SharedSurfaceMarkerLayout?>? onSurfaceMarkerLayoutChanged;
  final ProductModelHostBuilder? hostBuilder;
  final Future<String> Function(String url)? resolveLocalPath;
  @visibleForTesting
  final http.Client? browserModelClient;

  @override
  State<ProductModelView> createState() => _ProductModelViewState();
}

class _ProductModelViewState extends State<ProductModelView>
    with WidgetsBindingObserver {
  static const _captureInterval = Duration(milliseconds: 42); // <= 24 fps.
  late SharedViewerController _controller;
  LocalWorkViewerLease? _localLease;
  CommunityViewerLease? _communityLease;
  int? _communityGeneration;
  bool _controllerReady = false;
  int _preparation = 0;
  bool _communityRecoveryUsed = false;
  VoidCallback? _removeOwnerRevocation;
  late final ProductViewerCapture _capture = ProductViewerCapture._(
    _captureThumb,
    surfaceMode: (enabled) => _controller.setSurfaceCommentMode(enabled),
    surfaceMarkers: (markers) => _controller.setSurfaceCommentMarkers(markers),
    surfaceFocus: (anchor) => _controller.focusSurfaceComment(anchor),
    modelIdentity: () async =>
        !_disposed &&
            _loaded &&
            _active &&
            (_communityLease == null || _communityLease!.isValid)
        ? _modelContentHash
        : null,
  );
  int _lastDownloadProgressRevision = 0;
  int _lastSurfacePickRevision = 0;
  int _lastSurfaceMarkerSelectionRevision = 0;
  int _lastSurfaceMarkerLayoutRevision = 0;
  String? _modelContentHash;
  bool _hostReady = false;
  bool _tickerEnabled = true;
  bool _routeCurrent = true;
  bool _foreground = true;
  bool _disposed = false;
  bool _capturing = false;
  bool _rotationArmed = false;
  bool _userTookControl = false;
  int _rotationConfigurationEpoch = -1;
  bool? _lastAutoRotate;
  bool? _lastUntilTouched;
  int _epoch = 0;
  Stopwatch _loadClock = Stopwatch()..start();
  int _loadedEpoch = -1;
  int _initialViewAttemptedEpoch = -1;
  int _notifiedEpoch = -1;
  int _frameEpoch = -1;
  int _layoutRevision = 0;
  int _frameLayoutRevision = -1;
  Size? _captureSize;
  double? _capturePixelRatio;
  int? _loadingEpoch;
  VoidCallback? _firstFrameCallbackForLoad;
  ValueChanged<Uint8List>? _stillFrameCallbackForLoad;
  ValueChanged<ProductViewerCapture>? _viewerReadyCallbackForLoad;
  ValueChanged<double>? _aspectCallbackForLoad;
  int _notifiedAspectEpoch = -1;
  MemoryImage? _frame;
  Future<void> _captureQueue = Future<void>.value();
  Object? _error;
  double? _downloadProgress = 0;
  Timer? _captureTimer;

  bool get _active =>
      widget.active &&
      _tickerEnabled &&
      _foreground &&
      (_communityGeneration == null ||
          _communityGeneration ==
              (widget.communitySessions ?? CommunityViewerSessions.instance)
                  .generation) &&
      (widget.localWork?.store.isActive ?? true);
  bool get _loaded => _loadedEpoch == _epoch;
  bool get _showsCapturedFrame =>
      !widget.interactive || widget.concealRenderSource;
  bool get _hasCaptureLayout =>
      !widget.concealRenderSource || _captureSize != null;
  bool get _hasCurrentFrame =>
      _frame != null &&
      _frameEpoch == _epoch &&
      (!widget.concealRenderSource || _frameLayoutRevision == _layoutRevision);

  void _observeCaptureLayout(BoxConstraints constraints, double pixelRatio) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final valid =
        width.isFinite &&
        height.isFinite &&
        width > 0 &&
        height > 0 &&
        pixelRatio.isFinite &&
        pixelRatio > 0;
    final size = valid ? Size(width, height) : null;
    final ratio = valid ? pixelRatio : null;
    if (size == _captureSize && ratio == _capturePixelRatio) return;
    _captureSize = size;
    _capturePixelRatio = ratio;
    _layoutRevision++;
    // Layout can change in response to model metadata, including after a static
    // renderer has paused. Capture renders synchronously; no animation tick is
    // required. A pending frame must be rejected before it can pause or publish.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && mounted) _scheduleCapture(immediate: true);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _prepareController();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null ||
        state == AppLifecycleState.resumed ||
        (kIsWeb && state == AppLifecycleState.inactive);
  }

  void _prepareController() {
    final preparation = ++_preparation;
    final binding = widget.localWork;
    if (binding == null && widget.communitySessionKey != null) {
      final sessions =
          widget.communitySessions ?? CommunityViewerSessions.instance;
      final generation = sessions.generation;
      unawaited(() async {
        try {
          final lease = await sessions.acquire(
            jsonEncode([widget.communitySessionKey, widget.modelUrl]),
          );
          if (_disposed ||
              !mounted ||
              preparation != _preparation ||
              generation != sessions.generation) {
            lease?.release();
            return;
          }
          _installController(null, community: lease);
          _communityGeneration = generation;
          setState(() {});
        } catch (error) {
          if (!_disposed && mounted && preparation == _preparation) {
            _fail(error);
          }
        }
      }());
      return;
    }
    if (binding == null ||
        !binding.canRetain ||
        !binding.matchesLocalReference(widget.modelUrl)) {
      _installController(null);
      return;
    }
    _removeOwnerRevocation = binding.store.addRevocationListener(() {
      if (!_disposed && mounted) setState(() {});
    });
    unawaited(() async {
      LocalWorkViewerLease? lease;
      try {
        lease =
            await (widget.localWorkSessions ?? LocalWorkViewerSessions.instance)
                .acquire(binding);
      } catch (error) {
        // Owner rejection must not retry through an unretained host.
        if (!_disposed &&
            mounted &&
            preparation == _preparation &&
            binding.sameSource(widget.localWork)) {
          _fail(error);
        }
        return;
      }
      if (_disposed ||
          !mounted ||
          preparation != _preparation ||
          !binding.sameSource(widget.localWork)) {
        lease?.release();
        return;
      }
      _installController(lease);
      setState(() {});
    }());
  }

  void _installController(
    LocalWorkViewerLease? lease, {
    CommunityViewerLease? community,
  }) {
    _localLease = lease;
    _communityLease = community;
    _controller =
        lease?.controller ?? community?.controller ?? SharedViewerController();
    _controllerReady = true;
    _lastSurfacePickRevision = _controller.surfacePickRevision;
    _lastSurfaceMarkerSelectionRevision =
        _controller.surfaceMarkerSelectionRevision;
    _lastSurfaceMarkerLayoutRevision = _controller.surfaceMarkerLayoutRevision;
    _controller.addListener(_observeRotation);
    if (lease?.hasLoadedScene == true || community?.hasLoadedScene == true) {
      // Keep the real retained camera/rotation state; metadata or re-entry must
      // not rearm OrbitControls after a user's earlier touch.
      _rotationConfigurationEpoch = _epoch;
      _lastAutoRotate = widget.autoRotate;
      _lastUntilTouched = widget.autoRotateUntilTouched;
    }
  }

  void _releaseController() {
    if (!_controllerReady) return;
    _controller.removeListener(_observeRotation);
    final lease = _localLease;
    if (lease == null && _communityLease == null) {
      _controller.dispose();
    } else {
      lease?.release();
      _communityLease?.release();
    }
    _localLease = null;
    _communityLease = null;
    _communityGeneration = null;
    _controllerReady = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (current != _routeCurrent) {
      _routeCurrent = current;
      // A non-opaque sheet can leave TickerMode enabled. Retry the SAME
      // dispatched result's first-frame notification once this route returns.
      if (current && _loaded) _notifyReady(_epoch);
    }
    final enabled = TickerMode.valuesOf(context).enabled;
    if (enabled != _tickerEnabled) {
      _tickerEnabled = enabled;
      _updateActivity();
    }
  }

  @override
  void didUpdateWidget(covariant ProductModelView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bindingChanged = oldWidget.localWork == null
        ? widget.localWork != null
        : !oldWidget.localWork!.sameSource(widget.localWork);
    final communityChanged =
        oldWidget.communitySessionKey != widget.communitySessionKey ||
        !identical(oldWidget.communitySessions, widget.communitySessions);
    if (bindingChanged ||
        communityChanged ||
        oldWidget.modelUrl != widget.modelUrl) {
      _communityRecoveryUsed = false;
      if (bindingChanged ||
          communityChanged ||
          _localLease != null ||
          _communityLease != null ||
          oldWidget.communitySessionKey != null ||
          widget.communitySessionKey != null) {
        _removeOwnerRevocation?.call();
        _releaseController();
        _hostReady = false;
        _loadedEpoch = -1;
        _prepareController();
      }
      _epoch++;
      _downloadProgress = 0;
      _loadClock = Stopwatch()..start();
      _rotationArmed = false;
      _userTookControl = false;
      _error = null;
      _cancelCapture();
    }
    if (oldWidget.initialView != widget.initialView && _loaded) {
      unawaited(_applyInitialView(_epoch));
    }
    // A web parent's size-only rebuild needs ordinary layout, not another
    // configure/resume round trip to the same iframe. Keep native behavior.
    final activityChanged =
        bindingChanged ||
        communityChanged ||
        oldWidget.modelUrl != widget.modelUrl ||
        oldWidget.active != widget.active ||
        oldWidget.interactive != widget.interactive ||
        oldWidget.autoRotate != widget.autoRotate ||
        oldWidget.autoRotateUntilTouched != widget.autoRotateUntilTouched ||
        oldWidget.autoRotateSpeed != widget.autoRotateSpeed ||
        oldWidget.background != widget.background ||
        oldWidget.concealRenderSource != widget.concealRenderSource ||
        !identical(oldWidget.localWorkSessions, widget.localWorkSessions) ||
        oldWidget.resolveLocalPath != widget.resolveLocalPath ||
        oldWidget.hostBuilder != widget.hostBuilder ||
        (oldWidget.onSurfacePicked == null) != (widget.onSurfacePicked == null);
    if (_hostReady &&
        (!(widget.webActivityUpdatesForTesting ?? kIsWeb) || activityChanged)) {
      _updateActivity();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A focused iframe makes the outer Flutter page inactive while it remains
    // visible. Keep drawing so OrbitControls can repaint the drag it receives.
    final foreground = state == AppLifecycleState.resumed ||
        (kIsWeb && state == AppLifecycleState.inactive);
    if (_foreground == foreground) return;
    setState(() => _foreground = foreground);
    _updateActivity();
  }

  void _observeRotation() {
    final progressRevision = _controller.downloadProgressRevision;
    if (progressRevision != _lastDownloadProgressRevision) {
      _lastDownloadProgressRevision = progressRevision;
      if (!_disposed &&
          mounted &&
          _active &&
          widget.onSurfacePicked == null &&
          _loadingEpoch == _epoch) {
        final total = _controller.downloadTotalBytes;
        setState(
          () => _downloadProgress = total == null
              ? null
              : (_controller.downloadedBytes / total).clamp(0.0, 1.0),
        );
      }
    }
    final layoutRevision = _controller.surfaceMarkerLayoutRevision;
    if (layoutRevision != _lastSurfaceMarkerLayoutRevision) {
      _lastSurfaceMarkerLayoutRevision = layoutRevision;
      if (!_disposed && mounted && _loaded && _active && _routeCurrent) {
        widget.onSurfaceMarkerLayoutChanged?.call(
          _controller.surfaceMarkerLayout,
        );
      }
    }
    final markerRevision = _controller.surfaceMarkerSelectionRevision;
    if (markerRevision != _lastSurfaceMarkerSelectionRevision) {
      _lastSurfaceMarkerSelectionRevision = markerRevision;
      final id = _controller.selectedSurfaceMarkerId;
      if (!_disposed &&
          mounted &&
          _loaded &&
          _active &&
          _routeCurrent &&
          id != null) {
        widget.onSurfaceMarkerSelected?.call(id);
      }
    }
    final surfaceRevision = _controller.surfacePickRevision;
    if (surfaceRevision != _lastSurfacePickRevision) {
      _lastSurfacePickRevision = surfaceRevision;
      final anchor = _controller.pickedSurface;
      if (!_disposed &&
          mounted &&
          _loaded &&
          _active &&
          _routeCurrent &&
          anchor != null) {
        widget.onSurfacePicked?.call(anchor);
      }
    }
    _notifyIdealAspect();
    if (_disposed || !widget.autoRotateUntilTouched) return;
    final state = _controller.state;
    if (state['autoRotateUntilTouched'] == true &&
        state['autoRotate'] == true) {
      _rotationArmed = true;
    } else if (_rotationArmed &&
        state['autoRotateUntilTouched'] == false &&
        state['autoRotate'] == false) {
      // OrbitControls' start listener reports the actual user takeover. An
      // initial ready message with default false is not a touch event.
      _userTookControl = true;
    }
  }

  void _notifyIdealAspect() {
    if (_disposed ||
        !_loaded ||
        _notifiedAspectEpoch == _epoch ||
        _aspectCallbackForLoad == null) {
      return;
    }
    final state = _controller.state;
    final raw = state['idealAspect'];
    if (state['status'] != 'ready' ||
        raw is! num ||
        !raw.isFinite ||
        raw <= 0) {
      return;
    }
    final epoch = _epoch;
    final callback = _aspectCallbackForLoad!;
    _notifiedAspectEpoch = epoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !mounted || epoch != _epoch || !_loaded) return;
      try {
        callback(raw.toDouble());
      } catch (error) {
        debugPrint('[ProductModelView] aspect callback: $error');
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _ready() {
    if (_disposed) return;
    _hostReady = true;
    _logLoadPhase('host_ready');
    _updateActivity();
  }

  void _logLoadPhase(String phase, {String? source}) {
    // Timings intentionally exclude URLs, paths and account/work identifiers.
    // A loopback GLB load includes parsing, image decoding and GPU upload; it is
    // not an Internet download. Keep each milestone tied to this source epoch.
    DeviceLog.log(
      'SharedViewer',
      'phase=$phase elapsed_ms=${_loadClock.elapsedMilliseconds} '
          'epoch=$_epoch${source == null ? '' : ' source=$source'}',
    );
  }

  void _fail(Object error) {
    debugPrint('[ProductModelView] shared viewer failed: $error');
    if (_disposed) return;
    _cancelCapture();
    if (_communityLease != null &&
        !_communityLease!.isValid &&
        !_communityRecoveryUsed &&
        widget.communitySessionKey != null &&
        _communityGeneration ==
            (widget.communitySessions ?? CommunityViewerSessions.instance)
                .generation) {
      // A warm document may have been reclaimed while hidden. Rebuild it once;
      // never try to load through the invalidated controller/presentation.
      _communityRecoveryUsed = true;
      _epoch++;
      _downloadProgress = 0;
      _hostReady = false;
      _loadedEpoch = -1;
      _loadingEpoch = null;
      _error = null;
      _releaseController();
      _prepareController();
      setState(() {});
      return;
    }
    setState(() => _error = error);
    _logLoadPhase('failed');
    widget.onError?.call(error);
    debugPrint('[ProductModelView] $error');
  }

  void _updateActivity() {
    if (!_hostReady || _disposed) return;
    _cancelCapture();
    final epoch = _epoch;
    unawaited(
      _synchronize().catchError((Object error) {
        if (!_disposed && epoch == _epoch) _fail(error);
      }),
    );
  }

  Future<void> _synchronize() async {
    final epoch = _epoch;
    final updateRotation =
        _rotationConfigurationEpoch != epoch ||
        _lastAutoRotate != widget.autoRotate ||
        _lastUntilTouched != widget.autoRotateUntilTouched;
    _rotationConfigurationEpoch = epoch;
    _lastAutoRotate = widget.autoRotate;
    _lastUntilTouched = widget.autoRotateUntilTouched;
    await _controller.configure(
      interactive: widget.interactive,
      // Omit these keys on activity/color refreshes: even a delayed state
      // message cannot cause pause/resume to rearm rotation after a touch.
      autoRotate: updateRotation
          ? widget.autoRotate && !_userTookControl
          : null,
      autoRotateUntilTouched: updateRotation
          ? widget.autoRotateUntilTouched && !_userTookControl
          : null,
      // Existing product callers express speed in radians per second.
      // OrbitControls uses revolutions per 30 seconds at speed=2.
      autoRotateSpeed: widget.autoRotateSpeed * 30 / math.pi,
      background: widget.background.toARGB32() & 0xffffff,
    );
    if (_disposed || epoch != _epoch) return;
    if (!_active) {
      await _controller.pause();
      return;
    }
    await _controller.resume();
    if (_disposed || epoch != _epoch) return;
    if (!_active) {
      await _controller.pause();
      return;
    }
    if (!_loaded) {
      await _load(epoch);
    } else if (_showsCapturedFrame) {
      _scheduleCapture(immediate: true);
    } else {
      _notifyReady(epoch);
    }
  }

  Future<void> _load(int epoch) async {
    if (_loadingEpoch == epoch) return;
    _loadingEpoch = epoch;
    _firstFrameCallbackForLoad = widget.onFirstFrameReady;
    _stillFrameCallbackForLoad = widget.onStillFrame;
    _viewerReadyCallbackForLoad = widget.onViewerReady;
    _aspectCallbackForLoad = widget.onIdealAspectRatio;
    final url = widget.modelUrl;
    _modelContentHash = null;
    try {
      final uri = Uri.parse(url);
      final format = switch (uri.path.toLowerCase()) {
        final path when path.endsWith('.ply') => SharedModelFormat.ply,
        final path when path.endsWith('.skp') => SharedModelFormat.skp,
        _ => SharedModelFormat.glb,
      };
      final lease = _localLease;
      final community = _communityLease;
      final warm =
          (lease != null &&
              lease.hasLoadedScene &&
              await lease.verifyLoadedScene(format)) ||
          (community != null &&
              community.hasLoadedScene &&
              await community.verifyLoadedScene(format));
      if (warm) {
        _modelContentHash = community?.modelContentSha256;
        _logLoadPhase('retained_scene');
      } else if (community != null) {
        // The retained owner, rather than this route, owns an in-flight load.
        // Closing the route must not turn a completed download into a second
        // parse/upload on the next entry.
        final controller = community.controller;
        final resolver =
            widget.resolveLocalPath ?? resolveSharedViewerModelPath;
        final needsIdentity = widget.onSurfacePicked != null;
        String? verifiedIdentity;
        await community.ensureLoaded(() async {
          final path = uri.scheme.isEmpty
              ? url
              : uri.scheme == 'file'
              ? uri.toFilePath()
              : await resolver(url);
          if (!community.retainedSession.isDisposed) {
            final before = needsIdentity ? await modelFileSha256(path) : null;
            if (community.retainedSession.isDisposed) {
              throw StateError('Community viewer scene revoked');
            }
            await controller.loadLocalFile(path, format: format);
            if (before != null && !community.retainedSession.isDisposed) {
              final after = await modelFileSha256(path);
              if (after == before) verifiedIdentity = before;
            }
          }
        }, verifiedModelSha256: () async => verifiedIdentity);
        _modelContentHash = community.modelContentSha256;
        _logLoadPhase('renderer_load', source: 'retained_community');
      } else if (lease != null) {
        await lease.ensureLoaded(
          () => _controller.loadLocalFile(lease.canonicalPath, format: format),
        );
        _logLoadPhase('renderer_load', source: 'retained_local');
      } else if (kIsWeb || widget.browserModelClient != null) {
        _logLoadPhase('renderer_load', source: 'browser');
        if (widget.onSurfacePicked == null) {
          setState(() => _downloadProgress = null);
          await _controller.load(url: uri, format: format);
        } else {
          final controller = _controller;
          bool current() =>
              !_disposed &&
              epoch == _epoch &&
              _active &&
              identical(controller, _controller);
          final identity = await loadBrowserModelBytes(
            uri: uri,
            isCurrent: current,
            client: widget.browserModelClient,
            onProgress: (received, total) {
              if (!current() || !mounted) return;
              final progress = total == null
                  ? null
                  : (received / total).clamp(0.0, 1.0);
              unawaited(
                controller.setDownloadProgress(received, total).catchError((
                  Object error,
                ) {
                  if (current()) _fail(error);
                }),
              );
              if (_downloadProgress != progress) {
                setState(() => _downloadProgress = progress);
              }
            },
            load: (bytes) => controller.loadBytes(bytes, format: format),
          );
          if (!current() || identity == null) return;
          _modelContentHash = identity;
        }
      } else {
        // Local work output is the durable source itself: do not involve the
        // community download/cache resolver for a file URL.
        final path = uri.scheme.isEmpty
            ? url
            : uri.scheme == 'file'
            ? uri.toFilePath()
            : await (widget.resolveLocalPath ?? resolveSharedViewerModelPath)(
                url,
              );
        if (_disposed || epoch != _epoch || !_active) return;
        // Only surface-comment consumers request content identity. Other model
        // viewers keep their existing load path and cost.
        final identity = widget.onSurfacePicked == null
            ? null
            : await modelFileSha256(path);
        if (_disposed || epoch != _epoch || !_active) return;
        _logLoadPhase(
          'renderer_load',
          source: uri.scheme.isEmpty || uri.scheme == 'file'
              ? 'local'
              : 'cached_remote',
        );
        await _controller.loadLocalFile(path, format: format);
        if (identity != null && !_disposed && epoch == _epoch) {
          final afterLoad = await modelFileSha256(path);
          if (!_disposed && epoch == _epoch && afterLoad == identity) {
            _modelContentHash = identity;
          }
        }
      }
      if (_disposed || epoch != _epoch) return;
      await _applyInitialView(epoch);
      if (_disposed || epoch != _epoch) return;
      _loadedEpoch = epoch;
      _notifyIdealAspect();
      _logLoadPhase('decoded');
      if (!_active) {
        await _controller.pause();
      } else if (!_showsCapturedFrame) {
        _notifyReady(epoch);
      } else {
        _scheduleCapture(immediate: true);
      }
    } finally {
      if (_loadingEpoch == epoch) _loadingEpoch = null;
    }
  }

  Future<void> _applyInitialView(int epoch) async {
    if (_disposed || epoch != _epoch || _initialViewAttemptedEpoch == epoch) return;
    final initialView = widget.initialView;
    if (initialView == null || initialView['schema'] != 'pw.camera-framing.v1' ||
        _modelContentHash == null || initialView['asset_sha256'] != _modelContentHash) return;
    _initialViewAttemptedEpoch = epoch;
    // An opening-card seed may precede the server descriptor. Never move a
    // camera the user has already adjusted while that metadata was arriving.
    if (_controller.state['userHasInteracted'] == true || _userTookControl) return;
    try {
      await _controller.setCameraFraming(initialView);
    } catch (_) {
      // Invalid server framing retains the official loaded-model camera.
    }
  }

  void _notifyReady(int epoch) {
    // A completed JavaScript request need not schedule a Flutter frame itself.
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed ||
          epoch != _epoch ||
          !_loaded ||
          !_active ||
          !_routeCurrent ||
          _error != null ||
          _notifiedEpoch == epoch ||
          (widget.concealRenderSource && !_hasCurrentFrame)) {
        return;
      }
      setState(() => _notifiedEpoch = epoch);
      _logLoadPhase('first_frame');
      // The same current-frame gate guards both callbacks. Deliver the exact
      // decoded PNG before readiness can release this mounted source. Evicting
      // its image cache on dispose does not mutate the recipient's byte data.
      if (!widget.interactive && !widget.autoRotate && _hasCurrentFrame) {
        try {
          _stillFrameCallbackForLoad?.call(_frame!.bytes);
        } catch (error) {
          debugPrint('[ProductModelView] still-frame callback: $error');
        }
      }
      // Parent callbacks must not turn an already displayed model into a load
      // failure, or prevent independent callbacks from running.
      try {
        _firstFrameCallbackForLoad?.call();
      } catch (error) {
        debugPrint('[ProductModelView] first-frame callback: $error');
      }
      try {
        _viewerReadyCallbackForLoad?.call(_capture);
      } catch (error) {
        debugPrint('[ProductModelView] capture callback: $error');
      }
    });
  }

  void _cancelCapture() {
    _captureTimer?.cancel();
    _captureTimer = null;
  }

  void _scheduleCapture({bool immediate = false}) {
    if (_disposed ||
        !_active ||
        !_loaded ||
        !_showsCapturedFrame ||
        !_hasCaptureLayout ||
        _capturing ||
        _captureTimer != null ||
        _error != null) {
      return;
    }
    _captureTimer = Timer(immediate ? Duration.zero : _captureInterval, () {
      _captureTimer = null;
      unawaited(_captureFrame());
    });
  }

  Future<void> _captureFrame() async {
    if (_disposed ||
        !_active ||
        !_loaded ||
        _capturing ||
        !_showsCapturedFrame ||
        !_hasCaptureLayout) {
      return;
    }
    _capturing = true;
    final epoch = _epoch;
    final layoutRevision = _layoutRevision;
    bool stale() =>
        _disposed ||
        epoch != _epoch ||
        !_active ||
        (widget.concealRenderSource && layoutRevision != _layoutRevision);
    try {
      final data = await _rendererCapture();
      if (!mounted || stale()) return;
      final bytes = _decodeCapture(data, 'image/png');
      if (bytes == null) throw StateError('Shared renderer returned no PNG');
      final next = MemoryImage(bytes);
      Object? decodeError;
      await precacheImage(
        next,
        context,
        onError: (error, stack) {
          decodeError = error;
        },
      );
      if (decodeError != null) {
        await next.evict();
        throw StateError(
          'Shared renderer PNG could not be decoded: $decodeError',
        );
      }
      if (stale()) {
        await next.evict();
        return;
      }
      final previous = _frame;
      setState(() {
        _frame = next;
        _frameEpoch = epoch;
        _frameLayoutRevision = layoutRevision;
      });
      // The Image widget owns its display handle. Evict the previous cache key
      // so a rotating card does not accumulate every captured frame in RAM.
      if (previous != null) unawaited(previous.evict());
      _notifyReady(epoch);
      if (!widget.autoRotate) await _controller.pause();
    } catch (error) {
      if (!stale()) _fail(error);
    } finally {
      _capturing = false;
      if (!_disposed && _active && (widget.autoRotate || !_hasCurrentFrame)) {
        _scheduleCapture();
      }
    }
  }

  Future<Uint8List?> _captureThumb(double quality) async {
    if (_disposed ||
        !_hostReady ||
        !_loaded ||
        !_active ||
        !_hasCaptureLayout) {
      return null;
    }
    try {
      final epoch = _epoch;
      final layoutRevision = _layoutRevision;
      final result = await _rendererCapture(
        type: 'image/jpeg',
        quality: quality,
      );
      if (_disposed ||
          epoch != _epoch ||
          !_active ||
          (widget.concealRenderSource && layoutRevision != _layoutRevision)) {
        return null;
      }
      return _decodeCapture(result, 'image/jpeg');
    } catch (error) {
      debugPrint('[ProductModelView] thumbnail capture: $error');
      return null;
    }
  }

  Future<Object?> _rendererCapture({
    String type = 'image/png',
    double? quality,
  }) {
    // Includes thumbnail requests: there is never more than one bridge capture
    // in flight, even if the thumbnail baker races the live-card compositor.
    final epoch = _epoch;
    final layoutRevision = _layoutRevision;
    final concealed = widget.concealRenderSource;
    final size = _captureSize;
    final pixelRatio = _capturePixelRatio;
    bool stale() =>
        _disposed ||
        !_active ||
        epoch != _epoch ||
        (concealed && (layoutRevision != _layoutRevision || size == null));
    final result = _captureQueue.then((_) async {
      if (stale()) return null;
      if (concealed) {
        // Offstage hosts may expose a 1px DOM viewport. Every PNG/JPEG request
        // owns its measured logical viewport and DPR until capture completes.
        await _controller.resize(
          width: size!.width,
          height: size.height,
          pixelRatio: pixelRatio,
        );
        if (stale()) return null;
      }
      return _controller.capture(type: type, quality: quality);
    });
    _captureQueue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  static Uint8List? _decodeCapture(Object? data, String mime) {
    final prefix = 'data:$mime;base64,';
    if (data is! String || !data.startsWith(prefix)) return null;
    try {
      return base64Decode(data.substring(prefix.length));
    } on FormatException {
      return null;
    }
  }

  bool get _showDownloadProgress =>
      (kIsWeb || widget.browserModelClient != null) &&
      _error == null &&
      _notifiedEpoch != _epoch;

  Widget _downloadOverlay() => ColoredBox(
    key: const ValueKey('product-model-download'),
    color: widget.background,
    child: Center(
      child: SizedBox.square(
        dimension: 64,
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: _downloadProgress,
              color: Colors.white,
              backgroundColor: Colors.white24,
              strokeWidth: 3,
            ),
            Center(
              child: Text(
                _downloadProgress == null
                    ? '—'
                    : '${(_downloadProgress! * 100).floor()}%',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!_controllerReady || !(widget.localWork?.store.isActive ?? true)) {
      return ColoredBox(
        color: widget.background,
        child: _error == null
            ? (_showDownloadProgress
                  ? _downloadOverlay()
                  : const SizedBox.expand())
            : const Center(
                child: Icon(
                  Icons.error_outline_rounded,
                  color: Colors.grey,
                  size: 32,
                ),
              ),
      );
    }
    final viewerL10n = Localizations.of<AppL10n>(context, AppL10n);
    final viewerUiStrings = <String, String>{
      if (viewerL10n != null) ...{
        'locale': viewerL10n.localeName,
        'title': viewerL10n.sharedViewerTitle,
        'canvasLabel': viewerL10n.sharedViewerCanvasLabel,
        'initializing': viewerL10n.sharedViewerInitializing,
        'loading': viewerL10n.sharedViewerLoading,
        'failure': viewerL10n.sharedViewerFailure,
        'skpNotice': viewerL10n.sharedViewerSkpNotice,
      },
      // The pinned localization bridge accepts non-empty strings only.
      if (kIsWeb) ...{'initializing': ' ', 'loading': ' '},
    };
    final host =
        widget.hostBuilder?.call(context, _controller, _ready, _fail) ??
        SharedViewer(
          uiStrings: viewerUiStrings,
          controller: _controller,
          retainedSession:
              _localLease?.retainedSession ?? _communityLease?.retainedSession,
          active: _active,
          pointerEventsEnabled: widget.pointerEventsEnabled,
          pointerEventsEnabledNotifier: widget.pointerEventsEnabledNotifier,
          onReady: _ready,
          onError: _fail,
        );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (widget.concealRenderSource) {
          _observeCaptureLayout(
            constraints,
            MediaQuery.devicePixelRatioOf(context),
          );
        }
        return ColoredBox(
          color: widget.background,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Concealed static cards never submit platform-view paint. Keep
              // WebView/JS mounted and ticking; explicit resize/capture drives it.
              if (widget.concealRenderSource)
                Offstage(
                  key: const ValueKey('product-shared-render-source'),
                  offstage: true,
                  child: IgnorePointer(child: host),
                )
              else
                // The default interactive/rotating presentation retains its
                // positive-opacity source and existing lifecycle behavior.
                Opacity(
                  key: const ValueKey('product-shared-render-source'),
                  opacity: widget.interactive ? 1 : 0.02,
                  child: IgnorePointer(
                    ignoring: !widget.interactive,
                    child: host,
                  ),
                ),
              if (_showsCapturedFrame)
                ColoredBox(
                  color: widget.background,
                  child: !_hasCurrentFrame
                      ? const SizedBox.expand()
                      : Image(
                          image: _frame!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          excludeFromSemantics: true,
                        ),
                ),
              if (_showDownloadProgress) _downloadOverlay(),
              if (_error != null)
                const Center(
                  child: Icon(
                    Icons.error_outline_rounded,
                    color: Colors.grey,
                    size: 32,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _preparation++;
    _disposed = true;
    _epoch++;
    _cancelCapture();
    WidgetsBinding.instance.removeObserver(this);
    _removeOwnerRevocation?.call();
    _releaseController();
    final frame = _frame;
    if (frame != null) unawaited(frame.evict());
    super.dispose();
  }
}
