/// Surface anchors are bound by the host to one immutable asset revision.
/// Position and normal use the current model root's local space. Camera vectors
/// use the existing viewer scene space. Animated/replaced models are unsupported.
class SharedSurfaceAnchor {
  SharedSurfaceAnchor(
      {required List<double> position,
      List<double>? normal,
      List<double>? cameraPosition,
      List<double>? cameraTarget})
      : position = _vector(position, 'position'),
        normal = normal == null ? null : _vector(normal, 'normal'),
        cameraPosition = cameraPosition == null
            ? null
            : _vector(cameraPosition, 'cameraPosition'),
        cameraTarget = cameraTarget == null
            ? null
            : _vector(cameraTarget, 'cameraTarget') {
    if ((cameraPosition == null) != (cameraTarget == null)) {
      throw ArgumentError(
          'Camera position and target must be supplied together');
    }
    if (normal != null && normal.every((v) => v == 0)) {
      throw ArgumentError('Normal must be nonzero');
    }
  }
  final List<double> position;
  final List<double>? normal, cameraPosition, cameraTarget;
  static List<double> _vector(List<double> values, String name) {
    if (values.length != 3 ||
        values.any((v) => !v.isFinite || v.abs() > 1e12)) {
      throw ArgumentError.value(
          values, name, 'Expected three bounded finite coordinates');
    }
    return List<double>.unmodifiable(values);
  }

  static List<double> _decode(Object? value) {
    if (value is! List || value.length != 3 || value.any((v) => v is! num)) {
      throw ArgumentError('Invalid surface vector');
    }
    return value.map((v) => (v as num).toDouble()).toList();
  }

  factory SharedSurfaceAnchor.fromJson(Map<String, Object?> json) =>
      SharedSurfaceAnchor(
        position: _decode(json['position']),
        normal: json['normal'] == null ? null : _decode(json['normal']),
        cameraPosition: json['cameraPosition'] == null
            ? null
            : _decode(json['cameraPosition']),
        cameraTarget:
            json['cameraTarget'] == null ? null : _decode(json['cameraTarget']),
      );
  Map<String, Object?> toJson() => {
        'position': position,
        if (normal != null) 'normal': normal,
        if (cameraPosition != null) 'cameraPosition': cameraPosition,
        if (cameraTarget != null) 'cameraTarget': cameraTarget,
      };
}

/// Position of the visible comment panel anchor in the viewer's own viewport.
/// Rendering and projection stay in Three.js; the host only lays out its UI.
class SharedSurfaceMarkerLayout {
  SharedSurfaceMarkerLayout(
      {required this.id,
      required this.x,
      required this.y,
      required this.expanded}) {
    if (id.isEmpty ||
        id.length > 128 ||
        !x.isFinite ||
        !y.isFinite ||
        x < 0 ||
        x > 1 ||
        y < 0 ||
        y > 1) {
      throw ArgumentError('Invalid surface marker layout');
    }
  }
  final String id;
  final double x, y;
  final bool expanded;
  factory SharedSurfaceMarkerLayout.fromJson(Map<String, Object?> json) {
    final id = json['id'],
        x = json['x'],
        y = json['y'],
        expanded = json['expanded'];
    if (id is! String || x is! num || y is! num || expanded is! bool) {
      throw ArgumentError('Invalid surface marker layout');
    }
    return SharedSurfaceMarkerLayout(
        id: id, x: x.toDouble(), y: y.toDouble(), expanded: expanded);
  }
  Map<String, Object?> toJson() =>
      {'id': id, 'x': x, 'y': y, 'expanded': expanded};
}

class SharedSurfaceMarker {
  SharedSurfaceMarker(
      {required this.id,
      required this.anchor,
      required this.number,
      this.previewText = '',
      List<String> previewImages = const [],
      this.selected = false})
      : previewImages = List.unmodifiable(previewImages) {
    if (id.isEmpty || id.length > 128 || number < 1 || number > 999999) {
      throw ArgumentError('Invalid surface marker identity or number');
    }
    if (previewText.length > 2000 ||
        previewImages.length > 3 ||
        previewImages.any((url) {
          final uri = Uri.tryParse(url);
          return url.length > 4096 ||
              uri == null ||
              uri.userInfo.isNotEmpty ||
              uri.host.isEmpty ||
              !(uri.scheme == 'https' ||
                  (uri.scheme == 'http' &&
                      const ['localhost', '127.0.0.1', '::1']
                          .contains(uri.host)));
        })) {
      throw ArgumentError('Invalid surface comment content');
    }
  }
  final String id;
  final SharedSurfaceAnchor anchor;
  final int number;
  final bool selected;
  final String previewText;
  final List<String> previewImages;
  Map<String, Object?> toJson() => {
        'id': id,
        'anchor': anchor.toJson(),
        'number': number,
        'selected': selected,
        if (previewText.isNotEmpty) 'previewText': previewText,
        if (previewImages.isNotEmpty) 'previewImages': previewImages,
      };
}
