import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:plendy/models/receive_share_help_target.dart';

/// Data extracted from TikTok oEmbed API
class TikTokOEmbedData {
  final String? title;       // Video caption/description
  final String? authorName;  // Creator's display name
  final String? authorUrl;   // Creator's profile URL
  final String? thumbnailUrl; // Video thumbnail
  final String type;         // "video" or "photo"
  
  TikTokOEmbedData({
    this.title,
    this.authorName,
    this.authorUrl,
    this.thumbnailUrl,
    required this.type,
  });
  
  /// Check if there's useful content for location extraction
  bool get hasContent => (title != null && title!.isNotEmpty) || 
                         (authorName != null && authorName!.isNotEmpty);
  
  @override
  String toString() => 'TikTokOEmbedData(title: ${title?.substring(0, (title?.length ?? 0) > 50 ? 50 : title?.length)}..., author: $authorName, type: $type)';
}

class TikTokPreviewWidget extends StatefulWidget {
  final String url;
  final Future<void> Function(String) launchUrlCallback;
  final void Function(bool, String)? onExpansionChanged;
  final void Function(String url, bool isPhotoCarousel)? onPhotoDetected;
  /// Callback when oEmbed data (caption, author, etc.) is loaded
  final void Function(TikTokOEmbedData data)? onOEmbedDataLoaded;
  final bool showControls;
  final Function(InAppWebViewController)? onWebViewCreated;
  final bool isDiscoveryMode;
  final bool isHelpMode;
  final bool Function(ReceiveShareHelpTargetId id, BuildContext ctx)? onHelpTap;

  const TikTokPreviewWidget({
    super.key,
    required this.url,
    required this.launchUrlCallback,
    this.onExpansionChanged,
    this.onPhotoDetected,
    this.onOEmbedDataLoaded,
    this.showControls = true,
    this.onWebViewCreated,
    this.isDiscoveryMode = false,
    this.isHelpMode = false,
    this.onHelpTap,
  });

  @override
  State<TikTokPreviewWidget> createState() => TikTokPreviewWidgetState();
}

class TikTokPreviewWidgetState extends State<TikTokPreviewWidget> with AutomaticKeepAliveClientMixin {
  bool _isDisposed = false;
  InAppWebViewController? _controller;
  bool _isLoading = true;
  String? _errorMessage;
  String? _currentEmbedHtml;
  bool _isPhotoCarousel = false;
  String? _postId;

  @override
  bool get wantKeepAlive => true;

  bool _helpTap(ReceiveShareHelpTargetId id, BuildContext ctx) {
    if (widget.onHelpTap != null) return widget.onHelpTap!(id, ctx);
    return false;
  }

  @override
  void initState() {
    super.initState();
    _initializeEmbed();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  /// Extract the TikTok post ID from various URL formats
  String? _extractPostId(String url) {
    // Pattern for standard TikTok URLs: /@username/video/ID or /@username/photo/ID
    final videoPattern = RegExp(r'/(?:video|photo)/(\d+)');
    final videoMatch = videoPattern.firstMatch(url);
    if (videoMatch != null) {
      return videoMatch.group(1);
    }
    
    // Pattern for /v/ URLs: tiktok.com/v/ID
    final vPattern = RegExp(r'/v/(\d+)');
    final vMatch = vPattern.firstMatch(url);
    if (vMatch != null) {
      return vMatch.group(1);
    }
    
    return null;
  }

  /// Take a screenshot of the current WebView content
  /// Uses PNG format for best quality OCR/text detection
  Future<Uint8List?> takeScreenshot() async {
    if (_controller == null) {
      print('⚠️ TIKTOK PREVIEW: Controller is null, cannot take screenshot');
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
        print('✅ TIKTOK PREVIEW: Screenshot captured (${screenshot.length} bytes, PNG format)');
      }
      return screenshot;
    } catch (e) {
      print('❌ TIKTOK PREVIEW: Screenshot failed: $e');
      return null;
    }
  }

  Future<void> _initializeEmbed() async {
    // First, try to extract post ID from URL
    _postId = _extractPostId(widget.url);
    
    if (_postId == null) {
      // For short URLs (vm.tiktok.com), we need to resolve them first
      print('TikTok Embed Player: Could not extract post ID from ${widget.url}, trying to resolve...');
      await _resolveShortUrl();
    }
    
    if (_postId != null) {
      // Fetch oEmbed data for metadata (title, author, etc.)
      await _fetchOEmbedMetadata();
      // Load the embed player
      _loadEmbedPlayer();
    } else {
      print('TikTok Embed Player: Failed to get post ID');
      setState(() {
        _errorMessage = 'Could not load TikTok content';
      });
      _loadFallbackHtml();
    }
  }

