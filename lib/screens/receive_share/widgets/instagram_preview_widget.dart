import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../services/instagram_oembed_service.dart';
import '../../../services/instagram_settings_service.dart';
import 'package:plendy/models/receive_share_help_target.dart';

// Conditional imports for web support
import 'instagram_web_logic.dart'
    if (dart.library.io) 'instagram_web_logic_stub.dart' as web_logic;

/// Instagram WebView widget using Meta oEmbed API for embedding Instagram content
/// On web, uses oEmbed API to get embed HTML and renders in an iframe
/// On mobile, uses oEmbed API to get embed HTML and renders in InAppWebView
///
/// Settings:
/// - Default: Uses oEmbed HTML (no login required, some content may not play)
/// - Web View: Loads Instagram URL directly (may require login, plays all content)
class InstagramWebView extends StatefulWidget {
  final String url;
  final double height;
  final Future<void> Function(String) launchUrlCallback;
  final Function(InAppWebViewController)? onWebViewCreated;
  final Function(String)? onPageFinished;
  final Function(double)?
      onContentHeightChanged; // Callback when content height is measured
  final double topPadding;

  /// Optional override for display mode. When provided, bypasses user settings.
  /// true = Web View mode, false = Default mode, null = use settings
  final bool? overrideWebViewMode;

  /// Callback when user requests to switch to web view mode from error state.
  /// Parent should update overrideWebViewMode to true when this is called.
  final VoidCallback? onRequestWebViewMode;
  final bool isHelpMode;
  final bool Function(ReceiveShareHelpTargetId id, BuildContext ctx)? onHelpTap;

  const InstagramWebView({
    super.key,
    required this.url,
    required this.height,
    required this.launchUrlCallback,
    this.onWebViewCreated,
    this.onPageFinished,
    this.onContentHeightChanged,
    this.topPadding = 0,
    this.overrideWebViewMode,
    this.onRequestWebViewMode,
    this.isHelpMode = false,
    this.onHelpTap,
  });

  @override
  InstagramWebViewState createState() => InstagramWebViewState();
}

class InstagramWebViewState extends State<InstagramWebView> {
  InAppWebViewController? controller;
  bool isLoading = true;

  bool _helpTap(ReceiveShareHelpTargetId id, BuildContext ctx) {
    if (widget.onHelpTap != null) return widget.onHelpTap!(id, ctx);
    return false;
  }

  int _loadingDelayOperationId = 0;
  bool _isDisposed = false;

  // oEmbed state (used for both web and mobile)
  String? _webViewType;
  String? _oembedHtml;
  String? _errorMessage;
  bool _webViewRegistered = false;
  bool _useOEmbed = true; // Whether to use oEmbed API

  // Display mode from settings
  bool _forceDirectWebView =
      false; // When true, skip oEmbed and load URL directly

  @override
  void initState() {
    super.initState();
    _loadSettingsAndInitialize();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant InstagramWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reinitialize if override mode changed (from toggle chip or error state button)
    if (oldWidget.overrideWebViewMode != widget.overrideWebViewMode) {
      _loadSettingsAndInitialize();
    }
  }

  /// Switch to Web View mode (temporary, does not persist to settings)
  void _switchToWebViewMode() {
    print('🔄 INSTAGRAM: Requesting switch to Web View mode from error state');
    // Notify parent to switch mode - parent controls the override
    widget.onRequestWebViewMode?.call();
  }

