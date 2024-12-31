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
  bool _isInitialized = false;

  final List<Map<String, dynamic>> _locations = [
    {'label': 'A', 'latLng': const LatLng(24.922022, 67.093269)},
    {'label': 'B', 'latLng': const LatLng(24.921022, 67.093269)},
    {'label': 'C', 'latLng': const LatLng(24.923022, 67.093269)},
  ];

  late LatLng _centerPoint;
  late double _radius;

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
      setState(() {
        _isInitialized = true;
      });
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
          infoWindow: InfoWindow(title: ''),
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

  void _checkGeofence() async {
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    LatLng currentPosition = LatLng(position.latitude, position.longitude);

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

    if (isWithinGeofence) {
      print("Attendance Marked");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attendance Marked Successfully!')),
      );
    } else {
      _showErrorDialog("You are not within the premises!");
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geofence Map'),
      ),
      body: !_isInitialized
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
                  zoomControlsEnabled: false,
                  myLocationButtonEnabled: false,
                  mapToolbarEnabled:
                      false, // This removes the direction and Google Maps icons
                  onMapCreated: (controller) {
                    _mapController = controller;
                  },
                ),
                Positioned(
                  bottom: 20,
                  left: 60,
                  right: 60,
                  child: ElevatedButton(
                    onPressed: _checkGeofence,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 21, 99, 23),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
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
