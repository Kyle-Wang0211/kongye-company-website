import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';
import 'host_receipt.dart';

void main() => runApp(const MaterialApp(home: HostFixture()));

/// Cross-platform integration fixture; no production record, account or job access.
class HostFixture extends StatefulWidget {
  const HostFixture({super.key});
  @override
  State<HostFixture> createState() => _HostFixtureState();
}

class _HostFixtureState extends State<HostFixture> {
  final controller = SharedViewerController();
  @override
  void initState() {
    super.initState();
    controller.addListener(_publishState);
  }

  void _publishState() => publishState(controller.state);

  Future<void> _ready() async {
    try {
      const configuredModel = String.fromEnvironment('VIEWER_MODEL_URL');
      final model = configuredModel.isNotEmpty
          ? configuredModel
          : Uri.base.queryParameters['model'];
      if (model != null) {
        await controller.load(
          url: Uri.base.resolve(model),
          format: SharedModelFormat.values.byName(
              (const String.fromEnvironment('VIEWER_MODEL_FORMAT')).isNotEmpty
                  ? const String.fromEnvironment('VIEWER_MODEL_FORMAT')
                  : Uri.base.queryParameters['format'] ?? 'glb'),
        );
      }
      publishReady();
    } catch (error) {
      _error(error);
    }
  }

  void _error(Object error) => publishError(error);

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: SharedViewer(
          controller: controller,
          onReady: () => unawaited(_ready()),
          onError: _error,
        ),
      );

  @override
  void dispose() {
    controller.removeListener(_publishState);
    controller.dispose();
    super.dispose();
  }
}
