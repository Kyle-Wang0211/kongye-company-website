import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../shared/product_point_view.dart';
import '../shared/local_work_viewer_session.dart';
import '../community/card_live_governor.dart';

/// The shared renderer's upstream OrbitControls owns rotation and yields after
/// the first touch. No second camera, Dart orbit loop, or point renderer.
class AutoRotatingCloudView extends StatefulWidget {
  const AutoRotatingCloudView({
    super.key,
    required this.xyz,
    required this.rgb,
    this.showControls = true,
    this.logTag = 'viewer',
    this.sourcePath,
    this.onFirstFrameReady,
    this.onError,
    this.viewerBuilderForTesting,
    this.localWork,
  });

  final Float32List xyz;
  final Uint8List rgb;
  final bool showControls;
  final String logTag;
  final String? sourcePath;
  final LocalWorkViewerBinding? localWork;
  final VoidCallback? onFirstFrameReady;
  final ValueChanged<Object>? onError;
  final ProductPointViewerBuilder? viewerBuilderForTesting;

  @override
  State<AutoRotatingCloudView> createState() => _AutoRotatingCloudViewState();
}

class _AutoRotatingCloudViewState extends State<AutoRotatingCloudView> {
  late final CardLiveGovernor _governor;
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _governor = CardLiveGovernor()..addListener(_governorChanged);
  }

  void _governorChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _governor.removeListener(_governorChanged);
    _governor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) {
      if (!_touched) setState(() => _touched = true);
    },
    child: ProductPointView(
      xyz: widget.xyz,
      rgb: widget.rgb,
      sourcePath: widget.sourcePath,
      localWork: widget.localWork,
      onFirstFrameReady: widget.onFirstFrameReady,
      onError: widget.onError,
      viewerBuilder: widget.viewerBuilderForTesting,
      autoRotate: !_touched && _governor.liveAllowed,
      showControls: widget.showControls,
      maxFps: _governor.fpsCap.toDouble(),
    ),
  );
}
