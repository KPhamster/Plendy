import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
import 'dart:convert';

class TikTokPreviewWidget extends StatefulWidget {
  final String url;
  final Future<void> Function(String) launchUrlCallback;
  final void Function(bool, String)? onExpansionChanged;
  final void Function(String url, bool isPhotoCarousel)? onPhotoDetected;

  const TikTokPreviewWidget({
    super.key,
    required this.url,
    required this.launchUrlCallback,
    this.onExpansionChanged,
    this.onPhotoDetected,
  });

  @override
  State<TikTokPreviewWidget> createState() => _TikTokPreviewWidgetState();
}

class _TikTokPreviewWidgetState extends State<TikTokPreviewWidget> {
  bool _isDisposed = false;
  late WebViewController _controller;
  bool _isLoading = true;
  String? _errorMessage;
  String? _currentEmbedHtml;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
    _fetchTikTokEmbed();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  Future<void> _fetchTikTokEmbed() async {
    try {
      // Use TikTok's oEmbed API to get the proper embed code
      final Uri oembedUrl = Uri.parse('https://www.tiktok.com/oembed?url=${Uri.encodeComponent(widget.url)}');
      
      print('TikTok oEmbed: Fetching embed for ${widget.url}');
      
      final response = await http.get(oembedUrl);
      
      if (!mounted || _isDisposed) return;
      
      print('TikTok oEmbed: Response status ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        print('TikTok oEmbed: Response data keys: ${data.keys.toList()}');
        
        if (data['html'] != null) {
          print('TikTok oEmbed: Successfully retrieved embed HTML');
          print('TikTok oEmbed: Type: ${data['type'] ?? 'unknown'}');
          
          // Check if this is a photo post
          final bool isPhotoPost = data['type'] == 'photo' || 
                                   (data['title'] != null && data['title'].toString().contains('photo')) ||
                                   (data['author_name'] != null && data['html'].toString().contains('photo'));
          
          if (isPhotoPost) {
            print('TikTok oEmbed: Detected photo carousel post');
            widget.onPhotoDetected?.call(widget.url, true);
          } else {
            // It's a video post
            widget.onPhotoDetected?.call(widget.url, false);
          }
          
          // Wrap the embed HTML in our custom container
          final embedHtml = '''
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
      overflow-x: hidden;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    }
    .embed-container {
      width: 100% !important;
      max-width: 100% !important;
      display: flex;
      justify-content: center;
      align-items: center;
    }
    /* Override TikTok's default styles */
    blockquote.tiktok-embed {
      margin: 0 !important;
      max-width: 100% !important;
      min-width: unset !important;
    }
    /* Ensure photo carousels display properly */
    .tiktok-embed iframe {
      min-height: 700px !important;
    }
  </style>
</head>
<body>
  <div class="embed-container">
    ${data['html']}
  </div>
  <script>
    // Add error handling for embed loading
    window.addEventListener('message', function(e) {
      if (e.data && typeof e.data === 'string') {
        console.log('TikTok embed message:', e.data);
      }
    });
  </script>
</body>
</html>
''';
          
          setState(() {
            _currentEmbedHtml = embedHtml;
          });
          
          _loadEmbedHtml(embedHtml);
        } else {
          print('TikTok oEmbed: No HTML in response. Full response: ${response.body}');
          
          // Check if we have other useful data in the response
          if (data['error'] != null) {
            throw Exception('TikTok API error: ${data['error']}');
          } else {
            throw Exception('No embed HTML in response');
          }
        }
      } else {
        // Log the response body for debugging
        print('TikTok oEmbed: Failed with status ${response.statusCode}');
        print('TikTok oEmbed: Response body: ${response.body}');
        
        if (response.statusCode == 404) {
          throw Exception('TikTok post not found or not embeddable');
        } else if (response.statusCode == 403) {
          throw Exception('TikTok post is private or restricted');
        } else if (response.statusCode == 400) {
          // 400 error often indicates unsupported content type (like photo carousels)
          print('TikTok oEmbed: 400 error - attempting direct embed approach');
          widget.onPhotoDetected?.call(widget.url, true);
          _loadDirectEmbed();
          return;
        } else {
          throw Exception('Failed to fetch embed: ${response.statusCode}');
        }
      }
    } catch (e) {
      print('TikTok oEmbed Error: $e');
      print('TikTok URL: ${widget.url}');
      
      if (!mounted || _isDisposed) return;
      
      // If it's a 400 error from the API call above, we've already tried direct embed
      if (e.toString().contains('400') && _currentEmbedHtml != null) {
        return;
      }
      
      // Provide more specific error messages
      String errorMsg = 'Failed to load TikTok content';
      
      if (e.toString().contains('not found')) {
        errorMsg = 'TikTok post not found';
      } else if (e.toString().contains('private')) {
        errorMsg = 'This TikTok is private or restricted';
      } else if (e.toString().contains('photo') || widget.url.contains('photo')) {
        errorMsg = 'Photo carousels may have limited preview support';
      }
      
      setState(() {
        _errorMessage = errorMsg;
      });
      
      // Load fallback UI with direct link option
      _loadFallbackHtmlWithDirectEmbed();
    }
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (JavaScriptMessage message) {
          if (message.message == 'openTikTok') {
            widget.launchUrlCallback(widget.url);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (!_isDisposed && mounted) {
              setState(() {
                _isLoading = true;
              });
            }
          },
          onPageFinished: (String url) {
            if (!_isDisposed && mounted) {
              setState(() {
                _isLoading = false;
              });
              _injectCustomStyles();
            }
          },
          onWebResourceError: (WebResourceError error) {
            // print('TikTok WebView error: ${error.description}');
          },
        ),
      );
  }

  void _loadEmbedHtml(String html) {
    _controller.loadHtmlString(
      html,
      baseUrl: 'https://www.tiktok.com',
    );
  }

  void _loadFallbackHtmlWithDirectEmbed() {
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
      flex-direction: column;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    }
    .fallback-container {
      text-align: center;
      padding: 20px;
      color: white;
      width: 100%;
    }
    .tiktok-logo {
      width: 60px;
      height: 60px;
      margin-bottom: 20px;
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
      text-decoration: none;
      display: inline-block;
      margin-top: 20px;
    }
    .error-message {
      color: #ccc;
      margin: 10px 0;
      font-size: 14px;
    }
    .try-embed {
      margin-top: 30px;
      padding: 20px;
      background: rgba(255,255,255,0.05);
      border-radius: 8px;
    }
    .info-text {
      color: #aaa;
      font-size: 12px;
      margin-top: 10px;
    }
  </style>
