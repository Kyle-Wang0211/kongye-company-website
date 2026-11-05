// Fake host verifies flow and identity guards. Real rendering is tested by root IAB.
// ignore_for_file: invalid_use_of_internal_member
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:pocketworld_flutter/official_capture/selection_box.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';
import 'package:pocketworld_flutter/community/web_publication_service.dart';
import 'package:pocketworld_flutter/ui/community/web_publication_page.dart';
import 'package:pocketworld_flutter/ui/community/web_publication_selection_page.dart';

import 'web_publication_service_test.dart' show Ports, glb, uid, sid, key;

class Preview extends StatefulWidget {
  const Preview(this.controller, this.ready, this.harness);
  final SharedViewerController controller;
  final VoidCallback ready;
  final Harness harness;
  @override
  State<Preview> createState() => PreviewState();
}

class PreviewState extends State<Preview> {
  @override
  void initState() {
    super.initState();
    widget.controller.attachTransport((request) async {
      Object? result;
      if (request['method'] == 'getCameraFraming') {
        if (widget.harness.pendingCamera != null)
          await widget.harness.pendingCamera!.future;
        result = widget.harness.camera;
      }
      if (request['method'] == 'capture') {
        result =
            'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=';
      }
      widget.controller.receive({
        'protocol': sharedViewerProtocol,
        'id': request['id'],
        'ok': true,
        'result': result,
      });
    }, registerBytes: (_, _) async => Uri.parse('blob:preview'));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.ready();
    });
  }

  @override
  Widget build(BuildContext context) =>
      const SizedBox(key: ValueKey('fake-publication-preview'));
}

class Harness {
  Map<String, dynamic> camera = {
    'projection': 'perspective',
    'position': [3, 2, 4],
    'target': [0, 0, 0],
    'up': [0, 1, 0],
    'fov_y_degrees': 45,
    'aspect': 1.5,
  };
  Completer<void>? pendingCamera;
  Widget host(
    SharedViewerController c,
    VoidCallback ready,
    ValueChanged<Object> error,
  ) => Preview(c, ready, this);
}

