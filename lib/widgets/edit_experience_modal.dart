import 'package:flutter/material.dart';
import 'package:plendy/models/experience.dart';
import 'package:plendy/models/user_category.dart';
import 'package:plendy/screens/receive_share_screen.dart'
    show ExperienceCardData; // Re-use data structure
// For field structure reference (or reuse fields)
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; // For icons
import 'package:plendy/services/google_maps_service.dart'; // For location picker interaction
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:plendy/models/color_category.dart';
import 'package:plendy/widgets/add_color_category_modal.dart'; // Placeholder/Actual
import 'package:plendy/widgets/edit_color_categories_modal.dart'; // Placeholder/Actual
import 'package:plendy/widgets/add_category_modal.dart';
import 'package:plendy/widgets/edit_categories_modal.dart';
import 'package:plendy/services/experience_service.dart';
import 'package:collection/collection.dart'; // ADDED: Import for firstWhereOrNull
import 'package:plendy/screens/location_picker_screen.dart'; // ADDED: Import for LocationPickerScreen

class EditExperienceModal extends StatefulWidget {
  final Experience experience;
  final List<UserCategory> userCategories;
  final List<ColorCategory> userColorCategories;

  const EditExperienceModal({
    super.key,
    required this.experience,
    required this.userCategories,
    required this.userColorCategories,
  });

  @override
  State<EditExperienceModal> createState() => _EditExperienceModalState();
}

class _EditExperienceModalState extends State<EditExperienceModal> {
  // Use ExperienceCardData to manage form state internally
  late ExperienceCardData _cardData;
  final _formKey = GlobalKey<FormState>();
  final GoogleMapsService _mapsService =
      GoogleMapsService(); // If needed for picker

  // --- ADDED: Service instance and local state for categories ---
  final ExperienceService _experienceService = ExperienceService();
  List<UserCategory> _currentUserCategories = [];
  List<ColorCategory> _currentColorCategories = [];
  bool _isLoadingCategories = true; // Loading indicator for categories
  
  // --- ADDED: ValueNotifiers for reactive category updates ---
  late ValueNotifier<List<UserCategory>> _userCategoriesNotifier;
  late ValueNotifier<List<ColorCategory>> _colorCategoriesNotifier;
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
    // Initialize cardData with values from the existing experience
    _cardData = ExperienceCardData(); // Create a new instance
    _cardData.existingExperienceId =
        widget.experience.id; // Keep track of original ID
    _cardData.titleController.text = widget.experience.name;
    _cardData.yelpUrlController.text = widget.experience.yelpUrl ?? '';
    _cardData.websiteController.text = widget.experience.website ?? '';
    _cardData.notesController.text = widget.experience.additionalNotes ?? '';
    _cardData.selectedCategoryId = widget.experience.categoryId;
    _cardData.selectedColorCategoryId = widget.experience.colorCategoryId;
    _cardData.selectedOtherCategoryIds = List<String>.from(widget.experience.otherCategories); // Initialize other categories
    _cardData.selectedLocation = widget.experience.location;
    _cardData.locationEnabled.value = widget.experience.location.latitude != 0.0 ||
        widget.experience.location.longitude != 0.0;

    // If location exists, pre-fill searchController for display consistency (optional)
    if (_cardData.selectedLocation?.address != null) {
      _cardData.searchController.text = _cardData.selectedLocation!.address!;
    }

    // --- ADDED: Initialize ValueNotifiers ---
    _userCategoriesNotifier = ValueNotifier<List<UserCategory>>([]);
    _colorCategoriesNotifier = ValueNotifier<List<ColorCategory>>([]);
    // --- END ADDED ---

    // --- ADDED: Listener to rebuild on Yelp URL text change for suffix icons ---
    _cardData.yelpUrlController.addListener(_triggerRebuild);
    // --- END ADDED ---
    // --- ADDED: Listener for Website URL ---
    _cardData.websiteController.addListener(_triggerRebuild);
    // --- END ADDED ---

