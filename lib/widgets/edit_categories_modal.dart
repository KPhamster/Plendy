import 'package:flutter/material.dart';
import 'package:plendy/models/user_category.dart';
import 'package:plendy/services/experience_service.dart';
import 'package:plendy/widgets/add_category_modal.dart';

class EditCategoriesModal extends StatefulWidget {
  const EditCategoriesModal({super.key});

  @override
  State<EditCategoriesModal> createState() => _EditCategoriesModalState();
}

class _EditCategoriesModalState extends State<EditCategoriesModal> {
  final ExperienceService _experienceService = ExperienceService();
  List<UserCategory> _categories = [];
  bool _isLoading = false;
  bool _categoriesChanged = false; // Track if any changes were made

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
          _categories = categories;
          _isLoading = false;
          print(
              "_loadCategories END - Set state with fetched categories."); // Log State Set
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
          print(
              "_loadCategories END - Set state with empty categories after error."); // Log Error State Set
        });
      }
    }
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
    // TODO: Implement editing logic
    // This might involve showing another modal (like AddCategoryModal but pre-filled)
    // or navigating to a dedicated edit screen.
    print("Placeholder: Edit category '${category.name}'");
    // Example: Show AddCategoryModal pre-filled for editing
    /*
    final updatedCategory = await showModalBottomSheet<UserCategory>(
      context: context,
      builder: (context) => AddCategoryModal(categoryToEdit: category), // Pass category to edit
      isScrollControlled: true,
    );
    if (updatedCategory != null && mounted) {
      _categoriesChanged = true;
      _loadCategories(); // Refresh list after edit
    }
    */
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
      _loadCategories();
    }
  }

  @override
  Widget build(BuildContext context) {
    print(
        "EditCategoriesModal BUILD START - Current category count: ${_categories.length}"); // Log Build Start
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
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      Navigator.of(context).pop(_categoriesChanged),
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
                      : ListView.builder(
                          // ListView will scroll within the Expanded area
                          itemCount: _categories.length,
                          itemBuilder: (context, index) {
                            final category = _categories[index];
                            return ListTile(
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
                                ],
                              ),
                            );
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
}
