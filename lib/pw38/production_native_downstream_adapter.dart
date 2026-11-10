import 'native_downstream.dart';
import 'request.dart';
import 'vendor/production_downstream_bridge_v3/lib/pw38_downstream.dart';

/// Transport the actual imported retention without requiring new fusion output
/// tuples. Existing declarations are validated and reused; this grants no
/// asynchronous durable-input, format or native-capability acceptance.
final class ProductionImportedDownstreamRequest implements Pw38RequestTransport {
  ProductionImportedDownstreamRequest(this.request)
      : _frames = List.unmodifiable(request.frames) {
    final upstream = request.upstream;
    if (ioRoots.durableInputRoot != upstream.durableInputRoot ||
        ioRoots.textureSceneRoot != upstream.textureSceneRoot) {
      throw Pw38IoBindingError('Imported request/upstream roots differ');
    }
    ioRoots.validate(request.cleanupRoots);
    upstream.validate(request.cleanupRoots);
    if (request.contract.orderedFrames != _frames.length ||
        upstream.orderedFrames.length != _frames.length || _frames.isEmpty) {
      throw StateError('Imported request requires exact original97 frames');
    }
    for (var index = 0; index < _frames.length; index++) {
      final actual = _frames[index], retained = upstream.orderedFrames[index];
      if (actual.frameIdF64Bits != retained.frameIdF64Bits ||
          actual.width != retained.width || actual.height != retained.height ||
          actual.width != 1536 || actual.height != 1152 ||
          actual.originalCameraPath != retained.original4032Camera.path) {
        throw StateError('Imported transport frame $index identity differs');
      }
    }
  }

  final MainlineRequest request;
  final List<RequestFrame> _frames;
  Pw38ImportedUpstream get upstream => request.upstream;
  @override
  Map<String, dynamic> get json => request.json;
  @override
  Map<String, dynamic> get paths => request.paths;
  @override
  Map<String, dynamic> get native => request.native;
  @override
  Pw38IoRoots get ioRoots => request.ioRoots;
  @override
  String get runId => request.runId;
  @override
  List<RequestFrame> get frames => _frames;
  @override
  List<String> outputPaths(Pw38Stage stage, String role) =>
      request.outputPaths(stage, role);
  @override
  String retainedOutputPath(int index, String key) {
    if (index < 0 || index >= _frames.length) {
      throw RangeError.index(index, upstream.orderedFrames, 'index');
    }
    final retained = upstream.orderedFrames[index];
    switch (key) {
      case 'd16': return retained.d16.path;
      case 'camera_f64': return retained.cameraF64.path;
      default: throw ArgumentError.value(key, 'key', 'Expected d16 or camera_f64');
    }
  }
}

/// IO ownership attached to the real, source-checked native driver. This adds
/// no native capability, retention or output acceptance: vendor gates still
/// verify those independently before and after the delegated call.
final class ProductionNativeDownstreamDriver
    implements Pw38StageDriver, Pw38IoBound {
  ProductionNativeDownstreamDriver._(this.native, this.ioRoots);

  final NativeDriver native;
  @override
  final Pw38IoRoots ioRoots;
  NativeSlot get slot => native.slot;
  @override
  Pw38Stage get stage => native.stage;
  @override
  String get sourceManifestSha256 => native.sourceManifestSha256;
  @override
  String get binarySha256 => native.binarySha256;
  @override
  List<String> get verifiedCAbiSymbols => native.verifiedCAbiSymbols;
  @override
  Future<int> run(Pw38RunContract contract) => native.run(contract);
}

/// Bind the existing nine native stages for Pw38ImportedDownstream. The request
/// transport must resolve retainedOutputPath to imported D16/camera relative
/// paths; no newly generated fusion outputs are required by this adapter.
final class ProductionNativeDownstreamAdapter implements Pw38IoBound {
  ProductionNativeDownstreamAdapter._(this.native, this.drivers);

  final DownstreamNative native;
  final Map<Pw38Stage, ProductionNativeDownstreamDriver> drivers;
  @override
  Pw38IoRoots get ioRoots => native.request.ioRoots;
  List<Map<String, Object?>> get calls => native.calls;

  static Future<ProductionNativeDownstreamAdapter> bindImported({
    required MainlineRequest request,
    required String bundleRoot,
    List<Map<String, Object?>>? calls,
  }) => bind(request: ProductionImportedDownstreamRequest(request),
      bundleRoot: bundleRoot, calls: calls);

  static Future<ProductionNativeDownstreamAdapter> bind({
    required Pw38RequestTransport request,
    required String bundleRoot,
    List<Map<String, Object?>>? calls,
  }) async {
    final native = DownstreamNative(request, bundleRoot,
        calls: calls, retainedFramesFromInput: true);
    await native.bind(stages: pw38DownstreamStages);
    final drivers = <Pw38Stage, ProductionNativeDownstreamDriver>{};
    for (final stage in pw38DownstreamStages) {
      final driver = native.drivers[stage];
      if (driver is! NativeDriver || driver.stage != stage) {
        throw UnsupportedError(
            '${stage.name}: ${native.missing[stage] ?? "Imported native binding unavailable"}');
      }
      drivers[stage] = ProductionNativeDownstreamDriver._(driver, request.ioRoots);
    }
    return ProductionNativeDownstreamAdapter._(native, Map.unmodifiable(drivers));
  }
}