</head>
<body>
  <div class="fallback-container">
    <svg class="tiktok-logo" viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M34.353 13.547c2.849.204 5.524-1.27 7.455-3.13v7.126a14.41 14.41 0 01-7.455-2.002v9.154c0 9.154-9.843 15.487-17.484 9.702-5.072-3.838-6.361-11.627-2.829-16.936 3.532-5.31 10.794-6.748 16.087-3.195v7.57c-.88-.352-1.863-.52-2.84-.477-2.876.127-5.128 2.509-5.026 5.38.102 2.871 2.557 5.136 5.433 5.026 2.876-.11 5.173-2.463 5.173-5.338V4h7.486v9.547z" fill="#FE2C55"/>
      <path d="M34.353 13.547V4h7.486c-.086 4.023 2.126 7.78 5.725 9.547-1.931 1.86-4.606 3.334-7.455 3.13a10.41 10.41 0 01-5.756-3.13z" fill="#25F4EE"/>
      <path d="M11.343 28.705c-3.532 5.309-2.243 13.098 2.829 16.936 7.641 5.785 17.484-.548 17.484-9.702v-9.154a14.41 14.41 0 007.455 2.002v-7.126c-3.599-1.767-5.811-5.524-5.725-9.547H26.9v23.314c0 2.875-2.297 5.228-5.173 5.338-2.876.11-5.331-2.155-5.433-5.026-.102-2.871 2.15-5.253 5.026-5.38.977-.043 1.96.125 2.84.477v-7.57c-5.293-3.553-12.555-2.115-16.087 3.195z" fill="#FE2C55"/>
    </svg>
    <h2 style="color: white; margin: 10px 0;">TikTok Content</h2>
    <p class="error-message">${_errorMessage ?? 'Unable to load preview'}</p>
    ${_errorMessage?.contains('Photo') ?? false ? '<p class="info-text">Photo carousel posts may need to be viewed directly on TikTok</p>' : ''}
    <button class="open-button" onclick="FlutterChannel.postMessage('openTikTok');">
      Open in TikTok
    </button>
  </div>
  
  <!-- Try direct TikTok embed as fallback -->
  <div class="try-embed" style="display: none;">
    <blockquote class="tiktok-embed" cite="${widget.url}" data-video-id="${_extractVideoId(widget.url)}" style="max-width: 605px;min-width: 325px;">
      <section></section>
    </blockquote>
    <script async src="https://www.tiktok.com/embed.js"></script>
  </div>
