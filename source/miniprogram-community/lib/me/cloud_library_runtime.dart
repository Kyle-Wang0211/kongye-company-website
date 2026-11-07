import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cloud_library.dart';
import 'cloud_library_backend.dart';
import 'scan_record_store.dart';

/// Foreground reconciliation using shared Dart TUS uploads and metadata RPCs.
/// After relaunch, the durable journal and protected files recreate the queue.
class CloudLibraryRuntime with WidgetsBindingObserver {
  CloudLibraryRuntime._(this.library) {
    CloudLibrary.attach(library);
    WidgetsBinding.instance.addObserver(this);
    _removeRevocation = library.store.addRevocationListener(dispose);
    _records = library.store.changes.listen((_) => _schedule());
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => _schedule());
    _schedule();
  }
  static CloudLibraryRuntime? _current;
  static void bind(
    ScanRecordStore store,
    SupabaseClient client, {
    CloudLibraryBackend? backend,
  }) {
    detach();
    if (!store.isActive) return;
    _current = CloudLibraryRuntime._(
      CloudLibrary(
        store: store,
        backend:
            backend ??
            SupabaseCloudLibraryBackend(store: store, client: client),
      ),
    );
  }

  static void detach() {
    _current?.dispose();
    _current = null;
    CloudLibrary.attach(null);
  }

  final CloudLibrary library;
  StreamSubscription<dynamic>? _records;
  Timer? _timer, _debounce;
  late final void Function() _removeRevocation;
  bool _disposed = false;
  bool _foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  void _schedule() {
    if (_disposed ||
        !_foreground ||
        !library.isActive ||
        _debounce?.isActive == true) {
      return;
    }
    _debounce = Timer(const Duration(seconds: 2), () {
      if (!_disposed && _foreground && library.isActive) {
        unawaited(library.synchronize());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _schedule();
    } else {
      _debounce?.cancel();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _debounce?.cancel();
    _records?.cancel();
    _removeRevocation();
    WidgetsBinding.instance.removeObserver(this);
    library.dispose();
  }
}
