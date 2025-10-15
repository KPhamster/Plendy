import 'dart:async';

import 'package:flutter/material.dart';
import 'package:plendy/models/user_category.dart';
import 'package:plendy/models/share_permission.dart';
import 'package:plendy/services/experience_service.dart';
import 'package:plendy/services/auth_service.dart';
import 'package:plendy/widgets/add_category_modal.dart';
import 'package:plendy/models/category_sort_type.dart';
import 'package:plendy/services/category_ordering_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EditCategoriesModal extends StatefulWidget {
  const EditCategoriesModal({super.key});

  @override
  State<EditCategoriesModal> createState() => _EditCategoriesModalState();
}

class _EditCategoriesModalState extends State<EditCategoriesModal> {
  final ExperienceService _experienceService = ExperienceService();
  final CategoryOrderingService _categoryOrderingService =
      CategoryOrderingService();
  final AuthService _authService = AuthService();
  List<UserCategory> _Categories =
      []; // Now holds the current display/manual order
  List<UserCategory> _fetchedCategories = []; // Holds original fetched order
  Map<String, SharePermission> _sharedCategoryPermissions =
      {}; // Track permissions for shared categories
  bool _isLoading = false;
  bool _CategoriesChanged =
      false; // Track if *any* change to order/content occurred
  static const String _prefsKeyCategoryOrderPrefix =
      'collections_category_order_';
  static const String _prefsKeyUseManualCategoryOrderPrefix =
      'collections_use_manual_category_order_';

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
      final userId = _authService.currentUser?.uid;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      print(
          "_loadCategories - Fetching categories (owned + shared editable) via ExperienceService.");
      final UserCategoryFetchResult result =
          await _experienceService.getUserCategoriesWithMeta(
        includeSharedEditable: true,
      );
      final orderedCategories =
          await _categoryOrderingService.orderUserCategories(result.categories,
              sharedPermissions: result.sharedPermissions);
      final sharedCount = result.sharedPermissions.length;
      final ownedCount = orderedCategories.length - sharedCount;

      if (mounted) {
        setState(() {
          _fetchedCategories = List<UserCategory>.from(orderedCategories);
          _Categories = List<UserCategory>.from(orderedCategories);
          _sharedCategoryPermissions =
              Map<String, SharePermission>.from(result.sharedPermissions);
          _isLoading = false;
          print(
              "_loadCategories END - Set state with ${_Categories.length} total Categories (owned: $ownedCount, shared: $sharedCount).");
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
          _sharedCategoryPermissions = {};
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

  void _updateLocalOrderIndices() {
    final String? currentUserId = _authService.currentUser?.uid;
    if (currentUserId == null || currentUserId.isEmpty) {
      return;
    }
    int nextOrder = 0;
    for (int i = 0; i < _Categories.length; i++) {
      final UserCategory category = _Categories[i];
      if (category.ownerUserId != currentUserId) {
        continue;
      }
      _Categories[i] = category.copyWith(orderIndex: nextOrder);
      nextOrder++;
    }
    print("Updated local order indices for owned categories.");
  }

  String? _userSpecificPrefsKey(String prefix) {
    final String? userId = _authService.currentUser?.uid;
    if (userId == null || userId.isEmpty) {
      return null;
    }
    return '$prefix$userId';
  }

  Future<void> _persistManualCategoryOrderPrefs(
      List<String> manualOrder) async {
    final String? key = _userSpecificPrefsKey(_prefsKeyCategoryOrderPrefix);
    if (key == null) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (manualOrder.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setStringList(key, manualOrder);
      }
    } catch (e) {
      print("Error saving manual category order preference: $e");
    }
  }

  Future<void> _persistUseManualCategoryOrder(bool useManual) async {
    final String? key =
        _userSpecificPrefsKey(_prefsKeyUseManualCategoryOrderPrefix);
    if (key == null) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, useManual);
    } catch (e) {
      print("Error saving manual category order toggle: $e");
    }
  }

