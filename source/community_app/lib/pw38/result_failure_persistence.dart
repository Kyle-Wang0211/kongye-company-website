import 'dart:convert';
import 'dart:io';

typedef Pw38ResultWriter = Future<void> Function(File file, String contents);

Future<void> _writeResult(File file, String contents) async {
  await file.writeAsString(contents, flush: true);
}

/// A terminal failure remains useful in memory when even compact evidence
/// cannot be persisted. Checkpoints fail closed before the next native stage.
/// This never changes native ownership or authorizes a same-process retry.
Future<Map<String, Object?>> savePw38ResultSafely(
  File file,
  Map<String, Object?> value, {
  required bool terminal,
  Pw38ResultWriter? writer,
}) async {
  try {
    await (writer ?? _writeResult)(file, jsonEncode(value));
  } catch (error) {
    if (!terminal) {
      throw FileSystemException(
        'PW38 checkpoint persistence failed before next stage: $error',
        file.path,
      );
    }
    value['result_persistence_error'] = error.toString();
    value['result_persisted'] = false;
    value['full38_complete'] = false;
    if (value['exit_code'] == 0) {
      value['exit_code'] = 38;
      value['stopped_reason'] = 'Terminal result persistence failed: $error';
    }
    // On failure stopped_reason already identifies the original error. Do not
    // replace it with ENOSPC, attempt another large write, or delete old data.
  }
  return value;
}
