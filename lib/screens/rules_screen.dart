import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/subscription_service.dart';
import '../models/scan_rule.dart';
import '../utils/theme.dart';
import 'paywall_screen.dart';
import 'create_rule_screen.dart';

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
        
        return Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          appBar: AppBar(
            backgroundColor: AppTheme.backgroundColor,
            title: const Text('Scan Rules'),
            actions: [
              if (subscription.isPro)
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _openCreateRule(context),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Free tier banner
              if (!subscription.isPro) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppTheme.textSecondaryColor, size: 20),
                      const SizedBox(width: 12),
                      const Expanded(child: Text('Free tier includes 3 rules. Upgrade for all rules + create custom rules.', style: TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor))),
                      TextButton(onPressed: () => PaywallScreen.show(context, feature: ProFeature.unlimitedRules), child: const Text('Upgrade')),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Custom Rules Section (Pro only)
              if (subscription.isPro) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      const Icon(Icons.auto_awesome, size: 16, color: AppTheme.accentColor),
                      const SizedBox(width: 6),
                      const Text('My Custom Rules', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.accentColor)),
                      if (customRules.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                          child: Text('${customRules.length}', style: const TextStyle(fontSize: 11, color: AppTheme.accentColor, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ]),
                  ],
                ),
                const SizedBox(height: 12),
                
                if (customRules.isEmpty)
                  _buildCreateRuleCard(context)
                else ...[
                  ...customRules.map((rule) => _buildRuleCard(context, provider, rule, isLocked: false, isCustom: true)),
                  const SizedBox(height: 8),
                  _buildCreateRuleCard(context),
                ],
                
                const SizedBox(height: 24),
              ],
              
              // Preset Rules
              if (presetRules.isNotEmpty) ...[
                Row(
                  children: [
                    const Text('Preset Rules', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondaryColor)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppTheme.successColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                      child: Text('${presetRules.length}', style: const TextStyle(fontSize: 11, color: AppTheme.successColor, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...presetRules.map((rule) => _buildRuleCard(context, provider, rule, isLocked: false, isCustom: false)),
              ],
              
              // Locked Rules
              if (lockedRules.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Icon(Icons.lock, size: 14, color: AppTheme.textTertiaryColor),
                    const SizedBox(width: 6),
                    const Text('Pro Rules', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textTertiaryColor)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                      child: Text('${lockedRules.length}', style: const TextStyle(fontSize: 11, color: AppTheme.accentColor, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...lockedRules.map((rule) => _buildRuleCard(context, provider, rule, isLocked: true, isCustom: false)),
              ],
              
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCreateRuleCard(BuildContext context) {
    return GestureDetector(
      onTap: () => _openCreateRule(context),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3), style: BorderStyle.solid),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, color: AppTheme.accentColor.withValues(alpha: 0.7)),
            const SizedBox(width: 8),
            Text('Create Custom Rule', style: TextStyle(color: AppTheme.accentColor.withValues(alpha: 0.7), fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleCard(BuildContext context, AppProvider provider, ScanRule rule, {required bool isLocked, required bool isCustom}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isLocked ? Colors.transparent : (rule.isActive ? AppTheme.accentColor.withValues(alpha: 0.5) : Colors.transparent), width: 1.5),
      ),
      child: Opacity(
        opacity: isLocked ? 0.6 : 1.0,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          onTap: isLocked ? () => PaywallScreen.show(context, feature: ProFeature.unlimitedRules) : null,
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isLocked 
                  ? AppTheme.textTertiaryColor.withValues(alpha: 0.15) 
                  : isCustom 
                      ? AppTheme.accentColor.withValues(alpha: 0.15)
                      : (rule.isActive ? AppTheme.accentColor.withValues(alpha: 0.15) : AppTheme.surfaceColor),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isLocked ? Icons.lock : (isCustom ? Icons.auto_awesome : _getRuleIcon(rule.id)), 
              color: isLocked ? AppTheme.textTertiaryColor : (rule.isActive ? AppTheme.accentColor : AppTheme.textSecondaryColor),
            ),
          ),
          title: Row(
            children: [
              Expanded(child: Text(rule.name, style: const TextStyle(fontWeight: FontWeight.w600))),
              if (isLocked)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                  child: const Text('PRO', style: TextStyle(fontSize: 9, color: AppTheme.accentColor, fontWeight: FontWeight.bold)),
                ),
              if (isCustom && !isLocked) ...[
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  color: AppTheme.textSecondaryColor,
                  onPressed: () => _openEditRule(context, rule),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: AppTheme.errorColor,
                  onPressed: () => _confirmDeleteRule(context, provider, rule),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(rule.description, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: rule.conditions.map((condition) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppTheme.surfaceColor, borderRadius: BorderRadius.circular(6)),
                  child: Text(condition.description, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondaryColor)),
                )).toList(),
              ),
            ],
          ),
          trailing: isLocked
              ? const Icon(Icons.chevron_right, color: AppTheme.textTertiaryColor)
              : isCustom
                  ? Switch(value: rule.isActive, onChanged: (_) => provider.toggleRule(rule.id), activeThumbColor: AppTheme.accentColor)
                  : Switch(value: rule.isActive, onChanged: (_) => provider.toggleRule(rule.id), activeThumbColor: AppTheme.accentColor),
        ),
      ),
    );
  }

  void _openCreateRule(BuildContext context) async {
    final result = await Navigator.push<bool>(
      context, 
      MaterialPageRoute(builder: (_) => const CreateRuleScreen()),
    );
    if (result == true) {
      // Rule was created
    }
  }

  void _openEditRule(BuildContext context, ScanRule rule) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CreateRuleScreen(editRule: rule)),
    );
    if (result == true) {
      // Rule was updated
    }
  }

  Future<void> _confirmDeleteRule(BuildContext context, AppProvider provider, ScanRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: const Text('Delete Rule?'),
        content: Text('Are you sure you want to delete "${rule.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Delete', style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await provider.deleteRule(rule.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rule deleted'), backgroundColor: AppTheme.textSecondaryColor),
        );
      }
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
