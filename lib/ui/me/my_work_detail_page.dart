// MyWorkDetailPage — full-screen viewer for one of the user's OWN scans,
// plus the publish-to-community workflow.
//
// ── 2026-08-16 ───────────────────────────────────────────────────────
//
// (1) It shows the scan again. The page rendered `record.artifactPath`,
//     which only the GLB-import path ever sets — the official capture
//     route leaves `$captureDir/official_sfm_sparse.ply` and never
//     touches artifactPath, so every real scan fell through to the
//     "processing" placeholder forever. Sparse clouds now render through
//     the shared renderer, identical to final GLBs and the web viewer.
//     Durable final models take precedence over sparse data on re-entry.
//
// (2) Publication submits only the verified final GLB to the private review
// queue. Submission progress is persisted separately from cloudWorkId; only
// an owner-scoped server status may attach an actually public work identity.
// The existing sparse loader remains available for local viewing.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';

import '../../community/community_service.dart';
import '../../dense/dense_work_state.dart';
import '../../dense/pw38_final_record_artifact.dart';
import '../../dense/pw38_capture_retirement.dart';
import '../../pw38/final_artifact_completion.dart';
import '../../community/publish_service.dart';
import '../../l10n/app_localizations.dart';
import '../../me/scan_record_store.dart';
import '../community/aether_cpp_card_demo.dart';
import '../design_system.dart';
import '../final_mesh_thumbnail.dart';
import '../shared/product_model_view.dart';
import '../shared/product_preview_cover.dart';
import '../shared/local_work_viewer_session.dart';
import '../sparse_thumbnail.dart' show sparseThumbPathFor;
import '../official_capture/auto_rotating_cloud_view.dart';
import '../official_capture/sparse_cloud_viewer_page.dart' show SparseCloudData;
import '../scan_record.dart';

/// Rendering priority is independent of asynchronous sparse loading. A full
/// original38 proof outranks a durable attachment; local legacy attachments
/// must still have an actual GLB2 header and matching declared file length.
/// The original38 byte/integrity verifier remains the authority for run proof.
String? myWorkModelUrl(ScanRecord record, {String? verifiedGlbPath}) {
  if (verifiedGlbPath != null) return Uri.file(verifiedGlbPath).toString();
  if (hasPw38FinalRecordProof(record)) return null;
  final reference = record.artifactPath;
  if (reference == null || reference.isEmpty) return null;
  final uri = Uri.tryParse(reference);
  if (uri != null && const {'https', 'http', 'asset'}.contains(uri.scheme)) {
    return reference;
  }
  RandomAccessFile? input;
  try {
    final path = uri?.scheme == 'file' ? uri!.toFilePath() : reference;
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    input = File(path).openSync();
    final length = input.lengthSync();
    final bytes = input.readSync(12);
    if (length < 20 || bytes.length != 12) return null;
    final header = ByteData.sublistView(bytes);
    if (header.getUint32(0, Endian.little) != 0x46546c67 ||
        header.getUint32(4, Endian.little) != 2 ||
        header.getUint32(8, Endian.little) != length) {
      return null;
    }
    return Uri.file(path).toString();
  } catch (_) {
    return null;
  } finally {
    input?.closeSync();
  }
}

/// Store emits for sync, titles and viewed-result badges as well as new output.
/// Those metadata events must not replace an already selected local final model.
bool myWorkModelSourceChanged(ScanRecord previous, ScanRecord next) =>
    previous.id != next.id ||
    previous.accountNamespace != next.accountNamespace ||
    (!hasPw38FinalRecordProof(previous) &&
        previous.captureDir != next.captureDir) ||
    previous.pipelineKind != next.pipelineKind ||
    previous.cloudLibraryRevision != next.cloudLibraryRevision ||
    previous.artifactPath != next.artifactPath ||
    previous.finalGlbSha256 != next.finalGlbSha256 ||
    previous.finalGlbBytes != next.finalGlbBytes;

