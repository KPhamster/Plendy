import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

class YouTubePreviewWidget extends StatefulWidget {
  final String url;
  final Future<void> Function(String) launchUrlCallback;
  final bool showControls;
  final Function(WebViewController)? onWebViewCreated;
  final double? height; // Optional height, will auto-calculate based on video type

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
  late WebViewController _controller;
  bool _isLoading = true;
  bool _isDisposed = false;
  String? _videoId;
  bool _isShort = false;
  String? _currentEmbedHtml;

  @override
  void initState() {
    super.initState();
    _extractVideoInfo();
    _initializeWebView();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  void _extractVideoInfo() {
    // Extract video ID and determine if it's a Short
    final uri = Uri.parse(widget.url);
    
    // Check if it's a YouTube Short
    _isShort = widget.url.contains('/shorts/');
    
    // Extract video ID from various YouTube URL formats
    if (_isShort) {
      // Format: https://youtube.com/shorts/VIDEO_ID
      final pathSegments = uri.pathSegments;
      if (pathSegments.length >= 2 && pathSegments[0] == 'shorts') {
        _videoId = pathSegments[1];
      }
    } else if (uri.host.contains('youtu.be')) {
      // Format: https://youtu.be/VIDEO_ID
      _videoId = uri.pathSegments.isNotEmpty ? uri.pathSegments[0] : null;
    } else if (uri.host.contains('youtube.com')) {
      // Format: https://www.youtube.com/watch?v=VIDEO_ID
      _videoId = uri.queryParameters['v'];
      
      // Also check for embed format: https://www.youtube.com/embed/VIDEO_ID
      if (_videoId == null && uri.pathSegments.contains('embed')) {
        final embedIndex = uri.pathSegments.indexOf('embed');
        if (embedIndex < uri.pathSegments.length - 1) {
          _videoId = uri.pathSegments[embedIndex + 1];
        }
      }
    }
    
    // Remove any query parameters from video ID
    if (_videoId != null && _videoId!.contains('?')) {
      _videoId = _videoId!.split('?')[0];
    }
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {},
          onPageStarted: (String url) {
            if (!mounted || _isDisposed) return;
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            if (!mounted || _isDisposed) return;
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            print("YouTube WebView Error: ${error.description}");
            if (!mounted || _isDisposed) return;
            setState(() {
              _isLoading = false;
            });
          },
          onNavigationRequest: (NavigationRequest request) {
            // Allow YouTube navigation
            if (request.url.contains('youtube.com') || 
                request.url.contains('youtu.be') ||
                request.url.contains('googlevideo.com') ||
                request.url.contains('ytimg.com')) {
              return NavigationDecision.navigate;
            }
            
            // Open external links
            if (mounted && !_isDisposed) {
              widget.launchUrlCallback(request.url);
            }
            return NavigationDecision.prevent;
          },
        ),
      );

    if (widget.onWebViewCreated != null) {
      widget.onWebViewCreated!(_controller);
    }

    _loadYouTubeEmbed();
  }

  void _loadYouTubeEmbed() {
    if (_videoId == null) {
      _loadErrorHtml();
      return;
    }

    _currentEmbedHtml = _generateYouTubeEmbedHtml(_videoId!);
    _controller.loadHtmlString(_currentEmbedHtml!);
  }

  void refreshWebView() {
    if (_currentEmbedHtml != null && mounted && !_isDisposed) {
      setState(() {
        _isLoading = true;
      });
      _controller.loadHtmlString(_currentEmbedHtml!);
    } else {
      _loadYouTubeEmbed();
    }
  }

  String _generateYouTubeEmbedHtml(String videoId) {
    // Calculate aspect ratio based on video type
    // Shorts use 9:16 (56.25%), regular videos use 16:9 (177.78%)
    final aspectRatio = _isShort ? '177.78%' : '56.25%';
    
    return '''
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
    .error-container {
      display: flex;
      justify-content: center;
      align-items: center;
      height: 100vh;
      color: white;
      text-align: center;
      font-family: Arial, sans-serif;
    }
  </style>
</head>
<body>
  <div class="video-container">
    <iframe
      id="youtube-player"
      src="https://www.youtube.com/embed/$videoId?enablejsapi=1&modestbranding=1&rel=0&showinfo=0&fs=1&playsinline=1"
      allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
      allowfullscreen>
    </iframe>
  </div>
  
  <script>
    // Optional: Add YouTube IFrame API for more control
    var tag = document.createElement('script');
    tag.src = "https://www.youtube.com/iframe_api";
    var firstScriptTag = document.getElementsByTagName('script')[0];
    firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);
    
    var player;
    function onYouTubeIframeAPIReady() {
      player = new YT.Player('youtube-player', {
        events: {
          'onReady': onPlayerReady,
          'onError': onPlayerError
        }
      });
    }
    
    function onPlayerReady(event) {
      console.log('YouTube player ready');
    }
    
    function onPlayerError(event) {
      console.error('YouTube player error:', event.data);
    }
  </script>
</body>
</html>
    ''';
  }

  void _loadErrorHtml() {
    final errorHtml = '''
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
      box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    }
    .error-icon {
      font-size: 48px;
      color: #ff0000;
      margin-bottom: 20px;
    }
    .error-message {
      color: #333;
      margin-bottom: 10px;
    }
    .error-url {
      color: #666;
      font-size: 14px;
      word-break: break-all;
    }
  </style>
</head>
<body>
  <div class="error-container">
    <div class="error-icon">⚠️</div>
    <div class="error-message">Unable to load YouTube video</div>
    <div class="error-url">${widget.url}</div>
  </div>
</body>
</html>
    ''';
    
    _controller.loadHtmlString(errorHtml);
  }

  Future<void> _launchYouTubeUrl() async {
    final Uri uri = Uri.parse(widget.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open YouTube link')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate height based on video type if not provided
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: WebViewWidget(controller: _controller),
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
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Loading YouTube ${_isShort ? "Short" : "video"}...',
                        style: TextStyle(color: Colors.white),
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
                const SizedBox(width: 48), // Spacer for alignment
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
