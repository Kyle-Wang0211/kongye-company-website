// Browser URLs are loaded directly by the same-origin shared viewer host.
Future<String> resolveSharedViewerModelPath(String url) =>
    Future.error(UnsupportedError('Browser viewer uses URL transport'));
