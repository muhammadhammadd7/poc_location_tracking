import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initializeServices();
    _loadLastStoredLocation();
    _loadTimer();
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
          // Pause recording
          timer?.cancel();
          FlutterForegroundTask.stopService();
        } else {
          // Resume recording
          _startTracking();
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

  ////
  // Request permissions for Android and IOS
  ////
  void requestPermissionsAndroid() async {
    await LocationService().requestPermissionForAndroid();
  }

  void requestPermissionsIOS() async {
    await LocationService().requestPermissionsForiOS();
  }

  ////
  // Initialize the event stream
  ////
  void _initializeEventStream() {
    _eventSubscription = FlutterForegroundTask.receivePort?.listen((data) {
      if (data is Map) {
        if (data.containsKey('timer')) {
          setState(() {
            LocationService().trackingDuration = data['timer'] as int;
          });
        }
        if (data.containsKey('location')) {
          final locationMap = data['location'] as Map<String, dynamic>;
          setState(() {
            currentPosition = Position.fromMap(locationMap);
            lastStoredPosition = currentPosition;

            // Update the polyline coordinates using MapService
            _mapService.addPolylinePoint(LatLng(
              currentPosition!.latitude,
              currentPosition!.longitude,
            ));
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
      }
    }
  }

  Future<void> initializeServices() async {
    ////
    // Initialize the foreground task configuration
    ////
    LocationTrackingHandler().initForegroundTask();
    ////
    // Start the foreground service
    ////
    await FlutterForegroundTask.startService(
      notificationTitle: 'Location Tracking Active',
      notificationText: 'Initializing...',
      callback: startCallback,
    );
  }

  Future<void> _loadLastStoredLocation() async {
    final locationData =
        await FlutterForegroundTask.getData<String>(key: 'last_location');
    if (locationData != null) {
      final locationMap = json.decode(locationData);
      setState(() {
        lastStoredPosition = Position.fromMap(locationMap);

        // Add last stored position to polyline using MapService
        _mapService.addPolylinePoint(LatLng(
          lastStoredPosition!.latitude,
          lastStoredPosition!.longitude,
        ));
      });
    }
  }

  Future<void> _loadTimer() async {
    final timerData = await FlutterForegroundTask.getData<String>(key: 'timer');
    setState(() {
      LocationService().trackingDuration = int.tryParse(timerData ?? '0') ?? 0;
    });
  }

  Future<void> _saveTimer() async {
    await FlutterForegroundTask.saveData(
        key: 'timer', value: LocationService().trackingDuration.toString());
  }

  Future<void> _checkTrackingStatus() async {
    final trackingData =
        await FlutterForegroundTask.getData<String>(key: 'is_tracking');
    bool wasTracking = trackingData == 'true';
    if (wasTracking) {
      _startTracking();
    }
  }

  void _startTracking() async {
    await FlutterForegroundTask.saveData(key: 'is_tracking', value: 'true');
    await FlutterForegroundTask.saveData(
        key: 'start_time', value: DateTime.now().toIso8601String());

    setState(() {
      isTracking = true;
      isRecording = true;
      isPaused = false;
      LocationService().trackingDuration = 0;
    });

    // Start foreground service
    await FlutterForegroundTask.startService(
      notificationTitle: 'Location Tracking Active',
      notificationText: 'Timer: 00:00:00\nWaiting for location...',
      callback: startCallback,
    );

    _initializeEventStream();

    timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      LocationService().trackingDuration++;
      _saveTimer();

      final position = await LocationService.getCurrentLocation();
      if (position != null) {
        setState(() {
          currentPosition = position;

          // Update polyline coordinates using MapService
          _mapService
              .addPolylinePoint(LatLng(position.latitude, position.longitude));
        });

        final locationJson = json.encode(position.toJson());
        await FlutterForegroundTask.saveData(
            key: 'last_location', value: locationJson);
        setState(() {
          lastStoredPosition = position;
        });

        String notificationText =
            'Timer: ${LocationService().formatDuration()}\n'
            'Latitude: ${position.latitude.toStringAsFixed(8)}\n'
            'Longitude: ${position.longitude.toStringAsFixed(8)}';

        await FlutterForegroundTask.updateService(
          notificationTitle: 'Location Tracking Active',
          notificationText: notificationText,
        );
      }
    });
  }

  void _resumeTracking() async {
    // Get current location and add marker
    final position = await LocationService.getCurrentLocation();
    if (position != null) {
      setState(() {
        currentPosition = position;
        lastStoredPosition = position;
        isTracking = true;
        isPaused = false;

        // Add marker and polyline point at resume position
        _mapService
            .addPolylinePoint(LatLng(position.latitude, position.longitude));
      });

      // Save current location
      final locationJson = json.encode(position.toJson());
      await FlutterForegroundTask.saveData(
          key: 'last_location', value: locationJson);

      // Update tracking status
      await FlutterForegroundTask.saveData(key: 'is_tracking', value: 'true');

      // Resume timer
      timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
        LocationService().trackingDuration++;
        _saveTimer();

        final newPosition = await LocationService.getCurrentLocation();
        if (newPosition != null) {
          setState(() {
            currentPosition = newPosition;
            _mapService.addPolylinePoint(
                LatLng(newPosition.latitude, newPosition.longitude));
          });

          final newLocationJson = json.encode(newPosition.toJson());
          await FlutterForegroundTask.saveData(
              key: 'last_location', value: newLocationJson);

          String notificationText =
              'Timer: ${LocationService().formatDuration()}\n'
              'Latitude: ${newPosition.latitude.toStringAsFixed(8)}\n'
              'Longitude: ${newPosition.longitude.toStringAsFixed(8)}';

          await FlutterForegroundTask.updateService(
            notificationTitle: 'Location Tracking Active',
            notificationText: notificationText,
          );
        }
      });
    }
  }

  void _stopTracking() async {
    // Save final timer and location before stopping
    await _saveTimer();
    if (currentPosition != null) {
      final locationJson = json.encode(currentPosition!.toJson());
      await FlutterForegroundTask.saveData(
          key: 'last_location', value: locationJson);
    }

    await FlutterForegroundTask.saveData(key: 'is_tracking', value: 'false');
    await FlutterForegroundTask.saveData(
        key: 'background_tracking', value: 'false');

    setState(() {
      isTracking = false;
      isPaused = false;
    });

    await FlutterForegroundTask.stopService();
    _eventSubscription?.cancel();
    timer?.cancel();
    timer = null;
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
            title: const Text('Live Location Tracker'),
            centerTitle: true,
          ),
          body: Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: currentPosition != null
                      ? LatLng(
                          currentPosition!.latitude,
                          currentPosition!.longitude,
                        )
                      : const LatLng(
                          37.4219999, -122.0840575), // Default location
                  zoom: 15,
                ),
                onMapCreated: _mapService.onMapCreated,
                polylines: _mapService.polylines,
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
                                      // Left swipe
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
                                              if (kDebugMode) {
                                                print("Resume button pressed");
                                              }
                                              _resumeTracking();
                                            },
                                            style: TextButton.styleFrom(
                                              backgroundColor: Colors.green,
                                              foregroundColor: Colors.white,
                                              shape:
                                                  const RoundedRectangleBorder(
                                                borderRadius: BorderRadius.zero,
                                              ),
                                            ),
                                            child: const Text("Resume",
                                                style: TextStyle(fontSize: 16)),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: SizedBox(
                                          height: double.infinity,
                                          child: TextButton(
                                            onPressed: () {
                                              if (kDebugMode) {
                                                print("Finish button pressed");
                                              }
                                              _stopTracking();
                                            },
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
                                  child: const Icon(Icons.fiber_manual_record,
                                      color: Colors.red)),
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
                    const SizedBox(
                      height: 20,
                    ),
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
