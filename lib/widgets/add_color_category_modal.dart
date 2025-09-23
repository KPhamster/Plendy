import 'package:flutter/material.dart';
import 'package:plendy/models/color_category.dart';
import 'package:plendy/services/experience_service.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

class AddColorCategoryModal extends StatefulWidget {
  final ColorCategory? categoryToEdit;

  const AddColorCategoryModal({super.key, this.categoryToEdit});

  @override
  State<AddColorCategoryModal> createState() => _AddColorCategoryModalState();
}

class _AddColorCategoryModalState extends State<AddColorCategoryModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final ExperienceService _experienceService = ExperienceService();
  bool _isLoading = false;

  // State for color picker
  Color _selectedColor = Colors.blue; // Default color

  bool get _isEditing => widget.categoryToEdit != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _nameController.text = widget.categoryToEdit!.name;
      // Initialize color from hex string
      try {
        _selectedColor = widget.categoryToEdit!.color;
      } catch (e) {
        print("Error parsing initial color: $e, defaulting to blue.");
        _selectedColor = Colors.blue;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // Function to open color picker dialog
  void _pickColor(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Pick a color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: _selectedColor,
            onColorChanged: (color) {
              setState(() => _selectedColor = color);
            },
            pickerAreaHeightPercent: 0.8,
            enableAlpha: false, // Disable alpha channel
            // Display AppBar directives for harmony and undo/redo
            displayThumbColor: true,
            paletteType: PaletteType.hsl,
            pickerAreaBorderRadius: const BorderRadius.only(
              topLeft: Radius.circular(2.0),
              topRight: Radius.circular(2.0),
            ),
            hexInputBar: true,
          ),
        ),
        actions: <Widget>[
          ElevatedButton(
            child: const Text('Select'),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _saveCategory() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      final name = _nameController.text.trim();
      // Convert color to hex string (e.g., FF00FF00 for opaque green)
      final colorHex = _selectedColor.value.toRadixString(16).toUpperCase();

      try {
        ColorCategory resultCategory;
        if (_isEditing) {
          final updatedCategory = widget.categoryToEdit!.copyWith(
            name: name,
            colorHex: colorHex,
          );
          print(
              "🎨 ADD_COLOR_MODAL: Attempting to update category ID: ${updatedCategory.id}");
          print(
              "🎨 ADD_COLOR_MODAL: Updating with Name: ${updatedCategory.name}, ColorHex: ${updatedCategory.colorHex}");
          await _experienceService.updateColorCategory(updatedCategory);
          resultCategory = updatedCategory;
          print("Color category updated: ${resultCategory.name}");
        } else {
          print(
              "🎨 ADD_COLOR_MODAL: Attempting to add new category with Name: $name, ColorHex: $colorHex");
          resultCategory =
              await _experienceService.addColorCategory(name, colorHex);
          print("Color category added: ${resultCategory.name}");
        }

        print(
            "🎨 ADD_COLOR_MODAL: Popping with resultCategory: ${resultCategory.id} - ${resultCategory.name}");

        if (mounted) {
          Navigator.of(context)
              .pop(resultCategory); // Return the saved/updated category
        }
      } catch (e) {
        print("Error saving color category: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Error ${_isEditing ? "updating" : "adding"} color category: ${e.toString()}')),
          );
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Material(
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16.0,
          right: 16.0,
          top: 20.0,
          bottom: bottomPadding + 20.0,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                    _isEditing
                        ? 'Edit Color Category'
                        : 'Create a New Color Category',
                    style: Theme.of(context).textTheme.titleLarge),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Cancel',
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: _isEditing
                    ? 'Edit category name'
                    : 'Name your new color category',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a category name';
                }
                // Optional: Add validation to check if name already exists (might need service call)
                return null;
              },
            ),
            const SizedBox(height: 16),
            Text('Select Color',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _pickColor(context),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: _selectedColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade400, width: 1),
                ),
                child: Center(
                  child: Text(
                    'Tap to change color',
                    style: TextStyle(
                      color: ThemeData.estimateBrightnessForColor(
                                  _selectedColor) ==
                              Brightness.dark
                          ? Colors.white
                          : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _isLoading
                    ? Container(
                        width: 20,
                        height: 20,
                        padding: const EdgeInsets.all(2.0),
                        child: const CircularProgressIndicator(
                            strokeWidth: 3, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: Text(_isLoading
                    ? 'Saving...'
                    : _isEditing
                        ? 'Update Category'
                        : 'Save Category'),
                onPressed: _isLoading ? null : _saveCategory,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
