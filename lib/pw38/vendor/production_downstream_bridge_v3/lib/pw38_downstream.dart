import '../../../frame_transport.dart';
import '../../dart_pipeline/lib/pw38_pipeline.dart';

export '../../dart_pipeline/lib/pw38_pipeline.dart'
    show
        Pw38Artifact,
        Pw38ArtifactGate,
        Pw38RunContract,
        Pw38SourceGates,
        Pw38Stage,
        Pw38StageDriver,
        Pw38StageReceipt;

const pw38ImportedRouteId = 'selected38_original97_v1';
const pw38DownstreamStages = <Pw38Stage>[
  Pw38Stage.tsdf,
  Pw38Stage.trim,
  Pw38Stage.meshopt,
  Pw38Stage.lagrange,
  Pw38Stage.texture,
  Pw38Stage.avVisibility,
  Pw38Stage.avSfmToAbc,
  Pw38Stage.avNormal,
  Pw38Stage.glb,
];
const pw38ImportedUpstreamStages = <Pw38Stage>[
  Pw38Stage.mvs768,
  Pw38Stage.mvs1536,
  Pw38Stage.cer,
  Pw38Stage.fusionPly,
];
bool _hash(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

String _root(String value) {
  if (!value.startsWith('/') ||
      value.length < 2 ||
      value.contains('\\') ||
      value.contains('\x00') ||
      value.split('/').skip(1).any((p) => p.isEmpty || p == '.' || p == '..')) {
    throw FormatException('Noncanonical absolute IO root: $value');
  }
  return value;
}

bool _inside(String path, String root) =>
    path == root || path.startsWith('$root/');

/// Exact adapter IO ownership. These immutable strings are declarations until
/// reviewed async gates attest resolved actual paths (including symlink safety).
final class Pw38IoRoots {
  const Pw38IoRoots({
    required this.durableInputRoot,
    required this.downstreamOutputRoot,
    required this.textureSceneRoot,
  });
  final String durableInputRoot, downstreamOutputRoot, textureSceneRoot;
  bool same(Pw38IoRoots other) =>
      durableInputRoot == other.durableInputRoot &&
      downstreamOutputRoot == other.downstreamOutputRoot &&
      textureSceneRoot == other.textureSceneRoot;
  void validate(List<String> cleanupRoots) {
    for (final root in [
      durableInputRoot,
      downstreamOutputRoot,
      textureSceneRoot,
    ]) {
      _root(root);
    }
    if (!_inside(textureSceneRoot, durableInputRoot) ||
        textureSceneRoot == durableInputRoot ||
        _inside(durableInputRoot, downstreamOutputRoot) ||
        _inside(downstreamOutputRoot, durableInputRoot)) {
      throw Pw38IoBindingError('Input/output/texture scene ownership overlaps');
    }
    if (cleanupRoots.length != 2 || cleanupRoots[0] == cleanupRoots[1]) {
      throw Pw38IoBindingError('Both distinct cleanup roots required');
    }
    for (final cleanupRoot in cleanupRoots) {
      _root(cleanupRoot);
      for (final retainedRoot in [durableInputRoot, downstreamOutputRoot]) {
        if (_inside(retainedRoot, cleanupRoot) ||
            _inside(cleanupRoot, retainedRoot)) {
          throw Pw38IoBindingError(
            'Durable input/output overlaps production cleanup',
          );
        }
      }
    }
  }
}

final class Pw38IoBindingError implements Exception {
  const Pw38IoBindingError(this.message);
  final String message;
  @override
  String toString() => 'Actual IO binding rejected: $message';
}

abstract interface class Pw38IoBound {
  Pw38IoRoots get ioRoots;
}

/// Keeps the existing frozen contract/types and adds mandatory actual IO roots.
final class Pw38DownstreamContract {
  const Pw38DownstreamContract({required this.value, required this.ioRoots});
  final Pw38RunContract value;
  final Pw38IoRoots ioRoots;
}

bool _sameArtifact(Pw38Artifact a, Pw38Artifact b) =>
    a.path == b.path &&
    a.role == b.role &&
    a.bytes == b.bytes &&
    a.sha256 == b.sha256;

/// Copied identities only: no camera math, image decoder, D16 conversion or
/// substitute serializer exists in this Dart handoff. Native producer metadata
/// and every file are checked again by the asynchronous durable acceptor.
final class Pw38RetainedFrame {
  const Pw38RetainedFrame({
    required this.originalIndex,
    required this.packIndex,
    required this.frameIdF64Bits,
    required this.d16,
    required this.cameraF64,
    required this.metadata,
    required this.textureImage,
    required this.texture1920Camera,
    required this.normalImage,
    required this.original4032Camera,
    this.width = 1536,
    this.height = 1152,
    this.depthScale = 5000,
    this.textureWidth = 1920,
    this.textureHeight = 1440,
    this.originalImageWidth = 4032,
    this.originalImageHeight = 3024,
  });
  final int originalIndex, packIndex;
  final String frameIdF64Bits;
  final Pw38Artifact d16, cameraF64, metadata;
  final Pw38Artifact textureImage, normalImage, original4032Camera;
  final Pw38Artifact? texture1920Camera;
  final int width, height, depthScale, textureWidth, textureHeight;
  final int originalImageWidth, originalImageHeight;
  List<Pw38Artifact> get artifacts => [
    d16,
    cameraF64,
    metadata,
    textureImage,
    if (texture1920Camera != null) texture1920Camera!,
    normalImage,
    original4032Camera,
  ];
  void validate(int index, String sceneRelativePath) {
    if (originalIndex != index ||
        packIndex != index ||
        !RegExp(r'^[0-9a-f]{16}$').hasMatch(frameIdF64Bits) ||
        width != 1536 ||
        height != 1152 ||
        depthScale != 5000 ||
        d16.bytes != width * height * 2 ||
        cameraF64.bytes != 25 * 8 ||
        textureWidth != 1920 ||
        textureHeight != 1440 ||
        originalImageWidth != 4032 ||
        originalImageHeight != 3024 ||
        d16.role != 'retained_d16' ||
        cameraF64.role != 'retained_camera' ||
        metadata.role != 'retained_frame_metadata' ||
        textureImage.role != 'texture_image' ||
        texture1920Camera?.role != 'texture_1920_camera' ||
        normalImage.role != 'normal_image' ||
        original4032Camera.role != 'original_4032_camera') {
      throw StateError(
        'Selected97 retained frame $index identity/shape/role unresolved',
      );
    }
    final imageName = textureImage.path.split('/').last;
    final dot = imageName.lastIndexOf('.');
    if (dot <= 0 ||
        textureImage.path != '$sceneRelativePath/$imageName' ||
        texture1920Camera!.path !=
            '$sceneRelativePath/${imageName.substring(0, dot)}.cam') {
      throw StateError(
        'Original1920 image/camera scene pair missing for frame $index',
      );
    }
  }
}

final class Pw38ImportedUpstream {
  Pw38ImportedUpstream({
    required this.routeId,
    this.denseProducerProfile = originalRetainedLegacyProfile,
    required this.manifest,
    required this.order,
    required this.densePly,
    required this.durableInputRoot,
    required this.textureSceneRoot,
    required this.sourceCaptureDir,
    required this.sourceDensePlyPath,
    required this.producerSourceManifestSha256,
    required this.producerBinarySha256,
    required this.orderedInputManifestSha256,
    required this.modelManifestSha256,
    required this.environmentManifestSha256,
    required this.sourceGates,
    required List<Pw38RetainedFrame> orderedFrames,
    required List<Pw38StageReceipt> acceptedUpstreamReceipts,
  }) : orderedFrames = List.unmodifiable(orderedFrames),
       acceptedUpstreamReceipts = List.unmodifiable(acceptedUpstreamReceipts);
  final String denseProducerProfile;
  final String routeId,
      durableInputRoot,
      textureSceneRoot,
      sourceCaptureDir,
      sourceDensePlyPath;
  final Pw38Artifact manifest, order, densePly;
  final String producerSourceManifestSha256, producerBinarySha256;
  final String orderedInputManifestSha256,
      modelManifestSha256,
      environmentManifestSha256;
  final Pw38SourceGates sourceGates;
  final List<Pw38RetainedFrame> orderedFrames;
  final List<Pw38StageReceipt> acceptedUpstreamReceipts;
  List<Pw38Artifact> get artifacts => List.unmodifiable([
    manifest,
    order,
    densePly,
    for (final frame in orderedFrames) ...frame.artifacts,
  ]);

  void validate(List<String> cleanupRoots) {
    _root(durableInputRoot);
    _root(textureSceneRoot);
    if (!_inside(textureSceneRoot, durableInputRoot) ||
        textureSceneRoot == durableInputRoot) {
      throw StateError(
        'Texture scene must be retained under immutable input root',
      );
    }
    _root(sourceCaptureDir);
    _root(sourceDensePlyPath);
    if (routeId != pw38ImportedRouteId ||
        orderedFrames.length != frameTransportCount({'dense_producer_profile': denseProducerProfile}, actualCount: orderedFrames.length) ||
        manifest.role != 'accepted_upstream_manifest' ||
        order.role != 'order' ||
        densePly.role != 'dense_ply' ||
        !sourceGates.accepted ||
        ![
          producerSourceManifestSha256,
          producerBinarySha256,
          orderedInputManifestSha256,
          modelManifestSha256,
          environmentManifestSha256,
        ].every(_hash)) {
      throw StateError(
        'Explicit selected38 original97 accepted upstream manifest required',
      );
    }
    if (cleanupRoots.length != 2 || cleanupRoots[0] == cleanupRoots[1]) {
      throw StateError(
        'Both distinct production cleanup roots must be registered',
      );
    }
    for (final root in cleanupRoots) {
      _root(root);
      if (_inside(durableInputRoot, root) || _inside(root, durableInputRoot)) {
        throw StateError(
          'Durable upstream overlaps production cleanup ownership',
        );
      }
    }
    final paths = <String>{}, ids = <String>{};
    for (var i = 0; i < orderedFrames.length; i++) {
      orderedFrames[i].validate(
        i,
        textureSceneRoot.substring(durableInputRoot.length + 1),
      );
      if (!ids.add(orderedFrames[i].frameIdF64Bits))
        throw StateError('Duplicate retained frame identity');
    }
    for (final a in artifacts) {
      if (!paths.add(a.path))
        throw StateError('Duplicate upstream artifact path');
    }
    if (acceptedUpstreamReceipts.length != 4)
      throw StateError('Four upstream stage receipts required');
    for (var i = 0; i < 4; i++) {
      final receipt = acceptedUpstreamReceipts[i];
      if (receipt.stage != pw38ImportedUpstreamStages[i] ||
          receipt.entryReturnCode != 0 ||
          !receipt.outputGatePassed ||
          receipt.error != null) {
        throw StateError(
          'Upstream stage was not accepted: ${pw38ImportedUpstreamStages[i].name}',
        );
      }
    }
  }
}

/// Actual complete scene enumeration and format evidence, returned by the
/// durable native-file validator. No Dart camera conversion/serializer exists.
final class Pw38TextureSceneAcceptance {
  Pw38TextureSceneAcceptance({
    required this.sceneRoot,
    required List<Pw38Artifact> orderedImages,
    required List<Pw38Artifact> ordered1920Cameras,
    required this.completeDirectoryEnumerationAccepted,
    required this.original1920CameraFormatAccepted,
    required this.imageAndCameraDimensionsAccepted,
  }) : orderedImages = List.unmodifiable(orderedImages),
       ordered1920Cameras = List.unmodifiable(ordered1920Cameras);
  final String sceneRoot;
  final List<Pw38Artifact> orderedImages, ordered1920Cameras;
  final bool completeDirectoryEnumerationAccepted,
      original1920CameraFormatAccepted,
      imageAndCameraDimensionsAccepted;
  void bind(Pw38ImportedUpstream upstream) {
    if (sceneRoot != upstream.textureSceneRoot ||
        !completeDirectoryEnumerationAccepted ||
        !original1920CameraFormatAccepted ||
        !imageAndCameraDimensionsAccepted ||
        orderedImages.length != upstream.orderedFrames.length ||
        ordered1920Cameras.length != upstream.orderedFrames.length) {
      throw StateError(
        'Complete original1920 texture scene/camera format gate missing',
      );
    }
    for (var i = 0; i < upstream.orderedFrames.length; i++) {
      if (!_sameArtifact(
            orderedImages[i],
            upstream.orderedFrames[i].textureImage,
          ) ||
          !_sameArtifact(
            ordered1920Cameras[i],
            upstream.orderedFrames[i].texture1920Camera!,
          )) {
        throw StateError(
          'Actual texture scene enumeration/order/camera identity changed',
        );
      }
    }
  }
}

/// Issued only after actual native retention, canonical durable input/output
/// roots, immutable file bytes/order/metadata and full scene formats are checked.
final class Pw38UpstreamAcceptance {
  Pw38UpstreamAcceptance({
    required this.manifestSha256,
    required this.ioRoots,
    required this.textureScene,
    required List<String> checkedCleanupRoots,
    required this.producerBinarySha256,
    required this.producerSourceManifestSha256,
    required List<String> actualDefinedRetentionApiSymbols,
    required this.durableReceiptSha256,
    required this.nativeRetentionApiAccepted,
    required this.completeImmutableBytesAccepted,
    required this.formatsAndOrderAccepted,
    required this.resolvedInputAndOutputRootsAccepted,
  }) : checkedCleanupRoots = List.unmodifiable(checkedCleanupRoots),
       actualDefinedRetentionApiSymbols = List.unmodifiable(
         actualDefinedRetentionApiSymbols,
       );
  final String manifestSha256, producerBinarySha256, durableReceiptSha256;
  final Pw38IoRoots ioRoots;
  final Pw38TextureSceneAcceptance textureScene;
  final List<String> checkedCleanupRoots;
  final String producerSourceManifestSha256;
  final List<String> actualDefinedRetentionApiSymbols;
  final bool nativeRetentionApiAccepted,
      completeImmutableBytesAccepted,
      formatsAndOrderAccepted,
      resolvedInputAndOutputRootsAccepted;
  void bind(
    Pw38ImportedUpstream upstream,
    Pw38DownstreamContract contract,
    List<String> cleanupRoots,
  ) {
    if (checkedCleanupRoots.length != cleanupRoots.length ||
        !Iterable.generate(cleanupRoots.length)
            .every((i) => checkedCleanupRoots[i] == cleanupRoots[i]) ||
        !ioRoots.same(contract.ioRoots) ||
        ioRoots.durableInputRoot != upstream.durableInputRoot ||
        ioRoots.textureSceneRoot != upstream.textureSceneRoot ||
        !resolvedInputAndOutputRootsAccepted) {
      throw Pw38IoBindingError(
        'Durable validator actual roots do not bind contract',
      );
    }
    if (manifestSha256 != upstream.manifest.sha256 ||
        producerBinarySha256 != upstream.producerBinarySha256 ||
        !_hash(durableReceiptSha256) ||
        producerSourceManifestSha256 != upstream.producerSourceManifestSha256 ||
        actualDefinedRetentionApiSymbols.isEmpty ||
        !nativeRetentionApiAccepted ||
        !completeImmutableBytesAccepted ||
        !formatsAndOrderAccepted) {
      throw StateError(
        'Actual native retention/durable input acceptance incomplete',
      );
    }
    textureScene.bind(upstream);
  }
}

abstract interface class Pw38DurableUpstreamAcceptor implements Pw38IoBound {
  Future<Pw38UpstreamAcceptance> accept(
    Pw38ImportedUpstream upstream,
    Pw38DownstreamContract contract,
    List<String> cleanupRoots,
  );
}

/// Actual native adapter and artifact validator roots, attested before running
/// any stage. Declaration-only roots/export names cannot produce this receipt.
final class Pw38NativeIoAcceptance {
  Pw38NativeIoAcceptance({
    required this.stage,
    required this.driverIoRoots,
    required this.artifactGateIoRoots,
    required List<String> checkedCleanupRoots,
    required this.sourceManifestSha256,
    required this.binarySha256,
    required this.receiptSha256,
    required this.actualResolvedAdapterAndArtifactRootsAccepted,
  }) : checkedCleanupRoots = List.unmodifiable(checkedCleanupRoots);
  final Pw38Stage stage;
  final Pw38IoRoots driverIoRoots, artifactGateIoRoots;
  final List<String> checkedCleanupRoots;
  final String sourceManifestSha256, binarySha256, receiptSha256;
  final bool actualResolvedAdapterAndArtifactRootsAccepted;
  void bind(
    Pw38StageDriver driver,
    Pw38DownstreamContract contract,
    List<String> cleanupRoots,
  ) {
    if (checkedCleanupRoots.length != cleanupRoots.length ||
        !Iterable.generate(cleanupRoots.length)
            .every((i) => checkedCleanupRoots[i] == cleanupRoots[i]) ||
        !driverIoRoots.same(contract.ioRoots) ||
        !artifactGateIoRoots.same(contract.ioRoots) ||
        !actualResolvedAdapterAndArtifactRootsAccepted) {
      throw Pw38IoBindingError(
        'Actual native adapter/artifact roots unaccepted',
      );
    }
    if (stage != driver.stage ||
        sourceManifestSha256 != driver.sourceManifestSha256 ||
        binarySha256 != driver.binarySha256 ||
        !_hash(receiptSha256)) {
      throw StateError(
        'Actual driver receipt belongs to another source/binary/stage',
      );
    }
  }
}

abstract interface class Pw38NativeCapabilityGate implements Pw38IoBound {
  /// Verify actual exports, source/binary bytes, resolved IO ownership and
  /// required platform byte gates, without running algorithms.
  Future<Pw38NativeIoAcceptance> requireAccepted(
    Pw38StageDriver driver,
    Pw38DownstreamContract contract,
    Pw38DownstreamArtifactGate artifacts,
    List<String> cleanupRoots,
  );
}

final class Pw38OutputAcceptance {
  const Pw38OutputAcceptance({
    required this.stage,
    required this.ioRoots,
    required this.actualOutputPath,
    required this.artifact,
    required this.driverBinarySha256,
    required this.driverSourceManifestSha256,
    required this.receiptSha256,
    required this.actualOutputBytesAndResolvedPathAccepted,
  });
  final Pw38Stage stage;
  final Pw38IoRoots ioRoots;
  final String actualOutputPath,
      driverBinarySha256,
      driverSourceManifestSha256,
      receiptSha256;
  final Pw38Artifact artifact;
  final bool actualOutputBytesAndResolvedPathAccepted;
  void bind(
    Pw38StageDriver driver,
    Pw38DownstreamContract contract,
    Pw38Artifact expected,
  ) {
    if (!ioRoots.same(contract.ioRoots) ||
        actualOutputPath !=
            '${contract.ioRoots.downstreamOutputRoot}/${expected.path}' ||
        !actualOutputBytesAndResolvedPathAccepted) {
      throw Pw38IoBindingError(
        'Checked output is outside bound actual driver/output roots',
      );
    }
    if (stage != driver.stage ||
        !_sameArtifact(artifact, expected) ||
        driverBinarySha256 != driver.binarySha256 ||
        driverSourceManifestSha256 != driver.sourceManifestSha256 ||
        !_hash(receiptSha256)) {
      throw StateError(
        'Output acceptance artifact/driver/source/binary mismatch',
      );
    }
  }
}

abstract interface class Pw38DownstreamArtifactGate
    implements Pw38ArtifactGate, Pw38IoBound {
  Future<Pw38OutputAcceptance> verifyBoundOutput(
    Pw38StageDriver driver,
    Pw38DownstreamContract contract,
    Pw38Artifact artifact,
  );
}

abstract interface class Pw38DownstreamJournal implements Pw38IoBound {
  Future<void> started(
    Pw38ImportedUpstream upstream,
    Pw38DownstreamContract contract,
    Pw38UpstreamAcceptance acceptance,
  );
  Future<void> stageStarted(Pw38Stage stage);
  Future<void> stageFinished(Pw38StageReceipt receipt);
  Future<void> stopped(String reason, int exitCode);
  Future<void> completed(List<Pw38StageReceipt> receipts);
}

final class Pw38DownstreamResult {
  Pw38DownstreamResult._({
    required this.exitCode,
    required this.stoppedReason,
    required this.upstreamAcceptance,
    required List<Pw38StageReceipt> receipts,
  }) : receipts = List.unmodifiable(receipts);
  factory Pw38DownstreamResult.blocked(String reason) => Pw38DownstreamResult._(
    exitCode: 38,
    stoppedReason: reason,
    upstreamAcceptance: null,
    receipts: [],
  );
  final int exitCode;
  final String? stoppedReason;
  final Pw38UpstreamAcceptance? upstreamAcceptance;
  final List<Pw38StageReceipt> receipts;
  // Cleanup permission includes durable OUTPUT ownership and actual IO gates.
  bool get durableIoAccepted => upstreamAcceptance != null;
  bool get durableInputsAccepted => durableIoAccepted;
  bool get full38Complete =>
      durableIoAccepted &&
      exitCode == 0 &&
      stoppedReason == null &&
      receipts.length == pw38DownstreamStages.length &&
      receipts.every(
        (r) => r.entryReturnCode == 0 && r.outputGatePassed && r.error == null,
      );
}

/// A downstream-only entry. It never calls the full13-stage runner and never
/// constructs upstream no-op drivers. Existing native C/C++ stage drivers are
/// invoked once each, starting TSDF, after all async capability/IO gates pass.
final class Pw38ImportedDownstream {
  Pw38ImportedDownstream({
    required Map<Pw38Stage, Pw38StageDriver> drivers,
    required this.upstreamAcceptor,
    required this.capabilities,
    required this.artifacts,
    required this.journal,
  }) : _drivers = Map.unmodifiable(drivers);
  final Map<Pw38Stage, Pw38StageDriver> _drivers;
  final Pw38DurableUpstreamAcceptor upstreamAcceptor;
  final Pw38NativeCapabilityGate capabilities;
  final Pw38ArtifactGate artifacts;
  final Pw38DownstreamJournal journal;
  bool _running = false;

  void _assertIoBindings(Pw38DownstreamContract contract) {
    for (final object in <Object>[
      upstreamAcceptor,
      capabilities,
      artifacts,
      journal,
      ..._drivers.values,
    ]) {
      if (object is! Pw38IoBound || !object.ioRoots.same(contract.ioRoots)) {
        throw Pw38IoBindingError(
          'Unbound or mismatched real driver/validator/journal IO roots',
        );
      }
    }
    if (artifacts is! Pw38DownstreamArtifactGate) {
      throw Pw38IoBindingError(
        'Actual artifact gate lacks bound output acceptance',
      );
    }
  }

  void _validateContract(
    Pw38ImportedUpstream upstream,
    Pw38RunContract contract,
  ) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(contract.runId) ||
        contract.orderedFrames != upstream.orderedFrames.length || contract.denseProducerProfile != upstream.denseProducerProfile ||
        contract.sourceInputManifestSha256 != pw38SourceInputManifestSha256 ||
        contract.orderedInputManifestSha256 !=
            upstream.orderedInputManifestSha256 ||
        contract.modelManifestSha256 != upstream.modelManifestSha256 ||
        contract.environmentManifestSha256 !=
            upstream.environmentManifestSha256 ||
        !contract.sourceGates.accepted ||
        contract.outputs.length != 9 ||
        contract.outputs.keys.any((s) => !pw38DownstreamStages.contains(s))) {
      throw StateError(
        'Selected38 downstream contract/source/input/model/environment mismatch',
      );
    }
    final expected = upstream.artifacts;
    if (contract.inputs.length != expected.length)
      throw StateError('Complete imported manifest must be reused');
    for (var i = 0; i < expected.length; i++) {
      final a = expected[i], b = contract.inputs[i];
      if (a.path != b.path ||
          a.role != b.role ||
          a.bytes != b.bytes ||
          a.sha256 != b.sha256) {
        throw StateError('Imported artifact manifest identity/order changed');
      }
    }
    final paths = <String>{};
    for (final stage in pw38DownstreamStages) {
      final outputs = contract.outputs[stage];
      if (outputs == null ||
          outputs.isEmpty ||
          !outputs
              .map((a) => a.role)
              .toSet()
              .containsAll(pw38RequiredOutputRoles[stage]!)) {
        throw StateError('${stage.name} downstream outputs unregistered');
      }
      for (final output in outputs) {
        if (!paths.add(output.path))
          throw StateError('Downstream output path reused');
      }
    }
  }

  Future<Pw38DownstreamResult> run({
    required Pw38ImportedUpstream upstream,
    required Pw38DownstreamContract boundContract,
    required List<String> cleanupRoots,
  }) async {
    if (_running)
      return Pw38DownstreamResult.blocked('Downstream run already active');
    _running = true;
    final ownedCleanupRoots = List<String>.unmodifiable(cleanupRoots);
    final contract = boundContract.value;
    Pw38UpstreamAcceptance? acceptance;
    var journalStarted = false;
    final receipts = <Pw38StageReceipt>[];
    final nativeAcceptances = <Pw38Stage, Pw38NativeIoAcceptance>{};
    Future<Pw38DownstreamResult> stop(String reason, int code) async {
      var completeReason = reason;
      try {
        _assertIoBindings(boundContract);
      } catch (_) {
        acceptance = null;
      }
      if (journalStarted) {
        try {
          await journal.stopped(reason, code);
        } catch (e) {
          completeReason = '$reason; durable failure receipt write failed: $e';
        } finally {
          try {
            _assertIoBindings(boundContract);
          } catch (_) {
            acceptance = null;
          }
        }
      }
      return Pw38DownstreamResult._(
        exitCode: code,
        stoppedReason: completeReason,
        upstreamAcceptance: acceptance,
        receipts: receipts,
      );
    }

    try {
      if (_drivers.keys.any((s) => !pw38DownstreamStages.contains(s))) {
        throw StateError(
          'Upstream drivers are forbidden in imported downstream route',
        );
      }
      final missing = pw38DownstreamStages
          .where((s) => !_drivers.containsKey(s))
          .toList();
      if (missing.isNotEmpty)
        throw UnsupportedError(
          'Missing downstream native drivers: ${missing.map((s) => s.name).join(',')}',
        );
      boundContract.ioRoots.validate(ownedCleanupRoots);
      if (boundContract.ioRoots.durableInputRoot != upstream.durableInputRoot ||
          boundContract.ioRoots.textureSceneRoot != upstream.textureSceneRoot) {
        throw Pw38IoBindingError('Contract/input scene roots differ');
      }
      _assertIoBindings(boundContract);
      upstream.validate(ownedCleanupRoots);
      _validateContract(upstream, contract);
      for (final stage in pw38DownstreamStages) {
        final driver = _drivers[stage]!;
        if (driver.stage != stage ||
            driver.sourceManifestSha256 != contract.sourceInputManifestSha256 ||
            !_hash(driver.binarySha256) ||
            driver.verifiedCAbiSymbols.isEmpty) {
          throw StateError(
            '${stage.name} native C ABI/source/binary identity unresolved',
          );
        }
        final nativeIo = await capabilities.requireAccepted(
          driver,
          boundContract,
          artifacts as Pw38DownstreamArtifactGate,
          ownedCleanupRoots,
        );
        _assertIoBindings(boundContract);
        nativeIo.bind(driver, boundContract, ownedCleanupRoots);
        nativeAcceptances[stage] = nativeIo;
      }
      final accepted = await upstreamAcceptor.accept(
        upstream,
        boundContract,
        ownedCleanupRoots,
      );
      _assertIoBindings(boundContract);
      accepted.bind(upstream, boundContract, ownedCleanupRoots);
      // Assign only after all acceptance fields bind; an invalid object must
      // never authorize archived-launcher scratch cleanup.
      await artifacts.validateInputs(contract);
      _assertIoBindings(boundContract);
      acceptance = accepted;
      await artifacts.requireFreshOutputs(contract);
      _assertIoBindings(boundContract);
      await journal.started(upstream, boundContract, accepted);
      journalStarted = true;
      for (final stage in pw38DownstreamStages) {
        final watch = Stopwatch()..start();
        int? rc;
        try {
          await journal.stageStarted(stage);
          _assertIoBindings(boundContract);
          nativeAcceptances[stage]!.bind(
            _drivers[stage]!,
            boundContract,
            ownedCleanupRoots,
          );
          rc = await _drivers[stage]!.run(contract);
          nativeAcceptances[stage]!.bind(
            _drivers[stage]!,
            boundContract,
            ownedCleanupRoots,
          );
          _assertIoBindings(boundContract);
          if (rc != 0) {
            final row = Pw38StageReceipt(
              stage,
              rc,
              false,
              watch.elapsedMicroseconds,
              'Native stage returned nonzero',
            );
            receipts.add(row);
            await journal.stageFinished(row);
            return await stop('${stage.name} returned $rc', rc);
          }
          for (final output in contract.outputs[stage]!) {
            final checked = await (artifacts as Pw38DownstreamArtifactGate)
                .verifyBoundOutput(_drivers[stage]!, boundContract, output);
            _assertIoBindings(boundContract);
            checked.bind(_drivers[stage]!, boundContract, output);
          }
          final row = Pw38StageReceipt(
            stage,
            rc,
            true,
            watch.elapsedMicroseconds,
          );
          receipts.add(row);
          await journal.stageFinished(row);
        } catch (e) {
          if (e is Pw38IoBindingError) acceptance = null;
          if (receipts.isEmpty || receipts.last.stage != stage) {
            final row = Pw38StageReceipt(
              stage,
              rc,
              false,
              watch.elapsedMicroseconds,
              e.toString(),
            );
            receipts.add(row);
            try {
              await journal.stageFinished(row);
            } catch (_) {
              /* stop records the failure */
            }
          }
          return await stop(e.toString(), 38);
        } finally {
          watch.stop();
        }
      }
      _assertIoBindings(boundContract);
      await journal.completed(List.unmodifiable(receipts));
      _assertIoBindings(boundContract);
      return Pw38DownstreamResult._(
        exitCode: 0,
        stoppedReason: null,
        upstreamAcceptance: acceptance,
        receipts: receipts,
      );
    } catch (e) {
      if (e is Pw38IoBindingError) acceptance = null;
      return await stop(e.toString(), 38);
    } finally {
      _running = false;
    }
  }
}

