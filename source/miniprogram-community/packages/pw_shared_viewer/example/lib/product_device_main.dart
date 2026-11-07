// ignore_for_file: invalid_use_of_visible_for_testing_member
// Isolated physical fixture of actual production embedding classes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';
import 'production_fixture/ui/shared/product_model_view.dart';
import 'production_fixture/ui/shared/product_point_view.dart';

void main()=>runApp(const MaterialApp(home:ProductFixture()));
class ProductFixture extends StatefulWidget{
 const ProductFixture({super.key});
 @override State<ProductFixture> createState()=>_ProductFixtureState();
}
class _ProductFixtureState extends State<ProductFixture>{
 final point=SharedViewerController();
 SharedViewerController? model;
 ProductViewerCapture? thumb;
 final boundary=GlobalKey();
 final result=<String,Object?>{'schema':'PW_PRODUCTION_VIEWER_EMBEDDING_V1','phases':<Object?>[]};
 String? documents;
 String phase='正在验证生产 Viewer';
 bool showPoint=true,feed=false,enabled=true;
 String? finalModel;
 final ready=Completer<void>();
 Future<void> writes=Future.value();
 @override void initState(){super.initState();unawaited(run());}
 Future<void> save(){if(documents==null)return Future.value();final s=jsonEncode(result);writes=writes.then((_)async{await File('$documents/PRODUCT_RESULT.json').writeAsString(s,flush:true);});return writes;}
 void check(bool value,String message){if(!value)throw StateError(message);}
 Future<void> stage(String name,Future<Map<String,Object?>>Function() body)async{
  setState(()=>phase=name);final row=<String,Object?>{'name':name,'startUtc':DateTime.now().toUtc().toIso8601String()};(result['phases'] as List).add(row);await save();
  try{row.addAll(await body());row['status']='PASS';}catch(e){row['status']='FAIL';row['error']=e.toString();rethrow;}finally{row['endUtc']=DateTime.now().toUtc().toIso8601String();await save();}
 }
 Future<Map<String,Object?>> waitState(SharedViewerController c,bool Function(Map<String,Object?>) predicate)async{
  final deadline=DateTime.now().add(const Duration(seconds:45));
  while(DateTime.now().isBefore(deadline)){
   if(c.isAttached){final state=await c.getState();if(predicate(state))return state;}
   await Future<void>.delayed(const Duration(milliseconds:100));
  }
  throw TimeoutException('Production embedded renderer did not reach expected state');
 }
 Future<Map<String,Object?>> inspectPng(String name,List<int> bytes,{int minVisible=100})async{
  await File('$documents/$name.png').writeAsBytes(bytes,flush:true);
  final codec=await ui.instantiateImageCodec(Uint8List.fromList(bytes));final frame=await codec.getNextFrame();final data=await frame.image.toByteData(format:ui.ImageByteFormat.rawRgba);final pixels=data!.buffer.asUint8List();int visible=0;
  for(int i=0;i<pixels.length;i+=4){if(pixels[i]+pixels[i+1]+pixels[i+2]>30)visible++;}
  final receipt=<String,Object?>{'png':'$name.png','width':frame.image.width,'height':frame.image.height,'visiblePixels':visible,'bytes':bytes.length};frame.image.dispose();codec.dispose();check(visible>minVisible,'Production image is empty');return receipt;
 }
 Future<Map<String,Object?>> capture(String name,SharedViewerController c)async{final data=await c.capture();check(data is String && data.startsWith('data:image/png;base64,'),'Expected renderer PNG');return inspectPng(name,base64Decode((data as String).split(',').last));}
 Future<void> run()async{
  try{
   documents=await const MethodChannel('dev.pocketworld.viewer.fixture').invokeMethod<String>('documents');check(documents!=null,'Missing fixture Documents');await save();setState((){});
   Map<String,Object?>? pointCamera;
   await stage('真实稀疏 PLY 进入生产点云层',()async{final s=await waitState(point,(s)=>s['pointCount']==49253&&s['status']=='ready');pointCamera=s['camera'] as Map<String,Object?>;return {'state':s,'capture':await capture('prod01_points',point)};});
   await stage('同一生产点云层切换最终 GLB',()async{
    setState(()=>finalModel=Uri.file('$documents/fixtures/final.glb').toString());
    final s=await waitState(point,(s)=>s['triangleCount']==70564&&s['status']=='ready');check(s['loadedTextureCount']==80&&s['normalMapCount']==40,'Lost original GLB textures');final current=s['camera'] as Map; double delta=0; for(final group in ['position','target']){for(final axis in ['x','y','z']){final d=((current[group] as Map)[axis] as num).toDouble()-((pointCamera![group] as Map)[axis] as num).toDouble(); if(d.abs()>delta)delta=d.abs();}} check(delta<1e-9,'Progressive replacement reset camera');return {'state':s,'capture':await capture('prod02_progressive_glb',point)};
   });
   await stage('实际生产模型包装层',()async{
    setState(()=>showPoint=false);await ready.future.timeout(const Duration(seconds:45));final c=model!;final s=await waitState(c,(s)=>s['triangleCount']==70564&&s['loadedTextureCount']==80&&s['status']=='ready');final jpeg=await thumb!.captureThumb();check(jpeg!=null&&jpeg.length>1000&&jpeg[0]==255&&jpeg[1]==216,'Thumbnail is not original JPEG capture');return {'state':s,'jpegBytes':jpeg!.length,'capture':await capture('prod03_direct_glb',c)};
   });
   await stage('社区同渲染器帧与原玻璃层合成',()async{
    final c=model!;setState(()=>feed=true);await Future<void>.delayed(const Duration(seconds:3));
    final first=await c.getState();check(first['paused']==false,'Feed unexpectedly paused');
    final firstCapture=await capture('prod04a_feed_start',c);final interval=Stopwatch()..start();
    await Future<void>.delayed(const Duration(seconds:2));final second=await c.getState();interval.stop();
    check(second['paused']==false,'Feed stopped during active interval');
    double azimuth(Map<String,Object?> state){final cam=state['camera'] as Map;final p=cam['position'] as Map;final t=cam['target'] as Map;return math.atan2((p['x'] as num)-(t['x'] as num),(p['z'] as num)-(t['z'] as num));}
    final angle=math.atan2(math.sin(azimuth(second)-azimuth(first)),math.cos(azimuth(second)-azimuth(first))).abs();
    check(angle>0.5&&angle<2.2,'Feed did not sustain expected rotation: $angle');
    final rotationProof={'first':first,'second':second,'elapsedMs':interval.elapsedMilliseconds,'angleRadians':angle,'firstCapture':firstCapture,'secondCapture':await capture('prod04b_feed_rotated',c)};
    await WidgetsBinding.instance.endOfFrame;
    final image=await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio:1);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);image.dispose();check(bytes!=null,'No Flutter composed image');return {'rotationProof':rotationProof,'state':await c.getState(),'capture':await inspectPng('prod04_flutter_glass',bytes!.buffer.asUint8List(),minVisible:10000)};
   });
   await stage('生产离焦暂停与返回恢复',()async{
    setState(()=>enabled=false);final p=await waitState(model!,(s)=>s['paused']==true);setState(()=>enabled=true);final r=await waitState(model!,(s)=>s['paused']==false);return {'paused':p['paused'],'resumed':r['paused'],'capture':await capture('prod05_focus_resume',model!)};
   });
   setState((){feed=false;phase='生产包装层验证通过';});result['status']='PASS_PRODUCTION_EMBEDDING';
  }catch(e,s){result['status']='FAIL';result['error']=e.toString();result['stack']=s.toString();if(mounted)setState(()=>phase='验证失败：$e');}finally{await save();}
 }
 @override Widget build(BuildContext context)=>Scaffold(backgroundColor:Colors.black,body:SafeArea(child:Column(children:[Text(phase,style:const TextStyle(color:Colors.white)),Expanded(child:documents==null?const SizedBox():TickerMode(enabled:enabled,child:RepaintBoundary(key:boundary,child:Stack(fit:StackFit.expand,children:[
  if(showPoint)ProductPointView(key:const ValueKey('progressive'),xyz:Float32List(0),rgb:Uint8List(0),sourcePath:'$documents/fixtures/sparse.ply',finalModelUrl:finalModel,controller:point)
  else ProductModelView(key:const ValueKey('actual-product-model'),modelUrl:Uri.file('$documents/fixtures/final.glb').toString(),interactive:!feed,autoRotate:feed,onViewerReady:(c){thumb=c;if(!ready.isCompleted)ready.complete();},hostBuilder:(context,c,onReady,onError){model=c;return SharedViewer(controller:c,onReady:onReady,onError:onError);}),
  if(feed)Positioned(left:16,right:16,bottom:16,child:LiquidGlassLayer(settings:const LiquidGlassSettings(thickness:20,blur:4,glassColor:Color(0x08FFFFFF),refractiveIndex:1.20,lightIntensity:1,saturation:1),child:LiquidGlass(shape:const LiquidRoundedSuperellipse(borderRadius:20),glassContainsChild:false,child:const Padding(padding:EdgeInsets.all(18),child:Text('原有社区信息层',style:TextStyle(color:Colors.white))))))
 ]))))])));
 @override void dispose(){point.dispose();super.dispose();}
}
