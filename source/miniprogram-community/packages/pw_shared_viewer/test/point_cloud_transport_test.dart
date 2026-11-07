import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pw_shared_viewer/src/point_cloud_transport.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';

void main(){
 test('standard PLY transport preserves exact ordered coordinates and colors',(){
  final bytes=encodePointCloudPly(Float32List.fromList([1.25,-2,3.5,4,5,6]),Uint8List.fromList([1,2,3,250,251,252]));
  final marker=ascii.encode('end_header\n');
  int offset=0;for(int i=0;i<bytes.length-marker.length;i++){if(List.generate(marker.length,(j)=>bytes[i+j]==marker[j]).every((v)=>v)){offset=i+marker.length;break;}}
  expect(offset,greaterThan(0));expect(ascii.decode(bytes.sublist(0,offset)),contains('element vertex 2\n'));
  final body=ByteData.sublistView(bytes,offset);expect(body.getFloat32(0,Endian.little),1.25);expect(body.getFloat32(4,Endian.little),-2);expect(body.getFloat32(8,Endian.little),3.5);expect(bytes.sublist(offset+12,offset+15),[1,2,3]);expect(body.getFloat32(15,Endian.little),4);expect(bytes.sublist(offset+27),[250,251,252]);
  expect(()=>encodePointCloudPly(Float32List(2),Uint8List(2)),throwsArgumentError);
 });
 test('point transport releases registered memory after correlated load completion',()async{
  final c=SharedViewerController();late Map<String,Object?> sent;bool released=false;
  c.attachTransport((m)async{sent=m;},registerBytes:(bytes,format)async=>Uri.parse('http://127.0.0.1/model.ply'),releaseResource:(uri){released=true;});
  final load=c.loadPointCloud(xyz:Float32List.fromList([1,2,3]),rgb:Uint8List.fromList([4,5,6]));
  await Future<void>.delayed(Duration.zero);expect(released,false);expect((sent['args'] as Map)['preserveCamera'],true);
  c.receive({'protocol':sharedViewerProtocol,'id':sent['id'],'ok':true,'result':{}});await load;expect(released,true);c.dispose();
 });
}
