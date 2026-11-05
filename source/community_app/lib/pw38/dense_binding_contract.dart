import 'frame_transport.dart';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'native_downstream.dart';
import 'request.dart';
import 'reconstruction_request.dart' show validateOriginalFusionJpegs;
import 'original_retention_io.dart';
import 'vendor/dart_pipeline/lib/pw38_pipeline.dart';
import 'vendor/dart_texture_integration_v1/lib/pw38_texture_ffi.dart' show pw38TextureAbsolutePath;

const pwFull38DenseHeaderSha256='ad7e203ec0629e1cbccee623e0eb5bf8dd5a2964ee9917d6fbbd7174b5283ea8';
const pwOriginalRetainedDenseHeaderSha256='9e649c29eb414cf6c3788da1b83281a005c8a84c7cc61268911c92c7bb9fbe3b';
int requiredDenseAbiVersion(Map<String, dynamic> request) =>
    usesOriginalRetained97(request) ? 2 : 1;
String requiredDenseHeaderSha256(Map<String, dynamic> request) =>
    usesOriginalRetained97(request)
        ? pwOriginalRetainedDenseHeaderSha256 : pwFull38DenseHeaderSha256;

final class DenseFrame extends Struct {
  @Double() external double frameId;
  @Double() external double fx;
  @Double() external double fy;
  @Double() external double cx;
  @Double() external double cy;
  @Double() external double imageW;
  @Double() external double imageH;
  @Array(4) external Array<Double> q;
  @Array(3) external Array<Double> t;
  external Pointer<Char> jpeg;
}
final class DenseOptions extends Struct {
  @Uint32() external int abiVersion;
  @Uint32() external int structSize;
  @Int32() external int width;
  @Int32() external int height;
  @Int32() external int nsrc;
  @Int32() external int webgpu;
  @Int32() external int geoMask;
  @Int32() external int allViews;
  @Int32() external int photoFirst;
  @Float() external double geoPixel;
  @Float() external double geoDepth;
  @Array(3) external Array<Float> photo;
  @Float() external double sat;
  @Float() external double angle;
  external Pointer<Char> lowModel;
  external Pointer<Char> highModel;
  external Pointer<Char> lowNoise;
  external Pointer<Char> highNoise;
  external Pointer<Char> work;
  external Pointer<Char> outPly;
  external Pointer<Char> fusedDepth;
  external Pointer<Float> cameras;
  external Pointer<Int32> neighbors;
  @Uint64() external int camerasCount;
  @Uint64() external int neighborsCount;
  external Pointer<Pointer<Char>> originalFusionJpegs;
  @Uint64() external int originalFusionJpegCount;
}
final class DenseResult extends Struct {
  @Int32() external int status;
  @Int32() external int frames;
  @Int32() external int inferred;
  @Int32() external int fusedFrames;
  @Uint64() external int points;
  @Double() external double lowMs;
  @Double() external double highMs;
  @Double() external double mergeMs;
  @Double() external double fuseMs;
  @Array(512) external Array<Char> error;
  @Array(4096) external Array<Char> outPly;
  @Array(4096) external Array<Char> fusedDepth;
  @Array(4096) external Array<Char> order;
  @Array(4096) external Array<Char> work;
}
typedef ProfileN=Pointer<Char> Function();
typedef ProfileD=Pointer<Char> Function();
typedef VersionN=Int32 Function();
typedef VersionD=int Function();
typedef InitN=Int32 Function(Pointer<DenseOptions>);
typedef InitD=int Function(Pointer<DenseOptions>);
typedef ProgressN=Int32 Function(Pointer<Char>,Int32,Int32,Pointer<Void>);
typedef ChunkN=Int32 Function(Int32,Pointer<Float>,Pointer<Uint8>,Int32,Pointer<Void>);
typedef RunN=Int32 Function(Pointer<DenseFrame>,Int32,Pointer<Float>,Int32,
  Pointer<DenseOptions>,Pointer<NativeFunction<ProgressN>>,Pointer<NativeFunction<ChunkN>>,Pointer<Void>,Pointer<DenseResult>);
