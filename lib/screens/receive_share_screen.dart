import 'package:flutter/material.dart';
import 'dart:math';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:any_link_preview/any_link_preview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../models/experience.dart';
import '../services/experience_service.dart';
import '../services/google_maps_service.dart';
import '../widgets/google_maps_widget.dart';
import 'location_picker_screen.dart';
import '../services/sharing_service.dart';
import 'dart:async';
import 'package:http/http.dart' as http;

/// Data class to hold the state of each experience card
class ExperienceCardData {
  // Form controllers
  final TextEditingController titleController = TextEditingController();
  final TextEditingController yelpUrlController = TextEditingController();
  final TextEditingController websiteUrlController = TextEditingController();
  final TextEditingController searchController = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController categoryController = TextEditingController();

  // Form key
  final formKey = GlobalKey<FormState>();

  // Focus nodes
  final FocusNode titleFocusNode = FocusNode();

  // Experience type selection
  ExperienceType selectedType = ExperienceType.restaurant;

  // Location selection
  Location? selectedLocation;
  Location? location;
  bool isSelectingLocation = false;
  bool locationEnabled = true;
  List<Map<String, dynamic>> searchResults = [];

  // State variable for card
  bool isExpanded = true;

  // Unique identifier for this card
  final String id = DateTime.now().millisecondsSinceEpoch.toString();

  // Constructor can set initial values if needed
  ExperienceCardData();

  // Dispose resources
  void dispose() {
    titleController.dispose();
    yelpUrlController.dispose();
    websiteUrlController.dispose();
    searchController.dispose();
    locationController.dispose();
    categoryController.dispose();
    titleFocusNode.dispose();
  }
}

class ReceiveShareScreen extends StatefulWidget {
  final List<SharedMediaFile> sharedFiles;
  final VoidCallback onCancel;

  const ReceiveShareScreen({
    super.key,
    required this.sharedFiles,
    required this.onCancel,
  });

  @override
  _ReceiveShareScreenState createState() => _ReceiveShareScreenState();
}

