import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter/material.dart';

/// Background task service for running scans and backtests
/// even when the app is in the background
class BackgroundTaskService {
  static bool _isInitialized = false;
  
  /// Initialize the foreground task service
  static Future<void> initialize() async {
    if (_isInitialized) return;
    
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'asx_radar_scan',
        channelName: 'ASX Radar Scanning',
        channelDescription: 'Notification for ASX Radar background scanning',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 1000,
        isOnceEvent: false,
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    
    _isInitialized = true;
  }
  
  /// Start the foreground task for scanning
  static Future<bool> startScanTask({
    required String taskName,
    required int totalStocks,
  }) async {
    await initialize();
    
    // Request permissions if needed
    final notificationPermission = await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    
    // Start the foreground service
    return await FlutterForegroundTask.startService(
      notificationTitle: 'ASX Radar',
      notificationText: '$taskName - Starting...',
      callback: _startCallback,
    );
  }
  
  /// Update the notification with progress
  static Future<void> updateProgress({
    required String taskName,
    required int current,
    required int total,
    required int matches,
  }) async {
    final percent = total > 0 ? (current / total * 100).toInt() : 0;
    await FlutterForegroundTask.updateService(
      notificationTitle: 'ASX Radar - $taskName',
      notificationText: '$current/$total ($percent%) • $matches matches found',
    );
  }
  
  /// Show completion notification before stopping
  static Future<void> completeTask({
    required String taskName,
    required int matches,
    required int uniqueStocks,
  }) async {
    // Update notification to show completion
    await FlutterForegroundTask.updateService(
      notificationTitle: 'ASX Radar - Complete ✓',
      notificationText: '$taskName finished: $matches signals from $uniqueStocks stocks',
    );
    
    // Keep notification visible for 3 seconds so user sees it
    await Future.delayed(const Duration(seconds: 3));
    
    // Now stop the service
    await FlutterForegroundTask.stopService();
  }
  
  /// Stop the foreground task
  static Future<bool> stopTask() async {
    return await FlutterForegroundTask.stopService();
  }
  
  /// Check if a task is running
  static Future<bool> isRunning() async {
    return await FlutterForegroundTask.isRunningService;
  }
}

// Top-level callback function for the foreground task
@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(ScanTaskHandler());
}

/// Task handler that runs in the foreground service
class ScanTaskHandler extends TaskHandler {
  SendPort? _sendPort;
  
  @override
  void onStart(DateTime timestamp, SendPort? sendPort) {
    _sendPort = sendPort;
  }
  
  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) {
    // This is called periodically but we don't need it for our use case
    // The actual scanning is done in the main isolate
  }
  
  @override
  void onDestroy(DateTime timestamp, SendPort? sendPort) {
    // Cleanup when the service is stopped
  }
  
  @override
  void onNotificationButtonPressed(String id) {
    // Handle notification button presses if needed
    if (id == 'stop') {
      FlutterForegroundTask.stopService();
    }
  }
  
  @override
  void onNotificationPressed() {
    // Called when the notification is pressed
    // This will bring the app to the foreground
    FlutterForegroundTask.launchApp();
  }
}

/// Widget wrapper that enables foreground task functionality
class WithForegroundTask extends StatelessWidget {
  final Widget child;
  
  const WithForegroundTask({super.key, required this.child});
  
  @override
  Widget build(BuildContext context) {
    return WillStartForegroundTask(
      onWillStart: () async => await BackgroundTaskService.isRunning(),
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'asx_radar_scan',
        channelName: 'ASX Radar Scanning',
        channelDescription: 'Background scanning notification',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 1000,
        isOnceEvent: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
      notificationTitle: 'ASX Radar',
      notificationText: 'Scanning in progress...',
      child: child,
    );
  }
}