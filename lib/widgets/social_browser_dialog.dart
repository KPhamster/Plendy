import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

class SocialBrowserDialog extends StatefulWidget {
  final String initialUrl;

  const SocialBrowserDialog({super.key, required this.initialUrl});

  @override
  State<SocialBrowserDialog> createState() => _SocialBrowserDialogState();
}

class _SocialBrowserDialogState extends State<SocialBrowserDialog> {
  late final WebViewController _controller;
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _urlController.text = widget.initialUrl;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final url = request.url;
            final customSchemes = [
              'snssdk',
              'fb',
              'instagram',
              'tiktok',
              'intent'
            ];
            final uri = Uri.tryParse(url);

            if (uri != null &&
                customSchemes.any((scheme) => url.startsWith('$scheme:'))) {
              if (uri.queryParameters.containsKey('params_url')) {
                final originalUrl =
                    Uri.decodeComponent(uri.queryParameters['params_url']!);
                _controller.loadRequest(Uri.parse(originalUrl));
              }
              return NavigationDecision.prevent;
            }

            if (url.startsWith('http://') || url.startsWith('https://')) {
              return NavigationDecision.navigate;
            }

            return NavigationDecision.prevent;
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() => _isLoading = true);
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() {
              _urlController.text = url;
              _isLoading = false;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _loadUrlFromTextField() {
    var url = _urlController.text.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    _urlController.text = url;
    setState(() => _isLoading = true);
    _controller.loadRequest(Uri.parse(url));
    FocusScope.of(context).unfocus();
  }

  void _loadPresetUrl(String url) {
    _urlController.text = url;
    setState(() => _isLoading = true);
    _controller.loadRequest(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          title: const Text('Sign into your socials'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _buildModalQuickLink(
                        icon: FontAwesomeIcons.instagram,
                        label: 'Instagram',
                        url: 'https://instagram.com',
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _buildModalQuickLink(
                        icon: FontAwesomeIcons.tiktok,
                        label: 'TikTok',
                        url: 'https://tiktok.com',
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _buildModalQuickLink(
                        icon: FontAwesomeIcons.facebook,
                        label: 'Facebook',
                        url: 'https://facebook.com',
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _buildModalQuickLink(
                        icon: FontAwesomeIcons.youtube,
                        label: 'YouTube',
                        url: 'https://youtube.com',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  hintText: 'Enter URL',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _loadUrlFromTextField,
                  ),
                ),
                onSubmitted: (_) => _loadUrlFromTextField(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  WebViewWidget(controller: _controller),
                  if (_isLoading)
                    const Center(
                      child: CircularProgressIndicator(),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                bottom: 24,
                top: 12,
                left: 24,
                right: 24,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.check),
                  label: const Text('Done'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModalQuickLink({
    required IconData icon,
    required String label,
    required String url,
  }) {
    return Tooltip(
      message: label,
      child: SizedBox(
        height: 56,
        width: 56,
        child: ElevatedButton(
          onPressed: () => _loadPresetUrl(url),
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.zero,
            shape: const CircleBorder(),
          ),
          child: Icon(icon, size: 22),
        ),
      ),
    );
  }
}
