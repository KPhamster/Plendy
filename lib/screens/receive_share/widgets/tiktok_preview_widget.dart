import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';

class TikTokPreviewWidget extends StatefulWidget {
  final String url;
  final Future<void> Function(String) launchUrlCallback;
  final void Function(bool, String)? onExpansionChanged;
  final void Function(String url, bool isPhotoCarousel)? onPhotoDetected;
  final bool showControls;
  final Function(InAppWebViewController)? onWebViewCreated;

  const TikTokPreviewWidget({
    super.key,
    required this.url,
    required this.launchUrlCallback,
    this.onExpansionChanged,
    this.onPhotoDetected,
    this.showControls = true,
    this.onWebViewCreated,
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

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchTikTokEmbed();
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

  Future<void> _fetchTikTokEmbed() async {
    try {
      final Uri oembedUrl = Uri.parse('https://www.tiktok.com/oembed?url=${Uri.encodeComponent(widget.url)}');
      
      print('TikTok oEmbed: Fetching embed for ${widget.url}');
      
      final response = await http.get(oembedUrl);
      
      if (!mounted || _isDisposed) return;
      
      print('TikTok oEmbed: Response status ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['html'] != null) {
          // ONLY check the type field - don't check HTML content as it may contain "photo" in scripts
          final bool isPhotoPost = data['type'] == 'photo';
          
          print('🎬 TIKTOK TYPE: ${data['type']}');
          print('🎬 IS PHOTO CAROUSEL: $isPhotoPost');
          print('🎬 HEIGHT WILL BE: ${isPhotoPost ? 350.0 : 700.0}px');
          
          if (mounted) {
            setState(() {
              _isPhotoCarousel = isPhotoPost;
            });
          }
          
          if (isPhotoPost) {
            widget.onPhotoDetected?.call(widget.url, true);
          } else {
            widget.onPhotoDetected?.call(widget.url, false);
          }
          
          final double embedHeight = isPhotoPost ? 350.0 : 700.0;
          final embedHtml = '''
<!DOCTYPE html>
<html style="height: ${embedHeight}px; margin: 0; padding: 0;">
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    html, body {
      margin: 0 !important;
      padding: 0 !important;
      background: #000 !important;
      height: ${embedHeight}px !important;
      min-height: ${embedHeight}px !important;
      max-height: ${embedHeight}px !important;
      overflow-x: hidden;
      overflow-y: hidden;
    }
    body {
      display: flex;
      justify-content: center;
      align-items: center;
    }
    .embed-container {
      width: 100% !important;
      max-width: 100% !important;
      height: ${embedHeight}px !important;
      min-height: ${embedHeight}px !important;
      display: flex;
      justify-content: center;
      align-items: center;
    }
    blockquote.tiktok-embed {
      margin: 0 !important;
      max-width: 100% !important;
      min-width: unset !important;
      height: ${embedHeight}px !important;
      min-height: ${embedHeight}px !important;
    }
    .tiktok-embed iframe {
      min-height: ${embedHeight}px !important;
      height: ${embedHeight}px !important;
      max-height: ${embedHeight}px !important;
    }
  </style>
</head>
<body>
  <div class="embed-container">
    ${data['html']}
  </div>
</body>
</html>
''';
          
          setState(() {
            _currentEmbedHtml = embedHtml;
          });
        } else {
          if (data['error'] != null) {
            throw Exception('TikTok API error: ${data['error']}');
          } else {
            throw Exception('No embed HTML in response');
          }
        }
      } else {
        if (response.statusCode == 400) {
          widget.onPhotoDetected?.call(widget.url, true);
          _loadDirectEmbed();
          return;
        } else {
          throw Exception('Failed to fetch embed: ${response.statusCode}');
        }
      }
    } catch (e) {
      print('TikTok oEmbed Error: $e');
      
      if (!mounted || _isDisposed) return;
      
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
      
      _loadFallbackHtml();
    }
  }

  void _loadDirectEmbed() {
    if (mounted) {
      setState(() {
        _isPhotoCarousel = true;
      });
    }
    
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
    }
    .fallback-container {
      text-align: center;
      padding: 40px 20px;
      color: white;
      width: 100%;
      background: rgba(255, 255, 255, 0.05);
      border-radius: 12px;
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
      margin-top: 24px;
    }
  </style>
</head>
<body>
  <div class="fallback-container">      
    <h2 style="color: white;">Photo Carousel Post</h2>
    <p style="color: #ccc;">This TikTok contains multiple photos in a slideshow format.</p>
    <p style="color: #ccc;">Photo carousels cannot be previewed in the app at this time.</p>
    <button class="open-button" onclick="window.flutter_inappwebview.callHandler('openTikTok');">
      View Photos on TikTok
    </button>
  </div>
</body>
</html>
''';
    
    setState(() {
      _currentEmbedHtml = directEmbedHtml;
      _errorMessage = null;
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
      _fetchTikTokEmbed();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final double height = _isPhotoCarousel ? 350.0 : 700.0;
    print('🎬 TIKTOK BUILD: Photo=${_isPhotoCarousel}, Height=${height}px');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: Container(
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
                      iframeAllowFullscreen: false,
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
                        
                        // Force TikTok embed to respect our height
                        final double embedHeight = _isPhotoCarousel ? 350.0 : 700.0;
                        controller.evaluateJavascript(source: '''
                          (function() {
                            const iframe = document.querySelector('.tiktok-embed iframe');
                            if (iframe) {
                              iframe.style.height = '${embedHeight}px !important';
                              iframe.style.minHeight = '${embedHeight}px !important';
                            }
                            const blockquote = document.querySelector('blockquote.tiktok-embed');
                            if (blockquote) {
                              blockquote.style.height = '${embedHeight}px !important';
                              blockquote.style.minHeight = '${embedHeight}px !important';
                            }
                            document.body.style.height = '${embedHeight}px !important';
                          })();
                        ''');
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
          ),
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
                  icon: const FaIcon(FontAwesomeIcons.tiktok),
                  color: Colors.black,
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
                  onPressed: refreshWebView,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
