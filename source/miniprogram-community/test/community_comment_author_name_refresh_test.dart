import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pocketworld_flutter/community/comments/comment_repository.dart';
import 'package:pocketworld_flutter/community/comments/comment_models.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/community/comments/community_comments_panel.dart';

class _Names
    implements
        CommunityCommentRepository,
        CommunityCommentAuthorNameRepository,
        CommunityCommentAuthorNameEvents {
  List<CommunityComment> rows = [];
  int fetches = 0;
  @override
  Future<CommunityCommentPage> fetch(String workId) async {
    fetches++;
    return CommunityCommentPage(
      assetRevision: 'revision',
      comments: rows,
      canComment: true,
      publicCount: rows.length,
    );
  }

  @override
  Future<CommunityComment> submit(CommunityCommentDraft draft) async =>
      throw UnimplementedError();
  @override
  Future<void> remove(String workId, String commentId) async {}
  @override
  Future<CommunityComment> setLiked(
    String workId,
    String commentId,
    bool liked,
  ) async => rows.first;
  String name = '旧昵称';
  int reads = 0;
  final changes = StreamController<void>.broadcast();
  @override
  Stream<void> watchAuthorNameChanges(String workId) => changes.stream;
  @override
  Future<Map<String, String>> fetchAuthorNames(
    String workId,
    Set<String> userIds,
  ) async {
    reads++;
    expect(workId, 'work');
    expect(userIds, {'other'});
    return {'other': name};
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Names repo, {
  Duration? refreshInterval,
  bool active = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(
        body: CommunityCommentsPanel(
          workId: 'work',
          repository: repo,
          currentUserId: 'me',
          active: active,
          refreshInterval: refreshInterval,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('SDK broadcast envelope reaches the name-only stream', () async {
    final client = SupabaseClient('https://example.invalid', 'test-public-key');
    // No socket is opened. Exercise the installed SDK's event dispatch directly.
    client.realtime.connState = SocketStates.open;
    final repo = SupabaseCommunityCommentRepository(
      client: client,
      identity: () => null,
    );
    var changes = 0;
    final subscription = repo
        .watchAuthorNameChanges('work')
        .listen((_) => changes++);
    final channel = client.getChannels().single;
    channel.trigger('broadcast', {
      'event': 'author_names_changed',
      'payload': {'work_id': 'work'},
      'type': 'broadcast',
    });
    channel.trigger('broadcast', {
      'event': 'author_names_changed',
      'payload': {'work_id': 'another-work'},
      'type': 'broadcast',
    });
    await Future<void>.delayed(Duration.zero);
    expect(changes, 1);
    await subscription.cancel();
    await client.dispose();
  });

  testWidgets(
    'official realtime invalidation updates loaded names and preserves draft',
    (tester) async {
      final repo = _Names()
        ..rows = [
          CommunityComment(
            id: 'old',
            workId: 'work',
            userId: 'other',
            body: 'comment body',
            authorName: 'cached name',
            createdAt: DateTime.utc(2026),
            status: CommunityCommentStatus.published,
          ),
        ];
      await _mount(tester, repo, refreshInterval: const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('旧昵称'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'unfinished draft');
      final fetches = repo.fetches;
      final reads = repo.reads;
      await tester.pump(const Duration(seconds: 5));
      expect(repo.reads, reads);
      repo.name = '新昵称';
      repo.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.text('新昵称'), findsOneWidget);
      expect(find.text('旧昵称'), findsNothing);
      expect(find.text('unfinished draft'), findsOneWidget);
      expect(repo.fetches, fetches);
      await _mount(
        tester,
        repo,
        active: false,
        refreshInterval: const Duration(seconds: 30),
      );
      final stoppedReads = repo.reads;
      repo.changes.add(null);
      await tester.pump(const Duration(seconds: 4));
      expect(repo.reads, stoppedReads);
      await _mount(
        tester,
        repo,
        active: true,
        refreshInterval: const Duration(seconds: 30),
      );
      await tester.pumpAndSettle();
      expect(repo.reads, greaterThan(stoppedReads));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(repo.changes.hasListener, isFalse);
      await repo.changes.close();
    },
  );
}
