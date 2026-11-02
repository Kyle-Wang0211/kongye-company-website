import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/auth/phone_country_catalog.dart';
import 'package:pocketworld_flutter/auth/phone_number_input.dart';

void main() {
  test('all 245 geographic regions retain exact mobile examples', () {
    expect(phoneCountries, hasLength(245));
    expect(phoneCountries.map((c) => c.iso).toSet(), hasLength(245));
    expect(phoneCountries.any((c) => c.iso == '001'), isFalse);
    for (final country in phoneCountries) {
      expect(country.flag.runes.length, 2);
      if (country.mobileExample.isNotEmpty) {
        expect(
          normalizePhoneSignup(country.mobileExample, country),
          '+${country.callingCode}${country.mobileExample}',
          reason: country.iso,
        );
      }
    }
  });
  test(
    'login retains China compatibility and explicit international numbers',
    () {
      expect(normalizePhoneLogin('13800000000'), '+8613800000000');
      expect(normalizePhoneLogin('+44 7400 123456'), '+447400123456');
      expect(normalizePhoneLogin('0044 7400 123456'), '+447400123456');
      expect(normalizePhoneLogin('07400123456'), isNull);
      expect(normalizePhoneLogin('person@example.test'), isNull);
    },
  );
  test('signup never doubles country code and rejects mismatching code', () {
    final gb = phoneCountryForIso('GB');
    expect(normalizePhoneSignup('+44 7400 123456', gb), '+447400123456');
    expect(normalizePhoneSignup('00447400123456', gb), '+447400123456');
    expect(normalizePhoneSignup('+8613800000000', gb), isNull);
    expect(normalizePhoneSignup('07400123456', gb), isNull);
  });
  test(
    'Italian significant zero is preserved rather than silently stripped',
    () {
      final italy = phoneCountryForIso('IT');
      expect(
        canonicalSignupNationalNumber('+39 02 12345678', italy),
        '0212345678',
      );
      expect(canonicalSignupNationalNumber('0212345678', italy), '0212345678');
      // This is fixed-line format, outside the pinned MOBILE pattern.
      expect(normalizePhoneSignup('0212345678', italy), isNull);
      expect(normalizePhoneSignup(italy.mobileExample, italy), '+393123456789');
    },
  );
  test(
    'oversized input and national digits are rejected before mobile matching',
    () {
      final cn = phoneCountryForIso('CN');
      final atLimit = '${' ' * 53}13800000000';
      expect(atLimit.length, 64);
      expect(normalizePhoneSignup(atLimit, cn), '+8613800000000');
      expect(canonicalSignupNationalNumber(' $atLimit', cn), isNull);
      expect(normalizePhoneSignup(' $atLimit', cn), isNull);
      expect(canonicalSignupNationalNumber('1' * 16, cn), isNull);
      expect(canonicalSignupNationalNumber('1' * 10000, cn), isNull);
    },
  );
  test('invalid syntax, overlength, and missing mobile data fail closed', () {
    final cn = phoneCountryForIso('CN');
    expect(normalizePhoneSignup('13800000000', cn), '+8613800000000');
    for (final bad in [
      '+86+13800000000',
      '138letters00000000',
      '000',
      '9' * 16,
    ]) {
      expect(normalizePhoneSignup(bad, cn), isNull);
    }
    expect(normalizePhoneSignup('12345', phoneCountryForIso('TA')), isNull);
  });
}
