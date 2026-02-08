import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Scan result with matched rule info
class ScanResult {
  final Stock stock;
  final String ruleId;
  final String ruleName;
  final DateTime matchedAt;

  ScanResult({required this.stock, required this.ruleId, required this.ruleName, required this.matchedAt});
}

class AppProvider with ChangeNotifier {
  Map<String, Stock> _stockCache = {};
  List<WatchlistItem> _watchlist = [];
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
  bool _includeDividends = false;
  ScanFilters _scanFilters = ScanFilters.defaultFilters;

  Map<String, Stock> get stockCache => _stockCache;
  List<WatchlistItem> get watchlist => _watchlist;
  List<ScanRule> get rules => _rules;
  List<ScanRule> get activeRules => _rules.where((r) => r.isActive).toList();
  List<Map<String, dynamic>> get alerts => _alerts;
  List<ScanResult> get scanResults => _scanResults;
  bool get isLoading => _isLoading;
  bool get isScanning => _isScanning;
  String get scanStatus => _scanStatus;
  int get scanProgress => _scanProgress;
  int get scanTotal => _scanTotal;
  int get validStocksFound => _validStocksFound;
  String? get error => _error;
  DateTime? get lastRefresh => _lastRefresh;
  int get unreadAlertCount => _alerts.where((a) => a['isRead'] != true).length;
  SubscriptionService? get subscription => _subscription;
  bool get includeDividends => _includeDividends;
  ScanFilters get scanFilters => _scanFilters;
  
  void updateScanFilters(ScanFilters filters) {
    _scanFilters = filters;
    notifyListeners();
  }

  double get portfolioValue => _watchlist.fold(0, (sum, item) => sum + (item.currentPrice ?? item.addedPrice));
  double get portfolioGainLoss => _watchlist.fold(0.0, (sum, item) => sum + item.dollarGainLoss);
  double get portfolioGainLossPercent {
    double totalCost = _watchlist.fold(0, (sum, item) => sum + item.addedPrice);
    return totalCost == 0 ? 0 : portfolioGainLoss / totalCost * 100;
  }
  int get winnersCount => _watchlist.where((w) => w.gainLossPercent > 0).length;
  int get losersCount => _watchlist.where((w) => w.gainLossPercent < 0).length;

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
      _watchlist = await StorageService.loadWatchlist();
      _rules = await StorageService.loadRules();
      _alerts = await StorageService.loadAlerts();
      _stockCache = await StorageService.loadStockCache();
      _lastRefresh = await StorageService.getCacheTime();
      
      // Load settings
      final settings = await StorageService.loadSettings();
      _includeDividends = settings['includeDividends'] ?? false;
      
      await ApiService.initializeValidSymbols();
      if (_stockCache.isEmpty) {
        await refreshData();
      } else {
        await _updateWatchlistPrices();
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
      await _updateWatchlistPrices();
    } catch (e) { _error = e.toString(); }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _updateWatchlistPrices() async {
    if (_watchlist.isEmpty) return;
    
    // Always fetch fresh prices for all watchlist items
    final symbols = _watchlist.map((w) => w.symbol).toList();
    
    try {
      // Fetch all watchlist stocks in one batch call
      final stocks = await ApiService.fetchStocks(symbols);
      
      for (final stock in stocks) {
        // Update cache with fresh data
        _stockCache[stock.symbol] = stock;
        
        // Update watchlist item
        final index = _watchlist.indexWhere((w) => w.symbol == stock.symbol);
        if (index != -1) {
          _watchlist[index].updatePrice(stock.currentPrice, change: stock.change, changePercent: stock.changePercent);
        }
      }
    } catch (e) {
      // Fallback: fetch individually if batch fails
      for (int i = 0; i < _watchlist.length; i++) {
        try {
          final stock = await ApiService.fetchStock(_watchlist[i].symbol);
          if (stock != null) {
            _watchlist[i].updatePrice(stock.currentPrice, change: stock.change, changePercent: stock.changePercent);
            _stockCache[stock.symbol] = stock;
          }
        } catch (_) {}
      }
    }
    
    await StorageService.saveWatchlist(_watchlist);
    await StorageService.saveStockCache(_stockCache);
    notifyListeners();
  }

  bool canAddToWatchlist() => _subscription?.canAddToWatchlist(_watchlist.length) ?? true;

  int get remainingWatchlistSlots {
    if (_subscription?.isPro ?? false) return -1;
    return SubscriptionService.freeMaxWatchlist - _watchlist.length;
  }

