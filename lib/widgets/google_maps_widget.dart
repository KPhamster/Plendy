import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/experience.dart';
import '../services/google_maps_service.dart';

class GoogleMapsWidget extends StatefulWidget {
  final Location? initialLocation;
  final double initialZoom;
  final bool showUserLocation;
  final bool allowSelection;
  final bool showControls;
  final Function(Location)? onLocationSelected;
  final Map<String, Marker>? additionalMarkers;
  
  // Accessing the controller
  GoogleMapController? get mapController => _GoogleMapsWidgetState._instance?._mapController;
  
  // Animation helper method
  void animateToLocation(Location location) {
    _GoogleMapsWidgetState._instance?._animateToLocation(location);
  }
  
  const GoogleMapsWidget({
    super.key,
    this.initialLocation,
    this.initialZoom = 14.0,
    this.showUserLocation = true,
    this.allowSelection = true,
    this.showControls = true,
    this.onLocationSelected,
    this.additionalMarkers,
  });

  @override
  _GoogleMapsWidgetState createState() => _GoogleMapsWidgetState();
}

class _GoogleMapsWidgetState extends State<GoogleMapsWidget> {
  // Static instance reference for access
  static _GoogleMapsWidgetState? _instance;
  
  final GoogleMapsService _mapsService = GoogleMapsService();
  final Completer<GoogleMapController> _controllerCompleter = Completer<GoogleMapController>();
  GoogleMapController? _mapController;
  
  // Map state
  CameraPosition? _initialCameraPosition;
  Location? _selectedLocation;
  Position? _userPosition;
  bool _isLoading = true;
  
  // Markers
  final Map<MarkerId, Marker> _markers = {};
  
  @override
  void initState() {
    super.initState();
    _instance = this;
    _initMap();
  }

  @override
  void dispose() {
    if (_instance == this) {
      _instance = null;
    }
    _mapController?.dispose();
    super.dispose();
  }
  
