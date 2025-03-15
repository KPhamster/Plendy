import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/experience.dart';
import '../services/map_service.dart';

class ExperienceMapScreen extends StatefulWidget {
  final Experience experience;
  
  const ExperienceMapScreen({
    Key? key,
    required this.experience,
  }) : super(key: key);

  @override
  _ExperienceMapScreenState createState() => _ExperienceMapScreenState();
}

class _ExperienceMapScreenState extends State<ExperienceMapScreen> {
  final MapService _mapService = MapService();
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  
  @override
  void initState() {
    super.initState();
    _updateMarkers();
  }
  
  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
  
  void _updateMarkers() {
    final markers = <Marker>{};
    
    // Add the experience marker
    markers.add(
      Marker(
        markerId: MarkerId('experience_${widget.experience.id}'),
        position: LatLng(
          widget.experience.location.latitude,
          widget.experience.location.longitude,
        ),
        infoWindow: InfoWindow(
          title: widget.experience.name,
          snippet: widget.experience.location.address ?? '',
        ),
      ),
    );
    
    setState(() {
      _markers = markers;
    });
  }
  
  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }
  
  Future<void> _getDirections() async {
    // Get user's current location if available
    final position = await _mapService.getCurrentLocation();
    
    String url;
    if (position != null) {
      url = _mapService.getDirectionsUrl(
        widget.experience.location.latitude,
        widget.experience.location.longitude,
        originLat: position.latitude,
        originLng: position.longitude,
      );
    } else {
      url = _mapService.getDirectionsUrl(
        widget.experience.location.latitude,
        widget.experience.location.longitude,
      );
    }
    
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw 'Could not launch $url';
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final initialPosition = LatLng(
      widget.experience.location.latitude,
      widget.experience.location.longitude,
    );
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.experience.name),
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: initialPosition,
              zoom: 15.0,
            ),
            onMapCreated: _onMapCreated,
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true,
            compassEnabled: true,
            mapToolbarEnabled: true,
          ),
          
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.experience.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    widget.experience.location.address ?? 'No address available',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                  SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: Icon(Icons.directions),
                      label: Text('Get Directions'),
                      onPressed: _getDirections,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
