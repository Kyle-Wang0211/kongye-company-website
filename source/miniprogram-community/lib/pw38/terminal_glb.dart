import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Never _bad(String detail) => throw FormatException('Terminal GLB: $detail');
Map<String, dynamic> _object(Object? value, String label) {
  if (value is! Map<String, dynamic>) _bad('$label must be an object');
  return value;
}
List<dynamic> _array(Object? value, String label) {
  if (value is! List || value.isEmpty) _bad('$label must be a nonempty array');
  return value;
}
int _integer(Object? value, String label, {int minimum = 0}) {
  if (value is! int || value < minimum || value > 0xffffffff) {
    _bad('$label must be an integer in [$minimum,4294967295]');
  }
  return value;
}
int _index(Object? value, List<dynamic> rows, String label) {
  final i = _integer(value, label);
  if (i >= rows.length) _bad('$label index out of bounds');
  return i;
}
Future<Uint8List> _read(RandomAccessFile file, int offset, int length) async {
  await file.setPosition(offset);
  final data = Uint8List(length);
  var done = 0;
  while (done < length) {
    final n = await file.readInto(data, done, length);
    if (n == 0) _bad('truncated read at ${offset + done}');
    done += n;
  }
  return data;
}
int _u32(Uint8List b, int offset) =>
    ByteData.sublistView(b).getUint32(offset, Endian.little);

final class _View {
  const _View(this.offset, this.length, this.stride);
  final int offset, length;
  final int? stride;
}
final class _Accessor {
  const _Accessor(this.offset, this.count, this.component, this.type, this.stride,
      this.elementBytes, this.normalized);
  final int offset, count, component, stride, elementBytes;
  final String type;
  final bool normalized;
}

