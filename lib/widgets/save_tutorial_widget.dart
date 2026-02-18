import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:rive/rive.dart' hide Animation;
import 'package:video_player/video_player.dart';

import '../config/colors.dart';

List<TextSpan> _buildTutorialFormattedSpans(String text, TextStyle? baseStyle) {
  final spans = <TextSpan>[];
  final buffer = StringBuffer();
  bool isBold = false;
  final shouldApplyCategoryColorHighlight =
      text.contains("which means 'Want to go' in this case.");

  void appendStyledSegment(String segment, TextStyle? style) {
    if (!shouldApplyCategoryColorHighlight) {
      spans.add(TextSpan(text: segment, style: style));
      return;
    }

    final highlightPattern = RegExp(r"\bred\b|Want to go");
    int lastMatchEnd = 0;

    for (final match in highlightPattern.allMatches(segment)) {
      if (match.start > lastMatchEnd) {
        spans.add(
          TextSpan(
              text: segment.substring(lastMatchEnd, match.start), style: style),
        );
      }
      spans.add(
        TextSpan(
          text: segment.substring(match.start, match.end),
          style: (style ?? const TextStyle()).copyWith(
            color: Colors.red,
            fontWeight: style?.fontWeight ?? FontWeight.w600,
          ),
        ),
      );
      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < segment.length) {
      spans.add(TextSpan(text: segment.substring(lastMatchEnd), style: style));
    }
  }

  void flushBuffer() {
    if (buffer.isEmpty) return;
    appendStyledSegment(
      buffer.toString(),
      isBold ? baseStyle?.copyWith(fontWeight: FontWeight.w700) : baseStyle,
    );
    buffer.clear();
  }

  for (int i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == '*') {
      flushBuffer();
      isBold = !isBold;
      continue;
    }
    buffer.write(char);
  }
  flushBuffer();

  return spans;
}

/// A guided, mocked tutorial that simulates the ReceiveShareScreen experience.
/// Shows a fake Instagram preview inside a phone frame and walks users through
/// the steps of saving content to Plendy with highlight-and-explain dialogues.
class SaveTutorialWidget extends StatefulWidget {
  final VoidCallback onComplete;

  const SaveTutorialWidget({
    super.key,
    required this.onComplete,
  });

  @override
  State<SaveTutorialWidget> createState() => _SaveTutorialWidgetState();
}

