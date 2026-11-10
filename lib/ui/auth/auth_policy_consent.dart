import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../legal/legal_doc_links_row.dart';

/// Consent belongs to the current explicit authentication form.
class AuthPolicyConsent extends StatelessWidget {
  const AuthPolicyConsent({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Checkbox(
        key: const ValueKey('auth-policy-consent'),
        value: value,
        semanticLabel: AppL10n.of(context).authPolicyConsentLabel,
        onChanged: enabled ? (value) => onChanged(value == true) : null,
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: LegalDocLinksRow(
            prefix: AppL10n.of(context).authPolicyConsentLabel,
          ),
        ),
      ),
    ],
  );
}
