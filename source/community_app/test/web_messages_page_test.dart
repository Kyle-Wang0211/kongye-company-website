import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/ui/design_system.dart';
import 'package:pocketworld_flutter/ui/social/web_messages_page.dart';

Future<void> mount(
  WidgetTester tester, {
  Future<List<WebConversationSummary>> Function()? loader,
  ValueChanged<WebConversationSummary>? onOpen,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: WebMessagesPage(
        loadConversations: loader,
        onOpen: onOpen ?? (_) {},
        isEnglish: true,
      ),
    ),
  ),
);

WebConversationSummary conversation({String name = 'Creator'}) =>
    WebConversationSummary(
      id: 'conversation-1',
      peerId: 'creator-1',
      displayName: name,
      preview: List.filled(30, 'A message with a long preview.').join(' '),
      updatedAt: DateTime.utc(2026, 11, 5),
      unreadCount: 120,
    );

void main() {
  testWidgets('date caption keeps its size and readable grayscale contrast', (
    tester,
  ) async {
    await mount(
      tester,
      loader: () async => [
        WebConversationSummary(
          id: 'dated-conversation',
          peerId: 'creator-1',
          displayName: 'Creator',
          preview: 'Message',
          updatedAt: DateTime(2026, 11, 5, 12),
        ),
      ],
    );
    await tester.pumpAndSettle();
    final caption = tester.widget<Text>(find.text('2026-11-05'));
    expect(caption.style!.fontSize, AetherTextStyles.caption.fontSize);
    expect(caption.style!.color, const Color(0xFF6B6B6B));
    final foregroundLuminance = caption.style!.color!.computeLuminance();
    final backgroundLuminance = AetherColors.bgCanvas.computeLuminance();
    final contrast =
        (backgroundLuminance + 0.05) / (foregroundLuminance + 0.05);
    expect(contrast, greaterThanOrEqualTo(4.5));
  });

  testWidgets('missing service is unavailable, never an empty inbox', (
    tester,
  ) async {
    await mount(tester);
    await tester.pumpAndSettle();
    expect(find.text('Messaging unavailable'), findsOneWidget);
    expect(find.text('No messages yet'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('pending request becomes empty only when it completes', (
    tester,
  ) async {
    final pending = Completer<List<WebConversationSummary>>();
    await mount(tester, loader: () => pending.future);
    expect(find.text('Loading messages…'), findsOneWidget);
    expect(find.text('No messages yet'), findsNothing);
    pending.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('No messages yet'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('sync failure retries and opens exactly the supplied summary', (
    tester,
  ) async {
    var calls = 0;
    final row = conversation();
    WebConversationSummary? opened;
    await mount(
      tester,
      loader: () {
        calls++;
        if (calls == 1) throw StateError('private server detail');
        return Future.value([row]);
      },
      onOpen: (value) => opened = value,
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load messages'), findsOneWidget);
    expect(find.textContaining('private server detail'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Creator'), findsOneWidget);
    expect(find.text('99+'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('conversation-conversation-1')));
    expect(identical(opened, row), isTrue);
  });

  for (final width in [360.0, 768.0, 1440.0]) {
    testWidgets('long rows fit width $width and support keyboard activation', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var opens = 0;
      await mount(
        tester,
        loader: () async => [
          conversation(name: List.filled(30, 'Long creator name').join()),
        ],
        onOpen: (_) => opens++,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Traversal: refresh button, followed by the actionable conversation.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(opens, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('changing repository discards previous pending content', (
    tester,
  ) async {
    final old = Completer<List<WebConversationSummary>>();
    await mount(tester, loader: () => old.future);
    await mount(tester, loader: () async => []);
    await tester.pumpAndSettle();
    old.complete([conversation()]);
    await tester.pumpAndSettle();
    expect(find.text('No messages yet'), findsOneWidget);
    expect(find.text('Creator'), findsNothing);
  });
}
