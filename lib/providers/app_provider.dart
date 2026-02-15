import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/stock.dart';
import '../models/watchlist_item.dart';
import '../models/scan_rule.dart';
import '../models/scan_filters.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/technical_indicators_service.dart';
import '../services/scan_engine_service.dart';
import '../services/subscription_service.dart';
import '../services/background_task_service.dart';
import '../services/error_reporting_service.dart';
import 'watchlist_provider.dart';

enum ScanSortOption {
  matchTime,
  alphabetical,
  priceHigh,
  priceLow,
  changeHigh,
  changeLow,
  volumeHigh,
  rulesMatched,
}

enum PortfolioSource {
  holdings,
  watchlist,
  both,
}

/// Scan result with matched rule info
class ScanResult {
  final Stock stock;
  final String ruleId; // Primary rule ID (first matched)
  final String ruleName; // Primary rule name
  final List<String> matchedRuleIds; // All rule IDs that matched
  final List<String> matchedRuleNames; // All rule names that matched
  final DateTime matchedAt;

  ScanResult({
    required this.stock, 
    required this.ruleId, 
    required this.ruleName, 
    required this.matchedAt,
    List<String>? matchedRuleIds,
    List<String>? matchedRuleNames,
  }) : matchedRuleIds = matchedRuleIds ?? [ruleId],
       matchedRuleNames = matchedRuleNames ?? [ruleName];
  
  // Add a rule to the matched list
  ScanResult withAdditionalRule(String id, String name) {
    return ScanResult(
      stock: stock,
      ruleId: ruleId,
      ruleName: ruleName,
      matchedAt: matchedAt,
      matchedRuleIds: [...matchedRuleIds, if (!matchedRuleIds.contains(id)) id],
      matchedRuleNames: [...matchedRuleNames, if (!matchedRuleNames.contains(name)) name],
    );
  }
}

class AppProvider with ChangeNotifier, WatchlistProviderMixin {
  Map<String, Stock> _stockCache = {};
  
  /// Cached backtest stats per rule ID (populated after backtests)
  final Map<String, Map<String, dynamic>> _ruleBacktestStats = {};
  List<ScanRule> _rules = [];
  List<Map<String, dynamic>> _alerts = [];
  List<ScanResult> _scanResults = [];
  bool _isLoading = false;
  bool _isScanning = false;
  String _scanStatus = '';
  int _scanProgress = 0;
  int _scanTotal = 0;
  int _validStocksFound = 0;
  String? _error;
  DateTime? _lastRefresh;
  SubscriptionService? _subscription;
  PortfolioSource _portfolioSource = PortfolioSource.holdings;

  // Provide stockCache and subscription to WatchlistProviderMixin
  @override
  Map<String, Stock> get stockCache => _stockCache;
  @override
  SubscriptionService? get subscription => _subscription;
  ScanFilters _scanFilters = ScanFilters.defaultFilters;

  // Non-watchlist getters (watchlist ones come from WatchlistProviderMixin)
  List<ScanRule> get rules => _rules;
  List<ScanRule> get activeRules => _rules.where((r) => r.isActive).toList();
  List<Map<String, dynamic>> get alerts => _alerts;
  List<ScanResult> get scanResults => _scanResults;
  
  /// Get cached backtest stats for a rule, or null if not yet tested
  Map<String, dynamic>? getRuleBacktestStats(String ruleId) => _ruleBacktestStats[ruleId];
  bool get isLoading => _isLoading;
  bool get isScanning => _isScanning;
  String get scanStatus => _scanStatus;
  int get scanProgress => _scanProgress;
  int get scanTotal => _scanTotal;
  int get validStocksFound => _validStocksFound;
  String? get error => _error;
  DateTime? get lastRefresh => _lastRefresh;
  int get unreadAlertCount => _alerts.where((a) => a['isRead'] != true).length;
  ScanFilters get scanFilters => _scanFilters;
  PortfolioSource get portfolioSource => _portfolioSource;
  
  void updateScanFilters(ScanFilters filters) {
    _scanFilters = filters;
    notifyListeners();
  }

  Future<void> setPortfolioSource(PortfolioSource source) async {
    _portfolioSource = source;
    await StorageService.saveSettings({'portfolioSource': source.name});
    notifyListeners();
  }

  void setSubscription(SubscriptionService subscription) {
    _subscription = subscription;
  }

  bool canUseRule(String ruleId) => _subscription?.canUseRule(ruleId) ?? false;

  List<ScanRule> get availableRules {
    if (_subscription?.isPro ?? false) return _rules;
    return _rules.where((r) => SubscriptionService.freeRuleIds.contains(r.id)).toList();
  }

  List<ScanRule> get lockedRules {
    if (_subscription?.isPro ?? false) return [];
    return _rules.where((r) => !SubscriptionService.freeRuleIds.contains(r.id)).toList();
  }

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();
    try {
      await initWatchlist();
      _rules = await StorageService.loadRules();
      _alerts = await StorageService.loadAlerts();
      _stockCache = await StorageService.loadStockCache();
      _lastRefresh = await StorageService.getCacheTime();
      
      // Load persisted scan results from last session
      await _loadScanResults();
      
      // Load settings
      final settings = await StorageService.loadSettings();
      includeDividendsValue = settings['includeDividends'] ?? false;
      final srcStr = settings['portfolioSource'] as String?;
      if (srcStr != null) {
        _portfolioSource = PortfolioSource.values.firstWhere(
          (e) => e.name == srcStr, orElse: () => PortfolioSource.holdings,
        );
      }
      
      await ApiService.initializeValidSymbols();
      
      // ALWAYS refresh watchlist prices on app open
      await updateWatchlistPrices();
      
      // Also refresh major stocks if cache is empty
      if (_stockCache.isEmpty) {
        await refreshData();
      }
    } catch (e) { _error = e.toString(); }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> refreshData() async {
    _isLoading = true; _error = null;
    notifyListeners();
    try {
      // Always fetch fresh stock data (don't use cache)
      final stocks = await ApiService.fetchStocks(ApiService.majorStocks);
      for (final stock in stocks) {
        _stockCache[stock.symbol] = stock;
      }
      await StorageService.saveStockCache(_stockCache);
      _lastRefresh = DateTime.now();
      
      // Update watchlist with fresh prices
      await updateWatchlistPrices();
    } catch (e) { _error = e.toString(); }
    _isLoading = false;
    notifyListeners();
  }

  // Watchlist methods are provided by WatchlistProviderMixin
  // refreshWatchlistPrices delegates to the mixin's updateWatchlistPrices
  Future<void> refreshWatchlistPrices() async {
    await updateWatchlistPrices();
    await StorageService.saveWatchlist(watchlist);
    notifyListeners();
  }

  Future<void> toggleRule(String id) async {
    if (!canUseRule(id)) {
      _error = 'Upgrade to Pro to use this rule';
      notifyListeners();
      return;
    }
    final index = _rules.indexWhere((r) => r.id == id);
    if (index != -1) {
      _rules[index] = _rules[index].copyWith(isActive: !_rules[index].isActive);
      await StorageService.saveRules(_rules);
      notifyListeners();
    }
  }

