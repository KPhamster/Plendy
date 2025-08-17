import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebUrlPreviewWidget extends StatefulWidget {
  final String url;
  final Future<void> Function(String) launchUrlCallback;

  const WebUrlPreviewWidget({
    super.key,
    required this.url,
    required this.launchUrlCallback,
  });

  @override
  State<WebUrlPreviewWidget> createState() => _WebUrlPreviewWidgetState();
}

class _WebUrlPreviewWidgetState extends State<WebUrlPreviewWidget> with AutomaticKeepAliveClientMixin {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isInitialized = false;
  bool _isExpanded = false;

  @override
  bool get wantKeepAlive => true;

  void _initializeWebView() {
    if (_isInitialized) return;
    _isInitialized = true;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(true)
      ..setUserAgent('Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Mobile Safari/537.36')
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _hasError = false;
            });
          },
          onPageFinished: (String url) async {
            setState(() {
              _isLoading = false;
            });
            try {
              await _controller.runJavaScript('''
                document.body.style.overflow = 'auto';
                document.documentElement.style.overflow = 'auto';
                document.body.style.touchAction = 'auto';
                document.body.style.webkitOverflowScrolling = 'touch';
                document.body.style.height = 'auto';
                document.body.style.width = '100%';
                document.body.style.position = 'relative';
              ''');
            } catch (_) {}
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              _isLoading = false;
              _hasError = true;
            });
          },
          onNavigationRequest: (NavigationRequest request) {
            final String url = request.url;
            // Keep standard web links inside WebView
            if (url.startsWith('http://') || url.startsWith('https://')) {
              return NavigationDecision.navigate;
            }
            // Handle Android intent:// deep links (e.g., Yelp app redirects)
            if (url.startsWith('intent://')) {
              final String? fallback = _extractBrowserFallbackUrl(url);
              if (fallback != null && (fallback.startsWith('http://') || fallback.startsWith('https://'))) {
                _controller.loadRequest(Uri.parse(fallback));
              }
              return NavigationDecision.prevent;
            }
            // Handle custom Yelp scheme by converting to web URL
            if (url.startsWith('yelp://')) {
              final String path = url.replaceFirst('yelp://', '');
              final String httpsUrl = 'https://www.yelp.com/$path';
              _controller.loadRequest(Uri.parse(httpsUrl));
              return NavigationDecision.prevent;
            }
            // Fallback: try to open externally; if it fails, just block
            widget.launchUrlCallback(url);
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            border: Border.all(color: Colors.blue.shade200),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.public, color: Colors.blue.shade700, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => widget.launchUrlCallback(widget.url),
                  child: Text(
                    widget.url,
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      decoration: TextDecoration.underline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          height: _isExpanded ? 1000 : 600,
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.zero,
            child: Stack(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: _isExpanded ? 1000 : 600,
                  child: WebViewWidget(controller: _controller),
                ),
                if (_isLoading)
                  Container(
                    color: Colors.white.withOpacity(0.8),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            'Loading preview...',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_hasError && !_isLoading)
                  Container(
                    color: Colors.grey.shade100,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 48, color: Colors.grey.shade600),
                          const SizedBox(height: 16),
                          Text(
                            'Unable to load preview',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => widget.launchUrlCallback(widget.url),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Open in Browser'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: _refreshPreview,
                icon: Icon(Icons.refresh, size: 20, color: Colors.blue.shade700),
                tooltip: 'Refresh Preview',
                padding: EdgeInsets.all(8),
                constraints: BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => widget.launchUrlCallback(widget.url),
                icon: Icon(Icons.open_in_new, size: 20, color: Colors.blue.shade700),
                tooltip: 'Open Link',
                padding: EdgeInsets.all(8),
                constraints: BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              const Spacer(),
              IconButton(
                onPressed: _toggleExpand,
                icon: Icon(_isExpanded ? Icons.fullscreen_exit : Icons.fullscreen, size: 20, color: Colors.blue.shade700),
                tooltip: _isExpanded ? 'Collapse Preview' : 'Expand Preview',
                padding: EdgeInsets.all(8),
                constraints: BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _refreshPreview() {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    _controller.loadRequest(Uri.parse(widget.url));
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  String? _extractBrowserFallbackUrl(String intentUrl) {
    try {
      final RegExp rx = RegExp(r'S\\.browser_fallback_url=([^;]+)');
      final Match? m = rx.firstMatch(intentUrl);
      if (m != null && m.groupCount >= 1) {
        final String encoded = m.group(1)!;
        return Uri.decodeComponent(encoded);
      }
      // Also try without escaped backslash variant
      final RegExp rx2 = RegExp(r'S\.browser_fallback_url=([^;]+)');
      final Match? m2 = rx2.firstMatch(intentUrl);
      if (m2 != null && m2.groupCount >= 1) {
        final String encoded = m2.group(1)!;
        return Uri.decodeComponent(encoded);
      }
    } catch (_) {}
    return null;
  }
}


