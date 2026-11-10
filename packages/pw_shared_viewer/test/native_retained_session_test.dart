// ignore_for_file: depend_on_referenced_packages, invalid_use_of_internal_member
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';

class _FakePlatform extends WebViewPlatform {
  final views = <_FakeController>[];
  Completer<void>? setupGate, disposeGate;
  bool autoReady = true, healthy = true;
  int presentations = 0, nativeParents = 0, parentCollisions = 0;
  bool deferWrapperDetach = false;
  @override
  PlatformWebViewController createPlatformWebViewController(
      PlatformWebViewControllerCreationParams params) {
    final result = _FakeController(params, this);
    views.add(result);
    return result;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
          PlatformNavigationDelegateCreationParams params) =>
      _FakeNavigation(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
          PlatformWebViewWidgetCreationParams params) =>
      _FakeWidget(params, this);
}

class _FakeNavigation extends PlatformNavigationDelegate {
  _FakeNavigation(super.params) : super.implementation();
  WebResourceErrorCallback? error;
  @override
  Future<void> setOnNavigationRequest(
      NavigationRequestCallback callback) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {
    error = callback;
  }
}

class _FakeWidget extends PlatformWebViewWidget {
  _FakeWidget(super.params, this.owner) : super.implementation();
  final _FakePlatform owner;
  @override
  Widget build(BuildContext context) {
    owner.presentations++;
    return _NativeParent(owner: owner);
  }
}

class _NativeParent extends StatefulWidget {
  const _NativeParent({required this.owner});
  final _FakePlatform owner;
  @override
  State<_NativeParent> createState() => _NativeParentState();
}

class _NativeParentState extends State<_NativeParent> {
  @override
  void initState() {
    super.initState();
    if (widget.owner.nativeParents != 0) widget.owner.parentCollisions++;
    widget.owner.nativeParents++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
  @override
  void dispose() {
    final owner = widget.owner;
    if (owner.deferWrapperDetach) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          owner.nativeParents--;
        });
      });
    } else {
      owner.nativeParents--;
    }
    super.dispose();
  }
}

class _FakeController extends PlatformWebViewController {
  _FakeController(super.params, this.owner) : super.implementation();
  final _FakePlatform owner;
  JavaScriptChannelParams? channel;
  _FakeNavigation? navigation;
  final scripts = <String>[];
  int loads = 0;
  Uri? entry;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {
    await owner.setupGate?.future;
  }

  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> setOnConsoleMessage(
      void Function(JavaScriptConsoleMessage message) callback) async {}
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channel = params;
  }

  @override
  Future<void> removeJavaScriptChannel(String name) async {
    channel = null;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
      PlatformNavigationDelegate delegate) async {
    navigation = delegate as _FakeNavigation;
  }

  void ready() => message({
        'protocol': sharedViewerProtocol,
        'type': 'pw-viewer-ready',
        'state': {'status': 'empty'}
      });
  void message(Map<String, Object?> data) =>
      channel?.onMessageReceived(JavaScriptMessage(message: jsonEncode(data)));
  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    loads++;
    entry = params.uri;
    if (owner.autoReady) ready();
  }

  @override
  Future<Object> runJavaScriptReturningResult(String script) async {
    scripts.add(script);
    return owner.healthy;
  }

  @override
  Future<void> runJavaScript(String script) async {
    scripts.add(script);
    if (script.contains('window.pwSharedViewerController?.dispose()')) {
      await owner.disposeGate?.future;
    }
    if (!script.startsWith('window.PWSharedBridge.request(')) return;
    final begin = script.indexOf('(') + 1;
    final end = script.lastIndexOf(').catch');
    final request = jsonDecode(script.substring(begin, end)) as Map;
    message({
      'protocol': sharedViewerProtocol,
      'id': request['id'],
      'ok': true,
      'result': request['method'] == 'getState' ? {'status': 'ready'} : null
    });
  }

  int methods(String name) =>
      scripts.where((s) => s.contains('"method":"$name"')).length;
  int get disposals => scripts
      .where((s) => s.contains('window.pwSharedViewerController?.dispose()'))
      .length;
}

