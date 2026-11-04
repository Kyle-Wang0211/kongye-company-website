import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../community/web_publication_service.dart';
import 'web_publication_selection_page.dart';

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
  });
  final WebPublicationService? service;
  final String? Function()? ownerForTesting;
  final Stream<String?>? identityChangesForTesting;
  final Future<PlatformFile?> Function()? pickFileForTesting;
  final Widget Function(BuildContext, Uint8List)? selectionBuilderForTesting;
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
    unawaited(_restore());
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
        _key = draft['key'] as String;
        _submission = draft['submission'] as String?;
        _sourceHash = draft['sha256'] as String?;
        _selection = (draft['selection'] as Map?)?.cast<String, dynamic>();
        _title.text = draft['title'] as String? ?? '';
        _description.text = draft['description'] as String? ?? '';
        _message = _submission == null
            ? '上次提交结果未确认。重新选择同一 GLB 可安全重试。'
            : '正在查询上次提交';
      });
    } catch (_) {
      setState(() => _message = '上次草稿无法读取，请刷新页面重试');
      return;
    }
    if (_submission != null) await _checkStatus();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_current) {
      throw const WebPublicationException('signed_out_or_account_changed');
    }
    await prefs.setString(
      _storageKey,
      jsonEncode({
        'key': _key,
        'submission': _submission,
        'sha256': _sourceHash,
        'selection': _selection,
        'title': _title.text,
        'description': _description.text,
      }),
    );
  }

  Future<void> _newDraft() async {
    if (!_current || _busy || _status?.isTerminal != true) return;
    final prefs = await SharedPreferences.getInstance();
    if (!_current) return;
    await prefs.remove(_storageKey);
    if (!_current) return;
    setState(() {
      _key = null;
      _submission = null;
      _sourceHash = null;
      _bytes = null;
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
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['glb'],
          withData: true,
          allowMultiple: false,
        );
        file = result?.files.single;
      }
      if (!_current || file == null) return;
      if (!file.name.toLowerCase().endsWith('.glb') ||
          file.size > WebPublicationService.maxSourceBytes ||
          file.bytes == null) {
        throw const WebPublicationException('请选择不超过 50 MB 的 GLB');
      }
      final bytes = file.bytes!;
      if (_key != null) {
        if (sha256.convert(bytes).toString() != _sourceHash) {
          throw const WebPublicationException('source_changed');
        }
        setState(() {
          _bytes = bytes;
          _selected = true;
        });
        return;
      }
      if (!mounted) return;
      final route = MaterialPageRoute<WebPublicationSelectionResult>(
        builder: (context) =>
            widget.selectionBuilderForTesting?.call(context, bytes) ??
            WebPublicationSelectionPage(bytes: bytes),
      );
      _selectionRoute = route;
      final selection = await Navigator.of(context).push(route);
      _selectionRoute = null;
      if (!_current || selection == null) return;
      setState(() {
        _bytes = bytes;
        _selection = selection.box?.toJson();
        _selected = true;
      });
    } catch (_) {
      if (_current) setState(() => _message = '文件或模型选区不可用，请选择有效 GLB');
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_current || _bytes == null || !_selected || _busy) return;
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
        title: _title.text,
        description: _description.text,
        idempotencyKey: _key!,
        selectionBox: _selection,
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
    try {
      final status = await _service.getStatus(_submission!);
      if (!_current) return;
      setState(() {
        _status = status;
        _message = null;
      });
      _schedule();
    } catch (_) {
      if (_current) setState(() => _message = '状态查询暂不可用，请点击刷新状态');
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _auth?.cancel();
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
    'not_qualified' => '未达到发布要求',
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
                  OutlinedButton.icon(
                    onPressed:
                        _busy ||
                            (_submission != null &&
                                _status?.status != 'uploading')
                        ? null
                        : _pick,
                    icon: const Icon(Icons.upload_file),
                    label: Text(_selected ? '重新选择 GLB / 调整选区' : '选择 GLB'),
                  ),
                  if (_selected)
                    Text(_selection == null ? '保留整个模型' : '已确认模型选区'),
                  TextField(
                    controller: _title,
                    enabled: !_busy && _key == null,
                    decoration: const InputDecoration(labelText: '标题（1–100 字）'),
                  ),
                  TextField(
                    controller: _description,
                    enabled: !_busy && _key == null,
                    decoration: const InputDecoration(labelText: '描述（最多 30 字）'),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed:
                        !_busy &&
                            _selected &&
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
                    TextButton(
                      onPressed: _busy ? null : _checkStatus,
                      child: const Text('刷新状态'),
                    ),
                  if (_submission != null && _status?.isTerminal != true)
                    TextButton(
                      onPressed: _current && !_busy ? _cancelSubmission : null,
                      child: const Text('取消本次提交'),
                    ),
                  if (_status?.isTerminal == true)
                    TextButton(
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
