import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import '../models/experience.dart';
import '../models/user_category.dart'; // Import UserCategory
// TODO: Import your PlaceDetails model and PlacesService
// import '../models/place_details.dart';
// ADDED: Import GoogleMapsService
import '../services/google_maps_service.dart';
import 'package:url_launcher/url_launcher.dart'; // ADDED: Import url_launcher
// TODO: Import Review/Comment models if needed for display
import '../models/review.dart';
import '../models/comment.dart';
import '../services/experience_service.dart'; // For fetching reviews/comments
// REMOVED: FontAwesome import (no longer needed for Yelp icon)
// import 'package:font_awesome_flutter/font_awesome_flutter.dart';
// RE-ADDED: Import Instagram Preview Widget
import 'receive_share/widgets/instagram_preview_widget.dart'
    as instagram_widget;
import 'receive_share/widgets/tiktok_preview_widget.dart';
import 'receive_share/widgets/facebook_preview_widget.dart';
import 'receive_share/widgets/youtube_preview_widget.dart';
import 'receive_share/widgets/generic_url_preview_widget.dart';
import 'receive_share/widgets/web_url_preview_widget.dart';
import 'receive_share/widgets/maps_preview_widget.dart';
import 'receive_share/widgets/yelp_preview_widget.dart';
// REMOVED: Dio import (no longer needed for thumbnail fetching)
// import 'package:dio/dio.dart';
// REMOVED: Dotenv import (no longer needed for credentials)
// import 'package:flutter_dotenv/flutter_dotenv.dart';
// ADDED: Import the new fullscreen screen
// UPDATED: Import the renamed widget
// ADDED: Import for FontAwesomeIcons
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
// ADDED: Import AuthService (adjust path if necessary)
import '../services/auth_service.dart';
// ADDED: Import the new edit modal (we will create this file next)
import '../widgets/edit_experience_modal.dart';
// ADDED: Import for SystemUiOverlayStyle
import 'package:flutter/services.dart';
import '../models/shared_media_item.dart'; // ADDED Import
import '../models/public_experience.dart';
// --- ADDED: Import ColorCategory ---
import '../models/color_category.dart';
// --- END ADDED ---
// --- ADDED --- Import collection package
import 'package:collection/collection.dart';
// --- END ADDED ---
import 'map_screen.dart'; // ADDED: Import for MapScreen
import 'main_screen.dart';
import 'package:flutter/foundation.dart'; // ADDED for kIsWeb
import 'package:webview_flutter/webview_flutter.dart';
import '../services/experience_share_service.dart'; // ADDED: Import ExperienceShareService
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_constants.dart';
import '../widgets/web_media_preview_card.dart'; // ADDED: Import for WebMediaPreviewCard
import '../widgets/share_experience_bottom_sheet.dart';
import '../widgets/save_to_experiences_modal.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/report.dart';
import '../services/report_service.dart';
import '../widgets/privacy_toggle_button.dart';
import '../models/event.dart';
import '../services/event_service.dart';
import 'package:intl/intl.dart';
import '../widgets/event_editor_modal.dart';

// Convert to StatefulWidget
class ExperiencePageScreen extends StatefulWidget {
  final Experience experience;
  final UserCategory category;
  final List<ColorCategory> userColorCategories;
  final List<UserCategory> additionalUserCategories;
  final List<SharedMediaItem>? initialMediaItems; // Optional media for previews
  final bool readOnlyPreview; // Hide actions when true
  final String?
      shareBannerFromUserId; // If provided, show overlay text in header
  // ADDED: Share preview metadata for dynamic messaging
  final String? sharePreviewType; // 'my_copy' | 'separate_copy'
  final String? shareAccessMode; // 'view' | 'edit'
  final bool focusMapOnPop; // When read-only from map, return focus payload
  final String? publicExperienceId; // Public experience reference when read-only

  const ExperiencePageScreen({
    super.key,
    required this.experience,
    required this.category,
    required this.userColorCategories,
    this.initialMediaItems,
    this.readOnlyPreview = false,
    this.shareBannerFromUserId,
    this.sharePreviewType,
    this.shareAccessMode,
    this.focusMapOnPop = false,
    this.publicExperienceId,
    this.additionalUserCategories = const <UserCategory>[],
  });

  @override
  State<ExperiencePageScreen> createState() => _ExperiencePageScreenState();
}

