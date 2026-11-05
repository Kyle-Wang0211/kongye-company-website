import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/ui/social/web_profile_edit_page.dart';

const initial = WebProfileDraft(displayName: '原昵称', bio: '原简介');

Future<void> openEditor(
  WidgetTester tester,
  Future<WebProfileSaveResult> Function(WebProfileDraft) save,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: WebProfileEditPage(initialProfile: initial, save: save),
    ),
  );
}

Future<void> save(WidgetTester tester) async {
  await tester.pump();
  await tester.ensureVisible(find.text('保存修改'));
  await tester.tap(find.text('保存修改'));
  await tester.pump();
}

void main() {
  testWidgets('approval changes public values only after repository approval', (
    tester,
  ) async {
    final completer = Completer<WebProfileSaveResult>();
    WebProfileDraft? submitted;
    await openEditor(tester, (draft) {
      submitted = draft;
      return completer.future;
    });
    await tester.enterText(find.byKey(const Key('profile-name')), ' 新昵称 ');
    await save(tester);
    expect(submitted!.displayName, '新昵称');
    expect(
      tester.widget<Text>(find.byKey(const Key('approved-name'))).data,
      '原昵称',
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    completer.complete(WebProfileSaveResult.approved);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('approved-name'))).data,
      '新昵称',
    );
    expect(find.text('个人资料已更新'), findsOneWidget);
  });

  testWidgets('pending review keeps approved public profile', (tester) async {
    await openEditor(tester, (_) async => WebProfileSaveResult.pendingReview);
    await tester.enterText(find.byKey(const Key('profile-bio')), '待审核简介');
    await save(tester);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('approved-bio'))).data,
      '原简介',
    );
    expect(find.textContaining('等待内容审核'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('failure preserves approved values and draft for retry', (
    tester,
  ) async {
    var calls = 0;
    await openEditor(tester, (_) async {
      calls++;
      throw StateError('offline');
    });
    await tester.enterText(find.byKey(const Key('profile-name')), '未保存昵称');
    await save(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(find.textContaining('等待内容审核'), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('approved-name'))).data,
      '原昵称',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('profile-name')))
          .controller!
          .text,
      '未保存昵称',
    );
    await save(tester);
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('blank nickname is rejected before save', (tester) async {
    var calls = 0;
    await openEditor(tester, (_) async {
      calls++;
      return WebProfileSaveResult.approved;
    });
    await tester.enterText(find.byKey(const Key('profile-name')), '   ');
    await save(tester);
    expect(find.text('请输入昵称'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('dirty exit asks and respects continue or discard', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => WebProfileEditPage(
                    initialProfile: initial,
                    save: (_) async => WebProfileSaveResult.approved,
                  ),
                ),
              ),
              child: const Text('打开编辑'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile-name')), '修改');
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑个人资料'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.text('打开编辑'), findsOneWidget);
    expect(find.text('编辑个人资料'), findsNothing);
  });

  testWidgets('discard dialog keeps monochrome surface and action colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: WebProfileEditPage(
          initialProfile: initial,
          save: (_) async => WebProfileSaveResult.approved,
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('profile-name')), '修改');
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    final action = find.descendant(
      of: dialog,
      matching: find.widgetWithText(TextButton, '继续编辑'),
    );
    final actionColor = Theme.of(tester.element(action)).colorScheme.primary;
    expect(actionColor.r, actionColor.g);
    expect(actionColor.g, actionColor.b);
    final surface = tester.widget<Material>(
      find.descendant(of: dialog, matching: find.byType(Material)).first,
    );
    final surfaceColor = surface.color!;
    expect(surfaceColor.r, surfaceColor.g);
    expect(surfaceColor.g, surfaceColor.b);
  });

  testWidgets('published refresh preserves a newer unsent draft', (
    tester,
  ) async {
    Widget editor(WebProfileDraft profile, WebProfileSaveResult? result) =>
        MaterialApp(
          home: WebProfileEditPage(
            initialProfile: profile,
            save: (_) async => WebProfileSaveResult.pendingReview,
            observedResult: result,
            approvalFromProjection: true,
          ),
        );
    await tester.pumpWidget(editor(initial, null));
    await tester.enterText(find.byKey(const Key('profile-name')), '尚未提交的草稿');
    await tester.pumpWidget(
      editor(
        const WebProfileDraft(displayName: '审核通过的昵称', bio: '公开简介'),
        WebProfileSaveResult.approved,
      ),
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('profile-name')))
          .controller!
          .text,
      '尚未提交的草稿',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('approved-name'))).data,
      '审核通过的昵称',
    );
  });

  testWidgets('grapheme limits reject input before a write', (tester) async {
    var calls = 0;
    await openEditor(tester, (_) async {
      calls++;
      return WebProfileSaveResult.approved;
    });
    await tester.enterText(
      find.byKey(const Key('profile-name')),
      List.filled(21, '人').join(),
    );
    await save(tester);
    expect(find.text('昵称最多 20 个字符'), findsOneWidget);
    expect(calls, 0);
    await tester.enterText(find.byKey(const Key('profile-name')), '昵称');
    await tester.enterText(
      find.byKey(const Key('profile-bio')),
      List.filled(161, '字').join(),
    );
    await save(tester);
    expect(find.text('个人简介最多 160 个字符'), findsOneWidget);
    expect(calls, 0);
  });

  for (final width in [360.0, 768.0, 1440.0]) {
    testWidgets('form fits width $width and avatar is read only', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await openEditor(tester, (_) async => WebProfileSaveResult.approved);
      expect(find.text('头像由系统生成'), findsOneWidget);
      expect(find.byIcon(Icons.upload), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
