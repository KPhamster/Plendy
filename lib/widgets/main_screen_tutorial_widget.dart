import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:rive/rive.dart' hide Animation;
import 'package:video_player/video_player.dart';

import '../config/colors.dart';

List<TextSpan> _buildMainTutorialFormattedSpans(
    String text, TextStyle? baseStyle) {
  final spans = <TextSpan>[];
  final buffer = StringBuffer();
  bool isBold = false;

  void flushBuffer() {
    if (buffer.isEmpty) return;
    spans.add(
      TextSpan(
        text: buffer.toString(),
        style: isBold
            ? baseStyle?.copyWith(fontWeight: FontWeight.w700)
            : baseStyle,
      ),
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

enum _MainTutorialTab { collection, map }

class MainScreenTutorialWidget extends StatefulWidget {
  final VoidCallback onComplete;

  const MainScreenTutorialWidget({
    super.key,
    required this.onComplete,
  });

  @override
  State<MainScreenTutorialWidget> createState() =>
      _MainScreenTutorialWidgetState();
}

class _MainScreenTutorialWidgetState extends State<MainScreenTutorialWidget>
    with TickerProviderStateMixin {
  static const double _dialogueFontSize = 15;
  static const String _experienceName = 'The Golden Noodle House';
  static const String _experienceAddress = '123 Foodie St, San Francisco, CA';
  static const double _experienceRating = 4.6;
  static const int _experienceRatingCount = 238;
  static const String _previewVideoAsset =
      'assets/onboarding/restaurant_video.mp4';
  static const int _mediaPlayPromptStepIndex = 3;
  static const int _mediaPreviewInfoStepIndex = 4;
  static const int _mediaDismissPromptStepIndex = 5;
  static const int _switchToMapStepIndex = 6;
  static const int _mapIntroStepIndex = 7;
  static const int _mapDetailsStepIndex = 8;
  static const int _mapTapDetailsStepIndex = 9;
  static const int _mapFullWorldTransitionStepIndex = 10;
  static const Duration _mockModalAnimationDuration =
      Duration(milliseconds: 280);
  static const Duration _mapImageFadeDuration = Duration(milliseconds: 2600);
  static const String _mockMediaSavedAt = 'Jan 12, 2026 • 2:14 PM';
  static const String _mockMediaUrl =
      'https://www.instagram.com/reel/C6pLendyNoodle/';

  static const List<String> _stepDialogues = [
    'Perfect! Your save is now in your *Collection* tab.',
    'Here it is: *The Golden Noodle House* is saved with the *Restaurant* category and red *Want to go* color.',
    'All your saved experiences will be listed here for you to organize and revisit.',
    'You can see there is *1 media item* saved to this experience. Try tapping it!',
    'Here\'s the Instagram video we shared and saved to Plendy, so you can remember why you saved this experience in the first place!',
    'Let\'s dismiss this for now.',
    'Let\'s switch over to the map tab.',
    'Welcome to the *Plendy Map*! Look! The *Golden Noodle House* shows up as a marker.',
    'When a marker is selected, details appear at the bottom so you can quickly open maps or directions.',
    'You can tap there to see even more details.',
    'As you collect more experiences, you\'ll find that the world is full of exciting places to explore!',
    'That\'s enough yapping from me! There\'s a lot more you can do with Plendy but I\'ll let you discover the rest on your own. Get out there and start exploring!',
  ];

  final GlobalKey<_MainTutorialTypewriterTextState> _typewriterKey =
      GlobalKey<_MainTutorialTypewriterTextState>();
  final GlobalKey _collectionTabNavKey = GlobalKey();
  final GlobalKey _mapTabNavKey = GlobalKey();
  final GlobalKey _collectionCardKey = GlobalKey();
  final GlobalKey _mapMarkerKey = GlobalKey();
  final GlobalKey _mapDetailsKey = GlobalKey();

  int _currentStep = 0;
  bool _typewriterComplete = false;
  bool _isCompleting = false;
  _MainTutorialTab _activeTab = _MainTutorialTab.collection;
  bool _isMockMediaPreviewOpen = false;
  bool _isMockMediaPreviewClosing = false;
  late final AnimationController _markerPulseController;
  late final AnimationController _mockModalAnimationController;
  late final Animation<double> _mockModalBackdropOpacity;
  late final Animation<double> _mockModalContentOpacity;
  late final Animation<Offset> _mockModalSlideOffset;
  FileLoader? _mapTabFingerFileLoader;
  VideoPlayerController? _previewVideoController;

  @override
  void initState() {
    super.initState();
    _markerPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
      lowerBound: 0.92,
      upperBound: 1.08,
    )..repeat(reverse: true);
    _mockModalAnimationController = AnimationController(
      vsync: this,
      duration: _mockModalAnimationDuration,
      reverseDuration: _mockModalAnimationDuration,
    );
    _mockModalBackdropOpacity = CurvedAnimation(
      parent: _mockModalAnimationController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _mockModalContentOpacity = CurvedAnimation(
      parent: _mockModalAnimationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _mockModalSlideOffset = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _mockModalAnimationController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _mapTabFingerFileLoader = FileLoader.fromAsset(
      'assets/tutorials/tap_here_finger.riv',
      riveFactory: Factory.flutter,
    );
    _initializeMockPreviewVideo();
    _syncTabToStep();
  }

  @override
  void dispose() {
    _markerPulseController.dispose();
    _mockModalAnimationController.dispose();
    _mapTabFingerFileLoader?.dispose();
    _previewVideoController?.dispose();
    super.dispose();
  }

  String get _currentBirdMessage => _stepDialogues[_currentStep];

  bool get _highlightCollectionNav => _currentStep <= _switchToMapStepIndex;
  bool get _highlightMapNav => _currentStep >= 2;
  bool get _highlightCollectionCard =>
      _currentStep == 1 || _currentStep == _mediaPlayPromptStepIndex;
  bool get _highlightMapMarker => _currentStep == _mapIntroStepIndex;
  bool get _highlightMapDetails =>
      _currentStep == _mapDetailsStepIndex ||
      _currentStep == _mapTapDetailsStepIndex;
  bool get _showMapTabFinger =>
      _currentStep == _switchToMapStepIndex && _typewriterComplete;
  bool get _showPlayButtonFinger =>
      _currentStep == _mediaPlayPromptStepIndex &&
      _typewriterComplete &&
      !_isMockMediaPreviewOpen;
  bool get _showModalCloseFinger =>
      _currentStep == _mediaDismissPromptStepIndex &&
      _typewriterComplete &&
      _isMockMediaPreviewOpen &&
      !_isMockMediaPreviewClosing;

  void _syncTabToStep() {
    _activeTab = _currentStep >= _mapIntroStepIndex
        ? _MainTutorialTab.map
        : _MainTutorialTab.collection;
  }

  void _initializeMockPreviewVideo() {
    _previewVideoController = VideoPlayerController.asset(_previewVideoAsset);
    _previewVideoController!.initialize().then((_) {
      if (!mounted) return;
      _previewVideoController!
        ..setLooping(true)
        ..setVolume(0);
      if (_isMockMediaPreviewOpen) {
        _previewVideoController!.play();
      }
      setState(() {});
    });
  }

  void _handleTutorialTap() {
    if (_isCompleting) return;

    if (!_typewriterComplete) {
      _typewriterKey.currentState?.skipToEnd();
      return;
    }

    if (_currentStep == _mediaPlayPromptStepIndex ||
        _currentStep == _mediaDismissPromptStepIndex ||
        _currentStep == _switchToMapStepIndex) {
      // These steps advance only via their specific target actions.
      return;
    }

    if (_currentStep >= _stepDialogues.length - 1) {
      _isCompleting = true;
      HapticFeedback.mediumImpact();
      widget.onComplete();
      return;
    }

    HapticFeedback.lightImpact();
    setState(() {
      _currentStep++;
      _typewriterComplete = false;
      _syncTabToStep();
    });
  }

  void _onCollectionPlayButtonTapped() {
    if (_currentStep != _mediaPlayPromptStepIndex) return;
    if (!_typewriterComplete) {
      _typewriterKey.currentState?.skipToEnd();
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _isMockMediaPreviewClosing = false;
      _isMockMediaPreviewOpen = true;
      _currentStep = _mediaPreviewInfoStepIndex;
      _typewriterComplete = false;
    });
    _mockModalAnimationController.forward(from: 0);
    _previewVideoController?.play();
  }

  Future<void> _onMockPreviewCloseTapped() async {
    if (_currentStep != _mediaDismissPromptStepIndex) return;
    if (_isMockMediaPreviewClosing) return;
    if (!_typewriterComplete) {
      _typewriterKey.currentState?.skipToEnd();
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _isMockMediaPreviewClosing = true;
    });
    _previewVideoController?.pause();
    await _mockModalAnimationController.reverse();
    if (!mounted) return;
    setState(() {
      _isMockMediaPreviewOpen = false;
      _isMockMediaPreviewClosing = false;
      _currentStep = _switchToMapStepIndex;
      _typewriterComplete = false;
      _syncTabToStep();
    });
  }

  void _handleBottomNavTap(int index) {
    if (index == 1) {
      setState(() {
        _activeTab = _MainTutorialTab.collection;
      });
      return;
    }
    if (index == 2) {
      if (_currentStep == _switchToMapStepIndex) {
        if (!_typewriterComplete) {
          _typewriterKey.currentState?.skipToEnd();
          return;
        }
        HapticFeedback.lightImpact();
        setState(() {
          _isMockMediaPreviewOpen = false;
          _activeTab = _MainTutorialTab.map;
          _currentStep = _mapIntroStepIndex;
          _typewriterComplete = false;
        });
        return;
      }
      if (_currentStep < _mapIntroStepIndex) {
        return;
      }
      setState(() {
        _activeTab = _MainTutorialTab.map;
      });
    }
  }

  int get _activeNavIndex => _activeTab == _MainTutorialTab.collection ? 1 : 2;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Center(
            child: Text(
              'Using Collections and Map',
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
            child: _buildMockMainScreen(),
            overlays: [_buildBirdOverlay()],
            onTap: _handleTutorialTap,
          ),
        ),
      ],
    );
  }

  Widget _buildMockMainScreen() {
    const Size designSize = Size(390, 844);
    final mediaQuery = MediaQuery.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: designSize.width,
          height: designSize.height,
          child: MediaQuery(
            data: mediaQuery.copyWith(
              size: designSize,
              textScaler: TextScaler.linear(1.0),
            ),
            child: _buildMockMainScreenScaffold(),
          ),
        ),
      ),
    );
  }

  Widget _buildMockMainScreenScaffold() {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.backgroundColor,
          appBar: _activeTab == _MainTutorialTab.collection
              ? _buildCollectionsAppBar()
              : _buildMapAppBar(),
          body: _activeTab == _MainTutorialTab.collection
              ? _buildCollectionsTabBody()
              : _buildMapTabBody(),
          floatingActionButton: _activeTab == _MainTutorialTab.collection
              ? _buildMockFab()
              : null,
          bottomNavigationBar: _buildMockBottomNavigationBar(),
        ),
        if (_isMockMediaPreviewOpen) _buildMockSharedMediaPreviewModal(),
      ],
    );
  }

  PreferredSizeWidget _buildCollectionsAppBar() {
    return AppBar(
      title: const Text('Collection'),
      backgroundColor: AppColors.backgroundColor,
      foregroundColor: Colors.black,
      actions: [
        TextButton.icon(
          onPressed: () {},
          style: TextButton.styleFrom(foregroundColor: Colors.black),
          icon: Image.asset(
            'assets/icon/icon-cropped.png',
            height: 22,
          ),
          label: Text(
            'Map',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.sort),
          tooltip: 'Sort',
        ),
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.filter_list),
          tooltip: 'Filter',
        ),
      ],
    );
  }

  PreferredSizeWidget _buildMapAppBar() {
    return AppBar(
      backgroundColor: AppColors.backgroundColor,
      foregroundColor: Colors.black,
      elevation: 0,
      titleSpacing: 0,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 16),
          Image.asset(
            'assets/icon/icon-cropped.png',
            height: 28,
          ),
          const SizedBox(width: 8),
          const Text('Plendy Map'),
        ],
      ),
      actions: [
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.event_outlined),
        ),
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.public),
        ),
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.filter_list),
        ),
      ],
    );
  }

  Widget _buildCollectionsTabBody() {
    return Container(
      color: AppColors.backgroundColor,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            child: TextField(
              enabled: false,
              decoration: InputDecoration(
                labelText: 'Search your experiences',
                labelStyle: TextStyle(color: Colors.grey[700], fontSize: 12),
                filled: true,
                fillColor: AppColors.backgroundColorDark,
                prefixIcon:
                    Icon(Icons.search, color: Theme.of(context).primaryColor),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: _buildCollectionsSegmentedControl(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
            child: Row(
              children: [
                Text(
                  '1 Experience',
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                Icon(Icons.tune, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  'Filtered',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 2, bottom: 92),
              children: [
                _buildHighlightWrapper(
                  key: _collectionCardKey,
                  isHighlighted: _highlightCollectionCard,
                  child: _buildMockCollectionExperienceCard(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionsSegmentedControl() {
    Widget segment({
      required String label,
      required bool selected,
    }) {
      return Expanded(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.grey[700],
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              fontSize: 11,
            ),
          ),
        ),
      );
    }

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.backgroundColorDark,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          segment(label: 'Categories', selected: false),
          segment(label: 'Experiences', selected: true),
          segment(label: 'Saves', selected: false),
        ],
      ),
    );
  }

  Widget _buildMockCollectionExperienceCard() {
    const double playButtonDiameter = 34;
    const double badgeDiameter = 18;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        isThreeLine: true,
        title: const Text(
          _experienceName,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        leading: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(28),
          ),
          alignment: Alignment.center,
          child: const Text(
            '🍜',
            style: TextStyle(fontSize: 27),
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 1),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _experienceAddress,
                    style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _onCollectionPlayButtonTapped,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: playButtonDiameter,
                        height: playButtonDiameter,
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: badgeDiameter,
                          height: badgeDiameter,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).primaryColor,
                              width: 2,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '1',
                            style: TextStyle(
                              color: Theme.of(context).primaryColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      if (_showPlayButtonFinger)
                        Positioned(
                          right: -4,
                          bottom: -40,
                          child: _buildFingerPrompt(
                            angle: -1.5708,
                            size: 42,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  Widget _buildMapTabBody() {
    return Container(
      color: AppColors.backgroundColor,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Card(
              color: AppColors.backgroundColorDark,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TextField(
                  enabled: false,
                  decoration: InputDecoration(
                    hintText: 'Search for a place or address',
                    hintStyle: const TextStyle(fontSize: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide.none,
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: AppColors.backgroundColorDark,
                    prefixIcon: Icon(Icons.search,
                        color: Theme.of(context).primaryColor),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Opacity(
                        opacity: 0.92,
                        child: Image.asset(
                          'assets/tutorials/empty_plendymap_example.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                      AnimatedOpacity(
                        opacity:
                            _currentStep >= _mapFullWorldTransitionStepIndex
                                ? 1.0
                                : 0.0,
                        duration: _mapImageFadeDuration,
                        curve: Curves.easeInOutCubic,
                        child: Opacity(
                          opacity: 0.92,
                          child: Image.asset(
                            'assets/tutorials/full_plendymap_example.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 14,
                  right: 12,
                  child: Column(
                    children: [
                      _buildMapControlButton(Icons.my_location),
                      const SizedBox(height: 8),
                      _buildMapControlButton(Icons.layers_outlined),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 112,
                  child: Center(
                    child: _buildHighlightWrapper(
                      key: _mapMarkerKey,
                      isHighlighted: _highlightMapMarker,
                      borderRadius: 40,
                      child: ScaleTransition(
                        scale: _markerPulseController,
                        child: _buildMockMarker(),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _buildHighlightWrapper(
                    key: _mapDetailsKey,
                    isHighlighted: _highlightMapDetails,
                    borderRadius: 28,
                    child: _buildMapDetailsSheet(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapControlButton(IconData icon) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.13),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, size: 18, color: Colors.black87),
    );
  }

  Widget _buildMockMarker() {
    return Container(
      width: 60,
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.red.withValues(alpha: 0.25), width: 2),
      ),
      child: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        child: const Text(
          '🍜',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }

  Widget _buildMapDetailsSheet() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        8 + MediaQuery.of(context).padding.bottom / 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.backgroundColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              'Tap to view experience details',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '🍜',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  _experienceName,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                ),
              ),
              Icon(Icons.map_outlined, size: 22, color: Colors.grey[700]),
              const SizedBox(width: 10),
              Icon(Icons.directions, size: 22, color: AppColors.sage),
              const SizedBox(width: 10),
              Icon(Icons.close, size: 22, color: Colors.grey[600]),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
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
                    Text(
                      'Want to go',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  _experienceAddress,
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 48,
                height: 48,
                child: OverflowBox(
                  minHeight: 48,
                  maxHeight: 48,
                  alignment: Alignment.center,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).primaryColor,
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '1',
                              style: TextStyle(
                                color: Theme.of(context).primaryColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              ...List.generate(5, (index) {
                return Icon(
                  index < _experienceRating.floor()
                      ? Icons.star
                      : (index < _experienceRating
                          ? Icons.star_half
                          : Icons.star_border),
                  size: 16,
                  color: Colors.amber,
                );
              }),
              const SizedBox(width: 6),
              Text(
                '($_experienceRatingCount)',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMockSharedMediaPreviewModal() {
    final videoController = _previewVideoController;
    final bool isVideoReady = videoController?.value.isInitialized ?? false;

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: FadeTransition(
              opacity: _mockModalBackdropOpacity,
              child: Container(color: Colors.black.withValues(alpha: 0.28)),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position: _mockModalSlideOffset,
              child: FadeTransition(
                opacity: _mockModalContentOpacity,
                child: FractionallySizedBox(
                  heightFactor: 0.95,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.backgroundColor,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 12,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          Container(
                            width: 48,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade400,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _experienceName,
                                    style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                            ) ??
                                        const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    IconButton(
                                      tooltip: 'Close',
                                      icon: const Icon(Icons.close),
                                      onPressed: _onMockPreviewCloseTapped,
                                    ),
                                    if (_showModalCloseFinger)
                                      Positioned(
                                        left: -42,
                                        top: 1,
                                        child: _buildFingerPrompt(angle: 0),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final previewHeight =
                                      constraints.maxHeight * 0.62;
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: Container(
                                          width: double.infinity,
                                          height: previewHeight,
                                          color: Colors.black,
                                          child: isVideoReady
                                              ? Center(
                                                  child: AspectRatio(
                                                    aspectRatio:
                                                        videoController!
                                                            .value.aspectRatio,
                                                    child: VideoPlayer(
                                                        videoController),
                                                  ),
                                                )
                                              : const Center(
                                                  child:
                                                      CircularProgressIndicator(),
                                                ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      _buildMockMediaActionButtons(),
                                      const SizedBox(height: 12),
                                      _buildMockMediaDetailsSection(),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMockMediaActionButtons() {
    final Color primaryColor = Theme.of(context).primaryColor;
    return SizedBox(
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 0,
            child: Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.sage.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.sage.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.code,
                    size: 14,
                    color: AppColors.sage,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Default view',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.sage.withValues(alpha: 0.95),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Center(
            child: Icon(
              FontAwesomeIcons.instagram,
              color: Color(0xFFE1306C),
              size: 30,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.share_outlined,
                  size: 26,
                  color: Colors.blue.shade600,
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.fullscreen,
                  size: 26,
                  color: Colors.blue.shade600,
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 28,
                  color: primaryColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMockMediaDetailsSection() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Details',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.primaryColor,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: theme.primaryColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMockMediaDetailsRow(
                icon: Icons.schedule,
                label: 'Saved',
                value: _mockMediaSavedAt,
              ),
              const SizedBox(height: 8),
              _buildMockMediaDetailsRow(
                icon: Icons.public,
                label: 'URL',
                value: _mockMediaUrl,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMockMediaDetailsRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFingerPrompt({
    required double angle,
    double size = 42,
  }) {
    if (_mapTabFingerFileLoader == null) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * 0.62,
            height: size * 0.62,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.36),
                  blurRadius: 10,
                  spreadRadius: 1.5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
          IgnorePointer(
            child: Transform.rotate(
              angle: angle,
              child: RiveWidgetBuilder(
                fileLoader: _mapTabFingerFileLoader!,
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
        ],
      ),
    );
  }

  Widget _buildMockBottomNavigationBar() {
    return BottomNavigationBar(
      currentIndex: _activeNavIndex,
      onTap: _handleBottomNavTap,
      type: BottomNavigationBarType.fixed,
      backgroundColor: AppColors.backgroundColor,
      selectedItemColor: Theme.of(context).primaryColor,
      unselectedItemColor: Colors.grey,
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.explore_outlined),
          label: 'Discovery',
        ),
        BottomNavigationBarItem(
          icon: _buildNavIcon(
            key: _collectionTabNavKey,
            icon: Icons.collections_bookmark_outlined,
            isHighlighted: _highlightCollectionNav,
          ),
          label: 'Collection',
        ),
        BottomNavigationBarItem(
          icon: _buildNavIcon(
            key: _mapTabNavKey,
            icon: Icons.map_outlined,
            isHighlighted: _highlightMapNav,
            showFinger: _showMapTabFinger,
          ),
          label: 'Map',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.event_outlined),
          label: 'Plans',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: 'Me',
        ),
      ],
    );
  }

  Widget _buildNavIcon({
    required GlobalKey key,
    required IconData icon,
    required bool isHighlighted,
    bool showFinger = false,
  }) {
    return AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: isHighlighted
            ? Border.all(color: AppColors.teal, width: 1.8)
            : null,
        boxShadow: isHighlighted
            ? [
                BoxShadow(
                  color: AppColors.teal.withValues(alpha: 0.28),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(icon),
          if (showFinger && _mapTabFingerFileLoader != null)
            Positioned(
              top: -40,
              child: _buildFingerPrompt(angle: 1.5708),
            ),
        ],
      ),
    );
  }

  Widget _buildMockFab() {
    return FloatingActionButton(
      onPressed: () {},
      backgroundColor: Theme.of(context).primaryColor,
      foregroundColor: Colors.white,
      shape: const CircleBorder(),
      child: const Icon(Icons.add),
    );
  }

  Widget _buildBirdOverlay() {
    final bool isFinalStep = _currentStep == _stepDialogues.length - 1;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      right: 12,
      bottom: 300,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 220,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
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
                          children: _buildMainTutorialFormattedSpans(
                            _currentBirdMessage,
                            GoogleFonts.fredoka(
                              fontSize: _dialogueFontSize,
                              color: Colors.black87,
                              height: 1.4,
                            ),
                          ),
                        ),
                      )
                    : _MainTutorialTypewriterText(
                        key: _typewriterKey,
                        text: _currentBirdMessage,
                        style: GoogleFonts.fredoka(
                          fontSize: _dialogueFontSize,
                          color: Colors.black87,
                          height: 1.4,
                        ),
                        onComplete: () {
                          if (!mounted) return;
                          setState(() {
                            _typewriterComplete = true;
                          });
                        },
                      ),
                if (_typewriterComplete)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _currentStep == _mediaPlayPromptStepIndex
                          ? 'Tap the play button'
                          : _currentStep == _mediaDismissPromptStepIndex
                              ? 'Tap the X button'
                              : _currentStep == _switchToMapStepIndex
                                  ? 'Tap the Map tab'
                                  : (isFinalStep
                                      ? 'Tap anywhere to finish'
                                      : 'Tap to continue'),
                      style: GoogleFonts.fredoka(
                        fontSize: 10,
                        color: (isFinalStep ||
                                _currentStep == _mediaPlayPromptStepIndex ||
                                _currentStep == _mediaDismissPromptStepIndex ||
                                _currentStep == _switchToMapStepIndex)
                            ? AppColors.teal
                            : Colors.grey[400],
                        fontStyle: FontStyle.italic,
                        fontWeight: (isFinalStep ||
                                _currentStep == _mediaPlayPromptStepIndex ||
                                _currentStep == _mediaDismissPromptStepIndex ||
                                _currentStep == _switchToMapStepIndex)
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
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

  Widget _buildHighlightWrapper({
    required GlobalKey key,
    required bool isHighlighted,
    required Widget child,
    double borderRadius = 12,
  }) {
    return Container(
      key: key,
      decoration: isHighlighted
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              boxShadow: [
                BoxShadow(
                  color: AppColors.teal.withValues(alpha: 0.32),
                  blurRadius: 9,
                  spreadRadius: 2,
                ),
              ],
            )
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          border: isHighlighted
              ? Border.all(color: AppColors.teal, width: 2)
              : null,
        ),
        child: child,
      ),
    );
  }

  Widget _buildPhoneFrameWithContent({
    required Widget child,
    List<Widget>? overlays,
    required VoidCallback onTap,
  }) {
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
                Positioned.fill(
                  child: IgnorePointer(
                    child: Image.asset(
                      'assets/tutorials/apple-iphone-15-black-portrait.png',
                      fit: BoxFit.fill,
                    ),
                  ),
                ),
                if (overlays != null) ...overlays,
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerUp: (_) => onTap(),
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

class _MainTutorialTypewriterText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final VoidCallback? onComplete;

  const _MainTutorialTypewriterText({
    super.key,
    required this.text,
    this.style,
    this.onComplete,
  });

  @override
  State<_MainTutorialTypewriterText> createState() =>
      _MainTutorialTypewriterTextState();
}

class _MainTutorialTypewriterTextState
    extends State<_MainTutorialTypewriterText> {
  Timer? _timer;
  String _displayText = '';
  int _currentIndex = 0;
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    _startTypewriter();
  }

  @override
  void didUpdateWidget(covariant _MainTutorialTypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _startTypewriter();
    }
  }

  void _startTypewriter() {
    _timer?.cancel();
    setState(() {
      _displayText = '';
      _currentIndex = 0;
      _isComplete = false;
    });
    _typeNextCharacter();
  }

  void _typeNextCharacter() {
    if (_currentIndex < widget.text.length) {
      _timer = Timer(const Duration(milliseconds: 30), () {
        if (!mounted) return;
        setState(() {
          _displayText = widget.text.substring(0, _currentIndex + 1);
          _currentIndex++;
        });
        _typeNextCharacter();
      });
    } else if (!_isComplete) {
      _isComplete = true;
      widget.onComplete?.call();
    }
  }

  void skipToEnd() {
    _timer?.cancel();
    if (!_isComplete) {
      setState(() {
        _displayText = widget.text;
        _currentIndex = widget.text.length;
        _isComplete = true;
      });
      widget.onComplete?.call();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: _buildMainTutorialFormattedSpans(_displayText, widget.style),
      ),
    );
  }
}
