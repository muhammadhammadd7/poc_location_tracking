import 'package:flutter/material.dart';
import 'package:overlay_support/overlay_support.dart';
import 'home_screen.dart';
import 'service/trail_sharing_service.dart';
import 'shared_trail_screen.dart';

void main() {
  runApp(const OverlaySupport.global(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: Builder(
        builder: (context) {
          // Initialize deep linking
          TrailSharingService().initDeepLinking(context);
          return const HomeScreen();
        },
      ),
      routes: {
        '/shared-trail': (context) => const SavedTrailScreen(),
      },
    );
  }
}
