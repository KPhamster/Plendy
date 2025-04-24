import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import '../models/experience.dart';
import '../models/user_category.dart'; // Import UserCategory
// TODO: Import your PlaceDetails model and PlacesService
// import '../models/place_details.dart';
// import '../services/places_service.dart';
// ADDED: Import GoogleMapsService
import '../services/google_maps_service.dart';
import 'dart:convert';
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
// REMOVED: Dio import (no longer needed for thumbnail fetching)
// import 'package:dio/dio.dart';
// REMOVED: Dotenv import (no longer needed for credentials)
// import 'package:flutter_dotenv/flutter_dotenv.dart';
// ADDED: Import the new fullscreen screen
import 'media_fullscreen_screen.dart';
// UPDATED: Import the renamed widget
import 'receive_share/widgets/instagram_preview_widget.dart'
    as instagram_widget;
// ADDED: Import for FontAwesomeIcons
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
// ADDED: Import AuthService (adjust path if necessary)
import '../services/auth_service.dart';
// ADDED: Import the new edit modal (we will create this file next)
import '../widgets/edit_experience_modal.dart';

// Convert to StatefulWidget
class ExperiencePageScreen extends StatefulWidget {
  final Experience experience;
  final UserCategory category;

  const ExperiencePageScreen({
    super.key,
    required this.experience,
    required this.category,
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

  // Tab Controller State
  late TabController _tabController;
  bool _isLoadingReviews = true;
  bool _isLoadingComments = true;
  List<Review> _reviews = [];
  List<Comment> _comments = [];
  // TODO: Add state for comment count if fetching separately
  int _commentCount = 0; // Placeholder

  // Hours Expansion State
  bool _isHoursExpanded = false;

  // Services
  final _googleMapsService = GoogleMapsService();
  final _experienceService = ExperienceService(); // ADDED
  // ADDED: AuthService instance
  final _authService = AuthService();
  // REMOVED: Dio instance
  // final _dio = Dio();

  // ADDED: State for current user ID and categories
  String? _currentUserId;
  bool _isLoadingAuth = true;
  List<UserCategory> _userCategories = [];
  bool _isLoadingCategories = false; // Separate loading for categories

  // REMOVED: Instagram Credentials
  // String? _instagramAppId;
  // String? _instagramClientToken;

  // REMOVED: Thumbnail Cache
  // final Map<String, String?> _thumbnailCache = {};

  @override
  void initState() {
    super.initState();
    // Initialize local state with initial experience data
    _currentExperience = widget.experience;

    _tabController =
        TabController(length: 3, vsync: this); // Initialize TabController
    // REMOVED: Call to load Instagram credentials
    // _loadInstagramCredentials();
    _fetchPlaceDetails();
    _fetchReviews(); // Fetch reviews on init
    _fetchComments(); // Fetch comments on init
    _loadCurrentUserAndCategories(); // Fetch current user and categories
    // TODO: Fetch comment count if needed
  }

  @override
  void dispose() {
    _tabController.dispose(); // Dispose TabController
    super.dispose();
  }

  // REMOVED: Function to load Instagram credentials
  // void _loadInstagramCredentials() { ... }

  // Method to fetch place details
  Future<void> _fetchPlaceDetails() async {
    // Ensure we have a placeId to fetch details
    final placeId = _currentExperience.location.placeId;
    if (placeId == null || placeId.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoadingDetails = false;
          _errorLoadingDetails = 'Missing Place ID for details.';
        });
      }
      return;
    }

    setState(() {
      _isLoadingDetails = true;
      _errorLoadingDetails = null;
    });

