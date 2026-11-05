// Fake host verifies flow and identity guards. Real rendering is tested by root IAB.
// ignore_for_file: invalid_use_of_internal_member
import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';
import 'package:pocketworld_flutter/community/web_publication_service.dart';
import 'package:pocketworld_flutter/ui/community/web_publication_page.dart';
import 'package:pocketworld_flutter/ui/community/web_publication_selection_page.dart';

import 'web_publication_service_test.dart' show Ports, glb, uid;

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
        result = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=';
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
  Stream<String?> changes,
) async {
  SharedPreferences.setMockInitialValues({});
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
            onPressed: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => page)),
            child: const Text('Open publication'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open publication'));
  await tester.pumpAndSettle();
  await flush(tester);
  await tester.tap(find.text('选择 GLB'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('保留模型'));
  await tester.pumpAndSettle();
  await flush(tester);
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
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('确认当前画面为封面和初始视角'));
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
      await tester.enterText(find.byType(TextField).first, '作品');
      await tester.ensureVisible(find.text('提交发布'));
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
    await tester.ensureVisible(find.text('确认当前画面为封面和初始视角'));
    await tester.tap(find.text('确认当前画面为封面和初始视角'));
    await flush(tester);
    await flush(tester);
    expect(
      find.byKey(const ValueKey('publication-confirmed-cover')),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('重新选择 GLB / 调整选区'));
    await tester.tap(find.text('重新选择 GLB / 调整选区'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留模型'));
    await tester.pumpAndSettle();
    await flush(tester);
    expect(
      find.byKey(const ValueKey('publication-confirmed-cover')),
      findsNothing,
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
    await tester.ensureVisible(find.text('确认当前画面为封面和初始视角'));
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
}
