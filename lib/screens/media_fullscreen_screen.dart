import 'package:flutter/material.dart';
import 'receive_share/widgets/instagram_preview_widget.dart'
    as instagram_widget;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../models/experience.dart';
import '../services/experience_service.dart';

class MediaFullscreenScreen extends StatefulWidget {
  final List<String> instagramUrls;
  final Future<void> Function(String) launchUrlCallback;
  final Experience experience;
  final ExperienceService experienceService;

  const MediaFullscreenScreen({
    super.key,
    required this.instagramUrls,
    required this.launchUrlCallback,
    required this.experience,
    required this.experienceService,
  });

  @override
  _MediaFullscreenScreenState createState() => _MediaFullscreenScreenState();
}

class _MediaFullscreenScreenState extends State<MediaFullscreenScreen> {
  // State map for expansion
  final Map<String, bool> _expansionStates = {};
  // ADDED: Local mutable list for URLs and change tracking flag
  late List<String> _localInstagramUrls;
  bool _didDataChange = false;

  @override
  void initState() {
    super.initState();
    // Initialize local list from widget property
    _localInstagramUrls = List<String>.from(widget.instagramUrls);
  }

  Future<void> _confirmAndDelete(String urlToDelete) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content:
              const Text('Are you sure you want to remove this media item?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('Delete'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      try {
        final List<String> updatedPaths =
            List<String>.from(widget.experience.sharedMediaPaths ?? []);
        bool removed = updatedPaths.remove(urlToDelete);

        if (removed) {
          Experience updatedExperience = widget.experience.copyWith(
            sharedMediaPaths: updatedPaths,
            updatedAt: DateTime.now(),
          );
          await widget.experienceService.updateExperience(updatedExperience);

          // Pop with true to indicate success/change
          // Navigator.of(context).pop(true); // REMOVED: Don't pop automatically

          // ADDED: Update local state instead of popping
          if (mounted) {
            setState(() {
              _localInstagramUrls.remove(urlToDelete);
              _didDataChange = true; // Mark that a change occurred
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Media item removed.')),
            );
          }
        } else {
          if (mounted) {
            // ADDED: Check mounted before showing SnackBar
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Error: Media item not found.')),
            );
          }
        }
      } catch (e) {
        print("Error deleting media path from fullscreen: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error removing media item: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ADDED: Wrap with WillPopScope to return the change status
    return WillPopScope(
      onWillPop: () async {
        // Pop with the value of _didDataChange
        Navigator.of(context).pop(_didDataChange);
        // Return false because we handled the pop manually
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Media'),
          // Back button is automatically added, WillPopScope handles its pop result
        ),
        body: ListView.builder(
          // Use similar padding as the tab view for consistency
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          // MODIFIED: Use local list length
          itemCount: _localInstagramUrls.length,
          itemBuilder: (context, index) {
            // MODIFIED: Use local list to get URL
            final url = _localInstagramUrls[index];
            // Replicate the Column + Number Bubble + Card structure
            return Padding(
              // ADDED: Use ValueKey based on the URL for stable identification
              key: ValueKey(url),
              // Add padding below each item for vertical spacing
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                      height: (_expansionStates[url] ?? false)
                          ? 1200.0
                          : 840.0, // Use fullscreen height
                      launchUrlCallback: widget.launchUrlCallback,
                      // Add required callbacks
                      onWebViewCreated: (controller) {},
                      onPageFinished: (url) {},
                    ),
                  ),
                  // Add spacing before buttons
                  const SizedBox(height: 8),
                  // Buttons Row - REFRACTORED to use Stack for centering
                  SizedBox(
                    height: 48, // Provide height constraint for Stack alignment
                    child: Stack(
                      children: [
                        // Instagram Button (Centered)
                        Align(
                          alignment: Alignment.center, // Alignment(0.0, 0.0)
                          child: IconButton(
                            icon: const Icon(FontAwesomeIcons.instagram),
                            color: const Color(0xFFE1306C), // Instagram color
                            iconSize: 32, // Standard size
                            tooltip: 'Open in Instagram',
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                            onPressed: () => widget.launchUrlCallback(url),
                          ),
                        ),
                        // Expand/Collapse Button (Halfway between Center and Right)
                        Align(
                          alignment: const Alignment(0.5, 0.0), // Halfway point
                          child: IconButton(
                            icon: Icon((_expansionStates[url] ?? false)
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen),
                            iconSize: 24,
                            color: Colors.blue,
                            tooltip: (_expansionStates[url] ?? false)
                                ? 'Collapse'
                                : 'Expand',
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets
                                .zero, // Remove padding for precise alignment
                            onPressed: () {
                              setState(() {
                                _expansionStates[url] =
                                    !(_expansionStates[url] ?? false);
                              });
                            },
                          ),
                        ),
                        // Delete Button (Right Edge)
                        Align(
                          alignment:
                              Alignment.centerRight, // Alignment(1.0, 0.0)
                          child: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            iconSize: 24,
                            color: Colors.red[700],
                            tooltip: 'Delete Media',
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12), // Keep some padding from edge
                            onPressed: () => _confirmAndDelete(url),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ), // End WillPopScope
    );
  }
}