</body>
</html>
''';
    
    setState(() {
      _currentEmbedHtml = fallbackHtml;
    });
    
    _loadEmbedHtml(fallbackHtml);
  }
  
  String _extractVideoId(String url) {
    // Try to extract video ID from URL
    final RegExp videoIdPattern = RegExp(r'/video/(\d+)');
    final match = videoIdPattern.firstMatch(url);
    return match?.group(1) ?? '';
  }

  void _loadDirectEmbed() {
    print('TikTok: Attempting direct embed for URL: ${widget.url}');
    
    // For photo carousels, skip the embed attempt and show our custom message directly
    // since TikTok's embed.js will just show "Video currently unavailable"
    final directEmbedHtml = '''
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
      overflow-x: hidden;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    }
    .embed-container {
      width: 100%;
      max-width: 605px;
      display: flex;
      flex-direction: column;
      justify-content: center;
      align-items: center;
      padding: 20px;
    }
    .fallback-container {
      text-align: center;
      padding: 40px 20px;
      color: white;
      width: 100%;
      background: rgba(255, 255, 255, 0.05);
      border-radius: 12px;
    }
    .tiktok-logo {
      width: 80px;
      height: 80px;
      margin-bottom: 24px;
    }
    .open-button {
      background: #FE2C55;
      color: white;
      border: none;
      padding: 14px 28px;
      border-radius: 8px;
      font-size: 16px;
      font-weight: 600;
      cursor: pointer;
      text-decoration: none;
      display: inline-block;
      margin-top: 24px;
      transition: background 0.2s;
    }
    .open-button:hover {
      background: #E61942;
    }
    .info-text {
      color: #ccc;
      font-size: 16px;
      margin: 12px 0;
      line-height: 1.5;
    }
    .title {
      color: white;
      font-size: 24px;
      font-weight: 600;
      margin: 16px 0;
    }
    .icon-container {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      margin-bottom: 16px;
    }
    .photo-icon {
      width: 24px;
      height: 24px;
      fill: #FE2C55;
    }
  </style>
