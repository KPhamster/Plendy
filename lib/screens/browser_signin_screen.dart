import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../config/colors.dart';
import '../widgets/social_browser_dialog.dart';

class BrowserSignInScreen extends StatefulWidget {
  final String initialUrl;

  const BrowserSignInScreen({
    super.key,
    this.initialUrl = 'https://instagram.com',
  });

  @override
  State<BrowserSignInScreen> createState() => _BrowserSignInScreenState();
}

class _BrowserSignInScreenState extends State<BrowserSignInScreen> {
  static const String _previewImageAsset =
      'assets/tutorials/restaurant_image.jpeg';
  static const String _previewProfilePhotoAsset =
      'assets/tutorials/profile_photo_example.jpeg';
  static const String _previewRestaurantName = 'Patty Planet Burger Co.';
  static const String _previewUsername = 'grillmasterjay';
  static const Duration _popupReappearDelay = Duration(seconds: 10);

  bool _isBeforePopupVisible = true;
  Timer? _beforePopupTimer;

  @override
  void dispose() {
    _beforePopupTimer?.cancel();
    super.dispose();
  }

  void _handleQuickLinkTap(String url) {
    _openBrowserModal(url);
  }

  Future<void> _openBrowserModal(String url) async {
    final normalizedUrl =
        url.startsWith('http://') || url.startsWith('https://')
            ? url
            : 'https://$url';

    FocusScope.of(context).unfocus();
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => SocialBrowserDialog(initialUrl: normalizedUrl),
    );
  }

  Widget _buildQuickLinkButton({
    required IconData icon,
    required String label,
    required String url,
  }) {
    final theme = Theme.of(context);
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      onPressed: () => _handleQuickLinkTap(url),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Widget _buildPreviewExample({
    required String title,
    required bool showSignInPopup,
    String? subtitle,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1F1A1E),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF5A5458),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        const SizedBox(height: 12),
        GestureDetector(
          onTap: showSignInPopup ? _dismissBeforePopupTemporarily : null,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFDADADA)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                aspectRatio: 0.53,
                child: Container(
                  color: const Color(0xFFF5F4F4),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: Column(
                    children: [
                      Container(
                        width: 58,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBC9C9),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _previewRestaurantName,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF211B20),
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.close,
                            size: 30,
                            color: Color(0xFF56484C),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Image.asset(
                                  _previewImageAsset,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      stops: const [0, 0.3, 1],
                                      colors: [
                                        Colors.black.withValues(alpha: 0.4),
                                        Colors.transparent,
                                        Colors.black.withValues(alpha: 0.24),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  height: 52,
                                  color: const Color(0xFF090F1B).withValues(
                                    alpha: 0.96,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14),
                                  child: Row(
                                    children: [
                                      Text(
                                        'Instagram',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          color: Colors.white.withValues(
                                            alpha: 0.88,
                                          ),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const Spacer(),
                                      if (showSignInPopup) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF3E57D8),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: const Text(
                                            'Log In',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          'Sign Up',
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                            color: const Color(0xFF8DA2FF),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              if (showSignInPopup)
                                Center(
                                  child: FractionallySizedBox(
                                    widthFactor: 0.88,
                                    child: IgnorePointer(
                                      ignoring: !_isBeforePopupVisible,
                                      child: AnimatedOpacity(
                                        opacity: _isBeforePopupVisible ? 1 : 0,
                                        duration:
                                            const Duration(milliseconds: 280),
                                        curve: Curves.easeInOut,
                                        child: GestureDetector(
                                          onTap: () {},
                                          child: _buildSignInPopup(theme),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildBottomToolbar(theme),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _dismissBeforePopupTemporarily() {
    if (!_isBeforePopupVisible) return;
    setState(() => _isBeforePopupVisible = false);
    _beforePopupTimer?.cancel();
    _beforePopupTimer = Timer(_popupReappearDelay, () {
      if (!mounted) return;
      setState(() => _isBeforePopupVisible = true);
    });
  }

  Widget _buildSignInPopup(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2230).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: ClipOval(
              child: Image.asset(
                _previewProfilePhotoAsset,
                fit: BoxFit.cover,
                width: 74,
                height: 74,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Continue as\n$_previewUsername',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              height: 1.12,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'You logged into Instagram before as $_previewUsername.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A5CF1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {},
              child: Text('Continue as $_previewUsername'),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Sign up',
              style: theme.textTheme.titleMedium?.copyWith(
                color: const Color(0xFF8DA2FF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomToolbar(ThemeData theme) {
    const double toolbarIconSlot = 28;
    const double rightPadding = 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final centerX = width / 2;
        final step = ((width / 2) - (toolbarIconSlot / 2) - rightPadding) / 3;

        Widget actionIcon({
          required double center,
          required Widget icon,
        }) {
          return Positioned(
            left: center - (toolbarIconSlot / 2),
            width: toolbarIconSlot,
            top: 0,
            bottom: 0,
            child: Center(child: icon),
          );
        }

        return SizedBox(
          height: 38,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.teal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.teal.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.language,
                        size: 16,
                        color: AppColors.teal,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Web view',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: AppColors.teal,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actionIcon(
                center: centerX,
                icon: const Icon(
                  FontAwesomeIcons.instagram,
                  size: 24,
                  color: Color(0xFFE13A73),
                ),
              ),
              actionIcon(
                center: centerX + step,
                icon: const Icon(
                  Icons.share_outlined,
                  size: 25,
                  color: Color(0xFF2C8FE6),
                ),
              ),
              actionIcon(
                center: centerX + (step * 2),
                icon: const Icon(
                  Icons.fullscreen,
                  size: 25,
                  color: Color(0xFF2C8FE6),
                ),
              ),
              actionIcon(
                center: centerX + (step * 3),
                icon: const Icon(
                  Icons.arrow_forward,
                  size: 26,
                  color: Color(0xFFC94B57),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(true);
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          title: const Text('Sign into Instagram'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This is optional. It is mainly for Instagram preview web views, which will keep asking you to sign in until you do. See the examples below.'
              ),
              const SizedBox(height: 24),
              Center(
                child: _buildQuickLinkButton(
                  icon: FontAwesomeIcons.instagram,
                  label: 'Sign into Instagram',
                  url: 'https://instagram.com',
                ),
              ),
              const SizedBox(height: 28),
              _buildPreviewExample(
                title: 'Before signing into Instagram',
                showSignInPopup: true,
                subtitle: 'You can tap outside the signin popup to dismiss it.',
              ),
              const SizedBox(height: 24),
              _buildPreviewExample(
                title: 'After signing into Instagram',
                showSignInPopup: false,
              ),
              const SizedBox(height: 28),
              Center(
                child: _buildQuickLinkButton(
                  icon: FontAwesomeIcons.instagram,
                  label: 'Sign into Instagram',
                  url: 'https://instagram.com',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
