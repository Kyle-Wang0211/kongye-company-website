import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'request.dart';
import 'original_retention_io.dart';
import 'vendor/dart_pipeline/lib/pw38_pipeline.dart';
import 'vendor/dart_pipeline/lib/pw38_geometry_ffi.dart';
import 'vendor/dart_texture_integration_v1/lib/pw38_texture_ffi.dart';

final class TsdfFrame extends Struct {
  @UintPtr() external int width;
  @UintPtr() external int height;
  @Array(9) external Array<Double> intrinsics;
  @Array(16) external Array<Double> extrinsics;
}
final class NormalFrame extends Struct {
  external Pointer<Char> d16;
  @Uint32() external int width;
  @Uint32() external int height;
  @Array(9) external Array<Double> intrinsics;
  @Array(16) external Array<Double> extrinsics;
  external Pointer<Char> originalCamera;
}
typedef CreateN = Int32 Function(Pointer<Pointer<Void>>);
typedef CreateD = int Function(Pointer<Pointer<Void>>);
typedef DestroyN = Void Function(Pointer<Void>);
typedef DestroyD = void Function(Pointer<Void>);
typedef IntegrateN = Int32 Function(Pointer<Void>,Pointer<Char>,Pointer<TsdfFrame>,Pointer<UintPtr>);
typedef IntegrateD = int Function(Pointer<Void>,Pointer<Char>,Pointer<TsdfFrame>,Pointer<UintPtr>);
typedef OriginalIntegrateXyzN = Int32 Function(Pointer<Void>,Pointer<Double>,UintPtr,Pointer<Double>);
typedef OriginalD16N = Int32 Function(Pointer<Void>,Pointer<NativeFunction<OriginalIntegrateXyzN>>,Pointer<Uint16>,UintPtr,UintPtr,Pointer<Double>,Pointer<Double>,Pointer<UintPtr>);
typedef OriginalD16D = int Function(Pointer<Void>,Pointer<NativeFunction<OriginalIntegrateXyzN>>,Pointer<Uint16>,int,int,Pointer<Double>,Pointer<Double>,Pointer<UintPtr>);
typedef ExtractN = Int32 Function(Pointer<Void>,Pointer<Pointer<Void>>);
typedef ExtractD = int Function(Pointer<Void>,Pointer<Pointer<Void>>);
typedef CountN = UintPtr Function(Pointer<Void>);
typedef CountD = int Function(Pointer<Void>);
typedef VerticesN = Pointer<Double> Function(Pointer<Void>);
typedef VerticesD = Pointer<Double> Function(Pointer<Void>);
typedef FacesN = Pointer<Int32> Function(Pointer<Void>);
typedef FacesD = Pointer<Int32> Function(Pointer<Void>);
typedef ExportN = Int32 Function(Pointer<Double>,UintPtr,Pointer<Int32>,UintPtr,Pointer<Char>,Pointer<UintPtr>);
typedef ExportD = int Function(Pointer<Double>,int,Pointer<Int32>,int,Pointer<Char>,Pointer<UintPtr>);
typedef CleanN = Int32 Function(Pointer<Char>,Pointer<Char>,Pointer<UintPtr>);
typedef CleanD = int Function(Pointer<Char>,Pointer<Char>,Pointer<UintPtr>);
typedef ReadN = Int32 Function(Pointer<Char>,Pointer<Pointer<Void>>);
typedef ReadD = int Function(Pointer<Char>,Pointer<Pointer<Void>>);
typedef HasColorsN = Int32 Function(Pointer<Void>);
typedef HasColorsD = int Function(Pointer<Void>);
typedef OriginalVisibilityN = Int32 Function(Pointer<Double>,Pointer<Double>,Uint64,Int32,Pointer<NormalFrame>,Uint32,Pointer<Char>,Pointer<Char>,Pointer<Char>);
typedef OriginalVisibilityD = int Function(Pointer<Double>,Pointer<Double>,int,int,Pointer<NormalFrame>,int,Pointer<Char>,Pointer<Char>,Pointer<Char>);
typedef PairN = Int32 Function(Pointer<Char>,Pointer<Char>);
typedef PairD = int Function(Pointer<Char>,Pointer<Char>);
typedef NormalN = Int32 Function(Pointer<Char>,Pointer<Char>,Pointer<Char>,Pointer<Char>,Pointer<Char>);
typedef NormalD = int Function(Pointer<Char>,Pointer<Char>,Pointer<Char>,Pointer<Char>,Pointer<Char>);
typedef TripleN = Int32 Function(Pointer<Char>,Pointer<Char>,Pointer<Char>);
typedef TripleD = int Function(Pointer<Char>,Pointer<Char>,Pointer<Char>);
// Exact meshio_bridge/pw38_mo_ply.h: six path pointers and four uint64 outputs.
typedef MeshoptPlyN = Int32 Function(Pointer<Char>,Pointer<Char>,Pointer<Char>,Pointer<Char>,
  Pointer<Char>,Pointer<Char>,Pointer<Uint64>,Pointer<Uint64>,Pointer<Uint64>,Pointer<Uint64>);
