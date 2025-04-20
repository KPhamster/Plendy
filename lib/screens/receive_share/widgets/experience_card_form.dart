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
});

class ExperienceCardForm extends StatefulWidget {
  final ExperienceCardData cardData;
  final bool isFirstCard; // To potentially hide remove button
  final bool canRemove; // Explicit flag to control remove button visibility
  final List<UserCategory> userCategories; // RENAMED
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
    required this.userCategories, // RENAMED
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
  bool _isExpanded = true;
  bool _locationEnabled = true;

  // Service needed for location updates if interaction happens within the form
  final GoogleMapsService _mapsService = GoogleMapsService();

  // ADDED: Service instance
  final ExperienceService _experienceService = ExperienceService();

  // --- ADDED: Constants for special dropdown values ---
  static const String _addCategoryValue = '__add_new_category__';
  static const String _editCategoriesValue = '__edit_categories__';
  // --- END ADDED ---

  // --- ADDED: Constants for special dialog actions ---
  static const String _dialogActionAdd = '__add__';
  static const String _dialogActionEdit = '__edit__';
  // --- END ADDED ---

  @override
  void initState() {
    super.initState();
    // Initialize local state from widget.cardData
    _isExpanded = widget.cardData.isExpanded;
    _locationEnabled = widget.cardData.locationEnabled;

    // Add listeners to controllers from widget.cardData
    // to trigger rebuilds for suffix icons, collapsed header title etc.
    widget.cardData.titleController.addListener(_triggerRebuild);
    widget.cardData.yelpUrlController.addListener(_triggerRebuild);
    widget.cardData.websiteController.addListener(_triggerRebuild);
  }

  // Helper simply calls setState if mounted
  void _triggerRebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant ExperienceCardForm oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update local state based on incoming widget data if it changed
    if (widget.cardData.locationEnabled != oldWidget.cardData.locationEnabled) {
      setState(() {
        _locationEnabled = widget.cardData.locationEnabled;
      });
    }
    if (widget.cardData.isExpanded != oldWidget.cardData.isExpanded) {
      setState(() {
        _isExpanded = widget.cardData.isExpanded;
      });
    }
    if (widget.cardData.selectedcategory !=
        oldWidget.cardData.selectedcategory) {
      _triggerRebuild();
    }

