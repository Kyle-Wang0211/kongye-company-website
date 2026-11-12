import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/community/community_search_service.dart';
import 'package:pocketworld_flutter/community/feed_models.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/community/community_search_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SearchService extends CommunitySearchService {
  SearchService()
    : super(
        client: SupabaseClient(
          'https://example.test',
          'public',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  final queries = <String>[];
  final pending = <String, Completer<List<String>>>{};

  @override
  Future<List<String>> suggest(String query) {
    queries.add(query);
    return (pending[query] = Completer<List<String>>()).future;
  }

  @override
  Future<List<FeedWork>> search(String query) async => [];
}

void main() {
  testWidgets(
    'one character requests suggestions; stale results and clear are safe',
    (tester) async {
      final service = SearchService();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: CommunitySearchPage(service: service, onWorkSelected: (_) {}),
        ),
      );
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump(const Duration(milliseconds: 201));
      expect(service.queries, ['a']);
      await tester.enterText(find.byType(TextField), '中');
      await tester.pump(const Duration(milliseconds: 201));
      expect(service.queries, ['a', '中']);
      service.pending['中']!.complete(['中国']);
      await tester.pump();
      expect(find.text('中国'), findsOneWidget);
      service.pending['a']!.complete(['apple']);
      await tester.pump();
      expect(find.text('apple'), findsNothing);
      expect(find.text('中国'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(find.text('中国'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
