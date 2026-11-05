import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/ui/social/web_conversation_page.dart';

WebChatMessage message(String id, String text, {bool review = false}) =>
    WebChatMessage(
      id: id,
      text: text,
      isMine: true,
      createdAt: DateTime(2026, 11, 5, 12),
      status: review
          ? WebChatMessageStatus.pendingReview
          : WebChatMessageStatus.sent,
    );

void main() {
  testWidgets(
    'machine retry receipt stays undelivered and preserves an unrelated draft',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WebConversationPage(
            peerName: 'Peer',
            loader: () async => [
              WebChatMessage(
                id: 'request:1',
                text: 'retry me',
                isMine: true,
                createdAt: DateTime(2026, 11, 5),
                status: WebChatMessageStatus.retryable,
              ),
            ],
            send: (_) async => message('sent', 'confirmed'),
            idempotentRetry: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('服务暂不可用，尚未送达'), findsOneWidget);
      expect(find.textContaining('待审核'), findsNothing);
      await tester.enterText(find.byType(TextField), 'unsent different draft');
      await tester.pump();
      final retry = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '重试发送'),
      );
      expect(retry.onPressed, isNull);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'unsent different draft',
      );
    },
  );

  testWidgets(
    'realtime invalidation during a pending history load is reconciled afterward',
    (tester) async {
      final changes = StreamController<void>();
      addTearDown(changes.close);
      final initial = Completer<List<WebChatMessage>>();
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: WebConversationPage(
            peerName: 'Peer',
            changes: changes.stream,
            loader: () => ++loads == 1
                ? initial.future
                : Future.value([message('latest', 'new private message')]),
            send: (_) async => message('sent', 'confirmed'),
          ),
        ),
      );
      changes.add(null);
      await tester.pump();
      initial.complete([]);
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(find.text('new private message'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'long emoji draft reports canonical send limit before transport',
    (tester) async {
      var sends = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: WebConversationPage(
            peerName: 'Peer',
            loader: () async => [],
            send: (_) async {
              sends++;
              return message('sent', 'sent');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        List.filled(301, '🙂').join(),
      );
      await tester.pump();
      expect(find.text('消息过长，请缩短后发送。'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(sends, 0);
    },
  );

  testWidgets('loading, unavailable, retry and empty are distinct', (
    tester,
  ) async {
    var loads = 0;
    final pending = Completer<List<WebChatMessage>>();
    await tester.pumpWidget(
      MaterialApp(
        home: WebConversationPage(
          peerName: 'Alice',
          loader: () {
            loads++;
            return loads == 1 ? pending.future : Future.value([]);
          },
          send: (_) async => message('1', 'confirmed'),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('消息暂时无法加载'), findsOneWidget);
    expect(find.textContaining('待审核'), findsNothing);
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(find.textContaining('还没有消息'), findsOneWidget);
  });

  testWidgets('send is single-flight and only displays returned confirmation', (
    tester,
  ) async {
    final pending = Completer<WebChatMessage>();
    var sends = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WebConversationPage(
          peerName: 'Alice',
          loader: () async => [],
          send: (text) {
            sends++;
            expect(text, 'draft');
            return pending.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'draft');
    await tester.pump();
    await tester.tap(find.text('发送'));
    await tester.pump();
    expect(sends, 1);
    expect(find.byType(SelectableText), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    pending.complete(message('server-id', 'server-confirmed', review: true));
    await tester.pumpAndSettle();
    expect(find.text('server-confirmed'), findsOneWidget);
    expect(find.textContaining('待审核，仅自己可见'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets(
    'ambiguous failure retains draft and never automatically replays',
    (tester) async {
      var sends = 0;
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: WebConversationPage(
            peerName: 'Alice',
            loader: () async {
              loads++;
              return [];
            },
            send: (_) async {
              sends++;
              throw TimeoutException('ambiguous');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'keep this draft');
      await tester.pump();
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(find.textContaining('发送结果未确认'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'keep this draft',
      );
      expect(find.byType(SelectableText), findsNothing);
      await tester.tap(find.byTooltip('刷新消息'));
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(sends, 1);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('确认重试发送？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(sends, 1);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认重试'));
      await tester.pumpAndSettle();
      expect(sends, 2);
    },
  );

  testWidgets(
    'late send completion cannot leak into a different conversation',
    (tester) async {
      final pending = Completer<WebChatMessage>();
      Widget page(String peer) => MaterialApp(
        home: WebConversationPage(
          peerName: peer,
          loader: () async => [],
          send: (_) => pending.future,
        ),
      );
      await tester.pumpWidget(page('Alice'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'to Alice');
      await tester.pump();
      await tester.tap(find.text('发送'));
      await tester.pump();
      await tester.pumpWidget(page('Bob'));
      await tester.pumpAndSettle();
      pending.complete(message('old', 'private to Alice'));
      await tester.pumpAndSettle();
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('private to Alice'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    },
  );

  for (final width in [360.0, 768.0, 1440.0]) {
    testWidgets('fits $width width with long messages', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: WebConversationPage(
            peerName: 'A very long peer name repeated for responsive layout',
            loader: () async => [message('1', 'Long message ' * 100)],
            send: (_) async => message('2', 'confirmed'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip('刷新消息'), findsOneWidget);
    });
  }
}
