import 'package:flutter/material.dart';
import 'receive_share/widgets/instagram_preview_widget.dart'
    as instagram_widget;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class MediaFullscreenScreen extends StatefulWidget {
  final List<String> instagramUrls;
  final Future<void> Function(String) launchUrlCallback;

  const MediaFullscreenScreen({
    super.key,
    required this.instagramUrls,
    required this.launchUrlCallback,
  });

  @override
  _MediaFullscreenScreenState createState() => _MediaFullscreenScreenState();
}

class _MediaFullscreenScreenState extends State<MediaFullscreenScreen> {
  // State map for expansion
  final Map<int, bool> _expansionStates = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Media'),
        // Back button is automatically added by Navigator
      ),
      body: ListView.builder(
        // Use similar padding as the tab view for consistency
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        itemCount: widget.instagramUrls.length,
        itemBuilder: (context, index) {
          final url = widget.instagramUrls[index];
          // Replicate the Column + Number Bubble + Card structure
          return Padding(
            // Add padding below each item for vertical spacing
            padding: const EdgeInsets.only(bottom: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Display the number inside a bubble
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor:
                        Theme.of(context).primaryColor.withOpacity(0.8),
                    child: Text(
                      '${index + 1}', // Number without period
                      style: TextStyle(
                        fontSize: 14.0,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                // The Card containing the preview
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 2.0,
                  clipBehavior: Clip.antiAlias,
                  child: instagram_widget.InstagramWebView(
                    url: url,
                    // Calculate height based on state
                    height: (_expansionStates[index] ?? false)
                        ? 1200.0
                        : 500.0, // Use fullscreen height
                    launchUrlCallback: widget.launchUrlCallback,
                    // Add required callbacks
                    onWebViewCreated: (controller) {},
                    onPageFinished: (url) {},
                  ),
                ),
                // Add spacing before buttons
                const SizedBox(height: 8),
                // Buttons Row - managed by this parent screen
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(FontAwesomeIcons.instagram),
                      color: const Color(0xFFE1306C), // Instagram color
                      iconSize: 24,
                      tooltip: 'Open in Instagram',
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      onPressed: () => widget.launchUrlCallback(url),
                    ),
                    const SizedBox(width: 16), // Increased spacing slightly
                    IconButton(
                      icon: Icon((_expansionStates[index] ?? false)
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen),
                      iconSize: 24,
                      color: Colors.blue,
                      tooltip: (_expansionStates[index] ?? false)
                          ? 'Collapse'
                          : 'Expand',
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      onPressed: () {
                        setState(() {
                          _expansionStates[index] =
                              !(_expansionStates[index] ?? false);
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
