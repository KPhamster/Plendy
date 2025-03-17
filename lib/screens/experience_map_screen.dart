import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/experience.dart';
import '../widgets/google_maps_widget.dart';
import '../services/google_maps_service.dart';

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
  final GoogleMapsService _mapsService = GoogleMapsService();
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.experience.name),
      ),
      body: Stack(
        children: [
          // Map
          GoogleMapsWidget(
            initialLocation: widget.experience.location,
            initialZoom: 15.0,
            showUserLocation: true,
            allowSelection: false, // Read-only map
          ),
          
          // Information panel
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
  
  Future<void> _getDirections() async {
    // Get user's current location
    try {
      final position = await _mapsService.getCurrentLocation();
      
      final url = _mapsService.getDirectionsUrl(
        widget.experience.location.latitude,
        widget.experience.location.longitude,
        originLat: position.latitude,
        originLng: position.longitude,
      );
      
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch $url';
      }
    } catch (e) {
      // If we can't get current location, provide directions without origin
      final url = _mapsService.getDirectionsUrl(
        widget.experience.location.latitude,
        widget.experience.location.longitude,
      );
      
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch $url';
      }
    }
  }
}