import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Builds a web-friendly preview card for social media URLs
/// Used on web to avoid CORS issues with embedded content
/// Matches the style from DiscoverySharePreviewScreen
class WebMediaPreviewCard extends StatelessWidget {
  final String url;
  final String? experienceName;
  final VoidCallback? onOpenPressed;

  const WebMediaPreviewCard({
    super.key,
    required this.url,
    this.experienceName,
    this.onOpenPressed,
  });

  Future<void> _openInPlendy() async {
    // Use the regular Plendy URL - on mobile it will trigger app links/universal links
    const appUrl = 'https://plendy.app';
    final uri = Uri.parse(appUrl);
    
    try {
      // Use webOnlyWindowName: '_self' to replace current page (triggers app links on mobile)
      await launchUrl(
        uri, 
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      );
      debugPrint('Launched Plendy URL');
    } catch (e) {
      debugPrint('Failed to launch Plendy URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine media type
    final isTikTokUrl = url.toLowerCase().contains('tiktok.com') ||
        url.toLowerCase().contains('vm.tiktok.com');
    final isInstagramUrl = url.toLowerCase().contains('instagram.com');
    final isFacebookUrl = url.toLowerCase().contains('facebook.com') ||
        url.toLowerCase().contains('fb.com') ||
        url.toLowerCase().contains('fb.watch');
    final isYouTubeUrl = url.toLowerCase().contains('youtube.com') ||
        url.toLowerCase().contains('youtu.be') ||
        url.toLowerCase().contains('youtube.com/shorts');

    String platformName = '';
    IconData platformIcon = Icons.link;
    Color platformColor = Colors.grey;

    if (isInstagramUrl) {
      platformName = 'Instagram';
      platformIcon = FontAwesomeIcons.instagram;
      platformColor = const Color(0xFFE4405F);
    } else if (isTikTokUrl) {
      platformName = 'TikTok';
      platformIcon = FontAwesomeIcons.tiktok;
      platformColor = Colors.black;
    } else if (isFacebookUrl) {
      platformName = 'Facebook';
      platformIcon = FontAwesomeIcons.facebookF;
      platformColor = const Color(0xFF1877F2);
    } else if (isYouTubeUrl) {
      platformName = 'YouTube';
      platformIcon = FontAwesomeIcons.youtube;
      platformColor = const Color(0xFFFF0000);
    }

    // Return empty if not a recognized platform
    if (platformName.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            platformColor.withOpacity(0.3),
            Colors.black,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FaIcon(
              platformIcon,
              size: 80,
              color: Colors.white.withOpacity(0.9),
            ),
            const SizedBox(height: 24),
            if (experienceName != null && experienceName!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Text(
                  experienceName!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Noto Serif',
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 24),
            // "Open in Plendy" button
            ElevatedButton.icon(
              onPressed: _openInPlendy,
              icon: SizedBox(
                width: 24,
                height: 24,
                child: Image.asset(
                  'assets/icon/icon-cropped.png',
                  fit: BoxFit.contain,
                ),
              ),
              label: const Text('Open in Plendy'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFFD40000), // Plendy red text
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // "Open on [Platform]" button
            ElevatedButton.icon(
              onPressed: onOpenPressed,
              icon: const Icon(Icons.open_in_new),
              label: Text('Open on $platformName'),
              style: ElevatedButton.styleFrom(
                backgroundColor: platformColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
