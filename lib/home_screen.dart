import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location_service/saved_trail_screen.dart';
import 'service/foreground_task_handler.dart';
import 'service/location_service.dart';
import 'service/map_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  bool isTracking = false;
  bool isRecording = false;
  bool isPaused = false;
  Position? currentPosition;
  Position? lastStoredPosition;
  Timer? timer;
  StreamSubscription? _eventSubscription;
  final MapService _mapService = MapService();
  late AnimationController _controller;
  late Animation<double> _widthAnimation;
  bool isRowOpen = false;
  List<LatLng> trackingPoints = [];
  Set<Marker> markers = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initializeServices();
    _loadLastStoredLocation();
    _saveTrackingData();
    // _loadTimer();
    _mapService.loadSavedTrackingData();
    _checkTrackingStatus();
    requestPermissionsAndroid();
    requestPermissionsIOS();
    _initializeEventStream();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _widthAnimation = Tween<double>(begin: 0.0, end: 300.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  void toggleRow() {
    setState(() {
      if (isRowOpen) {
        _controller.reverse();
      } else {
        _controller.forward();
      }
      isRowOpen = !isRowOpen;
    });

    if (isRecording) {
      setState(() {
        isPaused = !isPaused;
        if (isPaused) {
          _pauseTracking();
        } else {
          _resumeTracking();
        }
      });
    }
  }

  void closeRow() {
    if (isRowOpen) {
      _controller.reverse();
      setState(() {
        isRowOpen = false;
      });
    }
  }

  void requestPermissionsAndroid() async {
    await LocationService().requestPermissionForAndroid();
  }

  void requestPermissionsIOS() async {
    await LocationService().requestPermissionsForiOS();
  }

  void _initializeEventStream() {
    _eventSubscription = FlutterForegroundTask.receivePort?.listen((data) {
      if (data is Map) {
        if (data.containsKey('timer')) {
          setState(() {
            LocationService().trackingDuration = data['timer'] as int;
          });
        }
        if (data.containsKey('location') && !isPaused) {
          final locationMap = data['location'] as Map<String, dynamic>;
          setState(() {
            currentPosition = Position.fromMap(locationMap);
            lastStoredPosition = currentPosition;

            if (currentPosition != null) {
              LatLng point =
                  LatLng(currentPosition!.latitude, currentPosition!.longitude);
              trackingPoints.add(point);
              _mapService.addPolylinePoint(point);
            }
          });
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (isTracking) {
        FlutterForegroundTask.saveData(
            key: 'background_tracking', value: 'true');
        FlutterForegroundTask.saveData(
            key: 'is_paused', value: isPaused.toString());
      }
    }
  }

  Future<void> initializeServices() async {
    LocationTrackingHandler handler = LocationTrackingHandler();
    handler.initForegroundTask();
    handler.requestOverlayPermission();
  }

  // Future<void> _loadLastStoredLocation() async {
  //   final locationData =
  //       await FlutterForegroundTask.getData<String>(key: 'last_location');
  //   if (locationData != null) {
  //     final locationMap = json.decode(locationData);
  //     setState(() {
  //       lastStoredPosition = Position.fromMap(locationMap);
  //       if (lastStoredPosition != null) {
  //         LatLng point = LatLng(
  //             lastStoredPosition!.latitude, lastStoredPosition!.longitude);
  //         trackingPoints.add(point);
  //         _mapService.addPolylinePoint(point);
  //       }
  //     });
  //   }
  // }

  Future<void> _loadLastStoredLocation() async {
    final locationData =
        await FlutterForegroundTask.getData<String>(key: 'tracking_points');
    if (locationData != null) {
      final locationMap = json.decode(locationData);

      if (kDebugMode) {
        print('============================================');
        print(locationMap);
        print('=======================================');
      }

      setState(() {
        // Check if locationMap is a list
        if (locationMap is List) {
          trackingPoints = locationMap
              .map((point) => LatLng(
                    point['latitude'] is double
                        ? point['latitude']
                        : double.parse(point['latitude'].toString()),
                    point['longitude'] is double
                        ? point['longitude']
                        : double.parse(point['longitude'].toString()),
                  ))
              .toList();
        } else if (locationMap is Map) {
          // If it's a map, handle it accordingly
          // Example: {"points": [{latitude: 12.3456, longitude: 78.9101}, ...]}
          var points = locationMap['points'] as List?;
          if (points != null) {
            trackingPoints = points
                .map((point) => LatLng(
                      point['latitude'] is double
                          ? point['latitude']
                          : double.parse(point['latitude'].toString()),
                      point['longitude'] is double
                          ? point['longitude']
                          : double.parse(point['longitude'].toString()),
                    ))
                .toList();
          }
        }

        if (kDebugMode) {
          print('===== | trackingPoints.length | =====');
          print(trackingPoints.length);
          print('===== | trackingPoints.length | =====');
        }
      });
    }
  }

  // Future<void> _loadTimer() async {
  //   final timerData = await FlutterForegroundTask.getData<String>(key: 'timer');
  //   setState(() {
  //     LocationService().trackingDuration = int.tryParse(timerData ?? '0') ?? 0;
  //   });
  // }

  // Future<void> _saveTimer() async {
  //   await FlutterForegroundTask.saveData(
  //       key: 'timer', value: LocationService().trackingDuration.toString());
  // }

  Future<void> _checkTrackingStatus() async {
    final trackingData =
        await FlutterForegroundTask.getData<String>(key: 'is_tracking');
    final pausedData =
        await FlutterForegroundTask.getData<String>(key: 'is_paused');

    bool wasTracking = trackingData == 'true';
    bool wasPaused = pausedData == 'true';

    if (wasTracking) {
      setState(() {
        isTracking = true;
        isRecording = true;
        isPaused = wasPaused;
      });

      if (!wasPaused) {
        _startTracking();
      } else {
        _updateNotificationForPausedState();
      }
    }
  }

  void _startTracking() async {
    // Clear previous tracking data
    _mapService.setLocationSettings();
    trackingPoints.clear();

    await FlutterForegroundTask.saveData(key: 'is_tracking', value: 'true');
    await FlutterForegroundTask.saveData(key: 'is_paused', value: 'false');
    await FlutterForegroundTask.saveData(
        key: 'start_time', value: DateTime.now().toIso8601String());

    setState(() {
      isTracking = true;
      isRecording = true;
      isPaused = false;
      LocationService().trackingDuration = 0;
    });

    await FlutterForegroundTask.startService(
      notificationTitle: 'Location Tracking Active',
      notificationText: 'Timer: 00:00:00\nTracking in progress...',
      callback: startCallback,
    );

    _initializeEventStream();
    _startLocationUpdates();
  }

  void _startLocationUpdates() {
    timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!isPaused) {
        LocationService().trackingDuration++;
        // _saveTimer();

        final position = await LocationService.getCurrentLocation();
        // print('Position: ${position?.latitude} ${position?.longitude}');
        if (position != null) {
          setState(() {
            currentPosition = position;
            LatLng point = LatLng(position.latitude, position.longitude);
            trackingPoints.add(point);
            trackingPoints.toSet().toList();
            _mapService.addPolylinePoint(point);
          });
          await FlutterForegroundTask.saveData(
            key: 'tracking_points',
            value: json.encode(trackingPoints),
          );
          await FlutterForegroundTask.saveData(
              key: 'last_location', value: json.encode(position.toJson()));

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
      }
    });
  }

  void _pauseTracking() async {
    setState(() {
      isPaused = true;
    });

    await FlutterForegroundTask.saveData(key: 'is_paused', value: 'true');
    _updateNotificationForPausedState();
  }

  void _updateNotificationForPausedState() async {
    String notificationText = 'Timer: ${LocationService().formatDuration()}\n'
        'Tracking paused';

    await FlutterForegroundTask.updateService(
      notificationTitle: 'Location Tracking Paused',
      notificationText: notificationText,
    );
  }

  void _resumeTracking() async {
    setState(() {
      isPaused = false;
    });

    await FlutterForegroundTask.saveData(key: 'is_paused', value: 'false');

    final position = await LocationService.getCurrentLocation();
    if (position != null) {
      setState(() {
        currentPosition = position;
        LatLng point = LatLng(position.latitude, position.longitude);
        trackingPoints.add(point);
        _mapService.addPolylinePoint(point);
      });

      String notificationText = 'Timer: ${LocationService().formatDuration()}\n'
          'Tracking resumed\n'
          'Lat: ${position.latitude.toStringAsFixed(6)}, '
          'Lng: ${position.longitude.toStringAsFixed(6)}';

      await FlutterForegroundTask.updateService(
        notificationTitle: 'Location Tracking Active',
        notificationText: notificationText,
      );
    }
  }

  void _stopTracking() async {
    final String? trackingPointsStr =
        await FlutterForegroundTask.getData(key: 'tracking_points');

    Map<String, dynamic> trackingData = {};

    if (trackingPointsStr != null) {
      try {
        final List<dynamic> points = json.decode(trackingPointsStr);

        if (points.isNotEmpty) {
          // Get start and end points
          final startPoint = points.first;
          final endPoint = points.last;

          trackingData = {
            'points': points,
            'duration': LocationService().trackingDuration,
            'timestamp': DateTime.now().toIso8601String(),
            'startMarker': {
              'latitude': startPoint['latitude'],
              'longitude': startPoint['longitude']
            },
            'endMarker': {
              'latitude': endPoint['latitude'],
              'longitude': endPoint['longitude']
            }
          };
        }
      } catch (e) {
        debugPrint('Error preparing tracking data: $e');
      }
    }

    // Clear tracking state
    await FlutterForegroundTask.saveData(key: 'is_tracking', value: 'false');
    await FlutterForegroundTask.saveData(key: 'is_paused', value: 'false');
    await FlutterForegroundTask.saveData(
        key: 'background_tracking', value: 'false');

    setState(() {
      isTracking = false;
      isRecording = false;
      isPaused = false;
      trackingPoints.clear();
      markers.clear();
    });

    // Stop all services and subscriptions
    await FlutterForegroundTask.stopService();
    _eventSubscription?.cancel();
    timer?.cancel();
    timer = null;

    // Navigate to SavedTrailScreen with the collected data
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SavedTrailScreen(
          trackingData: trackingData,
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _saveTrackingData() async {
    Map<String, dynamic> trackingData = {};

    if (trackingPoints.isNotEmpty) {
      // Add start and end markers
      LatLng startPoint = trackingPoints.first;
      LatLng endPoint = trackingPoints.last;

      // Convert points to serializable format
      List<Map<String, double>> points = trackingPoints
          .map((point) =>
              {'latitude': point.latitude, 'longitude': point.longitude})
          .toList();

      // Create tracking data
      trackingData = {
        'points': points,
        'duration': LocationService().trackingDuration,
        'timestamp': DateTime.now().toIso8601String(),
        'startMarker': {
          'latitude': startPoint.latitude,
          'longitude': startPoint.longitude
        },
        'endMarker': {
          'latitude': endPoint.latitude,
          'longitude': endPoint.longitude
        }
      };

      // Save to FlutterForegroundTask storage

      // await FlutterForegroundTask.saveData(
      //   key: 'last_tracking_data',
      //   value: json.encode(trackingData),
      // );
      await FlutterForegroundTask.saveData(
        key: 'tracking_points',
        value: json.encode(trackingPoints),
      );
    }

    return trackingData;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _eventSubscription?.cancel();
    timer?.cancel();
    if (!isTracking) {
      FlutterForegroundTask.stopService();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: closeRow,
      child: WithForegroundTask(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Location Tracker'),
            centerTitle: true,
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          body: Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: currentPosition != null
                      ? LatLng(
                          currentPosition!.latitude, currentPosition!.longitude)
                      : const LatLng(37.4219999, -122.0840575),
                  zoom: 15,
                ),
                onMapCreated: _mapService.onMapCreated,
                polylines: _mapService.polylines,
                markers: markers,
                myLocationEnabled: true,
              ),
              if (isRecording)
                AnimatedBuilder(
                  animation: _widthAnimation,
                  builder: (context, child) {
                    return Positioned(
                      left: 0,
                      top: MediaQuery.of(context).size.height / 1.5 - 30,
                      child: isRowOpen
                          ? GestureDetector(
                              onTap: () {},
                              child: Container(
                                width: _widthAnimation.value,
                                height: 50,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.horizontal(
                                    right: Radius.circular(10),
                                  ),
                                ),
                                child: GestureDetector(
                                  onHorizontalDragEnd: (details) {
                                    if (details.primaryVelocity! < 0) {
                                      closeRow();
                                    }
                                  },
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: SizedBox(
                                          height: double.infinity,
                                          child: TextButton(
                                            onPressed: () {
                                              if (isPaused) {
                                                _resumeTracking();
                                              } else {
                                                _pauseTracking();
                                              }
                                            },
                                            style: TextButton.styleFrom(
                                              backgroundColor: isPaused
                                                  ? Colors.green
                                                  : Colors.orange,
                                              foregroundColor: Colors.white,
                                              shape:
                                                  const RoundedRectangleBorder(
                                                borderRadius: BorderRadius.zero,
                                              ),
                                            ),
                                            child: Text(
                                                isPaused ? "Resume" : "Pause",
                                                style: const TextStyle(
                                                    fontSize: 16)),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: SizedBox(
                                          height: double.infinity,
                                          child: TextButton(
                                            onPressed: _stopTracking,
                                            style: TextButton.styleFrom(
                                              backgroundColor: Colors.red,
                                              foregroundColor: Colors.white,
                                              shape:
                                                  const RoundedRectangleBorder(
                                                borderRadius: BorderRadius.only(
                                                  topRight: Radius.circular(10),
                                                  bottomRight:
                                                      Radius.circular(10),
                                                ),
                                              ),
                                            ),
                                            child: const Text("Finish",
                                                style: TextStyle(fontSize: 16)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : GestureDetector(
                              onTap: toggleRow,
                              child: Container(
                                width: 60,
                                height: 60,
                                decoration: const BoxDecoration(
                                  color: Color.fromARGB(255, 255, 255, 255),
                                  borderRadius: BorderRadius.horizontal(
                                    right: Radius.circular(30),
                                  ),
                                ),
                                child: Icon(
                                  isPaused ? Icons.play_arrow : Icons.pause,
                                  color:
                                      isPaused ? Colors.green : Colors.orange,
                                  size: 30,
                                ),
                              ),
                            ),
                    );
                  },
                ),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (isTracking && currentPosition != null) ...[
                      Text(
                        'Current Location:\nLatitude: ${currentPosition!.latitude.toStringAsFixed(8)}\nLongitude: ${currentPosition!.longitude.toStringAsFixed(8)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    Text(
                      LocationService().formatDuration(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (isTracking && currentPosition == null)
                      const Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 20),
                          Text(
                            'Getting your location...',
                            style: TextStyle(fontSize: 18),
                          ),
                        ],
                      ),
                    const SizedBox(height: 15),
                    Center(
                      child: !isRecording
                          ? ElevatedButton(
                              onPressed: _startTracking,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 70, vertical: 15),
                              ),
                              child: const Text(
                                'Start Recording',
                                style: TextStyle(
                                    fontSize: 18, color: Colors.white),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