    // If the controller instances themselves have changed (e.g., after resetExperienceCards)
    // update listeners.
    if (!identical(
        widget.cardData.titleController, oldWidget.cardData.titleController)) {
      oldWidget.cardData.titleController.removeListener(_triggerRebuild);
      widget.cardData.titleController.addListener(_triggerRebuild);
    }
    if (!identical(widget.cardData.yelpUrlController,
        oldWidget.cardData.yelpUrlController)) {
      oldWidget.cardData.yelpUrlController.removeListener(_triggerRebuild);
      widget.cardData.yelpUrlController.addListener(_triggerRebuild);
    }
    if (!identical(widget.cardData.websiteController,
        oldWidget.cardData.websiteController)) {
      oldWidget.cardData.websiteController.removeListener(_triggerRebuild);
      widget.cardData.websiteController.addListener(_triggerRebuild);
    }
  }

  @override
  void dispose() {
    // Remove listeners added in initState (from the potentially old widget.cardData instance)
    // It's safer to check if the controller still exists or handle potential errors,
    // but typically dispose is called when the state object is permanently removed.
    // We access the current widget's cardData controllers here.
    widget.cardData.titleController.removeListener(_triggerRebuild);
    widget.cardData.yelpUrlController.removeListener(_triggerRebuild);
    widget.cardData.websiteController.removeListener(_triggerRebuild);
    super.dispose();
  }

  // Helper method moved from ReceiveShareScreen
  bool _isValidUrl(String text) {
    // Basic check, can be enhanced
    final uri = Uri.tryParse(text);
    return uri != null && (uri.isScheme('http') || uri.isScheme('https'));
  }

  // Helper method to launch Yelp URLs
  Future<void> _launchYelpUrl() async {
    String urlString = widget.cardData.yelpUrlController.text.trim();
    Uri uri;

    // Check if the entered text is a valid Yelp URL
    if (_isValidUrl(urlString) &&
        (urlString.contains('yelp.com') || urlString.contains('yelp.to'))) {
      uri = Uri.parse(urlString);
    } else {
      // Fallback to Yelp homepage
      uri = Uri.parse('https://www.yelp.com');
    }

    try {
      bool launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        // print('Could not launch $uri');
        // Optionally show a snackbar to the user
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open Yelp link')),
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
    final selectedName = widget.cardData.selectedcategory;
    if (selectedName == null) {
      return '❓'; // Default icon
    }
    // Use renamed parameter and class
    final matchingCategory = widget.userCategories.firstWhere(
      (category) => category.name == selectedName,
      orElse: () => UserCategory(id: '', name: '', icon: '❓'), // Fallback
    );
    return matchingCategory.icon;
  }

  // UPDATED: Method to handle adding a new category
  Future<void> _handleAddCategory() async {
    FocusScope.of(context).unfocus();
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
  Future<void> _handleEditCategories() async {
    FocusScope.of(context).unfocus();
    // Show the EditCategoriesModal
    final bool? categoriesChanged = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => const EditCategoriesModal(), // Show the new modal
      isScrollControlled: true,
      // Add shape etc. if desired, similar to Add modal
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );

    if (categoriesChanged == true && mounted) {
      print("Categories potentially changed in Edit modal, refreshing list.");
      // Notify parent to just refresh the list
      widget.onUpdate(refreshCategories: true);
      // Note: We don't need to explicitly select a category here
    }
  }

  // --- UPDATED: Function to show the category selection dialog ---
  Future<void> _showCategorySelectionDialog() async {
    FocusScope.of(context).unfocus(); // Dismiss keyboard

    final uniqueCategoriesByName = <String, UserCategory>{};
    for (var category in widget.userCategories) {
      uniqueCategoriesByName[category.name] = category;
    }
    final uniqueCategoryList = uniqueCategoriesByName.values.toList();

    final String? selectedValue = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        // Use a standard Dialog for more layout control
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
          child: ConstrainedBox(
            // Limit the dialog height to make the list scrollable
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8),
            child: Column(
              mainAxisSize: MainAxisSize.min, // Important for Column height
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Title Padding
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    'Select Category',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                // Scrollable List Area
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: uniqueCategoryList.length,
                    itemBuilder: (context, index) {
                      final category = uniqueCategoryList[index];
                      final bool isSelected =
                          category.name == widget.cardData.selectedcategory;
                      return ListTile(
                        leading: Text(category.icon,
                            style: const TextStyle(fontSize: 20)),
                        title: Text(category.name),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Colors.blue)
                            : null,
                        onTap: () {
                          Navigator.pop(
                              context, category.name); // Return category name
                        },
                        // Visual density can make items feel slightly shorter
                        visualDensity: VisualDensity.compact,
                      );
                    },
                  ),
                ),
                // Separator
                const Divider(height: 1),
                // Fixed Bottom Action Buttons
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8.0, vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextButton.icon(
                        icon:
                            Icon(Icons.add, size: 20, color: Colors.blue[700]),
                        label: Text('Add New Category',
                            style: TextStyle(color: Colors.blue[700])),
                        onPressed: () {
                          Navigator.pop(context, _dialogActionAdd);
                        },
                        style: TextButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12)),
                      ),
                      TextButton.icon(
                        icon: Icon(Icons.edit,
                            size: 20, color: Colors.orange[700]),
                        label: Text('Edit Categories',
                            style: TextStyle(color: Colors.orange[700])),
                        onPressed: () {
                          Navigator.pop(context, _dialogActionEdit);
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

    // --- Handle the dialog result ---
    if (selectedValue != null) {
      if (selectedValue == _dialogActionAdd) {
        // User selected Add New
        _handleAddCategory(); // This already handles refresh if needed
      } else if (selectedValue == _dialogActionEdit) {
        // User selected Edit
        _handleEditCategories(); // This already handles refresh if needed
      } else {
        // User selected an actual category
        if (widget.cardData.selectedcategory != selectedValue) {
          setState(() {
            widget.cardData.selectedcategory = selectedValue;
          });
          widget.onUpdate(refreshCategories: false);
        }
      }
    }
  }
  // --- END UPDATED FUNCTION ---

  // Build method - Logic from _buildExperienceCard goes here
  @override
  Widget build(BuildContext context) {
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
                  _isExpanded = !_isExpanded;
                });
                widget.cardData.isExpanded = _isExpanded; // Update data model
                // Unfocus any active fields when collapsing
                if (!_isExpanded) {
                  FocusScope.of(context).unfocus();
                }
                widget.onUpdate(
                    refreshCategories:
                        false); // Notify parent, no refresh needed
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      _isExpanded
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
            if (_isExpanded)
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
                      onTap: (_locationEnabled)
                          ? () => widget.onLocationSelect(widget.cardData)
                          : null,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: _locationEnabled
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
                                color: _locationEnabled
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
                                            color: _locationEnabled
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
                                              color: _locationEnabled
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
                                          color: _locationEnabled
                                              ? Colors.grey[600]
                                              : Colors.grey[400]),
                                    ),
                            ),
                            // Toggle switch inside the location field
                            Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: _locationEnabled,
                                onChanged: (value) {
                                  setState(() {
                                    _locationEnabled = value;
                                  });
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
                        // Listener calls _triggerRebuild for UI updates (suffix icon, header)
                        // Notify parent only if parent needs immediate reaction to text changes
                        // widget.onUpdate();
                      },
                    ),
                    SizedBox(height: 16),

                    // --- REPLACED Dropdown with a Button ---
                    Text('Category',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600])), // Label like text field
                    const SizedBox(height: 4),
                    OutlinedButton(
                      onPressed: _showCategorySelectionDialog,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 15), // Adjust padding for height
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(8.0), // Match field style
                        ),
                        side: BorderSide(
                            color: Colors.grey), // Match field border
                        alignment: Alignment.centerLeft, // Align content left
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
                                widget.cardData.selectedcategory ??
                                    'Select Category',
                                style: TextStyle(
                                  // Ensure text color matches default button text color or form field color
                                  color: widget.cardData.selectedcategory !=
                                          null
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
                          const Icon(Icons.arrow_drop_down, color: Colors.grey),
                        ],
                      ),
                    ),
                    // You might need a way to show validation errors if category is required
                    // This could involve a separate Text widget below the button
                    // that appears if widget.cardData.selectedcategory is null during form validation.
                    // For now, relying on parent form validation.
                    /* Example Validation Message Display:
                    if (widget.formKey.currentState?.validate() == false && widget.cardData.selectedcategory == null) 
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0, left: 12.0),
                        child: Text(
                          'Please select a category',
                          style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                        ),
                      ), 
                    */
                    // --- END REPLACEMENT ---

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
                              width: 60,
                              height: 48), // Increase width for both icons
                          // Use suffix to combine clear and launch buttons
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize
                                .min, // Prevent row taking full width
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: <Widget>[
                              // Clear button (only shown if text exists)
                              if (yelpUrlController.text.isNotEmpty)
                                InkWell(
                                  onTap: () {
                                    yelpUrlController.clear();
                                    widget.onUpdate(refreshCategories: false);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal:
                                            2.0), // Reduce horizontal padding
                                    child: Icon(Icons.clear, size: 18),
                                  ),
                                  // Consider adding splash/highlight color if desired
                                ),
                              // Yelp launch button
                              InkWell(
                                onTap: _launchYelpUrl,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal:
                                          8.0), // Reduce horizontal padding
                                  child: Icon(FontAwesomeIcons.yelp,
                                      size: 18, color: Colors.red[700]),
                                ),
                                // Consider adding splash/highlight color if desired
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
                        // Listener calls _triggerRebuild if needed
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
                        // Combine clear and launch buttons in the suffix
                        suffixIconConstraints: BoxConstraints.tightFor(
                            width: 60,
                            height: 48), // Adjust constraints for two icons
                        suffixIcon: Row(
                          mainAxisSize:
                              MainAxisSize.min, // Prevent row taking full width
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            // Clear button (only show if text exists)
                            if (websiteController.text.isNotEmpty)
                              InkWell(
                                onTap: () {
                                  websiteController.clear();
                                  widget.onUpdate(refreshCategories: false);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal:
                                          2.0), // Reduce horizontal padding
                                  child: Icon(Icons.clear, size: 18),
                                ),
                              ),
                            // Launch button
                            InkWell(
                              onTap: () async {
                                String urlString =
                                    websiteController.text.trim();
                                if (_isValidUrl(urlString)) {
                                  try {
                                    await launchUrl(
                                      Uri.parse(urlString),
                                      mode: LaunchMode.externalApplication,
                                    );
                                  } catch (e) {
                                    // print('Error launching URL: $e');
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content:
                                                Text('Error opening link: $e')),
                                      );
                                    }
                                  }
                                } else {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text('Enter a valid URL')),
                                    );
                                  }
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal:
                                        8.0), // Adjust padding as needed
                                child: Icon(Icons.launch, // Use launch icon
                                    size: 18,
                                    color: Colors.blue[700]),
                              ),
                            ),
                          ],
                        ),
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
                        // Listener calls _triggerRebuild if needed
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
