import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_provider.dart';
import '../models/holding.dart';
import '../models/scan_rule.dart';
import '../models/stock.dart';
import '../models/watchlist_item.dart';
import '../services/subscription_service.dart';
import '../services/storage_service.dart';
import '../services/api_service.dart';
import '../services/scan_engine_service.dart';
import '../services/technical_indicators_service.dart';
import '../services/market_hours_service.dart';
import '../utils/theme.dart';
import '../main.dart';
import 'stock_detail_sheet.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'paywall_screen.dart';

class TopSetup {
  final Stock stock;
  final String signalType;
  final String signalDescription;
  final DateTime detectedAt;
  final List<double>? sparklineData;
  TopSetup({required this.stock, required this.signalType, required this.signalDescription, required this.detectedAt, this.sparklineData});
  String get timeAgo {
    final diff = DateTime.now().difference(detectedAt);
    if (diff.inMinutes < 60) return '+${diff.inMinutes} Min ago';
    if (diff.inHours < 24) return '~${diff.inHours} Hour${diff.inHours > 1 ? 's' : ''} ago';
    return '~${diff.inDays} Day${diff.inDays > 1 ? 's' : ''} ago';
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<TopSetup> _topSetups = [];
  List<Holding> _holdings = [];
  bool _isLoadingSetups = true;
  bool _isLoadingHoldings = true;
  String? _userName;
  double _portfolioGain = 0;
  double _portfolioValue = 0;

  // Collapsible sections
  bool _watchlistExpanded = true;
  bool _holdingsExpanded = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserName();
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadData();
  }

