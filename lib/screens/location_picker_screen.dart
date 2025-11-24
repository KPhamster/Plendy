import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/google_maps_widget.dart';
import '../models/experience.dart';
import '../services/google_maps_service.dart';
import 'dart:async';

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
  String? _selectedLocationBusinessStatus; // ADDED: business status for selected location
  bool? _selectedLocationOpenNow; // ADDED: open-now status
  List<Map<String, dynamic>> _searchResults = [];
  bool _showSearchResults = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearching = false;
  GoogleMapController? _mapController;
  final Map<String, Marker> _mapMarkers = {};
  Timer? _debounce;
  final GlobalKey _mapKey = GlobalKey(); // Preserve map state across rebuilds
  bool _mapInitialized = false; // Track if map has been initialized
  Location? _initialMapLocation; // Store initial location

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
    _initialMapLocation = widget.initialLocation; // Store for map initialization
    _updateSelectedLocationMarker();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_searchFocusNode);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _searchPlaces(String query) async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (query.isEmpty) {
        if (mounted) {
          setState(() {
            _searchResults = [];
            _showSearchResults = false;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _isSearching = true;
        });
      }

      try {
        final results = await _mapsService.searchPlaces(query);

        // Get current map center for distance calculation
        LatLng? mapCenter;
        if (_mapController != null) {
          try {
            // Ensure context is still valid before accessing MediaQuery
            if (mounted) {
              mapCenter = await _mapController!.getLatLng(ScreenCoordinate(
                  x: MediaQuery.of(context).size.width ~/ 2,
                  y: MediaQuery.of(context).size.height ~/ 2));
            }
          } catch (e) {
            print('Error getting map center: $e');
          }
        }

        // Sort results based on text priority first, then by distance
        results.sort((a, b) {
          final String nameA = (a['description'] ?? '').toString().toLowerCase();
          final String nameB = (b['description'] ?? '').toString().toLowerCase();
          final String queryLower = query.toLowerCase();
          final String? hintLower = widget.isFromYelpShare && widget.businessNameHint != null
              ? widget.businessNameHint!.toLowerCase()
              : null;

          int getScore(String name, String currentQuery, String? currentHint) {
            int score = 0;
            // Priority 1: Business Hint Matching (highest)
            if (currentHint != null && currentHint.isNotEmpty && name.contains(currentHint)) {
              score += 10000;
            }
            // Priority 2: Exact match with query
            if (name == currentQuery) {
              score += 5000;
            }
            // Priority 3: Starts with query
            else if (name.startsWith(currentQuery)) {
              score += 2000;
            }
            // Priority 4: Contains query
            else if (name.contains(currentQuery)) {
              score += 1000;
            }
            // Priority 5: Query contains name (e.g. query="Full Place Name", name="Place")
            else if (currentQuery.contains(name) && name.length > 3) {
              score += 500;
            }
            return score;
          }

          int scoreA = getScore(nameA, queryLower, hintLower);
          int scoreB = getScore(nameB, queryLower, hintLower);

          if (scoreA != scoreB) {
            return scoreB.compareTo(scoreA); // Higher score comes first
          }

          // Tie-breaking 1: Longer name (more specific) preferred if scores are equal
          if (nameA.length != nameB.length) {
            return nameB.length.compareTo(nameA.length); // Longer name first
          }

          // Tie-breaking 2: Distance (only if coordinates are available in results)
          final double? latA = a['latitude'];
          final double? lngA = a['longitude'];
          final double? latB = b['latitude'];
          final double? lngB = b['longitude'];

          if (mapCenter != null && latA != null && lngA != null && latB != null && lngB != null) {
            final distanceA = _calculateDistance(
                mapCenter.latitude, mapCenter.longitude, latA, lngA);
            final distanceB = _calculateDistance(
                mapCenter.latitude, mapCenter.longitude, latB, lngB);
            return distanceA.compareTo(distanceB); // Closer distance first
          }

          // Final tie-breaker: alphabetical (maintains some stable order)
          return nameA.compareTo(nameB);
        });
        if (mounted) {
          setState(() {
            _searchResults = results;
            _showSearchResults = results.isNotEmpty;
            _isSearching = false;
          });
        }
      } catch (e) {
        print('Error searching places: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error searching places: $e')),
          );
          setState(() {
            _isSearching = false;
          });
        }
      }
    });
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

      // Fetch business status using Places API v1 details
      String? businessStatus;
      bool? openNow;
      try {
        final detailsMap = await _mapsService.fetchPlaceDetailsData(placeId);
        businessStatus = detailsMap?['businessStatus'] as String?;
        openNow = (detailsMap?['currentOpeningHours']?['openNow']) as bool?;
      } catch (e) {
        businessStatus = null;
        openNow = null;
      }

    // First update state WITHOUT markers to avoid rebuild
    setState(() {
      _selectedLocation = location;
      _searchController.text =
          location.displayName ?? location.address ?? 'Selected Location';
      _showSearchResults = false;
      _isSearching = false;
      _selectedLocationBusinessStatus = businessStatus; // ADDED
      _selectedLocationOpenNow = openNow; // ADDED
    });

    // Animate camera FIRST, then update markers
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      
      // Try multiple times to ensure the controller is ready and animate camera
      bool animationSuccess = false;
      for (int i = 0; i < 5; i++) {
        if (_mapController != null && mounted) {
          try {
            await _mapController!.animateCamera(CameraUpdate.newLatLngZoom(
                    LatLng(location.latitude, location.longitude),
                    16.0) // Zoom in closer
                );
            print('📍 PICKER: Camera animated to ${location.getPlaceName()}');
            animationSuccess = true;
            break; // Success, exit loop
          } catch (e) {
            print('📍 PICKER: Camera animation attempt ${i + 1} failed: $e');
            if (i < 4) await Future.delayed(Duration(milliseconds: 100));
          }
        } else {
          await Future.delayed(Duration(milliseconds: 100));
        }
      }
      
      // After camera animation completes, update markers
      if (mounted && animationSuccess) {
        final Map<String, Marker> newMarkers = {};
        final markerId = MarkerId('selected_location');
        newMarkers[markerId.value] = Marker(
          markerId: markerId,
          position: LatLng(location.latitude, location.longitude),
          infoWindow: InfoWindow(
            title: location.getPlaceName(),
            snippet: location.address,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        );
        
        setState(() {
          _mapMarkers.clear();
          _mapMarkers.addAll(newMarkers);
        });
      }
    });

    // Don't call onLocationSelected here - only call it when user confirms with button
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
    // Dismiss keyboard if focused on the search bar when tapping the map
    _searchFocusNode.unfocus();
    FocusScope.of(context).unfocus();

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

    // Fetch business status using Places API v1 if placeId available
    String? businessStatus;
    bool? openNow;
    try {
      if (detailedLocation.placeId != null && detailedLocation.placeId!.isNotEmpty) {
        final detailsMap = await _mapsService.fetchPlaceDetailsData(detailedLocation.placeId!);
        businessStatus = detailsMap?['businessStatus'] as String?;
        openNow = (detailsMap?['currentOpeningHours']?['openNow']) as bool?;
      }
    } catch (e) {
      businessStatus = null;
      openNow = null;
    }

    // First update state WITHOUT markers to avoid rebuild
    setState(() {
      _selectedLocation = detailedLocation;
      _searchController.text = detailedLocation.displayName ??
          detailedLocation.address ??
          'Selected Location';
      _selectedLocationBusinessStatus = businessStatus; // ADDED
      _selectedLocationOpenNow = openNow; // ADDED
    });

    // Animate camera FIRST, then update markers
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      
      // Try multiple times to ensure the controller is ready and animate camera
      bool animationSuccess = false;
      for (int i = 0; i < 5; i++) {
        if (_mapController != null && mounted) {
          try {
            await _mapController!.animateCamera(CameraUpdate.newLatLng(
                LatLng(detailedLocation.latitude, detailedLocation.longitude)));
            print('📍 PICKER: Camera animated to map tap location');
            animationSuccess = true;
            break; // Success, exit loop
          } catch (e) {
            print('📍 PICKER: Camera animation attempt ${i + 1} failed: $e');
            if (i < 4) await Future.delayed(Duration(milliseconds: 100));
          }
        } else {
          await Future.delayed(Duration(milliseconds: 100));
        }
      }
      
      // After camera animation completes, update markers
      if (mounted && animationSuccess) {
        final Map<String, Marker> newMarkers = {};
        final markerId = MarkerId('selected_location');
        newMarkers[markerId.value] = Marker(
          markerId: markerId,
          position: LatLng(detailedLocation.latitude, detailedLocation.longitude),
          infoWindow: InfoWindow(
            title: detailedLocation.getPlaceName(),
            snippet: detailedLocation.address,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        );
        
        setState(() {
          _mapMarkers.clear();
          _mapMarkers.addAll(newMarkers);
        });
      }
    });
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
    final bool isIOS = Theme.of(context).platform == TargetPlatform.iOS;

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

    // Allocate more space to the results on iOS when keyboard is visible
    final bool giveResultsMoreSpace = isIOS && isKeyboardVisible && _showSearchResults;

    // Prebuild search results container to allow platform-specific wrapping
    final Widget searchResultsContainer = Container(
      constraints: giveResultsMoreSpace
          ? null
          : BoxConstraints(
              maxHeight: isKeyboardVisible
                  ? (isIOS
                      ? MediaQuery.of(context).size.height * 0.6
                      : MediaQuery.of(context).size.height * 0.4)
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
        padding: EdgeInsets.only(
          top: 8,
          bottom: (isIOS && isKeyboardVisible) ? keyboardHeight : 8,
        ),
        itemCount: _searchResults.length,
        separatorBuilder: (context, index) =>
            Divider(height: 1, indent: 56, endIndent: 16),
        itemBuilder: (context, index) {
          final result = _searchResults[index];
          final bool hasRating = result['rating'] != null;
          final double rating = hasRating ? (result['rating'] as double) : 0.0;
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
                    backgroundColor:
                        Theme.of(context).primaryColor.withOpacity(0.1),
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
    );

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.white,
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
      bottomNavigationBar: _selectedLocation != null && !(isIOS && isKeyboardVisible)
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
      body: Container(
        color: Colors.white,
        child: SafeArea(
          child: Column(
          children: [
            // Search bar
            Container(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Card(
                  color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    decoration: InputDecoration(
                      hintText: 'Search for a place',
                      border: InputBorder.none,
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.search, color: Theme.of(context).primaryColor),
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
            ),

            // Search results
            if (_showSearchResults)
              (giveResultsMoreSpace
                  ? Expanded(flex: 3, child: searchResultsContainer)
                  : (isIOS
                      ? Flexible(child: searchResultsContainer)
                      : searchResultsContainer)),

            // Map takes the remaining space
            (giveResultsMoreSpace
                ? Flexible(
                    flex: 1,
                    child: Stack(
                      children: [
                        GoogleMapsWidget(
                          key: _mapKey, // Use key to preserve state
                          initialLocation: _initialMapLocation, // Always use the original initial location
                          showUserLocation: true,
                          allowSelection: true,
                          onLocationSelected: _onLocationSelected,
                          // Pass a copy of the map - GoogleMap now has stable key so won't reset
                          additionalMarkers: Map.of(_mapMarkers),
                          onMapControllerCreated: (controller) {
                            _mapController = controller;
                            if (!_mapInitialized) {
                              _mapInitialized = true; // Mark as initialized only first time
                            }
                          },
                        ),
                      ],
                    ),
                  )
                : Expanded(
                    child: Stack(
                      children: [
                        GoogleMapsWidget(
                          key: _mapKey, // Use key to preserve state
                          initialLocation: _initialMapLocation, // Always use the original initial location
                          showUserLocation: true,
                          allowSelection: true,
                          onLocationSelected: _onLocationSelected,
                          // Pass a copy of the map - GoogleMap now has stable key so won't reset
                          additionalMarkers: Map.of(_mapMarkers),
                          onMapControllerCreated: (controller) {
                            _mapController = controller;
                            if (!_mapInitialized) {
                              _mapInitialized = true; // Mark as initialized only first time
                            }
                          },
                        ),
                      ],
                    ),
                  )),

            // Information about selected location - only when keyboard is not visible
            if (_selectedLocation != null && !isKeyboardVisible)
              Container(
                width: double.infinity,
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
                        if (_selectedLocation!.address != null && _selectedLocation!.address!.isNotEmpty) ...[
                          Text(
                            _selectedLocation!.address!,
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                          SizedBox(height: 8),
                        ],
                        // Star Rating
                        if (_selectedLocation!.rating != null) ...[
                          Row(
                            children: [
                              ...List.generate(5, (i) {
                                final ratingValue = _selectedLocation!.rating!;
                                return Icon(
                                  i < ratingValue.floor()
                                      ? Icons.star
                                      : (i < ratingValue)
                                          ? Icons.star_half
                                          : Icons.star_border,
                                  size: 18, // Adjusted size for this context
                                  color: Colors.amber,
                                );
                              }),
                              SizedBox(width: 8),
                              if (_selectedLocation!.userRatingCount != null && _selectedLocation!.userRatingCount! > 0)
                                Text(
                                  '(${_selectedLocation!.userRatingCount})',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 13,
                                  ),
                                ),
                            ],
                          ),
                          SizedBox(height: 8),
                        ],

                        // ADDED: Business/open-now status beneath rating
                        Builder(builder: (context) {
                          String? statusText;
                          Color statusColor = Colors.grey;
                          if (_selectedLocationBusinessStatus == 'CLOSED_PERMANENTLY') {
                            statusText = 'Closed Permanently';
                            statusColor = Colors.red[700]!;
                          } else if (_selectedLocationBusinessStatus == 'CLOSED_TEMPORARILY') {
                            statusText = 'Closed Temporarily';
                            statusColor = Colors.red[700]!;
                          } else if (_selectedLocationOpenNow != null) {
                            if (_selectedLocationOpenNow == true) {
                              statusText = 'Open now';
                              statusColor = Colors.green[700]!;
                            } else {
                              statusText = 'Closed now';
                              statusColor = Colors.red[700]!;
                            }
                          } else if (_selectedLocationBusinessStatus == 'OPERATIONAL') {
                            statusText = 'Operational';
                            statusColor = Colors.grey;
                          }
                          if (statusText == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.info_outline, size: 18.0, color: Colors.black54),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    statusText,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),

                    // Get Directions button positioned at top-right
                    Positioned(
                      top: -8,
                      right: -8,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () {
                              if (_selectedLocation != null) {
                                _launchMapLocation(_selectedLocation!);
                              }
                            },
                            icon: Icon(Icons.map_outlined,
                                color: Colors.green[700], size: 28),
                            tooltip: 'Open in map app',
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: _openDirectionsInGoogleMaps,
                            icon: Icon(Icons.directions,
                                color: Colors.blue, size: 28),
                            tooltip: 'Get Directions',
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
          ),
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

  // ADDED: Helper method to launch map location directly
  Future<void> _launchMapLocation(Location location) async {
    final String mapUrl;
    // Prioritize Place ID if available for a more specific search
    if (location.placeId != null && location.placeId!.isNotEmpty) {
      // Use the Google Maps search API with place_id format
      final placeName =
          location.displayName ?? location.address ?? 'Selected Location';
      mapUrl =
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(placeName)}&query_place_id=${location.placeId}';
      print('📍 PICKER: Launching Map with Place ID: $mapUrl');
    } else {
      // Fallback to coordinate-based URL if no place ID
      final lat = location.latitude;
      final lng = location.longitude;
      mapUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
      print('📍 PICKER: Launching Map with Coordinates: $mapUrl');
    }

    final Uri mapUri = Uri.parse(mapUrl);

    if (!await launchUrl(mapUri, mode: LaunchMode.externalApplication)) {
      print('📍 PICKER: Could not launch $mapUri');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open map location.')),
        );
      }
    }
    // Note: No need to clear marker here as it's managed differently
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
