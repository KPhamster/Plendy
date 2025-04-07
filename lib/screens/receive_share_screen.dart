import 'package:flutter/material.dart';
import 'dart:math';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart'; // Import Provider
import '../providers/receive_share_provider.dart'; // Import the provider
import '../models/experience.dart';
import '../services/experience_service.dart';
import '../services/google_maps_service.dart';
import '../widgets/google_maps_widget.dart';
import 'location_picker_screen.dart';
import '../services/sharing_service.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'receive_share/widgets/yelp_preview_widget.dart';
import 'receive_share/widgets/maps_preview_widget.dart';
import 'receive_share/widgets/instagram_preview_widget.dart';
import 'receive_share/widgets/generic_url_preview_widget.dart';
import 'receive_share/widgets/image_preview_widget.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:shared_preferences/shared_preferences.dart';
import 'receive_share/widgets/experience_card_form.dart';

/// Data class to hold the state of each experience card
class ExperienceCardData {
  // Form controllers
  final TextEditingController titleController = TextEditingController();
  final TextEditingController yelpUrlController = TextEditingController();
  final TextEditingController websiteController =
      TextEditingController(); // Added
  final TextEditingController searchController = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController categoryController = TextEditingController();
  final TextEditingController notesController =
      TextEditingController(); // Added

  // Form key
  final formKey = GlobalKey<FormState>();

  // Focus nodes
  final FocusNode titleFocusNode = FocusNode();

  // Experience type selection
  ExperienceType selectedType = ExperienceType.restaurant;

  // Rating
  double rating = 0.0; // Added (or use double? rating)

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

  // State for preview rebuilding
  String?
      placeIdForPreview; // Tracks the placeId currently shown in preview - RENAMED from currentPlaceIdForPreview

  // Constructor can set initial values if needed
  ExperienceCardData();

  // Dispose resources
  void dispose() {
    titleController.dispose();
    yelpUrlController.dispose();
    websiteController.dispose(); // Added
    searchController.dispose();
    locationController.dispose();
    categoryController.dispose();
    notesController.dispose(); // Added
    titleFocusNode.dispose();
  }
}

class ReceiveShareScreen extends StatefulWidget {
  final List<SharedMediaFile> sharedFiles;
  final VoidCallback onCancel; // Callback to handle closing/canceling

  const ReceiveShareScreen({
    Key? key,
    required this.sharedFiles,
    required this.onCancel,
  }) : super(key: key);

  @override
  _ReceiveShareScreenState createState() => _ReceiveShareScreenState();
}

