import 'dart:io';
import 'generated_artifact_retirement.dart';
import 'vendor/dart_pipeline/lib/pw38_pipeline.dart';

/// Reuses the existing last-reader retirement after the actual awaited
/// avNormal call and output observation. These are generated PNG inputs,
/// distinct from original JPEGs and baked normal maps consumed by GLB.
Future<void> retireGeneratedNormalInputPngs({
  required Directory inputRoot,
  required File evidenceFile,
  required Iterable<Pw38Artifact> normalImages,
  required Iterable<Pw38Artifact> allMaterial,
}) async {
  final retirement = GeneratedArtifactRetirement(
    root: inputRoot,
    evidenceFile: evidenceFile,
  );
  final protected = allMaterial
      .where((a) => a.role != 'normal_image')
      .map((a) => a.path)
      .toSet();
  for (final image in normalImages) {
    if (!protected.contains(image.path)) {
      retirement.register(
        image.path,
        bytes: image.bytes,
        sha256: image.sha256,
        lastReaderStage: Pw38Stage.avNormal.index,
      );
    }
  }
  await retirement.stageValidated(Pw38Stage.avNormal.index);
  await retirement.seal();
}
