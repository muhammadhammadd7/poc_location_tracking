// import 'package:flutter/material.dart';
// import 'home.dart';

// void main() {
//   runApp(const MyApp());
// }

// class MyApp extends StatelessWidget {
//   const MyApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return const MaterialApp(
//       debugShowCheckedModeBanner: false,
//       home: HomeScreen(),
//     );
//   }
// }
import 'dart:async';
import 'dart:isolate';
import 'dart:ui';
import 'package:background_locator_2/background_locator.dart';
import 'package:background_locator_2/location_dto.dart';
import 'package:background_locator_2/settings/android_settings.dart';
import 'package:background_locator_2/settings/ios_settings.dart';
import 'package:background_locator_2/settings/locator_settings.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ReceivePort port = ReceivePort();
  bool isRunning = false;
  String logStr = '';
  LocationDto? lastLocation;

  @override
  void initState() {
    super.initState();

    if (IsolateNameServer.lookupPortByName('LocatorIsolate') != null) {
      IsolateNameServer.removePortNameMapping('LocatorIsolate');
    }

    IsolateNameServer.registerPortWithName(port.sendPort, 'LocatorIsolate');

    port.listen((dynamic data) {
      setState(() {
        lastLocation = LocationDto.fromJson(data);
      });
    });

    initPlatformState();
  }

  Future<void> initPlatformState() async {
    print('Initializing...');
    await BackgroundLocator.initialize();
    final isRunning = await BackgroundLocator.isServiceRunning();
    setState(() {
      this.isRunning = isRunning;
    });
    print('Initialization done');
  }

  Future<bool> checkPermissions() async {
    if (await Permission.locationAlways.isGranted) {
      return true;
    } else {
      final result = await Permission.locationAlways.request();
      return result.isGranted;
    }
  }

  Future<void> startLocator() async {
    if (await checkPermissions()) {
      BackgroundLocator.registerLocationUpdate(
        (LocationDto location) {
          setState(() {
            lastLocation = location;
          });
        },
        iosSettings: const IOSSettings(
          accuracy: LocationAccuracy.NAVIGATION,
          distanceFilter: 0,
          stopWithTerminate: true,
        ),
        androidSettings: const AndroidSettings(
          accuracy: LocationAccuracy.NAVIGATION,
          interval: 5,
          distanceFilter: 0,
          client: LocationClient.google,
          androidNotificationSettings: AndroidNotificationSettings(
            notificationChannelName: 'Location Tracking',
            notificationTitle: 'Background Locator',
            notificationMsg: 'Tracking your location in the background',
            notificationIcon: '',
          ),
        ),
      );

      setState(() {
        isRunning = true;
      });
    } else {
      print('Permission denied');
    }
  }

  Future<void> stopLocator() async {
    await BackgroundLocator.unRegisterLocationUpdate();
    setState(() {
      isRunning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Background Locator')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Is Running: $isRunning'),
              ElevatedButton(
                onPressed: isRunning ? null : startLocator,
                child: const Text('Start Location Tracking'),
              ),
              ElevatedButton(
                onPressed: isRunning ? stopLocator : null,
                child: const Text('Stop Location Tracking'),
              ),
              if (lastLocation != null)
                Text(
                  'Last Location: ${lastLocation!.latitude}, ${lastLocation!.longitude}',
                ),
            ],
          ),
        ),
      ),
    );
  }
}
