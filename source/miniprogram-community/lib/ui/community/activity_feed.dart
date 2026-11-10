import 'dart:async';

import 'package:flutter/material.dart';

import '../../community/activity_repository.dart';

typedef ActivityLoader = Future<List<CommunityActivity>> Function();
typedef ActivityFeedBuilder =
    Widget Function(
      BuildContext context,
      List<CommunityActivity> entries,
      Future<void> Function() refresh,
    );

/// Owns catalog requests independently of work-feed requests and preserves the
/// last complete published snapshot on transport/validation errors.
class ActivityCatalogController extends ChangeNotifier {
  ActivityCatalogController(this.load);
  final ActivityLoader load;
  List<CommunityActivity> entries = const [];
  Object? error;
  bool _disposed = false;
  int _generation = 0;

  Future<void> refresh() async {
    if (_disposed) return;
    final generation = ++_generation;
    try {
      final result = await load();
      if (_disposed || generation != _generation) return;
      entries = List.unmodifiable(result);
      error = null;
    } catch (failure) {
      if (_disposed || generation != _generation) return;
      error = failure;
    }
    if (!_disposed && generation == _generation) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}

class ActivityFeed extends StatefulWidget {
  const ActivityFeed({
    super.key,
    required this.builder,
    this.load,
    this.isVisible = true,
  });
  final ActivityFeedBuilder builder;
  final ActivityLoader? load;
  final bool isVisible;
  @override
  State<ActivityFeed> createState() => _ActivityFeedState();
}

class _ActivityFeedState extends State<ActivityFeed>
    with WidgetsBindingObserver {
  late final ActivityCatalogController _catalog;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    _catalog = ActivityCatalogController(
      widget.load ?? ActivityRepository().list,
    );
    WidgetsBinding.instance.addObserver(this);
    unawaited(_catalog.refresh());
  }

  @override
  void didUpdateWidget(covariant ActivityFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isVisible && widget.isVisible) unawaited(_catalog.refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed && !_foreground && widget.isVisible) {
      unawaited(_catalog.refresh());
    }
    _foreground = resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _catalog.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _catalog,
    builder: (context, _) =>
        widget.builder(context, _catalog.entries, _catalog.refresh),
  );
}
