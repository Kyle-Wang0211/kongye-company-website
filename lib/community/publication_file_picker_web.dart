import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:web/web.dart' as web;

/// The browser retains its native File handle. No data URL, Object URL, full
/// FileReader operation or file-sized ArrayBuffer is created by selection.
Future<XFile?> pickPublicationFile() {
  final result = Completer<XFile?>();
  final input = web.document.createElement('input') as web.HTMLInputElement;
  input
    ..type = 'file'
    ..accept = '.glb,.ply'
    ..multiple = false;
  input.style.display = 'none';

  late final JSFunction changed;
  late final JSFunction cancelled;
  void cleanup() {
    input.removeEventListener('change', changed);
    input.removeEventListener('cancel', cancelled);
    input.remove();
  }

  void finish(XFile? file) {
    if (result.isCompleted) return;
    cleanup();
    result.complete(file);
  }

  changed = ((web.Event event) {
    final files = input.files;
    finish(
      files == null || files.length == 0
          ? null
          : _BrowserPublicationFile(files.item(0)!),
    );
  }).toJS;
  cancelled = ((web.Event event) => finish(null)).toJS;
  input.addEventListener('change', changed);
  input.addEventListener('cancel', cancelled);
  try {
    web.document.body!.append(input);
    input.click();
  } catch (error, stack) {
    cleanup();
    result.completeError(error, stack);
  }
  return result.future;
}

/// XFile's URL rehydration path rejects >=4GiB on Safari. Keep the original
/// File and slice it directly through the standard File/Blob API instead.
/// Even an unbounded openRead emits only one 6MiB slice at a time.
class _BrowserPublicationFile extends XFile {
  _BrowserPublicationFile(this._file) : super('');
  final web.File _file;
  static const _chunkBytes = 6 * 1024 * 1024;

  @override
  String get name => _file.name;
  @override
  String get mimeType => _file.type;
  @override
  Future<int> length() async => _file.size;
  @override
  Future<DateTime> lastModified() async =>
      DateTime.fromMillisecondsSinceEpoch(_file.lastModified);

  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    final first = start ?? 0;
    final last = end ?? _file.size;
    if (first < 0 || last < first || last > _file.size) {
      throw RangeError('Invalid publication file range');
    }
    for (var offset = first; offset < last; offset += _chunkBytes) {
      final next = math.min(last, offset + _chunkBytes);
      final buffer = await _file.slice(offset, next).arrayBuffer().toDart;
      final bytes = buffer.toDart.asUint8List();
      if (bytes.length != next - offset) {
        throw StateError('Publication file range is incomplete');
      }
      yield bytes;
    }
  }

  @override
  Future<Uint8List> readAsBytes() =>
      throw UnsupportedError('Use bounded publication file ranges');
}