  Future<void> _initMap() async {
    setState(() {
      _isLoading = true;
      _selectedLocation = widget.initialLocation;
    });
    
    try {
      // Get user location if requested and initial location not provided
      if (widget.showUserLocation && _selectedLocation == null) {
        await _getCurrentLocation();
      }
      
      // Set initial camera position based on selected location or user position
      _setInitialCameraPosition();
      
      // Add markers
      _updateMarkers();
      
      // Add any additional markers provided
      if (widget.additionalMarkers != null) {
        widget.additionalMarkers!.forEach((id, marker) {
          _markers[MarkerId(id)] = marker;
        });
      }
      
    } catch (e) {
      print('Error initializing map: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _getCurrentLocation() async {
    try {
      final position = await _mapsService.getCurrentLocation();
      
      setState(() {
        _userPosition = position;
        
        // If no location is selected yet, use user location
        _selectedLocation ??= Location(
            latitude: position.latitude,
            longitude: position.longitude,
          );
      });
    } catch (e) {
      print('Error getting current location: $e');
    }
  }
  
  void _setInitialCameraPosition() {
    // Default zoom level - if we have a selected location, use a higher zoom
    double zoomLevel = _selectedLocation != null ? 16.0 : widget.initialZoom;
    
    if (_selectedLocation != null) {
      _initialCameraPosition = CameraPosition(
        target: LatLng(_selectedLocation!.latitude, _selectedLocation!.longitude),
        zoom: zoomLevel,
      );
    } else if (_userPosition != null) {
      _initialCameraPosition = CameraPosition(
        target: LatLng(_userPosition!.latitude, _userPosition!.longitude),
        zoom: widget.initialZoom,
      );
    } else {
      // Default position (San Francisco)
      _initialCameraPosition = CameraPosition(
        target: LatLng(37.7749, -122.4194),
        zoom: 12.0, // More reasonable default zoom for a city view
      );
    }
  }
  
  void _updateMarkers() {
    _markers.clear();
    
    // Add selected location marker if available
    if (_selectedLocation != null) {
      final markerId = MarkerId('selected_location');
      
      // Debug: Log the marker coordinates we're setting
      print('📍 MARKER COORDINATES: ${_selectedLocation!.latitude}, ${_selectedLocation!.longitude}');
      
      if (_selectedLocation!.address != null) {
        // This is an established place
        _markers[markerId] = Marker(
          markerId: markerId,
          position: LatLng(_selectedLocation!.latitude, _selectedLocation!.longitude),
          infoWindow: InfoWindow(
            title: _getLocationTitle(_selectedLocation!),
            snippet: _selectedLocation!.address,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        );
      } else {
        // This is a new location
        _markers[markerId] = Marker(
          markerId: markerId,
          position: LatLng(_selectedLocation!.latitude, _selectedLocation!.longitude),
          infoWindow: InfoWindow(
            title: 'Selected Location',
            snippet: 'Lat: ${_selectedLocation!.latitude.toStringAsFixed(6)}, Lng: ${_selectedLocation!.longitude.toStringAsFixed(6)}',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        );
      }
    }
    
    // Add user location marker if available and requested
    if (_userPosition != null && widget.showUserLocation) {
      final markerId = MarkerId('user_location');
      _markers[markerId] = Marker(
        markerId: markerId,
        position: LatLng(_userPosition!.latitude, _userPosition!.longitude),
        infoWindow: InfoWindow(title: 'Your Location'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      );
    }
    
    setState(() {});
  }
  
  String _getLocationTitle(Location location) {
    // Use the new helper method for consistent place name display
    return location.getPlaceName();
  }
  
  Future<void> _onMapCreated(GoogleMapController controller) async {
    _mapController = controller;
    _controllerCompleter.complete(controller);
    
    // If there's a selected location, ensure the map is properly positioned
    if (_selectedLocation != null) {
      _animateToLocation(_selectedLocation!);
    }
  }
  
  Future<void> _onMapTapped(LatLng position) async {
    if (!widget.allowSelection) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Log the tapped coordinates
      print('📍 MAP TAPPED: ${position.latitude}, ${position.longitude}');
      
      // Use the findPlaceNearPosition method which will search for POIs
      final location = await _mapsService.findPlaceNearPosition(position);
      
      // Debug: Log the POI coordinates returned by the API
      print('📍 POI COORDINATES FOUND: ${location.latitude}, ${location.longitude}');
      print('📍 POI NAME: ${location.displayName}');
      print('📍 POI ADDRESS: ${location.address}');
      
      // Update the selected location (using the POI coordinates)
      setState(() {
        _selectedLocation = location; 
      });
      
      // Notify parent if callback provided
      if (widget.onLocationSelected != null) {
        widget.onLocationSelected!(_selectedLocation!);
      }
      
      // Ensure the marker is updated
      _updateMarkers();
      
      // Force map to center on the POI coordinates
      if (_mapController != null) {
        print('📍 ANIMATING TO POI COORDINATES: ${location.latitude}, ${location.longitude}');
        await _mapController!.animateCamera(
          CameraUpdate.newLatLng(LatLng(location.latitude, location.longitude))
        );
      }
    } catch (e) {
      print('Error handling map tap: $e');
      
      // Even in case of error, create a basic location
      final location = Location(
        latitude: position.latitude,
        longitude: position.longitude,
        displayName: 'Selected Location',
      );
      
      setState(() {
        _selectedLocation = location;
      });
      
      // Notify parent if callback provided
      if (widget.onLocationSelected != null) {
        widget.onLocationSelected!(_selectedLocation!);
      }
      
      // Update markers
      _updateMarkers();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  /// Animates the map camera to focus on the given location
  Future<void> _animateToLocation(Location location) async {
    // Get current zoom level if possible, otherwise use the initial zoom
    double currentZoom = widget.initialZoom;
    if (_mapController != null) {
      try {
        // Get current camera position to maintain zoom level
        final cameraPosition = await _mapController!.getVisibleRegion();
        // Calculate approximate zoom from visible region
        // This helps maintain the current zoom level instead of resetting
        currentZoom = await _mapController!.getZoomLevel();
        print('📍 Current zoom level: $currentZoom');
      } catch (e) {
        print('Error getting current zoom: $e');
        // Fall back to initial zoom if we can't get current zoom
      }
    }
    
    try {
      if (_mapController == null) {
        // If map controller isn't ready yet, wait for it
        final controller = await _controllerCompleter.future;
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(location.latitude, location.longitude),
            currentZoom,
          ),
        );
      } else {
        // Otherwise use existing controller directly
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(location.latitude, location.longitude),
            currentZoom,
          ),
        );
      }
    } catch (e) {
      print('Error animating camera: $e');
    }
    
    // Update selected location and markers
    setState(() {
      _selectedLocation = location;
    });
    
    _updateMarkers();
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isLoading && _initialCameraPosition == null) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: _initialCameraPosition!,
          myLocationEnabled: widget.showUserLocation,
          myLocationButtonEnabled: widget.showUserLocation && widget.showControls,
          zoomControlsEnabled: widget.showControls,
          compassEnabled: widget.showControls,
          mapToolbarEnabled: widget.showControls,
          markers: Set<Marker>.of(_markers.values),
          onMapCreated: _onMapCreated,
          onTap: widget.allowSelection ? _onMapTapped : null,
        ),
        
        if (_isLoading)
          Container(
            color: Colors.black.withOpacity(0.1),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
      ],
    );
  }
}