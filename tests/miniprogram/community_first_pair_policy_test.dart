import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/community/feed_models.dart';
import 'package:pocketworld_flutter/ui/community/first_pair_policy.dart';
import 'package:pocketworld_flutter/ui/community/masonry_policy.dart';

FeedWork work(int n, {String? modelPath}) => FeedWork(
  id: '$n',
  userId: 'author',
  title: '$n',
  description: null,
  format: 'glb',
  modelStoragePath: modelPath ?? '$n.glb',
  thumbnailStoragePath: null,
  likesCount: 0,
  viewsCount: 0,
  publishedAt: null,
  authorDisplayName: 'Creator',
  authorAvatarUrl: null,
  likedByMe: false,
);
CommunityCardMetrics size(
  double viewerHeight, {
  double? cardHeight,
  double width = 190,
  double dpr = 3,
}) => CommunityCardMetrics(
  cardSize: Size(width, cardHeight ?? viewerHeight + 55),
  viewerSize: Size(width, viewerHeight),
  pixelRatio: dpr,
);

void main() {
  final works = List.generate(6, work);
  Map<String, CommunityCardMetrics> measured(
    Map<int, CommunityCardMetrics> values,
  ) => {
    for (final e in values.entries)
      communityCoverSourceKey(works[e.key]): e.value,
  };
  List<String>? ids(List<FeedWork>? list) => list?.map((w) => w.id).toList();

  test(
    'select a natural matching pair and preserve every other item in raw order',
    () {
      final m = measured({
        0: size(150),
        1: size(220),
        2: size(180),
        3: size(180),
        4: size(250),
        5: size(240),
      });
      expect(ids(communityFirstPairOrder(works, m)), [
        '2',
        '3',
        '0',
        '1',
        '4',
        '5',
      ]);
      expect(works.map((w) => w.id), ['0', '1', '2', '3', '4', '5']);
      expect(m[communityCoverSourceKey(works[2])]!.viewerSize.height, 180);
    },
  );
  test(
    'a shorter matching pair is valid; height preference is not imposed',
    () {
      expect(
        ids(
          communityFirstPairOrder(
            works,
            measured({0: size(150), 1: size(150), 2: size(250), 3: size(250)}),
          ),
        ),
        ['0', '1', '2', '3', '4', '5'],
      );
    },
  );
  test(
    'same viewer size with different title metadata height does not fake an equal card',
    () {
      expect(
        communityFirstPairOrder(
          works,
          measured({
            0: size(190, cardHeight: 245),
            1: size(190, cardHeight: 262),
          }),
        ),
        isNull,
      );
    },
  );
  test('same whole-card size with different viewer heights is not a match', () {
    expect(
      communityFirstPairOrder(
        works,
        measured({
          0: size(190, cardHeight: 260),
          1: size(205, cardHeight: 260),
        }),
      ),
      isNull,
    );
  });
  test(
    'no known pair remains pending rather than manufacturing equal heights',
    () {
      expect(
        communityFirstPairOrder(
          works,
          measured({0: size(150), 1: size(180), 2: size(210)}),
        ),
        isNull,
      );
      expect(communityFirstPairOrder(works, {}), isNull);
    },
  );
  test(
    'reselect with each refreshed order, without mutating cached dimensions',
    () {
      final m = measured({
        0: size(180),
        1: size(210),
        2: size(210),
        3: size(180),
      });
      expect(ids(communityFirstPairOrder(works, m)), [
        '0',
        '3',
        '1',
        '2',
        '4',
        '5',
      ]);
      final refreshed = [
        works[2],
        works[1],
        works[3],
        works[0],
        works[5],
        works[4],
      ];
      expect(ids(communityFirstPairOrder(refreshed, m)), [
        '2',
        '1',
        '3',
        '0',
        '5',
        '4',
      ]);
    },
  );
  test('invalid measurements and different viewport widths cannot pair', () {
    expect(
      communityFirstPairOrder(
        works,
        measured({
          0: size(180, width: 190),
          1: size(180, width: 200),
          2: size(double.nan),
        }),
      ),
      isNull,
    );
    expect(
      communityFirstPairOrder(
        works,
        measured({0: size(180, dpr: 0), 1: size(180, dpr: 0)}),
      ),
      isNull,
    );
  });
  test(
    'source changes invalidate a measurement even when the work id is unchanged',
    () {
      final m = measured({0: size(180), 1: size(180)});
      final changed = [work(0, modelPath: 'new.glb'), ...works.skip(1)];
      expect(communityFirstPairOrder(changed, m), isNull);
    },
  );
  test('empty and single-item feeds need no fabricated partner', () {
    expect(communityFirstPairOrder([], {}), isEmpty);
    expect(ids(communityFirstPairOrder([works.first], {})), ['0']);
  });
}