class _ReceiveShareScreenState extends State<ReceiveShareScreen>
    with WidgetsBindingObserver {
  // Services
  final ExperienceService _experienceService = ExperienceService();
  final GoogleMapsService _mapsService = GoogleMapsService();
  final SharingService _sharingService = SharingService();

  // Experience card data structure
  List<ExperienceCardData> _experienceCards = [];

  // Track filled business data to avoid duplicates but also cache results
  Map<String, Map<String, dynamic>> _businessDataCache = {};

  // Form validation key
  final _formKey = GlobalKey<FormState>();

  // Loading state
  bool _isSaving = false;

  // Snackbar controller to manage notifications
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _activeSnackBar;

  // Add a map to cache futures for Yelp preview data
  final Map<String, Future<Map<String, dynamic>?>> _yelpPreviewFutures = {};

  // Method to show snackbar only if not already showing
  void _showSnackBar(BuildContext context, String message) {
    // Hide any existing snackbar first
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    // Show new snackbar
    _activeSnackBar = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void initState() {
    super.initState();
    // Register observer for app lifecycle events
    WidgetsBinding.instance.addObserver(this);
    // Add first experience card
    _addExperienceCard();

    // Automatically process any Yelp URLs in the shared content
    _processSharedContent();

    // Ensure the intent is reset when screen is shown
    ReceiveSharingIntent.instance.reset();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // If app resumes from background, reset sharing intent to be ready for new shares
    if (state == AppLifecycleState.resumed) {
      _sharingService.resetSharedItems();
    }
  }

  @override
  void dispose() {
    // Unregister observer
    WidgetsBinding.instance.removeObserver(this);
    // Make sure intent is fully reset when screen closes
    _sharingService.resetSharedItems();
    // Dispose all controllers for all experience cards
    for (var card in _experienceCards) {
      card.dispose();
    }
    super.dispose();
  }

  // Register for new shares while this screen is open
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Reset intent when screen first loads to clear any stale data
    ReceiveSharingIntent.instance.reset();

    // Listen for new shares that might come in while screen is already open
    _sharingService.sharedFiles.addListener(() {
      final newSharedFiles = _sharingService.sharedFiles.value;
      if (newSharedFiles != null && newSharedFiles.isNotEmpty && mounted) {
        // Refresh this screen with the new data
        setState(() {
          // Reset current data
          for (var card in _experienceCards) {
            card.dispose();
          }
          _experienceCards.clear();
          _addExperienceCard();

          // Process the new content
          _processSharedContent();
        });
      }
    });
  }

  // WillPopScope wrapper to ensure proper cleanup on back button press
  Widget _wrapWithWillPopScope(Widget child) {
    return WillPopScope(
      onWillPop: () async {
        // Make sure intent is reset before closing screen
        _sharingService.resetSharedItems();
        return true;
      },
      child: child,
    );
  }

  // Process shared content to extract Yelp URLs or Map URLs
  void _processSharedContent() {
    print('DEBUG: Processing shared content');
    if (widget.sharedFiles.isEmpty) return;

    // Look for Yelp URLs or Map URLs in shared files
    for (final file in widget.sharedFiles) {
      if (file.type == SharedMediaType.text) {
        String text = file.path;
        print(
            'DEBUG: Checking shared text: ${text.substring(0, min(100, text.length))}...');

        // Check if this is a special URL (Yelp or Maps)
        if (_isTextSpecialContent(text)) {
          print('DEBUG: Found special content URL: $text');
          _processSpecialUrl(text);
          return;
        }

        // Check for "Check out X on Yelp" message format
        if (text.contains('Check out') && text.contains('yelp.to/')) {
          // Extract URL using regex to get the Yelp link
          final RegExp urlRegex = RegExp(r'https?://yelp.to/[^\s]+');
          final match = urlRegex.firstMatch(text);
          if (match != null) {
            final extractedUrl = match.group(0);
            print('DEBUG: Extracted Yelp URL from share text: $extractedUrl');
            if (extractedUrl != null) {
              _getBusinessFromYelpUrl(extractedUrl);
              return;
            }
          }
        } else if (text.contains('\n')) {
          // Check for multi-line text with URL on separate line
          final lines = text.split('\n');
          for (final line in lines) {
            if (_isTextSpecialContent(line)) {
              print('DEBUG: Found special URL in multi-line text: $line');
              _processSpecialUrl(line);
              return;
            }
          }
        }
      }
    }
  }

  // Check if the shared content is from Yelp or Google Maps
  bool _isSpecialContent() {
    if (widget.sharedFiles.isEmpty) return false;

    for (final file in widget.sharedFiles) {
      if (file.type == SharedMediaType.text) {
        String text = file.path;
        if (_isValidUrl(text)) {
          return text.contains('yelp.com/biz') ||
              text.contains('yelp.to/') ||
              text.contains('google.com/maps') ||
              text.contains('maps.app.goo.gl') ||
              text.contains('goo.gl/maps');
        }
      }
    }
    return false;
  }

  // Process special URL
  void _processSpecialUrl(String url) {
    if (url.contains('yelp.com/biz') || url.contains('yelp.to/')) {
      _getBusinessFromYelpUrl(url);
    } else if (url.contains('google.com/maps') ||
        url.contains('maps.app.goo.gl') ||
        url.contains('goo.gl/maps')) {
      // Use an async function to properly await the result
      _processGoogleMapsUrl(url);
    }
  }

  // Helper method to process Google Maps URLs asynchronously
  Future<void> _processGoogleMapsUrl(String url) async {
    try {
      // Show loading state if desired
      setState(() {
        // You could set a loading flag here if needed
      });

      // Wait for the map data to be retrieved
      final mapData = await _getLocationFromMapsUrl(url);

      // Verify we got data back
      if (mapData != null && mapData['location'] != null) {
        final location = mapData['location'] as Location;
        final placeName = mapData['placeName'] as String? ?? 'Shared Location';
        final websiteUrl = mapData['website'] as String? ?? '';

        // Fill the form with the retrieved data
        _fillFormWithGoogleMapsData(location, placeName, websiteUrl);

        // Show success message
        _showSnackBar(context, 'Location added from Google Maps');
      } else {
        print('🗺️ MAPS ERROR: Failed to extract location data from URL');
        // Show error message if desired
        _showSnackBar(
            context, 'Could not extract location data from the shared URL');
      }
    } catch (e) {
      print('🗺️ MAPS ERROR: Error processing Maps URL: $e');
      // Show error message
      _showSnackBar(context, 'Error processing Google Maps URL');
    }
  }

  // Add a new experience card
  void _addExperienceCard() {
    setState(() {
      _experienceCards.add(ExperienceCardData());
    });
  }

  // Remove an experience card
  void _removeExperienceCard(ExperienceCardData card) {
    setState(() {
      _experienceCards.remove(card);
      // If all cards are removed, add a new one
      if (_experienceCards.isEmpty) {
        _addExperienceCard();
      }
    });
  }

  /// Extract business data from a Yelp URL and look it up in Google Places API
  Future<Map<String, dynamic>?> _getBusinessFromYelpUrl(String yelpUrl) async {
    print("\n📊 YELP DATA: Starting business lookup for URL: $yelpUrl");

    // Create a cache key for this URL
    final cacheKey = yelpUrl.trim();

    // Check if we've already processed and cached this URL
    if (_businessDataCache.containsKey(cacheKey)) {
      print(
          '📊 YELP DATA: URL $cacheKey already processed, returning cached data');
      final cachedData = _businessDataCache[cacheKey];
      print(
          '📊 YELP DATA: Cache hit! Data: ${cachedData != null && cachedData.isNotEmpty ? "Has business data" : "Empty map (no results)"}');
      return _businessDataCache[cacheKey];
    }

    String url = yelpUrl.trim();

    // Make sure it's a properly formatted URL
    if (url.isEmpty) {
      print('📊 YELP DATA: Empty URL, aborting');
      return null;
    } else if (!url.startsWith('http')) {
      url = 'https://' + url;
      print('📊 YELP DATA: Added https:// to URL: $url');
    }

    // Check if this is a Yelp URL
    bool isYelpUrl = url.contains('yelp.com') || url.contains('yelp.to');
    if (!isYelpUrl) {
      print('📊 YELP DATA: Not a Yelp URL, aborting');
      return null;
    }

    print('📊 YELP DATA: Processing Yelp URL: $url');

    try {
      // Extract business info from URL and share context
      String businessName = "";
      String businessCity = "";
      String businessType = "";
      String fullSearchText = "";

      // 1. First try to extract from the message text if it's a "Check out X on Yelp" format
      if (widget.sharedFiles.isNotEmpty) {
        print('📊 YELP DATA: Examining shared text for business info');
        for (final file in widget.sharedFiles) {
          if (file.type == SharedMediaType.text) {
            final text = file.path;
            print(
                '📊 YELP DATA: Shared text: ${text.length > 50 ? text.substring(0, 50) + "..." : text}');

            // "Check out X on Yelp!" format
            if (text.contains('Check out') && text.contains('!')) {
              fullSearchText = text.split('Check out ')[1].split('!')[0].trim();
              businessName = fullSearchText;
              print(
                  '📊 YELP DATA: Extracted business name from share text: $businessName');

              // Try to extract city name if present (common format: "Business Name - City")
              if (businessName.contains('-')) {
                final parts = businessName.split('-');
                if (parts.length >= 2) {
                  businessName = parts[0].trim();
                  businessCity = parts[1].trim();
                  print('📊 YELP DATA: Extracted city: $businessCity');
                }
              }
              break;
            }
          }
        }
      }

      // 2. If we couldn't get it from the share text, try the URL
      if (businessName.isEmpty && url.contains('/biz/')) {
        // Extract the business part from URL
        // Format: https://www.yelp.com/biz/business-name-location
        final bizPath = url.split('/biz/')[1].split('?')[0];

        print('📊 YELP DATA: Extracting from biz URL path: $bizPath');

        // Convert hyphenated business name to spaces
        businessName = bizPath.split('-').join(' ');

        // If there's a location suffix at the end (like "restaurant-city"), try to extract it
        if (businessName.contains('/')) {
          final parts = businessName.split('/');
          businessName = parts[0];

          // Remaining parts might have city or business type info
          if (parts.length > 1) {
            // The last part is often a city
            businessCity = parts[parts.length - 1];
            print('📊 YELP DATA: Extracted city from URL path: $businessCity');
          }
        }

        print(
            '📊 YELP DATA: Extracted business name from URL path: $businessName');

        // Try to extract business type from hyphenated biz name (common pattern)
        final nameParts = businessName.split(' ');
        if (nameParts.length > 1) {
          // Last word might be business type (e.g., "restaurant", "cafe", etc.)
          final lastWord = nameParts[nameParts.length - 1].toLowerCase();
          if (['restaurant', 'cafe', 'bar', 'grill', 'bakery', 'coffee']
              .contains(lastWord)) {
            businessType = lastWord;
            print('📊 YELP DATA: Extracted business type: $businessType');
          }
        }
      }

      // If we couldn't extract a business name, use a generic one
      if (businessName.isEmpty) {
        businessName = "Shared Business";
        print('📊 YELP DATA: Using generic business name');
      }

      // Create search strategies in order of most to least specific
      List<String> searchQueries = [];

      // Strategy 1: Complete share text if available
      if (fullSearchText.isNotEmpty) {
        searchQueries.add(fullSearchText);
      }

      // Strategy 2: Business name + city if both available
      if (businessName.isNotEmpty && businessCity.isNotEmpty) {
        searchQueries.add('$businessName $businessCity');
      }

      // Strategy 3: Business name + business type if both available
      if (businessName.isNotEmpty && businessType.isNotEmpty) {
        searchQueries.add('$businessName $businessType');
      }

      // Strategy 4: Just business name
      if (businessName.isNotEmpty) {
        searchQueries.add(businessName);
      }

      // Deduplicate search queries
      searchQueries = searchQueries.toSet().toList();

      print('📊 YELP DATA: Search strategies (in order): $searchQueries');

      // Try each search query until we get results
      for (final query in searchQueries) {
        print('📊 YELP DATA: Trying Google Places with query: "$query"');

        // Using Google Places API to search for this business
        final results = await _mapsService.searchPlaces(query);
        print(
            '📊 YELP DATA: Got ${results.length} search results from Google Places for query "$query"');

        if (results.isNotEmpty) {
          print(
              '📊 YELP DATA: Results found! First result: ${results[0]['description']}');

          // Get details of the first result
          final placeId = results[0]['placeId'];
          print('📊 YELP DATA: Getting details for place ID: $placeId');

          final location = await _mapsService.getPlaceDetails(placeId);
          print(
              '📊 YELP DATA: Retrieved location details: ${location.displayName}, ${location.address}');
          print(
              '📊 YELP DATA: Coordinates: ${location.latitude}, ${location.longitude}');
          print('📊 YELP DATA: Place ID: ${location.placeId}');

          if (location.latitude == 0.0 && location.longitude == 0.0) {
            print(
                '📊 YELP DATA: WARNING - Zero coordinates returned, likely invalid location');
            continue; // Try the next search strategy
          }

          // Create the result data
          Map<String, dynamic> resultData = {
            'location': location,
            'businessName': businessName,
            'yelpUrl': url,
          };

          // Cache the result data
          _businessDataCache[cacheKey] = resultData;

          // Autofill the form data
          _fillFormWithBusinessData(location, businessName, url);

          print('📊 YELP DATA: Successfully found and processed business data');

          return resultData;
        }
      }

      print(
          '📊 YELP DATA: No results found after trying all search strategies');
      // Store empty map instead of null to prevent repeated processing
      _businessDataCache[cacheKey] = {};
      return null;
    } catch (e) {
      print('📊 YELP DATA ERROR: Error extracting business from Yelp URL: $e');
      return null;
    }
  }

  // Helper method to fill the form with business data
  void _fillFormWithBusinessData(
      Location location, String businessName, String yelpUrl) {
    final String businessKey = '${location.latitude},${location.longitude}';

    // Update UI
    setState(() {
      for (var card in _experienceCards) {
        // Set data in the card
        print(
            'DEBUG: Setting card data - title: ${location.displayName ?? businessName}');
        card.titleController.text = location.displayName ?? businessName;
        card.selectedLocation = location;
        card.yelpUrlController.text = yelpUrl;
        card.searchController.text = location.address ?? '';
      }
    });

    // Success message removed
  }

  // Helper method to fill the form with Google Maps data
  void _fillFormWithGoogleMapsData(
      Location location, String placeName, String websiteUrl) {
    final String locationKey = '${location.latitude},${location.longitude}';

    // Update UI
    setState(() {
      for (var card in _experienceCards) {
        // Set data in the card
        print(
            '🗺️ MAPS: Setting card data - title: ${location.displayName ?? placeName}');
        card.titleController.text = location.displayName ?? placeName;
        card.selectedLocation = location;
        card.websiteUrlController.text =
            websiteUrl; // Set official website if available
        card.searchController.text = location.address ?? '';
      }
    });

    // Show success message (optional)
    // ScaffoldMessenger.of(context).showSnackBar(
    //   SnackBar(content: Text('Location data filled automatically')),
    // );
  }

  // Handle experience save along with shared content
  Future<void> _saveExperience() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please fill in required fields correctly')),
      );
      return;
    }

    // Check for required locations in all cards
    for (int i = 0; i < _experienceCards.length; i++) {
      final card = _experienceCards[i];
      if (card.locationEnabled && card.selectedLocation == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Please select a location for experience ${i + 1}')),
        );
        return;
      }
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final now = DateTime.now();

      // Save each experience
      for (final card in _experienceCards) {
        // Create a default empty location if location is disabled
        final Location defaultLocation = Location(
          latitude: 0.0,
          longitude: 0.0,
          address: 'No location specified',
        );

        final newExperience = Experience(
          id: '', // ID will be assigned by Firestore
          name: card.titleController.text,
          description: 'Created from shared content',
          location: card.locationEnabled
              ? card.selectedLocation!
              : defaultLocation, // Use default when disabled
          type: card.selectedType,
          yelpUrl: card.yelpUrlController.text.isNotEmpty
              ? card.yelpUrlController.text
              : null,
          website: card.websiteUrlController.text.isNotEmpty
              ? card.websiteUrlController.text
              : null,
          createdAt: now,
          updatedAt: now,
        );

        // Save the experience to Firestore
        await _experienceService.createExperience(newExperience);
      }

      // TODO: Add code to save the shared media files appropriately
      // For example, if they're images, upload them as photos for the experience
      // If they're links, associate them with the experience

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Experiences created successfully')),
      );

      // Return to the main screen
      widget.onCancel();
    } catch (e) {
      print('Error saving experiences: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating experiences: $e')),
      );
      setState(() {
        _isSaving = false;
      });
    }
  }

  // Use GoogleMapsService for places search for a specific card
  Future<void> _searchPlaces(String query, ExperienceCardData card) async {
    if (query.isEmpty) {
      setState(() {
        card.searchResults = [];
      });
      return;
    }

    setState(() {
      card.isSelectingLocation = true;
    });

    try {
      final results = await _mapsService.searchPlaces(query);

      setState(() {
        card.searchResults = results;
      });
    } catch (e) {
      print('Error searching places: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error searching places')),
      );
    } finally {
      setState(() {
        card.isSelectingLocation = false;
      });
    }
  }

  // Get place details using GoogleMapsService for a specific card
  Future<void> _selectPlace(String placeId, ExperienceCardData card) async {
    setState(() {
      card.isSelectingLocation = true;
    });

    try {
      final location = await _mapsService.getPlaceDetails(placeId);

      setState(() {
        card.selectedLocation = location;
        card.searchController.text = location.address ?? '';
      });
    } catch (e) {
      print('Error getting place details: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error selecting location')),
      );
    } finally {
      setState(() {
        card.isSelectingLocation = false;
      });
    }
  }

  // Use the LocationPickerScreen for a specific experience card
  Future<void> _showLocationPicker(ExperienceCardData card) async {
    // Unfocus all fields before showing the location picker
    FocusScope.of(context).unfocus();

    final Location? result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          initialLocation: card.selectedLocation,
          onLocationSelected: (location) {
            // This is just a placeholder during the picker's lifetime
            // The actual result is returned via Navigator.pop
          },
        ),
      ),
    );

    if (result != null) {
      // Immediately unfocus after return - outside of setState to ensure it happens right away
      FocusScope.of(context).unfocus();

      setState(() {
        card.selectedLocation = result;
        card.searchController.text = result.address ?? 'Location selected';

        // If title is empty, set it to the place name
        if (card.titleController.text.isEmpty) {
          card.titleController.text = result.getPlaceName();
          // Position cursor at beginning so start of text is visible
          card.titleController.selection = TextSelection.fromPosition(
            const TextPosition(offset: 0),
          );
        }
      });

      // Unfocus again after state update to ensure keyboard is dismissed
      Future.microtask(() => FocusScope.of(context).unfocus());
    }
  }

  // Build collapsible experience card
  Widget _buildExperienceCard(ExperienceCardData card, {bool isLast = false}) {
    return Card(
      margin: EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 2,
      child: Column(
        children: [
          // Header row with expand/collapse and delete functionality
          InkWell(
            onTap: () {
              setState(() {
                card.isExpanded = !card.isExpanded;
                // Unfocus any active fields when collapsing
                if (!card.isExpanded) {
                  FocusScope.of(context).unfocus();
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    card.isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.blue,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      card.titleController.text.isNotEmpty
                          ? card.titleController.text
                          : "New Experience",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  // Only show delete button if there's more than one card
                  if (_experienceCards.length > 1)
                    IconButton(
                      icon: Icon(Icons.delete_outline, color: Colors.red[400]),
                      onPressed: () => _removeExperienceCard(card),
                      tooltip: 'Remove experience',
                    ),
                ],
              ),
            ),
          ),

          // Expandable content
          if (card.isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Button to choose saved experience
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      icon: Icon(Icons.bookmark_outline),
                      label: Text('Choose a saved experience'),
                      onPressed: null, // No functionality yet
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue,
                        padding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                  SizedBox(height: 12),

                  // Location selection with preview
                  GestureDetector(
                    onTap: (card.isSelectingLocation || !card.locationEnabled)
                        ? null
                        : () => _showLocationPicker(card),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: card.locationEnabled
                                ? Colors.grey
                                : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(4),
                        color: Colors.transparent,
                      ),
                      padding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      child: Row(
                        children: [
                          Icon(Icons.location_on,
                              color: card.locationEnabled
                                  ? Colors.grey[600]
                                  : Colors.grey[400]),
                          SizedBox(width: 12),
                          Expanded(
                            child: card.selectedLocation != null
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Place name in bold
                                      Text(
                                        card.selectedLocation!.getPlaceName(),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: card.locationEnabled
                                              ? Colors.black
                                              : Colors.grey[500],
                                        ),
                                      ),
                                      // Address
                                      Text(
                                        card.selectedLocation!.address ??
                                            'No address',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: card.locationEnabled
                                              ? Colors.black87
                                              : Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    card.isSelectingLocation
                                        ? 'Selecting location...'
                                        : 'Select location',
                                    style: TextStyle(
                                        color: card.locationEnabled
                                            ? Colors.grey[600]
                                            : Colors.grey[400]),
                                  ),
                          ),
                          // Toggle switch inside the location field
                          Transform.scale(
                            scale: 0.8,
                            child: Switch(
                              value: card.locationEnabled,
                              onChanged: (value) {
                                setState(() {
                                  card.locationEnabled = value;
                                });
                              },
                              activeColor: Colors.blue,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 16),

                  // Experience title
                  TextFormField(
                    controller: card.titleController,
                    focusNode: card.titleFocusNode,
                    decoration: InputDecoration(
                      labelText: 'Experience Title',
                      hintText: 'Enter title',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.title),
                      suffixIcon: card.titleController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, size: 18),
                              onPressed: () {
                                setState(() {
                                  card.titleController.clear();
                                });
                              },
                            )
                          : null,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a title';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      // Trigger a rebuild to show/hide the clear button
                      // and update the card title when collapsed
                      setState(() {});
                    },
                  ),
                  SizedBox(height: 16),

                  // Experience type selection
                  DropdownButtonFormField<ExperienceType>(
                    value: card.selectedType,
                    decoration: InputDecoration(
                      labelText: 'Experience Type',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                    ),
                    items: ExperienceType.values.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type.displayName),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          card.selectedType = value;
                        });
                      }
                    },
                  ),
                  SizedBox(height: 16),

                  // Yelp URL
                  TextFormField(
                    controller: card.yelpUrlController,
                    decoration: InputDecoration(
                      labelText: 'Yelp URL (optional)',
                      hintText: 'https://yelp.com/...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.restaurant_menu),
                      suffixIcon: IconButton(
                        icon: FaIcon(FontAwesomeIcons.yelp, color: Colors.red),
                        tooltip: 'Open in Yelp',
                        onPressed: () =>
                            _openYelpUrl(card.yelpUrlController.text),
                      ),
                    ),
                    keyboardType: TextInputType.url,
                    validator: (value) {
                      if (value != null && value.isNotEmpty) {
                        if (!_isValidUrl(value)) {
                          return 'Please enter a valid URL';
                        }
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 16),

                  // Official website
                  TextFormField(
                    controller: card.websiteUrlController,
                    decoration: InputDecoration(
                      labelText: 'Official Website (optional)',
                      hintText: 'https://...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.language),
                    ),
                    keyboardType: TextInputType.url,
                    validator: (value) {
                      if (value != null && value.isNotEmpty) {
                        if (!_isValidUrl(value)) {
                          return 'Please enter a valid URL';
                        }
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _wrapWithWillPopScope(Scaffold(
      appBar: AppBar(
        title: Text('New Experience'),
        leading: IconButton(
          icon: Icon(Icons.close),
          onPressed: () {
            // Cancel button explicitly resets before calling onCancel
            _sharingService.resetSharedItems();
            widget.onCancel();
          },
        ),
        actions: [
          // Add button - hidden for Yelp content
          if (!_isSpecialContent())
            IconButton(
              icon: Icon(Icons.add),
              onPressed: _addExperienceCard,
              tooltip: 'Add another experience',
            ),
        ],
      ),
      body: SafeArea(
        child: _isSaving
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Saving experience...'),
                  ],
                ),
              )
            : Column(
                children: [
                  // Shared content display (existing code)
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Display the shared content
                          if (widget.sharedFiles.isEmpty)
                            Center(child: Text('No shared content received'))
                          else
                            ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              physics: NeverScrollableScrollPhysics(),
                              itemCount: widget.sharedFiles.length,
                              itemBuilder: (context, index) {
                                final file = widget.sharedFiles[index];
                                return Card(
                                  margin: EdgeInsets.only(bottom: 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildMediaPreview(file),

                                      // Display metadata (only for non-URL content)
                                      if (!(file.type == SharedMediaType.text &&
                                          _isValidUrl(file.path)))
                                        Padding(
                                          padding: const EdgeInsets.all(16.0),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Type: ${_getMediaTypeString(file.type)}',
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                              SizedBox(height: 8),
                                              if (file.type !=
                                                  SharedMediaType.text)
                                                Text('Path: ${file.path}'),
                                              if (file.type ==
                                                      SharedMediaType.text &&
                                                  !_isValidUrl(file.path))
                                                Text('Content: ${file.path}'),
                                              if (file.thumbnail != null) ...[
                                                SizedBox(height: 8),
                                                Text(
                                                    'Thumbnail: ${file.thumbnail}'),
                                              ],
                                            ],
                                          ),
                                        ),

                                      // For URLs, we'll only show the preview and open button
                                      if (file.type == SharedMediaType.text &&
                                          _isValidUrl(file.path))
                                        Padding(
                                          padding: const EdgeInsets.all(16.0),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Type: ${_getMediaTypeString(file.type)}',
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),

                          // Experience association form
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Save to Experiences',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 16),

                                  // List of experience cards
                                  for (int i = 0;
                                      i < _experienceCards.length;
                                      i++)
                                    _buildExperienceCard(_experienceCards[i],
                                        isLast:
                                            i == _experienceCards.length - 1),

                                  // Add another experience button - hidden for Yelp content
                                  if (!_isSpecialContent())
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          top: 4.0, bottom: 16.0),
                                      child: OutlinedButton.icon(
                                        icon: Icon(Icons.add),
                                        label: Text('Add Another Experience'),
                                        onPressed: _addExperienceCard,
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.blue,
                                          padding: EdgeInsets.symmetric(
                                              vertical: 12, horizontal: 16),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Action buttons
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 16),
                            ),
                            onPressed: widget.onCancel,
                            child: Text('Cancel'),
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: EdgeInsets.symmetric(vertical: 16),
                            ),
                            onPressed: _saveExperience,
                            child: Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    ));
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  /// Opens Yelp URL or Yelp.com if no URL is provided
  Future<void> _openYelpUrl(String yelpUrl) async {
    String url = yelpUrl.trim();

    // If empty, use Yelp.com
    if (url.isEmpty) {
      url = 'https://yelp.com';
    } else if (!url.startsWith('http')) {
      // Make sure it starts with http:// or https://
      url = 'https://' + url;
    }

    // Check if this is a Yelp URL for potential app deep linking
    bool isYelpUrl = url.contains('yelp.com');

    try {
      // Parse the regular web URL
      final Uri webUri = Uri.parse(url);

      // For mobile platforms, try to create a deep link URI
      if (!kIsWeb && isYelpUrl) {
        // Extract business ID for deep linking if present in the URL
        // Typical Yelp URL format: https://www.yelp.com/biz/business-name-location
        String? yelpAppUrl;

        if (url.contains('/biz/')) {
          // Extract the business part from URL
          final bizPath = url.split('/biz/')[1].split('?')[0];

          if (Platform.isIOS) {
            // iOS deep link format
            yelpAppUrl = 'yelp:///biz/$bizPath';
          } else if (Platform.isAndroid) {
            // Android deep link format
            yelpAppUrl = 'yelp://biz/$bizPath';
          }
        }

        // Try opening the app URL first if available
        if (yelpAppUrl != null) {
          try {
            final appUri = Uri.parse(yelpAppUrl);
            final canOpenApp = await canLaunchUrl(appUri);

            if (canOpenApp) {
              await launchUrl(appUri, mode: LaunchMode.externalApplication);
              return; // Exit if app opens successfully
            }
          } catch (e) {
            print('Error opening Yelp app: $e');
            // Continue to open the web URL as fallback
          }
        }
      }

      // Open web URL as fallback
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      print('Error launching URL: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open Yelp: $e')),
      );
    }
  }

  bool _isValidUrl(String text) {
    // More permissive URL validation
    try {
      // First try with standard URL validation
      final uri = Uri.parse(text);
      if (uri.hasScheme && uri.hasAuthority) {
        return true;
      }

      // Fallback for URLs without scheme
      if (text.contains('/') &&
          (text.contains('.com') ||
              text.contains('.to') ||
              text.contains('.org') ||
              text.contains('.net') ||
              text.contains('.io'))) {
        return true;
      }

      // Try with an added https:// prefix
      if (!text.startsWith('http')) {
        final uri = Uri.parse('https://' + text);
        return uri.hasScheme && uri.hasAuthority;
      }

      return false;
    } catch (e) {
      // Check if it looks like a URL but just needs a scheme
      if (text.contains('.') && !text.contains(' ')) {
        try {
          final uri = Uri.parse('https://' + text);
          return uri.hasScheme && uri.hasAuthority;
        } catch (_) {
          return false;
        }
      }
      return false;
    }
  }

  String _getMediaTypeString(SharedMediaType type) {
    switch (type) {
      case SharedMediaType.image:
        return 'Image';
      case SharedMediaType.video:
        return 'Video';
      case SharedMediaType.file:
        return 'File';
      case SharedMediaType.text:
        return 'Text';
      default:
        return type.toString();
    }
  }

  Widget _buildMediaPreview(SharedMediaFile file) {
    switch (file.type) {
      case SharedMediaType.image:
        return _buildImagePreview(file);
      case SharedMediaType.video:
        return _buildVideoPreview(file);
      case SharedMediaType.text:
        return _buildTextPreview(file);
      case SharedMediaType.file:
      default:
        return _buildFilePreview(file);
    }
  }

  Widget _buildTextPreview(SharedMediaFile file) {
    // Check if it's a URL
    if (_isValidUrl(file.path)) {
      // Enhanced Yelp detection
      if (file.path.toLowerCase().contains('yelp.to/') ||
          file.path.toLowerCase().contains('yelp.com/biz/')) {
        print('DEBUG: Building Yelp preview for URL: ${file.path}');
        return _buildYelpPreview(file.path);
      }
      return _buildUrlPreview(file.path);
    } else {
      // Special case for text content that contains both a message and URL
      // Format: "Check out Yuk Dae Jang - Irvine!\nhttps://yelp.to/R_mzCnQBf8"
      if (file.path.contains('\n') && file.path.contains('http')) {
        final lines = file.path.split('\n');
        for (final line in lines) {
          if (line.trim().startsWith('http')) {
            print('DEBUG: Extracted URL from text: ${line.trim()}');
            // Enhanced Yelp detection to include both yelp.com and yelp.to URLs
            if (line.toLowerCase().contains('yelp.to/') ||
                line.toLowerCase().contains('yelp.com/biz/')) {
              return _buildYelpPreview(line.trim());
            }
            return _buildUrlPreview(line.trim());
          }
        }
      } else if (file.path.contains('Check out') &&
          file.path.contains('yelp.to/')) {
        // Generic match for Yelp shares with business name and short URL
        print('DEBUG: Found match for shared Yelp content');
        // Extract URL using regex to get the Yelp link
        final RegExp urlRegex = RegExp(r'https?://yelp.to/[^\s]+');
        final match = urlRegex.firstMatch(file.path);
        if (match != null) {
          final extractedUrl = match.group(0);
          print('DEBUG: Extracted Yelp URL using regex: $extractedUrl');
          return _buildYelpPreview(extractedUrl!);
        }
      } else if (file.path.contains('yelp.to/') ||
          file.path.contains('yelp.com/biz/')) {
        // Extract URL using regex
        final RegExp urlRegex = RegExp(r'https?://[^\s]+');
        final match = urlRegex.firstMatch(file.path);
        if (match != null) {
          final extractedUrl = match.group(0);
          print('DEBUG: Extracted Yelp URL using regex: $extractedUrl');
          return _buildYelpPreview(extractedUrl!);
        }
      }
      // Regular text
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(16),
        color: Colors.grey[200],
        child: Text(
          file.path,
          style: TextStyle(fontSize: 16),
        ),
      );
    }
  }

  Widget _buildUrlPreview(String url) {
    // Special handling for Yelp URLs
    if (url.contains('yelp.com/biz') || url.contains('yelp.to/')) {
      return _buildYelpPreview(url);
    }

    // Special handling for Google Maps URLs
    if (url.contains('google.com/maps') ||
        url.contains('maps.app.goo.gl') ||
        url.contains('goo.gl/maps')) {
      return _buildMapsPreview(url);
    }

    // Special handling for Instagram URLs
    if (url.contains('instagram.com')) {
      return _buildInstagramPreview(url);
    }

    return SizedBox(
      height: 220,
      width: double.infinity,
      child: AnyLinkPreview(
        link: url,
        displayDirection: UIDirection.uiDirectionVertical,
        cache: Duration(hours: 1),
        backgroundColor: Colors.white,
        errorWidget: Container(
          color: Colors.grey[200],
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.link, size: 50, color: Colors.blue),
              SizedBox(height: 8),
              Text(
                url,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.blue),
              ),
            ],
          ),
        ),
        onTap: () => _launchUrl(url),
      ),
    );
  }

  /// Build a preview widget for a Yelp URL
  Widget _buildYelpPreview(String url) {
    // Create a stable key for the FutureBuilder to prevent unnecessary rebuilds
    final String urlKey = url.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

    // Try to extract business name from URL for fallback display
    String fallbackBusinessName = _extractBusinessNameFromYelpUrl(url);

    print("🔍 YELP PREVIEW: Starting preview generation for URL: $url");
    print(
        "🔍 YELP PREVIEW: Extracted fallback business name: $fallbackBusinessName");

    // Get or create the future - this is the key change
    if (!_yelpPreviewFutures.containsKey(url)) {
      print("🔍 YELP PREVIEW: Creating new future for URL: $url");
      _yelpPreviewFutures[url] = _getBusinessFromYelpUrl(url);
    } else {
      print("🔍 YELP PREVIEW: Using cached future for URL: $url");
    }

    return FutureBuilder<Map<String, dynamic>?>(
      key: ValueKey('yelp_preview_$urlKey'),
      future: _yelpPreviewFutures[url],
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          print("🔍 YELP PREVIEW: Loading state - waiting for data");
          return _buildYelpLoadingPreview();
        }

        // If we have data, build the complete preview
        if (snapshot.data != null) {
          final data = snapshot.data!;
          final location = data['location'] as Location;
          final businessName = data['businessName'] as String;
          final yelpUrl = data['yelpUrl'] as String;

          print("🔍 YELP PREVIEW: Success! Building detailed preview");
          print("🔍 YELP PREVIEW: Business name: $businessName");
          print(
              "🔍 YELP PREVIEW: Location data: lat=${location.latitude}, lng=${location.longitude}");
          print("🔍 YELP PREVIEW: Address: ${location.address}");

          return _buildYelpDetailedPreview(location, businessName, yelpUrl);
        }

        // If snapshot has error, log it
        if (snapshot.hasError) {
          print("🔍 YELP PREVIEW ERROR: ${snapshot.error}");
          print("🔍 YELP PREVIEW: Using fallback preview due to error");
        } else {
          print("🔍 YELP PREVIEW: No data received, using fallback preview");
        }

        // If we have an error or no data, build a fallback preview
        return _buildYelpFallbackPreview(url, fallbackBusinessName);
      },
    );
  }

  // Extract a readable business name from a Yelp URL
  String _extractBusinessNameFromYelpUrl(String url) {
    try {
      String businessName = "Yelp Business";

      // For standard Yelp URLs with business name in the path
      if (url.contains('/biz/')) {
        // Extract the business part from URL (e.g., https://www.yelp.com/biz/business-name-location)
        final bizPath = url.split('/biz/')[1].split('?')[0];

        // Convert hyphenated business name to spaces and capitalize words
        businessName = bizPath
            .split('-')
            .map((word) => word.isNotEmpty
                ? word[0].toUpperCase() + word.substring(1)
                : '')
            .join(' ');

        // If there's a location suffix at the end (like "restaurant-city"), remove it
        if (businessName.contains('/')) {
          businessName = businessName.split('/')[0];
        }
      }
      // For short URLs, use the code as part of the name
      else if (url.contains('yelp.to/')) {
        final shortCode =
            url.split('yelp.to/').last.split('?')[0].split('/')[0];
        if (shortCode.isNotEmpty) {
          businessName = "Yelp Business ($shortCode)";
        }
      }

      return businessName;
    } catch (e) {
      return "Yelp Business";
    }
  }

  // Loading state for Yelp preview
  Widget _buildYelpLoadingPreview() {
    return SizedBox(
      height: 250,
      width: double.infinity,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFFD32323)),
              SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FaIcon(FontAwesomeIcons.yelp,
                      color: Color(0xFFD32323), size: 18),
                  SizedBox(width: 8),
                  Text('Loading business information...'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Detailed preview when we have location data
  Widget _buildYelpDetailedPreview(
      Location location, String businessName, String yelpUrl) {
    print('🏢 PREVIEW: Building detailed Yelp preview');
    print('🏢 PREVIEW: Business name: "$businessName"');
    print(
        '🏢 PREVIEW: Location - lat: ${location.latitude}, lng: ${location.longitude}');
    print('🏢 PREVIEW: Address: ${location.address}');
    print('🏢 PREVIEW: Yelp URL: $yelpUrl');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Preview container with tap functionality
        InkWell(
          onTap: () => _openYelpUrl(yelpUrl),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Business photo instead of map
                Container(
                  height: 180,
                  width: double.infinity,
                  child: ClipRRect(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Business photo based on location
                        _getBusinessPhotoWidget(location, businessName),

                        // Yelp branding overlay in top-right corner
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Color(0xFFD32323),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FaIcon(FontAwesomeIcons.yelp,
                                    color: Colors.white, size: 12),
                                SizedBox(width: 4),
                                Text(
                                  'Yelp',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Business details
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Yelp logo and business name
                      Row(
                        children: [
                          FaIcon(FontAwesomeIcons.yelp,
                              color: Colors.red, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              location.displayName ?? businessName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),

                      // Address
                      if (location.address != null) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.location_on,
                                size: 16, color: Colors.grey[600]),
                            SizedBox(width: 6),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  print(
                                      '🧭 ADDRESS: Opening map for ${location.latitude}, ${location.longitude}');
                                  // Open map to show location with higher zoom level
                                  if (location.placeId != null &&
                                      location.placeId!.isNotEmpty) {
                                    // Use the Google Maps search API with place_id format
                                    final placeUrl =
                                        'https://www.google.com/maps/search/?api=1&query=${location.displayName ?? businessName}&query_place_id=${location.placeId}';
                                    print(
                                        '🧭 ADDRESS: Opening URL with placeId: $placeUrl');
                                    await _launchUrl(placeUrl);
                                  } else {
                                    // Fallback to coordinate-based URL with zoom parameter
                                    final zoom = 18;
                                    final url =
                                        'https://www.google.com/maps/search/?api=1&query=${location.latitude},${location.longitude}';
                                    print(
                                        '🧭 ADDRESS: Opening URL with coordinates: $url');
                                    await _launchUrl(url);
                                  }
                                },
                                child: Text(
                                  location.address!,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[800],
                                    decoration: TextDecoration.underline,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Buttons below the container
        SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: Icon(Icons.directions, size: 18),
                label: Text('Get Directions'),
                onPressed: () async {
                  print(
                      '🧭 DIRECTIONS: Getting directions for ${location.latitude}, ${location.longitude}');
                  final GoogleMapsService mapsService = GoogleMapsService();
                  final url = mapsService.getDirectionsUrl(
                      location.latitude, location.longitude);
                  print('🧭 DIRECTIONS: Opening URL: $url');
                  await _launchUrl(url);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Get a widget displaying a business photo
  Widget _getBusinessPhotoWidget(Location location, String businessName) {
    print('🖼️ PHOTO: Getting business photo for "$businessName"');
    print(
        '🖼️ PHOTO: Location data - lat: ${location.latitude}, lng: ${location.longitude}');
    print('🖼️ PHOTO: Place ID: ${location.placeId ?? "null"}');
    print('🖼️ PHOTO: Address: ${location.address ?? "null"}');

    // Get the place ID, which should be available in the location object
    final String? placeId = location.placeId;
    if (placeId == null || placeId.isEmpty) {
      print('🖼️ PHOTO: No place ID available, using fallback');
      return _buildPhotoFallback(businessName);
    }

    // For diagnostics, check the API key
    final apiKey = GoogleMapsService.apiKey;
    print(
        '🖼️ PHOTO: API key length: ${apiKey.length} chars, starts with: ${apiKey.substring(0, min(5, apiKey.length))}...');

    // Create a unique photo query using both business name and address
    // This ensures that chain businesses (like Trader Joe's, Starbucks) get the correct location images
    String photoQuery = businessName;

    // Include address in the query if available to get photos for the specific chain location
    if (location.address != null && location.address!.isNotEmpty) {
      // Extract the street address part (usually the first component before the first comma)
      String streetAddress = location.address!;
      if (streetAddress.contains(',')) {
        streetAddress = streetAddress.substring(0, streetAddress.indexOf(','));
      }

      // Combine business name with street address for better identification
      photoQuery = '$businessName, $streetAddress';
      print('🖼️ PHOTO: Enhanced photo query with address: "$photoQuery"');
    }

    // First try to get photos by place ID
    return FutureBuilder<List<String>>(
      future: GoogleMapsService().getPlacePhotoReferences(placeId),
      builder: (context, snapshot) {
        // If we have photo URLs, display them
        if (snapshot.hasData &&
            snapshot.data != null &&
            snapshot.data!.isNotEmpty) {
          final List<String> photoUrls = snapshot.data!;
          print('🖼️ PHOTO: Got ${photoUrls.length} photos from Places API');

          // If we have multiple photos, show a carousel
          if (photoUrls.length > 1) {
            return _buildPhotoCarousel(photoUrls, businessName);
          }

          // Otherwise show a single photo
          return _buildSinglePhoto(photoUrls.first, businessName);
        }

        // Check for specific errors
        if (snapshot.hasError) {
          print('🖼️ PHOTO ERROR: Error fetching photos: ${snapshot.error}');
        }

        // If no photos found via place ID, try a search approach
        if (snapshot.connectionState == ConnectionState.done &&
            (snapshot.data == null || snapshot.data!.isEmpty)) {
          print(
              '🖼️ PHOTO: No photos via place ID, trying search approach with "$photoQuery"');

          // Use GoogleMapsService to search for the place with the enhanced query
          return FutureBuilder<List<Map<String, dynamic>>>(
              future: GoogleMapsService().searchPlaces(photoQuery),
              builder: (context, searchSnapshot) {
                if (searchSnapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFD32323),
                    ),
                  );
                }

                if (searchSnapshot.hasData &&
                    searchSnapshot.data != null &&
                    searchSnapshot.data!.isNotEmpty) {
                  // If we found search results, use the place ID from the first match
                  final String? foundPlaceId =
                      searchSnapshot.data!.first['placeId'] as String?;

                  if (foundPlaceId != null && foundPlaceId.isNotEmpty) {
                    print(
                        '🖼️ PHOTO: Found place ID via search: $foundPlaceId');

                    // Try to get photos with this specific place ID
                    return FutureBuilder<List<String>>(
                        future: GoogleMapsService()
                            .getPlacePhotoReferences(foundPlaceId),
                        builder: (context, photoSnapshot) {
                          if (photoSnapshot.connectionState ==
                              ConnectionState.waiting) {
                            return Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFFD32323),
                              ),
                            );
                          }

                          if (photoSnapshot.hasData &&
                              photoSnapshot.data != null &&
                              photoSnapshot.data!.isNotEmpty) {
                            final List<String> photoUrls = photoSnapshot.data!;
                            print(
                                '🖼️ PHOTO: Got ${photoUrls.length} photos via search approach');

                            // Display photos
                            if (photoUrls.length > 1) {
                              return _buildPhotoCarousel(
                                  photoUrls, businessName);
                            }
                            return _buildSinglePhoto(
                                photoUrls.first, businessName);
                          }

                          // If no photos found via search either, use fallback
                          print(
                              '🖼️ PHOTO: No photos found via search approach either');
                          final String businessSeed =
                              _createPhotoSeed(businessName, location);
                          final String photoUrl =
                              _getBusinessPhotoUrl(businessName, businessSeed);
                          return _buildSinglePhoto(photoUrl, businessName);
                        });
                  }
                }

                // If search approach failed, use category-based fallback
                print(
                    '🖼️ PHOTO: Search approach failed, using category-based fallback');
                final String businessSeed =
                    _createPhotoSeed(businessName, location);
                final String photoUrl =
                    _getBusinessPhotoUrl(businessName, businessSeed);
                return _buildSinglePhoto(photoUrl, businessName);
              });
        }

        // While loading, show loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          print('🖼️ PHOTO: Loading photos...');
          return Center(
            child: CircularProgressIndicator(
              color: Color(0xFFD32323),
            ),
          );
        }

        // Default fallback
        print('🖼️ PHOTO: Using category-based fallback');
        final String businessSeed = _createPhotoSeed(businessName, location);
        final String photoUrl =
            _getBusinessPhotoUrl(businessName, businessSeed);
        return _buildSinglePhoto(photoUrl, businessName);
      },
    );
  }

  // Build a carousel to display multiple photos
  Widget _buildPhotoCarousel(List<String> photoUrls, String businessName) {
    return Stack(
      children: [
        PageView.builder(
          itemCount: photoUrls.length,
          itemBuilder: (context, index) {
            return _buildSinglePhoto(photoUrls[index], businessName);
          },
        ),

        // Photo counter indicator
        Positioned(
          right: 8,
          bottom: 8,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.photo, size: 14, color: Colors.white),
                SizedBox(width: 4),
                Text(
                  '${photoUrls.length}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Build a single photo display
  Widget _buildSinglePhoto(String photoUrl, String businessName) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background color before image loads
        Container(color: Color(0xFFEEEEEE)),

        // Image with loading indicator
        Image.network(
          photoUrl,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              print('🖼️ PHOTO: Image loaded successfully!');
              return child;
            }
            print(
                '🖼️ PHOTO: Loading progress: ${loadingProgress.cumulativeBytesLoaded}/${loadingProgress.expectedTotalBytes ?? 'unknown'}');
            return Center(
              child: CircularProgressIndicator(
                color: Color(0xFFD32323),
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            print('🖼️ PHOTO ERROR: Failed to load image: $error');
            return _buildPhotoFallback(businessName);
          },
        ),

        // Subtle gradient overlay at the bottom
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.3),
                ],
                stops: [0.7, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Generate a seed for consistent photo selection
  String _createPhotoSeed(String businessName, Location location) {
    // Create a deterministic but unique value based on business name and location
    String seed = businessName;

    // Add location info if available (truncated to avoid excessive precision)
    if (location.latitude != null && location.longitude != null) {
      // Round to 3 decimal places to create a general area identifier
      String locationStr =
          '${location.latitude!.toStringAsFixed(3)}_${location.longitude!.toStringAsFixed(3)}';
      seed = '$seed-$locationStr';
    }

    // Generate hash for the seed
    return seed.hashCode.abs().toString();
  }

  // Get a photo URL based on business type
  String _getBusinessPhotoUrl(String businessName, String seed) {
    final String businessNameLower = businessName.toLowerCase();
    int seedNumber = int.tryParse(seed) ?? 0;

    // Determine business category
    String category = 'business';

    if (businessNameLower.contains('restaurant') ||
        businessNameLower.contains('grill') ||
        businessNameLower.contains('pizza') ||
        businessNameLower.contains('kitchen') ||
        businessNameLower.contains('cafe') ||
        businessNameLower.contains('coffee')) {
      category = 'restaurant';
      print('🔍 CATEGORY: Detected restaurant type business');
    } else if (businessNameLower.contains('bar') ||
        businessNameLower.contains('pub') ||
        businessNameLower.contains('lounge')) {
      category = 'bar';
      print('🔍 CATEGORY: Detected bar type business');
    } else if (businessNameLower.contains('shop') ||
        businessNameLower.contains('store') ||
        businessNameLower.contains('market')) {
      category = 'retail';
      print('🔍 CATEGORY: Detected retail type business');
    } else if (businessNameLower.contains('hotel') ||
        businessNameLower.contains('inn') ||
        businessNameLower.contains('suites')) {
      category = 'hotel';
      print('🔍 CATEGORY: Detected hotel type business');
    } else {
      print('🔍 CATEGORY: Using generic business type');
    }

    // Create URLs for different categories
    // Using reliable image services with category-specific images
    Map<String, List<String>> categoryImages = {
      'restaurant': [
        'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1552566626-52f8b828add9?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1600891964599-f61ba0e24092?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1466978913421-dad2ebd01d17?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1592861956120-e524fc739696?w=800&h=400&fit=crop'
      ],
      'bar': [
        'https://images.unsplash.com/photo-1514933651103-005eec06c04b?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1543007630-9710e4a00a20?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1470337458703-46ad1756a187?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1572116469696-31de0f17cc34?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1575444758702-4a6b9222336e?w=800&h=400&fit=crop'
      ],
      'retail': [
        'https://images.unsplash.com/photo-1441986300917-64674bd600d8?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1604719312566-8912e9c8a213?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1567401893414-76b7b1e5a7a5?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1534452203293-494d7ddbf7e0?w=800&h=400&fit=crop'
      ],
      'hotel': [
        'https://images.unsplash.com/photo-1582719508461-905c673771fd?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1566073771259-6a8506099945?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1445019980597-93fa8acb246c?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1520250497591-112f2f40a3f4?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1551882547-ff40c63fe5fa?w=800&h=400&fit=crop'
      ],
      'business': [
        'https://images.unsplash.com/photo-1497366754035-f200968a6e72?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1497215842964-222b430dc094?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1504328345606-18bbc8c9d7d8?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1497366811353-6870744d04b2?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1568992687947-868a62a9f521?w=800&h=400&fit=crop'
      ]
    };

    // Get the images for the determined category
    List<String> images =
        categoryImages[category] ?? categoryImages['business']!;

    // Pick one based on the seed (deterministic selection)
    int imageIndex = seedNumber % images.length;

    return images[imageIndex];
  }

  // Fallback when image fails to load
  Widget _buildPhotoFallback(String businessName) {
    print('⚠️ FALLBACK: Building fallback photo for "$businessName"');
    return Container(
      color: Color(0xFFE8E8E8),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.business,
              size: 48,
              color: Color(0xFFD32323),
            ),
            SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                businessName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF333333),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Detailed preview when we don't have location data
  Widget _buildYelpFallbackPreview(String url, String businessName) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Fallback container with Yelp styling
        InkWell(
          onTap: () => _openYelpUrl(url),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Yelp Logo
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Color(0xFFD32323),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: FaIcon(FontAwesomeIcons.yelp,
                        size: 40, color: Colors.white),
                  ),
                ),
                SizedBox(height: 16),

                // Business Name
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    businessName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(height: 8),

                // Yelp URL
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Text(
                    url.length > 30 ? '${url.substring(0, 30)}...' : url,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ),
                SizedBox(height: 24),

                // Small helper text
                Text(
                  'Tap to view this business on Yelp',
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Action button below the container - removed
        SizedBox(height: 8),
      ],
    );
  }

  Widget _buildInstagramPreview(String url) {
    // Check if it's a reel
    final bool isReel = _isInstagramReel(url);

    if (isReel) {
      return InstagramReelEmbed(url: url, onOpen: () => _launchUrl(url));
    } else {
      // Regular Instagram content (fallback to current implementation)
      final String contentId = _extractInstagramId(url);

      return InkWell(
        onTap: () => _launchUrl(url),
        child: Container(
          width: double.infinity,
          color: Colors.white,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Instagram logo or icon
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      Color(0xFFE1306C),
                      Color(0xFFF77737),
                      Color(0xFFFCAF45),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Instagram Content',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 4),
              Text(
                contentId,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontFamily: 'Courier',
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Tap to play video',
                style: TextStyle(
                  color: Colors.grey[700],
                ),
              ),
              SizedBox(height: 16),
              OutlinedButton.icon(
                icon: Icon(Icons.open_in_new),
                label: Text('Open Instagram'),
                onPressed: () => _launchUrl(url),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Color(0xFFE1306C),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  // Check if URL is an Instagram reel
  bool _isInstagramReel(String url) {
    return url.contains('instagram.com/reel') ||
        url.contains('instagram.com/reels') ||
        (url.contains('instagram.com/p') &&
            (url.contains('?img_index=') ||
                url.contains('video_index=') ||
                url.contains('media_index=') ||
                url.contains('?igsh=')));
  }

  // Extract content ID from Instagram URL
  String _extractInstagramId(String url) {
    // Try to extract the content ID from the URL
    try {
      // Remove query parameters if present
      String cleanUrl = url;
      if (url.contains('?')) {
        cleanUrl = url.split('?')[0];
      }

      // Split the URL by slashes
      List<String> pathSegments = cleanUrl.split('/');

      // Instagram URLs usually have the content ID as one of the last segments
      // For reels: instagram.com/reel/{content_id}
      if (pathSegments.length > 2) {
        for (int i = pathSegments.length - 1; i >= 0; i--) {
          if (pathSegments[i].isNotEmpty &&
              pathSegments[i] != 'instagram.com' &&
              pathSegments[i] != 'reel' &&
              pathSegments[i] != 'p' &&
              !pathSegments[i].startsWith('http')) {
            return pathSegments[i];
          }
        }
      }

      return 'Instagram Content';
    } catch (e) {
      return 'Instagram Content';
    }
  }

  Widget _buildImagePreview(SharedMediaFile file) {
    try {
      return SizedBox(
        height: 350,
        width: double.infinity,
        child: Image.file(
          File(file.path),
          fit: BoxFit.cover,
        ),
      );
    } catch (e) {
      return Container(
        height: 400,
        width: double.infinity,
        color: Colors.grey[300],
        child: Center(
          child: Icon(Icons.image_not_supported, size: 50),
        ),
      );
    }
  }

  Widget _buildVideoPreview(SharedMediaFile file) {
    return Container(
      height: 350,
      width: double.infinity,
      color: Colors.black87,
      child: Center(
        child: Icon(
          Icons.play_circle_outline,
          size: 70,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildFilePreview(SharedMediaFile file) {
    IconData iconData;
    Color iconColor;

    // Determine file type from path extension
    final String extension = file.path.split('.').last.toLowerCase();

    if (['pdf'].contains(extension)) {
      iconData = Icons.picture_as_pdf;
      iconColor = Colors.red;
    } else if (['doc', 'docx'].contains(extension)) {
      iconData = Icons.description;
      iconColor = Colors.blue;
    } else if (['xls', 'xlsx'].contains(extension)) {
      iconData = Icons.table_chart;
      iconColor = Colors.green;
    } else if (['ppt', 'pptx'].contains(extension)) {
      iconData = Icons.slideshow;
      iconColor = Colors.orange;
    } else if (['txt', 'rtf'].contains(extension)) {
      iconData = Icons.text_snippet;
      iconColor = Colors.blueGrey;
    } else if (['zip', 'rar', '7z'].contains(extension)) {
      iconData = Icons.folder_zip;
      iconColor = Colors.amber;
    } else {
      iconData = Icons.insert_drive_file;
      iconColor = Colors.grey;
    }

    return Container(
      height: 350,
      width: double.infinity,
      color: Colors.grey[200],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(iconData, size: 70, color: iconColor),
            SizedBox(height: 8),
            Text(
              extension.toUpperCase(),
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  /// Extract location data from a Google Maps URL
  Future<Map<String, dynamic>?> _getLocationFromMapsUrl(String url) async {
    print('🗺️ MAPS: Starting to extract location from Maps URL: $url');

    try {
      final Uri uri = Uri.parse(url);
      String? locationName;
      double? latitude;
      double? longitude;
      String? placeId;
      String? addressText;
      String? websiteUrl = '';

      // Extract query parameters
      final queryParams = uri.queryParameters;

      // Try to extract place_id
      if (queryParams.containsKey('place_id')) {
        placeId = queryParams['place_id'];
        print('🗺️ MAPS: Found place_id in URL: $placeId');

        // Get place details using Google Places API
        if (placeId != null && placeId.isNotEmpty) {
          print('🗺️ MAPS: Getting place details for place_id: $placeId');
          final location = await GoogleMapsService().getPlaceDetails(placeId);

          // Get additional place details including website URL
          try {
            // Make API call to get website URL and photos
            final apiKey = GoogleMapsService.apiKey;
            final detailsUrl =
                'https://places.googleapis.com/v1/places/$placeId?fields=name,formattedAddress,website,photos&key=$apiKey';

            final dio = Dio();
            final response = await dio.get(detailsUrl,
                options: Options(
                  headers: {
                    'Content-Type': 'application/json',
                    'X-Goog-Api-Key': apiKey,
                    'X-Goog-FieldMask': 'name,formattedAddress,website,photos'
                  },
                ));

            if (response.statusCode == 200) {
              final data = response.data;
              if (data != null) {
                // Get website if available
                websiteUrl = data['website'];
                print('🗺️ MAPS: Found website URL: $websiteUrl');

                // Check if this is a chain location
                final displayName = data['name']?['text'] ?? '';
                final possibleChainNames = [
                  'McDonald',
                  'Starbucks',
                  'Subway',
                  'KFC',
                  'Burger King',
                  'Wendy',
                  'Taco Bell',
                  'Pizza Hut',
                  'Domino',
                  'Dunkin',
                  'Chipotle',
                  'Chick-fil-A',
                  'Popeyes',
                  'Panera',
                  'Baskin',
                  'Dairy Queen',
                  'Papa John',
                  'Panda Express',
                  'Sonic',
                  'Arby'
                ];

                bool isChain = false;
                for (final chain in possibleChainNames) {
                  if (displayName.toLowerCase().contains(chain.toLowerCase())) {
                    isChain = true;
                    print('🗺️ MAPS: Detected chain business: $chain');
                    break;
                  }
                }

                if (isChain) {
                  print(
                      '🗺️ MAPS: This is a chain location - ensuring we get the right branch photo');
                }

                // Fill the form with the data from Google Maps
                _fillFormWithGoogleMapsData(location,
                    locationName ?? 'Shared Location', websiteUrl ?? '');

                return {
                  'location': location,
                  'placeName': locationName ?? 'Shared Location',
                  'mapsUrl': url,
                  'website': websiteUrl,
                };
              }
            }
          } catch (e) {
            print('🗺️ MAPS ERROR: Failed to get additional place details: $e');
          }

          // Even if we couldn't get the website, still fill the form with location data
          _fillFormWithGoogleMapsData(
              location, location.displayName ?? '', websiteUrl ?? '');

          return {
            'location': location,
            'name': location.displayName,
            'website': websiteUrl,
          };
        }
      }

      // Continue with the rest of the existing implementation...

      // Try to extract coordinates from query parameter
      if (queryParams.containsKey('q')) {
        final query = queryParams['q']!;
        print('🗺️ MAPS: Found query parameter: $query');

        // Check if query contains coordinates
        if (_containsOnlyCoordinates(query)) {
          print('🗺️ MAPS: Query appears to be coordinates');
          final parts = query.split(',');
          if (parts.length == 2) {
            try {
              latitude = double.parse(parts[0]);
              longitude = double.parse(parts[1]);
              print('🗺️ MAPS: Extracted coordinates: $latitude, $longitude');
            } catch (e) {
              print('🗺️ MAPS ERROR: Failed to parse coordinates: $e');
            }
          }
        } else {
          // If not coordinates, use as place name
          locationName = query;
          print('🗺️ MAPS: Using query as place name: $locationName');
        }
      }

      // Try to extract coordinates from @param
      if (latitude == null && queryParams.containsKey('@')) {
        final atParam = queryParams['@']!;
        print('🗺️ MAPS: Found @ parameter: $atParam');

        // Extract latitude and longitude from the @ parameter
        // Format is usually like: 37.7749,-122.4194,14z (lat,lng,zoom)
        final coordsPattern = RegExp(r'(-?\d+\.\d+),(-?\d+\.\d+)');
        final match = coordsPattern.firstMatch(atParam);

        if (match != null && match.groupCount >= 2) {
          try {
            latitude = double.parse(match.group(1)!);
            longitude = double.parse(match.group(2)!);
            print(
                '🗺️ MAPS: Extracted coordinates from @ param: $latitude, $longitude');
          } catch (e) {
            print(
                '🗺️ MAPS ERROR: Failed to parse coordinates from @ param: $e');
          }
        }
      }

      // Try to extract coordinates from direct path segments
      // For URLs like: maps.google.com/?ll=37.7749,-122.4194
      if (latitude == null && queryParams.containsKey('ll')) {
        final ll = queryParams['ll']!;
        print('🗺️ MAPS: Found ll parameter: $ll');

        final parts = ll.split(',');
        if (parts.length == 2) {
          try {
            latitude = double.parse(parts[0]);
            longitude = double.parse(parts[1]);
            print(
                '🗺️ MAPS: Extracted coordinates from ll param: $latitude, $longitude');
          } catch (e) {
            print(
                '🗺️ MAPS ERROR: Failed to parse coordinates from ll param: $e');
          }
        }
      }

      // For shortened URLs or URLs without clear parameters, try to extract coordinates from the path
      if ((latitude == null || locationName == null) &&
          (url.contains('goo.gl') || url.contains('maps.app.goo.gl'))) {
        // For shortened URLs, we need to follow redirects
        print('🗺️ MAPS: Shortened URL detected, following redirects...');

        // Improved handling of shortened URLs with retry logic
        bool success = false;
        int retryCount = 0;
        const int maxRetries = 3;

        while (!success && retryCount < maxRetries) {
          try {
            // Use Dio for better redirect handling
            final dio = Dio();
            dio.options.followRedirects = true;
            dio.options.maxRedirects = 5;
            dio.options.validateStatus = (status) => status! < 500;
            dio.options.connectTimeout = const Duration(seconds: 10);
            dio.options.receiveTimeout = const Duration(seconds: 10);

            // Enhanced headers to better mimic a real browser
            final response = await dio.get(
              url,
              options: Options(
                followRedirects: true,
                validateStatus: (status) => status! < 500,
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  'Accept':
                      'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
                  'Accept-Language': 'en-US,en;q=0.9',
                  'Accept-Encoding': 'gzip, deflate, br',
                  'Connection': 'keep-alive',
                  'Cache-Control': 'max-age=0',
                  'Referer': 'https://www.google.com/',
                  'Sec-Ch-Ua': '"Not_A Brand";v="8", "Chromium";v="120"',
                  'Sec-Ch-Ua-Mobile': '?0',
                  'Sec-Ch-Ua-Platform': '"Windows"',
                  'Sec-Fetch-Dest': 'document',
                  'Sec-Fetch-Mode': 'navigate',
                  'Sec-Fetch-Site': 'cross-site',
                  'Upgrade-Insecure-Requests': '1',
                },
              ),
            );

            // Check if we got a successful response
            if (response.statusCode == 200) {
              success = true;
              // Successfully resolved URL, now parse it
              final resolvedUrl = response.realUri.toString();
              print('🗺️ MAPS: Following URL after redirects: $resolvedUrl');

              // Use a direct second request if needed for better results
              if (!resolvedUrl.contains('/maps/place/') &&
                  !resolvedUrl.contains('@')) {
                print(
                    '🗺️ MAPS: Resolved URL doesn\'t contain place info, trying secondary approach...');
                // Make a second request with the resolved URL
                final secondResponse = await dio.get(
                  resolvedUrl,
                  options: Options(
                    headers: {
                      'User-Agent':
                          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                      'Accept':
                          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
                      'Accept-Language': 'en-US,en;q=0.9',
                    },
                  ),
                );
                if (secondResponse.statusCode == 200) {
                  final html = secondResponse.data.toString();
                  // Try to extract place data from the HTML
                  RegExp placeNameRegex =
                      RegExp(r'<meta property="og:title" content="([^"]+)"');
                  Match? placeNameMatch = placeNameRegex.firstMatch(html);
                  if (placeNameMatch != null &&
                      placeNameMatch.groupCount >= 1) {
                    locationName = placeNameMatch.group(1)!;
                    print(
                        '🗺️ MAPS: Extracted place name from HTML: $locationName');
                  }
                }
              }

              // Check if this is a place URL (contains "/place/" in path)
              bool isPlaceUrl = resolvedUrl.contains('/place/');
              if (isPlaceUrl) {
                print('🗺️ MAPS: Detected place URL pattern');

                // Extract place name from the URL path for places
                // Format: /maps/place/PLACE_NAME/data=...
                RegExp placeNameRegex = RegExp(r'/place/([^/]+)/');
                Match? placeMatch = placeNameRegex.firstMatch(resolvedUrl);

                if (placeMatch != null && placeMatch.groupCount >= 1) {
                  String encodedPlaceName = placeMatch.group(1)!;
                  // Decode URL-encoded place name
                  locationName = Uri.decodeComponent(
                      encodedPlaceName.replaceAll('+', ' '));
                  print(
                      '🗺️ MAPS: Extracted place name from URL path: $locationName');

                  // Extract place ID if present in the URL
                  RegExp placeIdRegex = RegExp(r'!1s([a-zA-Z0-9:_-]+)');
                  Match? placeIdMatch = placeIdRegex.firstMatch(resolvedUrl);

                  if (placeIdMatch != null && placeIdMatch.groupCount >= 1) {
                    placeId = placeIdMatch.group(1);
                    print(
                        '🗺️ MAPS: Extracted place ID from resolved URL: $placeId');
                  }

                  // Also look for CID and FID values which can be useful for finding places
                  RegExp cidRegex = RegExp(r'cid=(\d+)');
                  Match? cidMatch = cidRegex.firstMatch(resolvedUrl);

                  if (cidMatch != null && cidMatch.groupCount >= 1) {
                    String cid = cidMatch.group(1)!;
                    print('🗺️ MAPS: Found CID in resolved URL: $cid');

                    // Store CID in place ID if we don't have one yet
                    if (placeId == null || placeId.isEmpty) {
                      placeId = 'cid:$cid';
                    }
                  }

                  // Check for FID (another ID format in some Google Maps URLs)
                  RegExp fidRegex = RegExp(r'ftid=([a-zA-Z0-9-]+)');
                  Match? fidMatch = fidRegex.firstMatch(resolvedUrl);

                  if (fidMatch != null && fidMatch.groupCount >= 1) {
                    String fid = fidMatch.group(1)!;
                    print('🗺️ MAPS: Found FID in resolved URL: $fid');

                    // Store FID in place ID if we don't have one yet
                    if (placeId == null || placeId.isEmpty) {
                      placeId = 'ftid:$fid';
                    }
                  }
                }
              }

              // Check if resolved URL contains coordinates in standard format
              final coordsRegex = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)');
              final match = coordsRegex.firstMatch(resolvedUrl);

              if (match != null && match.groupCount >= 2) {
                latitude = double.parse(match.group(1)!);
                longitude = double.parse(match.group(2)!);
                print(
                    '🗺️ MAPS: Extracted coordinates from resolved URL: $latitude, $longitude');
              } else {
                // Try to extract from query parameters
                final uri = Uri.parse(resolvedUrl);

                // Check for data parameter that might contain coordinates
                String? dataParam = uri.path.contains('data=')
                    ? uri.path.substring(uri.path.indexOf('data='))
                    : uri.queryParameters['data'];

                if (dataParam != null) {
                  print('🗺️ MAPS: Found data parameter: $dataParam');

                  // Try to extract place ID from data parameter
                  RegExp dataPlaceIdRegex = RegExp(r'!1s([a-zA-Z0-9:_-]+)');
                  Match? dataPlaceIdMatch =
                      dataPlaceIdRegex.firstMatch(dataParam);

                  if (dataPlaceIdMatch != null &&
                      dataPlaceIdMatch.groupCount >= 1) {
                    placeId = dataPlaceIdMatch.group(1);
                    print(
                        '🗺️ MAPS: Extracted place ID from data parameter: $placeId');
                  }
                }

                if (uri.queryParameters.containsKey('q')) {
                  final query = uri.queryParameters['q']!;
                  print(
                      '🗺️ MAPS: Found query parameter in resolved URL: $query');

                  if (_containsOnlyCoordinates(query)) {
                    final parts = query.split(',');
                    if (parts.length == 2) {
                      latitude = double.parse(parts[0]);
                      longitude = double.parse(parts[1]);
                      print(
                          '🗺️ MAPS: Extracted coordinates from query: $latitude, $longitude');
                    }
                  } else if (locationName == null) {
                    // Query might be a place name
                    locationName = query;
                  }
                }
              }
            } else {
              print(
                  '🗺️ MAPS ERROR: Failed to follow redirect, status code: ${response.statusCode}');
            }
          } catch (e) {
            print('🗺️ MAPS ERROR: Failed to follow redirect: $e');
          }

          // Increment retry counter if we failed
          if (!success) {
            retryCount++;
            print('🗺️ MAPS: Retry attempt $retryCount of $maxRetries');
            // Add a small delay before retrying
            await Future.delayed(Duration(milliseconds: 500 * retryCount));
          }
        }

        // If all retries failed, log a final error
        if (!success) {
          print('🗺️ MAPS ERROR: All $maxRetries redirect attempts failed');

          // Fallback: Try direct extraction of data from shortened URL
          print('🗺️ MAPS: Trying fallback method - direct extraction');

          // If we have a shortened URL, we can try to extract the ID part
          // Most goo.gl/maps URLs use a format where the last part is an identifier
          try {
            final uri = Uri.parse(url);
            final pathSegments = uri.pathSegments;

            if (pathSegments.isNotEmpty) {
              // Get the last segment which is often the identifier
              final idPart = pathSegments.last;
              print('🗺️ MAPS: Extracted ID part from shortened URL: $idPart');

              // If we have a location name from earlier attempts, use it
              if (locationName != null) {
                print(
                    '🗺️ MAPS: Using previously extracted location name: $locationName');

                // Use the place search function as a fallback
                final GoogleMapsService mapsService = GoogleMapsService();
                final results = await mapsService.searchPlaces(locationName);

                if (results.isNotEmpty) {
                  final placeResult = results.first;

                  // Update with found data
                  latitude = placeResult['latitude'] as double?;
                  longitude = placeResult['longitude'] as double?;
                  placeId = placeResult['placeId'] as String?;

                  // Use address if we don't have one yet
                  if (addressText == null) {
                    addressText = placeResult['address'] as String?;
                  }

                  print('🗺️ MAPS: Fallback method successful!');
                  print('🗺️ MAPS: Updated place ID: $placeId');
                  print('🗺️ MAPS: Coordinates: $latitude, $longitude');
                  print('🗺️ MAPS: Address: ${addressText ?? 'Not available'}');

                  // If fallback worked, mark as success
                  success = true;
                } else {
                  print('🗺️ MAPS: Fallback search returned no results');
                }
              } else {
                print(
                    '🗺️ MAPS: No location name available for fallback search');
              }
            }
          } catch (e) {
            print('🗺️ MAPS ERROR: Fallback method also failed: $e');
          }
        }
      }

      // If we have a place ID but missing coordinates or name, get place details
      if (placeId != null &&
          (latitude == null || longitude == null || locationName == null)) {
        print('🗺️ MAPS: Have place ID, fetching place details: $placeId');

        // Check if we need to use search by name instead of place ID
        if (placeId.startsWith('0x') ||
            placeId.startsWith('cid:') ||
            placeId.startsWith('ftid:')) {
          print('🗺️ MAPS: Using name search instead of non-standard place ID');

          // Skip to the search by name approach
          if (locationName != null) {
            // Use the full location name including address for accurate search
            String searchName = locationName;

            print('🗺️ MAPS: Searching for location by name: "$searchName"');
            try {
              final GoogleMapsService mapsService = GoogleMapsService();
              final results = await mapsService.searchPlaces(searchName);

              if (results.isNotEmpty) {
                // Try to find exact match based on the address if we have multiple results
                Map<String, dynamic>? exactMatch;

                // Extract address part from full location name (after the first comma)
                String? addressPart;
                if (locationName.contains(',')) {
                  addressPart = locationName
                      .substring(locationName.indexOf(',') + 1)
                      .trim();
                  print('🗺️ MAPS: Looking for address match: "$addressPart"');
                }

                // If we have an address part, look for an exact match
                if (addressPart != null && results.length > 1) {
                  for (var place in results) {
                    String? placeAddress = place['address'] as String?;
                    if (placeAddress != null) {
                      // Check if this address matches the address part from our location name
                      if (placeAddress.contains(addressPart)) {
                        exactMatch = place;
                        print(
                            '🗺️ MAPS: Found exact address match: $placeAddress');
                        break;
                      }
                    }
                  }
                }

                // Use the exact match if found, otherwise use the first result
                final placeResult = exactMatch ?? results.first;

                // Update with found data
                latitude = placeResult['latitude'] as double?;
                longitude = placeResult['longitude'] as double?;
                String? standardPlaceId = placeResult['placeId'] as String?;

                // Use address if we don't have one yet
                if (addressText == null) {
                  addressText = placeResult['address'] as String?;
                }

                print('🗺️ MAPS: Found place by name search');
                print('🗺️ MAPS: Updated coordinates: $latitude, $longitude');
                print(
                    '🗺️ MAPS: Standard place ID: ${standardPlaceId ?? "Not found"}');
                print('🗺️ MAPS: Address: ${addressText ?? "Not available"}');

                // If we have a standard place ID now, try to get more details
                if (standardPlaceId != null && standardPlaceId.isNotEmpty) {
                  try {
                    print(
                        '🗺️ MAPS: Getting more details with standard place ID: $standardPlaceId');
                    final placeDetails =
                        await mapsService.getPlaceDetails(standardPlaceId);

                    if (placeDetails != null) {
                      // Keep the original placeId for reference but use standard one internally
                      placeId = standardPlaceId;

                      // Update with more detailed information
                      latitude = placeDetails.latitude;
                      longitude = placeDetails.longitude;
                      addressText = placeDetails.address;

                      print('🗺️ MAPS: Got detailed place info');
                      print(
                          '🗺️ MAPS: Updated coordinates: $latitude, $longitude');
                      print(
                          '🗺️ MAPS: Updated address: ${addressText ?? "Not available"}');
                    }
                  } catch (e) {
                    print(
                        '🗺️ MAPS ERROR: Failed to get detailed place info: $e');
                    // Continue with the data we have from search
                  }
                }
              } else {
                print(
                    '🗺️ MAPS: No search results found for name: "$searchName"');
              }
            } catch (e) {
              print('🗺️ MAPS ERROR: Failed to search by name: $e');
            }
          } else {
            print('🗺️ MAPS ERROR: No location name available for search');
          }
        } else {
          // This is a standard place ID, proceed with normal place details lookup
          try {
            final GoogleMapsService mapsService = GoogleMapsService();
            final placeDetails = await mapsService.getPlaceDetails(placeId);

            if (placeDetails != null) {
              // Extract coordinate geometry from place details
              if (latitude == null || longitude == null) {
                // Use direct property access for Location object
                latitude = placeDetails.latitude;
                longitude = placeDetails.longitude;
                print(
                    '🗺️ MAPS: Got coordinates from place details: $latitude, $longitude');
              }

              // Extract name if not already set
              if (locationName == null) {
                locationName = placeDetails.displayName;
                print(
                    '🗺️ MAPS: Got place name from place details: $locationName');
              }

              // Extract formatted address
              if (addressText == null) {
                addressText = placeDetails.address;
                print('🗺️ MAPS: Got address from place details: $addressText');
              }
            }
          } catch (e) {
            print('🗺️ MAPS ERROR: Failed to get place details: $e');
          }
        }
      }

      // If we have a place ID that needs conversion, try finding the place by name
      if (placeId == 'SEARCH_BY_NAME' && locationName != null) {
        print(
            '🗺️ MAPS: Place ID needs conversion, searching by name: $locationName');
        try {
          final GoogleMapsService mapsService = GoogleMapsService();

          // Use the full name and address for accurate search
          String searchName = locationName;

          print('🗺️ MAPS: Searching for location with query: "$searchName"');
          final results = await mapsService.searchPlaces(searchName);

          if (results.isNotEmpty) {
            // Try to find exact match based on the address if we have multiple results
            Map<String, dynamic>? exactMatch;

            // Extract address part from full location name (after the first comma)
            String? addressPart;
            if (locationName.contains(',')) {
              addressPart =
                  locationName.substring(locationName.indexOf(',') + 1).trim();
              print('🗺️ MAPS: Looking for address match: "$addressPart"');
            }

            // If we have an address part, look for an exact match
            if (addressPart != null && results.length > 1) {
              for (var place in results) {
                String? placeAddress = place['address'] as String?;
                if (placeAddress != null) {
                  // Check if this address matches the address part from our location name
                  if (placeAddress.contains(addressPart)) {
                    exactMatch = place;
                    print('🗺️ MAPS: Found exact address match: $placeAddress');
                    break;
                  }
                }
              }
            }

            // Use the exact match if found, otherwise use the first result
            final placeResult = exactMatch ?? results.first;

            // Update with found data
            latitude = placeResult['latitude'] as double?;
            longitude = placeResult['longitude'] as double?;
            placeId = placeResult['placeId'] as String?;

            // Use address if we don't have one yet
            if (addressText == null) {
              addressText = placeResult['address'] as String?;
            }

            print('🗺️ MAPS: Found place by name search');
            print('🗺️ MAPS: Updated place ID: $placeId');
            print('🗺️ MAPS: Coordinates: $latitude, $longitude');
            print('🗺️ MAPS: Address: ${addressText ?? 'Not available'}');

            // If we've got a valid place ID, try to get more detailed information
            if (placeId != null &&
                placeId.isNotEmpty &&
                !placeId.startsWith('0x')) {
              print(
                  '🗺️ MAPS: Getting more details with standard place ID: $placeId');
              try {
                final placeDetails = await mapsService.getPlaceDetails(placeId);
                if (placeDetails != null) {
                  // Update with more detailed information
                  if (latitude == null || longitude == null) {
                    latitude = placeDetails.latitude;
                    longitude = placeDetails.longitude;
                  }

                  if (addressText == null) {
                    addressText = placeDetails.address;
                  }

                  print(
                      '🗺️ MAPS: Successfully retrieved detailed place information');
                }
              } catch (e) {
                print(
                    '🗺️ MAPS ERROR: Unable to get detailed place information: $e');
                // Continue with what we already have
              }
            }
          } else {
            print('🗺️ MAPS: No search results found for query: "$searchName"');
          }
        } catch (e) {
          print('🗺️ MAPS ERROR: Failed to search by name: $e');
        }
      }

      // If we have coordinates but no name, try reverse geocoding
      if (latitude != null && longitude != null && locationName == null) {
        print(
            '🗺️ MAPS: Have coordinates but no name, attempting reverse geocoding');

        // Use Google Maps Service to get location details
        try {
          final GoogleMapsService mapsService = GoogleMapsService();
          final results =
              await mapsService.searchNearbyPlaces(latitude, longitude);

          if (results.isNotEmpty) {
            final placeResult = results.first;
            locationName = placeResult['name'] as String?;
            placeId = placeResult['placeId'] as String?;
            addressText = placeResult['vicinity'] as String?;

            print('🗺️ MAPS: Reverse geocoding successful');
            print('🗺️ MAPS: Found place: ${locationName ?? 'Unknown'}');
            print('🗺️ MAPS: Place ID: ${placeId ?? 'Not available'}');
            print('🗺️ MAPS: Address: ${addressText ?? 'Not available'}');
          }
        } catch (e) {
          print('🗺️ MAPS ERROR: Reverse geocoding failed: $e');
        }
      }

      // If we have a location name but no coordinates, search for the place
      if (locationName != null &&
          (latitude == null || longitude == null) &&
          (placeId == null ||
              (!placeId.startsWith('0x') &&
                  !placeId.startsWith('cid:') &&
                  !placeId.startsWith('ftid:')))) {
        print(
            '🗺️ MAPS: Have name but no coordinates, searching for place: $locationName');

        try {
          final GoogleMapsService mapsService = GoogleMapsService();

          // Extract just the business name to improve search results
          String searchName = locationName;
          if (locationName.contains(',')) {
            searchName = locationName.substring(0, locationName.indexOf(','));
          }

          print('🗺️ MAPS: Searching with query: "$searchName"');
          final results = await mapsService.searchPlaces(searchName);

          if (results.isNotEmpty) {
            final placeResult = results.first;

            latitude = placeResult['latitude'] as double?;
            longitude = placeResult['longitude'] as double?;

            if (placeId == null) {
              placeId = placeResult['placeId'] as String?;
            }

            // Use address if we don't have one yet
            if (addressText == null) {
              addressText = placeResult['address'] as String?;
            }

            print('🗺️ MAPS: Place search successful');
            print('🗺️ MAPS: Coordinates: $latitude, $longitude');
            print('🗺️ MAPS: Place ID: ${placeId ?? 'Not available'}');
            print('🗺️ MAPS: Address: ${addressText ?? 'Not available'}');
          }
        } catch (e) {
          print('🗺️ MAPS ERROR: Place search failed: $e');
        }
      }

      // If we still don't have enough information but have a location name,
      // we'll create a minimal result with just the name
      if ((latitude == null || longitude == null) && locationName != null) {
        print('🗺️ MAPS: Creating minimal result with just location name');
        // Create a basic location with just the name
        final location = Location(
          placeId: placeId,
          latitude: latitude ?? 0.0,
          longitude: longitude ?? 0.0,
          address: addressText,
          displayName: locationName,
        );

        return {
          'location': location,
          'placeName': locationName,
          'mapsUrl': url,
        };
      }

      // If we still don't have enough information, return null
      if (latitude == null || longitude == null) {
        print(
            '🗺️ MAPS ERROR: Could not extract sufficient location data from URL');
        return null;
      }

      // Get website URL if we have a place ID
      String? mapWebsiteUrl = '';
      String? photoUrl = '';
      if (placeId != null &&
          placeId.isNotEmpty &&
          !placeId.startsWith('0x') &&
          !placeId.startsWith('cid:') &&
          !placeId.startsWith('ftid:')) {
        try {
          // Make API call to get website URL and photos
          final apiKey = GoogleMapsService.apiKey;
          final detailsUrl =
              'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&fields=name,formatted_address,website,photos&key=$apiKey';

          final dio = Dio();
          final response = await dio.get(detailsUrl);

          if (response.statusCode == 200) {
            final data = response.data;
            if (data['status'] == 'OK' && data['result'] != null) {
              final result = data['result'];

              // Get website if available
              mapWebsiteUrl = result['website'] ?? '';
              print('🗺️ MAPS: Found website URL: $mapWebsiteUrl');

              // Get photo if available
              if (result['photos'] != null &&
                  (result['photos'] as List).isNotEmpty) {
                // First try to find a primary/main photo
                String? photoReference;
                for (var photo in result['photos']) {
                  if (photo['is_primary'] == true || photo['is_main'] == true) {
                    photoReference = photo['photo_reference'];
                    print('🗺️ MAPS: Found primary photo');
                    break;
                  }
                }

                // If no primary photo found, use the first (most recent) photo
                if (photoReference == null) {
                  photoReference = result['photos'][0]['photo_reference'];
                  print('🗺️ MAPS: Using most recent photo');
                }

                photoUrl =
                    'https://maps.googleapis.com/maps/api/place/photo?photo_reference=$photoReference&maxwidth=800&key=$apiKey';
              }
            }
          }
        } catch (e) {
          print('🗺️ MAPS ERROR: Failed to get place details: $e');
        }
      }

      // Create a location object with the data we've collected
      final location = Location(
        placeId: placeId,
        latitude: latitude,
        longitude: longitude,
        address: addressText,
        displayName: locationName ?? 'Shared Location',
        photoUrl: photoUrl,
      );

      print('🗺️ MAPS: Successfully created location object');
      print('🗺️ MAPS: Location name: ${location.displayName}');
      print(
          '🗺️ MAPS: Coordinates: ${location.latitude}, ${location.longitude}');
      print('🗺️ MAPS: Address: ${location.address ?? 'Not available'}');
      print('🗺️ MAPS: Place ID: ${location.placeId ?? 'Not available'}');

      return {
        'location': location,
        'placeName': locationName ?? 'Shared Location',
        'mapsUrl': url,
        'website': mapWebsiteUrl,
      };
    } catch (e) {
      print('🗺️ MAPS ERROR: Error processing Maps URL: $e');
      print(e.toString());
      return null;
    }
  }

  // Fill the form fields with the location data from Maps
  void _fillFormWithMapData(
      Location location, String placeName, String mapsUrl) {
    // Only autofill if we have a first experience card
    if (_experienceCards.isEmpty) return;

    // Get the first experience
    final experienceCard = _experienceCards.first;
    final formController = experienceCard.formKey.currentState;

    if (formController != null) {
      // Set location
      experienceCard.location = location;

      // Update the form fields
      experienceCard.locationController.text = placeName;

      // Check if we have a category to autofill
      if (experienceCard.categoryController.text.isEmpty) {
        // Default to "Attraction" or other appropriate category
        experienceCard.categoryController.text =
            ExperienceType.attraction.displayName;
      }
    }
  }

  /// Build a preview widget for a Google Maps URL
  Widget _buildMapsPreview(String url) {
    // Create a stable key for the FutureBuilder to prevent unnecessary rebuilds
    final String urlKey = url.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

    // Try to extract location name from URL for fallback display
    String fallbackPlaceName = _extractLocationNameFromMapsUrl(url);

    print("🗺️ MAPS PREVIEW: Starting preview generation for URL: $url");
    print(
        "🗺️ MAPS PREVIEW: Extracted fallback place name: $fallbackPlaceName");

    // Get or create the future - prevents reloading when the experience card is expanded/collapsed
    if (!_yelpPreviewFutures.containsKey(url)) {
      print("🗺️ MAPS PREVIEW: Creating new future for URL: $url");
      _yelpPreviewFutures[url] = _getLocationFromMapsUrl(url);
    } else {
      print("🗺️ MAPS PREVIEW: Using cached future for URL: $url");
    }

    return FutureBuilder<Map<String, dynamic>?>(
      key: ValueKey('maps_preview_$urlKey'),
      future: _yelpPreviewFutures[url],
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          print("🗺️ MAPS PREVIEW: Loading state - waiting for data");
          return _buildMapsLoadingPreview();
        }

        // If we have data, build the complete preview
        if (snapshot.data != null) {
          final data = snapshot.data!;
          final location = data['location'] as Location;
          final placeName = data['placeName'] as String;
          final mapsUrl = data['mapsUrl'] as String;
          final website = data['website'] as String? ?? '';

          print("🗺️ MAPS PREVIEW: Success! Building detailed preview");
          print("🗺️ MAPS PREVIEW: Place name: $placeName");
          print(
              "🗺️ MAPS PREVIEW: Location data: lat=${location.latitude}, lng=${location.longitude}");
          print("🗺️ MAPS PREVIEW: Address: ${location.address}");
          print("🗺️ MAPS PREVIEW: Website URL: $website");

          return _buildMapsDetailedPreview(location, placeName, mapsUrl,
              websiteUrl: website);
        }

        // If snapshot has error, log it
        if (snapshot.hasError) {
          print("🗺️ MAPS PREVIEW ERROR: ${snapshot.error}");
          print("🗺️ MAPS PREVIEW: Using fallback preview due to error");
        } else {
          print("🗺️ MAPS PREVIEW: No data received, using fallback preview");
        }

        // If we have an error or no data, build a fallback preview
        return _buildMapsFallbackPreview(url, fallbackPlaceName);
      },
    );
  }

  // Extract a location name from a Google Maps URL
  String _extractLocationNameFromMapsUrl(String url) {
    try {
      String locationName = "Shared Location";

      // Try to extract a place name from query parameter
      final Uri uri = Uri.parse(url);
      final queryParams = uri.queryParameters;

      if (queryParams.containsKey('q')) {
        final query = queryParams['q']!;
        if (query.isNotEmpty && !_containsOnlyCoordinates(query)) {
          locationName = query;
        }
      }

      return locationName;
    } catch (e) {
      return "Shared Location";
    }
  }

  // Check if a string contains only coordinates
  bool _containsOnlyCoordinates(String text) {
    // Pattern for latitude,longitude format
    RegExp coordPattern = RegExp(r'^-?\d+\.\d+,-?\d+\.\d+$');
    return coordPattern.hasMatch(text);
  }

  // Loading state for Maps preview
  Widget _buildMapsLoadingPreview() {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        height: 350,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.blue),
            SizedBox(height: 16),
            Text(
              'Loading location details...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Detailed preview when we have location data for Maps
  Widget _buildMapsDetailedPreview(
      Location location, String placeName, String mapsUrl,
      {String? websiteUrl}) {
    print('🗺️ PREVIEW: Building detailed Maps preview');
    print('🗺️ PREVIEW: Place name: "$placeName"');
    print(
        '🗺️ PREVIEW: Location - lat: ${location.latitude}, lng: ${location.longitude}');
    print('🗺️ PREVIEW: Address: ${location.address}');
    print('🗺️ PREVIEW: Maps URL: $mapsUrl');
    print('🗺️ PREVIEW: Website URL: ${websiteUrl ?? "Not available"}');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Preview container with tap functionality
        InkWell(
          onTap: () => _launchUrl(mapsUrl),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Photo or map preview
                Container(
                  height: 180,
                  width: double.infinity,
                  child: ClipRRect(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Use actual photo if available, otherwise fall back to static map
                        if (location.photoUrl != null)
                          Image.network(
                            location.photoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              print('Error loading photo: $error');
                              return _getLocationMapImage(location);
                            },
                          )
                        else
                          _getLocationMapImage(location),
                        // Gradient overlay
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.3),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Location details
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Google Maps logo and place name
                      Row(
                        children: [
                          Icon(Icons.place, color: Colors.red, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              location.displayName ?? placeName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),

                      // Address
                      if (location.address != null) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.location_on,
                                size: 16, color: Colors.grey[600]),
                            SizedBox(width: 6),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  print(
                                      '🧭 ADDRESS: Opening map for ${location.latitude}, ${location.longitude}');
                                  // Open map to show location with higher zoom level
                                  if (location.placeId != null &&
                                      location.placeId!.isNotEmpty) {
                                    // Use the Google Maps search API with place_id format
                                    final placeUrl =
                                        'https://www.google.com/maps/search/?api=1&query=${location.displayName ?? placeName}&query_place_id=${location.placeId}';
                                    print(
                                        '🧭 ADDRESS: Opening URL with placeId: $placeUrl');
                                    await _launchUrl(placeUrl);
                                  } else {
                                    // Fallback to coordinate-based URL with zoom parameter
                                    final zoom = 18;
                                    final url =
                                        'https://www.google.com/maps/search/?api=1&query=${location.latitude},${location.longitude}';
                                    print(
                                        '🧭 ADDRESS: Opening URL with coordinates: $url');
                                    await _launchUrl(url);
                                  }
                                },
                                child: Text(
                                  location.address!,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[800],
                                    decoration: TextDecoration.underline,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Buttons below the container
        SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: Icon(Icons.directions, size: 18),
                label: Text('Get Directions'),
                onPressed: () async {
                  print(
                      '🧭 DIRECTIONS: Getting directions for ${location.latitude}, ${location.longitude}');
                  final GoogleMapsService mapsService = GoogleMapsService();
                  final url = mapsService.getDirectionsUrl(
                      location.latitude, location.longitude);
                  print('🧭 DIRECTIONS: Opening URL: $url');
                  await _launchUrl(url);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Widget to display a static map image
  Widget _getLocationMapImage(Location location) {
    print(
        '🗺️ MAP: Getting map image for coordinates: ${location.latitude}, ${location.longitude}');
    print(
        '🗺️ MAP: Location display name: ${location.displayName ?? "Not available"}');

    // Check if we have a placeId to use Google Places API
    if (location.placeId != null && location.placeId!.isNotEmpty) {
      print('🗺️ MAP: Using Places API with placeId: ${location.placeId}');

      return FutureBuilder<String?>(
        future: GoogleMapsService().getPlaceImageUrl(location.placeId!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Container(
              color: Colors.grey[200],
              child: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          if (snapshot.hasData && snapshot.data != null) {
            final imageUrl = snapshot.data!;
            print(
                '🗺️ MAP: Places API returned image URL for specific location: $imageUrl');

            return Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                print('🗺️ MAP ERROR: Could not load place image: $error');
                // Fall back to static map on error
                return _getStaticMapImage(location);
              },
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  color: Colors.grey[200],
                  child: Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  ),
                );
              },
            );
          } else {
            // Fall back to static map if no place image
            print('🗺️ MAP: No place image found, using static map fallback');
            return _getStaticMapImage(location);
          }
        },
      );
    } else {
      // Fall back to static map if no placeId
      print('🗺️ MAP: No placeId available, using static map');
      return _getStaticMapImage(location);
    }
  }

  // Helper to get a static map image (fallback)
  Widget _getStaticMapImage(Location location) {
    // Get API key
    final apiKey = GoogleMapsService.apiKey;

    // Fix: Manually construct the URL to avoid any domain typos
    final mapUrl = 'https://maps.googleapis.com/maps/api/staticmap'
        '?center=${location.latitude},${location.longitude}'
        '&zoom=15'
        '&size=600x300'
        '&markers=color:red%7C${location.latitude},${location.longitude}'
        '&key=$apiKey';

    // Debug: Print the full map URL
    print(
        '🗺️ MAP DEBUG: Using map URL: ${mapUrl.replaceAll(apiKey, "API_KEY_HIDDEN")}');

    return Image.network(
      mapUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        print('🗺️ MAP ERROR: Could not load map image: $error');
        return Container(
          color: Colors.grey[300],
          child: Center(
            child: Icon(Icons.map, size: 64, color: Colors.blue),
          ),
        );
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: Colors.grey[200],
          child: Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
    );
  }

  // Fallback preview when we don't have location data
  Widget _buildMapsFallbackPreview(String url, String placeName) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Fallback container with Maps styling
        InkWell(
          onTap: () => _launchUrl(url),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Google Maps Logo
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Center(
                    child: Icon(Icons.map, size: 40, color: Colors.blue),
                  ),
                ),
                SizedBox(height: 16),

                // Place Name
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    placeName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(height: 8),

                // Maps URL
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Text(
                    url.length > 30 ? '${url.substring(0, 30)}...' : url,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ),
                SizedBox(height: 24),

                // Small helper text
                Text(
                  'Tap to view this location on Google Maps',
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),

        // No action button needed
        SizedBox(height: 8),
      ],
    );
  }

  // Check if a particular text is special content
  bool _isTextSpecialContent(String text) {
    if (!_isValidUrl(text)) return false;

    return text.contains('yelp.com/biz') ||
        text.contains('yelp.to/') ||
        text.contains('google.com/maps') ||
        text.contains('maps.app.goo.gl') ||
        text.contains('goo.gl/maps');
  }
}

// Separate stateful widget for Instagram Reel embeds
class InstagramReelEmbed extends StatefulWidget {
  final String url;
  final VoidCallback onOpen;

  const InstagramReelEmbed(
      {super.key, required this.url, required this.onOpen});

  @override
  _InstagramReelEmbedState createState() => _InstagramReelEmbedState();
}

class _InstagramReelEmbedState extends State<InstagramReelEmbed> {
  late final WebViewController controller;
  bool isLoading = true;
  bool isExpanded = false; // Track whether the preview is expanded

  @override
  void initState() {
    super.initState();
    _initWebViewController();
  }

  // Method to simulate a tap in the embed container
  void _simulateEmbedTap() {
    // Calculate center of content window
    controller.runJavaScript('''
      (function() {
        try {
          // First approach: Using a simulated click on known elements
          // Find any clickable elements in the Instagram embed
          var embedContainer = document.querySelector('.instagram-media');
          if (embedContainer) {
            console.log('Found Instagram embed container');
            
            // Try to find the top level <a> tag which is usually clickable
            var mainLink = document.querySelector('.instagram-media div a');
            if (mainLink) {
              console.log('Found main Instagram link, simulating click');
              mainLink.click();
              return;
            }
            
            // Try to find any Instagram link
            var anyLink = document.querySelector('a[href*="instagram.com"]');
            if (anyLink) {
              console.log('Found Instagram link, simulating click');
              anyLink.click();
              return;
            }
            
            // If no specific element found, click in the center of the embed
            var rect = embedContainer.getBoundingClientRect();
            var centerX = rect.left + rect.width / 2;
            var centerY = rect.top + rect.height / 2;
            
            console.log('Simulating click at center:', centerX, centerY);
            
            // Create and dispatch click event
            var clickEvent = new MouseEvent('click', {
              view: window,
              bubbles: true,
              cancelable: true,
              clientX: centerX,
              clientY: centerY
            });
            
            embedContainer.dispatchEvent(clickEvent);
            return;
          }
          
          // Second approach: Try to find a media player or embed
          var player = document.querySelector('iframe[src*="instagram.com"]');
          if (player) {
            console.log('Found Instagram iframe, simulating click');
            player.click();
            return;
          }
          
          console.log('Instagram embed container not found');
        } catch (e) {
          console.error('Error in auto-click script:', e);
        }
      })();
    ''');
  }

  void _initWebViewController() {
    controller = WebViewController();

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setUserAgent(
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Progress is reported during page load
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                isLoading = true;
              });
            }
          },
          onPageFinished: (String url) {
            // Try to manually process Instagram embeds
            controller.runJavaScript('''
              console.log('Page finished loading');
              
              // Add tap detection to log when the user taps
              document.addEventListener('click', function(e) {
                console.log('Tapped!!!');
                console.log('Tap target:', e.target);
              }, true);
              
              document.addEventListener('touchstart', function(e) {
                console.log('Tapped!!! (touchstart)');
                console.log('Touch target:', e.target);
              }, true);
            ''').then((_) {
              // Set loading to false after a short delay to ensure embed is processed
              Future.delayed(Duration(milliseconds: 1500), () {
                if (mounted) {
                  setState(() {
                    isLoading = false;
                  });

                  // Auto-simulate a tap in the center of the embed after loading
                  Future.delayed(Duration(milliseconds: 500), () {
                    _simulateEmbedTap();

                    // Try again after a longer delay in case the first attempt doesn't work
                    Future.delayed(Duration(seconds: 2), () {
                      if (mounted) {
                        _simulateEmbedTap();
                      }
                    });
                  });
                }
              });
            });
          },
          onWebResourceError: (WebResourceError error) {
            print("WebView Error: ${error.description}");
            if (mounted) {
              setState(() {
                isLoading = false;
              });
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            // Intercept navigation to external links
            if (!request.url.contains('instagram.com') &&
                !request.url.contains('cdn.instagram.com') &&
                !request.url.contains('cdninstagram.com')) {
              widget.onOpen();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadHtmlString(_generateInstagramEmbedHtml(widget.url));
  }

  // Clean Instagram URL for proper embedding
  String _cleanInstagramUrl(String url) {
    // Try to parse the URL
    try {
      // Parse URL
      Uri uri = Uri.parse(url);

      // Get base path without query parameters
      String cleanUrl = '${uri.scheme}://${uri.host}${uri.path}';

      // Ensure trailing slash if needed
      if (!cleanUrl.endsWith('/')) {
        cleanUrl = '$cleanUrl/';
      }

      return cleanUrl;
    } catch (e) {
      // If parsing fails, try basic string manipulation
      if (url.contains('?')) {
        url = url.split('?')[0];
      }

      // Ensure trailing slash if needed
      if (!url.endsWith('/')) {
        url = '$url/';
      }

      return url;
    }
  }

  // Generate HTML for embedding Instagram content
  String _generateInstagramEmbedHtml(String url) {
    // Clean the URL to ensure proper embedding
    final String cleanUrl = _cleanInstagramUrl(url);

    // Create an Instagram embed with tap detection
    return '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
          body {
            margin: 0;
            padding: 0;
            font-family: Arial, sans-serif;
            overflow: hidden;
            background-color: white;
          }
          .container {
            position: relative;
            height: 100%;
            display: flex;
            justify-content: center;
            align-items: center;
          }
          .embed-container {
            height: 100%;
            max-width: 540px;
            margin: 0 auto;
          }
          iframe {
            border: none !important;
            margin: 0 !important;
            padding: 0 !important;
            height: 100% !important;
          }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="embed-container">
            <blockquote class="instagram-media" data-instgrm-captioned data-instgrm-permalink="$cleanUrl" 
              data-instgrm-version="14" style="background:#FFF; border:0; border-radius:3px; 
              box-shadow:0 0 1px 0 rgba(0,0,0,0.5),0 1px 10px 0 rgba(0,0,0,0.15); 
              margin: 1px; max-width:540px; min-width:326px; padding:0; width:99.375%; width:-webkit-calc(100% - 2px); width:calc(100% - 2px);">
              <div style="padding:16px;">
                <a href="$cleanUrl" style="background:#FFFFFF; line-height:0; padding:0 0; text-align:center; text-decoration:none; width:100%;" target="_blank">
                  <div style="display:flex; flex-direction:row; align-items:center;">
                    <div style="background-color:#F4F4F4; border-radius:50%; flex-grow:0; height:40px; margin-right:14px; width:40px;"></div>
                    <div style="display:flex; flex-direction:column; flex-grow:1; justify-content:center;">
                      <div style="background-color:#F4F4F4; border-radius:4px; flex-grow:0; height:14px; margin-bottom:6px; width:100px;"></div>
                      <div style="background-color:#F4F4F4; border-radius:4px; flex-grow:0; height:14px; width:60px;"></div>
                    </div>
                  </div>
                  <div style="padding:19% 0;"></div>
                  <div style="display:block; height:50px; margin:0 auto 12px; width:50px;">
                    <svg width="50px" height="50px" viewBox="0 0 60 60" version="1.1" xmlns="https://www.w3.org/2000/svg" xmlns:xlink="https://www.w3.org/1999/xlink">
                      <g stroke="none" stroke-width="1" fill="none" fill-rule="evenodd">
                        <g transform="translate(-511.000000, -20.000000)" fill="#000000">
                          <g>
                            <path d="M556.869,30.41 C554.814,30.41 553.148,32.076 553.148,34.131 C553.148,36.186 554.814,37.852 556.869,37.852 C558.924,37.852 560.59,36.186 560.59,34.131 C560.59,32.076 558.924,30.41 556.869,30.41 M541,60.657 C535.114,60.657 530.342,55.887 530.342,50 C530.342,44.114 535.114,39.342 541,39.342 C546.887,39.342 551.658,44.114 551.658,50 C551.658,55.887 546.887,60.657 541,60.657 M541,33.886 C532.1,33.886 524.886,41.1 524.886,50 C524.886,58.899 532.1,66.113 541,66.113 C549.9,66.113 557.115,58.899 557.115,50 C557.115,41.1 549.9,33.886 541,33.886 M565.378,62.101 C565.244,65.022 564.756,66.606 564.346,67.663 C563.803,69.06 563.154,70.057 562.106,71.106 C561.058,72.155 560.06,72.803 558.662,73.347 C557.607,73.757 556.021,74.244 553.102,74.378 C549.944,74.521 548.997,74.552 541,74.552 C533.003,74.552 532.056,74.521 528.898,74.378 C525.979,74.244 524.393,73.757 523.338,73.347 C521.94,72.803 520.942,72.155 519.894,71.106 C518.846,70.057 518.197,69.06 517.654,67.663 C517.244,66.606 516.755,65.022 516.623,62.101 C516.479,58.943 516.448,57.996 516.448,50 C516.448,42.003 516.479,41.056 516.623,37.899 C516.755,34.978 517.244,33.391 517.654,32.338 C518.197,30.938 518.846,29.942 519.894,28.894 C520.942,27.846 521.94,27.196 523.338,26.654 C524.393,26.244 525.979,25.756 528.898,25.623 C532.057,25.479 533.004,25.448 541,25.448 C548.997,25.448 549.943,25.479 553.102,25.623 C556.021,25.756 557.607,26.244 558.662,26.654 C560.06,27.196 561.058,27.846 562.106,28.894 C563.154,29.942 563.803,30.938 564.346,32.338 C564.756,33.391 565.244,34.978 565.378,37.899 C565.522,41.056 565.552,42.003 565.552,50 C565.552,57.996 565.522,58.943 565.378,62.101 M570.82,37.631 C570.674,34.438 570.167,32.258 569.425,30.349 C568.659,28.377 567.633,26.702 565.965,25.035 C564.297,23.368 562.623,22.342 560.652,21.575 C558.743,20.834 556.562,20.326 553.369,20.18 C550.169,20.033 549.148,20 541,20 C532.853,20 531.831,20.033 528.631,20.18 C525.438,20.326 523.257,20.834 521.349,21.575 C519.376,22.342 517.703,23.368 516.035,25.035 C514.368,26.702 513.342,28.377 512.574,30.349 C511.834,32.258 511.326,34.438 511.181,37.631 C511.035,40.831 511,41.851 511,50 C511,58.147 511.035,59.17 511.181,62.369 C511.326,65.562 511.834,67.743 512.574,69.651 C513.342,71.625 514.368,73.296 516.035,74.965 C517.703,76.634 519.376,77.658 521.349,78.425 C523.257,79.167 525.438,79.673 528.631,79.82 C531.831,79.965 532.853,80.001 541,80.001 C549.148,80.001 550.169,79.965 553.369,79.82 C556.562,79.673 558.743,79.167 560.652,78.425 C562.623,77.658 564.297,76.634 565.965,74.965 C567.633,73.296 568.659,71.625 569.425,69.651 C570.167,67.743 570.674,65.562 570.82,62.369 C570.966,59.17 571,58.147 571,50 C571,41.851 570.966,40.831 570.82,37.631"></path>
                          </g>
                        </g>
                      </g>
                    </svg>
                  </div>
                  <div style="padding-top:8px;">
                    <div style="color:#3897f0; font-family:Arial,sans-serif; font-size:14px; font-style:normal; font-weight:550; line-height:18px;">View this on Instagram</div>
                  </div>
                  <div style="padding:12.5% 0;"></div>
                  <div style="display:flex; flex-direction:row; margin-bottom:14px; align-items:center;">
                    <div>
                      <div style="background-color:#F4F4F4; border-radius:50%; height:12.5px; width:12.5px; transform:translateX(0px) translateY(7px);"></div>
                      <div style="background-color:#F4F4F4; height:12.5px; transform:rotate(-45deg) translateX(3px) translateY(1px); width:12.5px; flex-grow:0; margin-right:14px; margin-left:2px;"></div>
                      <div style="background-color:#F4F4F4; border-radius:50%; height:12.5px; width:12.5px; transform:translateX(9px) translateY(-18px);"></div>
                    </div>
                    <div style="margin-left:8px;">
                      <div style="background-color:#F4F4F4; border-radius:50%; flex-grow:0; height:20px; width:20px;"></div>
                      <div style="width:0; height:0; border-top:2px solid transparent; border-left:6px solid #f4f4f4; border-bottom:2px solid transparent; transform:translateX(16px) translateY(-4px) rotate(30deg);"></div>
                    </div>
                    <div style="margin-left:auto;">
                      <div style="width:0px; border-top:8px solid #F4F4F4; border-right:8px solid transparent; transform:translateY(16px);"></div>
                      <div style="background-color:#F4F4F4; flex-grow:0; height:12px; width:16px; transform:translateY(-4px);"></div>
                      <div style="width:0; height:0; border-top:8px solid #F4F4F4; border-left:8px solid transparent; transform:translateY(-4px) translateX(8px);"></div>
                    </div>
                  </div>
                </a>
              </div>
            </blockquote>
            <script async src="//www.instagram.com/embed.js"></script>

            <!-- Tap detection script -->
            <script>
              document.addEventListener('click', function(e) {
                console.log('Tapped!!!');
                console.log('Tap target:', e.target);
              }, true);
              
              document.addEventListener('touchstart', function(e) {
                console.log('Tapped!!! (touchstart)');
                console.log('Touch target:', e.target);
              }, true);
            </script>
          </div>
        </div>
      </body>
      </html>
    ''';
  }

  @override
  Widget build(BuildContext context) {
    // Define the container height based on expansion state
    final double containerHeight = isExpanded ? 1200 : 400;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              isExpanded = !isExpanded; // Toggle expansion state
            });
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: containerHeight, // Use dynamic height based on state
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: WebViewWidget(controller: controller),
              ),
              if (isLoading)
                Container(
                  width: double.infinity,
                  height: containerHeight, // Use dynamic height based on state
                  color: Colors.white.withOpacity(0.7),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading Instagram content...')
                      ],
                    ),
                  ),
                ),
              // No tap to expand indicator
            ],
          ),
        ),
        SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              icon: Icon(Icons.open_in_new),
              label: Text('Open in Instagram'),
              onPressed: widget.onOpen,
              style: OutlinedButton.styleFrom(
                foregroundColor: Color(0xFFE1306C),
              ),
            ),
            SizedBox(width: 8),
            OutlinedButton.icon(
              icon: Icon(isExpanded ? Icons.fullscreen_exit : Icons.fullscreen),
              label: Text(isExpanded ? 'Collapse' : 'Expand'),
              onPressed: () {
                setState(() {
                  isExpanded = !isExpanded;
                });
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Converts a Google Maps place ID format to the standard format expected by Places API
String _convertToStandardPlaceId(String originalPlaceId) {
  // Google Maps URLs use a hexadecimal format like: 0x80dcd7dae0047c6b:0x6a02064e16dc90be
  // Places API expects a format like: ChIJ...

  if (originalPlaceId.startsWith('0x') && originalPlaceId.contains(':0x')) {
    print(
        '🗺️ MAPS: Converting from Google Maps hex format to standard place ID format');

    // If this is a hex encoded place ID, use a different approach
    // Instead of direct conversion, we'll use the Text Search API to find the place by name
    // as conversion algorithms between these formats are proprietary to Google
    return originalPlaceId; // Return original ID, we'll handle it specially above
  }

  // For CID or FID values, also use search by name approach
  if (originalPlaceId.startsWith('cid:') ||
      originalPlaceId.startsWith('ftid:')) {
    print('🗺️ MAPS: Using CID/FID identifier, will search by name instead');
    return originalPlaceId; // Return original ID, we'll handle it specially above
  }

  return originalPlaceId;
}
