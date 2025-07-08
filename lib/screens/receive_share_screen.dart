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
import 'package:provider/provider.dart';
import '../providers/receive_share_provider.dart';
import '../models/experience.dart';
import '../models/user_category.dart';
import '../models/color_category.dart';
import '../models/shared_media_item.dart';
import '../services/experience_service.dart';
import '../services/google_maps_service.dart';
import '../services/google_knowledge_graph_service.dart';
import '../widgets/google_maps_widget.dart';
import 'location_picker_screen.dart';
import '../services/sharing_service.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'receive_share/widgets/yelp_preview_widget.dart';
import 'receive_share/widgets/maps_preview_widget.dart';
import 'receive_share/widgets/generic_url_preview_widget.dart';
import 'receive_share/widgets/google_knowledge_graph_preview_widget.dart';
import 'receive_share/widgets/image_preview_widget.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:shared_preferences/shared_preferences.dart';
import 'receive_share/widgets/experience_card_form.dart';
import '../widgets/select_saved_experience_modal_content.dart'; // Attempting relative import again
import 'receive_share/widgets/instagram_preview_widget.dart'
    as instagram_widget;
import 'receive_share/widgets/tiktok_preview_widget.dart';
import 'receive_share/widgets/facebook_preview_widget.dart';
import 'receive_share/widgets/youtube_preview_widget.dart';
import 'main_screen.dart';
import '../models/public_experience.dart';
import '../services/auth_service.dart';
import 'package:collection/collection.dart';
import 'package:plendy/config/app_constants.dart';
// Import ApiSecrets conditionally
import '../config/api_secrets.dart' if (dart.library.io) '../config/api_secrets.dart' if (dart.library.html) '../config/api_secrets.dart';
import 'package:fluttertoast/fluttertoast.dart';

// Ensures _ExperienceCardsSection is defined at the top-level
class _ExperienceCardsSection extends StatelessWidget {
  final List<UserCategory> userCategories;
  final List<ColorCategory> userColorCategories;
  final ValueNotifier<List<UserCategory>> userCategoriesNotifier;
  final ValueNotifier<List<ColorCategory>> userColorCategoriesNotifier;
  final void Function(ExperienceCardData) removeExperienceCard;
  final Future<void> Function(ExperienceCardData) showLocationPicker;
  final Future<void> Function(ExperienceCardData) selectSavedExperienceForCard;
  final void Function({
    required String cardId,
    bool refreshCategories,
    String? newCategoryName,
    String? selectedColorCategoryId,
    String? newTitleFromCard, // ADDED to match new signature
  }) handleCardFormUpdate;
  final void Function() addExperienceCard;
  final bool Function(String) isSpecialUrl;
  final String? Function(String) extractFirstUrl;
  final List<SharedMediaFile> currentSharedFiles;
  final List<ExperienceCardData> experienceCards; // ADDED: To receive cards directly
  final GlobalKey? sectionKey; // ADDED for scrolling
  final void Function(String cardId)? onYelpButtonTapped; // ADDED

  const _ExperienceCardsSection({
    super.key,
    required this.userCategories,
    required this.userColorCategories,
    required this.userCategoriesNotifier,
    required this.userColorCategoriesNotifier,
    required this.removeExperienceCard,
    required this.showLocationPicker,
    required this.selectSavedExperienceForCard,
    required this.handleCardFormUpdate,
    required this.addExperienceCard,
    required this.isSpecialUrl,
    required this.extractFirstUrl,
    required this.currentSharedFiles,
    required this.experienceCards, // ADDED: To constructor
    this.sectionKey, // ADDED for scrolling
    this.onYelpButtonTapped, // ADDED
  });

