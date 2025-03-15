import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/map_service.dart';
import '../models/experience.dart';

class PlendyMapWidget extends StatefulWidget {
  final Location? initialLocation;
  final double? initialZoom;
  final bool showUserLocation;
  final bool allowSelection;
  final bool showControls;
  final Function(Location)? onLocationSelected;
  
  const PlendyMapWidget({
    Key? key,
    this.initialLocation,
    this.initialZoom = 15.0,
    this.showUserLocation = true,
    this.allowSelection = true,
    this.showControls = true,
    this.onLocationSelected,
  }) : super(key: key);

  @override
  _PlendyMapWidgetState createState() => _PlendyMapWidgetState();
}

class _PlendyMapWidgetState extends State<PlendyMapWidget> {
  final MapService _mapService = MapService();
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Location? _selectedLocation;
  bool _isLoading = true;
  Position? _userPosition;
  TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _showSearchResults = false;
  
  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
    _setupMap();
  }
  
  @override
  void dispose() {
    _mapController?.dispose();
    _searchController.dispose();
    super.dispose();
  }
  
  Future<void> _setupMap() async {
    if (_selectedLocation == null && widget.showUserLocation) {
      await _getCurrentLocation();
    }
    
    _updateMarkers();
    
    setState(() {
      _isLoading = false;
    });
  }
  
  Future<void> _getCurrentLocation() async {
    try {
      final position = await _mapService.getCurrentLocation();
      
      if (position != null) {
        setState(() {
          _userPosition = position;
          
          // If no initial location is provided, use the user's location
          if (_selectedLocation == null) {
            _selectedLocation = Location(
              latitude: position.latitude,
              longitude: position.longitude,
            );
          }
        });
      }
    } catch (e) {
      print('Error getting current location: $e');
    }
  }
  
  void _updateMarkers() {
    final markers = <Marker>{};
    
    if (_selectedLocation != null) {
      markers.add(
        Marker(
          markerId: MarkerId('selected_location'),
          position: LatLng(_selectedLocation!.latitude, _selectedLocation!.longitude),
          infoWindow: InfoWindow(
            title: 'Selected Location',
            snippet: _selectedLocation!.address ?? 'Location selected',
          ),
        ),
      );
    }
    
    if (_userPosition != null && widget.showUserLocation) {
      markers.add(
        Marker(
          markerId: MarkerId('user_location'),
          position: LatLng(_userPosition!.latitude, _userPosition!.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(title: 'You are here'),
        ),
      );
    }
    
    setState(() {
      _markers = markers;
    });
  }
  
  Future<void> _onMapTapped(LatLng position) async {
    if (!widget.allowSelection) return;
    
    // Create a location from the tapped position
    final location = Location(
      latitude: position.latitude,
      longitude: position.longitude,
    );
    
    setState(() {
      _selectedLocation = location;
    });
    
    _updateMarkers();
    
    if (widget.onLocationSelected != null) {
      widget.onLocationSelected!(_selectedLocation!);
    }
  }
  
  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    
    if (_selectedLocation != null) {
      _animateToLocation(_selectedLocation!);
    } else if (_userPosition != null) {
      _animateToPosition(_userPosition!);
    }
  }
  
  void _animateToLocation(Location location) {
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(location.latitude, location.longitude),
        widget.initialZoom!,
      ),
    );
  }
  
  void _animateToPosition(Position position) {
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(position.latitude, position.longitude),
        widget.initialZoom!,
      ),
    );
  }
  
  Future<void> _searchPlaces(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }
    
    final results = await _mapService.searchPlaces(query);
    
    setState(() {
      _searchResults = results;
      _showSearchResults = results.isNotEmpty;
    });
  }
  
  Future<void> _selectSearchResult(Map<String, dynamic> result) async {
    final placeId = result['placeId'];
    final location = await _mapService.getPlaceDetails(placeId);
    
    if (location != null) {
      setState(() {
        _selectedLocation = location;
        _showSearchResults = false;
        _searchController.text = result['description'];
      });
      
      _updateMarkers();
      _animateToLocation(location);
      
      if (widget.onLocationSelected != null) {
        widget.onLocationSelected!(_selectedLocation!);
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _isLoading
            ? Center(child: CircularProgressIndicator())
            : GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _selectedLocation != null
                      ? LatLng(_selectedLocation!.latitude, _selectedLocation!.longitude)
                      : _userPosition != null
                          ? LatLng(_userPosition!.latitude, _userPosition!.longitude)
                          : LatLng(37.7749, -122.4194), // Default to San Francisco
                  zoom: widget.initialZoom!,
                ),
                onMapCreated: _onMapCreated,
                markers: _markers,
                myLocationEnabled: widget.showUserLocation,
                myLocationButtonEnabled: widget.showUserLocation && widget.showControls,
                zoomControlsEnabled: widget.showControls,
                compassEnabled: widget.showControls,
                mapToolbarEnabled: widget.showControls,
                onTap: widget.allowSelection ? _onMapTapped : null,
              ),
        
        if (widget.allowSelection)
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Card(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search for a place',
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _searchController.clear();
                                    _searchResults = [];
                                    _showSearchResults = false;
                                  });
                                },
                              )
                            : null,
                      ),
                      onChanged: _searchPlaces,
                    ),
                  ),
                  
                  if (_showSearchResults)
                    Container(
                      constraints: BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final result = _searchResults[index];
                          return ListTile(
                            title: Text(result['description']),
                            onTap: () => _selectSearchResult(result),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        
        if (_selectedLocation != null && widget.showControls)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              backgroundColor: Theme.of(context).primaryColor,
              child: Icon(Icons.check),
              onPressed: () {
                if (widget.onLocationSelected != null && _selectedLocation != null) {
                  widget.onLocationSelected!(_selectedLocation!);
                }
              },
            ),
          ),
      ],
    );
  }
}
