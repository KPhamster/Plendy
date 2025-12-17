import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../services/facebook_oembed_service.dart';
import '../../../config/api_secrets.dart';

// Conditional imports for web support
import 'facebook_web_logic.dart' if (dart.library.io) 'facebook_web_logic_stub.dart' as web_logic;

/// Facebook WebView widget using Meta oEmbed API for embedding Facebook content
/// On web, uses oEmbed API to get embed HTML and renders in an iframe
/// On mobile, uses oEmbed API to get embed HTML and renders in InAppWebView
class FacebookPreviewWidget extends StatefulWidget {
  final String url;
  final double height;
  final Function(InAppWebViewController)? onWebViewCreated;
  final Function(String)? onPageFinished;
  final Future<void> Function(String) launchUrlCallback;
  final bool showControls;

  const FacebookPreviewWidget({
    super.key,
    required this.url,
    required this.height,
    this.onWebViewCreated,
    this.onPageFinished,
    required this.launchUrlCallback,
    this.showControls = true,
  });

  @override
  State<FacebookPreviewWidget> createState() => FacebookPreviewWidgetState();
}

class FacebookPreviewWidgetState extends State<FacebookPreviewWidget> {
  InAppWebViewController? controller;
  bool isLoading = true;
  bool hasError = false;
  String? errorMessage;
  bool _isExpanded = false;
  bool _isDisposed = false;
  
  // oEmbed state
  String? _oembedHtml;
  String? _webViewType;
  bool _webViewRegistered = false;
  bool _useOEmbed = true; // Whether to use oEmbed API

