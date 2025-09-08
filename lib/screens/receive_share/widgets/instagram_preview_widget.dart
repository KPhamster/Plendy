import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
// For Platform checks
import 'dart:async'; // For cancellation
import 'dart:io' show Platform; // For iOS detection
import 'package:flutter/foundation.dart' show kIsWeb; // Import kIsWeb
// Removed unused url_launcher import
// For Instagram Icon

// Web-specific imports removed - now using direct URL loading like browser signin

// Renamed class to reflect its focus
class InstagramWebView extends StatefulWidget {
  final String url;
  final double height; // Requires a specific height from the parent
  final Future<void> Function(String) launchUrlCallback;
  final Function(WebViewController) onWebViewCreated;
  final Function(String) onPageFinished; // Callback when page finishes

  const InstagramWebView({
    super.key,
    required this.url,
    required this.height, // This will be effectively ignored for web aspect ratio
    required this.launchUrlCallback,
    required this.onWebViewCreated,
    required this.onPageFinished,
  });

  @override
  InstagramWebViewState createState() => InstagramWebViewState();
}

class InstagramWebViewState extends State<InstagramWebView> {
  // Mobile-only controller
  late final WebViewController controller;
  bool isLoading = true; // Still manage internal loading indicator
  
  // Add cancellation tokens for operations
  int _loadingDelayOperationId = 0;
  
  // Add a dispose flag as an extra safety check
  bool _isDisposed = false;

  // Web-specific variables removed

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // Web implementation would go here if needed
      // For now, we'll focus on mobile implementation
    } else {
      _initWebViewController(); // Mobile: Initialize WebView controller
    }
  }
  
  @override
  void dispose() {
    _isDisposed = true; // Mark as disposed first
    super.dispose();
  }

  // Removed unused auto-click simulation helper

  void _initWebViewController() {
    // This should only be called if !kIsWeb, but double-check.
    if (kIsWeb) return;

    if (Platform.isIOS) {
      final WebKitWebViewControllerCreationParams params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
      );
      controller = WebViewController.fromPlatformCreationParams(params);
    } else {
      controller = WebViewController();
    }
    
    if (!mounted || _isDisposed) return; // Safety check
    
    widget.onWebViewCreated(controller); // Pass controller to parent

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setUserAgent(
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {},
          onPageStarted: (String url) {
            if (!mounted || _isDisposed) return; // Safety check
            
            setState(() {
              isLoading = true;
            });
          },
          onPageFinished: (String url) {
            if (!mounted || _isDisposed) return; // Safety check
            
            // Safely call the callback
            try {
              widget.onPageFinished(url); // Notify parent
            } catch (e) {
              print("Error in onPageFinished callback: $e");
            }
            
            // Try to strip fullscreen permissions and enforce inline playback
            try {
              controller.runJavaScript('''
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
            
            // Set loading to false after a short delay to allow rendering
            final currentLoadingOperationId = ++_loadingDelayOperationId;
            
            Future.delayed(const Duration(milliseconds: 500), () {
              // Check if this is still the current operation and widget is still mounted
              if (!mounted || _isDisposed || _loadingDelayOperationId != currentLoadingOperationId) return;
              
              setState(() {
                isLoading = false;
              });
            });
          },
          onWebResourceError: (WebResourceError error) {
            print("WebView Error: ${error.description}");
            
            if (!mounted || _isDisposed) return; // Safety check
            
            setState(() {
              isLoading = false; // Stop loading on error
            });
          },
          onNavigationRequest: (NavigationRequest request) {
            // Handle custom URL schemes (like Instagram app deep links)
            final url = request.url;
            
            // Handle about:blank URLs
            if (url == 'about:blank' || url == 'https://about:blank') {
              return NavigationDecision.prevent;
            }
            
            // List of custom schemes to block
            final customSchemes = ['instagram', 'fb', 'intent'];
            final uri = Uri.tryParse(url);
            
            if (uri != null && customSchemes.any((scheme) => url.startsWith('$scheme:'))) {
              // Block the custom scheme navigation
              return NavigationDecision.prevent;
            }
            
            // Allow Instagram domains, CDN, and Facebook authentication
            if (url.contains('instagram.com') || 
                url.contains('cdn.instagram.com') ||
                url.contains('cdninstagram.com') ||
                url.contains('fbcdn.net') ||
                url.contains('facebook.com/instagram/') ||  // Allow Facebook-Instagram auth flows
                url.contains('facebook.com/login/') ||      // Allow Facebook login
                url.contains('accounts.instagram.com')) {   // Allow Instagram accounts
              return NavigationDecision.navigate;
            }
            
            // For external links, use callback only if it's a valid HTTP/HTTPS URL
            if (mounted && !_isDisposed && url.startsWith('http')) {
              try {
                widget.launchUrlCallback(url);
              } catch (e) {
                print("Error in launchUrlCallback: $e");
              }
            }
            
            return NavigationDecision.prevent;
          },
        ),
      );
      
    // Final check before loading URL directly
    if (!mounted || _isDisposed) return;
    
    // Load the Instagram URL directly instead of custom HTML
    controller.loadRequest(Uri.parse(_cleanInstagramUrl(widget.url)));
  }

  void refresh() {
    if (kIsWeb) {
      // Web logic would go here if needed
    } else {
      if (mounted && !_isDisposed) {
        controller.loadRequest(Uri.parse(_cleanInstagramUrl(widget.url)));
      }
    }
  }

  // Clean Instagram URL (keep this helper)
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

  // Custom HTML generation removed - now loading Instagram URLs directly

  // Removed unused launcher helper

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      // Web implementation would go here if needed
      return SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Center(child: Text("Web implementation not yet available")),
      );
    }

    // Mobile specific WebViewWidget implementation
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
          child: WebViewWidget(controller: controller),
        ),
        if (isLoading)
          Container(
            width: double.infinity,
            height: containerHeight,
            color: Colors.white.withOpacity(0.7),
            child: Center(
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