  @override
  Widget build(BuildContext context) {
    // REMOVED: No longer watching provider directly here
    // final shareProvider = context.watch<ReceiveShareProvider>();
    // final experienceCards = shareProvider.experienceCards;
    print("ReceiveShareScreen: _ExperienceCardsSection build called. Cards count: ${experienceCards.length}");

    return Padding(
      key: sectionKey, // ADDED for scrolling
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (experienceCards.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
              child: Text(
                  experienceCards.length > 1
                      ? 'Save to Experiences'
                      : 'Save to Experience',
                  style: Theme.of(context).textTheme.titleLarge),
            )
          else
            const Padding(
                padding: EdgeInsets.only(top: 16.0, bottom: 8.0),
                child: Text("No Experience Card")),
          const SizedBox(height: 8),
          if (experienceCards.isEmpty)
            const Center(
                child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20.0),
              child: Text("Error: No experience card available.",
                  style: TextStyle(color: Colors.red)),
            ))
          else
            ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: experienceCards.length,
                itemBuilder: (context, i) {
                  final card = experienceCards[i];
                  return ExperienceCardForm(
                    key: ValueKey(card.id),
                    cardData: card,
                    isFirstCard: i == 0,
                    canRemove: experienceCards.length > 1,
                    userCategoriesNotifier: userCategoriesNotifier,
                    userColorCategoriesNotifier: userColorCategoriesNotifier,
                    onRemove: removeExperienceCard,
                    onLocationSelect: showLocationPicker,
                    onSelectSavedExperience: selectSavedExperienceForCard,
                    onUpdate: ({
                      bool refreshCategories = false,
                      String? newCategoryName,
                      String? selectedColorCategoryId,
                      String? newTitleFromCard, // ADDED to match new signature
                    }) {
                      handleCardFormUpdate(
                        cardId: card.id,
                        refreshCategories: refreshCategories,
                        newCategoryName: newCategoryName,
                        selectedColorCategoryId: selectedColorCategoryId,
                        newTitleFromCard: newTitleFromCard, // Pass it through
                      );
                    },
                    formKey: card.formKey,
                    onYelpButtonTapped: onYelpButtonTapped, // ADDED
                  );
                }),
          if (!isSpecialUrl(currentSharedFiles.isNotEmpty
              ? extractFirstUrl(currentSharedFiles.first.path) ?? ''
              : ''))
            Padding(
              padding: const EdgeInsets.only(top: 12.0, bottom: 16.0),
              child: Center(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add Another Experience'),
                  onPressed: () { // MODIFIED: Added print statement
                    print("ReceiveShareScreen: 'Add Another Experience' button pressed in _ExperienceCardsSection.");
                    addExperienceCard();
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 24),
                    side: BorderSide(
                        color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

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
  String? selectedCategoryId; // NEW: Stores the ID of the UserCategory

  // Rating
  double rating = 0.0; // Added (or use double? rating)

  // Location selection
  Location? selectedLocation;
  Location? location;
  bool isSelectingLocation = false;
  ValueNotifier<bool> locationEnabled = ValueNotifier(true); // NEW: Use ValueNotifier
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

  // --- ADDED ---
  // Selected Color Category ID
  String? selectedColorCategoryId;
  // --- END ADDED ---

  // --- ADDED for Other Categories ---
  List<String> selectedOtherCategoryIds = [];
  // --- END ADDED ---

  // Constructor can set initial values if needed
  // Set default category name
  ExperienceCardData() {
    // Initialize with "Restaurant" as the default category
    // selectedCategoryId = 'Restaurant'; // REMOVED: Defaulting logic moved to provider
    // selectedColorCategoryId will be null by default and should be set by the provider
    // based on SharedPreferences or "Want to go" default logic.
  }

  // Dispose resources
  void dispose() {
    // Dispose all controllers
    titleController.dispose();
    yelpUrlController.dispose();
    websiteController.dispose(); // Added
    searchController.dispose();
    locationController.dispose();
    notesController.dispose(); // Added

    // Dispose focus nodes
    titleFocusNode.dispose();
    // No need to explicitly handle selectedCategoryId in dispose,
    // as it is just a simple String? type and not a controller/listener.

    locationEnabled.dispose(); // NEW: Dispose the ValueNotifier
  }
}

class ReceiveShareScreen extends StatefulWidget {
  final List<SharedMediaFile> sharedFiles;
  final VoidCallback onCancel; // Callback to handle closing/canceling

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
  
  // Add flag to prevent double processing
  bool _isProcessingUpdate = false;
  // ADDED: AuthService instance
  final AuthService _authService = AuthService();
  // ADDED: GoogleKnowledgeGraphService instance with optional API key
  late final GoogleKnowledgeGraphService _knowledgeGraphService;

  // Add a field to track the current reload operation
  int _currentReloadOperationId = 0;

  // --- ADDED FOR SCROLLING FAB ---
  late ScrollController _scrollController;
  final GlobalKey _mediaPreviewListKey = GlobalKey(); // Key for the first media item/list itself
  final GlobalKey _experienceCardsSectionKey = GlobalKey();
  bool _showUpArrowForFab = false;
  bool _isInstagramPreviewExpanded = false;
  Map<String, GlobalKey> _instagramPreviewKeys = {}; // To store keys for active Instagram previews
  String? _currentVisibleInstagramUrl; // To track which Instagram preview is potentially visible
  // --- END ADDED FOR SCROLLING FAB ---

  // Track initialization state
  bool _isFullyInitialized = false;

  // Remove local experience card list - managed by Provider now
  // List<ExperienceCardData> _experienceCards = [];

  // Track filled business data to avoid duplicates but also cache results
  final Map<String, Map<String, dynamic>> _businessDataCache = {};

  // Form validation key - Now managed within the list of cards?
  // Consider if this should be per-card or one overall key.
  // For now, let's assume each ExperienceCardForm manages its own key.
  // final _formKey = GlobalKey<FormState>();

  // Loading state
  bool _isSaving = false;

  // Add a map to cache futures for Yelp preview data
  final Map<String, Future<Map<String, dynamic>?>> _yelpPreviewFutures = {};

  // Add a map to track TikTok photo carousel status
  final Map<String, bool> _tiktokPhotoStatus = {};

  // Method to show snackbar only if not already showing
  void _showSnackBar(BuildContext context, String message) {
    // Hide any existing snackbar first
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    // Show new snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 1), // Set duration to 1 second
      ),
    );
  }

  // Initialize with the files passed to the widget
  List<SharedMediaFile> _currentSharedFiles = [];

  // Flag to track if a chain was detected from URL structure
  bool _chainDetectedFromUrl = false;

  // RENAMED: State for user Categories
  Future<List<UserCategory>>? _userCategoriesFuture;
  List<UserCategory> _userCategories =
      []; // RENAMED Cache the loaded Categories

  // --- ADDED: State for user Color Categories ---
  Future<List<ColorCategory>>? _userColorCategoriesFuture;
  List<ColorCategory> _userColorCategories =
      []; // Cache the loaded ColorCategories
  // --- END ADDED ---

  // --- ADDED: Stable future for the FutureBuilder --- 
  Future<List<dynamic>>? _combinedCategoriesFuture;
  // --- END ADDED ---

  // --- ADDED: ValueNotifiers ---
  late ValueNotifier<List<UserCategory>> _userCategoriesNotifier;
  late ValueNotifier<List<ColorCategory>> _userColorCategoriesNotifier;
  // --- END ADDED ---

  SharedPreferences? _prefsInstance; // Store SharedPreferences instance

  @override
  void initState() {
    print("ReceiveShareScreen initState: START - Instance ${this.hashCode}");
    super.initState();
    // _sharingService.isShareFlowActive = true; // REMOVED: This is now set by SharingService.showReceiveShareScreen

    // --- ADDED FOR SCROLLING FAB ---
    _scrollController = ScrollController();
    _scrollController.addListener(_scrollListener);
    // --- END ADDED FOR SCROLLING FAB ---

    // Initialize with the files passed to the widget
    _currentSharedFiles = widget.sharedFiles;

    // Initialize Knowledge Graph service
    _initializeKnowledgeGraphService();

    // Register observer for app lifecycle events
    WidgetsBinding.instance.addObserver(this);

    // --- ADDED: Initialize ValueNotifiers ---
    _userCategoriesNotifier = ValueNotifier<List<UserCategory>>(_userCategories);
    _userColorCategoriesNotifier =
        ValueNotifier<List<ColorCategory>>(_userColorCategories);
    // --- END ADDED ---

    // IMPORTANT: Asynchronously load dependencies and then process content
    _initializeScreenDataAndProcessContent();

    // Listen for changes to the sharedFiles controller in SharingService
    _sharingService.sharedFiles.addListener(_handleSharedFilesUpdate);
    print("ReceiveShareScreen initState: END"); // ADDED
  }

  Future<void> _initializeScreenDataAndProcessContent() async {
    print("ReceiveShareScreen: _initializeScreenDataAndProcessContent START");
    // Load SharedPreferences
    _prefsInstance = await SharedPreferences.getInstance();
    print("ReceiveShareScreen: SharedPreferences loaded.");

    // Load categories (these methods update _userCategories, _userColorCategories, and their notifiers, and set the futures)
    // Await them to ensure data is available before setting provider deps
    try {
      await _loadUserCategories(); // This already handles setting _userCategoriesFuture and updating _userCategories
      print("ReceiveShareScreen: User categories loaded/updated via _loadUserCategories. Count: ${_userCategories.length}");
      await _loadUserColorCategories(); // This already handles setting _userColorCategoriesFuture and updating _userColorCategories
      print("ReceiveShareScreen: User color categories loaded/updated via _loadUserColorCategories. Count: ${_userColorCategories.length}");
    } catch (e) {
        print("ReceiveShareScreen: Error loading categories in _initializeScreenDataAndProcessContent: $e");
        // Ensure lists are at least empty for the provider if loading failed
        if (mounted) {
          _userCategories = [];
          _userCategoriesNotifier.value = [];
          _userColorCategories = [];
          _userColorCategoriesNotifier.value = [];
        }
    }
    
    if (mounted) {
      // Set dependencies on the provider
      // This assumes your ReceiveShareProvider has a method like `setDependencies`
      try {
        final provider = context.read<ReceiveShareProvider>();
        await provider.setDependencies( // This method needs to be defined in ReceiveShareProvider
          prefs: _prefsInstance!,
          userCategories: _userCategories, 
          userColorCategories: _userColorCategories,
        );
        print("ReceiveShareScreen: Called provider.setDependencies with: Prefs, ${_userCategories.length} UserCategories, ${_userColorCategories.length} ColorCategories");
        // TODO: Remove the line below once setDependencies in ReceiveShareProvider is confirmed implemented
        // print("ReceiveShareProvider DEPS COMMENTED OUT: Call provider.setDependencies here with: Prefs, ${_userCategories.length} UserCategories, ${_userColorCategories.length} ColorCategories");
        
      } catch (e) {
        print("ReceiveShareScreen: Error during provider.setDependencies call: $e");
      }
      
      // Initialize the combined future for the FutureBuilder in build()
      // This must be called after _userCategoriesFuture and _userColorCategoriesFuture are (re)set by the _load methods
      _initializeCombinedFuture();
      print("ReceiveShareScreen: Combined future initialized.");

      // Now it's safe to process initial shared content,
      // as the provider (conceptually) has what it needs for default categories.
      print("ReceiveShareScreen: Processing initial shared content.");
      _processInitialSharedContent(_currentSharedFiles);
      
      // Mark as fully initialized
      _isFullyInitialized = true;
      print("ReceiveShareScreen: Marked as fully initialized");
    }
    print("ReceiveShareScreen: _initializeScreenDataAndProcessContent END");
  }

  // Handle updates to the sharedFiles controller from SharingService
  void _handleSharedFilesUpdate() {
    if (_isProcessingUpdate) {
      Fluttertoast.showToast(
        msg: "DEBUG: Already processing update, ignoring",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.grey.withOpacity(0.8),
        textColor: Colors.white,
      );
      return;
    }
    
    final updatedFiles = _sharingService.sharedFiles.value;
    if (updatedFiles != null && 
        updatedFiles.isNotEmpty && 
        !_areSharedFilesEqual(updatedFiles, _currentSharedFiles)) {
      
      _isProcessingUpdate = true;
      
      print("ReceiveShareScreen: Received updated shared files. Processing...");
      print("ReceiveShareScreen: Is fully initialized: $_isFullyInitialized");
      print("ReceiveShareScreen: Current files: ${_currentSharedFiles?.map((f) => f.path.substring(0, min(50, f.path.length))).join(", ") ?? "null"}");
      print("ReceiveShareScreen: Updated files: ${updatedFiles.map((f) => f.path.substring(0, min(50, f.path.length))).join(", ")}");
      
      Fluttertoast.showToast(
        msg: "DEBUG: _handleSharedFilesUpdate called",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.yellow.withOpacity(0.8),
        textColor: Colors.black,
      );
      
      // Check if this is a Yelp URL - if so, treat as update rather than full refresh
      String? yelpUrl = _extractYelpUrlFromSharedFiles(updatedFiles);
      if (yelpUrl != null) {
        print("ReceiveShareScreen: Yelp URL detected - treating as update rather than full refresh");
        Fluttertoast.showToast(
          msg: "DEBUG: Yelp URL in _handleSharedFilesUpdate - routing to update",
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.teal.withOpacity(0.8),
          textColor: Colors.white,
        );
        // For Yelp URLs, always try to update existing cards instead of creating new content
        _handleYelpUrlUpdate(yelpUrl, updatedFiles);
        
        // Reset flag after a delay to allow for future updates
        Future.delayed(const Duration(milliseconds: 1000), () {
          _isProcessingUpdate = false;
        });
        return;
      }
      
      // If not fully initialized yet, wait for initialization to complete
      if (!_isFullyInitialized) {
        print("ReceiveShareScreen: Screen not fully initialized yet. Deferring share update.");
        // Defer the update until after initialization
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _isFullyInitialized) {
            _handleSharedFilesUpdate();
          }
        });
        return;
      }
      
      // Check if this update is essentially the same as what we just processed during initialization
      // This prevents double-processing during cold starts
      if (_areSharedFilesEqual(updatedFiles, widget.sharedFiles)) {
        print("ReceiveShareScreen: Updated files are same as initial widget.sharedFiles. Likely initialization echo - ignoring.");
        _isProcessingUpdate = false;
        return;
      }
      
      // Check if this is a Yelp URL that should be added to existing card (reuse yelpUrl from above)
      if (yelpUrl != null && _hasExistingCards()) {
        print("ReceiveShareScreen: Detected Yelp URL with existing cards. Updating in-place.");
        _handleYelpUrlUpdate(yelpUrl, updatedFiles);
        _isProcessingUpdate = false;
        return;
      }
      
      // If not a Yelp URL or no existing cards, proceed with normal reset logic
      print("ReceiveShareScreen: Not a Yelp URL or no existing cards. Resetting.");
      final provider = context.read<ReceiveShareProvider>();
      provider.resetExperienceCards();
      
      setState(() {
        _currentSharedFiles = updatedFiles;
        _businessDataCache.clear();
        _yelpPreviewFutures.clear();
      });
      
      // Process the new content
      _processSharedContent(_currentSharedFiles);
      _isProcessingUpdate = false;
    }
  }
  
  // Helper method to compare shared files lists
  bool _areSharedFilesEqual(List<SharedMediaFile> a, List<SharedMediaFile> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].path != b[i].path) return false;
    }
    return true;
  }

  // Check if there are existing experience cards
  bool _hasExistingCards() {
    final provider = context.read<ReceiveShareProvider>();
    return provider.experienceCards.isNotEmpty;
  }

  // Extract Yelp URL from shared files
  String? _extractYelpUrlFromSharedFiles(List<SharedMediaFile> files) {
    for (final file in files) {
      if (file.type == SharedMediaType.text || file.type == SharedMediaType.url) {
        String? url = _extractFirstUrl(file.path);
        if (url != null && _isYelpUrl(url)) {
          return url;
        }
      }
    }
    return null;
  }

  // Check if a URL is a Yelp URL
  bool _isYelpUrl(String url) {
    String urlLower = url.toLowerCase();
    return urlLower.contains('yelp.com/biz') || urlLower.contains('yelp.to/');
  }

  // Track which card's Yelp button was last tapped
  String? _lastYelpButtonTappedCardId;

  // Handle updating an existing card with a new Yelp URL
  void _handleYelpUrlUpdate(String yelpUrl, List<SharedMediaFile> updatedFiles) {
    final provider = context.read<ReceiveShareProvider>();
    final experienceCards = provider.experienceCards;
    
    Fluttertoast.showToast(
      msg: "DEBUG: _handleYelpUrlUpdate called, cards=${experienceCards.length}",
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.CENTER,
      backgroundColor: Colors.red.withOpacity(0.8),
      textColor: Colors.white,
    );
    
    if (experienceCards.isEmpty) {
      print("ReceiveShareScreen: No experience cards yet for Yelp URL update - will retry in 500ms");
      Fluttertoast.showToast(
        msg: "DEBUG: No cards yet, retrying in 500ms",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.CENTER,
        backgroundColor: Colors.grey.withOpacity(0.8),
        textColor: Colors.white,
      );
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _handleYelpUrlUpdate(yelpUrl, updatedFiles);
        }
      });
      return;
    }
    
    // Find the target card to populate with the Yelp URL
    ExperienceCardData? targetCard;
    
    // First priority: If user recently tapped a Yelp button, update that card
    if (_lastYelpButtonTappedCardId != null) {
      try {
        targetCard = experienceCards.firstWhere(
          (card) => card.id == _lastYelpButtonTappedCardId
        );
        print("ReceiveShareScreen: Prioritizing card ${targetCard.id} that recently opened Yelp");
        // Clear the tracking after use
        _lastYelpButtonTappedCardId = null;
      } catch (e) {
        // Card not found, fall back to other logic
        _lastYelpButtonTappedCardId = null;
      }
    }
    
    // Second priority: Use the bottom-most (last) experience card
    targetCard ??= experienceCards.last;
    
    // Normalize the URL
    String normalizedUrl = yelpUrl.trim();
    if (!normalizedUrl.startsWith('http')) {
      normalizedUrl = 'https://$normalizedUrl';
    }
    
    // Update the card with the Yelp URL (replace existing if present)
    final previousUrl = targetCard.yelpUrlController.text;
    targetCard.yelpUrlController.text = normalizedUrl;
    
    // No notifications needed - the TextEditingController will handle its own listeners
    // This prevents any rebuilds of the page or provider listeners
    Fluttertoast.showToast(
        msg: "Yelp URL added",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        timeInSecForIosWeb: 1,
        backgroundColor: Colors.black.withOpacity(0.7),
        textColor: Colors.white,
        fontSize: 16.0
    );
    
    if (previousUrl.isNotEmpty) {
      print("ReceiveShareScreen: Replaced Yelp URL in card ${targetCard.id}: '$previousUrl' -> '$normalizedUrl'");
    } else {
      print("ReceiveShareScreen: Added Yelp URL to card ${targetCard.id}: '$normalizedUrl'");
    }

    // DON'T update _currentSharedFiles for Yelp URLs - we want to preserve the original preview
    // Only the Yelp URL field should be updated, not the shared files or preview content
  }

  // Method to track when a Yelp button is tapped
  void _trackYelpButtonTapped(String cardId) {
    _lastYelpButtonTappedCardId = cardId;
    print("ReceiveShareScreen: Tracked Yelp button tap for card: $cardId");
    
    // Inform SharingService that we're temporarily leaving for external app
    // This preserves the share flow state instead of resetting it
    _sharingService.temporarilyLeavingForExternalApp();
  }

  Future<void> _loadUserCategories() async {
    try {
      final Categories = await _experienceService.getUserCategories();
      if (mounted) {
        _userCategories = Categories;
        _userCategoriesNotifier.value = Categories;
        _updateCardDefaultCategoriesIfNeeded(Categories);
      }
      _userCategoriesFuture = Future.value(Categories); // Ensure future resolves to the fetched list
    } catch (error) {
      print("ReceiveShareScreen: Error loading user Categories: $error");
      if (mounted) {
        _userCategories = [];
        _userCategoriesNotifier.value = [];
      }
      _userCategoriesFuture = Future.value([]); // Ensure future resolves to an empty list on error
    }
  }

  void _updateCardDefaultCategoriesIfNeeded(
      List<UserCategory> loadedCategories) {
    final provider = context.read<ReceiveShareProvider>();
    if (provider.experienceCards.isEmpty || loadedCategories.isEmpty) return;

    // MODIFIED: Default to the ID of the first loaded category
    final firstLoadedCategoryId = loadedCategories.first.id; 

    for (var card in provider.experienceCards) {
      // MODIFIED: Check if the card's selectedCategoryId is valid within the loadedCategories
      if (!loadedCategories.any((c) => c.id == card.selectedCategoryId)) {
        card.selectedCategoryId = firstLoadedCategoryId;
      }
    }
  }

  Future<void> _refreshUserCategoriesFromDialog() {
    print("_refreshUserCategoriesFromDialog START");
    return _experienceService.getUserCategories().then((categories) {
      if (mounted) {
        _userCategories = categories; 
        _userCategoriesNotifier.value = categories; 
        _updateCardDefaultCategoriesIfNeeded(categories); 
        print(
            "  _refreshUserCategoriesFromDialog: Notifier updated with ${categories.length} categories.");
      }
    }).catchError((error) {
      print("Error refreshing user Categories from dialog: $error");
      if (mounted) {
        _userCategories = [];
        _userCategoriesNotifier.value = [];
      }
    });
  }

  Future<void> _refreshUserColorCategoriesFromDialog() {
    print("_refreshUserColorCategoriesFromDialog START");
    return _experienceService.getUserColorCategories().then((colorCategories) {
      if (mounted) {
        _userColorCategories = colorCategories; 
        _userColorCategoriesNotifier.value =
            colorCategories; 
        print(
            "  _refreshUserColorCategoriesFromDialog: Notifier updated with ${colorCategories.length} color categories.");
      }
    }).catchError((error) {
      print("Error refreshing user Color Categories from dialog: $error");
      if (mounted) {
        _userColorCategories = [];
        _userColorCategoriesNotifier.value = [];
      }
    });
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    print("SHARE DEBUG: App lifecycle state changed to $state");

    if (state == AppLifecycleState.resumed) {
      print("SHARE DEBUG: App resumed"); // Simplified log
      _conditionallyReloadCategories(); 
    }
  }

  Future<void> _conditionallyReloadCategories() async {
    // Exit early if the widget is no longer mounted (ensures no operations start on unmounted widget)
    if (!mounted) return;

    // Store the current instance as a variable to track if this operation should continue
    final int operationId = DateTime.now().millisecondsSinceEpoch;
    // Update the class member to track this operation
    _currentReloadOperationId = operationId;

    bool categoriesChanged = false;
    bool colorCategoriesChanged = false;
    bool needsSetState = false;

    List<UserCategory>? newCategoriesData;
    List<ColorCategory>? newColorCategoriesData;

    // Helper function to check if this operation should continue
    bool shouldContinue() {
      // If the widget is unmounted or a newer reload operation was started, abort
      return mounted && _currentReloadOperationId == operationId;
    }

    try {
      final fetchedCategories = await _experienceService.getUserCategories();
      // Check if we should continue after the async operation
      if (!shouldContinue()) return;

      if (!const DeepCollectionEquality().equals(fetchedCategories, _userCategories)) {
        newCategoriesData = fetchedCategories;
        categoriesChanged = true;
      }
    } catch (error) {
      print("Error reloading user categories on resume: $error");
      if (shouldContinue()) {
        newCategoriesData = []; 
        categoriesChanged = true; 
      }
    }

    try {
      final fetchedColorCategories = await _experienceService.getUserColorCategories();
      // Check if we should continue after the async operation
      if (!shouldContinue()) return;

      if (!const DeepCollectionEquality().equals(fetchedColorCategories, _userColorCategories)) {
        newColorCategoriesData = fetchedColorCategories;
        colorCategoriesChanged = true;
      }
    } catch (error) {
      print("Error reloading user color categories on resume: $error");
      if (shouldContinue()) {
        newColorCategoriesData = []; 
        colorCategoriesChanged = true; 
      }
    }

    // Final check before updating state
    if (!shouldContinue()) return;

    if (categoriesChanged) {
      _userCategories = newCategoriesData!;
      _userCategoriesNotifier.value = _userCategories;
      if (newCategoriesData.isNotEmpty) { 
        _updateCardDefaultCategoriesIfNeeded(_userCategories);
      }
      needsSetState = true;
    }
    if (colorCategoriesChanged) {
      _userColorCategories = newColorCategoriesData!;
      _userColorCategoriesNotifier.value = _userColorCategories;
      needsSetState = true;
    }

    if (needsSetState) {
      // One final check before trying to setState
      if (!shouldContinue()) return;
      
      setState(() {
        // Update futures to reflect the new (or error) state for FutureBuilder
        // This ensures FutureBuilder gets a new future instance and rebuilds.
        _userCategoriesFuture = Future.value(_userCategories);
        _userColorCategoriesFuture = Future.value(_userColorCategories);
        _initializeCombinedFuture(); // Re-initialize combined future
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // print("SHARE DEBUG: didChangeDependencies called"); // CLEANED
    // Intent listener setup is now handled by SharingService
  }

  void _initializeKnowledgeGraphService() {
    try {
      // Try to get API key from ApiSecrets
      // ignore: undefined_class, undefined_getter
      String? apiKey = ApiSecrets.googleKnowledgeGraphApiKey;
      _knowledgeGraphService = GoogleKnowledgeGraphService(apiKey: apiKey);
      print('🔍 KNOWLEDGE GRAPH: Service initialized with API key: ${apiKey != null && apiKey.isNotEmpty ? 'configured' : 'not configured'}');
    } catch (e) {
      // ApiSecrets not available, initialize without API key
      _knowledgeGraphService = GoogleKnowledgeGraphService();
      print('🔍 KNOWLEDGE GRAPH: Service initialized without API key (ApiSecrets not found)');
    }
  }

  @override
  void dispose() {
    print("ReceiveShareScreen dispose: START - Instance ${this.hashCode}");
    // If _saveExperience initiated navigation, prepareToNavigateAwayFromShare already handled things.
    // This call to markShareFlowAsInactive is mainly for cases where dispose is called due to
    // other reasons (like system back if not fully handled, or unexpected unmount).
    // However, if _navigatingAwayFromShare is true, we might not want to call markShareFlowAsInactive again here
    // as it calls resetSharedItems again. Let's rely on onCancel and onWillPop for explicit user exits.
    // The SharingService's shareNavigationComplete (called by MainScreen) will reset _navigatingAwayFromShare.
    // If _sharingService.isNavigatingAwayFromShare is false, then it means we are disposing due to a non-save exit.
    if (!_sharingService.isNavigatingAwayFromShare) { // MODIFIED to use getter
        _sharingService.markShareFlowAsInactive();
    }
    _currentReloadOperationId = -1;
    _isFullyInitialized = false; // Reset initialization flag
    WidgetsBinding.instance.removeObserver(this);
    _sharingService.sharedFiles.removeListener(_handleSharedFilesUpdate);
    // Removed direct call to ReceiveSharingIntent.instance.reset() from here,
    // it's now part of _sharingService.resetSharedItems()
    _userCategoriesNotifier.dispose();
    _userColorCategoriesNotifier.dispose();
    super.dispose();
  }

  Widget _wrapWithWillPopScope(Widget child) {
    return WillPopScope(
      onWillPop: () async {
        print("ReceiveShareScreen: WillPopScope triggered (system back).");
        _sharingService.markShareFlowAsInactive(); 
        if (mounted) { 
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const MainScreen()),
            (Route<dynamic> route) => false, 
          );
        }
        return false; 
      },
      child: child,
    );
  }

  String? _extractFirstUrl(String text) {
    if (text.isEmpty) return null;
    final RegExp urlRegex = RegExp(
        r"(?:(?:https?|ftp):\/\/|www\.)[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)",
        caseSensitive: false);
    final match = urlRegex.firstMatch(text);
    return match?.group(0);
  }

  // Process initial shared content on cold start - behaves like warm start logic
  void _processInitialSharedContent(List<SharedMediaFile> files) {
    print("ReceiveShareScreen: _processInitialSharedContent called with ${files.length} files");
    
    if (files.isEmpty) {
      print("ReceiveShareScreen: No initial shared files to process");
      return;
    }

    // Check if this is a Yelp URL and add debug toast
    String? yelpUrl = _extractYelpUrlFromSharedFiles(files);
    if (yelpUrl != null) {
      Fluttertoast.showToast(
        msg: "DEBUG: Initial processing Yelp URL",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.TOP,
        backgroundColor: Colors.purple.withOpacity(0.8),
        textColor: Colors.white,
      );
    }

    // For all content, always use normal processing
    // The Yelp URL handling complexity was causing more issues than it solved
    setState(() {
      _currentSharedFiles = files;
    });
    print("ReceiveShareScreen: Set _currentSharedFiles to prevent double-processing from SharingService listener");
    _processSharedContent(files);
  }

  void _processSharedContent(List<SharedMediaFile> files) {
    // print('🔄 PROCESSING START: _processSharedContent called with ${files.length} files.'); // CLEANED
    // print('DEBUG: Processing shared content'); // CLEANED
    if (files.isEmpty) {
      // print('🔄 PROCESSING END: No files to process.'); // CLEANED
      return;
    }

    final fileFirst = files.first; 
    // print('🔄 PROCESSING DETAIL: First file type: ${fileFirst.type}, path: ${fileFirst.path.substring(0, min(100, fileFirst.path.length))}...'); // CLEANED

    String? foundUrl;
    for (final file in files) {
      if (file.type == SharedMediaType.text ||
          file.type == SharedMediaType.url) {
        String text = file.path;
        // print('DEBUG: Checking shared text: ${text.substring(0, min(100, text.length))}...'); // CLEANED
        foundUrl = _extractFirstUrl(text);
        if (foundUrl != null) {
          // print('DEBUG: Extracted first URL: $foundUrl'); // CLEANED
          if (_isSpecialUrl(foundUrl)) {
            // print('DEBUG: Found special content URL: $foundUrl'); // CLEANED
            
            // SPECIAL CASE: If this is a Yelp URL and we already have cards, treat it as an update
            String? yelpUrl = _extractYelpUrlFromSharedFiles(files);
            if (yelpUrl != null) {
              final provider = context.read<ReceiveShareProvider>();
              
              // Check if sharing service indicates this should be an update (from existing session)
              bool hasActiveShareFlow = _sharingService.isShareFlowActive;
              bool hasPersistedContent = false;
              
              // Quick async check for persisted content
              _sharingService.getPersistedOriginalContent().then((content) {
                hasPersistedContent = content != null && content.isNotEmpty;
              });
              
              Fluttertoast.showToast(
                msg: "DEBUG: Yelp in _processSharedContent, cards=${provider.experienceCards.length}, shareFlow=$hasActiveShareFlow",
                toastLength: Toast.LENGTH_LONG,
                gravity: ToastGravity.CENTER,
                backgroundColor: Colors.blue.withOpacity(0.8),
                textColor: Colors.white,
              );
              
              // If we have existing cards OR there's evidence of a previous session, treat as update
              if (provider.experienceCards.isNotEmpty || hasActiveShareFlow) {
                print("ReceiveShareScreen: Yelp URL detected with existing cards or active session - updating instead of creating new preview");
                Fluttertoast.showToast(
                  msg: "DEBUG: Updating existing card with Yelp URL (cards=${provider.experienceCards.length})",
                  toastLength: Toast.LENGTH_LONG,
                  gravity: ToastGravity.CENTER,
                  backgroundColor: Colors.green.withOpacity(0.8),
                  textColor: Colors.white,
                );
                _handleYelpUrlUpdate(yelpUrl, files);
                return;
              } else {
                Fluttertoast.showToast(
                  msg: "DEBUG: No existing cards or session, creating new Yelp preview",
                  toastLength: Toast.LENGTH_LONG,
                  gravity: ToastGravity.CENTER,
                  backgroundColor: Colors.orange.withOpacity(0.8),
                  textColor: Colors.white,
                );
              }
            }
            
            _processSpecialUrl(
                foundUrl, file); 
            return; 
          } else {
            // print('DEBUG: Extracted URL is not a special Yelp/Maps URL, ignoring.'); // CLEANED
          }
        }
      }
    }

    if (foundUrl == null) {
      // print('DEBUG: No processable URL found in any shared text/URL files.'); // CLEANED
    } else {
      // print('DEBUG: Found a URL ($foundUrl), but it was not a Yelp or Maps URL.'); // CLEANED
    }
  }

  bool _isSpecialUrl(String url) {
    if (url.isEmpty) return false;
    String urlLower = url.toLowerCase();

    final yelpPattern = RegExp(r'yelp\.(com/biz|to)/');
    final mapsPattern =
        RegExp(r'(google\.com/maps|maps\.app\.goo\.gl|goo\.gl/maps)');
    final facebookPattern = RegExp(r'(facebook\.com|fb\.com|fb\.watch)');
    final googleKnowledgePattern = RegExp(r'g\.co/kgs/'); // Added pattern for Google Knowledge Graph URLs
    final shareGooglePattern = RegExp(r'share\.google/'); // Added pattern for share.google URLs

    if (yelpPattern.hasMatch(urlLower) || 
        mapsPattern.hasMatch(urlLower) || 
        facebookPattern.hasMatch(urlLower) ||
        googleKnowledgePattern.hasMatch(urlLower) ||
        shareGooglePattern.hasMatch(urlLower)) {
      print("DEBUG: _isSpecialUrl detected special pattern in URL: $url");
      return true;
    }

    print(
        "DEBUG: _isSpecialUrl did not find special pattern in URL: $url");
    return false;
  }

  void _processSpecialUrl(String url, SharedMediaFile file) {
    print('🔄 PROCESSING START: _processSpecialUrl called with URL: $url');
    final provider = context.read<ReceiveShareProvider>();
    if (provider.experienceCards.isEmpty) {
      print("DEBUG: Adding initial experience card before processing URL.");
      provider.addExperienceCard();
    }
    final firstCard = provider.experienceCards.first;

    String normalizedUrl = url.trim();
    if (!normalizedUrl.startsWith('http')) {
      normalizedUrl = 'https://$normalizedUrl';
    }

    if (normalizedUrl.contains('yelp.com/biz') ||
        normalizedUrl.contains('yelp.to/')) {
      print("SHARE DEBUG: Processing as Yelp URL: $normalizedUrl");
      firstCard.originalShareType = ShareType.yelp; 
      firstCard.yelpUrlController.text =
          normalizedUrl; 
      _yelpPreviewFutures[normalizedUrl] = _getBusinessFromYelpUrl(
        normalizedUrl,
        sharedText: file.path, 
      );
    } else if (normalizedUrl.contains('google.com/maps') ||
        normalizedUrl.contains('maps.app.goo.gl') ||
        normalizedUrl.contains('goo.gl/maps')) {
      print("SHARE DEBUG: Processing as Google Maps URL: $normalizedUrl");
      firstCard.originalShareType = ShareType.maps; 
      _yelpPreviewFutures[normalizedUrl] =
          _getLocationFromMapsUrl(normalizedUrl);
    } else if (normalizedUrl.contains('g.co/kgs/') || normalizedUrl.contains('share.google/')) {
      print("SHARE DEBUG: Processing as Google Knowledge Graph URL (showing web preview): $normalizedUrl");
      // Google Knowledge Graph URLs are displayed as web previews using GenericUrlPreviewWidget
      firstCard.originalShareType = ShareType.genericUrl;
      // The URL will be displayed in the media preview section using AnyLinkPreview
    } else if (normalizedUrl.contains('facebook.com') ||
               normalizedUrl.contains('fb.com') ||
               normalizedUrl.contains('fb.watch')) {
      print("SHARE DEBUG: Processing as Facebook URL: $normalizedUrl");
      // Facebook URLs are handled differently - they're displayed in the preview
      // but don't extract location data like Yelp/Maps
      firstCard.originalShareType = ShareType.genericUrl;
      // The URL will be displayed in the media preview section
    } else {
      print("ERROR: _processSpecialUrl called with non-special URL: $url");
    }
  }

  Future<void> _processGoogleMapsUrl(String url) async {
    try {
      setState(() {
      });

      final mapData = await _getLocationFromMapsUrl(url);

      if (mapData != null && mapData['location'] != null) {
        final location = mapData['location'] as Location;
        final placeName = mapData['placeName'] as String? ?? 'Shared Location';
        final websiteUrl = mapData['website'] as String? ?? '';

        _fillFormWithGoogleMapsData(location, placeName, websiteUrl, url);
      } else {
        print('🗺️ MAPS ERROR: Failed to extract location data from URL');
        _showSnackBar(
            context, 'Could not extract location data from the shared URL');
      }
    } catch (e) {
      print('🗺️ MAPS ERROR: Error processing Maps URL: $e');
      _showSnackBar(context, 'Error processing Google Maps URL');
    }
  }

  void _addExperienceCard() {
    print("ReceiveShareScreen: _addExperienceCard method called."); // ADDED
    context.read<ReceiveShareProvider>().addExperienceCard();
  }

  void _removeExperienceCard(ExperienceCardData card) {
    context.read<ReceiveShareProvider>().removeExperienceCard(card);
    if (context.read<ReceiveShareProvider>().experienceCards.isEmpty) {
      context.read<ReceiveShareProvider>().addExperienceCard();
    }
  }

  Future<Map<String, dynamic>?> _getBusinessFromYelpUrl(String yelpUrl,
      {String? sharedText}) async {
    print(
        '🔄 GET YELP START: _getBusinessFromYelpUrl called for URL: $yelpUrl');
    if (sharedText != null) {
      print(
          '🔄 GET YELP START: Shared text provided (${sharedText.length} chars): ${sharedText.substring(0, min(100, sharedText.length))}${sharedText.length > 100 ? "..." : ""}');
    } else {
      print(
          '🔄 GET YELP START: No shared text provided (likely called from preview).');
    }
    print("\n📊 YELP DATA: Starting business lookup for URL: $yelpUrl");

    _chainDetectedFromUrl = false;

    final cacheKey = yelpUrl.trim();

    if (_businessDataCache.containsKey(cacheKey)) {
      print(
          '📊 YELP DATA: URL $cacheKey already processed, returning cached data');
      final cachedData = _businessDataCache[cacheKey];
      print(
          '📊 YELP DATA: Cache hit! Data: ${cachedData != null && cachedData.isNotEmpty ? "Has business data" : "Empty map (no results)"}');
      return _businessDataCache[cacheKey];
    }

    String url = yelpUrl.trim();

    if (url.isEmpty) {
      print('📊 YELP DATA: Empty URL, aborting');
      return null;
    } else if (!url.startsWith('http')) {
      url = 'https://$url';
      print('📊 YELP DATA: Added https:// to URL: $url');
    }

    bool isYelpUrl = url.contains('yelp.com') || url.contains('yelp.to');
    if (!isYelpUrl) {
      print('📊 YELP DATA: Not a Yelp URL, aborting: $url');
      return null;
    }

    print('📊 YELP DATA: Processing Yelp URL: $url');

    try {
      String businessName = "";
      String businessAddress = "";
      String businessCity = "";
      String businessState = "";
      String businessZip = "";
      String businessType = "";
      bool isShortUrl = url.contains('yelp.to/');

      Position? userPosition = await _getCurrentPosition();

      if (isShortUrl) {
        print('📊 YELP DATA: Detected shortened URL, attempting to resolve it');
        try {
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
                '📊 YELP DATA: Could not resolve shortened URL or resolved URL is not a /biz/ link.');
          }
        } catch (e) {
          print('📊 YELP DATA: Error resolving shortened URL: $e');
        }
      }

      bool extractedFromUrl = false;
      bool extractedFromSharedText = false;
      
      // First, try to extract business name from shared text if available
      if (sharedText != null) {
        print(
            '📊 YELP DATA: Attempting name extraction from shared text first.');
        try {
          // Look for any Yelp URL pattern in the shared text (yelp.com or yelp.to)
          RegExp yelpUrlPattern = RegExp(r'https?://(?:www\.)?yelp\.(?:com|to)/[^\s]+');
          Match? urlMatch = yelpUrlPattern.firstMatch(sharedText);
          
          int urlIndex = -1;
          if (urlMatch != null) {
            urlIndex = urlMatch.start;
            print('📊 YELP DATA: Found Yelp URL pattern at index $urlIndex');
          } else {
            // Fallback: look for the exact URL we received
            urlIndex = sharedText.indexOf(yelpUrl);
            if (urlIndex != -1) {
              print('📊 YELP DATA: Found exact URL match at index $urlIndex');
            }
          }
          
          if (urlIndex != -1) {
            String potentialName = sharedText.substring(0, urlIndex).trim();
            
            // Clean up common prefixes and suffixes
            potentialName = potentialName.replaceAll(
                RegExp(r'^Check out ', caseSensitive: false), '');
            potentialName = potentialName.replaceAll(
                RegExp(r'^See ', caseSensitive: false), '');
            potentialName = potentialName.replaceAll(
                RegExp(r'^Visit ', caseSensitive: false), '');
            potentialName = potentialName.replaceAll(
                RegExp(r'!+$'), ''); // Remove trailing exclamation marks
            potentialName = potentialName.replaceAll(
                RegExp(r'\s*\n.*$', multiLine: true),
                ''); // Remove everything after newline
            potentialName = potentialName.trim();

            if (potentialName.isNotEmpty && potentialName.length < 100) {
              businessName = potentialName;
              extractedFromSharedText = true;
              extractedFromUrl = true; // Mark as extracted so we don't use generic name
              print(
                  '📊 YELP DATA: Successfully extracted business name from shared text: "$businessName"');
            } else {
              print(
                  '📊 YELP DATA: Failed to extract meaningful name from text preceding URL.');
            }
          } else {
            print(
                '📊 YELP DATA: Could not find any Yelp URL within the shared text to extract preceding name.');
          }
        } catch (e) {
          print('📊 YELP DATA: Error during shared text name extraction: $e');
        }
      }
      
      // Only try URL parsing if we didn't get a good name from shared text
      if (!extractedFromSharedText && url.contains('/biz/')) {
        final bizPath = url.split('/biz/')[1].split('?')[0];
        print('📊 YELP DATA: Extracting from biz URL path: $bizPath');

        bool isChainFromUrl = false;
        final lastPathSegment = bizPath.split('/').last;
        final RegExp numericSuffixRegex = RegExp(r'-(\d+)$');
        final match = numericSuffixRegex.firstMatch(lastPathSegment);
        if (match != null) {
          print(
              '📊 YELP DATA: Detected numeric suffix in URL path, indicating a chain location: ${match.group(1)}');
          isChainFromUrl = true;
        }

        List<String> pathParts = bizPath.split('-');

        if (pathParts.isNotEmpty && RegExp(r'^\d+$').hasMatch(pathParts.last)) {
          print(
              '📊 YELP DATA: Removing numeric suffix ${pathParts.last} from business name');
          pathParts.removeLast();
          isChainFromUrl = true;
        }

        int cityStartIndex = -1;
        List<String> states = [
          "al", "ak", "az", "ar", "ca", "co", "ct", "de", "fl", "ga",
          "hi", "id", "il", "in", "ia", "ks", "ky", "la", "me", "md",
          "ma", "mi", "mn", "ms", "mo", "mt", "ne", "nv", "nh", "nj",
          "nm", "ny", "nc", "nd", "oh", "ok", "or", "pa", "ri", "sc",
          "sd", "tn", "tx", "ut", "vt", "va", "wa", "wv", "wi", "wy"
        ];

        for (int i = pathParts.length - 1; i >= 0; i--) {
          if (states.contains(pathParts[i].toLowerCase()) ||
              ["city", "town", "village"]
                  .contains(pathParts[i].toLowerCase())) {
            if (i > 0) {
              cityStartIndex =
                  i - 1; 
              break;
            }
          }
          if (i == pathParts.length - 1 &&
              pathParts[i].length > 2 &&
              !isChainFromUrl) {
            final possibleCity = pathParts.last;
            final nonCityWords = [
              'restaurant', 'pizza', 'cafe', 'bar', 'grill',
              'and', 'the', 'co', 'inc'
            ];
            bool mightBeCity =
                !nonCityWords.contains(possibleCity.toLowerCase());
            if (mightBeCity) {
              cityStartIndex = i; 
              break;
            }
          }
        }

        if (cityStartIndex != -1 && cityStartIndex < pathParts.length) {
          businessCity = pathParts.sublist(cityStartIndex).join(' ');
          businessCity = businessCity
              .split(' ')
              .map((word) => word.isNotEmpty
                  ? word[0].toUpperCase() + word.substring(1)
                  : '')
              .join(' ');
          print('📊 YELP DATA: Extracted city from URL path: $businessCity');
          businessName = pathParts.sublist(0, cityStartIndex).join(' ');
        } else {
          businessName = pathParts.join(' ');
          print(
              '📊 YELP DATA: Could not reliably extract city, using full path as name basis: $businessName');
        }

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
            true; 
      }


      bool isChainOrGeneric = _chainDetectedFromUrl;
      if (!isChainOrGeneric && businessName.isNotEmpty) {
        final chainTerms = [
          'restaurant', 'cafe', 'pizza', 'coffee',
          'bar', 'grill', 'bakery'
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

      // Try web scraping for additional details if we have a short URL or need more info
      if (isShortUrl || (!extractedFromSharedText && businessName.isEmpty)) {
        print(
            '📊 YELP DATA: Attempting web scraping for additional details');
        try {
          final extraInfo = await _getLocationDetailsFromYelpPage(yelpUrl);
          if (extraInfo != null) {
            if (businessCity.isEmpty &&
                extraInfo['city'] != null &&
                extraInfo['city']!.isNotEmpty) {
              businessCity = extraInfo['city']!;
              print(
                  '📊 YELP DATA: Extracted city from Yelp page scrape: $businessCity');
            }
            if (extraInfo['state'] != null && extraInfo['state']!.isNotEmpty) {
              businessState = extraInfo['state']!;
              print(
                  '📊 YELP DATA: Extracted state from Yelp page scrape: $businessState');
            }
            // Try to extract business name from scraped page if we still don't have it
            if (businessName.isEmpty && extraInfo['businessName'] != null && extraInfo['businessName']!.isNotEmpty) {
              businessName = extraInfo['businessName']!;
              extractedFromUrl = true;
              print(
                  '📊 YELP DATA: Extracted business name from Yelp page scrape: $businessName');
            }
          }
        } catch (e) {
          print(
              '📊 YELP DATA: Error fetching details from Yelp page scrape: $e');
        }
      }

      if (businessName.isEmpty) {
        businessName = "Shared Business";
        print('📊 YELP DATA: Using generic business name');
      }

      List<String> searchQueries = [];
      
      // Prioritize exact business name searches when we have good data from shared text
      if (businessName.isNotEmpty) {
        // Add exact quoted search first (most precise)
        searchQueries.add('"$businessName"');
        
        // Add business name with city if available
        if (businessCity.isNotEmpty) {
          String query = '$businessName $businessCity';
          searchQueries.add('"$query"');
          searchQueries.add(query);
        }
        
        // Add plain business name search (less precise but broader)
        searchQueries.add(businessName);
      }
      
      // Remove duplicates while preserving order
      searchQueries = searchQueries.toSet().toList(); 
      print('📊 YELP DATA: Search strategies (in order): $searchQueries');

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

          bool isCorrectBusiness = true;

          if (businessName.isNotEmpty && foundLocation.displayName != null) {
            final googleNameLower = foundLocation.displayName!.toLowerCase();
            final yelpNameLower = businessName.toLowerCase();
            
            // Split names into words for better matching
            final googleWords = googleNameLower.split(RegExp(r'\s+'));
            final yelpWords = yelpNameLower.split(RegExp(r'\s+'));
            
            // Calculate word overlap
            int matchingWords = 0;
            for (String yelpWord in yelpWords) {
              if (yelpWord.length > 2) { // Only consider meaningful words
                for (String googleWord in googleWords) {
                  if (googleWord.contains(yelpWord) || yelpWord.contains(googleWord)) {
                    matchingWords++;
                    break;
                  }
                }
              }
            }
            
            // Require at least 60% word overlap for extracted names from shared text
            double matchRatio = matchingWords / yelpWords.length;
            bool nameMatches = matchRatio >= 0.6 || 
                              googleNameLower.contains(yelpNameLower) || 
                              yelpNameLower.contains(googleNameLower.split(' ')[0]);
            
            if (!nameMatches) {
              print(
                  '📊 YELP DATA: Name verification failed. Google name "${foundLocation.displayName}" doesn\'t align well with Yelp name "${businessName}" (match ratio: ${(matchRatio * 100).toStringAsFixed(1)}%)');
              isCorrectBusiness = false;
            } else {
              print(
                  '📊 YELP DATA: Name check passed: Google="${foundLocation.displayName}", Yelp="$businessName" (match ratio: ${(matchRatio * 100).toStringAsFixed(1)}%)');
            }
          }

          if (isChainOrGeneric && isCorrectBusiness) {
            if (businessCity.isNotEmpty && foundLocation.city != null) {
              String googleCityLower = foundLocation.city!.toLowerCase();
              String yelpCityLower = businessCity.toLowerCase();
              if (!googleCityLower.contains(yelpCityLower) &&
                  !yelpCityLower.contains(googleCityLower)) {
                print(
                    '📊 YELP DATA: City verification failed for chain. Google city "${foundLocation.city}" doesn\'t match Yelp city "${businessCity}"');
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
      } 

      if (foundLocation == null && isChainOrGeneric && userPosition != null) {
        print(
            '📊 YELP DATA: All strategies failed for chain restaurant, trying FINAL fallback with Nearby Search');
        final nearbyResults = await _mapsService.searchNearbyPlaces(
            userPosition.latitude, userPosition.longitude, 50000, businessName);
        if (nearbyResults.isNotEmpty) {
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

      if (foundLocation != null) {
        Map<String, dynamic> resultData = {
          'location': foundLocation,
          'businessName': businessName,
          'yelpUrl': url,
        };
        _businessDataCache[cacheKey] = resultData;
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

  Future<String?> _resolveShortUrl(String shortUrl) async {
    print("🔗 RESOLVE: Attempting to resolve URL: $shortUrl"); 
    try {
      final dio = Dio(BaseOptions(
        followRedirects: true, 
        maxRedirects: 5, 
        validateStatus: (status) =>
            status != null && status < 500, 
      ));

      final response = await dio.get(shortUrl);

      if (response.statusCode == 200) {
        final finalUrl = response.realUri.toString();
        if (finalUrl != shortUrl) {
          print(
              "🔗 RESOLVE: Successfully resolved via redirects to: $finalUrl");
          return finalUrl;
        } else {
          print("🔗 RESOLVE: URL did not redirect to a different location.");
          return null; 
        }
      }

      print(
          "🔗 RESOLVE: Request completed but status was ${response.statusCode} or realUri was null.");
      return null; 
    } catch (e) {
      print("🔗 RESOLVE ERROR: Error resolving short URL $shortUrl: $e");
      return null;
    }
  }

  Future<Map<String, String>?> _getLocationDetailsFromYelpPage(
      String url) async {
    try {
      final dio = Dio();
      final response = await dio.get(url);

      if (response.statusCode == 200) {
        final html = response.data.toString();

        // Extract structured data
        final addressRegex = RegExp(r'address":"([^"]+)');
        final addressMatch = addressRegex.firstMatch(html);

        final cityRegex = RegExp(r'addressLocality":"([^"]+)');
        final cityMatch = cityRegex.firstMatch(html);

        final stateRegex = RegExp(r'addressRegion":"([^"]+)');
        final stateMatch = stateRegex.firstMatch(html);

        // Try to extract business name from various sources
        String businessName = '';
        
        // Try JSON-LD structured data first
        final nameRegex = RegExp(r'"name":"([^"]+)"');
        final nameMatch = nameRegex.firstMatch(html);
        if (nameMatch != null) {
          businessName = nameMatch.group(1) ?? '';
        }
        
        // Fallback: try page title
        if (businessName.isEmpty) {
          final titleRegex = RegExp(r'<title>([^<]+)</title>', caseSensitive: false);
          final titleMatch = titleRegex.firstMatch(html);
          if (titleMatch != null) {
            String title = titleMatch.group(1) ?? '';
            // Clean up title (Yelp titles often end with " - Yelp")
            title = title.replaceAll(RegExp(r'\s*-\s*Yelp.*$'), '');
            if (title.isNotEmpty && title.length < 100) {
              businessName = title;
            }
          }
        }

        if (addressMatch != null || cityMatch != null || stateMatch != null || businessName.isNotEmpty) {
          return {
            'address': addressMatch?.group(1) ?? '',
            'city': cityMatch?.group(1) ?? '',
            'state': stateMatch?.group(1) ?? '',
            'businessName': businessName,
          };
        }
      }

      return null;
    } catch (e) {
      print('Error fetching Yelp page: $e');
      return null;
    }
  }

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

      Position? position = await Geolocator.getLastKnownPosition();

      position ??= await Geolocator.getCurrentPosition();

      print(
          '📊 YELP DATA: Got user position: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      print('📊 YELP DATA: Error getting position: $e');
      return null;
    }
  }

  int _findBestMatch(List<Map<String, dynamic>> results, String address,
      String city, String state) {
    if (results.isEmpty || results.length == 1) return 0;

    final targetCityLower = city.trim().toLowerCase();
    print(
        '📊 YELP DATA _findBestMatch: Looking for results matching city: "$targetCityLower"');

    int bestMatchIndex = 0; 
    int highestScore =
        -1; 

    for (int i = 0; i < results.length; i++) {
      final result = results[i];
      final placeAddress = result['vicinity'] as String? ??
          result['formatted_address'] as String? ??
          result['description'] as String? ??
          '';
      final placeAddressLower = placeAddress.toLowerCase();
      print(
          '📊 YELP DATA _findBestMatch: Checking Result ${i + 1}: "$placeAddress"');

      int currentScore = -1;

      if (targetCityLower.isNotEmpty) {
        final extractedCity = _extractCityFromAddress(placeAddress);
        final extractedCityLower = extractedCity.toLowerCase();

        if (extractedCityLower == targetCityLower) {
          print(
              '📊 YELP DATA _findBestMatch: Found EXACT city match "$extractedCity" at index $i');
          currentScore = 2; 
        } else if (placeAddressLower.contains(targetCityLower)) {
          print(
              '📊 YELP DATA _findBestMatch: Found PARTIAL city match in address "$placeAddress" at index $i');
          currentScore = max(currentScore, 1); 
        }
      }

      final targetStateLower = state.trim().toLowerCase();
      if (currentScore < 1 &&
          targetStateLower.isNotEmpty &&
          targetStateLower.length == 2) {
        final statePattern = RegExp(
            r'[\s,]' + targetStateLower + r'(?:\s+\d{5}(-\d{4})?|,|\s*$)',
            caseSensitive: false);

        if (statePattern.hasMatch(placeAddress)) {
          print(
              '📊 YELP DATA _findBestMatch: Found STATE match "$targetStateLower" in address "$placeAddress" at index $i');
          currentScore = max(currentScore, 0); 
        }
      }

      if (currentScore > highestScore) {
        highestScore = currentScore;
        bestMatchIndex = i;
        print(
            '📊 YELP DATA _findBestMatch: New best match index: $i (Score: $highestScore)');
      }

      if (highestScore == 2) {
        break;
      }
    }

    print(
        '📊 YELP DATA _findBestMatch: Final selected index: $bestMatchIndex (Score: $highestScore)');
    return bestMatchIndex;
  }

  String _extractCityFromAddress(String address) {
    if (address.isEmpty) return '';
    final parts = address.split(',');
    if (parts.length >= 3) {
      String potentialCity = parts[parts.length - 3].trim();
      if (potentialCity.length > 2 &&
          !RegExp(r'^[A-Z]{2}$').hasMatch(potentialCity) &&
          !RegExp(r'^\d+$').hasMatch(potentialCity)) {
        return potentialCity;
      }
      potentialCity = parts[parts.length - 2].trim();
      if (potentialCity.length > 2 &&
          !RegExp(r'^[A-Z]{2}$').hasMatch(potentialCity) &&
          !RegExp(r'^\d+$').hasMatch(potentialCity)) {
        potentialCity = potentialCity.replaceAll(
            RegExp(r'\s+[A-Z]{2}(\s+\d{5}(-\d{4})?)?$'), '');
        return potentialCity.trim();
      }
    } else if (parts.length == 2) {
      String potentialCity = parts[0].trim();
      String lastPart = parts[1].trim();
      if (RegExp(r'^[A-Z]{2}(\s+\d{5}(-\d{4})?)?$').hasMatch(lastPart)) {
        return potentialCity;
      }
    } else if (parts.length == 1) {
      if (address.length < 30 && !address.contains(RegExp(r'\d'))) {
        return address.trim();
      }
    }
    return ''; 
  }

  void _fillFormWithBusinessData(
      Location location, String businessName, String yelpUrl) async { // Ensured async
    // Check mounted HERE before using context or calling setState
    if (!mounted) return;

    final provider = context.read<ReceiveShareProvider>();

    ExperienceCardData? targetCard;
    for (var card in provider.experienceCards) {
      if (card.yelpUrlController.text == yelpUrl) {
        targetCard = card;
        break;
      }
    }
    targetCard ??=
        provider.experienceCards.isNotEmpty ? provider.experienceCards.first : null;

    if (targetCard == null) {
      print("WARN: _fillFormWithBusinessData - No target card found.");
      return;
    }

    // --- ADDED: Duplicate Check ---
    FocusManager.instance.primaryFocus?.unfocus(); // MODIFIED
    await Future.microtask(() {});      // ADDED
    Experience? existingExperience = await _checkForDuplicateExperienceDialog(
      context: context,
      card: targetCard,
      placeIdToCheck: location.placeId,
    );

    if (existingExperience != null) {
      provider.updateCardWithExistingExperience(targetCard.id, existingExperience);
      // Potentially update _yelpPreviewFutures if the existing experience has a different placeId/structure
      // For now, we assume the existingExperience's details are sufficient and don't re-trigger preview future updates here.
      print("Yelp Fill: Used existing experience by Place ID: ${existingExperience.id}");
      return; // Early return
    }

    // If no match by placeId, or user chose "Create New", check by title
    FocusManager.instance.primaryFocus?.unfocus(); // MODIFIED
    await Future.microtask(() {});      // ADDED
    existingExperience = await _checkForDuplicateExperienceDialog(
      context: context,
      card: targetCard,
      titleToCheck: location.displayName ?? businessName,
    );

    if (existingExperience != null) {
      provider.updateCardWithExistingExperience(targetCard.id, existingExperience);
      print("Yelp Fill: Used existing experience by Title: ${existingExperience.id}");
      return; // Early return
    }
    // --- END ADDED ---

    print('====> 📝 YELP FILL: Filling card for Yelp URL: $yelpUrl');
    print('====> 📝 YELP FILL:   Location Display Name: ${location.displayName}');
    print('====> 📝 YELP FILL:   Location Address: ${location.address}');
    print('====> 📝 YELP FILL:   Location Website: ${location.website}');
    print('====> 📝 YELP FILL:   Business Name (parsed): $businessName');

    final String titleToSet = location.displayName ?? businessName;
    final String addressToSet = location.address ?? '';
    final String websiteToSet = location.website ?? '';
    final String? placeIdForPreviewToSet = location.placeId;

    provider.updateCardFromShareDetails(
      cardId: targetCard.id,
      location: location,
      title: titleToSet,
      yelpUrl: yelpUrl, 
      website: websiteToSet,
      placeIdForPreview: placeIdForPreviewToSet,
      searchQueryText: addressToSet, 
    );

    setState(() {
      final String originalUrlKey = yelpUrl.trim();
      final String? placeIdKey = location.placeId;

      if (_yelpPreviewFutures.containsKey(originalUrlKey)) {
        _yelpPreviewFutures.remove(originalUrlKey);
        print('🔄 FUTURE MAP (Yelp): Removed future keyed by original URL: $originalUrlKey');
      }

      if (placeIdKey != null && placeIdKey.isNotEmpty) {
        final Map<String, dynamic> finalData = {
          'location': location,
          'businessName': titleToSet,
          'yelpUrl': yelpUrl,
        };
        _yelpPreviewFutures[placeIdKey] = Future.value(finalData);
        print('🔄 FUTURE MAP (Yelp): Updated/Added future keyed by Place ID: $placeIdKey');
      } else {
        print('🔄 FUTURE MAP (Yelp): No Place ID available to update future map.');
      }
    });
  }

  void _fillFormWithGoogleMapsData(Location location, String placeName,
      String websiteUrl, String originalMapsUrl) async { // Ensured async
    // Check mounted HERE
    if (!mounted) return;

    final provider = context.read<ReceiveShareProvider>();
    final firstCard = provider.experienceCards.isNotEmpty
        ? provider.experienceCards.first
        : null;

    if (firstCard == null) {
      print("WARN: _fillFormWithGoogleMapsData - No card found.");
      return; 
    }

    // --- ADDED: Duplicate Check ---
    FocusManager.instance.primaryFocus?.unfocus(); // ADDED
    await Future.microtask(() {});      // ADDED
    Experience? existingExperience = await _checkForDuplicateExperienceDialog(
      context: context,
      card: firstCard,
      placeIdToCheck: location.placeId,
    );

    if (existingExperience != null) {
      provider.updateCardWithExistingExperience(firstCard.id, existingExperience);
      // Similar to Yelp, preview futures might need updating based on existingExperience.
      print("Maps Fill: Used existing experience by Place ID: ${existingExperience.id}");
      return; // Early return
    }

    // If no match by placeId, or user chose "Create New", check by title
    FocusManager.instance.primaryFocus?.unfocus(); // ADDED
    await Future.microtask(() {});      // ADDED
    existingExperience = await _checkForDuplicateExperienceDialog(
      context: context,
      card: firstCard,
      titleToCheck: location.displayName ?? placeName,
    );

    if (existingExperience != null) {
      provider.updateCardWithExistingExperience(firstCard.id, existingExperience);
      print("Maps Fill: Used existing experience by Title: ${existingExperience.id}");
      return; // Early return
    }
    // --- END ADDED ---

    print('🗺️ MAPS FILL: Filling card for Maps Location: ${location.displayName ?? placeName}');
    print('🗺️ MAPS FILL:   Location Address: ${location.address}');
    print('🗺️ MAPS FILL:   Location Website: ${location.website}');

    final String titleToSet = location.displayName ?? placeName;
    final String addressToSet = location.address ?? '';
    final String websiteToSet = websiteUrl; 
    final String? placeIdForPreviewToSet = location.placeId;

    provider.updateCardFromShareDetails(
      cardId: firstCard.id,
      location: location,
      title: titleToSet,
      mapsUrl: originalMapsUrl, 
      website: websiteToSet,
      placeIdForPreview: placeIdForPreviewToSet,
      searchQueryText: addressToSet, 
    );

    setState(() {
      final String? placeIdKey = location.placeId;
      if (placeIdKey != null && placeIdKey.isNotEmpty) {
        final String originalUrlKey = originalMapsUrl.trim();
        if (_yelpPreviewFutures.containsKey(originalUrlKey)) {
            _yelpPreviewFutures.remove(originalUrlKey);
            print('🔄 FUTURE MAP (Maps): Removed future keyed by original URL: $originalUrlKey');
        }

        final Map<String, dynamic> finalData = {
          'location': location,
          'placeName': titleToSet,
          'website': websiteToSet,
          'mapsUrl': originalMapsUrl,
        };
        _yelpPreviewFutures[placeIdKey] = Future.value(finalData);
        print('🔄 FUTURE MAP (Maps): Updated/Added future keyed by Place ID: $placeIdKey');
      } else {
        print('🔄 FUTURE MAP (Maps): No Place ID available to update future map.');
      }
    });
  }

  Future<void> _saveExperience() async {
    final provider = context.read<ReceiveShareProvider>();
    final experienceCards = provider.experienceCards;

    if (_userCategories.isEmpty) {
      _showSnackBar(context, 'Categories not loaded yet. Please wait.');
      return;
    }

    final String? currentUserId = _authService.currentUser?.uid;
    if (currentUserId == null) {
      if (!mounted) return;
      _showSnackBar(
          context, 'Error: Could not identify user. Please log in again.');
      return;
    }

    bool allValid = true;
    for (var card in experienceCards) {
      if (!card.formKey.currentState!.validate()) {
        allValid = false;
        break;
      }
      if (card.selectedCategoryId == null || card.selectedCategoryId!.isEmpty) {
        if (!mounted) return;
        _showSnackBar(context, 'Please select a category for each card.');
        allValid = false;
        break;
      }
      if (card.locationEnabled.value && card.selectedLocation == null) {
        if (!mounted) return;
        _showSnackBar(context,
            'Please select a location for experience card: "${card.titleController.text}" ');
        allValid = false;
        break;
      }
    }

    if (!allValid) {
      if (!mounted) return;
      _showSnackBar(context, 'Please fill in required fields correctly');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    int successCount = 0;
    int updateCount = 0;
    List<String> errors = [];
    bool shouldAttemptNavigation = false; // Renamed from navigateAway for clarity

    try {
      if (!mounted) return;

      final now = DateTime.now();
      final uniqueSharedPaths =
          _currentSharedFiles.map((f) => f.path).toSet().toList();
      print(
          "SAVE_DEBUG: Starting save process for ${experienceCards.length} card(s) with ${uniqueSharedPaths.length} unique media paths.");

      final Map<String, String> mediaPathToItemIdMap = {};
      print("SAVE_DEBUG: Pre-processing media paths...");
      for (final path in uniqueSharedPaths) {
        try {
          SharedMediaItem? existingItem;
          try {
            print(
                "SAVE_DEBUG: Checking for existing SharedMediaItem for path: $path AND owner: $currentUserId");
            SharedMediaItem? foundItem =
                await _experienceService.findSharedMediaItemByPath(path);
            if (!mounted) return;

            if (foundItem != null && foundItem.ownerUserId == currentUserId) {
              existingItem = foundItem;
              print("SAVE_DEBUG: Found existing item ID: ${existingItem.id}");
            } else if (foundItem != null) {
              print(
                  "SAVE_DEBUG: Found item with same path but DIFFERENT owner (${foundItem.ownerUserId}). Will create new one for $currentUserId.");
            } else {
              print(
                  "SAVE_DEBUG: No existing item found for this path and owner.");
            }
          } catch (e) {
            print(
                "SAVE_DEBUG: Error querying for existing shared media item: $e");
          }

          if (existingItem != null) {
            mediaPathToItemIdMap[path] = existingItem.id;
          } else {
            print(
                "SAVE_DEBUG: Creating new SharedMediaItem for path: $path, owner: $currentUserId");
            
            // Check if this is a TikTok URL and get its photo status
            bool? isTiktokPhoto;
            if (path.contains('tiktok.com') || path.contains('vm.tiktok.com')) {
              isTiktokPhoto = _tiktokPhotoStatus[path];
              print("SAVE_DEBUG: TikTok URL detected. Is photo carousel: $isTiktokPhoto");
            }
            
            SharedMediaItem newItem = SharedMediaItem(
              id: '',
              path: path,
              createdAt: now,
              ownerUserId: currentUserId,
              experienceIds: [],
              isTiktokPhoto: isTiktokPhoto,
            );
            String newItemId =
                await _experienceService.createSharedMediaItem(newItem);
            if (!mounted) return;
            mediaPathToItemIdMap[path] = newItemId;
            print("SAVE_DEBUG: Created new item ID: $newItemId");
          }
        } catch (e) {
          print(
              "SAVE_DEBUG: Error finding/creating SharedMediaItem for path '$path': $e");
          errors.add(
              "Error processing media: ${path.split('/').last}");
        }
      }
      print(
          "SAVE_DEBUG: Media pre-processing complete. Map: $mediaPathToItemIdMap");

      if (mediaPathToItemIdMap.length != uniqueSharedPaths.length && errors.isEmpty) {
         // If there was an issue creating media items but no errors were added to the list yet (e.g. silent failure)
        print(
            "SAVE_DEBUG: Discrepancy in media item processing but no explicit errors. Adding a generic media error.");
        errors.add("Error processing some media files.");
      }

      if (errors.isEmpty) { // Only proceed with card processing if media pre-processing was okay
        for (final card in experienceCards) {
          String? targetExperienceId;
          bool isNewExperience = false;
          Experience? currentExperienceData;

          try {
            print(
                "SAVE_DEBUG: Processing card ${card.id}. ExistingID: ${card.existingExperienceId}");

            final String cardTitle = card.titleController.text;
            final Location? cardLocation = card.selectedLocation;
            final String placeId = cardLocation?.placeId ?? '';
            final String cardYelpUrl = card.yelpUrlController.text.trim();
            final String cardWebsite = card.websiteController.text.trim();
            final String notes = card.notesController.text.trim();
            final String categoryIdToSave = card.selectedCategoryId!;
            bool canProcessPublicExperience = placeId.isNotEmpty && cardLocation != null;
            final String? colorCategoryIdToSave = card.selectedColorCategoryId;
            UserCategory? selectedCategoryObject;
            try {
              selectedCategoryObject = _userCategories
                  .firstWhere((cat) => cat.id == categoryIdToSave);
            } catch (e) {
              selectedCategoryObject = null;
            }

            final Location defaultLocation = Location(
                latitude: 0.0,
                longitude: 0.0,
                address: 'No location specified');
            final Location locationToSave =
                (card.locationEnabled.value && cardLocation != null)
                    ? cardLocation
                    : defaultLocation;

            if (card.existingExperienceId == null ||
                card.existingExperienceId!.isEmpty) {
              isNewExperience = true;
              Experience newExperience = Experience(
                id: '',
                name: cardTitle,
                description:
                    notes.isNotEmpty ? notes : 'Created from shared content',
                location: locationToSave,
                categoryId: categoryIdToSave,
                yelpUrl: cardYelpUrl.isNotEmpty ? cardYelpUrl : null,
                website: cardWebsite.isNotEmpty ? cardWebsite : null,
                additionalNotes: notes.isNotEmpty ? notes : null,
                sharedMediaItemIds: [],
                createdAt: now,
                updatedAt: now,
                editorUserIds: [currentUserId],
                colorCategoryId: colorCategoryIdToSave,
                otherCategories: card.selectedOtherCategoryIds,
              );
              targetExperienceId =
                  await _experienceService.createExperience(newExperience);
              if (!mounted) return;
              currentExperienceData = newExperience.copyWith();
              currentExperienceData = await _experienceService.getExperience(
                  targetExperienceId);
              if (!mounted) return;
              print(
                  "SAVE_DEBUG: Created NEW Experience ID: $targetExperienceId");
              successCount++;
            } else {
              isNewExperience = false;
              targetExperienceId = card.existingExperienceId!;
              print(
                  "SAVE_DEBUG: Using EXISTING experience ID: $targetExperienceId");
              currentExperienceData =
                  await _experienceService.getExperience(targetExperienceId);
              if (!mounted) return;
              if (currentExperienceData == null) {
                print(
                    "SAVE_DEBUG: ERROR - Could not find existing experience $targetExperienceId");
                errors.add('Could not update "$cardTitle" (not found).');
                continue;
              }
              Experience updatedExpData = currentExperienceData.copyWith(
                  name: cardTitle,
                  description: notes.isNotEmpty ? notes : currentExperienceData.description,
                  location: locationToSave,
                  categoryId: categoryIdToSave,
                  yelpUrl: cardYelpUrl.isNotEmpty ? cardYelpUrl : null,
                  website: cardWebsite.isNotEmpty ? cardWebsite : null,
                  additionalNotes: notes.isNotEmpty ? notes : null,
                  updatedAt: now,
                  editorUserIds: currentExperienceData.editorUserIds.contains(currentUserId)
                      ? currentExperienceData.editorUserIds
                      : [...currentExperienceData.editorUserIds, currentUserId],
                  colorCategoryId: colorCategoryIdToSave,
                  otherCategories: card.selectedOtherCategoryIds);
              await _experienceService.updateExperience(updatedExpData);
              currentExperienceData = updatedExpData;
              if (!mounted) return;
              print(
                  "SAVE_DEBUG: Updated EXISTING Experience ID: $targetExperienceId");
              updateCount++;
            }

            final List<String> relevantMediaItemIds = uniqueSharedPaths
                .map((path) => mediaPathToItemIdMap[path])
                .where((id) => id != null)
                .cast<String>()
                .toList();
            print(
                "SAVE_DEBUG: Relevant Media IDs for Experience $targetExperienceId: $relevantMediaItemIds");

            if (currentExperienceData != null) {
              List<String> existingMediaIds =
                  currentExperienceData.sharedMediaItemIds;
              List<String> finalMediaIds =
                  {...existingMediaIds, ...relevantMediaItemIds}.toList();
              if (isNewExperience ||
                  !DeepCollectionEquality()
                      .equals(existingMediaIds, finalMediaIds)) {
                print(
                    "SAVE_DEBUG: Updating Experience $targetExperienceId with final media IDs: $finalMediaIds");
                Experience experienceToUpdate = currentExperienceData.copyWith(
                  name:
                      !isNewExperience ? cardTitle : currentExperienceData.name,
                  location: !isNewExperience
                      ? locationToSave
                      : currentExperienceData.location,
                  categoryId: !isNewExperience
                      ? categoryIdToSave
                      : currentExperienceData.categoryId,
                  yelpUrl: !isNewExperience && cardYelpUrl.isNotEmpty
                      ? cardYelpUrl
                      : currentExperienceData.yelpUrl,
                  website: !isNewExperience && cardWebsite.isNotEmpty
                      ? cardWebsite
                      : currentExperienceData.website,
                  description: !isNewExperience && notes.isNotEmpty
                      ? notes
                      : currentExperienceData.description,
                  additionalNotes: !isNewExperience && notes.isNotEmpty
                      ? notes
                      : currentExperienceData.additionalNotes,
                  colorCategoryId: !isNewExperience
                      ? colorCategoryIdToSave
                      : currentExperienceData.colorCategoryId,
                  otherCategories: !isNewExperience
                      ? card.selectedOtherCategoryIds
                      : currentExperienceData.otherCategories,
                  sharedMediaItemIds: finalMediaIds,
                  updatedAt: now,
                );
                await _experienceService.updateExperience(experienceToUpdate);
                if (!mounted) return;
              } else {
                print(
                    "SAVE_DEBUG: No changes to media links for existing Experience $targetExperienceId. Skipping update.");
                if (!isNewExperience && relevantMediaItemIds.isNotEmpty) updateCount--; // Correct if only media was new and no other field changed
              }
            } else {
              print(
                  "SAVE_DEBUG: ERROR - currentExperienceData is null when trying to update media links.");
              continue;
            }
            print(
                "SAVE_DEBUG: Linking ${relevantMediaItemIds.length} media items to Experience $targetExperienceId...");
            for (final mediaItemId in relevantMediaItemIds) {
              try {
                await _experienceService.addExperienceLinkToMediaItem(
                    mediaItemId, targetExperienceId);
                if (!mounted) return;
              } catch (e) {
                print(
                    "SAVE_DEBUG: Error linking media $mediaItemId to experience $targetExperienceId: $e");
              }
            }
            if (canProcessPublicExperience) {
              print(
                  "SAVE_DEBUG: Processing Public Experience logic for PlaceID: $placeId");
              PublicExperience? existingPublicExp = await _experienceService
                  .findPublicExperienceByPlaceId(placeId);
              if (!mounted) return;
              if (existingPublicExp == null) {
                String publicName = locationToSave.getPlaceName();
                PublicExperience newPublicExperience = PublicExperience(
                    id: '',
                    name: publicName,
                    location: locationToSave,
                    placeID: placeId,
                    yelpUrl: cardYelpUrl.isNotEmpty ? cardYelpUrl : null,
                    website: cardWebsite.isNotEmpty ? cardWebsite : null,
                    allMediaPaths: uniqueSharedPaths);
                print("SAVE_DEBUG: Creating Public Experience: $publicName");
                await _experienceService
                    .createPublicExperience(newPublicExperience);
                if (!mounted) return;
              } else {
                print(
                    "SAVE_DEBUG: Found existing Public Experience ID: ${existingPublicExp.id}. Adding media paths.");
                await _experienceService.updatePublicExperienceMediaAndMaybeYelp(
                    existingPublicExp.id,
                    uniqueSharedPaths,
                    newYelpUrl: cardYelpUrl.isNotEmpty ? cardYelpUrl : null);
                if (!mounted) return;
              }
            } else {
              print(
                  "SAVE_DEBUG: Skipping Public Experience logic due to missing PlaceID or Location.");
            }
            if (selectedCategoryObject != null) {
              try {
                await _experienceService
                    .updateCategoryLastUsedTimestamp(selectedCategoryObject.id);
                if (!mounted) return;
                print(
                    "SAVE_DEBUG [Card ${card.id}]: Updated timestamp for category: ${selectedCategoryObject.name}");
              } catch (e) {
                print(
                    "Error updating timestamp for category ${selectedCategoryObject.id}: $e");
              }
            } else {
              print(
                  "Warning: Could not find category object for ID '$categoryIdToSave' to update timestamp.");
            }
            if (colorCategoryIdToSave != null) {
              try {
                await _experienceService.updateColorCategoryLastUsedTimestamp(
                    colorCategoryIdToSave);
                if (!mounted) return;
                print(
                    "SAVE_DEBUG [Card ${card.id}]: Updated timestamp for color category ID: $colorCategoryIdToSave");
              } catch (e) {
                print(
                    "Error updating timestamp for color category $colorCategoryIdToSave: $e");
              }
            }
          } catch (e) {
            print(
                "SAVE_DEBUG: Error processing card '${card.titleController.text}': $e");
            errors.add('Error saving "${card.titleController.text}".');
            if (isNewExperience && successCount > 0) {
              successCount--;
            } else if (!isNewExperience && updateCount > 0) {
              updateCount--;
            }
          }
        }
      } // End of if (errors.isEmpty) for card processing

      String message;
      if (errors.isEmpty) {
        message = '';
        if (successCount > 0) {
          message += '$successCount experience(s) created. ';
        }
        if (updateCount > 0) message += '$updateCount experience(s) updated. ';
        message = message.trim();
        if (message.isEmpty) message = 'No changes saved.';
        shouldAttemptNavigation = true;
      } else {
        message = 'Completed with errors: ';
        if (successCount > 0) message += '$successCount created. ';
        if (updateCount > 0) message += '$updateCount updated. ';
        message += '${errors.length} failed.';
        print('Save errors: ${errors.join('\n')}');
        if (successCount > 0 || updateCount > 0) {
            shouldAttemptNavigation = true; // Still navigate if some parts succeeded
        }
      }

      if (!mounted) return;
      _showSnackBar(context, message);

      if (experienceCards.isNotEmpty && (successCount > 0 || updateCount > 0)) {
        final lastProcessedCard = experienceCards.last;
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;

        if (lastProcessedCard.selectedCategoryId != null) {
          await prefs.setString(AppConstants.lastUsedCategoryKey, lastProcessedCard.selectedCategoryId!);
          if (!mounted) return;
          print("ReceiveShareScreen: Saved last used category: ${lastProcessedCard.selectedCategoryId}");
        } else {
          await prefs.remove(AppConstants.lastUsedCategoryKey);
          if (!mounted) return;
          print("ReceiveShareScreen: Last used category was null, removed preference.");
        }

        if (lastProcessedCard.selectedColorCategoryId != null) {
          await prefs.setString(AppConstants.lastUsedColorCategoryKey, lastProcessedCard.selectedColorCategoryId!);
          if (!mounted) return;
          print("ReceiveShareScreen: Saved last used color category ID: ${lastProcessedCard.selectedColorCategoryId}");
        } else {
          await prefs.remove(AppConstants.lastUsedColorCategoryKey);
          if (!mounted) return;
          print("ReceiveShareScreen: Last used color category ID was null, removed preference.");
        }

        // ADDED: Save last used other categories
        await prefs.setStringList(AppConstants.lastUsedOtherCategoriesKey, lastProcessedCard.selectedOtherCategoryIds);
        if (!mounted) return;
        print("ReceiveShareScreen: Saved last used other categories: ${lastProcessedCard.selectedOtherCategoryIds}");
        // --- END ADDED ---
      }

      if (shouldAttemptNavigation) {
        if (!mounted) return;

        _sharingService.prepareToNavigateAwayFromShare(); // Use new method

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const MainScreen()),
          (Route<dynamic> route) => false,
        );
        // The old Future.delayed for resetSharedItems is removed as markShareFlowAsInactive handles reset.
      }
    } catch (e) {
      if (!mounted) return;
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

      if (mounted) {
        setState(() {
          card.searchResults = results;
        });
      }
    } catch (e) {
      print('Error searching places: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error searching places')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          card.isSelectingLocation = false;
        });
      }
    }
  }

  Future<void> _selectPlace(String placeId, ExperienceCardData card) async {
    setState(() {
      card.isSelectingLocation = true;
    });

    try {
      final location = await _mapsService.getPlaceDetails(placeId);

      if (mounted) {
        setState(() {
          card.selectedLocation = location;
          card.searchController.text = location.address ?? '';
        });
      }
    } catch (e) {
      print('Error getting place details: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting location')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          card.isSelectingLocation = false;
        });
      }
    }
  }

  Future<void> _showLocationPicker(ExperienceCardData card) async {
    FocusManager.instance.primaryFocus?.unfocus(); // MODIFIED
    await Future.microtask(() {}); // ADDED

    bool isOriginalShareYelp = card.originalShareType == ShareType.yelp;
    print(
        "LocationPicker opening context: originalShareType is ${card.originalShareType}");

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          initialLocation: card.selectedLocation,
          onLocationSelected: (location) {},
          businessNameHint:
              isOriginalShareYelp ? card.titleController.text : null,
        ),
      ),
    );

    if (result != null && mounted) {
      Future.microtask(() {
        if (mounted) { // Check mounted before using context
          FocusScope.of(context).unfocus();
        }
      });

      final Location selectedLocationFromResult =
          result is Map ? result['location'] : result as Location;
      final provider = context.read<ReceiveShareProvider>();

      // --- ADDED: Duplicate Check based on selected location's Place ID ---
      if (selectedLocationFromResult.placeId != null && selectedLocationFromResult.placeId!.isNotEmpty) {
        FocusManager.instance.primaryFocus?.unfocus(); // MODIFIED
        await Future.microtask(() {});      // ADDED
        final Experience? existingExperienceByPlaceId = await _checkForDuplicateExperienceDialog(
          context: context,
          card: card,
          placeIdToCheck: selectedLocationFromResult.placeId,
        );
        if (mounted && existingExperienceByPlaceId != null) {
          provider.updateCardWithExistingExperience(card.id, existingExperienceByPlaceId);
          print("LocationPicker: Used existing experience by Place ID: ${existingExperienceByPlaceId.id}");
          return; // Stop further processing if existing experience is used
        }
      }
      // --- END ADDED ---

      final Location selectedLocation = selectedLocationFromResult; // Use the original variable name for clarity below

      if (isOriginalShareYelp) {
        print("LocationPicker returned from Yelp context: Updating info.");
        try {
          if (selectedLocation.placeId == null ||
              selectedLocation.placeId!.isEmpty) {
            print("Error: Cannot update Yelp info without a Place ID.");
            provider.updateCardData(card, location: selectedLocation);
            return;
          }

          Location detailedLocation =
              await _mapsService.getPlaceDetails(selectedLocation.placeId!);
          
          if (!mounted) return; // Check mounted after await

          final String businessName = detailedLocation.getPlaceName();
          final String yelpUrl = card.yelpUrlController.text.trim();

          _businessDataCache.remove(yelpUrl);
          _yelpPreviewFutures.remove(yelpUrl);
          if (card.placeIdForPreview != null) {
            _yelpPreviewFutures.remove(card.placeIdForPreview);
          }

          provider.updateCardFromShareDetails( 
            cardId: card.id,
            location: detailedLocation,
            title: businessName,
            yelpUrl: yelpUrl, 
            website: detailedLocation.website,
            searchQueryText: detailedLocation.address,
            placeIdForPreview: detailedLocation.placeId,
          );

          if (card.originalShareType == ShareType.yelp || card.originalShareType == ShareType.maps) {
            setState(() {
              final String futureKey = detailedLocation.placeId!;
              final Map<String, dynamic> newFutureData = {
                'location': detailedLocation,
                'businessName': businessName,
                'yelpUrl': yelpUrl,
                'photoUrl': detailedLocation.photoUrl,
                'address': detailedLocation.address,
                'website': detailedLocation.website,
              };
              _yelpPreviewFutures[futureKey] = Future.value(newFutureData);
              print("Updated _yelpPreviewFutures for Yelp/Maps original shareType with key: $futureKey");
            });
          }
        } catch (e) {
          print("Error getting place details or updating card: $e");
          if (mounted) {
            _showSnackBar(
                context, "Error updating location details from Yelp context: $e");
          }
          provider.updateCardData(card, location: selectedLocation);
        }
      } else {
        print(
            "LocationPicker returned (non-Yelp context): Fetching details and updating card fully.");
        try {
          if (selectedLocation.placeId == null ||
              selectedLocation.placeId!.isEmpty) {
            print(
                "Error: Location picked has no Place ID. Performing basic update.");
            provider.updateCardData(card,
                location: selectedLocation,
                searchQuery: selectedLocation.address ?? 'Selected Location');
            return;
          }

          Location detailedLocation =
              await _mapsService.getPlaceDetails(selectedLocation.placeId!);

          if (!mounted) return; // Check mounted after await

          final String title = detailedLocation.getPlaceName();
          final String? website = detailedLocation.website;
          final String address = detailedLocation.address ?? '';
          final String? placeId = detailedLocation.placeId;

          if (card.placeIdForPreview != null) {
            _yelpPreviewFutures.remove(card.placeIdForPreview);
            print(
                "Cleared future cache for old placeId: ${card.placeIdForPreview}");
          }

          provider.updateCardFromShareDetails( 
            cardId: card.id,
            location: detailedLocation,
            title: title,
            website: website,
            searchQueryText: address,
            placeIdForPreview: placeId,
          );
          
          bool shouldUpdateFuturesForGenericPick = false; 

          if (shouldUpdateFuturesForGenericPick && placeId != null && placeId.isNotEmpty) {
             setState(() {
                final String futureKey = placeId;
                final Map<String, dynamic> newFutureData = {
                  'location': detailedLocation,
                  'placeName': title,
                  'website': website,
                  'mapsUrl': null, 
                  'photoUrl': detailedLocation.photoUrl,
                  'address': address,
                };
                _yelpPreviewFutures[futureKey] = Future.value(newFutureData);
                print("Updated _yelpPreviewFutures for generic pick with key: $futureKey");
            });
          }

          print("LocationPicker update successful for non-Yelp context.");
        } catch (e) {
          print(
              "Error getting place details or updating card in non-Yelp context: $e");
          if (mounted) {
            _showSnackBar(context, "Error updating location details: $e");
          }
          provider.updateCardData(card,
              location: selectedLocation,
              searchQuery: selectedLocation.address ?? 'Selected Location');
        }
      }
    } else {
      print("LocationPicker returned null or screen unmounted.");
    }
  }

  Future<void> _selectSavedExperienceForCard(ExperienceCardData card) async {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus(); // MODIFIED
    await Future.microtask(() {}); // ADDED

    final selectedExperience = await showModalBottomSheet<Experience>(
      context: context,
      isScrollControlled: true, 
      backgroundColor: Theme.of(context).cardColor, 
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85, 
          minChildSize: 0.5,
          maxChildSize: 0.9, 
          builder: (BuildContext scrollSheetContext, ScrollController scrollController) {
            return SelectSavedExperienceModalContent(
              scrollController: scrollController,
            );
          },
        );
      },
    );

    if (selectedExperience != null && mounted) {
      Future.microtask(() => FocusScope.of(context).unfocus());

      // --- ADDED: Duplicate check if an existing experience is selected by its title ---
      // This scenario implies the user explicitly chose an existing experience.
      // We might still want to confirm if by chance the *card's current title* (if different from selectedExperience.name)
      // also matches another experience. However, the primary action here is to use the *selectedExperience*.
      // For now, we directly update with the selected experience as the user made an explicit choice.
      // If further checks are needed based on the card's potentially *different* current title field before this selection,
      // that would be a separate logic branch.

      context.read<ReceiveShareProvider>().updateCardWithExistingExperience(
            card.id, 
            selectedExperience,
          );
      print("ReceiveShareScreen: Card ${card.id} updated with explicitly selected existing experience: ${selectedExperience.id}");
    }
  }

  void _handleExperienceCardFormUpdate({
    required String cardId,
    bool refreshCategories = false,
    String? newCategoryName,
    String? selectedColorCategoryId,
    String? newTitleFromCard, // ADDED
  }) async { // Ensured async
    print(
        "ReceiveShareScreen._handleExperienceCardFormUpdate called: cardId=$cardId, refreshCategories=$refreshCategories, newCategoryName=$newCategoryName, selectedColorCategoryId=$selectedColorCategoryId, newTitleFromCard=$newTitleFromCard");

    final provider = context.read<ReceiveShareProvider>();
    final card = provider.experienceCards.firstWhere((c) => c.id == cardId, orElse: () {
      // This should ideally not happen if cardId is always valid
      print("Error in _handleExperienceCardFormUpdate: Card with ID $cardId not found.");
      // Return a dummy/empty card or throw to prevent null errors, though provider should handle this.
      // For safety, let's assume if card not found, we can't proceed with title check.
      throw Exception("Card not found for ID $cardId in _handleExperienceCardFormUpdate");
    });

    // --- ADDED: Duplicate Check for Title Submission ---
    if (newTitleFromCard != null && newTitleFromCard.isNotEmpty) {
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus(); // MODIFIED
      await Future.microtask(() {});      // ADDED
      Experience? existingExperience = await _checkForDuplicateExperienceDialog(
        context: context,
        card: card,
        titleToCheck: newTitleFromCard,
      );
      if (mounted && existingExperience != null) {
        provider.updateCardWithExistingExperience(card.id, existingExperience);
        print("ReceiveShareScreen: Card ${card.id} updated with existing experience by title check: ${existingExperience.id}");
        // If an existing experience is used, we might not need to proceed with other updates below,
        // or we might want to merge (e.g., category change could still apply to the chosen existing experience).
        // For now, if user selects an existing one, we prioritize that and skip further category/color updates in this call.
        return; 
      }
      // If no duplicate used, the title controller on the card in the provider ALREADY has the newTitleFromCard
      // because the ExperienceCardForm's titleController is directly from ExperienceCardData.
      // The provider just needs to be notified if other UI depends on a specific title update event, but the data is there.
      // Provider listeners will trigger rebuilds if necessary.
    }
    // --- END ADDED ---

    if (selectedColorCategoryId != null) { 
      print(
          "  Updating color category for card $cardId to $selectedColorCategoryId via provider.");
      context
          .read<ReceiveShareProvider>()
          .updateCardColorCategory(cardId, selectedColorCategoryId);
    } else if (refreshCategories) { // UNCOMMENTED
      print("  Refreshing Categories via Notifiers...");
      Future.wait([
        _refreshUserCategoriesFromDialog(),
        _refreshUserColorCategoriesFromDialog()
      ]).then((_) {
        print("  Category Notifiers updated.");
        if (mounted) {
          print(
              "  Component is mounted after category refresh via notifiers.");
          if (newCategoryName != null) {
            print(
                "  Attempting to set selected TEXT category for card $cardId to: $newCategoryName");
            context // UNCOMMENTED
                .read<ReceiveShareProvider>()
                .updateCardTextCategory(cardId, newCategoryName);
          }
        } else {
          print(
              "  Component is NOT mounted after category refresh via notifiers.");
        }
      });
    } else {
      print(
          "ReceiveShareScreen._handleExperienceCardFormUpdate: Non-category/color update. No special action here.");
    }
    // print("ReceiveShareScreen._handleExperienceCardFormUpdate: LOGIC TEMPORARILY COMMENTED OUT"); // REMOVE THIS LINE
  }

  // --- ADDED FOR SCROLLING FAB ---
  void _scrollListener() {
    if (!_scrollController.hasClients || !mounted) return;

    final experienceCardsContext = _experienceCardsSectionKey.currentContext;
    if (experienceCardsContext != null) {
      final RenderBox experienceBox = experienceCardsContext.findRenderObject() as RenderBox;
      final double experienceBoxTopOffsetInViewport = experienceBox.localToGlobal(Offset.zero).dy;
      final double screenHeight = MediaQuery.of(context).size.height;
      final double threshold = screenHeight * 0.60;

      // print("ScrollListener: experienceBoxTopOffsetInViewport: $experienceBoxTopOffsetInViewport, threshold: $threshold"); // DEBUG

      bool shouldShowUpArrow;
      if (experienceBoxTopOffsetInViewport < threshold) {
        shouldShowUpArrow = true;
      } else {
        shouldShowUpArrow = false;
      }

      if (_showUpArrowForFab != shouldShowUpArrow) {
        print("ScrollListener: Changing _showUpArrowForFab to $shouldShowUpArrow"); // DEBUG
        setState(() {
          _showUpArrowForFab = shouldShowUpArrow;
        });
      }
    } else {
      // print("ScrollListener: experienceCardsContext is null"); // DEBUG
    }
  }

  void _handleFabPress() {
    print("FAB_DEBUG: _handleFabPress called. _showUpArrowForFab: $_showUpArrowForFab"); // DEBUG
    if (!_scrollController.hasClients || !mounted) {
      print("FAB_DEBUG: Scroll controller no clients or not mounted. Bailing."); // DEBUG
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus(); // ADDED: Unfocus text fields

    if (_showUpArrowForFab) { // Scroll Up
      print("FAB_DEBUG: Trying to scroll UP."); // DEBUG
      
      // Check for expanded Instagram preview
      if (_isInstagramPreviewExpanded && _currentVisibleInstagramUrl != null && _instagramPreviewKeys.containsKey(_currentVisibleInstagramUrl)) {
        final instagramKey = _instagramPreviewKeys[_currentVisibleInstagramUrl]!;
        final instagramContext = instagramKey.currentContext;
        print("FAB_DEBUG: Instagram preview is expanded. URL: $_currentVisibleInstagramUrl. Context null? ${instagramContext == null}"); // DEBUG
        if (instagramContext != null) {
          print("FAB_DEBUG: Current Scroll Offset before Insta calc: ${_scrollController.offset}"); // DIAGNOSTIC

          final RenderBox instagramRenderBox = instagramContext.findRenderObject() as RenderBox;
          final RenderObject? scrollableRenderObject = _scrollController.position.context.storageContext.findRenderObject();

          if (scrollableRenderObject == null || scrollableRenderObject is! RenderBox) {
            print("FAB_DEBUG: Could not find scrollable RenderBox for Instagram.");
            _scrollToMediaPreviewTop(); // Fallback
            return;
          }
          final RenderBox scrollableBox = scrollableRenderObject;

          // Offset of the Instagram widget relative to the screen
          final double instagramGlobalOffsetY = instagramRenderBox.localToGlobal(Offset.zero).dy;
          // Offset of the Scrollable area itself relative to the screen
          final double scrollableGlobalOffsetY = scrollableBox.localToGlobal(Offset.zero).dy;
          // Offset of the Instagram widget relative to the top of the VISIBLE part of the scrollable area
          final double instagramOffsetYInViewport = instagramGlobalOffsetY - scrollableGlobalOffsetY;
          // Absolute offset of the Instagram widget from the VERY TOP of all scrollable content
          final double instagramTopOffsetInScrollableContent = _scrollController.offset + instagramOffsetYInViewport;
          
          print("FAB_DEBUG: InstaGlobalY: $instagramGlobalOffsetY, ScrollableGlobalY: $scrollableGlobalOffsetY, InstaInViewportY: $instagramOffsetYInViewport");
          print("FAB_DEBUG: Instagram Top in Scrollable Content: $instagramTopOffsetInScrollableContent"); 
          
          const double instagramExpandedHeight = 1200.0;
          double calculatedTargetOffset = instagramTopOffsetInScrollableContent + (instagramExpandedHeight / 2.5);
          print("FAB_DEBUG: Instagram Calculated Target Offset (before clamp): $calculatedTargetOffset");
          
          double targetOffset = calculatedTargetOffset.clamp(0.0, _scrollController.position.maxScrollExtent);

          print("FAB_DEBUG: Scrolling for Instagram. TargetOffset: $targetOffset, MaxScroll: ${_scrollController.position.maxScrollExtent}");
          _scrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );

        } else { // Fallback if key context is lost
          print("FAB_DEBUG: Instagram context was null, falling back to scroll to media preview top."); // DEBUG
          _scrollToMediaPreviewTop();
        }
      } else {
         print("FAB_DEBUG: Not an expanded Instagram preview, or URL/key issue. Scrolling to media preview top."); // DEBUG
         _scrollToMediaPreviewTop();
      }
    } else { // Scroll Down (_showUpArrowForFab is false)
      print("FAB_DEBUG: Trying to scroll DOWN to bottom-most experience card."); // DEBUG
      print("FAB_DEBUG: Current scroll offset: ${_scrollController.offset}"); // DEBUG
      
      // Get the experience cards from provider
      final provider = context.read<ReceiveShareProvider>();
      final experienceCards = provider.experienceCards;
      print("FAB_DEBUG: Number of experience cards: ${experienceCards.length}"); // DEBUG
      
      if (experienceCards.isNotEmpty) {
        final experienceCardsSectionContext = _experienceCardsSectionKey.currentContext;
        print("FAB_DEBUG: Experience cards section context null? ${experienceCardsSectionContext == null}"); // DEBUG
        
        if (experienceCardsSectionContext != null) {
          // Get current position of experience cards section
          final RenderBox experienceBox = experienceCardsSectionContext.findRenderObject() as RenderBox;
          final double experienceBoxTopOffsetInViewport = experienceBox.localToGlobal(Offset.zero).dy;
          final double sectionHeight = experienceBox.size.height;
          print("FAB_DEBUG: Experience cards top offset: $experienceBoxTopOffsetInViewport, section height: $sectionHeight"); // DEBUG
          
          // Calculate position to scroll to show the top of the bottom-most experience card
          // We want to position the last card's TOP at the top of the viewport (below app header)
          final double screenHeight = MediaQuery.of(context).size.height;
          final double appBarHeight = AppBar().preferredSize.height + MediaQuery.of(context).padding.top;
          
          // Estimate the height of each experience card (approximate)
          final int cardCount = experienceCards.length;
          final double estimatedCardHeight = cardCount > 0 ? sectionHeight / cardCount : 400.0;
          
          // Calculate offset to show the LAST card at the top of the visible area
          final double lastCardStartPosition = experienceBoxTopOffsetInViewport + sectionHeight - estimatedCardHeight;
          final double targetScrollOffset = _scrollController.offset + lastCardStartPosition - appBarHeight;
          
          final double clampedOffset = targetScrollOffset.clamp(0.0, _scrollController.position.maxScrollExtent);
          
          print("FAB_DEBUG: Card count: $cardCount, estimated card height: $estimatedCardHeight"); // DEBUG
          print("FAB_DEBUG: Last card start position: $lastCardStartPosition, app bar height: $appBarHeight"); // DEBUG
          
          print("FAB_DEBUG: Target scroll offset: $targetScrollOffset, clamped: $clampedOffset, max: ${_scrollController.position.maxScrollExtent}"); // DEBUG
          
          _scrollController.animateTo(
            clampedOffset,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
          print("FAB_DEBUG: Scrolling to show bottom-most experience card."); // DEBUG
        }
      } else {
        print("FAB_DEBUG: No experience cards available."); // DEBUG
      }
    }
  }

  void _scrollToMediaPreviewTop(){
    final mediaPreviewContext = _mediaPreviewListKey.currentContext; // This is key for the *first* media item.
    print("FAB_DEBUG: _scrollToMediaPreviewTop called. Context null? ${mediaPreviewContext == null}"); // DEBUG
    if (mediaPreviewContext != null) {
      Scrollable.ensureVisible(
        mediaPreviewContext,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.0, // Align to top
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
      print("FAB_DEBUG: Called Scrollable.ensureVisible for media preview top."); // DEBUG
    }
  }

  void _onInstagramExpansionChanged(bool isExpanded, String url) {
    if (mounted) {
      setState(() {
        _isInstagramPreviewExpanded = isExpanded;
        _currentVisibleInstagramUrl = url; // Keep track of the URL for the key
      });
    }
  }
  // --- END ADDED FOR SCROLLING FAB ---

  @override
  Widget build(BuildContext context) {
    print('ReceiveShareScreen build called. Current card count from provider: ${context.watch<ReceiveShareProvider>().experienceCards.length}'); // MODIFIED
    print('ReceiveShareScreen BUILD DEBUG: _currentSharedFiles count=${_currentSharedFiles.length}, _isFullyInitialized=$_isFullyInitialized');

    return _wrapWithWillPopScope(Scaffold(
      appBar: AppBar(
        title: _isSpecialUrl(_currentSharedFiles.isNotEmpty
                ? _extractFirstUrl(_currentSharedFiles.first.path) ?? ''
                : '') 
            ? const Text('Save Shared Content')
            : const Text('Save Shared Content'),
        leading: IconButton(
          icon: Icon(Platform.isIOS ? Icons.arrow_back_ios : Icons.arrow_back),
          onPressed: () {
            print("ReceiveShareScreen: AppBar back button pressed.");
            _sharingService.markShareFlowAsInactive(); 
            if (mounted) { 
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const MainScreen()),
                (Route<dynamic> route) => false, 
              );
            }
          },
        ),
        automaticallyImplyLeading:
            false, 
        actions: [],
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
            : FutureBuilder<List<dynamic>>(
                future: _combinedCategoriesFuture, // MODIFIED: Use stable combined future
                builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
                  // Primary Loading State: Show spinner if the future is null (early init) or still running.
                  if (_combinedCategoriesFuture == null || snapshot.connectionState == ConnectionState.waiting) {
                    // print("FutureBuilder: STATE_WAITING (Future is null or connection is waiting)");
                    return const Center(child: CircularProgressIndicator());
                  }

                  // Error State: If the future completed with an error.
                  if (snapshot.hasError) {
                    // print("FutureBuilder: STATE_ERROR (${snapshot.error})");
                    return Center(
                        child: Text(
                            "Error loading categories: ${snapshot.error}"));
                  }

                  // Data State (Success or Failure to get sufficient data):
                  // Future is done, no error, now check the data itself.
                  if (snapshot.hasData && snapshot.data != null && snapshot.data!.length >= 2) {
                    // Data is present and seems structurally correct.
                    // The lists _userCategories and _userColorCategories should be populated by now.
                    // print("FutureBuilder: STATE_HAS_DATA. Categories loaded: Text=${_userCategories.length}, Color=${_userColorCategories.length}");

                    // Proceed with the main UI build
                    return Column(
                      children: [
                        Expanded(
                          child: Stack( // WRAPPED IN STACK FOR FAB
                            children: [
                              SingleChildScrollView(
                                controller: _scrollController, // ATTACHED SCROLL CONTROLLER
                                padding: const EdgeInsets.only(bottom: 80),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Re-enable the shared files preview list
                                    if (_currentSharedFiles.isEmpty)
                                      const Padding(
                                        padding: EdgeInsets.all(16.0),
                                        child: Center(
                                            child:
                                                Text('No shared content received')),
                                      )
                                    else
                                      Consumer<ReceiveShareProvider>(
                                        key: _mediaPreviewListKey, // MOVED KEY HERE
                                        builder: (context, provider, child) {
                                          final experienceCards = provider.experienceCards;
                                          final firstCard = experienceCards.isNotEmpty
                                              ? experienceCards.first
                                              : null;

                                          return ListView.builder(
                                            padding: EdgeInsets.zero, 
                                            shrinkWrap: true,
                                            physics: const NeverScrollableScrollPhysics(),
                                            itemCount: _currentSharedFiles.length,
                                            itemBuilder: (context, index) {
                                              final file = _currentSharedFiles[index];
                                              
                                              bool isInstagram = false;
                                              bool isTikTok = false;
                                              if (file.type == SharedMediaType.text ||
                                                  file.type == SharedMediaType.url) {
                                                String? url = _extractFirstUrl(file.path);
                                                if (url != null) {
                                                  if (url.contains('instagram.com')) {
                                                    isInstagram = true;
                                                  } else if (url.contains('tiktok.com') || url.contains('vm.tiktok.com')) {
                                                    isTikTok = true;
                                                  }
                                                }
                                              }
                                              final double horizontalPadding =
                                                  (isInstagram || isTikTok) ? 0.0 : 16.0;
                                              final double verticalPadding =
                                                  8.0; 
                                              
                                              return Padding(
                                                key: ValueKey(file.path),
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: horizontalPadding,
                                                  vertical: verticalPadding,
                                                ),
                                                child: Card(
                                                  elevation: 2.0,
                                                  margin: (isInstagram || isTikTok)
                                                      ? EdgeInsets.zero
                                                      : const EdgeInsets.only(
                                                          bottom:
                                                              0), 
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(
                                                        (isInstagram || isTikTok) ? 0 : 8),
                                                  ),
                                                  clipBehavior: (isInstagram || isTikTok)
                                                      ? Clip.antiAlias
                                                      : Clip.none,
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      _buildMediaPreview(
                                                          file, firstCard, index),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          );
                                        }
                                      ),
                                    Selector<ReceiveShareProvider, List<ExperienceCardData>>(
                                      key: const ValueKey('experience_cards_selector'), // Keep this key or change if you prefer
                                      selector: (_, provider) {
                                        // print("ReceiveShareScreen: Selector retrieving cards. Provider HASH: ${provider.hashCode}"); // Can be removed
                                        return provider.experienceCards;
                                      },
                                      shouldRebuild: (previous, next) {
                                        if (previous.length != next.length) {
                                          // print("ReceiveShareScreen: Selector WILL REBUILD (list lengths different).");
                                          return true;
                                        }
                                        for (int i = 0; i < previous.length; i++) {
                                          final pCard = previous[i];
                                          final nCard = next[i];
                                          // Compare relevant fields that determine if UI for a card should change
                                          if (pCard.id != nCard.id ||
                                              pCard.titleController.text != nCard.titleController.text ||
                                              pCard.selectedCategoryId != nCard.selectedCategoryId ||
                                              pCard.selectedColorCategoryId != nCard.selectedColorCategoryId ||
                                              pCard.existingExperienceId != nCard.existingExperienceId || // If it's linked/unlinked
                                              pCard.placeIdForPreview != nCard.placeIdForPreview || // If preview should change
                                              pCard.selectedLocation?.placeId != nCard.selectedLocation?.placeId || // If location changed
                                              pCard.searchController.text != nCard.searchController.text // If search text/displayed location changed
                                              ) {
                                            // print("ReceiveShareScreen: Selector WILL REBUILD (card data different at index $i).");
                                            return true;
                                          }
                                        }
                                        // print("ReceiveShareScreen: Selector WILL NOT REBUILD (lists appear identical by check).");
                                        return false;
                                      },
                                      builder: (context, selectedExperienceCards, child) {
                                        print("ReceiveShareScreen: Selector for _ExperienceCardsSection rebuilding. Cards count: ${selectedExperienceCards.length}");
                                        return _ExperienceCardsSection(
                                          userCategories: _userCategories,
                                          userColorCategories: _userColorCategories,
                                          userCategoriesNotifier: _userCategoriesNotifier,
                                          userColorCategoriesNotifier: _userColorCategoriesNotifier,
                                          removeExperienceCard: _removeExperienceCard,
                                          showLocationPicker: _showLocationPicker,
                                          selectSavedExperienceForCard: _selectSavedExperienceForCard,
                                          handleCardFormUpdate: _handleExperienceCardFormUpdate,
                                          addExperienceCard: _addExperienceCard,
                                          isSpecialUrl: _isSpecialUrl,
                                          extractFirstUrl: _extractFirstUrl,
                                          currentSharedFiles: _currentSharedFiles,
                                          experienceCards: selectedExperienceCards, // Pass selected cards from Selector
                                          sectionKey: _experienceCardsSectionKey, // PASSING THE KEY
                                          onYelpButtonTapped: _trackYelpButtonTapped, // ADDED
                                        );
                                      }
                                    ),
                                  ],
                                ),
                              ),
                              // --- ADDED FAB ---
                              Positioned(
                                bottom: 16, // Adjust as needed
                                right: 16,  // Adjust as needed
                                child: FloatingActionButton(
                                  shape: const CircleBorder(), // ENSURE CIRCULAR
                                  onPressed: _handleFabPress,
                                  child: Icon(_showUpArrowForFab ? Icons.arrow_upward : Icons.arrow_downward),
                                ),
                              ),
                              // --- END ADDED FAB ---
                            ],
                          ),
                        ),
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
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.grey[700],
                                ),
                                child: const Text('Cancel'),
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
                      ],
                    );
                  } else {
                    // Future is done, no error, but data is missing or insufficient.
                    // print("FutureBuilder: STATE_NO_SUFFICIENT_DATA (Done, no error, but data invalid or missing)");
                    return const Center(
                        child: Text("Error: Could not load category data."));
                  }
                },
              ),
      ),
    ));
  }

  Future<void> _launchUrl(String urlString) async {
    Uri url = Uri.parse(urlString);
    
    // Add timestamp to Yelp search URLs to force new navigation
    if (urlString.contains('yelp.com/search')) {
      String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      String separator = urlString.contains('?') ? '&' : '?';
      url = Uri.parse('$urlString${separator}t=$timestamp');
    }
    
    try {
      // For Yelp URLs, try multiple approaches to force new navigation
      bool launched = false;
      
      // First try externalApplication with webOnlyWindowName to force new window/tab
      if (urlString.contains('yelp.com/search')) {
        launched = await launchUrl(url, 
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_blank'
        );
      }
      
      if (!launched) {
        // Try platformDefault as fallback
        launched = await launchUrl(url, mode: LaunchMode.platformDefault);
      }
      
      if (!launched) {
        // Final fallback to externalApplication
        launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      }
      
      if (!launched) {
        print('Could not launch $urlString');
        _showSnackBar(context, 'Could not open link');
      }
    } catch (e) {
      print('Error launching URL: $e');
      _showSnackBar(context, 'Error opening link: $e');
    }
  }

  bool _isValidUrl(String urlString) {
    final Uri? uri = Uri.tryParse(urlString);
    return uri != null && (uri.isScheme('http') || uri.isScheme('https'));
  }

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
      case SharedMediaType.url: 
        return 'URL';
      default:
        return 'Unknown';
    }
  }

  Widget _buildMediaPreview(
      SharedMediaFile file, ExperienceCardData? card, int index) {

    switch (file.type) {
      case SharedMediaType.image:
        return ImagePreviewWidget(file: file);
      case SharedMediaType.video:
        return _buildVideoPreview(file);
      case SharedMediaType.text:
      case SharedMediaType
            .url: 
        return _buildTextPreview(file, card, index);
      case SharedMediaType.file:
      default:
        return _buildFilePreview(file);
    }
  }

  Widget _buildTextPreview(
      SharedMediaFile file, ExperienceCardData? card, int index) {
    String textContent = file.path; 
    String? extractedUrl = _extractFirstUrl(textContent);

    if (extractedUrl != null) {
      return _buildUrlPreview(extractedUrl, card, index, textContent);
    } else {
      return Container(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          textContent,
          maxLines: 5, 
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
  }

  Widget _buildUrlPreview(String url, ExperienceCardData? card, int index, [String? sharedText]) {
    if (card != null &&
        (url.contains('yelp.com/biz') || url.contains('yelp.to/'))) {
      
      return YelpPreviewWidget(
        yelpUrl: url,
        sharedText: sharedText,
        card: card, 
        yelpPreviewFutures: _yelpPreviewFutures,
        getBusinessFromYelpUrl: _getBusinessFromYelpUrl,
        launchUrlCallback: _launchUrl,
        mapsService: _mapsService,
      );
    }

    if (url.contains('google.com/maps') ||
        url.contains('maps.app.goo.gl') ||
        url.contains('goo.gl/maps') ||
        (url.contains('g.co/kgs/') && !url.contains('share.google/'))) {
      return MapsPreviewWidget(
        mapsUrl: url,
        mapsPreviewFutures: _yelpPreviewFutures,
        getLocationFromMapsUrl: _getLocationFromMapsUrl,
        launchUrlCallback: _launchUrl,
        mapsService: _mapsService,
      );
    }

    if (url.contains('instagram.com')) {
      // print("DEBUG: Instagram URL detected, preview temporarily disabled.");
      // return const SizedBox(height: 50, child: Center(child: Text("Instagram Preview Disabled")));
      if (!_instagramPreviewKeys.containsKey(url)) { // Ensure key exists
        _instagramPreviewKeys[url] = GlobalKey();
      }
      // If this is the first media item and it's instagram, update _currentVisibleInstagramUrl
      // This logic is a bit tricky here as _buildMediaPreview is called inside a loop.
      // We set _currentVisibleInstagramUrl more reliably in the ListView builder.
      
      return InstagramPreviewWrapper(
        key: _instagramPreviewKeys[url], // Use the specific key for this Instagram preview
        url: url,
        launchUrlCallback: _launchUrl,
        onExpansionChanged: (isExpanded, instaUrl) => _onInstagramExpansionChanged(isExpanded, instaUrl), // CORRECTED: Match signature
      );
    }

    if (url.contains('tiktok.com') || url.contains('vm.tiktok.com')) {
      return TikTokPreviewWidget(
        url: url,
        launchUrlCallback: _launchUrl,
        onPhotoDetected: (detectedUrl, isPhoto) {
          // Track whether this TikTok URL is a photo carousel
          _tiktokPhotoStatus[detectedUrl] = isPhoto;
          print('TikTok photo detection: URL=$detectedUrl, isPhoto=$isPhoto');
        },
      );
    }

    if (url.contains('facebook.com') || url.contains('fb.com') || url.contains('fb.watch')) {
      return FacebookPreviewWidget(
        url: url,
        height: 500,
        onWebViewCreated: (controller) {
          // Handle controller if needed
        },
        onPageFinished: (url) {
          // Handle page finished if needed
        },
        launchUrlCallback: _launchUrl,
      );
    }

    if (url.contains('youtube.com') || url.contains('youtu.be') || url.contains('youtube.com/shorts')) {
      return YouTubePreviewWidget(
        url: url,
        launchUrlCallback: _launchUrl,
      );
    }

    // Google Knowledge Graph URLs - use WebView
    if (url.contains('g.co/kgs/') || url.contains('share.google/')) {
      print("🔍 URL PREVIEW: Using GoogleKnowledgeGraphPreviewWidget (WebView) for URL: $url");
      return GoogleKnowledgeGraphPreviewWidget(
        url: url,
        launchUrlCallback: _launchUrl,
      );
    }

    return GenericUrlPreviewWidget(
      url: url,
      launchUrlCallback: _launchUrl,
    );
  }

  Widget _buildVideoPreview(SharedMediaFile file) {
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

  Widget _buildFilePreview(SharedMediaFile file) {
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

  Future<void> _processGoogleKnowledgeUrl(String url, SharedMediaFile file) async {
    print('🔍 GOOGLE KG: Processing Google Knowledge Graph URL: $url');
    
    final provider = context.read<ReceiveShareProvider>();
    final firstCard = provider.experienceCards.first;
    
    // Extract and clean entity name from shared text
    String? entityName;
    try {
      final sharedText = file.path;
      final urlIndex = sharedText.indexOf(url);
      if (urlIndex > 0) {
        entityName = sharedText.substring(0, urlIndex).trim();
        // Remove any trailing newlines and clean up
        entityName = _cleanEntityName(entityName);
        print('🔍 GOOGLE KG: Extracted and cleaned entity name: "$entityName"');
      }
    } catch (e) {
      print('🔍 GOOGLE KG: Error extracting entity name: $e');
    }
    
    // First, try to use Knowledge Graph API to get entity information
    if (entityName != null && entityName.isNotEmpty) {
      print('🔍 GOOGLE KG: Searching Knowledge Graph for: "$entityName"');
      final kgResults = await _knowledgeGraphService.searchEntities(entityName, limit: 10);
      
      if (kgResults.isNotEmpty) {
        print('🔍 GOOGLE KG: Found ${kgResults.length} Knowledge Graph results');
        
        // Find the best place entity match
        Map<String, dynamic>? bestPlaceEntity = _findBestPlaceEntity(kgResults, entityName);
        
        if (bestPlaceEntity != null) {
          print('🔍 GOOGLE KG: Found best place entity: ${bestPlaceEntity['name']}');
          print('🔍 GOOGLE KG: Entity types: ${bestPlaceEntity['types']}');
          
          // Extract useful information from Knowledge Graph
          final kgName = bestPlaceEntity['name'] as String?;
          final kgDescription = _knowledgeGraphService.extractDescription(bestPlaceEntity);
          final kgImageUrl = _knowledgeGraphService.extractImageUrl(bestPlaceEntity);
          final kgWebsite = bestPlaceEntity['url'] as String?;
          
          if (kgDescription != null) {
            print('🔍 GOOGLE KG: Description: ${kgDescription.substring(0, min(100, kgDescription.length))}...');
          }
          if (kgWebsite != null) {
            print('🔍 GOOGLE KG: Official website: $kgWebsite');
          }
          
          // Store this information for potential use in the form
          // For now, we'll still search for the place in Google Maps to get location data
          firstCard.originalShareType = ShareType.maps;
          _yelpPreviewFutures[url] = _searchForLocationByNameWithKGDataImproved(
            kgName ?? entityName, 
            url,
            originalEntityName: entityName,
            kgDescription: kgDescription,
            kgImageUrl: kgImageUrl,
            kgWebsite: kgWebsite,
            kgEntity: bestPlaceEntity,
          );
          return;
        } else {
          print('🔍 GOOGLE KG: No suitable place entities found in Knowledge Graph results');
          // Log what types were found instead
          if (kgResults.isNotEmpty) {
            print('🔍 GOOGLE KG: Available results: ${kgResults.map((r) => '${r['name']} (${r['types']})').join(', ')}');
          }
        }
      }
    }
    
    // If Knowledge Graph didn't help, fall back to original logic
    // Try to resolve the shortened URL
    try {
      final resolvedUrl = await _resolveShortUrl(url);
      print('🔍 GOOGLE KG: Resolved URL: $resolvedUrl');
      
      if (resolvedUrl != null && (
          resolvedUrl.contains('google.com/maps') ||
          resolvedUrl.contains('maps.app.goo.gl') ||
          resolvedUrl.contains('goo.gl/maps'))) {
        // It resolved to a Google Maps URL, process it as such
        print('🔍 GOOGLE KG: Resolved to Google Maps URL, processing as Maps');
        firstCard.originalShareType = ShareType.maps;
        // FIXED: Store with original URL key, not resolved URL key
        _yelpPreviewFutures[url] = _getLocationFromMapsUrl(resolvedUrl);
      } else {
        // Didn't resolve to Maps, try to search for the location by name
        print('🔍 GOOGLE KG: Did not resolve to Maps URL, searching by location name');
        if (entityName != null && entityName.isNotEmpty) {
          firstCard.originalShareType = ShareType.maps;
          // Create a future that searches for the location with improved logic
          _yelpPreviewFutures[url] = _searchForLocationByNameImproved(entityName, url);
        } else {
          print('🔍 GOOGLE KG: No location name extracted, treating as generic URL');
          firstCard.originalShareType = ShareType.genericUrl;
        }
      }
    } catch (e) {
      print('🔍 GOOGLE KG: Error processing Google Knowledge URL: $e');
      // Fall back to searching by name if we have it
      if (entityName != null && entityName.isNotEmpty) {
        firstCard.originalShareType = ShareType.maps;
        _yelpPreviewFutures[url] = _searchForLocationByNameImproved(entityName, url);
      }
    }
  }

  // ADDED: Clean entity name to improve search accuracy
  String _cleanEntityName(String rawName) {
    String cleaned = rawName;
    
    // Remove common prefixes that might be added by sharing
    cleaned = cleaned.replaceAll(RegExp(r'^(Check out |Visit |About |)\s*', caseSensitive: false), '');
    
    // Remove URLs and content after blank lines while preserving entity names
    // This handles cases like "Entity Name\n\n https://url" 
    cleaned = cleaned.replaceAll(RegExp(r'\n\s*\n.*$', multiLine: true, dotAll: true), '');
    
    // Remove any remaining URLs that might be on the same line or after single newlines
    cleaned = cleaned.replaceAll(RegExp(r'\n\s*https?://.*$', multiLine: true), '');
    
    // Clean up any remaining trailing whitespace and newlines
    cleaned = cleaned.trim();
    
    // Remove extra punctuation at the end
    cleaned = cleaned.replaceAll(RegExp(r'[,.!?]+$'), '');
    
    print('🔍 GOOGLE KG: Cleaned "$rawName" -> "$cleaned"');
    return cleaned;
  }

  // ADDED: Find the best place entity from Knowledge Graph results
  Map<String, dynamic>? _findBestPlaceEntity(List<Map<String, dynamic>> entities, String originalQuery) {
    Map<String, dynamic>? bestPlace;
    double bestScore = 0.0;
    
    for (final entity in entities) {
      final types = entity['types'] as List<dynamic>? ?? [];
      final name = entity['name'] as String? ?? '';
      final resultScore = (entity['resultScore'] as num?)?.toDouble() ?? 0.0;
      
      // Check if it's a place entity
      if (!_knowledgeGraphService.isPlaceEntity(types)) continue;
      
      // Calculate a relevance score
      double score = resultScore;
      
      // Boost score for exact name matches
      if (name.toLowerCase() == originalQuery.toLowerCase()) {
        score += 1000;
      } else if (name.toLowerCase().contains(originalQuery.toLowerCase()) || 
                 originalQuery.toLowerCase().contains(name.toLowerCase())) {
        score += 500;
      }
      
      // Boost score for more specific place types
      if (types.contains('TouristAttraction') || types.contains('Museum') || 
          types.contains('Park') || types.contains('LandmarksOrHistoricalBuildings')) {
        score += 200;
      } else if (types.contains('Place')) {
        score += 100;
      }
      
      print('🔍 GOOGLE KG: Entity "${entity['name']}" score: $score (types: $types)');
      
      if (score > bestScore) {
        bestScore = score;
        bestPlace = entity;
      }
    }
    
    if (bestPlace != null) {
      print('🔍 GOOGLE KG: Selected best entity: "${bestPlace['name']}" with score: $bestScore');
    }
    
    return bestPlace;
  }

  // IMPROVED: Search for location with better strategies and validation
  Future<Map<String, dynamic>?> _searchForLocationByNameImproved(String locationName, String originalUrl) async {
    print('🔍 GOOGLE KG SEARCH IMPROVED: Searching for location: "$locationName"');
    
    try {
      // Try multiple search strategies
      List<String> searchQueries = _generateSearchQueries(locationName);
      
      for (String query in searchQueries) {
        print('🔍 GOOGLE KG SEARCH IMPROVED: Trying query: "$query"');
        
        // Search without location bias first for famous places
        List<Map<String, dynamic>> results = await _mapsService.searchPlaces(query);
        
        if (results.isNotEmpty) {
          // Find the best match from results
          Map<String, dynamic>? bestResult = _findBestLocationMatch(results, locationName, query);
          
          if (bestResult != null) {
            final placeId = bestResult['placeId'] as String?;
            if (placeId != null && placeId.isNotEmpty) {
              print('🔍 GOOGLE KG SEARCH IMPROVED: Getting details for best match place ID: $placeId');
              final location = await _mapsService.getPlaceDetails(placeId);
              
              if (location != null) {
                final Map<String, dynamic> result = {
                  'location': location,
                  'placeName': location.displayName ?? locationName,
                  'website': location.website,
                  'mapsUrl': originalUrl,
                  'searchQuery': query,
                  'confidence': 'high', // We found a good match
                };
                
                // Fill the form with the found location data
                _fillFormWithGoogleMapsData(
                  location,
                  location.displayName ?? locationName,
                  location.website ?? '',
                  originalUrl
                );
                
                print('🔍 GOOGLE KG SEARCH IMPROVED: ✅ Successfully created result with location data');
                print('🔍 GOOGLE KG SEARCH IMPROVED: Result structure: location=${location.displayName}, placeName=${location.displayName ?? locationName}');
                return result;
              } else {
                print('🔍 GOOGLE KG SEARCH IMPROVED: ⚠️ getPlaceDetails returned null for placeId: $placeId');
              }
            } else {
              print('🔍 GOOGLE KG SEARCH IMPROVED: ⚠️ bestResult missing placeId');
            }
          } else {
            print('🔍 GOOGLE KG SEARCH IMPROVED: ⚠️ No best result found from ${results.length} results');
          }
        } else {
          print('🔍 GOOGLE KG SEARCH IMPROVED: ⚠️ Empty result set for query "$query"');
        }
      }
      
      print('🔍 GOOGLE KG SEARCH IMPROVED: ❌ No suitable location found with any query');
      return null;
    } catch (e) {
      print('🔍 GOOGLE KG SEARCH IMPROVED ERROR: ❌ Exception occurred: $e');
      return null;
    }
  }

  // ADDED: Generate multiple search query variations
  List<String> _generateSearchQueries(String locationName) {
    List<String> queries = [];
    
    // Primary query - exact name
    queries.add(locationName);
    
    // Add variations for better matching
    if (locationName.contains(',')) {
      // Try without everything after the first comma
      queries.add(locationName.split(',')[0].trim());
    }
    
    // If it contains "The", try without it
    if (locationName.toLowerCase().startsWith('the ')) {
      queries.add(locationName.substring(4).trim());
    }
    
    // Add "attraction" or "museum" for tourist spots
    if (!locationName.toLowerCase().contains('museum') && 
        !locationName.toLowerCase().contains('attraction') &&
        !locationName.toLowerCase().contains('park')) {
      queries.add('$locationName attraction');
      queries.add('$locationName museum');
    }
    
    return queries;
  }

  // ADDED: Find the best location match from search results
  Map<String, dynamic>? _findBestLocationMatch(List<Map<String, dynamic>> results, String originalName, String searchQuery) {
    if (results.isEmpty) return null;
    if (results.length == 1) return results[0];
    
    Map<String, dynamic>? bestMatch;
    double bestScore = 0.0;
    
    for (final result in results) {
      final name = result['description'] as String? ?? result['name'] as String? ?? '';
      final types = result['types'] as List<dynamic>? ?? [];
      
      double score = 0.0;
      
      // Exact name match gets highest score
      if (name.toLowerCase() == originalName.toLowerCase()) {
        score += 100.0;
      } else if (name.toLowerCase().contains(originalName.toLowerCase()) || 
                 originalName.toLowerCase().contains(name.toLowerCase())) {
        score += 50.0;
      }
      
      // Boost score for tourist attractions, museums, parks
      if (types.any((type) => ['tourist_attraction', 'museum', 'park', 'establishment'].contains(type))) {
        score += 25.0;
      }
      
      // Prefer results that are not just addresses
      if (!name.contains(RegExp(r'\d+.*\w+\s+(St|Ave|Rd|Dr|Blvd|Way)', caseSensitive: false))) {
        score += 15.0;
      }
      
      print('🔍 GOOGLE KG: Result "$name" score: $score (types: $types)');
      
      if (score > bestScore) {
        bestScore = score;
        bestMatch = result;
      }
    }
    
    // Only return if we have a reasonable confidence
    if (bestScore >= 25.0) {
      print('🔍 GOOGLE KG: Selected best result: "${bestMatch!['description']}" with score: $bestScore');
      return bestMatch;
    }
    
    print('🔍 GOOGLE KG: No result met minimum confidence threshold');
    return null;
  }

  Future<Map<String, dynamic>?> _searchForLocationByNameWithKGDataImproved(
    String locationName, 
    String originalUrl, {
    String? originalEntityName,
    String? kgDescription,
    String? kgImageUrl,
    String? kgWebsite,
    Map<String, dynamic>? kgEntity,
  }) async {
    print('🔍 GOOGLE KG SEARCH+: Searching for location with Knowledge Graph data: "$locationName"');
    
    try {
      // Try multiple search strategies with the KG-enhanced name
      List<String> searchQueries = _generateSearchQueriesWithKGData(
        locationName, 
        originalEntityName, 
        kgEntity
      );
      
      for (String query in searchQueries) {
        print('🔍 GOOGLE KG SEARCH+: Trying query: "$query"');
        
        // Try without location bias first for famous places, then with bias
        List<List<Map<String, dynamic>>> resultSets = [];
        
        // Get user position first for better search accuracy
        Position? userPosition = await _getCurrentPosition();
        
        // First attempt: With location bias (prioritize local/regional results)
        if (userPosition != null) {
          print('🔍 GOOGLE KG SEARCH+: Searching with location bias first (user location: ${userPosition.latitude}, ${userPosition.longitude})');
          List<Map<String, dynamic>> localResults = await _mapsService.searchPlaces(
            query,
            latitude: userPosition.latitude,
            longitude: userPosition.longitude,
            radius: 50000, // 50km radius
          );
          if (localResults.isNotEmpty) {
            resultSets.add(localResults);
          }
        }
        
        // Second attempt: No location bias (for famous places that might be far away)
        print('🔍 GOOGLE KG SEARCH+: Searching without location bias (global search)');
        List<Map<String, dynamic>> globalResults = await _mapsService.searchPlaces(query);
        if (globalResults.isNotEmpty) {
          resultSets.add(globalResults);
        }
        
        // Process both result sets
        for (List<Map<String, dynamic>> results in resultSets) {
          if (results.isNotEmpty) {
            print('🔍 GOOGLE KG SEARCH+: Found ${results.length} results for query "$query"');
            
            // Find the best match using improved scoring
            Map<String, dynamic>? bestResult = _findBestLocationMatchWithKGData(
              results, 
              locationName, 
              originalEntityName ?? locationName,
              kgEntity
            );
            
            if (bestResult != null) {
              final placeId = bestResult['placeId'] as String?;
              if (placeId != null && placeId.isNotEmpty) {
                print('🔍 GOOGLE KG SEARCH+: Getting details for best match place ID: $placeId');
                final location = await _mapsService.getPlaceDetails(placeId);
                
                if (location != null) {
                  // Use Knowledge Graph website if Maps doesn't have one
                  String? finalWebsite = location.website;
                  if ((finalWebsite == null || finalWebsite.isEmpty) && kgWebsite != null) {
                    print('🔍 GOOGLE KG SEARCH+: Using Knowledge Graph website: $kgWebsite');
                    finalWebsite = kgWebsite;
                  }
                  
                  final Map<String, dynamic> result = {
                    'location': location,
                    'placeName': location.displayName ?? locationName,
                    'website': finalWebsite,
                    'mapsUrl': originalUrl,
                    'kgDescription': kgDescription,
                    'kgImageUrl': kgImageUrl,
                    'kgEntity': kgEntity,
                    'searchQuery': query,
                    'confidence': 'high',
                  };
                  
                  // Fill the form with the found location data
                  _fillFormWithGoogleMapsData(
                    location,
                    location.displayName ?? locationName,
                    finalWebsite ?? '',
                    originalUrl
                  );
                  
                  // If we have a KG description, store it in the notes field
                  if (kgDescription != null && mounted) {
                    final provider = context.read<ReceiveShareProvider>();
                    final firstCard = provider.experienceCards.first;
                    if (firstCard.notesController.text.isEmpty) {
                      firstCard.notesController.text = kgDescription;
                      print('🔍 GOOGLE KG SEARCH+: Added Knowledge Graph description to notes');
                    }
                  }
                  
                  print('🔍 GOOGLE KG SEARCH+: ✅ Successfully created result with location data');
                  print('🔍 GOOGLE KG SEARCH+: Result structure: location=${location.displayName}, placeName=${location.displayName ?? locationName}, website=$finalWebsite');
                  return result;
                } else {
                  print('🔍 GOOGLE KG SEARCH+: ⚠️ getPlaceDetails returned null for placeId: $placeId');
                }
              } else {
                print('🔍 GOOGLE KG SEARCH+: ⚠️ bestResult missing placeId: $bestResult');
              }
            } else {
              print('🔍 GOOGLE KG SEARCH+: ⚠️ No best result found from ${results.length} results');
            }
          } else {
            print('🔍 GOOGLE KG SEARCH+: ⚠️ Empty result set received for query "$query"');
          }
        }
      }
      
      print('🔍 GOOGLE KG SEARCH+: ❌ No suitable location found with any query or strategy');
      return null;
    } catch (e) {
      print('🔍 GOOGLE KG SEARCH+ ERROR: ❌ Exception occurred: $e');
      return null;
    }
  }

  // ADDED: Generate search queries enhanced with Knowledge Graph data
  List<String> _generateSearchQueriesWithKGData(
    String kgName, 
    String? originalEntityName, 
    Map<String, dynamic>? kgEntity
  ) {
    List<String> queries = [];
    
    // Primary query - Knowledge Graph name
    queries.add(kgName);
    
    // Original entity name if different
    if (originalEntityName != null && originalEntityName != kgName) {
      queries.add(originalEntityName);
    }
    
    // Extract additional names from KG entity if available
    if (kgEntity != null) {
      final alternateName = kgEntity['alternateName'] as String?;
      if (alternateName != null && !queries.contains(alternateName)) {
        queries.add(alternateName);
      }
    }
    
    // Add variations
    for (String baseQuery in List<String>.from(queries)) {
      // Try without "The" prefix
      if (baseQuery.toLowerCase().startsWith('the ')) {
        String withoutThe = baseQuery.substring(4).trim();
        if (!queries.contains(withoutThe)) {
          queries.add(withoutThe);
        }
      }
      
      // Try without everything after comma
      if (baseQuery.contains(',')) {
        String beforeComma = baseQuery.split(',')[0].trim();
        if (!queries.contains(beforeComma)) {
          queries.add(beforeComma);
        }
      }
      
      // Try adding common location context if not already present
      String baseLower = baseQuery.toLowerCase();
      if (!baseLower.contains(' near ') && !baseLower.contains(' in ')) {
        // Add "near me" variant for local searches
        queries.add('$baseQuery near me');
      }
    }
    
    return queries;
  }

  // ADDED: Enhanced location matching with Knowledge Graph data
  Map<String, dynamic>? _findBestLocationMatchWithKGData(
    List<Map<String, dynamic>> results, 
    String kgName,
    String originalName, 
    Map<String, dynamic>? kgEntity
  ) {
    if (results.isEmpty) return null;
    if (results.length == 1) {
      print('🔍 GOOGLE KG ENHANCED: Only one result found, using it by default');
      return results[0];
    }
    
    Map<String, dynamic>? bestMatch;
    double bestScore = 0.0;
    
    // Get KG entity types for scoring
    List<String> kgTypes = [];
    if (kgEntity != null) {
      final types = kgEntity['types'] as List<dynamic>? ?? [];
      kgTypes = types.cast<String>();
    }
    
    print('🔍 GOOGLE KG ENHANCED: Evaluating ${results.length} results for "$kgName"');
    print('🔍 GOOGLE KG ENHANCED: Knowledge Graph types: $kgTypes');
    
    for (int i = 0; i < results.length; i++) {
      final result = results[i];
      final name = result['description'] as String? ?? result['name'] as String? ?? '';
      final types = result['types'] as List<dynamic>? ?? [];
      final address = result['vicinity'] as String? ?? result['formatted_address'] as String? ?? '';
      
      double score = 0.0;
      List<String> scoreReasons = [];
      
      // Exact name matches get highest scores
      if (name.toLowerCase() == kgName.toLowerCase() || 
          name.toLowerCase() == originalName.toLowerCase()) {
        score += 100.0;
        scoreReasons.add('exact name match (+100)');
      } else if (name.toLowerCase().contains(kgName.toLowerCase()) || 
                 kgName.toLowerCase().contains(name.toLowerCase()) ||
                 name.toLowerCase().contains(originalName.toLowerCase()) || 
                 originalName.toLowerCase().contains(name.toLowerCase())) {
        score += 60.0;
        scoreReasons.add('partial name match (+60)');
      }
      
      // Boost for specific place types that match KG types
      if (kgTypes.contains('TouristAttraction') && 
          types.any((type) => ['tourist_attraction', 'point_of_interest'].contains(type))) {
        score += 40.0;
        scoreReasons.add('tourist attraction type match (+40)');
      } else if (kgTypes.contains('Museum') && 
                 types.any((type) => ['museum', 'establishment'].contains(type))) {
        score += 40.0;
        scoreReasons.add('museum type match (+40)');
      } else if (kgTypes.contains('Park') && 
                 types.any((type) => ['park', 'natural_feature'].contains(type))) {
        score += 40.0;
        scoreReasons.add('park type match (+40)');
      } else if (types.any((type) => ['tourist_attraction', 'museum', 'park', 'establishment'].contains(type))) {
        score += 25.0;
        scoreReasons.add('general place type match (+25)');
      }
      
      // Prefer non-address results for tourist attractions
      if (!name.contains(RegExp(r'\d+.*\w+\s+(St|Ave|Rd|Dr|Blvd|Way)', caseSensitive: false))) {
        score += 20.0;
        scoreReasons.add('not a street address (+20)');
      }
      
      // Boost for establishment type (generally more reliable for places)
      if (types.contains('establishment')) {
        score += 15.0;
        scoreReasons.add('establishment type (+15)');
      }
      
      // Check if result has a rating (indicates it's a real place people visit)
      if (result['rating'] != null) {
        score += 10.0;
        scoreReasons.add('has rating (+10)');
      }
      
      print('🔍 GOOGLE KG ENHANCED [Result ${i+1}]:');
      print('  Name: "$name"');
      print('  Address: "$address"');
      print('  Types: $types');
      print('  Score: $score (${scoreReasons.join(', ')})');
      
      if (score > bestScore) {
        bestScore = score;
        bestMatch = result;
      }
    }
    
    // Require higher confidence for KG-enhanced results
    if (bestScore >= 35.0) {
      print('🔍 GOOGLE KG ENHANCED: ✓ Selected best result: "${bestMatch!['description']}" with score: $bestScore');
      return bestMatch;
    }
    
    print('🔍 GOOGLE KG ENHANCED: ⚠️ No result met minimum confidence threshold (35.0). Best score was: $bestScore');
    // Return the best match anyway if we have one, but log the low confidence
    if (bestMatch != null && bestScore > 0) {
      print('🔍 GOOGLE KG ENHANCED: ⚠️ Returning best match despite low confidence');
      return bestMatch;
    }
    
    return null;
  }

  Future<Map<String, dynamic>?> _getLocationFromMapsUrl(String mapsUrl) async {
    print(
        '🔄 GET MAPS START: _getLocationFromMapsUrl called for URL: $mapsUrl');
    print("🗺️ MAPS PARSE (Simplified): Getting location for URL: $mapsUrl");
    final String originalUrlKey = mapsUrl.trim();

    if (_businessDataCache.containsKey(originalUrlKey)) {
      print("🗺️ MAPS PARSE: Returning cached data for $originalUrlKey");
      return _businessDataCache[originalUrlKey];
    }

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

    if (!resolvedUrl.contains('google.com/maps')) {
      print(
          "🗺️ MAPS PARSE ERROR: URL is not a standard Google Maps URL: $resolvedUrl");
      return null;
    }

    Location? foundLocation;
    String? placeIdToLookup;

    try {
      String searchQuery =
          resolvedUrl; 
      try {
        final Uri uri = Uri.parse(resolvedUrl);
        final placeSegmentIndex = uri.pathSegments.indexOf('place');
        if (placeSegmentIndex != -1 &&
            placeSegmentIndex < uri.pathSegments.length - 1) {
          String placePathInfo = uri.pathSegments[placeSegmentIndex + 1];
          placePathInfo =
              Uri.decodeComponent(placePathInfo).replaceAll('+', ' ');
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
          placeIdToLookup = searchResults.first['placeId'] as String?;
          if (placeIdToLookup != null && placeIdToLookup.isNotEmpty) {
            print(
                "🗺️ MAPS PARSE: Search found Place ID: '$placeIdToLookup'. Getting details.");
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
            foundLocation = null; 
          }
        } else {
          print(
              "🗺️ MAPS PARSE (Query Fallback): No Place ID (cid/placeid) found in query parameters either.");
        }
      }

      if (foundLocation != null) {
        final String finalName = foundLocation.getPlaceName(); 
        final String? finalWebsite = foundLocation.website;

        final provider = context.read<ReceiveShareProvider>();
        if (provider.experienceCards.isNotEmpty) {
          _fillFormWithGoogleMapsData(foundLocation, finalName,
              finalWebsite ?? '', mapsUrl); 
        }

        final Map<String, dynamic> result = {
          'location': foundLocation,
          'placeName': finalName,
          'website': finalWebsite,
          'mapsUrl': mapsUrl, 
        };

        _businessDataCache[originalUrlKey] = result;
        print("🗺️ MAPS PARSE: Successfully processed Maps URL: $mapsUrl");
        return result;
      } else {
        print(
            "🗺️ MAPS PARSE ERROR: Failed to determine location from Maps URL after all strategies: $mapsUrl");
        _businessDataCache[originalUrlKey] = {}; 
        return null; 
      }
    } catch (e) {
      print(
          "🗺️ MAPS PARSE ERROR: Unexpected error processing Google Maps URL $mapsUrl: $e");
      _businessDataCache[originalUrlKey] = {}; 
      return null;
    }
  }

  String? _extractPlaceIdFromMapsUrl(String url) {
    print("🗺️ EXTRACT (Simplified): Parsing URL for Place ID: $url");
    try {
      final Uri uri = Uri.parse(url);
      final queryParams = uri.queryParameters;

      String? placeId = queryParams['cid'] ?? queryParams['placeid'];

      if (placeId != null && placeId.isNotEmpty) {
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

  bool _containsOnlyCoordinates(String text) {
    final coordRegex = RegExp(r'^-?[\d.]+, ?-?[\d.]+$');
    return coordRegex.hasMatch(text.trim());
  }

  // ADDED: Handle low confidence location results
  Future<Location?> _handleLowConfidenceLocationResult(
    List<Map<String, dynamic>> topResults, 
    String entityName
  ) async {
    if (!mounted || topResults.isEmpty) return null;
    
    // Show a dialog with the top location options
    final selectedResult = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Select Location for "$entityName"'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Multiple locations found. Please select the correct one:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              ...topResults.take(3).map((result) {
                final name = result['description'] as String? ?? result['name'] as String? ?? '';
                final address = result['vicinity'] as String? ?? result['formatted_address'] as String? ?? '';
                return ListTile(
                  title: Text(name),
                  subtitle: Text(address, style: TextStyle(fontSize: 12)),
                  onTap: () => Navigator.of(dialogContext).pop(result),
                );
              }).toList(),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Search Manually'),
              onPressed: () => Navigator.of(dialogContext).pop(null),
            ),
          ],
        );
      },
    );
    
    if (selectedResult != null) {
      final placeId = selectedResult['placeId'] as String?;
      if (placeId != null && placeId.isNotEmpty) {
        return await _mapsService.getPlaceDetails(placeId);
      }
    }
    
    return null;
  }

  Future<void> _loadUserColorCategories() async {
    print("_loadUserColorCategories START"); 
    try {
      final colorCategories = await _experienceService.getUserColorCategories();
      print(
          "  _loadUserColorCategories: Service call successful, received ${colorCategories.length} items.");
      if (mounted) {
        _userColorCategories = colorCategories;
        _userColorCategoriesNotifier.value = colorCategories;
        print("  _loadUserColorCategories: Notifier updated.");
      } else {
        print(
            "  _loadUserColorCategories: Component not mounted after service call.");
      }
      _userColorCategoriesFuture = Future.value(colorCategories); // Ensure future resolves to the fetched list
    } catch (error) {
      print("ReceiveShareScreen: Error loading user Color Categories: $error");
      if (mounted) {
        _userColorCategories = [];
        _userColorCategoriesNotifier.value = [];
      }
      _userColorCategoriesFuture = Future.value([]); // Ensure future resolves to an empty list on error
    }
  }

  // --- ADDED: Method to initialize/update the combined future ---
  void _initializeCombinedFuture() {
    // Handles potential nulls from initial load before futures are set
    final f1 = _userCategoriesFuture ?? Future.value([]);
    final f2 = _userColorCategoriesFuture ?? Future.value([]);
    _combinedCategoriesFuture = Future.wait([f1, f2]);
  }
  // --- END ADDED ---

  // ADDED: Helper method for duplicate checking and dialog
  Future<Experience?> _checkForDuplicateExperienceDialog({
    required BuildContext context,
    required ExperienceCardData card,
    String? placeIdToCheck,
    String? titleToCheck,
  }) async {
    if (!mounted) return null;

    final String? currentUserId = _authService.currentUser?.uid;
    if (currentUserId == null) {
      _showSnackBar(context, 'Cannot check for duplicates: User not identified.');
      return null;
    }

    print(
        '_checkForDuplicateExperienceDialog: Checking for card ${card.id}, placeId: $placeIdToCheck, title: $titleToCheck');

    List<Experience> userExperiences = [];
    try {
      userExperiences = await _experienceService.getUserExperiences();
    } catch (e) {
      print('Error fetching user experiences for duplicate check: $e');
      _showSnackBar(context, 'Could not load your experiences to check for duplicates.');
      return null; // Cannot proceed without experiences
    }

    if (!mounted) return null;

    Experience? foundDuplicate;
    String? duplicateReason;

    for (final existingExp in userExperiences) {
      // Skip if checking an existing experience against itself
      if (card.existingExperienceId != null && card.existingExperienceId == existingExp.id) {
        continue;
      }

      bool match = false;
      if (placeIdToCheck != null &&
          placeIdToCheck.isNotEmpty &&
          existingExp.location.placeId == placeIdToCheck) {
        match = true;
        // MODIFIED: duplicateReason no longer needed for specific attribute
        // duplicateReason = 'location (Place ID: $placeIdToCheck)'; 
        print('Duplicate check: Matched by Place ID: ${existingExp.id} - ${existingExp.name}');
      }
      if (!match && 
          titleToCheck != null &&
          titleToCheck.trim().toLowerCase() == existingExp.name.trim().toLowerCase()) {
        match = true;
        // MODIFIED: duplicateReason no longer needed for specific attribute
        // duplicateReason = 'title "${existingExp.name}"';
        print('Duplicate check: Matched by Title: ${existingExp.id} - ${existingExp.name}');
      }

      if (match) {
        foundDuplicate = existingExp;
        break;
      }
    }

    if (foundDuplicate != null) {
      if (!mounted) return null;
      final bool? useExisting = await showDialog<bool>(
        context: context,
        barrierDismissible: false, // User must choose an action
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Potential Duplicate Found'),
            // MODIFIED: Dialog content to show both title and address
            content: Text(
                'You already saved an experience named "${foundDuplicate!.name}" located at "${foundDuplicate.location.address ?? 'No address provided'}." Do you want to use this existing experience?'),
            actions: <Widget>[
              TextButton(
                child: const Text('Create New'),
                onPressed: () {
                  Navigator.of(dialogContext).pop(false); // Don't use existing
                },
              ),
              ElevatedButton(
                child: const Text('Use Existing'),
                onPressed: () {
                  Navigator.of(dialogContext).pop(true); // Use existing
                },
              ),
            ],
          );
        },
      );
      if (useExisting == true) {
        return foundDuplicate;
      }
    }
    return null; // No duplicate found, or user chose to create new
  }
  // END ADDED
}

