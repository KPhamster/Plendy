import 'package:flutter/material.dart';
import 'package:plendy/models/color_category.dart';
import 'package:plendy/services/experience_service.dart';
import 'package:plendy/widgets/add_color_category_modal.dart';

// Enum for sort order
enum ColorCategorySortType { mostRecent, alphabetical }

class EditColorCategoriesModal extends StatefulWidget {
  const EditColorCategoriesModal({super.key});

  @override
  State<EditColorCategoriesModal> createState() =>
      _EditColorCategoriesModalState();
}

class _EditColorCategoriesModalState extends State<EditColorCategoriesModal> {
  final ExperienceService _experienceService = ExperienceService();
  List<ColorCategory> _categories =
      []; // Holds the current display/manual order
  List<ColorCategory> _fetchedCategories = []; // Holds original fetched order
  bool _isLoading = false;
  bool _categoriesChanged =
      false; // Track if any change to order/content occurred

  @override
  void initState() {
    super.initState();
    _loadColorCategories();
  }

  Future<void> _loadColorCategories() async {
    if (!mounted) return;
    print("_loadColorCategories START - Setting isLoading=true");
    setState(() {
      _isLoading = true;
    });
    try {
      print(
          "_loadColorCategories - Calling _experienceService.getUserColorCategories...");
      final categories = await _experienceService.getUserColorCategories();
      print(
          "_loadColorCategories - Received ${categories.length} categories from service:");
      for (var c in categories) {
        print("  - ${c.name} (ID: ${c.id})");
      }

      if (mounted) {
        setState(() {
          _fetchedCategories = List.from(categories);
          _categories = List.from(_fetchedCategories);
          _isLoading = false;
          print(
              "_loadColorCategories END - Set state with fetched categories.");
        });
      }
    } catch (error) {
      print("_loadColorCategories ERROR: $error");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading color categories: $error')),
        );
        setState(() {
          _isLoading = false;
          _categories = [];
          _fetchedCategories = [];
          print(
              "_loadColorCategories END - Set state with empty categories after error.");
        });
      }
    }
  }

  void _applySort(ColorCategorySortType sortType) {
    print("Applying color category sort permanently: $sortType");
    setState(() {
      if (sortType == ColorCategorySortType.alphabetical) {
        _categories.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      } else if (sortType == ColorCategorySortType.mostRecent) {
        _categories.sort((a, b) {
          final tsA = a.lastUsedTimestamp;
          final tsB = b.lastUsedTimestamp;
          if (tsA == null && tsB == null) return 0;
          if (tsA == null) return 1; // Nulls last
          if (tsB == null) return -1; // Nulls last
          return tsB.compareTo(tsA); // Newest first
        });
      }

      _updateLocalOrderIndices();
      _categoriesChanged = true;
      print("Color category sorted via menu, _categoriesChanged set to true.");
      print("Display color categories count after sort: ${_categories.length}");
    });
  }

  void _updateLocalOrderIndices() {
    for (int i = 0; i < _categories.length; i++) {
      _categories[i] = _categories[i].copyWith(orderIndex: i);
    }
    print("Updated local color category order indices.");
  }

  Future<void> _deleteCategory(ColorCategory category) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Delete Color Category?'),
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
        _isLoading = true;
      });
      try {
        await _experienceService.deleteColorCategory(category.id);
        _categoriesChanged = true;
        print("Color category deleted, _categoriesChanged set to true.");
        _loadColorCategories(); // Refresh list
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${category.name}" category deleted.')),
          );
        }
      } catch (e) {
        print("Error deleting color category: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting color tag: $e')),
          );
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _editCategory(ColorCategory category) async {
    final updatedCategory = await showModalBottomSheet<ColorCategory>(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) => AddColorCategoryModal(categoryToEdit: category),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );

    if (updatedCategory != null && mounted) {
      _categoriesChanged = true;
      print("Color category edited, _categoriesChanged set to true.");
      _loadColorCategories(); // Refresh list
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${updatedCategory.name}" category updated.')),
      );
    }
  }

  Future<void> _addNewCategory() async {
    final newCategory = await showModalBottomSheet<ColorCategory>(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) => const AddColorCategoryModal(),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );

    if (newCategory != null && mounted) {
      _categoriesChanged = true;
      print("Color category added, _categoriesChanged set to true.");
      _loadColorCategories(); // Refresh list
    }
  }

  @override
  Widget build(BuildContext context) {
    print(
        "EditColorCategoriesModal BUILD START - Current category count: ${_categories.length}");
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.9;

    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) async {
        if (didPop) {
          return;
        }
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
            bottom: bottomPadding + 16.0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.only(left: 8.0, top: 8.0, bottom: 8.0),
                    child: Text('Edit Color Categories',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  PopupMenuButton<ColorCategorySortType>(
                    icon: const Icon(Icons.sort),
                    tooltip: "Sort Color Categories",
                    onSelected: (ColorCategorySortType result) {
                      _applySort(result);
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<ColorCategorySortType>>[
                      const PopupMenuItem<ColorCategorySortType>(
                        value: ColorCategorySortType.mostRecent,
                        child: Text('Sort by Most Recent'),
                      ),
                      const PopupMenuItem<ColorCategorySortType>(
                        value: ColorCategorySortType.alphabetical,
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
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _categories.isEmpty
                        ? const Center(child: Text('No color categories found.'))
                        : ReorderableListView.builder(
                            itemCount: _categories.length,
                            itemBuilder: (context, index) {
                              final category = _categories[index];
                              return ListTile(
                                key: ValueKey(category.id),
                                leading: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                      color: category.color,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.grey.shade400, width: 1)),
                                ),
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
                                    const SizedBox(width: 20),
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
                                if (newIndex > oldIndex) {
                                  newIndex -= 1;
                                }
                                final ColorCategory item =
                                    _categories.removeAt(oldIndex);
                                _categories.insert(newIndex, item);
                                _updateLocalOrderIndices();
                                _categoriesChanged = true;
                                print(
                                    "Color category reordered, _categoriesChanged set to true.");
                              });
                            },
                          ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add New Color Category'),
                  onPressed: _isLoading ? null : _addNewCategory,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
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
                    side: BorderSide(color: Colors.grey),
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
    bool hadChanges = _categoriesChanged; // Store initial state

    print(
        "Executing _handleCloseLogic (Color Categories). Had changes: $hadChanges");

    if (hadChanges) {
      setState(() {
        _isLoading = true;
      });
      try {
        final List<Map<String, dynamic>> updates = [];
        for (int i = 0; i < _categories.length; i++) {
          if (_categories[i].id.isNotEmpty &&
              _categories[i].orderIndex != null) {
            updates.add({
              'id': _categories[i].id,
              'orderIndex': _categories[i].orderIndex!,
            });
          } else {
            print(
                "Warning: Skipping color category with missing id or index: ${_categories[i].name}");
          }
        }

        if (updates.isNotEmpty) { 
          print(
              "Attempting to save order for ${updates.length} color categories.");
          await _experienceService.updateColorCategoryOrder(updates);
          print("Color category order saved successfully.");
          changesSuccessfullySaved = true;
        } else if (updates.isEmpty && _categoriesChanged) {
          changesSuccessfullySaved = true; 
        }

      } catch (e) {
        print("Error saving color category order: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error saving color category order: $e")),
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
