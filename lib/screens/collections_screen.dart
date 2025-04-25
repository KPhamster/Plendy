import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../models/experience.dart';
import '../models/user_category.dart';
import '../services/auth_service.dart';
import '../services/experience_service.dart';
import '../widgets/add_category_modal.dart';
import '../widgets/edit_categories_modal.dart' show CategorySortType;
import 'experience_page_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async'; // <-- ADDED Import for TimeoutException
import 'package:url_launcher/url_launcher.dart'; // ADDED for launching URLs
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; // ADDED for icons
// ADDED: Import Instagram Preview Widget (adjust alias if needed)
import 'receive_share/widgets/instagram_preview_widget.dart'
    as instagram_widget;
import '../models/shared_media_item.dart'; // ADDED Import

// ADDED: Enum for experience sort types
enum ExperienceSortType { mostRecent, alphabetical, distanceFromMe }

// ADDED: Enum for content sort types
enum ContentSortType { mostRecent, alphabetical, distanceFromMe }

// ADDED: Helper class to hold media item and parent experience for display/sorting
class ContentDisplayItem {
  final SharedMediaItem mediaItem;
  final Experience parentExperience;

  ContentDisplayItem({required this.mediaItem, required this.parentExperience});
}

class CollectionsScreen extends StatefulWidget {
  CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  final _experienceService = ExperienceService();
  final TextEditingController _searchController = TextEditingController();

  late TabController _tabController;
  int _currentTabIndex = 0;

  bool _isLoading = true;
  List<UserCategory> _categories = [];
  List<Experience> _experiences = [];
  // ADDED: State variable for experience sort type
  ExperienceSortType _experienceSortType = ExperienceSortType.mostRecent;
  // ADDED: State variable for content sort type
  ContentSortType _contentSortType = ContentSortType.mostRecent;
  String? _userEmail;
  // ADDED: State variable to track the selected category in the first tab
  UserCategory? _selectedCategory;
  // ADDED: State variable to hold flattened list of all content items
  List<ContentDisplayItem> _allContentItems = [];
  // ADDED: State map for content preview expansion
  final Map<String, bool> _contentExpansionStates = {};

