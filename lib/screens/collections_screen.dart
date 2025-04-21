import 'package:flutter/material.dart';
import '../models/experience.dart';
import '../models/user_category.dart';
import '../services/auth_service.dart';
import '../services/experience_service.dart';
import '../widgets/add_category_modal.dart';
import '../widgets/edit_categories_modal.dart' show CategorySortType;

// ADDED: Enum for experience view modes
enum _ExperienceViewMode { list, detailed }

class CollectionsScreen extends StatefulWidget {
  CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  final _experienceService = ExperienceService();

  late TabController _tabController;
  int _currentTabIndex = 0;

  // ADDED: State variable for experience view mode
  _ExperienceViewMode _experiencesViewMode = _ExperienceViewMode.list;

  bool _isLoading = true;
  List<UserCategory> _categories = [];
  List<Experience> _experiences = [];
  String? _userEmail;

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

      if (mounted) {
        setState(() {
          _categories = categories;
          _experiences = experiences;
          _isLoading = false;
        });
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

  // ADDED: Main widget builder for the Experiences tab content
  Widget _buildExperiencesTabContent() {
    // Loading and empty states handled within the specific view builders
    switch (_experiencesViewMode) {
      case _ExperienceViewMode.list:
        return _buildExperiencesListView();
      case _ExperienceViewMode.detailed:
        // Placeholder for the detailed view
        return const Center(
          child: Text('Detailed View (coming soon)'),
        );
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
            print('Tapped on ${category.name}');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Collection'),
        actions: [
          if (_currentTabIndex == 0)
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
            IconButton(
              icon: Icon(
                _experiencesViewMode == _ExperienceViewMode.list
                    ? Icons
                        .view_module_outlined // Icon for switching to detailed
                    : Icons.view_list_outlined, // Icon for switching to list
              ),
              tooltip: 'Toggle Experience View',
              onPressed: () {
                setState(() {
                  _experiencesViewMode =
                      _experiencesViewMode == _ExperienceViewMode.list
                          ? _ExperienceViewMode.detailed
                          : _ExperienceViewMode.list;
                });
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Categories'),
            Tab(text: 'Experiences'),
            Tab(text: 'Content'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCategoriesList(),
                _buildExperiencesTabContent(),
                Center(child: Text('Content Tab Content for $_userEmail')),
              ],
            ),
      floatingActionButton: _currentTabIndex == 0
          ? FloatingActionButton(
              onPressed: _showAddCategoryModal,
              tooltip: 'Add Category',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  // ADDED: Widget builder for the Experience List View
  Widget _buildExperiencesListView() {
    if (_experiences.isEmpty) {
      return const Center(child: Text('No experiences found. Add some!'));
    }

    return ListView.builder(
      itemCount: _experiences.length,
      itemBuilder: (context, index) {
        final experience = _experiences[index];
        // Find the matching category icon
        final categoryIcon = _categories
            .firstWhere((cat) => cat.name == experience.category,
                orElse: () => UserCategory(
                    id: '',
                    name: '',
                    icon: '❓') // Default icon if category not found
                )
            .icon;

        // Get the full address
        final fullAddress = experience.location.address;
        // Get the first image URL or null
        final imageUrl = experience.location.photoUrl;

        return ListTile(
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
                      child: Icon(Icons.image_not_supported,
                          color: Colors.grey[600]),
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
                          fontStyle:
                              FontStyle.italic, // Optional: Italicize notes
                        ),
                    maxLines: 2, // Limit notes length in list view
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          // TODO: Add onTap to navigate to experience details
          onTap: () {
            print('Tapped on Experience: ${experience.name}');
            // Navigation logic will go here later
          },
        );
      },
    );
  }
}
