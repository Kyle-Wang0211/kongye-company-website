import 'dart:convert';
import 'dart:io';
import 'dense_binding_contract.dart';
import 'native_downstream.dart';
import 'request.dart';
import 'reconstruction_mainline.dart';
import 'reconstruction_request.dart';
import 'vendor/dart_pipeline/lib/pw38_pipeline.dart';

/// One real grouped dense call followed by nine genuine downstream calls.
/// No upstream no-op driver is manufactured to fit a thirteen-call registry.
Future<Map<String,Object?>> runMainline(Map<String,String> bootstrap,
    {Pw38DenseMainline? denseCore}) async {
  final events=<Map<String,Object?>>[];
  final receipts=<Map<String,Object?>>[];
  MainlineRequest? request;
  Directory? ownedOutputRoot;
  Map<String,Object?>? nativeDense;
  Future<Map<String,Object?>> finish(int code,String? reason) async {
    final full=code==0 && reason==null && receipts.length==13;
    final value=<String,Object?>{'schema':'PW38_MAINLINE_RESULT_V1','run_id':request?.runId,
      'bundle_id':bootstrap['bundle_id'],'build':bootstrap['build'],'full38_complete':full,
      'exit_code':code,'stopped_reason':reason,'native_binding':events,
      'dense_native_result':nativeDense,'stages':receipts};
    final owned=ownedOutputRoot;
    if(owned!=null && await owned.exists()){
      await File('${owned.path}/RESULT.json').writeAsString(jsonEncode(value),flush:true);
    }
    return value;
  }
  try {
    final requestFile=File(bootstrap['request_path']!);
    if(await hashFile(requestFile)!=bootstrap['request_sha256']) {
      throw StateError('Root-frozen request hash changed');
    }
    final envelope=object(jsonDecode(await requestFile.readAsString()));
    if(envelope['schema']==reconstructionSchema) {
      return await runOfficialReconstruction(bootstrap,denseCore:denseCore);
    }
    request=await MainlineRequest.load(File(bootstrap['request_path']!),bootstrap['request_sha256']!);
    final r=request;
    if(bootstrap['bundle_id']!='com.kyle.pocketworldOnnxBench.k35476742' || bootstrap['build']!='3810') {
      throw StateError('Dedicated full38 candidate identity mismatch');
    }
    r.contract.validate();await r.verifyRetainedInputs();
    final output=Directory(r.ioRoots.downstreamOutputRoot);
    if(await output.exists()){throw StateError('Fresh mainline output root already exists');}
    await output.create(recursive:false);
    ownedOutputRoot=output;
    final native=DownstreamNative(r,bootstrap['bundle_path']!);await native.bind();
    events.add({'stage':'native_binding','available':native.drivers.keys.map((s)=>s.name).toList(),
      'missing':native.missing.map((stage,reason)=>MapEntry(stage.name,reason))});
    final dense=denseCore??await openRootBoundDense(r,bootstrap['bundle_path']!);
    // Resolve complete closure before allocating/inferencing the large actual97 job.
    for(final stage in pw38StageOrder.skip(4)){
      if(!native.drivers.containsKey(stage)){return await finish(38,'${stage.name}: ${native.missing[stage]}');}
    }
    final gate=Pw38FileArtifactGate(inputRoot:Directory(r.ioRoots.durableInputRoot),runRoot:output,
      sha256File:hashFile,validateFormat:r.verifyFormatEvidence);
    await gate.validateInputs(r.contract);await gate.requireFreshOutputs(r.contract);
    final denseReceipt=await dense.run(r);nativeDense=denseReceipt.nativeResult;
    if(denseReceipt.returnCode!=0){return await finish(denseReceipt.returnCode,'pw_full38_dense_run returned ${denseReceipt.returnCode}');}
    if(nativeDense['status']!=0 || nativeDense['frames']!=97 || nativeDense['fused_frames']!=97){
      return await finish(38,'Actual dense result did not complete97 fused references');
    }
    for(final stage in pw38StageOrder.take(4)){
      for(final a in r.contract.outputs[stage]!){await gate.verifyOutput(stage,a);}
      receipts.add({'stage':stage.name,'entry_return_code':0,'output_gate_passed':true,
        'native_entry':'pw_full38_dense_run','grouped_call':true,
        'native_phase_milliseconds':denseReceipt.phaseMilliseconds[stage]});
    }
    for(final stage in pw38StageOrder.skip(4)){
      final driver=native.drivers[stage]!;final watch=Stopwatch()..start();
      final rc=await driver.run(r.contract);
      if(rc!=0){receipts.add({'stage':stage.name,'entry_return_code':rc,'output_gate_passed':false});
        return await finish(rc,'${stage.name} returned $rc');}
      for(final a in r.contract.outputs[stage]!){await gate.verifyOutput(stage,a);}
      receipts.add({'stage':stage.name,'entry_return_code':rc,'output_gate_passed':true,
        'native_entries':driver.verifiedCAbiSymbols,'elapsed_microseconds':watch.elapsedMicroseconds});
    }
    return await finish(0,null);
  }catch(e){return await finish(38,'$e');}
}
