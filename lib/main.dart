import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: GeofenceMap(),
    );
  }
}

class GeofenceMap extends StatefulWidget {
  const GeofenceMap({super.key});

  @override
  _GeofenceMapState createState() => _GeofenceMapState();
}

class _GeofenceMapState extends State<GeofenceMap> {
  late GoogleMapController _mapController;
  final Set<Circle> _circles = {};
  final Set<Marker> _markers = {};
  LatLng? _currentPosition;
  bool _isButtonEnabled = false;

  final List<Map<String, dynamic>> _locations = [
    {'label': 'A', 'latLng': const LatLng(24.922022, 67.093269)},
    {'label': 'B', 'latLng': const LatLng(24.921022, 67.093269)},
    {'label': 'C', 'latLng': const LatLng(24.923022, 67.093269)},
  ];

  late LatLng _centerPoint;
  late double _radius;
  late Stream<Position> _locationStream;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    final status = await Permission.locationWhenInUse.request();

    if (status.isGranted) {
      _calculateCircle();
      _initializeMapElements();
      _startLocationUpdates();
    } else if (status.isDenied || status.isPermanentlyDenied) {
      _showPermissionDeniedDialog();
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Permission Denied"),
          content: const Text(
              "Location permission is required to use this feature. Please enable it in the app settings."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text("Open Settings"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text("Cancel"),
            ),
          ],
        );
      },
    );
  }

  void _calculateCircle() {
    double avgLat = 0.0;
    double avgLng = 0.0;
    for (var location in _locations) {
      avgLat += location['latLng'].latitude;
      avgLng += location['latLng'].longitude;
    }
    _centerPoint =
        LatLng(avgLat / _locations.length, avgLng / _locations.length);

    double maxDistance = 0.0;
    for (var location in _locations) {
      final distance = Geolocator.distanceBetween(
        _centerPoint.latitude,
        _centerPoint.longitude,
        location['latLng'].latitude,
        location['latLng'].longitude,
      );
      if (distance > maxDistance) {
        maxDistance = distance;
      }
    }
    _radius = maxDistance + 100;
  }

  void _initializeMapElements() {
    for (var location in _locations) {
      _markers.add(
        Marker(
          markerId: MarkerId(location['label']),
          position: location['latLng'],
          infoWindow: InfoWindow(title: location['label']),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );

      _circles.add(
        Circle(
          circleId: CircleId(location['label']),
          center: location['latLng'],
          radius: 50,
          strokeWidth: 2,
          strokeColor: Colors.green.withOpacity(0.6),
          fillColor: Colors.green.withOpacity(0.2),
        ),
      );
    }
  }

  void _startLocationUpdates() {
    _locationStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    );

    _locationStream.listen((Position position) {
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });
      _checkGeofence(_currentPosition!);
    });
  }

  void _checkGeofence(LatLng currentPosition) {
    try {
      bool isWithinGeofence = false;

      for (var location in _locations) {
        final distance = Geolocator.distanceBetween(
          currentPosition.latitude,
          currentPosition.longitude,
          location['latLng'].latitude,
          location['latLng'].longitude,
        );

        if (distance <= 50) {
          isWithinGeofence = true;
          break;
        }
      }

      setState(() {
        _isButtonEnabled = isWithinGeofence;
      });
    } catch (e) {
      _showErrorDialog("Error checking geofence: $e");
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Error"),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _locationStream.drain();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geofence Map'),
      ),
      body: _currentPosition == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _centerPoint,
                    zoom: 15,
                  ),
                  circles: _circles,
                  markers: _markers,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  onMapCreated: (controller) {
                    _mapController = controller;
                  },
                ),
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: ElevatedButton(
                    onPressed: _isButtonEnabled ? () {} : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _isButtonEnabled ? Colors.green : Colors.grey,
                    ),
                    child: const Text(
                      'Mark Attendance',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
