import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'location_service.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(LocationTrackingHandler());
}

class LocationTrackingHandler extends TaskHandler {
  StreamSubscription<Position>? positionStream;
  DateTime? _lastUpdateTime;
  List<Map<String, dynamic>> trackingPoints = [];
  List<LatLng> points = [];
  int _elapsedSeconds = 0;
  DateTime? _startTime;

  String _formatDuration() {
    final hours = (_elapsedSeconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((_elapsedSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  // Request overlay permission function
  void requestOverlayPermission() async {
    final permissionStatus = await Permission.systemAlertWindow.status;

    if (!permissionStatus.isGranted) {
      final result = await Permission.systemAlertWindow.request();
      if (result.isGranted) {
        if (kDebugMode) {
          print("Overlay permission granted");
        }
      } else {
        if (kDebugMode) {
          print("Overlay permission denied");
        }
      }
    } else {
      if (kDebugMode) {
        print("Overlay permission already granted");
      }
    }
  }

  // Ensure all location permissions are requested
  Future<void> requestLocationPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception("Location permissions are permanently denied.");
    }
  }

  // Start the foreground task
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Request necessary permissions before starting the task
    await requestLocationPermissions();
    requestOverlayPermission();

    // Initialize timer
    _startTime = await FlutterForegroundTask.getData(key: 'start_time') != null
        ? DateTime.parse(await FlutterForegroundTask.getData(key: 'start_time'))
        : DateTime.now();

    _elapsedSeconds = DateTime.now().difference(_startTime!).inSeconds;

    // Initialize anything needed for the background task
    if (kDebugMode) {
      print(" ~~~ Background location tracking started ~~~");
      print(" ~~~ Timer started at: $_startTime ~~~");
    }
  }

  // Handle the event
  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {
    try {
      // Get the current location
      final position = await LocationService.getCurrentLocation();

      if (position != null) {
        // Print the location to the terminal
        print(
            'Location update: Latitude: ${position.latitude}, Longitude: ${position.longitude}');

        // Send location data to the foreground via SendPort if provided
        sendPort?.send({'location': position.toJson()});
      }
    } catch (e) {
      // Handle errors in background location tracking
      print('Error in background location tracking: $e');
    }
  }

  // Stop the foreground task
  @override
  Future<void> onDestroy(DateTime timestamp) async {
    // Clean up location stream subscription
    await positionStream?.cancel();
    // Save final tracking data before destroying
    if (trackingPoints.isNotEmpty) {
      await FlutterForegroundTask.saveData(
        key: 'tracking_points',
        value: json.encode(trackingPoints),
      );
    }
    // Save final timer state
    await FlutterForegroundTask.saveData(
      key: 'elapsed_seconds',
      value: _elapsedSeconds.toString(),
    );
    if (kDebugMode) {
      print(
          "Background location tracking stopped with ${trackingPoints.length} points saved");
      print("Background tracking stopped - Duration: ${_formatDuration()}");
    }
  }

  // Handle the repeat event
  @override
  void onRepeatEvent(DateTime timestamp) async {
    try {
      // Fetch location on each event
      final position = await LocationService.getCurrentLocation();

      // Update timer
      if (_startTime != null) {
        _elapsedSeconds = DateTime.now().difference(_startTime!).inSeconds;
      }

      if (position != null) {
        print("[Position]: ${position.latitude}, ${position.longitude}");

        // Add new point and save
        points.add(LatLng(
          position.latitude,
          position.longitude,
        ));

        // We remove any duplicates points
        points.toSet().toList();

        // Store points to local storage
        await FlutterForegroundTask.saveData(
          key: 'tracking_points',
          value: json.encode(points
              .map((point) => {
                    'latitude': point.latitude,
                    'longitude': point.longitude,
                  })
              .toList()),
        );

        await FlutterForegroundTask.saveData(key: 'is_tracking', value: 'true');

        print('${points.length} Total Points');

        // Update notification with timer and location
        String notificationText = 'Timer: ${_formatDuration()}\n'
            'Points: ${points.length}\n'
            'Lat: ${position.latitude.toStringAsFixed(6)}, '
            'Lng: ${position.longitude.toStringAsFixed(6)}';

        await FlutterForegroundTask.updateService(
          notificationTitle: 'Location Tracking Active',
          notificationText: notificationText,
        );

        // Save elapsed time
        await FlutterForegroundTask.saveData(
          key: 'elapsed_seconds',
          value: _elapsedSeconds.toString(),
        );
      }
    } catch (e, stackTrace) {
      print('Error in repeat event: $e');
      print('[Stacktrace] in repeat event: $stackTrace');
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
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(500),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }
}
