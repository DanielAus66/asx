import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Handles all local (device) push notifications — distinct from the
/// foreground-service status notification which flutter_foreground_task manages.
///
/// Can be called from both the main isolate and the background task isolate.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  // Channel IDs
  static const String _scanAlertChannelId = 'asx_scan_alerts';
  static const String _scanAlertChannelName = 'Scan Alerts';
  static const String _scanAlertChannelDesc =
      'Notifications when a scan rule matches a stock in your watchlist';

  /// Call once from main() and once from the background task isolate entry point.
  static Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationTap,
    );

    // Ensure the high-importance channel exists on Android 8+
    const channel = AndroidNotificationChannel(
      _scanAlertChannelId,
      _scanAlertChannelName,
      description: _scanAlertChannelDesc,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  /// Show a scan-match alert notification.
  ///
  /// [id] should be unique per (ruleId, symbol) pair so identical matches
  /// update the existing notification rather than stacking duplicates.
  static Future<void> showScanAlert({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      _scanAlertChannelId,
      _scanAlertChannelName,
      channelDescription: _scanAlertChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'ASX Radar signal',
      icon: '@mipmap/ic_launcher',
      // Group multiple match notifications under one summary
      groupKey: 'asx_scan_group',
      setAsGroupSummary: false,
    );

    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }

  /// Show a grouped summary when multiple alerts fire in one scan cycle.
  static Future<void> showGroupSummary(int matchCount) async {
    if (!_initialized) await initialize();
    if (matchCount < 2) return;

    const androidDetails = AndroidNotificationDetails(
      _scanAlertChannelId,
      _scanAlertChannelName,
      importance: Importance.high,
      priority: Priority.high,
      groupKey: 'asx_scan_group',
      setAsGroupSummary: true,
      styleInformation: InboxStyleInformation(
        [],
        contentTitle: 'ASX Radar',
        summaryText: 'New signals found',
      ),
    );

    await _plugin.show(
      0, // fixed ID for the summary notification
      'ASX Radar',
      '$matchCount new signals found',
      const NotificationDetails(android: androidDetails),
    );
  }

  static void _onNotificationTap(NotificationResponse response) {
    // Main isolate: navigate to scan results tab
    // Navigation from here requires a global navigator key — hook up in main.dart if needed
  }
}

@pragma('vm:entry-point')
void _onBackgroundNotificationTap(NotificationResponse response) {
  // Background isolate tap handler — required annotation
}