  /// Resolve short URLs (vm.tiktok.com) to get the full URL with post ID
  Future<void> _resolveShortUrl() async {
    try {
      // Make a HEAD request to follow redirects and get the final URL
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(widget.url))
        ..followRedirects = false;
      
      final response = await client.send(request);
      
      if (response.statusCode == 301 || response.statusCode == 302) {
        final redirectUrl = response.headers['location'];
        if (redirectUrl != null) {
          print('TikTok Embed Player: Resolved to $redirectUrl');
          _postId = _extractPostId(redirectUrl);
        }
      }
      client.close();
    } catch (e) {
      print('TikTok Embed Player: Error resolving short URL: $e');
    }
  }

  /// Fetch metadata from oEmbed API (for title, author, type info)
  Future<void> _fetchOEmbedMetadata() async {
    try {
      final Uri oembedUrl = Uri.parse('https://www.tiktok.com/oembed?url=${Uri.encodeComponent(widget.url)}');
      
      print('TikTok Embed Player: Fetching metadata for ${widget.url}');
      
      final response = await http.get(oembedUrl);
      
      if (!mounted || _isDisposed) return;
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Check the type field to determine if it's a photo carousel
        final bool isPhotoPost = data['type'] == 'photo';
        
        print('🎬 TIKTOK TYPE: ${data['type']}');
        print('🎬 IS PHOTO CAROUSEL: $isPhotoPost');
        
        // Extract and pass oEmbed data for location extraction
        final oembedData = TikTokOEmbedData(
          title: data['title'] as String?,
          authorName: data['author_name'] as String?,
          authorUrl: data['author_url'] as String?,
          thumbnailUrl: data['thumbnail_url'] as String?,
          type: data['type'] as String? ?? 'video',
        );
        
        print('🎬 TIKTOK CAPTION: ${oembedData.title?.substring(0, (oembedData.title?.length ?? 0) > 100 ? 100 : oembedData.title?.length)}...');
        print('🎬 TIKTOK AUTHOR: ${oembedData.authorName}');
        
        // Notify listener about oEmbed data (for automatic location extraction)
        widget.onOEmbedDataLoaded?.call(oembedData);
        
        if (mounted) {
          setState(() {
            _isPhotoCarousel = isPhotoPost;
          });
        }
        
        widget.onPhotoDetected?.call(widget.url, isPhotoPost);
      }
    } catch (e) {
      print('TikTok Embed Player: Error fetching metadata: $e');
      // Continue anyway - we can still show the player without metadata
    }
  }

  /// Load the TikTok Embed Player using direct iframe
  void _loadEmbedPlayer() {
    if (_postId == null) {
      _loadFallbackHtml();
      return;
    }
    
    // Build the embed player URL with customization parameters
    // See: https://developers.tiktok.com/doc/embed-player
    
    // Default settings (for normal preview mode)
    // - Show most controls for usability
    // - Autoplay enabled (since user explicitly tapped)
    String settings = '?music_info=0'
        '&description=1'
        //'&controls=1'
        '&progress_bar=1'
        '&timestamp=1'
        '&play_button=1'
        '&volume_control=1'
        '&fullscreen_button=1'
        '&loop=0'
        '&autoplay=1'
        '&native_context_menu=0'
        '&rel=0';
        
    // Discovery mode settings (cleaner look, like a feed)
    if (widget.isDiscoveryMode) {
      settings = '?music_info=0'      // Show music info
        '&description=0'     // Show video description
        //'&controls=0'        // Hide all control buttons
        '&progress_bar=0'    // Hide progress bar
        '&timestamp=0'       // Show timestamp
        '&play_button=0'     // Hide play button
        '&volume_control=1'  // Hide volume control
        '&fullscreen_button=1' // Hide fullscreen button
        '&loop=1'            // Loop for discovery feed experience
        '&autoplay=1'       // Autoplay
        '&native_context_menu=0'
        '&rel=0';
    }

    final playerUrl = 'https://www.tiktok.com/player/v1/$_postId$settings';
    
    print('🎬 TIKTOK EMBED PLAYER: Loading $playerUrl');

    // In discovery mode, use 100% height to fill the screen. Otherwise use fixed height.
    final String cssHeight = widget.isDiscoveryMode ? '100%' : '100%';

    final embedHtml = '''
<!DOCTYPE html>
<html style="height: $cssHeight; margin: 0; padding: 0;">
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    html, body {
      margin: 0 !important;
      padding: 0 !important;
      background: #000 !important;
      height: $cssHeight !important;
      min-height: $cssHeight !important;
      max-height: $cssHeight !important;
      overflow: hidden;
    }
    body {
      display: flex;
      justify-content: center;
      align-items: center;
    }
    .player-container {
      width: 100%;
      height: 100%;
      display: flex;
      justify-content: center;
      align-items: center;
    }
    iframe {
      width: 100%;
      height: $cssHeight;
      border: none;
      max-width: 400px;
    }
  </style>
</head>
<body>
  <div class="player-container">
    <iframe 
      src="$playerUrl"
      allow="fullscreen"
      allowfullscreen
      referrerpolicy="no-referrer-when-downgrade"
    ></iframe>
  </div>
</body>
</html>
''';
    
    setState(() {
      _currentEmbedHtml = embedHtml;
    });
  }

  void _loadFallbackHtml() {
    final fallbackHtml = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    body {
      margin: 0;
      padding: 0;
      background: #000;
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
    }
    .fallback-container {
      text-align: center;
      padding: 20px;
      color: white;
      width: 100%;
    }
    .open-button {
      background: #FE2C55;
      color: white;
      border: none;
      padding: 12px 24px;
      border-radius: 4px;
      font-size: 16px;
      font-weight: 600;
      cursor: pointer;
      margin-top: 20px;
    }
  </style>
</head>
<body>
  <div class="fallback-container">
    <h2 style="color: white;">TikTok Content</h2>
    <p style="color: #ccc;">${_errorMessage ?? 'Unable to load preview'}</p>
    <button class="open-button" onclick="window.flutter_inappwebview.callHandler('openTikTok');">
      Open in TikTok
    </button>
  </div>
</body>
</html>
''';
    
    setState(() {
      _currentEmbedHtml = fallbackHtml;
    });
  }
  
  void refreshWebView() {
    if (_controller != null && _currentEmbedHtml != null) {
      setState(() {
        _isLoading = true;
      });
      _controller!.loadData(data: _currentEmbedHtml!, baseUrl: WebUri('https://www.tiktok.com'));
    } else {
      _initializeEmbed();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final double height = _isPhotoCarousel ? 500.0 : 700.0;
    print('🎬 TIKTOK BUILD: Photo=$_isPhotoCarousel, Height=${height}px');

    Widget webViewContent = Container(
      color: Colors.black,
      child: Stack(
        children: [
          if (_currentEmbedHtml != null)
            InAppWebView(
              initialData: InAppWebViewInitialData(
                data: _currentEmbedHtml!,
                baseUrl: WebUri('https://www.tiktok.com'),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                iframeAllowFullscreen: true,
                transparentBackground: true,
              ),
              onWebViewCreated: (controller) {
                _controller = controller;
                controller.addJavaScriptHandler(
                  handlerName: 'openTikTok',
                  callback: (args) {
                    widget.launchUrlCallback(widget.url);
                  },
                );
                widget.onWebViewCreated?.call(controller);
              },
              onLoadStart: (controller, url) {
                if (!_isDisposed && mounted) {
                  setState(() {
                    _isLoading = true;
                  });
                }
              },
              onLoadStop: (controller, url) {
                if (!_isDisposed && mounted) {
                  setState(() {
                    _isLoading = false;
                  });
                }
              },
            ),
          if (_isLoading)
            Container(
              color: Colors.black,
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFE2C55)),
                ),
              ),
            ),
        ],
      ),
    );

    if (widget.isDiscoveryMode) {
      return SizedBox.expand(
        child: webViewContent,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: webViewContent,
        ),
        if (widget.showControls)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 48),
                Builder(builder: (ctx) => IconButton(
                  icon: const FaIcon(FontAwesomeIcons.tiktok),
                  color: Colors.black,
                  iconSize: 32,
                  tooltip: 'Open in TikTok',
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    if (_helpTap(ReceiveShareHelpTargetId.previewOpenExternalButton, ctx)) return;
                    widget.launchUrlCallback(widget.url);
                  },
                )),
                Builder(builder: (ctx) => IconButton(
                  icon: const Icon(Icons.refresh),
                  iconSize: 24,
                  color: Colors.blue,
                  tooltip: 'Refresh',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onPressed: () {
                    if (_helpTap(ReceiveShareHelpTargetId.previewRefreshButton, ctx)) return;
                    refreshWebView();
                  },
                )),
              ],
            ),
          ),
      ],
    );
  }
}
