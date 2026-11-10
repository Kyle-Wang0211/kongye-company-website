// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Port of the speed/progress/throttle subset of DownloadCore.sys.mjs::_setBytes
// at mozilla-firefox/firefox@d0d4af3c69ea85c292cbbdf68ae00126d5bae45b.
// Gecko notification/part-file side effects are excluded. The caller dispatches
// the original one-shot throttle using nextUpdateMs / flushDue. No idle samples
// or Firefox's separate downward-biased displayed-ETA smoothing are included.
class FirefoxEma {
  double speed = 0;
  void observeRawSpeed(double rawSpeed) {
    if (speed == 0) {
      speed = rawSpeed;
    } else {
      speed = rawSpeed * 0.1 + speed * 0.9;
    }
  }
}

class FirefoxDownloadSpeed {
  final _ema = FirefoxEma();
  double get speed => _ema.speed;
  int currentBytes = 0;
  int totalBytes = 0;
  int progress = 0;
  bool hasProgress = false;
  int _lastProgressTimeMs = 0;
  int _throttledCurrentBytes = 0;
  int? nextUpdateMs;

  void setBytes(int current, int total, int nowMs) {
    if (total != -1 && (!hasProgress || totalBytes != total)) {
      hasProgress = true;
      totalBytes = total;
    }
    final intervalMs = nowMs - _lastProgressTimeMs;
    if (intervalMs >= 400) {
      nextUpdateMs = null;
      if (_lastProgressTimeMs != 0) {
        _ema.observeRawSpeed(((current - currentBytes) / intervalMs) * 1000);
      }
      if (current > 0) {
        _lastProgressTimeMs = nowMs;
        currentBytes = current;
        if (totalBytes > 0) {
          progress = ((currentBytes / totalBytes) * 100).floor();
        }
      }
    } else if (hasProgress) {
      _throttledCurrentBytes = current;
      nextUpdateMs ??= nowMs + 400 - intervalMs;
    }
  }

  void flushDue(int nowMs) {
    final due = nextUpdateMs;
    if (due != null && due <= nowMs) {
      // Dispatch once at its actual execution time, as a delayed Gecko timer.
      setBytes(_throttledCurrentBytes, totalBytes, nowMs);
    }
  }
}
