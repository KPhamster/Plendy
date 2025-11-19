import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

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
  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _urlController.text = widget.initialUrl.isNotEmpty
        ? widget.initialUrl
        : 'https://instagram.com';
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _handleQuickLinkTap(String url) {
    _urlController.text = url;
    _openBrowserModal(url);
  }

  void _handleUrlSubmit() {
    _openBrowserModal(_urlController.text);
  }

  Future<void> _openBrowserModal(String url) async {
    final normalizedUrl = _normalizeUrl(url);
    if (normalizedUrl == null) return;

    FocusScope.of(context).unfocus();
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => SocialBrowserDialog(initialUrl: normalizedUrl),
    );
  }

  String? _normalizeUrl(String rawUrl) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          title: const Text('Browser Sign In'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
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
                'Use the secure browser to sign into Instagram, TikTok, Facebook, or YouTube. '
                'Tap a quick link below or enter any URL to launch the browser when you are ready.',
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildQuickLinkButton(
                    icon: FontAwesomeIcons.instagram,
                    label: 'Instagram',
                    url: 'https://instagram.com',
                  ),
                  _buildQuickLinkButton(
                    icon: FontAwesomeIcons.tiktok,
                    label: 'TikTok',
                    url: 'https://tiktok.com',
                  ),
                  _buildQuickLinkButton(
                    icon: FontAwesomeIcons.facebook,
                    label: 'Facebook',
                    url: 'https://facebook.com',
                  ),
                  _buildQuickLinkButton(
                    icon: FontAwesomeIcons.youtube,
                    label: 'YouTube',
                    url: 'https://youtube.com',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Enter a URL',
                  hintText: 'https://instagram.com',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.open_in_new),
                    onPressed: _handleUrlSubmit,
                  ),
                ),
                onSubmitted: (_) => _handleUrlSubmit(),
              ),
              const SizedBox(height: 8),
              Text(
                'A full-screen secure browser opens so you can sign in. Close it when you are done to return here.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _handleUrlSubmit,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open secure browser'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
