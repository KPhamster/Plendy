import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:io'; // For Platform checks

class InstagramPreviewWidget extends StatefulWidget {
  final String url;
  final Future<void> Function(String) launchUrlCallback;

  const InstagramPreviewWidget({
    super.key,
    required this.url,
    required this.launchUrlCallback,
  });

  @override
  _InstagramPreviewWidgetState createState() => _InstagramPreviewWidgetState();
}

class _InstagramPreviewWidgetState extends State<InstagramPreviewWidget> {
  late final WebViewController controller;
  bool isLoading = true;
  bool isExpanded = false; // Track whether the preview is expanded

  @override
  void initState() {
    super.initState();
    _initWebViewController();
  }

  // Method to simulate a tap in the embed container
  void _simulateEmbedTap() {
    // Calculate center of content window
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

            // If no specific element found, click in the center of the embed
            var rect = embedContainer.getBoundingClientRect();
            var centerX = rect.left + rect.width / 2;
            var centerY = rect.top + rect.height / 2;

            console.log('Simulating click at center:', centerX, centerY);

            // Create and dispatch click event
            var clickEvent = new MouseEvent('click', {
              view: window,
              bubbles: true,
              cancelable: true,
              clientX: centerX,
              clientY: centerY
            });

            embedContainer.dispatchEvent(clickEvent);
            return;
          }

          // Second approach: Try to find a media player or embed
          var player = document.querySelector('iframe[src*="instagram.com"]');
          if (player) {
            console.log('Found Instagram iframe, simulating click');
            player.click();
            return;
          }

