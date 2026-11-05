import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/ui/social/web_publication_status_page.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    required Future<List<WebPublicationSummary>> Function() loader,
    ValueChanged<String>? onOpen,
    Future<void> Function(String)? onRetry,
    double width = 360,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: WebPublicationStatusPage(
          loader: loader,
          onOpen: onOpen ?? (_) {},
          onRetry: onRetry,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('loading, failure retry, and empty states are truthful', (
    tester,
  ) async {
    final pending = Completer<List<WebPublicationSummary>>();
    var calls = 0;
    await open(
      tester,
      loader: () {
        calls++;
        return calls == 1 ? pending.future : Future.value([]);
      },
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法获取发布记录'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(find.text('还没有发布记录'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets(
    'all backend stages and unknown state have distinct safe labels',
    (tester) async {
      const stages = {
        'uploading': '正在上传',
        'queued': '排队中',
        'preparing': '准备中',
        'rendering': '正在处理',
        'moderating': '内容审核中',
        'awaiting_human': '等待人工审核',
        'published': '已发布',
        'private': '非公开',
        'removed': '已移除',
        'withdrawn': '已撤回',
        'rejected': '未通过审核',
        'failed': '处理失败',
        'cancelled': '已取消',
        'new_backend_stage': '处理中',
      };
      await open(
        tester,
        width: 1440,
        loader: () async => [
          for (final stage in stages.keys)
            WebPublicationSummary(id: stage, title: stage, stage: stage),
        ],
      );
      await tester.pumpAndSettle();
      for (final entry in stages.entries) {
        await tester.scrollUntilVisible(find.text(entry.key), 200);
        expect(find.text(entry.value), findsOneWidget);
      }
      expect(find.textContaining('%'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [360.0, 768.0, 1440.0]) {
    testWidgets('published detail action fits at width $width', (tester) async {
      String? opened;
      await open(
        tester,
        width: width,
        loader: () async => [
          WebPublicationSummary(
            id: 'pub',
            title: '我的作品',
            stage: 'published',
            updatedAt: DateTime.utc(2026, 11, 5),
          ),
        ],
        onOpen: (id) => opened = id,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的作品'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('在社区查看'));
      expect(opened, 'pub');
      if (width < 768) {
        await tester.tap(find.text('返回发布列表'));
        await tester.pumpAndSettle();
        expect(find.text('在社区查看'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('technical faults retry without a human moderation label', (
    tester,
  ) async {
    var retries = 0;
    var loads = 0;
    final pending = Completer<void>();
    await open(
      tester,
      loader: () async {
        loads++;
        return const [
          WebPublicationSummary(
            id: 'a',
            title: '图片缺失',
            stage: 'missing_images',
          ),
          WebPublicationSummary(
            id: 'b',
            title: '版本问题',
            stage: 'version_mismatch',
          ),
          WebPublicationSummary(id: 'c', title: '服务问题', stage: 'vendor_error'),
        ];
      },
      onRetry: (id) {
        expect(id, 'a');
        retries++;
        return pending.future;
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('处理遇到问题'), findsNWidgets(3));
    expect(find.textContaining('人工'), findsNothing);
    await tester.tap(find.text('图片缺失'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试处理'));
    await tester.pump();
    expect(find.text('正在提交重试…'), findsOneWidget);
    pending.completeError(StateError('response lost'));
    await tester.pumpAndSettle();
    expect(find.text('重试未确认，请刷新状态后再试。'), findsOneWidget);
    expect(retries, 1);
    expect(loads, 1);
  });

  testWidgets('keyboard can open a publication detail', (tester) async {
    await open(
      tester,
      loader: () async => const [
        WebPublicationSummary(id: 'a', title: '键盘作品', stage: 'queued'),
      ],
    );
    await tester.pumpAndSettle();
    // Move through the app-bar action and the Material list-tile focus target.
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      if (find.text('返回发布列表').evaluate().isNotEmpty) break;
    }
    expect(find.text('返回发布列表'), findsOneWidget);
  });
}