  /// Add stock to watchlist - simulates purchase at current price
  /// Pro users can set custom capital, free users get $10,000 default
  Future<void> addToWatchlist(String symbol, String name, double price, {double? customCapital, String? triggerRule, List<String>? triggerRules}) async {
    if (_watchlist.any((w) => w.symbol == symbol)) return;
    
    // Only Pro users can set custom capital
    final capital = (_subscription?.isPro ?? false) && customCapital != null 
      ? customCapital 
      : 10000.0;
    
    _watchlist.add(WatchlistItem(
      symbol: symbol, 
      name: name, 
      addedPrice: price, 
      addedAt: DateTime.now(), 
      currentPrice: price,
      capitalInvested: capital,
      triggerRule: triggerRule,
      triggerRules: triggerRules,
    ));
    await StorageService.saveWatchlist(_watchlist);
    notifyListeners();
  }

  Future<void> removeFromWatchlist(String symbol) async {
    _watchlist.removeWhere((w) => w.symbol == symbol);
    await StorageService.saveWatchlist(_watchlist);
    notifyListeners();
  }

  /// Update capital invested for a watchlist item (Pro only)
  Future<void> updateWatchlistCapital(String symbol, double newCapital) async {
    if (!(_subscription?.isPro ?? false)) return;
    
    final index = _watchlist.indexWhere((w) => w.symbol == symbol);
    if (index != -1) {
      _watchlist[index] = _watchlist[index].copyWith(capitalInvested: newCapital);
      await StorageService.saveWatchlist(_watchlist);
      notifyListeners();
    }
  }

  /// Toggle include dividends in returns (Pro only)
  Future<void> toggleDividends() async {
    if (!(_subscription?.isPro ?? false)) return;
    
    _includeDividends = !_includeDividends;
    await StorageService.saveSettings({'includeDividends': _includeDividends});
    notifyListeners();
  }

  bool isInWatchlist(String symbol) => _watchlist.any((w) => w.symbol == symbol);

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
          
          // Apply scan filters first (before expensive rule evaluation)
          List<double>? pricesForFilter;
          if (_scanFilters.enabled && _scanFilters.maxSingleDayGap != null) {
            // Need price history for gap check
            final priceData = await ApiService.fetchHistoricalPricesAndVolumes(stock.symbol, days: 10);
            pricesForFilter = (priceData['prices'])?.map((p) => (p as num).toDouble()).toList();
          }
          
          if (!_scanFilters.passesFilters(
            currentPrice: stock.currentPrice,
            avgVolume: stock.avgVolume,
            historicalPrices: pricesForFilter,
          )) {
            continue; // Skip this stock - doesn't pass filters
          }

