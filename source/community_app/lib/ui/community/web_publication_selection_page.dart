// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';
import '../../official_capture/selection_box.dart';

import '../official_capture/cloud_camera.dart';
import '../official_capture/selection_tools_layer.dart';
import '../official_capture/selection_rect_handles.dart';
import '../official_capture/web_publication_camera_controls.dart'
    show CloudViewCamera, CloudViewController;

/// null route result is cancellation; box == null explicitly retains all GLB.
class WebPublicationSelectionResult {
  const WebPublicationSelectionResult({
    this.box,
    this.coverJpeg,
    this.cameraFraming,
  });
  final SelectionBox? box;
  final Uint8List? coverJpeg;
  final Map<String, dynamic>? cameraFraming;
}

/// Publication-only draft. Never reads or writes the capture selection archive.
class WebPublicationSelectionPage extends StatefulWidget {
  const WebPublicationSelectionPage({super.key, required this.bytes});
  final Uint8List bytes;

  @override
  State<WebPublicationSelectionPage> createState() =>
      _WebPublicationSelectionPageState();
}

class _WebPublicationSelectionPageState
    extends State<WebPublicationSelectionPage> {
  final _controller = SharedViewerController();
  SharedViewerController? _viewer;
  final _camera = ValueNotifier<CloudViewCamera?>(null);
  final _controls =
      CloudViewController(); // pose messages only; no point renderer/data
  SelectionBox? _box, _initial;
  String? _error;
  bool _busy = false, _keepAll = false, _showAdjustment = false;
  bool _choosingCover = false;
  bool get _supportedModel => true;

  double _span = 1;
  Timer? _cameraPoll;
  Future<void> _queue = Future.value();

  @override
  void initState() {
    super.initState();
    _controls.addListener(_moveCamera);
    if (!_supportedModel) _error = '发布选区只支持 GLB 模型';
  }

  void _fail(Object error) {
    if (mounted) setState(() => _error = '模型选区暂不可用：$error');
  }

  Future<void> _ready() async {
    final viewer = _controller;
    _viewer = viewer;
    try {
      await viewer.loadBytes(widget.bytes, format: SharedModelFormat.glb);
      final bounds = await viewer.getSelectionBounds();
      List<double> read(String key) {
        final raw = bounds?[key];
        if (raw is! List ||
            raw.length != 3 ||
            raw.any((v) => v is! num || !v.isFinite)) {
          throw StateError('无法读取原始 GLB 边界');
        }
        return raw.map((v) => (v as num).toDouble()).toList();
      }

      final min = read('min'), max = read('max');
      if (List.generate(3, (i) => max[i] <= min[i]).any((v) => v)) {
        throw StateError('GLB 边界无效');
      }
      _span = List.generate(3, (i) => max[i] - min[i]).reduce(math.max);
      final initial = SelectionBox.initialSquareFace(
        cx: (min[0] + max[0]) / 2,
        cy: (min[1] + max[1]) / 2,
        cz: (min[2] + max[2]) / 2,
        halfExtent: _span / 2,
      );
      await viewer.beginSelectionEditing(_span / 2);
      await viewer.setSelectionPreview(initial.toJson());
      final rotation = await viewer.getSelectionView();
      if (!mounted) return;
      final (yaw, pitch, roll) = decomposeViewMatrix(rotation);
      _camera.value = (
        yaw: yaw,
        pitch: pitch,
        roll: roll,
        zoom: 1,
        panX: 0,
        panY: 0,
        pivotX: initial.cx,
        pivotY: initial.cy,
        pivotZ: initial.cz,
      );
      setState(() {
        _box = initial;
        _initial = initial;
      });
      _cameraPoll?.cancel();
      _cameraPoll = Timer.periodic(
        const Duration(milliseconds: 150),
        (_) => _syncCamera(),
      );
    } catch (e) {
      _fail(e);
    }
  }

  bool _polling = false;
  Future<void> _syncCamera() async {
    if (_polling || _busy || _camera.value == null || _viewer == null) return;
    _polling = true;
    try {
      final rot = await _viewer!.getSelectionView();
      final state = await _viewer!.getState();
      final cameraState = state['camera'] as Map?;
      final target = cameraState?['target'] as Map?;
      final zoom = (cameraState?['zoom'] as num?)?.toDouble() ?? 1.0;
      if (!mounted) return;
      final (y, p, r) = decomposeViewMatrix(rot);
      final c = _camera.value!;
      if ((c.yaw - y).abs() + (c.pitch - p).abs() + (c.roll - r).abs() > 1e-6 ||
          (zoom - c.zoom).abs() > 1e-6 ||
          target?['x'] != c.pivotX ||
          target?['y'] != c.pivotY ||
          target?['z'] != c.pivotZ) {
        _camera.value = (
          yaw: y,
          pitch: p,
          roll: r,
          zoom: zoom,
          panX: c.panX,
          panY: c.panY,
          pivotX: (target?['x'] as num?)?.toDouble() ?? c.pivotX,
          pivotY: (target?['y'] as num?)?.toDouble() ?? c.pivotY,
          pivotZ: (target?['z'] as num?)?.toDouble() ?? c.pivotZ,
        );
      }
    } catch (e) {
      _fail(e);
    } finally {
      _polling = false;
    }
  }

  void _moveCamera() {
    final target = _controls.takeTarget();
    if (_controls.takeReframe()) _enqueue(() => _viewer!.resetCamera());
    if (target == null || _viewer == null) return;
    _camera.value = target;
    _enqueue(
      () => _viewer!.setSelectionView(
        composeViewMatrix(target.yaw, target.pitch, target.roll),
        [target.pivotX, target.pivotY, target.pivotZ],
      ),
    );
  }

  void _enqueue(Future<void> Function() operation) {
    setState(() => _busy = true);
    final pending = _queue.then((_) => operation());
    _queue = pending.catchError((Object e) {
      _fail(e);
    });
    // Every operation is ordered; finishing the tail is the acceptance boundary.
    final tail = _queue;
    tail.then((_) {
      if (mounted && identical(_queue, tail)) setState(() => _busy = false);
    });
  }

  void _change(SelectionBox box) {
    setState(() {
      _box = box;
      _keepAll = false;
    });
    _enqueue(() => _viewer!.setSelectionPreview(box.toJson()));
  }

  Future<void> _finish({bool cancel = false}) async {
    if (_busy) return;
    if (!cancel && (_error != null || _box == null || _viewer == null)) return;
    setState(() => _busy = true);
    try {
      await _queue;
      await _viewer?.endSelectionEditing();
      if (cancel) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      await _viewer!.setSelectionPreview(
        _keepAll ? null : _box!.toJson(),
        decorations: false,
      );
      await _viewer!.configure(autoRotate: false);
      _cameraPoll?.cancel();
      if (mounted) setState(() => _choosingCover = true);
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _takeCover() async {
    if (_busy || !_choosingCover || _viewer == null) return;
    setState(() => _busy = true);
    try {
      await _viewer!.configure(interactive: false);
      final camera = await _viewer!.getCameraFraming();
      final capture = await _viewer!.capture(
        type: 'image/jpeg',
        quality: 0.85,
        canonicalCamera: false,
      );
      const prefix = 'data:image/jpeg;base64,';
      if (capture is! String || !capture.startsWith(prefix)) {
        throw StateError('无法拍摄作品封面');
      }
      final jpeg = base64Decode(capture.substring(prefix.length));
      if (jpeg.isEmpty) throw StateError('作品封面为空');
      if (!mounted) return;
      Navigator.of(context).pop(
        WebPublicationSelectionResult(
          box: _keepAll ? null : _box,
          coverJpeg: jpeg,
          cameraFraming: camera,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('封面拍摄未完成，请重试')));
      }
    } finally {
      try {
        await _viewer?.configure(interactive: true);
      } catch (_) {}
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _cameraPoll?.cancel();
    _controller.dispose();
    _controls.removeListener(_moveCamera);
    _controls.dispose();
    _camera.dispose();
    super.dispose();
  }

  Widget _adjustment() {
    final b = _box!, initial = _initial!;
    return Material(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('选区位置与大小', style: TextStyle(color: Colors.white)),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => _keepAll = !_keepAll);
                    final selection = _keepAll ? null : _box!.toJson();
                    _enqueue(() => _viewer!.setSelectionPreview(selection));
                  },
                  child: Text(_keepAll ? '恢复选区' : '保留全部'),
                ),
              ],
            ),
            for (var axis = 0; axis < 3; axis++)
              Row(
                children: [
                  Text(
                    ['X', 'Y', 'Z'][axis],
                    style: const TextStyle(color: Colors.white),
                  ),
                  Expanded(
                    child: Slider(
                      value:
                          ([b.cx, b.cy, b.cz][axis] -
                                  [initial.cx, initial.cy, initial.cz][axis])
                              .clamp(-_span, _span),
                      min: -_span,
                      max: _span,
                      onChanged: (v) {
                        final center = [b.cx, b.cy, b.cz];
                        center[axis] =
                            [initial.cx, initial.cy, initial.cz][axis] + v;
                        _change(
                          b.copyWith(
                            cx: center[0],
                            cy: center[1],
                            cz: center[2],
                          ),
                        );
                      },
                    ),
                  ),
                  const Text('尺寸', style: TextStyle(color: Colors.white)),
                  Expanded(
                    child: Slider(
                      value: [
                        b.sx,
                        b.sy,
                        b.sz,
                      ][axis].clamp(_span * .02, _span * 2),
                      min: _span * .02,
                      max: _span * 2,
                      onChanged: (v) {
                        final sizes = [b.sx, b.sy, b.sz];
                        sizes[axis] = v;
                        _change(
                          b.copyWith(sx: sizes[0], sy: sizes[1], sz: sizes[2]),
                        );
                      },
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  CloudProjection _projection(Size size, CloudViewCamera camera) => CloudCamera(
    yaw: camera.yaw,
    pitch: camera.pitch,
    roll: camera.roll,
    zoom: camera.zoom,
    panX: 0,
    panY: 0,
    pivotX: camera.pivotX,
    pivotY: camera.pivotY,
    pivotZ: camera.pivotZ,
    radius: _span / 2,
    orthographic: true,
  ).projectionFor(size);

  Widget _handles(Size size) => ValueListenableBuilder<CloudViewCamera?>(
    valueListenable: _camera,
    builder: (context, camera, _) {
      if (camera == null || _box == null || _keepAll) {
        return const SizedBox.shrink();
      }
      final projection = _projection(size, camera);
      final basis = boxScreenBasis(projection, _box!);
      final rect = selectionScreenRect(basis, _box!);
      final positions = <Offset>[
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
        Offset(rect.left, rect.center.dy),
        Offset(rect.right, rect.center.dy),
        Offset(rect.center.dx, rect.top),
        Offset(rect.center.dx, rect.bottom),
      ];
      return Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: RectHandlesPainter(rect: rect)),
            ),
          ),
          for (final position in positions)
            Positioned(
              left: position.dx - 22,
              top: position.dy - 22,
              width: 44,
              height: 44,
              child: GestureDetector(
                key: ValueKey(
                  'publication-handle-${positions.indexOf(position)}',
                ),
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (event) {
                  final box = _box!;
                  final currentBasis = boxScreenBasis(
                    _projection(size, _camera.value!),
                    box,
                  );
                  final handle = hitRectHandle(rect, position)!;
                  _change(
                    applyRectHandleDrag(
                      box: box,
                      basis: currentBasis,
                      h: handle,
                      screenDelta: event.delta,
                      minHalfSize:
                          _span * .5 * SelectionBox.kMinHalfSizeFraction,
                    ),
                  );
                },
                child: const SizedBox.expand(),
              ),
            ),
          Positioned(
            left: rect.center.dx - 22,
            top: rect.center.dy - 22,
            width: 44,
            height: 44,
            child: GestureDetector(
              key: const ValueKey('publication-move-box'),
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (event) {
                final p = _projection(size, _camera.value!);
                final right = p.rightAxisWorld(), up = p.upAxisWorld();
                final unit = p.worldPerPixelAt(p.camDist);
                final b = _box!;
                _change(
                  b.copyWith(
                    cx:
                        b.cx +
                        (right[0] * event.delta.dx - up[0] * event.delta.dy) *
                            unit,
                    cy:
                        b.cy +
                        (right[1] * event.delta.dx - up[1] * event.delta.dy) *
                            unit,
                    cz:
                        b.cz +
                        (right[2] * event.delta.dx - up[2] * event.delta.dy) *
                            unit,
                  ),
                );
              },
              child: const Icon(Icons.open_with, color: Colors.white, size: 20),
            ),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = Size(
        constraints.maxWidth.floorToDouble(),
        constraints.maxHeight.floorToDouble(),
      );
      return PopScope(
        canPop: !_busy,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              if (_supportedModel)
                SharedViewer(
                  controller: _controller,
                  onReady: _ready,
                  onError: _fail,
                ),
              if (_box != null && !_choosingCover) _handles(viewport),
              if (_box != null && !_choosingCover)
                SelectionToolsLayer(
                  box: _box!,
                  onBoxChanged: _change,
                  camera: _camera,
                  controller: _controls,
                  onExit: () {
                    if (!_busy && _error == null) _finish();
                  },
                  onCancel: () => _finish(cancel: true),
                  onResetBoxSize: () => _change(_initial!),
                ),
              if (_box != null && !_choosingCover && _showAdjustment)
                Positioned(
                  left: 12,
                  right: 100,
                  bottom: 180,
                  child: _adjustment(),
                ),
              if (_box != null && !_choosingCover)
                Positioned(
                  left: 12,
                  bottom: 150,
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () =>
                            setState(() => _showAdjustment = !_showAdjustment),
                        child: const Text('位置与尺寸'),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() => _keepAll = !_keepAll);
                          final selection = _keepAll ? null : _box!.toJson();
                          _enqueue(
                            () => _viewer!.setSelectionPreview(selection),
                          );
                        },
                        child: Text(_keepAll ? '恢复选区' : '保留全部'),
                      ),
                    ],
                  ),
                ),
              if (_choosingCover)
                SafeArea(
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: IconButton(
                          onPressed: _busy ? null : () => _finish(cancel: true),
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                          tooltip: '取消',
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        '旋转、缩放作品，选择封面角度',
                        style: TextStyle(color: Colors.white),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _takeCover,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                            ),
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('拍摄封面并继续'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_box == null || _error != null)
                SafeArea(
                  child: Column(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                      if (_error != null)
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.white),
                        )
                      else
                        const CircularProgressIndicator(),
                    ],
                  ),
                ),
              if (_busy)
                const Positioned(
                  left: 16,
                  bottom: 160,
                  child: Text('正在更新预览…', style: TextStyle(color: Colors.white)),
                ),
            ],
          ),
        ),
      );
    },
  );
}
