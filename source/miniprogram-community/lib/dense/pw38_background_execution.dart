import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../official_util/device_log.dart';

typedef Pw38BackgroundCall =
    Future<Object?> Function(String method, Map<String, Object?> arguments);

final class Pw38BackgroundReport {
  const Pw38BackgroundReport(this.captureDir, this.status, {this.reason});
  final String captureDir, status;
  final String? reason;
  bool get granted => status == 'active';
  String? get notice => switch (status) {
    'active' || 'completed' => null,
    'submitted' => '已申请后台处理，等待系统确认',
    'expired' => '系统已结束后台许可，请回到 App 继续处理',
    'unsupported' => '当前设备未提供所需后台处理能力，请保持 App 前台',
    _ => '后台处理许可未确认，请保持 App 前台',
  };
}

final class Pw38BackgroundLease {
  static int _nextAttempt = 0;
  Pw38BackgroundLease(this.captureDir)
    : jobId =
          'pw38:${DateTime.now().microsecondsSinceEpoch}:${_nextAttempt++}:$captureDir',
      report = Pw38BackgroundReport(captureDir, 'pending');
  final String captureDir, jobId;
  final _ready = Completer<Pw38BackgroundLease>();
  Pw38BackgroundReport report;
  bool ownedByRun = false, ended = false;
  Future<void> _updates = Future<void>.value();
  bool _refreshing = false;
  String? _lastProgress;
  int _completedStages = 0;
}

/// Owns OS lifetime independently of a page. This never changes a numerical
/// backend or claims that a submitted OS request is an execution grant.
final class Pw38BackgroundCoordinator with WidgetsBindingObserver {
  Pw38BackgroundCoordinator({
    required Pw38BackgroundCall call,
    this.pollInterval = const Duration(seconds: 3),
  }) : _call = call;
  static final instance = Pw38BackgroundCoordinator(call: _platformCall);
  static const _channel = MethodChannel('pocketworld_official_arkit');
  static Future<Object?> _platformCall(
    String method,
    Map<String, Object?> args,
  ) async {
    if (!Platform.isIOS) {
      return {
        'schema': 'PW38_BACKGROUND_V1',
        'job_id': args['jobId'],
        'status': 'unsupported',
        'reason': 'platform_adapter_unavailable',
      };
    }
    return _channel.invokeMethod<Object?>(method, args);
  }

  final Pw38BackgroundCall _call;
  final Duration pollInterval;
  final state = ValueNotifier<Pw38BackgroundReport?>(null);
  final _leases = <String, Pw38BackgroundLease>{};
  Timer? _poller;
  bool _observing = false;

  Future<Pw38BackgroundLease> reserve(String captureDir) {
    final old = _leases[captureDir];
    if (old != null && !old.ended) return old._ready.future;
    final lease = Pw38BackgroundLease(captureDir);
    _leases[captureDir] = lease;
    unawaited(_acquire(lease));
    return lease._ready.future;
  }

  Future<void> _acquire(Pw38BackgroundLease lease) async {
    await _read(lease, 'beginFull38Background', extra: {'requiresGPU': true});
    lease._ready.complete(lease);
    if (!_observing && pollInterval > Duration.zero) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    if (pollInterval > Duration.zero &&
        !lease.ended &&
        const {'submitted', 'active'}.contains(lease.report.status)) {
      _poller ??= Timer.periodic(pollInterval, (_) => unawaited(refresh()));
    }
  }

  Future<Pw38BackgroundLease> claim(String captureDir) async {
    final ready = reserve(captureDir);
    final lease = _leases[captureDir]!;
    if (lease.ended || !identical(_leases[captureDir], lease)) {
      throw StateError('后台任务预约已结束，保留本地输入');
    }
    if (lease.ownedByRun) throw StateError('完整38任务已有运行所有者');
    lease.ownedByRun = true;
    await ready;
    return lease;
  }

  Future<void> abandonBeforeStart(String captureDir) async {
    final lease = _leases[captureDir];
    if (lease == null || lease.ownedByRun) return;
    await finish(lease, success: false);
  }

  Future<void> finish(
    Pw38BackgroundLease lease, {
    required bool success,
  }) async {
    if (lease.ended) return;
    lease.ended = true;
    await lease._ready.future;
    await lease._updates;
    await _read(
      lease,
      'endFull38Background',
      extra: {'success': success},
      terminal: true,
    );
    if (identical(_leases[lease.captureDir], lease))
      _leases.remove(lease.captureDir);
    if (_leases.isEmpty) {
      _poller?.cancel();
      _poller = null;
      if (_observing) WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  void update(Pw38BackgroundLease lease, String phase, int done, int total) {
    if (lease.ended ||
        !lease.ownedByRun ||
        !identical(_leases[lease.captureDir], lease))
      return;
    final key = '$phase:$done:$total';
    if (key == lease._lastProgress) return;
    lease._lastProgress = key;
    const stages = {
      'mvs768',
      'mvs1536',
      'cer',
      'fusionPly',
      'tsdf',
      'trim',
      'meshopt',
      'lagrange',
      'texture',
      'avVisibility',
      'avSfmToAbc',
      'avNormal',
      'glb',
      'done',
    };
    if (total == 13 && stages.contains(phase)) {
      lease._completedStages = done.clamp(lease._completedStages, 13);
    }
    final completed = lease._completedStages;
    lease._updates = lease._updates.then((_) async {
      if (!identical(_leases[lease.captureDir], lease)) return;
      await _read(
        lease,
        'updateFull38Background',
        extra: {
          'completedStages': completed,
          'phase': phase,
          'done': done.clamp(0, 0x7fffffff),
          'total': total.clamp(0, 0x7fffffff),
        },
      );
    });
  }

  Future<void> refresh() async {
    for (final lease in _leases.values.toList()) {
      if (lease.ended || lease._refreshing) continue;
      lease._refreshing = true;
      try {
        await _read(lease, 'full38BackgroundStatus');
      } finally {
        lease._refreshing = false;
      }
    }
  }

  Future<void> _read(
    Pw38BackgroundLease lease,
    String method, {
    Map<String, Object?> extra = const {},
    bool terminal = false,
  }) async {
    Object? result;
    String? reason;
    try {
      result = await _call(method, {
        'jobId': lease.jobId,
        ...extra,
      }).timeout(const Duration(seconds: 5));
    } catch (error) {
      reason = '$error';
    }
    if (!identical(_leases[lease.captureDir], lease) ||
        (lease.ended && !terminal))
      return;
    const statuses = {
      'unsupported',
      'rejected',
      'submitted',
      'active',
      'expired',
      'completed',
    };
    final valid =
        result is Map &&
        result['schema'] == 'PW38_BACKGROUND_V1' &&
        result['job_id'] == lease.jobId &&
        statuses.contains(result['status']);
    final report = Pw38BackgroundReport(
      lease.captureDir,
      valid ? (result as Map)['status'] as String : 'rejected',
      reason: valid && (result as Map)['reason'] is String
          ? result['reason'] as String
          : reason ?? (valid ? null : 'unverified_native_response'),
    );
    final previous = lease.report;
    lease.report = report;
    if (previous.status != report.status || previous.reason != report.reason) {
      DeviceLog.log(
        'Full38Background',
        'status=${report.status} reason=${report.reason ?? "none"}',
      );
    }
    state.value = report;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @visibleForTesting
  void dispose() {
    _poller?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _observing = false;
    state.dispose();
  }
}
