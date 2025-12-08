import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class FacebookPreviewWidget extends StatefulWidget {
  final String url;
  final double height;
  final Function(InAppWebViewController) onWebViewCreated;
  final Function(String) onPageFinished;
  final Future<void> Function(String) launchUrlCallback;
  final bool showControls;

  const FacebookPreviewWidget({
    super.key,
    required this.url,
    required this.height,
    required this.onWebViewCreated,
    required this.onPageFinished,
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

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  /// Take a screenshot of the current WebView content
  /// Uses PNG format for best quality OCR/text detection
  Future<Uint8List?> takeScreenshot() async {
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

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Container(
        height: widget.height,
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
              const Text(
                'Facebook content',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
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

    final double containerHeight = _isExpanded ? 800 : widget.height;
    
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
                initialUrlRequest: URLRequest(url: WebUri(widget.url)),
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
                  widget.onWebViewCreated(webController);
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
                    widget.onPageFinished(url?.toString() ?? '');
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
                onPressed: () {
                  if (controller != null) {
                    controller!.reload();
                  }
                },
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
