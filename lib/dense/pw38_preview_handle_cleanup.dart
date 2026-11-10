import 'dart:io';

/// Display-only readers never own reconstruction resources. A failed close
/// must neither replace a successful reconstruction result nor skip the other
/// readers. The OS also releases these descriptors when their isolate exits.
void closePw38PreviewHandles(Iterable<RandomAccessFile?> handles) {
  for (final handle in handles) {
    try {
      handle?.closeSync();
    } catch (_) {
      // Optional display cleanup cannot become a numerical pipeline failure.
    }
  }
}
