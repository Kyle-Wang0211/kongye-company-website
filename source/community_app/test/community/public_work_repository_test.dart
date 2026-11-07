import 'dart:async';
import 'dart:convert';

// Reuse Flutter's locked test timer dependency without changing the lockfile.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pocketworld_flutter/community/feed_models.dart';
import 'package:pocketworld_flutter/community/public_work_repository.dart';

const _workId = '12345678-1234-4234-8234-123456789abc';
const _viewerId = '12345678-1234-4234-8234-123456789abd';
const _otherId = '12345678-1234-4234-8234-123456789abe';
const _work = {
  'id': _workId,
  'user_id': _otherId,
  'title': 'Public work',
  'description': 'Description',
  'format': 'glb',
  'model_storage_path': 'owner/model.glb',
  'thumbnail_storage_path': 'owner/cover.png',
  'initial_view': {'zoom': 2},
  'file_size_bytes': 123,
  'likes_count': 4,
  'comments_count': 5,
  'views_count': 6,
  'published_at': '2026-11-07T01:00:00Z',
  'publish_region': 'Shanghai',
};
const _profile = {
  'id': _otherId,
  'display_name': 'Author',
  'avatar_url': 'avatar.png',
  'handle': 'author',
};

class _PendingRead {
  _PendingRead(this.request);
  final http.BaseRequest request;
  final response = Completer<http.StreamedResponse>();

  void complete(Object? data) {
    response.complete(
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(data))),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      ),
    );
  }
}

class _DeferredClient extends http.BaseClient {
  final reads = <_PendingRead>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final read = _PendingRead(request);
    reads.add(read);
    return read.response.future;
  }

  _PendingRead pendingFor(String table) =>
      reads.singleWhere((read) => read.request.url.path == '/rest/v1/$table');
}

class _Load {
  _Load(this.clock, this.client, this.transport, {bool signedIn = true}) {
    if (signedIn) switchAccount(_viewerId);
    repository = PublicWorkRepository(client);
  }

  final FakeAsync clock;
  final _DeferredClient transport;
  final SupabaseClient client;
  late final PublicWorkRepository repository;
  FeedWork? result;
  Object? error;
  StackTrace? stack;
  bool completed = false;

  void switchAccount(String id) {
    client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'test-token',
        'token_type': 'bearer',
        'user': {'id': id, 'aud': 'authenticated', 'created_at': ''},
      }),
    );
    clock.flushMicrotasks();
  }

  void start({String id = _workId}) {
    repository
        .fetch(id)
        .then(
          (work) {
            result = work;
            completed = true;
          },
          onError: (Object failure, StackTrace trace) {
            error = failure;
            stack = trace;
            completed = true;
          },
        );
    clock.flushMicrotasks();
  }

  void releaseWork() {
    transport.pendingFor('works').complete([_work]);
    clock.flushMicrotasks();
  }

  void expectConcurrentReads() {
    expect(transport.reads.length, 3);
    expect(
      transport.pendingFor('community_author_profiles').response.isCompleted,
      false,
    );
    expect(transport.pendingFor('work_likes').response.isCompleted, false);
  }
}

