import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import '../models/shared_media_compat.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
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
import '../services/ai_settings_service.dart';
import '../models/extracted_location_data.dart';
import 'location_picker_screen.dart';
import '../services/sharing_service.dart';
import 'dart:async';
import 'receive_share/widgets/maps_preview_widget.dart';
import 'receive_share/widgets/google_knowledge_graph_preview_widget.dart';
import 'receive_share/widgets/web_url_preview_widget.dart';
import 'receive_share/widgets/yelp_preview_widget.dart';
import 'receive_share/widgets/image_preview_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'receive_share/widgets/experience_card_form.dart';
import '../widgets/select_saved_experience_modal_content.dart'; // Attempting relative import again
import '../widgets/privacy_toggle_button.dart';
import 'receive_share/widgets/instagram_preview_widget.dart'
    as instagram_widget;
import 'receive_share/widgets/tiktok_preview_widget.dart';
import 'receive_share/widgets/facebook_preview_widget.dart';
import '../services/facebook_oembed_service.dart';
import 'receive_share/widgets/youtube_preview_widget.dart';
import 'receive_share/widgets/ticketmaster_preview_widget.dart';
import 'main_screen.dart';
import '../models/public_experience.dart';
import '../services/auth_service.dart';
import '../services/gemini_service.dart';
import '../services/foreground_scan_service.dart';
import '../services/category_auto_assign_service.dart';
import 'package:collection/collection.dart';
import 'package:plendy/config/app_constants.dart';
import 'package:plendy/config/colors.dart';
import '../models/experience_card_data.dart';
import '../models/extracted_event_info.dart';
import '../models/event.dart';
import '../widgets/event_editor_modal.dart';
import '../services/ticketmaster_service.dart';
import '../services/event_service.dart';
import 'package:intl/intl.dart';
// Import ApiSecrets conditionally
import '../config/api_secrets.dart'
    if (dart.library.io) '../config/api_secrets.dart'
    if (dart.library.html) '../config/api_secrets.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:plendy/utils/haptic_feedback.dart';
import '../models/help_flow_state.dart';
import '../models/receive_share_help_target.dart';
import '../config/receive_share_help_content.dart';
import '../models/help_target.dart';
import '../widgets/help_bubble.dart';
import '../widgets/help_spotlight_painter.dart';

Rect? _resolveTargetRect(BuildContext ctx) {
  final renderObject = ctx.findRenderObject();
  final box = renderObject is RenderBox && renderObject.hasSize
      ? renderObject
      : (ctx is Element ? _findNearestDescendantRenderBox(ctx) : null) ??
          ctx.findAncestorRenderObjectOfType<RenderBox>();
  if (box == null || !box.hasSize) return null;
  final topLeft = box.localToGlobal(Offset.zero);
  return topLeft & box.size;
}