typedef MeshoptPlyD = int Function(Pointer<Char>,Pointer<Char>,Pointer<Char>,Pointer<Char>,
  Pointer<Char>,Pointer<Char>,Pointer<Uint64>,Pointer<Uint64>,Pointer<Uint64>,Pointer<Uint64>);


void copyF64(Array<Double> array,List<int> bytes) {
  final target=array.elements;
  if(bytes.length!=target.lengthInBytes){throw StateError("Frozen camera array byte length mismatch");}
  target.buffer.asUint8List(target.offsetInBytes,target.lengthInBytes).setAll(0,bytes);
}

final class Arena {
  Arena(this.memory);
  final Pw38NativeMemory memory;
  final owned = <Pointer<Uint8>>[];
  Pointer<Uint8> bytes(int count) {
    final p = memory.allocate(count); owned.add(p);
    p.asTypedList(count).fillRange(0,count,0); return p;
  }
  Pointer<Char> path(String path) {
    pw38TextureAbsolutePath(path);
    final data=utf8.encode(path);final p=bytes(data.length+1);
    p.asTypedList(data.length).setAll(0,data);return p.cast<Char>();
  }
  void dispose() { for(final p in owned.reversed){memory.release(p);} owned.clear(); }
}

/// Source-bound external native libraries only. Absence is a hard stage stop.
final class NativeSlot {
  NativeSlot(this.library,this.binarySha256,this.symbols,this.sourceEvidence);
  final DynamicLibrary library;
  final String binarySha256;
  final Set<String> symbols;
  final Map<String,dynamic> sourceEvidence;
  static Future<NativeSlot> open(Map<String,dynamic> row, String bundleRoot, Set<String> required) async {
    final relative=checkedRelativePath(string(row,'bundle_relative_path'));
    final file=File('$bundleRoot/$relative');
    final expected=string(row,'binary_sha256');
    if(await hashFile(file)!=expected) {throw StateError('Native library bytes changed: $relative');}
    final receipt=File('$bundleRoot/${checkedRelativePath(string(row,'source_receipt_path'))}');
    if(await hashFile(receipt)!=string(row,'source_receipt_sha256')) {
      throw StateError('Root source-bound native receipt changed: $relative');
    }
    final evidence=object(jsonDecode(await receipt.readAsString()));
    if(evidence['accepted_source_closure']!=true || evidence['binary_sha256']!=expected) {
      throw UnsupportedError('Unaccepted source closure: $relative');
    }
    final defined=(evidence['actual_defined_c_symbols'] as List).cast<String>().toSet();
    if(!defined.containsAll(required)) {throw UnsupportedError('Missing real native functions: ${required.difference(defined)}');}
    final library=DynamicLibrary.open(file.path);
    for(final symbol in required) {library.lookup<NativeFunction<Void Function()>>(symbol);}
    return NativeSlot(library,expected,defined,Map<String,dynamic>.unmodifiable(evidence));
  }
}

final class NativeDriver implements Pw38StageDriver {
  NativeDriver(this.stage,this.slot,this.symbols,this.call);
  @override final Pw38Stage stage;
  final NativeSlot slot;
  final List<String> symbols;
  final Future<int> Function() call;
  @override String get sourceManifestSha256 => pw38SourceInputManifestSha256;
  @override String get binarySha256 => slot.binarySha256;
  @override List<String> get verifiedCAbiSymbols => List.unmodifiable(symbols);
  @override Future<int> run(Pw38RunContract contract) => call();
}

