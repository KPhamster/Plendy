import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:video_player/video_player.dart';

import '../models/tutorial_slide.dart';
import '../services/user_service.dart';
import '../widgets/social_browser_dialog.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback? onFinishedFlow;

  const OnboardingScreen({super.key, this.onFinishedFlow});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const int _tutorialStartIndex = 2;
  static const String _defaultSocialUrl = 'https://instagram.com';
  static const List<String> _tutorialHeadings = [
    'Share and save content to Plendy',
    'Find and select the location',
    'Categorize the way you want',
    'Save and check out your experience',
    'Enjoy amazing experiences!',
  ];

  final PageController _pageController = PageController();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _socialUrlInputController =
      TextEditingController();
  final FocusNode _displayNameFocus = FocusNode();
  final FocusNode _usernameFocus = FocusNode();
  final UserService _userService = UserService();

  late final List<VideoPlayerController?> _tutorialControllers;
  late final List<Future<void>?> _tutorialInitializations;

  int _currentPage = 0;
  bool _isSavingProfile = false;
  bool _isCompletingOnboarding = false;
  String? _displayNameError;
  String? _usernameError;

  int get _totalPages => _tutorialStartIndex + tutorialSlides.length;
  bool get _isOnProfileStep => _currentPage == 0;
  bool get _isOnSocialStep => _currentPage == 1;
  bool get _isOnTutorialStep => _currentPage >= _tutorialStartIndex;

  bool get _canSubmitProfile =>
      _displayNameController.text.trim().isNotEmpty &&
      _usernameController.text.trim().isNotEmpty &&
      _usernameError == null &&
      !_isSavingProfile;

  String get _primaryButtonLabel {
    if (_isOnProfileStep) return 'Save & Continue';
    if (_currentPage == _totalPages - 1) return 'Finish';
    return 'Next';
  }

  @override
  void initState() {
    super.initState();
    _tutorialControllers =
        List<VideoPlayerController?>.filled(tutorialSlides.length, null);
    _tutorialInitializations =
        List<Future<void>?>.filled(tutorialSlides.length, null);
    _displayNameController.addListener(_handleProfileFieldChange);
    _usernameController.addListener(_handleProfileFieldChange);
    _socialUrlInputController.text = _defaultSocialUrl;
    _prefillExistingValues();
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
    _socialUrlInputController.dispose();
    _displayNameFocus.dispose();
    _usernameFocus.dispose();
    for (final controller in _tutorialControllers) {
      controller?.dispose();
    }
    super.dispose();
  }

  void _handleProfileFieldChange() {
    if (_isOnProfileStep) {
      final displayNameFilled = _displayNameController.text.trim().isNotEmpty;
      if (_displayNameError != null && displayNameFilled) {
        _displayNameError = null;
      }
      setState(() {});
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    if (_isOnTutorialStep) {
      final slideIndex = index - _tutorialStartIndex;
      _startTutorialVideo(slideIndex);
      _disposeTutorialControllers(exceptIndex: slideIndex);
    } else {
      _disposeTutorialControllers();
    }
  }

  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _handleBackPressed() {
    if (_currentPage == 0) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _handlePrimaryAction() async {
    if (_isCompletingOnboarding) return;
    FocusScope.of(context).unfocus();
    if (_isOnProfileStep) {
      await _submitProfileInfo();
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
      _goToPage(1);
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

  void _startTutorialVideo(int slideIndex) {
    final slide = tutorialSlides[slideIndex];
    if (!slide.hasVideo) return;

    final controller = _tutorialControllers[slideIndex] ??
        _createTutorialController(slideIndex);
    final initialization = _tutorialInitializations[slideIndex];

    if (controller.value.isInitialized) {
      controller
        ..seekTo(Duration.zero)
        ..play();
      return;
    }

    initialization?.then((_) {
      if (!mounted) return;
      final isCurrentSlide = _currentPage == _tutorialStartIndex + slideIndex;
      if (!isCurrentSlide) return;
      controller
        ..seekTo(Duration.zero)
        ..play();
      setState(() {});
    });
  }

  VideoPlayerController _createTutorialController(int slideIndex) {
    final slide = tutorialSlides[slideIndex];
    final controller = VideoPlayerController.asset(slide.videoAsset!);
    _tutorialControllers[slideIndex] = controller;
    _tutorialInitializations[slideIndex] =
        controller.initialize().then((_) => controller.setLooping(true));
    return controller;
  }

  void _disposeTutorialControllers({int? exceptIndex}) {
    for (var i = 0; i < _tutorialControllers.length; i++) {
      if (exceptIndex != null && i == exceptIndex) continue;
      _tutorialControllers[i]?.dispose();
      _tutorialControllers[i] = null;
      _tutorialInitializations[i] = null;
    }
  }

  double _tutorialAspectRatio(int slideIndex) {
    final controller = _tutorialControllers[slideIndex];
    if (controller == null || !controller.value.isInitialized) {
      return 16 / 9;
    }
    final ratio = controller.value.aspectRatio;
    return ratio == 0 ? 16 / 9 : ratio;
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
    final progress = (_currentPage + 1) / _totalPages;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isOnTutorialStep ? 'Tutorial' : 'Get set up',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Step ${_currentPage + 1} of $_totalPages',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: Colors.grey[200],
                      color: theme.primaryColor,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: _onPageChanged,
                children: [
                  _buildProfileStep(theme),
                  _buildSocialStep(theme),
                  for (var i = 0; i < tutorialSlides.length; i++)
                    _buildTutorialStep(theme, i),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                children: [
                  if (_currentPage > 0 && _currentPage != 1)
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
                      onPressed: (_isOnProfileStep && !_canSubmitProfile) ||
                              _isCompletingOnboarding ||
                              (_isOnProfileStep && _isSavingProfile)
                          ? null
                          : _handlePrimaryAction,
                      child: _isOnProfileStep && _isSavingProfile
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : _isCompletingOnboarding &&
                                  _currentPage == _totalPages - 1
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : Text(_primaryButtonLabel),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileStep(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose your Plendy identity',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pick a username and display name so your friends know it\'s you. '
            'Both fields are required before you can continue. \n\n'
            'Your username must be unique but your display name can be anything you want!',
          ),
          const SizedBox(height: 24),
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
          const SizedBox(height: 16),
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
            'Usernames must be 3-20 characters and can include letters, numbers, and underscores.',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialStep(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sign into your socials',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Open a secure browser window to sign into Instagram, TikTok, Facebook, or YouTube. '
            'This helps Plendy load the content you save from those apps. '
            'This step is optional — you can skip it and sign in later from your profile.',
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildSocialQuickLinkButton(
                theme: theme,
                icon: FontAwesomeIcons.instagram,
                label: 'Instagram',
                url: 'https://instagram.com',
              ),
              _buildSocialQuickLinkButton(
                theme: theme,
                icon: FontAwesomeIcons.tiktok,
                label: 'TikTok',
                url: 'https://tiktok.com',
              ),
              _buildSocialQuickLinkButton(
                theme: theme,
                icon: FontAwesomeIcons.facebook,
                label: 'Facebook',
                url: 'https://facebook.com',
              ),
              _buildSocialQuickLinkButton(
                theme: theme,
                icon: FontAwesomeIcons.youtube,
                label: 'YouTube',
                url: 'https://youtube.com',
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _socialUrlInputController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Enter a URL',
              hintText: 'https://instagram.com',
              suffixIcon: IconButton(
                icon: const Icon(Icons.open_in_new),
                onPressed: _handleSocialUrlSubmit,
              ),
            ),
            onSubmitted: (_) => _handleSocialUrlSubmit(),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap a quick link or enter a URL, and a full-screen secure browser will open so you can sign in.',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _goToPage(_currentPage + 1),
              child: const Text('Skip for now'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTutorialStep(ThemeData theme, int slideIndex) {
    final slide = tutorialSlides[slideIndex];
    final controller = _tutorialControllers[slideIndex];
    final heading = slideIndex < _tutorialHeadings.length
        ? _tutorialHeadings[slideIndex]
        : 'Tutorial';

    Widget media;
    if (slide.hasVideo) {
      Widget videoContent;
      if (controller == null || !controller.value.isInitialized) {
        videoContent = const AspectRatio(
          aspectRatio: 16 / 9,
          child: Center(child: CircularProgressIndicator()),
        );
      } else {
        videoContent = AspectRatio(
          aspectRatio: _tutorialAspectRatio(slideIndex),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: VideoPlayer(controller),
          ),
        );
      }

      media = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          videoContent,
          if (controller != null && controller.value.isInitialized) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: VideoProgressIndicator(
                controller!,
                allowScrubbing: true,
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ],
      );
    } else {
      final imageAspectRatio =
          slideIndex == tutorialSlides.length - 1 ? 5 / 6 : 16 / 9;
      media = AspectRatio(
        aspectRatio: imageAspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(
            slide.imageAsset!,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            slide.description,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          media,
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              tutorialSlides.length,
              (index) {
                final isActive = index == (_currentPage - _tutorialStartIndex);
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 8,
                  width: isActive ? 24 : 8,
                  decoration: BoxDecoration(
                    color: isActive ? theme.primaryColor : Colors.grey[300],
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialQuickLinkButton({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required String url,
  }) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      onPressed: () => _handleSocialQuickLinkTap(url),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  void _handleSocialQuickLinkTap(String url) {
    _socialUrlInputController.text = url;
    _openSocialBrowserModal(url);
  }

  void _handleSocialUrlSubmit() {
    _openSocialBrowserModal(_socialUrlInputController.text);
  }

  Future<void> _openSocialBrowserModal(String url) async {
    final normalizedUrl = _normalizeSocialUrl(url);
    if (normalizedUrl == null) return;

    FocusScope.of(context).unfocus();
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => SocialBrowserDialog(initialUrl: normalizedUrl),
    );
  }

  String? _normalizeSocialUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a URL to open the secure browser.'),
        ),
      );
      return null;
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    return 'https://$trimmed';
  }
}