    // --- ADDED: Load categories on init ---
    _loadAllCategories();
    // --- END ADDED ---
  }

  @override
  void dispose() {
    // Dispose controllers managed by _cardData
    _cardData.dispose();
    // --- ADDED: Remove listener ---
    _cardData.yelpUrlController.removeListener(_triggerRebuild);
    // --- END ADDED ---
    // --- ADDED: Remove Website listener ---
    _cardData.websiteController.removeListener(_triggerRebuild);
    // --- END ADDED ---
    
    // --- ADDED: Dispose ValueNotifiers ---
    _userCategoriesNotifier.dispose();
    _colorCategoriesNotifier.dispose();
    // --- END ADDED ---
    
    super.dispose();
  }

  // --- ADDED: Helper simply calls setState if mounted ---
  void _triggerRebuild() {
    if (mounted) {
      setState(() {});
    }
  }
  // --- END ADDED ---

  // --- ADDED: Methods to load categories locally ---
  Future<void> _loadAllCategories() async {
    setState(() => _isLoadingCategories = true);
    try {
      final results = await Future.wait([
        _experienceService.getUserCategories(),
        _experienceService.getUserColorCategories(),
      ]);
      if (mounted) {
        setState(() {
          _currentUserCategories = results[0] as List<UserCategory>;
          _currentColorCategories = results[1] as List<ColorCategory>;
          _isLoadingCategories = false;
        });
        // --- ADDED: Update ValueNotifiers ---
        _userCategoriesNotifier.value = _currentUserCategories;
        _colorCategoriesNotifier.value = _currentColorCategories;
        // --- END ADDED ---
      }
    } catch (e) {
      print("EditExperienceModal: Error loading categories: $e");
      if (mounted) {
        setState(() => _isLoadingCategories = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading categories: $e")),
        );
      }
    }
  }

  Future<void> _loadUserCategories() async {
    // Simplified version for targeted refresh
    setState(() => _isLoadingCategories = true);
    try {
      final categories = await _experienceService.getUserCategories();
      if (mounted) {
        setState(() {
          _currentUserCategories = categories;
          _isLoadingCategories = false;
        });
        // --- ADDED: Update ValueNotifier ---
        _userCategoriesNotifier.value = _currentUserCategories;
        // --- END ADDED ---
      }
    } catch (e) {
      print("EditExperienceModal: Error loading user categories: $e");
      if (mounted) {
        setState(() => _isLoadingCategories = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading user categories: $e")),
        );
      }
    }
  }

  Future<void> _loadColorCategories() async {
    // Simplified version for targeted refresh
    setState(() => _isLoadingCategories = true);
    try {
      final categories = await _experienceService.getUserColorCategories();
      if (mounted) {
        setState(() {
          _currentColorCategories = categories;
          _isLoadingCategories = false;
        });
        // --- ADDED: Update ValueNotifier ---
        _colorCategoriesNotifier.value = _currentColorCategories;
        // --- END ADDED ---
      }
    } catch (e) {
      print("EditExperienceModal: Error loading color categories: $e");
      if (mounted) {
        setState(() => _isLoadingCategories = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading color categories: $e")),
        );
      }
    }
  }
  // --- END ADDED ---

  // Helper method moved from ReceiveShareScreen's form widget
  bool _isValidUrl(String text) {
    final uri = Uri.tryParse(text);
    return uri != null && (uri.isScheme('http') || uri.isScheme('https'));
  }

  // --- Location Picker Logic (Adapted from ReceiveShareScreen) ---
  Future<void> _showLocationPicker() async {
    FocusScope.of(context).unfocus();

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          initialLocation: _cardData.selectedLocation,
          onLocationSelected: (location) {}, // Dummy callback
          // Pass name hint if desired, potentially from titleController
          businessNameHint: _cardData.titleController.text,
        ),
      ),
    );

    if (result != null && mounted) {
      Future.microtask(() => FocusScope.of(context).unfocus());

      final Location selectedLocation =
          result is Map ? result['location'] : result as Location;

      // Fetch details for the *newly selected* location to get address/website etc.
      try {
        if (selectedLocation.placeId == null ||
            selectedLocation.placeId!.isEmpty) {
          print(
              "WARN: Location picked has no Place ID. Performing basic update.");
          setState(() {
            _cardData.selectedLocation = selectedLocation;
            _cardData.searchController.text =
                selectedLocation.address ?? 'Selected Location';
            _cardData.locationEnabled.value = true; // Assume enabled if picked
          });
          return;
        }

        Location detailedLocation =
            await _mapsService.getPlaceDetails(selectedLocation.placeId!);
        print(
            "Edit Modal: Fetched details for picked location: ${detailedLocation.displayName}");

        // Update cardData state
        setState(() {
          _cardData.selectedLocation = detailedLocation;
          _cardData.titleController.text = detailedLocation
              .getPlaceName(); // Update title? Discuss if needed
          _cardData.websiteController.text = detailedLocation.website ??
              _cardData.websiteController
                  .text; // Keep existing website if new one is null? Or override?
          _cardData.searchController.text =
              detailedLocation.address ?? ''; // For display in location field
          _cardData.locationEnabled.value = true;
        });
      } catch (e) {
        print("Error getting place details after picking location: $e");
        // Fallback: Update with the basic location selected if details fetch fails
        setState(() {
          _cardData.selectedLocation = selectedLocation;
          _cardData.searchController.text =
              selectedLocation.address ?? 'Selected Location';
          _cardData.locationEnabled.value = true;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating location details: $e')),
          );
        }
      }
    }
  }
  // --- End Location Picker Logic ---

  // --- Category Selection Logic (Adapted from ExperienceCardForm) ---
  Future<void> _showCategorieselectionDialog() async {
    FocusScope.of(context).unfocus(); // Dismiss keyboard

    final String? selectedValue = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        // Use StatefulBuilder to allow the dialog's content to rebuild when categories change
        return StatefulBuilder(
          builder: (stfContext, stfSetState) {
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
                      child: Text('Select Primary Category',
                          style: Theme.of(stfContext).textTheme.titleLarge),
                    ),
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _currentUserCategories.length,
                        itemBuilder: (context, index) {
                          final category = _currentUserCategories[index];
                          final bool isSelected = 
                              category.id == _cardData.selectedCategoryId;
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
                            icon: Icon(Icons.add,
                                size: 20, color: Colors.blue[700]),
                            label: Text('Add New Category',
                                style: TextStyle(color: Colors.blue[700])),
                            onPressed: () async {
                              // Handle add category and refresh dialog
                              final newCategory = await showModalBottomSheet<UserCategory>(
                                context: stfContext,
                                builder: (context) => const AddCategoryModal(),
                                isScrollControlled: true,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                                ),
                              );
                              if (newCategory != null && mounted) {
                                print("Edit Modal: New user category added: ${newCategory.name} (${newCategory.icon})");
                                setState(() {
                                  _cardData.selectedCategoryId = newCategory.id;
                                });
                                await _loadUserCategories();
                                // Refresh the dialog
                                stfSetState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Category "${newCategory.name}" added and selected.')),
                                );
                              }
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
                            onPressed: () async {
                              final bool? categoriesChanged = await showModalBottomSheet<bool>(
                                context: stfContext,
                                builder: (context) => const EditCategoriesModal(),
                                isScrollControlled: true,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                                ),
                              );
                              if (categoriesChanged == true && mounted) {
                                print("Edit Modal: User Categories potentially changed.");
                                await _loadUserCategories();
                                // Check if current selection still exists
                                final currentSelectionExists = _currentUserCategories
                                    .any((cat) => cat.id == _cardData.selectedCategoryId);
                                if (!currentSelectionExists && _cardData.selectedCategoryId != null) {
                                  setState(() {
                                    _cardData.selectedCategoryId = null;
                                  });
                                }
                                // Refresh the dialog
                                stfSetState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Category list updated. Please review your selection.')),
                                );
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

    // Handle the dialog result
    if (selectedValue != null) {
      if (_cardData.selectedCategoryId != selectedValue) { 
        setState(() {
          _cardData.selectedCategoryId = selectedValue; 
        });
      }
    }
  }
  // --- END ADDED ---

  // Helper to get category icon
  String _getIconForSelectedCategory() {
    final selectedId = _cardData.selectedCategoryId; 
    if (selectedId == null) return '❓'; 
    try {
      final matchingCategory = _currentUserCategories.firstWhere(
        (category) => category.id == selectedId, // Find by ID
      );
      return matchingCategory.icon;
    } catch (e) {
      return '❓'; // Not found
    }
  }
  // --- End Category Selection Logic ---

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

  // --- ADDED: Helper method to launch Yelp URLs ---
  // MODIFIED: Replaced with the comprehensive version from ExperienceCardForm
  Future<void> _launchYelpUrl() async {
    String yelpUrlString = _cardData.yelpUrlController.text.trim();
    Uri uri;

    if (yelpUrlString.isNotEmpty) {
      // Behavior when Yelp URL field is NOT empty
      if (_isValidUrl(yelpUrlString) &&
          (yelpUrlString.toLowerCase().contains('yelp.com/biz') || yelpUrlString.toLowerCase().contains('yelp.to/'))) { // Ensure it's a Yelp specific link for direct launch
        uri = Uri.parse(yelpUrlString);
      } else {
        // Fallback to Yelp homepage if URL in field is invalid or not a specific Yelp business link
        // Or, consider showing an error: "Please enter a valid Yelp business page URL."
        uri = Uri.parse('https://www.yelp.com');
         if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Invalid or non-specific Yelp URL. Opening Yelp home.')),
          );
        }
      }
    } else {
      // Behavior when Yelp URL field IS empty: Search Yelp
      String titleString = _cardData.titleController.text.trim();
      Location? currentLocation = _cardData.selectedLocation;
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
        uri = Uri.parse('https://www.yelp.com');
      }
    }

    try {
      bool launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        // print('Could not launch $uri');
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
  // --- END ADDED ---

  // --- ADDED: Helper to paste Yelp URL from clipboard ---
  Future<void> _pasteYelpUrlFromClipboard() async {
    // print('MODAL: _pasteYelpUrlFromClipboard called.'); // Log entry
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final clipboardText = clipboardData?.text;
    // print('MODAL: Clipboard text retrieved: "$clipboardText"'); // Log clipboard content

    if (clipboardText != null && clipboardText.isNotEmpty) {
      // --- MODIFIED: Extract URL first ---
      final extractedUrl = _extractFirstUrl(clipboardText);
      // print('MODAL: Extracted URL from clipboard: "$extractedUrl"');

      if (extractedUrl != null) {
        final isYelp = _isYelpUrl(extractedUrl);
        // print('MODAL: Is Yelp URL check result (extracted): $isYelp'); // Log Yelp check
        if (isYelp) {
          // Validate the *extracted* URL
          final isValid = _isValidUrl(extractedUrl);
          // print('MODAL: Is valid URL check result (extracted): $isValid'); // Log validity check
          if (isValid) {
            // print(
            //     'MODAL: Conditions met, calling setState to update text field with extracted URL.'); // Log before setState
            setState(() {
              _cardData.yelpUrlController.text =
                  extractedUrl; // Paste extracted URL
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Yelp URL pasted from clipboard.'),
                  duration: Duration(seconds: 1)),
            );
          } else {
            // print('MODAL: Extracted URL is not a valid URL.'); // Log error
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Extracted URL is not valid.')),
            );
          }
        } else {
          // print('MODAL: Extracted URL is not a Yelp URL.'); // Log error
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Clipboard does not contain a Yelp URL.')),
          );
        }
      } else {
        // print('MODAL: No URL found in clipboard text.'); // Log error
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No URL found in clipboard.')),
        );
      }
      // --- END MODIFICATION ---
    } else {
      // print('MODAL: Clipboard is empty.'); // Log error
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
      setState(() {
        _cardData.websiteController.text = clipboardText; // Direct paste
      });
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

  // --- ADDED: Color Category Selection Logic (Copied & Adapted from ExperienceCardForm state) ---

  // Helper to find Color for selected ColorCategory
  Color _getColorForSelectedCategory() {
    final selectedId = _cardData.selectedColorCategoryId;
    if (selectedId == null) {
      return Colors.grey.shade400; // Default indicator color
    }
    // Use the list passed to the modal
    final matchingCategory = _currentColorCategories.firstWhere(
      (category) => category.id == selectedId,
      orElse: () => const ColorCategory(
          id: '',
          name: '',
          colorHex: 'FF9E9E9E', // Grey fallback
          ownerUserId: ''),
    );
    return matchingCategory.color;
  }

  // Helper to get the full ColorCategory object
  ColorCategory? _getSelectedColorCategoryObject() {
    final selectedId = _cardData.selectedColorCategoryId;
    if (selectedId == null) {
      return null;
    }
    try {
      // Use the list passed to the modal
      return _currentColorCategories.firstWhere((cat) => cat.id == selectedId);
    } catch (e) {
      return null; // Not found
    }
  }

  // Method to handle adding a new color category
  Future<void> _handleAddColorCategory() async {
    FocusScope.of(context).unfocus();
    final newCategory = await showModalBottomSheet<ColorCategory>(
      context: context,
      builder: (context) => const AddColorCategoryModal(), // Use the modal
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );
    if (newCategory != null && mounted) {
      print(
          "Edit Modal: New color category added: ${newCategory.name} (${newCategory.colorHex})");
      // Similar to user categories, select the new one
      setState(() {
        _cardData.selectedColorCategoryId = newCategory.id;
        // Assume widget.userColorCategories might update via provider
      });
      // --- MODIFIED: Refresh local list ---
      _loadColorCategories(); // Refresh the list within this modal
      // --- END MODIFICATION ---
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Color Category "${newCategory.name}" added. It has been selected.')),
      );
    }
  }

  // Method to handle editing color categories
  Future<void> _handleEditColorCategories() async {
    FocusScope.of(context).unfocus();
    final bool? categoriesChanged = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => const EditColorCategoriesModal(), // Use the modal
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );

    if (categoriesChanged == true && mounted) {
      print("Edit Modal: Color Categories potentially changed.");
      // Check if the current selection still exists
      final currentSelectionExists = _currentColorCategories
          .any((cat) => cat.id == _cardData.selectedColorCategoryId);
      if (!currentSelectionExists &&
          _cardData.selectedColorCategoryId != null) {
        setState(() {
          _cardData.selectedColorCategoryId =
              null; // Clear selection if removed/renamed
        });
      } else {
        // Force rebuild in case color/name changed
        setState(() {});
      }
      // --- MODIFIED: Refresh local list ---
      _loadColorCategories(); // Refresh the list within this modal
      // --- END MODIFICATION ---
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Color Category list updated. Please review your selection.')),
      );
    }
  }

  // Function to show the color category selection dialog
  Future<void> _showColorCategorySelectionDialog() async {
    FocusScope.of(context).unfocus(); // Dismiss keyboard

    // Use the list passed to the modal
    final List<ColorCategory> categoriesToShow =
        List.from(_currentColorCategories);

    final String? selectedValue = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    'Select Color Category',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: categoriesToShow.length,
                    itemBuilder: (context, index) {
                      final category = categoriesToShow[index];
                      final bool isSelected = category.id ==
                          _cardData.selectedColorCategoryId; // Use _cardData
                      return ListTile(
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
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Colors.blue)
                            : null,
                        onTap: () {
                          Navigator.pop(
                              context, category.id); // Return category ID
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
                              context, _addColorCategoryValue); // Use constant
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
                        onPressed: () {
                          Navigator.pop(context,
                              _editColorCategoriesValue); // Use constant
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

    // Handle the dialog result
    if (selectedValue != null) {
      if (selectedValue == _addColorCategoryValue) {
        _handleAddColorCategory(); // Call handler
      } else if (selectedValue == _editColorCategoriesValue) {
        _handleEditColorCategories(); // Call handler
      } else {
        // User selected an actual category ID
        if (_cardData.selectedColorCategoryId != selectedValue) {
          setState(() {
            _cardData.selectedColorCategoryId =
                selectedValue; // Update _cardData
          });
        }
      }
    }
  }
  // --- END ADDED Color Category Logic ---

  // --- ADDED: Function to show the other categories selection dialog ---
  Future<void> _showOtherCategoriesSelectionDialog() async {
    FocusScope.of(context).unfocus();

    final result = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false, // User must press button
      builder: (BuildContext dialogContext) {
        return _OtherCategoriesSelectionDialog(
          userCategoriesNotifier: _userCategoriesNotifier,
          initiallySelectedIds: _cardData.selectedOtherCategoryIds,
          primaryCategoryId: _cardData.selectedCategoryId,
          onEditCategories: () async {
            final bool? categoriesChanged = await showModalBottomSheet<bool>(
              context: dialogContext,
              builder: (context) => const EditCategoriesModal(),
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
            );
            if (categoriesChanged == true && mounted) {
              print("Edit Modal: User Categories potentially changed from Other Categories dialog.");
              await _loadUserCategories();
              // Check if current selection still exists
              final currentSelectionExists = _currentUserCategories
                  .any((cat) => cat.id == _cardData.selectedCategoryId);
              if (!currentSelectionExists && _cardData.selectedCategoryId != null) {
                setState(() {
                  _cardData.selectedCategoryId = null;
                });
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Category list updated. Please review your selection.')),
              );
              // After editing categories, reopen this dialog
              if (mounted) {
                _showOtherCategoriesSelectionDialog();
              }
            }
            return categoriesChanged;
          },
          onAddCategory: () async {
            final newCategory = await showModalBottomSheet<UserCategory>(
              context: dialogContext,
              builder: (context) => const AddCategoryModal(),
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
            );
            if (newCategory != null && mounted) {
              print("Edit Modal: New user category added from Other Categories dialog: ${newCategory.name} (${newCategory.icon})");
              await _loadUserCategories();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Category "${newCategory.name}" added.')),
              );
              // After adding the category, reopen this dialog
              if (mounted) {
                _showOtherCategoriesSelectionDialog();
              }
            }
          },
        );
      },
    );

    if (result is List<String>) {
      setState(() {
        _cardData.selectedOtherCategoryIds = result;
      });
    }
  }
  // --- END ADDED ---

  void _saveAndClose() {
    if (_formKey.currentState!.validate()) {
      // Construct the updated Experience object
      final Location locationToSave = (_cardData.locationEnabled.value &&
              _cardData.selectedLocation != null)
          ? _cardData.selectedLocation!
          : Location(
              latitude: 0.0,
              longitude: 0.0,
              address: 'No location specified'); // Default/disabled location

      final updatedExperience = widget.experience.copyWith(
        name: _cardData.titleController.text.trim(),
        categoryId: _cardData.selectedCategoryId,
        location: locationToSave,
        yelpUrl: _cardData.yelpUrlController.text.trim().isNotEmpty
            ? _cardData.yelpUrlController.text.trim()
            : null,
        website: _cardData.websiteController.text.trim().isNotEmpty
            ? _cardData.websiteController.text.trim()
            : null,
        colorCategoryId: _cardData.selectedColorCategoryId,
        otherCategories: _cardData.selectedOtherCategoryIds,
        additionalNotes: _cardData.notesController.text.trim().isEmpty
            ? null
            : _cardData.notesController.text.trim(),
        updatedAt: DateTime.now(), // Update timestamp
      );

      // --- DEBUG PRINTS ---
      print(
          "EDIT MODAL SAVE: Notes Controller Text: '${_cardData.notesController.text.trim()}'");
      print(
          "EDIT MODAL SAVE: updatedExperience.additionalNotes: ${updatedExperience.additionalNotes}");
      // --- END DEBUG PRINTS ---

      Navigator.of(context).pop(updatedExperience); // Return the updated object
    } else {
      // Show error if form invalid
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fix the errors in the form.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Make modal content scrollable and handle keyboard padding
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min, // Fit content vertically
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Modal Title
              Text(
                'Edit Experience',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),

              // --- Form Fields (Similar to ExperienceCardForm) ---

              // Location selection (using adapted widget/logic)
              GestureDetector(
                onTap: (_cardData.locationEnabled.value) ? _showLocationPicker : null,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: _cardData.locationEnabled.value
                            ? Colors.grey
                            : Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.location_on,
                          color: _cardData.locationEnabled.value
                              ? Colors.grey[600]
                              : Colors.grey[400]),
                      SizedBox(width: 12),
                      Expanded(
                        child: _cardData.selectedLocation != null &&
                                _cardData.selectedLocation!.latitude != 0.0
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _cardData.selectedLocation!
                                        .getPlaceName(), // Use helper
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: _cardData.locationEnabled.value
                                            ? Colors.black
                                            : Colors.grey[500]),
                                  ),
                                  if (_cardData.selectedLocation!.address !=
                                      null)
                                    Text(
                                      _cardData.selectedLocation!.address!,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: _cardData.locationEnabled.value
                                              ? Colors.black87
                                              : Colors.grey[500]),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              )
                            : Text(
                                'Select location',
                                style: TextStyle(
                                    color: _cardData.locationEnabled.value
                                        ? Colors.grey[600]
                                        : Colors.grey[400]),
                              ),
                      ),
                      Transform.scale(
                        // Toggle switch
                        scale: 0.8,
                        child: Switch(
                          value: _cardData.locationEnabled.value,
                          onChanged: (value) {
                            setState(() {
                              _cardData.locationEnabled.value = value;
                            });
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
                controller: _cardData.titleController,
                decoration: InputDecoration(
                  labelText: 'Experience Title',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),

              // Category Selection Button
              Text('Primary Category',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey[600])),
              const SizedBox(height: 4),
              OutlinedButton(
                onPressed:
                    _isLoadingCategories ? null : _showCategorieselectionDialog,
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
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
                        Text(_getIconForSelectedCategory(),
                            style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Text(
                          _currentUserCategories.firstWhereOrNull((cat) => cat.id == _cardData.selectedCategoryId)?.name ?? 'Select Category',
                          style: TextStyle(
                              color: _cardData.selectedCategoryId != null
                                  ? Theme.of(context).textTheme.bodyLarge?.color
                                  : Colors.grey[600]),
                        ),
                      ],
                    ),
                    const Icon(Icons.arrow_drop_down, color: Colors.grey),
                  ],
                ),
              ),
              // TODO: Add validation message display if needed
              SizedBox(height: 16),

              // Color Category Selection Button
              Text('Color Category',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey[600])),
              const SizedBox(height: 4),
              OutlinedButton(
                onPressed: _isLoadingCategories
                    ? null
                    : _showColorCategorySelectionDialog,
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
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
                                  color: Colors.grey.shade400, width: 1)),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _getSelectedColorCategoryObject()?.name ??
                              'Select Color Category',
                          style: TextStyle(
                            color: _cardData.selectedColorCategoryId != null
                                ? Theme.of(context).textTheme.bodyLarge?.color
                                : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const Icon(Icons.arrow_drop_down, color: Colors.grey),
                  ],
                ),
              ),
              SizedBox(height: 16),

              // --- ADDED: Other Categories Selection ---
              Text('Other Categories',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey[600])),
              const SizedBox(height: 4),
              Container(
                width: double.infinity, // Ensure it takes full width
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_cardData.selectedOtherCategoryIds.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          'No other categories assigned.',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Wrap(
                          spacing: 6.0,
                          runSpacing: 6.0,
                          children: _cardData.selectedOtherCategoryIds.map((categoryId) {
                            final category = _currentUserCategories.firstWhereOrNull((cat) => cat.id == categoryId);
                            if (category == null) return const SizedBox.shrink();
                            return Chip(
                              avatar: Text(category.icon,
                                  style: const TextStyle(fontSize: 14)),
                              label: Text(category.name),
                              onDeleted: () {
                                setState(() {
                                  _cardData.selectedOtherCategoryIds.remove(categoryId);
                                });
                              },
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(horizontal: 0),
                              visualDensity: VisualDensity.compact,
                              labelPadding: const EdgeInsets.symmetric(horizontal: 4.0),
                              deleteIconColor: Colors.grey[600],
                              deleteButtonTooltipMessage: 'Remove category',
                            );
                          }).toList(),
                        ),
                      ),
                    Center(
                      child: TextButton.icon(
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text('Add / Edit Categories'),
                        onPressed: _showOtherCategoriesSelectionDialog,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // --- END ADDED ---

              SizedBox(height: 16),

              // Yelp URL
              TextFormField(
                controller: _cardData.yelpUrlController,
                decoration: InputDecoration(
                    labelText: 'Yelp URL (optional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(FontAwesomeIcons.yelp),
                    // --- ADDED: Suffix Icons ---
                    suffixIconConstraints: BoxConstraints.tightFor(
                        width: 110, // Keep width for three icons
                        height: 48),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        // Clear button (now first)
                        if (_cardData.yelpUrlController.text.isNotEmpty)
                          InkWell(
                            onTap: () {
                              _cardData.yelpUrlController.clear();
                              // Listener will call _triggerRebuild
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(4.0), // No horizontal padding needed here
                              child: Icon(Icons.clear, size: 22),
                            ),
                          ),
                        // Spacer
                        if (_cardData.yelpUrlController.text
                            .isNotEmpty) // Only show spacer if clear button is shown
                          const SizedBox(width: 4),

                        // Paste button (now second)
                        InkWell(
                          onTap: _pasteYelpUrlFromClipboard,
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0), // No horizontal padding needed here
                            child: Icon(Icons.content_paste,
                                size: 22, color: Colors.blue[700]),
                          ),
                        ),

                        // Spacer
                        const SizedBox(width: 4),

                        // Yelp launch button (remains last)
                        InkWell(
                          onTap: _launchYelpUrl, // MODIFIED: Always call _launchYelpUrl
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4.0, 4.0, 8.0, 4.0),
                            child: Icon(FontAwesomeIcons.yelp,
                                size: 22,
                                color: Colors.red[700]), // MODIFIED: Always active color
                          ),
                        ),
                      ],
                    )
                    // --- END ADDED ---
                    ),
                keyboardType: TextInputType.url,
                validator: (value) {
                  if (value != null &&
                      value.isNotEmpty &&
                      !_isValidUrl(value)) {
                    return 'Please enter a valid URL (http/https)';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),

              // Official website
              TextFormField(
                controller: _cardData.websiteController,
                decoration: InputDecoration(
                    labelText: 'Official Website (optional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.language),
                    // --- MODIFIED: Add Paste button to suffix ---
                    suffixIconConstraints: BoxConstraints.tightFor(
                        width: 110, // Keep width for three icons
                        height: 48),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        // Clear button (first)
                        if (_cardData.websiteController.text.isNotEmpty)
                          InkWell(
                            onTap: () {
                              _cardData.websiteController.clear();
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding:
                                  const EdgeInsets.all(4.0),
                              child: Icon(Icons.clear, size: 22),
                            ),
                          ),
                        // Spacer
                        if (_cardData.websiteController.text.isNotEmpty)
                          const SizedBox(width: 4),

                        // Paste button (second)
                        InkWell(
                          onTap: _pasteWebsiteUrlFromClipboard,
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(Icons.content_paste,
                                size: 22, color: Colors.blue[700]),
                          ),
                        ),

                        // Spacer
                        const SizedBox(width: 4),

                        // Launch button (last)
                        InkWell(
                          onTap: _cardData.websiteController.text.isNotEmpty &&
                                  _isValidUrl(
                                      _cardData.websiteController.text.trim())
                              ? () => _launchUrl(
                                  _cardData.websiteController.text.trim())
                              : null,
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4.0, 4.0, 8.0, 4.0),
                            child: Icon(Icons.launch,
                                size: 22,
                                color: _cardData.websiteController.text
                                            .isNotEmpty &&
                                        _isValidUrl(_cardData
                                            .websiteController.text
                                            .trim())
                                    ? Colors.blue[700]
                                    : Colors.grey),
                          ),
                        ),
                      ],
                    )
                    // --- END MODIFICATION ---
                    ),
                keyboardType: TextInputType.url,
                validator: (value) {
                  if (value != null &&
                      value.isNotEmpty &&
                      !_isValidUrl(value)) {
                    return 'Please enter a valid URL (http/https)';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),

              // Notes field (using description/additionalNotes)
              TextFormField(
                controller: _cardData.notesController,
                decoration: InputDecoration(
                  labelText: 'Notes (optional)', // Or 'Description'
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.notes),
                  alignLabelWithHint: true,
                ),
                keyboardType: TextInputType.multiline,
                minLines: 3,
                maxLines: null,
              ),
              SizedBox(height: 24), // Space before buttons

              // --- Action Buttons ---
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop(), // Close without saving
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saveAndClose,
                    style: ElevatedButton.styleFrom(
                        // backgroundColor: Theme.of(context).primaryColor, // Optional styling
                        // foregroundColor: Colors.white,
                        ),
                    child: const Text('Save Changes'),
                  ),
                ],
              ),
              const SizedBox(height: 16), // Bottom padding
            ],
          ),
        ),
      ),
    );
  }

  // --- ADDED: Helper method to launch Generic URLs (if not already present) ---
  Future<void> _launchUrl(String urlString) async {
    // Ensure this method exists or add it if missing
    if (!_isValidUrl(urlString)) {
      print("Invalid URL, cannot launch: $urlString");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid URL entered')),
      );
      return;
    }
    Uri uri = Uri.parse(urlString);
    try {
      bool launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        print('Could not launch $uri');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open link')),
          );
        }
      }
    } catch (e) {
      print('Error launching URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening link: $e')),
        );
      }
    }
  }
  // --- END ADDED ---
}

