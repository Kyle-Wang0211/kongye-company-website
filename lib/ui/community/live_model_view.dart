import 'package:flutter/material.dart';

import '../shared/product_model_view.dart';

/// Legacy caller-compatible name; this no longer creates a Thermion renderer.
class LiveModelView extends StatelessWidget {
  const LiveModelView({
    super.key,
    required this.modelUrl,
    this.autoRotate = false,
    this.interactive = false,
    this.background = Colors.white,
    this.cameraDistance = 5.5,
    this.useEnvironmentLighting = true,
  });

  final String modelUrl;
  final bool autoRotate;
  final bool interactive;
  final Color background;
  final double cameraDistance;
  final bool useEnvironmentLighting;

  @override
  Widget build(BuildContext context) => ProductModelView(
    modelUrl: modelUrl,
    autoRotate: autoRotate && !interactive,
    interactive: interactive,
    background: background,
  );
}