    try {
      // TODO: Replace with actual API call from your service
      // print('Simulating API call for Place ID: $placeId');
      // await Future.delayed(const Duration(seconds: 1)); // Simulate network delay
      // final details = await _placesService.getPlaceDetails(placeId);

      // --- REMOVED SIMULATED DATA ---

      // Call the new service method
      final fetchedDetails =
          await _googleMapsService.fetchPlaceDetailsData(placeId);

      if (mounted) {
        if (fetchedDetails != null) {
          setState(() {
            // Assign actual fetched details (as Map)
            _placeDetailsData = fetchedDetails;
            _isLoadingDetails = false;
            // ADDED: Log fetched data
            print('✅ Fetched Place Details Data:');
            print(jsonEncode(
                _placeDetailsData)); // Use jsonEncode for readability
          });
        } else {
          // Handle case where service returned null (error handled inside service)
          setState(() {
            _isLoadingDetails = false;
            _errorLoadingDetails =
                'Failed to load place details. Please try again later.';
          });
        }
      }
    } catch (e) {
      // This catch block might be redundant if service handles errors, but kept for safety
      print('Error calling fetchPlaceDetailsData: $e');
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

    try {
      // Fetch categories only if user ID was obtained (or handle public categories)
      if (_currentUserId != null) {
        final categories = await _experienceService.getUserCategories();
        if (mounted) {
          setState(() {
            _userCategories = categories;
            _isLoadingCategories = false;
          });
        }
      } else {
        // Handle case where user ID is null (e.g., fetch public categories or leave empty)
        if (mounted) {
          setState(() {
            _isLoadingCategories = false;
          });
        }
      }
    } catch (e) {
      print("Error loading user categories: $e");
      if (mounted) {
        setState(() {
          _isLoadingCategories = false; // Stop loading even on error
        });
        // Optionally show error
      }
    }
  }

  // ADDED: Helper to determine if the current user can edit
  bool _canEditExperience() {
    if (_isLoadingAuth || _currentUserId == null) {
      return false; // Can't edit if loading or not logged in
    }
    // Check if current user is the owner
    // return _currentExperience.ownerUserId == _currentUserId; // OLD Check
    // NEW Check: See if current user ID is in the list of editors
    return _currentExperience.editorUserIds.contains(_currentUserId);
    // TODO: Add logic here later to check SharePermission for edit access
    // if (isOwner) return true;
    // else { Check share permissions... }
  }

