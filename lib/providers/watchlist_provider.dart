import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../models/stock.dart';

/// Watchlist item with price tracking
class WatchlistItem {
  final String symbol;
  final String name;
  final double addedPrice;
  final DateTime addedAt;
  double? currentPrice;
  double? priceChange;
  double? priceChangePercent;

  WatchlistItem({
    required this.symbol,
    required this.name,
    required this.addedPrice,
    required this.addedAt,
    this.currentPrice,
    this.priceChange,
    this.priceChangePercent,
  });

  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'name': name,
    'addedPrice': addedPrice,
    'addedAt': addedAt.toIso8601String(),
  };

  factory WatchlistItem.fromJson(Map<String, dynamic> json) => WatchlistItem(
    symbol: json['symbol'],
    name: json['name'],
    addedPrice: (json['addedPrice'] ?? 0.0).toDouble(),
    addedAt: DateTime.tryParse(json['addedAt'] ?? '') ?? DateTime.now(),
  );

  WatchlistItem copyWith({
    double? currentPrice,
    double? priceChange,
    double? priceChangePercent,
  }) {
    return WatchlistItem(
      symbol: symbol,
      name: name,
      addedPrice: addedPrice,
      addedAt: addedAt,
      currentPrice: currentPrice ?? this.currentPrice,
      priceChange: priceChange ?? this.priceChange,
      priceChangePercent: priceChangePercent ?? this.priceChangePercent,
    );
  }

  /// Calculate change since added to watchlist
  void updateCurrentPrice(double price) {
    currentPrice = price;
    priceChange = price - addedPrice;
    priceChangePercent = addedPrice > 0 ? ((price - addedPrice) / addedPrice) * 100 : 0;
  }
}

class WatchlistProvider with ChangeNotifier {
  List<WatchlistItem> _watchlist = [];
  bool _isLoading = false;
  
  List<WatchlistItem> get watchlist => _watchlist;
  List<String> get watchlistSymbols => _watchlist.map((w) => w.symbol).toList();
  bool get isLoading => _isLoading;
  
  WatchlistProvider() {
    loadWatchlist();
  }

  Future<void> loadWatchlist() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final watchlistJson = prefs.getString('watchlist_items');
      
      if (watchlistJson != null) {
        final List<dynamic> items = json.decode(watchlistJson);
        _watchlist = items.map((item) => WatchlistItem.fromJson(item)).toList();
      }
      
      // Refresh current prices
      await refreshPrices();
    } catch (e) {
      print('Error loading watchlist: $e');
    }
    
    _isLoading = false;
    notifyListeners();
  }
  
  Future<void> _saveWatchlist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final watchlistJson = json.encode(_watchlist.map((w) => w.toJson()).toList());
      await prefs.setString('watchlist_items', watchlistJson);
    } catch (e) {
      print('Error saving watchlist: $e');
    }
  }
  
  Future<void> addToWatchlist(String symbol, String name, {double? currentPrice}) async {
    if (isInWatchlist(symbol)) return;
    
    // Get current price if not provided
    double price = currentPrice ?? 0;
    if (price == 0) {
      try {
        final stock = await ApiService.fetchStock(symbol);
        price = stock?.currentPrice ?? 0;
      } catch (_) {}
    }
    
    final item = WatchlistItem(
      symbol: symbol,
      name: name,
      addedPrice: price,
      addedAt: DateTime.now(),
      currentPrice: price,
      priceChange: 0,
      priceChangePercent: 0,
    );
    
    _watchlist.add(item);
    await _saveWatchlist();
    notifyListeners();
  }
  
  Future<void> removeFromWatchlist(String symbol) async {
    _watchlist.removeWhere((w) => w.symbol == symbol);
    await _saveWatchlist();
    notifyListeners();
  }
  
  bool isInWatchlist(String symbol) {
    return _watchlist.any((w) => w.symbol == symbol);
  }
  
  Future<void> toggleWatchlist(String symbol, String name, {double? currentPrice}) async {
    if (isInWatchlist(symbol)) {
      await removeFromWatchlist(symbol);
    } else {
      await addToWatchlist(symbol, name, currentPrice: currentPrice);
    }
  }
  
  WatchlistItem? getWatchlistItem(String symbol) {
    try {
      return _watchlist.firstWhere((w) => w.symbol == symbol);
    } catch (_) {
      return null;
    }
  }
  
  /// Refresh current prices for all watchlist items
  Future<void> refreshPrices() async {
    if (_watchlist.isEmpty) return;
    
    for (int i = 0; i < _watchlist.length; i++) {
      try {
        final stock = await ApiService.fetchStock(_watchlist[i].symbol);
        if (stock != null) {
          _watchlist[i].updateCurrentPrice(stock.currentPrice);
        }
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        print('Error refreshing ${_watchlist[i].symbol}: $e');
      }
    }
    notifyListeners();
  }
  
  /// Update a single watchlist item with stock data
  void updateFromStock(Stock stock) {
    final index = _watchlist.indexWhere((w) => w.symbol == stock.symbol);
    if (index != -1) {
      _watchlist[index].updateCurrentPrice(stock.currentPrice);
      notifyListeners();
    }
  }
  
  /// Get watchlist sorted by performance since added
  List<WatchlistItem> get sortedByPerformance {
    final sorted = List<WatchlistItem>.from(_watchlist);
    sorted.sort((a, b) => (b.priceChangePercent ?? 0).compareTo(a.priceChangePercent ?? 0));
    return sorted;
  }
  
  /// Get total portfolio stats
  Map<String, double> get portfolioStats {
    double totalValue = 0;
    double totalCost = 0;
    int winners = 0;
    int losers = 0;
    
    for (final item in _watchlist) {
      if (item.currentPrice != null) {
        totalValue += item.currentPrice!;
        totalCost += item.addedPrice;
        if ((item.priceChangePercent ?? 0) > 0) {
          winners++;
        } else if ((item.priceChangePercent ?? 0) < 0) {
          losers++;
        }
      }
    }
    
    return {
      'totalValue': totalValue,
      'totalCost': totalCost,
      'totalChange': totalValue - totalCost,
      'totalChangePercent': totalCost > 0 ? ((totalValue - totalCost) / totalCost) * 100 : 0,
      'winners': winners.toDouble(),
      'losers': losers.toDouble(),
    };
  }
}