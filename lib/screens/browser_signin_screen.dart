import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

class BrowserSignInScreen extends StatefulWidget {
  const BrowserSignInScreen({super.key});

  @override
  State<BrowserSignInScreen> createState() => _BrowserSignInScreenState();
}

class _BrowserSignInScreenState extends State<BrowserSignInScreen> {
  late final WebViewController _controller;
  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    const initialUrl = 'https://instagram.com';
    _urlController.text = initialUrl;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            // Handle custom URL schemes (like TikTok's snssdk://)
            final url = request.url;
            
            // List of custom schemes to block
            final customSchemes = ['snssdk', 'fb', 'instagram', 'tiktok', 'intent'];
            final uri = Uri.tryParse(url);
            
            if (uri != null && customSchemes.any((scheme) => url.startsWith('$scheme:'))) {
              // Extract the original URL from params if available
              if (uri.queryParameters.containsKey('params_url')) {
                final originalUrl = Uri.decodeComponent(uri.queryParameters['params_url']!);
                _controller.loadRequest(Uri.parse(originalUrl));
              }
              // Block the custom scheme navigation
              return NavigationDecision.prevent;
            }
            
            // Allow regular http/https URLs
            if (url.startsWith('http://') || url.startsWith('https://')) {
              return NavigationDecision.navigate;
            }
            
            // Block any other non-standard URLs
            return NavigationDecision.prevent;
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _urlController.text = url;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(initialUrl));
  }

  void _loadUrlFromTextField() {
    var url = _urlController.text;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    _controller.loadRequest(Uri.parse(url));
    FocusScope.of(context).unfocus(); // Hide keyboard
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: const Text('Browser Sign In'),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Plendy uses a web browser view to display content from Instagram, TikTok, and other sites. For the best experience, use the browser window below to sign into any accounts you wish to save to Plendy from. This ensures all content you save displays correctly. Plendy does not save any data from the web browser.',
              textAlign: TextAlign.center,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    const url = 'https://instagram.com';
                    _urlController.text = url;
                    _controller.loadRequest(Uri.parse(url));
                  },
                  icon: const Icon(FontAwesomeIcons.instagram),
                  label: const Text('Instagram'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    const url = 'https://tiktok.com';
                    _urlController.text = url;
                    _controller.loadRequest(Uri.parse(url));
                  },
                  icon: const Icon(FontAwesomeIcons.tiktok),
                  label: const Text('TikTok'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
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
            child: WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
} 