  Future<bool> _saveCategoryOrder({bool showErrors = false}) async {
    final String? currentUserId = _authService.currentUser?.uid;
    if (currentUserId == null || currentUserId.isEmpty) {
      return false;
    }

    final List<Map<String, dynamic>> updates = [];
    for (final category in _Categories) {
      if (category.ownerUserId != currentUserId) {
        continue;
      }
      if (category.id.isNotEmpty && category.orderIndex != null) {
        updates.add({
          'id': category.id,
          'orderIndex': category.orderIndex!,
        });
      }
    }

    if (updates.isEmpty) {
      print("No owned category order updates to save.");
      return true;
    }

    try {
      await _experienceService.updateCategoryOrder(updates);
      print("Category order saved successfully.");
      return true;
    } catch (e) {
      print("Error saving category order: $e");
      if (showErrors && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving category order: $e")),
        );
      }
      return false;
    }
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
            bottom:
                bottomPadding + 16.0, // Padding for keyboard is still needed
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
                              final bool isShared = _sharedCategoryPermissions
                                  .containsKey(category.id);
                              final bool isOwned = category.ownerUserId ==
                                  _authService.currentUser?.uid;
                              final bool canEdit = isOwned ||
                                  isShared; // If shared with edit permission
                              final bool canDelete =
                                  isOwned; // Only owner can delete

                              // IMPORTANT: Each item MUST have a unique Key
                              return ListTile(
                                key: ValueKey(category.id),
                                leading: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(category.icon,
                                        style: const TextStyle(fontSize: 24)),
                                    if (isShared) const SizedBox(width: 4),
                                    if (isShared)
                                      Icon(Icons.people,
                                          size: 16, color: Colors.blue[600]),
                                  ],
                                ),
                                title: Text(category.name),
                                subtitle: isShared
                                    ? Text('Shared with you',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.blue[600]))
                                    : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.edit_outlined,
                                          color: canEdit
                                              ? Colors.blue[700]
                                              : Colors.grey,
                                          size: 20),
                                      tooltip: canEdit
                                          ? 'Edit ${category.name}'
                                          : 'Cannot edit shared category',
                                      onPressed: _isLoading || !canEdit
                                          ? null
                                          : () => _editCategory(category),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline,
                                          color: canDelete
                                              ? Colors.red[700]
                                              : Colors.grey,
                                          size: 20),
                                      tooltip: canDelete
                                          ? 'Delete ${category.name}'
                                          : 'Cannot delete shared category',
                                      onPressed: _isLoading || !canDelete
                                          ? null
                                          : () => _deleteCategory(category),
                                    ),
                                    // Add some spacing before the drag handle
                                    const SizedBox(width: 20),
                                    // Moved Drag Handle to the end of the Row
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: Icon(Icons.drag_handle,
                                          color: isOwned
                                              ? Colors.grey
                                              : Colors.grey[400],
                                          size: 24),
                                    ),
                                  ],
                                ),
                              );
                            },
                            onReorder: (int oldIndex, int newIndex) {
                              if (newIndex > oldIndex) {
                                newIndex -= 1;
                              }
                              if (oldIndex < 0 ||
                                  oldIndex >= _Categories.length ||
                                  newIndex < 0 ||
                                  newIndex >= _Categories.length) {
                                return;
                              }
                              setState(() {
                                final UserCategory item =
                                    _Categories.removeAt(oldIndex);
                                _Categories.insert(newIndex, item);
                                _updateLocalOrderIndices();
                                _CategoriesChanged = true;
                                print(
                                    "Category reordered, _CategoriesChanged set to true.");
                              });
                              final List<String> manualOrder =
                                  List<String>.from(
                                      _Categories.map((c) => c.id));
                              unawaited(_persistManualCategoryOrderPrefs(
                                  manualOrder));
                              unawaited(_persistUseManualCategoryOrder(
                                  manualOrder.isNotEmpty));
                              unawaited(_saveCategoryOrder());
                              print("Categories reordered.");
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
                    side: BorderSide(
                        color: Colors
                            .grey), // Match theme or provide subtle border
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

    print("Executing _handleCloseLogic. Had changes: $hadChanges");

    if (hadChanges) {
      setState(() {
        _isLoading = true;
      });
      try {
        final List<String> manualOrder =
            List<String>.from(_Categories.map((c) => c.id));
        print(
            "Attempting to persist manual category order (${manualOrder.length} items).");
        await _persistManualCategoryOrderPrefs(manualOrder);
        await _persistUseManualCategoryOrder(manualOrder.isNotEmpty);
        final bool orderSaved =
            await _saveCategoryOrder(showErrors: true);
        changesSuccessfullySaved = orderSaved;
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