void main() {
  late _DeferredClient transport;
  late SupabaseClient client;
  setUp(() {
    transport = _DeferredClient();
    client = SupabaseClient(
      'https://example.invalid',
      'test-public-key',
      httpClient: transport,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDown(() => client.dispose());

  test(
    'profile and like overlap while the FeedWork projection stays intact',
    () {
      fakeAsync((clock) {
        final load = _Load(clock, client, transport)..start();
        expect(load.transport.reads.length, 1);
        final query = load.transport
            .pendingFor('works')
            .request
            .url
            .queryParameters;
        expect(query['visibility'], 'eq.public');
        expect(query['moderation_status'], 'eq.ok');
        expect(query['published_at'], 'not.is.null');
        expect(query['deleted_at'], 'is.null');
        load.releaseWork();
        load.expectConcurrentReads();
        final likeQuery = load.transport
            .pendingFor('work_likes')
            .request
            .url
            .queryParameters;
        expect(likeQuery['user_id'], 'eq.$_viewerId');
        expect(likeQuery['work_id'], 'eq.$_workId');
        load.transport.pendingFor('work_likes').complete([
          {'work_id': _workId},
        ]);
        clock.flushMicrotasks();
        expect(load.completed, false);
        load.transport.pendingFor('community_author_profiles').complete([
          _profile,
        ]);
        clock.flushMicrotasks();
        expect(load.error, isNull);
        final work = load.result!;
        expect(work.id, _workId);
        expect(work.userId, _otherId);
        expect(work.title, 'Public work');
        expect(work.description, 'Description');
        expect(work.format, 'glb');
        expect(work.modelStoragePath, 'owner/model.glb');
        expect(work.thumbnailStoragePath, 'owner/cover.png');
        expect(work.initialView, {'zoom': 2});
        expect(work.fileSizeBytes, 123);
        expect(work.likesCount, 4);
        expect(work.commentCount, 5);
        expect(work.viewsCount, 6);
        expect(work.publishedAt, DateTime.utc(2026, 11, 7, 1));
        expect(work.publishRegion, 'Shanghai');
        expect(work.authorDisplayName, 'Author');
        expect(work.authorAvatarUrl, 'avatar.png');
        expect(work.authorHandle, 'author');
        expect(work.likedByMe, true);
      });
    },
  );

  test(
    'A-B-A account return defers a skipped like read until profile passes',
    () {
      fakeAsync((clock) {
        final load = _Load(clock, client, transport)..start();
        load.switchAccount(_otherId);
        load.releaseWork();
        expect(load.transport.reads.length, 2);
        expect(
          load.transport
              .pendingFor('community_author_profiles')
              .response
              .isCompleted,
          false,
        );
        load.switchAccount(_viewerId);
        expect(load.transport.reads.length, 2);
        expect(load.completed, false);
        load.transport.pendingFor('community_author_profiles').complete([
          _profile,
        ]);
        clock.flushMicrotasks();
        expect(load.transport.reads.length, 3);
        expect(load.completed, false);
        final likeQuery = load.transport
            .pendingFor('work_likes')
            .request
            .url
            .queryParameters;
        expect(likeQuery['user_id'], 'eq.$_viewerId');
        expect(likeQuery['work_id'], 'eq.$_workId');
        load.transport.pendingFor('work_likes').complete([
          {'work_id': _workId},
        ]);
        clock.flushMicrotasks();
        expect(load.error, isNull);
        expect(load.result!.likedByMe, true);
        expect(load.result!.id, _workId);
      });
    },
  );

  for (final profileFails in [false, true]) {
    test('early like error is held with profile failure=$profileFails', () {
      fakeAsync((clock) {
        final load = _Load(clock, client, transport)
          ..start()
          ..releaseWork();
        load.expectConcurrentReads();
        final likeError = StateError('like failure');
        final likeStack = StackTrace.fromString('original like stack');
        load.transport
            .pendingFor('work_likes')
            .response
            .completeError(likeError, likeStack);
        clock.flushMicrotasks();
        expect(load.completed, false);
        final profileError = StateError('profile failure');
        if (profileFails) {
          load.transport
              .pendingFor('community_author_profiles')
              .response
              .completeError(profileError);
        } else {
          load.transport.pendingFor('community_author_profiles').complete([
            _profile,
          ]);
        }
        clock.flushMicrotasks();
        expect(load.error, same(profileFails ? profileError : likeError));
        if (!profileFails) {
          expect(load.stack.toString(), contains('original like stack'));
        }
        expect(load.result, isNull);
      });
    });
  }

  for (final profileComplete in [false, true]) {
    test(
      'account switch after profile complete=$profileComplete rejects stale work',
      () {
        fakeAsync((clock) {
          final load = _Load(clock, client, transport)
            ..start()
            ..releaseWork();
          load.expectConcurrentReads();
          if (profileComplete) {
            load.transport.pendingFor('community_author_profiles').complete([
              _profile,
            ]);
            clock.flushMicrotasks();
          }
          load.switchAccount(_otherId);
          load.transport.pendingFor('work_likes').complete([
            {'work_id': _workId},
          ]);
          if (!profileComplete) {
            load.transport.pendingFor('community_author_profiles').complete([
              _profile,
            ]);
          }
          clock.flushMicrotasks();
          expect(
            load.error,
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Public work account changed during load',
            ),
          );
          expect(load.result, isNull);
        });
      },
    );
  }

  test('first identity check precedes an already failed like', () {
    fakeAsync((clock) {
      final load = _Load(clock, client, transport)
        ..start()
        ..releaseWork();
      load.expectConcurrentReads();
      load.transport
          .pendingFor('work_likes')
          .response
          .completeError(StateError('like failure'));
      clock.flushMicrotasks();
      load.switchAccount(_otherId);
      load.transport.pendingFor('community_author_profiles').complete([
        _profile,
      ]);
      clock.flushMicrotasks();
      expect(load.error.toString(), contains('account changed'));
      expect(load.result, isNull);
    });
  });

  test(
    'anonymous missing author uses existing defaults without a like request',
    () {
      fakeAsync((clock) {
        final load = _Load(clock, client, transport, signedIn: false)
          ..start()
          ..releaseWork();
        expect(load.transport.reads.length, 2);
        load.transport.pendingFor('community_author_profiles').complete([]);
        clock.flushMicrotasks();
        expect(load.result!.authorDisplayName, 'unknown');
        expect(load.result!.authorAvatarUrl, isNull);
        expect(load.result!.authorHandle, isNull);
        expect(load.result!.likedByMe, false);
      });
    },
  );

  test('inaccessible work stops before any dependent reads', () {
    fakeAsync((clock) {
      final load = _Load(clock, client, transport)..start();
      load.transport.pendingFor('works').complete([]);
      clock.flushMicrotasks();
      expect(load.error, isA<StateError>());
      expect(load.result, isNull);
      expect(load.transport.reads.length, 1);
    });
  });

  test('invalid ID fails before any requests', () {
    fakeAsync((clock) {
      final load = _Load(clock, client, transport)..start(id: 'invalid');
      expect(load.error, isA<FormatException>());
      expect(load.transport.reads, isEmpty);
    });
  });

  for (final table in ['works', 'community_author_profiles', 'work_likes']) {
    test('$table keeps its 15 second timeout', () {
      fakeAsync((clock) {
        final load = _Load(clock, client, transport)..start();
        if (table != 'works') {
          load.releaseWork();
          load.expectConcurrentReads();
          final otherTable = table == 'work_likes'
              ? 'community_author_profiles'
              : 'work_likes';
          load.transport.pendingFor(otherTable).complete([]);
          clock.flushMicrotasks();
        }
        clock.elapse(const Duration(seconds: 14));
        expect(load.completed, false);
        clock.elapse(const Duration(seconds: 1));
        expect(load.error, isA<TimeoutException>());
        expect(load.result, isNull);
        load.transport
            .pendingFor(table)
            .complete(table == 'works' ? [_work] : []);
        clock.flushMicrotasks();
        expect(load.error, isA<TimeoutException>());
        expect(load.result, isNull);
      });
    });
  }
}
