import 'dart:async'; // Import async
import 'dart:math' as Math; // Import for mathematical functions
// Import for ByteData
import 'dart:ui' as ui; // Import for ui.Image, ui.Canvas etc.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'; // Add Google Maps import
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart'; // ADDED: Import url_launcher
import 'package:cloud_firestore/cloud_firestore.dart'; // ADDED: For pagination cursors
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../services/sharing_service.dart'; // RESTORED: Fallback path
import '../models/enums/share_enums.dart'; // RESTORED: Fallback path
import '../widgets/google_maps_widget.dart';
import '../services/experience_service.dart'; // Import ExperienceService
import '../services/auth_service.dart'; // Import AuthService
import '../services/user_service.dart';
import '../services/google_maps_service.dart'; // Import GoogleMapsService
import '../models/shared_media_item.dart';
import '../widgets/shared_media_preview_modal.dart';
import '../models/experience.dart'; // Import Experience model (includes Location)
import '../models/user_category.dart'; // Import UserCategory model
import '../models/color_category.dart'; // Import ColorCategory model
import '../models/user_profile.dart';
import 'experience_page_screen.dart'; // Import ExperiencePageScreen for navigation
import '../models/public_experience.dart';
import '../config/app_constants.dart';
import '../config/colors.dart';
import '../models/event.dart';
import '../services/event_service.dart';
import '../services/experience_share_service.dart';
import '../widgets/event_editor_modal.dart';
import '../widgets/share_experience_bottom_sheet.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:plendy/utils/haptic_feedback.dart';

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

// Helper class to represent either a date header or an event
class _EventListItem {
  final DateTime? date;
  final Event? event;
  final bool isHeader;

  _EventListItem.header(this.date)
      : event = null,
        isHeader = true;
  _EventListItem.event(this.event)
      : date = null,
        isHeader = false;
}

class MapScreen extends StatefulWidget {
  final Location?
      initialExperienceLocation; // ADDED: To receive a specific location
  final PublicExperience?
      initialPublicExperience; // ADDED: Optional public experience context
  final Event?
      initialEvent; // ADDED: Optional initial event for event view mode

  const MapScreen(
      {super.key,
      this.initialExperienceLocation,
      this.initialPublicExperience,
      this.initialEvent}); // UPDATED: Constructor

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final ExperienceService _experienceService = ExperienceService();
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
  final SharingService _sharingService = SharingService();
  final EventService _eventService = EventService();
  final GoogleMapsService _mapsService =
      GoogleMapsService(); // ADDED: Maps Service
  final Map<String, Marker> _markers = {}; // Use String keys for marker IDs
  bool _isLoading = true;

  // Animation controller for smooth marker animations
  AnimationController? _markerAnimationController;
  List<Experience> _experiences = [];
  List<UserCategory> _categories = [];
  List<ColorCategory> _colorCategories = [];
  List<UserProfile> _followingUsers = [];
  // ADDED: Cache of owner display names for shared categories
  final Map<String, String> _ownerNameByUserId = {};
  final Completer<GoogleMapController> _mapControllerCompleter =
      Completer<GoogleMapController>();
  // ADDED: Cache for generated category icons
  final Map<String, BitmapDescriptor> _categoryIconCache = {};
  // ADDED: Cache for experience media previews
  final Map<String, List<SharedMediaItem>> _experienceMediaCache = {};
  final Set<String> _mediaPrefetchInFlight = {};

  // ADDED: State for selected filters
  Set<String> _selectedCategoryIds = {}; // Empty set means no filter
  Set<String> _selectedColorCategoryIds = {}; // Empty set means no filter
  Set<String> _selectedFolloweeIds = {};
  Set<String> _followingUserIds = {};
  Map<String, List<String>> _followeeCategoryIcons = {};
  Map<String, List<Experience>> _followeePublicExperiences = {};
  Map<String, Map<String, UserCategory>> _followeeCategories = {};
  Map<String, Map<String, ColorCategory>> _followeeColorCategories = {};
  final Map<String, Set<String>> _followeeCategorySelections = {};
  final Map<String, Set<String>> _followeeColorSelections = {};
  final Set<String> _sharedCategoryPermissionKeys = {};
  final Set<String> _sharedExperiencePermissionKeys = {};
  bool _sharedPermissionsLoaded = false;
  bool get _hasActiveFilters =>
      _selectedCategoryIds.isNotEmpty ||
      _selectedColorCategoryIds.isNotEmpty ||
      _selectedFolloweeIds.isNotEmpty;

  // ADDED: State for tapped location
  Marker? _tappedLocationMarker;
  Location? _tappedLocationDetails;
  Experience? _tappedExperience; // ADDED: Track associated experience
  UserCategory? _tappedExperienceCategory; // ADDED: Track associated category
  String?
      _tappedLocationBusinessStatus; // ADDED: Track business status for tapped location
  bool? _tappedLocationOpenNow; // ADDED: Track open-now status
  Experience?
      _publicReadOnlyExperience; // ADDED: Cached public experience for discovery launches
  String? _publicReadOnlyExperienceId; // Tracks tapped public experience ID
  Experience?
      _publicExperienceDraft; // ADDED: Precomputed draft from initial public experience
  String? _publicExperienceDraftId; // ID for the precomputed draft
  List<SharedMediaItem>?
      _publicPreviewMediaItems; // ADDED: Public media previews for read-only experience page
  static const UserCategory _publicReadOnlyCategory = UserCategory(
    id: 'public_readonly_category',
    name: 'Discovery',
    icon: '*',
    ownerUserId: 'public',
  );

  bool get _canOpenSelectedExperience =>
      _tappedExperience != null || _publicReadOnlyExperience != null;

  // ADDED: State for search functionality
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Map<String, dynamic>> _searchResults = [];
  bool _showSearchResults = false;
  bool _isSearching = false;
  bool _isReturningFromNavigation = false; // Track navigation return to disable search
  Timer? _debounce;
  GoogleMapController?
      _mapController; // To be initialized from _mapControllerCompleter
  bool _isProgrammaticTextUpdate = false; // RE-ADDED
  Location?
      _mapWidgetInitialLocation; // ADDED: To control GoogleMapsWidget initial location
  // ADDED: Indicates background loading of shared experiences
  bool _isSharedLoading = false;
  // ADDED: Paging state for shared experiences
  DocumentSnapshot<Object?>? _sharedLastDoc;
  bool _sharedHasMore = true;
  bool _sharedIsFetching = false;
  static const int _sharedPageSize = 200;
  bool _isGlobalToggleActive = false; // ADDED: Track globe toggle state
  bool _isCalendarDialogLoading = false;
  // ADDED: Fallback paging state when query path fails
  List<String>? _fallbackSharedIds;
  int _fallbackPageOffset = 0;
  // ADDED: State for public experiences (globe toggle)
  List<PublicExperience> _nearbyPublicExperiences = [];
  final Map<String, Marker> _publicExperienceMarkers = {};
  bool _isGlobeLoading = false;
  LatLng? _lastGlobeMapCenter;
  final Map<String, Experience> _eventExperiencesCache = {};
  int _markerAnimationToken = 0;

  // ADDED: Event view mode state
  Event? _activeEventViewMode;
  final Map<String, Marker> _eventViewMarkers = {};
  final Map<String, Experience?> _eventViewMarkerExperiences =
      {}; // Store experience for each marker
  final Map<String, EventExperienceEntry> _eventViewMarkerEntries =
      {}; // Store entry for each marker
  bool get _isEventViewModeActive => _activeEventViewMode != null;
  bool _isEventOverlayExpanded = false; // Track expanded state of event overlay
  List<UserCategory> _plannerCategories =
      []; // Planner's categories for shared events
  List<ColorCategory> _plannerColorCategories =
      []; // Planner's color categories for shared events

  // ADDED: Select mode state (for creating new events by selecting experiences on map)
  bool _isSelectModeActive = false;
  Color _selectModeColor = Colors.blue; // Random color for the new event
  List<EventExperienceEntry> _selectModeDraftItinerary = [];
  bool _isSelectModeOverlayExpanded = false;
  final Map<String, Marker> _selectModeEventOnlyMarkers =
      {}; // Markers for event-only entries

  // ADDED: State for adding experiences to existing event
  bool _isAddToEventModeActive = false;
  List<EventExperienceEntry> _addToEventDraftItinerary = [];

