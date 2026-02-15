import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../providers/app_provider.dart';
import '../services/api_service.dart';
import '../services/subscription_service.dart';
import '../models/stock.dart';
import '../utils/theme.dart';
import 'stock_detail_sheet.dart';
import 'paywall_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<Stock> _results = [];
  bool _isLoading = false;
  String? _error;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() { _results = []; _error = null; });
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final provider = Provider.of<AppProvider>(context, listen: false);
      final results = await provider.searchStocks(query.trim());
      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
          _error = results.isEmpty ? 'No stocks found for "$query"' : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Search failed: ${e.toString()}';
        });
      }
    }
  }

  void _showStockActions(BuildContext context, Stock stock, AppProvider provider, SubscriptionService subscription) {
    final inWatchlist = provider.isInWatchlist(stock.symbol);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stock.displaySymbol, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      Text(stock.name, style: const TextStyle(color: AppTheme.textSecondaryColor, fontSize: 13)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(stock.formattedPrice, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(
                      '${stock.changePercent >= 0 ? '+' : ''}${stock.changePercent.toStringAsFixed(2)}%',
                      style: TextStyle(color: stock.changePercent >= 0 ? AppTheme.successColor : AppTheme.errorColor),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 24),
            
            // View Details
            ListTile(
              leading: const Icon(Icons.show_chart, color: AppTheme.accentColor),
              title: const Text('View Details & Chart'),
              subtitle: const Text('Full stock analysis', style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
              onTap: () {
                Navigator.pop(ctx);
                provider.stockCache[stock.symbol] = stock;
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => StockDetailSheet(symbol: stock.symbol),
                );
              },
            ),
            
            // Test Rules on this stock
            ListTile(
              leading: const Icon(Icons.science, color: Colors.purple),
              title: const Text('Test Rules on This Stock'),
              subtitle: const Text('Run all active rules against this stock', style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
              onTap: () {
                Navigator.pop(ctx);
                _testRulesOnStock(context, stock, provider);
              },
            ),
            
            // Backtest on this stock
            ListTile(
              leading: const Icon(Icons.history, color: Colors.orange),
              title: const Text('Backtest on This Stock'),
              subtitle: const Text('Test rule performance on this stock\'s history', style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
              onTap: () {
                Navigator.pop(ctx);
                _backtestOnStock(context, stock, provider, subscription);
              },
            ),
            
            const Divider(height: 8),
            
            // Add/Remove from Watchlist
            if (!inWatchlist)
              ListTile(
                leading: const Icon(Icons.bookmark_add, color: AppTheme.successColor),
                title: const Text('Add to Watchlist'),
                onTap: () {
                  Navigator.pop(ctx);
                  if (provider.canAddToWatchlist()) {
                    provider.addToWatchlist(stock.symbol, stock.name, stock.currentPrice);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${stock.displaySymbol} added to watchlist'), backgroundColor: AppTheme.successColor),
                    );
                  } else {
                    PaywallScreen.show(context, feature: ProFeature.unlimitedWatchlist);
                  }
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.bookmark_remove, color: AppTheme.errorColor),
                title: const Text('Remove from Watchlist'),
                onTap: () {
                  Navigator.pop(ctx);
                  provider.removeFromWatchlist(stock.symbol);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${stock.displaySymbol} removed from watchlist'), backgroundColor: AppTheme.textSecondaryColor),
                  );
                },
              ),
            
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
  
  Future<void> _testRulesOnStock(BuildContext context, Stock stock, AppProvider provider) async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: AppTheme.cardColor,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.accentColor),
            SizedBox(height: 16),
            Text('Testing rules...'),
          ],
        ),
      ),
    );
    
    try {
      // Fetch historical data for the stock
      final priceData = await ApiService.fetchHistoricalPricesAndVolumes(stock.symbol, days: 300);
      final prices = (priceData['prices'])?.map((p) => (p as num).toDouble()).toList() ?? [];
      final volumes = (priceData['volumes'])?.map((v) => (v as num).toInt()).toList() ?? [];
      
      if (prices.isEmpty) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not fetch price data'), backgroundColor: AppTheme.errorColor),
        );
        return;
      }
      
      // Test all active rules
      final activeRules = provider.activeRules;
      final matchedRules = <String>[];
      
      for (final rule in activeRules) {
        final passed = provider.testRuleOnStock(stock, rule, prices: prices, volumes: volumes);
        if (passed) {
          matchedRules.add(rule.name);
        }
      }
      
      Navigator.pop(context); // Close loading
      
      // Show results
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppTheme.cardColor,
          title: Row(
            children: [
              Icon(
                matchedRules.isNotEmpty ? Icons.check_circle : Icons.cancel,
                color: matchedRules.isNotEmpty ? AppTheme.successColor : AppTheme.textSecondaryColor,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('${stock.displaySymbol} Rule Test', style: const TextStyle(fontSize: 18))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (matchedRules.isEmpty)
                const Text('No active rules matched this stock today.', style: TextStyle(color: AppTheme.textSecondaryColor))
              else ...[
                Text('${matchedRules.length} rule${matchedRules.length > 1 ? 's' : ''} matched:', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                ...matchedRules.map((rule) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt, size: 16, color: AppTheme.accentColor),
                      const SizedBox(width: 8),
                      Expanded(child: Text(rule, style: const TextStyle(color: AppTheme.accentColor))),
                    ],
                  ),
                )),
              ],
              const SizedBox(height: 8),
              Text('Tested ${activeRules.length} active rules', style: const TextStyle(fontSize: 12, color: AppTheme.textTertiaryColor)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            if (matchedRules.isNotEmpty && !provider.isInWatchlist(stock.symbol))
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  provider.addToWatchlist(stock.symbol, stock.name, stock.currentPrice, triggerRules: matchedRules);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${stock.displaySymbol} added to watchlist'), backgroundColor: AppTheme.successColor),
                  );
                },
                child: const Text('Add to Watchlist'),
              ),
          ],
        ),
      );
    } catch (e) {
      Navigator.pop(context); // Close loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: AppTheme.errorColor),
      );
    }
  }
  
  Future<void> _backtestOnStock(BuildContext context, Stock stock, AppProvider provider, SubscriptionService subscription) async {
    if (!provider.canRunBacktest()) {
      PaywallScreen.show(context, feature: ProFeature.unlimitedBacktests);
      return;
    }
    
    // Show rule selection dialog
    final activeRules = provider.availableRules;
    String? selectedRuleId;
    int selectedPeriod = 30;
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.cardColor,
          title: Text('Backtest on ${stock.displaySymbol}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select Rule:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: activeRules.length,
                    itemBuilder: (_, i) {
                      final rule = activeRules[i];
                      final isSelected = selectedRuleId == rule.id;
                      return ListTile(
                        dense: true,
                        selected: isSelected,
                        selectedTileColor: AppTheme.accentColor.withValues(alpha: 0.15),
                        title: Text(rule.name, style: TextStyle(fontSize: 13, color: isSelected ? AppTheme.accentColor : null)),
                        trailing: isSelected ? const Icon(Icons.check, color: AppTheme.accentColor, size: 18) : null,
                        onTap: () => setDialogState(() => selectedRuleId = rule.id),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Period:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [7, 14, 30, 90].map((days) {
                    final isSelected = selectedPeriod == days;
                    return ChoiceChip(
                      label: Text(days == 7 ? '1W' : days == 14 ? '2W' : days == 30 ? '1M' : '3M'),
                      selected: isSelected,
                      selectedColor: AppTheme.accentColor,
                      onSelected: (_) => setDialogState(() => selectedPeriod = days),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: selectedRuleId == null ? null : () => Navigator.pop(context, {'ruleId': selectedRuleId, 'period': selectedPeriod}),
              child: const Text('Run Backtest'),
            ),
          ],
        ),
      ),
    );
    
    if (result == null) return;
    
    final selectedRule = activeRules.firstWhere((r) => r.id == result['ruleId']);
    final period = result['period'] as int;
    
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppTheme.accentColor),
            const SizedBox(height: 16),
            Text('Backtesting ${selectedRule.name}...'),
            Text('on ${stock.displaySymbol} for $period days', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor)),
          ],
        ),
      ),
    );
    
    try {
      final backtestResult = await provider.backtestRuleOnStock(stock.symbol, selectedRule, periodDays: period);
      
      Navigator.pop(context); // Close loading
      
      // Show results
      final signals = backtestResult['signals'] as List<Map<String, dynamic>>? ?? [];
      final stats = backtestResult['stats'] as Map<String, dynamic>? ?? {};
      
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppTheme.cardColor,
          title: Text('${stock.displaySymbol} Backtest Results'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rule: ${selectedRule.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('Period: $period days', style: const TextStyle(color: AppTheme.textSecondaryColor, fontSize: 13)),
              const Divider(height: 24),
              if (signals.isEmpty)
                const Text('No signals found in this period.', style: TextStyle(color: AppTheme.textSecondaryColor))
              else ...[
                Text('${signals.length} signal${signals.length > 1 ? 's' : ''} found', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                ...signals.take(5).map((s) {
                  final change = (s['changePercent'] as double?) ?? 0;
                  final isUp = change >= 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Text('${s['daysAgo']}d ago:', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor)),
                        const Spacer(),
                        Text(
                          '${isUp ? '+' : ''}${change.toStringAsFixed(1)}%',
                          style: TextStyle(color: isUp ? AppTheme.successColor : AppTheme.errorColor, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  );
                }),
                if (signals.length > 5)
                  Text('... and ${signals.length - 5} more', style: const TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      );
    } catch (e) {
      Navigator.pop(context); // Close loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: AppTheme.errorColor),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppProvider, SubscriptionService>(
      builder: (context, provider, subscription, child) {
        return Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          appBar: AppBar(
            backgroundColor: AppTheme.backgroundColor,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            title: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(
                hintText: 'Search ASX stocks...',
                hintStyle: TextStyle(color: AppTheme.textTertiaryColor),
                border: InputBorder.none,
              ),
              onChanged: (value) {
                // Proper debounce: cancel previous timer, start new 300ms delay
                _debounceTimer?.cancel();
                _debounceTimer = Timer(const Duration(milliseconds: 300), () {
                  _search(value);
                });
              },
              onSubmitted: _search,
            ),
            actions: [
              if (_controller.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _controller.clear();
                    setState(() { _results = []; _error = null; });
                  },
                ),
            ],
          ),
          body: _buildBody(provider, subscription),
        );
      },
    );
  }

  Widget _buildBody(AppProvider provider, SubscriptionService subscription) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppTheme.accentColor),
            SizedBox(height: 16),
            Text('Searching...', style: TextStyle(color: AppTheme.textSecondaryColor)),
          ],
        ),
      );
    }

    if (_error != null && _results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.search_off, size: 64, color: AppTheme.textTertiaryColor),
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: AppTheme.textSecondaryColor), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              const Text(
                'Tips:\n• Enter stock code (BHP, CBA, CSL)\n• Enter company name (Woolworths, Telstra)\n• Check your internet connection',
                style: TextStyle(fontSize: 13, color: AppTheme.textTertiaryColor),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty && _controller.text.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.search, size: 64, color: AppTheme.textTertiaryColor),
              const SizedBox(height: 16),
              const Text('Search ASX Stocks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text(
                'Enter a stock code or company name\nto find ASX listed stocks',
                style: TextStyle(color: AppTheme.textSecondaryColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: ['BHP', 'CBA', 'CSL', 'WOW', 'TLS'].map((code) {
                  return ActionChip(
                    label: Text(code),
                    backgroundColor: AppTheme.cardColor,
                    onPressed: () {
                      _controller.text = code;
                      _search(code);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final stock = _results[index];
        final isUp = stock.changePercent >= 0;
        final color = isUp ? AppTheme.successColor : AppTheme.errorColor;
        final inWatchlist = provider.isInWatchlist(stock.symbol);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppTheme.cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            onTap: () => _showStockActions(context, stock, provider, subscription),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  stock.displaySymbol.substring(0, stock.displaySymbol.length > 3 ? 3 : stock.displaySymbol.length),
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
            title: Row(
              children: [
                Text(stock.displaySymbol, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (inWatchlist) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.bookmark, size: 14, color: AppTheme.accentColor),
                ],
              ],
            ),
            subtitle: Text(
              stock.name,
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(stock.formattedPrice, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  '${isUp ? '+' : ''}${stock.changePercent.toStringAsFixed(2)}%',
                  style: TextStyle(color: color, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}