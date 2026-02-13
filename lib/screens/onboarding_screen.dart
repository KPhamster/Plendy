import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:rive/rive.dart' hide Animation;
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../config/colors.dart';
import '../services/user_service.dart';
import '../widgets/save_tutorial_widget.dart';

// DEV MODE: Set to true to enable onboarding testing for kevinphamster1
// This user will always see onboarding and profile saves will be skipped
// TODO: Remove this when done testing onboarding
const bool devModeOnboardingTest = true;
const String devModeTestUsername = 'aaa';
const bool devModeStartAtSaveTutorial = true;

class OnboardingScreen extends StatefulWidget {
  final VoidCallback? onFinishedFlow;

  const OnboardingScreen({super.key, this.onFinishedFlow});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  static const String _instagramVideoAsset =
      'assets/onboarding/restaurant_video.mp4';
  static const String _eggHatchVideoAsset =
      'assets/onboarding/egg_hatch_intro.mp4';

  final PageController _pageController = PageController();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final FocusNode _displayNameFocus = FocusNode();
  final FocusNode _usernameFocus = FocusNode();
  final UserService _userService = UserService();

  VideoPlayerController? _instagramVideoController;
  Future<void>? _instagramVideoInitialization;

  // Egg hatch video
  VideoPlayerController? _eggHatchVideoController;
  Future<void>? _eggHatchVideoInitialization;
  bool _eggHatchVideoCompleted = false;
  bool _showEggHatchFadeToWhite = false;

  // Rive animations
  FileLoader? _rightArrowFileLoader;
  FileLoader? _birdWavingFileLoader;
  FileLoader? _successAnimationFileLoader;

  // Success animation state
  bool _showSuccessAnimation = false;
  final GlobalKey _plendyButtonKey = GlobalKey();

  int _currentPage = 0;
  bool _isSavingProfile = false;
  bool _isCompletingOnboarding = false;
  String? _displayNameError;
  String? _usernameError;
  int _speechBubbleMessageIndex = 0;
  bool _firstBirdTypewriterComplete = false;
  bool _showHandPointer = false;
  bool _showShareSheet = false;
  bool _showFirstBird = false;
  bool _showSecondBird = false;
  bool _secondTypewriterComplete = false;
  bool _showSecondHandPointer = false;
  bool _showIOSShareSheet = false;
  bool _isDismissingInstagramSheet = false;
  bool _showThirdBird = false;
  int _thirdBirdMessageIndex = 0;
  bool _showRightArrow = false;
  bool _thirdBirdFirstMessageComplete = false;
  bool _thirdBirdSecondMessageComplete = false;
  bool _showMoreButtonHand = false;
  bool _showAppsSheet = false;
  bool _showAppsSheetBird = false;
  bool _appsSheetTypewriterComplete = false;
  bool _showDownArrow = false;
  bool _showPlendyHand = false;

  // Post-Plendy tap dialogue state
  bool _showPostPlendyDialogue = false;
  int _postPlendyDialogueIndex = 0;
  bool _postPlendyTypewriterComplete = false;
  late AnimationController _postPlendyBirdSlideController;
  late Animation<double> _postPlendyBirdSlideAnimation;

  // Apps sheet edit mode state
  bool _isAppsSheetEditMode = false;
  List<_OnboardingAppItem> _editFavoriteApps = [];
  List<_OnboardingAppItem> _editSuggestedApps = [];

  // Edit mode dialogue state
  int _editModeDialogueIndex = 0;
  bool _editModeTypewriterComplete = false;
  bool _showEditModePlendyHand = false;
  bool _showEditModeDragHand = false;
  bool _showEditModeDownArrow = false;
  bool _plendyReachedTop = false;
  late AnimationController _editModeBirdSlideController;
  late Animation<double> _editModeBirdSlideAnimation;

  // Real sharing step state
  bool _showRealSharingStep = false;
  int _realSharingDialogueIndex = 0;
  bool _realSharingTypewriterComplete = false;
  bool _showRealSharingButtons = false;
  late AnimationController _realSharingButtonsController;
  late Animation<double> _shareButton1Animation;
  late Animation<double> _shareButton2Animation;
  late Animation<double> _shareButton3Animation;

  // Save tutorial transition dialogue state
  bool _showSaveTutorialTransition = false;
  int _saveTutorialTransitionIndex = 0;
  bool _saveTutorialTransitionTypewriterComplete = false;

  // Save tutorial step state
  bool _showSaveTutorialStep = false;

  // Welcome step bird dialogue
  int _welcomeBirdDialogueIndex = 0;
  bool _welcomeBirdTypewriterComplete = false;

  // Welcome step name fields animation
  bool _showNameFields = false;
  bool _showPostSaveDialogues = false;
  int _postSaveDialogueIndex = 0;
  bool _postSaveTypewriterComplete = false;
  String _savedDisplayName = '';
  late AnimationController _birdSlideController;
  late AnimationController _displayNameFadeController;
  late AnimationController _usernameFadeController;
  late Animation<double> _birdSlideAnimation;
  late Animation<double> _displayNameFadeAnimation;
  late Animation<double> _usernameFadeAnimation;

  // Hatched bird image overlay
  bool _showHatchedBirdImage = false;
  late AnimationController _hatchedBirdImageSlideController;
  late Animation<Offset> _hatchedBirdImageSlideAnimation;

  // Basket collection image overlay (post-save dialogues)
  bool _showBasketCollectionImage = false;
  late AnimationController _basketCollectionImageSlideController;
  late Animation<Offset> _basketCollectionImageSlideAnimation;

  final ScrollController _appsRowScrollController = ScrollController();
  final ScrollController _appsSheetScrollController = ScrollController();
  final ScrollController _editModeScrollController = ScrollController();
  final GlobalKey _moreButtonKey = GlobalKey();
  final GlobalKey _editButtonKey = GlobalKey();

  // GlobalKeys for typewriter text widgets to enable skip functionality
  final GlobalKey<_TypewriterTextState> _welcomeTypewriterKey =
      GlobalKey<_TypewriterTextState>();
  final GlobalKey<_TypewriterTextState> _postSaveTypewriterKey =
      GlobalKey<_TypewriterTextState>();
  final GlobalKey<_TypewriterTextState> _secondBubbleTypewriterKey =
      GlobalKey<_TypewriterTextState>();
  final GlobalKey<_TypewriterTextState> _thirdBubbleTypewriterKey =
      GlobalKey<_TypewriterTextState>();
  final GlobalKey<_TypewriterTextWithIconState>
      _thirdBubbleWithIconTypewriterKey =
      GlobalKey<_TypewriterTextWithIconState>();
  final GlobalKey<_TypewriterTextState> _appsSheetTypewriterKey =
      GlobalKey<_TypewriterTextState>();
  final GlobalKey<_TypewriterTextState> _firstBirdTypewriterKey =
      GlobalKey<_TypewriterTextState>();
  final GlobalKey<_TypewriterTextState> _postPlendyTypewriterKey =
      GlobalKey<_TypewriterTextState>();
  final GlobalKey<_TypewriterTextState> _editModeTypewriterKey =
      GlobalKey<_TypewriterTextState>();
  final GlobalKey<_TypewriterTextState> _realSharingTypewriterKey =
      GlobalKey<_TypewriterTextState>();
  final GlobalKey<_TypewriterTextState> _saveTutorialTransitionTypewriterKey =
      GlobalKey<_TypewriterTextState>();

  int get _totalPages => 3;
  bool get _isOnEggHatchVideoStep => _currentPage == 0;
  bool get _isOnWelcomeStep => _currentPage == 1;
  bool get _isOnInstagramTutorialStep => _currentPage == 2;

  bool get _canSubmitProfile =>
      _displayNameController.text.trim().isNotEmpty &&
      _usernameController.text.trim().isNotEmpty &&
      _usernameError == null &&
      !_isSavingProfile;

  String get _primaryButtonLabel {
    if (_isOnEggHatchVideoStep) return 'Get Started';
    if (_isOnWelcomeStep) {
      return _showNameFields ? 'Save & Continue' : 'Next';
    }
    if (_currentPage == _totalPages - 1) return 'Finish';
    return 'Next';
  }

