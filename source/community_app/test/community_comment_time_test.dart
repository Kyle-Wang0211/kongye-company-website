import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/community/comments/comment_time.dart';

void main() {
  final now = DateTime(2026, 11, 3, 18, 30);
  test(
    '24h minus/at/plus one millisecond uses elapsed time before calendar label',
    () {
      expect(
        formatCommunityCommentTime(
          now
              .subtract(const Duration(hours: 24))
              .add(const Duration(milliseconds: 1)),
          now: now,
        ),
        '18:30',
      );
      expect(
        formatCommunityCommentTime(
          now.subtract(const Duration(hours: 24)),
          now: now,
        ),
        '18:30',
      );
      expect(
        formatCommunityCommentTime(
          now.subtract(const Duration(hours: 24, milliseconds: 1)),
          now: now,
        ),
        '昨天',
      );
    },
  );
  test('crossing midnight while younger than 24h still displays HH:mm', () {
    expect(
      formatCommunityCommentTime(
        DateTime(2026, 11, 2, 23, 59),
        now: DateTime(2026, 11, 3, 0, 1),
      ),
      '23:59',
    );
  });
  test('older dates use local calendar yesterday/day before/date labels', () {
    expect(
      formatCommunityCommentTime(DateTime(2026, 11, 2, 17), now: now),
      '昨天',
    );
    expect(
      formatCommunityCommentTime(DateTime(2026, 11, 1, 23), now: now),
      '前天',
    );
    expect(
      formatCommunityCommentTime(
        DateTime(2026, 10, 31, 23),
        now: DateTime(2026, 11, 3, 0, 1),
      ),
      '10月31日',
    );
    expect(
      formatCommunityCommentTime(DateTime(2025, 12, 31), now: now),
      '12月31日',
    );
  });
  test('invalid values are blank and future values show their actual date', () {
    for (final value in [null, 'invalid', {}, 42]) {
      expect(formatCommunityCommentTime(value, now: now), '');
    }
    expect(
      formatCommunityCommentTime(
        now.add(const Duration(milliseconds: 1)),
        now: now,
      ),
      '11月3日',
    );
    expect(formatCommunityCommentTime(DateTime(2027, 1, 1), now: now), '1月1日');
  });
  test(
    'English and Chinese preserve the same calendar and elapsed boundaries',
    () {
      for (final locale in ['en', 'zh']) {
        final english = locale == 'en';
        expect(
          formatCommunityCommentTime(
            now.subtract(const Duration(hours: 24)),
            now: now,
            locale: locale,
          ),
          '18:30',
        );
        expect(
          formatCommunityCommentTime(
            now.subtract(const Duration(hours: 24, milliseconds: 1)),
            now: now,
            locale: locale,
          ),
          english ? 'Yesterday' : '昨天',
        );
        expect(
          formatCommunityCommentTime(
            DateTime(2026, 11, 1, 23),
            now: now,
            locale: locale,
          ),
          english ? '2 days ago' : '前天',
        );
        expect(
          formatCommunityCommentTime(
            DateTime(2026, 10, 31, 23),
            now: now,
            locale: locale,
          ),
          english ? '10/31' : '10月31日',
        );
        expect(
          formatCommunityCommentTime(
            now.add(const Duration(milliseconds: 1)),
            now: now,
            locale: locale,
          ),
          english ? '11/3' : '11月3日',
        );
      }
    },
  );
}