RenderBox? _findNearestDescendantRenderBox(Element element) {
  final children = <Element>[];
  element.visitChildren(children.add);

  for (final child in children) {
    final ro = child.renderObject;
    if (ro is RenderBox && ro.hasSize) return ro;
  }

  for (final child in children) {
    final nested = _findNearestDescendantRenderBox(child);
    if (nested != null) return nested;
  }

  return null;
}

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
  final void Function(ExperienceCardData card)?
      showSelectEventDialog; // ADDED: Show event selection dialog for a specific card
  final String? Function()? getDetectedEventName;
  final bool isHelpMode;
  final bool Function(ReceiveShareHelpTargetId id, BuildContext ctx)? onHelpTap;

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
    this.showSelectEventDialog, // ADDED
    this.getDetectedEventName,
    this.isHelpMode = false,
    this.onHelpTap,
  });

  @override
  Widget build(BuildContext context) {
    // REMOVED: No longer watching provider directly here
    // final shareProvider = context.watch<ReceiveShareProvider>();
    // final experienceCards = shareProvider.experienceCards;

    return Container(
      color: AppColors.backgroundColorDark,
      child: Padding(
        key: sectionKey, // ADDED for scrolling
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 16,
              color: AppColors.backgroundColorDark,
            ),
            if (experienceCards.isNotEmpty)
              Container(
                color: AppColors.backgroundColorDark,
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                    experienceCards.length > 1
                        ? 'Save to Experiences'
                        : 'Save to Experience',
                    style: Theme.of(context).textTheme.titleLarge),
              )
            else
              Container(
                color: AppColors.backgroundColorDark,
                padding: const EdgeInsets.only(bottom: 8.0),
                child: const Text("No Experience Card"),
              ),
            Container(
              height: 8,
              color: AppColors.backgroundColorDark,
            ),
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
                      onYelpButtonTapped: onYelpButtonTapped,
                      onEventSelect: showSelectEventDialog != null
                          ? () => showSelectEventDialog!(card)
                          : null,
                      selectedEventTitle: card.selectedEvent?.title,
                      getDetectedEventName: getDetectedEventName,
                      isHelpMode: isHelpMode,
                      onHelpTap: onHelpTap,
                    );
                  }),
            if (!isSpecialUrl(currentSharedFiles.isNotEmpty
                ? extractFirstUrl(currentSharedFiles.first.path) ?? ''
                : ''))
              Column(
                children: [
                  Container(
                    color: AppColors.backgroundColorDark,
                    padding: const EdgeInsets.only(top: 12.0),
                    child: Center(
                      child: Builder(builder: (addBtnCtx) {
                        return OutlinedButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('Add Another Experience'),
                          onPressed: () {
                            if (onHelpTap != null &&
                                onHelpTap!(
                                    ReceiveShareHelpTargetId
                                        .addAnotherExperienceButton,
                                    addBtnCtx)) {
                              return;
                            }
                            addExperienceCard();
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 24),
                            side: BorderSide(
                                color: Theme.of(context).colorScheme.primary),
                          ),
                        );
                      }),
                    ),
                  ),
                  Container(
                    height: 16,
                    color: AppColors.backgroundColorDark,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class ReceiveShareScreen extends StatefulWidget {
  final List<SharedMediaFile> sharedFiles;
  final VoidCallback onCancel;
  final bool requireUrlFirst;
  final VoidCallback? onExperienceSaved;

  const ReceiveShareScreen({
    super.key,
    required this.sharedFiles,
    required this.onCancel,
    this.requireUrlFirst = false,
    this.onExperienceSaved,
  });

  @override
  _ReceiveShareScreenState createState() => _ReceiveShareScreenState();
}

class _ReceiveShareScreenState extends State<ReceiveShareScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // Services
  final ExperienceService _experienceService = ExperienceService();
  final CategoryOrderingService _categoryOrderingService =
      CategoryOrderingService();
  final CategoryAutoAssignService _categoryAutoAssignService =
      CategoryAutoAssignService();
  final GoogleMapsService _mapsService = GoogleMapsService();
  final SharingService _sharingService = SharingService();
  final LinkLocationExtractionService _locationExtractor =
      LinkLocationExtractionService();
  final ForegroundScanService _foregroundScanService = ForegroundScanService();
  final AiSettingsService _aiSettingsService = AiSettingsService.instance;
  final TicketmasterService _ticketmasterService = TicketmasterService();

  // AI Location Extraction state
  bool _isExtractingLocation = false;
  bool _isProcessingScreenshot = false; // For screenshot-based extraction
  Position? _currentUserPosition; // For location-biased extraction

  // Track if AI scan is running
  bool _isAiScanInProgress = false;
  // Track if categorization is in progress
  bool _isCategorizing = false;
  // Track scan progress (0.0 to 1.0)
  double _scanProgress = 0.0;
  // Token used to invalidate stale async scan work after user cancellation
  int _analysisSessionId = 0;
  // Store pending scan results to apply when app returns to foreground
  List<ExtractedLocationData>? _pendingScanResults;
  String? _pendingScanSingleMessage; // Toast message for single result
  // Store pending deep scan request to run after quick scan cleanup
  ReceiveShareProvider? _pendingDeepScanProvider;
  ExtractedEventInfo? _pendingDeepScanEventInfo;
  // Store confirmed locations from quick scan to preserve during deep scan
  List<ExtractedLocationData>? _pendingDeepScanConfirmedLocations;
  final ImagePicker _imagePicker = ImagePicker();
  // URL bar controller and focus node
  late final TextEditingController _sharedUrlController;
  late final FocusNode _sharedUrlFocusNode;
  String? _lastProcessedUrl;
  // Track URLs that have been auto-scanned to prevent duplicate scans
  final Set<String> _autoScannedUrls = {};
  // Track URLs where location extraction (Maps grounding or page scan) has already completed
  final Set<String> _locationExtractionCompletedUrls = {};

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
    // FIXED: Skip vibration on web to avoid Platform crash
    if (kIsWeb) return;
    try {
      // For Android: Use platform channel to vibrate for 500ms
      if (Platform.isAndroid) {
        await SystemChannels.platform
            .invokeMethod('HapticFeedback.vibrate', 500);
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

  // Quick Add dialog state
  Location? _quickAddSelectedLocation;
  Experience?
      _quickAddSelectedExperience; // Non-null if saved experience selected
  bool _isQuickAddSavedExperience = false;

  // Event detection state - stored for use after successful save
  ExtractedEventInfo? _detectedEventInfo;

  // Event service for managing events
  final EventService _eventService = EventService();

  // ─── Help mode state ──────────────────────────────────────
  late final HelpFlowState<ReceiveShareHelpTargetId> _helpFlow;
  late final AnimationController _spotlightController;
  final GlobalKey _helpButtonKey = GlobalKey();
  final GlobalKey<HelpBubbleState> _helpBubbleKey = GlobalKey();
  bool _isHelpTyping = false;

  void _toggleHelpMode() {
    triggerHeavyHaptic();
    setState(() {
      final nowActive = _helpFlow.toggle();
      if (nowActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _helpButtonKey.currentContext != null) {
            _showHelpForTarget(ReceiveShareHelpTargetId.helpButton,
                _helpButtonKey.currentContext!);
          }
        });
      }
    });
  }

  void _showHelpForTarget(ReceiveShareHelpTargetId id, BuildContext targetCtx) {
    final rect = _resolveTargetRect(targetCtx);
    if (rect == null) return;
    setState(() {
      _helpFlow.showTarget(id, rect);
      _isHelpTyping = true;
    });
  }

  void _advanceHelpStep() {
    setState(() {
      _helpFlow.advance();
      if (_helpFlow.hasActiveTarget) {
        _isHelpTyping = true;
      }
    });
  }

  void _dismissHelpBubble() {
    setState(() {
      _helpFlow.dismiss();
      _isHelpTyping = false;
    });
  }

  void _onHelpBarrierTap() {
    if (_isHelpTyping) {
      _helpBubbleKey.currentState?.skipTypewriter();
    } else {
      _advanceHelpStep();
    }
  }

  bool _tryHelpTap(ReceiveShareHelpTargetId id, BuildContext targetCtx) {
    if (!_helpFlow.isActive) return false;
    triggerHeavyHaptic();
    _showHelpForTarget(id, targetCtx);
    return true;
  }

  Widget _buildHelpOverlay() {
    final flow = _helpFlow;
    final spec = flow.activeSpec;
    final step = flow.activeHelpStep;

    return Positioned.fill(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: flow.hasActiveTarget ? 1.0 : 0.0,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _onHelpBarrierTap,
          child: Stack(
            children: [
              if (flow.activeTargetRect != null)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _spotlightController,
                    builder: (context, _) => CustomPaint(
                      painter: HelpSpotlightPainter(
                        targetRect: flow.activeTargetRect!,
                        glowProgress: _spotlightController.value,
                      ),
                    ),
                  ),
                ),
              if (spec != null && step != null && flow.activeTargetRect != null)
                HelpBubble(
                  key: _helpBubbleKey,
                  text: step.text,
                  instruction: step.instruction,
                  isLastStep: flow.isLastStep,
                  targetRect: flow.activeTargetRect!,
                  onAdvance: _advanceHelpStep,
                  onDismiss: _dismissHelpBubble,
                  onTypingStarted: () {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _isHelpTyping = true);
                    });
                  },
                  onTypingFinished: () {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _isHelpTyping = false);
                    });
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHelpBanner() {
    if (!_helpFlow.isActive) return const SizedBox.shrink();
    return GestureDetector(
      onTap: _toggleHelpMode,
      child: AnimatedBuilder(
        animation: _spotlightController,
        builder: (context, _) {
          final opacity = 0.6 + 0.4 * _spotlightController.value;
          return Opacity(
            opacity: opacity,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              color: AppColors.teal.withValues(alpha: 0.08),
              child: Text(
                'Help mode is ON  •  Tap here to exit',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.teal,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _pauseHelpForDialog() {
    if (_helpFlow.isActive) {
      setState(() => _helpFlow.pause());
    }
  }

  void _resumeHelpAfterDialog() {
    setState(() => _helpFlow.resume());
  }
  // ─── End help mode state ──────────────────────────────────

  Widget _buildSharedUrlBar({required bool showInstructions}) {
    // Rebuilds show suffix icons immediately based on controller text
    return StatefulBuilder(
      builder: (context, setInnerState) {
        final instructionStyle = Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Colors.grey[700]);
        return Container(
          color: AppColors.backgroundColor,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Builder(builder: (urlFieldCtx) {
                  return TextField(
                    controller: _sharedUrlController,
                    focusNode: _sharedUrlFocusNode,
                    autofocus: widget.requireUrlFirst && !_didDeferredInit,
                    keyboardType: TextInputType.url,
                    readOnly: _helpFlow.isActive,
                    decoration: InputDecoration(
                      labelText: 'Shared URL',
                      hintText: 'https://... or paste content with a URL',
                      border: const OutlineInputBorder(),
                      enabledBorder: const OutlineInputBorder(
                        borderSide: BorderSide(
                          color: AppColors.backgroundColorDark,
                        ),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(
                          color: AppColors.backgroundColorDark,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.link),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 8.0, horizontal: 12.0),
                      suffixIconConstraints: const BoxConstraints.tightFor(
                        width: 120,
                        height: 40,
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (_sharedUrlController.text.isNotEmpty)
                            Builder(builder: (clearCtx) {
                              return InkWell(
                                onTap: withHeavyTap(() {
                                  if (_tryHelpTap(
                                      ReceiveShareHelpTargetId.urlClearButton,
                                      clearCtx)) {
                                    return;
                                  }
                                  _sharedUrlController.clear();
                                  setInnerState(() {});
                                }),
                                borderRadius: BorderRadius.circular(16),
                                child: const Padding(
                                  padding: EdgeInsets.all(4.0),
                                  child: Icon(Icons.clear, size: 22),
                                ),
                              );
                            }),
                          if (_sharedUrlController.text.isNotEmpty)
                            const SizedBox(width: 4),
                          Builder(builder: (pasteCtx) {
                            return InkWell(
                              onTap: withHeavyTap(() async {
                                if (_tryHelpTap(
                                    ReceiveShareHelpTargetId.urlPasteButton,
                                    pasteCtx)) {
                                  return;
                                }
                                await _pasteSharedUrlFromClipboard();
                                setInnerState(() {});
                              }),
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: const Icon(Icons.content_paste,
                                    size: 22, color: Color(0xFF1F2A44)),
                              ),
                            );
                          }),
                          const SizedBox(width: 4),
                          Builder(builder: (submitCtx) {
                            return InkWell(
                              onTap: withHeavyTap(() {
                                if (_tryHelpTap(
                                    ReceiveShareHelpTargetId.urlSubmitButton,
                                    submitCtx)) {
                                  return;
                                }
                                _handleSharedUrlSubmit();
                              }),
                              borderRadius: BorderRadius.circular(16),
                              child: const Padding(
                                padding: EdgeInsets.fromLTRB(4, 4, 8, 4),
                                child: Icon(Icons.arrow_circle_right,
                                    size: 22, color: Color(0xFF1F2A44)),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    onTap: () {
                      if (_tryHelpTap(ReceiveShareHelpTargetId.urlInputField,
                          urlFieldCtx)) {
                        return;
                      }
                    },
                    onSubmitted: (_) {
                      if (_tryHelpTap(ReceiveShareHelpTargetId.urlSubmitButton,
                          urlFieldCtx)) {
                        return;
                      }
                      _handleSharedUrlSubmit();
                    },
                    onChanged: (_) {
                      setInnerState(() {});
                    },
                  );
                }),
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
                    _isGenericWebUrl()
                        ? _buildScanPageContentButtonInRow()
                        : _buildScanCurrentPreviewButton(),
                  ],
                ),
                // Scan All Locations button (only show below for non-generic URLs)
                if (!_isGenericWebUrl()) _buildScanPageContentButton(),
                // AI Location Extraction loading indicator
                if (_isExtractingLocation || _isAiScanInProgress) ...[
                  const SizedBox(height: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildAnalyzingChip(),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: _scanProgress),
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          builder: (context, value, _) {
                            return LinearProgressIndicator(
                              value: value,
                              minHeight: 4,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.2),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.primary,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
                // Screenshot processing loading indicator (skip if first chip already visible)
                if (_isProcessingScreenshot &&
                    !_isExtractingLocation &&
                    !_isAiScanInProgress) ...[
                  const SizedBox(height: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildAnalyzingChip(),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: _scanProgress),
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          builder: (context, value, _) {
                            return LinearProgressIndicator(
                              value: value,
                              minHeight: 4,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.2),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.primary,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnalyzingChip() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _cancelActiveAnalysis,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.wineLight.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.wineLight.withOpacity(0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.wineLight),
                ),
              ),
              const SizedBox(width: 10),
              Image.asset(
                'assets/icon/icon-cropped.png',
                width: 16,
                height: 16,
              ),
              const SizedBox(width: 8),
              Text(
                _isCategorizing ? 'Categorizing...' : 'Plendy AI analyzing...',
                style: TextStyle(
                  color: AppColors.wineLight,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.close,
                size: 14,
                color: AppColors.wineLight,
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _startAnalysisSession() {
    _analysisSessionId += 1;
    return _analysisSessionId;
  }

  bool _isAnalysisSessionActive(int sessionId) {
    return mounted && sessionId == _analysisSessionId;
  }

  Future<void> _cancelActiveAnalysis() async {
    final hadActiveAnalysis = _isProcessingScreenshot ||
        _isExtractingLocation ||
        _isAiScanInProgress ||
        _isCategorizing;

    _analysisSessionId += 1;
    _locationUpdateDebounce?.cancel();
    _pendingScanResults = null;
    _pendingScanSingleMessage = null;
    _pendingDeepScanProvider = null;
    _pendingDeepScanEventInfo = null;
    _pendingDeepScanConfirmedLocations = null;

    if (mounted) {
      final provider = context.read<ReceiveShareProvider>();
      for (final card in provider.experienceCards) {
        card.isSelectingLocation = false;
      }
      setState(() {
        _isProcessingScreenshot = false;
        _isExtractingLocation = false;
        _isAiScanInProgress = false;
        _isCategorizing = false;
        _scanProgress = 0.0;
      });
    }

    WakelockPlus.disable();
    await _foregroundScanService.stopScanService();

    if (hadActiveAnalysis) {
      Fluttertoast.showToast(
        msg: 'Analysis canceled',
        toastLength: Toast.LENGTH_SHORT,
      );
    }
  }

  /// Helper method to update scan progress
  void _updateScanProgress(double progress, {int? sessionId}) {
    if (sessionId != null && sessionId != _analysisSessionId) return;
    if (mounted) {
      setState(() {
        _scanProgress = progress.clamp(0.0, 1.0);
      });
    }
  }

  Future<bool> _shouldAutoExtractLocations() async {
    return _aiSettingsService.shouldAutoExtractLocations();
  }

  Future<bool> _shouldUseDeepScan() async {
    return _aiSettingsService.shouldUseDeepScan();
  }

  /// Build the screenshot upload button widget
  Widget _buildScreenshotUploadButton() {
    final isLoading = _isProcessingScreenshot || _isExtractingLocation;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Builder(builder: (screenshotBtnCtx) {
          return OutlinedButton(
            onPressed: isLoading
                ? null
                : () {
                    if (_tryHelpTap(
                        ReceiveShareHelpTargetId.screenshotUploadButton,
                        screenshotBtnCtx)) {
                      return;
                    }
                    _showScreenshotUploadOptions();
                  },
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              side: BorderSide(
                color: isLoading ? Colors.grey[300]! : AppColors.sage,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Icon(
              Icons.add_photo_alternate_outlined,
              size: 20,
              color: isLoading ? Colors.grey : AppColors.sage,
            ),
          );
        }),
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
        !_isGoogleKnowledgeGraphUrl(url) &&
        !_isTicketmasterUrl(url);
  }

  /// Build the scan current preview button widget
  Widget _buildScanCurrentPreviewButton() {
    // Hide for generic web URLs (they use "Scan Locations" instead)
    if (_isGenericWebUrl()) return const SizedBox.shrink();

    // Hide for Ticketmaster URLs (event details are loaded automatically via API)
    final url = _currentSharedFiles.isNotEmpty
        ? _extractFirstUrl(_currentSharedFiles.first.path)
        : null;
    if (url != null && _isTicketmasterUrl(url)) return const SizedBox.shrink();

    final isLoading = _isProcessingScreenshot || _isExtractingLocation;
    final hasPreview = _hasActivePreview();

    // Determine button text based on URL type
    // Use "Scan Screen" for YouTube and Facebook Reels (where auto-extraction doesn't work well)
    final isYouTubeUrl = url != null && _isYouTubeUrl(url);
    final isFacebookReel = url != null &&
        (url.contains('facebook.com/reel/') ||
            url.contains('facebook.com/reels/'));
    final buttonText =
        (isYouTubeUrl || isFacebookReel) ? 'Scan Screen' : 'Scan Preview';

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Builder(builder: (scanBtnCtx) {
          return OutlinedButton.icon(
            onPressed: (isLoading || !hasPreview)
                ? null
                : () {
                    if (_tryHelpTap(
                        ReceiveShareHelpTargetId.scanButton, scanBtnCtx)) {
                      return;
                    }
                    _scanCurrentPreview();
                  },
            icon: Icon(
              Icons.screenshot_monitor,
              size: 20,
              color: (isLoading || !hasPreview)
                  ? Colors.grey
                  : const Color(0xFF2F6F6D),
            ),
            label: Text(
              buttonText,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color:
                    (isLoading || !hasPreview) ? Colors.grey : AppColors.teal,
              ),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              side: BorderSide(
                color: (isLoading || !hasPreview)
                    ? Colors.grey[300]!
                    : const Color(0xFF2F6F6D),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }),
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
        child: Builder(builder: (scanBtnCtx) {
          return OutlinedButton.icon(
            onPressed: (isLoading || !hasPreview)
                ? null
                : () {
                    if (_tryHelpTap(
                        ReceiveShareHelpTargetId.scanButton, scanBtnCtx)) {
                      return;
                    }
                    _scanPageContent();
                  },
            icon: Icon(
              Icons.article_outlined,
              size: 20,
              color:
                  (isLoading || !hasPreview) ? Colors.grey : Colors.purple[700],
            ),
            label: const Text(
              'Scan Locations',
              style: TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
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
          );
        }),
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
    // Only show for generic web URLs (not social media or Ticketmaster)
    final url = _currentSharedFiles.isNotEmpty
        ? _extractFirstUrl(_currentSharedFiles.first.path)
        : null;
    final isWebUrl = url != null &&
        url.startsWith('http') &&
        !_isInstagramUrl(url) &&
        !_isTikTokUrl(url) &&
        !_isYouTubeUrl(url) &&
        !_isFacebookUrl(url) &&
        !_isTicketmasterUrl(url);

    // Don't show button if not a web URL
    if (!isWebUrl) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.only(left: 4, top: 8),
      child: SizedBox(
        width: double.infinity,
        child: Builder(builder: (scanBtnCtx) {
          return OutlinedButton.icon(
            onPressed: (isLoading || !hasPreview)
                ? null
                : () {
                    if (_tryHelpTap(
                        ReceiveShareHelpTargetId.scanButton, scanBtnCtx)) {
                      return;
                    }
                    _scanPageContent();
                  },
            icon: Icon(
              Icons.article_outlined,
              size: 20,
              color:
                  (isLoading || !hasPreview) ? Colors.grey : Colors.purple[700],
            ),
            label: Text(
              'Scan Locations',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: (isLoading || !hasPreview)
                    ? Colors.grey
                    : Colors.purple[700],
              ),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
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
          );
        }),
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
                  onTap: withHeavyTap(() {
                    Navigator.pop(context);
                    _pickScreenshotFromGallery();
                  }),
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
                  onTap: withHeavyTap(() {
                    Navigator.pop(context);
                    _takePhotoForLocation();
                  }),
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

    final scanSessionId = _startAnalysisSession();

    // For other platforms, use standard screenshot-only scan
    setState(() {
      _isProcessingScreenshot = true;
      _isAiScanInProgress = true;
      _scanProgress = 0.0;
    });

    // Enable wakelock to prevent screen from sleeping during AI scan
    WakelockPlus.enable();

    // Start foreground service to keep app alive during scan
    await _foregroundScanService.startScanService();
    if (!_isAnalysisSessionActive(scanSessionId)) return;

    try {
      _updateScanProgress(0.1, sessionId: scanSessionId);
      print('📷 SCAN PREVIEW: Capturing WebView content...');

      // Try to capture the WebView screenshot from any active preview
      Uint8List? screenshotBytes = await _tryCaptureaActiveWebView();
      if (!_isAnalysisSessionActive(scanSessionId)) return;
      _updateScanProgress(0.25, sessionId: scanSessionId);

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
      _updateScanProgress(0.35, sessionId: scanSessionId);

      // Get user location for better results
      LatLng? userLocation;
      if (_currentUserPosition != null) {
        userLocation = LatLng(
          _currentUserPosition!.latitude,
          _currentUserPosition!.longitude,
        );
      }

      // Process the captured image
      _updateScanProgress(0.45, sessionId: scanSessionId);
      final result = await _locationExtractor.extractLocationsFromImageBytes(
        screenshotBytes,
        mimeType: 'image/png',
        userLocation: userLocation,
        onProgress: (current, total, phase) {
          // Map progress from 0.45 to 0.85 range
          if (current == 0) {
            _updateScanProgress(0.50, sessionId: scanSessionId); // AI analysis
          } else {
            final progress = 0.50 + (0.35 * current / total);
            _updateScanProgress(progress, sessionId: scanSessionId);
          }
        },
      );
      if (!_isAnalysisSessionActive(scanSessionId)) return;
      final locations = result.locations;
      _updateScanProgress(0.85, sessionId: scanSessionId);

      // Check if mounted - if not, store results to apply when app resumes
      if (!mounted) {
        if (locations.isNotEmpty) {
          print(
              '📷 SCAN PREVIEW: App backgrounded, storing ${locations.length} result(s) for later');
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
      _updateScanProgress(0.88, sessionId: scanSessionId);

      // Try to detect event information from available text content
      // Priority 1: WebView extracted caption (e.g., from Instagram/TikTok)
      // Priority 2: Location metadata's extracted text
      ExtractedEventInfo? detectedEvent;

      if (_extractedCaption != null && _extractedCaption!.isNotEmpty) {
        print('📅 SCAN PREVIEW: Checking WebView caption for event info...');
        detectedEvent = await _detectEventFromTextAsync(_extractedCaption!);
        if (!_isAnalysisSessionActive(scanSessionId)) return;
      }

      // Check location metadata for extracted text if no event found yet
      if (detectedEvent == null && locations.isNotEmpty) {
        for (final location in locations) {
          if (location.metadata != null) {
            final extractedText =
                location.metadata!['extractedText'] as String?;
            if (extractedText != null && extractedText.isNotEmpty) {
              print(
                  '📅 SCAN PREVIEW: Checking location metadata for event info...');
              detectedEvent = await _detectEventFromTextAsync(extractedText);
              if (!_isAnalysisSessionActive(scanSessionId)) return;
              if (detectedEvent != null) break;
            }
          }
        }
      }

      _updateScanProgress(0.95, sessionId: scanSessionId);

      // Heavy vibration to notify user scan completed
      _heavyVibration();

      final provider = context.read<ReceiveShareProvider>();

      // Always show the location selection dialog, even for single results
      // This lets users verify the location is correct before saving
      // Pass detected event info for event designation
      // Get scanned text from:
      // 1. OCR extracted text from the image scan result (primary source)
      // 2. WebView extracted caption (fallback for platforms like Instagram/TikTok)
      String? scannedTextForDialog = result.extractedText ?? _extractedCaption;
      final deepScanRequested = await _handleMultipleExtractedLocations(
        locations,
        provider,
        detectedEventInfo: detectedEvent,
        scannedText: scannedTextForDialog,
      );
      if (!_isAnalysisSessionActive(scanSessionId)) return;
      _updateScanProgress(1.0, sessionId: scanSessionId);

      // If user requested deep scan, run it after cleanup
      if (deepScanRequested && mounted) {
        _pendingDeepScanProvider = provider;
        _pendingDeepScanEventInfo = detectedEvent;
      }
    } catch (e) {
      print('❌ SCAN PREVIEW ERROR: $e');
      if (_isAnalysisSessionActive(scanSessionId)) {
        Fluttertoast.showToast(
          msg: '❌ Scan failed. Please try scanning again.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.red,
        );
      }
    } finally {
      // Disable wakelock and stop foreground service
      WakelockPlus.disable();
      await _foregroundScanService.stopScanService();
      if (_isAnalysisSessionActive(scanSessionId)) {
        setState(() {
          _isProcessingScreenshot = false;
          _isAiScanInProgress = false;
          _scanProgress = 0.0;
        });
      }
    }

    // Run deep scan if requested (after cleanup is complete)
    if (_isAnalysisSessionActive(scanSessionId) &&
        _pendingDeepScanProvider != null &&
        mounted) {
      final provider = _pendingDeepScanProvider!;
      final eventInfo = _pendingDeepScanEventInfo;
      _pendingDeepScanProvider = null;
      _pendingDeepScanEventInfo = null;
      await _runDeepScan(provider, detectedEventInfo: eventInfo);
    }
  }

  /// Scan the entire page content to extract ALL locations
  /// Useful for articles like "50 best restaurants" or travel guides
  Future<void> _scanPageContent() async {
    if (_isProcessingScreenshot || _isExtractingLocation) return;

    // Resolve URL before try block so it's accessible in finally for tracking
    final url = _currentSharedFiles.isNotEmpty
        ? _extractFirstUrl(_currentSharedFiles.first.path)
        : null;
    final scanSessionId = _startAnalysisSession();

    setState(() {
      _isProcessingScreenshot = true;
      _isAiScanInProgress = true;
      _scanProgress = 0.0;
    });

    // Enable wakelock to prevent screen from sleeping during AI scan
    WakelockPlus.enable();

    // Start foreground service to keep app alive during scan
    await _foregroundScanService.startScanService();
    if (!_isAnalysisSessionActive(scanSessionId)) return;

    try {
      _updateScanProgress(0.1, sessionId: scanSessionId);
      print('📄 SCAN PAGE: Extracting page content...');

      // Try to extract page content from the active WebView
      String? pageContent = await _tryExtractPageContent();
      if (!_isAnalysisSessionActive(scanSessionId)) return;
      _updateScanProgress(0.25, sessionId: scanSessionId);

      if (pageContent == null || pageContent.isEmpty) {
        Fluttertoast.showToast(
          msg:
              '📄 Could not extract page content. Try the screenshot scan instead.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.orange[700],
        );
        return;
      }

      print(
          '📄 SCAN PAGE: Extracted ${pageContent.length} characters, sending to Gemini...');
      _updateScanProgress(0.35, sessionId: scanSessionId);

      // Get user location for better results
      LatLng? userLocation;
      if (_currentUserPosition != null) {
        userLocation = LatLng(
          _currentUserPosition!.latitude,
          _currentUserPosition!.longitude,
        );
      }

      // Process with Gemini
      _updateScanProgress(0.45, sessionId: scanSessionId);
      final geminiService = GeminiService();
      final result = await geminiService.extractLocationsFromWebPage(
        pageContent,
        pageUrl: url,
        userLocation: userLocation,
      );
      if (!_isAnalysisSessionActive(scanSessionId)) return;
      _updateScanProgress(0.75, sessionId: scanSessionId);

      // Convert Gemini results to ExtractedLocationData first (doesn't need mounted)
      List<ExtractedLocationData> locations = [];
      if (result != null && result.locations.isNotEmpty) {
        print('✅ SCAN PAGE: Found ${result.locations.length} location(s)');
        for (final loc in result.locations) {
          final hasPlaceId = loc.placeId.isNotEmpty;
          final hasCoords =
              loc.coordinates.latitude != 0 || loc.coordinates.longitude != 0;
          print(
              '   📍 ${loc.name} (placeId: ${hasPlaceId ? "✓" : "✗"}, coords: ${hasCoords ? "✓" : "✗"})');
        }

        locations = result.locations.map((loc) {
          // Infer place type from the types list
          final placeType = ExtractedLocationData.inferPlaceType(loc.types);

          // Check if we have valid coordinates (not 0,0 which is our fallback)
          final hasValidCoords =
              loc.coordinates.latitude != 0 || loc.coordinates.longitude != 0;

          // Determine confidence based on whether we have grounding data
          final hasGrounding = loc.placeId.isNotEmpty;
          final confidence = hasGrounding ? 0.9 : (hasValidCoords ? 0.7 : 0.5);

          return ExtractedLocationData(
            name: loc.name,
            address: loc.formattedAddress,
            placeId: loc.placeId.isNotEmpty ? loc.placeId : null,
            coordinates: hasValidCoords
                ? loc.coordinates
                : null, // Don't use (0,0) coordinates
            type: placeType,
            source: hasGrounding
                ? ExtractionSource.geminiGrounding
                : ExtractionSource.placesSearch,
            confidence: confidence,
            googleMapsUri: loc.uri,
            placeTypes: loc.types,
          );
        }).toList();
      }

      // If any locations are missing coordinates (grounding failed), try to resolve via Places API
      final locationsWithoutCoords =
          locations.where((loc) => loc.coordinates == null).length;
      if (locationsWithoutCoords > 0) {
        print(
            '🔍 SCAN PAGE: $locationsWithoutCoords location(s) missing coordinates, resolving via Places API...');
        _updateScanProgress(0.80, sessionId: scanSessionId);
        locations =
            await _resolveLocationsWithoutCoordinates(locations, userLocation);
        if (!_isAnalysisSessionActive(scanSessionId)) return;
        final resolvedCount =
            locations.where((loc) => loc.coordinates != null).length;
        print(
            '✅ SCAN PAGE: Resolved ${resolvedCount}/${locations.length} location(s) with coordinates');
      }

      // Check if mounted - if not, store results to apply when app resumes
      if (!mounted) {
        if (locations.isNotEmpty) {
          print(
              '📄 SCAN PAGE: App backgrounded, storing ${locations.length} result(s) for later');
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

      _updateScanProgress(0.85, sessionId: scanSessionId);

      // Try to detect event information from the page content
      ExtractedEventInfo? detectedEvent;
      if (pageContent.isNotEmpty) {
        print('📅 SCAN PAGE: Checking page content for event info...');
        detectedEvent = await _detectEventFromTextAsync(pageContent);
        if (!_isAnalysisSessionActive(scanSessionId)) return;
      }

      _updateScanProgress(0.95, sessionId: scanSessionId);

      // Heavy vibration to notify user scan completed
      _heavyVibration();

      final provider = context.read<ReceiveShareProvider>();

      // Always show the location selection dialog, even for single results
      // Pass detected event info for event designation
      final deepScanRequested = await _handleMultipleExtractedLocations(
        locations,
        provider,
        detectedEventInfo: detectedEvent,
        scannedText: pageContent,
      );
      if (!_isAnalysisSessionActive(scanSessionId)) return;
      _updateScanProgress(1.0, sessionId: scanSessionId);

      // If user requested deep scan, run it after cleanup
      if (deepScanRequested && mounted) {
        _pendingDeepScanProvider = provider;
        _pendingDeepScanEventInfo = detectedEvent;
      }
    } catch (e) {
      print('❌ SCAN PAGE ERROR: $e');
      if (_isAnalysisSessionActive(scanSessionId)) {
        Fluttertoast.showToast(
          msg: '❌ Scan failed. Please try scanning again.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.red,
        );
      }
    } finally {
      if (url != null) _locationExtractionCompletedUrls.add(url);
      // Disable wakelock and stop foreground service
      WakelockPlus.disable();
      await _foregroundScanService.stopScanService();
      if (_isAnalysisSessionActive(scanSessionId)) {
        setState(() {
          _isProcessingScreenshot = false;
          _isAiScanInProgress = false;
          _scanProgress = 0.0;
        });
      }
    }

    // Run deep scan if requested (after cleanup is complete)
    if (_isAnalysisSessionActive(scanSessionId) &&
        _pendingDeepScanProvider != null &&
        mounted) {
      final provider = _pendingDeepScanProvider!;
      final eventInfo = _pendingDeepScanEventInfo;
      _pendingDeepScanProvider = null;
      _pendingDeepScanEventInfo = null;
      await _runDeepScan(provider, detectedEventInfo: eventInfo);
    }
  }

  /// Combined scan that runs BOTH screenshot OCR AND text extraction
  /// This gives better results for Instagram by:
  /// 1. Screenshot OCR catches text overlays on videos/images
  /// 2. Text extraction gets captions, handles, and uses Maps grounding for accuracy
  Future<void> _scanPreviewCombined() async {
    if (_isProcessingScreenshot || _isExtractingLocation) return;
    final scanSessionId = _startAnalysisSession();

    setState(() {
      _isProcessingScreenshot = true;
      _isAiScanInProgress = true;
      _scanProgress = 0.0;
    });

    // Enable wakelock to prevent screen from sleeping during AI scan
    WakelockPlus.enable();

    // Start foreground service to keep app alive during scan (prevents interruption when minimized)
    await _foregroundScanService.startScanService();
    if (!_isAnalysisSessionActive(scanSessionId)) return;

    try {
      _updateScanProgress(0.1, sessionId: scanSessionId);
      print(
          '🔄 COMBINED SCAN: Starting both screenshot and text extraction...');

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

      _updateScanProgress(0.2, sessionId: scanSessionId);

      // Run both extraction methods in parallel
      // The screenshot extraction reports per-location progress
      final results = await Future.wait([
        _extractLocationsFromScreenshot(
          userLocation,
          onProgress: (current, total, phase) {
            // Map progress from 0.2 to 0.75 range
            // Phase 0 = AI analysis (0.2-0.35), Phase 1+ = verifying locations (0.35-0.75)
            if (current == 0) {
              _updateScanProgress(0.25,
                  sessionId: scanSessionId); // AI analysis starting
            } else {
              // Location verification: spread 0.35-0.75 across all locations
              final progress = 0.35 + (0.40 * current / total);
              _updateScanProgress(progress, sessionId: scanSessionId);
            }
          },
        ),
        _extractLocationsFromPageText(url, userLocation),
      ]);
      if (!_isAnalysisSessionActive(scanSessionId)) return;
      _updateScanProgress(0.75, sessionId: scanSessionId);

      final screenshotLocations = results[0];
      final textLocations = results[1];

      print(
          '🔄 COMBINED SCAN: Screenshot found ${screenshotLocations.length} location(s)');
      print(
          '🔄 COMBINED SCAN: Text extraction found ${textLocations.length} location(s)');

      // Merge results first (doesn't need mounted)
      // Prefer text extraction (grounded) results over screenshot (OCR)
      // Text extraction results have Maps grounding and are more accurate
      var mergedLocations =
          _mergeExtractedLocations(textLocations, screenshotLocations);
      _updateScanProgress(0.80, sessionId: scanSessionId);

      print(
          '🔄 COMBINED SCAN: Merged to ${mergedLocations.length} unique location(s)');

      // If any locations are missing coordinates (grounding failed), try to resolve via Places API
      final locationsWithoutCoords =
          mergedLocations.where((loc) => loc.coordinates == null).length;
      if (locationsWithoutCoords > 0) {
        print(
            '🔍 COMBINED SCAN: $locationsWithoutCoords location(s) missing coordinates, resolving via Places API...');
        mergedLocations = await _resolveLocationsWithoutCoordinates(
            mergedLocations, userLocation);
        if (!_isAnalysisSessionActive(scanSessionId)) return;
        final resolvedCount =
            mergedLocations.where((loc) => loc.coordinates != null).length;
        print(
            '✅ COMBINED SCAN: Resolved ${resolvedCount}/${mergedLocations.length} location(s) with coordinates');
      }
      _updateScanProgress(0.85, sessionId: scanSessionId);

      // Check if mounted - if not, store results to apply when app resumes
      if (!mounted) {
        if (mergedLocations.isNotEmpty) {
          print(
              '🔄 COMBINED SCAN: App backgrounded, storing ${mergedLocations.length} result(s) for later');
          _pendingScanResults = mergedLocations;
          if (mergedLocations.length == 1) {
            _pendingScanSingleMessage =
                '📷 Found: ${mergedLocations.first.name}';
          }
        }
        return;
      }

      if (mergedLocations.isEmpty) {
        print('⚠️ COMBINED SCAN: No locations found from either method');
        Fluttertoast.showToast(
          msg:
              '📷 No locations found. Try pausing video on text, or upload a screenshot.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.orange[700],
        );
        return;
      }

      _updateScanProgress(0.88, sessionId: scanSessionId);

      // Try to detect event information from any available text content
      // Priority 1: Use the OCR extracted text from Gemini (has dates like "April 4-6, 2025")
      // Priority 2: Use the WebView extracted caption
      // Priority 3: Check location metadata
      ExtractedEventInfo? detectedEvent;

      // Priority 1: OCR extracted text from Gemini scan (most likely to have dates)
      if (_lastScanExtractedText != null &&
          _lastScanExtractedText!.isNotEmpty) {
        print(
            '📅 COMBINED SCAN: Checking OCR extracted text for event info (${_lastScanExtractedText!.length} chars)...');
        detectedEvent =
            await _detectEventFromTextAsync(_lastScanExtractedText!);
        if (!_isAnalysisSessionActive(scanSessionId)) return;
      }

      // Priority 2: WebView extracted caption (might have additional context)
      if (detectedEvent == null &&
          _extractedCaption != null &&
          _extractedCaption!.isNotEmpty) {
        print('📅 COMBINED SCAN: Checking WebView caption for event info...');
        detectedEvent = await _detectEventFromTextAsync(_extractedCaption!);
        if (!_isAnalysisSessionActive(scanSessionId)) return;
      }

      // Priority 3: Check location metadata for event-related text
      if (detectedEvent == null && mergedLocations.isNotEmpty) {
        for (final location in mergedLocations) {
          if (location.metadata != null) {
            final extractedText =
                location.metadata!['extractedText'] as String?;
            if (extractedText != null && extractedText.isNotEmpty) {
              print(
                  '📅 COMBINED SCAN: Checking location metadata for event info...');
              detectedEvent = await _detectEventFromTextAsync(extractedText);
              if (!_isAnalysisSessionActive(scanSessionId)) return;
              if (detectedEvent != null) break;
            }
          }
        }
      }

      // Clear the stored extracted text after use
      _lastScanExtractedText = null;

      _updateScanProgress(0.95, sessionId: scanSessionId);

      // Heavy vibration to notify user scan completed
      _heavyVibration();

      final provider = context.read<ReceiveShareProvider>();

      // Always show the location dialog, even for single locations
      // This allows users to verify the extracted location before saving
      // If event info was detected, the dialog will show a second page for event designation
      // For combined scan, prefer the WebView caption, fall back to OCR extracted text
      final scannedTextForDialog = _extractedCaption ?? _lastScanExtractedText;
      final deepScanRequested = await _handleMultipleExtractedLocations(
        mergedLocations,
        provider,
        detectedEventInfo: detectedEvent,
        scannedText: scannedTextForDialog,
      );
      if (!_isAnalysisSessionActive(scanSessionId)) return;
      _updateScanProgress(1.0, sessionId: scanSessionId);

      // If user requested deep scan, run it after cleanup
      if (deepScanRequested && mounted) {
        _pendingDeepScanProvider = provider;
        _pendingDeepScanEventInfo = detectedEvent;
      }
    } catch (e) {
      print('❌ COMBINED SCAN ERROR: $e');
      if (_isAnalysisSessionActive(scanSessionId)) {
        Fluttertoast.showToast(
          msg: '❌ Scan failed. Please try scanning again.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.red,
        );
      }
    } finally {
      // Disable wakelock and stop foreground service
      WakelockPlus.disable();
      await _foregroundScanService.stopScanService();
      if (_isAnalysisSessionActive(scanSessionId)) {
        setState(() {
          _isProcessingScreenshot = false;
          _isAiScanInProgress = false;
          _scanProgress = 0.0;
        });
      }
    }

    // Run deep scan if requested (after cleanup is complete)
    if (_isAnalysisSessionActive(scanSessionId) &&
        _pendingDeepScanProvider != null &&
        mounted) {
      final provider = _pendingDeepScanProvider!;
      final eventInfo = _pendingDeepScanEventInfo;
      _pendingDeepScanProvider = null;
      _pendingDeepScanEventInfo = null;
      await _runDeepScan(provider, detectedEventInfo: eventInfo);
    }
  }

  /// Extract locations from screenshots using OCR
  /// For Instagram, captures BOTH native screen AND WebView screenshots and analyzes them TOGETHER
  /// [onProgress] - Optional callback for per-location progress updates (current, total, phase)
  Future<List<ExtractedLocationData>> _extractLocationsFromScreenshot(
    LatLng? userLocation, {
    void Function(int current, int total, String phase)? onProgress,
  }) async {
    try {
      final url = _currentSharedFiles.isNotEmpty
          ? _extractFirstUrl(_currentSharedFiles.first.path)
          : null;
      final isInstagram = url != null && _isInstagramUrl(url);

      List<Uint8List> screenshots = [];

      if (isInstagram) {
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
        print(
            '📷 COMBINED SCAN: Using multi-image combined analysis for ${screenshots.length} screenshots...');

        // Convert to the format expected by multi-image extraction
        final imageList = screenshots
            .map((bytes) => (
                  bytes: bytes,
                  mimeType: 'image/png',
                ))
            .toList();

        final result =
            await _locationExtractor.extractLocationsFromMultipleImages(
          imageList,
          userLocation: userLocation,
          onProgress: onProgress,
        );

        print(
            '📷 COMBINED SCAN: Multi-image analysis found ${result.locations.length} location(s)');
        if (result.regionContext != null) {
          print('🌍 COMBINED SCAN: Region context: "${result.regionContext}"');
        }

        // Store extracted text for event detection
        if (result.extractedText != null && result.extractedText!.isNotEmpty) {
          _lastScanExtractedText = result.extractedText;
          print(
              '📝 COMBINED SCAN: Stored extracted text (${result.extractedText!.length} chars) for event detection');
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
        onProgress: onProgress,
      );

      print(
          '📷 COMBINED SCAN: Single-image analysis found ${result.locations.length} location(s)');

      // Store extracted text for event detection (same as multi-image path)
      if (result.extractedText != null && result.extractedText!.isNotEmpty) {
        _lastScanExtractedText = result.extractedText;
        print(
            '📝 COMBINED SCAN: Stored extracted text (${result.extractedText!.length} chars) for event detection');
      }

      return result.locations;
    } catch (e) {
      print('⚠️ COMBINED SCAN: Screenshot extraction error: $e');
      return [];
    }
  }

  /// Check if a location is a duplicate of any in the list
  bool _isDuplicateLocation(
      ExtractedLocationData loc, List<ExtractedLocationData> existingList) {
    final normalizedName =
        (loc.name ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    for (final existing in existingList) {
      // Check place ID match
      if (loc.placeId != null &&
          existing.placeId != null &&
          loc.placeId == existing.placeId) {
        return true;
      }

      // Check name similarity
      final existingNormalized = (existing.name ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (normalizedName.isNotEmpty && existingNormalized.isNotEmpty) {
        // Exact match is definitely a duplicate
        if (normalizedName == existingNormalized) {
          return true;
        }

        // For containment matches, require the shorter name to be at least 80% of the
        // longer name's length to avoid false positives like "Ruru Kamakura" vs "Kamakura"
        // (8/12 = 67% < 80%, so NOT a duplicate)
        if (normalizedName.contains(existingNormalized) ||
            existingNormalized.contains(normalizedName)) {
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
  Future<List<ExtractedLocationData>> _extractLocationsFromPageText(
      String? url, LatLng? userLocation) async {
    try {
      print('📄 COMBINED SCAN: Extracting page text...');
      final pageContent = await _tryExtractPageContent();

      if (pageContent == null || pageContent.isEmpty) {
        print('⚠️ COMBINED SCAN: Could not extract page content');
        return [];
      }

      print(
          '📄 COMBINED SCAN: Extracted ${pageContent.length} chars, analyzing with Gemini...');

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
        final hasValidCoords =
            loc.coordinates.latitude != 0 || loc.coordinates.longitude != 0;
        final hasGrounding = loc.placeId.isNotEmpty;
        final confidence = hasGrounding ? 0.9 : (hasValidCoords ? 0.7 : 0.5);

        return ExtractedLocationData(
          name: loc.name,
          address: loc.formattedAddress,
          placeId: loc.placeId.isNotEmpty ? loc.placeId : null,
          coordinates: hasValidCoords ? loc.coordinates : null,
          type: placeType,
          source: hasGrounding
              ? ExtractionSource.geminiGrounding
              : ExtractionSource.placesSearch,
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

  /// Resolve locations that don't have coordinates via Places API
  ///
  /// When Gemini's Maps grounding doesn't return coordinates (e.g., for generic web pages),
  /// we fall back to searching Places Text Search API using the location name.
  /// Text Search API returns full place details including coordinates (unlike Autocomplete).
  /// This ensures locations can be saved and shown in the dialog.
  Future<List<ExtractedLocationData>> _resolveLocationsWithoutCoordinates(
    List<ExtractedLocationData> locations,
    LatLng? userLocation,
  ) async {
    final resolved = <ExtractedLocationData>[];

    for (final loc in locations) {
      // If already has coordinates, keep it as-is
      if (loc.coordinates != null) {
        resolved.add(loc);
        continue;
      }

      // Try to resolve via Places Text Search API (returns coordinates directly)
      final searchQuery = loc.address != null && loc.address!.isNotEmpty
          ? '${loc.name} ${loc.address}'
          : loc.name ?? '';

      if (searchQuery.isEmpty) {
        print('⏭️ RESOLVE: Skipping location with no name');
        continue;
      }

      print(
          '🔍 RESOLVE: Searching Places Text Search API for "$searchQuery"...');

      try {
        // Use searchPlacesTextSearch which returns full details including lat/lng
        // (unlike searchPlaces which uses Autocomplete and only returns place IDs)
        final results = await _mapsService.searchPlacesTextSearch(
          searchQuery,
          latitude: userLocation?.latitude,
          longitude: userLocation?.longitude,
        );

        if (results.isNotEmpty) {
          final firstResult = results.first;
          final placeId = firstResult['placeId'] as String?;
          // Text Search API returns 'latitude'/'longitude' not 'lat'/'lng'
          final lat = firstResult['latitude'] as double?;
          final lng = firstResult['longitude'] as double?;
          // Text Search API returns 'address' not 'formattedAddress'
          final address = firstResult['address'] as String?;
          final resolvedName = firstResult['name'] as String?;
          final placeTypes = (firstResult['types'] as List?)?.cast<String>();

          if (lat != null && lng != null) {
            print(
                '✅ RESOLVE: Found "${loc.name}" → placeId: ${placeId ?? "none"}, coords: ($lat, $lng)');
            resolved.add(loc.copyWith(
              placeId: placeId,
              coordinates: LatLng(lat, lng),
              address: address ?? loc.address,
              // Keep original name if resolver returned a different one
              name: loc.name ?? resolvedName,
              source: ExtractionSource.placesSearch,
              // Match Instagram preview confidence: 0.85 for verified Places API results with coordinates
              // This is consistent with LinkLocationExtractionService._verifyLocationWithPlacesAPI
              confidence: 0.85,
              placeTypes: placeTypes,
            ));
            continue;
          }
        }

        print(
            '⏭️ RESOLVE: Could not resolve "${loc.name}" - no Places API match');
        // Keep the unresolved location so it shows in the dialog (with a "not found" indicator)
        resolved.add(loc);
      } catch (e) {
        print('⚠️ RESOLVE: Error searching for "${loc.name}": $e');
        resolved.add(loc); // Keep unresolved
      }
    }

    return resolved;
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
      return name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').trim();
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
          final shorterLen =
              name.length < seen.length ? name.length : seen.length;
          final longerLen =
              name.length > seen.length ? name.length : seen.length;
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

    // Try Instagram preview
    if (_isInstagramUrl(url)) {
      final instagramPreviewKey = _instagramPreviewKeys[url];
      if (instagramPreviewKey?.currentState != null) {
        try {
          final content =
              await instagramPreviewKey!.currentState!.extractPageContent();
          if (content != null && content.isNotEmpty) {
            print('✅ SCAN PAGE: Extracted content from Instagram preview');
            return content;
          }
        } catch (e) {
          print('⚠️ SCAN PAGE: Instagram content extraction failed: $e');
        }
      }
    }

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
          final content =
              await facebookPreviewKey!.currentState!.extractPageContent();
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
          print(
              '⚠️ SCAN PREVIEW: Unexpected native result type: ${result.runtimeType}');
        }

        if (result is Uint8List || result is List) {
          final bytes = result is Uint8List
              ? result
              : Uint8List.fromList((result as List).cast<int>());
          print(
              '✅ SCAN PREVIEW: Captured native screen for Instagram (${bytes.length} bytes)');
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
            print(
                '✅ SCAN PREVIEW: Captured Instagram WebView (${webviewScreenshot.length} bytes)');
            screenshots.add(webviewScreenshot);
          }
        }
      }
    } catch (e) {
      print('⚠️ SCAN PREVIEW: WebView screenshot failed: $e');
    }

    print(
        '📷 SCAN PREVIEW: Captured ${screenshots.length} screenshot(s) for Instagram');
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
  static const MethodChannel _screenshotChannel =
      MethodChannel('com.plendy.app/screenshot');

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
          print(
              '⚠️ SCAN PREVIEW: Unexpected result type: ${result.runtimeType}');
          return await _captureYouTubeWebViewFallback(url);
        }

        print(
            '✅ SCAN PREVIEW: Captured native screen (${pngBytes.length} bytes, PNG format)');

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
        print(
            '📷 SCAN PREVIEW: Taking native screen capture for Facebook Reel...');

        final result = await _screenshotChannel.invokeMethod('captureScreen');

        if (result != null) {
          Uint8List pngBytes;
          if (result is Uint8List) {
            pngBytes = result;
          } else if (result is List) {
            pngBytes = Uint8List.fromList(result.cast<int>());
          } else {
            print(
                '⚠️ SCAN PREVIEW: Unexpected result type: ${result.runtimeType}');
            return await _captureFacebookWebViewFallback(url);
          }

          print(
              '✅ SCAN PREVIEW: Captured native screen for Facebook Reel (${pngBytes.length} bytes, PNG format)');
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
    final scanSessionId = _startAnalysisSession();

    setState(() {
      _isProcessingScreenshot = true;
      _isAiScanInProgress = true;
      _scanProgress = 0.0;
    });

    // Enable wakelock to prevent screen from sleeping during AI scan
    WakelockPlus.enable();

    // Start foreground service to keep app alive during scan
    await _foregroundScanService.startScanService();
    if (!_isAnalysisSessionActive(scanSessionId)) return;

    try {
      _updateScanProgress(0.1, sessionId: scanSessionId);

      // Get user location for better results (optional)
      LatLng? userLocation;
      if (_currentUserPosition != null) {
        userLocation = LatLng(
          _currentUserPosition!.latitude,
          _currentUserPosition!.longitude,
        );
      }

      _updateScanProgress(0.2, sessionId: scanSessionId);
      print('📷 SCREENSHOT: Starting AI location extraction from image...');

      // Extract locations using Gemini Vision
      _updateScanProgress(0.35, sessionId: scanSessionId);
      final result = await _locationExtractor.extractLocationsFromImage(
        imageFile,
        userLocation: userLocation,
        onProgress: (current, total, phase) {
          // Map progress from 0.35 to 0.8 range
          if (current == 0) {
            _updateScanProgress(0.40, sessionId: scanSessionId); // AI analysis
          } else {
            final progress = 0.40 + (0.40 * current / total);
            _updateScanProgress(progress, sessionId: scanSessionId);
          }
        },
      );
      if (!_isAnalysisSessionActive(scanSessionId)) return;
      final locations = result.locations;
      _updateScanProgress(0.8, sessionId: scanSessionId);

      // Check if mounted - if not, store results to apply when app resumes
      if (!mounted) {
        if (locations.isNotEmpty) {
          print(
              '📷 SCREENSHOT: App backgrounded, storing ${locations.length} result(s) for later');
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
      _updateScanProgress(0.85, sessionId: scanSessionId);

      // Try to detect event information from the extracted text (OCR result)
      // For uploaded screenshots, we use the extracted text from OCR
      ExtractedEventInfo? detectedEvent;
      if (result.extractedText != null && result.extractedText!.isNotEmpty) {
        print('📅 SCREENSHOT: Checking OCR extracted text for event info...');
        detectedEvent = await _detectEventFromTextAsync(result.extractedText!);
        if (!_isAnalysisSessionActive(scanSessionId)) return;
      }

      _updateScanProgress(0.95, sessionId: scanSessionId);

      // Heavy vibration to notify user scan completed
      _heavyVibration();

      final provider = context.read<ReceiveShareProvider>();

      // Always show the location selection dialog, even for single results
      // Pass detected event info for event designation
      // Use the extracted text from OCR directly (already available in result)
      final deepScanRequested = await _handleMultipleExtractedLocations(
        locations,
        provider,
        detectedEventInfo: detectedEvent,
        scannedText: result.extractedText,
      );
      if (!_isAnalysisSessionActive(scanSessionId)) return;
      _updateScanProgress(1.0, sessionId: scanSessionId);

      // If user requested deep scan, run it after cleanup
      if (deepScanRequested && mounted) {
        _pendingDeepScanProvider = provider;
        _pendingDeepScanEventInfo = detectedEvent;
      }
    } catch (e) {
      print('❌ SCREENSHOT ERROR: $e');
      if (_isAnalysisSessionActive(scanSessionId)) {
        Fluttertoast.showToast(
          msg: '❌ Scan failed. Please try scanning again.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.red,
        );
      }
    } finally {
      // Disable wakelock and stop foreground service
      WakelockPlus.disable();
      await _foregroundScanService.stopScanService();
      if (_isAnalysisSessionActive(scanSessionId)) {
        setState(() {
          _isProcessingScreenshot = false;
          _isAiScanInProgress = false;
          _scanProgress = 0.0;
        });
      }
    }

    // Run deep scan if requested (after cleanup is complete)
    if (_isAnalysisSessionActive(scanSessionId) &&
        _pendingDeepScanProvider != null &&
        mounted) {
      final provider = _pendingDeepScanProvider!;
      final eventInfo = _pendingDeepScanEventInfo;
      _pendingDeepScanProvider = null;
      _pendingDeepScanEventInfo = null;
      await _runDeepScan(provider, detectedEventInfo: eventInfo);
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

  // Track Instagram URLs that have already been processed for oEmbed extraction
  final Set<String> _instagramUrlsProcessed = {};

  // Ticketmaster event details cache - maps URL to event details
  final Map<String, TicketmasterEventDetails?> _ticketmasterEventDetails = {};
  // Track Ticketmaster URLs that are currently being loaded
  final Set<String> _ticketmasterUrlsLoading = {};

  // ============================================================================
  // SOCIAL MEDIA CONTENT EXTRACTION (Instagram/Facebook oEmbed)
  // ============================================================================
  // These variables store extracted content from Instagram/Facebook posts
  // when shared to Plendy. Use these values in other methods as needed.

  /// The full caption text extracted from Instagram/Facebook post
  String? _extractedCaption;

  /// List of hashtags found in the caption (without # prefix)
  List<String> _extractedHashtags = [];

  /// List of mentions found in the caption (without @ prefix)
  List<String> _extractedMentions = [];

  /// The source URL that the content was extracted from
  String? _extractedFromUrl;

  /// The platform the content was extracted from ('Instagram' or 'Facebook')
  String? _extractedFromPlatform;

  /// Full extracted text from Gemini OCR/image analysis (includes dates, event info, etc.)
  /// This is populated during screenshot scans and contains the raw text from images.
  String? _lastScanExtractedText;

  // Add debounce timer for location updates
  Timer? _locationUpdateDebounce;

  // Suspend media previews (unmount WebViews) while navigating to other screens
  bool _suspendMediaPreviews = false;

  // Method to show toast notifications with Plendy icon
  void _showSnackBar(BuildContext context, String message) {
    // Use FToast for custom toast with icon
    final fToast = FToast();
    fToast.init(context);

    final toast = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        color: Colors.grey[800],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Plendy icon in a circle
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(4),
            child: Image.asset(
              'assets/icon/icon-cropped.png',
              width: 16,
              height: 16,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );

    fToast.showToast(
      child: toast,
      gravity: ToastGravity.BOTTOM,
      toastDuration: const Duration(seconds: 2),
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
    // Help flow + spotlight animation
    _helpFlow = HelpFlowState<ReceiveShareHelpTargetId>(
        content: receiveShareHelpContent);
    _spotlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

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
      _sharingService.markReceiveShareScreenOpen(
          context: context, sharedFiles: widget.sharedFiles);
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
        // Note: selectedOtherCategoryIds intentionally not restored to start fresh each time
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
        String? currentYelpUrl =
            _extractYelpUrlFromSharedFiles(_currentSharedFiles);

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
        if (currentYelpUrl != null &&
            currentYelpUrl == yelpUrl &&
            _hasExistingCards()) {
          _handleYelpUrlUpdate(yelpUrl, updatedFiles);
          Future.delayed(const Duration(milliseconds: 1000), () {
            _isProcessingUpdate = false;
          });
          return;
        }

        // If it's a different Yelp URL (or no current content), reset the screen and process as new share
        // This handles the case where user shares a new Yelp URL while screen is already open
        print(
            '🔄 YELP: New Yelp URL detected while screen is open. Resetting and processing as new share.');
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
    if (first.type != SharedMediaType.url && first.type != SharedMediaType.text)
      return;

    final url = _extractFirstUrl(first.path);
    if (url == null) return;

    // Only auto-extract for YouTube URLs
    if (_isYouTubeUrl(url)) {
      print(
          '🎬 AUTO-EXTRACT: YouTube URL detected via share intent, triggering video analysis');
      // Delay slightly to allow UI to settle
      Future.delayed(const Duration(milliseconds: 500), () async {
        if (!mounted) return;
        if (!await _shouldAutoExtractLocations()) return;
        _extractLocationsFromUrl(url);
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

  bool _shouldAutoExtractFromSubmittedUrl(String url) {
    if (_isInstagramUrl(url) || _isTikTokUrl(url) || _isFacebookUrl(url)) {
      return false;
    }
    if (_isGoogleKnowledgeGraphUrl(url)) {
      return false;
    }
    if (_isYouTubeUrl(url)) {
      return true;
    }
    // Generic URLs auto-scan on WebView load.
    return false;
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
    final shouldAutoExtractFromSubmit = _shouldAutoExtractFromSubmittedUrl(url);
    _shouldAutoExtractLocations().then((shouldAuto) {
      if (!shouldAuto || !shouldAutoExtractFromSubmit) return;
      _extractLocationsFromUrl(url);
    });
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
    final scanSessionId = _startAnalysisSession();

    setState(() {
      _isExtractingLocation = true;
      _isAiScanInProgress = true;
      _scanProgress = 0.0;
    });

    // Enable wakelock to prevent screen from sleeping during AI scan
    WakelockPlus.enable();

    // Start foreground service to keep app alive during scan
    await _foregroundScanService.startScanService();
    if (!_isAnalysisSessionActive(scanSessionId)) return;

    try {
      _updateScanProgress(0.1, sessionId: scanSessionId);

      // Get user location for better results (optional)
      LatLng? userLocation;
      if (_currentUserPosition != null) {
        userLocation = LatLng(
          _currentUserPosition!.latitude,
          _currentUserPosition!.longitude,
        );
      }

      _updateScanProgress(0.2, sessionId: scanSessionId);
      print('🤖 AI EXTRACTION: Starting location extraction from URL...');

      // Extract locations using Gemini + Maps grounding
      // No limit on locations extracted from URLs
      _updateScanProgress(0.35, sessionId: scanSessionId);
      final locations = await _locationExtractor.extractLocationsFromSharedLink(
        url,
        userLocation: userLocation,
        maxLocations: null, // No limit
      );
      if (!_isAnalysisSessionActive(scanSessionId)) return;
      _updateScanProgress(0.8, sessionId: scanSessionId);

      // Check if mounted - if not, store results to apply when app resumes
      if (!mounted) {
        if (locations.isNotEmpty) {
          print(
              '🤖 AI EXTRACTION: App backgrounded, storing ${locations.length} result(s) for later');
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
      _updateScanProgress(0.9, sessionId: scanSessionId);

      // Heavy vibration to notify user scan completed
      _heavyVibration();

      final provider = context.read<ReceiveShareProvider>();

      // Always show the location selection dialog, even for single results
      // Priority for scanned text:
      // 1. lastAnalyzedContent from extraction service (YouTube video title/description/transcript)
      // 2. _extractedCaption from WebView caption extraction
      // 3. Fallback is handled by _handleMultipleExtractedLocations
      final analyzedContent = _locationExtractor.lastAnalyzedContent;
      final scannedTextForDialog = analyzedContent ?? _extractedCaption;

      final deepScanRequested = await _handleMultipleExtractedLocations(
        locations,
        provider,
        scannedText: scannedTextForDialog,
      );
      if (!_isAnalysisSessionActive(scanSessionId)) return;
      _updateScanProgress(1.0, sessionId: scanSessionId);

      // If user requested deep scan, run it after cleanup
      print(
          '🔍 URL EXTRACTION: deepScanRequested=$deepScanRequested, mounted=$mounted');
      if (deepScanRequested && mounted) {
        print('🔍 URL EXTRACTION: Setting _pendingDeepScanProvider');
        _pendingDeepScanProvider = provider;
        _pendingDeepScanEventInfo = null;
      }
    } catch (e) {
      print('❌ AI EXTRACTION ERROR: $e');
      if (_isAnalysisSessionActive(scanSessionId)) {
        Fluttertoast.showToast(
          msg: '❌ Scan failed. Please try scanning again.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.red,
        );
      }
    } finally {
      // Disable wakelock and stop foreground service
      print('🔍 URL EXTRACTION: Finally block - cleaning up');
      WakelockPlus.disable();
      await _foregroundScanService.stopScanService();
      if (_isAnalysisSessionActive(scanSessionId)) {
        setState(() {
          _isExtractingLocation = false;
          _isAiScanInProgress = false;
          _scanProgress = 0.0;
        });
      }
      print(
          '🔍 URL EXTRACTION: Finally block complete, _pendingDeepScanProvider=${_pendingDeepScanProvider != null}');
    }

    // Run deep scan if requested (after cleanup is complete)
    print(
        '🔍 URL EXTRACTION: After finally - _pendingDeepScanProvider=${_pendingDeepScanProvider != null}, mounted=$mounted');
    if (_isAnalysisSessionActive(scanSessionId) &&
        _pendingDeepScanProvider != null &&
        mounted) {
      print('🔍 URL EXTRACTION: Starting deep scan...');
      final provider = _pendingDeepScanProvider!;
      final eventInfo = _pendingDeepScanEventInfo;
      _pendingDeepScanProvider = null;
      _pendingDeepScanEventInfo = null;
      await _runDeepScan(provider, detectedEventInfo: eventInfo);
    } else {
      print(
          '🔍 URL EXTRACTION: NOT starting deep scan - provider null or not mounted');
    }
  }

  /// Load Ticketmaster event details and auto-fill experience card
  Future<void> _loadTicketmasterEventDetails(
      String url, ExperienceCardData? card) async {
    // Prevent duplicate loading
    if (_ticketmasterUrlsLoading.contains(url)) {
      print('🎫 TICKETMASTER: Already loading $url, skipping');
      return;
    }

    // Mark as loading (both preview and location field)
    if (mounted) {
      setState(() {
        _ticketmasterUrlsLoading.add(url);
        // Show loading spinner in location field
        if (card != null) {
          card.isSelectingLocation = true;
        }
      });
    }

    try {
      print('🎫 TICKETMASTER: Loading event details from URL: $url');

      // Extract event ID first to verify URL format
      final eventId = TicketmasterService.extractEventIdFromUrl(url);
      if (eventId == null) {
        print('🎫 TICKETMASTER: Could not extract event ID from URL: $url');
        if (mounted) {
          setState(() {
            _ticketmasterUrlsLoading.remove(url);
            _ticketmasterEventDetails[url] = null;
            // Clear location loading state
            if (card != null) {
              card.isSelectingLocation = false;
            }
          });
        }
        return;
      }

      print('🎫 TICKETMASTER: Extracted event ID: $eventId');

      // Step 1: Try direct event ID lookup
      TicketmasterEventDetails? details =
          await _ticketmasterService.getEventFromUrl(url);

      if (!mounted) return;

      // Step 2: If direct lookup failed, try searching by event name + date + city
      if (details == null) {
        print(
            '🎫 TICKETMASTER: Direct ID lookup failed, trying search fallback...');
        details = await _searchTicketmasterEventFromUrl(url);
      }

      print(
          '🎫 TICKETMASTER: Final result: details=${details != null ? "found" : "null"}');

      setState(() {
        _ticketmasterEventDetails[url] = details;
        _ticketmasterUrlsLoading.remove(url);
      });

      // Auto-fill the experience card if we have details
      if (details != null) {
        print('🎫 TICKETMASTER: Event found: ${details.name}');
        await _autoFillExperienceCardFromTicketmaster(details, url, card);
      } else {
        print(
            '🎫 TICKETMASTER: No event details from API or search, using URL fallback');
        // Fallback: Extract info from URL and still populate card
        await _autoFillExperienceCardFromTicketmasterUrl(url, card);
      }
    } catch (e, stackTrace) {
      print('🎫 TICKETMASTER: Error loading event details: $e');
      print('🎫 TICKETMASTER: Stack trace: $stackTrace');
      if (!mounted) return;
      setState(() {
        _ticketmasterUrlsLoading.remove(url);
        _ticketmasterEventDetails[url] = null;
        // Clear location loading state on error
        if (card != null) {
          card.isSelectingLocation = false;
        }
      });
    }
  }

  /// Search Ticketmaster API for an event using info extracted from URL
  /// This is a fallback when direct event ID lookup fails
  Future<TicketmasterEventDetails?> _searchTicketmasterEventFromUrl(
      String url) async {
    try {
      // Extract event info from URL
      final urlInfo = _extractTicketmasterUrlInfo(url);
      if (urlInfo == null) {
        print('🎫 TICKETMASTER SEARCH: Could not extract info from URL');
        return null;
      }

      final eventName = urlInfo['eventName'] as String?;
      final city = urlInfo['city'] as String?;
      final state = urlInfo['state'] as String?;
      final date = urlInfo['date'] as DateTime?;

      if (eventName == null || eventName.isEmpty) {
        print('🎫 TICKETMASTER SEARCH: No event name extracted');
        return null;
      }

      print(
          '🎫 TICKETMASTER SEARCH: Searching for "$eventName" in $city, $state on $date');

      // Get state code for API (e.g., "California" -> "CA", "Illinois" -> "IL")
      final stateCode = _getStateCode(state);

      // Search for the event
      final searchResults = await _ticketmasterService.searchEvents(
        keyword: eventName,
        city: city,
        stateCode: stateCode,
        startDateTime: date?.subtract(const Duration(days: 1)),
        endDateTime: date?.add(const Duration(days: 1)),
        size: 5,
      );

      if (searchResults.isEmpty) {
        print(
            '🎫 TICKETMASTER SEARCH: No results with date filter, trying without date');
        // Try again without date filter
        final fallbackResults = await _ticketmasterService.searchEvents(
          keyword: eventName,
          city: city,
          stateCode: stateCode,
          size: 5,
        );

        if (fallbackResults.isEmpty) {
          print('🎫 TICKETMASTER SEARCH: No results found');
          return null;
        }

        // Use the first result
        final bestMatch = fallbackResults.first;
        print(
            '🎫 TICKETMASTER SEARCH: Found match (no date filter): ${bestMatch.name} at ${bestMatch.venueName}');

        // Get full details using the event ID from search
        return await _ticketmasterService.getEventById(bestMatch.id);
      }

      // Find best match by date proximity if we have a date
      TicketmasterEventResult bestMatch = searchResults.first;
      if (date != null) {
        Duration? closestDiff;
        for (final result in searchResults) {
          if (result.startDateTime != null) {
            final diff = result.startDateTime!.difference(date).abs();
            if (closestDiff == null || diff < closestDiff) {
              closestDiff = diff;
              bestMatch = result;
            }
          }
        }
      }

      print(
          '🎫 TICKETMASTER SEARCH: Found match: ${bestMatch.name} at ${bestMatch.venueName}');

      // Get full details using the event ID from search
      final fullDetails = await _ticketmasterService.getEventById(bestMatch.id);

      if (fullDetails != null) {
        print(
            '🎫 TICKETMASTER SEARCH: Got full details with venue: ${fullDetails.venue?.name}');
      }

      return fullDetails;
    } catch (e) {
      print('🎫 TICKETMASTER SEARCH: Error: $e');
      return null;
    }
  }

  /// Extract event info from Ticketmaster URL
  /// Returns map with eventName, city, state, date
  Map<String, dynamic>? _extractTicketmasterUrlInfo(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;

      // Find the segment before "event"
      for (int i = 0; i < pathSegments.length; i++) {
        if (pathSegments[i] == 'event' && i > 0) {
          final slug = pathSegments[i - 1];
          final parts = slug.split('-');

          String? eventName;
          String? city;
          String? state;
          DateTime? date;

          // Try to extract date from the end (MM-DD-YYYY format)
          if (parts.length >= 3) {
            try {
              final yearStr = parts[parts.length - 1];
              final dayStr = parts[parts.length - 2];
              final monthStr = parts[parts.length - 3];

              final year = int.tryParse(yearStr);
              final day = int.tryParse(dayStr);
              final month = int.tryParse(monthStr);

              if (year != null &&
                  year > 2000 &&
                  year < 2100 &&
                  month != null &&
                  month >= 1 &&
                  month <= 12 &&
                  day != null &&
                  day >= 1 &&
                  day <= 31) {
                date = DateTime(year, month, day);

                // Remove date parts from the list
                final partsWithoutDate = parts.sublist(0, parts.length - 3);

                // Extract state (usually the last word before date)
                if (partsWithoutDate.isNotEmpty) {
                  final possibleState = partsWithoutDate.last.toLowerCase();
                  if (_isLikelyUSState(possibleState)) {
                    state = _capitalizeWord(possibleState);
                    partsWithoutDate.removeLast();
                  }
                }

                // Extract city (usually the word before state)
                if (partsWithoutDate.isNotEmpty) {
                  city = _capitalizeWord(partsWithoutDate.last);
                  partsWithoutDate.removeLast();
                }

                // The rest is the event name
                if (partsWithoutDate.isNotEmpty) {
                  eventName = partsWithoutDate
                      .map((word) => _capitalizeWord(word))
                      .join(' ');
                }
              }
            } catch (e) {
              // Date parsing failed
            }
          }

          // Fallback: just use the whole slug as event name
          if (eventName == null) {
            eventName = parts
                .map((word) => _capitalizeWord(word))
                .join(' ')
                .replaceAll(RegExp(r'\s+\d{2}\s+\d{2}\s+\d{4}$'), '');
          }

          return {
            'eventName': eventName,
            'city': city,
            'state': state,
            'date': date,
          };
        }
      }
      return null;
    } catch (e) {
      print('🎫 TICKETMASTER: Error extracting URL info: $e');
      return null;
    }
  }

  /// Convert full state name to state code
  String? _getStateCode(String? stateName) {
    if (stateName == null) return null;

    const stateCodeMap = {
      'alabama': 'AL',
      'alaska': 'AK',
      'arizona': 'AZ',
      'arkansas': 'AR',
      'california': 'CA',
      'colorado': 'CO',
      'connecticut': 'CT',
      'delaware': 'DE',
      'florida': 'FL',
      'georgia': 'GA',
      'hawaii': 'HI',
      'idaho': 'ID',
      'illinois': 'IL',
      'indiana': 'IN',
      'iowa': 'IA',
      'kansas': 'KS',
      'kentucky': 'KY',
      'louisiana': 'LA',
      'maine': 'ME',
      'maryland': 'MD',
      'massachusetts': 'MA',
      'michigan': 'MI',
      'minnesota': 'MN',
      'mississippi': 'MS',
      'missouri': 'MO',
      'montana': 'MT',
      'nebraska': 'NE',
      'nevada': 'NV',
      'new hampshire': 'NH',
      'new jersey': 'NJ',
      'new mexico': 'NM',
      'new york': 'NY',
      'north carolina': 'NC',
      'north dakota': 'ND',
      'ohio': 'OH',
      'oklahoma': 'OK',
      'oregon': 'OR',
      'pennsylvania': 'PA',
      'rhode island': 'RI',
      'south carolina': 'SC',
      'south dakota': 'SD',
      'tennessee': 'TN',
      'texas': 'TX',
      'utah': 'UT',
      'vermont': 'VT',
      'virginia': 'VA',
      'washington': 'WA',
      'west virginia': 'WV',
      'wisconsin': 'WI',
      'wyoming': 'WY',
      'district of columbia': 'DC',
    };

    return stateCodeMap[stateName.toLowerCase()];
  }

  /// Auto-fill experience card form with Ticketmaster event details
  Future<void> _autoFillExperienceCardFromTicketmaster(
    TicketmasterEventDetails details,
    String url,
    ExperienceCardData? card,
  ) async {
    final provider = context.read<ReceiveShareProvider>();
    final experienceCards = provider.experienceCards;

    // Find the target card to update
    ExperienceCardData? targetCard = card;
    if (targetCard == null && experienceCards.isNotEmpty) {
      // Use the first card if no specific card provided
      targetCard = experienceCards.first;
    }

    if (targetCard == null) {
      print('🎫 TICKETMASTER: No experience card to update');
      return;
    }

    print('🎫 TICKETMASTER: Auto-filling experience card with event details');
    print('🎫 Event: ${details.name}');
    print('🎫 Venue: ${details.venue?.name}');
    print('🎫 Date: ${details.startDateTime}');

    // Update title with venue name (not event name - event name goes to the calendar event)
    if (targetCard.titleController.text.isEmpty) {
      final venueName = details.venue?.name;
      if (venueName != null && venueName.isNotEmpty) {
        targetCard.titleController.text = venueName;
        print('🎫 TICKETMASTER: Set title to venue: $venueName');
      }
    }

    // Update website with Ticketmaster URL
    if (targetCard.websiteController.text.isEmpty) {
      targetCard.websiteController.text = details.url ?? url;
    }

    // Update location if we have venue details
    if (targetCard.selectedLocation == null && details.venue != null) {
      final venue = details.venue!;
      Location? location;
      String? placeId;

      // Build search query for Google Places to get the actual place with placeId
      // We always search Google Places even if Ticketmaster provides coordinates,
      // because we need the placeId for duplicate detection and photo retrieval
      String? searchQuery;
      if (venue.name != null && venue.name!.isNotEmpty) {
        searchQuery = venue.fullAddress != null
            ? '${venue.name}, ${venue.fullAddress}'
            : venue.city != null
                ? '${venue.name}, ${venue.city}'
                : venue.name;
      } else if (venue.fullAddress != null && venue.fullAddress!.isNotEmpty) {
        searchQuery = venue.fullAddress;
      } else if (venue.city != null) {
        searchQuery =
            venue.state != null ? '${venue.city}, ${venue.state}' : venue.city;
      }

      if (searchQuery != null) {
        print('🎫 TICKETMASTER: Searching Google Places for: $searchQuery');
        try {
          final results =
              await _mapsService.searchPlacesTextSearch(searchQuery);
          if (results.isNotEmpty) {
            final firstResult = results.first;
            placeId = firstResult['placeId'] as String?;

            // If we got a placeId, fetch full place details for better data
            if (placeId != null && placeId.isNotEmpty) {
              print(
                  '🎫 TICKETMASTER: Found place ID: $placeId, fetching details...');
              try {
                final placeDetails =
                    await _mapsService.getPlaceDetails(placeId);
                location = placeDetails;
                print(
                    '🎫 TICKETMASTER: Got full place details: ${placeDetails.displayName}');
                print(
                    '🎫 TICKETMASTER: Photo resource: ${placeDetails.photoResourceName}');
              } catch (e) {
                print(
                    '🎫 TICKETMASTER: Error fetching place details, using search result: $e');
                // Fallback to search result data
                final lat = firstResult['latitude'] as double?;
                final lng = firstResult['longitude'] as double?;
                if (lat != null && lng != null) {
                  location = Location(
                    placeId: placeId,
                    displayName: venue.name ?? searchQuery,
                    address: venue.fullAddress ??
                        firstResult['address'] as String? ??
                        searchQuery,
                    city: venue.city,
                    state: venue.state,
                    country: venue.country,
                    zipCode: venue.postalCode,
                    latitude: lat,
                    longitude: lng,
                  );
                }
              }
            } else {
              // No placeId - use search result coordinates
              final lat = firstResult['latitude'] as double?;
              final lng = firstResult['longitude'] as double?;
              if (lat != null && lng != null) {
                location = Location(
                  displayName: venue.name ?? searchQuery,
                  address: venue.fullAddress ??
                      firstResult['address'] as String? ??
                      searchQuery,
                  city: venue.city,
                  state: venue.state,
                  country: venue.country,
                  zipCode: venue.postalCode,
                  latitude: lat,
                  longitude: lng,
                );
                print(
                    '🎫 TICKETMASTER: Created location from search (no placeId): ${venue.name ?? searchQuery}');
              }
            }
          }
        } catch (e) {
          print('🎫 TICKETMASTER: Error searching Google Places: $e');
        }
      }

      // Fallback: If Google Places search failed but Ticketmaster has coordinates,
      // use those as a last resort (won't have placeId or photos)
      if (location == null &&
          venue.latitude != null &&
          venue.longitude != null) {
        print(
            '🎫 TICKETMASTER: Falling back to Ticketmaster coordinates (no Google Place found)');
        location = Location(
          displayName: venue.name ?? details.name,
          address: venue.fullAddress ?? '',
          city: venue.city,
          state: venue.state,
          country: venue.country,
          zipCode: venue.postalCode,
          latitude: venue.latitude!,
          longitude: venue.longitude!,
        );
      }

      // Check for duplicate if we have a location
      if (location != null && mounted) {
        final venueName = venue.name ?? location.displayName;
        final locationPlaceId = location.placeId ?? placeId;

        // Check by placeId first (use location.placeId which has the Google Place ID)
        if (locationPlaceId != null && locationPlaceId.isNotEmpty) {
          final existingByPlaceId = await _checkForDuplicateExperienceDialog(
            context: context,
            card: targetCard,
            placeIdToCheck: locationPlaceId,
          );

          if (existingByPlaceId != null) {
            provider.updateCardWithExistingExperience(
                targetCard.id, existingByPlaceId);
            print(
                '🎫 TICKETMASTER: Using existing experience by placeId: ${existingByPlaceId.name}');
            // Clear location loading state and set event info for calendar
            targetCard.isSelectingLocation = false;
            if (mounted) setState(() {});
            _setTicketmasterEventInfo(details, url);
            return;
          }
        }

        // Check by venue name
        if (venueName != null && venueName.isNotEmpty) {
          final existingByName = await _checkForDuplicateExperienceDialog(
            context: context,
            card: targetCard,
            titleToCheck: venueName,
          );

          if (existingByName != null) {
            provider.updateCardWithExistingExperience(
                targetCard.id, existingByName);
            print(
                '🎫 TICKETMASTER: Using existing experience by name: ${existingByName.name}');
            // Clear location loading state and set event info for calendar
            targetCard.isSelectingLocation = false;
            if (mounted) setState(() {});
            _setTicketmasterEventInfo(details, url);
            return;
          }
        }

        // No duplicate found - set the location
        targetCard.selectedLocation = location;
        targetCard.locationController.text = venueName ?? '';

        // Also set the title to the venue name
        if (targetCard.titleController.text.isEmpty && venueName != null) {
          targetCard.titleController.text = venueName;
          print('🎫 TICKETMASTER: Set title to venue: $venueName');
        }

        print(
            '🎫 TICKETMASTER: Set location with placeId: ${locationPlaceId ?? "none"}');
        print(
            '🎫 TICKETMASTER: Location: ${venueName ?? location.displayName}');
      }
    }

    // Set detected event info for calendar
    _setTicketmasterEventInfo(details, url);

    // Clear location loading state and trigger UI update
    if (mounted && targetCard != null) {
      setState(() {
        targetCard!.isSelectingLocation = false;
      });
      _handleExperienceCardFormUpdate(
        cardId: targetCard.id,
        refreshCategories: false,
      );
    }

    // Show a toast notification
    Fluttertoast.showToast(
      msg: details.startDateTime != null
          ? '🎫 Event loaded! Date info will be saved.'
          : 'Event details loaded from Ticketmaster',
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
    );
  }

  /// Helper to set detected event info from Ticketmaster details
  void _setTicketmasterEventInfo(TicketmasterEventDetails details, String url) {
    if (details.startDateTime != null) {
      // Determine end time (use endDateTime if available, otherwise default to 2 hours after start)
      final endTime = details.endDateTime ??
          details.startDateTime!.add(const Duration(hours: 2));

      _detectedEventInfo = ExtractedEventInfo(
        eventName: details.name,
        startDateTime: details.startDateTime!,
        endDateTime: endTime,
        confidence: 0.95, // High confidence since it's from Ticketmaster API
        ticketmasterUrl: details.url ?? url,
        ticketmasterId: details.id,
        ticketmasterImageUrl:
            details.imageUrl, // Include image URL for event cover
      );

      print(
          '📅 TICKETMASTER EVENT: Detected event "${details.name}" at ${details.startDateTime}');
      print('📅 TICKETMASTER EVENT: Image URL: ${details.imageUrl}');
      print('📅 TICKETMASTER EVENT: Event info stored for post-save flow');
    }
  }

  /// Fallback: Auto-fill experience card from Ticketmaster URL when API fails
  /// Extracts event name from the URL slug
  Future<void> _autoFillExperienceCardFromTicketmasterUrl(
    String url,
    ExperienceCardData? card,
  ) async {
    final provider = context.read<ReceiveShareProvider>();
    final experienceCards = provider.experienceCards;

    // Find the target card to update
    ExperienceCardData? targetCard = card;
    if (targetCard == null && experienceCards.isNotEmpty) {
      targetCard = experienceCards.first;
    }

    if (targetCard == null) {
      print('🎫 TICKETMASTER FALLBACK: No experience card to update');
      return;
    }

    print('🎫 TICKETMASTER FALLBACK: Extracting info from URL');

    // Extract event name, city, state, and date from URL slug
    // URL format: https://www.ticketmaster.com/event-name-city-state-MM-DD-YYYY/event/ID
    // Example: lady-gaga-the-mayhem-ball-inglewood-california-02-18-2026
    String? eventName;
    String? city;
    String? state;
    DateTime? eventDate;

    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;

      // Find the segment before "event"
      for (int i = 0; i < pathSegments.length; i++) {
        if (pathSegments[i] == 'event' && i > 0) {
          // The previous segment is the event slug
          final slug = pathSegments[i - 1];
          final parts = slug.split('-');

          // Try to extract date from the end (MM-DD-YYYY format)
          if (parts.length >= 3) {
            try {
              final yearStr = parts[parts.length - 1];
              final dayStr = parts[parts.length - 2];
              final monthStr = parts[parts.length - 3];

              final year = int.tryParse(yearStr);
              final day = int.tryParse(dayStr);
              final month = int.tryParse(monthStr);

              if (year != null &&
                  year > 2000 &&
                  year < 2100 &&
                  month != null &&
                  month >= 1 &&
                  month <= 12 &&
                  day != null &&
                  day >= 1 &&
                  day <= 31) {
                eventDate = DateTime(year, month, day);
                print('🎫 TICKETMASTER FALLBACK: Extracted date: $eventDate');

                // Remove date parts from the list
                final partsWithoutDate = parts.sublist(0, parts.length - 3);

                // Try to extract state (usually the last word before date)
                // Common US state names: california, texas, new-york, florida, etc.
                if (partsWithoutDate.isNotEmpty) {
                  final possibleState = partsWithoutDate.last.toLowerCase();
                  if (_isLikelyUSState(possibleState)) {
                    state = _capitalizeWord(possibleState);
                    partsWithoutDate.removeLast();
                    print('🎫 TICKETMASTER FALLBACK: Extracted state: $state');
                  }
                }

                // Try to extract city (usually the word before state)
                if (partsWithoutDate.isNotEmpty) {
                  city = _capitalizeWord(partsWithoutDate.last);
                  partsWithoutDate.removeLast();
                  print('🎫 TICKETMASTER FALLBACK: Extracted city: $city');
                }

                // The rest is the event name
                if (partsWithoutDate.isNotEmpty) {
                  eventName = partsWithoutDate
                      .map((word) => _capitalizeWord(word))
                      .join(' ');
                }
              }
            } catch (e) {
              print('🎫 TICKETMASTER FALLBACK: Error parsing date: $e');
            }
          }

          // Fallback: just convert the whole slug to a readable name
          if (eventName == null) {
            eventName = parts.map((word) => _capitalizeWord(word)).join(' ');
            // Try to clean up: remove date patterns at the end (like "02 22 2026")
            eventName =
                eventName.replaceAll(RegExp(r'\s+\d{2}\s+\d{2}\s+\d{4}$'), '');
          }

          print('🎫 TICKETMASTER FALLBACK: Extracted event name: $eventName');
          break;
        }
      }
    } catch (e) {
      print('🎫 TICKETMASTER FALLBACK: Error parsing URL: $e');
    }

    // Don't fill title with event name - title will be set to venue/location name after geocoding
    // Event name will be used for the calendar event instead

    // Update website with Ticketmaster URL
    if (targetCard.websiteController.text.isEmpty) {
      targetCard.websiteController.text = url;
    }

    // Set detected event info if we have a date from the URL
    if (eventDate != null && eventName != null) {
      // Default event time to 7:00 PM if no specific time in URL
      final startTime = DateTime(
        eventDate.year,
        eventDate.month,
        eventDate.day,
        19, 0, // 7:00 PM
      );
      final endTime =
          startTime.add(const Duration(hours: 3)); // Default 3 hour duration

      _detectedEventInfo = ExtractedEventInfo(
        eventName: eventName,
        startDateTime: startTime,
        endDateTime: endTime,
        confidence: 0.7, // Lower confidence since extracted from URL, not API
        ticketmasterUrl: url,
      );

      print(
          '📅 TICKETMASTER FALLBACK EVENT: Detected event "$eventName" on $eventDate');
      print(
          '📅 TICKETMASTER FALLBACK EVENT: Event info stored for post-save flow');
    }

    // Geocode and update location if we have city/state
    if (targetCard != null &&
        targetCard.selectedLocation == null &&
        city != null) {
      await _geocodeAndSetTicketmasterLocation(targetCard, city, state,
          eventName: eventName);
    }

    // Clear location loading state and trigger UI update
    if (mounted && targetCard != null) {
      setState(() {
        targetCard!.isSelectingLocation = false;
      });
      _handleExperienceCardFormUpdate(
        cardId: targetCard.id,
        refreshCategories: false,
      );
    }

    // Show a toast notification
    Fluttertoast.showToast(
      msg: eventDate != null
          ? '🎫 Event loaded! Date info will be saved.'
          : city != null
              ? '🎫 Ticketmaster event loaded!'
              : 'Ticketmaster link saved (event details unavailable)',
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
    );
  }

  /// Helper to capitalize a word
  String _capitalizeWord(String word) {
    if (word.isEmpty) return word;
    return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
  }

  /// Check if a string looks like a US state name
  bool _isLikelyUSState(String word) {
    // Common US state names that appear in Ticketmaster URLs
    const usStates = {
      'alabama',
      'alaska',
      'arizona',
      'arkansas',
      'california',
      'colorado',
      'connecticut',
      'delaware',
      'florida',
      'georgia',
      'hawaii',
      'idaho',
      'illinois',
      'indiana',
      'iowa',
      'kansas',
      'kentucky',
      'louisiana',
      'maine',
      'maryland',
      'massachusetts',
      'michigan',
      'minnesota',
      'mississippi',
      'missouri',
      'montana',
      'nebraska',
      'nevada',
      'hampshire',
      'jersey',
      'mexico',
      'york',
      'carolina',
      'dakota',
      'ohio',
      'oklahoma',
      'oregon',
      'pennsylvania',
      'island',
      'tennessee',
      'texas',
      'utah',
      'vermont',
      'virginia',
      'washington',
      'wisconsin',
      'wyoming',
      'dc',
      'columbia',
    };
    return usStates.contains(word.toLowerCase());
  }

  /// Geocode city/state using Google Places API and set the location on the card
  /// First tries to find the specific venue by searching event name + city,
  /// then falls back to just city/state if no venue found
  Future<void> _geocodeAndSetTicketmasterLocation(
      ExperienceCardData targetCard, String city, String? state,
      {String? eventName}) async {
    try {
      // Step 1: Try to find the specific venue by searching "event name city"
      // This often returns the venue (e.g., "Lady Gaga Inglewood" -> Kia Forum)
      if (eventName != null && eventName.isNotEmpty) {
        final venueSearchQuery = '$eventName $city';
        print(
            '🎫 TICKETMASTER FALLBACK: Searching for venue: $venueSearchQuery');

        final venueResults =
            await _mapsService.searchPlacesTextSearch(venueSearchQuery);

        if (venueResults.isNotEmpty) {
          final firstResult = venueResults.first;
          final types = firstResult['types'] as List<String>?;
          final name = firstResult['name'] as String?;

          // Check if this is a specific venue/establishment, not just the city
          final isVenue = types != null &&
              !types.contains('locality') &&
              !types.contains('administrative_area_level_1') &&
              !types.contains('administrative_area_level_2') &&
              (types.contains('establishment') ||
                  types.contains('point_of_interest') ||
                  types.contains('stadium') ||
                  types.contains('concert_hall') ||
                  types.contains('performing_arts_theater') ||
                  types.contains('night_club') ||
                  types.contains('bar') ||
                  types.contains('restaurant'));

          if (isVenue && name != null) {
            final lat = firstResult['latitude'] as double?;
            final lng = firstResult['longitude'] as double?;
            final address = firstResult['address'] as String?;
            final placeId = firstResult['placeId'] as String?;

            if (lat != null && lng != null) {
              // Check for duplicates before setting
              final usedExisting = await _checkAndSetTicketmasterVenue(
                targetCard: targetCard,
                name: name,
                address: address ?? '$name, $city',
                city: city,
                state: state,
                lat: lat,
                lng: lng,
                placeId: placeId,
              );
              if (usedExisting != null) {
                print(
                    '🎫 TICKETMASTER FALLBACK: Using existing experience: ${usedExisting.name}');
              } else {
                print(
                    '🎫 TICKETMASTER FALLBACK: Found venue "$name" at $lat, $lng');
              }
              return;
            }
          } else {
            print(
                '🎫 TICKETMASTER FALLBACK: Search result is not a venue (types: $types), trying city search');
          }
        }
      }

      // Step 2: Try searching for "concert venue city" or "arena city"
      final venueTypeSearches = [
        'concert venue $city',
        'arena $city',
        'stadium $city'
      ];
      for (final searchQuery in venueTypeSearches) {
        print(
            '🎫 TICKETMASTER FALLBACK: Trying venue type search: $searchQuery');
        final results = await _mapsService.searchPlacesTextSearch(searchQuery);

        if (results.isNotEmpty) {
          final firstResult = results.first;
          final types = firstResult['types'] as List<String>?;
          final name = firstResult['name'] as String?;

          // Check if this is a specific venue
          final isVenue = types != null &&
              !types.contains('locality') &&
              (types.contains('establishment') ||
                  types.contains('point_of_interest') ||
                  types.contains('stadium'));

          if (isVenue && name != null) {
            final lat = firstResult['latitude'] as double?;
            final lng = firstResult['longitude'] as double?;
            final address = firstResult['address'] as String?;
            final placeId = firstResult['placeId'] as String?;

            if (lat != null && lng != null) {
              // Check for duplicates before setting
              final usedExisting = await _checkAndSetTicketmasterVenue(
                targetCard: targetCard,
                name: name,
                address: address ?? '$name, $city',
                city: city,
                state: state,
                lat: lat,
                lng: lng,
                placeId: placeId,
              );
              if (usedExisting != null) {
                print(
                    '🎫 TICKETMASTER FALLBACK: Using existing experience: ${usedExisting.name}');
              } else {
                print(
                    '🎫 TICKETMASTER FALLBACK: Found venue "$name" via type search at $lat, $lng');
              }
              return;
            }
          }
        }
      }

      // Step 3: Fall back to just city/state (don't set title - no specific venue found)
      final citySearchQuery = state != null ? '$city, $state' : city;
      print(
          '🎫 TICKETMASTER FALLBACK: No venue found, falling back to city: $citySearchQuery');

      final results =
          await _mapsService.searchPlacesTextSearch(citySearchQuery);

      if (results.isNotEmpty) {
        final firstResult = results.first;
        final placeId = firstResult['placeId'] as String?;

        Location? location;

        // Try to get full place details if we have a placeId
        if (placeId != null && placeId.isNotEmpty) {
          try {
            print(
                '🎫 TICKETMASTER FALLBACK: Fetching place details for city: $placeId');
            location = await _mapsService.getPlaceDetails(placeId);
          } catch (e) {
            print(
                '🎫 TICKETMASTER FALLBACK: Error fetching city place details: $e');
          }
        }

        // Fallback to search result data
        if (location == null) {
          final lat = firstResult['latitude'] as double?;
          final lng = firstResult['longitude'] as double?;
          final address = firstResult['address'] as String?;

          if (lat != null && lng != null) {
            location = Location(
              placeId: placeId,
              displayName: citySearchQuery,
              address: address ?? citySearchQuery,
              city: city,
              state: state,
              latitude: lat,
              longitude: lng,
            );
          }
        }

        if (location != null) {
          targetCard.selectedLocation = location;
          targetCard.locationController.text =
              location.displayName ?? citySearchQuery;

          print(
              '🎫 TICKETMASTER FALLBACK: Set location to city ${location.displayName ?? citySearchQuery}');
          print(
              '🎫 TICKETMASTER FALLBACK: PlaceId: ${location.placeId ?? "none"}');
        } else {
          print('🎫 TICKETMASTER FALLBACK: No coordinates in geocode result');
        }
      } else {
        print(
            '🎫 TICKETMASTER FALLBACK: No geocode results for $citySearchQuery');
      }
    } catch (e) {
      print('🎫 TICKETMASTER FALLBACK: Error geocoding location: $e');
    }
  }

  /// Helper to check for duplicates and set venue for Ticketmaster fallback
  /// Returns the existing Experience if user chose to use it, null otherwise
  Future<Experience?> _checkAndSetTicketmasterVenue({
    required ExperienceCardData targetCard,
    required String name,
    required String address,
    required String city,
    String? state,
    required double lat,
    required double lng,
    String? placeId,
  }) async {
    final provider = context.read<ReceiveShareProvider>();

    // Check for duplicate by placeId
    if (placeId != null && placeId.isNotEmpty && mounted) {
      final existingByPlaceId = await _checkForDuplicateExperienceDialog(
        context: context,
        card: targetCard,
        placeIdToCheck: placeId,
      );

      if (existingByPlaceId != null) {
        provider.updateCardWithExistingExperience(
            targetCard.id, existingByPlaceId);
        return existingByPlaceId;
      }
    }

    // Check for duplicate by venue name
    if (mounted) {
      final existingByName = await _checkForDuplicateExperienceDialog(
        context: context,
        card: targetCard,
        titleToCheck: name,
      );

      if (existingByName != null) {
        provider.updateCardWithExistingExperience(
            targetCard.id, existingByName);
        return existingByName;
      }
    }

    // No duplicate found - fetch full place details if we have a placeId
    Location? location;

    if (placeId != null && placeId.isNotEmpty) {
      try {
        print(
            '🎫 TICKETMASTER FALLBACK: Fetching full place details for $placeId');
        location = await _mapsService.getPlaceDetails(placeId);
        print(
            '🎫 TICKETMASTER FALLBACK: Got place details: ${location.displayName}');
        print(
            '🎫 TICKETMASTER FALLBACK: Photo resource: ${location.photoResourceName}');
      } catch (e) {
        print('🎫 TICKETMASTER FALLBACK: Error fetching place details: $e');
      }
    }

    // Fallback to basic location if place details fetch failed
    location ??= Location(
      placeId: placeId,
      displayName: name,
      address: address,
      city: city,
      state: state,
      latitude: lat,
      longitude: lng,
    );

    targetCard.selectedLocation = location;
    targetCard.locationController.text = location.displayName ?? name;

    // Also set the title to the venue name
    if (targetCard.titleController.text.isEmpty) {
      targetCard.titleController.text = location.displayName ?? name;
      print(
          '🎫 TICKETMASTER FALLBACK: Set title to venue: ${location.displayName ?? name}');
    }

    return null;
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

    if (!await _shouldAutoExtractLocations()) {
      print('🎬 TIKTOK AUTO-EXTRACT: Auto extraction disabled in settings');
      return;
    }

    // Skip if already extracting
    if (_isExtractingLocation) {
      print('🎬 TIKTOK AUTO-EXTRACT: Extraction already in progress');
      return;
    }

    // Mark as processed to prevent duplicate extractions
    _tiktokCaptionsProcessed.add(url);
    final scanSessionId = _startAnalysisSession();

    print('🎬 TIKTOK AUTO-EXTRACT: Starting automatic location extraction...');
    print('🎬 Caption: ${data.title}');
    print('🎬 Author: ${data.authorName}');

    setState(() {
      _isExtractingLocation = true;
      _isAiScanInProgress = true;
      _scanProgress = 0.0;
    });

    // Enable wakelock to prevent screen from sleeping during AI scan
    WakelockPlus.enable();

    // Start foreground service to keep app alive during scan
    await _foregroundScanService.startScanService();
    if (!_isAnalysisSessionActive(scanSessionId)) return;

    try {
      _updateScanProgress(0.1, sessionId: scanSessionId);

      // Get user location for better results (optional)
      LatLng? userLocation;
      if (_currentUserPosition != null) {
        userLocation = LatLng(
          _currentUserPosition!.latitude,
          _currentUserPosition!.longitude,
        );
      }

      _updateScanProgress(0.25, sessionId: scanSessionId);

      // Extract locations from the TikTok caption using quick extraction
      // Deep scan option available in the results dialog if needed
      final locations = await _locationExtractor.extractLocationsFromCaption(
        data.title ?? '',
        platform: 'TikTok',
        userLocation: userLocation,
      );
      if (!_isAnalysisSessionActive(scanSessionId)) return;
      _updateScanProgress(0.8, sessionId: scanSessionId);

      // Check if mounted - if not, store results to apply when app resumes
      if (!mounted) {
        if (locations.isNotEmpty) {
          print(
              '🎬 TIKTOK AUTO-EXTRACT: App backgrounded, storing ${locations.length} result(s) for later');
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
      _updateScanProgress(0.9, sessionId: scanSessionId);

      // Heavy vibration to notify user scan completed
      _heavyVibration();

      final provider = context.read<ReceiveShareProvider>();

      // Always show the location selection dialog, even for single results
      final deepScanRequested = await _handleMultipleExtractedLocations(
        locations,
        provider,
        scannedText: _extractedCaption,
      );
      if (!_isAnalysisSessionActive(scanSessionId)) return;
      _updateScanProgress(1.0, sessionId: scanSessionId);

      // If user requested deep scan, run it after cleanup
      if (deepScanRequested && mounted) {
        _pendingDeepScanProvider = provider;
        _pendingDeepScanEventInfo = null;
      }
    } catch (e) {
      print('❌ TIKTOK AUTO-EXTRACT ERROR: $e');
      if (_isAnalysisSessionActive(scanSessionId)) {
        Fluttertoast.showToast(
          msg: '❌ Scan failed. Please try scanning again.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.red,
        );
      }
    } finally {
      // Disable wakelock and stop foreground service
      WakelockPlus.disable();
      await _foregroundScanService.stopScanService();
      if (_isAnalysisSessionActive(scanSessionId)) {
        setState(() {
          _isExtractingLocation = false;
          _isAiScanInProgress = false;
          _scanProgress = 0.0;
        });
      }
    }

    // Run deep scan if requested (after cleanup is complete)
    if (_isAnalysisSessionActive(scanSessionId) &&
        _pendingDeepScanProvider != null &&
        mounted) {
      final provider = _pendingDeepScanProvider!;
      final eventInfo = _pendingDeepScanEventInfo;
      _pendingDeepScanProvider = null;
      _pendingDeepScanEventInfo = null;
      await _runDeepScan(provider, detectedEventInfo: eventInfo);
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

    if (!await _shouldAutoExtractLocations()) {
      print('📘 FACEBOOK AUTO-EXTRACT: Auto extraction disabled in settings');
      return;
    }

    // Mark as processed to prevent duplicate extractions
    _facebookUrlsProcessed.add(url);
    final scanSessionId = _startAnalysisSession();

    print(
        '📘 FACEBOOK AUTO-EXTRACT: Starting automatic location extraction...');

    setState(() {
      _isExtractingLocation = true;
      _isAiScanInProgress = true;
      _scanProgress = 0.0;
    });

    // Enable wakelock to prevent screen from sleeping during AI scan
    WakelockPlus.enable();

    // Start foreground service to keep app alive during scan
    await _foregroundScanService.startScanService();
    if (!_isAnalysisSessionActive(scanSessionId)) return;

    try {
      _updateScanProgress(0.1, sessionId: scanSessionId);

      // Get user location for better results (optional)
      LatLng? userLocation;
      if (_currentUserPosition != null) {
        userLocation = LatLng(
          _currentUserPosition!.latitude,
          _currentUserPosition!.longitude,
        );
      }

      _updateScanProgress(0.2, sessionId: scanSessionId);

      // Try to extract page content from the Facebook WebView
      String? pageContent;
      final previewKey = _facebookPreviewKeys[url];
      if (previewKey?.currentState != null) {
        try {
          pageContent = await previewKey!.currentState!.extractPageContent();
          if (!_isAnalysisSessionActive(scanSessionId)) return;
        } catch (e) {
          print('⚠️ FACEBOOK AUTO-EXTRACT: Content extraction failed: $e');
        }
      }
      _updateScanProgress(0.35, sessionId: scanSessionId);

      if (pageContent == null ||
          pageContent.isEmpty ||
          pageContent.length < 20) {
        print('⚠️ FACEBOOK AUTO-EXTRACT: No usable content extracted');
        if (mounted) {
          Fluttertoast.showToast(
            msg:
                '💡 No location found in post. Try the "Scan Preview" button to analyze visible text.',
            toastLength: Toast.LENGTH_LONG,
            backgroundColor: Colors.orange[700],
          );
        }
        return;
      }

      print(
          '📘 FACEBOOK AUTO-EXTRACT: Extracted ${pageContent.length} characters');
      print(
          '📘 FACEBOOK AUTO-EXTRACT: Content preview: ${pageContent.substring(0, pageContent.length > 200 ? 200 : pageContent.length)}...');
      _updateScanProgress(0.45, sessionId: scanSessionId);

      // Extract locations using quick extraction
      // Deep scan option available in the results dialog if needed
      final locations = await _locationExtractor.extractLocationsFromCaption(
        pageContent,
        platform: 'Facebook',
        userLocation: userLocation,
      );
      if (!_isAnalysisSessionActive(scanSessionId)) return;
      _updateScanProgress(0.8, sessionId: scanSessionId);

      // Check if mounted - if not, store results to apply when app resumes
      if (!mounted) {
        if (locations.isNotEmpty) {
          print(
              '📘 FACEBOOK AUTO-EXTRACT: App backgrounded, storing ${locations.length} result(s) for later');
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
          msg:
              '💡 No location found in post. Try the "Scan Preview" button to analyze visible text.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.orange[700],
        );
        return;
      }

      print('✅ FACEBOOK AUTO-EXTRACT: Found ${locations.length} location(s)');
      _updateScanProgress(0.9, sessionId: scanSessionId);

      // Heavy vibration to notify user scan completed
      _heavyVibration();

      final provider = context.read<ReceiveShareProvider>();

      // Always show the location selection dialog, even for single results
      final deepScanRequested = await _handleMultipleExtractedLocations(
        locations,
        provider,
        scannedText: pageContent,
      );
      if (!_isAnalysisSessionActive(scanSessionId)) return;
      _updateScanProgress(1.0, sessionId: scanSessionId);

      // If user requested deep scan, run it after cleanup
      if (deepScanRequested && mounted) {
        _pendingDeepScanProvider = provider;
        _pendingDeepScanEventInfo = null;
      }
    } catch (e) {
      print('❌ FACEBOOK AUTO-EXTRACT ERROR: $e');
      if (_isAnalysisSessionActive(scanSessionId)) {
        Fluttertoast.showToast(
          msg: '❌ Scan failed. Please try scanning again.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.red,
        );
      }
    } finally {
      // Disable wakelock and stop foreground service
      WakelockPlus.disable();
      await _foregroundScanService.stopScanService();
      if (_isAnalysisSessionActive(scanSessionId)) {
        setState(() {
          _isExtractingLocation = false;
          _isAiScanInProgress = false;
          _scanProgress = 0.0;
        });
      }
    }

    // Run deep scan if requested (after cleanup is complete)
    if (_isAnalysisSessionActive(scanSessionId) &&
        _pendingDeepScanProvider != null &&
        mounted) {
      final provider = _pendingDeepScanProvider!;
      final eventInfo = _pendingDeepScanEventInfo;
      _pendingDeepScanProvider = null;
      _pendingDeepScanEventInfo = null;
      await _runDeepScan(provider, detectedEventInfo: eventInfo);
    }
  }

  // ============================================================================
  // INSTAGRAM/FACEBOOK OEMBED CONTENT EXTRACTION & AUTO LOCATION EXTRACTION
  // ============================================================================

  /// Extract caption, hashtags, and mentions from an Instagram URL using Meta oEmbed API
  /// AND automatically extract locations from the caption (like TikTok auto-extract)
  ///
  /// This method fetches the post content and parses it into usable components.
  /// The extracted data is stored in:
  /// - [_extractedCaption]: Full caption text
  /// - [_extractedHashtags]: List of hashtags (without #)
  /// - [_extractedMentions]: List of mentions (without @)
  /// - [_extractedFromUrl]: Source URL
  /// - [_extractedFromPlatform]: 'Instagram' or 'Facebook'
  ///
  /// After extraction, automatically triggers location extraction using AI.
  /// Goes directly to WebView extraction (skips oEmbed API since it rarely works for Reels).
  Future<void> _extractInstagramContent(String url) async {
    // Skip if already processed this URL
    if (_instagramUrlsProcessed.contains(url)) {
      print('📸 INSTAGRAM: Already processed $url');
      return;
    }

    print('📸 INSTAGRAM: Scheduling WebView content extraction for $url');

    // Mark as processed to prevent duplicate extractions
    _instagramUrlsProcessed.add(url);

    // Go directly to WebView extraction (oEmbed rarely works for Reels)
    _scheduleInstagramWebViewExtraction(url);
  }

  /// Extract content from Instagram WebView after it loads
  ///
  /// Waits for the WebView to fully render before extracting visible text.
  /// This is more reliable than oEmbed API, especially for Reels.
  void _scheduleInstagramWebViewExtraction(String url) {
    print('📸 INSTAGRAM: Waiting 5 seconds for WebView to load...');

    // Wait for WebView to fully load before attempting extraction
    Future.delayed(const Duration(seconds: 5), () async {
      if (!mounted) return;

      // Skip if we already got caption from somewhere else
      if (_extractedCaption != null && _extractedFromUrl == url) {
        print('📸 INSTAGRAM: Caption already extracted, skipping');
        return;
      }
      final scanSessionId = _analysisSessionId;

      // Yield to the event loop so any pending UI work (e.g. background
      // experience loading or marker generation) can complete first,
      // reducing perceived UI freeze.
      await Future.delayed(Duration.zero);
      if (!mounted) return;

      print('📸 INSTAGRAM: Extracting content from WebView...');

      // Show the "Plendy AI analyzing..." chip immediately so the user sees
      // progress while the WebView content is being extracted.
      if (mounted) {
        setState(() {
          _isAiScanInProgress = true;
          _scanProgress = 0.0;
        });
      }

      // Try to get content from the Instagram preview WebView
      final previewKey = _instagramPreviewKeys[url];
      if (previewKey?.currentState != null) {
        try {
          final content = await previewKey!.currentState!.extractPageContent();
          if (!_isAnalysisSessionActive(scanSessionId)) return;

          if (content != null && content.isNotEmpty && content.length > 20) {
            print(
                '✅ INSTAGRAM: Got content from WebView (${content.length} chars)');

            // Clean up the content - remove boilerplate using dedicated Instagram cleaner
            String caption = _cleanInstagramCaption(content);

            // DEBUG: Log raw vs cleaned content for comparison
            print('📸 INSTAGRAM DEBUG: Raw content (${content.length} chars):');
            print('--- RAW START ---');
            print(content);
            print('--- RAW END ---');
            print(
                '📸 INSTAGRAM DEBUG: Cleaned caption (${caption.length} chars):');
            print('--- CLEANED START ---');
            print(caption);
            print('--- CLEANED END ---');

            if (caption.length > 10) {
              // Always store the caption -- it's useful for the experience card
              // regardless of whether location extraction proceeds here.
              _storeExtractedContent(
                caption: caption,
                sourceUrl: url,
                platform: 'Instagram',
              );

              print('📸 INSTAGRAM: Cleaned caption: ${caption.length} chars');
              print('📸 INSTAGRAM: Hashtags: $_extractedHashtags');
              print('📸 INSTAGRAM: Mentions: $_extractedMentions');

              // Only proceed to Maps grounding if no other extraction is active
              // or already completed for this URL.
              if (_isExtractingLocation || _isProcessingScreenshot) {
                print(
                    '📸 INSTAGRAM: Another extraction in progress, skipping Maps grounding (caption stored)');
                if (_isAnalysisSessionActive(scanSessionId)) {
                  setState(() => _isAiScanInProgress = false);
                }
              } else if (_locationExtractionCompletedUrls.contains(url)) {
                print(
                    '📸 INSTAGRAM: Extraction already completed for this URL, skipping Maps grounding (caption stored)');
                if (_isAnalysisSessionActive(scanSessionId)) {
                  setState(() => _isAiScanInProgress = false);
                }
              } else {
                // _autoExtractWithMapsGrounding sets its own flags and clears
                // _isAiScanInProgress in its finally block.
                print('📸 INSTAGRAM: Using Maps-grounded text extraction...');
                if (!_isAnalysisSessionActive(scanSessionId)) return;
                await _autoExtractWithMapsGrounding(url);
              }
            } else {
              print('⚠️ INSTAGRAM: Caption too short after cleaning');
              if (_isAnalysisSessionActive(scanSessionId)) {
                setState(() => _isAiScanInProgress = false);
              }
            }
          } else {
            print('⚠️ INSTAGRAM: No useful content in WebView');
            if (_isAnalysisSessionActive(scanSessionId)) {
              setState(() => _isAiScanInProgress = false);
            }
          }
        } catch (e) {
          print('❌ INSTAGRAM EXTRACT ERROR: $e');
          if (_isAnalysisSessionActive(scanSessionId)) {
            setState(() => _isAiScanInProgress = false);
          }
        }
      } else {
        print('⚠️ INSTAGRAM: No preview widget available yet');
        if (_isAnalysisSessionActive(scanSessionId)) {
          setState(() => _isAiScanInProgress = false);
        }
      }
    });
  }

  /// Clean Instagram caption by removing UI boilerplate and formatting nicely
  ///
  /// Instagram WebView content often includes lots of UI text like:
  /// - "username and otheraccount Original audio View profile" (Reels)
  /// - "username and otheraccount Location Name Verified N," (Photo posts with location)
  /// - "Verified NNN posts · NNNK followers View more on Instagram"
  /// - "Like Comment Share Save NNN"
  /// - "View all NNN comments Add a comment... Instagram"
  ///
  /// The MOST RELIABLE pattern is that the username appears TWICE consecutively
  /// right before the actual caption text: "{username} {username} {caption}"
  ///
  /// This extracts just the username and actual caption content.
  String _cleanInstagramCaption(String rawContent) {
    String content = rawContent;

    // Extract username from the beginning (first word is usually the poster's username)
    // Handle case where content might already have a dash (from previous processing)
    final firstWord = content.split(RegExp(r'[\s\-]+')).first;
    final username = firstWord.replaceAll(RegExp(r'[^a-zA-Z0-9._]'), '');

    if (username.isEmpty) {
      return content;
    }

    // MOST RELIABLE: Find the LAST occurrence of "{username} {username}"
    // This pattern appears right before the actual caption in almost all Instagram posts
    final doubleUsernamePattern = RegExp(
      RegExp.escape(username) + r'\s+' + RegExp.escape(username) + r'\s+',
      caseSensitive: false,
    );

    // Find ALL matches and use the LAST one (closest to the actual caption)
    final allMatches = doubleUsernamePattern.allMatches(content).toList();
    if (allMatches.isNotEmpty) {
      final lastMatch = allMatches.last;
      String captionText = content.substring(lastMatch.end).trim();
      captionText = _removeInstagramTrailingUI(captionText);

      // Remove any duplicate username at the start of caption if still present
      while (captionText.startsWith(username)) {
        captionText = captionText.substring(username.length).trim();
      }

      if (captionText.isNotEmpty) {
        return '$username - $captionText';
      }
    }

    // FALLBACK: Try other patterns if double-username wasn't found
    final captionStartPatterns = [
      // Match: "Save NNN, username caption" (engagement count before username)
      RegExp(r'Save\s+[\d,]+\s+likes?\s*' + RegExp.escape(username) + r'\s+',
          caseSensitive: false),
      RegExp(r'Save\s+[\d,]+\s*' + RegExp.escape(username) + r'\s+',
          caseSensitive: false),
      // Match: "Location Name Verified N, username caption" (Photo posts with tagged location)
      RegExp(r'Verified\s+[\d,]+\s*' + RegExp.escape(username) + r'\s+',
          caseSensitive: false),
    ];

    String? captionText;
    for (final pattern in captionStartPatterns) {
      final match = pattern.firstMatch(content);
      if (match != null) {
        captionText = content.substring(match.end).trim();
        break;
      }
    }

    // Clean up trailing Instagram UI elements from the caption
    if (captionText != null && captionText.isNotEmpty) {
      captionText = _removeInstagramTrailingUI(captionText);

      // Remove duplicate username at the start of caption if present
      while (captionText != null && captionText.startsWith(username)) {
        captionText = captionText.substring(username.length).trim();
      }

      if (captionText != null && captionText.isNotEmpty) {
        return '$username - $captionText';
      }
    }

    // Fallback: Remove known UI patterns and return cleaned content
    content = content
        // Remove audio info for Reels (Original audio format)
        .replaceAll(
            RegExp(r'\s+and\s+\w+\s+Original audio', caseSensitive: false), '')
        .replaceAll(RegExp(r'Original audio', caseSensitive: false), '')
        // Remove music info for Reels (Artist · Song Title Watch on Instagram)
        .replaceAll(
            RegExp(r"Verified\s+[\w\s]+·[^W]+Watch on Instagram",
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(r"[\w\s]+·[^W]+Watch on Instagram", caseSensitive: false),
            '')
        .replaceAll(RegExp(r'Watch on Instagram', caseSensitive: false), '')
        // Remove tagged accounts and locations before caption
        .replaceAll(
            RegExp(r'\s+and\s+\w+\s+[\w\s]+Verified\s+\d+,?',
                caseSensitive: false),
            '')
        // Remove profile view patterns
        .replaceAll(RegExp(r'View profile\s+\w+', caseSensitive: false), '')
        .replaceAll(RegExp(r'View profile', caseSensitive: false), '')
        // Remove verified badge and stats
        .replaceAll(
            RegExp(r'Verified\s+\d+\s+posts\s+·\s+[\d.]+[KMB]?\s+followers',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(r'\d+\s+posts\s+·\s+[\d.]+[KMB]?\s+followers',
                caseSensitive: false),
            '')
        // Remove "View more on Instagram"
        .replaceAll(RegExp(r'View more on Instagram', caseSensitive: false), '')
        // Remove action buttons
        .replaceAll(
            RegExp(r'Like\s+Comment\s+Share\s+Save\s*\d*,?',
                caseSensitive: false),
            '')
        // Remove "View this post/reel on Instagram"
        .replaceAll(
            RegExp(r'View this (post|reel) on Instagram', caseSensitive: false),
            '')
        // Remove "A post/reel shared by..." footer
        .replaceAll(
            RegExp(r'A (post|reel) shared by.*$',
                caseSensitive: false, dotAll: true),
            '')
        // Remove engagement metrics
        .replaceAll(RegExp(r'liked by.*and.*others', caseSensitive: false), '')
        .replaceAll(RegExp(r'\d+\s+likes', caseSensitive: false), '')
        // Remove login prompts
        .replaceAll(RegExp(r'Log in', caseSensitive: false), '')
        .replaceAll(RegExp(r'Sign up', caseSensitive: false), '')
        // Clean up whitespace
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Remove trailing UI elements
    content = _removeInstagramTrailingUI(content);

    // If we have a clean content that starts with username, format it nicely
    if (content.startsWith(username) && content.length > username.length + 5) {
      final afterUsername = content.substring(username.length).trim();
      if (!afterUsername.startsWith('-')) {
        return '$username - $afterUsername';
      }
    }

    return content;
  }

  /// Remove trailing Instagram UI elements like comments section
  String _removeInstagramTrailingUI(String text) {
    return text
        // Remove "View all NNN comments Add a comment... Instagram"
        .replaceAll(
            RegExp(r'\s*View all \d+ comments.*$',
                caseSensitive: false, dotAll: true),
            '')
        // Remove "Add a comment... Instagram" without view all
        .replaceAll(
            RegExp(r'\s*Add a comment\.{0,3}\s*Instagram\s*$',
                caseSensitive: false),
            '')
        // Remove trailing "Instagram" label
        .replaceAll(RegExp(r'\s+Instagram\s*$', caseSensitive: false), '')
        .trim();
  }

  /// Extract caption, hashtags, and mentions from a Facebook URL using Meta oEmbed API
  /// AND automatically extract locations from the caption (like TikTok auto-extract)
  ///
  /// This method fetches the post content and parses it into usable components.
  Future<void> _extractFacebookContent(String url) async {
    // Skip if already processed this URL for content extraction
    // Note: _facebookUrlsProcessed is used for WebView-based extraction,
    // this uses oEmbed API which is faster and more reliable
    if (_extractedFromUrl == url && _extractedFromPlatform == 'Facebook') {
      print('📘 FACEBOOK OEMBED: Already extracted content from $url');
      return;
    }

    print('📘 FACEBOOK OEMBED: Extracting content from $url');

    try {
      final oembedService = FacebookOEmbedService();

      if (!oembedService.isConfigured) {
        print(
            '⚠️ FACEBOOK OEMBED: Service not configured (missing Facebook App credentials)');
        return;
      }

      // Fetch oEmbed data
      final oembedData = await oembedService.getOEmbedData(url);

      if (oembedData != null && oembedData['html'] != null) {
        // Extract text from the HTML response
        final html = oembedData['html'] as String;
        final caption = oembedService.extractTextFromHtml(html);

        if (caption != null && caption.isNotEmpty) {
          print('✅ FACEBOOK OEMBED: Got caption (${caption.length} chars)');

          // Parse and store the extracted content
          _storeExtractedContent(
            caption: caption,
            sourceUrl: url,
            platform: 'Facebook',
          );

          print(
              '📘 FACEBOOK OEMBED: Extracted ${_extractedHashtags.length} hashtags, ${_extractedMentions.length} mentions');

          // Mark as processed to prevent duplicate WebView-based extraction
          _facebookUrlsProcessed.add(url);

          // Automatically extract locations from the caption (like TikTok)
          await _autoExtractLocationsFromCaption(
            caption: caption,
            platform: 'Facebook',
            sourceUrl: url,
          );
        } else {
          print('⚠️ FACEBOOK OEMBED: No text found in post HTML');
        }
      } else {
        print('⚠️ FACEBOOK OEMBED: No oEmbed data returned');
      }
    } catch (e) {
      print('❌ FACEBOOK OEMBED ERROR: $e');
    }
  }

  /// Auto-extract locations from caption text using AI (same flow as TikTok)
  ///
  /// This method:
  /// 1. Shows scan progress UI
  /// 2. Uses LinkLocationExtractionService to extract locations via AI + Places API
  /// 3. Handles single/multiple location results
  /// 4. Shows toast notifications for status
  Future<void> _autoExtractLocationsFromCaption({
    required String caption,
    required String platform,
    required String sourceUrl,
  }) async {
    // Skip if caption is too short to be useful
    if (caption.length < 10) {
      print('📍 $platform AUTO-EXTRACT: Caption too short to analyze');
      return;
    }

    // Skip if already extracting
    if (_isExtractingLocation || _isProcessingScreenshot) {
      print('📍 $platform AUTO-EXTRACT: Extraction already in progress');
      return;
    }

    if (!await _shouldAutoExtractLocations()) {
      print('📍 $platform AUTO-EXTRACT: Auto extraction disabled in settings');
      return;
    }

    print(
        '📍 $platform AUTO-EXTRACT: Starting automatic location extraction from oEmbed caption...');
    print(
        '📍 Caption preview: ${caption.substring(0, caption.length > 100 ? 100 : caption.length)}...');
    final scanSessionId = _startAnalysisSession();

    setState(() {
      _isExtractingLocation = true;
      _isAiScanInProgress = true;
      _scanProgress = 0.0;
    });

    // Enable wakelock to prevent screen from sleeping during AI scan
    WakelockPlus.enable();

    // Start foreground service to keep app alive during scan
    await _foregroundScanService.startScanService();
    if (!_isAnalysisSessionActive(scanSessionId)) return;

    try {
      _updateScanProgress(0.1, sessionId: scanSessionId);

      // Get user location for better results (optional)
      LatLng? userLocation;
      if (_currentUserPosition != null) {
        userLocation = LatLng(
          _currentUserPosition!.latitude,
          _currentUserPosition!.longitude,
        );
      }

      _updateScanProgress(0.25, sessionId: scanSessionId);

      // Extract locations using quick extraction
      // Deep scan option available in the results dialog if needed
      final locations = await _locationExtractor.extractLocationsFromCaption(
        caption,
        platform: platform,
        userLocation: userLocation,
      );
      if (!_isAnalysisSessionActive(scanSessionId)) return;
      _updateScanProgress(0.8, sessionId: scanSessionId);

      // Check if mounted - if not, store results to apply when app resumes
      if (!mounted) {
        if (locations.isNotEmpty) {
          print(
              '📍 $platform AUTO-EXTRACT: App backgrounded, storing ${locations.length} result(s) for later');
          _pendingScanResults = locations;
          if (locations.length == 1) {
            _pendingScanSingleMessage = '📍 Found: ${locations.first.name}';
          }
        }
        return;
      }

      if (locations.isEmpty) {
        print('⚠️ $platform AUTO-EXTRACT: No locations found in caption');
        Fluttertoast.showToast(
          msg:
              '💡 No location found in caption. Try the "Scan Preview" button to analyze visible text.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.orange[700],
        );
        return;
      }

      print('✅ $platform AUTO-EXTRACT: Found ${locations.length} location(s)');
      _updateScanProgress(0.85, sessionId: scanSessionId);

      // Try to detect event information from the caption
      final detectedEvent = await _detectEventFromTextAsync(caption);
      if (!_isAnalysisSessionActive(scanSessionId)) return;
      _updateScanProgress(0.95, sessionId: scanSessionId);

      // Heavy vibration to notify user scan completed
      _heavyVibration();

      final provider = context.read<ReceiveShareProvider>();

      // Always show the location selection dialog, even for single results
      // If event info was detected, the dialog will show a second page for event designation
      final deepScanRequested = await _handleMultipleExtractedLocations(
        locations,
        provider,
        detectedEventInfo: detectedEvent,
        scannedText: caption,
      );
      if (!_isAnalysisSessionActive(scanSessionId)) return;
      _updateScanProgress(1.0, sessionId: scanSessionId);

      // If user requested deep scan, run it after cleanup
      if (deepScanRequested && mounted) {
        _pendingDeepScanProvider = provider;
        _pendingDeepScanEventInfo = detectedEvent;
      }
    } catch (e) {
      print('❌ $platform AUTO-EXTRACT ERROR: $e');
      if (_isAnalysisSessionActive(scanSessionId)) {
        Fluttertoast.showToast(
          msg: '❌ Location scan failed. Try the "Scan Preview" button.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.red,
        );
      }
    } finally {
      // Disable wakelock and stop foreground service
      WakelockPlus.disable();
      await _foregroundScanService.stopScanService();
      if (_isAnalysisSessionActive(scanSessionId)) {
        setState(() {
          _isExtractingLocation = false;
          _isAiScanInProgress = false;
          _scanProgress = 0.0;
        });
      }
    }

    // Run deep scan if requested (after cleanup is complete)
    if (_isAnalysisSessionActive(scanSessionId) &&
        _pendingDeepScanProvider != null &&
        mounted) {
      final provider = _pendingDeepScanProvider!;
      final eventInfo = _pendingDeepScanEventInfo;
      _pendingDeepScanProvider = null;
      _pendingDeepScanEventInfo = null;
      await _runDeepScan(provider, detectedEventInfo: eventInfo);
    }
  }

  /// Auto-extract locations using Gemini with Maps grounding (no city context bias)
  ///
  /// This method uses the same approach as Preview Scan's text extraction path:
  /// - Extracts page text from WebView
  /// - Sends to Gemini with Google Maps grounding enabled
  /// - Returns locations with verified placeIds and coordinates
  ///
  /// Unlike [_autoExtractLocationsFromCaption], this does NOT detect city context
  /// from the caption and apply it to all searches, which avoids incorrect results
  /// when locations are not in the detected city.
  Future<void> _autoExtractWithMapsGrounding(String sourceUrl) async {
    // Skip if already extracting
    if (_isExtractingLocation || _isProcessingScreenshot) {
      print('📍 MAPS GROUNDING: Extraction already in progress');
      return;
    }

    if (!await _shouldAutoExtractLocations()) {
      print('📍 MAPS GROUNDING: Auto extraction disabled in settings');
      return;
    }

    // Use the already-extracted caption (stored by _storeExtractedContent)
    // Don't try to re-extract from WebView as that often fails for Instagram reels
    if (_extractedCaption == null || _extractedCaption!.isEmpty) {
      print('⚠️ MAPS GROUNDING: No caption available to analyze');
      Fluttertoast.showToast(
        msg: '💡 No caption found. Try the "Scan Preview" button.',
        toastLength: Toast.LENGTH_LONG,
        backgroundColor: Colors.orange[700],
      );
      return;
    }

    print(
        '📍 MAPS GROUNDING: Starting location extraction with Maps grounding...');
    print(
        '📍 MAPS GROUNDING: Using pre-extracted caption (${_extractedCaption!.length} chars)');
    final scanSessionId = _startAnalysisSession();

    setState(() {
      _isExtractingLocation = true;
      _isAiScanInProgress = true;
      _scanProgress = 0.0;
    });

    // Enable wakelock to prevent screen from sleeping during AI scan
    WakelockPlus.enable();

    // Start foreground service to keep app alive during scan
    await _foregroundScanService.startScanService();
    if (!_isAnalysisSessionActive(scanSessionId)) return;

    try {
      _updateScanProgress(0.1, sessionId: scanSessionId);

      // Get user location for better results (optional)
      LatLng? userLocation;
      if (_currentUserPosition != null) {
        userLocation = LatLng(
          _currentUserPosition!.latitude,
          _currentUserPosition!.longitude,
        );
      }

      _updateScanProgress(0.2, sessionId: scanSessionId);

      // Check if user prefers deep scan for auto-extraction
      final useDeepScan = await _shouldUseDeepScan();
      if (!_isAnalysisSessionActive(scanSessionId)) return;

      List<ExtractedLocationData> locations;
      bool isDeepScanResult = false;

      if (useDeepScan) {
        // ========== USE DEEP EXTRACTION ==========
        // More thorough analysis using unified extraction
        print('📍 AUTO SCAN: Using deep extraction (user preference)...');

        final unifiedResult =
            await _locationExtractor.extractLocationsFromTextUnified(
          _extractedCaption!,
          userLocation: userLocation,
          onProgress: (current, total, message) {
            // Map progress from 0.2 to 0.8
            _updateScanProgress(0.2 + (0.6 * current / total),
                sessionId: scanSessionId);
          },
        );
        if (!_isAnalysisSessionActive(scanSessionId)) return;
        locations = unifiedResult.locations;
        isDeepScanResult = true;
      } else {
        // ========== USE QUICK EXTRACTION ==========
        // Fast extraction using Gemini's Maps grounding directly
        // Deep scan option available in the results dialog if needed
        print('📍 AUTO SCAN: Using quick extraction...');

        locations = await _locationExtractor.extractLocationsFromCaption(
          _extractedCaption!,
          platform: 'social media',
          userLocation: userLocation,
        );
        if (!_isAnalysisSessionActive(scanSessionId)) return;
      }
      _updateScanProgress(0.8, sessionId: scanSessionId);

      // Check if mounted - if not, store results to apply when app resumes
      if (!mounted) {
        if (locations.isNotEmpty) {
          print(
              '📍 AUTO SCAN: App backgrounded, storing ${locations.length} result(s) for later');
          _pendingScanResults = locations;
          if (locations.length == 1) {
            _pendingScanSingleMessage = '📍 Found: ${locations.first.name}';
          }
        }
        return;
      }

      if (locations.isEmpty) {
        print(
            '⚠️ AUTO SCAN: No locations found - showing dialog with Deep Scan option');
      } else {
        final scanType = useDeepScan ? 'deep' : 'quick';
        print(
            '✅ AUTO SCAN: Found ${locations.length} location(s) via $scanType extraction');
      }
      _updateScanProgress(0.85, sessionId: scanSessionId);

      // Try to detect event information from the extracted caption
      ExtractedEventInfo? detectedEvent;
      if (_extractedCaption != null && _extractedCaption!.isNotEmpty) {
        detectedEvent = await _detectEventFromTextAsync(_extractedCaption!);
        if (!_isAnalysisSessionActive(scanSessionId)) return;
      }
      _updateScanProgress(0.95, sessionId: scanSessionId);

      // Heavy vibration to notify user scan completed
      _heavyVibration();

      final provider = context.read<ReceiveShareProvider>();

      // Always show the location selection dialog
      // If we already did a deep scan, hide the deep scan option in the dialog
      final deepScanRequested = await _handleMultipleExtractedLocations(
        locations,
        provider,
        detectedEventInfo: detectedEvent,
        scannedText: _extractedCaption,
        isDeepScan: isDeepScanResult,
      );
      if (!_isAnalysisSessionActive(scanSessionId)) return;
      _updateScanProgress(1.0, sessionId: scanSessionId);

      // If user requested deep scan, run it after cleanup (only if we didn't already do deep scan)
      print(
          '🔍 MAPS GROUNDING: deepScanRequested=$deepScanRequested, mounted=$mounted, isDeepScanResult=$isDeepScanResult');
      if (deepScanRequested && mounted && !isDeepScanResult) {
        // Store provider and event info for use after finally block
        print('🔍 MAPS GROUNDING: Setting _pendingDeepScanProvider');
        _pendingDeepScanProvider = provider;
        _pendingDeepScanEventInfo = detectedEvent;
      }
    } catch (e) {
      print('❌ MAPS GROUNDING ERROR: $e');
      if (_isAnalysisSessionActive(scanSessionId)) {
        Fluttertoast.showToast(
          msg: '❌ Location scan failed. Try the "Scan Preview" button.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.red,
        );
      }
    } finally {
      // Disable wakelock and stop foreground service
      print('🔍 MAPS GROUNDING: Finally block - cleaning up');
      _locationExtractionCompletedUrls.add(sourceUrl);
      WakelockPlus.disable();
      await _foregroundScanService.stopScanService();
      if (_isAnalysisSessionActive(scanSessionId)) {
        setState(() {
          _isExtractingLocation = false;
          _isAiScanInProgress = false;
          _scanProgress = 0.0;
        });
      }
      print(
          '🔍 MAPS GROUNDING: Finally block complete, _pendingDeepScanProvider=${_pendingDeepScanProvider != null}');
    }

    // Run deep scan if requested (after cleanup is complete)
    print(
        '🔍 MAPS GROUNDING: After finally - _pendingDeepScanProvider=${_pendingDeepScanProvider != null}, mounted=$mounted');
    if (_isAnalysisSessionActive(scanSessionId) &&
        _pendingDeepScanProvider != null &&
        mounted) {
      print('🔍 MAPS GROUNDING: Starting deep scan...');
      final provider = _pendingDeepScanProvider!;
      final eventInfo = _pendingDeepScanEventInfo;
      _pendingDeepScanProvider = null;
      _pendingDeepScanEventInfo = null;
      await _runDeepScan(provider, detectedEventInfo: eventInfo);
    } else {
      print(
          '🔍 MAPS GROUNDING: NOT starting deep scan - provider null or not mounted');
    }
  }

  /// Store extracted content and parse hashtags/mentions from caption
  void _storeExtractedContent({
    required String caption,
    required String sourceUrl,
    required String platform,
  }) {
    setState(() {
      _extractedCaption = caption;
      _extractedFromUrl = sourceUrl;
      _extractedFromPlatform = platform;
      _extractedHashtags = _parseHashtags(caption);
      _extractedMentions = _parseMentions(caption);
    });
  }

  /// Parse hashtags from text (returns list without # prefix)
  ///
  /// Example: "#pizza #nyc #foodie" → ["pizza", "nyc", "foodie"]
  List<String> _parseHashtags(String text) {
    final hashtagRegex = RegExp(r'#(\w+)', unicode: true);
    final matches = hashtagRegex.allMatches(text);
    return matches
        .map((match) => match.group(1)!)
        .where((tag) => tag.isNotEmpty)
        .toList();
  }

  /// Parse mentions from text (returns list without @ prefix)
  ///
  /// Example: "@foodblogger @chef_joe" → ["foodblogger", "chef_joe"]
  List<String> _parseMentions(String text) {
    final mentionRegex = RegExp(r'@([\w.]+)', unicode: true);
    final matches = mentionRegex.allMatches(text);
    return matches
        .map((match) => match.group(1)!)
        .where((mention) => mention.isNotEmpty)
        .toList();
  }

  /// Clear extracted social media content
  /// Call this when processing new shared content
  void _clearExtractedSocialContent() {
    setState(() {
      _extractedCaption = null;
      _extractedHashtags = [];
      _extractedMentions = [];
      _extractedFromUrl = null;
      _extractedFromPlatform = null;
    });
  }

  /// Get the extracted content as a structured map
  /// Useful for passing to other methods or services
  Map<String, dynamic> getExtractedSocialContent() {
    return {
      'caption': _extractedCaption,
      'hashtags': _extractedHashtags,
      'mentions': _extractedMentions,
      'sourceUrl': _extractedFromUrl,
      'platform': _extractedFromPlatform,
      'hasContent': _extractedCaption != null && _extractedCaption!.isNotEmpty,
    };
  }

  /// Check if we have extracted social content available
  bool get hasExtractedSocialContent =>
      _extractedCaption != null && _extractedCaption!.isNotEmpty;

  /// Auto-extract content when Instagram/Facebook URL is detected
  /// Called from _processSharedContent when social media URLs are found
  Future<void> _autoExtractSocialMediaContent(String url) async {
    if (_isInstagramUrl(url)) {
      await _extractInstagramContent(url);
    } else if (_isFacebookUrl(url)) {
      await _extractFacebookContent(url);
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
            backgroundColor: AppColors.backgroundColorDark,
            title: const Text('Already Saved'),
            content: Text(
                'You already have "${existingExperience.name}" saved at "${existingExperience.location.address ?? 'No address'}". Would you like to use this existing experience?'),
            actions: <Widget>[
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.backgroundColorDark,
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
  /// If [detectedEventInfo] is provided, the dialog will show a second page
  /// for the user to select which locations should be designated as events.
  /// If [isDeepScan] is true, the deep scan option will not be shown in the dialog.
  /// If [scannedText] is provided, it will be shown in an expandable section.
  /// If no scannedText is provided, a fallback is built from location originalQuery fields.
  /// Returns true if the user requested a deep scan (caller should handle running it).
  Future<bool> _handleMultipleExtractedLocations(
    List<ExtractedLocationData> locations,
    ReceiveShareProvider provider, {
    ExtractedEventInfo? detectedEventInfo,
    bool isDeepScan = false,
    String? scannedText,
  }) async {
    // Build fallback scanned text from location originalQuery fields if not provided
    // This ensures ALL Locations Found dialogs show original text for user verification
    final effectiveScannedText = scannedText?.isNotEmpty == true
        ? scannedText
        : _buildScannedTextFallback(locations);

    // Sort locations by order of appearance in the scanned text
    // This ensures the dialog shows locations in the same order as the original content
    final sortedLocations =
        _sortLocationsByTextAppearance(locations, effectiveScannedText);

    // Check for duplicates before showing dialog (using sorted list)
    final duplicates = await _checkLocationsForDuplicates(sortedLocations);

    if (!mounted) return false;

    // Show dialog with selectable checklist (including duplicate info)
    // If event info is detected, the dialog will show a second page for event designation
    _pauseHelpForDialog();
    final result = await showDialog<_MultiLocationSelectionResult>(
      context: context,
      builder: (dialogContext) => _MultiLocationSelectionDialog(
        locations: sortedLocations,
        duplicates: duplicates,
        detectedEventInfo: detectedEventInfo,
        isDeepScan: isDeepScan,
        onDeepScanRequested: isDeepScan
            ? null
            : () {}, // Placeholder, not used - result handles this
        scannedText: effectiveScannedText,
      ),
    );
    _resumeHelpAfterDialog();

    // Check if user requested deep scan
    if (result?.deepScanRequested == true) {
      // Store confirmed locations from quick scan to preserve during deep scan
      // These are locations the user has already selected/verified as correct
      if (result!.selectedLocations.isNotEmpty) {
        _pendingDeepScanConfirmedLocations = result.selectedLocations;
        print(
            '📍 DEEP SCAN: Preserving ${result.selectedLocations.length} confirmed location(s) from quick scan');
      } else {
        _pendingDeepScanConfirmedLocations = null;
      }
      // Store the scanned text content for deep scan to use
      // This is important for Facebook, TikTok, Instagram etc. where content comes from WebView
      if (effectiveScannedText != null && effectiveScannedText.isNotEmpty) {
        _extractedCaption = effectiveScannedText;
        print(
            '📍 DEEP SCAN: Preserving scanned text (${effectiveScannedText.length} chars) for deep scan');
      }
      return true; // Caller should run deep scan AFTER cleanup
    }

    // Handle the result (which now includes both locations and their duplicate info)
    final selectedLocations = result?.selectedLocations;
    final selectedDuplicates = result?.selectedDuplicates;

    // Store event info for use after successful save
    if (result?.eventInfo != null) {
      _detectedEventInfo = result!.eventInfo;
      print(
          '📅 EVENT: Detected event info stored for post-save handling: ${_detectedEventInfo?.eventName ?? 'Event'}');
    }

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

      // Find 'Want to go' color category to auto-assign to new locations
      final wantToGoCategory = _userColorCategories.firstWhereOrNull(
        (cat) => cat.name.toLowerCase() == 'want to go',
      );
      final String? wantToGoColorCategoryId = wantToGoCategory?.id;

      // Check if auto-set categories is enabled
      final shouldAutoSetCategories =
          await _aiSettingsService.shouldAutoSetCategories();

      // Set categorizing state if auto-set categories is enabled
      if (shouldAutoSetCategories && mounted) {
        setState(() {
          _isCategorizing = true;
        });
      }

      // Fill existing empty cards with new locations
      for (int i = 0; i < locationsForEmptyCards.length; i++) {
        final locationData = locationsForEmptyCards[i];
        final cardId = emptyCards[i].id;

        provider.updateCardWithExtractedLocation(cardId, locationData);

        // Auto-set categories only if enabled in settings
        if (shouldAutoSetCategories) {
          // Set color category to 'Want to go' for new locations (not from saved experiences)
          if (wantToGoColorCategoryId != null) {
            provider.updateCardColorCategory(cardId, wantToGoColorCategoryId);
          }

          // Determine and set the best primary category based on place types
          final bestCategoryId = await _determineBestCategoryForLocation(
            locationData,
            _userCategories,
            useAiFallback: true, // Use AI if no direct match found
          );
          if (bestCategoryId != null) {
            provider.updateCardTextCategory(cardId, bestCategoryId);
          }
        }

        print('📍 Filled existing card with: ${locationData.name}');
      }

      // Create all new cards for remaining new locations in one batch
      if (locationsNeedingNewCards.isNotEmpty) {
        // Track the number of cards before creation to identify newly created ones
        final cardCountBefore = provider.experienceCards.length;
        await provider.createCardsFromLocations(locationsNeedingNewCards);
        cardsCreated += locationsNeedingNewCards.length;
        print(
            '📍 Created ${locationsNeedingNewCards.length} new cards for new locations');

        // Set color category and primary category for all newly created cards (only if enabled)
        if (shouldAutoSetCategories) {
          for (int i = 0; i < locationsNeedingNewCards.length; i++) {
            final cardIndex = cardCountBefore + i;
            if (cardIndex < provider.experienceCards.length) {
              final cardId = provider.experienceCards[cardIndex].id;
              final locationData = locationsNeedingNewCards[i];

              // Set color category to 'Want to go'
              if (wantToGoColorCategoryId != null) {
                provider.updateCardColorCategory(
                    cardId, wantToGoColorCategoryId);
              }

              // Determine and set the best primary category based on place types
              final bestCategoryId = await _determineBestCategoryForLocation(
                locationData,
                _userCategories,
                useAiFallback: true, // Use AI if no direct match found
              );
              if (bestCategoryId != null) {
                provider.updateCardTextCategory(cardId, bestCategoryId);
              }
            }
          }
        }
      }

      // Reset categorizing state
      if (mounted && _isCategorizing) {
        setState(() {
          _isCategorizing = false;
        });
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

      // Force UI rebuild after all category changes
      // (provider notifyListeners doesn't trigger rebuild because _ExperienceCardsSection doesn't watch the provider)
      if (mounted) {
        setState(() {});
      }

      // Show appropriate toast message
      if (existingUsed > 0 && newLocations.isNotEmpty) {
        Fluttertoast.showToast(
          msg:
              '📍 ${newLocations.length} new + $existingUsed existing experience${existingUsed > 1 ? 's' : ''} added',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.blue,
        );
      } else if (existingUsed > 0) {
        Fluttertoast.showToast(
          msg:
              '📍 Using $existingUsed existing experience${existingUsed > 1 ? 's' : ''}',
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

      // Scroll to the top-most experience card after a brief delay for UI to update
      _scrollToExperienceCardsTop();
    }

    return false; // No deep scan requested
  }

  /// Run deep scan using unified extraction (more accurate but slower)
  /// This is called when user requests deep scan from the quick scan results dialog
  Future<void> _runDeepScan(
    ReceiveShareProvider provider, {
    ExtractedEventInfo? detectedEventInfo,
  }) async {
    // Make sure widget is still mounted
    if (!mounted) return;
    final scanSessionId = _startAnalysisSession();

    // For YouTube URLs, the analyzed content is stored in lastAnalyzedContent, not _extractedCaption
    // Use lastAnalyzedContent as fallback if _extractedCaption is empty
    final contentToScan = (_extractedCaption?.isNotEmpty == true)
        ? _extractedCaption
        : _locationExtractor.lastAnalyzedContent;

    // Make sure we have caption text to scan
    if (contentToScan == null || contentToScan.isEmpty) {
      print(
          '🔍 DEEP SCAN: No content to scan - _extractedCaption=${_extractedCaption?.length ?? 0}, lastAnalyzedContent=${_locationExtractor.lastAnalyzedContent?.length ?? 0}');
      Fluttertoast.showToast(
        msg: '❌ No content to scan. Please try again.',
        toastLength: Toast.LENGTH_LONG,
        backgroundColor: Colors.red,
      );
      return;
    }

    print(
        '🔍 DEEP SCAN: Content to scan length: ${contentToScan.length} chars');

    // Get confirmed locations from quick scan (user-verified correct locations)
    final confirmedLocations = _pendingDeepScanConfirmedLocations;
    _pendingDeepScanConfirmedLocations = null; // Clear after retrieval

    // Build set of confirmed place IDs for efficient deduplication after scan
    final confirmedPlaceIds = <String>{};
    // Build set of confirmed ORIGINAL QUERY NAMES to skip verification during scan
    // IMPORTANT: Use originalQuery (e.g., "Lovesong") not the verified name (e.g., "Lovesong Coffee + Market")
    // because Gemini will extract the original text from the caption, not the verified name
    final confirmedOriginalQueries = <String>{};
    if (confirmedLocations != null) {
      for (final loc in confirmedLocations) {
        // PRIORITY: Use originalQuery (the original extracted text from caption)
        // This matches what Gemini will extract during deep scan
        if (loc.originalQuery != null && loc.originalQuery!.isNotEmpty) {
          confirmedOriginalQueries.add(loc.originalQuery!);
        } else if (loc.name.isNotEmpty) {
          // Fallback to verified name if no originalQuery
          confirmedOriginalQueries.add(loc.name);
        }
        // Add placeId for post-scan deduplication
        if (loc.placeId != null && loc.placeId!.isNotEmpty) {
          // Handle 'places/' prefix that may come from grounding chunks
          final cleanPlaceId = loc.placeId!.startsWith('places/')
              ? loc.placeId!.substring(7)
              : loc.placeId!;
          confirmedPlaceIds.add(cleanPlaceId);
        }
      }
      print(
          '📍 DEEP SCAN: Will preserve ${confirmedLocations.length} confirmed location(s)');
      print(
          '📍 DEEP SCAN: Will skip verification for ${confirmedOriginalQueries.length} original query(s): ${confirmedOriginalQueries.take(5).join(", ")}${confirmedOriginalQueries.length > 5 ? "..." : ""}');
    }

    try {
      // Show scanning indicator
      if (mounted) {
        setState(() {
          _isExtractingLocation = true;
          _isAiScanInProgress = true;
          _scanProgress = 0.0;
        });
      }

      // Enable wakelock to prevent screen from sleeping during deep scan
      WakelockPlus.enable();
      await _foregroundScanService.startScanService();
      if (!_isAnalysisSessionActive(scanSessionId)) return;

      print('🔍 DEEP SCAN: Starting unified extraction...');
      _updateScanProgress(0.1, sessionId: scanSessionId);

      // Get user location for better results
      LatLng? userLocation;
      if (_currentUserPosition != null) {
        userLocation = LatLng(
          _currentUserPosition!.latitude,
          _currentUserPosition!.longitude,
        );
      }

      _updateScanProgress(0.2, sessionId: scanSessionId);

      // Run unified extraction (deep scan)
      // Pass confirmed location names to skip verification for those locations
      // This saves Gemini API calls for locations user has already confirmed
      final unifiedResult =
          await _locationExtractor.extractLocationsFromTextUnified(
        contentToScan,
        userLocation: userLocation,
        onProgress: (current, total, message) {
          // Map progress from 0.2 to 0.8
          _updateScanProgress(0.2 + (0.6 * current / total),
              sessionId: scanSessionId);
        },
        skipLocationNames: confirmedOriginalQueries.isNotEmpty
            ? confirmedOriginalQueries
            : null,
      );
      if (!_isAnalysisSessionActive(scanSessionId)) return;

      var deepScanLocations = unifiedResult.locations;
      _updateScanProgress(0.8, sessionId: scanSessionId);

      // Check if mounted
      if (!mounted) {
        // Merge confirmed + deep scan for pending results
        final mergedLocations = _mergeLocationsWithConfirmed(
          deepScanLocations,
          confirmedLocations,
          confirmedPlaceIds,
        );
        if (mergedLocations.isNotEmpty) {
          print(
              '🔍 DEEP SCAN: App backgrounded, storing ${mergedLocations.length} result(s) for later');
          _pendingScanResults = mergedLocations;
          if (mergedLocations.length == 1) {
            _pendingScanSingleMessage =
                '📍 Found: ${mergedLocations.first.name}';
          }
        }
        return;
      }

      // Merge confirmed locations with deep scan results
      final mergedLocations = _mergeLocationsWithConfirmed(
        deepScanLocations,
        confirmedLocations,
        confirmedPlaceIds,
      );

      // Log what we found
      final newFromDeepScan =
          mergedLocations.length - (confirmedLocations?.length ?? 0);
      if (confirmedLocations != null && confirmedLocations.isNotEmpty) {
        print(
            '✅ DEEP SCAN: ${confirmedLocations.length} confirmed + $newFromDeepScan new = ${mergedLocations.length} total location(s)');
      } else {
        print(
            '✅ DEEP SCAN: Found ${mergedLocations.length} location(s) via unified extraction');
      }

      if (mergedLocations.isEmpty) {
        print('⚠️ DEEP SCAN: No locations found');
        Fluttertoast.showToast(
          msg:
              '💡 Deep scan found no locations. Try the "Scan Preview" button.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.orange[700],
        );
        return;
      }

      _updateScanProgress(0.9, sessionId: scanSessionId);

      // Heavy vibration to notify user scan completed
      _heavyVibration();

      // Show results dialog - isDeepScan=true hides the deep scan option
      await _handleMultipleExtractedLocations(
        mergedLocations,
        provider,
        detectedEventInfo: detectedEventInfo,
        isDeepScan: true,
        scannedText: _extractedCaption,
      );
      if (!_isAnalysisSessionActive(scanSessionId)) return;
      _updateScanProgress(1.0, sessionId: scanSessionId);
    } catch (e) {
      print('❌ DEEP SCAN ERROR: $e');
      if (_isAnalysisSessionActive(scanSessionId)) {
        Fluttertoast.showToast(
          msg: '❌ Deep scan failed. Please try again.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.red,
        );
      }
    } finally {
      // Disable wakelock and stop foreground service
      WakelockPlus.disable();
      await _foregroundScanService.stopScanService();
      if (_isAnalysisSessionActive(scanSessionId)) {
        setState(() {
          _isExtractingLocation = false;
          _isAiScanInProgress = false;
          _scanProgress = 0.0;
        });
      }
    }
  }

  /// Merge confirmed locations (from quick scan) with deep scan results
  /// Confirmed locations are placed first, then new locations from deep scan
  /// Duplicates (matching placeId) from deep scan are filtered out
  List<ExtractedLocationData> _mergeLocationsWithConfirmed(
    List<ExtractedLocationData> deepScanLocations,
    List<ExtractedLocationData>? confirmedLocations,
    Set<String> confirmedPlaceIds,
  ) {
    if (confirmedLocations == null || confirmedLocations.isEmpty) {
      return deepScanLocations;
    }

    // Filter deep scan results to exclude already-confirmed locations
    final newLocations = deepScanLocations.where((loc) {
      if (loc.placeId == null || loc.placeId!.isEmpty) {
        return true; // Keep locations without placeId (couldn't dedupe)
      }
      // Handle 'places/' prefix
      final cleanPlaceId = loc.placeId!.startsWith('places/')
          ? loc.placeId!.substring(7)
          : loc.placeId!;
      return !confirmedPlaceIds.contains(cleanPlaceId);
    }).toList();

    // Merge: confirmed locations first, then new locations from deep scan
    final merged = <ExtractedLocationData>[
      ...confirmedLocations,
      ...newLocations,
    ];

    if (newLocations.length < deepScanLocations.length) {
      final filtered = deepScanLocations.length - newLocations.length;
      print(
          '📍 DEEP SCAN: Filtered out $filtered duplicate(s) already confirmed by user');
    }

    return merged;
  }

  /// Sort locations by their order of appearance in the scanned text
  /// This ensures the Locations Found dialog shows locations in the same order
  /// they appear in the original content (e.g., a numbered list of places)
  ///
  /// Uses the `originalQuery` field which stores the original extracted text
  /// before Places API verification. Falls back to the verified name if not set.
  List<ExtractedLocationData> _sortLocationsByTextAppearance(
    List<ExtractedLocationData> locations,
    String? scannedText,
  ) {
    if (scannedText == null || scannedText.isEmpty || locations.length <= 1) {
      return locations;
    }

    final lowerText = scannedText.toLowerCase();

    // Create a list of (location, firstIndex) pairs
    final locationsWithIndex = locations.map((loc) {
      var index = -1;
      String? matchedOn;

      // PRIORITY 1: Use originalQuery if available
      // This is the original text extracted from the caption before verification
      // e.g., "S3 Coffee" before it became "S3 Coffee Bar"
      if (loc.originalQuery != null && loc.originalQuery!.isNotEmpty) {
        final lowerOriginal = loc.originalQuery!.toLowerCase();
        index = lowerText.indexOf(lowerOriginal);
        if (index != -1) {
          matchedOn = 'originalQuery: "${loc.originalQuery}"';
        }

        // Also try without @ prefix for handle-based queries
        if (index == -1 && lowerOriginal.startsWith('@')) {
          final withoutAt = lowerOriginal.substring(1);
          index = lowerText.indexOf(withoutAt);
          if (index != -1) {
            matchedOn = 'originalQuery (no @): "$withoutAt"';
          }
        }
      }

      // PRIORITY 2: Try the verified name
      if (index == -1) {
        final lowerName = loc.name.toLowerCase();
        index = lowerText.indexOf(lowerName);
        if (index != -1) {
          matchedOn = 'name: "${loc.name}"';
        }

        // Strategy 2a: Try progressive prefix matching
        // e.g., "S3 Coffee Bar" → try "S3 Coffee", then "S3"
        if (index == -1) {
          final words = lowerName.split(' ');
          for (var wordCount = words.length - 1; wordCount >= 1; wordCount--) {
            final prefix = words.take(wordCount).join(' ');
            if (prefix.length >= 2) {
              final prefixIndex = lowerText.indexOf(prefix);
              if (prefixIndex != -1) {
                index = prefixIndex;
                matchedOn = 'prefix: "$prefix"';
                break;
              }
            }
          }
        }

        // Strategy 2b: Try first distinctive word only
        // Skip common words like "the", "cafe", "coffee", etc.
        if (index == -1) {
          const commonWords = [
            'the',
            'and',
            '&',
            'bar',
            'cafe',
            'café',
            'coffee',
            'house',
            'restaurant',
            'shop',
            'market',
            'bakery',
            'dessert',
            'tea',
            'room',
            'north',
            'south',
            'east',
            'west',
            'park',
            'mesa',
            'mira',
            'beach',
          ];
          final words = lowerName.split(' ');
          final distinctiveWords = words
              .where((w) => w.length > 1 && !commonWords.contains(w))
              .toList();

          if (distinctiveWords.isNotEmpty) {
            final firstWord = distinctiveWords.first;
            index = lowerText.indexOf(firstWord);
            if (index != -1) {
              matchedOn = 'distinctive word: "$firstWord"';
            }
          }
        }
      }

      print('📍 SORT: "${loc.name}" → index $index (matched on $matchedOn)');
      return (location: loc, index: index == -1 ? 999999 : index);
    }).toList();

    // Sort by index (order of appearance)
    locationsWithIndex.sort((a, b) => a.index.compareTo(b.index));

    print(
        '📍 SORT: Final order: ${locationsWithIndex.map((e) => '"${e.location.name}" @${e.index}').join(', ')}');

    return locationsWithIndex.map((e) => e.location).toList();
  }

  /// Build a fallback scanned text from location originalQuery fields
  /// This is used when no explicit scannedText is provided to ensure
  /// ALL Locations Found dialogs show the original text for user verification
  String? _buildScannedTextFallback(List<ExtractedLocationData> locations) {
    if (locations.isEmpty) return null;

    // Collect all unique original queries from the locations
    // originalQuery is the raw text extracted before Places API resolution
    final originalQueries = <String>[];
    for (final location in locations) {
      if (location.originalQuery != null &&
          location.originalQuery!.isNotEmpty) {
        // Use originalQuery if available (the raw extracted text before resolution)
        if (!originalQueries.contains(location.originalQuery!)) {
          originalQueries.add(location.originalQuery!);
        }
      } else if (location.name.isNotEmpty) {
        // Fall back to the resolved name if no originalQuery
        if (!originalQueries.contains(location.name)) {
          originalQueries.add(location.name);
        }
      }
    }

    if (originalQueries.isEmpty) return null;

    // Also try to get the current URL as additional context
    final currentUrl = _sharedUrlController.text.trim();

    // Build the fallback text
    final buffer = StringBuffer();

    // Add explanatory note about what AI detected
    buffer.writeln('AI detected the following location(s) from the scan:');
    buffer.writeln();

    // Add the extracted location names/queries
    for (var i = 0; i < originalQueries.length; i++) {
      buffer.writeln('${i + 1}. ${originalQueries[i]}');
    }

    // Add URL if available (helps user know what was scanned)
    if (currentUrl.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Source: $currentUrl');
    }

    return buffer.toString().trim();
  }

  /// Scroll to the top of the experience cards section
  void _scrollToExperienceCardsTop() {
    // Use a post-frame callback to ensure the cards are built before scrolling
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final experienceCardsContext = _experienceCardsSectionKey.currentContext;
      if (experienceCardsContext != null) {
        Scrollable.ensureVisible(
          experienceCardsContext,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          alignment: 0.0, // Align to top
        );
      }
    });
  }

  /// Show dialog asking user if they want to create an event from detected event info
  /// [savedExperiences] is used to get a fallback title if event name wasn't detected
  Future<bool?> _showEventConfirmationDialog(
      {List<Experience>? savedExperiences}) async {
    if (_detectedEventInfo == null) return false;

    // Determine the event title for display
    String eventName;
    if (_detectedEventInfo!.eventName != null &&
        _detectedEventInfo!.eventName!.isNotEmpty) {
      eventName = _detectedEventInfo!.eventName!;
    } else if (savedExperiences != null &&
        savedExperiences.isNotEmpty &&
        savedExperiences.first.name.isNotEmpty) {
      eventName = savedExperiences.first.name;
    } else {
      eventName = 'Event';
    }
    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.plum.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.event, color: AppColors.plum, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Event Detected',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Would you like to save and remind yourself of this event?',
                style: TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Text(
                  eventName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('No, thanks'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.plum,
                foregroundColor: Colors.white,
              ),
              child: const Text('Yes, create event'),
            ),
          ],
        );
      },
    );
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  /// Open EventEditorModal with a new event pre-populated with saved experiences
  Future<void> _openEventEditorWithExperiences(
    List<Experience> experiences,
    ExtractedEventInfo eventInfo,
  ) async {
    final currentUserId = _authService.currentUser?.uid;
    if (currentUserId == null) {
      print('⚠️ Cannot create event: user not logged in');
      return;
    }

    final now = DateTime.now();

    // Create event entries from the saved experiences
    final experienceEntries = experiences.map((exp) {
      return EventExperienceEntry(
        experienceId: exp.id,
      );
    }).toList();

    // Determine the event title:
    // 1. Use detected event name from Gemini if available
    // 2. Otherwise use the first experience's name as fallback
    // 3. Finally fall back to "Untitled Event"
    String eventTitle;
    if (eventInfo.eventName != null && eventInfo.eventName!.isNotEmpty) {
      eventTitle = eventInfo.eventName!;
    } else if (experiences.isNotEmpty && experiences.first.name.isNotEmpty) {
      eventTitle = experiences.first.name;
    } else {
      eventTitle = 'Untitled Event';
    }

    // Automatically set cover image
    // Priority: 1. Ticketmaster image (if available), 2. First experience's photo
    String? coverImageUrl;

    // For Ticketmaster events, use the event image as the cover
    if (eventInfo.ticketmasterImageUrl != null &&
        eventInfo.ticketmasterImageUrl!.isNotEmpty) {
      coverImageUrl = eventInfo.ticketmasterImageUrl;
      print('📷 EVENT COVER: Using Ticketmaster image: $coverImageUrl');
    }
    // Fall back to the first experience's photo
    else if (experiences.isNotEmpty) {
      final firstExp = experiences.first;

      // First try to get photo from existing data
      coverImageUrl = _buildCoverImageUrlFromExperience(firstExp);

      // If no photo data but we have a placeId, fetch from Google Places API
      if (coverImageUrl == null &&
          firstExp.location.placeId != null &&
          firstExp.location.placeId!.isNotEmpty) {
        try {
          coverImageUrl = await _mapsService.getPlaceImageUrl(
            firstExp.location.placeId!,
            maxWidth: 800,
            maxHeight: 600,
          );
        } catch (e) {
          print('Failed to fetch cover image from API: $e');
        }
      }
    }

    // Create a new Event with the detected info
    final newEvent = Event(
      id: '', // Will be generated on save
      title: eventTitle,
      description: '',
      startDateTime: eventInfo.startDateTime,
      endDateTime: eventInfo.endDateTime,
      coverImageUrl: coverImageUrl,
      plannerUserId: currentUserId,
      createdAt: now,
      updatedAt: now,
      experiences: experienceEntries,
      ticketmasterUrl: eventInfo.ticketmasterUrl,
      ticketmasterSearchTerm: eventInfo.ticketmasterSearchTerm,
    );

    if (!mounted) return;

    // Open the EventEditorModal
    await showModalBottomSheet<EventEditorResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EventEditorModal(
        event: newEvent,
        experiences: experiences,
        categories: _userCategories,
        colorCategories: _userColorCategories,
        isReadOnly: false, // Allow editing
      ),
    );
  }

  /// Build a cover image URL from an Experience's location photo data.
  /// Returns null if no photo is available.
  String? _buildCoverImageUrlFromExperience(Experience experience) {
    final resourceName = experience.location.photoResourceName;
    if (resourceName != null && resourceName.isNotEmpty) {
      return GoogleMapsService.buildPlacePhotoUrlFromResourceName(
        resourceName,
        maxWidthPx: 800,
        maxHeightPx: 600,
      );
    }
    final photoUrl = experience.location.photoUrl;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return photoUrl;
    }
    return null;
  }

  /// Determine the best primary category for an extracted location.
  /// Delegates to CategoryAutoAssignService for shared logic.
  Future<String?> _determineBestCategoryForLocation(
    ExtractedLocationData locationData,
    List<UserCategory> userCategories, {
    bool useAiFallback = true,
  }) async {
    return _categoryAutoAssignService.determineBestCategoryForExtractedLocation(
      locationData,
      userCategories,
      useAiFallback: useAiFallback,
    );
  }

  /// Auto-categorize a card with Color Category (Want to go) and Primary Category.
  ///
  /// This method sets:
  /// 1. Color Category to 'Want to go'
  /// 2. Primary Category based on location name (using AI if needed)
  ///
  /// Used when selecting a location from LocationPickerScreen or Quick Add dialog.
  /// Delegates to CategoryAutoAssignService for shared logic.
  ///
  /// Respects the "Automatically set categories" user setting.
  Future<void> _autoCategorizeCardForNewLocation(
    String cardId,
    Location location,
    ReceiveShareProvider provider,
  ) async {
    // Check if auto-set categories is enabled in settings
    final shouldAutoSetCategories =
        await _aiSettingsService.shouldAutoSetCategories();
    if (!shouldAutoSetCategories) {
      print('🏷️ AUTO-CATEGORIZE: Skipped (disabled in settings)');
      return;
    }

    final locationName = location.displayName ?? location.getPlaceName();
    print('🏷️ AUTO-CATEGORIZE: Setting categories for "$locationName"');

    // Build location context for AI disambiguation (city, country helps with common place names)
    final locationContextParts = <String>[];
    if (location.city != null && location.city!.isNotEmpty) {
      locationContextParts.add(location.city!);
    }
    if (location.state != null && location.state!.isNotEmpty) {
      locationContextParts.add(location.state!);
    }
    if (location.country != null && location.country!.isNotEmpty) {
      locationContextParts.add(location.country!);
    }
    final locationContext = locationContextParts.isNotEmpty
        ? locationContextParts.join(', ')
        : null;

    final categorization =
        await _categoryAutoAssignService.autoCategorizeForNewLocation(
      locationName: locationName,
      userCategories: _userCategories,
      colorCategories: _userColorCategories,
      placeTypes:
          location.placeTypes, // Use stored placeTypes for better accuracy
      placeId: location.placeId, // API fallback if placeTypes not stored
      locationContext: locationContext, // City/country for AI disambiguation
    );

    // Set Color Category to 'Want to go'
    if (categorization.colorCategoryId != null) {
      provider.updateCardColorCategory(cardId, categorization.colorCategoryId!);
      print('   ✅ Color Category set to "Want to go"');
    }

    // Set Primary Category based on location name
    if (categorization.primaryCategoryId != null) {
      provider.updateCardTextCategory(
          cardId, categorization.primaryCategoryId!);
      final categoryName = _userCategories
          .firstWhereOrNull((c) => c.id == categorization.primaryCategoryId)
          ?.name;
      print('   ✅ Primary Category set to "$categoryName"');
    }
  }

  /// Show informational dialog about multiple cards added
  void _showMultiLocationInfoDialog(int count) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.backgroundColorDark,
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

  /// Check if URL is a Ticketmaster URL
  bool _isTicketmasterUrl(String url) {
    return TicketmasterService.isTicketmasterUrl(url);
  }

  /// Extract Ticketmaster URL from text that may contain other content
  /// (e.g., "Share the event! https://www.ticketmaster.com/...")
  String? _extractTicketmasterUrlFromText(String text) {
    // Pattern to match Ticketmaster URLs
    final urlPattern = RegExp(
      r'https?://(?:www\.)?ticketmaster\.[a-z.]+/[^\s]+',
      caseSensitive: false,
    );
    final match = urlPattern.firstMatch(text);
    return match?.group(0);
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
    final card = targetCard;
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
    final scanSessionId = _startAnalysisSession();

    final results = _pendingScanResults!;

    // Clear pending results
    _pendingScanResults = null;
    _pendingScanSingleMessage = null;

    print('🔄 SCAN RESUME: Applying ${results.length} pending scan result(s)');

    // Heavy vibration to notify user that background scan completed
    _heavyVibration();

    try {
      final provider = context.read<ReceiveShareProvider>();

      // Always show the location selection dialog, even for single results
      // Use extracted caption if available for resumed scans
      final deepScanRequested = await _handleMultipleExtractedLocations(
        results,
        provider,
        scannedText: _extractedCaption,
      );
      if (!_isAnalysisSessionActive(scanSessionId)) return;

      // If user requested deep scan, run it after cleanup
      if (deepScanRequested && mounted) {
        _pendingDeepScanProvider = provider;
        _pendingDeepScanEventInfo = null;
      }
    } catch (e) {
      print('❌ SCAN RESUME ERROR: $e');
      if (_isAnalysisSessionActive(scanSessionId)) {
        Fluttertoast.showToast(
          msg: '❌ Scan failed. Please try scanning again.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.red,
        );
      }
    } finally {
      if (_isAnalysisSessionActive(scanSessionId)) {
        setState(() {
          _isProcessingScreenshot = false;
          _isAiScanInProgress = false;
          _scanProgress = 0.0;
        });
      }
      // Disable wakelock and stop foreground service after applying results
      WakelockPlus.disable();
      await _foregroundScanService.stopScanService();
    }

    // Run deep scan if requested (after cleanup is complete)
    if (_isAnalysisSessionActive(scanSessionId) &&
        _pendingDeepScanProvider != null &&
        mounted) {
      final provider = _pendingDeepScanProvider!;
      final eventInfo = _pendingDeepScanEventInfo;
      _pendingDeepScanProvider = null;
      _pendingDeepScanEventInfo = null;
      await _runDeepScan(provider, detectedEventInfo: eventInfo);
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
    _spotlightController.dispose();
    _sharedUrlController.dispose();
    _sharedUrlFocusNode.dispose();
    super.dispose();
  }

  void _navigateToCollections() {
    _sharingService.markShareFlowAsInactive();
    if (!mounted) {
      return;
    }
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
          builder: (context) => const MainScreen(initialIndex: 1)),
      (Route<dynamic> route) => false,
    );
  }

  Widget _wrapWithWillPopScope(Widget child) {
    return WillPopScope(
      onWillPop: () async {
        _navigateToCollections();
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

    // Check if content actually changed before clearing auto-scan state
    final bool contentChanged = _hasContentChanged(files);

    // For all content, always use normal processing
    // The Yelp URL handling complexity was causing more issues than it solved
    setState(() {
      _currentSharedFiles = files;
    });

    // Only clear auto-scanned URLs and processed URLs when content actually changes
    // This prevents duplicate auto-scans when provider reinitializes with same content
    if (contentChanged) {
      print('🔄 SHARE: Content changed, clearing auto-scan state');
      _autoScannedUrls.clear();
      _locationExtractionCompletedUrls.clear();
      _facebookUrlsProcessed.clear();
      _tiktokCaptionsProcessed.clear();
      _instagramUrlsProcessed.clear();
      _clearExtractedSocialContent(); // Clear any previously extracted social media content
    } else {
      print('🔄 SHARE: Same content, preserving auto-scan state');
    }
    _processSharedContent(files);
    _syncSharedUrlControllerFromContent();
  }

  /// Check if the new files are different from the current files
  bool _hasContentChanged(List<SharedMediaFile> newFiles) {
    if (_currentSharedFiles.isEmpty) return true;
    if (_currentSharedFiles.length != newFiles.length) return true;

    // Compare URLs from both lists
    final currentUrls = _currentSharedFiles
        .map((f) => _extractFirstUrl(f.path))
        .where((url) => url != null)
        .toSet();
    final newUrls = newFiles
        .map((f) => _extractFirstUrl(f.path))
        .where((url) => url != null)
        .toSet();

    return !currentUrls.containsAll(newUrls) ||
        !newUrls.containsAll(currentUrls);
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
          // Auto-extract content from Instagram/Facebook posts using oEmbed API
          // This extracts caption, hashtags, and mentions for use in other methods
          if (_isInstagramUrl(foundUrl) || _isFacebookUrl(foundUrl)) {
            _autoExtractSocialMediaContent(foundUrl);
          }

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
        shareGooglePattern.hasMatch(urlLower) ||
        _isTicketmasterUrl(url)) {
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
      final scanSessionId = _startAnalysisSession();

      // Set loading state to show spinner in location field AND AI analyzing chip
      firstCard.isSelectingLocation = true;
      _isExtractingLocation = true;
      _scanProgress = 0.5; // Show progress in the bar
      if (mounted) {
        setState(() {}); // Trigger rebuild to show loading indicator and chip
      }

      // Start the extraction and handle completion
      _yelpPreviewFutures[normalizedUrl] = _getLocationFromMapsUrl(
        normalizedUrl,
        analysisSessionId: scanSessionId,
      ).then((result) {
        if (!_isAnalysisSessionActive(scanSessionId)) return null;
        // Loading state will be cleared in _fillFormWithGoogleMapsData
        // after the location is actually set on the card
        // Only clear here if no location was found (result is null)
        if (result == null || result['location'] == null) {
          firstCard.isSelectingLocation = false;
          _isExtractingLocation = false;
          _scanProgress = 0.0;
          if (mounted) {
            setState(
                () {}); // Trigger rebuild to hide loading indicator and chip
          }
        }
        return result;
      }).catchError((error) {
        if (!_isAnalysisSessionActive(scanSessionId)) return null;
        // Clear loading state on error
        firstCard.isSelectingLocation = false;
        _isExtractingLocation = false;
        _scanProgress = 0.0;
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

          // Use UNIFIED extraction (same as Preview Scan) to extract location with Gemini
          final unifiedResult =
              await _locationExtractor.extractLocationsFromTextUnified(
            'Find the restaurant/business: $searchContext',
            userLocation: userLatLng,
          );
          final geminiLocations = unifiedResult.locations;

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
    } catch (e) {
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
          targetCard.id, existingExperience);
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
          targetCard.id, existingExperience);
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
      String websiteUrl, String originalMapsUrl,
      {int? analysisSessionId}) async {
    if (analysisSessionId != null &&
        !_isAnalysisSessionActive(analysisSessionId)) {
      return;
    }

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
    if (analysisSessionId != null &&
        !_isAnalysisSessionActive(analysisSessionId)) {
      return;
    }
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
    if (analysisSessionId != null &&
        !_isAnalysisSessionActive(analysisSessionId)) {
      return;
    }
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
    _locationUpdateDebounce =
        Timer(const Duration(milliseconds: 100), () async {
      if (analysisSessionId != null &&
          !_isAnalysisSessionActive(analysisSessionId)) {
        return;
      }
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
        // Check if auto-categorization is enabled before clearing the chip
        final shouldAutoSetCategories = location.placeId != null
            ? await _aiSettingsService.shouldAutoSetCategories()
            : false;
        if (analysisSessionId != null &&
            !_isAnalysisSessionActive(analysisSessionId)) {
          return;
        }

        setState(() {
          // Clear location field loading state
          firstCard.isSelectingLocation = false;

          // Update progress bar - extraction done
          _scanProgress = 0.8;

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

          // If auto-categorization is enabled, switch chip to "Categorizing..."
          // Keep _isExtractingLocation true so the chip stays visible
          if (shouldAutoSetCategories) {
            _isCategorizing = true;
          } else {
            // No categorization, hide the chip now
            _isExtractingLocation = false;
            _scanProgress = 0.0;
          }
        });

        // Auto-set Color Category to 'Want to go' and determine Primary Category
        // for the newly extracted location from Google Maps URL
        if (shouldAutoSetCategories) {
          await _autoCategorizeCardForNewLocation(cardId, location, provider);
          if (analysisSessionId != null &&
              !_isAnalysisSessionActive(analysisSessionId)) {
            return;
          }

          // Hide chip after categorization completes
          if (mounted) {
            setState(() {
              _isCategorizing = false;
              _isExtractingLocation = false;
              _scanProgress = 0.0;
            });
          }
        }
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

    // Track saved experience IDs for potential event creation
    final List<String> savedExperienceIds = [];
    final List<Experience> savedExperiences = [];

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

            // Check if this is a Ticketmaster URL and get cached event details
            String? ticketmasterEventName;
            String? ticketmasterVenueName;
            DateTime? ticketmasterEventDate;
            String? ticketmasterImageUrl;
            String? ticketmasterEventId;
            if (_isTicketmasterUrl(path)) {
              // Extract the actual URL from the path (it might include prefix text like "Share the event!")
              final ticketmasterUrl = _extractTicketmasterUrlFromText(path);
              if (ticketmasterUrl != null) {
                final details = _ticketmasterEventDetails[ticketmasterUrl];
                if (details != null) {
                  ticketmasterEventName = details.name;
                  ticketmasterVenueName = details.venue?.name;
                  ticketmasterEventDate = details.startDateTime;
                  ticketmasterImageUrl = details.imageUrl;
                  ticketmasterEventId = details.id;
                  print(
                      '🎫 TICKETMASTER SAVE: Caching event details for "${details.name}"');
                } else {
                  print(
                      '🎫 TICKETMASTER SAVE: No cached details found for URL: $ticketmasterUrl');
                }
              } else {
                print(
                    '🎫 TICKETMASTER SAVE: Could not extract URL from path: $path');
              }
            }

            SharedMediaItem newItem = SharedMediaItem(
              id: '',
              path: path,
              createdAt: now,
              ownerUserId: currentUserId,
              experienceIds: [],
              isTiktokPhoto: isTiktokPhoto,
              isPrivate: _sharedMediaIsPrivate,
              caption: _extractedCaption,
              ticketmasterEventName: ticketmasterEventName,
              ticketmasterVenueName: ticketmasterVenueName,
              ticketmasterEventDate: ticketmasterEventDate,
              ticketmasterImageUrl: ticketmasterImageUrl,
              ticketmasterEventId: ticketmasterEventId,
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

            // Determine description: user notes > fetched summary > empty
            // Defined before if/else so it's available for PublicExperience creation later
            String descriptionToSave;
            if (notes.isNotEmpty) {
              descriptionToSave = notes;
            } else if (card.fetchedDescription != null &&
                card.fetchedDescription!.isNotEmpty) {
              descriptionToSave = card.fetchedDescription!;
            } else {
              descriptionToSave = '';
            }

            if (card.existingExperienceId == null ||
                card.existingExperienceId!.isEmpty) {
              isNewExperience = true;
              // Include placeTypes in location for auto-categorization optimization
              final locationWithPlaceTypes =
                  card.placeTypes != null && card.placeTypes!.isNotEmpty
                      ? locationToSave.copyWith(placeTypes: card.placeTypes)
                      : locationToSave;

              Experience newExperience = Experience(
                id: '',
                name: cardTitle,
                description: descriptionToSave,
                location: locationWithPlaceTypes,
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
              // Track for potential event creation
              if (targetExperienceId.isNotEmpty) {
                savedExperienceIds.add(targetExperienceId);
                if (currentExperienceData != null) {
                  savedExperiences.add(currentExperienceData);
                }
              }
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
              // Track for potential event creation
              if (targetExperienceId.isNotEmpty) {
                savedExperienceIds.add(targetExperienceId);
                savedExperiences.add(updatedExpData);
              }
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
                if (!isNewExperience && relevantMediaItemIds.isNotEmpty) {
                  updateCount--; // Correct if only media was new and no other field changed
                }
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
                // Include placeTypes for auto-categorization when users save from Discovery
                final locationWithPlaceTypesForPublic =
                    card.placeTypes != null && card.placeTypes!.isNotEmpty
                        ? locationToSave.copyWith(placeTypes: card.placeTypes)
                        : locationToSave;
                PublicExperience newPublicExperience = PublicExperience(
                    id: '',
                    name: publicName,
                    location: locationWithPlaceTypesForPublic,
                    placeID: placeId,
                    yelpUrl: cardYelpUrl.isNotEmpty ? cardYelpUrl : null,
                    website: cardWebsite.isNotEmpty ? cardWebsite : null,
                    allMediaPaths: uniqueMediaPaths,
                    icon: selectedCategoryObject?.icon,
                    placeTypes: card.placeTypes,
                    description: descriptionToSave.isNotEmpty
                        ? descriptionToSave
                        : null);
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
          message +=
              '$successCount ${successCount == 1 ? 'experience' : 'experiences'} created. ';
        }
        if (updateCount > 0) {
          message +=
              '$updateCount ${updateCount == 1 ? 'experience' : 'experiences'} updated! ';
        }
        message = message.trim();
        if (message.isEmpty) message = 'No changes saved.';
        shouldAttemptNavigation = true;
      } else {
        message = 'Completed with errors: ';
        if (successCount > 0) message += '$successCount created! ';
        if (updateCount > 0) message += '$updateCount updated! ';
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

      // Add each saved experience to its respective selected event's itinerary
      // Group experiences by their selected event
      final Map<String, List<String>> eventToExperienceIds = {};
      final Map<String, Event> eventCache = {};

      for (int i = 0; i < experienceCards.length; i++) {
        final card = experienceCards[i];
        if (card.selectedEvent != null && i < savedExperienceIds.length) {
          final eventId = card.selectedEvent!.id;
          final experienceId = savedExperienceIds[i];

          eventToExperienceIds.putIfAbsent(eventId, () => []);
          eventToExperienceIds[eventId]!.add(experienceId);
          eventCache[eventId] = card.selectedEvent!;
        }
      }

      // Add experiences to their respective events
      for (final entry in eventToExperienceIds.entries) {
        final eventId = entry.key;
        final experienceIdsForEvent = entry.value;
        final cachedEvent = eventCache[eventId]!;

        try {
          // Refresh the event to get the latest data
          final freshEvent = await _eventService.getEvent(eventId);
          if (freshEvent != null && mounted) {
            // Create new itinerary entries for the experiences
            final newEntries = experienceIdsForEvent
                .map((expId) => EventExperienceEntry(experienceId: expId))
                .toList();

            // Add to existing experiences
            final updatedExperiences = [
              ...freshEvent.experiences,
              ...newEntries,
            ];

            // Update the event
            final updatedEvent = freshEvent.copyWith(
              experiences: updatedExperiences,
              updatedAt: DateTime.now(),
            );

            await _eventService.updateEvent(updatedEvent);

            if (mounted) {
              Fluttertoast.showToast(
                msg:
                    '${experienceIdsForEvent.length} experience${experienceIdsForEvent.length != 1 ? 's' : ''} added to "${cachedEvent.title}"',
                toastLength: Toast.LENGTH_LONG,
                gravity: ToastGravity.BOTTOM,
              );
            }
          }
        } catch (e) {
          debugPrint('Error adding experiences to event $eventId: $e');
          if (mounted) {
            Fluttertoast.showToast(
              msg:
                  'Experiences saved, but could not add to "${cachedEvent.title}"',
              toastLength: Toast.LENGTH_LONG,
              gravity: ToastGravity.BOTTOM,
            );
          }
        }
      }

      // Clear selected events from all cards after handling
      for (final card in experienceCards) {
        card.selectedEvent = null;
      }

      if (shouldAttemptNavigation) {
        if (!mounted) return;

        // Check if we should offer to create an event
        if (_detectedEventInfo != null && savedExperienceIds.isNotEmpty) {
          final shouldCreateEvent = await _showEventConfirmationDialog(
              savedExperiences: savedExperiences);
          if (shouldCreateEvent == true && mounted) {
            // Open EventEditorModal with the saved experiences
            await _openEventEditorWithExperiences(
              savedExperiences,
              _detectedEventInfo!,
            );
          }
          // Clear the detected event info after handling
          _detectedEventInfo = null;
        }

        if (!mounted) return;

        widget.onExperienceSaved?.call();

        _sharingService.prepareToNavigateAwayFromShare();

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const MainScreen()),
          (Route<dynamic> route) => false,
        );
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

          // Fetch summary for the location (editorialSummary → reviewSummary → generativeSummary)
          String? fetchedSummary;
          try {
            fetchedSummary =
                await _mapsService.fetchPlaceSummary(selectedLocation.placeId!);
          } catch (e) {
            print("ReceiveShareScreen: Error fetching summary: $e");
          }
          if (!mounted) return;

          final String businessName = detailedLocation.getPlaceName();
          final String yelpUrl = card.yelpUrlController.text.trim();

          _businessDataCache.remove(yelpUrl);
          _yelpPreviewFutures.remove(yelpUrl);
          if (card.placeIdForPreview != null) {
            _yelpPreviewFutures.remove(card.placeIdForPreview);
          }

          // Store the fetched description in the card
          card.fetchedDescription = fetchedSummary;

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

          // Fetch summary for the location (editorialSummary → reviewSummary → generativeSummary)
          String? fetchedSummary;
          try {
            fetchedSummary =
                await _mapsService.fetchPlaceSummary(selectedLocation.placeId!);
          } catch (e) {
            print("ReceiveShareScreen: Error fetching summary: $e");
          }
          if (!mounted) return;

          final String title = detailedLocation.getPlaceName();
          final String? website = detailedLocation.website;
          final String address = detailedLocation.address ?? '';
          final String? placeId = detailedLocation.placeId;

          if (card.placeIdForPreview != null) {
            _yelpPreviewFutures.remove(card.placeIdForPreview);
          }

          // Store the fetched description in the card
          card.fetchedDescription = fetchedSummary;

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

      // Auto-set Color Category to 'Want to go' and determine Primary Category
      // for the newly selected location (only if we reach here - not if existing experience was used)
      // Use card.selectedLocation which has been updated with detailedLocation (including placeTypes from API)
      if (mounted &&
          card.selectedLocation != null &&
          card.selectedLocation!.placeId != null) {
        await _autoCategorizeCardForNewLocation(
            card.id, card.selectedLocation!, provider);
        // Force UI rebuild after category changes
        if (mounted) {
          setState(() {});
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
      backgroundColor: AppColors.backgroundColorDark,
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

  // --- Quick Add Dialog ---
  Future<void> _showQuickAddDialog() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future.microtask(() {});

    // Reset quick add state
    _quickAddSelectedLocation = null;
    _quickAddSelectedExperience = null;
    _isQuickAddSavedExperience = false;

    _pauseHelpForDialog();
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Quick Add Dialog',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return _QuickAddDialog(
          mapsService: _mapsService,
          experienceService: _experienceService,
          onLocationSelected: (location, experience) {
            setState(() {
              _quickAddSelectedLocation = location;
              _quickAddSelectedExperience = experience;
              _isQuickAddSavedExperience = experience != null;
            });
            Navigator.of(dialogContext).pop();
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        );
      },
    );
    _resumeHelpAfterDialog();

    // After dialog closes, handle the selected location/experience
    if (!mounted) return;

    if (_quickAddSelectedLocation != null) {
      await _handleQuickAddSelection(
        _quickAddSelectedLocation!,
        _quickAddSelectedExperience,
      );
    }
  }

  /// Handle the Quick Add selection - fills an empty card or creates a new one
  Future<void> _handleQuickAddSelection(
    Location location,
    Experience? existingExperience,
  ) async {
    final provider = context.read<ReceiveShareProvider>();

    // Find an empty card (no location selected)
    ExperienceCardData? targetCard;
    for (final card in provider.experienceCards) {
      if (card.selectedLocation == null ||
          card.selectedLocation!.placeId == null ||
          card.selectedLocation!.placeId!.isEmpty) {
        targetCard = card;
        break;
      }
    }

    // If no empty card found, create a new one
    if (targetCard == null) {
      provider.addExperienceCard();
      targetCard = provider.experienceCards.last;
    }

    if (existingExperience != null) {
      // User selected an existing saved experience
      provider.updateCardWithExistingExperience(
        targetCard.id,
        existingExperience,
      );

      // Show toast for saved experience
      Fluttertoast.showToast(
        msg: '✓ Added saved experience: ${existingExperience.name}',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );
    } else {
      // User selected a new location - fill in location and website
      provider.updateCardData(
        targetCard,
        location: location,
        title: location.displayName ?? location.getPlaceName(),
        website: location.website,
        searchQuery: location.address,
        placeIdForPreview: location.placeId,
      );

      // Auto-set Color Category to 'Want to go' and determine Primary Category
      await _autoCategorizeCardForNewLocation(
          targetCard.id, location, provider);

      // Force UI rebuild after category changes (provider notifyListeners doesn't trigger rebuild
      // because _ExperienceCardsSection doesn't watch the provider)
      if (mounted) {
        setState(() {});
      }

      // Show toast for new location
      final locationName = location.displayName ?? location.getPlaceName();
      Fluttertoast.showToast(
        msg: '✓ Added location: $locationName',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.blue,
        textColor: Colors.white,
      );
    }
  }
  // --- End Quick Add Dialog ---

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
    // #region agent log
    debugPrint(
        '[DEBUG H1] ReceiveShareScreen.build: START, kIsWeb=$kIsWeb, requireUrlFirst=${widget.requireUrlFirst}');
    // #endregion
    // FIXED: Check kIsWeb before Platform.isIOS to avoid crash on web
    final bool useIOSBackIcon = !kIsWeb && Platform.isIOS;
    // #region agent log
    debugPrint(
        '[DEBUG H1] ReceiveShareScreen.build: Platform check passed, useIOSBackIcon=$useIOSBackIcon');
    // #endregion
    return _wrapWithWillPopScope(Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.backgroundColor,
          appBar: AppBar(
            backgroundColor: AppColors.backgroundColor,
            foregroundColor: Colors.black,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: AppColors.backgroundColor,
            title: const FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'Save Content',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
              ),
            ),
            leading: IconButton(
              icon: Icon(
                  useIOSBackIcon ? Icons.arrow_back_ios : Icons.arrow_back),
              onPressed: () {
                _navigateToCollections();
              },
            ),
            automaticallyImplyLeading: false,
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Builder(builder: (privacyCtx) {
                      return PrivacyToggleButton(
                        isPrivate: _sharedMediaIsPrivate,
                        onPressed: () {
                          if (_tryHelpTap(
                              ReceiveShareHelpTargetId.privacyToggle,
                              privacyCtx)) return;
                          setState(() {
                            _sharedMediaIsPrivate = !_sharedMediaIsPrivate;
                          });
                        },
                      );
                    }),
                    const SizedBox(width: 4),
                    _helpFlow.isActive
                        ? AnimatedBuilder(
                            animation: _spotlightController,
                            builder: (context, _) {
                              final scale =
                                  1.0 + 0.15 * _spotlightController.value;
                              return Transform.scale(
                                scale: scale,
                                child: Semantics(
                                  label: 'Exit help mode',
                                  child: IconButton(
                                    key: _helpButtonKey,
                                    icon:
                                        Icon(Icons.help, color: AppColors.teal),
                                    tooltip: 'Exit Help Mode',
                                    onPressed: _toggleHelpMode,
                                  ),
                                ),
                              );
                            },
                          )
                        : Semantics(
                            label: 'Enter help mode',
                            child: IconButton(
                              key: _helpButtonKey,
                              icon: const Icon(Icons.help_outline),
                              tooltip: 'Help',
                              onPressed: _toggleHelpMode,
                            ),
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
                        builder:
                            (context, AsyncSnapshot<List<dynamic>> snapshot) {
                          // #region agent log
                          debugPrint(
                              '[DEBUG H2] FutureBuilder: _combinedCategoriesFuture=${_combinedCategoriesFuture != null}, connectionState=${snapshot.connectionState}, requireUrlFirst=${widget.requireUrlFirst}');
                          // #endregion
                          // Primary Loading State: Show spinner if the future is null (early init) or still running.
                          if (_combinedCategoriesFuture == null ||
                              snapshot.connectionState ==
                                  ConnectionState.waiting) {
                            // print("FutureBuilder: STATE_WAITING (Future is null or connection is waiting)");
                            // In URL-first mode, show the UI with URL bar so user can proceed
                            if (widget.requireUrlFirst) {
                              // #region agent log
                              debugPrint(
                                  '[DEBUG H2] FutureBuilder: Returning URL bar for requireUrlFirst mode');
                              // #endregion
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildSharedUrlBar(showInstructions: true),
                                ],
                              );
                            }
                            return const Center(
                                child: CircularProgressIndicator());
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
                                _buildHelpBanner(),
                                _buildSharedUrlBar(
                                    showInstructions:
                                        _currentSharedFiles.isEmpty),
                                Container(
                                  height: 8,
                                  color: AppColors.backgroundColor,
                                ),
                                // Gate the rest of content when required
                                Expanded(
                                  child: AbsorbPointer(
                                    absorbing: !_urlGateOpen,
                                    child: AnimatedOpacity(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      opacity: _urlGateOpen ? 1.0 : 0.4,
                                      child: Stack(
                                        // WRAPPED IN STACK FOR FAB
                                        children: [
                                          SingleChildScrollView(
                                            controller:
                                                _scrollController, // ATTACHED SCROLL CONTROLLER
                                            padding: EdgeInsets.zero,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                // Re-enable the shared files preview list
                                                Builder(
                                                    builder: (mediaSectionCtx) {
                                                  return GestureDetector(
                                                    behavior: HitTestBehavior
                                                        .translucent,
                                                    onTap: _helpFlow.isActive
                                                        ? () {
                                                            _tryHelpTap(
                                                                ReceiveShareHelpTargetId
                                                                    .mediaPreviewSection,
                                                                mediaSectionCtx);
                                                          }
                                                        : null,
                                                    child: Container(
                                                      color: AppColors
                                                          .backgroundColor,
                                                      child: _currentSharedFiles
                                                              .isEmpty
                                                          ? const Padding(
                                                              padding:
                                                                  EdgeInsets
                                                                      .all(
                                                                          16.0),
                                                              child: Center(
                                                                  child: Text(
                                                                      'No shared content received')),
                                                            )
                                                          : Consumer<
                                                              ReceiveShareProvider>(
                                                              key:
                                                                  _mediaPreviewListKey, // MOVED KEY HERE
                                                              builder: (context,
                                                                  provider,
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

                                                                return ListView
                                                                    .builder(
                                                                  padding:
                                                                      EdgeInsets
                                                                          .zero,
                                                                  shrinkWrap:
                                                                      true,
                                                                  physics:
                                                                      const NeverScrollableScrollPhysics(),
                                                                  itemCount:
                                                                      _currentSharedFiles
                                                                          .length,
                                                                  itemBuilder:
                                                                      (context,
                                                                          index) {
                                                                    final file =
                                                                        _currentSharedFiles[
                                                                            index];

                                                                    bool
                                                                        isInstagram =
                                                                        false;
                                                                    bool
                                                                        isTikTok =
                                                                        false;
                                                                    if (file.type ==
                                                                            SharedMediaType
                                                                                .text ||
                                                                        file.type ==
                                                                            SharedMediaType.url) {
                                                                      String?
                                                                          url =
                                                                          _extractFirstUrl(
                                                                              file.path);
                                                                      if (url !=
                                                                          null) {
                                                                        if (url.contains(
                                                                            'instagram.com')) {
                                                                          isInstagram =
                                                                              true;
                                                                        } else if (url.contains('tiktok.com') ||
                                                                            url.contains('vm.tiktok.com')) {
                                                                          isTikTok =
                                                                              true;
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
                                                                    final bool
                                                                        isLastItem =
                                                                        index ==
                                                                            _currentSharedFiles.length -
                                                                                1;

                                                                    return Padding(
                                                                      key: ValueKey(
                                                                          file.path),
                                                                      padding:
                                                                          EdgeInsets
                                                                              .fromLTRB(
                                                                        horizontalPadding,
                                                                        verticalPadding,
                                                                        horizontalPadding,
                                                                        isLastItem
                                                                            ? 0.0
                                                                            : verticalPadding,
                                                                      ),
                                                                      child:
                                                                          Card(
                                                                        color: Colors
                                                                            .white,
                                                                        elevation:
                                                                            2.0,
                                                                        margin: (isInstagram ||
                                                                                isTikTok)
                                                                            ? EdgeInsets.zero
                                                                            : const EdgeInsets.only(bottom: 0),
                                                                        shape:
                                                                            RoundedRectangleBorder(
                                                                          borderRadius: BorderRadius.circular((isInstagram || isTikTok)
                                                                              ? 0
                                                                              : 8),
                                                                        ),
                                                                        clipBehavior: (isInstagram ||
                                                                                isTikTok)
                                                                            ? Clip.antiAlias
                                                                            : Clip.none,
                                                                        child:
                                                                            Column(
                                                                          crossAxisAlignment:
                                                                              CrossAxisAlignment.start,
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
                                                              },
                                                            ),
                                                    ),
                                                  );
                                                }),
                                                Container(
                                                  height: 8,
                                                  color: AppColors
                                                      .backgroundColorDark,
                                                ),
                                                Builder(
                                                    builder: (cardsSectionCtx) {
                                                  return GestureDetector(
                                                    behavior: HitTestBehavior
                                                        .translucent,
                                                    onTap: _helpFlow.isActive
                                                        ? () {
                                                            _tryHelpTap(
                                                                ReceiveShareHelpTargetId
                                                                    .experienceCardsSection,
                                                                cardsSectionCtx);
                                                          }
                                                        : null,
                                                    child: Selector<
                                                        ReceiveShareProvider,
                                                        int>(
                                                      key: const ValueKey(
                                                          'experience_cards_selector'),
                                                      selector: (_, provider) =>
                                                          provider
                                                              .experienceCards
                                                              .length,
                                                      builder: (context,
                                                          cardCount, _) {
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
                                                          isSpecialUrl:
                                                              _isSpecialUrl,
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
                                                          showSelectEventDialog:
                                                              _showSelectEventDialogForCard,
                                                          getDetectedEventName: () =>
                                                              _detectedEventInfo
                                                                  ?.eventName,
                                                          isHelpMode: _helpFlow
                                                              .isActive,
                                                          onHelpTap:
                                                              _tryHelpTap,
                                                        );
                                                      },
                                                    ),
                                                  );
                                                }),
                                                Container(
                                                  height: 80,
                                                  color: AppColors
                                                      .backgroundColorDark,
                                                ),
                                              ],
                                            ),
                                          ),
                                          // --- ADDED FAB ---
                                          Positioned(
                                            bottom: 16,
                                            right: 16,
                                            child: Builder(builder: (fabCtx) {
                                              return FloatingActionButton(
                                                backgroundColor:
                                                    Theme.of(context)
                                                        .primaryColor,
                                                foregroundColor: Colors.white,
                                                shape: const CircleBorder(),
                                                onPressed: () {
                                                  if (_tryHelpTap(
                                                      ReceiveShareHelpTargetId
                                                          .scrollFab,
                                                      fabCtx)) return;
                                                  _handleFabPress();
                                                },
                                                child: Icon(_showUpArrowForFab
                                                    ? Icons.arrow_upward
                                                    : Icons.arrow_downward),
                                              );
                                            }),
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
                                    color: AppColors.backgroundColor,
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
                                      Builder(builder: (cancelCtx) {
                                        return OutlinedButton(
                                          onPressed: () {
                                            if (_tryHelpTap(
                                                ReceiveShareHelpTargetId
                                                    .cancelButton,
                                                cancelCtx)) return;
                                            widget.onCancel();
                                          },
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.grey[700],
                                          ),
                                          child: const Text('Cancel'),
                                        );
                                      }),
                                      Builder(builder: (quickAddCtx) {
                                        return ElevatedButton.icon(
                                          onPressed: () {
                                            if (_tryHelpTap(
                                                ReceiveShareHelpTargetId
                                                    .quickAddButton,
                                                quickAddCtx)) return;
                                            _showQuickAddDialog();
                                          },
                                          icon: const Icon(Icons.add,
                                              color: Colors.white),
                                          label: const Text('Quick Add',
                                              style: TextStyle(
                                                  color: Colors.white)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                Theme.of(context).primaryColor,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 16, vertical: 12),
                                          ),
                                        );
                                      }),
                                      Builder(builder: (saveCtx) {
                                        return ElevatedButton.icon(
                                          onPressed: _isSaving
                                              ? null
                                              : () {
                                                  if (_tryHelpTap(
                                                      ReceiveShareHelpTargetId
                                                          .saveButton,
                                                      saveCtx)) return;
                                                  _saveExperience();
                                                },
                                          icon: _isSaving
                                              ? Container(
                                                  width: 20,
                                                  height: 20,
                                                  padding:
                                                      const EdgeInsets.all(2.0),
                                                  child:
                                                      const CircularProgressIndicator(
                                                          strokeWidth: 3,
                                                          color: Colors.white),
                                                )
                                              : const Icon(Icons.save),
                                          label: Text(
                                              _isSaving ? 'Saving...' : 'Save'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                Theme.of(context).primaryColor,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 24, vertical: 12),
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                )
                              ],
                            );
                          } else {
                            // Future is done, no error, but data is missing or insufficient.
                            // print("FutureBuilder: STATE_NO_SUFFICIENT_DATA (Done, no error, but data invalid or missing)");
                            return const Center(
                                child: Text(
                                    "Error: Could not load category data."));
                          }
                        },
                      ),
              ),
            ),
          ),
        ),
        if (_helpFlow.isActive && _helpFlow.hasActiveTarget)
          _buildHelpOverlay(),
      ],
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
        isHelpMode: _helpFlow.isActive,
        onHelpTap: _tryHelpTap,
      );
    }

    // Ticketmaster event URLs
    if (_isTicketmasterUrl(url)) {
      // Trigger loading event details if not already cached
      // Use addPostFrameCallback to avoid calling setState during build
      if (!_ticketmasterEventDetails.containsKey(url) &&
          !_ticketmasterUrlsLoading.contains(url)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadTicketmasterEventDetails(url, card);
          }
        });
      }

      final details = _ticketmasterEventDetails[url];
      final isLoading = _ticketmasterUrlsLoading.contains(url);

      return TicketmasterPreviewWidget(
        ticketmasterUrl: url,
        launchUrlCallback: _launchUrl,
        isLoading: isLoading,
        eventName: details?.name,
        venueName: details?.venue?.name,
        eventDate: details?.startDateTime,
        imageUrl: details?.imageUrl,
        isHelpMode: _helpFlow.isActive,
        onHelpTap: _tryHelpTap,
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
        isHelpMode: _helpFlow.isActive,
        onHelpTap: _tryHelpTap,
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
        isHelpMode: _helpFlow.isActive,
        onExpansionChanged: (isExpanded, instaUrl) =>
            _onInstagramExpansionChanged(
                isExpanded, instaUrl), // CORRECTED: Match signature
        onPageFinished: (loadedUrl) => _onInstagramPageLoaded(url),
        onHelpTap: _tryHelpTap,
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
        isHelpMode: _helpFlow.isActive,
        onHelpTap: _tryHelpTap,
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
        isHelpMode: _helpFlow.isActive,
        onHelpTap: _tryHelpTap,
        onWebViewCreated: (controller) {
          // Handle controller if needed
        },
        onPageFinished: (loadedUrl) {
          // NOTE: Reel restriction temporarily disabled to test auto-scanning on Reels.
          // Uncomment below to restore the restriction if Reel auto-extraction is unreliable.
          //
          // // Skip auto-extraction for Facebook Reels - their DOM structure is too
          // // obfuscated for reliable scraping. Users can use "Scan Preview" instead.
          // final isReel = url.contains('/reel/') || url.contains('/reels/');
          // if (isReel) {
          //   print(
          //       '📘 FACEBOOK: Skipping auto-extraction for Reel (use Scan Preview instead)');
          //   return;
          // }

          // Automatically extract locations from Facebook posts (including Reels)
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
        isHelpMode: _helpFlow.isActive,
        onHelpTap: _tryHelpTap,
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
        isHelpMode: _helpFlow.isActive,
        onHelpTap: _tryHelpTap,
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
      isHelpMode: _helpFlow.isActive,
      onHelpTap: _tryHelpTap,
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

    print(
        '🚀 AUTO-SCAN: Web page loaded, automatically scanning for locations...');

    // Small delay to ensure WebView is fully rendered
    Future.delayed(const Duration(milliseconds: 500), () async {
      if (!mounted || _isProcessingScreenshot || _isExtractingLocation) {
        return;
      }
      if (!await _shouldAutoExtractLocations()) return;
      _scanPageContent();
    });
  }

  /// Called when Instagram preview finishes loading.
  ///
  /// For Instagram, _scheduleInstagramWebViewExtraction (5s timer) is the
  /// primary extraction path: it extracts the caption from the WebView and
  /// feeds it to the lighter Maps-grounded extraction. This callback only
  /// serves as a fallback -- if the caption was already extracted but Maps
  /// grounding hasn't run yet, it triggers it here. We intentionally avoid
  /// calling _scanPageContent because it would redundantly re-extract the
  /// same WebView content and use the heavier full-page Gemini scan.
  void _onInstagramPageLoaded(String url) {
    // Only auto-scan once per URL
    if (_autoScannedUrls.contains(url)) {
      print('🔄 AUTO-SCAN: Already scanned Instagram $url, skipping');
      return;
    }

    // Don't auto-scan if already processing
    if (_isProcessingScreenshot || _isExtractingLocation) {
      print('🔄 AUTO-SCAN: Already processing, skipping Instagram auto-scan');
      return;
    }

    // Mark as scanned
    _autoScannedUrls.add(url);

    print(
        '🚀 AUTO-SCAN: Instagram preview loaded, waiting for embed to render...');

    Future.delayed(const Duration(milliseconds: 4000), () async {
      if (!mounted || _isProcessingScreenshot || _isExtractingLocation) {
        return;
      }
      if (_locationExtractionCompletedUrls.contains(url)) {
        print(
            '🔄 AUTO-SCAN: Location extraction already completed for $url, skipping');
        return;
      }
      if (!await _shouldAutoExtractLocations()) return;

      // If the caption was already extracted by _scheduleInstagramWebViewExtraction
      // but Maps grounding hasn't run yet, trigger the lighter path here.
      if (_extractedCaption != null && _extractedFromUrl == url) {
        print(
            '🚀 AUTO-SCAN: Caption already available, running Maps grounding...');
        await _autoExtractWithMapsGrounding(url);
        return;
      }

      // Caption not yet available -- _scheduleInstagramWebViewExtraction is
      // likely still running. Let it finish; failures show a hint toast for
      // manual scanning.
      print(
          '🔄 AUTO-SCAN: Instagram caption extraction still pending, deferring to WebView extraction path');
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
        _yelpPreviewFutures[url] =
            _getLocationFromMapsUrl(resolvedUrl).then((result) {
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

  Future<Map<String, dynamic>?> _getLocationFromMapsUrl(String mapsUrl,
      {int? analysisSessionId}) async {
    bool wasCanceled() {
      if (analysisSessionId == null) return false;
      return !_isAnalysisSessionActive(analysisSessionId);
    }

    if (wasCanceled()) return null;

    final String originalUrlKey = mapsUrl.trim();

    if (_businessDataCache.containsKey(originalUrlKey)) {
      return _businessDataCache[originalUrlKey];
    }

    String resolvedUrl = mapsUrl;
    if (!resolvedUrl.contains('google.com/maps')) {
      try {
        final String? expandedUrl = await _resolveShortUrl(resolvedUrl);
        if (wasCanceled()) return null;
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
        if (wasCanceled()) return null;

        if (searchResults.isNotEmpty) {
          placeIdToLookup = searchResults.first['placeId'] as String?;
          if (placeIdToLookup != null && placeIdToLookup.isNotEmpty) {
            foundLocation = await _mapsService.getPlaceDetails(placeIdToLookup);
            if (wasCanceled()) return null;
          } else {}
        } else {}
      } catch (e) {}

      if (foundLocation == null) {
        placeIdToLookup = _extractPlaceIdFromMapsUrl(resolvedUrl);

        if (placeIdToLookup != null && placeIdToLookup.isNotEmpty) {
          try {
            foundLocation = await _mapsService.getPlaceDetails(placeIdToLookup);
            if (wasCanceled()) return null;
          } catch (e) {
            foundLocation = null;
          }
        } else {}
      }

      if (foundLocation != null) {
        final String finalName = foundLocation.getPlaceName();
        final String? finalWebsite = foundLocation.website;

        final provider = context.read<ReceiveShareProvider>();
        if (!wasCanceled() && provider.experienceCards.isNotEmpty) {
          _fillFormWithGoogleMapsData(
            foundLocation,
            finalName,
            finalWebsite ?? '',
            mapsUrl,
            analysisSessionId: analysisSessionId,
          );
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
                  onTap: withHeavyTap(
                      () => Navigator.of(dialogContext).pop(result)),
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
            backgroundColor: AppColors.backgroundColorDark,
            title: const Text('Potential Duplicate Found'),
            // MODIFIED: Dialog content to show both title and address
            content: Text(
                'You already saved an experience named "${foundDuplicate!.name}" located at "${foundDuplicate.location.address ?? 'No address provided'}." Do you want to use this existing experience?'),
            actions: <Widget>[
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.backgroundColorDark,
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

  /// Attempt to detect event information from text content (captions, descriptions, etc.)
  /// Returns ExtractedEventInfo if an event is detected, null otherwise.
  ///
  /// Uses a two-step approach:
  /// 1. Quick regex check for explicit date/time patterns
  /// 2. AI-based detection for natural language event references
  Future<ExtractedEventInfo?> _detectEventFromTextAsync(String? text) async {
    if (text == null || text.isEmpty) return null;

    // Step 1: Try quick regex-based detection first
    final regexResult = _detectEventFromTextRegex(text);
    if (regexResult != null) {
      print(
          '📅 EVENT DETECTION: Found event via regex - ${regexResult.startDateTime}');
      // Try to enrich with Ticketmaster information
      final enrichedResult = await _searchTicketmasterForEvent(regexResult);
      return enrichedResult;
    }

    // Step 2: Check for event-related keywords before calling AI
    final eventKeywords = [
      'event',
      'festival',
      'fair',
      'concert',
      'show',
      'exhibition',
      'happening',
      'this weekend',
      'this saturday',
      'this sunday',
      'next week',
      'tickets',
      'admission',
      'doors open',
      'starts at',
      'march',
      'april',
      'may',
      'june',
      'july',
      'august',
      'september',
      'october',
      'november',
      'december',
      'january',
      'february',
    ];

    final lowerText = text.toLowerCase();
    final hasEventKeywords = eventKeywords.any((kw) => lowerText.contains(kw));

    if (!hasEventKeywords) {
      print(
          '📅 EVENT DETECTION: No event keywords found, skipping AI detection');
      return null;
    }

    // Step 3: Use Gemini AI to detect event information
    try {
      print('📅 EVENT DETECTION: Using AI to analyze text for event info...');
      final geminiService = GeminiService();

      if (!geminiService.isConfigured) {
        print('⚠️ EVENT DETECTION: Gemini not configured');
        return null;
      }

      final result = await geminiService.detectEventFromText(text);
      if (result != null) {
        print(
            '📅 EVENT DETECTION: AI found event - ${result.startDateTime} to ${result.endDateTime}');
        // Try to enrich with Ticketmaster information
        final enrichedResult = await _searchTicketmasterForEvent(result);
        return enrichedResult;
      } else {
        print('📅 EVENT DETECTION: AI did not detect an event');
      }
      return result;
    } catch (e) {
      print('❌ EVENT DETECTION: AI error - $e');
      return null;
    }
  }

  /// Search Ticketmaster for a matching event and enrich the event info with URL
  Future<ExtractedEventInfo> _searchTicketmasterForEvent(
      ExtractedEventInfo eventInfo) async {
    // Only search if we have an event name
    if (eventInfo.eventName == null || eventInfo.eventName!.isEmpty) {
      print('🎫 TICKETMASTER: No event name to search for');
      return eventInfo;
    }

    try {
      print('🎫 TICKETMASTER: Searching for "${eventInfo.eventName}"...');

      // Track the search term that found results
      String? successfulSearchTerm;

      // Try full event name first
      var ticketmasterResult =
          await _ticketmasterService.findEventByNameAndDate(
        eventName: eventInfo.eventName!,
        eventDate: eventInfo.startDateTime,
      );

      if (ticketmasterResult != null && ticketmasterResult.url != null) {
        successfulSearchTerm = eventInfo.eventName;
      } else {
        // If no results, try simplified searches
        // Try extracting just the artist/main name (before " - " or " Live")
        final simplifiedName = _simplifyEventName(eventInfo.eventName!);
        if (simplifiedName != eventInfo.eventName) {
          print('🎫 TICKETMASTER: Trying simplified name: "$simplifiedName"');
          ticketmasterResult =
              await _ticketmasterService.findEventByNameAndDate(
            eventName: simplifiedName,
            eventDate: eventInfo.startDateTime,
          );
          if (ticketmasterResult != null && ticketmasterResult.url != null) {
            successfulSearchTerm = simplifiedName;
          }
        }
      }

      if (ticketmasterResult != null &&
          ticketmasterResult.url != null &&
          successfulSearchTerm != null) {
        print('🎫 TICKETMASTER: Found match - ${ticketmasterResult.name}');
        print('🎫 TICKETMASTER: URL - ${ticketmasterResult.url}');
        print(
            '🎫 TICKETMASTER: Search term that worked: "$successfulSearchTerm"');

        // Return enriched event info with Ticketmaster URL and the search term that worked
        return eventInfo.copyWith(
          ticketmasterUrl: ticketmasterResult.url,
          ticketmasterId: ticketmasterResult.id,
          ticketmasterSearchTerm: successfulSearchTerm,
        );
      } else {
        print('🎫 TICKETMASTER: No matching event found');
      }
    } catch (e) {
      print('🎫 TICKETMASTER: Search error - $e');
    }

    return eventInfo;
  }

  /// Simplify event name for better Ticketmaster search results
  String _simplifyEventName(String eventName) {
    // Remove common suffixes like " - The Mountain Live", " Live", " Tour", etc.
    var simplified = eventName
        .replaceAll(
            RegExp(r'\s*-\s*(The\s+)?\w+\s+(Live|Tour|Concert|Show|Festival).*',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(r'\s+(Live|Tour|Concert|Show|Festival)$',
                caseSensitive: false),
            '')
        .trim();

    // If we stripped too much, use the first part before " - "
    if (simplified.isEmpty || simplified.length < 3) {
      final parts = eventName.split(' - ');
      simplified = parts.first.trim();
    }

    return simplified;
  }

  /// Quick regex-based event detection for explicit date/time patterns
  /// This looks for patterns like:
  /// - "December 31, 2024 at 8:00 PM"
  /// - "Saturday, Jan 15 from 6pm-10pm"
  /// - "Happening on 1/15/2025"
  /// - ISO date formats, etc.
  ExtractedEventInfo? _detectEventFromTextRegex(String text) {
    // Pattern 1: "Month Day, Year at Time" (e.g., "December 31, 2024 at 8:00 PM")
    final monthDayYearTimePattern = RegExp(
      r'(January|February|March|April|May|June|July|August|September|October|November|December)\s+'
      r'(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\s+'
      r'(?:at|@)\s*(\d{1,2}):?(\d{2})?\s*(am|pm|AM|PM)?',
      caseSensitive: false,
    );

    // Pattern 2: "MM/DD/YYYY" or "MM-DD-YYYY" with optional time
    final slashDatePattern = RegExp(
      r'(\d{1,2})[/\-](\d{1,2})[/\-](\d{2,4})\s*(?:(?:at|@)\s*(\d{1,2}):?(\d{2})?\s*(am|pm|AM|PM)?)?',
    );

    // Pattern 3: ISO format "YYYY-MM-DD" or "YYYY-MM-DDTHH:MM"
    final isoPattern = RegExp(
      r'(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}))?',
    );

    // Try to find a date pattern
    DateTime? startDateTime;
    String? rawMatch;

    // Try Pattern 1
    final monthMatch = monthDayYearTimePattern.firstMatch(text);
    if (monthMatch != null) {
      rawMatch = monthMatch.group(0);
      final monthNames = {
        'january': 1,
        'february': 2,
        'march': 3,
        'april': 4,
        'may': 5,
        'june': 6,
        'july': 7,
        'august': 8,
        'september': 9,
        'october': 10,
        'november': 11,
        'december': 12,
      };
      final month = monthNames[monthMatch.group(1)!.toLowerCase()] ?? 1;
      final day = int.tryParse(monthMatch.group(2)!) ?? 1;
      final year = int.tryParse(monthMatch.group(3)!) ?? DateTime.now().year;
      var hour = int.tryParse(monthMatch.group(4) ?? '12') ?? 12;
      final minute = int.tryParse(monthMatch.group(5) ?? '0') ?? 0;
      final ampm = monthMatch.group(6)?.toLowerCase() ?? 'pm';

      if (ampm == 'pm' && hour != 12) hour += 12;
      if (ampm == 'am' && hour == 12) hour = 0;

      startDateTime = DateTime(year, month, day, hour, minute);
    }

    // Try Pattern 2 if Pattern 1 didn't match
    if (startDateTime == null) {
      final slashMatch = slashDatePattern.firstMatch(text);
      if (slashMatch != null) {
        rawMatch = slashMatch.group(0);
        final month = int.tryParse(slashMatch.group(1)!) ?? 1;
        final day = int.tryParse(slashMatch.group(2)!) ?? 1;
        var year = int.tryParse(slashMatch.group(3)!) ?? DateTime.now().year;
        if (year < 100) year += 2000; // Convert 2-digit year

        var hour = int.tryParse(slashMatch.group(4) ?? '12') ?? 12;
        final minute = int.tryParse(slashMatch.group(5) ?? '0') ?? 0;
        final ampm = slashMatch.group(6)?.toLowerCase();

        if (ampm == 'pm' && hour != 12) hour += 12;
        if (ampm == 'am' && hour == 12) hour = 0;

        startDateTime = DateTime(year, month, day, hour, minute);
      }
    }

    // Try Pattern 3 (ISO format)
    if (startDateTime == null) {
      final isoMatch = isoPattern.firstMatch(text);
      if (isoMatch != null) {
        rawMatch = isoMatch.group(0);
        final year = int.tryParse(isoMatch.group(1)!) ?? DateTime.now().year;
        final month = int.tryParse(isoMatch.group(2)!) ?? 1;
        final day = int.tryParse(isoMatch.group(3)!) ?? 1;
        final hour = int.tryParse(isoMatch.group(4) ?? '12') ?? 12;
        final minute = int.tryParse(isoMatch.group(5) ?? '0') ?? 0;

        startDateTime = DateTime(year, month, day, hour, minute);
      }
    }

    // If we found a date, create event info
    if (startDateTime != null) {
      // Check if the date is in the future or recent past (within last 7 days)
      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7));

      if (startDateTime.isAfter(weekAgo)) {
        // Default end time is 2 hours after start
        final endDateTime = startDateTime.add(const Duration(hours: 2));

        return ExtractedEventInfo(
          startDateTime: startDateTime,
          endDateTime: endDateTime,
          confidence: 0.7,
          rawText: rawMatch,
        );
      }
    }

    return null;
  }

  // --- Select Event Dialog for adding experience to event itinerary ---

  /// Helper class to represent either a date header or an event in the list

  // Group events by date and create a list with headers
  List<_EventListItem> _buildEventListWithHeaders(List<Event> events) {
    if (events.isEmpty) return [];

    final List<_EventListItem> items = [];
    DateTime? currentDate;

    for (final event in events) {
      final eventDate = DateTime(
        event.startDateTime.year,
        event.startDateTime.month,
        event.startDateTime.day,
      );

      // Add date header if this is a new day
      if (currentDate == null || !_isSameDay(currentDate, eventDate)) {
        items.add(_EventListItem.header(eventDate));
        currentDate = eventDate;
      }

      items.add(_EventListItem.event(event));
    }

    return items;
  }

  // Format date header as "Tuesday, June 4, 2025"
  String _formatDateHeader(DateTime date) {
    return DateFormat('EEEE, MMMM d, yyyy').format(date);
  }

  // Build date header widget
  Widget _buildEventDateHeader(DateTime date, ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        _formatDateHeader(date),
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white70 : Colors.black87,
          fontSize: 14,
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatEventTime(Event event) {
    final start = DateFormat('h:mm a').format(event.startDateTime);
    final end = DateFormat('h:mm a').format(event.endDateTime);

    if (_isSameDay(event.startDateTime, event.endDateTime)) {
      return '$start - $end';
    } else {
      return '$start - ${DateFormat('MMM d, h:mm a').format(event.endDateTime)}';
    }
  }

  Color _getEventColor(Event event) {
    if (event.colorHex != null && event.colorHex!.isNotEmpty) {
      return _parseEventColorHex(event.colorHex!);
    }
    const colors = [
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

  Color _parseEventColorHex(String hex) {
    String cleaned = hex.replaceAll('#', '');
    if (cleaned.length == 6) {
      cleaned = 'FF$cleaned';
    }
    return Color(int.parse(cleaned, radix: 16));
  }

  Widget _buildSelectEventCard(
      Event event, ThemeData theme, bool isDark, bool isSelected,
      {VoidCallback? onTap}) {
    final cardColor = isDark ? const Color(0xFF2B2930) : Colors.white;
    final borderColor = _getEventColor(event);

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: borderColor.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: borderColor,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(16),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title.isEmpty
                                ? 'Untitled Event'
                                : event.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Google Sans',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 16,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatEventTime(event),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color:
                                      isDark ? Colors.white60 : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                          if (event.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              event.description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isDark ? Colors.white54 : Colors.black45,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (event.experiences.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 16,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${event.experiences.length} experience${event.experiences.length != 1 ? 's' : ''}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w500,
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
            ),
          ),
          // Selection indicator - sage circle with checkmark
          if (isSelected)
            Positioned(
              top: 2,
              right: 12,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.sage,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showSelectEventDialogForCard(ExperienceCardData card) async {
    if (!mounted) return;
    _pauseHelpForDialog();

    final currentUserId = _authService.currentUser?.uid;
    if (currentUserId == null) {
      Fluttertoast.showToast(
        msg: 'Please sign in to select an event',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
      );
      return;
    }

    // Show loading dialog while fetching events
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // Fetch user's events
      final events = await _eventService.getEventsForUser(currentUserId);

      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      // Sort events by start date (most recent first, but future events at top)
      events.sort((a, b) => b.startDateTime.compareTo(a.startDateTime));

      final eventListItems = _buildEventListWithHeaders(events);

      // Find the index to scroll to
      int anchorIndex = -1;

      // First priority: scroll to selected event for this card if there is one
      if (card.selectedEvent != null) {
        for (int i = 0; i < eventListItems.length; i++) {
          if (!eventListItems[i].isHeader &&
              eventListItems[i].event != null &&
              eventListItems[i].event!.id == card.selectedEvent!.id) {
            anchorIndex = i;
            break;
          }
        }
      }

      // Second priority: scroll to first upcoming event
      if (anchorIndex == -1 && events.isNotEmpty) {
        final now = DateTime.now();
        for (int i = 0; i < eventListItems.length; i++) {
          if (!eventListItems[i].isHeader && eventListItems[i].event != null) {
            if (!eventListItems[i].event!.startDateTime.isBefore(now)) {
              anchorIndex = i;
              break;
            }
          }
        }
        // If no upcoming event found, anchor to the last event
        if (anchorIndex == -1 && eventListItems.isNotEmpty) {
          anchorIndex = eventListItems.length - 1;
        }
      }

      final List<GlobalKey> itemKeys =
          List.generate(eventListItems.length, (_) => GlobalKey());

      await showDialog(
        context: context,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          final isDark = theme.brightness == Brightness.dark;
          final ScrollController scrollController = ScrollController();

          // Scroll to anchor
          void scrollToAnchor() {
            if (anchorIndex < 0 || anchorIndex >= itemKeys.length) return;

            void performScroll() {
              // Initial jump to estimated position
              const estimatedItemHeight = 110.0;
              final estimatedOffset = anchorIndex * estimatedItemHeight;
              final maxScroll = scrollController.position.maxScrollExtent;
              scrollController.jumpTo(estimatedOffset.clamp(0.0, maxScroll));

              int retries = 0;
              const maxRetries = 15;

              void tryEnsureVisible() {
                if (retries++ >= maxRetries) return;
                final keyContext = itemKeys[anchorIndex].currentContext;
                if (keyContext != null) {
                  Scrollable.ensureVisible(
                    keyContext,
                    duration: const Duration(milliseconds: 0),
                    curve: Curves.easeOut,
                    alignment: 0.1,
                  );
                } else {
                  Future.delayed(
                      const Duration(milliseconds: 100), tryEnsureVisible);
                }
              }

              Future.delayed(
                  const Duration(milliseconds: 150), tryEnsureVisible);
            }

            WidgetsBinding.instance.addPostFrameCallback((_) {
              performScroll();
            });
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            scrollToAnchor();
          });

          return StatefulBuilder(
            builder: (context, setDialogState) {
              return Dialog(
                backgroundColor: AppColors.backgroundColor,
                insetPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(dialogContext).size.width * 0.95,
                    maxHeight: MediaQuery.of(dialogContext).size.height * 0.7,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                        child: Row(
                          children: [
                            Text(
                              'Select an Event',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Google Sans',
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                triggerHeavyHaptic();
                                scrollController.dispose();
                                Navigator.of(dialogContext).pop();
                              },
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: events.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.event_outlined,
                                      size: 48,
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.black45,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No events yet',
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.black54,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Create events from the Map screen',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black45,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                itemCount: eventListItems.length,
                                itemBuilder: (context, index) {
                                  final item = eventListItems[index];
                                  return Container(
                                    key: itemKeys[index],
                                    child: item.isHeader
                                        ? _buildEventDateHeader(
                                            item.date!, theme, isDark)
                                        : _buildSelectEventCard(
                                            item.event!,
                                            theme,
                                            isDark,
                                            card.selectedEvent?.id ==
                                                item.event!.id,
                                            onTap: () {
                                              triggerHeavyHaptic();
                                              final tappedEvent = item.event!;

                                              if (card.selectedEvent?.id ==
                                                  tappedEvent.id) {
                                                // Deselect if already selected
                                                setState(() {
                                                  card.selectedEvent = null;
                                                });
                                                setDialogState(() {});
                                                Fluttertoast.showToast(
                                                  msg: 'Event deselected',
                                                  toastLength:
                                                      Toast.LENGTH_SHORT,
                                                  gravity: ToastGravity.BOTTOM,
                                                );
                                              } else {
                                                // Select the event for this card
                                                setState(() {
                                                  card.selectedEvent =
                                                      tappedEvent;
                                                });
                                                setDialogState(() {});

                                                // Close dialog and show toast
                                                Navigator.of(dialogContext)
                                                    .pop();
                                                Fluttertoast.showToast(
                                                  msg:
                                                      'Experience will be saved to "${tappedEvent.title}"',
                                                  toastLength:
                                                      Toast.LENGTH_LONG,
                                                  gravity: ToastGravity.BOTTOM,
                                                );
                                              }
                                            },
                                          ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog
      Fluttertoast.showToast(
        msg: 'Error loading events: $e',
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
      );
    } finally {
      _resumeHelpAfterDialog();
    }
  }
  // --- End Select Event Dialog ---
}

// Helper class to represent either a date header or an event
class _EventListItem {
  final DateTime? date;
  final Event? event;
  final bool isHeader;

  _EventListItem.header(this.date)
      : event = null,
        isHeader = true;
  _EventListItem.event(this.event)
      : date = null,
        isHeader = false;
}

class InstagramPreviewWrapper extends StatefulWidget {
  final String url;
  final Future<void> Function(String) launchUrlCallback;
  final bool isHelpMode;
  final void Function(bool, String)?
      onExpansionChanged; // MODIFIED to include URL
  final void Function(String)?
      onPageFinished; // Callback when preview finishes loading
  final bool Function(ReceiveShareHelpTargetId id, BuildContext ctx)? onHelpTap;

  const InstagramPreviewWrapper({
    super.key, // Ensure super.key is passed
    required this.url,
    required this.launchUrlCallback,
    this.isHelpMode = false,
    this.onExpansionChanged,
    this.onPageFinished,
    this.onHelpTap,
  });

  @override
  _InstagramPreviewWrapperState createState() =>
      _InstagramPreviewWrapperState();
}

class _InstagramPreviewWrapperState extends State<InstagramPreviewWrapper> {
  bool _isExpanded = false;
  bool _isDisposed = false;
  inapp.InAppWebViewController? _controller;

  /// Display mode: true = web view, false = default (oEmbed HTML)
  /// This is temporary/local state only - does NOT persist to settings
  bool _isWebViewMode = false;

  /// Dynamic content height reported by the WebView
  double? _dynamicContentHeight;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  /// Toggle between default (oEmbed) and web view modes
  /// This is temporary and does not persist to settings
  void _toggleDisplayMode() {
    _safeSetState(() {
      _isWebViewMode = !_isWebViewMode;
    });
  }

  /// Called when user taps "Switch to Web View" in error state
  /// This is temporary and does not persist to settings
  void _handleRequestWebViewMode() {
    _safeSetState(() {
      _isWebViewMode = true;
    });
  }

  // Safe setState that checks if the widget is still mounted
  void _safeSetState(Function fn) {
    if (mounted && !_isDisposed) {
      setState(() {
        fn();
      });
    }
  }

  bool _helpTap(ReceiveShareHelpTargetId id, BuildContext ctx) {
    if (widget.onHelpTap != null) return widget.onHelpTap!(id, ctx);
    return false;
  }

  // Safe callback for webview
  void _handleWebViewCreated(inapp.InAppWebViewController controller) {
    if (!mounted || _isDisposed) return;
    _controller = controller;
  }

  /// Handle content height changes from the WebView
  void _handleContentHeightChanged(double height) {
    if (!mounted || _isDisposed) return;

    // Only update if height is significantly different to avoid jitter
    // and ensure we have a reasonable minimum height
    if (_dynamicContentHeight == null ||
        (height - _dynamicContentHeight!).abs() > 20) {
      // Ensure minimum height of 400 to avoid tiny previews
      final newHeight = height < 400.0 ? 400.0 : height;

      _safeSetState(() {
        _dynamicContentHeight = newHeight;
      });
    }
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

  /// Extract text content from the Instagram WebView
  ///
  /// This is useful as a fallback when oEmbed doesn't return caption data.
  /// For Reels especially, the caption may only be available after JavaScript renders.
  Future<String?> extractPageContent() async {
    if (_controller == null) {
      print('⚠️ INSTAGRAM WRAPPER: Controller is null, cannot extract content');
      return null;
    }

    try {
      print('📸 INSTAGRAM WRAPPER: Extracting page content...');

      // Try to extract text from the WebView
      final result = await _controller!.evaluateJavascript(source: '''
        (function() {
          // Try to get text from the entire document
          var bodyText = document.body ? document.body.innerText : '';
          
          // Also try to get specific Instagram embed content
          var blockquotes = document.querySelectorAll('blockquote');
          var blockquoteText = '';
          blockquotes.forEach(function(bq) {
            blockquoteText += bq.innerText + ' ';
          });
          
          // Try to get iframe content if accessible
          var iframes = document.querySelectorAll('iframe');
          var iframeText = '';
          iframes.forEach(function(iframe) {
            try {
              if (iframe.contentDocument && iframe.contentDocument.body) {
                iframeText += iframe.contentDocument.body.innerText + ' ';
              }
            } catch(e) {
              // Cross-origin iframe, can't access
            }
          });
          
          // Combine all text sources
          var allText = bodyText + ' ' + blockquoteText + ' ' + iframeText;
          
          // Clean up whitespace
          allText = allText.replace(/\\s+/g, ' ').trim();
          
          return allText;
        })();
      ''');

      if (result != null &&
          result.toString().isNotEmpty &&
          result.toString() != 'null') {
        final content = result.toString().trim();
        print(
            '✅ INSTAGRAM WRAPPER: Extracted content (${content.length} chars)');
        if (content.length > 200) {
          print(
              '📸 INSTAGRAM WRAPPER: Content preview: ${content.substring(0, 200)}...');
        }
        return content;
      } else {
        print('⚠️ INSTAGRAM WRAPPER: No content extracted from WebView');
        return null;
      }
    } catch (e) {
      print('❌ INSTAGRAM WRAPPER: Content extraction failed: $e');
      return null;
    }
  }

  // Safe callback for page finished
  void _handlePageFinished(String url) {
    // Notify parent when preview finishes loading (for auto-scan)
    widget.onPageFinished?.call(url);
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
    // Use dynamic height if available for default view, otherwise fallback to 910.0
    // For expanded view, use fixed large height
    final double height =
        _isExpanded ? 2800.0 : (_dynamicContentHeight ?? 910.0);

    // Use a consistent key to prevent widget recreation across rebuilds
    final widgetKey = ValueKey('instagram_preview_${widget.url}');

    // Pass local mode override to InstagramWebView
    // When null, widget uses settings; when set, overrides settings temporarily
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        instagram_widget.InstagramWebView(
          key: widgetKey,
          url: widget.url,
          height: height,
          launchUrlCallback: _handleUrlLaunch,
          onWebViewCreated: _handleWebViewCreated,
          onPageFinished: _handlePageFinished,
          onContentHeightChanged: _handleContentHeightChanged,
          overrideWebViewMode: _isWebViewMode,
          onRequestWebViewMode: _handleRequestWebViewMode,
          isHelpMode: widget.isHelpMode,
          onHelpTap: widget.onHelpTap,
        ),
        Container(height: 8, color: AppColors.backgroundColor),
        _buildBottomControls(),
        Container(height: 8, color: AppColors.backgroundColor),
      ],
    );
  }

  Widget _buildBottomControls() {
    return Container(
      color: AppColors.backgroundColor,
      height: 48,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Builder(builder: (toggleCtx) {
                return GestureDetector(
                  onTap: () {
                    if (_helpTap(
                        ReceiveShareHelpTargetId.previewDisplayModeToggle,
                        toggleCtx)) {
                      return;
                    }
                    _toggleDisplayMode();
                  },
                  child: Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _isWebViewMode
                          ? AppColors.teal.withOpacity(0.15)
                          : AppColors.sage.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isWebViewMode
                            ? AppColors.teal.withOpacity(0.5)
                            : AppColors.sage.withOpacity(0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isWebViewMode ? Icons.language : Icons.code,
                          size: 14,
                          color:
                              _isWebViewMode ? AppColors.teal : AppColors.sage,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isWebViewMode ? 'Web view' : 'Default view',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: _isWebViewMode
                                ? AppColors.teal
                                : AppColors.sage,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          Builder(builder: (openExternalCtx) {
            return IconButton(
              icon: const Icon(FontAwesomeIcons.instagram),
              color: const Color(0xFFE1306C),
              iconSize: 32,
              tooltip: 'Open in Instagram',
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
              onPressed: () {
                if (_helpTap(ReceiveShareHelpTargetId.previewOpenExternalButton,
                    openExternalCtx)) {
                  return;
                }
                _handleUrlLaunch(widget.url);
              },
            );
          }),
          if (_isWebViewMode)
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Builder(builder: (expandCtx) {
                  return IconButton(
                    icon: Icon(
                        _isExpanded ? Icons.fullscreen_exit : Icons.fullscreen),
                    iconSize: 24,
                    color: AppColors.teal,
                    tooltip: _isExpanded ? 'Collapse' : 'Expand',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    onPressed: () {
                      if (_helpTap(ReceiveShareHelpTargetId.previewExpandButton,
                          expandCtx)) {
                        return;
                      }
                      _safeSetState(() {
                        _isExpanded = !_isExpanded;
                        widget.onExpansionChanged
                            ?.call(_isExpanded, widget.url);
                      });
                    },
                  );
                }),
              ),
            )
          else
            const Expanded(child: SizedBox()),
        ],
      ),
    );
  }
}

/// Result from the multi-location selection dialog
class _MultiLocationSelectionResult {
  final List<ExtractedLocationData> selectedLocations;
  final Map<ExtractedLocationData, Experience> selectedDuplicates;

  /// Event info if detected (passed through for post-save handling)
  final ExtractedEventInfo? eventInfo;

  /// Whether the user requested a deep scan
  final bool deepScanRequested;

  _MultiLocationSelectionResult({
    required this.selectedLocations,
    required this.selectedDuplicates,
    this.eventInfo,
    this.deepScanRequested = false,
  });

  /// Factory for creating a deep scan request result
  /// [confirmedLocations] are locations the user has selected/confirmed from quick scan
  /// [confirmedDuplicates] maps confirmed locations to their existing experiences
  factory _MultiLocationSelectionResult.deepScanRequest({
    List<ExtractedLocationData> confirmedLocations = const [],
    Map<ExtractedLocationData, Experience> confirmedDuplicates = const {},
  }) {
    return _MultiLocationSelectionResult(
      selectedLocations: confirmedLocations,
      selectedDuplicates: confirmedDuplicates,
      deepScanRequested: true,
    );
  }
}

/// Dialog for selecting multiple locations from AI extraction results
/// If event info is provided, shows a second page for event designation
class _MultiLocationSelectionDialog extends StatefulWidget {
  final List<ExtractedLocationData> locations;
  final Map<int, Experience> duplicates; // index -> existing Experience
  /// Optional event info detected from the content
  final ExtractedEventInfo? detectedEventInfo;

  /// Whether this is showing results from deep scan (hides deep scan option if true)
  final bool isDeepScan;

  /// Callback when user requests deep scan
  final VoidCallback? onDeepScanRequested;

  /// Optional raw scanned text to show in expandable section
  final String? scannedText;

  const _MultiLocationSelectionDialog({
    required this.locations,
    this.duplicates = const {},
    this.detectedEventInfo,
    this.isDeepScan = false,
    this.onDeepScanRequested,
    this.scannedText,
  });

  @override
  State<_MultiLocationSelectionDialog> createState() =>
      _MultiLocationSelectionDialogState();
}

class _MultiLocationSelectionDialogState
    extends State<_MultiLocationSelectionDialog> with TickerProviderStateMixin {
  late Set<int> _selectedIndices;

  /// Maps location index to business status from Places API
  final Map<int, String?> _businessStatusMap = {};

  /// Service for fetching place details
  final GoogleMapsService _mapsService = GoogleMapsService();

  /// Whether the scanned text section is expanded
  bool _isScannedTextExpanded = false;

  /// Confidence threshold - locations below this should be verified by user
  static const double _lowConfidenceThreshold = 0.80;

  // Dialog-local help mode
  late final HelpFlowState<ReceiveShareHelpTargetId> _dialogHelp;
  late final AnimationController _dialogSpotlight;
  final GlobalKey _dialogHelpBtnKey = GlobalKey();
  final GlobalKey<HelpBubbleState> _dialogBubbleKey = GlobalKey();
  bool _dialogIsTyping = false;

  void _toggleDialogHelp() {
    triggerHeavyHaptic();
    setState(() {
      final nowActive = _dialogHelp.toggle();
      if (nowActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final helpCtx = _dialogHelpBtnKey.currentContext;
          if (helpCtx != null) {
            _showDialogHelpFor(ReceiveShareHelpTargetId.helpButton, helpCtx);
          } else {
            setState(() {
              _dialogHelp.showTarget(
                ReceiveShareHelpTargetId.helpButton,
                _dialogFallbackTargetRect(),
              );
              _dialogIsTyping = true;
            });
          }
        });
      }
    });
  }

  void _showDialogHelpFor(ReceiveShareHelpTargetId id, BuildContext ctx) {
    final rect = _resolveTargetRect(ctx);
    if (rect == null) return;
    setState(() {
      _dialogHelp.showTarget(id, rect);
      _dialogIsTyping = true;
    });
  }

  Rect _dialogFallbackTargetRect() {
    final size = MediaQuery.of(context).size;
    final width = (size.width * 0.4).clamp(96.0, 220.0);
    const height = 44.0;
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: width,
      height: height,
    );
  }

  bool _tryDialogHelpTap(ReceiveShareHelpTargetId id, BuildContext ctx) {
    if (!_dialogHelp.isActive) return false;
    triggerHeavyHaptic();
    _showDialogHelpFor(id, ctx);
    return true;
  }

  void _advanceDialogHelp() {
    setState(() {
      _dialogHelp.advance();
      if (_dialogHelp.hasActiveTarget) _dialogIsTyping = true;
    });
  }

  void _dismissDialogHelp() {
    setState(() {
      _dialogHelp.dismiss();
      _dialogIsTyping = false;
    });
  }

  void _onDialogHelpBarrierTap() {
    if (_dialogIsTyping) {
      _dialogBubbleKey.currentState?.skipTypewriter();
    } else {
      _advanceDialogHelp();
    }
  }

  Widget _buildDialogHelpOverlay() {
    final flow = _dialogHelp;
    final spec = flow.activeSpec;
    final step = flow.activeHelpStep;
    return Positioned.fill(
      child: Builder(
        builder: (overlayCtx) {
          final localTargetRect =
              _dialogTargetRectInOverlay(overlayCtx, flow.activeTargetRect);
          return AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: flow.hasActiveTarget ? 1.0 : 0.0,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _onDialogHelpBarrierTap,
              child: Stack(children: [
                if (localTargetRect != null)
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _dialogSpotlight,
                      builder: (context, _) => CustomPaint(
                        painter: HelpSpotlightPainter(
                          targetRect: localTargetRect,
                          glowProgress: _dialogSpotlight.value,
                        ),
                      ),
                    ),
                  ),
                if (spec != null && step != null && localTargetRect != null)
                  HelpBubble(
                    key: _dialogBubbleKey,
                    text: step.text,
                    instruction: step.instruction,
                    isLastStep: flow.isLastStep,
                    targetRect: localTargetRect,
                    onAdvance: _advanceDialogHelp,
                    onDismiss: _dismissDialogHelp,
                    onTypingStarted: () {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _dialogIsTyping = true);
                      });
                    },
                    onTypingFinished: () {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _dialogIsTyping = false);
                      });
                    },
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Rect? _dialogTargetRectInOverlay(
      BuildContext overlayContext, Rect? globalRect) {
    if (globalRect == null) return null;
    final renderObject = overlayContext.findRenderObject();
    final overlayBox = renderObject is RenderBox && renderObject.hasSize
        ? renderObject
        : overlayContext.findAncestorRenderObjectOfType<RenderBox>();
    if (overlayBox == null || !overlayBox.hasSize) return null;
    final topLeft = overlayBox.globalToLocal(globalRect.topLeft);
    final bottomRight = overlayBox.globalToLocal(globalRect.bottomRight);
    return Rect.fromPoints(topLeft, bottomRight);
  }

  @override
  void initState() {
    super.initState();
    _dialogHelp = HelpFlowState<ReceiveShareHelpTargetId>(
        content: receiveShareHelpContent);
    _dialogSpotlight = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    // Start with all valid locations selected (those with coordinates)
    _selectedIndices = Set<int>.from(widget.locations
        .asMap()
        .entries
        .where((e) => e.value.coordinates != null)
        .map((e) => e.key));
    _fetchBusinessStatuses();
  }

  @override
  void dispose() {
    _dialogSpotlight.dispose();
    super.dispose();
  }

  /// Fetch business status for all locations that have a placeId
  Future<void> _fetchBusinessStatuses() async {
    for (int i = 0; i < widget.locations.length; i++) {
      final location = widget.locations[i];
      if (location.placeId != null && location.placeId!.isNotEmpty) {
        // Fetch in parallel but update UI as each completes
        _fetchBusinessStatusForIndex(i, location.placeId!);
      }
    }
  }

  /// Fetch business status for a single location by index
  Future<void> _fetchBusinessStatusForIndex(int index, String placeId) async {
    try {
      // Strip 'places/' prefix if present (comes from grounding chunks)
      String cleanPlaceId = placeId;
      if (placeId.startsWith('places/')) {
        cleanPlaceId = placeId.substring(7); // Remove 'places/' prefix
      }

      final detailsMap = await _mapsService.fetchPlaceDetailsData(cleanPlaceId);
      final businessStatus = detailsMap?['businessStatus'] as String?;
      if (mounted) {
        setState(() {
          _businessStatusMap[index] = businessStatus;
        });
      }
    } catch (e) {
      print('⚠️ BUSINESS STATUS: Error fetching for index $index: $e');
    }
  }

  /// Check if a location at index is permanently closed
  bool _isPermanentlyClosed(int index) {
    return _businessStatusMap[index] == 'CLOSED_PERMANENTLY';
  }

  bool get _hasEventInfo => widget.detectedEventInfo != null;

  /// Count of valid locations (those with coordinates - excludes "No results" items)
  int get _validLocationCount =>
      widget.locations.where((loc) => loc.coordinates != null).length;

  /// Indices of valid locations (those with coordinates)
  Set<int> get _validLocationIndices => Set<int>.from(widget.locations
      .asMap()
      .entries
      .where((e) => e.value.coordinates != null)
      .map((e) => e.key));

  bool get _allSelected =>
      _selectedIndices.length == _validLocationCount && _validLocationCount > 0;
  bool get _noneSelected => _selectedIndices.isEmpty;

  int get _duplicateCount => widget.duplicates.length;
  int get _selectedDuplicateCount =>
      _selectedIndices.where((i) => widget.duplicates.containsKey(i)).length;
  int get _selectedNewCount =>
      _selectedIndices.length - _selectedDuplicateCount;

  /// Count of locations with low confidence that need verification
  int get _lowConfidenceCount => widget.locations
      .where((loc) =>
          loc.confidence < _lowConfidenceThreshold || loc.needsConfirmation)
      .length;

  /// Check if a specific location has low confidence
  bool _isLowConfidence(ExtractedLocationData location) {
    return location.confidence < _lowConfidenceThreshold ||
        location.needsConfirmation;
  }

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selectedIndices.clear();
      } else {
        // Only select valid locations (those with coordinates)
        _selectedIndices = Set<int>.from(_validLocationIndices);
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

  void _finishSelection() {
    // Sort indices and map to locations
    final sortedIndices = _selectedIndices.toList()..sort();
    final allSelectedLocations =
        sortedIndices.map((i) => widget.locations[i]).toList();

    // Filter out locations without coordinates (not found in Google Places)
    final validLocations =
        allSelectedLocations.where((loc) => loc.coordinates != null).toList();
    final skippedLocations =
        allSelectedLocations.where((loc) => loc.coordinates == null).toList();

    // Show warning if any locations were skipped
    if (skippedLocations.isNotEmpty) {
      final skippedNames =
          skippedLocations.map((loc) => '"${loc.name}"').join(', ');
      Fluttertoast.showToast(
        msg:
            '⚠️ Skipped ${skippedLocations.length} location(s) not found in Google Places: $skippedNames',
        toastLength: Toast.LENGTH_LONG,
        backgroundColor: Colors.orange[700],
      );
    }

    // If no valid locations remain, don't proceed
    if (validLocations.isEmpty) {
      Fluttertoast.showToast(
        msg:
            '❌ No valid locations selected. Please select locations that were found in Google Places.',
        toastLength: Toast.LENGTH_LONG,
        backgroundColor: Colors.red[700],
      );
      return;
    }

    // Build map of selected locations that are duplicates (only for valid locations)
    final selectedDuplicates = <ExtractedLocationData, Experience>{};
    for (final index in sortedIndices) {
      final loc = widget.locations[index];
      if (loc.coordinates != null && widget.duplicates.containsKey(index)) {
        selectedDuplicates[loc] = widget.duplicates[index]!;
      }
    }

    Navigator.pop(
        context,
        _MultiLocationSelectionResult(
          selectedLocations: validLocations,
          selectedDuplicates: selectedDuplicates,
          // Pass through event info for post-save handling
          eventInfo: widget.detectedEventInfo,
        ));
  }

  /// Get the currently selected valid locations (for deep scan request)
  /// Returns only locations with coordinates that are selected
  List<ExtractedLocationData> _getConfirmedLocations() {
    final sortedIndices = _selectedIndices.toList()..sort();
    return sortedIndices
        .map((i) => widget.locations[i])
        .where((loc) => loc.coordinates != null)
        .toList();
  }

  /// Get duplicates map for confirmed locations (for deep scan request)
  Map<ExtractedLocationData, Experience> _getConfirmedDuplicates() {
    final sortedIndices = _selectedIndices.toList()..sort();
    final confirmedDuplicates = <ExtractedLocationData, Experience>{};
    for (final index in sortedIndices) {
      final loc = widget.locations[index];
      if (loc.coordinates != null && widget.duplicates.containsKey(index)) {
        confirmedDuplicates[loc] = widget.duplicates[index]!;
      }
    }
    return confirmedDuplicates;
  }

  /// Request deep scan while preserving confirmed selections
  void _requestDeepScanWithConfirmed() {
    Navigator.pop(
      context,
      _MultiLocationSelectionResult.deepScanRequest(
        confirmedLocations: _getConfirmedLocations(),
        confirmedDuplicates: _getConfirmedDuplicates(),
      ),
    );
  }

  void _handleDialogCancelTap(BuildContext ctx) {
    if (_tryDialogHelpTap(
        ReceiveShareHelpTargetId.multiLocationCancelButton, ctx)) {
      return;
    }
    Navigator.pop(context, null);
  }

  void _handleDialogDeepScanTap(BuildContext ctx) {
    if (_tryDialogHelpTap(
        ReceiveShareHelpTargetId.multiLocationDeepScanButton, ctx)) {
      return;
    }
    _requestDeepScanWithConfirmed();
  }

  VoidCallback? _buildDialogConfirmAction(BuildContext ctx) {
    if (_dialogHelp.isActive) {
      return () {
        _tryDialogHelpTap(
            ReceiveShareHelpTargetId.multiLocationConfirmButton, ctx);
      };
    }
    if (_noneSelected) return null;
    return _finishSelection;
  }

  @override
  Widget build(BuildContext context) {
    // Using Dialog with custom structure instead of AlertDialog
    // because AlertDialog's actions don't handle Expanded widgets properly,
    // causing layout issues specifically in iOS release builds with Impeller.
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: AppColors.backgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width - 32,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLocationTitle(),
                  const SizedBox(height: 16),
                  Flexible(
                    child: _buildLocationSelectionPage(),
                  ),
                  const SizedBox(height: 16),
                  _buildLocationActionsRow(),
                ],
              ),
            ),
            if (_dialogHelp.isActive && _dialogHelp.hasActiveTarget)
              _buildDialogHelpOverlay(),
          ],
        ),
      ),
    );
  }

  /// Build actions as a simple row/column instead of AlertDialog actions
  Widget _buildLocationActionsRow() {
    final bool isEmpty = widget.locations.isEmpty;

    // Special handling for empty state - show prominent Deep Scan button
    if (isEmpty && !widget.isDeepScan && widget.onDeepScanRequested != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Builder(
            builder: (closeCtx) => TextButton(
              onPressed: () => _handleDialogCancelTap(closeCtx),
              child: const Text('Close'),
            ),
          ),
          const SizedBox(width: 8),
          Builder(
            builder: (deepScanCtx) => ElevatedButton.icon(
              onPressed: () => _handleDialogDeepScanTap(deepScanCtx),
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Run Deep Scan'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.sage,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      );
    }

    // Empty state from deep scan - just show close button
    if (isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Builder(
            builder: (closeCtx) => TextButton(
              onPressed: () => _handleDialogCancelTap(closeCtx),
              child: const Text('Close'),
            ),
          ),
        ],
      );
    }

    // Normal state with locations
    if (!widget.isDeepScan && widget.onDeepScanRequested != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Deep scan info text and button
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  _selectedIndices.isEmpty
                      ? 'Not what you expected?'
                      : 'Selected locations will be kept',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Builder(
                  builder: (deepScanCtx) => OutlinedButton.icon(
                    onPressed: () => _handleDialogDeepScanTap(deepScanCtx),
                    icon: const Icon(Icons.search, size: 16),
                    label: const Text('Try Deep Scan'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.sage,
                      side: BorderSide(color: AppColors.sage),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Main action buttons row
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Builder(
                builder: (cancelCtx) => TextButton(
                  onPressed: () => _handleDialogCancelTap(cancelCtx),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Builder(
                builder: (confirmCtx) => ElevatedButton(
                  onPressed: _buildDialogConfirmAction(confirmCtx),
                  child: Text(_buildButtonText()),
                ),
              ),
            ],
          ),
        ],
      );
    }

    // When deep scan option is not shown, just show Cancel and Create buttons
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Builder(
          builder: (cancelCtx) => TextButton(
            onPressed: () => _handleDialogCancelTap(cancelCtx),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 8),
        Builder(
          builder: (confirmCtx) => ElevatedButton(
            onPressed: _buildDialogConfirmAction(confirmCtx),
            child: Text(_buildButtonText()),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationTitle() {
    final primaryColor = Theme.of(context).primaryColor;
    final bool isEmpty = _validLocationCount == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              isEmpty ? Icons.search_off : Icons.location_on,
              color: isEmpty ? Colors.orange[700] : AppColors.sage,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isEmpty
                    ? 'No Locations Found'
                    : _validLocationCount == 1
                        ? '1 Location Found'
                        : '$_validLocationCount Locations Found',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _dialogHelp.isActive
                ? IconButton(
                    key: _dialogHelpBtnKey,
                    icon: Icon(Icons.help, color: AppColors.teal),
                    tooltip: 'Exit Help Mode',
                    onPressed: _toggleDialogHelp,
                    visualDensity: VisualDensity.compact,
                  )
                : IconButton(
                    key: _dialogHelpBtnKey,
                    icon: Icon(Icons.help_outline, color: Colors.grey[400]),
                    tooltip: 'Help',
                    onPressed: _toggleDialogHelp,
                    visualDensity: VisualDensity.compact,
                  ),
          ],
        ),
        if (_lowConfidenceCount > 0) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: primaryColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '$_lowConfidenceCount location${_lowConfidenceCount == 1 ? '' : 's'} may need verification',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                    color: primaryColor,
                  ),
                ),
              ),
            ],
          ),
        ],
        // Show event detected indicator
        if (_hasEventInfo) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.plum.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.plum.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.event, size: 16, color: AppColors.plum),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Event detected! You can save it after adding these locations.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.plum,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLocationSelectionPage() {
    final primaryColor = Theme.of(context).primaryColor;
    final bool isEmpty = widget.locations.isEmpty;

    // Show empty state message when no locations found
    if (isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 16),
          Icon(
            Icons.location_searching,
            size: 48,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Auto-scan couldn\'t find any locations in this content.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.sage.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.sage.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb_outline,
                        size: 16, color: AppColors.sage),
                    const SizedBox(width: 8),
                    Text(
                      'Try Deep Scan',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.sage,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Deep Scan analyzes screenshots and visible text to find locations that auto-scan missed. Your selected locations will be preserved.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          // Expandable scanned text section for empty state too
          if (widget.scannedText != null && widget.scannedText!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildScannedTextSection(),
          ],
          const SizedBox(height: 8),
        ],
      );
    }

    // Using Column without mainAxisSize.min since parent is Flexible.
    // This allows proper constraint propagation in iOS release builds.
    return Column(
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.teal.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.teal.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                Icon(Icons.bookmark, size: 16, color: AppColors.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$_duplicateCount already saved',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.teal,
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
        Builder(
          builder: (selectAllCtx) => InkWell(
            onTap: _dialogHelp.isActive
                ? () => _tryDialogHelpTap(
                      ReceiveShareHelpTargetId.multiLocationCheckbox,
                      selectAllCtx,
                    )
                : withHeavyTap(_toggleAll),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Builder(
                    builder: (selectAllCheckboxCtx) => Checkbox(
                      value: _allSelected,
                      tristate: true,
                      onChanged: (_) {
                        if (_tryDialogHelpTap(
                            ReceiveShareHelpTargetId.multiLocationCheckbox,
                            selectAllCheckboxCtx)) {
                          return;
                        }
                        _toggleAll();
                      },
                      activeColor: AppColors.sage,
                    ),
                  ),
                  Text(
                    _allSelected ? 'Deselect All' : 'Select All',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.sage,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.sage.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_selectedIndices.length}/$_validLocationCount',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.sage,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        const SizedBox(height: 8),
        // Scrollable list of locations - use Flexible to fill remaining space
        // within the parent Flexible wrapper
        Flexible(
          child: ListView.builder(
            itemCount: widget.locations.length,
            itemBuilder: (context, index) {
              final location = widget.locations[index];
              final isSelected = _selectedIndices.contains(index);
              final isDuplicate = widget.duplicates.containsKey(index);
              final existingExp = widget.duplicates[index];
              final isLowConfidence = _isLowConfidence(location);
              final hasNoCoordinates = location.coordinates == null;
              final isDisabled =
                  hasNoCoordinates; // Can't select locations without coordinates
              final isPermanentlyClosed = _isPermanentlyClosed(index);

              return Builder(
                builder: (rowCtx) => InkWell(
                  onTap: _dialogHelp.isActive
                      ? () => _tryDialogHelpTap(
                            ReceiveShareHelpTargetId.multiLocationCheckbox,
                            rowCtx,
                          )
                      : (isDisabled
                          ? null
                          : withHeavyTap(() => _toggleLocation(index))),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      // Gray out disabled items, use primaryColor for permanently closed
                      color: isDisabled
                          ? Colors.red.withOpacity(0.05)
                          : isSelected
                              ? (isPermanentlyClosed
                                  ? primaryColor.withOpacity(0.05)
                                  : isLowConfidence
                                      ? primaryColor.withOpacity(0.05)
                                      : isDuplicate
                                          ? AppColors.teal.withOpacity(0.12)
                                          : AppColors.sage.withOpacity(0.08))
                              : null,
                      borderRadius: BorderRadius.circular(8),
                      border:
                          (isPermanentlyClosed || isLowConfidence) && isSelected
                              ? Border.all(
                                  color: primaryColor.withOpacity(0.3),
                                  width: 1)
                              : isDisabled
                                  ? Border.all(
                                      color: Colors.red.withOpacity(0.2),
                                      width: 1)
                                  : null,
                    ),
                    child: Row(
                      children: [
                        // Show checkbox only if location is not disabled
                        if (!isDisabled) ...[
                          Builder(
                            builder: (locationCheckboxCtx) => Checkbox(
                              value: isSelected,
                              onChanged: (_) {
                                if (_tryDialogHelpTap(
                                    ReceiveShareHelpTargetId
                                        .multiLocationCheckbox,
                                    locationCheckboxCtx)) {
                                  return;
                                }
                                _toggleLocation(index);
                              },
                              // Permanently closed and low confidence use primaryColor
                              activeColor:
                                  isPermanentlyClosed || isLowConfidence
                                      ? primaryColor
                                      : isDuplicate
                                          ? AppColors.teal
                                          : AppColors.sage,
                            ),
                          ),
                        ] else ...[
                          // Show empty space to align with other items
                          const SizedBox(width: 48),
                        ],
                        Icon(
                          // Show error icon for disabled items, store_off for closed, otherwise based on confidence
                          isDisabled
                              ? Icons.error_outline
                              : isPermanentlyClosed
                                  ? Icons.store_outlined
                                  : isLowConfidence
                                      ? Icons.help_outline
                                      : isDuplicate
                                          ? Icons.bookmark
                                          : Icons.place,
                          size: 18,
                          color: isDisabled
                              ? Colors.red[700]
                              : isPermanentlyClosed || isLowConfidence
                                  ? primaryColor
                                  : isDuplicate
                                      ? AppColors.teal
                                      : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // For disabled items (no coordinates), show "No result for..."
                              if (isDisabled)
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'No result for "${location.originalQuery ?? location.name}"',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: Colors.red[700],
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              else
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
                                        margin: const EdgeInsets.only(left: 4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color:
                                              AppColors.teal.withOpacity(0.18),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Saved',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.teal,
                                          ),
                                        ),
                                      ),
                                    // Show closed badge for permanently closed locations
                                    if (isPermanentlyClosed)
                                      Container(
                                        margin: const EdgeInsets.only(left: 4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: primaryColor.withOpacity(0.12),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                            color:
                                                primaryColor.withOpacity(0.35),
                                            width: 1,
                                          ),
                                        ),
                                        child: Text(
                                          'Closed',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: primaryColor,
                                          ),
                                        ),
                                      ),
                                    // Show verify badge for low confidence locations (even if also a duplicate)
                                    if (isLowConfidence)
                                      Container(
                                        margin: const EdgeInsets.only(left: 4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: primaryColor.withOpacity(0.12),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                            color:
                                                primaryColor.withOpacity(0.35),
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.warning_amber_rounded,
                                              size: 10,
                                              color: primaryColor,
                                            ),
                                            const SizedBox(width: 2),
                                            Text(
                                              'Verify',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: primaryColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    // Show confident badge for sage-colored locations (not duplicate, not low confidence, not closed)
                                    if (!isDuplicate &&
                                        !isLowConfidence &&
                                        !isPermanentlyClosed)
                                      Container(
                                        margin: const EdgeInsets.only(left: 4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color:
                                              AppColors.sage.withOpacity(0.18),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Confident',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.sage,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              // Show details only for enabled items
                              if (!isDisabled) ...[
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
                                // Show original scanned text if different from resolved name
                                if (location.originalQuery != null &&
                                    location.originalQuery!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.search,
                                          size: 11,
                                          color: Colors.grey[500],
                                        ),
                                        const SizedBox(width: 3),
                                        Expanded(
                                          child: Text(
                                            'From: "${location.originalQuery}"',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontStyle: FontStyle.italic,
                                              color: Colors.grey[500],
                                            ),
                                          ),
                                        ),
                                      ],
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
                                      color: AppColors.teal,
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
                                      color: primaryColor,
                                    ),
                                  ),
                              ] else ...[
                                // For disabled items, show simplified error message
                                const SizedBox(height: 2),
                                Text(
                                  'Not found in Google Places',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.red[600],
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Expandable scanned text section
        if (widget.scannedText != null && widget.scannedText!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildScannedTextSection(),
        ],
      ],
    );
  }

  /// Build the expandable scanned text section
  Widget _buildScannedTextSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with expand/collapse tap area
          Builder(
            builder: (scannedTextCtx) => InkWell(
              onTap: () {
                if (_tryDialogHelpTap(
                    ReceiveShareHelpTargetId.multiLocationScannedTextToggle,
                    scannedTextCtx)) {
                  return;
                }
                setState(() {
                  _isScannedTextExpanded = !_isScannedTextExpanded;
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      _isScannedTextExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 20,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isScannedTextExpanded
                            ? 'Hide scanned text'
                            : 'Show scanned text to double check',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                    Icon(
                      Icons.text_snippet_outlined,
                      size: 16,
                      color: Colors.grey[500],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Expanded content
          if (_isScannedTextExpanded) ...[
            Divider(height: 1, color: Colors.grey[300]),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 150),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  widget.scannedText!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[800],
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _buildButtonText() {
    if (_selectedIndices.length == 1) {
      final isDuplicate = widget.duplicates.containsKey(_selectedIndices.first);
      return isDuplicate ? 'Use Existing' : 'Create 1 Experience';
    }

    if (_selectedDuplicateCount > 0 && _selectedNewCount > 0) {
      return 'Add ${_selectedIndices.length} ($_selectedNewCount new, $_selectedDuplicateCount existing)';
    } else if (_selectedDuplicateCount > 0) {
      return 'Use $_selectedDuplicateCount Existing';
    } else {
      return 'Create $_selectedNewCount Experiences';
    }
  }
}

// --- Quick Add Dialog Widget ---
class _QuickAddDialog extends StatefulWidget {
  final GoogleMapsService mapsService;
  final ExperienceService experienceService;
  final void Function(Location location, Experience? experience)
      onLocationSelected;

  const _QuickAddDialog({
    required this.mapsService,
    required this.experienceService,
    required this.onLocationSelected,
  });

  @override
  State<_QuickAddDialog> createState() => _QuickAddDialogState();
}

class _QuickAddDialogState extends State<_QuickAddDialog>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _showSearchResults = false;
  Timer? _debounce;
  Location? _selectedLocation;
  Experience? _selectedExperience;
  bool _isLoadingDetails = false;

  // Dialog-local help mode
  late final HelpFlowState<ReceiveShareHelpTargetId> _dialogHelp;
  late final AnimationController _dialogSpotlight;
  final GlobalKey _dialogHelpBtnKey = GlobalKey();
  final GlobalKey<HelpBubbleState> _dialogBubbleKey = GlobalKey();
  bool _dialogIsTyping = false;

  void _toggleDialogHelp() {
    triggerHeavyHaptic();
    setState(() {
      final nowActive = _dialogHelp.toggle();
      if (nowActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final helpCtx = _dialogHelpBtnKey.currentContext;
          if (helpCtx != null) {
            _showDialogHelpFor(ReceiveShareHelpTargetId.helpButton, helpCtx);
          } else {
            setState(() {
              _dialogHelp.showTarget(
                ReceiveShareHelpTargetId.helpButton,
                _dialogFallbackTargetRect(),
              );
              _dialogIsTyping = true;
            });
          }
        });
      }
    });
  }

  void _showDialogHelpFor(ReceiveShareHelpTargetId id, BuildContext ctx) {
    final rect = _resolveTargetRect(ctx) ?? _dialogFallbackTargetRect();
    setState(() {
      _dialogHelp.showTarget(id, rect);
      _dialogIsTyping = true;
    });
  }

  Rect _dialogFallbackTargetRect() {
    final size = MediaQuery.of(context).size;
    final width = (size.width * 0.4).clamp(96.0, 220.0);
    const height = 44.0;
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: width,
      height: height,
    );
  }

  // ignore: unused_element
  bool _tryDialogHelpTap(ReceiveShareHelpTargetId id, BuildContext ctx) {
    if (!_dialogHelp.isActive) return false;
    triggerHeavyHaptic();
    _showDialogHelpFor(id, ctx);
    return true;
  }

  void _advanceDialogHelp() {
    setState(() {
      _dialogHelp.advance();
      if (_dialogHelp.hasActiveTarget) _dialogIsTyping = true;
    });
  }

  void _dismissDialogHelp() {
    setState(() {
      _dialogHelp.dismiss();
      _dialogIsTyping = false;
    });
  }

  void _onDialogHelpBarrierTap() {
    if (_dialogIsTyping) {
      _dialogBubbleKey.currentState?.skipTypewriter();
    } else {
      _advanceDialogHelp();
    }
  }

  Widget _buildDialogHelpOverlay() {
    final flow = _dialogHelp;
    final spec = flow.activeSpec;
    final step = flow.activeHelpStep;
    return Positioned.fill(
      child: Builder(
        builder: (overlayCtx) {
          final localTargetRect =
              _dialogTargetRectInOverlay(overlayCtx, flow.activeTargetRect);
          return AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: flow.hasActiveTarget ? 1.0 : 0.0,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _onDialogHelpBarrierTap,
              child: Stack(children: [
                if (localTargetRect != null)
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _dialogSpotlight,
                      builder: (context, _) => CustomPaint(
                        painter: HelpSpotlightPainter(
                          targetRect: localTargetRect,
                          glowProgress: _dialogSpotlight.value,
                        ),
                      ),
                    ),
                  ),
                if (spec != null && step != null && localTargetRect != null)
                  HelpBubble(
                    key: _dialogBubbleKey,
                    text: step.text,
                    instruction: step.instruction,
                    isLastStep: flow.isLastStep,
                    targetRect: localTargetRect,
                    onAdvance: _advanceDialogHelp,
                    onDismiss: _dismissDialogHelp,
                    onTypingStarted: () {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _dialogIsTyping = true);
                      });
                    },
                    onTypingFinished: () {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _dialogIsTyping = false);
                      });
                    },
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Rect? _dialogTargetRectInOverlay(
      BuildContext overlayContext, Rect? globalRect) {
    if (globalRect == null) return null;
    final renderObject = overlayContext.findRenderObject();
    final overlayBox = renderObject is RenderBox && renderObject.hasSize
        ? renderObject
        : overlayContext.findAncestorRenderObjectOfType<RenderBox>();
    if (overlayBox == null || !overlayBox.hasSize) return null;
    final topLeft = overlayBox.globalToLocal(globalRect.topLeft);
    final bottomRight = overlayBox.globalToLocal(globalRect.bottomRight);
    return Rect.fromPoints(topLeft, bottomRight);
  }

  @override
  void initState() {
    super.initState();
    _dialogHelp = HelpFlowState<ReceiveShareHelpTargetId>(
        content: receiveShareHelpContent);
    _dialogSpotlight = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _dialogSpotlight.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _searchPlaces(String query) async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (query.isEmpty) {
        if (mounted) {
          setState(() {
            _searchResults = [];
            _showSearchResults = false;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _isSearching = true;
        });
      }

      try {
        // Search user's saved experiences first
        List<Experience> userExperiences = [];
        try {
          userExperiences = await widget.experienceService.getUserExperiences();
        } catch (e) {
          debugPrint('Error fetching user experiences: $e');
        }

        final String queryLower = query.toLowerCase();
        final List<Map<String, dynamic>> experienceResults = userExperiences
            .where((exp) {
              final nameMatch = exp.name.toLowerCase().contains(queryLower);
              final locationMatch = exp.location.displayName
                      ?.toLowerCase()
                      .contains(queryLower) ??
                  false;
              final addressMatch =
                  exp.location.address?.toLowerCase().contains(queryLower) ??
                      false;
              return nameMatch || locationMatch || addressMatch;
            })
            .take(5)
            .map((exp) => {
                  'type': 'experience',
                  'experience': exp,
                  'description': exp.name,
                  'address': exp.location.address,
                  'latitude': exp.location.latitude,
                  'longitude': exp.location.longitude,
                })
            .toList();

        // Then search Google Maps
        final mapsResults = await widget.mapsService.searchPlaces(query);

        // Fetch place details for top results to get ratings
        final List<Map<String, dynamic>> markedMapsResults = [];
        for (int i = 0; i < mapsResults.length && i < 5; i++) {
          final result = mapsResults[i];
          final placeId = result['placeId'];

          // Try to get rating from place details
          double? rating;
          int? userRatingCount;
          if (placeId != null && placeId.isNotEmpty) {
            try {
              final location =
                  await widget.mapsService.getPlaceDetails(placeId);
              rating = location.rating;
              userRatingCount = location.userRatingCount;
            } catch (e) {
              debugPrint('Error fetching place details for rating: $e');
            }
          }

          markedMapsResults.add({
            'type': 'place',
            ...result,
            if (rating != null) 'rating': rating,
            if (userRatingCount != null) 'userRatingCount': userRatingCount,
          });
        }

        // Add remaining results without ratings
        for (int i = 5; i < mapsResults.length; i++) {
          markedMapsResults.add({
            'type': 'place',
            ...mapsResults[i],
          });
        }

        // Combine results: experiences first, then places
        final combinedResults = [...experienceResults, ...markedMapsResults];

        if (mounted) {
          setState(() {
            _searchResults = combinedResults;
            _showSearchResults = combinedResults.isNotEmpty;
            _isSearching = false;
          });
        }
      } catch (e) {
        debugPrint('Error searching places: $e');
        if (mounted) {
          setState(() {
            _isSearching = false;
          });
        }
      }
    });
  }

  Future<void> _selectSearchResult(Map<String, dynamic> result) async {
    FocusScope.of(context).unfocus();

    setState(() {
      _showSearchResults = false;
      _isLoadingDetails = true;
    });

    try {
      if (result['type'] == 'experience') {
        // User's saved experience
        final Experience experience = result['experience'];
        setState(() {
          _selectedLocation = experience.location;
          _selectedExperience = experience;
          _isLoadingDetails = false;
          _searchController.text = experience.name;
        });
      } else {
        // Google Maps place - get full details
        final placeId = result['placeId'];
        if (placeId != null && placeId.isNotEmpty) {
          final location = await widget.mapsService.getPlaceDetails(placeId);
          setState(() {
            _selectedLocation = location;
            _selectedExperience = null;
            _isLoadingDetails = false;
            _searchController.text =
                location.displayName ?? result['description'] ?? '';
          });
        } else {
          setState(() {
            _isLoadingDetails = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error selecting search result: $e');
      if (mounted) {
        setState(() {
          _isLoadingDetails = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location details: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;

    return Align(
      alignment: Alignment.topCenter,
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: EdgeInsets.only(top: topPadding),
          constraints: BoxConstraints(
            maxHeight: mediaQuery.size.height * 0.7,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(0),
                        bottomRight: Radius.circular(0),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.add_location_alt, color: Colors.white),
                        const SizedBox(width: 12),
                        const Text(
                          'Quick Add',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        _dialogHelp.isActive
                            ? IconButton(
                                key: _dialogHelpBtnKey,
                                icon:
                                    const Icon(Icons.help, color: Colors.white),
                                tooltip: 'Exit Help Mode',
                                onPressed: _toggleDialogHelp,
                              )
                            : IconButton(
                                key: _dialogHelpBtnKey,
                                icon: const Icon(Icons.help_outline,
                                    color: Colors.white70),
                                tooltip: 'Help',
                                onPressed: _toggleDialogHelp,
                              ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),

                  // Search field
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      decoration: InputDecoration(
                        hintText: 'Search locations or saved experiences...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _isSearching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _searchResults = [];
                                        _showSearchResults = false;
                                        _selectedLocation = null;
                                        _selectedExperience = null;
                                      });
                                    },
                                  )
                                : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onChanged: _searchPlaces,
                    ),
                  ),

                  // Search results
                  if (_showSearchResults)
                    Flexible(
                      child: Container(
                        constraints: BoxConstraints(
                          maxHeight: mediaQuery.size.height * 0.35,
                        ),
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _searchResults.length,
                          separatorBuilder: (context, index) =>
                              Divider(height: 1, indent: 56, endIndent: 16),
                          itemBuilder: (context, index) {
                            final result = _searchResults[index];
                            final bool isUserExperience =
                                result['type'] == 'experience';
                            final String? address = result['address'] ??
                                (result['structured_formatting'] != null
                                    ? result['structured_formatting']
                                        ['secondary_text']
                                    : null);
                            final bool hasRating =
                                result['rating'] != null && !isUserExperience;
                            final double rating = hasRating
                                ? (result['rating'] as num).toDouble()
                                : 0.0;

                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: withHeavyTap(
                                    () => _selectSearchResult(result)),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4.0),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: isUserExperience
                                          ? Colors.green.withOpacity(0.1)
                                          : Theme.of(context)
                                              .primaryColor
                                              .withOpacity(0.1),
                                      child: isUserExperience
                                          ? const Icon(
                                              Icons.bookmark,
                                              color: Colors.green,
                                              size: 18,
                                            )
                                          : Icon(
                                              Icons.location_on,
                                              color: Theme.of(context)
                                                  .primaryColor,
                                              size: 18,
                                            ),
                                    ),
                                    title: Row(
                                      children: [
                                        if (isUserExperience) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color:
                                                  Colors.green.withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                  color: Colors.green
                                                      .withOpacity(0.3)),
                                            ),
                                            child: Text(
                                              'Saved',
                                              style: TextStyle(
                                                color: Colors.green[700],
                                                fontSize: 10,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Expanded(
                                          child: Text(
                                            result['description'] ??
                                                'Unknown Place',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w500,
                                              fontSize: 15,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (address != null)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 4.0),
                                            child: Row(
                                              children: [
                                                Icon(Icons.location_on,
                                                    size: 14,
                                                    color: Colors.grey[600]),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    address,
                                                    style: TextStyle(
                                                      color: Colors.grey[600],
                                                      fontSize: 13,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if (hasRating)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 4.0),
                                            child: Row(
                                              children: [
                                                ...List.generate(
                                                  5,
                                                  (i) => Icon(
                                                    i < rating.floor()
                                                        ? Icons.star
                                                        : (i < rating)
                                                            ? Icons.star_half
                                                            : Icons.star_border,
                                                    size: 14,
                                                    color: Colors.amber,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                if (result['userRatingCount'] !=
                                                    null)
                                                  Text(
                                                    '(${result['userRatingCount']})',
                                                    style: TextStyle(
                                                      color: Colors.grey[600],
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                  // Selected location display
                  if (_selectedLocation != null && !_showSearchResults)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _selectedExperience != null
                            ? Colors.green.withOpacity(0.05)
                            : Colors.blue.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _selectedExperience != null
                              ? Colors.green.withOpacity(0.3)
                              : Colors.blue.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _selectedExperience != null
                                    ? Icons.bookmark
                                    : Icons.location_on,
                                color: _selectedExperience != null
                                    ? Colors.green
                                    : Theme.of(context).primaryColor,
                              ),
                              const SizedBox(width: 8),
                              if (_selectedExperience != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                        color: Colors.green.withOpacity(0.3)),
                                  ),
                                  child: Text(
                                    'Saved Experience',
                                    style: TextStyle(
                                      color: Colors.green[700],
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                )
                              else
                                Text(
                                  'New Location',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              // Show rating on the right side for new locations
                              if (_selectedExperience == null &&
                                  _selectedLocation!.rating != null) ...[
                                const Spacer(),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ...List.generate(
                                      5,
                                      (i) => Icon(
                                        i < _selectedLocation!.rating!.floor()
                                            ? Icons.star
                                            : (i < _selectedLocation!.rating!)
                                                ? Icons.star_half
                                                : Icons.star_border,
                                        size: 16,
                                        color: Colors.amber,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    if (_selectedLocation!.userRatingCount !=
                                        null)
                                      Text(
                                        '(${_selectedLocation!.userRatingCount})',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _selectedLocation!.displayName ??
                                'Unnamed Location',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (_selectedLocation!.address != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              _selectedLocation!.address!,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                  // Loading indicator for details
                  if (_isLoadingDetails)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),

                  // Action buttons
                  if (_selectedLocation != null &&
                      !_showSearchResults &&
                      !_isLoadingDetails)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _selectedLocation = null;
                                  _selectedExperience = null;
                                  _searchController.clear();
                                });
                              },
                              child: const Text('Clear'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                widget.onLocationSelected(
                                  _selectedLocation!,
                                  _selectedExperience,
                                );
                              },
                              icon:
                                  const Icon(Icons.check, color: Colors.white),
                              label: Text(
                                _selectedExperience != null
                                    ? 'Add Saved Experience'
                                    : 'Add Location',
                                style: const TextStyle(color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).primaryColor,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Bottom padding
                  const SizedBox(height: 8),
                ],
              ),
              if (_dialogHelp.isActive && _dialogHelp.hasActiveTarget)
                _buildDialogHelpOverlay(),
            ],
          ),
        ),
      ),
    );
  }
}
// --- End Quick Add Dialog Widget ---

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
