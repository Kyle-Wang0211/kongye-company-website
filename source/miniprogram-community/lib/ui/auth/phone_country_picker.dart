import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../auth/phone_country_catalog.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/phone_country_names.dart';
import '../design_system.dart';
import 'auth_minimal_widgets.dart';

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
      ),
      body: SafeArea(
        child: AuthFormBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.phoneCountrySearchHint, softWrap: true),
              ShadInput(
                key: const ValueKey('phone-country-search'),
                onChanged: (value) => setState(() => _query = value),
              ),
              Expanded(
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
                            leading: CountryFlag(country: country, width: 32),
                            title: Text(
                              phoneCountryName(l, country.iso),
                              softWrap: true,
                            ),
                            trailing: Text('+${country.callingCode}'),
                            onTap: () => Navigator.of(context).pop(country),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Country flag, calling code and arrow for the password login field.
class PhoneCountryPrefix extends StatelessWidget {
  final PhoneCountry country;
  final bool enabled;
  final VoidCallback onTap;

  const PhoneCountryPrefix({
    super.key,
    required this.country,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final countryLabel = l.phoneCountryCallingCodeLabel(
      phoneCountryName(l, country.iso),
      country.callingCode,
    );
    return SizedBox(
      width: 100,
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: countryLabel,
              excludeFromSemantics: true,
              child: ShadButton.ghost(
                key: const ValueKey('phone-country-selector'),
                onPressed: enabled ? onTap : null,
                foregroundColor: AetherColors.textPrimary,
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                enabled: (enabled ? onTap : null) != null,
                child: Semantics(
                  label: countryLabel,
                  excludeSemantics: true,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CountryFlag(country: country),
                        const SizedBox(width: 4),
                        Text(
                          '+${country.callingCode}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        const Icon(Icons.arrow_drop_down, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            key: const ValueKey('phone-country-inline-separator'),
            width: 1,
            height: 24,
            color: AetherColors.border,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// A bundled image keeps flag artwork consistent across supported platforms.
class CountryFlag extends StatelessWidget {
  final PhoneCountry country;
  final double width;

  const CountryFlag({super.key, required this.country, this.width = 20});

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/auth/flags/${country.iso.toLowerCase()}.png',
    width: width,
    height: width * 3 / 4,
    fit: BoxFit.contain,
    excludeFromSemantics: true,
  );
}
