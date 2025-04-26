import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/google_maps_widget.dart';
import '../models/experience.dart';
import '../services/google_maps_service.dart';

class LocationPickerScreen extends StatefulWidget {
  final Location? initialLocation;
  final Function(Location) onLocationSelected;
  final String title;
  final bool isFromYelpShare;
  final String? businessNameHint;

  const LocationPickerScreen({
    super.key,
    this.initialLocation,
    required this.onLocationSelected,
    this.title = 'Select Location',
    this.isFromYelpShare = false,
    this.businessNameHint,
  });

  @override
  _LocationPickerScreenState createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final GoogleMapsService _mapsService = GoogleMapsService();
  Location? _selectedLocation;
  List<Map<String, dynamic>> _searchResults = [];
  bool _showSearchResults = false;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  GoogleMapController? _mapController;
  final Map<String, Marker> _mapMarkers = {};

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
    _updateSelectedLocationMarker();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchPlaces(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final results = await _mapsService.searchPlaces(query);

      // Get current map center for distance calculation
      LatLng? mapCenter;
      if (_mapController != null) {
        try {
          mapCenter = await _mapController!.getLatLng(ScreenCoordinate(
              x: MediaQuery.of(context).size.width ~/ 2,
              y: MediaQuery.of(context).size.height ~/ 2));
        } catch (e) {
          print('Error getting map center: $e');
        }
      }

      // Sort results based on text priority first, then by distance
      results.sort((a, b) {
        final String nameA = (a['description'] ?? '').toString().toLowerCase();
        final String nameB = (b['description'] ?? '').toString().toLowerCase();
        final String searchLower = query.toLowerCase();

        // Check if name starts with search query
        final bool aStartsWith = nameA.startsWith(searchLower);
        final bool bStartsWith = nameB.startsWith(searchLower);

        // First priority: names starting with the search query
        if (aStartsWith && !bStartsWith) return -1;
        if (!aStartsWith && bStartsWith) return 1;

        // If both names have the same priority based on text, sort by distance
        if (mapCenter != null) {
          final double? latA = a['latitude'];
          final double? lngA = a['longitude'];
          final double? latB = b['latitude'];
          final double? lngB = b['longitude'];

          if (latA != null && lngA != null && latB != null && lngB != null) {
            // Calculate distances
            final distanceA = _calculateDistance(
                mapCenter.latitude, mapCenter.longitude, latA, lngA);
            final distanceB = _calculateDistance(
                mapCenter.latitude, mapCenter.longitude, latB, lngB);

            return distanceA.compareTo(distanceB);
          }
        }

        // If no location data or they're the same priority, keep original order
        return 0;
      });

      setState(() {
        _searchResults = results;
        _showSearchResults = results.isNotEmpty;
        _isSearching = false;
      });
    } catch (e) {
      print('Error searching places: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error searching places: $e')),
      );

      setState(() {
        _isSearching = false;
      });
    }
  }

  // Helper method to calculate distance between coordinates
  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    // Simple Euclidean distance - good enough for sorting
    return (lat1 - lat2) * (lat1 - lat2) + (lon1 - lon2) * (lon1 - lon2);
  }

  Future<void> _selectSearchResult(Map<String, dynamic> result) async {
    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    setState(() {
      _showSearchResults = false;
      _isSearching = true;
    });

    try {
      final placeId = result['placeId'];
      final location = await _mapsService.getPlaceDetails(placeId);

      setState(() {
        _selectedLocation = location;
        _searchController.text =
            location.displayName ?? location.address ?? 'Selected Location';
        _showSearchResults = false;
        _isSearching = false;
      });

      // Get reference to the GoogleMapsWidget
      if (_mapController != null) {
        // Animate map to the selected location using the controller
        _mapController!.animateCamera(CameraUpdate.newLatLngZoom(
                LatLng(location.latitude, location.longitude),
                16.0) // Zoom in closer
            );
      }

      // Update parent with selected location
      if (widget.onLocationSelected != null) {
        widget.onLocationSelected!(_selectedLocation!);
      }

      // Update the marker on the map
      _updateSelectedLocationMarker();
    } catch (e) {
      print('Error getting place details: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error selecting location: $e')),
      );
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  Future<void> _onLocationSelected(Location location) async {
    Location detailedLocation = location;

    if (location.placeId != null && location.placeId!.isNotEmpty) {
      print(
          "📍 Map tap has Place ID: ${location.placeId}. Fetching details...");
      try {
        detailedLocation =
            await _mapsService.getPlaceDetails(location.placeId!);
        print(
            "📍 Fetched details for map tap: ${detailedLocation.displayName}, Website: ${detailedLocation.website}");
      } catch (e) {
        print("📍 Error fetching details for map tap location: $e");
      }
    } else {
      print("📍 Map tap location has no Place ID. Using basic info.");
    }

    setState(() {
      _selectedLocation = detailedLocation;
      _searchController.text = detailedLocation.displayName ??
          detailedLocation.address ??
          'Selected Location';
    });

    // Make sure we have the location centered on the map
    if (_mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLng(
          LatLng(detailedLocation.latitude, detailedLocation.longitude)));
    }

    // Update the marker on the map
    _updateSelectedLocationMarker();
  }

  // Open Google Maps with directions to the selected location
  Future<void> _openDirectionsInGoogleMaps() async {
    if (_selectedLocation == null) return;

    // Pass the entire Location object
    final url = _mapsService.getDirectionsUrl(_selectedLocation!);

    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      print('Error launching Google Maps: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open Google Maps')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate keyboard height and adjust layout accordingly
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bool isKeyboardVisible = keyboardHeight > 0;

    // Calculate flexible height for map based on available space
    final double screenHeight = MediaQuery.of(context).size.height;
    final double searchBarHeight = 70; // Approximate height of search bar
    final double searchResultsHeight =
        _showSearchResults ? MediaQuery.of(context).size.height * 0.3 : 0;
    final double locationInfoHeight =
        _selectedLocation != null && !isKeyboardVisible ? 200 : 0;
    final double appBarHeight =
        kToolbarHeight + MediaQuery.of(context).padding.top;

    // Min height for map when keyboard is visible
    final double minMapHeight = 150;

    // Calculate map height: available space minus other elements
    double mapHeight = screenHeight -
        appBarHeight -
        searchBarHeight -
        searchResultsHeight -
        locationInfoHeight -
        keyboardHeight;

    // Ensure map has at least minimum height when keyboard is visible
    if (isKeyboardVisible) {
      mapHeight = mapHeight < minMapHeight ? minMapHeight : mapHeight;
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_selectedLocation != null)
            IconButton(
              icon: Icon(Icons.check),
              onPressed: () {
                widget.onLocationSelected(_selectedLocation!);
                Navigator.of(context).pop({
                  'location': _selectedLocation,
                  'shouldUpdateYelpInfo': widget.isFromYelpShare
                });
              },
            ),
        ],
      ),
      // Fixed bottom button that's always visible
      bottomNavigationBar: _selectedLocation != null
          ? Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: Offset(0, -3),
                  ),
                ],
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  widget.onLocationSelected(_selectedLocation!);
                  Navigator.of(context).pop({
                    'location': _selectedLocation,
                    'shouldUpdateYelpInfo': widget.isFromYelpShare
                  });
                },
                child: Text(
                  'Confirm Location',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search for a place',
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.search),
                      suffixIcon: _isSearching
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : _searchController.text.isNotEmpty
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
              ),
            ),

            // Search results
            if (_showSearchResults)
              Container(
                constraints: BoxConstraints(
                  maxHeight: isKeyboardVisible
                      ? MediaQuery.of(context).size.height * 0.4
                      : MediaQuery.of(context).size.height * 0.3,
                ),
                margin: EdgeInsets.symmetric(horizontal: 8.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.symmetric(vertical: 8),
                  itemCount: _searchResults.length,
                  separatorBuilder: (context, index) =>
                      Divider(height: 1, indent: 56, endIndent: 16),
                  itemBuilder: (context, index) {
                    final result = _searchResults[index];
                    final bool hasRating = result['rating'] != null;
                    final double rating =
                        hasRating ? (result['rating'] as double) : 0.0;
                    final String? address = result['address'] ??
                        (result['structured_formatting'] != null
                            ? result['structured_formatting']['secondary_text']
                            : null);

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _selectSearchResult(result),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context)
                                  .primaryColor
                                  .withOpacity(0.1),
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: Theme.of(context).primaryColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            title: Text(
                              result['description'] ?? 'Unknown Place',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (address != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Row(
                                      children: [
                                        Icon(Icons.location_on,
                                            size: 14, color: Colors.grey[600]),
                                        SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            address,
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 13,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (hasRating)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Row(
                                      children: [
                                        ...List.generate(
                                            5,
                                            (i) => Icon(
                                                  i < rating.floor()
                                                      ? Icons.star
                                                      : (i < rating)
                                                          ? Icons.star_half
                                                          : Icons.star_border,
                                                  size: 14,
                                                  color: Colors.amber,
                                                )),
                                        SizedBox(width: 4),
                                        if (result['userRatingCount'] != null)
                                          Text(
                                            '(${result['userRatingCount']})',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

            // Map takes the remaining space
            Expanded(
              child: Stack(
                children: [
                  GoogleMapsWidget(
                    initialLocation: widget.initialLocation,
                    showUserLocation: true,
                    allowSelection: true,
                    onLocationSelected: _onLocationSelected,
                    // Pass a *copy* of the map to ensure change detection
                    additionalMarkers: Map.of(_mapMarkers),
                    onMapControllerCreated: (controller) {
                      _mapController = controller;
                    },
                  ),
                ],
              ),
            ),

            // Information about selected location - only when keyboard is not visible
            if (_selectedLocation != null && !isKeyboardVisible)
              Container(
                padding: EdgeInsets.all(16),
                color: Colors.white,
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Selected Location',
                          style: TextStyle(
                            fontWeight: FontWeight.normal,
                            fontSize: 14,
                            color: Colors.grey[800],
                          ),
                        ),
                        SizedBox(height: 12),

                        // Place name
                        Text(
                          _selectedLocation!.getPlaceName(),
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 8),

                        // Full address
                        if (_selectedLocation!.address != null) ...[
                          Text(
                            _selectedLocation!.address!,
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                          SizedBox(height: 8),
                        ],

                        // Area details if available
                        Row(children: [
                          if (_selectedLocation!.city != null) ...[
                            Icon(Icons.location_city,
                                size: 16, color: Colors.grey[600]),
                            SizedBox(width: 4),
                            Text(
                              _selectedLocation!.city!,
                              style: TextStyle(color: Colors.grey[700]),
                            ),
                            SizedBox(width: 16),
                          ],
                          if (_selectedLocation!.state != null) ...[
                            Text(
                              _selectedLocation!.state!,
                              style: TextStyle(color: Colors.grey[700]),
                            ),
                            SizedBox(width: 8),
                          ],
                          if (_selectedLocation!.country != null) ...[
                            Text(
                              _selectedLocation!.country!,
                              style: TextStyle(color: Colors.grey[700]),
                            ),
                          ],
                        ]),
                        SizedBox(height: 12),

                        // Coordinates
                        Row(
                          children: [
                            Icon(Icons.gps_fixed,
                                size: 16, color: Colors.grey[600]),
                            SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // Get Directions button positioned at top-right
                    Positioned(
                      top: -8,
                      right: -8,
                      child: IconButton(
                        onPressed: _openDirectionsInGoogleMaps,
                        icon: Icon(Icons.directions, color: Colors.blue),
                        tooltip: 'Get Directions',
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Helper method to get icon based on place type
  IconData _getIconForPlaceType(String type) {
    final typeLower = type.toLowerCase();

    if (typeLower.contains('restaurant') || typeLower.contains('food')) {
      return Icons.restaurant;
    } else if (typeLower.contains('cafe') || typeLower.contains('coffee')) {
      return Icons.coffee;
    } else if (typeLower.contains('bar')) {
      return Icons.local_bar;
    } else if (typeLower.contains('store') || typeLower.contains('shop')) {
      return Icons.shopping_bag;
    } else if (typeLower.contains('hotel') || typeLower.contains('lodging')) {
      return Icons.hotel;
    } else if (typeLower.contains('airport')) {
      return Icons.flight;
    } else if (typeLower.contains('train') || typeLower.contains('transit')) {
      return Icons.train;
    } else if (typeLower.contains('park')) {
      return Icons.park;
    } else if (typeLower.contains('school') ||
        typeLower.contains('university')) {
      return Icons.school;
    } else if (typeLower.contains('hospital') || typeLower.contains('doctor')) {
      return Icons.local_hospital;
    } else if (typeLower.contains('gym')) {
      return Icons.fitness_center;
    } else if (typeLower.contains('bank')) {
      return Icons.account_balance;
    } else if (typeLower.contains('gas') || typeLower.contains('fuel')) {
      return Icons.local_gas_station;
    } else if (typeLower.contains('car')) {
      return Icons.directions_car;
    } else if (typeLower.contains('pharmacy')) {
      return Icons.local_pharmacy;
    } else {
      return Icons.place;
    }
  }

  // ADDED: Helper function to create/update the selected location marker
  void _updateSelectedLocationMarker() {
    // Create a new map instead of mutating the old one
    final Map<String, Marker> newMarkers = {};
    if (_selectedLocation != null) {
      print(
          "📍 PICKER: Updating marker for: ${_selectedLocation!.getPlaceName()}");
      final markerId = MarkerId('selected_location');
      newMarkers[markerId.value] = Marker(
        markerId: markerId,
        position:
            LatLng(_selectedLocation!.latitude, _selectedLocation!.longitude),
        infoWindow: InfoWindow(
          title: _selectedLocation!.getPlaceName(),
          snippet: _selectedLocation!.address,
        ),
        // Use a distinct color for the selected location marker
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
      );
    }
    // Trigger rebuild to show the updated marker
    if (mounted) {
      setState(() {
        // Revert to clearing and adding all
        _mapMarkers.clear();
        _mapMarkers.addAll(newMarkers);
      });
    }
  }
}