  // ADDED: Method stub to show the edit modal
  Future<void> _showEditExperienceModal() async {
    if (!_canEditExperience() || _isLoadingCategories) {
      print(
          "Cannot edit: User doesn't have permission or categories not loaded.");
      return; // Prevent opening if not allowed or categories loading
    }

    final result = await showModalBottomSheet<Experience?>(
      context: context,
      isScrollControlled: true, // Important for keyboard handling
      shape: const RoundedRectangleBorder(
        // Optional: Rounded corners
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        // Pass the current experience and loaded categories
        return EditExperienceModal(
          experience: _currentExperience,
          userCategories: _userCategories,
        );
      },
    );

    // Handle the result from the modal
    if (result != null && mounted) {
      print("Edit modal returned updated experience. Saving...");
      // Optimistic update locally first? Or wait for save? Let's wait.
      setState(() {
        _isLoadingExperience = true; // Show loading indicator
      });
      try {
        // Save the updated experience using the service
        await _experienceService.updateExperience(result);

        // Refresh the full experience data on the screen
        await _refreshExperienceData(); // This handles setting loading state

        // Set flag for popping result
        setState(() {
          _didDataChange = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Experience updated successfully!')),
        );
      } catch (e) {
        print("Error saving updated experience: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving changes: $e')),
          );
          // Revert loading state if save fails
          setState(() {
            _isLoadingExperience = false;
          });
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

    return Container(
      height: headerHeight,
      child: Stack(
        children: [
          // 1. Background Image
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                image: experience.location.photoUrl != null
                    ? DecorationImage(
                        image: NetworkImage(experience.location.photoUrl!),
                        fit: BoxFit.cover,
                      )
                    : null, // No background image if URL is null
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
                  const SizedBox(height: 16), // Spacing below the top row

                  // Action Buttons (Centered)
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.center, // Center the buttons
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          // TODO: Implement Follow logic
                          print('Follow button pressed');
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Follow'),
                        style: ElevatedButton.styleFrom(
                          // Optional: Add styling if needed (e.g., minimumSize)
                          minimumSize:
                              Size(140, 36), // Give buttons some minimum width
                        ),
                      ),
                      const SizedBox(width: 16), // Space between buttons
                      ElevatedButton.icon(
                        onPressed: () {
                          // TODO: Implement Add to Itinerary logic
                          print('Add to Itinerary button pressed');
                        },
                        icon: const Icon(
                            Icons.calendar_today_outlined), // Itinerary icon
                        label: const Text('Add to Itinerary'),
                        style: ElevatedButton.styleFrom(
                          // Optional: Add styling if needed (e.g., minimumSize)
                          minimumSize:
                              Size(140, 36), // Give buttons some minimum width
                        ),
                      ),
                    ],
                  ),
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

    // Wrap main Scaffold with WillPopScope
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(_didDataChange);
        return false;
      },
      child: Scaffold(
        // Revert AppBar to be transparent and behind body
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: Container(
            // Keep custom leading button
            margin: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: BackButton(
              color: Colors.white,
              // Pop with the change status - Handled by WillPopScope + this button
              onPressed: () => Navigator.of(context).pop(_didDataChange),
            ),
          ),
          // Remove the explicit title added in the previous step
          title: null,
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pass _currentExperience to header builder
              _buildHeader(context, _currentExperience),
              const Divider(),
              // Build details section based on loading/error state
              _buildDynamicDetailsSection(context),
              const Divider(),
              // ADDED: Quick Actions Section
              _buildQuickActionsSection(
                  context, _placeDetailsData, _currentExperience.location),
              const Divider(),
              // ADDED: Tabbed Content Section
              _buildTabbedContentSection(context),
            ],
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

  // Helper method to build a single row in the details section
  Widget _buildDetailRow(
      BuildContext context, IconData icon, String label, String? value,
      {bool showLabel = true}) {
    // Don't build row if value is null or empty
    if (value == null || value.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
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
      if (reservableValue == null)
        return 'Not specified'; // Changed from Not available
      // Handle String 'true'/'false' in case toString() was used in getDetail
      if (reservableValue is String) {
        if (reservableValue.toLowerCase() == 'true')
          return 'Takes reservations';
        if (reservableValue.toLowerCase() == 'false') return 'No reservations';
      }
      if (reservableValue is bool) {
        return reservableValue ? 'Takes reservations' : 'No reservations';
      }
      // print('    ⚠️ formatReservable: Unexpected type, returning raw.');
      return reservableValue.toString(); // Fallback
    }

    // Formatting for Hours
    String formatHours(dynamic hoursValue) {
      // ADDED: Log input to formatter
      // print('    🔄 formatHours: Input value type: ${hoursValue?.runtimeType}');
      // Check if data is available and is a Map
      if (hoursValue == null || hoursValue is! Map) {
        // print('    ⚠️ formatHours: Input is null or not a Map.');
        return 'Not available';
      }

      // Prioritize weekday descriptions if available (most user-friendly)
      if (hoursValue.containsKey('weekdayDescriptions') &&
          hoursValue['weekdayDescriptions'] is List &&
          (hoursValue['weekdayDescriptions'] as List).isNotEmpty) {
        final descriptions =
            (hoursValue['weekdayDescriptions'] as List).join('\n');
        // print('    ✅ formatHours: Using weekdayDescriptions.');
        return descriptions;
      }

      // Fallback: Check openNow status if available
      if (hoursValue.containsKey('openNow') && hoursValue['openNow'] is bool) {
        final isOpen = hoursValue['openNow'] as bool;
        // print('    ✅ formatHours: Using openNow status ($isOpen).');
        return isOpen
            ? 'Open now (details unavailable)'
            : 'Closed now (details unavailable)';
      }
      // print('    ⚠️ formatHours: No useful hour info found in Map.');
      // If no useful info found
      return 'Hours details unavailable';
    }

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
    final formattedHours = formatHours(getDetail(
        'regularOpeningHours')); // Use regularOpeningHours if that's what fetchPlaceDetailsData requests
    final formattedStatus = getDetail('businessStatus');
    final formattedReservable = formatReservable(getDetail('reservable'));
    final formattedParking = formatParking(getDetail('parkingOptions'));

    // ADDED: Log formatted values before building UI
    // print('ℹ️ Building Details Section with Formatted Data:');
    // print('  - Description: $formattedDescription');
    // print('  - Hours: $formattedHours');
    // print('  - Status: $formattedStatus');
    // print('  - Reservable: $formattedReservable');
    // print('  - Parking: $formattedParking');

    // Get Yelp URL (handle null)
    final String? yelpUrl = experience.yelpUrl;
    // Determine if edit is allowed
    final bool canEdit = _canEditExperience();

    return Container(
      color: Colors.grey[100],
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
                        widget.category.icon, // Use widget.category
                        style: const TextStyle(fontSize: 20),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.category.name, // Use widget.category
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Colors.black87,
                            ),
                        overflow: TextOverflow.ellipsis, // Prevent overflow
                      ),
                    ],
                  ),
                ),

