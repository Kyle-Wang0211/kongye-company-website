import 'package:flutter/material.dart';

import '../community/social_profile_models.dart';
import '../l10n/app_localizations.dart';
import 'design_system.dart';
import 'community/generated_account_avatar.dart';

class MeProfileHeader extends StatelessWidget {
  const MeProfileHeader({
    super.key,
    required this.profile,
    required this.loading,
    required this.hasError,
    required this.onRetry,
    required this.onFollowingTap,
    this.onSettingsTap,
    this.inboxAction,
    this.fallbackDisplayName = '',
    this.userId = '',
    this.libraryWorksCount,
    this.likesReceived,
  });

  final SocialProfile? profile;
  final bool loading;
  final bool hasError;
  final VoidCallback onRetry;
  final VoidCallback onFollowingTap;
  final VoidCallback? onSettingsTap;
  final Widget? inboxAction;
  final String fallbackDisplayName;
  final String userId;
  final int? libraryWorksCount;
  final int? likesReceived;

  @override
  Widget build(BuildContext context) {
    final value = profile;
    final l = AppL10n.of(context);
    final name = value?.displayName ?? fallbackDisplayName;
    final identity = <String>[
      if (value?.handle != null) '@${value!.handle}',
      if (value?.lastRegion != null) value!.lastRegion!,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(AetherSpacing.lg),
      decoration: BoxDecoration(
        color: AetherColors.bgCanvas,
        borderRadius: BorderRadius.circular(AetherRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GeneratedAccountAvatar(
                userId: userId.isNotEmpty ? userId : value?.id ?? '',
                radius: 32,
              ),
              const SizedBox(width: AetherSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AetherTextStyles.h2),
                    if (identity.isNotEmpty) ...[
                      const SizedBox(height: AetherSpacing.xs),
                      Text(identity, style: AetherTextStyles.bodySm),
                    ],
                  ],
                ),
              ),
              ?inboxAction,
              if (onSettingsTap != null)
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  color: AetherColors.textPrimary,
                  tooltip: l.meSettingsTitle,
                  onPressed: onSettingsTap,
                ),
            ],
          ),
          const SizedBox(height: AetherSpacing.lg),
          Row(
            children: [
              _MeSocialCount(value: libraryWorksCount, label: l.socialWorks),
              _MeSocialCount(
                value: likesReceived,
                label: l.socialLikesReceived,
              ),
              _MeSocialCount(
                value: value?.followersCount,
                label: AppL10n.of(context).socialFollowers,
              ),
              _MeSocialCount(
                value: value?.followingCount,
                label: AppL10n.of(context).socialFollow,
                onTap: onFollowingTap,
              ),
            ],
          ),
          if (loading) ...[
            const SizedBox(height: AetherSpacing.sm),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (hasError) ...[
            const SizedBox(height: AetherSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.meSocialLoadFailed,
                    style: AetherTextStyles.bodySm,
                  ),
                ),
                TextButton(onPressed: onRetry, child: Text(l.communityRetry)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MeSocialCount extends StatelessWidget {
  const _MeSocialCount({required this.value, required this.label, this.onTap});

  final int? value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AetherRadii.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AetherSpacing.sm),
          child: Column(
            children: [
              Text(value?.toString() ?? '—', style: AetherTextStyles.h3),
              const SizedBox(height: AetherSpacing.xs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AetherTextStyles.bodySm,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
