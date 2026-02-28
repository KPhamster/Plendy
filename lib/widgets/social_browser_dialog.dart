import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class SocialBrowserDialog extends StatefulWidget {
  final String initialUrl;

  const SocialBrowserDialog({super.key, required this.initialUrl});

  @override
  State<SocialBrowserDialog> createState() => _SocialBrowserDialogState();
}

class _SocialBrowserDialogState extends State<SocialBrowserDialog> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
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
            setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
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
          title: const Text('Sign into Instagram'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Column(
          children: [
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
}
