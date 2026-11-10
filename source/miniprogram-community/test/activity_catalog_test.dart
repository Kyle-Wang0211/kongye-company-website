import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pocketworld_flutter/community/activity_repository.dart';
import 'package:pocketworld_flutter/ui/community/activity_feed.dart';

Map<String, Object?> snapshot({
  String slug = 'porcelain',
  int revision = 1,
  int order = 1,
  String title = 'Published title',
  String cover = 'https://kongye.space/cover.png',
  String id = '00000000-0000-0000-0000-000000000001',
}) => {
  'id': id,
  'slug': slug,
  'revision': revision,
  'published_at': '2026-11-10T00:00:00Z',
  'content': {
    'title': title,
    'cover_url': cover,
    'sort_order': order,
    'template_key': 'article',
    'detail': {'summary': 'Published summary'},
  },
};

void main() {
  test(
    'official public RPC reads each complete published snapshot including empty',
    () async {
      Object response = [snapshot()];
      final client = SupabaseClient(
        'https://api.kongye.space',
        'public-test-key',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/list_community_activities');
          return http.Response(
            jsonEncode(response),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      final repo = ActivityRepository(client: client);
      final first = (await repo.list()).single;
      expect(first.title, 'Published title');
      expect(first.summary, 'Published summary');
      expect(first.destination.queryParameters['activity'], 'porcelain');
      response = [
        snapshot(
          title: 'New title',
          revision: 2,
          cover: 'https://api.kongye.space/new.png',
        ),
      ];
      final next = (await repo.list()).single;
      expect(next.id, first.id);
      expect(next.revision, 2);
      expect(next.title, 'New title');
      expect(next.coverUrl, 'https://api.kongye.space/new.png');
      response = [];
      expect(await repo.list(), isEmpty);
      await client.dispose();
    },
  );

  test(
    'slugs match the published contract including repeated and trailing hyphens',
    () {
      for (final slug in ['spring--sale', 'spring-', 'a', 'a' * 80]) {
        expect(
          ActivityRepository.parse([snapshot(slug: slug)]).single.slug,
          slug,
        );
      }
      for (final slug in ['-spring', 'a' * 81, '', 'Spring', 'spring_sale']) {
        expect(
          () => ActivityRepository.parse([snapshot(slug: slug)]),
          throwsFormatException,
        );
      }
    },
  );

  test('ordering and strict external URL validation', () {
    final entries = ActivityRepository.parse([
      snapshot(order: 8),
      snapshot(
        order: 0,
        slug: 'other',
        id: '00000000-0000-0000-0000-000000000002',
      ),
    ]);
    expect(entries.first.slug, 'other');
    for (final url in [
      'http://kongye.space/a',
      'https://kongye.space.evil/a',
      'javascript:alert(1)',
      '//kongye.space/a',
      'https://user@kongye.space/a',
      'https://kongye.space:444/a',
    ]) {
      expect(
        () => ActivityRepository.parse([snapshot(cover: url)]),
        throwsFormatException,
      );
    }
    expect(() => ActivityRepository.parse({}), throwsFormatException);
    expect(
      () => ActivityRepository.parse([snapshot(), snapshot()]),
      throwsFormatException,
    );
  });

  test(
    'stale success and failure cannot replace newer state, errors retain valid state',
    () async {
      final requests = <Completer<List<CommunityActivity>>>[];
      final controller = ActivityCatalogController(() {
        final request = Completer<List<CommunityActivity>>();
        requests.add(request);
        return request.future;
      });
      final old = controller.refresh();
      final current = controller.refresh();
      requests[1].complete(
        ActivityRepository.parse([snapshot(title: 'Latest')]),
      );
      await current;
      requests[0].complete(ActivityRepository.parse([snapshot(title: 'Old')]));
      await old;
      expect(controller.entries.single.title, 'Latest');
      final failure = controller.refresh();
      requests.last.completeError(StateError('offline'));
      await failure;
      expect(controller.entries.single.title, 'Latest');
      final empty = controller.refresh();
      requests.last.complete([]);
      await empty;
      expect(controller.entries, isEmpty);
      final late = controller.refresh();
      controller.dispose();
      requests.last.complete(ActivityRepository.parse([snapshot()]));
      await late;
      expect(controller.entries, isEmpty);
    },
  );

  testWidgets(
    'enter, visibility, resume and pull use fresh catalog with disposal guard',
    (tester) async {
      var calls = 0;
      var response = ActivityRepository.parse([snapshot()]);
      Future<void> Function()? refresh;
      Widget feed(bool visible) => MaterialApp(
        home: ActivityFeed(
          isVisible: visible,
          load: () async {
            calls++;
            return response;
          },
          builder: (context, entries, reload) {
            refresh = reload;
            return Text(entries.map((e) => e.title).join(','));
          },
        ),
      );
      await tester.pumpWidget(feed(true));
      await tester.pump();
      expect(find.text('Published title'), findsOneWidget);
      expect(calls, 1);
      response = ActivityRepository.parse([snapshot(title: 'Pull update')]);
      await refresh!();
      await tester.pump();
      expect(find.text('Pull update'), findsOneWidget);
      await tester.pumpWidget(feed(false));
      await tester.pumpWidget(feed(true));
      await tester.pump();
      expect(calls, 3);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls, 4);
      response = [];
      await refresh!();
      await tester.pump();
      expect(find.text('Pull update'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await refresh!();
      expect(calls, 5);
      expect(tester.takeException(), isNull);
    },
  );
}
