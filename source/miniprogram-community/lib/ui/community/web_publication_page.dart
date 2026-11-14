import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';

import '../../community/web_publication_service.dart';
import 'web_publication_selection_page.dart';
import 'mini_model_picker_stub.dart'
    if (dart.library.js_interop) 'mini_model_picker_web.dart';

/// Private drafts never enter the public feed. Reload resumes status, never
/// silently starts another submission after an ambiguous request.
class WebPublicationPage extends StatefulWidget {
  const WebPublicationPage({
    super.key,
    @visibleForTesting this.service,
    @visibleForTesting this.ownerForTesting,
    @visibleForTesting this.identityChangesForTesting,
    @visibleForTesting this.pickFileForTesting,
    @visibleForTesting this.selectionBuilderForTesting,
    @visibleForTesting this.previewHostBuilderForTesting,
  });
  final WebPublicationService? service;
  final String? Function()? ownerForTesting;
  final Stream<String?>? identityChangesForTesting;
  final Future<PlatformFile?> Function()? pickFileForTesting;
  final Widget Function(BuildContext, Uint8List)? selectionBuilderForTesting;
  final Widget Function(
    SharedViewerController,
    VoidCallback,
    ValueChanged<Object>,
  )?
  previewHostBuilderForTesting;
  @override
  State<WebPublicationPage> createState() => _WebPublicationPageState();
}

class _WebPublicationPageState extends State<WebPublicationPage> {
  final _title = TextEditingController(),
      _description = TextEditingController();
  late final String? _owner;
  late final _service = widget.service ?? WebPublicationService();
  StreamSubscription<String?>? _auth;
  Route<dynamic>? _publicationRoute, _selectionRoute;
  String? get _liveOwner => widget.ownerForTesting != null
      ? widget.ownerForTesting!()
      : Supabase.instance.client.auth.currentUser?.id;
  Uint8List? _bytes;
  SharedViewerController? _previewController;
  Map<String, dynamic>? _confirmedView;
  Uint8List? _coverPreview;
  int _previewEpoch = 0;
  bool _previewReady = false, _confirming = false, _coverEditing = false;
  final _previewAnchor = GlobalKey();
  int _draftEpoch = 0;
  bool get _canReturnToEditing =>
      const {'failed', 'not_qualified'}.contains(_status?.status);

  void _resetPreview({bool keepConfirmed = false}) {
    _previewEpoch++;
    _previewController?.dispose();
    _previewController = _bytes == null ? null : SharedViewerController();
    _previewReady = false;
    _confirming = false;
    _coverPreview = null;
    if (!keepConfirmed) {
      _confirmedView = null;
      _coverEditing = false;
    }
  }

  Future<void> _previewLoaded(
    int epoch,
    SharedViewerController controller,
  ) async {
    bool current() =>
        _current &&
        epoch == _previewEpoch &&
        identical(controller, _previewController);
    final bytes = _bytes;
    if (!current() || bytes == null) return;
    try {
      await controller.configure(
        interactive: true,
        autoRotate: false,
        background: 0,
      );
      if (!current()) return;
      await controller.loadBytes(
        bytes,
        format: _format == 'ply'
            ? SharedModelFormat.ply
            : SharedModelFormat.glb,
      );
      if (!current()) return;
      await controller.setSelectionPreview(_selection, decorations: false);
      if (!current()) return;
      if (_confirmedView != null)
        await controller.setCameraFraming(_confirmedView!);
      if (current()) setState(() => _previewReady = true);
    } catch (_) {
      if (current()) setState(() => _message = '3D 预览暂不可用，请重新选择 GLB / PLY');
    }
  }