          console.log('Instagram embed container not found');
        } catch (e) {
          console.error('Error in auto-click script:', e);
        }
      })();
    ''');
  }

  void _initWebViewController() {
    controller = WebViewController();

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setUserAgent(
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Progress is reported during page load
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                isLoading = true;
              });
            }
          },
          onPageFinished: (String url) {
            // Try to manually process Instagram embeds
            controller.runJavaScript('''
              console.log('Page finished loading');

              // Add tap detection to log when the user taps
              document.addEventListener('click', function(e) {
                console.log('Tapped!!!');
                console.log('Tap target:', e.target);
              }, true);

              document.addEventListener('touchstart', function(e) {
                console.log('Tapped!!! (touchstart)');
                console.log('Touch target:', e.target);
              }, true);
            ''').then((_) {
              // Set loading to false after a short delay to ensure embed is processed
              Future.delayed(Duration(milliseconds: 1500), () {
                if (mounted) {
                  setState(() {
                    isLoading = false;
                  });

                  // Auto-simulate a tap in the center of the embed after loading
                  Future.delayed(Duration(milliseconds: 500), () {
                    _simulateEmbedTap();

                    // Try again after a longer delay in case the first attempt doesn't work
                    Future.delayed(Duration(seconds: 2), () {
                      if (mounted) {
                        _simulateEmbedTap();
                      }
                    });
                  });
                }
              });
            });
          },
          onWebResourceError: (WebResourceError error) {
            print("WebView Error: ${error.description}");
            if (mounted) {
              setState(() {
                isLoading = false;
              });
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            // Intercept navigation to external links
            if (!request.url.contains('instagram.com') &&
                !request.url.contains('cdn.instagram.com') &&
                !request.url.contains('cdninstagram.com')) {
              widget.launchUrlCallback(
                  request.url); // Use callback to launch external URLs
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadHtmlString(_generateInstagramEmbedHtml(widget.url));
  }

  // Clean Instagram URL for proper embedding
  String _cleanInstagramUrl(String url) {
    // Try to parse the URL
    try {
      // Parse URL
      Uri uri = Uri.parse(url);

      // Get base path without query parameters
      String cleanUrl = '${uri.scheme}://${uri.host}${uri.path}';

      // Ensure trailing slash if needed
      if (!cleanUrl.endsWith('/')) {
        cleanUrl = '$cleanUrl/';
      }

      return cleanUrl;
    } catch (e) {
      // If parsing fails, try basic string manipulation
      if (url.contains('?')) {
        url = url.split('?')[0];
      }

      // Ensure trailing slash if needed
      if (!url.endsWith('/')) {
        url = '$url/';
      }

      return url;
    }
  }

  // Generate HTML for embedding Instagram content
  String _generateInstagramEmbedHtml(String url) {
    // Clean the URL to ensure proper embedding
    final String cleanUrl = _cleanInstagramUrl(url);

    // Create an Instagram embed with tap detection
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
            overflow: hidden;
            background-color: white;
          }
          .container {
            position: relative;
            height: 100%;
            display: flex;
            justify-content: center;
            align-items: center;
          }
          .embed-container {
            height: 100%;
            max-width: 540px;
            margin: 0 auto;
          }
          iframe {
            border: none !important;
            margin: 0 !important;
            padding: 0 !important;
            height: 100% !important;
          }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="embed-container">
            <blockquote class="instagram-media" data-instgrm-captioned data-instgrm-permalink="$cleanUrl"
              data-instgrm-version="14" style="background:#FFF; border:0; border-radius:3px;
              box-shadow:0 0 1px 0 rgba(0,0,0,0.5),0 1px 10px 0 rgba(0,0,0,0.15);
              margin: 1px; max-width:540px; min-width:326px; padding:0; width:99.375%; width:-webkit-calc(100% - 2px); width:calc(100% - 2px);">
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

  @override
  Widget build(BuildContext context) {
    // Define the container height based on expansion state
    final double containerHeight = isExpanded ? 1200 : 400;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              isExpanded = !isExpanded; // Toggle expansion state
            });
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: containerHeight, // Use dynamic height based on state
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
                  height: containerHeight, // Use dynamic height based on state
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
              // No tap to expand indicator
            ],
          ),
        ),
        SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              icon: Icon(Icons.open_in_new),
              label: Text('Open in Instagram'),
              onPressed: () =>
                  widget.launchUrlCallback(widget.url), // Use callback
              style: OutlinedButton.styleFrom(
                foregroundColor: Color(0xFFE1306C),
              ),
            ),
            SizedBox(width: 8),
            OutlinedButton.icon(
              icon: Icon(isExpanded ? Icons.fullscreen_exit : Icons.fullscreen),
              label: Text(isExpanded ? 'Collapse' : 'Expand'),
              onPressed: () {
                setState(() {
                  isExpanded = !isExpanded;
                });
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // <<< HELPER METHODS >>>

  // Check if URL is an Instagram reel
  bool _isInstagramReel(String url) {
    return url.contains('instagram.com/reel') ||
        url.contains('instagram.com/reels') ||
        (url.contains('instagram.com/p') &&
            (url.contains('?img_index=') ||
                url.contains('video_index=') ||
                url.contains('media_index=') ||
                url.contains('?igsh=')));
  }

  // Extract content ID from Instagram URL
  String _extractInstagramId(String url) {
    // Try to extract the content ID from the URL
    try {
      // Remove query parameters if present
      String cleanUrl = url;
      if (url.contains('?')) {
        cleanUrl = url.split('?')[0];
      }

      // Split the URL by slashes
      List<String> pathSegments = cleanUrl.split('/');

      // Instagram URLs usually have the content ID as one of the last segments
      // For reels: instagram.com/reel/{content_id}
      if (pathSegments.length > 2) {
        for (int i = pathSegments.length - 1; i >= 0; i--) {
          if (pathSegments[i].isNotEmpty &&
              pathSegments[i] != 'instagram.com' &&
              pathSegments[i] != 'reel' &&
              pathSegments[i] != 'p' &&
              !pathSegments[i].startsWith('http')) {
            return pathSegments[i];
          }
        }
      }

      return 'Instagram Content';
    } catch (e) {
      return 'Instagram Content';
    }
  }
}
