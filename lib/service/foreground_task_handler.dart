import 'dart:convert';
import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'location_service.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(LocationTrackingHandler());
}

class LocationTrackingHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Initialize anything needed for the background task
    print("Background location tracking started");
  }

  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {
    try {
      final position = await LocationService.getCurrentLocation();

      if (position != null) {
        // Save the latest position
        final locationJson = json.encode(position.toJson());
        await FlutterForegroundTask.saveData(
            key: 'last_location', value: locationJson);

        // Send location data to the foreground via SendPort if provided
        sendPort?.send({'location': position.toJson()});

        // Update the foreground notification with the new location data
        String notificationText =
            'Latitude: ${position.latitude.toStringAsFixed(8)}\n'
            'Longitude: ${position.longitude.toStringAsFixed(8)}';
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Location Tracking Active',
          notificationText: notificationText,
        );
      }
    } catch (e) {
      print('Error in background location tracking: $e');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    // Clean up any resources
    print("Background location tracking stopped");
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Repeated events can be handled here if necessary
  }
}
