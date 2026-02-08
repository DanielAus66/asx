import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Subscription tiers
enum SubscriptionTier {
  free,
  pro,
  proPlus,
}

/// Feature flags for gating
enum ProFeature {
  unlimitedRules,
  customRules,
  fullAsxScan,
  unlimitedWatchlist,
  unlimitedBacktests,
  realTimeAlerts,
  exportResults,
  noAds,
  aiSuggestions,
  multiplePortfolios,
  emailAlerts,
}

/// Subscription plan details
class SubscriptionPlan {
  final SubscriptionTier tier;
  final String name;
  final String description;
  final double monthlyPrice;
  final double yearlyPrice;
  final List<String> features;
  final String? badge;

  const SubscriptionPlan({
    required this.tier,
    required this.name,
    required this.description,
    required this.monthlyPrice,
    required this.yearlyPrice,
    required this.features,
    this.badge,
  });

  double get yearlySavings => ((monthlyPrice * 12) - yearlyPrice) / (monthlyPrice * 12) * 100;
  double get monthlyEquivalent => yearlyPrice / 12;
}

/// Subscription service to manage user subscription state
class SubscriptionService with ChangeNotifier {
  static const String _tierKey = 'subscription_tier';
  static const String _expiryKey = 'subscription_expiry';
  static const String _backtestCountKey = 'daily_backtest_count';
  static const String _backtestDateKey = 'backtest_date';

  SubscriptionTier _currentTier = SubscriptionTier.free;
  DateTime? _expiryDate;
  int _dailyBacktestCount = 0;
  String _lastBacktestDate = '';

  // Limits for free tier
  static const int freeMaxRules = 2;
  static const int freeMaxWatchlist = 5;
  static const int freeMaxBacktestsPerDay = 1;
  static const List<String> freeRuleIds = ['oversold_rsi', 'volume_breakout', 'near_52_low'];

  SubscriptionTier get currentTier => _currentTier;
  bool get isPro => _currentTier == SubscriptionTier.pro || _currentTier == SubscriptionTier.proPlus;
  bool get isProPlus => _currentTier == SubscriptionTier.proPlus;
  bool get isFree => _currentTier == SubscriptionTier.free;
  DateTime? get expiryDate => _expiryDate;
  int get dailyBacktestCount => _dailyBacktestCount;

  // Available plans
  static const List<SubscriptionPlan> plans = [
    SubscriptionPlan(
      tier: SubscriptionTier.free,
      name: 'Free',
      description: 'Get started with basic scanning',
      monthlyPrice: 0,
      yearlyPrice: 0,
      features: [
        '2 pre-built scan rules',
        'Quick scan (20 stocks)',
        'Watchlist (max 5 stocks)',
        '1 backtest per day',
        'Basic charts',
      ],
    ),
    SubscriptionPlan(
      tier: SubscriptionTier.pro,
      name: 'Pro',
      description: 'Full power for serious traders',
      monthlyPrice: 7.99,
      yearlyPrice: 49.99,
      badge: 'POPULAR',
      features: [
        'All 6+ pre-built rules',
        'Create custom rules',
        'Full ASX scan (17,000+ symbols)',
        'Unlimited watchlist',
        'Unlimited backtesting',
        'Real-time alerts',
        'Export results',
        'No ads',
      ],
    ),
    SubscriptionPlan(
      tier: SubscriptionTier.proPlus,
      name: 'Pro+',
      description: 'For professional traders',
      monthlyPrice: 14.99,
      yearlyPrice: 99.99,
      badge: 'BEST VALUE',
      features: [
        'Everything in Pro',
        'AI-suggested rules',
        'Alert performance tracking',
        'Multiple portfolios',
        'Email & SMS alerts',
        'Priority support',
      ],
    ),
  ];

  /// Initialize subscription service
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    
    final tierIndex = prefs.getInt(_tierKey) ?? 0;
    _currentTier = SubscriptionTier.values[tierIndex];
    
