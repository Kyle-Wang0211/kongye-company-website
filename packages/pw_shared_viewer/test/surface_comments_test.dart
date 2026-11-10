import 'package:flutter_test/flutter_test.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';

void main() {
  test('floating panel layout validates finite viewport coordinates and clears',
      () {
    final c = SharedViewerController();
    final packet = <String, Object?>{
      'protocol': sharedViewerProtocol,
      'type': 'pw-viewer-surface-marker-layout',
      'layout': {'id': 'comment-1', 'x': .2, 'y': .7, 'expanded': true},
    };
    c.receive(packet);
    expect(c.surfaceMarkerLayout!.id, 'comment-1');
    expect(c.surfaceMarkerLayout!.x, .2);
    expect(c.surfaceMarkerLayout!.expanded, isTrue);
    expect(c.surfaceMarkerLayoutRevision, 1);
    for (final invalid in [double.nan, -1.0, 1.1, double.infinity]) {
      c.receive({
        ...packet,
        'layout': {'id': 'bad', 'x': invalid, 'y': .5, 'expanded': true}
      });
      expect(c.surfaceMarkerLayoutRevision, 1);
    }
    c.receive({
      ...packet,
      'layout': {'id': 'bad', 'x': '0.2', 'y': .5, 'expanded': true}
    });
    c.receive({...packet, 'protocol': 'wrong'});
    c.receive({...packet}..remove('layout'));
    expect(c.surfaceMarkerLayoutRevision, 1);
    final value = SharedSurfaceMarkerLayout.fromJson(
        {'id': 'c', 'x': .5, 'y': .4, 'expanded': false});
    expect(value.toJson(), {'id': 'c', 'x': .5, 'y': .4, 'expanded': false});
    c.receive({...packet, 'layout': null});
    expect(c.surfaceMarkerLayout, isNull);
    expect(c.surfaceMarkerLayoutRevision, 2);
    c.dispose();
  });
  test('anchor validates and freezes finite root-local coordinates', () {
    final values = [1.0, 2.0, 3.0];
    final anchor = SharedSurfaceAnchor(
        position: values, cameraPosition: [0, 0, 5], cameraTarget: [0, 0, 0]);
    values[0] = 99;
    expect(anchor.position, [1, 2, 3]);
    expect(SharedSurfaceAnchor.fromJson(anchor.toJson()).cameraPosition,
        [0, 0, 5]);
    for (final p in [
      [0.0, 1.0],
      [0.0, double.nan, 0.0],
      [0.0, double.infinity, 0.0],
      [1e20, 0.0, 0.0]
    ]) {
      expect(() => SharedSurfaceAnchor(position: p), throwsArgumentError);
    }
  });
  test(
      'surface events require protocol and valid anchor; each legal pick increments revision',
      () {
    final c = SharedViewerController();
    var notifications = 0;
    c.addListener(() => notifications++);
    final pick = {
      'type': 'pw-viewer-surface-picked',
      'anchor': {
        'position': [1, 2, 3]
      }
    };
    c.receive(pick);
    expect(c.surfacePickRevision, 0);
    c.receive({
      ...pick,
      'protocol': sharedViewerProtocol,
      'anchor': {
        'position': [1, 2]
      }
    });
    expect(c.surfacePickRevision, 0);
    c.receive({...pick, 'protocol': sharedViewerProtocol});
    c.receive({...pick, 'protocol': sharedViewerProtocol});
    expect(c.surfacePickRevision, 2);
    expect(c.pickedSurface!.position, [1, 2, 3]);
    expect(notifications, 2);
    c.receive({
      'protocol': sharedViewerProtocol,
      'type': 'pw-viewer-surface-marker-selected',
      'id': 'comment-1'
    });
    expect(c.selectedSurfaceMarkerId, 'comment-1');
    c.dispose();
  });
  test('surface commands transport validated anchors and bound markers',
      () async {
    final c = SharedViewerController();
    final requests = <Map<String, Object?>>[];
    c.attachTransport((p) async {
      requests.add(p);
      c.receive({'protocol': sharedViewerProtocol, 'id': p['id'], 'ok': true});
    });
    final a = SharedSurfaceAnchor(position: [0, 0, 0]);
    await c.setSurfaceCommentMode(true);
    await c.setSurfaceCommentMarkers(
        [SharedSurfaceMarker(id: 'c', anchor: a, number: 1)]);
    await c.focusSurfaceComment(a);
    expect(requests.map((p) => p['method']), [
      'setSurfaceCommentMode',
      'setSurfaceCommentMarkers',
      'focusSurfaceComment'
    ]);
    await expectLater(
        c.setSurfaceCommentMarkers(List.generate(257,
            (i) => SharedSurfaceMarker(id: '$i', anchor: a, number: i + 1))),
        throwsArgumentError);
    c.dispose();
  });
}
