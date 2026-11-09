// Test host deliberately exercises the shared package transport seam.
// ignore_for_file: invalid_use_of_internal_member
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pocketworld_flutter/ui/shared/product_model_view.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';
import 'package:pocketworld_flutter/ui/community/community_loading.dart';

void main() {
  testWidgets(
    'unknown progress retains numeric label and never completes early',
    (tester) async {
      late SharedViewerController controller;
      String? loadId;
      bool attached = false;
      final client = http.Client();
      await tester.pumpWidget(
        MaterialApp(
          home: ProductModelView(
            modelUrl: 'https://example.test/model.glb',
            interactive: true,
            browserModelClient: client,
            hostBuilder: (_, value, ready, _) {
              controller = value;
              if (!attached) {
                attached = true;
                controller.attachTransport((message) async {
                  if (message['method'] == 'load') {
                    loadId = message['id'] as String;
                    return;
                  }
                  controller.receive({
                    'protocol': sharedViewerProtocol,
                    'id': message['id'],
                    'ok': true,
                    'result': null,
                  });
                });
                WidgetsBinding.instance.addPostFrameCallback((_) => ready());
              }
              return const SizedBox.expand();
            },
          ),
        ),
      );
      await tester.pump();
      expect(loadId, isNotNull);
      void progress(int received, int? total) => controller.receive({
        'protocol': sharedViewerProtocol,
        'type': 'pw-viewer-download-progress',
        'id': loadId,
        'receivedBytes': received,
        'totalBytes': total,
      });
      expect(find.byType(CommunityShimmer), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      progress(1, null);
      await tester.pump();
      expect(find.text('0%'), findsOneWidget);
      progress(40, 100);
      await tester.pump();
      expect(find.text('40%'), findsOneWidget);
      progress(50, null);
      await tester.pump();
      expect(find.text('40%'), findsOneWidget);
      final ring = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(ring.value, isNull);
      progress(100, 100);
      await tester.pump();
      expect(find.text('99%'), findsOneWidget);
      expect(find.text('100%'), findsNothing);
      expect(find.text('—'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      client.close();
    },
  );
}
