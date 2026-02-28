import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:typed_data';
import 'package:plendy/models/receive_share_help_target.dart';

class YouTubePreviewWidget extends StatefulWidget {
  final String url;
  final Future<void> Function(String) launchUrlCallback;
  final bool showControls;
  final Function(InAppWebViewController)? onWebViewCreated;
  final double? height;
  final bool isHelpMode;
  final bool Function(ReceiveShareHelpTargetId id, BuildContext ctx)? onHelpTap;

  const YouTubePreviewWidget({
    super.key,
    required this.url,
    required this.launchUrlCallback,
    this.showControls = true,
    this.onWebViewCreated,
    this.height,
    this.isHelpMode = false,
    this.onHelpTap,
  });

  @override
  YouTubePreviewWidgetState createState() => YouTubePreviewWidgetState();
}

class YouTubePreviewWidgetState extends State<YouTubePreviewWidget> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  bool _isDisposed = false;
  bool _isShort = false;

  bool _helpTap(ReceiveShareHelpTargetId id, BuildContext ctx) {
    if (widget.onHelpTap != null) return widget.onHelpTap!(id, ctx);
    return false;
  }

  @override
  void initState() {
    super.initState();
    _isShort = widget.url.contains('/shorts/');
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
      print('⚠️ YOUTUBE PREVIEW: Controller is null, cannot take screenshot');
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
        print('✅ YOUTUBE PREVIEW: Screenshot captured (${screenshot.length} bytes, PNG format)');
      }
      return screenshot;
    } catch (e) {
      print('❌ YOUTUBE PREVIEW: Screenshot failed: $e');
      return null;
    }
  }

  /// Get the mobile-friendly YouTube URL
  String _getMobileUrl() {
    // Convert to mobile YouTube URL for better WebView compatibility
    String url = widget.url;
    
    // Ensure we're using m.youtube.com for mobile-friendly viewing
    if (url.contains('youtube.com') && !url.contains('m.youtube.com')) {
      url = url.replaceFirst('youtube.com', 'm.youtube.com');
      url = url.replaceFirst('www.', '');
    } else if (url.contains('youtu.be')) {
      // Convert youtu.be short URLs to m.youtube.com
      final uri = Uri.parse(url);
      if (uri.pathSegments.isNotEmpty) {
        final videoId = uri.pathSegments[0];
        url = 'https://m.youtube.com/watch?v=$videoId';
      }
    }
    
    return url;
  }

  void refreshWebView() {
    if (_controller != null && mounted && !_isDisposed) {
      setState(() {
        _isLoading = true;
      });
      _controller!.loadUrl(urlRequest: URLRequest(url: WebUri(_getMobileUrl())));
    }
  }

  Future<void> _launchYouTubeUrl() async {
    final Uri uri = Uri.parse(widget.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open YouTube link')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double containerHeight = widget.height ?? (_isShort ? 600.0 : 350.0);
    
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              height: containerHeight,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.hardEdge,
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(_getMobileUrl())),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  iframeAllowFullscreen: true,
                  transparentBackground: true,
                  useShouldOverrideUrlLoading: true,
                  // Use a desktop Chrome user agent - YouTube mobile site works better with this
                  userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  // Allow mixed content for YouTube resources
                  mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                  // Enable DOM storage for YouTube player state
                  domStorageEnabled: true,
                  // Allow file access for media playback
                  allowFileAccess: true,
                  allowContentAccess: true,
                  // Support zoom for better UX
                  supportZoom: false,
                  // Disable text zoom to maintain layout
                  textZoom: 100,
                ),
                onWebViewCreated: (controller) {
                  _controller = controller;
                  widget.onWebViewCreated?.call(controller);
                },
                onLoadStart: (controller, url) {
                  if (!mounted || _isDisposed) return;
                  setState(() {
                    _isLoading = true;
                  });
                },
                onLoadStop: (controller, url) {
                  if (!mounted || _isDisposed) return;
                  setState(() {
                    _isLoading = false;
                  });
                },
                onReceivedError: (controller, request, error) {
                  print('⚠️ YOUTUBE PREVIEW: WebView error: ${error.description}');
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  final url = navigationAction.request.url?.toString() ?? '';
                  
                  // Allow YouTube-related URLs
                  if (url.contains('youtube.com') || 
                      url.contains('youtu.be') ||
                      url.contains('googlevideo.com') ||
                      url.contains('ytimg.com') ||
                      url.contains('ggpht.com') ||
                      url.contains('googleusercontent.com') ||
                      url.contains('gstatic.com') ||
                      url.contains('google.com')) {
                    return NavigationActionPolicy.ALLOW;
                  }
                  
                  // External URLs - launch externally
                  if (mounted && !_isDisposed) {
                    widget.launchUrlCallback(url);
                  }
                  return NavigationActionPolicy.CANCEL;
                },
              ),
            ),
            if (_isLoading)
              Container(
                height: containerHeight,
                width: double.infinity,
                color: Colors.black.withOpacity(0.7),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Loading YouTube ${_isShort ? "Short" : "video"}...',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
          ],
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
                  icon: const FaIcon(FontAwesomeIcons.youtube),
                  color: Colors.red,
                  iconSize: 32,
                  tooltip: 'Open in YouTube',
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    if (_helpTap(ReceiveShareHelpTargetId.previewOpenExternalButton, ctx)) return;
                    _launchYouTubeUrl();
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
