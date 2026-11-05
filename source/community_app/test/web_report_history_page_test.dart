import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocketworld_flutter/ui/social/web_report_history_page.dart';

WebReportSummary report() => WebReportSummary(
  id: 'owner-report',
  targetTitle: '我的举报对象',
  reason: '内容不适当',
  status: 'resolved',
  createdAt: DateTime(2026, 11, 5),
  outcome: '已完成核查',
);

void main() {
  testWidgets('loading, failure and retry to empty state', (tester) async {
    final pending = Completer<List<WebReportSummary>>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WebReportHistoryPage(
          loader: () {
            calls++;
            return calls == 1 ? pending.future : Future.value([]);
          },
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(StateError('private server details'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法加载举报记录'), findsOneWidget);
    expect(find.textContaining('private server'), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('暂无举报记录'), findsOneWidget);
  });

  testWidgets(
    'owner details expand and appeals remain unavailable without backend',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: WebReportHistoryPage(loader: () async => [report()])),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('已处理'), findsOneWidget);
      await tester.tap(find.text('我的举报对象'));
      await tester.pumpAndSettle();
      expect(find.text('举报原因：内容不适当'), findsOneWidget);
      expect(find.text('处理结果：已完成核查'), findsOneWidget);
      expect(find.text('当前暂不支持在线申诉。'), findsOneWidget);
      expect(find.text('提交申诉'), findsNothing);
    },
  );

  testWidgets(
    'appeal validates, retains failed text, and waits for backend success',
    (tester) async {
      var calls = 0;
      final pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: WebReportHistoryPage(
            loader: () async => [report()],
            onAppeal: (id, explanation) async {
              expect(id, 'owner-report');
              expect(explanation, '请重新核查');
              calls++;
              if (calls == 1) throw StateError('private error');
              return pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的举报对象'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('提交申诉'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('提交'));
      await tester.pumpAndSettle();
      expect(find.text('请填写申诉说明'), findsOneWidget);
      expect(calls, 0);
      await tester.enterText(find.byType(TextField), '请重新核查');
      await tester.tap(find.text('提交'));
      await tester.pumpAndSettle();
      expect(find.text('申诉未能提交，请重试。'), findsOneWidget);
      expect(find.text('请重新核查'), findsOneWidget);
      await tester.tap(find.text('提交'));
      await tester.pump();
      expect(find.text('提交中…'), findsOneWidget);
      expect(find.textContaining('申诉已提交'), findsNothing);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('申诉已提交，处理结果请留意平台通知。'), findsOneWidget);
    },
  );

  for (final width in [360.0, 768.0, 1440.0]) {
    testWidgets('fits $width and keyboard opens report', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: WebReportHistoryPage(loader: () async => [report()])),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('举报原因：内容不适当'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
