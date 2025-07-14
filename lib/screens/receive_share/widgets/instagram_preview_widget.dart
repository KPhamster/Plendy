import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
// For Platform checks
import 'dart:async'; // For cancellation
import 'dart:io' show Platform; // For iOS detection
import 'package:flutter/foundation.dart' show kIsWeb; // Import kIsWeb
import 'package:url_launcher/url_launcher.dart'; // For launching URLs
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
  int _simulateTapOperationId = 0;
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

  // Method to simulate a tap (might still be useful for auto-play) - COMMENTED OUT
  void _simulateEmbedTap() {
    if (!mounted || _isDisposed || kIsWeb) return; // Safety check and web check
    
    // ALL AUTO-CLICKING BEHAVIOR COMMENTED OUT - UNCOMMENT TO RE-ENABLE
    /*
    controller.runJavaScript('''
      (function() {
        try {
          // Find any clickable elements in the Instagram embed
          var embedContainer = document.querySelector('.instagram-media');
          if (embedContainer) {
            console.log('Found Instagram embed container');

            // PRIMARY STRATEGY: Coordinate-based clicking with ±100 pixel randomization from center of top-half
            var rect = embedContainer.getBoundingClientRect();
            var baseCenterX = rect.left + rect.width / 2;
            var baseCenterY = rect.top + rect.height / 4; // Center of top-half (1/4 from top)

            // Generate random offset within ±100 pixels range
            var offsetX = Math.random() * 200 - 100; // Range -100 to +100
            var offsetY = Math.random() * 200 - 100; // Range -100 to +100
            var clickX = baseCenterX + offsetX;
            var clickY = baseCenterY + offsetY;

            console.log('Primary strategy: Simulating click with randomization from top-half center at:', clickX, clickY);

            // Find the actual element at the calculated coordinates
            var targetElement = document.elementFromPoint(clickX, clickY);
            if (targetElement) {
              console.log('Target element found at coordinates:', targetElement.tagName, targetElement.className);
              
              // Validate that we have a clickable element (prefer links and interactive elements)
              var clickableElement = targetElement;
              
              // If we hit a non-interactive element, try to find a parent link or clickable element
              var current = targetElement;
              while (current && current !== embedContainer) {
                if (current.tagName === 'A' || 
                    current.onclick || 
                    current.style.cursor === 'pointer' ||
                    current.getAttribute('role') === 'button') {
                  clickableElement = current;
                  console.log('Found clickable parent element:', clickableElement.tagName, clickableElement.className);
                  break;
                }
                current = current.parentElement;
              }
              
              // Dispatch click event on the clickable element
              var clickEvent = new MouseEvent('click', {
                view: window,
                bubbles: true,
                cancelable: true,
                clientX: clickX,
                clientY: clickY
              });
              
              // Try to dispatch touchstart event, but don't let it block the click event
              try {
                var touchEvent = new TouchEvent('touchstart', {
                  bubbles: true,
                  cancelable: true
                });
                clickableElement.dispatchEvent(touchEvent);
                console.log('TouchEvent dispatched successfully');
              } catch (touchError) {
                console.log('TouchEvent failed, continuing with click:', touchError.message);
              }
              
              // Always dispatch the click event
              clickableElement.dispatchEvent(clickEvent);
              console.log('Primary strategy: Dispatched click event on element:', clickableElement.tagName, clickableElement.className);
              return;
            } else {
              console.log('No element found at coordinates, falling back to container click');
              // Fallback to original container click if elementFromPoint fails
              var clickEvent = new MouseEvent('click', {
                view: window,
                bubbles: true,
                cancelable: true,
                clientX: clickX,
                clientY: clickY
              });
              embedContainer.dispatchEvent(clickEvent);
              return;
            }
          }

          // FALLBACK STRATEGY 1: Try to find the top level <a> tag which is usually clickable
          var mainLink = document.querySelector('.instagram-media div a');
          if (mainLink) {
            console.log('Fallback 1: Found main Instagram link, simulating click');
            mainLink.click();
            return;
          }

          // FALLBACK STRATEGY 2: Try to find any Instagram link
          var anyLink = document.querySelector('a[href*="instagram.com"]');
          if (anyLink) {
            console.log('Fallback 2: Found Instagram link, simulating click');
            anyLink.click();
            return;
          }

          // FALLBACK STRATEGY 3: Try to find a media player or embed
          var player = document.querySelector('iframe[src*="instagram.com"]');
          if (player) {
            console.log('Fallback 3: Found Instagram iframe, simulating click');
            // Clicking the iframe itself might not work, better to target content within if possible
            // or stick to the embedContainer click simulation above.
             console.log('Skipping iframe click, relying on embedContainer fallback.');
            // player.click(); // This might be less effective
            return;
          }

          console.log('Instagram embed container not found');
        } catch (e) {
          console.error('Error in auto-click script:', e);
        }
      })();
    ''').catchError((error) {
      // Safely handle JavaScript errors
      print("JavaScript error during tap simulation: $error");
    });
    */
  }

  void _initWebViewController() {
    // This should only be called if !kIsWeb, but double-check.
    if (kIsWeb) return;

    controller = WebViewController();
    
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
            
            // List of custom schemes to block
            final customSchemes = ['instagram', 'fb', 'intent'];
            final uri = Uri.tryParse(url);
            
            if (uri != null && customSchemes.any((scheme) => url.startsWith('$scheme:'))) {
              // Block the custom scheme navigation
              return NavigationDecision.prevent;
            }
            
            // Allow Instagram domains and CDN
            if (url.contains('instagram.com') || 
                url.contains('cdn.instagram.com') ||
                url.contains('cdninstagram.com') ||
                url.contains('fbcdn.net')) {
              return NavigationDecision.navigate;
            }
            
            // For external links, use callback
            if (mounted && !_isDisposed) {
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

  Future<void> _launchInstagramUrl() async {
    final Uri uri = Uri.parse(widget.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      // Handle error or show a message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open Instagram link: ${widget.url}')),
        );
      }
      print('Could not launch ${widget.url}');
    }
  }

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
