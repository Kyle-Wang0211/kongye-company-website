import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/community/publication_cover_url.dart';
import 'package:pocketworld_flutter/ui/community/published_cover.dart';

void main() {
  test('server cover endpoint stays on the API origin and ordinary paths retain their route', () {
    final origin = Uri.parse('https://api.example.test/rest/v1');
    const path =
        '/functions/v1/publication-cover?work_id=11111111-1111-4111-8111-111111111111';
    expect(publicationCoverUrl(origin, path), 'https://api.example.test$path');
    for (final invalid in [
      'owner/cover.jpg',
      'https://other.test$path',
      '$path&token=private',
      '$path#fragment',
      '/functions/v1/publication-cover?work_id=invalid',
    ]) {
      expect(publicationCoverUrl(origin, invalid), isNull);
    }
  });
  test(
    'the three reviewed model identities reuse their canonical public covers',
    () {
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
    },
  );
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
