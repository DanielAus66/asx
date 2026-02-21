import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/scan_rule.dart';
import '../providers/app_provider.dart';
import '../utils/theme.dart';
import 'create_rule_screen.dart';
import 'backtest_screen.dart';

/// The single detail surface for a rule.
///
/// Everything that was stuffed into the list card now lives here:
/// — Full description
/// — All conditions (properly readable)
/// — Backtest result (if run) or CTA to run it
/// — Edit / Delete for custom rules
/// — The toggle (large, prominent, not a tiny switch)
///
/// Opened by tapping the right side of any rule row.
/// The circle toggle on the list row is faster — this is for inspection.
class RuleDetailSheet extends StatefulWidget {
  final ScanRule rule;
  final bool isCustom;
  final Map<String, dynamic>? backtestStats;

  const RuleDetailSheet({
    super.key,
    required this.rule,
    required this.isCustom,
    this.backtestStats,
  });

  static Future<void> show(
    BuildContext context, {
    required ScanRule rule,
    required bool isCustom,
    Map<String, dynamic>? backtestStats,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RuleDetailSheet(
        rule: rule,
        isCustom: isCustom,
        backtestStats: backtestStats,
      ),
    );
  }

  @override
  State<RuleDetailSheet> createState() => _RuleDetailSheetState();
}

class _RuleDetailSheetState extends State<RuleDetailSheet> {
  late ScanRule _rule;

