import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:typed_data';
import '../models/shared_media_compat.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as inapp;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/receive_share_provider.dart';
import '../models/experience.dart';
import '../models/user_category.dart';
import '../models/color_category.dart';
import '../models/share_permission.dart';
import '../models/enums/share_enums.dart';
import '../models/shared_media_item.dart';
import '../services/experience_service.dart';
import '../services/category_ordering_service.dart';
import '../services/google_maps_service.dart';
import '../services/google_knowledge_graph_service.dart';
import '../services/link_location_extraction_service.dart';
import '../models/extracted_location_data.dart';
import '../widgets/google_maps_widget.dart';
import 'location_picker_screen.dart';
import '../services/sharing_service.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'receive_share/widgets/maps_preview_widget.dart';
import 'receive_share/widgets/generic_url_preview_widget.dart';
import 'receive_share/widgets/google_knowledge_graph_preview_widget.dart';
import 'receive_share/widgets/web_url_preview_widget.dart';
import 'receive_share/widgets/yelp_preview_widget.dart';
import 'receive_share/widgets/image_preview_widget.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:shared_preferences/shared_preferences.dart';
import 'receive_share/widgets/experience_card_form.dart';
import '../widgets/select_saved_experience_modal_content.dart'; // Attempting relative import again
import '../widgets/privacy_toggle_button.dart';
import 'receive_share/widgets/privacy_tooltip_icon.dart';
import 'receive_share/widgets/instagram_preview_widget.dart'
    as instagram_widget;
