import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import '../providers/app_provider.dart';
import '../services/subscription_service.dart';
import '../models/scan_rule.dart';
import '../models/stock.dart';
import '../utils/theme.dart';
import '../widgets/scan_filters_sheet.dart';
import 'stock_detail_sheet.dart';
import 'paywall_screen.dart';

class BacktestScreen extends StatefulWidget {
  const BacktestScreen({super.key});
  @override
  State<BacktestScreen> createState() => _BacktestScreenState();
}

class _BacktestScreenState extends State<BacktestScreen> {
  final Set<String> _selectedRuleIds = {};
  bool _combineMode = false;
  bool _useAndLogic = true;
  
  bool _hasResults = false;
  List<Map<String, dynamic>> _signals = [];
  Map<String, dynamic> _stats = {};
  int _uniqueStocks = 0;
  int _totalSignals = 0;
  String _testedRuleName = '';
  int _testedPeriod = 0;
  
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppProvider, SubscriptionService>(
      builder: (context, provider, subscription, child) {
        if (_isLoading) return _buildLoadingScreen(context, provider);
        if (_hasResults) return _buildResultsScreen(context, provider);
        return _buildSelectionScreen(context, provider, subscription);
      },
    );
  }

  Widget _buildLoadingScreen(BuildContext context, AppProvider provider) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundColor,
        title: const Text('Running Backtest'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            provider.stopScan();
            setState(() => _isLoading = false);
          },
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 80, height: 80, child: CircularProgressIndicator(strokeWidth: 6, color: AppTheme.accentColor)),
              const SizedBox(height: 32),
              Text(_testedRuleName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(provider.scanStatus, style: const TextStyle(color: AppTheme.textSecondaryColor)),
              const SizedBox(height: 24),
              if (_signals.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt, color: AppTheme.accentColor, size: 20),
                      const SizedBox(width: 8),
                      Text('${_signals.length} signals found', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              const SizedBox(height: 32),
              TextButton.icon(
                onPressed: () {
                  provider.stopScan();
                  setState(() => _isLoading = false);
                },
                icon: const Icon(Icons.stop, color: AppTheme.errorColor),
                label: const Text('Stop', style: TextStyle(color: AppTheme.errorColor)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionScreen(BuildContext context, AppProvider provider, SubscriptionService subscription) {
    final availableRules = provider.availableRules;
    final remaining = subscription.remainingBacktests;
    final canBacktest = provider.canRunBacktest();
    
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Filter action row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Stack(
                      children: [
                        const Icon(Icons.tune, size: 20),
                        if (provider.scanFilters.enabled)
                          Positioned(right: 0, top: 0, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.accentColor, shape: BoxShape.circle))),
                      ],
                    ),
                    tooltip: 'Stock Filters',
                    onPressed: () async {
                      final newFilters = await ScanFiltersSheet.show(context, provider.scanFilters);
                      if (newFilters != null) provider.updateScanFilters(newFilters);
                    },
                  ),
                ],
              ),
            ),
          if (!subscription.isPro)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: remaining <= 1 ? AppTheme.errorColor.withValues(alpha: 0.1) : AppTheme.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: remaining <= 1 ? Border.all(color: AppTheme.errorColor.withValues(alpha: 0.3)) : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: remaining <= 1 ? AppTheme.errorColor.withValues(alpha: 0.15) : AppTheme.backgroundColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(child: Text('$remaining', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: remaining <= 1 ? AppTheme.errorColor : AppTheme.textPrimaryColor))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Backtest${remaining != 1 ? 's' : ''} remaining today', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        const Text('Resets at midnight', style: TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor)),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => PaywallScreen.show(context, feature: ProFeature.unlimitedBacktests),
                    style: TextButton.styleFrom(backgroundColor: AppTheme.accentColor.withValues(alpha: 0.15), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                    child: const Text('Unlimited', style: TextStyle(fontSize: 12, color: AppTheme.accentColor, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          if (provider.scanFilters.enabled)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  const Icon(Icons.filter_list, size: 16, color: AppTheme.accentColor),
                  const SizedBox(width: 8),
                  Expanded(child: Text(provider.scanFilters.toString(), style: const TextStyle(fontSize: 11, color: AppTheme.accentColor))),
                  GestureDetector(
                    onTap: () async {
                      final newFilters = await ScanFiltersSheet.show(context, provider.scanFilters);
                      if (newFilters != null) provider.updateScanFilters(newFilters);
                    },
                    child: const Text('Edit', style: TextStyle(fontSize: 11, color: AppTheme.accentColor, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(_combineMode ? 'Select Rules to Combine' : 'Select a Rule to Test', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(_combineMode ? 'Choose 2+ rules to test together' : 'Tap a rule to configure and run backtest', style: const TextStyle(color: AppTheme.textSecondaryColor, fontSize: 14)),
                const SizedBox(height: 20),
                ...availableRules.map((rule) => _buildRuleCard(context, provider, rule, canBacktest)),
                const SizedBox(height: 16),
                if (!_combineMode)
                  _buildCombineRulesButton()
                else ...[
                  _buildLogicToggle(),
                  const SizedBox(height: 16),
                  if (_selectedRuleIds.length >= 2) _buildRunCombinedButton(context, provider, canBacktest),
                  const SizedBox(height: 8),
                  Center(child: TextButton(onPressed: () => setState(() { _combineMode = false; _selectedRuleIds.clear(); }), child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondaryColor)))),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleCard(BuildContext context, AppProvider provider, ScanRule rule, bool canBacktest) {
    final isSelected = _selectedRuleIds.contains(rule.id);
    final isCombo = rule.conditions.length > 2;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isSelected ? AppTheme.accentColor : Colors.transparent, width: 2),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (_combineMode) {
              setState(() {
                if (isSelected) {
                  _selectedRuleIds.remove(rule.id);
                } else {
                  _selectedRuleIds.add(rule.id);
                }
              });
            } else {
              _showPeriodSelector(context, provider, rule, canBacktest);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(color: isSelected ? AppTheme.accentColor.withValues(alpha: 0.2) : AppTheme.backgroundColor, borderRadius: BorderRadius.circular(12)),
                  child: Icon(_getRuleIcon(rule), color: isSelected ? AppTheme.accentColor : AppTheme.textSecondaryColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(rule.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
                          if (isCombo)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                              child: const Text('COMBO', style: TextStyle(fontSize: 9, color: Colors.purple, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(rule.description, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor), maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6, runSpacing: 4,
                        children: rule.conditions.take(3).map((c) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppTheme.backgroundColor, borderRadius: BorderRadius.circular(4)),
                          child: Text(c.shortDescription, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondaryColor)),
                        )).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (_combineMode)
                  Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.accentColor : Colors.transparent,
                      border: Border.all(color: isSelected ? AppTheme.accentColor : AppTheme.textTertiaryColor),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.black) : null,
                  )
                else
                  const Icon(Icons.chevron_right, color: AppTheme.textTertiaryColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCombineRulesButton() {
    return GestureDetector(
      onTap: () => setState(() => _combineMode = true),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.textTertiaryColor.withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.merge_type, color: AppTheme.textSecondaryColor),
            SizedBox(width: 8),
            Text('Combine Multiple Rules', style: TextStyle(color: AppTheme.textSecondaryColor, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildLogicToggle() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Match Logic', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _useAndLogic = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(color: _useAndLogic ? AppTheme.accentColor : AppTheme.backgroundColor, borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      children: [
                        Text('AND', style: TextStyle(fontWeight: FontWeight.bold, color: _useAndLogic ? Colors.black : AppTheme.textSecondaryColor)),
                        Text('All must match', style: TextStyle(fontSize: 10, color: _useAndLogic ? Colors.black54 : AppTheme.textTertiaryColor)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _useAndLogic = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(color: !_useAndLogic ? AppTheme.accentColor : AppTheme.backgroundColor, borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      children: [
                        Text('OR', style: TextStyle(fontWeight: FontWeight.bold, color: !_useAndLogic ? Colors.black : AppTheme.textSecondaryColor)),
                        Text('Any can match', style: TextStyle(fontSize: 10, color: !_useAndLogic ? Colors.black54 : AppTheme.textTertiaryColor)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRunCombinedButton(BuildContext context, AppProvider provider, bool canBacktest) {
    return GestureDetector(
      onTap: canBacktest ? () => _showPeriodSelectorCombined(context, provider) : () => PaywallScreen.show(context, feature: ProFeature.unlimitedBacktests),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: AppTheme.accentColor, borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_arrow, color: Colors.black),
            const SizedBox(width: 8),
            Text('Test ${_selectedRuleIds.length} Rules Combined', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
            if (!canBacktest) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.lock, size: 16, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  void _showPeriodSelector(BuildContext context, AppProvider provider, ScanRule rule, bool canBacktest) {
    int selectedPeriod = 30;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          decoration: const BoxDecoration(color: AppTheme.surfaceColor, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.textTertiaryColor, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Container(width: 44, height: 44, decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)), child: Icon(_getRuleIcon(rule), color: AppTheme.accentColor)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(rule.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      Text('${rule.conditions.length} conditions', style: const TextStyle(color: AppTheme.textSecondaryColor, fontSize: 13)),
                    ])),
                  ],
                ),
                const SizedBox(height: 28),
                const Align(alignment: Alignment.centerLeft, child: Text('Test Period', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                const SizedBox(height: 12),
                Row(children: [
                  _buildPeriodChip('1W', 7, selectedPeriod, (p) => setSheetState(() => selectedPeriod = p)),
                  const SizedBox(width: 8),
                  _buildPeriodChip('2W', 14, selectedPeriod, (p) => setSheetState(() => selectedPeriod = p)),
                  const SizedBox(width: 8),
                  _buildPeriodChip('1M', 30, selectedPeriod, (p) => setSheetState(() => selectedPeriod = p)),
                  const SizedBox(width: 8),
                  _buildPeriodChip('3M', 90, selectedPeriod, (p) => setSheetState(() => selectedPeriod = p)),
                  const SizedBox(width: 8),
                  _buildPeriodChip('6M', 126, selectedPeriod, (p) => setSheetState(() => selectedPeriod = p)),
                ]),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppTheme.backgroundColor, borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    const Icon(Icons.info_outline, size: 16, color: AppTheme.textTertiaryColor),
                    const SizedBox(width: 8),
                    Text('Tests ~2,200 ASX stocks • Est. ${selectedPeriod <= 14 ? '2-3' : selectedPeriod <= 30 ? '3-5' : '5-8'} min', style: const TextStyle(fontSize: 12, color: AppTheme.textTertiaryColor)),
                  ]),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity, height: 54,
                  child: ElevatedButton(
                    onPressed: canBacktest ? () { Navigator.pop(ctx); _runBacktest(provider, [rule], selectedPeriod); } : () { Navigator.pop(ctx); PaywallScreen.show(context, feature: ProFeature.unlimitedBacktests); },
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.play_arrow, color: Colors.black),
                      const SizedBox(width: 8),
                      const Text('Run Backtest', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                      if (!canBacktest) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.lock, size: 16, color: Colors.black54)),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPeriodSelectorCombined(BuildContext context, AppProvider provider) {
    int selectedPeriod = 30;
    final rules = provider.availableRules.where((r) => _selectedRuleIds.contains(r.id)).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          decoration: const BoxDecoration(color: AppTheme.surfaceColor, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.textTertiaryColor, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 24),
                Row(children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.merge_type, color: Colors.purple)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${rules.length} Rules Combined', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    Text(_useAndLogic ? 'All must match (AND)' : 'Any can match (OR)', style: const TextStyle(color: AppTheme.textSecondaryColor, fontSize: 13)),
                  ])),
                ]),
                const SizedBox(height: 16),
                Wrap(spacing: 6, runSpacing: 6, children: rules.map((r) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text(r.name, style: const TextStyle(fontSize: 12, color: AppTheme.accentColor)),
                )).toList()),
                const SizedBox(height: 24),
                const Align(alignment: Alignment.centerLeft, child: Text('Test Period', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                const SizedBox(height: 12),
                Row(children: [
                  _buildPeriodChip('1W', 7, selectedPeriod, (p) => setSheetState(() => selectedPeriod = p)),
                  const SizedBox(width: 8),
                  _buildPeriodChip('2W', 14, selectedPeriod, (p) => setSheetState(() => selectedPeriod = p)),
                  const SizedBox(width: 8),
                  _buildPeriodChip('1M', 30, selectedPeriod, (p) => setSheetState(() => selectedPeriod = p)),
                  const SizedBox(width: 8),
                  _buildPeriodChip('3M', 90, selectedPeriod, (p) => setSheetState(() => selectedPeriod = p)),
                  const SizedBox(width: 8),
                  _buildPeriodChip('6M', 126, selectedPeriod, (p) => setSheetState(() => selectedPeriod = p)),
                ]),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity, height: 54,
                  child: ElevatedButton(
                    onPressed: () { Navigator.pop(ctx); _runBacktest(provider, rules, selectedPeriod); },
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.play_arrow, color: Colors.black), SizedBox(width: 8), Text('Run Combined Backtest', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16))]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodChip(String label, int days, int selected, Function(int) onSelect) {
    final isSelected = selected == days;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelect(days),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: isSelected ? AppTheme.accentColor : AppTheme.backgroundColor, borderRadius: BorderRadius.circular(8)),
          child: Center(child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: isSelected ? Colors.black : AppTheme.textSecondaryColor))),
        ),
      ),
    );
  }

  Future<void> _runBacktest(AppProvider provider, List<ScanRule> rules, int periodDays) async {
    setState(() {
      _isLoading = true;
      _signals = [];
      _stats = {};
      _testedRuleName = rules.length == 1 ? rules.first.name : '${rules.length} Rules Combined';
      _testedPeriod = periodDays;
    });

    try {
      Map<String, dynamic> result;
      if (rules.length == 1) {
        result = await provider.backtestRule(rules.first, periodDays: periodDays, onResultFound: (signal) {
          if (mounted) setState(() { _signals.add(signal); _totalSignals = _signals.length; });
        });
      } else {
        result = await provider.backtestRules(rules, periodDays: periodDays, useAndLogic: _useAndLogic, onResultFound: (signal) {
          if (mounted) setState(() { _signals.add(signal); _totalSignals = _signals.length; });
        });
      }

      if (mounted) {
        final signalsList = result['signals'];
        final statsList = result['stats'];
        setState(() {
          _signals = signalsList is List<Map<String, dynamic>> ? signalsList : (signalsList as List?)?.map((s) => Map<String, dynamic>.from(s as Map)).toList() ?? [];
          _stats = statsList is Map<String, dynamic> ? statsList : (statsList != null ? Map<String, dynamic>.from(statsList as Map) : {});
          _uniqueStocks = (result['uniqueStocks'] as int?) ?? 0;
          _totalSignals = (result['totalSignals'] as int?) ?? _signals.length;
          _isLoading = false;
          _hasResults = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorColor));
      }
    }
  }

  Widget _buildResultsScreen(BuildContext context, AppProvider provider) {
    double avgReturn = 0, winRate = 0, sharpe = 0, maxLoss = 0, maxGain = 0;
    Map<String, dynamic> holdingPeriods = {};
    if (_stats.containsKey('holdingPeriods') && _stats['holdingPeriods'] != null) {
      final hp = _stats['holdingPeriods'];
      holdingPeriods = hp is Map<String, dynamic> ? hp : (hp is Map ? Map<String, dynamic>.from(hp) : {});
    }
    if (holdingPeriods.containsKey('toToday')) {
      final todayStats = holdingPeriods['toToday'];
      if (todayStats is Map) {
        avgReturn = (todayStats['avgReturn'] as num?)?.toDouble() ?? 0;
        winRate = (todayStats['winRate'] as num?)?.toDouble() ?? 0;
        sharpe = (todayStats['sharpe'] as num?)?.toDouble() ?? 0;
      }
    }
    for (final signal in _signals) {
      final change = (signal['changePercent'] as num?)?.toDouble() ?? 0;
      if (change > maxGain) maxGain = change;
      if (change < maxLoss) maxLoss = change;
    }
    final isPositive = avgReturn >= 0;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundColor,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() { _hasResults = false; _signals = []; _stats = {}; _combineMode = false; _selectedRuleIds.clear(); })),
        title: const Text('Results'),
        actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Run Again', onPressed: () => setState(() => _hasResults = false))],
      ),
      body: _signals.isEmpty ? _buildEmptyResults() : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_testedRuleName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('${_getPeriodLabel(_testedPeriod)} • $_totalSignals signals • $_uniqueStocks stocks', style: const TextStyle(color: AppTheme.textSecondaryColor, fontSize: 14)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: isPositive ? [AppTheme.successColor.withValues(alpha: 0.15), AppTheme.successColor.withValues(alpha: 0.05)] : [AppTheme.errorColor.withValues(alpha: 0.15), AppTheme.errorColor.withValues(alpha: 0.05)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: (isPositive ? AppTheme.successColor : AppTheme.errorColor).withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                Icon(isPositive ? Icons.trending_up : Icons.trending_down, size: 32, color: isPositive ? AppTheme.successColor : AppTheme.errorColor),
                const SizedBox(height: 8),
                Text('${isPositive ? '+' : ''}${avgReturn.toStringAsFixed(1)}%', style: TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: isPositive ? AppTheme.successColor : AppTheme.errorColor)),
                const Text('avg return to today', style: TextStyle(color: AppTheme.textSecondaryColor, fontSize: 14)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildMiniKPI('🏆', '${winRate.toStringAsFixed(0)}%', 'win rate'),
                    Container(width: 1, height: 30, color: AppTheme.textTertiaryColor.withValues(alpha: 0.3)),
                    _buildMiniKPI('📊', sharpe.toStringAsFixed(2), 'sharpe'),
                    Container(width: 1, height: 30, color: AppTheme.textTertiaryColor.withValues(alpha: 0.3)),
                    _buildMiniKPI('📈', '+${maxGain.toStringAsFixed(0)}%', 'best'),
                    Container(width: 1, height: 30, color: AppTheme.textTertiaryColor.withValues(alpha: 0.3)),
                    _buildMiniKPI('📉', '${maxLoss.toStringAsFixed(0)}%', 'worst'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (holdingPeriods.isNotEmpty) ...[
            const Text('Returns by Holding Period', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: holdingPeriods.entries.map((entry) {
                  final stats = entry.value is Map ? Map<String, dynamic>.from(entry.value as Map) : <String, dynamic>{};
                  final ret = (stats['avgReturn'] as num?)?.toDouble() ?? 0;
                  final win = (stats['winRate'] as num?)?.toDouble() ?? 0;
                  final isUp = ret >= 0;
                  final periodLabel = entry.key == 'toToday' ? 'To Today' : entry.key.toUpperCase();
                  final barWidth = (ret.abs() / 20).clamp(0.0, 1.0);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        SizedBox(width: 60, child: Text(periodLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                        Expanded(
                          child: Stack(
                            children: [
                              Container(height: 24, decoration: BoxDecoration(color: AppTheme.backgroundColor, borderRadius: BorderRadius.circular(4))),
                              FractionallySizedBox(widthFactor: barWidth, child: Container(height: 24, decoration: BoxDecoration(color: (isUp ? AppTheme.successColor : AppTheme.errorColor).withValues(alpha: 0.3), borderRadius: BorderRadius.circular(4)))),
                              Positioned.fill(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('${isUp ? '+' : ''}${ret.toStringAsFixed(1)}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isUp ? AppTheme.successColor : AppTheme.errorColor)),
                                      Text('${win.toStringAsFixed(0)}% win', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 20),
          // Equity curve
          if (_signals.length >= 2) ...[
            const Text('Equity Curve', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Cumulative return if each signal invested equally', style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor)),
            const SizedBox(height: 12),
            Container(
              height: 200,
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
              decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(16)),
              child: CustomPaint(
                painter: EquityCurvePainter(_buildEquityCurveData()),
                size: Size.infinite,
              ),
            ),
            const SizedBox(height: 20),
          ],
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Top Performers', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            Text('${_signals.length} total', style: const TextStyle(color: AppTheme.textTertiaryColor, fontSize: 12)),
          ]),
          const SizedBox(height: 12),
          ..._signals.take(20).map((signal) => _buildSignalCard(signal, provider)),
          if (_signals.length > 20) Padding(padding: const EdgeInsets.only(top: 12), child: Center(child: Text('Showing top 20 of ${_signals.length} signals', style: const TextStyle(color: AppTheme.textTertiaryColor, fontSize: 12)))),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildEmptyResults() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: AppTheme.textTertiaryColor),
            const SizedBox(height: 16),
            const Text('No Signals Found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('No stocks matched the rule criteria during this period. Try a longer timeframe or different rule.', style: TextStyle(color: AppTheme.textSecondaryColor), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: () => setState(() => _hasResults = false), child: const Text('Try Different Settings')),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniKPI(String emoji, String value, String label) {
    return Column(children: [
      Text(emoji, style: const TextStyle(fontSize: 16)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textTertiaryColor)),
    ]);
  }

  Widget _buildSignalCard(Map<String, dynamic> signal, AppProvider provider) {
    final symbol = (signal['symbol'] as String?) ?? '';
    final name = (signal['name'] as String?) ?? symbol.replaceAll('.AX', '');
    final changePercent = (signal['changePercent'] as num?)?.toDouble() ?? 0;
    final isUp = changePercent >= 0;
    final color = isUp ? AppTheme.successColor : AppTheme.errorColor;
    final daysAgo = (signal['daysAgo'] as int?) ?? 0;
    final priceAtSignal = (signal['priceAtSignal'] as num?)?.toDouble() ?? 0;
    final currentPrice = (signal['currentPrice'] as num?)?.toDouble() ?? 0;
    final inWatchlist = signal['inWatchlist'] == true;
    final matchedRules = (signal['matchedRules'] as List?)?.cast<String>() ?? [];
    final signalDateStr = signal['signalDate'] as String?;
    String dateLabel = '${daysAgo}d ago';
    if (signalDateStr != null) { try { dateLabel = DateFormat('MMM d').format(DateTime.parse(signalDateStr)); } catch (_) {} }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            provider.stockCache[symbol] = provider.stockCache[symbol] ?? Stock(symbol: symbol, name: name, currentPrice: currentPrice, previousClose: priceAtSignal, change: currentPrice - priceAtSignal, changePercent: changePercent, volume: 0, marketCap: 0, lastUpdate: DateTime.now());
            showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => StockDetailSheet(symbol: symbol));
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)), child: Icon(isUp ? Icons.trending_up : Icons.trending_down, color: color, size: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(symbol.replaceAll('.AX', ''), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(width: 6),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: AppTheme.backgroundColor, borderRadius: BorderRadius.circular(4)), child: Text(dateLabel, style: const TextStyle(fontSize: 10, color: AppTheme.textTertiaryColor))),
                        if (inWatchlist) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.bookmark, size: 12, color: Colors.amber)),
                      ]),
                      const SizedBox(height: 2),
                      Text('\$${priceAtSignal.toStringAsFixed(2)} → \$${currentPrice.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
                      if (matchedRules.length > 1) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${matchedRules.length} rules matched', style: const TextStyle(fontSize: 10, color: AppTheme.accentColor))),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                  child: Text('${isUp ? '+' : ''}${changePercent.toStringAsFixed(1)}%', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getRuleIcon(ScanRule rule) {
    final name = rule.name.toLowerCase();
    if (name.contains('rsi') || name.contains('oversold')) return Icons.show_chart;
    if (name.contains('52w') || name.contains('high')) return Icons.trending_up;
    if (name.contains('volume')) return Icons.bar_chart;
    if (name.contains('momentum')) return Icons.speed;
    if (name.contains('breakout')) return Icons.open_in_full;
    if (name.contains('trend')) return Icons.timeline;
    if (name.contains('sma') || name.contains('moving')) return Icons.auto_graph;
    if (name.contains('accumulation') || name.contains('stealth')) return Icons.visibility_off;
    return Icons.bolt;
  }

  /// Build equity curve data from signals sorted by date
  List<double> _buildEquityCurveData() {
    if (_signals.isEmpty) return [];
    
    // Sort signals by days ago (oldest first = highest daysAgo)
    final sorted = List<Map<String, dynamic>>.from(_signals);
    sorted.sort((a, b) {
      final aDays = (a['daysAgo'] as num?)?.toInt() ?? 0;
      final bDays = (b['daysAgo'] as num?)?.toInt() ?? 0;
      return bDays.compareTo(aDays); // Oldest first
    });
    
    // Build cumulative return curve
    // Each signal contributes equally (1/N weight)
    final equityCurve = <double>[0.0]; // Start at 0%
    double cumulative = 0;
    
    for (final signal in sorted) {
      final returns = signal['returns'] as Map<String, double>? ?? {};
      // Use toToday return, fallback to 7d, 3d, 1d
      double signalReturn = returns['toToday'] ?? returns['7d'] ?? returns['3d'] ?? returns['1d'] ?? 0;
      cumulative += signalReturn / sorted.length; // Equal-weight contribution
      equityCurve.add(cumulative);
    }
    
    return equityCurve;
  }

  String _getPeriodLabel(int days) {
    switch (days) {
      case 7: return '1 week';
      case 14: return '2 weeks';
      case 30: return '1 month';
      case 90: return '3 months';
      case 126: return '6 months';
      default: return '$days days';
    }
  }
}

/// Paints an equity curve (cumulative return) chart with gradient fill
class EquityCurvePainter extends CustomPainter {
  final List<double> data;
  EquityCurvePainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    
    final minVal = data.reduce(math.min);
    final maxVal = data.reduce(math.max);
    final range = maxVal - minVal;
    if (range == 0) return;
    
    final finalReturn = data.last;
    final isPositive = finalReturn >= 0;
    final color = isPositive ? AppTheme.successColor : AppTheme.errorColor;
    
    // Draw zero line
    final zeroY = size.height - ((0 - minVal) / range) * size.height * 0.85 - size.height * 0.075;
    final zeroPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), zeroPaint);
    
    // Draw curve
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    
    final path = Path();
    final fillPath = Path();
    
    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height - ((data[i] - minVal) / range) * size.height * 0.85 - size.height * 0.075;
      
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, zeroY);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    
    // Fill between curve and zero line
    fillPath.lineTo(size.width, zeroY);
    fillPath.close();
    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, isPositive ? 0 : size.height),
        Offset(0, isPositive ? size.height : 0),
        [color.withValues(alpha: 0.25), color.withValues(alpha: 0.0)],
      );
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);
    
    // Labels
    final textStyle = TextStyle(color: Colors.grey[500], fontSize: 10);
    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    
    // Max return label
    textPainter.text = TextSpan(text: '${maxVal >= 0 ? '+' : ''}${maxVal.toStringAsFixed(1)}%', style: textStyle);
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - textPainter.width - 4, 2));
    
    // Min return label
    textPainter.text = TextSpan(text: '${minVal >= 0 ? '+' : ''}${minVal.toStringAsFixed(1)}%', style: textStyle);
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - textPainter.width - 4, size.height - textPainter.height - 2));
    
    // Zero line label
    if (minVal < 0 && maxVal > 0) {
      textPainter.text = TextSpan(text: '0%', style: textStyle);
      textPainter.layout();
      textPainter.paint(canvas, Offset(4, zeroY - textPainter.height - 2));
    }
    
    // Final return label at end of curve
    final finalY = size.height - ((finalReturn - minVal) / range) * size.height * 0.85 - size.height * 0.075;
    textPainter.text = TextSpan(
      text: '${finalReturn >= 0 ? '+' : ''}${finalReturn.toStringAsFixed(1)}%',
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
    );
    textPainter.layout();
    // Draw dot at end
    canvas.drawCircle(
      Offset(size.width - 2, finalY), 
      4, 
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}