import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:typed_data';

class YouTubePreviewWidget extends StatefulWidget {
  final String url;
  final Future<void> Function(String) launchUrlCallback;
  final bool showControls;
  final Function(InAppWebViewController)? onWebViewCreated;
  final double? height;

  const YouTubePreviewWidget({
    super.key,
    required this.url,
    required this.launchUrlCallback,
    this.showControls = true,
    this.onWebViewCreated,
    this.height,
  });

  @override
  YouTubePreviewWidgetState createState() => YouTubePreviewWidgetState();
}

class YouTubePreviewWidgetState extends State<YouTubePreviewWidget> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  bool _isDisposed = false;
  String? _videoId;
  bool _isShort = false;
  String? _currentEmbedHtml;

  @override
  void initState() {
    super.initState();
    _extractVideoInfo();
    _generateEmbedHtml();
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

  void _extractVideoInfo() {
    final uri = Uri.parse(widget.url);
    
    _isShort = widget.url.contains('/shorts/');
    
    if (_isShort) {
      final pathSegments = uri.pathSegments;
      if (pathSegments.length >= 2 && pathSegments[0] == 'shorts') {
        _videoId = pathSegments[1];
      }
    } else if (uri.host.contains('youtu.be')) {
      _videoId = uri.pathSegments.isNotEmpty ? uri.pathSegments[0] : null;
    } else if (uri.host.contains('youtube.com')) {
      _videoId = uri.queryParameters['v'];
      
      if (_videoId == null && uri.pathSegments.contains('embed')) {
        final embedIndex = uri.pathSegments.indexOf('embed');
        if (embedIndex < uri.pathSegments.length - 1) {
          _videoId = uri.pathSegments[embedIndex + 1];
        }
      }
    }
    
    if (_videoId != null && _videoId!.contains('?')) {
      _videoId = _videoId!.split('?')[0];
    }
  }

  void _generateEmbedHtml() {
    if (_videoId == null) {
      _currentEmbedHtml = _generateErrorHtml();
      return;
    }

    final aspectRatio = _isShort ? '177.78%' : '56.25%';
    
    _currentEmbedHtml = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    body {
      margin: 0;
      padding: 0;
      background-color: #000;
      overflow: hidden;
    }
    .video-container {
      position: relative;
      width: 100%;
      padding-bottom: $aspectRatio;
      height: 0;
      overflow: hidden;
    }
    .video-container iframe {
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      border: 0;
    }
  </style>
</head>
<body>
  <div class="video-container">
    <iframe
      id="youtube-player"
      src="https://www.youtube.com/embed/$_videoId?enablejsapi=1&modestbranding=1&rel=0&showinfo=0&fs=0&playsinline=1"
      allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
      playsinline>
    </iframe>
  </div>
</body>
</html>
    ''';
  }

  String _generateErrorHtml() {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body {
      margin: 0;
      padding: 20px;
      font-family: Arial, sans-serif;
      background-color: #f0f0f0;
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 200px;
    }
    .error-container {
      text-align: center;
      background: white;
      padding: 30px;
      border-radius: 10px;
    }
    .error-icon {
      font-size: 48px;
      color: #ff0000;
      margin-bottom: 20px;
    }
  </style>
</head>
<body>
  <div class="error-container">
    <div class="error-icon">⚠️</div>
    <div>Unable to load YouTube video</div>
    <div style="color: #666; font-size: 14px;">${widget.url}</div>
  </div>
</body>
</html>
    ''';
  }

  void refreshWebView() {
    if (_controller != null && _currentEmbedHtml != null && mounted && !_isDisposed) {
      setState(() {
        _isLoading = true;
      });
      _controller!.loadData(data: _currentEmbedHtml!, baseUrl: WebUri('https://www.youtube.com'));
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
    final double containerHeight = widget.height ?? (_isShort ? 600.0 : 220.0);
    
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
              child: _currentEmbedHtml != null
                  ? InAppWebView(
                      initialData: InAppWebViewInitialData(
                        data: _currentEmbedHtml!,
                        baseUrl: WebUri('https://www.youtube.com'),
                      ),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        mediaPlaybackRequiresUserGesture: false,
                        allowsInlineMediaPlayback: true,
                        iframeAllowFullscreen: false,
                        transparentBackground: true,
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
                      shouldOverrideUrlLoading: (controller, navigationAction) async {
                        final url = navigationAction.request.url?.toString() ?? '';
                        if (url.contains('youtube.com') || 
                            url.contains('youtu.be') ||
                            url.contains('googlevideo.com') ||
                            url.contains('ytimg.com')) {
                          return NavigationActionPolicy.ALLOW;
                        }
                        if (mounted && !_isDisposed) {
                          widget.launchUrlCallback(url);
                        }
                        return NavigationActionPolicy.CANCEL;
                      },
                    )
                  : const SizedBox(),
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
                IconButton(
                  icon: const FaIcon(FontAwesomeIcons.youtube),
                  color: Colors.red,
                  iconSize: 32,
                  tooltip: 'Open in YouTube',
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  onPressed: _launchYouTubeUrl,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  iconSize: 24,
                  color: Colors.blue,
                  tooltip: 'Refresh',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onPressed: refreshWebView,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