  Future<void> _loadUserName() async {
    final name = await StorageService.getUserName();
    setState(() => _userName = name);
    if (name == null) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted && _userName == null) _showNamePrompt();
      });
    }
  }

  Future<void> _loadData() async {
    _loadHoldings();
    _loadTopSetups();
    final provider = Provider.of<AppProvider>(context, listen: false);
    provider.refreshData();
  }

  Future<void> _loadHoldings() async {
    final holdings = await StorageService.loadHoldings();
    if (holdings.isNotEmpty) {
      // Fetch live prices for all holdings
      final symbols = holdings.map((h) => h.symbol).toList();
      try {
        final stocks = await ApiService.fetchStocks(symbols);
        for (final stock in stocks) {
          final idx = holdings.indexWhere((h) => h.symbol == stock.symbol);
          if (idx != -1) holdings[idx] = holdings[idx].copyWith(currentPrice: stock.currentPrice);
        }
        // Persist updated prices
        await StorageService.saveHoldings(holdings);
      } catch (_) {}
    }
    double totalGain = 0;
    double totalValue = 0;
    for (final h in holdings) {
      totalGain += h.unrealizedGain;
      totalValue += h.marketValue;
    }
    if (mounted) setState(() {
      _holdings = holdings;
      _portfolioGain = totalGain;
      _portfolioValue = totalValue;
      _isLoadingHoldings = false;
    });
  }

  Future<void> _loadTopSetups() async {
    setState(() => _isLoadingSetups = true);
    final provider = Provider.of<AppProvider>(context, listen: false);

    // Show persisted scan results immediately
    if (provider.scanResults.isNotEmpty) {
      final cached = provider.scanResults.take(5).map((r) => TopSetup(
        stock: r.stock,
        signalType: _getSignalType(r.ruleName),
        signalDescription: r.matchedRuleNames.join(' · '),
        detectedAt: r.matchedAt,
        sparklineData: null,
      )).toList();
      if (mounted) setState(() { _topSetups = cached; _isLoadingSetups = false; });
      return;
    }

    final activeRules = provider.activeRules;
    if (activeRules.isEmpty) {
      if (mounted) setState(() { _topSetups = []; _isLoadingSetups = false; });
      return;
    }

    try {
      int requiredDays = 60;
      for (final rule in activeRules) {
        for (final condition in rule.conditions) {
          if (condition.type == RuleConditionType.event52WeekHighCrossover || condition.type == RuleConditionType.stateNear52WeekHigh) {
            requiredDays = 280;
          } else if (condition.type == RuleConditionType.momentum6Month || condition.type == RuleConditionType.stateMomentumPositive || condition.type == RuleConditionType.eventMomentumCrossover) {
            if (requiredDays < 180) requiredDays = 180;
          } else if (condition.type == RuleConditionType.momentum12Month) {
            requiredDays = 280;
          }
        }
      }
      final setups = <TopSetup>[];
      final topStocks = ApiService.majorStocks.take(50).toList();
      final stocks = await ApiService.fetchStocks(topStocks);
      for (final stock in stocks) {
        if (stock.currentPrice <= 0) continue;
        try {
          final priceData = await ApiService.fetchHistoricalPricesAndVolumes(stock.symbol, days: requiredDays);
          final prices = (priceData['prices'] as List?)?.map((p) => (p as num).toDouble()).toList() ?? [];
          final volumes = (priceData['volumes'] as List?)?.map((v) => (v as num).toInt()).toList() ?? [];
          final highs = (priceData['highs'] as List?)?.map((h) => (h as num).toDouble()).toList();
          final lows = (priceData['lows'] as List?)?.map((l) => (l as num).toDouble()).toList();
          if (prices.isEmpty) continue;
          final enrichedStock = await TechnicalIndicatorsService.addIndicators(stock, prices, highs: highs, lows: lows);
          for (final rule in activeRules) {
            final matches = ScanEngineService.isHybridRule(rule)
              ? ScanEngineService.evaluateHybridRule(enrichedStock, rule, prices: prices, volumes: volumes)
              : ScanEngineService.evaluateRule(enrichedStock, rule, prices: prices, volumes: volumes);
            if (matches) {
              final sparkline = prices.length > 20 ? prices.sublist(prices.length - 20) : prices;
              setups.add(TopSetup(stock: enrichedStock, signalType: _getSignalType(rule.name), signalDescription: _getSignalDescription(rule), detectedAt: DateTime.now(), sparklineData: sparkline));
              break;
            }
          }
          if (setups.length >= 5) break;
        } catch (_) {}
      }
      if (mounted) setState(() { _topSetups = setups; _isLoadingSetups = false; });
    } catch (e) {
      if (mounted) setState(() { _topSetups = []; _isLoadingSetups = false; });
    }
  }

  // ──────────────────────────────────────────────
  // HELPERS
  // ──────────────────────────────────────────────

  String _getSignalType(String ruleName) {
    final lower = ruleName.toLowerCase();
    if (lower.contains('52') && lower.contains('high')) return 'BREAKOUT';
    if (lower.contains('volume') && lower.contains('breakout')) return 'VOLUME';
    if (lower.contains('momentum')) return 'MOMENTUM';
    if (lower.contains('golden')) return 'TREND';
    if (lower.contains('rsi') && lower.contains('oversold')) return 'REVERSAL';
    if (lower.contains('macd')) return 'TREND';
    return 'SIGNAL';
  }

  String _getSignalDescription(dynamic rule) {
    final name = rule.name.toLowerCase();
    if (name.contains('52') && name.contains('high')) return 'Near 52-Week High';
    if (name.contains('volume')) return 'Volume breakout detected';
    if (name.contains('momentum')) return 'Strong momentum signal';
    if (name.contains('golden')) return 'Golden cross confirmed';
    return rule.description ?? 'Signal detected';
  }

  Color _getSignalColor(String signalType) {
    switch (signalType) {
      case 'BREAKOUT': return const Color(0xFFA78BFA);
      case 'VOLUME': return AppTheme.successColor;
      case 'MOMENTUM': return const Color(0xFF5B8DEF);
      case 'REVERSAL': return AppTheme.errorColor;
      case 'TREND': return AppTheme.accentColor;
      default: return AppTheme.accentColor;
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _showNamePrompt() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [Icon(Icons.waving_hand, color: AppTheme.accentColor), SizedBox(width: 12), Text('Welcome!')]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('What should we call you?', style: TextStyle(color: AppTheme.textSecondaryColor)),
          const SizedBox(height: 16),
          TextField(controller: controller, autofocus: true, textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(hintText: 'Your name', filled: true, fillColor: AppTheme.backgroundColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
        ]),
        actions: [
          TextButton(onPressed: () { Navigator.pop(ctx); StorageService.saveUserName(''); }, child: const Text('Skip', style: TextStyle(color: AppTheme.textSecondaryColor))),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) { await StorageService.saveUserName(name); setState(() => _userName = name); }
              if (mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor, foregroundColor: Colors.black),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _showStockDetail(BuildContext context, String symbol, {List<String>? triggerRules}) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) => StockDetailSheet(symbol: symbol, triggerRules: triggerRules),
    );
  }

  // ──────────────────────────────────────────────
  // LONG PRESS MENUS
  // ──────────────────────────────────────────────

  void _showWatchlistItemMenu(BuildContext context, AppProvider provider, SubscriptionService subscription, WatchlistItem item) {
    showModalBottomSheet(
      context: context, backgroundColor: AppTheme.cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header
            Row(children: [
              Text(item.displaySymbol, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text(item.formattedCurrentPrice, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondaryColor)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(ctx)),
            ]),
            Text(item.name, style: const TextStyle(color: AppTheme.textSecondaryColor, fontSize: 13)),
            if (item.allTriggerRules.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.bolt, size: 12, color: AppTheme.accentColor),
                const SizedBox(width: 4),
                Expanded(child: Text(item.allTriggerRules.join(' · '), style: const TextStyle(fontSize: 11, color: AppTheme.accentColor), overflow: TextOverflow.ellipsis)),
              ]),
            ],
            const SizedBox(height: 12),

            // Capital info card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppTheme.backgroundColor, borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Capital Invested', style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
                  Text('\$${item.capitalInvested.toStringAsFixed(0)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Text('Shares', style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
                  Text('${item.theoreticalShares}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Text('Return', style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
                  Text(item.formattedReturn, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: item.isUp ? AppTheme.successColor : AppTheme.errorColor)),
                ]),
              ]),
            ),
            const SizedBox(height: 8),

            // Actions
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.attach_money, color: subscription.isPro ? AppTheme.accentColor : AppTheme.textTertiaryColor, size: 20),
              title: const Text('Change Capital Amount', style: TextStyle(fontSize: 14)),
              trailing: subscription.isPro ? const Icon(Icons.chevron_right, size: 18) : const Icon(Icons.lock, size: 14, color: AppTheme.textTertiaryColor),
              onTap: () {
                Navigator.pop(ctx);
                if (subscription.isPro) _showEditCapitalDialog(context, provider, item);
                else PaywallScreen.show(context, feature: ProFeature.unlimitedWatchlist);
              },
            ),
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.open_in_new, color: AppTheme.textSecondaryColor, size: 20),
              title: const Text('View Details & Chart', style: TextStyle(fontSize: 14)),
              onTap: () { Navigator.pop(ctx); _showStockDetail(context, item.symbol, triggerRules: item.allTriggerRules); },
            ),
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.radar, color: AppTheme.accentColor, size: 20),
              title: const Text('Run Live Scan', style: TextStyle(fontSize: 14)),
              onTap: () { Navigator.pop(ctx); MainScreen.mainKey.currentState?.navigateToScan(segment: 0); },
            ),
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.science_outlined, color: AppTheme.accentColor, size: 20),
              title: const Text('Backtest', style: TextStyle(fontSize: 14)),
              onTap: () { Navigator.pop(ctx); MainScreen.mainKey.currentState?.navigateToScan(segment: 2); },
            ),
            const Divider(height: 8),
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_outline, color: AppTheme.errorColor, size: 20),
              title: const Text('Remove from Watchlist', style: TextStyle(color: AppTheme.errorColor, fontSize: 14)),
              onTap: () { Navigator.pop(ctx); provider.removeFromWatchlist(item.symbol); },
            ),
          ]),
        ),
      ),
    );
  }

  void _showEditCapitalDialog(BuildContext context, AppProvider provider, WatchlistItem item) {
    final controller = TextEditingController(text: item.capitalInvested.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: Text('Edit Capital – ${item.displaySymbol}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('How much would you have invested?', style: TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor)),
          const SizedBox(height: 16),
          TextField(
            controller: controller, keyboardType: TextInputType.number, autofocus: true,
            decoration: const InputDecoration(prefixText: '\$ ', border: OutlineInputBorder(), hintText: '10000'),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [5000, 10000, 25000, 50000].map((amount) =>
            ActionChip(label: Text('\$${(amount / 1000).toStringAsFixed(0)}K'), onPressed: () => controller.text = amount.toString(), backgroundColor: AppTheme.backgroundColor),
          ).toList()),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final newCapital = double.tryParse(controller.text) ?? 10000;
              if (newCapital > 0) { provider.updateWatchlistCapital(item.symbol, newCapital); Navigator.pop(ctx); }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showHoldingMenu(BuildContext context, Holding holding) {
    final isUp = holding.unrealizedGain >= 0;
    final color = isUp ? AppTheme.successColor : AppTheme.errorColor;
    showModalBottomSheet(
      context: context, backgroundColor: AppTheme.cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(holding.symbol.replaceAll('.AX', ''), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text('\$${(holding.currentPrice ?? holding.avgCostBasis).toStringAsFixed(2)}', style: const TextStyle(fontSize: 14, color: AppTheme.textSecondaryColor)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(ctx)),
            ]),
            Text(holding.name, style: const TextStyle(color: AppTheme.textSecondaryColor, fontSize: 13)),
            const SizedBox(height: 12),

            // Holdings info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppTheme.backgroundColor, borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Quantity', style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
                  Text('${holding.quantity}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  const Text('Avg Cost', style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
                  Text('\$${holding.avgCostBasis.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Text('P&L', style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
                  Text(holding.formattedReturn, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
                ]),
              ]),
            ),
            const SizedBox(height: 8),

            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit, color: AppTheme.accentColor, size: 20),
              title: const Text('Edit Quantity / Cost Basis', style: TextStyle(fontSize: 14)),
              onTap: () { Navigator.pop(ctx); _showEditHoldingDialog(context, holding); },
            ),
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.open_in_new, color: AppTheme.textSecondaryColor, size: 20),
              title: const Text('View Details & Chart', style: TextStyle(fontSize: 14)),
              onTap: () { Navigator.pop(ctx); _showStockDetail(context, holding.symbol); },
            ),
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.radar, color: AppTheme.accentColor, size: 20),
              title: const Text('Run Live Scan', style: TextStyle(fontSize: 14)),
              onTap: () { Navigator.pop(ctx); MainScreen.mainKey.currentState?.navigateToScan(segment: 0); },
            ),
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.science_outlined, color: AppTheme.accentColor, size: 20),
              title: const Text('Backtest', style: TextStyle(fontSize: 14)),
              onTap: () { Navigator.pop(ctx); MainScreen.mainKey.currentState?.navigateToScan(segment: 2); },
            ),
            const Divider(height: 8),
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_outline, color: AppTheme.errorColor, size: 20),
              title: const Text('Remove Holding', style: TextStyle(color: AppTheme.errorColor, fontSize: 14)),
              onTap: () async {
                Navigator.pop(ctx);
                final updated = List<Holding>.from(_holdings)..removeWhere((h) => h.symbol == holding.symbol);
                await StorageService.saveHoldings(updated);
                _loadHoldings();
              },
            ),
          ]),
        ),
      ),
    );
  }

  void _showEditHoldingDialog(BuildContext context, Holding holding) {
    final qtyController = TextEditingController(text: holding.quantity.toString());
    final costController = TextEditingController(text: holding.avgCostBasis.toStringAsFixed(2));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: Text('Edit – ${holding.symbol.replaceAll('.AX', '')}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: qtyController, keyboardType: TextInputType.number, autofocus: true,
            decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: costController, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Avg Cost Basis', prefixText: '\$ ', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final qty = int.tryParse(qtyController.text) ?? holding.quantity;
              final cost = double.tryParse(costController.text) ?? holding.avgCostBasis;
              if (qty > 0 && cost > 0) {
                final updated = _holdings.map((h) {
                  if (h.symbol == holding.symbol) return h.copyWith(quantity: qty, avgCostBasis: cost);
                  return h;
                }).toList();
                await StorageService.saveHoldings(updated);
                Navigator.pop(ctx);
                _loadHoldings();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppProvider, SubscriptionService>(
      builder: (context, provider, subscription, child) {
        return Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: _loadData,
              color: AppTheme.accentColor,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader(context)),
                  SliverToBoxAdapter(child: _buildMarketStatus()),
                  SliverToBoxAdapter(child: _buildStatsRow(provider)),

                  // Signals
                  SliverToBoxAdapter(child: _buildSignalsHeader()),
                  if (_isLoadingSetups)
                    const SliverToBoxAdapter(child: _SetupLoadingShimmer())
                  else if (_topSetups.isEmpty && provider.scanResults.isEmpty)
                    SliverToBoxAdapter(child: _buildNoSignals(provider))
                  else ...[
                    if (_topSetups.isNotEmpty)
                      SliverList(delegate: SliverChildBuilderDelegate(
                        (context, i) => _buildSignalCard(_topSetups[i], provider),
                        childCount: _topSetups.length,
                      )),
                    if (provider.scanResults.isNotEmpty && _topSetups.isEmpty)
                      SliverList(delegate: SliverChildBuilderDelegate(
                        (context, i) => _buildScanSignalCard(provider.scanResults[i], provider),
                        childCount: provider.scanResults.take(5).length,
                      )),
                  ],

                  // Watchlist (collapsible)
                  if (provider.watchlist.isNotEmpty) ...[
                    SliverToBoxAdapter(child: _buildCollapsibleHeader(
                      title: 'Watchlist',
                      count: provider.watchlist.length,
                      expanded: _watchlistExpanded,
                      onTap: () => setState(() => _watchlistExpanded = !_watchlistExpanded),
                      trailing: GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(6)),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.add, size: 14, color: AppTheme.textSecondaryColor),
                            SizedBox(width: 4),
                            Text('Add', style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor, fontWeight: FontWeight.w500)),
                          ]),
                        ),
                      ),
                    )),
                    if (_watchlistExpanded)
                      SliverList(delegate: SliverChildBuilderDelegate(
                        (context, i) => _buildWatchlistCard(provider.watchlist[i], provider, subscription),
                        childCount: provider.watchlist.length,
                      )),
                  ],

                  // Holdings (collapsible)
                  if (_holdings.isNotEmpty) ...[
                    SliverToBoxAdapter(child: _buildCollapsibleHeader(
                      title: 'Holdings',
                      count: _holdings.length,
                      expanded: _holdingsExpanded,
                      onTap: () => setState(() => _holdingsExpanded = !_holdingsExpanded),
                      subtitle: _isLoadingHoldings ? null : '\$${NumberFormat.compact().format(_portfolioValue)}',
                    )),
                    if (_holdingsExpanded)
                      SliverList(delegate: SliverChildBuilderDelegate(
                        (context, i) => _buildHoldingCard(_holdings[i]),
                        childCount: _holdings.length,
                      )),
                  ],

                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ──────────────────────────────────────────────
  // HEADER + MARKET
  // ──────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    final name = _userName ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      child: Row(children: [
        Expanded(child: GestureDetector(
          onTap: _userName == null ? _showNamePrompt : null,
          child: Text(
            name.isNotEmpty ? '${_getGreeting()}, $name' : _getGreeting(),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: -0.5),
          ),
        )),
        IconButton(icon: const Icon(Icons.search, size: 24), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()))),
        IconButton(icon: const Icon(Icons.settings_outlined, size: 22), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
      ]),
    );
  }

  Widget _buildMarketStatus() {
    final status = MarketHoursService.getMarketStatus();
    Color statusColor;
    IconData statusIcon;
    switch (status.phase) {
      case MarketPhase.trading: statusColor = AppTheme.successColor; statusIcon = Icons.circle;
      case MarketPhase.preMarket: statusColor = AppTheme.accentColor; statusIcon = Icons.access_time;
      default: statusColor = AppTheme.textSecondaryColor; statusIcon = Icons.circle_outlined;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(children: [
        Icon(statusIcon, size: 7, color: statusColor), const SizedBox(width: 6),
        Text(status.statusText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor)),
        const SizedBox(width: 8),
        Text(status.detailText, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor)),
      ]),
    );
  }

  // ──────────────────────────────────────────────
  // STATS ROW — Portfolio gain from HOLDINGS
  // ──────────────────────────────────────────────

  Widget _buildStatsRow(AppProvider provider) {
    final signalCount = _topSetups.length + (provider.scanResults.isNotEmpty && _topSetups.isEmpty ? provider.scanResults.length : 0);

    // Compute portfolio gain + cost basis based on user's chosen source
    double gain = 0;
    double costBasis = 0;
    bool hasData = false;
    switch (provider.portfolioSource) {
      case PortfolioSource.holdings:
        gain = _portfolioGain;
        for (final h in _holdings) { costBasis += h.costBasis; }
        hasData = _holdings.isNotEmpty;
      case PortfolioSource.watchlist:
        for (final item in provider.watchlist) {
          gain += item.dollarGainLoss;
          costBasis += item.capitalInvested;
        }
        hasData = provider.watchlist.isNotEmpty;
      case PortfolioSource.both:
        gain = _portfolioGain;
        for (final h in _holdings) { costBasis += h.costBasis; }
        for (final item in provider.watchlist) {
          gain += item.dollarGainLoss;
          costBasis += item.capitalInvested;
        }
        hasData = _holdings.isNotEmpty || provider.watchlist.isNotEmpty;
    }
    final pct = costBasis > 0 ? (gain / costBasis) * 100 : 0.0;
    final gainColor = gain >= 0 ? AppTheme.successColor : AppTheme.errorColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(children: [
        // Portfolio card with $ + %
        Expanded(child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text(
              _isLoadingHoldings ? '...' : !hasData ? '—' : '${gain >= 0 ? '+' : '-'}\$${NumberFormat.compact().format(gain.abs())}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: gainColor),
            ),
            if (hasData && !_isLoadingHoldings) ...[
              const SizedBox(height: 1),
              Text(
                '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: gainColor.withValues(alpha: 0.7)),
              ),
            ],
            const SizedBox(height: 2),
            Text('PORTFOLIO', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: AppTheme.textTertiaryColor, letterSpacing: 0.5)),
          ]),
        )),
        const SizedBox(width: 8),
        Expanded(child: _statCard('${provider.watchlist.length}', 'TRACKING', AppTheme.textPrimaryColor)),
        const SizedBox(width: 8),
        Expanded(child: _statCard(_isLoadingSetups ? '...' : '$signalCount', 'SIGNALS', signalCount > 0 ? AppTheme.accentColor : AppTheme.textSecondaryColor)),
      ]),
    );
  }

  Widget _statCard(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: AppTheme.textTertiaryColor, letterSpacing: 0.5)),
      ]),
    );
  }

  // ──────────────────────────────────────────────
  // SIGNALS
  // ──────────────────────────────────────────────

  Widget _buildSignalsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(children: [
        const Text("Today's Signals", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        if (_topSetups.isNotEmpty) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
            child: Text('${_topSetups.length}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.accentColor)),
          ),
        ],
      ]),
    );
  }

  Widget _buildNoSignals(AppProvider provider) {
    final hasRules = provider.activeRules.isNotEmpty;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Icon(Icons.radar, size: 40, color: AppTheme.textTertiaryColor.withValues(alpha: 0.5)),
        const SizedBox(height: 12),
        Text(hasRules ? 'No signals found' : 'No rules active', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 4),
        Text(hasRules ? 'Run a scan to discover setups' : 'Enable rules in Scan tab, then scan', style: const TextStyle(color: AppTheme.textSecondaryColor, fontSize: 13), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: OutlinedButton(
          onPressed: () {
            if (hasRules) MainScreen.mainKey.currentState?.navigateToScan(segment: 0);
            else MainScreen.mainKey.currentState?.navigateToScan(segment: 1);
          },
          style: OutlinedButton.styleFrom(foregroundColor: AppTheme.accentColor, side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.5)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 12)),
          child: Text(hasRules ? 'Go to Scanner' : 'Set Up Rules'),
        )),
      ]),
    );
  }

  Widget _buildSignalCard(TopSetup setup, AppProvider provider) {
    final signalColor = _getSignalColor(setup.signalType);
    final isUp = setup.stock.changePercent >= 0;
    return GestureDetector(
      onTap: () => _showStockDetail(context, setup.stock.symbol, triggerRules: [setup.signalType]),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: signalColor.withValues(alpha: 0.15))),
        child: Row(children: [
          if (setup.sparklineData != null && setup.sparklineData!.length > 2)
            SizedBox(width: 48, height: 32, child: CustomPaint(painter: _SparklinePainter(data: setup.sparklineData!, color: isUp ? AppTheme.successColor : AppTheme.errorColor)))
          else
            Container(width: 40, height: 40, decoration: BoxDecoration(color: signalColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.bolt, color: signalColor, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(setup.stock.symbol.replaceAll('.AX', ''), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: signalColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                child: Text(setup.signalType, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: signalColor, letterSpacing: 0.3)),
              ),
            ]),
            const SizedBox(height: 3),
            Text(setup.signalDescription, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('\$${setup.stock.currentPrice.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('${isUp ? '+' : ''}${setup.stock.changePercent.toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 12, color: isUp ? AppTheme.successColor : AppTheme.errorColor, fontWeight: FontWeight.w500)),
          ]),
        ]),
      ),
    );
  }

  Widget _buildScanSignalCard(ScanResult result, AppProvider provider) {
    final stock = result.stock;
    final isUp = stock.changePercent >= 0;
    final color = isUp ? AppTheme.successColor : AppTheme.errorColor;
    return GestureDetector(
      onTap: () => _showStockDetail(context, stock.symbol, triggerRules: result.matchedRuleNames),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(isUp ? Icons.trending_up : Icons.trending_down, color: color, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(stock.displaySymbol, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 2),
            Text(result.matchedRuleNames.join(' \u00B7 '), style: const TextStyle(fontSize: 11, color: AppTheme.accentColor), overflow: TextOverflow.ellipsis),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(stock.formattedPrice, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            Text('${isUp ? '+' : ''}${stock.changePercent.toStringAsFixed(2)}%', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
          ]),
        ]),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // COLLAPSIBLE SECTION HEADER
  // ──────────────────────────────────────────────

  Widget _buildCollapsibleHeader({
    required String title,
    required int count,
    required bool expanded,
    required VoidCallback onTap,
    Widget? trailing,
    String? subtitle,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
        child: Row(children: [
          AnimatedRotation(
            turns: expanded ? 0.25 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.chevron_right, size: 18, color: AppTheme.textTertiaryColor),
          ),
          const SizedBox(width: 6),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text('$count', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor)),
          if (subtitle != null) ...[
            const SizedBox(width: 8),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textTertiaryColor)),
          ],
          const Spacer(),
          if (trailing != null) trailing,
        ]),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // WATCHLIST CARD (with long-press)
  // ──────────────────────────────────────────────

  Widget _buildWatchlistCard(WatchlistItem item, AppProvider provider, SubscriptionService subscription) {
    final isUp = item.gainLossPercent >= 0;
    final gainColor = isUp ? AppTheme.successColor : AppTheme.errorColor;
    final triggerRules = item.allTriggerRules;
    return Dismissible(
      key: Key(item.symbol),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 6),
        decoration: BoxDecoration(color: AppTheme.errorColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.delete, color: AppTheme.errorColor),
      ),
      onDismissed: (_) {
        provider.removeFromWatchlist(item.symbol);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${item.displaySymbol} removed'),
          action: SnackBarAction(label: 'Undo', onPressed: () => provider.addToWatchlist(item.symbol, item.name, item.addedPrice)),
        ));
      },
      child: GestureDetector(
        onTap: () => _showStockDetail(context, item.symbol, triggerRules: triggerRules),
        onLongPress: () {
          HapticFeedback.mediumImpact();
          _showWatchlistItemMenu(context, provider, subscription, item);
        },
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(item.displaySymbol, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                Text('${item.daysSinceAdded}d', style: const TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor)),
                if (item.capitalInvested != 10000.0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(3)),
                    child: Text('\$${(item.capitalInvested / 1000).toStringAsFixed(0)}K', style: const TextStyle(fontSize: 8, color: AppTheme.accentColor)),
                  ),
                ],
              ]),
              if (triggerRules.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 2), child: Row(children: [
                  const Icon(Icons.bolt, size: 10, color: AppTheme.accentColor),
                  const SizedBox(width: 3),
                  Expanded(child: Text(triggerRules.first, style: const TextStyle(fontSize: 10, color: AppTheme.accentColor), overflow: TextOverflow.ellipsis)),
                ])),
            ])),
            Text(item.formattedCurrentPrice, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: gainColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
              child: Text(item.formattedReturn, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: gainColor)),
            ),
          ]),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // HOLDINGS CARD (with long-press)
  // ──────────────────────────────────────────────

  Widget _buildHoldingCard(Holding holding) {
    final isUp = holding.unrealizedGain >= 0;
    final color = isUp ? AppTheme.successColor : AppTheme.errorColor;
    final price = holding.currentPrice ?? holding.avgCostBasis;
    return GestureDetector(
      onTap: () => _showStockDetail(context, holding.symbol),
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _showHoldingMenu(context, holding);
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(holding.symbol.replaceAll('.AX', ''), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Text('${holding.quantity} shares', style: const TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor)),
            ]),
            const SizedBox(height: 2),
            Text('Avg \$${holding.avgCostBasis.toStringAsFixed(2)} · ${holding.daysHeld}d held',
                style: const TextStyle(fontSize: 10, color: AppTheme.textTertiaryColor)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('\$${price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text('\$${NumberFormat.compact().format(holding.marketValue)}',
                style: const TextStyle(fontSize: 10, color: AppTheme.textTertiaryColor)),
          ]),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
            child: Text(
              '${isUp ? '+' : ''}${holding.unrealizedGainPercent.toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ]),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// SHIMMER + SPARKLINE
// ──────────────────────────────────────────────

class _SetupLoadingShimmer extends StatelessWidget {
  const _SetupLoadingShimmer();
  @override
  Widget build(BuildContext context) {
    return Column(children: List.generate(2, (_) => Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: AppTheme.backgroundColor, borderRadius: BorderRadius.circular(10))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 80, height: 14, decoration: BoxDecoration(color: AppTheme.backgroundColor, borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 6),
          Container(width: 140, height: 10, decoration: BoxDecoration(color: AppTheme.backgroundColor, borderRadius: BorderRadius.circular(4))),
        ])),
        Container(width: 50, height: 14, decoration: BoxDecoration(color: AppTheme.backgroundColor, borderRadius: BorderRadius.circular(4))),
      ]),
    )));
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;
  _SparklinePainter({required this.data, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final paint = Paint()..color = color..strokeWidth = 1.5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final min = data.reduce((a, b) => a < b ? a : b);
    final max = data.reduce((a, b) => a > b ? a : b);
    final range = max - min;
    if (range == 0) return;
    final path = Path();
    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height - ((data[i] - min) / range) * size.height;
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
    final lastY = size.height - ((data.last - min) / range) * size.height;
    canvas.drawCircle(Offset(size.width, lastY), 2.5, Paint()..color = color);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}