Future<void> flush(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> open(
  WidgetTester tester,
  Ports ports,
  Harness harness,
  Stream<String?> changes, {
  bool restore = false,
}) async {
  if (!restore) SharedPreferences.setMockInitialValues({});
  final page = WebPublicationPage(
    service: WebPublicationService.forTest(ports),
    ownerForTesting: () => ports.active,
    identityChangesForTesting: changes,
    pickFileForTesting: () async =>
        PlatformFile(name: 'model.glb', size: 20, bytes: glb()),
    selectionBuilderForTesting: (context, bytes) => Scaffold(
      body: TextButton(
        onPressed: () =>
            Navigator.of(context).pop(WebPublicationSelectionResult()),
        child: const Text('保留模型'),
      ),
    ),
    previewHostBuilderForTesting: harness.host,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => page)),
            child: const Text('Open publication'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open publication'));
  await tester.pumpAndSettle();
  await flush(tester);
  if (restore) return;
  await tester.tap(find.text('选择 GLB'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('保留模型'));
  await tester.pumpAndSettle();
  await flush(tester);
}

const newSubmission = '44444444-4444-4444-8444-444444444444';

class EditingPorts extends Ports {
  Completer<Map<String, dynamic>>? pendingStatus;
  @override
  Future<Map<String, dynamic>> invoke(Map<String, dynamic> body) async {
    final response = await super.invoke(body);
    if (body['action'] == 'status' && pendingStatus != null) {
      return pendingStatus!.future;
    }
    if (body['action'] == 'initiate') {
      final upload = response['upload'] as Map<String, dynamic>;
      final bucket = upload['bucket'];
      final path = '$uid/$newSubmission/source.glb';
      response['submission_id'] = newSubmission;
      upload['path'] = path;
      upload['signed_url'] =
          '${apiOrigin.origin}/storage/v1/object/upload/sign/$bucket/$path?token=token';
    } else if (body['action'] == 'seal') {
      response['submission_id'] = body['submission_id'];
    }
    return response;
  }
}

Future<void> reveal(
  WidgetTester tester,
  Finder finder, {
  double delta = 200,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'preview stays interactive and only explicit confirmation freezes submit camera',
    (tester) async {
      final ports = Ports(), harness = Harness();
      final changes = StreamController<String?>.broadcast();
      await open(tester, ports, harness, changes.stream);
      expect(
        find.byKey(const ValueKey('fake-publication-preview')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byType(FilledButton),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.scrollUntilVisible(
        find.text('确认当前画面为封面和初始视角'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('确认当前画面为封面和初始视角'));
      await flush(tester);
      await flush(tester);
      expect(
        find.byKey(const ValueKey('publication-confirmed-cover')),
        findsOneWidget,
      );
      harness.camera = {
        ...harness.camera,
        'position': [9, 9, 9],
      };
      await tester.scrollUntilVisible(
        find.byType(TextField).first,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField).first, '作品');
      await tester.scrollUntilVisible(
        find.text('提交发布'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('提交发布'));
      await flush(tester);
      await flush(tester);
      expect((ports.calls.first['initial_view'] as Map)['position'], [3, 2, 4]);
      await tester.pumpWidget(const SizedBox());
      await changes.close();
    },
  );
  testWidgets('reselecting the asset discards its confirmed cover', (
    tester,
  ) async {
    final ports = Ports(), harness = Harness();
    final changes = StreamController<String?>.broadcast();
    await open(tester, ports, harness, changes.stream);
    await tester.scrollUntilVisible(
      find.text('确认当前画面为封面和初始视角'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('确认当前画面为封面和初始视角'));
    await flush(tester);
    await flush(tester);
    expect(
      find.byKey(const ValueKey('publication-confirmed-cover')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('重新选择 GLB / 调整选区'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('重新选择 GLB / 调整选区')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新选择 GLB / 调整选区'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留模型'));
    await tester.pumpAndSettle();
    await flush(tester);
    expect(
      find.byKey(const ValueKey('publication-confirmed-cover')),
      findsNothing,
    );
    await tester.scrollUntilVisible(
      find.byType(FilledButton),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    await changes.close();
  });
  testWidgets('account switch discards pending camera confirmation', (
    tester,
  ) async {
    final ports = Ports(),
        harness = Harness()..pendingCamera = Completer<void>();
    final changes = StreamController<String?>.broadcast();
    await open(tester, ports, harness, changes.stream);
    await tester.scrollUntilVisible(
      find.text('确认当前画面为封面和初始视角'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('确认当前画面为封面和初始视角'));
    await flush(tester);
    ports.active = null;
    changes.add(null);
    await flush(tester);
    harness.pendingCamera!.complete();
    await flush(tester);
    expect(ports.calls, isEmpty);
    expect(
      find.byKey(const ValueKey('publication-confirmed-cover')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
    await changes.close();
  });
  testWidgets(
    'changing a confirmed cover retains content and requires a new camera confirmation',
    (tester) async {
      final ports = Ports(), harness = Harness();
      final changes = StreamController<String?>.broadcast();
      await open(tester, ports, harness, changes.stream);
      await reveal(tester, find.text('确认当前画面为封面和初始视角'));
      await tester.tap(find.text('确认当前画面为封面和初始视角'));
      await flush(tester);
      await flush(tester);
      await reveal(tester, find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, '保留标题');
      await tester.enterText(find.byType(TextField).last, '保留描述');
      expect(
        find.byKey(const ValueKey('publication-change-cover')),
        findsOneWidget,
      );
      await reveal(
        tester,
        find.byKey(const ValueKey('publication-change-cover')),
        delta: -200,
      );
      await tester.tap(find.byKey(const ValueKey('publication-change-cover')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('fake-publication-preview')),
        findsOneWidget,
      );
      await reveal(
        tester,
        find.byKey(const ValueKey('publication-confirmed-cover')),
      );
      expect(
        find.byKey(const ValueKey('publication-cover-pending')),
        findsOneWidget,
      );
      await reveal(tester, find.byType(FilledButton));
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '保留标题',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        '保留描述',
      );
      harness.camera = {
        ...harness.camera,
        'position': [8, 3, 5],
      };
      await reveal(tester, find.text('确认当前画面为封面和初始视角'), delta: -200);
      await tester.tap(find.text('确认当前画面为封面和初始视角'));
      await flush(tester);
      await flush(tester);
      await reveal(tester, find.text('提交发布'));
      await tester.tap(find.text('提交发布'));
      await flush(tester);
      await flush(tester);
      final initiate = ports.calls.firstWhere(
        (call) => call['action'] == 'initiate',
      );
      expect(initiate['title'], '保留标题');
      expect(initiate['description'], '保留描述');
      expect((initiate['initial_view'] as Map)['position'], [8, 3, 5]);
      expect(initiate['source_sha256'], sha256.convert(glb()).toString());
      await tester.pumpWidget(const SizedBox());
      await changes.close();
    },
  );

  for (final terminal in ['failed', 'not_qualified']) {
    testWidgets(
      '$terminal returns to editable retained content and submits with a new identity',
      (tester) async {
        final ports = EditingPorts()..state = terminal;
        final harness = Harness();
        final changes = StreamController<String?>.broadcast();
        final box = SelectionBox.initialSquareFace(
          cx: 0,
          cy: 0,
          cz: 0,
          halfExtent: 1,
        ).toJson();
        final sourceHash = sha256.convert(glb()).toString();
        SharedPreferences.setMockInitialValues({
          'pw.web.publication.$uid': jsonEncode({
            'key': key,
            'submission': sid,
            'sha256': sourceHash,
            'title': '原作品标题',
            'description': '原作品描述',
            'selection': box,
            'initial_view': {
              ...harness.camera,
              'schema': 'pw.camera-framing.v1',
              'source_sha256': sourceHash,
              'selection_box': box,
            },
          }),
        });
        await open(tester, ports, harness, changes.stream, restore: true);
        expect(
          find.byKey(const ValueKey('publication-return-editing')),
          findsOneWidget,
        );
        final staleStatus = Completer<Map<String, dynamic>>();
        ports.pendingStatus = staleStatus;
        await reveal(tester, find.text('刷新状态'));
        await tester.tap(find.text('刷新状态'));
        await flush(tester);
        await reveal(
          tester,
          find.byKey(const ValueKey('publication-return-editing')),
        );
        await tester.tap(
          find.byKey(const ValueKey('publication-return-editing')),
        );
        await flush(tester);
        staleStatus.complete({
          'ok': true,
          'submission_id': sid,
          'status': 'processing',
        });
        ports.pendingStatus = null;
        await flush(tester);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('publication-status')), findsNothing);
        final prefs = await SharedPreferences.getInstance();
        final draft =
            jsonDecode(prefs.getString('pw.web.publication.$uid')!) as Map;
        expect(draft['editable'], true);
        expect(draft['key'], isNull);
        expect(draft['submission'], isNull);
        expect(draft['title'], '原作品标题');
        expect(draft['description'], '原作品描述');
        expect(draft['selection'], box);
        expect(draft['sha256'], sourceHash);
        expect(
          ports.calls.where((call) => call['action'] != 'status'),
          isEmpty,
        );
        await reveal(tester, find.byType(TextField).first, delta: -200);
        expect(
          tester.widget<TextField>(find.byType(TextField).first).enabled,
          true,
        );
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          '原作品标题',
        );
        await tester.pumpWidget(const SizedBox());
        await open(tester, ports, harness, changes.stream, restore: true);
        await tester.tap(find.byType(OutlinedButton).first);
        await tester.pumpAndSettle();
        await flush(tester);
        expect(
          find.text('保留模型'),
          findsNothing,
          reason: 'original selection is retained on same-source reselection',
        );
        await reveal(tester, find.text('确认当前画面为封面和初始视角'));
        await tester.tap(find.text('确认当前画面为封面和初始视角'));
        await flush(tester);
        await flush(tester);
        await reveal(tester, find.text('提交发布'));
        await tester.tap(find.text('提交发布'));
        await flush(tester);
        await flush(tester);
        final initiate = ports.calls.firstWhere(
          (call) => call['action'] == 'initiate',
        );
        expect(initiate['idempotency_key'], isNot(key));
        expect(initiate['title'], '原作品标题');
        expect(initiate['description'], '原作品描述');
        expect(initiate['selection_box'], box);
        expect(initiate['source_sha256'], sourceHash);
        expect(
          ports.calls
              .where((call) => call['action'] == 'seal')
              .single['submission_id'],
          newSubmission,
        );
        await tester.pumpWidget(const SizedBox());
        await changes.close();
      },
    );
  }

  testWidgets('in-flight confirmation cannot change a sealed request cover', (
    tester,
  ) async {
    final ports = Ports(), harness = Harness();
    final changes = StreamController<String?>.broadcast();
    await open(tester, ports, harness, changes.stream);
    await reveal(tester, find.text('确认当前画面为封面和初始视角'));
    await tester.tap(find.text('确认当前画面为封面和初始视角'));
    await flush(tester);
    await flush(tester);
    await reveal(tester, find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, '进行中作品');
    await reveal(tester, find.text('提交发布'));
    await tester.tap(find.text('提交发布'));
    await flush(tester);
    await flush(tester);
    await reveal(
      tester,
      find.byKey(const ValueKey('publication-change-cover')),
      delta: -200,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('publication-change-cover')),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.byKey(const ValueKey('publication-return-editing')),
      findsNothing,
    );
    expect(
      ports.calls.where((call) => call['action'] == 'initiate'),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox());
    await changes.close();
  });
}
