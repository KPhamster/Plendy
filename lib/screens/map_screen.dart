import 'dart:async'; // Import async
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'; // Add Google Maps import
import '../widgets/google_maps_widget.dart';
import '../services/experience_service.dart'; // Import ExperienceService
import '../services/auth_service.dart'; // Import AuthService
import '../models/experience.dart'; // Import Experience model
import '../models/user_category.dart'; // Import UserCategory model
import 'experience_page_screen.dart'; // Import ExperiencePageScreen for navigation

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final ExperienceService _experienceService = ExperienceService();
  final AuthService _authService = AuthService();
  final Map<String, Marker> _markers = {}; // Use String keys for marker IDs
  bool _isLoading = true;
  List<Experience> _experiences = [];
  List<UserCategory> _categories = [];
  final Completer<GoogleMapController> _mapControllerCompleter =
      Completer<GoogleMapController>();

  @override
  void initState() {
    super.initState();
    _loadDataAndGenerateMarkers();
  }

  Future<void> _loadDataAndGenerateMarkers() async {
    print("🗺️ MAP SCREEN: Starting data load...");
    setState(() {
      _isLoading = true;
    });

    try {
      final userId = _authService.currentUser?.uid;
      if (userId == null) {
        print("🗺️ MAP SCREEN: User not logged in.");
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User not logged in.')),
          );
        }
        return;
      }

      _categories = await _experienceService.getUserCategories();
      _experiences = await _experienceService.getExperiencesByUser(userId);
      print(
          "🗺️ MAP SCREEN: Loaded ${_experiences.length} experiences and ${_categories.length} categories.");

      _markers.clear();
      // We will calculate bounds manually now
      double minLat = double.infinity;
      double maxLat = double.negativeInfinity;
      double minLng = double.infinity;
      double maxLng = double.negativeInfinity;
      bool hasValidMarkers = false;

      for (final experience in _experiences) {
        // Basic validation for location data
        if (experience.location.latitude == 0.0 &&
            experience.location.longitude == 0.0) {
          print(
              "🗺️ MAP SCREEN: Skipping experience '${experience.name}' due to invalid coordinates (0,0).");
          continue; // Skip markers with default/invalid coordinates
        }

        final category = _categories.firstWhere(
          (cat) => cat.name == experience.category,
          orElse: () =>
              UserCategory(id: '', name: 'Unknown', icon: '❓', ownerUserId: ''),
        );

        final position = LatLng(
          experience.location.latitude,
          experience.location.longitude,
        );

        // Logging marker details
        print(
            "🗺️ MAP SCREEN: Creating marker for '${experience.name}' at ${position.latitude}, ${position.longitude}");

        final markerId = MarkerId(experience.id);
        final marker = Marker(
          markerId: markerId,
          position: position,
          infoWindow: InfoWindow(
            title: '${category.icon} ${experience.name}',
            snippet: experience.location.getPlaceName(),
            onTap: () => _navigateToExperience(experience, category),
          ),
          icon: BitmapDescriptor.defaultMarker, // Keep default for now
          onTap: () => _navigateToExperience(experience, category),
        );
        _markers[experience.id] = marker;

        // Update bounds manually
        if (position.latitude < minLat) minLat = position.latitude;
        if (position.latitude > maxLat) maxLat = position.latitude;
        if (position.longitude < minLng) minLng = position.longitude;
        if (position.longitude > maxLng) maxLng = position.longitude;
        hasValidMarkers = true;
      }

      print("🗺️ MAP SCREEN: Generated ${_markers.length} valid markers.");

      // Animate camera after markers are generated AND map controller is ready
      if (hasValidMarkers) {
        print("🗺️ MAP SCREEN: Waiting for map controller to be ready...");
        // Wait for the controller to be created and retrieve it
        final GoogleMapController controller =
            await _mapControllerCompleter.future;
        print("🗺️ MAP SCREEN: Map controller is ready. Calculating bounds...");

        // Use the helper to calculate bounds
        final bounds = _calculateBoundsFromMarkers(_markers);

        if (bounds != null) {
          print(
              "🗺️ MAP SCREEN: Animating camera to calculated bounds: $bounds");
          // Use the controller obtained from the Completer
          controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50.0));
        } else {
          print(
              "🗺️ MAP SCREEN: Calculated invalid bounds, not animating camera.");
        }
      } else {
        print("🗺️ MAP SCREEN: No valid markers to calculate bounds for.");
      }
    } catch (e, stackTrace) {
      print("🗺️ MAP SCREEN: Error loading map data: $e");
      print(stackTrace); // Print stack trace for detailed debugging
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading map data: $e')),
        );
      }
    } finally {
      if (mounted) {
        print(
            "🗺️ MAP SCREEN: Data load finished. Setting loading state to false.");
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Helper function to navigate to the Experience Page
  void _navigateToExperience(Experience experience, UserCategory category) {
    print("🗺️ MAP SCREEN: Navigating to experience: ${experience.name}");
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExperiencePageScreen(
          experience: experience,
          category: category,
        ),
      ),
    );
  }

  // Callback to get the map controller from the widget
  void _onMapWidgetCreated(GoogleMapController controller) {
    print("🗺️ MAP SCREEN: Map Controller received via callback.");
    // Complete the completer ONLY if it hasn't been completed yet.
    if (!_mapControllerCompleter.isCompleted) {
      print("🗺️ MAP SCREEN: Completing the map controller completer.");
      _mapControllerCompleter.complete(controller);
    } else {
      print("🗺️ MAP SCREEN: Map controller completer was already completed.");
    }
  }

  // Renamed helper to be more specific
  LatLngBounds? _calculateBoundsFromMarkers(Map<String, Marker> markers) {
    if (markers.isEmpty) return null;

    // Start with the first marker's position to initialize bounds
    final firstMarkerPosition = markers.values.first.position;
    double minLat = firstMarkerPosition.latitude;
    double maxLat = firstMarkerPosition.latitude;
    double minLng = firstMarkerPosition.longitude;
    double maxLng = firstMarkerPosition.longitude;

    // Iterate through the rest of the markers to find min/max lat/lng
    for (final marker in markers.values) {
      final lat = marker.position.latitude;
      final lng = marker.position.longitude;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }

    // Create the LatLngBounds object
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    // Basic validation: southwest lat should be <= northeast lat
    // (Longitude can wrap around, so less strict check needed)
    if (bounds.southwest.latitude <= bounds.northeast.latitude) {
      return bounds;
    }
    print("🗺️ MAP SCREEN: Calculated invalid bounds: $bounds");
    return null; // Indicate invalid bounds
  }

  @override
  Widget build(BuildContext context) {
    print("🗺️ MAP SCREEN: Building widget. isLoading: $_isLoading");
    return Scaffold(
      appBar: AppBar(
        title: const Text('Experiences Map'),
      ),
      // Use a Stack to overlay the loading indicator
      body: Stack(
        children: [
          // Always build the map widget
          GoogleMapsWidget(
            // Pass initial location if needed, or let the widget handle default
            // initialLocation: const Location(latitude: 37.42, longitude: -122.08), // Example default
            showUserLocation: true,
            allowSelection: false,
            showControls: true,
            additionalMarkers:
                _markers.map((key, marker) => MapEntry(key, marker)),
            onMapControllerCreated: _onMapWidgetCreated,
          ),
          // Show loading indicator on top if loading
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