/// The frame may finish after a same-path GLB replacement. Its cover must still
/// belong to the exact generation selected before the renderer was dispatched.
bool myWorkFinalCoverStillCurrent(
  ScanRecord current,
  String modelUrl,
  FinalMeshThumbnailIdentity dispatched,
) =>
    finalMeshThumbnailIdentity(current, modelUrl: modelUrl)?.token ==
    dispatched.token;

/// Persisted progress never treats a private submission as a public work.
String? myWorkPublicationLabel(ScanRecord record) =>
    switch (record.publicationStatus) {
      'uploading' => '上传中',
      'queued' || 'rendering' || 'processing' => '处理中',
      'awaiting_review' => '等待人工审核',
      'published' => record.cloudWorkId == null ? '正在核对发布状态' : '已公开',
      'rejected' => '审核未通过',
      'failed' || 'not_qualified' => '未达标',
      'unpublished' => '当前未公开',
      'cancelled' => '已取消',
      _ => record.publicationSubmissionId != null ? '正在核对发布状态' : null,
    };

bool _publicationPending(ScanRecord record) =>
    record.publicationSubmissionId != null &&
    (record.publicationStatus == 'published' && record.cloudWorkId == null ||
        !const {
          'published',
          'rejected',
          'failed',
          'not_qualified',
          'cancelled',
          'unpublished',
        }.contains(record.publicationStatus));

class MyWorkDetailPage extends StatefulWidget {
  final String recordId;

  const MyWorkDetailPage({
    super.key,
    required this.recordId,
    @visibleForTesting this.storeForTesting,
    @visibleForTesting this.verifyCompletionForTesting,
    @visibleForTesting this.hostBuilderForTesting,
    @visibleForTesting this.publicationStatusForTesting,
  });
  final ScanRecordStore? storeForTesting;
  final Future<GlbPublicationStatus> Function(String)?
  publicationStatusForTesting;
  final Future<void> Function(String)? verifyCompletionForTesting;
  // ignore: invalid_use_of_visible_for_testing_member
  final ProductModelHostBuilder? hostBuilderForTesting;

  @override
  State<MyWorkDetailPage> createState() => _MyWorkDetailPageState();
}

class _MyWorkDetailPageState extends State<MyWorkDetailPage> {
  late final ScanRecordStore _store =
      widget.storeForTesting ?? ScanRecordStore.instance;
  StreamSubscription<List<ScanRecord>>? _sub;
  ScanRecord? _record;

  String? _loadedPlyPath;
  String? _modelUrl;
  int _recordGeneration = 0;
  String? _coverRequestedFor;
  final _retirementCoverWriter = ProductPreviewCoverWriter();
  String? _retirementCoverRequestedFor;
  String? _openingSourceGeneration;
  String? _openingPreviewPath;

  Pw38FinalArtifactCompletionProof? _finalArtifactProof;

  Timer? _publicationPoll;
  bool _refreshingPublication = false;
  bool _publishing = false;
  double _publishFraction = 0;

  /// Server-side moderation state for an already-published work.
  /// null = unknown / not published / lookup failed.
  String? _moderationStatus;

