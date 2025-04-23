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
import '../models/user_category.dart'; // RENAMED Import
import '../services/experience_service.dart';
import '../services/google_maps_service.dart';
import '../widgets/google_maps_widget.dart';
import 'location_picker_screen.dart';
import '../services/sharing_service.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'receive_share/widgets/yelp_preview_widget.dart';
import 'receive_share/widgets/maps_preview_widget.dart';
import 'receive_share/widgets/generic_url_preview_widget.dart';
import 'receive_share/widgets/image_preview_widget.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:shared_preferences/shared_preferences.dart';
import 'receive_share/widgets/experience_card_form.dart';
import 'package:plendy/screens/select_saved_experience_screen.dart';
import 'receive_share/widgets/instagram_preview_widget.dart'
    as instagram_widget;
import 'main_screen.dart'; // Add this import
import '../models/public_experience.dart'; // ADDED Import

// Enum to track the source of the shared content
enum ShareType { none, yelp, maps, instagram, genericUrl, image, video, file }

/// Data class to hold the state of each experience card
class ExperienceCardData {
  // Form controllers
  final TextEditingController titleController = TextEditingController();
  final TextEditingController yelpUrlController = TextEditingController();
  final TextEditingController websiteController =
      TextEditingController(); // Added
  final TextEditingController searchController = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController notesController =
      TextEditingController(); // Added

  // Form key
  final formKey = GlobalKey<FormState>();

  // Focus nodes
  final FocusNode titleFocusNode = FocusNode();

  // Category selection
  String? selectedcategory; // RENAMED

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

  // Track the original source of the shared content
  ShareType originalShareType = ShareType.none;

  // --- ADDED ---
  // ID of the existing experience if this card represents one
  String? existingExperienceId;
  // --- END ADDED ---

  // Constructor can set initial values if needed
  // Set default category name
  ExperienceCardData() {
    // Initialize with the name of the first default category, or 'Other'
    selectedcategory = UserCategory.defaultCategories.keys.isNotEmpty
        ? UserCategory.defaultCategories.keys.first
        : 'Other';
  }