/// Actual production launcher IO boundary. No caller may fabricate retained
/// depth from this PLY/scratch request. The manifest provider must discover an
/// existing native producer's complete, immutable, accepted retention manifest.
final class Pw38NativeDenseHandoff {
  Pw38NativeDenseHandoff({
    required this.captureDir,
    required this.densePlyPath,
    required this.denseWorkDir,
    required this.materializedImageCacheDir,
  }) {
    for (final path in [
      captureDir,
      densePlyPath,
      denseWorkDir,
      materializedImageCacheDir,
    ]) {
      _root(path);
    }
  }
  final String captureDir,
      densePlyPath,
      denseWorkDir,
      materializedImageCacheDir;
  List<String> get cleanupRoots => [denseWorkDir, materializedImageCacheDir];
}

typedef Pw38DownstreamHook = Future<Pw38DownstreamResult> Function(
  Pw38NativeDenseHandoff request,
);

abstract interface class Pw38ExistingRetentionManifestProvider {
  Future<Pw38ImportedUpstream?> findExisting(Pw38NativeDenseHandoff request);
}

typedef Pw38DownstreamContractFactory = Future<Pw38DownstreamContract> Function(
  Pw38ImportedUpstream upstream,
);

final class Pw38ProductionDownstreamLink {
  Pw38ProductionDownstreamLink({
    required this.existingManifest,
    required this.downstreamContract,
    required this.controller,
  });
  final Pw38ExistingRetentionManifestProvider existingManifest;
  final Pw38DownstreamContractFactory downstreamContract;
  final Pw38ImportedDownstream controller;
  Future<Pw38DownstreamResult> call(Pw38NativeDenseHandoff request) async {
    try {
      final upstream = await existingManifest.findExisting(request);
      if (upstream == null)
        return Pw38DownstreamResult.blocked(
          'Actual complete native retention manifest unavailable; do not rerun or synthesize upstream',
        );
      if (upstream.sourceCaptureDir != request.captureDir ||
          upstream.sourceDensePlyPath != request.densePlyPath) {
        return Pw38DownstreamResult.blocked(
          'Retention manifest belongs to another production capture/dense PLY',
        );
      }
      final contract = await downstreamContract(upstream);
      return await controller.run(
        upstream: upstream,
        boundContract: contract,
        cleanupRoots: request.cleanupRoots,
      );
    } catch (e) {
      return Pw38DownstreamResult.blocked(e.toString());
    }
  }
}
