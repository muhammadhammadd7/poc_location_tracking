import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'service/map_service.dart';
import 'service/trail_sharing_service.dart';

class SavedTrailScreen extends StatefulWidget {
  const SavedTrailScreen({super.key});

  @override
  State<SavedTrailScreen> createState() => _SavedTrailScreenState();
}

class _SavedTrailScreenState extends State<SavedTrailScreen> {
  final MapService _mapService = MapService();
  final TrailSharingService _sharingService = TrailSharingService();
  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};
  List<LatLng> _trackingPoints = [];
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _loadTrackingData();
  }

  Future<void> _loadTrackingData() async {
    final String? trackingData =
        await FlutterForegroundTask.getData(key: 'last_tracking_data');

    if (trackingData != null) {
      final decodedData = json.decode(trackingData);
      final List<dynamic> points = decodedData['points'];

      setState(() {
        _trackingPoints = points
            .map((point) => LatLng(
                point['latitude'] as double, point['longitude'] as double))
            .toList();

        if (_trackingPoints.isNotEmpty) {
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('saved_route'),
              color: const Color.fromARGB(255, 0, 128, 4),
              width: 5,
              points: _trackingPoints,
              jointType: JointType.round,
            ),
          );

          _markers.add(
            Marker(
              markerId: const MarkerId('start'),
              position: _trackingPoints.first,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen),
              infoWindow: const InfoWindow(title: 'Start Point'),
            ),
          );

          _markers.add(
            Marker(
              markerId: const MarkerId('end'),
              position: _trackingPoints.last,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueRed),
              infoWindow: const InfoWindow(title: 'End Point'),
            ),
          );
        }
      });

      if (_mapController != null && _trackingPoints.isNotEmpty) {
        _mapService.fitBounds(_trackingPoints);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Trail'),
        centerTitle: true,
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _sharingService.shareTrail(context),
          ),
        ],
      ),
      body: GoogleMap(
        initialCameraPosition: const CameraPosition(
          target: LatLng(0, 0),
          zoom: 15,
        ),
        onMapCreated: (GoogleMapController controller) {
          _mapController = controller;
          if (_trackingPoints.isNotEmpty) {
            _mapService.fitBounds(_trackingPoints);
          }
        },
        polylines: _polylines,
        markers: _markers,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        zoomControlsEnabled: true,
        mapType: MapType.normal,
      ),
    );
  }
}
