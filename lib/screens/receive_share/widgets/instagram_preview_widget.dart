import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
// For Platform checks
import 'dart:async'; // For cancellation
import 'package:flutter/foundation.dart' show kIsWeb; // Import kIsWeb
import 'package:url_launcher/url_launcher.dart'; // For launching URLs
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; // For Instagram Icon

// Conditional imports for web-specific embedding
import 'instagram_web_logic_stub.dart' 
    if (dart.library.html) 'instagram_web_logic.dart' as instagram_web;

// Renamed class to reflect its focus
class InstagramWebView extends StatefulWidget {
  final String url;
  final double height; // Requires a specific height from the parent
  final Function(WebViewController) onWebViewCreated;
  final Function(String) onPageFinished; // Callback when page finishes
  final Future<void> Function(String)
      launchUrlCallback; // For internal navigation

  const InstagramWebView({
    super.key,
    required this.url,
    required this.height, // This will be effectively ignored for web aspect ratio
    required this.onWebViewCreated,
    required this.onPageFinished,
    required this.launchUrlCallback,
  });

  @override
  _InstagramWebViewState createState() => _InstagramWebViewState();
}

class _InstagramWebViewState extends State<InstagramWebView> {
  // Mobile-only controller
  late final WebViewController controller;
  bool isLoading = true; // Still manage internal loading indicator
  
  // Add cancellation tokens for operations
  int _simulateTapOperationId = 0;
  int _loadingDelayOperationId = 0;
  
  // Add a dispose flag as an extra safety check
  bool _isDisposed = false;

  // Web-only view type
  String? _webEmbedViewType;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // Generate a unique view type for HtmlElementView
      // Using DateTime ensures uniqueness even if hashCode collides (unlikely for URLs here)
      _webEmbedViewType = 'instagram-embed-view-${widget.url.hashCode}-${DateTime.now().microsecondsSinceEpoch}';

