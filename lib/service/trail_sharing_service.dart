import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

class TrailSharingService {
  static const String APP_SCHEME = 'locationtracker';
  static const String APP_HOST = 'trail';

  // Singleton instance
  static final TrailSharingService _instance = TrailSharingService._internal();
  factory TrailSharingService() => _instance;
  TrailSharingService._internal();

  final _appLinks = AppLinks();

  // Initialize deep linking
  void initDeepLinking(BuildContext context) {
    _appLinks.uriLinkStream.listen((uri) {
      handleIncomingLink(context, uri);
    });
  }

  // Generate a shareable link for a trail
  Future<String> generateTrailLink(String trailId) async {
    return '$APP_SCHEME://$APP_HOST?id=$trailId';
  }

  // Format trail details for sharing
  String _formatTrailDetails(Map<String, dynamic> decodedData) {
    final timestamp = DateTime.parse(decodedData['timestamp']);
    final formattedDate = DateFormat('MMM d, yyyy').format(timestamp);
    final formattedTime = DateFormat('h:mm a').format(timestamp);

    final points = decodedData['points'] as List;
    final distance = _calculateTotalDistance(points);
    final duration = Duration(seconds: decodedData['duration'] ?? 0);

    return '''
🏃‍♂️ Trail Details:
📅 Date: $formattedDate
⏰ Time: $formattedTime
📏 Distance: ${distance.toStringAsFixed(2)} km
⏱️ Duration: ${_formatDuration(duration)}''';
  }

  // Calculate total distance of the trail
  double _calculateTotalDistance(List<dynamic> points) {
    double totalDistance = 0;
    for (int i = 0; i < points.length - 1; i++) {
      final start = LatLng(
        points[i]['latitude'] as double,
        points[i]['longitude'] as double,
      );
      final end = LatLng(
        points[i + 1]['latitude'] as double,
        points[i + 1]['longitude'] as double,
      );
      totalDistance += _calculateDistance(start, end);
    }
    return totalDistance;
  }

  // Calculate distance between two points
  double _calculateDistance(LatLng start, LatLng end) {
    return Geolocator.distanceBetween(
          start.latitude,
          start.longitude,
          end.latitude,
          end.longitude,
        ) /
        1000; // Convert to kilometers
  }

  // Format duration
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  // Share the trail with others
  Future<void> shareTrail(BuildContext context) async {
    final trailData =
        await FlutterForegroundTask.getData(key: 'last_tracking_data');
    if (trailData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No trail data available to share')),
      );
      return;
    }

    final decodedData = json.decode(trailData);
    final trailId = base64Encode(utf8.encode(json.encode({
      'timestamp': decodedData['timestamp'],
      'points': decodedData['points'],
      'duration': decodedData['duration'],
    })));

    final link = await generateTrailLink(trailId);
    final trailDetails = _formatTrailDetails(decodedData);

    final message = '''
🌟 Check out my trail! 🌟

$trailDetails

📱 View my trail:
$link

📥 Don't have the app? Download it now:
• Android: [Play Store Link]
• iOS: [App Store Link]''';

    await Share.share(message, subject: 'Check out my trail!');
  }

  // Handle incoming shared links
  Future<void> handleIncomingLink(BuildContext context, Uri? uri) async {
    if (uri == null || uri.scheme != APP_SCHEME || uri.host != APP_HOST) return;

    final trailId = uri.queryParameters['id'];
    if (trailId == null) return;

    try {
      final decodedData = json.decode(utf8.decode(base64Decode(trailId)));

      await FlutterForegroundTask.saveData(
          key: 'shared_trail_data', value: json.encode(decodedData));

      // Show success notification
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trail loaded successfully!')),
      );

      // Navigate to the shared trail view
      Navigator.pushNamed(context, '/shared-trail');
    } catch (e) {
      debugPrint('Error handling shared link: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error loading shared trail')),
      );
    }
  }
}
