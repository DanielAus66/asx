import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/stock.dart';
import '../models/watchlist_item.dart';
import '../models/scan_rule.dart';
import '../models/holding.dart';

class StorageService {
  static const String _keyWatchlist = 'watchlist_v2';
  static const String _keyRules = 'scan_rules_v2';
  static const String _keyAlerts = 'alerts_v2';
  static const String _keyStockCache = 'stock_cache_v2';
  static const String _keyCacheTime = 'cache_time_v2';
  static const String _keyHoldings = 'holdings_v1';
  static const String _keySettings = 'app_settings_v1';

  static Future<List<WatchlistItem>> loadWatchlist() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_keyWatchlist);
    if (json == null) return [];
    try {
      final List<dynamic> items = jsonDecode(json);
      return items.map((e) => WatchlistItem.fromJson(e)).toList();
    } catch (e) { return []; }
  }

  static Future<void> saveWatchlist(List<WatchlistItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyWatchlist, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  static Future<List<ScanRule>> loadRules() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_keyRules);
    if (json == null) { await saveRules(defaultRules); return defaultRules; }
    try {
      final List<dynamic> items = jsonDecode(json);
      final rules = items.map((e) => ScanRule.fromJson(e)).toList();
      for (final defaultRule in defaultRules) {
        if (!rules.any((r) => r.id == defaultRule.id)) rules.add(defaultRule);
      }
      return rules;
    } catch (e) { return defaultRules; }
  }

  static Future<void> saveRules(List<ScanRule> rules) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRules, jsonEncode(rules.map((e) => e.toJson()).toList()));
  }

  static Future<List<Map<String, dynamic>>> loadAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_keyAlerts);
    if (json == null) return [];
    try { return (jsonDecode(json) as List).cast<Map<String, dynamic>>(); } catch (e) { return []; }
  }

  static Future<void> saveAlerts(List<Map<String, dynamic>> alerts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAlerts, jsonEncode(alerts));
  }

  static Future<void> addAlert(Map<String, dynamic> alert) async {
    final alerts = await loadAlerts();
    alerts.insert(0, alert);
    if (alerts.length > 100) alerts.removeRange(100, alerts.length);
    await saveAlerts(alerts);
  }

  static Future<Map<String, Stock>> loadStockCache() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_keyStockCache);
    final cacheTimeStr = prefs.getString(_keyCacheTime);
    if (json == null || cacheTimeStr == null) return {};
    final cacheTime = DateTime.parse(cacheTimeStr);
    // Cache expires after 1 minute - always fetch fresh on refresh
    if (DateTime.now().difference(cacheTime).inMinutes > 1) return {};
    try {
      final Map<String, dynamic> items = jsonDecode(json);
      return items.map((k, v) => MapEntry(k, Stock.fromJson(v)));
    } catch (e) { return {}; }
  }

  static Future<void> saveStockCache(Map<String, Stock> stocks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyStockCache, jsonEncode(stocks.map((k, v) => MapEntry(k, v.toJson()))));
    await prefs.setString(_keyCacheTime, DateTime.now().toIso8601String());
  }

  static Future<DateTime?> getCacheTime() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheTimeStr = prefs.getString(_keyCacheTime);
    if (cacheTimeStr == null) return null;
    return DateTime.parse(cacheTimeStr);
  }

  // Holdings storage
  static Future<List<Holding>> loadHoldings() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_keyHoldings);
    if (json == null) return [];
    try {
      final List<dynamic> items = jsonDecode(json);
      return items.map((e) => Holding.fromJson(e)).toList();
    } catch (e) { return []; }
  }

  static Future<void> saveHoldings(List<Holding> holdings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHoldings, jsonEncode(holdings.map((e) => e.toJson()).toList()));
  }

  // App settings storage
  static Future<Map<String, dynamic>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_keySettings);
    if (json == null) return {};
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (e) { return {}; }
  }

  static Future<void> saveSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadSettings();
    existing.addAll(settings);
    await prefs.setString(_keySettings, jsonEncode(existing));
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyWatchlist);
    await prefs.remove(_keyRules);
    await prefs.remove(_keyAlerts);
    await prefs.remove(_keyStockCache);
    await prefs.remove(_keyCacheTime);
  }
}