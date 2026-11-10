import 'package:flutter/widgets.dart';
import '../../eta/pipeline_eta.dart';
import '../../l10n/app_localizations.dart';

/// Minute-granularity display of the live, per-second prediction. Prediction
/// preserves the supplied estimator: sparse/legacy Ninja or Full38 browser-rate
/// trial. This formatter does not change its rate.
/// Null or exhausted estimates never imply reconstruction has completed.
String? etaCountdownText(
  BuildContext context,
  EtaLabel? label, {
  bool sparseStage = false,
}) {
  final l10n = AppL10n.of(context);
  final seconds = label?.remainingSeconds;
  if (seconds == null || seconds <= 0) {
    return sparseStage ? l10n.etaSparseCalculating : null;
  }
  final time = seconds <= 60
      ? l10n.etaDurationUnderMinute
      : l10n.etaDurationMinutes((seconds / 60).ceil());
  return sparseStage ? l10n.etaSparseCountdown(time) : l10n.etaCountdown(time);
}
