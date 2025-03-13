import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'dart:io';
import 'package:any_link_preview/any_link_preview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ReceiveShareScreen extends StatefulWidget {
  final List<SharedMediaFile> sharedFiles;
  final VoidCallback onCancel;

  const ReceiveShareScreen({
    Key? key,
    required this.sharedFiles,
    required this.onCancel,
  }) : super(key: key);

  @override
  _ReceiveShareScreenState createState() => _ReceiveShareScreenState();
}

class _ReceiveShareScreenState extends State<ReceiveShareScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Shared Content'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: Icon(Icons.close),
            onPressed: widget.onCancel,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: widget.sharedFiles.isEmpty
                  ? Center(child: Text('No shared content received'))
                  : ListView.builder(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      itemCount: widget.sharedFiles.length,
                      itemBuilder: (context, index) {
                        final file = widget.sharedFiles[index];
                        return Card(
                          margin: EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Display media content or appropriate icon
                              _buildMediaPreview(file),
                                
                              // Display metadata (only for non-URL content)
                              if (!(file.type == SharedMediaType.text && _isValidUrl(file.path)))
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Type: ${_getMediaTypeString(file.type)}',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      SizedBox(height: 8),
                                      if (file.type != SharedMediaType.text)
                                        Text('Path: ${file.path}'),
                                      if (file.type == SharedMediaType.text && !_isValidUrl(file.path))
                                        Text('Content: ${file.path}'),
                                      if (file.thumbnail != null) ...[
                                        SizedBox(height: 8),
                                        Text('Thumbnail: ${file.thumbnail}'),
                                      ],
                                    ],
                                  ),
                                ),
                              
                              // For URLs, we'll only show the preview and open button
                              if (file.type == SharedMediaType.text && _isValidUrl(file.path))
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Type: ${_getMediaTypeString(file.type)}',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: widget.onCancel,
                      child: Text('Cancel'),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () {
                        // TODO: Implement logic to save or process the shared content
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Content saved')),
                        );
                        widget.onCancel(); // Return to main screen after saving
                      },
                      child: Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }
  
  bool _isValidUrl(String text) {
    // Simple URL validation
    try {
      final uri = Uri.parse(text);
      return uri.hasScheme && uri.hasAuthority;
    } catch (e) {
      return false;
    }
  }

  String _getMediaTypeString(SharedMediaType type) {
    switch (type) {
      case SharedMediaType.image:
        return 'Image';
      case SharedMediaType.video:
        return 'Video';
      case SharedMediaType.file:
        return 'File';
      case SharedMediaType.text:
        return 'Text';
      default:
        return type.toString();
    }
  }

  Widget _buildMediaPreview(SharedMediaFile file) {
    switch (file.type) {
      case SharedMediaType.image:
        return _buildImagePreview(file);
      case SharedMediaType.video:
        return _buildVideoPreview(file);
      case SharedMediaType.text:
        return _buildTextPreview(file);
      case SharedMediaType.file:
      default:
        return _buildFilePreview(file);
    }
  }

  Widget _buildTextPreview(SharedMediaFile file) {
    // Check if it's a URL
    if (_isValidUrl(file.path)) {
      return _buildUrlPreview(file.path);
    } else {
      // Regular text
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(16),
        color: Colors.grey[200],
        child: Text(
          file.path,
          style: TextStyle(fontSize: 16),
        ),
      );
    }
  }

  Widget _buildUrlPreview(String url) {
    // Special handling for Instagram URLs
    if (url.contains('instagram.com')) {
      return _buildInstagramPreview(url);
    }

    return Container(
      height: 250,
      width: double.infinity,
      child: AnyLinkPreview(
        link: url,
        displayDirection: UIDirection.uiDirectionVertical,
        cache: Duration(hours: 1),
        backgroundColor: Colors.white,
        errorWidget: Container(
          color: Colors.grey[200],
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.link, size: 50, color: Colors.blue),
              SizedBox(height: 8),
              Text(
                url,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.blue),
              ),
            ],
          ),
        ),
        onTap: () => _launchUrl(url),
      ),
    );
  }

  Widget _buildInstagramPreview(String url) {
    // Check if it's a reel
    final bool isReel = _isInstagramReel(url);
    
    if (isReel) {
      return InstagramReelEmbed(url: url, onOpen: () => _launchUrl(url));
    } else {
      // Regular Instagram content (fallback to current implementation)
      final String contentId = _extractInstagramId(url);
      
      return InkWell(
        onTap: () => _launchUrl(url),
        child: Container(
          height: 280,
          width: double.infinity,
          color: Colors.white,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Instagram logo or icon
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      Color(0xFFE1306C),
                      Color(0xFFF77737),
                      Color(0xFFFCAF45),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Instagram Content',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 4),
              Text(
                contentId,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontFamily: 'Courier',
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Tap to play video',
                style: TextStyle(
                  color: Colors.grey[700],
                ),
              ),
              SizedBox(height: 16),
              OutlinedButton.icon(
                icon: Icon(Icons.open_in_new),
                label: Text('Open Instagram'),
                onPressed: () => _launchUrl(url),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Color(0xFFE1306C),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  // Check if URL is an Instagram reel
  bool _isInstagramReel(String url) {
    return url.contains('instagram.com/reel') || 
           url.contains('instagram.com/reels') ||
           (url.contains('instagram.com/p') && 
            (url.contains('?img_index=') || url.contains('video_index=') || 
             url.contains('media_index=') || url.contains('?igsh=')));
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

  Widget _buildImagePreview(SharedMediaFile file) {
    try {
      return Container(
        height: 400,
        width: double.infinity,
        child: Image.file(
          File(file.path),
          fit: BoxFit.cover,
        ),
      );
    } catch (e) {
      return Container(
        height: 400,
        width: double.infinity,
        color: Colors.grey[300],
        child: Center(
          child: Icon(Icons.image_not_supported, size: 50),
        ),
      );
    }
  }

  Widget _buildVideoPreview(SharedMediaFile file) {
    return Container(
      height: 400,
      width: double.infinity,
      color: Colors.black87,
      child: Center(
        child: Icon(
          Icons.play_circle_outline,
          size: 70,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildFilePreview(SharedMediaFile file) {
    IconData iconData;
    Color iconColor;
    
    // Determine file type from path extension
    final String extension = file.path.split('.').last.toLowerCase();
    
    if (['pdf'].contains(extension)) {
      iconData = Icons.picture_as_pdf;
      iconColor = Colors.red;
    } else if (['doc', 'docx'].contains(extension)) {
      iconData = Icons.description;
      iconColor = Colors.blue;
    } else if (['xls', 'xlsx'].contains(extension)) {
      iconData = Icons.table_chart;
      iconColor = Colors.green;
    } else if (['ppt', 'pptx'].contains(extension)) {
      iconData = Icons.slideshow;
      iconColor = Colors.orange;
    } else if (['txt', 'rtf'].contains(extension)) {
      iconData = Icons.text_snippet;
      iconColor = Colors.blueGrey;
    } else if (['zip', 'rar', '7z'].contains(extension)) {
      iconData = Icons.folder_zip;
      iconColor = Colors.amber;
    } else {
      iconData = Icons.insert_drive_file;
      iconColor = Colors.grey;
    }
    
    return Container(
      height: 400,
      width: double.infinity,
      color: Colors.grey[200],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(iconData, size: 70, color: iconColor),
            SizedBox(height: 8),
            Text(
              extension.toUpperCase(),
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

// Separate stateful widget for Instagram Reel embeds
class InstagramReelEmbed extends StatefulWidget {
  final String url;
  final VoidCallback onOpen;
  
  const InstagramReelEmbed({Key? key, required this.url, required this.onOpen}) : super(key: key);
  
  @override
  _InstagramReelEmbedState createState() => _InstagramReelEmbedState();
}

class _InstagramReelEmbedState extends State<InstagramReelEmbed> {
  late final WebViewController controller;
  bool isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _initWebViewController();
  }
  
  void _initWebViewController() {
    controller = WebViewController();
    
    // Add JavaScript code to initialize controllers properly for better autoplay support
    final String initialScript = '''
      // Enable autoplay in video elements when they are added to the DOM
      const observer = new MutationObserver(function(mutations) {
        mutations.forEach(function(mutation) {
          if (mutation.addedNodes) {
            mutation.addedNodes.forEach(function(node) {
              // Check if a video element was added
              if (node.nodeName === 'VIDEO') {
                console.log('Video element detected, setting up autoplay');
                node.autoplay = true;
                node.controls = true;
                node.playsInline = true;
                node.muted = false;
                node.play();
              }
              
              // Check for iframes that might contain videos
              if (node.querySelectorAll) {
                const videos = node.querySelectorAll('video');
                videos.forEach(function(video) {
                  video.autoplay = true;
                  video.controls = true;
                  video.playsInline = true;
                  video.muted = false;
                  video.play();
                });
              }
            });
          }
        });
      });
      
      // Start observing the document with the configured parameters
      observer.observe(document, { childList: true, subtree: true });
    ''';
    
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setUserAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")
      ..addJavaScriptChannel(
        'AppJSChannel',
        onMessageReceived: (JavaScriptMessage message) {
          print('JS Channel message: ${message.message}');
        },
      )
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
              if (typeof window.instgrm !== 'undefined') {
                console.log('Processing Instagram embeds');
                window.instgrm.Embeds.process();
                
                // Add a retry mechanism in case the embed takes longer to be fully interactive
                for (let retryCount = 0; retryCount < 5; retryCount++) {
                  setTimeout(function() {
                    // Try to find and click the play button
                    var playButtons = document.querySelectorAll('.sqdOP, ._6CZji, .tCibT, .fXIG0');
                    if (playButtons.length > 0) {
                      console.log('Retry ' + retryCount + ': Found play button, clicking...');
                      playButtons[0].click();
                    }
                    
                    // Try to find the video element and play it
                    var videos = document.querySelectorAll('video');
                    if (videos.length > 0) {
                      console.log('Retry ' + retryCount + ': Found video element, playing...');
                      videos[0].play();
                    }
                    
                    // Try to find any clickable play overlays
                    var overlays = document.querySelectorAll('.fXIG0, ._8jZFn, ._2dDPU, ._9AhH0');
                    if (overlays.length > 0) {
                      console.log('Retry ' + retryCount + ': Found overlay, clicking...');
                      overlays[0].click();
                    }
                    
                    // As a last resort, try to hide play overlays with CSS
                    if (retryCount == 4) { // Only add on last retry
                      try {
                        var style = document.createElement('style');
                        style.textContent = `
                          .sqdOP, ._6CZji, .tCibT, .fXIG0, ._8jZFn, ._2dDPU, ._9AhH0, .QvAa1 {
                            opacity: 0 !important;
                            pointer-events: none !important;
                          }
                          .videoSpritePlayButton, .coreSpritePlayButton {
                            opacity: 0 !important;
                            pointer-events: none !important;
                          }
                        `;
                        document.head.appendChild(style);
                        console.log('Added CSS to hide play buttons');
                      } catch(e) {
                        console.error('Error adding style:', e);
                      }
                    }
                  }, 2000 + (retryCount * 1000));
                }
              } else {
                console.log('Instagram embed.js not loaded properly');
                // Try to load it again manually
                var script = document.createElement('script');
                script.async = true;
                script.src = '//www.instagram.com/embed.js';
                document.body.appendChild(script);
                
                // Try to process embeds after a delay
                setTimeout(function() {
                  if (typeof window.instgrm !== 'undefined') {
                    window.instgrm.Embeds.process();
                  }
                }, 1000);
              }
            ''').then((_) {
              // Set loading to false after a short delay to ensure embed is processed
              Future.delayed(Duration(milliseconds: 1500), () {
                if (mounted) {
                  setState(() {
                    isLoading = false;
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
              widget.onOpen();
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
    
    // Create a simpler direct embed approach that bypasses Instagram's player overlay
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
            flex-direction: column;
            justify-content: center;
            align-items: center;
            text-align: center;
          }
          iframe {
            width: 100%;
            height: 90vh;
            border: none;
          }
          .loading {
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: white;
            display: flex;
            flex-direction: column;
            justify-content: center;
            align-items: center;
            z-index: 10;
          }
          .loading-text {
            margin-top: 16px;
            font-weight: bold;
          }
          .spinner {
            border: 5px solid #f3f3f3;
            border-top: 5px solid #E1306C;
            border-radius: 50%;
            width: 50px;
            height: 50px;
            animation: spin 1s linear infinite;
          }
          @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
          }
        </style>
      </head>
      <body>
        <div class="container">
          <!-- Direct iframe embed to bypass the play button overlay -->
          <iframe 
            src="${cleanUrl}embed/" 
            frameborder="0" 
            scrolling="no" 
            allowtransparency="true" 
            allowfullscreen="true" 
            allow="autoplay; encrypted-media"
          ></iframe>
          
          <!-- Loading overlay that will be removed by JavaScript -->
          <div class="loading" id="loadingOverlay">
            <div class="spinner"></div>
            <p class="loading-text">Loading Instagram Content...</p>
          </div>
        </div>
        
        <script>
          // Remove loading overlay after a short delay
          setTimeout(function() {
            document.getElementById('loadingOverlay').style.display = 'none';
          }, 3000);
          
          // Attempt to trigger play on any videos
          function autoplayVideos() {
            try {
              // Try to find videos in the iframe
              const videos = document.querySelectorAll('video, iframe');
              videos.forEach(function(video) {
                console.log('Found video element, attempting to autoplay');
                video.play();
                video.setAttribute('autoplay', '');
                video.setAttribute('playsinline', '');
                video.setAttribute('muted', 'false');
                video.muted = false;
              });
              
              // Try to click any play buttons
              const playButtons = document.querySelectorAll('[role="button"], button, .play-button');
              playButtons.forEach(function(button) {
                console.log('Found button, attempting to click');
                button.click();
              });
            } catch (e) {
              console.error('Error in autoplay:', e);
            }
          }
          
          // Try to autoplay videos multiple times
          setInterval(autoplayVideos, 1000);
        </script>
      </body>
      </html>
    ''';
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              height: 1000, // Increased height for better visibility
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
                height: 1000,
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
        ),
        SizedBox(height: 8),
        OutlinedButton.icon(
          icon: Icon(Icons.open_in_new),
          label: Text('Open in Instagram'),
          onPressed: widget.onOpen,
          style: OutlinedButton.styleFrom(
            foregroundColor: Color(0xFFE1306C),
          ),
        ),
      ],
    );
  }
}
