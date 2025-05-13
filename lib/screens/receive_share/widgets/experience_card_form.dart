import 'package:flutter/material.dart';
import 'package:plendy/screens/receive_share_screen.dart'; // For ExperienceCardData
import 'package:plendy/models/experience.dart'
    show Location; // ONLY import Location
import 'package:plendy/models/user_category.dart'; // RENAMED Import
import 'package:plendy/screens/location_picker_screen.dart'; // For Location Picker
import 'package:plendy/services/experience_service.dart'; // ADDED for adding category
import 'package:plendy/services/google_maps_service.dart'; // If needed for location updates
import 'package:plendy/widgets/google_maps_widget.dart'; // If needed
import 'package:url_launcher/url_launcher.dart'; // Import url_launcher
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; // Import FontAwesome
// UPDATED: Import the modal
import 'package:plendy/widgets/add_category_modal.dart';
// ADDED: Import for the Edit modal
import 'package:plendy/widgets/edit_categories_modal.dart';
// ADDED: Import for Clipboard
import 'package:flutter/services.dart';
// ADDED: Import for ColorCategory
import 'package:plendy/models/color_category.dart';
// --- ADDED: Placeholders for Color Category Modals ---
import 'package:plendy/widgets/add_color_category_modal.dart'; // Placeholder
import 'package:plendy/widgets/edit_color_categories_modal.dart'; // Placeholder
// --- END ADDED ---

// Define necessary callbacks
typedef OnRemoveCallback = void Function(ExperienceCardData card);
typedef OnLocationSelectCallback = Future<void> Function(
    ExperienceCardData card);
typedef OnSelectSavedExperienceCallback = Future<void> Function(
    ExperienceCardData card);
typedef OnUpdateCallback = void Function({
  // Modified to accept optional flag
  bool refreshCategories, // Flag to indicate category list needs refresh
  String? newCategoryName, // Optional new category name
  String? selectedColorCategoryId, // ADDED
});

class ExperienceCardForm extends StatefulWidget {
  final ExperienceCardData cardData;
  final bool isFirstCard; // To potentially hide remove button
  final bool canRemove; // Explicit flag to control remove button visibility
  final ValueNotifier<List<UserCategory>> userCategoriesNotifier; // ADDED
  final ValueNotifier<List<ColorCategory>> userColorCategoriesNotifier; // ADDED
  final OnRemoveCallback onRemove;
  final OnLocationSelectCallback onLocationSelect;
  final OnSelectSavedExperienceCallback onSelectSavedExperience;
  final OnUpdateCallback onUpdate; // Callback to parent (signature updated)
  final GlobalKey<FormState> formKey; // Pass form key down

  const ExperienceCardForm({
    super.key,
    required this.cardData,
    required this.isFirstCard,
    required this.canRemove,
    required this.userCategoriesNotifier, // ADDED
    required this.userColorCategoriesNotifier, // ADDED
    required this.onRemove,
    required this.onLocationSelect,
    required this.onSelectSavedExperience,
    required this.onUpdate, // Signature updated
    required this.formKey,
  });

  @override
  State<ExperienceCardForm> createState() => _ExperienceCardFormState();
}

class _ExperienceCardFormState extends State<ExperienceCardForm> {
  // Local state for UI elements directly managed here
  // REMOVED: _isExpanded and _locationEnabled are driven by cardData now
  // bool _isExpanded = true;
  // bool _locationEnabled = true;

  // Service needed for location updates if interaction happens within the form
  final GoogleMapsService _mapsService = GoogleMapsService();

  // ADDED: Service instance
  final ExperienceService _experienceService = ExperienceService();

  // --- ADDED: Helper to check for Yelp URL ---
  bool _isYelpUrl(String url) {
    if (url.isEmpty) return false;
    String urlLower = url.toLowerCase();
    // Basic check for yelp.com/biz or yelp.to
    return urlLower.contains('yelp.com/biz') || urlLower.contains('yelp.to/');
  }
  // --- END ADDED ---

  // --- ADDED: Helper to extract the first URL from text ---
  String? _extractFirstUrl(String text) {
    if (text.isEmpty) return null;
    final RegExp urlRegex = RegExp(
        r"(?:(?:https?|ftp):\/\/|www\.)[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)",
        caseSensitive: false);
    final match = urlRegex.firstMatch(text);
    return match?.group(0);
  }
  // --- END ADDED ---

  // --- ADDED: Helper to paste Yelp URL from clipboard ---
  Future<void> _pasteYelpUrlFromClipboard() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final clipboardText = clipboardData?.text;