// ADDED: SingleTickerProviderStateMixin for TabController
class _ExperiencePageScreenState extends State<ExperiencePageScreen>
    with SingleTickerProviderStateMixin {
  // ADDED: Local state for the experience data
  late Experience _currentExperience;
  bool _isLoadingExperience = false; // Loading state for refresh
  // ADDED: Flag to indicate data change for popping result
  bool _didDataChange = false;

  // Place Details State
  bool _isLoadingDetails = true;
  String? _errorLoadingDetails;
  Map<String, dynamic>? _placeDetailsData;
  String? _headerPhotoUrl; // ADDED: State variable for header photo
  String? _shareBannerDisplayName; // Resolved sharer display name

  // ADDED: Helper to build DecorationImage using photo resource name with caching
  DecorationImage? _buildHeaderDecorationImage(Experience experience) {
    final String? resourceName = experience.location.photoResourceName;
    String? url;
    if (resourceName != null && resourceName.isNotEmpty) {
      url = GoogleMapsService.buildPlacePhotoUrlFromResourceName(
        resourceName,
        maxWidthPx: 800,
        maxHeightPx: 600,
      );
    }
    url ??= experience.location.photoUrl;
    if (url == null || url.isEmpty) return null;
    return DecorationImage(
      image: NetworkImage(url, headers: const {}),
      fit: BoxFit.cover,
    );
  }

  // Tab Controller State
  late TabController _tabController;
  bool _isLoadingReviews = true;
  bool _isLoadingComments = true;
  List<Review> _reviews = [];
  List<Comment> _comments = [];
  // TODO: Add state for comment count if fetching separately
  int _commentCount = 0; // Placeholder
  // ADDED: State for fetched media items
  bool _isLoadingMedia = true;
  List<SharedMediaItem> _mediaItems = [];
  bool _showingPublicMedia = false;
  bool _isLoadingPublicMedia = false;
  bool _hasAttemptedPublicMediaFetch = false;
  List<SharedMediaItem> _publicMediaItems = [];
  PublicExperience? _cachedReadOnlyPublicExperienceForMap;

  // Hours Expansion State
  bool _isHoursExpanded = false;

  // Services
  final _googleMapsService = GoogleMapsService();
  final _experienceService = ExperienceService(); // ADDED
  final ExperienceShareService _experienceShareService =
      ExperienceShareService();
  // ADDED: AuthService instance
  final _authService = AuthService();
  final ReportService _reportService = ReportService();
  // REMOVED: Dio instance
  // final _dio = Dio();

  // ADDED: State for current user ID and categories
  String? _currentUserId;
  bool _isLoadingAuth = true;
  List<UserCategory> _userCategories = [];
  bool _isLoadingCategories = false; // Separate loading for categories

  // --- ADDED: Scroll controller and status bar state ---
  late ScrollController _scrollController;
  bool _isStatusBarLight = true; // Start with light icons
  final double _headerHeight = 320.0; // Match the header height

  // --- ADDED: Track which media preview is expanded in the Content tab ---
  String? _expandedMediaPath;
  bool _isMediaPreviewHeightExpanded = false;
  static const double _contentPreviewDefaultHeight = 640.0;
  static const double _contentPreviewMaxExpandedHeight = 830.0;
  // --- END ADDED ---
  bool _isMediaShareInProgress = false;
  bool _isSaveSheetOpen = false;
  // --- ADDED: Maps preview futures cache for content tab ---
  final Map<String, Future<Map<String, dynamic>?>> _mapsPreviewFutures = {};
  // --- END ADDED ---
  // --- ADDED: Webview controllers for refresh ---
  final Map<String, WebViewController> _webViewControllers = {};
  final Map<String, GlobalKey<TikTokPreviewWidgetState>> _tiktokControllerKeys =
      {};
  final Map<String, GlobalKey<instagram_widget.InstagramWebViewState>>
      _instagramControllerKeys = {};
  final Map<String, GlobalKey<YouTubePreviewWidgetState>>
      _youtubeControllerKeys = {};
  // --- END ADDED ---

  // --- ADDED: State for other experiences linked to media --- START ---
  bool _isLoadingOtherExperiences = true;
  Map<String, List<Experience>> _otherAssociatedExperiences = {};
  Map<String, UserCategory> _fetchedCategoriesForMedia =
      {}; // Separate cache for media tab categories
  // --- ADDED: State for other experiences linked to media --- END ---

  // --- ADDED: State for event banner --- START ---
  bool _isLoadingEventBanner = true;
  Event? _matchingEvent;
  final EventService _eventService = EventService();
  // --- ADDED: State for event banner --- END ---

  static const Duration _photoRefreshInterval = Duration(days: 30);

  bool get _canShowPublicContentToggle {
    final String? placeId = _currentExperience.location.placeId;
    return !widget.readOnlyPreview && placeId != null && placeId.isNotEmpty;
  }

  // REMOVED: Instagram Credentials
  // String? _instagramAppId;
  // String? _instagramClientToken;

  // REMOVED: Thumbnail Cache
  // final Map<String, String?> _thumbnailCache = {};

  // --- ADDED: Helper to compute share preview category label ---
  String? _computeSharePreviewCategoryLabel() {
    if (!widget.readOnlyPreview) return null;
    final String sender = _shareBannerDisplayName ?? 'Someone';
    final String? type = widget.sharePreviewType; // 'my_copy' | 'separate_copy'
    final String? access = widget.shareAccessMode; // 'view' | 'edit'

    if (type == 'my_copy') {
      if (access == 'edit') {
        return '$sender wants to give you edit access to their experience';
      }
      return '$sender wants to give you view-only access to their experience';
    }
    if (type == 'separate_copy') {
      return 'Shared by $sender. Save the experience for yourself!';
    }
    return null;
  }

  // --- ADDED: Helper to get the current category based on experience's categoryId ---
  UserCategory _getCurrentCategory() {
    if (_currentExperience.categoryId == null) {
      // Fallback to widget.category if no categoryId
      return widget.category;
    }

    // Try to find the category from loaded user categories
    final category = _userCategories.firstWhereOrNull(
      (cat) => cat.id == _currentExperience.categoryId,
    );

    // Return found category or fallback to widget.category
    return category ?? widget.category;
  }

  bool _isLocationUnset(Experience experience) {
    final String? address = experience.location.address;
    if (address != null &&
        address.trim().toLowerCase() == 'no location specified') {
      return true;
    }
    final String? displayName = experience.location.displayName;
    if (displayName != null &&
        displayName.trim().toLowerCase() == 'no location specified') {
      return true;
    }
    return false;
  }

  bool _isPhotoRefreshDue(Location location) {
    final String? resourceName = location.photoResourceName;
    if (resourceName == null || resourceName.isEmpty) {
      return true;
    }
    final DateTime? lastSyncedAt = location.photoResourceLastSyncedAt;
    if (lastSyncedAt == null) {
      return true;
    }
    final DateTime nowUtc = DateTime.now().toUtc();
    final DateTime lastSyncUtc = lastSyncedAt.toUtc();
    return nowUtc.isAfter(lastSyncUtc.add(_photoRefreshInterval));
  }

  @override
  void initState() {
    super.initState();
    // Initialize local state with initial experience data
    _currentExperience = widget.experience;

    _tabController =
        TabController(length: 3, vsync: this); // Initialize TabController
    // REMOVED: Call to load Instagram credentials
    // _loadInstagramCredentials();

    // --- ADDED: Initialize ScrollController and add listener ---
    _scrollController = ScrollController();
    _scrollController.addListener(_scrollListener);
    // --- END ADDED ---

    _fetchPlaceDetails();
    _fetchReviews(); // Fetch reviews on init
    _fetchComments(); // Fetch comments on init
    _loadCurrentUserAndCategories(); // Fetch current user and categories
    // TODO: Fetch comment count if needed
    // If preview media were provided, use them and skip fetching
    if (widget.initialMediaItems != null) {
      _mediaItems = List<SharedMediaItem>.from(widget.initialMediaItems!);
      _expandedMediaPath =
          _mediaItems.isNotEmpty ? _mediaItems.first.path : null;
      _isMediaPreviewHeightExpanded = false;
      _isLoadingMedia = false;
      // Also kick off loading of other experience data based on provided media
      _loadOtherExperienceData();
    } else {
      _fetchMediaItems(); // ADDED: Fetch media items
    }

    // If this is a share preview with a fromUserId, resolve their display name
    if (widget.shareBannerFromUserId != null &&
        widget.shareBannerFromUserId!.isNotEmpty) {
      _resolveSharerDisplayName(widget.shareBannerFromUserId!);
    }

    // Fetch matching event for banner
    _fetchMatchingEvent();
  }

  void _navigateToMainScreen() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainScreen()),
      (route) => false,
    );
  }

  Future<bool> _handleBackNavigation() async {
    if (Navigator.of(context).canPop()) {
      if (widget.readOnlyPreview) {
        if (widget.focusMapOnPop) {
          Navigator.of(context).pop(_buildMapFocusPayload());
        } else {
          Navigator.of(context).pop();
        }
      } else {
        Navigator.of(context).pop(_didDataChange);
      }
    } else {
      _navigateToMainScreen();
    }
    return false;
  }

  Map<String, dynamic> _buildMapFocusPayload() {
    final Location location = widget.experience.location;
    final String fallbackId = widget.experience.id.isNotEmpty
        ? widget.experience.id
        : ((location.placeId != null && location.placeId!.isNotEmpty)
            ? location.placeId!
            : widget.experience.name);
    return {
      'focusExperienceId': fallbackId,
      'focusExperienceName': widget.experience.name,
      'latitude': location.latitude,
      'longitude': location.longitude,
      'placeId': location.placeId,
    };
  }

  Location _buildLocationForMapNavigation() {
    final Location location = _currentExperience.location;
    final String? displayName = location.displayName;
    if (displayName != null && displayName.trim().isNotEmpty) {
      return location;
    }
    final String fallbackName = _currentExperience.name.trim();
    if (fallbackName.isEmpty) {
      return location;
    }
    return location.copyWith(displayName: fallbackName);
  }

  List<String> _collectMediaPathsForPublicExperienceFallback() {
    Iterable<SharedMediaItem> sourceItems = const <SharedMediaItem>[];
    if (_mediaItems.isNotEmpty) {
      sourceItems = _mediaItems;
    } else if (_publicMediaItems.isNotEmpty) {
      sourceItems = _publicMediaItems;
    } else if (widget.initialMediaItems != null &&
        widget.initialMediaItems!.isNotEmpty) {
      sourceItems = widget.initialMediaItems!;
    }
    return sourceItems
        .map((item) => item.path.trim())
        .where((path) => path.isNotEmpty)
        .toList();
  }

  PublicExperience _buildFallbackPublicExperience(Location location) {
    final List<String> mediaPaths =
        _collectMediaPathsForPublicExperienceFallback();
    final String fallbackId = widget.publicExperienceId?.isNotEmpty == true
        ? widget.publicExperienceId!
        : (_currentExperience.location.placeId?.isNotEmpty == true
            ? _currentExperience.location.placeId!
            : _currentExperience.id);
    final String effectivePlaceId =
        location.placeId?.isNotEmpty == true ? location.placeId! : fallbackId;
    return PublicExperience(
      id: fallbackId,
      name: _currentExperience.name,
      location: location,
      placeID: effectivePlaceId,
      yelpUrl: _currentExperience.yelpUrl,
      website: _currentExperience.website,
      allMediaPaths: mediaPaths,
    );
  }

  Future<PublicExperience?> _resolvePublicExperienceForMap(
      Location location) async {
    if (!widget.readOnlyPreview) {
      return null;
    }
    if (_cachedReadOnlyPublicExperienceForMap != null) {
      return _cachedReadOnlyPublicExperienceForMap;
    }

    PublicExperience? publicExperience;
    try {
      final String? publicExperienceId = widget.publicExperienceId;
      if (publicExperienceId != null && publicExperienceId.isNotEmpty) {
        publicExperience =
            await _experienceService.findPublicExperienceById(
                publicExperienceId);
      }
      if (publicExperience == null) {
        final String? placeId = location.placeId;
        if (placeId != null && placeId.isNotEmpty) {
          publicExperience =
              await _experienceService.findPublicExperienceByPlaceId(placeId);
        }
      }
    } catch (e) {
      debugPrint(
          'ExperiencePageScreen: Error resolving public experience for map: $e');
    }

    publicExperience ??= _buildFallbackPublicExperience(location);
    _cachedReadOnlyPublicExperienceForMap = publicExperience;
    return publicExperience;
  }

  Future<void> _handleMapButtonPressed() async {
    final Location locationForMap = _buildLocationForMapNavigation();
    PublicExperience? publicExperience;
    if (widget.readOnlyPreview) {
      publicExperience = await _resolvePublicExperienceForMap(locationForMap);
      if (!mounted) return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MapScreen(
          initialExperienceLocation: locationForMap,
          initialPublicExperience: publicExperience,
        ),
      ),
    );
  }

  // --- ADDED: Scroll Listener ---
  void _scrollListener() {
    // Calculate a threshold. E.g., when header is mostly scrolled off.
    // Adjust kToolbarHeight based on actual visual needs.
    final threshold =
        _headerHeight - kToolbarHeight - MediaQuery.of(context).padding.top;
    final offset = _scrollController.offset;

    if (offset > threshold && _isStatusBarLight) {
      // Scrolled past threshold, need dark icons
      setState(() {
        _isStatusBarLight = false;
      });
    } else if (offset <= threshold && !_isStatusBarLight) {
      // Scrolled back up above threshold, need light icons
      setState(() {
        _isStatusBarLight = true;
      });
    }
  }
  // --- END ADDED ---

  @override
  void dispose() {
    _tabController.dispose(); // Dispose TabController
    // --- ADDED: Remove listener and dispose controller ---
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    // --- END ADDED ---
    super.dispose();
  }

  // REMOVED: Function to load Instagram credentials
  // void _loadInstagramCredentials() { ... }

  // Method to fetch place details
  Future<void> _fetchPlaceDetails() async {
    final placeId = _currentExperience.location.placeId;
    final Location originalLocation = _currentExperience.location;
    if (placeId == null || placeId.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoadingDetails = false;
          _errorLoadingDetails = null;
        });
      }
      return;
    }

    setState(() {
      _isLoadingDetails = true;
      _errorLoadingDetails = null;
    });

    try {
      final fetchedDetailsMap =
          await _googleMapsService.fetchPlaceDetailsData(placeId);

      if (mounted) {
        if (fetchedDetailsMap != null) {
          String?
              newConstructedPhotoUrl; // legacy immediate use (not persisted)
          String? newPhotoResourceName; // ADDED: persistable resource name

          // Try to get photo resource name from fetchedDetailsMap
          if (fetchedDetailsMap['photos'] != null &&
              fetchedDetailsMap['photos'] is List &&
              (fetchedDetailsMap['photos'] as List).isNotEmpty) {
            final photosList = fetchedDetailsMap['photos'] as List;
            final firstPhotoData = photosList.first as Map<String, dynamic>?;
            final String? photoResourceName =
                firstPhotoData?['name'] as String?;

            if (photoResourceName != null && photoResourceName.isNotEmpty) {
              newPhotoResourceName = photoResourceName; // store for persistence
              // Optionally build a transient URL for immediate UI use
              newConstructedPhotoUrl =
                  GoogleMapsService.buildPlacePhotoUrlFromResourceName(
                      photoResourceName,
                      maxWidthPx: 800,
                      maxHeightPx: 600);
              if (newConstructedPhotoUrl != null) {
                print(
                    "ExperiencePageScreen: Constructed transient photo URL: $newConstructedPhotoUrl");
              }
            } else {
              print(
                  "ExperiencePageScreen: No photo resource name found in fetched details.");
            }
          } else {
            print(
                "ExperiencePageScreen: No 'photos' array or empty in fetched details.");
          }

          final bool isPhotoRefreshDue = _isPhotoRefreshDue(originalLocation);
          final String? resolvedPhotoResourceName =
              (newPhotoResourceName != null && newPhotoResourceName.isNotEmpty)
                  ? newPhotoResourceName
                  : originalLocation.photoResourceName;
          final bool resourceNameChanged =
              resolvedPhotoResourceName != originalLocation.photoResourceName;
          final bool shouldPersistLocationUpdate =
              resourceNameChanged || isPhotoRefreshDue;
          final DateTime? nextSyncedAt =
              shouldPersistLocationUpdate ? DateTime.now().toUtc() : null;
          final Location? updatedLocation = shouldPersistLocationUpdate
              ? originalLocation.copyWith(
                  photoResourceName: resolvedPhotoResourceName,
                  photoResourceLastSyncedAt: nextSyncedAt,
                )
              : null;
          final Experience? updatedExperience = updatedLocation != null
              ? _currentExperience.copyWith(location: updatedLocation)
              : null;

          setState(() {
            _placeDetailsData = fetchedDetailsMap; // Store the raw details map

            if (kIsWeb) {
              _headerPhotoUrl = newConstructedPhotoUrl;
              if (newConstructedPhotoUrl != null) {
                print(
                    "ExperiencePageScreen: Updated transient _headerPhotoUrl (Web Specific) to: $newConstructedPhotoUrl");
              }
            }
            if (updatedExperience != null) {
              _currentExperience = updatedExperience;
              _didDataChange = true; // Signal that data changed for pop result
            }
            _isLoadingDetails = false;
          });

          if (!kIsWeb) {
            if (newConstructedPhotoUrl != null) {
              print(
                  "ExperiencePageScreen: Photo URL constructed ($newConstructedPhotoUrl) for non-web platform.");
            } else {
              print(
                  "ExperiencePageScreen: No new photo URL constructed for non-web platform.");
            }
          }

          if (updatedExperience != null && !widget.readOnlyPreview) {
            _experienceService.updateExperience(updatedExperience).then((_) {
              print(
                  "ExperiencePageScreen: Saved updated experience with refreshed photo metadata to Firestore.");
            }).catchError((e) {
              print(
                  "ExperiencePageScreen: Error saving updated experience to Firestore: $e");
            });
          }
        } else {
          setState(() {
            _isLoadingDetails = false;
            _errorLoadingDetails =
                'Failed to load place details. Please try again later.';
          });
        }
      }
    } catch (e) {
      print(
          'ExperiencePageScreen: Error in _fetchPlaceDetails for placeId $placeId: $e');
      if (mounted) {
        setState(() {
          _isLoadingDetails = false;
          _errorLoadingDetails =
              'Failed to load place details. Please try again later.';
        });
      }
    }
  }

  // ADDED: Method to fetch reviews
  Future<void> _fetchReviews() async {
    setState(() {
      _isLoadingReviews = true;
    });
    try {
      final reviews = await _experienceService
          .getReviewsForExperience(_currentExperience.id);
      if (mounted) {
        setState(() {
          _reviews = reviews;
          _isLoadingReviews = false;
        });
      }
    } catch (e) {
      print("Error fetching reviews: $e");
      if (mounted) {
        setState(() {
          _isLoadingReviews = false;
          // Optionally show error message in the tab
        });
      }
    }
  }

  // ADDED: Method to fetch comments
  Future<void> _fetchComments() async {
    setState(() {
      _isLoadingComments = true;
    });
    try {
      // Fetch only top-level comments for the count/list initially
      final comments = await _experienceService
          .getCommentsForExperience(_currentExperience.id);
      if (mounted) {
        setState(() {
          _comments = comments;
          _commentCount = comments.length; // Update count based on fetched list
          _isLoadingComments = false;
        });
      }
    } catch (e) {
      print("Error fetching comments: $e");
      if (mounted) {
        setState(() {
          _isLoadingComments = false;
          // Optionally show error message in the tab
        });
      }
    }
  }

  // REMOVED: Helper to fetch Instagram Thumbnail
  // Future<String?> _fetchInstagramThumbnailUrl(String reelUrl) async { ... }
  // --- END Instagram Thumbnail Helper ---

  // ADDED: Method to fetch current user ID and categories
  Future<void> _loadCurrentUserAndCategories() async {
    if (!mounted) return;
    setState(() {
      _isLoadingAuth = true;
      _isLoadingCategories = true;
    });
    try {
      final userId = _authService.currentUser?.uid;
      if (mounted) {
        setState(() {
          _currentUserId = userId;
          _isLoadingAuth = false;
        });
      }
    } catch (e) {
      print("Error getting current user ID: $e");
      if (mounted) {
        setState(() {
          _isLoadingAuth = false; // Stop loading even on error
        });
        // Optionally show error
      }
    }

    List<UserCategory> fetchedCategories = [];
    if (_currentUserId != null) {
      try {
        fetchedCategories = await _experienceService.getUserCategories(
          includeSharedEditable: true,
        );
      } catch (e) {
        print("Error loading user categories: $e");
      }
    }
    if (mounted) {
      setState(() {
        _userCategories =
            _mergeAdditionalUserCategories(fetchedCategories);
        _isLoadingCategories = false;
      });
    }
  }

  List<UserCategory> _mergeAdditionalUserCategories(
      List<UserCategory> baseCategories) {
    if (widget.additionalUserCategories.isEmpty) {
      return baseCategories;
    }
    final Map<String, UserCategory> merged = {
      for (final category in baseCategories) category.id: category,
    };
    for (final extra in widget.additionalUserCategories) {
      if (extra.id.isNotEmpty) {
        merged[extra.id] = extra;
      }
    }
    return merged.values.toList();
  }

  // ADDED: Helper to determine if the current user can edit
  bool _canEditExperience() {
    if (widget.readOnlyPreview) {
      return false;
    }
    if (_isLoadingAuth || _currentUserId == null) {
      return false; // Can't edit if loading or not logged in
    }
    if (_currentExperience.editorUserIds.contains(_currentUserId)) {
      return true;
    }
    final String? accessMode = widget.shareAccessMode?.toLowerCase();
    return accessMode == 'edit';
  }

  // ADDED: Method stub to show the edit modal
  Future<void> _showEditExperienceModal() async {
    if (!_canEditExperience() || _isLoadingCategories) {
      print(
          "Cannot edit: User doesn't have permission or categories not loaded.");
      return; // Prevent opening if not allowed or categories loading
    }

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final result = await showModalBottomSheet<Experience?>(
      context: context,
      isScrollControlled: true, // Important for keyboard handling
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        // Optional: Rounded corners
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        // Pass the current experience and loaded categories
        return EditExperienceModal(
          experience: _currentExperience,
          userCategories: _userCategories,
          userColorCategories: widget.userColorCategories, // ADD THIS LINE
          scaffoldMessenger: messenger,
        );
      },
    );

    // Handle the result from the modal
    if (result != null && mounted) {
      print("Edit modal returned updated experience. Saving...");

      // Optimistically update the local experience so UI reflects the edits immediately.
      // Note: We don't fetch from Firestore after this because:
      // 1. We already have the correct updated data from the modal
      // 2. Firestore cache might return stale data
      // 3. Parent screens will refresh when they receive _didDataChange = true
      final previousExperience = _currentExperience;
      setState(() {
        _currentExperience = result;
      });

      try {
        // Save the updated experience using the service
        await _experienceService.updateExperience(result);

        // Set flag for popping result so parent screens can refresh
        if (mounted) {
          setState(() {
            _didDataChange = true;
          });
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Experience updated successfully!')),
        );
      } catch (e) {
        print("Error saving updated experience: $e");
        if (mounted) {
          // Revert optimistic update on failure
          setState(() {
            _currentExperience = previousExperience;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving changes: $e')),
          );
        }
      }
    } else {
      print("Edit modal was cancelled or returned null.");
    }
  }

  // Helper method to build the header section (now uses widget.experience)
  Widget _buildHeader(BuildContext context, Experience experience) {
    // Determine header height (adjust as needed)
    const double headerHeight = 320.0;

    return SizedBox(
      height: headerHeight,
      child: Stack(
        children: [
          // 1. Background Image
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                image: _buildHeaderDecorationImage(experience),
                color: experience.location.photoUrl == null
                    ? Colors.grey[400] // Placeholder color if no image
                    : null,
              ),
              // Basic placeholder if no image URL
              child: experience.location.photoUrl == null
                  ? Center(
                      child: Icon(
                      Icons.image_not_supported,
                      color: Colors.white70,
                      size: 50,
                    ))
                  : null,
            ),
          ),

          // 2. Dark Overlay for text visibility
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withOpacity(0.6),
                    Colors.black.withOpacity(0.2),
                    Colors.transparent
                  ],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
            ),
          ),

          // --- ADDED: Top-center share banner text when in preview ---
          if (widget.readOnlyPreview &&
              _shareBannerDisplayName != null &&
              _shareBannerDisplayName!.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8.0,
              left: 64.0,
              right: 64.0,
              child: Center(
                child: Text(
                  _computeSharePreviewCategoryLabel() ??
                      '${_shareBannerDisplayName} wants you to check out this experience! Save it to create your own copy of the experience.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        offset: const Offset(1.0, 1.0),
                        blurRadius: 2.0,
                        color: Colors.black.withOpacity(0.5),
                      ),
                    ],
                  ),
                  softWrap: true,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

          // --- ADDED: Positioned Back Button ---
          // Show when not in read-only preview, or when opened from discovery screen
          // (discovery screen sets publicExperienceId, share preview sets shareBannerFromUserId)
          if (!widget.readOnlyPreview || widget.publicExperienceId != null || widget.shareBannerFromUserId != null)
            Positioned(
              // Position accounting for status bar height + padding
              top: MediaQuery.of(context).padding.top + 8.0,
              left: 8.0,
              child: Container(
                // Copied from SliverAppBar leading
                margin:
                    const EdgeInsets.all(0), // No margin needed when positioned
                decoration: BoxDecoration(
                  color: Colors.black
                      .withOpacity(0.4), // Slightly darker for visibility
                  shape: BoxShape.circle,
                ),
                child: BackButton(
                  color: Colors.white,
                  onPressed: () {
                    _handleBackNavigation();
                  },
                ),
              ),
            ),
          // --- END: Positioned Back Button ---

          // --- ADDED: Positioned Overflow Menu (3-dot) ---
          Positioned(
            top: MediaQuery.of(context).padding.top + 8.0,
            right: 8.0,
            child: Theme(
              data: Theme.of(context).copyWith(
                popupMenuTheme: const PopupMenuThemeData(color: Colors.white),
                canvasColor: Colors.white,
              ),
                child: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'report') {
                      _showReportDialog();
                    }
                    if (value == 'remove') {
                      _promptRemoveExperience();
                    }
                  },
                itemBuilder: (context) {
                  final bool canEdit = _canEditExperience();
                  final menuItems = <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'report',
                      child: Text('Report'),
                    ),
                  ];
                  if (canEdit) {
                    menuItems.add(
                      const PopupMenuItem<String>(
                        value: 'remove',
                        child: Text('Remove Experience'),
                      ),
                    );
                  }
                  return menuItems;
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(8.0),
                  child: const Icon(
                    Icons.more_vert,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          // --- END: Positioned Overflow Menu (3-dot) ---

          // 3. Content (Positioned to add padding)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                // Outer column to stack the top row and buttons
                crossAxisAlignment:
                    CrossAxisAlignment.start, // Align buttons left potentially
                children: [
                  Row(
                      // Main row for Icon + Name/Rating - REMOVED ICON
                      crossAxisAlignment: CrossAxisAlignment
                          .center, // Align items vertically center
                      children: [
                        // REMOVED CircleAvatar
                        // const SizedBox(width: 16), // REMOVED Spacing

                        // Column for Name and Rating
                        Expanded(
                          // Allow text column to take available space
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start, // Align text left
                            mainAxisSize:
                                MainAxisSize.min, // Fit content vertically
                            children: [
                              // Name
                              Text(
                                experience.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      offset: Offset(1.0, 1.0),
                                      blurRadius: 2.0,
                                      color: Colors.black.withOpacity(0.5),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),

                              // Rating
                              Row(
                                mainAxisAlignment: MainAxisAlignment
                                    .center, // Center the rating row
                                children: [
                                  RatingBarIndicator(
                                    rating: experience
                                        .plendyRating, // Use Plendy rating
                                    itemBuilder: (context, index) => const Icon(
                                      Icons.star,
                                      color: Colors.amber,
                                    ),
                                    unratedColor: Colors.white.withOpacity(0.7),
                                    itemCount: 5,
                                    itemSize: 24.0,
                                    direction: Axis.horizontal,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${experience.plendyReviewCount} ratings',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                      color: Colors.white,
                                      shadows: [
                                        Shadow(
                                          offset: Offset(1.0, 1.0),
                                          blurRadius: 2.0,
                                          color: Colors.black.withOpacity(0.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ]),
                  if (widget.readOnlyPreview) ...[
                    const SizedBox(height: 16), // Spacing below the top row

                    // Save button only shown in read-only experience view
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.center, // Center the buttons
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _handleSaveExperiencePressed(),
                          icon: const Icon(Icons.bookmark_outline),
                          label: const Text('Save Experience'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD40000),
                            foregroundColor: Colors.white,
                            // Optional: Add styling if needed (e.g., minimumSize)
                            minimumSize: Size(
                                140, 36), // Give buttons some minimum width
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
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator while refreshing experience data
    if (_isLoadingExperience) {
      return Scaffold(
        appBar: AppBar(), // Basic AppBar
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Calculate tab counts using the currently selected content source
    final bool isShowingPublicContent = _showingPublicMedia;
    final bool isMediaTabLoading =
        isShowingPublicContent ? _isLoadingPublicMedia : _isLoadingMedia;
    final List<SharedMediaItem> activeMediaItems =
        isShowingPublicContent ? _publicMediaItems : _mediaItems;
    final mediaCount =
        isMediaTabLoading ? '...' : activeMediaItems.length.toString();
    final reviewCount = _isLoadingReviews ? '...' : _reviews.length.toString();
    final commentCount = _isLoadingComments ? '...' : _commentCount.toString();

    // Prepare the tab bar once so we can use its preferred height
    final TabBar tabBar = TabBar(
      controller: _tabController,
      labelColor: Theme.of(context).primaryColor,
      unselectedLabelColor: Colors.grey[600],
      indicatorColor: Theme.of(context).primaryColor,
      tabs: [
        Tab(
          icon: Icon(Icons.photo_library_outlined),
          text: 'Content ($mediaCount)',
        ),
        Tab(
          icon: Icon(Icons.star_border_outlined),
          text: 'Reviews ($reviewCount)',
        ),
        Tab(
          icon: Icon(Icons.comment_outlined),
          text: 'Comments ($commentCount)',
        ),
      ],
    );

    // Wrap main Scaffold with WillPopScope
    return WillPopScope(
      onWillPop: _handleBackNavigation,
      child: Scaffold(
        backgroundColor: Colors.white,
        // No AppBar needed here anymore
        // appBar: AppBar(...),

        // The body is the NestedScrollView, wrapped with AnnotatedRegion
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          // Only control icon brightness based on scroll position
          value: _isStatusBarLight
              ? SystemUiOverlayStyle.light.copyWith(
                  // Use default transparent background
                  statusBarIconBrightness: Brightness.light,
                  statusBarBrightness: Brightness.dark, // For iOS
                )
              : SystemUiOverlayStyle.dark.copyWith(
                  // Use default transparent background
                  statusBarIconBrightness: Brightness.dark,
                  statusBarBrightness: Brightness.light, // For iOS
                ),
          child: NestedScrollView(
            // --- ADDED: Attach ScrollController ---
            controller: _scrollController,
            // --- END ADDED ---
            headerSliverBuilder:
                (BuildContext context, bool innerBoxIsScrolled) {
              // These are the slivers that show up in the "app bar" area.
              return <Widget>[
                // --- Header Section (remains the same) ---
                SliverToBoxAdapter(
                  child: _buildHeader(context, _currentExperience),
                ),
                // --- Event Banner ---
                if (!_isLoadingEventBanner && _matchingEvent != null)
                  SliverToBoxAdapter(
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
                      child: _buildEventBanner(context),
                    ),
                  ),
                // --- Details Section ---
                SliverToBoxAdapter(
                  child: Container(
                    color: Colors.white,
                    child: Column(
                      children: [
                        _buildDynamicDetailsSection(context),
                        const Divider(),
                        _buildQuickActionsSection(context, _placeDetailsData,
                            _currentExperience.location),
                        const Divider(),
                      ],
                    ),
                  ),
                ),
                // --- Sticky TabBar ---
                SliverPersistentHeader(
                  delegate: _SliverAppBarDelegate(
                    Container(
                      color: Colors.white,
                      child: tabBar,
                    ),
                    minHeight: tabBar.preferredSize.height,
                    maxHeight: tabBar.preferredSize.height,
                  ),
                  pinned: true, // Make the TabBar stick
                ),
              ];
            },
            // --- Body (TabBarView) ---
            body: TabBarView(
              controller: _tabController,
              children: [
                // Pass fetched media items to _buildMediaTab
                _buildMediaTab(context, activeMediaItems),
                _buildReviewsTab(context),
                _buildCommentsTab(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // New method to handle loading/error states for details section
  Widget _buildDynamicDetailsSection(BuildContext context) {
    if (_isLoadingDetails) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(32.0),
        child: CircularProgressIndicator(),
      ));
    }

    if (_errorLoadingDetails != null) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          _errorLoadingDetails!,
          style: TextStyle(color: Colors.red[700]),
          textAlign: TextAlign.center,
        ),
      ));
    }

    // If loaded successfully, build the details section with data
    return _buildDetailsSection(context, _currentExperience, _placeDetailsData);
  }

  // --- ADDED: Restore original _buildDetailRow --- START ---
  Widget _buildDetailRow(
      BuildContext context, IconData icon, String label, String? value,
      {bool showLabel = true}) {
    // Don't build row if value is null or empty
    if (value == null || value.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0), // Original padding
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20.0, color: Colors.black54),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium,
                children: <TextSpan>[
                  if (showLabel)
                    TextSpan(
                        text: '$label: ',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Description block
  Widget _buildDescriptionSection(
    BuildContext context, {
    String? description,
  }) {
    final bool hasDescription =
        description != null && description.trim().isNotEmpty;

    if (!hasDescription) return const SizedBox.shrink();

    final textTheme = Theme.of(context).textTheme.bodyMedium;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.description_outlined,
              size: 20.0, color: Colors.black54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description!.trim(),
                  style: textTheme,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesRow(BuildContext context, String notes) {
    final textTheme = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.notes, size: 20.0, color: Colors.black54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notes',
                  style: textTheme?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  notes,
                  style: textTheme?.copyWith(fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  // --- ADDED: Helper to build detail row with a leading WIDGET --- END ---

  // Helper method to build the details section (now accepts place details)
  Widget _buildDetailsSection(
      BuildContext context,
      Experience experience,
      Map<String, dynamic>? // TODO: Replace Map with your PlaceDetails model
          placeDetails) {
    // Helper to safely get data from the details map
    dynamic getDetail(String key) {
      // ADDED: Log what we are looking for and if the map exists
      // print(
      //     '  🔍 getDetail: Looking for key "$key". placeDetails is ${placeDetails == null ? 'NULL' : 'NOT NULL'}');

      if (placeDetails == null) return null;

      final value = placeDetails[key];
      // ADDED: Log the found value (or lack thereof)
      // print(
      //     '  🔍 getDetail: Found value for "$key": ${value == null ? 'NULL' : value.runtimeType}');

      // Basic check for nested text field (like editorialSummary)
      if (key == 'editorialSummary' &&
          value is Map &&
          value.containsKey('text')) {
        // print('  🔍 getDetail: Extracted text for editorialSummary');
        return value['text'] as String?;
      }

      // For other fields, return the raw value
      return value;
    }

    // Basic formatting for boolean reservable field
    String formatReservable(dynamic reservableValue) {
      // ADDED: Log input to formatter
      // print(
      //     '    🔄 formatReservable: Input value: $reservableValue (${reservableValue?.runtimeType})');
      if (reservableValue == null) {
        return 'Not specified'; // Changed from Not available
      }
      // Handle String 'true'/'false' in case toString() was used in getDetail
      if (reservableValue is String) {
        if (reservableValue.toLowerCase() == 'true') {
          return 'Takes reservations';
        }
        if (reservableValue.toLowerCase() == 'false') return 'No reservations';
      }
      if (reservableValue is bool) {
        return reservableValue ? 'Takes reservations' : 'No reservations';
      }
      // print('    ⚠️ formatReservable: Unexpected type, returning raw.');
      return reservableValue.toString(); // Fallback
    }

    // Removed legacy hours formatter; status/hours now handled in dedicated rows

    // Formatting for Parking
    String formatParking(dynamic parkingValue) {
      // ADDED: Log input to formatter
      // print(
      //     '    🔄 formatParking: Input value type: ${parkingValue?.runtimeType}');
      // Check if data is available and is a Map
      if (parkingValue == null || parkingValue is! Map) {
        // print('    ⚠️ formatParking: Input is null or not a Map.');
        return 'Not specified';
      }

      List<String> options = [];
      const parkingMap = {
        'freeParkingLots': 'Free lot parking',
        'paidParkingLots': 'Paid lot parking',
        'freeStreetParking': 'Free street parking',
        'paidStreetParking': 'Paid street parking',
        'valetParking': 'Valet parking',
        'freeGarageParking': 'Free garage parking',
        'paidGarageParking': 'Paid garage parking',
      };

      parkingMap.forEach((key, friendlyName) {
        if (parkingValue.containsKey(key) && parkingValue[key] == true) {
          options.add(friendlyName);
        }
      });

      if (options.isEmpty) {
        // print(
        //     '    ⚠️ formatParking: No specific parking options found in Map.');
        return 'Parking details not specified';
      }

      final result = options.join(', ');
      // print('    ✅ formatParking: Formatted result: $result');
      return result;
    }

    // Get formatted values to log them
    final formattedDescription = getDetail('editorialSummary');
    // Keep hours/status formatting via dedicated UI rows; avoid unused locals
    final formattedReservable = formatReservable(getDetail('reservable'));
    final formattedParking = formatParking(getDetail('parkingOptions'));

    // ADDED: Log formatted values before building UI
    // print('ℹ️ Building Details Section with Formatted Data:');
    // print('  - Description: $formattedDescription');
    // print('  - Hours: $formattedHours');
    // print('  - Status: $formattedStatus');
    // print('  - Reservable: $formattedReservable');
    // print('  - Parking: $formattedParking');

    // Determine if edit is allowed
    final bool canEdit = _canEditExperience();
    final bool hideLocationDetails = _isLocationUnset(experience);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Modified Category Row to include buttons on the right
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              children: [
                // Category Icon and Name (wrapped in Expanded)
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        _getCurrentCategory().icon,
                        style: const TextStyle(fontSize: 20),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _computeSharePreviewCategoryLabel() ??
                              _getCurrentCategory().name,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                color: Colors.black87,
                              ),
                          softWrap: true,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                // Buttons on the right
                // 1. Map Screen Button (View Location on App Map)
                ActionChip(
                  avatar: Image.asset(
                    'assets/icon/icon-cropped.png',
                    height: 18,
                  ),
                  label: const SizedBox.shrink(),
                  labelPadding: EdgeInsets.zero,
                  onPressed: () async {
                    await _handleMapButtonPressed();
                  },
                  tooltip: 'View Location on App Map', // Updated tooltip
                  backgroundColor: Colors.white,
                  shape: StadiumBorder(
                      side: BorderSide(color: Colors.grey.shade300)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.all(4),
                ),
                const SizedBox(width: 4), // Spacing

                // 2. Google Button (View on Google Maps)
                ActionChip(
                  avatar: Icon(
                    FontAwesomeIcons.google, // Google icon
                    color: const Color(0xFF4285F4), // Official Google Blue
                    size: 18,
                  ),
                  label: const SizedBox.shrink(),
                  labelPadding: EdgeInsets.zero,
                  onPressed: () =>
                      _launchMapLocation(_currentExperience.location),
                  tooltip: 'View on Map',
                  backgroundColor: Colors.white,
                  shape: StadiumBorder(
                      side: BorderSide(color: Colors.grey.shade300)),
                  materialTapTargetSize:
                      MaterialTapTargetSize.shrinkWrap, // Reduce tap area
                  padding: const EdgeInsets.all(4), // Adjust padding
                ),
                const SizedBox(width: 4), // Spacing

                // 3. Yelp Button (Icon Only)
                ActionChip(
                  avatar: const Icon(
                    FontAwesomeIcons.yelp,
                    color: Color(0xFFd32323), // Yelp Red
                    size: 18,
                  ),
                  label: const SizedBox.shrink(),
                  labelPadding: EdgeInsets.zero,
                  onPressed: _launchYelpSearch,
                  tooltip: 'Search on Yelp',
                  backgroundColor: Colors.white,
                  shape: StadiumBorder(
                      side: BorderSide(color: Colors.grey.shade300)),
                  materialTapTargetSize:
                      MaterialTapTargetSize.shrinkWrap, // Reduce tap area
                  padding: const EdgeInsets.all(4), // Adjust padding
                ),
                const SizedBox(width: 4), // Spacing

                // 4. Share Button
                ActionChip(
                  avatar: Icon(
                    Icons.share_outlined,
                    color: Colors.blue, // Or another appropriate color
                    size: 18,
                  ),
                  label: const SizedBox.shrink(),
                  labelPadding: EdgeInsets.zero,
                  onPressed: _showShareBottomSheet,
                  tooltip: 'Share Experience',
                  backgroundColor: Colors.white,
                  shape: StadiumBorder(
                      side: BorderSide(color: Colors.grey.shade300)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.all(4),
                ),
                if (!widget.readOnlyPreview) ...[
                  const SizedBox(width: 4), // Spacing

                  // 5. Edit Button
                  ActionChip(
                    avatar: Icon(
                      Icons.edit_outlined,
                      color: canEdit
                          ? Colors.orange[700]
                          : Colors.grey, // Dynamic color
                      size: 18,
                    ),
                    label: const SizedBox.shrink(),
                    labelPadding: EdgeInsets.zero,
                    // Call _showEditExperienceModal only if canEdit is true
                    onPressed: canEdit ? _showEditExperienceModal : null,
                    tooltip:
                        canEdit ? 'Edit Experience' : 'Cannot Edit (View Only)',
                    backgroundColor: Colors.white,
                    shape: StadiumBorder(
                        side: BorderSide(color: Colors.grey.shade300)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.all(4),
                  ),
                ],
              ],
            ),
          ),
          // --- ADDED: Color Category Row (Directly) --- START ---
          Builder(
            builder: (context) {
              if (_currentExperience.colorCategoryId == null) {
                return const SizedBox.shrink(); // No color category ID
              }
              final colorCategory = widget.userColorCategories.firstWhereOrNull(
                (cat) => cat.id == _currentExperience.colorCategoryId,
              );
              if (colorCategory == null) {
                print(
                    "Warning: ColorCategory object not found for ID: ${_currentExperience.colorCategoryId}");
                return const SizedBox.shrink(); // Category object not found
              }
              // Build the row directly here
              return Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: 6.0), // Reduced vertical padding further
                child: Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start, // Match _buildDetailRow
                  children: [
                    // --- MODIFIED: Use SizedBox + Center to mimic Icon space --- START ---
                    SizedBox(
                      width: 20.0, // Match Icon size used in _buildDetailRow
                      height: 20.0,
                      child: Center(
                        child: Container(
                          width: 14, // Smaller circle size
                          height: 14,
                          decoration: BoxDecoration(
                            color: colorCategory.color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                              width: 1,
                            ),
                          ),
                          child: Tooltip(
                              message:
                                  colorCategory.name), // Tooltip on the circle
                        ),
                      ),
                    ),
                    // --- MODIFIED: Use SizedBox + Center to mimic Icon space --- END ---
                    const SizedBox(width: 12), // Standard spacing
                    Expanded(
                      child: Text(
                        colorCategory.name,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          // --- ADDED: Color Category Row (Directly) --- END ---
          _buildDescriptionSection(
            context,
            description: formattedDescription,
          ),
          // Make the address row tappable
          if (!hideLocationDetails) ...[
            GestureDetector(
              onTap: () => _launchMapLocation(_currentExperience.location),
              child: _buildDetailRow(
                context,
                Icons.location_on_outlined,
                'Location',
                _currentExperience.location.address,
                showLabel: false, // HIDE label
              ),
            ),
            if ((_currentExperience.additionalNotes?.trim().isNotEmpty ?? false))
              _buildNotesRow(context, _currentExperience.additionalNotes!.trim()),
            _buildStatusRow(
              context,
              getDetail('businessStatus'),
              getDetail('currentOpeningHours'),
            ),
            _buildExpandableHoursRow(
              context,
              getDetail('regularOpeningHours'), // Weekly descriptions
              getDetail('businessStatus'), // For temporary/permanent closures
              getDetail('currentOpeningHours'), // For live open/closed
            ),
            _buildDetailRow(
              context,
              Icons.event_available_outlined,
              'Reservable',
              formattedReservable, // Use pre-formatted value
              showLabel: false, // HIDE label
            ),
            _buildDetailRow(
              context,
              Icons.local_parking_outlined,
              'Parking',
              formattedParking, // Use pre-formatted value
              showLabel: false, // HIDE label
            ),
          ],
          // --- ADDED: Other Categories Row ---
          _buildOtherCategoriesRow(context, _currentExperience),
          // --- END ADDED ---
        ],
      ),
    );
  }

  // --- ADDED: Helper Widget for Color Category Row --- START ---
  Widget _buildColorCategoryRow(BuildContext context, Experience experience) {
    if (experience.colorCategoryId == null) {
      return const SizedBox.shrink(); // Don't show row if no color category
    }

    // Find the color category object from the passed list
    final colorCategory = widget.userColorCategories.firstWhereOrNull(
      (cat) => cat.id == experience.colorCategoryId,
    );

    // Don't show if the category object wasn't found in the list
    if (colorCategory == null) {
      print(
          "Warning: ColorCategory object not found for ID: ${experience.colorCategoryId}");
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.center, // Center items vertically
        children: [
          // Color Circle
          Container(
            width: 14, // Smaller size
            height: 14,
            decoration: BoxDecoration(
              color: colorCategory.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Category Name
          Expanded(
            child: Text(
              colorCategory.name,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
  // --- ADDED: Helper Widget for Color Category Row --- END ---

  // --- ADDED: New Widget/Helper for Status Row ---
  Widget _buildStatusRow(
      BuildContext context, String? businessStatus, dynamic currentHours) {
    // Determine if permanently/temporarily closed first
    if (businessStatus == 'CLOSED_PERMANENTLY') {
      return _statusBadge(context, 'Closed Permanently', Colors.red[700]!);
    }
    if (businessStatus == 'CLOSED_TEMPORARILY') {
      return _statusBadge(context, 'Closed Temporarily', Colors.red[700]!);
    }

    // Otherwise treat as operational and use live open/closed if available
    bool? openNow;
    if (currentHours is Map && currentHours['openNow'] is bool) {
      openNow = currentHours['openNow'] as bool;
    }

    if (openNow == true) {
      return _statusBadge(context, 'Open now', Colors.green[700]!);
    }
    if (openNow == false) {
      return _statusBadge(context, 'Closed now', Colors.red[700]!);
    }

    // Unknown hours; if operational show neutral, else hide
    if (businessStatus == 'OPERATIONAL' || businessStatus == null) {
      return _statusBadge(context, 'Status unknown', Colors.grey);
    }

    return const SizedBox.shrink();
  }

  Widget _statusBadge(BuildContext context, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20.0, color: Colors.black54),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium,
                children: <TextSpan>[
                  TextSpan(
                    text: text,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  // --- End Status Row Widget ---

  // --- ADDED: New Widget for Expandable Hours ---
  Widget _buildExpandableHoursRow(BuildContext context, dynamic regularHours,
      String? businessStatus, dynamic currentHours) {
    // --- Helper Logic within the build method ---
    bool? openNow;
    if (currentHours is Map && currentHours['openNow'] is bool) {
      openNow = currentHours['openNow'] as bool;
    }
    final bool isTemporarilyOrPermanentlyClosed =
        businessStatus == 'CLOSED_TEMPORARILY' ||
            businessStatus == 'CLOSED_PERMANENTLY';
    final Color statusColor = isTemporarilyOrPermanentlyClosed
        ? Colors.red[700]!
        : (openNow == true
            ? Colors.green[700]!
            : (openNow == false ? Colors.red[700]! : Colors.grey));
    List<String>? descriptions;
    String todayString = 'Hours details unavailable';
    final now = DateTime.now(); // ADDED for debugging
    int currentWeekday = now.weekday; // MODIFIED to use `now`

    // Adjust to match Google's Monday-first format in weekdayDescriptions
    // Google API returns: [Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday]
    // So we need: Mon(1)→0, Tue(2)→1, ..., Sat(6)→5, Sun(7)→6
    int googleWeekdayIndex =
        (currentWeekday - 1); // Mon=0, Tue=1, ..., Sat=5, Sun=6

    // --- ADDED: Debug Prints ---
    print('--- DEBUG: Day Highlighting ---');
    print('Current DateTime from device: $now');
    print('Dart weekday from device (1=Mon, 7=Sun): $currentWeekday');
    print('Calculated Google Index (0=Mon, ..., 6=Sun): $googleWeekdayIndex');
    // --- END: Debug Prints ---

    if (regularHours is Map &&
        regularHours.containsKey('weekdayDescriptions') &&
        regularHours['weekdayDescriptions'] is List &&
        (regularHours['weekdayDescriptions'] as List).isNotEmpty) {
      descriptions =
          (regularHours['weekdayDescriptions'] as List).cast<String>();
      // --- ADDED: Debug Print for API data ---
      print('Weekday Descriptions from API: $descriptions');
      // --- END: Debug Print ---
      if (descriptions.length > googleWeekdayIndex) {
        todayString = descriptions[googleWeekdayIndex];
      } else {
        todayString = 'Today\'s hours unavailable'; // Data length mismatch
      }
    } else if (currentHours is Map &&
        currentHours.containsKey('openNow') &&
        currentHours['openNow'] is bool) {
      // Fallback if only openNow is available
      todayString = currentHours['openNow']
          ? 'Open now (details unavailable)'
          : 'Closed now (details unavailable)';
      descriptions = [todayString]; // Use this as the only description
    }
    // --- End Helper Logic ---

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Padding(
            padding: const EdgeInsets.only(top: 2.0), // Align icon better
            child: Icon(Icons.access_time_outlined,
                size: 20.0, color: Colors.black54),
          ),
          const SizedBox(width: 12),
          // Label and Hours
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Label
                Text(
                  'Hours: ',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 2), // Small space
                // Collapsed/Expanded Hours View
                if (!_isHoursExpanded || descriptions == null)
                  // Collapsed View or No descriptions
                  Text(
                    todayString,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.bold, // Bold today always
                        ),
                  )
                else
                  // Expanded View
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(descriptions.length, (index) {
                      bool isToday = index == googleWeekdayIndex;
                      return Text(
                        descriptions![index],
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight:
                                  isToday ? FontWeight.bold : FontWeight.normal,
                              color: isToday ? statusColor : null,
                            ),
                      );
                    }),
                  ),
              ],
            ),
          ),
          // Expand/Collapse Button (only show if there are descriptions)
          if (descriptions != null && descriptions.length > 1)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(),
              icon: Icon(
                _isHoursExpanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.black54,
              ),
              onPressed: () {
                setState(() {
                  _isHoursExpanded = !_isHoursExpanded;
                });
              },
            ),
        ],
      ),
    );
  }
  // --- End Expandable Hours Widget ---

  // --- ADDED: Tabbed Content Section Widgets ---

  Widget _buildTabbedContentSection(BuildContext context) {
    // Calculate counts
    final bool isPublicView = _showingPublicMedia;
    final bool isMediaLoading =
        isPublicView ? _isLoadingPublicMedia : _isLoadingMedia;
    final List<SharedMediaItem> effectiveMediaItems =
        isPublicView ? _publicMediaItems : _mediaItems;

    // Filter media paths for Instagram URLs to get the count
    final instagramMediaItems = effectiveMediaItems
        .where((item) => item.path.toLowerCase().contains('instagram.com'))
        .toList();
    final mediaCount =
        isMediaLoading ? '...' : instagramMediaItems.length.toString();
    final reviewCount = _isLoadingReviews
        ? '...'
        : _reviews.length.toString(); // Show loading indicator or count
    final commentCount = _isLoadingComments
        ? '...'
        : _commentCount.toString(); // Show loading indicator or count

    // Define a fixed height for the TabBarView content area
    const double tabContentHeight = 400.0; // Adjust as needed

    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: Theme.of(context).primaryColor,
            unselectedLabelColor: Colors.grey[600],
            indicatorColor: Theme.of(context).primaryColor,
            tabs: [
              Tab(
                // Use an Instagram icon or keep the generic one
                icon: Icon(Icons
                    .photo_library_outlined), // Or Icons.camera_alt_outlined etc.
                text: 'Media ($mediaCount)', // Updated count
              ),
              Tab(
                icon: Icon(Icons.star_border_outlined),
                text: 'Reviews ($reviewCount)',
              ),
              Tab(
                icon: Icon(Icons.comment_outlined),
                text: 'Comments ($commentCount)',
              ),
            ],
          ),
        ),
        SizedBox(
          height: tabContentHeight,
          child: TabBarView(
            controller: _tabController,
            children: [
              // Pass fetched media items
              _buildMediaTab(context, effectiveMediaItems),
              _buildReviewsTab(context),
              _buildCommentsTab(context),
            ],
          ),
        ),
      ],
    );
  }

  // ADDED: Function to handle media path deletion with confirmation
  Future<void> _deleteMediaPath(String urlToDelete) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        final primary = Theme.of(context).primaryColor;
        return AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Confirm Deletion'),
          content:
              const Text('Are you sure you want to remove this media item?'),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: <Widget>[
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: primary,
                side: BorderSide(color: primary),
                shape: const StadiumBorder(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    // Proceed only if confirmed (confirm == true)
    if (confirm == true) {
      try {
        // Find the media item ID corresponding to the URL
        // MODIFIED: Use try-catch instead of orElse for null safety
        SharedMediaItem? mediaItemToRemove;
        try {
          mediaItemToRemove =
              _mediaItems.firstWhere((item) => item.path == urlToDelete);
        } catch (e) {
          // Handle the case where no element is found (StateError)
          mediaItemToRemove = null;
        }

        if (mediaItemToRemove == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Error: Media item not found locally.')),
          );
          return; // Exit if not found locally
        }

        // Remove link using the service
        await _experienceService.removeExperienceLinkFromMediaItem(
            mediaItemToRemove.id, _currentExperience.id);
        print(
            "Removed link between experience ${_currentExperience.id} and media ${mediaItemToRemove.id}");

        // Refresh the local state (refetch experience AND media)
        await _refreshExperienceData(); // This should implicitly trigger _fetchMediaItems
        // Set flag to signal change on pop
        setState(() {
          _didDataChange = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Media item removed.')),
        );
      } catch (e) {
        print("Error deleting media path: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing media item: $e')),
        );
      }
    }
  }

  void _toggleMediaPreview(String mediaPath) {
    setState(() {
      if (_expandedMediaPath == mediaPath) {
        _expandedMediaPath = null;
      } else {
        _expandedMediaPath = mediaPath;
      }
      _isMediaPreviewHeightExpanded = false;
    });
  }

  void _toggleMediaPreviewHeight(String mediaPath) {
    setState(() {
      if (_expandedMediaPath != mediaPath) {
        _expandedMediaPath = mediaPath;
        _isMediaPreviewHeightExpanded = true;
      } else {
        _isMediaPreviewHeightExpanded = !_isMediaPreviewHeightExpanded;
      }
    });
  }

  double? _getMediaPreviewHeightOverride(
      BuildContext context, String mediaPath) {
    if (_expandedMediaPath != mediaPath || !_isMediaPreviewHeightExpanded) {
      return null;
    }
    return _calculateExpandedMediaPreviewHeight(context);
  }

  double _calculateExpandedMediaPreviewHeight(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double targetHeight = screenHeight * 1.5;
    final double clampedHeight = targetHeight.clamp(
      _contentPreviewDefaultHeight,
      _contentPreviewMaxExpandedHeight,
    );
    return clampedHeight.toDouble();
  }

  Widget _buildMediaPreviewToggleButton({
    required String mediaPath,
    required bool isExpanded,
  }) {
    return Tooltip(
      message: isExpanded ? 'Hide preview' : 'Show preview',
      child: CircleAvatar(
        radius: 18,
        backgroundColor: Colors.white,
        child: Icon(
          isExpanded ? Icons.stop : Icons.play_arrow,
          size: 20,
          color: Theme.of(context).primaryColor,
        ),
      ),
    );
  }

  // Builds the Media Tab, now including a fullscreen button
  Widget _buildMediaTab(
      BuildContext context, List<SharedMediaItem> mediaItems) {
    final bool isPublicView = _showingPublicMedia;
    final bool isActiveLoading =
        isPublicView ? _isLoadingPublicMedia : _isLoadingMedia;

    // Use the passed mediaItems list directly
    if (isActiveLoading) {
      return Container(
        color: Colors.white,
        child: const Center(child: CircularProgressIndicator()),
      );
    } else if (mediaItems.isEmpty) {
      return Container(
        color: Colors.white,
        child: Center(
          child: Text(isPublicView
              ? 'No public content available yet for this place.'
              : 'No media items shared for this experience.'),
        ),
      );
    }

    // Use a CustomScrollView so the filter row and media list can flex with the
    // outer NestedScrollView without causing layout overflows.
    return Container(
      color: Colors.white,
      child: CustomScrollView(
        slivers: [
          // --- MOVED Fullscreen Button to the top ---
          SliverPadding(
            padding: const EdgeInsets.only(top: 8.0, right: 16.0, left: 16.0),
            sliver: SliverToBoxAdapter(
              child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.filter_list,
                          size: 20.0, color: Colors.black),
                      label: const Text('Filter',
                          style: TextStyle(color: Colors.black)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                      onPressed: () {
                        // TODO: Implement Filter functionality
                      },
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.sort,
                          size: 20.0, color: Colors.black),
                      label: const Text('Sort',
                          style: TextStyle(color: Colors.black)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                      onPressed: () {
                        // TODO: Implement Sort functionality
                      },
                    ),
                    if (_canShowPublicContentToggle)
                      TextButton.icon(
                        icon: Icon(
                          isPublicView ? Icons.bookmark_outline : Icons.public,
                          size: 20.0,
                          color: Colors.black,
                        ),
                        label: Text(
                          isPublicView
                              ? 'Show Saved Content'
                              : 'Show Public Content',
                          style: const TextStyle(color: Colors.black),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                        onPressed: (_isLoadingPublicMedia && !isPublicView)
                            ? null
                            : _toggleContentSource,
                      ),
                  ],
                ),
              ),
            ),
          ),
          // --- END MOVED Button ---

          // Media list rendered as a sliver so it can flex with available height
          SliverPadding(
            padding: const EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                top: 8.0,
                bottom: 16.0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                // MODIFIED: Get SharedMediaItem and its path
                final item = mediaItems[index];
                final url = item.path;

                Widget? mediaWidget;
                final isTikTokUrl = url.toLowerCase().contains('tiktok.com') ||
                    url.toLowerCase().contains('vm.tiktok.com');
                final isInstagramUrl =
                    url.toLowerCase().contains('instagram.com');
                final isFacebookUrl =
                    url.toLowerCase().contains('facebook.com') ||
                        url.toLowerCase().contains('fb.com') ||
                        url.toLowerCase().contains('fb.watch');
                final isYouTubeUrl =
                    url.toLowerCase().contains('youtube.com') ||
                        url.toLowerCase().contains('youtu.be') ||
                        url.toLowerCase().contains('youtube.com/shorts');
                final isYelpUrl = url.toLowerCase().contains('yelp.com/biz') ||
                    url.toLowerCase().contains('yelp.to/');
                final bool isMapsUrl =
                    url.toLowerCase().contains('google.com/maps') ||
                        url.toLowerCase().contains('maps.app.goo.gl') ||
                        url.toLowerCase().contains('goo.gl/maps') ||
                        url.toLowerCase().contains('g.co/kgs/') ||
                        url.toLowerCase().contains('share.google/');
                final bool isNetworkUrl =
                    url.startsWith('http') || url.startsWith('https');
                final bool isGenericUrl = !isTikTokUrl &&
                    !isInstagramUrl &&
                    !isFacebookUrl &&
                    !isYouTubeUrl &&
                    !isYelpUrl &&
                    !isMapsUrl;
                final bool isExpanded = _expandedMediaPath == url;
                final bool isPreviewHeightExpanded =
                    isExpanded && _isMediaPreviewHeightExpanded;
                final double? previewHeightOverride =
                    _getMediaPreviewHeightOverride(context, url);
                final bool canEditMediaPrivacy =
                    !widget.readOnlyPreview &&
                        !_showingPublicMedia &&
                        item.id.isNotEmpty;

                if (isExpanded) {
                  if (isTikTokUrl) {
                    final key = _tiktokControllerKeys.putIfAbsent(
                      url,
                      () => GlobalKey<TikTokPreviewWidgetState>(),
                    );
                    mediaWidget = kIsWeb
                        ? WebMediaPreviewCard(
                            url: url,
                            experienceName: _currentExperience.name,
                            onOpenPressed: () => _launchUrl(url),
                          )
                        : TikTokPreviewWidget(
                            key: key,
                            url: url,
                            launchUrlCallback: _launchUrl,
                            showControls: false,
                            onWebViewCreated: (controller) {
                              _webViewControllers[url] = controller;
                            },
                          );
                  } else if (isInstagramUrl) {
                    final key = _instagramControllerKeys.putIfAbsent(
                      url,
                      () => GlobalKey<instagram_widget.InstagramWebViewState>(),
                    );
                    final double instagramHeight =
                        previewHeightOverride ?? 640.0;
                    mediaWidget = kIsWeb
                        ? WebMediaPreviewCard(
                            url: url,
                            experienceName: _currentExperience.name,
                            onOpenPressed: () => _launchUrl(url),
                          )
                        : instagram_widget.InstagramWebView(
                            key: key,
                            url: url,
                            height: instagramHeight,
                            launchUrlCallback: _launchUrl,
                            onWebViewCreated: (controller) {
                              _webViewControllers[url] = controller;
                            },
                            onPageFinished: (_) {},
                          );
                  } else if (isFacebookUrl) {
                    final double facebookHeight =
                        previewHeightOverride ?? 500.0;
                    mediaWidget = kIsWeb
                        ? WebMediaPreviewCard(
                            url: url,
                            experienceName: _currentExperience.name,
                            onOpenPressed: () => _launchUrl(url),
                          )
                        : FacebookPreviewWidget(
                            url: url,
                            height: facebookHeight,
                            launchUrlCallback: _launchUrl,
                            onWebViewCreated: (controller) {
                              _webViewControllers[url] = controller;
                            },
                            onPageFinished: (_) {},
                            showControls: false,
                          );
                  } else if (isYouTubeUrl) {
                    final key = _youtubeControllerKeys.putIfAbsent(
                      url,
                      () => GlobalKey<YouTubePreviewWidgetState>(),
                    );
                    mediaWidget = kIsWeb
                        ? WebMediaPreviewCard(
                            url: url,
                            experienceName: _currentExperience.name,
                            onOpenPressed: () => _launchUrl(url),
                          )
                        : YouTubePreviewWidget(
                            key: key,
                            url: url,
                            launchUrlCallback: _launchUrl,
                            showControls: false,
                            height: previewHeightOverride,
                            onWebViewCreated: (controller) {
                              _webViewControllers[url] = controller;
                            },
                          );
                  } else if (isNetworkUrl) {
                    final lowerUrl = url.toLowerCase();
                    if (lowerUrl.endsWith('.jpg') ||
                        lowerUrl.endsWith('.jpeg') ||
                        lowerUrl.endsWith('.png') ||
                        lowerUrl.endsWith('.gif') ||
                        lowerUrl.endsWith('.webp')) {
                      mediaWidget = Image.network(
                        url,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                              child: CircularProgressIndicator());
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey[200],
                            height: 200,
                            child: Center(
                                child: Icon(Icons.broken_image_outlined,
                                    color: Colors.grey[600], size: 40)),
                          );
                        },
                      );
                    } else if (isYelpUrl) {
                      mediaWidget = YelpPreviewWidget(
                        yelpUrl: url,
                        launchUrlCallback: _launchUrl,
                      );
                    } else if (isMapsUrl) {
                      if (!_mapsPreviewFutures.containsKey(url)) {
                        _mapsPreviewFutures[url] = Future.value({
                          'location': _currentExperience.location,
                          'placeName': _currentExperience.name,
                          'mapsUrl': url,
                          'website': _currentExperience.location.website,
                        });
                      }
                      mediaWidget = MapsPreviewWidget(
                        mapsUrl: url,
                        mapsPreviewFutures: _mapsPreviewFutures,
                        getLocationFromMapsUrl: (u) async => null,
                        launchUrlCallback: _launchUrl,
                        mapsService: _googleMapsService,
                      );
                    } else {
                      mediaWidget = GenericUrlPreviewWidget(
                        url: url,
                        launchUrlCallback: _launchUrl,
                      );
                    }
                  } else {
                    mediaWidget = Container(
                      height: 150,
                      color: Colors.grey[200],
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.description,
                                color: Colors.grey[600], size: 40),
                            const SizedBox(height: 8),
                            Text(
                              'Content Preview',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                } else {
                  mediaWidget = null;
                }

                // Keep the Column for layout *within* the list item
                final circleAvatar = CircleAvatar(
                  radius: 14,
                  backgroundColor:
                      Theme.of(context).primaryColor.withOpacity(0.8),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontSize: 14.0,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                );

                final Widget indexHeader = SizedBox(
                  height: 32,
                  width: double.infinity,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      circleAvatar,
                      if (canEditMediaPrivacy)
                        Positioned(
                          right: 0,
                          child: PrivacyToggleButton(
                            isPrivate: item.isPrivate,
                            showLabel: false,
                            onPressed: () => _toggleMediaItemPrivacy(item),
                          ),
                        ),
                    ],
                  ),
                );

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0), // Reduced from 24.0
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
                        child: indexHeader,
                      ),
                      Container(
                        margin: EdgeInsets.zero,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4.0),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4.0,
                              offset: const Offset(0, -2),
                            ),
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4.0,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _toggleMediaPreview(url),
                              child: Container(
                                color: Theme.of(context).primaryColor,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12.0, vertical: 8.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        url,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    _buildMediaPreviewToggleButton(
                                      mediaPath: url,
                                      isExpanded: isExpanded,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (isExpanded && mediaWidget != null) mediaWidget!,
                          ],
                        ),
                      ),
                      // --- ADDED: 'Also linked to' section --- START ---
                      Builder(
                        builder: (context) {
                          final otherExperiences =
                              _otherAssociatedExperiences[url] ?? [];
                          final bool shouldShowSection =
                              !_isLoadingOtherExperiences &&
                                  otherExperiences.isNotEmpty;

                          if (!shouldShowSection) {
                            return const SizedBox
                                .shrink(); // Don't show if not applicable
                          }

                          return Padding(
                            padding:
                                const EdgeInsets.only(top: 12.0, bottom: 4.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: 6.0,
                                      left: 4.0), // Indent slightly
                                  child: Text(
                                    otherExperiences.length == 1
                                        ? 'Also linked to:'
                                        : 'Also linked to (${otherExperiences.length}):',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                  ),
                                ),
                                // List the other experiences
                                ...otherExperiences.map((exp) {
                                  // final categoryName = exp.category; // OLD
                                  // Use the specific category cache for media tab, now keyed by ID
                                  final UserCategory? categoryForMediaItem =
                                      _fetchedCategoriesForMedia[
                                          exp.categoryId]; // NEW: Lookup by ID

                                  final categoryIcon =
                                      categoryForMediaItem?.icon ?? '❓';
                                  final categoryName =
                                      categoryForMediaItem?.name ??
                                          'Uncategorized';

                                  final address = exp.location.address;
                                  final bool hasAddress =
                                      address != null && address.isNotEmpty;

                                  return Padding(
                                    padding: const EdgeInsets.only(
                                        bottom: 4.0,
                                        left: 4.0), // Indent slightly
                                    child: InkWell(
                                      onTap: () async {
                                        print(
                                            'Tapped on other experience ${exp.name} from exp page tab');
                                        // final category = // OLD
                                        //     _fetchedCategoriesForMedia[
                                        //             categoryName] ??
                                        //         UserCategory(
                                        //             id: '',
                                        //             name: categoryName,
                                        //             icon: '❓',
                                        //             ownerUserId: '');
                                        final UserCategory
                                            categoryForNavigation =
                                            _fetchedCategoriesForMedia[exp
                                                    .categoryId] ?? // NEW: Lookup by ID
                                                UserCategory(
                                                    id: exp.categoryId ??
                                                        '', // Use the ID if available for fallback
                                                    name: 'Uncategorized',
                                                    icon: '❓',
                                                    ownerUserId: '');

                                        final result =
                                            await Navigator.push<bool>(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                ExperiencePageScreen(
                                              experience: exp,
                                              category: categoryForNavigation,
                                              userColorCategories:
                                                  widget.userColorCategories,
                                            ),
                                          ),
                                        );
                                        // If navigation might cause changes relevant here, refresh
                                        if (result == true && mounted) {
                                          // Decide what needs refreshing - maybe just the other experience data?
                                          _loadOtherExperienceData();
                                          // Or maybe the whole page?
                                          // _refreshExperienceData();
                                        }
                                      },
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                right: 8.0, top: 2.0),
                                            child: Text(categoryIcon,
                                                style: TextStyle(fontSize: 14)),
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  exp.name,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall
                                                      ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w500),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  maxLines: 1,
                                                ),
                                                if (hasAddress)
                                                  Text(
                                                    address,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                            color:
                                                                Colors.black54),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    maxLines: 1,
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          );
                        },
                      ),
                      // --- ADDED: 'Also linked to' section --- END ---

                      const SizedBox(height: 4), // Reduced from 8
                      SizedBox(
                        height: 40, // Reduced from 48
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Refresh Button
                            if (!isGenericUrl)
                              IconButton(
                                icon: const Icon(Icons.refresh),
                                iconSize: 24,
                                color: Colors.blue,
                                tooltip: 'Refresh Preview',
                                onPressed: () {
                                  if (isTikTokUrl) {
                                    _tiktokControllerKeys[url]
                                        ?.currentState
                                        ?.refreshWebView();
                                  } else if (isInstagramUrl) {
                                    _instagramControllerKeys[url]
                                        ?.currentState
                                        ?.refresh();
                                  } else if (isYouTubeUrl) {
                                    _youtubeControllerKeys[url]
                                        ?.currentState
                                        ?.refreshWebView();
                                  } else if (_webViewControllers
                                      .containsKey(url)) {
                                    _webViewControllers[url]!.reload();
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'Cannot refresh this item.')));
                                  }
                                },
                              ),
                            // Share Button
                            IconButton(
                              icon: const Icon(Icons.share_outlined),
                              iconSize: 24,
                              color:
                                  Colors.blue, // Use blue like expand/collapse
                              tooltip:
                                  'Share Media', // Tooltip for the new button
                              onPressed: _isMediaShareInProgress
                                  ? null
                                  : () => _handleMediaShareButtonPressed(item),
                            ),
                            // Open in App button
                            IconButton(
                              icon: Icon(
                                isInstagramUrl
                                    ? FontAwesomeIcons.instagram
                                    : isFacebookUrl
                                        ? FontAwesomeIcons.facebook
                                        : isTikTokUrl
                                            ? FontAwesomeIcons.tiktok
                                            : isYouTubeUrl
                                                ? FontAwesomeIcons.youtube
                                                : isMapsUrl
                                                    ? FontAwesomeIcons.google
                                                    : Icons.open_in_new,
                              ),
                              color: isInstagramUrl
                                  ? const Color(0xFFE1306C)
                                  : isFacebookUrl
                                      ? const Color(0xFF1877F2)
                                      : isTikTokUrl
                                          ? Colors.black
                                          : isYouTubeUrl
                                              ? Colors.red
                                              : isMapsUrl
                                                  ? const Color(0xFF4285F4)
                                                  : Theme.of(context)
                                                      .primaryColor,
                              iconSize: 32,
                              tooltip: isInstagramUrl
                                  ? 'Open in Instagram'
                                  : isFacebookUrl
                                      ? 'Open in Facebook'
                                      : isTikTokUrl
                                          ? 'Open in TikTok'
                                          : isYouTubeUrl
                                              ? 'Open in YouTube'
                                              : isMapsUrl
                                                  ? 'Open in Google Maps'
                                                  : 'Open URL',
                              onPressed: () => _launchUrl(url),
                            ),
                            IconButton(
                              icon: Icon(isPreviewHeightExpanded
                                  ? Icons.fullscreen_exit
                                  : Icons.fullscreen),
                              iconSize: 24,
                              color: Colors.blue,
                              tooltip: isPreviewHeightExpanded
                                  ? 'Collapse preview'
                                  : 'Expand preview',
                              onPressed: () => _toggleMediaPreviewHeight(url),
                            ),
                            if (!widget.readOnlyPreview && !isPublicView)
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                iconSize: 24,
                                color: Colors.red[700],
                                tooltip: 'Delete Media',
                                onPressed: () => _deleteMediaPath(url),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
              childCount: mediaItems.length,
            ),
          ),
        ),
        ],
      ),
    );
  }

  // Builds the Reviews Tab ListView
  Widget _buildReviewsTab(BuildContext context) {
    if (_isLoadingReviews) {
      return Container(
        color: Colors.white,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_reviews.isEmpty) {
      return Container(
        color: Colors.white,
        child: const Center(child: Text('No reviews yet.')),
      );
    }

    return Container(
      color: Colors.white,
      child: ListView.builder(
        itemCount: _reviews.length,
        itemBuilder: (context, index) {
          final review = _reviews[index];
          // TODO: Create a proper ReviewListItem widget
          return ListTile(
            leading:
                CircleAvatar(child: Text(review.rating.toStringAsFixed(1))),
            title: Text(review.content),
            subtitle: Text(
                'By: ${review.userName ?? review.userId} - ${review.createdAt.toLocal()}'),
          );
        },
      ),
    );
  }

  // Builds the Comments Tab ListView
  Widget _buildCommentsTab(BuildContext context) {
    if (_isLoadingComments) {
      return Container(
        color: Colors.white,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_comments.isEmpty) {
      return Container(
        color: Colors.white,
        child: const Center(child: Text('No comments yet.')),
      );
    }

    return Container(
      color: Colors.white,
      child: ListView.builder(
        itemCount: _comments.length,
        itemBuilder: (context, index) {
          final comment = _comments[index];
          // TODO: Create a proper CommentListItem widget
          return ListTile(
            title: Text(comment.content),
            subtitle: Text(
                'By: ${comment.userName ?? comment.userId} - ${comment.createdAt.toLocal()}'),
          );
        },
      ),
    );
  }

  // --- End Tabbed Content Widgets ---

  // --- ADDED: Quick Actions Section Widgets ---

  // Builds the row containing the quick action buttons
  Widget _buildQuickActionsSection(
      BuildContext context,
      Map<String, dynamic>? placeDetails, // Use fetched details
      Location location // Use experience location for coordinates
      ) {
    // Safely get phone number from details
    final String? phoneNumber = placeDetails?['nationalPhoneNumber'];
    // Safely get website URI: Prioritize experience's website, then place details
    final String? experienceWebsite = _currentExperience.website;
    final String? placeDetailsWebsite = placeDetails?['websiteUri'];
    final String? websiteUri =
        (experienceWebsite != null && experienceWebsite.isNotEmpty)
            ? experienceWebsite
            : placeDetailsWebsite;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildActionItem(
            context,
            Icons.star_outline,
            'Add Review',
            () {
              // TODO: Navigate to Add Review Screen/Modal
              print('Add Review tapped');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content:
                        Text('Add Review functionality not yet implemented.')),
              );
            },
          ),
          _buildActionItem(
            context,
            Icons.phone_outlined,
            'Call Venue',
            // Disable button if no phone number
            phoneNumber != null && phoneNumber.isNotEmpty
                ? () => _launchPhoneCall(phoneNumber)
                : null, // Pass null if no number
          ),
          _buildActionItem(
            context,
            Icons.language_outlined,
            'Website',
            // Disable button if no website URI
            websiteUri != null && websiteUri.isNotEmpty
                ? () => _launchUrl(websiteUri)
                : null, // Pass null if no URI
          ),
          _buildActionItem(
            context,
            Icons.directions_outlined,
            'Directions',
            () => _launchDirections(location),
          ),
        ],
      ),
    );
  }

  // Builds a single tappable action item (icon + label)
  Widget _buildActionItem(
      BuildContext context, IconData icon, String label, VoidCallback? onTap) {
    final bool enabled = onTap != null;
    final Color iconColor =
        enabled ? Theme.of(context).primaryColor : Colors.grey;
    final Color labelColor = enabled ? Colors.black87 : Colors.grey;

    return InkWell(
      onTap: onTap, // onTap will be null if disabled
      borderRadius: BorderRadius.circular(8.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: labelColor,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // --- Helper methods for launching URLs ---

  Future<void> _launchUrl(String urlString) async {
    final Uri uri = Uri.parse(urlString);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      print('Could not launch $uri');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open website: $urlString')),
        );
      }
    }
  }

  Future<void> _launchYelpSearch() async {
    final String experienceName = _currentExperience.name.trim();
    final Location location = _currentExperience.location;
    final String? address = location.address?.trim();
    Uri uri;

    if (experienceName.isNotEmpty) {
      final String searchDesc = Uri.encodeComponent(experienceName);
      final String timestamp =
          DateTime.now().millisecondsSinceEpoch.toString();
      if (address != null && address.isNotEmpty) {
        final String searchLoc = Uri.encodeComponent(address);
        uri = Uri.parse(
            'https://www.yelp.com/search?find_desc=$searchDesc&find_loc=$searchLoc&t=$timestamp');
      } else {
        uri = Uri.parse(
            'https://www.yelp.com/search?find_desc=$searchDesc&t=$timestamp');
      }
    } else {
      uri = Uri.parse('https://www.yelp.com');
    }

    try {
      bool launched = false;
      if (uri.toString().contains('yelp.com/search')) {
        final String? terms = uri.queryParameters['find_desc'];
        final String? locationQuery = uri.queryParameters['find_loc'];
        if (terms != null && terms.isNotEmpty) {
          final String encodedTerms = Uri.encodeComponent(terms);
          final String locationParam = locationQuery != null &&
                  locationQuery.isNotEmpty
              ? '&location=${Uri.encodeComponent(locationQuery)}'
              : '';
          final Uri deepLink = Uri.parse(
              'yelp:///search?terms=$encodedTerms$locationParam');
          try {
            // Try launching without canLaunchUrl check first
            launched = await launchUrl(deepLink,
                mode: LaunchMode.externalApplication);
            if (launched) {
              return;
            }
          } catch (e) {
            // Ignore deep link errors and fall back to HTTPS URL
          }
        }
      }

      launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Yelp link/search')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening Yelp: $e')),
        );
      }
    }
  }

  Future<void> _launchPhoneCall(String phoneNumber) async {
    // Format as tel: URI, removing non-digit characters
    final Uri phoneUri = Uri(
        scheme: 'tel', path: phoneNumber.replaceAll(RegExp(r'[^0-9+]'), ''));
    if (!await launchUrl(phoneUri)) {
      print('Could not launch $phoneUri');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not call $phoneNumber')),
        );
      }
    }
  }

  Future<void> _launchDirections(Location location) async {
    // Construct Google Maps directions URL (cross-platform)
    final lat = location.latitude;
    final lng = location.longitude;
    // Using address as destination query if available, otherwise lat/lng
    String query = (location.address != null && location.address!.isNotEmpty)
        ? Uri.encodeComponent(location.address!)
        : '$lat,$lng';

    final Uri mapUri =
        Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$query');

    if (!await launchUrl(mapUri, mode: LaunchMode.externalApplication)) {
      print('Could not launch $mapUri');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open map directions.')),
        );
      }
    }
  }

  // --- End Helper methods ---

  // --- ADDED Helper method to launch map location --- //
  Future<void> _launchMapLocation(Location location) async {
    final String mapUrl;
    // Prioritize Place ID if available
    if (location.placeId != null && location.placeId!.isNotEmpty) {
      // Use the Google Maps search API with place_id format
      // Use displayName if available, otherwise fall back to name from the experience
      final placeName = location.displayName ?? _currentExperience.name;
      mapUrl =
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(placeName)}&query_place_id=${location.placeId}';
      print('🗺️ Launching Map with Place ID: $mapUrl');
    } else {
      // Fallback to coordinate-based URL
      final lat = location.latitude;
      final lng = location.longitude;
      mapUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
      print('🗺️ Launching Map with Coordinates: $mapUrl');
    }

    final Uri mapUri = Uri.parse(mapUrl);

    if (!await launchUrl(mapUri, mode: LaunchMode.externalApplication)) {
      print('Could not launch $mapUri');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open map location.')),
        );
      }
    }
  }
  // --- END: Helper method to launch map location --- //

  Future<void> _handleSaveExperiencePressed() async {
    if (!widget.readOnlyPreview) return;
    if (_isSaveSheetOpen) return;

    setState(() {
      _isSaveSheetOpen = true;
    });

    try {
      final String mediaUrl = _resolveSaveMediaUrl();
      List<Experience> initialExperiences =
          await _buildInitialExperiencesForSave(mediaUrl: mediaUrl);
      if (initialExperiences.isEmpty) {
        initialExperiences = [_buildExperienceDraftForSaveModal()];
      }
      if (!mounted) return;

      final String? resultMessage = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => SaveToExperiencesModal(
          initialExperiences: initialExperiences,
          mediaUrl: mediaUrl,
        ),
      );

      if (resultMessage != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resultMessage)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to open save sheet: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaveSheetOpen = false;
        });
      } else {
        _isSaveSheetOpen = false;
      }
    }
  }

  String _resolveSaveMediaUrl() {
    if (_mediaItems.isNotEmpty) {
      final String primary = _mediaItems.first.path.trim();
      if (primary.isNotEmpty) {
        return primary;
      }
    }
    if (_publicMediaItems.isNotEmpty) {
      final String publicPath = _publicMediaItems.first.path.trim();
      if (publicPath.isNotEmpty) {
        return publicPath;
      }
    }
    if (_currentExperience.imageUrls.isNotEmpty) {
      final String firstImage = _currentExperience.imageUrls.first.trim();
      if (firstImage.isNotEmpty) {
        return firstImage;
      }
    }
    final String? headerUrl = _currentExperience.location.photoUrl;
    if (headerUrl != null && headerUrl.trim().isNotEmpty) {
      return headerUrl.trim();
    }
    return '';
  }

  Future<List<Experience>> _buildInitialExperiencesForSave({
    required String mediaUrl,
  }) async {
    // When viewing an experience in read-only mode (from share_preview_screen
    // or discovery_screen), only offer the current experience for saving -
    // don't fetch other experiences linked to the media.
    // - shareBannerFromUserId is set when coming from share_preview_screen
    // - publicExperienceId is set when coming from discovery_screen
    // In both cases, the "Save Experience" button should only save the current
    // experience being viewed, not show a list of linked experiences.
    // Note: The discovery feed's direct "Save" button (in discovery_screen.dart)
    // still fetches linked experiences - this only affects the ExperiencePageScreen.
    final bool isReadOnlyView = widget.shareBannerFromUserId != null ||
        widget.publicExperienceId != null;

    if (isReadOnlyView) {
      return [_buildExperienceDraftForSaveModal()];
    }

    final List<Experience> linkedExperiences =
        await _fetchExperiencesLinkedToMedia(mediaUrl);
    final List<Experience> deduped = _dedupeExperiencesById(linkedExperiences);
    if (deduped.isEmpty) {
      return [_buildExperienceDraftForSaveModal()];
    }

    final bool alreadyContainsCurrent = deduped.any(
      (experience) => _experiencesLikelyMatch(experience, _currentExperience),
    );

    if (alreadyContainsCurrent) {
      return deduped;
    }

    return [...deduped, _buildExperienceDraftForSaveModal()];
  }

  Future<List<Experience>> _fetchExperiencesLinkedToMedia(
      String mediaUrl) async {
    if (mediaUrl.isEmpty) {
      return const <Experience>[];
    }

    try {
      final SharedMediaItem? mediaItem =
          await _experienceService.findSharedMediaItemByPath(mediaUrl);
      if (mediaItem == null || mediaItem.experienceIds.isEmpty) {
        return const <Experience>[];
      }

      final experiences =
          await _experienceService.getExperiencesByIds(mediaItem.experienceIds);
      experiences.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return experiences;
    } catch (e) {
      debugPrint(
          'ExperiencePageScreen: Failed to load linked experiences for save: $e');
      return const <Experience>[];
    }
  }

  Experience _buildExperienceDraftForSaveModal() {
    return _currentExperience.copyWith(
      id: '',
      clearCategoryId: true,
      colorCategoryId: null,
      otherCategories: const <String>[],
      editorUserIds: const <String>[],
      sharedMediaItemIds: const <String>[],
      sharedMediaType: null,
    );
  }

  bool _experiencesLikelyMatch(
    Experience savedExperience,
    Experience targetExperience,
  ) {
    final String savedPlaceId = savedExperience.location.placeId?.trim() ?? '';
    final String targetPlaceId = targetExperience.location.placeId?.trim() ?? '';
    if (savedPlaceId.isNotEmpty && targetPlaceId.isNotEmpty) {
      return savedPlaceId == targetPlaceId;
    }

    final String savedName = savedExperience.name.trim().toLowerCase();
    final String targetName = targetExperience.name.trim().toLowerCase();
    if (savedName.isEmpty || targetName.isEmpty) {
      return false;
    }

    final String savedAddress =
        (savedExperience.location.address ?? '').trim().toLowerCase();
    final String targetAddress =
        (targetExperience.location.address ?? '').trim().toLowerCase();

    if (savedAddress.isNotEmpty && targetAddress.isNotEmpty) {
      return savedName == targetName && savedAddress == targetAddress;
    }

    return savedName == targetName;
  }

  List<Experience> _dedupeExperiencesById(List<Experience> experiences) {
    final Set<String> seen = <String>{};
    final List<Experience> deduped = [];
    for (final exp in experiences) {
      final String key = _experienceCacheKey(exp);
      if (seen.add(key)) {
        deduped.add(exp);
      }
    }
    return deduped;
  }

  String _experienceCacheKey(Experience experience) {
    if (experience.id.isNotEmpty) {
      return experience.id;
    }

    final Location location = experience.location;
    final StringBuffer buffer = StringBuffer()
      ..write(experience.name.trim().toLowerCase())
      ..write('|')
      ..write(location.placeId?.trim().toLowerCase() ?? '')
      ..write('|')
      ..write((location.address ?? '').trim().toLowerCase());
    return buffer.toString();
  }

  Future<void> _resolveSharerDisplayName(String userId) async {
    try {
      final userProfile = await _experienceService.getUserProfileById(userId);
      if (!mounted) return;
      setState(() {
        _shareBannerDisplayName =
            userProfile?.displayName ?? userProfile?.username ?? 'Someone';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _shareBannerDisplayName = 'Someone';
      });
    }
  }

  /// Fetch events and find the matching event for the banner
  Future<void> _fetchMatchingEvent() async {
    final String? userId = _authService.currentUser?.uid;
    if (userId == null || _currentExperience.id.isEmpty) {
      setState(() {
        _isLoadingEventBanner = false;
        _matchingEvent = null;
      });
      return;
    }

    try {
      final events = await _eventService.getEventsForUser(userId);
      if (!mounted) return;

      final now = DateTime.now();
      Event? matchingEvent;
      DateTime? earliestStartTime;

      for (final event in events) {
        // Only consider upcoming or ongoing events
        if (event.endDateTime.isBefore(now)) {
          continue; // Event has ended
        }

        // Check if this event contains the current experience
        final hasMatch = event.experiences.any((entry) =>
            entry.experienceId.isNotEmpty &&
            entry.experienceId == _currentExperience.id);

        if (hasMatch) {
          // Pick the earliest event that matches
          if (earliestStartTime == null ||
              event.startDateTime.isBefore(earliestStartTime)) {
            earliestStartTime = event.startDateTime;
            matchingEvent = event;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _matchingEvent = matchingEvent;
        _isLoadingEventBanner = false;
      });
    } catch (e) {
      debugPrint('_fetchMatchingEvent: Error fetching events: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingEventBanner = false;
        _matchingEvent = null;
      });
    }
  }

  /// Get the event color (prefer colorHex, fall back to ID-based color)
  Color _getEventColor(Event event) {
    if (event.colorHex != null && event.colorHex!.isNotEmpty) {
      return _parseEventColor(event.colorHex!);
    }
    // Default color generation based on event ID
    final colors = [
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

  Color _parseEventColor(String hexColor) {
    String normalized = hexColor.toUpperCase().replaceAll('#', '');
    if (normalized.length == 6) {
      normalized = 'FF$normalized';
    }
    if (normalized.length == 8) {
      try {
        return Color(int.parse('0x$normalized'));
      } catch (_) {
        return Colors.blue;
      }
    }
    return Colors.blue;
  }

  bool _isEventColorDark(Color color) {
    final luminance = (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue) / 255;
    return luminance < 0.5;
  }

  /// Build the event banner widget
  Widget _buildEventBanner(BuildContext context) {
    final event = _matchingEvent!;
    final eventColor = _getEventColor(event);
    final isDark = _isEventColorDark(eventColor);
    final textColor = isDark ? Colors.white : Colors.black87;

    // Format the date as "Tuesday, June 15, 2025"
    final dateFormatter = DateFormat('EEEE, MMMM d, yyyy');
    final formattedDate = dateFormatter.format(event.startDateTime);

    return GestureDetector(
      onTap: () => _openEventEditor(event),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: eventColor,
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Row(
          children: [
            Icon(
              Icons.event,
              color: textColor,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'You are scheduled to go here on $formattedDate',
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: textColor.withOpacity(0.7),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  /// Open the event editor modal
  Future<void> _openEventEditor(Event event) async {
    try {
      // Fetch experiences for the event
      final experienceIds = event.experiences
          .where((entry) => entry.experienceId.isNotEmpty)
          .map((entry) => entry.experienceId)
          .toList();

      final experiences = experienceIds.isNotEmpty
          ? await _experienceService.getExperiencesByIds(experienceIds)
          : <Experience>[];

      // Fetch categories if not already loaded
      List<UserCategory> categories = _userCategories;
      List<ColorCategory> colorCategories = widget.userColorCategories;

      if (categories.isEmpty || colorCategories.isEmpty) {
        final result = await _experienceService.getUserAndColorCategories(
          includeSharedEditable: true,
        );
        categories = result.userCategories;
        colorCategories = result.colorCategories;
      }

      if (!mounted) return;

      // Open the event editor modal
      final result = await showDialog<EventEditorResult>(
        context: context,
        useSafeArea: false,
        builder: (context) => EventEditorModal(
          event: event,
          experiences: experiences,
          categories: categories,
          colorCategories: colorCategories,
          isReadOnly: true,
        ),
      );

      // Handle result
      if (result != null && result.wasSaved && mounted) {
        // Refresh the matching event data
        _fetchMatchingEvent();
      }
    } catch (e) {
      debugPrint('_openEventEditor: Error opening event editor: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open event: $e')),
        );
      }
    }
  }

  // ADDED: Method to refresh experience data
  Future<void> _refreshExperienceData() async {
    if (!mounted) return;
    setState(() {
      _isLoadingExperience = true;
    });
    try {
      final updatedExperience =
          await _experienceService.getExperience(_currentExperience.id);
      if (mounted && updatedExperience != null) {
        setState(() {
          _currentExperience = updatedExperience;
        });
        // After refreshing the experience (including sharedMediaItemIds), refresh media items list
        await _fetchMediaItems();
      }
      // Handle case where experience is not found after deletion (optional)
      // else if (mounted) { Navigator.of(context).pop(); // Or show error }
    } catch (e) {
      print("Error refreshing experience data: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to refresh experience data: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingExperience = false;
        });
      }
    }
  }

  // ADDED: Method to fetch media items based on IDs
  Future<void> _fetchMediaItems() async {
    setState(() {
      _isLoadingMedia = true;
    });
    try {
      final mediaIds = _currentExperience.sharedMediaItemIds;
      if (mediaIds.isNotEmpty) {
        final items = await _experienceService.getSharedMediaItems(mediaIds);
        // ADDED: Sort fetched items by createdAt descending
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        if (mounted) {
          setState(() {
            _mediaItems = items;
            _expandedMediaPath =
                _mediaItems.isNotEmpty ? _mediaItems.first.path : null;
            _isMediaPreviewHeightExpanded = false;
            print("Fetched ${_mediaItems.length} media items for experience.");
          });
          // --- ADDED: Trigger loading of other experience data --- START ---
          // Call this AFTER _mediaItems is set
          _loadOtherExperienceData();
          // --- ADDED: Trigger loading of other experience data --- END ---
        }
      } else {
        print("No media item IDs associated with this experience.");
        if (mounted) {
          setState(() {
            _mediaItems = [];
            _expandedMediaPath = null;
            _isMediaPreviewHeightExpanded = false;
          });
        }
      }
    } catch (e) {
      print("Error fetching media items: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading media: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMedia = false;
        });
      }
    }
  }

  Future<void> _toggleContentSource() async {
    if (_showingPublicMedia) {
      setState(() {
        _showingPublicMedia = false;
        _expandedMediaPath =
            _mediaItems.isNotEmpty ? _mediaItems.first.path : null;
        _isMediaPreviewHeightExpanded = false;
      });
      return;
    }

    if (!_canShowPublicContentToggle) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Public content is not available for this place.')),
      );
      return;
    }

    final String? placeId = _currentExperience.location.placeId;
    if (placeId == null || placeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing place information.')),
      );
      return;
    }

    // If we've already fetched public media once, just switch views.
    if (_hasAttemptedPublicMediaFetch) {
      setState(() {
        _showingPublicMedia = true;
        _expandedMediaPath =
            _publicMediaItems.isNotEmpty ? _publicMediaItems.first.path : null;
        _isMediaPreviewHeightExpanded = false;
      });
      return;
    }

    setState(() {
      _showingPublicMedia = true;
      _isLoadingPublicMedia = true;
      _expandedMediaPath = null;
      _isMediaPreviewHeightExpanded = false;
    });

    bool fetchCompleted = false;
    try {
      final PublicExperience? publicExperience =
          await _experienceService.findPublicExperienceByPlaceId(placeId);
      if (!mounted) return;

      final List<SharedMediaItem> items = List<SharedMediaItem>.from(
          publicExperience?.buildMediaItemsForPreview() ??
              const <SharedMediaItem>[]);
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      fetchCompleted = true;
      setState(() {
        _publicMediaItems = items;
        if (_showingPublicMedia) {
          _expandedMediaPath = _publicMediaItems.isNotEmpty
              ? _publicMediaItems.first.path
              : null;
        }
        _isMediaPreviewHeightExpanded = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _showingPublicMedia = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to load public content: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPublicMedia = false;
          if (fetchCompleted) {
            _hasAttemptedPublicMediaFetch = true;
          }
        });
      }
    }
  }

  Future<void> _maybeSyncMediaPathWithPublicExperiences({
    required String mediaPath,
    required String toggledMediaId,
    required bool newIsPrivate,
    required Set<String> placeIds,
  }) async {
    if (mediaPath.isEmpty || placeIds.isEmpty || toggledMediaId.isEmpty) {
      return;
    }

    try {
      final items =
          await _experienceService.getSharedMediaItemsByPath(mediaPath);
      final bool otherHasPublic = items.any((media) {
        if (media.id == toggledMediaId) {
          return false;
        }
        return !media.isPrivate;
      });

      if (newIsPrivate) {
        if (otherHasPublic) return;
        for (final placeId in placeIds) {
          await _experienceService
              .removeMediaPathFromPublicExperienceByPlaceId(placeId, mediaPath);
        }
      } else {
        if (otherHasPublic) return;
        final experienceTemplate = _currentExperience;
        for (final placeId in placeIds) {
          await _experienceService.addMediaPathToPublicExperienceByPlaceId(
            placeId,
            mediaPath,
            experienceTemplate: experienceTemplate.location.placeId == placeId
                ? experienceTemplate
                : null,
          );
        }
      }
    } catch (e) {
      debugPrint(
          '_maybeSyncMediaPathWithPublicExperiences: Failed for $mediaPath -> $e');
    }
  }

  Future<void> _toggleMediaItemPrivacy(SharedMediaItem item) async {
    if (item.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This content item cannot be updated yet.')),
      );
      return;
    }
    final bool newValue = !item.isPrivate;
    final previousMedia = List<SharedMediaItem>.from(_mediaItems);
    setState(() {
      _mediaItems = _mediaItems
          .map((media) =>
              media.id == item.id ? media.copyWith(isPrivate: newValue) : media)
          .toList();
    });
    try {
      await _experienceService.updateSharedMediaPrivacy(item.id, newValue);
      final placeId = _currentExperience.location.placeId;
      if (placeId != null && placeId.isNotEmpty && item.path.isNotEmpty) {
        unawaited(_maybeSyncMediaPathWithPublicExperiences(
          mediaPath: item.path,
          toggledMediaId: item.id,
          newIsPrivate: newValue,
          placeIds: {placeId},
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mediaItems = previousMedia;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to update privacy. Please try again.')),
      );
    }
  }

  // --- ADDED: Method to load data about other experiences linked to the media items --- START ---
  Future<void> _loadOtherExperienceData() async {
    // Use the same logic as in MediaFullscreenScreen
    print("[ExpPage - _loadOtherExperienceData] Starting...");
    if (!mounted || _mediaItems.isEmpty) {
      print(
          "[ExpPage - _loadOtherExperienceData] Not mounted or no media items yet. Aborting.");
      setState(() => _isLoadingOtherExperiences =
          false); // Ensure loading stops if no items
      return;
    }

    setState(() {
      _isLoadingOtherExperiences = true;
    });

    final Map<String, List<Experience>> otherExperiencesMap = {};
    final Set<String> otherExperienceIds = {};
    // final Set<String> requiredCategoryNames = {}; // OLD: Was Set of names
    final Set<String?> requiredCategoryIds =
        {}; // NEW: Set of category IDs (nullable)

    print(
        "[ExpPage - _loadOtherExperienceData] Comparing against current Experience ID: ${_currentExperience.id}");

    // 1. Collect all *other* experience IDs from the current media items
    for (final item in _mediaItems) {
      print(
          "[ExpPage - _loadOtherExperienceData] Processing item ${item.id} (Path: ${item.path}) with experienceIds: ${item.experienceIds}");
      final otherIds = item.experienceIds
          .where((id) => id != _currentExperience.id)
          .toList();
      if (otherIds.isNotEmpty) {
        otherExperienceIds.addAll(otherIds);
      }
    }

    print(
        "[ExpPage - _loadOtherExperienceData] Found other experience IDs: $otherExperienceIds");

    // 2. Fetch other experiences if any exist
    Map<String, Experience> fetchedExperiencesById = {};
    if (otherExperienceIds.isNotEmpty) {
      try {
        // Fetch experiences individually using Future.wait
        final List<Experience?> experienceFutures = await Future.wait(
            otherExperienceIds
                .map((id) => _experienceService.getExperience(id))
                .toList());
        final List<Experience> experiences =
            experienceFutures.whereType<Experience>().toList();
        print(
            "[ExpPage - _loadOtherExperienceData] Fetched ${experiences.length} other experiences.");
        fetchedExperiencesById = {for (var exp in experiences) exp.id: exp};
        for (final exp in experiences) {
          // if (exp.category.isNotEmpty) { // OLD
          //   requiredCategoryNames.add(exp.category); // OLD
          // }
          if (exp.categoryId != null && exp.categoryId!.isNotEmpty) {
            // NEW
            requiredCategoryIds.add(exp.categoryId); // NEW
          }
        }
      } catch (e) {
        print("Error fetching other experiences: $e");
      }
    }

    // 3. Fetch required categories if any exist (use existing _userCategories or fetch)
    // Map<String, UserCategory> categoryLookupMap = {}; // OLD: Keyed by name
    Map<String, UserCategory> categoryLookupMapById = {}; // NEW: Keyed by ID

    // Use already loaded categories if available and create a map by ID
    if (_userCategories.isNotEmpty) {
      categoryLookupMapById = {for (var cat in _userCategories) cat.id: cat};
      print(
          "[ExpPage - _loadOtherExperienceData] Using already loaded categories (${_userCategories.length}) and mapped by ID.");
    }

    // Check if all requiredCategoryIds are covered by the existing lookup map
    bool allRequiredCategoriesFound = requiredCategoryIds
        .every((id) => id == null || categoryLookupMapById.containsKey(id));

    if (!allRequiredCategoriesFound &&
        requiredCategoryIds.whereNotNull().isNotEmpty) {
      print(
          "[ExpPage - _loadOtherExperienceData] Not all required categories found in local cache. Fetching all categories again to ensure completeness.");
      try {
        final allUserCategories = await _experienceService.getUserCategories(
          includeSharedEditable: true,
        );
        categoryLookupMapById = {
          for (var cat in allUserCategories) cat.id: cat
        }; // Rebuild map with all categories by ID
        print(
            "[ExpPage - _loadOtherExperienceData] Fetched ${categoryLookupMapById.length} categories and mapped by ID.");
      } catch (e) {
        print("Error fetching user categories: $e");
      }
    }

    // 4. Build the map for the state
    for (final item in _mediaItems) {
      final otherIds = item.experienceIds
          .where((id) => id != _currentExperience.id)
          .toList();
      if (otherIds.isNotEmpty) {
        final associatedExps = otherIds
            .map((id) => fetchedExperiencesById[id])
            .where((exp) => exp != null)
            .cast<Experience>()
            .toList();
        associatedExps.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        otherExperiencesMap[item.path] = associatedExps;
      }
    }

    print(
        "[ExpPage - _loadOtherExperienceData] Built map for UI: ${otherExperiencesMap.keys.length} items have other experiences.");

    if (mounted) {
      setState(() {
        _otherAssociatedExperiences = otherExperiencesMap;
        _fetchedCategoriesForMedia =
            categoryLookupMapById; // Store the category lookup by ID
        _isLoadingOtherExperiences = false;
        print(
            "[ExpPage - _loadOtherExperienceData] Set state: isLoading=false");
      });
    }
  }
  // --- ADDED: Method to load data about other experiences linked to the media items --- END ---

  // --- ADDED: Helper Widget for Other Categories Row --- START ---
  Widget _buildOtherCategoriesRow(BuildContext context, Experience experience) {
    final bool hasOtherCategories = experience.otherCategories.isNotEmpty;
    final bool hasOtherColorCategories =
        experience.otherColorCategoryIds.isNotEmpty;
    if (!hasOtherCategories && !hasOtherColorCategories) {
      return const SizedBox.shrink(); // Don't show row if no other categories
    }

    // Find the category objects from the loaded user categories
    final otherCategoryObjects = experience.otherCategories
        .map((categoryId) {
          try {
            return _userCategories.firstWhere((cat) => cat.id == categoryId);
          } catch (e) {
            return null; // Category not found
          }
        })
        .where((cat) => cat != null)
        .cast<UserCategory>()
        .toList();

    final otherColorCategoryObjects = experience.otherColorCategoryIds
        .map((colorCategoryId) {
          try {
            return widget.userColorCategories
                .firstWhere((cat) => cat.id == colorCategoryId);
          } catch (e) {
            return null; // Color category not found
          }
        })
        .where((cat) => cat != null)
        .cast<ColorCategory>()
        .toList();

    final bool showOtherCategories = otherCategoryObjects.isNotEmpty;
    final bool showOtherColorCategories =
        otherColorCategoryObjects.isNotEmpty;
    if (!showOtherCategories && !showOtherColorCategories) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.category_outlined, size: 20.0, color: Colors.black54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showOtherCategories) ...[
                  Text(
                    'Other Categories:',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6.0,
                    runSpacing: 6.0,
                    children: otherCategoryObjects.map((category) {
                      return Chip(
                        backgroundColor: Colors.white,
                        avatar: Text(category.icon,
                            style: const TextStyle(fontSize: 14)),
                        label: Text(category.name),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        visualDensity: VisualDensity.compact,
                        labelPadding:
                            const EdgeInsets.symmetric(horizontal: 4.0),
                      );
                    }).toList(),
                  ),
                ],
                if (showOtherColorCategories) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Other Color Categories:',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6.0,
                    runSpacing: 6.0,
                    children: otherColorCategoryObjects.map((colorCategory) {
                      return Chip(
                        backgroundColor: Colors.white,
                        avatar: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: colorCategory.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        label: Text(colorCategory.name),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        visualDensity: VisualDensity.compact,
                        labelPadding:
                            const EdgeInsets.symmetric(horizontal: 4.0),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
  // --- ADDED: Helper Widget for Other Categories Row --- END ---

  void _showReportDialog() {
    String? selectedReason;
    final TextEditingController explanationController = TextEditingController();
    bool isSubmitting = false;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'What would you like to report about this experience?',
                style: TextStyle(fontSize: 18),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RadioListTile<String>(
                      title: const Text('Inappropriate content'),
                      value: 'inappropriate',
                      groupValue: selectedReason,
                      onChanged: isSubmitting
                          ? null
                          : (value) {
                              setState(() {
                                selectedReason = value;
                              });
                            },
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    RadioListTile<String>(
                      title: const Text('Incorrect Information'),
                      value: 'incorrect',
                      groupValue: selectedReason,
                      onChanged: isSubmitting
                          ? null
                          : (value) {
                              setState(() {
                                selectedReason = value;
                              });
                            },
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    RadioListTile<String>(
                      title: const Text('Other'),
                      value: 'other',
                      groupValue: selectedReason,
                      onChanged: isSubmitting
                          ? null
                          : (value) {
                              setState(() {
                                selectedReason = value;
                              });
                            },
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Please explain:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: explanationController,
                      maxLines: 4,
                      enabled: !isSubmitting,
                      decoration: InputDecoration(
                        hintText: 'Provide additional details...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () {
                          explanationController.dispose();
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          await _handleReportSubmit(
                            dialogContext: dialogContext,
                            selectedReason: selectedReason,
                            explanationController: explanationController,
                            setSubmitting: (value) {
                              setState(() {
                                isSubmitting = value;
                              });
                            },
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleReportSubmit({
    required BuildContext dialogContext,
    required String? selectedReason,
    required TextEditingController explanationController,
    required void Function(bool) setSubmitting,
  }) async {
    if (selectedReason == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a reason for reporting'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You must be logged in to report content'),
          ),
        );
      }
      return;
    }

    setSubmitting(true);

    try {
      const String previewUrl = '';
      final bool isReadOnly = widget.readOnlyPreview;
      final String? publicExperienceIdForReport = isReadOnly
          ? (widget.publicExperienceId?.isNotEmpty == true
              ? widget.publicExperienceId
              : (_currentExperience.id.isNotEmpty
                  ? _currentExperience.id
                  : null))
          : null;
      final String experienceIdForReport = isReadOnly
          ? (publicExperienceIdForReport ?? _currentExperience.id)
          : _currentExperience.id;

      final existingReport = await _reportService.findExistingReport(
        userId: currentUser.uid,
        experienceId: experienceIdForReport,
        previewURL: previewUrl,
      );

      if (existingReport != null) {
        if (!mounted) return;
        explanationController.dispose();
        Navigator.of(dialogContext).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You have already reported this content. Thank you for your feedback!',
            ),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      final deviceInfo = _getDeviceInfo();
      final String screenReported = isReadOnly
          ? 'read-only experience_page_screen'
          : 'experience_page_screen';

      final report = Report(
        id: '',
        userId: currentUser.uid,
        screenReported: screenReported,
        previewURL: previewUrl,
        experienceId: experienceIdForReport,
        reportType: selectedReason,
        details: explanationController.text.trim(),
        createdAt: DateTime.now(),
        reportedUserId: _currentExperience.createdBy,
        publicExperienceId: publicExperienceIdForReport,
        deviceInfo: deviceInfo,
      );

      await _reportService.submitReport(report);

      if (!mounted) return;
      explanationController.dispose();
      Navigator.of(dialogContext).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report submitted. Thank you for your feedback!'),
          duration: Duration(seconds: 3),
        ),
      );

      debugPrint(
        'ExperiencePageScreen: Report submitted for experience ${_currentExperience.id}',
      );
    } catch (e) {
      debugPrint('ExperiencePageScreen: Failed to submit report: $e');
      if (!mounted) return;
      setSubmitting(false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to submit report. Please try again.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  String _getDeviceInfo() {
    if (kIsWeb) {
      return 'Web';
    }
    try {
      if (Platform.isIOS) {
        return 'iOS';
      } else if (Platform.isAndroid) {
        return 'Android';
      } else if (Platform.isMacOS) {
        return 'macOS';
      } else if (Platform.isWindows) {
        return 'Windows';
      } else if (Platform.isLinux) {
        return 'Linux';
      }
    } catch (e) {
      debugPrint('ExperiencePageScreen: Failed to get platform info: $e');
    }
    return 'Unknown';
  }

  // --- ADDED: Removal confirmation and execution ---
  Future<void> _promptRemoveExperience() async {
    // Ensure user is authenticated
    final String? userId = _currentUserId ?? _authService.currentUser?.uid;
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('You must be signed in to remove experiences.')),
        );
      }
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white, // Force a pure white dialog on M3
          title: const Text('Remove Experience'),
          content: const Text(
              'This will remove the experience from your list. You will no longer see or edit it. Do you want to proceed?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      // Remove current user's ID from editorUserIds
      final List<String> updatedEditors =
          List<String>.from(_currentExperience.editorUserIds)
            ..removeWhere((id) => id == userId);

      if (updatedEditors.isEmpty) {
        // No editors remain; delete the experience
        await _experienceService.deleteExperience(_currentExperience.id);
      } else {
        final Experience updated =
            _currentExperience.copyWith(editorUserIds: updatedEditors);
        await _experienceService.updateExperience(updated);
      }

      if (mounted) {
        // Show toast/snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Experience removed.')),
        );
        _didDataChange = true;
        // Navigate back to the main screen
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove experience: $e')),
        );
      }
    }
  }
  // --- END: Removal confirmation and execution ---

  // --- Media item share helpers ---
  Future<void> _handleMediaShareButtonPressed(SharedMediaItem mediaItem) async {
    if (!mounted) return;
    await showShareExperienceBottomSheet(
      context: context,
      onDirectShare: () => _shareMediaItemDirectly(mediaItem),
      onCreateLink: ({
        required String shareMode,
        required bool giveEditAccess,
      }) =>
          _createLinkShareForMedia(
        shareMode: shareMode,
        giveEditAccess: giveEditAccess,
      ),
    );
  }

  Future<void> _shareMediaItemDirectly(SharedMediaItem mediaItem) async {
    if (!mounted) return;
    final String? highlightedUrl =
        mediaItem.path.isNotEmpty ? mediaItem.path : null;
    final result = await showShareToFriendsModal(
      context: context,
      subjectLabel: _currentExperience.name,
      onSubmit: (recipientIds) async {
        return await _experienceShareService.createDirectShare(
          experience: _currentExperience,
          toUserIds: recipientIds,
          highlightedMediaUrl: highlightedUrl,
        );
      },
      onSubmitToThreads: (threadIds) async {
        return await _experienceShareService.createDirectShareToThreads(
          experience: _currentExperience,
          threadIds: threadIds,
          highlightedMediaUrl: highlightedUrl,
        );
      },
      onSubmitToNewGroupChat: (participantIds) async {
        return await _experienceShareService.createDirectShareToNewGroupChat(
          experience: _currentExperience,
          participantIds: participantIds,
          highlightedMediaUrl: highlightedUrl,
        );
      },
    );
    if (!mounted) return;
    if (result != null) {
      showSharedWithFriendsSnackbar(context, result);
    }
  }

  Future<void> _createLinkShareForMedia({
    required String shareMode,
    required bool giveEditAccess,
  }) async {
    if (_isMediaShareInProgress || !mounted) return;
    setState(() {
      _isMediaShareInProgress = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final DateTime expiresAt = DateTime.now().add(const Duration(days: 30));
      final String url = await _experienceShareService.createLinkShare(
        experience: _currentExperience,
        expiresAt: expiresAt,
        linkMode: shareMode,
        grantEdit: giveEditAccess,
      );
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) {
        Navigator.of(context).pop();
      }
      await Share.share('Check out this experience from Plendy! $url');
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content:
                Text('Unable to generate a share link. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isMediaShareInProgress = false;
        });
      }
    }
  }

  // --- ADD: Share bottom sheet ---
  void _showShareBottomSheet() {
    showShareExperienceBottomSheet(
      context: context,
      onDirectShare: _openDirectShareDialog,
      onCreateLink: _createLinkShareWithOptions,
    );
  }

  Future<void> _openDirectShareDialog() async {
    if (!mounted) return;
    final result = await showShareToFriendsModal(
      context: context,
      subjectLabel: _currentExperience.name,
      onSubmit: (recipientIds) async {
        return await _experienceShareService.createDirectShare(
          experience: _currentExperience,
          toUserIds: recipientIds,
        );
      },
      onSubmitToThreads: (threadIds) async {
        return await _experienceShareService.createDirectShareToThreads(
          experience: _currentExperience,
          threadIds: threadIds,
        );
      },
      onSubmitToNewGroupChat: (participantIds) async {
        return await _experienceShareService.createDirectShareToNewGroupChat(
          experience: _currentExperience,
          participantIds: participantIds,
        );
      },
    );
    if (!mounted) return;
    if (result != null) {
      showSharedWithFriendsSnackbar(context, result);
    }
  }

  Future<void> _createLinkShareWithOptions({
    required String shareMode, // 'my_copy' | 'separate_copy'
    required bool giveEditAccess,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Creating shareable link...')),
    );
    try {
      final service = ExperienceShareService();
      final DateTime expiresAt = DateTime.now().add(const Duration(days: 30));
      final url = await service.createLinkShare(
        experience: _currentExperience,
        expiresAt: expiresAt,
        linkMode: shareMode,
        grantEdit: giveEditAccess,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await Share.share('Check out this experience from Plendy! $url');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to create link: $e')),
      );
    }
  }

  // --- END: Share bottom sheet ---
}

// --- ADDED Helper class for SliverPersistentHeader (for TabBar) ---
class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(
    this._child, {
    required this.minHeight,
    required this.maxHeight,
  }) : assert(maxHeight >= minHeight);

  final Widget _child;
  final double minHeight;
  final double maxHeight;

  @override
  double get minExtent => minHeight;
  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    // Return a container that fills the delegate's space
    return Container(
      color: Colors.white, // Force white background for the pinned area
      // Align the child widget to the bottom of this container
      child: Align(
        alignment: Alignment.bottomCenter,
        child: _child, // Place the actual child widget here
      ),
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    // Rebuild if the child widget instance changes
    return _child != oldDelegate._child;
  }
}
// --- End Helper Class ---
