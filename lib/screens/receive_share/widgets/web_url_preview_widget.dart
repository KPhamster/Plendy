import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:typed_data';
import 'package:plendy/utils/haptic_feedback.dart';

class WebUrlPreviewWidget extends StatefulWidget {
  final String url;
  final Future<void> Function(String) launchUrlCallback;
  final void Function(InAppWebViewController)? onWebViewCreated;
  final void Function(String url)? onPageFinished;
  final bool showControls;
  final double? height;

  const WebUrlPreviewWidget({
    super.key,
    required this.url,
    required this.launchUrlCallback,
    this.onWebViewCreated,
    this.onPageFinished,
    this.showControls = true,
    this.height,
  });

  @override
  State<WebUrlPreviewWidget> createState() => WebUrlPreviewWidgetState();
}

class WebUrlPreviewWidgetState extends State<WebUrlPreviewWidget> with AutomaticKeepAliveClientMixin {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isExpanded = false;
  bool _isDisposed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  /// Take a screenshot of the current WebView content
  /// Uses PNG format for best quality OCR/text detection
  Future<Uint8List?> takeScreenshot() async {
    if (_controller == null) {
      print('⚠️ WEB PREVIEW: Controller is null, cannot take screenshot');
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
        print('✅ WEB PREVIEW: Screenshot captured (${screenshot.length} bytes, PNG format)');
      }
      return screenshot;
    } catch (e) {
      print('❌ WEB PREVIEW: Screenshot failed: $e');
      return null;
    }
  }

  /// Extract all text content from the current page
  /// This is useful for scraping articles with lists of locations
  Future<String?> extractPageContent() async {
    if (_controller == null) {
      print('⚠️ WEB PREVIEW: Controller is null, cannot extract content');
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
        print('✅ WEB PREVIEW: Extracted ${content.length} characters of page content');
        return content;
      }
      return null;
    } catch (e) {
      print('❌ WEB PREVIEW: Content extraction failed: $e');
      return null;
    }
  }

  /// Get the current page URL (may differ from initial URL after redirects)
  Future<String?> getCurrentUrl() async {
    if (_controller == null) return widget.url;
    try {
      final url = await _controller!.getUrl();
      return url?.toString() ?? widget.url;
    } catch (e) {
      return widget.url;
    }
  }

  void refreshWebView() {
    if (_controller != null) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
      _controller!.loadUrl(urlRequest: URLRequest(url: WebUri(widget.url)));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final double resolvedHeight = widget.showControls
        ? (_isExpanded ? 1000 : 600)
        : (widget.height ?? 600);

    final Widget webViewStack = Container(
      height: resolvedHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        border: widget.showControls
            ? Border.all(color: Colors.grey.shade300)
            : null,
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.url)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              iframeAllowFullscreen: false,
              userAgent: 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Mobile Safari/537.36',
            ),
            onWebViewCreated: (controller) {
              _controller = controller;
              widget.onWebViewCreated?.call(controller);
            },
            onLoadStart: (controller, url) {
              if (!mounted || _isDisposed) return;
              setState(() {
                _isLoading = true;
                _hasError = false;
              });
            },
            onLoadStop: (controller, url) async {
              if (!mounted || _isDisposed) return;
              setState(() {
                _isLoading = false;
              });
              try {
                await controller.evaluateJavascript(source: '''
                  document.body.style.overflow = 'auto';
                  document.documentElement.style.overflow = 'auto';
                  document.body.style.touchAction = 'auto';
                  document.body.style.webkitOverflowScrolling = 'touch';
                  document.body.style.height = 'auto';
                  document.body.style.width = '100%';
                  document.body.style.position = 'relative';
                ''');
              } catch (_) {}
              // Notify parent that page has finished loading
              widget.onPageFinished?.call(url?.toString() ?? widget.url);
            },
            onReceivedError: (controller, request, error) {
              if (!mounted || _isDisposed) return;
              setState(() {
                _isLoading = false;
                _hasError = true;
              });
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final String url = navigationAction.request.url?.toString() ?? '';
              
              // Keep standard web links inside WebView
              if (url.startsWith('http://') || url.startsWith('https://')) {
                return NavigationActionPolicy.ALLOW;
              }
              
              // Handle Android intent:// deep links
              if (url.startsWith('intent://')) {
                final String? fallback = _extractBrowserFallbackUrl(url);
                if (fallback != null && (fallback.startsWith('http://') || fallback.startsWith('https://'))) {
                  controller.loadUrl(urlRequest: URLRequest(url: WebUri(fallback)));
                }
                return NavigationActionPolicy.CANCEL;
              }
              
              // Handle custom Yelp scheme
              if (url.startsWith('yelp://')) {
                final String path = url.replaceFirst('yelp://', '');
                final String httpsUrl = 'https://www.yelp.com/$path';
                controller.loadUrl(urlRequest: URLRequest(url: WebUri(httpsUrl)));
                return NavigationActionPolicy.CANCEL;
              }
              
              widget.launchUrlCallback(url);
              return NavigationActionPolicy.CANCEL;
            },
          ),
          if (_isLoading)
            Container(
              color: Colors.white.withOpacity(0.8),
              child: const Center(
                child: CircularProgressIndicator(),
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
    );

    if (!widget.showControls) {
      return webViewStack;
    }

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
                  onTap: withHeavyTap(() => widget.launchUrlCallback(widget.url)),
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
        webViewStack,
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
                onPressed: refreshWebView,
                icon: Icon(Icons.refresh, size: 20, color: Colors.blue.shade700),
                tooltip: 'Refresh Preview',
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => widget.launchUrlCallback(widget.url),
                icon: Icon(Icons.open_in_new, size: 20, color: Colors.blue.shade700),
                tooltip: 'Open Link',
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              const Spacer(),
              IconButton(
                onPressed: _toggleExpand,
                icon: Icon(_isExpanded ? Icons.fullscreen_exit : Icons.fullscreen, size: 20, color: Colors.blue.shade700),
                tooltip: _isExpanded ? 'Collapse Preview' : 'Expand Preview',
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ),
      ],
    );
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
