import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const GeofenceMap(),
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
  final Set<Circle> _circles = {}; // Set of circles around markers
  final Set<Marker> _markers = {}; // Set of markers
  LatLng? _currentPosition;
  bool _isButtonEnabled = false; // Track if button should be enabled

  // Hardcoded coordinates for testing
  final List<Map<String, dynamic>> _locations = [
    {
      'label': 'A',
      'latLng': const LatLng(24.922022, 67.093269)
    }, // Near Bahadurabad, Karachi
    {'label': 'B', 'latLng': const LatLng(24.921022, 67.093269)}, // Close to A
    {
      'label': 'C',
      'latLng': const LatLng(24.923022, 67.093269)
    }, // Close to both A and B
  ];

  late LatLng _centerPoint; // Center of the circle
  late double _radius; // Radius of the circle
  late Stream<Position> _locationStream; // Stream for location updates

  @override
  void initState() {
    super.initState();
    _calculateCircle();
    _initializeMapElements();
    _startLocationUpdates();
  }

  void _calculateCircle() {
    // Calculate center point as the average latitude and longitude of all coordinates
    double avgLat = 0.0;
    double avgLng = 0.0;
    for (var location in _locations) {
      avgLat += location['latLng'].latitude;
      avgLng += location['latLng'].longitude;
    }
    _centerPoint =
        LatLng(avgLat / _locations.length, avgLng / _locations.length);

    // Calculate the maximum distance from the center point to any coordinate
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
    _radius = maxDistance + 100; // Add padding to the radius
  }

  void _initializeMapElements() {
    // Initialize markers and circles for A, B, C
    for (var location in _locations) {
      // Add marker
      _markers.add(
        Marker(
          markerId: MarkerId(location['label']),
          position: location['latLng'],
          infoWindow: InfoWindow(title: location['label']),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );

      // Add circle with a 50-meter radius around the marker
      _circles.add(
        Circle(
          circleId: CircleId(location['label']),
          center: location['latLng'],
          radius: 50, // 50 meters radius
          strokeWidth: 2,
          strokeColor: Colors.green.withOpacity(0.6),
          fillColor: Colors.green.withOpacity(0.2),
        ),
      );
    }
  }

  // Start location updates
  void _startLocationUpdates() {
    _locationStream = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update location if the user moves 10 meters
      ),
    );

    _locationStream.listen((Position position) {
      // Update current position and check geofence on every location update
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });
      _checkGeofence(_currentPosition!);
    });
  }

  void _checkGeofence(LatLng currentPosition) {
    try {
      bool isWithinGeofence =
          false; // Track if the location is within any marker's radius

      // Loop through each marker and check if the current location is within 50 meters
      for (var location in _locations) {
        final distance = Geolocator.distanceBetween(
          currentPosition.latitude,
          currentPosition.longitude,
          location['latLng'].latitude,
          location['latLng'].longitude,
        );

        // Debugging: Print the calculated distance
        print('Distance to ${location['label']}: $distance meters');

        if (distance <= 50) {
          // 50 meters radius check
          isWithinGeofence = true;
          break; // Exit the loop if within any marker's 50-meter radius
        }
      }

      setState(() {
        _isButtonEnabled =
            isWithinGeofence; // Enable button only if within any marker's radius
        print('Button Enabled: $_isButtonEnabled'); // Debugging state change
      });

      if (isWithinGeofence) {
        _triggerGeofenceAction('One of the markers');
      }
    } catch (e) {
      _showErrorDialog("Error checking geofence: $e");
    }
  }

  void _triggerGeofenceAction(String label) {
    try {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text("Geofence Alert"),
            content: Text("You have entered the geofence for location $label."),
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
    } catch (e) {
      _showErrorDialog("Error triggering geofence action: $e");
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
    super.dispose();
    _locationStream
        .drain(); // Stop listening for location updates when the widget is disposed
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
                  circles: _circles, // Circle set with 50-meter radius
                  markers: _markers,
                  myLocationEnabled:
                      true, // Show the blue dot for live location
                  myLocationButtonEnabled:
                      false, // Optionally hide the "My Location" button
                  onMapCreated: (controller) {
                    _mapController = controller;
                  },
                ),
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: ElevatedButton(
                    onPressed: _isButtonEnabled
                        ? () {
                            // Handle attendance logic here
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isButtonEnabled
                          ? Colors.green
                          : Colors
                              .grey, // Use backgroundColor instead of primary
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