  @override
  void initState() {
    super.initState();
    _rule = widget.rule;
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.backtestStats;
    final hasBacktest = stats != null;
    final winRate = (stats?['winRate'] as num?)?.toDouble();

    return Container(
      // 85% of screen height — enough room without feeling full-screen
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: AppTheme.dividerColor,
                borderRadius: BorderRadius.circular(2)),
          ),

          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header: name + big toggle ──────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.isCustom)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 4),
                                child: Text('CUSTOM RULE',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.accentColor,
                                        letterSpacing: 0.6)),
                              ),
                            Text(
                              _rule.name,
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.3),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Big toggle button — the most important action
                      Consumer<AppProvider>(
                        builder: (context, provider, _) {
                          // Read fresh state from provider
                          final liveRule = provider.rules
                              .firstWhere((r) => r.id == _rule.id,
                                  orElse: () => _rule);
                          final isActive = liveRule.isActive;
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              provider.toggleRule(_rule.id);
                              setState(() {
                                _rule = liveRule.copyWith(
                                    isActive: !isActive);
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AppTheme.accentColor
                                    : AppTheme.cardColor,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isActive
                                      ? AppTheme.accentColor
                                      : AppTheme.dividerColor,
                                ),
                              ),
                              child: Text(
                                isActive ? 'Active' : 'Inactive',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isActive
                                      ? Colors.black
                                      : AppTheme.textSecondaryColor,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ── Description ────────────────────────────────────
                  Text(
                    _rule.description.isEmpty
                        ? 'No description.'
                        : _rule.description,
                    style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondaryColor,
                        height: 1.6),
                  ),

                  const SizedBox(height: 24),

                  // ── Conditions ─────────────────────────────────────
                  const Text('Conditions',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textTertiaryColor,
                          letterSpacing: 0.6)),
                  const SizedBox(height: 10),

                  if (_rule.conditions.isEmpty)
                    const Text('No conditions defined.',
                        style: TextStyle(color: AppTheme.textTertiaryColor))
                  else
                    ..._rule.conditions.asMap().entries.map((entry) {
                      final i = entry.key;
                      final c = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Condition number
                            Container(
                              width: 22, height: 22,
                              decoration: const BoxDecoration(
                                color: AppTheme.cardColor,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text('${i + 1}',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: AppTheme.textTertiaryColor,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  c.description,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.textPrimaryColor,
                                      height: 1.4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                  const SizedBox(height: 24),
                  const Divider(color: AppTheme.dividerColor),
                  const SizedBox(height: 20),

                  // ── Backtest stats OR CTA ──────────────────────────
                  if (hasBacktest && winRate != null)
                    _BacktestResultCard(stats: stats)
                  else
                    _BacktestCTA(
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => BacktestScreen(
                                    autoRules: [_rule])));
                      },
                    ),

                  // ── Custom rule actions ────────────────────────────
                  if (widget.isCustom) ...[
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(
                        child: _ActionButton(
                          label: 'Edit Rule',
                          icon: Icons.edit_outlined,
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => CreateRuleScreen(
                                        editRule: _rule)));
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActionButton(
                          label: 'Delete',
                          icon: Icons.delete_outline,
                          isDestructive: true,
                          onTap: () => _confirmDelete(context),
                        ),
                      ),
                    ]),
                  ],

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Delete "${_rule.name}"?'),
        content: const Text('This cannot be undone.',
            style: TextStyle(color: AppTheme.textSecondaryColor)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(color: AppTheme.errorColor))),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final provider = Provider.of<AppProvider>(context, listen: false);
      await provider.deleteRule(_rule.id);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BACKTEST RESULT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _BacktestResultCard extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _BacktestResultCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final winRate = (stats['winRate'] as num?)?.toDouble() ?? 0;
    final avgReturn = (stats['avgReturn'] as num?)?.toDouble();
    final maxDrawdown = (stats['maxDrawdown'] as num?)?.toDouble();
    final sharpe = (stats['sharpe'] as num?)?.toDouble();
    final avgHold = (stats['avgHoldDays'] as num?)?.toInt();
    final good = winRate >= 50;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Backtest Results',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textTertiaryColor,
                letterSpacing: 0.6)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            // Primary stat — win rate, large
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    '${winRate.toStringAsFixed(1)}%',
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: good
                            ? AppTheme.successColor
                            : AppTheme.errorColor),
                  ),
                  const Text('Win rate',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondaryColor)),
                ]),
                Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (avgReturn != null)
                        Text(
                          '${avgReturn >= 0 ? '+' : ''}${avgReturn.toStringAsFixed(1)}%',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      if (avgReturn != null)
                        const Text('avg return',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondaryColor)),
                    ]),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(color: AppTheme.dividerColor, height: 1),
            const SizedBox(height: 14),

            // Secondary stats row
            Row(children: [
              if (maxDrawdown != null)
                _Stat('Max DD',
                    '${maxDrawdown.toStringAsFixed(1)}%'),
              if (sharpe != null)
                _Stat('Sharpe', sharpe.toStringAsFixed(2)),
              if (avgHold != null) _Stat('Avg hold', '${avgHold}d'),
            ]),

            const SizedBox(height: 10),
            const Text(
              'General advice only. Past performance is not indicative of future results.',
              style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.textTertiaryColor,
                  height: 1.4),
            ),
          ]),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(children: [
        Text(value,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: AppTheme.textTertiaryColor)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BACKTEST CTA (not yet run)
// ─────────────────────────────────────────────────────────────────────────────

class _BacktestCTA extends StatelessWidget {
  final VoidCallback onTap;
  const _BacktestCTA({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.dividerColor),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.science_outlined,
                size: 18, color: AppTheme.accentColor),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Backtest this rule',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                SizedBox(height: 2),
                Text('See historical win rate on ASX',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondaryColor)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right,
              size: 18, color: AppTheme.textTertiaryColor),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTION BUTTON (edit / delete)
// ─────────────────────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive
        ? AppTheme.errorColor
        : AppTheme.textSecondaryColor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: isDestructive
              ? AppTheme.errorColor.withValues(alpha: 0.08)
              : AppTheme.cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDestructive
                ? AppTheme.errorColor.withValues(alpha: 0.3)
                : AppTheme.dividerColor,
          ),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: color)),
        ]),
      ),
    );
  }
}
