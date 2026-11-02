// 平台公约页 —— 承载 platform_rules_content.dart 的正文。
//
// 第六条要求的是"制定**和公开**"。在此之前注册页只有一句纯文本
// "注册即表示你同意……",点不开也没有内容页 —— 那不构成公开。
// 这一页 + 注册页的可点链接 + 设置页入口,三处一起才算把"公开"做到。
import 'package:flutter/material.dart';

import '../design_system.dart';
import '../../l10n/app_localizations.dart';
import 'platform_rules_content.dart';

class PlatformRulesPage extends StatelessWidget {
  const PlatformRulesPage({super.key});

  /// 统一的打开方式,三个入口都走它,避免各处各写一遍 MaterialPageRoute。
  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const PlatformRulesPage()));

  @override
  Widget build(BuildContext context) {
    // 中文版为准:法定义务依据的是中文法条,英文版仅为便利。
    final l = AppL10n.of(context);
    final sections = _platformRulesSections(l);
    return Scaffold(
      backgroundColor: AetherColors.bgCanvas,
      appBar: AppBar(
        backgroundColor: AetherColors.bgCanvas,
        elevation: 0,
        title: Text(l.mePlatformRules, style: AetherTextStyles.h2),
      ),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(
            AetherSpacing.lg,
            AetherSpacing.md,
            AetherSpacing.lg,
            AetherSpacing.xxl,
          ),
          itemCount: sections.length + 1,
          itemBuilder: (context, i) {
            if (i == sections.length) {
              return Padding(
                padding: const EdgeInsets.only(top: AetherSpacing.xl),
                child: Text(
                  l.legalRulesFooter,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: AetherColors.textTertiary,
                  ),
                ),
              );
            }
            final s = sections[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: AetherSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AetherColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AetherSpacing.sm),
                  for (final item in s.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 7, right: 8),
                            child: SizedBox(
                              width: 3,
                              height: 3,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: AetherColors.textTertiary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              item,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.7,
                                color: AetherColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

List<RuleSection> _platformRulesSections(AppL10n l) => [
  RuleSection(l.legalRulesS0Title, [
    l.legalRulesS0P0,
    l.legalRulesS0P1,
    l.legalRulesS0P2,
    l.legalRulesS0P3,
    l.legalRulesS0P4,
    l.legalRulesS0P5,
    l.legalRulesS0P6,
  ]),
  RuleSection(l.legalRulesS1Title, [
    l.legalRulesS1P0,
    l.legalRulesS1P1,
    l.legalRulesS1P2,
    l.legalRulesS1P3,
    l.legalRulesS1P4,
  ]),
  RuleSection(l.legalRulesS2Title, [
    l.legalRulesS2P0,
    l.legalRulesS2P1,
    l.legalRulesS2P2,
    l.legalRulesS2P3,
  ]),
  RuleSection(l.legalRulesS3Title, [
    l.legalRulesS3P0,
    l.legalRulesS3P1,
    l.legalRulesS3P2,
  ]),
  RuleSection(l.legalRulesS4Title, [l.legalRulesS4P0, l.legalRulesS4P1]),
];
