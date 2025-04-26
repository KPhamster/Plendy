import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
// Re-add Geolocator and MapsService imports as they are needed for selection
import 'package:geolocator/geolocator.dart';
import '../models/experience.dart';
import '../services/google_maps_service.dart'; // Needed for findPlaceNearPosition

class GoogleMapsWidget extends StatefulWidget {
  final Location? initialLocation;
  final double initialZoom;
  final bool showUserLocation;
  // Restore allowSelection and onLocationSelected
  final bool allowSelection;
  final Function(Location)? onLocationSelected;
  final bool showControls;
  final Map<String, Marker>? additionalMarkers;
  final Function(GoogleMapController)? onMapControllerCreated;

  const GoogleMapsWidget({
    super.key,
    this.initialLocation,
    this.initialZoom = 14.0,
    this.showUserLocation = true,
    this.allowSelection = true, // Default to true
    this.showControls = true,
    this.onLocationSelected,
    this.additionalMarkers,
    this.onMapControllerCreated,
  });

  @override
  _GoogleMapsWidgetState createState() => _GoogleMapsWidgetState();
}

class _GoogleMapsWidgetState extends State<GoogleMapsWidget> {
  final GoogleMapsService _mapsService = GoogleMapsService();
  GoogleMapController? _mapController;
  final Map<MarkerId, Marker> _markers = {};
  bool _isProcessingTap = false;
  // ADDED: State for user position and loading
  Position? _currentUserPosition;
  bool _isLoadingUserLocation = false;
  // ADDED: Store the calculated initial camera position
  late CameraPosition _initialCameraPosition;
  // ADDED: Flag to track if initial position is determined
  bool _initialPositionDetermined = false;

  @override
  void initState() {
    super.initState();
    _updateInternalMarkers(); // Initialize markers from props first

    // Determine initial camera position SYNCHRONOUSLY if possible
    if (widget.initialLocation != null) {
      print(
          "📍 GOOGLE MAPS WIDGET: Using provided initialLocation (sync path).");
      final target = LatLng(
          widget.initialLocation!.latitude, widget.initialLocation!.longitude);
      _initialCameraPosition =
          CameraPosition(target: target, zoom: widget.initialZoom);
      _initialPositionDetermined = true; // Set flag immediately
    } else {
      // Only fetch user location if initialLocation was null
      _fetchUserLocationForInitialPosition();
    }
  }

  // Renamed the async part for clarity
  Future<void> _fetchUserLocationForInitialPosition() async {
    print(
        "📍 GOOGLE MAPS WIDGET: No initialLocation, attempting user location fetch...");
    // Set loading state only when actually fetching
    setState(() {
      _isLoadingUserLocation = true;
    });
    LatLng target;
    try {
      _currentUserPosition = await _mapsService.getCurrentLocation();
      target = LatLng(
          _currentUserPosition!.latitude, _currentUserPosition!.longitude);
      print("📍 GOOGLE MAPS WIDGET: Got user location: $target");
    } catch (e) {
      print(
          "📍 GOOGLE MAPS WIDGET: Failed to get user location: $e. Using default.");
      target = const LatLng(37.42796133580664, -122.085749655962); // Default
    }

    // Set position and flag only if the widget is still mounted
    if (mounted) {
      _initialCameraPosition =
          CameraPosition(target: target, zoom: widget.initialZoom);
      setState(() {
        _isLoadingUserLocation = false;
        _initialPositionDetermined = true;
      });
    }
  }

  @override
  void didUpdateWidget(covariant GoogleMapsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    print(
        "📍 GOOGLE MAPS WIDGET: didUpdateWidget called."); // Log widget update
    // Update markers if the additionalMarkers prop changes
    if (widget.additionalMarkers != oldWidget.additionalMarkers) {
      print(
          "📍 GOOGLE MAPS WIDGET: additionalMarkers prop changed, calling _updateInternalMarkers.");
      _updateInternalMarkers();
    }
    // Optionally, update camera if initialLocation changes, though MapScreen manages this now
    // if (widget.initialLocation != oldWidget.initialLocation && widget.initialLocation != null) {
    //    _animateToLocation(widget.initialLocation!); // Needs _animateToLocation re-added
    // }
  }