  /// Build the error message widget with tappable "Web View" link
  Widget _buildErrorMessage() {
    const errorTextStyle = TextStyle(color: Color(0xFF616161), fontSize: 14);
    const webViewLinkStyle = TextStyle(
      color: Color(0xFFE1306C), // Instagram pink
      fontSize: 14,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: errorTextStyle,
        children: [
          const TextSpan(
            text:
                'Unable to load Instagram preview.\n\nThe uploader of this content may have disallowed embedding of their content in other apps, the content may be private, or it has been marked as inappropriate.\n\nTry opening in Instagram or switch to "',
          ),
          TextSpan(
            text: 'Web View',
            style: webViewLinkStyle,
            recognizer: TapGestureRecognizer()..onTap = _switchToWebViewMode,
          ),
          const TextSpan(
            text: '" mode.',
          ),
        ],
      ),
    );
  }

  /// Load user settings and initialize
  /// Called on init and when widget.overrideWebViewMode changes
  Future<void> _loadSettingsAndInitialize() async {
    // Check widget override first, otherwise load user's display preference
    final bool isWebViewMode;
    if (widget.overrideWebViewMode != null) {
      isWebViewMode = widget.overrideWebViewMode!;
      print(
          '🔧 INSTAGRAM: Using override mode - isWebViewMode: $isWebViewMode');
    } else {
      final settingsService = InstagramSettingsService.instance;
      isWebViewMode = await settingsService.isWebViewMode();
      print('🔧 INSTAGRAM: Loading settings - isWebViewMode: $isWebViewMode');
    }

    if (!mounted || _isDisposed) return;

    // Reset state for reinitialization
    setState(() {
      _forceDirectWebView = isWebViewMode;
      _oembedHtml = null;
      _errorMessage = null;
      _webViewRegistered = false;
      isLoading = true;
    });

    if (_forceDirectWebView && !kIsWeb) {
      // Direct WebView mode on mobile - skip oEmbed, load URL directly
      print('🔧 INSTAGRAM: Using DIRECT WebView mode');
      setState(() {
        _useOEmbed = false;
        isLoading = false;
      });
    } else {
      // Default mode - use oEmbed
      print('🔧 INSTAGRAM: Using oEmbed mode');
      setState(() {
        _useOEmbed = true;
      });
      _initializeOEmbed();
    }
  }

  /// Initialize the embed using Meta oEmbed API
  Future<void> _initializeOEmbed() async {
    setState(() {
      isLoading = true;
      _errorMessage = null;
    });

    try {
      // For oEmbed API: keep original /reel/ format (API supports it directly)
      final normalizedUrl =
          _normalizeInstagramUrl(widget.url, convertReelToPost: false);
      print(
          '📸 INSTAGRAM: Fetching oEmbed data for $normalizedUrl (original: ${widget.url})');

      final oembedService = InstagramOEmbedService();

      if (!oembedService.isConfigured) {
        print('⚠️ INSTAGRAM: oEmbed service not configured');
        setState(() {
          _errorMessage =
              'Instagram API not configured. Please configure Facebook App credentials.';
          isLoading = false;
        });
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
          _webViewType =
              'instagram-oembed-${widget.url.hashCode}-${DateTime.now().millisecondsSinceEpoch}';
          web_logic.registerInstagramViewFactory(_webViewType!, fullHtml);

          setState(() {
            _oembedHtml = fullHtml;
            _webViewRegistered = true;
            isLoading = false;
          });

          // Notify parent that page finished loading (web only - iframe is ready)
          widget.onPageFinished?.call(widget.url);
        } else {
          // On mobile, we'll load the HTML in InAppWebView
          // Note: onPageFinished will be called from onLoadStop when WebView actually loads
          setState(() {
            _oembedHtml = fullHtml;
            _useOEmbed = true;
            isLoading = false;
          });
        }
      } else {
        print('❌ INSTAGRAM: No oEmbed HTML returned - showing error state');
        // In Default mode, show error instead of falling back to WebView
        // This happens when the API fails (e.g., permissions error, private content)
        setState(() {
          _errorMessage =
              'Unable to load Instagram preview.\n\nThe uploader of this content may have disallowed embedding of their content in other apps, the content may be private, or it has been marked as inappropriate.\n\nTry opening in Instagram or switch to "Web View" mode in Settings.';
          isLoading = false;
        });
      }
    } catch (e) {
      print('❌ INSTAGRAM ERROR: $e');
      if (mounted && !_isDisposed) {
        setState(() {
          _errorMessage = 'Error loading Instagram preview: $e';
          isLoading = false;
        });
      }
    }
  }

  /// Build the full HTML document with Instagram embed
  String _buildEmbedHtmlDocument(String embedHtml) {
    final topPaddingValue = widget.topPadding.toInt();
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
      padding: ${topPaddingValue}px 8px 8px 8px;
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
    /* Hide captions in Instagram embeds for Default Mode - DISABLED for dynamic height */
    /*
    .instagram-media-rendered {
      overflow: hidden !important;
    }
    */
    /* Hide caption text containers - target various Instagram render structures */
    /*
    .instagram-media-rendered > div:last-child,
    .instagram-media-rendered > *:last-child,
    .instagram-media article > div:nth-child(2),
    .instagram-media [role="article"] > div:last-child,
    .instagram-media__caption,
    .instagram-media .caption,
    .instagram-media .post-caption,
    .instagram-media p:not([class]),
    .instagram-media-rendered p {
      display: none !important;
      height: 0 !important;
      visibility: hidden !important;
      overflow: hidden !important;
    }
    */
    /* Additional aggressive caption hiding */
    /*
    .instagram-media-rendered svg,
    .instagram-media article > svg {
      max-height: 500px !important;
      overflow: hidden !important;
    }
    */
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

    // Hide captions in Instagram embeds for Default Mode - DISABLED
    function hideInstagramCaptions() {
      // Function disabled to allow full content height
      return;
      
      /* Original hiding logic:
      try {
        // Find all Instagram embed containers
        var instagramEmbeds = document.querySelectorAll('.instagram-media, blockquote.instagram-media, .instagram-media-rendered');

        instagramEmbeds.forEach(function(embed) {
          // Strategy 1: Hide elements that look like they contain caption text
          // Instagram embeds contain multiple sections - we want to hide the text section
          
          // Hide all paragraphs and text containers
          var elementsToHide = embed.querySelectorAll('p, span, div');
          elementsToHide.forEach(function(el) {
            var text = el.textContent.trim();
            // Hide any text that's substantial and doesn't look like metadata
            if (text.length > 5 && 
                !text.includes('View on Instagram') &&
                !text.includes('@') && 
                !text.match(/^\d+\s*(like|comment|follow)/i) &&
                !text.match(/^(Just now|a few|minutes|hours|days|weeks|months|years)/i)) {
              el.style.display = 'none !important';
              el.style.height = '0 !important';
              el.style.overflow = 'hidden !important';
              el.style.visibility = 'hidden !important';
            }
          });

          // Strategy 2: Limit the height of the rendered content to show only media
          var rendered = embed.querySelector('.instagram-media-rendered');
          if (rendered) {
            var children = rendered.children;
            if (children.length > 1) {
              // Hide all children except the first one (usually the media)
              for (var i = 1; i < children.length; i++) {
                children[i].style.display = 'none !important';
              }
            }
            // Also set max-height on rendered content
            rendered.style.maxHeight = '600px !important';
            rendered.style.overflow = 'hidden !important';
          }

          // Strategy 3: Target the specific caption structure in Instagram oEmbed
          // Instagram puts the caption in the last section, usually after media container
          var divs = embed.querySelectorAll('div');
          for (var i = divs.length - 1; i >= 0; i--) {
            var div = divs[i];
            // Check if this div contains substantial non-metadata text
            if (div.children.length < 3 && div.textContent.trim().length > 20) {
              var text = div.textContent.toLowerCase();
              // If it looks like caption text (not just author/date info)
              if (!text.match(/^\s*(@|view|posted|a few|just now|\/)/)) {
                div.style.display = 'none !important';
                div.style.height = '0 !important';
              }
            }
          }
        });
      } catch(e) {
        console.log('Error hiding Instagram captions:', e);
      }
      */
    }

    // Run immediately and after embed loads
    hideInstagramCaptions();
    
    if (window.instgrm) {
      // If already loaded, try immediately and also after processing
      window.instgrm.Embeds.process().then(hideInstagramCaptions);
    } else {
      document.querySelector('script[src*="embed.js"]').addEventListener('load', function() {
        if (window.instgrm) {
          window.instgrm.Embeds.process().then(hideInstagramCaptions);
        }
        // Run hiding after embed.js loads
        setTimeout(hideInstagramCaptions, 500);
      });
    }
    
    // Keep running the hiding function periodically as content loads
    var hideInterval = setInterval(function() {
      hideInstagramCaptions();
    }, 200);
    
    // Stop after 5 seconds to avoid excessive checks
    setTimeout(function() {
      clearInterval(hideInterval);
    }, 5000);
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
        print(
            '✅ INSTAGRAM PREVIEW: Screenshot captured (${screenshot.length} bytes, PNG format)');
      }
      return screenshot;
    } catch (e) {
      print('❌ INSTAGRAM PREVIEW: Screenshot failed: $e');
      return null;
    }
  }

  /// Extract text content from the Instagram WebView
  ///
  /// This is useful as a fallback when oEmbed doesn't return caption data.
  /// For Reels especially, the caption may only be available after JavaScript renders.
  Future<String?> extractPageContent() async {
    if (kIsWeb) {
      print('⚠️ INSTAGRAM PREVIEW: Content extraction not available on web');
      return null;
    }

    if (controller == null) {
      print('⚠️ INSTAGRAM PREVIEW: Controller is null, cannot extract content');
      return null;
    }

    try {
      print('📸 INSTAGRAM PREVIEW: Extracting page content...');

      // Try to extract text from the WebView
      final result = await controller!.evaluateJavascript(source: '''
        (function() {
          // Try to get text from the entire document
          var bodyText = document.body ? document.body.innerText : '';
          
          // Also try to get specific Instagram embed content
          var blockquotes = document.querySelectorAll('blockquote');
          var blockquoteText = '';
          blockquotes.forEach(function(bq) {
            blockquoteText += bq.innerText + ' ';
          });
          
          // Try to get iframe content if accessible
          var iframes = document.querySelectorAll('iframe');
          var iframeText = '';
          iframes.forEach(function(iframe) {
            try {
              if (iframe.contentDocument && iframe.contentDocument.body) {
                iframeText += iframe.contentDocument.body.innerText + ' ';
              }
            } catch(e) {
              // Cross-origin iframe, can't access
            }
          });
          
          // Combine all text sources
          var allText = bodyText + ' ' + blockquoteText + ' ' + iframeText;
          
          // Clean up whitespace
          allText = allText.replace(/\\s+/g, ' ').trim();
          
          return allText;
        })();
      ''');

      if (result != null &&
          result.toString().isNotEmpty &&
          result.toString() != 'null') {
        final content = result.toString().trim();
        print(
            '✅ INSTAGRAM PREVIEW: Extracted content (${content.length} chars)');
        if (content.length > 200) {
          print(
              '📸 INSTAGRAM PREVIEW: Content preview: ${content.substring(0, 200)}...');
        }
        return content;
      } else {
        print('⚠️ INSTAGRAM PREVIEW: No content extracted from WebView');
        return null;
      }
    } catch (e) {
      print('❌ INSTAGRAM PREVIEW: Content extraction failed: $e');
      return null;
    }
  }

  void refresh() {
    if (_forceDirectWebView && !kIsWeb) {
      // For direct WebView, just reload
      controller?.reload();
    } else {
      _initializeOEmbed();
    }
  }

  /// Normalize Instagram URL:
  /// - Convert /reel/ to /p/ format (both point to same content)
  /// - Remove query parameters
  /// - Ensure trailing slash
  /// Clean Instagram URL by removing query parameters
  ///
  /// [convertReelToPost] - If true, converts /reel/ and /tv/ to /p/ format.
  ///   - Use `false` for oEmbed API (Default mode) - API supports /reel/ directly
  ///   - Use `true` for direct WebView (Web View mode) - /p/ format works better
  String _normalizeInstagramUrl(String url, {bool convertReelToPost = false}) {
    try {
      Uri uri = Uri.parse(url);
      String path = uri.path;

      // Optionally convert /reel/ and /tv/ to /p/ format for WebView mode
      if (convertReelToPost) {
        if (path.contains('/reel/')) {
          path = path.replaceFirst('/reel/', '/p/');
        }
        if (path.contains('/tv/')) {
          path = path.replaceFirst('/tv/', '/p/');
        }
      }

      String cleanUrl = '${uri.scheme}://${uri.host}$path';
      if (!cleanUrl.endsWith('/')) {
        cleanUrl = '$cleanUrl/';
      }
      return cleanUrl;
    } catch (e) {
      // Fallback: simple string manipulation - just remove query params
      if (url.contains('?')) {
        url = url.split('?')[0];
      }
      if (convertReelToPost) {
        url = url.replaceFirst('/reel/', '/p/');
        url = url.replaceFirst('/tv/', '/p/');
      }
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
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: Colors.grey[600], size: 48),
                const SizedBox(height: 16),
                _buildErrorMessage(),
                const SizedBox(height: 24),
                Builder(builder: (ctx) {
                  return OutlinedButton.icon(
                    onPressed: () {
                      if (_helpTap(
                          ReceiveShareHelpTargetId.previewDisplayModeToggle,
                          ctx)) {
                        return;
                      }
                      _switchToWebViewMode();
                    },
                    icon: const Icon(Icons.web),
                    label: const Text('Switch to Web View'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE1306C),
                      side: const BorderSide(color: Color(0xFFE1306C)),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                Builder(
                    builder: (ctx) => ElevatedButton.icon(
                          onPressed: () {
                            if (_helpTap(
                                ReceiveShareHelpTargetId
                                    .previewOpenExternalButton,
                                ctx)) return;
                            widget.launchUrlCallback(widget.url);
                          },
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open in Instagram'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE1306C),
                            foregroundColor: Colors.white,
                          ),
                        )),
              ],
            ),
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

    // Show error state if oEmbed failed
    if (_errorMessage != null && _useOEmbed) {
      return Container(
        height: containerHeight,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: Colors.grey[600], size: 48),
                const SizedBox(height: 16),
                _buildErrorMessage(),
                const SizedBox(height: 24),
                Builder(builder: (ctx) {
                  return OutlinedButton.icon(
                    onPressed: () {
                      if (_helpTap(
                          ReceiveShareHelpTargetId.previewDisplayModeToggle,
                          ctx)) {
                        return;
                      }
                      _switchToWebViewMode();
                    },
                    icon: const Icon(Icons.web),
                    label: const Text('Switch to Web View'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE1306C),
                      side: const BorderSide(color: Color(0xFFE1306C)),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                Builder(
                    builder: (ctx) => ElevatedButton.icon(
                          onPressed: () {
                            if (_helpTap(
                                ReceiveShareHelpTargetId
                                    .previewOpenExternalButton,
                                ctx)) return;
                            widget.launchUrlCallback(widget.url);
                          },
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open in Instagram'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE1306C),
                            foregroundColor: Colors.white,
                          ),
                        )),
              ],
            ),
          ),
        ),
      );
    }

    // If using oEmbed mode but HTML hasn't loaded yet, show loading indicator
    // This prevents creating a WebView with the wrong initialUrlRequest
    if (_useOEmbed && _oembedHtml == null) {
      return Container(
        height: containerHeight,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
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

    // If using oEmbed and we have HTML, load it in WebView
    final bool loadOEmbedHtml = _useOEmbed && _oembedHtml != null;

    // Create a unique key based on the display mode to force WebView recreation
    final webViewKey = ValueKey(
        'ig_${widget.url}_${loadOEmbedHtml ? 'oembed' : 'direct'}_${_oembedHtml?.hashCode ?? 0}');

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
            key: webViewKey,
            // For direct WebView mode: convert /reel/ to /p/ for better compatibility
            initialUrlRequest: loadOEmbedHtml
                ? null
                : URLRequest(
                    url: WebUri(_normalizeInstagramUrl(widget.url,
                        convertReelToPost: true))),
            initialData: loadOEmbedHtml
                ? InAppWebViewInitialData(
                    data: _oembedHtml!,
                    mimeType: 'text/html',
                    encoding: 'utf-8',
                    baseUrl: WebUri('https://www.instagram.com/'),
                  )
                : null,
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              iframeAllowFullscreen: false,
              transparentBackground: true,
              userAgent:
                  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
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

              // Measure content height after a delay (to allow Instagram embed.js to render)
              Future.delayed(const Duration(milliseconds: 1500), () async {
                if (!mounted || _isDisposed || controller == null) return;

                try {
                  // Get the actual content height from the document
                  final heightResult =
                      await controller!.evaluateJavascript(source: '''
                    (function() {
                      // Try to get Instagram embed height first
                      var instagramEmbed = document.querySelector('.instagram-media-rendered');
                      if (instagramEmbed) {
                        return instagramEmbed.scrollHeight;
                      }
                      // Fall back to body scroll height
                      return Math.max(
                        document.body.scrollHeight,
                        document.documentElement.scrollHeight
                      );
                    })();
                  ''');

                  if (heightResult != null && mounted && !_isDisposed) {
                    final height = double.tryParse(heightResult.toString());
                    if (height != null && height > 0) {
                      // Add some padding for safety
                      widget.onContentHeightChanged?.call(height + 50);
                    }
                  }
                } catch (e) {
                  print('⚠️ INSTAGRAM: Failed to measure content height: $e');
                }
              });

              // Set loading to false after a short delay
              final currentLoadingOperationId = ++_loadingDelayOperationId;

              Future.delayed(const Duration(milliseconds: 500), () {
                if (!mounted ||
                    _isDisposed ||
                    _loadingDelayOperationId != currentLoadingOperationId)
                  return;

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
