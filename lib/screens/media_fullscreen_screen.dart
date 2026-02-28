import 'package:flutter/material.dart';
import 'receive_share/widgets/instagram_preview_widget.dart'
    as instagram_widget;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../models/experience.dart';
import '../services/experience_service.dart';
import '../models/shared_media_item.dart';
import '../models/user_category.dart';
import '../models/color_category.dart';
import 'experience_page_screen.dart';
import 'package:plendy/utils/haptic_feedback.dart';
import '../config/media_fullscreen_help_content.dart';
import '../models/media_fullscreen_help_target.dart';
import '../widgets/screen_help_controller.dart';

class MediaFullscreenScreen extends StatefulWidget {
  final List<SharedMediaItem> mediaItems;
  final Future<void> Function(String) launchUrlCallback;
  final Experience experience;
  final ExperienceService experienceService;

  const MediaFullscreenScreen({
    super.key,
    required this.mediaItems,
    required this.launchUrlCallback,
    required this.experience,
    required this.experienceService,
  });

  @override
  _MediaFullscreenScreenState createState() => _MediaFullscreenScreenState();
}

class _MediaFullscreenScreenState extends State<MediaFullscreenScreen>
    with TickerProviderStateMixin {
  late PageController _pageController;
  int _currentIndex = 0;
  // State map for expansion
  final Map<String, bool> _expansionStates = {};
  // ADDED: Local mutable list for URLs and change tracking flag
  late List<SharedMediaItem> _localInstagramItems;
  bool _didDataChange = false;
  // ADDED: State for storing other associated experiences and categories
  bool _isLoadingOtherExperiences = true;
  Map<String, List<Experience>> _otherAssociatedExperiences = {};
  Map<String, UserCategory> _fetchedCategories = {}; // Cache for category icons
  // --- ADDED: State for Color Categories --- START ---
  List<ColorCategory> _userColorCategories = [];
  final bool _isLoadingColorCategories = true;
  // --- ADDED: State for Color Categories --- END ---
  late final ScreenHelpController<MediaFullscreenHelpTargetId> _help;

  @override
  void initState() {
    super.initState();
    _help = ScreenHelpController<MediaFullscreenHelpTargetId>(
      vsync: this,
      content: mediaFullscreenHelpContent,
      setState: setState,
      isMounted: () => mounted,
      defaultFirstTarget: MediaFullscreenHelpTargetId.helpButton,
    );
    _pageController = PageController();
    _localInstagramItems = List<SharedMediaItem>.from(widget.mediaItems);
    _localInstagramItems.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadOtherExperienceData();
      _loadColorCategories();
    });
  }

  @override
  void dispose() {
    _help.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadOtherExperienceData() async {
    print("[Fullscreen - _loadOtherExperienceData] Starting...");
    if (!mounted || widget.mediaItems.isEmpty) {
      print(
          "[Fullscreen - _loadOtherExperienceData] Not mounted or no media items. Aborting.");
      setState(() => _isLoadingOtherExperiences = false);
      return;
    }

    setState(() {
      _isLoadingOtherExperiences = true;
    });

    final Map<String, List<Experience>> otherExperiencesMap = {};
    final Set<String> otherExperienceIds = {};
    final Set<String?> requiredCategoryIds = {};

    for (final item in widget.mediaItems) {
      final otherIds =
          item.experienceIds.where((id) => id != widget.experience.id).toList();
      if (otherIds.isNotEmpty) {
        otherExperienceIds.addAll(otherIds);
      }
    }

    Map<String, Experience> fetchedExperiencesById = {};
    if (otherExperienceIds.isNotEmpty) {
      try {
        final List<Experience?> experienceFutures = await Future.wait(
            otherExperienceIds
                .map((id) => widget.experienceService.getExperience(id))
                .toList());
        final List<Experience> experiences =
            experienceFutures.whereType<Experience>().toList();
        fetchedExperiencesById = {for (var exp in experiences) exp.id: exp};
        for (final exp in experiences) {
          if (exp.categoryId != null && exp.categoryId!.isNotEmpty) {
            requiredCategoryIds.add(exp.categoryId);
          }
        }
      } catch (e) {
        print("Error fetching other experiences: $e");
      }
    }

    Map<String, UserCategory> categoryLookupMap = {};
    if (requiredCategoryIds.isNotEmpty) {
      try {
        final List<UserCategory> categories =
            await widget.experienceService.getUserCategories();
        categoryLookupMap = {for (var cat in categories) cat.id: cat};
      } catch (e) {
        print("Error fetching user categories: $e");
      }
    }

    for (final item in widget.mediaItems) {
      final otherIds =
          item.experienceIds.where((id) => id != widget.experience.id).toList();
      if (otherIds.isNotEmpty) {
        final associatedExps = otherIds
            .map((id) => fetchedExperiencesById[id])
            .where((exp) => exp != null)
            .cast<Experience>()
            .toList();
        associatedExps.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        otherExperiencesMap[item.path] = associatedExps;
      }
    }

    if (mounted) {
      setState(() {
        _otherAssociatedExperiences = otherExperiencesMap;
        _fetchedCategories = categoryLookupMap;
        _isLoadingOtherExperiences = false;
        print(
            "[Fullscreen - _loadOtherExperienceData] Set state: isLoading=false");
      });
    }
  }

  Future<void> _loadColorCategories() async {
    try {
      final colors = await widget.experienceService.getUserColorCategories();
      if (mounted) {
        setState(() {
          _userColorCategories = colors;
        });
      }
    } catch (e) {
      print("Error loading color categories in fullscreen: $e");
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
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
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
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(_didDataChange);
        return false;
      },
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              title: const Text('Content'),
              actions: [_help.buildIconButton(inactiveColor: Colors.black87)],
              bottom: _help.isActive
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(24),
                      child: _help.buildExitBanner(),
                    )
                  : null,
            ),
            body: GestureDetector(
              behavior: _help.isActive
                  ? HitTestBehavior.opaque
                  : HitTestBehavior.deferToChild,
              onTap: _help.isActive
                  ? () => _help.tryTap(
                      MediaFullscreenHelpTargetId.mediaViewer, context)
                  : null,
              child: IgnorePointer(
                ignoring: _help.isActive,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: widget.mediaItems.length,
                  onPageChanged: (index) {
                    setState(() {
                      _currentIndex = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    final item = widget.mediaItems[index];
                    final url = item.path;
                    final otherExperiences =
                        _otherAssociatedExperiences[url] ?? [];

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: CircleAvatar(
                            radius: 14,
                            backgroundColor:
                                Theme.of(context).primaryColor.withOpacity(0.8),
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 14.0,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        Card(
                          margin: EdgeInsets.zero,
                          elevation: 2.0,
                          clipBehavior: Clip.antiAlias,
                          child: instagram_widget.InstagramWebView(
                            url: url,
                            height: (_expansionStates[url] ?? false)
                                ? 1200.0
                                : 840.0,
                            launchUrlCallback: widget.launchUrlCallback,
                            onWebViewCreated: (controller) {},
                            onPageFinished: (url) {},
                          ),
                        ),
                        if (!_isLoadingOtherExperiences &&
                            otherExperiences.isNotEmpty)
                          Padding(
                            padding:
                                const EdgeInsets.only(top: 12.0, bottom: 4.0),
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
                                ...otherExperiences.map((exp) {
                                  final UserCategory? categoryForDisplay =
                                      _fetchedCategories[exp.categoryId];
                                  final String categoryIcon =
                                      categoryForDisplay?.icon ?? '❓';
                                  final String categoryName =
                                      categoryForDisplay?.name ??
                                          'Uncategorized';

                                  return ListTile(
                                    leading: Text(categoryIcon,
                                        style: const TextStyle(fontSize: 20)),
                                    title: Text(exp.name),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: withHeavyTap(() async {
                                      print(
                                          'Tapped on other experience ${exp.name} from fullscreen');
                                      final UserCategory categoryForNavigation =
                                          _fetchedCategories[exp.categoryId] ??
                                              UserCategory(
                                                  id: exp.categoryId ?? '',
                                                  name: 'Uncategorized',
                                                  icon: '❓',
                                                  ownerUserId: '');
                                      final result = await Navigator.push<bool>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              ExperiencePageScreen(
                                            experience: exp,
                                            category: categoryForNavigation,
                                            userColorCategories:
                                                _userColorCategories,
                                          ),
                                        ),
                                      );
                                      if (result == true && mounted) {
                                        _loadOtherExperienceData();
                                      }
                                    }),
                                  );
                                }),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 48,
                          child: Stack(
                            children: [
                              Align(
                                alignment: Alignment.center,
                                child: IconButton(
                                  icon: const Icon(FontAwesomeIcons.instagram),
                                  color: const Color(0xFFE1306C),
                                  iconSize: 32,
                                  tooltip: 'Open in Instagram',
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.zero,
                                  onPressed: () =>
                                      widget.launchUrlCallback(url),
                                ),
                              ),
                              Align(
                                alignment: const Alignment(0.5, 0.0),
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
                                  padding: EdgeInsets.zero,
                                  onPressed: () {
                                    setState(() {
                                      _expansionStates[url] =
                                          !(_expansionStates[url] ?? false);
                                    });
                                  },
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  iconSize: 24,
                                  color: Colors.red[700],
                                  tooltip: 'Delete Media',
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  onPressed: () => _confirmAndDelete(url),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          if (_help.isActive && _help.hasActiveTarget) _help.buildOverlay(),
        ],
      ),
    );
  }
}
