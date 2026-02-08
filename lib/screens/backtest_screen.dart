import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_provider.dart';
import '../services/subscription_service.dart';
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
  int _selectedPeriod = 14;
  bool _useAndLogic = true;
  
  // Results
  List<Map<String, dynamic>> _signals = [];
  Map<String, dynamic> _stats = {};
  int _uniqueStocks = 0;
  int _totalSignals = 0;
  
  bool _isLoading = false;
  String _status = '';
  
  final List<int> _periodOptions = [7, 14, 30, 90, 126]; // 1 week, 2 weeks, 1 month, 3 months, 6 months

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppProvider, SubscriptionService>(
      builder: (context, provider, subscription, child) {
        final canBacktest = provider.canRunBacktest();
        final remaining = subscription.remainingBacktests;
        final availableRules = provider.availableRules;
        
        return Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          appBar: AppBar(
            backgroundColor: AppTheme.backgroundColor,
            title: const Text('Backtest Rules'),
            actions: [
              // Filters button
              IconButton(
                icon: Stack(
                  children: [
                    const Icon(Icons.filter_list),
                    if (provider.scanFilters.enabled)
                      Positioned(
                        right: 0, top: 0,
                        child: Container(
                          width: 8, height: 8,
                          decoration: const BoxDecoration(color: AppTheme.accentColor, shape: BoxShape.circle),
                        ),
                      ),
                  ],
                ),
                tooltip: 'Filters: ${provider.scanFilters}',
                onPressed: () async {
                  final newFilters = await ScanFiltersSheet.show(context, provider.scanFilters);
                  if (newFilters != null) {
                    provider.updateScanFilters(newFilters);
                  }
                },
              ),
              if (_selectedRuleIds.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _selectedRuleIds.clear()),
                  child: const Text('Clear'),
                ),
            ],
          ),
          body: Column(
            children: [
              // Backtest limit warning
              if (!subscription.isPro)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  decoration: BoxDecoration(
                    color: remaining <= 1 ? AppTheme.errorColor.withValues(alpha: 0.15) : AppTheme.cardColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(remaining <= 1 ? Icons.warning : Icons.info_outline, 
                        size: 16, 
                        color: remaining <= 1 ? AppTheme.errorColor : AppTheme.textSecondaryColor),
                      const SizedBox(width: 8),
                      Text('$remaining backtest${remaining != 1 ? 's' : ''} remaining today',
                        style: TextStyle(fontSize: 12, color: remaining <= 1 ? AppTheme.errorColor : AppTheme.textSecondaryColor)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => PaywallScreen.show(context, feature: ProFeature.unlimitedBacktests),
                        child: const Text('Upgrade', style: TextStyle(fontSize: 12, color: AppTheme.accentColor, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Info card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.lightbulb_outline, size: 18, color: AppTheme.accentColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Rolling window backtest: Tests rules on EVERY day in the period, tracking multiple holding period returns.',
                                style: TextStyle(fontSize: 11, color: AppTheme.accentColor.withValues(alpha: 0.9)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Rule selection
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Select Rules', style: TextStyle(fontWeight: FontWeight.w600)),
                                if (_selectedRuleIds.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: AppTheme.accentColor, borderRadius: BorderRadius.circular(10)),
                                    child: Text('${_selectedRuleIds.length} selected', style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w600)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: availableRules.map((rule) {
                                final isSelected = _selectedRuleIds.contains(rule.id);
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedRuleIds.remove(rule.id);
                                      } else {
                                        _selectedRuleIds.add(rule.id);
                                      }
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isSelected ? AppTheme.accentColor : AppTheme.backgroundColor,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: isSelected ? AppTheme.accentColor : AppTheme.textTertiaryColor.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isSelected) ...[
                                          const Icon(Icons.check, size: 14, color: Colors.black),
                                          const SizedBox(width: 4),
                                        ],
                                        Text(rule.name, style: TextStyle(fontSize: 12, color: isSelected ? Colors.black : AppTheme.textPrimaryColor, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      
                      // AND/OR logic toggle (only shown when 2+ rules selected)
                      if (_selectedRuleIds.length >= 2) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Combine Rules With', style: TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(() => _useAndLogic = true),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        decoration: BoxDecoration(
                                          color: _useAndLogic ? AppTheme.accentColor : AppTheme.backgroundColor,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Column(
                                          children: [
                                            Text('AND', style: TextStyle(color: _useAndLogic ? Colors.black : AppTheme.textSecondaryColor, fontWeight: FontWeight.bold, fontSize: 16)),
                                            const SizedBox(height: 4),
                                            Text('Match ALL rules', style: TextStyle(color: _useAndLogic ? Colors.black54 : AppTheme.textTertiaryColor, fontSize: 11)),
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
                                        decoration: BoxDecoration(
                                          color: !_useAndLogic ? AppTheme.accentColor : AppTheme.backgroundColor,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Column(
                                          children: [
                                            Text('OR', style: TextStyle(color: !_useAndLogic ? Colors.black : AppTheme.textSecondaryColor, fontWeight: FontWeight.bold, fontSize: 16)),
                                            const SizedBox(height: 4),
                                            Text('Match ANY rule', style: TextStyle(color: !_useAndLogic ? Colors.black54 : AppTheme.textTertiaryColor, fontSize: 11)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                      
                      // Time period
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Test Period', style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            const Text('Tests rule on every day in this period', style: TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor)),
                            const SizedBox(height: 12),
                            Row(
                              children: _periodOptions.map((days) {
                                final isSelected = _selectedPeriod == days;
                                final label = days == 7 ? '1 Week' : days == 14 ? '2 Weeks' : days == 30 ? '1 Month' : days == 90 ? '3 Months' : '6 Months';
                                return Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(() => _selectedPeriod = days),
                                    child: Container(
                                      margin: EdgeInsets.only(right: days != 126 ? 8 : 0),
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isSelected ? AppTheme.accentColor : AppTheme.backgroundColor,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        label,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isSelected ? Colors.black : AppTheme.textSecondaryColor,
                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      
                      // Run button
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _selectedRuleIds.isEmpty 
                            ? null 
                            : (_isLoading 
                                ? () {
                                    provider.stopScan();
                                    setState(() => _isLoading = false);
                                  }
                                : (canBacktest ? _runBacktest : () => PaywallScreen.show(context, feature: ProFeature.unlimitedBacktests))),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isLoading ? AppTheme.errorColor : null,
                          ),
                          child: _isLoading
                            ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                const Icon(Icons.stop, color: Colors.white),
                                const SizedBox(width: 8), 
                                Text('STOP ($_totalSignals signals)', style: const TextStyle(color: Colors.white)),
                              ])
                            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                const Icon(Icons.play_arrow),
                                const SizedBox(width: 8),
                                Text(_selectedRuleIds.length > 1 
                                  ? 'RUN COMBINED BACKTEST' 
                                  : 'RUN BACKTEST'),
                                if (!canBacktest) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.lock, size: 16)),
                              ]),
                        ),
                      ),
                      
                      // Progress
                      if (_isLoading) ...[
                        const SizedBox(height: 8),
                        Text(provider.scanStatus, style: const TextStyle(color: AppTheme.textSecondaryColor, fontSize: 12)),
                        const SizedBox(height: 4),
                        const LinearProgressIndicator(backgroundColor: AppTheme.cardColor, color: AppTheme.accentColor),
                      ],
                      
                      // Status
                      if (_status.isNotEmpty && !_isLoading) ...[
                        const SizedBox(height: 12),
                        Text(_status, style: const TextStyle(color: AppTheme.textSecondaryColor, fontSize: 13)),
                      ],
                      
                      // Stats card
                      if (_stats.isNotEmpty && !_isLoading) ...[
                        const SizedBox(height: 16),
                        _buildStatsCard(),
                      ],
                      
                      // Results
                      if (_signals.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(children: [
                              Text('Signals ($_totalSignals)', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
                              if (_isLoading) ...[
                                const SizedBox(width: 8),
                                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                              ],
                            ]),
                            Text('$_uniqueStocks stocks', style: const TextStyle(color: AppTheme.textSecondaryColor, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._signals.take(50).map((signal) => _buildSignalCard(signal)),
                        if (_signals.length > 50)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('Showing top 50 of $_totalSignals signals', style: const TextStyle(color: AppTheme.textTertiaryColor, fontSize: 12)),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatsCard() {
    // Safely get holdingPeriods with proper null and type checking
    Map<String, dynamic> holdingPeriods = {};
    if (_stats.containsKey('holdingPeriods') && _stats['holdingPeriods'] != null) {
      final hp = _stats['holdingPeriods'];
      if (hp is Map<String, dynamic>) {
        holdingPeriods = hp;
      } else if (hp is Map) {
        holdingPeriods = Map<String, dynamic>.from(hp);
      }
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Performance by Holding Period', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 4),
          const Text('How signals performed at different exit points', style: TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor)),
          const SizedBox(height: 16),
          
          // Table header
          const Row(
            children: [
              Expanded(flex: 2, child: Text('Hold', style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor, fontWeight: FontWeight.w600))),
              Expanded(flex: 2, child: Text('Avg Ret', style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor, fontWeight: FontWeight.w600))),
              Expanded(flex: 2, child: Text('Win %', style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor, fontWeight: FontWeight.w600))),
              Expanded(flex: 1, child: Text('Sharpe', style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor, fontWeight: FontWeight.w600))),
            ],
          ),
          const Divider(height: 16),
          
          // Show empty state if no data
          if (holdingPeriods.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('No performance data available', style: TextStyle(color: AppTheme.textTertiaryColor, fontSize: 13)),
              ),
            )
          else
          // Table rows
          ...['1d', '3d', '7d', 'toToday'].map((period) {
            final statsData = holdingPeriods[period];
            if (statsData == null) return const SizedBox.shrink();
            
            // Safely convert to Map<String, dynamic>
            Map<String, dynamic> stats = {};
            if (statsData is Map<String, dynamic>) {
              stats = statsData;
            } else if (statsData is Map) {
              stats = Map<String, dynamic>.from(statsData);
            } else {
              return const SizedBox.shrink();
            }
            
            final avgReturn = (stats['avgReturn'] as num?)?.toDouble() ?? 0;
            final winRate = (stats['winRate'] as num?)?.toDouble() ?? 0;
            final sharpe = (stats['sharpe'] as num?)?.toDouble() ?? 0;
            final isUp = avgReturn >= 0;
            final color = isUp ? AppTheme.successColor : AppTheme.errorColor;
            
            final periodLabel = period == 'toToday' ? 'Today' : period.toUpperCase();
            
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(flex: 2, child: Text(periodLabel, style: const TextStyle(fontSize: 13))),
                  Expanded(
                    flex: 2, 
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                      child: Text('${isUp ? '+' : ''}${avgReturn.toStringAsFixed(1)}%', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  Expanded(flex: 2, child: Text('${winRate.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 13))),
                  Expanded(flex: 1, child: Text(sharpe.toStringAsFixed(2), style: TextStyle(fontSize: 13, color: sharpe > 0.5 ? AppTheme.successColor : AppTheme.textSecondaryColor))),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSignalCard(Map<String, dynamic> signal) {
    final changePercent = signal['changePercent'] as double? ?? 0;
    final isUp = changePercent >= 0;
    final color = isUp ? AppTheme.successColor : AppTheme.errorColor;
    final daysAgo = signal['daysAgo'] as int? ?? 0;
    final returns = signal['returns'] as Map<String, double>? ?? {};
    final signalDateStr = signal['signalDate'] as String?;
    
    String signalDateFormatted = '$daysAgo days ago';
    if (signalDateStr != null) {
      try {
        final date = DateTime.parse(signalDateStr);
        signalDateFormatted = DateFormat('MMM d').format(date);
      } catch (_) {}
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showModalBottomSheet(
          context: context, 
          isScrollControlled: true, 
          backgroundColor: Colors.transparent, 
          builder: (_) => StockDetailSheet(symbol: signal['symbol']),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40, 
                    height: 40, 
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                    child: Icon(isUp ? Icons.trending_up : Icons.trending_down, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text((signal['symbol'] as String).replaceAll('.AX', ''), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: AppTheme.backgroundColor, borderRadius: BorderRadius.circular(4)),
                              child: Text(signalDateFormatted, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondaryColor)),
                            ),
                            // Watchlist indicator
                            if (signal['inWatchlist'] == true) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.bookmark, size: 10, color: Colors.amber),
                                    SizedBox(width: 2),
                                    Text('WL', style: TextStyle(fontSize: 9, color: Colors.amber, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '\$${(signal['priceAtSignal'] as double).toStringAsFixed(2)} → \$${(signal['currentPrice'] as double).toStringAsFixed(2)}',
                          style: const TextStyle(color: AppTheme.textSecondaryColor, fontSize: 11),
                        ),
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
              
              // Mini returns row
              if (returns.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: returns.entries.where((e) => e.key != 'toToday').take(3).map((entry) {
                    final ret = entry.value;
                    final retUp = ret >= 0;
                    final retColor = retUp ? AppTheme.successColor : AppTheme.errorColor;
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: retColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${entry.key}: ${retUp ? '+' : ''}${ret.toStringAsFixed(1)}%',
                        style: TextStyle(fontSize: 9, color: retColor),
                      ),
                    );
                  }).toList(),
                ),
              ],
              
              // Matched rules display
              if (signal['matchedRules'] != null && (signal['matchedRules'] as List).isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: (signal['matchedRules'] as List).map((ruleName) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bolt, size: 10, color: AppTheme.accentColor),
                          const SizedBox(width: 2),
                          Text(
                            ruleName.toString(),
                            style: const TextStyle(fontSize: 9, color: AppTheme.accentColor, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runBacktest() async {
    if (_selectedRuleIds.isEmpty) return;
    
    setState(() { 
      _isLoading = true; 
      _signals = []; 
      _stats = {};
      _uniqueStocks = 0;
      _totalSignals = 0;
      _status = 'Starting backtest...'; 
    });
    
    final provider = Provider.of<AppProvider>(context, listen: false);
    final selectedRules = provider.availableRules.where((r) => _selectedRuleIds.contains(r.id)).toList();
    
    try {
      final result = await provider.backtestRules(
        selectedRules,
        periodDays: _selectedPeriod,
        useAndLogic: _useAndLogic,
        onResultFound: (signal) {
          if (mounted) {
            setState(() {
              _signals.add(signal);
              _totalSignals = _signals.length;
            });
          }
        },
      );
      
      if (mounted) {
        // Safely extract results with proper type conversion
        List<Map<String, dynamic>> signals = [];
        final signalsData = result['signals'];
        if (signalsData is List) {
          signals = signalsData.map((s) => s is Map<String, dynamic> ? s : Map<String, dynamic>.from(s as Map)).toList();
        }
        
        Map<String, dynamic> stats = {};
        final statsData = result['stats'];
        if (statsData is Map<String, dynamic>) {
          stats = statsData;
        } else if (statsData is Map) {
          stats = Map<String, dynamic>.from(statsData);
        }
        
        setState(() {
          _signals = signals;
          _stats = stats;
          _uniqueStocks = (result['uniqueStocks'] as int?) ?? 0;
          _totalSignals = (result['totalSignals'] as int?) ?? signals.length;
          _isLoading = false;
          _status = _totalSignals == 0 
            ? 'No signals found in the last $_selectedPeriod days'
            : 'Found $_totalSignals signals from $_uniqueStocks stocks';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { 
          _isLoading = false; 
          _status = 'Error: ${e.toString()}'; 
        });
      }
    }
  }
}