  @override
  void initState() {
    super.initState();
    _displayNameController.addListener(_handleProfileFieldChange);
    _usernameController.addListener(_handleProfileFieldChange);
    _prefillExistingValues();

    // Initialize Rive animation loaders
    _rightArrowFileLoader = FileLoader.fromAsset(
      'assets/tutorials/tap_here_finger.riv',
      riveFactory: Factory.flutter,
    );
    _birdWavingFileLoader = FileLoader.fromAsset(
      'assets/onboarding/bird_waving.riv',
      riveFactory: Factory.flutter,
    );
    _successAnimationFileLoader = FileLoader.fromAsset(
      'assets/tutorials/success.riv',
      riveFactory: Factory.flutter,
    );

    // Initialize welcome step name fields animation controllers
    _birdSlideController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _displayNameFadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _usernameFadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _birdSlideAnimation = CurvedAnimation(
      parent: _birdSlideController,
      curve: Curves.easeOutCubic,
    );
    _displayNameFadeAnimation = CurvedAnimation(
      parent: _displayNameFadeController,
      curve: Curves.easeIn,
    );
    _usernameFadeAnimation = CurvedAnimation(
      parent: _usernameFadeController,
      curve: Curves.easeIn,
    );

    // Initialize hatched bird image slide controller
    // Animation range: 0.0 = off-screen right, 0.5 = center, 1.0 = off-screen left
    _hatchedBirdImageSlideController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _hatchedBirdImageSlideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0), // Start from right
      end: const Offset(-1.0, 0.0), // End at left
    ).animate(CurvedAnimation(
      parent: _hatchedBirdImageSlideController,
      curve: Curves.easeInOut,
    ));

    // Initialize basket collection image slide controller
    // Animation range: 0.0 = off-screen right, 0.5 = center, 1.0 = off-screen left
    _basketCollectionImageSlideController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _basketCollectionImageSlideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0), // Start from right
      end: const Offset(-1.0, 0.0), // End at left
    ).animate(CurvedAnimation(
      parent: _basketCollectionImageSlideController,
      curve: Curves.easeInOut,
    ));

    // Initialize post-Plendy bird slide controller
    _postPlendyBirdSlideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _postPlendyBirdSlideAnimation = CurvedAnimation(
      parent: _postPlendyBirdSlideController,
      curve: Curves.easeOutCubic,
    );

    // Initialize edit mode bird slide controller
    _editModeBirdSlideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _editModeBirdSlideAnimation = CurvedAnimation(
      parent: _editModeBirdSlideController,
      curve: Curves.easeOutCubic,
    );

    // Initialize real sharing buttons animation controller
    _realSharingButtonsController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _shareButton1Animation = CurvedAnimation(
      parent: _realSharingButtonsController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
    );
    _shareButton2Animation = CurvedAnimation(
      parent: _realSharingButtonsController,
      curve: const Interval(0.2, 0.7, curve: Curves.easeOutBack),
    );
    _shareButton3Animation = CurvedAnimation(
      parent: _realSharingButtonsController,
      curve: const Interval(0.4, 0.9, curve: Curves.easeOutBack),
    );

    // Listen to apps row scroll to hide arrow when More button is visible
    _appsRowScrollController.addListener(_onAppsRowScroll);

    // Listen to apps sheet scroll to hide down arrow when scrolled to bottom
    _appsSheetScrollController.addListener(_onAppsSheetScroll);

    // Listen to edit mode scroll to hide down arrow when scrolled to Plendy
    _editModeScrollController.addListener(_onEditModeScroll);

    // Start egg hatch video on initial load (since it's now page 0)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (devModeOnboardingTest && devModeStartAtSaveTutorial) {
        _startSaveTutorialDevMode();
      } else if (mounted && _isOnEggHatchVideoStep) {
        _startEggHatchVideo();
      }
    });
  }

  void _startSaveTutorialDevMode() {
    if (!mounted) return;

    // Jump directly to Instagram tutorial page and open save tutorial from step 1.
    _pageController.jumpToPage(2);
    setState(() {
      _showSaveTutorialTransition = false;
      _saveTutorialTransitionIndex = 0;
      _saveTutorialTransitionTypewriterComplete = false;
      _showRealSharingStep = false;
      _realSharingDialogueIndex = 0;
      _realSharingTypewriterComplete = false;
      _showRealSharingButtons = false;
      _showSaveTutorialStep = true;
    });
  }

  void _onAppsRowScroll() {
    if (!_appsRowScrollController.hasClients) return;

    final maxScroll = _appsRowScrollController.position.maxScrollExtent;
    final currentScroll = _appsRowScrollController.position.pixels;

    // When scrolled near the end (within 50 pixels), hide arrow and show hand
    if (currentScroll >= maxScroll - 50) {
      if (_showRightArrow) {
        setState(() {
          _showRightArrow = false;
          _showMoreButtonHand = true;
        });
      }
    }
  }

  void _onAppsSheetScroll() {
    if (!_appsSheetScrollController.hasClients) return;

    final maxScroll = _appsSheetScrollController.position.maxScrollExtent;
    final currentScroll = _appsSheetScrollController.position.pixels;

    // When scrolled near the end (within 50 pixels), hide down arrow
    if (currentScroll >= maxScroll - 50) {
      if (_showDownArrow) {
        setState(() {
          _showDownArrow = false;
        });
      }
    }
  }

  void _onEditModeScroll() {
    if (!_editModeScrollController.hasClients) return;

    final maxScroll = _editModeScrollController.position.maxScrollExtent;
    final currentScroll = _editModeScrollController.position.pixels;

    // When scrolled near the end (within 50 pixels), hide edit mode down arrow
    if (currentScroll >= maxScroll - 50) {
      if (_showEditModeDownArrow) {
        setState(() {
          _showEditModeDownArrow = false;
        });
      }
    }
  }

  void _prefillExistingValues() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && (user.displayName?.isNotEmpty ?? false)) {
      _displayNameController.text = user.displayName!;
    }

    if (user == null) return;

    _userService.getUserProfile(user.uid).then((profile) {
      if (!mounted) return;

      final profileDisplayName = profile?.displayName ?? '';
      final profileUsername = profile?.username ?? '';

      if (profileDisplayName.trim().isNotEmpty &&
          _displayNameController.text.trim().isEmpty) {
        _displayNameController.text = profileDisplayName;
      }

      if (profileUsername.trim().isNotEmpty &&
          _usernameController.text.trim().isEmpty) {
        _usernameController.text = profileUsername;
      }

      if (_usernameController.text.trim().isNotEmpty) {
        _usernameError = null;
      }

      if (_displayNameController.text.trim().isNotEmpty) {
        _displayNameError = null;
      }

      setState(() {});
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _displayNameController
      ..removeListener(_handleProfileFieldChange)
      ..dispose();
    _usernameController
      ..removeListener(_handleProfileFieldChange)
      ..dispose();
    _displayNameFocus.dispose();
    _usernameFocus.dispose();
    _eggHatchVideoController?.removeListener(_onEggHatchVideoUpdate);
    _eggHatchVideoController?.dispose();
    _instagramVideoController?.dispose();
    _rightArrowFileLoader?.dispose();
    _birdWavingFileLoader?.dispose();
    _successAnimationFileLoader?.dispose();
    _appsRowScrollController.removeListener(_onAppsRowScroll);
    _appsRowScrollController.dispose();
    _appsSheetScrollController.removeListener(_onAppsSheetScroll);
    _appsSheetScrollController.dispose();
    _editModeScrollController.removeListener(_onEditModeScroll);
    _editModeScrollController.dispose();
    _birdSlideController.dispose();
    _displayNameFadeController.dispose();
    _usernameFadeController.dispose();
    _hatchedBirdImageSlideController.dispose();
    _basketCollectionImageSlideController.dispose();
    _postPlendyBirdSlideController.dispose();
    _editModeBirdSlideController.dispose();
    _realSharingButtonsController.dispose();
    super.dispose();
  }

  void _handleProfileFieldChange() {
    if (_isOnWelcomeStep && _showNameFields) {
      final displayNameFilled = _displayNameController.text.trim().isNotEmpty;
      if (_displayNameError != null && displayNameFilled) {
        _displayNameError = null;
      }
      setState(() {});
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);

    // Handle egg hatch video
    if (_isOnEggHatchVideoStep) {
      _startEggHatchVideo();
    } else {
      _eggHatchVideoController?.pause();
    }

    // Handle welcome step
    if (_isOnWelcomeStep) {
      _welcomeBirdDialogueIndex = 0;
      _welcomeBirdTypewriterComplete = false;
      // Reset name fields animation state
      _showNameFields = false;
      _showPostSaveDialogues = false;
      _postSaveDialogueIndex = 0;
      _postSaveTypewriterComplete = false;
      _savedDisplayName = '';
      _birdSlideController.reset();
      _displayNameFadeController.reset();
      _usernameFadeController.reset();
      // Reset hatched bird image state
      _showHatchedBirdImage = false;
      _hatchedBirdImageSlideController.reset();
      // Reset basket collection image state
      _showBasketCollectionImage = false;
      _basketCollectionImageSlideController.reset();
    }

    // Handle Instagram tutorial video
    if (_isOnInstagramTutorialStep) {
      _startInstagramVideo();
      _speechBubbleMessageIndex = 0; // Reset message when entering this step
      _firstBirdTypewriterComplete = false;
      _showHandPointer = false;
      _showShareSheet = false;
      _showFirstBird = false;
      _showSecondBird = false;
      _secondTypewriterComplete = false;
      _showSecondHandPointer = false;
      _showIOSShareSheet = false;
      _isDismissingInstagramSheet = false;
      _showThirdBird = false;
      _thirdBirdMessageIndex = 0;
      _showRightArrow = false;
      _thirdBirdFirstMessageComplete = false;
      _thirdBirdSecondMessageComplete = false;
      _showMoreButtonHand = false;
      _showAppsSheet = false;
      _showAppsSheetBird = false;
      _appsSheetTypewriterComplete = false;
      _showDownArrow = false;
      _showPlendyHand = false;
      _showSuccessAnimation = false;
      _showPostPlendyDialogue = false;
      _postPlendyDialogueIndex = 0;
      _postPlendyTypewriterComplete = false;
      _isAppsSheetEditMode = false;
      _editFavoriteApps = [];
      _editSuggestedApps = [];
      _editModeDialogueIndex = 0;
      _editModeTypewriterComplete = false;
      _showEditModePlendyHand = false;
      _showEditModeDragHand = false;
      _showEditModeDownArrow = false;
      _plendyReachedTop = false;
      _postPlendyBirdSlideController.reset();
      _editModeBirdSlideController.reset();
      _showRealSharingStep = false;
      _realSharingDialogueIndex = 0;
      _realSharingTypewriterComplete = false;
      _showRealSharingButtons = false;
      _realSharingButtonsController.reset();
      // Show first bird after a short delay
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted && _isOnInstagramTutorialStep) {
          setState(() {
            _showFirstBird = true;
          });
        }
      });
    } else {
      _instagramVideoController?.pause();
    }

  }

  void _goToPage(int index) {
    HapticFeedback.lightImpact();
    _pageController.jumpToPage(index);
  }

  void _handleBackPressed() {
    if (_currentPage == 0) return;
    HapticFeedback.lightImpact();
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _handlePrimaryAction() async {
    if (_isCompletingOnboarding) return;
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();

    if (_isOnEggHatchVideoStep) {
      _goToPage(1);
      return;
    }

    if (_isOnWelcomeStep) {
      if (!_showNameFields) {
        // Trigger the animation to show name fields
        _triggerNameFieldsAnimation();
      } else {
        // Name fields are showing, submit the profile info
        await _submitProfileInfo();
      }
      return;
    }

    if (_currentPage == _totalPages - 1) {
      await _completeOnboarding();
      return;
    }

    _goToPage(_currentPage + 1);
  }

  Future<void> _submitProfileInfo() async {
    final displayName = _displayNameController.text.trim();
    final username = _usernameController.text.trim();

    setState(() {
      _displayNameError =
          displayName.isEmpty ? 'Display name is required' : null;
    });
    _validateUsernameFormat(username);

    if (_displayNameError != null || _usernameError != null) {
      return;
    }

    // DEV MODE: Skip saving for test user - just proceed to post-save dialogues
    if (devModeOnboardingTest && username == devModeTestUsername) {
      print(
          'DEV MODE: Skipping profile save for test user $devModeTestUsername');
      _triggerPostSaveDialogues(displayName);
      return;
    }

    setState(() => _isSavingProfile = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No signed-in user found.');
      }

      final success = await _userService.setUsername(user.uid, username);
      if (!success) {
        setState(() => _usernameError = 'Could not save username. Try again.');
        return;
      }

      await user.updateDisplayName(displayName);
      await _userService.updateUserCoreData(user.uid, {
        'displayName': displayName,
        'hasCompletedOnboarding': true,
        'hasFinishedOnboardingFlow': true,
      });

      if (!mounted) return;
      _triggerPostSaveDialogues(displayName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save profile info: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingProfile = false);
      }
    }
  }

  void _validateUsernameFormat(String value) {
    final username = value.trim();
    String? error;

    if (username.isEmpty) {
      error = 'Username is required';
    } else if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(username)) {
      error = 'Use 3-20 letters, numbers, or underscores';
    }

    setState(() {
      _usernameError = error;
    });
  }

  Future<void> _completeOnboarding() async {
    if (_isCompletingOnboarding) return;
    setState(() => _isCompletingOnboarding = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No signed-in user found.');
      }
      widget.onFinishedFlow?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCompletingOnboarding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not finish onboarding: $e')),
      );
      return;
    }
    if (mounted) {
      setState(() => _isCompletingOnboarding = false);
    }
  }

  void _startEggHatchVideo() {
    // Reset state when starting
    _eggHatchVideoCompleted = false;
    _showEggHatchFadeToWhite = false;

    if (_eggHatchVideoController == null) {
      _eggHatchVideoController =
          VideoPlayerController.asset(_eggHatchVideoAsset);
      _eggHatchVideoInitialization =
          _eggHatchVideoController!.initialize().then((_) {
        _eggHatchVideoController!.setLooping(false); // Play only once
        _eggHatchVideoController!.setVolume(1.0);
        _eggHatchVideoController!.addListener(_onEggHatchVideoUpdate);
        if (mounted && _isOnEggHatchVideoStep) {
          _eggHatchVideoController!.play();
          setState(() {});
        }
      });
    } else if (_eggHatchVideoController!.value.isInitialized) {
      _eggHatchVideoController!
        ..seekTo(Duration.zero)
        ..play();
    } else {
      _eggHatchVideoInitialization?.then((_) {
        if (!mounted || !_isOnEggHatchVideoStep) return;
        _eggHatchVideoController!
          ..seekTo(Duration.zero)
          ..play();
        setState(() {});
      });
    }
  }

  void _onEggHatchVideoUpdate() {
    if (!mounted || _eggHatchVideoCompleted) return;

    final controller = _eggHatchVideoController;
    if (controller == null || !controller.value.isInitialized) return;

    // Check if video has completed
    if (controller.value.isCompleted) {
      _eggHatchVideoCompleted = true;

      // Start fade to white animation
      setState(() {
        _showEggHatchFadeToWhite = true;
      });

      // After fade completes, go to next page (Welcome to Plendy)
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          _goToPage(1); // Go to Welcome step
        }
      });
    }
  }

  void _startInstagramVideo() {
    if (_instagramVideoController == null) {
      _instagramVideoController =
          VideoPlayerController.asset(_instagramVideoAsset);
      _instagramVideoInitialization =
          _instagramVideoController!.initialize().then((_) {
        _instagramVideoController!.setLooping(true);
        _instagramVideoController!.setVolume(0);
        if (mounted && _isOnInstagramTutorialStep) {
          _instagramVideoController!.play();
          setState(() {});
        }
      });
    } else if (_instagramVideoController!.value.isInitialized) {
      _instagramVideoController!
        ..seekTo(Duration.zero)
        ..play();
    } else {
      _instagramVideoInitialization?.then((_) {
        if (!mounted || !_isOnInstagramTutorialStep) return;
        _instagramVideoController!
          ..seekTo(Duration.zero)
          ..play();
        setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryButtonStyle = ElevatedButton.styleFrom(
      backgroundColor: theme.primaryColor,
      foregroundColor: Colors.white,
      disabledBackgroundColor: theme.primaryColor.withOpacity(0.3),
      disabledForegroundColor: Colors.white70,
    );

    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: _onPageChanged,
                    children: [
                      _buildEggHatchVideoStep(theme),
                      _buildWelcomeStep(theme),
                      _buildInstagramTutorialStep(theme),
                    ],
                  ),
                ),
                Visibility(
                  // Only show buttons on welcome step with name fields and valid input
                  visible: _isOnWelcomeStep &&
                      _showNameFields &&
                      _canSubmitProfile,
                  maintainState: true,
                  maintainAnimation: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Row(
                      children: [
                        // Hide back button on welcome step
                        if (_currentPage > 0 && !_isOnWelcomeStep)
                          TextButton(
                            onPressed: _handleBackPressed,
                            child: const Text('Back'),
                          )
                        else
                          const SizedBox(width: 80),
                        const Spacer(),
                        SizedBox(
                          width: 200,
                          child: ElevatedButton(
                            style: primaryButtonStyle,
                            onPressed:
                                (_isOnWelcomeStep &&
                                            _showNameFields &&
                                            !_canSubmitProfile) ||
                                        _isCompletingOnboarding ||
                                        _isSavingProfile
                                    ? null
                                    : _handlePrimaryAction,
                            child: _isSavingProfile
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : _isCompletingOnboarding &&
                                        _currentPage == _totalPages - 1
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                        ),
                                      )
                                    : Text(_primaryButtonLabel),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Success animation overlay above the Plendy button (rendered above everything)
          if (_showSuccessAnimation && _successAnimationFileLoader != null)
            Builder(
              builder: (context) {
                // Get the Plendy button position via its GlobalKey
                final RenderBox? plendyBox = _plendyButtonKey.currentContext
                    ?.findRenderObject() as RenderBox?;
                if (plendyBox == null) return const SizedBox.shrink();
                final plendyPosition = plendyBox.localToGlobal(Offset.zero);
                final plendySize = plendyBox.size;
                return Positioned(
                  left: plendyPosition.dx +
                      (plendySize.width / 2) -
                      100, // Center horizontally
                  top: plendyPosition.dy - 180, // Place above the button
                  child: IgnorePointer(
                    child: SizedBox(
                      width: 200,
                      height: 200,
                      child: RiveWidgetBuilder(
                        fileLoader: _successAnimationFileLoader!,
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
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildWelcomeStep(ThemeData theme) {
    final welcomeDialogues = [
      "Oh, hello!",
      "I'm Plendy, your new exploration buddy!",
      "I just hatched and am so excited to experience the world with you!",
      "What's your name?",
    ];

    final postSaveDialogues = [
      "Nice to meet you, $_savedDisplayName!",
      "Looking forward to exploring many experiences together.",
      "Save all your recommendations from anywhere to Plendy so you actually go out and do them!",
      "First, let me show you how to share and save to Plendy.",
    ];

    // Determine which text to show in the speech bubble
    String speechBubbleText;
    if (_showPostSaveDialogues) {
      speechBubbleText = postSaveDialogues[_postSaveDialogueIndex];
    } else {
      speechBubbleText = welcomeDialogues[_welcomeBirdDialogueIndex];
    }

    // Handle tap for different states
    void handleTap() {
      HapticFeedback.lightImpact();

      if (_showPostSaveDialogues) {
        // Post-save dialogues phase
        if (!_postSaveTypewriterComplete) {
          _postSaveTypewriterKey.currentState?.skipToEnd();
        } else if (_postSaveDialogueIndex < postSaveDialogues.length - 1) {
          final nextIndex = _postSaveDialogueIndex + 1;
          setState(() {
            _postSaveDialogueIndex = nextIndex;
            _postSaveTypewriterComplete = false;
          });
          // Slide in basket collection image when "Save all your recommendations" dialogue appears (index 2)
          if (nextIndex == 2) {
            _showBasketCollectionImage = true;
            _basketCollectionImageSlideController
                .animateTo(0.5); // Slide to center
          }
          // Slide out basket collection image to the left when moving to next dialogue (index 3)
          if (nextIndex == 3 && _showBasketCollectionImage) {
            _basketCollectionImageSlideController.animateTo(1.0).then((_) {
              if (mounted) {
                setState(() {
                  _showBasketCollectionImage = false;
                });
              }
            });
          }
        } else {
          // Finished all post-save dialogues, go to next page
          _goToPage(2);
        }
      } else {
        // Initial dialogues phase
        if (!_welcomeBirdTypewriterComplete) {
          _welcomeTypewriterKey.currentState?.skipToEnd();
        } else if (_welcomeBirdDialogueIndex < welcomeDialogues.length - 1) {
          final nextIndex = _welcomeBirdDialogueIndex + 1;
          setState(() {
            _welcomeBirdDialogueIndex = nextIndex;
            _welcomeBirdTypewriterComplete = false;
          });
          // Slide in hatched bird image when "I just hatched" dialogue appears (index 2)
          if (nextIndex == 2) {
            _showHatchedBirdImage = true;
            _hatchedBirdImageSlideController.animateTo(0.5); // Slide to center
          }
        } else {
          // On last dialogue ("What's your name?"), trigger name fields animation
          _triggerNameFieldsAnimation();
        }
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _showNameFields ? null : handleTap,
      child: _showNameFields
          // Name fields phase: scrollable layout with bird at top and fields below
          ? SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Animated bird and speech bubble container
                  AnimatedBuilder(
                    animation: _birdSlideAnimation,
                    builder: (context, child) {
                      final birdSize = 280.0 -
                          (80.0 * _birdSlideAnimation.value); // 280 -> 200
                      final bubbleWidth = 260.0 -
                          (60.0 * _birdSlideAnimation.value); // 260 -> 200
                      final bubblePadding =
                          16.0 - (4.0 * _birdSlideAnimation.value); // 16 -> 12
                      final fontSize =
                          18.0 - (4.0 * _birdSlideAnimation.value); // 18 -> 14
                      final spacing =
                          16.0 - (6.0 * _birdSlideAnimation.value); // 16 -> 10

                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Speech bubble on top
                            Container(
                              width: bubbleWidth,
                              padding: EdgeInsets.all(bubblePadding),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Text(
                                speechBubbleText,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.fredoka(
                                  fontSize: fontSize,
                                  color: Colors.black87,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            SizedBox(height: spacing),
                            // Bird animation below
                            SizedBox(
                              width: birdSize,
                              height: birdSize,
                              child: _birdWavingFileLoader != null
                                  ? RiveWidgetBuilder(
                                      fileLoader: _birdWavingFileLoader!,
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
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  // Display Name field
                  FadeTransition(
                    opacity: _displayNameFadeAnimation,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _displayNameController,
                          focusNode: _displayNameFocus,
                          decoration: InputDecoration(
                            labelText: 'Display Name',
                            hintText: 'e.g. Taylor Adams',
                            errorText: _displayNameError,
                          ),
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) => _usernameFocus.requestFocus(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This is how your name will be displayed for others to see. It can be anything you want!',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Username field
                  FadeTransition(
                    opacity: _usernameFadeAnimation,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _usernameController,
                          focusNode: _usernameFocus,
                          decoration: InputDecoration(
                            labelText: 'Username',
                            hintText: 'e.g. tayloradams',
                            prefixText: '@',
                            errorText: _usernameError,
                          ),
                          textInputAction: TextInputAction.done,
                          onChanged: _validateUsernameFormat,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This is how you are identified. Usernames must be unique and must be 3-20 characters long.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          // Before name fields OR post-save dialogues: bird positioned at bottom-center
          : Stack(
              children: [
                // Hatched bird image at top half of screen (behind speech bubble)
                if (_showHatchedBirdImage)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SlideTransition(
                      position: _hatchedBirdImageSlideAnimation,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(32, 60, 32, 0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            'assets/onboarding/hatched_bird_image.jpeg',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                // Basket collection image at top half of screen (behind speech bubble)
                if (_showBasketCollectionImage)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SlideTransition(
                      position: _basketCollectionImageSlideAnimation,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(32, 60, 32, 0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            'assets/onboarding/basket_collection_image.jpeg',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                // Speech bubble and bird (on top of image)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    children: [
                      const Spacer(),
                      // Speech bubble and bird stacked vertically
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Speech bubble on top
                            Container(
                              width: 260,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: _showPostSaveDialogues
                                  // Post-save dialogues with typewriter
                                  ? (_postSaveTypewriterComplete
                                      ? Text(
                                          speechBubbleText,
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.fredoka(
                                            fontSize: 18,
                                            color: Colors.black87,
                                            height: 1.4,
                                          ),
                                        )
                                      : _TypewriterText(
                                          key: _postSaveTypewriterKey,
                                          text: speechBubbleText,
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.fredoka(
                                            fontSize: 18,
                                            color: Colors.black87,
                                            height: 1.4,
                                          ),
                                          speed:
                                              const Duration(milliseconds: 40),
                                          onComplete: () {
                                            setState(() {
                                              _postSaveTypewriterComplete =
                                                  true;
                                            });
                                          },
                                        ))
                                  // Initial dialogues with typewriter
                                  : (_welcomeBirdTypewriterComplete
                                      ? Text(
                                          speechBubbleText,
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.fredoka(
                                            fontSize: 18,
                                            color: Colors.black87,
                                            height: 1.4,
                                          ),
                                        )
                                      : _TypewriterText(
                                          key: _welcomeTypewriterKey,
                                          text: speechBubbleText,
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.fredoka(
                                            fontSize: 18,
                                            color: Colors.black87,
                                            height: 1.4,
                                          ),
                                          speed:
                                              const Duration(milliseconds: 40),
                                          onComplete: () {
                                            setState(() {
                                              _welcomeBirdTypewriterComplete =
                                                  true;
                                            });
                                          },
                                        )),
                            ),
                            const SizedBox(height: 8),
                            // Bird animation below
                            SizedBox(
                              width: 280,
                              height: 280,
                              child: _birdWavingFileLoader != null
                                  ? RiveWidgetBuilder(
                                      fileLoader: _birdWavingFileLoader!,
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
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  void _triggerNameFieldsAnimation() {
    setState(() {
      _showNameFields = true;
    });

    // Slide out the hatched bird image to the left if visible
    if (_showHatchedBirdImage) {
      _hatchedBirdImageSlideController.animateTo(1.0).then((_) {
        if (mounted) {
          setState(() {
            _showHatchedBirdImage = false;
          });
        }
      });
    }

    // Start the bird slide animation
    _birdSlideController.forward();

    // Stagger the fade-in animations
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _displayNameFadeController.forward();
      }
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _usernameFadeController.forward();
        // Focus the display name field after animation
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            _displayNameFocus.requestFocus();
          }
        });
      }
    });
  }

  void _triggerPostSaveDialogues(String displayName) {
    // Store the display name for use in dialogue
    _savedDisplayName = displayName;

    // Fade out the name fields
    _displayNameFadeController.reverse();
    _usernameFadeController.reverse();

    // After fields fade out, slide bird back down and show post-save dialogues
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        _birdSlideController.reverse();
        setState(() {
          _showNameFields = false;
          _showPostSaveDialogues = true;
          _postSaveDialogueIndex = 0;
          _postSaveTypewriterComplete = false;
          _isSavingProfile = false;
        });
      }
    });
  }

  Widget _buildEggHatchVideoStep(ThemeData theme) {
    final controller = _eggHatchVideoController;
    final isInitialized = controller?.value.isInitialized ?? false;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Video background - full screen white
        Container(
          color: Colors.white,
          child: isInitialized
              ? Center(
                  child: AspectRatio(
                    aspectRatio: controller!.value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                )
              : const Center(
                  child: CircularProgressIndicator(color: Colors.black),
                ),
        ),
        // Fade to white overlay
        AnimatedOpacity(
          opacity: _showEggHatchFadeToWhite ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
          child: Container(
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildInstagramTutorialStep(ThemeData theme) {
    if (_showSaveTutorialStep) {
      return SaveTutorialWidget(
        onComplete: () {
          setState(() {
            _showSaveTutorialStep = false;
            // Return to real sharing step
          });
        },
      );
    }
    if (_showRealSharingStep) {
      return _buildRealSharingStep(theme);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            'How to share from Instagram',
            style: GoogleFonts.notoSerif(
              fontSize: theme.textTheme.titleLarge?.fontSize ?? 22,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
        Expanded(
          child: _buildPhoneFrameWithContent(
            child: _buildFakeInstagramReel(),
            overlays: _buildBirdOverlays(),
          ),
        ),
      ],
    );
  }

  /// Builds bird and speech bubble overlays that appear above the phone bezel
  List<Widget> _buildBirdOverlays() {
    final List<Widget> overlays = [];

    // First bird and speech bubble (on send button)
    if (_showFirstBird) {
      // Speech bubble
      overlays.add(
        Positioned(
          right: 120,
          bottom: 220,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (!_firstBirdTypewriterComplete) {
                HapticFeedback.lightImpact();
                _firstBirdTypewriterKey.currentState?.skipToEnd();
              } else if (_speechBubbleMessageIndex < 2) {
                HapticFeedback.lightImpact();
                setState(() {
                  _speechBubbleMessageIndex++;
                  _firstBirdTypewriterComplete = false;
                });
              }
            },
            child: Container(
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
              child: _firstBirdTypewriterComplete
                  ? Text(
                      _speechBubbleMessageIndex == 0
                          ? 'Check out this reel I found on Instagram!'
                          : _speechBubbleMessageIndex == 1
                              ? 'That looks yummy! Let\'s save this restaurant to Plendy.'
                              : 'First, we need to find the share button to share this reel to Plendy. To find this in Instagram, tap this send button.',
                      style: GoogleFonts.fredoka(
                        fontSize: 15,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                    )
                  : _TypewriterText(
                      key: _firstBirdTypewriterKey,
                      text: _speechBubbleMessageIndex == 0
                          ? 'Check out this reel I found on Instagram!'
                          : _speechBubbleMessageIndex == 1
                              ? 'That looks yummy! Let\'s save this restaurant to Plendy.'
                              : 'First, we need to find the share button to share this reel to Plendy. To find this in Instagram, tap this send button.',
                      style: GoogleFonts.fredoka(
                        fontSize: 15,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                      speed: const Duration(milliseconds: 30),
                      onComplete: () {
                        setState(() {
                          _firstBirdTypewriterComplete = true;
                          if (_speechBubbleMessageIndex == 2) {
                            _showHandPointer = true;
                          }
                        });
                      },
                    ),
            ),
          ),
        ),
      );
      // First bird
      overlays.add(
        Positioned(
          right: 90,
          bottom: 200,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Lottie.asset(
              'assets/mascot/bird_talking_head.json',
              fit: BoxFit.contain,
              options: LottieOptions(enableMergePaths: true),
            ),
          ),
        ),
      );
    }

    // Second bird and speech bubble (on Instagram share sheet)
    if (_showShareSheet && _showSecondBird) {
      // Speech bubble
      overlays.add(
        Positioned(
          right: 50,
          bottom: 185,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (!_secondTypewriterComplete) {
                HapticFeedback.lightImpact();
                _secondBubbleTypewriterKey.currentState?.skipToEnd();
              }
            },
            child: Container(
              width: 180,
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
              child: _secondTypewriterComplete
                  ? Text(
                      'There\'s the share button! Let\'s tap it.',
                      style: GoogleFonts.fredoka(
                        fontSize: 15,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                    )
                  : _TypewriterText(
                      key: _secondBubbleTypewriterKey,
                      text: 'There\'s the share button! Let\'s tap it.',
                      style: GoogleFonts.fredoka(
                        fontSize: 15,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                      speed: const Duration(milliseconds: 30),
                      onComplete: () {
                        setState(() {
                          _secondTypewriterComplete = true;
                          _showSecondHandPointer = true;
                        });
                      },
                    ),
            ),
          ),
        ),
      );
      // Second bird
      overlays.add(
        Positioned(
          right: 20,
          bottom: 190,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Lottie.asset(
              'assets/mascot/bird_talking_head.json',
              fit: BoxFit.contain,
              options: LottieOptions(enableMergePaths: true),
            ),
          ),
        ),
      );
    }

    // Third bird and speech bubble (on iOS share sheet)
    if (_showIOSShareSheet && _showThirdBird) {
      // Speech bubble
      overlays.add(
        Positioned(
          right: 50,
          bottom: 420,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_thirdBirdMessageIndex == 0) {
                HapticFeedback.lightImpact();
                if (!_thirdBirdFirstMessageComplete) {
                  _thirdBubbleTypewriterKey.currentState?.skipToEnd();
                } else {
                  setState(() {
                    _thirdBirdMessageIndex++;
                    _thirdBirdFirstMessageComplete = false;
                  });
                }
              } else if (_thirdBirdMessageIndex == 1 &&
                  !_thirdBirdSecondMessageComplete) {
                HapticFeedback.lightImpact();
                _thirdBubbleWithIconTypewriterKey.currentState?.skipToEnd();
              }
            },
            child: Container(
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
              child: _thirdBirdMessageIndex == 0
                  ? (_thirdBirdFirstMessageComplete
                      ? Text(
                          'This is your share sheet. This is where you choose the app you want to share to.',
                          style: GoogleFonts.fredoka(
                            fontSize: 14,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                        )
                      : _TypewriterText(
                          key: _thirdBubbleTypewriterKey,
                          text:
                              'This is your share sheet. This is where you choose the app you want to share to.',
                          style: GoogleFonts.fredoka(
                            fontSize: 14,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                          speed: const Duration(milliseconds: 30),
                          onComplete: () {
                            setState(() {
                              _thirdBirdFirstMessageComplete = true;
                            });
                          },
                        ))
                  : (_thirdBirdSecondMessageComplete
                      ? Text.rich(
                          TextSpan(
                            style: GoogleFonts.fredoka(
                              fontSize: 14,
                              color: Colors.black87,
                              height: 1.4,
                            ),
                            children: [
                              const TextSpan(text: 'Now we need to find the '),
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 2),
                                  child: Image.asset(
                                    'assets/icon/icon-cropped.png',
                                    width: 18,
                                    height: 18,
                                  ),
                                ),
                              ),
                              const TextSpan(
                                  text:
                                      ' Plendy app. If you don\'t see it already, scroll all the way to the right and tap the ••• button.'),
                            ],
                          ),
                        )
                      : _TypewriterTextWithIcon(
                          key: _thirdBubbleWithIconTypewriterKey,
                          textBefore: 'Now we need to find the ',
                          iconPath: 'assets/icon/icon-cropped.png',
                          textAfter:
                              ' Plendy app. If you don\'t see it already, scroll all the way to the right and tap the ••• button.',
                          style: GoogleFonts.fredoka(
                            fontSize: 14,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                          speed: const Duration(milliseconds: 30),
                          onComplete: () {
                            setState(() {
                              _thirdBirdSecondMessageComplete = true;
                              _showRightArrow = true;
                            });
                          },
                        )),
            ),
          ),
        ),
      );
      // Third bird
      overlays.add(
        Positioned(
          right: 20,
          bottom: 400,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Lottie.asset(
              'assets/mascot/bird_talking_head.json',
              fit: BoxFit.contain,
              options: LottieOptions(enableMergePaths: true),
            ),
          ),
        ),
      );
    }

    // Apps sheet bird and speech bubble
    if (_showAppsSheet && _showAppsSheetBird && !_isAppsSheetEditMode) {
      final postPlendyDialogues = [
        'Excellent! That\'s how you successfully share to Plendy from other apps!',
        'Remember, you can share to Plendy like this from all kinds of apps like Instagram, TikTok, Yelp, YouTube, Facebook, webpages, and more!',
        'SHARE_ICONS_DIALOGUE', // Special marker for dialogue with icons
        'Before we move on, let\'s make it even easier to share to Plendy.',
        'You can pin the Plendy app as a Favorite in your share sheet so that you don\'t have to try so hard to find the Plendy app to share to it moving forward.',
        'Tap \'Edit\' in the top-right corner to enter edit mode.',
      ];

      // Speech bubble with animated position
      overlays.add(
        AnimatedBuilder(
          animation: _postPlendyBirdSlideAnimation,
          builder: (context, child) {
            // Slide down by 250 when animation plays (for dialogue index 5+)
            final slideOffset = _postPlendyBirdSlideAnimation.value * 250;
            return Positioned(
              right: 20,
              top: 80 + slideOffset,
              child: child!,
            );
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.lightImpact();
              if (_showPostPlendyDialogue) {
                // Handle post-Plendy dialogue taps
                if (!_postPlendyTypewriterComplete) {
                  _postPlendyTypewriterKey.currentState?.skipToEnd();
                } else if (_postPlendyDialogueIndex <
                    postPlendyDialogues.length - 1) {
                  final nextIndex = _postPlendyDialogueIndex + 1;
                  setState(() {
                    _postPlendyDialogueIndex = nextIndex;
                    _postPlendyTypewriterComplete = false;
                  });
                  // Trigger slide animation when moving to dialogue 5
                  if (nextIndex == 5) {
                    _postPlendyBirdSlideController.forward();
                  }
                }
                // Do nothing when last dialogue is dismissed (index 5)
              } else if (!_appsSheetTypewriterComplete) {
                _appsSheetTypewriterKey.currentState?.skipToEnd();
              }
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
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
                  child: _showPostPlendyDialogue
                      ? (_postPlendyDialogueIndex == 2
                          ? _buildShareIconsDialogue()
                          : _postPlendyTypewriterComplete
                              ? Text(
                                  postPlendyDialogues[_postPlendyDialogueIndex],
                                  style: GoogleFonts.fredoka(
                                    fontSize: 15,
                                    color: Colors.black87,
                                    height: 1.4,
                                  ),
                                )
                              : _TypewriterText(
                                  key: _postPlendyTypewriterKey,
                                  text: postPlendyDialogues[
                                      _postPlendyDialogueIndex],
                                  style: GoogleFonts.fredoka(
                                    fontSize: 15,
                                    color: Colors.black87,
                                    height: 1.4,
                                  ),
                                  speed: const Duration(milliseconds: 30),
                                  onComplete: () {
                                    setState(() {
                                      _postPlendyTypewriterComplete = true;
                                    });
                                  },
                                ))
                      : _appsSheetTypewriterComplete
                          ? Text(
                              'Now you can see all of your apps available to share to. Find the Plendy app in your list of apps and tap it. You might have to scroll down.',
                              style: GoogleFonts.fredoka(
                                fontSize: 15,
                                color: Colors.black87,
                                height: 1.4,
                              ),
                            )
                          : _TypewriterText(
                              key: _appsSheetTypewriterKey,
                              text:
                                  'Now you can see all of your apps available to share to. Find the Plendy app in your list of apps and tap it. You might have to scroll down.',
                              style: GoogleFonts.fredoka(
                                fontSize: 15,
                                color: Colors.black87,
                                height: 1.4,
                              ),
                              speed: const Duration(milliseconds: 30),
                              onComplete: () {
                                setState(() {
                                  _appsSheetTypewriterComplete = true;
                                  _showDownArrow = true;
                                  _showPlendyHand = true;
                                });
                              },
                            ),
                ),
                // Bird animation - overlaps the speech bubble edge
                Transform.translate(
                  offset: const Offset(-12, 0),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Lottie.asset(
                      'assets/mascot/bird_talking_head.json',
                      fit: BoxFit.contain,
                      options: LottieOptions(enableMergePaths: true),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Hand pointer pointing at Edit button from the left
      if (_postPlendyDialogueIndex == 5 && _rightArrowFileLoader != null) {
        overlays.add(
          Positioned(
            right: 90, // Directly to the left of the Edit button
            top: 72, // Vertically aligned with the Edit button in the header
            child: SizedBox(
              width: 48,
              height: 48,
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
        );
      }
    }

    // Edit mode bird dialogue
    if (_isAppsSheetEditMode) {
      final editModeDialogues = [
        'Great! You are now in edit mode.',
        'From here, scroll down and find the Plendy app and tap the + next to it. This will move it to your Favorites section of the share sheet.',
        'Excellent! You added Plendy to your Favorites list.',
        'To really make sure that it\'s the first app you see when sharing, drag it to the top of the Favorites list.',
        'Perfect! Now sharing to Plendy is a piece of cake!',
        'Tap the Done button to save your changes.',
      ];

      // Indices where user must interact with the content (not tap to advance)
      final bool waitingForInteraction =
          (_editModeDialogueIndex == 1 && _editModeTypewriterComplete) ||
              (_editModeDialogueIndex == 3 && _editModeTypewriterComplete) ||
              (_editModeDialogueIndex == 5 && _editModeTypewriterComplete);

      overlays.add(
        AnimatedBuilder(
          animation: _editModeBirdSlideAnimation,
          builder: (context, child) {
            // Slide down by 200 when animation plays (for dialogue index 2+)
            final slideOffset = _editModeBirdSlideAnimation.value * 200;
            return Positioned(
              right: 20,
              top: 330 + slideOffset,
              child: child!,
            );
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.lightImpact();
              if (!_editModeTypewriterComplete) {
                _editModeTypewriterKey.currentState?.skipToEnd();
              } else if (!waitingForInteraction &&
                  _editModeDialogueIndex < editModeDialogues.length - 1) {
                // Advance to next dialogue (skip interaction-wait indices)
                setState(() {
                  _editModeDialogueIndex++;
                  _editModeTypewriterComplete = false;
                });
              }
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
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
                  child: _editModeTypewriterComplete
                      ? Text(
                          editModeDialogues[_editModeDialogueIndex],
                          style: GoogleFonts.fredoka(
                            fontSize: 15,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                        )
                      : _TypewriterText(
                          key: _editModeTypewriterKey,
                          text: editModeDialogues[_editModeDialogueIndex],
                          style: GoogleFonts.fredoka(
                            fontSize: 15,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                          speed: const Duration(milliseconds: 30),
                          onComplete: () {
                            setState(() {
                              _editModeTypewriterComplete = true;
                              if (_editModeDialogueIndex == 1) {
                                _showEditModePlendyHand = true;
                                _showEditModeDownArrow = true;
                              } else if (_editModeDialogueIndex == 3) {
                                _showEditModeDragHand = true;
                              }
                            });
                          },
                        ),
                ),
                // Bird animation
                Transform.translate(
                  offset: const Offset(-12, 0),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Lottie.asset(
                      'assets/mascot/bird_talking_head.json',
                      fit: BoxFit.contain,
                      options: LottieOptions(enableMergePaths: true),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Hand pointer pointing at Done button when "Tap the Done button" dialogue appears
      if (_editModeDialogueIndex == 5 &&
          _editModeTypewriterComplete &&
          _rightArrowFileLoader != null) {
        overlays.add(
          Positioned(
            right: 90, // Directly to the left of the Done button
            top: 72, // Vertically aligned with the Done button in the header
            child: SizedBox(
              width: 48,
              height: 48,
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
        );
      }
    }

    return overlays;
  }

  /// Builds the special dialogue with share button icons
  Widget _buildShareIconsDialogue() {
    if (!_postPlendyTypewriterComplete) {
      return _TypewriterText(
        key: _postPlendyTypewriterKey,
        text:
            'Whenever you find something you want to save, find the share button and share it to Plendy!',
        style: GoogleFonts.fredoka(
          fontSize: 15,
          color: Colors.black87,
          height: 1.4,
        ),
        speed: const Duration(milliseconds: 30),
        onComplete: () {
          setState(() {
            _postPlendyTypewriterComplete = true;
          });
        },
      );
    }

    // Show the full text with icons after typewriter completes
    return RichText(
      text: TextSpan(
        style: GoogleFonts.fredoka(
          fontSize: 15,
          color: Colors.black87,
          height: 1.4,
        ),
        children: [
          const TextSpan(
              text:
                  'Whenever you find something you want to save, find the share button ('),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(Icons.ios_share, size: 18, color: Colors.black87),
          ),
          const TextSpan(text: ' '),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(Icons.share, size: 18, color: Colors.black87),
          ),
          const TextSpan(text: ' '),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Transform.flip(
              flipX: true,
              child: Icon(Icons.reply, size: 18, color: Colors.black87),
            ),
          ),
          const TextSpan(text: ') and share it to Plendy!'),
        ],
      ),
    );
  }

  /// Builds the "real sharing" step after the edit mode tutorial is complete
  Widget _buildRealSharingStep(ThemeData theme) {
    final realSharingDialogues = [
      'Now let\'s do it for real!',
      'Tap any of these share buttons, add Plendy to your Favorites, and try sharing to Plendy. Doesn\'t matter which - they all do the same thing!',
      'Okie dokie! Let\'s go over it again.',
    ];

    final currentMessage = realSharingDialogues[_realSharingDialogueIndex];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Three share buttons centered with action buttons below
        if (_showRealSharingButtons)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () => Share.share('Share to Plendy!'),
                      child: _buildAnimatedLargeShareButton(
                        Icons.ios_share,
                        _shareButton1Animation,
                      ),
                    ),
                    const SizedBox(width: 24),
                    GestureDetector(
                      onTap: () => Share.share('Share to Plendy!'),
                      child: _buildAnimatedLargeShareButton(
                        Icons.share,
                        _shareButton2Animation,
                      ),
                    ),
                    const SizedBox(width: 24),
                    GestureDetector(
                      onTap: () => Share.share('Share to Plendy!'),
                      child: _buildAnimatedLargeShareButton(
                        Icons.reply,
                        _shareButton3Animation,
                        flipX: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                // "I'll do this later" button
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _showSaveTutorialTransition = true;
                      _saveTutorialTransitionIndex = 0;
                      _saveTutorialTransitionTypewriterComplete = false;
                      _showRealSharingButtons = false;
                    });
                  },
                  child: Text(
                    'I\'ll do this later',
                    style: GoogleFonts.fredoka(
                      fontSize: 16,
                      color: Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // "Show me how again" button
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _realSharingDialogueIndex = 2;
                      _realSharingTypewriterComplete = false;
                      _showRealSharingButtons = false;
                    });
                  },
                  child: Text(
                    'Show me how again',
                    style: GoogleFonts.fredoka(
                      fontSize: 16,
                      color: const Color(0xFF0A84FF),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Bird and speech bubble on bottom-right (hidden during save tutorial transition)
        if (!_showSaveTutorialTransition)
          Positioned(
            right: -9,
            bottom: 40,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Speech bubble
                Container(
                  width: 220,
                  padding: const EdgeInsets.all(14),
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
                  child: _realSharingTypewriterComplete
                      ? Text(
                          currentMessage,
                          style: GoogleFonts.fredoka(
                            fontSize: 15,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                        )
                      : _TypewriterText(
                          key: _realSharingTypewriterKey,
                          text: currentMessage,
                          style: GoogleFonts.fredoka(
                            fontSize: 15,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                          speed: const Duration(milliseconds: 30),
                          onComplete: () {
                            setState(() {
                              _realSharingTypewriterComplete = true;
                              // When second dialogue completes, trigger share buttons
                              if (_realSharingDialogueIndex == 1) {
                                _showRealSharingButtons = true;
                                _realSharingButtonsController.forward();
                              }
                              // When "Okie dokie" dialogue completes, auto-reset
                              if (_realSharingDialogueIndex == 2) {
                                Future.delayed(const Duration(milliseconds: 1200),
                                    () {
                                  if (mounted && _realSharingDialogueIndex == 2) {
                                    _resetInstagramTutorial();
                                  }
                                });
                              }
                            });
                          },
                        ),
                ),
                const SizedBox(width: 8),
                // Bird Lottie (larger)
                SizedBox(
                  width: 100,
                  height: 100,
                  child: Lottie.asset(
                    'assets/mascot/bird_talking_head.json',
                    fit: BoxFit.contain,
                    options: LottieOptions(enableMergePaths: true),
                  ),
                ),
              ],
            ),
          ),

        // Tap detector for dialogue advancement
        // Hidden when second dialogue is complete (user should tap share buttons)
        if (!_showSaveTutorialTransition &&
            !(_realSharingDialogueIndex == 1 &&
                _realSharingTypewriterComplete))
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              if (!_realSharingTypewriterComplete) {
                _realSharingTypewriterKey.currentState?.skipToEnd();
              } else if (_realSharingDialogueIndex == 2) {
                // "Okie dokie" complete — reset immediately on tap
                _resetInstagramTutorial();
              } else if (_realSharingDialogueIndex <
                  realSharingDialogues.length - 1) {
                setState(() {
                  _realSharingDialogueIndex++;
                  _realSharingTypewriterComplete = false;
                });
              }
            },
            behavior: HitTestBehavior.translucent,
          ),

        // Save tutorial transition dialogue overlay
        if (_showSaveTutorialTransition) ..._buildSaveTutorialTransition(),
      ],
    );
  }

  /// Builds the transition dialogue overlays before the save tutorial begins
  List<Widget> _buildSaveTutorialTransition() {
    const transitionDialogues = [
      'Okay, let\'s move on. So what happens when you share to Plendy?',
      'This is where the magic happens! Come with me and I\'ll show you how it works.',
    ];

    final currentMessage = transitionDialogues[_saveTutorialTransitionIndex];

    return [
      // Semi-transparent background to dim the share buttons
      Positioned.fill(
        child: Container(
          color: Colors.white.withOpacity(0.85),
        ),
      ),

      // Bird and speech bubble on bottom-right
      Positioned(
        right: -9,
        bottom: 40,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Speech bubble
            Container(
              width: 220,
              padding: const EdgeInsets.all(14),
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
              child: _saveTutorialTransitionTypewriterComplete
                  ? Text(
                      currentMessage,
                      style: GoogleFonts.fredoka(
                        fontSize: 15,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                    )
                  : _TypewriterText(
                      key: _saveTutorialTransitionTypewriterKey,
                      text: currentMessage,
                      style: GoogleFonts.fredoka(
                        fontSize: 15,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                      speed: const Duration(milliseconds: 30),
                      onComplete: () {
                        setState(() {
                          _saveTutorialTransitionTypewriterComplete = true;
                        });
                      },
                    ),
            ),
            const SizedBox(width: 8),
            // Bird Lottie
            SizedBox(
              width: 100,
              height: 100,
              child: Lottie.asset(
                'assets/mascot/bird_talking_head.json',
                fit: BoxFit.contain,
                options: LottieOptions(enableMergePaths: true),
              ),
            ),
          ],
        ),
      ),

      // Tap detector for transition dialogue advancement
      GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          if (!_saveTutorialTransitionTypewriterComplete) {
            // Skip typewriter to show full text
            _saveTutorialTransitionTypewriterKey.currentState?.skipToEnd();
          } else if (_saveTutorialTransitionIndex < 1) {
            // Advance to next dialogue
            setState(() {
              _saveTutorialTransitionIndex++;
              _saveTutorialTransitionTypewriterComplete = false;
            });
          } else {
            // Dismiss transition, enter save tutorial
            setState(() {
              _showSaveTutorialTransition = false;
              _showSaveTutorialStep = true;
            });
          }
        },
        behavior: HitTestBehavior.translucent,
      ),
    ];
  }

  /// Builds an animated large share button that slides up from the bottom
  Widget _buildAnimatedLargeShareButton(
    IconData icon,
    Animation<double> animation, {
    bool flipX = false,
  }) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, 60 * (1 - animation.value)),
          child: Opacity(
            opacity: animation.value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF3A3A3A),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: flipX
            ? Transform.flip(
                flipX: true,
                child: Icon(icon, color: Colors.white, size: 36),
              )
            : Icon(icon, color: Colors.white, size: 36),
      ),
    );
  }

  /// Wraps content in an iPhone frame mockup
  /// [overlays] are rendered above the bezel (for birds, speech bubbles, etc.)
  Widget _buildPhoneFrameWithContent(
      {required Widget child, List<Widget>? overlays}) {
    // iPhone 15 aspect ratio is approximately 19.5:9 (or about 2.17:1)
    const double phoneAspectRatio =
        874 / 1792; // width / height based on iPhone 15 dimensions

    // Bezel insets as percentages of the frame dimensions
    // These values position the content within the screen area of the phone frame
    const double horizontalBezelPercent = 0.084; // ~5.5% on each side
    const double topBezelPercent = 0.042; // ~2.2% at top
    const double bottomBezelPercent = 0.042; // ~2.2% at bottom
    const double screenCornerRadius = 45.0; // Corner radius for the screen area
    const double dynamicIslandBarPercent =
        0.045; // Height of black bar for Dynamic Island area

    return LayoutBuilder(
      builder: (context, outerConstraints) {
        // Calculate the maximum size that fits while maintaining aspect ratio
        final maxWidth = outerConstraints.maxWidth;
        final maxHeight = outerConstraints.maxHeight;

        // Determine phone dimensions based on available space
        double phoneWidth;
        double phoneHeight;

        if (maxWidth / maxHeight < phoneAspectRatio) {
          // Width is the limiting factor
          phoneWidth = maxWidth;
          phoneHeight = maxWidth / phoneAspectRatio;
        } else {
          // Height is the limiting factor
          phoneHeight = maxHeight;
          phoneWidth = maxHeight * phoneAspectRatio;
        }

        // Calculate the insets for the screen area
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
                        // Black bar at top for Dynamic Island area
                        Container(
                          height: dynamicIslandBarHeight,
                          color: Colors.black,
                        ),
                        // Main content fills remaining space
                        Expanded(child: child),
                      ],
                    ),
                  ),
                ),
                // Phone frame overlay on top
                Positioned.fill(
                  child: IgnorePointer(
                    child: Image.asset(
                      'assets/tutorials/apple-iphone-15-black-portrait.png',
                      fit: BoxFit.fill,
                    ),
                  ),
                ),
                // Overlays rendered above the bezel (birds, speech bubbles, etc.)
                if (overlays != null) ...overlays,
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFakeInstagramReel() {
    final controller = _instagramVideoController;
    final isInitialized = controller?.value.isInitialized ?? false;

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video background
          if (isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller!.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),

          // Instagram UI overlay
          _buildInstagramOverlay(),

          // Transparent tap detector on top
          // Disabled when hand pointer is shown so send button can be tapped
          IgnorePointer(
            ignoring: _showHandPointer,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                if (!_firstBirdTypewriterComplete) {
                  // Skip typewriter animation to show full text
                  _firstBirdTypewriterKey.currentState?.skipToEnd();
                } else if (_speechBubbleMessageIndex < 2) {
                  // Advance to next message
                  setState(() {
                    _speechBubbleMessageIndex++;
                    _firstBirdTypewriterComplete = false;
                  });
                }
              },
              behavior: HitTestBehavior.translucent,
            ),
          ),

          // Instagram share sheet overlay
          if (_showShareSheet) _buildInstagramShareSheet(),

          // Tap detector to skip second bird dialogue typewriter
          if (_showShareSheet && _showSecondBird && !_secondTypewriterComplete)
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _secondBubbleTypewriterKey.currentState?.skipToEnd();
              },
              behavior: HitTestBehavior.translucent,
            ),

          // iOS share sheet overlay
          if (_showIOSShareSheet) _buildIOSShareSheet(),

          // Apps sheet overlay (3rd share sheet)
          if (_showAppsSheet) _buildAppsSheet(),

          // Tap detector to skip apps sheet bird dialogue typewriter
          if (_showAppsSheet &&
              _showAppsSheetBird &&
              !_appsSheetTypewriterComplete)
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _appsSheetTypewriterKey.currentState?.skipToEnd();
              },
              behavior: HitTestBehavior.translucent,
            ),

          // Hand pointing up at the More button - tracks button position using GlobalKey
          if (_showMoreButtonHand)
            AnimatedBuilder(
              animation: _appsRowScrollController,
              builder: (context, child) {
                // Get the More button's position using GlobalKey
                final RenderBox? buttonBox = _moreButtonKey.currentContext
                    ?.findRenderObject() as RenderBox?;
                if (buttonBox == null) return const SizedBox.shrink();

                // Get the button's position in global coordinates
                final buttonPosition = buttonBox.localToGlobal(Offset.zero);
                final buttonSize = buttonBox.size;

                // Calculate the center X of the button
                final buttonCenterX = buttonPosition.dx + buttonSize.width / 2;

                // Get screen dimensions
                final screenWidth = MediaQuery.of(context).size.width;
                final screenHeight = MediaQuery.of(context).size.height;

                // Position hand centered below the button
                const handSize = 48.0;
                // Horizontal: center under button, with offset to account for rotation
                final handRight =
                    screenWidth - buttonCenterX - handSize / 2 - 45;

                // Calculate vertical position: hand should be just below the button
                // buttonPosition.dy + buttonSize.height = bottom edge of button
                final buttonBottomEdge = buttonPosition.dy + buttonSize.height;
                final handBottom =
                    screenHeight - buttonBottomEdge - handSize - 50;

                return Stack(
                  children: [
                    // Hand pointing up
                    Positioned(
                      right: handRight,
                      bottom: handBottom,
                      child: Transform.rotate(
                        angle: -1.5708, // -90 degrees in radians (pointing up)
                        child: SizedBox(
                          width: handSize,
                          height: handSize,
                          child: _rightArrowFileLoader != null
                              ? RiveWidgetBuilder(
                                  fileLoader: _rightArrowFileLoader!,
                                  builder: (context, state) => switch (state) {
                                    RiveLoading() => const SizedBox.shrink(),
                                    RiveFailed() => const SizedBox.shrink(),
                                    RiveLoaded() => RiveWidget(
                                        controller: state.controller,
                                        fit: Fit.contain,
                                      ),
                                  },
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),

          // Tap detector for advancing third bird messages
          // Disabled when hand is showing so More button can be tapped
          if (_showIOSShareSheet && _showThirdBird && !_showMoreButtonHand)
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                if (_thirdBirdMessageIndex == 0) {
                  // First message
                  if (!_thirdBirdFirstMessageComplete) {
                    // Skip to end of first message
                    _thirdBubbleTypewriterKey.currentState?.skipToEnd();
                  } else {
                    // Advance to second message
                    setState(() {
                      _thirdBirdMessageIndex++;
                      _thirdBirdFirstMessageComplete = false;
                    });
                  }
                } else if (_thirdBirdMessageIndex == 1 &&
                    !_thirdBirdSecondMessageComplete) {
                  // Skip to end of second message
                  _thirdBubbleWithIconTypewriterKey.currentState?.skipToEnd();
                }
              },
              behavior: HitTestBehavior.translucent,
            ),

          // Tap detector for post-Plendy dialogues
          if (_showPostPlendyDialogue &&
              !_isAppsSheetEditMode &&
              !(_postPlendyDialogueIndex == 5 && _postPlendyTypewriterComplete))
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                if (!_postPlendyTypewriterComplete) {
                  _postPlendyTypewriterKey.currentState?.skipToEnd();
                } else if (_postPlendyDialogueIndex < 5) {
                  final nextIndex = _postPlendyDialogueIndex + 1;
                  setState(() {
                    _postPlendyDialogueIndex = nextIndex;
                    _postPlendyTypewriterComplete = false;
                  });
                  // Trigger slide animation when moving to dialogue 5
                  if (nextIndex == 5) {
                    _postPlendyBirdSlideController.forward();
                  }
                }
                // Do nothing when last dialogue is dismissed (index 5)
              },
              behavior: HitTestBehavior.translucent,
            ),

          // Tap detector for edit mode dialogues
          // Hidden at interaction-wait indices (1, 3, 5 when complete)
          if (_isAppsSheetEditMode &&
              !((_editModeDialogueIndex == 1 && _editModeTypewriterComplete) ||
                  (_editModeDialogueIndex == 3 &&
                      _editModeTypewriterComplete) ||
                  (_editModeDialogueIndex == 5 && _editModeTypewriterComplete)))
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                if (!_editModeTypewriterComplete) {
                  _editModeTypewriterKey.currentState?.skipToEnd();
                } else if (_editModeDialogueIndex < 5) {
                  setState(() {
                    _editModeDialogueIndex++;
                    _editModeTypewriterComplete = false;
                  });
                }
              },
              behavior: HitTestBehavior.translucent,
            ),
        ],
      ),
    );
  }

  Widget _buildInstagramShareSheet() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(
          begin: 1.0,
          end: _isDismissingInstagramSheet ? 1.0 : 0.0,
        ),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(0, MediaQuery.of(context).size.height * value),
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF262626),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 16),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[600],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Search bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3A3A3A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, color: Colors.grey[400], size: 20),
                          const SizedBox(width: 12),
                          Text(
                            'Search',
                            style: GoogleFonts.inter(
                              color: Colors.grey[400],
                              fontSize: 16,
                            ),
                          ),
                          const Spacer(),
                          Icon(Icons.group_add_outlined,
                              color: Colors.grey[400], size: 22),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Contact grid
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      children: [
                        // First row of contacts
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildShareContact('Sarah Chen'),
                            _buildShareContact('Marcus Johnson',
                                hasStatus: true),
                            _buildShareContact('Emma Williams'),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Second row of contacts
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildShareContact('David Kim'),
                            _buildShareContact('Olivia Martinez'),
                            _buildShareContact('James Taylor'),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Bottom action buttons
                  Container(
                    padding: const EdgeInsets.only(bottom: 32, top: 16),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildShareAction(
                                  Icons.add_circle_outline, 'Add to story'),
                              const SizedBox(width: 24),
                              _buildShareAction(Icons.link, 'Copy link'),
                              const SizedBox(width: 24),
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  GestureDetector(
                                    onTap: _showSecondHandPointer
                                        ? () {
                                            HapticFeedback.lightImpact();
                                            // Start dismiss animation for Instagram sheet
                                            setState(() {
                                              _isDismissingInstagramSheet =
                                                  true;
                                              _showSecondBird = false;
                                              _secondTypewriterComplete = false;
                                              _showSecondHandPointer = false;
                                            });
                                            // After dismiss animation completes, show iOS sheet
                                            Future.delayed(
                                                const Duration(
                                                    milliseconds: 400), () {
                                              if (mounted) {
                                                setState(() {
                                                  _showShareSheet = false;
                                                  _isDismissingInstagramSheet =
                                                      false;
                                                  _showIOSShareSheet = true;
                                                });
                                                // Show third bird after 1 second
                                                Future.delayed(
                                                    const Duration(
                                                        milliseconds: 1000),
                                                    () {
                                                  if (mounted) {
                                                    setState(() {
                                                      _showThirdBird = true;
                                                    });
                                                  }
                                                });
                                              }
                                            });
                                          }
                                        : null,
                                    child: _buildShareAction(
                                        Icons.ios_share, 'Share to...'),
                                  ),
                                  // Hand pointer - positioned to the left of the button, scrolls with it
                                  if (_showSecondHandPointer &&
                                      _rightArrowFileLoader != null)
                                    Positioned(
                                      left: -40,
                                      top: 8,
                                      child: SizedBox(
                                        width: 48,
                                        height: 48,
                                        child: RiveWidgetBuilder(
                                          fileLoader: _rightArrowFileLoader!,
                                          builder: (context, state) =>
                                              switch (state) {
                                            RiveLoading() =>
                                              const SizedBox.shrink(),
                                            RiveFailed() =>
                                              const SizedBox.shrink(),
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
                              const SizedBox(width: 24),
                              _buildShareActionWithImage('WhatsApp\nStatus',
                                  isWhatsApp: true),
                              const SizedBox(width: 24),
                              _buildShareActionWithImage('WhatsApp',
                                  isWhatsApp: true),
                            ],
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
    );
  }

  Widget _buildIOSShareSheet() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(
          begin: 1.0,
          end: _showIOSShareSheet ? 0.0 : 1.0,
        ),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(0, MediaQuery.of(context).size.height * value),
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF2C2C2E),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 12),
                    child: Container(
                      width: 36,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey[600],
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),

                  // Preview card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3A3A3C),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          // Instagram icon placeholder
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.link_off,
                              color: Colors.grey,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Reel from foodie_adventures',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'instagram.com',
                                  style: GoogleFonts.inter(
                                    color: Colors.grey[400],
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // AirDrop row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        _buildIOSShareDevice('MacBook\nAir', Icons.laptop_mac),
                        const SizedBox(width: 16),
                        _buildIOSShareDevice(
                            'Emiri and Sam\n2 People', Icons.people),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Apps row with arrow overlay
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Disable scrolling until right arrow shows up
                      IgnorePointer(
                        ignoring: !_showRightArrow && !_showMoreButtonHand,
                        child: SingleChildScrollView(
                          controller: _appsRowScrollController,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              _buildIOSShareApp('AirDrop', Icons.wifi_tethering,
                                  const Color(0xFF007AFF)),
                              const SizedBox(width: 16),
                              _buildIOSShareApp('Messages', Icons.message,
                                  const Color(0xFF34C759)),
                              const SizedBox(width: 16),
                              _buildIOSShareApp(
                                  'Mail', Icons.mail, const Color(0xFF007AFF)),
                              const SizedBox(width: 16),
                              _buildIOSShareApp(
                                  'Notes', Icons.note, const Color(0xFFFFCC00)),
                              const SizedBox(width: 16),
                              _buildIOSShareApp('Reminders', Icons.checklist,
                                  const Color(0xFF007AFF)),
                              const SizedBox(width: 16),
                              _buildIOSShareApp('Journal', Icons.book,
                                  const Color(0xFFFF9500)),
                              const SizedBox(width: 16),
                              _buildIOSShareApp('Freeform', Icons.dashboard,
                                  const Color(0xFF000000)),
                              const SizedBox(width: 16),
                              _buildIOSShareApp('Gmail', Icons.email,
                                  const Color(0xFFEA4335)),
                              const SizedBox(width: 16),
                              _buildIOSShareApp('Instagram', Icons.camera_alt,
                                  const Color(0xFFE4405F)),
                              const SizedBox(width: 16),
                              _buildIOSShareApp('WhatsApp', Icons.phone,
                                  const Color(0xFF25D366)),
                              const SizedBox(width: 16),
                              GestureDetector(
                                onTap: _showMoreButtonHand
                                    ? () {
                                        HapticFeedback.lightImpact();
                                        setState(() {
                                          _showAppsSheet = true;
                                          // Dismiss 2nd share sheet and its elements
                                          _showIOSShareSheet = false;
                                          _showThirdBird = false;
                                          _showMoreButtonHand = false;
                                          _showRightArrow = false;
                                        });
                                        // Show bird after 1 second
                                        Future.delayed(
                                            const Duration(milliseconds: 1000),
                                            () {
                                          if (mounted) {
                                            setState(() {
                                              _showAppsSheetBird = true;
                                            });
                                          }
                                        });
                                      }
                                    : null,
                                child: Container(
                                  key: _moreButtonKey,
                                  child: _buildIOSShareApp(
                                      'More',
                                      Icons.more_horiz,
                                      const Color(0xFF8E8E93)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Right arrow animation to prompt scrolling
                      if (_showRightArrow)
                        Positioned(
                          right: 16,
                          top: 8,
                          child: _AnimatedArrow(),
                        ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Divider
                  Container(
                    height: 1,
                    color: Colors.grey[700],
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                  ),

                  const SizedBox(height: 8),

                  // Actions list
                  _buildIOSShareAction('Copy', Icons.copy),
                  _buildIOSShareAction(
                      'Add to New\nQuick Note', Icons.note_add),
                  _buildIOSShareAction(
                      'Add to\nReading List', Icons.bookmark_border),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAppsSheet() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.0, end: 0.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, MediaQuery.of(context).size.height * value),
          child: child,
        );
      },
      child: Stack(
        children: [
          Container(
            color: Colors.black,
            child: SafeArea(
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        // Checkmark button
                        Container(
                          width: 30,
                          height: 30,
                          decoration: const BoxDecoration(
                            color: Color(0xFF0A84FF),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const Expanded(
                          child: Text(
                            'Apps',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        // Edit / Done button
                        GestureDetector(
                          onTap: () {
                            if (_isAppsSheetEditMode) {
                              // Only allow Done tap after the "Tap the Done button" dialogue appears
                              if (_editModeDialogueIndex == 5 &&
                                  _editModeTypewriterComplete) {
                                _exitAppsSheetEditMode();
                              }
                            } else if (_postPlendyDialogueIndex == 5 &&
                                _postPlendyTypewriterComplete) {
                              _enterAppsSheetEditMode();
                            }
                          },
                          child: Container(
                            key: _editButtonKey,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: _isAppsSheetEditMode
                                  ? const Color(0xFF0A84FF)
                                  : const Color(0xFF2C2C2E),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _isAppsSheetEditMode ? 'Done' : 'Edit',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Content
                  Expanded(
                    child: _isAppsSheetEditMode
                        ? _buildAppsSheetEditModeContent()
                        : IgnorePointer(
                            ignoring: !_appsSheetTypewriterComplete,
                            child: SingleChildScrollView(
                              controller: _appsSheetScrollController,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Favorites section
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 20, 16, 8),
                                    child: Text(
                                      'Favorites',
                                      style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  _buildAppsGroup([
                                    _buildAppsListItem(
                                        'AirDrop',
                                        Icons.wifi_tethering,
                                        const Color(0xFF007AFF)),
                                    _buildAppsListItem('Messages',
                                        Icons.message, const Color(0xFF34C759)),
                                    _buildAppsListItem('Mail', Icons.mail,
                                        const Color(0xFF007AFF)),
                                  ]),

                                  // Suggestions section
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 24, 16, 8),
                                    child: Text(
                                      'Suggestions',
                                      style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  _buildAppsGroup([
                                    _buildAppsListItem('Notes', Icons.note,
                                        const Color(0xFFFFCC00)),
                                    _buildAppsListItem(
                                        'Reminders',
                                        Icons.checklist,
                                        const Color(0xFF007AFF)),
                                    _buildAppsListItem('Journal', Icons.book,
                                        const Color(0xFFFF9500)),
                                    _buildAppsListItem(
                                        'Freeform',
                                        Icons.dashboard,
                                        const Color(0xFF000000)),
                                    _buildAppsListItem(
                                        'Instagram',
                                        Icons.camera_alt,
                                        const Color(0xFFE4405F)),
                                    _buildAppsListItem('Gmail', Icons.email,
                                        const Color(0xFFEA4335)),
                                    _buildAppsListItem(
                                        'Google Keep',
                                        Icons.lightbulb,
                                        const Color(0xFFFBBC04)),
                                    _buildAppsListItem('WhatsApp', Icons.phone,
                                        const Color(0xFF25D366)),
                                    _buildAppsListItem('Maps', Icons.map,
                                        const Color(0xFF34C759)),
                                    _buildPlendyItemWithHand(),
                                  ]),

                                  const SizedBox(height: 40),
                                ],
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),

          // Down arrow at bottom of sheet
          if ((_showDownArrow && !_isAppsSheetEditMode) ||
              (_showEditModeDownArrow && _isAppsSheetEditMode))
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: _AnimatedDownArrow(),
              ),
            ),
        ],
      ),
    );
  }

  // --- Apps sheet edit mode ---

  void _enterAppsSheetEditMode() {
    HapticFeedback.lightImpact();
    setState(() {
      _isAppsSheetEditMode = true;
      _editModeDialogueIndex = 0;
      _editModeTypewriterComplete = false;
      _showEditModePlendyHand = false;
      _showEditModeDragHand = false;
      _showEditModeDownArrow = false;
      _plendyReachedTop = false;
      _editFavoriteApps = [
        const _OnboardingAppItem(
            label: 'AirDrop',
            icon: Icons.wifi_tethering,
            color: Color(0xFF007AFF)),
        const _OnboardingAppItem(
            label: 'Messages', icon: Icons.message, color: Color(0xFF34C759)),
        const _OnboardingAppItem(
            label: 'Mail', icon: Icons.mail, color: Color(0xFF007AFF)),
      ];
      _editSuggestedApps = [
        const _OnboardingAppItem(
            label: 'Notes', icon: Icons.note, color: Color(0xFFFFCC00)),
        const _OnboardingAppItem(
            label: 'Reminders',
            icon: Icons.checklist,
            color: Color(0xFF007AFF)),
        const _OnboardingAppItem(
            label: 'Journal', icon: Icons.book, color: Color(0xFFFF9500)),
        const _OnboardingAppItem(
            label: 'Freeform', icon: Icons.dashboard, color: Color(0xFF000000)),
        const _OnboardingAppItem(
            label: 'Instagram',
            icon: Icons.camera_alt,
            color: Color(0xFFE4405F)),
        const _OnboardingAppItem(
            label: 'Gmail', icon: Icons.email, color: Color(0xFFEA4335)),
        const _OnboardingAppItem(
            label: 'Google Keep',
            icon: Icons.lightbulb,
            color: Color(0xFFFBBC04)),
        const _OnboardingAppItem(
            label: 'WhatsApp', icon: Icons.phone, color: Color(0xFF25D366)),
        const _OnboardingAppItem(
            label: 'Maps', icon: Icons.map, color: Color(0xFF34C759)),
        const _OnboardingAppItem(label: 'Plendy', isPlendy: true),
      ];
    });
  }

  void _exitAppsSheetEditMode() {
    HapticFeedback.lightImpact();
    setState(() {
      _isAppsSheetEditMode = false;
      _showEditModeDownArrow = false;
      _showRealSharingStep = true;
      _realSharingDialogueIndex = 0;
      _realSharingTypewriterComplete = false;
      _showRealSharingButtons = false;
      _realSharingButtonsController.reset();
    });
  }

  /// Resets all Instagram tutorial state back to the very beginning
  void _resetInstagramTutorial() {
    setState(() {
      _speechBubbleMessageIndex = 0;
      _firstBirdTypewriterComplete = false;
      _showHandPointer = false;
      _showShareSheet = false;
      _showFirstBird = false;
      _showSecondBird = false;
      _secondTypewriterComplete = false;
      _showSecondHandPointer = false;
      _showIOSShareSheet = false;
      _isDismissingInstagramSheet = false;
      _showThirdBird = false;
      _thirdBirdMessageIndex = 0;
      _showRightArrow = false;
      _thirdBirdFirstMessageComplete = false;
      _thirdBirdSecondMessageComplete = false;
      _showMoreButtonHand = false;
      _showAppsSheet = false;
      _showAppsSheetBird = false;
      _appsSheetTypewriterComplete = false;
      _showDownArrow = false;
      _showPlendyHand = false;
      _showSuccessAnimation = false;
      _showPostPlendyDialogue = false;
      _postPlendyDialogueIndex = 0;
      _postPlendyTypewriterComplete = false;
      _isAppsSheetEditMode = false;
      _editFavoriteApps = [];
      _editSuggestedApps = [];
      _editModeDialogueIndex = 0;
      _editModeTypewriterComplete = false;
      _showEditModePlendyHand = false;
      _showEditModeDragHand = false;
      _showEditModeDownArrow = false;
      _plendyReachedTop = false;
      _postPlendyBirdSlideController.reset();
      _editModeBirdSlideController.reset();
      _showRealSharingStep = false;
      _realSharingDialogueIndex = 0;
      _realSharingTypewriterComplete = false;
      _showRealSharingButtons = false;
      _realSharingButtonsController.reset();
      // Reset save tutorial state
      _showSaveTutorialTransition = false;
      _saveTutorialTransitionIndex = 0;
      _saveTutorialTransitionTypewriterComplete = false;
      _showSaveTutorialStep = false;
    });
    // Restart the Instagram video
    _startInstagramVideo();
    // Show first bird after a short delay
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted && _isOnInstagramTutorialStep) {
        setState(() {
          _showFirstBird = true;
        });
      }
    });
  }

  Widget _buildAppsSheetEditModeContent() {
    // Block all interaction during the initial dialogue only;
    // the full-screen tap detector handles blocking during other dialogues
    return IgnorePointer(
      ignoring: _editModeDialogueIndex == 0,
      child: SingleChildScrollView(
        controller: _editModeScrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Favorites section header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                'Favorites',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            _buildEditModeFavoritesGroup(),

            // Suggestions section header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text(
                'Suggestions',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            _buildEditModeSuggestionsGroup(),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildEditModeFavoritesGroup() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.none,
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          padding: EdgeInsets.zero,
          proxyDecorator: (child, index, animation) {
            return Material(
              color: const Color(0xFF2C2C2E),
              elevation: 4,
              shadowColor: Colors.black45,
              child: child,
            );
          },
          itemCount: _editFavoriteApps.length,
          itemBuilder: (context, index) {
            final app = _editFavoriteApps[index];
            final isLast = index == _editFavoriteApps.length - 1;
            return _buildEditModeFavoriteItem(app, index, showDivider: !isLast);
          },
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex--;
              final item = _editFavoriteApps.removeAt(oldIndex);
              _editFavoriteApps.insert(newIndex, item);

              // Check if Plendy is now at the top of the Favorites list
              if (_editFavoriteApps.isNotEmpty &&
                  _editFavoriteApps[0].isPlendy &&
                  !_plendyReachedTop) {
                HapticFeedback.mediumImpact();
                _plendyReachedTop = true;
                _showEditModeDragHand = false;
                _editModeDialogueIndex = 4;
                _editModeTypewriterComplete = false;
              }
            });
          },
        ),
      ),
    );
  }

  Widget _buildEditModeFavoriteItem(_OnboardingAppItem app, int index,
      {bool showDivider = true}) {
    // Only allow dragging when the drag dialogue (index 3) is complete
    final bool canDrag =
        _editModeDialogueIndex == 3 && _editModeTypewriterComplete;
    final bool showDragHand = app.isPlendy && _showEditModeDragHand;

    Widget dragHandle = IgnorePointer(
      ignoring: !canDrag,
      child: Listener(
        onPointerDown: (_) {
          // Hide the drag hand when user starts dragging Plendy
          if (app.isPlendy && _showEditModeDragHand) {
            HapticFeedback.selectionClick();
            setState(() {
              _showEditModeDragHand = false;
            });
          }
        },
        child: ReorderableDragStartListener(
          index: index,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.drag_handle, color: Colors.grey[600], size: 24),
          ),
        ),
      ),
    );

    // Wrap drag handle in a Stack with the hand pointer for Plendy
    if (showDragHand && _rightArrowFileLoader != null) {
      dragHandle = Stack(
        clipBehavior: Clip.none,
        children: [
          dragHandle,
          // Rive hand pointing UP at the drag handle
          Positioned(
            left: -4,
            top: 30,
            child: Transform.rotate(
              angle: -1.5708, // -90 degrees (pointing up)
              child: SizedBox(
                width: 48,
                height: 48,
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
      );
    }

    return Container(
      key: ValueKey('fav_${app.label}'),
      decoration: showDivider
          ? BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: Colors.grey[800]!, width: 0.5)),
            )
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          // Red minus button (disabled during post-add dialogues)
          IgnorePointer(
            ignoring: _editModeDialogueIndex >= 2,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  final removed = _editFavoriteApps.removeAt(index);
                  _editSuggestedApps.insert(0, removed);
                });
              },
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF3B30),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.remove, color: Colors.white, size: 16),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _buildEditModeAppIcon(app),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              app.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
              ),
            ),
          ),
          // Drag handle with optional hand pointer
          dragHandle,
        ],
      ),
    );
  }

  Widget _buildEditModeSuggestionsGroup() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (int i = 0; i < _editSuggestedApps.length; i++) ...[
            _buildEditModeSuggestionItem(_editSuggestedApps[i], i),
            if (i < _editSuggestedApps.length - 1)
              Container(
                height: 0.5,
                color: Colors.grey[800],
                margin: const EdgeInsets.only(left: 60),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildEditModeSuggestionItem(_OnboardingAppItem app, int index) {
    final showHand = app.isPlendy && _showEditModePlendyHand;

    Widget item = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          // Green plus button
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                final removed = _editSuggestedApps.removeAt(index);
                _editFavoriteApps.add(removed);
                if (app.isPlendy) {
                  _showEditModePlendyHand = false;
                  _showEditModeDownArrow = false;
                  // Advance to "added to Favorites" dialogue
                  _editModeDialogueIndex = 2;
                  _editModeTypewriterComplete = false;
                  // Trigger slide animation
                  _editModeBirdSlideController.forward();
                }
              });
            },
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Color(0xFF34C759),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 16),
            ),
          ),
          const SizedBox(width: 12),
          _buildEditModeAppIcon(app),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              app.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
              ),
            ),
          ),
        ],
      ),
    );

    if (showHand && _rightArrowFileLoader != null) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          item,
          // Rive hand pointing at the + button
          Positioned(
            left: 48,
            top: -2,
            child: Transform.flip(
              flipX: true,
              child: SizedBox(
                width: 48,
                height: 48,
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
      );
    }

    return item;
  }

  Widget _buildEditModeAppIcon(_OnboardingAppItem app) {
    if (app.isPlendy) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(
          'assets/icon/icon_white_background.jpg',
          width: 32,
          height: 32,
          fit: BoxFit.cover,
        ),
      );
    }
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: app.color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(app.icon, color: Colors.white, size: 20),
    );
  }

  Widget _buildAppsGroup(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Container(
                height: 0.5,
                color: Colors.grey[800],
                margin: const EdgeInsets.only(
                    left: 60), // Indent separator (16 + 32 + 12)
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildAppsListItem(String label, IconData icon, Color color,
      {bool isHighlighted = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlendyItemWithHand() {
    // Only allow tap when dialogue is complete and post-Plendy dialogues haven't started
    final canTap = _appsSheetTypewriterComplete && !_showPostPlendyDialogue;

    return GestureDetector(
      onTapDown: canTap
          ? (TapDownDetails details) {
              HapticFeedback.lightImpact();
              setState(() {
                _showSuccessAnimation = true;
                _showPlendyHand = false;
                _showDownArrow = false;
              });

              // After success animation plays, show post-Plendy dialogues
              Future.delayed(const Duration(milliseconds: 2000), () {
                if (mounted) {
                  setState(() {
                    _showSuccessAnimation = false;
                    _showPostPlendyDialogue = true;
                  });
                }
              });
            }
          : null,
      child: Container(
        key: _plendyButtonKey,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/icon/icon_white_background.jpg',
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Plendy',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                    ),
                  ),
                ),
              ],
            ),
            // Hand positioned right next to the Plendy text
            if (_showPlendyHand) ...[
              // Hand pointing LEFT (flipped)
              if (_rightArrowFileLoader != null)
                Positioned(
                  left: 105,
                  top: -8,
                  child: Transform.flip(
                    flipX: true,
                    child: SizedBox(
                      width: 48,
                      height: 48,
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
          ],
        ),
      ),
    );
  }

  Widget _buildIOSShareDevice(String label, IconData icon) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: const Color(0xFF3A3A3C),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 11,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildIOSShareApp(String label, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 11,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildIOSShareAction(String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF3A3A3C),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareContact(String name,
      {bool hasEmoji = false, bool hasStatus = false}) {
    return SizedBox(
      width: 85,
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[700],
                  border: Border.all(color: Colors.grey[600]!, width: 1),
                ),
                child: Icon(Icons.person, color: Colors.grey[500], size: 32),
              ),
              if (hasStatus)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '36m',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  name,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasEmoji) const Text(' 👋', style: TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShareAction(IconData icon, String label) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF3A3A3A),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 11,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildShareActionWithImage(String label, {bool isWhatsApp = false}) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF25D366),
          ),
          child: const Icon(
            Icons.phone,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 11,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildInstagramOverlay() {
    return Column(
      children: [
        // Top bar
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                // Profile pic
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    color: Colors.grey[400],
                  ),
                  child:
                      const Icon(Icons.person, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'foodie_adventures',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text('🍕', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                      Text(
                        '1w ago',
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.camera_alt_outlined,
                    color: Colors.white, size: 24),
              ],
            ),
          ),
        ),

        const Spacer(),

        // Bottom section
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Left side - caption and info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.pink,
                              width: 2,
                            ),
                            color: Colors.grey[800],
                          ),
                          child: const Icon(Icons.restaurant,
                              color: Colors.white, size: 14),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'best_restaurants',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You NEED to try this place! 🔥',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Liked by travel_lover and 2,847 others',
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              // Right side - action buttons
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildInstagramActionButton(
                    icon: Icons.favorite,
                    label: '2.8K',
                    color: Colors.red,
                  ),
                  const SizedBox(height: 16),
                  _buildInstagramActionButton(
                    icon: Icons.chat_bubble_outline,
                    label: '124',
                  ),
                  const SizedBox(height: 16),
                  // Send button with pointing hand animation
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      GestureDetector(
                        onTap: _showHandPointer
                            ? () {
                                HapticFeedback.lightImpact();
                                setState(() {
                                  _showShareSheet = true;
                                  _showFirstBird =
                                      false; // Hide the first bird when share sheet appears
                                  _showHandPointer =
                                      false; // Hide the first hand pointer
                                });
                                // Show second bird with speech bubble after share sheet slides up
                                Future.delayed(
                                    const Duration(milliseconds: 1000), () {
                                  if (mounted) {
                                    setState(() {
                                      _showSecondBird = true;
                                    });
                                  }
                                });
                              }
                            : null,
                        child: _buildInstagramActionButton(
                          icon: Icons.send_outlined,
                          label: '',
                          highlighted: true,
                        ),
                      ),
                      // Pointing hand Rive animation - positioned to the left
                      if (_showHandPointer && _rightArrowFileLoader != null)
                        Positioned(
                          right: 50,
                          top: -4,
                          child: SizedBox(
                            width: 48,
                            height: 48,
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
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildInstagramActionButton(
                    icon: Icons.more_horiz,
                    label: '',
                  ),
                ],
              ),
            ],
          ),
        ),

        // Reply bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white30),
                  ),
                  child: Text(
                    'Add a comment...',
                    style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Text('❤️', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              const Text('😂', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              const Text('😮', style: TextStyle(fontSize: 20)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInstagramActionButton({
    required IconData icon,
    required String label,
    Color? color,
    bool highlighted = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: highlighted ? const EdgeInsets.all(8) : EdgeInsets.zero,
          decoration: highlighted
              ? BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                )
              : null,
          child: Icon(
            icon,
            color: color ?? Colors.white,
            size: 28,
          ),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

}

class _TypewriterText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration speed;
  final VoidCallback? onComplete;
  final TextAlign? textAlign;

  const _TypewriterText({
    super.key,
    required this.text,
    this.style,
    this.speed = const Duration(milliseconds: 30),
    this.onComplete,
    this.textAlign,
  });

  @override
  State<_TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<_TypewriterText> {
  String _displayText = '';
  int _currentIndex = 0;
  bool _isComplete = false;

  bool get isComplete => _isComplete;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  @override
  void didUpdateWidget(_TypewriterText oldWidget) {
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
    return Text(
      _displayText,
      style: widget.style,
      textAlign: widget.textAlign,
    );
  }
}

class _TypewriterTextWithIcon extends StatefulWidget {
  final String textBefore;
  final String iconPath;
  final String textAfter;
  final TextStyle? style;
  final Duration speed;
  final VoidCallback? onComplete;

  const _TypewriterTextWithIcon({
    super.key,
    required this.textBefore,
    required this.iconPath,
    required this.textAfter,
    this.style,
    this.speed = const Duration(milliseconds: 30),
    this.onComplete,
  });

  @override
  State<_TypewriterTextWithIcon> createState() =>
      _TypewriterTextWithIconState();
}

class _TypewriterTextWithIconState extends State<_TypewriterTextWithIcon> {
  String _displayTextBefore = '';
  String _displayTextAfter = '';
  int _currentIndex = 0;
  bool _showIcon = false;
  bool _isComplete = false;

  bool get isComplete => _isComplete;
  String get _fullText => widget.textBefore + widget.textAfter;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  @override
  void didUpdateWidget(_TypewriterTextWithIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textBefore != widget.textBefore ||
        oldWidget.textAfter != widget.textAfter) {
      _displayTextBefore = '';
      _displayTextAfter = '';
      _currentIndex = 0;
      _showIcon = false;
      _isComplete = false;
      _startTyping();
    }
  }

  void skipToEnd() {
    if (!_isComplete && mounted) {
      setState(() {
        _displayTextBefore = widget.textBefore;
        _displayTextAfter = widget.textAfter;
        _showIcon = true;
        _currentIndex = _fullText.length;
        _isComplete = true;
      });
      widget.onComplete?.call();
    }
  }

  void _startTyping() {
    final beforeLength = widget.textBefore.length;
    final totalLength = _fullText.length;

    if (_currentIndex < totalLength) {
      Future.delayed(widget.speed, () {
        if (mounted && !_isComplete) {
          setState(() {
            _currentIndex++;
            if (_currentIndex <= beforeLength) {
              _displayTextBefore =
                  widget.textBefore.substring(0, _currentIndex);
            } else {
              _displayTextBefore = widget.textBefore;
              if (!_showIcon) _showIcon = true;
              _displayTextAfter =
                  widget.textAfter.substring(0, _currentIndex - beforeLength);
            }
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
    return Text.rich(
      TextSpan(
        style: widget.style,
        children: [
          TextSpan(text: _displayTextBefore),
          if (_showIcon)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Image.asset(
                  widget.iconPath,
                  width: 18,
                  height: 18,
                ),
              ),
            ),
          TextSpan(text: _displayTextAfter),
        ],
      ),
    );
  }
}

class _AnimatedArrow extends StatefulWidget {
  const _AnimatedArrow();

  @override
  State<_AnimatedArrow> createState() => _AnimatedArrowState();
}

class _AnimatedArrowState extends State<_AnimatedArrow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0, end: 10).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_animation.value, 0),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_forward,
              color: Colors.blue,
              size: 28,
            ),
          ),
        );
      },
    );
  }
}

class _OnboardingAppItem {
  final String label;
  final IconData? icon;
  final Color? color;
  final bool isPlendy;

  const _OnboardingAppItem({
    required this.label,
    this.icon,
    this.color,
    this.isPlendy = false,
  });
}

class _AnimatedDownArrow extends StatefulWidget {
  const _AnimatedDownArrow();

  @override
  State<_AnimatedDownArrow> createState() => _AnimatedDownArrowState();
}

class _AnimatedDownArrowState extends State<_AnimatedDownArrow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0, end: 10).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _animation.value),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_downward,
              color: Colors.blue,
              size: 28,
            ),
          ),
        );
      },
    );
  }
}
