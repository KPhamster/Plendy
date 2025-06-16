import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class FacebookPreviewWidget extends StatefulWidget {
  final String url;
  final double height;
  final Function(WebViewController) onWebViewCreated;
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
  State<FacebookPreviewWidget> createState() => _FacebookPreviewWidgetState();
}

class _FacebookPreviewWidgetState extends State<FacebookPreviewWidget> {
  WebViewController? controller;
  bool isLoading = true;
  bool hasError = false;
  String? errorMessage;
  bool _isInitialized = false;
  bool _isExpanded = false;
  
  // Cancellation tokens for operations
  int _loadingDelayOperationId = 0;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _initWebViewController();
    }
  }
  
  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  void _initWebViewController() {
    if (kIsWeb) return;

    try {
      final webViewController = WebViewController();
      
      if (!mounted || _isDisposed) return;
      
      webViewController
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000))
        ..setUserAgent(
            "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Mobile Safari/537.36")
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {},
            onPageStarted: (String url) {
              if (!mounted || _isDisposed) return;
              
              setState(() {
                isLoading = true;
                hasError = false;
                errorMessage = null;
              });
            },
            onPageFinished: (String url) {
              if (!mounted || _isDisposed) return;
              
              try {
                widget.onPageFinished(url);
              } catch (e) {
                // Handle error silently in production
                if (kDebugMode) {
                  print("Error in onPageFinished callback: $e");
                }
              }
              
              // Set loading to false after a short delay
              final currentLoadingOperationId = ++_loadingDelayOperationId;
              
              Future.delayed(const Duration(milliseconds: 500), () {
                if (!mounted || _isDisposed || _loadingDelayOperationId != currentLoadingOperationId) return;
                
                setState(() {
                  isLoading = false;
                });
              });
            },
            onWebResourceError: (WebResourceError error) {
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
            onNavigationRequest: (NavigationRequest request) {
              // Allow Facebook navigation
              if (kDebugMode) {
                print("Facebook WebView navigation to: ${request.url}");
              }
              return NavigationDecision.navigate;
            },
          ),
        );
        
      if (!mounted || _isDisposed) return;
      
      setState(() {
        controller = webViewController;
        _isInitialized = true;
      });
      
      // Notify parent widget
      widget.onWebViewCreated(webViewController);
      
      // Load the Facebook URL directly
      webViewController.loadRequest(Uri.parse(widget.url));
      
    } catch (e) {
      if (kDebugMode) {
        print("Error initializing Facebook WebView: $e");
      }
      if (!mounted || _isDisposed) return;
      
      setState(() {
        hasError = true;
        errorMessage = "Failed to initialize preview: $e";
        isLoading = false;
      });
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
      if (kDebugMode) {
        print('Could not launch ${widget.url}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      // Web platform - show simple fallback
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

    // Mobile specific WebViewWidget implementation
    final double containerHeight = _isExpanded ? 800 : widget.height;
    
    // Show loading or error state if controller is not initialized
    if (!_isInitialized || controller == null) {
      return Container(
        height: containerHeight,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: hasError
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Unable to load Facebook content',
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
                )
              : Column(
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
      );
    }
    
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: WebViewWidget(controller: controller!),
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