  /// Save a custom rule (Pro feature)
  Future<void> saveCustomRule(ScanRule rule, {bool isNew = true}) async {
    if (isNew) {
      _rules.add(rule);
    } else {
      final index = _rules.indexWhere((r) => r.id == rule.id);
      if (index != -1) {
        _rules[index] = rule;
      } else {
        _rules.add(rule);
      }
    }
    await StorageService.saveRules(_rules);
    notifyListeners();
  }

  /// Delete a custom rule
  Future<void> deleteRule(String id) async {
    _rules.removeWhere((r) => r.id == id);
    await StorageService.saveRules(_rules);
    notifyListeners();
  }

  /// Check if rule is custom (can be edited/deleted)
  bool isCustomRule(String id) {
    return id.startsWith('custom_');
  }

  bool get canRunFullScan => _subscription?.hasFeature(ProFeature.fullAsxScan) ?? false;

  /// Stop the current scan
  void stopScan() {
    _isScanning = false;
    _scanStatus = 'Scan stopped';
    BackgroundTaskService.stopTask();
    notifyListeners();
  }

  /// Run scan with background support
  Future<void> runScan({bool fullScan = true}) async {
    if (_isScanning) return;
    
    final usableActiveRules = activeRules.where((r) => canUseRule(r.id)).toList();
    if (usableActiveRules.isEmpty) {
      _error = 'No active rules. Enable at least one rule first.';
      notifyListeners();
      return;
    }
    
    _isScanning = true;
    _scanResults = [];
    _error = null;
    _scanProgress = 0;
    _validStocksFound = 0;
    
    final doFullScan = fullScan && canRunFullScan;
    final allSymbols = doFullScan ? ApiService.generateAllAsxSymbols() : ApiService.majorStocks;
    
    _scanTotal = allSymbols.length;
    _scanStatus = doFullScan ? 'Starting full ASX scan...' : 'Quick scan: $_scanTotal stocks...';
    notifyListeners();

    // Start background task to keep running when app is backgrounded
    await BackgroundTaskService.startScanTask(
      taskName: doFullScan ? 'Full ASX Scan' : 'Quick Scan',
      totalStocks: _scanTotal,
    );

    try {
      // Process in batches
      for (int i = 0; i < allSymbols.length && _isScanning; i += 10) {
        final batch = allSymbols.skip(i).take(10).toList();
        _scanProgress = i;
        _scanStatus = 'Scanning $i/$_scanTotal | Found $_validStocksFound stocks | ${_scanResults.length} matches';
        notifyListeners();
        
        // Update background notification
        await BackgroundTaskService.updateProgress(
          taskName: doFullScan ? 'Full Scan' : 'Quick Scan',
          current: i,
          total: _scanTotal,
          matches: _scanResults.length,
        );

        final stocks = await ApiService.fetchStocks(batch);
        
        for (final stock in stocks) {
          if (!_isScanning) break;
          
          _validStocksFound++;
          _stockCache[stock.symbol] = stock;
          
          // --- Fetch historical data ONCE per stock ---
          // Determine the maximum data needed across all active rules
          bool anyNeedsHistorical = false;
          bool anyNeedsVolume = false;
          bool anyNeedsLongHistory = false;
          
          for (final rule in usableActiveRules) {
            if (!ScanEngineService.canQuickEvaluate(rule)) anyNeedsHistorical = true;
            if (rule.conditions.any((c) => 
              c.type == RuleConditionType.stateVolumeExpanding ||
              c.type == RuleConditionType.eventVolumeBreakout ||
              c.type == RuleConditionType.volumeSpike ||
              c.type == RuleConditionType.stealthAccumulation
            )) anyNeedsVolume = true;
            if (rule.conditions.any((c) =>
              c.type == RuleConditionType.event52WeekHighCrossover ||
              c.type == RuleConditionType.eventMomentumCrossover ||
              c.type == RuleConditionType.stateMomentumPositive ||
              c.type == RuleConditionType.stateNear52WeekHigh ||
              c.type == RuleConditionType.momentum6Month
            )) anyNeedsLongHistory = true;
          }
          
          // Fetch data once with the maximum required lookback
          List<double>? prices;
          List<int>? volumes;
          List<double>? highs;
          List<double>? lows;
          
          // Always fetch at least short history for filter gap check
          if (_scanFilters.enabled && _scanFilters.maxSingleDayGap != null) {
            anyNeedsHistorical = true;
          }
          
          if (anyNeedsHistorical || anyNeedsVolume || anyNeedsLongHistory) {
            final days = anyNeedsLongHistory ? 280 : 100;
            final priceData = await ApiService.fetchHistoricalPricesAndVolumes(stock.symbol, days: days);
            prices = (priceData['prices'])?.map((p) => (p as num).toDouble()).toList();
            volumes = (priceData['volumes'])?.map((v) => (v as num).toInt()).toList();
            highs = (priceData['highs'])?.map((h) => (h as num).toDouble()).toList();
            lows = (priceData['lows'])?.map((l) => (l as num).toDouble()).toList();
          }
          
          // Apply scan filters (using already-fetched prices)
          if (!_scanFilters.passesFilters(
            currentPrice: stock.currentPrice,
            avgVolume: stock.avgVolume,
            historicalPrices: prices,
          )) {
            continue; // Skip this stock - doesn't pass filters
          }

          // Enrich stock with indicators ONCE
          Stock enrichedStock = stock;
          if (prices != null && prices.isNotEmpty) {
            enrichedStock = await TechnicalIndicatorsService.addIndicators(
              stock, prices, highs: highs, lows: lows,
            );
            _stockCache[stock.symbol] = enrichedStock;
          }

          // Check each rule against the same enriched stock
          for (final rule in usableActiveRules) {
            final passed = ScanEngineService.isHybridRule(rule)
              ? ScanEngineService.evaluateHybridRule(enrichedStock, rule, prices: prices, volumes: volumes)
              : ScanEngineService.evaluateRule(enrichedStock, rule, prices: prices, volumes: volumes);
            
            if (passed) {
              // Check if already matched by a different rule
              final existingIndex = _scanResults.indexWhere((r) => r.stock.symbol == stock.symbol);
              if (existingIndex >= 0) {
                // Add this rule to the existing result
                _scanResults[existingIndex] = _scanResults[existingIndex].withAdditionalRule(rule.id, rule.name);
              } else {
                // First rule match for this stock
                _scanResults.add(ScanResult(
                  stock: enrichedStock,
                  ruleId: rule.id,
                  ruleName: rule.name,
                  matchedAt: DateTime.now(),
                ));
                await _createAlert(enrichedStock, rule);
                // Live-load: notify UI immediately so cards appear as found
                notifyListeners();
              }
            }
          }
        }

        // Small delay to prevent rate limiting and allow UI updates
        await Future.delayed(const Duration(milliseconds: 50));
      }

      await StorageService.saveStockCache(_stockCache);
      
      if (_isScanning) {
        _scanStatus = 'Complete: ${_scanResults.length} matches from $_validStocksFound stocks';
      }
    } catch (e) {
      _error = e.toString();
      _scanStatus = 'Error: ${e.toString()}';
    }

    _isScanning = false;
    
    // Persist scan results for Home screen on next launch
    await _saveScanResults();
    
    // Show completion notification
    await BackgroundTaskService.completeTask(
      taskName: 'Scan',
      matches: _scanResults.length,
      uniqueStocks: _validStocksFound,
    );
    
    notifyListeners();
    
    // Notify user with haptic feedback when done
    HapticFeedback.mediumImpact();
  }

