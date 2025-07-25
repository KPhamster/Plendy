import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../models/experience.dart';
import '../models/user_category.dart';
import '../models/color_category.dart';
import '../widgets/add_color_category_modal.dart';
import '../widgets/edit_color_categories_modal.dart' show ColorCategorySortType;
import '../services/auth_service.dart';
import '../services/experience_service.dart';
import '../widgets/add_category_modal.dart';
import '../widgets/edit_categories_modal.dart' show CategorySortType;
import '../widgets/add_experience_modal.dart'; // ADDED: Import for AddExperienceModal
import 'experience_page_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async'; // <-- ADDED Import for TimeoutException
import 'package:url_launcher/url_launcher.dart'; // ADDED for launching URLs
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; // ADDED for icons
// ADDED: Import Instagram Preview Widget (adjust alias if needed)
import 'receive_share/widgets/instagram_preview_widget.dart'
    as instagram_widget;
import 'receive_share/widgets/tiktok_preview_widget.dart';
import 'receive_share/widgets/facebook_preview_widget.dart';
import 'receive_share/widgets/youtube_preview_widget.dart';
import 'receive_share/widgets/generic_url_preview_widget.dart';
import '../models/shared_media_item.dart'; // ADDED Import
import 'package:collection/collection.dart'; // ADDED: Import for groupBy
import 'map_screen.dart'; // ADDED: Import for MapScreen
import 'package:flutter/foundation.dart'; // ADDED: Import for kIsWeb
import 'package:flutter/gestures.dart'; // ADDED Import for PointerScrollEvent
import 'package:flutter/rendering.dart'; // ADDED Import for Scrollable

// Helper function to parse hex color string (copied from map_screen)
Color _parseColor(String hexColor) {
  hexColor = hexColor.toUpperCase().replaceAll("#", "");
  if (hexColor.length == 6) {
    hexColor = "FF$hexColor"; // Add alpha if missing
  }
  if (hexColor.length == 8) {
    try {
      return Color(int.parse("0x$hexColor"));
    } catch (e) {
      print("🎨 COLLECTIONS SCREEN: Error parsing color '$hexColor': $e");
      return Colors.grey; // Default color on parsing error
    }
  }
  print("🎨 COLLECTIONS SCREEN: Invalid hex color format: '$hexColor'");
  return Colors.grey; // Default color on invalid format
}

// ADDED: Enum for experience sort types
enum ExperienceSortType { mostRecent, alphabetical, distanceFromMe }

// ADDED: Enum for content sort types
enum ContentSortType { mostRecent, alphabetical, distanceFromMe }

// ADDED: New helper class to hold grouped content
class GroupedContentItem {
  final SharedMediaItem mediaItem;
  final List<Experience> associatedExperiences;
  double? minDistance; // Used for distance sorting

  GroupedContentItem({
    required this.mediaItem,
    required this.associatedExperiences,
    this.minDistance,
  });
}

