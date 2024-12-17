import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'location_service.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(LocationTrackingHandler());
}

class LocationTrackingHandler extends TaskHandler {
  StreamSubscription<Position>? positionStream;

  ////
  // Start the foreground task
  ////
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Initialize anything needed for the background task
    print("Background location tracking started");

    // Start listening to location updates
    positionStream =
        Geolocator.getPositionStream().listen((Position position) async {
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
      );
    });

    // Optionally load saved data or initialize settings
    final lastLocation =
        await FlutterForegroundTask.getData(key: 'last_location');
    if (lastLocation != null) {
      print('Restored last location: $lastLocation');
    }
  }

  ////
  // Handle the event
  ////
  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {
    try {
      final position = await LocationService.getCurrentLocation();

      if (position != null) {
        // Send location data to the foreground via SendPort if provided
        sendPort?.send({'location': position.toJson()});
      }
    } catch (e) {
      print('Error in background location tracking: $e');
    }
  }

  ////
  // Stop the foreground task
  ////
  @override
  Future<void> onDestroy(DateTime timestamp) async {
    // Clean up location stream subscription
    await positionStream?.cancel();
    print("Background location tracking stopped");
  }

  ////
  // Handle the repeat event
  ////
  @override
  void onRepeatEvent(DateTime timestamp) {
    // Repeated events can be handled here if necessary
    print("Repeat event triggered at: $timestamp");
  }

  ////
  // Initialize the foreground task
  ////
  void initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'location_tracker',
        channelName: 'Location Tracking Service',
        channelDescription:
            'This notification appears when location is being tracked',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.LOW,
        visibility: NotificationVisibility.VISIBILITY_PRIVATE,
        enableVibration: false,
        playSound: false,
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