    final expiryMillis = prefs.getInt(_expiryKey);
    if (expiryMillis != null) {
      _expiryDate = DateTime.fromMillisecondsSinceEpoch(expiryMillis);
      
      // Check if subscription has expired
      if (_expiryDate!.isBefore(DateTime.now())) {
        _currentTier = SubscriptionTier.free;
        _expiryDate = null;
        await _saveTier();
      }
    }
    
    // Load daily backtest count
    _lastBacktestDate = prefs.getString(_backtestDateKey) ?? '';
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (_lastBacktestDate != today) {
      _dailyBacktestCount = 0;
      _lastBacktestDate = today;
    } else {
      _dailyBacktestCount = prefs.getInt(_backtestCountKey) ?? 0;
    }
    
    notifyListeners();
  }

  /// Check if a feature is available
  bool hasFeature(ProFeature feature) {
    switch (feature) {
      case ProFeature.unlimitedRules:
      case ProFeature.customRules:
      case ProFeature.fullAsxScan:
      case ProFeature.unlimitedWatchlist:
      case ProFeature.unlimitedBacktests:
      case ProFeature.realTimeAlerts:
      case ProFeature.exportResults:
      case ProFeature.noAds:
        return isPro;
      case ProFeature.aiSuggestions:
      case ProFeature.multiplePortfolios:
      case ProFeature.emailAlerts:
        return isProPlus;
    }
  }

  /// Check if user can use a specific rule
  bool canUseRule(String ruleId) {
    if (isPro) return true;
    return freeRuleIds.contains(ruleId);
  }

  /// Check if user can add more watchlist items
  bool canAddToWatchlist(int currentCount) {
    if (isPro) return true;
    return currentCount < freeMaxWatchlist;
  }

  /// Check if user can run a backtest today
  bool canRunBacktest() {
    if (isPro) return true;
    return _dailyBacktestCount < freeMaxBacktestsPerDay;
  }

  /// Record a backtest usage
  Future<void> recordBacktest() async {
    if (isPro) return;
    
    _dailyBacktestCount++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_backtestCountKey, _dailyBacktestCount);
    await prefs.setString(_backtestDateKey, _lastBacktestDate);
    notifyListeners();
  }

  /// Get remaining backtests for free users
  int get remainingBacktests {
    if (isPro) return -1; // Unlimited
    return freeMaxBacktestsPerDay - _dailyBacktestCount;
  }

  /// Upgrade subscription (mock - would connect to IAP)
  Future<bool> upgradeTo(SubscriptionTier tier, {bool yearly = true}) async {
    // In real app, this would:
    // 1. Launch in-app purchase flow
    // 2. Verify receipt with server
    // 3. Update subscription status
    
    // For now, mock the upgrade
    _currentTier = tier;
    _expiryDate = DateTime.now().add(Duration(days: yearly ? 365 : 30));
    
    await _saveTier();
    notifyListeners();
    return true;
  }

  /// Restore purchases
  Future<bool> restorePurchases() async {
    // In real app, this would verify with app store
    // For now, just check stored tier
    await initialize();
    return isPro;
  }

  /// Cancel subscription
  Future<void> cancelSubscription() async {
    // In real app, this would redirect to app store subscription management
    // Subscription remains active until expiry date
  }

  Future<void> _saveTier() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_tierKey, _currentTier.index);
    if (_expiryDate != null) {
      await prefs.setInt(_expiryKey, _expiryDate!.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_expiryKey);
    }
  }

  /// Get the plan details for a tier
  static SubscriptionPlan getPlan(SubscriptionTier tier) {
    return plans.firstWhere((p) => p.tier == tier);
  }

  /// Format price for display
  static String formatPrice(double price) {
    if (price == 0) return 'Free';
    return '\$${price.toStringAsFixed(2)}';
  }
}
