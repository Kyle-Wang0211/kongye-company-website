@TestOn('browser')
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';
import 'package:web/web.dart' as web;

void main() {
  Future<void> mount(WidgetTester tester, SharedViewerController controller,
      VoidCallback ready, ValueChanged<Object> error, Uri entry) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(width: 320, height: 200, child: SharedViewer(
        controller: controller, onReady: ready, onError: error,
        webEntryUri: entry,
      )),
    ));
    await tester.pump();
  }

  testWidgets('missing readiness reports one bounded error and never attaches', (tester) async {
    final controller = SharedViewerController();
    var ready = 0;
    final errors = <Object>[];
    await mount(tester, controller, () => ready++, errors.add,
      Uri.parse(web.document.baseURI).resolve('missing-viewer-startup-test.html'));
    await tester.pump(const Duration(seconds: 36));
    expect(errors.length, 1);
    expect(errors.single.toString(), contains('did not report readiness'));
    expect(ready, 0);
    expect(controller.isAttached, false);
    await tester.pump(const Duration(seconds: 36));
    expect(errors.length, 1);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('foreign entry fails once without attaching transport', (tester) async {
    final controller = SharedViewerController();
    var ready = 0;
    final errors = <Object>[];
    await mount(tester, controller, () => ready++, errors.add, Uri.parse('https://example.invalid/viewer'));
    expect(errors.length, 1);
    expect(errors.single.toString(), contains('same-origin'));
    expect(ready, 0);
    expect(controller.isAttached, false);
    await tester.pump(const Duration(seconds: 36));
    expect(errors.length, 1);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
