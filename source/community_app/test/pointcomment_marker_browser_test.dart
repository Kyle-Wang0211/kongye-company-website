// Browser integration with the existing shared-viewer transport. No GPU algorithm changes.
// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_internal_member
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pocketworld_flutter/community/community_service.dart';
import 'package:pocketworld_flutter/community/comments/comment_models.dart';
import 'package:pocketworld_flutter/community/feed_models.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/community/work_detail_page.dart';
import 'community_comments_panel_test.dart' show FakeComments, comment;

class _Service extends CommunityService {
  _Service() : super(client: Supabase.instance.client);
  @override
  String? get currentUserId => 'me';
  @override
  String modelUrlFor(String path) => 'https://fixture.invalid/model.glb';
  @override
  Future<int?> recordView(String id) async => 1;
}

class _Host extends StatefulWidget {
  const _Host(this.controller, this.ready, this.requests);
  final SharedViewerController controller;
  final VoidCallback ready;
  final List<Map<String, Object?>> requests;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  void initState() {
    super.initState();
    widget.controller.attachTransport(
      (request) async {
        widget.requests.add(request);
        widget.controller.receive({
          'protocol': sharedViewerProtocol,
          'id': request['id'],
          'ok': true,
          'result': request['method'] == 'getState'
              ? {
                  'status': 'ready',
                  'format': 'glb',
                  'error': null,
                  'disposed': false,
                }
              : null,
        });
      },
      registerBytes: (bytes, format) async =>
          Uri.parse('https://fixture.invalid/registered.glb'),
      releaseResource: (uri) async {},
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.ready());
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://fixture.invalid',
      anonKey: 'anon',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
  });
  testWidgets(
    'GLB shared-viewer hit event submits exact anchor and marker reopens comments',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final json = utf8.encode(
        '{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[]}]}',
      );
      final padded = (json.length + 3) ~/ 4 * 4;
      final bytes = Uint8List(20 + padded);
      final header = ByteData.sublistView(bytes);
      header.setUint32(0, 0x46546c67, Endian.little);
      header.setUint32(4, 2, Endian.little);
      header.setUint32(8, bytes.length, Endian.little);
      header.setUint32(12, padded, Endian.little);
      header.setUint32(16, 0x4e4f534a, Endian.little);
      bytes.fillRange(20, bytes.length, 32);
      bytes.setRange(20, 20 + json.length, json);
      final repo = FakeComments()
        ..assetSha256 = sha256.convert(bytes).toString()
        ..submitResult = CommunityComment.fromJson({
          ...comment(
            'saved-point',
            status: CommunityCommentStatus.review,
          ).toJson(),
          'body': '',
        })
        ..rows = [
          comment('pin', anchor: CommunityCommentAnchor(position: [3, 2, 1])),
        ];
      SharedViewerController? controller;
      final requests = <Map<String, Object?>>[];
      try {
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              MaterialApp(
                locale: const Locale('zh'),
                localizationsDelegates: AppL10n.localizationsDelegates,
                supportedLocales: AppL10n.supportedLocales,
                home: WorkDetailPage(
                  work: FeedWork(
                    id: 'work',
                    userId: 'owner',
                    title: 'GLB',
                    description: '',
                    format: 'glb',
                    modelStoragePath: 'model.glb',
                    thumbnailStoragePath: 'existing.jpg',
                    likesCount: 0,
                    viewsCount: 0,
                    publishedAt: null,
                    authorDisplayName: 'owner',
                    authorAvatarUrl: null,
                    likedByMe: false,
                  ),
                  service: _Service(),
                  commentRepository: repo,
                  viewerHostBuilder: (context, bridge, ready, error) {
                    controller = bridge;
                    return _Host(bridge, ready, requests);
                  },
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('work-detail-comments')),
            );
            await tester.pumpAndSettle();
            await tester.enterText(
              find.byKey(const Key('comment-input')),
              '保留文字',
            );
            await tester.pump();
            await tester.tap(find.byTooltip('选择模型点位'));
            await tester.pumpAndSettle();
            controller!.receive({
              'protocol': sharedViewerProtocol,
              'type': 'pw-viewer-surface-picked',
              'anchor': {
                'position': [1.5, 2.5, 3.5],
                'normal': [0, 1, 0],
                'cameraPosition': [4, 5, 6],
                'cameraTarget': [1, 2, 3],
              },
            });
            await tester.pumpAndSettle();
            expect(find.text('已选择模型点位'), findsOneWidget);
            List<dynamic> lastMarkers() =>
                (requests.lastWhere(
                          (r) => r['method'] == 'setSurfaceCommentMarkers',
                        )['args']
                        as Map)['markers']
                    as List;
            expect(
              lastMarkers().any(
                (m) =>
                    m['id'] == 'pw-draft-comment-point' &&
                    m['selected'] == true,
              ),
              isTrue,
            );
            final draftMarker =
                lastMarkers().singleWhere(
                      (m) => m['id'] == 'pw-draft-comment-point',
                    )
                    as Map;
            expect((draftMarker['anchor'] as Map)['position'], [1.5, 2.5, 3.5]);
            await tester.tap(find.byTooltip('移除模型点位'));
            await tester.pumpAndSettle();
            expect(
              lastMarkers().any((m) => m['id'] == 'pw-draft-comment-point'),
              isFalse,
            );
            await tester.tap(find.byTooltip('选择模型点位'));
            await tester.pumpAndSettle();
            controller!.receive({
              'protocol': sharedViewerProtocol,
              'type': 'pw-viewer-surface-picked',
              'anchor': {
                'position': [1.5, 2.5, 3.5],
                'normal': [0, 1, 0],
                'cameraPosition': [4, 5, 6],
                'cameraTarget': [1, 2, 3],
              },
            });
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const Key('comment-send')));
            await tester.pumpAndSettle();
            expect(repo.sent.single.anchor!.position, [1.5, 2.5, 3.5]);
            expect(repo.sent.single.anchor!.cameraPosition, [4, 5, 6]);
            expect(repo.sent.single.body, '保留文字');
            expect(
              lastMarkers().any((m) => m['id'] == 'pw-draft-comment-point'),
              isFalse,
            );
            final saved =
                lastMarkers().singleWhere((m) => m['id'] == 'saved-point')
                    as Map;
            expect((saved['anchor'] as Map)['position'], [1.5, 2.5, 3.5]);
            // A rejected server snapshot must revoke the private local point.
            repo.rows.add(
              comment('saved-point', status: CommunityCommentStatus.rejected),
            );
            await tester.tap(find.byTooltip('刷新评论'));
            await tester.pumpAndSettle();
            expect(lastMarkers().any((m) => m['id'] == 'saved-point'), isFalse);
            await tester.tap(find.byTooltip('关闭评论'));
            await tester.pumpAndSettle();
            expect(find.byKey(const Key('comment-input')), findsNothing);
            controller!.receive({
              'protocol': sharedViewerProtocol,
              'type': 'pw-viewer-surface-marker-selected',
              'id': 'pin',
            });
            await tester.pumpAndSettle();
            expect(find.byKey(const Key('comment-input')), findsOneWidget);
            expect(find.text('body-pin'), findsOneWidget);
            expect(requests.where((r) => r['method'] == 'load'), hasLength(1));
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          },
          () => MockClient((request) async => http.Response.bytes(bytes, 200)),
        );
      } catch (error, stack) {
        debugPrint('POINT_INTEGRATION_FAILURE $error\n$stack');
        rethrow;
      }
    },
  );
}
