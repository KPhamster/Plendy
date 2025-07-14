import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class GoogleKnowledgeGraphPreviewWidget extends StatefulWidget {
  final String url;
  final Future<void> Function(String) launchUrlCallback;

  const GoogleKnowledgeGraphPreviewWidget({
    super.key,
    required this.url,
    required this.launchUrlCallback,
  });

  @override
  State<GoogleKnowledgeGraphPreviewWidget> createState() => _GoogleKnowledgeGraphPreviewWidgetState();
}

class _GoogleKnowledgeGraphPreviewWidgetState extends State<GoogleKnowledgeGraphPreviewWidget> with AutomaticKeepAliveClientMixin {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isInitialized = false;
  bool _isExpanded = false;

  @override
  bool get wantKeepAlive => true; // Keep the widget alive to prevent rebuilds

  void _initializeWebView() {
    if (_isInitialized) return;
    _isInitialized = true;
    
    print("🌐 GOOGLE KG WEBVIEW: Initializing WebView for URL: ${widget.url}");
    
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(true)
      ..setUserAgent('Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Mobile Safari/537.36')
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            print("🌐 GOOGLE KG WEBVIEW: Page started loading: $url");
            setState(() {
              _isLoading = true;
              _hasError = false;
            });
          },
          onPageFinished: (String url) async {
            print("🌐 GOOGLE KG WEBVIEW: Page finished loading: $url");
            setState(() {
              _isLoading = false;
            });
            
            // Enable basic scrolling with JavaScript
            try {
              await _controller.runJavaScript('''
                // Enable scrolling
                document.body.style.overflow = 'auto';
                document.documentElement.style.overflow = 'auto';
                document.body.style.touchAction = 'auto';
                document.body.style.webkitOverflowScrolling = 'touch';
                
                // Remove any scrolling restrictions
                document.body.style.height = 'auto';
                document.body.style.width = '100%';
                document.body.style.position = 'relative';
                
                console.log('WebView basic scrolling enabled');
              ''');
            } catch (e) {
              print("🌐 GOOGLE KG WEBVIEW: Error running JavaScript: $e");
            }
          },
          onWebResourceError: (WebResourceError error) {
            print("🌐 GOOGLE KG WEBVIEW: Error loading page: ${error.description}");
            setState(() {
              _isLoading = false;
              _hasError = true;
            });
          },
          onNavigationRequest: (NavigationRequest request) {
            // Allow all Google-related navigation
            if (request.url.contains('google.com') || 
                request.url.contains('share.google') ||
                request.url.contains('g.co')) {
              return NavigationDecision.navigate;
            }
            
            // For external links, open in external browser
            if (request.url.startsWith('http://') || request.url.startsWith('https://')) {
              widget.launchUrlCallback(request.url);
              return NavigationDecision.prevent;
            }
            
            return NavigationDecision.navigate;
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
    print("🌐 GOOGLE KG WEBVIEW: Building widget for URL: ${widget.url}");
    
    return Column(
      children: [
        // Header with URL
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
        
        // WebView container with simplified gesture handling
        Container(
          height: _isExpanded ? 1000 : 600, // Dynamic height based on expanded state
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.zero,
            child: Stack(
              children: [
                // Simple WebView without complex gesture isolation
                SizedBox(
                  width: double.infinity,
                  height: _isExpanded ? 1000 : 600,
                  child: WebViewWidget(controller: _controller),
                ),
                
                // Loading indicator
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
                            'Loading Google Knowledge Graph...',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                
                // Error state
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
        
        // Bottom bar with refresh, open link, and expand buttons
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
              // Refresh button (far left)
              IconButton(
                onPressed: () => _refreshPreview(),
                icon: Icon(Icons.refresh, size: 20, color: Colors.blue.shade700),
                tooltip: 'Refresh Preview',
                padding: EdgeInsets.all(8),
                constraints: BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              
              const Spacer(),
              
              // Open link button (center)
              IconButton(
                onPressed: () => widget.launchUrlCallback(widget.url),
                icon: Icon(Icons.open_in_new, size: 20, color: Colors.blue.shade700),
                tooltip: 'Open Link',
                padding: EdgeInsets.all(8),
                constraints: BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              
              const Spacer(),
              
              // Expand/Collapse button (far right)
              IconButton(
                onPressed: () => _toggleExpand(),
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
    print("🌐 GOOGLE KG WEBVIEW: Refreshing preview to original URL: ${widget.url}");
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    // Load the original shared URL, not just refresh current page
    _controller.loadRequest(Uri.parse(widget.url));
  }
  
  void _toggleExpand() {
    print("🌐 GOOGLE KG WEBVIEW: Toggling expand state from $_isExpanded");
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }
}