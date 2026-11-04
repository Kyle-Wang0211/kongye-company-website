import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocketworld_flutter/community/web_publication_service.dart';
import 'package:pocketworld_flutter/ui/community/web_publication_page.dart';
import 'web_publication_service_test.dart' show Ports, uid, sid, key;

class RecoveryPorts extends Ports {
  bool ambiguousCancel = false;
  @override
  Future<Map<String, dynamic>> invoke(Map<String, dynamic> body) async {
    if (body['action'] == 'cancel') {
      calls.add(body);
      if (ambiguousCancel) throw TimeoutException('lost response');
      state = 'cancelled';
      return {'ok': true, 'submission_id': sid, 'status': state};
    }
    return super.invoke(body);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storageKey = 'pw.web.publication.$uid';
  void savedDraft() => SharedPreferences.setMockInitialValues({
    storageKey: jsonEncode({
      'key': key,
      'submission': sid,
      'sha256': 'old-source-hash',
      'title': 'Alice private title',
      'description': 'Alice private description',
      'selection': null,
    }),
  });
  Future<void> open(WidgetTester tester, Widget page) async {
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
  }

  testWidgets(
    'unavailable original file can be cancelled before a fresh draft',
    (tester) async {
      savedDraft();
      final ports = RecoveryPorts()..state = 'uploading';
      final changes = StreamController<String?>.broadcast();
      addTearDown(changes.close);
      await open(
        tester,
        WebPublicationPage(
          service: WebPublicationService.forTest(ports),
          ownerForTesting: () => ports.active,
          identityChangesForTesting: changes.stream,
        ),
      );
      expect(find.text('Alice private title'), findsOneWidget);
      expect(find.text('发布另一个作品'), findsNothing);
      await tester.tap(find.text('取消本次提交'));
      await tester.pumpAndSettle();
      expect(ports.calls.last, {'action': 'cancel', 'submission_id': sid});
      expect(find.text('已取消'), findsOneWidget);
      await tester.tap(find.text('发布另一个作品'));
      await tester.pumpAndSettle();
      expect(
        (await SharedPreferences.getInstance()).containsKey(storageKey),
        false,
      );
      expect(find.text('Alice private title'), findsNothing);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('ambiguous cancellation preserves draft and status recovery', (
    tester,
  ) async {
    savedDraft();
    final ports = RecoveryPorts()
      ..state = 'uploading'
      ..ambiguousCancel = true;
    final changes = StreamController<String?>.broadcast();
    addTearDown(changes.close);
    await open(
      tester,
      WebPublicationPage(
        service: WebPublicationService.forTest(ports),
        ownerForTesting: () => ports.active,
        identityChangesForTesting: changes.stream,
      ),
    );
    final before = (await SharedPreferences.getInstance()).getString(
      storageKey,
    );
    await tester.tap(find.text('取消本次提交'));
    await tester.pumpAndSettle();
    expect(find.textContaining('取消结果未确认'), findsOneWidget);
    expect(find.text('发布另一个作品'), findsNothing);
    expect(
      (await SharedPreferences.getInstance()).getString(storageKey),
      before,
    );
    ports.state = 'cancelled';
    await tester.tap(find.text('刷新状态'));
    await tester.pumpAndSettle();
    expect(find.text('已取消'), findsOneWidget);
    expect(find.text('发布另一个作品'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'logout removes nested selection AND publication route and clears private state',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final ports = RecoveryPorts();
      final changes = StreamController<String?>.broadcast(sync: true);
      addTearDown(changes.close);
      final page = WebPublicationPage(
        service: WebPublicationService.forTest(ports),
        ownerForTesting: () => ports.active,
        identityChangesForTesting: changes.stream,
        pickFileForTesting: () async =>
            PlatformFile(name: 'source.glb', size: 20, bytes: Uint8List(20)),
        selectionBuilderForTesting: (_, _) => PopScope(
          canPop: false,
          child: Scaffold(body: const Text('Private nested selection')),
        ),
      );
      await open(tester, page);
      await tester.enterText(find.byType(TextField).first, 'Alice secret');
      await tester.tap(find.text('选择 GLB'));
      await tester.pumpAndSettle();
      expect(find.text('Private nested selection'), findsOneWidget);
      ports.active = null;
      changes.add(null);
      await tester.pumpAndSettle();
      expect(
        find.byType(WebPublicationPage, skipOffstage: false),
        findsNothing,
      );
      expect(
        find.text('Private nested selection', skipOffstage: false),
        findsNothing,
      );
      expect(find.text('Alice secret', skipOffstage: false), findsNothing);
      expect(find.text('Open publication'), findsOneWidget);
      ports.active = key;
      changes.add(key);
      await tester.tap(find.text('Open publication'));
      await tester.pumpAndSettle();
      expect(find.text('Alice secret', skipOffstage: false), findsNothing);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('account replacement removes restored private title and status', (
    tester,
  ) async {
    savedDraft();
    final ports = RecoveryPorts()..state = 'uploading';
    final changes = StreamController<String?>.broadcast(sync: true);
    addTearDown(changes.close);
    final page = WebPublicationPage(
      service: WebPublicationService.forTest(ports),
      ownerForTesting: () => ports.active,
      identityChangesForTesting: changes.stream,
    );
    await open(tester, page);
    expect(find.text('Alice private title'), findsOneWidget);
    expect(find.text('等待上传完成'), findsOneWidget);
    ports.active = key;
    changes.add(key);
    await tester.pumpAndSettle();
    expect(find.byType(WebPublicationPage, skipOffstage: false), findsNothing);
    await tester.tap(find.text('Open publication'));
    await tester.pumpAndSettle();
    expect(find.text('Alice private title', skipOffstage: false), findsNothing);
    expect(find.text('等待上传完成', skipOffstage: false), findsNothing);
    expect(
      (await SharedPreferences.getInstance()).containsKey(storageKey),
      true,
      reason: 'old owner draft stays recoverable only under that owner',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
