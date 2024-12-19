import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:location_service/service/location_service.dart';

class MapService {
  GoogleMapController? mapController;
  final Set<Polyline> _polylines = {};
  final PolylinePoints _polylinePoints = PolylinePoints();
  final LocationService _locationService = LocationService();
  StreamSubscription<Position>? _positionStreamSubscription;
  List<LatLng> trackingPoints = [];

  void onMapCreated(GoogleMapController controller) {
    mapController = controller;
    _loadSavedTrackingData();
  }

  Future<void> _loadSavedTrackingData() async {
    final String? trackingData =
        await FlutterForegroundTask.getData(key: 'last_tracking_data');
    if (trackingData != null) {
      final decodedData = json.decode(trackingData);
      final List<dynamic> points = decodedData['points'];

      List<LatLng> savedPoints = points
          .map((point) =>
              LatLng(point['latitude'] as double, point['longitude'] as double))
          .toList();

      if (savedPoints.isNotEmpty) {
        _polylines.add(Polyline(
          polylineId: const PolylineId('saved_route'),
          color: const Color.fromARGB(255, 0, 128, 4),
          width: 5,
          points: savedPoints,
          jointType: JointType.round,
        ));

        fitBounds(savedPoints);
      }
    }
  }

  Future<void> setLocationSettings() async {
    // Clear previous tracking data
    _polylines.clear();
    trackingPoints.clear();

    Position? position = await LocationService.getCurrentLocation();
    if (position != null) {
      final latLng = LatLng(position.latitude, position.longitude);
      addPolylinePoint(latLng);
      trackingPoints.add(latLng);
    }
  }

  void disableBackgroundMode() {
    _locationService.unregisterBackgroundUpdates();
    _positionStreamSubscription?.cancel();
  }

  void startLocationTracking() async {
    await setLocationSettings();

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
    );

    _positionStreamSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((Position position) {
      final latLng = LatLng(position.latitude, position.longitude);
      addPolylinePoint(latLng);
      trackingPoints.add(latLng);
    });
  }

  Future<void> saveTrackingData() async {
    if (trackingPoints.isEmpty) return;

    List<Map<String, double>> points = trackingPoints
        .map((point) =>
            {'latitude': point.latitude, 'longitude': point.longitude})
        .toList();

    String trackingData = json.encode({
      'points': points,
      'timestamp': DateTime.now().toIso8601String(),
    });

    await FlutterForegroundTask.saveData(
      key: 'last_tracking_data',
      value: trackingData,
    );
  }

  Future<List<LatLng>> getPolylinePoints(
      LatLng origin, LatLng destination) async {
    List<LatLng> polylineCoordinates = [];

    try {
      PolylineResult result = await _polylinePoints.getRouteBetweenCoordinates(
        request: PolylineRequest(
          origin: PointLatLng(origin.latitude, origin.longitude),
          destination: PointLatLng(destination.latitude, destination.longitude),
          mode: TravelMode.walking,
        ),
      );

      if (result.points.isNotEmpty) {
        for (var point in result.points) {
          polylineCoordinates.add(LatLng(point.latitude, point.longitude));
        }
      }
    } catch (e) {
      debugPrint('Error getting polyline points: $e');
    }

    return polylineCoordinates;
  }

  void addPolylinePoint(LatLng position) {
    if (_polylines.isEmpty) {
      _polylines.add(Polyline(
        polylineId: const PolylineId('tracking_route'),
        color: const Color.fromARGB(255, 0, 128, 4),
        width: 5,
        points: [position],
        jointType: JointType.round,
      ));
    } else {
      final polyline = _polylines.first;
      final updatedPoints = List<LatLng>.from(polyline.points)..add(position);
      _polylines.remove(polyline);
      _polylines.add(polyline.copyWith(pointsParam: updatedPoints));
    }
  }

  Set<Polyline> get polylines => _polylines;

  void animateCameraToPosition(LatLng position, {double zoom = 15.0}) {
    mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: position, zoom: zoom),
      ),
    );
  }

  void fitBounds(List<LatLng> points) {
    if (points.isEmpty) return;

    double minLat = points[0].latitude;
    double maxLat = points[0].latitude;
    double minLng = points[0].longitude;
    double maxLng = points[0].longitude;

    for (var point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        50.0,
      ),
    );
  }
}