// Helper extension for Location (if not already defined globally)
// Ensure this is consistent with the one in receive_share_screen.dart
// or move it to the Location model file.
extension LocationNameHelperModal on Location {
  String getPlaceName() {
    if (displayName != null &&
        displayName!.isNotEmpty &&
        !_containsCoordinates(displayName!)) {
      return displayName!;
    }
    if (address != null) {
      final parts = address!.split(',');
      if (parts.isNotEmpty) return parts.first.trim();
    }
    return 'Unnamed Location';
  }

  bool _containsCoordinates(String text) {
    final coordRegex =
        RegExp(r'-?\d+\.\d+ ?, ?-?\d+\.\d+'); // Basic coordinate pattern
    return coordRegex.hasMatch(text);
  }
}

// --- ADDED: Dialog for selecting 'Other' categories ---
class _OtherCategoriesSelectionDialog extends StatefulWidget {
  final ValueNotifier<List<UserCategory>> userCategoriesNotifier;
  final List<String> initiallySelectedIds;
  final String? primaryCategoryId; // To disable primary category
  final Future<bool?> Function() onEditCategories;
  final Future<void> Function() onAddCategory;

  const _OtherCategoriesSelectionDialog({
    required this.userCategoriesNotifier,
    required this.initiallySelectedIds,
    this.primaryCategoryId,
    required this.onEditCategories,
    required this.onAddCategory,
  });

