import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'background_task_service.dart';

/// How often the background scan runs (must be ≥ 15 minutes on Android).
enum ScanInterval {
  min15(15, '15 minutes'),
  min30(30, '30 minutes'),
  min60(60, '1 hour');

  final int minutes;
  final String label;
  const ScanInterval(this.minutes, this.label);

  int get milliseconds => minutes * 60 * 1000;
}

/// Manages the lifecycle of the periodic background scanner and persists
/// user settings (enabled, interval, market-hours-only flag).
///
/// Communication to the background isolate is done via SharedPreferences
/// (compatible with flutter_foreground_task v6.x which lacks sendDataToTask).
/// The handler re-reads relevant keys on every onRepeatEvent.
class ScanSchedulerService with ChangeNotifier {
  static const String _keyEnabled = 'bg_scanner_enabled';
  static const String _keyInterval = 'bg_scanner_interval_minutes';
  static const String _keyMarketHoursOnly = 'bg_scanner_market_hours_only';
  // Written by main isolate, read+cleared by background handler
  static const String keyScanNow = 'bg_scanner_scan_now';

  bool _enabled = false;
  ScanInterval _interval = ScanInterval.min15;
  bool _marketHoursOnly = true;
  bool _isServiceRunning = false;

  bool get enabled => _enabled;
  ScanInterval get interval => _interval;
  bool get marketHoursOnly => _marketHoursOnly;
  bool get isServiceRunning => _isServiceRunning;

  static bool get isMarketHours {
    final aest = DateTime.now().toUtc().add(const Duration(hours: 10));
    if (aest.weekday == DateTime.saturday || aest.weekday == DateTime.sunday) {
      return false;
    }
    final minuteOfDay = aest.hour * 60 + aest.minute;
    return minuteOfDay >= 600 && minuteOfDay < 960;
  }

  static String get marketStatusLabel {
    final aest = DateTime.now().toUtc().add(const Duration(hours: 10));
    if (aest.weekday == DateTime.saturday || aest.weekday == DateTime.sunday) {
      return 'Market closed — weekend';
    }
    final minuteOfDay = aest.hour * 60 + aest.minute;
    if (minuteOfDay < 600) {
      final opens = Duration(minutes: 600 - minuteOfDay);
      return 'Market opens in ${_formatDuration(opens)}';
    }
    if (minuteOfDay >= 960) return 'Market closed for today';
    final closes = Duration(minutes: 960 - minuteOfDay);
    return 'Market open · closes in ${_formatDuration(closes)}';
  }

  static String _formatDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    return '${d.inMinutes}m';
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_keyEnabled) ?? false;
    final savedMinutes = prefs.getInt(_keyInterval) ?? 15;
    _interval = ScanInterval.values.firstWhere(
      (i) => i.minutes == savedMinutes,
      orElse: () => ScanInterval.min15,
    );
    _marketHoursOnly = prefs.getBool(_keyMarketHoursOnly) ?? true;
    _isServiceRunning = await FlutterForegroundTask.isRunningService;

    if (_enabled && !_isServiceRunning) {
      await _startService();
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, value);

    if (value) {
      await _startService();
    } else {
      await _stopService();
    }
    notifyListeners();
  }

  Future<void> setInterval(ScanInterval interval) async {
    _interval = interval;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyInterval, interval.minutes);

    if (_enabled && _isServiceRunning) {
      await _stopService();
      await _startService();
    }
    notifyListeners();
  }

  Future<void> setMarketHoursOnly(bool value) async {
    _marketHoursOnly = value;
    final prefs = await SharedPreferences.getInstance();
    // The background handler re-reads this key on every onRepeatEvent
    await prefs.setBool(_keyMarketHoursOnly, value);
    notifyListeners();
  }

  Future<void> _startService() async {
    final started = await BackgroundTaskService.startPeriodicScan(
      intervalMs: _interval.milliseconds,
      marketHoursOnly: _marketHoursOnly,
    );
    _isServiceRunning = started;
    notifyListeners();
  }

  Future<void> _stopService() async {
    await BackgroundTaskService.stopTask();
    _isServiceRunning = false;
    notifyListeners();
  }

  /// Request an immediate scan on the next onRepeatEvent tick.
  /// Uses a SharedPreferences flag rather than sendDataToTask (v6 compat).
  Future<void> triggerImmediateScan() async {
    if (_isServiceRunning) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyScanNow, true);
    }
  }

  Future<void> refreshRunningState() async {
    _isServiceRunning = await FlutterForegroundTask.isRunningService;
    notifyListeners();
  }
}