  @override
  void initState() {
    super.initState();
    _userEmail = _authService.currentUser?.email ?? 'Guest';
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _currentTabIndex = _tabController.index;
        });
      } else {
        if (_currentTabIndex != _tabController.index) {
          setState(() {
            _currentTabIndex = _tabController.index;
          });
        }
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    final userId = _authService.currentUser?.uid;
    try {
      final categories = await _experienceService.getUserCategories();
      List<Experience> experiences = [];
      if (userId != null) {
        experiences = await _experienceService.getExperiencesByUser(userId);
      }

      // --- REFACTORED: Populate _allContentItems using new data model --- START ---
      List<ContentDisplayItem> allContent = [];
      if (experiences.isNotEmpty) {
        // 1. Collect all unique media item IDs from all experiences
        final Set<String> allMediaItemIds = {};
        for (final exp in experiences) {
          allMediaItemIds.addAll(exp.sharedMediaItemIds);
        }

        if (allMediaItemIds.isNotEmpty) {
          // 2. Fetch all required SharedMediaItem objects in one go
          final List<SharedMediaItem> allMediaItems = await _experienceService
              .getSharedMediaItems(allMediaItemIds.toList());

          // 3. Create a lookup map for efficient access
          final Map<String, SharedMediaItem> mediaItemMap = {
            for (var item in allMediaItems) item.id: item
          };

          // 4. Build the ContentDisplayItem list
          for (final exp in experiences) {
            for (final mediaId in exp.sharedMediaItemIds) {
              final mediaItem = mediaItemMap[mediaId];
              if (mediaItem != null) {
                allContent.add(ContentDisplayItem(
                    mediaItem: mediaItem, parentExperience: exp));
              } else {
                print(
                    "Warning: Could not find SharedMediaItem for ID $mediaId referenced by Experience ${exp.id}");
              }
            }
          }
        }
      }
      // --- REFACTORED: Populate _allContentItems using new data model --- END ---

      if (mounted) {
        setState(() {
          _categories = categories;
          _experiences = experiences;
          _allContentItems = allContent; // Set the state variable
          _isLoading = false;
          _selectedCategory = null; // Reset selected category on reload
        });
        // Apply initial sorts after loading
        _applyExperienceSort(_experienceSortType);
        await _applyContentSort(
            _contentSortType); // Apply initial content sort (await for distance)
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  Future<void> _showAddCategoryModal() async {
    final result = await showModalBottomSheet<UserCategory>(
      context: context,
      builder: (_) => const AddCategoryModal(),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );

    if (result != null) {
      print("AddCategoryModal returned a category, refreshing data...");
      _loadData();
    } else {
      print("AddCategoryModal closed without adding.");
    }
  }

  Future<void> _showEditSingleCategoryModal(UserCategory category) async {
    final result = await showModalBottomSheet<UserCategory>(
      context: context,
      builder: (_) => AddCategoryModal(categoryToEdit: category),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );

    if (result != null) {
      print("AddCategoryModal (for edit) returned, refreshing data...");
      _loadData();
    } else {
      print("AddCategoryModal (for edit) closed without saving.");
    }
  }

  Future<void> _showDeleteCategoryConfirmation(UserCategory category) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category?'),
        content: Text(
            'Are you sure you want to delete the "${category.name}" category? Associated experiences will NOT be deleted but will lose this category tag. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await _experienceService.deleteUserCategory(category.id);
        print('Category "${category.name}" deleted successfully.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${category.name}" category deleted.')),
          );
          _loadData();
        }
      } catch (e) {
        print("Error deleting category: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting category: $e')),
          );
        }
      }
    }
  }

  // ADDED: Helper to update local orderIndex properties
  void _updateLocalOrderIndices() {
    for (int i = 0; i < _categories.length; i++) {
      // Create a new UserCategory instance with the updated index
      // Directly modifying the object in the list might not trigger updates
      // if UserCategory relies on equatable/identity.
      _categories[i] = _categories[i].copyWith(orderIndex: i);
    }
    print("Updated local category order indices.");
  }

  // ADDED: Method to save the new category order to Firestore
  Future<void> _saveCategoryOrder() async {
    // Show loading indicator during save
    // We might want a more subtle indicator than the main screen one
    // but for now, let's signal activity.
    setState(() => _isLoading = true);

    final List<Map<String, dynamic>> updates = [];
    for (final category in _categories) {
      if (category.id.isNotEmpty && category.orderIndex != null) {
        updates.add({
          'id': category.id,
          'orderIndex': category.orderIndex!,
        });
      } else {
        print(
            "Warning: Skipping category in save order with missing id or index: ${category.name}");
      }
    }

    if (updates.isEmpty) {
      print("No valid category updates to save.");
      setState(() => _isLoading = false);
      return;
    }

    try {
      print("Attempting to save order for ${updates.length} categories.");
      await _experienceService.updateCategoryOrder(updates);
      print("Category order saved successfully.");
      if (mounted) {
        // Optionally show a success message (might be too noisy)
        // ScaffoldMessenger.of(context).showSnackBar(
        //   const SnackBar(content: Text('Category order saved.'), duration: Duration(seconds: 1)),
        // );
        // No need to call _loadData here if we are confident the local state is correct
        // and the save was successful. We just turn off the indicator.
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print("Error saving category order: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving category order: $e")),
        );
        // If save failed, reload data to revert to the last known good state
        setState(() => _isLoading = false);
        _loadData();
      }
    }
  }

  int _getExperienceCountForCategory(UserCategory category) {
    return _experiences.where((exp) => exp.category == category.name).length;
  }

  Widget _buildCategoriesList() {
    if (_categories.isEmpty) {
      return const Center(child: Text('No categories found.'));
    }

    return ReorderableListView.builder(
      itemCount: _categories.length,
      itemBuilder: (context, index) {
        final category = _categories[index];
        final count = _getExperienceCountForCategory(category);
        return ListTile(
          key: ValueKey(category.id),
          leading: Text(
            category.icon,
            style: const TextStyle(fontSize: 24),
          ),
          title: Text(category.name),
          subtitle: Text('$count ${count == 1 ? "experience" : "experiences"}'),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Category Options',
            onSelected: (String result) {
              switch (result) {
                case 'edit':
                  _showEditSingleCategoryModal(category);
                  break;
                case 'delete':
                  _showDeleteCategoryConfirmation(category);
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red),
                  title: Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ),
            ],
          ),
          onTap: () {
            // MODIFIED: Set the selected category to show its experiences
            setState(() {
              _selectedCategory = category;
            });
            print('Tapped on ${category.name}, showing experiences.');
          },
        );
      },
      onReorder: (int oldIndex, int newIndex) {
        setState(() {
          if (newIndex > oldIndex) {
            newIndex -= 1;
          }
          final UserCategory item = _categories.removeAt(oldIndex);
          _categories.insert(newIndex, item);

          _updateLocalOrderIndices();

          print("Categories reordered locally. Triggering save.");

          _saveCategoryOrder();
        });
      },
    );
  }

  // ADDED: Method to apply sorting and save the new order
  Future<void> _applySortAndSave(CategorySortType sortType) async {
    print("Applying sort: $sortType");
    setState(() {
      if (sortType == CategorySortType.alphabetical) {
        _categories.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      } else if (sortType == CategorySortType.mostRecent) {
        _categories.sort((a, b) {
          // Handle null timestamps gracefully during sort
          final tsA = a.lastUsedTimestamp;
          final tsB = b.lastUsedTimestamp;
          if (tsA == null && tsB == null) {
            // If both null, maintain relative order based on name for stability
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }
          if (tsA == null) return 1; // Treat null as oldest
          if (tsB == null) return -1; // Treat null as oldest
          return tsB.compareTo(tsA); // Sort descending (most recent first)
        });
      }

      // Update local indices based on the new sort order
      _updateLocalOrderIndices();
    });

    // Persist the newly assigned order indices
    await _saveCategoryOrder();
  }

  // MODIFIED: Method to apply sorting to the experiences list
  // Takes the desired sort type as an argument
  Future<void> _applyExperienceSort(ExperienceSortType sortType) async {
    print("Applying experience sort: $sortType");
    // Set the internal state first, so UI reflects the choice while processing
    setState(() {
      _experienceSortType = sortType;
      _isLoading =
          true; // Show loading indicator for potentially long operations (like distance)
    });

    try {
      if (sortType == ExperienceSortType.alphabetical) {
        _experiences.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      } else if (sortType == ExperienceSortType.mostRecent) {
        _experiences.sort((a, b) {
          // Sort descending by creation date (most recent first)
          return b.createdAt.compareTo(a.createdAt);
        });
      } else if (sortType == ExperienceSortType.distanceFromMe) {
        // --- ADDED: Distance Sorting Logic ---
        await _sortExperiencesByDistance();
        // --- END ADDED ---
      }
      // Add other sort types here if needed
    } catch (e) {
      print("Error applying sort: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sorting experiences: $e')),
        );
      }
    } finally {
      // Ensure loading indicator is turned off and UI rebuilds
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
    print("Experiences sorted.");
  }

  // --- ADDED: Method to sort experiences by distance ---
  Future<void> _sortExperiencesByDistance() async {
    print("Attempting to sort by distance...");
    Position? currentPosition;
    bool locationPermissionGranted = false;

    try {
      // 1. Check Location Services
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Location services are disabled. Please enable them.')));
        return; // Stop if services are disabled
      }

      // 2. Check and Request Permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Location permission denied. Cannot sort by distance.')));
        }
        return; // Stop if permission denied
      }

      locationPermissionGranted = true;

      // 3. Get Current Location (with timeout)
      print("Getting current location...");
      currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy:
            LocationAccuracy.medium, // Medium accuracy is often faster
        timeLimit: Duration(seconds: 10), // Add a timeout
      );
      print(
          "Current location obtained: ${currentPosition.latitude}, ${currentPosition.longitude}");
    } catch (e) {
      print("Error getting current location: $e");
      if (mounted) {
        String message = 'Could not get current location.';
        if (e is TimeoutException) {
          message = 'Could not get current location: Request timed out.';
        } else if (!locationPermissionGranted) {
          // This case is unlikely if permission check above is robust,
          // but kept for safety.
          message = 'Location permission denied. Cannot sort by distance.';
        } else {
          message = 'Error getting location: ${e.toString()}';
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
      return; // Stop if location couldn't be determined
    }

    // 4. Calculate Distances and Sort
    if (currentPosition != null) {
      // Use a temporary list or map to store experiences with distances
      List<Map<String, dynamic>> experiencesWithDistance = [];

      for (var exp in _experiences) {
        double? distance;
        // Check if the experience has valid coordinates
        if (exp.location.latitude != 0.0 || exp.location.longitude != 0.0) {
          try {
            distance = Geolocator.distanceBetween(
              currentPosition!.latitude,
              currentPosition!.longitude,
              exp.location.latitude,
              exp.location.longitude,
            );
          } catch (e) {
            print("Error calculating distance for ${exp.name}: $e");
            distance = null; // Treat calculation error as unknown distance
          }
        } else {
          print("Experience ${exp.name} has no valid coordinates.");
          distance = null; // No coordinates, unknown distance
        }
        experiencesWithDistance.add({'experience': exp, 'distance': distance});
      }

      // Sort the temporary list
      experiencesWithDistance.sort((a, b) {
        final distA = a['distance'] as double?;
        final distB = b['distance'] as double?;

        // Handle null distances (experiences w/o location or errors)
        if (distA == null && distB == null) return 0; // Keep relative order
        if (distA == null) return 1; // Nulls go to the end
        if (distB == null) return -1; // Nulls go to the end

        return distA.compareTo(distB); // Sort by distance ascending
      });

      // Update the main experiences list with the sorted order
      _experiences = experiencesWithDistance
          .map((item) => item['experience'] as Experience)
          .toList();

      print("Experiences sorted by distance successfully.");
    }
  }
  // --- END ADDED ---

  // ADDED: Helper method for launching URLs (copied from ExperiencePageScreen)
  Future<void> _launchUrl(String urlString) async {
    // Ensure URL starts with http/https for launchUrl
    String launchableUrl = urlString;
    if (!launchableUrl.startsWith('http://') &&
        !launchableUrl.startsWith('https://')) {
      // Assume https if no scheme provided
      launchableUrl = 'https://' + launchableUrl;
      print("Prepended 'https://' to URL: $launchableUrl");
    }

    final Uri uri = Uri.parse(launchableUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      print('Could not launch $uri');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link: $urlString')),
        );
      }
    }
  }

  // ADDED: Function to get search suggestions
  Future<List<Experience>> _getExperienceSuggestions(String pattern) async {
    if (pattern.isEmpty) {
      return [];
    }
    // Simple case-insensitive search on the name
    return _experiences
        .where((exp) => exp.name.toLowerCase().contains(pattern.toLowerCase()))
        .toList();
  }

  // --- ADDED: Method to apply sorting to the content items list ---
  Future<void> _applyContentSort(ContentSortType sortType) async {
    print("Applying content sort: $sortType");
    setState(() {
      _contentSortType = sortType;
      // Show loading only for distance sort as it's potentially slow
      if (sortType == ContentSortType.distanceFromMe) {
        _isLoading = true;
      }
    });

    try {
      if (sortType == ContentSortType.mostRecent) {
        _allContentItems.sort((a, b) {
          // Sort descending by media item creation date
          return b.mediaItem.createdAt.compareTo(a.mediaItem.createdAt);
        });
      } else if (sortType == ContentSortType.alphabetical) {
        _allContentItems.sort((a, b) {
          // Sort ascending by parent experience name
          return a.parentExperience.name
              .toLowerCase()
              .compareTo(b.parentExperience.name.toLowerCase());
        });
      } else if (sortType == ContentSortType.distanceFromMe) {
        await _sortContentByDistance();
      }
    } catch (e, stackTrace) {
      print("Error applying content sort: $e");
      print(stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sorting content: $e')),
        );
      }
    } finally {
      // Ensure loading indicator is turned off and UI rebuilds
      if (mounted && _isLoading && sortType == ContentSortType.distanceFromMe) {
        setState(() {
          _isLoading = false;
        });
      }
    }
    // Need setState to rebuild the list after sorting (unless isLoading was already true)
    if (mounted && sortType != ContentSortType.distanceFromMe) {
      setState(() {});
    }
    print("Content items sorted.");
  }

  // --- ADDED: Method to sort content items by distance --- ///
  Future<void> _sortContentByDistance() async {
    print("Attempting to sort content by distance...");
    Position? currentPosition;
    bool locationPermissionGranted = false;

    // Much of this logic is duplicated from _sortExperiencesByDistance
    // Consider refactoring into a shared location service/helper in the future
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Location services are disabled. Please enable them.')));
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Location permission denied. Cannot sort by distance.')));
        }
        return;
      }

      locationPermissionGranted = true;

      print("Getting current location for content sort...");
      currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 10),
      );
      print(
          "Current location obtained: ${currentPosition.latitude}, ${currentPosition.longitude}");
    } catch (e) {
      print("Error getting current location: $e");
      if (mounted) {
        String message = 'Could not get current location.';
        if (e is TimeoutException) {
          message = 'Could not get current location: Request timed out.';
        } else if (!locationPermissionGranted) {
          message = 'Location permission denied. Cannot sort by distance.';
        } else {
          message = 'Error getting location: ${e.toString()}';
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
      return;
    }

    if (currentPosition != null) {
      // Create a temporary list with distances
      List<Map<String, dynamic>> contentWithDistance = [];

      for (var item in _allContentItems) {
        double? distance;
        final location = item.parentExperience.location;
        if (location.latitude != 0.0 || location.longitude != 0.0) {
          try {
            distance = Geolocator.distanceBetween(
              currentPosition.latitude,
              currentPosition.longitude,
              location.latitude,
              location.longitude,
            );
          } catch (e) {
            print(
                "Error calculating distance for ${item.parentExperience.name}: $e");
            distance = null;
          }
        } else {
          print(
              "Experience ${item.parentExperience.name} has no valid coordinates.");
          distance = null;
        }
        contentWithDistance.add({'item': item, 'distance': distance});
      }

      // Sort the temporary list
      contentWithDistance.sort((a, b) {
        final distA = a['distance'] as double?;
        final distB = b['distance'] as double?;

        if (distA == null && distB == null) return 0;
        if (distA == null) return 1;
        if (distB == null) return -1;

        return distA.compareTo(distB);
      });

      // Update the main content list
      _allContentItems = contentWithDistance
          .map((mapItem) => mapItem['item'] as ContentDisplayItem)
          .toList();

      print("Content items sorted by distance successfully.");
    }
  }
  // --- END ADDED ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Collection'),
        actions: [
          if (_currentTabIndex == 0 && _selectedCategory == null)
            PopupMenuButton<CategorySortType>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort Categories',
              onSelected: (CategorySortType result) {
                _applySortAndSave(result);
              },
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<CategorySortType>>[
                const PopupMenuItem<CategorySortType>(
                  value: CategorySortType.mostRecent,
                  child: Text('Sort by Most Recent'),
                ),
                const PopupMenuItem<CategorySortType>(
                  value: CategorySortType.alphabetical,
                  child: Text('Sort Alphabetically'),
                ),
              ],
            ),
          if (_currentTabIndex == 1)
            PopupMenuButton<ExperienceSortType>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort Experiences',
              onSelected: (ExperienceSortType result) {
                _applyExperienceSort(result);
              },
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<ExperienceSortType>>[
                const PopupMenuItem<ExperienceSortType>(
                  value: ExperienceSortType.mostRecent,
                  child: Text('Sort by Most Recent'),
                ),
                const PopupMenuItem<ExperienceSortType>(
                  value: ExperienceSortType.alphabetical,
                  child: Text('Sort Alphabetically'),
                ),
                const PopupMenuItem<ExperienceSortType>(
                  value: ExperienceSortType.distanceFromMe,
                  child: Text('Sort by Distance'),
                ),
              ],
            ),
          if (_currentTabIndex == 2)
            PopupMenuButton<ContentSortType>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort Content',
              onSelected: (ContentSortType result) {
                _applyContentSort(result); // Use the new sort function
              },
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<ContentSortType>>[
                const PopupMenuItem<ContentSortType>(
                  value: ContentSortType.mostRecent,
                  child: Text('Sort by Most Recent Added'), // Clarified label
                ),
                const PopupMenuItem<ContentSortType>(
                  value: ContentSortType.alphabetical,
                  child: Text(
                      'Sort Alphabetically (by Experience)'), // Clarified label
                ),
                const PopupMenuItem<ContentSortType>(
                  value: ContentSortType.distanceFromMe,
                  child: Text(
                      'Sort by Distance (from Experience)'), // Clarified label
                ),
              ],
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ADDED: Search Bar Area
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12.0, vertical: 4.0),
                  child: TypeAheadField<Experience>(
                    builder: (context, controller, focusNode) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: 'Search your experiences',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25.0),
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Clear Search',
                            onPressed: () {
                              controller.clear();
                              _searchController.clear();
                              FocusScope.of(context).unfocus();
                              setState(() {});
                            },
                          ),
                        ),
                      );
                    },
                    suggestionsCallback: (pattern) async {
                      return await _getExperienceSuggestions(pattern);
                    },
                    itemBuilder: (context, suggestion) {
                      return ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(suggestion.name),
                      );
                    },
                    onSelected: (suggestion) async {
                      print('Selected experience: ${suggestion.name}');
                      // ADDED: Navigate to the experience page

                      // Find the matching category for the selected experience
                      final category = _categories.firstWhere(
                          (cat) => cat.name == suggestion.category,
                          orElse: () => UserCategory(
                              id: '',
                              name: suggestion.category,
                              icon: '❓',
                              ownerUserId: '') // Fallback
                          );

                      // Await result and refresh if needed
                      final result = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ExperiencePageScreen(
                            experience: suggestion,
                            category: category, // Pass the found category
                          ),
                        ),
                      );
                      _searchController.clear();
                      FocusScope.of(context).unfocus();
                      // Refresh if deletion occurred
                      if (result == true && mounted) {
                        _loadData();
                      }
                    },
                    emptyBuilder: (context) => const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text('No experiences found.',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                ),
                // ADDED: TabBar placed here in the body's Column
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'Categories'),
                    Tab(text: 'Experiences'),
                    Tab(text: 'Content'),
                  ],
                  // Optional: Style the TabBar if needed when outside AppBar
                  // labelColor: Theme.of(context).primaryColor,
                  // unselectedLabelColor: Colors.grey,
                  // indicatorColor: Theme.of(context).primaryColor,
                ),
                // Existing TabBarView wrapped in Expanded
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // MODIFIED: Conditionally show category list or category experiences
                      _selectedCategory == null
                          ? _buildCategoriesList()
                          : _buildCategoryExperiencesList(_selectedCategory!),
                      _buildExperiencesListView(),
                      // MODIFIED: Call builder for Content tab
                      _buildContentTabBody(),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: _currentTabIndex == 0 && _selectedCategory == null
          ? FloatingActionButton(
              onPressed: _showAddCategoryModal,
              tooltip: 'Add Category',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  // REFACTORED: Extracted list item builder for reuse
  Widget _buildExperienceListItem(Experience experience) {
    // Find the matching category icon
    final categoryIcon = _categories
        .firstWhere((cat) => cat.name == experience.category,
            orElse: () => UserCategory(
                id: '', name: '', icon: '❓', ownerUserId: '') // Default icon
            )
        .icon;

    // Get the full address
    final fullAddress = experience.location.address;
    // Get the first image URL or null
    final imageUrl = experience.location.photoUrl;

    return ListTile(
      key: ValueKey(experience.id), // Use experience ID as key
      leading: SizedBox(
        width: 56, // Define width for the leading image container
        height: 56, // Define height for the leading image container
        child: ClipRRect(
          // Clip the image to a rounded rectangle
          borderRadius: BorderRadius.circular(8.0),
          child: imageUrl != null
              ? Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  // Optional: Add loading/error builders
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                        child: CircularProgressIndicator(strokeWidth: 2.0));
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[200],
                      child: Icon(Icons.broken_image, color: Colors.grey),
                    );
                  },
                )
              : Container(
                  // Placeholder if no image URL
                  color: Colors.grey[300],
                  child:
                      Icon(Icons.image_not_supported, color: Colors.grey[600]),
                ),
        ),
      ),
      title: Text(experience.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fullAddress != null && fullAddress.isNotEmpty)
            Text(
              fullAddress, // Use full address
              style: Theme.of(context).textTheme.bodySmall,
            ),
          Text(
            '$categoryIcon ${experience.category}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          // ADDED: Display notes if available
          if (experience.additionalNotes != null &&
              experience.additionalNotes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4.0), // Add some spacing
              child: Text(
                experience.additionalNotes!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic, // Optional: Italicize notes
                    ),
                maxLines: 2, // Limit notes length in list view
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
      onTap: () async {
        // Make onTap async
        print('Tapped on Experience: ${experience.name}');
        // ADDED: Navigation logic to the ExperiencePageScreen

        // Find the matching category for the tapped experience
        final category = _categories.firstWhere(
            (cat) => cat.name == experience.category,
            orElse: () => UserCategory(
                id: '',
                name: experience.category,
                icon: '❓',
                ownerUserId: '') // Fallback
            );

        // Await result and refresh if needed
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => ExperiencePageScreen(
              experience: experience,
              category: category, // Pass the found category
            ),
          ),
        );
        // Refresh if deletion occurred
        if (result == true && mounted) {
          _loadData();
        }
      },
    );
  }

  // MODIFIED: Widget builder for the Experience List View uses the refactored item builder
  Widget _buildExperiencesListView() {
    if (_experiences.isEmpty) {
      return const Center(child: Text('No experiences found. Add some!'));
    }

    // Use the refactored item builder
    return ListView.builder(
      itemCount: _experiences.length,
      itemBuilder: (context, index) {
        return _buildExperienceListItem(_experiences[index]);
      },
    );
  }

  // ADDED: Widget to display experiences for a specific category
  Widget _buildCategoryExperiencesList(UserCategory category) {
    final categoryExperiences = _experiences
        .where((exp) => exp.category == category.name)
        .toList(); // Filter experiences

    // Apply the current experience sort order to this sublist
    // Note: This creates a sorted copy, doesn't modify the original _experiences
    if (_experienceSortType == ExperienceSortType.alphabetical) {
      categoryExperiences
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else if (_experienceSortType == ExperienceSortType.mostRecent) {
      categoryExperiences.sort((a, b) {
        return b.createdAt.compareTo(a.createdAt);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row with back button and category name
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to Categories',
                onPressed: () {
                  setState(() {
                    _selectedCategory = null; // Go back to category list
                  });
                },
              ),
              const SizedBox(width: 8),
              Text(
                '${category.icon} ${category.name}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(), // Pushes sort button to the right if added later
              // Optional: Add a sort button specific to this view if needed
              // PopupMenuButton<ExperienceSortType>(...)
            ],
          ),
        ),
        const Divider(height: 1),
        // List of experiences for this category
        Expanded(
          child: categoryExperiences.isEmpty
              ? Center(
                  child: Text(
                      'No experiences found in the "${category.name}" category.'))
              : ListView.builder(
                  itemCount: categoryExperiences.length,
                  itemBuilder: (context, index) {
                    // Use the refactored item builder
                    return _buildExperienceListItem(categoryExperiences[index]);
                  },
                ),
        ),
      ],
    );
  }

  // --- ADDED: Widget builder for the Content Tab Body --- ///
  Widget _buildContentTabBody() {
    // Use instance member _allContentItems
    if (_allContentItems.isEmpty) {
      return const Center(
          child: Text('No shared content found across experiences.'));
    }

    // MODIFIED: Use ListView.builder instead of GridView.builder
    return ListView.builder(
      // padding: const EdgeInsets.all(4.0), // Removed grid padding
      // Add padding similar to fullscreen list
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      // gridDelegate: ..., // Removed gridDelegate
      itemCount: _allContentItems.length,
      itemBuilder: (context, index) {
        final item = _allContentItems[index];
        final mediaPath = item.mediaItem.path;
        final parentExp = item.parentExperience;

        final isExpanded = _contentExpansionStates[mediaPath] ?? false;
        final bool isInstagramUrl =
            mediaPath.toLowerCase().contains('instagram.com');

        bool isNetworkUrl =
            mediaPath.startsWith('http') || mediaPath.startsWith('https');

        Widget mediaWidget;
        if (isInstagramUrl) {
          // Use InstagramWebView for Instagram URLs
          mediaWidget = instagram_widget.InstagramWebView(
            url: mediaPath,
            // MODIFIED: Adjust height for list view (similar to fullscreen/exp page)
            height: isExpanded ? 1200 : 840,
            launchUrlCallback: _launchUrl,
            onWebViewCreated: (_) {},
            onPageFinished: (_) {},
          );
        } else if (isNetworkUrl) {
          // Use Image.network for other network URLs
          mediaWidget = Image.network(
            mediaPath,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              // Keep standard indicator for list view
              return const Center(child: CircularProgressIndicator());
            },
            errorBuilder: (context, error, stackTrace) {
              print("Error loading image $mediaPath: $error");
              return Container(
                color: Colors.grey[200],
                height: 200, // Give error placeholder some height
                child: Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: Colors.grey[600], size: 40)),
              );
            },
          );
        } else {
          // Placeholder for local paths or non-image URLs
          mediaWidget = Container(
            color: Colors.grey[300],
            height: 150, // Give placeholder some height
            child: Center(
                child:
                    Icon(Icons.description, color: Colors.grey[700], size: 40)),
          );
        }

        // MODIFIED: Return a Column structure suitable for a list item
        return Padding(
          key: ValueKey(mediaPath), // Use mediaPath as key
          padding:
              const EdgeInsets.only(bottom: 24.0), // Spacing between list items
          child: Card(
            elevation: 2.0,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // ADDED: Row for Numbering and Parent Experience Name
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12.0, vertical: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Number Bubble
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.8),
                        child: Text(
                          '${index + 1}', // Display index + 1
                          style: TextStyle(
                            fontSize: 12.0,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Parent Experience Name (Expanded to fill space)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Experience Name
                            Text(
                              parentExp.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            // ADDED: Address Subtext (if available)
                            if (parentExp.location.address != null &&
                                parentExp.location.address!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                    top: 2.0), // Add slight spacing
                                child: Text(
                                  parentExp.location.address!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Colors.black54, // Subdued color
                                      ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Divider (optional)
                // const Divider(height: 1, thickness: 1),
                // Media Preview Area
                GestureDetector(
                  onTap: () async {
                    print('Tapped on media from Experience: ${parentExp.name}');
                    final category = _categories.firstWhere(
                        (cat) => cat.name == parentExp.category,
                        orElse: () => UserCategory(
                            id: '',
                            name: parentExp.category,
                            icon: '❓',
                            ownerUserId: '') // Fallback
                        );

                    final result = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ExperiencePageScreen(
                          experience: parentExp,
                          category: category,
                        ),
                      ),
                    );
                    if (result == true && mounted) {
                      _loadData();
                    }
                  },
                  child: mediaWidget,
                ),
                // Buttons Row
                Container(
                  height: 48, // Standard height for buttons
                  color: Colors.black.withOpacity(0.03),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      // Instagram Button (only if Instagram URL)
                      if (isInstagramUrl)
                        IconButton(
                          icon: const Icon(FontAwesomeIcons.instagram),
                          iconSize: 28, // Slightly larger icon for list view
                          color: const Color(0xFFE1306C),
                          tooltip: 'Open in Instagram',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _launchUrl(mediaPath),
                        ),
                      // Expand/Collapse Button (only if Instagram URL)
                      if (isInstagramUrl)
                        IconButton(
                          icon: Icon(isExpanded
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen),
                          iconSize: 24,
                          color: Colors.blueGrey,
                          tooltip: isExpanded ? 'Collapse' : 'Expand',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            setState(() {
                              _contentExpansionStates[mediaPath] = !isExpanded;
                            });
                          },
                        ),
                      // Add other generic buttons here if needed (e.g., Share)
                      // If not instagram, provide some spacing or alternative actions
                      if (!isInstagramUrl)
                        Spacer(), // Use Spacer to push potential future buttons
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  // --- END MODIFIED ---
}