class _ReceiveShareScreenState extends State<ReceiveShareScreen>
    with WidgetsBindingObserver {
  // Services
  final ExperienceService _experienceService = ExperienceService();
  final GoogleMapsService _mapsService = GoogleMapsService();
  final SharingService _sharingService = SharingService();

  // Remove local experience card list - managed by Provider now
  // List<ExperienceCardData> _experienceCards = [];

  // Track filled business data to avoid duplicates but also cache results
  Map<String, Map<String, dynamic>> _businessDataCache = {};

  // Form validation key - Now managed within the list of cards?
  // Consider if this should be per-card or one overall key.
  // For now, let's assume each ExperienceCardForm manages its own key.
  // final _formKey = GlobalKey<FormState>();

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

  // Initialize with the files passed to the widget
  List<SharedMediaFile> _currentSharedFiles = [];

  // Subscription for intent data stream
  StreamSubscription<List<SharedMediaFile>>? _intentDataStreamSubscription;

  // Flag to track if a chain was detected from URL structure
  bool _chainDetectedFromUrl = false;

  @override
  void initState() {
    super.initState();
    // Initialize with the files passed to the widget
    _currentSharedFiles = widget.sharedFiles;

    // Register observer for app lifecycle events
    WidgetsBinding.instance.addObserver(this);

    // Access provider - DO NOT listen here, just need read access
    // final provider = context.read<ReceiveShareProvider>();
    // Cards are initialized in the provider's constructor

    // Process the initial shared content
    print(
        "SHARE DEBUG: initState processing initial widget.sharedFiles (count: ${_currentSharedFiles.length})");
    _processSharedContent(_currentSharedFiles);

    // Setup the stream listener
    _setupIntentListener();

    // Handle the initial intent (getInitialMedia might be needed if launched cold)
    ReceiveSharingIntent.instance
        .getInitialMedia()
        .then((List<SharedMediaFile>? value) {
      if (mounted && value != null) {
        print(
            "SHARE DEBUG: getInitialMedia returned ${value.length} files. Current: ${_currentSharedFiles.length}");

        // Check if the incoming list is meaningfully different from the current list
        bool isDifferent = value.isNotEmpty &&
            (_currentSharedFiles
                    .isEmpty || // If current is empty, it's different
                value.length !=
                    _currentSharedFiles.length || // Different number of files
                value.first.path !=
                    _currentSharedFiles
                        .first.path); // Different first file path (basic check)

        if (isDifferent) {
          print(
              "SHARE DEBUG: getInitialMedia has different content - updating UI");
          // Use provider to reset cards
          context.read<ReceiveShareProvider>().resetExperienceCards();
          setState(() {
            _currentSharedFiles = value;
            // Reset UI state NOT related to cards
            _businessDataCache.clear();
            _yelpPreviewFutures.clear();
            // Process the new content
            _processSharedContent(_currentSharedFiles);
          });
        } else {
          print(
              "SHARE DEBUG: getInitialMedia - no different content to process");
        }
      } else if (value == null) {
        print("SHARE DEBUG: getInitialMedia returned null");
      } else {
        print("SHARE DEBUG: getInitialMedia - component not mounted, ignoring");
      }
    });
  }

  // Setup the intent listener
  void _setupIntentListener() {
    // Cancel any existing subscription first
    _intentDataStreamSubscription?.cancel();

    print("SHARE DEBUG: Setting up new intent stream listener");

    // Listen to new intents coming in while the app is running
    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen((List<SharedMediaFile> value) {
      print(
          "SHARE DEBUG: Stream Listener Fired! Received ${value.length} files. Mounted: $mounted");

      if (mounted && value.isNotEmpty) {
        print("SHARE DEBUG: Stream - Updating state with new files.");
        // Use provider to reset cards
        context.read<ReceiveShareProvider>().resetExperienceCards();
        setState(() {
          _currentSharedFiles = value; // Update with the latest files
          // Reset UI state NOT related to cards
          _businessDataCache.clear(); // Clear cache for new content
          _yelpPreviewFutures.clear();
          // Process the new content
          _processSharedContent(_currentSharedFiles);
          // Show a notification
          _showSnackBar(context, "New content received!");
        });

        // Only reset for Android - iOS needs the intent to persist
        if (!Platform.isIOS) {
          // Reset the intent *after* processing
          ReceiveSharingIntent.instance.reset();
          print("SHARE DEBUG: Stream - Intent stream processed and reset.");
        } else {
          print(
              "SHARE DEBUG: On iOS - not resetting intent to ensure it persists");
        }
      } else {
        print(
            "SHARE DEBUG: Stream - Listener fired but not processing (mounted: $mounted, value empty: ${value.isEmpty})");
      }
    }, onError: (err) {
      print("SHARE DEBUG: Error receiving intent stream: $err");
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    print("SHARE DEBUG: App lifecycle state changed to $state");

    // If app resumes from background, re-initialize the intent listener
    if (state == AppLifecycleState.resumed) {
      print("SHARE DEBUG: App resumed - recreating intent listener");
      _setupIntentListener();

      // Also check for any pending intents
      ReceiveSharingIntent.instance.getInitialMedia().then((value) {
        if (value != null && value.isNotEmpty && mounted) {
          print(
              "SHARE DEBUG: Found pending intent after resume: ${value.length} files");
          // Use provider to reset cards
          context.read<ReceiveShareProvider>().resetExperienceCards();
          setState(() {
            _currentSharedFiles = value;
            // Reset UI for new content NOT related to cards
            _businessDataCache.clear();
            _yelpPreviewFutures.clear();
            _addExperienceCard();
            _processSharedContent(_currentSharedFiles);
            _showSnackBar(context, "New content received after resume!");
          });
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    print("SHARE DEBUG: didChangeDependencies called");

    // Ensure the intent listener is setup (in case it was lost)
    _setupIntentListener();
  }

  @override
  void dispose() {
    // Cancel the subscription
    print("SHARE DEBUG: dispose called - cleaning up resources");
    if (_intentDataStreamSubscription != null) {
      _intentDataStreamSubscription!.cancel();
      print("SHARE DEBUG: Intent stream subscription canceled");
    }

    // Unregister observer
    WidgetsBinding.instance.removeObserver(this);

    // Make sure intent is fully reset when screen closes
    if (!Platform.isIOS) {
      ReceiveSharingIntent.instance.reset();
      print("SHARE DEBUG: Intent reset in dispose");
    }

    // No need to dispose cards here, Provider handles it
    // Dispose all controllers for all experience cards
    // for (var card in _experienceCards) {
    //   card.dispose();
    // }
    super.dispose();
  }

  // Add a method to trigger rebuilds from child widgets
  // Remove _triggerRebuild - no longer needed
  /*
  void _triggerRebuild() {
    if (mounted) {
      setState(() {});
    }
  }
  */

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
  void _processSharedContent(List<SharedMediaFile> files) {
    print('DEBUG: Processing shared content');
    if (files.isEmpty) return;

    // Look for Yelp URLs or Map URLs in shared files
    for (final file in files) {
      if (file.type == SharedMediaType.text) {
        String text = file.path;
        print(
            'DEBUG: Checking shared text: ${text.substring(0, min(100, text.length))}...');

        // Check if this is a special URL (Yelp or Maps)
        // Use _isSpecialContent instead of _isTextSpecialContent
        if (_isSpecialContent([file])) {
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
            // Use _isSpecialContent instead of _isTextSpecialContent
            if (_isValidUrl(line.trim()) &&
                _isSpecialContent([
                  SharedMediaFile(path: line.trim(), type: SharedMediaType.text)
                ])) {
              print('DEBUG: Found special URL in multi-line text: $line');
              _processSpecialUrl(line.trim());
              return;
            }
          }
        }
      }
    }
  }

  // Check if the shared content is from Yelp or Google Maps
  bool _isSpecialContent(List<SharedMediaFile> files) {
    if (files.isEmpty) return false;

    for (final file in files) {
      if (file.type == SharedMediaType.text ||
          file.type == SharedMediaType.url) {
        String text = file.path; // Original text
        String textLower =
            text.toLowerCase(); // Lowercase for checking patterns

        // Define patterns for special URLs
        final yelpPattern = RegExp(r'yelp\.(com/biz|to)/'); // Corrected pattern
        final mapsPattern = RegExp(
            r'(google\.com/maps|maps\.app\.goo\.gl|goo\.gl/maps)'); // Corrected pattern

        // Check if the text CONTAINS either Yelp or Maps patterns
        if (yelpPattern.hasMatch(textLower) ||
            mapsPattern.hasMatch(textLower)) {
          // Added check: Ensure there's actually a link present, not just text mentioning Yelp/Maps.
          // This helps avoid false positives if someone shares plain text like "check google.com/maps".
          final urlRegex = RegExp(
              r'https?://'); // Corrected pattern (though likely ok before)
          if (urlRegex.hasMatch(text)) {
            print(
                "DEBUG: _isSpecialContent detected Yelp or Maps pattern in text: ${text.substring(0, min(50, text.length))}..."); // Removed trailing backslash
            return true; // Found a pattern within the text
          }
        }
      }
    }
    // If loop finishes without finding special content, return false
    print("DEBUG: _isSpecialContent did not find Yelp or Maps pattern.");
    return false;
  }

  // Process special URL
  void _processSpecialUrl(String url) {
    final provider = context.read<ReceiveShareProvider>();
    // Ensure at least one card exists before processing
    if (provider.experienceCards.isEmpty) {
      provider.addExperienceCard();
    }
    // Get the (potentially just added) first card
    final firstCard = provider.experienceCards.first;

    if (url.contains('yelp.com/biz') || url.contains('yelp.to/')) {
      print("SHARE DEBUG: Processing as Yelp URL");
      firstCard.yelpUrlController.text = url; // Set URL in the card
      // Use the URL as the initial key for the future
      _yelpPreviewFutures[url] = _getBusinessFromYelpUrl(url);
    } else if (url.contains('google.com/maps') ||
        url.contains('maps.app.goo.gl') ||
        url.contains('goo.gl/maps')) {
      print("SHARE DEBUG: Processing as Google Maps URL");
      // Use the URL as the key for the future
      _yelpPreviewFutures[url] = _getLocationFromMapsUrl(url);
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

  // Modify add/remove to use Provider
  void _addExperienceCard() {
    // Use context.read as we are calling a method, not listening
    context.read<ReceiveShareProvider>().addExperienceCard();
  }

  void _removeExperienceCard(ExperienceCardData card) {
    context.read<ReceiveShareProvider>().removeExperienceCard(card);
    // Check if cards list became empty AFTER removal by provider
    if (context.read<ReceiveShareProvider>().experienceCards.isEmpty) {
      context.read<ReceiveShareProvider>().addExperienceCard();
    }
  }

  /// Extract business data from a Yelp URL and look it up in Google Places API
  Future<Map<String, dynamic>?> _getBusinessFromYelpUrl(String yelpUrl) async {
    print("\n📊 YELP DATA: Starting business lookup for URL: $yelpUrl");

    // Reset chain detection flag for this new URL
    _chainDetectedFromUrl = false;

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
      String businessAddress = "";
      String businessCity = "";
      String businessState = "";
      String businessZip = "";
      String businessType = "";
      String fullSearchText = "";
      bool isShortUrl = url.contains('yelp.to/');

      // Position to bias search results if needed (for chains or generic names)
      Position? userPosition = await _getCurrentPosition();

      // If it's a shortened URL (yelp.to), try to resolve it to get the full URL
      if (isShortUrl) {
        print('📊 YELP DATA: Detected shortened URL, attempting to resolve it');
        try {
          // First try to resolve the shortened URL to get the full URL
          final resolvedUrl = await _resolveShortUrl(url);
          if (resolvedUrl != null &&
              resolvedUrl != url &&
              resolvedUrl.contains('/biz/')) {
            print(
                '📊 YELP DATA: Successfully resolved shortened URL to: $resolvedUrl');
            url = resolvedUrl;
            isShortUrl = false;
          } else {
            print(
                '📊 YELP DATA: Could not resolve shortened URL, continuing with original');
          }
        } catch (e) {
          print('📊 YELP DATA: Error resolving shortened URL: $e');
        }
      }

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

              // Try to extract address information if present
              // Common Yelp share format includes address after business name
              if (text.contains('located at')) {
                final addressPart = text.split('located at')[1].trim();
                businessAddress = addressPart.split('.')[0].trim();
                print('📊 YELP DATA: Extracted address: $businessAddress');

                // Extract city, state, zip if available
                final addressComponents = businessAddress.split(',');
                if (addressComponents.length > 1) {
                  final lastComponent = addressComponents.last.trim();
                  // Attempt to extract state and zip code (common format: "City, ST 12345")
                  final stateZipMatch =
                      RegExp(r'([A-Z]{2})\s+(\d{5})').firstMatch(lastComponent);
                  if (stateZipMatch != null) {
                    businessState = stateZipMatch.group(1) ?? '';
                    businessZip = stateZipMatch.group(2) ?? '';
                    print(
                        '📊 YELP DATA: Extracted state: $businessState, zip: $businessZip');
                  }

                  // Extract city (second to last component is usually the city)
                  if (addressComponents.length > 2) {
                    businessCity =
                        addressComponents[addressComponents.length - 2].trim();
                    print('📊 YELP DATA: Extracted city: $businessCity');
                  }
                }
              }
              // Try to extract city name if present (common format: "Business Name - City")
              else if (businessName.contains('-')) {
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
      if ((businessName.isEmpty || businessCity.isEmpty) &&
          url.contains('/biz/')) {
        // Extract the business part from URL
        // Format: https://www.yelp.com/biz/business-name-location
        final bizPath = url.split('/biz/')[1].split('?')[0];

        print('📊 YELP DATA: Extracting from biz URL path: $bizPath');

        // Check for numeric suffix after city name which indicates a chain location
        bool isChainFromUrl = false;
        final lastPathSegment = bizPath.split('/').last;
        final RegExp numericSuffixRegex = RegExp(r'-(\d+)$');
        final match = numericSuffixRegex.firstMatch(lastPathSegment);

        if (match != null) {
          print(
              '📊 YELP DATA: Detected numeric suffix in URL path, indicating a chain location: ${match.group(1)}');
          isChainFromUrl = true;
        }

        // Convert hyphenated business name to spaces
        final pathParts = bizPath.split('-');

        // If the last part is a number, it indicates a chain location
        // Remove it from the business name
        if (pathParts.isNotEmpty && RegExp(r'^\d+$').hasMatch(pathParts.last)) {
          print(
              '📊 YELP DATA: Removing numeric suffix ${pathParts.last} from business name');
          pathParts.removeLast();
          isChainFromUrl = true;
        }

        // Check if the last part might be a city name
        if (pathParts.isNotEmpty) {
          final possibleCity = pathParts.last;
          // Common city names usually don't contain these words
          final nonCityWords = [
            'restaurant',
            'pizza',
            'cafe',
            'bar',
            'grill',
            'and',
            'the'
          ];
          bool mightBeCity = true;

          for (final word in nonCityWords) {
            if (possibleCity.toLowerCase() == word) {
              mightBeCity = false;
              break;
            }
          }

          if (mightBeCity) {
            businessCity = possibleCity;
            print('📊 YELP DATA: Extracted city from URL path: $businessCity');
            // Remove city from business name
            pathParts.removeLast();
          }
        }

        businessName = pathParts.join(' ');

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

        // If we detected a chain from the URL structure, update our flag
        if (isChainFromUrl) {
          print(
              '📊 YELP DATA: Marked as chain restaurant based on URL structure');
          // Will be used later when checking isChainOrGeneric
          _chainDetectedFromUrl = true;
        }

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

      // 1. Detect that this is a chain restaurant from URL patterns
      bool isChainOrGeneric = _chainDetectedFromUrl;

      // 2. Assume any restaurant with very generic name might be a chain
      if (!isChainOrGeneric && businessName.isNotEmpty) {
        // Common chain restaurant terms
        final chainTerms = [
          'restaurant',
          'cafe',
          'pizza',
          'coffee',
          'bar',
          'grill',
          'bakery'
        ];
        final nameLower = businessName.toLowerCase();

        for (final term in chainTerms) {
          if (nameLower.contains(term) && businessName.split(' ').length < 3) {
            print(
                '📊 YELP DATA: Likely generic chain name detected: $businessName');
            isChainOrGeneric = true;
            break;
          }
        }
      }

      print('📊 YELP DATA: Is chain or generic restaurant: $isChainOrGeneric');

      // If we have a short Yelp URL and couldn't resolve it,
      // try to scrape the Yelp page for more info regardless of chain status
      if (isShortUrl) {
        print(
            '📊 YELP DATA: Attempting to get location details from Yelp page');

        try {
          final extraInfo = await _getLocationDetailsFromYelpPage(url);
          if (extraInfo != null) {
            if (extraInfo['address'] != null &&
                extraInfo['address']!.isNotEmpty) {
              businessAddress = extraInfo['address']!;
              print(
                  '📊 YELP DATA: Extracted address from Yelp page: $businessAddress');
            }
            if (extraInfo['city'] != null && extraInfo['city']!.isNotEmpty) {
              businessCity = extraInfo['city']!;
              print(
                  '📊 YELP DATA: Extracted city from Yelp page: $businessCity');
            }
            if (extraInfo['state'] != null && extraInfo['state']!.isNotEmpty) {
              businessState = extraInfo['state']!;
              print(
                  '📊 YELP DATA: Extracted state from Yelp page: $businessState');
            }
          }
        } catch (e) {
          print('📊 YELP DATA: Error fetching details from Yelp page: $e');
        }
      }

      // If we couldn't extract a business name, use a generic one
      if (businessName.isEmpty) {
        businessName = "Shared Business";
        print('📊 YELP DATA: Using generic business name');
      }

      // Create search strategies in order of most to least specific
      List<String> searchQueries = [];

      // Strategy 1: Business name + city if available (most specific for chains)
      if (businessName.isNotEmpty && businessCity.isNotEmpty) {
        // For chains, exact match with city should be first priority
        if (isChainOrGeneric) {
          searchQueries.add('"$businessName $businessCity"');
          searchQueries.add('$businessName $businessCity');
        } else {
          searchQueries.add('$businessName $businessCity');
          searchQueries.add('"$businessName $businessCity"');
        }
      }

      // Strategy 2: Business name + business type if both available
      if (businessName.isNotEmpty && businessType.isNotEmpty) {
        searchQueries.add('$businessName $businessType');
        // If we also have city data, add with city
        if (businessCity.isNotEmpty) {
          searchQueries.add('$businessName $businessType $businessCity');
        }
      }

      // Strategy 3: Complete share text if available
      if (fullSearchText.isNotEmpty) {
        searchQueries.add(fullSearchText);
      }

      // Strategy 4: Just business name with various qualifiers
      if (businessName.isNotEmpty) {
        // Add "exact" to help find the precise business
        searchQueries.add('"$businessName"');
        searchQueries.add(businessName);
      }

      // Deduplicate search queries
      searchQueries = searchQueries.toSet().toList();

      print('📊 YELP DATA: Search strategies (in order): $searchQueries');

      // Try each search query until we get results
      int searchAttempt = 0;
      for (final query in searchQueries) {
        searchAttempt++;
        print(
            '📊 YELP DATA: Trying Google Places with query: "$query" (Attempt $searchAttempt/${searchQueries.length})');

        // Using Google Places API to search for this business
        List<Map<String, dynamic>> results = [];

        // For chain restaurants or generic names, if we have user location, use it to bias search
        if (isChainOrGeneric && userPosition != null && searchAttempt > 1) {
          print(
              '📊 YELP DATA: Using location-biased search for chain restaurant');
          results = await _mapsService.searchNearbyPlaces(
              userPosition.latitude,
              userPosition.longitude,
              50000, // 50km radius
              query);
          print(
              '📊 YELP DATA: Location-biased search found ${results.length} results');
        } else {
          // Standard search for non-chains or first attempt
          results = await _mapsService.searchPlaces(query);
        }

        print(
            '📊 YELP DATA: Got ${results.length} search results from Google Places for query "$query"');

        if (results.isNotEmpty) {
          print(
              '📊 YELP DATA: Results found! First result: ${results[0]['description']}');

          // For chain restaurants, check if we can find a better match using address info
          int resultIndex = 0;
          if (isChainOrGeneric && results.length > 1) {
            // Try to find the best match based on address components if available
            if (businessAddress.isNotEmpty || businessCity.isNotEmpty) {
              print(
                  '📊 YELP DATA: Comparing multiple locations for chain restaurant');

              resultIndex = _findBestMatch(
                  results, businessAddress, businessCity, businessState);
              print(
                  '📊 YELP DATA: Selected result #${resultIndex + 1} as best match');
            }
          }

          // Get details of the selected result
          final placeId = results[resultIndex]['placeId'];
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

          // Verify this is the correct business by checking name and address match
          bool isCorrectBusiness = true;

          // Name verification: If we have a business name, check that the Google result contains key parts
          if (!isChainOrGeneric &&
              businessName.isNotEmpty &&
              location.displayName != null) {
            // Simple verification: Check if key words from the business name appear in the Google result
            final businessNameWords = businessName
                .toLowerCase()
                .split(' ')
                .where(
                    (word) => word.length > 3) // Only check significant words
                .toList();

            if (businessNameWords.isNotEmpty) {
              final googleNameLower = location.displayName!.toLowerCase();

              // Count how many key words match
              int matchCount = 0;
              for (final word in businessNameWords) {
                if (googleNameLower.contains(word)) {
                  matchCount++;
                }
              }

              // If less than half of the key words match, it's probably not the right business
              if (matchCount < businessNameWords.length / 2) {
                print(
                    '📊 YELP DATA: Name verification failed. Google name "${location.displayName}" doesn\'t match Yelp name "$businessName"');
                isCorrectBusiness = false;
              }
            }
          }

          // Address verification: If we have a business address, check that the Google result address contains key parts
          if (isCorrectBusiness &&
              businessAddress.isNotEmpty &&
              location.address != null) {
            // We know from testing that Yelp shares don't include reliable address information
            // So we'll skip detailed address verification
            print(
                '📊 YELP DATA: Skipping address verification as Yelp shares do not contain reliable address data');
          }

          // Special verification for chain restaurants
          if (isChainOrGeneric) {
            if (businessCity.isNotEmpty && location.city != null) {
              // For chains, city match is critical
              if (!location.city!
                      .toLowerCase()
                      .contains(businessCity.toLowerCase()) &&
                  !businessCity
                      .toLowerCase()
                      .contains(location.city!.toLowerCase())) {
                print(
                    '📊 YELP DATA: City verification failed for chain. Google city "${location.city}" doesn\'t match Yelp city "$businessCity"');
                isCorrectBusiness = false;
                print(
                    '📊 YELP DATA: Will try next search strategy that includes city name');
              } else {
                print(
                    '📊 YELP DATA: City match confirmed for chain restaurant');
              }
            }
          }

          // If verification failed, try next search query
          if (!isCorrectBusiness) {
            print(
                '📊 YELP DATA: Verification failed, trying next search strategy');
            continue;
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

      // If all strategies failed and we have a chain restaurant, try a final attempt with nearby search
      if (isChainOrGeneric && userPosition != null) {
        print(
            '📊 YELP DATA: All strategies failed for chain restaurant, trying nearby search');

        // Search for the chain in a large radius around the user
        final nearbyResults = await _mapsService.searchNearbyPlaces(
            userPosition.latitude,
            userPosition.longitude,
            50000, // 50km radius
            businessName);

        if (nearbyResults.isNotEmpty) {
          print(
              '📊 YELP DATA: Nearby search found ${nearbyResults.length} results');

          // Get the first result
          final placeId = nearbyResults[0]['placeId'];
          final location = await _mapsService.getPlaceDetails(placeId);

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

          print('📊 YELP DATA: Successfully found nearby chain location');
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

  // Helper method to resolve a shortened URL to its full URL
  Future<String?> _resolveShortUrl(String shortUrl) async {
    print("🔗 RESOLVE: Attempting to resolve URL: $shortUrl"); // Keep log
    try {
      // Reverted back to Dio implementation
      final dio = Dio(BaseOptions(
        followRedirects:
            false, // Important: Do not follow redirects automatically
        validateStatus: (status) =>
            status != null && status < 500, // Allow redirect statuses
      ));

      final response = await dio.get(shortUrl);

      // Check if it's a redirect status
      if (response.statusCode == 301 ||
          response.statusCode == 302 ||
          response.statusCode == 307 || // Handle temporary redirects too
          response.statusCode == 308) {
        // Extract the 'location' header
        final redirectUrl = response.headers.map['location']?.first;
        if (redirectUrl != null) {
          print(
              "🔗 RESOLVE: Successfully resolved via Location header to: $redirectUrl");
          return redirectUrl;
        }
      }

      print("🔗 RESOLVE: No redirect status or Location header found.");
      return null; // Not a redirect or missing header
    } catch (e) {
      print("🔗 RESOLVE ERROR: Error resolving short URL $shortUrl: $e");
      return null;
    }
  }

  // Attempt to get location details from Yelp page HTML
  Future<Map<String, String>?> _getLocationDetailsFromYelpPage(
      String url) async {
    try {
      final dio = Dio();
      final response = await dio.get(url);

      if (response.statusCode == 200) {
        final html = response.data.toString();

        // Simple regex-based extraction of address information
        // Look for address in the page content
        final addressRegex = RegExp(r'address":"([^"]+)');
        final addressMatch = addressRegex.firstMatch(html);

        final cityRegex = RegExp(r'addressLocality":"([^"]+)');
        final cityMatch = cityRegex.firstMatch(html);

        final stateRegex = RegExp(r'addressRegion":"([^"]+)');
        final stateMatch = stateRegex.firstMatch(html);

        if (addressMatch != null || cityMatch != null || stateMatch != null) {
          return {
            'address': addressMatch?.group(1) ?? '',
            'city': cityMatch?.group(1) ?? '',
            'state': stateMatch?.group(1) ?? '',
          };
        }
      }

      return null;
    } catch (e) {
      print('Error fetching Yelp page: $e');
      return null;
    }
  }

  // Helper method to get current user position for location-biased searches
  Future<Position?> _getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('📊 YELP DATA: Location services are disabled');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('📊 YELP DATA: Location permission denied');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('📊 YELP DATA: Location permission permanently denied');
        return null;
      }

      // Get last known position as it's faster than getCurrentPosition
      Position? position = await Geolocator.getLastKnownPosition();

      // If we don't have a last known position, get current position
      if (position == null) {
        position = await Geolocator.getCurrentPosition();
      }

      print(
          '📊 YELP DATA: Got user position: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      print('📊 YELP DATA: Error getting position: $e');
      return null;
    }
  }

  // Helper method to find the best matching result from a list of places
  // Simplified to prioritize exact city matches for chain restaurants
  int _findBestMatch(List<Map<String, dynamic>> results, String address,
      String city, String state) {
    if (results.isEmpty || results.length == 1) return 0;

    // Only try to find a match with city if we have it
    if (city.isNotEmpty) {
      print('📊 YELP DATA: Looking for results matching city: $city');

      // First try exact city matches
      for (int i = 0; i < results.length; i++) {
        final result = results[i];
        final placeAddress =
            result['vicinity'] ?? result['formatted_address'] ?? '';
        final placeCity = _extractCityFromAddress(placeAddress);

        if (placeCity.toLowerCase() == city.toLowerCase()) {
          print('📊 YELP DATA: Found exact city match at index $i: $placeCity');
          return i;
        }
      }

      // Then try partial city matches
      for (int i = 0; i < results.length; i++) {
        final result = results[i];
        final placeAddress =
            result['vicinity'] ?? result['formatted_address'] ?? '';

        if (placeAddress.toLowerCase().contains(city.toLowerCase())) {
          print(
              '📊 YELP DATA: Found result with city in address at index $i: $placeAddress');
          return i;
        }
      }
    }

    // No specific match found, return the first result
    print('📊 YELP DATA: No city match found, using first result');
    return 0;
  }

  // Helper to extract city from Google Places address
  String _extractCityFromAddress(String address) {
    final parts = address.split(',');
    if (parts.length >= 2) {
      // City is typically the second-to-last part before state/zip
      return parts[parts.length - 2].trim();
    }
    return '';
  }

  // Helper method to fill the form with business data
  void _fillFormWithBusinessData(
      Location location, String businessName, String yelpUrl) {
    final String businessKey = '${location.latitude},${location.longitude}';

    // Use provider to get cards
    final provider = context.read<ReceiveShareProvider>();

    // Find the specific card that matches this Yelp URL
    ExperienceCardData? targetCard;
    for (var card in provider.experienceCards) {
      if (card.yelpUrlController.text == yelpUrl) {
        targetCard = card;
        break;
      }
    }

    // If no specific card found, use the first one
    targetCard ??= provider.experienceCards.isNotEmpty
        ? provider.experienceCards.first
        : null;

    if (targetCard == null) return;

    // Log the data before setting it to the card
    print('====> 📝 CARD FORM Log: Filling card for Yelp URL: $yelpUrl');
    print(
        '====> 📝 CARD FORM Log:   Location Display Name: ${location.displayName}');
    print('====> 📝 CARD FORM Log:   Location Address: ${location.address}');
    print(
        '====> 📝 CARD FORM Log:   Location Coords: ${location.latitude}, ${location.longitude}');
    print('====> 📝 CARD FORM Log:   Location Website: ${location.website}');
    print(
        '====> 📝 CARD FORM Log:   Business Name (from initial Yelp parse): $businessName');

    // Try to get website URL from the Maps service if the location has a placeId
    String? websiteUrl;
    if (location.website != null) {
      websiteUrl = location.website;
      print('DEBUG: Got website URL from location object: $websiteUrl');
    }

    // Update UI
    setState(() {
      // Set data in the target card
      print(
          'DEBUG: Setting card data - title: ${location.displayName ?? businessName}');

      // Determine the final title and address to be set
      final String titleToSet = location.displayName ?? businessName;
      final String addressToSet = location.address ?? '';
      final String websiteToSet =
          websiteUrl ?? ''; // Use fetched website if available

      print('====> 📝 CARD FORM Log:   Title being set: "$titleToSet"');
      print(
          '====> 📝 CARD FORM Log:   Search text being set (address): "$addressToSet"');
      print('====> 📝 CARD FORM Log:   Website being set: "$websiteToSet"');

      targetCard!.titleController.text = titleToSet; // Use determined title
      targetCard!.selectedLocation = location;
      targetCard!.yelpUrlController.text = yelpUrl;
      targetCard!.searchController.text =
          addressToSet; // Use determined address

      // Update website URL if we found one
      // if (websiteUrl != null && websiteUrl.isNotEmpty) {
      targetCard!.websiteController.text =
          websiteToSet; // Use determined website
      //   print('DEBUG: Updated website URL to: $websiteUrl');
      // }

      // If we have a photoUrl, make sure to force a refresh of any UI that shows it
      if (location.photoUrl != null) {
        print('DEBUG: Location has photo URL: ${location.photoUrl}');
      }
    });

    // Force refresh of any Yelp preview or cached business data
    setState(() {
      // Remove from cache to force reload
      _businessDataCache.remove(yelpUrl.trim());

      // Force refresh of the business preview
      if (_yelpPreviewFutures.containsKey(yelpUrl)) {
        _yelpPreviewFutures.remove(yelpUrl);
      }
    });
  }

  // Helper method to fill the form with Google Maps data
  void _fillFormWithGoogleMapsData(
      Location location, String placeName, String websiteUrl) {
    final String locationKey = '${location.latitude},${location.longitude}';

    // Use provider to get cards
    final provider = context.read<ReceiveShareProvider>();

    // Update UI
    setState(() {
      for (var card in provider.experienceCards) {
        // Set data in the card
        print(
            '🗺️ MAPS: Setting card data - title: ${location.displayName ?? placeName}');
        card.titleController.text = location.displayName ?? placeName;
        card.selectedLocation = location;
        card.websiteController.text =
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
    // Get cards from provider
    final provider = context.read<ReceiveShareProvider>();
    final experienceCards = provider.experienceCards;

    // Validate all forms within the cards
    bool allValid = true;
    for (var card in experienceCards) {
      if (!card.formKey.currentState!.validate()) {
        allValid = false;
        // Optionally break or collect all errors
        break;
      }
    }

    if (!allValid) {
      _showSnackBar(context, 'Please fill in required fields correctly');
      return;
    }

    // Check for required locations if enabled
    // Use provider list here
    for (int i = 0; i < experienceCards.length; i++) {
      final card = experienceCards[i];
      if (card.locationEnabled && card.selectedLocation == null) {
        _showSnackBar(
            context, 'Please select a location for experience ${i + 1}');
        return;
      }
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final now = DateTime.now();
      int successCount = 0;

      // Save each experience using data from provider list
      for (final card in experienceCards) {
        final Location defaultLocation = Location(
          latitude: 0.0,
          longitude: 0.0,
          address: 'No location specified',
        );

        Experience newExperience = Experience(
          id: '', // ID will be assigned by Firestore
          name: card.titleController.text,
          description: card.notesController.text.isNotEmpty
              ? card.notesController.text
              : 'Created from shared content', // Use notes if available
          location: card.locationEnabled
              ? card.selectedLocation!
              : defaultLocation, // Use default when disabled
          type: card.selectedType,
          rating: card
              .rating, // Pass rating (assuming Experience model has it) // UNCOMMENTED
          yelpUrl: card.yelpUrlController.text.isNotEmpty
              ? card.yelpUrlController.text
              : null,
          website: card.websiteController.text.isNotEmpty
              ? card.websiteController.text
              : null,
          createdAt: now,
          updatedAt: now,
        );

        // Include shared media paths if available (assuming Experience model has fields)
        // UNCOMMENTED Block
        if (_currentSharedFiles.isNotEmpty) {
          // Note: This assumes the Experience model now has these fields
          newExperience = newExperience.copyWith(
            sharedMediaPaths: _currentSharedFiles.map((f) => f.path).toList(),
            sharedMediaType: _getMediaTypeString(_currentSharedFiles
                .first.type), // Assuming homogeneous type for now
          );
        }

        await _experienceService.createExperience(newExperience);
        successCount++;
      }

      print('Successfully created $successCount experiences');
      _showSnackBar(
          context, '$successCount Experience(s) created successfully');

      // Call the onCancel callback to close the screen
      widget.onCancel();
    } catch (e) {
      print('Error saving experiences: $e');
      _showSnackBar(context, 'Error creating experiences: $e');
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
    FocusScope.of(context).unfocus(); // Dismiss keyboard

    // Determine if the picker should behave differently based on Yelp context
    bool isFromYelpShare = card.yelpUrlController.text.isNotEmpty;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          initialLocation: card.selectedLocation,
          // Pass a dummy callback, the update happens below based on the result
          onLocationSelected: (location) {},
          isFromYelpShare: isFromYelpShare,
          // Pass name hint (assuming LocationPickerScreen has this param)
          businessNameHint:
              isFromYelpShare ? card.titleController.text : null, // UNCOMMENTED
        ),
      ),
    );

    if (result != null && mounted) {
      // Unfocus again after returning
      Future.microtask(() => FocusScope.of(context).unfocus());

      final Location selectedLocation =
          result is Map ? result['location'] : result as Location;
      final bool shouldUpdateYelpInfo =
          result is Map ? result['shouldUpdateYelpInfo'] ?? false : false;

      final provider = context.read<ReceiveShareProvider>();

      // SIMPLIFY: Always treat as shouldUpdateYelpInfo == true if it came from Yelp
      if (isFromYelpShare) {
        // Simplified condition: only check if it was Yelp context
        print("LocationPicker returned from Yelp context: Updating info.");
        // Fetch detailed Google Place info using the selected Place ID
        try {
          if (selectedLocation.placeId == null ||
              selectedLocation.placeId!.isEmpty) {
            print("Error: Cannot update Yelp info without a Place ID.");
            // Fallback to basic location update
            provider.updateCardData(card, location: selectedLocation);
            return;
          }

          print("Fetching details for Place ID: ${selectedLocation.placeId}");
          Location detailedLocation =
              await _mapsService.getPlaceDetails(selectedLocation.placeId!);
          print(
              "Fetched details: ${detailedLocation.displayName}, Addr: ${detailedLocation.address}, Web: ${detailedLocation.website}");

          // Prepare data for the card update and potentially the futures map
          final String businessName = detailedLocation.getPlaceName();
          final String yelpUrl = card.yelpUrlController.text.trim();

          // Clear relevant caches before updating
          _businessDataCache.remove(yelpUrl);
          _yelpPreviewFutures.remove(yelpUrl);
          if (card.placeIdForPreview != null) {
            _yelpPreviewFutures.remove(card.placeIdForPreview);
          }

          // Update card data via provider (assuming provider has these params)
          provider.updateCardData(card,
              location: detailedLocation,
              // UNCOMMENTED Block
              title: businessName, // Update title based on Google Place name
              website: detailedLocation.website, // Update website
              searchQuery:
                  detailedLocation.address, // Update search field display
              placeIdForPreview:
                  detailedLocation.placeId // Update the place ID cache key
              );

          // Update the futures map with the *new* detailed data, keyed by Place ID
          final String futureKey = detailedLocation.placeId!;
          final Map<String, dynamic> newFutureData = {
            'location': detailedLocation,
            'businessName': businessName,
            'yelpUrl': yelpUrl, // Keep Yelp URL for context if needed
            'photoUrl': detailedLocation.photoUrl,
            'address': detailedLocation.address,
            'website': detailedLocation.website,
          };
          // We store the *resolved* data, wrapped in a Future.value
          _yelpPreviewFutures[futureKey] = Future.value(newFutureData);

          // Trigger rebuild for the preview widget if it depends on the future map
          setState(() {});
        } catch (e) {
          print("Error getting place details or updating card: $e");
          _showSnackBar(context, "Error updating location details.");
          // Fallback: Update with the basic location selected
          provider.updateCardData(card, location: selectedLocation);
        }
      } else {
        // Just update the location using Provider based on picker selection
        print("LocationPicker returned (non-Yelp): Basic location update.");
        // Update card data via provider (assuming provider has searchQuery param)
        provider.updateCardData(card,
            location: selectedLocation,
            // UNCOMMENTED
            searchQuery: selectedLocation.address ?? 'Location Selected');
      }
    } else {
      print("LocationPicker returned null or screen unmounted.");
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get the provider instance - listen for changes here
    final shareProvider = context.watch<ReceiveShareProvider>();
    final experienceCards =
        shareProvider.experienceCards; // Get list from provider

    return _wrapWithWillPopScope(Scaffold(
      appBar: AppBar(
        title: _isSpecialContent(_currentSharedFiles)
            ? const Text('Save Shared Content')
            : const Text('Save to Experiences'),
        leading: IconButton(
          // Use leading for the cancel/back action
          icon: Icon(Platform.isIOS ? Icons.arrow_back_ios : Icons.arrow_back),
          onPressed: widget.onCancel, // Use the cancel callback
        ),
        automaticallyImplyLeading:
            false, // We handle the leading button manually
        actions: [
          // Add button - only show if not special content
          if (!_isSpecialContent(_currentSharedFiles))
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add Another Experience',
              // Use the corrected method name
              onPressed: _addExperienceCard,
            ),
        ],
      ),
      body: SafeArea(
        child: _isSaving
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text("Saving Experiences..."),
                  ],
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      // Add padding around the scrollable content
                      padding: const EdgeInsets.only(
                          bottom: 80), // Prevent overlap with bottom buttons
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Display the shared content preview section
                          if (_currentSharedFiles.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(
                                  child: Text('No shared content received')),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0, vertical: 8.0),
                              child: ListView.builder(
                                // Use a Column instead of ListView for previews if only one?
                                // Or keep ListView for potential multi-file shares later
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _currentSharedFiles
                                    .length, // Show preview for each shared item
                                itemBuilder: (context, index) {
                                  final file = _currentSharedFiles[index];
                                  // Pass the first card from the provider to previews if it exists
                                  // Use provider list here
                                  final firstCard = experienceCards.isNotEmpty
                                      ? experienceCards.first
                                      : null;
                                  // Wrap preview in a Card for visual separation
                                  return Card(
                                    elevation: 2.0,
                                    margin: const EdgeInsets.only(bottom: 12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Build the appropriate preview based on type
                                        if (firstCard != null)
                                          _buildMediaPreview(file, firstCard)
                                        else
                                          // Fallback if no cards exist (shouldn't happen with current logic)
                                          _buildMediaPreview(file,
                                              ExperienceCardData()), // Pass dummy data
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),

                          // Experience association form section
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (experienceCards.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        top: 16.0, bottom: 8.0),
                                    child: Text(
                                        experienceCards.length > 1
                                            ? 'Associated Experiences'
                                            : 'Associate Experience',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge),
                                  )
                                else // Show if no cards (e.g., error state)
                                  const Padding(
                                      padding: EdgeInsets.only(
                                          top: 16.0, bottom: 8.0),
                                      child: Text("No Experience Card")),

                                const SizedBox(height: 8),

                                // Use AnimatedList or similar for smoother add/remove?
                                // For now, just rebuild the list from provider state
                                if (experienceCards.isEmpty)
                                  Center(
                                      child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 20.0),
                                    child: Text(
                                        "Error: No experience card available.",
                                        style: TextStyle(color: Colors.red)),
                                  ))
                                else
                                  ListView.builder(
                                      padding: EdgeInsets.zero,
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: experienceCards.length,
                                      itemBuilder: (context, i) {
                                        final card = experienceCards[i];
                                        return ExperienceCardForm(
                                          // Use a unique key based on the card's ID
                                          key: ValueKey(card.id),
                                          cardData: card,
                                          isFirstCard: i == 0,
                                          canRemove: experienceCards.length > 1,
                                          // Pass methods directly (assuming correct signature in form widget)
                                          onRemove: _removeExperienceCard,
                                          onLocationSelect: _showLocationPicker,
                                          onUpdate: () => setState(
                                              () {}), // Trigger rebuild of ReceiveShareScreen
                                          formKey: card
                                              .formKey, // Pass the key from the card data
                                          // Pass maps service if needed by form (e.g., for internal search)
                                          // mapsService: _mapsService,
                                        );
                                      }),

                                // Add another experience button - only show if not special content
                                if (!_isSpecialContent(_currentSharedFiles))
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        top: 12.0,
                                        bottom: 16.0), // Adjust spacing
                                    child: Center(
                                      // Center the button
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.add),
                                        label: const Text(
                                            'Add Another Experience'),
                                        // Use the corrected method name
                                        onPressed: _addExperienceCard,
                                        style: OutlinedButton.styleFrom(
                                          // foregroundColor: Colors.blue,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12, horizontal: 24),
                                          side: BorderSide(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary), // Use theme color
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Action buttons (Save/Cancel) - Fixed at the bottom
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 12.0),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).cardColor, // Match card background
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          spreadRadius: 0,
                          blurRadius: 4,
                          offset: const Offset(0, -2), // Shadow upwards
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        OutlinedButton(
                          onPressed: widget.onCancel, // Use callback
                          child: const Text('Cancel'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey[700],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveExperience,
                          icon: _isSaving
                              ? Container(
                                  width: 20,
                                  height: 20,
                                  padding: const EdgeInsets.all(2.0),
                                  child: const CircularProgressIndicator(
                                      strokeWidth: 3, color: Colors.white),
                                )
                              : const Icon(Icons.save),
                          label: Text(
                              _isSaving ? 'Saving...' : 'Save Experience(s)'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
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

  // Helper function to launch URLs
  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      print('Could not launch $urlString');
      _showSnackBar(context, 'Could not open link');
    }
  }

  // Helper to check if a string is a valid URL
  bool _isValidUrl(String urlString) {
    final Uri? uri = Uri.tryParse(urlString);
    return uri != null && (uri.isScheme('http') || uri.isScheme('https'));
  }

  // Helper function to convert SharedMediaType enum to String
  String _getMediaTypeString(SharedMediaType type) {
    switch (type) {
      case SharedMediaType.image:
        return 'Image';
      case SharedMediaType.video:
        return 'Video';
      case SharedMediaType.text:
        return 'Text/URL';
      case SharedMediaType.file:
        return 'File';
      case SharedMediaType.url: // Treat URL type similar to text for display
        return 'URL';
      default:
        return 'Unknown';
    }
  }

  // Modify _buildMediaPreview if it needs access to provider
  Widget _buildMediaPreview(SharedMediaFile file, ExperienceCardData card) {
    // Access provider if needed for previews, e.g., for Yelp/Maps
    // final provider = context.read<ReceiveShareProvider>(); // Read needed? Only if passing methods

    switch (file.type) {
      case SharedMediaType.image:
        // Assuming ImagePreviewWidget doesn't need provider data directly
        return ImagePreviewWidget(file: file);
      case SharedMediaType.video:
        // Assuming _buildVideoPreview doesn't need provider data directly
        return _buildVideoPreview(file);
      case SharedMediaType.text:
      case SharedMediaType
            .url: // Handle URL type like text for preview building
        return _buildTextPreview(file, card); // Pass card data from provider
      case SharedMediaType.file:
      default:
        // Assuming _buildFilePreview doesn't need provider data directly
        return _buildFilePreview(file);
    }
  }

  // Modify _buildTextPreview if it needs provider access
  Widget _buildTextPreview(SharedMediaFile file, ExperienceCardData card) {
    // final provider = context.read<ReceiveShareProvider>(); // Not needed directly here now

    String textContent = file.path; // Path contains the text or URL

    // Check if it's likely a URL
    if (_isValidUrl(textContent)) {
      // Pass the card data (already obtained from provider in build method)
      // to _buildUrlPreview which handles URL-specific previews.
      return _buildUrlPreview(textContent, card);
    } else {
      // Handle complex text that might *contain* a URL
      if (textContent.contains('\n') && textContent.contains('http')) {
        final lines = textContent.split('\n');
        for (String line in lines) {
          line = line.trim();
          if (_isValidUrl(line)) {
            if (line.toLowerCase().contains('yelp.to/') ||
                line.toLowerCase().contains('yelp.com/biz/')) {
              return YelpPreviewWidget(
                yelpUrl: line,
                card: card, // Pass card data
                yelpPreviewFutures: _yelpPreviewFutures,
                getBusinessFromYelpUrl: _getBusinessFromYelpUrl,
                launchUrlCallback: _launchUrl,
                mapsService: _mapsService,
              );
            }
            // Add checks for other special URLs (Maps, Instagram) if needed here
            // Fallback to generic URL preview for the first valid URL found
            return _buildUrlPreview(line, card);
          }
        }
        // If no valid URL found in lines, show as plain text
        print("Complex text, no standalone URL line found.");
      } else if (textContent.contains('Check out') &&
          textContent.contains('yelp.to/')) {
        final urlRegex = RegExp(r'(https?://yelp\.to/[^\s]+)');
        final match = urlRegex.firstMatch(textContent);
        if (match != null) {
          final extractedUrl = match.group(0)!;
          return YelpPreviewWidget(
            yelpUrl: extractedUrl,
            card: card, // Pass card data
            yelpPreviewFutures: _yelpPreviewFutures,
            getBusinessFromYelpUrl: _getBusinessFromYelpUrl,
            launchUrlCallback: _launchUrl,
            mapsService: _mapsService,
          );
        }
      } else if (textContent.toLowerCase().contains('yelp.to/') ||
          textContent.toLowerCase().contains('yelp.com/biz/')) {
        // Attempt to extract Yelp URL from general text if specific patterns above failed
        final urlRegex =
            RegExp(r'(https?://(?:www\.)?yelp\.(?:com/biz|to)/[^\s]+)');
        final match = urlRegex.firstMatch(textContent);
        if (match != null) {
          final extractedUrl = match.group(0)!;
          return YelpPreviewWidget(
            yelpUrl: extractedUrl,
            card: card, // Pass card data
            yelpPreviewFutures: _yelpPreviewFutures,
            getBusinessFromYelpUrl: _getBusinessFromYelpUrl,
            launchUrlCallback: _launchUrl,
            mapsService: _mapsService,
          );
        }
      }

      // If not a URL or special format, display as plain text (potentially truncated)
      return Container(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          textContent,
          maxLines: 5, // Limit lines for preview
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
  }

  // Modify _buildUrlPreview to accept and use card data
  Widget _buildUrlPreview(String url, ExperienceCardData card) {
    // Access provider only if needed for actions, not just data access
    // final provider = context.read<ReceiveShareProvider>();

    // Special handling for Yelp URLs
    if (url.contains('yelp.com/biz') || url.contains('yelp.to/')) {
      return YelpPreviewWidget(
        yelpUrl: url,
        card: card, // Pass the card data
        yelpPreviewFutures: _yelpPreviewFutures,
        getBusinessFromYelpUrl: _getBusinessFromYelpUrl,
        launchUrlCallback: _launchUrl,
        mapsService: _mapsService,
      );
    }

    // Special handling for Google Maps URLs
    if (url.contains('google.com/maps') ||
        url.contains('maps.app.goo.gl') ||
        url.contains('goo.gl/maps')) {
      return MapsPreviewWidget(
        mapsUrl: url,
        // Pass the futures map (might need renaming if Maps uses a different key system)
        // For now, assume it can use the same map or adapt internally
        mapsPreviewFutures: _yelpPreviewFutures,
        getLocationFromMapsUrl: _getLocationFromMapsUrl,
        launchUrlCallback: _launchUrl,
        mapsService: _mapsService,
        // Pass card if MapsPreview needs it, e.g., to prefill something later
        // card: card,
      );
    }

    // Special handling for Instagram URLs
    if (url.contains('instagram.com')) {
      return InstagramPreviewWidget(
        url: url,
        launchUrlCallback: _launchUrl,
      );
    }

    // Generic URL
    return GenericUrlPreviewWidget(
      url: url,
      launchUrlCallback: _launchUrl,
    );
  }

  // Preview widget for Video content
  Widget _buildVideoPreview(SharedMediaFile file) {
    // Placeholder - Needs a video player implementation
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Icon(Icons.video_library, size: 50, color: Colors.grey),
          const SizedBox(height: 8),
          Text('Video Preview Unavailable: ${file.path}'),
        ],
      ),
    );
  }

  // Preview widget for File content
  Widget _buildFilePreview(SharedMediaFile file) {
    // Placeholder - Show file icon and name
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Icon(Icons.insert_drive_file, size: 50, color: Colors.grey),
          const SizedBox(height: 8),
          Text('File: ${file.path}'),
        ],
      ),
    );
  }

  // --- Google Maps Specific Logic ---

  // Fetches location details from a Google Maps URL
  Future<Map<String, dynamic>?> _getLocationFromMapsUrl(String mapsUrl) async {
    print("Attempting to get location details for Maps URL: $mapsUrl");
    String resolvedUrl = mapsUrl;

    // Resolve potential short URLs (e.g., maps.app.goo.gl, goo.gl/maps)
    if (!resolvedUrl.contains('google.com/maps')) {
      try {
        final String? expandedUrl = await _resolveShortUrl(resolvedUrl);
        if (expandedUrl != null && expandedUrl.contains('google.com/maps')) {
          resolvedUrl = expandedUrl;
          print("Resolved short Maps URL to: $resolvedUrl");
        } else {
          print(
              "Failed to resolve short Maps URL or resolved to non-maps page: $expandedUrl");
          return null;
        }
      } catch (e) {
        print("Error resolving short Maps URL $resolvedUrl: $e");
        return null;
      }
    }

    // Ensure it's a google.com/maps link now
    if (!resolvedUrl.contains('google.com/maps')) {
      print("URL is not a standard Google Maps URL: $resolvedUrl");
      return null;
    }

    // Check cache first (using the original URL as key)
    if (_businessDataCache.containsKey(mapsUrl.trim())) {
      print("Returning cached data for $mapsUrl");
      return _businessDataCache[mapsUrl.trim()];
    }

    try {
      // Extract relevant info (name, coords, placeID) from the URL
      final extractedInfo = _extractInfoFromMapsUrl(resolvedUrl);
      if (extractedInfo == null) {
        print("Could not extract usable info from Maps URL: $resolvedUrl");
        return null;
      }

      String? placeName = extractedInfo['name'];
      double? lat = extractedInfo['lat'];
      double? lng = extractedInfo['lng'];
      String? placeId = extractedInfo['placeId'];
      String? query = extractedInfo['query']; // Search query from ?q=
      String? data = extractedInfo['data']; // Data blob

      print(
          "Extracted Maps Info: Name=$placeName, Lat=$lat, Lng=$lng, PlaceID=$placeId, Query=$query, Data=$data");

      Location? foundLocation;

      // Strategy:
      // 1. If Place ID exists, use it to get details (most reliable).
      // 2. If Lat/Lng exist, reverse geocode to get an address and maybe refine with name.
      // 3. If only Name/Query exists, perform a search.
      // 4. Use Data blob as a potential source for Place ID or refinement.

      // --- Try using Place ID ---
      if (placeId != null && placeId.isNotEmpty) {
        try {
          print("Attempting lookup via Place ID: $placeId");
          foundLocation = await _mapsService.getPlaceDetails(placeId);
          print("Found location via Place ID: ${foundLocation.displayName}");
        } catch (e) {
          print("Initial Place ID lookup failed for '$placeId': $e");
          // Handle potential DioException for API errors
          bool isInvalidIdError = false;
          if (e is DioException && e.response?.data is Map) {
            var errorData = e.response?.data as Map;
            if (errorData['status'] == 'INVALID_REQUEST') {
              // Check API status
              isInvalidIdError = true;
              print("API confirmed INVALID_REQUEST for Place ID: $placeId");
            }
          }

          // If it was an invalid ID error AND we have a name, try searching
          if (isInvalidIdError && placeName != null && placeName.isNotEmpty) {
            print(
                "Invalid Place ID from blob. Attempting search with name: '$placeName'");
            try {
              // --- ENHANCED FALLBACK SEARCH ---
              String searchQuery = placeName;
              // Try to make the search more specific if we have coordinates
              if (lat != null && lng != null) {
                try {
                  print(
                      "🗺️ FALLBACK: Reverse geocoding $lat, $lng to add context to search");
                  final addresses =
                      await geocoding.placemarkFromCoordinates(lat, lng);
                  if (addresses.isNotEmpty) {
                    final placemark = addresses.first;
                    String city = placemark.locality ?? '';
                    String street = placemark.thoroughfare ?? '';
                    if (city.isNotEmpty) {
                      searchQuery = "$placeName, $city";
                      print(
                          "🗺️ FALLBACK: Using query with city: '$searchQuery'");
                    } else if (street.isNotEmpty) {
                      searchQuery = "$placeName, $street";
                      print(
                          "🗺️ FALLBACK: Using query with street: '$searchQuery'");
                    }
                  }
                } catch (geocodeError) {
                  print(
                      "🗺️ FALLBACK: Error during reverse geocoding for search context: $geocodeError");
                  // Proceed with just the name if geocoding fails
                }
              }
              print(
                  "🗺️ FALLBACK: Performing search with query: '$searchQuery'");
              // --- END ENHANCED FALLBACK SEARCH ---

              List<Map<String, dynamic>> searchResults = await _mapsService
                  .searchPlaces(searchQuery); // Use enhanced query
              if (searchResults.isNotEmpty) {
                String? searchResultPlaceId = searchResults.first['placeId'];
                if (searchResultPlaceId != null &&
                    searchResultPlaceId.isNotEmpty) {
                  print(
                      "Search found potential match. Getting details for Place ID: $searchResultPlaceId");
                  // Get details using the ID from the search result
                  foundLocation =
                      await _mapsService.getPlaceDetails(searchResultPlaceId);
                  print(
                      "Successfully found location via search fallback: ${foundLocation.displayName}");
                } else {
                  print("Search result missing Place ID.");
                }
              } else {
                print("Search with name '$placeName' returned no results.");
              }
            } catch (searchError) {
              print(
                  "Error during fallback search for '$placeName': $searchError");
            } // End fallback search try-catch
          } // End if (isInvalidIdError...)
          // Place ID might be invalid or outdated, continue to other methods
        }
      }

      // --- Try using Data Blob (often contains Place ID) ---
      if (foundLocation == null && data != null && data.isNotEmpty) {
        // Example data blob: !1s0x... !2sPlace+Name !3dlat !4dlng ... !9sPlaceID
        // This parsing is fragile and specific to observed formats
        final placeIdMatch = RegExp(r'!9s([^!]+)').firstMatch(data);
        final nameMatch =
            RegExp(r'!2s([^!]+)').firstMatch(data); // Name might be here
        final latMatch = RegExp(r'!3d([\d.-]+)').firstMatch(data);
        final lngMatch = RegExp(r'!4d([\d.-]+)').firstMatch(data);

        String? dataPlaceId = placeIdMatch?.group(1);
        String? dataName = nameMatch?.group(1)?.replaceAll('+', ' ');
        double? dataLat = latMatch?.group(1) != null
            ? double.tryParse(latMatch!.group(1)!)
            : null;
        double? dataLng = lngMatch?.group(1) != null
            ? double.tryParse(lngMatch!.group(1)!)
            : null;

        print(
            "Parsed Data Blob: Name=$dataName, Lat=$dataLat, Lng=$dataLng, PlaceID=$dataPlaceId");

        if (dataPlaceId != null && dataPlaceId.isNotEmpty) {
          try {
            print(
                "Attempting lookup via Place ID from data blob: $dataPlaceId");
            foundLocation = await _mapsService.getPlaceDetails(dataPlaceId);
            print(
                "Found location via Place ID from data blob: ${foundLocation.displayName}");
          } catch (e) {
            print(
                "Error fetching details by Place ID from data blob '$dataPlaceId': $e");
          }
        }
        // If lookup by Place ID failed, but we have lat/lng from data, use that
        if (foundLocation == null && dataLat != null && dataLng != null) {
          print("Using Lat/Lng from data blob for reverse geocoding.");
          lat = dataLat;
          lng = dataLng;
          // Proceed to Lat/Lng section below
        }
        // Use name from data blob if primary name wasn't found earlier
        if (placeName == null && dataName != null) {
          placeName = dataName;
        }
      }

      // --- Try using Lat/Lng ---
      if (foundLocation == null && lat != null && lng != null) {
        try {
          print("Attempting reverse geocoding for $lat, $lng");
          final addresses = await geocoding.placemarkFromCoordinates(lat, lng);
          if (addresses.isNotEmpty) {
            final placemark = addresses.first;
            String bestAddress = [
              placemark.name, // Often the POI name or number
              placemark.thoroughfare, // Street
              placemark.locality, // City
              placemark.administrativeArea, // State
              placemark.postalCode,
            ].where((s) => s != null && s.isNotEmpty).join(', ');

            print("Reverse geocoded address: $bestAddress");

            // If we also have a placeName from the URL, try to refine the search
            if (placeName != null && placeName.isNotEmpty) {
              print("Refining reverse geocoded result with name: $placeName");
              // Search near the coords using the name
              // Fix type mismatch and parameters for searchPlaces
              List<
                  Map<String,
                      dynamic>> searchResultsMap = await _mapsService.searchPlaces(
                  placeName /*, lat: lat, lng: lng, radius: 50*/); // Fix params
              if (searchResultsMap.isNotEmpty) {
                final firstResultMap = searchResultsMap.first;
                final firstResultName =
                    firstResultMap['description'] as String? ??
                        firstResultMap['name'] as String?;
                final firstResultPlaceId = firstResultMap['placeId'] as String?;

                // Heuristic: If the top result name is similar to the original name, use it.
                if (firstResultName != null &&
                    (firstResultName
                            .toLowerCase()
                            .contains(placeName.toLowerCase()) ??
                        false)) {
                  print("Refined search found better match: $firstResultName");
                  // Attempt to get full details for this refined match
                  try {
                    if (firstResultPlaceId != null) {
                      foundLocation = await _mapsService
                          .getPlaceDetails(firstResultPlaceId);
                      print(
                          "Got details for refined match: ${foundLocation.displayName}");
                    } else {
                      // Convert map to Location if no placeId for details
                      // foundLocation = Location.fromJson(firstResultMap); // TODO: Uncomment when Location.fromJson exists
                      print(
                          "Skipping Location.fromJson call for now"); // Placeholder
                    }
                  } catch (detailError) {
                    print(
                        "Error getting details for refined match: $detailError");
                    // foundLocation = Location.fromJson(firstResultMap); // TODO: Uncomment when Location.fromJson exists // Fallback, assuming fromJson
                    print(
                        "Skipping Location.fromJson call for now"); // Placeholder
                  } // End inner try-catch
                }
              }
            }

            // If refinement didn't work or wasn't needed, use the reverse geocoded result directly
            if (foundLocation == null) {
              print("Using direct reverse geocoded result.");
              foundLocation = Location(
                  latitude: lat,
                  longitude: lng,
                  address: bestAddress,
                  displayName: placemark.name ??
                      placeName ??
                      'Unnamed Location', // Use name from placemark or URL if available
                  placeId:
                      null // Reverse geocoding doesn't reliably give Place ID
                  );
            }
          } else {
            print("Reverse geocoding failed for $lat, $lng");
            // Use Lat/Lng directly without address/name?
            foundLocation = Location(
                latitude: lat,
                longitude: lng,
                address: 'Coordinates: $lat, $lng',
                displayName: placeName ?? 'Unknown Location',
                placeId: null);
          }
        } catch (e) {
          print("Error during reverse geocoding for $lat, $lng: $e");
          // Fallback to basic location if geocoding fails
          foundLocation = Location(
              latitude: lat,
              longitude: lng,
              address: 'Error finding address',
              displayName: placeName ?? 'Unknown Location',
              placeId: null);
        } // End outer try-catch for Lat/Lng
      }

      // --- Try using Name/Query ---
      if (foundLocation == null && placeName != null && placeName.isNotEmpty) {
        print("Attempting search by name/query: $placeName");
        try {
          // Replace incorrect _findBestMatch call with searchPlaces
          List<Map<String, dynamic>> searchResultsMap =
              await _mapsService.searchPlaces(placeName);
          if (searchResultsMap.isNotEmpty) {
            String? resultPlaceId = searchResultsMap.first['placeId'];
            if (resultPlaceId != null) {
              foundLocation = await _mapsService.getPlaceDetails(resultPlaceId);
              print("Found location via search: ${foundLocation.displayName}");
            } else {
              // Handle case where search result has no place ID
              // foundLocation = Location.fromJson(searchResultsMap.first); // TODO: Uncomment when Location.fromJson exists // Assuming fromJson
              print("Skipping Location.fromJson call for now"); // Placeholder
              print(
                  "Found location via search (basic): ${foundLocation?.displayName ?? 'N/A'}");
            }
          } else {
            print("Search returned no results for '$placeName'.");
          }
        } catch (e) {
          print("Error searching by name '$placeName': $e");
        } // End try-catch for Name search
      } else if (foundLocation == null && query != null && query.isNotEmpty) {
        // Fallback to using the 'q' parameter if name wasn't found elsewhere
        print("Attempting search by query parameter: $query");
        try {
          // Replace incorrect _findBestMatch call with searchPlaces
          List<Map<String, dynamic>> searchResultsMap =
              await _mapsService.searchPlaces(query);
          if (searchResultsMap.isNotEmpty) {
            String? resultPlaceId = searchResultsMap.first['placeId'];
            if (resultPlaceId != null) {
              foundLocation = await _mapsService.getPlaceDetails(resultPlaceId);
              print(
                  "Found location via query search: ${foundLocation.displayName}");
            } else {
              foundLocation = Location.fromMap(
                  searchResultsMap.first); // Assuming fromMap - WAS fromJson
              print(
                  "Found location via query search (basic): ${foundLocation.displayName}");
            }
          } else {
            print("Search returned no results for query '$query'.");
          }
        } catch (e) {
          print("Error searching by query '$query': $e");
        } // End try-catch for Query search
      }

      // --- Final Check and Return ---
      if (foundLocation != null) {
        // Ensure name consistency if possible
        final finalName =
            foundLocation.displayName ?? placeName ?? 'Location Found';
        final finalWebsite =
            foundLocation.website; // Website comes from getPlaceDetails

        // Fill form using the first card from provider
        final provider = context.read<ReceiveShareProvider>();
        if (provider.experienceCards.isNotEmpty) {
          // Fix nullability for websiteUrl
          _fillFormWithGoogleMapsData(
              foundLocation, finalName, finalWebsite ?? '');
        }

        // Prepare result map for FutureBuilder
        final Map<String, dynamic> result = {
          'location': foundLocation,
          'businessName': finalName, // Use the best name we found
          'website': finalWebsite, // Pass website if available
          'mapsUrl': mapsUrl, // Original URL for reference
        };

        // Cache the result using the original URL
        _businessDataCache[mapsUrl.trim()] = result;
        print("Successfully processed Maps URL: $mapsUrl");
        return result;
      } else {
        print("Failed to determine location from Maps URL: $mapsUrl");
        return null; // Could not find location
      }
    } catch (e) {
      print("Error processing Google Maps URL $mapsUrl: $e");
      return null;
    }
  }

  // Extracts Name, Lat/Lng, PlaceID, Query from Google Maps URL
  Map<String, dynamic>? _extractInfoFromMapsUrl(String url) {
    print("🗺️ EXTRACT: Parsing URL: $url");
    final Uri uri = Uri.parse(url);
    double? lat;
    double? lng;
    String? name;
    String? placeId;
    String? query;
    String? dataBlob; // Changed variable name for clarity

    // --- Strategy 1: Extract from path segments ---
    final pathSegments = uri.pathSegments;
    print("🗺️ EXTRACT: Path segments: $pathSegments");

    // Check for @lat,lng,zoom pattern
    int atIndex = pathSegments.indexWhere((s) => s.startsWith('@'));
    if (atIndex != -1) {
      final parts = pathSegments[atIndex].substring(1).split(',');
      if (parts.length >= 2) {
        lat = double.tryParse(parts[0]);
        lng = double.tryParse(parts[1]);
        print("🗺️ EXTRACT: Found @lat,lng in path: $lat, $lng");
      }
    }

    // Check for /place/Place+Name pattern
    int placeIndex = pathSegments.indexOf('place');
    if (placeIndex != -1 && placeIndex < pathSegments.length - 1) {
      String potentialName = pathSegments[placeIndex + 1];
      // Check if the segment after /place/ is the data blob
      if (!potentialName.startsWith('data=')) {
        name = Uri.decodeComponent(potentialName)
            .replaceAll('+', ' '); // Use decodeComponent
        print("🗺️ EXTRACT: Found name after /place/: $name");
      }
    }

    // Check for /data=! pattern
    int dataIndex = pathSegments.indexWhere((s) => s.startsWith('data='));
    if (dataIndex != -1) {
      dataBlob =
          pathSegments[dataIndex].substring(5); // Get the part after 'data='
      print("🗺️ EXTRACT: Found data blob in path: $dataBlob");
      // If name wasn't found via /place/, try the segment *before* /data=
      if (name == null &&
          dataIndex > 0 &&
          pathSegments[dataIndex - 1] != 'place') {
        name = Uri.decodeComponent(pathSegments[dataIndex - 1])
            .replaceAll('+', ' '); // Use decodeComponent
        print("🗺️ EXTRACT: Found name before /data=/: $name");
      }
    }

    // --- Strategy 2: Extract from query parameters ---
    print("🗺️ EXTRACT: Query parameters: ${uri.queryParameters}");
    // Prioritize 'q' for name if it's not coordinates and name isn't set yet
    query = uri.queryParameters['q'];
    if (name == null && query != null && !_containsOnlyCoordinates(query)) {
      name = query;
      print("🗺️ EXTRACT: Found name in query param 'q': $name");
    }

    // Get Place ID from 'cid' or 'placeid'
    placeId = uri.queryParameters['cid'] ?? uri.queryParameters['placeid'];
    if (placeId != null) {
      print("🗺️ EXTRACT: Found placeId in query params: $placeId");
    }

    // Get data blob from 'data' query param if not found in path
    dataBlob ??= uri.queryParameters['data'];
    if (dataBlob != null && uri.queryParameters.containsKey('data')) {
      print("🗺️ EXTRACT: Found data blob in query param 'data': $dataBlob");
    }

    // --- Strategy 3: Parse the data blob if found ---
    if (dataBlob != null && dataBlob.isNotEmpty) {
      print("🗺️ EXTRACT: Parsing data blob: $dataBlob");

      // Regex patterns for data blob parsing (more specific)
      // Place ID patterns: !1s..., !9s..., !16s... (handle potential encoding)
      // final placeIdPattern = RegExp(r'!(?:1s|9s|16s%2F[a-zA-Z0-9%]+)([^!]+)'); // REMOVED - This is not a valid Place ID
      final latPattern = RegExp(r'!3d([\d.-]+)');
      final lngPattern = RegExp(r'!4d([\d.-]+)');

      // Extract Place ID - REMOVED Block
      /*
      final placeIdMatch = placeIdPattern.firstMatch(dataBlob);
      if (placeIdMatch != null) {
        String extractedPid = Uri.decodeComponent(placeIdMatch.group(1)!);
        extractedPid = extractedPid
            .split(RegExp(r'[!&\\]')).first; // Split by !, &, or backslash
        print("🗺️ EXTRACT: Extracted Place ID from blob: $extractedPid");
        if (placeId == null ||
            (placeId != extractedPid && extractedPid.length > 5)) {
          placeId = extractedPid;
          print("🗺️ EXTRACT: Using Place ID from data blob.");
        }
      } else {
        print("🗺️ EXTRACT: Place ID pattern not found in data blob.");
      }
      */ // Added closing comment tag

      // Extract Latitude
      final latMatch = latPattern.firstMatch(dataBlob);
      if (latMatch != null) {
        double? extractedLat = double.tryParse(latMatch.group(1)!);
        if (extractedLat != null) {
          print("🗺️ EXTRACT: Extracted Latitude from blob: $extractedLat");
          if (lat == null) {
            lat = extractedLat;
            print("🗺️ EXTRACT: Using Latitude from data blob.");
          }
        }
      } else {
        print("🗺️ EXTRACT: Latitude pattern not found in data blob.");
      }

      // Extract Longitude
      final lngMatch = lngPattern.firstMatch(dataBlob);
      if (lngMatch != null) {
        double? extractedLng = double.tryParse(lngMatch.group(1)!);
        if (extractedLng != null) {
          print("🗺️ EXTRACT: Extracted Longitude from blob: $extractedLng");
          if (lng == null) {
            lng = extractedLng;
            print("🗺️ EXTRACT: Using Longitude from data blob.");
          }
        }
      } else {
        print("🗺️ EXTRACT: Longitude pattern not found in data blob.");
      }

      // Attempt to extract name from data blob (less reliable, use as last resort)
      final namePattern = RegExp(r'!2s([^!]+)');
      final nameMatch = namePattern.firstMatch(dataBlob);
      if (name == null && nameMatch != null) {
        String potentialName =
            Uri.decodeComponent(nameMatch.group(1)!).replaceAll('+', ' ');
        if (potentialName.length < 100 &&
            !potentialName.contains('=') &&
            !potentialName.contains('!')) {
          name = potentialName;
          print("🗺️ EXTRACT: Found potential name in data blob: $name");
        }
      }
    }

    // --- Final Check and Return ---
    // If name is still null, try using the last path segment if it doesn't look like coordinates or data
    if (name == null && pathSegments.isNotEmpty) {
      String lastSegment = pathSegments.last;
      if (!lastSegment.startsWith('@') &&
          !lastSegment.startsWith('data=') &&
          !_containsOnlyCoordinates(lastSegment)) {
        name = Uri.decodeComponent(lastSegment)
            .replaceAll('+', ' '); // Use decodeComponent
        print("🗺️ EXTRACT: Using last path segment as name fallback: $name");
      }
    }

    print(
        "🗺️ EXTRACT: Final Extracted Info -> Name: $name, Lat: $lat, Lng: $lng, PlaceID: $placeId, Query: $query");

    // If we have extracted *any* useful info, return it
    if (name != null ||
        lat != null ||
        lng != null ||
        placeId != null ||
        query != null) {
      // Removed dataBlob from the check, only return useful fields
      return {
        'name': name?.trim(),
        'lat': lat,
        'lng': lng,
        'placeId': placeId?.trim(),
        'query': query?.trim(),
      };
    }

    print("🗺️ EXTRACT: Could not extract any useful info from URL.");
    return null; // No useful info extracted
  }

  // Check if a string looks like "lat,lng"
  bool _containsOnlyCoordinates(String text) {
    // Adjusted regex to be less strict, matching potential float numbers
    final coordRegex = RegExp(r'^-?[\d.]+, ?-?[\d.]+$');
    return coordRegex.hasMatch(text.trim());
  }

  // --- End Google Maps Specific Logic ---
} // End _ReceiveShareScreenState

// Helper extension for Place Name (consider moving to Location model)
extension LocationNameHelper on Location {
  String getPlaceName() {
    // Prioritize displayName if available and not just coordinates
    if (displayName != null &&
        displayName!.isNotEmpty &&
        !_containsCoordinates(displayName!)) {
      return displayName!;
    }
    // Fallback logic (example: use address parts)
    if (address != null) {
      final parts = address!.split(',');
      if (parts.isNotEmpty)
        return parts.first.trim(); // Use first part of address
    }
    return 'Unnamed Location'; // Default fallback
  }

  // Helper to check if a string *contains* coordinates pattern (less strict than only coordinates)
  bool _containsCoordinates(String text) {
    final coordRegex = RegExp(r'-?[\d.]+ ?, ?-?[\d.]+');
    return coordRegex.hasMatch(text);
  }

  /*
  // Helper to check if a string *only* contains coordinates <-- COMMENTED OUT DUPLICATE
  bool _containsOnlyCoordinates(String text) {
    final coordOnlyRegex = RegExp(r'^-?[\d.]+ ?, ?-?[\d.]+$');
    return coordOnlyRegex.hasMatch(text.trim());
  }
  */
}