    if (clipboardText != null && clipboardText.isNotEmpty) {
      // --- MODIFIED: Extract URL first ---
      final extractedUrl = _extractFirstUrl(clipboardText);

      if (extractedUrl != null) {
        final isYelp = _isYelpUrl(extractedUrl);
        if (isYelp) {
          final isValid = _isValidUrl(extractedUrl);
          if (isValid) {
            // REMOVED setState
            // setState(() {
            widget.cardData.yelpUrlController.text = extractedUrl;
            // });
            // Notify parent of update (needed for suffix icon changes)
            widget.onUpdate(refreshCategories: false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Yelp URL pasted from clipboard.'),
                  duration: Duration(seconds: 1)),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Extracted URL is not valid.')),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Clipboard does not contain a Yelp URL.')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No URL found in clipboard.')),
        );
      }
      // --- END MODIFICATION ---
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard is empty.')),
      );
    }
  }
  // --- END ADDED ---

  // --- ADDED: Helper to paste Website URL from clipboard (direct paste) ---
  Future<void> _pasteWebsiteUrlFromClipboard() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final clipboardText = clipboardData?.text;

    if (clipboardText != null && clipboardText.isNotEmpty) {
      // REMOVED setState
      // setState(() {
      widget.cardData.websiteController.text = clipboardText; // Direct paste
      // });
      // Notify parent of update (needed for suffix icon changes)
      widget.onUpdate(refreshCategories: false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Pasted from clipboard.'),
            duration: Duration(seconds: 1)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard is empty.')),
      );
    }
  }
  // --- END ADDED ---

  // --- ADDED: Constants for special dropdown values ---
  static const String _addCategoryValue = '__add_new_category__';
  static const String _editCategoriesValue = '__edit_categories__';
  // --- ADDED Color Category constants ---
  static const String _addColorCategoryValue = '__add_new_color_category__';
  static const String _editColorCategoriesValue = '__edit_color_categories__';
  // --- END ADDED ---

  // --- ADDED: Constants for special dialog actions ---
  static const String _dialogActionAdd = '__add__';
  static const String _dialogActionEdit = '__edit__';
  // --- END ADDED ---

  @override
  void initState() {
    super.initState();
    // REMOVED: Initialize local state from widget.cardData
    // _isExpanded = widget.cardData.isExpanded;
    // _locationEnabled = widget.cardData.locationEnabled;

    // REMOVED: Add listeners to controllers
    // widget.cardData.titleController.addListener(_triggerRebuild);
    // widget.cardData.yelpUrlController.addListener(_triggerRebuild);
    // widget.cardData.websiteController.addListener(_triggerRebuild);
  }

  // REMOVED: _triggerRebuild method
  // void _triggerRebuild() {
  //   if (mounted) {
  //     setState(() {});
  //   }
  // }

  @override
  void didUpdateWidget(covariant ExperienceCardForm oldWidget) {
    super.didUpdateWidget(oldWidget);

    // REMOVED: Update local state based on incoming widget data
    // if (widget.cardData.locationEnabled != oldWidget.cardData.locationEnabled) {
    //   setState(() {
    //     _locationEnabled = widget.cardData.locationEnabled;
    //   });
    // }
    // if (widget.cardData.isExpanded != oldWidget.cardData.isExpanded) {
    //   setState(() {
    //     _isExpanded = widget.cardData.isExpanded;
    //   });
    // }
    // if (widget.cardData.selectedcategory !=
    //     oldWidget.cardData.selectedcategory) {
    //   _triggerRebuild(); // Keep this if the category button relies on it? No, parent rebuilds.
    // }

    // REMOVED: Update listeners if controller instances change
    // if (!identical(
    //     widget.cardData.titleController, oldWidget.cardData.titleController)) {
    //   oldWidget.cardData.titleController.removeListener(_triggerRebuild);
    //   widget.cardData.titleController.addListener(_triggerRebuild);
    // }
    // if (!identical(widget.cardData.yelpUrlController,
    //     oldWidget.cardData.yelpUrlController)) {
    //   oldWidget.cardData.yelpUrlController.removeListener(_triggerRebuild);
    //   widget.cardData.yelpUrlController.addListener(_triggerRebuild);
    // }
    // if (!identical(widget.cardData.websiteController,
    //     oldWidget.cardData.websiteController)) {
    //   oldWidget.cardData.websiteController.removeListener(_triggerRebuild);
    //   widget.cardData.websiteController.addListener(_triggerRebuild);
    // }
  }

  @override
  void dispose() {
    // REMOVED: Remove listeners
    // widget.cardData.titleController.removeListener(_triggerRebuild);
    // widget.cardData.yelpUrlController.removeListener(_triggerRebuild);
    // widget.cardData.websiteController.removeListener(_triggerRebuild);
    super.dispose();
  }

  // Helper method moved from ReceiveShareScreen
  bool _isValidUrl(String text) {
    // Basic check, can be enhanced
    final uri = Uri.tryParse(text);
    return uri != null && (uri.isScheme('http') || uri.isScheme('https'));
  }

  // Helper method to launch Yelp URLs or search Yelp
  Future<void> _launchYelpUrl() async {
    String yelpUrlString = widget.cardData.yelpUrlController.text.trim();
    Uri uri;

    if (yelpUrlString.isNotEmpty) {
      // Current behavior: field is not empty
      if (_isValidUrl(yelpUrlString) &&
          (yelpUrlString.contains('yelp.com') || yelpUrlString.contains('yelp.to'))) {
        uri = Uri.parse(yelpUrlString);
      } else {
        // Fallback to Yelp homepage if URL in field is invalid
        uri = Uri.parse('https://www.yelp.com');
      }
    } else {
      // New behavior: Yelp URL field is empty. Search using title and/or address.
      String titleString = widget.cardData.titleController.text.trim();
      // Get the Location object from cardData
      Location? currentLocation = widget.cardData.selectedLocation;
      // Get address from the currentLocation, can be null or empty if not set
      String? addressString = currentLocation?.address?.trim();

      if (titleString.isNotEmpty) {
        String searchDesc = Uri.encodeComponent(titleString);
        if (addressString != null && addressString.isNotEmpty) {
          // Both title and address are available
          String searchLoc = Uri.encodeComponent(addressString);
          uri = Uri.parse('https://www.yelp.com/search?find_desc=$searchDesc&find_loc=$searchLoc');
        } else {
          // Only title is available, address is not
          uri = Uri.parse('https://www.yelp.com/search?find_desc=$searchDesc');
        }
      } else {
        // Title is empty. Fallback to Yelp homepage.
        // (If title is empty, searching "along with title" is not possible)
        uri = Uri.parse('https://www.yelp.com');
      }
    }

    try {
      bool launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        // print('Could not launch $uri');
        // Optionally show a snackbar to the user
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open Yelp link/search')),
          );
        }
      }
    } catch (e) {
      // print('Error launching URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening link: $e')),
        );
      }
    }
  }

  // RENAMED: Helper to find icon for selected category
  String _getIconForSelectedCategory() {
    // Use renamed field
    final selectedId = widget.cardData.selectedCategoryId;
    if (selectedId == null) {
      return '❓'; // Default icon
    }
    // Use renamed parameter and class
    final matchingCategory = widget.userCategoriesNotifier.value.firstWhere(
      (category) => category.id == selectedId,
      orElse: () => UserCategory(
          id: '',
          name: '',
          icon: '❓',
          ownerUserId: ''), // Fallback with ownerUserId
    );
    return matchingCategory.icon;
  }

  // UPDATED: Method to handle adding a new category
  Future<void> _handleAddCategory() async {
    FocusScope.of(context).unfocus();
    print("DEBUG: Attempting to show AddCategoryModal...");
    final newCategory = await showModalBottomSheet<UserCategory>(
      context: context,
      builder: (context) => const AddCategoryModal(),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );
    if (newCategory != null && mounted) {
      print("New category added: ${newCategory.name} (${newCategory.icon})");
      // Notify parent to refresh list and pass new name to potentially select it
      widget.onUpdate(
          refreshCategories: true, newCategoryName: newCategory.name);
    }
  }

  // UPDATED: Method to handle editing categories
  Future<bool?> _handleEditCategories() async {
    FocusScope.of(context).unfocus();
    print("DEBUG: Attempting to show EditCategoriesModal...");
    // Show the EditCategoriesModal
    final bool? categoriesChanged = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => const EditCategoriesModal(), // Show the new modal
      isScrollControlled: true,
      enableDrag: false, // PREVENT DRAG TO DISMISS
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );
    // ADDED LOGGING
    print("EditCategoriesModal closed, categoriesChanged: $categoriesChanged (Text Categories)");

    if (categoriesChanged == true && mounted) {
      print("Categories potentially changed in Edit modal, refreshing list.");
      // Notify parent to just refresh the list
      widget.onUpdate(refreshCategories: true);
    }
    return categoriesChanged; // ADDED: Return the result
  }

  // --- UPDATED: Function to show the category selection dialog ---
  Future<void> _showCategorieselectionDialog() async {
    FocusScope.of(context).unfocus(); // Dismiss keyboard

    // Note: _userCategoriesNotifier.value will be used by ValueListenableBuilder inside StatefulBuilder

    final String? selectedValue = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        // Use StatefulBuilder to allow the dialog's content to rebuild when notifiers change
        return StatefulBuilder(
          builder: (stfContext, stfSetState) {
            // Listen to the notifier for category list changes
            return ValueListenableBuilder<List<UserCategory>>(
              valueListenable: widget.userCategoriesNotifier,
              builder: (context, currentCategories, child) {
                final uniqueCategoriesByName = <String, UserCategory>{};
                for (var category in currentCategories) {
                  uniqueCategoriesByName[category.name] = category;
                }
                final uniqueCategoryList = uniqueCategoriesByName.values.toList();

                return Dialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0)),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(stfContext).size.height * 0.8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                          child: Text(
                            'Select Category',
                            style: Theme.of(stfContext).textTheme.titleLarge,
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: uniqueCategoryList.length,
                            itemBuilder: (context, index) {
                              final category = uniqueCategoryList[index];
                              final bool isSelected = category.id == widget.cardData.selectedCategoryId;
                              return ListTile(
                                leading: Text(category.icon,
                                    style: const TextStyle(fontSize: 20)),
                                title: Text(category.name),
                                trailing: isSelected
                                    ? const Icon(Icons.check, color: Colors.blue)
                                    : null,
                                onTap: () {
                                  Navigator.pop(dialogContext, category.id);
                                },
                                visualDensity: VisualDensity.compact,
                              );
                            },
                          ),
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8.0, vertical: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextButton.icon(
                                icon: Icon(Icons.add, size: 20, color: Colors.blue[700]),
                                label: Text('Add New Category',
                                    style: TextStyle(color: Colors.blue[700])),
                                onPressed: () {
                                  Navigator.pop(dialogContext, _dialogActionAdd);
                                },
                                style: TextButton.styleFrom(
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 12)),
                              ),
                              TextButton.icon(
                                icon: Icon(Icons.edit, size: 20, color: Colors.orange[700]),
                                label: Text('Edit Categories',
                                    style: TextStyle(color: Colors.orange[700])),
                                onPressed: () async {
                                  final bool? categoriesActuallyChanged = await _handleEditCategories();
                                  // _handleEditCategories already calls widget.onUpdate(refreshCategories: true)
                                  // which updates the notifier. The ValueListenableBuilder above will rebuild.
                                  // No need to pop dialogContext here if changes were made,
                                  // as the goal is to keep the dialog open and show the refreshed list.
                                  if (categoriesActuallyChanged == true) {
                                      // Optional: if you want to do something specific in the dialog after edit modal closes with changes
                                      // For example, scroll to a newly selected/edited item if possible.
                                      // stfSetState(() {}); // Could be used if local dialog state needs refresh not covered by ValueListenableBuilder
                                  }
                                },
                                style: TextButton.styleFrom(
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 12)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );

    // --- Handle the dialog result --- (This part remains largely the same)
    if (selectedValue != null) {
      if (selectedValue == _dialogActionAdd) {
        _handleAddCategory();
      } else if (selectedValue == _dialogActionEdit) {
        // This case is less likely to be hit if we don't pop from edit action anymore unless intended
        // However, _handleEditCategories already calls onUpdate which should refresh the parent.
        print("CategorySelectionDialog popped with _dialogActionEdit, parent will refresh categories via onUpdate.");
      } else {
        if (widget.cardData.selectedCategoryId != selectedValue) {
          widget.cardData.selectedCategoryId = selectedValue;
          widget.onUpdate(refreshCategories: false);
        }
      }
    }
  }
  // --- END UPDATED FUNCTION ---

  // --- ADDED: Helper to find Color for selected ColorCategory ---
  Color _getColorForSelectedCategory() {
    final selectedId = widget.cardData.selectedColorCategoryId;
    if (selectedId == null) {
      return Colors.grey.shade400; // Default indicator color
    }
    final matchingCategory = widget.userColorCategoriesNotifier.value.firstWhere(
      (category) => category.id == selectedId,
      orElse: () => const ColorCategory(
          id: '',
          name: '',
          colorHex: 'FF9E9E9E', // Grey fallback
          ownerUserId: ''),
    );
    return matchingCategory.color;
  }

  ColorCategory? _getSelectedColorCategoryObject() {
    final selectedId = widget.cardData.selectedColorCategoryId;
    if (selectedId == null) {
      return null;
    }
    try {
      return widget.userColorCategoriesNotifier.value
          .firstWhere((cat) => cat.id == selectedId);
    } catch (e) {
      return null; // Not found
    }
  }

  // --- ADDED: Method to handle adding a new color category ---
  Future<void> _handleAddColorCategory() async {
    FocusScope.of(context).unfocus();
    // TODO: Implement AddColorCategoryModal
    final newCategory = await showModalBottomSheet<ColorCategory>(
      context: context,
      builder: (context) => const AddColorCategoryModal(), // Use placeholder
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );
    if (newCategory != null && mounted) {
      print(
          "New color category added: ${newCategory.name} (${newCategory.colorHex})");
      // Notify parent to refresh list and potentially select it
      // Note: We refresh BOTH lists as the modal interaction might affect order/usage indirectly
      widget.onUpdate(
          refreshCategories: true,
          newCategoryName:
              null); // Pass null for new name, selection happens based on ID
      // Explicitly set the new category ID
      // REMOVED setState
      // setState(() {
      widget.cardData.selectedColorCategoryId = newCategory.id;
      // });
    }
  }

  // --- ADDED: Method to handle editing color categories ---
  Future<bool?> _handleEditColorCategories() async {
    FocusScope.of(context).unfocus();
    
    final bool? categoriesChanged = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => const EditColorCategoriesModal(), 
      isScrollControlled: true,
      enableDrag: false, // PREVENT DRAG TO DISMISS
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );
    // ADDED LOGGING
    print("EditColorCategoriesModal closed, categoriesChanged: $categoriesChanged (Color Categories)");

    if (categoriesChanged == true && mounted) {
      print(
          "Color Categories potentially changed in Edit modal, refreshing list.");
      widget.onUpdate(refreshCategories: true);
    }
    return categoriesChanged; // ADDED: Return the result
  }

  // --- ADDED: Function to show the color category selection dialog ---
  Future<void> _showColorCategorySelectionDialog() async {
    FocusScope.of(context).unfocus(); // Dismiss keyboard

    final String? selectedValue = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        // Use StatefulBuilder to allow the dialog's content to rebuild when notifiers change
        return StatefulBuilder(
          builder: (stfContext, stfSetState) {
            // Listen to the notifier for color category list changes
            return ValueListenableBuilder<List<ColorCategory>>(
              valueListenable: widget.userColorCategoriesNotifier,
              builder: (context, currentColorCategories, child) {
                final List<ColorCategory> categoriesToShow =
                    List.from(currentColorCategories);

                return Dialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0)),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(stfContext).size.height * 0.8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                          child: Text(
                            'Select Color Category',
                            style: Theme.of(stfContext).textTheme.titleLarge,
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: categoriesToShow.length,
                            itemBuilder: (context, index) {
                              final category = categoriesToShow[index];
                              final bool isSelected = category.id ==
                                  widget.cardData.selectedColorCategoryId;
                              return ListTile(
                                leading: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                      color: category.color,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.grey.shade400,
                                          width: 1)),
                                ),
                                title: Text(category.name),
                                trailing: isSelected
                                    ? const Icon(Icons.check, color: Colors.blue)
                                    : null,
                                onTap: () {
                                  Navigator.pop(dialogContext, category.id);
                                },
                                visualDensity: VisualDensity.compact,
                              );
                            },
                          ),
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8.0, vertical: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextButton.icon(
                                icon: Icon(Icons.add_circle_outline,
                                    size: 20, color: Colors.blue[700]),
                                label: Text('Add New Color Category',
                                    style: TextStyle(color: Colors.blue[700])),
                                onPressed: () {
                                  Navigator.pop(
                                      dialogContext, _addColorCategoryValue);
                                },
                                style: TextButton.styleFrom(
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 12)),
                              ),
                              TextButton.icon(
                                icon: Icon(Icons.edit_outlined,
                                    size: 20, color: Colors.orange[700]),
                                label: Text('Edit Color Categories',
                                    style: TextStyle(color: Colors.orange[700])),
                                onPressed: () async {
                                  final bool? categoriesActuallyChanged = await _handleEditColorCategories();
                                  // _handleEditColorCategories already calls widget.onUpdate(refreshCategories: true)
                                  // which updates the notifier. The ValueListenableBuilder above will rebuild.
                                  // No need to pop dialogContext here if changes were made,
                                  // as the goal is to keep the dialog open and show the refreshed list.
                                  if (categoriesActuallyChanged == true) {
                                    // Optional: stfSetState(() {}); if local dialog state needs a nudge not covered by ValueListenableBuilder
                                  }
                                },
                                style: TextButton.styleFrom(
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 12)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );

    // Handle the dialog result
    if (selectedValue != null) {
      if (selectedValue == _addColorCategoryValue) {
        _handleAddColorCategory();
      } else if (selectedValue == _editColorCategoriesValue) {
         // This case is less likely to be hit if we don't pop from edit action anymore unless intended
        print("ColorCategorySelectionDialog popped with _editColorCategoriesValue, parent will refresh categories via onUpdate.");
      } else {
        // User selected an actual category ID
        if (widget.cardData.selectedColorCategoryId != selectedValue) {
          widget.cardData.selectedColorCategoryId = selectedValue;
          widget.onUpdate(
            refreshCategories: false,
          );
        }
      }
    }
  }
  // --- END ADDED ---

  // Build method - Logic from _buildExperienceCard goes here
  @override
  Widget build(BuildContext context) {
    // --- ADDED LOG ---
    print(
        "ExperienceCardForm BUILD: Received ${widget.userColorCategoriesNotifier.value.length} color categories.");
    // --- END ADDED LOG ---

    // Access controllers directly from widget.cardData
    final titleController = widget.cardData.titleController;
    final yelpUrlController = widget.cardData.yelpUrlController;
    final websiteController = widget.cardData.websiteController;
    final titleFocusNode = widget.cardData.titleFocusNode;
    final currentLocation = widget.cardData.selectedLocation;

    // print("FORM_DEBUG (${widget.cardData.id}): Build method running.");
    // print("FORM_DEBUG (${widget.cardData.id}): widget.cardData.selectedLocation: ${currentLocation?.displayName}");
    // print("FORM_DEBUG (${widget.cardData.id}): websiteController text: '${websiteController.text}'");

    return Card(
      margin: EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 2,
      child: Form(
        key: widget.formKey, // Use the passed form key
        child: Column(
          children: [
            // Header row with expand/collapse and delete functionality
            InkWell(
              onTap: () {
                setState(() {
                  widget.cardData.isExpanded = !widget.cardData.isExpanded;
                  // Unfocus any active fields when collapsing
                  if (!widget.cardData.isExpanded) {
                    FocusScope.of(context).unfocus();
                  }
                });
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      widget.cardData.isExpanded // Read directly from cardData
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.blue,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        titleController.text.isNotEmpty
                            ? titleController.text
                            : "New Experience",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    // Use the passed flag to control delete button
                    if (widget.canRemove)
                      IconButton(
                        icon:
                            Icon(Icons.delete_outline, color: Colors.red[400]),
                        onPressed: () => widget.onRemove(widget.cardData),
                        tooltip: 'Remove experience',
                      ),
                  ],
                ),
              ),
            ),

            // Expandable content
            if (widget.cardData.isExpanded) // Read directly from cardData
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Button to choose saved experience
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        icon: Icon(Icons.bookmark_outline),
                        label: Text('Choose a saved experience'),
                        onPressed: () =>
                            widget.onSelectSavedExperience(widget.cardData),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue,
                          padding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                    SizedBox(height: 12),

                    // Location selection with preview
                    GestureDetector(
                      // Call the parent's location selection logic
                      onTap: (widget.cardData
                              .locationEnabled) // Read directly from cardData
                          ? () => widget.onLocationSelect(widget.cardData)
                          : null,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: widget.cardData
                                      .locationEnabled // Read directly from cardData
                                  ? Colors.grey
                                  : Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(4),
                          color: Colors.transparent,
                        ),
                        padding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        child: Row(
                          children: [
                            Icon(Icons.location_on,
                                color: widget.cardData
                                        .locationEnabled // Read directly from cardData
                                    ? Colors.grey[600]
                                    : Colors.grey[400]),
                            SizedBox(width: 12),
                            Expanded(
                              child: currentLocation != null
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Place name in bold
                                        Text(
                                          currentLocation.getPlaceName(),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: widget.cardData
                                                    .locationEnabled // Read directly from cardData
                                                ? Colors.black
                                                : Colors.grey[500],
                                          ),
                                        ),
                                        // Address
                                        if (currentLocation.address != null)
                                          Text(
                                            currentLocation.address!,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: widget.cardData
                                                      .locationEnabled // Read directly from cardData
                                                  ? Colors.black87
                                                  : Colors.grey[500],
                                            ),
                                            maxLines: 1, // Limit address lines
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    )
                                  : Text(
                                      'Select location',
                                      style: TextStyle(
                                          color: widget.cardData
                                                  .locationEnabled // Read directly from cardData
                                              ? Colors.grey[600]
                                              : Colors.grey[400]),
                                    ),
                            ),
                            // Toggle switch inside the location field
                            Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: widget.cardData
                                    .locationEnabled, // Read directly from cardData
                                onChanged: (value) {
                                  widget.cardData.locationEnabled =
                                      value; // Update model
                                  widget.onUpdate(
                                      refreshCategories:
                                          false); // Notify parent, no refresh needed
                                },
                                activeColor: Colors.blue,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 16),

                    // Experience title
                    TextFormField(
                      controller: titleController, // Use controller from widget
                      focusNode: titleFocusNode, // Use focus node from widget
                      decoration: InputDecoration(
                        labelText: 'Experience Title',
                        hintText: 'Enter title',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.title),
                        suffixIcon: titleController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  // Directly clear controller from widget.cardData
                                  titleController.clear();
                                  // Listener will call _triggerRebuild
                                  widget.onUpdate(
                                      refreshCategories:
                                          false); // Notify parent, no refresh needed
                                },
                              )
                            : null,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a title';
                        }
                        return null;
                      },
                      onChanged: (value) {
                        // REMOVED Listener calls _triggerRebuild for UI updates (suffix icon, header)
                        // Notify parent only if parent needs immediate reaction to text changes
                        // widget.onUpdate();
                      },
                    ),
                    SizedBox(height: 16),

                    // --- REPLACED Dropdown with a Button wrapped in ValueListenableBuilder ---
                    Text('Category',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600])), // Label like text field
                    const SizedBox(height: 4),
                    ValueListenableBuilder<List<UserCategory>>(
                      valueListenable: widget.userCategoriesNotifier,
                      builder: (context, currentCategoryList, child) {
                        // Note: currentCategoryList is available if needed, but button display
                        // mainly depends on widget.cardData.selectedcategory
                        UserCategory? selectedCategoryObject;
                        if (widget.cardData.selectedCategoryId != null) {
                          try {
                            selectedCategoryObject = currentCategoryList.firstWhere(
                              (cat) => cat.id == widget.cardData.selectedCategoryId
                            );
                          } catch (e) {
                            // Category ID from cardData not found in current list, leave selectedCategoryObject null
                          }
                        }

                        return OutlinedButton(
                          onPressed: _showCategorieselectionDialog,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 15), // Adjust padding for height
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  8.0), // Match field style
                            ),
                            side: BorderSide(
                                color: Colors.grey), // Match field border
                            alignment:
                                Alignment.centerLeft, // Align content left
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment
                                .spaceBetween, // Space between content and arrow
                            children: [
                              // Display selected category icon and name
                              Row(
                                children: [
                                  Text(_getIconForSelectedCategory(),
                                      style: const TextStyle(fontSize: 18)),
                                  const SizedBox(width: 8),
                                  Text(
                                    selectedCategoryObject?.name ?? 'Select Category',
                                    style: TextStyle(
                                      // Ensure text color matches default button text color or form field color
                                      color:
                                          selectedCategoryObject != null
                                              ? Theme.of(context)
                                                  .textTheme
                                                  .bodyLarge
                                                  ?.color
                                              : Colors.grey[
                                                  600], // Hint color if nothing selected
                                    ),
                                  ),
                                ],
                              ),
                              // Dropdown arrow indicator
                              const Icon(Icons.arrow_drop_down,
                                  color: Colors.grey),
                            ],
                          ),
                        );
                      },
                    ),
                    // --- END REPLACEMENT (with wrapper) ---

                    SizedBox(height: 16),

                    // --- ADDED: Color Category Selection Button wrapped in ValueListenableBuilder ---
                    Text('Color Category',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.grey[600])),
                    const SizedBox(height: 4),
                    ValueListenableBuilder<List<ColorCategory>>(
                      valueListenable: widget.userColorCategoriesNotifier,
                      builder: (context, currentColorCategoryList, child) {
                        // Note: currentColorCategoryList is available if needed, but button display
                        // mainly depends on _getSelectedColorCategoryObject() and widget.cardData.selectedColorCategoryId
                        return OutlinedButton(
                          onPressed:
                              _showColorCategorySelectionDialog, // Call the new dialog function
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 15),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.0)),
                            side: BorderSide(color: Colors.grey),
                            alignment: Alignment.centerLeft,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  // Display selected category color circle
                                  Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                        color:
                                            _getColorForSelectedCategory(), // Use helper
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.grey.shade400,
                                            width: 1)),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _getSelectedColorCategoryObject()?.name ??
                                        'Select Color Category',
                                    style: TextStyle(
                                      color:
                                          widget.cardData.selectedColorCategoryId !=
                                                  null
                                              ? Theme.of(context)
                                                  .textTheme
                                                  .bodyLarge
                                                  ?.color
                                              : Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                              const Icon(Icons.arrow_drop_down,
                                  color: Colors.grey),
                            ],
                          ),
                        );
                      },
                    ),
                    // --- END ADDED (with wrapper) ---

                    SizedBox(height: 16),

                    // Yelp URL
                    TextFormField(
                      controller:
                          yelpUrlController, // Use controller from widget
                      decoration: InputDecoration(
                          labelText: 'Yelp URL (optional)',
                          hintText: 'https://yelp.com/...',
                          border: OutlineInputBorder(),
                          prefixIcon:
                              Icon(FontAwesomeIcons.yelp), // Use Yelp icon here
                          suffixIconConstraints: BoxConstraints.tightFor(
                              width: 90, // Keep width for three icons
                              height: 48), // Increase width for both icons
                          // Use suffix to combine clear and launch buttons
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize
                                .min, // Prevent row taking full width
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: <Widget>[
                              // Clear button (now first)
                              if (yelpUrlController.text.isNotEmpty)
                                InkWell(
                                  onTap: () {
                                    yelpUrlController.clear();
                                    widget.onUpdate(refreshCategories: false);
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 0), // No horizontal padding
                                    child: Icon(Icons.clear, size: 18),
                                  ),
                                ),
                              // Spacer
                              if (yelpUrlController.text
                                  .isNotEmpty) // Only show spacer if clear button is shown
                                const SizedBox(width: 8),

                              // Paste Button (now second)
                              InkWell(
                                onTap: _pasteYelpUrlFromClipboard,
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 0), // No horizontal padding
                                  child: Icon(Icons.content_paste,
                                      size: 18, color: Colors.blue[700]),
                                ),
                              ),

                              // Spacer
                              const SizedBox(width: 8),

                              // Yelp launch button (remains last)
                              InkWell(
                                onTap: _launchYelpUrl, // Always calls _launchYelpUrl
                                borderRadius: BorderRadius.circular(16), 
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                      right:
                                          8.0), // Add padding only on the right end
                                  child: Icon(FontAwesomeIcons.yelp,
                                      size: 18,
                                      color: Colors.red[700]), // Always active color
                                ),
                              ),
                            ],
                          )),
                      keyboardType: TextInputType.url,
                      validator: (value) {
                        if (value != null && value.isNotEmpty) {
                          // Use refined _isValidUrl
                          if (!_isValidUrl(value)) {
                            return 'Please enter a valid URL (http/https)';
                          }
                        }
                        return null;
                      },
                      onChanged: (value) {
                        // REMOVED Listener calls _triggerRebuild if needed
                        // widget.onUpdate();
                      },
                    ),
                    SizedBox(height: 16),

                    // Official website
                    TextFormField(
                      controller:
                          websiteController, // Use controller from widget
                      decoration: InputDecoration(
                        labelText: 'Official Website (optional)',
                        hintText: 'https://...',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.language),
                        // --- MODIFIED: Add Paste button to suffix ---
                        suffixIconConstraints: BoxConstraints.tightFor(
                            width: 90, // Keep width for three icons
                            height: 48),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            // Clear button (first)
                            if (websiteController.text.isNotEmpty)
                              InkWell(
                                onTap: () {
                                  websiteController.clear();
                                  widget.onUpdate(refreshCategories: false);
                                },
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 0),
                                  child: Icon(Icons.clear, size: 18),
                                ),
                              ),
                            // Spacer
                            if (websiteController.text.isNotEmpty)
                              const SizedBox(width: 8),

                            // Paste button (second)
                            InkWell(
                              onTap: _pasteWebsiteUrlFromClipboard,
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 0),
                                child: Icon(Icons.content_paste,
                                    size: 18, color: Colors.blue[700]),
                              ),
                            ),

                            // Spacer
                            const SizedBox(width: 8),

                            // Launch button (last)
                            InkWell(
                              onTap: websiteController.text.isNotEmpty &&
                                      _isValidUrl(websiteController.text.trim())
                                  ? () async {
                                      String urlString =
                                          websiteController.text.trim();
                                      // No need to re-validate here, already checked in condition
                                      try {
                                        await launchUrl(
                                          Uri.parse(urlString),
                                          mode: LaunchMode.externalApplication,
                                        );
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                                content: Text(
                                                    'Error opening link: $e')),
                                          );
                                        }
                                      }
                                    }
                                  : null,
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: Icon(Icons.launch, // Use launch icon
                                    size: 18,
                                    color: websiteController.text.isNotEmpty &&
                                            _isValidUrl(
                                                websiteController.text.trim())
                                        ? Colors.blue[700]
                                        : Colors.grey),
                              ),
                            ),
                          ],
                        ),
                        // --- END MODIFICATION ---
                      ),
                      keyboardType: TextInputType.url,
                      validator: (value) {
                        if (value != null && value.isNotEmpty) {
                          if (!_isValidUrl(value)) {
                            return 'Please enter a valid URL (http/https)';
                          }
                        }
                        return null;
                      },
                      onChanged: (value) {
                        // REMOVED Listener calls _triggerRebuild if needed
                        // widget.onUpdate();
                      },
                    ),
                    SizedBox(height: 16),

                    // Notes field
                    TextFormField(
                      controller: widget
                          .cardData.notesController, // Use notes controller
                      decoration: InputDecoration(
                        labelText: 'Notes (optional)',
                        hintText: 'Enter any additional notes...',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.notes),
                        alignLabelWithHint:
                            true, // Align label top-left for multi-line
                        suffixIcon:
                            widget.cardData.notesController.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      widget.cardData.notesController.clear();
                                      widget.onUpdate(refreshCategories: false);
                                    },
                                  )
                                : null,
                      ),
                      keyboardType: TextInputType.multiline,
                      minLines: 3, // Start with 3 lines height
                      maxLines: null, // Allow unlimited lines
                      // No validator needed as it's optional
                      onChanged: (value) {
                        // Trigger rebuild if suffix icon logic depends on it
                        widget.onUpdate(refreshCategories: false);
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
