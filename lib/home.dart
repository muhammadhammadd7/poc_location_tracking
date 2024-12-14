import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'service/foreground_task_handler.dart';
import 'service/location_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool isTracking = false;
  Position? currentPosition;
  Position? lastStoredPosition;
  Timer? timer;
  int trackingDuration = 0;
  StreamSubscription? _eventSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initializeServices();
    _loadLastStoredLocation();
    _loadTimer();
    _checkTrackingStatus();
    requestPermissionForAndroid();
    _initializeEventStream();
  }

  void _initializeEventStream() {
    _eventSubscription = FlutterForegroundTask.receivePort?.listen((data) {
      if (data is Map) {
        if (data.containsKey('timer')) {
          setState(() {
            trackingDuration = data['timer'] as int;
          });
        }
        if (data.containsKey('location')) {
          final locationMap = data['location'] as Map<String, dynamic>;
          setState(() {
            currentPosition = Position.fromMap(locationMap);
            lastStoredPosition = currentPosition;
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
    _initForegroundTask();
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'location_tracker',
        channelName: 'Location Tracking Service',
        channelDescription:
            'This notification appears when location is being tracked',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.LOW,
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
        enableVibration: false,
        playSound: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> _loadLastStoredLocation() async {
    final locationData =
        await FlutterForegroundTask.getData<String>(key: 'last_location');
    if (locationData != null) {
      final locationMap = json.decode(locationData);
      setState(() {
        lastStoredPosition = Position.fromMap(locationMap);
      });
    }
  }

  Future<void> _loadTimer() async {
    final timerData = await FlutterForegroundTask.getData<String>(key: 'timer');
    setState(() {
      trackingDuration = int.tryParse(timerData ?? '0') ?? 0;
    });
  }

  Future<void> _saveTimer() async {
    await FlutterForegroundTask.saveData(
        key: 'timer', value: trackingDuration.toString());
  }

  Future<void> _checkTrackingStatus() async {
    final trackingData =
        await FlutterForegroundTask.getData<String>(key: 'is_tracking');
    bool wasTracking = trackingData == 'true';
    if (wasTracking) {
      _startTracking();
    }
  }

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

  void _startTracking() async {
    await FlutterForegroundTask.saveData(key: 'is_tracking', value: 'true');
    await FlutterForegroundTask.saveData(
        key: 'start_time', value: DateTime.now().toIso8601String());

    setState(() {
      isTracking = true;
      trackingDuration = 0;
    });

    // Start foreground service
    await FlutterForegroundTask.startService(
      notificationTitle: 'Location Tracking Active',
      notificationText: 'Timer: 00:00:00\nWaiting for location...',
      callback: startCallback,
    );

    _initializeEventStream();

    timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      trackingDuration++;
      _saveTimer();

      final position = await LocationService.getCurrentLocation();
      if (position != null) {
        setState(() {
          currentPosition = position;
        });

        final locationJson = json.encode(position.toJson());
        await FlutterForegroundTask.saveData(
            key: 'last_location', value: locationJson);
        setState(() {
          lastStoredPosition = position;
        });

        String notificationText = 'Timer: ${_formatDuration()}\n'
            'Latitude: ${position.latitude.toStringAsFixed(8)}\n'
            'Longitude: ${position.longitude.toStringAsFixed(8)}';

        await FlutterForegroundTask.updateService(
          notificationTitle: 'Location Tracking Active',
          notificationText: notificationText,
        );
      }
    });
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
      // Keep currentPosition to show last tracked location
    });

    await FlutterForegroundTask.stopService();
    _eventSubscription?.cancel();
    timer?.cancel();
    timer = null;
  }

  String _formatDuration() {
    final hours = (trackingDuration ~/ 3600).toString().padLeft(2, '0');
    final minutes =
        ((trackingDuration % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (trackingDuration % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
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
    return WithForegroundTask(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Live Location Tracker'),
          centerTitle: true,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _formatDuration(),
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isTracking ? _stopTracking : _startTracking,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isTracking ? Colors.red : Colors.green,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                ),
                child: Text(
                  isTracking ? 'Stop Tracking' : 'Start Tracking',
                  style: const TextStyle(fontSize: 18, color: Colors.white),
                ),
              ),
              const SizedBox(height: 30),
              if (isTracking && currentPosition != null) ...[
                const Icon(
                  Icons.location_on,
                  size: 50,
                  color: Colors.black,
                ),
                const SizedBox(height: 20),
                Text(
                  'LIVE LOCATION',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Current Location:\nLatitude: ${currentPosition!.latitude.toStringAsFixed(8)}\nLongitude: ${currentPosition!.longitude.toStringAsFixed(8)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (!isTracking && lastStoredPosition != null) ...[
                const SizedBox(height: 20),
                Text(
                  'Last Tracking Session',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Duration: ${_formatDuration()}\n\nLast Location:\nLatitude: ${lastStoredPosition!.latitude.toStringAsFixed(8)}\nLongitude: ${lastStoredPosition!.longitude.toStringAsFixed(8)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black,
                  ),
                ),
              ],
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
            ],
          ),
        ),
      ),
    );
  }
}




// import 'dart:async';
// import 'dart:convert';
// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:flutter_foreground_task/flutter_foreground_task.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'service/foreground_task_handler.dart';
// import 'service/location_service.dart';

// class HomeScreen extends StatefulWidget {
//   const HomeScreen({super.key});
//   @override
//   HomeScreenState createState() => HomeScreenState();
// }

// class HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
//   bool isTracking = false;
//   Position? currentPosition;
//   Position? lastStoredPosition;
//   Timer? timer;
//   int trackingDuration = 0;
//   StreamSubscription? _eventSubscription;
//   GoogleMapController? mapController;

//   final Set<Polyline> _polylines = {};
//   final List<LatLng> _polylineCoordinates = [];

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     initializeServices();
//     _loadLastStoredLocation();
//     _loadTimer();
//     _checkTrackingStatus();
//     requestPermissionForAndroid();
//     _initializeEventStream();
//   }

//   void _initializeEventStream() {
//     _eventSubscription = FlutterForegroundTask.receivePort?.listen((data) {
//       if (data is Map) {
//         if (data.containsKey('timer')) {
//           setState(() {
//             trackingDuration = data['timer'] as int;
//           });
//         }
//         if (data.containsKey('location')) {
//           final locationMap = data['location'] as Map<String, dynamic>;
//           setState(() {
//             currentPosition = Position.fromMap(locationMap);
//             lastStoredPosition = currentPosition;

//             // Update the polyline coordinates
//             _updatePolyline(LatLng(
//               currentPosition!.latitude,
//               currentPosition!.longitude,
//             ));
//           });
//         }
//       }
//     });
//   }

//   Future<void> initializeServices() async {
//     _initForegroundTask();
//   }

//   void _initForegroundTask() {
//     FlutterForegroundTask.init(
//       androidNotificationOptions: AndroidNotificationOptions(
//         channelId: 'location_tracker',
//         channelName: 'Location Tracking Service',
//         channelDescription:
//             'This notification appears when location is being tracked',
//         channelImportance: NotificationChannelImportance.HIGH,
//         priority: NotificationPriority.LOW,
//         visibility: NotificationVisibility.VISIBILITY_PUBLIC,
//         enableVibration: false,
//         playSound: false,
//       ),
//       iosNotificationOptions: const IOSNotificationOptions(
//         showNotification: true,
//         playSound: false,
//       ),
//       foregroundTaskOptions: ForegroundTaskOptions(
//         eventAction: ForegroundTaskEventAction.repeat(5000),
//         autoRunOnBoot: true,
//         allowWakeLock: true,
//         allowWifiLock: true,
//       ),
//     );
//   }

//   Future<void> _loadLastStoredLocation() async {
//     final locationData =
//         await FlutterForegroundTask.getData<String>(key: 'last_location');
//     if (locationData != null) {
//       final locationMap = json.decode(locationData);
//       setState(() {
//         lastStoredPosition = Position.fromMap(locationMap);

//         // Add last stored position to polyline
//         _updatePolyline(LatLng(
//           lastStoredPosition!.latitude,
//           lastStoredPosition!.longitude,
//         ));
//       });
//     }
//   }

//   Future<void> _loadTimer() async {
//     final timerData = await FlutterForegroundTask.getData<String>(key: 'timer');
//     setState(() {
//       trackingDuration = int.tryParse(timerData ?? '0') ?? 0;
//     });
//   }

//   Future<void> _saveTimer() async {
//     await FlutterForegroundTask.saveData(
//         key: 'timer', value: trackingDuration.toString());
//   }

//   Future<void> _checkTrackingStatus() async {
//     final trackingData =
//         await FlutterForegroundTask.getData<String>(key: 'is_tracking');
//     bool wasTracking = trackingData == 'true';
//     if (wasTracking) {
//       _startTracking();
//     }
//   }

//   Future<void> requestPermissionForAndroid() async {
//     if (!Platform.isAndroid) {
//       return;
//     }
//     if (!await FlutterForegroundTask.canDrawOverlays) {
//       await FlutterForegroundTask.openSystemAlertWindowSettings();
//     }
//     if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
//       await FlutterForegroundTask.requestIgnoreBatteryOptimization();
//     }
//     final NotificationPermission notificationPermissionStatus =
//         await FlutterForegroundTask.checkNotificationPermission();
//     if (notificationPermissionStatus != NotificationPermission.granted) {
//       await FlutterForegroundTask.requestNotificationPermission();
//     }
//   }

//   void _startTracking() async {
//     await FlutterForegroundTask.saveData(key: 'is_tracking', value: 'true');
//     await FlutterForegroundTask.saveData(
//         key: 'start_time', value: DateTime.now().toIso8601String());

//     setState(() {
//       isTracking = true;
//       trackingDuration = 0;
//     });

//     // Start foreground service
//     await FlutterForegroundTask.startService(
//       notificationTitle: 'Location Tracking Active',
//       notificationText: 'Timer: 00:00:00\nWaiting for location...',
//       callback: startCallback,
//     );

//     _initializeEventStream();

//     timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
//       trackingDuration++;
//       _saveTimer();

//       final position = await LocationService.getCurrentLocation();
//       if (position != null) {
//         setState(() {
//           currentPosition = position;

//           // Update polyline coordinates
//           _updatePolyline(LatLng(position.latitude, position.longitude));
//         });

//         final locationJson = json.encode(position.toJson());
//         await FlutterForegroundTask.saveData(
//             key: 'last_location', value: locationJson);
//         setState(() {
//           lastStoredPosition = position;
//         });

//         String notificationText = 'Timer: ${_formatDuration()}\n'
//             'Latitude: ${position.latitude.toStringAsFixed(8)}\n'
//             'Longitude: ${position.longitude.toStringAsFixed(8)}';

//         await FlutterForegroundTask.updateService(
//           notificationTitle: 'Location Tracking Active',
//           notificationText: notificationText,
//         );
//       }
//     });
//   }

//   void _stopTracking() async {
//     await _saveTimer();
//     if (currentPosition != null) {
//       final locationJson = json.encode(currentPosition!.toJson());
//       await FlutterForegroundTask.saveData(
//           key: 'last_location', value: locationJson);
//     }

//     await FlutterForegroundTask.saveData(key: 'is_tracking', value: 'false');
//     await FlutterForegroundTask.saveData(
//         key: 'background_tracking', value: 'false');

//     setState(() {
//       isTracking = false;
//     });

//     await FlutterForegroundTask.stopService();
//     _eventSubscription?.cancel();
//     timer?.cancel();
//     timer = null;
//   }

//   void _updatePolyline(LatLng position) {
//     setState(() {
//       _polylineCoordinates.add(position);
//       _polylines.add(Polyline(
//         polylineId: const PolylineId('tracking_route'),
//         color: Colors.blue,
//         width: 5,
//         points: _polylineCoordinates,
//       ));
//     });
//   }

//   String _formatDuration() {
//     final hours = (trackingDuration ~/ 3600).toString().padLeft(2, '0');
//     final minutes =
//         ((trackingDuration % 3600) ~/ 60).toString().padLeft(2, '0');
//     final seconds = (trackingDuration % 60).toString().padLeft(2, '0');
//     return '$hours:$minutes:$seconds';
//   }

//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     _eventSubscription?.cancel();
//     timer?.cancel();
//     if (!isTracking) {
//       FlutterForegroundTask.stopService();
//     }
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return WithForegroundTask(
//       child: Scaffold(
//         appBar: AppBar(
//           title: const Text('Live Location Tracker'),
//           centerTitle: true,
//         ),
//         body: Stack(
//           children: [
//             GoogleMap(
//               initialCameraPosition: CameraPosition(
//                 target: currentPosition != null
//                     ? LatLng(
//                         currentPosition!.latitude,
//                         currentPosition!.longitude,
//                       )
//                     : const LatLng(
//                         37.4219999, -122.0840575), // Default location
//                 zoom: 15,
//               ),
//               onMapCreated: (controller) {
//                 mapController = controller;
//               },
//               polylines: _polylines,
//               myLocationEnabled: true,
//             ),
//             Center(
//               child: Column(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   ElevatedButton(
//                     onPressed: isTracking ? _stopTracking : _startTracking,
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: isTracking ? Colors.red : Colors.green,
//                       padding: const EdgeInsets.symmetric(
//                           horizontal: 30, vertical: 15),
//                     ),
//                     child: Text(
//                       isTracking ? 'Stop Tracking' : 'Start Tracking',
//                       style: const TextStyle(fontSize: 18, color: Colors.white),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