      // MODIFIED: Call the conditionally imported function
      instagram_web.registerInstagramViewFactory(
        _webEmbedViewType!,
        _generateInstagramEmbedHtml(widget.url), // HTML includes embed.js script call
      );
    } else {
      _initWebViewController(); // Mobile: Initialize WebView controller
    }
  }
  
  @override
  void dispose() {
    _isDisposed = true; // Mark as disposed first
    super.dispose();
  }

  // Method to simulate a tap (might still be useful for auto-play)
  void _simulateEmbedTap() {
    if (!mounted || _isDisposed || kIsWeb) return; // Safety check and web check
    
    controller.runJavaScript('''
      (function() {
        try {
          // First approach: Using a simulated click on known elements
          // Find any clickable elements in the Instagram embed
          var embedContainer = document.querySelector('.instagram-media');
          if (embedContainer) {
            console.log('Found Instagram embed container');

            // Try to find the top level <a> tag which is usually clickable
            var mainLink = document.querySelector('.instagram-media div a');
            if (mainLink) {
              console.log('Found main Instagram link, simulating click');
              mainLink.click();
              return;
            }

            // Try to find any Instagram link
            var anyLink = document.querySelector('a[href*="instagram.com"]');
            if (anyLink) {
              console.log('Found Instagram link, simulating click');
              anyLink.click();
              return;
            }

            // If no specific element found, click near the center of the embed
            var rect = embedContainer.getBoundingClientRect();
            var baseCenterX = rect.left + rect.width / 2;
            var baseCenterY = rect.top + rect.height / 2;

            // Generate random offset within a small range (e.g., +/- 5 pixels)
            var offsetX = Math.random() * 10 - 5; // Range -5 to +5
            var offsetY = Math.random() * 10 - 5; // Range -5 to +5
            var clickX = baseCenterX + offsetX;
            var clickY = baseCenterY + offsetY;

            console.log('Simulating click near center at:', clickX, clickY);

            // Create and dispatch click event using the offset coordinates
            var clickEvent = new MouseEvent('click', {
              view: window,
              bubbles: true,
              cancelable: true,
              clientX: clickX, // Use coordinate with offset
              clientY: clickY  // Use coordinate with offset
            });

            embedContainer.dispatchEvent(clickEvent);
            return;
          }

          // Second approach: Try to find a media player or embed
          var player = document.querySelector('iframe[src*="instagram.com"]');
          if (player) {
            console.log('Found Instagram iframe, simulating click');
            // Clicking the iframe itself might not work, better to target content within if possible
            // or stick to the embedContainer click simulation above.
            // For simplicity, let's keep the embedContainer simulation as the main fallback.
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
            // Use cancellation approach
            final currentLoadingOperationId = ++_loadingDelayOperationId;
            
            Future.delayed(const Duration(milliseconds: 0), () {
              // Check if this is still the current operation and widget is still mounted
              if (!mounted || _isDisposed || _loadingDelayOperationId != currentLoadingOperationId) return;
              
              setState(() {
                isLoading = false;
              });
              
              // RE-ADD: Simulate tap after loading with cancellation
              final currentTapOperationId = ++_simulateTapOperationId;
              
              Future.delayed(const Duration(milliseconds: 0), () {
                // Check again before executing
                if (!mounted || _isDisposed || _simulateTapOperationId != currentTapOperationId) return;
                _simulateEmbedTap();
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
            // Intercept navigation to external links
            if (!request.url.contains('instagram.com') &&
                !request.url.contains('cdn.instagram.com') &&
                !request.url.contains('cdninstagram.com')) {
              
              // Check if mounted before attempting callback
              if (mounted && !_isDisposed) {
                // Use a try-catch for the callback
                try {
                  widget.launchUrlCallback(request.url);
                } catch (e) {
                  print("Error in launchUrlCallback: $e");
                }
              }
              
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );
      
    // Final check before loading HTML
    if (!mounted || _isDisposed) return;
    
    controller.loadHtmlString(_generateInstagramEmbedHtml(widget.url));
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

  // Generate HTML (keep this helper)
  String _generateInstagramEmbedHtml(String url) {
    final String cleanUrl = _cleanInstagramUrl(url);
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
            font-family: Arial, sans-serif;
            overflow: hidden; /* Keep this to prevent scrollbars on body */
            background-color: white;
          }
          .container { /* This div wraps the embed-container */
            display: flex; /* Use flex to center content if needed */
            justify-content: center;
            align-items: center;
            width: 100%;
            height: 100%; /* Ensure it takes full space from iframe */
          }
          .embed-container { /* This is the direct parent of the blockquote */
            width: 100%; 
            padding-top: 177.77%; /* 16/9 aspect ratio (100% / (9/16)) */
            position: relative; 
            max-width: 540px; /* Instagram's standard max-width for embeds */
            margin: 0 auto; /* Center if max-width is hit */
            overflow: hidden; /* Hide anything that might spill out of aspect ratio */
          }
          .instagram-media { /* The blockquote itself */
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            /* Remove fixed widths from here, let parent .embed-container control it */
            /* style attribute on blockquote below will also be simplified */
            margin: 0 !important; /* Override default margins */
            padding: 0 !important; /* Override default padding */
            border: 0 !important; /* Override default border */
            border-radius:0 !important; /* Override default radius */
            box-shadow: none !important; /* Override default shadow */
          }
          iframe { /* Just in case Instagram's script adds its own iframe inside our iframe */
            border: none !important;
            margin: 0 !important;
            padding: 0 !important;
            height: 100% !important;
            width: 100% !important;
          }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="embed-container">
            <blockquote class="instagram-media" data-instgrm-captioned data-instgrm-permalink="$cleanUrl"
              data-instgrm-version="14" style="background:#FFF;">
              <!-- Placeholder content inside blockquote is mostly for when JS is disabled -->
              <!-- The embed.js script will replace this or use it -->
              <div style="padding:16px;"> 
                <a href="$cleanUrl" style="background:#FFFFFF; line-height:0; padding:0 0; text-align:center; text-decoration:none; width:100%;" target="_blank">
                  <div style="display:flex; flex-direction:row; align-items:center;">
                    <div style="background-color:#F4F4F4; border-radius:50%; flex-grow:0; height:40px; margin-right:14px; width:40px;"></div>
                    <div style="display:flex; flex-direction:column; flex-grow:1; justify-content:center;">
                      <div style="background-color:#F4F4F4; border-radius:4px; flex-grow:0; height:14px; margin-bottom:6px; width:100px;"></div>
                      <div style="background-color:#F4F4F4; border-radius:4px; flex-grow:0; height:14px; width:60px;"></div>
                    </div>
                  </div>
                  <div style="padding:19% 0;"></div>
                  <div style="display:block; height:50px; margin:0 auto 12px; width:50px;">
                    <svg width="50px" height="50px" viewBox="0 0 60 60" version="1.1" xmlns="https://www.w3.org/2000/svg" xmlns:xlink="https://www.w3.org/1999/xlink">
                      <g stroke="none" stroke-width="1" fill="none" fill-rule="evenodd">
                        <g transform="translate(-511.000000, -20.000000)" fill="#000000">
                          <g>
                            <path d="M556.869,30.41 C554.814,30.41 553.148,32.076 553.148,34.131 C553.148,36.186 554.814,37.852 556.869,37.852 C558.924,37.852 560.59,36.186 560.59,34.131 C560.59,32.076 558.924,30.41 556.869,30.41 M541,60.657 C535.114,60.657 530.342,55.887 530.342,50 C530.342,44.114 535.114,39.342 541,39.342 C546.887,39.342 551.658,44.114 551.658,50 C551.658,55.887 546.887,60.657 541,60.657 M541,33.886 C532.1,33.886 524.886,41.1 524.886,50 C524.886,58.899 532.1,66.113 541,66.113 C549.9,66.113 557.115,58.899 557.115,50 C557.115,41.1 549.9,33.886 541,33.886 M565.378,62.101 C565.244,65.022 564.756,66.606 564.346,67.663 C563.803,69.06 563.154,70.057 562.106,71.106 C561.058,72.155 560.06,72.803 558.662,73.347 C557.607,73.757 556.021,74.244 553.102,74.378 C549.944,74.521 548.997,74.552 541,74.552 C533.003,74.552 532.056,74.521 528.898,74.378 C525.979,74.244 524.393,73.757 523.338,73.347 C521.94,72.803 520.942,72.155 519.894,71.106 C518.846,70.057 518.197,69.06 517.654,67.663 C517.244,66.606 516.755,65.022 516.623,62.101 C516.479,58.943 516.448,57.996 516.448,50 C516.448,42.003 516.479,41.056 516.623,37.899 C516.755,34.978 517.244,33.391 517.654,32.338 C518.197,30.938 518.846,29.942 519.894,28.894 C520.942,27.846 521.94,27.196 523.338,26.654 C524.393,26.244 525.979,25.756 528.898,25.623 C532.057,25.479 533.004,25.448 541,25.448 C548.997,25.448 549.943,25.479 553.102,25.623 C556.021,25.756 557.607,26.244 558.662,26.654 C560.06,27.196 561.058,27.846 562.106,28.894 C563.154,29.942 563.803,30.938 564.346,32.338 C564.756,33.391 565.244,34.978 565.378,37.899 C565.522,41.056 565.552,42.003 565.552,50 C565.552,57.996 565.522,58.943 565.378,62.101 M570.82,37.631 C570.674,34.438 570.167,32.258 569.425,30.349 C568.659,28.377 567.633,26.702 565.965,25.035 C564.297,23.368 562.623,22.342 560.652,21.575 C558.743,20.834 556.562,20.326 553.369,20.18 C550.169,20.033 549.148,20 541,20 C532.853,20 531.831,20.033 528.631,20.18 C525.438,20.326 523.257,20.834 521.349,21.575 C519.376,22.342 517.703,23.368 516.035,25.035 C514.368,26.702 513.342,28.377 512.574,30.349 C511.834,32.258 511.326,34.438 511.181,37.631 C511.035,40.831 511,41.851 511,50 C511,58.147 511.035,59.17 511.181,62.369 C511.326,65.562 511.834,67.743 512.574,69.651 C513.342,71.625 514.368,73.296 516.035,74.965 C517.703,76.634 519.376,77.658 521.349,78.425 C523.257,79.167 525.438,79.673 528.631,79.82 C531.831,79.965 532.853,80.001 541,80.001 C549.148,80.001 550.169,79.965 553.369,79.82 C556.562,79.673 558.743,79.167 560.652,78.425 C562.623,77.658 564.297,76.634 565.965,74.965 C567.633,73.296 568.659,71.625 569.425,69.651 C570.167,67.743 570.674,65.562 570.82,62.369 C570.966,59.17 571,58.147 571,50 C571,41.851 570.966,40.831 570.82,37.631"></path>
                          </g>
                        </g>
                      </g>
                    </svg>
                  </div>
                  <div style="padding-top:8px;">
                    <div style="color:#3897f0; font-family:Arial,sans-serif; font-size:14px; font-style:normal; font-weight:550; line-height:18px;">View this on Instagram</div>
                  </div>
                  <div style="padding:12.5% 0;"></div>
                  <div style="display:flex; flex-direction:row; margin-bottom:14px; align-items:center;">
                    <div>
                      <div style="background-color:#F4F4F4; border-radius:50%; height:12.5px; width:12.5px; transform:translateX(0px) translateY(7px);"></div>
                      <div style="background-color:#F4F4F4; height:12.5px; transform:rotate(-45deg) translateX(3px) translateY(1px); width:12.5px; flex-grow:0; margin-right:14px; margin-left:2px;"></div>
                      <div style="background-color:#F4F4F4; border-radius:50%; height:12.5px; width:12.5px; transform:translateX(9px) translateY(-18px);"></div>
                    </div>
                    <div style="margin-left:8px;">
                      <div style="background-color:#F4F4F4; border-radius:50%; flex-grow:0; height:20px; width:20px;"></div>
                      <div style="width:0; height:0; border-top:2px solid transparent; border-left:6px solid #f4f4f4; border-bottom:2px solid transparent; transform:translateX(16px) translateY(-4px) rotate(30deg);"></div>
                    </div>
                    <div style="margin-left:auto;">
                      <div style="width:0px; border-top:8px solid #F4F4F4; border-right:8px solid transparent; transform:translateY(16px);"></div>
                      <div style="background-color:#F4F4F4; flex-grow:0; height:12px; width:16px; transform:translateY(-4px);"></div>
                      <div style="width:0; height:0; border-top:8px solid #F4F4F4; border-left:8px solid transparent; transform:translateY(-4px) translateX(8px);"></div>
                    </div>
                  </div>
                </a>
              </div>
            </blockquote>
            <script async src="//www.instagram.com/embed.js"></script>

            <!-- Tap detection script -->
            <script>
              document.addEventListener('click', function(e) {
                console.log('Tapped!!!');
                console.log('Tap target:', e.target);
              }, true);

              document.addEventListener('touchstart', function(e) {
                console.log('Tapped!!! (touchstart)');
                console.log('Touch target:', e.target);
              }, true);
            </script>
          </div>
        </div>
      </body>
      </html>
    ''';
  }

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
      if (_webEmbedViewType == null) {
        // This case should ideally not be reached if initState completes successfully.
        return SizedBox(
          height: widget.height, // Fallback height from widget
          width: double.infinity,
          child: Center(child: Text("Error initializing web embed view type.")),
        );
      }
      // MODIFIED: Call the conditionally imported function
      return instagram_web.buildInstagramWebViewForWeb(_webEmbedViewType!);
    }

    // Mobile specific WebViewWidget implementation
    final double containerHeight = widget.height; // Use widget.height for mobile
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
          child: WebViewWidget(controller: controller), // controller is initialized only for mobile
        ),
        if (isLoading) // isLoading is managed by mobile path
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
