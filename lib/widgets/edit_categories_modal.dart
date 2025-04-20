import 'package:flutter/material.dart';
import 'package:plendy/models/user_category.dart';
import 'package:plendy/services/experience_service.dart';
import 'package:plendy/widgets/add_category_modal.dart';

// UPDATED: Enum for sort order
enum CategorySortOrder { manual, mostRecent, alphabetical }

class EditCategoriesModal extends StatefulWidget {
  const EditCategoriesModal({super.key});

  @override
  State<EditCategoriesModal> createState() => _EditCategoriesModalState();
}

class _EditCategoriesModalState extends State<EditCategoriesModal> {
  final ExperienceService _experienceService = ExperienceService();
  List<UserCategory> _categories =
      []; // Now holds the current display/manual order
  List<UserCategory> _fetchedCategories = []; // Holds original fetched order
  bool _isLoading = false;
  bool _categoriesChanged = false; // Track if any changes were made

  // UPDATED: State for sorting (default to manual)
  CategorySortOrder _sortOrder = CategorySortOrder.manual;

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
      final categories = await _experienceService.getUserCategories();
      print(
          "_loadCategories - Received ${categories.length} categories from service:"); // Log Received
      categories.forEach((c) => print("  - ${c.name} (ID: ${c.id})"));

      if (mounted) {
        setState(() {
          _fetchedCategories =
              List.from(categories); // Store the original fetched order
          _isLoading = false;
          print(
              "_loadCategories END - Set state with fetched categories."); // Log State Set
          _applySort(); // Apply initial sort order (manual will copy from fetched)
        });
      }
    } catch (error) {
      print("_loadCategories ERROR: $error"); // Log Error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading categories: $error')),
        );
        setState(() {
          _isLoading = false;
          _categories = [];
          _fetchedCategories = [];
          print(
              "_loadCategories END - Set state with empty categories after error."); // Log Error State Set
        });
      }
    }
  }

  // UPDATED: Function to apply the current sort order
  void _applySort() {
    print("Applying sort order: $_sortOrder");
    setState(() {
      if (_sortOrder == CategorySortOrder.alphabetical) {
        // Start with a copy of the original fetched order for sorting
        List<UserCategory> sortedList = List.from(_fetchedCategories);
        sortedList.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _categories = sortedList; // Update the display list
      } else if (_sortOrder == CategorySortOrder.mostRecent) {
        // Start with a copy of the original fetched order for sorting
        List<UserCategory> sortedList = List.from(_fetchedCategories);
        sortedList.sort((a, b) {
          final tsA = a.lastUsedTimestamp;
          final tsB = b.lastUsedTimestamp;
          if (tsA == null && tsB == null) return 0;
          if (tsA == null) return 1;
          if (tsB == null) return -1;
          return tsB.compareTo(tsA);
        });
        _categories = sortedList; // Update the display list
      } else {
        // Manual / Default: Use the fetched list directly (already sorted by index)
        _categories = List.from(_fetchedCategories);
      }
      print("Display categories count after sort: ${_categories.length}");
    });
  }

  Future<void> _deleteCategory(UserCategory category) async {
    // Confirmation Dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
        _categoriesChanged = true; // Mark that changes were made
        // Refresh the list immediately after delete
        _loadCategories();
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
      _categoriesChanged = true; // Mark that changes happened
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
      builder: (context) => const AddCategoryModal(),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );

    if (newCategory != null && mounted) {
      // If a new category was added, mark changes and refresh the list
      _categoriesChanged = true;
      _loadCategories(); // Refresh the list (will re-apply sort)
    }
  }

  @override
  Widget build(BuildContext context) {
    print(
        "EditCategoriesModal BUILD START - Current category count: ${_categories.length}"); // Log Build Start (use _categories)
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    // Calculate a max height (e.g., 70% of screen height)
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.9;

    // Wrap Padding in a Container with constraints
    return Container(
      constraints: BoxConstraints(
        maxHeight: maxHeight,
      ),
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
                PopupMenuButton<CategorySortOrder>(
                  // Change icon based on sort order?
                  icon: _sortOrder == CategorySortOrder.manual
                      ? const Icon(Icons
                          .drag_handle) // Indicate manual order allows dragging
                      : const Icon(Icons.sort),
                  tooltip: "Sort Categories",
                  onSelected: (CategorySortOrder result) {
                    if (_sortOrder != result) {
                      setState(() {
                        _sortOrder = result;
                      });
                      _applySort(); // Apply the selected sort
                    }
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<CategorySortOrder>>[
                    // UPDATED: Menu items
                    const PopupMenuItem<CategorySortOrder>(
                      value: CategorySortOrder.manual,
                      child: Text('Manual / Default'),
                    ),
                    const PopupMenuItem<CategorySortOrder>(
                      value: CategorySortOrder.mostRecent,
                      child: Text('Sort by Most Recent'),
                    ),
                    const PopupMenuItem<CategorySortOrder>(
                      value: CategorySortOrder.alphabetical,
                      child: Text('Sort Alphabetically'),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      _handleClose(), // UPDATED: Use helper to handle close
                  tooltip: 'Close',
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            // Scrollable List Area (Uses Expanded)
            Expanded(
              child: _isLoading && _categories.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _categories.isEmpty
                      ? const Center(child: Text('No categories found.'))
                      // UPDATED: Use ReorderableListView.builder
                      : ReorderableListView.builder(
                          // buildDefaultDragHandles: false, // We use a custom handle
                          itemCount: _categories.length,
                          itemBuilder: (context, index) {
                            final category = _categories[index];
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
                                  // ADDED: Drag Handle
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
                                  _categories.removeAt(oldIndex);
                              _categories.insert(newIndex, item);

                              // IMPORTANT: Set sort order to manual after any reorder
                              _sortOrder = CategorySortOrder.manual;
                              _categoriesChanged =
                                  true; // Mark that changes were made

                              // ADDED: Update orderIndex property in the local list
                              for (int i = 0; i < _categories.length; i++) {
                                // Use copyWith to update the object immutably
                                _categories[i] =
                                    _categories[i].copyWith(orderIndex: i);
                              }

                              print(
                                  "Categories reordered. Set sortOrder to manual.");
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
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ADDED: Helper function to handle closing and potentially saving order
  Future<void> _handleClose() async {
    bool shouldSaveChanges =
        _categoriesChanged && _sortOrder == CategorySortOrder.manual;
    print(
        "Closing EditCategoriesModal. Should save changes: $shouldSaveChanges");

    if (shouldSaveChanges) {
      setState(() {
        _isLoading = true;
      }); // Show loading indicator
      try {
        // Prepare data for batch update
        final List<Map<String, dynamic>> updates = [];
        for (int i = 0; i < _categories.length; i++) {
          // Ensure category has an ID and index before adding to update
          if (_categories[i].id.isNotEmpty &&
              _categories[i].orderIndex != null) {
            updates.add({
              'id': _categories[i].id,
              'orderIndex':
                  _categories[i].orderIndex!, // Use ! as we updated it
            });
          } else {
            print(
                "Warning: Skipping category with missing id or index: ${_categories[i].name}");
          }
        }

        print("Attempting to save order for ${updates.length} categories.");
        await _experienceService.updateCategoryOrder(updates);
        print("Category order saved successfully.");
        if (mounted) {
          Navigator.of(context)
              .pop(true); // Indicate changes were made and saved
        }
      } catch (e) {
        print("Error saving category order: $e");
        if (mounted) {
          // Show error message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error saving category order: $e")),
          );
          // Optionally, don't pop or pop indicating failure?
          // For now, we still pop but indicate no changes were successfully saved (original _categoriesChanged state)
          Navigator.of(context)
              .pop(_categoriesChanged && false); // Force false if save failed
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          }); // Hide loading indicator
        }
      }
    } else {
      // No changes to save, just pop
      Navigator.of(context).pop(_categoriesChanged);
    }
  }
}