class _SaveTutorialWidgetState extends State<SaveTutorialWidget>
    with TickerProviderStateMixin {
  static const double _dialogueFontSize = 15;

  // Tutorial step index
  int _currentStep = 0;
  bool _typewriterComplete = false;
  bool _isCompletingScan = false;
  bool _showLocationFoundDialog = false;
  int _postScanDialogueIndex = 0;
  bool _showCreateCardPromptDialogue = false;
  double _scanProgress = _mockScanStartProgress;

  // Video controller for Instagram preview
  VideoPlayerController? _videoController;
  FileLoader? _rightArrowFileLoader;
  late final AnimationController _scanProgressController;
  late final AnimationController _scanLoadingFlashController;
  Animation<double>? _scanProgressAnimation;

  final ScrollController _tutorialScrollController = ScrollController();

  // Typewriter key
  final GlobalKey<_TutorialTypewriterTextState> _typewriterKey =
      GlobalKey<_TutorialTypewriterTextState>();

  // GlobalKeys for highlight sections
  final GlobalKey _previewKey = GlobalKey();
  final GlobalKey _scanLoadingKey = GlobalKey();
  final GlobalKey _experienceCardSectionKey = GlobalKey();
  final GlobalKey _locationKey = GlobalKey();
  final GlobalKey _categoryKey = GlobalKey();
  final GlobalKey _saveButtonKey = GlobalKey();

  // Mocked data
  static const String _videoAsset = 'assets/onboarding/restaurant_video.mp4';
  static const String _locationName = 'The Golden Noodle House';
  static const String _locationAddress = '123 Foodie St, San Francisco, CA';
  static const int _analyzeStartStepIndex = 3;
  static const int _analyzeStepIndex = 7;
  static const int _postLocationCategoryIntroStepIndex = 8;
  static const double _mockScanStartProgress = 0.58;
  static const List<String> _postScanDialogues = [
    'Done! Here\'s the location that I found. Yep, it\'s *The Golden Noodle House*!',
    'Here, you can check and confirm if the location I found for you is correct.',
    'There is a slight chance that I\'ll make mistakes here. I\'m just a bird!',
    'In the rare case that I get it wrong, you can fix it manually yourself or have me try again with \'Deep Scan\'.',
    'Deep scanning takes more time but provides accuracy.',
    'This looks like the correct location so let\'s just move on.',
  ];
  static const String _postScanCreateCardDialogue =
      'Since this is the correct location, let\'s go ahead and add the experience.';

  static const List<String> _stepDialogues = [
    'Look - Plendy opened up!',
    'When you share something to Plendy, Plendy will open up showing you a preview of what you shared.',
    'Here\'s that video from Instagram we shared!',
    'Notice the progress bar above!',
    'I can analyze the post\'s caption to pull any location details automatically.',
    'For example, this Instagram post\'s caption mentions that the restaurant\'s name is *The Golden Noodle House*.',
    'So I should be able to find the location for *The Golden Noodle House*!',
    'Let\'s see if I got it right. It only takes a few moments.',
    'Look! We created an experience with the location details.',
    'Now that we have a location, you can categorize the experience with icons and colors. See below!',
    'Since *The Golden Noodle House* is a restaurant, I went ahead and categorized it as such. I assume you haven\'t been here before, so I went ahead and set the color to red which means \'Want to go\' in this case.',
    'This makes it easy to organize and view your experiences on your map. You can customize and edit these to your heart\'s content!',
    'You can assign multiple categories and colors for each experience. If there\'s more than one location on a post, I\'ll pull each location so you can save it as separate experiences!',
    'When you\'re ready, tap Save to add this to your collection!',
  ];

  @override
  void initState() {
    super.initState();
    _scanProgressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _scanProgressController.addListener(() {
      final animation = _scanProgressAnimation;
      if (!mounted || animation == null) return;
      setState(() {
        _scanProgress = animation.value;
      });
    });
    _scanProgressController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        HapticFeedback.mediumImpact();
        setState(() {
          _isCompletingScan = false;
          _showLocationFoundDialog = true;
          _postScanDialogueIndex = 0;
          _showCreateCardPromptDialogue = false;
          _typewriterComplete = false;
        });
      }
    });
    _scanLoadingFlashController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _rightArrowFileLoader = FileLoader.fromAsset(
      'assets/tutorials/tap_here_finger.riv',
      riveFactory: Factory.flutter,
    );
    _initVideoController();
  }

  void _initVideoController() {
    _videoController = VideoPlayerController.asset(_videoAsset);
    _videoController!.initialize().then((_) {
      _videoController!.setLooping(true);
      _videoController!.setVolume(0);
      if (mounted) {
        _videoController!.play();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _scanProgressController.dispose();
    _scanLoadingFlashController.dispose();
    _rightArrowFileLoader?.dispose();
    _tutorialScrollController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  double get _scanFlashGlowOpacity {
    final t = _scanLoadingFlashController.value;

    double pulse(double start, double duration) {
      final end = start + duration;
      if (t < start || t >= end) return 0.0;
      final progress = (t - start) / duration;
      if (progress < 0.5) return progress / 0.5;
      return (1.0 - progress) / 0.5;
    }

    final p1 = pulse(0.00, 0.20);
    final p2 = pulse(0.28, 0.20);
    return p1 > p2 ? p1 : p2;
  }

  String get _currentBirdMessage => _showLocationFoundDialog
      ? (_showCreateCardPromptDialogue
          ? _postScanCreateCardDialogue
          : _postScanDialogues[_postScanDialogueIndex])
      : _stepDialogues[_currentStep];

  void _startScanCompletion() {
    if (_isCompletingScan || _showLocationFoundDialog) return;
    final animation = Tween<double>(begin: _scanProgress, end: 1.0).animate(
      CurvedAnimation(
        parent: _scanProgressController,
        curve: Curves.easeOutCubic,
      ),
    );
    _scanProgressAnimation = animation;
    setState(() {
      _isCompletingScan = true;
    });
    _scanProgressController
      ..stop()
      ..reset()
      ..forward();
  }

  Future<void> _scrollToExperienceCardForm() async {
    final targetContext = _experienceCardSectionKey.currentContext;
    if (targetContext == null) return;

    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      alignment: 0.0,
    );
  }

  void _onCreateCardButtonTapped() {
    if (!_showLocationFoundDialog || !_showCreateCardPromptDialogue) return;
    HapticFeedback.mediumImpact();

    setState(() {
      _showLocationFoundDialog = false;
      _postScanDialogueIndex = 0;
      _showCreateCardPromptDialogue = false;
      if (_currentStep < _stepDialogues.length - 1) {
        _currentStep++;
      }
      _typewriterComplete = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToExperienceCardForm();
    });
  }

  void _advanceStep() {
    if (_isCompletingScan) return;
    HapticFeedback.lightImpact();

    if (_currentStep == _analyzeStepIndex && !_showLocationFoundDialog) {
      if (!_typewriterComplete) {
        _typewriterKey.currentState?.skipToEnd();
        return;
      }
      _startScanCompletion();
      return;
    }

    if (!_typewriterComplete) {
      _typewriterKey.currentState?.skipToEnd();
      return;
    }

    if (_showLocationFoundDialog) {
      if (_showCreateCardPromptDialogue) {
        // Once the Create Card prompt is shown, user must tap "Create 1 Card".
        return;
      }

      if (_postScanDialogueIndex < _postScanDialogues.length - 1) {
        setState(() {
          _postScanDialogueIndex++;
          _typewriterComplete = false;
        });
      } else {
        setState(() {
          _showCreateCardPromptDialogue = true;
          _typewriterComplete = false;
        });
      }
      return;
    }
    if (_currentStep < _stepDialogues.length - 1) {
      setState(() {
        _currentStep++;
        _typewriterComplete = false;
      });
    }
    // On final step, tapping anywhere doesn't complete - must tap Save button
  }

  void _onSaveButtonTapped() {
    // Only allow Save tap on final step after typewriter is complete
    if (_currentStep == _stepDialogues.length - 1 && _typewriterComplete) {
      HapticFeedback.mediumImpact();
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Center(
            child: Text(
              'Saving experiences in Plendy',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ) ??
                  const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
            ),
          ),
        ),
        Expanded(
          child: _buildPhoneFrameWithContent(
            child: _buildMockedReceiveShareScreen(),
            overlays: [_buildBirdOverlay()],
          ),
        ),
      ],
    );
  }

  /// Builds the mocked ReceiveShareScreen content inside the phone frame
  Widget _buildMockedReceiveShareScreen() {
    final bool isAnalyzeFocusStep = _currentStep >= _analyzeStartStepIndex &&
        _currentStep <= _analyzeStepIndex &&
        !_showLocationFoundDialog;

    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundColor,
        foregroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: AppColors.backgroundColor,
        title: const Text(
          'Save Content',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        leading: const Padding(
          padding: EdgeInsets.only(left: 8),
          child: Icon(Icons.arrow_back_ios, size: 16),
        ),
        leadingWidth: 32,
        toolbarHeight: 40,
        automaticallyImplyLeading: false,
        actions: [
          // Privacy toggle button (mocked)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility_off,
                          size: 12, color: Colors.grey[600]),
                      const SizedBox(width: 3),
                      Text(
                        'Private',
                        style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.info_outline, size: 14, color: Colors.grey[400]),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                SingleChildScrollView(
                  controller: _tutorialScrollController,
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Shared URL bar (mocked)
                      _buildMockedUrlBar(),
                      if (_currentStep >= _analyzeStartStepIndex &&
                          _currentStep <= _analyzeStepIndex) ...[
                        const SizedBox(height: 12),
                        AnimatedBuilder(
                          animation: _scanLoadingFlashController,
                          builder: (context, child) {
                            return _buildGlowHighlightWrapper(
                              key: _scanLoadingKey,
                              glowOpacity: isAnalyzeFocusStep
                                  ? _scanFlashGlowOpacity
                                  : 0,
                              child: child!,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: _buildMockedLocationScanningIndicator(),
                          ),
                        ),
                      ],
                      Container(height: 6, color: AppColors.backgroundColor),
                      // Instagram preview (with highlight)
                      _buildHighlightWrapper(
                        key: _previewKey,
                        isHighlighted: _currentStep <= 2,
                        child: _buildMockedInstagramPreview(),
                      ),
                      Container(
                          height: 6, color: AppColors.backgroundColorDark),
                      // Experience card section
                      Container(
                        key: _experienceCardSectionKey,
                        child: _buildMockedExperienceCard(),
                      ),
                    ],
                  ),
                ),
                if (_showLocationFoundDialog) _buildMockedLocationFoundDialog(),
              ],
            ),
          ),
          // Bottom action bar
          _buildMockedBottomBar(),
        ],
      ),
    );
  }

  Widget _buildMockedUrlBar() {
    return Container(
      color: AppColors.backgroundColor,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.backgroundColorDark),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Shared URL',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    'https://www.instagram.com/reel/...',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[800],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.link, size: 14, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildMockedInstagramPreview() {
    final controller = _videoController;
    final isInitialized = controller?.value.isInitialized ?? false;

    return Container(
      color: AppColors.backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Card(
        margin: EdgeInsets.zero,
        color: Colors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(0),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Instagram header row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFF58529),
                          Color(0xFFDD2A7B),
                          Color(0xFF8134AF),
                        ],
                      ),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child:
                        const Icon(Icons.person, color: Colors.white, size: 14),
                  ),
                  const SizedBox(width: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'foodie_adventures',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'instagram.com',
                        style: GoogleFonts.inter(
                          fontSize: 8,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Video preview
            Container(
              width: double.infinity,
              color: Colors.black,
              child: isInitialized
                  ? AspectRatio(
                      aspectRatio: controller!.value.aspectRatio,
                      child: VideoPlayer(controller),
                    )
                  : const SizedBox(
                      height: 120,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
            ),
            // Instagram post details below video
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // "View more on Instagram" link
                  Text(
                    'View more on Instagram',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      color: const Color(0xFF0095F6),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Action icons row
                  Row(
                    children: [
                      // Heart icon
                      Icon(Icons.favorite_border,
                          size: 16, color: Colors.black87),
                      const SizedBox(width: 10),
                      // Comment icon
                      Icon(Icons.chat_bubble_outline,
                          size: 14, color: Colors.black87),
                      const SizedBox(width: 10),
                      // Share icon
                      Icon(Icons.send_outlined,
                          size: 14, color: Colors.black87),
                      const Spacer(),
                      // Bookmark icon
                      Icon(Icons.bookmark_border,
                          size: 16, color: Colors.black87),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Likes count
                  Text(
                    '1,234 likes',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 3),
                  // Username and caption
                  RichText(
                    text: TextSpan(
                      style:
                          GoogleFonts.inter(fontSize: 9, color: Colors.black87),
                      children: [
                        TextSpan(
                          text: 'foodie_adventures ',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const TextSpan(
                          text: 'Best noodles in the city! 🍜',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Hashtags
                  Text(
                    '#foodie #noodles #sanfrancisco',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      color: const Color(0xFF00376B),
                    ),
                  ),
                  const SizedBox(height: 3),
                  // View comments
                  Text(
                    'View all 42 comments',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Add a comment row
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Add a comment...',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            color: Colors.grey[400],
                          ),
                        ),
                      ),
                      Icon(Icons.camera_alt_outlined,
                          size: 12, color: Colors.grey[400]),
                    ],
                  ),
                ],
              ),
            ),
            // Control bar below preview (Default view, Instagram icon, Expand)
            _buildMockedPreviewControlBar(),
          ],
        ),
      ),
    );
  }

  /// Builds the control bar with Default view chip, Instagram button, and Expand button
  Widget _buildMockedPreviewControlBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey[200]!, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Default view chip on the left
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.sage.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.sage.withOpacity(0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.code,
                      size: 10,
                      color: AppColors.sage,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'Default view',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w500,
                        color: AppColors.sage,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(FontAwesomeIcons.instagram),
            color: const Color(0xFFE1306C),
            iconSize: 32,
            tooltip: 'Open in Instagram',
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
            onPressed: () {},
          ),
          // Expand button on the right
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Icon(
                Icons.fullscreen,
                size: 18,
                color: AppColors.teal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMockedExperienceCard() {
    return Container(
      color: AppColors.backgroundColorDark,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              spreadRadius: 1,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with expand/collapse
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.keyboard_arrow_up, color: Colors.black, size: 16),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _locationName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // Card content
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Privacy toggle row (right-aligned)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.visibility_off,
                                size: 10, color: Colors.grey[600]),
                            const SizedBox(width: 2),
                            Text(
                              'Private',
                              style: TextStyle(
                                  fontSize: 8, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(Icons.info_outline,
                          size: 10, color: Colors.grey[400]),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Events + Choose saved experience buttons row
                  Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.teal, width: 1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.event,
                                  size: 10, color: AppColors.teal),
                              const SizedBox(width: 2),
                              Text(
                                'Events',
                                style: TextStyle(
                                    fontSize: 8, color: AppColors.teal),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.teal, width: 1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bookmark_outline,
                                  size: 10, color: AppColors.teal),
                              const SizedBox(width: 2),
                              Flexible(
                                child: Text(
                                  'Choose a saved experience',
                                  style: TextStyle(
                                      fontSize: 8, color: AppColors.teal),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Location section (with highlight)
                  _buildHighlightWrapper(
                    key: _locationKey,
                    isHighlighted: _currentStep >= _analyzeStartStepIndex &&
                        _currentStep <= _analyzeStepIndex,
                    child: _buildMockedLocationSection(),
                  ),

                  const SizedBox(height: 6),

                  // Experience Title field
                  _buildMockedTextField(
                    label: 'Experience Title',
                    value: _locationName,
                    prefixIcon: Icons.title,
                  ),
                  const SizedBox(height: 4),

                  // For reference row (Yelp, Maps, Ticketmaster)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'For reference',
                        style: TextStyle(fontSize: 8, color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 4),
                      // Yelp icon
                      Container(
                        padding: const EdgeInsets.all(2),
                        child: Icon(Icons.restaurant,
                            size: 12, color: Colors.red[700]),
                      ),
                      const SizedBox(width: 3),
                      // Maps icon
                      Container(
                        padding: const EdgeInsets.all(2),
                        child: Icon(Icons.map_outlined,
                            size: 12, color: const Color(0xFF6D8B74)),
                      ),
                      const SizedBox(width: 3),
                      // Ticketmaster icon
                      Container(
                        padding: const EdgeInsets.all(2),
                        child: Icon(Icons.confirmation_number,
                            size: 12, color: const Color(0xFF026CDF)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Category section (with highlight)
                  _buildHighlightWrapper(
                    key: _categoryKey,
                    isHighlighted: _currentStep >= 9 && _currentStep <= 11,
                    child: _buildMockedCategorySection(),
                  ),

                  const SizedBox(height: 6),

                  // Official Website field (optional)
                  _buildMockedTextField(
                    label: 'Official Website (optional)',
                    value: '',
                    hintText: 'https://...',
                    prefixIcon: Icons.language,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMockedTextField({
    required String label,
    required String value,
    String? hintText,
    required IconData prefixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.backgroundColorDark),
            borderRadius: BorderRadius.circular(4),
            color: Colors.white,
          ),
          child: Row(
            children: [
              Icon(prefixIcon, size: 12, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(fontSize: 7, color: Colors.grey[500]),
                    ),
                    Text(
                      value.isNotEmpty ? value : (hintText ?? ''),
                      style: TextStyle(
                        fontSize: 9,
                        color: value.isNotEmpty
                            ? Colors.grey[800]
                            : Colors.grey[400],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMockedLocationSection() {
    // This mimics the actual location section with a container, location info, and toggle
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.backgroundColorDark),
        borderRadius: BorderRadius.circular(4),
        color: Colors.white,
      ),
      child: Row(
        children: [
          Icon(Icons.location_on, color: Colors.grey[600], size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _locationName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    color: Colors.black,
                  ),
                ),
                Text(
                  _locationAddress,
                  style: TextStyle(
                    fontSize: 8,
                    color: Colors.grey[700],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Toggle switch (mocked, always on)
          Transform.scale(
            scale: 0.6,
            child: Switch(
              value: true,
              onChanged: null,
              activeColor: AppColors.teal,
              activeTrackColor: AppColors.teal.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  /// Matches the AI scan loading UI shown in ReceiveShareScreen while location extraction runs.
  Widget _buildMockedLocationScanningIndicator() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
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
                'Plendy AI analyzing...',
                style: TextStyle(
                  color: AppColors.wineLight,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _scanProgress,
            minHeight: 4,
            backgroundColor:
                Theme.of(context).colorScheme.primary.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMockedLocationFoundDialog() {
    final bool showCreateFinger = _showCreateCardPromptDialogue;

    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            onTap: _advanceStep,
            behavior: HitTestBehavior.opaque,
            child: Container(color: Colors.black.withOpacity(0.2)),
          ),
          Center(
            child: GestureDetector(
              onTap: _showCreateCardPromptDialogue ? null : _advanceStep,
              behavior: HitTestBehavior.opaque,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                decoration: BoxDecoration(
                  color: AppColors.backgroundColor,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.location_on,
                            size: 20, color: AppColors.sage),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            '1 Location Found',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Select which locations to add:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.sage.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Checkbox(value: true, onChanged: (_) {}),
                          const SizedBox(width: 4),
                          Icon(Icons.place, size: 16, color: Colors.grey[700]),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  _locationName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  _locationAddress,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        'Selected locations will be kept',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.search, size: 14),
                        label: const Text('Try Deep Scan'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.sage,
                          side: BorderSide(color: AppColors.sage),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          textStyle: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {},
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ElevatedButton(
                              onPressed: _onCreateCardButtonTapped,
                              child: const Text('Add 1 Experience'),
                            ),
                            if (showCreateFinger &&
                                _rightArrowFileLoader != null)
                              Positioned(
                                left: -46,
                                top: -8,
                                child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: IgnorePointer(
                                    child: RiveWidgetBuilder(
                                      fileLoader: _rightArrowFileLoader!,
                                      builder: (context, state) =>
                                          switch (state) {
                                        RiveLoading() =>
                                          const SizedBox.shrink(),
                                        RiveFailed() => const SizedBox.shrink(),
                                        RiveLoaded() => RiveWidget(
                                            controller: state.controller,
                                            fit: Fit.contain,
                                          ),
                                      },
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMockedCategorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Primary Category label
        Text(
          'Primary Category',
          style: TextStyle(fontSize: 8, color: Colors.grey[600]),
        ),
        const SizedBox(height: 3),
        // Primary Category dropdown button (mocked)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.backgroundColorDark),
            borderRadius: BorderRadius.circular(6),
            color: Colors.white,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('🍜', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 6),
                  const Text(
                    'Restaurant',
                    style: TextStyle(fontSize: 10, color: Colors.black87),
                  ),
                ],
              ),
              Icon(Icons.arrow_drop_down, color: Colors.grey, size: 16),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Assign more categories link
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 10, color: AppColors.teal),
              const SizedBox(width: 2),
              Text(
                'Assign more categories',
                style: TextStyle(fontSize: 8, color: AppColors.teal),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Color Category label
        Text(
          'Color Category',
          style: TextStyle(fontSize: 8, color: Colors.grey[600]),
        ),
        const SizedBox(height: 3),
        // Color Category dropdown button (mocked)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.backgroundColorDark),
            borderRadius: BorderRadius.circular(6),
            color: Colors.white,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: Colors.grey.shade400, width: 0.5),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Want to go',
                    style: TextStyle(fontSize: 10, color: Colors.black87),
                  ),
                ],
              ),
              Icon(Icons.arrow_drop_down, color: Colors.grey, size: 16),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Assign more color categories link
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 10, color: AppColors.teal),
              const SizedBox(width: 2),
              Text(
                'Assign more color categories',
                style: TextStyle(fontSize: 8, color: AppColors.teal),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMockedBottomBar() {
    final bool isOnFinalStep = _currentStep == _stepDialogues.length - 1;
    final bool canTapSave = isOnFinalStep && _typewriterComplete;
    final bool showSaveFinger = isOnFinalStep && _typewriterComplete;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          OutlinedButton(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey[700],
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 11),
            ),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add, color: Colors.white, size: 14),
            label:
                const Text('Quick Add', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 11),
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              ElevatedButton.icon(
                key: _saveButtonKey,
                onPressed: canTapSave ? _onSaveButtonTapped : null,
                icon: const Icon(Icons.save, size: 14),
                label: const Text('Save'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 11),
                ),
              ),
              if (showSaveFinger && _rightArrowFileLoader != null)
                Positioned(
                  left: -46,
                  top: -8,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: IgnorePointer(
                      child: RiveWidgetBuilder(
                        fileLoader: _rightArrowFileLoader!,
                        builder: (context, state) => switch (state) {
                          RiveLoading() => const SizedBox.shrink(),
                          RiveFailed() => const SizedBox.shrink(),
                          RiveLoaded() => RiveWidget(
                              controller: state.controller,
                              fit: Fit.contain,
                            ),
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Wraps a widget with a highlight effect when active
  Widget _buildHighlightWrapper({
    required GlobalKey key,
    required bool isHighlighted,
    required Widget child,
  }) {
    return Container(
      key: key,
      decoration: isHighlighted
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: AppColors.teal.withOpacity(0.3),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            )
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: isHighlighted
              ? Border.all(color: AppColors.teal, width: 2)
              : null,
        ),
        child: child,
      ),
    );
  }

  /// Wraps a widget with a glow-only highlight driven by animated opacity.
  Widget _buildGlowHighlightWrapper({
    required GlobalKey key,
    required double glowOpacity,
    required Widget child,
  }) {
    return Container(
      key: key,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: glowOpacity > 0
              ? [
                  BoxShadow(
                    color: AppColors.teal.withOpacity(0.8 * glowOpacity),
                    blurRadius: 10 + (14 * glowOpacity),
                    spreadRadius: 2 + (4 * glowOpacity),
                  ),
                ]
              : null,
        ),
        child: child,
      ),
    );
  }

  /// Bird overlay with speech bubble
  Widget _buildBirdOverlay() {
    if (_isCompletingScan &&
        _currentStep == _analyzeStepIndex &&
        !_showLocationFoundDialog) {
      return const SizedBox.shrink();
    }

    final currentMessage = _currentBirdMessage;
    final isOnFinalStep = _currentStep == _stepDialogues.length - 1;
    final bool isAnalyzeFocusStep = !_showLocationFoundDialog &&
        _currentStep >= _analyzeStartStepIndex &&
        _currentStep <= _analyzeStepIndex;
    final bool isPostLocationFocusStep = !_showLocationFoundDialog &&
        _currentStep >= _postLocationCategoryIntroStepIndex;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      right: (isAnalyzeFocusStep || isPostLocationFocusStep) ? 16 : -9,
      bottom: isPostLocationFocusStep ? 500 : (isAnalyzeFocusStep ? 320 : 40),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Speech bubble
          Container(
            width: 200,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _typewriterComplete
                    ? RichText(
                        text: TextSpan(
                          children: _buildTutorialFormattedSpans(
                            currentMessage,
                            GoogleFonts.fredoka(
                              fontSize: _dialogueFontSize,
                              color: Colors.black87,
                              height: 1.4,
                            ),
                          ),
                        ),
                      )
                    : _TutorialTypewriterText(
                        key: _typewriterKey,
                        text: currentMessage,
                        style: GoogleFonts.fredoka(
                          fontSize: _dialogueFontSize,
                          color: Colors.black87,
                          height: 1.4,
                        ),
                        speed: const Duration(milliseconds: 30),
                        onComplete: () {
                          if (mounted) {
                            setState(() {
                              _typewriterComplete = true;
                            });
                          }
                        },
                      ),
                if (_typewriterComplete && !_isCompletingScan)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _showLocationFoundDialog && _showCreateCardPromptDialogue
                          ? 'Tap Add 1 Experience'
                          : (isOnFinalStep
                              ? 'Tap the Save button'
                              : 'Tap to continue'),
                      style: GoogleFonts.fredoka(
                        fontSize: 10,
                        color: (isOnFinalStep ||
                                (_showLocationFoundDialog &&
                                    _showCreateCardPromptDialogue))
                            ? AppColors.teal
                            : Colors.grey[400],
                        fontStyle: FontStyle.italic,
                        fontWeight: (isOnFinalStep ||
                                (_showLocationFoundDialog &&
                                    _showCreateCardPromptDialogue))
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Bird Lottie
          SizedBox(
            width: 80,
            height: 80,
            child: Lottie.asset(
              'assets/mascot/bird_talking_head.json',
              fit: BoxFit.contain,
              options: LottieOptions(enableMergePaths: true),
            ),
          ),
        ],
      ),
    );
  }

  /// Wraps content in an iPhone frame mockup (matches onboarding_screen pattern)
  Widget _buildPhoneFrameWithContent(
      {required Widget child, List<Widget>? overlays}) {
    const double phoneAspectRatio = 874 / 1792;
    const double horizontalBezelPercent = 0.084;
    const double topBezelPercent = 0.042;
    const double bottomBezelPercent = 0.042;
    const double screenCornerRadius = 45.0;
    const double dynamicIslandBarPercent = 0.045;

    return LayoutBuilder(
      builder: (context, outerConstraints) {
        final maxWidth = outerConstraints.maxWidth;
        final maxHeight = outerConstraints.maxHeight;

        double phoneWidth;
        double phoneHeight;

        if (maxWidth / maxHeight < phoneAspectRatio) {
          phoneWidth = maxWidth;
          phoneHeight = maxWidth / phoneAspectRatio;
        } else {
          phoneHeight = maxHeight;
          phoneWidth = maxHeight * phoneAspectRatio;
        }

        final horizontalInset = phoneWidth * horizontalBezelPercent;
        final topInset = phoneHeight * topBezelPercent;
        final bottomInset = phoneHeight * bottomBezelPercent;
        final dynamicIslandBarHeight = phoneHeight * dynamicIslandBarPercent;

        return Center(
          child: SizedBox(
            width: phoneWidth,
            height: phoneHeight,
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                // Content positioned within the screen area
                Positioned(
                  left: horizontalInset,
                  right: horizontalInset,
                  top: topInset,
                  bottom: bottomInset,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(screenCornerRadius),
                    child: Column(
                      children: [
                        Container(
                          height: dynamicIslandBarHeight,
                          color: Colors.black,
                        ),
                        Expanded(child: child),
                      ],
                    ),
                  ),
                ),
                // Phone frame overlay
                Positioned.fill(
                  child: IgnorePointer(
                    child: Image.asset(
                      'assets/tutorials/apple-iphone-15-black-portrait.png',
                      fit: BoxFit.fill,
                    ),
                  ),
                ),
                // Overlays above bezel
                if (overlays != null) ...overlays,
                // Tap detector for advancing tutorial (all steps except final-complete)
                if (!_isCompletingScan &&
                    !_showLocationFoundDialog &&
                    (_currentStep < _stepDialogues.length - 1 ||
                        !_typewriterComplete))
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: _advanceStep,
                      behavior: HitTestBehavior.translucent,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Typewriter text widget for the save tutorial (self-contained, not dependent
/// on onboarding_screen's private _TypewriterText).
class _TutorialTypewriterText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration speed;
  final VoidCallback? onComplete;

  const _TutorialTypewriterText({
    super.key,
    required this.text,
    this.style,
    this.speed = const Duration(milliseconds: 30),
    this.onComplete,
  });

  @override
  State<_TutorialTypewriterText> createState() =>
      _TutorialTypewriterTextState();
}

class _TutorialTypewriterTextState extends State<_TutorialTypewriterText> {
  String _displayText = '';
  int _currentIndex = 0;
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  @override
  void didUpdateWidget(_TutorialTypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _displayText = '';
      _currentIndex = 0;
      _isComplete = false;
      _startTyping();
    }
  }

  void skipToEnd() {
    if (!_isComplete && mounted) {
      setState(() {
        _displayText = widget.text;
        _currentIndex = widget.text.length;
        _isComplete = true;
      });
      widget.onComplete?.call();
    }
  }

  void _startTyping() {
    if (_currentIndex < widget.text.length) {
      Future.delayed(widget.speed, () {
        if (mounted && !_isComplete) {
          setState(() {
            _displayText = widget.text.substring(0, _currentIndex + 1);
            _currentIndex++;
          });
          _startTyping();
        }
      });
    } else if (!_isComplete) {
      _isComplete = true;
      widget.onComplete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: _buildTutorialFormattedSpans(_displayText, widget.style),
      ),
    );
  }
}
