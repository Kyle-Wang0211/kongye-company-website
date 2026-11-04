import 'package:flutter_test/flutter_test.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';

void main() {
  test(
      'selection bridge preserves source-world JSON and explicitly clears draft',
      () async {
    final controller = SharedViewerController();
    final calls = <Map<String, Object?>>[];
    controller.attachTransport((packet) async {
      calls.add(packet);
      controller.receive({
        'protocol': sharedViewerProtocol,
        'id': packet['id'],
        'ok': true,
        'result': packet['method'] == 'getSelectionBounds'
            ? {
                'min': [10, -3, 4],
                'max': [20, 5, 9]
              }
            : null
      });
    });
    final box = <String, dynamic>{
      'v': 2,
      'cx': 15.0,
      'cy': 1.0,
      'cz': 6.5,
      'sx': 10.0,
      'sy': 8.0,
      'sz': 5.0,
      'rot': [1, 0, 0, 0, 1, 0, 0, 0, 1]
    };
    expect((await controller.getSelectionBounds())!['min'], [10, -3, 4]);
    await controller.setSelectionPreview(box);
    expect((calls.last['args'] as Map)['box'], box);
    await controller.setSelectionPreview(null);
    expect((calls.last['args'] as Map).containsKey('box'), isTrue);
    expect((calls.last['args'] as Map)['box'], isNull);
    controller.dispose();
  });
}
