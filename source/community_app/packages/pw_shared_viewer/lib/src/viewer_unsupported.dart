import 'package:flutter/widgets.dart';
import 'controller.dart';
import 'retained_session_unsupported.dart';

class SharedViewer extends StatelessWidget {
  const SharedViewer(
      {super.key,
      required this.controller,
      this.onReady,
      this.onError,
      this.active = true,
      this.webEntryUri,
      this.retainedSession});
  final SharedViewerController controller;
  final VoidCallback? onReady;
  final ValueChanged<Object>? onError;
  final Uri? webEntryUri;
  final bool active;
  // Native retention is unsupported here; ordinary web behavior is unchanged.
  final SharedViewerRetainedSession? retainedSession;
  @override
  Widget build(BuildContext context) => const SizedBox.expand(
      child:
          Center(child: Text('Shared Viewer is unavailable on this platform')));
}