  Future<void> runQuickScan() async => await runScan(fullScan: false);

  Future<void> _createAlert(Stock stock, ScanRule rule) async {
    final alert = {
      'id': '${stock.symbol}_${rule.id}_${DateTime.now().millisecondsSinceEpoch}',
      'symbol': stock.symbol,
      'name': stock.name,
      'ruleId': rule.id,
      'ruleName': rule.name,
      'price': stock.currentPrice,
      'change': stock.changePercent,
      'timestamp': DateTime.now().toIso8601String(),
      'isRead': false,
    };
    _alerts.insert(0, alert);
    if (_alerts.length > 100) _alerts = _alerts.sublist(0, 100);
    await StorageService.saveAlerts(_alerts);
  }

  // ─── Scan result persistence ───────────────────────────────
  
  DateTime? _scanResultsTimestamp;
  DateTime? get scanResultsTimestamp => _scanResultsTimestamp;

  Future<void> _saveScanResults() async {
    if (_scanResults.isEmpty) return;
    try {
      final data = _scanResults.map((r) => {
        'stock': r.stock.toJson(),
        'ruleId': r.ruleId,
        'ruleName': r.ruleName,
        'matchedRuleIds': r.matchedRuleIds,
        'matchedRuleNames': r.matchedRuleNames,
        'matchedAt': r.matchedAt.toIso8601String(),
      }).toList();
      final payload = {
        'results': data,
        'timestamp': DateTime.now().toIso8601String(),
      };
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_scan_results', jsonEncode(payload));
    } catch (_) {}
  }

  Future<void> _loadScanResults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('last_scan_results');
      if (raw == null) return;
      final payload = jsonDecode(raw) as Map<String, dynamic>;
      final timestamp = DateTime.tryParse(payload['timestamp'] ?? '');
      _scanResultsTimestamp = timestamp;
      
      // Only load if less than 24 hours old
      if (timestamp != null && DateTime.now().difference(timestamp).inHours > 24) return;
      
      final results = (payload['results'] as List).map((r) {
        final map = r as Map<String, dynamic>;
        return ScanResult(
          stock: Stock.fromJson(map['stock'] as Map<String, dynamic>),
          ruleId: map['ruleId'] as String,
          ruleName: map['ruleName'] as String,
          matchedAt: DateTime.tryParse(map['matchedAt'] ?? '') ?? DateTime.now(),
          matchedRuleIds: (map['matchedRuleIds'] as List?)?.cast<String>(),
          matchedRuleNames: (map['matchedRuleNames'] as List?)?.cast<String>(),
        );
      }).toList();
      
