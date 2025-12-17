import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../services/instagram_oembed_service.dart';

// Conditional imports for web support
import 'instagram_web_logic.dart' if (dart.library.io) 'instagram_web_logic_stub.dart' as web_logic;

/// Instagram WebView widget using Meta oEmbed API for embedding Instagram content
/// On web, uses oEmbed API to get embed HTML and renders in an iframe
/// On mobile, uses oEmbed API to get embed HTML and renders in InAppWebView
class InstagramWebView extends StatefulWidget {
  final String url;
  final double height;
  final Future<void> Function(String) launchUrlCallback;
  final Function(InAppWebViewController)? onWebViewCreated;
  final Function(String)? onPageFinished;

  const InstagramWebView({
    super.key,
    required this.url,
    required this.height,
    required this.launchUrlCallback,
    this.onWebViewCreated,
    this.onPageFinished,
  });

  @override
  InstagramWebViewState createState() => InstagramWebViewState();
}

class InstagramWebViewState extends State<InstagramWebView> {
  InAppWebViewController? controller;
  bool isLoading = true;
  
  int _loadingDelayOperationId = 0;
  bool _isDisposed = false;
  
  // oEmbed state (used for both web and mobile)
  String? _webViewType;
  String? _oembedHtml;
  String? _errorMessage;
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
      _errorMessage = null;
    });
    
    try {
      // Normalize URL: convert /reel/ and /tv/ to /p/, remove query params
      final normalizedUrl = _normalizeInstagramUrl(widget.url);
      print('📸 INSTAGRAM: Fetching oEmbed data for $normalizedUrl (original: ${widget.url})');
      
      final oembedService = InstagramOEmbedService();
      
      if (!oembedService.isConfigured) {
        print('⚠️ INSTAGRAM: oEmbed service not configured');
        if (kIsWeb) {
          setState(() {
            _errorMessage = 'Instagram API not configured';
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
      
      final metadata = await oembedService.getPostMetadata(normalizedUrl);
      
      if (!mounted || _isDisposed) return;
      
      if (metadata != null && metadata['html'] != null) {
        final embedHtml = metadata['html'] as String;
        print('✅ INSTAGRAM: Got oEmbed HTML (${embedHtml.length} chars)');
        
        // Create full HTML document with Instagram embed.js
        final fullHtml = _buildEmbedHtmlDocument(embedHtml);
        
        if (kIsWeb) {
          // On web, register the view factory for iframe
          _webViewType = 'instagram-oembed-${widget.url.hashCode}-${DateTime.now().millisecondsSinceEpoch}';
          web_logic.registerInstagramViewFactory(_webViewType!, fullHtml);
          
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
        print('❌ INSTAGRAM: No oEmbed HTML returned');
        if (kIsWeb) {
          setState(() {
            _errorMessage = 'Could not load Instagram preview';
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
      print('❌ INSTAGRAM ERROR: $e');
      if (mounted && !_isDisposed) {
        if (kIsWeb) {
          setState(() {
            _errorMessage = 'Error loading Instagram preview';
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
  
  /// Build the full HTML document with Instagram embed
  String _buildEmbedHtmlDocument(String embedHtml) {
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
      background: #fafafa;
      overflow: auto;
    }
    body {
      display: flex;
      justify-content: center;
      align-items: flex-start;
      padding: 8px;
    }
    .instagram-media {
      max-width: 100% !important;
      min-width: 280px !important;
      width: 100% !important;
      margin: 0 auto !important;
    }
    blockquote.instagram-media {
      background: #FFF;
      border: 0;
      border-radius: 8px;
      box-shadow: 0 0 1px 0 rgba(0,0,0,0.5), 0 1px 10px 0 rgba(0,0,0,0.15);
      margin: 0 auto;
      max-width: 540px;
      min-width: 280px;
      padding: 0;
      width: calc(100% - 2px);
    }
  </style>
</head>
<body>
  $embedHtml
  <script async src="//www.instagram.com/embed.js"></script>
  <script>
    // Force process embeds when script loads
    if (window.instgrm) {
      window.instgrm.Embeds.process();
    } else {
      document.querySelector('script[src*="embed.js"]').addEventListener('load', function() {
        if (window.instgrm) {
          window.instgrm.Embeds.process();
        }
      });
    }
  </script>
</body>
</html>
''';
  }

  /// Take a screenshot of the current WebView content
  /// Uses PNG format for best quality OCR/text detection
  /// Note: Screenshot is not available on web
  Future<Uint8List?> takeScreenshot() async {
    if (kIsWeb) {
      print('⚠️ INSTAGRAM PREVIEW: Screenshot not available on web');
      return null;
    }
    
    if (controller == null) {
      print('⚠️ INSTAGRAM PREVIEW: Controller is null, cannot take screenshot');
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
        print('✅ INSTAGRAM PREVIEW: Screenshot captured (${screenshot.length} bytes, PNG format)');
      }
      return screenshot;
    } catch (e) {
      print('❌ INSTAGRAM PREVIEW: Screenshot failed: $e');
      return null;
    }
  }

  void refresh() {
    _initializeOEmbed();
  }

  /// Normalize Instagram URL:
  /// - Convert /reel/ to /p/ format (both point to same content)
  /// - Remove query parameters
  /// - Ensure trailing slash
  String _normalizeInstagramUrl(String url) {
    try {
      Uri uri = Uri.parse(url);
      String path = uri.path;
      
      // Convert /reel/ to /p/ - both formats point to the same content
      // but /p/ is more universally supported by the oEmbed API
      if (path.contains('/reel/')) {
        path = path.replaceFirst('/reel/', '/p/');
      }
      
      // Also handle /tv/ (IGTV) - convert to /p/
      if (path.contains('/tv/')) {
        path = path.replaceFirst('/tv/', '/p/');
      }
      
      String cleanUrl = '${uri.scheme}://${uri.host}$path';
      if (!cleanUrl.endsWith('/')) {
        cleanUrl = '$cleanUrl/';
      }
      return cleanUrl;
    } catch (e) {
      // Fallback: simple string manipulation
      if (url.contains('?')) {
        url = url.split('?')[0];
      }
      // Convert /reel/ to /p/
      url = url.replaceFirst('/reel/', '/p/');
      url = url.replaceFirst('/tv/', '/p/');
      if (!url.endsWith('/')) {
        url = '$url/';
      }
      return url;
    }
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
          color: const Color(0xFFFAFAFA),
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading Instagram content...'),
            ],
          ),
        ),
      );
    }
    
    // Show error state
    if (_errorMessage != null) {
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
              Icon(Icons.error_outline, color: Colors.grey[600], size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => widget.launchUrlCallback(widget.url),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open in Instagram'),
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
        child: web_logic.buildInstagramWebViewForWeb(_webViewType!),
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
      child: const Center(
        child: Text('Instagram preview unavailable'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _buildWebView();
    }

    final double containerHeight = widget.height;
    
    // If using oEmbed and we have HTML, load it in WebView
    final bool loadOEmbedHtml = _useOEmbed && _oembedHtml != null;
    
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          height: containerHeight,
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.hardEdge,
          child: InAppWebView(
            initialUrlRequest: loadOEmbedHtml 
                ? null 
                : URLRequest(url: WebUri(_normalizeInstagramUrl(widget.url))),
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
              userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
            ),
            onWebViewCreated: (webController) {
              controller = webController;
              widget.onWebViewCreated?.call(webController);
            },
            onLoadStart: (webController, url) {
              if (!mounted || _isDisposed) return;
              
              setState(() {
                isLoading = true;
              });
            },
            onLoadStop: (webController, url) async {
              if (!mounted || _isDisposed) return;
              
              // Notify parent
              try {
                widget.onPageFinished?.call(url?.toString() ?? '');
              } catch (e) {
                print("Error in onPageFinished callback: $e");
              }
              
              // Strip fullscreen permissions and enforce inline playback
              try {
                await webController.evaluateJavascript(source: '''
                  (function(){
                    try {
                      var iframes = document.querySelectorAll('iframe');
                      iframes.forEach(function(iframe){
                        iframe.removeAttribute('allowfullscreen');
                        var allow = iframe.getAttribute('allow') || '';
                        allow = allow.replace(/fullscreen/g,'').trim();
                        if (allow.length>0) { iframe.setAttribute('allow', allow); } else { iframe.removeAttribute('allow'); }
                        iframe.setAttribute('playsinline','');
                      });
                      var videos = document.querySelectorAll('video');
                      videos.forEach(function(v){ v.setAttribute('playsinline',''); v.removeAttribute('webkit-playsinline'); });
                    } catch(e) {}
                  })();
                ''');
              } catch (_) {}
              
              // Set loading to false after a short delay
              final currentLoadingOperationId = ++_loadingDelayOperationId;
              
              Future.delayed(const Duration(milliseconds: 500), () {
                if (!mounted || _isDisposed || _loadingDelayOperationId != currentLoadingOperationId) return;
                
                setState(() {
                  isLoading = false;
                });
              });
            },
            onReceivedError: (webController, request, error) {
              print("WebView Error: ${error.description}");
              
              if (!mounted || _isDisposed) return;
              
              setState(() {
                isLoading = false;
              });
            },
            shouldOverrideUrlLoading: (webController, navigationAction) async {
              final url = navigationAction.request.url?.toString() ?? '';
              
              // Handle about:blank URLs
              if (url == 'about:blank' || url == 'https://about:blank') {
                return NavigationActionPolicy.CANCEL;
              }
              
              // Block custom schemes
              final customSchemes = ['instagram', 'fb', 'intent'];
              if (customSchemes.any((scheme) => url.startsWith('$scheme:'))) {
                return NavigationActionPolicy.CANCEL;
              }
              
              // Allow Instagram domains, CDN, and Facebook authentication
              if (url.contains('instagram.com') || 
                  url.contains('cdn.instagram.com') ||
                  url.contains('cdninstagram.com') ||
                  url.contains('fbcdn.net') ||
                  url.contains('facebook.com/instagram/') ||
                  url.contains('facebook.com/login/') ||
                  url.contains('accounts.instagram.com')) {
                return NavigationActionPolicy.ALLOW;
              }
              
              // For external links, use callback
              if (mounted && !_isDisposed && url.startsWith('http')) {
                try {
                  widget.launchUrlCallback(url);
                } catch (e) {
                  print("Error in launchUrlCallback: $e");
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
            color: Colors.white.withOpacity(0.7),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading Instagram content...')
                ],
              ),
            ),
          ),
      ],
    );
  }
}
