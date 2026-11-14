import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
      Semantics(
        label: AppL10n.of(context).authPolicyConsentLabel,
        child: ShadCheckbox(
          key: const ValueKey('auth-policy-consent'),
          value: value,
          onChanged: enabled ? (value) => onChanged(value == true) : null,
          enabled: enabled,
          checkboxPadding: const EdgeInsets.all(12),
        ),
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