  @override
  State<_OtherCategoriesSelectionDialog> createState() =>
      _OtherCategoriesSelectionDialogState();
}

class _OtherCategoriesSelectionDialogState
    extends State<_OtherCategoriesSelectionDialog> {
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<String>.from(widget.initiallySelectedIds);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Other Categories'),
      contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: ValueListenableBuilder<List<UserCategory>>(
          valueListenable: widget.userCategoriesNotifier,
          builder: (context, allCategories, child) {
            // Use the same ordering logic as the primary category dialog
            final uniqueCategoriesByName = <String, UserCategory>{};
            for (var category in allCategories) {
              uniqueCategoriesByName[category.name] = category;
            }
            final uniqueCategoryList = uniqueCategoriesByName.values.toList();
            
            // Filter out the primary category from the deduplicated list
            final availableCategories = uniqueCategoryList
                .where((cat) => cat.id != widget.primaryCategoryId)
                .toList();

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: availableCategories.length,
                    itemBuilder: (context, index) {
                      final category = availableCategories[index];
                      final bool isSelected = _selectedIds.contains(category.id);
                      return CheckboxListTile(
                        title: Text(category.name),
                        secondary: Text(category.icon, 
                            style: const TextStyle(fontSize: 20)),
                        value: isSelected,
                        onChanged: (bool? value) {
                          setState(() {
                            if (value == true) {
                              _selectedIds.add(category.id);
                            } else {
                              _selectedIds.remove(category.id);
                            }
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8.0, vertical: 8.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextButton.icon(
                        icon: Icon(Icons.add,
                            size: 20, color: Colors.blue[700]),
                        label: Text('Add New Category',
                            style: TextStyle(color: Colors.blue[700])),
                        onPressed: () async {
                          await widget.onAddCategory();
                          // The parent will handle reopening the dialog
                          Navigator.of(context).pop();
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
                        onPressed: () async {
                          final result = await widget.onEditCategories();
                          if (result == true) {
                            // Categories were changed, we need to refresh
                            // The parent will handle the refresh, we just need to close and reopen
                            Navigator.of(context).pop();
                            // The parent will reopen the dialog with updated categories
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
            );
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Cancel'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        TextButton(
          child: const Text('Confirm'),
          onPressed: () {
            Navigator.of(context).pop(_selectedIds.toList());
          },
        ),
      ],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}
// --- END ADDED ---
