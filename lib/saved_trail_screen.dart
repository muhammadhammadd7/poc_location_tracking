import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'service/map_service.dart';
import 'service/trail_sharing_service.dart';

class SavedTrailScreen extends StatefulWidget {
  final Map<String, dynamic> trackingData;
  const SavedTrailScreen({
    super.key,
    required this.trackingData,
  });

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
    _processTrackingData();
  }

  void _processTrackingData() {
    if (widget.trackingData.isEmpty) return;

    try {
      final List<dynamic> points = widget.trackingData['points'];
      _trackingPoints = points
          .map((point) => LatLng(
                double.parse(point['latitude'].toString()),
                double.parse(point['longitude'].toString()),
              ))
          .toList();

      if (_trackingPoints.isNotEmpty) {
        // Add polyline
        _polylines.add(Polyline(
          polylineId: const PolylineId('saved_route'),
          color: const Color.fromARGB(255, 0, 128, 4),
          width: 5,
          points: _trackingPoints,
          jointType: JointType.round,
          geodesic: true,
        ));

        // Add start marker (green)
        _markers.add(Marker(
          markerId: const MarkerId('start'),
          position: _trackingPoints.first,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'Start Point'),
        ));

        // Add end marker (red)
        _markers.add(Marker(
          markerId: const MarkerId('end'),
          position: _trackingPoints.last,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'End Point'),
        ));

        // Fit map to bounds after a short delay
        if (_mapController != null) {
          Future.delayed(const Duration(milliseconds: 500), () {
            _mapService.fitBounds(_trackingPoints);
          });
        }
      }
    } catch (e) {
      debugPrint('Error processing tracking data: $e');
      debugPrint('Raw data: ${widget.trackingData}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Saved Trail (${_trackingPoints.length} points)'),
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
        initialCameraPosition: CameraPosition(
          target: _trackingPoints.isNotEmpty
              ? _trackingPoints.first
              : const LatLng(0, 0),
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
