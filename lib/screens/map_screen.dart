import 'dart:async'; // Import async
import 'dart:typed_data'; // Import for ByteData
import 'dart:ui' as ui; // Import for ui.Image, ui.Canvas etc.
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'; // Add Google Maps import
import 'package:url_launcher/url_launcher.dart'; // ADDED: Import url_launcher
import '../widgets/google_maps_widget.dart';
import '../services/experience_service.dart'; // Import ExperienceService
import '../services/auth_service.dart'; // Import AuthService
import '../services/google_maps_service.dart'; // Import GoogleMapsService
import '../services/sharing_service.dart'; // ADDED: SharingService for shared experiences
import '../models/enums/share_enums.dart'; // ADDED: ShareableItemType enum
import '../models/user_profile.dart'; // ADDED: UserProfile for owner names
import '../models/experience.dart'; // Import Experience model (includes Location)
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
  final Location? initialExperienceLocation; // ADDED: To receive a specific location

  const MapScreen({super.key, this.initialExperienceLocation}); // UPDATED: Constructor

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
  // ADDED: Cache of owner display names for shared categories
  final Map<String, String> _ownerNameByUserId = {};
  final Completer<GoogleMapController> _mapControllerCompleter =
      Completer<GoogleMapController>();
  // ADDED: Cache for generated category icons
  final Map<String, BitmapDescriptor> _categoryIconCache = {};

  // ADDED: State for selected filters
  Set<String> _selectedCategoryIds = {}; // Empty set means no filter
  Set<String> _selectedColorCategoryIds = {}; // Empty set means no filter

  // ADDED: State for tapped location
  Marker? _tappedLocationMarker;
  Location? _tappedLocationDetails;
  Experience? _tappedExperience; // ADDED: Track associated experience
  UserCategory? _tappedExperienceCategory; // ADDED: Track associated category
  String? _tappedLocationBusinessStatus; // ADDED: Track business status for tapped location
  bool? _tappedLocationOpenNow; // ADDED: Track open-now status

  // ADDED: State for search functionality
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Map<String, dynamic>> _searchResults = [];
  bool _showSearchResults = false;
  bool _isSearching = false;
  Timer? _debounce;
  GoogleMapController? _mapController; // To be initialized from _mapControllerCompleter
  bool _isProgrammaticTextUpdate = false; // RE-ADDED
  Location? _mapWidgetInitialLocation; // ADDED: To control GoogleMapsWidget initial location
  // ADDED: Indicates background loading of shared experiences
  bool _isSharedLoading = false;

  @override
  void initState() {
    super.initState();

    if (widget.initialExperienceLocation != null) {
      // If a specific location is passed, use it for the map's initial center
      _mapWidgetInitialLocation = widget.initialExperienceLocation;
      print(
          "🗺️ MAP SCREEN: Initializing with provided experience location: ${widget.initialExperienceLocation!.getPlaceName()}");
      // Animate to this location once the map controller is ready
      _mapControllerCompleter.future.then((controller) {
        if (mounted) {
          if (!_mapControllerCompleter.isCompleted) {
             _mapControllerCompleter.complete(controller);
          }
          _mapController = controller;
          final target = LatLng(widget.initialExperienceLocation!.latitude,
              widget.initialExperienceLocation!.longitude);
          print(
              "🗺️ MAP SCREEN: Animating to provided initial experience location: $target");
          _mapController!
              .animateCamera(CameraUpdate.newLatLngZoom(target, 15.0));
        }
      });
    } else {
      // Default behavior: set a generic initial location and then focus on user's current GPS location
      _mapWidgetInitialLocation = Location(
          latitude: 37.4219999,
          longitude: -122.0840575,
          displayName: "Default Location"); // Googleplex
      _focusOnUserLocation();
    }

    _loadDataAndGenerateMarkers(); // Load all experiences and their markers
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged); // ADDED: Remove listener here
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
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

      // Fetch owned data in parallel (categories, color categories, owned experiences)
      final ownedResults = await Future.wait([
        _experienceService.getUserCategories(),
        _experienceService.getUserColorCategories(),
        _experienceService.getExperiencesByUser(userId),
      ]);

      _categories = ownedResults[0] as List<UserCategory>;
      _colorCategories = ownedResults[1] as List<ColorCategory>;
      _experiences = ownedResults[2] as List<Experience>;
      print(
          "🗺️ MAP SCREEN: Loaded ${_experiences.length} owned experiences and ${_categories.length}/${_colorCategories.length} categories.");

      // Render markers immediately for owned experiences
      await _generateMarkersFromExperiences(_experiences);

      // Kick off shared experiences loading in the background (no await)
      _loadSharedExperiencesInBackground(userId);

      /* --- REMOVED Marker generation loop (moved to _generateMarkersFromExperiences) ---
      _markers.clear();
      // We will calculate bounds manually now
      double minLat = double.infinity;
      double maxLat = double.negativeInfinity;
      double minLng = double.infinity;
      double maxLng = double.negativeInfinity;
      bool hasValidMarkers = false;

      for (final experience in _experiences) {
          // ... (loop content removed) ...
      }

      print("🗺️ MAP SCREEN: Generated ${_markers.length} valid markers.");
      */
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

  // Load shared experiences after initial render and merge incrementally
  Future<void> _loadSharedExperiencesInBackground(String userId) async {
    try {
      setState(() {
        _isSharedLoading = true;
      });
      final sharingService = SharingService();
      final sharedPermissions =
          await sharingService.getSharedItemsForUser(userId);
      final sharedExperienceIds = sharedPermissions
          .where((perm) => perm.itemType == ShareableItemType.experience)
          .map((perm) => perm.itemId)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      if (sharedExperienceIds.isEmpty) {
        print("🗺️ MAP SCREEN: No shared experiences to load in background.");
        return;
      }

      // Map shared experience ID -> owner user ID
      final Map<String, String> sharedExpOwnerById = {};
      for (final perm in sharedPermissions) {
        if (perm.itemType == ShareableItemType.experience &&
            perm.itemId.isNotEmpty &&
            perm.ownerUserId.isNotEmpty) {
          sharedExpOwnerById[perm.itemId] = perm.ownerUserId;
        }
      }

      print(
          "🗺️ MAP SCREEN: [BG] Fetching ${sharedExperienceIds.length} shared experiences...");
      final sharedExperiences =
          await _experienceService.getExperiencesByIds(sharedExperienceIds);
      print(
          "🗺️ MAP SCREEN: [BG] Loaded ${sharedExperiences.length} shared experiences.");

      // Fetch referenced owners' categories/color categories that are missing locally
      final Set<String> existingCategoryIds =
          _categories.map((c) => c.id).toSet();
      final Set<String> existingColorCategoryIds =
          _colorCategories.map((c) => c.id).toSet();

      final Set<String> requestedCategoryPairKeys = {};
      final Set<String> requestedColorPairKeys = {};
      final List<Future<UserCategory?>> categoryFetches = [];
      final List<Future<ColorCategory?>> colorFetches = [];

      for (final exp in sharedExperiences) {
        final ownerId = sharedExpOwnerById[exp.id];
        if (ownerId == null || ownerId.isEmpty) continue;

        final String? catId = exp.categoryId;
        if (catId != null && catId.isNotEmpty &&
            !existingCategoryIds.contains(catId)) {
          final key = ownerId + '|' + catId;
          if (requestedCategoryPairKeys.add(key)) {
            categoryFetches
                .add(_experienceService.getUserCategoryByOwner(ownerId, catId));
          }
        }

        for (final oc in exp.otherCategories) {
          if (oc.isEmpty || existingCategoryIds.contains(oc)) continue;
          final key = ownerId + '|' + oc;
          if (requestedCategoryPairKeys.add(key)) {
            categoryFetches
                .add(_experienceService.getUserCategoryByOwner(ownerId, oc));
          }
        }

        final String? colorId = exp.colorCategoryId;
        if (colorId != null && colorId.isNotEmpty &&
            !existingColorCategoryIds.contains(colorId)) {
          final key = ownerId + '|' + colorId;
          if (requestedColorPairKeys.add(key)) {
            colorFetches.add(
                _experienceService.getColorCategoryByOwner(ownerId, colorId));
          }
        }
      }

      if (categoryFetches.isNotEmpty) {
        try {
          final fetchedCats = await Future.wait(categoryFetches);
          final newCats = fetchedCats.whereType<UserCategory>().toList();
          if (newCats.isNotEmpty) {
            _categories.addAll(newCats);
            print(
                "🗺️ MAP SCREEN: [BG] Added ${newCats.length} shared user categories.");
          }
        } catch (e) {
          print("🗺️ MAP SCREEN: [BG] Error fetching shared categories: $e");
        }
      }

      if (colorFetches.isNotEmpty) {
        try {
          final fetchedColors = await Future.wait(colorFetches);
          final newColors = fetchedColors.whereType<ColorCategory>().toList();
          if (newColors.isNotEmpty) {
            _colorCategories.addAll(newColors);
            print(
                "🗺️ MAP SCREEN: [BG] Added ${newColors.length} shared color categories.");
          }
        } catch (e) {
          print("🗺️ MAP SCREEN: [BG] Error fetching shared color categories: $e");
        }
      }

      // Fetch owner display names (deduped)
      try {
        final Set<String> ownerIdsToFetch = {};
        for (final c in _categories) {
          if (c.ownerUserId.isNotEmpty &&
              c.ownerUserId != userId &&
              !_ownerNameByUserId.containsKey(c.ownerUserId)) {
            ownerIdsToFetch.add(c.ownerUserId);
          }
        }
        for (final cc in _colorCategories) {
          if (cc.ownerUserId.isNotEmpty &&
              cc.ownerUserId != userId &&
              !_ownerNameByUserId.containsKey(cc.ownerUserId)) {
            ownerIdsToFetch.add(cc.ownerUserId);
          }
        }

        if (ownerIdsToFetch.isNotEmpty) {
          final List<UserProfile?> profiles = await Future.wait(
              ownerIdsToFetch.map((oid) => _experienceService.getUserProfileById(oid)));
          final Map<String, String> newNames = {};
          for (final p in profiles) {
            if (p != null) {
              final name = (p.displayName ?? p.username ?? 'Unknown');
              newNames[p.id] = name;
            }
          }
          if (newNames.isNotEmpty && mounted) {
            setState(() {
              _ownerNameByUserId.addAll(newNames);
            });
          }
        }
      } catch (e) {
        print("🗺️ MAP SCREEN: [BG] Error fetching owner names: $e");
      }

      // Merge and update markers
      final Map<String, Experience> combined = {
        for (final e in _experiences) e.id: e,
      };
      for (final e in sharedExperiences) {
        combined[e.id] = e;
      }

      if (mounted) {
        setState(() {
          _experiences = combined.values.toList();
        });
      }

      await _generateMarkersFromExperiences(_experiences);
      print("🗺️ MAP SCREEN: [BG] Shared experiences merged and markers updated.");
    } catch (e) {
      print(
          "🗺️ MAP SCREEN: [BG] Error loading shared experiences: $e. Skipping background merge.");
    } finally {
      if (mounted) {
        setState(() {
          _isSharedLoading = false;
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
      // final GoogleMapController controller = // Commented out, will use _mapController
      //     await _mapControllerCompleter.future;
      _mapController ??= await _mapControllerCompleter.future;
      print("🗺️ MAP SCREEN: Map controller ready. Fetching user location...");

      // Get current location
      final position = await _mapsService.getCurrentLocation();
      final userLatLng = LatLng(position.latitude, position.longitude);
      final userLocationForMapWidget = Location(
        latitude: position.latitude,
        longitude: position.longitude,
        displayName: "My Current Location"
      );
      print(
          "🗺️ MAP SCREEN: User location fetched: $userLatLng. Animating camera...");

      // Animate camera to user location
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(userLatLng, 14.0), // Zoom level 14
      );
      print("🗺️ MAP SCREEN: Camera animation initiated.");

      // Update the initial location for the map widget after animation
      if (mounted) {
        setState(() {
          _mapWidgetInitialLocation = userLocationForMapWidget;
        });
        print("🗺️ MAP SCREEN: Updated _mapWidgetInitialLocation to user's location.");
      }
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
    double backgroundOpacity = 0.7, // ADDED: Opacity parameter
  }) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final double radius = size / 2;

    // Optional: Draw a background circle if needed
    // final Paint circlePaint = Paint()..color = Colors.blue; // Example background
    // canvas.drawCircle(Offset(radius, radius), radius, circlePaint);

    // MODIFIED: Draw background circle using the provided color and opacity
    final Paint circlePaint = Paint()
      ..color =
          backgroundColor.withOpacity(backgroundOpacity); // Use passed opacity
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
    // Clear the temporary tapped marker when navigating away
    setState(() {
      _tappedLocationMarker = null;
      _tappedLocationDetails = null;
      _tappedExperience = null; // ADDED: Clear associated experience
      _tappedExperienceCategory = null; // ADDED: Clear associated category
      _tappedLocationBusinessStatus = null; // ADDED: Clear business status
      _tappedLocationOpenNow = null; // ADDED: Clear open-now status
    });
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
    // ADDED: Assign to _mapController as well
    _mapController = controller;
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

  // --- ADDED: Filter Dialog ---
  Future<void> _showFilterDialog() async {
    // Create temporary sets to hold selections within the dialog
    Set<String> tempSelectedCategoryIds = Set.from(_selectedCategoryIds);
    Set<String> tempSelectedColorCategoryIds =
        Set.from(_selectedColorCategoryIds);

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Filter Experiences'),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.85,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: StatefulBuilder(
              // Use StatefulBuilder to manage state within the dialog
              builder: (BuildContext context, StateSetter setStateDialog) {
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('By Category:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      // FIX: Correctly use map().toList() to generate CheckboxListTiles
                      ...(_categories.toList()
                            ..sort((a, b) => a.name.compareTo(b.name)))
                          .map((category) {
                        final bool isSharedOwner = category.ownerUserId != _authService.currentUser?.uid;
                        final String? ownerName = isSharedOwner ? _ownerNameByUserId[category.ownerUserId] : null;
                        // This map returns a Widget (CheckboxListTile)
                        return CheckboxListTile(
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    child: Center(child: Text(category.icon)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      category.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (isSharedOwner && ownerName != null && ownerName.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 28),
                                  child: Text(
                                    '(Shared by ${ownerName})',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: null,
                          value: tempSelectedCategoryIds.contains(category.id),
                          onChanged: (bool? selected) {
                            setStateDialog(() {
                              if (selected == true) {
                                tempSelectedCategoryIds.add(category.id);
                              } else {
                                tempSelectedCategoryIds.remove(category.id);
                              }
                            });
                          },
                        );
                      }), // This creates List<CheckboxListTile>
                      const SizedBox(height: 16),
                      const Text('By Color:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      // FIX: Correctly use map().toList() to generate CheckboxListTiles
                      ...(_colorCategories.toList()
                            ..sort((a, b) => a.name.compareTo(b.name)))
                          .map((colorCategory) {
                        final bool isSharedOwner = colorCategory.ownerUserId != _authService.currentUser?.uid;
                        final String? ownerName = isSharedOwner ? _ownerNameByUserId[colorCategory.ownerUserId] : null;
                        // This map returns a Widget (CheckboxListTile)
                        return CheckboxListTile(
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                        color: _parseColor(colorCategory.colorHex),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.grey)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      colorCategory.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (isSharedOwner && ownerName != null && ownerName.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 28),
                                  child: Text(
                                    '(Shared by ${ownerName})',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: null,
                          value: tempSelectedColorCategoryIds
                              .contains(colorCategory.id),
                          onChanged: (bool? selected) {
                            setStateDialog(() {
                              if (selected == true) {
                                tempSelectedColorCategoryIds
                                    .add(colorCategory.id);
                              } else {
                                tempSelectedColorCategoryIds
                                    .remove(colorCategory.id);
                              }
                            });
                          },
                        );
                      }),
                    ],
                  ),
                );
              },
            ),
          )),
          actions: <Widget>[
            // ADDED: Show All Button
            TextButton(
              child: const Text('Show All'),
              onPressed: () {
                // Clear temporary selections
                tempSelectedCategoryIds.clear();
                tempSelectedColorCategoryIds.clear();

                // Apply the cleared filters directly to the main state
                setState(() {
                  _selectedCategoryIds = tempSelectedCategoryIds; // Now empty
                  _selectedColorCategoryIds =
                      tempSelectedColorCategoryIds; // Now empty
                });

                Navigator.of(context).pop(); // Close the dialog
                _applyFiltersAndUpdateMarkers(); // Apply filters (which are now empty) and update map
              },
            ),
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog without applying
              },
            ),
            TextButton(
              child: const Text('Apply'),
              onPressed: () {
                // Apply the selected filters from the temporary sets
                setState(() {
                  _selectedCategoryIds = tempSelectedCategoryIds;
                  _selectedColorCategoryIds = tempSelectedColorCategoryIds;
                });
                Navigator.of(context).pop(); // Close the dialog
                _applyFiltersAndUpdateMarkers(); // Apply filters and update map
              },
            ),
          ],
        );
      },
    );
  }
  // --- END Filter Dialog ---

  // --- ADDED: Function to apply filters and regenerate markers ---
  Future<void> _applyFiltersAndUpdateMarkers() async {
    print("🗺️ MAP SCREEN: Applying filters and updating markers...");
    setState(() {
      _isLoading = true; // Show loading indicator while filtering
    });

    try {
      // Filter experiences based on selected IDs
      final filteredExperiences = _experiences.where((exp) {
        // Find the category ID based on the experience's category name
        // String? expCategoryId; // REMOVED: No longer need to look up by name
        // try {
        //   expCategoryId = 
        //       _categories.firstWhere((cat) => cat.name == exp.category).id;
        // } catch (e) {
        //   // Handle case where category name doesn't match any known category
        //   expCategoryId = null;
        //   print(
        //       "🗺️ MAP SCREEN: Warning - Could not find category ID for category name: ${exp.category}");
        // }

        // MODIFIED: Use exp.categoryId directly
        final bool categoryMatch = _selectedCategoryIds.isEmpty ||
            (exp.categoryId != null && // Check if categoryId exists
                _selectedCategoryIds.contains(exp.categoryId)) || // Check if it's in the selected set
            (exp.otherCategories.any((catId) => _selectedCategoryIds.contains(catId))); // Check if any other category matches

        final bool colorMatch = _selectedColorCategoryIds.isEmpty ||
            (exp.colorCategoryId != null &&
                _selectedColorCategoryIds.contains(exp.colorCategoryId));

        return categoryMatch && colorMatch;
      }).toList();

      print(
          "🗺️ MAP SCREEN: Filtered ${_experiences.length} experiences down to ${filteredExperiences.length}");

      // Regenerate markers from the filtered list
      _generateMarkersFromExperiences(filteredExperiences);

      // Optionally: Animate camera to fit the filtered markers if needed
      // This might be desired behavior after filtering
      // final GoogleMapController controller = await _mapControllerCompleter.future;
      // final bounds = _calculateBoundsFromMarkers(_markers); // Use the updated _markers
      // if (bounds != null) {
      //   controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50.0));
      // }
      _mapController ??= await _mapControllerCompleter.future;
      final bounds = _calculateBoundsFromMarkers(_markers);
      if (bounds != null && _mapController != null) {
        _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50.0));
      }
    } catch (e, stackTrace) {
      print("🗺️ MAP SCREEN: Error applying filters: $e");
      print(stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error applying filters: $e')),
        );
      }
    } finally {
      if (mounted) {
        print("🗺️ MAP SCREEN: Filter application finished.");
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  // --- END Apply Filters ---

  // --- REFACTORED: Marker generation logic ---
  Future<void> _generateMarkersFromExperiences(
      List<Experience> experiencesToMark) async {
    Map<String, Marker> tempMarkers = {};

    for (final experience in experiencesToMark) {
      // Basic validation for location data
      if (experience.location.latitude == 0.0 &&
          experience.location.longitude == 0.0) {
        print(
            "🗺️ MAP SCREEN: Skipping experience '${experience.name}' due to invalid coordinates (0,0).");
        continue; // Skip markers with default/invalid coordinates
      }

      // MODIFIED: Find category using categoryId
      final category = _categories.firstWhere(
        (cat) => cat.id == experience.categoryId, // Use categoryId for matching
        orElse: () =>
            UserCategory(id: '', name: 'Uncategorized', icon: '❓', ownerUserId: ''), // Updated fallback
      );

      // Find the corresponding color category *based on the experience's property*
      ColorCategory? colorCategory;
      String? experienceColorCategoryId =
          experience.colorCategoryId; // Get the ID (nullable)

      if (experienceColorCategoryId != null) {
        // print(
        //     "🗺️ MAP SCREEN: Searching for ColorCategory with ID: '${experienceColorCategoryId}' for experience '${experience.name}'");
        try {
          colorCategory = _colorCategories.firstWhere(
            (cc) => cc.id == experienceColorCategoryId, // Match by ID now
          );
          // print(
          //     "🗺️ MAP SCREEN: Found ColorCategory '${colorCategory.name}' with color ${colorCategory.colorHex}");
        } catch (e) {
          colorCategory = null; // Not found
          // print(
          //     "🗺️ MAP SCREEN: No ColorCategory found matching ID '${experienceColorCategoryId}'. Using default color.");
        }
      } else {
        // print(
        //     "🗺️ MAP SCREEN: Experience '${experience.name}' has no colorCategoryId. Using default color.");
      }

      // Determine marker background color
      Color markerBackgroundColor = Colors.grey; // Default
      if (colorCategory != null && colorCategory.colorHex.isNotEmpty) {
        markerBackgroundColor = _parseColor(colorCategory.colorHex);
        // print(
        //     "🗺️ MAP SCREEN: Using color ${markerBackgroundColor} for category '${category.name}'.");
      }

      // Generate a unique cache key including the color and the *icon*
      final String cacheKey = '${category.icon}_${markerBackgroundColor.value}';

      BitmapDescriptor categoryIconBitmap =
          BitmapDescriptor.defaultMarker; // Default

      // Use cache or generate new icon
      if (_categoryIconCache.containsKey(cacheKey)) {
        categoryIconBitmap = _categoryIconCache[cacheKey]!;
        // print(
        //     "🗺️ MAP SCREEN: Using cached icon '$cacheKey' for ${category.name}");
      } else {
        try {
          // print(
          //     "🗺️ MAP SCREEN: Generating icon for '$cacheKey' (${category.name})");
          // Pass the background color to the generator
          categoryIconBitmap = await _bitmapDescriptorFromText(
            category.icon,
            backgroundColor: markerBackgroundColor,
            size: 70,
          );
          _categoryIconCache[cacheKey] = categoryIconBitmap; // Cache the result
        } catch (e) {
          print(
              "🗺️ MAP SCREEN: Failed to generate bitmap for icon '$cacheKey': $e");
          // Keep the default marker if generation fails
        }
      }

      final position = LatLng(
        experience.location.latitude,
        experience.location.longitude,
      );

      // Logging marker details
      // print(
      //     "🗺️ MAP SCREEN: Creating marker for '${experience.name}' at ${position.latitude}, ${position.longitude}");

      final markerId = MarkerId(experience.id);
      final marker = Marker(
        markerId: markerId,
        position: position,
        infoWindow: InfoWindow(
          title: '${category.icon} ${experience.name}',
          snippet: experience.location.getPlaceName(),
        ),
        icon: categoryIconBitmap,
        // MODIFIED: Experience marker onTap shows location details panel
        onTap: () async {
          FocusScope.of(context).unfocus(); // Unfocus search bar
          print("🗺️ MAP SCREEN: Experience marker tapped for '${experience.name}'. Showing location details panel.");
          
          // --- REGENERATING ICON FOR SELECTED STATE ---
          Color markerBackgroundColor = Colors.grey;
          try {
            if (experience.colorCategoryId != null) {
              final colorCategory = _colorCategories.firstWhere((cc) => cc.id == experience.colorCategoryId);
              markerBackgroundColor = _parseColor(colorCategory.colorHex);
            }
          } catch (e) { /* Use default grey color */ }

          final selectedIcon = await _bitmapDescriptorFromText(
            category.icon,
            backgroundColor: markerBackgroundColor,
            size: 100, // 125% of 70
            backgroundOpacity: 1.0, // Fully opaque
          );
          // --- END ICON REGENERATION ---

          // Create a marker for the selected experience location
          final tappedMarkerId = MarkerId('selected_experience_location');
          final tappedMarker = Marker(
            markerId: tappedMarkerId,
            position: position,
            infoWindow: InfoWindow(
              title: '${category.icon} ${experience.name}',
              snippet: experience.location.getPlaceName(),
            ),
            icon: selectedIcon, // Use the new enlarged icon
            zIndex: 1.0,
          );

          // Fetch business and open-now status for the experience location if possible
          String? businessStatus;
          bool? openNow;
          try {
            if (experience.location.placeId != null && experience.location.placeId!.isNotEmpty) {
              final detailsMap = await _mapsService.fetchPlaceDetailsData(experience.location.placeId!);
              businessStatus = detailsMap?['businessStatus'] as String?;
              openNow = (detailsMap?['currentOpeningHours']?['openNow']) as bool?;
            }
          } catch (e) {
            businessStatus = null;
            openNow = null;
          }

          setState(() {
            _mapWidgetInitialLocation = experience.location;
            _tappedLocationDetails = experience.location;
            _tappedLocationMarker = tappedMarker;
            _tappedExperience = experience; // Set associated experience
            _tappedExperienceCategory = category; // Set associated category
            _tappedLocationBusinessStatus = businessStatus; // Set business status
            _tappedLocationOpenNow = openNow; // Set open-now status
            _searchController.clear();
            _searchResults = [];
            _showSearchResults = false;
          });
        },
      );
      tempMarkers[experience.id] = marker;
    }

    print(
        "🗺️ MAP SCREEN: Generated ${tempMarkers.length} experience markers from ${experiencesToMark.length} experiences.");

    if (mounted) {
      setState(() {
        _markers.clear();
        _markers.addAll(tempMarkers);
      });
    }
  }
  // --- END REFACTORED Marker generation ---

  // --- ADDED: Handle location selection from GoogleMapsWidget ---
  Future<void> _handleLocationSelected(Location locationDetails) async {
    FocusScope.of(context).unfocus(); // ADDED: Unfocus search bar
    print(
        "🗺️ MAP SCREEN: Location selected via widget callback: ${locationDetails.displayName}");

    print("🗺️ MAP SCREEN: (_handleLocationSelected) Removing search listener before clearing text");
    _searchController.removeListener(_onSearchChanged);
    print("🗺️ MAP SCREEN: (_handleLocationSelected) Listener removed. Clearing text next.");

    // Clear the search text. If listener was still active, this would trigger _onSearchChanged.
    _searchController.clear(); 
    print("🗺️ MAP SCREEN: (_handleLocationSelected) Text cleared.");

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        print("🗺️ MAP SCREEN: (_handleLocationSelected POST-FRAME) Re-adding search listener.");
        _searchController.addListener(_onSearchChanged);
        print("🗺️ MAP SCREEN: (_handleLocationSelected POST-FRAME) Search listener re-added.");
      } else {
        print("🗺️ MAP SCREEN: (_handleLocationSelected POST-FRAME) NOT RUNNING because !mounted.");
      }
    });

    _isProgrammaticTextUpdate = false; 

    // Show loading immediately for this operation
    if(mounted){
      setState(() {
        _isLoading = true; 
        _searchResults = [];
        _showSearchResults = false;
      });
    }
    

    try {
      // MODIFIED: Fetch full details if placeId is available
      Location finalLocationDetails = locationDetails;
      if (locationDetails.placeId != null && locationDetails.placeId!.isNotEmpty) {
        print("🗺️ MAP SCREEN: (_handleLocationSelected) Map tap has Place ID: ${locationDetails.placeId}. Fetching details...");
        try {
          finalLocationDetails = await _mapsService.getPlaceDetails(locationDetails.placeId!);
          print("🗺️ MAP SCREEN: (_handleLocationSelected) Fetched details for map tap: ${finalLocationDetails.displayName}, Rating: ${finalLocationDetails.rating}");
        } catch (e) {
          print("🗺️ MAP SCREEN: (_handleLocationSelected) Error fetching details for map tap location: $e. Using initial details.");
          // finalLocationDetails remains locationDetails (original)
        }
      } else {
        print("🗺️ MAP SCREEN: (_handleLocationSelected) Map tap location has no Place ID. Using basic info.");
      }

      print(
          "🗺️ MAP SCREEN: Selected location details: Name='${finalLocationDetails.displayName}', Address='${finalLocationDetails.address}', PlaceID='${finalLocationDetails.placeId}'");
      // Fetch business/open-now status using Places API v1 details
      String? businessStatus;
      bool? openNow;
      try {
        if (finalLocationDetails.placeId != null && finalLocationDetails.placeId!.isNotEmpty) {
          final detailsMap = await _mapsService.fetchPlaceDetailsData(finalLocationDetails.placeId!);
          businessStatus = detailsMap?['businessStatus'] as String?;
          openNow = (detailsMap?['currentOpeningHours']?['openNow']) as bool?;
        }
      } catch (e) {
        businessStatus = null;
        openNow = null;
      }
      
      final LatLng targetLatLng = LatLng(finalLocationDetails.latitude, finalLocationDetails.longitude);

      // Animate camera to the tapped location
      // Ensure map controller is available before animating
      GoogleMapController currentMapController;
      if (_mapController != null) {
          currentMapController = _mapController!;
      } else {
          print("🗺️ MAP SCREEN: (_handleLocationSelected) Awaiting map controller for animation...");
          currentMapController = await _mapControllerCompleter.future;
          print("🗺️ MAP SCREEN: (_handleLocationSelected) Map controller obtained for animation.");
      }
      currentMapController.animateCamera(
        CameraUpdate.newLatLng(targetLatLng),
      );


      // Create a new marker for the selected location
      final tappedMarkerId = MarkerId('selected_location'); 
      final tappedMarker = Marker(
        markerId: tappedMarkerId,
        position: targetLatLng, 
        infoWindow: InfoWindow(
          title:
              finalLocationDetails.getPlaceName(), 
          snippet:
              '${finalLocationDetails.address ?? 'Unknown Address'}\nTap for Directions',
          onTap: () {
            print(
                "🗺️ MAP SCREEN: InfoWindow tapped for ${_tappedLocationDetails?.displayName}");
            if (_tappedLocationDetails != null) {
              _openDirectionsForLocation(_tappedLocationDetails!);
            }
          },
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        zIndex:
            1.0, 
      );

      // Update state to show the new marker and set initial location for map widget
      if (mounted) {
        setState(() {
          _mapWidgetInitialLocation = finalLocationDetails; // Update map widget's initial location
          _tappedLocationDetails = finalLocationDetails;
          _tappedLocationMarker = tappedMarker;
          _tappedExperience = null; // ADDED: Clear associated experience for map-tapped locations
          _tappedExperienceCategory = null; // ADDED: Clear associated category for map-tapped locations
          _tappedLocationBusinessStatus = businessStatus; // ADDED: Set business status
          _tappedLocationOpenNow = openNow; // ADDED: Set open-now status
          _isLoading = false; 
        });
        print("🗺️ MAP SCREEN: (_handleLocationSelected) Updated state with new tapped location and map initial location: ${finalLocationDetails.getPlaceName()}");
      }

    } catch (e) {
      print("🗺️ MAP SCREEN: Error handling location selection: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing selected location: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false; // Ensure loading indicator is off
        });
      }
    }
  }
  // --- END Handle location selection ---

  // --- ADDED: Open Directions ---
  Future<void> _openDirectionsForLocation(Location location) async {
    print(
        "🗺️ MAP SCREEN: Opening directions for ${location.displayName ?? location.address}");

    // Use the Place ID if available for a more specific destination
    final url = _mapsService.getDirectionsUrl(location);
    final uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        // Clear the temporary marker after successfully launching maps
        if (mounted) {
          setState(() {
            _tappedLocationMarker = null;
            _tappedLocationDetails = null;
            _tappedLocationBusinessStatus = null;
            _tappedLocationOpenNow = null;
          });
        }
      } catch (e) {
        print("🗺️ MAP SCREEN: Could not launch $uri: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open Google Maps')),
          );
        }
      }
    } else {
      print("🗺️ MAP SCREEN: Cannot launch URL: $uri");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not open Google Maps application')),
        );
      }
    }
  }
  // --- END Open Directions ---

  // --- ADDED: Helper method to launch map location directly --- //
  Future<void> _launchMapLocation(Location location) async {
    final String mapUrl;
    // Prioritize Place ID if available for a more specific search
    if (location.placeId != null && location.placeId!.isNotEmpty) {
      // Use the Google Maps search API with place_id format
      final placeName =
          location.displayName ?? location.address ?? 'Selected Location';
      mapUrl =
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(placeName)}&query_place_id=${location.placeId}';
      print('🗺️ MAP SCREEN: Launching Map with Place ID: $mapUrl');
    } else {
      // Fallback to coordinate-based URL if no place ID
      final lat = location.latitude;
      final lng = location.longitude;
      mapUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
      print('🗺️ MAP SCREEN: Launching Map with Coordinates: $mapUrl');
    }

    final Uri mapUri = Uri.parse(mapUrl);

    if (!await launchUrl(mapUri, mode: LaunchMode.externalApplication)) {
      print('🗺️ MAP SCREEN: Could not launch $mapUri');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open map location.')),
        );
      }
    }
    // Clear the temporary marker after successfully launching maps
    if (mounted) {
      setState(() {
        _tappedLocationMarker = null;
        _tappedLocationDetails = null;
        _tappedLocationBusinessStatus = null;
        _tappedLocationOpenNow = null;
      });
    }
  }
  // --- END: Helper method to launch map location --- //

  // --- ADDED: Search functionality from LocationPickerScreen ---

  // Helper method to calculate distance between coordinates (copied from LocationPickerScreen)
  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    // Simple Euclidean distance - good enough for sorting
    return (lat1 - lat2) * (lat1 - lat2) + (lon1 - lon2) * (lon1 - lon2);
  }

  // ADDED: Helper method to search through user's saved experiences
  List<Map<String, dynamic>> _searchUserExperiences(String query) {
    final queryLower = query.toLowerCase();
    final matchingExperiences = <Map<String, dynamic>>[];

    for (final experience in _experiences) {
      final experienceName = experience.name.toLowerCase();
      final locationName = experience.location.displayName?.toLowerCase() ?? '';
      final locationAddress = experience.location.address?.toLowerCase() ?? '';
      
      // Check if query matches experience name, location name, or address
      if (experienceName.contains(queryLower) || 
          locationName.contains(queryLower) || 
          locationAddress.contains(queryLower)) {
        
        // Find the category for display
        final category = _categories.firstWhere(
          (cat) => cat.id == experience.categoryId,
          orElse: () => UserCategory(id: '', name: 'Uncategorized', icon: '❓', ownerUserId: ''),
        );

        matchingExperiences.add({
          'type': 'experience',
          'experienceId': experience.id,
          'experience': experience,
          'category': category,
          'description': '${category.icon} ${experience.name}',
          'address': experience.location.getPlaceName(),
          'latitude': experience.location.latitude,
          'longitude': experience.location.longitude,
          'placeId': experience.location.placeId,
          'rating': experience.location.rating,
          'userRatingCount': experience.location.userRatingCount,
        });
      }
    }

    return matchingExperiences;
  }

  Future<void> _searchPlaces(String query) async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      print("🗺️ MAP SCREEN: (_searchPlaces DEBOUNCED) Query: '$query', _isProgrammaticTextUpdate: $_isProgrammaticTextUpdate");

      if (_isProgrammaticTextUpdate) {
        // This path should ideally not be taken if _selectSearchResult resets the flag.
        // If it is taken, it means a search was triggered while the flag was still true.
        print("🗺️ MAP SCREEN: (_searchPlaces) Safeguard: Detected _isProgrammaticTextUpdate = true. Suppressing search and resetting flag.");
        if (mounted) {
          setState(() {
            _isSearching = false; // Ensure _isSearching is false if this path is taken.
            _showSearchResults = false; // Ensure results list is hidden
          });
        }
        _isProgrammaticTextUpdate = false; // Reset immediately.
        print("🗺️ MAP SCREEN: (_searchPlaces) Reset _isProgrammaticTextUpdate directly inside safeguard.");
        return;
      }

      if (query.isEmpty) {
        print("🗺️ MAP SCREEN: (_searchPlaces DEBOUNCED) Query is empty. Clearing results.");
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
          // This is a new user-initiated search or a map tap that cleared search, so clear previous details
          _tappedLocationDetails = null;
          _tappedLocationMarker = null;
          _tappedExperience = null; // ADDED: Clear associated experience
          _tappedExperienceCategory = null; // ADDED: Clear associated category
          _tappedLocationBusinessStatus = null; // ADDED: Clear business status
          _tappedLocationOpenNow = null; // ADDED: Clear open-now status
        });
      }

      try {
        // MODIFIED: First search user's experiences
        final experienceResults = _searchUserExperiences(query);
        print("🗺️ MAP SCREEN: (_searchPlaces DEBOUNCED) Found ${experienceResults.length} matching user experiences for query: '$query'");

        // Then search Google Maps
        print("🗺️ MAP SCREEN: (_searchPlaces DEBOUNCED) Calling _mapsService.searchPlaces for query: '$query'");
        final mapsResults = await _mapsService.searchPlaces(query);
        print("🗺️ MAP SCREEN: (_searchPlaces DEBOUNCED) Received ${mapsResults.length} results from _mapsService for query: '$query'");
        

        // Mark Google Maps results as type 'place'
        final markedMapsResults = mapsResults.map((result) {
          return {
            'type': 'place',
            ...result,
          };
        }).toList();

        // Combine results with experiences first (prioritized)
        final allResults = [...experienceResults, ...markedMapsResults];

        LatLng? mapCenter;
        if (_mapController != null) {
          try {
            if (mounted) {
                 mapCenter = await _mapController!.getLatLng(ScreenCoordinate(
                  x: MediaQuery.of(context).size.width ~/ 2,
                  y: MediaQuery.of(context).size.height ~/ 2));
            }
          } catch (e) {
            print('🗺️ MAP SCREEN: Error getting map center for search: $e');
          }
        }

        allResults.sort((a, b) {
          final String nameA = (a['description'] ?? '').toString().toLowerCase();
          final String nameB = (b['description'] ?? '').toString().toLowerCase();
          final String queryLower = query.toLowerCase();

          // Prioritize user experiences over Google Maps results
          if (a['type'] == 'experience' && b['type'] == 'place') {
            return -1; // a comes first
          } else if (a['type'] == 'place' && b['type'] == 'experience') {
            return 1; // b comes first
          }

          // Simplified scoring from LocationPickerScreen (no businessNameHint)
          int getScore(String name, String currentQuery) {
            int score = 0;
            if (name == currentQuery) { // Exact match
              score += 5000;
            } else if (name.startsWith(currentQuery)) { // Starts with
              score += 2000;
            } else if (name.contains(currentQuery)) { // Contains
              score += 1000;
            } else if (currentQuery.contains(name) && name.length > 3){ // Query contains name
              score += 500;
            }
            return score;
          }

          int scoreA = getScore(nameA, queryLower);
          int scoreB = getScore(nameB, queryLower);

          if (scoreA != scoreB) {
            return scoreB.compareTo(scoreA); // Higher score first
          }
          if (nameA.length != nameB.length) {
            return nameB.length.compareTo(nameA.length); // Longer name first
          }

          final double? latA = a['latitude'];
          final double? lngA = a['longitude'];
          final double? latB = b['latitude'];
          final double? lngB = b['longitude'];

          if (mapCenter != null && latA != null && lngA != null && latB != null && lngB != null) {
            final distanceA = _calculateDistance(
                mapCenter.latitude, mapCenter.longitude, latA, lngA);
            final distanceB = _calculateDistance(
                mapCenter.latitude, mapCenter.longitude, latB, lngB);
            return distanceA.compareTo(distanceB);
          }
          return nameA.compareTo(nameB);
        });

        if (mounted) {
          setState(() {
            _searchResults = allResults;
            _showSearchResults = allResults.isNotEmpty;
            _isSearching = false;
            print("🗺️ MAP SCREEN: (_searchPlaces DEBOUNCED) setState: _showSearchResults: $_showSearchResults, _isSearching: $_isSearching, results count: ${_searchResults.length} (${experienceResults.length} experiences + ${mapsResults.length} places)");
          });
        }
      } catch (e) {
        print('🗺️ MAP SCREEN: Error searching places: $e');
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

  Future<void> _selectSearchResult(Map<String, dynamic> result) async {
    _debounce?.cancel(); 
    FocusScope.of(context).unfocus(); 

    _isProgrammaticTextUpdate = true; 
    print("🗺️ MAP SCREEN: (_selectSearchResult) Set _isProgrammaticTextUpdate = true");

    print("🗺️ MAP SCREEN: (_selectSearchResult) Removing search listener before setting text");
    _searchController.removeListener(_onSearchChanged);
    print("🗺️ MAP SCREEN: (_selectSearchResult) Listener removed.");

    // Check if this is a user's saved experience
    if (result['type'] == 'experience') {
      print("🗺️ MAP SCREEN: (_selectSearchResult) Selected result is a saved experience. Showing location details panel.");
      
      final Experience experience = result['experience'];
      final UserCategory category = result['category'];
      final LatLng targetLatLng = LatLng(experience.location.latitude, experience.location.longitude);

      // Animate camera to the experience location
      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(targetLatLng, 16.0),
        );
      } else {
        final GoogleMapController c = await _mapControllerCompleter.future;
        c.animateCamera(
          CameraUpdate.newLatLngZoom(targetLatLng, 16.0),
        );
      }

      // --- REGENERATING ICON FOR SELECTED STATE ---
      Color markerBackgroundColor = Colors.grey;
      try {
        if (experience.colorCategoryId != null) {
          final colorCategory = _colorCategories.firstWhere((cc) => cc.id == experience.colorCategoryId);
          markerBackgroundColor = _parseColor(colorCategory.colorHex);
        }
      } catch (e) { /* Use default grey color */ }

      final selectedIcon = await _bitmapDescriptorFromText(
        category.icon,
        backgroundColor: markerBackgroundColor,
        size: 88, // 125% of 70
        backgroundOpacity: 1.0, // Fully opaque
      );
      // --- END ICON REGENERATION ---

      // Create marker for the experience location
      final tappedMarkerId = MarkerId('selected_experience_location');
      final tappedMarker = Marker(
        markerId: tappedMarkerId,
        position: targetLatLng,
        infoWindow: InfoWindow(
          title: '${category.icon} ${experience.name}',
          snippet: experience.location.getPlaceName(),
        ),
        icon: selectedIcon, // Use the new enlarged icon
        zIndex: 1.0,
      );

      // Fetch business/open-now status for the experience location if possible
      String? businessStatus;
      bool? openNow;
      try {
        if (experience.location.placeId != null && experience.location.placeId!.isNotEmpty) {
          final detailsMap = await _mapsService.fetchPlaceDetailsData(experience.location.placeId!);
          businessStatus = detailsMap?['businessStatus'] as String?;
          openNow = (detailsMap?['currentOpeningHours']?['openNow']) as bool?;
        }
      } catch (e) {
        businessStatus = null;
        openNow = null;
      }

      // Set search text to experience name
      _searchController.text = experience.name;
      
      // Reset the flag immediately after the programmatic text update
      _isProgrammaticTextUpdate = false;
      print("🗺️ MAP SCREEN: (_selectSearchResult) Reset _isProgrammaticTextUpdate = false for experience.");

      if (mounted) {
        setState(() {
          _mapWidgetInitialLocation = experience.location;
          _tappedLocationDetails = experience.location;
          _tappedLocationMarker = tappedMarker;
          _tappedExperience = experience; // ADDED: Set associated experience
          _tappedExperienceCategory = category; // ADDED: Set associated category
          _tappedLocationBusinessStatus = businessStatus; // ADDED: Set business status
          _tappedLocationOpenNow = openNow; // ADDED: Set open-now status
          _isSearching = false;
          _showSearchResults = false;
        });
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchController.addListener(_onSearchChanged);
        }
      });
      return;
    }

    // Handle Google Maps places (original logic)
    final placeId = result['placeId']; 

    // Show loading indicator immediately for this specific operation
    if (mounted) {
      setState(() {
        _isSearching = true; 
      });
    }

    try {
      final location = await _mapsService.getPlaceDetails(placeId);
      final LatLng targetLatLng = LatLng(location.latitude, location.longitude);
      // Fetch business/open-now status for the selected place
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

      // Animate camera BEFORE setState that updates markers/details
      if (_mapController != null) {
        print("🗺️ MAP SCREEN: (_selectSearchResult) Animating BEFORE setState to $targetLatLng");
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(targetLatLng, 16.0),
        );
      } else {
        print("🗺️ MAP SCREEN: (_selectSearchResult) _mapController is NULL before animation. Animation might be delayed or rely on initial setup.");
        // If controller is null here, it's unexpected as map should be ready for user interaction.
        // Awaiting the completer here could introduce a delay if map isn't ready,
        // but it's a fallback.
        final GoogleMapController c = await _mapControllerCompleter.future;
         c.animateCamera(
          CameraUpdate.newLatLngZoom(targetLatLng, 16.0),
        );
      }

      final tappedMarkerId = MarkerId('selected_location');
      final tappedMarker = Marker(
        markerId: tappedMarkerId,
        position: targetLatLng, 
        infoWindow: InfoWindow(
          title: location.getPlaceName(),
          snippet: '${location.address ?? 'Unknown Address'}\nTap for Directions',
          onTap: () {
            if (_tappedLocationDetails != null) {
              _openDirectionsForLocation(_tappedLocationDetails!);
            }
          },
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        zIndex: 1.0,
      );

      print('🗺️ MAP SCREEN: (_selectSearchResult) Before setting text, location is: ${location.getPlaceName()}');
      _searchController.text = location.displayName ?? location.address ?? 'Selected Location';
      
      // Reset the flag immediately after the programmatic text update & before listener is re-added.
      _isProgrammaticTextUpdate = false;
      print("🗺️ MAP SCREEN: (_selectSearchResult) Reset _isProgrammaticTextUpdate = false (IMMEDIATELY after text set).");

      if (mounted) {
        print('🗺️ MAP SCREEN: (_selectSearchResult) Setting state with new location details and map initial location.');
        setState(() {
          _mapWidgetInitialLocation = location; // Update map widget's initial location
          _tappedLocationDetails = location;
          _tappedLocationMarker = tappedMarker;
          _tappedExperience = null; // ADDED: Clear associated experience for Google Maps places
          _tappedExperienceCategory = null; // ADDED: Clear associated category for Google Maps places
          _tappedLocationBusinessStatus = businessStatus; // ADDED: Set business status
          _tappedLocationOpenNow = openNow; // ADDED: Set open-now status
          _isSearching = false; 
          _showSearchResults = false; 
        });
        print('🗺️ MAP SCREEN: (_selectSearchResult) After setState, _tappedLocationDetails is: ${_tappedLocationDetails?.getPlaceName()} and _mapWidgetInitialLocation is: ${_mapWidgetInitialLocation?.getPlaceName()}');
      }

    } catch (e) {
      print('🗺️ MAP SCREEN: Error selecting search result: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting location: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false; // Ensure loading indicator is off
        });
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) { // Check mounted again inside callback
          print("🗺️ MAP SCREEN: (_selectSearchResult POST-FRAME) Re-adding search listener.");
          // The flag should already be false here.
          // print("🗺️ MAP SCREEN: (_selectSearchResult) State of _isProgrammaticTextUpdate in post-frame: $_isProgrammaticTextUpdate");

          _searchController.addListener(_onSearchChanged);
          print("🗺️ MAP SCREEN: (_selectSearchResult POST-FRAME) Search listener re-added.");
        } else {
          print("🗺️ MAP SCREEN: (_selectSearchResult POST-FRAME) NOT RUNNING because !mounted.");
        }
      });
    }
  }
  // --- END Search functionality ---

  // ADDED: Separate method for onChanged to easily add/remove listener
  void _onSearchChanged() {
    print("🗺️ MAP SCREEN: (_onSearchChanged) Text: '${_searchController.text}', _isProgrammaticTextUpdate: $_isProgrammaticTextUpdate");
    _searchPlaces(_searchController.text);
  }

  // ADDED: Helper to build a business/open-now status row similar to ExperiencePage
  Widget _buildBusinessStatusWidget() {
    // Prefer current open/closed status when available; fall back to businessStatus
    String? statusText;
    Color statusColor = Colors.grey;
    if (_tappedLocationBusinessStatus == 'CLOSED_PERMANENTLY') {
      statusText = 'Closed Permanently';
      statusColor = Colors.red;
    } else if (_tappedLocationBusinessStatus == 'CLOSED_TEMPORARILY') {
      statusText = 'Closed Temporarily';
      statusColor = Colors.red;
    } else if (_tappedLocationOpenNow != null) {
      if (_tappedLocationOpenNow == true) {
        statusText = 'Open now';
        statusColor = Colors.green;
      } else {
        statusText = 'Closed now';
        statusColor = Colors.red;
      }
    } else if (_tappedLocationBusinessStatus == 'OPERATIONAL') {
      // If we only know it's operational but not openNow, show neutral 'Operational'
      statusText = 'Operational';
      statusColor = Colors.grey;
    }
    if (statusText == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18.0, color: Colors.black54),
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
  }

  // ADDED: Helper to build the "Other Categories" display
  Widget _buildOtherCategoriesWidget() {
    if (_tappedExperience == null || _tappedExperience!.otherCategories.isEmpty) {
      return const SizedBox.shrink(); // Return empty space if no other categories
    }

    // Get the full UserCategory objects from the IDs
    final otherCategoryObjects = _tappedExperience!.otherCategories
        .map((id) {
          try {
            return _categories.firstWhere((cat) => cat.id == id);
          } catch (e) {
            return null; // Category not found
          }
        })
        .whereType<UserCategory>() // Filter out nulls
        .toList();

    if (otherCategoryObjects.isEmpty) {
      return const SizedBox.shrink();
    }

    // MODIFIED: Display as a Wrap of icons, without the header
    return Wrap(
      spacing: 8.0,
      runSpacing: 4.0,
      children: otherCategoryObjects.map((category) {
        return Text(
          category.icon,
          style: const TextStyle(fontSize: 16),
        );
      }).toList(),
    );
  }

  // ADDED: Helper to build the Color Category display
  Widget _buildColorCategoryWidget() {
    if (_tappedExperience == null || _tappedExperience!.colorCategoryId == null) {
      return const SizedBox.shrink();
    }

    ColorCategory? colorCategory;
    try {
      colorCategory = _colorCategories
          .firstWhere((cc) => cc.id == _tappedExperience!.colorCategoryId);
    } catch (e) {
      return const SizedBox.shrink(); // Not found
    }

    // MODIFIED: Removed the Column and header text
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: _parseColor(colorCategory.colorHex),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade400, width: 0.5),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            colorCategory.name,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    print("🗺️ MAP SCREEN: Building widget. isLoading: $_isLoading");

    // Calculate keyboard height and adjust layout accordingly
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bool isKeyboardVisible = keyboardHeight > 0;

    // Combine experience markers and the tapped marker (if it exists)
    final Map<String, Marker> allMarkers = Map.from(_markers);

    // If an experience is currently tapped, remove its original marker from the map
    // so it can be replaced by the styled _tappedLocationMarker.
    if (_tappedExperience != null) {
      allMarkers.remove(_tappedExperience!.id);
      print("🗺️ MAP SCREEN: Hiding original marker for '${_tappedExperience!.name}' to show selected marker.");
    }
    
    if (_tappedLocationMarker != null) {
      allMarkers[_tappedLocationMarker!.markerId.value] =
          _tappedLocationMarker!;
      print(
          "🗺️ MAP SCREEN: Adding selected location marker '${_tappedLocationMarker!.markerId.value}' to map.");
    } else {
      print("🗺️ MAP SCREEN: No selected location marker to add to map.");
    }
    print(
        "🗺️ MAP SCREEN: Total markers being sent to widget: ${allMarkers.length}");

    print("🗺️ MAP SCREEN: (build) _tappedLocationDetails is: ${_tappedLocationDetails?.getPlaceName()}");
    print("🗺️ MAP SCREEN: (build) Condition for BottomNav/Details Panel is: ${_tappedLocationDetails != null}");

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: const Text('Experiences Map'),
        actions: [
          Container(
            color: Colors.white,
            child: IconButton(
              icon: const Icon(Icons.filter_list),
              tooltip: 'Filter Experiences',
              onPressed: () {
                print("🗺️ MAP SCREEN: Filter button pressed!");
                setState(() {
                  _tappedLocationMarker = null;
                  _tappedLocationDetails = null;
                  _tappedExperience = null; // ADDED: Clear associated experience
                  _tappedExperienceCategory = null; // ADDED: Clear associated category
                  _tappedLocationBusinessStatus = null; // ADDED: Clear business status
                  _tappedLocationOpenNow = null; // ADDED: Clear open-now status
                  _searchController.clear();
                  _searchResults = [];
                  _showSearchResults = false;
                  _searchFocusNode.unfocus();
                });
                _showFilterDialog();
              },
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // --- Search bar ---
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
                      hintText: 'Search for a place or address',
                      border: InputBorder.none,
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.search, color: Theme.of(context).primaryColor),
                      suffixIcon: _isSearching // Show loading indicator in search bar
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.clear),
                                                      onPressed: () {
                      setState(() {
                        _searchController.clear();
                        _searchResults = [];
                        _showSearchResults = false;
                        // Clear tapped location when search is cleared
                        _tappedLocationDetails = null;
                        _tappedLocationMarker = null;
                        _tappedExperience = null;
                        _tappedExperienceCategory = null;
                        _tappedLocationBusinessStatus = null;
                        _tappedLocationOpenNow = null;
                      });
                    },
                                )
                              : null,
                    ),
                    onTap: () {
                      // When search bar is tapped, clear any existing map-tapped location
                      // to avoid confusion if the user then selects from search results.
                      // However, don't clear if a search result was *just* selected.
                      // This is now handled in _searchPlaces (clears on new query) and _selectSearchResult.
                    },
                  ),
                ),
              ),
            ),
            ),
            // --- END Search bar ---

            // --- ADDED: Search results (from LocationPickerScreen) ---
            if (_showSearchResults)
              Container(
                constraints: BoxConstraints(
                  // Adjust max height based on keyboard visibility
                  maxHeight: isKeyboardVisible
                      ? MediaQuery.of(context).size.height * 0.35 // More space when keyboard is up
                      : MediaQuery.of(context).size.height * 0.3, // Less space otherwise
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
                    final bool isUserExperience = result['type'] == 'experience';
                    final bool hasRating = result['rating'] != null;
                    final double rating =
                        hasRating ? (result['rating'] as double) : 0.0;
                    final String? address = result['address'] ??
                        (result['structured_formatting'] != null
                            ? result['structured_formatting']
                                ['secondary_text']
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
                              backgroundColor: isUserExperience 
                                  ? Colors.green.withOpacity(0.1) 
                                  : Theme.of(context).primaryColor.withOpacity(0.1),
                              child: isUserExperience
                                  ? Icon(
                                      Icons.bookmark,
                                      color: Colors.green,
                                      size: 18,
                                    )
                                  : Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        color: Theme.of(context).primaryColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                            ),
                            title: Row(
                              children: [
                                if (isUserExperience) ...[
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                                    ),
                                    child: Text(
                                      'Saved',
                                      style: TextStyle(
                                        color: Colors.green[700],
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Text(
                                    result['description'] ?? 'Unknown Place',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 15,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
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
                                            size: 14,
                                            color: Colors.grey[600]),
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
                                        if (result['userRatingCount'] !=
                                            null)
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
            // --- END Search results ---

            // --- MODIFIED: Map now takes remaining space ---
            Expanded(
              child: Stack(
                children: [
                  GoogleMapsWidget(
                    initialLocation: _mapWidgetInitialLocation, // Use the dynamic initial location
                    showUserLocation: true,
                    allowSelection: true,
                    onLocationSelected: _handleLocationSelected,
                    showControls: true,
                    additionalMarkers: allMarkers,
                    onMapControllerCreated: _onMapWidgetCreated,
                  ),
                  // Show a small, non-blocking loading spinner in the top-right during load
                  Positioned(
                    top: 12,
                    right: 12,
                    child: IgnorePointer(
                      ignoring: true,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: child,
                        ),
                        child: ((_isLoading || _isSharedLoading) && !_isSearching)
                            ? SizedBox(
                                key: const ValueKey('spinner'),
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(context).primaryColor,
                                ),
                              )
                            : const SizedBox(
                                key: ValueKey('empty'),
                                width: 0,
                                height: 0,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // --- ADDED: Tapped Location Details Panel (moved from bottomNavigationBar) ---
            if (_tappedLocationDetails != null && !isKeyboardVisible)
              // ADDED: Make entire panel tappable for experiences
              GestureDetector(
                onTap: _tappedExperience != null && _tappedExperienceCategory != null
                    ? () {
                        print("🗺️ MAP SCREEN: Experience location panel tapped. Navigating to experience page.");
                        _navigateToExperience(_tappedExperience!, _tappedExperienceCategory!);
                      }
                    : null,
                child: Container(
                  width: double.infinity, // ADDED: Make container fill screen width
                  padding: EdgeInsets.fromLTRB(
                      16, 16, 16, 8 + MediaQuery.of(context).padding.bottom / 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: Offset(0, -3), // Shadow upwards as it's at the bottom of content
                      ),
                    ],
                  ),
                  child: Stack(
                    clipBehavior: Clip.none, 
                    children: [
                      // ADDED: Positioned "Tap to view" text at the very top
                      if (_tappedExperience != null)
                        Positioned(
                          top: -12, // Move it further up, closer to the edge
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Text(
                              'Tap to view experience',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min, 
                        children: [
                          // ADDED: Add space at the top for the positioned text
                          if (_tappedExperience != null)
                            SizedBox(height: 12),
                          // Only show "Selected Location" for non-experience locations
                          if (_tappedExperience == null) ...[
                            Text(
                              'Selected Location',
                              style: TextStyle(
                                fontWeight: FontWeight.normal,
                                fontSize: 14,
                                color: Colors.grey[800],
                              ),
                            ),
                            SizedBox(height: 12),
                          ],
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  _tappedExperience != null
                                      ? '${_tappedExperienceCategory!.icon} ${_tappedExperience!.name}'
                                      : _tappedLocationDetails!.getPlaceName(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              // Add spacing to prevent title from overlapping with the action buttons in the Stack
                              const SizedBox(width: 96),
                            ],
                          ),
                          SizedBox(height: 8),
                          if (_tappedLocationDetails!.address != null &&
                              _tappedLocationDetails!.address!.isNotEmpty) ...[
                            Text(
                              _tappedLocationDetails!.address!,
                              style: TextStyle(color: Colors.grey[700]),
                            ),
                            SizedBox(height: 8),
                          ],
                          // ADDED: Star Rating
                          if (_tappedLocationDetails!.rating != null) ...[
                            Row(
                              children: [
                                ...List.generate(5, (i) {
                                  final ratingValue = _tappedLocationDetails!.rating!;
                                  return Icon(
                                    i < ratingValue.floor()
                                        ? Icons.star
                                        : (i < ratingValue)
                                            ? Icons.star_half
                                            : Icons.star_border,
                                    size: 18, 
                                    color: Colors.amber,
                                  );
                                }),
                                SizedBox(width: 8),
                                if (_tappedLocationDetails!.userRatingCount != null && _tappedLocationDetails!.userRatingCount! > 0)
                                  Text(
                                    '(${_tappedLocationDetails!.userRatingCount})',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 13,
                                    ),
                                  ),
                              ],
                            ),
                            SizedBox(height: 8), // Added SizedBox after rating like in location_picker_screen
                          ],

                          // ADDED: Business Status row below star rating
                          _buildBusinessStatusWidget(),

                          const SizedBox(height: 12), // Spacer before the new row

                          // ADDED: Row for Other Categories and Color Category
                          if (_tappedExperience != null)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _buildOtherCategoriesWidget()),
                                const SizedBox(width: 8),
                                _buildColorCategoryWidget(),
                              ],
                            ),
                        ],
                      ),
                    Positioned(
                      top: -8,
                      right: -8,
                      child: Row(
                        mainAxisSize: MainAxisSize.min, 
                        children: [
                          IconButton(
                            onPressed: () {
                              if (_tappedLocationDetails != null) {
                                _launchMapLocation(_tappedLocationDetails!);
                              }
                            },
                            icon: Icon(Icons.map_outlined, color: Colors.green[700], size: 28),
                            tooltip: 'Open in map app',
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: () {
                              if (_tappedLocationDetails != null) {
                                _openDirectionsForLocation(_tappedLocationDetails!);
                              }
                            },
                            icon: Icon(Icons.directions, color: Colors.blue, size: 28),
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
              ),
            // --- END Tapped Location Details ---
          ],
        ),
      ),
    );
  }
}
