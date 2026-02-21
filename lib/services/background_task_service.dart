import 'dart:convert';
import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/scan_rule.dart';
import '../models/stock.dart';
import 'notification_service.dart';
import 'scan_engine_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TOP-LEVEL ENTRY POINT
// ─────────────────────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
void startCallback() {
  NotificationService.initialize();
  FlutterForegroundTask.setTaskHandler(PeriodicScanTaskHandler());
}

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC SERVICE API
// ─────────────────────────────────────────────────────────────────────────────

class BackgroundTaskService {
  static bool _initialized = false;

  static void _init(int intervalMs) {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'asx_radar_scan',
        channelName: 'ASX Radar Scanner',
        channelDescription: 'Watches your rules during ASX market hours',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
        buttons: [const NotificationButton(id: 'stop', text: 'Stop')],
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        interval: intervalMs,
        isOnceEvent: false,
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    _initialized = true;
  }

  static Future<bool> startPeriodicScan({
    required int intervalMs,
    required bool marketHoursOnly,
  }) async {
    _init(intervalMs);

    final perm = await FlutterForegroundTask.checkNotificationPermission();
    if (perm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) return await FlutterForegroundTask.restartService();

    return await FlutterForegroundTask.startService(
      notificationTitle: 'ASX Radar',
      notificationText: 'Scanner active · watching your watchlist',
      callback: startCallback,
    );
  }

  static Future<bool> stopTask() async {
    _initialized = false;
    return await FlutterForegroundTask.stopService();
  }

  static Future<bool> isRunning() async =>
      await FlutterForegroundTask.isRunningService;

