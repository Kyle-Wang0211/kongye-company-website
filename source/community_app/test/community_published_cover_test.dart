import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/ui/community/published_cover.dart';

void main() {
  test('the three reviewed model identities reuse their canonical public covers', () {
    for (final path in [
      '76db4d238fba298028a8be1157601e1c39159b1ebd4d73917ec3e66a549088b2/source.glb',
      'f80acfbf8e1c88a096187a59c41dcb98e9a78c263044d5d8bc7a0187ab0e4ccc/source.glb',
      '3e4fce6fe2014ec83de31dd47930f7946b458ae615bf4b9526a2d65a0a944d2a/source.glb',
    ]) {
      expect(
        publishedModelCover(path),
        startsWith('https://kongye.space/assets/models/cma-'),
      );
    }
  });
  test(
    'unknown or modified model identities never inherit another work cover',
    () {
      expect(publishedModelCover(null), isNull);
      expect(publishedModelCover('owner/another.glb'), isNull);
      expect(
        publishedModelCover(
          '76db4d238fba298028a8be1157601e1c39159b1ebd4d73917ec3e66a549088b2/source.glb?changed',
        ),
        isNull,
      );
    },
  );
}
