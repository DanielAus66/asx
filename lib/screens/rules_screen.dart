import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/subscription_service.dart';
import '../models/scan_rule.dart';
import '../utils/theme.dart';
import 'paywall_screen.dart';
import 'create_rule_screen.dart';

/// My Rules segment — lives inside ScanScreen's PageView.
/// Shows all rules with toggles + inline backtest win-rate badges.
class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppProvider, SubscriptionService>(
      builder: (context, provider, subscription, child) {
        final availableRules = provider.availableRules;
        final lockedRules = provider.lockedRules;
        final customRules = provider.rules.where((r) => provider.isCustomRule(r.id)).toList();
        final presetRules = availableRules.where((r) => !provider.isCustomRule(r.id)).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            // Active rules summary
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: provider.activeRules.isNotEmpty
                        ? AppTheme.successColor.withValues(alpha: 0.12)
                        : AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(child: Text(
                    '${provider.activeRules.length}',
                    style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold,
                      color: provider.activeRules.isNotEmpty ? AppTheme.successColor : AppTheme.textTertiaryColor,
                    ),
                  )),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    '${provider.activeRules.length} rule${provider.activeRules.length != 1 ? 's' : ''} active for scanning',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  if (!subscription.isPro)
                    const Text('Free: 3 max. Upgrade for unlimited.', style: TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor)),
                ])),
                if (!subscription.isPro)
                  TextButton(
                    onPressed: () => PaywallScreen.show(context, feature: ProFeature.unlimitedRules),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
                    child: const Text('Upgrade', style: TextStyle(fontSize: 12)),
                  ),
              ]),
            ),
            const SizedBox(height: 16),

            // Custom Rules (Pro only)
            if (subscription.isPro) ...[
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Row(children: [
                  Icon(Icons.auto_awesome, size: 14, color: AppTheme.accentColor),
                  SizedBox(width: 6),
                  Text('Custom Rules', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.accentColor)),
                ]),
                IconButton(icon: const Icon(Icons.add, size: 18, color: AppTheme.accentColor),
                    onPressed: () => _openCreateRule(context)),
              ]),
              const SizedBox(height: 8),
              if (customRules.isEmpty) _buildCreateRuleCard(context)
              else ...[
                ...customRules.map((rule) => _buildRuleCard(context, provider, rule, isLocked: false, isCustom: true)),
                const SizedBox(height: 4),
                _buildCreateRuleCard(context),
              ],
              const SizedBox(height: 20),
            ],

            // Preset Rules
            if (presetRules.isNotEmpty) ...[
              Row(children: [
                const Text('Preset Rules', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondaryColor)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: AppTheme.successColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                  child: Text('${presetRules.length}', style: const TextStyle(fontSize: 11, color: AppTheme.successColor, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 10),
              ...presetRules.map((rule) => _buildRuleCard(context, provider, rule, isLocked: false, isCustom: false)),
            ],

            // Locked Rules
            if (lockedRules.isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(children: [
                const Icon(Icons.lock, size: 13, color: AppTheme.textTertiaryColor),
                const SizedBox(width: 6),
                const Text('Pro Rules', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textTertiaryColor)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                  child: Text('${lockedRules.length}', style: const TextStyle(fontSize: 11, color: AppTheme.accentColor, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 10),
              ...lockedRules.map((rule) => _buildRuleCard(context, provider, rule, isLocked: true, isCustom: false)),
            ],
          ],
        );
      },
    );
  }

  Widget _buildCreateRuleCard(BuildContext context) {
    return GestureDetector(
      onTap: () => _openCreateRule(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.transparent, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.dividerColor),
        ),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.add_circle_outline, color: AppTheme.textTertiaryColor, size: 18),
          SizedBox(width: 8),
          Text('Create Custom Rule', style: TextStyle(color: AppTheme.textTertiaryColor, fontWeight: FontWeight.w500, fontSize: 13)),
        ]),
      ),
    );
  }

  Widget _buildRuleCard(BuildContext context, AppProvider provider, ScanRule rule, {required bool isLocked, required bool isCustom}) {
    final backtestStats = provider.getRuleBacktestStats(rule.id);
    final hasBacktest = backtestStats != null;
    final winRate = hasBacktest ? (backtestStats['winRate'] as num?)?.toDouble() : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLocked ? Colors.transparent : (rule.isActive ? AppTheme.accentColor.withValues(alpha: 0.3) : Colors.transparent),
        ),
      ),
      child: Opacity(
        opacity: isLocked ? 0.55 : 1.0,
        child: InkWell(
          onTap: isLocked ? () => PaywallScreen.show(context, feature: ProFeature.unlimitedRules) : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Icon
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: isLocked
                      ? AppTheme.textTertiaryColor.withValues(alpha: 0.12)
                      : isCustom
                          ? AppTheme.accentColor.withValues(alpha: 0.12)
                          : (rule.isActive ? AppTheme.accentColor.withValues(alpha: 0.12) : AppTheme.surfaceColor),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isLocked ? Icons.lock : (isCustom ? Icons.auto_awesome : _getRuleIcon(rule.id)),
                  color: isLocked ? AppTheme.textTertiaryColor : (rule.isActive ? AppTheme.accentColor : AppTheme.textSecondaryColor),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Name + actions
                Row(children: [
                  Expanded(child: Text(rule.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                  if (isLocked)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                      child: const Text('PRO', style: TextStyle(fontSize: 9, color: AppTheme.accentColor, fontWeight: FontWeight.bold)),
                    ),
                  if (isCustom && !isLocked) ...[
                    GestureDetector(onTap: () => _openEditRule(context, rule),
                        child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.edit, size: 16, color: AppTheme.textSecondaryColor))),
                    GestureDetector(onTap: () => _confirmDeleteRule(context, provider, rule),
                        child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.delete_outline, size: 16, color: AppTheme.errorColor))),
                  ],
                ]),
                const SizedBox(height: 4),
                Text(rule.description, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),

                // Conditions + win rate
                Row(children: [
                  Expanded(child: Wrap(spacing: 4, runSpacing: 4,
                    children: rule.conditions.take(3).map((c) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(color: AppTheme.surfaceColor, borderRadius: BorderRadius.circular(5)),
                      child: Text(c.description, style: const TextStyle(fontSize: 9, color: AppTheme.textSecondaryColor)),
                    )).toList(),
                  )),
                  if (!isLocked) ...[
                    const SizedBox(width: 8),
                    if (hasBacktest && winRate != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: winRate >= 50
                              ? AppTheme.successColor.withValues(alpha: 0.12)
                              : AppTheme.errorColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('${winRate.toStringAsFixed(0)}%',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                                  color: winRate >= 50 ? AppTheme.successColor : AppTheme.errorColor)),
                          Text('win', style: TextStyle(fontSize: 8,
                              color: winRate >= 50 ? AppTheme.successColor : AppTheme.errorColor)),
                        ]),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(color: AppTheme.surfaceColor, borderRadius: BorderRadius.circular(6)),
                        child: const Text('\u2014', style: TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor)),
                      ),
                  ],
                ]),
              ])),

              // Toggle / lock chevron
              if (!isLocked) ...[
                const SizedBox(width: 8),
                Switch(
                  value: rule.isActive,
                  onChanged: (_) { HapticFeedback.lightImpact(); provider.toggleRule(rule.id); },
                  activeColor: AppTheme.accentColor,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ] else
                const Padding(padding: EdgeInsets.only(left: 8, top: 8),
                    child: Icon(Icons.chevron_right, color: AppTheme.textTertiaryColor, size: 20)),
            ]),
          ),
        ),
      ),
    );
  }

  void _openCreateRule(BuildContext context) async {
    await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const CreateRuleScreen()));
  }

  void _openEditRule(BuildContext context, ScanRule rule) async {
    await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => CreateRuleScreen(editRule: rule)));
  }

  Future<void> _confirmDeleteRule(BuildContext context, AppProvider provider, ScanRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: const Text('Delete Rule?'),
        content: Text('Delete "${rule.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.errorColor))),
        ],
      ),
    );
    if (confirmed == true) {
      await provider.deleteRule(rule.id);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rule deleted')));
    }
  }

  IconData _getRuleIcon(String ruleId) {
    switch (ruleId) {
      case 'oversold_rsi': return Icons.trending_down;
      case 'overbought_rsi': return Icons.trending_up;
      case 'golden_cross': return Icons.auto_graph;
      case 'volume_breakout': return Icons.bar_chart;
      case 'near_52_low': return Icons.vertical_align_bottom;
      case 'big_movers': return Icons.rocket_launch;
      default: return Icons.rule;
    }
  }
}
