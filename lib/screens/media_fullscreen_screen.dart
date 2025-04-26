import 'package:flutter/material.dart';
import 'receive_share/widgets/instagram_preview_widget.dart'
    as instagram_widget;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../models/experience.dart';
import '../services/experience_service.dart';
import '../models/shared_media_item.dart';
import '../models/user_category.dart';
import 'experience_page_screen.dart';

class MediaFullscreenScreen extends StatefulWidget {
  final List<SharedMediaItem> instagramUrls;
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
  late List<SharedMediaItem> _localInstagramItems;
  bool _didDataChange = false;
  // ADDED: State for storing other associated experiences and categories
  bool _isLoadingOtherExperiences = true;
  Map<String, List<Experience>> _otherAssociatedExperiences = {};
  Map<String, UserCategory> _fetchedCategories = {}; // Cache for category icons

  @override
  void initState() {
    super.initState();
    // Initialize local list from widget property
    _localInstagramItems = List<SharedMediaItem>.from(widget.instagramUrls);
    // ADDED: Sort the local list by createdAt descending (most recent first)
    _localInstagramItems.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    // ADDED: Load other experience data after initial build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadOtherExperienceData();
    });
  }

  // ADDED: Method to load data about other experiences linked to the media items
  Future<void> _loadOtherExperienceData() async {
    print("[_loadOtherExperienceData] Starting..."); // DEBUG
    if (!mounted) return;
    setState(() {
      _isLoadingOtherExperiences = true;
    });

    final Map<String, List<Experience>> otherExperiencesMap = {};
    final Set<String> otherExperienceIds = {};
    final Set<String> requiredCategoryNames = {};

    print(
        "[_loadOtherExperienceData] Comparing against current Experience ID: ${widget.experience.id}"); // DEBUG

    // 1. Collect all *other* experience IDs
    for (final item in _localInstagramItems) {
      print(
          "[_loadOtherExperienceData] Processing item ${item.id} (Path: ${item.path}) with experienceIds: ${item.experienceIds}"); // DEBUG
      final otherIds =
          item.experienceIds.where((id) => id != widget.experience.id).toList();
      if (otherIds.isNotEmpty) {
        otherExperienceIds.addAll(otherIds);
      }
    }

    print(
        "[_loadOtherExperienceData] Found other experience IDs: $otherExperienceIds"); // DEBUG

    // 2. Fetch other experiences if any exist
    Map<String, Experience> fetchedExperiencesById = {};
    if (otherExperienceIds.isNotEmpty) {
      try {
        // Fetch experiences individually using Future.wait
        final List<Experience?> experienceFutures = await Future.wait(
            otherExperienceIds
                .map((id) => widget.experienceService.getExperience(id))
                .toList());

        final List<Experience> experiences = experienceFutures
            .whereType<Experience>()
            .toList(); // Filter out nulls

        print(
            "[_loadOtherExperienceData] Fetched ${experiences.length} other experiences."); // DEBUG

        fetchedExperiencesById = {for (var exp in experiences) exp.id: exp};
        // Collect required category names from fetched experiences
        for (final exp in experiences) {
          if (exp.category.isNotEmpty) {
            requiredCategoryNames.add(exp.category);
          }
        }
      } catch (e) {
        print("Error fetching other experiences: $e");
        // Handle error appropriately, maybe show a message
      }
    }

    // 3. Fetch required categories if any exist
    Map<String, UserCategory> fetchedCategoriesByName = {};
    if (requiredCategoryNames.isNotEmpty) {
      try {
        // Fetch ALL categories once and create a lookup map
        final allUserCategories =
            await widget.experienceService.getUserCategories();
        fetchedCategoriesByName = {
          for (var cat in allUserCategories) cat.name: cat
        };
        print(
            "[_loadOtherExperienceData] Fetched ${fetchedCategoriesByName.length} categories."); // DEBUG
      } catch (e) {
        print("Error fetching user categories: $e");
        // Handle error - icons might be missing
      }
    }

    // 4. Build the map for the state
    for (final item in _localInstagramItems) {
      final otherIds =
          item.experienceIds.where((id) => id != widget.experience.id).toList();
      if (otherIds.isNotEmpty) {
        final associatedExps = otherIds
            .map((id) => fetchedExperiencesById[id])
            .where((exp) => exp != null)
            .cast<Experience>()
            .toList();
        // Sort them alphabetically for consistent display
        associatedExps.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        otherExperiencesMap[item.path] = associatedExps;
      }
    }

    print(
        "[_loadOtherExperienceData] Built map for UI: ${otherExperiencesMap.keys.length} items have other experiences."); // DEBUG

    if (mounted) {
      setState(() {
        _otherAssociatedExperiences = otherExperiencesMap;
        _fetchedCategories = fetchedCategoriesByName;
        _isLoadingOtherExperiences = false;
        print("[_loadOtherExperienceData] Set state: isLoading=false"); // DEBUG
      });
    }
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
        // --- REFACTORED Deletion Logic --- START ---
        // Find the matching SharedMediaItem in the local list
        // MODIFIED: Use try-catch instead of orElse
        SharedMediaItem? itemToRemove;
        try {
          itemToRemove = _localInstagramItems
              .firstWhere((item) => item.path == urlToDelete);
        } catch (e) {
          // Handle StateError if not found
          itemToRemove = null;
        }

        if (itemToRemove == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Error: Media item not found locally.')),
            );
          }
          return; // Exit if not found
        }

        // Call the service to remove the link between the experience and the media item
        await widget.experienceService.removeExperienceLinkFromMediaItem(
            itemToRemove.id, widget.experience.id);
        print(
            "Removed link between experience ${widget.experience.id} and media ${itemToRemove.id} (from Fullscreen)");

        // --- Old logic removed ---
        /*
        final List<SharedMediaItem> currentPaths = List<SharedMediaItem>.from(
            widget.experience.sharedMediaPaths ?? []);
        final indexToRemove = currentPaths.indexWhere((item) => item.path == urlToDelete);
        bool removed = false;
        List<SharedMediaItem> updatedPaths = List.from(currentPaths);
        if (indexToRemove != -1) {
          updatedPaths.removeAt(indexToRemove);
          removed = true;
        }
        if (removed) {
           Experience updatedExperience = widget.experience.copyWith(
             sharedMediaItemIds: updatedPaths.map((item) => item.id).toList(), // Corrected field
             updatedAt: DateTime.now(),
           );
           await widget.experienceService.updateExperience(updatedExperience);
        */
        // --- End Old logic ---

        // Update local state to remove the item visually
        if (mounted) {
          setState(() {
            _localInstagramItems
                .removeWhere((item) => item.path == urlToDelete);
            _didDataChange = true; // Mark that a change occurred
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Media item removed.')),
          );
        }
        // --- REFACTORED Deletion Logic --- END ---
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
          title: const Text('Content'),
          // Back button is automatically added, WillPopScope handles its pop result
        ),
        body: ListView.builder(
          // Use similar padding as the tab view for consistency
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          // MODIFIED: Use local item list length
          itemCount: _localInstagramItems.length,
          itemBuilder: (context, index) {
            // MODIFIED: Get item and extract url (path)
            final item = _localInstagramItems[index];
            final url = item.path;
            // ADDED: Get other associated experiences for this URL
            final List<Experience> otherExperiences =
                _otherAssociatedExperiences[url] ?? [];

            // --- DEBUG PRINTS --- START ---
            print("[itemBuilder index $index] URL: $url");
            print(
                "[itemBuilder index $index] _isLoadingOtherExperiences: $_isLoadingOtherExperiences");
            print(
                "[itemBuilder index $index] otherExperiences found: ${otherExperiences.length}");
            final bool shouldShowSection =
                !_isLoadingOtherExperiences && otherExperiences.isNotEmpty;
            print(
                "[itemBuilder index $index] Should show section: $shouldShowSection");
            // --- DEBUG PRINTS --- END ---

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
                  // --- ADDED: Section for Other Linked Experiences --- START ---
                  if (shouldShowSection) // Use the calculated boolean
                    Padding(
                      padding: const EdgeInsets.only(top: 12.0, bottom: 4.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6.0),
                            child: Text(
                              otherExperiences.length == 1
                                  ? 'Also linked to:'
                                  : 'Also linked to (${otherExperiences.length}):',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                            ),
                          ),
                          // List the other experiences
                          ...otherExperiences.map((exp) {
                            final categoryName = exp.category;
                            final categoryIcon =
                                _fetchedCategories[categoryName]?.icon ??
                                    '❓'; // Use fetched icon or default
                            final address = exp.location.address;
                            final bool hasAddress =
                                address != null && address.isNotEmpty;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4.0),
                              child: InkWell(
                                onTap: () async {
                                  print(
                                      'Tapped on other experience ${exp.name} from fullscreen');
                                  final category =
                                      _fetchedCategories[categoryName] ??
                                          UserCategory(
                                              id: '',
                                              name: categoryName,
                                              icon: '❓',
                                              ownerUserId:
                                                  ''); // Fallback category

                                  // Await result and potentially refresh if the main screen needs it (though unlikely from here)
                                  final result = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          ExperiencePageScreen(
                                        experience: exp,
                                        category:
                                            category, // Pass the found/fallback category
                                      ),
                                    ),
                                  );
                                  // Optionally handle result if needed (e.g., _loadOtherExperienceData() if modification is possible)
                                  if (result == true && mounted) {
                                    // Might need a more targeted refresh depending on what ExperiencePageScreen returns
                                    _loadOtherExperienceData();
                                  }
                                },
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          right: 8.0, top: 2.0),
                                      child: Text(categoryIcon,
                                          style: TextStyle(fontSize: 14)),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            exp.name,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                    fontWeight:
                                                        FontWeight.w500),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                          if (hasAddress)
                                            Text(
                                              address,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                      color: Colors.black54),
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  // --- ADDED: Section for Other Linked Experiences --- END ---
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
