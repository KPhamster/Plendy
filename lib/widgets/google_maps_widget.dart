import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
// Re-add Geolocator and MapsService imports as they are needed for selection
import 'package:geolocator/geolocator.dart';
import '../models/experience.dart';
import '../services/google_maps_service.dart'; // Needed for findPlaceNearPosition
import 'package:plendy/utils/haptic_feedback.dart';

class GoogleMapsWidget extends StatefulWidget {
  final Location? initialLocation;
  final double initialZoom;
  final bool showUserLocation;
  // Restore allowSelection and onLocationSelected
  final bool allowSelection;
  final Function(Location)? onLocationSelected;
  final bool showControls;
  final bool mapToolbarEnabled;
  final Map<String, Marker>? additionalMarkers;
  final Function(GoogleMapController)? onMapControllerCreated;

  const GoogleMapsWidget({
    super.key,
    this.initialLocation,
    this.initialZoom = 14.0,
    this.showUserLocation = true,
    this.allowSelection = true, // Default to true
    this.showControls = true,
    this.mapToolbarEnabled = false, // Disable to prevent duplicate semantic nodes
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
  // ADDED: Stable key for the GoogleMap widget to prevent recreation
  final _googleMapKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _syncMarkers();

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
    _syncMarkers();
  }

  /// Incrementally sync internal markers with the incoming prop so that the
  /// native GoogleMap only sees actual additions / removals / changes instead
  /// of a full clear-and-readd on every parent rebuild.
  void _syncMarkers() {
    final incoming = widget.additionalMarkers;
    if (incoming == null) {
      if (_markers.isNotEmpty) {
        _markers.clear();
        if (mounted) setState(() {});
      }
      return;
    }

    bool changed = false;
    final incomingKeys = <MarkerId>{};

    for (final entry in incoming.entries) {
      final key = MarkerId(entry.key);
      incomingKeys.add(key);
      final existing = _markers[key];
      if (existing == null || existing != entry.value) {
        _markers[key] = entry.value;
        changed = true;
      }
    }

    // Remove markers that are no longer present.
    final staleKeys =
        _markers.keys.where((k) => !incomingKeys.contains(k)).toList();
    if (staleKeys.isNotEmpty) {
      for (final k in staleKeys) {
        _markers.remove(k);
      }
      changed = true;
    }

    if (changed && mounted) {
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
          key: _googleMapKey, // Use stable key to prevent recreation across rebuilds
          // Use the determined initial position
          initialCameraPosition: _initialCameraPosition,
          myLocationEnabled: widget.showUserLocation,
          myLocationButtonEnabled:
              widget.showUserLocation && widget.showControls,
          zoomControlsEnabled: widget.showControls,
          compassEnabled: widget.showControls,
          mapToolbarEnabled: widget.mapToolbarEnabled,
          // Use the internal markers map now
          markers: Set<Marker>.of(_markers.values),
          onMapCreated: _onMapCreated,
          // Add onTap back
          onTap: withHeavyTap(widget.allowSelection ? _onMapTapped : null),
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
