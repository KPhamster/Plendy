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

class _ExperiencePageScreenState extends State<ExperiencePageScreen> {
  // TODO: Define state variables for PlaceDetails and loading state
  // PlaceDetails? _placeDetails;
  bool _isLoadingDetails = true;
  String? _errorLoadingDetails;
  // ADDED: State for hours expansion
  bool _isHoursExpanded = false;

  // TODO: Instantiate your PlacesService
  // final _placesService = PlacesService();
  // ADDED: Instantiate GoogleMapsService
  final _googleMapsService = GoogleMapsService();

  @override
  void initState() {
    super.initState();
    _fetchPlaceDetails();
  }

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

  // Simulated place details data (replace with actual PlaceDetails model instance)
  Map<String, dynamic>? _placeDetailsData;

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
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                  '// TODO: Add Quick Actions, Tabs...'), // Updated placeholder
            )
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
        if (reservableValue.toLowerCase() == 'true') return 'Takes reservations';
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
}
