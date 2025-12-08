import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Instagram WebView widget using flutter_inappwebview for screenshot support
class InstagramWebView extends StatefulWidget {
  final String url;
  final double height;
  final Future<void> Function(String) launchUrlCallback;
  final Function(InAppWebViewController) onWebViewCreated;
  final Function(String) onPageFinished;

  const InstagramWebView({
    super.key,
    required this.url,
    required this.height,
    required this.launchUrlCallback,
    required this.onWebViewCreated,
    required this.onPageFinished,
  });

  @override
  InstagramWebViewState createState() => InstagramWebViewState();
}

class InstagramWebViewState extends State<InstagramWebView> {
  InAppWebViewController? controller;
  bool isLoading = true;
  
  int _loadingDelayOperationId = 0;
  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  /// Take a screenshot of the current WebView content
  /// Uses PNG format for best quality OCR/text detection
  Future<Uint8List?> takeScreenshot() async {
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
    if (kIsWeb) return;
    
    if (mounted && !_isDisposed && controller != null) {
      controller!.loadUrl(
        urlRequest: URLRequest(url: WebUri(_cleanInstagramUrl(widget.url))),
      );
    }
  }

  String _cleanInstagramUrl(String url) {
    try {
      Uri uri = Uri.parse(url);
      String cleanUrl = '${uri.scheme}://${uri.host}${uri.path}';
      if (!cleanUrl.endsWith('/')) {
        cleanUrl = '$cleanUrl/';
      }
      return cleanUrl;
    } catch (e) {
      if (url.contains('?')) {
        url = url.split('?')[0];
      }
      if (!url.endsWith('/')) {
        url = '$url/';
      }
      return url;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return SizedBox(
        height: widget.height,
        width: double.infinity,
        child: const Center(child: Text("Web implementation not yet available")),
      );
    }

    final double containerHeight = widget.height;
    
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
            initialUrlRequest: URLRequest(
              url: WebUri(_cleanInstagramUrl(widget.url)),
            ),
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
              widget.onWebViewCreated(webController);
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
                widget.onPageFinished(url?.toString() ?? '');
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
