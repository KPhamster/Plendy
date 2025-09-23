import 'package:flutter/material.dart';
import 'package:plendy/models/user_category.dart';
import 'package:plendy/services/experience_service.dart';
import 'package:plendy/widgets/add_category_modal.dart';

// UPDATED: Enum for sort order (used as parameter, not state)
enum CategorySortType { mostRecent, alphabetical }

class EditCategoriesModal extends StatefulWidget {
  const EditCategoriesModal({super.key});

  @override
  State<EditCategoriesModal> createState() => _EditCategoriesModalState();
}

class _EditCategoriesModalState extends State<EditCategoriesModal> {
  final ExperienceService _experienceService = ExperienceService();
  List<UserCategory> _Categories =
      []; // Now holds the current display/manual order
  List<UserCategory> _fetchedCategories = []; // Holds original fetched order
  bool _isLoading = false;
  bool _CategoriesChanged =
      false; // Track if *any* change to order/content occurred

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    if (!mounted) return;
    print("_loadCategories START - Setting isLoading=true"); // Log Start
    setState(() {
      _isLoading = true;
    });
    try {
      print(
          "_loadCategories - Calling _experienceService.getUserCategories..."); // Log Before Call
      final Categories = await _experienceService.getUserCategories();
      print(
          "_loadCategories - Received ${Categories.length} Categories from service:"); // Log Received
      for (var c in Categories) {
        print("  - ${c.name} (ID: ${c.id})");
      }

      if (mounted) {
        setState(() {
          _fetchedCategories =
              List.from(Categories); // Store the original fetched order
          // Initialize _Categories with the fetched order (already sorted by index)
          _Categories = List.from(_fetchedCategories);
          _isLoading = false;
          print(
              "_loadCategories END - Set state with fetched Categories."); // Log State Set
          // No initial sort application needed, _Categories starts with saved order
        });
      }
    } catch (error) {
      print("_loadCategories ERROR: $error"); // Log Error
      print("ERROR TYPE: ${error.runtimeType}");
      if (error is Error) {
        print("ERROR StackTrace: ${error.stackTrace}");
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading Categories: $error')),
        );
        setState(() {
          _isLoading = false;
          _Categories = [];
          _fetchedCategories = [];
          print(
              "_loadCategories END - Set state with empty Categories after error."); // Log Error State Set
        });
      }
    }
  }

  // UPDATED: Function now takes sort type and applies it permanently
  void _applySort(CategorySortType sortType) {
    print("Applying sort permanently: $sortType");
    setState(() {
      if (sortType == CategorySortType.alphabetical) {
        _Categories.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      } else if (sortType == CategorySortType.mostRecent) {
        _Categories.sort((a, b) {
          final tsA = a.lastUsedTimestamp;
          final tsB = b.lastUsedTimestamp;
          if (tsA == null && tsB == null) return 0;
          if (tsA == null) return 1;
          if (tsB == null) return -1;
          return tsB.compareTo(tsA);
        });
      }

      // IMPORTANT: Update orderIndex locally after sorting
      _updateLocalOrderIndices();
      _CategoriesChanged = true; // Mark that changes were made
      print(
          "Category sorted via menu, _CategoriesChanged set to true."); // Log flag set

      print("Display Categories count after sort: ${_Categories.length}");
    });
  }

  // ADDED: Helper to update local orderIndex properties
  void _updateLocalOrderIndices() {
    for (int i = 0; i < _Categories.length; i++) {
      _Categories[i] = _Categories[i].copyWith(orderIndex: i);
    }
    print("Updated local order indices.");
  }

  Future<void> _deleteCategory(UserCategory category) async {
    // Confirmation Dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Delete Category?'),
        content: Text(
            'Are you sure you want to delete the "${category.name}" category? This cannot be undone.'),
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
      setState(() {
        _isLoading = true; // Indicate loading during delete
      });
      try {
        await _experienceService.deleteUserCategory(category.id);
        // Ensure flag is set *before* loading, as load might reset list
        _CategoriesChanged = true;
        print(
            "Category deleted, _CategoriesChanged set to true."); // Log flag set
        _loadCategories(); // Refresh the list immediately after delete
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${category.name}" category deleted.')),
          );
        }
      } catch (e) {
        print("Error deleting category: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting category: $e')),
          );
          setState(() {
            _isLoading = false; // Reset loading state on error
          });
        }
      }
    }
  }

  Future<void> _editCategory(UserCategory category) async {
    // Show the AddCategoryModal, passing the category to edit
    final updatedCategory = await showModalBottomSheet<UserCategory>(
      context: context,
      backgroundColor: Colors.white,
      // Pass the category to the modal
      builder: (context) => AddCategoryModal(categoryToEdit: category),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );

    // Check if the modal returned an updated category
    if (updatedCategory != null && mounted) {
      // No need to call updateUserCategory here, as AddCategoryModal handles it
      // Ensure flag is set *before* loading
      _CategoriesChanged = true;
      print("Category edited, _CategoriesChanged set to true."); // Log flag set
      _loadCategories(); // Refresh the list in this modal (will re-apply sort)

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${updatedCategory.name}" category updated.')),
      );
    }
  }

  Future<void> _addNewCategory() async {
    // Show the existing AddCategoryModal
    final newCategory = await showModalBottomSheet<UserCategory>(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) => const AddCategoryModal(),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );

    if (newCategory != null && mounted) {
      // If a new category was added, mark changes and refresh the list
      // Ensure flag is set *before* loading
      _CategoriesChanged = true;
      print("Category added, _CategoriesChanged set to true."); // Log flag set
      _loadCategories(); // Refresh the list (will re-apply sort)
    }
  }

  @override
  Widget build(BuildContext context) {
    print(
        "EditCategoriesModal BUILD START - Current category count: ${_Categories.length}"); // Log Build Start (use _Categories)
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    // Calculate a max height (e.g., 70% of screen height)
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.9;

    return PopScope(
      canPop: false, 
      onPopInvoked: (bool didPop) async {
        if (didPop) {
          return; 
        }
        // If not popped (e.g., swipe gesture), call _handleCloseLogic
        bool result = await _handleCloseLogic();
        if (mounted) {
          Navigator.of(context).pop(result); 
        }
      },
      child: Container(
        constraints: BoxConstraints(
          maxHeight: maxHeight,
        ),
        color: Colors.white,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16.0,
            right: 16.0,
            top: 8.0,
            bottom: bottomPadding + 16.0, // Padding for keyboard is still needed
          ),
          child: Column(
            // Re-add mainAxisSize: MainAxisSize.min so the column doesn't force max height if content is short
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row (Fixed Top)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.only(left: 8.0, top: 8.0, bottom: 8.0),
                    child: Text('Edit Categories',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  // UPDATED: Sorting Menu Button
                  PopupMenuButton<CategorySortType>(
                    // Use standard sort icon
                    icon: const Icon(Icons.sort),
                    tooltip: "Sort Categories",
                    onSelected: (CategorySortType result) {
                      // Directly apply the selected sort permanently
                      _applySort(result);
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<CategorySortType>>[
                      // UPDATED: Menu items (Removed Manual)
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
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      bool result = await _handleCloseLogic();
                      if (mounted) {
                        Navigator.of(context).pop(result);
                      }
                    },
                    tooltip: 'Close',
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),
              // Scrollable List Area (Uses Expanded)
              Expanded(
                child: _isLoading && _Categories.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _Categories.isEmpty
                        ? const Center(child: Text('No Categories found.'))
                        // UPDATED: Use ReorderableListView.builder
                        : ReorderableListView.builder(
                            // buildDefaultDragHandles: false, // We use a custom handle
                            itemCount: _Categories.length,
                            itemBuilder: (context, index) {
                              final category = _Categories[index];
                              // IMPORTANT: Each item MUST have a unique Key
                              return ListTile(
                                key: ValueKey(category.id),
                                leading: Text(category.icon,
                                    style: const TextStyle(fontSize: 24)),
                                title: Text(category.name),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.edit_outlined,
                                          color: Colors.blue[700], size: 20),
                                      tooltip: 'Edit ${category.name}',
                                      onPressed: _isLoading
                                          ? null
                                          : () => _editCategory(category),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline,
                                          color: Colors.red[700], size: 20),
                                      tooltip: 'Delete ${category.name}',
                                      onPressed: _isLoading
                                          ? null
                                          : () => _deleteCategory(category),
                                    ),
                                    // Add some spacing before the drag handle
                                    const SizedBox(width: 20),
                                    // Moved Drag Handle to the end of the Row
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: const Icon(Icons.drag_handle,
                                          color: Colors.grey, size: 24),
                                    ),
                                  ],
                                ),
                              );
                            },
                            onReorder: (int oldIndex, int newIndex) {
                              setState(() {
                                // Adjust index if item is moved down in the list
                                if (newIndex > oldIndex) {
                                  newIndex -= 1;
                                }
                                // Remove item from old position and insert into new position
                                final UserCategory item =
                                    _Categories.removeAt(oldIndex);
                                _Categories.insert(newIndex, item);

                                // Update orderIndex property in the local list
                                _updateLocalOrderIndices(); // Use helper

                                _CategoriesChanged =
                                    true; // Mark that changes were made
                                print(
                                    "Category reordered, _CategoriesChanged set to true."); // Log flag set

                                // Update orderIndex property in the local list
                                _updateLocalOrderIndices(); // Use helper

                                print("Categories reordered.");
                              });
                            },
                          ),
              ),
              const SizedBox(height: 16),
              // Add New Category Button (Fixed Bottom)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add New Category'),
                  onPressed: _isLoading ? null : _addNewCategory,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              // ADDED Padding below button
              const SizedBox(height: 8), // Reduced space a bit
              // ADDED: Additional Close Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    bool result = await _handleCloseLogic();
                    if (mounted) {
                      Navigator.of(context).pop(result);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(color: Colors.grey), // Match theme or provide subtle border
                  ),
                  child: const Text('Close'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // MODIFIED: To only perform logic and return Future<bool>, does NOT pop.
  Future<bool> _handleCloseLogic() async {
    bool changesSuccessfullySaved = false;
    bool hadChanges = _CategoriesChanged; // Store initial state

    print(
        "Executing _handleCloseLogic. Had changes: $hadChanges");

    if (hadChanges) {
      setState(() {
        _isLoading = true;
      });
      try {
        final List<Map<String, dynamic>> updates = [];
        for (int i = 0; i < _Categories.length; i++) {
          if (_Categories[i].id.isNotEmpty &&
              _Categories[i].orderIndex != null) {
            updates.add({
              'id': _Categories[i].id,
              'orderIndex': _Categories[i].orderIndex!,
            });
          } else {
            print(
                "Warning: Skipping category with missing id or index: ${_Categories[i].name}");
          }
        }

        if (updates.isNotEmpty) {
          print("Attempting to save order for ${updates.length} Categories.");
          await _experienceService.updateCategoryOrder(updates);
          print("Category order saved successfully.");
          changesSuccessfullySaved = true;
        } else if (updates.isEmpty && _CategoriesChanged) {
          changesSuccessfullySaved = true; 
        }

      } catch (e) {
        print("Error saving category order: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error saving category order: $e")),
          );
        }
        changesSuccessfullySaved = false; 
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
    return changesSuccessfullySaved && hadChanges;
  }
}

