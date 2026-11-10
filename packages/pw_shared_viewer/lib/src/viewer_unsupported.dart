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
      this.pointerEventsEnabled = true,
      this.pointerEventsEnabledNotifier,
      this.uiStrings = const {},
      this.webEntryUri,
      this.retainedSession});
  final SharedViewerController controller;
  final VoidCallback? onReady;
  final ValueChanged<Object>? onError;
  final Uri? webEntryUri;
  final bool active;
  final bool pointerEventsEnabled;
  final ValueNotifier<bool>? pointerEventsEnabledNotifier;
  final Map<String, String> uiStrings;
  // Native retention is unsupported here; ordinary web behavior is unchanged.
  final SharedViewerRetainedSession? retainedSession;
  @override
  Widget build(BuildContext context) => SizedBox.expand(
      child: Center(
          child: Text(uiStrings['failure'] ??
              'Shared Viewer is unavailable on this platform')));
}
