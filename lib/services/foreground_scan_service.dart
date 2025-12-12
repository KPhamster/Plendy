import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Service to manage foreground service during AI scans.
/// This keeps the app alive when it goes to background during a scan,
/// preventing the scan from being interrupted.
class ForegroundScanService {
  static final ForegroundScanService _instance = ForegroundScanService._internal();
  factory ForegroundScanService() => _instance;
  ForegroundScanService._internal();

  bool _isInitialized = false;
  bool _isServiceRunning = false;

  /// Initialize the foreground task service.
  /// Call this once during app startup.
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    // Only initialize on mobile platforms
    if (!Platform.isAndroid && !Platform.isIOS) {
      _isInitialized = true;
      return;
    }

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'plendy_scan_service',
        channelName: 'AI Scan Service',
        channelDescription: 'Keeps the app running while scanning for locations.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
        showWhen: false,
        enableVibration: false,
        playSound: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    _isInitialized = true;
    print('✅ ForegroundScanService: Initialized');
  }

  /// Request notification permission if needed.
  /// Returns true if permission is granted.
  Future<bool> requestPermissionIfNeeded() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      final result = await FlutterForegroundTask.requestNotificationPermission();
      return result == NotificationPermission.granted;
    }
    return true;
  }

  /// Start the foreground service to keep the app alive during scanning.
  /// This shows a notification while the scan is in progress.
  Future<bool> startScanService() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    if (!_isInitialized) {
      await initialize();
    }
    
    if (_isServiceRunning) {
      print('⚠️ ForegroundScanService: Service already running');
      return true;
    }

    try {
      // Check if service is already running
      if (await FlutterForegroundTask.isRunningService) {
        _isServiceRunning = true;
        return true;
      }

      final result = await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: 'Scanning for locations...',
        notificationText: 'AI is analyzing the content. Please wait.',
        notificationIcon: null, // Uses default app icon
        callback: _emptyCallback,
      );

      if (result is ServiceRequestSuccess) {
        _isServiceRunning = true;
        print('✅ ForegroundScanService: Service started');
        return true;
      } else if (result is ServiceRequestFailure) {
        print('❌ ForegroundScanService: Failed to start - ${result.error}');
        return false;
      }
      return false;
    } catch (e) {
      print('❌ ForegroundScanService: Error starting service - $e');
      return false;
    }
  }

  /// Update the notification text during the scan.
  Future<void> updateProgress(String text) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (!_isServiceRunning) return;

    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Scanning for locations...',
        notificationText: text,
      );
    } catch (e) {
      print('⚠️ ForegroundScanService: Error updating progress - $e');
    }
  }

  /// Stop the foreground service after scanning is complete.
  Future<void> stopScanService() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (!_isServiceRunning) return;

    try {
      final result = await FlutterForegroundTask.stopService();
      if (result is ServiceRequestSuccess) {
        _isServiceRunning = false;
        print('✅ ForegroundScanService: Service stopped');
      } else if (result is ServiceRequestFailure) {
        print('⚠️ ForegroundScanService: Failed to stop - ${result.error}');
        _isServiceRunning = false; // Reset state anyway
      }
    } catch (e) {
      print('⚠️ ForegroundScanService: Error stopping service - $e');
      _isServiceRunning = false;
    }
  }

  /// Check if the service is currently running.
  bool get isRunning => _isServiceRunning;

  /// Check if initialized.
  bool get isInitialized => _isInitialized;
}

/// Empty callback for the foreground service.
/// The actual work is done in the main isolate, this just keeps the app alive.
@pragma('vm:entry-point')
void _emptyCallback() {
  // No-op - we don't need to do anything here.
  // The foreground service just keeps the app alive while we do work in the main isolate.
  FlutterForegroundTask.setTaskHandler(_EmptyTaskHandler());
}

/// Empty task handler that does nothing.
/// The actual scan work happens in the main isolate.
class _EmptyTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // No-op
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // No-op
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // No-op
  }
}

