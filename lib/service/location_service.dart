import 'package:geolocator/geolocator.dart';
import 'package:background_locator_2/background_locator.dart';
import 'package:background_locator_2/location_dto.dart';
import 'dart:async';

class LocationService {
  // Singleton instance
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionStreamSubscription;

  /// Method to get the current location
  static Future<Position?> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Check if location services are enabled
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
        desiredAccuracy: LocationAccuracy.high);
  }

  /// Initialize Background Locator
  Future<void> initializeBackgroundLocator() async {
    await BackgroundLocator.initialize();
  }

  /// Register background location updates
  Future<void> registerBackgroundUpdates(Function(LocationDto) callback) async {
    // Cancel any existing subscription first
    await _positionStreamSubscription?.cancel();

    await BackgroundLocator.registerLocationUpdate(
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

    await BackgroundLocator.unRegisterLocationUpdate();
  }

  /// Android notification callback for background updates
  static void _androidNotificationCallback() {
    // This method can be used for handling notification actions if needed
  }
}