  @override
  void initState() {
    super.initState();
    _record = _store.byId(widget.recordId);
    if (_record != null) _modelUrl = _preferredModelUrl(_record!);
    _sub = _store.changes.listen((_) {
      final fresh = _store.byId(widget.recordId);
      if (mounted && fresh != null) {
        final sourceChanged =
            _record == null || myWorkModelSourceChanged(_record!, fresh);
        setState(() {
          _record = fresh;
          if (sourceChanged) {
            _recordGeneration++;
            _finalArtifactProof = null;
            _modelUrl = _preferredModelUrl(fresh);
            _loadedPlyPath = null;
          }
        });
        if (sourceChanged) {
          unawaited(_verifyCompletedModel().whenComplete(_maybeLoadCloud));
        }
      }
    });
    unawaited(_verifyCompletedModel().whenComplete(_maybeLoadCloud));
    // The existing displayed Viewer supplies a missing final PNG before the
    // same record's pending cleanup is resumed from its first-frame callback.
    unawaited(_refreshModerationStatus());
    unawaited(_refreshPublicationStatus());
    _publicationPoll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted &&
          ModalRoute.of(context)?.isCurrent == true &&
          _record != null &&
          _publicationPending(_record!)) {
        unawaited(_refreshPublicationStatus());
      }
    });
  }

  String? _preferredModelUrl(ScanRecord record) {
    if (hasPw38FinalRecordProof(record)) {
      final proof = _finalArtifactProof;
      return proof != null && pw38FinalRecordProofMatches(record, proof)
          ? Uri.file(proof.publishedGlb).toString()
          : null;
    }
    final capture = record.captureDir;
    final artifact = capture == null
        ? null
        : verifiedPw38CacheArtifact(capture);
    return myWorkModelUrl(
      record,
      verifiedGlbPath: artifact?.recordId == record.id
          ? artifact?.glbPath
          : null,
    );
  }

  void _modelDisplayed(ScanResultViewRevision revision, String renderedUrl) {
    final renderedRecord = revision.record;
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        _record?.id != renderedRecord.id ||
        _record?.captureDir != renderedRecord.captureDir ||
        _modelUrl != renderedUrl) {
      return;
    }
    // Consume only the result that actually reached a first model frame. The
    // store checks the immutable result revision again before persisting it.
    unawaited(
      _store.markResultViewed(renderedRecord, revision: revision).catchError((
        Object error,
      ) {
        debugPrint(
          '[MyWorkDetailPage] result acknowledgement unavailable: $error',
        );
      }),
    );
  }

  Future<void> _verifyCompletedModel() async {
    final r = _record;
    if (r == null) return;
    final generation = _recordGeneration;
    if (hasPw38FinalRecordProof(r)) {
      try {
        final proof = await verifyPw38FinalRecordArtifact(_store, r);
        if (!mounted ||
            generation != _recordGeneration ||
            _record?.id != r.id ||
            !pw38FinalRecordProofMatches(_record!, proof)) {
          return;
        }
        setState(() {
          _finalArtifactProof = proof;
          _modelUrl = Uri.file(proof.publishedGlb).toString();
          _loadedPlyPath = null;
        });
      } catch (error) {
        if (mounted && generation == _recordGeneration) {
          setState(() {
            _finalArtifactProof = null;
            _modelUrl = null;
            _loadedPlyPath = null;
          });
        }
        debugPrint('[MyWorkDetailPage] final artifact unavailable: $error');
      }
      return;
    }
    final capture = r.captureDir;
    if (capture == null) return;
    try {
      final verifyForTesting = widget.verifyCompletionForTesting;
      if (verifyForTesting != null) {
        await verifyForTesting(capture);
      } else {
        await verifyDenseWorkStateOf(capture);
      }
    } catch (error) {
      debugPrint('[MyWorkDetailPage] model proof unavailable: $error');
      return;
    }
    if (!mounted ||
        generation != _recordGeneration ||
        _record?.id != r.id ||
        _record?.captureDir != capture) {
      return;
    }
    final artifact = verifiedPw38CacheArtifact(capture);
    if (artifact == null || artifact.recordId != r.id) return;
    setState(() {
      _modelUrl = myWorkModelUrl(r, verifiedGlbPath: artifact.glbPath);
      _loadedPlyPath = null;
    });
  }

  /// The local record only knows "I was published once" (`cloudWorkId`).
  /// It cannot know the work was later taken down, so without this the
  /// author sees "已发布" while the work is invisible to everyone else.
  /// Best-effort: failure leaves the plain published state.
  Future<void> _refreshModerationStatus() async {
    final workId = _record?.cloudWorkId;
    if (workId == null) return;
    final status = await CommunityService().fetchMyWorkModerationStatus(workId);
    if (!mounted || status == null) return;
    setState(() => _moderationStatus = status);
  }

  @override
  void dispose() {
    _publicationPoll?.cancel();
    _sub?.cancel();
    _retirementCoverWriter.invalidate();
    super.dispose();
  }

  /// Persisted PLY goes directly to the existing shared loader. Do not parse
  /// it into Dart arrays only to encode it back into PLY for that same loader.
  Future<void> _maybeLoadCloud() async {
    final r = _record;
    if (!mounted ||
        r == null ||
        _modelUrl != null ||
        hasPw38FinalRecordProof(r)) {
      return;
    }
    final ply = PublishService.sparsePlyFor(r);
    if (ply == null) return;
    try {
      final path = ply.resolveSymbolicLinksSync();
      if (path != _loadedPlyPath) setState(() => _loadedPlyPath = path);
    } catch (error) {
      debugPrint('[MyWorkDetailPage] local point source unavailable: $error');
    }
  }

  void _captureFinalCover(
    String renderedUrl,
    ProductViewerCapture viewer,
    ScanRecord renderedRecord,
    ScanResultViewRevision revision,
    FinalMeshThumbnailIdentity identity,
  ) {
    if (hasPw38FinalRecordProof(renderedRecord)) return;
    if (!mounted ||
        !_store.isActive ||
        _modelUrl != renderedUrl ||
        _coverRequestedFor == identity.token) {
      return;
    }
    bool isCurrent() {
      if (!mounted || !_store.isActive || _modelUrl != renderedUrl) {
        return false;
      }
      final current = _store.byId(renderedRecord.id);
      return current != null &&
          current.accountNamespace == renderedRecord.accountNamespace &&
          myWorkFinalCoverStillCurrent(current, renderedUrl, identity);
    }

    if (!isCurrent()) return;
    _coverRequestedFor = identity.token;
    unawaited(
      ensureFinalMeshThumbnail(
        record: renderedRecord,
        modelUrl: renderedUrl,
        capture: () => viewer.captureThumb(),
        isCurrent: isCurrent,
        attach: (path) => _store.attachFinalMeshThumbnail(
          revision: revision,
          thumbnailPath: path,
        ),
      ).catchError((Object error) {
        debugPrint('[MyWorkDetailPage] final cover unavailable: $error');
        return null;
      }),
    );
  }

  void _captureRetirementCover(
    ScanRecord renderedRecord,
    String renderedUrl,
    SharedViewerController controller,
  ) {
    if (!hasPw38FinalRecordProof(renderedRecord)) return;
    unawaited(() async {
      try {
        final proof = await verifyPw38FinalRecordArtifact(_store, renderedRecord);
        final artifactIdentity = '${proof.publishedGlb}:${renderedRecord.finalGlbSha256}';
        if (_retirementCoverRequestedFor == artifactIdentity) return;
        bool current() {
          final record = _store.byId(renderedRecord.id);
          return mounted && _store.isActive && _modelUrl == renderedUrl &&
              record != null && pw38FinalRecordProofMatches(record, proof);
        }
        if (!current()) return;
        _retirementCoverRequestedFor = artifactIdentity;
        final capture = renderedRecord.captureDir;
        if (renderedRecord.finalCoverSha256 == null && capture != null) {
          final source = ProductPreviewCoverSource(
            accountNamespace: renderedRecord.accountNamespace,
            workId: renderedRecord.id,
            captureDir: capture,
            runId: renderedRecord.id,
            stage: 'glb',
            artifactIdentity: artifactIdentity,
          );
          _retirementCoverWriter.select(source);
          final image = await _retirementCoverWriter.capture(
            source: source,
            controller: controller,
            isCurrent: current,
            attach: (path) => _store.attachPreviewThumbnail(
              expected: renderedRecord,
              thumbnailPath: path,
              isCurrent: current,
            ),
          );
          if (image == null) return;
        }
        if (!current()) return;
        final retirement = Pw38CaptureRetirement(
          store: _store,
          drainPipelineReaders: () async {},
        );
        await retirement.resumePending(renderedRecord.id);
        await retirement.waitForCompletion(renderedRecord.id);
      } catch (error) {
        debugPrint('[MyWorkDetailPage] final PNG/retirement pending: $error');
      }
    }());
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _samePublicationOwner(ScanRecord original) {
    final current = _store.byId(original.id);
    return _store.isActive &&
        current != null &&
        current.accountNamespace == original.accountNamespace &&
        current.captureDir == original.captureDir;
  }

  Future<void> _applyPublicationStatus(
    ScanRecord original,
    GlbPublicationStatus status,
  ) async {
    if (!_samePublicationOwner(original)) return;
    final current = _store.byId(original.id)!;
    if (current.publicationSubmissionId != status.submissionId) return;
    final updated = current.copyWith(
      publicationStatus: status.status,
      cloudWorkId: status.status == 'published' ? status.workId : null,
      clearCloudWorkId: status.status != 'published' || status.workId == null,
    );
    await _store.addOrUpdate(updated);
    if (mounted && _store.isActive) {
      setState(() => _record = _store.byId(original.id));
    }
  }

  Future<void> _refreshPublicationStatus() async {
    final r = _record;
    if (_refreshingPublication ||
        r == null ||
        r.publicationSubmissionId == null ||
        !_store.isActive) {
      return;
    }
    _refreshingPublication = true;
    try {
      final status =
          await (widget.publicationStatusForTesting?.call(
                r.publicationSubmissionId!,
              ) ??
              GlbPublicationService().getStatus(r.publicationSubmissionId!));
      await _applyPublicationStatus(r, status);
    } catch (_) {
      // Preserve the last verified state; transient errors grant no visibility.
    } finally {
      _refreshingPublication = false;
    }
  }

  Future<void> _startPublish(ScanRecord r) async {
    if (_publishing || r.cloudWorkId != null) return;
    final form =
        r.publicationIdempotencyKey != null && r.publicationTitle != null
        ? _PublishFormResult(r.publicationTitle!, r.publicationDescription)
        : await showModalBottomSheet<_PublishFormResult>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _PublishForm(defaultTitle: r.name),
          );
    if (form == null || !mounted || !_samePublicationOwner(r)) return;
    setState(() {
      _publishing = true;
      _publishFraction = 0;
    });
    try {
      final String glbPath;
      if (hasPw38FinalRecordProof(r)) {
        final proof = await verifyPw38FinalRecordArtifact(_store, r);
        glbPath = proof.publishedGlb;
      } else {
        final capture = r.captureDir;
        if (capture == null) throw StateError('需要已完成的最终 GLB 模型');
        await verifyDenseWorkStateOf(capture);
        final artifact = verifiedPw38CacheArtifact(capture);
        if (artifact == null || artifact.recordId != r.id) {
          throw StateError('最终 GLB 尚未完成核验');
        }
        glbPath = artifact.glbPath;
      }
      if (!_samePublicationOwner(r)) return;
      var current = _store.byId(r.id)!;
      final requestKey = current.publicationIdempotencyKey ?? const Uuid().v4();
      await _store.addOrUpdate(
        current.copyWith(
          publicationIdempotencyKey: requestKey,
          publicationTitle: form.title,
          publicationDescription: form.description ?? '',
        ),
      );
      if (!_samePublicationOwner(r)) return;
      final result = await GlbPublicationService().submit(
        recordId: r.id,
        glbPath: glbPath,
        title: form.title,
        description: form.description ?? '',
        idempotencyKey: requestKey,
        onSubmissionCreated: (id) async {
          if (!_samePublicationOwner(r)) throw StateError('账号已切换');
          current = _store.byId(r.id)!;
          await _store.addOrUpdate(
            current.copyWith(
              publicationSubmissionId: id,
              publicationStatus: 'uploading',
            ),
          );
          if (mounted) setState(() => _record = _store.byId(r.id));
        },
        onProgress: (_, fraction) {
          if (mounted) setState(() => _publishFraction = fraction);
        },
      );
      await _applyPublicationStatus(r, result);
      if (mounted) _snack(myWorkPublicationLabel(_record!) ?? '已提交审核');
    } catch (_) {
      if (mounted) _snack('提交未完成，请稍后重试');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final r = _record;
    if (r == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(backgroundColor: Colors.white, elevation: 0),
        body: Center(child: Text(l.meDetailRecordNotFound)),
      );
    }
    final hasCloud = _loadedPlyPath != null;
    // Black behind a point cloud, white behind the legacy GLB viewer —
    // matches the drafts viewer and the community detail page.
    final dark = _modelUrl != null || hasCloud;
    final fg = dark ? Colors.white : AetherColors.textPrimary;

    return Scaffold(
      backgroundColor: dark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: dark ? Colors.black : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.chevron_left_rounded, color: fg),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          r.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(child: _buildBody(r)),
                _PublishBar(
                  record: r,
                  canPublish: hasPw38FinalRecordProof(r)
                      ? _finalArtifactProof != null &&
                            pw38FinalRecordProofMatches(r, _finalArtifactProof!)
                      : r.captureDir != null &&
                            verifiedPw38CacheArtifact(
                                  r.captureDir!,
                                )?.recordId ==
                                r.id,
                  busy: _publishing,
                  onPublish: () => _startPublish(r),
                  moderationStatus: _moderationStatus,
                ),
              ],
            ),
            if (_publishing) _PublishOverlay(fraction: _publishFraction),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ScanRecord r) {
    final modelUrl = _modelUrl;
    final revision = modelUrl == null
        ? null
        : _store.captureResultViewRevision(r);
    final coverIdentity = modelUrl == null
        ? null
        : finalMeshThumbnailIdentity(r, modelUrl: modelUrl);
    // Keep the opening presentation selected for this actual source generation.
    // A thumbnail arriving later is metadata, not a reason to replace the
    // already mounted renderer with a new wrapper and load the model again.
    final finalGeneration = hasPw38FinalRecordProof(r) && modelUrl != null
        ? 'glb:$modelUrl:final:${r.finalGlbSha256}'
        : null;
    final localBinding = finalGeneration != null
        ? LocalWorkViewerBinding(
            store: _store,
            localPath: modelUrl!,
            generation: finalGeneration,
            publishedRevision: revision,
          )
        : localWorkViewerBindingFor(
            store: _store,
            record: r,
            modelUrl: modelUrl,
            sparsePath: _loadedPlyPath,
          );
    final sourceGeneration = localBinding?.generation;
    if (sourceGeneration != null &&
        sourceGeneration != _openingSourceGeneration) {
      _openingSourceGeneration = sourceGeneration;
      final candidate = modelUrl != null
          ? (hasPw38FinalRecordProof(r)
                ? productPreviewCoverFor(r)?.path
                : finalMeshThumbnailFor(r, modelUrl: modelUrl)?.path)
          : (r.captureDir == null ? null : sparseThumbPathFor(r.captureDir!));
      _openingPreviewPath = candidate != null && File(candidate).existsSync()
          ? candidate
          : null;
    }
    return myWorkViewerFor(
      localWork: localBinding,
      hostBuilderForTesting: widget.hostBuilderForTesting,
      modelGeneration: finalGeneration ?? coverIdentity?.token,
      recordId: r.id,
      modelUrl: modelUrl,
      cloud: null,
      cloudLoading: false,
      sparseSourcePath: _loadedPlyPath,
      previewPath: _openingPreviewPath,
      onViewerReady:
          modelUrl == null || revision == null || coverIdentity == null
          ? null
          : (viewer) => _captureFinalCover(
              modelUrl,
              viewer,
              r,
              revision,
              coverIdentity,
            ),
      onControllerFrameReady: modelUrl == null || !hasPw38FinalRecordProof(r)
          ? null
          : (controller) => _captureRetirementCover(r, modelUrl, controller),
      onModelDisplayed: modelUrl == null || revision == null
          ? null
          : () => _modelDisplayed(revision, modelUrl),
    );
  }
}

