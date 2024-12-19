import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'location_service.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(LocationTrackingHandler());
}

class LocationTrackingHandler extends TaskHandler {
  StreamSubscription<Position>? positionStream;
  bool isPaused = false;

  // Request overlay permission function
  void requestOverlayPermission() async {
    final permissionStatus = await Permission.systemAlertWindow.status;

    if (!permissionStatus.isGranted) {
      final result = await Permission.systemAlertWindow.request();

      if (result.isGranted) {
        print("Overlay permission granted");
      } else {
        print("Overlay permission denied");
      }
    } else {
      print("Overlay permission already granted");
    }
  }

  // Start the foreground task
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Request overlay permission before starting the task
    requestOverlayPermission();

    // Initialize anything needed for the background task
    if (kDebugMode) {
      print("Background location tracking started");
    }

    // Load pause state
    final pausedData = await FlutterForegroundTask.getData(key: 'is_paused');
    isPaused = pausedData == 'true';

    // Start listening to location updates
    positionStream =
        Geolocator.getPositionStream().listen((Position position) async {
      if (!isPaused) {
        final locationJson = json.encode(position.toJson());
        await FlutterForegroundTask.saveData(
            key: 'last_location', value: locationJson);

        // Update the foreground notification with the new location data
        String notificationText =
            'Latitude: ${position.latitude.toStringAsFixed(8)}\n'
            'Longitude: ${position.longitude.toStringAsFixed(8)}';
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Location Tracking Active',
          notificationText: notificationText,
          notificationButtons: [
            const NotificationButton(
              id: 'pauseButton',
              text: 'Pause',
              textColor: Colors.red,
            ),
          ],
        );
      }
    });

    // Optionally load saved data or initialize settings
    final lastLocation =
        await FlutterForegroundTask.getData(key: 'last_location');
    if (lastLocation != null) {
      if (kDebugMode) {
        print('Restored last location: $lastLocation');
      }
    }
  }

  // Handle the event
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {
    try {
      if (!isPaused) {
        final position = await LocationService.getCurrentLocation();

        if (position != null) {
          // Send location data to the foreground via SendPort if provided
          sendPort?.send({'location': position.toJson()});
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error in background location tracking: $e');
      }
    }
  }

  // Stop the foreground task
  @override
  Future<void> onDestroy(DateTime timestamp) async {
    // Clean up location stream subscription
    await positionStream?.cancel();
    if (kDebugMode) {
      print("Background location tracking stopped");
    }
  }

  // Handle button press events
  @override
  void onButtonPressed(String id) {
    if (id == 'pauseButton') {
      isPaused = true;
      FlutterForegroundTask.saveData(key: 'is_paused', value: 'true');
      FlutterForegroundTask.updateService(
        notificationTitle: 'Location Tracking Paused',
        notificationText: 'Tracking is paused',
        notificationButtons: [
          const NotificationButton(
            id: 'resumeButton',
            text: 'Resume',
            textColor: Colors.green,
          ),
        ],
      );
    } else if (id == 'resumeButton') {
      isPaused = false;
      FlutterForegroundTask.saveData(key: 'is_paused', value: 'false');
      FlutterForegroundTask.updateService(
        notificationTitle: 'Location Tracking Active',
        notificationText: 'Tracking resumed...',
        notificationButtons: [
          const NotificationButton(
            id: 'pauseButton',
            text: 'Pause',
            textColor: Colors.orange,
          ),
        ],
      );
    }
  }

  // Handle the repeat event
  @override
  void onRepeatEvent(DateTime timestamp) {
    // Repeated events can be handled here if necessary
    if (kDebugMode) {
      print("Repeat event triggered at: $timestamp");
    }
  }

  // Initialize the foreground task
  void initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'location_tracker',
        channelName: 'Location Tracking Service',
        channelDescription:
            'This notification appears when location is being tracked',
        channelImportance: NotificationChannelImportance.MIN,
        priority: NotificationPriority.MIN,
        visibility: NotificationVisibility.VISIBILITY_PRIVATE,
        enableVibration: false,
        playSound: false,
        showWhen: false,
        onlyAlertOnce: true,
        // notificationButtons: [
        //   const NotificationButton(
        //     id: 'pauseButton',
        //     text: 'Pause',
        //     textColor: Colors.red,
        //   ),
        // ],
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }
}
