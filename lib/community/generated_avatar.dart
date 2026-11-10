import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// An authenticated server projection of one actual official Jdenticon image.
/// The seed remains server-side. This decorative image is not an identity proof.
class GeneratedAvatarImage {
  GeneratedAvatarImage._(this.png, this.pngSha256, this.pixelSha256);
  static const version = 'jdenticon-3.3.0-pw-v2';
  final Uint8List png;
  final String pngSha256;
  final String pixelSha256;

  static GeneratedAvatarImage? tryParse(Object? value) {
    if (value is! Map || value['version'] != version) return null;
    final encoded = value['png_base64'];
    final pngHash = value['png_sha256'];
    final pixelHash = value['pixel_sha256'];
    final digest = RegExp(r'^[0-9a-f]{64}$');
    if (encoded is! String ||
        encoded.length > 22000 ||
        pngHash is! String ||
        pixelHash is! String ||
        !digest.hasMatch(pngHash) ||
        !digest.hasMatch(pixelHash)) {
      return null;
    }
    try {
      final png = base64Decode(encoded);
      if (png.length < 100 ||
          png.length > 16384 ||
          sha256.convert(png).toString() != pngHash) {
        return null;
      }
      const signature = [137, 80, 78, 71, 13, 10, 26, 10];
      for (var i = 0; i < 8; i++) {
        if (png[i] != signature[i]) return null;
      }
      final data = ByteData.sublistView(png);
      if (data.getUint32(16) != 128 || data.getUint32(20) != 128) return null;
      return GeneratedAvatarImage._(png, pngHash, pixelHash);
    } on FormatException {
      return null;
    }
  }

  Map<String, String> toJson() => {
    'version': version,
    'png_base64': base64Encode(png),
    'png_sha256': pngSha256,
    'pixel_sha256': pixelSha256,
  };
}
