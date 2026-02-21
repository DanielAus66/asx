import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/marketplace_strategy.dart';
import '../models/scan_rule.dart';

/// Manages the Strategy Marketplace — subscriptions, published strategies, revenue tracking.
/// 
/// In production: replace mock data with Firebase/Supabase calls.
/// Local state (subscribed IDs, published IDs) is persisted via SharedPreferences.
class MarketplaceService with ChangeNotifier {
  static const String _subscribedKey = 'marketplace_subscribed_ids';
  static const String _ratingsKey = 'marketplace_user_ratings';
  static const String _publishedKey = 'marketplace_published_strategies';

  // IDs the current user is subscribed to
  Set<String> _subscribedIds = {};
  // strategyId -> rating the current user gave (1-5)
  Map<String, double> _userRatings = {};

  // Strategies the current user has published (stored locally until backend)
  List<MarketplaceStrategy> _publishedStrategies = [];

  bool _isLoading = false;

  Set<String> get subscribedIds => Set.unmodifiable(_subscribedIds);
  List<MarketplaceStrategy> get publishedStrategies => List.unmodifiable(_publishedStrategies);
  bool get isLoading => _isLoading;

  /// All marketplace strategies (mock data + user-published)
  List<MarketplaceStrategy> get allStrategies => [
    ...mockMarketplaceStrategies,
    ..._publishedStrategies,
  ];

  List<MarketplaceStrategy> get featuredStrategies =>
      allStrategies.where((s) => s.isFeatured).toList();

  List<MarketplaceStrategy> get trendingStrategies {
    final sorted = [...allStrategies];
    sorted.sort((a, b) => b.subscriberCount.compareTo(a.subscriberCount));
    return sorted.take(10).toList();
  }

  List<MarketplaceStrategy> get subscribedStrategies =>
      allStrategies.where((s) => _subscribedIds.contains(s.id)).toList();

  /// Strategies by category
  List<MarketplaceStrategy> byCategory(StrategyCategory category) =>
      allStrategies.where((s) => s.category == category).toList();

  /// Free strategies (always accessible)
  List<MarketplaceStrategy> get freeStrategies =>
      allStrategies.where((s) => s.isFree).toList();

  bool isSubscribed(String strategyId) => _subscribedIds.contains(strategyId);

  double? userRatingFor(String strategyId) => _userRatings[strategyId];

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final subscribedJson = prefs.getStringList(_subscribedKey) ?? [];
      _subscribedIds = subscribedJson.toSet();
      final ratingsJson = prefs.getString(_ratingsKey);
      if (ratingsJson != null) {
        try {
          final map = jsonDecode(ratingsJson) as Map<String, dynamic>;
          _userRatings = map.map((k, v) => MapEntry(k, (v as num).toDouble()));
        } catch (_) {}
      }

      final publishedJson = prefs.getStringList(_publishedKey) ?? [];
      // In production: fetch from backend. For now, just restore IDs.
      _publishedStrategies = []; // Would deserialize from JSON
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
  }

  /// Subscribe to a strategy (free or after payment flow)
  Future<bool> subscribe(String strategyId) async {
    _subscribedIds.add(strategyId);
    notifyListeners();
    await _persistSubscriptions();
    return true;
  }

  /// Unsubscribe from a strategy
  Future<void> unsubscribe(String strategyId) async {
    _subscribedIds.remove(strategyId);
    notifyListeners();
    await _persistSubscriptions();
  }

  /// Publish a new strategy (Pro feature)
  /// Returns the published strategy on success
  Future<MarketplaceStrategy?> publishStrategy({
    required String title,
    required String description,
    required String longDescription,
    required List<ScanRule> rules,
    required StrategyCategory category,
    required PricingModel pricing,
    double? monthlyPrice,
    required List<String> tags,
    required String publisherName,
    required String publisherHandle,
  }) async {
    final strategy = MarketplaceStrategy(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      description: description,
      longDescription: longDescription,
      rules: rules,
      publisherId: 'current_user',
      publisherName: publisherName,
      publisherHandle: publisherHandle,
      publisherAvatarInitials: publisherName.isNotEmpty
          ? publisherName.substring(0, 1).toUpperCase()
          : '?',
      category: category,
      pricing: pricing,
      monthlyPrice: monthlyPrice,
      subscriberCount: 0,
      averageRating: 0,
      ratingCount: 0,
      publishedAt: DateTime.now(),
      lastUpdated: DateTime.now(),
      tags: tags,
    );

    _publishedStrategies.add(strategy);
    notifyListeners();
    await _persistPublished();
    return strategy;
  }

  /// Rate a strategy (1–5 stars). Locally stored; in production sync to backend.
  Future<void> rateStrategy(String strategyId, double rating) async {
    _userRatings[strategyId] = rating;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_ratingsKey, jsonEncode(_userRatings));
    } catch (_) {}
  }

  Future<void> _persistSubscriptions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_subscribedKey, _subscribedIds.toList());
    } catch (_) {}
  }

  Future<void> _persistPublished() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Simplified: just store IDs for now
      await prefs.setStringList(
        _publishedKey,
        _publishedStrategies.map((s) => s.id).toList(),
      );
    } catch (_) {}
  }

  /// Revenue stats for the current user's published strategies
  /// In production: comes from backend
  Map<String, dynamic> get revenueStats {
    final totalSubs = _publishedStrategies.fold<int>(0, (sum, s) => sum + s.subscriberCount);
    final paidSubs = _publishedStrategies
        .where((s) => !s.isFree)
        .fold<int>(0, (sum, s) => sum + s.subscriberCount);
    final grossMrr = _publishedStrategies
        .where((s) => !s.isFree)
        .fold<double>(0, (sum, s) => sum + (s.monthlyPrice ?? 0) * s.subscriberCount);
    const revenueSharePct = 0.70; // 70% to creator
    return {
      'totalSubscribers': totalSubs,
      'paidSubscribers': paidSubs,
      'grossMrr': grossMrr,
      'creatorMrr': grossMrr * revenueSharePct,
      'publishedCount': _publishedStrategies.length,
    };
  }
}
