import 'dart:io';

import 'package:flutter/services.dart';

import 'archive_background_scheduler.dart';
import 'photo_archive_coordinator.dart';

class MethodChannelArchiveBackgroundScheduler
    implements ArchiveBackgroundScheduler {
  const MethodChannelArchiveBackgroundScheduler({required this.channel});

  final MethodChannel channel;

  @override
  Future<void> cancelScheduled() =>
      channel.invokeMethod<void>('cancelScheduled');

  @override
  Future<void> schedule() => channel.invokeMethod<void>('schedule');
}

class OfficialArchiveBackgroundRuntime {
  OfficialArchiveBackgroundRuntime({
    required this.channel,
    required this.coordinator,
    required this.documentsDirectory,
    this.coordinatorProvider,
  });

  final MethodChannel channel;
  final PhotoArchiveCoordinator coordinator;
  final PhotoArchiveCoordinator Function()? coordinatorProvider;
  final Future<Directory> Function() documentsDirectory;
  final Set<PhotoArchiveCoordinator> _running = {};
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    channel.setMethodCallHandler(_handleNativeCall);
    try {
      await channel.invokeMethod<void>('ready');
    } on MissingPluginException {
      // Non-iOS platforms continue with immediate in-process archive work.
    } on PlatformException {
      // Native scheduling is an execution opportunity, not a data-safety gate.
    }
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'runColdArchive':
        // Resolve both dependencies synchronously before the first await.
        // The provider and directory future then refer to one account only.
        final coordinator = coordinatorProvider?.call() ?? this.coordinator;
        _running.add(coordinator);
        try {
          final documents = await documentsDirectory();
          await coordinator.discoverUnderDocuments(
            documents,
            trigger: 'bg_processing',
          );
          return <String, Object?>{
            'success': true,
            'work_remaining': coordinator.hasPendingWork,
          };
        } catch (_) {
          return <String, Object?>{
            'success': false,
            'work_remaining': coordinator.hasPendingWork,
          };
        } finally {
          _running.remove(coordinator);
        }
      case 'cancelColdArchive':
        for (final running in _running) {
          running.requestSystemInterruption();
        }
        return const <String, Object?>{'accepted': true};
      default:
        throw MissingPluginException(
          'Unknown official archive background method ${call.method}',
        );
    }
  }
}
