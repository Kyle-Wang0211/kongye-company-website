/// Public COPC derivatives explicitly enabled for community streaming.
/// Add an entry only after its immutable object is uploaded and range-served.
/// Ordinary GLB and unregistered PLY retain the existing shared viewer route.
const Map<String, String> pointCloudStreamingSources = {
  '110df056-bd11-49f0-992f-3b27e3f29429': 'https://api.kongye.space/storage/v1/object/public/works/b5e271cb-1bc9-4738-b83d-4e98e4803579/streaming-ee0ea729a8f9e302cb38003addaffca0c1beecb0cd8453bef144a3667bb4add2.copc.laz',
  '36734643-fc11-4d54-9cfe-9f7366babb01': 'https://api.kongye.space/storage/v1/object/public/works/b5e271cb-1bc9-4738-b83d-4e98e4803579/streaming-183f60bfacc9cad581d7e0344b812ac6566780b9656dc1ddf1decfbdbc5ae150.copc.laz',
  'b42756ae-36f0-4fda-8f30-b592b915dfa4': 'https://api.kongye.space/storage/v1/object/public/works/b5e271cb-1bc9-4738-b83d-4e98e4803579/streaming-9a14584c6eae41b11800de4964561ed51d70f1c17fef43de58e3a6dbd0b956fc.copc.laz',
};

Uri? pointCloudStreamingSourceFor(String workId) {
  final value = pointCloudStreamingSources[workId];
  if (value == null) return null;
  final source = Uri.parse(value);
  if (source.scheme != 'https' ||
      source.host != 'api.kongye.space' ||
      source.userInfo.isNotEmpty ||
      source.hasFragment ||
      !source.path.toLowerCase().endsWith('.copc.laz')) {
    throw StateError('Invalid registered public COPC source');
  }
  return source;
}