  @override
  void initState() {
    super.initState();
    _initializeOEmbed();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  /// Initialize the embed using Meta oEmbed API
  Future<void> _initializeOEmbed() async {
    setState(() {
      isLoading = true;
      hasError = false;
      errorMessage = null;
    });
    
    try {
      print('📘 FACEBOOK: Fetching oEmbed data for ${widget.url}');
      
      final oembedService = FacebookOEmbedService();
      
      if (!oembedService.isConfigured) {
        print('⚠️ FACEBOOK: oEmbed service not configured');
        if (kIsWeb) {
          setState(() {
            errorMessage = 'Facebook API not configured';
            hasError = true;
            isLoading = false;
          });
        } else {
          // On mobile, fall back to direct WebView loading
          setState(() {
            _useOEmbed = false;
            isLoading = false;
          });
        }
        return;
      }
      
      final oembedData = await oembedService.getOEmbedData(widget.url);
      
      if (!mounted || _isDisposed) return;
      
      if (oembedData != null && oembedData['html'] != null) {
        final embedHtml = oembedData['html'] as String;
        print('✅ FACEBOOK: Got oEmbed HTML (${embedHtml.length} chars)');
        
        // Create full HTML document with Facebook SDK
        final fullHtml = _buildEmbedHtmlDocument(embedHtml);
        
        if (kIsWeb) {
          // On web, register the view factory for iframe
          _webViewType = 'facebook-oembed-${widget.url.hashCode}-${DateTime.now().millisecondsSinceEpoch}';
          web_logic.registerFacebookViewFactory(_webViewType!, fullHtml);
          
          setState(() {
            _oembedHtml = fullHtml;
            _webViewRegistered = true;
            isLoading = false;
          });
        } else {
          // On mobile, we'll load the HTML in InAppWebView
          setState(() {
            _oembedHtml = fullHtml;
            _useOEmbed = true;
            isLoading = false;
          });
        }
        
        // Notify parent that page finished loading
        widget.onPageFinished?.call(widget.url);
      } else {
        print('❌ FACEBOOK: No oEmbed HTML returned');
        if (kIsWeb) {
          setState(() {
            errorMessage = 'Could not load Facebook preview';
            hasError = true;
            isLoading = false;
          });
        } else {
          // On mobile, fall back to direct URL loading
          setState(() {
            _useOEmbed = false;
            isLoading = false;
          });
        }
      }
    } catch (e) {
      print('❌ FACEBOOK ERROR: $e');
      if (mounted && !_isDisposed) {
        if (kIsWeb) {
          setState(() {
            errorMessage = 'Error loading Facebook preview';
            hasError = true;
            isLoading = false;
          });
        } else {
          // On mobile, fall back to direct URL loading
          setState(() {
            _useOEmbed = false;
            isLoading = false;
          });
        }
      }
    }
  }
  
  /// Build the full HTML document with Facebook SDK for oEmbed content
  String _buildEmbedHtmlDocument(String embedHtml) {
    // Get the Facebook App ID for SDK initialization
    final appId = ApiSecrets.facebookAppId;
    
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    html, body {
      width: 100%;
      height: 100%;
      background: #f0f2f5;
      overflow: auto;
    }
    body {
      display: flex;
      justify-content: center;
      align-items: flex-start;
      padding: 8px;
    }
    .fb-post, .fb-video {
      max-width: 100% !important;
      width: 100% !important;
    }
    iframe {
      max-width: 100% !important;
    }
  </style>
</head>
<body>
  <div id="fb-root"></div>
  $embedHtml
  <script async defer crossorigin="anonymous" 
    src="https://connect.facebook.net/en_US/sdk.js#xfbml=1&version=v21.0&appId=$appId">
  </script>
  <script>
    // Ensure Facebook SDK processes embeds
    window.fbAsyncInit = function() {
      FB.init({
        appId: '$appId',
        xfbml: true,
        version: 'v21.0'
      });
      FB.XFBML.parse();
    };
    
    // Fallback: try to parse after a delay if SDK already loaded
    setTimeout(function() {
      if (typeof FB !== 'undefined' && FB.XFBML) {
        FB.XFBML.parse();
      }
    }, 1000);
  </script>
</body>
</html>
''';
  }

  /// Take a screenshot of the current WebView content
  /// Uses PNG format for best quality OCR/text detection
  Future<Uint8List?> takeScreenshot() async {
    if (kIsWeb) {
      print('⚠️ FACEBOOK PREVIEW: Screenshot not available on web');
      return null;
    }
    
    if (controller == null) {
      print('⚠️ FACEBOOK PREVIEW: Controller is null, cannot take screenshot');
      return null;
    }
    
    try {
      // Use PNG format (lossless) for best text/OCR quality
      final screenshot = await controller!.takeScreenshot(
        screenshotConfiguration: ScreenshotConfiguration(
          compressFormat: CompressFormat.PNG,
          quality: 100,
        ),
      );
      if (screenshot != null) {
        print('✅ FACEBOOK PREVIEW: Screenshot captured (${screenshot.length} bytes, PNG format)');
      }
      return screenshot;
    } catch (e) {
      print('❌ FACEBOOK PREVIEW: Screenshot failed: $e');
      return null;
    }
  }

  /// Extract text content from the WebView page for location analysis
  Future<String?> extractPageContent() async {
    if (kIsWeb) {
      // On web, we can try to extract from oEmbed data
      if (_oembedHtml != null) {
        final service = FacebookOEmbedService();
        return service.extractTextFromHtml(_oembedHtml!);
      }
      return null;
    }
    
    if (controller == null) {
      print('⚠️ FACEBOOK PREVIEW: Controller is null, cannot extract content');
      return null;
    }
    
    try {
      // For Reels, we need to interact with the page to reveal the full description
      // Step 1: Try to expand any collapsed content by clicking "See more" type buttons
      await controller!.evaluateJavascript(source: '''
        (function() {
          try {
            // Click any "See more", "...more", or expansion buttons
            var clickTargets = document.querySelectorAll('[role="button"], a, span');
            clickTargets.forEach(function(el) {
              var text = (el.innerText || el.textContent || '').toLowerCase().trim();
              if (text === 'see more' || text === '...more' || text === 'more' || 
                  text === '... more' || text.endsWith('more') || text === '...') {
                try { el.click(); } catch(e) {}
              }
            });
            
            // Also try clicking on the description area to expand it
            var descAreas = document.querySelectorAll('[data-sigil*="more"], [data-gt*="see_more"]');
            descAreas.forEach(function(el) {
              try { el.click(); } catch(e) {}
            });
          } catch(e) {}
        })();
      ''');
      
      // Wait for expansion animation
      await Future.delayed(const Duration(milliseconds: 800));
      
      // Step 2: Scroll down to reveal more content
      await controller!.evaluateJavascript(source: '''
        (function() {
          try {
            // Scroll down multiple times to load more content
            window.scrollTo(0, 300);
            setTimeout(function() { window.scrollTo(0, 600); }, 200);
            setTimeout(function() { window.scrollTo(0, 900); }, 400);
          } catch(e) {}
        })();
      ''');
      
      // Wait for content to load after scroll
      await Future.delayed(const Duration(milliseconds: 800));
      
      // Execute JavaScript to extract text content from the page
      final result = await controller!.evaluateJavascript(source: '''
        (function() {
          try {
            var content = '';
            var isReel = window.location.href.includes('/reel/') || window.location.href.includes('/reels/');
            var seenTexts = new Set();
            
            // Helper function to check if text is UI noise
            function isUIText(text) {
              var lower = text.toLowerCase();
              var uiPatterns = [
                'log in', 'sign up', 'create new account', 'forgot password',
                'videos', 'reels', 'following', 'for you', 'saved',
                'like', 'comment', 'share', 'send', 'follow',
                'notifications', 'menu', 'search', 'home', 'watch',
                'marketplace', 'groups', 'gaming', 'more'
              ];
              // Skip very short text
              if (text.length < 15) return true;
              // Skip if it's just a UI element
              for (var pattern of uiPatterns) {
                if (lower === pattern || lower === pattern + 's') return true;
              }
              // Skip if it matches count patterns (15+ views, 8 likes, etc)
              if (/^\\d+[KMB]?\\+?\\s*(views?|likes?|comments?|shares?)?\$/i.test(text.trim())) return true;
              return false;
            }
            
            // Helper to add unique text
            function addText(text) {
              text = text.trim();
              if (text && !seenTexts.has(text) && !isUIText(text)) {
                seenTexts.add(text);
                content += text + ' ';
              }
            }
            
            // ===== STRATEGY 1: Look for spans with dir="auto" (common for user content) =====
            var dirAutoSpans = document.querySelectorAll('span[dir="auto"]');
            dirAutoSpans.forEach(function(span) {
              var text = span.innerText || '';
              if (text.length > 20) {
                addText(text);
              }
            });
            
            // ===== STRATEGY 2: Look for any element containing hashtags or @ mentions =====
            var allElements = document.querySelectorAll('*');
            allElements.forEach(function(el) {
              var text = el.innerText || '';
              // Look for content with hashtags, @ mentions, or restaurant-like keywords
              if ((text.includes('#') || text.includes('@') || 
                   /restaurant|cafe|bar|food|eat|dining|brunch|lunch|dinner/i.test(text)) &&
                  text.length > 30 && text.length < 3000) {
                addText(text);
              }
            });
            
            // ===== STRATEGY 3: Look for text containing location-like content =====
            var bodyText = document.body.innerText || '';
            var lines = bodyText.split('\\n');
            lines.forEach(function(line) {
              line = line.trim();
              // Look for lines that look like descriptions (contain addresses, restaurant names, etc)
              if (line.length > 40 && line.length < 2000 &&
                  (/\\d+\\.\\s|•|→|📍|🍽|🍴|🥘|🍜|restaurant|cafe|bar|food|place|spot|weekend|try|visit|best|top|favorite/i.test(line))) {
                addText(line);
              }
            });
            
            // ===== STRATEGY 4: Get article content =====
            var articles = document.querySelectorAll('[role="article"], article');
            articles.forEach(function(article) {
              var text = article.innerText || '';
              if (text.length > 50) {
                addText(text);
              }
            });
            
            // ===== STRATEGY 5: If still not enough, get all visible text =====
            if (content.trim().length < 200) {
              // Get all text from divs that might contain descriptions
              var divs = document.querySelectorAll('div');
              divs.forEach(function(div) {
                var text = div.innerText || '';
                // Look for divs with substantial text that aren't just UI
                if (text.length > 100 && text.length < 5000 && 
                    !div.querySelector('nav, header, footer, [role="navigation"]')) {
                  addText(text);
                }
              });
            }
            
            // ===== ABSOLUTE FALLBACK: Get full body text =====
            if (content.trim().length < 200) {
              content = bodyText;
            }
            
            // Clean up content
            content = content.replace(/\\s+/g, ' ').trim();
            
            // Limit to first 15000 characters for processing
            if (content.length > 15000) {
              content = content.substring(0, 15000);
            }
            
            return content;
          } catch(e) {
            return document.body.innerText || '';
          }
        })();
      ''');
      
      if (result != null && result is String && result.isNotEmpty && result != 'null') {
        print('✅ FACEBOOK PREVIEW: Extracted ${result.length} characters of content');
        return result;
      }
      
      print('⚠️ FACEBOOK PREVIEW: No content extracted');
      return null;
    } catch (e) {
      print('❌ FACEBOOK PREVIEW: Content extraction failed: $e');
      return null;
    }
  }

  Future<void> _launchFacebookUrl() async {
    final Uri uri = Uri.parse(widget.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open Facebook link: ${widget.url}')),
        );
      }
    }
  }
  
  void refresh() {
    _initializeOEmbed();
  }

  /// Build the web-specific view using Meta oEmbed
  Widget _buildWebView() {
    final double containerHeight = widget.height;
    
    // Show loading state
    if (isLoading) {
      return Container(
        height: containerHeight,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F2F5),
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1877F2)),
              ),
              SizedBox(height: 16),
              Text('Loading Facebook content...'),
            ],
          ),
        ),
      );
    }
    
    // Show error state
    if (hasError) {
      return Container(
        height: containerHeight,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FaIcon(
                FontAwesomeIcons.facebook,
                size: 48,
                color: Color(0xFF1877F2),
              ),
              const SizedBox(height: 16),
              Text(
                errorMessage ?? 'Could not load Facebook preview',
                style: TextStyle(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _launchFacebookUrl,
                icon: const FaIcon(FontAwesomeIcons.facebook, size: 16),
                label: const Text('Open in Facebook'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1877F2),
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _initializeOEmbed,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    
    // Show the embedded content
    if (_webViewRegistered && _webViewType != null) {
      return Container(
        height: containerHeight,
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.hardEdge,
        child: web_logic.buildFacebookWebViewForWeb(_webViewType!),
      );
    }
    
    // Fallback - shouldn't reach here normally
    return Container(
      height: containerHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FaIcon(
              FontAwesomeIcons.facebook,
              size: 48,
              color: Color(0xFF1877F2),
            ),
            const SizedBox(height: 16),
            const Text('Facebook preview unavailable'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _launchFacebookUrl,
              icon: const FaIcon(FontAwesomeIcons.facebook, size: 16),
              label: const Text('Open in Facebook'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1877F2),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _buildWebView();
    }

    final double containerHeight = _isExpanded ? 1200 : widget.height;
    
    // If using oEmbed and we have HTML, load it in WebView
    final bool loadOEmbedHtml = _useOEmbed && _oembedHtml != null;
    
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              height: containerHeight,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.hardEdge,
              child: InAppWebView(
                initialUrlRequest: loadOEmbedHtml 
                    ? null 
                    : URLRequest(url: WebUri(widget.url)),
                initialData: loadOEmbedHtml 
                    ? InAppWebViewInitialData(
                        data: _oembedHtml!,
                        mimeType: 'text/html',
                        encoding: 'utf-8',
                      )
                    : null,
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  iframeAllowFullscreen: false,
                  transparentBackground: true,
                  userAgent: "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Mobile Safari/537.36",
                ),
                onWebViewCreated: (webController) {
                  controller = webController;
                  widget.onWebViewCreated?.call(webController);
                },
                onLoadStart: (webController, url) {
                  if (!mounted || _isDisposed) return;
                  setState(() {
                    isLoading = true;
                    hasError = false;
                    errorMessage = null;
                  });
                },
                onLoadStop: (webController, url) async {
                  if (!mounted || _isDisposed) return;
                  
                  try {
                    widget.onPageFinished?.call(url?.toString() ?? '');
                  } catch (e) {
                    if (kDebugMode) {
                      print("Error in onPageFinished callback: $e");
                    }
                  }
                  
                  // Remove fullscreen permissions
                  try {
                    await webController.evaluateJavascript(source: '''
                      (function(){
                        try {
                          var iframes = document.querySelectorAll('iframe');
                          iframes.forEach(function(iframe){
                            iframe.removeAttribute('allowfullscreen');
                            iframe.setAttribute('playsinline','');
                          });
                          var videos = document.querySelectorAll('video');
                          videos.forEach(function(v){ v.setAttribute('playsinline',''); });
                        } catch(e) {}
                      })();
                    ''');
                  } catch (_) {}

                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (!mounted || _isDisposed) return;
                    setState(() {
                      isLoading = false;
                    });
                  });
                },
                onReceivedError: (webController, request, error) {
                  if (kDebugMode) {
                    print("Facebook WebView Error: ${error.description}");
                  }
                  if (!mounted || _isDisposed) return;
                  setState(() {
                    isLoading = false;
                    hasError = true;
                    errorMessage = error.description;
                  });
                },
                shouldOverrideUrlLoading: (webController, navigationAction) async {
                  final url = navigationAction.request.url?.toString() ?? '';
                  
                  // Handle about:blank URLs
                  if (url == 'about:blank' || url == 'https://about:blank') {
                    return NavigationActionPolicy.CANCEL;
                  }
                  
                  // Block custom schemes (fb://, intent://, etc.) that WebView can't handle
                  final customSchemes = ['fb', 'intent', 'market', 'instagram'];
                  if (customSchemes.any((scheme) => url.startsWith('$scheme:'))) {
                    if (kDebugMode) {
                      print('Facebook WebView: Blocked custom scheme URL: $url');
                    }
                    return NavigationActionPolicy.CANCEL;
                  }
                  
                  // Allow Facebook domains and CDN
                  if (url.contains('facebook.com') || 
                      url.contains('fb.com') ||
                      url.contains('fbcdn.net') ||
                      url.contains('m.facebook.com') ||
                      url.contains('web.facebook.com') ||
                      url.contains('static.xx.fbcdn.net') ||
                      url.contains('connect.facebook.net')) {
                    return NavigationActionPolicy.ALLOW;
                  }
                  
                  // For external links, launch externally
                  if (mounted && !_isDisposed && url.startsWith('http')) {
                    try {
                      widget.launchUrlCallback(url);
                    } catch (e) {
                      if (kDebugMode) {
                        print("Error in launchUrlCallback: $e");
                      }
                    }
                  }
                  
                  return NavigationActionPolicy.CANCEL;
                },
              ),
            ),
            if (isLoading)
              Container(
                width: double.infinity,
                height: containerHeight,
                color: Colors.white.withOpacity(0.9),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1877F2)),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Loading Facebook content...',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (hasError)
              Container(
                width: double.infinity,
                height: containerHeight,
                color: Colors.white,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Unable to load content',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        errorMessage ?? 'This content may be private or unavailable',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _launchFacebookUrl,
                        icon: const FaIcon(FontAwesomeIcons.facebook, size: 16),
                        label: const Text('Open in Facebook'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1877F2),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (widget.showControls) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: refresh,
              ),
              IconButton(
                icon: const FaIcon(FontAwesomeIcons.facebook, color: Color(0xFF1877F2)),
                tooltip: 'Open in Facebook',
                onPressed: _launchFacebookUrl,
              ),
              IconButton(
                icon: Icon(_isExpanded ? Icons.fullscreen_exit : Icons.fullscreen),
                tooltip: _isExpanded ? 'Collapse' : 'Expand',
                onPressed: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
              ),
            ],
          ),
        ]
      ],
    );
  }
}
