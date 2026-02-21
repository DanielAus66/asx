import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/scan_rule.dart';
import '../services/subscription_service.dart';
import '../utils/theme.dart';
import 'paywall_screen.dart';
import 'create_rule_screen.dart';
import 'rule_detail_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CATEGORY DEFINITIONS
// ─────────────────────────────────────────────────────────────────────────────

enum _RuleCategory {
  all('All'),
  momentum('Momentum'),
  breakout('Breakout'),
  reversal('Reversal'),
  volume('Volume'),
  fundamental('Fundamental');

  final String label;
  const _RuleCategory(this.label);
}

_RuleCategory _categoryForRule(ScanRule rule) {
  final types = rule.conditions.map((c) => c.type).toSet();

  const fundamentalTypes = {
    RuleConditionType.announcementWithinDays,
    RuleConditionType.earningsWithinDays,
    RuleConditionType.directorTradeWithinDays,
    RuleConditionType.capitalRaiseWithinDays,
    RuleConditionType.marketSensitiveWithinDays,
    RuleConditionType.shortInterestAbove,
    RuleConditionType.shortInterestBelow,
    RuleConditionType.shortInterestRising,
    RuleConditionType.daysToCoverAbove,
    RuleConditionType.isNotHalted,
    RuleConditionType.resumedFromHalt,
    RuleConditionType.earningsSurprise,
    RuleConditionType.insiderBuying,
  };
  if (types.any(fundamentalTypes.contains)) return _RuleCategory.fundamental;

  const reversalTypes = {
    RuleConditionType.rsiBelow,
    RuleConditionType.oversoldBounce,
    RuleConditionType.priceNear52WeekLow,
  };
  if (types.any(reversalTypes.contains)) return _RuleCategory.reversal;

  const volumeTypes = {
    RuleConditionType.volumeSpike,
    RuleConditionType.stealthAccumulation,
    RuleConditionType.obvDivergence,
    RuleConditionType.stateVolumeExpanding,
    RuleConditionType.eventVolumeBreakout,
  };
  if (types.any(volumeTypes.contains)) return _RuleCategory.volume;

  const momentumTypes = {
    RuleConditionType.momentum6Month,
    RuleConditionType.momentum12Month,
    RuleConditionType.macdCrossover,
    RuleConditionType.macdCrossunder,
    RuleConditionType.priceChangeAbove,
    RuleConditionType.stateMomentumPositive,
    RuleConditionType.eventMomentumCrossover,
    RuleConditionType.stateUptrend,
  };
  if (types.any(momentumTypes.contains)) return _RuleCategory.momentum;

  return _RuleCategory.breakout;
}

