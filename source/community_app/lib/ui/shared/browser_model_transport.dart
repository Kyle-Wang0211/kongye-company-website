import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../../community/glb_cache.dart' show kMaxInMemoryBytes;

/// Fetch once with the browser's standard HTTP cache, hash and load the same
/// owned bytes. Identity is published only after successful current-epoch load.
Future<String?> loadBrowserModelBytes({
  required Uri uri,
  required Future<void> Function(Uint8List) load,
  required bool Function() isCurrent,
  http.Client? client,
}) async {
  if (uri.scheme != 'https' && uri.scheme != 'http') {
    throw ArgumentError.value(uri, 'uri', 'Expected HTTP(S) model URL');
  }
  if (!isCurrent()) return null;
  final transport = client ?? http.Client();
  try {
    final response = await transport.send(http.Request('GET', uri))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('Model download failed: HTTP ${response.statusCode}');
    }
    if ((response.contentLength ?? 0) > kMaxInMemoryBytes) {
      throw StateError('Model exceeds the existing in-memory model limit');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(const Duration(seconds: 180))) {
      if (!isCurrent()) return null;
      if (builder.length + chunk.length > kMaxInMemoryBytes) {
        throw StateError('Model exceeds the existing in-memory model limit');
      }
      builder.add(chunk);
    }
    if (!isCurrent()) return null;
    // Own the buffer before exposing it to the host; transport chunks may be views.
    final bytes = Uint8List.fromList(builder.takeBytes()).asUnmodifiableView();
    if (bytes.isEmpty) throw StateError('Model download is empty');
    final identity = sha256.convert(bytes).toString();
    await load(bytes);
    return isCurrent() ? identity : null;
  } finally {
    if (client == null) transport.close();
  }
}