  // Event color palette (same as used in _getEventColor)
  static const List<Color> _eventColorPalette = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
  ];

  // ADDED: Resolve and cache display name for owners of shared items
  Future<String> _getOwnerDisplayName(String userId) async {
    if (_ownerNameByUserId.containsKey(userId)) {
      return _ownerNameByUserId[userId]!;
    }
    try {
      final profile = await _experienceService.getUserProfileById(userId);
      final name = profile?.displayName ?? profile?.username ?? 'Someone';
      _ownerNameByUserId[userId] = name;
      return name;
    } catch (_) {
      _ownerNameByUserId[userId] = 'Someone';
      return 'Someone';
    }
  }

  int _markerStartSize(int finalSize) {
    return Math.max(1, (finalSize * 0.55).round());
  }

  Marker _buildSelectedMarker({
    required MarkerId markerId,
    required LatLng position,
    required String infoWindowTitle,
    required BitmapDescriptor icon,
  }) {
    return Marker(
      markerId: markerId,
      position: position,
      infoWindow: _infoWindowForPlatform(infoWindowTitle),
      icon: icon,
      zIndex: 1.0,
    );
  }

  /// Animates the selected marker using vsync-aligned frames for smooth performance.
  /// Uses keyframe-based animation with reduced intermediate frames to minimize
  /// icon generation overhead while maintaining visual smoothness.
  Future<void> _animateSelectedMarkerSmooth({
    required int animationToken,
    required MarkerId markerId,
    required LatLng position,
    required String infoWindowTitle,
    required Future<BitmapDescriptor> Function(int size) iconBuilder,
    required int startSize,
    required int endSize,
    Duration duration = const Duration(milliseconds: 260),
  }) async {
    // Cancel any existing animation
    _markerAnimationController?.dispose();

    // Create a new animation controller with vsync for smooth 60fps animation
    final controller = AnimationController(
      vsync: this,
      duration: duration,
    );
    _markerAnimationController = controller;

    // Use easeOutCubic for natural deceleration
    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    );

    int lastSize = startSize;

    // Use a listener that's called on each vsync frame
    void onAnimationUpdate() {
      if (!mounted || animationToken != _markerAnimationToken) {
        controller.dispose();
        return;
      }

      final int size =
          (startSize + (endSize - startSize) * animation.value).round();

      // Only update if size actually changed (reduces unnecessary work)
      if (size != lastSize) {
        lastSize = size;
        // Build icon asynchronously and update marker
        iconBuilder(size).then((icon) {
          if (!mounted || animationToken != _markerAnimationToken) return;
          setState(() {
            _tappedLocationMarker = _buildSelectedMarker(
              markerId: markerId,
              position: position,
              infoWindowTitle: infoWindowTitle,
              icon: icon,
            );
          });
        });
      }
    }

    animation.addListener(onAnimationUpdate);

    // Start the animation
    await controller.forward();

    // Clean up
    animation.removeListener(onAnimationUpdate);
    if (_markerAnimationController == controller) {
      _markerAnimationController = null;
    }
    controller.dispose();
  }

  Future<void> _refreshBusinessStatus(
      String? placeId, int animationToken) async {
    if (placeId == null || placeId.isEmpty) {
      return;
    }
    try {
      final detailsMap = await _mapsService.fetchPlaceDetailsData(placeId);
      final String? businessStatus = detailsMap?['businessStatus'] as String?;
      final bool? openNow =
          (detailsMap?['currentOpeningHours']?['openNow']) as bool?;
      if (!mounted || animationToken != _markerAnimationToken) {
        return;
      }
      setState(() {
        _tappedLocationBusinessStatus = businessStatus;
        _tappedLocationOpenNow = openNow;
      });
    } catch (_) {
      if (!mounted || animationToken != _markerAnimationToken) {
        return;
      }
      setState(() {
        _tappedLocationBusinessStatus = null;
        _tappedLocationOpenNow = null;
      });
    }
  }

  @override
  void initState() {
    super.initState();

    if (widget.initialPublicExperience != null) {
      _publicExperienceDraft =
          widget.initialPublicExperience!.toExperienceDraft();
      _publicExperienceDraftId = widget.initialPublicExperience!.id;
      _publicPreviewMediaItems =
          widget.initialPublicExperience!.buildMediaItemsForPreview();
    }

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
          unawaited(_selectLocationOnMap(
            widget.initialExperienceLocation!,
            animateCamera: false,
            updateLoadingState: false,
            markerId: 'initial_selected_location',
          ).catchError((e, __) {
            print("🗺️ MAP SCREEN: Failed to preselect initial location: $e");
          }));
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

    _initializeFiltersAndData(); // Load saved filters and experiences
    _searchController.addListener(_onSearchChanged);

    // Handle initial event if provided
    if (widget.initialEvent != null) {
      // Wait a bit for initial data to load, then handle the event
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _handleInitialEvent(widget.initialEvent!);
        }
      });
    }
  }

  Future<void> _handleInitialEvent(Event event) async {
    // Wait for map controller to be ready first
    final controller = await _mapControllerCompleter.future;
    if (!mounted) return;
    _mapController = controller;

    // Ensure experiences are loaded (this may already be in progress from _initializeFiltersAndData)
    // Calling it again is safe - it will reload if needed
    await _loadDataAndGenerateMarkers();

    if (!mounted) return;

    // Cache experiences for this event
    await _cacheEventExperiencesForEvents([event]);

    if (!mounted) return;

    // Enter event view mode
    await _enterEventViewMode(event);

    // If initialExperienceLocation is provided, focus on the matching marker
    if (widget.initialExperienceLocation != null) {
      await _focusOnInitialLocationInEventView(
          event, widget.initialExperienceLocation!);
    }
  }

  // ADDED: Focus on a specific location in event view mode
  Future<void> _focusOnInitialLocationInEventView(
      Event event, Location targetLocation) async {
    if (!mounted || _mapController == null) return;

    // Find the matching entry/experience in the event
    for (int i = 0; i < event.experiences.length; i++) {
      final entry = event.experiences[i];
      Location? entryLocation;

      if (entry.isEventOnly) {
        entryLocation = entry.inlineLocation;
      } else if (entry.experienceId.isNotEmpty) {
        final experience = _eventExperiencesCache[entry.experienceId];
        if (experience != null) {
          entryLocation = experience.location;
        }
      }

      // Check if this location matches the target location (within small tolerance)
      if (entryLocation != null &&
          (entryLocation.latitude - targetLocation.latitude).abs() < 0.0001 &&
          (entryLocation.longitude - targetLocation.longitude).abs() < 0.0001) {
        // Found matching entry - focus on it
        Experience? experience;
        if (!entry.isEventOnly && entry.experienceId.isNotEmpty) {
          experience = _eventExperiencesCache[entry.experienceId];
        }
        await _focusEventItineraryItem(entry, experience, i);
        return;
      }
    }

    // If no exact match found, just focus on the location
    final position = LatLng(targetLocation.latitude, targetLocation.longitude);
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: position, zoom: 16.0),
      ),
    );
  }

  @override
  void dispose() {
    _searchController
        .removeListener(_onSearchChanged); // ADDED: Remove listener here
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    _markerAnimationController?.dispose();
    _markerAnimationController = null;
    super.dispose();
  }

  void _initializeFiltersAndData() {
    unawaited(() async {
      await _loadSavedMapFilters();
      if (mounted) {
        await _loadDataAndGenerateMarkers();
      }
    }());
  }

  Future<void> _loadSavedMapFilters() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCategoryIds =
          prefs.getStringList(AppConstants.mapFilterCategoryIdsKey);
      final savedColorIds =
          prefs.getStringList(AppConstants.mapFilterColorIdsKey);
      final savedFolloweeIds =
          prefs.getStringList(AppConstants.mapFilterFolloweeIdsKey);
      if (!mounted) return;
      if (savedCategoryIds != null ||
          savedColorIds != null ||
          savedFolloweeIds != null) {
        setState(() {
          _selectedCategoryIds = savedCategoryIds?.toSet() ?? {};
          _selectedColorCategoryIds = savedColorIds?.toSet() ?? {};
          _selectedFolloweeIds = savedFolloweeIds?.toSet() ?? {};
        });
      }
    } catch (e) {
      print("🗺️ MAP SCREEN: Failed to load saved filter selections: $e");
    }
  }

  Future<void> _loadSharePermissions(String userId,
      {bool forceRefresh = false}) async {
    if (_sharedPermissionsLoaded && !forceRefresh) {
      return;
    }
    try {
      final permissions = await _sharingService.getSharedItemsForUser(userId);
      final Set<String> categoryKeys = permissions
          .where((perm) => perm.itemType == ShareableItemType.category)
          .map((perm) => _sharePermissionKey(perm.ownerUserId, perm.itemId))
          .toSet();
      final Set<String> experienceKeys = permissions
          .where((perm) => perm.itemType == ShareableItemType.experience)
          .map((perm) => _sharePermissionKey(perm.ownerUserId, perm.itemId))
          .toSet();
      if (mounted) {
        setState(() {
          _sharedCategoryPermissionKeys
            ..clear()
            ..addAll(categoryKeys);
          _sharedExperiencePermissionKeys
            ..clear()
            ..addAll(experienceKeys);
        });
        _rebuildFolloweeCategoryIcons();
      }
      _sharedPermissionsLoaded = true;
    } catch (e) {
      print("🗺️ MAP SCREEN: Failed to load share permissions for $userId: $e");
    }
  }

  Future<void> _loadFollowingUsers(String userId) async {
    try {
      final List<String> followingIds =
          await _userService.getFollowingIds(userId);
      if (!mounted) {
        return;
      }

      if (followingIds.isEmpty) {
        setState(() {
          _followingUsers = [];
          _followingUserIds = {};
          _selectedFolloweeIds.clear();
          _followeeCategoryIcons = {};
          _followeeCategories = {};
          _followeeColorCategories = {};
          _followeePublicExperiences = {};
        });
        return;
      }

      final List<UserProfile> loadedProfiles = await Future.wait(
        followingIds.map((id) async {
          try {
            final profile = await _userService.getUserProfile(id);
            return profile ?? UserProfile(id: id);
          } catch (e) {
            print(
                "🗺️ MAP SCREEN: Failed to load profile for followee $id: $e");
            return UserProfile(id: id);
          }
        }),
      );

      loadedProfiles.sort(_compareProfilesByName);
      final Set<String> resolvedIds =
          loadedProfiles.map((profile) => profile.id).toSet();

      if (!mounted) {
        return;
      }
      setState(() {
        _followingUsers = loadedProfiles;
        _followingUserIds = resolvedIds;
        _selectedFolloweeIds
            .removeWhere((id) => !_followingUserIds.contains(id));
        if (_followingUserIds.isEmpty) {
          _followeePublicExperiences = {};
          _followeeCategories = {};
          _followeeColorCategories = {};
        }
      });
      await _fetchFolloweePublicExperiences(_followingUserIds);
    } catch (e) {
      print("🗺️ MAP SCREEN: Failed to load following users: $e");
    }
  }

  Future<void> _fetchFolloweePublicExperiences(Set<String> followeeIds) async {
    if (!mounted) {
      return;
    }
    if (followeeIds.isEmpty) {
      setState(() {
        _followeePublicExperiences = {};
        _followeeCategories = {};
        _followeeColorCategories = {};
      });
      _rebuildFolloweeCategoryIcons();
      return;
    }

    final List<Future<MapEntry<String, List<Experience>>>> tasks =
        followeeIds.map((followeeId) async {
      try {
        // Use forceRefresh: true to bypass in-flight deduplication since we're
        // fetching for different users in parallel. The shared in-flight tracking
        // in ExperienceService would otherwise cause all followees to get the
        // same experiences from the first request.
        final experiences = await _experienceService.getExperiencesByUser(
            followeeId,
            limit: 0,
            forceRefresh: true); // No limit - load all followee experiences
        final List<Experience> publicExperiences = experiences
            .where((exp) => _canViewFolloweeExperience(exp))
            .toList();
        return MapEntry(followeeId, publicExperiences);
      } catch (e) {
        print(
            "🗺️ MAP SCREEN: Failed to load experiences for followee $followeeId: $e");
        return MapEntry(followeeId, <Experience>[]);
      }
    }).toList();

    try {
      final results = await Future.wait(tasks);
      if (!mounted) {
        return;
      }
      final Map<String, List<Experience>> newFolloweeExperiences = {};
      final Map<String, Map<String, UserCategory>> newFolloweeCategories = {};
      final Map<String, Map<String, ColorCategory>> newFolloweeColorCategories =
          {};
      for (final entry in results) {
        final String followeeId = entry.key;
        final List<Experience> experiences = entry.value;
        newFolloweeExperiences[followeeId] = experiences;

        final Map<String, UserCategory> ownerCategories =
            Map<String, UserCategory>.from(
                _followeeCategories[followeeId] ?? {});
        final Map<String, ColorCategory> ownerColors =
            Map<String, ColorCategory>.from(
                _followeeColorCategories[followeeId] ?? {});
        final Set<String> missingCategoryIds = {};
        final Set<String> missingColorIds = {};
        for (final experience in experiences) {
          final String? categoryId = experience.categoryId;
          if (categoryId == null ||
              categoryId.isEmpty ||
              ownerCategories.containsKey(categoryId)) {
            continue;
          }
          missingCategoryIds.add(categoryId);
        }
        for (final otherId
            in experiences.expand((exp) => exp.otherCategories)) {
          if (otherId.isEmpty || ownerCategories.containsKey(otherId)) {
            continue;
          }
          missingCategoryIds.add(otherId);
        }
        for (final experience in experiences) {
          final String? colorId = experience.colorCategoryId;
          if (colorId == null ||
              colorId.isEmpty ||
              ownerColors.containsKey(colorId)) {
            continue;
          }
          missingColorIds.add(colorId);
        }
        for (final otherColorId
            in experiences.expand((exp) => exp.otherColorCategoryIds)) {
          if (otherColorId.isEmpty || ownerColors.containsKey(otherColorId)) {
            continue;
          }
          missingColorIds.add(otherColorId);
        }
        if (missingCategoryIds.isNotEmpty) {
          try {
            final fetchedCategories =
                await _experienceService.getUserCategoriesByOwnerAndIds(
                    followeeId, missingCategoryIds.toList());
            for (final category in fetchedCategories) {
              ownerCategories[category.id] = category;
            }
          } catch (e) {
            print(
                "🗺️ MAP SCREEN: Failed to fetch category metadata for followee $followeeId: $e");
          }
        }
        if (missingColorIds.isNotEmpty) {
          try {
            final fetchedColors =
                await _experienceService.getColorCategoriesByOwnerAndIds(
                    followeeId, missingColorIds.toList());
            for (final color in fetchedColors) {
              ownerColors[color.id] = color;
            }
          } catch (e) {
            print(
                "🗺️ MAP SCREEN: Failed to fetch color metadata for followee $followeeId: $e");
          }
        }
        newFolloweeCategories[followeeId] = ownerCategories;
        newFolloweeColorCategories[followeeId] = ownerColors;
      }
      setState(() {
        _followeePublicExperiences = newFolloweeExperiences;
        _followeeCategories = newFolloweeCategories;
        _followeeColorCategories = newFolloweeColorCategories;
      });
      _rebuildFolloweeCategoryIcons();
      if (_selectedFolloweeIds.isNotEmpty) {
        unawaited(_applyFiltersAndUpdateMarkers());
      }
    } catch (e) {
      print("🗺️ MAP SCREEN: Error fetching followee experiences: $e");
    }
  }

  void _rebuildFolloweeCategoryIcons() {
    if (!mounted) {
      return;
    }
    final bool hasAnyExperiences = _experiences.isNotEmpty ||
        _followeePublicExperiences.values
            .any((experiences) => experiences.isNotEmpty);
    if (_followingUserIds.isEmpty || !hasAnyExperiences) {
      setState(() {
        _followeeCategoryIcons = {};
      });
      return;
    }

    final Map<String, Set<String>> iconsByUser = {};

    void addIconsFromExperience(Experience experience) {
      final String? ownerId = experience.createdBy;
      if (ownerId == null ||
          ownerId.isEmpty ||
          !_followingUserIds.contains(ownerId) ||
          _isExperienceEffectivelyPrivate(experience)) {
        return;
      }
      final String? icon = _getCategoryIconForExperience(experience);
      if (icon == null || icon.isEmpty || icon == '❓') {
        return;
      }
      iconsByUser.putIfAbsent(ownerId, () => <String>{}).add(icon);
    }

    for (final experience in _experiences) {
      addIconsFromExperience(experience);
    }
    _followeePublicExperiences.forEach((_, experiences) {
      for (final experience in experiences) {
        addIconsFromExperience(experience);
      }
    });

    final Map<String, List<String>> normalized = {};
    iconsByUser.forEach((userId, icons) {
      final List<String> sortedIcons = icons.toList()..sort();
      normalized[userId] = List<String>.unmodifiable(sortedIcons);
    });

    setState(() {
      _followeeCategoryIcons = normalized;
    });
  }

  String? _getCategoryIconForExperienceFromCategories(
      Experience experience, List<UserCategory> categoriesToUse) {
    final String? categoryId = experience.categoryId;

    // First try the denormalized icon
    if (experience.categoryIconDenorm != null &&
        experience.categoryIconDenorm!.isNotEmpty) {
      return experience.categoryIconDenorm;
    }

    // Then try to find the category in the provided categories list
    if (categoryId != null && categoryId.isNotEmpty) {
      try {
        final UserCategory category =
            categoriesToUse.firstWhere((cat) => cat.id == categoryId);
        return category.icon;
      } catch (_) {
        // Category not found in provided list
      }
    }

    return null;
  }

  String? _getCategoryIconForExperience(Experience experience) {
    final String? ownerId = experience.createdBy;
    final String? currentUserId = _authService.currentUser?.uid;
    final String? categoryId = experience.categoryId;
    final bool isFolloweeExperience =
        ownerId != null && ownerId.isNotEmpty && ownerId != currentUserId;

    final UserCategory? accessibleCategory =
        _getAccessibleUserCategory(ownerId, categoryId);
    if (accessibleCategory != null && accessibleCategory.icon.isNotEmpty) {
      return accessibleCategory.icon;
    }

    if (isFolloweeExperience && categoryId != null) {
      final bool hasAccess = _canAccessFolloweeCategory(ownerId, categoryId);
      if (!hasAccess) {
        return null;
      }
    }

    if (experience.categoryIconDenorm != null &&
        experience.categoryIconDenorm!.isNotEmpty) {
      return experience.categoryIconDenorm;
    }

    if (categoryId == null || categoryId.isEmpty) {
      return null;
    }
    try {
      final UserCategory category =
          _categories.firstWhere((cat) => cat.id == categoryId);
      return category.icon;
    } catch (_) {
      if (ownerId != null &&
          ownerId.isNotEmpty &&
          _followeeCategories.containsKey(ownerId)) {
        final UserCategory? followeeCategory =
            _followeeCategories[ownerId]?[categoryId];
        if (followeeCategory != null && followeeCategory.icon.isNotEmpty) {
          return followeeCategory.icon;
        }
      }
      return null;
    }
  }

  int _compareProfilesByName(UserProfile a, UserProfile b) {
    final String aValue = _normalizeUserSortValue(a);
    final String bValue = _normalizeUserSortValue(b);
    return aValue.compareTo(bValue);
  }

  String _normalizeUserSortValue(UserProfile profile) {
    if (profile.displayName != null && profile.displayName!.trim().isNotEmpty) {
      return profile.displayName!.trim().toLowerCase();
    }
    if (profile.username != null && profile.username!.trim().isNotEmpty) {
      return profile.username!.trim().toLowerCase();
    }
    return profile.id.toLowerCase();
  }

  String _getUserDisplayName(UserProfile profile) {
    if (profile.displayName != null && profile.displayName!.trim().isNotEmpty) {
      return profile.displayName!.trim();
    }
    if (profile.username != null && profile.username!.trim().isNotEmpty) {
      return profile.username!.trim();
    }
    return 'Friend';
  }

  UserCategory? _getAccessibleUserCategory(
      String? ownerId, String? categoryId) {
    if (categoryId == null || categoryId.isEmpty) {
      return null;
    }
    final String? currentUserId = _authService.currentUser?.uid;
    if (ownerId == null || ownerId.isEmpty || ownerId == currentUserId) {
      try {
        return _categories.firstWhere((cat) => cat.id == categoryId);
      } catch (_) {
        return null;
      }
    }
    return _followeeCategories[ownerId]?[categoryId];
  }

  ColorCategory? _getAccessibleColorCategory(
      String? ownerId, String? colorCategoryId) {
    if (colorCategoryId == null || colorCategoryId.isEmpty) {
      return null;
    }
    final String? currentUserId = _authService.currentUser?.uid;
    if (ownerId == null || ownerId.isEmpty || ownerId == currentUserId) {
      try {
        return _colorCategories.firstWhere((cc) => cc.id == colorCategoryId);
      } catch (_) {
        return null;
      }
    }
    return _followeeColorCategories[ownerId]?[colorCategoryId];
  }

  Set<String> _getFolloweeAccessibleCategoryIds(String? ownerId) {
    if (ownerId == null || ownerId.isEmpty) {
      return const <String>{};
    }
    final String? currentUserId = _authService.currentUser?.uid;
    if (ownerId == currentUserId) {
      return _categories.map((c) => c.id).toSet();
    }
    final Iterable<UserCategory> categories =
        _followeeCategories[ownerId]?.values ??
            const Iterable<UserCategory>.empty();
    return categories
        .where((category) => _canAccessFolloweeCategory(ownerId, category.id))
        .map((category) => category.id)
        .toSet();
  }

  Set<String> _getFolloweeAccessibleColorCategoryIds(String? ownerId) {
    if (ownerId == null || ownerId.isEmpty) {
      return const <String>{};
    }
    final String? currentUserId = _authService.currentUser?.uid;
    if (ownerId == currentUserId) {
      return _colorCategories.map((c) => c.id).toSet();
    }
    final Iterable<ColorCategory> colors =
        _followeeColorCategories[ownerId]?.values ??
            const Iterable<ColorCategory>.empty();
    return colors
        .where((color) => _canAccessFolloweeColorCategory(ownerId, color.id))
        .map((color) => color.id)
        .toSet();
  }

  bool _hasSelectedCategoriesForFollowee(String ownerId) {
    return _followeeCategorySelections[ownerId]?.isNotEmpty ?? false;
  }

  bool _hasSelectedColorCategoriesForFollowee(String ownerId) {
    return _followeeColorSelections[ownerId]?.isNotEmpty ?? false;
  }

  List<UserCategory> _collectAccessibleCategoriesForExperience(
      Experience experience) {
    if (!_canDisplayFolloweeMetadata(experience)) {
      return const <UserCategory>[];
    }
    final String? ownerId = experience.createdBy;
    final Map<String, UserCategory> collected = {};

    void addCategory(String? categoryId) {
      final UserCategory? category =
          _getAccessibleUserCategory(ownerId, categoryId);
      if (category != null && category.id.isNotEmpty) {
        collected[category.id] = category;
      }
    }

    addCategory(experience.categoryId);
    for (final otherId in experience.otherCategories) {
      addCategory(otherId);
    }
    return collected.values.toList();
  }

  List<ColorCategory> _collectAccessibleColorCategoriesForExperience(
      Experience experience) {
    if (!_canDisplayFolloweeMetadata(experience)) {
      return const <ColorCategory>[];
    }
    final String? ownerId = experience.createdBy;
    final Map<String, ColorCategory> collected = {};

    void addColor(String? colorId) {
      final ColorCategory? color =
          _getAccessibleColorCategory(ownerId, colorId);
      if (color != null && color.id.isNotEmpty) {
        collected[color.id] = color;
      }
    }

    addColor(experience.colorCategoryId);
    for (final otherId in experience.otherColorCategoryIds) {
      addColor(otherId);
    }
    return collected.values.toList();
  }

  List<ColorCategory> _buildColorCategoryListForExperience(
      Experience experience) {
    if (!_canDisplayFolloweeMetadata(experience)) {
      return _colorCategories;
    }
    final Map<String, ColorCategory> merged = {
      for (final color in _colorCategories) color.id: color,
    };
    for (final color
        in _collectAccessibleColorCategoriesForExperience(experience)) {
      merged[color.id] = color;
    }
    return merged.values.toList();
  }

  String _sharePermissionKey(String ownerId, String itemId) =>
      '$ownerId|$itemId';

  bool _hasCategorySharePermission(String ownerId, String itemId) {
    return _sharedCategoryPermissionKeys
        .contains(_sharePermissionKey(ownerId, itemId));
  }

  bool _hasExperienceSharePermission(String ownerId, String itemId) {
    return _sharedExperiencePermissionKeys
        .contains(_sharePermissionKey(ownerId, itemId));
  }

  bool _canViewFolloweeExperience(Experience experience) {
    final String? ownerId = experience.createdBy;
    final String? currentUserId = _authService.currentUser?.uid;
    if (ownerId == null || ownerId.isEmpty || ownerId == currentUserId) {
      return true;
    }
    if (!_isExperienceEffectivelyPrivate(experience)) {
      return true;
    }
    return _hasExperienceSharePermission(ownerId, experience.id);
  }

  bool _canDisplayFolloweeMetadata(Experience experience) {
    return _canViewFolloweeExperience(experience);
  }

  bool _canAccessFolloweeCategory(String ownerId, String? categoryId) {
    if (categoryId == null || categoryId.isEmpty) {
      return false;
    }
    final String? currentUserId = _authService.currentUser?.uid;
    if (ownerId == currentUserId) {
      return true;
    }
    final UserCategory? category = _followeeCategories[ownerId]?[categoryId];
    if (category == null) {
      return false;
    }
    if (!category.isPrivate) {
      return true;
    }
    return _hasCategorySharePermission(ownerId, category.id);
  }

  bool _canAccessFolloweeColorCategory(
      String ownerId, String? colorCategoryId) {
    if (colorCategoryId == null || colorCategoryId.isEmpty) {
      return false;
    }
    final String? currentUserId = _authService.currentUser?.uid;
    if (ownerId == currentUserId) {
      return true;
    }
    final ColorCategory? colorCategory =
        _followeeColorCategories[ownerId]?[colorCategoryId];
    if (colorCategory == null) {
      return false;
    }
    if (!colorCategory.isPrivate) {
      return true;
    }
    return _hasCategorySharePermission(ownerId, colorCategory.id);
  }

  bool _canEditEvent(Event event) {
    final String? currentUserId = _authService.currentUser?.uid;
    if (currentUserId == null) return false;
    return event.plannerUserId == currentUserId ||
        event.collaboratorIds.contains(currentUserId);
  }

  bool _isExperienceEffectivelyPrivate(Experience experience) {
    if (!experience.hasExplicitPrivacy) {
      return false;
    }
    return experience.isPrivate;
  }

  Future<void> _loadDataAndGenerateMarkers() async {
    print("🗺️ MAP SCREEN: Starting data load...");
    setState(() {
      _isLoading = true;
      // ADDED: Invalidate public experience data when saved experiences refresh
      // This ensures public markers don't show stale experiences that user may have just saved
      if (_isGlobalToggleActive) {
        _nearbyPublicExperiences = [];
        _publicExperienceMarkers.clear();
        print(
            "🗺️ MAP SCREEN: Cleared public experiences due to data reload (will refetch after)");
      }
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

      await _loadSharePermissions(userId);

      unawaited(_loadFollowingUsers(userId));

      // Fetch owned data in parallel (categories, color categories, owned experiences)
      final ownedResults = await Future.wait([
        _experienceService.getUserCategories(includeSharedEditable: true),
        _experienceService.getUserColorCategories(includeSharedEditable: true),
        _experienceService.getExperiencesByUser(userId,
            limit: 0), // No limit - load all owned experiences
      ]);

      _categories = ownedResults[0] as List<UserCategory>;
      _colorCategories = ownedResults[1] as List<ColorCategory>;
      _experiences = ownedResults[2] as List<Experience>;
      print(
          "🗺️ MAP SCREEN: Loaded ${_experiences.length} owned experiences and ${_categories.length}/${_colorCategories.length} categories.");
      _rebuildFolloweeCategoryIcons();

      // Render markers immediately, respecting any saved filters
      await _generateMarkersFromExperiences(_filterExperiences(_experiences));

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
        if (_tappedLocationDetails != null) {
          _maybeAttachSavedOrPublicExperience(_tappedLocationDetails!);
        }
        // ADDED: Refetch public experiences if globe is active (after saved experiences updated)
        if (_isGlobalToggleActive && _lastGlobeMapCenter != null) {
          print(
              "🗺️ MAP SCREEN: Refetching public experiences after data reload");
          unawaited(() async {
            try {
              await _fetchNearbyPublicExperiences(_lastGlobeMapCenter!);
            } catch (e) {
              print("🗺️ MAP SCREEN: Error refetching public experiences: $e");
            }
          }());
        }
      }
    }
  }

  // Load shared experiences after initial render and merge incrementally
  Future<void> _loadSharedExperiencesInBackground(String userId) async {
    try {
      if (mounted) {
        setState(() {
          _isSharedLoading = true;
        });
      }

      if (_sharedIsFetching || !_sharedHasMore) {
        return;
      }
      _sharedIsFetching = true;
      List<Experience> sharedExperiences = [];
      try {
        final page = await _experienceService.getExperiencesSharedWith(
          userId,
          limit: _sharedPageSize,
          startAfter: _sharedLastDoc,
        );
        sharedExperiences = page.$1;
        _sharedLastDoc = page.$2;
        if (sharedExperiences.isEmpty || page.$2 == null) {
          _sharedHasMore = false;
        }
        print(
            "🗺️ MAP SCREEN: [BG] Loaded page with ${sharedExperiences.length} shared experiences.");
      } catch (e) {
        // Fallback: use permissions + get by IDs for compatibility until index/denorm propagates
        print(
            "🗺️ MAP SCREEN: [BG] Paging query failed ($e). Falling back to share_permissions path.");
        // On first call, fetch all permission IDs and process in pages
        if (_fallbackSharedIds == null) {
          final sharedPermissions =
              await _sharingService.getSharedItemsForUser(userId);
          final allSharedExperienceIds = sharedPermissions
              .where((perm) => perm.itemType == ShareableItemType.experience)
              .map((perm) => perm.itemId)
              .where((id) => id.isNotEmpty)
              .toSet()
              .toList();
          _fallbackSharedIds = allSharedExperienceIds;
          _fallbackPageOffset = 0;
          print(
              "🗺️ MAP SCREEN: [BG] Fallback: Found ${_fallbackSharedIds!.length} total shared experiences to page.");
        }
        if (_fallbackSharedIds != null && _fallbackSharedIds!.isNotEmpty) {
          final start = _fallbackPageOffset;
          final end = (start + _sharedPageSize) > _fallbackSharedIds!.length
              ? _fallbackSharedIds!.length
              : (start + _sharedPageSize);
          final idsPage = _fallbackSharedIds!.sublist(start, end);
          print(
              "🗺️ MAP SCREEN: [BG] Fallback: Fetching experiences from offset $start to $end (${idsPage.length} IDs).");
          sharedExperiences =
              await _experienceService.getExperiencesByIds(idsPage);
          _fallbackPageOffset = end;
          if (end >= _fallbackSharedIds!.length) {
            _sharedHasMore = false;
            print(
                "🗺️ MAP SCREEN: [BG] Fallback: Reached end of shared experiences.");
          }
        } else {
          _sharedHasMore = false;
        }
      }

      // Fetch minimal missing category/color data for this page when denorm is absent
      final Set<String> existingCategoryIds =
          _categories.map((c) => c.id).toSet();
      final Set<String> existingColorCategoryIds =
          _colorCategories.map((c) => c.id).toSet();
      final Set<String> catKeys = {};
      final Set<String> colorKeys = {};
      final List<Future<UserCategory?>> categoryFetches = [];
      final List<Future<ColorCategory?>> colorFetches = [];

      for (final exp in sharedExperiences) {
        final String? ownerId = exp.createdBy;
        if (ownerId == null || ownerId.isEmpty) continue;

        if ((exp.categoryIconDenorm == null ||
            exp.categoryIconDenorm!.isEmpty)) {
          final String? catId = exp.categoryId;
          if (catId != null &&
              catId.isNotEmpty &&
              !existingCategoryIds.contains(catId)) {
            final key = '$ownerId|$catId';
            if (catKeys.add(key)) {
              categoryFetches.add(
                  _experienceService.getUserCategoryByOwner(ownerId, catId));
            }
          }
        }

        if ((exp.colorHexDenorm == null || exp.colorHexDenorm!.isEmpty)) {
          final String? colorId = exp.colorCategoryId;
          if (colorId != null &&
              colorId.isNotEmpty &&
              !existingColorCategoryIds.contains(colorId)) {
            final key = '$ownerId|$colorId';
            if (colorKeys.add(key)) {
              colorFetches.add(
                  _experienceService.getColorCategoryByOwner(ownerId, colorId));
            }
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
                "🗺️ MAP SCREEN: [BG] Added ${newCats.length} shared user categories (for icons).");
          }
        } catch (e) {
          print(
              "🗺️ MAP SCREEN: [BG] Error fetching shared categories for icons: $e");
        }
      }

      if (colorFetches.isNotEmpty) {
        try {
          final fetchedColors = await Future.wait(colorFetches);
          final newColors = fetchedColors.whereType<ColorCategory>().toList();
          if (newColors.isNotEmpty) {
            _colorCategories.addAll(newColors);
            print(
                "🗺️ MAP SCREEN: [BG] Added ${newColors.length} shared color categories (for colors).");
          }
        } catch (e) {
          print(
              "🗺️ MAP SCREEN: [BG] Error fetching shared color categories for colors: $e");
        }
      }

      // Skip owner name fetch for performance; optional enhancement later.

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
      _rebuildFolloweeCategoryIcons();

      // IMPORTANT: Regenerate markers after merging to pick up newly fetched category/color data
      await _generateMarkersFromExperiences(_filterExperiences(_experiences));
      print(
          "🗺️ MAP SCREEN: [BG] Shared experiences merged and markers updated with fresh category/color data.");
      if (_tappedLocationDetails != null) {
        _maybeAttachSavedOrPublicExperience(_tappedLocationDetails!);
      }

      // Continue paging in background until exhausted
      if (_sharedHasMore && mounted) {
        Future.microtask(() => _loadSharedExperiencesInBackground(userId));
      }
    } catch (e) {
      print(
          "🗺️ MAP SCREEN: [BG] Error loading shared experiences: $e. Skipping background merge.");
    } finally {
      _sharedIsFetching = false;
      if (mounted) {
        setState(() {
          _isSharedLoading =
              _sharedHasMore; // keep loading indicator until last page
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
          displayName: "My Current Location");
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
        print(
            "🗺️ MAP SCREEN: Updated _mapWidgetInitialLocation to user's location.");
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

  // Adjust marker icon size for web where the rendered pixels appear larger.
  int _markerSizeForPlatform(int baseSize) {
    if (kIsWeb) {
      final int scaled = (baseSize * 0.32).round();
      return scaled.clamp(18, baseSize);
    }
    return baseSize;
  }

  // ADDED: Helper function to create BitmapDescriptor from text/emoji
  Future<BitmapDescriptor> _bitmapDescriptorFromText(
    String text, {
    int size = 60,
    required Color backgroundColor, // Added required background color parameter
    double backgroundOpacity = 0.7, // ADDED: Opacity parameter
    Color textColor = Colors.black,
    String? fontFamily,
  }) async {
    final int effectiveSize = _markerSizeForPlatform(size);
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final double radius = effectiveSize / 2;

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
        fontSize:
            effectiveSize * 0.7, // Adjust emoji size relative to marker size
        fontFamily: fontFamily,
      ),
    );
    paragraphBuilder.pushStyle(ui.TextStyle(
      color: textColor,
      fontFamily: fontFamily,
      fontSize: effectiveSize * 0.7,
    ));
    paragraphBuilder.addText(text);
    paragraphBuilder.pop();
    final ui.Paragraph paragraph = paragraphBuilder.build();
    paragraph.layout(ui.ParagraphConstraints(width: effectiveSize.toDouble()));

    // Center the emoji text
    final double textX = (effectiveSize - paragraph.width) / 2;
    final double textY = (effectiveSize - paragraph.height) / 2;
    canvas.drawParagraph(paragraph, Offset(textX, textY));

    // Convert canvas to image
    final ui.Image image = await pictureRecorder.endRecording().toImage(
        effectiveSize, effectiveSize); // Use size for both width and height

    // Convert image to bytes
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw Exception('Failed to convert image to byte data');
    }

    return BitmapDescriptor.fromBytes(byteData.buffer.asUint8List());
  }

  // ADDED: Calculate distance in meters between two lat/lng points using Haversine formula
  double _calculateDistanceInMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadiusMeters = 6371000; // Earth's radius in meters
    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLng = _degreesToRadians(lng2 - lng1);

    final double a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(_degreesToRadians(lat1)) *
            Math.cos(_degreesToRadians(lat2)) *
            Math.sin(dLng / 2) *
            Math.sin(dLng / 2);

    final double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * Math.pi / 180;
  }

  // ADDED: Check if public experience is already saved by user
  bool _isPublicExperienceAlreadySaved(PublicExperience publicExp) {
    // Check by place ID first
    if (publicExp.placeID.isNotEmpty) {
      try {
        _experiences.firstWhere(
          (exp) =>
              exp.location.placeId != null &&
              exp.location.placeId!.isNotEmpty &&
              exp.location.placeId == publicExp.placeID,
        );
        return true; // Found a match
      } catch (_) {
        // No match by place ID, continue to coordinate check
      }
    }

    // Check by coordinates (within small tolerance)
    for (final experience in _experiences) {
      if (_areCoordinatesClose(
        experience.location.latitude,
        experience.location.longitude,
        publicExp.location.latitude,
        publicExp.location.longitude,
        tolerance: 0.0001, // Smaller tolerance for exact matches
      )) {
        return true;
      }
    }
    return false;
  }

  // ADDED: Fetch and filter nearby public experiences within 50 miles
  Future<void> _fetchNearbyPublicExperiences(LatLng center) async {
    const double fiftyMilesInMeters = 80467; // 50 miles ≈ 80467 meters
    const int targetCount = 100;
    const int maxPages = 20; // Safety limit to avoid excessive fetching

    print(
        "🗺️ MAP SCREEN: Fetching public experiences near ${center.latitude}, ${center.longitude} (within 50 miles)");

    final List<PublicExperience> nearby = [];
    DocumentSnapshot<Object?>? lastDoc;
    bool hasMore = true;
    int pageCount = 0;

    try {
      while (nearby.length < targetCount && hasMore && pageCount < maxPages) {
        pageCount++;
        final page = await _experienceService.fetchPublicExperiencesPage(
          startAfter: lastDoc,
          limit: 50,
        );

        for (final publicExp in page.experiences) {
          // Skip if already saved
          if (_isPublicExperienceAlreadySaved(publicExp)) {
            continue;
          }

          // Check distance
          final distance = _calculateDistanceInMeters(
            center.latitude,
            center.longitude,
            publicExp.location.latitude,
            publicExp.location.longitude,
          );

          if (distance <= fiftyMilesInMeters) {
            nearby.add(publicExp);
            if (nearby.length >= targetCount) {
              break;
            }
          }
        }

        lastDoc = page.lastDocument;
        hasMore = page.hasMore;
      }

      print(
          "🗺️ MAP SCREEN: Found ${nearby.length} nearby public experiences (fetched $pageCount pages)");

      if (mounted) {
        setState(() {
          _nearbyPublicExperiences = nearby;
        });
      }

      // Generate markers for these public experiences
      await _generatePublicExperienceMarkers();
    } catch (e) {
      print("🗺️ MAP SCREEN: Error fetching nearby public experiences: $e");
      rethrow;
    }
  }

  // ADDED: Helper method to find a category icon for a public experience
  // Searches Firestore for any Experience with the same placeId and returns its category icon
  // Also persists the icon to the public experience document so we don't need to look it up again
  Future<String?> _findCategoryIconForPublicExperience(
      PublicExperience publicExp) async {
    // If the public experience already has an icon, use it
    if (publicExp.icon != null && publicExp.icon!.isNotEmpty) {
      return publicExp.icon;
    }

    // Search Firestore for any experience with the same placeId
    // Pass the publicExperienceId so the icon gets persisted to the document
    if (publicExp.placeID.isNotEmpty) {
      final icon = await _experienceService.findCategoryIconByPlaceId(
        publicExp.placeID,
        publicExperienceId: publicExp.id,
      );
      if (icon != null && icon.isNotEmpty) {
        return icon;
      }
    }
    return null;
  }

  // ADDED: Generate markers for public experiences
  Future<void> _generatePublicExperienceMarkers() async {
    print(
        "🗺️ MAP SCREEN: Generating markers for ${_nearbyPublicExperiences.length} public experiences");

    _publicExperienceMarkers.clear();

    if (!mounted) {
      print(
          "🗺️ MAP SCREEN: Widget unmounted, skipping public marker generation");
      return;
    }

    // Generate default globe icon for public experiences without a category icon
    final BitmapDescriptor defaultPublicIcon = await _bitmapDescriptorFromText(
      String.fromCharCode(Icons.public.codePoint),
      size: 60,
      backgroundColor: Colors.black,
      backgroundOpacity: 1.0,
      textColor: Colors.white,
      fontFamily: Icons.public.fontFamily,
    );

    // Cache for category-based icons to avoid regenerating
    final Map<String, BitmapDescriptor> publicCategoryIconCache = {};

    for (final publicExp in _nearbyPublicExperiences) {
      final position = LatLng(
        publicExp.location.latitude,
        publicExp.location.longitude,
      );

      // Try to find a category icon for this public experience (searches Firestore)
      final String? categoryIcon =
          await _findCategoryIconForPublicExperience(publicExp);

      // Determine which icons to use
      BitmapDescriptor publicIcon;
      if (categoryIcon != null && categoryIcon.isNotEmpty) {
        // Use category icon - check cache first
        if (publicCategoryIconCache.containsKey(categoryIcon)) {
          publicIcon = publicCategoryIconCache[categoryIcon]!;
        } else {
          // Generate new icons for this category
          publicIcon = await _bitmapDescriptorFromText(
            categoryIcon,
            size: 60,
            backgroundColor: Colors.black,
            backgroundOpacity: 1.0,
          );
          publicCategoryIconCache[categoryIcon] = publicIcon;
        }
      } else {
        // Use default globe icon
        publicIcon = defaultPublicIcon;
      }

      final markerId = MarkerId('public_${publicExp.id}');
      final marker = Marker(
        markerId: markerId,
        position: position,
        infoWindow: _infoWindowForPlatform(publicExp.name),
        icon: publicIcon,
        onTap: withHeavyTap(() async {
          triggerHeavyHaptic();
          FocusScope.of(context).unfocus();
          print(
              "🗺️ MAP SCREEN: Public experience marker tapped: '${publicExp.name}'");

          // Determine icon for selected marker
          final String? tappedCategoryIcon = categoryIcon;
          final tappedMarkerId = MarkerId('selected_public_experience');
          final int animationToken = ++_markerAnimationToken;
          const int finalSize = 80;
          final int startSize = _markerStartSize(finalSize);
          Future<BitmapDescriptor> iconBuilder(int size) {
            if (tappedCategoryIcon != null && tappedCategoryIcon.isNotEmpty) {
              return _bitmapDescriptorFromText(
                tappedCategoryIcon,
                size: size,
                backgroundColor: Colors.black,
                backgroundOpacity: 1.0,
              );
            }
            return _bitmapDescriptorFromText(
              String.fromCharCode(Icons.public.codePoint),
              size: size,
              backgroundColor: Colors.black,
              backgroundOpacity: 1.0,
              textColor: Colors.white,
              fontFamily: Icons.public.fontFamily,
            );
          }

          if (!mounted || animationToken != _markerAnimationToken) {
            return;
          }
          setState(() {
            _mapWidgetInitialLocation = publicExp.location;
            _tappedLocationDetails = publicExp.location;
            _tappedLocationMarker = null;
            _tappedExperience = null;
            _tappedExperienceCategory = null;
            _tappedLocationBusinessStatus = null;
            _tappedLocationOpenNow = null;
            _publicReadOnlyExperience = publicExp.toExperienceDraft();
            _publicReadOnlyExperienceId = publicExp.id;
            _publicPreviewMediaItems = publicExp.buildMediaItemsForPreview();
            _searchController.clear();
            _searchResults = [];
            _showSearchResults = false;
          });
          unawaited(_refreshBusinessStatus(publicExp.placeID, animationToken));
          if (!mounted || animationToken != _markerAnimationToken) {
            return;
          }
          final BitmapDescriptor firstIcon = await iconBuilder(startSize);
          if (!mounted || animationToken != _markerAnimationToken) {
            return;
          }
          setState(() {
            _tappedLocationMarker = _buildSelectedMarker(
              markerId: tappedMarkerId,
              position: position,
              infoWindowTitle: publicExp.name,
              icon: firstIcon,
            );
          });
          unawaited(_animateSelectedMarkerSmooth(
            animationToken: animationToken,
            markerId: tappedMarkerId,
            position: position,
            infoWindowTitle: publicExp.name,
            iconBuilder: iconBuilder,
            startSize: startSize,
            endSize: finalSize,
          ));
          _showMarkerInfoWindow(tappedMarkerId);
        }),
      );

      _publicExperienceMarkers[publicExp.id] = marker;
    }

    print(
        "🗺️ MAP SCREEN: Generated ${_publicExperienceMarkers.length} public experience markers");

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handleCalendarToggle() async {
    if (_isCalendarDialogLoading) {
      return;
    }
    print("🗺️ MAP SCREEN: Calendar button pressed.");
    await _showEventsDialog();
  }

  // ADDED: Handle globe toggle button press
  Future<void> _handleGlobeToggle() async {
    print(
        "🗺️ MAP SCREEN: Globe toggle pressed. Current state: $_isGlobalToggleActive");

    // Toggle the state
    final bool newState = !_isGlobalToggleActive;

    if (!newState) {
      // Turning off: clear public experience data
      print(
          "🗺️ MAP SCREEN: Deactivating globe view, clearing public experiences");
      setState(() {
        _isGlobalToggleActive = false;
        _nearbyPublicExperiences = [];
        _publicExperienceMarkers.clear();
        _lastGlobeMapCenter = null;
      });
      return;
    }

    // Turning on: capture map center and fetch nearby public experiences
    print("🗺️ MAP SCREEN: Activating globe view, capturing map center...");

    try {
      // Get the map controller
      GoogleMapController? controller = _mapController;
      if (controller == null) {
        if (!_mapControllerCompleter.isCompleted) {
          print("🗺️ MAP SCREEN: Map controller not ready yet");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Map is still loading. Please try again.')),
            );
          }
          return;
        }
        controller = await _mapControllerCompleter.future;
      }

      // Get the visible region to calculate center
      final LatLngBounds bounds = await controller.getVisibleRegion();
      final LatLng center = LatLng(
        (bounds.northeast.latitude + bounds.southwest.latitude) / 2,
        (bounds.northeast.longitude + bounds.southwest.longitude) / 2,
      );

      print(
          "🗺️ MAP SCREEN: Map center captured: ${center.latitude}, ${center.longitude}");

      // Update state to show loading
      setState(() {
        _isGlobalToggleActive = true;
        _isGlobeLoading = true;
        _lastGlobeMapCenter = center;
      });

      // Show loading toast
      Fluttertoast.showToast(
        msg: 'Finding experiences from the community...',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        timeInSecForIosWeb: 2,
        backgroundColor: Colors.grey[800],
        textColor: Colors.white,
        fontSize: 16.0,
      );

      // Fetch nearby public experiences
      await _fetchNearbyPublicExperiences(center);

      // Update state to hide loading
      if (mounted) {
        setState(() {
          _isGlobeLoading = false;
          // If no experiences were found, turn off the globe toggle
          if (_nearbyPublicExperiences.isEmpty) {
            _isGlobalToggleActive = false;
            _publicExperienceMarkers.clear();
            _lastGlobeMapCenter = null;
          }
        });

        triggerHeavyHaptic();
        // Show completion toast with count
        Fluttertoast.showToast(
          msg:
              'Showing ${_nearbyPublicExperiences.length} experiences from the community!',
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          timeInSecForIosWeb: 3,
          backgroundColor: Colors.grey[800],
          textColor: Colors.white,
          fontSize: 16.0,
        );
      }

      print(
          "🗺️ MAP SCREEN: Globe view activated with ${_nearbyPublicExperiences.length} public experiences");
    } catch (e, stackTrace) {
      print("🗺️ MAP SCREEN: Error activating globe view: $e");
      print(stackTrace);

      // Revert to inactive state on error
      if (mounted) {
        setState(() {
          _isGlobalToggleActive = false;
          _isGlobeLoading = false;
          _nearbyPublicExperiences = [];
          _publicExperienceMarkers.clear();
          _lastGlobeMapCenter = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Failed to load nearby experiences: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _showEventsDialog() async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to view your events.')),
        );
      }
      return;
    }

    setState(() {
      _isCalendarDialogLoading = true;
    });

    try {
      final events = await _loadEventsForDialog(userId);
      if (!mounted) return;

      setState(() {
        _isCalendarDialogLoading = false;
      });

      await _openEventsDialog(events);
    } catch (e, stackTrace) {
      print("🗺️ MAP SCREEN: Failed to load events for dialog: $e");
      print(stackTrace);
      if (mounted) {
        setState(() {
          _isCalendarDialogLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to load events right now.')),
        );
      }
    } finally {}
  }

  Future<List<Event>> _loadEventsForDialog(String userId) async {
    final events = await _eventService.getEventsForUser(userId);
    final List<Event> sortedEvents = [...events]
      ..sort((a, b) => a.startDateTime.compareTo(b.startDateTime));
    await _cacheEventExperiencesForEvents(sortedEvents);
    return sortedEvents;
  }

  Future<void> _cacheEventExperiencesForEvents(List<Event> events) async {
    _eventExperiencesCache.clear();
    for (final exp in _experiences) {
      _eventExperiencesCache[exp.id] = exp;
    }

    final Set<String> idsToFetch = {};
    for (final event in events) {
      for (final entry in event.experiences) {
        final id = entry.experienceId;
        if (id.isNotEmpty && !_eventExperiencesCache.containsKey(id)) {
          idsToFetch.add(id);
        }
      }
    }

    if (idsToFetch.isNotEmpty) {
      try {
        final fetched =
            await _experienceService.getExperiencesByIds(idsToFetch.toList());
        for (final exp in fetched) {
          _eventExperiencesCache[exp.id] = exp;
        }
      } catch (e) {
        print("🗺️ MAP SCREEN: Error caching experiences for events: $e");
      }
    }
  }

  // Group events by date and create a list with headers
  List<_EventListItem> _buildEventListWithHeaders(List<Event> events) {
    if (events.isEmpty) return [];

    final List<_EventListItem> items = [];
    DateTime? currentDate;

    for (final event in events) {
      final eventDate = DateTime(
        event.startDateTime.year,
        event.startDateTime.month,
        event.startDateTime.day,
      );

      // Add date header if this is a new day
      if (currentDate == null || !_isSameDay(currentDate, eventDate)) {
        items.add(_EventListItem.header(eventDate));
        currentDate = eventDate;
      }

      items.add(_EventListItem.event(event));
    }

    return items;
  }

  // Format date header as "Tuesday, June 4, 2025"
  String _formatDateHeader(DateTime date) {
    return DateFormat('EEEE, MMMM d, yyyy').format(date);
  }

  // Build date header widget
  Widget _buildDateHeader(DateTime date, ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        _formatDateHeader(date),
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white70 : Colors.black87,
          fontSize: 14,
        ),
      ),
    );
  }

  Future<void> _openEventsDialog(List<Event> events) async {
    if (!mounted) return;

    final eventListItems = _buildEventListWithHeaders(events);

    // Find the index of the first upcoming event in the new list structure
    int anchorIndex = -1;
    if (events.isNotEmpty) {
      final now = DateTime.now();
      for (int i = 0; i < eventListItems.length; i++) {
        if (!eventListItems[i].isHeader && eventListItems[i].event != null) {
          if (!eventListItems[i].event!.startDateTime.isBefore(now)) {
            anchorIndex = i;
            break;
          }
        }
      }
      // If no upcoming event found, anchor to the last event
      if (anchorIndex == -1 && eventListItems.isNotEmpty) {
        anchorIndex = eventListItems.length - 1;
      }
    }

    final List<GlobalKey> itemKeys =
        List.generate(eventListItems.length, (_) => GlobalKey());

    await showDialog(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final isDark = theme.brightness == Brightness.dark;
        final ScrollController scrollController = ScrollController();

        // Scroll to anchor - first jump to estimated position, then refine with ensureVisible
        void scrollToAnchor() {
          if (anchorIndex < 0 || anchorIndex >= itemKeys.length) return;

          // Calculate estimated scroll position
          const double estimatedHeaderHeight = 40.0;
          const double estimatedCardHeight = 120.0;
          const double padding = 8.0;

          double estimatedOffset = padding;
          for (int i = 0; i < anchorIndex; i++) {
            if (eventListItems[i].isHeader) {
              estimatedOffset += estimatedHeaderHeight;
            } else {
              estimatedOffset += estimatedCardHeight;
            }
          }

          // Wait for ListView to be ready, then scroll
          void performScroll() {
            if (!dialogContext.mounted) return;

            // Check if scroll controller is attached
            if (!scrollController.hasClients) {
              Future.delayed(const Duration(milliseconds: 50), performScroll);
              return;
            }

            // First, jump to estimated position to trigger ListView rendering
            final maxScroll = scrollController.position.maxScrollExtent;
            final targetOffset = estimatedOffset.clamp(0.0, maxScroll);
            scrollController.jumpTo(targetOffset);

            // Then, after a delay, use ensureVisible for precise positioning
            // Retry multiple times since ListView.builder is lazy
            int retryCount = 0;
            void tryEnsureVisible() {
              if (!dialogContext.mounted || retryCount >= 5) return;
              retryCount++;

              final ctx = itemKeys[anchorIndex].currentContext;
              if (ctx != null && ctx.mounted) {
                Scrollable.ensureVisible(
                  ctx,
                  duration: const Duration(milliseconds: 0),
                  curve: Curves.easeOut,
                  alignment: 0.1,
                );
              } else {
                // Retry after delay to give ListView time to render
                Future.delayed(
                    const Duration(milliseconds: 100), tryEnsureVisible);
              }
            }

            // Start trying ensureVisible after initial scroll
            Future.delayed(const Duration(milliseconds: 150), tryEnsureVisible);
          }

          // Start scrolling after dialog frame
          WidgetsBinding.instance.addPostFrameCallback((_) {
            performScroll();
          });
        }

        // Initialize scroll after dialog is shown
        WidgetsBinding.instance.addPostFrameCallback((_) {
          scrollToAnchor();
        });

        return _wrapWebPointerInterceptor(Dialog(
          backgroundColor: AppColors.backgroundColor,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(dialogContext).size.width * 0.95,
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                  child: Row(
                    children: [
                      Text(
                        'Select an Event',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Google Sans',
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () {
                          triggerHeavyHaptic();
                          scrollController.dispose();
                          Navigator.of(dialogContext).pop();
                          _enterSelectMode();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        child: const Text('Create New'),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          triggerHeavyHaptic();
                          scrollController.dispose();
                          Navigator.of(dialogContext).pop();
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: events.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.event_outlined,
                                size: 48,
                                color: isDark ? Colors.white38 : Colors.black45,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No events yet',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color:
                                      isDark ? Colors.white70 : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: eventListItems.length,
                          itemBuilder: (context, index) {
                            final item = eventListItems[index];
                            return Container(
                              key: itemKeys[index],
                              child: item.isHeader
                                  ? _buildDateHeader(item.date!, theme, isDark)
                                  : _buildMapEventCard(
                                      item.event!,
                                      theme,
                                      isDark,
                                      onTap: withHeavyTap(() => _showEventCardOptions(
                                          item.event!, dialogContext)),
                                    ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ));
      },
    );
  }

  Widget _buildMapEventCard(Event event, ThemeData theme, bool isDark,
      {VoidCallback? onTap}) {
    final cardColor = isDark ? const Color(0xFF2B2930) : Colors.white;
    final borderColor = _getEventColor(event);

    return GestureDetector(
      onTap: withHeavyTap(onTap == null
          ? null
          : () {
              triggerHeavyHaptic();
              onTap();
            }),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor.withOpacity(0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: borderColor,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(16),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title.isEmpty ? 'Untitled Event' : event.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Google Sans',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 16,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatEventTime(event),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                      if (event.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          event.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (event.experiences.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${event.experiences.length} experience${event.experiences.length != 1 ? 's' : ''}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: _buildTruncatedCategoryIcons(
                                event.experiences,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getEventColor(Event event) {
    if (event.colorHex != null && event.colorHex!.isNotEmpty) {
      return _parseColor(event.colorHex!);
    }
    const colors = [
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
    ];
    final hash = event.id.hashCode;
    return colors[hash.abs() % colors.length];
  }

  // ADDED: Show options when tapping an event card
  void _showEventCardOptions(Event event, BuildContext dialogContext) {
    showModalBottomSheet<void>(
      context: dialogContext,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Event title header
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _getEventColor(event),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          event.title.isEmpty ? 'Untitled Event' : event.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 24),
                // View event page option
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.event_note,
                      color: theme.primaryColor,
                    ),
                  ),
                  title: const Text('View event page'),
                  subtitle: const Text('See full event details'),
                  onTap: withHeavyTap(() {
                    triggerHeavyHaptic();
                    Navigator.of(sheetContext).pop();
                    Navigator.of(dialogContext).pop();
                    _openEventPage(event);
                  }),
                ),
                // View event map option
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.map,
                      color: Colors.green,
                    ),
                  ),
                  title: const Text('View event map'),
                  subtitle: Text(
                      '${event.experiences.length} experience${event.experiences.length != 1 ? 's' : ''} on map'),
                  onTap: withHeavyTap(() {
                    triggerHeavyHaptic();
                    Navigator.of(sheetContext).pop(); // Close bottom sheet
                    Navigator.of(dialogContext).pop(); // Close events dialog
                    _enterEventViewMode(event);
                  }),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  // ADDED: Open event editor in view mode for the selected event
  Future<void> _openEventPage(Event event) async {
    if (!mounted) return;

    print(
        "🗺️ MAP SCREEN: Opening event page for '${event.title}' (${event.id})");

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _wrapWebPointerInterceptor(
        const Center(child: CircularProgressIndicator()),
      ),
    );

    try {
      // Resolve experiences referenced by the event (exclude event-only entries)
      final experienceIds = event.experiences
          .map((entry) => entry.experienceId)
          .where((id) => id.isNotEmpty)
          .toList();

      final Map<String, Experience> resolvedExperiences = {};
      final List<String> missingExperienceIds = [];

      for (final id in experienceIds) {
        final cached = _eventExperiencesCache[id];
        if (cached != null) {
          resolvedExperiences[id] = cached;
        } else {
          missingExperienceIds.add(id);
        }
      }

      if (missingExperienceIds.isNotEmpty) {
        final fetchedExperiences =
            await _experienceService.getExperiencesByIds(missingExperienceIds);
        for (final exp in fetchedExperiences) {
          resolvedExperiences[exp.id] = exp;
          _eventExperiencesCache[exp.id] = exp;
        }
      }

      final List<Experience> experiences = experienceIds
          .map((id) => resolvedExperiences[id])
          .whereType<Experience>()
          .toList();

      // Fetch category + color metadata from planner so viewers see correct icons
      final userId = _authService.currentUser?.uid;
      final bool isOwner = userId != null && event.plannerUserId == userId;

      List<UserCategory> categories = [];
      List<ColorCategory> colorCategories = [];

      if (isOwner) {
        categories = _categories.isNotEmpty
            ? _categories
            : await _experienceService.getUserCategories();
        colorCategories = _colorCategories.isNotEmpty
            ? _colorCategories
            : await _experienceService.getUserColorCategories();
      } else {
        final Set<String> categoryIds = {};
        final Set<String> colorCategoryIds = {};

        for (final exp in experiences) {
          if (exp.categoryId != null && exp.categoryId!.isNotEmpty) {
            categoryIds.add(exp.categoryId!);
          }
          categoryIds.addAll(exp.otherCategories.where((id) => id.isNotEmpty));

          if (exp.colorCategoryId != null && exp.colorCategoryId!.isNotEmpty) {
            colorCategoryIds.add(exp.colorCategoryId!);
          }
          colorCategoryIds
              .addAll(exp.otherColorCategoryIds.where((id) => id.isNotEmpty));
        }

        for (final entry in event.experiences) {
          if (entry.inlineCategoryId != null &&
              entry.inlineCategoryId!.isNotEmpty) {
            categoryIds.add(entry.inlineCategoryId!);
          }
          categoryIds.addAll(
              entry.inlineOtherCategoryIds.where((id) => id.isNotEmpty));

          if (entry.inlineColorCategoryId != null &&
              entry.inlineColorCategoryId!.isNotEmpty) {
            colorCategoryIds.add(entry.inlineColorCategoryId!);
          }
          colorCategoryIds.addAll(
              entry.inlineOtherColorCategoryIds.where((id) => id.isNotEmpty));
        }

        try {
          if (categoryIds.isNotEmpty) {
            categories =
                await _experienceService.getUserCategoriesByOwnerAndIds(
              event.plannerUserId,
              categoryIds.toList(),
            );
          }
        } catch (e) {
          print(
              "🗺️ MAP SCREEN: Failed to fetch planner categories for event ${event.id}: $e");
        }

        try {
          if (colorCategoryIds.isNotEmpty) {
            colorCategories =
                await _experienceService.getColorCategoriesByOwnerAndIds(
              event.plannerUserId,
              colorCategoryIds.toList(),
            );
          }
        } catch (e) {
          print(
              "🗺️ MAP SCREEN: Failed to fetch planner color categories for event ${event.id}: $e");
        }

        if (categories.isEmpty) {
          categories = _categories.isNotEmpty
              ? _categories
              : await _experienceService.getUserCategories();
        }
        if (colorCategories.isEmpty) {
          colorCategories = _colorCategories.isNotEmpty
              ? _colorCategories
              : await _experienceService.getUserColorCategories();
        }
      }

      if (!mounted) return;

      Navigator.of(context).pop();

      await Navigator.push<EventEditorResult>(
        context,
        MaterialPageRoute(
          builder: (context) => EventEditorModal(
            event: event,
            experiences: experiences,
            categories: categories,
            colorCategories: colorCategories,
            isReadOnly: true,
          ),
          fullscreenDialog: true,
        ),
      );
    } catch (e, stackTrace) {
      print("🗺️ MAP SCREEN: Error opening event page for ${event.id}: $e");
      print(stackTrace);
      if (!mounted) return;

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading event details: $e')),
      );
    }
  }

  // ADDED: Enter event view mode - show event's experiences on map
  Future<void> _enterEventViewMode(Event event) async {
    print(
        "🗺️ MAP SCREEN: Entering event view mode for '${event.title}' with ${event.experiences.length} experiences");

    if (event.experiences.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('This event has no experiences to show on the map.')),
        );
      }
      return;
    }

    setState(() {
      _activeEventViewMode = event;
      _eventViewMarkers.clear();
      _eventViewMarkerExperiences.clear();
      _eventViewMarkerEntries.clear();
      _isEventOverlayExpanded = false; // Start collapsed
      // Clear any existing tapped location
      _tappedLocationMarker = null;
      _tappedLocationDetails = null;
      _tappedExperience = null;
      _tappedExperienceCategory = null;
      _tappedLocationBusinessStatus = null;
      _tappedLocationOpenNow = null;
      _publicReadOnlyExperience = null;
      _publicReadOnlyExperienceId = null;
    });

    // Fetch planner's categories for shared events so viewers see correct icons
    final userId = _authService.currentUser?.uid;
    final bool isOwner = userId != null && event.plannerUserId == userId;
    List<UserCategory> plannerCategories = [];
    List<ColorCategory> plannerColorCategories = [];

    // Clear previous planner categories
    _plannerCategories = [];
    _plannerColorCategories = [];

    if (!isOwner) {
      // For shared events, fetch the planner's categories to show correct icons
      final Set<String> categoryIds = {};
      final Set<String> colorCategoryIds = {};

      // Collect category IDs from experiences
      for (final entry in event.experiences) {
        if (!entry.isEventOnly && entry.experienceId.isNotEmpty) {
          final experience = _eventExperiencesCache[entry.experienceId];
          if (experience != null) {
            if (experience.categoryId != null &&
                experience.categoryId!.isNotEmpty) {
              categoryIds.add(experience.categoryId!);
            }
            categoryIds.addAll(
                experience.otherCategories.where((id) => id.isNotEmpty));

            if (experience.colorCategoryId != null &&
                experience.colorCategoryId!.isNotEmpty) {
              colorCategoryIds.add(experience.colorCategoryId!);
            }
            colorCategoryIds.addAll(
                experience.otherColorCategoryIds.where((id) => id.isNotEmpty));
          }
        } else if (entry.isEventOnly) {
          // Event-only experiences
          if (entry.inlineCategoryId != null &&
              entry.inlineCategoryId!.isNotEmpty) {
            categoryIds.add(entry.inlineCategoryId!);
          }
          categoryIds.addAll(
              entry.inlineOtherCategoryIds.where((id) => id.isNotEmpty));

          if (entry.inlineColorCategoryId != null &&
              entry.inlineColorCategoryId!.isNotEmpty) {
            colorCategoryIds.add(entry.inlineColorCategoryId!);
          }
          colorCategoryIds.addAll(
              entry.inlineOtherColorCategoryIds.where((id) => id.isNotEmpty));
        }
      }

      try {
        if (categoryIds.isNotEmpty) {
          plannerCategories =
              await _experienceService.getUserCategoriesByOwnerAndIds(
            event.plannerUserId,
            categoryIds.toList(),
          );
          _plannerCategories = plannerCategories;
        }
      } catch (e) {
        print(
            "🗺️ MAP SCREEN: Failed to fetch planner categories for event ${event.id}: $e");
      }

      try {
        if (colorCategoryIds.isNotEmpty) {
          plannerColorCategories =
              await _experienceService.getColorCategoriesByOwnerAndIds(
            event.plannerUserId,
            colorCategoryIds.toList(),
          );
          _plannerColorCategories = plannerColorCategories;
        }
      } catch (e) {
        print(
            "🗺️ MAP SCREEN: Failed to fetch planner color categories for event ${event.id}: $e");
      }
    }

    // Build markers for each experience in the event
    final List<LatLng> positions = [];

    for (int i = 0; i < event.experiences.length; i++) {
      final entry = event.experiences[i];
      final int positionNumber = i + 1;

      Location? location;
      String iconText = '📍';
      Color markerBackgroundColor = _getEventColor(event);

      if (entry.isEventOnly) {
        // Inline experience
        location = entry.inlineLocation;
        iconText = entry.inlineCategoryIconDenorm ?? '📍';
      } else if (entry.experienceId.isNotEmpty) {
        // Reference to saved experience
        final experience = _eventExperiencesCache[entry.experienceId];
        if (experience != null) {
          location = experience.location;
          // Use planner's categories for shared events to show correct icons
          if (!isOwner && plannerCategories.isNotEmpty) {
            iconText = _getCategoryIconForExperienceFromCategories(
                    experience, plannerCategories) ??
                '📍';
          } else {
            iconText = _getCategoryIconForExperience(experience) ?? '📍';
          }
          // Always use event color for markers in event view mode (not experience color)
          // markerBackgroundColor remains as _getEventColor(event) set above
        }
      }

      if (location == null ||
          (location.latitude == 0.0 && location.longitude == 0.0)) {
        print(
            "🗺️ MAP SCREEN: Skipping event experience $positionNumber - no valid location");
        continue;
      }

      // Capture location as non-null for use in closure
      final validLocation = location;
      final position = LatLng(validLocation.latitude, validLocation.longitude);
      positions.add(position);

      // Generate numbered marker icon
      final markerIcon = await _bitmapDescriptorFromNumberedIcon(
        number: positionNumber,
        iconText: iconText,
        backgroundColor: markerBackgroundColor,
        size: 80, // Larger for selected state
      );

      final markerId = MarkerId('event_view_$i');

      // Store experience/entry data for this marker
      Experience? markerExperience;
      if (!entry.isEventOnly && entry.experienceId.isNotEmpty) {
        markerExperience = _eventExperiencesCache[entry.experienceId];
      }
      _eventViewMarkerExperiences[markerId.value] = markerExperience;
      _eventViewMarkerEntries[markerId.value] = entry;

      final marker = Marker(
        markerId: markerId,
        position: position,
        icon: markerIcon,
        zIndex: 2.0, // Above regular markers
        infoWindow: _infoWindowForPlatform(
          entry.isEventOnly
              ? '$positionNumber. ${entry.inlineName ?? 'Stop $positionNumber'}'
              : '$positionNumber. ${markerExperience?.name ?? 'Experience'}',
        ),
        onTap: withHeavyTap(() async {
          triggerHeavyHaptic();
          print("🗺️ MAP SCREEN: Event view marker $positionNumber tapped");
          FocusScope.of(context).unfocus();

          // If this is a saved experience, show the experience details bottom sheet
          if (markerExperience != null) {
            await _handleEventViewMarkerTap(markerExperience, validLocation,
                markerBackgroundColor, positionNumber);
          } else {
            // Event-only experience - show location details
            await _handleEventOnlyMarkerTap(
                entry, validLocation, positionNumber);
          }
        }),
      );

      _eventViewMarkers[markerId.value] = marker;
    }

    if (positions.isEmpty) {
      if (mounted) {
        setState(() {
          _activeEventViewMode = null;
          _eventViewMarkers.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No valid locations found for this event.')),
        );
      }
      return;
    }

    if (mounted) {
      setState(() {});
    }

    // Fit camera to bounds of all event markers
    await _fitCameraToBounds(positions);

    print(
        "🗺️ MAP SCREEN: Event view mode active with ${_eventViewMarkers.length} markers");
  }

  // ADDED: Generate a numbered marker icon with the itinerary position
  Future<BitmapDescriptor> _bitmapDescriptorFromNumberedIcon({
    required int number,
    required String iconText,
    required Color backgroundColor,
    int size = 80,
  }) async {
    final int effectiveSize = _markerSizeForPlatform(size);
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final double radius = effectiveSize / 2;

    // Draw main background circle (fully opaque for selected state)
    final Paint circlePaint = Paint()..color = backgroundColor;
    canvas.drawCircle(Offset(radius, radius), radius, circlePaint);

    // Draw icon/emoji in the center
    final ui.ParagraphBuilder iconBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.center,
        fontSize: effectiveSize * 0.45,
      ),
    );
    iconBuilder.pushStyle(ui.TextStyle(
      color: Colors.white,
      fontSize: effectiveSize * 0.45,
    ));
    iconBuilder.addText(iconText);
    iconBuilder.pop();
    final ui.Paragraph iconParagraph = iconBuilder.build();
    iconParagraph
        .layout(ui.ParagraphConstraints(width: effectiveSize.toDouble()));

    final double iconX = (effectiveSize - iconParagraph.width) / 2;
    final double iconY =
        (effectiveSize - iconParagraph.height) / 2 - effectiveSize * 0.08;
    canvas.drawParagraph(iconParagraph, Offset(iconX, iconY));

    // Draw number badge in bottom-right corner
    final double badgeRadius = effectiveSize * 0.22;
    final double badgeX = effectiveSize - badgeRadius - 2;
    final double badgeY = effectiveSize - badgeRadius - 2;

    // Badge background (white with border)
    final Paint badgeBorderPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final Paint badgeFillPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(badgeX, badgeY), badgeRadius, badgeFillPaint);
    canvas.drawCircle(Offset(badgeX, badgeY), badgeRadius, badgeBorderPaint);

    // Draw number text
    final ui.ParagraphBuilder numberBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.center,
        fontSize: badgeRadius * 1.2,
      ),
    );
    numberBuilder.pushStyle(ui.TextStyle(
      color: backgroundColor,
      fontSize: badgeRadius * 1.2,
      fontWeight: FontWeight.bold,
    ));
    numberBuilder.addText(number.toString());
    numberBuilder.pop();
    final ui.Paragraph numberParagraph = numberBuilder.build();
    numberParagraph.layout(ui.ParagraphConstraints(width: badgeRadius * 2));

    final double numberX = badgeX - numberParagraph.width / 2;
    final double numberY = badgeY - numberParagraph.height / 2;
    canvas.drawParagraph(numberParagraph, Offset(numberX, numberY));

    // Convert to image
    final ui.Image image = await pictureRecorder
        .endRecording()
        .toImage(effectiveSize, effectiveSize);
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw Exception('Failed to convert numbered icon to byte data');
    }

    return BitmapDescriptor.fromBytes(byteData.buffer.asUint8List());
  }

  // ADDED: Fit camera to show all positions
  Future<void> _fitCameraToBounds(List<LatLng> positions) async {
    if (positions.isEmpty) return;

    _mapController ??= await _mapControllerCompleter.future;

    if (positions.length == 1) {
      // Single position - zoom to it
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(positions.first, 16.0),
      );
      return;
    }

    // Calculate bounds
    double minLat = positions.first.latitude;
    double maxLat = positions.first.latitude;
    double minLng = positions.first.longitude;
    double maxLng = positions.first.longitude;

    for (final pos in positions) {
      if (pos.latitude < minLat) minLat = pos.latitude;
      if (pos.latitude > maxLat) maxLat = pos.latitude;
      if (pos.longitude < minLng) minLng = pos.longitude;
      if (pos.longitude > maxLng) maxLng = pos.longitude;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    await _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 80.0),
    );
  }

  // ADDED: Handle tap on event view marker for saved experience
  Future<void> _handleEventViewMarkerTap(
    Experience experience,
    Location location,
    Color markerBackgroundColor,
    int positionNumber,
  ) async {
    print(
        "🗺️ MAP SCREEN: Handling tap on saved experience in event view: '${experience.name}'");

    // Get category for the experience - use planner's categories for shared events
    UserCategory? resolvedCategory;
    final String? categoryId = experience.categoryId;
    final userId = _authService.currentUser?.uid;
    final bool isOwner = userId != null &&
        _activeEventViewMode != null &&
        _activeEventViewMode!.plannerUserId == userId;

    if (categoryId != null && categoryId.isNotEmpty) {
      try {
        // For shared events, try planner's categories first
        if (!isOwner && _plannerCategories.isNotEmpty) {
          resolvedCategory =
              _plannerCategories.firstWhere((cat) => cat.id == categoryId);
        } else {
          resolvedCategory =
              _categories.firstWhere((cat) => cat.id == categoryId);
        }
      } catch (_) {
        final String? ownerId = experience.createdBy;
        if (ownerId != null &&
            ownerId.isNotEmpty &&
            _followeeCategories.containsKey(ownerId)) {
          resolvedCategory = _followeeCategories[ownerId]?[categoryId];
        }
      }
    }
    resolvedCategory ??= _resolveCategoryForExperience(experience);

    // Generate selected icon with number badge for event view mode
    // Use planner's categories for shared events to show correct icons
    final String selectedIconText;
    if (!isOwner && _plannerCategories.isNotEmpty) {
      selectedIconText = _getCategoryIconForExperienceFromCategories(
              experience, _plannerCategories) ??
          '❓';
    } else {
      selectedIconText = _getCategoryIconForExperience(experience) ?? '❓';
    }
    final tappedMarkerId = MarkerId('selected_experience_location');
    final int animationToken = ++_markerAnimationToken;
    const int finalSize = 100;
    final int startSize = _markerStartSize(finalSize);
    Future<BitmapDescriptor> iconBuilder(int size) {
      return _bitmapDescriptorFromNumberedIcon(
        number: positionNumber,
        iconText: selectedIconText,
        backgroundColor: markerBackgroundColor,
        size: size,
      );
    }

    if (!mounted || animationToken != _markerAnimationToken) {
      return;
    }

    setState(() {
      _mapWidgetInitialLocation = location;
      _tappedLocationDetails = location;
      _tappedLocationMarker = null;
      _tappedExperience = experience;
      _tappedExperienceCategory = resolvedCategory;
      _tappedLocationBusinessStatus = null;
      _tappedLocationOpenNow = null;
      _searchController.clear();
      _searchResults = [];
      _showSearchResults = false;
    });
    unawaited(_refreshBusinessStatus(location.placeId, animationToken));
    if (!mounted || animationToken != _markerAnimationToken) {
      return;
    }
    final BitmapDescriptor firstIcon = await iconBuilder(startSize);
    if (!mounted || animationToken != _markerAnimationToken) {
      return;
    }
    setState(() {
      _tappedLocationMarker = _buildSelectedMarker(
        markerId: tappedMarkerId,
        position: LatLng(location.latitude, location.longitude),
        infoWindowTitle: '$selectedIconText ${experience.name}',
        icon: firstIcon,
      );
    });
    unawaited(_animateSelectedMarkerSmooth(
      animationToken: animationToken,
      markerId: tappedMarkerId,
      position: LatLng(location.latitude, location.longitude),
      infoWindowTitle: '$selectedIconText ${experience.name}',
      iconBuilder: iconBuilder,
      startSize: startSize,
      endSize: finalSize,
    ));

    _showMarkerInfoWindow(tappedMarkerId);
    unawaited(_prefetchExperienceMedia(experience));
  }

  // ADDED: Handle tap on event-only marker (no saved experience)
  Future<void> _handleEventOnlyMarkerTap(
    EventExperienceEntry entry,
    Location location,
    int positionNumber,
  ) async {
    print(
        "🗺️ MAP SCREEN: Handling tap on event-only experience: '${entry.inlineName}'");

    // Create a simple marker for event-only experiences
    final tappedMarkerId = MarkerId('selected_location');
    final tappedMarker = Marker(
      markerId: tappedMarkerId,
      position: LatLng(location.latitude, location.longitude),
      infoWindow:
          _infoWindowForPlatform(entry.inlineName ?? 'Stop $positionNumber'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
      zIndex: 1.0,
    );

    // Fetch business status
    String? businessStatus;
    bool? openNow;
    try {
      if (location.placeId != null && location.placeId!.isNotEmpty) {
        final detailsMap =
            await _mapsService.fetchPlaceDetailsData(location.placeId!);
        businessStatus = detailsMap?['businessStatus'] as String?;
        openNow = (detailsMap?['currentOpeningHours']?['openNow']) as bool?;
      }
    } catch (e) {
      businessStatus = null;
      openNow = null;
    }

    if (!mounted) return;

    setState(() {
      _mapWidgetInitialLocation = location;
      _tappedLocationDetails = location;
      _tappedLocationMarker = tappedMarker;
      _tappedExperience = null; // No saved experience
      _tappedExperienceCategory = null;
      _tappedLocationBusinessStatus = businessStatus;
      _tappedLocationOpenNow = openNow;
      _publicReadOnlyExperience = null;
      _publicReadOnlyExperienceId = null;
      _searchController.clear();
      _searchResults = [];
      _showSearchResults = false;
    });

    _showMarkerInfoWindow(tappedMarkerId);
  }

  // ADDED: Build event itinerary list for overlay
  Widget _buildEventItineraryList() {
    if (_activeEventViewMode == null) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
          child: Text(
            'No experiences in itinerary',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    // Combine existing experiences with draft items when in add-to-event mode
    final existingExperiences = _activeEventViewMode!.experiences;
    final draftItems = _isAddToEventModeActive
        ? _addToEventDraftItinerary
        : <EventExperienceEntry>[];
    final totalCount = existingExperiences.length + draftItems.length;

    if (totalCount == 0) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
          child: Text(
            'No experiences in itinerary',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        final bool isNewItem = index >= existingExperiences.length;
        final entry = isNewItem
            ? draftItems[index - existingExperiences.length]
            : existingExperiences[index];

        Experience? experience;
        if (!entry.isEventOnly && entry.experienceId.isNotEmpty) {
          // Find experience from cache or marker experiences map
          experience = _eventExperiencesCache[entry.experienceId];
          if (experience == null) {
            // Try to find from marker experiences map
            for (final exp in _eventViewMarkerExperiences.values) {
              if (exp?.id == entry.experienceId) {
                experience = exp;
                break;
              }
            }
          }
          // Also check from experiences list
          if (experience == null) {
            try {
              experience =
                  _experiences.firstWhere((e) => e.id == entry.experienceId);
            } catch (_) {}
          }
        }
        return _buildEventItineraryItem(entry, experience, index,
            isNewItem: isNewItem);
      },
    );
  }

  // ADDED: Build individual itinerary item for overlay
  Widget _buildEventItineraryItem(
    EventExperienceEntry entry,
    Experience? experience,
    int index, {
    bool isNewItem = false,
  }) {
    final bool isEventOnly = entry.isEventOnly;
    final String displayName = isEventOnly
        ? (entry.inlineName ?? 'Untitled')
        : (experience?.name ?? 'Unknown Experience');

    final String? colorCategoryId =
        isEventOnly ? entry.inlineColorCategoryId : experience?.colorCategoryId;

    // Get category icon - use planner's categories for shared events
    String categoryIcon = '📍';
    final userId = _authService.currentUser?.uid;
    final bool isOwner = userId != null &&
        _activeEventViewMode != null &&
        _activeEventViewMode!.plannerUserId == userId;

    if (isEventOnly) {
      categoryIcon = entry.inlineCategoryIconDenorm ?? '📍';
    } else if (experience != null) {
      // Use planner's categories for shared events to show correct icons
      if (!isOwner && _plannerCategories.isNotEmpty) {
        categoryIcon = _getCategoryIconForExperienceFromCategories(
                experience, _plannerCategories) ??
            '📍';
      } else {
        categoryIcon = _getCategoryIconForExperience(experience) ?? '📍';
      }
    }

    // Get color - use planner's color categories for shared events
    Color leadingBoxColor = Colors.grey.shade200;
    if (colorCategoryId != null) {
      try {
        ColorCategory? colorCat;
        // For shared events, try planner's color categories first
        if (!isOwner && _plannerColorCategories.isNotEmpty) {
          colorCat = _plannerColorCategories
              .firstWhere((cc) => cc.id == colorCategoryId);
        } else {
          colorCat =
              _colorCategories.firstWhere((cc) => cc.id == colorCategoryId);
        }
        leadingBoxColor = _parseColor(colorCat.colorHex).withOpacity(0.5);
      } catch (_) {
        if (isEventOnly && entry.inlineColorHexDenorm != null) {
          leadingBoxColor =
              _parseColor(entry.inlineColorHexDenorm!).withOpacity(0.5);
        } else if (experience?.colorHexDenorm != null &&
            experience!.colorHexDenorm!.isNotEmpty) {
          leadingBoxColor =
              _parseColor(experience.colorHexDenorm!).withOpacity(0.5);
        }
      }
    } else if (isEventOnly && entry.inlineColorHexDenorm != null) {
      leadingBoxColor =
          _parseColor(entry.inlineColorHexDenorm!).withOpacity(0.5);
    } else if (experience?.colorHexDenorm != null &&
        experience!.colorHexDenorm!.isNotEmpty) {
      leadingBoxColor =
          _parseColor(experience.colorHexDenorm!).withOpacity(0.5);
    }

    final String? address = isEventOnly
        ? entry.inlineLocation?.address
        : experience?.location.address;

    return Material(
      color: isNewItem ? Colors.green.withOpacity(0.08) : Colors.transparent,
      child: InkWell(
        onTap: withHeavyTap(() {
          triggerHeavyHaptic();
          _focusEventItineraryItem(entry, experience, index);
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Number badge
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isNewItem
                      ? Colors.green
                      : _getEventColor(_activeEventViewMode!),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Icon box
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: leadingBoxColor,
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Text(
                  categoryIcon,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isNewItem)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'NEW',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        else if (isEventOnly)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade600,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Event-only',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (address != null && address.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        address,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ADDED: Build select mode itinerary list for overlay
  Widget _buildSelectModeItineraryList() {
    if (_selectModeDraftItinerary.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
          child: Text(
            'No experiences selected yet.\nTap locations on the map to add them.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _selectModeDraftItinerary.length,
      itemBuilder: (context, index) {
        final entry = _selectModeDraftItinerary[index];
        Experience? experience;
        if (!entry.isEventOnly && entry.experienceId.isNotEmpty) {
          // Try to find experience from experiences list
          experience = _experiences.cast<Experience?>().firstWhere(
                (exp) => exp?.id == entry.experienceId,
                orElse: () => null,
              );
        }
        return _buildSelectModeItineraryItem(entry, experience, index);
      },
    );
  }

  // ADDED: Build individual itinerary item for select mode overlay
  Widget _buildSelectModeItineraryItem(
    EventExperienceEntry entry,
    Experience? experience,
    int index,
  ) {
    final bool isEventOnly = entry.isEventOnly;
    final String displayName = isEventOnly
        ? (entry.inlineName ?? 'Untitled')
        : (experience?.name ?? 'Unknown Experience');

    final String? colorCategoryId =
        isEventOnly ? entry.inlineColorCategoryId : experience?.colorCategoryId;

    // Get category icon
    String categoryIcon = '📍';
    if (isEventOnly) {
      categoryIcon = entry.inlineCategoryIconDenorm ?? '📍';
    } else if (experience != null) {
      categoryIcon = _getCategoryIconForExperience(experience) ?? '📍';
    }

    // Get color
    Color leadingBoxColor = Colors.grey.shade200;
    if (colorCategoryId != null) {
      try {
        final colorCat =
            _colorCategories.firstWhere((cc) => cc.id == colorCategoryId);
        leadingBoxColor = _parseColor(colorCat.colorHex).withOpacity(0.5);
      } catch (_) {
        if (isEventOnly && entry.inlineColorHexDenorm != null) {
          leadingBoxColor =
              _parseColor(entry.inlineColorHexDenorm!).withOpacity(0.5);
        } else if (experience?.colorHexDenorm != null &&
            experience!.colorHexDenorm!.isNotEmpty) {
          leadingBoxColor =
              _parseColor(experience.colorHexDenorm!).withOpacity(0.5);
        }
      }
    } else if (isEventOnly && entry.inlineColorHexDenorm != null) {
      leadingBoxColor =
          _parseColor(entry.inlineColorHexDenorm!).withOpacity(0.5);
    } else if (experience?.colorHexDenorm != null &&
        experience!.colorHexDenorm!.isNotEmpty) {
      leadingBoxColor =
          _parseColor(experience.colorHexDenorm!).withOpacity(0.5);
    }

    final String? address = isEventOnly
        ? entry.inlineLocation?.address
        : experience?.location.address;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: withHeavyTap(() {
          triggerHeavyHaptic();
          _focusSelectModeItineraryItem(entry, experience, index);
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Number badge
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: _selectModeColor,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Icon box
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: leadingBoxColor,
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Text(
                  categoryIcon,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isEventOnly)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade600,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Event-only',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (address != null && address.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        address,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // Remove button
              const SizedBox(width: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: withHeavyTap(() {
                    triggerHeavyHaptic();
                    _removeFromSelectModeDraft(index);
                  }),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.remove_circle_outline,
                      size: 20,
                      color: Colors.red[400],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ADDED: Focus map on select mode itinerary item
  Future<void> _focusSelectModeItineraryItem(
    EventExperienceEntry entry,
    Experience? experience,
    int index,
  ) async {
    Location? location;
    Color markerBackgroundColor = _selectModeColor;

    if (entry.isEventOnly) {
      location = entry.inlineLocation;
    } else if (experience != null) {
      location = experience.location;
      // Get marker color from experience
      if (experience.colorHexDenorm != null &&
          experience.colorHexDenorm!.isNotEmpty) {
        markerBackgroundColor = _parseColor(experience.colorHexDenorm!);
      } else if (experience.colorCategoryId != null) {
        try {
          final colorCat = _colorCategories
              .firstWhere((cc) => cc.id == experience.colorCategoryId);
          markerBackgroundColor = _parseColor(colorCat.colorHex);
        } catch (_) {}
      }
    }

    if (location == null ||
        (location.latitude == 0.0 && location.longitude == 0.0)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No valid location for this experience')),
        );
      }
      return;
    }

    final position = LatLng(location.latitude, location.longitude);
    _mapController ??= await _mapControllerCompleter.future;

    // Animate camera first
    await _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(position, 16.0),
    );

    // Collapse the overlay after focusing
    setState(() {
      _isSelectModeOverlayExpanded = false;
    });

    // Then show the bottom sheet by setting tapped state
    if (experience != null) {
      // Saved experience - show full experience details bottom sheet
      // Get category for the experience
      UserCategory? resolvedCategory;
      final String? categoryId = experience.categoryId;
      if (categoryId != null && categoryId.isNotEmpty) {
        try {
          resolvedCategory =
              _categories.firstWhere((cat) => cat.id == categoryId);
        } catch (_) {
          final String? ownerId = experience.createdBy;
          if (ownerId != null &&
              ownerId.isNotEmpty &&
              _followeeCategories.containsKey(ownerId)) {
            resolvedCategory = _followeeCategories[ownerId]?[categoryId];
          }
        }
      }
      resolvedCategory ??= _resolveCategoryForExperience(experience);

      // Generate selected icon with number badge for select mode
      final String selectedIconText =
          _getCategoryIconForExperience(experience) ?? '❓';
      final tappedMarkerId = MarkerId('selected_experience_location');
      final int animationToken = ++_markerAnimationToken;
      const int finalSize = 100;
      final int startSize = _markerStartSize(finalSize);
      Future<BitmapDescriptor> iconBuilder(int size) {
        return _bitmapDescriptorFromNumberedIcon(
          number: index + 1,
          iconText: selectedIconText,
          backgroundColor: markerBackgroundColor,
          size: size,
        );
      }

      if (!mounted || animationToken != _markerAnimationToken) {
        return;
      }

      setState(() {
        _mapWidgetInitialLocation = location;
        _tappedLocationDetails = location;
        _tappedLocationMarker = null;
        _tappedExperience = experience;
        _tappedExperienceCategory = resolvedCategory;
        _tappedLocationBusinessStatus = null;
        _tappedLocationOpenNow = null;
        _publicReadOnlyExperience = null;
        _publicReadOnlyExperienceId = null;
        _searchController.clear();
        _searchResults = [];
        _showSearchResults = false;
      });
      unawaited(_refreshBusinessStatus(location.placeId, animationToken));
      if (!mounted || animationToken != _markerAnimationToken) {
        return;
      }
      final BitmapDescriptor firstIcon = await iconBuilder(startSize);
      if (!mounted || animationToken != _markerAnimationToken) {
        return;
      }
      setState(() {
        _tappedLocationMarker = _buildSelectedMarker(
          markerId: tappedMarkerId,
          position: position,
          infoWindowTitle: '$selectedIconText ${experience.name}',
          icon: firstIcon,
        );
      });
      unawaited(_animateSelectedMarkerSmooth(
        animationToken: animationToken,
        markerId: tappedMarkerId,
        position: position,
        infoWindowTitle: '$selectedIconText ${experience.name}',
        iconBuilder: iconBuilder,
        startSize: startSize,
        endSize: finalSize,
      ));

      _showMarkerInfoWindow(tappedMarkerId);
      unawaited(_prefetchExperienceMedia(experience));
    } else {
      // Event-only experience - show location details bottom sheet
      final tappedMarkerId = MarkerId('selected_location');
      final tappedMarker = Marker(
        markerId: tappedMarkerId,
        position: position,
        infoWindow:
            _infoWindowForPlatform(entry.inlineName ?? 'Stop ${index + 1}'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        zIndex: 1.0,
      );

      // Fetch business status
      String? businessStatus;
      bool? openNow;
      try {
        if (location.placeId != null && location.placeId!.isNotEmpty) {
          final detailsMap =
              await _mapsService.fetchPlaceDetailsData(location.placeId!);
          businessStatus = detailsMap?['businessStatus'] as String?;
          openNow = (detailsMap?['currentOpeningHours']?['openNow']) as bool?;
        }
      } catch (e) {
        businessStatus = null;
        openNow = null;
      }

      if (!mounted) return;

      setState(() {
        _mapWidgetInitialLocation = location;
        _tappedLocationDetails = location;
        _tappedLocationMarker = tappedMarker;
        _tappedExperience = null; // No saved experience
        _tappedExperienceCategory = null;
        _tappedLocationBusinessStatus = businessStatus;
        _tappedLocationOpenNow = openNow;
        _publicReadOnlyExperience = null;
        _publicReadOnlyExperienceId = null;
        _searchController.clear();
        _searchResults = [];
        _showSearchResults = false;
      });

      _showMarkerInfoWindow(tappedMarkerId);
    }
  }

  // ADDED: Focus map on itinerary item
  Future<void> _focusEventItineraryItem(
    EventExperienceEntry entry,
    Experience? experience,
    int index,
  ) async {
    Location? location;
    Color markerBackgroundColor = _getEventColor(_activeEventViewMode!);

    if (entry.isEventOnly) {
      location = entry.inlineLocation;
    } else if (experience != null) {
      location = experience.location;
      // Get marker color from experience
      if (experience.colorHexDenorm != null &&
          experience.colorHexDenorm!.isNotEmpty) {
        markerBackgroundColor = _parseColor(experience.colorHexDenorm!);
      } else if (experience.colorCategoryId != null) {
        try {
          final colorCat = _colorCategories
              .firstWhere((cc) => cc.id == experience.colorCategoryId);
          markerBackgroundColor = _parseColor(colorCat.colorHex);
        } catch (_) {}
      }
    }

    if (location == null ||
        (location.latitude == 0.0 && location.longitude == 0.0)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No valid location for this experience')),
        );
      }
      return;
    }

    final position = LatLng(location.latitude, location.longitude);
    _mapController ??= await _mapControllerCompleter.future;

    // Animate camera first
    await _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(position, 16.0),
    );

    // Then show the bottom sheet by calling the appropriate handler
    if (experience != null) {
      // Saved experience - show full experience details bottom sheet
      await _handleEventViewMarkerTap(
          experience, location, markerBackgroundColor, index + 1);
    } else {
      // Event-only experience - show location details bottom sheet
      await _handleEventOnlyMarkerTap(entry, location, index + 1);
    }
  }

  // ADDED: Confirm exit event view mode with dialog
  Future<void> _confirmExitEventViewMode() async {
    // If in add-to-event mode, exit that first
    if (_isAddToEventModeActive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return _wrapWebPointerInterceptor(AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('Stop Adding Experiences?'),
            content: Text(
              _addToEventDraftItinerary.isEmpty
                  ? 'Are you sure you want to stop adding experiences to this event?'
                  : 'You have ${_addToEventDraftItinerary.length} unadded experience${_addToEventDraftItinerary.length != 1 ? 's' : ''}. Are you sure you want to exit?',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  triggerHeavyHaptic();
                  Navigator.of(dialogContext).pop(false);
                },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  triggerHeavyHaptic();
                  Navigator.of(dialogContext).pop(true);
                },
                child: const Text('Exit'),
              ),
            ],
          ));
        },
      );

      if (confirmed == true && mounted) {
        // If we came from event experience selector and have changes, return the updated event
        if (widget.initialEvent != null &&
            _activeEventViewMode != null &&
            _addToEventDraftItinerary.isNotEmpty) {
          final updatedEvent = _activeEventViewMode!.copyWith(
            experiences: [
              ..._activeEventViewMode!.experiences,
              ..._addToEventDraftItinerary,
            ],
            updatedAt: DateTime.now(),
          );
          Navigator.of(context).pop(updatedEvent);
        } else {
          _exitAddToEventMode();
        }
        return; // Don't exit event view mode, just exit add mode
      } else {
        return; // User cancelled
      }
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return _wrapWebPointerInterceptor(AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Leave Event View?'),
          content: const Text('Are you sure you want to leave the event view?'),
          actions: [
            TextButton(
              onPressed: () {
                triggerHeavyHaptic();
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                triggerHeavyHaptic();
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Yes'),
            ),
          ],
        ));
      },
    );

    if (confirmed == true && mounted) {
      // If we came from event experience selector (initialEvent provided), return to it with the event
      if (widget.initialEvent != null && _activeEventViewMode != null) {
        Navigator.of(context).pop(_activeEventViewMode);
      } else {
        _exitEventViewMode();
      }
    }
  }

  // ADDED: Exit event view mode
  void _exitEventViewMode() {
    print("🗺️ MAP SCREEN: Exiting event view mode");
    setState(() {
      _activeEventViewMode = null;
      _eventViewMarkers.clear();
      _eventViewMarkerExperiences.clear();
      _eventViewMarkerEntries.clear();
      _isEventOverlayExpanded = false;
      // Also exit add-to-event mode if active
      _isAddToEventModeActive = false;
      _addToEventDraftItinerary = [];
      // Clear planner categories
      _plannerCategories = [];
      _plannerColorCategories = [];
    });
  }

  // ADDED: Enter select mode - for creating new events by selecting experiences on map
  void _enterSelectMode() {
    print("🗺️ MAP SCREEN: Entering select mode for new event creation");

    // Pick a random color from the palette
    final random = Math.Random();
    final randomColor =
        _eventColorPalette[random.nextInt(_eventColorPalette.length)];

    setState(() {
      _isSelectModeActive = true;
      _selectModeColor = randomColor;
      _selectModeDraftItinerary = [];
      _isSelectModeOverlayExpanded = false;
      _selectModeEventOnlyMarkers.clear();
      // Exit event view mode if active
      if (_isEventViewModeActive) {
        _activeEventViewMode = null;
        _eventViewMarkers.clear();
        _eventViewMarkerExperiences.clear();
        _eventViewMarkerEntries.clear();
        _isEventOverlayExpanded = false;
      }
      // Exit add to event mode if active
      _isAddToEventModeActive = false;
      _addToEventDraftItinerary = [];
    });

    // Regenerate markers to show selection state (initially none selected)
    unawaited(
        _generateMarkersFromExperiences(_filterExperiences(_experiences)));
  }

  // ADDED: Enter add to event mode - for adding experiences to existing event
  void _enterAddToEventMode() {
    if (_activeEventViewMode == null) return;

    print(
        "🗺️ MAP SCREEN: Entering add to event mode for '${_activeEventViewMode!.title}'");

    setState(() {
      _isAddToEventModeActive = true;
      _addToEventDraftItinerary = [];
      // Exit regular select mode if active
      _isSelectModeActive = false;
      _selectModeDraftItinerary = [];
      _isSelectModeOverlayExpanded = false;
      _selectModeEventOnlyMarkers.clear();
    });

    // Regenerate markers to show selection state
    unawaited(
        _generateMarkersFromExperiences(_filterExperiences(_experiences)));
  }

  // ADDED: Exit select mode
  void _exitSelectMode() {
    print("🗺️ MAP SCREEN: Exiting select mode");
    setState(() {
      _isSelectModeActive = false;
      _selectModeDraftItinerary = [];
      _isSelectModeOverlayExpanded = false;
      _selectModeEventOnlyMarkers.clear();
    });
    // Regenerate markers to remove numbered badges
    unawaited(
        _generateMarkersFromExperiences(_filterExperiences(_experiences)));
  }

  // ADDED: Exit add to event mode
  void _exitAddToEventMode() {
    print("🗺️ MAP SCREEN: Exiting add to event mode");
    setState(() {
      _isAddToEventModeActive = false;
      _addToEventDraftItinerary = [];
    });
    // Regenerate markers to remove selection state
    unawaited(
        _generateMarkersFromExperiences(_filterExperiences(_experiences)));
  }

  // ADDED: Finish adding to event and navigate back to event editor
  Future<void> _finishAddToEvent() async {
    if (_addToEventDraftItinerary.isEmpty || _activeEventViewMode == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No experiences selected to add.')),
        );
      }
      return;
    }

    final userId = _authService.currentUser?.uid;
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to update the event.')),
        );
      }
      return;
    }

    // Show loading indicator
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _wrapWebPointerInterceptor(
        const Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );

    try {
      // Combine existing experiences with new ones
      final updatedExperiences = [
        ..._activeEventViewMode!.experiences,
        ..._addToEventDraftItinerary,
      ];

      // Create updated event with new experiences
      final updatedEvent = _activeEventViewMode!.copyWith(
        experiences: updatedExperiences,
        updatedAt: DateTime.now(),
      );

      // Fetch experiences that are referenced in the itinerary (non-event-only entries)
      final allExperienceIds = updatedEvent.experiences
          .map((entry) => entry.experienceId)
          .where((id) => id.isNotEmpty)
          .toList();

      List<Experience> experiences = [];
      if (allExperienceIds.isNotEmpty) {
        experiences =
            await _experienceService.getExperiencesByIds(allExperienceIds);
      }

      // Fetch user's categories and color categories
      final categories = await _experienceService.getUserCategories();
      final colorCategories = await _experienceService.getUserColorCategories();

      if (!mounted) return;

      // Close loading dialog
      Navigator.of(context).pop();

      // Exit add to event mode
      _exitAddToEventMode();

      // Pop the map screen to go back
      Navigator.of(context).pop();

      // Navigate to event editor with updated event
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EventEditorModal(
              event: updatedEvent,
              experiences: experiences,
              categories: categories,
              colorCategories: colorCategories,
            ),
            fullscreenDialog: true,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      // Close loading dialog
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open event editor: $e')),
      );
    }
  }

  // ADDED: Confirm exit select mode (prompts if there are items in the draft)
  Future<void> _confirmExitSelectMode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return _wrapWebPointerInterceptor(AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Stop Selecting Events?'),
          content: const Text(
            'Are you sure you want to stop selecting for your new event?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                triggerHeavyHaptic();
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                triggerHeavyHaptic();
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Stop'),
            ),
          ],
        ));
      },
    );

    if (confirmed == true && mounted) {
      _exitSelectMode();
    }
  }

  // ADDED: Finish select mode and open event editor with selected experiences
  Future<void> _finishSelectModeAndOpenEditor() async {
    if (_selectModeDraftItinerary.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Please select at least one experience before continuing.')),
        );
      }
      return;
    }

    final userId = _authService.currentUser?.uid;
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to create an event.')),
        );
      }
      return;
    }

    // Show loading indicator
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _wrapWebPointerInterceptor(
        const Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );

    try {
      // Create a new event with the draft itinerary
      final now = DateTime.now();
      final defaultStart = DateTime(now.year, now.month, now.day, now.hour, 0);
      final defaultEnd = defaultStart.add(const Duration(hours: 2));

      // Convert select mode color to hex string
      final colorHexString =
          '#${_selectModeColor.value.toRadixString(16).padLeft(8, '0').substring(2)}';

      final newEvent = Event(
        id: '',
        title: '',
        description: '',
        startDateTime: defaultStart,
        endDateTime: defaultEnd,
        plannerUserId: userId,
        experiences: _selectModeDraftItinerary,
        createdAt: now,
        updatedAt: now,
        colorHex: colorHexString,
      );

      // Fetch experiences that are referenced in the itinerary (non-event-only entries)
      final experienceIds = _selectModeDraftItinerary
          .map((entry) => entry.experienceId)
          .where((id) => id.isNotEmpty)
          .toList();

      List<Experience> experiences = [];
      if (experienceIds.isNotEmpty) {
        experiences =
            await _experienceService.getExperiencesByIds(experienceIds);
      }

      // Fetch user's categories and color categories
      final categories = await _experienceService.getUserCategories();
      final colorCategories = await _experienceService.getUserColorCategories();

      if (!mounted) return;

      // Close loading dialog
      Navigator.of(context).pop();

      // Exit select mode before navigating
      _exitSelectMode();

      // Navigate to event editor
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EventEditorModal(
            event: newEvent,
            experiences: experiences,
            categories: categories,
            colorCategories: colorCategories,
          ),
          fullscreenDialog: true,
        ),
      );

      // Handle result if needed (e.g., refresh events list)
      if (result != null && mounted) {
        // Event was saved or edited
        // Could refresh data here if needed
      }
    } catch (e) {
      if (!mounted) return;

      // Close loading dialog
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening event editor: $e')),
      );
    }
  }

  // ADDED: Check if an experience is in the select mode draft and return its index
  int? _getSelectModeDraftIndexForExperience(Experience experience) {
    for (int i = 0; i < _selectModeDraftItinerary.length; i++) {
      final entry = _selectModeDraftItinerary[i];
      if (!entry.isEventOnly && entry.experienceId == experience.id) {
        return i;
      }
    }
    return null;
  }

  int? _getAddToEventDraftIndexForExperience(Experience experience) {
    for (int i = 0; i < _addToEventDraftItinerary.length; i++) {
      final entry = _addToEventDraftItinerary[i];
      if (!entry.isEventOnly && entry.experienceId == experience.id) {
        return i;
      }
    }
    return null;
  }

  // ADDED: Check if tapped item is in the active event's itinerary
  bool _isTappedItemInEventItinerary() {
    if (_activeEventViewMode == null || _tappedLocationDetails == null)
      return false;

    if (_tappedExperience != null) {
      // Check if saved experience is in event
      return _activeEventViewMode!.experiences.any((entry) =>
          !entry.isEventOnly && entry.experienceId == _tappedExperience!.id);
    } else {
      // Check if location (event-only) is in event by placeId or coordinates
      return _activeEventViewMode!.experiences.any((entry) {
        if (!entry.isEventOnly || entry.inlineLocation == null) return false;
        // Check by placeId first
        if (_tappedLocationDetails!.placeId != null &&
            _tappedLocationDetails!.placeId!.isNotEmpty &&
            entry.inlineLocation!.placeId == _tappedLocationDetails!.placeId) {
          return true;
        }
        // Check by coordinates
        return _areCoordinatesClose(
          _tappedLocationDetails!.latitude,
          _tappedLocationDetails!.longitude,
          entry.inlineLocation!.latitude,
          entry.inlineLocation!.longitude,
          tolerance: 0.0005,
        );
      });
    }
  }

  // ADDED: Add tapped item directly to event itinerary and enter add-to-event mode
  Future<void> _addTappedItemToEvent() async {
    if (_activeEventViewMode == null || _tappedLocationDetails == null) return;

    // Create the entry
    EventExperienceEntry entry;
    if (_tappedExperience != null) {
      entry = EventExperienceEntry(experienceId: _tappedExperience!.id);
    } else {
      entry = EventExperienceEntry(
        experienceId: '',
        inlineName: _tappedLocationDetails!.getPlaceName(),
        inlineDescription: '',
        inlineLocation: _tappedLocationDetails,
        inlineCategoryId: _tappedExperienceCategory?.id,
        inlineColorCategoryId: null,
        inlineCategoryIconDenorm: _tappedExperienceCategory?.icon ?? '📍',
        inlineColorHexDenorm: null,
      );
    }

    // Enter add-to-event mode with this item
    setState(() {
      _isAddToEventModeActive = true;
      _addToEventDraftItinerary = [entry];
      _isSelectModeActive = false;
      _selectModeDraftItinerary = [];
      // Clear tapped location
      _tappedLocationMarker = null;
      _tappedLocationDetails = null;
      _tappedExperience = null;
      _tappedExperienceCategory = null;
      _tappedLocationBusinessStatus = null;
      _tappedLocationOpenNow = null;
    });

    // Regenerate markers to show selection state
    unawaited(
        _generateMarkersFromExperiences(_filterExperiences(_experiences)));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Added to event. Tap "✓" to save changes.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ADDED: Remove tapped item from event itinerary
  Future<void> _removeTappedItemFromEvent() async {
    if (_activeEventViewMode == null || _tappedLocationDetails == null) return;

    // Find the index of the item to remove
    int indexToRemove = -1;

    if (_tappedExperience != null) {
      // Find saved experience in event
      indexToRemove = _activeEventViewMode!.experiences.indexWhere((entry) =>
          !entry.isEventOnly && entry.experienceId == _tappedExperience!.id);
    } else {
      // Find location (event-only) in event
      indexToRemove = _activeEventViewMode!.experiences.indexWhere((entry) {
        if (!entry.isEventOnly || entry.inlineLocation == null) return false;
        if (_tappedLocationDetails!.placeId != null &&
            _tappedLocationDetails!.placeId!.isNotEmpty &&
            entry.inlineLocation!.placeId == _tappedLocationDetails!.placeId) {
          return true;
        }
        return _areCoordinatesClose(
          _tappedLocationDetails!.latitude,
          _tappedLocationDetails!.longitude,
          entry.inlineLocation!.latitude,
          entry.inlineLocation!.longitude,
          tolerance: 0.0005,
        );
      });
    }

    if (indexToRemove == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item not found in event')),
      );
      return;
    }

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _wrapWebPointerInterceptor(
        const Center(child: CircularProgressIndicator()),
      ),
    );

    try {
      // Create updated experiences list without the removed item
      final updatedExperiences =
          List<EventExperienceEntry>.from(_activeEventViewMode!.experiences)
            ..removeAt(indexToRemove);

      // Create updated event
      final updatedEvent = _activeEventViewMode!.copyWith(
        experiences: updatedExperiences,
        updatedAt: DateTime.now(),
      );

      // Save the event
      await _eventService.updateEvent(updatedEvent);

      if (!mounted) return;

      // Close loading dialog
      Navigator.of(context).pop();

      // Clear tapped location state
      setState(() {
        _tappedLocationMarker = null;
        _tappedLocationDetails = null;
        _tappedExperience = null;
        _tappedExperienceCategory = null;
        _tappedLocationBusinessStatus = null;
        _tappedLocationOpenNow = null;
      });

      // Refresh event view mode with updated event
      await _enterEventViewMode(updatedEvent);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Removed from event'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove: $e')),
        );
      }
    }
  }

  // ADDED: Check if a location is in the select mode draft and return its index
  int? _getSelectModeDraftIndexForLocation(Location location) {
    for (int i = 0; i < _selectModeDraftItinerary.length; i++) {
      final entry = _selectModeDraftItinerary[i];
      if (entry.isEventOnly && entry.inlineLocation != null) {
        // Compare by placeId first, then coordinates
        if (location.placeId != null &&
            location.placeId!.isNotEmpty &&
            entry.inlineLocation!.placeId == location.placeId) {
          return i;
        }
        if (_areCoordinatesClose(
          location.latitude,
          location.longitude,
          entry.inlineLocation!.latitude,
          entry.inlineLocation!.longitude,
          tolerance: 0.0005,
        )) {
          return i;
        }
      }
    }
    return null;
  }

  // ADDED: Check if tapped item is in draft itinerary (select mode or add-to-event mode)
  bool _isTappedItemInDraftItinerary() {
    if (_tappedLocationDetails == null) return false;

    if (_tappedExperience != null) {
      // Check if saved experience is in draft
      if (_isSelectModeActive) {
        return _getSelectModeDraftIndexForExperience(_tappedExperience!) !=
            null;
      } else if (_isAddToEventModeActive) {
        return _getAddToEventDraftIndexForExperience(_tappedExperience!) !=
            null;
      }
    } else {
      // Check if location is in draft
      if (_isSelectModeActive) {
        return _getSelectModeDraftIndexForLocation(_tappedLocationDetails!) !=
            null;
      } else if (_isAddToEventModeActive) {
        // Check in add-to-event draft
        for (final entry in _addToEventDraftItinerary) {
          if (entry.isEventOnly && entry.inlineLocation != null) {
            if (_tappedLocationDetails!.placeId != null &&
                _tappedLocationDetails!.placeId!.isNotEmpty &&
                entry.inlineLocation!.placeId ==
                    _tappedLocationDetails!.placeId) {
              return true;
            }
            if (_areCoordinatesClose(
              _tappedLocationDetails!.latitude,
              _tappedLocationDetails!.longitude,
              entry.inlineLocation!.latitude,
              entry.inlineLocation!.longitude,
              tolerance: 0.0005,
            )) {
              return true;
            }
          }
        }
      }
    }

    return false;
  }

  // ADDED: Check if tapped item is in existing event itinerary (for add-to-event mode)
  bool _isTappedItemInExistingEventItinerary() {
    if (_activeEventViewMode == null || _tappedLocationDetails == null)
      return false;

    if (_tappedExperience != null) {
      // Check if saved experience is in event
      return _activeEventViewMode!.experiences.any((entry) =>
          !entry.isEventOnly && entry.experienceId == _tappedExperience!.id);
    } else {
      // Check if location (event-only) is in event by placeId or coordinates
      return _activeEventViewMode!.experiences.any((entry) {
        if (!entry.isEventOnly || entry.inlineLocation == null) return false;
        if (_tappedLocationDetails!.placeId != null &&
            _tappedLocationDetails!.placeId!.isNotEmpty &&
            entry.inlineLocation!.placeId == _tappedLocationDetails!.placeId) {
          return true;
        }
        return _areCoordinatesClose(
          _tappedLocationDetails!.latitude,
          _tappedLocationDetails!.longitude,
          entry.inlineLocation!.latitude,
          entry.inlineLocation!.longitude,
          tolerance: 0.0005,
        );
      });
    }
  }

  // ADDED: Remove tapped item from draft itinerary
  void _removeTappedItemFromDraftItinerary() {
    if (_tappedLocationDetails == null) return;

    if (_tappedExperience != null) {
      // Remove saved experience from draft
      if (_isSelectModeActive) {
        final index = _getSelectModeDraftIndexForExperience(_tappedExperience!);
        if (index != null) {
          _removeFromSelectModeDraft(index);
        }
      } else if (_isAddToEventModeActive) {
        final index = _getAddToEventDraftIndexForExperience(_tappedExperience!);
        if (index != null) {
          setState(() {
            _addToEventDraftItinerary.removeAt(index);
          });
          // Regenerate markers to update selection state
          unawaited(_generateMarkersFromExperiences(
              _filterExperiences(_experiences)));
        }
      }
    } else {
      // Remove location from draft
      if (_isSelectModeActive) {
        final index =
            _getSelectModeDraftIndexForLocation(_tappedLocationDetails!);
        if (index != null) {
          _removeFromSelectModeDraft(index);
        }
      } else if (_isAddToEventModeActive) {
        // Find and remove from add-to-event draft
        int? indexToRemove;
        for (int i = 0; i < _addToEventDraftItinerary.length; i++) {
          final entry = _addToEventDraftItinerary[i];
          if (entry.isEventOnly && entry.inlineLocation != null) {
            if (_tappedLocationDetails!.placeId != null &&
                _tappedLocationDetails!.placeId!.isNotEmpty &&
                entry.inlineLocation!.placeId ==
                    _tappedLocationDetails!.placeId) {
              indexToRemove = i;
              break;
            }
            if (_areCoordinatesClose(
              _tappedLocationDetails!.latitude,
              _tappedLocationDetails!.longitude,
              entry.inlineLocation!.latitude,
              entry.inlineLocation!.longitude,
              tolerance: 0.0005,
            )) {
              indexToRemove = i;
              break;
            }
          }
        }
        if (indexToRemove != null) {
          setState(() {
            _addToEventDraftItinerary.removeAt(indexToRemove!);
          });
          // Regenerate markers to update selection state
          unawaited(_generateMarkersFromExperiences(
              _filterExperiences(_experiences)));
        }
      }
    }
  }

  // ADDED: Add experience to select mode draft itinerary
  void _addToSelectModeDraft(EventExperienceEntry entry) {
    // Check for duplicates based on experienceId or inline location
    final isDuplicate = _selectModeDraftItinerary.any((existing) {
      if (entry.isEventOnly && existing.isEventOnly) {
        // Compare inline locations
        return entry.inlineLocation?.placeId != null &&
            existing.inlineLocation?.placeId == entry.inlineLocation?.placeId;
      } else if (!entry.isEventOnly && !existing.isEventOnly) {
        // Compare experience IDs
        return entry.experienceId == existing.experienceId;
      }
      return false;
    });

    if (isDuplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This item is already in your itinerary'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _selectModeDraftItinerary.add(entry);
    });

    // Regenerate markers to show numbered badges for selected items
    if (entry.isEventOnly) {
      // Generate event-only marker immediately
      unawaited(_generateSelectModeEventOnlyMarkers());
    }
    // Always regenerate experience markers (they may have been selected)
    unawaited(_regenerateMarkersForSelectMode());

    // Show feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Added to itinerary (${_selectModeDraftItinerary.length} item${_selectModeDraftItinerary.length != 1 ? 's' : ''})',
        ),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ADDED: Remove item from select mode draft itinerary
  void _removeFromSelectModeDraft(int index) {
    if (index >= 0 && index < _selectModeDraftItinerary.length) {
      setState(() {
        _selectModeDraftItinerary.removeAt(index);
      });
      // Regenerate markers to update numbered badges
      unawaited(_regenerateMarkersForSelectMode());
    }
  }

  // ADDED: Regenerate markers when select mode draft changes
  Future<void> _regenerateMarkersForSelectMode() async {
    if (!_isSelectModeActive) return;
    // Regenerate all experience markers to reflect selection state
    await _generateMarkersFromExperiences(_filterExperiences(_experiences));
  }

  // ADDED: Generate markers for event-only entries in select mode
  Future<void> _generateSelectModeEventOnlyMarkers() async {
    _selectModeEventOnlyMarkers.clear();

    for (int i = 0; i < _selectModeDraftItinerary.length; i++) {
      final entry = _selectModeDraftItinerary[i];
      if (!entry.isEventOnly || entry.inlineLocation == null) continue;

      final location = entry.inlineLocation!;
      if (location.latitude == 0.0 && location.longitude == 0.0) continue;

      final position = LatLng(location.latitude, location.longitude);
      final iconText = entry.inlineCategoryIconDenorm ?? '📍';
      final positionNumber = i + 1;

      try {
        final markerIcon = await _bitmapDescriptorFromNumberedIcon(
          number: positionNumber,
          iconText: iconText,
          backgroundColor: _selectModeColor,
          size: 90, // Larger size for selected markers
        );

        final markerId = MarkerId('select_mode_event_only_$i');
        final marker = Marker(
          markerId: markerId,
          position: position,
          icon: markerIcon,
          zIndex: 2.0, // Above regular markers
          infoWindow: _infoWindowForPlatform(
              entry.inlineName ?? 'Stop $positionNumber'),
          onTap: withHeavyTap(() async {
            triggerHeavyHaptic();
            FocusScope.of(context).unfocus();
            // Show location details bottom sheet
            await _selectLocationOnMap(
              location,
              fetchPlaceDetails: false,
              updateLoadingState: false,
              animateCamera: true,
              markerId: 'selected_location',
            );
          }),
        );

        _selectModeEventOnlyMarkers[markerId.value] = marker;
      } catch (e) {
        print(
            "🗺️ MAP SCREEN: Failed to generate marker for event-only entry: $e");
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  // ADDED: Handle selecting current tapped location for event itinerary
  void _handleSelectForEvent() {
    if (_tappedLocationDetails == null) return;

    EventExperienceEntry entry;

    if (_tappedExperience != null) {
      // Existing saved experience - add as experience-backed entry
      entry = EventExperienceEntry(
        experienceId: _tappedExperience!.id,
      );
    } else {
      // Arbitrary location - add as event-only entry
      entry = EventExperienceEntry(
        experienceId: '', // Empty for event-only
        inlineName: _tappedLocationDetails!.getPlaceName(),
        inlineDescription: '',
        inlineLocation: _tappedLocationDetails,
        inlineCategoryId: _tappedExperienceCategory?.id,
        inlineColorCategoryId: null,
        inlineCategoryIconDenorm: _tappedExperienceCategory?.icon ?? '📍',
        inlineColorHexDenorm: null,
      );
    }

    if (_isAddToEventModeActive) {
      // Add to event mode - check against current event's experiences
      _addToEventDraft(entry);
    } else {
      // Regular select mode - add to draft itinerary
      _addToSelectModeDraft(entry);
    }

    // Clear the tapped location after adding
    setState(() {
      _tappedLocationMarker = null;
      _tappedLocationDetails = null;
      _tappedExperience = null;
      _tappedExperienceCategory = null;
      _tappedLocationBusinessStatus = null;
      _tappedLocationOpenNow = null;
    });
  }

  // ADDED: Add to event draft (similar to select mode but checks against current event)
  void _addToEventDraft(EventExperienceEntry entry) {
    if (_activeEventViewMode == null) return;

    // Check for duplicates in current event's experiences
    final isDuplicateInEvent =
        _activeEventViewMode!.experiences.any((existing) {
      if (entry.isEventOnly && existing.isEventOnly) {
        return entry.inlineLocation?.placeId != null &&
            existing.inlineLocation?.placeId == entry.inlineLocation?.placeId;
      } else if (!entry.isEventOnly && !existing.isEventOnly) {
        return entry.experienceId == existing.experienceId;
      }
      return false;
    });

    // Check for duplicates in draft
    final isDuplicateInDraft = _addToEventDraftItinerary.any((existing) {
      if (entry.isEventOnly && existing.isEventOnly) {
        return entry.inlineLocation?.placeId != null &&
            existing.inlineLocation?.placeId == entry.inlineLocation?.placeId;
      } else if (!entry.isEventOnly && !existing.isEventOnly) {
        return entry.experienceId == existing.experienceId;
      }
      return false;
    });

    if (isDuplicateInEvent || isDuplicateInDraft) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This item is already in your event itinerary'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _addToEventDraftItinerary.add(entry);
    });

    // Regenerate markers to show selection state
    unawaited(
        _generateMarkersFromExperiences(_filterExperiences(_experiences)));
  }

  String _formatEventTime(Event event) {
    final start = DateFormat('h:mm a').format(event.startDateTime);
    final end = DateFormat('h:mm a').format(event.endDateTime);

    if (_isSameDay(event.startDateTime, event.endDateTime)) {
      return '$start - $end';
    } else {
      return '$start - ${DateFormat('MMM d, h:mm a').format(event.endDateTime)}';
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildTruncatedCategoryIcons(List<EventExperienceEntry> entries) {
    final icons = entries
        .map((entry) => _getCategoryIconForEntry(entry))
        .where((icon) => icon != null)
        .cast<String>()
        .toList();

    if (icons.isEmpty) {
      return const SizedBox.shrink();
    }

    return Text(
      icons.join(' '),
      style: const TextStyle(fontSize: 14),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );
  }

  String? _getCategoryIconForEntry(EventExperienceEntry entry) {
    if (entry.isEventOnly) {
      return entry.inlineCategoryIconDenorm?.isNotEmpty == true
          ? entry.inlineCategoryIconDenorm
          : '📍';
    }

    final experience = _eventExperiencesCache[entry.experienceId];
    if (experience != null) {
      if (experience.categoryIconDenorm != null &&
          experience.categoryIconDenorm!.isNotEmpty) {
        return experience.categoryIconDenorm;
      }

      if (experience.categoryId != null && experience.categoryId!.isNotEmpty) {
        try {
          final category = _categories.firstWhere(
            (cat) => cat.id == experience.categoryId,
          );
          if (category.icon.isNotEmpty) {
            return category.icon;
          }
        } catch (_) {
          // Category not found in user's categories
        }
      }
    }

    return null;
  }

  // Helper function to navigate to the Experience Page
  Future<void> _navigateToExperience(
      Experience experience, UserCategory category) async {
    print("🗺️ MAP SCREEN: Navigating to experience: ${experience.name}");
    // Set flag to disable search field during navigation return
    setState(() {
      _isReturningFromNavigation = true;
    });
    // Unfocus any focused element to dismiss keyboard before navigation
    FocusScope.of(context).unfocus();
    // Disable focus on search field to prevent it from gaining focus during navigation
    _searchFocusNode.canRequestFocus = false;
    // Clear search state to prevent search from triggering on return
    _searchController.removeListener(_onSearchChanged);
    _searchController.clear();
    final List<UserCategory> additionalCategories =
        _collectAccessibleCategoriesForExperience(experience);
    final List<ColorCategory> mergedColorCategories =
        _buildColorCategoryListForExperience(experience);
    // Save the state to restore selection after navigation
    final Experience savedExperience = experience;
    final UserCategory savedCategory = category;
    final Location savedLocation = experience.location;
    final String? savedBusinessStatus = _tappedLocationBusinessStatus;
    final bool? savedOpenNow = _tappedLocationOpenNow;
    // Clear the temporary tapped marker when navigating away
    setState(() {
      _tappedLocationMarker = null;
      _tappedLocationDetails = null;
      _tappedExperience = null; // ADDED: Clear associated experience
      _tappedExperienceCategory = null; // ADDED: Clear associated category
      _tappedLocationBusinessStatus = null; // ADDED: Clear business status
      _tappedLocationOpenNow = null; // ADDED: Clear open-now status
      _publicReadOnlyExperience =
          null; // ADDED: Clear any public fallback experience
      _publicReadOnlyExperienceId = null;
      _showSearchResults = false;
      _searchResults = [];
    });
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => ExperiencePageScreen(
          experience: experience,
          category: category,
          userColorCategories: mergedColorCategories,
          additionalUserCategories: additionalCategories,
        ),
      ),
    );
    if (!mounted) return;
    // Force hide keyboard immediately after returning from navigation
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    if (result == true) {
      await _loadDataAndGenerateMarkers();
    }
    if (!mounted) return;
    // Force hide keyboard again before restore to prevent any flicker
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    // Restore the selected experience state after returning from navigation
    await _restoreSelectedExperience(
      savedExperience,
      savedCategory,
      savedLocation,
      savedBusinessStatus,
      savedOpenNow,
    );
    // Re-enable search field focus and re-add the listener after restore is complete
    if (mounted) {
      setState(() {
        _isReturningFromNavigation = false;
      });
      _searchFocusNode.canRequestFocus = true;
      _searchController.addListener(_onSearchChanged);
    }
  }

  /// Restores the selected experience state after returning from navigation.
  /// This rebuilds the marker and bottom sheet without animating the camera.
  Future<void> _restoreSelectedExperience(
    Experience experience,
    UserCategory category,
    Location location,
    String? businessStatus,
    bool? openNow,
  ) async {
    // Force hide keyboard using system channel
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    // Ensure any keyboard is dismissed before restoring state
    FocusScope.of(context).unfocus();
    // Wait for keyboard to fully dismiss before restoring state
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    // Force hide again after delay to ensure it stays hidden
    SystemChannels.textInput.invokeMethod('TextInput.hide');

    // Get marker background color from color category
    Color markerBackgroundColor = Colors.grey;
    try {
      if (experience.colorCategoryId != null) {
        final colorCat = _colorCategories
            .firstWhere((cc) => cc.id == experience.colorCategoryId);
        markerBackgroundColor = _parseColor(colorCat.colorHex);
      }
    } catch (_) {}

    final String iconText = (experience.categoryIconDenorm != null &&
            experience.categoryIconDenorm!.isNotEmpty)
        ? experience.categoryIconDenorm!
        : category.icon;

    final tappedMarkerId = MarkerId('selected_experience_location');
    final int animationToken = ++_markerAnimationToken;
    const int finalSize = 100;
    final int startSize = _markerStartSize(finalSize);

    Future<BitmapDescriptor> iconBuilder(int size) {
      return _bitmapDescriptorFromText(
        iconText,
        backgroundColor: markerBackgroundColor,
        size: size,
        backgroundOpacity: 1.0,
      );
    }

    if (!mounted || animationToken != _markerAnimationToken) {
      return;
    }

    // Restore state to show bottom sheet
    setState(() {
      _tappedLocationDetails = location;
      _tappedExperience = experience;
      _tappedExperienceCategory = category;
      _tappedLocationBusinessStatus = businessStatus;
      _tappedLocationOpenNow = openNow;
    });

    // Build and set the marker
    final BitmapDescriptor firstIcon = await iconBuilder(startSize);
    if (!mounted || animationToken != _markerAnimationToken) {
      return;
    }
    setState(() {
      _tappedLocationMarker = _buildSelectedMarker(
        markerId: tappedMarkerId,
        position: LatLng(location.latitude, location.longitude),
        infoWindowTitle: '$iconText ${experience.name}',
        icon: firstIcon,
      );
    });

    // Animate marker to final size
    unawaited(_animateSelectedMarkerSmooth(
      animationToken: animationToken,
      markerId: tappedMarkerId,
      position: LatLng(location.latitude, location.longitude),
      infoWindowTitle: '$iconText ${experience.name}',
      iconBuilder: iconBuilder,
      startSize: startSize,
      endSize: finalSize,
    ));
  }

  Future<void> _handleTappedLocationNavigation() async {
    if (_tappedExperience != null && _tappedExperienceCategory != null) {
      await _navigateToExperience(
        _tappedExperience!,
        _tappedExperienceCategory!,
      );
      return;
    }
    if (_publicReadOnlyExperience != null) {
      final Experience publicExperience = _publicReadOnlyExperience!;
      final String? publicExperienceId = _publicReadOnlyExperienceId;
      final List<SharedMediaItem>? publicPreviewMediaItems =
          _publicPreviewMediaItems;
      setState(() {
        _tappedLocationMarker = null;
        _tappedLocationDetails = null;
        _tappedLocationBusinessStatus = null;
        _tappedLocationOpenNow = null;
        _publicReadOnlyExperience = null;
        _publicReadOnlyExperienceId = null;
      });
      final dynamic result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ExperiencePageScreen(
            experience: publicExperience,
            category: _publicReadOnlyCategory,
            userColorCategories: const <ColorCategory>[],
            readOnlyPreview: true,
            initialMediaItems: publicPreviewMediaItems,
            focusMapOnPop: true,
            publicExperienceId: publicExperienceId,
          ),
        ),
      );
      // Handle focus payload from read-only back
      if (mounted && result is Map<String, dynamic>) {
        try {
          final String? focusId = result['focusExperienceId'] as String?;
          if (focusId != null && focusId.isNotEmpty) {
            // Prefer the local publicExperience we navigated with
            await _focusExperienceOnMap(
              publicExperience,
              usePurpleMarker: true,
            );
            return;
          }
          // Fallback: if lat/lng provided, animate and set tapped location
          final double? lat = (result['latitude'] as num?)?.toDouble();
          final double? lng = (result['longitude'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            final Location loc = Location(
              latitude: lat,
              longitude: lng,
              displayName: result['focusExperienceName'] as String?,
              placeId: result['placeId'] as String?,
            );
            await _selectLocationOnMap(
              loc,
              fetchPlaceDetails: false,
              updateLoadingState: false,
              animateCamera: true,
              markerId: 'selected_experience_location',
            );
          }
        } catch (_) {
          // Ignore result parsing errors and simply return
        }
      }
    }
  }

  // --- ADDED: Helper to focus and select a given experience on the map ---
  Future<void> _focusExperienceOnMap(Experience experience,
      {bool usePurpleMarker = false}) async {
    try {
      // Animate to experience location
      final LatLng target = LatLng(
        experience.location.latitude,
        experience.location.longitude,
      );
      _mapController ??= await _mapControllerCompleter.future;
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(target, 16.0),
      );

      // Build selected marker similar to onTap logic
      Color markerBackgroundColor = Colors.grey;
      try {
        if (experience.colorCategoryId != null) {
          final colorCat = _colorCategories
              .firstWhere((cc) => cc.id == experience.colorCategoryId);
          markerBackgroundColor = _parseColor(colorCat.colorHex);
        }
      } catch (_) {}

      final tappedMarkerId = MarkerId('selected_experience_location');
      final int animationToken = ++_markerAnimationToken;
      const int finalSize = 100;
      final int startSize = _markerStartSize(finalSize);
      final String iconText = (experience.categoryIconDenorm != null &&
              experience.categoryIconDenorm!.isNotEmpty)
          ? experience.categoryIconDenorm!
          : _resolveCategoryForExperience(experience).icon;
      Future<BitmapDescriptor> iconBuilder(int size) {
        return _bitmapDescriptorFromText(
          iconText,
          backgroundColor: markerBackgroundColor,
          size: size,
          backgroundOpacity: 1.0,
        );
      }

      if (!mounted || animationToken != _markerAnimationToken) {
        return;
      }
      setState(() {
        _mapWidgetInitialLocation = experience.location;
        _tappedLocationDetails = experience.location;
        _tappedLocationMarker = usePurpleMarker
            ? _buildSelectedMarker(
                markerId: tappedMarkerId,
                position: target,
                infoWindowTitle:
                    '${_resolveCategoryForExperience(experience).icon} ${experience.name}',
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueViolet,
                ),
              )
            : null;
        _tappedExperience = experience;
        _tappedExperienceCategory = _resolveCategoryForExperience(experience);
      });
      if (!usePurpleMarker) {
        unawaited(_refreshBusinessStatus(
          experience.location.placeId,
          animationToken,
        ));
      }
      if (!usePurpleMarker) {
        if (!mounted || animationToken != _markerAnimationToken) {
          return;
        }
        final BitmapDescriptor firstIcon = await iconBuilder(startSize);
        if (!mounted || animationToken != _markerAnimationToken) {
          return;
        }
        setState(() {
          _tappedLocationMarker = _buildSelectedMarker(
            markerId: tappedMarkerId,
            position: target,
            infoWindowTitle:
                '${_resolveCategoryForExperience(experience).icon} ${experience.name}',
            icon: firstIcon,
          );
        });
        unawaited(_animateSelectedMarkerSmooth(
          animationToken: animationToken,
          markerId: tappedMarkerId,
          position: target,
          infoWindowTitle:
              '${_resolveCategoryForExperience(experience).icon} ${experience.name}',
          iconBuilder: iconBuilder,
          startSize: startSize,
          endSize: finalSize,
        ));
      }
      _showMarkerInfoWindow(tappedMarkerId);
      unawaited(_prefetchExperienceMedia(experience));
    } catch (_) {
      // Best-effort focus; ignore errors
    }
  }

  void _maybeAttachSavedOrPublicExperience(Location location) {
    final Experience? saved = _findMatchingExperience(location);
    if (saved != null) {
      final UserCategory category = _resolveCategoryForExperience(saved);
      final bool requiresUpdate = _tappedExperience?.id != saved.id ||
          _tappedExperienceCategory?.id != category.id ||
          _publicReadOnlyExperience != null;
      if (requiresUpdate && mounted) {
        setState(() {
          _tappedExperience = saved;
          _tappedExperienceCategory = category;
          _publicReadOnlyExperience = null;
          _publicReadOnlyExperienceId = null;
        });
      }
      return;
    }

    if (_publicExperienceDraft != null &&
        _doesLocationMatchInitialPublic(location)) {
      final bool requiresUpdate = _publicReadOnlyExperience == null;
      if (requiresUpdate && mounted) {
        setState(() {
          _tappedExperience = null;
          _tappedExperienceCategory = null;
          _publicReadOnlyExperience = _publicExperienceDraft;
          _publicReadOnlyExperienceId = _publicExperienceDraftId;
        });
      }
    } else if (_publicReadOnlyExperience != null && mounted) {
      setState(() {
        _publicReadOnlyExperience = null;
        _publicReadOnlyExperienceId = null;
      });
    }
  }

  Experience? _findMatchingExperience(Location location) {
    if (_experiences.isEmpty) {
      return null;
    }
    final String? placeId = location.placeId;
    if (placeId != null && placeId.isNotEmpty) {
      try {
        return _experiences.firstWhere(
          (exp) =>
              exp.location.placeId != null &&
              exp.location.placeId!.isNotEmpty &&
              exp.location.placeId == placeId,
        );
      } catch (_) {
        // No match by place ID, fall through to coordinate comparison.
      }
    }

    for (final experience in _experiences) {
      if (_areCoordinatesClose(
        experience.location.latitude,
        experience.location.longitude,
        location.latitude,
        location.longitude,
      )) {
        return experience;
      }
    }
    return null;
  }

  bool _doesLocationMatchInitialPublic(Location location) {
    final Location? publicLocation = widget.initialPublicExperience?.location;
    if (publicLocation == null) {
      return false;
    }
    if (location.placeId != null &&
        location.placeId!.isNotEmpty &&
        publicLocation.placeId != null &&
        publicLocation.placeId!.isNotEmpty &&
        location.placeId == publicLocation.placeId) {
      return true;
    }
    return _areCoordinatesClose(
      location.latitude,
      location.longitude,
      publicLocation.latitude,
      publicLocation.longitude,
    );
  }

  bool _areCoordinatesClose(
    double lat1,
    double lng1,
    double lat2,
    double lng2, {
    double tolerance = 0.0005,
  }) {
    return (lat1 - lat2).abs() <= tolerance && (lng1 - lng2).abs() <= tolerance;
  }

  UserCategory _resolveCategoryForExperience(Experience experience) {
    final String? categoryId = experience.categoryId;
    if (categoryId != null) {
      final UserCategory? accessibleCategory =
          _getAccessibleUserCategory(experience.createdBy, categoryId);
      if (accessibleCategory != null) {
        return accessibleCategory;
      }
    }
    final String fallbackIcon = (experience.categoryIconDenorm != null &&
            experience.categoryIconDenorm!.isNotEmpty)
        ? experience.categoryIconDenorm!
        : '*';
    return UserCategory(
      id: categoryId ?? 'uncategorized',
      name: categoryId != null ? 'Shared Category' : 'Uncategorized',
      icon: fallbackIcon,
      ownerUserId: experience.createdBy ?? '',
    );
  }

  int _getMediaCountForExperience(Experience experience) {
    final cached = _experienceMediaCache[experience.id];
    return cached?.length ?? experience.sharedMediaItemIds.length;
  }

  Future<void> _prefetchExperienceMedia(Experience experience) async {
    if (experience.sharedMediaItemIds.isEmpty) {
      return;
    }
    if (_experienceMediaCache.containsKey(experience.id)) {
      return;
    }
    if (_mediaPrefetchInFlight.contains(experience.id)) {
      return;
    }
    _mediaPrefetchInFlight.add(experience.id);
    try {
      print(
          "🗺️ MAP SCREEN: Prefetching media for experience '${experience.name}' (${experience.sharedMediaItemIds.length} IDs).");
      final items = await _experienceService
          .getSharedMediaItems(experience.sharedMediaItemIds);
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _experienceMediaCache[experience.id] = items;
      });
      print(
          "🗺️ MAP SCREEN: Prefetched ${items.length} media items for '${experience.name}'.");
    } catch (e) {
      print(
          "🗺️ MAP SCREEN: Error prefetching media for '${experience.name}': $e");
    } finally {
      _mediaPrefetchInFlight.remove(experience.id);
    }
  }

  Future<void> _onPlayExperienceContent() async {
    if (_tappedExperience != null) {
      final Experience experience = _tappedExperience!;
      final List<SharedMediaItem>? cachedItems =
          _experienceMediaCache[experience.id];
      late final List<SharedMediaItem> resolvedItems;

      if (cachedItems == null) {
        if (experience.sharedMediaItemIds.isEmpty) {
          print(
              "🗺️ MAP SCREEN: Play button tapped but experience '${experience.name}' has no shared media IDs.");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text(
                      'No saved content available yet for this experience.')),
            );
          }
          return;
        }
        try {
          print(
              "🗺️ MAP SCREEN: Fetching media items on-demand for '${experience.name}'.");
          final fetched = await _experienceService
              .getSharedMediaItems(experience.sharedMediaItemIds);
          fetched.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          resolvedItems = fetched;
          if (mounted) {
            setState(() {
              _experienceMediaCache[experience.id] = fetched;
            });
          }
        } catch (e) {
          print("🗺️ MAP SCREEN: Error loading media items for preview: $e");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not load content preview: $e')),
            );
          }
          return;
        }
      } else {
        resolvedItems = cachedItems;
      }

      if (resolvedItems.isEmpty) {
        print(
            "🗺️ MAP SCREEN: No media items available after fetch for '${experience.name}'.");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'No saved content available yet for this experience.')),
          );
        }
        return;
      }

      if (!mounted) return;

      print(
          "🗺️ MAP SCREEN: Opening shared media preview modal for '${experience.name}' with ${resolvedItems.length} items.");
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        useRootNavigator: true,
        sheetAnimationStyle: const AnimationStyle(
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
          duration: Duration(milliseconds: 480),
          reverseDuration: Duration(milliseconds: 320),
        ),
        builder: (modalContext) {
          print(
              "🗺️ MAP SCREEN: Building SharedMediaPreviewModal for '${experience.name}'.");
          return SharedMediaPreviewModal(
            experience: experience,
            mediaItem: resolvedItems.first,
            mediaItems: resolvedItems,
            onLaunchUrl: _launchExternalUrl,
            category: _tappedExperienceCategory,
            userColorCategories: _colorCategories,
          );
        },
      );
      print(
          "🗺️ MAP SCREEN: Shared media preview modal for '${experience.name}' dismissed.");
      return;
    }

    if (_publicReadOnlyExperience != null) {
      final Experience publicExperience = _publicReadOnlyExperience!;
      final List<SharedMediaItem>? previewItems = _publicPreviewMediaItems;

      if (previewItems == null || previewItems.isEmpty) {
        print(
            "🗺️ MAP SCREEN: Play button tapped but public experience '${publicExperience.name}' has no preview media.");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'No saved content available yet for this experience.')),
          );
        }
        return;
      }

      if (!mounted) return;

      print(
          "🗺️ MAP SCREEN: Opening public experience preview modal for '${publicExperience.name}' with ${previewItems.length} items.");
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        useRootNavigator: true,
        sheetAnimationStyle: const AnimationStyle(
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
          duration: Duration(milliseconds: 480),
          reverseDuration: Duration(milliseconds: 320),
        ),
        builder: (modalContext) {
          print(
              "🗺️ MAP SCREEN: Building SharedMediaPreviewModal for public experience '${publicExperience.name}'.");
          return SharedMediaPreviewModal(
            experience: publicExperience,
            mediaItem: previewItems.first,
            mediaItems: previewItems,
            onLaunchUrl: _launchExternalUrl,
            category: _publicReadOnlyCategory,
            userColorCategories: const <ColorCategory>[],
            isPublicExperience: true,
            publicExperienceId: _publicReadOnlyExperienceId,
          );
        },
      );
      print(
          "🗺️ MAP SCREEN: Public shared media preview modal for '${publicExperience.name}' dismissed.");
      return;
    }

    print(
        "🗺️ MAP SCREEN: Play button tapped but no experience (saved or public) is currently selected.");
  }

  Future<void> _launchExternalUrl(String url) async {
    if (url.isEmpty) {
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      print("🗺️ MAP SCREEN: launchExternalUrl received an invalid URI: $url");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link is invalid.')),
        );
      }
      return;
    }
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link.')),
        );
      }
    } catch (e) {
      print("🗺️ MAP SCREEN: Failed to launch external URL $url: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link: $e')),
        );
      }
    }
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

  void _showMarkerInfoWindow(MarkerId markerId) {
    // Info windows are intentionally disabled.
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

  List<Experience> _filterExperiences(List<Experience> source) {
    if (!_hasActiveFilters) {
      return source;
    }
    return source.where(_experienceMatchesActiveFilters).toList();
  }

  bool _experienceMatchesActiveFilters(Experience exp) {
    final String? ownerId = exp.createdBy;
    final bool followeeSelected =
        ownerId != null && _selectedFolloweeIds.contains(ownerId);
    final bool followeeCategoryFiltersActive =
        followeeSelected && _hasSelectedCategoriesForFollowee(ownerId);
    final bool followeeColorFiltersActive =
        followeeSelected && _hasSelectedColorCategoriesForFollowee(ownerId);
    final Set<String> followeeCategorySelection =
        ownerId != null && followeeCategoryFiltersActive
            ? (_followeeCategorySelections[ownerId] ?? const <String>{})
            : const <String>{};
    final Set<String> followeeColorSelection =
        ownerId != null && followeeColorFiltersActive
            ? (_followeeColorSelections[ownerId] ?? const <String>{})
            : const <String>{};

    final bool categoryMatch =
        (!followeeSelected || followeeCategoryFiltersActive)
            ? (_selectedCategoryIds.isEmpty ||
                (exp.categoryId != null &&
                    _selectedCategoryIds.contains(exp.categoryId)) ||
                exp.otherCategories
                    .any((catId) => _selectedCategoryIds.contains(catId)))
            : true;

    final bool colorMatch = (!followeeSelected || followeeColorFiltersActive)
        ? (_selectedColorCategoryIds.isEmpty ||
            (exp.colorCategoryId != null &&
                _selectedColorCategoryIds.contains(exp.colorCategoryId)) ||
            exp.otherColorCategoryIds
                .any((colorId) => _selectedColorCategoryIds.contains(colorId)))
        : true;
    final bool followeeCategoryMatch = followeeCategoryFiltersActive
        ? ((exp.categoryId != null &&
                followeeCategorySelection.contains(exp.categoryId)) ||
            exp.otherCategories
                .any((catId) => followeeCategorySelection.contains(catId)))
        : true;
    final bool followeeColorMatch = followeeColorFiltersActive
        ? ((exp.colorCategoryId != null &&
                followeeColorSelection.contains(exp.colorCategoryId)) ||
            exp.otherColorCategoryIds
                .any((colorId) => followeeColorSelection.contains(colorId)))
        : true;

    final bool followeeMatch = _selectedFolloweeIds.isEmpty ||
        (followeeSelected && _canViewFolloweeExperience(exp));

    return categoryMatch &&
        colorMatch &&
        followeeCategoryMatch &&
        followeeColorMatch &&
        followeeMatch;
  }

  Future<void> _persistFilterSelections(Set<String> categoryIds,
      Set<String> colorCategoryIds, Set<String> followeeIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        AppConstants.mapFilterCategoryIdsKey,
        categoryIds.toList(),
      );
      await prefs.setStringList(
        AppConstants.mapFilterColorIdsKey,
        colorCategoryIds.toList(),
      );
      await prefs.setStringList(
        AppConstants.mapFilterFolloweeIdsKey,
        followeeIds.toList(),
      );
    } catch (e) {
      print("🗺️ MAP SCREEN: Failed to persist filter selections: $e");
    }
  }

  // --- ADDED: Filter Dialog ---
  Future<void> _showFilterDialog() async {
    // Prefetch owner display names for shared categories to show labels identically to Collections
    try {
      final String? currentUserId = _authService.currentUser?.uid;
      if (currentUserId != null) {
        final Set<String> ownerIdsToFetch = {};
        for (final c in _categories) {
          if (c.ownerUserId.isNotEmpty && c.ownerUserId != currentUserId) {
            ownerIdsToFetch.add(c.ownerUserId);
          }
        }
        for (final cc in _colorCategories) {
          if (cc.ownerUserId.isNotEmpty && cc.ownerUserId != currentUserId) {
            ownerIdsToFetch.add(cc.ownerUserId);
          }
        }
        if (ownerIdsToFetch.isNotEmpty) {
          await Future.wait(ownerIdsToFetch.map(_getOwnerDisplayName));
        }
      }
    } catch (_) {
      // Ignore prefetch errors; UI will fallback to 'Someone'
    }

    // Create temporary sets to hold selections within the dialog
    Set<String> tempSelectedCategoryIds = Set.from(_selectedCategoryIds);
    Set<String> tempSelectedColorCategoryIds =
        Set.from(_selectedColorCategoryIds);
    Set<String> tempSelectedFolloweeIds = Set.from(_selectedFolloweeIds);
    final Map<String, Set<String>> tempFolloweeCategorySelections = {
      for (final entry in _followeeCategorySelections.entries)
        entry.key: Set<String>.from(entry.value),
    };
    final Map<String, Set<String>> tempFolloweeColorSelections = {
      for (final entry in _followeeColorSelections.entries)
        entry.key: Set<String>.from(entry.value),
    };

    String? activeFolloweeId;
    UserProfile? activeFolloweeProfile;

    final ScrollController dialogScrollController = ScrollController();

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateOuter) {
            return _wrapWebPointerInterceptor(AlertDialog(
              backgroundColor: Colors.white,
              title: const Text('Filter Experiences'),
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.85,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                  ),
                  child: StatefulBuilder(
                    // Use StatefulBuilder to manage state within the dialog
                    builder:
                        (BuildContext context, StateSetter setStateDialog) {
                      void updateDialogState(VoidCallback fn) {
                        setStateDialog(fn);
                        setStateOuter(() {});
                      }

                      if (activeFolloweeId != null) {
                        final String followeeId = activeFolloweeId!;
                        final UserProfile followeeProfile =
                            activeFolloweeProfile ??
                                _followingUsers.firstWhere(
                                    (profile) => profile.id == followeeId,
                                    orElse: () => UserProfile(id: followeeId));
                        final String displayName =
                            _getUserDisplayName(followeeProfile);
                        final List<UserCategory> detailCategories =
                            (_followeeCategories[followeeId]?.values ??
                                    const Iterable<UserCategory>.empty())
                                .where((category) => _canAccessFolloweeCategory(
                                    followeeId, category.id))
                                .toList()
                              ..sort((a, b) => a.name.compareTo(b.name));
                        final List<ColorCategory> detailColors =
                            (_followeeColorCategories[followeeId]?.values ??
                                    const Iterable<ColorCategory>.empty())
                                .where((colorCategory) =>
                                    _canAccessFolloweeColorCategory(
                                        followeeId, colorCategory.id))
                                .toList()
                              ..sort((a, b) => a.name.compareTo(b.name));
                        final int experienceCount =
                            _followeePublicExperiences[followeeId]?.length ?? 0;

                        return SingleChildScrollView(
                          controller: dialogScrollController,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.arrow_back),
                                    tooltip: 'Back',
                                    onPressed: () {
                                      triggerHeavyHaptic();
                                      updateDialogState(() {
                                        activeFolloweeId = null;
                                        activeFolloweeProfile = null;
                                      });
                                    },
                                  ),
                                  Expanded(
                                    child: Text(
                                      'Filters for $displayName',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                experienceCount > 0
                                    ? '$experienceCount experiences available'
                                    : 'No experiences yet',
                                style: const TextStyle(
                                    fontSize: 13, color: Colors.black54),
                              ),
                              const SizedBox(height: 16),
                              const Text('By Category:',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              if (detailCategories.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    'No categories available.',
                                    style: TextStyle(color: Colors.black54),
                                  ),
                                )
                              else
                                ...detailCategories.map((category) {
                                  return CheckboxListTile(
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    contentPadding: EdgeInsets.zero,
                                    title: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 16,
                                          child: Center(
                                              child: Text(category.icon)),
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
                                    value: tempFolloweeCategorySelections[
                                                followeeId]
                                            ?.contains(category.id) ??
                                        false,
                                    onChanged: (bool? selected) {
                                      updateDialogState(() {
                                        if (selected == true) {
                                          tempFolloweeCategorySelections
                                              .putIfAbsent(
                                                  followeeId, () => <String>{})
                                              .add(category.id);
                                          tempSelectedFolloweeIds
                                              .add(followeeId);
                                        } else {
                                          tempFolloweeCategorySelections[
                                                  followeeId]
                                              ?.remove(category.id);
                                          if (tempFolloweeCategorySelections[
                                                      followeeId]
                                                  ?.isEmpty ??
                                              false) {
                                            tempFolloweeCategorySelections
                                                .remove(followeeId);
                                          }
                                        }
                                      });
                                    },
                                  );
                                }),
                              const SizedBox(height: 16),
                              const Text('By Color:',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              if (detailColors.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    'No color categories available.',
                                    style: TextStyle(color: Colors.black54),
                                  ),
                                )
                              else
                                ...detailColors.map((colorCategory) {
                                  return CheckboxListTile(
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    contentPadding: EdgeInsets.zero,
                                    title: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 16,
                                          height: 16,
                                          decoration: BoxDecoration(
                                            color: _parseColor(
                                                colorCategory.colorHex),
                                            shape: BoxShape.circle,
                                            border:
                                                Border.all(color: Colors.grey),
                                          ),
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
                                    value:
                                        tempFolloweeColorSelections[followeeId]
                                                ?.contains(colorCategory.id) ??
                                            false,
                                    onChanged: (bool? selected) {
                                      updateDialogState(() {
                                        if (selected == true) {
                                          tempFolloweeColorSelections
                                              .putIfAbsent(
                                                  followeeId, () => <String>{})
                                              .add(colorCategory.id);
                                          tempSelectedFolloweeIds
                                              .add(followeeId);
                                        } else {
                                          tempFolloweeColorSelections[
                                                  followeeId]
                                              ?.remove(colorCategory.id);
                                          if (tempFolloweeColorSelections[
                                                      followeeId]
                                                  ?.isEmpty ??
                                              false) {
                                            tempFolloweeColorSelections
                                                .remove(followeeId);
                                          }
                                        }
                                      });
                                    },
                                  );
                                }),
                            ],
                          ),
                        );
                      }

                      return SingleChildScrollView(
                        controller: dialogScrollController,
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
                              final bool isSharedOwner = category.ownerUserId !=
                                  _authService.currentUser?.uid;
                              final String? ownerName = isSharedOwner
                                  ? _ownerNameByUserId[category.ownerUserId]
                                  : null;
                              final String? shareLabel = isSharedOwner
                                  ? 'Shared by ${ownerName ?? 'Someone'}'
                                  : null;
                              // This map returns a Widget (CheckboxListTile)
                              return CheckboxListTile(
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                title: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 16,
                                          child: Center(
                                              child: Text(category.icon)),
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
                                    if (shareLabel != null)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(left: 28),
                                        child: Text(
                                          shareLabel,
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600]),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: null,
                                value: tempSelectedCategoryIds
                                    .contains(category.id),
                                onChanged: (bool? selected) {
                                  updateDialogState(() {
                                    if (selected == true) {
                                      tempSelectedCategoryIds.add(category.id);
                                    } else {
                                      tempSelectedCategoryIds
                                          .remove(category.id);
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
                              final bool isSharedOwner =
                                  colorCategory.ownerUserId !=
                                      _authService.currentUser?.uid;
                              final String? ownerName = isSharedOwner
                                  ? _ownerNameByUserId[
                                      colorCategory.ownerUserId]
                                  : null;
                              final String? shareLabel = isSharedOwner
                                  ? 'Shared by ${ownerName ?? 'Someone'}'
                                  : null;
                              // This map returns a Widget (CheckboxListTile)
                              return CheckboxListTile(
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
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
                                              color: _parseColor(
                                                  colorCategory.colorHex),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                  color: Colors.grey)),
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
                                    if (shareLabel != null)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(left: 28),
                                        child: Text(
                                          shareLabel,
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600]),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: null,
                                value: tempSelectedColorCategoryIds
                                    .contains(colorCategory.id),
                                onChanged: (bool? selected) {
                                  updateDialogState(() {
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
                            const SizedBox(height: 16),
                            const Text('By People You Follow:',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            if (_followingUsers.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  'Follow friends to filter their public experiences.',
                                  style: TextStyle(color: Colors.black54),
                                ),
                              )
                            else
                              ..._followingUsers.map((profile) {
                                final String displayName =
                                    _getUserDisplayName(profile);
                                final int experienceCount =
                                    _followeePublicExperiences[profile.id]
                                            ?.length ??
                                        0;
                                final Widget leadingAvatar;
                                if (profile.photoURL != null &&
                                    profile.photoURL!.trim().isNotEmpty) {
                                  leadingAvatar = ClipOval(
                                    child: CachedNetworkImage(
                                      imageUrl: profile.photoURL!.trim(),
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) =>
                                          CircleAvatar(
                                        radius: 20,
                                        backgroundColor: Colors.grey[200],
                                        child: const SizedBox.shrink(),
                                      ),
                                      errorWidget: (context, url, error) {
                                        final String initial =
                                            displayName.isNotEmpty
                                                ? displayName
                                                    .substring(0, 1)
                                                    .toUpperCase()
                                                : profile.id
                                                    .substring(0, 1)
                                                    .toUpperCase();
                                        return CircleAvatar(
                                          radius: 20,
                                          backgroundColor: Colors.grey[300],
                                          child: Text(
                                            initial,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                } else {
                                  final String initial = displayName.isNotEmpty
                                      ? displayName
                                          .substring(0, 1)
                                          .toUpperCase()
                                      : profile.id
                                          .substring(0, 1)
                                          .toUpperCase();
                                  leadingAvatar = CircleAvatar(
                                    radius: 20,
                                    backgroundColor: Colors.grey[300],
                                    child: Text(
                                      initial,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white),
                                    ),
                                  );
                                }

                                final bool isSelected = tempSelectedFolloweeIds
                                    .contains(profile.id);
                                final Set<String> followeeCategoryIds =
                                    _getFolloweeAccessibleCategoryIds(
                                        profile.id);
                                final Set<String> followeeColorIds =
                                    _getFolloweeAccessibleColorCategoryIds(
                                        profile.id);

                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Checkbox(
                                        value: isSelected,
                                        onChanged: (bool? selected) {
                                          updateDialogState(() {
                                            if (selected == true) {
                                              tempSelectedFolloweeIds
                                                  .add(profile.id);
                                            } else {
                                              tempSelectedFolloweeIds
                                                  .remove(profile.id);
                                              tempSelectedCategoryIds
                                                  .removeWhere(
                                                      followeeCategoryIds
                                                          .contains);
                                              tempSelectedColorCategoryIds
                                                  .removeWhere(followeeColorIds
                                                      .contains);
                                            }
                                          });
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: withHeavyTap(() {
                                            triggerHeavyHaptic();
                                            updateDialogState(() {
                                              activeFolloweeId = profile.id;
                                              activeFolloweeProfile = profile;
                                            });
                                            dialogScrollController.animateTo(
                                              0,
                                              duration: const Duration(
                                                  milliseconds: 200),
                                              curve: Curves.easeOut,
                                            );
                                          }),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              leadingAvatar,
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      displayName,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      experienceCount > 0
                                                          ? '$experienceCount experiences'
                                                          : 'No experiences yet',
                                                      style: const TextStyle(
                                                          fontSize: 12,
                                                          color:
                                                              Colors.black54),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Icon(Icons.chevron_right),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              actions: <Widget>[
                if (activeFolloweeId == null)
                  TextButton(
                    child: const Text('Show All'),
                    onPressed: () {
                      triggerHeavyHaptic();
                      tempSelectedCategoryIds.clear();
                      tempSelectedColorCategoryIds.clear();
                      tempSelectedFolloweeIds.clear();
                      tempFolloweeCategorySelections.clear();
                      tempFolloweeColorSelections.clear();

                      setState(() {
                        _selectedCategoryIds =
                            tempSelectedCategoryIds; // Now empty
                        _selectedColorCategoryIds =
                            tempSelectedColorCategoryIds; // Now empty
                        _selectedFolloweeIds = tempSelectedFolloweeIds;
                        _followeeCategorySelections
                          ..clear()
                          ..addAll(tempFolloweeCategorySelections);
                        _followeeColorSelections
                          ..clear()
                          ..addAll(tempFolloweeColorSelections);
                      });
                      unawaited(_persistFilterSelections(
                        _selectedCategoryIds,
                        _selectedColorCategoryIds,
                        _selectedFolloweeIds,
                      ));

                      Navigator.of(context).pop();
                      _applyFiltersAndUpdateMarkers();
                    },
                  ),
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () {
                    triggerHeavyHaptic();
                    Navigator.of(context)
                        .pop(); // Close dialog without applying
                  },
                ),
                TextButton(
                  child: const Text('Apply'),
                  onPressed: () {
                    triggerHeavyHaptic();
                    // Apply the selected filters from the temporary sets
                    setState(() {
                      _selectedCategoryIds = tempSelectedCategoryIds;
                      _selectedColorCategoryIds = tempSelectedColorCategoryIds;
                      _selectedFolloweeIds = tempSelectedFolloweeIds;
                      _followeeCategorySelections
                        ..clear()
                        ..addAll(tempFolloweeCategorySelections);
                      _followeeColorSelections
                        ..clear()
                        ..addAll(tempFolloweeColorSelections);
                    });
                    unawaited(_persistFilterSelections(
                      _selectedCategoryIds,
                      _selectedColorCategoryIds,
                      _selectedFolloweeIds,
                    ));
                    Navigator.of(context).pop(); // Close the dialog
                    _applyFiltersAndUpdateMarkers(); // Apply filters and update map
                  },
                ),
              ],
            ));
          },
        );
      },
    );
    dialogScrollController.dispose();
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
      final List<Experience> workingExperiences =
          List<Experience>.from(_experiences);
      if (_selectedFolloweeIds.isNotEmpty) {
        for (final followeeId in _selectedFolloweeIds) {
          final List<Experience>? followeeExperiences =
              _followeePublicExperiences[followeeId];
          if (followeeExperiences != null && followeeExperiences.isNotEmpty) {
            workingExperiences.addAll(followeeExperiences);
          }
        }
      }
      final Map<String, Experience> deduped = {
        for (final experience in workingExperiences) experience.id: experience
      };
      final filteredExperiences = _filterExperiences(deduped.values.toList());

      print(
          "🗺️ MAP SCREEN: Filtered ${deduped.length} experiences down to ${filteredExperiences.length}");

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
        _mapController!
            .animateCamera(CameraUpdate.newLatLngBounds(bounds, 50.0));
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

      final String? ownerId = experience.createdBy;
      final String? currentUserId = _authService.currentUser?.uid;
      final bool isFolloweeExperience =
          ownerId != null && ownerId.isNotEmpty && ownerId != currentUserId;

      UserCategory? resolvedCategory;
      final String? categoryId = experience.categoryId;
      if (categoryId != null && categoryId.isNotEmpty) {
        try {
          resolvedCategory =
              _categories.firstWhere((cat) => cat.id == categoryId);
        } catch (_) {
          if (ownerId != null &&
              ownerId.isNotEmpty &&
              _followeeCategories.containsKey(ownerId)) {
            resolvedCategory = _followeeCategories[ownerId]?[categoryId];
          }
        }
      }
      if (isFolloweeExperience &&
          !_canAccessFolloweeCategory(ownerId, categoryId)) {
        resolvedCategory = null;
      }

      final String iconText = _getCategoryIconForExperience(experience) ?? '❓';

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
          colorCategory = null; // Not found locally
          if (ownerId != null &&
              ownerId.isNotEmpty &&
              _followeeColorCategories.containsKey(ownerId)) {
            colorCategory =
                _followeeColorCategories[ownerId]?[experienceColorCategoryId];
          }
          // print(
          //     "🗺️ MAP SCREEN: No ColorCategory found matching ID '${experienceColorCategoryId}'. Using default color.");
        }
      } else {
        // print(
        //     "🗺️ MAP SCREEN: Experience '${experience.name}' has no colorCategoryId. Using default color.");
      }

      bool canUseColor = true;
      if (isFolloweeExperience &&
          experienceColorCategoryId != null &&
          experienceColorCategoryId.isNotEmpty &&
          !_canAccessFolloweeColorCategory(
              ownerId, experienceColorCategoryId)) {
        canUseColor = false;
        colorCategory = null;
      }

      // Determine marker background color (prefer denormalized color if present)
      Color markerBackgroundColor = Colors.grey; // Default
      if (canUseColor &&
          experience.colorHexDenorm != null &&
          experience.colorHexDenorm!.isNotEmpty) {
        markerBackgroundColor = _parseColor(experience.colorHexDenorm!);
      } else if (canUseColor &&
          colorCategory != null &&
          colorCategory.colorHex.isNotEmpty) {
        markerBackgroundColor = _parseColor(colorCategory.colorHex);
      }

      // Check if this experience is selected in select mode or add-to-event mode
      final int? selectModeIndex = _isSelectModeActive
          ? _getSelectModeDraftIndexForExperience(experience)
          : null;
      final int? addToEventIndex = _isAddToEventModeActive
          ? _getAddToEventDraftIndexForExperience(experience)
          : null;
      final bool isSelectedInDraft =
          selectModeIndex != null || addToEventIndex != null;
      final int? selectedIndex = selectModeIndex ?? addToEventIndex;
      final Color selectionColor =
          _isAddToEventModeActive && _activeEventViewMode != null
              ? _getEventColor(_activeEventViewMode!)
              : _selectModeColor;
      final int regularMarkerSizeKey = _markerSizeForPlatform(70);

      BitmapDescriptor categoryIconBitmap =
          BitmapDescriptor.defaultMarker; // Default

      if (isSelectedInDraft) {
        // Use numbered icon with selection color (more saturated)
        try {
          categoryIconBitmap = await _bitmapDescriptorFromNumberedIcon(
            number: selectedIndex! + 1, // 1-indexed position
            iconText: iconText,
            backgroundColor: selectionColor, // Use selection color
            size: 90, // Base size; scaled inside helper
          );
        } catch (e) {
          print(
              "🗺️ MAP SCREEN: Failed to generate numbered icon for selected experience: $e");
          // Fall back to regular icon generation
          final String cacheKey =
              '${iconText}_${markerBackgroundColor.value}_$regularMarkerSizeKey';
          if (_categoryIconCache.containsKey(cacheKey)) {
            categoryIconBitmap = _categoryIconCache[cacheKey]!;
          } else {
            categoryIconBitmap = await _bitmapDescriptorFromText(
              iconText,
              backgroundColor: markerBackgroundColor,
              size: 70, // Base size; scaled inside helper
            );
            _categoryIconCache[cacheKey] = categoryIconBitmap;
          }
        }
      } else {
        // Regular marker generation
        // Generate a unique cache key including the color and the *icon*
        final String cacheKey =
            '${iconText}_${markerBackgroundColor.value}_$regularMarkerSizeKey';

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
              iconText,
              backgroundColor: markerBackgroundColor,
              size: 70, // Base size; scaled inside helper
            );
            _categoryIconCache[cacheKey] =
                categoryIconBitmap; // Cache the result
          } catch (e) {
            print(
                "🗺️ MAP SCREEN: Failed to generate bitmap for icon '$cacheKey': $e");
            // Keep the default marker if generation fails
          }
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
        infoWindow: _infoWindowForPlatform('$iconText ${experience.name}'),
        icon: categoryIconBitmap,
        // MODIFIED: Experience marker onTap shows location details panel
        onTap: withHeavyTap(() async {
          triggerHeavyHaptic();
          FocusScope.of(context).unfocus(); // Unfocus search bar
          print(
              "🗺️ MAP SCREEN: Experience marker tapped for '${experience.name}'. Showing location details panel.");

          // --- REGENERATING ICON FOR SELECTED STATE ---
          final Color selectedMarkerBackgroundColor = markerBackgroundColor;

          final String selectedIconText =
              _getCategoryIconForExperience(experience) ?? '❓';
          final tappedMarkerId = MarkerId('selected_experience_location');
          final int animationToken = ++_markerAnimationToken;
          const int finalSize = 100;
          final int startSize = _markerStartSize(finalSize);
          Future<BitmapDescriptor> iconBuilder(int size) {
            return _bitmapDescriptorFromText(
              selectedIconText,
              backgroundColor: selectedMarkerBackgroundColor,
              size: size, // 125% of 70
              backgroundOpacity: 1.0, // Fully opaque
            );
          }
          // --- END ICON REGENERATION ---

          if (!mounted || animationToken != _markerAnimationToken) {
            return;
          }
          setState(() {
            _mapWidgetInitialLocation = experience.location;
            _tappedLocationDetails = experience.location;
            _tappedLocationMarker = null;
            _tappedExperience = experience; // Set associated experience
            _tappedExperienceCategory =
                resolvedCategory; // Set associated category
            _tappedLocationBusinessStatus = null; // Set business status
            _tappedLocationOpenNow = null; // Set open-now status
            _searchController.clear();
            _searchResults = [];
            _showSearchResults = false;
          });
          unawaited(_refreshBusinessStatus(
              experience.location.placeId, animationToken));
          if (!mounted || animationToken != _markerAnimationToken) {
            return;
          }
          final BitmapDescriptor firstIcon = await iconBuilder(startSize);
          if (!mounted || animationToken != _markerAnimationToken) {
            return;
          }
          setState(() {
            _tappedLocationMarker = _buildSelectedMarker(
              markerId: tappedMarkerId,
              position: position,
              infoWindowTitle: '$selectedIconText ${experience.name}',
              icon: firstIcon,
            );
          });
          unawaited(_animateSelectedMarkerSmooth(
            animationToken: animationToken,
            markerId: tappedMarkerId,
            position: position,
            infoWindowTitle: '$selectedIconText ${experience.name}',
            iconBuilder: iconBuilder,
            startSize: startSize,
            endSize: finalSize,
          ));
          _showMarkerInfoWindow(tappedMarkerId);
          unawaited(_prefetchExperienceMedia(experience));
        }),
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

  Future<void> _selectLocationOnMap(
    Location locationDetails, {
    bool fetchPlaceDetails = true,
    bool updateLoadingState = true,
    bool animateCamera = true,
    String markerId = 'selected_location',
  }) async {
    print(
        "🗺️ MAP SCREEN: _selectLocationOnMap invoked for ${locationDetails.displayName ?? locationDetails.address}");
    Location finalLocationDetails = locationDetails;

    if (fetchPlaceDetails &&
        locationDetails.placeId != null &&
        locationDetails.placeId!.isNotEmpty) {
      print(
          "🗺️ MAP SCREEN: Fetching detailed place info for ${locationDetails.placeId}");
      try {
        finalLocationDetails =
            await _mapsService.getPlaceDetails(locationDetails.placeId!);
        print(
            "🗺️ MAP SCREEN: Detailed place info fetched: ${finalLocationDetails.displayName}");
      } catch (e) {
        print(
            "🗺️ MAP SCREEN: Failed to fetch detailed place info: $e. Using provided data.");
      }
    } else {
      print("🗺️ MAP SCREEN: No placeId available; using provided location.");
    }

    String? businessStatus;
    bool? openNow;
    try {
      if (finalLocationDetails.placeId != null &&
          finalLocationDetails.placeId!.isNotEmpty) {
        final detailsMap = await _mapsService
            .fetchPlaceDetailsData(finalLocationDetails.placeId!);
        businessStatus = detailsMap?['businessStatus'] as String?;
        openNow = (detailsMap?['currentOpeningHours']?['openNow']) as bool?;
      }
    } catch (e) {
      print("🗺️ MAP SCREEN: Failed to fetch business status: $e");
      businessStatus = null;
      openNow = null;
    }

    final LatLng targetLatLng =
        LatLng(finalLocationDetails.latitude, finalLocationDetails.longitude);

    GoogleMapController currentMapController;
    if (_mapController != null) {
      currentMapController = _mapController!;
    } else {
      print(
          "🗺️ MAP SCREEN: Awaiting map controller before selecting location.");
      currentMapController = await _mapControllerCompleter.future;
      print("🗺️ MAP SCREEN: Map controller ready for selection.");
      _mapController = currentMapController;
    }

    if (animateCamera) {
      currentMapController.animateCamera(
        CameraUpdate.newLatLng(targetLatLng),
      );
    }

    final markerIdObj = MarkerId(markerId);
    final tappedMarker = Marker(
      markerId: markerIdObj,
      position: targetLatLng,
      infoWindow: _infoWindowForPlatform(finalLocationDetails.getPlaceName()),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
      zIndex: 1.0,
    );

    if (!mounted) return;

    setState(() {
      _mapWidgetInitialLocation = finalLocationDetails;
      _tappedLocationDetails = finalLocationDetails;
      _tappedLocationMarker = tappedMarker;
      _tappedExperience = null;
      _tappedExperienceCategory = null;
      _tappedLocationBusinessStatus = businessStatus;
      _tappedLocationOpenNow = openNow;
      if (updateLoadingState) {
        _isLoading = false;
      }
    });

    _maybeAttachSavedOrPublicExperience(finalLocationDetails);
    _showMarkerInfoWindow(markerIdObj);
  }

  // --- ADDED: Handle location selection from GoogleMapsWidget ---
  Future<void> _handleLocationSelected(Location locationDetails) async {
    FocusScope.of(context).unfocus(); // ADDED: Unfocus search bar
    print(
        "🗺️ MAP SCREEN: Location selected via widget callback: ${locationDetails.displayName}");

    print(
        "🗺️ MAP SCREEN: (_handleLocationSelected) Removing search listener before clearing text");
    _searchController.removeListener(_onSearchChanged);
    print(
        "🗺️ MAP SCREEN: (_handleLocationSelected) Listener removed. Clearing text next.");

    // Clear the search text. If listener was still active, this would trigger _onSearchChanged.
    _searchController.clear();
    print("🗺️ MAP SCREEN: (_handleLocationSelected) Text cleared.");

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        print(
            "🗺️ MAP SCREEN: (_handleLocationSelected POST-FRAME) Re-adding search listener.");
        _searchController.addListener(_onSearchChanged);
        print(
            "🗺️ MAP SCREEN: (_handleLocationSelected POST-FRAME) Search listener re-added.");
      } else {
        print(
            "🗺️ MAP SCREEN: (_handleLocationSelected POST-FRAME) NOT RUNNING because !mounted.");
      }
    });

    _isProgrammaticTextUpdate = false;

    // Show loading immediately for this operation
    if (mounted) {
      setState(() {
        _isLoading = true;
        _searchResults = [];
        _showSearchResults = false;
      });
    }

    try {
      await _selectLocationOnMap(locationDetails);
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

  // --- ADDED: Share selected experience ---
  Future<void> _shareSelectedExperience() async {
    if (!mounted || _tappedExperience == null) return;

    final Experience experience = _tappedExperience!;

    await showShareExperienceBottomSheet(
      context: context,
      onDirectShare: () => _directShareExperience(experience),
      onCreateLink: ({
        required String shareMode,
        required bool giveEditAccess,
      }) =>
          _createLinkShareForExperience(
        experience,
        shareMode: shareMode,
        giveEditAccess: giveEditAccess,
      ),
    );
  }

  Future<void> _directShareExperience(Experience experience) async {
    if (!mounted) return;
    final ExperienceShareService shareService = ExperienceShareService();
    final result = await showShareToFriendsModal(
      context: context,
      subjectLabel: experience.name,
      onSubmit: (recipientIds) async {
        return await shareService.createDirectShare(
          experience: experience,
          toUserIds: recipientIds,
        );
      },
      onSubmitToThreads: (threadIds) async {
        return await shareService.createDirectShareToThreads(
          experience: experience,
          threadIds: threadIds,
        );
      },
      onSubmitToNewGroupChat: (participantIds) async {
        return await shareService.createDirectShareToNewGroupChat(
          experience: experience,
          participantIds: participantIds,
        );
      },
    );
    if (!mounted) return;
    if (result != null) {
      showSharedWithFriendsSnackbar(context, result);
    }
  }

  Future<void> _createLinkShareForExperience(
    Experience experience, {
    required String shareMode,
    required bool giveEditAccess,
  }) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final ExperienceShareService shareService = ExperienceShareService();
    try {
      final DateTime expiresAt = DateTime.now().add(const Duration(days: 30));
      final String url = await shareService.createLinkShare(
        experience: experience,
        expiresAt: expiresAt,
        linkMode: shareMode,
        grantEdit: giveEditAccess,
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // Close the bottom sheet
      await Share.share('Check out this experience from Plendy! $url');
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Unable to generate a share link. Please try again.'),
          ),
        );
      }
    }
  }
  // --- END: Share selected experience ---

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
          orElse: () => UserCategory(
              id: '', name: 'Uncategorized', icon: '❓', ownerUserId: ''),
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
      print(
          "🗺️ MAP SCREEN: (_searchPlaces DEBOUNCED) Query: '$query', _isProgrammaticTextUpdate: $_isProgrammaticTextUpdate");

      if (_isProgrammaticTextUpdate) {
        // This path should ideally not be taken if _selectSearchResult resets the flag.
        // If it is taken, it means a search was triggered while the flag was still true.
        print(
            "🗺️ MAP SCREEN: (_searchPlaces) Safeguard: Detected _isProgrammaticTextUpdate = true. Suppressing search and resetting flag.");
        if (mounted) {
          setState(() {
            _isSearching =
                false; // Ensure _isSearching is false if this path is taken.
            _showSearchResults = false; // Ensure results list is hidden
          });
        }
        _isProgrammaticTextUpdate = false; // Reset immediately.
        print(
            "🗺️ MAP SCREEN: (_searchPlaces) Reset _isProgrammaticTextUpdate directly inside safeguard.");
        return;
      }

      if (query.isEmpty) {
        print(
            "🗺️ MAP SCREEN: (_searchPlaces DEBOUNCED) Query is empty. Clearing results.");
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
        print(
            "🗺️ MAP SCREEN: (_searchPlaces DEBOUNCED) Found ${experienceResults.length} matching user experiences for query: '$query'");

        // Then search Google Maps
        print(
            "🗺️ MAP SCREEN: (_searchPlaces DEBOUNCED) Calling _mapsService.searchPlaces for query: '$query'");
        final mapsResults = await _mapsService.searchPlaces(query);
        print(
            "🗺️ MAP SCREEN: (_searchPlaces DEBOUNCED) Received ${mapsResults.length} results from _mapsService for query: '$query'");

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
          final String nameA =
              (a['description'] ?? '').toString().toLowerCase();
          final String nameB =
              (b['description'] ?? '').toString().toLowerCase();
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
            if (name == currentQuery) {
              // Exact match
              score += 5000;
            } else if (name.startsWith(currentQuery)) {
              // Starts with
              score += 2000;
            } else if (name.contains(currentQuery)) {
              // Contains
              score += 1000;
            } else if (currentQuery.contains(name) && name.length > 3) {
              // Query contains name
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

          if (mapCenter != null &&
              latA != null &&
              lngA != null &&
              latB != null &&
              lngB != null) {
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
            print(
                "🗺️ MAP SCREEN: (_searchPlaces DEBOUNCED) setState: _showSearchResults: $_showSearchResults, _isSearching: $_isSearching, results count: ${_searchResults.length} (${experienceResults.length} experiences + ${mapsResults.length} places)");
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
    print(
        "🗺️ MAP SCREEN: (_selectSearchResult) Set _isProgrammaticTextUpdate = true");

    print(
        "🗺️ MAP SCREEN: (_selectSearchResult) Removing search listener before setting text");
    _searchController.removeListener(_onSearchChanged);
    print("🗺️ MAP SCREEN: (_selectSearchResult) Listener removed.");

    // Check if this is a user's saved experience
    if (result['type'] == 'experience') {
      print(
          "🗺️ MAP SCREEN: (_selectSearchResult) Selected result is a saved experience. Showing location details panel.");

      final Experience experience = result['experience'];
      final UserCategory category = result['category'];
      final LatLng targetLatLng =
          LatLng(experience.location.latitude, experience.location.longitude);

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
          final colorCategory = _colorCategories
              .firstWhere((cc) => cc.id == experience.colorCategoryId);
          markerBackgroundColor = _parseColor(colorCategory.colorHex);
        }
      } catch (e) {/* Use default grey color */}

      final String selectedIconText =
          _getCategoryIconForExperience(experience) ?? category.icon;
      final tappedMarkerId = MarkerId('selected_experience_location');
      final int animationToken = ++_markerAnimationToken;
      const int finalSize = 88;
      final int startSize = _markerStartSize(finalSize);
      Future<BitmapDescriptor> iconBuilder(int size) {
        return _bitmapDescriptorFromText(
          selectedIconText,
          backgroundColor: markerBackgroundColor,
          size: size, // 125% of 70
          backgroundOpacity: 1.0, // Fully opaque
        );
      }
      // --- END ICON REGENERATION ---

      // Set search text to experience name
      _searchController.text = experience.name;

      // Reset the flag immediately after the programmatic text update
      _isProgrammaticTextUpdate = false;
      print(
          "🗺️ MAP SCREEN: (_selectSearchResult) Reset _isProgrammaticTextUpdate = false for experience.");

      if (mounted) {
        setState(() {
          _mapWidgetInitialLocation = experience.location;
          _tappedLocationDetails = experience.location;
          _tappedLocationMarker = null;
          _tappedExperience = experience; // ADDED: Set associated experience
          _tappedExperienceCategory =
              category; // ADDED: Set associated category
          _tappedLocationBusinessStatus = null; // ADDED: Set business status
          _tappedLocationOpenNow = null; // ADDED: Set open-now status
          _isSearching = false;
          _showSearchResults = false;
        });
        unawaited(_refreshBusinessStatus(
          experience.location.placeId,
          animationToken,
        ));
        if (!mounted || animationToken != _markerAnimationToken) {
          return;
        }
        final BitmapDescriptor firstIcon = await iconBuilder(startSize);
        if (!mounted || animationToken != _markerAnimationToken) {
          return;
        }
        setState(() {
          _tappedLocationMarker = _buildSelectedMarker(
            markerId: tappedMarkerId,
            position: targetLatLng,
            infoWindowTitle: '${category.icon} ${experience.name}',
            icon: firstIcon,
          );
        });
        unawaited(_animateSelectedMarkerSmooth(
          animationToken: animationToken,
          markerId: tappedMarkerId,
          position: targetLatLng,
          infoWindowTitle: '${category.icon} ${experience.name}',
          iconBuilder: iconBuilder,
          startSize: startSize,
          endSize: finalSize,
        ));
        _showMarkerInfoWindow(tappedMarkerId);
      }
      unawaited(_prefetchExperienceMedia(experience));

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
        print(
            "🗺️ MAP SCREEN: (_selectSearchResult) Animating BEFORE setState to $targetLatLng");
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(targetLatLng, 16.0),
        );
      } else {
        print(
            "🗺️ MAP SCREEN: (_selectSearchResult) _mapController is NULL before animation. Animation might be delayed or rely on initial setup.");
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
        infoWindow: _infoWindowForPlatform(location.getPlaceName()),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        zIndex: 1.0,
      );

      print(
          '🗺️ MAP SCREEN: (_selectSearchResult) Before setting text, location is: ${location.getPlaceName()}');
      _searchController.text =
          location.displayName ?? location.address ?? 'Selected Location';

      // Reset the flag immediately after the programmatic text update & before listener is re-added.
      _isProgrammaticTextUpdate = false;
      print(
          "🗺️ MAP SCREEN: (_selectSearchResult) Reset _isProgrammaticTextUpdate = false (IMMEDIATELY after text set).");

      if (mounted) {
        print(
            '🗺️ MAP SCREEN: (_selectSearchResult) Setting state with new location details and map initial location.');
        setState(() {
          _mapWidgetInitialLocation =
              location; // Update map widget's initial location
          _tappedLocationDetails = location;
          _tappedLocationMarker = tappedMarker;
          _tappedExperience =
              null; // ADDED: Clear associated experience for Google Maps places
          _tappedExperienceCategory =
              null; // ADDED: Clear associated category for Google Maps places
          _tappedLocationBusinessStatus =
              businessStatus; // ADDED: Set business status
          _tappedLocationOpenNow = openNow; // ADDED: Set open-now status
          _isSearching = false;
          _showSearchResults = false;
        });
        print(
            '🗺️ MAP SCREEN: (_selectSearchResult) After setState, _tappedLocationDetails is: ${_tappedLocationDetails?.getPlaceName()} and _mapWidgetInitialLocation is: ${_mapWidgetInitialLocation?.getPlaceName()}');
        _maybeAttachSavedOrPublicExperience(location);
        _showMarkerInfoWindow(tappedMarkerId);
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
        if (mounted) {
          // Check mounted again inside callback
          print(
              "🗺️ MAP SCREEN: (_selectSearchResult POST-FRAME) Re-adding search listener.");
          // The flag should already be false here.
          // print("🗺️ MAP SCREEN: (_selectSearchResult) State of _isProgrammaticTextUpdate in post-frame: $_isProgrammaticTextUpdate");

          _searchController.addListener(_onSearchChanged);
          print(
              "🗺️ MAP SCREEN: (_selectSearchResult POST-FRAME) Search listener re-added.");
        } else {
          print(
              "🗺️ MAP SCREEN: (_selectSearchResult POST-FRAME) NOT RUNNING because !mounted.");
        }
      });
    }
  }
  // --- END Search functionality ---

  // ADDED: Separate method for onChanged to easily add/remove listener
  void _onSearchChanged() {
    print(
        "🗺️ MAP SCREEN: (_onSearchChanged) Text: '${_searchController.text}', _isProgrammaticTextUpdate: $_isProgrammaticTextUpdate");
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
    if (_tappedExperience == null ||
        _tappedExperience!.otherCategories.isEmpty) {
      return const SizedBox
          .shrink(); // Return empty space if no other categories
    }

    if (!_canDisplayFolloweeMetadata(_tappedExperience!)) {
      return const SizedBox
          .shrink(); // Return empty space if no other categories
    }

    // Get the full UserCategory objects from the IDs
    final String? ownerId = _tappedExperience!.createdBy;
    final otherCategoryObjects = _tappedExperience!.otherCategories
        .map((id) => _getAccessibleUserCategory(ownerId, id))
        .whereType<UserCategory>()
        .toList();

    if (otherCategoryObjects.isEmpty) {
      return const SizedBox.shrink();
    }

    // MODIFIED: Display as a Wrap of icons, without the header
    return Wrap(
      spacing: 8.0,
      runSpacing: 4.0,
      children: otherCategoryObjects.asMap().entries.map((entry) {
        final int index = entry.key;
        final UserCategory category = entry.value;

        // For the first item, wrap in SizedBox and center to align with primary icon
        if (index == 0) {
          return SizedBox(
            width: 24,
            child: Center(
              child: Text(
                category.icon,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return Text(
          category.icon,
          style: const TextStyle(fontSize: 16),
        );
      }).toList(),
    );
  }

  // ADDED: Helper to build the Color Category display
  Widget _buildColorCategoryWidget() {
    if (_tappedExperience == null) {
      return const SizedBox.shrink();
    }

    final experience = _tappedExperience!;
    if (!_canDisplayFolloweeMetadata(experience)) {
      return const SizedBox.shrink();
    }
    final String? ownerId = experience.createdBy;
    ColorCategory? primaryColorCategory =
        _getAccessibleColorCategory(ownerId, experience.colorCategoryId);

    final List<ColorCategory> otherColorCategories = experience
        .otherColorCategoryIds
        .map((id) => _getAccessibleColorCategory(ownerId, id))
        .whereType<ColorCategory>()
        .toList();

    if (primaryColorCategory == null && otherColorCategories.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<Widget> rowChildren = [];

    if (primaryColorCategory != null) {
      rowChildren.add(
        Container(
          padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
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
                  color: _parseColor(primaryColorCategory.colorHex),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade400, width: 0.5),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                primaryColorCategory.name,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    if (otherColorCategories.isNotEmpty) {
      if (rowChildren.isNotEmpty) {
        rowChildren.add(const SizedBox(width: 12));
      }
      rowChildren.addAll(
        otherColorCategories.map(
          (colorCategory) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3.0),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _parseColor(colorCategory.colorHex),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade400, width: 0.5),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: rowChildren,
    );
  }

  String _formatExperienceTitle({
    required String name,
    String? icon,
    bool allowPlaceholderStar = false,
  }) {
    final String trimmedIcon = icon?.trim() ?? '';
    if (trimmedIcon.isEmpty) {
      return name;
    }
    if (!allowPlaceholderStar && trimmedIcon == '*') {
      return name;
    }
    return '$trimmedIcon $name';
  }

  Widget _wrapWebPointerInterceptor(Widget child) {
    if (!kIsWeb) {
      return child;
    }
    return PointerInterceptor(child: child);
  }

  // Info windows are disabled across platforms.
  InfoWindow _infoWindowForPlatform(String title) {
    return InfoWindow.noText;
  }

  @override
  Widget build(BuildContext context) {
    print("🗺️ MAP SCREEN: Building widget. isLoading: $_isLoading");

    // Calculate keyboard height and adjust layout accordingly
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bool isKeyboardVisible = keyboardHeight > 0;
    final bool hasPublicFallback = _publicReadOnlyExperience != null;
    final int tappedExperienceMediaCount = _tappedExperience != null
        ? _getMediaCountForExperience(_tappedExperience!)
        : 0;
    final int publicExperienceMediaCount =
        hasPublicFallback ? _publicPreviewMediaItems?.length ?? 0 : 0;
    final int selectedMediaCount = _tappedExperience != null
        ? tappedExperienceMediaCount
        : publicExperienceMediaCount;
    final bool canPreviewContent = selectedMediaCount > 0;
    final bool showExperiencePrompt = _canOpenSelectedExperience;
    final bool showFilterButton = _authService.currentUser != null &&
        !(_authService.currentUser?.isAnonymous ?? false);
    final String selectedName = _tappedExperience != null
        ? _tappedExperience!.name
        : hasPublicFallback
            ? _publicReadOnlyExperience!.name
            : _tappedLocationDetails?.getPlaceName() ?? 'Selected Location';

    final String? selectedIcon = _tappedExperience != null
        ? _tappedExperienceCategory?.icon
        : hasPublicFallback
            ? _publicReadOnlyCategory.icon
            : null;

    final String selectedTitle = _tappedExperience != null
        ? _formatExperienceTitle(
            name: _tappedExperience!.name,
            icon: _tappedExperienceCategory?.icon,
          )
        : hasPublicFallback
            ? _formatExperienceTitle(
                name: _publicReadOnlyExperience!.name,
                icon: _publicReadOnlyCategory.icon,
              )
            : _tappedLocationDetails?.getPlaceName() ?? 'Selected Location';
    final String? selectedAdditionalNotes = (() {
      final notes = _tappedExperience?.additionalNotes?.trim();
      if (notes != null && notes.isNotEmpty) {
        return notes;
      }
      if (hasPublicFallback) {
        final publicNotes = _publicReadOnlyExperience?.additionalNotes?.trim();
        if (publicNotes != null && publicNotes.isNotEmpty) {
          return publicNotes;
        }
      }
      return null;
    })();

    // Combine experience markers and the tapped marker (if it exists)
    final Map<String, Marker> allMarkers = Map.from(_markers);

    // ADDED: Add public experience markers when globe is active
    if (_isGlobalToggleActive) {
      allMarkers.addAll(_publicExperienceMarkers);
      print(
          "🗺️ MAP SCREEN: Added ${_publicExperienceMarkers.length} public experience markers (globe active)");
    }

    // ADDED: Add event view markers when in event view mode
    if (_isEventViewModeActive) {
      allMarkers.addAll(_eventViewMarkers);
      print(
          "🗺️ MAP SCREEN: Added ${_eventViewMarkers.length} event view markers (event mode active)");
    }

    // ADDED: Add select mode event-only markers when in select mode
    if (_isSelectModeActive) {
      allMarkers.addAll(_selectModeEventOnlyMarkers);
      print(
          "🗺️ MAP SCREEN: Added ${_selectModeEventOnlyMarkers.length} select mode event-only markers");
    }

    // If an experience is currently tapped, remove its original marker from the map
    // so it can be replaced by the styled _tappedLocationMarker.
    if (_tappedExperience != null) {
      allMarkers.remove(_tappedExperience!.id);
      print(
          "🗺️ MAP SCREEN: Hiding original marker for '${_tappedExperience!.name}' to show selected marker.");
    }

    // If a public experience is currently tapped, remove its original marker from the map
    // so it can be replaced by the styled _tappedLocationMarker.
    if (_publicReadOnlyExperienceId != null && _isGlobalToggleActive) {
      allMarkers.remove(_publicReadOnlyExperienceId);
      print(
          "🗺️ MAP SCREEN: Hiding original public marker for '${_publicReadOnlyExperience?.name}' to show selected marker.");
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

    print(
        "🗺️ MAP SCREEN: (build) _tappedLocationDetails is: ${_tappedLocationDetails?.getPlaceName()}");
    print(
        "🗺️ MAP SCREEN: (build) Condition for BottomNav/Details Panel is: ${_tappedLocationDetails != null}");

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundColor,
        foregroundColor: Colors.black,
        elevation: 0,
        titleSpacing: 0,
        leading: (_isEventViewModeActive || _isAddToEventModeActive) &&
                widget.initialEvent != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () async {
                  triggerHeavyHaptic();
                  // If in add-to-event mode with changes, return the updated event
                  if (_isAddToEventModeActive &&
                      _addToEventDraftItinerary.isNotEmpty &&
                      _activeEventViewMode != null) {
                    final updatedEvent = _activeEventViewMode!.copyWith(
                      experiences: [
                        ..._activeEventViewMode!.experiences,
                        ..._addToEventDraftItinerary,
                      ],
                      updatedAt: DateTime.now(),
                    );
                    Navigator.of(context).pop(updatedEvent);
                  } else if (_activeEventViewMode != null) {
                    // Return the current event (might have been modified via remove)
                    Navigator.of(context).pop(_activeEventViewMode);
                  } else {
                    Navigator.of(context).pop();
                  }
                },
              )
            : null,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/icon/icon-cropped.png',
              height: 28,
            ),
            const SizedBox(width: 8),
            const Text('Plendy Map'),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: child,
              ),
              child: ((_isLoading ||
                          _isSharedLoading ||
                          _isGlobeLoading ||
                          _isCalendarDialogLoading) &&
                      !_isSearching)
                  ? SizedBox(
                      key: const ValueKey('appbar_spinner'),
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).primaryColor,
                      ),
                    )
                  : const SizedBox(
                      key: ValueKey('appbar_empty'),
                      width: 0,
                      height: 0,
                    ),
            ),
          ],
        ),
        actions: [
          Container(
            color: AppColors.backgroundColor,
            child: IconButton(
              icon: Icon(
                Icons.event_outlined,
                color: Colors.black,
              ),
              tooltip: 'Toggle calendar view',
              onPressed: () {
                triggerHeavyHaptic();
                _handleCalendarToggle();
              },
            ),
          ),
          Container(
            color: AppColors.backgroundColor,
            child: IconButton(
              icon: Icon(
                Icons.public,
                color: _isGlobalToggleActive ? Colors.black : Colors.grey,
              ),
              tooltip: 'Toggle global view',
              onPressed: () {
                triggerHeavyHaptic();
                _handleGlobeToggle();
              },
            ),
          ),
          if (showFilterButton)
            Container(
              color: AppColors.backgroundColor,
              child: IconButton(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.filter_list),
                    if (_hasActiveFilters)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.backgroundColor,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                tooltip: 'Filter Experiences',
                onPressed: () {
                  triggerHeavyHaptic();
                  print("🗺️ MAP SCREEN: Filter button pressed!");
                  setState(() {
                    _tappedLocationMarker = null;
                    _tappedLocationDetails = null;
                    _tappedExperience =
                        null; // ADDED: Clear associated experience
                    _tappedExperienceCategory =
                        null; // ADDED: Clear associated category
                    _tappedLocationBusinessStatus =
                        null; // ADDED: Clear business status
                    _tappedLocationOpenNow =
                        null; // ADDED: Clear open-now status
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
              color: AppColors.backgroundColor,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Card(
                  color: AppColors.backgroundColorDark,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25.0),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      enabled: !_isReturningFromNavigation,
                      decoration: InputDecoration(
                        hintText: 'Search for a place or address',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25.0),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25.0),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25.0),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: AppColors.backgroundColorDark,
                        prefixIcon: Icon(Icons.search,
                            color: Theme.of(context).primaryColor),
                        suffixIcon:
                            _isSearching // Show loading indicator in search bar
                                ? SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: Padding(
                                      padding: const EdgeInsets.all(4.0),
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  )
                                : _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(Icons.clear),
                                        onPressed: () {
                                          triggerHeavyHaptic();
                                          setState(() {
                                            _searchController.clear();
                                            _searchResults = [];
                                            _showSearchResults = false;
                                            // Clear tapped location when search is cleared
                                            _tappedLocationDetails = null;
                                            _tappedLocationMarker = null;
                                            _tappedExperience = null;
                                            _tappedExperienceCategory = null;
                                            _tappedLocationBusinessStatus =
                                                null;
                                            _tappedLocationOpenNow = null;
                                          });
                                        },
                                      )
                                    : null,
                      ),
                      onTap: withHeavyTap(() {
                        triggerHeavyHaptic();
                        // When search bar is tapped, clear any existing map-tapped location
                        // to avoid confusion if the user then selects from search results.
                        // However, don't clear if a search result was *just* selected.
                        // This is now handled in _searchPlaces (clears on new query) and _selectSearchResult.
                      }),
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
                      ? MediaQuery.of(context).size.height *
                          0.35 // More space when keyboard is up
                      : MediaQuery.of(context).size.height *
                          0.3, // Less space otherwise
                ),
                margin: EdgeInsets.symmetric(horizontal: 8.0),
                decoration: BoxDecoration(
                  color: AppColors.backgroundColor,
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
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    indent: 56,
                    endIndent: 16,
                    color: AppColors.backgroundColorMid,
                  ),
                  itemBuilder: (context, index) {
                    final result = _searchResults[index];
                    final bool isUserExperience =
                        result['type'] == 'experience';
                    final bool hasRating = result['rating'] != null;
                    final double rating =
                        hasRating ? (result['rating'] as double) : 0.0;
                    final String? address = result['address'] ??
                        (result['structured_formatting'] != null
                            ? result['structured_formatting']['secondary_text']
                            : null);

                    return Material(
                      color: AppColors.backgroundColor,
                      child: InkWell(
                        onTap: withHeavyTap(() {
                          triggerHeavyHaptic();
                          _selectSearchResult(result);
                        }),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: ListTile(
                            tileColor: AppColors.backgroundColor,
                            leading: CircleAvatar(
                              backgroundColor: isUserExperience
                                  ? Colors.green.withOpacity(0.1)
                                  : Theme.of(context)
                                      .primaryColor
                                      .withOpacity(0.1),
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
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                          color: Colors.green.withOpacity(0.3)),
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
            // --- END Search results ---

            // --- MODIFIED: Map now takes remaining space ---
            Expanded(
              child: Stack(
                children: [
                  GoogleMapsWidget(
                    initialLocation:
                        _mapWidgetInitialLocation, // Use the dynamic initial location
                    showUserLocation: true,
                    allowSelection: true,
                    onLocationSelected: _handleLocationSelected,
                    showControls: true,
                    mapToolbarEnabled: !_canOpenSelectedExperience &&
                        !_isEventViewModeActive &&
                        !_isAddToEventModeActive,
                    additionalMarkers: allMarkers,
                    onMapControllerCreated: _onMapWidgetCreated,
                  ),
                  // ADDED: Event view mode overlay
                  if (_isEventViewModeActive && _activeEventViewMode != null)
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: _wrapWebPointerInterceptor(
                        GestureDetector(
                          onTap: withHeavyTap(() async {
                            triggerHeavyHaptic();
                            // Fit camera to show all itinerary experiences
                            final positions = _eventViewMarkers.values
                                .map((marker) => marker.position)
                                .toList();
                            if (positions.isNotEmpty) {
                              await _fitCameraToBounds(positions);
                            }
                          }),
                          child: Container(
                            constraints: _isEventOverlayExpanded
                                ? BoxConstraints(
                                    maxHeight:
                                        MediaQuery.of(context).size.height *
                                            0.6,
                                  )
                                : const BoxConstraints(),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Header row
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 4,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: _getEventColor(
                                              _activeEventViewMode!),
                                          borderRadius:
                                              BorderRadius.circular(2),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _activeEventViewMode!
                                                      .title.isEmpty
                                                  ? 'Untitled Event'
                                                  : _activeEventViewMode!.title,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 16,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _isAddToEventModeActive
                                                  ? (() {
                                                      final existingCount =
                                                          _activeEventViewMode!
                                                              .experiences
                                                              .length;
                                                      final newCount =
                                                          _addToEventDraftItinerary
                                                              .length;
                                                      final totalCount =
                                                          existingCount +
                                                              newCount;
                                                      if (newCount == 0) {
                                                        return '$existingCount item${existingCount != 1 ? 's' : ''} • Tap to add more';
                                                      } else {
                                                        return '$totalCount item${totalCount != 1 ? 's' : ''} (+$newCount new)';
                                                      }
                                                    })()
                                                  : '${_eventViewMarkers.length} stop${_eventViewMarkers.length != 1 ? 's' : ''} on map',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // List icon button
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              onTap: withHeavyTap(() {
                                                triggerHeavyHaptic();
                                                setState(() {
                                                  _isEventOverlayExpanded =
                                                      !_isEventOverlayExpanded;
                                                });
                                              }),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: _getEventColor(
                                                    _activeEventViewMode!,
                                                  ).withOpacity(
                                                    _isEventOverlayExpanded
                                                        ? 0.8
                                                        : 0.6,
                                                  ),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.list,
                                                  size: 20,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            right: -4,
                                            bottom: -4,
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: BoxDecoration(
                                                color: _getEventColor(
                                                    _activeEventViewMode!),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Text(
                                                _isAddToEventModeActive
                                                    ? '${_activeEventViewMode!.experiences.length + _addToEventDraftItinerary.length}'
                                                    : '${_activeEventViewMode!.experiences.length}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      // Add experiences button (or finish button when in add mode)
                                      // Only show if user can edit the event
                                      if (_canEditEvent(
                                          _activeEventViewMode!)) ...[
                                        const SizedBox(width: 4),
                                        Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                onTap: withHeavyTap(() {
                                                  triggerHeavyHaptic();
                                                  if (_isAddToEventModeActive) {
                                                    _finishAddToEvent();
                                                  } else {
                                                    _enterAddToEventMode();
                                                  }
                                                }),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        _isAddToEventModeActive
                                                            ? Colors.green
                                                            : Theme.of(context)
                                                                .primaryColor,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(
                                                    _isAddToEventModeActive
                                                        ? Icons.check
                                                        : Icons.add,
                                                    size: 20,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if (_isAddToEventModeActive)
                                              Positioned(
                                                right: -4,
                                                bottom: -4,
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.all(4),
                                                  decoration: BoxDecoration(
                                                    color: _addToEventDraftItinerary
                                                            .isNotEmpty
                                                        ? Colors.red
                                                        : _getEventColor(
                                                            _activeEventViewMode!),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Text(
                                                    '${_addToEventDraftItinerary.length}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                      const SizedBox(width: 4),
                                      // Close button
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: withHeavyTap(() {
                                            triggerHeavyHaptic();
                                            _confirmExitEventViewMode();
                                          }),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.grey[100],
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.close,
                                              size: 20,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Expanded itinerary list
                                if (_isEventOverlayExpanded)
                                  Divider(height: 1, thickness: 1),
                                if (_isEventOverlayExpanded)
                                  Flexible(
                                    child: _buildEventItineraryList(),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  // ADDED: Select mode overlay (for creating new events)
                  if (_isSelectModeActive)
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: _wrapWebPointerInterceptor(
                        Container(
                          constraints: _isSelectModeOverlayExpanded
                              ? BoxConstraints(
                                  maxHeight:
                                      MediaQuery.of(context).size.height * 0.6,
                                )
                              : const BoxConstraints(),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Header row
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 4,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: _selectModeColor,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            'Select experiences',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 16,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _selectModeDraftItinerary.isEmpty
                                                ? 'Tap locations to add them'
                                                : '${_selectModeDraftItinerary.length} item${_selectModeDraftItinerary.length != 1 ? 's' : ''} selected',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // List icon button
                                    Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: withHeavyTap(() {
                                              triggerHeavyHaptic();
                                              setState(() {
                                                _isSelectModeOverlayExpanded =
                                                    !_isSelectModeOverlayExpanded;
                                              });
                                            }),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            child: Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: _selectModeColor.withOpacity(
                                                    _isSelectModeOverlayExpanded
                                                        ? 0.8
                                                        : 0.6),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.list,
                                                size: 20,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          right: -4,
                                          bottom: -4,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: _selectModeColor,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Text(
                                              '${_selectModeDraftItinerary.length}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 4),
                                    // Checkmark button
                                    Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: withHeavyTap(() {
                                              triggerHeavyHaptic();
                                              _finishSelectModeAndOpenEditor();
                                            }),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            child: Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .primaryColor,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.check,
                                                size: 20,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          right: -4,
                                          bottom: -4,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: _selectModeDraftItinerary
                                                      .isNotEmpty
                                                  ? Colors.red
                                                  : _selectModeColor,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Text(
                                              '${_selectModeDraftItinerary.length}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 4),
                                    // Close button
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: withHeavyTap(() {
                                          triggerHeavyHaptic();
                                          _confirmExitSelectMode();
                                        }),
                                        borderRadius: BorderRadius.circular(20),
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[100],
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            size: 20,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Expanded itinerary list
                              if (_isSelectModeOverlayExpanded)
                                const Divider(height: 1, thickness: 1),
                              if (_isSelectModeOverlayExpanded)
                                Flexible(
                                  child: _buildSelectModeItineraryList(),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // --- ADDED: Tapped Location Details Panel (moved from bottomNavigationBar) ---
                  // Wrapped in RepaintBoundary to isolate animation from rest of widget tree
                  RepaintBoundary(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 420),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        final offsetAnimation = Tween<Offset>(
                          begin: const Offset(0, 0.35),
                          end: Offset.zero,
                        ).animate(animation);
                        return SlideTransition(
                          position: offsetAnimation,
                          child:
                              FadeTransition(opacity: animation, child: child),
                        );
                      },
                      child: (_tappedLocationDetails != null &&
                              !isKeyboardVisible)
                          ? Align(
                              key: ValueKey(
                                _tappedExperience?.id ??
                                    _tappedLocationDetails?.placeId ??
                                    selectedTitle,
                              ),
                              alignment: Alignment.bottomCenter,
                              child: _wrapWebPointerInterceptor(
                                ConstrainedBox(
                                  constraints: kIsWeb
                                      ? const BoxConstraints(maxWidth: 480)
                                      : const BoxConstraints(),
                                  child: Container(
                                    padding: EdgeInsets.fromLTRB(
                                      16,
                                      16,
                                      16,
                                      2 +
                                          MediaQuery.of(context)
                                                  .padding
                                                  .bottom /
                                              2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.backgroundColor,
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(28),
                                        topRight: Radius.circular(28),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
                                          blurRadius: 8,
                                          offset: Offset(0,
                                              -3), // Shadow upwards as it's at the bottom of content
                                        ),
                                      ],
                                    ),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        // ADDED: Positioned "Tap to view" text at the very top
                                        if (showExperiencePrompt)
                                          Positioned(
                                            top:
                                                -12, // Move it further up, closer to the edge
                                            left: 0,
                                            right: 0,
                                            child: Center(
                                              child: Text(
                                                'Tap to view experience details',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[500],
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ),
                                          ),
                                        GestureDetector(
                                          onTap: withHeavyTap(showExperiencePrompt
                                              ? () {
                                                  triggerHeavyHaptic();
                                                  _handleTappedLocationNavigation();
                                                }
                                              : null),
                                          behavior: HitTestBehavior.translucent,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // ADDED: Add space at the top for the positioned text
                                              if (showExperiencePrompt)
                                                SizedBox(height: 12),
                                              // Only show "Selected Location" for non-experience locations
                                              if (!showExperiencePrompt) ...[
                                                Text(
                                                  'Selected Location',
                                                  style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.normal,
                                                    fontSize: 14,
                                                    color: Colors.grey[800],
                                                  ),
                                                ),
                                                SizedBox(height: 12),
                                              ],
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 4.0),
                                                      child: Row(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          if (selectedIcon !=
                                                                  null &&
                                                              selectedIcon
                                                                  .isNotEmpty &&
                                                              selectedIcon !=
                                                                  '*') ...[
                                                            SizedBox(
                                                              width: 24,
                                                              child: Center(
                                                                child: Text(
                                                                  selectedIcon,
                                                                  style:
                                                                      const TextStyle(
                                                                    fontSize:
                                                                        16,
                                                                  ),
                                                                  textAlign:
                                                                      TextAlign
                                                                          .center,
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                width: 4),
                                                          ],
                                                          Expanded(
                                                            child: Text(
                                                              selectedName,
                                                              style:
                                                                  const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                                fontSize: 16,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      // Share button - only show when experience is selected
                                                      if (_tappedExperience !=
                                                          null) ...[
                                                        const SizedBox(
                                                            width: 8),
                                                        IconButton(
                                                          onPressed: () {
                                                            triggerHeavyHaptic();
                                                            _shareSelectedExperience();
                                                          },
                                                          icon: const Icon(
                                                              Icons
                                                                  .share_outlined,
                                                              color:
                                                                  Colors.blue,
                                                              size: 28),
                                                          tooltip: 'Share',
                                                          padding:
                                                              EdgeInsets.zero,
                                                          constraints:
                                                              const BoxConstraints(),
                                                          style: IconButton
                                                              .styleFrom(
                                                            minimumSize:
                                                                Size.zero,
                                                            tapTargetSize:
                                                                MaterialTapTargetSize
                                                                    .shrinkWrap,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 12),
                                                      ],
                                                      IconButton(
                                                        onPressed: () {
                                                          triggerHeavyHaptic();
                                                          if (_tappedLocationDetails !=
                                                              null) {
                                                            _launchMapLocation(
                                                                _tappedLocationDetails!);
                                                          }
                                                        },
                                                        icon: Icon(
                                                            Icons.map_outlined,
                                                            color: Colors
                                                                .green[700],
                                                            size: 28),
                                                        tooltip:
                                                            'Open in map app',
                                                        padding:
                                                            EdgeInsets.zero,
                                                        constraints:
                                                            const BoxConstraints(),
                                                        style: IconButton
                                                            .styleFrom(
                                                          minimumSize:
                                                              Size.zero,
                                                          tapTargetSize:
                                                              MaterialTapTargetSize
                                                                  .shrinkWrap,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      IconButton(
                                                        onPressed: () {
                                                          triggerHeavyHaptic();
                                                          if (_tappedLocationDetails !=
                                                              null) {
                                                            _openDirectionsForLocation(
                                                                _tappedLocationDetails!);
                                                          }
                                                        },
                                                        icon: Icon(
                                                            Icons.directions,
                                                            color: Colors.blue,
                                                            size: 28),
                                                        tooltip:
                                                            'Get Directions',
                                                        padding:
                                                            EdgeInsets.zero,
                                                        constraints:
                                                            const BoxConstraints(),
                                                        style: IconButton
                                                            .styleFrom(
                                                          minimumSize:
                                                              Size.zero,
                                                          tapTargetSize:
                                                              MaterialTapTargetSize
                                                                  .shrinkWrap,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      IconButton(
                                                        onPressed: () {
                                                          triggerHeavyHaptic();
                                                          setState(() {
                                                            _tappedLocationMarker =
                                                                null;
                                                            _tappedLocationDetails =
                                                                null;
                                                            _tappedExperience =
                                                                null;
                                                            _tappedExperienceCategory =
                                                                null;
                                                            _tappedLocationBusinessStatus =
                                                                null;
                                                            _tappedLocationOpenNow =
                                                                null;
                                                          });
                                                        },
                                                        icon: Icon(Icons.close,
                                                            color: Colors
                                                                .grey[600],
                                                            size: 28),
                                                        tooltip: 'Close',
                                                        padding:
                                                            EdgeInsets.zero,
                                                        constraints:
                                                            const BoxConstraints(),
                                                        style: IconButton
                                                            .styleFrom(
                                                          minimumSize:
                                                              Size.zero,
                                                          tapTargetSize:
                                                              MaterialTapTargetSize
                                                                  .shrinkWrap,
                                                        ),
                                                      ),
                                                      if (kIsWeb)
                                                        const SizedBox(
                                                            width: 8),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              if (_tappedExperience !=
                                                  null) ...[
                                                if (_tappedExperience!
                                                    .otherCategories
                                                    .isNotEmpty) ...[
                                                  _buildOtherCategoriesWidget(),
                                                ],
                                                Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child:
                                                      _buildColorCategoryWidget(),
                                                ),
                                              ],
                                              const SizedBox(
                                                  height:
                                                      0), // Removed top padding
                                              if (_tappedLocationDetails!
                                                          .address !=
                                                      null &&
                                                  _tappedLocationDetails!
                                                      .address!.isNotEmpty) ...[
                                                Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        _tappedLocationDetails!
                                                            .address!,
                                                        style: TextStyle(
                                                            color: Colors
                                                                .grey[700]),
                                                      ),
                                                    ),
                                                    if (_tappedExperience !=
                                                            null ||
                                                        hasPublicFallback) ...[
                                                      const SizedBox(width: 12),
                                                      SizedBox(
                                                        width: 48,
                                                        height: 48,
                                                        child: OverflowBox(
                                                          minHeight: 48,
                                                          maxHeight: 48,
                                                          alignment:
                                                              Alignment.center,
                                                          child:
                                                              GestureDetector(
                                                            onTap: withHeavyTap(() {
                                                              triggerHeavyHaptic();
                                                              _onPlayExperienceContent();
                                                            }),
                                                            child:
                                                                AnimatedOpacity(
                                                              duration:
                                                                  const Duration(
                                                                      milliseconds:
                                                                          200),
                                                              opacity:
                                                                  canPreviewContent
                                                                      ? 1.0
                                                                      : 0.45,
                                                              child: Stack(
                                                                clipBehavior:
                                                                    Clip.none,
                                                                children: [
                                                                  Container(
                                                                    width: 48,
                                                                    height: 48,
                                                                    decoration:
                                                                        BoxDecoration(
                                                                      color: Theme.of(
                                                                              context)
                                                                          .primaryColor,
                                                                      shape: BoxShape
                                                                          .circle,
                                                                    ),
                                                                    child:
                                                                        const Icon(
                                                                      Icons
                                                                          .play_arrow,
                                                                      color: Colors
                                                                          .white,
                                                                      size: 24,
                                                                    ),
                                                                  ),
                                                                  Positioned(
                                                                    bottom: -2,
                                                                    right: -2,
                                                                    child:
                                                                        Container(
                                                                      width: 22,
                                                                      height:
                                                                          22,
                                                                      decoration:
                                                                          BoxDecoration(
                                                                        color: Colors
                                                                            .white,
                                                                        shape: BoxShape
                                                                            .circle,
                                                                        border:
                                                                            Border.all(
                                                                          color:
                                                                              Theme.of(context).primaryColor,
                                                                          width:
                                                                              2,
                                                                        ),
                                                                      ),
                                                                      child:
                                                                          Center(
                                                                        child:
                                                                            Text(
                                                                          selectedMediaCount
                                                                              .toString(),
                                                                          style:
                                                                              TextStyle(
                                                                            color:
                                                                                Theme.of(context).primaryColor,
                                                                            fontSize:
                                                                                12,
                                                                            fontWeight:
                                                                                FontWeight.w600,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                const SizedBox(height: 0),
                                              ],
                                              if (selectedAdditionalNotes !=
                                                  null) ...[
                                                Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Icon(
                                                      Icons.notes,
                                                      size: 18,
                                                      color: Colors.grey[700],
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        selectedAdditionalNotes,
                                                        style: TextStyle(
                                                          color:
                                                              Colors.grey[800],
                                                          fontStyle:
                                                              FontStyle.italic,
                                                        ),
                                                        maxLines: 3,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                              ],
                                              // ADDED: Star Rating
                                              if (_tappedLocationDetails!
                                                      .rating !=
                                                  null) ...[
                                                Row(
                                                  children: [
                                                    ...List.generate(5, (i) {
                                                      final ratingValue =
                                                          _tappedLocationDetails!
                                                              .rating!;
                                                      return Icon(
                                                        i < ratingValue.floor()
                                                            ? Icons.star
                                                            : (i < ratingValue)
                                                                ? Icons
                                                                    .star_half
                                                                : Icons
                                                                    .star_border,
                                                        size: 18,
                                                        color: Colors.amber,
                                                      );
                                                    }),
                                                    SizedBox(width: 8),
                                                    if (_tappedLocationDetails!
                                                                .userRatingCount !=
                                                            null &&
                                                        _tappedLocationDetails!
                                                                .userRatingCount! >
                                                            0)
                                                      Text(
                                                        '(${_tappedLocationDetails!.userRatingCount})',
                                                        style: TextStyle(
                                                          color:
                                                              Colors.grey[600],
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                                SizedBox(
                                                    height:
                                                        8), // Added SizedBox after rating like in location_picker_screen
                                              ],

                                              // ADDED: Business Status row below star rating
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Expanded(
                                                      child:
                                                          _buildBusinessStatusWidget()),
                                                ],
                                              ),

                                              // ADDED: Add/Remove button for event itinerary when in select mode or add-to-event mode
                                              // Only show for add-to-event mode if user can edit the event
                                              if ((_isSelectModeActive ||
                                                      (_isAddToEventModeActive &&
                                                          _activeEventViewMode !=
                                                              null &&
                                                          _canEditEvent(
                                                              _activeEventViewMode!))) &&
                                                  _tappedLocationDetails !=
                                                      null) ...[
                                                const SizedBox(height: 12),
                                                SizedBox(
                                                  width: double.infinity,
                                                  child: (() {
                                                    // Check if item is in itinerary (existing event or draft)
                                                    final bool
                                                        isInExistingEvent =
                                                        _isAddToEventModeActive &&
                                                            _isTappedItemInExistingEventItinerary();
                                                    final bool isInDraft =
                                                        _isTappedItemInDraftItinerary();
                                                    final bool isInItinerary =
                                                        isInExistingEvent ||
                                                            isInDraft;

                                                    return isInItinerary
                                                        ? ElevatedButton.icon(
                                                            onPressed: () {
                                                              triggerHeavyHaptic();
                                                              if (isInDraft) {
                                                                // Remove from draft
                                                                _removeTappedItemFromDraftItinerary();
                                                                ScaffoldMessenger.of(
                                                                        context)
                                                                    .showSnackBar(
                                                                  const SnackBar(
                                                                    content: Text(
                                                                        'Removed from itinerary'),
                                                                    duration: Duration(
                                                                        seconds:
                                                                            1),
                                                                  ),
                                                                );
                                                              } else if (isInExistingEvent) {
                                                                // Remove from existing event
                                                                _removeTappedItemFromEvent();
                                                              }
                                                            },
                                                            icon: const Icon(
                                                                Icons
                                                                    .remove_circle_outline,
                                                                size: 20),
                                                            label: const Text(
                                                                'Remove from event'),
                                                            style:
                                                                ElevatedButton
                                                                    .styleFrom(
                                                              backgroundColor:
                                                                  Colors.red
                                                                      .shade600,
                                                              foregroundColor:
                                                                  Colors.white,
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                      vertical:
                                                                          12),
                                                              shape:
                                                                  RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            8),
                                                              ),
                                                            ),
                                                          )
                                                        : ElevatedButton.icon(
                                                            onPressed: () {
                                                              triggerHeavyHaptic();
                                                              _handleSelectForEvent();
                                                            },
                                                            icon: const Icon(
                                                                Icons
                                                                    .add_circle_outline,
                                                                size: 20),
                                                            label: const Text(
                                                                'Add to Event'),
                                                            style:
                                                                ElevatedButton
                                                                    .styleFrom(
                                                              backgroundColor: _isAddToEventModeActive &&
                                                                      _activeEventViewMode !=
                                                                          null
                                                                  ? _getEventColor(
                                                                      _activeEventViewMode!)
                                                                  : _selectModeColor,
                                                              foregroundColor:
                                                                  Colors.white,
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                      vertical:
                                                                          12),
                                                              shape:
                                                                  RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            8),
                                                              ),
                                                            ),
                                                          );
                                                  })(),
                                                ),
                                              ],

                                              // ADDED: Add/Remove from event button when in event view mode (not in add-to-event or select mode)
                                              // Only show if user can edit the event
                                              if (_isEventViewModeActive &&
                                                  !_isAddToEventModeActive &&
                                                  !_isSelectModeActive &&
                                                  _tappedLocationDetails !=
                                                      null &&
                                                  _activeEventViewMode !=
                                                      null &&
                                                  _canEditEvent(
                                                      _activeEventViewMode!)) ...[
                                                const SizedBox(height: 12),
                                                SizedBox(
                                                  width: double.infinity,
                                                  child:
                                                      _isTappedItemInEventItinerary()
                                                          ? ElevatedButton.icon(
                                                              onPressed: () {
                                                                triggerHeavyHaptic();
                                                                _removeTappedItemFromEvent();
                                                              },
                                                              icon: const Icon(
                                                                  Icons
                                                                      .remove_circle_outline,
                                                                  size: 20),
                                                              label: const Text(
                                                                  'Remove from event'),
                                                              style:
                                                                  ElevatedButton
                                                                      .styleFrom(
                                                                backgroundColor:
                                                                    Colors.red
                                                                        .shade600,
                                                                foregroundColor:
                                                                    Colors
                                                                        .white,
                                                                padding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                        vertical:
                                                                            12),
                                                                shape:
                                                                    RoundedRectangleBorder(
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              8),
                                                                ),
                                                              ),
                                                            )
                                                          : ElevatedButton.icon(
                                                              onPressed: () {
                                                                triggerHeavyHaptic();
                                                                _addTappedItemToEvent();
                                                              },
                                                              icon: const Icon(
                                                                  Icons
                                                                      .add_circle_outline,
                                                                  size: 20),
                                                              label: const Text(
                                                                  'Add to event'),
                                                              style:
                                                                  ElevatedButton
                                                                      .styleFrom(
                                                                backgroundColor:
                                                                    _getEventColor(
                                                                        _activeEventViewMode!),
                                                                foregroundColor:
                                                                    Colors
                                                                        .white,
                                                                padding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                        vertical:
                                                                            12),
                                                                shape:
                                                                    RoundedRectangleBorder(
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              8),
                                                                ),
                                                              ),
                                                            ),
                                                ),
                                              ],

                                              const SizedBox(height: 0),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(
                              key: ValueKey('selected_location_sheet_empty'),
                            ),
                    ),
                  ),
                  // --- END Tapped Location Details ---
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