typedef RunD=int Function(Pointer<DenseFrame>,int,Pointer<Float>,int,
  Pointer<DenseOptions>,Pointer<NativeFunction<ProgressN>>,Pointer<NativeFunction<ChunkN>>,Pointer<Void>,Pointer<DenseResult>);

final class DenseNativeReceipt {
  DenseNativeReceipt(this.returnCode,this.nativeResult,this.phaseMilliseconds);
  final int returnCode;
  final Map<String,Object?> nativeResult;
  final Map<Pw38Stage,double> phaseMilliseconds;
}
abstract interface class Pw38DenseMainline {
  String get headerSha256;
  String get binarySha256;
  List<String> get actualDefinedSymbols;
  Future<DenseNativeReceipt> run(Pw38RequestTransport request, {void Function(String,int,int)? onProgress});
}

/// One actual native call includes the four existing dense phases. There are no
/// synthetic no-op stage drivers and no Dart callbacks from foreign threads.
final class RootBoundDense implements Pw38DenseMainline {
  RootBoundDense(this.slot,this.bundleRoot,{this.originalCacheOnly=false});
  final bool originalCacheOnly;
  final NativeSlot slot;
  final String bundleRoot;
  @override String get headerSha256=>originalCacheOnly ? pwOriginalRetainedDenseHeaderSha256 : pwFull38DenseHeaderSha256;
  @override String get binarySha256=>slot.binarySha256;
  @override List<String> get actualDefinedSymbols=>slot.symbols.toList();
  @override Future<DenseNativeReceipt> run(Pw38RequestTransport request, {void Function(String,int,int)? onProgress}) async {
    final j=object(request.json['dense_inputs']);
    final root=string(j,'input_root');pw38TextureAbsolutePath(root);
    final rows=(j['frames'] as List).map(object).toList();
    final count=frameTransportCount(request.json);
    if(rows.length!=count){throw StateError('Dense requires exact97 real frames');}
    final inputs=(j['artifacts'] as List).map(artifact).toList();
    final lookup=<String,Pw38Artifact>{for(final a in inputs)a.path:a};
    for(final a in inputs){
      final f=File('$root/${a.path}');
      if(await f.length()!=a.bytes || await hashFile(f)!=a.sha256){throw StateError('Dense immutable input changed: ${a.path}');}
    }
    final memory=DownstreamNative(request,bundleRoot).memory;final arena=Arena(memory);
    try {
      final l=slot.library;
      if(usesOriginalRetained97(request.json)!=originalCacheOnly ||
          l.lookupFunction<VersionN,VersionD>('pw_full38_dense_abi_version')()!=requiredDenseAbiVersion(request.json)) {
        throw StateError('Dense profile/ABI version mismatch');
      }
      if(originalCacheOnly) {
        final ptr=l.lookupFunction<ProfileN,ProfileD>('pw_full38_dense_producer_profile')();
        if(ptr==nullptr) throw StateError('Original producer profile absent');
        final bytes=<int>[];var terminated=false;
        for(var i=0;i<128;i++) {final v=(ptr+i).value & 255;if(v==0){terminated=true;break;}bytes.add(v);}
        if(!terminated || utf8.decode(bytes)!=request.json['dense_producer_profile']) throw StateError('Actual original producer profile mismatch');
      }
      final options=arena.bytes(sizeOf<DenseOptions>()).cast<DenseOptions>();
      final init=l.lookupFunction<InitN,InitD>('pw_full38_dense_options_init')(options);
      if(init!=0){throw StateError('Dense native selected-options initialization failed $init');}
      // Every selected arithmetic parameter comes from unchanged native init.
      final p=object(request.paths['fusionPly']);
      options.ref.lowModel=arena.path('$bundleRoot/dense_models/casdiffmvs_ep0_768.onnx');
      options.ref.highModel=arena.path('$bundleRoot/dense_models/casdiffmvs_ep0_1536.onnx');
      for(final model in [('casdiffmvs_ep0_768.onnx','cc32cee17f7ede31dc957d0a860fea54e4b21ad5d8ba125336238829aa13faba'),
        ('casdiffmvs_ep0_1536.onnx','18533085f03602aec66b0fcd36e985c398a85025549c364cb679d05a735705b9')]){
        if(await hashFile(File('$bundleRoot/dense_models/${model.$1}'))!=model.$2){throw StateError('Dense selected model bytes mismatch');}
      }
      options.ref.lowNoise=arena.path('$root/${checkedRelativePath(string(j,'low_noise_f32'))}');
      options.ref.highNoise=arena.path('$root/${checkedRelativePath(string(j,'high_noise_f32'))}');
      if(lookup[string(j,'low_noise_f32')]?.bytes!=lowNoiseBytes(count) ||
         lookup[string(j,'high_noise_f32')]?.bytes!=highNoiseBytes(count)){throw StateError('Exact original97 sorted noise file manifest missing');}
      options.ref.work=arena.path('${request.ioRoots.downstreamOutputRoot}/${checkedRelativePath(string(p,'work_dir'))}');
      options.ref.outPly=originalCacheOnly ? nullptr : arena.path('${request.ioRoots.downstreamOutputRoot}/${checkedRelativePath(string(p,'out_ply'))}');
      if(originalCacheOnly) {
        if(p['out_ply']!='' || options.ref.abiVersion!=2 || options.ref.structSize!=sizeOf<DenseOptions>()) {
          throw StateError('Original retained-only options layout/outPly mismatch');
        }
        final fusionRows=validateOriginalFusionJpegs(j,lookup,profile:request.json['dense_producer_profile'] as String);
        final pointers=arena.bytes(count*sizeOf<Pointer<Char>>()).cast<Pointer<Char>>();
        for(var i=0;i<count;i++) {pointers[i]=arena.path('$root/${artifact(fusionRows[i]['artifact']).path}');}
        options.ref.originalFusionJpegs=pointers;options.ref.originalFusionJpegCount=count;
        if(j['cameras_f32']==null || j['neighbors_i32']==null) throw StateError('Frozen original camera/neighbor tables required');
      }
      options.ref.fusedDepth=arena.path('${request.ioRoots.downstreamOutputRoot}/${checkedRelativePath(string(p,'fused_depth_dir'))}');
      final frames=arena.bytes(count*sizeOf<DenseFrame>()).cast<DenseFrame>();
      for(var i=0;i<count;i++){
        final row=rows[i],f=(frames+i).ref;
        // JSON numbers are frozen binary64 transport, with original frame bit gate.
        f.frameId=(row['frame_id'] as num).toDouble();
        final bits=ByteData(8)..setFloat64(0,f.frameId,Endian.big);
        final identity=bits.getUint64(0,Endian.big).toRadixString(16).padLeft(16,'0');
        if(identity!=request.frames[i].frameIdF64Bits){throw StateError('Dense original retained frame order changed');}
        f.fx=(row['fx'] as num).toDouble();f.fy=(row['fy'] as num).toDouble();
        f.cx=(row['cx'] as num).toDouble();f.cy=(row['cy'] as num).toDouble();
        f.imageW=(row['image_w'] as num).toDouble();f.imageH=(row['image_h'] as num).toDouble();
        final q=(row['q_wxyz'] as List).cast<num>(),t=(row['t'] as List).cast<num>();
        if(q.length!=4 || t.length!=3){throw StateError('Dense real pose arity mismatch');}
        for(var n=0;n<4;n++){f.q[n]=q[n].toDouble();}for(var n=0;n<3;n++){f.t[n]=t[n].toDouble();}
        final jpeg=checkedRelativePath(string(row,'jpeg_path'));
        if(!lookup.containsKey(jpeg)){throw StateError('Actual JPEG absent from immutable input manifest');}
        f.jpeg=arena.path('$root/$jpeg');
      }
      Pointer<Uint8> load(String name,int bytes,List<int> content){
        if(content.length!=bytes || lookup[name]?.bytes!=bytes){throw StateError('Native input size mismatch: $name');}
        final p=arena.bytes(bytes);p.asTypedList(bytes).setAll(0,content);return p;
      }
      final sparseName=checkedRelativePath(string(j,'sparse_xyz_f32'));
      final sparseBytes=await File('$root/$sparseName').readAsBytes();
      if(sparseBytes.length%12!=0){throw StateError('Sparse xyz f32 triples required');}
      final sparse=load(sparseName,sparseBytes.length,sparseBytes).cast<Float>();
      if(j['cameras_f32']!=null || j['neighbors_i32']!=null){
        final cameraName=checkedRelativePath(string(j,'cameras_f32'));
        final neighborName=checkedRelativePath(string(j,'neighbors_i32'));
        options.ref.cameras=load(cameraName,count*36*4,await File('$root/$cameraName').readAsBytes()).cast<Float>();
        options.ref.neighbors=load(neighborName,count*9*4,await File('$root/$neighborName').readAsBytes()).cast<Int32>();
        options.ref.camerasCount=count*36;options.ref.neighborsCount=count*9;
      }
      final result=arena.bytes(sizeOf<DenseResult>()).cast<DenseResult>();
      final callbackErrors = <String>[];
      NativeCallable<ProgressN>? progress;
      if(onProgress!=null) {
        progress=NativeCallable<ProgressN>.isolateLocal((Pointer<Char> phase,int done,int total,Pointer<Void> user) {
          try {
            if(phase==nullptr) throw StateError('Native progress phase absent');
            final bytes=<int>[];var terminated=false;
            for(var i=0;i<512;i++) { final value=(phase+i).value & 255; if(value==0){terminated=true;break;} bytes.add(value); }
            if(!terminated) throw StateError('Unterminated native progress phase');
            onProgress(utf8.decode(bytes),done,total);
          } catch(error) {
            callbackErrors.add(error.toString());
            stderr.writeln('PW38_DENSE_PROGRESS_ERROR: $error');
          }
          return 0; // Observation only; no cancellation or native parameter changes.
        },exceptionalReturn:0);
      }
      late final int rc;
      try {
        rc=l.lookupFunction<RunN,RunD>('pw_full38_dense_run')(frames,count,sparse,sparseBytes.length~/12,
          options,progress?.nativeFunction ?? nullptr,nullptr,nullptr,result);
      } finally { progress?.close(); }
      final r=result.ref;
      String text(Array<Char> chars){final bytes=chars.elements.map((value)=>value & 255).toList(growable:false);final end=bytes.indexOf(0);
        if(end<0){throw StateError('Dense result text unterminated');}return utf8.decode(bytes.sublist(0,end));}
      return DenseNativeReceipt(rc,{'native_entry':'pw_full38_dense_run','status':r.status,'frames':r.frames,
        'inferred':r.inferred,'fused_frames':r.fusedFrames,'points':r.points,'error':text(r.error),
        'out_ply':text(r.outPly),'fused_depth_dir':text(r.fusedDepth),'order_json':text(r.order),
        'work_dir':text(r.work),'dense_producer_profile': originalCacheOnly ? request.json['dense_producer_profile'] : 'legacy_native_retained_ply','callbacks':onProgress==null ? 'NULL/NULL' : 'same_calling_thread_progress/NULL_chunk',
        'progress_callback_errors':callbackErrors},
        {Pw38Stage.mvs768:r.lowMs,Pw38Stage.mvs1536:r.highMs,Pw38Stage.cer:r.mergeMs,Pw38Stage.fusionPly:r.fuseMs});
    }finally{arena.dispose();}
  }
}
Future<Pw38DenseMainline> openRootBoundDense(Pw38RequestTransport request,String bundleRoot) async {
  if(await hashFile(File('$bundleRoot/Frameworks/libonnxruntime.1.dylib'))!='cd0d290e395f82cf2e1571f8c163af688d950c7cee8f0152d787f889b7dc4749'){throw StateError('Recovered original paired ORT bytes required');}
  final row=object(request.native['dense']);
  final original=usesOriginalRetained97(request.json);
  if(row['header_sha256']!=requiredDenseHeaderSha256(request.json)){throw StateError('Final frozen dense ABI header mismatch');}
  final slot=await NativeSlot.open(row,bundleRoot,{'pw_full38_dense_abi_version','pw_full38_dense_options_init','pw_full38_dense_run',
    if(original) 'pw_full38_dense_producer_profile'});
  return RootBoundDense(slot,bundleRoot,originalCacheOnly:original);
}
