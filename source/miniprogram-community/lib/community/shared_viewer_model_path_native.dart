import 'glb_cache.dart';

Future<String> resolveSharedViewerModelPath(String url) => GlbCache.instance.fetchPath(url);