/// Structural acceptance for the pinned Trimesh GLB2 embedded-image exporter.
/// JSON is capped at 8 MiB; binary reads are image prefixes/tails and bounded
/// index blocks. This does not decode images, render, or judge geometry quality.
Future<Map<String, Object?>> validateTerminalGlb(File file) async {
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
      FileSystemEntityType.file) _bad('output is not a regular file');
  final before = await file.stat();
  final length = before.size;
  if (length < 28 || length > 0xffffffff || length % 4 != 0) {
    _bad('invalid file length');
  }
  final handle = await file.open(mode: FileMode.read);
  try {
    final header = await _read(handle, 0, 12);
    if (_u32(header, 0) != 0x46546c67 || _u32(header, 4) != 2 ||
        _u32(header, 8) != length) _bad('magic/version/declared length mismatch');
    Map<String, dynamic>? tree;
    int? binOffset, binLength;
    var cursor = 12;
    final chunks = <Map<String, Object?>>[];
    while (cursor < length) {
      if (length - cursor < 8) _bad('truncated chunk header');
      final h = await _read(handle, cursor, 8);
      final size = _u32(h, 0), type = _u32(h, 4);
      cursor += 8;
      if (size % 4 != 0 || size > length - cursor) _bad('chunk alignment/bounds');
      if (chunks.isEmpty && type != 0x4e4f534a) _bad('first chunk is not JSON');
      if (type == 0x4e4f534a) {
        if (tree != null || chunks.isNotEmpty || size == 0 || size > 8 * 1024 * 1024) {
          _bad('duplicate, misplaced, empty or oversized JSON');
        }
        final text = utf8.decode(await _read(handle, cursor, size));
        // Exporter pads JSON with spaces, not NUL bytes.
        final end = text.lastIndexOf('}');
        if (end < 0 || text.substring(end + 1).codeUnits.any((c) => c != 32)) _bad('JSON root/padding');
        tree = _object(jsonDecode(text), 'JSON');
      } else if (type == 0x004e4942) {
        if (binOffset != null || chunks.length != 1 || size == 0) {
          _bad('duplicate, misplaced or empty BIN');
        }
        binOffset = cursor; binLength = size;
      } else {
        _bad('unsupported chunk type $type in selected exporter profile');
      }
      chunks.add({'type': type, 'bytes': size});
      cursor += size;
    }
    if (tree == null || binOffset == null || binLength == null || chunks.length != 2) {
      _bad('JSON and BIN chunks required');
    }
    final t = tree;
    final asset = _object(t['asset'], 'asset');
    if (asset['version'] != '2.0' || (asset.containsKey('minVersion') && asset['minVersion'] != '2.0')) {
      _bad('asset.version/minVersion');
    }
    final required = t['extensionsRequired'];
    if (required != null && (required is! List || required.isNotEmpty)) {
      _bad('required extensions unsupported');
    }
    final buffers = _array(t['buffers'], 'buffers');
    if (buffers.length != 1) _bad('single embedded buffer required');
    final buffer = _object(buffers.single, 'buffer');
    if (buffer.containsKey('uri')) _bad('external/data buffer URI unsupported');
    final bufferBytes = _integer(buffer['byteLength'], 'buffer.byteLength', minimum: 1);
    if (bufferBytes > binLength || binLength - bufferBytes > 3) _bad('BIN buffer length');
    if (binLength > bufferBytes &&
        (await _read(handle, binOffset + bufferBytes, binLength - bufferBytes)).any((b) => b != 0)) {
      _bad('nonzero BIN padding');
    }
    final viewRows = _array(t['bufferViews'], 'bufferViews');
    final views = <_View>[];
    for (var i = 0; i < viewRows.length; i++) {
      final v = _object(viewRows[i], 'bufferView[$i]');
      if (_integer(v['buffer'], 'view.buffer') != 0 || v.containsKey('extensions')) {
        _bad('bufferView buffer/extension unsupported');
      }
      final off = _integer(v['byteOffset'] ?? 0, 'view.byteOffset');
      final len = _integer(v['byteLength'], 'view.byteLength', minimum: 1);
      if (off % 4 != 0 || off > bufferBytes || len > bufferBytes - off) _bad('bufferView bounds/alignment');
      final stride = v.containsKey('byteStride') ? _integer(v['byteStride'], 'view.byteStride', minimum: 4) : null;
      if (stride != null && (stride > 252 || stride % 4 != 0)) _bad('bufferView stride');
      if (v.containsKey('target') && ![34962, 34963].contains(_integer(v['target'], 'view.target'))) _bad('bufferView target');
      views.add(_View(off, len, stride));
    }
    final accessorRows = _array(t['accessors'], 'accessors');
    final accessors = <_Accessor>[];
    const sizes = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4};
    const widths = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT2': 4, 'MAT3': 9, 'MAT4': 16};
    for (var i = 0; i < accessorRows.length; i++) {
      final a = _object(accessorRows[i], 'accessor[$i]');
      if (a.containsKey('sparse') || a.containsKey('extensions')) _bad('sparse/extended accessor unsupported');
      final v = views[_index(a['bufferView'], viewRows, 'accessor.bufferView')];
      final component = _integer(a['componentType'], 'accessor.componentType');
      final bytes = sizes[component]; final type = a['type']; final width = widths[type];
      if (bytes == null || width == null || type is! String) _bad('accessor component/type');
      var element = bytes * width;
      // Matrix columns have four-byte alignment, including byte/short matrices.
      if (type.startsWith('MAT')) {
        final side = int.parse(type.substring(3));
        element = ((bytes * side + 3) ~/ 4) * 4 * side;
      }
      final off = _integer(a['byteOffset'] ?? 0, 'accessor.byteOffset');
      final count = _integer(a['count'], 'accessor.count', minimum: 1);
      final stride = v.stride ?? element;
      if (type.startsWith('MAT') && ((v.offset + off) % 4 != 0 || stride % 4 != 0)) _bad('matrix column alignment');
      if (off % bytes != 0 || (v.offset + off) % bytes != 0 || stride < element || stride % bytes != 0 ||
          off > v.length || element > v.length - off || count > (v.length - off - element) ~/ stride + 1) {
        _bad('accessor count/stride/offset exceeds bufferView');
      }
      final normalized = a['normalized'] ?? false;
      if (normalized is! bool || (normalized && [5125, 5126].contains(component))) _bad('accessor.normalized');
      for (final key in ['min', 'max']) {
        if (a.containsKey(key)) {
          final bound = _array(a[key], 'accessor.$key');
          if (bound.length != width || bound.any((x) => x is! num || !x.isFinite)) _bad('accessor.$key components');
        }
      }
      accessors.add(_Accessor(v.offset + off, count, component, type, stride, element, normalized));
    }
    final images = _array(t['images'], 'images');
    final imageEvidence = <Map<String, Object?>>[];
    for (var i = 0; i < images.length; i++) {
      final image = _object(images[i], 'image[$i]');
      if (image.containsKey('uri') || image.containsKey('extensions')) _bad('image URI/extension unsupported');
      final v = views[_index(image['bufferView'], viewRows, 'image.bufferView')];
      if (v.stride != null || v.length < 4) _bad('image bufferView');
      final mime = image['mimeType'];
      final n = v.length < 33 ? v.length : 33;
      final prefix = await _read(handle, binOffset + v.offset, n);
      if (mime == 'image/png') {
        const magic = [137, 80, 78, 71, 13, 10, 26, 10];
        if (prefix.length < 33 || List.generate(8, (j) => prefix[j] == magic[j]).contains(false) ||
            ByteData.sublistView(prefix).getUint32(8, Endian.big) != 13 ||
            ascii.decode(prefix.sublist(12, 16)) != 'IHDR' ||
            ByteData.sublistView(prefix).getUint32(16, Endian.big) == 0 ||
            ByteData.sublistView(prefix).getUint32(20, Endian.big) == 0) _bad('PNG signature/IHDR');
      } else if (mime == 'image/jpeg') {
        if (prefix[0] != 255 || prefix[1] != 216 || prefix[2] != 255) _bad('JPEG signature');
        // _buffer_append includes up to three zero pad bytes in image views.
        final tailLength = v.length < 5 ? v.length : 5;
        final tail = await _read(handle, binOffset + v.offset + v.length - tailLength, tailLength);
        var end = tail.length;
        while (end > 0 && tail[end - 1] == 0 && tail.length - end < 3) { end--; }
        if (end < 2 || tail[end - 2] != 255 || tail[end - 1] != 217) _bad('JPEG end marker');
      } else { _bad('image MIME unsupported: $mime'); }
      imageEvidence.add({'image': i, 'mime_type': mime, 'bytes': v.length, 'signature_valid': true});
    }
    final textures = _array(t['textures'], 'textures');
    if (t.containsKey('samplers')) {
      for (final row in _array(t['samplers'], 'samplers')) {
        final s = _object(row, 'sampler');
        if (s.containsKey('magFilter') && ![9728, 9729].contains(_integer(s['magFilter'], 'sampler.magFilter'))) _bad('sampler.magFilter');
        if (s.containsKey('minFilter') && ![9728, 9729, 9984, 9985, 9986, 9987].contains(_integer(s['minFilter'], 'sampler.minFilter'))) _bad('sampler.minFilter');
        for (final key in ['wrapS', 'wrapT']) {
          if (s.containsKey(key) && ![33071, 33648, 10497].contains(_integer(s[key], 'sampler.$key'))) _bad('sampler.$key');
        }
      }
    }
    for (final row in textures) {
      final texture = _object(row, 'texture');
      if (texture.containsKey('extensions')) _bad('texture extension unsupported');
      _index(texture['source'], images, 'texture.source');
      if (texture.containsKey('sampler')) _index(texture['sampler'], _array(t['samplers'], 'samplers'), 'texture.sampler');
    }
    final materials = _array(t['materials'], 'materials');
    int textureImage(Object? row, String label, Map<String, dynamic> attributes) {
      final info = _object(row, label);
      if (info.containsKey('extensions')) _bad('texture info extension unsupported');
      final tex = _object(textures[_index(info['index'], textures, '$label.index')], 'texture');
      final uv = _integer(info['texCoord'] ?? 0, '$label.texCoord');
      if (!attributes.containsKey('TEXCOORD_$uv')) _bad('$label UV set missing');
      return _index(tex['source'], images, 'texture.source');
    }
    final meshes = _array(t['meshes'], 'meshes');
    var primitiveCount = 0, vertices = 0, triangles = 0;
    final meshEvidence = <Map<String, Object?>>[];
    for (var mi = 0; mi < meshes.length; mi++) {
      final mesh = _object(meshes[mi], 'mesh');
      for (final row in _array(mesh['primitives'], 'mesh.primitives')) {
        final p = _object(row, 'primitive');
        if (_integer(p['mode'] ?? 4, 'primitive.mode') != 4 || p.containsKey('extensions') || p.containsKey('targets')) {
          _bad('selected triangle primitive required; compression/morphs unsupported');
        }
        final attrs = _object(p['attributes'], 'primitive.attributes');
        final posIndex = _index(attrs['POSITION'], accessorRows, 'POSITION');
        final pos = accessors[posIndex];
        if (pos.type != 'VEC3' || pos.component != 5126 || pos.normalized || pos.offset % 4 != 0) _bad('POSITION format');
        final positionJson = _object(accessorRows[posIndex], 'POSITION accessor');
        if (!positionJson.containsKey('min') || !positionJson.containsKey('max')) _bad('POSITION bounds required');
        for (final entry in attrs.entries) {
          final a = accessors[_index(entry.value, accessorRows, 'attribute ${entry.key}')];
          if (a.component == 5125 || a.count != pos.count || a.offset % 4 != 0 || a.stride % 4 != 0) _bad('attribute component/count/alignment');
          if (entry.key.startsWith('TEXCOORD_') && (a.type != 'VEC2' ||
              !(a.component == 5126 || ([5121, 5123].contains(a.component) && a.normalized)))) _bad('UV format');
          if (entry.key == 'NORMAL' && (a.type != 'VEC3' || a.component != 5126 || a.normalized)) _bad('NORMAL format');
          if (entry.key == 'TANGENT' && (a.type != 'VEC4' || a.component != 5126 || a.normalized)) _bad('TANGENT format');
          if (entry.key.startsWith('COLOR_') && (!['VEC3', 'VEC4'].contains(a.type) ||
              !(a.component == 5126 || ([5121, 5123].contains(a.component) && a.normalized)))) _bad('COLOR format');
        }
        final ind = accessors[_index(p['indices'], accessorRows, 'primitive.indices')];
        if (ind.type != 'SCALAR' || ![5121, 5123, 5125].contains(ind.component) || ind.normalized ||
            ind.stride != ind.elementBytes || ind.count % 3 != 0) _bad('triangle index format/count');
        // Check actual index values in blocks, never materialize a whole BIN.
        for (var start = 0; start < ind.count;) {
          final count = (ind.count - start) < 16384 ? ind.count - start : 16384;
          final data = await _read(handle, binOffset + ind.offset + start * ind.elementBytes, count * ind.elementBytes);
          final b = ByteData.sublistView(data);
          for (var i = 0; i < count; i++) {
            final value = ind.elementBytes == 1 ? data[i] : ind.elementBytes == 2
                ? b.getUint16(i * 2, Endian.little) : b.getUint32(i * 4, Endian.little);
            if (value >= pos.count || value == (ind.elementBytes == 1 ? 255 : ind.elementBytes == 2 ? 65535 : 0xffffffff)) {
              _bad('index outside POSITION or primitive restart value');
            }
          }
          start += count;
        }
        final material = _object(materials[_index(p['material'], materials, 'primitive.material')], 'material');
        final pbr = _object(material['pbrMetallicRoughness'], 'material.pbrMetallicRoughness');
        final colorImage = textureImage(pbr['baseColorTexture'], 'baseColorTexture', attrs);
        final normalImage = textureImage(material['normalTexture'], 'normalTexture', attrs);
        primitiveCount++; vertices += pos.count; triangles += ind.count ~/ 3;
        meshEvidence.add({'mesh': mi, 'vertices': pos.count, 'triangles': ind.count ~/ 3,
          'base_color_image': colorImage, 'normal_image': normalImage});
      }
    }
    final nodes = _array(t['nodes'], 'nodes');
    final scenes = _array(t['scenes'], 'scenes');
    final scene = _object(scenes[_index(t['scene'] ?? 0, scenes, 'scene')], 'scene');
    final visiting = <int>{}, visited = <int>{}, rendered = <int>{};
    void visit(Object? value) {
      final i = _index(value, nodes, 'scene/node');
      if (visiting.contains(i)) _bad('node cycle');
      if (visited.contains(i)) return;
      visiting.add(i);
      final node = _object(nodes[i], 'node');
      if (node.containsKey('mesh')) rendered.add(_index(node['mesh'], meshes, 'node.mesh'));
      if (node.containsKey('children')) {
        final children = _array(node['children'], 'node.children');
        for (final child in children) { visit(child); }
      }
      visiting.remove(i); visited.add(i);
    }
    for (final n in _array(scene['nodes'], 'scene.nodes')) { visit(n); }
    if (rendered.isEmpty) _bad('active scene contains no mesh');
    final after = await file.stat();
    if (after.size != before.size || after.modified != before.modified || await handle.length() != length) {
      _bad('file changed during validation');
    }
    return {'status': 'PASS_TERMINAL_GLB_STRUCTURE', 'format': 'GLB2', 'file_bytes': length,
      'asset_version': '2.0', 'chunks': chunks, 'buffer_bytes': bufferBytes,
      'buffer_views': views.length, 'accessors': accessors.length, 'mesh_primitives': primitiveCount,
      'vertices': vertices, 'triangles': triangles, 'active_scene_meshes': rendered.length,
      'meshes': meshEvidence, 'embedded_images': imageEvidence, 'external_uris': false,
      'index_values_checked': true, 'json_limit_bytes': 8 * 1024 * 1024,
      'image_evidence': 'signature_and_header_only_not_full_codec_decode',
      'geometry_quality': 'NOT_ASSESSED', 'rendering': 'NOT_RUN'};
  } finally { await handle.close(); }
}
