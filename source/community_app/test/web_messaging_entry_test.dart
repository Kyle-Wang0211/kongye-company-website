import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/auth/auth_models.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/auth/unavailable_auth_service.dart';
import 'package:pocketworld_flutter/community/web_messaging_repository.dart';
import 'package:pocketworld_flutter/ui/social/web_conversation_page.dart';
import 'package:pocketworld_flutter/ui/social/web_messages_page.dart';
import 'package:pocketworld_flutter/ui/social/web_messaging_entry.dart';

import 'web_messaging_repository_test.dart' show Api;

class User extends CurrentUser {
  User() : super(service: const UnavailableAuthService());
  AuthenticatedUser? identity = const AuthenticatedUser(
    id: InternalUserID('owner'),
  );
  @override
  AuthenticatedUser? get signedInUser => identity;
  void leave() {
    identity = null;
    notifyListeners();
  }
}

class Repository extends WebMessagingRepository {
  Repository(User user)
    : super(
        api: Api(),
        ownerId: 'owner',
        currentUserId: () => user.identity?.id.rawValue,
      );
  int loads = 0, opens = 0;
  final changes = StreamController<void>.broadcast();
  @override
  Future<List<WebConversationSummary>> inbox() async => [
    WebConversationSummary(
      id: 'conversation',
      peerId: 'peer',
      displayName: 'Private peer',
      preview: 'Private preview',
      updatedAt: DateTime(2026, 11, 5),
    ),
  ];
  @override
  Future<String> openPeer(String peerId) async {
    opens++;
    return 'conversation';
  }

  @override
  Future<List<WebChatMessage>> history(String id) async {
    loads++;
    return [
      WebChatMessage(
        id: '7',
        text: 'Private history $loads',
        isMine: false,
        createdAt: DateTime(2026, 11, 5),
      ),
    ];
  }

  @override
  Stream<void> watch(String id) => changes.stream;
}

void main() {
  testWidgets('unreleased backend shows unavailable without initializing SDK', (
    tester,
  ) async {
    final user = User();
    addTearDown(user.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: WebMessagingEntry(user: user, ownerId: 'owner'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Messaging unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'inbox opens real conversation, realtime refetches, signout clears private content',
    (tester) async {
      final user = User();
      final repo = Repository(user);
      addTearDown(() {
        repo.dispose();
        repo.api.close();
        user.dispose();
        repo.changes.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: WebMessagingEntry(
            user: user,
            ownerId: 'owner',
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Private peer'));
      await tester.pumpAndSettle();
      expect(find.text('Private history 1'), findsOneWidget);
      repo.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Private history 2'), findsOneWidget);
      user.leave();
      await tester.pumpAndSettle();
      expect(find.textContaining('Private history'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('会话已结束，请重新登录。'), findsOneWidget);
    },
  );

  testWidgets(
    'profile entry opens canonical pair once across parent rebuilds',
    (tester) async {
      final user = User();
      final repo = Repository(user);
      addTearDown(() {
        repo.dispose();
        repo.api.close();
        user.dispose();
        repo.changes.close();
      });
      Widget entry() => MaterialApp(
        home: WebMessagingEntry(
          user: user,
          ownerId: 'owner',
          peerId: 'peer',
          peerName: 'Private peer',
          repository: repo,
        ),
      );
      await tester.pumpWidget(entry());
      await tester.pumpAndSettle();
      await tester.pumpWidget(entry());
      await tester.pumpAndSettle();
      expect(repo.opens, 1);
      expect(find.text('Private history 1'), findsOneWidget);
    },
  );
}