  Future<void> _confirmView() async {
    final controller = _previewController;
    final epoch = _previewEpoch;
    bool current() =>
        _current &&
        epoch == _previewEpoch &&
        identical(controller, _previewController);
    if (!current() ||
        controller == null ||
        !_previewReady ||
        _busy ||
        _confirming ||
        _key != null)
      return;
    setState(() {
      _confirming = true;
      _coverEditing = true;
    });
    try {
      await controller.configure(interactive: false);
      if (!current()) return;
      final camera = await controller.getCameraFraming();
      if (!current()) return;
      final image = await controller.capture(type: 'image/png');
      if (!current()) return;
      if (image is! String || !image.startsWith('data:image/png;base64,')) {
        throw const WebPublicationException('cover_preview_unavailable');
      }
      final confirmed = validatePublicationInitialView(
        {
          'schema': 'pw.camera-framing.v1',
          'source_sha256': _sourceHash,
          'selection_box': _selection,
          ...camera,
        },
        sourceSha256: _sourceHash!,
        selectionBox: _selection,
      );
      final png = base64Decode(
        image.substring('data:image/png;base64,'.length),
      );
      if (!current()) return;
      setState(() {
        _confirmedView = confirmed;
        _coverPreview = png;
        _coverEditing = false;
        _message = '已确认封面和初始视角';
      });
    } catch (_) {
      if (current()) setState(() => _message = '当前画面未确认，请重试');
    } finally {
      if (current()) {
        try {
          await controller.configure(interactive: true);
        } catch (_) {}
        if (current()) setState(() => _confirming = false);
      }
    }
  }

