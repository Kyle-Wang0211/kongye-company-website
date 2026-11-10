/// Keeps disk/package initialization behind the first visible splash frame.
/// Auth and capture readiness must still await [ensureReady]. A failed attempt
/// propagates to the caller and may be retried; successful work is reused.
class FirstFrameStartup {
  FirstFrameStartup({required this.firstFrame, required this.initialize});

  final Future<void> Function() firstFrame;
  final Future<void> Function() initialize;
  Future<void>? _pending;

  Future<void> ensureReady() => _pending ??= _run();

  Future<void> _run() async {
    try {
      await firstFrame();
      await initialize();
    } catch (_) {
      _pending = null;
      rethrow;
    }
  }
}