          // Check each rule
          for (final rule in usableActiveRules) {
            List<double>? prices = pricesForFilter;
            List<int>? volumes;
            
            // Check if rule needs historical data
            final needsHistoricalData = !ScanEngineService.canQuickEvaluate(rule);
            final needsVolumeData = rule.conditions.any((c) => 
              c.type == RuleConditionType.stateVolumeExpanding ||
              c.type == RuleConditionType.eventVolumeBreakout ||
              c.type == RuleConditionType.volumeSpike ||
              c.type == RuleConditionType.stealthAccumulation
            );
            final needsLongHistory = rule.conditions.any((c) =>
              c.type == RuleConditionType.event52WeekHighCrossover ||
              c.type == RuleConditionType.eventMomentumCrossover ||
              c.type == RuleConditionType.stateMomentumPositive ||
              c.type == RuleConditionType.stateNear52WeekHigh ||
              c.type == RuleConditionType.momentum6Month
            );
            
            if (needsHistoricalData || needsVolumeData || needsLongHistory) {
              // Fetch historical prices and volumes
              final days = needsLongHistory ? 280 : 100;
              final priceData = await ApiService.fetchHistoricalPricesAndVolumes(stock.symbol, days: days);
              prices = (priceData['prices'])?.map((p) => (p as num).toDouble()).toList();
              volumes = (priceData['volumes'])?.map((v) => (v as num).toInt()).toList();
            }

            Stock enrichedStock = stock;
            if (prices != null && prices.isNotEmpty) {
              enrichedStock = await TechnicalIndicatorsService.addIndicators(stock, prices);
              _stockCache[stock.symbol] = enrichedStock;
            }

            // Use hybrid evaluation for rules with events + state filters
            final passed = ScanEngineService.isHybridRule(rule)
              ? ScanEngineService.evaluateHybridRule(enrichedStock, rule, prices: prices, volumes: volumes)
              : ScanEngineService.evaluateRule(enrichedStock, rule, prices: prices, volumes: volumes);
            
            if (passed) {
              // Check if already matched (by different rule)
              if (!_scanResults.any((r) => r.stock.symbol == stock.symbol)) {
                _scanResults.add(ScanResult(
                  stock: enrichedStock,
                  ruleId: rule.id,
                  ruleName: rule.name,
                  matchedAt: DateTime.now(),
                ));
                await _createAlert(enrichedStock, rule);
              }
              break; // Only count first matching rule
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
    
    // Stop background task
    await BackgroundTaskService.stopTask();
    
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
      final prices = await ApiService.fetchHistoricalPrices(symbol);
      final enriched = await TechnicalIndicatorsService.addIndicators(stock, prices);
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
        
        // Calculate avg volume for filter
        double avgVolumeForFilter = 0;
        if (volumes.length >= 20) {
          avgVolumeForFilter = volumes.sublist(volumes.length - 20).reduce((a, b) => a + b) / 20;
        }
        
        // Apply scan filters
        if (!_scanFilters.passesFilters(
          currentPrice: currentPrice,
          avgVolume: avgVolumeForFilter,
          historicalPrices: prices,
        )) {
          continue; // Skip this stock - doesn't pass filters
        }
        
        // Test EVERY day in the effective period (rolling window)
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
            totalSignalCount++;
            
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
            final inWatchlist = _watchlist.any((w) => w.symbol == symbol);
            final watchlistItem = inWatchlist ? _watchlist.firstWhere((w) => w.symbol == symbol) : null;
            
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
            
            signals.add(signal);
            stockSignals.putIfAbsent(symbol, () => []);
            stockSignals[symbol]!.add(signal);
            
            onResultFound?.call(signal);
          }
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
    
    await BackgroundTaskService.stopTask();
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
    
    final periodStats = <String, Map<String, dynamic>>{};
    
    for (final period in ['1d', '3d', '7d', 'toToday']) {
      final returns = holdingPeriods[period] ?? [];
      if (returns.isEmpty) continue;
      
      final avgReturn = returns.reduce((a, b) => a + b) / returns.length;
      final winners = returns.where((r) => r > 0).length;
      final winRate = winners / returns.length * 100;
      
      final mean = avgReturn;
      final squaredDiffs = returns.map((r) => (r - mean) * (r - mean));
      final variance = squaredDiffs.reduce((a, b) => a + b) / returns.length;
      final stdDev = variance > 0 ? sqrt(variance) : 1;
      final sharpe = stdDev > 0 ? avgReturn / stdDev : 0;
      
      periodStats[period] = {
        'avgReturn': avgReturn,
        'winRate': winRate,
        'sharpe': sharpe,
        'count': returns.length,
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
        
        // Calculate avg volume for filter
        double avgVolumeForFilterMulti = 0;
        if (volumes.length >= 20) {
          avgVolumeForFilterMulti = volumes.sublist(volumes.length - 20).reduce((a, b) => a + b) / 20;
        }
        
        // Apply scan filters
        if (!_scanFilters.passesFilters(
          currentPrice: currentPrice,
          avgVolume: avgVolumeForFilterMulti,
          historicalPrices: prices,
        )) {
          continue; // Skip this stock - doesn't pass filters
        }
        
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
          final matchedRules = <String>[];
          for (final rule in rules) {
            final passed = ScanEngineService.isHybridRule(rule)
              ? ScanEngineService.evaluateHybridRule(enrichedMock, rule, prices: historicalPrices, volumes: historicalVolumes)
              : ScanEngineService.evaluateRule(enrichedMock, rule, prices: historicalPrices, volumes: historicalVolumes);
            
            if (passed) {
              matchedRules.add(rule.name);
            }
          }
          
          // Apply AND/OR logic
          final passes = useAndLogic 
            ? matchedRules.length == rules.length  // AND: must match ALL
            : matchedRules.isNotEmpty;              // OR: must match at least ONE
          
          if (passes) {
            totalSignalCount++;
            
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
            final inWatchlist = _watchlist.any((w) => w.symbol == symbol);
            final watchlistItem = inWatchlist ? _watchlist.firstWhere((w) => w.symbol == symbol) : null;
            
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
              'matchedRules': matchedRules,
              'inWatchlist': inWatchlist,
              'watchlistTriggerRule': watchlistItem?.triggerRule,
            };
            
            signals.add(signal);
            stockSignals.putIfAbsent(symbol, () => []);
            stockSignals[symbol]!.add(signal);
            
            onResultFound?.call(signal);
          }
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
    
    await BackgroundTaskService.stopTask();
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