// User-authorized isolated physical-device acceptance fixture; never production.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';

const bundleIdentity =
    'dc633f8e6ea776f1575b26bf9bee18b9b4bad0f8f80472816a98563ee06c466a';
void main() => runApp(const MaterialApp(home: DeviceFixture()));

class DeviceFixture extends StatefulWidget {
  const DeviceFixture({super.key});
  @override
  State<DeviceFixture> createState() => _DeviceFixtureState();
}

class _DeviceFixtureState extends State<DeviceFixture>
    with WidgetsBindingObserver {
  SharedViewerController controller = SharedViewerController();
  Completer<void> ready = Completer<void>();
  bool show = true;
  int generation = 1;
  String status = '正在验证共享 Viewer';
  String? documents;
  final result = <String, Object?>{
    'schema': 'PW_SHARED_IOS_DEVICE_V1',
    'runId': DateTime.now().toUtc().toIso8601String(),
    'bundleIdentity': bundleIdentity,
    'phases': <Object?>[],
    'lifecycle': <Object?>[]
  };
  Future<void> writes = Future<void>.value();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(run());
  }

  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  void onReady() {
    if (!ready.isCompleted) ready.complete();
  }

  void onError(Object error) {
    (result.putIfAbsent('nativeErrors', () => <Object?>[]) as List).add({
      'utc': DateTime.now().toUtc().toIso8601String(), 'message': error.toString()
    });
    result['status'] = 'FAIL';
    unawaited(save());
    if (!ready.isCompleted) ready.completeError(error);
  }

  Future<void> save() {
    final path = documents;
    if (path == null) return Future.value();
    final text = const JsonEncoder.withIndent('  ').convert(result);
    writes = writes.then((_) => File('$path/RESULT.json')
        .writeAsString(text, flush: true)
        .then<void>((_) {}));
    return writes;
  }

  Future<void> stage(
      String name, Future<Map<String, Object?>> Function() body) async {
    if (mounted) setState(() => status = name);
    final phase = <String, Object?>{
      'name': name,
      'startUtc': DateTime.now().toUtc().toIso8601String(),
      'generation': generation
    };
    (result['phases'] as List).add(phase);
    await save();
    try {
      phase.addAll(await body());
      phase['status'] = 'PASS';
    } catch (error) {
      phase['status'] = 'FAIL';
      phase['error'] = error.toString();
      rethrow;
    } finally {
      phase['endUtc'] = DateTime.now().toUtc().toIso8601String();
      await save();
    }
  }

  Future<Map<String, Object?>> snapshot(String name) async {
    final data = await controller.capture();
    check(data is String && data.startsWith('data:image/png;base64,'),
        'Expected canvas PNG');
    final bytes = base64Decode((data as String).split(',').last);
    await File('$documents/$name.png').writeAsBytes(bytes, flush: true);
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final rgba =
        await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    check(rgba != null, 'PNG decode unavailable');
    final pixels = rgba!.buffer.asUint8List();
    int visible = 0;
    for (int i = 0; i < pixels.length; i += 4) {
      if (pixels[i] + pixels[i + 1] + pixels[i + 2] > 30) visible++;
    }
    final receipt = <String, Object?>{
      'png': '$name.png',
      'pngBytes': bytes.length,
      'width': frame.image.width,
      'height': frame.image.height,
      'visiblePixels': visible
    };
    frame.image.dispose();
    codec.dispose();
    check(visible > 100, 'Rendered canvas is empty');
    return receipt;
  }

  Future<Map<String, Object?>> load(
      String filename, SharedModelFormat format, String capture) async {
    await controller.loadLocalFile('$documents/fixtures/$filename',
        format: format);
    final state = await controller.getState();
    check(
        state['bundleIdentity'] == bundleIdentity && state['status'] == 'ready',
        'Wrong renderer identity or state');
    if (format == SharedModelFormat.glb)
      check(
          state['triangleCount'] == 70564 &&
              state['loadedTextureCount'] == 80 &&
              state['normalMapCount'] == 40,
          'GLB geometry/textures mismatch');
    if (format == SharedModelFormat.ply)
      check(state['pointCount'] == 49253 && state['triangleCount'] == 0,
          'PLY geometry mismatch');
    if (format == SharedModelFormat.skp) {
      check(state['triangleCount'] == 4 && state['loadedTextureCount'] == 1,
          'SKP geometry/texture mismatch');
      final info = state['importInfo'] as Map;
      check(
          info['sourceSha256'] ==
              'f68a36f4578ffb8533eae9a29c1b3dc2f6b5683bacc3e53c52fc5406b1375688',
          'SKP source changed');
    }
    return {'state': state, 'capture': await snapshot(capture)};
  }

  Future<void> run() async {
    try {
      documents = await const MethodChannel('dev.pocketworld.viewer.fixture')
          .invokeMethod<String>('documents');
      check(documents != null, 'Missing app Documents');
      await save();
      await stage('初始化 WKWebView', () async {
        await ready.future.timeout(const Duration(seconds: 40));
        final state = await controller.getState();
        check(state['bundleIdentity'] == bundleIdentity,
            'Bundle identity mismatch');
        return {'state': state};
      });
      await stage('显示原38最终 GLB',
          () => load('final.glb', SharedModelFormat.glb, '01_glb'));
      await stage('切换稀疏 PLY',
          () => load('sparse.ply', SharedModelFormat.ply, '02_ply'));
      await stage('显示 SKP 转换预览',
          () => load('textured.skp', SharedModelFormat.skp, '03_skp'));
      await stage('错误替换保留旧模型', () async {
        bool rejected = false;
        String? error;
        try {
          await controller.loadLocalFile('$documents/fixtures/sparse.ply',
              format: SharedModelFormat.skp);
        } catch (e) {
          rejected = true;
          error = e.toString();
        }
        check(rejected, 'Invalid SKP unexpectedly accepted');
        final state = await controller.getState();
        check(state['format'] == 'skp' && state['triangleCount'] == 4,
            'Last successful model lost');
        return {
          'expectedError': error,
          'state': state,
          'capture': await snapshot('04_error_retains_skp')
        };
      });
      await stage('恢复 GLB',
          () => load('final.glb', SharedModelFormat.glb, '05_recovery'));
      await stage('销毁并重新进入 Viewer', () async {
        final old = controller;
        setState(() => show = false);
        await WidgetsBinding.instance.endOfFrame;
        check(!old.isAttached, 'Old host stayed attached');
        old.dispose();
        controller = SharedViewerController();
        ready = Completer<void>();
        generation++;
        setState(() => show = true);
        await ready.future.timeout(const Duration(seconds: 40));
        return load('final.glb', SharedModelFormat.glb, '06_reentry');
      });
      check((result['nativeErrors'] as List?)?.isEmpty ?? true,
          'Native host reported an error');
      result['status'] = 'PASS_FORMATS_REPLACEMENT_REENTRY';
      result['nativeGestures'] = 'NOT_YET_EXERCISED';
      result['actualBackgroundForeground'] = 'AWAITING_USER_ACTION';
      if (mounted) setState(() => status = '三种格式与重新进入验证通过；可旋转、缩放检查');
    } catch (error, stack) {
      result['status'] = 'FAIL';
      result['error'] = error.toString();
      result['stack'] = stack.toString();
      if (mounted) setState(() => status = '验证失败：$error');
    } finally {
      await save();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    (result['lifecycle'] as List).add(
        {'state': state.name, 'utc': DateTime.now().toUtc().toIso8601String()});
    unawaited(save());
    if (state == AppLifecycleState.resumed &&
        result['status'] == 'PASS_FORMATS_REPLACEMENT_REENTRY') {
      Future<void>.delayed(const Duration(seconds: 1), () async {
        if (!mounted || !controller.isAttached) return;
        try {
          result['postResumeState'] = await controller.getState();
          result['postResumeCapture'] = await snapshot('07_post_resume');
          await save();
        } catch (error) {
          result['status'] = 'FAIL';
          result['postResumeError'] = error.toString();
          await save();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
          child: Column(children: [
        Text(status, style: const TextStyle(color: Colors.white, fontSize: 13)),
        Expanded(
            child: show
                ? SharedViewer(
                    key: ValueKey(generation),
                    controller: controller,
                    onReady: onReady,
                    onError: onError)
                : const SizedBox())
      ])));
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }
}
