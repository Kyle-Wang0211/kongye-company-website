// Browser has no native Apple thermal/footprint probe. No measurement is fabricated.
class PwTelemetrySample {
  const PwTelemetrySample({
    required this.physFootprintMb,
    required this.peakFootprintMb,
    required this.thermalState,
  });

  /// Jetsam-relevant resident footprint, MB. -1 if the mach query failed.
  final double physFootprintMb;

  /// Process-lifetime high-water footprint, MB.
  final double peakFootprintMb;

  /// 0 nominal · 1 fair · 2 serious · 3 critical.
  final int thermalState;

  String get thermalName => switch (thermalState) {
        0 => 'nominal',
        1 => 'fair',
        2 => 'serious',
        3 => 'critical',
        _ => 'unknown',
      };

  @override
  String toString() =>
      'mem=${physFootprintMb.toStringAsFixed(0)}MB '
      'peak=${peakFootprintMb.toStringAsFixed(0)}MB '
      'thermal=$thermalName';
}

class PwTelemetry {
  static PwTelemetrySample? sample() => null;
}
