import 'package:flutter/material.dart';

/// Shared with the released website's 64px percentage ring and gray sweep.
class ModelDownloadPlaceholder extends StatelessWidget {
  const ModelDownloadPlaceholder({
    super.key,
    this.progress,
    this.lastProgress = 0,
  });
  final double? progress;
  final double lastProgress;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const _ViewerLoadingSweep(),
      Center(
        child: SizedBox.square(
          dimension: 64,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: progress,
                color: Colors.white,
                backgroundColor: Colors.white24,
                strokeWidth: 3,
              ),
              Center(
                child: Text(
                  '${(lastProgress * 100).floor().clamp(0, 99)}%',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

// Exact colors, timing and sweep from the existing web CommunityShimmer.
class _ViewerLoadingSweep extends StatefulWidget {
  const _ViewerLoadingSweep();
  @override
  State<_ViewerLoadingSweep> createState() => _ViewerLoadingSweepState();
}

class _ViewerLoadingSweepState extends State<_ViewerLoadingSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context)) {
      _animation.stop();
    } else {
      _animation.repeat();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AnimatedBuilder(
      animation: _animation,
      builder: (_, child) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-3 + _animation.value * 6, -1),
            end: Alignment(-1 + _animation.value * 6, 1),
            colors: const [
              Color(0xff242424),
              Color(0xff404040),
              Color(0xff242424),
            ],
          ),
        ),
        child: child,
      ),
      child: const SizedBox.expand(),
    ),
  );
}