void main() {
  late _FakePlatform platform;
  setUp(() {
    platform = _FakePlatform();
    WebViewPlatform.instance = platform;
  });
  Future<void> flush(WidgetTester tester, [int count = 12]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
    }
  }

  Future<void> close(
      WidgetTester tester, SharedViewerRetainedSession session) async {
    var done = false;
    Object? failure;
    session.dispose().then((_) => done = true, onError: (Object error) {
      failure = error;
      done = true;
    });
    for (var i = 0; i < 60 && !done; i++) {
      await flush(tester, 1);
    }
    expect(failure, isNull);
    expect(done, isTrue, reason: 'Session resource cleanup must complete');
  }

  Widget view(SharedViewerController controller,
          SharedViewerRetainedSession? session,
          {VoidCallback? ready, ValueChanged<Object>? error, Key? key}) =>
      MaterialApp(
          home: SharedViewer(
        key: key,
        controller: controller,
        retainedSession: session,
        onReady: ready,
        onError: error,
      ));

  testWidgets(
      'warm presentation retains the exact native controller and JS document',
      (tester) async {
    final controller = SharedViewerController();
    final session = SharedViewerRetainedSession(controller: controller);
    var first = 0, second = 0;
    await tester.pumpWidget(view(controller, session, ready: () => first++));
    await flush(tester);
    expect(first, 1);
    expect(session.isReady, isTrue);
    final native = platform.views.single;
    expect(native.loads, 1);
    await tester.pumpWidget(const SizedBox());
    await flush(tester, 3);
    expect(session.hasPresentationLease, isFalse);
    expect(controller.isAttached, isTrue);
    expect(native.disposals, 0);
    expect(native.methods('pause'), greaterThan(0));
    await tester.pumpWidget(view(controller, session, ready: () => second++));
    await flush(tester);
    expect(second, 1);
    expect(first, 1);
    expect(platform.views.single, same(native));
    expect(native.loads, 1);
    expect(native.methods('resume'), greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    await close(tester, session);
    await close(tester, session);
    expect(native.disposals, 1);
    expect(controller.isAttached, isFalse);
    expect(session.isDisposed, isTrue);
    expect(session.isReady, isFalse);
    controller.dispose();
  });

  testWidgets(
      'second concurrent presentation fails without stealing the first lease',
      (tester) async {
    final controller = SharedViewerController();
    final session = SharedViewerRetainedSession(controller: controller);
    final errors = <Object>[];
    var ready = 0;
    await tester.pumpWidget(MaterialApp(
        home: Column(children: [
      Expanded(
          child: SharedViewer(
              controller: controller,
              retainedSession: session,
              onReady: () => ready++)),
      Expanded(
          child: SharedViewer(
              controller: controller,
              retainedSession: session,
              onError: errors.add)),
    ])));
    await flush(tester);
    expect(errors.single.toString(), contains('presentation'));
    expect(ready, 1);
    expect(platform.views.length, 1);
    expect(session.hasPresentationLease, isTrue);
    await tester.pumpWidget(const SizedBox());
    await close(tester, session);
    controller.dispose();
  });

  testWidgets(
      'readiness during detach never calls the disposed presentation callback',
      (tester) async {
    platform.autoReady = false;
    final controller = SharedViewerController();
    final session = SharedViewerRetainedSession(controller: controller);
    var stale = 0, fresh = 0;
    await tester.pumpWidget(view(controller, session, ready: () => stale++));
    await flush(tester);
    final native = platform.views.single;
    await tester.pumpWidget(const SizedBox());
    native.ready();
    await flush(tester, 3);
    expect(stale, 0);
    await tester.pumpWidget(view(controller, session, ready: () => fresh++));
    await flush(tester);
    expect(fresh, 1);
    expect(stale, 0);
    expect(platform.views.length, 1);
    await tester.pumpWidget(const SizedBox());
    await close(tester, session);
    controller.dispose();
  });

  testWidgets(
      'disposing during initialization prevents later navigation and attachment',
      (tester) async {
    platform.setupGate = Completer<void>();
    final controller = SharedViewerController();
    final session = SharedViewerRetainedSession(controller: controller);
    var ready = 0;
    await tester.pumpWidget(view(controller, session, ready: () => ready++));
    await flush(tester);
    expect(platform.views.length, 1);
    await close(tester, session);
    platform.setupGate!.complete();
    await flush(tester);
    expect(ready, 0);
    expect(platform.views.single.loads, 0);
    expect(controller.isAttached, isFalse);
    expect(session.isDisposed, isTrue);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('unretained default disposes and recreates its host',
      (tester) async {
    final first = SharedViewerController();
    await tester.pumpWidget(view(first, null));
    await flush(tester);
    final old = platform.views.single;
    await tester.pumpWidget(const SizedBox());
    await flush(tester, 3);
    expect(old.disposals, 1);
    expect(first.isAttached, isFalse);
    final second = SharedViewerController();
    await tester.pumpWidget(view(second, null));
    await flush(tester);
    expect(platform.views.length, 2);
    await tester.pumpWidget(const SizedBox());
    await flush(tester, 3);
    first.dispose();
    second.dispose();
  });
  testWidgets('a retained session never accepts another shared controller',
      (tester) async {
    final owner = SharedViewerController(), foreign = SharedViewerController();
    final session = SharedViewerRetainedSession(controller: owner);
    final errors = <Object>[];
    await tester.pumpWidget(view(foreign, session, error: errors.add));
    await flush(tester, 2);
    expect(errors.single.toString(), contains('associated shared controller'));
    expect(platform.views, isEmpty);
    expect(session.hasPresentationLease, isFalse);
    await tester.pumpWidget(const SizedBox());
    await close(tester, session);
    owner.dispose();
    foreign.dispose();
  });

  testWidgets(
      'retained readiness timeout invalidates without a stale ready callback',
      (tester) async {
    platform.autoReady = false;
    final controller = SharedViewerController();
    final session = SharedViewerRetainedSession(controller: controller);
    var ready = 0;
    final errors = <Object>[];
    await tester.pumpWidget(
        view(controller, session, ready: () => ready++, error: errors.add));
    await flush(tester);
    await tester.pump(const Duration(seconds: 36));
    await tester.pump();
    expect(ready, 0);
    expect(errors.single.toString(), contains('did not report readiness'));
    expect(session.isReady, isFalse);
    expect(controller.isAttached, isFalse);
    platform.views.single.ready();
    await tester.pump();
    expect(ready, 0);
    await tester.pumpWidget(const SizedBox());
    await close(tester, session);
    controller.dispose();
  });

  testWidgets('process termination while retained invalidates the transport',
      (tester) async {
    final controller = SharedViewerController();
    final session = SharedViewerRetainedSession(controller: controller);
    await tester.pumpWidget(view(controller, session));
    await flush(tester);
    final native = platform.views.single;
    await tester.pumpWidget(const SizedBox());
    native.navigation!.error!(WebResourceError(
      errorCode: 2,
      description: 'process terminated',
      isForMainFrame: false,
      errorType: WebResourceErrorType.webContentProcessTerminated,
    ));
    expect(session.isReady, isFalse);
    expect(controller.isAttached, isFalse);
    final errors = <Object>[];
    var ready = 0;
    await tester.pumpWidget(
        view(controller, session, ready: () => ready++, error: errors.add));
    await flush(tester, 3);
    expect(ready, 0);
    expect(errors.single.toString(), contains('process terminated'));
    expect(platform.views.length, 1);
    await tester.pumpWidget(const SizedBox());
    await close(tester, session);
    controller.dispose();
  });

  testWidgets('warm context validation cannot acknowledge a reclaimed JS scene',
      (tester) async {
    final controller = SharedViewerController();
    final session = SharedViewerRetainedSession(controller: controller);
    await tester.pumpWidget(view(controller, session));
    await flush(tester);
    await tester.pumpWidget(const SizedBox());
    platform.healthy = false;
    var ready = 0;
    final errors = <Object>[];
    await tester.pumpWidget(
        view(controller, session, ready: () => ready++, error: errors.add));
    await flush(tester);
    expect(ready, 0);
    expect(errors.single.toString(), contains('document or context was lost'));
    expect(session.isReady, isFalse);
    expect(controller.isAttached, isFalse);
    expect(platform.views.single.loads, 1);
    await tester.pumpWidget(const SizedBox());
    await close(tester, session);
    controller.dispose();
  });

  testWidgets('unretained controller replacement keeps its existing document',
      (tester) async {
    final first = SharedViewerController(), second = SharedViewerController();
    var ready = 0;
    await tester.pumpWidget(view(first, null, ready: () => ready++));
    await flush(tester);
    await tester.pumpWidget(view(second, null, ready: () => ready++));
    await flush(tester);
    expect(ready, 2);
    expect(platform.views.length, 1);
    expect(platform.views.single.loads, 1);
    expect(first.isAttached, isFalse);
    expect(second.isAttached, isTrue);
    await tester.pumpWidget(const SizedBox());
    await flush(tester, 3);
    first.dispose();
    second.dispose();
  });
  testWidgets('stalled WebKit JS disposal cannot retain the server forever',
      (tester) async {
    final controller = SharedViewerController();
    final session = SharedViewerRetainedSession(controller: controller);
    await tester.pumpWidget(view(controller, session));
    await flush(tester);
    final native = platform.views.single;
    platform.disposeGate = Completer<void>();
    await tester.pumpWidget(const SizedBox());
    var done = false;
    session.dispose().then((_) => done = true);
    await tester.pump(const Duration(seconds: 6));
    await flush(tester, 8);
    expect(done, isTrue, reason: 'Native JS cleanup has a bounded deadline');
    expect(native.channel, isNull);
    expect(native.disposals, 1);
    platform.disposeGate!.complete();
    controller.dispose();
  });

  testWidgets('warm replacement drains frames before mounting a native wrapper',
      (tester) async {
    platform.deferWrapperDetach = true;
    final controller = SharedViewerController();
    final session = SharedViewerRetainedSession(controller: controller);
    var ready = 0;
    await tester.pumpWidget(view(controller, session));
    await flush(tester);
    expect(platform.nativeParents, 1);
    await tester.pumpWidget(const SizedBox());
    expect(platform.nativeParents, 1,
        reason: 'Native wrapper is still draining');
    await tester.pumpWidget(view(controller, session, ready: () => ready++));
    expect(ready, 0);
    expect(platform.parentCollisions, 0);
    await flush(tester, 4);
    expect(platform.parentCollisions, 0);
    expect(platform.nativeParents, 1);
    expect(ready, 1);
    expect(platform.views.single.loads, 1);
    await tester.pumpWidget(const SizedBox());
    await flush(tester, 3);
    await close(tester, session);
    controller.dispose();
  });
}
