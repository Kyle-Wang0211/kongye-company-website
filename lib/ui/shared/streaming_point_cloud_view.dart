/// OpenLiDARViewer host. It streams registered COPC ranges; it never downloads
/// a full PLY or enters the static shared-viewer/model-identity pathway.
export 'streaming_point_cloud_view_stub.dart'
    if (dart.library.io) 'streaming_point_cloud_view_native.dart'
    if (dart.library.js_interop) 'streaming_point_cloud_view_web.dart';