Widget myWorkViewerFor({
  required String recordId,
  required String? modelUrl,
  required SparseCloudData? cloud,
  required bool cloudLoading,
  String? sparseSourcePath,
  LocalWorkViewerBinding? localWork,
  String? modelGeneration,
  String? previewPath,
  VoidCallback? onModelDisplayed,
  ValueChanged<ProductViewerCapture>? onViewerReady,
  ValueChanged<SharedViewerController>? onControllerFrameReady,
  // ignore: invalid_use_of_visible_for_testing_member
  ProductModelHostBuilder? hostBuilderForTesting,
}) {
  Widget surface(VoidCallback? firstFrame, ValueChanged<Object>? error) {
    if (modelUrl != null) {
      return AetherCppCardDemo(
        key: ValueKey('mywork-shared-$recordId-$modelUrl-$modelGeneration'),
        modelUrl: modelUrl,
        localWork: localWork,
        interactive: true,
        background: Colors.black,
        onFirstFrameReady: firstFrame,
        onViewerReady: onViewerReady,
        onControllerFrameReady: onControllerFrameReady,
        hostBuilderForTesting: hostBuilderForTesting,
        onError: error,
      );
    }
    if (sparseSourcePath != null || cloud != null) {
      return AutoRotatingCloudView(
        xyz: cloud?.xyz ?? Float32List(0),
        rgb: cloud?.rgb ?? Uint8List(0),
        sourcePath: sparseSourcePath,
        localWork: localWork,
        onFirstFrameReady: firstFrame,
        onError: error,
        logTag: '我的作品',
      );
    }
    if (cloudLoading) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return const _RunningState();
  }

  final preview = previewPath == null ? null : File(previewPath);
  if (preview != null &&
      preview.existsSync() &&
      (modelUrl != null || sparseSourcePath != null || cloud != null)) {
    return LocalWorkOpeningPreview(
      key: ValueKey(
        'mywork-opening-$recordId-${modelUrl ?? sparseSourcePath}-$modelGeneration',
      ),
      thumbnail: preview,
      builder: (frame, error) => surface(() {
        frame();
        onModelDisplayed?.call();
      }, error),
    );
  }
  return surface(onModelDisplayed, null);
}

