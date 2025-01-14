import 'dart:convert';
import 'dart:io';
import 'package:advanced_background_locator/advanced_background_locator.dart';
import 'package:advanced_background_locator/location_dto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'foreground_task_handler.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();
  int trackingDuration = 0;
  StreamSubscription<Position>? _positionStreamSubscription;
  List<LatLng> trackingPoints = [];

  /// Method to get the current location
  static Future<Position?> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    /// Check if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    // Check and request permissions
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied');
    }

    // Get the current position
    return await Geolocator.getCurrentPosition(
        // ignore: deprecated_member_use
        desiredAccuracy: LocationAccuracy.high);
  }

  /// Initialize Background Locator
  Future<void> initializeBackgroundLocator() async {
    await AdvancedBackgroundLocator.initialize();
  }

  /// Register background location updates
  Future<void> registerBackgroundUpdates(Function(LocationDto) callback) async {
    // Cancel any existing subscription first
    await _positionStreamSubscription?.cancel();

    await AdvancedBackgroundLocator.registerLocationUpdate(
      (LocationDto location) {
        callback(location);
      },
      autoStop: false,
      //androidNotificationCallback: _androidNotificationCallback,
    );
  }

  /// Unregister background location updates
  Future<void> unregisterBackgroundUpdates() async {
    // Cancel the position stream subscription
    await _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;

    await AdvancedBackgroundLocator.unRegisterLocationUpdate();
  }

  /// Android notification callback for background updates
  static void _androidNotificationCallback() {
    // This method can be used for handling notification actions if needed
  }

  ////
  // Request permission for Android
  ////
  Future<void> requestPermissionForAndroid() async {
    if (!Platform.isAndroid) {
      return;
    }
    if (!await FlutterForegroundTask.canDrawOverlays) {
      await FlutterForegroundTask.openSystemAlertWindowSettings();
    }
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
    final NotificationPermission notificationPermissionStatus =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermissionStatus != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  ////
  // Request permission for IOS
  ////
  Future<void> requestPermissionsForiOS() async {
    if (!Platform.isIOS) {
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception("Location permissions are denied");
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception("Location permissions are permanently denied");
    }
    final NotificationPermission notificationPermissionStatus =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermissionStatus != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  Future<bool> requestPermissions() async {
    // Request location permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.locationAlways,
      Permission.locationWhenInUse,
    ].request();

    // Check if all required permissions are granted
    bool allGranted = statuses.values.every((status) => status.isGranted);

    if (!allGranted) {
      return false;
    }

    // For Android 14 (API 34) and above, explicitly check foreground service permission
    if (Platform.isAndroid) {
      final deviceInfo = await DeviceInfoPlugin().androidInfo;
      if (deviceInfo.version.sdkInt >= 34) {
        final fgsStatus = await Permission.systemAlertWindow.request();
        if (!fgsStatus.isGranted) {
          return false;
        }
      }
    }

    return true;
  }

  ////
  // Format duration
  ////
  String formatDuration() {
    final hours = (trackingDuration ~/ 3600).toString().padLeft(2, '0');
    final minutes =
        ((trackingDuration % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (trackingDuration % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  ////
  // Start tracking
  ////
  Future<void> startTracking(Function(String) updateNotificationText) async {
    bool permissionsGranted = await requestPermissions();
    if (!permissionsGranted) {
      throw Exception('Required permissions not granted');
    }
    await FlutterForegroundTask.saveData(key: 'is_tracking', value: 'true');
    await FlutterForegroundTask.saveData(
        key: 'start_time', value: DateTime.now().toIso8601String());

    // Set tracking state
    trackingDuration = 0;

    // Start the foreground service
    await FlutterForegroundTask.startService(
      notificationTitle: 'Location Tracking Active',
      notificationText: 'Timer: 00:00:00\nWaiting for location...',
      callback: startCallback,
    );

    // Start the timer and update every second
    Timer.periodic(const Duration(seconds: 1), (timer) async {
      trackingDuration++;
      print('position: $trackingDuration');
      String formattedDuration = formatDuration();
      updateNotificationText(formattedDuration);
      final position = await getCurrentLocation();

      print('Position: ${position?.latitude} ${position?.longitude}');
      if (position != null) {
        LatLng point = LatLng(position.latitude, position.longitude);
        trackingPoints.add(point);
        trackingPoints.toSet().toList();
        await FlutterForegroundTask.saveData(
          key: 'tracking_points',
          value: json.encode(trackingPoints),
        );
        await FlutterForegroundTask.saveData(
          key: 'last_location',
          value: json.encode(position.toJson()),
        );

        String notificationText =
            'Timer: ${LocationService().formatDuration()}\n'
            'Tracking in progress\n'
            'Lat: ${position.latitude.toStringAsFixed(6)}, '
            'Lng: ${position.longitude.toStringAsFixed(6)}';

        await FlutterForegroundTask.updateService(
          notificationTitle: 'Location Tracking Active',
          notificationText: notificationText,
        );
      }

      // if (position != null) {
      // Update the location
      // final locationJson = json.encode(position.toJson());
      // await FlutterForegroundTask.saveData(
      //     key: 'last_location', value: locationJson);
      // String notificationText =
      //     'Timer: $formattedDuration\nLatitude: ${position.latitude.toStringAsFixed(8)}\nLongitude: ${position.longitude.toStringAsFixed(8)}';
      // await FlutterForegroundTask.updateService(
      //   notificationTitle: 'Location Tracking Active',
      //   notificationText: notificationText,
      // );
      // }
    });
  }
}
