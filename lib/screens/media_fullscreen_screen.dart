import 'package:flutter/material.dart';
import 'receive_share/widgets/instagram_preview_widget.dart'; // Adjust import path if needed

class MediaFullscreenScreen extends StatelessWidget {
  final List<String> instagramUrls;
  final Future<void> Function(String) launchUrlCallback;

  const MediaFullscreenScreen({
    super.key,
    required this.instagramUrls,
    required this.launchUrlCallback,
  });

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
        itemCount: instagramUrls.length,
        itemBuilder: (context, index) {
          final url = instagramUrls[index];
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
                  child: InstagramPreviewWidget(
                    url: url,
                    launchUrlCallback: launchUrlCallback,
                    // Use default collapsed height (400) or a specific one for fullscreen?
                    // Let's use a slightly larger one for fullscreen
                    collapsedHeight: 840.0, // Or keep default 400.0
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