  // Dispose resources
  void dispose() {
    titleController.dispose();
    yelpUrlController.dispose();
    websiteController.dispose(); // Added
    searchController.dispose();
    locationController.dispose();
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

  // ADDED: State map for preview expansion
  final Map<int, bool> _previewExpansionStates = {};

  // RENAMED: State for user Categories
  Future<List<UserCategory>>? _userCategoriesFuture;
  List<UserCategory> _userCategories =
      []; // RENAMED Cache the loaded Categories

  @override
  void initState() {
    super.initState();
    // Initialize with the files passed to the widget
    _currentSharedFiles = widget.sharedFiles;

    // Register observer for app lifecycle events
    WidgetsBinding.instance.addObserver(this);

    // RENAMED: Fetch user Categories
    _loadUserCategories();

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
      print(
          '🔄 INIT STATE: getInitialMedia().then() fired.'); // Log when this callback executes
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
              '🔄 INIT STATE: getInitialMedia() - Processing DIFFERENT content.');
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
            _processSharedContent(_currentSharedFiles); // Log before calling
          });
        } else {
          print('🔄 INIT STATE: getInitialMedia() - Content is NOT different.');
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

  // RENAMED: Method to load user Categories
  // UPDATED Return Type
  Future<void> _loadUserCategories() {
    _userCategoriesFuture = _experienceService.getUserCategories();
    // Return the future that completes after setting state or handling error
    return _userCategoriesFuture!.then((Categories) {
      if (mounted) {
        setState(() {
          _userCategories = Categories; // RENAMED state variable
          _updateCardDefaultCategoriesIfNeeded(Categories);
        });
      }
    }).catchError((error) {
      print("Error loading user Categories: $error");
      if (mounted) {
        setState(() {
          // Use empty list instead of defaults on error
          _userCategories = [];
          // _userCategories = UserCategory.createInitialCategories(); // Needs ownerId
        });
        _showSnackBar(
            context, "Error loading your custom Categories. Using defaults.");
      }
      // Optionally rethrow or handle error further if needed
      // throw error;
    });
  }

  // RENAMED: Helper to ensure card default category exists in loaded list
  void _updateCardDefaultCategoriesIfNeeded(
      List<UserCategory> loadedCategories) {
    final provider = context.read<ReceiveShareProvider>();
    if (provider.experienceCards.isEmpty || loadedCategories.isEmpty) return;

    final firstLoadedCategoryName = loadedCategories.first.name;

    for (var card in provider.experienceCards) {
      // Check against renamed field
      if (!loadedCategories.any((c) => c.name == card.selectedcategory)) {
        print(
            "Card default category '${card.selectedcategory}' not found in loaded list. Resetting to '$firstLoadedCategoryName'.");
        // Use renamed field
        card.selectedcategory = firstLoadedCategoryName;
      }
    }
    // If direct update was used, trigger rebuild:
    // setState(() {});
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
          '🔄 STREAM LISTENER: Stream received ${value.length} files. Mounted: $mounted');

      if (mounted && value.isNotEmpty) {
        // --- ADDED: Compare incoming data with current data ---
        // --- REFINED COMPARISON LOGIC ---
        bool isDifferent = true; // Assume different by default
        if (_currentSharedFiles.length == value.length) {
          // If lengths match, compare paths carefully
          isDifferent = false; // Assume same until proven different
          for (int i = 0; i < value.length; i++) {
            // Compare paths at each index
            if (value[i].path != _currentSharedFiles[i].path) {
              print('🔄 STREAM LISTENER: Path difference found at index $i:');
              print('  Current: ${_currentSharedFiles[i].path}');
              print('  Incoming: ${value[i].path}');
              isDifferent = true;
              break; // Found a difference, no need to check further
            }
          }
        } else {
          print(
              '🔄 STREAM LISTENER: Lengths differ (${_currentSharedFiles.length} vs ${value.length})');
          // isDifferent remains true (initialized value)
        }
        // Handle case where current is empty but incoming is not
        if (_currentSharedFiles.isEmpty && value.isNotEmpty) {
          print('🔄 STREAM LISTENER: Current is empty, incoming has data.');
          isDifferent = true;
        }
        // --- END REFINED COMPARISON ---

        print('🔄 STREAM LISTENER: Final isDifferent decision: $isDifferent');

        if (isDifferent) {
          // Only process if the content is actually different
          print('🔄 STREAM LISTENER: Processing DIFFERENT stream content.');
          // Use provider to reset cards
          context.read<ReceiveShareProvider>().resetExperienceCards();
          setState(() {
            _currentSharedFiles = value; // Update with the latest files
            // Reset UI state NOT related to cards
            _businessDataCache.clear(); // Clear cache for new content
            _yelpPreviewFutures.clear();
            // Process the new content
            _processSharedContent(_currentSharedFiles);
          });

          // Reset intent only if processed (and not iOS)
          if (!Platform.isIOS) {
            ReceiveSharingIntent.instance.reset();
            print("SHARE DEBUG: Stream - Intent stream processed and reset.");
          } else {
            print(
                "SHARE DEBUG: On iOS - not resetting intent to ensure it persists");
          }
        } else {
          print(
              '🔄 STREAM LISTENER: Content is the same as current. Ignoring stream event.');
        }
        // --- END COMPARISON ---
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
      // RENAMED: Reload user Categories
      _loadUserCategories();
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

  // Extracts the first valid URL found in a given string
  String? _extractFirstUrl(String text) {
    if (text.isEmpty) return null;
    // More robust regex to find URLs, handling various start/end cases
    final RegExp urlRegex = RegExp(
        r"(?:(?:https?|ftp):\/\/|www\.)[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)",
        caseSensitive: false);
    final match = urlRegex.firstMatch(text);
    return match?.group(0);
  }

  // Process shared content to extract Yelp URLs or Map URLs
  void _processSharedContent(List<SharedMediaFile> files) {
    print(
        '🔄 PROCESSING START: _processSharedContent called with ${files.length} files.');
    print('DEBUG: Processing shared content');
    if (files.isEmpty) {
      print('🔄 PROCESSING END: No files to process.');
      return;
    }

    final fileFirst = files.first; // Example: Log details of the first file
    print(
        '🔄 PROCESSING DETAIL: First file type: ${fileFirst.type}, path: ${fileFirst.path.substring(0, min(100, fileFirst.path.length))}...');

    // Find the first text/URL file and extract the first URL from it
    String? foundUrl;
    for (final file in files) {
      if (file.type == SharedMediaType.text ||
          file.type == SharedMediaType.url) {
        String text = file.path;
        print(
            'DEBUG: Checking shared text: ${text.substring(0, min(100, text.length))}...');
        foundUrl = _extractFirstUrl(text);
        if (foundUrl != null) {
          print('DEBUG: Extracted first URL: $foundUrl');
          // Check if this URL is a special Yelp or Maps URL
          if (_isSpecialUrl(foundUrl)) {
            print('DEBUG: Found special content URL: $foundUrl');
            _processSpecialUrl(
                foundUrl, file); // Pass the whole file for context
            return; // Stop after processing the first special URL found
          } else {
            // Optional: Handle generic URLs if needed, otherwise ignore non-special ones
            print(
                'DEBUG: Extracted URL is not a special Yelp/Maps URL, ignoring.');
            // If you want to handle generic URLs, call a different function here.
            // For now, we only care about Yelp/Maps, so we continue the loop
            // in case another file contains a special URL.
          }
        }
      }
    }

    // If loop completes without finding and processing a special URL
    if (foundUrl == null) {
      print('DEBUG: No processable URL found in any shared text/URL files.');
    } else {
      print(
          'DEBUG: Found a URL ($foundUrl), but it was not a Yelp or Maps URL.');
    }
  }

  // Check if a SINGLE URL string is from Yelp or Google Maps
  bool _isSpecialUrl(String url) {
    if (url.isEmpty) return false;
    String urlLower = url.toLowerCase();

    // Define patterns for special URLs
    final yelpPattern = RegExp(r'yelp\.(com/biz|to)/');
    final mapsPattern =
        RegExp(r'(google\.com/maps|maps\.app\.goo\.gl|goo\.gl/maps)');

    // Check if the URL matches either Yelp or Maps patterns
    if (yelpPattern.hasMatch(urlLower) || mapsPattern.hasMatch(urlLower)) {
      print("DEBUG: _isSpecialUrl detected Yelp or Maps pattern in URL: $url");
      return true;
    }

    print(
        "DEBUG: _isSpecialUrl did not find Yelp or Maps pattern in URL: $url");
    return false;
  }

  // Process a SINGLE special URL (Yelp or Maps)
  void _processSpecialUrl(String url, SharedMediaFile file) {
    print('🔄 PROCESSING START: _processSpecialUrl called with URL: $url');
    final provider = context.read<ReceiveShareProvider>();
    // Ensure at least one card exists before processing
    if (provider.experienceCards.isEmpty) {
      print("DEBUG: Adding initial experience card before processing URL.");
      provider.addExperienceCard();
    }
    // Get the (potentially just added) first card
    final firstCard = provider.experienceCards.first;

    // Normalize URL before checking
    String normalizedUrl = url.trim();
    if (!normalizedUrl.startsWith('http')) {
      normalizedUrl = 'https://' + normalizedUrl;
    }

    if (normalizedUrl.contains('yelp.com/biz') ||
        normalizedUrl.contains('yelp.to/')) {
      print("SHARE DEBUG: Processing as Yelp URL: $normalizedUrl");
      firstCard.originalShareType = ShareType.yelp; // <<< SET SHARE TYPE
      firstCard.yelpUrlController.text =
          normalizedUrl; // Set normalized URL in the card
      // Use the URL as the initial key for the future
      _yelpPreviewFutures[normalizedUrl] = _getBusinessFromYelpUrl(
        normalizedUrl,
        sharedText: file.path, // Pass the full shared text
      );
    } else if (normalizedUrl.contains('google.com/maps') ||
        normalizedUrl.contains('maps.app.goo.gl') ||
        normalizedUrl.contains('goo.gl/maps')) {
      print("SHARE DEBUG: Processing as Google Maps URL: $normalizedUrl");
      firstCard.originalShareType = ShareType.maps; // <<< SET SHARE TYPE
      // Use the URL as the key for the future
      _yelpPreviewFutures[normalizedUrl] =
          _getLocationFromMapsUrl(normalizedUrl);
    } else {
      print("ERROR: _processSpecialUrl called with non-special URL: $url");
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
        _fillFormWithGoogleMapsData(location, placeName, websiteUrl, url);
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
  Future<Map<String, dynamic>?> _getBusinessFromYelpUrl(String yelpUrl,
      {String? sharedText}) async {
    print(
        '🔄 GET YELP START: _getBusinessFromYelpUrl called for URL: $yelpUrl');
    if (sharedText != null) {
      print(
          '🔄 GET YELP START: Shared text provided (first 100 chars): ${sharedText.substring(0, min(100, sharedText.length))}...');
    } else {
      print(
          '🔄 GET YELP START: No shared text provided (likely called from preview).');
    }
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
      print('📊 YELP DATA: Not a Yelp URL, aborting: $url');
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
      // Remove fullSearchText extraction here, rely on URL/Scraping
      // String fullSearchText = "";
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
            url = resolvedUrl; // IMPORTANT: Update the URL variable being used
            isShortUrl = false;
          } else {
            print(
                '📊 YELP DATA: Could not resolve shortened URL or resolved URL is not a /biz/ link.');
          }
        } catch (e) {
          print('📊 YELP DATA: Error resolving shortened URL: $e');
        }
      }

      // --- URL Extraction Logic ---
      // We now assume `url` holds either the original full URL or the resolved full URL.
      bool extractedFromUrl = false;
      if (url.contains('/biz/')) {
        // Extract the business part from URL
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
        List<String> pathParts = bizPath.split('-');

        // If the last part is a number, it indicates a chain location
        if (pathParts.isNotEmpty && RegExp(r'^\d+$').hasMatch(pathParts.last)) {
          print(
              '📊 YELP DATA: Removing numeric suffix ${pathParts.last} from business name');
          pathParts.removeLast();
          isChainFromUrl = true;
        }

        // Check if the last part might be a city name
        // Improved City Extraction - Look for known US states or common abbreviations
        // to better identify the boundary between name and city.
        int cityStartIndex = -1;
        List<String> states = [
          "al",
          "ak",
          "az",
          "ar",
          "ca",
          "co",
          "ct",
          "de",
          "fl",
          "ga",
          "hi",
          "id",
          "il",
          "in",
          "ia",
          "ks",
          "ky",
          "la",
          "me",
          "md",
          "ma",
          "mi",
          "mn",
          "ms",
          "mo",
          "mt",
          "ne",
          "nv",
          "nh",
          "nj",
          "nm",
          "ny",
          "nc",
          "nd",
          "oh",
          "ok",
          "or",
          "pa",
          "ri",
          "sc",
          "sd",
          "tn",
          "tx",
          "ut",
          "vt",
          "va",
          "wa",
          "wv",
          "wi",
          "wy"
        ];

        for (int i = pathParts.length - 1; i >= 0; i--) {
          // Check if a part looks like a state abbreviation or common city endings
          if (states.contains(pathParts[i].toLowerCase()) ||
              ["city", "town", "village"]
                  .contains(pathParts[i].toLowerCase())) {
            // Potential boundary found, city might start after this index
            // Let's assume the city is the part immediately before the state/marker
            if (i > 0) {
              // Make sure there is a part before the state/marker
              cityStartIndex =
                  i - 1; // The part before is likely the end of the city
              break;
            }
          }
          // Simple check if the last part could be a city (less reliable)
          if (i == pathParts.length - 1 &&
              pathParts[i].length > 2 &&
              !isChainFromUrl) {
            final possibleCity = pathParts.last;
            final nonCityWords = [
              'restaurant',
              'pizza',
              'cafe',
              'bar',
              'grill',
              'and',
              'the',
              'co',
              'inc'
            ];
            bool mightBeCity =
                !nonCityWords.contains(possibleCity.toLowerCase());
            if (mightBeCity) {
              cityStartIndex = i; // Assume last part is city
              break;
            }
          }
        }

        if (cityStartIndex != -1 && cityStartIndex < pathParts.length) {
          // Extract city parts (potentially multi-word)
          businessCity = pathParts.sublist(cityStartIndex).join(' ');
          // Capitalize city name properly
          businessCity = businessCity
              .split(' ')
              .map((word) => word.isNotEmpty
                  ? word[0].toUpperCase() + word.substring(1)
                  : '')
              .join(' ');
          print('📊 YELP DATA: Extracted city from URL path: $businessCity');
          // Extract business name parts
          businessName = pathParts.sublist(0, cityStartIndex).join(' ');
        } else {
          // Fallback if city wasn't clearly identified
          businessName = pathParts.join(' ');
          print(
              '📊 YELP DATA: Could not reliably extract city, using full path as name basis: $businessName');
        }

        // Capitalize business name properly
        businessName = businessName
            .split(' ')
            .map((word) => word.isNotEmpty
                ? word[0].toUpperCase() + word.substring(1)
                : '')
            .join(' ');

        print(
            '📊 YELP DATA: Extracted business name from URL path: $businessName');

        if (isChainFromUrl) {
          print(
              '📊 YELP DATA: Marked as chain restaurant based on URL structure');
          _chainDetectedFromUrl = true;
        }

        // Try to extract business type
        final nameParts = businessName.split(' ');
        if (nameParts.isNotEmpty) {
          final lastWord = nameParts.last.toLowerCase();
          if (['restaurant', 'cafe', 'bar', 'grill', 'bakery', 'coffee']
              .contains(lastWord)) {
            businessType = lastWord;
            print('📊 YELP DATA: Extracted business type: $businessType');
          }
        }
        extractedFromUrl =
            true; // Mark that we successfully extracted from URL path
      }

      // --- Shared Text Extraction Fallback ---
      if (!extractedFromUrl && sharedText != null) {
        print(
            '📊 YELP DATA: URL extraction/resolution failed. Attempting name extraction from shared text.');
        try {
          int urlIndex = sharedText.indexOf(yelpUrl); // Find original short URL
          if (urlIndex != -1) {
            String potentialName = sharedText.substring(0, urlIndex).trim();
            // Clean common prefixes
            potentialName = potentialName.replaceAll(
                RegExp(r'^Check out ', caseSensitive: false), '');
            potentialName = potentialName.replaceAll(
                RegExp(r'\s*\n.*$', multiLine: true),
                ''); // Remove lines after name
            potentialName = potentialName.trim();

            if (potentialName.isNotEmpty && potentialName.length < 100) {
              // Basic sanity check
              businessName = potentialName;
              print(
                  '📊 YELP DATA: Extracted business name from shared text: "$businessName"');
            } else {
              print(
                  '📊 YELP DATA: Failed to extract meaningful name from text preceding URL.');
            }
          } else {
            print(
                '📊 YELP DATA: Could not find the Yelp URL within the shared text to extract preceding name.');
          }
        } catch (e) {
          print('📊 YELP DATA: Error during shared text name extraction: $e');
        }
      }

      // Chain detection logic (remains similar)
      bool isChainOrGeneric = _chainDetectedFromUrl;
      if (!isChainOrGeneric && businessName.isNotEmpty) {
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

      // Scraping attempt (can remain as a fallback if needed, but less critical now)
      if (isShortUrl) {
        print(
            '📊 YELP DATA: Short URL was not resolved, attempting scrape as fallback');
        try {
          final extraInfo = await _getLocationDetailsFromYelpPage(
              yelpUrl); // Use original short URL for scrape
          if (extraInfo != null) {
            // Prioritize scraped info if URL parsing failed to get city
            if (businessCity.isEmpty &&
                extraInfo['city'] != null &&
                extraInfo['city']!.isNotEmpty) {
              businessCity = extraInfo['city']!;
              print(
                  '📊 YELP DATA: Extracted city from Yelp page scrape: $businessCity');
            }
            // Add state extraction if needed
            if (extraInfo['state'] != null && extraInfo['state']!.isNotEmpty) {
              businessState = extraInfo['state']!;
              print(
                  '📊 YELP DATA: Extracted state from Yelp page scrape: $businessState');
            }
          }
        } catch (e) {
          print(
              '📊 YELP DATA: Error fetching details from Yelp page scrape: $e');
        }
      }

      // Ensure a business name exists
      if (businessName.isEmpty) {
        businessName = "Shared Business";
        print('📊 YELP DATA: Using generic business name');
      }

      // Create search strategies (prioritize name + city)
      List<String> searchQueries = [];
      if (businessName.isNotEmpty && businessCity.isNotEmpty) {
        String query = '$businessName $businessCity';
        searchQueries.add('"$query"'); // Exact phrase first
        searchQueries.add(query);
      }
      if (businessName.isNotEmpty) {
        searchQueries.add('"$businessName"');
        searchQueries.add(businessName);
      }
      searchQueries = searchQueries.toSet().toList(); // Deduplicate
      print('📊 YELP DATA: Search strategies (in order): $searchQueries');

      // Search Logic (remains mostly the same, but should use better queries now)
      int searchAttempt = 0;
      Location? foundLocation;
      for (final query in searchQueries) {
        searchAttempt++;
        print(
            '📊 YELP DATA: Trying Google Places with query: "$query" (Attempt $searchAttempt/${searchQueries.length})');

        List<Map<String, dynamic>> results;
        if (userPosition != null) {
          print(
              '📊 YELP DATA: Calling searchPlaces WITH location bias (lat: ${userPosition.latitude}, lng: ${userPosition.longitude})');
          results = await _mapsService.searchPlaces(
            query,
            latitude: userPosition.latitude,
            longitude: userPosition.longitude,
            radius: 50000,
          );
        } else {
          print('📊 YELP DATA: Calling searchPlaces WITHOUT location bias');
          results = await _mapsService.searchPlaces(query);
        }

        print(
            '📊 YELP DATA: Got ${results.length} search results from Google Places for query "$query"');

        if (results.isNotEmpty) {
          print(
              '📊 YELP DATA: Results found! First result: ${results[0]['description']}');

          int resultIndex = 0;
          if (results.length > 1) {
            print('📊 YELP DATA: Comparing multiple locations for best match');
            resultIndex = _findBestMatch(
                results, businessAddress, businessCity, businessState);
            print(
                '📊 YELP DATA: Selected result #${resultIndex + 1} as best match based on city/state.');
          }

          final placeId = results[resultIndex]['placeId'];
          if (placeId == null || placeId.isEmpty) {
            print('📊 YELP DATA: Selected result missing placeId, skipping.');
            continue;
          }
          print('📊 YELP DATA: Getting details for place ID: $placeId');

          try {
            foundLocation = await _mapsService.getPlaceDetails(placeId);
          } catch (detailsError) {
            print(
                '📊 YELP DATA ERROR: Failed to get place details for $placeId: $detailsError');
            continue;
          }

          print(
              '📊 YELP DATA: Retrieved location details: ${foundLocation.displayName}, ${foundLocation.address}');
          print(
              '📊 YELP DATA: Coordinates: ${foundLocation.latitude}, ${foundLocation.longitude}');
          print('📊 YELP DATA: Place ID: ${foundLocation.placeId}');

          if (foundLocation.latitude == 0.0 && foundLocation.longitude == 0.0) {
            print(
                '📊 YELP DATA: WARNING - Zero coordinates returned, likely invalid location');
            foundLocation = null;
            continue;
          }

          // Verification Logic (Simplified Name Check, Keep City Check for Chains)
          bool isCorrectBusiness = true;

          // Simple name containment check
          if (businessName.isNotEmpty && foundLocation.displayName != null) {
            final googleNameLower = foundLocation.displayName!.toLowerCase();
            final yelpNameLower = businessName.toLowerCase();
            // Check if Google name contains Yelp name or vice versa (more flexible)
            if (!googleNameLower.contains(yelpNameLower) &&
                !yelpNameLower.contains(googleNameLower.split(' ')[0])) {
              // Check against first word too
              print(
                  '📊 YELP DATA: Name verification failed. Google name \"${foundLocation.displayName}\" doesn\'t align well with Yelp name \"$businessName\"');
              // isCorrectBusiness = false; // Make name check less strict, rely more on city
            } else {
              print(
                  '📊 YELP DATA: Name check passed (containment): Google="${foundLocation.displayName}", Yelp="$businessName"');
            }
          }

          // City verification for chains (critical)
          if (isChainOrGeneric && isCorrectBusiness) {
            if (businessCity.isNotEmpty && foundLocation.city != null) {
              String googleCityLower = foundLocation.city!.toLowerCase();
              String yelpCityLower = businessCity.toLowerCase();
              if (!googleCityLower.contains(yelpCityLower) &&
                  !yelpCityLower.contains(googleCityLower)) {
                print(
                    '📊 YELP DATA: City verification failed for chain. Google city \"${foundLocation.city}\" doesn\'t match Yelp city \"$businessCity\"');
                isCorrectBusiness = false;
                print('📊 YELP DATA: Will try next search strategy');
              } else {
                print(
                    '📊 YELP DATA: City match confirmed for chain restaurant: Google="${foundLocation.city}", Yelp="$businessCity"');
              }
            } else if (businessCity.isNotEmpty && foundLocation.city == null) {
              print(
                  '📊 YELP DATA: City verification needed but Google location has no city info. Assuming mismatch.');
              isCorrectBusiness = false;
            }
          }

          if (isCorrectBusiness) {
            print(
                '📊 YELP DATA: Verification successful for location: ${foundLocation.displayName}');
            break;
          } else {
            print(
                '📊 YELP DATA: Verification failed, trying next search strategy');
            foundLocation = null;
            continue;
          }
        }
      } // End search loop

      // Fallback nearby search for chains (remains the same)
      if (foundLocation == null && isChainOrGeneric && userPosition != null) {
        print(
            '📊 YELP DATA: All strategies failed for chain restaurant, trying FINAL fallback with Nearby Search');
        final nearbyResults = await _mapsService.searchNearbyPlaces(
            userPosition.latitude, userPosition.longitude, 50000, businessName);
        if (nearbyResults.isNotEmpty) {
          // ... (rest of nearby logic is unchanged)
          final placeId = nearbyResults[0]['placeId'];
          if (placeId != null && placeId.isNotEmpty) {
            try {
              foundLocation = await _mapsService.getPlaceDetails(placeId);
              print(
                  '📊 YELP DATA: Successfully found nearby chain location via fallback: ${foundLocation.displayName}');
            } catch (detailsError) {
              print(
                  '📊 YELP DATA ERROR: Failed to get place details for nearby result $placeId: $detailsError');
              foundLocation = null;
            }
          } else {
            print('📊 YELP DATA: Nearby search result missing placeId.');
            foundLocation = null;
          }
        } else {
          print('📊 YELP DATA: Fallback Nearby search found no results.');
          foundLocation = null;
        }
      }

      // Final result processing
      if (foundLocation != null) {
        Map<String, dynamic> resultData = {
          'location': foundLocation,
          'businessName': businessName,
          // Use the URL that was successfully processed (potentially resolved one)
          'yelpUrl': url,
        };
        _businessDataCache[cacheKey] = resultData;
        // Pass the potentially resolved URL to fill form
        _fillFormWithBusinessData(foundLocation, businessName, url);
        print(
            '📊 YELP DATA: Successfully found and processed business data for ${foundLocation.displayName}');
        return resultData;
      } else {
        print(
            '📊 YELP DATA: No suitable location found after trying all search strategies and fallbacks.');
        _businessDataCache[cacheKey] = {};
        return null;
      }
    } catch (e, stackTrace) {
      print(
          '📊 YELP DATA ERROR: Error extracting business from Yelp URL: $e\n$stackTrace');
      return null;
    }
  }

  // Helper method to resolve a shortened URL to its full URL
  Future<String?> _resolveShortUrl(String shortUrl) async {
    print("🔗 RESOLVE: Attempting to resolve URL: $shortUrl"); // Keep log
    try {
      // Reverted back to Dio implementation
      final dio = Dio(BaseOptions(
        followRedirects: true, // Let Dio handle redirects
        maxRedirects: 5, // Sensible limit
        validateStatus: (status) =>
            status != null && status < 500, // Allow redirect statuses
      ));

      final response = await dio.get(shortUrl);

      // After following redirects, the final URL is in response.realUri
      if (response.statusCode == 200 && response.realUri != null) {
        final finalUrl = response.realUri.toString();
        // Check if it actually redirected somewhere different
        if (finalUrl != shortUrl) {
          print(
              "🔗 RESOLVE: Successfully resolved via redirects to: $finalUrl");
          return finalUrl;
        } else {
          print("🔗 RESOLVE: URL did not redirect to a different location.");
          return null; // Or return shortUrl if no redirect is not an error?
        }
      }

      print(
          "🔗 RESOLVE: Request completed but status was ${response.statusCode} or realUri was null.");
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

  // Simplified to prioritize exact city matches for chain restaurants
  int _findBestMatch(List<Map<String, dynamic>> results, String address,
      String city, String state) {
    if (results.isEmpty || results.length == 1) return 0;

    // Normalize the target city name
    final targetCityLower = city.trim().toLowerCase();
    print(
        '📊 YELP DATA _findBestMatch: Looking for results matching city: "$targetCityLower"');

    int bestMatchIndex = 0; // Default to first result
    int highestScore =
        -1; // Score: 2=Exact City, 1=Partial City, 0=State, -1=None

    for (int i = 0; i < results.length; i++) {
      final result = results[i];
      // Prefer 'vicinity' if available, otherwise use 'formatted_address' or 'description'
      final placeAddress = result['vicinity'] as String? ??
          result['formatted_address'] as String? ??
          result['description'] as String? ??
          '';
      final placeAddressLower = placeAddress.toLowerCase();
      print(
          '📊 YELP DATA _findBestMatch: Checking Result ${i + 1}: "$placeAddress"');

      int currentScore = -1;

      // Check for City match first
      if (targetCityLower.isNotEmpty) {
        // Try extracting city using helper
        final extractedCity = _extractCityFromAddress(placeAddress);
        final extractedCityLower = extractedCity.toLowerCase();

        if (extractedCityLower == targetCityLower) {
          print(
              '📊 YELP DATA _findBestMatch: Found EXACT city match "$extractedCity" at index $i');
          currentScore = 2; // Highest score for exact city match
        } else if (placeAddressLower.contains(targetCityLower)) {
          // Check if the full address string contains the city name (partial match)
          print(
              '📊 YELP DATA _findBestMatch: Found PARTIAL city match in address "$placeAddress" at index $i');
          currentScore = max(currentScore, 1); // Score 1 for partial match
        }
      }

      // If no city match found yet, check for state match (lower priority)
      final targetStateLower = state.trim().toLowerCase();
      if (currentScore < 1 &&
          targetStateLower.isNotEmpty &&
          targetStateLower.length == 2) {
        // Only check if state looks valid (2 letters)
        // Look for ", ST " or " ST," or " ST " pattern
        // Use string interpolation within a single raw string
        final statePattern = RegExp(
            r'[\s,]' + targetStateLower + r'(?:\s+\d{5}(-\d{4})?|,|\s*$)',
            caseSensitive: false);

        if (statePattern.hasMatch(placeAddress)) {
          print(
              '📊 YELP DATA _findBestMatch: Found STATE match "$targetStateLower" in address "$placeAddress" at index $i');
          currentScore = max(currentScore, 0); // Score 0 for state match
        }
      }

      // Update best match if current score is higher
      if (currentScore > highestScore) {
        highestScore = currentScore;
        bestMatchIndex = i;
        print(
            '📊 YELP DATA _findBestMatch: New best match index: $i (Score: $highestScore)');
      }

      // If we found an exact city match, we can stop searching
      if (highestScore == 2) {
        break;
      }
    }

    // Return the index of the best match found
    print(
        '📊 YELP DATA _findBestMatch: Final selected index: $bestMatchIndex (Score: $highestScore)');
    return bestMatchIndex;
  }

  // Helper to extract city from Google Places address (Improved)
  String _extractCityFromAddress(String address) {
    if (address.isEmpty) return '';
    final parts = address.split(',');
    if (parts.length >= 3) {
      // City is often the third part from the end (..., City, ST ZIP)
      String potentialCity = parts[parts.length - 3].trim();
      // Basic sanity check: avoid returning state abbreviations or just numbers
      if (potentialCity.length > 2 &&
          !RegExp(r'^[A-Z]{2}$').hasMatch(potentialCity) &&
          !RegExp(r'^\d+$').hasMatch(potentialCity)) {
        return potentialCity;
      }
      // Fallback: try second to last part if third didn't work
      potentialCity = parts[parts.length - 2].trim();
      if (potentialCity.length > 2 &&
          !RegExp(r'^[A-Z]{2}$').hasMatch(potentialCity) &&
          !RegExp(r'^\d+$').hasMatch(potentialCity)) {
        // Remove potential state/zip if present using corrected regex (single backslashes in raw string)
        potentialCity = potentialCity.replaceAll(
            RegExp(r'\s+[A-Z]{2}(\s+\d{5}(-\d{4})?)?$'), '');
        return potentialCity.trim();
      }
    } else if (parts.length == 2) {
      // Less reliable: assume first part might be city if second looks like state/zip
      String potentialCity = parts[0].trim();
      String lastPart = parts[1].trim();
      if (RegExp(r'^[A-Z]{2}(\s+\d{5}(-\d{4})?)?$').hasMatch(lastPart)) {
        return potentialCity;
      }
    } else if (parts.length == 1) {
      // Single part, might be just the city name if it's short enough
      if (address.length < 30 && !address.contains(RegExp(r'\d'))) {
        // Avoid if it looks like a full street address
        return address.trim();
      }
    }
    return ''; // Return empty if city cannot be reliably extracted
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
      // Use the yelpUrl passed to this function for matching
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
        '====> 📝 CARD FORM Log:   Business Name (from Yelp URL parse): $businessName');

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
      targetCard!.yelpUrlController.text =
          yelpUrl; // Set the correct (maybe resolved) yelpUrl
      targetCard!.searchController.text =
          addressToSet; // Use determined address

      targetCard!.websiteController.text =
          websiteToSet; // Use determined website

      // Explicitly update the placeId used by the preview's FutureBuilder key
      targetCard!.placeIdForPreview = location.placeId;
      print(
          '====> 📝 CARD FORM Log:   Set placeIdForPreview to: "${location.placeId}"');

      if (location.photoUrl != null) {
        print('DEBUG: Location has photo URL: ${location.photoUrl}');
      }
    });

    // --- MODIFICATION: Update future map with Place ID as key ---
    setState(() {
      final String originalUrlKey =
          yelpUrl.trim(); // Use the yelpUrl passed to the function
      final String? placeIdKey = location.placeId;

      // Remove old future keyed by URL if it exists
      // Also check if the original cache key exists before trying to remove
      if (_yelpPreviewFutures.containsKey(originalUrlKey)) {
        _yelpPreviewFutures.remove(originalUrlKey);
        print(
            '🔄 FUTURE MAP: Removed future keyed by original URL: $originalUrlKey');
      } else {
        print(
            '🔄 FUTURE MAP: No future found for original URL key to remove: $originalUrlKey');
      }

      // If we have a placeId, update the future map keyed by placeId
      if (placeIdKey != null && placeIdKey.isNotEmpty) {
        final Map<String, dynamic> finalData = {
          'location': location,
          'businessName': location.displayName ??
              businessName, // Prefer Google's name if available
          'yelpUrl': yelpUrl,
          // Add other relevant fields if needed by preview
        };
        // Update the future map with the definitive data, keyed by Place ID
        _yelpPreviewFutures[placeIdKey] = Future.value(finalData);
        print(
            '🔄 FUTURE MAP: Updated/Added future keyed by Place ID: $placeIdKey');
      } else {
        print('🔄 FUTURE MAP: No Place ID available to update future map.');
      }
    });
    // --- END MODIFICATION ---
  }

  // Helper method to fill the form with Google Maps data
  void _fillFormWithGoogleMapsData(Location location, String placeName,
      String websiteUrl, String originalMapsUrl) {
    // Use provider to get cards
    final provider = context.read<ReceiveShareProvider>();
    final firstCard = provider.experienceCards.isNotEmpty
        ? provider.experienceCards.first
        : null;

    if (firstCard == null) return; // Exit if no card exists

    print(
        '🗺️ MAPS FILL: Filling card for Maps Location: ${location.displayName ?? placeName}');

    // Update UI
    setState(() {
      // Set data in the card
      firstCard.titleController.text = location.displayName ?? placeName;
      firstCard.selectedLocation = location;
      firstCard.websiteController.text =
          websiteUrl; // Set official website if available
      firstCard.searchController.text = location.address ?? '';

      // --- ADD THIS LINE ---
      firstCard.placeIdForPreview = location.placeId;
      print('🗺️ MAPS FILL: Set placeIdForPreview to: "${location.placeId}"');
      // --- END ADD ---

      // --- ADD FUTURE MAP UPDATE for Maps ---
      final String? placeIdKey = location.placeId;
      if (placeIdKey != null && placeIdKey.isNotEmpty) {
        final Map<String, dynamic> finalData = {
          'location': location,
          'placeName': placeName, // Use the name passed to this function
          'website': websiteUrl,
          'mapsUrl': originalMapsUrl, // Use the passed original Maps URL
        };
        _yelpPreviewFutures[placeIdKey] =
            Future.value(finalData); // Use the same future map
        print(
            '🔄 FUTURE MAP (Maps): Updated/Added future keyed by Place ID: $placeIdKey');
      } else {
        print(
            '🔄 FUTURE MAP (Maps): No Place ID available to update future map.');
      }
      // --- END FUTURE MAP UPDATE ---
    });

    // Show success message (optional)
    // ScaffoldMessenger.of(context).showSnackBar(
    //   SnackBar(content: Text('Location data filled automatically')),
    // );
  }

  // Handle experience save along with shared content
  Future<void> _saveExperience() async {
    final provider = context.read<ReceiveShareProvider>();
    final experienceCards = provider.experienceCards;

    // RENAMED: Check if Categories are loaded
    if (_userCategories.isEmpty) {
      _showSnackBar(context, 'Categories not loaded yet. Please wait.');
      return;
    }
    // --- END ADDED ---

    bool allValid = true;
    for (var card in experienceCards) {
      if (!card.formKey.currentState!.validate()) {
        allValid = false;
        break;
      }
      // RENAMED: Validate selected category name is set
      if (card.selectedcategory == null || card.selectedcategory!.isEmpty) {
        _showSnackBar(context, 'Please select a category for each card.');
        allValid = false;
        break;
      }
      // --- END ADDED ---
    }

    if (!allValid) {
      _showSnackBar(context, 'Please fill in required fields correctly');
      return;
    }

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

    int successCount = 0;
    int updateCount = 0;
    List<String> errors = [];

    try {
      final now = DateTime.now();
      final List<String> newMediaPaths =
          _currentSharedFiles.map((f) => f.path).toList();

      for (final card in experienceCards) {
        try {
          print(
              "SAVE_DEBUG: Processing card ${card.id}. ExistingExperienceId: ${card.existingExperienceId}");

          // --- Extract necessary info for both Experience and PublicExperience ---
          final String placeId = card.selectedLocation?.placeId ?? '';
          final Location? cardLocation = card.selectedLocation;
          final String cardTitle = card.titleController.text;
          final String cardYelpUrl = card.yelpUrlController.text.trim();
          final String cardWebsite = card.websiteController.text.trim();
          final String notes = card.notesController.text.trim();
          final String categoryNameToSave = card.selectedcategory!;

          // Validate Place ID for Public Experience logic
          bool canProcessPublicExperience =
              placeId.isNotEmpty && cardLocation != null;
          print(
              "SAVE_DEBUG: Can process Public Experience (PlaceID: '$placeId'): $canProcessPublicExperience");

          final Location defaultLocation = Location(
            latitude: 0.0,
            longitude: 0.0,
            address: 'No location specified',
          );

          final Location locationToSave =
              (card.locationEnabled && cardLocation != null)
                  ? cardLocation
                  : defaultLocation;

          // RENAMED: Use selectedcategory
          // final String categoryNameToSave = card.selectedcategory!;
          // UPDATED: Get the full category object using try-catch
          UserCategory? selectedCategoryObject;
          try {
            selectedCategoryObject = _userCategories
                .firstWhere((cat) => cat.name == categoryNameToSave);
          } catch (e) {
            // StateError if not found, assign null
            selectedCategoryObject = null;
          }

          // --- Handle User's Private Experience (Create or Update) --- START ---
          if (card.existingExperienceId == null ||
              card.existingExperienceId!.isEmpty) {
            // CREATE NEW EXPERIENCE
            Experience newExperience = Experience(
              id: '',
              name: cardTitle,
              description:
                  notes.isNotEmpty ? notes : 'Created from shared content',
              location: locationToSave,
              category: categoryNameToSave,
              yelpUrl: cardYelpUrl.isNotEmpty ? cardYelpUrl : null,
              website: cardWebsite.isNotEmpty ? cardWebsite : null,
              additionalNotes: notes.isNotEmpty ? notes : null,
              sharedMediaPaths:
                  newMediaPaths, // These are the *current* shared paths
              createdAt: now,
              updatedAt: now,
            );
            print("SAVE_DEBUG: Creating new Experience: ${newExperience.name}");
            await _experienceService.createExperience(newExperience);
            successCount++;
          } else {
            // UPDATE EXISTING EXPERIENCE
            print(
                "SAVE_DEBUG: Updating existing Experience ID: ${card.existingExperienceId}");
            Experience? existingExperience = await _experienceService
                .getExperience(card.existingExperienceId!);

            if (existingExperience != null) {
              final Set<String> combinedPathsSet = {
                ...?existingExperience.sharedMediaPaths,
                ...newMediaPaths // Combine existing with *current* shared paths
              };
              final List<String> updatedMediaPaths = combinedPathsSet.toList();

              Experience updatedExperience = existingExperience.copyWith(
                name: cardTitle,
                location: locationToSave,
                category: categoryNameToSave,
                yelpUrl: cardYelpUrl.isNotEmpty ? cardYelpUrl : null,
                website: cardWebsite.isNotEmpty ? cardWebsite : null,
                description:
                    notes.isNotEmpty ? notes : existingExperience.description,
                additionalNotes: notes.isNotEmpty ? notes : null,
                sharedMediaPaths: updatedMediaPaths, // Use combined paths
                updatedAt: now,
              );
              print(
                  "SAVE_DEBUG: Updating Experience: ${updatedExperience.name}");
              await _experienceService.updateExperience(updatedExperience);
              updateCount++;
            } else {
              print(
                  'Error: Could not find existing experience with ID: ${card.existingExperienceId}');
              errors.add('Could not update "$cardTitle" (not found).');
            }
          }
          // --- Handle User's Private Experience (Create or Update) --- END ---

          // --- Handle Public Experience (Create or Update Media) --- START ---
          if (canProcessPublicExperience) {
            print(
                "SAVE_DEBUG: Processing Public Experience logic for PlaceID: $placeId");
            // Find existing public experience by placeId
            PublicExperience? existingPublicExp =
                await _experienceService.findPublicExperienceByPlaceId(placeId);

            if (existingPublicExp == null) {
              // CREATE Public Experience
              print(
                  "SAVE_DEBUG: No existing Public Experience found. Creating new one.");
              // Use location's display name for public experience name
              String publicName = cardLocation.getPlaceName();

              PublicExperience newPublicExperience = PublicExperience(
                id: '', // ID will be generated by Firestore
                name: publicName,
                location: cardLocation,
                placeID: placeId,
                yelpUrl: cardYelpUrl.isNotEmpty ? cardYelpUrl : null,
                website: cardWebsite.isNotEmpty ? cardWebsite : null,
                allMediaPaths:
                    newMediaPaths, // Start with the current shared paths
              );
              print("SAVE_DEBUG: Creating Public Experience: $publicName");
              await _experienceService
                  .createPublicExperience(newPublicExperience);
            } else {
              // UPDATE Public Experience (add media paths)
              print(
                  "SAVE_DEBUG: Found existing Public Experience ID: ${existingPublicExp.id}. Adding media paths.");
              await _experienceService.updatePublicExperienceMediaAndMaybeYelp(
                existingPublicExp.id,
                newMediaPaths,
                newYelpUrl: cardYelpUrl.isNotEmpty
                    ? cardYelpUrl
                    : null, // Pass the card's Yelp URL
              );
            }
          } else {
            print(
                "SAVE_DEBUG: Skipping Public Experience logic due to missing PlaceID or Location.");
          }
          // --- Handle Public Experience (Create or Update Media) --- END ---

          // ADDED: Update timestamp for the selected category AFTER successful save/update
          if (selectedCategoryObject != null) {
            try {
              await _experienceService
                  .updateCategoryLastUsedTimestamp(selectedCategoryObject.id);
            } catch (e) {
              // Log error but don't stop the overall process
              print(
                  "Error updating timestamp for category ${selectedCategoryObject.id}: $e");
            }
          } else {
            print(
                "Warning: Could not find category object for '${categoryNameToSave}' to update timestamp.");
          }
        } catch (e) {
          print('Error processing card "${card.titleController.text}": $e');
          errors.add('Error saving "${card.titleController.text}".');
        }
      } // End for loop

      String message;
      if (errors.isEmpty) {
        message = '';
        if (successCount > 0)
          message += '$successCount experience(s) created. ';
        if (updateCount > 0) message += '$updateCount experience(s) updated. ';
        message = message.trim();
        if (message.isEmpty) message = 'No changes saved.';
      } else {
        message = 'Completed with errors: ';
        if (successCount > 0) message += '$successCount created. ';
        if (updateCount > 0) message += '$updateCount updated. ';
        message += '${errors.length} failed.';
        print('Save errors: ${errors.join('\n')}');
      }
      _showSnackBar(context, message);

      // widget.onCancel(); // OLD: Call the cancel callback
      // Navigator.pop(context); // OLD: Explicitly pop the current screen
      // NEW: Navigate to MainScreen and remove all routes until
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const MainScreen()),
        (Route<dynamic> route) => false, // Remove all routes
      );
    } catch (e) {
      print('Error saving experiences: $e');
      _showSnackBar(context, 'Error saving experiences: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
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

    // Use the tracked original share type
    bool isOriginalShareYelp = card.originalShareType == ShareType.yelp;
    print(
        "LocationPicker opening context: originalShareType is ${card.originalShareType}");

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          initialLocation: card.selectedLocation,
          // Pass a dummy callback, the update happens below based on the result
          onLocationSelected: (location) {},
          // isFromYelpShare: isOriginalShareYelp, // No longer needed? Remove if LocationPickerScreen doesn't use it
          // Pass name hint (assuming LocationPickerScreen has this param)
          businessNameHint:
              isOriginalShareYelp ? card.titleController.text : null,
        ),
      ),
    );

    if (result != null && mounted) {
      // Unfocus again after returning
      Future.microtask(() => FocusScope.of(context).unfocus());

      final Location selectedLocation =
          result is Map ? result['location'] : result as Location;
      // shouldUpdateYelpInfo is effectively handled by the isOriginalShareYelp check now

      final provider = context.read<ReceiveShareProvider>();

      // Check based on the ORIGINAL share type
      if (isOriginalShareYelp) {
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
          _showSnackBar(
              context, "Error updating location details from Yelp context: $e");
          // Fallback: Update with the basic location selected
          provider.updateCardData(card, location: selectedLocation);
        }
      } else {
        // Just update the location using Provider based on picker selection
        print(
            "LocationPicker returned (non-Yelp/Maps/etc. context): Fetching details and updating card fully.");
        // --- ENHANCED UPDATE LOGIC for non-Yelp contexts ---
        try {
          if (selectedLocation.placeId == null ||
              selectedLocation.placeId!.isEmpty) {
            print(
                "Error: Location picked has no Place ID. Performing basic update.");
            // Basic update if no Place ID
            provider.updateCardData(card,
                location: selectedLocation,
                searchQuery: selectedLocation.address ?? 'Selected Location');
            return;
          }

          print(
              "Fetching details for selected Place ID: ${selectedLocation.placeId}");
          Location detailedLocation =
              await _mapsService.getPlaceDetails(selectedLocation.placeId!);
          print(
              "Fetched details: ${detailedLocation.displayName}, Addr: ${detailedLocation.address}, Web: ${detailedLocation.website}");

          // Prepare data for update
          final String title = detailedLocation.getPlaceName();
          final String? website = detailedLocation.website;
          final String address = detailedLocation.address ?? '';
          final String? placeId = detailedLocation.placeId;

          // Clear potentially conflicting caches (use original URL if needed, or Place ID?)
          // Let's clear based on the *old* placeIdForPreview if it exists
          if (card.placeIdForPreview != null) {
            _yelpPreviewFutures.remove(card.placeIdForPreview);
            print(
                "Cleared future cache for old placeId: ${card.placeIdForPreview}");
          }
          // Consider clearing _businessDataCache too if necessary, based on how keys are formed.

          // Update card data via provider with all fetched details
          provider.updateCardData(card,
              location: detailedLocation,
              title: title,
              website: website,
              searchQuery: address,
              placeIdForPreview: placeId);

          // Update the futures map with the *new* detailed data, keyed by Place ID
          if (placeId != null && placeId.isNotEmpty) {
            final String futureKey = placeId;
            final Map<String, dynamic> newFutureData = {
              'location': detailedLocation,
              'placeName': title, // Use consistent naming
              'website': website,
              'mapsUrl':
                  null, // Explicitly null as original Maps URL isn't relevant to the NEW location preview
              'photoUrl': detailedLocation.photoUrl,
              'address': address,
            };
            _yelpPreviewFutures[futureKey] = Future.value(newFutureData);
            print("Updated future cache for new placeId: $futureKey");
          }

          // Trigger rebuild for the preview widget if it depends on the future map
          setState(() {});
          print("LocationPicker update successful for non-Yelp context.");
        } catch (e) {
          print(
              "Error getting place details or updating card in non-Yelp context: $e");
          _showSnackBar(context, "Error updating location details: $e");
          // Fallback: Update with the basic location selected if details fetch fails
          provider.updateCardData(card,
              location: selectedLocation,
              searchQuery: selectedLocation.address ?? 'Selected Location');
        }
        // --- END ENHANCED UPDATE LOGIC ---
      }
    } else {
      print("LocationPicker returned null or screen unmounted.");
    }
  }

  // Navigate to select an existing experience and update the card
  Future<void> _selectSavedExperienceForCard(ExperienceCardData card) async {
    // Ensure the context is valid before navigating
    if (!mounted) return;

    final selectedExperience = await Navigator.push<Experience>(
      context,
      MaterialPageRoute(
        builder: (context) => const SelectSavedExperienceScreen(),
      ),
    );

    if (selectedExperience != null && mounted) {
      // Unfocus after returning
      Future.microtask(() => FocusScope.of(context).unfocus());

      // Use provider to update the specific card
      context.read<ReceiveShareProvider>().updateCardWithExistingExperience(
            card.id, // Use the card's unique ID to find it
            selectedExperience,
          );
      // Trigger a rebuild to show updated card form details
      // This setState might not be strictly necessary if the provider update
      // triggers the ExperienceCardForm rebuild correctly via context.watch,
      // but it can ensure the ReceiveShareScreen itself rebuilds if needed.
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final shareProvider = context.watch<ReceiveShareProvider>();
    final experienceCards = shareProvider.experienceCards;

    return _wrapWithWillPopScope(Scaffold(
      appBar: AppBar(
        title: _isSpecialUrl(_currentSharedFiles.isNotEmpty
                ? _extractFirstUrl(_currentSharedFiles.first.path) ?? ''
                : '') // Check if first file content contains a special URL
            ? const Text('Save Shared Content')
            : const Text('Save Shared Media'),
        leading: IconButton(
          // Use leading for the cancel/back action
          icon: Icon(Platform.isIOS ? Icons.arrow_back_ios : Icons.arrow_back),
          onPressed: widget.onCancel, // Use the cancel callback
        ),
        automaticallyImplyLeading:
            false, // We handle the leading button manually
        actions: [
          // Add button - only show if not special content
          if (!_isSpecialUrl(_currentSharedFiles.isNotEmpty
              ? _extractFirstUrl(_currentSharedFiles.first.path) ?? ''
              : '')) // Check if first file content contains a special URL
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
            // RENAMED: FutureBuilder for User Categories
            : FutureBuilder<List<UserCategory>>(
                future: _userCategoriesFuture, // RENAMED future
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    // Already handled error in _loadUserCategories, show the UI with defaults
                    print(
                        "FutureBuilder Error (already handled): ${snapshot.error}");
                    // Proceed to build UI with potentially default Categories loaded in _userCategories
                  }
                  // snapshot.hasData or error handled (defaults loaded)
                  // Now _userCategories should be populated

                  return Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: 80),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Preview section
                              if (_currentSharedFiles.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Center(
                                      child:
                                          Text('No shared content received')),
                                )
                              else
                                // REMOVED Outer Padding around ListView
                                ListView.builder(
                                  padding: EdgeInsets
                                      .zero, // Ensure ListView itself has no padding
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _currentSharedFiles.length,
                                  itemBuilder: (context, index) {
                                    final file = _currentSharedFiles[index];
                                    final firstCard = experienceCards.isNotEmpty
                                        ? experienceCards.first
                                        : null;

                                    // --- ADDED: Conditional Padding Logic ---
                                    bool isInstagram = false;
                                    if (file.type == SharedMediaType.text ||
                                        file.type == SharedMediaType.url) {
                                      String? url = _extractFirstUrl(file.path);
                                      if (url != null &&
                                          url.contains('instagram.com')) {
                                        isInstagram = true;
                                      }
                                    }
                                    final double horizontalPadding =
                                        isInstagram ? 0.0 : 16.0;
                                    final double verticalPadding =
                                        8.0; // Consistent vertical padding
                                    // --- END Conditional Padding Logic ---

                                    // Apply padding conditionally around the Card
                                    return Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: horizontalPadding,
                                        vertical: verticalPadding,
                                      ),
                                      child: Card(
                                        elevation: 2.0,
                                        // SET margin based on type
                                        margin: isInstagram
                                            ? EdgeInsets.zero
                                            : const EdgeInsets.only(
                                                bottom:
                                                    0), // Keep original vertical logic if any was intended, else just use EdgeInsets.zero for instagram
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                              isInstagram ? 0 : 8),
                                        ),
                                        clipBehavior: isInstagram
                                            ? Clip.antiAlias
                                            : Clip.none,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (firstCard != null)
                                              _buildMediaPreview(
                                                  file, firstCard, index)
                                            else
                                              // Fallback: Pass index here too
                                              _buildMediaPreview(
                                                  file, null, index),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),

                              // Experience association form section
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (experienceCards.isNotEmpty)
                                      // --- Restored Title Placeholder ---
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            top: 16.0, bottom: 8.0),
                                        child: Text(
                                            experienceCards.length > 1
                                                ? 'Save to Experiences'
                                                : 'Save to Experience',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge),
                                      )
                                    // --- End Title Placeholder ---
                                    else
                                      // --- Restored No Cards Title ---
                                      const Padding(
                                          padding: EdgeInsets.only(
                                              top: 16.0, bottom: 8.0),
                                          child: Text(
                                              "No Experience Card")), // <<< ADDED COMMA HERE
                                    // --- End No Cards Title ---

                                    const SizedBox(height: 8),

                                    if (experienceCards.isEmpty)
                                      // --- Restored Error Placeholder ---
                                      const Center(
                                          child: Padding(
                                        padding: EdgeInsets.symmetric(
                                            vertical: 20.0),
                                        child: Text(
                                            "Error: No experience card available.",
                                            style:
                                                TextStyle(color: Colors.red)),
                                      ))
                                    // --- End Error Placeholder ---
                                    else
                                      ListView.builder(
                                          padding: EdgeInsets.zero,
                                          shrinkWrap: true,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          itemCount: experienceCards.length,
                                          itemBuilder: (context, i) {
                                            final card = experienceCards[i];
                                            // ADDED Key based on the category list to force rebuild
                                            return ExperienceCardForm(
                                              key: ObjectKey(
                                                  _userCategories), // Key changes when list instance changes
                                              cardData: card,
                                              isFirstCard: i == 0,
                                              canRemove:
                                                  experienceCards.length > 1,
                                              userCategories: _userCategories,
                                              onRemove: _removeExperienceCard,
                                              onLocationSelect:
                                                  _showLocationPicker,
                                              onSelectSavedExperience:
                                                  _selectSavedExperienceForCard,
                                              // UPDATED onUpdate handling:
                                              onUpdate: (
                                                  {bool refreshCategories =
                                                      false,
                                                  String? newCategoryName}) {
                                                print(
                                                    "onUpdate called: refreshCategories=$refreshCategories, newCategoryName=$newCategoryName"); // Log entry
                                                if (refreshCategories) {
                                                  print(
                                                      "  Refreshing Categories...");
                                                  _loadUserCategories()
                                                      .then((_) {
                                                    print(
                                                        "  _loadUserCategories finished.");
                                                    if (mounted) {
                                                      print(
                                                          "  Component is mounted.");
                                                      // Log BEFORE potential state update for newCategoryName
                                                      print(
                                                          "  _userCategories length BEFORE setState: ${_userCategories.length}");
                                                      if (newCategoryName !=
                                                          null) {
                                                        // Find the card associated with this specific form instance
                                                        // Note: This relies on the closure capturing the correct 'card'
                                                        print(
                                                            "  Attempting to set selected category for card ${card.id} to: $newCategoryName");
                                                        setState(() {
                                                          card.selectedcategory =
                                                              newCategoryName;
                                                          print(
                                                              "  setState called for newCategoryName selection.");
                                                        });
                                                      } else {
                                                        // If only refresh was requested (e.g., after Edit modal)
                                                        // We still need setState to trigger rebuild with the new list loaded by _loadUserCategories
                                                        print(
                                                            "  Only refresh requested, calling setState to update list.");
                                                        setState(() {});
                                                      }
                                                      // Log AFTER state update
                                                      print(
                                                          "  _userCategories length AFTER setState: ${_userCategories.length}");
                                                    } else {
                                                      print(
                                                          "  Component is NOT mounted after _loadUserCategories.");
                                                    }
                                                  });
                                                } else {
                                                  // Just trigger rebuild for other updates if needed
                                                  print(
                                                      "onUpdate: Non-category update, calling setState.");
                                                  if (mounted) {
                                                    setState(() {});
                                                  }
                                                }
                                              },
                                              formKey: card.formKey,
                                            );
                                          }),

                                    // Add another experience button
                                    // --- Restored _isSpecialUrl check ---
                                    if (!_isSpecialUrl(_currentSharedFiles
                                            .isNotEmpty
                                        ? _extractFirstUrl(_currentSharedFiles
                                                .first.path) ??
                                            ''
                                        : ''))
                                      // --- End Restored Check ---
                                      // --- Restored Button Placeholder ---
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            top: 12.0, bottom: 16.0),
                                        child: Center(
                                          child: OutlinedButton.icon(
                                            icon: const Icon(Icons.add),
                                            label: const Text(
                                                'Add Another Experience'),
                                            onPressed: _addExperienceCard,
                                            style: OutlinedButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 12,
                                                      horizontal: 24),
                                              side: BorderSide(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary),
                                            ),
                                          ),
                                        ),
                                      )
                                    // --- End Button Placeholder ---
                                    ,
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Action buttons (Save/Cancel) - Fixed at the bottom
                      // --- Restored Buttons Container ---
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 12.0),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              spreadRadius: 0,
                              blurRadius: 4,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            OutlinedButton(
                              onPressed: widget.onCancel,
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
                              label: Text(_isSaving
                                  ? 'Saving...'
                                  : 'Save Experience(s)'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 12),
                              ),
                            ),
                          ],
                        ),
                      )
                      // --- End Buttons Container ---
                    ],
                  );
                },
              ),
        // --- END FutureBuilder ---
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
  Widget _buildMediaPreview(
      SharedMediaFile file, ExperienceCardData? card, int index) {
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
        // Pass index to buildTextPreview
        return _buildTextPreview(file, card, index);
      case SharedMediaType.file:
      default:
        // Assuming _buildFilePreview doesn't need provider data directly
        return _buildFilePreview(file);
    }
  }

  // Modify _buildTextPreview to accept index
  Widget _buildTextPreview(
      SharedMediaFile file, ExperienceCardData? card, int index) {
    // final provider = context.read<ReceiveShareProvider>(); // Not needed directly here now

    String textContent = file.path; // Path contains the text or URL

    // Extract the first URL found in the text content
    String? extractedUrl = _extractFirstUrl(textContent);

    // Check if we extracted a URL
    if (extractedUrl != null) {
      // Check if it's a special one (Yelp/Maps)
      // Pass index to buildUrlPreview
      return _buildUrlPreview(extractedUrl, card, index);
    } else {
      // No URL extracted, display the original text content
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
  // This method already handles routing to InstagramPreviewWidget
  Widget _buildUrlPreview(String url, ExperienceCardData? card, int index) {
    // Access provider only if needed for actions, not just data access
    // final provider = context.read<ReceiveShareProvider>();

    // Special handling for Yelp URLs (ensure card is not null)
    if (card != null &&
        (url.contains('yelp.com/biz') || url.contains('yelp.to/'))) {
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
      // Determine expansion state for this specific preview
      final bool isExpanded = _previewExpansionStates[index] ?? false;
      // Determine height based on expansion
      final double height = isExpanded
          ? 1200.0
          : 400.0; // Default collapsed height for receive screen

      // Build Column with WebView and Buttons
      return Column(
        mainAxisSize:
            MainAxisSize.min, // Prevent column from taking excessive space
        children: [
          // The WebView
          instagram_widget.InstagramWebView(
            url: url,
            height: height, // Pass calculated height
            launchUrlCallback: _launchUrl,
            onWebViewCreated: (controller) {},
            onPageFinished: (url) {},
          ),
          // Spacing
          const SizedBox(height: 8),
          // Buttons specific to ReceiveShareScreen
          Row(
            // Space buttons out, pushing Expand to the right
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Spacer to help center the Instagram button
              const SizedBox(width: 48), // Approx width of an IconButton
              // Instagram Button (Centered)
              IconButton(
                icon: const Icon(FontAwesomeIcons.instagram),
                color: const Color(0xFFE1306C),
                iconSize: 32, // Increased size
                tooltip: 'Open in Instagram',
                constraints: const BoxConstraints(),
                padding:
                    EdgeInsets.zero, // Remove padding if centering with Spacer
                onPressed: () => _launchUrl(url),
              ),
              // Expand/Collapse Button (Right side)
              IconButton(
                icon:
                    Icon(isExpanded ? Icons.fullscreen_exit : Icons.fullscreen),
                iconSize: 24,
                color: Colors.blue,
                tooltip: isExpanded ? 'Collapse' : 'Expand',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                onPressed: () {
                  setState(() {
                    _previewExpansionStates[index] = !isExpanded;
                  });
                },
              ),
            ],
          ),
          // Optional extra spacing below buttons if needed
          const SizedBox(height: 8),
        ],
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

  // Fetches location details from a Google Maps URL (Simplified)
  Future<Map<String, dynamic>?> _getLocationFromMapsUrl(String mapsUrl) async {
    print(
        '🔄 GET MAPS START: _getLocationFromMapsUrl called for URL: $mapsUrl');
    print("🗺️ MAPS PARSE (Simplified): Getting location for URL: $mapsUrl");
    final String originalUrlKey = mapsUrl.trim();

    // --- Check Cache ---
    if (_businessDataCache.containsKey(originalUrlKey)) {
      print("🗺️ MAPS PARSE: Returning cached data for $originalUrlKey");
      return _businessDataCache[originalUrlKey];
    }

    // --- 1. Resolve URL ---
    String resolvedUrl = mapsUrl;
    if (!resolvedUrl.contains('google.com/maps')) {
      try {
        final String? expandedUrl = await _resolveShortUrl(resolvedUrl);
        if (expandedUrl != null && expandedUrl.contains('google.com/maps')) {
          resolvedUrl = expandedUrl;
          print("🗺️ MAPS PARSE: Resolved short URL to: $resolvedUrl");
        } else {
          print(
              "🗺️ MAPS PARSE ERROR: Failed to resolve short URL or not a Google Maps link: $expandedUrl");
          return null;
        }
      } catch (e) {
        print(
            "🗺️ MAPS PARSE ERROR: Error resolving short URL $resolvedUrl: $e");
        return null;
      }
    }

    // Ensure it's a google.com/maps link now
    if (!resolvedUrl.contains('google.com/maps')) {
      print(
          "🗺️ MAPS PARSE ERROR: URL is not a standard Google Maps URL: $resolvedUrl");
      return null;
    }

    Location? foundLocation;
    String? placeIdToLookup;

    try {
      // --- 2. Search with Extracted Path Info (Primary Strategy) ---
      String searchQuery =
          resolvedUrl; // Default to full URL in case path extraction fails
      try {
        final Uri uri = Uri.parse(resolvedUrl);
        // Look for /place/ segment
        final placeSegmentIndex = uri.pathSegments.indexOf('place');
        if (placeSegmentIndex != -1 &&
            placeSegmentIndex < uri.pathSegments.length - 1) {
          // Extract text after /place/
          String placePathInfo = uri.pathSegments[placeSegmentIndex + 1];
          // Decode and clean up
          placePathInfo =
              Uri.decodeComponent(placePathInfo).replaceAll('+', ' ');
          // Remove trailing coordinates if present (@lat,lng)
          placePathInfo = placePathInfo.split('@')[0].trim();

          if (placePathInfo.isNotEmpty) {
            searchQuery = placePathInfo;
            print(
                "🗺️ MAPS PARSE: Extracted path info for search fallback: \"$searchQuery\"");
          } else {
            print(
                "🗺️ MAPS PARSE WARN: Found /place/ segment but extracted info was empty. Using full URL.");
          }
        } else {
          print(
              "🗺️ MAPS PARSE: No /place/ segment found in path. Using full URL for fallback search.");
        }
      } catch (e) {
        print(
            "🗺️ MAPS PARSE ERROR: Error parsing URL path for fallback query: $e. Using full URL.");
      }

      print(
          "🗺️ MAPS PARSE (Path Search): Searching Places API with query: \"$searchQuery\"");
      try {
        List<Map<String, dynamic>> searchResults =
            await _mapsService.searchPlaces(searchQuery);

        if (searchResults.isNotEmpty) {
          // Extract placeId from the first result
          placeIdToLookup = searchResults.first['placeId'] as String?;
          if (placeIdToLookup != null && placeIdToLookup.isNotEmpty) {
            print(
                "🗺️ MAPS PARSE: Search found Place ID: '$placeIdToLookup'. Getting details.");
            // Get details using the placeId from search
            foundLocation = await _mapsService.getPlaceDetails(placeIdToLookup);
            print(
                "🗺️ MAPS PARSE (Path Search): Successfully found location: ${foundLocation.displayName}");
          } else {
            print(
                "🗺️ MAPS PARSE WARN: Top search result for query did not contain a Place ID.");
          }
        } else {
          print(
              "🗺️ MAPS PARSE WARN: Search with query \"$searchQuery\" returned no results.");
        }
      } catch (e) {
        print(
            "🗺️ MAPS PARSE ERROR: Error during fallback search with query \"$searchQuery\": $e");
      }

      // --- 3. Extract Place ID from Query (Fallback Strategy) ---
      // Only try this if the path search failed
      if (foundLocation == null) {
        print(
            "🗺️ MAPS PARSE: Path search failed. Trying Place ID extraction from query parameters as fallback.");
        placeIdToLookup = _extractPlaceIdFromMapsUrl(resolvedUrl);

        if (placeIdToLookup != null && placeIdToLookup.isNotEmpty) {
          print(
              "🗺️ MAPS PARSE (Query Fallback): Found Place ID '$placeIdToLookup'. Attempting direct lookup.");
          try {
            foundLocation = await _mapsService.getPlaceDetails(placeIdToLookup);
            print(
                "🗺️ MAPS PARSE (Query Fallback): Successfully found location: ${foundLocation.displayName}");
          } catch (e) {
            print(
                "🗺️ MAPS PARSE ERROR (Query Fallback): Direct Place ID lookup failed for '$placeIdToLookup': $e.");
            foundLocation = null; // Ensure location is null if lookup fails
          }
        } else {
          print(
              "🗺️ MAPS PARSE (Query Fallback): No Place ID (cid/placeid) found in query parameters either.");
        }
      }

      // --- 4. Final Check and Return ---
      if (foundLocation != null) {
        final String finalName = foundLocation.getPlaceName(); // Use helper
        final String? finalWebsite = foundLocation.website;

        // Fill form using the first card from provider
        final provider = context.read<ReceiveShareProvider>();
        if (provider.experienceCards.isNotEmpty) {
          _fillFormWithGoogleMapsData(foundLocation, finalName,
              finalWebsite ?? '', mapsUrl); // Pass original mapsUrl
        }

        // Prepare result map for FutureBuilder
        final Map<String, dynamic> result = {
          'location': foundLocation,
          // Use a consistent key, 'businessName' might be misleading for Maps
          'placeName': finalName,
          'website': finalWebsite,
          'mapsUrl': mapsUrl, // Original URL for reference
        };

        // Cache the result using the original URL
        _businessDataCache[originalUrlKey] = result;
        print("🗺️ MAPS PARSE: Successfully processed Maps URL: $mapsUrl");
        return result;
      } else {
        print(
            "🗺️ MAPS PARSE ERROR: Failed to determine location from Maps URL after all strategies: $mapsUrl");
        _businessDataCache[originalUrlKey] = {}; // Cache empty result
        return null; // Could not find location
      }
    } catch (e) {
      print(
          "🗺️ MAPS PARSE ERROR: Unexpected error processing Google Maps URL $mapsUrl: $e");
      _businessDataCache[originalUrlKey] = {}; // Cache empty result
      return null;
    }
  }

  // Extracts PlaceID ONLY from Google Maps URL query parameters (Simplified)
  String? _extractPlaceIdFromMapsUrl(String url) {
    print("🗺️ EXTRACT (Simplified): Parsing URL for Place ID: $url");
    try {
      final Uri uri = Uri.parse(url);
      final queryParams = uri.queryParameters;

      // Get Place ID from 'cid' (preferred) or 'placeid'
      String? placeId = queryParams['cid'] ?? queryParams['placeid'];

      if (placeId != null && placeId.isNotEmpty) {
        // Basic sanity check: Place IDs are typically > 10 chars and don't contain spaces
        if (placeId.length > 10 && !placeId.contains(' ')) {
          print(
              "🗺️ EXTRACT (Simplified): Found Place ID '$placeId' in query parameters.");
          return placeId.trim();
        } else {
          print(
              "🗺️ EXTRACT (Simplified): Found potential Place ID '$placeId' but it looks invalid. Ignoring.");
          return null;
        }
      } else {
        print(
            "🗺️ EXTRACT (Simplified): No Place ID (cid/placeid) found in query parameters.");
        return null;
      }
    } catch (e) {
      print("🗺️ EXTRACT (Simplified): Error parsing URL: $e");
      return null;
    }
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