  // Legacy on-demand scan methods kept for scan_screen.dart compatibility
  static Future<bool> startScanTask({
    required String taskName,
    required int totalStocks,
  }) async {
    _init(1000);
    final perm = await FlutterForegroundTask.checkNotificationPermission();
    if (perm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    return await FlutterForegroundTask.startService(
      notificationTitle: 'ASX Radar',
      notificationText: '$taskName - Starting...',
      callback: startCallback,
    );
  }

  static Future<void> updateProgress({
    required String taskName,
    required int current,
    required int total,
    required int matches,
  }) async {
    final pct = total > 0 ? (current / total * 100).toInt() : 0;
    await FlutterForegroundTask.updateService(
      notificationTitle: 'ASX Radar - $taskName',
      notificationText: '$current/$total ($pct%) • $matches matches',
    );
  }

  static Future<void> completeTask({
    required String taskName,
    required int matches,
    required int uniqueStocks,
  }) async {
    await FlutterForegroundTask.updateService(
      notificationTitle: 'ASX Radar - Complete',
      notificationText: '$taskName: $matches signals from $uniqueStocks stocks',
    );
    await Future.delayed(const Duration(seconds: 3));
    await FlutterForegroundTask.stopService();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TASK HANDLER  (background isolate)
// ─────────────────────────────────────────────────────────────────────────────

class PeriodicScanTaskHandler extends TaskHandler {
  // Config is always read fresh from SharedPreferences on each tick.
  // This avoids needing sendDataToTask (not available in v6.x).

  @override
  void onStart(DateTime timestamp, SendPort? sendPort) async {}

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {
    final prefs = await SharedPreferences.getInstance();

    // Re-read config on every tick so changes from main isolate are picked up
    final marketHoursOnly = prefs.getBool('bg_scanner_market_hours_only') ?? true;

    // Check for a "scan now" request written by the main isolate
    final scanNowRequested = prefs.getBool('bg_scanner_scan_now') ?? false;
    if (scanNowRequested) {
      await prefs.remove('bg_scanner_scan_now'); // clear the flag
    }

    final shouldScan = scanNowRequested || !marketHoursOnly || _isMarketHours();

    if (!shouldScan) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'ASX Radar',
        notificationText: 'Waiting · ${_marketStatusShort()}',
      );
      return;
    }
    await _runScan();
  }

  @override
  void onDestroy(DateTime timestamp, SendPort? sendPort) {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') FlutterForegroundTask.stopService();
  }

  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();

  @override
  void onReceiveData(Object data) {
    // onReceiveData requires sendDataToTask which is not available in v6.x.
    // All inter-isolate communication goes through SharedPreferences instead.
  }

  // ─── Scan logic ─────────────────────────────────────────────────────────

  Future<void> _runScan() async {
    await _setNotif('Scanning watchlist…');

    try {
      final rules = await _loadActiveRules();
      if (rules.isEmpty) { await _setNotif('No active rules'); return; }

      final bgRules = rules.where(_quoteOnlyRule).toList();
      if (bgRules.isEmpty) {
        await _setNotif('Rules need full scan · open app to scan');
        return;
      }

      final symbols = await _loadWatchlistSymbols();
      if (symbols.isEmpty) { await _setNotif('Watchlist empty'); return; }

      final stocks = await _batchFetchQuotes(symbols);
      if (stocks.isEmpty) { await _setNotif('Could not fetch prices · retrying'); return; }

      final prefs = await SharedPreferences.getInstance();
      final today = _todayStr();
      int newMatches = 0;

      for (final stock in stocks) {
        for (final rule in bgRules) {
          if (!ScanEngineService.evaluateRule(stock, rule)) continue;

          final key = 'bg_trigger_${rule.id}_${stock.symbol}_$today';
          if (prefs.getBool(key) == true) continue; // already notified today

          await prefs.setBool(key, true);
          newMatches++;

          await NotificationService.showScanAlert(
            id: _notifId(rule.id, stock.symbol),
            title: '${stock.symbol} · ${rule.name}',
            body: _body(stock, rule),
            payload: stock.symbol,
          );
        }
      }

      if (newMatches > 1) await NotificationService.showGroupSummary(newMatches);
      await _pruneOldKeys(prefs);

      final t = _hhmm(DateTime.now());
      await _setNotif(newMatches > 0
          ? '$newMatches new signal${newMatches > 1 ? 's' : ''} · $t'
          : 'No new signals · last checked $t');
    } catch (e) {
      await _setNotif('Scan error · will retry');
    }
  }

  // ─── Rule filter: can we evaluate this with quote data only? ────────────

  static const _quoteTypes = {
    RuleConditionType.priceChangeAbove,
    RuleConditionType.priceChangeBelow,
    RuleConditionType.priceNear52WeekHigh,
    RuleConditionType.priceNear52WeekLow,
    RuleConditionType.nearAllTimeHigh,
    RuleConditionType.volumeSpike,
    RuleConditionType.stealthAccumulation,
  };

  bool _quoteOnlyRule(ScanRule rule) =>
      rule.conditions.every((c) => _quoteTypes.contains(c.type));

  // ─── Data loading ────────────────────────────────────────────────────────

  Future<List<ScanRule>> _loadActiveRules() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('scan_rules_v2');
      if (json == null) return [];
      final list = jsonDecode(json) as List;
      return list
          .map((e) => ScanRule.fromJson(e as Map<String, dynamic>))
          .where((r) => r.isActive)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> _loadWatchlistSymbols() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('watchlist_v2');
      if (json == null) return [];
      final list = jsonDecode(json) as List;
      return list
          .map((e) => (e as Map<String, dynamic>)['symbol'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Stock>> _batchFetchQuotes(List<String> symbols) async {
    // Yahoo accepts up to ~100 comma-separated symbols in one request
    final joined = symbols.join(',');
    final url = Uri.parse(
        'https://query1.finance.yahoo.com/v7/finance/quote?symbols=$joined');
    try {
      final res = await http
          .get(url, headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return [];

      final data = jsonDecode(res.body);
      final results = data['quoteResponse']?['result'] as List?;
      if (results == null) return [];

      return results.map<Stock?>((q) {
        final price = (q['regularMarketPrice'] as num?)?.toDouble();
        if (price == null || price <= 0) return null;
        return Stock(
          symbol: q['symbol'] as String? ?? '',
          name: q['shortName'] ?? '',
          currentPrice: price,
          previousClose:
              ((q['regularMarketPreviousClose'] ?? price) as num).toDouble(),
          change: ((q['regularMarketChange'] ?? 0.0) as num).toDouble(),
          changePercent:
              ((q['regularMarketChangePercent'] ?? 0.0) as num).toDouble(),
          volume: (q['regularMarketVolume'] ?? 0) as int,
          marketCap: ((q['marketCap'] ?? 0.0) as num).toDouble(),
          lastUpdate: DateTime.now(),
          weekHigh52: (q['fiftyTwoWeekHigh'] as num?)?.toDouble(),
          weekLow52: (q['fiftyTwoWeekLow'] as num?)?.toDouble(),
          avgVolume: (q['averageDailyVolume3Month'] as num?)?.toDouble(),
        );
      }).whereType<Stock>().toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Utilities ────────────────────────────────────────────────────────────

  String _body(Stock stock, ScanRule rule) {
    final price = '\$${stock.currentPrice.toStringAsFixed(2)}';
    final chg = stock.changePercent >= 0
        ? '+${stock.changePercent.toStringAsFixed(1)}%'
        : '${stock.changePercent.toStringAsFixed(1)}%';
    final conds = rule.conditions.map((c) => c.shortDescription).join(' · ');
    return '$price ($chg) · $conds';
  }

  int _notifId(String ruleId, String symbol) =>
      (ruleId + symbol).hashCode.abs() % 9999 + 1;

  String _todayStr() {
    final d = DateTime.now();
    return '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
  }

  String _hhmm(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  Future<void> _setNotif(String text) async {
    await FlutterForegroundTask.updateService(
      notificationTitle: 'ASX Radar',
      notificationText: text,
    );
  }

  bool _isMarketHours() {
    final aest = DateTime.now().toUtc().add(const Duration(hours: 10));
    if (aest.weekday >= DateTime.saturday) return false;
    final m = aest.hour * 60 + aest.minute;
    return m >= 600 && m < 960; // 10:00am–4:00pm
  }

  String _marketStatusShort() {
    final aest = DateTime.now().toUtc().add(const Duration(hours: 10));
    final m = aest.hour * 60 + aest.minute;
    if (aest.weekday >= DateTime.saturday) return 'closed (weekend)';
    if (m < 600) return 'opens in ${600 - m}m';
    return 'closed';
  }

  Future<void> _pruneOldKeys(SharedPreferences prefs) async {
    final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
    final cutoff =
        '${twoDaysAgo.year}${twoDaysAgo.month.toString().padLeft(2, '0')}${twoDaysAgo.day.toString().padLeft(2, '0')}';
    for (final key in prefs.getKeys().where((k) => k.startsWith('bg_trigger_'))) {
      final parts = key.split('_');
      if (parts.isNotEmpty && parts.last.compareTo(cutoff) <= 0) {
        await prefs.remove(key);
      }
    }
  }
}