  // Helper to update internal markers from props
  void _updateInternalMarkers() {
    print("📍 GOOGLE MAPS WIDGET: Updating internal markers.");
    _markers.clear();
    if (widget.additionalMarkers != null) {
      print(
          "📍 GOOGLE MAPS WIDGET: Received ${widget.additionalMarkers!.length} additional markers:");
      widget.additionalMarkers!.forEach((id, marker) {
        print("  - Adding marker ID: $id at ${marker.position}");
        _markers[MarkerId(id)] = marker;
      });
    } else {
      print("📍 GOOGLE MAPS WIDGET: additionalMarkers is null.");
    }
    // Avoid calling setState if widget is disposed or not mounted
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _onMapCreated(GoogleMapController controller) async {
    print("📍 GOOGLE MAPS WIDGET: Simplified _onMapCreated fired!");
    _mapController = controller;
    if (widget.onMapControllerCreated != null) {
      widget.onMapControllerCreated!(controller);
    }
  }

  // Re-implement map tap handler
  Future<void> _onMapTapped(LatLng position) async {
    if (!widget.allowSelection || _isProcessingTap) return;

    print(
        "📍 GOOGLE MAPS WIDGET: Map tapped at $position. allowSelection: ${widget.allowSelection}");

    setState(() {
      _isProcessingTap = true;
    });

    try {
      final location = await _mapsService.findPlaceNearPosition(position);
      print(
          "📍 GOOGLE MAPS WIDGET: Found place near tap: ${location.displayName}");

      // Call the callback if provided
      if (widget.onLocationSelected != null) {
        widget.onLocationSelected!(location);
      }

      // Optional: Update a specific marker for immediate tap feedback if desired
      // You might want a dedicated 'tapped_location' marker here
      // _markers[MarkerId('tapped_location')] = Marker(...);
    } catch (e) {
      print('📍 GOOGLE MAPS WIDGET: Error handling map tap: $e');
      // Optionally show a snackbar or some feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting location: $e')), // Show error
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingTap = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use the flag to check if ready
    if (!_initialPositionDetermined) {
      // Show loading only if we are actively fetching user location
      if (_isLoadingUserLocation) {
        print(
            "📍 GOOGLE MAPS WIDGET: Waiting for initial position... Showing loading indicator.");
        return const Center(child: CircularProgressIndicator());
      } else {
        // If not loading user location (i.e., initialLocation was provided and processed instantly)
        // but the flag isn't set yet (build might run before initState setState completes),
        // show a minimal placeholder or an empty container briefly.
        print(
            "📍 GOOGLE MAPS WIDGET: Initial position not ready yet, showing empty container.");
        return Container(); // Or const SizedBox.shrink();
      }
    }

    print(
        "📍 GOOGLE MAPS WIDGET: Building map. allowSelection: ${widget.allowSelection}");
    print(
        "📍 GOOGLE MAPS WIDGET: Initial Camera Position: ${_initialCameraPosition.target}");
    return Stack(
      children: [
        GoogleMap(
          // Use the determined initial position
          initialCameraPosition: _initialCameraPosition,
          myLocationEnabled: widget.showUserLocation,
          myLocationButtonEnabled:
              widget.showUserLocation && widget.showControls,
          zoomControlsEnabled: widget.showControls,
          compassEnabled: widget.showControls,
          mapToolbarEnabled: widget.showControls,
          // Use the internal markers map now
          markers: Set<Marker>.of(_markers.values),
          onMapCreated: _onMapCreated,
          // Add onTap back
          onTap: widget.allowSelection ? _onMapTapped : null,
        ),
        // Show loading indicator overlay ONLY during tap processing now
        if (_isProcessingTap)
          Container(
            color: Colors.black.withOpacity(0.1),
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}
