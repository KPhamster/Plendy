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
import 'receive_share/widgets/instagram_preview_widget.dart';
// REMOVED: Dio import (no longer needed for thumbnail fetching)
// import 'package:dio/dio.dart';
// REMOVED: Dotenv import (no longer needed for credentials)
// import 'package:flutter_dotenv/flutter_dotenv.dart';

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
  // REMOVED: Dio instance
  // final _dio = Dio();

  // REMOVED: Instagram Credentials
  // String? _instagramAppId;
  // String? _instagramClientToken;

  // REMOVED: Thumbnail Cache
  // final Map<String, String?> _thumbnailCache = {};

  @override
  void initState() {
    super.initState();
    _tabController =
        TabController(length: 3, vsync: this); // Initialize TabController
    // REMOVED: Call to load Instagram credentials
    // _loadInstagramCredentials();
    _fetchPlaceDetails();
    _fetchReviews(); // Fetch reviews on init
    _fetchComments(); // Fetch comments on init
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
    final placeId = widget.experience.location.placeId;
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
          .getReviewsForExperience(widget.experience.id);
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
          .getCommentsForExperience(widget.experience.id);
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
                                children: [
                                  RatingBarIndicator(
                                    rating: experience
                                        .plendyRating, // Use Plendy rating
                                    itemBuilder: (context, index) => const Icon(
                                      Icons.star,
                                      color: Colors.amber,
                                    ),
                                    unratedColor: Colors.white.withOpacity(0.4),
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

          // 4. Back Button (Positioned top-left)
          Positioned(
            top: MediaQuery.of(context)
                .padding
                .top, // Consider status bar height
            left: 8.0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              margin: const EdgeInsets.all(4.0), // Margin around the circle
              child: BackButton(
                color: Colors.white, // Make sure back button is visible
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pass experience from widget to header builder
            _buildHeader(context, widget.experience),
            const Divider(),
            // Build details section based on loading/error state
            _buildDynamicDetailsSection(context),
            const Divider(),
            // ADDED: Quick Actions Section
            _buildQuickActionsSection(
                context, _placeDetailsData, widget.experience.location),
            const Divider(),
            // ADDED: Tabbed Content Section
            _buildTabbedContentSection(context),
          ],
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
    return _buildDetailsSection(context, widget.experience, _placeDetailsData);
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
      print(
          '  🔍 getDetail: Looking for key "$key". placeDetails is ${placeDetails == null ? 'NULL' : 'NOT NULL'}');

      if (placeDetails == null) return null;

      final value = placeDetails[key];
      // ADDED: Log the found value (or lack thereof)
      print(
          '  🔍 getDetail: Found value for "$key": ${value == null ? 'NULL' : value.runtimeType}');

      // Basic check for nested text field (like editorialSummary)
      if (key == 'editorialSummary' &&
          value is Map &&
          value.containsKey('text')) {
        print('  🔍 getDetail: Extracted text for editorialSummary');
        return value['text'] as String?;
      }

      // For other fields, return the raw value
      return value;
    }

    // Basic formatting for boolean reservable field
    String formatReservable(dynamic reservableValue) {
      // ADDED: Log input to formatter
      print(
          '    🔄 formatReservable: Input value: $reservableValue (${reservableValue?.runtimeType})');
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
      print('    ⚠️ formatReservable: Unexpected type, returning raw.');
      return reservableValue.toString(); // Fallback
    }

    // Formatting for Hours
    String formatHours(dynamic hoursValue) {
      // ADDED: Log input to formatter
      print('    🔄 formatHours: Input value type: ${hoursValue?.runtimeType}');
      // Check if data is available and is a Map
      if (hoursValue == null || hoursValue is! Map) {
        print('    ⚠️ formatHours: Input is null or not a Map.');
        return 'Not available';
      }

      // Prioritize weekday descriptions if available (most user-friendly)
      if (hoursValue.containsKey('weekdayDescriptions') &&
          hoursValue['weekdayDescriptions'] is List &&
          (hoursValue['weekdayDescriptions'] as List).isNotEmpty) {
        final descriptions =
            (hoursValue['weekdayDescriptions'] as List).join('\n');
        print('    ✅ formatHours: Using weekdayDescriptions.');
        return descriptions;
      }

      // Fallback: Check openNow status if available
      if (hoursValue.containsKey('openNow') && hoursValue['openNow'] is bool) {
        final isOpen = hoursValue['openNow'] as bool;
        print('    ✅ formatHours: Using openNow status ($isOpen).');
        return isOpen
            ? 'Open now (details unavailable)'
            : 'Closed now (details unavailable)';
      }
      print('    ⚠️ formatHours: No useful hour info found in Map.');
      // If no useful info found
      return 'Hours details unavailable';
    }

    // Formatting for Parking
    String formatParking(dynamic parkingValue) {
      // ADDED: Log input to formatter
      print(
          '    🔄 formatParking: Input value type: ${parkingValue?.runtimeType}');
      // Check if data is available and is a Map
      if (parkingValue == null || parkingValue is! Map) {
        print('    ⚠️ formatParking: Input is null or not a Map.');
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
        print(
            '    ⚠️ formatParking: No specific parking options found in Map.');
        return 'Parking details not specified';
      }

      final result = options.join(', ');
      print('    ✅ formatParking: Formatted result: $result');
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
    print('ℹ️ Building Details Section with Formatted Data:');
    print('  - Description: $formattedDescription');
    print('  - Hours: $formattedHours');
    print('  - Status: $formattedStatus');
    print('  - Reservable: $formattedReservable');
    print('  - Parking: $formattedParking');

    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
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
                ),
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
    final instagramMediaPaths = (widget.experience.sharedMediaPaths ?? [])
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
              _buildMediaTab(context, widget.experience.sharedMediaPaths),
              _buildReviewsTab(context),
              _buildCommentsTab(context),
            ],
          ),
        ),
      ],
    );
  }

  // Builds the Media Tab as a List of Instagram Previews
  Widget _buildMediaTab(BuildContext context, List<String>? mediaPaths) {
    // Filter for Instagram URLs
    final instagramUrls = (mediaPaths ?? [])
        .where((path) => path.toLowerCase().contains('instagram.com'))
        .toList();

    if (instagramUrls.isEmpty) {
      return const Center(
          child: Text('No Instagram posts shared for this experience.'));
    }

    // Display InstagramPreviewWidgets in a ListView
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
          vertical: 8.0, horizontal: 16.0), // Add some padding
      itemCount: instagramUrls.length,
      itemBuilder: (context, index) {
        final url = instagramUrls[index];
        // Return the InstagramPreviewWidget for each URL
        // Add padding below each widget for spacing
        return Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: InstagramPreviewWidget(
            url: url,
            // Pass the existing _launchUrl helper method
            launchUrlCallback: _launchUrl,
          ),
        );
      },
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
}