                // Buttons on the right
                // Yelp Button (Icon Only)
                ActionChip(
                  avatar: Icon(
                    FontAwesomeIcons.yelp,
                    color: yelpUrl != null && yelpUrl.isNotEmpty
                        ? const Color(0xFFd32323) // Yelp Red
                        : Colors.grey,
                    size: 18,
                  ),
                  label: const SizedBox.shrink(),
                  labelPadding: EdgeInsets.zero,
                  onPressed: yelpUrl != null && yelpUrl.isNotEmpty
                      ? () => _launchUrl(yelpUrl)
                      : null,
                  tooltip: yelpUrl != null && yelpUrl.isNotEmpty
                      ? 'Open Yelp Page'
                      : 'Yelp URL not available',
                  backgroundColor: Colors.white,
                  shape: StadiumBorder(
                      side: BorderSide(color: Colors.grey.shade300)),
                  materialTapTargetSize:
                      MaterialTapTargetSize.shrinkWrap, // Reduce tap area
                  padding: const EdgeInsets.all(4), // Adjust padding
                ),
                const SizedBox(width: 4), // Smaller spacing between buttons

                // Google Maps Button (Icon Only)
                ActionChip(
                  avatar: Icon(
                    Icons.map_outlined, // map icon
                    color: Theme.of(context).primaryColor,
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

                // --- ADDED Share Button ---
                ActionChip(
                  avatar: Icon(
                    Icons.share_outlined,
                    color: Colors.blue, // Or another appropriate color
                    size: 18,
                  ),
                  label: const SizedBox.shrink(),
                  labelPadding: EdgeInsets.zero,
                  onPressed: () {
                    // TODO: Implement Share functionality
                    print('Share button tapped');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('Share functionality not implemented yet.')),
                    );
                  },
                  tooltip: 'Share Experience',
                  backgroundColor: Colors.white,
                  shape: StadiumBorder(
                      side: BorderSide(color: Colors.grey.shade300)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.all(4),
                ),
                const SizedBox(width: 4), // Spacing

                // --- ADDED Edit Button ---
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
                // --- END Added Buttons ---
              ],
            ),
          ),
          _buildDetailRow(
            context,
            Icons.description_outlined,
            'Description',
            formattedDescription, // Use pre-formatted value
            showLabel: false, // HIDE label
          ),
          _buildDetailRow(
            context,
            Icons.location_on_outlined,
            'Location',
            experience.location.address,
            showLabel: false, // HIDE label
          ),
          _buildStatusRow(context, getDetail('businessStatus')),
          _buildExpandableHoursRow(
            context,
            getDetail('regularOpeningHours'), // Pass hours data
            getDetail(
                'businessStatus'), // Pass status for coloring (still needed for hours row)
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
          // --- ADDED Notes Row ---
          _buildDetailRow(
            context,
            Icons.notes, // CHANGED Icon to match modal
            'Notes',
            experience.additionalNotes, // Use the field directly
            showLabel: false, // HIDE label
          ),
          // --- END Notes Row ---
        ],
      ),
    );
  }

  // --- ADDED: New Widget/Helper for Status Row ---
  Widget _buildStatusRow(BuildContext context, dynamic statusValue) {
    String statusText = 'Status unknown';
    Color statusColor = Colors.grey;
    bool isVisible = statusValue != null;

    if (statusValue is String) {
      switch (statusValue) {
        case 'OPERATIONAL':
          statusText = 'Open';
          statusColor = Colors.green[700]!;
          break;
        case 'CLOSED_TEMPORARILY':
          statusText = 'Closed Temporarily';
          statusColor = Colors.red[700]!;
          break;
        case 'CLOSED_PERMANENTLY':
          statusText = 'Closed Permanently';
          statusColor = Colors.red[700]!;
          break;
        default:
          statusText = statusValue; // Display unknown status raw
          break;
      }
    } else if (statusValue != null) {
      statusText = statusValue.toString(); // Fallback for unexpected type
    }

    // Only build the row if the status is known
    if (!isVisible) return const SizedBox.shrink();

    // Use _buildDetailRow structure but apply custom text and color
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
                    text: statusText,
                    style: TextStyle(
                        color: statusColor, fontWeight: FontWeight.bold),
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
  Widget _buildExpandableHoursRow(
      BuildContext context, dynamic hoursData, String? businessStatus) {
    // --- Helper Logic within the build method ---
    final bool isOperational = businessStatus == 'OPERATIONAL';
    final Color statusColor =
        isOperational ? Colors.green[700]! : Colors.red[700]!;
    List<String>? descriptions;
    String todayString = 'Hours details unavailable';
    int currentWeekday = DateTime.now().weekday; // 1=Mon, 7=Sun

    // Adjust to match Google's likely Sunday=0 or Sunday=start index
    // This depends on the exact format in weekdayDescriptions.
    // Assuming Sunday is the first entry:
    int googleWeekdayIndex = (currentWeekday % 7); // Sun=0, Mon=1, ... Sat=6

    if (hoursData is Map &&
        hoursData.containsKey('weekdayDescriptions') &&
        hoursData['weekdayDescriptions'] is List &&
        (hoursData['weekdayDescriptions'] as List).isNotEmpty) {
      descriptions = (hoursData['weekdayDescriptions'] as List).cast<String>();
      if (descriptions.length > googleWeekdayIndex) {
        todayString = descriptions[googleWeekdayIndex];
      } else {
        todayString = 'Today\'s hours unavailable'; // Data length mismatch
      }
    } else if (hoursData is Map &&
        hoursData.containsKey('openNow') &&
        hoursData['openNow'] is bool) {
      // Fallback if only openNow is available
      todayString = hoursData['openNow']
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
    // Filter media paths for Instagram URLs to get the count
    final instagramMediaPaths = (_currentExperience.sharedMediaPaths ?? [])
        .where((path) => path.toLowerCase().contains('instagram.com'))
        .toList();
    final mediaCount = instagramMediaPaths.length; // Count only Instagram posts
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
        TabBar(
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
        SizedBox(
          height: tabContentHeight,
          child: TabBarView(
            controller: _tabController,
            children: [
              // Pass all paths, filtering happens inside _buildMediaTab
              _buildMediaTab(context, _currentExperience.sharedMediaPaths),
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
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content:
              const Text('Are you sure you want to remove this media item?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false), // Return false
            ),
            TextButton(
              child: const Text('Delete'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true), // Return true
            ),
          ],
        );
      },
    );

    // Proceed only if confirmed (confirm == true)
    if (confirm == true) {
      try {
        // Create a mutable copy and remove the URL
        final List<String> updatedPaths =
            List<String>.from(_currentExperience.sharedMediaPaths ?? []);
        bool removed = updatedPaths.remove(urlToDelete);

        if (removed) {
          // Create the updated experience object
          Experience updatedExperience = _currentExperience.copyWith(
            sharedMediaPaths: updatedPaths,
            updatedAt: DateTime.now(), // Update timestamp
          );

          // Update in the backend
          await _experienceService.updateExperience(updatedExperience);

          // Refresh the local state
          await _refreshExperienceData();
          // Set flag to signal change on pop
          setState(() {
            _didDataChange = true;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Media item removed.')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: Media item not found.')),
          );
        }
      } catch (e) {
        print("Error deleting media path: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing media item: $e')),
        );
      }
    }
  }

  // Builds the Media Tab, now including a fullscreen button
  Widget _buildMediaTab(BuildContext context, List<String>? mediaPaths) {
    // Filter for Instagram URLs first
    final instagramUrls = (mediaPaths ?? [])
        .where((path) => path.toLowerCase().contains('instagram.com'))
        .toList();

    // Reverse the list to show most recently added first
    final reversedInstagramUrls = instagramUrls.reversed.toList();

    // Use the reversed list for checking emptiness
    if (reversedInstagramUrls.isEmpty) {
      return const Center(
          child: Text('No Instagram posts shared for this experience.'));
    }

    // Return a Column containing the button and the list
    return Column(
      children: [
        // Fullscreen Button
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.fullscreen, size: 20.0),
              label: const Text('View Fullscreen'),
              style: TextButton.styleFrom(
                // Optional: Adjust text style/padding
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: TextStyle(fontSize: 13),
              ),
              onPressed: () async {
                // Make onPressed async
                // Navigate and wait for result
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MediaFullscreenScreen(
                      instagramUrls: reversedInstagramUrls,
                      launchUrlCallback: _launchUrl,
                      // Pass _currentExperience and service
                      experience: _currentExperience,
                      experienceService: _experienceService,
                    ),
                  ),
                );
                // Refresh data if fullscreen indicated deletion
                if (result == true && mounted) {
                  await _refreshExperienceData();
                  // Set flag to signal change on pop
                  setState(() {
                    _didDataChange = true;
                  });
                }
              },
            ),
          ),
        ),
        // The scrollable list (needs Expanded to fill remaining space)
        Expanded(
          child: ListView.builder(
            // Removed vertical padding, handled by Column/Button padding
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            // Use the reversed list length
            itemCount: reversedInstagramUrls.length,
            itemBuilder: (context, index) {
              // Use the reversed list to get URL
              final url = reversedInstagramUrls[index];
              // Use a Column to place the number above the card
              return Padding(
                padding: const EdgeInsets.only(bottom: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Display the number inside a bubble
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor:
                            Theme.of(context).primaryColor.withOpacity(0.8),
                        child: Text(
                          // Display index sequentially starting from 1
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 14.0,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    // The Card containing the preview
                    Card(
                      margin: EdgeInsets.zero,
                      elevation: 2.0,
                      clipBehavior: Clip.antiAlias,
                      child: instagram_widget.InstagramWebView(
                        url: url,
                        height: 840.0, // Use fixed height
                        launchUrlCallback: _launchUrl,
                        // Add required callbacks (can be empty if not needed)
                        onWebViewCreated: (controller) {},
                        onPageFinished: (url) {},
                      ),
                    ),
                    // Add spacing before buttons
                    const SizedBox(height: 8),
                    // Buttons Row - REFRACTORED to use Stack for centering
                    SizedBox(
                      height:
                          48, // Provide height constraint for Stack alignment
                      child: Stack(
                        children: [
                          // Instagram Button (Centered)
                          Align(
                            alignment: Alignment.center, // Alignment(0.0, 0.0)
                            child: IconButton(
                              icon: const Icon(FontAwesomeIcons.instagram),
                              color: const Color(0xFFE1306C), // Instagram color
                              iconSize: 32, // Standard size
                              tooltip: 'Open in Instagram',
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                              onPressed: () => _launchUrl(url),
                            ),
                          ),
                          // Delete Button (Right Edge)
                          Align(
                            alignment:
                                Alignment.centerRight, // Alignment(1.0, 0.0)
                            child: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              iconSize: 24,
                              color: Colors.red[700],
                              tooltip: 'Delete Media',
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.symmetric(
                                  horizontal:
                                      12), // Keep some padding from edge
                              onPressed: () =>
                                  _deleteMediaPath(url), // Call delete function
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Builds the Reviews Tab ListView
  Widget _buildReviewsTab(BuildContext context) {
    if (_isLoadingReviews) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_reviews.isEmpty) {
      return const Center(child: Text('No reviews yet.'));
    }

    return ListView.builder(
      itemCount: _reviews.length,
      itemBuilder: (context, index) {
        final review = _reviews[index];
        // TODO: Create a proper ReviewListItem widget
        return ListTile(
          leading: CircleAvatar(child: Text(review.rating.toStringAsFixed(1))),
          title: Text(review.content),
          subtitle: Text(
              'By: ${review.userName ?? review.userId} - ${review.createdAt.toLocal()}'),
        );
      },
    );
  }

  // Builds the Comments Tab ListView
  Widget _buildCommentsTab(BuildContext context) {
    if (_isLoadingComments) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_comments.isEmpty) {
      return const Center(child: Text('No comments yet.'));
    }

    return ListView.builder(
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
    // Safely get phone number and website from details
    final String? phoneNumber = placeDetails?['nationalPhoneNumber'];
    final String? websiteUri = placeDetails?['websiteUri'];

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

  // --- ADDED: Helper method to launch map location --- //
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
}
