import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

import '../me/scan_record_store.dart';

import 'archive_audit_store.dart';
import 'archive_background_runtime.dart';
import 'database_archive_codec.dart';
import 'database_archive_ffi_codec.dart';
import 'database_archive_ffi_preprocessor.dart';
import 'database_archive_preprocessor.dart';
import 'lepton_photo_archive_ffi_codec.dart';
import 'photo_archive_codec.dart';
import 'photo_archive_coordinator.dart';
import 'photo_archive_ffi_codec.dart';
import 'photo_archive_policy.dart';

final PhotoArchiveCodec photoArchiveCodec = LeptonFfiPhotoArchiveCodec();
final PhotoArchiveCodec legacyJxlPhotoArchiveCodec = JxlFfiPhotoArchiveCodec();
final Map<String, PhotoArchiveCodec> photoArchiveCodecsByName =
    <String, PhotoArchiveCodec>{
      PhotoArchivePolicy.leptonCodec: photoArchiveCodec,
      PhotoArchivePolicy.jpegXlCodec: legacyJxlPhotoArchiveCodec,
    };
final DatabaseArchiveCodec databaseArchiveCodec = ZpaqFfiDatabaseArchiveCodec();
final DatabaseArchivePreprocessor databaseArchivePreprocessor =
    TrackDeltaFfiDatabaseArchivePreprocessor();

const MethodChannel officialArchiveBackgroundChannel = MethodChannel(
  'pocketworld_official_archive_background',
);
final MethodChannelArchiveBackgroundScheduler archiveBackgroundScheduler =
    MethodChannelArchiveBackgroundScheduler(
      channel: officialArchiveBackgroundChannel,
    );
final _archiveRuntimes = Expando<_AccountArchiveRuntime>();

class _AccountArchiveRuntime {
  _AccountArchiveRuntime(this.store, {PhotoArchiveCodec? codec}) {
    audit = OfficialArchiveAuditStore(
      documentsDirectory: store.accountDocumentsDirectory,
    );
    coordinator = _AccountArchiveCoordinator(store, audit, codec: codec);
    store.addRevocationListener(coordinator.requestSystemInterruption);
  }
  final ScanRecordStore store;
  late final OfficialArchiveAuditStore audit;
  late final PhotoArchiveCoordinator coordinator;
}

_AccountArchiveRuntime _archiveRuntimeFor(ScanRecordStore store) {
  return _archiveRuntimes[store] ??= _AccountArchiveRuntime(store);
}

PhotoArchiveCoordinator photoArchiveCoordinatorFor(ScanRecordStore store) =>
    _archiveRuntimeFor(store).coordinator;

@visibleForTesting
PhotoArchiveCoordinator createAccountArchiveCoordinatorForTesting(
  ScanRecordStore store, {
  required PhotoArchiveCodec codec,
}) => _AccountArchiveRuntime(store, codec: codec).coordinator;

PhotoArchiveCoordinator get photoArchiveCoordinator =>
    photoArchiveCoordinatorFor(ScanRecordStore.instance);

OfficialArchiveAuditStore get officialArchiveAuditStore =>
    _archiveRuntimeFor(ScanRecordStore.instance).audit;

class _AccountArchiveCoordinator extends PhotoArchiveCoordinator {
  _AccountArchiveCoordinator(
    this.store,
    OfficialArchiveAuditStore audit, {
    PhotoArchiveCodec? codec,
  }) : super(
         codec: codec ?? photoArchiveCodec,
         codecsByName: codec == null
             ? photoArchiveCodecsByName
             : {PhotoArchivePolicy.leptonCodec: codec},
         databaseCodec: databaseArchiveCodec,
         databasePreprocessor: databaseArchivePreprocessor,
         backgroundScheduler: archiveBackgroundScheduler,
         auditStore: audit,
         isWorkspaceActive: () => store.isActive,
       );

  final ScanRecordStore store;

  @override
  PhotoArchiveActivityLease beginReconstructionActivity(
    Directory captureDirectory,
  ) {
    // Native reconstruction is process-wide, so it still preempts cold work.
    // Its completion may enqueue only a path owned by this frozen account.
    final activity = super.beginProcessingActivity();
    final owned = _ownsCapture(captureDirectory);
    return PhotoArchiveActivityLease(() async {
      await activity.close();
      if (await owned) await noteArtifactsPersisted(captureDirectory);
    });
  }

  Future<bool> _ownsCapture(Directory captureDirectory) async {
    try {
      await store.requireOwnedPath(captureDirectory.path);
      return store.isActive;
    } on StateError {
      return false;
    }
  }

  @override
  Future<void> noteArtifactsPersisted(Directory captureDirectory) async {
    if (!store.isActive) return;
    try {
      await store.requireOwnedPath(captureDirectory.path);
    } on StateError {
      // A completed producer can outlive logout. Keep its raw materials;
      // another account must not adopt its archive queue or audit entries.
      return;
    }
    await super.noteArtifactsPersisted(captureDirectory);
  }

  @override
  Future<void> discoverUnderDocuments(
    Directory documentsDirectory, {
    String trigger = 'startup',
  }) async {
    final owned = await store.accountDocumentsDirectory();
    if (owned.absolute.path != documentsDirectory.absolute.path) {
      throw StateError('Archive discovery belongs to a different account');
    }
    await store.requireOwnedPath(documentsDirectory.path);
    await super.discoverUnderDocuments(documentsDirectory, trigger: trigger);
  }
}

final OfficialArchiveBackgroundRuntime officialArchiveBackgroundRuntime =
    OfficialArchiveBackgroundRuntime(
      channel: officialArchiveBackgroundChannel,
      coordinator: photoArchiveCoordinator,
      coordinatorProvider: () => photoArchiveCoordinator,
      documentsDirectory: () =>
          ScanRecordStore.instance.accountDocumentsDirectory(),
    );