class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

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
  // ADDED: State for color categories
  List<ColorCategory> _colorCategories = [];
  bool _showingColorCategories = false; // Flag to toggle view in first tab
  // ADDED: State variable for experience sort type
  ExperienceSortType _experienceSortType = ExperienceSortType.mostRecent;
  // ADDED: State variable for content sort type
  ContentSortType _contentSortType = ContentSortType.mostRecent;
    // ADDED: State variables for category sort types
  CategorySortType _categorySortType = CategorySortType.mostRecent;
  ColorCategorySortType _colorCategorySortType = ColorCategorySortType.mostRecent;
  String? _userEmail;
  // ADDED: State variable to track the selected category in the first tab
  UserCategory? _selectedCategory;
  // --- ADDED: State variable for selected color category ---
  ColorCategory? _selectedColorCategory;
  // --- END ADDED ---
  // ADDED: State variable to hold grouped list of content items
  List<GroupedContentItem> _groupedContentItems = [];
  // ADDED: State map for content preview expansion
  final Map<String, bool> _contentExpansionStates = {};

  // --- ADDED: Filter State ---
  Set<String> _selectedCategoryIds =
      {}; // Empty set means no filter (copied from map_screen)
  Set<String> _selectedColorCategoryIds =
      {}; // Empty set means no filter (copied from map_screen)
  List<Experience> _filteredExperiences =
      []; // To hold filtered experiences for tab 1
  List<GroupedContentItem> _filteredGroupedContentItems =
      []; // To hold filtered content for tab 2
  // --- END Filter State ---

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
      // Fetch both types of categories concurrently
      final results = await Future.wait([
        _experienceService.getUserCategories(),
        _experienceService.getUserColorCategories(), // Fetch color categories
        if (userId != null)
          _experienceService.getExperiencesByUser(userId)
        else
          Future.value(<Experience>[]), // Return empty list if no user
      ]);

      final categories = results[0] as List<UserCategory>;
      final colorCategories =
          results[1] as List<ColorCategory>; // Get color categories
      final experiences = results[2] as List<Experience>;

      // --- REFACTORED: Populate _groupedContentItems using new data model --- START ---
      List<GroupedContentItem> groupedContent = [];
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

          // 4. Create intermediate list mapping media path to experience
          final List<Map<String, dynamic>> pathExperiencePairs = [];
          for (final exp in experiences) {
            for (final mediaId in exp.sharedMediaItemIds) {
              final mediaItem = mediaItemMap[mediaId];
              if (mediaItem != null) {
                pathExperiencePairs.add({
                  'path': mediaItem.path,
                  'mediaItem':
                      mediaItem, // Keep mediaItem for easy access later
                  'experience': exp,
                });
              } else {
                print(
                    "Warning: Could not find SharedMediaItem for ID $mediaId referenced by Experience ${exp.id}");
              }
            }
          }

          // 5. Group by media path
          final groupedByPath =
              groupBy(pathExperiencePairs, (pair) => pair['path'] as String);

          // 6. Build the GroupedContentItem list
          groupedByPath.forEach((path, pairs) {
            if (pairs.isNotEmpty) {
              final firstPair = pairs.first;
              final mediaItem = firstPair['mediaItem'] as SharedMediaItem;
              final associatedExperiences = pairs
                  .map((pair) => pair['experience'] as Experience)
                  .toList();
              // Sort associated experiences alphabetically by default? Or by date? Let's do name for now.
              associatedExperiences.sort((a, b) =>
                  a.name.toLowerCase().compareTo(b.name.toLowerCase()));

              groupedContent.add(GroupedContentItem(
                mediaItem: mediaItem,
                associatedExperiences: associatedExperiences,
              ));
            }
          });
        }
      }
      // --- REFACTORED: Populate _groupedContentItems using new data model --- END ---

      if (mounted) {
        setState(() {
          _categories = categories;
          _colorCategories = colorCategories; // Store color categories
          _experiences = experiences;
          _groupedContentItems = groupedContent; // Set the state variable
          _isLoading = false;
          _selectedCategory = null; // Reset selected category on reload
          _selectedColorCategory =
              null; // Reset selected color category on reload
          // _showingColorCategories = false; // Ensure default view on reload

          // Initialize filtered lists with all items initially
          _filteredExperiences = List.from(_experiences);
          _filteredGroupedContentItems = List.from(_groupedContentItems);
        });
        // Apply initial sorts after loading
        _applyExperienceSort(_experienceSortType);
        await _applyContentSort(
            _contentSortType); // Apply initial content sort (await for distance)
        // Also apply to filtered lists to ensure UI displays correctly sorted data
        _applyExperienceSort(_experienceSortType, applyToFiltered: true);
        await _applyContentSort(_contentSortType, applyToFiltered: true);
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

  // ADDED: Method to show add experience modal
  Future<void> _showAddExperienceModal() async {
    final result = await showModalBottomSheet<Experience>(
      context: context,
      builder: (_) => AddExperienceModal(
        userCategories: _categories,
        userColorCategories: _colorCategories,
      ),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );

    if (result != null) {
      print("AddExperienceModal returned an experience, refreshing data...");
      _loadData();
    } else {
      print("AddExperienceModal closed without adding.");
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
    // MODIFIED: Include experiences with this category as primary OR in otherCategories
    return _experiences.where((exp) => 
      exp.categoryId == category.id || 
      exp.otherCategories.contains(category.id)
    ).length;
  }

  // ADDED: Widget builder for a Category Grid Item (for web)
  Widget _buildCategoryGridItem(UserCategory category) {
    final count = _getExperienceCountForCategory(category);
    return Card(
      key: ValueKey('category_grid_${category.id}'),
      clipBehavior: Clip.antiAlias,
      elevation: 2.0,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedCategory = category;
            _showingColorCategories = false; 
            _selectedColorCategory = null; 
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text(
                category.icon,
                style: const TextStyle(fontSize: 32),
              ),
              const SizedBox(height: 8),
              Text(
                category.name,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '$count ${count == 1 ? "exp" : "exps"}',
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoriesList() {
    if (_categories.isEmpty) {
      return const Center(child: Text('No categories found.'));
    }

    final bool isDesktopWeb = kIsWeb && MediaQuery.of(context).size.width > 600;

    if (isDesktopWeb) {
      final screenWidth = MediaQuery.of(context).size.width;
      const double contentMaxWidth = 1200.0;
      const double defaultPadding = 12.0; // Original all-around padding was 12.0

      double horizontalPadding;
      if (screenWidth > contentMaxWidth) {
        horizontalPadding = (screenWidth - contentMaxWidth) / 2;
      } else {
        horizontalPadding = defaultPadding;
      }

      // Web: Use GridView.builder
      return GridView.builder(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: defaultPadding),
        itemCount: _categories.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: 10.0,
          crossAxisSpacing: 10.0,
          childAspectRatio: 3/3.5, // Width : Height ratio for each item
        ),
        itemBuilder: (context, index) {
          // Ensure _categories is accessed safely if it can be modified elsewhere
          // For simplicity, assuming it's stable during build or handled by setState
          final category = _categories[index];
          return _buildCategoryGridItem(category);
        },
      );
    } else {
      // Mobile: Use existing ReorderableListView.builder
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
              setState(() {
                _selectedCategory = category;
                _showingColorCategories = false; 
                _selectedColorCategory = null; 
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
  // ADDED: Optional parameter to apply sort to the filtered list
  Future<void> _applyExperienceSort(ExperienceSortType sortType,
      {bool applyToFiltered = false}) async {
    print(
        "Applying experience sort: $sortType (applyToFiltered: $applyToFiltered)");
    // Set the internal state first, so UI reflects the choice while processing
    setState(() {
      _experienceSortType = sortType;
      // Only show loading indicator if sorting the main list by distance
      _isLoading =
          (sortType == ExperienceSortType.distanceFromMe && !applyToFiltered);
    });

    // Determine which list to sort
    List<Experience> listToSort =
        applyToFiltered ? _filteredExperiences : _experiences;

    try {
      if (sortType == ExperienceSortType.alphabetical) {
        listToSort.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      } else if (sortType == ExperienceSortType.mostRecent) {
        listToSort.sort((a, b) {
          // Sort descending by creation date (most recent first)
          return b.createdAt.compareTo(a.createdAt);
        });
      } else if (sortType == ExperienceSortType.distanceFromMe) {
        // --- MODIFIED: Distance Sorting Logic now operates on listToSort ---
        await _sortExperiencesByDistance(listToSort);
        // --- END MODIFIED ---
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
  // MODIFIED: Takes the list to sort as a parameter
  Future<void> _sortExperiencesByDistance(
      List<Experience> experiencesToSort) async {
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
    // Use a temporary list or map to store experiences with distances
    List<Map<String, dynamic>> experiencesWithDistance = [];

    // Use the passed-in list
    for (var exp in experiencesToSort) {
      double? distance;
      // Check if the experience has valid coordinates
      if (exp.location.latitude != 0.0 || exp.location.longitude != 0.0) {
        try {
          distance = Geolocator.distanceBetween(
            currentPosition.latitude,
            currentPosition.longitude,
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

    // Update the *original* list passed in (experiencesToSort) with the sorted order
    // This modifies the list in place (either _experiences or _filteredExperiences)
    experiencesToSort.clear();
    experiencesToSort.addAll(experiencesWithDistance
        .map((item) => item['experience'] as Experience)
        .toList());

    print("Experiences sorted by distance successfully.");
    }
  // --- END ADDED ---

  // --- REFACTORED: Method to apply sorting to the grouped content items list ---
  // ADDED: Optional parameter to apply sort to the filtered list
  Future<void> _applyContentSort(ContentSortType sortType,
      {bool applyToFiltered = false}) async {
    print(
        "Applying content sort: $sortType (applyToFiltered: $applyToFiltered)");
    setState(() {
      _contentSortType = sortType;
      // Show loading only for distance sort on the main list
      if (sortType == ContentSortType.distanceFromMe && !applyToFiltered) {
        _isLoading = true;
      }
    });

    // Determine which list to sort
    List<GroupedContentItem> listToSort =
        applyToFiltered ? _filteredGroupedContentItems : _groupedContentItems;
    
    print("SORT DEBUG: listToSort.length = ${listToSort.length}");
    print("SORT DEBUG: _groupedContentItems.length = ${_groupedContentItems.length}");
    print("SORT DEBUG: _filteredGroupedContentItems.length = ${_filteredGroupedContentItems.length}");

    try {
      if (sortType == ContentSortType.mostRecent) {
        // Sort by media item creation date (descending)
        print("SORT DEBUG: Starting mostRecent sort with ${listToSort.length} items");
        listToSort.sort((a, b) {
          final comparison = b.mediaItem.createdAt.compareTo(a.mediaItem.createdAt);
          // Show first few comparisons for debugging
          if (listToSort.indexOf(a) < 5 || listToSort.indexOf(b) < 5) {
            final aPath = a.mediaItem.path.length > 30 ? a.mediaItem.path.substring(0, 30) + "..." : a.mediaItem.path;
            final bPath = b.mediaItem.path.length > 30 ? b.mediaItem.path.substring(0, 30) + "..." : b.mediaItem.path;
            print('SORT DEBUG: Comparing $aPath (${a.mediaItem.createdAt}) vs $bPath (${b.mediaItem.createdAt}) = $comparison');
          }
          return comparison;
        });
        
        // Debug logging to show final sort order with more detail
        print('SORT DEBUG: Final order after sorting (showing first 20 items):');
        for (int i = 0; i < listToSort.length && i < 20; i++) {
          final item = listToSort[i];
          final expNames = item.associatedExperiences.map((e) => e.name).join(', ');
          print('  [$i] ${item.mediaItem.path.length > 50 ? item.mediaItem.path.substring(0, 50) + "..." : item.mediaItem.path}');
          print('      createdAt: ${item.mediaItem.createdAt}');
          print('      experiences: $expNames');
        }
        
        // Also search for specific items we're interested in
        for (int i = 0; i < listToSort.length; i++) {
          final item = listToSort[i];
          if (item.mediaItem.createdAt.toString().contains('23:53:15') || 
              item.mediaItem.createdAt.toString().contains('23:52:19')) {
            final expNames = item.associatedExperiences.map((e) => e.name).join(', ');
            print('SORT DEBUG: Found target item at position [$i]:');
            print('  Path: ${item.mediaItem.path}');
            print('  CreatedAt: ${item.mediaItem.createdAt}');
            print('  Experiences: $expNames');
          }
        }
      } else if (sortType == ContentSortType.alphabetical) {
        // Sort by the name of the *first* associated experience (ascending)
        listToSort.sort((a, b) {
          if (a.associatedExperiences.isEmpty &&
              b.associatedExperiences.isEmpty) {
            return 0;
          }
          if (a.associatedExperiences.isEmpty) {
            return 1; // Items without experiences go last
          }
          if (b.associatedExperiences.isEmpty) return -1;
          return a.associatedExperiences.first.name
              .toLowerCase()
              .compareTo(b.associatedExperiences.first.name.toLowerCase());
        });
      } else if (sortType == ContentSortType.distanceFromMe) {
        // Sort by the minimum distance calculated in _sortContentByDistance
        // --- MODIFIED: Pass the list to sort ---
        await _sortContentByDistance(listToSort);
        // --- END MODIFIED ---
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
    
    // Debug: Check if the sorted list matches what's being displayed
    print("SORT DEBUG: After setState, checking display list:");
    final displayList = applyToFiltered ? _filteredGroupedContentItems : _groupedContentItems;
    print("SORT DEBUG: Display list length = ${displayList.length}");
    for (int i = 0; i < displayList.length && i < 10; i++) {
      final item = displayList[i];
      final expNames = item.associatedExperiences.map((e) => e.name).join(', ');
      print("  Display[$i]: ${expNames} - ${item.mediaItem.createdAt}");
    }
  }

  // --- REFACTORED: Method to sort grouped content items by distance --- ///
  // MODIFIED: Takes the list to sort as a parameter
  Future<void> _sortContentByDistance(
      List<GroupedContentItem> contentToSort) async {
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

    // Calculate minimum distance for each grouped item in the list to sort
    for (var group in contentToSort) {
      double? minGroupDistance;
      for (var exp in group.associatedExperiences) {
        double? distance;
        final location = exp.location;
        if (location.latitude != 0.0 || location.longitude != 0.0) {
          try {
            distance = Geolocator.distanceBetween(
              currentPosition.latitude,
              currentPosition.longitude,
              location.latitude,
              location.longitude,
            );
            // Update minimum distance for the group
            if (minGroupDistance == null || distance < minGroupDistance) {
              minGroupDistance = distance;
            }
          } catch (e) {
            print("Error calculating distance for ${exp.name}: $e");
            // Distance remains null or the previous minGroupDistance
          }
        } else {
          print(
              "Experience ${exp.name} in group ${group.mediaItem.path} has no valid coordinates.");
        }
      }
      // Store the calculated minimum distance in the object
      group.minDistance = minGroupDistance;
    }

    // Sort the list passed in (contentToSort) based on the calculated minDistance
    contentToSort.sort((a, b) {
      final distA = a.minDistance;
      final distB = b.minDistance;

      if (distA == null && distB == null) {
        return 0; // Keep relative order if both unknown
      }
      if (distA == null) return 1; // Nulls (unknown distances) go to the end
      if (distB == null) return -1; // Nulls go to the end

      return distA.compareTo(distB); // Sort by distance ascending
    });

    print("Grouped content items sorted by distance successfully.");
    }
  // --- END REFACTORED ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Collection'),
        actions: [
          // ADDED: Map Button
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'View Map',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const MapScreen()),
              );
            },
          ),
          // --- MODIFIED: Conditionally show sort button for first tab ---
          if (_currentTabIndex == 0 &&
              _selectedCategory == null &&
              !_showingColorCategories)
            PopupMenuButton<CategorySortType>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort Categories',
              onSelected: (CategorySortType result) {
                _applySortAndSave(result); // Saves text category order
              },
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<CategorySortType>>[
                _buildPopupMenuItem<CategorySortType>(
                  value: CategorySortType.mostRecent,
                  text: 'Sort by Most Recent',
                  currentValue: _categorySortType,
                ),
                _buildPopupMenuItem<CategorySortType>(
                  value: CategorySortType.alphabetical,
                  text: 'Sort Alphabetically',
                  currentValue: _categorySortType,
                ),
              ],
            ),
          // --- ADDED: Sort button for Color Categories --- START ---
          if (_currentTabIndex == 0 &&
              _selectedCategory == null &&
              _showingColorCategories)
            PopupMenuButton<ColorCategorySortType>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort Color Categories',
              onSelected: (ColorCategorySortType result) {
                _applyColorSortAndSave(result); // Saves color category order
              },
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<ColorCategorySortType>>[
                _buildPopupMenuItem<ColorCategorySortType>(
                  value: ColorCategorySortType.mostRecent,
                  text: 'Sort by Most Recent',
                  currentValue: _colorCategorySortType,
                ),
                _buildPopupMenuItem<ColorCategorySortType>(
                  value: ColorCategorySortType.alphabetical,
                  text: 'Sort Alphabetically',
                  currentValue: _colorCategorySortType,
                ),
              ],
            ),
          // --- ADDED: Sort button for Color Categories --- END ---
          if (_currentTabIndex == 1)
            PopupMenuButton<ExperienceSortType>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort Experiences',
              onSelected: (ExperienceSortType result) {
                _applyExperienceSort(result);
              },
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<ExperienceSortType>>[
                _buildPopupMenuItem<ExperienceSortType>(
                  value: ExperienceSortType.mostRecent,
                  text: 'Sort by Most Recent',
                  currentValue: _experienceSortType,
                ),
                _buildPopupMenuItem<ExperienceSortType>(
                  value: ExperienceSortType.alphabetical,
                  text: 'Sort Alphabetically',
                  currentValue: _experienceSortType,
                ),
                _buildPopupMenuItem<ExperienceSortType>(
                  value: ExperienceSortType.distanceFromMe,
                  text: 'Sort by Distance',
                  currentValue: _experienceSortType,
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
                _buildPopupMenuItem<ContentSortType>(
                  value: ContentSortType.mostRecent,
                  text: 'Sort by Most Recent Added',
                  currentValue: _contentSortType,
                ),
                _buildPopupMenuItem<ContentSortType>(
                  value: ContentSortType.alphabetical,
                  text: 'Sort Alphabetically (by Experience)',
                  currentValue: _contentSortType,
                ),
                _buildPopupMenuItem<ContentSortType>(
                  value: ContentSortType.distanceFromMe,
                  text: 'Sort by Distance (from Experience)',
                  currentValue: _contentSortType,
                ),
              ],
            ),
          // --- ADDED: Filter Button for Experiences and Content tabs ---
          if (_currentTabIndex == 1 || _currentTabIndex == 2)
            IconButton(
              icon: const Icon(Icons.filter_list),
              tooltip: 'Filter Items',
              onPressed: () {
                _showFilterDialog();
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ADDED: Search Bar Area
                Builder( // ADDED Builder for conditional width
                  builder: (context) {
                    final bool isDesktopWeb = kIsWeb && MediaQuery.of(context).size.width > 600;
                    
                    // Original search bar widget (TypeAheadField wrapped in Padding)
                    // This definition includes the original Padding and TypeAheadField configuration.
                    Widget searchBarWidget = Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12.0, vertical: 4.0),
                      child: TypeAheadField<Experience>(
                        builder: (context, controller, focusNode) {
                          return TextField(
                            controller: controller, // This is TypeAhead's controller
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
                                  controller.clear(); // Clear TypeAhead's controller
                                  _searchController.clear(); // Clear state's controller
                                  FocusScope.of(context).unfocus();
                                  // setState(() {}); // Removed as TypeAheadField/TextField should update with controller
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
                          final category = _categories.firstWhere(
                              (cat) => cat.id == suggestion.categoryId, 
                              orElse: () => UserCategory(
                                  id: '', 
                                  name: suggestion.categoryId != null 
                                      ? 'Category Not Found' 
                                      : 'Uncategorized', 
                                  icon: '❓', 
                                  ownerUserId: '' 
                              )
                          );

                          final result = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ExperiencePageScreen(
                                experience: suggestion,
                                category: category, 
                                userColorCategories: _colorCategories,
                              ),
                            ),
                          );
                          _searchController.clear(); 
                          FocusScope.of(context).unfocus();
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
                    );

                    if (isDesktopWeb) {
                      return Center( // Center the search bar on desktop
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width * 0.3, // 50% of screen width
                          child: searchBarWidget,
                        ),
                      );
                    } else {
                      return searchBarWidget; // Original layout for mobile/mobile-web
                    }
                  }
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
                      // _selectedCategory == null
                      //     ? _buildCategoriesList()
                      //     : _buildCategoryExperiencesList(_selectedCategory!),
                      // --- MODIFIED: First tab now uses Column and toggle ---
                      Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 8.0),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                icon: Icon(_showingColorCategories
                                    ? Icons.category_outlined
                                    : Icons.color_lens_outlined),
                                label: Text(_showingColorCategories
                                    ? 'Categories'
                                    : 'Color Categories'),
                                onPressed: () {
                                  setState(() {
                                    _showingColorCategories =
                                        !_showingColorCategories;
                                    _selectedCategory =
                                        null; // Clear selected text category when switching views
                                    _selectedColorCategory =
                                        null; // Clear selected color category when switching views
                                  });
                                },
                              ),
                            ),
                          ),
                          Expanded(
                            child: _selectedCategory != null
                                ? _buildCategoryExperiencesList(
                                    _selectedCategory!) // Still show experiences if a text category was selected
                                // --- MODIFIED: Check for selected color category first --- START ---
                                : _selectedColorCategory != null
                                    ? _buildColorCategoryExperiencesList(
                                        _selectedColorCategory!) // Show color experiences
                                    : _showingColorCategories
                                        ? _buildColorCategoriesList() // Show color list
                                        : _buildCategoriesList(), // Show text list
                            // --- MODIFIED: Check for selected color category first --- END ---
                          ),
                        ],
                      ),
                      // --- END MODIFIED ---
                      _buildExperiencesListView(),
                      // MODIFIED: Call builder for Content tab
                      _buildContentTabBody(),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: _showingColorCategories
          ? FloatingActionButton(
              onPressed: _showAddColorCategoryModal, // Call new modal func
              tooltip: 'Add Color Category',
              child: const Icon(Icons.add),
            )
          : _currentTabIndex == 0 && _selectedCategory == null
              ? FloatingActionButton(
                  onPressed: _showAddCategoryModal, // Original action
                  tooltip: 'Add Category',
                  child: const Icon(Icons.add),
                )
              : _currentTabIndex == 1 // ADDED: FAB for experiences tab
                  ? FloatingActionButton(
                      onPressed: _showAddExperienceModal,
                      tooltip: 'Add Experience',
                      child: const Icon(Icons.add),
                    )
                  : null, // No FAB for other tabs
    );
  }

  // REFACTORED: Extracted list item builder for reuse
  Widget _buildExperienceListItem(Experience experience) {
    // Find the matching category icon and name using categoryId
    final UserCategory category = _categories.firstWhere(
      (cat) => cat.id == experience.categoryId,
      orElse: () => UserCategory(
        id: '', // Default/fallback category
        name: 'Uncategorized',
        icon: '❓',
        ownerUserId: '', // Should be filled if applicable, or handle differently
      ),
    );
    final categoryIcon = category.icon;
    final categoryName = category.name;

    // Get the full address
    final fullAddress = experience.location.address;
    // Get the first image URL or null
    final String? imageUrl = experience.location.photoUrl; // REVERTED: Directly use photoUrl

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
      // --- MODIFIED: Integrate indicator into title --- START ---
      title: Row(
        mainAxisSize:
            MainAxisSize.min, // Prevent Row from taking excessive space
        children: [
          Expanded(
            child: Text(
              experience.name,
              overflow:
                  TextOverflow.ellipsis, // Prevent overflow if name is long
              maxLines: 1,
            ),
          ),
          // Add spacing
          const SizedBox(width: 8),
          // Color Indicator Circle
          if (experience.colorCategoryId != null)
            Builder(
              builder: (context) {
                final colorCategory = _colorCategories.firstWhereOrNull(
                  (cat) => cat.id == experience.colorCategoryId,
                );
                if (colorCategory != null) {
                  return Container(
                    width: 10, // User adjusted size
                    height: 10,
                    decoration: BoxDecoration(
                      color: colorCategory.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).dividerColor,
                        width: 1,
                      ),
                    ),
                    child: Tooltip(message: colorCategory.name),
                  );
                } else {
                  return const SizedBox(
                      width: 10,
                      height: 10); // Maintain space even if category not found
                }
              },
            ),
        ],
      ),
      // --- MODIFIED: Integrate indicator into title --- END ---
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fullAddress != null && fullAddress.isNotEmpty)
            Text(
              fullAddress, // Use full address
              style: Theme.of(context).textTheme.bodySmall,
            ),
          // --- MODIFIED: Primary category and other categories in same row ---
          Row(
            children: [
              // Primary category on the left
              Expanded(
                child: Text(
                  '$categoryIcon $categoryName', // Use looked-up category name
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              // Other categories icons on the right
              if (experience.otherCategories.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: experience.otherCategories
                      .map((categoryId) {
                        // Find the category object for this ID
                        final otherCategory = _categories.firstWhereOrNull(
                          (cat) => cat.id == categoryId,
                        );
                        if (otherCategory != null) {
                          return Padding(
                            padding: const EdgeInsets.only(left: 4.0),
                            child: Text(
                              otherCategory.icon,
                              style: const TextStyle(fontSize: 14),
                            ),
                          );
                        }
                        return const SizedBox.shrink(); // Skip if category not found
                      })
                      .toList(),
                ),
            ],
          ),
          // --- END MODIFIED ---
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

        // Find the matching category for the tapped experience using categoryId
        final UserCategory resolvedCategory = _categories.firstWhere(
          (cat) => cat.id == experience.categoryId,
          orElse: () => UserCategory(
            id: '',
            name: 'Uncategorized', // Fallback name
            icon: '❓', // Fallback icon
            ownerUserId: '', // Needs a valid owner or handle this case
          ),
        );

        // Await result and refresh if needed
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => ExperiencePageScreen(
              experience: experience,
              category: resolvedCategory, // Pass the resolved category
              userColorCategories: _colorCategories,
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

  // ADDED: Widget builder for an Experience Grid Item (for web)
  Widget _buildExperienceGridItem(Experience experience, bool isDesktopWeb) { // ADDED isDesktopWeb parameter
    final category = _categories.firstWhereOrNull((cat) => cat.id == experience.categoryId);
    final categoryIcon = category?.icon ?? '❓';
    final colorCategory = _colorCategories.firstWhereOrNull((cc) => cc.id == experience.colorCategoryId);
    final color = colorCategory != null ? _parseColor(colorCategory.colorHex) : Theme.of(context).disabledColor;
    final String? locationArea = experience.location.getFormattedArea();
    final String? photoUrl = experience.location.photoUrl;

    Widget categoryIconWidget = Container(
      height: 60, // MODIFIED: Reduced height
      color: color.withOpacity(0.15),
      padding: const EdgeInsets.symmetric(horizontal: 8.0), // Add some padding
      child: Center(
        child: Row( // MODIFIED: Use a Row for icon and text on the same line
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Text(
              categoryIcon,
              style: TextStyle(fontSize: 20, color: color), // MODIFIED: Smaller icon size
            ),
            const SizedBox(width: 8), // Space between icon and text
            if (category != null) // Add category name if category exists
              Expanded( // Use Expanded to handle long names
                child: Text(
                  category.name,
                  style: TextStyle(fontSize: 14, color: color.withOpacity(0.9)), // MODIFIED: Style for name
                  textAlign: TextAlign.left, // Align to left after icon
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );

    // Content (name, location, color category)
    Widget textContentColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 4.0),
          child: Text(
            experience.name,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  // Conditional color will be applied if it's part of a stack with background
                ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (locationArea != null && locationArea.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              locationArea,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const Spacer(), 
        if (colorCategory != null)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Icon(Icons.circle, color: colorCategory.color /* Use parsed color from model */, size: 10),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    colorCategory.name,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorCategory.color /* Use parsed color */),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    Widget lowerSectionContent;
    if (isDesktopWeb && photoUrl != null && photoUrl.isNotEmpty) {
      // Apply white text color for contrast against photo background
      Widget textContentWithWhiteColor = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 4.0),
            child: Text(
              experience.name,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white, // White text
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (locationArea != null && locationArea.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                locationArea,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70), // White text
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const Spacer(), 
          if (colorCategory != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  // Use a white circle or icon if colorCategory.color is too dark for the overlay
                  Icon(Icons.circle, color: colorCategory.color, size: 10), // MODIFIED: Use actual category color
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      colorCategory.name,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white), // White text for label
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
      
      lowerSectionContent = Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Image.network(
              photoUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(child: CircularProgressIndicator(strokeWidth: 2.0));
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.grey[300], // Placeholder if image fails
                  child: Center(child: Icon(Icons.broken_image_outlined, color: Colors.grey[500])),
                );
              },
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.5), // Dark overlay for text readability
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(0), // Padding is handled by textContentWithWhiteColor
            child: textContentWithWhiteColor,
          ),
        ],
      );
    } else {
      // If not desktop web or no photo, use the original textContentColumn directly
      lowerSectionContent = textContentColumn;
    }

    return Card(
      key: ValueKey('experience_grid_${experience.id}'),
      clipBehavior: Clip.antiAlias,
      elevation: 2.0,
      child: InkWell(
        onTap: () {
          final resolvedCategory = category ?? UserCategory(
            id: experience.categoryId ?? 'uncategorized',
            name: category?.name ?? 'Uncategorized', // Use category name if available
            icon: categoryIcon, // Use resolved icon
            ownerUserId: category?.ownerUserId ?? _authService.currentUser?.uid ?? 'system_default',
            orderIndex: category?.orderIndex ?? 9999, // Use category orderIndex or default
          );
          Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => ExperiencePageScreen(
                experience: experience,
                category: resolvedCategory,
                userColorCategories: _colorCategories,
              ),
            ),
          ).then((result) {
            if (result == true && mounted) {
              _loadData();
            }
          });
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            categoryIconWidget, // Category icon always on top
            Expanded(child: lowerSectionContent), // Lower section takes remaining space
            // Padding(
            //   padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 4.0),
            //   child: Text(
            // ... existing code ...
          ],
        ),
      ),
    );
  }

  // MODIFIED: Widget builder for the Experience List View uses the refactored item builder
  Widget _buildExperiencesListView() {
    if (_filteredExperiences.isEmpty) {
      bool filtersActive = _selectedCategoryIds.isNotEmpty ||
          _selectedColorCategoryIds.isNotEmpty;
      return Center(
          child: Text(filtersActive
              ? 'No experiences match the current filters.'
              : 'No experiences found. Add some!'));
    }

    final bool isDesktopWeb = kIsWeb && MediaQuery.of(context).size.width > 600;

    if (isDesktopWeb) {
      final screenWidth = MediaQuery.of(context).size.width;
      const double contentMaxWidth = 1200.0;
      const double defaultPadding = 12.0; // Original all-around padding was 12.0

      double horizontalPadding;
      if (screenWidth > contentMaxWidth) {
        horizontalPadding = (screenWidth - contentMaxWidth) / 2;
      } else {
        horizontalPadding = defaultPadding;
      }

      // Web: Use GridView.builder
      return GridView.builder(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: defaultPadding),
        itemCount: _filteredExperiences.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12.0,
          crossAxisSpacing: 12.0,
          childAspectRatio: 0.75, //  (width / height) - results in items being taller than wide
        ),
        itemBuilder: (context, index) {
          return _buildExperienceGridItem(_filteredExperiences[index], isDesktopWeb); // MODIFIED: Pass isDesktopWeb
        },
      );
    } else {
      // Mobile: Use existing ListView.builder
      return ListView.builder(
        itemCount: _filteredExperiences.length,
        itemBuilder: (context, index) {
          return _buildExperienceListItem(_filteredExperiences[index]);
        },
      );
    }
  }

  // ADDED: Widget to display experiences for a specific category
  Widget _buildCategoryExperiencesList(UserCategory category) {
    final categoryExperiences = _experiences
        .where((exp) => 
          exp.categoryId == category.id || 
          exp.otherCategories.contains(category.id)
        ) // MODIFIED: Include experiences with this category as primary OR in otherCategories
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

  // --- REFACTORED: Widget builder for the Content Tab Body --- ///
  Widget _buildContentTabBody() {
    if (_filteredGroupedContentItems.isEmpty) {
      bool filtersActive = _selectedCategoryIds.isNotEmpty || _selectedColorCategoryIds.isNotEmpty;
      return Center(
          child: Text(filtersActive
              ? 'No content matches the current filters.'
              : 'No shared content found across experiences.'));
    }

    final bool isDesktopWeb = kIsWeb && MediaQuery.of(context).size.width > 600;

    if (isDesktopWeb) {
      final screenWidth = MediaQuery.of(context).size.width;
      const double contentMaxWidth = 1200.0;
      const double defaultPadding = 10.0; // Original all-around padding was 10.0

      double horizontalPadding;
      if (screenWidth > contentMaxWidth) {
        horizontalPadding = (screenWidth - contentMaxWidth) / 2;
      } else {
        horizontalPadding = defaultPadding;
      }

      // Web: Use GridView.builder
      return GridView.builder(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: defaultPadding),
        itemCount: _filteredGroupedContentItems.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10.0,
          crossAxisSpacing: 10.0,
          childAspectRatio: 0.6, 
        ),
        itemBuilder: (context, index) {
          return _buildContentGridItem(_filteredGroupedContentItems[index], index);
        },
      );
    } else {
      // Mobile or Mobile Web: Use existing ListView.builder (original complex list item)
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        itemCount: _filteredGroupedContentItems.length,
        itemBuilder: (context, index) {
          final group = _filteredGroupedContentItems[index];
          final mediaItem = group.mediaItem;
          final mediaPath = mediaItem.path;
          final associatedExperiences = group.associatedExperiences;
          final isExpanded = _contentExpansionStates[mediaPath] ?? false;
          final bool isInstagramUrl =
              mediaPath.toLowerCase().contains('instagram.com');
          final bool isTikTokUrl = mediaPath.toLowerCase().contains('tiktok.com') ||
              mediaPath.toLowerCase().contains('vm.tiktok.com');
          final bool isFacebookUrl = mediaPath.toLowerCase().contains('facebook.com') ||
              mediaPath.toLowerCase().contains('fb.com') ||
              mediaPath.toLowerCase().contains('fb.watch');
          final bool isYouTubeUrl = mediaPath.toLowerCase().contains('youtube.com') ||
              mediaPath.toLowerCase().contains('youtu.be') ||
              mediaPath.toLowerCase().contains('youtube.com/shorts');
          bool isNetworkUrl =
              mediaPath.startsWith('http') || mediaPath.startsWith('https');

          Widget mediaWidget;
          if (isTikTokUrl) {
            mediaWidget = TikTokPreviewWidget(
              url: mediaPath,
              launchUrlCallback: _launchUrl,
            );
          } else if (isInstagramUrl) {
            mediaWidget = instagram_widget.InstagramWebView(
              url: mediaPath,
              height: 640.0, // Height for InstagramWebView
              launchUrlCallback: _launchUrl,
              onWebViewCreated: (_) {},
              onPageFinished: (_) {},
            );
            // Ensure no Center/ConstrainedBox here for mobile web list view
          } else if (isFacebookUrl) {
            mediaWidget = FacebookPreviewWidget(
              url: mediaPath,
              height: 500.0, // Height for FacebookPreviewWidget
              launchUrlCallback: _launchUrl,
              onWebViewCreated: (_) {},
              onPageFinished: (_) {},
            );
          } else if (isYouTubeUrl) {
            mediaWidget = YouTubePreviewWidget(
              url: mediaPath,
              launchUrlCallback: _launchUrl,
            );
          } else if (isNetworkUrl) {
            // Check if it's an image URL
            if (mediaPath.toLowerCase().endsWith('.jpg') ||
                mediaPath.toLowerCase().endsWith('.jpeg') ||
                mediaPath.toLowerCase().endsWith('.png') ||
                mediaPath.toLowerCase().endsWith('.gif') ||
                mediaPath.toLowerCase().endsWith('.webp')) {
              mediaWidget = Image.network(
                mediaPath,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
                errorBuilder: (context, error, stackTrace) {
                  print("Error loading image $mediaPath: $error");
                  return Container(
                    color: Colors.grey[200],
                    height: 200, 
                    child: Center(
                        child: Icon(Icons.broken_image_outlined,
                            color: Colors.grey[600], size: 40)),
                  );
                },
              );
            } else {
              // Use generic URL preview for other network URLs
              mediaWidget = GenericUrlPreviewWidget(
                url: mediaPath,
                launchUrlCallback: _launchUrl,
              );
            }
          } else {
            mediaWidget = Container(
              color: Colors.grey[300],
              height: 150, 
              child: Center(
                  child: Icon(Icons.description, color: Colors.grey[700], size: 40)),
            );
          }

          return Padding(
            key: ValueKey(mediaPath),
            padding: const EdgeInsets.only(bottom: 24.0),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Center(
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
                ),
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 2.0,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12.0, vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (associatedExperiences.length > 1)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6.0),
                                child: Text(
                                  'Linked Experiences (${associatedExperiences.length}):',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                ),
                              ),
                            ...associatedExperiences.map((exp) {
                              final category = _categories.firstWhereOrNull(
                                  (cat) => cat.id == exp.categoryId);
                              final categoryIcon = category?.icon ?? '❓';
                              final colorCategory = _colorCategories
                                  .firstWhereOrNull(
                                      (cc) => cc.id == exp.colorCategoryId);
                              final color = colorCategory != null
                                  ? _parseColor(colorCategory.colorHex)
                                  : Theme.of(context).disabledColor;

                              return InkWell(
                                onTap: () {
                                  final resolvedCategory = category ?? UserCategory(
                                    id: exp.categoryId ?? 'uncategorized',
                                    name: category?.name ?? 'Uncategorized',
                                    icon: categoryIcon,
                                    ownerUserId: category?.ownerUserId ?? _authService.currentUser?.uid ?? 'system_default',
                                    orderIndex: category?.orderIndex ?? 9999,
                                  );
                                  Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ExperiencePageScreen(
                                        experience: exp,
                                        category: resolvedCategory,
                                        userColorCategories: _colorCategories,
                                      ),
                                    ),
                                  ).then((result) {
                                    if (result == true && mounted) {
                                      _loadData();
                                    }
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                                  child: Row(
                                    children: [
                                      Text(categoryIcon, style: const TextStyle(fontSize: 16)),
                                      const SizedBox(width: 6),
                                      if (colorCategory != null)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 6.0),
                                          child: Icon(Icons.circle, color: color, size: 10),
                                        ),
                                      Expanded(
                                        child: Text(
                                          exp.name,
                                          style: Theme.of(context).textTheme.bodyMedium,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
                                    ],
                                  ),
                                ),
                              );
                            }),
                            if (associatedExperiences.isEmpty)
                              const Text('No linked experiences.',
                                  style: TextStyle(fontStyle: FontStyle.italic)),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _contentExpansionStates[mediaPath] = !isExpanded;
                          });
                        },
                        child: mediaWidget,
                      ),
                      if (isInstagramUrl)
                        Container(
                          color: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const FaIcon(FontAwesomeIcons.instagram),
                                color: const Color(0xFFE4405F),
                                iconSize: 32,
                                tooltip: 'Open in Instagram',
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                onPressed: () => _launchUrl(mediaPath),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  // --- ADDED: Method to show delete confirmation dialog for content ---
  Future<void> _showDeleteContentConfirmation(GroupedContentItem group) async {
    final mediaItem = group.mediaItem;
    final associatedExperiences = group.associatedExperiences;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Content?'),
        content: Column(
          // Use Column for better layout
          mainAxisSize: MainAxisSize.min, // Prevent excessive height
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to permanently delete this content?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // Display the content path or a placeholder
            Text(
              mediaItem.path.contains('instagram.com')
                  ? 'Instagram Post'
                  : mediaItem.path.contains('facebook.com') || mediaItem.path.contains('fb.com') || mediaItem.path.contains('fb.watch')
                    ? 'Facebook Post'
                    : mediaItem.path.contains('tiktok.com') || mediaItem.path.contains('vm.tiktok.com')
                      ? 'TikTok Post'
                      : mediaItem.path.contains('youtube.com') || mediaItem.path.contains('youtu.be')
                          ? 'YouTube Video'
                          : mediaItem.path.split('/').last, // Show filename if possible
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontStyle: FontStyle.italic),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            Text(
                'It will also be unlinked from the following ${associatedExperiences.length} experience(s):'),
            const SizedBox(height: 8),
            // List associated experiences concisely
            Container(
              constraints: BoxConstraints(maxHeight: 100), // Limit height
              child: SingleChildScrollView(
                // Make it scrollable if many
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: associatedExperiences
                      .map((exp) => Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: Text('• ${exp.name}',
                                style: Theme.of(context).textTheme.bodySmall),
                          ))
                      .toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'This action cannot be undone.',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
        ),
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
      // Show loading indicator while deleting
      setState(() => _isLoading = true);
      try {
        // --- Call ExperienceService method ---
        await _experienceService.deleteSharedMediaItemAndUnlink(
          mediaItem.id,
          associatedExperiences.map((e) => e.id).toList(),
        );
        print('Deletion confirmed for: ${mediaItem.path}');
        print(
            'Associated Experience IDs: ${associatedExperiences.map((e) => e.id).toList()}');
        // --- END Call ---

        print('Content "${mediaItem.path}" deleted and unlinked successfully.');
        if (mounted) {
          // Hide loading indicator
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Content deleted.')),
          );
          _loadData(); // Refresh the screen
        }
      } catch (e) {
        print("Error deleting content: $e");
        if (mounted) {
          // Hide loading indicator
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting content: $e')),
          );
        }
      }
    }
  }
  // --- END ADDED ---

  // --- ADDED: Methods for Color Category Editing --- START ---

  Future<void> _showAddColorCategoryModal() async {
    final result = await showModalBottomSheet<ColorCategory>(
      context: context,
      builder: (_) => const AddColorCategoryModal(),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );

    if (result != null) {
      print("AddColorCategoryModal returned, refreshing data...");
      _loadData(); // Refresh both lists
    }
  }

  Future<void> _showEditSingleColorCategoryModal(ColorCategory category) async {
    final result = await showModalBottomSheet<ColorCategory>(
      context: context,
      builder: (_) => AddColorCategoryModal(categoryToEdit: category),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );

    if (result != null) {
      print(
          "🎨 COLLECTIONS_SCREEN: EditColorCategoryModal returned result: ${result.id} - ${result.name}, refreshing data...");
      _loadData();
    } else {
      print(
          "🎨 COLLECTIONS_SCREEN: EditColorCategoryModal closed without saving.");
    }
  }

  Future<void> _showDeleteColorCategoryConfirmation(
      ColorCategory category) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Color Category?'),
        content: Text(
            'Are you sure you want to delete the "${category.name}" category? Experiences using this color will lose it. This cannot be undone.'),
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
        await _experienceService.deleteColorCategory(category.id);
        print('Color Category "${category.name}" deleted successfully.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${category.name}" category deleted.')),
          );
          _loadData(); // Refresh data
        }
      } catch (e) {
        print("Error deleting color category: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting color category: $e')),
          );
        }
      }
    }
  }

  void _updateLocalColorOrderIndices() {
    for (int i = 0; i < _colorCategories.length; i++) {
      _colorCategories[i] = _colorCategories[i].copyWith(orderIndex: i);
    }
    print("Updated local color category order indices.");
  }

  Future<void> _saveColorCategoryOrder() async {
    setState(() => _isLoading = true);
    final List<Map<String, dynamic>> updates = [];
    for (final category in _colorCategories) {
      if (category.id.isNotEmpty && category.orderIndex != null) {
        updates.add({
          'id': category.id,
          'orderIndex': category.orderIndex!,
        });
      } else {
        print(
            "Warning: Skipping color category in save order with missing id or index: ${category.name}");
      }
    }

    if (updates.isEmpty) {
      print("No valid color category updates to save.");
      setState(() => _isLoading = false);
      return;
    }

    try {
      print("Attempting to save order for ${updates.length} color categories.");
      await _experienceService.updateColorCategoryOrder(updates);
      print("Color category order saved successfully.");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print("Error saving color category order: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving color category order: $e")),
        );
        setState(() => _isLoading = false);
        _loadData(); // Revert on error
      }
    }
  }

  Future<void> _applyColorSortAndSave(ColorCategorySortType sortType) async {
    print("Applying color category sort: $sortType");
    setState(() {
      if (sortType == ColorCategorySortType.alphabetical) {
        _colorCategories.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      } else if (sortType == ColorCategorySortType.mostRecent) {
        _colorCategories.sort((a, b) {
          final tsA = a.lastUsedTimestamp;
          final tsB = b.lastUsedTimestamp;
          if (tsA == null && tsB == null) {
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }
          if (tsA == null) return 1;
          if (tsB == null) return -1;
          return tsB.compareTo(tsA);
        });
      }
      _updateLocalColorOrderIndices();
    });
    await _saveColorCategoryOrder();
  }

  // --- ADDED: Helper to count experiences for a specific color category --- START ---
  int _getExperienceCountForColorCategory(ColorCategory category) {
    // Filter experiences where colorCategoryId matches the category's ID
    return _experiences
        .where((exp) => exp.colorCategoryId == category.id)
        .length;
  }
  // --- ADDED: Helper to count experiences for a specific color category --- END ---

  // --- ADDED: Widget builder for a Color Category Grid Item (for web) ---
  Widget _buildColorCategoryGridItem(ColorCategory category) {
    final count = _getExperienceCountForColorCategory(category);
    return Card(
      key: ValueKey('color_category_grid_${category.id}'),
      clipBehavior: Clip.antiAlias,
      elevation: 2.0,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedColorCategory = category;
            _showingColorCategories = true; 
            _selectedCategory = null;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 28, 
                height: 28,
                decoration: BoxDecoration(
                  color: category.color, 
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).dividerColor, width: 1.5),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                category.name,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '$count ${count == 1 ? "exp" : "exps"}',
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- ADDED: Builder for Color Category List --- START ---
  Widget _buildColorCategoriesList() {
    if (_colorCategories.isEmpty) {
      return const Center(child: Text('No color categories found.'));
    }

    final bool isDesktopWeb = kIsWeb && MediaQuery.of(context).size.width > 600;

    if (isDesktopWeb) {
      // Web: Use GridView.builder
      return GridView.builder(
        padding: const EdgeInsets.all(12.0),
        itemCount: _colorCategories.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10.0,
          crossAxisSpacing: 10.0,
          childAspectRatio: 3/3, // Square items for color categories
        ),
        itemBuilder: (context, index) {
          final category = _colorCategories[index];
          return _buildColorCategoryGridItem(category);
        },
      );
    } else {
      // Mobile: Use existing ReorderableListView.builder
      return ReorderableListView.builder(
        itemCount: _colorCategories.length,
        itemBuilder: (context, index) {
          final category = _colorCategories[index];
          final count = _getExperienceCountForColorCategory(category);
          return ListTile(
            key: ValueKey(category.id),
            leading: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                  color: category.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade400, width: 1)),
            ),
            title: Text(category.name),
            subtitle: Text('$count ${count == 1 ? "experience" : "experiences"}'),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'Color Category Options',
              onSelected: (String result) {
                switch (result) {
                  case 'edit':
                    _showEditSingleColorCategoryModal(category);
                    break;
                  case 'delete':
                    _showDeleteColorCategoryConfirmation(category);
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
              setState(() {
                _selectedColorCategory = category;
                _showingColorCategories = true; 
                _selectedCategory = null;
              });
              print(
                  'Tapped on color category: ${category.name}, showing experiences.');
            },
          );
        },
        onReorder: (int oldIndex, int newIndex) {
          setState(() {
            if (newIndex > oldIndex) {
              newIndex -= 1;
            }
            final ColorCategory item = _colorCategories.removeAt(oldIndex);
            _colorCategories.insert(newIndex, item);
            _updateLocalColorOrderIndices();
            print("Color categories reordered locally. Triggering save.");
            _saveColorCategoryOrder();
          });
        },
      );
    }
  }
  // --- ADDED: Builder for Color Category List --- END ---

  // --- ADDED: Widget to display experiences for a specific color category --- START ---
  Widget _buildColorCategoryExperiencesList(ColorCategory category) {
    final categoryExperiences = _experiences
        .where((exp) => exp.colorCategoryId == category.id)
        .toList(); // Filter experiences by colorCategoryId

    // Apply the current experience sort order (reuse existing logic if applicable)
    // Note: This creates a sorted copy
    if (_experienceSortType == ExperienceSortType.alphabetical) {
      categoryExperiences
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else if (_experienceSortType == ExperienceSortType.mostRecent) {
      categoryExperiences.sort((a, b) {
        return b.createdAt.compareTo(a.createdAt);
      });
    } // TODO: Implement distance sort for this view if needed

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row with back button and color category name
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to Color Categories',
                onPressed: () {
                  setState(() {
                    _selectedColorCategory =
                        null; // Go back to color category list
                  });
                },
              ),
              const SizedBox(width: 8),
              // Show color circle and name
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                    color: category.color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade400, width: 1)),
              ),
              const SizedBox(width: 8),
              Text(
                category.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              // Optional: Add sort button specific to this filtered view
            ],
          ),
        ),
        const Divider(height: 1),
        // List of experiences for this color category
        Expanded(
          child: categoryExperiences.isEmpty
              ? Center(
                  child: Text(
                      'No experiences found with the "${category.name}" color category.'))
              : ListView.builder(
                  itemCount: categoryExperiences.length,
                  itemBuilder: (context, index) {
                    // Reuse the existing list item builder
                    return _buildExperienceListItem(categoryExperiences[index]);
                  },
                ),
        ),
      ],
    );
  }
  // --- ADDED: Widget to display experiences for a specific color category --- END ---

  // ADDED: Helper function to build popup menu items with visual indicators
  PopupMenuItem<T> _buildPopupMenuItem<T>({
    required T value,
    required String text,
    required T currentValue,
  }) {
    final bool isSelected = value == currentValue;
    return PopupMenuItem<T>(
      value: value,
      child: Row(
        children: [
          Icon(
            isSelected ? Icons.check : Icons.radio_button_off,
            color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? Theme.of(context).primaryColor : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- ADDED: Filter Dialog & Logic (Adapted from map_screen) --- START ---
  Future<void> _showFilterDialog() async {
    // Temporary sets for dialog state
    Set<String> tempSelectedCategoryIds = Set.from(_selectedCategoryIds);
    Set<String> tempSelectedColorCategoryIds =
        Set.from(_selectedColorCategoryIds);

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Filter Items'),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setStateDialog) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('By Category:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    if (_categories.isEmpty)
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text('No categories available.')),
                    ...(_categories.toList()
                          ..sort((a, b) => a.name.compareTo(b.name)))
                        .map((category) {
                      return CheckboxListTile(
                        title: Text('${category.icon} ${category.name}'),
                        value: tempSelectedCategoryIds.contains(category.id),
                        controlAffinity:
                            ListTileControlAffinity.leading, // Checkbox on left
                        contentPadding:
                            EdgeInsets.zero, // Remove default padding
                        onChanged: (bool? selected) {
                          setStateDialog(() {
                            if (selected == true) {
                              tempSelectedCategoryIds.add(category.id);
                            } else {
                              tempSelectedCategoryIds.remove(category.id);
                            }
                          });
                        },
                      );
                    }),
                    const SizedBox(height: 16),
                    const Text('By Color:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    if (_colorCategories.isEmpty)
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text('No color categories available.')),
                    ...(_colorCategories.toList()
                          ..sort((a, b) => a.name.compareTo(b.name)))
                        .map((colorCategory) {
                      return CheckboxListTile(
                        controlAffinity:
                            ListTileControlAffinity.leading, // Checkbox on left
                        contentPadding:
                            EdgeInsets.zero, // Remove default padding
                        title: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                  color: _parseColor(
                                      colorCategory.colorHex), // Use helper
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.grey)),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                                child: Text(colorCategory.name,
                                    overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                        value: tempSelectedColorCategoryIds
                            .contains(colorCategory.id),
                        onChanged: (bool? selected) {
                          setStateDialog(() {
                            if (selected == true) {
                              tempSelectedColorCategoryIds
                                  .add(colorCategory.id);
                            } else {
                              tempSelectedColorCategoryIds
                                  .remove(colorCategory.id);
                            }
                          });
                        },
                      );
                    }),
                  ],
                ),
              );
            },
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Show All'),
              onPressed: () {
                // Clear temporary selections
                tempSelectedCategoryIds.clear();
                tempSelectedColorCategoryIds.clear();
                // Apply cleared filters directly
                setState(() {
                  _selectedCategoryIds = tempSelectedCategoryIds;
                  _selectedColorCategoryIds = tempSelectedColorCategoryIds;
                });
                Navigator.of(context).pop(); // Close dialog
                _applyFiltersAndUpdateLists(); // Update lists
              },
            ),
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Apply'),
              onPressed: () {
                // Apply filters from dialog state
                setState(() {
                  _selectedCategoryIds = tempSelectedCategoryIds;
                  _selectedColorCategoryIds = tempSelectedColorCategoryIds;
                });
                Navigator.of(context).pop(); // Close dialog
                _applyFiltersAndUpdateLists(); // Update lists
              },
            ),
          ],
        );
      },
    );
  }

  void _applyFiltersAndUpdateLists() {
    print("🎨 COLLECTIONS SCREEN: Applying filters...");
    // Filter experiences
    final filteredExperiences = _experiences.where((exp) {
      // MODIFIED: Also check otherCategories for a match
      final bool categoryMatch = _selectedCategoryIds.isEmpty ||
          (exp.categoryId != null &&
              _selectedCategoryIds.contains(exp.categoryId)) ||
          (exp.otherCategories.any((catId) => _selectedCategoryIds.contains(catId)));

      final bool colorMatch = _selectedColorCategoryIds.isEmpty ||
          (exp.colorCategoryId != null &&
              _selectedColorCategoryIds.contains(exp.colorCategoryId));

      return categoryMatch && colorMatch;
    }).toList();

    // Filter grouped content items
    final filteredGroupedContent = _groupedContentItems.where((group) {
      // Include the group if ANY of its associated experiences match the filters
      return group.associatedExperiences.any((exp) {
        // MODIFIED: Also check otherCategories for a match
        final bool categoryMatch = _selectedCategoryIds.isEmpty ||
            (exp.categoryId != null &&
                _selectedCategoryIds.contains(exp.categoryId)) ||
            (exp.otherCategories.any((catId) => _selectedCategoryIds.contains(catId)));

        final bool colorMatch = _selectedColorCategoryIds.isEmpty ||
            (exp.colorCategoryId != null &&
                _selectedColorCategoryIds.contains(exp.colorCategoryId));

        return categoryMatch && colorMatch;
      });
    }).toList();

    print(
        "🎨 COLLECTIONS SCREEN: Experiences filtered to ${filteredExperiences.length}");
    print(
        "🎨 COLLECTIONS SCREEN: Content groups filtered to ${filteredGroupedContent.length}");

    // Update the state with the filtered lists
    setState(() {
      _filteredExperiences = filteredExperiences;
      _filteredGroupedContentItems = filteredGroupedContent;
    });

    // Re-apply sorting to the newly filtered lists
    // This ensures the sort order is maintained after filtering
    _applyExperienceSort(_experienceSortType, applyToFiltered: true);
    _applyContentSort(_contentSortType, applyToFiltered: true);
  }
  // --- ADDED: Filter Dialog & Logic (Adapted from map_screen) --- END ---

  // --- ADDED: Helper method for launching URLs (restored) ---
  Future<void> _launchUrl(String urlString) async {
    // Skip invalid URLs
    if (urlString.isEmpty || 
        urlString == 'about:blank' || 
        urlString == 'https://about:blank') {
      print('Skipping invalid URL: $urlString');
      return;
    }
    
    // Ensure URL starts with http/https for launchUrl
    String launchableUrl = urlString;
    if (!launchableUrl.startsWith('http://') &&
        !launchableUrl.startsWith('https://')) {
      // Assume https if no scheme provided
      launchableUrl = 'https://$launchableUrl';
      print("Prepended 'https://' to URL: $launchableUrl");
    }

    try {
      final Uri uri = Uri.parse(launchableUrl);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        print('Could not launch $uri');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open link: $urlString')),
          );
        }
      }
    } catch (e) {
      print('Error parsing URL: $urlString - $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid URL: $urlString')),
        );
      }
    }
  }
  // --- END ADDED ---

  // --- ADDED: Function to get search suggestions (restored) ---
  Future<List<Experience>> _getExperienceSuggestions(String pattern) async {
    if (pattern.isEmpty) {
      return [];
    }
    // Simple case-insensitive search on the name (using the full list)
    List<Experience> suggestions = _experiences
        .where((exp) => exp.name.toLowerCase().contains(pattern.toLowerCase()))
        .toList();

    // Sort suggestions: those matching _selectedCategoryIds first, then by name
    if (_selectedCategory != null) {
      suggestions.sort((a, b) {
        bool aMatchesSelected = a.categoryId == _selectedCategory!.id;
        bool bMatchesSelected = b.categoryId == _selectedCategory!.id;
        if (aMatchesSelected && !bMatchesSelected) return -1;
        if (!aMatchesSelected && bMatchesSelected) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    } else {
        suggestions.sort((a,b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return suggestions;
  }
  // --- END ADDED ---

  // ADDED: Widget builder for a Content Grid Item (for web)
  Widget _buildContentGridItem(GroupedContentItem group, int index) {
    final mediaItem = group.mediaItem;
    final mediaPath = mediaItem.path;
    final isInstagramUrl = mediaPath.toLowerCase().contains('instagram.com');
    final isTikTokUrl = mediaPath.toLowerCase().contains('tiktok.com') ||
        mediaPath.toLowerCase().contains('vm.tiktok.com');
    final isFacebookUrl = mediaPath.toLowerCase().contains('facebook.com') ||
        mediaPath.toLowerCase().contains('fb.com') ||
        mediaPath.toLowerCase().contains('fb.watch');
    final isYouTubeUrl = mediaPath.toLowerCase().contains('youtube.com') ||
        mediaPath.toLowerCase().contains('youtu.be') ||
        mediaPath.toLowerCase().contains('youtube.com/shorts');
    final bool isNetworkUrl =
        mediaPath.startsWith('http') || mediaPath.startsWith('https');

    Widget mediaDisplayWidget;
    if (isTikTokUrl) {
      mediaDisplayWidget = TikTokPreviewWidget(
        url: mediaPath,
        launchUrlCallback: _launchUrl,
      );
    } else if (isInstagramUrl) {
      mediaDisplayWidget = instagram_widget.InstagramWebView(
        url: mediaPath,
        height: 640.0, // Height for InstagramWebView
        launchUrlCallback: _launchUrl,
        onWebViewCreated: (_) {},
        onPageFinished: (_) {},
      );
      if (kIsWeb) { 
        mediaDisplayWidget = Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: mediaDisplayWidget,
          ),
        );
      }
    } else if (isFacebookUrl) {
      mediaDisplayWidget = FacebookPreviewWidget(
        url: mediaPath,
        height: 500.0, // Height for FacebookPreviewWidget
        launchUrlCallback: _launchUrl,
        onWebViewCreated: (_) {},
        onPageFinished: (_) {},
      );
    } else if (isYouTubeUrl) {
      mediaDisplayWidget = YouTubePreviewWidget(
        url: mediaPath,
        launchUrlCallback: _launchUrl,
      );
    } else if (isNetworkUrl) {
      // Check if it's an image URL
      if (mediaPath.toLowerCase().endsWith('.jpg') ||
          mediaPath.toLowerCase().endsWith('.jpeg') ||
          mediaPath.toLowerCase().endsWith('.png') ||
          mediaPath.toLowerCase().endsWith('.gif') ||
          mediaPath.toLowerCase().endsWith('.webp')) {
        mediaDisplayWidget = Image.network(
          mediaPath,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const Center(child: CircularProgressIndicator());
          },
          errorBuilder: (context, error, stackTrace) {
            print("Error loading image $mediaPath: $error");
            return Container(
              color: Colors.grey[200],
              height: 200, 
              child: Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: Colors.grey[600], size: 40)),
            );
          },
        );
      } else {
        // Use generic URL preview for other network URLs
        mediaDisplayWidget = GenericUrlPreviewWidget(
          url: mediaPath,
          launchUrlCallback: _launchUrl,
        );
      }
    } else {
      mediaDisplayWidget = Container(
        color: Colors.grey[300],
        height: 150, 
        child: Center(
            child: Icon(Icons.description, color: Colors.grey[700], size: 40)),
      );
    }

    return Card( // Card is the root, making the whole area clickable via InkWell
      key: ValueKey('content_grid_${mediaItem.id}_$index'),
      clipBehavior: Clip.antiAlias,
      elevation: 2.0,
      margin: EdgeInsets.zero, // Remove card's own margin to better fit GridView cell
      child: InkWell(
        onTap: () {
          _showMediaDetailsDialog(group);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, // Ensure children fill width
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 4.0), // Text padding
              child: Text(
                'Linked Experiences (${group.associatedExperiences.length})',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: mediaDisplayWidget, // Media preview takes remaining space
            ),
          ],
        ),
      ),
    );
  }

  // ADDED: Dialog to show media details (associated experiences)
  void _showMediaDetailsDialog(GroupedContentItem group) {
    showDialog(
      context: context, // This 'context' is from _CollectionsScreenState
      builder: (BuildContext dialogContext) { // Use a different name for dialog's own context
        return AlertDialog(
          title: Text(group.mediaItem.path.contains("instagram.com")
              ? "Instagram Post Details"
              : group.mediaItem.path.contains('facebook.com') || group.mediaItem.path.contains('fb.com') || group.mediaItem.path.contains('fb.watch')
                  ? 'Facebook Post Details'
                  : group.mediaItem.path.contains('tiktok.com') || group.mediaItem.path.contains('vm.tiktok.com')
                      ? 'TikTok Post Details'
                      : group.mediaItem.path.contains('youtube.com') || group.mediaItem.path.contains('youtu.be')
                          ? 'YouTube Video Details'
                          : "Shared Media Details"),
          content: SizedBox( // Wrap the Column with SizedBox to constrain its width
            width: MediaQuery.of(dialogContext).size.width * 0.2, // Example: 80% of screen width
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  "Linked Experiences (${group.associatedExperiences.length}):",
                  style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (group.associatedExperiences.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text("No experiences linked to this media."),
                  ),
                if (group.associatedExperiences.isNotEmpty)
                  ListView.builder(
                    shrinkWrap: true, 
                    itemCount: group.associatedExperiences.length,
                    itemBuilder: (context, index) { 
                      final exp = group.associatedExperiences[index];
                      final category = _categories.firstWhereOrNull((cat) => cat.id == exp.categoryId);
                      final categoryIcon = category?.icon ?? '❓';
                      final colorCategory = _colorCategories.firstWhereOrNull((cc) => cc.id == exp.colorCategoryId);
                      final color = colorCategory != null ? _parseColor(colorCategory.colorHex) : Theme.of(dialogContext).disabledColor;

                      return ListTile(
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(categoryIcon, style: const TextStyle(fontSize: 20)),
                            if (colorCategory != null) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.circle, color: color, size: 12),
                            ]
                          ],
                        ),
                        title: Text(exp.name, style: Theme.of(dialogContext).textTheme.bodyLarge),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(dialogContext).pop(); // Close dialog first
                          final resolvedCategory = category ?? UserCategory(
                            id: exp.categoryId ?? 'uncategorized',
                            name: category?.name ?? 'Uncategorized',
                            icon: categoryIcon,
                            ownerUserId: category?.ownerUserId ?? _authService.currentUser?.uid ?? 'system_default',
                            orderIndex: category?.orderIndex ?? 9999,
                          );
                          Navigator.push<bool>(
                            this.context, // Use _CollectionsScreenState's context for navigation
                            MaterialPageRoute(
                              builder: (ctx) => ExperiencePageScreen( // Use 'ctx' for clarity
                                experience: exp,
                                category: resolvedCategory,
                                userColorCategories: _colorCategories,
                              ),
                            ),
                          ).then((result) {
                            if (result == true && mounted) {
                              _loadData();
                            }
                          });
                        },
                      );
                    },
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }
}
