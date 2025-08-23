import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'receive_share/widgets/maps_preview_widget.dart';
import 'receive_share/widgets/generic_url_preview_widget.dart';
import 'receive_share/widgets/google_knowledge_graph_preview_widget.dart';
import 'receive_share/widgets/web_url_preview_widget.dart';
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

    return Container(
      color: Colors.white,
      child: Padding(
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
                  onPressed: () { 
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
  final bool requireUrlFirst; // When true, disable content until URL submitted

  const ReceiveShareScreen({
    super.key,
    required this.sharedFiles,
    required this.onCancel,
    this.requireUrlFirst = false,
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
  // URL bar controller and focus node
  late final TextEditingController _sharedUrlController;
  late final FocusNode _sharedUrlFocusNode;
  String? _lastProcessedUrl;
  
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
  final Map<String, GlobalKey> _instagramPreviewKeys = {}; // To store keys for active Instagram previews
  String? _currentVisibleInstagramUrl; // To track which Instagram preview is potentially visible
  // --- END ADDED FOR SCROLLING FAB ---

  // Gate content until URL submitted when required by caller
  bool _urlGateOpen = true;
  bool _didDeferredInit = false;

  Widget _buildSharedUrlBar() {
    // Rebuilds show suffix icons immediately based on controller text
    return StatefulBuilder(
      builder: (context, setInnerState) {
        return Container(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
            controller: _sharedUrlController,
            focusNode: _sharedUrlFocusNode,
            autofocus: widget.requireUrlFirst && !_didDeferredInit,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Shared URL',
              hintText: 'https://... or paste content with a URL',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.link),
              suffixIconConstraints: const BoxConstraints.tightFor(
                width: 120,
                height: 48,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_sharedUrlController.text.isNotEmpty)
                    InkWell(
                      onTap: () {
                        _sharedUrlController.clear();
                        setInnerState(() {});
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: const Padding(
                        padding: EdgeInsets.all(4.0),
                        child: Icon(Icons.clear, size: 22),
                      ),
                    ),
                  if (_sharedUrlController.text.isNotEmpty)
                    const SizedBox(width: 4),
                  InkWell(
                    onTap: () async {
                      await _pasteSharedUrlFromClipboard();
                      setInnerState(() {});
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Icon(Icons.content_paste,
                          size: 22, color: Colors.blue[700]),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: _handleSharedUrlSubmit,
                    borderRadius: BorderRadius.circular(16),
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(4, 4, 8, 4),
                      child:
                          Icon(Icons.arrow_circle_right, size: 22, color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
            onSubmitted: (_) => _handleSharedUrlSubmit(),
            onChanged: (_) {
              setInnerState(() {});
            },
            ),
          ),
        );
      },
    );
  }

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
    super.initState();
    // Initialize URL bar controller and focus
    _sharedUrlController = TextEditingController();
    _sharedUrlFocusNode = FocusNode();
    // _sharingService.isShareFlowActive = true; // REMOVED: This is now set by SharingService.showReceiveShareScreen

    // --- ADDED FOR SCROLLING FAB ---
    _scrollController = ScrollController();
    _scrollController.addListener(_scrollListener);
    // --- END ADDED FOR SCROLLING FAB ---
    // Initialize URL gate
    _urlGateOpen = !widget.requireUrlFirst;

    // Initialize with the files passed to the widget
    _currentSharedFiles = widget.sharedFiles;
    // Inform sharing service that this screen is open so Yelp-only shares update in-place
    try {
      _sharingService.markReceiveShareScreenOpen(context: context);
    } catch (_) {}
    
    // If URL-first mode, auto-focus the URL field on first open
    if (widget.requireUrlFirst) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_didDeferredInit) {
          _sharedUrlFocusNode.requestFocus();
        }
      });
    }
    
    // Check if this is a cold start with only a Yelp URL
    bool isColdStartWithYelpOnly = false;
    if (widget.sharedFiles.length == 1) {
      String? yelpUrl = _extractYelpUrlFromSharedFiles(widget.sharedFiles);
      if (yelpUrl != null) {
        isColdStartWithYelpOnly = true;
      }
    }

    // Initialize Knowledge Graph service
    _initializeKnowledgeGraphService();

    // Register observer for app lifecycle events
    WidgetsBinding.instance.addObserver(this);

    // --- ADDED: Initialize ValueNotifiers ---
    _userCategoriesNotifier = ValueNotifier<List<UserCategory>>(_userCategories);
    _userColorCategoriesNotifier =
        ValueNotifier<List<ColorCategory>>(_userColorCategories);
    // --- END ADDED ---

    // If URL-first mode, defer init until URL is provided

    // If URL-first mode, defer heavy initialization until URL is provided
    if (widget.requireUrlFirst) {
      // Do not call restore/init here; user will unlock by entering a URL
    } else {
      // If cold start with only Yelp URL, try to restore previous content
      if (isColdStartWithYelpOnly) {
        _restoreContentForYelpColdStart();
      } else {
        // Normal initialization
        _initializeScreenDataAndProcessContent();
      }
    }

    // Listen for changes to the sharedFiles controller in SharingService
    _sharingService.sharedFiles.addListener(_handleSharedFilesUpdate);
  }

  Future<void> _initializeScreenDataAndProcessContent() async {
    // Load SharedPreferences
    _prefsInstance = await SharedPreferences.getInstance();

    // Load categories (these methods update _userCategories, _userColorCategories, and their notifiers, and set the futures)
    // Await them to ensure data is available before setting provider deps
    try {
      await _loadUserCategories(); // This already handles setting _userCategoriesFuture and updating _userCategories
      await _loadUserColorCategories(); // This already handles setting _userColorCategoriesFuture and updating _userColorCategories
    } catch (e) {
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
        // TODO: Remove the line below once setDependencies in ReceiveShareProvider is confirmed implemented
        
      } catch (e) {
}
      
      // Initialize the combined future for the FutureBuilder in build()
      // This must be called after _userCategoriesFuture and _userColorCategoriesFuture are (re)set by the _load methods
      _initializeCombinedFuture();

      // Now it's safe to process initial shared content,
      // as the provider (conceptually) has what it needs for default categories.
      _processInitialSharedContent(_currentSharedFiles);
      _syncSharedUrlControllerFromContent();
      
      // Mark as fully initialized
      _isFullyInitialized = true;
    }
  }
  
  // Restore content for cold start with only Yelp URL
  Future<void> _restoreContentForYelpColdStart() async {
    
    // First, get the Yelp URL from the current share
    String? yelpUrl = _extractYelpUrlFromSharedFiles(widget.sharedFiles);
    if (yelpUrl == null) {
      _initializeScreenDataAndProcessContent();
      return;
    }
    
    // Try to restore previous content from persistence
    final restoredContent = await _sharingService.getPersistedCurrentContent();
    if (restoredContent != null && restoredContent.isNotEmpty) {
      
      // Use the restored content as our current files instead of the Yelp-only content
      _currentSharedFiles = restoredContent;
      
      // Persist the Instagram content again to keep it fresh
      await _sharingService.persistCurrentSharedContent(restoredContent);
      
      // Now initialize normally with the restored content
      await _initializeScreenDataAndProcessContent();
      
      // Try to restore form data
      await _restoreFormData();
      
      // After initialization and form restoration, handle the Yelp URL update
      // Wait a bit to ensure cards are created and form data is restored
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) {
        _handleYelpUrlUpdate(yelpUrl, widget.sharedFiles);
      }
    } else {
      _initializeScreenDataAndProcessContent();
    }
    
  }
  
  // Restore form data from persistence
  Future<void> _restoreFormData() async {
    final formData = await _sharingService.getPersistedExperienceCardData();
    if (formData == null || formData['cards'] == null) {
      return;
    }
    
    final provider = context.read<ReceiveShareProvider>();
    final List<dynamic> savedCards = formData['cards'];
    
    // Wait a bit to ensure provider cards are initialized
    await Future.delayed(const Duration(milliseconds: 200));
    
    final currentCards = provider.experienceCards;
    if (currentCards.isEmpty) {
      return;
    }
    
    // Restore data to matching cards
    for (final savedCardData in savedCards) {
      final Map<String, dynamic> cardData = savedCardData as Map<String, dynamic>;
      final String savedId = cardData['id'] ?? '';
      
      // Try to find matching card by ID or use index-based matching
      ExperienceCardData? targetCard;
      final cardIndex = savedCards.indexOf(savedCardData);
      
      // First try to match by ID
      try {
        targetCard = currentCards.firstWhere((card) => card.id == savedId);
      } catch (e) {
        // If no ID match, use index-based matching
        if (cardIndex < currentCards.length) {
          targetCard = currentCards[cardIndex];
        }
      }
      
      if (targetCard != null) {
        // Restore form fields
        targetCard.titleController.text = cardData['title'] ?? '';
        targetCard.yelpUrlController.text = cardData['yelpUrl'] ?? '';
        targetCard.websiteController.text = cardData['website'] ?? '';
        targetCard.notesController.text = cardData['notes'] ?? '';
        targetCard.selectedCategoryId = cardData['selectedCategoryId'];
        targetCard.selectedColorCategoryId = cardData['selectedColorCategoryId'];
        targetCard.selectedOtherCategoryIds = List<String>.from(cardData['selectedOtherCategoryIds'] ?? []);
        targetCard.locationController.text = cardData['locationController'] ?? '';
        targetCard.searchController.text = cardData['searchController'] ?? '';
        targetCard.locationEnabled.value = cardData['locationEnabled'] ?? true;
        targetCard.rating = (cardData['rating'] ?? 0.0).toDouble();
        targetCard.placeIdForPreview = cardData['placeIdForPreview'];
        targetCard.existingExperienceId = cardData['existingExperienceId'];
        
        // Restore location if present
        if (cardData['selectedLocation'] != null) {
          final locData = cardData['selectedLocation'] as Map<String, dynamic>;
          targetCard.selectedLocation = Location(
            latitude: (locData['latitude'] ?? 0.0).toDouble(),
            longitude: (locData['longitude'] ?? 0.0).toDouble(),
            displayName: locData['displayName'],
            address: locData['address'],
            city: locData['city'],
            state: locData['state'],
            country: locData['country'],
            zipCode: locData['zipCode'],
            placeId: locData['placeId'],
          );
          targetCard.location = targetCard.selectedLocation;
        }
        
      }
    }
    
    // Clear the persisted data after restoration
    await _sharingService.clearPersistedExperienceCardData();
    
    // Force a rebuild to show the restored data
    if (mounted) {
      setState(() {});
    }
  }

  // Handle updates to the sharedFiles controller from SharingService
  void _handleSharedFilesUpdate() {
    if (_isProcessingUpdate) {
      // Fluttertoast.showToast(
      //   msg: "DEBUG: Already processing update, ignoring",
      //   toastLength: Toast.LENGTH_SHORT,
      //   gravity: ToastGravity.BOTTOM,
      //   backgroundColor: Colors.grey.withOpacity(0.8),
      //   textColor: Colors.white,
      // );
      return;
    }
    
    final updatedFiles = _sharingService.sharedFiles.value;
    if (updatedFiles != null && 
        updatedFiles.isNotEmpty && 
        !_areSharedFilesEqual(updatedFiles, _currentSharedFiles)) {
      
      // Check if this is a Yelp-only update (only Yelp URL, no other content)
      bool isYelpOnlyUpdate = false;
      String? yelpUrl = _extractYelpUrlFromSharedFiles(updatedFiles);
      if (yelpUrl != null && updatedFiles.length == 1 && _currentSharedFiles.isNotEmpty) {
        // This is a Yelp-only share while we already have content
        isYelpOnlyUpdate = true;
      }
      
      // Special handling for Yelp-only updates - always process them separately
      if (isYelpOnlyUpdate) {
        // Skip all the normal processing and go directly to Yelp URL handling
        _isProcessingUpdate = true;
        
        // Fluttertoast.showToast(
        //   msg: "DEBUG: _handleSharedFilesUpdate called",
        //   toastLength: Toast.LENGTH_LONG,
        //   gravity: ToastGravity.BOTTOM,
        //   backgroundColor: Colors.yellow.withOpacity(0.8),
        //   textColor: Colors.black,
        // );
        
        // Fluttertoast.showToast(
        //   msg: "DEBUG: Yelp-only update - preserving existing content",
        //   toastLength: Toast.LENGTH_LONG,
        //   gravity: ToastGravity.BOTTOM,
        //   backgroundColor: Colors.teal.withOpacity(0.8),
        //   textColor: Colors.white,
        // );
        
        // Handle the Yelp URL update WITHOUT modifying _currentSharedFiles
        _handleYelpUrlUpdate(yelpUrl!, updatedFiles);
        
        // Reset flag after a delay to allow for future updates
        Future.delayed(const Duration(milliseconds: 1000), () {
          _isProcessingUpdate = false;
        });
        return;
      }
      
      _isProcessingUpdate = true;
    
      
      // Fluttertoast.showToast(
      //   msg: "DEBUG: _handleSharedFilesUpdate called",
      //   toastLength: Toast.LENGTH_LONG,
      //   gravity: ToastGravity.BOTTOM,
      //   backgroundColor: Colors.yellow.withOpacity(0.8),
      //   textColor: Colors.black,
      // );
      
      // Check if this is a Yelp URL - if so, treat as update rather than full refresh
      if (yelpUrl != null) {
        // Fluttertoast.showToast(
        //   msg: "DEBUG: Yelp URL in _handleSharedFilesUpdate - routing to update",
        //   toastLength: Toast.LENGTH_LONG,
        //   gravity: ToastGravity.BOTTOM,
        //   backgroundColor: Colors.teal.withOpacity(0.8),
        //   textColor: Colors.white,
        // );
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
        _isProcessingUpdate = false;
        return;
      }
      
      // Check if this is a Yelp URL that should be added to existing card (reuse yelpUrl from above)
      if (yelpUrl != null && _hasExistingCards()) {
        _handleYelpUrlUpdate(yelpUrl, updatedFiles);
        _isProcessingUpdate = false;
        return;
      }
      
      // If not a Yelp URL or no existing cards, proceed with normal reset logic
      final provider = context.read<ReceiveShareProvider>();
      provider.resetExperienceCards();
      
      setState(() {
        _currentSharedFiles = updatedFiles;
        _businessDataCache.clear();
        _yelpPreviewFutures.clear();
      });
      
      // Process the new content
      _processSharedContent(_currentSharedFiles);
      _syncSharedUrlControllerFromContent();
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

  // Sync URL bar from current content
  void _syncSharedUrlControllerFromContent() {
    String initial = '';
    if (_currentSharedFiles.isNotEmpty) {
      final first = _currentSharedFiles.first;
      if (first.type == SharedMediaType.url || first.type == SharedMediaType.text) {
        final extracted = _extractFirstUrl(first.path);
        if (extracted != null && extracted.isNotEmpty) {
          initial = extracted;
        }
      }
    }
    if (_sharedUrlController.text != initial) {
      _sharedUrlController.text = initial;
    }
  }

  // Paste from clipboard, like Yelp field
  Future<void> _pasteSharedUrlFromClipboard() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboardData?.text;
    if (text == null || text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clipboard is empty.')),
        );
      }
      return;
    }
    final url = _extractFirstUrl(text) ?? text.trim();
    _sharedUrlController.text = url;
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pasted from clipboard.'), duration: Duration(seconds: 1)),
      );
    }
    // Automatically submit after paste
    _handleSharedUrlSubmit();
  }

  // Handle submit: normalize URL and refresh preview
  void _handleSharedUrlSubmit() {
    final raw = _sharedUrlController.text.trim();
    if (raw.isEmpty) {
      _showSnackBar(context, 'Enter a URL');
      return;
    }
    String url = _extractFirstUrl(raw) ?? raw;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    final parsed = Uri.tryParse(url);
    if (parsed == null || (!parsed.isScheme('http') && !parsed.isScheme('https'))) {
      _showSnackBar(context, 'Invalid URL');
      return;
    }

    _lastProcessedUrl = url;

    // Update shared files to drive preview
    final updated = List<SharedMediaFile>.from(_currentSharedFiles);
    if (updated.isNotEmpty &&
        (updated.first.type == SharedMediaType.url || updated.first.type == SharedMediaType.text)) {
      updated[0] = SharedMediaFile(path: url, thumbnail: null, duration: null, type: SharedMediaType.url);
    } else {
      updated.insert(0, SharedMediaFile(path: url, thumbnail: null, duration: null, type: SharedMediaType.url));
    }

    setState(() {
      _currentSharedFiles = updated;
      _businessDataCache.clear();
      _yelpPreviewFutures.clear();
      _urlGateOpen = true; // Unlock UI if it was gated
    });

    // On first URL submit in URL-first mode, perform deferred initialization
    if (widget.requireUrlFirst && !_didDeferredInit) {
      _didDeferredInit = true;
      // Immediately dismiss keyboard before kicking heavy init
      _sharedUrlFocusNode.unfocus();
      FocusScope.of(context).unfocus();
      _initializeScreenDataAndProcessContent();
      return; // _initializeScreenDataAndProcessContent will process content
    }

    _processSharedContent(updated);
    
    // Unfocus the text field and hide keyboard
    _sharedUrlFocusNode.unfocus();
    FocusScope.of(context).unfocus();
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
    
    // Fluttertoast.showToast(
    //   msg: "DEBUG: _handleYelpUrlUpdate called, cards=${experienceCards.length}",
    //   toastLength: Toast.LENGTH_LONG,
    //   gravity: ToastGravity.CENTER,
    //   backgroundColor: Colors.red.withOpacity(0.8),
    //   textColor: Colors.white,
    // );
    
    if (experienceCards.isEmpty) {
      // Fluttertoast.showToast(
      //   msg: "DEBUG: No cards yet, retrying in 500ms",
      //   toastLength: Toast.LENGTH_SHORT,
      //   gravity: ToastGravity.CENTER,
      //   backgroundColor: Colors.grey.withOpacity(0.8),
      //   textColor: Colors.white,
      // );
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
    // Fluttertoast.showToast(
    //     msg: "Yelp URL added",
    //     toastLength: Toast.LENGTH_SHORT,
    //     gravity: ToastGravity.BOTTOM,
    //     timeInSecForIosWeb: 1,
    //     backgroundColor: Colors.black.withOpacity(0.7),
    //     textColor: Colors.white,
    //     fontSize: 16.0
    // );
    
    if (previousUrl.isNotEmpty) {
    } else {
    }

    // DON'T update _currentSharedFiles for Yelp URLs - we want to preserve the original preview
    // Only the Yelp URL field should be updated, not the shared files or preview content
  }

  // Method to track when a Yelp button is tapped
  void _trackYelpButtonTapped(String cardId) async {
    _lastYelpButtonTappedCardId = cardId;
    
    // Save form data before navigating to Yelp
    await _saveAllFormData();
    
    // Inform SharingService that we're temporarily leaving for external app
    // This preserves the share flow state instead of resetting it
    _sharingService.temporarilyLeavingForExternalApp();
  }
  
  // Save all form data from all experience cards
  Future<void> _saveAllFormData() async {
    final provider = context.read<ReceiveShareProvider>();
    final experienceCards = provider.experienceCards;
    
    if (experienceCards.isEmpty) return;
    
    // Collect all form data
    final List<Map<String, dynamic>> allCardsData = [];
    
    for (final card in experienceCards) {
      final cardData = {
        'id': card.id,
        'title': card.titleController.text,
        'yelpUrl': card.yelpUrlController.text,
        'website': card.websiteController.text,
        'notes': card.notesController.text,
        'selectedCategoryId': card.selectedCategoryId,
        'selectedColorCategoryId': card.selectedColorCategoryId,
        'selectedOtherCategoryIds': card.selectedOtherCategoryIds,
        'locationController': card.locationController.text,
        'searchController': card.searchController.text,
        'locationEnabled': card.locationEnabled.value,
        'rating': card.rating,
        'placeIdForPreview': card.placeIdForPreview,
        'existingExperienceId': card.existingExperienceId,
      };
      
      // Save location if available
      if (card.selectedLocation != null) {
        cardData['selectedLocation'] = {
          'latitude': card.selectedLocation!.latitude,
          'longitude': card.selectedLocation!.longitude,
          'displayName': card.selectedLocation!.displayName,
          'address': card.selectedLocation!.address,
          'city': card.selectedLocation!.city,
          'state': card.selectedLocation!.state,
          'country': card.selectedLocation!.country,
          'zipCode': card.selectedLocation!.zipCode,
          'placeId': card.selectedLocation!.placeId,
        };
      }
      
      allCardsData.add(cardData);
    }
    
    // Persist all cards data
    await _sharingService.persistExperienceCardData({
      'cards': allCardsData,
      'timestamp': DateTime.now().toIso8601String(),
    });
    
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
    return _experienceService.getUserCategories().then((categories) {
      if (mounted) {
        _userCategories = categories; 
        _userCategoriesNotifier.value = categories; 
        _updateCardDefaultCategoriesIfNeeded(categories); 
      }
    }).catchError((error) {
      if (mounted) {
        _userCategories = [];
        _userCategoriesNotifier.value = [];
      }
    });
  }

  Future<void> _refreshUserColorCategoriesFromDialog() {
    return _experienceService.getUserColorCategories().then((colorCategories) {
      if (mounted) {
        _userColorCategories = colorCategories; 
                  _userColorCategoriesNotifier.value =
              colorCategories; 
        }
      }).catchError((error) {
      if (mounted) {
        _userColorCategories = [];
        _userColorCategoriesNotifier.value = [];
      }
    });
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
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
    // Intent listener setup is now handled by SharingService
  }

  void _initializeKnowledgeGraphService() {
    try {
      // Try to get API key from ApiSecrets
      // ignore: undefined_class, undefined_getter
      String? apiKey = ApiSecrets.googleKnowledgeGraphApiKey;
      _knowledgeGraphService = GoogleKnowledgeGraphService(apiKey: apiKey);
    } catch (e) {
      // ApiSecrets not available, initialize without API key
      _knowledgeGraphService = GoogleKnowledgeGraphService();
    }
  }

  @override
  void dispose() {
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
    _sharedUrlController.dispose();
    _sharedUrlFocusNode.dispose();
    super.dispose();
  }

  Widget _wrapWithWillPopScope(Widget child) {
    return WillPopScope(
      onWillPop: () async {
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
    
    if (files.isEmpty) {
      return;
    }

    // Check if this is a Yelp URL and add debug toast
    String? yelpUrl = _extractYelpUrlFromSharedFiles(files);
    if (yelpUrl != null) {
      // Fluttertoast.showToast(
      //   msg: "DEBUG: Initial processing Yelp URL",
      //   toastLength: Toast.LENGTH_LONG,
      //   gravity: ToastGravity.TOP,
      //   backgroundColor: Colors.purple.withOpacity(0.8),
      //   textColor: Colors.white,
      // );
    }

    // For all content, always use normal processing
    // The Yelp URL handling complexity was causing more issues than it solved
    setState(() {
      _currentSharedFiles = files;
    });
    _processSharedContent(files);
    _syncSharedUrlControllerFromContent();
  }

  void _processSharedContent(List<SharedMediaFile> files) {
    if (files.isEmpty) {
      return;
    }
    
    // Persist the content for potential future restoration (e.g., when returning from Yelp)
    if (!_isYelpUrl(_extractFirstUrl(files.first.path) ?? '')) {
      _sharingService.persistCurrentSharedContent(files);
    }

    final fileFirst = files.first; 

    String? foundUrl;
    for (final file in files) {
      if (file.type == SharedMediaType.text ||
          file.type == SharedMediaType.url) {
        String text = file.path;
        foundUrl = _extractFirstUrl(text);
        if (foundUrl != null) {
          if (_isSpecialUrl(foundUrl)) {
            
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
              
              // Fluttertoast.showToast(
              //   msg: "DEBUG: Yelp in _processSharedContent, cards=${provider.experienceCards.length}, shareFlow=$hasActiveShareFlow",
              //   toastLength: Toast.LENGTH_LONG,
              //   gravity: ToastGravity.CENTER,
              //   backgroundColor: Colors.blue.withOpacity(0.8),
              //   textColor: Colors.white,
              // );
              
              // If we have existing cards OR there's evidence of a previous session, treat as update
              if (provider.experienceCards.isNotEmpty || hasActiveShareFlow) {
                // Fluttertoast.showToast(
                //   msg: "DEBUG: Updating existing card with Yelp URL (cards=${provider.experienceCards.length})",
                //   toastLength: Toast.LENGTH_LONG,
                //   gravity: ToastGravity.CENTER,
                //   backgroundColor: Colors.green.withOpacity(0.8),
                //   textColor: Colors.white,
                // );
                _handleYelpUrlUpdate(yelpUrl, files);
                return;
              } else {
                // Fluttertoast.showToast(
                //   msg: "DEBUG: No existing cards or session, creating new Yelp preview",
                //   toastLength: Toast.LENGTH_LONG,
                //   gravity: ToastGravity.CENTER,
                //   backgroundColor: Colors.orange.withOpacity(0.8),
                //   textColor: Colors.white,
                // );
              }
            }
            
            _processSpecialUrl(
                foundUrl, file); 
            return; 
          } else {
          }
        }
      }
    }

    if (foundUrl == null) {
    } else {
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
      return true;
    }

    return false;
  }

  void _processSpecialUrl(String url, SharedMediaFile file) {
    final provider = context.read<ReceiveShareProvider>();
    if (provider.experienceCards.isEmpty) {
      provider.addExperienceCard();
    }
    final firstCard = provider.experienceCards.first;

    String normalizedUrl = url.trim();
    if (!normalizedUrl.startsWith('http')) {
      normalizedUrl = 'https://$normalizedUrl';
    }

    if (normalizedUrl.contains('yelp.com/biz') ||
        normalizedUrl.contains('yelp.to/')) {
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
      firstCard.originalShareType = ShareType.maps; 
      _yelpPreviewFutures[normalizedUrl] =
          _getLocationFromMapsUrl(normalizedUrl);
    } else if (normalizedUrl.contains('g.co/kgs/') || normalizedUrl.contains('share.google/')) {
      // Google Knowledge Graph URLs are displayed as web previews using GenericUrlPreviewWidget
      firstCard.originalShareType = ShareType.genericUrl;
      // The URL will be displayed in the media preview section using AnyLinkPreview
    } else if (normalizedUrl.contains('facebook.com') ||
               normalizedUrl.contains('fb.com') ||
               normalizedUrl.contains('fb.watch')) {
      // Facebook URLs are handled differently - they're displayed in the preview
      // but don't extract location data like Yelp/Maps
      firstCard.originalShareType = ShareType.genericUrl;
      // The URL will be displayed in the media preview section
    } else {
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
        _showSnackBar(
            context, 'Could not extract location data from the shared URL');
      }
    } catch (e) {
      _showSnackBar(context, 'Error processing Google Maps URL');
    }
  }

  void _addExperienceCard() {
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
    _chainDetectedFromUrl = false;

    final cacheKey = yelpUrl.trim();

    if (_businessDataCache.containsKey(cacheKey)) {
      final cachedData = _businessDataCache[cacheKey];
      return _businessDataCache[cacheKey];
    }

    String url = yelpUrl.trim();

    if (url.isEmpty) {
      return null;
    } else if (!url.startsWith('http')) {
      url = 'https://$url';
    }

    bool isYelpUrl = url.contains('yelp.com') || url.contains('yelp.to');
    if (!isYelpUrl) {
      return null;
    }


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
        try {
          final resolvedUrl = await _resolveShortUrl(url);
          if (resolvedUrl != null &&
              resolvedUrl != url &&
              resolvedUrl.contains('/biz/')) {
            url = resolvedUrl; 
            isShortUrl = false;
          } else {
          }
        } catch (e) {
}
      }

      bool extractedFromUrl = false;
      bool extractedFromSharedText = false;
      
      // First, try to extract business name from shared text if available
      if (sharedText != null) {
        try {
          // Look for any Yelp URL pattern in the shared text (yelp.com or yelp.to)
          RegExp yelpUrlPattern = RegExp(r'https?://(?:www\.)?yelp\.(?:com|to)/[^\s]+');
          Match? urlMatch = yelpUrlPattern.firstMatch(sharedText);
          
          int urlIndex = -1;
          if (urlMatch != null) {
            urlIndex = urlMatch.start;
          } else {
            // Fallback: look for the exact URL we received
            urlIndex = sharedText.indexOf(yelpUrl);
            if (urlIndex != -1) {
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
            } else {
}
          } else {
}
        } catch (e) {
}
      }
      
      // Only try URL parsing if we didn't get a good name from shared text
      if (!extractedFromSharedText && url.contains('/biz/')) {
        final bizPath = url.split('/biz/')[1].split('?')[0];

        bool isChainFromUrl = false;
        final lastPathSegment = bizPath.split('/').last;
        final RegExp numericSuffixRegex = RegExp(r'-(\d+)$');
        final match = numericSuffixRegex.firstMatch(lastPathSegment);
        if (match != null) {
          isChainFromUrl = true;
        }

        List<String> pathParts = bizPath.split('-');

        if (pathParts.isNotEmpty && RegExp(r'^\d+$').hasMatch(pathParts.last)) {
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
          businessName = pathParts.sublist(0, cityStartIndex).join(' ');
        } else {
          businessName = pathParts.join(' ');
        }

        businessName = businessName
            .split(' ')
            .map((word) => word.isNotEmpty
                ? word[0].toUpperCase() + word.substring(1)
                : '')
            .join(' ');


        if (isChainFromUrl) {
          _chainDetectedFromUrl = true;
        }

        final nameParts = businessName.split(' ');
        if (nameParts.isNotEmpty) {
          final lastWord = nameParts.last.toLowerCase();
          if (['restaurant', 'cafe', 'bar', 'grill', 'bakery', 'coffee']
              .contains(lastWord)) {
            businessType = lastWord;
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
            isChainOrGeneric = true;
            break;
          }
        }
      }

      // Try web scraping for additional details if we have a short URL or need more info
      if (isShortUrl || (!extractedFromSharedText && businessName.isEmpty)) {
        try {
          final extraInfo = await _getLocationDetailsFromYelpPage(yelpUrl);
          if (extraInfo != null) {
            if (businessCity.isEmpty &&
                extraInfo['city'] != null &&
                extraInfo['city']!.isNotEmpty) {
              businessCity = extraInfo['city']!;
            }
            if (extraInfo['state'] != null && extraInfo['state']!.isNotEmpty) {
              businessState = extraInfo['state']!;
            }
            // Try to extract business name from scraped page if we still don't have it
            if (businessName.isEmpty && extraInfo['businessName'] != null && extraInfo['businessName']!.isNotEmpty) {
              businessName = extraInfo['businessName']!;
              extractedFromUrl = true;
            }
          }
        } catch (e) {
}
      }

      if (businessName.isEmpty) {
        businessName = "Shared Business";
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

      int searchAttempt = 0;
      Location? foundLocation;
      for (final query in searchQueries) {
        searchAttempt++;

        List<Map<String, dynamic>> results;
        if (userPosition != null) {
          results = await _mapsService.searchPlaces(
            query,
            latitude: userPosition.latitude,
            longitude: userPosition.longitude,
            radius: 50000,
          );
        } else {
          results = await _mapsService.searchPlaces(query);
        }


        if (results.isNotEmpty) {

          int resultIndex = 0;
          if (results.length > 1) {
            resultIndex = _findBestMatch(
                results, businessAddress, businessCity, businessState);
          }

          final placeId = results[resultIndex]['placeId'];
          if (placeId == null || placeId.isEmpty) {
            continue;
          }

          try {
            foundLocation = await _mapsService.getPlaceDetails(placeId);
          } catch (detailsError) {
            continue;
          }


          if (foundLocation.latitude == 0.0 && foundLocation.longitude == 0.0) {
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
              isCorrectBusiness = false;
            } else {
}
          }

          if (isChainOrGeneric && isCorrectBusiness) {
            if (businessCity.isNotEmpty && foundLocation.city != null) {
              String googleCityLower = foundLocation.city!.toLowerCase();
              String yelpCityLower = businessCity.toLowerCase();
              if (!googleCityLower.contains(yelpCityLower) &&
                  !yelpCityLower.contains(googleCityLower)) {
                isCorrectBusiness = false;
              } else {
}
            } else if (businessCity.isNotEmpty && foundLocation.city == null) {
              isCorrectBusiness = false;
            }
          }

          if (isCorrectBusiness) {
            break;
          } else {
            foundLocation = null;
            continue;
          }
        }
      } 

      if (foundLocation == null && isChainOrGeneric && userPosition != null) {
        final nearbyResults = await _mapsService.searchNearbyPlaces(
            userPosition.latitude, userPosition.longitude, 50000, businessName);
        if (nearbyResults.isNotEmpty) {
          final placeId = nearbyResults[0]['placeId'];
          if (placeId != null && placeId.isNotEmpty) {
            try {
              foundLocation = await _mapsService.getPlaceDetails(placeId);
            } catch (detailsError) {
              foundLocation = null;
            }
          } else {
            foundLocation = null;
          }
        } else {
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
        return resultData;
      } else {
        _businessDataCache[cacheKey] = {};
        return null;
      }
    } catch (e, stackTrace) {
      return null;
    }
  }

  Future<String?> _resolveShortUrl(String shortUrl) async {
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
          return finalUrl;
        } else {
          return null; 
        }
      }

      return null; 
    } catch (e) {
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
      return null;
    }
  }

  Future<Position?> _getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      Position? position = await Geolocator.getLastKnownPosition();

      position ??= await Geolocator.getCurrentPosition();

      return position;
    } catch (e) {
      return null;
    }
  }

  int _findBestMatch(List<Map<String, dynamic>> results, String address,
      String city, String state) {
    if (results.isEmpty || results.length == 1) return 0;

    final targetCityLower = city.trim().toLowerCase();

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

      int currentScore = -1;

      if (targetCityLower.isNotEmpty) {
        final extractedCity = _extractCityFromAddress(placeAddress);
        final extractedCityLower = extractedCity.toLowerCase();

        if (extractedCityLower == targetCityLower) {
          currentScore = 2; 
        } else if (placeAddressLower.contains(targetCityLower)) {
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
          currentScore = max(currentScore, 0); 
        }
      }

      if (currentScore > highestScore) {
        highestScore = currentScore;
        bestMatchIndex = i;
      }

      if (highestScore == 2) {
        break;
      }
    }

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
      return; // Early return
    }
    // --- END ADDED ---


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
      }

      if (placeIdKey != null && placeIdKey.isNotEmpty) {
        final Map<String, dynamic> finalData = {
          'location': location,
          'businessName': titleToSet,
          'yelpUrl': yelpUrl,
        };
        _yelpPreviewFutures[placeIdKey] = Future.value(finalData);
      } else {
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
      return; // Early return
    }
    // --- END ADDED ---


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
        }

        final Map<String, dynamic> finalData = {
          'location': location,
          'placeName': titleToSet,
          'website': websiteToSet,
          'mapsUrl': originalMapsUrl,
        };
        _yelpPreviewFutures[placeIdKey] = Future.value(finalData);
      } else {
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
      // Normalize shared paths so that Yelp text shares store only the Yelp URL
      final List<String> uniqueMediaPaths = _currentSharedFiles.map((f) {
        final String original = f.path;
        // For text/url types containing a Yelp link, extract and store only the Yelp URL
        if (f.type == SharedMediaType.text || f.type == SharedMediaType.url) {
          final String? extracted = _extractFirstUrl(original);
          if (extracted != null && _isYelpUrl(extracted)) {
            String url = extracted.trim();
            if (!url.startsWith('http://') && !url.startsWith('https://')) {
              url = 'https://$url';
            }
            return url;
          }
        }
        return original;
      }).toSet().toList();

      final Map<String, String> mediaPathToItemIdMap = {};
      for (final path in uniqueMediaPaths) {
        try {
          SharedMediaItem? existingItem;
          try {
            SharedMediaItem? foundItem =
                await _experienceService.findSharedMediaItemByPath(path);
            if (!mounted) return;

            if (foundItem != null && foundItem.ownerUserId == currentUserId) {
              existingItem = foundItem;
            } else if (foundItem != null) {
            } else {
            }
          } catch (e) {
          }

          if (existingItem != null) {
            mediaPathToItemIdMap[path] = existingItem.id;
          } else {
            
            // Check if this is a TikTok URL and get its photo status
            bool? isTiktokPhoto;
            if (path.contains('tiktok.com') || path.contains('vm.tiktok.com')) {
              isTiktokPhoto = _tiktokPhotoStatus[path];
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
          }
        } catch (e) {
          errors.add(
              "Error processing media: ${path.split('/').last}");
        }
      }

      if (mediaPathToItemIdMap.length != uniqueMediaPaths.length && errors.isEmpty) {
         // If there was an issue creating media items but no errors were added to the list yet (e.g. silent failure)
        errors.add("Error processing some media files.");
      }

      if (errors.isEmpty) { // Only proceed with card processing if media pre-processing was okay
        for (final card in experienceCards) {
          String? targetExperienceId;
          bool isNewExperience = false;
          Experience? currentExperienceData;

          try {

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
successCount++;
            } else {
              isNewExperience = false;
              targetExperienceId = card.existingExperienceId!;
currentExperienceData =
                  await _experienceService.getExperience(targetExperienceId);
              if (!mounted) return;
              if (currentExperienceData == null) {
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
updateCount++;
            }

            final List<String> relevantMediaItemIds = uniqueMediaPaths
                .map((path) => mediaPathToItemIdMap[path])
                .where((id) => id != null)
                .cast<String>()
                .toList();
if (currentExperienceData != null) {
              List<String> existingMediaIds =
                  currentExperienceData.sharedMediaItemIds;
              List<String> finalMediaIds =
                  {...existingMediaIds, ...relevantMediaItemIds}.toList();
              if (isNewExperience ||
                  !DeepCollectionEquality()
                      .equals(existingMediaIds, finalMediaIds)) {
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
if (!isNewExperience && relevantMediaItemIds.isNotEmpty) updateCount--; // Correct if only media was new and no other field changed
              }
            } else {
continue;
            }
for (final mediaItemId in relevantMediaItemIds) {
              try {
                await _experienceService.addExperienceLinkToMediaItem(
                    mediaItemId, targetExperienceId);
                if (!mounted) return;
              } catch (e) {
}
            }
            if (canProcessPublicExperience) {
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
                    allMediaPaths: uniqueMediaPaths);
await _experienceService
                    .createPublicExperience(newPublicExperience);
                if (!mounted) return;
              } else {
await _experienceService.updatePublicExperienceMediaAndMaybeYelp(
                    existingPublicExp.id,
                    uniqueMediaPaths,
                    newYelpUrl: cardYelpUrl.isNotEmpty ? cardYelpUrl : null);
                if (!mounted) return;
              }
            } else {
}
            if (selectedCategoryObject != null) {
              try {
                await _experienceService
                    .updateCategoryLastUsedTimestamp(selectedCategoryObject.id);
                if (!mounted) return;
} catch (e) {
}
            } else {
}
            if (colorCategoryIdToSave != null) {
              try {
                await _experienceService.updateColorCategoryLastUsedTimestamp(
                    colorCategoryIdToSave);
                if (!mounted) return;
} catch (e) {
}
            }
          } catch (e) {
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
} else {
          await prefs.remove(AppConstants.lastUsedCategoryKey);
          if (!mounted) return;
}

        if (lastProcessedCard.selectedColorCategoryId != null) {
          await prefs.setString(AppConstants.lastUsedColorCategoryKey, lastProcessedCard.selectedColorCategoryId!);
          if (!mounted) return;
} else {
          await prefs.remove(AppConstants.lastUsedColorCategoryKey);
          if (!mounted) return;
}

        // ADDED: Save last used other categories
        await prefs.setStringList(AppConstants.lastUsedOtherCategoriesKey, lastProcessedCard.selectedOtherCategoryIds);
        if (!mounted) return;
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
return; // Stop further processing if existing experience is used
        }
      }
      // --- END ADDED ---

      final Location selectedLocation = selectedLocationFromResult; // Use the original variable name for clarity below

      if (isOriginalShareYelp) {
try {
          if (selectedLocation.placeId == null ||
              selectedLocation.placeId!.isEmpty) {
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
});
          }
        } catch (e) {
if (mounted) {
            _showSnackBar(
                context, "Error updating location details from Yelp context: $e");
          }
          provider.updateCardData(card, location: selectedLocation);
        }
      } else {
try {
          if (selectedLocation.placeId == null ||
              selectedLocation.placeId!.isEmpty) {
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
});
          }

} catch (e) {
if (mounted) {
            _showSnackBar(context, "Error updating location details: $e");
          }
          provider.updateCardData(card,
              location: selectedLocation,
              searchQuery: selectedLocation.address ?? 'Selected Location');
        }
      }
    } else {
}
  }

  Future<void> _selectSavedExperienceForCard(ExperienceCardData card) async {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus(); // MODIFIED
    await Future.microtask(() {}); // ADDED

    final selectedExperience = await showModalBottomSheet<Experience>(
      context: context,
      isScrollControlled: true, 
      backgroundColor: Colors.white, 
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
}
  }

  void _handleExperienceCardFormUpdate({
    required String cardId,
    bool refreshCategories = false,
    String? newCategoryName,
    String? selectedColorCategoryId,
    String? newTitleFromCard, // ADDED
  }) async { // Ensured async
final provider = context.read<ReceiveShareProvider>();
    final card = provider.experienceCards.firstWhere((c) => c.id == cardId, orElse: () {
      // This should ideally not happen if cardId is always valid
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
context
          .read<ReceiveShareProvider>()
          .updateCardColorCategory(cardId, selectedColorCategoryId);
    } else if (refreshCategories) { // UNCOMMENTED
Future.wait([
        _refreshUserCategoriesFromDialog(),
        _refreshUserColorCategoriesFromDialog()
      ]).then((_) {
if (mounted) {
if (newCategoryName != null) {
context // UNCOMMENTED
                .read<ReceiveShareProvider>()
                .updateCardTextCategory(cardId, newCategoryName);
          }
        } else {
}
      });
    } else {
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
        setState(() {
          _showUpArrowForFab = shouldShowUpArrow;
        });
      }
    } else {
      // print("ScrollListener: experienceCardsContext is null"); // DEBUG
    }
  }

  void _handleFabPress() {
    if (!_scrollController.hasClients || !mounted) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus(); // ADDED: Unfocus text fields

    if (_showUpArrowForFab) { // Scroll Up
      
      // Check for expanded Instagram preview
      if (_isInstagramPreviewExpanded && _currentVisibleInstagramUrl != null && _instagramPreviewKeys.containsKey(_currentVisibleInstagramUrl)) {
        final instagramKey = _instagramPreviewKeys[_currentVisibleInstagramUrl]!;
        final instagramContext = instagramKey.currentContext;
        if (instagramContext != null) {

          final RenderBox instagramRenderBox = instagramContext.findRenderObject() as RenderBox;
          final RenderObject? scrollableRenderObject = _scrollController.position.context.storageContext.findRenderObject();

          if (scrollableRenderObject == null || scrollableRenderObject is! RenderBox) {
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
          
          
          const double instagramExpandedHeight = 1200.0;
          double calculatedTargetOffset = instagramTopOffsetInScrollableContent + (instagramExpandedHeight / 2.5);
double targetOffset = calculatedTargetOffset.clamp(0.0, _scrollController.position.maxScrollExtent);

_scrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );

        } else { // Fallback if key context is lost
          _scrollToMediaPreviewTop();
        }
      } else {
         _scrollToMediaPreviewTop();
      }
    } else { // Scroll Down (_showUpArrowForFab is false)
      
      // Get the experience cards from provider
      final provider = context.read<ReceiveShareProvider>();
      final experienceCards = provider.experienceCards;
      
      if (experienceCards.isNotEmpty) {
        final experienceCardsSectionContext = _experienceCardsSectionKey.currentContext;
        
        if (experienceCardsSectionContext != null) {
          // Get current position of experience cards section
          final RenderBox experienceBox = experienceCardsSectionContext.findRenderObject() as RenderBox;
          final double experienceBoxTopOffsetInViewport = experienceBox.localToGlobal(Offset.zero).dy;
          final double sectionHeight = experienceBox.size.height;
          
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
          
          
          
          _scrollController.animateTo(
            clampedOffset,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      } else {
      }
    }
  }

  void _scrollToMediaPreviewTop(){
    final mediaPreviewContext = _mediaPreviewListKey.currentContext; // This is key for the *first* media item.
    if (mediaPreviewContext != null) {
      Scrollable.ensureVisible(
        mediaPreviewContext,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.0, // Align to top
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
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
return _wrapWithWillPopScope(Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.white,
        title: _isSpecialUrl(_currentSharedFiles.isNotEmpty
                ? _extractFirstUrl(_currentSharedFiles.first.path) ?? ''
                : '') 
            ? const Text('Save Shared Content')
            : const Text('Save Shared Content'),
        leading: IconButton(
          icon: Icon(Platform.isIOS ? Icons.arrow_back_ios : Icons.arrow_back),
          onPressed: () {
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
      body: Container(
        color: Colors.white,
        child: SafeArea(
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
                      // In URL-first mode, show the UI with URL bar so user can proceed
                      if (widget.requireUrlFirst) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildSharedUrlBar(),
                          ],
                        );
                      }
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
                        _buildSharedUrlBar(),
                        const SizedBox(height: 8),
                        // Gate the rest of content when required
                        Expanded(
                          child: AbsorbPointer(
                            absorbing: !_urlGateOpen,
                            child: Opacity(
                              opacity: _urlGateOpen ? 1.0 : 0.4,
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
                                                  color: Colors.white,
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
                                    Selector<ReceiveShareProvider, List<String>>(
                                      key: const ValueKey('experience_cards_selector'),
                                      selector: (_, provider) {
                                        final cards = provider.experienceCards;
                                        // Build immutable signatures so Selector can detect in-place mutations
                                        return List<String>.generate(cards.length, (i) {
                                          final c = cards[i];
                                          final id = c.id;
                                          final title = c.titleController.text;
                                          final cat = c.selectedCategoryId ?? '';
                                          final colorCat = c.selectedColorCategoryId ?? '';
                                          final existingId = c.existingExperienceId ?? '';
                                          final previewId = c.placeIdForPreview ?? '';
                                          final locId = c.selectedLocation?.placeId ?? '';
                                          final search = c.searchController.text;
                                          return '$id|$title|$cat|$colorCat|$existingId|$previewId|$locId|$search';
                                        });
                                      },
                                      builder: (context, _signatures, child) {
                                        final selectedExperienceCards = context.read<ReceiveShareProvider>().experienceCards;
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
                                          experienceCards: selectedExperienceCards,
                                          sectionKey: _experienceCardsSectionKey,
                                          onYelpButtonTapped: _trackYelpButtonTapped,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              // --- ADDED FAB ---
                              Positioned(
                                bottom: 16, // Adjust as needed
                                right: 16,  // Adjust as needed
                                child: FloatingActionButton(
                                  backgroundColor: Theme.of(context).primaryColor,
                                  foregroundColor: Colors.white,
                                  shape: const CircleBorder(), // ENSURE CIRCULAR
                                  onPressed: _handleFabPress,
                                  child: Icon(_showUpArrowForFab ? Icons.arrow_upward : Icons.arrow_downward),
                                ),
                              ),
                                  // --- END ADDED FAB ---
                                ],
                              ),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 12.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
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
                                  backgroundColor: Theme.of(context).primaryColor,
                                  foregroundColor: Colors.white,
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
_showSnackBar(context, 'Could not open link');
      }
    } catch (e) {
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
    if (url.contains('yelp.com/biz') || url.contains('yelp.to/')) {
      // Render Yelp links as a WebView consistent with GoogleKnowledgeGraphPreviewWidget
      return WebUrlPreviewWidget(
        url: url,
        launchUrlCallback: _launchUrl,
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
}
    } catch (e) {
}
    
    // First, try to use Knowledge Graph API to get entity information
    if (entityName != null && entityName.isNotEmpty) {
final kgResults = await _knowledgeGraphService.searchEntities(entityName, limit: 10);
      
      if (kgResults.isNotEmpty) {
        Map<String, dynamic>? bestPlaceEntity = _findBestPlaceEntity(kgResults, entityName);
        
        if (bestPlaceEntity != null) {
          
          // Extract useful information from Knowledge Graph
          final kgName = bestPlaceEntity['name'] as String?;
          final kgDescription = _knowledgeGraphService.extractDescription(bestPlaceEntity);
          final kgImageUrl = _knowledgeGraphService.extractImageUrl(bestPlaceEntity);
          final kgWebsite = bestPlaceEntity['url'] as String?;
          
          if (kgDescription != null) {
}
          if (kgWebsite != null) {
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
          if (kgResults.isNotEmpty) {
}
        }
      }
    }
    
    // If Knowledge Graph didn't help, fall back to original logic
    // Try to resolve the shortened URL
    try {
      final resolvedUrl = await _resolveShortUrl(url);
if (resolvedUrl != null && (
          resolvedUrl.contains('google.com/maps') ||
          resolvedUrl.contains('maps.app.goo.gl') ||
          resolvedUrl.contains('goo.gl/maps'))) {
        // It resolved to a Google Maps URL, process it as such
firstCard.originalShareType = ShareType.maps;
        // FIXED: Store with original URL key, not resolved URL key
        _yelpPreviewFutures[url] = _getLocationFromMapsUrl(resolvedUrl);
      } else {
        // Didn't resolve to Maps, try to search for the location by name
if (entityName != null && entityName.isNotEmpty) {
          firstCard.originalShareType = ShareType.maps;
          // Create a future that searches for the location with improved logic
          _yelpPreviewFutures[url] = _searchForLocationByNameImproved(entityName, url);
        } else {
firstCard.originalShareType = ShareType.genericUrl;
        }
      }
    } catch (e) {
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
      
if (score > bestScore) {
        bestScore = score;
        bestPlace = entity;
      }
    }
    
    if (bestPlace != null) {
}
    
    return bestPlace;
  }

  // IMPROVED: Search for location with better strategies and validation
  Future<Map<String, dynamic>?> _searchForLocationByNameImproved(String locationName, String originalUrl) async {
try {
      // Try multiple search strategies
      List<String> searchQueries = _generateSearchQueries(locationName);
      
      for (String query in searchQueries) {
        List<Map<String, dynamic>> results = await _mapsService.searchPlaces(query);
        
        if (results.isNotEmpty) {
          // Find the best match from results
          Map<String, dynamic>? bestResult = _findBestLocationMatch(results, locationName, query);
          
          if (bestResult != null) {
            final placeId = bestResult['placeId'] as String?;
            if (placeId != null && placeId.isNotEmpty) {
final location = await _mapsService.getPlaceDetails(placeId);
              
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
              
              return result;
                        } else {
}
          } else {
}
        } else {
}
      }
      
return null;
    } catch (e) {
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
      
if (score > bestScore) {
        bestScore = score;
        bestMatch = result;
      }
    }
    
    // Only return if we have a reasonable confidence
    if (bestScore >= 25.0) {
return bestMatch;
    }
    
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
try {
      // Try multiple search strategies with the KG-enhanced name
      List<String> searchQueries = _generateSearchQueriesWithKGData(
        locationName, 
        originalEntityName, 
        kgEntity
      );
      
      for (String query in searchQueries) {
        List<List<Map<String, dynamic>>> resultSets = [];
        
        // Get user position first for better search accuracy
        Position? userPosition = await _getCurrentPosition();
        
        // First attempt: With location bias (prioritize local/regional results)
        if (userPosition != null) {
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
List<Map<String, dynamic>> globalResults = await _mapsService.searchPlaces(query);
        if (globalResults.isNotEmpty) {
          resultSets.add(globalResults);
        }
        
        // Process both result sets
        for (List<Map<String, dynamic>> results in resultSets) {
          if (results.isNotEmpty) {
            Map<String, dynamic>? bestResult = _findBestLocationMatchWithKGData(
              results, 
              locationName, 
              originalEntityName ?? locationName,
              kgEntity
            );
            
            if (bestResult != null) {
              final placeId = bestResult['placeId'] as String?;
              if (placeId != null && placeId.isNotEmpty) {
final location = await _mapsService.getPlaceDetails(placeId);
                
                // Use Knowledge Graph website if Maps doesn't have one
                String? finalWebsite = location.website;
                if ((finalWebsite == null || finalWebsite.isEmpty) && kgWebsite != null) {
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
}
                }
                
                return result;
                            } else {
}
            } else {
}
          } else {
}
        }
      }
      
return null;
    } catch (e) {
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
      

if (score > bestScore) {
        bestScore = score;
        bestMatch = result;
      }
    }
    
    // Require higher confidence for KG-enhanced results
    if (bestScore >= 35.0) {
return bestMatch;
    }
    
    if (bestMatch != null && bestScore > 0) {
return bestMatch;
    }
    
    return null;
  }

  Future<Map<String, dynamic>?> _getLocationFromMapsUrl(String mapsUrl) async {
    final String originalUrlKey = mapsUrl.trim();

    if (_businessDataCache.containsKey(originalUrlKey)) {
return _businessDataCache[originalUrlKey];
    }

    String resolvedUrl = mapsUrl;
    if (!resolvedUrl.contains('google.com/maps')) {
      try {
        final String? expandedUrl = await _resolveShortUrl(resolvedUrl);
        if (expandedUrl != null && expandedUrl.contains('google.com/maps')) {
          resolvedUrl = expandedUrl;
} else {
return null;
        }
      } catch (e) {
return null;
      }
    }

    if (!resolvedUrl.contains('google.com/maps')) {
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
} else {
}
        } else {
}
      } catch (e) {
}

try {
        List<Map<String, dynamic>> searchResults =
            await _mapsService.searchPlaces(searchQuery);

        if (searchResults.isNotEmpty) {
          placeIdToLookup = searchResults.first['placeId'] as String?;
          if (placeIdToLookup != null && placeIdToLookup.isNotEmpty) {
foundLocation = await _mapsService.getPlaceDetails(placeIdToLookup);
} else {
}
        } else {
}
      } catch (e) {
}

      if (foundLocation == null) {
placeIdToLookup = _extractPlaceIdFromMapsUrl(resolvedUrl);

        if (placeIdToLookup != null && placeIdToLookup.isNotEmpty) {
try {
            foundLocation = await _mapsService.getPlaceDetails(placeIdToLookup);
} catch (e) {
foundLocation = null; 
          }
        } else {
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
return result;
      } else {
_businessDataCache[originalUrlKey] = {}; 
        return null; 
      }
    } catch (e) {
_businessDataCache[originalUrlKey] = {}; 
      return null;
    }
  }

  String? _extractPlaceIdFromMapsUrl(String url) {
try {
      final Uri uri = Uri.parse(url);
      final queryParams = uri.queryParameters;

      String? placeId = queryParams['cid'] ?? queryParams['placeid'];

      if (placeId != null && placeId.isNotEmpty) {
        if (placeId.length > 10 && !placeId.contains(' ')) {
return placeId.trim();
        } else {
return null;
        }
      } else {
return null;
      }
    } catch (e) {
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
              }),
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
try {
      final colorCategories = await _experienceService.getUserColorCategories();
if (mounted) {
        _userColorCategories = colorCategories;
        _userColorCategoriesNotifier.value = colorCategories;
} else {
}
      _userColorCategoriesFuture = Future.value(colorCategories); // Ensure future resolves to the fetched list
    } catch (error) {
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

List<Experience> userExperiences = [];
    try {
      userExperiences = await _experienceService.getUserExperiences();
    } catch (e) {
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
}
      if (!match && 
          titleToCheck != null &&
          titleToCheck.trim().toLowerCase() == existingExp.name.trim().toLowerCase()) {
        match = true;
        // MODIFIED: duplicateReason no longer needed for specific attribute
        // duplicateReason = 'title "${existingExp.name}"';
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
        Container(
          color: Colors.white,
          child: Row(
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
