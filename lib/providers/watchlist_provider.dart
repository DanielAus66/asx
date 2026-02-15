import 'package:flutter/material.dart';
import '../models/watchlist_item.dart';
import '../models/stock.dart';
import '../services/storage_service.dart';
import '../services/api_service.dart';
import '../services/subscription_service.dart';
import '../services/error_reporting_service.dart';

/// Mixin providing watchlist functionality
/// Extracted from AppProvider to separate concerns
mixin WatchlistProviderMixin on ChangeNotifier {
  List<WatchlistItem> _watchlistItems = [];
  bool _includeDividendsFlag = false;
  
  // These must be provided by the host class
  Map<String, Stock> get stockCache;
  SubscriptionService? get subscription;
  
  List<WatchlistItem> get watchlist => _watchlistItems;
  bool get includeDividends => _includeDividendsFlag;
  set includeDividendsValue(bool val) => _includeDividendsFlag = val;
  
  double get portfolioValue => _watchlistItems.fold(0, (sum, item) => sum + (item.currentPrice ?? item.addedPrice));
  double get portfolioGainLoss => _watchlistItems.fold(0.0, (sum, item) => sum + item.dollarGainLoss);
  double get portfolioGainLossPercent {
    double totalCost = _watchlistItems.fold(0, (sum, item) => sum + item.addedPrice);
    return totalCost > 0 ? (portfolioGainLoss / totalCost) * 100 : 0;
  }
  int get winnersCount => _watchlistItems.where((w) => w.gainLossPercent > 0).length;
  int get losersCount => _watchlistItems.where((w) => w.gainLossPercent < 0).length;

  bool canAddToWatchlist() => subscription?.canAddToWatchlist(_watchlistItems.length) ?? true;
  int get remainingWatchlistSlots {
    final max = SubscriptionService.freeMaxWatchlist;
    return max - _watchlistItems.length;
  }
  bool isInWatchlist(String symbol) => _watchlistItems.any((w) => w.symbol == symbol);

  Future<void> initWatchlist() async {
    _watchlistItems = await StorageService.loadWatchlist();
  }

  Future<void> addToWatchlist(String symbol, String name, double price, {
    double? customCapital, String? triggerRule, List<String>? triggerRules,
  }) async {
    if (_watchlistItems.any((w) => w.symbol == symbol)) return;
    final item = WatchlistItem(
      symbol: symbol,
      name: name,
      addedPrice: price,
      addedAt: DateTime.now(),
      capitalInvested: customCapital ?? 10000.0,
      triggerRule: triggerRule,
      triggerRules: triggerRules,
    );
    _watchlistItems.add(item);
    await StorageService.saveWatchlist(_watchlistItems);
    notifyListeners();
  }

  Future<void> removeFromWatchlist(String symbol) async {
    _watchlistItems.removeWhere((w) => w.symbol == symbol);
    await StorageService.saveWatchlist(_watchlistItems);
    notifyListeners();
  }

  Future<void> updateWatchlistCapital(String symbol, double newCapital) async {
    final idx = _watchlistItems.indexWhere((w) => w.symbol == symbol);
    if (idx >= 0) {
      _watchlistItems[idx] = _watchlistItems[idx].copyWith(capitalInvested: newCapital);
      await StorageService.saveWatchlist(_watchlistItems);
      notifyListeners();
    }
  }

  Future<void> toggleDividends() async {
    _includeDividendsFlag = !_includeDividendsFlag;
    await StorageService.saveSettings({'includeDividends': _includeDividendsFlag});
    notifyListeners();
  }

  Future<void> updateWatchlistPrices() async {
    if (_watchlistItems.isEmpty) return;
    final symbols = _watchlistItems.map((w) => w.symbol).toList();
    
    for (int i = 0; i < symbols.length; i += 10) {
      final batch = symbols.sublist(i, (i + 10).clamp(0, symbols.length));
      try {
        final stocks = await ApiService.fetchStocks(batch);
        for (final stock in stocks) {
          final idx = _watchlistItems.indexWhere((w) => w.symbol == stock.symbol);
          if (idx >= 0) {
            _watchlistItems[idx].updatePrice(stock.currentPrice, change: stock.change, changePercent: stock.changePercent);
          }
        }
      } catch (e, st) {
        ErrorReportingService.reportApiError(e, endpoint: 'watchlist_batch_update', stackTrace: st);
      }
    }
    
    for (int i = 0; i < _watchlistItems.length; i++) {
      if (_watchlistItems[i].currentPrice == null) {
        try {
          final stock = await ApiService.fetchStock(_watchlistItems[i].symbol);
          if (stock != null) {
            _watchlistItems[i].updatePrice(stock.currentPrice, change: stock.change, changePercent: stock.changePercent);
          }
        } catch (e, st) {
          ErrorReportingService.reportApiError(e, endpoint: 'watchlist_price_update', stackTrace: st);
        }
      }
    }
  }
}
