// Copyright 2018 The Chromium Authors
// Use of this source code is governed by a BSD-style license in LICENSE.chromium.
// Arithmetic port of components/download/internal/common/rate_estimator.cc at
// chromium/chromium@0da097971657251c27bfdf098250dc770fe79cce.
// Explicit integer millisecond clock replaces base::TimeTicks, but bucket
// denominators, truncation and uint32 bucket wrap are preserved. No smoothing.
class ChromiumRateEstimator {
  ChromiumRateEstimator({
    required int nowMs,
    this.bucketSeconds = 1,
    int numBuckets = 10,
  }) : assert(bucketSeconds > 0),
       assert(numBuckets > 0),
       _history = List.filled(numBuckets, 0),
       _oldestTimeMs = nowMs;

  final int bucketSeconds;
  final List<int> _history;
  int _oldestIndex = 0;
  int _bucketCount = 1;
  int _oldestTimeMs;
  int get windowDurationMs => _history.length * bucketSeconds * 1000;

  void increment(int count, int nowMs) {
    if (count < 0 || count > 0xffffffff) {
      throw RangeError.range(count, 0, 0xffffffff, 'count');
    }
    _clearOldBuckets(nowMs);
    final seconds = (nowMs - _oldestTimeMs) ~/ 1000;
    final delta = seconds ~/ bucketSeconds;
    final index = (_oldestIndex + delta) % _history.length;
    _history[index] = (_history[index] + count) & 0xffffffff;
  }

  int countPerSecond(int nowMs) {
    _clearOldBuckets(nowMs);
    var total = 0;
    for (var i = 0; i < _bucketCount; i++) {
      total += _history[(_oldestIndex + i) % _history.length];
    }
    // Dart native int is signed64; the original total is uint64. With an
    // in-memory list of uint32 buckets, overflow requires >2^31 buckets.
    return total ~/ (_bucketCount * bucketSeconds);
  }

  void _clearOldBuckets(int nowMs) {
    final seconds = (nowMs - _oldestTimeMs) ~/ 1000;
    final delta = seconds ~/ bucketSeconds;
    if (delta < 0) {
      _reset(nowMs);
      return;
    }
    if (delta < _history.length) {
      _bucketCount = delta + 1;
      return;
    }
    final extra = delta - _history.length + 1;
    if (extra > _history.length) {
      _reset(nowMs);
      return;
    }
    _bucketCount = _history.length;
    for (var i = 0; i < extra; i++) {
      _history[_oldestIndex] = 0;
      _oldestIndex = (_oldestIndex + 1) % _history.length;
      _oldestTimeMs += bucketSeconds * 1000;
    }
  }

  void _reset(int nowMs) {
    _history.fillRange(0, _history.length, 0);
    _oldestIndex = 0;
    _bucketCount = 1;
    _oldestTimeMs = nowMs;
  }
}
