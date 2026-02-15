import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/stock.dart';
import '../models/watchlist_item.dart';
import '../models/scan_rule.dart';
import '../models/holding.dart';
import 'database_service.dart';
import 'error_reporting_service.dart';

/// Storage service that delegates to SQLite (DatabaseService) for large data
/// and SharedPreferences for small settings.
/// 
/// On first launch after update, migrates existing SharedPreferences data to SQLite.
class StorageService {
  static bool _initialized = false;
  static bool _useSqlite = false;

  /// Initialize storage - tries SQLite, falls back to SharedPreferences
  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      await DatabaseService.initialize();
      _useSqlite = true;
      // Run migration if needed
      final didMigrate = await DatabaseService.migrateFromSharedPreferences();
      if (didMigrate) {
        await _migrateData();
      }
    } catch (e, st) {
      ErrorReportingService.report(e, stackTrace: st, context: 'StorageService.initialize - falling back to SharedPreferences', category: ErrorCategory.storage);
      _useSqlite = false;
    }
    _initialized = true;
  }

  /// Migrate data from SharedPreferences to SQLite
  static Future<void> _migrateData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Migrate watchlist
      final watchlistJson = prefs.getString('watchlist_v2');
      if (watchlistJson != null) {
        final items = (jsonDecode(watchlistJson) as List).map((e) => WatchlistItem.fromJson(e)).toList();
        await DatabaseService.saveWatchlist(items);
      }
      
      // Migrate rules
      final rulesJson = prefs.getString('scan_rules_v2');
      if (rulesJson != null) {
        final rules = (jsonDecode(rulesJson) as List).map((e) => ScanRule.fromJson(e)).toList();
        await DatabaseService.saveRules(rules);
      }
      
      // Migrate alerts
      final alertsJson = prefs.getString('alerts_v2');
      if (alertsJson != null) {
        final alerts = (jsonDecode(alertsJson) as List).cast<Map<String, dynamic>>();
        await DatabaseService.saveAlerts(alerts);
      }
      
      // Migrate holdings
      final holdingsJson = prefs.getString('holdings_v1');
      if (holdingsJson != null) {
        final holdings = (jsonDecode(holdingsJson) as List).map((e) => Holding.fromJson(e)).toList();
        await DatabaseService.saveHoldings(holdings);
      }
      
      print('StorageService: Migrated SharedPreferences data to SQLite');
    } catch (e, st) {
      ErrorReportingService.report(e, stackTrace: st, context: 'StorageService._migrateData', category: ErrorCategory.storage);
    }
  }

  // === WATCHLIST ===
  
  static Future<List<WatchlistItem>> loadWatchlist() async {
    if (_useSqlite) return DatabaseService.loadWatchlist();
    return _loadWatchlistFromPrefs();
  }

  static Future<void> saveWatchlist(List<WatchlistItem> items) async {
    if (_useSqlite) return DatabaseService.saveWatchlist(items);
    return _saveWatchlistToPrefs(items);
  }

  // === RULES ===
  
  static Future<List<ScanRule>> loadRules() async {
    if (_useSqlite) return DatabaseService.loadRules();
    return _loadRulesFromPrefs();
  }

  static Future<void> saveRules(List<ScanRule> rules) async {
    if (_useSqlite) return DatabaseService.saveRules(rules);
    return _saveRulesToPrefs(rules);
  }

  // === ALERTS ===
  
  static Future<List<Map<String, dynamic>>> loadAlerts() async {
    if (_useSqlite) return DatabaseService.loadAlerts();
    return _loadAlertsFromPrefs();
  }

  static Future<void> saveAlerts(List<Map<String, dynamic>> alerts) async {
    if (_useSqlite) return DatabaseService.saveAlerts(alerts);
    return _saveAlertsToPrefs(alerts);
  }

  static Future<void> addAlert(Map<String, dynamic> alert) async {
    if (_useSqlite) return DatabaseService.addAlert(alert);
    final alerts = await loadAlerts();
    alerts.insert(0, alert);
    if (alerts.length > 100) alerts.removeRange(100, alerts.length);
    await saveAlerts(alerts);
  }

  // === STOCK CACHE ===
  
  static Future<Map<String, Stock>> loadStockCache() async {
    if (_useSqlite) return DatabaseService.loadStockCache();
    return _loadStockCacheFromPrefs();
  }

  static Future<void> saveStockCache(Map<String, Stock> stocks) async {
    if (_useSqlite) return DatabaseService.saveStockCache(stocks);
    return _saveStockCacheToPrefs(stocks);
  }

  static Future<DateTime?> getCacheTime() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheTimeStr = prefs.getString('cache_time_v2');
    if (cacheTimeStr == null) return null;
    return DateTime.parse(cacheTimeStr);
  }

  // === HOLDINGS ===
  
  static Future<List<Holding>> loadHoldings() async {
    if (_useSqlite) return DatabaseService.loadHoldings();
    return _loadHoldingsFromPrefs();
  }

  static Future<void> saveHoldings(List<Holding> holdings) async {
    if (_useSqlite) return DatabaseService.saveHoldings(holdings);
    return _saveHoldingsToPrefs(holdings);
  }

  // === SETTINGS (always SharedPreferences - small data) ===
  
  static Future<Map<String, dynamic>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('app_settings_v1');
    if (json == null) return {};
    try { return jsonDecode(json) as Map<String, dynamic>; } catch (e) { return {}; }
  }

  static Future<void> saveSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadSettings();
    existing.addAll(settings);
    await prefs.setString('app_settings_v1', jsonEncode(existing));
  }

  // === USER NAME (always SharedPreferences) ===
  
  static Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name_v1');
    return (name != null && name.isNotEmpty) ? name : null;
  }

  static Future<void> saveUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name_v1', name);
  }

  // === CLEAR ===
  
  static Future<void> clearAll() async {
    if (_useSqlite) {
      await DatabaseService.clearAll();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('watchlist_v2');
    await prefs.remove('scan_rules_v2');
    await prefs.remove('alerts_v2');
    await prefs.remove('stock_cache_v2');
    await prefs.remove('cache_time_v2');
  }

  // ===========================================================
  // SharedPreferences fallback implementations (kept for safety)
  // ===========================================================

  static Future<List<WatchlistItem>> _loadWatchlistFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('watchlist_v2');
    if (json == null) return [];
    try { return (jsonDecode(json) as List).map((e) => WatchlistItem.fromJson(e)).toList(); }
    catch (e) { return []; }
  }

  static Future<void> _saveWatchlistToPrefs(List<WatchlistItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('watchlist_v2', jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  static Future<List<ScanRule>> _loadRulesFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('scan_rules_v2');
    if (json == null) { await _saveRulesToPrefs(defaultRules); return defaultRules; }
    try {
      final rules = (jsonDecode(json) as List).map((e) => ScanRule.fromJson(e)).toList();
      for (final d in defaultRules) { if (!rules.any((r) => r.id == d.id)) rules.add(d); }
      return rules;
    } catch (e) { return defaultRules; }
  }

  static Future<void> _saveRulesToPrefs(List<ScanRule> rules) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('scan_rules_v2', jsonEncode(rules.map((e) => e.toJson()).toList()));
  }

  static Future<List<Map<String, dynamic>>> _loadAlertsFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('alerts_v2');
    if (json == null) return [];
    try { return (jsonDecode(json) as List).cast<Map<String, dynamic>>(); } catch (e) { return []; }
  }

  static Future<void> _saveAlertsToPrefs(List<Map<String, dynamic>> alerts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alerts_v2', jsonEncode(alerts));
  }

  static Future<Map<String, Stock>> _loadStockCacheFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('stock_cache_v2');
    final cacheTimeStr = prefs.getString('cache_time_v2');
    if (json == null || cacheTimeStr == null) return {};
    final cacheTime = DateTime.parse(cacheTimeStr);
    if (DateTime.now().difference(cacheTime).inMinutes > 1) return {};
    try { return (jsonDecode(json) as Map<String, dynamic>).map((k, v) => MapEntry(k, Stock.fromJson(v))); }
    catch (e) { return {}; }
  }

  static Future<void> _saveStockCacheToPrefs(Map<String, Stock> stocks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('stock_cache_v2', jsonEncode(stocks.map((k, v) => MapEntry(k, v.toJson()))));
    await prefs.setString('cache_time_v2', DateTime.now().toIso8601String());
  }

  static Future<List<Holding>> _loadHoldingsFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('holdings_v1');
    if (json == null) return [];
    try { return (jsonDecode(json) as List).map((e) => Holding.fromJson(e)).toList(); }
    catch (e) { return []; }
  }

  static Future<void> _saveHoldingsToPrefs(List<Holding> holdings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('holdings_v1', jsonEncode(holdings.map((e) => e.toJson()).toList()));
  }
}