</head>
<body>
  <div class="embed-container">
    <div class="fallback-container">
      <svg class="tiktok-logo" viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M34.353 13.547c2.849.204 5.524-1.27 7.455-3.13v7.126a14.41 14.41 0 01-7.455-2.002v9.154c0 9.154-9.843 15.487-17.484 9.702-5.072-3.838-6.361-11.627-2.829-16.936 3.532-5.31 10.794-6.748 16.087-3.195v7.57c-.88-.352-1.863-.52-2.84-.477-2.876.127-5.128 2.509-5.026 5.38.102 2.871 2.557 5.136 5.433 5.026 2.876-.11 5.173-2.463 5.173-5.338V4h7.486v9.547z" fill="#FE2C55"/>
        <path d="M34.353 13.547V4h7.486c-.086 4.023 2.126 7.78 5.725 9.547-1.931 1.86-4.606 3.334-7.455 3.13a10.41 10.41 0 01-5.756-3.13z" fill="#25F4EE"/>
        <path d="M11.343 28.705c-3.532 5.309-2.243 13.098 2.829 16.936 7.641 5.785 17.484-.548 17.484-9.702v-9.154a14.41 14.41 0 007.455 2.002v-7.126c-3.599-1.767-5.811-5.524-5.725-9.547H26.9v23.314c0 2.875-2.297 5.228-5.173 5.338-2.876.11-5.331-2.155-5.433-5.026-.102-2.871 2.15-5.253 5.026-5.38.977-.043 1.96.125 2.84.477v-7.57c-5.293-3.553-12.555-2.115-16.087 3.195z" fill="#FE2C55"/>
      </svg>
      
      <div class="icon-container">
        <svg class="photo-icon" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <path d="M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2zM8.5 13.5l2.5 3.01L14.5 12l4.5 6H5l3.5-4.5z"/>
        </svg>
        <h2 class="title">Photo Carousel Post</h2>
      </div>
      
      <p class="info-text">This TikTok contains multiple photos in a slideshow format.</p>
      <p class="info-text">Photo carousels cannot be previewed in the app at this time.</p>
      
      <button class="open-button" onclick="FlutterChannel.postMessage('openTikTok');">
        View Photos on TikTok
      </button>
    </div>
  </div>
</body>
</html>
''';
    
    setState(() {
      _currentEmbedHtml = directEmbedHtml;
      _errorMessage = null; // Clear any previous error
    });
    
    _loadEmbedHtml(directEmbedHtml);
  }

  void _injectCustomStyles() {
    // Inject custom JavaScript to improve the embed appearance
    _controller.runJavaScript('''
      // Wait for TikTok embed to load
      setTimeout(function() {
        // Hide unnecessary elements and customize appearance
        var style = document.createElement('style');
        style.innerHTML = `
          body { 
            background: #000 !important; 
          }
          /* Ensure the iframe fills the container */
          .tiktok-embed iframe {
            width: 100% !important;
            max-width: 100% !important;
            height: 700px !important;
          }
        `;
        document.head.appendChild(style);
        
        // Force a resize event to ensure proper rendering
        window.dispatchEvent(new Event('resize'));
      }, 1000);
    ''');
  }
  
  void _refreshWebView() {
    if (_currentEmbedHtml != null) {
      setState(() {
        _isLoading = true;
      });
      _controller.loadHtmlString(
        _currentEmbedHtml!,
        baseUrl: 'https://www.tiktok.com',
      );
    } else {
      // If we don't have saved HTML, fetch it again
      _fetchTikTokEmbed();
    }
  }

  void _loadFallbackHtml() {
    // Use the new method that includes better error handling
    _loadFallbackHtmlWithDirectEmbed();
  }

  @override
  Widget build(BuildContext context) {
    // Fixed height for TikTok embed
    const double height = 700.0;

    return Container(
      color: Colors.black,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // WebView Container
          Container(
            height: height,
            width: double.infinity,
            color: Colors.black,
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
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
          ),
          // Controls
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 48),
                IconButton(
                  icon: const FaIcon(FontAwesomeIcons.tiktok),
                  color: const Color(0xFF000000),
                  iconSize: 32,
                  tooltip: 'Open in TikTok',
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  onPressed: () => widget.launchUrlCallback(widget.url),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  iconSize: 24,
                  color: Colors.blue,
                  tooltip: 'Refresh',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onPressed: _refreshWebView,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