class InstagramPreviewWrapper extends StatefulWidget {
  final String url;
  final Future<void> Function(String) launchUrlCallback;
  final void Function(bool, String)? onExpansionChanged; // MODIFIED to include URL

  const InstagramPreviewWrapper({
    super.key, // Ensure super.key is passed
    required this.url,
    required this.launchUrlCallback,
    this.onExpansionChanged,
  });

  @override
  _InstagramPreviewWrapperState createState() =>
      _InstagramPreviewWrapperState();
}

class _InstagramPreviewWrapperState extends State<InstagramPreviewWrapper> {
  bool _isExpanded = false; 
  bool _isDisposed = false;
  late WebViewController _controller;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  // Safe setState that checks if the widget is still mounted
  void _safeSetState(Function fn) {
    if (mounted && !_isDisposed) {
      setState(() {
        fn();
      });
    }
  }

  // Safe callback for webview
  void _handleWebViewCreated(WebViewController controller) {
    if (!mounted || _isDisposed) return;
    _controller = controller;
  }

  // Safe callback for page finished
  void _handlePageFinished(String url) {
    // No state updates here, just a pass-through
  }
  
  // Safe callback for URL launching
  Future<void> _handleUrlLaunch(String url) async {
    if (!mounted || _isDisposed) return;
    try {
      await widget.launchUrlCallback(url);
    } catch (e) {
      print("Error in InstagramPreviewWrapper URL launch: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final double height = _isExpanded
        ? 2800.0
        : 840.0; 

    return Column(
      mainAxisSize:
          MainAxisSize.min, 
      children: [
        instagram_widget.InstagramWebView(
          url: widget.url,
          height: height, 
          launchUrlCallback: _handleUrlLaunch,
          onWebViewCreated: _handleWebViewCreated,
          onPageFinished: _handlePageFinished,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(width: 48), 
            IconButton(
              icon: const Icon(FontAwesomeIcons.instagram),
              color: const Color(0xFFE1306C),
              iconSize: 32, 
              tooltip: 'Open in Instagram',
              constraints: const BoxConstraints(),
              padding:
                  EdgeInsets.zero, 
              onPressed: () => _handleUrlLaunch(widget.url),
            ),
            IconButton(
              icon:
                  Icon(_isExpanded ? Icons.fullscreen_exit : Icons.fullscreen),
              iconSize: 24,
              color: Colors.blue,
              tooltip: _isExpanded ? 'Collapse' : 'Expand',
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              onPressed: () {
                _safeSetState(() {
                  _isExpanded = !_isExpanded;
                  widget.onExpansionChanged?.call(_isExpanded, widget.url); // CALL CALLBACK with URL
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
extension LocationNameHelper on Location {
  String getPlaceName() {
    if (displayName != null &&
        displayName!.isNotEmpty &&
        !_containsCoordinates(displayName!)) {
      return displayName!;
    }
    if (address != null) {
      final parts = address!.split(',');
      if (parts.isNotEmpty) {
        return parts.first.trim();
      } 
    }
    return 'Unnamed Location'; 
  }

  bool _containsCoordinates(String text) {
    final coordRegex = RegExp(r'-?[\d.]+ ?, ?-?[\d.]+');
    return coordRegex.hasMatch(text);
  }

}
