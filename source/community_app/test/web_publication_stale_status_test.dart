import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'web_publication_service_test.dart' show glb;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocketworld_flutter/community/web_publication_service.dart';
import 'package:pocketworld_flutter/ui/community/web_publication_page.dart';
const uid='11111111-1111-4111-8111-111111111111';
const sid='22222222-2222-4222-8222-222222222222';
const key='33333333-3333-4333-8333-333333333333';
class PollPorts implements WebPublicationPorts {
 final lateStatus=Completer<Map<String,dynamic>>();int statusCalls=0,uploads=0;
 @override String? get userId=>uid;
 @override Uri get apiOrigin=>Uri.parse('https://api.kongye.space');
 Map<String,dynamic> status(String s)=>{'ok':true,'submission_id':sid,'status':s};
 @override Future<Map<String,dynamic>> invoke(Map<String,dynamic> body)async {
  if(body['action']=='status'){statusCalls++;if(statusCalls>1)return lateStatus.future;return status('uploading');}
  if(body['action']=='initiate')return {...status('uploading'),'upload':{'bucket':'publication-staging','path':'$uid/$sid/source.glb','token':'token','signed_url':'${apiOrigin.origin}/storage/v1/object/upload/sign/publication-staging/$uid/$sid/source.glb?token=token'}};
  return status('queued');
 }
 @override Future<void> upload({required String path,required String token,required Uint8List bytes,String bucket='publication-staging',void Function(int,int)? onBytesSent})async {uploads++;onBytesSent?.call(bytes.length,bytes.length);}
}
void main(){testWidgets('late uploading status cannot overwrite a successfully sealed retry', (tester)async {
 final bytes=glb();
 SharedPreferences.setMockInitialValues({'pw.web.publication.$uid':jsonEncode({'key':key,'submission':sid,'sha256':sha256.convert(bytes).toString(),'title':'fixture','description':'test','selection':null})});
 final ports=PollPorts();
 await tester.pumpWidget(MaterialApp(home:WebPublicationPage(service:WebPublicationService.forTest(ports),ownerForTesting:()=>uid,identityChangesForTesting:const Stream<String?>.empty(),pickFileForTesting:()async=>PlatformFile(name:'cube.glb',size:bytes.length,bytes:bytes))));
 try {
  await tester.pumpAndSettle();
  await tester.tap(find.text('选择 GLB'));await tester.pumpAndSettle();
  await tester.tap(find.text('刷新状态'));await tester.pump();
  expect(ports.statusCalls,2);
  await tester.tap(find.text('提交发布'));await tester.pumpAndSettle();
  expect(ports.uploads,1);expect(find.text('已提交，等待处理'),findsOneWidget);
  ports.lateStatus.complete(ports.status('uploading'));await tester.pumpAndSettle();
  expect(find.text('已提交，等待处理'),findsOneWidget);
  expect(find.text('等待上传完成'),findsNothing);
 } finally {await tester.pumpWidget(const SizedBox());}
});}
