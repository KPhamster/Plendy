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
  
  const GoogleMapsWidget({
    Key? key,
    this.initialLocation,
    this.initialZoom = 14.0,
    this.showUserLocation = true,
    this.allowSelection = true,
    this.showControls = true,
    this.onLocationSelected,
    this.additionalMarkers,
  }) : super(key: key);

  @override
  _GoogleMapsWidgetState createState() => _GoogleMapsWidgetState();
}

class _GoogleMapsWidgetState extends State<GoogleMapsWidget> {
  final GoogleMapsService _mapsService = GoogleMapsService();
  final Completer<GoogleMapController> _controllerCompleter = Completer<GoogleMapController>();
  GoogleMapController? _mapController;
  
  // Map state
  CameraPosition? _initialCameraPosition;
  Location? _selectedLocation;
  Position? _userPosition;
  bool _isLoading = true;
  
  // Markers
  Map<MarkerId, Marker> _markers = {};
  
  @override
  void initState() {
    super.initState();
    _initMap();
  }

  @override
  void dispose() {
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
        if (_selectedLocation == null) {
          _selectedLocation = Location(
            latitude: position.latitude,
            longitude: position.longitude,
          );
        }
      });
    } catch (e) {
      print('Error getting current location: $e');
    }
  }
  
  void _setInitialCameraPosition() {
    if (_selectedLocation != null) {
      _initialCameraPosition = CameraPosition(
        target: LatLng(_selectedLocation!.latitude, _selectedLocation!.longitude),
        zoom: widget.initialZoom,
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
        zoom: widget.initialZoom,
      );
    }
  }
  
  void _updateMarkers() {
    _markers.clear();
    
    // Add selected location marker if available
    if (_selectedLocation != null) {
      final markerId = MarkerId('selected_location');
      
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
    if (location.address == null) return 'Selected Location';
    
    final addressParts = location.address!.split(',');
    return addressParts.first.trim();
  }
  
  Future<void> _onMapCreated(GoogleMapController controller) async {
    _mapController = controller;
    _controllerCompleter.complete(controller);
  }
  
  Future<void> _onMapTapped(LatLng position) async {
    if (!widget.allowSelection) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Try to find if the user tapped on an established place
      final placeDetails = await _mapsService.findPlaceDetails(
        position.latitude, 
        position.longitude
      );
      
      if (placeDetails != null) {
        // An established place was found
        final location = Location(
          latitude: placeDetails['latitude'] as double,
          longitude: placeDetails['longitude'] as double,
          address: placeDetails['address'] as String?,
        );
        
        setState(() {
          _selectedLocation = location;
        });
        
        if (widget.onLocationSelected != null) {
          widget.onLocationSelected!(_selectedLocation!);
        }
      } else {
        // No established place was found, create a new location
        final location = Location(
          latitude: position.latitude,
          longitude: position.longitude,
        );
        
        setState(() {
          _selectedLocation = location;
        });
        
        if (widget.onLocationSelected != null) {
          widget.onLocationSelected!(_selectedLocation!);
        }
      }
    } catch (e) {
      print('Error handling map tap: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
      
      _updateMarkers();
    }
  }
  
  Future<void> _animateToLocation(Location location) async {
    final controller = await _controllerCompleter.future;
    controller.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(location.latitude, location.longitude),
        widget.initialZoom,
      ),
    );
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