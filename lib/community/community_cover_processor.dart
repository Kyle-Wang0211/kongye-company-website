import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../util/image_sanitize.dart';

/// One community display resolution. Original input bytes are never modified.
/// Uses the existing image 4.3.0 orientation, resize and JPEG implementations.
/// Width is capped at 600; height remains proportional, with no upscaling,
/// cropping, byte-size target, or quality-search loop.
Uint8List prepareCommunityCover(Uint8List input) {
  // The upload broker already caps thumbnail inputs at ten MiB. Check decoder
  // dimensions before allocating pixels, as the existing evidence processor does.
  if (input.isEmpty || input.lengthInBytes > 10 * 1024 * 1024) {
    throw const FormatException('Invalid community cover image.');
  }
  try {
    final decoder = img.findDecoderForData(input);
    if (decoder == null ||
        !const [
          img.ImageFormat.jpg,
          img.ImageFormat.png,
        ].contains(decoder.format)) {
      throw const FormatException('Community covers require JPEG or PNG.');
    }
    final info = decoder.startDecode(input);
    if (info == null ||
        info.width <= 0 ||
        info.height <= 0 ||
        info.width * info.height > 40 * 1000 * 1000) {
      throw const FormatException(
        'Community cover pixels could not be decoded.',
      );
    }
    final decoded = decoder.decodeFrame(0);
    if (decoded == null) {
      throw const FormatException(
        'Community cover pixels could not be decoded.',
      );
    }
    var bitmap = img.bakeOrientation(decoded);
    if (bitmap.width > 600) {
      bitmap = img.copyResize(
        bitmap,
        width: 600,
        interpolation: img.Interpolation.average,
      );
    }
    // copyResize rounds inferred heights; JPEG stores dimensions in 16 bits.
    // Never sign/upload an empty or unrepresentable encoded frame.
    if (bitmap.width < 1 ||
        bitmap.height < 1 ||
        bitmap.width > 65535 ||
        bitmap.height > 65535) {
      throw const FormatException('Community cover cannot be encoded as JPEG.');
    }
    // A fresh RGB image retains the complete frame and composites transparency
    // on the viewer's black, rather than changing the image's aspect ratio.
    final rgb = img.Image(
      width: bitmap.width,
      height: bitmap.height,
      numChannels: 3,
    );
    img.compositeImage(rgb, bitmap);
    return encodeSanitizedJpg(rgb);
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('Community cover pixels could not be decoded.');
  }
}
