import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../official_capture/selection_box.dart';

/// Immutable transport of the user's existing box; no projection or fitting.
final class ReconstructionRegion {
  ReconstructionRegion._(
    this.box15,
    this.selection,
    this.selectedDepthDir,
    this.planSha256,
  );

  static const schema = 'PW38_RECONSTRUCTION_REGION_V1';
  final List<double> box15;
  final Map<String, dynamic> selection;
  final String selectedDepthDir, planSha256;

  factory ReconstructionRegion.fromSelection(
    SelectionBox selection, {
    String selectedDepthDir = 'region_depth',
  }) {
    if (selection.rot.length != 9) {
      throw const FormatException('Full nine-value rotation required');
    }
    final saved = _selection(selection.toJson());
    final box = _box(SelectionBox.fromJson(saved)!);
    final base = _base(box, saved, _path(selectedDepthDir));
    return ReconstructionRegion._(
      List.unmodifiable(box),
      saved,
      selectedDepthDir,
      _hash(base),
    );
  }

  factory ReconstructionRegion.fromJson(Object? value) {
    if (value is! Map ||
        value.length != 5 ||
        value['schema'] != schema ||
        value['box15'] is! List ||
        (value['box15'] as List).length != 15 ||
        value['selected_depth_dir'] is! String ||
        value['plan_sha256'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(value['plan_sha256'] as String)) {
      throw const FormatException('Malformed reconstruction region');
    }
    final saved = _selection(value['selection']);
    final expected = _box(SelectionBox.fromJson(saved)!);
    final box = (value['box15'] as List).map(_double).toList();
    for (var i = 0; i < 15; i++) {
      if (!_bitsEqual(box[i], expected[i])) {
        throw const FormatException('Region box differs from saved selection');
      }
    }
    final directory = _path(value['selected_depth_dir'] as String);
    final hash = _hash(_base(box, saved, directory));
    if (hash != value['plan_sha256']) {
      throw const FormatException('Reconstruction region plan hash mismatch');
    }
    return ReconstructionRegion._(
      List.unmodifiable(box),
      saved,
      directory,
      hash,
    );
  }

  static ReconstructionRegion? fromRequest(Map<String, dynamic> request) =>
      request.containsKey('reconstruction_region')
      ? ReconstructionRegion.fromJson(request['reconstruction_region'])
      : null;

  Map<String, dynamic> toJson() => {
    ..._base(box15, selection, selectedDepthDir),
    'plan_sha256': planSha256,
  };
}

Map<String, dynamic> _base(
  List<double> box,
  Map<String, dynamic> selection,
  String directory,
) => {
  'schema': ReconstructionRegion.schema,
  'box15': box,
  'selection': selection,
  'selected_depth_dir': directory,
};
String _hash(Map<String, dynamic> value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

double _double(Object? value) {
  if (value is! num || !value.isFinite) {
    throw const FormatException('Finite region coordinate required');
  }
  return value.toDouble();
}

Map<String, dynamic> _selection(Object? value) {
  const keys = ['v', 'cx', 'cy', 'cz', 'sx', 'sy', 'sz', 'rot', 'yawDeg'];
  if (value is! Map ||
      value.length != keys.length ||
      !keys.every(value.containsKey) ||
      value['v'] != kSelectionBoxSchemaVersion ||
      value['rot'] is! List ||
      (value['rot'] as List).length != 9) {
    throw const FormatException('Current full-rotation selection required');
  }
  final copied = <String, dynamic>{'v': kSelectionBoxSchemaVersion};
  for (final key in keys.skip(1)) {
    copied[key] = key == 'rot'
        ? List<double>.unmodifiable((value[key] as List).map(_double))
        : _double(value[key]);
  }
  final parsed = SelectionBox.fromJson(copied);
  if (parsed == null || parsed.sx <= 0 || parsed.sy <= 0 || parsed.sz <= 0) {
    throw const FormatException('Positive region dimensions required');
  }
  return Map.unmodifiable(copied);
}

List<double> _box(SelectionBox value) => [
  value.cx,
  value.cy,
  value.cz,
  value.sx,
  value.sy,
  value.sz,
  ...value.rot,
];

bool _bitsEqual(double a, double b) {
  final bytes = ByteData(16)
    ..setFloat64(0, a)
    ..setFloat64(8, b);
  return bytes.getUint64(0) == bytes.getUint64(8);
}

String _path(String value) {
  if (value.isEmpty ||
      !RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9._/-]*$').hasMatch(value) ||
      value.split('/').any((p) => p.isEmpty || p == '.' || p == '..')) {
    throw const FormatException('Canonical relative selected subtree required');
  }
  return value;
}
