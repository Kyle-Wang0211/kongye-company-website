import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/auth/phone_country_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every country has a bundled decodable 96 by 72 PNG flag', () async {
    expect(phoneCountries.length, 245);
    for (final country in phoneCountries) {
      final path = 'assets/auth/flags/${country.iso.toLowerCase()}.png';
      final data = await rootBundle.load(path);
      expect(data.buffer.asUint8List().take(8), [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ], reason: path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 96, reason: path);
      expect(frame.image.height, 72, reason: path);
      frame.image.dispose();
      codec.dispose();
    }
  });
}
