import 'dart:js_interop';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

@JS('window.pwOpenModelPicker')
external JSPromise<JSBoolean> _openModelPicker(JSString value);
@JS('window.pwConsumeModelHandoff')
external JSString? _consumeModelHandoff();

bool get usesMiniModelPicker => Uri.base.path.startsWith('/miniprogram/');

Future<PlatformFile?> pickMiniModelFile() async {
  final client = Supabase.instance.client;
  final owner = client.auth.currentUser?.id;
  final bearer = client.auth.currentSession?.accessToken;
  if (owner == null || bearer == null) throw StateError('请先登录');
  final endpoint = Uri.parse(
    client.rest.url,
  ).resolve('/functions/v1/mini-model-handoff');
  if (endpoint.origin != 'https://api.kongye.space')
    throw StateError('文件传输服务不可用');
  final id = _consumeModelHandoff()?.toDart;
  if (id != null) {
    final response = await http
        .post(
          endpoint,
          headers: {
            'Authorization': 'Bearer $bearer',
            'Content-Type': 'application/json',
          },
          body: '{"action":"read","id":"$id"}',
        )
        .timeout(const Duration(seconds: 90));
    if (client.auth.currentUser?.id != owner || response.statusCode != 200)
      throw StateError('私密草稿读取失败');
    final name = Uri.decodeComponent(response.headers['x-model-name'] ?? '');
    final format = name.split('.').last.toLowerCase();
    if (!const {'glb', 'ply'}.contains(format) ||
        response.bodyBytes.length > 50000000)
      throw StateError('模型文件不可用');
    // Owner-authenticated bytes are now local. Cleanup never queues publication.
    await client.functions.invoke(
      'mini-model-handoff',
      body: {'action': 'discard', 'id': id},
    );
    return PlatformFile(
      name: name,
      size: response.bodyBytes.length,
      bytes: response.bodyBytes,
    );
  }
  final response = await client.functions.invoke(
    'mini-model-handoff',
    body: {'action': 'create'},
  );
  final data = response.data;
  if (response.status != 200 ||
      data is! Map ||
      client.auth.currentUser?.id != owner)
    throw StateError('文件选择暂不可用');
  final grantId = data['id'], grant = data['grant'];
  if (grantId is! String ||
      !RegExp(r'^[0-9a-f-]{36}$').hasMatch(grantId) ||
      grant is! String ||
      !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(grant))
    throw StateError('文件选择暂不可用');
  // No session token or grant is placed in the native page URL.
  await _openModelPicker('{"id":"$grantId","grant":"$grant"}'.toJS).toDart;
  return null;
}