import 'receive_share/widgets/tiktok_preview_widget.dart';
import 'receive_share/widgets/facebook_preview_widget.dart';
import 'receive_share/widgets/youtube_preview_widget.dart';
import 'main_screen.dart';
import '../models/public_experience.dart';
import '../services/auth_service.dart';
import '../services/gemini_service.dart';
import '../services/foreground_scan_service.dart';
import 'package:collection/collection.dart';
import 'package:plendy/config/app_constants.dart';
import '../models/experience_card_data.dart';
// Import ApiSecrets conditionally
import '../config/api_secrets.dart'
    if (dart.library.io) '../config/api_secrets.dart'
    if (dart.library.html) '../config/api_secrets.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
  final List<ExperienceCardData>
      experienceCards; // ADDED: To receive cards directly
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
                        String?
                            newTitleFromCard, // ADDED to match new signature
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
  final CategoryOrderingService _categoryOrderingService =
      CategoryOrderingService();
  final GoogleMapsService _mapsService = GoogleMapsService();
  final SharingService _sharingService = SharingService();
  final LinkLocationExtractionService _locationExtractor =
      LinkLocationExtractionService();
  final ForegroundScanService _foregroundScanService = ForegroundScanService();

  // AI Location Extraction state
  bool _isExtractingLocation = false;
  bool _isProcessingScreenshot = false; // For screenshot-based extraction
  Position? _currentUserPosition; // For location-biased extraction
  
  // Track if AI scan is running
  bool _isAiScanInProgress = false;
  // Store pending scan results to apply when app returns to foreground
  List<ExtractedLocationData>? _pendingScanResults;
  String? _pendingScanSingleMessage; // Toast message for single result
  final ImagePicker _imagePicker = ImagePicker();
  // URL bar controller and focus node
  late final TextEditingController _sharedUrlController;
  late final FocusNode _sharedUrlFocusNode;
  String? _lastProcessedUrl;
  // Track URLs that have been auto-scanned to prevent duplicate scans
  final Set<String> _autoScannedUrls = {};

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
  final GlobalKey _mediaPreviewListKey =
      GlobalKey(); // Key for the first media item/list itself
  final GlobalKey _experienceCardsSectionKey = GlobalKey();
  bool _showUpArrowForFab = false;
  bool _isInstagramPreviewExpanded = false;
  final Map<String, GlobalKey<_InstagramPreviewWrapperState>>
      _instagramPreviewKeys = {};
  final Map<String, GlobalKey<TikTokPreviewWidgetState>> _tiktokPreviewKeys =
      {};
  final Map<String, GlobalKey<YouTubePreviewWidgetState>> _youtubePreviewKeys =
      {};
  final Map<String, GlobalKey<FacebookPreviewWidgetState>>
      _facebookPreviewKeys = {};
  final Map<String, GlobalKey<WebUrlPreviewWidgetState>> _webUrlPreviewKeys =
      {};
  final Map<String, GlobalKey<GoogleKnowledgeGraphPreviewWidgetState>>
      _googleKgPreviewKeys = {};
  String?
      _currentVisibleInstagramUrl; // To track which Instagram preview is potentially visible
  // --- END ADDED FOR SCROLLING FAB ---

  // Custom vibration method for longer, heavier feedback
  Future<void> _heavyVibration() async {
    try {
      // For Android: Use platform channel to vibrate for 500ms
      if (Platform.isAndroid) {
        await SystemChannels.platform.invokeMethod('HapticFeedback.vibrate', 500);
      } else if (Platform.isIOS) {
        // For iOS: Use multiple heavy impacts with delay
        await HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 100));
        await HapticFeedback.heavyImpact();
      } else {
        // Fallback for other platforms
        await HapticFeedback.vibrate();
        await Future.delayed(const Duration(milliseconds: 200));
        await HapticFeedback.vibrate();
      }
    } catch (e) {
      // Fallback to basic vibration if platform method fails
      await HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 200));
      await HapticFeedback.vibrate();
    }
  }

  // Gate content until URL submitted when required by caller
  bool _urlGateOpen = true;
  bool _didDeferredInit = false;
  bool _sharedMediaIsPrivate = false;

  Widget _buildSharedUrlBar({required bool showInstructions}) {
    // Rebuilds show suffix icons immediately based on controller text
    return StatefulBuilder(
      builder: (context, setInnerState) {
        final instructionStyle = Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Colors.grey[700]);
        return Container(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _sharedUrlController,
                  focusNode: _sharedUrlFocusNode,
                  autofocus: widget.requireUrlFirst && !_didDeferredInit,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: 'Shared URL',
                    hintText: 'https://... or paste content with a URL',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.link),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                    suffixIconConstraints: const BoxConstraints.tightFor(
                      width: 120,
                      height: 40,
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
                            child: Icon(Icons.arrow_circle_right,
                                size: 22, color: Colors.blue),
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
                if (showInstructions) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Paste any link you want to save to Plendy—from Instagram, TikTok, YouTube, Facebook, or any webpage!',
                    style: instructionStyle,
                  ),
                ],
                // Screenshot Upload Buttons - Always visible
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildScreenshotUploadButton(),
                    // For generic URLs, show "Scan Locations" instead of "Scan Preview"
                    _isGenericWebUrl() ? _buildScanPageContentButtonInRow() : _buildScanCurrentPreviewButton(),
                  ],
                ),
                // Scan All Locations button (only show below for non-generic URLs)
                if (!_isGenericWebUrl()) _buildScanPageContentButton(),
                // AI Location Extraction loading indicator
                if (_isExtractingLocation) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.blue[700]!),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '🤖 AI finding locations...',
                          style: TextStyle(
                            color: Colors.blue[800],
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Screenshot processing loading indicator
                if (_isProcessingScreenshot) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.purple[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purple[200]!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.purple[700]!),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '📷 Plendy AI analyzing...',
                          style: TextStyle(
                            color: Colors.purple[800],
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Build the screenshot upload button widget
  Widget _buildScreenshotUploadButton() {
    final isLoading = _isProcessingScreenshot || _isExtractingLocation;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: OutlinedButton.icon(
          onPressed: isLoading ? null : _showScreenshotUploadOptions,
          icon: Icon(
            Icons.add_photo_alternate_outlined,
            size: 20,
            color: isLoading ? Colors.grey : Colors.purple[700],
          ),
          label: const Text(
            'Upload Screenshot',
            style: TextStyle(
              fontWeight: FontWeight.w500,
            ),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            side: BorderSide(
              color: isLoading ? Colors.grey[300]! : Colors.purple[300]!,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }

  /// Check if current URL is a generic web URL (not social media)
  bool _isGenericWebUrl() {
    final url = _currentSharedFiles.isNotEmpty
        ? _extractFirstUrl(_currentSharedFiles.first.path)
        : null;
    return url != null &&
        url.startsWith('http') &&
        !_isInstagramUrl(url) &&
        !_isTikTokUrl(url) &&
        !_isYouTubeUrl(url) &&
        !_isFacebookUrl(url) &&
        !_isGoogleKnowledgeGraphUrl(url);
  }

  /// Build the scan current preview button widget
  Widget _buildScanCurrentPreviewButton() {
    // Hide for generic web URLs (they use "Scan Locations" instead)
    if (_isGenericWebUrl()) return const SizedBox.shrink();

    final isLoading = _isProcessingScreenshot || _isExtractingLocation;
    final hasPreview = _hasActivePreview();

    // Determine button text based on URL type
    // Use "Scan Screen" for YouTube and Facebook Reels (where auto-extraction doesn't work well)
    final url = _currentSharedFiles.isNotEmpty
        ? _extractFirstUrl(_currentSharedFiles.first.path)
        : null;
    final isYouTubeUrl = url != null && _isYouTubeUrl(url);
    final isFacebookReel = url != null && 
        (url.contains('facebook.com/reel/') || url.contains('facebook.com/reels/'));
    final buttonText = (isYouTubeUrl || isFacebookReel) ? 'Scan Screen' : 'Scan Preview';

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: OutlinedButton.icon(
          onPressed: (isLoading || !hasPreview) ? null : _scanCurrentPreview,
          icon: Icon(
            Icons.screenshot_monitor,
            size: 20,
            color: (isLoading || !hasPreview) ? Colors.grey : Colors.blue[700],
          ),
          label: Text(
            buttonText,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
            ),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            side: BorderSide(
              color: (isLoading || !hasPreview)
                  ? Colors.grey[300]!
                  : Colors.blue[300]!,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }

  /// Build the scan page content button widget for the Row (replaces "Scan Preview" for generic URLs)
  Widget _buildScanPageContentButtonInRow() {
    final isLoading = _isProcessingScreenshot || _isExtractingLocation;
    final hasPreview = _hasActivePreview();

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: OutlinedButton.icon(
          onPressed: (isLoading || !hasPreview) ? null : _scanPageContent,
          icon: Icon(
            Icons.article_outlined,
            size: 20,
            color: (isLoading || !hasPreview) ? Colors.grey : Colors.purple[700],
          ),
          label: const Text(
            'Scan Locations',
            style: TextStyle(
              fontWeight: FontWeight.w500,
            ),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            side: BorderSide(
              color: (isLoading || !hasPreview)
                  ? Colors.grey[300]!
                  : Colors.purple[300]!,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }

  /// Build the scan page content button widget (for articles with multiple locations)
  /// Shows below the Row for non-generic URLs
  Widget _buildScanPageContentButton() {
    // Only show below Row for non-generic URLs (generic URLs show it in the Row)
    if (_isGenericWebUrl()) return const SizedBox.shrink();
    
    final isLoading = _isProcessingScreenshot || _isExtractingLocation;
    final hasPreview = _hasActivePreview();
    // Only show for generic web URLs (not social media)
    final url = _currentSharedFiles.isNotEmpty
        ? _extractFirstUrl(_currentSharedFiles.first.path)
        : null;
    final isWebUrl = url != null &&
        url.startsWith('http') &&
        !_isInstagramUrl(url) &&
        !_isTikTokUrl(url) &&
        !_isYouTubeUrl(url) &&
        !_isFacebookUrl(url);

    // Don't show button if not a web URL
    if (!isWebUrl) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.only(left: 4, top: 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: (isLoading || !hasPreview) ? null : _scanPageContent,
          icon: Icon(
            Icons.article_outlined,
            size: 20,
            color: (isLoading || !hasPreview) ? Colors.grey : Colors.purple[700],
          ),
          label: Text(
            'Scan Locations',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: (isLoading || !hasPreview) ? Colors.grey : Colors.purple[700],
            ),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            side: BorderSide(
              color: (isLoading || !hasPreview)
                  ? Colors.grey[300]!
                  : Colors.purple[300]!,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }

  /// Show options dialog for screenshot upload (camera/gallery)
  void _showScreenshotUploadOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Container(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_awesome, color: Colors.purple[600]),
                          const SizedBox(width: 8),
                          const Text(
                            'AI Location from Screenshot',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Upload a screenshot or take a photo. AI will find locations from captions, tagged places, and visible text.',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.photo_library, color: Colors.blue[700]),
                  ),
                  title: const Text('Choose from Gallery'),
                  subtitle: const Text('Select an existing screenshot'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickScreenshotFromGallery();
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.camera_alt, color: Colors.green[700]),
                  ),
                  title: const Text('Take a Photo'),
                  subtitle:
                      const Text('Capture text or sign with location info'),
                  onTap: () {
                    Navigator.pop(context);
                    _takePhotoForLocation();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Pick a screenshot from gallery
  Future<void> _pickScreenshotFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );

      if (image != null) {
        await _processScreenshotForLocations(File(image.path));
      }
    } catch (e) {
      print('❌ SCREENSHOT: Error picking image from gallery: $e');
      Fluttertoast.showToast(
        msg: 'Error selecting image',
        backgroundColor: Colors.red,
      );
    }
  }

  /// Take a photo for location extraction
  Future<void> _takePhotoForLocation() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );

      if (image != null) {
        await _processScreenshotForLocations(File(image.path));
      }
    } catch (e) {
      print('❌ SCREENSHOT: Error taking photo: $e');
      Fluttertoast.showToast(
        msg: 'Error taking photo',
        backgroundColor: Colors.red,
      );
    }
  }

  /// Check if there's an active preview (any URL) that can be scanned
  bool _hasActivePreview() {
    if (_currentSharedFiles.isEmpty) return false;
    final url = _extractFirstUrl(_currentSharedFiles.first.path);
    if (url == null) return false;
    // Check if it's any URL that would have a WebView preview
    return _isInstagramUrl(url) ||
        _isTikTokUrl(url) ||
        _isFacebookUrl(url) ||
        _isYouTubeUrl(url) ||
        _isSocialMediaUrl(url) ||
        url.startsWith('http'); // Any web URL
  }

  /// Scan the current preview WebView content using AI
  /// For Instagram, uses combined scan (screenshot + text extraction) for better results
  Future<void> _scanCurrentPreview() async {
    if (_isProcessingScreenshot || _isExtractingLocation) return;

    // Check if this is an Instagram URL - use combined scan for better results
    final url = _currentSharedFiles.isNotEmpty
        ? _extractFirstUrl(_currentSharedFiles.first.path)
        : null;
    final isInstagram = url != null && _isInstagramUrl(url);
    
    if (isInstagram) {
      // Use combined scan for Instagram - runs both OCR and text extraction
      print('📷 SCAN PREVIEW: Using combined scan for Instagram...');
      return _scanPreviewCombined();
    }

    // For other platforms, use standard screenshot-only scan
    setState(() {
      _isProcessingScreenshot = true;
      _isAiScanInProgress = true;
    });

    // Enable wakelock to prevent screen from sleeping during AI scan
    WakelockPlus.enable();
    
    // Start foreground service to keep app alive during scan
    await _foregroundScanService.startScanService();

    try {
      print('📷 SCAN PREVIEW: Capturing WebView content...');

      // Try to capture the WebView screenshot from any active preview
      Uint8List? screenshotBytes = await _tryCaptureaActiveWebView();

      if (screenshotBytes == null || screenshotBytes.isEmpty) {
        Fluttertoast.showToast(
          msg:
              '📷 Could not capture preview. Try uploading a screenshot instead.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.orange[700],
        );
        return;
      }

      print(
          '📷 SCAN PREVIEW: Captured ${screenshotBytes.length} bytes, sending to AI...');

      // Get user location for better results
      LatLng? userLocation;
      if (_currentUserPosition != null) {
        userLocation = LatLng(
          _currentUserPosition!.latitude,
          _currentUserPosition!.longitude,
        );
      }

      // Process the captured image
      final result = await _locationExtractor.extractLocationsFromImageBytes(
        screenshotBytes,
        mimeType: 'image/png',
        userLocation: userLocation,
      );
      final locations = result.locations;

      // Check if mounted - if not, store results to apply when app resumes
      if (!mounted) {
        if (locations.isNotEmpty) {
          print('📷 SCAN PREVIEW: App backgrounded, storing ${locations.length} result(s) for later');
          _pendingScanResults = locations;
          if (locations.length == 1) {
            _pendingScanSingleMessage = '📷 Found: ${locations.first.name}';
          }
        }
        return;
      }

      if (locations.isEmpty) {
        print('⚠️ SCAN PREVIEW: No locations found in preview');
        Fluttertoast.showToast(
          msg:
              '📷 No locations found. Try pausing video on text, or upload a screenshot.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.orange[700],
        );
        return;
      }

      print('✅ SCAN PREVIEW: Found ${locations.length} location(s)');

      // Heavy vibration to notify user scan completed
      _heavyVibration();

      final provider = context.read<ReceiveShareProvider>();

      if (locations.length == 1) {
        await _applySingleExtractedLocation(locations.first, provider);
        Fluttertoast.showToast(
          msg: '📷 Found: ${locations.first.name}',
          toastLength: Toast.LENGTH_SHORT,
          backgroundColor: Colors.green,
        );
      } else {
        await _handleMultipleExtractedLocations(locations, provider);
      }
    } catch (e) {
      print('❌ SCAN PREVIEW ERROR: $e');
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Error scanning preview',
          backgroundColor: Colors.red,
        );
      }
    } finally {
      // Disable wakelock and stop foreground service
      WakelockPlus.disable();
      await _foregroundScanService.stopScanService();
      if (mounted) {
        setState(() {
          _isProcessingScreenshot = false;
          _isAiScanInProgress = false;
        });
      }
    }
  }

  /// Scan the entire page content to extract ALL locations
  /// Useful for articles like "50 best restaurants" or travel guides
  Future<void> _scanPageContent() async {
    if (_isProcessingScreenshot || _isExtractingLocation) return;

    setState(() {
      _isProcessingScreenshot = true;
      _isAiScanInProgress = true;
    });

    // Enable wakelock to prevent screen from sleeping during AI scan
    WakelockPlus.enable();
    
    // Start foreground service to keep app alive during scan
    await _foregroundScanService.startScanService();

    try {
      print('📄 SCAN PAGE: Extracting page content...');

      // Get the URL for context
      final url = _currentSharedFiles.isNotEmpty
          ? _extractFirstUrl(_currentSharedFiles.first.path)
          : null;

      // Try to extract page content from the active WebView
      String? pageContent = await _tryExtractPageContent();

      if (pageContent == null || pageContent.isEmpty) {
        Fluttertoast.showToast(
          msg: '📄 Could not extract page content. Try the screenshot scan instead.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.orange[700],
        );
        return;
      }

      print('📄 SCAN PAGE: Extracted ${pageContent.length} characters, sending to Gemini...');

      // Get user location for better results
      LatLng? userLocation;
      if (_currentUserPosition != null) {
        userLocation = LatLng(
          _currentUserPosition!.latitude,
          _currentUserPosition!.longitude,
        );
      }

      // Process with Gemini
      final geminiService = GeminiService();
      final result = await geminiService.extractLocationsFromWebPage(
        pageContent,
        pageUrl: url,
        userLocation: userLocation,
      );

      // Convert Gemini results to ExtractedLocationData first (doesn't need mounted)
      List<ExtractedLocationData> locations = [];
      if (result != null && result.locations.isNotEmpty) {
        print('✅ SCAN PAGE: Found ${result.locations.length} location(s)');
        for (final loc in result.locations) {
          final hasPlaceId = loc.placeId.isNotEmpty;
          final hasCoords = loc.coordinates.latitude != 0 || loc.coordinates.longitude != 0;
          print('   📍 ${loc.name} (placeId: ${hasPlaceId ? "✓" : "✗"}, coords: ${hasCoords ? "✓" : "✗"})');
        }

        locations = result.locations.map((loc) {
          // Infer place type from the types list
          final placeType = ExtractedLocationData.inferPlaceType(loc.types);
          
          // Check if we have valid coordinates (not 0,0 which is our fallback)
          final hasValidCoords = loc.coordinates.latitude != 0 || loc.coordinates.longitude != 0;
          
          // Determine confidence based on whether we have grounding data
          final hasGrounding = loc.placeId.isNotEmpty;
          final confidence = hasGrounding ? 0.9 : (hasValidCoords ? 0.7 : 0.5);
          
          return ExtractedLocationData(
            name: loc.name,
            address: loc.formattedAddress,
            placeId: loc.placeId.isNotEmpty ? loc.placeId : null,
            coordinates: hasValidCoords ? loc.coordinates : null, // Don't use (0,0) coordinates
            type: placeType,
            source: hasGrounding ? ExtractionSource.geminiGrounding : ExtractionSource.placesSearch,
            confidence: confidence,
            googleMapsUri: loc.uri,
            placeTypes: loc.types,
          );
        }).toList();
      }

      // Check if mounted - if not, store results to apply when app resumes
      if (!mounted) {
        if (locations.isNotEmpty) {
          print('📄 SCAN PAGE: App backgrounded, storing ${locations.length} result(s) for later');
          _pendingScanResults = locations;
          if (locations.length == 1) {
            _pendingScanSingleMessage = '📄 Found: ${locations.first.name}';
          }
        }
        return;
      }

      if (locations.isEmpty) {
        print('⚠️ SCAN PAGE: No locations found in page content');
        Fluttertoast.showToast(
          msg: '📄 No locations found on this page.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.orange[700],
        );
        return;
      }

      // Heavy vibration to notify user scan completed
      _heavyVibration();

      final provider = context.read<ReceiveShareProvider>();

      if (locations.length == 1) {
        await _applySingleExtractedLocation(locations.first, provider);
        Fluttertoast.showToast(
          msg: '📄 Found: ${locations.first.name}',
          toastLength: Toast.LENGTH_SHORT,
          backgroundColor: Colors.green,
        );
      } else {
        // Show selection dialog for multiple locations
        await _handleMultipleExtractedLocations(locations, provider);
      }
    } catch (e) {
      print('❌ SCAN PAGE ERROR: $e');
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Error scanning page content',
          backgroundColor: Colors.red,
        );
      }
    } finally {
      // Disable wakelock and stop foreground service
      WakelockPlus.disable();
      await _foregroundScanService.stopScanService();
      if (mounted) {
        setState(() {
          _isProcessingScreenshot = false;
          _isAiScanInProgress = false;
        });
      }
    }
  }

  /// Combined scan that runs BOTH screenshot OCR AND text extraction
  /// This gives better results for Instagram by:
  /// 1. Screenshot OCR catches text overlays on videos/images
  /// 2. Text extraction gets captions, handles, and uses Maps grounding for accuracy
  Future<void> _scanPreviewCombined() async {
    if (_isProcessingScreenshot || _isExtractingLocation) return;

    setState(() {
      _isProcessingScreenshot = true;
      _isAiScanInProgress = true;
    });

    // Enable wakelock to prevent screen from sleeping during AI scan
    WakelockPlus.enable();
    
    // Start foreground service to keep app alive during scan (prevents interruption when minimized)
    await _foregroundScanService.startScanService();

    try {
      print('🔄 COMBINED SCAN: Starting both screenshot and text extraction...');

      final url = _currentSharedFiles.isNotEmpty
          ? _extractFirstUrl(_currentSharedFiles.first.path)
          : null;

      // Get user location for better results
      LatLng? userLocation;
      if (_currentUserPosition != null) {
        userLocation = LatLng(
          _currentUserPosition!.latitude,
          _currentUserPosition!.longitude,
        );
      }

      // Run both extraction methods in parallel
      final results = await Future.wait([
        _extractLocationsFromScreenshot(userLocation),
        _extractLocationsFromPageText(url, userLocation),
      ]);

      final screenshotLocations = results[0];
      final textLocations = results[1];

      print('🔄 COMBINED SCAN: Screenshot found ${screenshotLocations.length} location(s)');
      print('🔄 COMBINED SCAN: Text extraction found ${textLocations.length} location(s)');

      // Merge results first (doesn't need mounted)
      // Prefer text extraction (grounded) results over screenshot (OCR)
      // Text extraction results have Maps grounding and are more accurate
      final mergedLocations = _mergeExtractedLocations(textLocations, screenshotLocations);
      
      print('🔄 COMBINED SCAN: Merged to ${mergedLocations.length} unique location(s)');

      // Check if mounted - if not, store results to apply when app resumes
      if (!mounted) {
        if (mergedLocations.isNotEmpty) {
          print('🔄 COMBINED SCAN: App backgrounded, storing ${mergedLocations.length} result(s) for later');
          _pendingScanResults = mergedLocations;
          if (mergedLocations.length == 1) {
            _pendingScanSingleMessage = '📷 Found: ${mergedLocations.first.name}';
          }
        }
        return;
      }

      if (mergedLocations.isEmpty) {
        print('⚠️ COMBINED SCAN: No locations found from either method');
        Fluttertoast.showToast(
          msg: '📷 No locations found. Try pausing video on text, or upload a screenshot.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.orange[700],
        );
        return;
      }

      // Heavy vibration to notify user scan completed
      _heavyVibration();

      final provider = context.read<ReceiveShareProvider>();

      if (mergedLocations.length == 1) {
        await _applySingleExtractedLocation(mergedLocations.first, provider);
        Fluttertoast.showToast(
          msg: '📷 Found: ${mergedLocations.first.name}',
          toastLength: Toast.LENGTH_SHORT,
          backgroundColor: Colors.green,
        );
      } else {
        await _handleMultipleExtractedLocations(mergedLocations, provider);
      }
    } catch (e) {
      print('❌ COMBINED SCAN ERROR: $e');
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Error scanning preview',
          backgroundColor: Colors.red,
        );
      }
    } finally {
      // Disable wakelock and stop foreground service
      WakelockPlus.disable();
      await _foregroundScanService.stopScanService();
      if (mounted) {
        setState(() {
          _isProcessingScreenshot = false;
          _isAiScanInProgress = false;
        });
      }
    }
  }

  /// Extract locations from screenshots using OCR
  /// For Instagram, captures BOTH native screen AND WebView screenshots and analyzes them TOGETHER
  Future<List<ExtractedLocationData>> _extractLocationsFromScreenshot(LatLng? userLocation) async {
    try {
      final url = _currentSharedFiles.isNotEmpty
          ? _extractFirstUrl(_currentSharedFiles.first.path)
          : null;
      final isInstagram = url != null && _isInstagramUrl(url);
      
      List<Uint8List> screenshots = [];
      
      if (isInstagram && url != null) {
        // For Instagram: capture BOTH native screen AND WebView screenshots
        print('📷 COMBINED SCAN: Capturing both screenshots for Instagram...');
        screenshots = await _captureInstagramBothScreenshots(url);
      } else {
        // For other platforms: use standard capture
        print('📷 COMBINED SCAN: Capturing screenshot...');
        final screenshotBytes = await _tryCaptureaActiveWebView();
        if (screenshotBytes != null && screenshotBytes.isNotEmpty) {
          screenshots.add(screenshotBytes);
        }
      }
      
      if (screenshots.isEmpty) {
        print('⚠️ COMBINED SCAN: Could not capture any screenshots');
        return [];
      }

      // ========== MULTI-IMAGE COMBINED ANALYSIS ==========
      // When we have multiple screenshots (especially for Instagram), analyze them TOGETHER
      // This is critical for content where:
      // - One screenshot shows a sign/name (e.g., "POET TREES")
      // - Another screenshot shows context (e.g., "library in Big Sur")
      // Together, they can identify "Henry Miller Memorial Library"
      
      if (screenshots.length > 1) {
        print('📷 COMBINED SCAN: Using multi-image combined analysis for ${screenshots.length} screenshots...');
        
        // Convert to the format expected by multi-image extraction
        final imageList = screenshots.map((bytes) => (
          bytes: bytes,
          mimeType: 'image/png',
        )).toList();
        
        final result = await _locationExtractor.extractLocationsFromMultipleImages(
          imageList,
          userLocation: userLocation,
        );
        
        print('📷 COMBINED SCAN: Multi-image analysis found ${result.locations.length} location(s)');
        if (result.regionContext != null) {
          print('🌍 COMBINED SCAN: Region context: "${result.regionContext}"');
        }
        
        return result.locations;
      }

      // ========== SINGLE IMAGE ANALYSIS ==========
      // For single screenshots, use the standard single-image analysis
      print('📷 COMBINED SCAN: Using single-image analysis...');
      
      final result = await _locationExtractor.extractLocationsFromImageBytes(
        screenshots.first,
        mimeType: 'image/png',
        userLocation: userLocation,
      );
      
      print('📷 COMBINED SCAN: Single-image analysis found ${result.locations.length} location(s)');
      return result.locations;
    } catch (e) {
      print('⚠️ COMBINED SCAN: Screenshot extraction error: $e');
      return [];
    }
  }

  /// Check if a location is a duplicate of any in the list
  bool _isDuplicateLocation(ExtractedLocationData loc, List<ExtractedLocationData> existingList) {
    final normalizedName = (loc.name ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    
    for (final existing in existingList) {
      // Check place ID match
      if (loc.placeId != null && existing.placeId != null && loc.placeId == existing.placeId) {
        return true;
      }
      
      // Check name similarity
      final existingNormalized = (existing.name ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (normalizedName.isNotEmpty && existingNormalized.isNotEmpty) {
        // Exact match is definitely a duplicate
        if (normalizedName == existingNormalized) {
          return true;
        }
        
        // For containment matches, require the shorter name to be at least 80% of the 
        // longer name's length to avoid false positives like "Ruru Kamakura" vs "Kamakura"
        // (8/12 = 67% < 80%, so NOT a duplicate)
        if (normalizedName.contains(existingNormalized) || existingNormalized.contains(normalizedName)) {
          final shorterLen = normalizedName.length < existingNormalized.length 
              ? normalizedName.length 
              : existingNormalized.length;
          final longerLen = normalizedName.length > existingNormalized.length 
              ? normalizedName.length 
              : existingNormalized.length;
          final ratio = shorterLen / longerLen;
          
          // Only consider it a duplicate if names are very similar in length (80%+ ratio)
          if (ratio >= 0.80) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Extract locations from page text content using Gemini with Maps grounding
  Future<List<ExtractedLocationData>> _extractLocationsFromPageText(String? url, LatLng? userLocation) async {
    try {
      print('📄 COMBINED SCAN: Extracting page text...');
      final pageContent = await _tryExtractPageContent();
      
      if (pageContent == null || pageContent.isEmpty) {
        print('⚠️ COMBINED SCAN: Could not extract page content');
        return [];
      }

      print('📄 COMBINED SCAN: Extracted ${pageContent.length} chars, analyzing with Gemini...');
      
      final geminiService = GeminiService();
      final result = await geminiService.extractLocationsFromWebPage(
        pageContent,
        pageUrl: url,
        userLocation: userLocation,
      );

      if (result == null || result.locations.isEmpty) {
        print('⚠️ COMBINED SCAN: Gemini found no locations in text');
        return [];
      }

      // Convert Gemini results to ExtractedLocationData
      return result.locations.map((loc) {
        final placeType = ExtractedLocationData.inferPlaceType(loc.types);
        final hasValidCoords = loc.coordinates.latitude != 0 || loc.coordinates.longitude != 0;
        final hasGrounding = loc.placeId.isNotEmpty;
        final confidence = hasGrounding ? 0.9 : (hasValidCoords ? 0.7 : 0.5);
        
        return ExtractedLocationData(
          name: loc.name,
          address: loc.formattedAddress,
          placeId: loc.placeId.isNotEmpty ? loc.placeId : null,
          coordinates: hasValidCoords ? loc.coordinates : null,
          type: placeType,
          source: hasGrounding ? ExtractionSource.geminiGrounding : ExtractionSource.placesSearch,
          confidence: confidence,
          googleMapsUri: loc.uri,
          placeTypes: loc.types,
        );
      }).toList();
    } catch (e) {
      print('⚠️ COMBINED SCAN: Text extraction error: $e');
      return [];
    }
  }

  /// Merge two lists of locations, preferring grounded results and removing duplicates
  List<ExtractedLocationData> _mergeExtractedLocations(
    List<ExtractedLocationData> primary,
    List<ExtractedLocationData> secondary,
  ) {
    final merged = <ExtractedLocationData>[];
    final seenPlaceIds = <String>{};
    final seenNames = <String>{};
    
    // Helper to normalize names for comparison
    String normalizeName(String name) {
      return name.toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '')
          .trim();
    }
    
    // Helper to check if two names are similar enough to be considered duplicates
    // Requires 80% length similarity for containment matches to avoid false positives
    // like "Ruru Kamakura" vs "Kamakura" (8/12 = 67% < 80%, so NOT a duplicate)
    bool isSimilarName(String name, Set<String> existingNames) {
      if (name.isEmpty) return false;
      
      for (final seen in existingNames) {
        // Exact match is definitely a duplicate
        if (name == seen) return true;
        
        // For containment matches, require high similarity
        if (seen.contains(name) || name.contains(seen)) {
          final shorterLen = name.length < seen.length ? name.length : seen.length;
          final longerLen = name.length > seen.length ? name.length : seen.length;
          final ratio = shorterLen / longerLen;
          
          // Only consider it a duplicate if names are very similar in length (80%+ ratio)
          if (ratio >= 0.80) return true;
        }
      }
      return false;
    }
    
    // Add primary (grounded) results first - they're more accurate
    for (final loc in primary) {
      final normalizedName = normalizeName(loc.name ?? '');
      
      // Skip if we've seen this place ID
      if (loc.placeId != null && seenPlaceIds.contains(loc.placeId)) {
        continue;
      }
      
      // Skip if we've seen a very similar name
      if (isSimilarName(normalizedName, seenNames)) {
        continue;
      }
      
      merged.add(loc);
      if (loc.placeId != null) seenPlaceIds.add(loc.placeId!);
      if (normalizedName.isNotEmpty) seenNames.add(normalizedName);
    }
    
    // Add secondary (OCR) results that aren't duplicates
    for (final loc in secondary) {
      final normalizedName = normalizeName(loc.name ?? '');
      
      // Skip if we've seen this place ID
      if (loc.placeId != null && seenPlaceIds.contains(loc.placeId)) {
        print('🔄 MERGE: Skipping duplicate placeId: ${loc.name}');
        continue;
      }
      
      // Skip if we've seen a very similar name (fuzzy match with 80% threshold)
      if (isSimilarName(normalizedName, seenNames)) {
        print('🔄 MERGE: Skipping duplicate name: ${loc.name}');
        continue;
      }
      
      merged.add(loc);
      if (loc.placeId != null) seenPlaceIds.add(loc.placeId!);
      if (normalizedName.isNotEmpty) seenNames.add(normalizedName);
    }
    
    return merged;
  }

  /// Try to extract text content from the active WebView
  Future<String?> _tryExtractPageContent() async {
    if (_currentSharedFiles.isEmpty) return null;

    final url = _extractFirstUrl(_currentSharedFiles.first.path);
    if (url == null) return null;

    print('📄 SCAN PAGE: Attempting to extract content for URL: $url');

    // Try Google KG preview first
    if (_isGoogleKnowledgeGraphUrl(url)) {
      final previewKey = _googleKgPreviewKeys[url];
      if (previewKey?.currentState != null) {
        try {
          final content = await previewKey!.currentState!.extractPageContent();
          if (content != null && content.isNotEmpty) {
            print('✅ SCAN PAGE: Extracted content from Google KG preview');
            return content;
          }
        } catch (e) {
          print('⚠️ SCAN PAGE: Google KG content extraction failed: $e');
        }
      }
    }

    // Try Facebook preview
    if (_isFacebookUrl(url)) {
      final facebookPreviewKey = _facebookPreviewKeys[url];
      if (facebookPreviewKey?.currentState != null) {
        try {
          final content = await facebookPreviewKey!.currentState!.extractPageContent();
          if (content != null && content.isNotEmpty) {
            print('✅ SCAN PAGE: Extracted content from Facebook preview');
            return content;
          }
        } catch (e) {
          print('⚠️ SCAN PAGE: Facebook content extraction failed: $e');
        }
      }
    }

    // Try Web URL preview
    final webPreviewKey = _webUrlPreviewKeys[url];
    if (webPreviewKey?.currentState != null) {
      try {
        final content = await webPreviewKey!.currentState!.extractPageContent();
        if (content != null && content.isNotEmpty) {
          print('✅ SCAN PAGE: Extracted content from Web URL preview');
          return content;
        }
      } catch (e) {
        print('⚠️ SCAN PAGE: Web URL content extraction failed: $e');
      }
    }

    print('⚠️ SCAN PAGE: No content could be extracted');
    return null;
  }

  /// Try to capture the active WebView content from any preview type
  Future<Uint8List?> _tryCaptureaActiveWebView() async {
    if (_currentSharedFiles.isEmpty) return null;

    final url = _extractFirstUrl(_currentSharedFiles.first.path);
    if (url == null) return null;

    print('📷 SCAN PREVIEW: Attempting to capture preview for URL: $url');

    // Try each preview type in order
    if (_isInstagramUrl(url)) {
      return await _captureInstagramPreview(url);
    } else if (_isTikTokUrl(url)) {
      return await _captureTikTokPreview(url);
    } else if (_isYouTubeUrl(url)) {
      return await _captureYouTubePreview(url);
    } else if (_isFacebookUrl(url)) {
      return await _captureFacebookPreview(url);
    } else if (_isGoogleKnowledgeGraphUrl(url)) {
      return await _captureGoogleKgPreview(url);
    } else if (url.startsWith('http')) {
      return await _captureWebUrlPreview(url);
    }

    print('⚠️ SCAN PREVIEW: No matching preview type found');
    return null;
  }

  /// Capture Instagram preview - returns WebView screenshot (for backward compatibility)
  /// For combined scan, use _captureInstagramBothScreenshots instead
  Future<Uint8List?> _captureInstagramPreview(String url) async {
    final previewKey = _instagramPreviewKeys[url];
    if (previewKey == null) {
      print('⚠️ SCAN PREVIEW: No Instagram preview key found');
      return null;
    }

    final state = previewKey.currentState;
    if (state != null) {
      try {
        final screenshot = await state.takeScreenshot();
        if (screenshot != null) {
          print(
              '✅ SCAN PREVIEW: Captured Instagram WebView (${screenshot.length} bytes)');
          return screenshot;
        }
      } catch (e) {
        print('⚠️ SCAN PREVIEW: Instagram takeScreenshot failed: $e');
      }
    }
    return null;
  }

  /// Capture BOTH native screen AND WebView screenshot for Instagram
  /// Returns a list of screenshots for comprehensive analysis
  Future<List<Uint8List>> _captureInstagramBothScreenshots(String url) async {
    final screenshots = <Uint8List>[];
    
    // 1. Try native screen capture (captures entire device screen including video frames)
    try {
      print('📷 SCAN PREVIEW: Taking native screen capture for Instagram...');
      
      final result = await _screenshotChannel.invokeMethod('captureScreen');
      
      if (result != null) {
        Uint8List pngBytes;
        if (result is Uint8List) {
          pngBytes = result;
        } else if (result is List) {
          pngBytes = Uint8List.fromList(result.cast<int>());
        } else {
          print('⚠️ SCAN PREVIEW: Unexpected native result type: ${result.runtimeType}');
        }
        
        if (result is Uint8List || result is List) {
          final bytes = result is Uint8List ? result : Uint8List.fromList((result as List).cast<int>());
          print('✅ SCAN PREVIEW: Captured native screen for Instagram (${bytes.length} bytes)');
          screenshots.add(bytes);
        }
      } else {
        print('⚠️ SCAN PREVIEW: Native screenshot returned null');
      }
    } on PlatformException catch (e) {
      print('⚠️ SCAN PREVIEW: Native screenshot failed: ${e.message}');
    } catch (e) {
      print('⚠️ SCAN PREVIEW: Native screenshot error: $e');
    }
    
    // 2. Also capture WebView screenshot (may capture different content)
    try {
      print('📷 SCAN PREVIEW: Taking WebView screenshot for Instagram...');
      final previewKey = _instagramPreviewKeys[url];
      if (previewKey != null) {
        final state = previewKey.currentState;
        if (state != null) {
          final webviewScreenshot = await state.takeScreenshot();
          if (webviewScreenshot != null) {
            print('✅ SCAN PREVIEW: Captured Instagram WebView (${webviewScreenshot.length} bytes)');
            screenshots.add(webviewScreenshot);
          }
        }
      }
    } catch (e) {
      print('⚠️ SCAN PREVIEW: WebView screenshot failed: $e');
    }
    
    print('📷 SCAN PREVIEW: Captured ${screenshots.length} screenshot(s) for Instagram');
    return screenshots;
  }

  /// Capture TikTok preview WebView
  Future<Uint8List?> _captureTikTokPreview(String url) async {
    final previewKey = _tiktokPreviewKeys[url];
    if (previewKey == null) {
      print('⚠️ SCAN PREVIEW: No TikTok preview key found');
      return null;
    }

    final state = previewKey.currentState;
    if (state != null) {
      try {
        final screenshot = await state.takeScreenshot();
        if (screenshot != null) {
          print(
              '✅ SCAN PREVIEW: Captured TikTok WebView (${screenshot.length} bytes)');
          return screenshot;
        }
      } catch (e) {
        print('⚠️ SCAN PREVIEW: TikTok takeScreenshot failed: $e');
      }
    }
    return null;
  }

  /// Platform channel for native screenshot
  static const MethodChannel _screenshotChannel = MethodChannel('com.plendy.app/screenshot');

  /// Capture YouTube preview using native screen capture
  /// This captures the entire device screen including WebView video content
  Future<Uint8List?> _captureYouTubePreview(String url) async {
    try {
      print('📷 SCAN PREVIEW: Taking native screen capture for YouTube...');
      
      // Use native platform screenshot to capture the entire screen
      // This includes WebView content and video frames
      final result = await _screenshotChannel.invokeMethod('captureScreen');
      
      if (result != null) {
        Uint8List pngBytes;
        if (result is Uint8List) {
          pngBytes = result;
        } else if (result is List) {
          pngBytes = Uint8List.fromList(result.cast<int>());
        } else {
          print('⚠️ SCAN PREVIEW: Unexpected result type: ${result.runtimeType}');
          return await _captureYouTubeWebViewFallback(url);
        }
        
        print('✅ SCAN PREVIEW: Captured native screen (${pngBytes.length} bytes, PNG format)');
        
        // No file is saved - the image stays in memory only
        return pngBytes;
      } else {
        print('⚠️ SCAN PREVIEW: Native screenshot returned null');
        return await _captureYouTubeWebViewFallback(url);
      }
    } on PlatformException catch (e) {
      print('⚠️ SCAN PREVIEW: Native screenshot failed: ${e.message}');
      return await _captureYouTubeWebViewFallback(url);
    } catch (e) {
      print('⚠️ SCAN PREVIEW: Native screenshot error: $e');
      return await _captureYouTubeWebViewFallback(url);
    }
  }

  /// Fallback to WebView screenshot for YouTube if native screen capture fails
  Future<Uint8List?> _captureYouTubeWebViewFallback(String url) async {
    print('📷 SCAN PREVIEW: Trying WebView fallback for YouTube...');
    final previewKey = _youtubePreviewKeys[url];
    if (previewKey == null) {
      print('⚠️ SCAN PREVIEW: No YouTube preview key found for fallback');
      return null;
    }

    final state = previewKey.currentState;
    if (state != null) {
      try {
        final screenshot = await state.takeScreenshot();
        if (screenshot != null) {
          print(
              '✅ SCAN PREVIEW: Captured YouTube WebView fallback (${screenshot.length} bytes)');
          return screenshot;
        }
      } catch (e) {
        print('⚠️ SCAN PREVIEW: YouTube WebView fallback failed: $e');
      }
    }
    return null;
  }

  /// Capture Facebook preview WebView
  /// For Reels, uses native screen capture (like YouTube) for better video text capture
  /// For regular posts, uses WebView screenshot
  Future<Uint8List?> _captureFacebookPreview(String url) async {
    // Check if this is a Facebook Reel
    final isReel = url.contains('/reel/') || url.contains('/reels/');
    
    if (isReel) {
      // Use native screen capture for Reels (same as YouTube)
      try {
        print('📷 SCAN PREVIEW: Taking native screen capture for Facebook Reel...');
        
        final result = await _screenshotChannel.invokeMethod('captureScreen');
        
        if (result != null) {
          Uint8List pngBytes;
          if (result is Uint8List) {
            pngBytes = result;
          } else if (result is List) {
            pngBytes = Uint8List.fromList(result.cast<int>());
          } else {
            print('⚠️ SCAN PREVIEW: Unexpected result type: ${result.runtimeType}');
            return await _captureFacebookWebViewFallback(url);
          }
          
          print('✅ SCAN PREVIEW: Captured native screen for Facebook Reel (${pngBytes.length} bytes, PNG format)');
          return pngBytes;
        } else {
          print('⚠️ SCAN PREVIEW: Native screenshot returned null');
          return await _captureFacebookWebViewFallback(url);
        }
      } on PlatformException catch (e) {
        print('⚠️ SCAN PREVIEW: Native screenshot failed: ${e.message}');
        return await _captureFacebookWebViewFallback(url);
      } catch (e) {
        print('⚠️ SCAN PREVIEW: Native screenshot error: $e');
        return await _captureFacebookWebViewFallback(url);
      }
    }
    
    // Regular Facebook post - use WebView screenshot
    return await _captureFacebookWebViewFallback(url);
  }
  
  /// Fallback to WebView screenshot for Facebook (used for both Reels fallback and regular posts)
  Future<Uint8List?> _captureFacebookWebViewFallback(String url) async {
    print('📷 SCAN PREVIEW: Using WebView screenshot for Facebook...');
    final previewKey = _facebookPreviewKeys[url];
    if (previewKey == null) {
      print('⚠️ SCAN PREVIEW: No Facebook preview key found');
      return null;
    }

    final state = previewKey.currentState;
    if (state != null) {
      try {
        final screenshot = await state.takeScreenshot();
        if (screenshot != null) {
          print(
              '✅ SCAN PREVIEW: Captured Facebook WebView (${screenshot.length} bytes)');
          return screenshot;
        }
      } catch (e) {
        print('⚠️ SCAN PREVIEW: Facebook takeScreenshot failed: $e');
      }
    }
    return null;
  }

  /// Capture Web URL preview WebView
  Future<Uint8List?> _captureWebUrlPreview(String url) async {
    final previewKey = _webUrlPreviewKeys[url];
    if (previewKey == null) {
      print('⚠️ SCAN PREVIEW: No Web URL preview key found');
      return null;
    }

    final state = previewKey.currentState;
    if (state != null) {
      try {
        final screenshot = await state.takeScreenshot();
        if (screenshot != null) {
          print(
              '✅ SCAN PREVIEW: Captured Web URL WebView (${screenshot.length} bytes)');
          return screenshot;
        }
      } catch (e) {
        print('⚠️ SCAN PREVIEW: Web URL takeScreenshot failed: $e');
      }
    }
    return null;
  }

  /// Capture Google Knowledge Graph preview WebView
  Future<Uint8List?> _captureGoogleKgPreview(String url) async {
    final previewKey = _googleKgPreviewKeys[url];
    if (previewKey == null) {
      print('⚠️ SCAN PREVIEW: No Google KG preview key found');
      return null;
    }

    final state = previewKey.currentState;
    if (state != null) {
      try {
        final screenshot = await state.takeScreenshot();
        if (screenshot != null) {
          print(
              '✅ SCAN PREVIEW: Captured Google KG WebView (${screenshot.length} bytes)');
          return screenshot;
        }
      } catch (e) {
        print('⚠️ SCAN PREVIEW: Google KG takeScreenshot failed: $e');
      }
    }
    return null;
  }

  /// Process the screenshot/image to extract locations using Gemini Vision
  Future<void> _processScreenshotForLocations(File imageFile) async {
    // Skip if already processing
    if (_isProcessingScreenshot || _isExtractingLocation) return;

    setState(() {
      _isProcessingScreenshot = true;
      _isAiScanInProgress = true;
    });

    // Enable wakelock to prevent screen from sleeping during AI scan
    WakelockPlus.enable();
    
    // Start foreground service to keep app alive during scan
    await _foregroundScanService.startScanService();

    try {
      // Get user location for better results (optional)
      LatLng? userLocation;
      if (_currentUserPosition != null) {
        userLocation = LatLng(
          _currentUserPosition!.latitude,
          _currentUserPosition!.longitude,
        );
      }

      print('📷 SCREENSHOT: Starting AI location extraction from image...');

      // Extract locations using Gemini Vision
      final locations = await _locationExtractor.extractLocationsFromImage(
        imageFile,
        userLocation: userLocation,
      );

      // Check if mounted - if not, store results to apply when app resumes
      if (!mounted) {
        if (locations.isNotEmpty) {
          print('📷 SCREENSHOT: App backgrounded, storing ${locations.length} result(s) for later');
          _pendingScanResults = locations;
          if (locations.length == 1) {
            _pendingScanSingleMessage = '📷 Found: ${locations.first.name}';
          }
        }
        return;
      }

      if (locations.isEmpty) {
        print('⚠️ SCREENSHOT: No locations found in image');
        Fluttertoast.showToast(
          msg:
              '📷 No locations found in screenshot. Try an image with visible text, captions, or location tags.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.orange[700],
        );
        return;
      }

      print('✅ SCREENSHOT: Found ${locations.length} location(s)');

      // Heavy vibration to notify user scan completed
      _heavyVibration();

      final provider = context.read<ReceiveShareProvider>();

      if (locations.length == 1) {
        // Single location: Update first card or create if none exists
        await _applySingleExtractedLocation(locations.first, provider);

        Fluttertoast.showToast(
          msg: '📷 Found: ${locations.first.name}',
          toastLength: Toast.LENGTH_SHORT,
          backgroundColor: Colors.green,
        );
      } else {
        // Multiple locations: Ask user before creating multiple cards
        await _handleMultipleExtractedLocations(locations, provider);
      }
    } catch (e) {
      print('❌ SCREENSHOT ERROR: $e');
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Error processing screenshot',
          backgroundColor: Colors.red,
        );
      }
    } finally {
      // Disable wakelock and stop foreground service
      WakelockPlus.disable();
      await _foregroundScanService.stopScanService();
      if (mounted) {
        setState(() {
          _isProcessingScreenshot = false;
          _isAiScanInProgress = false;
        });
      }
    }
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

  // Track TikTok URLs that have already been processed for auto-extraction
  final Set<String> _tiktokCaptionsProcessed = {};

  // Track Facebook URLs that have already been processed for auto-extraction
  final Set<String> _facebookUrlsProcessed = {};

  // Add debounce timer for location updates
  Timer? _locationUpdateDebounce;

  // Suspend media previews (unmount WebViews) while navigating to other screens
  bool _suspendMediaPreviews = false;

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

  Map<String, SharePermission> _editableCategoryPermissions = {};

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
    _userCategoriesNotifier =
        ValueNotifier<List<UserCategory>>(_userCategories);
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
        await provider.setDependencies(
          // This method needs to be defined in ReceiveShareProvider
          prefs: _prefsInstance!,
          userCategories: _userCategories,
          userColorCategories: _userColorCategories,
        );
        // TODO: Remove the line below once setDependencies in ReceiveShareProvider is confirmed implemented
      } catch (e) {}

      // Initialize the combined future for the FutureBuilder in build()
      // This must be called after _userCategoriesFuture and _userColorCategoriesFuture are (re)set by the _load methods
      _initializeCombinedFuture();

      // Now it's safe to process initial shared content,
      // as the provider (conceptually) has what it needs for default categories.
      _processInitialSharedContent(_currentSharedFiles);
      _syncSharedUrlControllerFromContent();

      // Mark as fully initialized
      _isFullyInitialized = true;
      
      // Auto-extract locations for YouTube URLs on initial load
      _autoExtractLocationsIfYouTube(_currentSharedFiles);
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
      final Map<String, dynamic> cardData =
          savedCardData as Map<String, dynamic>;
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
        targetCard.selectedColorCategoryId =
            cardData['selectedColorCategoryId'];
        targetCard.selectedOtherCategoryIds =
            List<String>.from(cardData['selectedOtherCategoryIds'] ?? []);
        targetCard.selectedOtherColorCategoryIds =
            List<String>.from(cardData['selectedOtherColorCategoryIds'] ?? []);
        targetCard.locationController.text =
            cardData['locationController'] ?? '';
        targetCard.searchController.text = cardData['searchController'] ?? '';
        targetCard.locationEnabled.value = cardData['locationEnabled'] ?? true;
        targetCard.rating = (cardData['rating'] ?? 0.0).toDouble();
        targetCard.placeIdForPreview = cardData['placeIdForPreview'];
        targetCard.existingExperienceId = cardData['existingExperienceId'];
        targetCard.isPrivate = cardData['isPrivate'] ?? false;

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

    if (formData.containsKey('sharedMediaIsPrivate')) {
      _sharedMediaIsPrivate = formData['sharedMediaIsPrivate'] == true;
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
      // Extract Yelp URL early to check for various scenarios
      String? yelpUrl = _extractYelpUrlFromSharedFiles(updatedFiles);
      
      // Check if this is a Yelp-only update (only Yelp URL, no other content)
      // BUT only if it's the EXACT SAME Yelp URL - any different Yelp URL should reset the screen
      bool isYelpOnlyUpdate = false;
      if (yelpUrl != null &&
          updatedFiles.length == 1 &&
          _currentSharedFiles.isNotEmpty) {
        // Check if current content also has a Yelp URL
        String? currentYelpUrl = _extractYelpUrlFromSharedFiles(_currentSharedFiles);
        
        // Only treat as "update" if current content has the EXACT SAME Yelp URL
        // If current content doesn't have a Yelp URL, or has a different one, treat as new share
        if (currentYelpUrl != null && currentYelpUrl == yelpUrl) {
          isYelpOnlyUpdate = true;
        }
        // Otherwise, fall through to reset logic below
      }

      // Special handling for Yelp-only updates - only when it's the exact same URL
      if (isYelpOnlyUpdate) {
        // Skip all the normal processing and go directly to Yelp URL handling
        _isProcessingUpdate = true;

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

      // Check if this is a Yelp URL
      if (yelpUrl != null) {
        // Check if this is a different Yelp URL than what we currently have
        String? currentYelpUrl;
        if (_currentSharedFiles.isNotEmpty) {
          currentYelpUrl = _extractYelpUrlFromSharedFiles(_currentSharedFiles);
        }
        
        // If it's the same Yelp URL and we have existing cards, just update the existing card
        if (currentYelpUrl != null && currentYelpUrl == yelpUrl && _hasExistingCards()) {
          _handleYelpUrlUpdate(yelpUrl, updatedFiles);
          Future.delayed(const Duration(milliseconds: 1000), () {
            _isProcessingUpdate = false;
          });
          return;
        }
        
        // If it's a different Yelp URL (or no current content), reset the screen and process as new share
        // This handles the case where user shares a new Yelp URL while screen is already open
        print('🔄 YELP: New Yelp URL detected while screen is open. Resetting and processing as new share.');
        print('   Current URL: $currentYelpUrl');
        print('   New URL: $yelpUrl');
        
        // If not fully initialized yet, wait for initialization to complete
        if (!_isFullyInitialized) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && _isFullyInitialized) {
              _handleSharedFilesUpdate();
            }
          });
          return;
        }
        
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
        
        // Auto-extract locations for YouTube URLs shared via intent
        _autoExtractLocationsIfYouTube(updatedFiles);
        
        _isProcessingUpdate = false;
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
      
      // Auto-extract locations for YouTube URLs shared via intent
      _autoExtractLocationsIfYouTube(updatedFiles);
      
      _isProcessingUpdate = false;
    }
  }
  
  /// Automatically trigger location extraction for YouTube URLs shared via intent
  /// This allows Gemini to analyze the actual video content (audio + visuals)
  void _autoExtractLocationsIfYouTube(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    
    final first = files.first;
    if (first.type != SharedMediaType.url && first.type != SharedMediaType.text) return;
    
    final url = _extractFirstUrl(first.path);
    if (url == null) return;
    
    // Only auto-extract for YouTube URLs
    if (_isYouTubeUrl(url)) {
      print('🎬 AUTO-EXTRACT: YouTube URL detected via share intent, triggering video analysis');
      // Delay slightly to allow UI to settle
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _extractLocationsFromUrl(url);
        }
      });
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
      if (first.type == SharedMediaType.url ||
          first.type == SharedMediaType.text) {
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
        const SnackBar(
            content: Text('Pasted from clipboard.'),
            duration: Duration(seconds: 1)),
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
    if (parsed == null ||
        (!parsed.isScheme('http') && !parsed.isScheme('https'))) {
      _showSnackBar(context, 'Invalid URL');
      return;
    }

    _lastProcessedUrl = url;

    // Update shared files to drive preview
    final updated = List<SharedMediaFile>.from(_currentSharedFiles);
    if (updated.isNotEmpty &&
        (updated.first.type == SharedMediaType.url ||
            updated.first.type == SharedMediaType.text)) {
      updated[0] = SharedMediaFile(
          path: url,
          thumbnail: null,
          duration: null,
          type: SharedMediaType.url);
    } else {
      updated.insert(
          0,
          SharedMediaFile(
              path: url,
              thumbnail: null,
              duration: null,
              type: SharedMediaType.url));
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

    // Trigger AI-powered location extraction
    _extractLocationsFromUrl(url);
  }

  /// Extract locations from URL using AI-powered Gemini service
  Future<void> _extractLocationsFromUrl(String url) async {
    // Skip if already extracting
    if (_isExtractingLocation) return;

    // Skip for URLs that we already handle specially with their own location logic
    if (_isYelpUrl(url) || _isGoogleMapsUrl(url)) {
      print('🔍 EXTRACTION: Skipping AI extraction for platform-specific URL');
      return;
    }

    setState(() {
      _isExtractingLocation = true;
      _isAiScanInProgress = true;
    });

    // Enable wakelock to prevent screen from sleeping during AI scan
    WakelockPlus.enable();
    
    // Start foreground service to keep app alive during scan
    await _foregroundScanService.startScanService();

    try {
      // Get user location for better results (optional)
      LatLng? userLocation;
      if (_currentUserPosition != null) {
        userLocation = LatLng(
          _currentUserPosition!.latitude,
          _currentUserPosition!.longitude,
        );
      }

      print('🤖 AI EXTRACTION: Starting location extraction from URL...');

      // Extract locations using Gemini + Maps grounding
      // YouTube videos can have many locations (e.g., "Top 10" videos) - no limit
      final isYouTube = _isYouTubeUrl(url);
      final locations = await _locationExtractor.extractLocationsFromSharedLink(
        url,
        userLocation: userLocation,
        maxLocations: isYouTube ? null : 5, // No limit for YouTube
      );

      // Check if mounted - if not, store results to apply when app resumes
      if (!mounted) {
        if (locations.isNotEmpty) {
          print('🤖 AI EXTRACTION: App backgrounded, storing ${locations.length} result(s) for later');
          _pendingScanResults = locations;
          if (locations.length == 1) {
            _pendingScanSingleMessage = '📍 Found: ${locations.first.name}';
          }
        }
        return;
      }

      if (locations.isEmpty) {
        print('⚠️ AI EXTRACTION: No locations found in URL');

        // Show helpful message for social media URLs
        if (_isSocialMediaUrl(url)) {
          Fluttertoast.showToast(
            msg:
                '💡 Tip: Copy the caption or post text that mentions the location, then paste it in the URL field',
            toastLength: Toast.LENGTH_LONG,
            backgroundColor: Colors.orange[700],
          );
        }
        return;
      }

      print('✅ AI EXTRACTION: Found ${locations.length} location(s)');

      // Heavy vibration to notify user scan completed
      _heavyVibration();

      final provider = context.read<ReceiveShareProvider>();

      if (locations.length == 1) {
        // Single location: Update first card or create if none exists
        await _applySingleExtractedLocation(locations.first, provider);

        Fluttertoast.showToast(
          msg: '📍 Found: ${locations.first.name}',
          toastLength: Toast.LENGTH_SHORT,
          backgroundColor: Colors.green,
        );
      } else {
        // Multiple locations: Ask user before creating multiple cards
        await _handleMultipleExtractedLocations(locations, provider);
      }
    } catch (e) {
      print('❌ AI EXTRACTION ERROR: $e');
    } finally {
      // Disable wakelock and stop foreground service
      WakelockPlus.disable();
      await _foregroundScanService.stopScanService();
      if (mounted) {
        setState(() {
          _isExtractingLocation = false;
          _isAiScanInProgress = false;
        });
      }
    }
  }

  /// Handle TikTok oEmbed data loaded - automatically extract locations from caption
  Future<void> _handleTikTokOEmbedData(
      String url, TikTokOEmbedData data) async {
    // Skip if already processed this URL
    if (_tiktokCaptionsProcessed.contains(url)) {
      print('🎬 TIKTOK AUTO-EXTRACT: Already processed $url');
      return;
    }

    // Skip if no useful content
    if (!data.hasContent) {
      print('🎬 TIKTOK AUTO-EXTRACT: No caption content to analyze');
      return;
    }

    // Skip if already extracting
    if (_isExtractingLocation) {
      print('🎬 TIKTOK AUTO-EXTRACT: Extraction already in progress');
      return;
    }

    // Mark as processed to prevent duplicate extractions
    _tiktokCaptionsProcessed.add(url);

    print('🎬 TIKTOK AUTO-EXTRACT: Starting automatic location extraction...');
    print('🎬 Caption: ${data.title}');
    print('🎬 Author: ${data.authorName}');

    setState(() {
      _isExtractingLocation = true;
      _isAiScanInProgress = true;
    });

    // Enable wakelock to prevent screen from sleeping during AI scan
    WakelockPlus.enable();
    
    // Start foreground service to keep app alive during scan
    await _foregroundScanService.startScanService();

    try {
      // Get user location for better results (optional)
      LatLng? userLocation;
      if (_currentUserPosition != null) {
        userLocation = LatLng(
          _currentUserPosition!.latitude,
          _currentUserPosition!.longitude,
        );
      }

      // Extract locations from the TikTok caption
      final locations = await _locationExtractor.extractLocationsFromCaption(
        data.title ?? '',
        platform: 'TikTok',
        authorName: data.authorName,
        sourceUrl: url,
        userLocation: userLocation,
        maxLocations: 5,
      );

      // Check if mounted - if not, store results to apply when app resumes
      if (!mounted) {
        if (locations.isNotEmpty) {
          print('🎬 TIKTOK AUTO-EXTRACT: App backgrounded, storing ${locations.length} result(s) for later');
          _pendingScanResults = locations;
          if (locations.length == 1) {
            _pendingScanSingleMessage = '📍 Found: ${locations.first.name}';
          }
        }
        return;
      }

      if (locations.isEmpty) {
        print('⚠️ TIKTOK AUTO-EXTRACT: No locations found in caption');
        Fluttertoast.showToast(
          msg:
              '💡 No location found in caption. Try the "Scan Preview" button to analyze visible text.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.orange[700],
        );
        return;
      }

      print('✅ TIKTOK AUTO-EXTRACT: Found ${locations.length} location(s)');

      // Heavy vibration to notify user scan completed
      _heavyVibration();

      final provider = context.read<ReceiveShareProvider>();

      if (locations.length == 1) {
        // Single location: Update first card or create if none exists
        await _applySingleExtractedLocation(locations.first, provider);

        Fluttertoast.showToast(
          msg: '📍 Found: ${locations.first.name}',
          toastLength: Toast.LENGTH_SHORT,
          backgroundColor: Colors.green,
        );
      } else {
        // Multiple locations: Ask user before creating multiple cards
        await _handleMultipleExtractedLocations(locations, provider);
      }
    } catch (e) {
      print('❌ TIKTOK AUTO-EXTRACT ERROR: $e');
    } finally {
      // Disable wakelock and stop foreground service
      WakelockPlus.disable();
      await _foregroundScanService.stopScanService();
      if (mounted) {
        setState(() {
          _isExtractingLocation = false;
          _isAiScanInProgress = false;
        });
      }
    }
  }

  /// Handle Facebook page loaded - automatically extract locations from page content
  Future<void> _onFacebookPageLoaded(String url) async {
    // Skip if already processed this URL
    if (_facebookUrlsProcessed.contains(url)) {
      print('📘 FACEBOOK AUTO-EXTRACT: Already processed $url');
      return;
    }

    // Skip if already extracting
    if (_isExtractingLocation || _isProcessingScreenshot) {
      print('📘 FACEBOOK AUTO-EXTRACT: Extraction already in progress');
      return;
    }

    // Mark as processed to prevent duplicate extractions
    _facebookUrlsProcessed.add(url);

    print('📘 FACEBOOK AUTO-EXTRACT: Starting automatic location extraction...');

    setState(() {
      _isExtractingLocation = true;
      _isAiScanInProgress = true;
    });

    // Enable wakelock to prevent screen from sleeping during AI scan
    WakelockPlus.enable();
    
    // Start foreground service to keep app alive during scan
    await _foregroundScanService.startScanService();

    try {
      // Get user location for better results (optional)
      LatLng? userLocation;
      if (_currentUserPosition != null) {
        userLocation = LatLng(
          _currentUserPosition!.latitude,
          _currentUserPosition!.longitude,
        );
      }

      // Try to extract page content from the Facebook WebView
      String? pageContent;
      final previewKey = _facebookPreviewKeys[url];
      if (previewKey?.currentState != null) {
        try {
          pageContent = await previewKey!.currentState!.extractPageContent();
        } catch (e) {
          print('⚠️ FACEBOOK AUTO-EXTRACT: Content extraction failed: $e');
        }
      }

      if (pageContent == null || pageContent.isEmpty || pageContent.length < 20) {
        print('⚠️ FACEBOOK AUTO-EXTRACT: No usable content extracted');
        if (mounted) {
          Fluttertoast.showToast(
            msg: '💡 No location found in post. Try the "Scan Preview" button to analyze visible text.',
            toastLength: Toast.LENGTH_LONG,
            backgroundColor: Colors.orange[700],
          );
        }
        return;
      }

      print('📘 FACEBOOK AUTO-EXTRACT: Extracted ${pageContent.length} characters');
      print('📘 FACEBOOK AUTO-EXTRACT: Content preview: ${pageContent.substring(0, pageContent.length > 200 ? 200 : pageContent.length)}...');

      // Use LinkLocationExtractionService (same as TikTok) for proper grounding with Places API
      final locations = await _locationExtractor.extractLocationsFromCaption(
        pageContent,
        platform: 'Facebook',
        sourceUrl: url,
        userLocation: userLocation,
        maxLocations: 5,
      );

      // Check if mounted - if not, store results to apply when app resumes
      if (!mounted) {
        if (locations.isNotEmpty) {
          print('📘 FACEBOOK AUTO-EXTRACT: App backgrounded, storing ${locations.length} result(s) for later');
          _pendingScanResults = locations;
          if (locations.length == 1) {
            _pendingScanSingleMessage = '📍 Found: ${locations.first.name}';
          }
        }
        return;
      }

      if (locations.isEmpty) {
        print('⚠️ FACEBOOK AUTO-EXTRACT: No locations found in page content');
        Fluttertoast.showToast(
          msg: '💡 No location found in post. Try the "Scan Preview" button to analyze visible text.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.orange[700],
        );
        return;
      }

      print('✅ FACEBOOK AUTO-EXTRACT: Found ${locations.length} location(s)');

      // Heavy vibration to notify user scan completed
      _heavyVibration();

      final provider = context.read<ReceiveShareProvider>();

      if (locations.length == 1) {
        await _applySingleExtractedLocation(locations.first, provider);
        Fluttertoast.showToast(
          msg: '📍 Found: ${locations.first.name}',
          toastLength: Toast.LENGTH_SHORT,
          backgroundColor: Colors.green,
        );
      } else {
        await _handleMultipleExtractedLocations(locations, provider);
      }
    } catch (e) {
      print('❌ FACEBOOK AUTO-EXTRACT ERROR: $e');
    } finally {
      // Disable wakelock and stop foreground service
      WakelockPlus.disable();
      await _foregroundScanService.stopScanService();
      if (mounted) {
        setState(() {
          _isExtractingLocation = false;
          _isAiScanInProgress = false;
        });
      }
    }
  }

  /// Check multiple locations for duplicates against user's saved experiences
  /// Returns a map of location index -> existing Experience if duplicate found
  Future<Map<int, Experience>> _checkLocationsForDuplicates(
    List<ExtractedLocationData> locations,
  ) async {
    final Map<int, Experience> duplicates = {};

    final String? currentUserId = _authService.currentUser?.uid;
    if (currentUserId == null) {
      print('📍 DUPLICATE CHECK: No user ID, skipping duplicate check');
      return duplicates;
    }

    List<Experience> userExperiences = [];
    try {
      userExperiences = await _experienceService.getUserExperiences();
    } catch (e) {
      print('📍 DUPLICATE CHECK: Could not load experiences: $e');
      return duplicates;
    }

    if (userExperiences.isEmpty) {
      return duplicates;
    }

    for (int i = 0; i < locations.length; i++) {
      final location = locations[i];

      // Check by Place ID first (most accurate)
      if (location.placeId != null && location.placeId!.isNotEmpty) {
        final matchByPlaceId = userExperiences.firstWhereOrNull(
          (exp) => exp.location.placeId == location.placeId,
        );
        if (matchByPlaceId != null) {
          duplicates[i] = matchByPlaceId;
          print(
              '📍 DUPLICATE CHECK: Found duplicate for "${location.name}" by Place ID');
          continue;
        }
      }

      // Check by title (case-insensitive)
      final matchByTitle = userExperiences.firstWhereOrNull(
        (exp) =>
            exp.name.trim().toLowerCase() == location.name.trim().toLowerCase(),
      );
      if (matchByTitle != null) {
        duplicates[i] = matchByTitle;
        print(
            '📍 DUPLICATE CHECK: Found duplicate for "${location.name}" by title');
      }
    }

    print(
        '📍 DUPLICATE CHECK: Found ${duplicates.length} duplicates out of ${locations.length} locations');
    return duplicates;
  }

  /// Apply a single extracted location to an available experience card
  /// If all cards already have locations, creates a new card
  Future<void> _applySingleExtractedLocation(
    ExtractedLocationData locationData,
    ReceiveShareProvider provider,
  ) async {
    // Ensure we have at least one card
    if (provider.experienceCards.isEmpty) {
      return;
    }

    // Find the first card without a location
    ExperienceCardData? targetCard;
    for (final card in provider.experienceCards) {
      if (card.selectedLocation == null ||
          card.selectedLocation!.placeId == null ||
          card.selectedLocation!.placeId!.isEmpty) {
        targetCard = card;
        break;
      }
    }

    // If all cards have locations, create a new card
    if (targetCard == null) {
      print('📍 AI EXTRACTION: All cards have locations, creating new card');
      await Future.delayed(const Duration(milliseconds: 2)); // Ensure unique ID
      provider.addExperienceCard();
      targetCard = provider.experienceCards.last;
    }

    // Check for duplicate
    final duplicates = await _checkLocationsForDuplicates([locationData]);

    if (duplicates.containsKey(0)) {
      // Found a duplicate - show dialog to ask user
      final existingExperience = duplicates[0]!;

      if (!mounted) return;

      final bool? useExisting = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          final Color primaryColor =
              Theme.of(dialogContext).colorScheme.primary;
          return AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('Already Saved'),
            content: Text(
                'You already have "${existingExperience.name}" saved at "${existingExperience.location.address ?? 'No address'}". Would you like to use this existing experience?'),
            actions: <Widget>[
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: primaryColor,
                ),
                child: const Text('Create New'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Use Existing'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          );
        },
      );

      if (useExisting == true) {
        provider.updateCardWithExistingExperience(
            targetCard.id, existingExperience);
        print(
            '✅ AI EXTRACTION: Using existing experience "${existingExperience.name}"');
        return;
      }
    }

    // Update the card with extracted location
    provider.updateCardWithExtractedLocation(targetCard.id, locationData);

    print('✅ AI EXTRACTION: Applied location "${locationData.name}" to card');
  }

  /// Handle multiple extracted locations - show dialog with checklist to user
  Future<void> _handleMultipleExtractedLocations(
    List<ExtractedLocationData> locations,
    ReceiveShareProvider provider,
  ) async {
    // Check for duplicates before showing dialog
    final duplicates = await _checkLocationsForDuplicates(locations);

    if (!mounted) return;

    // Show dialog with selectable checklist (including duplicate info)
    final result = await showDialog<_MultiLocationSelectionResult>(
      context: context,
      builder: (context) => _MultiLocationSelectionDialog(
        locations: locations,
        duplicates: duplicates,
      ),
    );

    // Handle the result (which now includes both locations and their duplicate info)
    final selectedLocations = result?.selectedLocations;
    final selectedDuplicates = result?.selectedDuplicates;

    if (selectedLocations != null && selectedLocations.isNotEmpty) {
      // Separate locations into new vs existing (duplicates)
      final List<ExtractedLocationData> newLocations = [];
      final List<Experience> existingExperiences = [];

      for (final location in selectedLocations) {
        if (selectedDuplicates != null &&
            selectedDuplicates.containsKey(location)) {
          existingExperiences.add(selectedDuplicates[location]!);
        } else {
          newLocations.add(location);
        }
      }

      print(
          '📍 MULTI-LOCATION: ${newLocations.length} new, ${existingExperiences.length} existing');

      // Track cards created/updated
      int cardsCreated = 0;
      int existingUsed = 0;

      // Find empty cards to fill first
      final emptyCards = provider.experienceCards
          .where(
            (card) =>
                card.selectedLocation == null ||
                card.selectedLocation!.placeId == null ||
                card.selectedLocation!.placeId!.isEmpty,
          )
          .toList();

      int emptyCardIndex = 0;

      // Split new locations into those that fill empty cards vs those that need new cards
      final List<ExtractedLocationData> locationsForEmptyCards = [];
      final List<ExtractedLocationData> locationsNeedingNewCards = [];

      for (final location in newLocations) {
        if (emptyCardIndex < emptyCards.length) {
          locationsForEmptyCards.add(location);
          emptyCardIndex++;
        } else {
          locationsNeedingNewCards.add(location);
        }
      }

      // Fill existing empty cards with new locations
      for (int i = 0; i < locationsForEmptyCards.length; i++) {
        provider.updateCardWithExtractedLocation(
          emptyCards[i].id,
          locationsForEmptyCards[i],
        );
        print(
            '📍 Filled existing card with: ${locationsForEmptyCards[i].name}');
      }

      // Create all new cards for remaining new locations in one batch
      if (locationsNeedingNewCards.isNotEmpty) {
        await provider.createCardsFromLocations(locationsNeedingNewCards);
        cardsCreated += locationsNeedingNewCards.length;
        print(
            '📍 Created ${locationsNeedingNewCards.length} new cards for new locations');
      }

      // Process existing experiences (duplicates user chose to use)
      // For these, we need to fill remaining empty cards or create new ones
      final remainingEmptyCards = emptyCards.sublist(
          locationsForEmptyCards.length < emptyCards.length
              ? locationsForEmptyCards.length
              : emptyCards.length);
      int remainingEmptyIndex = 0;

      for (final existingExp in existingExperiences) {
        if (remainingEmptyIndex < remainingEmptyCards.length) {
          // Fill an existing empty card with existing experience
          provider.updateCardWithExistingExperience(
              remainingEmptyCards[remainingEmptyIndex].id, existingExp);
          print('📍 Filled card with existing experience: ${existingExp.name}');
          remainingEmptyIndex++;
          existingUsed++;
        } else {
          // Need to create a new card for this existing experience
          // Add a small delay to ensure unique timestamp-based IDs
          await Future.delayed(const Duration(milliseconds: 2));
          provider.addExperienceCard();
          final newCard = provider.experienceCards.last;
          provider.updateCardWithExistingExperience(newCard.id, existingExp);
          print('📍 Created card for existing experience: ${existingExp.name}');
          cardsCreated++;
          existingUsed++;
        }
      }

      // Show appropriate toast message
      if (existingUsed > 0 && newLocations.isNotEmpty) {
        Fluttertoast.showToast(
          msg:
              '📍 ${newLocations.length} new + ${existingUsed} existing experience${existingUsed > 1 ? 's' : ''} added',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.blue,
        );
      } else if (existingUsed > 0) {
        Fluttertoast.showToast(
          msg:
              '📍 Using ${existingUsed} existing experience${existingUsed > 1 ? 's' : ''}',
          toastLength: Toast.LENGTH_SHORT,
          backgroundColor: Colors.green,
        );
      } else if (selectedLocations.length == 1) {
        Fluttertoast.showToast(
          msg: '📍 Applied: ${selectedLocations.first.name}',
          toastLength: Toast.LENGTH_SHORT,
          backgroundColor: Colors.green,
        );
      } else {
        Fluttertoast.showToast(
          msg: '📍 Added ${selectedLocations.length} new experience cards!',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.blue,
        );
      }

      // Show helpful info dialog if multiple cards affected
      if (selectedLocations.length > 1) {
        _showMultiLocationInfoDialog(selectedLocations.length);
      }
    }
  }

  /// Show informational dialog about multiple cards added
  void _showMultiLocationInfoDialog(int count) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 8),
            const Text('Locations Applied!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Applied locations to $count experience card${count > 1 ? 's' : ''}. Scroll down to take a look!',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            const Text(
              'You can edit them however you want and save them to your list of experiences.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 16)),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  /// Check if URL is a Google Maps URL
  bool _isGoogleMapsUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('google.com/maps') ||
        lower.contains('maps.google.com') ||
        lower.contains('goo.gl/maps');
  }

  /// Check if URL is from a social media platform
  bool _isSocialMediaUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('instagram.com') ||
        lower.contains('tiktok.com') ||
        lower.contains('youtube.com') ||
        lower.contains('facebook.com') ||
        lower.contains('twitter.com') ||
        lower.contains('x.com');
  }

  /// Check if URL is an Instagram URL
  bool _isInstagramUrl(String url) {
    return url.toLowerCase().contains('instagram.com');
  }

  /// Check if URL is a TikTok URL
  bool _isTikTokUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('tiktok.com') || lower.contains('vm.tiktok.com');
  }

  /// Check if URL is a Facebook URL
  bool _isFacebookUrl(String url) {
    return url.toLowerCase().contains('facebook.com');
  }

  /// Check if URL is a YouTube URL
  bool _isYouTubeUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('youtube.com') || lower.contains('youtu.be');
  }

  /// Check if URL is a Google Knowledge Graph URL (g.co/kgs/ or share.google/)
  bool _isGoogleKnowledgeGraphUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('g.co/kgs/') || lower.contains('share.google/');
  }

  // Extract Yelp URL from shared files
  String? _extractYelpUrlFromSharedFiles(List<SharedMediaFile> files) {
    for (final file in files) {
      if (file.type == SharedMediaType.text ||
          file.type == SharedMediaType.url) {
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
  void _handleYelpUrlUpdate(
      String yelpUrl, List<SharedMediaFile> updatedFiles) {
    final provider = context.read<ReceiveShareProvider>();
    final experienceCards = provider.experienceCards;

    print('🔗 YELP UPDATE: _handleYelpUrlUpdate called with URL: $yelpUrl');

    if (experienceCards.isEmpty) {
      print('🔗 YELP UPDATE: No cards yet, retrying in 500ms');
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
        targetCard = experienceCards
            .firstWhere((card) => card.id == _lastYelpButtonTappedCardId);
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
    targetCard.originalShareType = ShareType.yelp;

    print('🔗 YELP UPDATE: Set Yelp URL on card ${targetCard.id}');

    // Extract shared text from the updated files for business name extraction
    String? sharedText;
    for (final file in updatedFiles) {
      if (file.type == SharedMediaType.text ||
          file.type == SharedMediaType.url) {
        sharedText = file.path;
        break;
      }
    }

    // Trigger location extraction using Gemini AI
    // This is the key addition - we now extract location data for Yelp URLs
    print('🔗 YELP UPDATE: Triggering location extraction...');
    
    // Set loading state to show spinner in location field
    // targetCard is guaranteed to be non-null here since we checked experienceCards.isEmpty above
    final card = targetCard!;
    card.isSelectingLocation = true;
    if (mounted) {
      setState(() {}); // Trigger rebuild to show loading indicator
    }
    
    // Start the extraction and handle completion
    _yelpPreviewFutures[normalizedUrl] = _getBusinessFromYelpUrl(
      normalizedUrl,
      sharedText: sharedText,
    ).then((result) {
      // Loading state will be cleared in _fillFormWithGoogleMapsData or _fillFormWithBusinessData
      // after the location is actually set on the card
      // Only clear here if no location was found (result is null)
      if (result == null || result['location'] == null) {
        card.isSelectingLocation = false;
        if (mounted) {
          setState(() {}); // Trigger rebuild to hide loading indicator
        }
      }
      return result;
    }).catchError((error) {
      // Clear loading state on error
      card.isSelectingLocation = false;
      if (mounted) {
        setState(() {}); // Trigger rebuild to hide loading indicator
      }
      print('❌ YELP UPDATE: Location extraction error: $error');
      return null;
    });

    if (previousUrl.isNotEmpty) {
      print('🔗 YELP UPDATE: Replaced previous URL: $previousUrl');
    } else {
      print('🔗 YELP UPDATE: Added new Yelp URL');
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
        'selectedOtherColorCategoryIds': card.selectedOtherColorCategoryIds,
        'locationController': card.locationController.text,
        'searchController': card.searchController.text,
        'locationEnabled': card.locationEnabled.value,
        'rating': card.rating,
        'placeIdForPreview': card.placeIdForPreview,
        'existingExperienceId': card.existingExperienceId,
        'isPrivate': card.isPrivate,
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
      'sharedMediaIsPrivate': _sharedMediaIsPrivate,
    });
  }

  List<UserCategory> _filterEditableUserCategories(
      List<UserCategory> categories) {
    if (categories.isEmpty) {
      return categories;
    }
    final String? currentUserId = _authService.currentUser?.uid;
    return categories.where((category) {
      if (currentUserId != null && category.ownerUserId == currentUserId) {
        return true;
      }
      final SharePermission? permission =
          _editableCategoryPermissions[category.id];
      return permission?.accessLevel == ShareAccessLevel.edit;
    }).toList();
  }

  List<ColorCategory> _filterEditableColorCategories(
      List<ColorCategory> categories) {
    if (categories.isEmpty) {
      return categories;
    }
    final String? currentUserId = _authService.currentUser?.uid;
    return categories.where((category) {
      if (currentUserId != null && category.ownerUserId == currentUserId) {
        return true;
      }
      final SharePermission? permission =
          _editableCategoryPermissions[category.id];
      return permission?.accessLevel == ShareAccessLevel.edit;
    }).toList();
  }

  Future<List<UserCategory>> _fetchOrderedUserCategories() async {
    final resultFuture = _experienceService.getUserCategoriesWithMeta(
      includeSharedEditable: true,
    );
    final permissionsFuture =
        _experienceService.getEditableCategoryPermissionsMap();

    final UserCategoryFetchResult result = await resultFuture;
    Map<String, SharePermission> editablePermissions = {};
    try {
      editablePermissions = await permissionsFuture;
    } catch (e) {
      print(
          'ReceiveShareScreen: Failed to load editable category permissions: $e');
    }

    _editableCategoryPermissions = {
      ...editablePermissions,
      ...result.sharedPermissions,
    };

    final orderedCategories =
        await _categoryOrderingService.orderUserCategories(result.categories,
            sharedPermissions: result.sharedPermissions);
    return _filterEditableUserCategories(orderedCategories);
  }

  Future<List<ColorCategory>> _fetchOrderedColorCategories() async {
    final colorCategoriesFuture = _experienceService.getUserColorCategories(
      includeSharedEditable: true,
    );
    Map<String, SharePermission> editablePermissions = {};
    bool permissionsLoaded = true;
    try {
      editablePermissions =
          await _experienceService.getEditableCategoryPermissionsMap();
    } catch (e) {
      permissionsLoaded = false;
      print(
          'ReceiveShareScreen: Failed to refresh editable category permissions for color categories: $e');
    }

    if (permissionsLoaded) {
      _editableCategoryPermissions = {...editablePermissions};
    }

    final colorCategories = await colorCategoriesFuture;
    final orderedColorCategories =
        await _categoryOrderingService.orderColorCategories(colorCategories);
    return _filterEditableColorCategories(orderedColorCategories);
  }

  Future<void> _loadUserCategories() async {
    try {
      final Categories = await _fetchOrderedUserCategories();
      if (mounted) {
        _userCategories = Categories;
        _userCategoriesNotifier.value = Categories;
        _updateCardDefaultCategoriesIfNeeded(Categories);
      }
      _userCategoriesFuture = Future.value(
          Categories); // Ensure future resolves to the fetched list
    } catch (error) {
      if (mounted) {
        _userCategories = [];
        _userCategoriesNotifier.value = [];
      }
      _userCategoriesFuture =
          Future.value([]); // Ensure future resolves to an empty list on error
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
    return _fetchOrderedUserCategories().then((categories) {
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
    return _fetchOrderedColorCategories().then((colorCategories) {
      if (mounted) {
        _userColorCategories = colorCategories;
        _userColorCategoriesNotifier.value = colorCategories;
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
      // Apply any pending scan results that were found while app was in background
      _applyPendingScanResults();
    }
  }

  /// Apply any scan results that were found while the app was in the background
  Future<void> _applyPendingScanResults() async {
    if (_pendingScanResults == null || _pendingScanResults!.isEmpty) return;
    if (!mounted) return;

    final results = _pendingScanResults!;
    final singleMessage = _pendingScanSingleMessage;
    
    // Clear pending results
    _pendingScanResults = null;
    _pendingScanSingleMessage = null;

    print('🔄 SCAN RESUME: Applying ${results.length} pending scan result(s)');

    // Heavy vibration to notify user that background scan completed
    _heavyVibration();

    try {
      final provider = context.read<ReceiveShareProvider>();

      if (results.length == 1) {
        await _applySingleExtractedLocation(results.first, provider);
        if (singleMessage != null) {
          Fluttertoast.showToast(
            msg: singleMessage,
            toastLength: Toast.LENGTH_SHORT,
            backgroundColor: Colors.green,
          );
        }
      } else {
        await _handleMultipleExtractedLocations(results, provider);
      }
    } catch (e) {
      print('❌ SCAN RESUME ERROR: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingScreenshot = false;
          _isAiScanInProgress = false;
        });
      }
      // Disable wakelock and stop foreground service after applying results
      WakelockPlus.disable();
      await _foregroundScanService.stopScanService();
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
      final fetchedCategories = await _fetchOrderedUserCategories();
      // Check if we should continue after the async operation
      if (!shouldContinue()) return;

      if (!const DeepCollectionEquality()
          .equals(fetchedCategories, _userCategories)) {
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
      final fetchedColorCategories = await _fetchOrderedColorCategories();
      // Check if we should continue after the async operation
      if (!shouldContinue()) return;

      if (!const DeepCollectionEquality()
          .equals(fetchedColorCategories, _userColorCategories)) {
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
    // Cancel any pending debounce timers
    _locationUpdateDebounce?.cancel();

    // If _saveExperience initiated navigation, prepareToNavigateAwayFromShare already handled things.
    // This call to markShareFlowAsInactive is mainly for cases where dispose is called due to
    // other reasons (like system back if not fully handled, or unexpected unmount).
    // However, if _navigatingAwayFromShare is true, we might not want to call markShareFlowAsInactive again here
    // as it calls resetSharedItems again. Let's rely on onCancel and onWillPop for explicit user exits.
    // The SharingService's shareNavigationComplete (called by MainScreen) will reset _navigatingAwayFromShare.
    // If _sharingService.isNavigatingAwayFromShare is false, then it means we are disposing due to a non-save exit.
    if (!_sharingService.isNavigatingAwayFromShare) {
      // MODIFIED to use getter
      _sharingService.markShareFlowAsInactive();
    }
    _currentReloadOperationId = -1;
    _isFullyInitialized = false; // Reset initialization flag
    WidgetsBinding.instance.removeObserver(this);
    _sharingService.sharedFiles.removeListener(_handleSharedFilesUpdate);
    // Removed direct call to receive_sharing_intent reset from here,
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
    // Clear auto-scanned URLs and processed URLs when new content is shared
    _autoScannedUrls.clear();
    _facebookUrlsProcessed.clear();
    _tiktokCaptionsProcessed.clear();
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

            _processSpecialUrl(foundUrl, file);
            return;
          } else {}
        }
      }
    }

    if (foundUrl == null) {
    } else {}
  }

  bool _isSpecialUrl(String url) {
    if (url.isEmpty) return false;
    String urlLower = url.toLowerCase();

    final yelpPattern = RegExp(r'yelp\.(com/biz|to)/');
    final mapsPattern =
        RegExp(r'(google\.com/maps|maps\.app\.goo\.gl|goo\.gl/maps)');
    final facebookPattern = RegExp(r'(facebook\.com|fb\.com|fb\.watch)');
    final googleKnowledgePattern =
        RegExp(r'g\.co/kgs/'); // Added pattern for Google Knowledge Graph URLs
    final shareGooglePattern =
        RegExp(r'share\.google/'); // Added pattern for share.google URLs

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
      firstCard.yelpUrlController.text = normalizedUrl;
      
      // Set loading state to show spinner in location field
      firstCard.isSelectingLocation = true;
      if (mounted) {
        setState(() {}); // Trigger rebuild to show loading indicator
      }
      
      // Start the extraction and handle completion
      _yelpPreviewFutures[normalizedUrl] = _getBusinessFromYelpUrl(
        normalizedUrl,
        sharedText: file.path,
      ).then((result) {
        // Loading state will be cleared in _fillFormWithGoogleMapsData or _fillFormWithBusinessData
        // after the location is actually set on the card
        // Only clear here if no location was found (result is null)
        if (result == null || result['location'] == null) {
          firstCard.isSelectingLocation = false;
          if (mounted) {
            setState(() {}); // Trigger rebuild to hide loading indicator
          }
        }
        return result;
      }).catchError((error) {
        // Clear loading state on error
        firstCard.isSelectingLocation = false;
        if (mounted) {
          setState(() {}); // Trigger rebuild to hide loading indicator
        }
        print('❌ YELP PROCESS: Location extraction error: $error');
        return null;
      });
    } else if (normalizedUrl.contains('google.com/maps') ||
        normalizedUrl.contains('maps.app.goo.gl') ||
        normalizedUrl.contains('goo.gl/maps')) {
      firstCard.originalShareType = ShareType.maps;
      
      // Set loading state to show spinner in location field
      firstCard.isSelectingLocation = true;
      if (mounted) {
        setState(() {}); // Trigger rebuild to show loading indicator
      }
      
      // Start the extraction and handle completion
      _yelpPreviewFutures[normalizedUrl] = _getLocationFromMapsUrl(normalizedUrl)
          .then((result) {
        // Loading state will be cleared in _fillFormWithGoogleMapsData
        // after the location is actually set on the card
        // Only clear here if no location was found (result is null)
        if (result == null || result['location'] == null) {
          firstCard.isSelectingLocation = false;
          if (mounted) {
            setState(() {}); // Trigger rebuild to hide loading indicator
          }
        }
        return result;
      }).catchError((error) {
        // Clear loading state on error
        firstCard.isSelectingLocation = false;
        if (mounted) {
          setState(() {});
        }
        print('❌ MAPS PROCESS: Location extraction error: $error');
        return null;
      });
    } else if (normalizedUrl.contains('g.co/kgs/') ||
        normalizedUrl.contains('share.google/')) {
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
    } else {}
  }

  Future<void> _processGoogleMapsUrl(String url) async {
    try {
      setState(() {});

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
    print('🍽️ YELP LOOKUP: Starting _getBusinessFromYelpUrl');
    print('🍽️ YELP LOOKUP: URL: $yelpUrl');
    final sharedTextPreview = sharedText != null
        ? sharedText.substring(
            0, sharedText.length > 100 ? 100 : sharedText.length)
        : 'null';
    print('🍽️ YELP LOOKUP: Shared text: $sharedTextPreview...');

    _chainDetectedFromUrl = false;

    final cacheKey = yelpUrl.trim();

    if (_businessDataCache.containsKey(cacheKey)) {
      print('🍽️ YELP LOOKUP: Returning cached data');
      final cachedData = _businessDataCache[cacheKey];
      return _businessDataCache[cacheKey];
    }

    String url = yelpUrl.trim();

    if (url.isEmpty) {
      print('🍽️ YELP LOOKUP: URL is empty, returning null');
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
          } else {}
        } catch (e) {}
      }

      bool extractedFromUrl = false;
      bool extractedFromSharedText = false;

      // First, try to extract business name from shared text if available
      if (sharedText != null) {
        try {
          // Look for any Yelp URL pattern in the shared text (yelp.com or yelp.to)
          RegExp yelpUrlPattern =
              RegExp(r'https?://(?:www\.)?yelp\.(?:com|to)/[^\s]+');
          Match? urlMatch = yelpUrlPattern.firstMatch(sharedText);

          int urlIndex = -1;
          if (urlMatch != null) {
            urlIndex = urlMatch.start;
          } else {
            // Fallback: look for the exact URL we received
            urlIndex = sharedText.indexOf(yelpUrl);
            if (urlIndex != -1) {}
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
              extractedFromUrl =
                  true; // Mark as extracted so we don't use generic name
            } else {}
          } else {}
        } catch (e) {}
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
          if (states.contains(pathParts[i].toLowerCase()) ||
              ["city", "town", "village"]
                  .contains(pathParts[i].toLowerCase())) {
            if (i > 0) {
              cityStartIndex = i - 1;
              break;
            }
          }
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
        extractedFromUrl = true;
      }

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
            if (businessName.isEmpty &&
                extraInfo['businessName'] != null &&
                extraInfo['businessName']!.isNotEmpty) {
              businessName = extraInfo['businessName']!;
              extractedFromUrl = true;
            }
          }
        } catch (e) {}
      }

      if (businessName.isEmpty) {
        businessName = "Shared Business";
      }

      // --- GEMINI-POWERED LOCATION EXTRACTION ---
      // Use Gemini AI to find the location when we have a business name
      // This works especially well for Yelp shares with short URLs where we
      // only have the business name from the share text
      Location? geminiFoundLocation;
      if (businessName.isNotEmpty && businessName != "Shared Business") {
        print(
            '🤖 YELP->GEMINI: Attempting AI location extraction for "$businessName"');

        // Build context for Gemini - include city/state if we have them
        String searchContext = businessName;
        if (businessCity.isNotEmpty) {
          searchContext = '$businessName in $businessCity';
          if (businessState.isNotEmpty) {
            searchContext = '$businessName in $businessCity, $businessState';
          }
        } else if (businessState.isNotEmpty) {
          searchContext = '$businessName in $businessState';
        }

        // Add restaurant/business type hint for better search
        if (businessType.isNotEmpty) {
          searchContext = '$searchContext ($businessType)';
        } else {
          // Yelp shares are typically restaurants/food businesses
          searchContext = '$searchContext restaurant';
        }

        try {
          // Get user location for better search results
          LatLng? userLatLng;
          if (userPosition != null) {
            userLatLng = LatLng(userPosition.latitude, userPosition.longitude);
          }

          // Use LinkLocationExtractionService to extract location with Gemini
          final geminiLocations =
              await _locationExtractor.extractLocationsFromCaption(
            'Find the restaurant/business: $searchContext',
            platform: 'Yelp',
            sourceUrl: url,
            userLocation: userLatLng,
            maxLocations: 1,
          );

          if (geminiLocations.isNotEmpty) {
            final firstResult = geminiLocations.first;
            print('✅ YELP->GEMINI: Found location: ${firstResult.name}');
            print('   📍 PlaceId: ${firstResult.placeId}');
            print('   📍 Address: ${firstResult.address}');

            // Convert ExtractedLocationData to Location
            if (firstResult.placeId != null &&
                firstResult.placeId!.isNotEmpty) {
              // Get full place details from Google Maps service
              try {
                final fullLocation =
                    await _mapsService.getPlaceDetails(firstResult.placeId!);
                geminiFoundLocation = fullLocation;

                // Update city/state from the full location
                if (businessCity.isEmpty && fullLocation.city != null) {
                  businessCity = fullLocation.city!;
                  print('   📍 Updated city from Gemini: $businessCity');
                }
                if (businessState.isEmpty && fullLocation.state != null) {
                  businessState = fullLocation.state!;
                  print('   📍 Updated state from Gemini: $businessState');
                }
              } catch (e) {
                print('⚠️ YELP->GEMINI: Failed to get place details: $e');
                // Still create a basic Location from the extracted data
                if (firstResult.coordinates != null) {
                  geminiFoundLocation = Location(
                    placeId: firstResult.placeId,
                    latitude: firstResult.coordinates!.latitude,
                    longitude: firstResult.coordinates!.longitude,
                    address: firstResult.address,
                    displayName: firstResult.name,
                    website: firstResult.website,
                  );
                }
              }
            } else if (firstResult.coordinates != null) {
              // No placeId but we have coordinates - create a basic Location
              geminiFoundLocation = Location(
                placeId: firstResult.placeId,
                latitude: firstResult.coordinates!.latitude,
                longitude: firstResult.coordinates!.longitude,
                address: firstResult.address,
                displayName: firstResult.name,
                website: firstResult.website,
              );
            }
          } else {
            print('⚠️ YELP->GEMINI: No locations found by AI');
          }
        } catch (e) {
          print('⚠️ YELP->GEMINI: AI extraction failed: $e');
        }
      }

      // If Gemini found a valid location, use it directly
      if (geminiFoundLocation != null &&
          geminiFoundLocation.placeId != null &&
          geminiFoundLocation.placeId!.isNotEmpty) {
        print('✅ YELP->GEMINI: Using Gemini-found location directly');

        Map<String, dynamic> resultData = {
          'location': geminiFoundLocation,
          'businessName': businessName,
          'yelpUrl': url,
        };
        _businessDataCache[cacheKey] = resultData;
        _fillFormWithGoogleMapsData(
          geminiFoundLocation,
          businessName,
          geminiFoundLocation.website ?? "",
          yelpUrl,
        );
        return resultData;
      }

      // --- FALLBACK: Traditional Google Places Search ---
      print('🔍 YELP: Falling back to traditional Google Places search');

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
              if (yelpWord.length > 2) {
                // Only consider meaningful words
                for (String googleWord in googleWords) {
                  if (googleWord.contains(yelpWord) ||
                      yelpWord.contains(googleWord)) {
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
            } else {}
          }

          if (isChainOrGeneric && isCorrectBusiness) {
            if (businessCity.isNotEmpty && foundLocation.city != null) {
              String googleCityLower = foundLocation.city!.toLowerCase();
              String yelpCityLower = businessCity.toLowerCase();
              if (!googleCityLower.contains(yelpCityLower) &&
                  !yelpCityLower.contains(googleCityLower)) {
                isCorrectBusiness = false;
              } else {}
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
        validateStatus: (status) => status != null && status < 500,
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
          final titleRegex =
              RegExp(r'<title>([^<]+)</title>', caseSensitive: false);
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

        if (addressMatch != null ||
            cityMatch != null ||
            stateMatch != null ||
            businessName.isNotEmpty) {
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
    int highestScore = -1;

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
      Location location, String businessName, String yelpUrl) async {
    // Ensured async
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
    targetCard ??= provider.experienceCards.isNotEmpty
        ? provider.experienceCards.first
        : null;

    if (targetCard == null) {
      return;
    }

    // --- ADDED: Duplicate Check ---
    FocusManager.instance.primaryFocus?.unfocus(); // MODIFIED
    await Future.microtask(() {}); // ADDED
    Experience? existingExperience = await _checkForDuplicateExperienceDialog(
      context: context,
      card: targetCard,
      placeIdToCheck: location.placeId,
    );

    if (existingExperience != null) {
      provider.updateCardWithExistingExperience(
          targetCard!.id, existingExperience);
      // Clear loading state since location is set via existing experience
      if (mounted) {
        setState(() {
          targetCard!.isSelectingLocation = false;
        });
      }
      // Potentially update _yelpPreviewFutures if the existing experience has a different placeId/structure
      // For now, we assume the existingExperience's details are sufficient and don't re-trigger preview future updates here.
      return; // Early return
    }

    // If no match by placeId, or user chose "Create New", check by title
    FocusManager.instance.primaryFocus?.unfocus(); // MODIFIED
    await Future.microtask(() {}); // ADDED
    existingExperience = await _checkForDuplicateExperienceDialog(
      context: context,
      card: targetCard,
      titleToCheck: location.displayName ?? businessName,
    );

    if (existingExperience != null) {
      provider.updateCardWithExistingExperience(
          targetCard!.id, existingExperience);
      // Clear loading state since location is set via existing experience
      if (mounted) {
        setState(() {
          targetCard!.isSelectingLocation = false;
        });
      }
      return; // Early return
    }
    // --- END ADDED ---

    final String titleToSet = location.displayName ?? businessName;
    final String addressToSet = location.address ?? '';
    final String websiteToSet = location.website ?? '';
    final String? placeIdForPreviewToSet = location.placeId;
    final String cardId = targetCard.id; // Capture card ID before timer

    // Debounce the update to prevent rapid rebuilds
    _locationUpdateDebounce?.cancel();
    _locationUpdateDebounce = Timer(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      provider.updateCardFromShareDetails(
        cardId: cardId,
        location: location,
        title: titleToSet,
        yelpUrl: yelpUrl,
        website: websiteToSet,
        placeIdForPreview: placeIdForPreviewToSet,
        searchQueryText: addressToSet,
      );

      if (mounted) {
        setState(() {
          // Clear loading state after location is actually set
          // Find the card by cardId to ensure we're updating the correct one
          final card = provider.experienceCards.firstWhere(
            (c) => c.id == cardId,
            orElse: () => provider.experienceCards.first,
          );
          card.isSelectingLocation = false;
          
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
          } else {}
        });
      }
    });
  }

  void _fillFormWithGoogleMapsData(Location location, String placeName,
      String websiteUrl, String originalMapsUrl) async {
    // Ensured async
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
    await Future.microtask(() {}); // ADDED
    Experience? existingExperience = await _checkForDuplicateExperienceDialog(
      context: context,
      card: firstCard,
      placeIdToCheck: location.placeId,
    );

    if (existingExperience != null) {
      provider.updateCardWithExistingExperience(
          firstCard.id, existingExperience);
      // Clear loading state since location is set via existing experience
      if (mounted) {
        setState(() {
          firstCard.isSelectingLocation = false;
        });
      }
      // Similar to Yelp, preview futures might need updating based on existingExperience.
      return; // Early return
    }

    // If no match by placeId, or user chose "Create New", check by title
    FocusManager.instance.primaryFocus?.unfocus(); // ADDED
    await Future.microtask(() {}); // ADDED
    existingExperience = await _checkForDuplicateExperienceDialog(
      context: context,
      card: firstCard,
      titleToCheck: location.displayName ?? placeName,
    );

    if (existingExperience != null) {
      provider.updateCardWithExistingExperience(
          firstCard.id, existingExperience);
      // Clear loading state since location is set via existing experience
      if (mounted) {
        setState(() {
          firstCard.isSelectingLocation = false;
        });
      }
      return; // Early return
    }
    // --- END ADDED ---

    final String titleToSet = location.displayName ?? placeName;
    final String addressToSet = location.address ?? '';
    final String websiteToSet = websiteUrl;
    final String? placeIdForPreviewToSet = location.placeId;
    final String cardId = firstCard.id; // Capture card ID before timer

    // Debounce the update to prevent rapid rebuilds
    _locationUpdateDebounce?.cancel();
    _locationUpdateDebounce = Timer(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      provider.updateCardFromShareDetails(
        cardId: cardId,
        location: location,
        title: titleToSet,
        mapsUrl: originalMapsUrl,
        website: websiteToSet,
        placeIdForPreview: placeIdForPreviewToSet,
        searchQueryText: addressToSet,
      );

      if (mounted) {
        setState(() {
          // Clear loading state after location is actually set
          firstCard.isSelectingLocation = false;
          
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
          } else {}
        });
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
    bool shouldAttemptNavigation =
        false; // Renamed from navigateAway for clarity

    try {
      if (!mounted) return;

      final now = DateTime.now();
      // Normalize shared paths so that Yelp text shares store only the Yelp URL
      final List<String> uniqueMediaPaths = _currentSharedFiles
          .map((f) {
            final String original = f.path;
            // For text/url types containing a Yelp link, extract and store only the Yelp URL
            if (f.type == SharedMediaType.text ||
                f.type == SharedMediaType.url) {
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
          })
          .toSet()
          .toList();

      final Map<String, String> mediaPathToItemIdMap = {};
      for (final path in uniqueMediaPaths) {
        try {
          SharedMediaItem? existingItem;
          try {
            SharedMediaItem? foundItem =
                await _experienceService.findSharedMediaItemByPath(path);
            if (!mounted) return;

            if (foundItem != null && foundItem.ownerUserId == currentUserId) {
              if (foundItem.isPrivate != _sharedMediaIsPrivate) {
                try {
                  await _experienceService.updateSharedMediaPrivacy(
                      foundItem.id, _sharedMediaIsPrivate);
                  foundItem =
                      foundItem.copyWith(isPrivate: _sharedMediaIsPrivate);
                } catch (e) {
                  debugPrint(
                      'ReceiveShareScreen: Failed to update media privacy for ${foundItem?.id}: $e');
                }
              }
              existingItem = foundItem;
            } else if (foundItem != null) {
            } else {}
          } catch (e) {}

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
              isPrivate: _sharedMediaIsPrivate,
            );
            String newItemId =
                await _experienceService.createSharedMediaItem(newItem);
            if (!mounted) return;
            mediaPathToItemIdMap[path] = newItemId;
          }
        } catch (e) {
          errors.add("Error processing media: ${path.split('/').last}");
        }
      }

      if (mediaPathToItemIdMap.length != uniqueMediaPaths.length &&
          errors.isEmpty) {
        // If there was an issue creating media items but no errors were added to the list yet (e.g. silent failure)
        errors.add("Error processing some media files.");
      }

      if (errors.isEmpty) {
        // Only proceed with card processing if media pre-processing was okay
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
            final bool shouldClearNotes = notes.isEmpty;
            final String categoryIdToSave = card.selectedCategoryId!;
            bool canProcessPublicExperience =
                placeId.isNotEmpty && cardLocation != null;
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
                description: notes,
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
                otherColorCategoryIds: card.selectedOtherColorCategoryIds,
                otherCategories: card.selectedOtherCategoryIds,
                isPrivate: card.isPrivate,
              );
              targetExperienceId =
                  await _experienceService.createExperience(newExperience);
              if (!mounted) return;
              currentExperienceData = newExperience.copyWith();
              currentExperienceData =
                  await _experienceService.getExperience(targetExperienceId);
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
                  description: notes.isNotEmpty
                      ? notes
                      : currentExperienceData.description,
                  location: locationToSave,
                  categoryId: categoryIdToSave,
                  yelpUrl: cardYelpUrl.isNotEmpty ? cardYelpUrl : null,
                  website: cardWebsite.isNotEmpty ? cardWebsite : null,
                  additionalNotes: notes.isNotEmpty ? notes : null,
                  clearAdditionalNotes: shouldClearNotes,
                  updatedAt: now,
                  editorUserIds: currentExperienceData.editorUserIds
                          .contains(currentUserId)
                      ? currentExperienceData.editorUserIds
                      : [...currentExperienceData.editorUserIds, currentUserId],
                  colorCategoryId: colorCategoryIdToSave,
                  otherColorCategoryIds: card.selectedOtherColorCategoryIds,
                  otherCategories: card.selectedOtherCategoryIds,
                  isPrivate: card.isPrivate);
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
                  otherColorCategoryIds: !isNewExperience
                      ? card.selectedOtherColorCategoryIds
                      : currentExperienceData.otherColorCategoryIds,
                  otherCategories: !isNewExperience
                      ? card.selectedOtherCategoryIds
                      : currentExperienceData.otherCategories,
                  sharedMediaItemIds: finalMediaIds,
                  updatedAt: now,
                  isPrivate: card.isPrivate,
                );
                await _experienceService.updateExperience(experienceToUpdate);
                if (!mounted) return;
              } else {
                if (!isNewExperience && relevantMediaItemIds.isNotEmpty)
                  updateCount--; // Correct if only media was new and no other field changed
              }
            } else {
              continue;
            }
            for (final mediaItemId in relevantMediaItemIds) {
              try {
                await _experienceService.addExperienceLinkToMediaItem(
                    mediaItemId, targetExperienceId);
                if (!mounted) return;
              } catch (e) {}
            }
            final bool shouldUpdatePublicExperience =
                canProcessPublicExperience &&
                    !_sharedMediaIsPrivate &&
                    uniqueMediaPaths.isNotEmpty;
            if (shouldUpdatePublicExperience) {
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
                await _experienceService
                    .updatePublicExperienceMediaAndMaybeYelp(
                        existingPublicExp.id, uniqueMediaPaths,
                        newYelpUrl:
                            cardYelpUrl.isNotEmpty ? cardYelpUrl : null);
                if (!mounted) return;
              }
            } else {}
            if (selectedCategoryObject != null) {
              try {
                await _experienceService
                    .updateCategoryLastUsedTimestamp(selectedCategoryObject.id);
                if (!mounted) return;
              } catch (e) {}
            } else {}
            if (colorCategoryIdToSave != null) {
              try {
                await _experienceService.updateColorCategoryLastUsedTimestamp(
                    colorCategoryIdToSave);
                if (!mounted) return;
              } catch (e) {}
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
          shouldAttemptNavigation =
              true; // Still navigate if some parts succeeded
        }
      }

      if (!mounted) return;
      _showSnackBar(context, message);

      if (experienceCards.isNotEmpty && (successCount > 0 || updateCount > 0)) {
        final lastProcessedCard = experienceCards.last;
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;

        if (lastProcessedCard.selectedCategoryId != null) {
          await prefs.setString(AppConstants.lastUsedCategoryKey,
              lastProcessedCard.selectedCategoryId!);
          if (!mounted) return;
        } else {
          await prefs.remove(AppConstants.lastUsedCategoryKey);
          if (!mounted) return;
        }

        if (lastProcessedCard.selectedColorCategoryId != null) {
          await prefs.setString(AppConstants.lastUsedColorCategoryKey,
              lastProcessedCard.selectedColorCategoryId!);
          if (!mounted) return;
        } else {
          await prefs.remove(AppConstants.lastUsedColorCategoryKey);
          if (!mounted) return;
        }

        // ADDED: Save last used other categories
        await prefs.setStringList(AppConstants.lastUsedOtherCategoriesKey,
            lastProcessedCard.selectedOtherCategoryIds);
        await prefs.setStringList(AppConstants.lastUsedOtherColorCategoriesKey,
            lastProcessedCard.selectedOtherColorCategoryIds);
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
    // Suspend media previews to prevent auto-resume/fullscreen when returning
    if (mounted) {
      setState(() {
        _suspendMediaPreviews = true;
      });
    }

    dynamic result;
    try {
      result = await Navigator.push(
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
    } finally {
      if (mounted) {
        setState(() {
          _suspendMediaPreviews = false;
        });
      }
    }

    if (result == null || !mounted) {
      return;
    }

    Future.microtask(() {
      if (mounted) {
        // Check mounted before using context
        FocusScope.of(context).unfocus();
      }
    });

    if (!mounted) return;

    setState(() {
      card.isSelectingLocation = true;
    });

    final Location selectedLocationFromResult =
        result is Map ? result['location'] : result as Location;
    final provider = context.read<ReceiveShareProvider>();

    try {
      // --- ADDED: Duplicate Check based on selected location's Place ID ---
      if (selectedLocationFromResult.placeId != null &&
          selectedLocationFromResult.placeId!.isNotEmpty) {
        FocusManager.instance.primaryFocus?.unfocus(); // MODIFIED
        await Future.microtask(() {}); // ADDED
        final Experience? existingExperienceByPlaceId =
            await _checkForDuplicateExperienceDialog(
          context: context,
          card: card,
          placeIdToCheck: selectedLocationFromResult.placeId,
        );
        if (mounted && existingExperienceByPlaceId != null) {
          provider.updateCardWithExistingExperience(
              card.id, existingExperienceByPlaceId);
          return; // Stop further processing if existing experience is used
        }
      }
      // --- END ADDED ---

      final Location selectedLocation =
          selectedLocationFromResult; // Use the original variable name for clarity below

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

          if (card.originalShareType == ShareType.yelp ||
              card.originalShareType == ShareType.maps) {
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
            _showSnackBar(context,
                "Error updating location details from Yelp context: $e");
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

          if (shouldUpdateFuturesForGenericPick &&
              placeId != null &&
              placeId.isNotEmpty) {
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
    } finally {
      if (mounted) {
        setState(() {
          card.isSelectingLocation = false;
        });
      }
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
          builder: (BuildContext scrollSheetContext,
              ScrollController scrollController) {
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
  }) async {
    // Ensured async
    final provider = context.read<ReceiveShareProvider>();
    final card =
        provider.experienceCards.firstWhere((c) => c.id == cardId, orElse: () {
      // This should ideally not happen if cardId is always valid
      // For safety, let's assume if card not found, we can't proceed with title check.
      throw Exception(
          "Card not found for ID $cardId in _handleExperienceCardFormUpdate");
    });

    // --- ADDED: Duplicate Check for Title Submission ---
    if (newTitleFromCard != null && newTitleFromCard.isNotEmpty) {
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus(); // MODIFIED
      await Future.microtask(() {}); // ADDED
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
    } else if (refreshCategories) {
      // UNCOMMENTED
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
        } else {}
      });
    } else {}
    // print("ReceiveShareScreen._handleExperienceCardFormUpdate: LOGIC TEMPORARILY COMMENTED OUT"); // REMOVE THIS LINE
  }

  // --- ADDED FOR SCROLLING FAB ---
  void _scrollListener() {
    if (!_scrollController.hasClients || !mounted) return;

    final experienceCardsContext = _experienceCardsSectionKey.currentContext;
    if (experienceCardsContext != null) {
      final RenderBox experienceBox =
          experienceCardsContext.findRenderObject() as RenderBox;
      final double experienceBoxTopOffsetInViewport =
          experienceBox.localToGlobal(Offset.zero).dy;
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

    if (_showUpArrowForFab) {
      // Scroll Up

      // Check for expanded Instagram preview
      if (_isInstagramPreviewExpanded &&
          _currentVisibleInstagramUrl != null &&
          _instagramPreviewKeys.containsKey(_currentVisibleInstagramUrl)) {
        final instagramKey =
            _instagramPreviewKeys[_currentVisibleInstagramUrl]!;
        final instagramContext = instagramKey.currentContext;
        if (instagramContext != null) {
          final RenderBox instagramRenderBox =
              instagramContext.findRenderObject() as RenderBox;
          final RenderObject? scrollableRenderObject = _scrollController
              .position.context.storageContext
              .findRenderObject();

          if (scrollableRenderObject == null ||
              scrollableRenderObject is! RenderBox) {
            _scrollToMediaPreviewTop(); // Fallback
            return;
          }
          final RenderBox scrollableBox = scrollableRenderObject;

          // Offset of the Instagram widget relative to the screen
          final double instagramGlobalOffsetY =
              instagramRenderBox.localToGlobal(Offset.zero).dy;
          // Offset of the Scrollable area itself relative to the screen
          final double scrollableGlobalOffsetY =
              scrollableBox.localToGlobal(Offset.zero).dy;
          // Offset of the Instagram widget relative to the top of the VISIBLE part of the scrollable area
          final double instagramOffsetYInViewport =
              instagramGlobalOffsetY - scrollableGlobalOffsetY;
          // Absolute offset of the Instagram widget from the VERY TOP of all scrollable content
          final double instagramTopOffsetInScrollableContent =
              _scrollController.offset + instagramOffsetYInViewport;

          const double instagramExpandedHeight = 1200.0;
          double calculatedTargetOffset =
              instagramTopOffsetInScrollableContent +
                  (instagramExpandedHeight / 2.5);
          double targetOffset = calculatedTargetOffset.clamp(
              0.0, _scrollController.position.maxScrollExtent);

          _scrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        } else {
          // Fallback if key context is lost
          _scrollToMediaPreviewTop();
        }
      } else {
        _scrollToMediaPreviewTop();
      }
    } else {
      // Scroll Down (_showUpArrowForFab is false)

      // Get the experience cards from provider
      final provider = context.read<ReceiveShareProvider>();
      final experienceCards = provider.experienceCards;

      if (experienceCards.isNotEmpty) {
        final experienceCardsSectionContext =
            _experienceCardsSectionKey.currentContext;

        if (experienceCardsSectionContext != null) {
          // Get current position of experience cards section
          final RenderBox experienceBox =
              experienceCardsSectionContext.findRenderObject() as RenderBox;
          final double experienceBoxTopOffsetInViewport =
              experienceBox.localToGlobal(Offset.zero).dy;
          final double sectionHeight = experienceBox.size.height;

          // Calculate position to scroll to show the top of the bottom-most experience card
          // We want to position the last card's TOP at the top of the viewport (below app header)
          final double screenHeight = MediaQuery.of(context).size.height;
          final double appBarHeight = AppBar().preferredSize.height +
              MediaQuery.of(context).padding.top;

          // Estimate the height of each experience card (approximate)
          final int cardCount = experienceCards.length;
          final double estimatedCardHeight =
              cardCount > 0 ? sectionHeight / cardCount : 400.0;

          // Calculate offset to show the LAST card at the top of the visible area
          final double lastCardStartPosition =
              experienceBoxTopOffsetInViewport +
                  sectionHeight -
                  estimatedCardHeight;
          final double targetScrollOffset =
              _scrollController.offset + lastCardStartPosition - appBarHeight;

          final double clampedOffset = targetScrollOffset.clamp(
              0.0, _scrollController.position.maxScrollExtent);

          _scrollController.animateTo(
            clampedOffset,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      } else {}
    }
  }

  void _scrollToMediaPreviewTop() {
    final mediaPreviewContext = _mediaPreviewListKey
        .currentContext; // This is key for the *first* media item.
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text('Save Content'),
        leading: IconButton(
          icon: Icon(Platform.isIOS ? Icons.arrow_back_ios : Icons.arrow_back),
          onPressed: () {
            _sharingService.markShareFlowAsInactive();
            if (mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PrivacyToggleButton(
                  isPrivate: _sharedMediaIsPrivate,
                  onPressed: () {
                    setState(() {
                      _sharedMediaIsPrivate = !_sharedMediaIsPrivate;
                    });
                  },
                ),
                const SizedBox(width: 6),
                PrivacyTooltipIcon(
                  message:
                      'If public, the content you are saving will show up in Discovery and your public profile page (not yet implemented) to be viewed by others. If private, it will only be visible to you.',
                ),
              ],
            ),
          ),
        ],
      ),
      body: ExcludeSemantics(
        child: Container(
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
                    future:
                        _combinedCategoriesFuture, // MODIFIED: Use stable combined future
                    builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
                      // Primary Loading State: Show spinner if the future is null (early init) or still running.
                      if (_combinedCategoriesFuture == null ||
                          snapshot.connectionState == ConnectionState.waiting) {
                        // print("FutureBuilder: STATE_WAITING (Future is null or connection is waiting)");
                        // In URL-first mode, show the UI with URL bar so user can proceed
                        if (widget.requireUrlFirst) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildSharedUrlBar(showInstructions: true),
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
                      if (snapshot.hasData &&
                          snapshot.data != null &&
                          snapshot.data!.length >= 2) {
                        // Data is present and seems structurally correct.
                        // The lists _userCategories and _userColorCategories should be populated by now.
                        // print("FutureBuilder: STATE_HAS_DATA. Categories loaded: Text=${_userCategories.length}, Color=${_userColorCategories.length}");

                        // Proceed with the main UI build
                        return Column(
                          children: [
                            _buildSharedUrlBar(
                                showInstructions: _currentSharedFiles.isEmpty),
                            const SizedBox(height: 8),
                            // Gate the rest of content when required
                            Expanded(
                              child: AbsorbPointer(
                                absorbing: !_urlGateOpen,
                                child: Opacity(
                                  opacity: _urlGateOpen ? 1.0 : 0.4,
                                  child: Stack(
                                    // WRAPPED IN STACK FOR FAB
                                    children: [
                                      SingleChildScrollView(
                                        controller:
                                            _scrollController, // ATTACHED SCROLL CONTROLLER
                                        padding:
                                            const EdgeInsets.only(bottom: 80),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Re-enable the shared files preview list
                                            if (_currentSharedFiles.isEmpty)
                                              const Padding(
                                                padding: EdgeInsets.all(16.0),
                                                child: Center(
                                                    child: Text(
                                                        'No shared content received')),
                                              )
                                            else
                                              Consumer<ReceiveShareProvider>(
                                                  key:
                                                      _mediaPreviewListKey, // MOVED KEY HERE
                                                  builder: (context, provider,
                                                      child) {
                                                    final experienceCards =
                                                        provider
                                                            .experienceCards;
                                                    final firstCard =
                                                        experienceCards
                                                                .isNotEmpty
                                                            ? experienceCards
                                                                .first
                                                            : null;

                                                    return ListView.builder(
                                                      padding: EdgeInsets.zero,
                                                      shrinkWrap: true,
                                                      physics:
                                                          const NeverScrollableScrollPhysics(),
                                                      itemCount:
                                                          _currentSharedFiles
                                                              .length,
                                                      itemBuilder:
                                                          (context, index) {
                                                        final file =
                                                            _currentSharedFiles[
                                                                index];

                                                        bool isInstagram =
                                                            false;
                                                        bool isTikTok = false;
                                                        if (file.type ==
                                                                SharedMediaType
                                                                    .text ||
                                                            file.type ==
                                                                SharedMediaType
                                                                    .url) {
                                                          String? url =
                                                              _extractFirstUrl(
                                                                  file.path);
                                                          if (url != null) {
                                                            if (url.contains(
                                                                'instagram.com')) {
                                                              isInstagram =
                                                                  true;
                                                            } else if (url.contains(
                                                                    'tiktok.com') ||
                                                                url.contains(
                                                                    'vm.tiktok.com')) {
                                                              isTikTok = true;
                                                            }
                                                          }
                                                        }
                                                        final double
                                                            horizontalPadding =
                                                            (isInstagram ||
                                                                    isTikTok)
                                                                ? 0.0
                                                                : 16.0;
                                                        final double
                                                            verticalPadding =
                                                            8.0;

                                                        return Padding(
                                                          key: ValueKey(
                                                              file.path),
                                                          padding: EdgeInsets
                                                              .symmetric(
                                                            horizontal:
                                                                horizontalPadding,
                                                            vertical:
                                                                verticalPadding,
                                                          ),
                                                          child: Card(
                                                            color: Colors.white,
                                                            elevation: 2.0,
                                                            margin: (isInstagram ||
                                                                    isTikTok)
                                                                ? EdgeInsets
                                                                    .zero
                                                                : const EdgeInsets
                                                                    .only(
                                                                    bottom: 0),
                                                            shape:
                                                                RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                      (isInstagram ||
                                                                              isTikTok)
                                                                          ? 0
                                                                          : 8),
                                                            ),
                                                            clipBehavior:
                                                                (isInstagram ||
                                                                        isTikTok)
                                                                    ? Clip
                                                                        .antiAlias
                                                                    : Clip.none,
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                _buildMediaPreview(
                                                                    file,
                                                                    firstCard,
                                                                    index),
                                                              ],
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                    );
                                                  }),
                                            Selector<ReceiveShareProvider, int>(
                                              key: const ValueKey(
                                                  'experience_cards_selector'),
                                              selector: (_, provider) =>
                                                  provider
                                                      .experienceCards.length,
                                              builder: (context, cardCount, _) {
                                                final selectedExperienceCards =
                                                    context
                                                        .read<
                                                            ReceiveShareProvider>()
                                                        .experienceCards;
                                                return _ExperienceCardsSection(
                                                  key: const ValueKey(
                                                      'cards_section_stable'),
                                                  userCategories:
                                                      _userCategories,
                                                  userColorCategories:
                                                      _userColorCategories,
                                                  userCategoriesNotifier:
                                                      _userCategoriesNotifier,
                                                  userColorCategoriesNotifier:
                                                      _userColorCategoriesNotifier,
                                                  removeExperienceCard:
                                                      _removeExperienceCard,
                                                  showLocationPicker:
                                                      _showLocationPicker,
                                                  selectSavedExperienceForCard:
                                                      _selectSavedExperienceForCard,
                                                  handleCardFormUpdate:
                                                      _handleExperienceCardFormUpdate,
                                                  addExperienceCard:
                                                      _addExperienceCard,
                                                  isSpecialUrl: _isSpecialUrl,
                                                  extractFirstUrl:
                                                      _extractFirstUrl,
                                                  currentSharedFiles:
                                                      _currentSharedFiles,
                                                  experienceCards:
                                                      selectedExperienceCards,
                                                  sectionKey:
                                                      _experienceCardsSectionKey,
                                                  onYelpButtonTapped:
                                                      _trackYelpButtonTapped,
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      // --- ADDED FAB ---
                                      Positioned(
                                        bottom: 16, // Adjust as needed
                                        right: 16, // Adjust as needed
                                        child: FloatingActionButton(
                                          backgroundColor:
                                              Theme.of(context).primaryColor,
                                          foregroundColor: Colors.white,
                                          shape:
                                              const CircleBorder(), // ENSURE CIRCULAR
                                          onPressed: _handleFabPress,
                                          child: Icon(_showUpArrowForFab
                                              ? Icons.arrow_upward
                                              : Icons.arrow_downward),
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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  OutlinedButton(
                                    onPressed: widget.onCancel,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.grey[700],
                                    ),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed:
                                        _isSaving ? null : _saveExperience,
                                    icon: _isSaving
                                        ? Container(
                                            width: 20,
                                            height: 20,
                                            padding: const EdgeInsets.all(2.0),
                                            child:
                                                const CircularProgressIndicator(
                                                    strokeWidth: 3,
                                                    color: Colors.white),
                                          )
                                        : const Icon(Icons.save),
                                    label: Text(_isSaving
                                        ? 'Saving...'
                                        : 'Save Experience(s)'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          Theme.of(context).primaryColor,
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
                            child:
                                Text("Error: Could not load category data."));
                      }
                    },
                  ),
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
            mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
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
      case SharedMediaType.url:
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

  Widget _buildUrlPreview(String url, ExperienceCardData? card, int index,
      [String? sharedText]) {
    if (url.contains('yelp.com/biz') || url.contains('yelp.to/')) {
      return YelpPreviewWidget(
        yelpUrl: url,
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
      if (!_instagramPreviewKeys.containsKey(url)) {
        // Ensure key exists
        _instagramPreviewKeys[url] = GlobalKey<_InstagramPreviewWrapperState>();
      }
      // If this is the first media item and it's instagram, update _currentVisibleInstagramUrl
      // This logic is a bit tricky here as _buildMediaPreview is called inside a loop.
      // We set _currentVisibleInstagramUrl more reliably in the ListView builder.

      if (_suspendMediaPreviews) {
        return SizedBox(
          height: 840.0,
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: const Text(
              'Instagram preview paused',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        );
      }

      return InstagramPreviewWrapper(
        key: _instagramPreviewKeys[
            url], // Use the specific key for this Instagram preview
        url: url,
        launchUrlCallback: _launchUrl,
        onExpansionChanged: (isExpanded, instaUrl) =>
            _onInstagramExpansionChanged(
                isExpanded, instaUrl), // CORRECTED: Match signature
      );
    }

    if (url.contains('tiktok.com') || url.contains('vm.tiktok.com')) {
      if (_suspendMediaPreviews) {
        final bool isPhoto = _tiktokPhotoStatus[url] == true;
        final double height = isPhoto ? 350.0 : 700.0;
        return SizedBox(
          height: height,
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: const Text(
              'TikTok preview paused',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        );
      }

      // Ensure TikTok preview key exists
      if (!_tiktokPreviewKeys.containsKey(url)) {
        _tiktokPreviewKeys[url] = GlobalKey<TikTokPreviewWidgetState>();
      }
      return TikTokPreviewWidget(
        key: _tiktokPreviewKeys[url],
        url: url,
        launchUrlCallback: _launchUrl,
        onPhotoDetected: (detectedUrl, isPhoto) {
          // Track whether this TikTok URL is a photo carousel
          _tiktokPhotoStatus[detectedUrl] = isPhoto;
        },
        onOEmbedDataLoaded: (data) {
          // Automatically extract locations from TikTok caption
          _handleTikTokOEmbedData(url, data);
        },
      );
    }

    if (url.contains('facebook.com') ||
        url.contains('fb.com') ||
        url.contains('fb.watch')) {
      // Ensure Facebook preview key exists
      if (!_facebookPreviewKeys.containsKey(url)) {
        _facebookPreviewKeys[url] = GlobalKey<FacebookPreviewWidgetState>();
      }
      // Use taller height for Facebook Reels
      final isReel = url.contains('/reel/') || url.contains('/reels/');
      final facebookHeight = isReel ? 700.0 : 500.0;

      return FacebookPreviewWidget(
        key: _facebookPreviewKeys[url],
        url: url,
        height: facebookHeight,
        onWebViewCreated: (controller) {
          // Handle controller if needed
        },
        onPageFinished: (loadedUrl) {
          // Skip auto-extraction for Facebook Reels - their DOM structure is too
          // obfuscated for reliable scraping. Users can use "Scan Preview" instead.
          final isReel = url.contains('/reel/') || url.contains('/reels/');
          if (isReel) {
            print('📘 FACEBOOK: Skipping auto-extraction for Reel (use Scan Preview instead)');
            return;
          }
          
          // Automatically extract locations from regular Facebook posts only
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) {
              _onFacebookPageLoaded(url);
            }
          });
        },
        launchUrlCallback: _launchUrl,
      );
    }

    if (url.contains('youtube.com') ||
        url.contains('youtu.be') ||
        url.contains('youtube.com/shorts')) {
      // Ensure YouTube preview key exists
      if (!_youtubePreviewKeys.containsKey(url)) {
        _youtubePreviewKeys[url] = GlobalKey<YouTubePreviewWidgetState>();
      }
      return YouTubePreviewWidget(
        key: _youtubePreviewKeys[url],
        url: url,
        launchUrlCallback: _launchUrl,
      );
    }

    // Google Knowledge Graph URLs - use WebView
    if (url.contains('g.co/kgs/') || url.contains('share.google/')) {
      // Ensure Google KG preview key exists
      if (!_googleKgPreviewKeys.containsKey(url)) {
        _googleKgPreviewKeys[url] =
            GlobalKey<GoogleKnowledgeGraphPreviewWidgetState>();
      }
      return GoogleKnowledgeGraphPreviewWidget(
        key: _googleKgPreviewKeys[url],
        url: url,
        launchUrlCallback: _launchUrl,
      );
    }

    // Generic/fallback URLs - use WebView for screenshot support
    // Ensure Web URL preview key exists
    if (!_webUrlPreviewKeys.containsKey(url)) {
      _webUrlPreviewKeys[url] = GlobalKey<WebUrlPreviewWidgetState>();
    }
    return WebUrlPreviewWidget(
      key: _webUrlPreviewKeys[url],
      url: url,
      launchUrlCallback: _launchUrl,
      onPageFinished: (loadedUrl) => _onGenericWebPageLoaded(url),
    );
  }

  /// Called when a generic web page finishes loading - auto-triggers location scan
  void _onGenericWebPageLoaded(String url) {
    // Only auto-scan once per URL
    if (_autoScannedUrls.contains(url)) {
      print('🔄 AUTO-SCAN: Already scanned $url, skipping');
      return;
    }
    
    // Don't auto-scan if already processing
    if (_isProcessingScreenshot || _isExtractingLocation) {
      print('🔄 AUTO-SCAN: Already processing, skipping auto-scan');
      return;
    }
    
    // Mark as scanned
    _autoScannedUrls.add(url);
    
    print('🚀 AUTO-SCAN: Web page loaded, automatically scanning for locations...');
    
    // Small delay to ensure WebView is fully rendered
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && !_isProcessingScreenshot && !_isExtractingLocation) {
        _scanPageContent();
      }
    });
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

  Future<void> _processGoogleKnowledgeUrl(
      String url, SharedMediaFile file) async {
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
    } catch (e) {}

    // First, try to use Knowledge Graph API to get entity information
    if (entityName != null && entityName.isNotEmpty) {
      final kgResults =
          await _knowledgeGraphService.searchEntities(entityName, limit: 10);

      if (kgResults.isNotEmpty) {
        Map<String, dynamic>? bestPlaceEntity =
            _findBestPlaceEntity(kgResults, entityName);

        if (bestPlaceEntity != null) {
          // Extract useful information from Knowledge Graph
          final kgName = bestPlaceEntity['name'] as String?;
          final kgDescription =
              _knowledgeGraphService.extractDescription(bestPlaceEntity);
          final kgImageUrl =
              _knowledgeGraphService.extractImageUrl(bestPlaceEntity);
          final kgWebsite = bestPlaceEntity['url'] as String?;

          if (kgDescription != null) {}
          if (kgWebsite != null) {}

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
          if (kgResults.isNotEmpty) {}
        }
      }
    }

    // If Knowledge Graph didn't help, fall back to original logic
    // Try to resolve the shortened URL
    try {
      final resolvedUrl = await _resolveShortUrl(url);
      if (resolvedUrl != null &&
          (resolvedUrl.contains('google.com/maps') ||
              resolvedUrl.contains('maps.app.goo.gl') ||
              resolvedUrl.contains('goo.gl/maps'))) {
        // It resolved to a Google Maps URL, process it as such
        firstCard.originalShareType = ShareType.maps;
        
        // Set loading state to show spinner in location field
        firstCard.isSelectingLocation = true;
        if (mounted) {
          setState(() {}); // Trigger rebuild to show loading indicator
        }
        
        // FIXED: Store with original URL key, not resolved URL key
        // Start the extraction and handle completion
        _yelpPreviewFutures[url] = _getLocationFromMapsUrl(resolvedUrl)
            .then((result) {
          // Loading state will be cleared in _fillFormWithGoogleMapsData
          // after the location is actually set on the card
          // Only clear here if no location was found (result is null)
          if (result == null || result['location'] == null) {
            firstCard.isSelectingLocation = false;
            if (mounted) {
              setState(() {}); // Trigger rebuild to hide loading indicator
            }
          }
          return result;
        }).catchError((error) {
          // Clear loading state on error
          firstCard.isSelectingLocation = false;
          if (mounted) {
            setState(() {});
          }
          print('❌ MAPS PROCESS (resolved): Location extraction error: $error');
          return null;
        });
      } else {
        // Didn't resolve to Maps, try to search for the location by name
        if (entityName != null && entityName.isNotEmpty) {
          firstCard.originalShareType = ShareType.maps;
          // Create a future that searches for the location with improved logic
          _yelpPreviewFutures[url] =
              _searchForLocationByNameImproved(entityName, url);
        } else {
          firstCard.originalShareType = ShareType.genericUrl;
        }
      }
    } catch (e) {
      if (entityName != null && entityName.isNotEmpty) {
        firstCard.originalShareType = ShareType.maps;
        _yelpPreviewFutures[url] =
            _searchForLocationByNameImproved(entityName, url);
      }
    }
  }

  // ADDED: Clean entity name to improve search accuracy
  String _cleanEntityName(String rawName) {
    String cleaned = rawName;

    // Remove common prefixes that might be added by sharing
    cleaned = cleaned.replaceAll(
        RegExp(r'^(Check out |Visit |About |)\s*', caseSensitive: false), '');

    // Remove URLs and content after blank lines while preserving entity names
    // This handles cases like "Entity Name\n\n https://url"
    cleaned = cleaned.replaceAll(
        RegExp(r'\n\s*\n.*$', multiLine: true, dotAll: true), '');

    // Remove any remaining URLs that might be on the same line or after single newlines
    cleaned =
        cleaned.replaceAll(RegExp(r'\n\s*https?://.*$', multiLine: true), '');

    // Clean up any remaining trailing whitespace and newlines
    cleaned = cleaned.trim();

    // Remove extra punctuation at the end
    cleaned = cleaned.replaceAll(RegExp(r'[,.!?]+$'), '');

    return cleaned;
  }

  // ADDED: Find the best place entity from Knowledge Graph results
  Map<String, dynamic>? _findBestPlaceEntity(
      List<Map<String, dynamic>> entities, String originalQuery) {
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
      if (types.contains('TouristAttraction') ||
          types.contains('Museum') ||
          types.contains('Park') ||
          types.contains('LandmarksOrHistoricalBuildings')) {
        score += 200;
      } else if (types.contains('Place')) {
        score += 100;
      }

      if (score > bestScore) {
        bestScore = score;
        bestPlace = entity;
      }
    }

    if (bestPlace != null) {}

    return bestPlace;
  }

  // IMPROVED: Search for location with better strategies and validation
  Future<Map<String, dynamic>?> _searchForLocationByNameImproved(
      String locationName, String originalUrl) async {
    try {
      // Try multiple search strategies
      List<String> searchQueries = _generateSearchQueries(locationName);

      for (String query in searchQueries) {
        List<Map<String, dynamic>> results =
            await _mapsService.searchPlaces(query);

        if (results.isNotEmpty) {
          // Find the best match from results
          Map<String, dynamic>? bestResult =
              _findBestLocationMatch(results, locationName, query);

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
                  originalUrl);

              return result;
            } else {}
          } else {}
        } else {}
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
  Map<String, dynamic>? _findBestLocationMatch(
      List<Map<String, dynamic>> results,
      String originalName,
      String searchQuery) {
    if (results.isEmpty) return null;
    if (results.length == 1) return results[0];

    Map<String, dynamic>? bestMatch;
    double bestScore = 0.0;

    for (final result in results) {
      final name =
          result['description'] as String? ?? result['name'] as String? ?? '';
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
      if (types.any((type) => [
            'tourist_attraction',
            'museum',
            'park',
            'establishment'
          ].contains(type))) {
        score += 25.0;
      }

      // Prefer results that are not just addresses
      if (!name.contains(RegExp(r'\d+.*\w+\s+(St|Ave|Rd|Dr|Blvd|Way)',
          caseSensitive: false))) {
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
          locationName, originalEntityName, kgEntity);

      for (String query in searchQueries) {
        List<List<Map<String, dynamic>>> resultSets = [];

        // Get user position first for better search accuracy
        Position? userPosition = await _getCurrentPosition();

        // First attempt: With location bias (prioritize local/regional results)
        if (userPosition != null) {
          List<Map<String, dynamic>> localResults =
              await _mapsService.searchPlaces(
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
        List<Map<String, dynamic>> globalResults =
            await _mapsService.searchPlaces(query);
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
                kgEntity);

            if (bestResult != null) {
              final placeId = bestResult['placeId'] as String?;
              if (placeId != null && placeId.isNotEmpty) {
                final location = await _mapsService.getPlaceDetails(placeId);

                // Use Knowledge Graph website if Maps doesn't have one
                String? finalWebsite = location.website;
                if ((finalWebsite == null || finalWebsite.isEmpty) &&
                    kgWebsite != null) {
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
                    originalUrl);

                // If we have a KG description, store it in the notes field
                if (kgDescription != null && mounted) {
                  final provider = context.read<ReceiveShareProvider>();
                  final firstCard = provider.experienceCards.first;
                  if (firstCard.notesController.text.isEmpty) {
                    firstCard.notesController.text = kgDescription;
                  }
                }

                return result;
              } else {}
            } else {}
          } else {}
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // ADDED: Generate search queries enhanced with Knowledge Graph data
  List<String> _generateSearchQueriesWithKGData(String kgName,
      String? originalEntityName, Map<String, dynamic>? kgEntity) {
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
      Map<String, dynamic>? kgEntity) {
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
      final name =
          result['description'] as String? ?? result['name'] as String? ?? '';
      final types = result['types'] as List<dynamic>? ?? [];
      final address = result['vicinity'] as String? ??
          result['formatted_address'] as String? ??
          '';

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
          types.any((type) =>
              ['tourist_attraction', 'point_of_interest'].contains(type))) {
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
      } else if (types.any((type) => [
            'tourist_attraction',
            'museum',
            'park',
            'establishment'
          ].contains(type))) {
        score += 25.0;
        scoreReasons.add('general place type match (+25)');
      }

      // Prefer non-address results for tourist attractions
      if (!name.contains(RegExp(r'\d+.*\w+\s+(St|Ave|Rd|Dr|Blvd|Way)',
          caseSensitive: false))) {
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
      String searchQuery = resolvedUrl;
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
          } else {}
        } else {}
      } catch (e) {}

      try {
        List<Map<String, dynamic>> searchResults =
            await _mapsService.searchPlaces(searchQuery);

        if (searchResults.isNotEmpty) {
          placeIdToLookup = searchResults.first['placeId'] as String?;
          if (placeIdToLookup != null && placeIdToLookup.isNotEmpty) {
            foundLocation = await _mapsService.getPlaceDetails(placeIdToLookup);
          } else {}
        } else {}
      } catch (e) {}

      if (foundLocation == null) {
        placeIdToLookup = _extractPlaceIdFromMapsUrl(resolvedUrl);

        if (placeIdToLookup != null && placeIdToLookup.isNotEmpty) {
          try {
            foundLocation = await _mapsService.getPlaceDetails(placeIdToLookup);
          } catch (e) {
            foundLocation = null;
          }
        } else {}
      }

      if (foundLocation != null) {
        final String finalName = foundLocation.getPlaceName();
        final String? finalWebsite = foundLocation.website;

        final provider = context.read<ReceiveShareProvider>();
        if (provider.experienceCards.isNotEmpty) {
          _fillFormWithGoogleMapsData(
              foundLocation, finalName, finalWebsite ?? '', mapsUrl);
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
      List<Map<String, dynamic>> topResults, String entityName) async {
    if (!mounted || topResults.isEmpty) return null;

    // Show a dialog with the top location options
    final selectedResult = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
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
                final name = result['description'] as String? ??
                    result['name'] as String? ??
                    '';
                final address = result['vicinity'] as String? ??
                    result['formatted_address'] as String? ??
                    '';
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
      final colorCategories = await _fetchOrderedColorCategories();
      if (mounted) {
        _userColorCategories = colorCategories;
        _userColorCategoriesNotifier.value = colorCategories;
      }
      _userColorCategoriesFuture = Future.value(
          colorCategories); // Ensure future resolves to the fetched list
    } catch (error) {
      if (mounted) {
        _userColorCategories = [];
        _userColorCategoriesNotifier.value = [];
      }
      _userColorCategoriesFuture =
          Future.value([]); // Ensure future resolves to an empty list on error
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
      _showSnackBar(
          context, 'Cannot check for duplicates: User not identified.');
      return null;
    }

    List<Experience> userExperiences = [];
    try {
      userExperiences = await _experienceService.getUserExperiences();
    } catch (e) {
      _showSnackBar(
          context, 'Could not load your experiences to check for duplicates.');
      return null; // Cannot proceed without experiences
    }

    if (!mounted) return null;

    Experience? foundDuplicate;
    String? duplicateReason;

    for (final existingExp in userExperiences) {
      // Skip if checking an existing experience against itself
      if (card.existingExperienceId != null &&
          card.existingExperienceId == existingExp.id) {
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
          titleToCheck.trim().toLowerCase() ==
              existingExp.name.trim().toLowerCase()) {
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
          final Color primaryColor =
              Theme.of(dialogContext).colorScheme.primary;
          return AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('Potential Duplicate Found'),
            // MODIFIED: Dialog content to show both title and address
            content: Text(
                'You already saved an experience named "${foundDuplicate!.name}" located at "${foundDuplicate.location.address ?? 'No address provided'}." Do you want to use this existing experience?'),
            actions: <Widget>[
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: primaryColor,
                ),
                child: const Text('Create New'),
                onPressed: () {
                  Navigator.of(dialogContext).pop(false); // Don't use existing
                },
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                ),
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
  final void Function(bool, String)?
      onExpansionChanged; // MODIFIED to include URL

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
  inapp.InAppWebViewController? _controller;

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
  void _handleWebViewCreated(inapp.InAppWebViewController controller) {
    if (!mounted || _isDisposed) return;
    _controller = controller;
  }

  /// Take a screenshot of the Instagram WebView
  Future<Uint8List?> takeScreenshot() async {
    if (_controller == null) {
      print('⚠️ INSTAGRAM WRAPPER: Controller is null');
      return null;
    }
    try {
      return await _controller!.takeScreenshot();
    } catch (e) {
      print('❌ INSTAGRAM WRAPPER: Screenshot failed: $e');
      return null;
    }
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
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    final double height = _isExpanded ? 2800.0 : 890.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
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
                padding: EdgeInsets.zero,
                onPressed: () => _handleUrlLaunch(widget.url),
              ),
              IconButton(
                icon: Icon(
                    _isExpanded ? Icons.fullscreen_exit : Icons.fullscreen),
                iconSize: 24,
                color: Colors.blue,
                tooltip: _isExpanded ? 'Collapse' : 'Expand',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                onPressed: () {
                  _safeSetState(() {
                    _isExpanded = !_isExpanded;
                    widget.onExpansionChanged?.call(
                        _isExpanded, widget.url); // CALL CALLBACK with URL
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

/// Result from the multi-location selection dialog
class _MultiLocationSelectionResult {
  final List<ExtractedLocationData> selectedLocations;
  final Map<ExtractedLocationData, Experience> selectedDuplicates;

  _MultiLocationSelectionResult({
    required this.selectedLocations,
    required this.selectedDuplicates,
  });
}

/// Dialog for selecting multiple locations from AI extraction results
class _MultiLocationSelectionDialog extends StatefulWidget {
  final List<ExtractedLocationData> locations;
  final Map<int, Experience> duplicates; // index -> existing Experience

  const _MultiLocationSelectionDialog({
    required this.locations,
    this.duplicates = const {},
  });

  @override
  State<_MultiLocationSelectionDialog> createState() =>
      _MultiLocationSelectionDialogState();
}

class _MultiLocationSelectionDialogState
    extends State<_MultiLocationSelectionDialog> {
  late Set<int> _selectedIndices;
  
  /// Confidence threshold - locations below this should be verified by user
  static const double _lowConfidenceThreshold = 0.9;

  @override
  void initState() {
    super.initState();
    // Start with all locations selected
    _selectedIndices =
        Set<int>.from(List.generate(widget.locations.length, (i) => i));
  }

  bool get _allSelected => _selectedIndices.length == widget.locations.length;
  bool get _noneSelected => _selectedIndices.isEmpty;

  int get _duplicateCount => widget.duplicates.length;
  int get _selectedDuplicateCount =>
      _selectedIndices.where((i) => widget.duplicates.containsKey(i)).length;
  int get _selectedNewCount =>
      _selectedIndices.length - _selectedDuplicateCount;
  
  /// Count of locations with low confidence that need verification
  int get _lowConfidenceCount => widget.locations.where(
      (loc) => loc.confidence < _lowConfidenceThreshold || loc.needsConfirmation
    ).length;
  
  /// Check if a specific location has low confidence
  bool _isLowConfidence(ExtractedLocationData location) {
    return location.confidence < _lowConfidenceThreshold || location.needsConfirmation;
  }

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selectedIndices.clear();
      } else {
        _selectedIndices =
            Set<int>.from(List.generate(widget.locations.length, (i) => i));
      }
    });
  }

  void _toggleLocation(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16),
      backgroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.locations.length} Locations Found',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (_lowConfidenceCount > 0) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.red[700]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '$_lowConfidenceCount location${_lowConfidenceCount == 1 ? '' : 's'} may need verification',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                        color: Colors.red[700],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select which locations to add:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              // Show duplicate notice if any duplicates found
              if (_duplicateCount > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.bookmark, size: 16, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$_duplicateCount already saved',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange[800],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              // Select All / Deselect All row
              InkWell(
                onTap: _toggleAll,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _allSelected,
                        tristate: true,
                        onChanged: (_) => _toggleAll(),
                        activeColor: Colors.blue,
                      ),
                      Text(
                        _allSelected ? 'Deselect All' : 'Select All',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.blue[700],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_selectedIndices.length}/${widget.locations.length}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              const SizedBox(height: 8),
              // Scrollable list of locations
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.4,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.locations.length,
                    itemBuilder: (context, index) {
                      final location = widget.locations[index];
                      final isSelected = _selectedIndices.contains(index);
                      final isDuplicate = widget.duplicates.containsKey(index);
                      final existingExp = widget.duplicates[index];
                      final isLowConfidence = _isLowConfidence(location);

                      return InkWell(
                        onTap: () => _toggleLocation(index),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (isDuplicate
                                    ? Colors.orange.withOpacity(0.08)
                                    : isLowConfidence 
                                        ? Colors.red.withOpacity(0.05)
                                        : Colors.blue.withOpacity(0.05))
                                : null,
                            borderRadius: BorderRadius.circular(8),
                            border: isLowConfidence && isSelected
                                ? Border.all(color: Colors.red.withOpacity(0.3), width: 1)
                                : null,
                          ),
                          child: Row(
                            children: [
                              Checkbox(
                                value: isSelected,
                                onChanged: (_) => _toggleLocation(index),
                                activeColor: isDuplicate 
                                    ? Colors.orange 
                                    : isLowConfidence 
                                        ? Colors.red 
                                        : Colors.blue,
                              ),
                              Icon(
                                isDuplicate 
                                    ? Icons.bookmark 
                                    : isLowConfidence 
                                        ? Icons.help_outline
                                        : Icons.place,
                                size: 18,
                                color: isDuplicate
                                    ? Colors.orange[600]
                                    : isLowConfidence
                                        ? Colors.red[600]
                                        : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            location.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w500,
                                              color: isSelected
                                                  ? Colors.black
                                                  : Colors.grey[700],
                                            ),
                                          ),
                                        ),
                                        if (isDuplicate)
                                          Container(
                                            margin:
                                                const EdgeInsets.only(left: 4),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.orange[100],
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'Saved',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.orange[800],
                                              ),
                                            ),
                                          ),
                                        if (isLowConfidence && !isDuplicate)
                                          Container(
                                            margin:
                                                const EdgeInsets.only(left: 4),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.red[50],
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: Colors.red[200]!,
                                                width: 1,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.warning_amber_rounded,
                                                  size: 10,
                                                  color: Colors.red[700],
                                                ),
                                                const SizedBox(width: 2),
                                                Text(
                                                  'Verify',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.red[700],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (location.address != null &&
                                        location.address!.isNotEmpty)
                                      Text(
                                        location.address!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    if (isDuplicate && existingExp != null)
                                      Text(
                                        'Address already saved as: "${existingExp.name}"',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                          color: Colors.orange[700],
                                        ),
                                      ),
                                    if (isLowConfidence && !isDuplicate)
                                      Text(
                                        'Please verify this location is correct',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                          color: Colors.red[600],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _noneSelected
                ? null
                : () {
                    // Sort indices and map to locations
                    final sortedIndices = _selectedIndices.toList()..sort();
                    final selectedLocations =
                        sortedIndices.map((i) => widget.locations[i]).toList();

                    // Build map of selected locations that are duplicates
                    final selectedDuplicates =
                        <ExtractedLocationData, Experience>{};
                    for (final index in sortedIndices) {
                      if (widget.duplicates.containsKey(index)) {
                        selectedDuplicates[widget.locations[index]] =
                            widget.duplicates[index]!;
                      }
                    }

                    Navigator.pop(
                        context,
                        _MultiLocationSelectionResult(
                          selectedLocations: selectedLocations,
                          selectedDuplicates: selectedDuplicates,
                        ));
                  },
            child: Text(
              _buildButtonText(),
            ),
          ),
        ],
      );
  }

  String _buildButtonText() {
    if (_selectedIndices.length == 1) {
      final isDuplicate = widget.duplicates.containsKey(_selectedIndices.first);
      return isDuplicate ? 'Use Existing' : 'Create 1 Card';
    }

    if (_selectedDuplicateCount > 0 && _selectedNewCount > 0) {
      return 'Add ${_selectedIndices.length} (${_selectedNewCount} new, ${_selectedDuplicateCount} existing)';
    } else if (_selectedDuplicateCount > 0) {
      return 'Use ${_selectedDuplicateCount} Existing';
    } else {
      return 'Create ${_selectedNewCount} Cards';
    }
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
