import 'package:flutter/material.dart';
import '../widgets/google_maps_widget.dart'; // Import the map widget

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Experiences Map'),
      ),
      body: const GoogleMapsWidget(
        showUserLocation: true, // Show the user's current location
        allowSelection: false, // Don't allow selecting a new location on tap
        showControls: true, // Show zoom controls etc.
        // We'll add markers for experiences later
      ),
    );
  }
}