      // Only load persisted results if we don't already have fresh scan results
      if (_scanResults.isEmpty) {
        _scanResults = results;
      }
    } catch (_) {}
  }

  // ─── Sort scan results ─────────────────────────────────────

  ScanSortOption _scanSortOption = ScanSortOption.matchTime;
  ScanSortOption get scanSortOption => _scanSortOption;

  void setScanSort(ScanSortOption option) {
    _scanSortOption = option;
    _applyScanSort();
    notifyListeners();
  }

  void _applyScanSort() {
    switch (_scanSortOption) {
      case ScanSortOption.matchTime:
        _scanResults.sort((a, b) => b.matchedAt.compareTo(a.matchedAt));
      case ScanSortOption.alphabetical:
        _scanResults.sort((a, b) => a.stock.symbol.compareTo(b.stock.symbol));
      case ScanSortOption.priceHigh:
        _scanResults.sort((a, b) => b.stock.currentPrice.compareTo(a.stock.currentPrice));
      case ScanSortOption.priceLow:
        _scanResults.sort((a, b) => a.stock.currentPrice.compareTo(b.stock.currentPrice));
      case ScanSortOption.changeHigh:
        _scanResults.sort((a, b) => b.stock.changePercent.compareTo(a.stock.changePercent));
      case ScanSortOption.changeLow:
        _scanResults.sort((a, b) => a.stock.changePercent.compareTo(b.stock.changePercent));
      case ScanSortOption.volumeHigh:
        _scanResults.sort((a, b) => b.stock.volume.compareTo(a.stock.volume));
      case ScanSortOption.rulesMatched:
        _scanResults.sort((a, b) => b.matchedRuleNames.length.compareTo(a.matchedRuleNames.length));
    }
  }

  Future<void> markAlertRead(String id) async {
    final index = _alerts.indexWhere((a) => a['id'] == id);
    if (index != -1) {
      _alerts[index]['isRead'] = true;
      await StorageService.saveAlerts(_alerts);
      notifyListeners();
    }
  }

  Future<void> clearAlerts() async {
    _alerts.clear();
    await StorageService.saveAlerts(_alerts);
    notifyListeners();
  }

  Future<List<Stock>> searchStocks(String query) async => ApiService.searchAsxStocks(query);

  /// Test a single rule on a stock with the given price/volume data
  bool testRuleOnStock(Stock stock, ScanRule rule, {List<double>? prices, List<int>? volumes}) {
    return ScanEngineService.isHybridRule(rule)
      ? ScanEngineService.evaluateHybridRule(stock, rule, prices: prices, volumes: volumes)
      : ScanEngineService.evaluateRule(stock, rule, prices: prices, volumes: volumes);
  }
  
  /// Backtest a rule on a single stock's historical data
  Future<Map<String, dynamic>> backtestRuleOnStock(String symbol, ScanRule rule, {int periodDays = 30}) async {
    final signals = <Map<String, dynamic>>[];
    
    try {
      // Calculate minimum data needed
      int minDataDays = periodDays + 100;
      for (final condition in rule.conditions) {
        if (condition.type == RuleConditionType.event52WeekHighCrossover) {
          minDataDays = periodDays + 280;
        } else if (condition.type == RuleConditionType.momentum6Month || 
                   condition.type == RuleConditionType.stateMomentumPositive ||
                   condition.type == RuleConditionType.eventMomentumCrossover) {
          if (minDataDays < periodDays + 150) minDataDays = periodDays + 150;
        }
      }
      
      // Fetch historical data
      final priceData = await ApiService.fetchHistoricalPricesAndVolumes(symbol, days: minDataDays);
      final prices = (priceData['prices'])?.map((p) => (p as num).toDouble()).toList() ?? [];
      final volumes = (priceData['volumes'])?.map((v) => (v as num).toInt()).toList() ?? [];
      
      if (prices.isEmpty || prices.length < 30) {
        return {'signals': [], 'stats': {}, 'error': 'Insufficient price data'};
      }
      
      final currentPrice = prices.last;
      final effectivePeriod = periodDays > (prices.length - 30) ? (prices.length - 30) : periodDays;
      
      // Track oldest signal only
      Map<String, dynamic>? oldestSignal;
      int oldestDayOffset = 0;
      
      // Test each day in the period
      for (int dayOffset = 1; dayOffset <= effectivePeriod; dayOffset++) {
        final dataEndIndex = prices.length - dayOffset;
        if (dataEndIndex < 30) continue;
        
        final historicalPrices = prices.sublist(0, dataEndIndex);
        final historicalVolumes = volumes.length >= prices.length 
          ? volumes.sublist(0, dataEndIndex) 
          : <int>[];
        
        final priceAtSignal = historicalPrices.last;
        final prevClose = historicalPrices.length > 1 ? historicalPrices[historicalPrices.length - 2] : priceAtSignal;
        
        final lookbackFor52Week = historicalPrices.length > 252 
          ? historicalPrices.sublist(historicalPrices.length - 252) 
          : historicalPrices;
        final weekHigh52 = lookbackFor52Week.reduce((a, b) => a > b ? a : b);
        final weekLow52 = lookbackFor52Week.reduce((a, b) => a < b ? a : b);
        
        double avgVolume = 0;
        int volumeAtSignal = 0;
        if (historicalVolumes.length >= 20) {
          final recentVolumes = historicalVolumes.sublist(historicalVolumes.length - 20);
          avgVolume = recentVolumes.reduce((a, b) => a + b) / recentVolumes.length;
          volumeAtSignal = historicalVolumes.last;
        }
        
        final changeAtSignal = priceAtSignal - prevClose;
        final changePercentAtSignal = prevClose > 0 ? (changeAtSignal / prevClose) * 100 : 0.0;
        
        final enrichedMock = await TechnicalIndicatorsService.addIndicators(
          Stock(
            symbol: symbol,
            name: _stockCache[symbol]?.name ?? symbol.replaceAll('.AX', ''),
            currentPrice: priceAtSignal,
            previousClose: prevClose,
            change: changeAtSignal,
            changePercent: changePercentAtSignal,
            volume: volumeAtSignal,
            marketCap: 0,
            lastUpdate: DateTime.now().subtract(Duration(days: dayOffset)),
            weekHigh52: weekHigh52,
            weekLow52: weekLow52,
            avgVolume: avgVolume,
          ),
          historicalPrices,
        );
        
        final passed = ScanEngineService.isHybridRule(rule)
          ? ScanEngineService.evaluateHybridRule(enrichedMock, rule, prices: historicalPrices, volumes: historicalVolumes)
          : ScanEngineService.evaluateRule(enrichedMock, rule, prices: historicalPrices, volumes: historicalVolumes);
        
        if (passed) {
          // Calculate returns
          final returns = <String, double>{};
          for (final holdDays in [1, 3, 7]) {
            if (dayOffset >= holdDays) {
              final exitIndex = dataEndIndex + holdDays - 1;
              if (exitIndex < prices.length) {
                final exitPrice = prices[exitIndex];
                returns['${holdDays}d'] = ((exitPrice - priceAtSignal) / priceAtSignal) * 100;
              }
            }
          }
          returns['toToday'] = ((currentPrice - priceAtSignal) / priceAtSignal) * 100;
          
          final signal = {
            'symbol': symbol,
            'signalDate': DateTime.now().subtract(Duration(days: dayOffset)).toIso8601String(),
            'daysAgo': dayOffset,
            'priceAtSignal': priceAtSignal,
            'currentPrice': currentPrice,
            'returns': returns,
            'changePercent': returns['toToday'],
          };
          
          // Keep oldest signal
          if (oldestSignal == null || dayOffset > oldestDayOffset) {
            oldestSignal = signal;
            oldestDayOffset = dayOffset;
          }
          
          // Also add to list for display
          signals.add(signal);
        }
      }
      
      // Calculate stats if we have signals
      final stats = signals.isNotEmpty ? _calculateBacktestStats(signals) : {};
      
      return {
        'signals': signals,
        'stats': stats,
        'oldestSignal': oldestSignal,
      };
    } catch (e) {
      return {'signals': [], 'stats': {}, 'error': e.toString()};
    }
  }

  /// Get stock data - always fetches fresh data unless useCached is true
  Future<Stock?> getStock(String symbol, {bool useCached = false}) async {
    // Only use cache if explicitly requested AND cache exists AND is recent (< 1 min)
    if (useCached && _stockCache.containsKey(symbol)) {
      final cached = _stockCache[symbol]!;
      final age = DateTime.now().difference(cached.lastUpdate).inSeconds;
      if (age < 60) return cached;
    }
    
    // Always fetch fresh data
    final stock = await ApiService.fetchStock(symbol);
    if (stock != null) {
      final priceData = await ApiService.fetchHistoricalPricesAndVolumes(symbol);
      final prices = (priceData['prices'])?.map((p) => (p as num).toDouble()).toList() ?? [];
      final highs = (priceData['highs'])?.map((h) => (h as num).toDouble()).toList();
      final lows = (priceData['lows'])?.map((l) => (l as num).toDouble()).toList();
      final enriched = await TechnicalIndicatorsService.addIndicators(stock, prices, highs: highs, lows: lows);
      _stockCache[symbol] = enriched;
      await StorageService.saveStockCache(_stockCache);
      return enriched;
    }
    return _stockCache[symbol]; // Fallback to cache if API fails
  }

  Future<List<Map<String, dynamic>>> getChartData(String symbol, String range) async {
    String interval;
    String apiRange;
    switch (range) {
      case '1D': interval = '5m'; apiRange = '1d'; break;
      case '1W': interval = '30m'; apiRange = '5d'; break;
      case '1M': interval = '1d'; apiRange = '1mo'; break;
      case '3M': interval = '1d'; apiRange = '3mo'; break;
      case '1Y': interval = '1wk'; apiRange = '1y'; break;
      case 'ALL': interval = '1mo'; apiRange = 'max'; break;
      default: interval = '1d'; apiRange = '1mo';
    }
    return ApiService.fetchHistoricalData(symbol, range: apiRange, interval: interval);
  }

  bool canRunBacktest() => _subscription?.canRunBacktest() ?? false;

  /// Rolling Window Backtest - tests rule on EVERY day in the period
  /// Returns Map with signals, stats, uniqueStocks, totalSignals
  Future<Map<String, dynamic>> backtestRule(
    ScanRule rule, {
    int periodDays = 14,
    void Function(Map<String, dynamic> result)? onResultFound,
  }) async {
    await _subscription?.recordBacktest();
    
    final signals = <Map<String, dynamic>>[];
    final stockSignals = <String, List<Map<String, dynamic>>>{};
    
    _scanStatus = 'Backtesting ${rule.name}...';
    _isScanning = true;
    notifyListeners();
    
    await BackgroundTaskService.startScanTask(
      taskName: 'Backtest: ${rule.name}',
      totalStocks: ApiService.allAsxSymbolsDynamic.length,
    );
    
    // Calculate minimum data needed based on rule conditions
    int minDataDays = periodDays + 60;
    for (final condition in rule.conditions) {
      switch (condition.type) {
        case RuleConditionType.momentum6Month:
        case RuleConditionType.stateMomentumPositive:
          if (minDataDays < periodDays + 150) minDataDays = periodDays + 150;
          break;
        case RuleConditionType.momentum12Month:
          if (minDataDays < periodDays + 280) minDataDays = periodDays + 280;
          break;
        case RuleConditionType.event52WeekHighCrossover:
          // Need 252 days for 52-week high + period + buffer
          if (minDataDays < periodDays + 260) minDataDays = periodDays + 260;
          break;
        case RuleConditionType.eventMomentumCrossover:
          // Need 128 days for 6-month momentum + period + buffer
          if (minDataDays < periodDays + 150) minDataDays = periodDays + 150;
          break;
        case RuleConditionType.eventVolumeBreakout:
        case RuleConditionType.stateVolumeExpanding:
          if (minDataDays < periodDays + 50) minDataDays = periodDays + 50;
          break;
        case RuleConditionType.priceAboveSma:
        case RuleConditionType.priceBelowSma:
        case RuleConditionType.stateAboveSma50:
          final smaPeriod = condition.type == RuleConditionType.stateAboveSma50 ? 50 : condition.value.toInt();
          if (periodDays + smaPeriod + 30 > minDataDays) {
            minDataDays = periodDays + smaPeriod + 30;
          }
          break;
        default:
          break;
      }
    }
    
    // Ensure we have enough data for longer backtests
    if (minDataDays < periodDays + 100) {
      minDataDays = periodDays + 100;
    }
    
    print('DEBUG BACKTEST: periodDays=$periodDays, minDataDays=$minDataDays');
    
    final symbolsToTest = <String>{};
    symbolsToTest.addAll(_stockCache.keys);
    symbolsToTest.addAll(ApiService.allAsxSymbolsDynamic);
    
    int processed = 0;
    int totalSignalCount = 0;
    final totalSymbols = symbolsToTest.length;
    
    for (final symbol in symbolsToTest) {
      if (!_isScanning) break;
      
      processed++;
      if (processed % 50 == 0) {
        _scanStatus = 'Scanning $processed/$totalSymbols • $totalSignalCount signals';
        notifyListeners();
        
        await BackgroundTaskService.updateProgress(
          taskName: 'Backtest: ${rule.name}',
          current: processed,
          total: totalSymbols,
          matches: totalSignalCount,
        );
      }
      
      try {
        final priceData = await ApiService.fetchHistoricalPricesAndVolumes(symbol, days: minDataDays);
        final prices = (priceData['prices'])?.map((p) => (p as num).toDouble()).toList() ?? [];
        final volumes = (priceData['volumes'])?.map((v) => (v as num).toInt()).toList() ?? [];
        
        // Need at least 30 days of data
        if (prices.isEmpty || prices.length < 30) continue;
        
        // For longer periods, adjust to available data
        final effectivePeriod = periodDays > (prices.length - 30) ? (prices.length - 30) : periodDays;
        if (effectivePeriod < 1) continue;
        
        final currentPrice = prices.last;
        
        // Calculate avg volume for filter (use current as initial check, 
        // but re-check with historical data per signal date below)
        double avgVolumeForFilter = 0;
        if (volumes.length >= 20) {
          avgVolumeForFilter = volumes.sublist(volumes.length - 20).reduce((a, b) => a + b) / 20;
        }
        
        // Quick pre-filter: skip stocks that have NEVER been in the price range
        // (uses current data for speed, individual signal dates re-checked below)
        final minHistPrice = prices.reduce((a, b) => a < b ? a : b);
        final maxHistPrice = prices.reduce((a, b) => a > b ? a : b);
        if (_scanFilters.enabled) {
          if (_scanFilters.minPrice != null && maxHistPrice < _scanFilters.minPrice!) continue;
          if (_scanFilters.maxPrice != null && minHistPrice > _scanFilters.maxPrice!) continue;
        }
        
        // Track if this stock already has a signal (we want OLDEST only)
        bool stockAlreadySignaled = false;
        Map<String, dynamic>? oldestSignal;
        int oldestDayOffset = 0;
        
        // Test EVERY day in the effective period (rolling window)
        // We iterate through all days to find the OLDEST signal
        for (int dayOffset = 1; dayOffset <= effectivePeriod; dayOffset++) {
          if (!_isScanning) break;
          
          final dataEndIndex = prices.length - dayOffset;
          if (dataEndIndex < 30) continue;
          
          final historicalPrices = prices.sublist(0, dataEndIndex);
          final historicalVolumes = volumes.length >= prices.length 
            ? volumes.sublist(0, dataEndIndex) 
            : <int>[];
          
          final priceAtSignal = historicalPrices.last;
          final prevClose = historicalPrices.length > 1 ? historicalPrices[historicalPrices.length - 2] : priceAtSignal;
          
          final lookbackFor52Week = historicalPrices.length > 252 
            ? historicalPrices.sublist(historicalPrices.length - 252) 
            : historicalPrices;
          final weekHigh52 = lookbackFor52Week.reduce((a, b) => a > b ? a : b);
          final weekLow52 = lookbackFor52Week.reduce((a, b) => a < b ? a : b);
          
          double avgVolume = 0;
          int volumeAtSignal = 0;
          if (historicalVolumes.length >= 20) {
            final recentVolumes = historicalVolumes.sublist(historicalVolumes.length - 20);
            avgVolume = recentVolumes.reduce((a, b) => a + b) / recentVolumes.length;
            volumeAtSignal = historicalVolumes.last;
          }
          
          // Fix look-ahead bias: apply filters at the signal date, not current date
          if (!_scanFilters.passesFilters(
            currentPrice: priceAtSignal,
            avgVolume: avgVolume,
            historicalPrices: historicalPrices,
          )) {
            continue; // Would not have passed filters at this date
          }
          
          final changeAtSignal = priceAtSignal - prevClose;
          final changePercentAtSignal = prevClose > 0 ? (changeAtSignal / prevClose) * 100 : 0.0;
          
          final enrichedMock = await TechnicalIndicatorsService.addIndicators(
            Stock(
              symbol: symbol,
              name: _stockCache[symbol]?.name ?? symbol.replaceAll('.AX', ''),
              currentPrice: priceAtSignal,
              previousClose: prevClose,
              change: changeAtSignal,
              changePercent: changePercentAtSignal,
              volume: volumeAtSignal,
              marketCap: 0,
              lastUpdate: DateTime.now().subtract(Duration(days: dayOffset)),
              weekHigh52: weekHigh52,
              weekLow52: weekLow52,
              avgVolume: avgVolume,
            ),
            historicalPrices,
          );
          
          // Use hybrid evaluation if rule has both events and state filters
          // This ensures EVENT triggers while STATE filters are just validated
          final passed = ScanEngineService.isHybridRule(rule)
            ? ScanEngineService.evaluateHybridRule(enrichedMock, rule, prices: historicalPrices, volumes: historicalVolumes)
            : ScanEngineService.evaluateRule(enrichedMock, rule, prices: historicalPrices, volumes: historicalVolumes);
          
          if (passed) {
            // Calculate returns at different holding periods
            final returns = <String, double>{};
            for (final holdDays in [1, 3, 7]) {
              if (dayOffset >= holdDays) {
                final exitIndex = dataEndIndex + holdDays - 1;
                if (exitIndex < prices.length) {
                  final exitPrice = prices[exitIndex];
                  returns['${holdDays}d'] = ((exitPrice - priceAtSignal) / priceAtSignal) * 100;
                }
              }
            }
            returns['toToday'] = ((currentPrice - priceAtSignal) / priceAtSignal) * 100;
            
            // Check if in watchlist
            final inWatchlist = watchlist.any((w) => w.symbol == symbol);
            final watchlistItem = inWatchlist ? watchlist.firstWhere((w) => w.symbol == symbol) : null;
            
            final signal = {
              'symbol': symbol,
              'name': _stockCache[symbol]?.name ?? symbol.replaceAll('.AX', ''),
              'signalDate': DateTime.now().subtract(Duration(days: dayOffset)).toIso8601String(),
              'daysAgo': dayOffset,
              'priceAtSignal': priceAtSignal,
              'currentPrice': currentPrice,
              'returns': returns,
              'changePercent': returns['toToday'],
              'holdingDays': dayOffset,
              'matchedRules': [rule.name], // Single rule backtest
              'inWatchlist': inWatchlist,
              'watchlistTriggerRule': watchlistItem?.triggerRule,
            };
            
            // Keep only the OLDEST signal (highest dayOffset) for this stock
            // This prevents the same stock from skewing stats with multiple hits
            if (!stockAlreadySignaled || dayOffset > oldestDayOffset) {
              oldestSignal = signal;
              oldestDayOffset = dayOffset;
              stockAlreadySignaled = true;
            }
          }
        }
        
        // After checking all days, add only the oldest signal for this stock
        if (oldestSignal != null) {
          totalSignalCount++;
          signals.add(oldestSignal);
          stockSignals.putIfAbsent(symbol, () => []);
          stockSignals[symbol]!.add(oldestSignal);
          onResultFound?.call(oldestSignal);
        }
      } catch (e) {
        // Skip errors
      }
      
      if (processed % 10 == 0) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
    
    // Calculate stats
    final stats = _calculateBacktestStats(signals);
    
    signals.sort((a, b) => ((b['changePercent'] as double?) ?? 0).compareTo((a['changePercent'] as double?) ?? 0));
    _scanStatus = 'Complete: $totalSignalCount signals from ${stockSignals.length} stocks';
    _isScanning = false;
    
    // Show completion notification
    await BackgroundTaskService.completeTask(
      taskName: 'Backtest: ${rule.name}',
      matches: totalSignalCount,
      uniqueStocks: stockSignals.length,
    );
    
    // Cache the toToday stats for inline win-rate badges on rules screen
    if (stats.containsKey('holdingPeriods')) {
      final hp = stats['holdingPeriods'];
      if (hp is Map && hp.containsKey('toToday')) {
        final todayStats = hp['toToday'];
        if (todayStats is Map) {
          _ruleBacktestStats[rule.id] = Map<String, dynamic>.from(todayStats);
        }
      }
    }
    
    notifyListeners();
    HapticFeedback.mediumImpact();
    
    return {
      'signals': signals,
      'stats': stats,
      'uniqueStocks': stockSignals.length,
      'totalSignals': totalSignalCount,
      'periodDays': periodDays,
      'ruleName': rule.name,
    };
  }
  
  /// Calculate aggregate statistics for backtest results  
  /// Calculate aggregate statistics for backtest results
  /// Uses proper Sharpe ratio: (annualized return - risk free rate) / annualized stddev
  /// Australian risk-free rate approximation (RBA cash rate ~4.35% as of 2024)
  static const double _riskFreeRateAnnual = 0.0435; // 4.35% annual
  
  Map<String, dynamic> _calculateBacktestStats(List<Map<String, dynamic>> signals) {
    if (signals.isEmpty) {
      return {'holdingPeriods': {}, 'totalSignals': 0};
    }
    
    final holdingPeriods = <String, List<double>>{};
    
    for (final signal in signals) {
      final returns = signal['returns'] as Map<String, double>? ?? {};
      for (final entry in returns.entries) {
        holdingPeriods.putIfAbsent(entry.key, () => []);
        holdingPeriods[entry.key]!.add(entry.value);
      }
    }
    
    // Trading days per year for annualization
    const tradingDaysPerYear = 252.0;
    
    // Map holding period keys to approximate trading days
    const periodToDays = <String, double>{
      '1d': 1,
      '3d': 3,
      '7d': 5, // 7 calendar days ≈ 5 trading days
      'toToday': 0, // Variable - computed per signal below
    };
    
    final periodStats = <String, Map<String, dynamic>>{};
    
    for (final period in ['1d', '3d', '7d', 'toToday']) {
      final returns = holdingPeriods[period] ?? [];
      if (returns.isEmpty) continue;
      
      final avgReturn = returns.reduce((a, b) => a + b) / returns.length;
      final winners = returns.where((r) => r > 0).length;
      final winRate = winners / returns.length * 100;
      final losers = returns.where((r) => r < 0).length;
      
      // Median return
      final sortedReturns = List<double>.from(returns)..sort();
      final median = sortedReturns.length.isOdd
          ? sortedReturns[sortedReturns.length ~/ 2]
          : (sortedReturns[sortedReturns.length ~/ 2 - 1] + sortedReturns[sortedReturns.length ~/ 2]) / 2;
      
      // Max drawdown (worst single-trade loss)
      final maxLoss = sortedReturns.first;
      final maxGain = sortedReturns.last;
      
      // Sample standard deviation (N-1)
      final mean = avgReturn;
      final squaredDiffs = returns.map((r) => (r - mean) * (r - mean));
      final variance = returns.length > 1 
          ? squaredDiffs.reduce((a, b) => a + b) / (returns.length - 1)
          : 0.0;
      final stdDev = variance > 0 ? sqrt(variance) : 0.0;
      
      // Annualized Sharpe ratio per holding period
      double sharpe = 0;
      if (stdDev > 0) {
        double holdingDays;
        if (period == 'toToday') {
          // Average holding days from signals
          double totalDays = 0;
          int count = 0;
          for (final signal in signals) {
            final daysAgo = signal['daysAgo'] as int? ?? signal['holdingDays'] as int? ?? 14;
            totalDays += daysAgo;
            count++;
          }
          holdingDays = count > 0 ? totalDays / count : 14;
        } else {
          holdingDays = periodToDays[period] ?? 1;
        }
        
        // Annualize: scale factor = sqrt(tradingDaysPerYear / holdingDays)
        final annualizationFactor = holdingDays > 0 ? tradingDaysPerYear / holdingDays : tradingDaysPerYear;
        final annualizedReturn = avgReturn / 100 * annualizationFactor; // Convert % to decimal, annualize
        final annualizedStdDev = (stdDev / 100) * sqrt(annualizationFactor);
        
        // Sharpe = (annualized return - risk free rate) / annualized stddev
        sharpe = annualizedStdDev > 0 
            ? (annualizedReturn - _riskFreeRateAnnual) / annualizedStdDev 
            : 0;
      }
      
      // Profit factor = sum of gains / sum of losses
      final totalGains = returns.where((r) => r > 0).fold(0.0, (sum, r) => sum + r);
      final totalLosses = returns.where((r) => r < 0).fold(0.0, (sum, r) => sum + r.abs());
      final profitFactor = totalLosses > 0 ? totalGains / totalLosses : totalGains > 0 ? double.infinity : 0.0;
      
      periodStats[period] = {
        'avgReturn': avgReturn,
        'medianReturn': median,
        'winRate': winRate,
        'sharpe': sharpe,
        'stdDev': stdDev,
        'maxLoss': maxLoss,
        'maxGain': maxGain,
        'profitFactor': profitFactor,
        'count': returns.length,
        'winners': winners,
        'losers': losers,
      };
    }
    
    return {'holdingPeriods': periodStats, 'totalSignals': signals.length};
  }
  /// Unified rolling window backtest for single or multiple rules
  /// Tests rules on EVERY day in the period, with multiple holding period analysis
  Future<Map<String, dynamic>> backtestRules(
    List<ScanRule> rules, {
    int periodDays = 14,
    bool useAndLogic = true,
    void Function(Map<String, dynamic> result)? onResultFound,
  }) async {
    if (rules.isEmpty) return {'signals': [], 'stats': {}, 'uniqueStocks': 0, 'totalSignals': 0};
    
    // Single rule optimization
    if (rules.length == 1) {
      return backtestRule(rules.first, periodDays: periodDays, onResultFound: onResultFound);
    }
    
    await _subscription?.recordBacktest();
    
    final signals = <Map<String, dynamic>>[];
    final stockSignals = <String, List<Map<String, dynamic>>>{};
    
    final ruleNames = rules.map((r) => r.name).join(useAndLogic ? ' AND ' : ' OR ');
    _scanStatus = 'Backtesting $ruleNames...';
    _isScanning = true;
    notifyListeners();
    
    await BackgroundTaskService.startScanTask(
      taskName: 'Backtest: ${rules.length} rules',
      totalStocks: ApiService.allAsxSymbolsDynamic.length,
    );
    
    // Calculate minimum data needed based on all rule conditions
    int minDataDays = periodDays + 60;
    for (final rule in rules) {
      for (final condition in rule.conditions) {
        switch (condition.type) {
          case RuleConditionType.momentum6Month:
          case RuleConditionType.stateMomentumPositive:
            if (minDataDays < periodDays + 150) minDataDays = periodDays + 150;
            break;
          case RuleConditionType.momentum12Month:
            if (minDataDays < periodDays + 280) minDataDays = periodDays + 280;
            break;
          case RuleConditionType.event52WeekHighCrossover:
            if (minDataDays < periodDays + 260) minDataDays = periodDays + 260;
            break;
          case RuleConditionType.eventMomentumCrossover:
            if (minDataDays < periodDays + 150) minDataDays = periodDays + 150;
            break;
          case RuleConditionType.eventVolumeBreakout:
          case RuleConditionType.stateVolumeExpanding:
            if (minDataDays < periodDays + 50) minDataDays = periodDays + 50;
            break;
          case RuleConditionType.priceAboveSma:
          case RuleConditionType.priceBelowSma:
          case RuleConditionType.stateAboveSma50:
            final smaPeriod = condition.type == RuleConditionType.stateAboveSma50 ? 50 : condition.value.toInt();
            if (periodDays + smaPeriod + 30 > minDataDays) {
              minDataDays = periodDays + smaPeriod + 30;
            }
            break;
          default:
            break;
        }
      }
    }
    
    // Ensure enough data for longer backtests
    if (minDataDays < periodDays + 100) {
      minDataDays = periodDays + 100;
    }
    
    print('DEBUG MULTI-BACKTEST: periodDays=$periodDays, minDataDays=$minDataDays');
    
    final symbolsToTest = <String>{};
    symbolsToTest.addAll(_stockCache.keys);
    symbolsToTest.addAll(ApiService.allAsxSymbolsDynamic);
    
    int processed = 0;
    int totalSignalCount = 0;
    final totalSymbols = symbolsToTest.length;
    
    for (final symbol in symbolsToTest) {
      if (!_isScanning) break;
      
      processed++;
      if (processed % 50 == 0) {
        _scanStatus = 'Scanning $processed/$totalSymbols • $totalSignalCount signals';
        notifyListeners();
        
        await BackgroundTaskService.updateProgress(
          taskName: 'Backtest: ${rules.length} rules',
          current: processed,
          total: totalSymbols,
          matches: totalSignalCount,
        );
      }
      
      try {
        final priceData = await ApiService.fetchHistoricalPricesAndVolumes(symbol, days: minDataDays);
        final prices = (priceData['prices'])?.map((p) => (p as num).toDouble()).toList() ?? [];
        final volumes = (priceData['volumes'])?.map((v) => (v as num).toInt()).toList() ?? [];
        
        // Need at least 30 days of data
        if (prices.isEmpty || prices.length < 30) continue;
        
        // For longer periods, adjust to available data
        final effectivePeriodMulti = periodDays > (prices.length - 30) ? (prices.length - 30) : periodDays;
        if (effectivePeriodMulti < 1) continue;
        
        final currentPrice = prices.last;
        
        // Calculate avg volume for filter (quick pre-check only)
        double avgVolumeForFilterMulti = 0;
        if (volumes.length >= 20) {
          avgVolumeForFilterMulti = volumes.sublist(volumes.length - 20).reduce((a, b) => a + b) / 20;
        }
        
        // Quick pre-filter: skip stocks that have NEVER been in the price range
        final minHistPriceMulti = prices.reduce((a, b) => a < b ? a : b);
        final maxHistPriceMulti = prices.reduce((a, b) => a > b ? a : b);
        if (_scanFilters.enabled) {
          if (_scanFilters.minPrice != null && maxHistPriceMulti < _scanFilters.minPrice!) continue;
          if (_scanFilters.maxPrice != null && minHistPriceMulti > _scanFilters.maxPrice!) continue;
        }
        
        // Track oldest signal and all rules matched across all days
        Map<String, dynamic>? oldestSignalMulti;
        int oldestDayOffsetMulti = 0;
        final allMatchedRulesForStock = <String>{};
        
        // Test EVERY day in the effective period (rolling window)
        for (int dayOffset = 1; dayOffset <= effectivePeriodMulti; dayOffset++) {
          if (!_isScanning) break;
          
          final dataEndIndex = prices.length - dayOffset;
          if (dataEndIndex < 30) continue;
          
          final historicalPrices = prices.sublist(0, dataEndIndex);
          final historicalVolumes = volumes.length >= prices.length 
            ? volumes.sublist(0, dataEndIndex) 
            : <int>[];
          
          final priceAtSignal = historicalPrices.last;
          final prevClose = historicalPrices.length > 1 ? historicalPrices[historicalPrices.length - 2] : priceAtSignal;
          
          final lookbackFor52Week = historicalPrices.length > 252 
            ? historicalPrices.sublist(historicalPrices.length - 252) 
            : historicalPrices;
          final weekHigh52 = lookbackFor52Week.reduce((a, b) => a > b ? a : b);
          final weekLow52 = lookbackFor52Week.reduce((a, b) => a < b ? a : b);
          
          double avgVolume = 0;
          int volumeAtSignal = 0;
          if (historicalVolumes.length >= 20) {
            final recentVolumes = historicalVolumes.sublist(historicalVolumes.length - 20);
            avgVolume = recentVolumes.reduce((a, b) => a + b) / recentVolumes.length;
            volumeAtSignal = historicalVolumes.last;
          }
          
          // Fix look-ahead bias: apply filters at the signal date, not current date
          if (!_scanFilters.passesFilters(
            currentPrice: priceAtSignal,
            avgVolume: avgVolume,
            historicalPrices: historicalPrices,
          )) {
            continue; // Would not have passed filters at this date
          }
          
          final changeAtSignal = priceAtSignal - prevClose;
          final changePercentAtSignal = prevClose > 0 ? (changeAtSignal / prevClose) * 100 : 0.0;
          
          final enrichedMock = await TechnicalIndicatorsService.addIndicators(
            Stock(
              symbol: symbol,
              name: _stockCache[symbol]?.name ?? symbol.replaceAll('.AX', ''),
              currentPrice: priceAtSignal,
              previousClose: prevClose,
              change: changeAtSignal,
              changePercent: changePercentAtSignal,
              volume: volumeAtSignal,
              marketCap: 0,
              lastUpdate: DateTime.now().subtract(Duration(days: dayOffset)),
              weekHigh52: weekHigh52,
              weekLow52: weekLow52,
              avgVolume: avgVolume,
            ),
            historicalPrices,
          );
          
          // Test each rule (use hybrid evaluation for rules with events + state filters)
          final matchedRulesThisDay = <String>[];
          for (final rule in rules) {
            final passed = ScanEngineService.isHybridRule(rule)
              ? ScanEngineService.evaluateHybridRule(enrichedMock, rule, prices: historicalPrices, volumes: historicalVolumes)
              : ScanEngineService.evaluateRule(enrichedMock, rule, prices: historicalPrices, volumes: historicalVolumes);
            
            if (passed) {
              matchedRulesThisDay.add(rule.name);
              allMatchedRulesForStock.add(rule.name); // Track all rules ever matched
            }
          }
          
          // Apply AND/OR logic
          final passes = useAndLogic 
            ? matchedRulesThisDay.length == rules.length  // AND: must match ALL
            : matchedRulesThisDay.isNotEmpty;              // OR: must match at least ONE
          
          if (passes) {
            // Calculate returns at different holding periods
            final returns = <String, double>{};
            for (final holdDays in [1, 3, 7]) {
              if (dayOffset >= holdDays) {
                final exitIndex = dataEndIndex + holdDays - 1;
                if (exitIndex < prices.length) {
                  final exitPrice = prices[exitIndex];
                  returns['${holdDays}d'] = ((exitPrice - priceAtSignal) / priceAtSignal) * 100;
                }
              }
            }
            returns['toToday'] = ((currentPrice - priceAtSignal) / priceAtSignal) * 100;
            
            // Check if in watchlist
            final inWatchlist = watchlist.any((w) => w.symbol == symbol);
            final watchlistItem = inWatchlist ? watchlist.firstWhere((w) => w.symbol == symbol) : null;
            
            final signal = {
              'symbol': symbol,
              'name': _stockCache[symbol]?.name ?? symbol.replaceAll('.AX', ''),
              'signalDate': DateTime.now().subtract(Duration(days: dayOffset)).toIso8601String(),
              'daysAgo': dayOffset,
              'priceAtSignal': priceAtSignal,
              'currentPrice': currentPrice,
              'returns': returns,
              'changePercent': returns['toToday'],
              'holdingDays': dayOffset,
              'matchedRules': matchedRulesThisDay,
              'inWatchlist': inWatchlist,
              'watchlistTriggerRule': watchlistItem?.triggerRule,
            };
            
            // Keep only the OLDEST signal (highest dayOffset) for this stock
            if (oldestSignalMulti == null || dayOffset > oldestDayOffsetMulti) {
              oldestSignalMulti = signal;
              oldestDayOffsetMulti = dayOffset;
            }
          }
        }
        
        // After checking all days, add only the oldest signal with ALL matched rules
        if (oldestSignalMulti != null) {
          // Update matchedRules to include ALL rules that ever matched for this stock
          oldestSignalMulti['matchedRules'] = allMatchedRulesForStock.toList();
          
          totalSignalCount++;
          signals.add(oldestSignalMulti);
          stockSignals.putIfAbsent(symbol, () => []);
          stockSignals[symbol]!.add(oldestSignalMulti);
          onResultFound?.call(oldestSignalMulti);
        }
      } catch (e) {
        // Skip errors
      }
      
      if (processed % 10 == 0) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
    
    // Calculate statistics
    final stats = _calculateBacktestStats(signals);
    
    // Sort by return to today
    signals.sort((a, b) => ((b['changePercent'] as double?) ?? 0).compareTo((a['changePercent'] as double?) ?? 0));
    
    _scanStatus = 'Complete: $totalSignalCount signals from ${stockSignals.length} stocks';
    _isScanning = false;
    
    // Show completion notification
    await BackgroundTaskService.completeTask(
      taskName: 'Multi-Rule Backtest',
      matches: totalSignalCount,
      uniqueStocks: stockSignals.length,
    );
    
    notifyListeners();
    HapticFeedback.mediumImpact();
    
    return {
      'signals': signals,
      'stats': stats,
      'uniqueStocks': stockSignals.length,
      'totalSignals': totalSignalCount,
      'periodDays': periodDays,
    };
  }
}
