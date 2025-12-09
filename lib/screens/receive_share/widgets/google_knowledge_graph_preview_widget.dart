import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:typed_data';

class GoogleKnowledgeGraphPreviewWidget extends StatefulWidget {
  final String url;
  final Future<void> Function(String) launchUrlCallback;

  const GoogleKnowledgeGraphPreviewWidget({
    super.key,
    required this.url,
    required this.launchUrlCallback,
  });

  @override
  GoogleKnowledgeGraphPreviewWidgetState createState() => GoogleKnowledgeGraphPreviewWidgetState();
}

class GoogleKnowledgeGraphPreviewWidgetState extends State<GoogleKnowledgeGraphPreviewWidget> with AutomaticKeepAliveClientMixin {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isExpanded = false;
  bool _isDisposed = false;

  @override
  bool get wantKeepAlive => true; // Keep the widget alive to prevent rebuilds

  @override
  void initState() {
    super.initState();
    print("🌐 GOOGLE KG WEBVIEW: Initializing WebView for URL: ${widget.url}");
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  /// Take a screenshot of the current WebView content
  /// Uses PNG format for best quality OCR/text detection
  Future<Uint8List?> takeScreenshot() async {
    if (_controller == null) {
      print('⚠️ GOOGLE KG PREVIEW: Controller is null, cannot take screenshot');
      return null;
    }
    
    try {
      // Use PNG format (lossless) for best text/OCR quality
      final screenshot = await _controller!.takeScreenshot(
        screenshotConfiguration: ScreenshotConfiguration(
          compressFormat: CompressFormat.PNG,
          quality: 100,
        ),
      );
      if (screenshot != null) {
        print('✅ GOOGLE KG PREVIEW: Screenshot captured (${screenshot.length} bytes, PNG format)');
      }
      return screenshot;
    } catch (e) {
      print('❌ GOOGLE KG PREVIEW: Screenshot failed: $e');
      return null;
    }
  }

  /// Extract all text content from the current page
  /// This is useful for scraping articles with lists of locations
  Future<String?> extractPageContent() async {
    if (_controller == null) {
      print('⚠️ GOOGLE KG PREVIEW: Controller is null, cannot extract content');
      return null;
    }
    
    try {
      // JavaScript to extract meaningful text content from the page
      // Enhanced filtering to remove author bios, sidebars, related posts, etc.
      final result = await _controller!.evaluateJavascript(source: '''
        (function() {
          // Comprehensive list of selectors to remove (non-article content)
          const selectorsToRemove = [
            // Basic elements
            'script', 'style', 'noscript', 'iframe', 'svg', 'canvas', 'video', 'audio',
            
            // Navigation and structure
            'nav', 'footer', 'header', 'aside',
            '[role="navigation"]', '[role="banner"]', '[role="contentinfo"]', '[role="complementary"]',
            
            // Common class names for navigation/footer
            '.nav', '.navbar', '.navigation', '.menu', '.footer', '.header', '.masthead',
            
            // Sidebar content
            '.sidebar', '.side-bar', '.widget', '.widgets', '#sidebar', '#side-bar',
            '[class*="sidebar"]', '[id*="sidebar"]',
            
            // Author/About sections (often contain unrelated locations)
            '.author', '.author-bio', '.author-box', '.author-info', '.about-author',
            '.bio', '.writer-bio', '.contributor',
            '[class*="author"]', '[class*="bio"]',
            
            // Related/Popular posts
            '.related', '.related-posts', '.related-articles', '.similar-posts',
            '.popular', '.popular-posts', '.trending', '.recommended',
            '.recent-posts', '.latest-posts', '.more-posts',
            '[class*="related"]', '[class*="popular"]', '[class*="recent-posts"]',
            
            // Comments
            '.comments', '.comment-section', '.disqus', '#comments', '#respond',
            '[class*="comment"]',
            
            // Ads and promotions
            '.advertisement', '.ad', '.ads', '.advert', '.sponsored', '.promo',
            '[class*="advert"]', '[class*="sponsor"]',
            
            // Social sharing
            '.social', '.social-share', '.share-buttons', '.sharing',
            '[class*="social"]', '[class*="share"]',
            
            // Newsletter/Subscribe
            '.newsletter', '.subscribe', '.signup', '.opt-in', '.email-signup',
            '[class*="newsletter"]', '[class*="subscribe"]',
            
            // WordPress specific
            '.wp-sidebar', '.widget-area', '.tagcloud', '.wp-block-latest-posts',
            
            // Footer widgets and misc
            '.site-footer', '.footer-widgets', '.post-navigation', '.breadcrumb',
            '.pagination', '.page-links'
          ];
          
          // Get the main content area - prioritize article content
          let mainContent = document.querySelector('article.post, article.entry, article.blog-post, .post-content, .article-content, .entry-content, .blog-content');
          
          // Fallback to broader selectors
          if (!mainContent) {
            mainContent = document.querySelector('article, main, [role="main"], .content, #content, #main');
          }
          
          let textContent = '';
          
          if (mainContent) {
            // Clone to avoid modifying the actual DOM
            const clone = mainContent.cloneNode(true);
            
            // Remove all unwanted elements from clone
            selectorsToRemove.forEach(selector => {
              try {
                clone.querySelectorAll(selector).forEach(el => el.remove());
              } catch (e) {
                // Some selectors might fail, ignore
              }
            });
            
            textContent = clone.innerText || clone.textContent;
          } else {
            // Fallback: get body text but aggressively clean it
            const bodyClone = document.body.cloneNode(true);
            selectorsToRemove.forEach(selector => {
              try {
                bodyClone.querySelectorAll(selector).forEach(el => el.remove());
              } catch (e) {
                // Ignore selector errors
              }
            });
            textContent = bodyClone.innerText || bodyClone.textContent;
          }
          
          // Get the page title (important for context)
          const title = document.title || '';
          
          // Get meta description if available
          const metaDesc = document.querySelector('meta[name="description"]');
          const description = metaDesc ? metaDesc.getAttribute('content') : '';
          
          // Try to get the main heading (h1) for better context
          const h1 = document.querySelector('h1');
          const mainHeading = h1 ? h1.innerText.trim() : '';
          
          // Combine title, heading, description, and content
          let fullContent = '';
          if (title) fullContent += 'Page Title: ' + title + '\\n';
          if (mainHeading && mainHeading !== title) fullContent += 'Main Heading: ' + mainHeading + '\\n';
          if (description) fullContent += 'Description: ' + description + '\\n';
          fullContent += '\\n=== MAIN ARTICLE CONTENT ===\\n' + textContent;
          
          // Clean up whitespace
          fullContent = fullContent.replace(/\\s+/g, ' ').replace(/\\n\\s*\\n/g, '\\n\\n').trim();
          
          // Limit to ~50k characters to avoid token limits
          if (fullContent.length > 50000) {
            fullContent = fullContent.substring(0, 50000) + '... [content truncated]';
          }
          
          return fullContent;
        })();
      ''');
      
      if (result != null && result.toString().isNotEmpty) {
        final content = result.toString();
        print('✅ GOOGLE KG PREVIEW: Extracted ${content.length} characters of page content');
        return content;
      }
      return null;
    } catch (e) {
      print('❌ GOOGLE KG PREVIEW: Content extraction failed: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
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
        
        // WebView container
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
                // InAppWebView for better screenshot support
                SizedBox(
                  width: double.infinity,
                  height: _isExpanded ? 1000 : 600,
                  child: InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      mediaPlaybackRequiresUserGesture: false,
                      allowsInlineMediaPlayback: true,
                      useShouldOverrideUrlLoading: true,
                      userAgent: 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Mobile Safari/537.36',
                    ),
                    onWebViewCreated: (controller) {
                      _controller = controller;
                    },
                    onLoadStart: (controller, url) {
                      if (_isDisposed || !mounted) return;
                      print("🌐 GOOGLE KG WEBVIEW: Page started loading: $url");
                      setState(() {
                        _isLoading = true;
                        _hasError = false;
                      });
                    },
                    onLoadStop: (controller, url) async {
                      if (_isDisposed || !mounted) return;
                      print("🌐 GOOGLE KG WEBVIEW: Page finished loading: $url");
                      setState(() {
                        _isLoading = false;
                      });
                      
                      // Enable basic scrolling with JavaScript
                      try {
                        await controller.evaluateJavascript(source: '''
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
                    onReceivedError: (controller, request, error) {
                      if (_isDisposed || !mounted) return;
                      print("🌐 GOOGLE KG WEBVIEW: Error loading page: ${error.description}");
                      setState(() {
                        _isLoading = false;
                        _hasError = true;
                      });
                    },
                    shouldOverrideUrlLoading: (controller, navigationAction) async {
                      final url = navigationAction.request.url?.toString() ?? '';
                      
                      // Allow all Google-related navigation
                      if (url.contains('google.com') || 
                          url.contains('share.google') ||
                          url.contains('g.co')) {
                        return NavigationActionPolicy.ALLOW;
                      }
                      
                      // For external links, open in external browser
                      if (url.startsWith('http://') || url.startsWith('https://')) {
                        widget.launchUrlCallback(url);
                        return NavigationActionPolicy.CANCEL;
                      }
                      
                      return NavigationActionPolicy.ALLOW;
                    },
                  ),
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
    if (_isDisposed || !mounted) return;
    print("🌐 GOOGLE KG WEBVIEW: Refreshing preview to original URL: ${widget.url}");
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    // Load the original shared URL, not just refresh current page
    _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(widget.url)));
  }
  
  void _toggleExpand() {
    if (_isDisposed || !mounted) return;
    print("🌐 GOOGLE KG WEBVIEW: Toggling expand state from $_isExpanded");
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }
}