final class DownstreamNative {
  DownstreamNative(this.request,this.bundleRoot, {
    List<Map<String,Object?>>? calls,
    this.retainedFramesFromInput = false,
    this.allowDiagnosticTexture = false,
  }) : calls=calls ?? [];
  /// Imported native retention lives in the immutable durable input root.
  /// Complete dense and cached routes keep their output-root default.
  final bool retainedFramesFromInput;
  /// Only an explicit dedicated test entry can use reviewed diagnostic builds.
  final bool allowDiagnosticTexture;
  final List<Map<String,Object?>> calls;
  int record(String entry,int rc,[Map<String,Object?>? details]) {
    calls.add({'native_entry':entry,'return_code':rc,...?details});return rc;
  }
  final Pw38RequestTransport request;
  final String bundleRoot;
  final memory=Pw38SystemMemory(DynamicLibrary.process());
  final drivers=<Pw38Stage,Pw38StageDriver>{};
  final missing=<Pw38Stage,String>{};
  NativeSlot? _pythonRuntime;
  String input(String relative) => '${request.ioRoots.durableInputRoot}/${checkedRelativePath(relative)}';
  String output(String relative) => '${request.ioRoots.downstreamOutputRoot}/${checkedRelativePath(relative)}';
  String path(Pw38Stage stage,String name,bool isInput) {
    final p=string(object(request.paths[stage.name]),name);
    return isInput?input(p):output(p);
  }
  Future<NativeSlot> slot(String name,Set<String> symbols) async {
    final row=request.native[name];
    if(row==null) {throw UnsupportedError('$name: no accepted iOS native library in package');}
    return NativeSlot.open(object(row),bundleRoot,symbols);
  }
  String retainedOutput(int index,String key) {
    final relative = request.retainedOutputPath(index,key);
    return retainedFramesFromInput ? input(relative) : output(relative);
  }
  Future<void> bind({Iterable<Pw38Stage>? stages}) async {
    final selected = stages?.toSet();
    if (selected != null && (selected.isEmpty ||
        selected.any((s) => !pw38StageOrder.skip(4).contains(s)))) {
      throw StateError('A nonempty downstream process segment is required');
    }
    bool needs(Pw38Stage stage) => selected == null || selected.contains(stage);
    if (needs(Pw38Stage.tsdf)) await bindTsdf();
    if (needs(Pw38Stage.trim)) await bindMeshio();
    if (needs(Pw38Stage.lagrange)) await bindGeometry();
    if (needs(Pw38Stage.meshopt)) await bindMeshoptPly();
    if (needs(Pw38Stage.texture)) await bindTexture();
    if ([Pw38Stage.avVisibility, Pw38Stage.avSfmToAbc, Pw38Stage.avNormal].any(needs)) {
      await bindNormal(includeVisibility: needs(Pw38Stage.avVisibility));
    }
    // TSDF and visibility execute their original NumPy bodies in this runtime.
    if (needs(Pw38Stage.glb) || needs(Pw38Stage.tsdf) || needs(Pw38Stage.avVisibility)) await bindGlb();
    if (needs(Pw38Stage.avVisibility) && _pythonRuntime == null) {
      missing[Pw38Stage.avVisibility]=missing[Pw38Stage.glb] ?? 'Pinned CPython runtime is unavailable';
      drivers.remove(Pw38Stage.avVisibility);
    }
  }
  Future<void> bindTsdf() async {
    const symbols={'pw38_vdb_create','pw38_vdb_destroy','pw38_vdb_integrate_xyz',
      'pw38_vdb_extract_raw','pw38_vdb_mesh_destroy','pw38_vdb_mesh_vertex_count',
      'pw38_vdb_mesh_face_count','pw38_vdb_mesh_vertices','pw38_vdb_mesh_faces'};
    try {
      final s=await slot('tsdf',symbols);final l=s.library;
      drivers[Pw38Stage.tsdf]=NativeDriver(Pw38Stage.tsdf,s,symbols.toList(),() async {
        final a=Arena(memory);Pointer<Void> volume=nullptr,mesh=nullptr;
        final destroy=l.lookupFunction<DestroyN,DestroyD>('pw38_vdb_destroy');
        final meshDestroy=l.lookupFunction<DestroyN,DestroyD>('pw38_vdb_mesh_destroy');
        try {
          final holder=a.bytes(sizeOf<Pointer<Void>>()).cast<Pointer<Void>>();
          var rc=l.lookupFunction<CreateN,CreateD>('pw38_vdb_create')(holder);
          record('pw38_vdb_create',rc);
          volume=holder.value;if(rc!=0){return rc;}
          final points=a.bytes(sizeOf<UintPtr>()).cast<UintPtr>();
          final pythonRuntime=_pythonRuntime;
          if(pythonRuntime==null){throw StateError('Pinned original TSDF NumPy runtime initialization missing');}
          final integrateXyz=l.lookup<NativeFunction<OriginalIntegrateXyzN>>('pw38_vdb_integrate_xyz');
          final integrate=pythonRuntime.library.lookupFunction<OriginalD16N,OriginalD16D>('pw38_vdb_integrate_d16_original_numpy');
          for(var index=0;index<request.frames.length;index++) {
            final retained=request.frames[index];
            final camera=await File(retainedOutput(index,'camera_f64')).readAsBytes();
            if(camera.length!=200){throw StateError('Camera f64 identity must contain25 values');}
            final perFrame=Arena(memory);
            try {
              // Byte copies only; the original NumPy span performs all backprojection.
              final cameraMemory=perFrame.bytes(200);
              cameraMemory.asTypedList(200).setAll(0,camera);
              final depthBytes=retained.width*retained.height*2;
              final depthMemory=perFrame.bytes(depthBytes);
              final depthFile=await File(retainedOutput(index,'d16')).open();
              try {
                if(await depthFile.length()!=depthBytes){throw StateError('Original d16 shape/length mismatch');}
                var done=0;
                final view=depthMemory.asTypedList(depthBytes);
                while(done<depthBytes) {
                  final got=await depthFile.readInto(view,done);
                  if(got<=0){throw StateError('Incomplete original d16 input');}
                  done+=got;
                }
              } finally {await depthFile.close();}
              rc=integrate(volume,integrateXyz,depthMemory.cast<Uint16>(),retained.width,retained.height,
                cameraMemory.cast<Double>(),(cameraMemory+72).cast<Double>(),points);
              record('pw38_vdb_integrate_d16_original_numpy',rc,{'frame_index':index});
              if(rc!=0){return rc;}
            } finally {perFrame.dispose();}
          }
          rc=l.lookupFunction<ExtractN,ExtractD>('pw38_vdb_extract_raw')(volume,holder);
          record('pw38_vdb_extract_raw',rc);
          mesh=holder.value;if(rc!=0){return rc;}
          final nv=l.lookupFunction<CountN,CountD>('pw38_vdb_mesh_vertex_count')(mesh);
          final nf=l.lookupFunction<CountN,CountD>('pw38_vdb_mesh_face_count')(mesh);
          return record('pw38_trimesh_process_export_raw',pythonRuntime.library.lookupFunction<ExportN,ExportD>('pw38_trimesh_process_export_raw')(
            l.lookupFunction<VerticesN,VerticesD>('pw38_vdb_mesh_vertices')(mesh),nv,
            l.lookupFunction<FacesN,FacesD>('pw38_vdb_mesh_faces')(mesh),nf,
            a.path(path(Pw38Stage.tsdf,'output_ply',false)),a.bytes(6*sizeOf<UintPtr>()).cast<UintPtr>()));
        } finally {if(mesh!=nullptr){meshDestroy(mesh);}if(volume!=nullptr){destroy(volume);}a.dispose();}
      });
    } catch(e) {missing[Pw38Stage.tsdf]='$e';}
  }
  Future<void> bindMeshio() async {
    try {
      final s=await slot('meshio',{'pw38_open3d_clean_ply'});
      final l=s.library;
      drivers[Pw38Stage.trim]=NativeDriver(Pw38Stage.trim,s,['pw38_open3d_clean_ply'],() async {
        final a=Arena(memory);try{return record('pw38_open3d_clean_ply',l.lookupFunction<CleanN,CleanD>('pw38_open3d_clean_ply')(
          a.path(path(Pw38Stage.trim,'input_ply',false)),a.path(path(Pw38Stage.trim,'output_ply',false)),
          a.bytes(6*sizeOf<UintPtr>()).cast<UintPtr>()));}finally{a.dispose();}
      });
    } catch(e) {missing[Pw38Stage.trim]='$e';}
  }
  Future<void> bindGeometry() async {
    try {
      final s=await slot('geometry',pw38GeometrySymbols);
      final ffi=Pw38GeometryFfi(Pw38GeometryBindings.bind(s.library,Pw38GeometryEvidence(
        // NativeSlot has already checked the actual signed library against the
        // immutable package/source receipt. The unchanged geometry evidence
        // pins the original provider before packaging/re-signing.
        headerSha256:pw38GeometryHeaderSha256,
        binarySha256:string(s.sourceEvidence,'unsigned_provider_sha256'),
        sourceInputManifestSha256:pw38SourceInputManifestSha256,actualDefinedSymbols:s.symbols)),memory);
      drivers[Pw38Stage.lagrange]=NativeDriver(Pw38Stage.lagrange,s,['pw38_lagrange_fill_ply'],() async =>
        record('pw38_lagrange_fill_ply',ffi.fillPly(inputPly:path(Pw38Stage.lagrange,'input_ply',false),
          outputPly:path(Pw38Stage.lagrange,'output_ply',false)).entryReturnCode));
    } catch(e) {missing[Pw38Stage.lagrange]='$e';}
  }
  Future<void> bindMeshoptPly() async {
    const symbol='pw38_meshopt_simplify_ply';
    try {
      final s=await slot('meshopt_ply',{symbol,'pw38_mo_ply_last_error'});
      final config=object(request.paths[Pw38Stage.meshopt.name]);
      const names=['input_ply','output_ply','positions_f32','indices_u32',
        'output_positions_f32','output_indices_u32'];
      final relative={for(final name in names)name:checkedRelativePath(string(config,name))};
      final trim=request.outputPaths(Pw38Stage.trim,'mesh_ply');
      if(trim.length!=1 || trim.single!=relative['input_ply']) {
        throw StateError('meshopt input must be this run registered trim PLY output');
      }
      for(final entry in {'mesh_ply':'output_ply','positions_f32':'output_positions_f32',
          'indices_u32':'output_indices_u32'}.entries) {
        final rows=request.outputPaths(Pw38Stage.meshopt,entry.key);
        if(rows.length!=1 || rows.single!=relative[entry.value]) {
          throw StateError('meshopt ${entry.key} output does not bind ${entry.value}');
        }
      }
      final paths={for(final entry in relative.entries)entry.key:output(entry.value)};
      if(paths.values.toSet().length!=names.length){throw StateError('meshopt six IO paths must be distinct');}
      drivers[Pw38Stage.meshopt]=NativeDriver(Pw38Stage.meshopt,s,[symbol],() async {
        // All new bridge outputs/intermediates are under this run root; no cache input.
        for(final name in names.skip(1)) {
          if(await FileSystemEntity.type(paths[name]!,followLinks:false)!=FileSystemEntityType.notFound) {
            throw StateError('Refuse meshopt raw/PLY overwrite: ${paths[name]}');
          }
        }
        final arena=Arena(memory);
        try {
          final counts=arena.bytes(4*sizeOf<Uint64>()).cast<Uint64>();
          return record(symbol,s.library.lookupFunction<MeshoptPlyN,MeshoptPlyD>(symbol)(
            arena.path(paths['input_ply']!),arena.path(paths['output_ply']!),
            arena.path(paths['positions_f32']!),arena.path(paths['indices_u32']!),
            arena.path(paths['output_positions_f32']!),arena.path(paths['output_indices_u32']!),
            counts,counts+1,counts+2,counts+3));
        }finally{arena.dispose();}
      });
    }catch(e){missing[Pw38Stage.meshopt]='$e';}
  }
  Future<void> bindTexture() async {
    try {
      final s=await slot('texture',{pw38TextureSymbol});
      // NativeSlot has verified actual signed bytes, receipt bytes and exports.
      // Keep historical, compiler-only and test-only runtime identities distinct.
      final evidence=Pw38TextureEvidence.fromSourceReceipt(
          receipt:s.sourceEvidence,
          receiptSha256:string(object(request.native['texture']),'source_receipt_sha256'),
          signedBinarySha256:s.binarySha256,
          sourceInputManifestSha256:pw38SourceInputManifestSha256,
          actualDefinedSymbols:s.symbols);
      evidence.requireExecutionScope(allowDiagnostic:allowDiagnosticTexture);
      final ffi=Pw38TextureFfi(Pw38TextureBindings.bind(s.library,evidence),memory);
      final p=object(request.paths['texture']);
      if (request is! MainlineRequest || retainedFramesFromInput) {
        drivers[Pw38Stage.texture]=NativeDriver(Pw38Stage.texture,s,[pw38TextureSymbol],() async {
          final result=ffi.run(sceneDirectory:request.ioRoots.textureSceneRoot,
              meshPly:path(Pw38Stage.texture,'input_ply',false),
              outputPrefix:path(Pw38Stage.texture,'output_prefix',false));
          record(pw38TextureSymbol,result.entryReturnCode,{'native_error':result.error,'diagnostic_issue':result.diagnosticIssue});
          if(result.entryReturnCode==0 && result.diagnosticIssue!=null){throw StateError(result.diagnosticIssue!);}
          return result.entryReturnCode;
        });
        return;
      }
      drivers[Pw38Stage.texture]=Pw38TextureStageDriver(ffi:ffi,io:Pw38TextureIo(
        runId:request.runId,inputRoot:Directory(request.ioRoots.durableInputRoot),
        runRoot:Directory(request.ioRoots.downstreamOutputRoot),
        sceneRelativeDirectory:request.ioRoots.textureSceneRoot.substring(request.ioRoots.durableInputRoot.length+1),
        meshRelativePath:string(p,'input_ply'),outputRelativePrefix:string(p,'output_prefix')));
    } catch(e) {missing[Pw38Stage.texture]='$e';}
  }
  Future<void> bindNormal({bool includeVisibility = true}) async {
    const symbols={'pw38_av_convert_sfm_to_abc','pw38_av_bake_normal'};
    try {
      final s=await slot('normal',symbols);
      if (includeVisibility) {
      final visibilitySymbols={'pw38_av_prepare_sfm_original_numpy',
        if(usesOriginalRetained97(request.json)) 'pw38_av_original_numpy_last_error'};
      final visibility=await slot('glb',visibilitySymbols);
      final io=await slot('meshio',{'pw38_open3d_read_ply','pw38_open3d_mesh_destroy',
        'pw38_open3d_vertex_count','pw38_open3d_vertices','pw38_open3d_has_vertex_colors','pw38_open3d_vertex_colors'});
      drivers[Pw38Stage.avVisibility]=NativeDriver(Pw38Stage.avVisibility,visibility,visibilitySymbols.toList(),() async {
        final runtime=_pythonRuntime;
        if (runtime==null || runtime.binarySha256!=visibility.binarySha256) {
          throw StateError('Original visibility requires its verified initialized CPython provider');
        }
        final a=Arena(memory);Pointer<Void> mesh=nullptr;
        try {
          final holder=a.bytes(sizeOf<Pointer<Void>>()).cast<Pointer<Void>>();
          var rc=io.library.lookupFunction<ReadN,ReadD>('pw38_open3d_read_ply')(
            a.path(path(Pw38Stage.avVisibility,'high_ply',false)),holder);
          record('pw38_open3d_read_ply',rc);
          mesh=holder.value;if(rc!=0){return rc;}
          final count=io.library.lookupFunction<CountN,CountD>('pw38_open3d_vertex_count')(mesh);
          final hasColor=io.library.lookupFunction<HasColorsN,HasColorsD>('pw38_open3d_has_vertex_colors')(mesh);
          final colors=io.library.lookupFunction<VerticesN,VerticesD>('pw38_open3d_vertex_colors')(mesh);
          final frames=a.bytes(request.frames.length*sizeOf<NormalFrame>()).cast<NormalFrame>();
          for(var i=0;i<request.frames.length;i++) {
            final f=request.frames[i];final native=(frames+i).ref;
            native.d16=a.path(retainedOutput(i,'d16'));native.width=f.width;native.height=f.height;
            native.originalCamera=a.path(input(f.originalCameraPath));
            final camera=await File(retainedOutput(i,'camera_f64')).readAsBytes();
            copyF64(native.intrinsics,camera.sublist(0,72));
            copyF64(native.extrinsics,camera.sublist(72));
          }
          rc=visibility.library.lookupFunction<OriginalVisibilityN,OriginalVisibilityD>('pw38_av_prepare_sfm_original_numpy')(
            io.library.lookupFunction<VerticesN,VerticesD>('pw38_open3d_vertices')(mesh),colors,count,hasColor,frames,request.frames.length,
            a.path(path(Pw38Stage.avVisibility,'original_images',true)),
            a.path(path(Pw38Stage.avVisibility,'sfm_json',false)),
            a.path(path(Pw38Stage.avVisibility,'gate_directory',false)));
          // The original C bridge owns a thread-local char[2048] diagnostic.
          // Copy it immediately on the same calling thread, retaining native rc.
          String? nativeError;
          if (rc != 0 && visibility.symbols.contains('pw38_av_original_numpy_last_error')) {
            final error=visibility.library.lookupFunction<Pw38GeometryErrorNative,Pw38GeometryErrorDart>('pw38_av_original_numpy_last_error')();
            if (error == nullptr) {
              nativeError='Original visibility error getter returned nullptr';
            } else {
              final bytes=error.cast<Uint8>().asTypedList(2048);
              final end=bytes.indexOf(0);
              nativeError=utf8.decode(bytes.sublist(0,end < 0 ? bytes.length : end),allowMalformed:true);
            }
          }
          return record('pw38_av_prepare_sfm_original_numpy',rc,{'native_error':nativeError});
        }finally{if(mesh!=nullptr){io.library.lookupFunction<DestroyN,DestroyD>('pw38_open3d_mesh_destroy')(mesh);}a.dispose();}
      });
      }
      drivers[Pw38Stage.avSfmToAbc]=NativeDriver(Pw38Stage.avSfmToAbc,s,['pw38_av_convert_sfm_to_abc'],() async {
        final a=Arena(memory);try{return record('pw38_av_convert_sfm_to_abc',s.library.lookupFunction<PairN,PairD>('pw38_av_convert_sfm_to_abc')(
          a.path(path(Pw38Stage.avSfmToAbc,'sfm_json',false)),a.path(path(Pw38Stage.avSfmToAbc,'sfm_abc',false))));
        }finally{a.dispose();}
      });
      drivers[Pw38Stage.avNormal]=NativeDriver(Pw38Stage.avNormal,s,['pw38_av_bake_normal'],() async {
        final a=Arena(memory);try{return record('pw38_av_bake_normal',s.library.lookupFunction<NormalN,NormalD>('pw38_av_bake_normal')(
          a.path(path(Pw38Stage.avNormal,'sfm_abc',false)),a.path(path(Pw38Stage.avNormal,'low_obj',false)),
          a.path(path(Pw38Stage.avNormal,'high_ply',false)),a.path(path(Pw38Stage.avNormal,'original_images',true)),
          a.path(path(Pw38Stage.avNormal,'normal_directory',false))));}finally{a.dispose();}
      });
    }catch(e){for(final stage in [Pw38Stage.avVisibility,Pw38Stage.avSfmToAbc,Pw38Stage.avNormal]){missing[stage]='$e';}}
  }
  /// Bootstrap the same process-owned CPython provider before original CER/fusion.
  Future<void> initializePythonRuntime() async {
    await bindGlb();
    if (_pythonRuntime == null) {
      throw StateError(missing[Pw38Stage.glb] ?? 'Pinned original CPython runtime unavailable');
    }
  }
  Future<void> bindGlb() async {
    if (_pythonRuntime != null) return;
    try {
      const symbols={'pw38_glb_runtime_initialize','pw38_glb_export_obj','pw38_trimesh_process_export_raw','pw38_vdb_integrate_d16_original_numpy','pw38_av_prepare_sfm_original_numpy'};
      final s=await slot('glb',symbols);
      final row=object(request.native['glb']);
      final home='$bundleRoot/${checkedRelativePath(string(row,'runtime_home_bundle_relative_path'))}';
      final modules='$bundleRoot/${checkedRelativePath(string(row,'native_modules_bundle_relative_path'))}';
      final initArena=Arena(memory);
      try {
        final rc=s.library.lookupFunction<PairN,PairD>('pw38_glb_runtime_initialize')(
          initArena.path(home),initArena.path(modules));
        record('pw38_glb_runtime_initialize',rc);
        if(rc!=0){throw StateError('Pinned CPython initialization returned $rc');}
      } finally {initArena.dispose();}
      _pythonRuntime=s;
      drivers[Pw38Stage.glb]=NativeDriver(Pw38Stage.glb,s,symbols.toList(),() async {
        final a=Arena(memory);try{return record('pw38_glb_export_obj',s.library.lookupFunction<TripleN,TripleD>('pw38_glb_export_obj')(
          a.path(path(Pw38Stage.glb,'obj',false)),a.path(path(Pw38Stage.glb,'normal_directory',false)),
          a.path(path(Pw38Stage.glb,'output_glb',false))));}finally{a.dispose();}
      });
    }catch(e){missing[Pw38Stage.glb]='$e';}
  }
}