/// Bottom action bar reflects private submission progress independently from
/// the identity of a published community work.
/// Non-actionable bottom bar for a work whose server-side state takes the
/// publish action away (removed / under review). Same footprint as
/// [_PublishBar] so the page layout doesn't shift.
class _StatusBar extends StatelessWidget {
  final String label;
  final String? hint;
  final Color color;

  const _StatusBar({
    required this.label,
    required this.hint,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AetherSpacing.lg,
        AetherSpacing.md,
        AetherSpacing.lg,
        AetherSpacing.lg,
      ),
      color: Colors.black,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(AetherRadii.md),
              border: Border.all(color: color),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: AetherSpacing.sm),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Colors.white70,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PublishBar extends StatelessWidget {
  final ScanRecord record;
  final bool canPublish;
  final bool busy;
  final VoidCallback onPublish;

  /// Server truth for an already-published work: 'ok' | 'under_review' |
  /// 'removed'. null when unknown — in that case we fall back to the
  /// plain "published" label rather than guessing.
  final String? moderationStatus;

  const _PublishBar({
    required this.record,
    required this.canPublish,
    required this.busy,
    required this.onPublish,
    this.moderationStatus,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final published = record.cloudWorkId != null;
    final publicationLabel = myWorkPublicationLabel(record);
    if (publicationLabel != null) {
      if (record.publicationStatus == 'uploading' && !busy) {
        return Padding(
          padding: const EdgeInsets.all(AetherSpacing.lg),
          child: FilledButton(
            onPressed: onPublish,
            child: const Text('继续提交审核'),
          ),
        );
      }
      return _StatusBar(
        label: publicationLabel,
        hint: null,
        color: AetherColors.textSecondary,
      );
    }

    // A removed work must say so. Showing "已发布" while the work is
    // invisible to everyone else is the confusing state this fixes, and
    // the hint line tells the author how to appeal — which is also what
    // DSA Art.17 expects a takedown notice to carry.
    if (published && moderationStatus == 'removed') {
      return _StatusBar(
        label: l.publishModerationRemoved,
        hint: l.publishModerationRemovedHint,
        color: AetherColors.danger,
      );
    }
    if (published && moderationStatus == 'under_review') {
      return _StatusBar(
        label: l.publishModerationUnderReview,
        hint: null,
        color: AetherColors.textSecondary,
      );
    }

    final String label;
    final VoidCallback? action;
    if (published) {
      label = l.publishAlreadyDone;
      action = null;
    } else if (!canPublish) {
      label = l.publishNotReady;
      action = null;
    } else {
      label = l.publishAction;
      action = busy ? null : onPublish;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AetherSpacing.lg,
        AetherSpacing.md,
        AetherSpacing.lg,
        AetherSpacing.lg,
      ),
      color: Colors.black,
      child: SizedBox(
        height: 48,
        child: FilledButton(
          onPressed: action,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            disabledBackgroundColor: Colors.white24,
            disabledForegroundColor: Colors.white54,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AetherRadii.md),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                published
                    ? Icons.check_circle_rounded
                    : Icons.ios_share_rounded,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PublishFormResult {
  final String title;
  final String? description;
  const _PublishFormResult(this.title, this.description);
}

/// Title + description sheet. Mirrors the DB CHECK constraints
/// (title 1..100, description ≤5000) so a bad payload is stopped here
/// rather than after burning an upload.
class _PublishForm extends StatefulWidget {
  final String defaultTitle;
  const _PublishForm({required this.defaultTitle});

  @override
  State<_PublishForm> createState() => _PublishFormState();
}

class _PublishFormState extends State<_PublishForm> {
  late final TextEditingController _title = TextEditingController(
    text: widget.defaultTitle,
  );
  final TextEditingController _desc = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final titleOk = _title.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(
          AetherSpacing.lg,
          AetherSpacing.md,
          AetherSpacing.lg,
          AetherSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AetherColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AetherSpacing.lg),
            Text(
              l.publishAction,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AetherColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              Localizations.localeOf(context).languageCode == 'zh'
                  ? '提交最终 GLB 模型后，平台生成 26 张多角度审核图，并将标题、描述和审核图交由阿里云进行文字、图片审核。审核图不是拍摄源照片。模型及审核图在审核期间私有保存，通过审核并完成发布后才会公开。'
                  : 'Submit your final GLB model for review. We generate 26 views and send the title, description and rendered images to Alibaba Cloud for text and image checks. These images are not your original capture photos. The model and review images remain private during review; the work becomes public only after approval and publication.',
              style: const TextStyle(
                fontSize: 13,
                color: AetherColors.textSecondary,
              ),
            ),
            const SizedBox(height: AetherSpacing.lg),
            TextField(
              controller: _title,
              maxLength: 100,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l.publishFieldTitle,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AetherSpacing.sm),
            // [UGC-SURFACE 2026-08-23] 描述从 5000 字收到 30 字。
            // 理由不是 UI,是风险面:标题 100 字 + 描述 30 字是本产品仅有的
            // 两个自由文本入口(昵称走白名单池、评论/私信冷启动不开放),
            // 收窄后二者同量级,一次审核预算覆盖两者。
            // ⚠️ 这是客户端软限制,可绕过 —— `works_insert_own` 策略仍允许
            //    authenticated 直接 insert public.works,DB 侧 CHECK 才是
            //    真边界。见 supabase/migrations/*_tighten_description_length。
            TextField(
              controller: _desc,
              maxLength: 30,
              maxLines: 2,
              minLines: 1,
              decoration: InputDecoration(
                labelText: l.publishFieldDescription,
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AetherSpacing.md),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton(
                onPressed: titleOk
                    ? () => Navigator.of(context).pop(
                        _PublishFormResult(
                          _title.text.trim(),
                          _desc.text.trim().isEmpty ? null : _desc.text.trim(),
                        ),
                      )
                    : null,
                child: Text(l.publishConfirm),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal progress. Blocks interaction so the record cannot change under
/// an in-flight publish.
class _PublishOverlay extends StatelessWidget {
  final double fraction;
  const _PublishOverlay({required this.fraction});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AetherRadii.lg),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 120,
                  child: LinearProgressIndicator(
                    value: fraction <= 0 ? null : fraction,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '${AppL10n.of(context).publishInProgress} '
                  '${(fraction * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AetherColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RunningState extends StatelessWidget {
  const _RunningState();

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: AetherSpacing.md),
          Text(l.meDetailRunningProcessing, style: AetherTextStyles.bodySm),
        ],
      ),
    );
  }
}
