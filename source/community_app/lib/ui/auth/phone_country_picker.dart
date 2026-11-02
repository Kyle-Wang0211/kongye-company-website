import 'package:flutter/material.dart';

import '../../auth/phone_country_catalog.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/phone_country_names.dart';
import 'auth_minimal_widgets.dart';
import '../design_system.dart';

Future<PhoneCountry?> showPhoneCountryPicker(BuildContext context) =>
    Navigator.of(context).push<PhoneCountry>(
      MaterialPageRoute(builder: (_) => const _CountrySearchPage()),
    );

class _CountrySearchPage extends StatefulWidget {
  const _CountrySearchPage();

  @override
  State<_CountrySearchPage> createState() => _CountrySearchPageState();
}

class _CountrySearchPageState extends State<_CountrySearchPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final matches = phoneCountries.where((country) {
      return '${country.iso} ${country.englishName} ${country.chineseName} +${country.callingCode}'
          .toLowerCase()
          .contains(_query.trim().toLowerCase());
    }).toList();
    return Scaffold(
      backgroundColor: AetherColors.bgCanvas,
      appBar: AppBar(
        backgroundColor: AetherColors.bgCanvas,
        foregroundColor: AetherColors.textPrimary,
        elevation: 0,
        actions: const [CompactLanguageToggle()],
        title: TextField(
          key: const ValueKey('phone-country-search'),
          decoration: InputDecoration(
            hintText: l.phoneCountrySearchHint,
            border: InputBorder.none,
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
      ),
      body: SafeArea(
        child: matches.isEmpty
            ? Center(child: Text(l.phoneCountryNoMatches))
            : ListView.builder(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: matches.length,
                itemBuilder: (_, index) {
                  final country = matches[index];
                  return ListTile(
                    key: ValueKey('phone-country-${country.iso}'),
                    leading: Text(
                      country.flag,
                      style: const TextStyle(fontSize: 24),
                    ),
                    title: Text(phoneCountryName(l, country.iso)),
                    trailing: Text('+${country.callingCode}'),
                    onTap: () => Navigator.of(context).pop(country),
                  );
                },
              ),
      ),
    );
  }
}
