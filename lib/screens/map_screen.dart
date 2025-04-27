import 'dart:async'; // Import async
import 'dart:typed_data'; // Import for ByteData
import 'dart:ui' as ui; // Import for ui.Image, ui.Canvas etc.
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'; // Add Google Maps import
import '../widgets/google_maps_widget.dart';
import '../services/experience_service.dart'; // Import ExperienceService
import '../services/auth_service.dart'; // Import AuthService
import '../services/google_maps_service.dart'; // Import GoogleMapsService
import '../models/experience.dart'; // Import Experience model
import '../models/user_category.dart'; // Import UserCategory model
import '../models/color_category.dart'; // Import ColorCategory model
import 'experience_page_screen.dart'; // Import ExperiencePageScreen for navigation

// Helper function to parse hex color string
Color _parseColor(String hexColor) {
  hexColor = hexColor.toUpperCase().replaceAll("#", "");
  if (hexColor.length == 6) {
    hexColor = "FF$hexColor"; // Add alpha if missing
  }
  if (hexColor.length == 8) {
    try {
      return Color(int.parse("0x$hexColor"));
    } catch (e) {
      print("🗺️ MAP SCREEN: Error parsing color '$hexColor': $e");
      return Colors.grey; // Default color on parsing error
    }
  }
  print("🗺️ MAP SCREEN: Invalid hex color format: '$hexColor'");
  return Colors.grey; // Default color on invalid format
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final ExperienceService _experienceService = ExperienceService();
  final AuthService _authService = AuthService();
  final GoogleMapsService _mapsService =
      GoogleMapsService(); // ADDED: Maps Service
  final Map<String, Marker> _markers = {}; // Use String keys for marker IDs
  bool _isLoading = true;
  List<Experience> _experiences = [];
  List<UserCategory> _categories = [];
  List<ColorCategory> _colorCategories = [];
  final Completer<GoogleMapController> _mapControllerCompleter =
      Completer<GoogleMapController>();
  // ADDED: Cache for generated category icons
  final Map<String, BitmapDescriptor> _categoryIconCache = {};

  @override
  void initState() {
    super.initState();
    _loadDataAndGenerateMarkers();
    _focusOnUserLocation(); // ADDED: Start focusing map on user location
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
      _colorCategories = await _experienceService.getUserColorCategories();
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

        // --- Start Icon Generation ---
        // REMOVED: Print the category name being searched for
        // print("🗺️ MAP SCREEN: Searching for color for category: '${category.name}'");

        // Find the corresponding color category *based on the experience's property*
        ColorCategory? colorCategory;
        String? experienceColorCategoryId =
            experience.colorCategoryId; // Get the ID (nullable)
        // String experienceColorCategoryName = experience.colorCategoryName; // Assuming this field exists
        // print(
        //     "🗺️ MAP SCREEN: Searching for ColorCategory named: '${experienceColorCategoryName}' for experience '${experience.name}'");

        if (experienceColorCategoryId != null) {
          print(
              "🗺️ MAP SCREEN: Searching for ColorCategory with ID: '${experienceColorCategoryId}' for experience '${experience.name}'");
          try {
            colorCategory = _colorCategories.firstWhere(
              (cc) => cc.id == experienceColorCategoryId, // Match by ID now
            );
            print(
                "🗺️ MAP SCREEN: Found ColorCategory '${colorCategory.name}' with color ${colorCategory.colorHex}");
          } catch (e) {
            colorCategory = null; // Not found
            print(
                "🗺️ MAP SCREEN: No ColorCategory found matching ID '${experienceColorCategoryId}'. Using default color.");
          }
        } else {
          print(
              "🗺️ MAP SCREEN: Experience '${experience.name}' has no colorCategoryId. Using default color.");
        }

        // Determine marker background color
        Color markerBackgroundColor = Colors.grey; // Default
        if (colorCategory != null && colorCategory.colorHex.isNotEmpty) {
          markerBackgroundColor = _parseColor(colorCategory.colorHex);
          print(
              "🗺️ MAP SCREEN: Using color ${markerBackgroundColor} for category '${category.name}'.");
        }

        // Generate a unique cache key including the color and the *icon* (not the category name)
        final String cacheKey =
            '${category.icon}_${markerBackgroundColor.value}';

        BitmapDescriptor categoryIconBitmap =
            BitmapDescriptor.defaultMarker; // Default

        // Use cache or generate new icon
        if (_categoryIconCache.containsKey(cacheKey)) {
          categoryIconBitmap = _categoryIconCache[cacheKey]!;
          print(
              "🗺️ MAP SCREEN: Using cached icon '$cacheKey' for ${category.name}");
        } else {
          try {
            print(
                "🗺️ MAP SCREEN: Generating icon for '$cacheKey' (${category.name})");
            // Pass the background color to the generator
            categoryIconBitmap = await _bitmapDescriptorFromText(
              category.icon,
              backgroundColor: markerBackgroundColor,
            );
            _categoryIconCache[cacheKey] =
                categoryIconBitmap; // Cache the result
          } catch (e) {
            print(
                "🗺️ MAP SCREEN: Failed to generate bitmap for icon '$cacheKey': $e");
            // Keep the default marker if generation fails
          }
        }
        // --- End Icon Generation ---

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
          icon: categoryIconBitmap,
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

      // REMOVED: Automatic camera animation to fit markers.
      // The map will now initially center based on GoogleMapsWidget's logic (user location if available).
      // if (hasValidMarkers) {
      //    print("🗺️ MAP SCREEN: Waiting for map controller to be ready...");
      //    final GoogleMapController controller = await _mapControllerCompleter.future;
      //    print("🗺️ MAP SCREEN: Map controller is ready. Calculating bounds...");
      //
      //    final bounds = _calculateBoundsFromMarkers(_markers); // Use helper
      //
      //    if (bounds != null) {
      //       print("🗺️ MAP SCREEN: Animating camera to calculated bounds: $bounds");
      //       controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50.0));
      //    } else {
      //       print("🗺️ MAP SCREEN: Calculated invalid bounds, not animating camera.");
      //    }
      // } else {
      //      print("🗺️ MAP SCREEN: No valid markers to calculate bounds for.");
      // }
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

  // ADDED: Function to fetch user location and animate camera
  Future<void> _focusOnUserLocation() async {
    print("🗺️ MAP SCREEN: Attempting to focus on user location...");
    try {
      // Wait for the map controller to be ready
      print("🗺️ MAP SCREEN: Waiting for map controller...");
      final GoogleMapController controller =
          await _mapControllerCompleter.future;
      print("🗺️ MAP SCREEN: Map controller ready. Fetching user location...");

      // Get current location
      final position = await _mapsService.getCurrentLocation();
      final userLatLng = LatLng(position.latitude, position.longitude);
      print(
          "🗺️ MAP SCREEN: User location fetched: $userLatLng. Animating camera...");

      // Animate camera to user location
      controller.animateCamera(
        CameraUpdate.newLatLngZoom(userLatLng, 14.0), // Zoom level 14
      );
      print("🗺️ MAP SCREEN: Camera animation initiated.");
    } catch (e) {
      print(
          "🗺️ MAP SCREEN: Failed to get user location or animate camera: $e");
      // Handle error appropriately, maybe show a snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not center map on your location: $e')),
        );
      }
    }
  }

  // ADDED: Helper function to create BitmapDescriptor from text/emoji
  Future<BitmapDescriptor> _bitmapDescriptorFromText(
    String text, {
    int size = 60,
    required Color backgroundColor, // Added required background color parameter
  }) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final double radius = size / 2;

    // Optional: Draw a background circle if needed
    // final Paint circlePaint = Paint()..color = Colors.blue; // Example background
    // canvas.drawCircle(Offset(radius, radius), radius, circlePaint);

    // ADDED: Draw semi-transparent background circle using the provided color
    final Paint circlePaint = Paint()
      ..color =
          backgroundColor.withOpacity(0.7); // Use passed color with 70% opacity
    canvas.drawCircle(Offset(radius, radius), radius, circlePaint);

    // Draw text (emoji)
    final ui.ParagraphBuilder paragraphBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.center,
        fontSize: size * 0.7, // Adjust emoji size relative to marker size
      ),
    );
    paragraphBuilder.addText(text);
    final ui.Paragraph paragraph = paragraphBuilder.build();
    paragraph.layout(ui.ParagraphConstraints(width: size.toDouble()));

    // Center the emoji text
    final double textX = (size - paragraph.width) / 2;
    final double textY = (size - paragraph.height) / 2;
    canvas.drawParagraph(paragraph, Offset(textX, textY));

    // Convert canvas to image
    final ui.Image image = await pictureRecorder
        .endRecording()
        .toImage(size, size); // Use size for both width and height

    // Convert image to bytes
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw Exception('Failed to convert image to byte data');
    }

    return BitmapDescriptor.fromBytes(byteData.buffer.asUint8List());
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
          userColorCategories: _colorCategories,
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
            // ADDED: Provide a default initial location to avoid widget loading delay
            initialLocation: Location(
                latitude: 37.4219999, longitude: -122.0840575), // Googleplex
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
