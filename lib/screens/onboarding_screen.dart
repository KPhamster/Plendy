import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:video_player/video_player.dart';

import '../models/tutorial_slide.dart';
import '../services/user_service.dart';
import 'browser_signin_screen.dart';
import 'main_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const int _tutorialStartIndex = 2;

  final PageController _pageController = PageController();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final FocusNode _displayNameFocus = FocusNode();
  final FocusNode _usernameFocus = FocusNode();
  final UserService _userService = UserService();

  late final List<VideoPlayerController?> _tutorialControllers;
  late final List<Future<void>?> _tutorialInitializations;

  int _currentPage = 0;
  bool _isSavingProfile = false;
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
    FocusScope.of(context).unfocus();
    if (_isOnProfileStep) {
      await _submitProfileInfo();
      return;
    }

    if (_currentPage == _totalPages - 1) {
      _finishOnboarding();
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

      final isAvailable = await _userService.isUsernameAvailable(username);
      if (!isAvailable) {
        setState(() => _usernameError = 'Username is already taken');
        return;
      }

      final success = await _userService.setUsername(user.uid, username);
      if (!success) {
        setState(() => _usernameError = 'Could not save username. Try again.');
        return;
      }

      await user.updateDisplayName(displayName);
      await _userService.updateUserCoreData(user.uid, {
        'displayName': displayName,
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

  void _finishOnboarding() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainScreen()),
      (route) => false,
    );
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
                    'Get set up',
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
                  if (_currentPage > 0)
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
                      onPressed: _isOnProfileStep && !_canSubmitProfile
                          ? null
                          : (_isSavingProfile ? null : _handlePrimaryAction),
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
            'For the best experience, sign into Instagram, TikTok, Facebook, or YouTube using the secure in-app browser. '
            'This helps Plendy load the content you save from those apps. This step is optional — '
            'you can skip it and sign in later from your profile.',
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildSocialButton(
                theme: theme,
                icon: FontAwesomeIcons.instagram,
                label: 'Instagram',
                url: 'https://instagram.com',
              ),
              _buildSocialButton(
                theme: theme,
                icon: FontAwesomeIcons.tiktok,
                label: 'TikTok',
                url: 'https://tiktok.com',
              ),
              _buildSocialButton(
                theme: theme,
                icon: FontAwesomeIcons.facebook,
                label: 'Facebook',
                url: 'https://facebook.com',
              ),
              _buildSocialButton(
                theme: theme,
                icon: FontAwesomeIcons.youtube,
                label: 'YouTube',
                url: 'https://youtube.com',
              ),
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => _openBrowserScreen(),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open social browser'),
          ),
          const SizedBox(height: 8),
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

    Widget media;
    if (slide.hasVideo) {
      if (controller == null) {
        media = const AspectRatio(
          aspectRatio: 16 / 9,
          child: Center(child: CircularProgressIndicator()),
        );
      } else if (!controller.value.isInitialized) {
        media = const AspectRatio(
          aspectRatio: 16 / 9,
          child: Center(child: CircularProgressIndicator()),
        );
      } else {
        media = AspectRatio(
          aspectRatio: _tutorialAspectRatio(slideIndex),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: VideoPlayer(controller),
          ),
        );
      }
    } else {
      media = AspectRatio(
        aspectRatio: 16 / 9,
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
            'Saving content to Plendy',
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

  Widget _buildSocialButton({
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
      onPressed: () => _openBrowserScreen(initialUrl: url),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Future<void> _openBrowserScreen({String? initialUrl}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BrowserSignInScreen(
          initialUrl: initialUrl ?? 'https://instagram.com',
        ),
      ),
    );
  }
}