// ─────────────────────────────────────────────────────────────────────────────
// RULES SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key});

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  _RuleCategory _selectedCategory = _RuleCategory.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppProvider, SubscriptionService>(
      builder: (context, provider, subscription, _) {
        var visible = provider.availableRules;

        if (_query.isNotEmpty) {
          final q = _query.toLowerCase();
          visible = visible
              .where((r) =>
                  r.name.toLowerCase().contains(q) ||
                  r.description.toLowerCase().contains(q))
              .toList();
        }

        if (_selectedCategory != _RuleCategory.all) {
          visible = visible
              .where((r) => _categoryForRule(r) == _selectedCategory)
              .toList();
        }

        visible.sort((a, b) {
          if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
          return a.name.compareTo(b.name);
        });

        final lockedCount = provider.lockedRules.length;
        final activeCount = provider.activeRules.length;
        final totalRules = provider.availableRules.length;

        return Column(children: [
          _Header(
            activeCount: activeCount,
            isPro: subscription.isPro,
            onCreateTap: subscription.isPro
                ? () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const CreateRuleScreen()))
                : () => PaywallScreen.show(context,
                    feature: ProFeature.unlimitedRules),
          ),

          _CategoryChips(
            selected: _selectedCategory,
            rules: provider.availableRules,
            onSelect: (cat) => setState(() => _selectedCategory = cat),
          ),

          if (totalRules > 6)
            _SearchField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
            ),

          Expanded(
            child: visible.isEmpty && _query.isNotEmpty
                ? _EmptySearch(query: _query)
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 4, bottom: 120),
                    itemCount: visible.length +
                        (lockedCount > 0 &&
                                _selectedCategory == _RuleCategory.all
                            ? 1
                            : 0),
                    itemBuilder: (context, index) {
                      if (lockedCount > 0 &&
                          _selectedCategory == _RuleCategory.all &&
                          index == visible.length) {
                        return _LockedTeaser(
                          count: lockedCount,
                          onTap: () => PaywallScreen.show(context,
                              feature: ProFeature.unlimitedRules),
                        );
                      }

                      final rule = visible[index];
                      return _RuleRow(
                        rule: rule,
                        isCustom: provider.isCustomRule(rule.id),
                        onToggle: () {
                          HapticFeedback.lightImpact();
                          provider.toggleRule(rule.id);
                        },
                        onTap: () => RuleDetailSheet.show(
                          context,
                          rule: rule,
                          isCustom: provider.isCustomRule(rule.id),
                          backtestStats:
                              provider.getRuleBacktestStats(rule.id),
                        ),
                        onDelete: provider.isCustomRule(rule.id)
                            ? () => _confirmDelete(context, provider, rule)
                            : null,
                      );
                    },
                  ),
          ),
        ]);
      },
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, AppProvider provider, ScanRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Delete "${rule.name}"?'),
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
      await provider.deleteRule(rule.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Rule deleted')));
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int activeCount;
  final bool isPro;
  final VoidCallback onCreateTap;

  const _Header({
    required this.activeCount,
    required this.isPro,
    required this.onCreateTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: activeCount > 0
                ? AppTheme.accentColor.withValues(alpha: 0.12)
                : AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: activeCount > 0
                    ? AppTheme.accentColor
                    : AppTheme.textTertiaryColor,
                shape: BoxShape.circle,
                boxShadow: activeCount > 0
                    ? [
                        BoxShadow(
                            color: AppTheme.accentColor
                                .withValues(alpha: 0.5),
                            blurRadius: 4)
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              activeCount > 0 ? '$activeCount active' : 'None active',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: activeCount > 0
                    ? AppTheme.accentColor
                    : AppTheme.textTertiaryColor,
              ),
            ),
          ]),
        ),
        const Spacer(),
        if (isPro)
          GestureDetector(
            onTap: onCreateTap,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.dividerColor),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add, size: 14, color: AppTheme.textSecondaryColor),
                SizedBox(width: 4),
                Text('New rule',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondaryColor,
                        fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CATEGORY CHIPS
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryChips extends StatelessWidget {
  final _RuleCategory selected;
  final List<ScanRule> rules;
  final ValueChanged<_RuleCategory> onSelect;

  const _CategoryChips({
    required this.selected,
    required this.rules,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final counts = <_RuleCategory, int>{};
    counts[_RuleCategory.all] = rules.length;
    for (final rule in rules) {
      final cat = _categoryForRule(rule);
      counts[cat] = (counts[cat] ?? 0) + 1;
    }

    final visibleCategories = _RuleCategory.values
        .where((c) => c == _RuleCategory.all || (counts[c] ?? 0) > 0)
        .toList();

    if (visibleCategories.length <= 2) return const SizedBox.shrink();

    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: visibleCategories.length,
        itemBuilder: (context, i) {
          final cat = visibleCategories[i];
          final count = counts[cat] ?? 0;
          final isSelected = selected == cat;

          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onSelect(cat);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accentColor
                      : AppTheme.cardColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    cat.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.black
                          : AppTheme.textSecondaryColor,
                    ),
                  ),
                  if (cat != _RuleCategory.all && count > 0) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.black.withValues(alpha: 0.15)
                            : AppTheme.dividerColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? Colors.black
                              : AppTheme.textTertiaryColor,
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SEARCH FIELD
// ─────────────────────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search rules…',
          hintStyle: const TextStyle(
              color: AppTheme.textTertiaryColor, fontSize: 14),
          prefixIcon: const Icon(Icons.search,
              size: 18, color: AppTheme.textTertiaryColor),
          suffixIcon: controller.text.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    controller.clear();
                    onChanged('');
                  },
                  child: const Icon(Icons.clear,
                      size: 16, color: AppTheme.textTertiaryColor),
                )
              : null,
          filled: true,
          fillColor: AppTheme.cardColor,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RULE ROW
// ─────────────────────────────────────────────────────────────────────────────

class _RuleRow extends StatelessWidget {
  final ScanRule rule;
  final bool isCustom;
  final VoidCallback onToggle;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _RuleRow({
    required this.rule,
    required this.isCustom,
    required this.onToggle,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = rule.isActive;

    Widget row = AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isActive ? 1.0 : 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
        child: SizedBox(
          height: 56,
          child: Row(children: [
            GestureDetector(
              onTap: onToggle,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          isActive ? AppTheme.accentColor : Colors.transparent,
                      border: Border.all(
                        color: isActive
                            ? AppTheme.accentColor
                            : AppTheme.textTertiaryColor
                                .withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                  color: AppTheme.accentColor
                                      .withValues(alpha: 0.35),
                                  blurRadius: 8)
                            ]
                          : null,
                    ),
                    child: isActive
                        ? const Icon(Icons.check,
                            size: 13, color: Colors.black)
                        : null,
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: Row(children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rule.name,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _conditionSummary(),
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textTertiaryColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right,
                      size: 18, color: AppTheme.textTertiaryColor),
                  const SizedBox(width: 4),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );

    if (onDelete != null) {
      return Dismissible(
        key: Key('rule_${rule.id}'),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) async {
          onDelete!();
          return false;
        },
        background: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
          decoration: BoxDecoration(
            color: AppTheme.errorColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.delete_outline,
                color: AppTheme.errorColor, size: 18),
            SizedBox(width: 6),
            Text('Delete',
                style: TextStyle(
                    color: AppTheme.errorColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
        child: row,
      );
    }
    return row;
  }

  String _conditionSummary() {
    if (rule.conditions.isEmpty) return 'No conditions';
    final parts = rule.conditions.map((c) => c.shortDescription).toList();
    if (parts.length <= 3) return parts.join(' · ');
    return '${parts.take(3).join(' · ')} +${parts.length - 3}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY SEARCH STATE
// ─────────────────────────────────────────────────────────────────────────────

class _EmptySearch extends StatelessWidget {
  final String query;
  const _EmptySearch({required this.query});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Icon(Icons.search_off,
              size: 48,
              color: AppTheme.textTertiaryColor.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text('No rules match "$query"',
              style: const TextStyle(
                  fontSize: 15, color: AppTheme.textSecondaryColor)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOCKED TEASER
// ─────────────────────────────────────────────────────────────────────────────

class _LockedTeaser extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _LockedTeaser({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: AppTheme.accentColor.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.lock_open_outlined,
                size: 18, color: AppTheme.accentColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$count more rules available',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  const Text(
                      'Director activity, short squeeze, VCP & more',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondaryColor)),
                ]),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.accentColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('Unlock',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.black,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}
