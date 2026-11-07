import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pw_shared_viewer/src/local_server.dart';

void main() {
  late SharedViewerAssetServer server;
  late Directory temp;
  late HttpClient client;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('shared-viewer-test-');
    client = HttpClient();
    server = await SharedViewerAssetServer.start(
      assets: {'index.html', 'viewer.mjs'},
      readAsset: (path) async => Uint8List.fromList('asset:$path'.codeUnits),
    );
  });
  tearDown(() async {
    client.close(force: true);
    await server.close();
    await temp.delete(recursive: true);
  });
  Future<HttpClientResponse> get(Uri uri) async =>
      (await client.getUrl(uri)).close();
  test('token and exact asset allowlist required', () async {
    expect((await get(server.entryUri)).statusCode, 200);
    expect(
        (await get(server.entryUri.replace(path: '/bad/index.html')))
            .statusCode,
        404);
    expect((await get(server.entryUri.resolve('secret.txt'))).statusCode, 404);
    expect(
        (await get(server.entryUri.resolve('%2e%2e/%2e%2e/etc/passwd')))
            .statusCode,
        404);
  });
  test('streams only explicitly registered files with binary length', () async {
    final file = File('${temp.path}/model.glb');
    final output = await file.open(mode: FileMode.write);
    await output.truncate(77 * 1024 * 1024);
    await output.close();
    final uri = await server.registerModel(file.path);
    final response = await get(uri);
    expect(response.contentLength, 77 * 1024 * 1024);
    expect(response.headers.contentType?.mimeType, 'model/gltf-binary');
    var bytes = 0;
    await for (final chunk in response) {
      bytes += chunk.length;
    }
    expect(bytes, 77 * 1024 * 1024);
    expect((await get(uri.resolve('unregistered.glb'))).statusCode, 404);
    server.unregisterModel(uri);
    expect((await get(uri)).statusCode, 404);
  });
  test('symlink registration and unsupported format rejected', () async {
    final file = await File('${temp.path}/secret.glb').writeAsString('secret');
    final link = await Link('${temp.path}/link.glb').create(file.path);
    await expectLater(server.registerModel(link.path), throwsArgumentError);
    final sidecar = await File('${temp.path}/scene.obj').writeAsString('{}');
    await expectLater(server.registerModel(sidecar.path), throwsArgumentError);
    final gltf = await File('${temp.path}/scene.gltf').writeAsString('{"asset":{"version":"2.0"}}');
    final uri = await server.registerModel(gltf.path);
    expect((await get(uri)).statusCode, 200);
  });
  test('HEAD is bounded, forged Host denied, and changed models rejected',
      () async {
    final file = await File('${temp.path}/change.glb').writeAsBytes([1, 2, 3]);
    final uri = await server.registerModel(file.path);
    final head = await (await client.openUrl('HEAD', uri)).close();
    expect(head.statusCode, 200);
    expect(head.contentLength, 3);
    expect(await head.expand((chunk) => chunk).toList(), isEmpty);
    final forged = await client.getUrl(server.entryUri);
    forged.headers.set(HttpHeaders.hostHeader, 'evil.example');
    expect((await forged.close()).statusCode, 404);
    await file.writeAsBytes([1, 2, 3, 4]);
    expect((await get(uri)).statusCode, 409);
  });
  test('registered path replaced by symlink is never served', () async {
    final model =
        await File('${temp.path}/registered.glb').writeAsBytes([1, 2, 3]);
    final uri = await server.registerModel(model.path);
    final secret =
        await File('${temp.path}/secret.glb').writeAsBytes([4, 5, 6]);
    await model.delete();
    await Link(model.path).create(secret.path);
    expect((await get(uri)).statusCode, 409);
  });
  test('immutable point-memory transport requires token and is released explicitly', () async {
    final bytes=Uint8List.fromList([10,20,30]);
    final uri=await server.registerBytes(bytes,'ply');
    bytes[0]=99;
    final response=await get(uri);
    final body=await response.fold<List<int>>([], (out,chunk)=>out..addAll(chunk));
    expect(response.statusCode,200);expect(body,[10,20,30]);
    server.unregisterModel(uri);
    expect((await get(uri)).statusCode,404);
    await expectLater(server.registerBytes(Uint8List(0),'ply'),throwsArgumentError);
  });

}