  void _showPreview() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _previewAnchor.currentContext;
      if (!_current || target == null) return;
      unawaited(
        Scrollable.ensureVisible(
          target,
          alignment: 0.1,
          duration: const Duration(milliseconds: 200),
        ),
      );
    });
  }

  Future<void> _changeCover() async {
    if (!_current || _busy || _confirming) return;
    if (_key != null) {
      await _returnToEditing();
      return;
    }
    setState(() {
      _coverEditing = true;
      _message = '请调整 3D 取景并重新确认封面。';
    });
    _showPreview();
  }

  Future<void> _returnToEditing() async {
    if (!_current || _busy || _confirming || !_canReturnToEditing) return;
    final epoch = ++_draftEpoch;
    _poll?.cancel();
    setState(() => _busy = true);
    try {
      // The old sealed submission stays server-owned. Only its local recovery
      // pointer becomes a fresh editable draft, with a new nonce on submission.
      await _persist(editable: true);
      if (!_current || epoch != _draftEpoch) return;
      setState(() {
        _key = null;
        _submission = null;
        _status = null;
        _selected = _bytes != null;
        _coverEditing = true;
        _message = _bytes == null
            ? '标题、描述和选区已保留。请选择同一 GLB / PLY 后重新确认封面。'
            : '请调整 3D 取景并重新确认封面。';
      });
      _showPreview();
    } catch (_) {
      if (_current && epoch == _draftEpoch) {
        setState(() => _message = '暂时无法返回编辑，请重试。');
      }
    } finally {
      if (_current && epoch == _draftEpoch) setState(() => _busy = false);
    }
  }

  Widget _preview() {
    final controller = _previewController!;
    final epoch = _previewEpoch;
    void ready() => unawaited(_previewLoaded(epoch, controller));
    void failed(Object error) {
      if (_current && epoch == _previewEpoch)
        setState(() {
          _previewReady = false;
          _message = '3D 预览暂不可用，请重新选择 GLB / PLY';
        });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          key: _previewAnchor,
          aspectRatio: 1.5,
          child: ColoredBox(
            color: Colors.black,
            child: KeyedSubtree(
              key: ValueKey('publication-preview-$epoch'),
              child:
                  widget.previewHostBuilderForTesting?.call(
                    controller,
                    ready,
                    failed,
                  ) ??
                  SharedViewer(
                    controller: controller,
                    onReady: ready,
                    onError: failed,
                  ),
            ),
          ),
        ),
        const Text('拖动旋转、缩放或平移模型，再确认当前画面。'),
        if (_coverEditing)
          const Text('封面待重新确认', key: ValueKey('publication-cover-pending')),
        ShadButton.outline(
          enabled: _previewReady && !_busy && !_confirming && _key == null,
          onPressed: _previewReady && !_busy && !_confirming && _key == null
              ? _confirmView
              : null,
          child: Text(_confirming ? '正在确认画面…' : '确认当前画面为封面和初始视角'),
        ),
        ShadButton.ghost(
          enabled: _previewReady && !_busy && !_confirming && _key == null,
          onPressed: _previewReady && !_busy && !_confirming && _key == null
              ? () async {
                  try {
                    await controller.resetCamera();
                  } catch (_) {}
                }
              : null,
          child: const Text('恢复默认视角'),
        ),
        if (_coverPreview != null) ...[
          Text(_coverEditing ? '上次确认的封面（待重新确认）' : '已确认的封面预览'),
          Image.memory(
            _coverPreview!,
            key: const ValueKey('publication-confirmed-cover'),
            errorBuilder: (_, _, _) => const Text('已保存当前视角'),
          ),
          ShadButton.outline(
            enabled:
                !_busy && !_confirming && (_key == null || _canReturnToEditing),
            key: const ValueKey('publication-change-cover'),
            onPressed:
                !_busy && !_confirming && (_key == null || _canReturnToEditing)
                ? _changeCover
                : null,
            child: const Text('更换封面'),
          ),
        ],
      ],
    );
  }

  String _format = 'glb';
  Map<String, dynamic>? _selection;
  String? _key, _submission, _message, _sourceHash;
  WebPublicationStatus? _status;
  bool _busy = false, _selected = false, _invalidated = false;
  Timer? _poll;
  String get _storageKey => 'pw.web.publication.$_owner';
  bool get _current =>
      mounted && !_invalidated && _owner != null && _liveOwner == _owner;
  @override
  void initState() {
    super.initState();
    _owner = _liveOwner;
    final changes =
        widget.identityChangesForTesting ??
        Supabase.instance.client.auth.onAuthStateChange.map(
          (event) => event.session?.user.id,
        );
    _auth = changes.listen((owner) {
      if (owner != _owner) _invalidateIdentity();
    });
    unawaited(
      _restore().then((_) {
        if (_current && usesMiniModelPicker && _submission == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_current) unawaited(_pick());
          });
        }
      }),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _publicationRoute ??= ModalRoute.of(context);
  }

  void _invalidateIdentity() {
    if (_invalidated) return;
    _invalidated = true;
    _poll?.cancel();
    _title.clear();
    _description.clear();
    _bytes = null;
    _resetPreview();
    _selection = null;
    _status = null;
    _key = null;
    _submission = null;
    _sourceHash = null;
    _message = null;
    _selected = false;
    _busy = false;
    if (!mounted) return;
    setState(() {});
    final navigator = Navigator.of(context);
    // Remove only the two routes owned by this flow, including an editing
    // selection whose PopScope can currently forbid an ordinary pop.
    final selection = _selectionRoute;
    if (selection != null && selection.isActive) {
      navigator.removeRoute(selection);
    }
    final publication = _publicationRoute;
    if (publication != null && publication.isActive) {
      navigator.removeRoute(publication);
    }
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_current) return;
    final saved = prefs.getString(_storageKey);
    if (saved == null) return;
    try {
      final draft = jsonDecode(saved) as Map<String, dynamic>;
      setState(() {
        final editable = draft['editable'] == true;
        _key = editable ? null : draft['key'] as String;
        _submission = editable ? null : draft['submission'] as String?;
        _coverEditing = editable;
        _sourceHash = draft['sha256'] as String?;
        _format = draft['format'] == 'ply' ? 'ply' : 'glb';
        _selection = (draft['selection'] as Map?)?.cast<String, dynamic>();
        _confirmedView = (draft['initial_view'] as Map?)
            ?.cast<String, dynamic>();
        _title.text = draft['title'] as String? ?? '';
        _description.text = draft['description'] as String? ?? '';
        if (editable) {
          _message = '标题、描述和选区已保留。请选择同一 GLB / PLY 后重新确认封面。';
        } else {
          _message = _submission == null
              ? '上次提交结果未确认。重新选择同一 GLB / PLY 可安全重试。'
              : '正在查询上次提交';
        }
      });
    } catch (_) {
      setState(() => _message = '上次草稿无法读取，请刷新页面重试');
      return;
    }
    if (_submission != null) await _checkStatus();
  }

  Future<void> _persist({bool editable = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!_current) {
      throw const WebPublicationException('signed_out_or_account_changed');
    }
    await prefs.setString(
      _storageKey,
      jsonEncode({
        'editable': editable || _key == null,
        'key': editable ? null : _key,
        'submission': editable ? null : _submission,
        'sha256': _sourceHash,
        'selection': _selection,
        'initial_view': _confirmedView,
        'format': _format,
        'title': _title.text,
        'description': _description.text,
      }),
    );
  }

  Future<void> _newDraft() async {
    if (!_current || _busy || _status?.isTerminal != true) return;
    _draftEpoch++;
    final prefs = await SharedPreferences.getInstance();
    if (!_current) return;
    await prefs.remove(_storageKey);
    if (!_current) return;
    setState(() {
      _key = null;
      _submission = null;
      _sourceHash = null;
      _bytes = null;
      _resetPreview();
      _selection = null;
      _status = null;
      _selected = false;
      _message = null;
      _title.clear();
      _description.clear();
    });
  }

  Future<void> _pick() async {
    if (!_current || _busy) return;
    setState(() => _busy = true);
    try {
      PlatformFile? file;
      if (widget.pickFileForTesting != null) {
        file = await widget.pickFileForTesting!();
      } else if (usesMiniModelPicker) {
        file = await pickMiniModelFile();
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['glb', 'ply'],
          withData: true,
          allowMultiple: false,
        );
        file = result?.files.single;
      }
      if (!_current || file == null) return;
      final format = file.name.split('.').last.toLowerCase();
      if (!const {'glb', 'ply'}.contains(format) ||
          file.size > WebPublicationService.maxSourceBytes ||
          file.bytes == null) {
        throw const WebPublicationException('请选择不超过 50 MB 的 GLB / PLY');
      }
      final bytes = file.bytes!;
      _format = format;
      if (_key != null || (_bytes == null && _sourceHash != null)) {
        if (sha256.convert(bytes).toString() != _sourceHash) {
          throw const WebPublicationException('source_changed');
        }
        setState(() {
          _bytes = bytes;
          _resetPreview(keepConfirmed: true);
          _selected = true;
        });
        return;
      }
      if (!mounted) return;
      final route = MaterialPageRoute<WebPublicationSelectionResult>(
        builder: (context) =>
            widget.selectionBuilderForTesting?.call(context, bytes) ??
            WebPublicationSelectionPage(
              bytes: bytes,
              format: _format == 'ply'
                  ? SharedModelFormat.ply
                  : SharedModelFormat.glb,
            ),
      );
      _selectionRoute = route;
      final selection = await Navigator.of(context).push(route);
      _selectionRoute = null;
      if (!_current || selection == null) return;
      setState(() {
        _bytes = bytes;
        _selection = selection.box?.toJson();
        _sourceHash = sha256.convert(bytes).toString();
        _resetPreview();
        _selected = true;
      });
    } catch (error) {
      if (_current) {
        setState(
          () =>
              _message = error is StateError && error.message == '请在微信小程序中选择文件'
              ? '请在微信小程序中选择文件'
              : '文件或模型选区不可用，请选择有效 GLB / PLY',
        );
      }
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_current ||
        _bytes == null ||
        !_selected ||
        _busy ||
        _confirming ||
        (_key == null && (_confirmedView == null || _coverEditing)))
      return;
    if (_title.text.trim().isEmpty ||
        _title.text.runes.length > 100 ||
        _description.text.runes.length > 30) {
      setState(() => _message = '请输入 1–100 字标题和最多 30 字描述');
      return;
    }
    setState(() {
      _busy = true;
      _message = '正在提交';
    });
    try {
      _key ??= const Uuid().v4();
      _sourceHash ??= sha256.convert(_bytes!).toString();
      await _persist();
      if (!_current) return;
      final status = await _service.submit(
        bytes: _bytes!,
        format: _format,
        title: _title.text,
        description: _description.text,
        idempotencyKey: _key!,
        selectionBox: _selection,
        initialView: _confirmedView,
        expectedSourceSha256: _sourceHash,
        onSubmissionCreated: (id) async {
          if (!_current) return;
          _submission = id;
          await _persist();
        },
        onProgress: (phase, fraction) {
          if (_current) {
            setState(
              () => _message = switch (phase) {
                'uploading' => '正在上传 ${(fraction * 100).round()}%',
                'sealing' => '正在确认上传',
                _ => '正在准备提交',
              },
            );
          }
        },
      );
      if (!_current) return;
      setState(() {
        _status = status;
        _message = null;
      });
      _schedule();
    } on WebPublicationException catch (e) {
      if (_current) setState(() => _message = '提交未完成：${e.code}。重试将复用原请求。');
    } catch (_) {
      if (_current) setState(() => _message = '提交暂不可用，请重试');
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _cancelSubmission() async {
    if (!_current ||
        _busy ||
        _submission == null ||
        _status?.isTerminal == true) {
      return;
    }
    _poll?.cancel();
    setState(() {
      _busy = true;
      _message = '正在确认取消';
    });
    try {
      final status = await _service.cancel(_submission!);
      if (!_current) return;
      setState(() {
        _status = status;
        _message = status.status == 'cancelled'
            ? '本次提交已取消，可以发布另一个作品'
            : '服务器尚未确认取消，请刷新状态';
      });
      _schedule();
    } catch (_) {
      if (_current) setState(() => _message = '取消结果未确认，草稿已保留。请刷新状态后重试。');
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  void _schedule() {
    _poll?.cancel();
    if (_current && _status?.isTerminal == false) {
      _poll = Timer(const Duration(seconds: 5), _checkStatus);
    }
  }

  Future<void> _checkStatus() async {
    if (!_current || _submission == null) return;
    final epoch = _draftEpoch;
    final submission = _submission!;
    try {
      final status = await _service.getStatus(submission);
      if (!_current || epoch != _draftEpoch || submission != _submission)
        return;
      setState(() {
        _status = status;
        _message = null;
      });
      _schedule();
    } catch (_) {
      if (_current && epoch == _draftEpoch && submission == _submission) {
        setState(() => _message = '状态查询暂不可用，请点击刷新状态');
      }
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _auth?.cancel();
    _previewController?.dispose();
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  String get _statusText => switch (_status?.status) {
    'published' => '已发布',
    'uploading' => '等待上传完成',
    'queued' => '已提交，等待处理',
    'rendering' || 'processing' => '正在处理',
    'awaiting_review' => '等待审核',
    'rejected' => '审核未通过',
    'not_qualified' => '处理未完成',
    'failed' => '处理失败',
    'cancelled' => '已取消',
    'unpublished' => '已下架',
    _ => '',
  };
  @override
  Widget build(BuildContext context) => !_current
      ? const SizedBox.shrink()
      : Scaffold(
          appBar: AppBar(title: const Text('发布作品')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  ShadButton.outline(
                    enabled:
                        !(_busy ||
                            (_submission != null &&
                                _status?.status != 'uploading')),
                    onPressed:
                        _busy ||
                            (_submission != null &&
                                _status?.status != 'uploading')
                        ? null
                        : _pick,
                    leading: const Icon(Icons.upload_file),
                    child: Text(
                      _selected ? '重新选择 GLB / PLY / 调整选区' : '选择 GLB / PLY',
                    ),
                  ),
                  if (_selected)
                    Text(_selection == null ? '保留整个模型' : '已确认模型选区'),
                  if (_previewController != null) _preview(),
                  ShadInput(
                    controller: _title,
                    enabled: !_busy && _key == null,
                    top: const Text('标题（1–100 字）'),
                  ),
                  ShadInput(
                    controller: _description,
                    enabled: !_busy && _key == null,
                    top: const Text('描述（最多 30 字）'),
                  ),
                  const SizedBox(height: 24),
                  ShadButton(
                    enabled:
                        !_busy &&
                        _selected &&
                        !_confirming &&
                        (_key != null ||
                            (_confirmedView != null && !_coverEditing)) &&
                        (_submission == null ||
                            _status?.status == 'uploading' ||
                            _status == null),
                    onPressed:
                        !_busy &&
                            _selected &&
                            !_confirming &&
                            (_key != null ||
                                (_confirmedView != null && !_coverEditing)) &&
                            (_submission == null ||
                                _status?.status == 'uploading' ||
                                _status == null)
                        ? _submit
                        : null,
                    child: Text(_busy ? '正在提交…' : '提交发布'),
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  if (_message != null) Text(_message!),
                  if (_status != null)
                    Text(_statusText, key: const Key('publication-status')),
                  if (_submission != null)
                    ShadButton.ghost(
                      enabled: !(_busy),
                      onPressed: _busy ? null : _checkStatus,
                      child: const Text('刷新状态'),
                    ),
                  if (_submission != null && _status?.isTerminal != true)
                    ShadButton.ghost(
                      enabled: _current && !_busy,
                      onPressed: _current && !_busy ? _cancelSubmission : null,
                      child: const Text('取消本次提交'),
                    ),
                  if (_canReturnToEditing)
                    ShadButton.outline(
                      enabled: !(_busy || _confirming),
                      key: const ValueKey('publication-return-editing'),
                      onPressed: _busy || _confirming ? null : _returnToEditing,
                      child: const Text('返回编辑 / 更换封面'),
                    ),
                  if (_status?.isTerminal == true)
                    ShadButton.ghost(
                      onPressed: _newDraft,
                      child: const Text('发布另一个作品'),
                    ),
                  const Text('作品完成处理并通过审核后才会出现在社区。'),
                ],
              ),
            ),
          ),
        );
}
