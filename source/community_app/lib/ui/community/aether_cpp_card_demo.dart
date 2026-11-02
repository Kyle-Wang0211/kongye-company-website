import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';

import '../shared/product_model_view.dart';
import '../shared/community_viewer_session.dart';
import '../shared/local_work_viewer_session.dart';
import 'viewer_impl.dart' show SplatViewerOverrides, ViewerQuality;

/// Compatibility name for existing product callers. All rendering now uses the
/// same packaged Three.js renderer as the web viewer. Legacy quality/splat
/// arguments remain source-compatible; they do not select another renderer or
/// reduce the source model's quality.
class AetherCppCardDemo extends StatelessWidget {
  const AetherCppCardDemo({
    super.key,
    required this.modelUrl,
    this.isFocused = false,
    this.interactive = false,
    this.pointerEventsEnabled = true,
    this.pointerEventsEnabledNotifier,
    this.concealRenderSource = false,
    this.quality,
    this.autoRotateUntilTouched = false,
    this.autoRotateSpeed = 0.6,
    this.background = Colors.white,
    this.fallbackCameraDistance = 5.5,
    this.splatOverrides = SplatViewerOverrides.none,
    this.onFirstFrameReady,
    this.onStillFrame,
    this.onError,
    this.onViewerReady,
    this.onIdealAspectRatio,
    this.onSurfacePicked,
    this.onSurfaceMarkerSelected,
    this.onSurfaceMarkerLayoutChanged,
    this.resolveLocalPathForTesting,
    this.hostBuilderForTesting,
    this.localWork,
    this.communitySessionKey,
    this.communitySessions,
  });

  final String modelUrl;
  final LocalWorkViewerBinding? localWork;
  final String? communitySessionKey;
  final CommunityViewerSessions? communitySessions;
  final bool isFocused;
  final bool interactive;
  final bool pointerEventsEnabled;
  final ValueNotifier<bool>? pointerEventsEnabledNotifier;
  final bool concealRenderSource;
  final double autoRotateSpeed;
  final Color background;
  final double fallbackCameraDistance;
  final SplatViewerOverrides splatOverrides;
  final ViewerQuality? quality;
  final VoidCallback? onFirstFrameReady;
  final ValueChanged<Uint8List>? onStillFrame;
  final ValueChanged<Object>? onError;
  final ValueChanged<ProductViewerCapture>? onViewerReady;
  final ValueChanged<double>? onIdealAspectRatio;
  final ValueChanged<SharedSurfaceAnchor>? onSurfacePicked;
  final ValueChanged<String>? onSurfaceMarkerSelected;
  final ValueChanged<SharedSurfaceMarkerLayout?>? onSurfaceMarkerLayoutChanged;
  final Future<String> Function(String)? resolveLocalPathForTesting;
  // Forward the existing shared-renderer host seam only for widget tests.
  // ignore: invalid_use_of_visible_for_testing_member
  final ProductModelHostBuilder? hostBuilderForTesting;
  final bool autoRotateUntilTouched;

  @override
  Widget build(BuildContext context) => ProductModelView(
    modelUrl: modelUrl,
    localWork: localWork,
    communitySessionKey: communitySessionKey,
    communitySessions: communitySessions,
    interactive: interactive,
    pointerEventsEnabled: pointerEventsEnabled,
    pointerEventsEnabledNotifier: pointerEventsEnabledNotifier,
    concealRenderSource: concealRenderSource,
    autoRotate: isFocused && (!interactive || autoRotateUntilTouched),
    autoRotateUntilTouched: autoRotateUntilTouched,
    autoRotateSpeed: autoRotateSpeed,
    background: background,
    onFirstFrameReady: onFirstFrameReady,
    onStillFrame: onStillFrame,
    onError: onError,
    onViewerReady: onViewerReady,
    onIdealAspectRatio: onIdealAspectRatio,
    onSurfacePicked: onSurfacePicked,
    onSurfaceMarkerSelected: onSurfaceMarkerSelected,
    onSurfaceMarkerLayoutChanged: onSurfaceMarkerLayoutChanged,
    // ignore: invalid_use_of_visible_for_testing_member
    resolveLocalPath: resolveLocalPathForTesting,
    // ignore: invalid_use_of_visible_for_testing_member
    hostBuilder: hostBuilderForTesting,
  );
}
