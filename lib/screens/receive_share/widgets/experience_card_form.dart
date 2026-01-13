import 'package:flutter/material.dart';
import 'package:plendy/models/experience_card_data.dart'; // For ExperienceCardData
import 'package:plendy/models/experience.dart'
    show Location; // ONLY import Location
import 'package:plendy/models/user_category.dart'; // RENAMED Import
// For Location Picker
import 'package:plendy/services/experience_service.dart'; // ADDED for adding category
import 'package:plendy/services/google_maps_service.dart'; // If needed for location updates
// If needed
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
import 'package:plendy/widgets/privacy_toggle_button.dart';
import 'package:plendy/screens/receive_share/widgets/privacy_tooltip_icon.dart';
import 'package:plendy/config/colors.dart';
import 'package:plendy/utils/haptic_feedback.dart';
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
  String? newTitleFromCard, // ADDED for title submission
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
  final void Function(String cardId)? onYelpButtonTapped; // ADDED
  final VoidCallback? onEventSelect; // ADDED: Callback to show event selection dialog
  final String? selectedEventTitle; // ADDED: Title of currently selected event (for indicator)

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
    this.onYelpButtonTapped, // ADDED
    this.onEventSelect, // ADDED
    this.selectedEventTitle, // ADDED
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

  // --- ADDED: Function to show the other color categories selection dialog ---
  Future<void> _showOtherColorCategoriesSelectionDialog() async {
    FocusScope.of(context).unfocus();
    await Future.microtask(() {});

    final result = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return _OtherColorCategoriesSelectionDialog(
          userColorCategoriesNotifier: widget.userColorCategoriesNotifier,
          initiallySelectedIds: widget.cardData.selectedOtherColorCategoryIds,
          primaryColorCategoryId: widget.cardData.selectedColorCategoryId,
          onEditColorCategories: _handleEditColorCategories,
          onAddColorCategory: () async {
            await _handleAddColorCategory(selectAfterAdding: false);
            if (mounted) {
              _showOtherColorCategoriesSelectionDialog();
            }
          },
        );
      },
    );

    if (result is List<String>) {
      setState(() {
        widget.cardData.selectedOtherColorCategoryIds = result;
      });
      widget.onUpdate(refreshCategories: false);
    }
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

  String? _sharedOwnerLabel(String? ownerName) {
    if (ownerName == null) return null;
    final trimmed = ownerName.trim();
    if (trimmed.isEmpty) return null;
    return 'Shared by $trimmed';
  }

  @override
  void initState() {
    super.initState();
    // REMOVED: Initialize local state from widget.cardData
    // _isExpanded = widget.cardData.isExpanded;
    // _locationEnabled = widget.cardData.locationEnabled;

    // ADDED: Listener for focus changes on the title field
    widget.cardData.titleFocusNode.addListener(_handleTitleFocusChange);
  }

  // ADDED: Handler for title field focus changes
  void _handleTitleFocusChange() {
    if (!widget.cardData.titleFocusNode.hasFocus) {
      // Field lost focus, trigger update with current title for duplicate check
      final currentTitle = widget.cardData.titleController.text.trim();
      if (currentTitle.isNotEmpty) {
        // Only check if title is not empty
        print(
            "ExperienceCardForm: Title field lost focus. Current title: '$currentTitle'. Triggering update for potential duplicate check.");
        widget.onUpdate(
            refreshCategories: false, newTitleFromCard: currentTitle);
      }
    }
  }

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

    // ADDED: Remove focus listener
    widget.cardData.titleFocusNode.removeListener(_handleTitleFocusChange);
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
    print('DEBUG YELP: _launchYelpUrl() called');
    // Notify parent that Yelp button was tapped for this card
    widget.onYelpButtonTapped?.call(widget.cardData.id);

    String yelpUrlString = widget.cardData.yelpUrlController.text.trim();
    print('DEBUG YELP: yelpUrlString = "$yelpUrlString"');
    Uri uri;

    if (yelpUrlString.isNotEmpty) {
      // Current behavior: field is not empty
      if (_isValidUrl(yelpUrlString) &&
          (yelpUrlString.contains('yelp.com') ||
              yelpUrlString.contains('yelp.to'))) {
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
        print(
            'DEBUG YELP: Using title "$titleString" and address "$addressString"');
        String searchDesc = Uri.encodeComponent(titleString);
        // Add timestamp to force new navigation even if app is already open
        String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
        if (addressString != null && addressString.isNotEmpty) {
          // Both title and address are available
          String searchLoc = Uri.encodeComponent(addressString);
          uri = Uri.parse(
              'https://www.yelp.com/search?find_desc=$searchDesc&find_loc=$searchLoc&t=$timestamp');
          print('DEBUG YELP: Created URL with both title and location: $uri');
        } else {
          // Only title is available, address is not
          uri = Uri.parse(
              'https://www.yelp.com/search?find_desc=$searchDesc&t=$timestamp');
          print('DEBUG YELP: Created URL with title only: $uri');
        }
      } else {
        // Title is empty. Fallback to Yelp homepage.
        // (If title is empty, searching "along with title" is not possible)
        uri = Uri.parse('https://www.yelp.com');
        print('DEBUG YELP: Using fallback Yelp homepage: $uri');
      }
    }

    try {
      print('DEBUG YELP: About to launch URL: $uri');
      // For Yelp URLs, try multiple approaches to force new navigation
      bool launched = false;

      // Try Yelp app deep link for search URLs - cleaner navigation
      // Note: Yelp's Android app has a known issue where it shows a blank screen
      // when the deep link is used while the app is already open. This is a Yelp app bug.
      // The workaround is to close Yelp before tapping the button, or restart after blank screen.
      if (uri.toString().contains('yelp.com/search')) {
        final String? terms = uri.queryParameters['find_desc'];
        final String? location = uri.queryParameters['find_loc'];
        if (terms != null && terms.isNotEmpty) {
          final String t = Uri.encodeComponent(terms);
          final String l = location != null && location.isNotEmpty
              ? '&location=${Uri.encodeComponent(location)}'
              : '';
          final Uri deepLink = Uri.parse('yelp:///search?terms=$t$l');
          print('DEBUG YELP: Using deep link: $deepLink');
          try {
            // Try launching without canLaunchUrl check first
            launched = await launchUrl(deepLink,
                mode: LaunchMode.externalApplication);
            print('DEBUG YELP: Deep link launch result: $launched');
            if (launched) {
              print('DEBUG YELP: Successfully launched via deep link');
              return; // Successfully launched deep link; stop here
            }
          } catch (e) {
            print('DEBUG YELP: Error launching deep link: $e');
          }
        }
      }

      // Fallback: Launch the HTTPS URL - force external browser, not in-app
      print('DEBUG YELP: Fallback to HTTPS URL: $uri');
      launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank', // For web platform
      );
      print('DEBUG YELP: HTTPS URL launch result: $launched');

      if (!launched) {
        print('DEBUG YELP: All launch attempts failed for $uri');
        // Optionally show a snackbar to the user
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open Yelp link/search')),
          );
        }
      } else {
        print('DEBUG YELP: Successfully launched URL: $uri');
      }
    } catch (e) {
      print('DEBUG YELP: Error launching URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening link: $e')),
        );
      }
    }
  }

  // --- ADDED: Method to launch Google Maps at location ---
  Future<void> _launchMapLocation() async {
    Location? location = widget.cardData.selectedLocation;
    String mapUrl;

    if (location != null && location.latitude != 0.0 && location.longitude != 0.0) {
      // Use the Google Maps search API with coordinates
      final lat = location.latitude;
      final lng = location.longitude;
      final placeName = location.displayName ?? location.address ?? 'Selected Location';
      if (location.placeId != null && location.placeId!.isNotEmpty) {
        mapUrl = 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(placeName)}&query_place_id=${location.placeId}';
      } else {
        mapUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
      }
    } else {
      // Fallback to general Google Maps if no location
      mapUrl = 'https://www.google.com/maps';
    }

    final Uri mapUri = Uri.parse(mapUrl);
    if (!await launchUrl(mapUri, mode: LaunchMode.externalApplication)) {
      print('Could not launch map location.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open map location.')),
        );
      }
    }
  }
  // --- END ADDED ---

  // --- ADDED: Method to launch Ticketmaster search ---
  Future<void> _launchTicketmasterSearch() async {
    // Get the title to search for
    String searchTerm = widget.cardData.titleController.text.trim();
    
    // If no title, try using location name
    if (searchTerm.isEmpty && widget.cardData.selectedLocation != null) {
      searchTerm = widget.cardData.selectedLocation!.displayName ?? '';
    }
    
    String ticketmasterUrl;
    if (searchTerm.isNotEmpty) {
      // Search Ticketmaster for the event
      final searchQuery = Uri.encodeComponent(searchTerm);
      ticketmasterUrl = 'https://www.ticketmaster.com/search?q=$searchQuery';
    } else {
      // Fallback to Ticketmaster homepage
      ticketmasterUrl = 'https://www.ticketmaster.com';
    }

    final Uri uri = Uri.parse(ticketmasterUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      print('Could not launch Ticketmaster search.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Ticketmaster.')),
        );
      }
    }
  }
  // --- END ADDED ---

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
  Future<void> _handleAddCategory({bool selectAfterAdding = true}) async {
    FocusScope.of(context).unfocus();
    await Future.microtask(() {});
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

      // Always just refresh the list without passing newCategoryName
      // This prevents the parent from trying to select the category
      widget.onUpdate(refreshCategories: true);

      // Handle selection locally within the form component
      if (selectAfterAdding) {
        // Wait a bit for the refresh to complete, then select the new category
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          setState(() {
            widget.cardData.selectedCategoryId = newCategory.id;
          });
        }
      }
    }
  }

  // UPDATED: Method to handle editing categories
  Future<bool?> _handleEditCategories() async {
    FocusScope.of(context).unfocus();
    await Future.microtask(() {});
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
    print(
        "EditCategoriesModal closed, categoriesChanged: $categoriesChanged (Text Categories)");

    if (categoriesChanged == true && mounted) {
      print("Categories potentially changed in Edit modal, refreshing list.");
      // Notify parent to just refresh the list
      widget.onUpdate(refreshCategories: true);
    }
    return categoriesChanged; // ADDED: Return the result
  }

  // --- UPDATED: Function to show the category selection dialog ---
  Future<void> _showCategorieselectionDialog() async {
    FocusScope.of(context).unfocus();
    await Future.microtask(() {});

    // Note: _userCategoriesNotifier.value will be used by ValueListenableBuilder inside StatefulBuilder

    final searchController = TextEditingController();

    final String? selectedValue = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        String searchQuery = '';
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
                final uniqueCategoryList =
                    uniqueCategoriesByName.values.toList();

                // Filter categories based on search query
                final filteredCategories = searchQuery.isEmpty
                    ? uniqueCategoryList
                    : uniqueCategoryList
                        .where((cat) => cat.name
                            .toLowerCase()
                            .contains(searchQuery.toLowerCase()))
                        .toList();

                return Dialog(
                  backgroundColor: Colors.white,
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
                            'Select Primary Category',
                            style: Theme.of(stfContext).textTheme.titleLarge,
                          ),
                        ),
                        // Search bar
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: TextField(
                            controller: searchController,
                            decoration: InputDecoration(
                              hintText: 'Search categories...',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              suffixIcon: searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 20),
                                      onPressed: () {
                                        searchController.clear();
                                        stfSetState(() {
                                          searchQuery = '';
                                        });
                                      },
                                    )
                                  : null,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              filled: true,
                              fillColor: AppColors.backgroundColorDark,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppColors.backgroundColorDark,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppColors.backgroundColorDark,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppColors.backgroundColorDark,
                                  width: 2,
                                ),
                              ),
                            ),
                            onChanged: (value) {
                              stfSetState(() {
                                searchQuery = value;
                              });
                            },
                          ),
                        ),
                        Expanded(
                          child: filteredCategories.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Text(
                                      'No categories found',
                                      style: TextStyle(color: Colors.grey[600]),
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: filteredCategories.length,
                                  itemBuilder: (context, index) {
                                    final category = filteredCategories[index];
                                    final bool isSelected = category.id ==
                                        widget.cardData.selectedCategoryId;
                                    final sharedLabel = _sharedOwnerLabel(
                                        category.sharedOwnerDisplayName);
                                    return ListTile(
                                      leading: Text(category.icon,
                                          style: const TextStyle(fontSize: 20)),
                                      title: Text(category.name),
                                      subtitle: sharedLabel != null
                                          ? Text(
                                              sharedLabel,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(color: Colors.grey[600]),
                                            )
                                          : null,
                                      trailing: isSelected
                                          ? const Icon(Icons.check,
                                              color: Colors.blue)
                                          : null,
                                      onTap: withHeavyTap(() {
                                        FocusScope.of(dialogContext).unfocus();
                                        Navigator.pop(dialogContext, category.id);
                                      }),
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
                                onPressed: () {
                                  FocusScope.of(dialogContext).unfocus();
                                  Navigator.pop(
                                      dialogContext, _dialogActionAdd);
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
                                    style:
                                        TextStyle(color: Colors.orange[700])),
                                onPressed: () async {
                                  final bool? categoriesActuallyChanged =
                                      await _handleEditCategories();
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

    // Note: searchController will be garbage collected - don't dispose synchronously
    // as animations may still be running after unfocus

    // --- Handle the dialog result --- (This part remains largely the same)
    if (selectedValue != null) {
      if (selectedValue == _dialogActionAdd) {
        _handleAddCategory();
      } else if (selectedValue == _dialogActionEdit) {
        // This case is less likely to be hit if we don't pop from edit action anymore unless intended
        // However, _handleEditCategories already calls onUpdate which should refresh the parent.
        print(
            "CategorySelectionDialog popped with _dialogActionEdit, parent will refresh categories via onUpdate.");
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
    final matchingCategory =
        widget.userColorCategoriesNotifier.value.firstWhere(
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
  Future<void> _handleAddColorCategory({bool selectAfterAdding = true}) async {
    FocusScope.of(context).unfocus();
    await Future.microtask(() {});
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
      if (selectAfterAdding) {
        // REMOVED setState
        // setState(() {
        widget.cardData.selectedColorCategoryId = newCategory.id;
        // });
      }
    }
  }

  // --- ADDED: Method to handle editing color categories ---
  Future<bool?> _handleEditColorCategories() async {
    FocusScope.of(context).unfocus();
    await Future.microtask(() {});

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
    print(
        "EditColorCategoriesModal closed, categoriesChanged: $categoriesChanged (Color Categories)");

    if (categoriesChanged == true && mounted) {
      print(
          "Color Categories potentially changed in Edit modal, refreshing list.");
      widget.onUpdate(refreshCategories: true);
    }
    return categoriesChanged; // ADDED: Return the result
  }

  // --- ADDED: Function to show the color category selection dialog ---
  Future<void> _showColorCategorySelectionDialog() async {
    FocusScope.of(context).unfocus();
    await Future.microtask(() {});

    final searchController = TextEditingController();

    final String? selectedValue = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        String searchQuery = '';
        // Use StatefulBuilder to allow the dialog's content to rebuild when notifiers change
        return StatefulBuilder(
          builder: (stfContext, stfSetState) {
            // Listen to the notifier for color category list changes
            return ValueListenableBuilder<List<ColorCategory>>(
              valueListenable: widget.userColorCategoriesNotifier,
              builder: (context, currentColorCategories, child) {
                final List<ColorCategory> categoriesToShow =
                    List.from(currentColorCategories);

                // Filter categories based on search query
                final filteredCategories = searchQuery.isEmpty
                    ? categoriesToShow
                    : categoriesToShow
                        .where((cat) => cat.name
                            .toLowerCase()
                            .contains(searchQuery.toLowerCase()))
                        .toList();

                return Dialog(
                  backgroundColor: Colors.white,
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
                        // Search bar
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: TextField(
                            controller: searchController,
                            decoration: InputDecoration(
                              hintText: 'Search color categories...',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              suffixIcon: searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 20),
                                      onPressed: () {
                                        searchController.clear();
                                        stfSetState(() {
                                          searchQuery = '';
                                        });
                                      },
                                    )
                                  : null,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              filled: true,
                              fillColor: AppColors.backgroundColorDark,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppColors.backgroundColorDark,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppColors.backgroundColorDark,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppColors.backgroundColorDark,
                                  width: 2,
                                ),
                              ),
                            ),
                            onChanged: (value) {
                              stfSetState(() {
                                searchQuery = value;
                              });
                            },
                          ),
                        ),
                        Expanded(
                          child: filteredCategories.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Text(
                                      'No color categories found',
                                      style: TextStyle(color: Colors.grey[600]),
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: filteredCategories.length,
                                  itemBuilder: (context, index) {
                                    final category = filteredCategories[index];
                                    final bool isSelected = category.id ==
                                        widget.cardData.selectedColorCategoryId;
                                    final sharedLabel = _sharedOwnerLabel(
                                        category.sharedOwnerDisplayName);
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
                                      subtitle: sharedLabel != null
                                          ? Text(
                                              sharedLabel,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(color: Colors.grey[600]),
                                            )
                                          : null,
                                      trailing: isSelected
                                          ? const Icon(Icons.check,
                                              color: Colors.blue)
                                          : null,
                                      onTap: withHeavyTap(() {
                                        FocusScope.of(dialogContext).unfocus();
                                        Navigator.pop(dialogContext, category.id);
                                      }),
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
                                  FocusScope.of(dialogContext).unfocus();
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
                                    style:
                                        TextStyle(color: Colors.orange[700])),
                                onPressed: () async {
                                  final bool? categoriesActuallyChanged =
                                      await _handleEditColorCategories();
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

    // Note: searchController will be garbage collected - don't dispose synchronously
    // as animations may still be running after unfocus

    // Handle the dialog result
    if (selectedValue != null) {
      if (selectedValue == _addColorCategoryValue) {
        _handleAddColorCategory();
      } else if (selectedValue == _editColorCategoriesValue) {
        // This case is less likely to be hit if we don't pop from edit action anymore unless intended
        print(
            "ColorCategorySelectionDialog popped with _editColorCategoriesValue, parent will refresh categories via onUpdate.");
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

  // --- ADDED: Function to show the other categories selection dialog ---
  Future<void> _showOtherCategoriesSelectionDialog() async {
    FocusScope.of(context).unfocus();
    await Future.microtask(() {});

    // This is the key change. We are now calling a modified _handleAddCategory that
    // does not automatically select the new category.
    final result = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false, // User must press button
      builder: (BuildContext dialogContext) {
        return _OtherCategoriesSelectionDialog(
          userCategoriesNotifier: widget.userCategoriesNotifier,
          initiallySelectedIds: widget.cardData.selectedOtherCategoryIds,
          primaryCategoryId: widget.cardData.selectedCategoryId,
          onEditCategories: _handleEditCategories,
          onAddCategory: () async {
            await _handleAddCategory(selectAfterAdding: false);
            // After adding the category, reopen this dialog
            if (mounted) {
              _showOtherCategoriesSelectionDialog();
            }
          },
        );
      },
    );

    if (result is List<String>) {
      setState(() {
        widget.cardData.selectedOtherCategoryIds = result;
      });
      widget.onUpdate(refreshCategories: false);
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
    final websiteController = widget.cardData.websiteController;
    final titleFocusNode = widget.cardData.titleFocusNode;
    final currentLocation = widget.cardData.selectedLocation;

    // print("FORM_DEBUG (${widget.cardData.id}): Build method running.");
    // print("FORM_DEBUG (${widget.cardData.id}): widget.cardData.selectedLocation: ${currentLocation?.displayName}");
    // print("FORM_DEBUG (${widget.cardData.id}): websiteController text: '${websiteController.text}'");

    return GestureDetector(
      onTap: withHeavyTap(() {
        FocusManager.instance.primaryFocus?.unfocus();
      }),
      child: Container(
        margin: EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: widget.cardData.backgroundColor,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              spreadRadius: 2,
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              spreadRadius: 1,
              blurRadius: 4,
              offset: Offset(0, -2),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              spreadRadius: 1,
              blurRadius: 4,
              offset: Offset(-2, 0),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              spreadRadius: 1,
              blurRadius: 4,
              offset: Offset(2, 0),
            ),
          ],
        ),
        child: Form(
          key: widget.formKey, // Use the passed form key
          child: Column(
            children: [
              // Header row with expand/collapse and delete functionality
              InkWell(
                onTap: withHeavyTap(() {
                  setState(() {
                    widget.cardData.isExpanded = !widget.cardData.isExpanded;
                    // Unfocus any active fields when collapsing
                    if (!widget.cardData.isExpanded) {
                      FocusManager.instance.primaryFocus?.unfocus();
                    }
                  });
                }),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        widget.cardData
                                .isExpanded // Read directly from cardData
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: Colors.black,
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
                          icon: Icon(Icons.delete_outline,
                              color: Colors.red[400]),
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
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PrivacyToggleButton(
                              isPrivate: widget.cardData.isPrivate,
                              onPressed: () {
                                setState(() {
                                  widget.cardData.isPrivate =
                                      !widget.cardData.isPrivate;
                                });
                              },
                            ),
                            const SizedBox(width: 6),
                            PrivacyTooltipIcon(
                              message:
                                  'Public experiences will show up in your public profile page (not yet implemented) to be viewed by others. Private experiences will only be visible to you.',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.max,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              flex: 1,
                              child: OutlinedButton.icon(
                                icon: Icon(
                                  widget.selectedEventTitle != null
                                      ? Icons.check_circle
                                      : Icons.event,
                                  color: widget.selectedEventTitle != null
                                      ? AppColors.sage
                                      : null,
                                ),
                                label: Text(
                                  'Events',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onPressed: widget.onEventSelect,
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: widget.selectedEventTitle != null
                                      ? AppColors.sage.withOpacity(0.1)
                                      : Colors.white,
                                  foregroundColor: widget.selectedEventTitle != null
                                      ? AppColors.sage
                                      : Theme.of(context).primaryColor,
                                  side: BorderSide(
                                    color: widget.selectedEventTitle != null
                                        ? AppColors.sage
                                        : Theme.of(context).primaryColor,
                                    width: 2.0,
                                  ),
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: OutlinedButton.icon(
                                icon: Icon(Icons.bookmark_outline),
                                label: Text(
                                  'Choose a saved experience',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onPressed: () => widget
                                    .onSelectSavedExperience(widget.cardData),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor:
                                      Theme.of(context).primaryColor,
                                  side: BorderSide(
                                    color: Theme.of(context).primaryColor,
                                    width: 2.0,
                                  ),
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Location selection with preview
                      ValueListenableBuilder<bool>(
                        valueListenable: widget.cardData.locationEnabled,
                        builder: (context, isEnabled, child) {
                          final bool isLocationLoading =
                              widget.cardData.isSelectingLocation;
                          return GestureDetector(
                            // Call the parent's location selection logic
                            onTap: withHeavyTap(isEnabled && !isLocationLoading
                                ? () => widget.onLocationSelect(widget.cardData)
                                : null),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color:
                                        isEnabled // Use isEnabled from builder
                                            ? AppColors.backgroundColorDark
                                            : AppColors.backgroundColorDark),
                                borderRadius: BorderRadius.circular(4),
                                color: Colors.white,
                              ),
                              padding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              child: Row(
                                children: [
                                  Icon(Icons.location_on,
                                      color:
                                          isEnabled // Use isEnabled from builder
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
                                                  color:
                                                      isEnabled // Use isEnabled from builder
                                                          ? Colors.black
                                                          : Colors.grey[500],
                                                ),
                                              ),
                                              // Address
                                              if (currentLocation.address !=
                                                  null)
                                                Text(
                                                  currentLocation.address!,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        isEnabled // Use isEnabled from builder
                                                            ? Colors.black87
                                                            : Colors.grey[500],
                                                  ),
                                                  maxLines:
                                                      1, // Limit address lines
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                            ],
                                          )
                                        : Text(
                                            'Select location',
                                            style: TextStyle(
                                                color:
                                                    isEnabled // Use isEnabled from builder
                                                        ? Colors.grey[600]
                                                        : Colors.grey[400]),
                                          ),
                                  ),
                                  if (isLocationLoading)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8.0),
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation(
                                            Theme.of(context).primaryColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                  // Toggle switch inside the location field
                                  Transform.scale(
                                    scale: 0.8,
                                    child: Switch(
                                      value:
                                          isEnabled, // Use isEnabled from builder
                                      onChanged: (value) {
                                        widget.cardData.locationEnabled.value =
                                            value; // Update model directly
                                        // No widget.onUpdate() needed here for this toggle's visual state
                                      },
                                      activeThumbColor:
                                          const Color(0xFF2F6F6D),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      SizedBox(height: 16),

                      // Experience title
                      TextFormField(
                        controller:
                            titleController, // Use controller from widget
                        focusNode: titleFocusNode, // Use focus node from widget
                        decoration: InputDecoration(
                          labelText: 'Experience Title',
                          hintText: 'Enter title',
                          border: OutlineInputBorder(),
                          enabledBorder: const OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.backgroundColorDark,
                            ),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.backgroundColorDark,
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.white,
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
                          // Notify parent for UI updates (like header title) as user types,
                          // but don't trigger duplicate check on every keystroke.
                          widget.onUpdate(refreshCategories: false);
                        },
                        onFieldSubmitted: (value) {
                          // When field is submitted (e.g., user presses done/next on keyboard),
                          // trigger onUpdate with the new title to initiate duplicate check.
                          widget.onUpdate(
                              refreshCategories: false,
                              newTitleFromCard: value.trim());
                        },
                      ),
                      SizedBox(height: 8),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'For reference',
                            textAlign: TextAlign.right,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: Colors.black87),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: withHeavyTap(_launchYelpUrl),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Icon(
                                FontAwesomeIcons.yelp,
                                size: 22,
                                color: Colors.red[700],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: withHeavyTap(_launchMapLocation),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Icon(
                                Icons.map_outlined,
                                size: 22,
                                color: const Color(0xFF6D8B74),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: withHeavyTap(_launchTicketmasterSearch),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.asset(
                                  'assets/icon/misc/ticketmaster_logo.png',
                                  height: 22,
                                  width: 22,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Icon(
                                      Icons.confirmation_number,
                                      size: 22,
                                      color: const Color(0xFF026CDF),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),

                      // --- REPLACEMENT Dropdown with a Button wrapped in ValueListenableBuilder ---
                      Text('Primary Category',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                  color: Colors
                                      .grey[600])), // Label like text field
                      const SizedBox(height: 4),
                      ValueListenableBuilder<List<UserCategory>>(
                        valueListenable: widget.userCategoriesNotifier,
                        builder: (context, currentCategoryList, child) {
                          // Note: currentCategoryList is available if needed, but button display
                          // mainly depends on widget.cardData.selectedcategory
                          UserCategory? selectedCategoryObject;
                          if (widget.cardData.selectedCategoryId != null) {
                            try {
                              selectedCategoryObject =
                                  currentCategoryList.firstWhere((cat) =>
                                      cat.id ==
                                      widget.cardData.selectedCategoryId);
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
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    8.0), // Match field style
                              ),
                              side: BorderSide(
                                  color: AppColors
                                      .backgroundColorDark), // Match field border
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
                                      selectedCategoryObject?.name ??
                                          'Select Primary Category',
                                      style: TextStyle(
                                        // Ensure text color matches default button text color or form field color
                                        color: selectedCategoryObject != null
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

                      // --- ADDED: Other Categories Selection ---
                      ValueListenableBuilder<List<UserCategory>>(
                        valueListenable: widget.userCategoriesNotifier,
                        builder: (context, allCategories, child) {
                          final selectedCategories = allCategories
                              .where((cat) => widget
                                  .cardData.selectedOtherCategoryIds
                                  .contains(cat.id))
                              .toList();
                          final hasSelected = selectedCategories.isNotEmpty;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(height: hasSelected ? 16 : 1),
                              if (hasSelected) ...[
                                Text('Other Categories',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: Colors.grey[600])),
                                const SizedBox(height: 4),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12.0),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: AppColors.backgroundColorDark),
                                    borderRadius: BorderRadius.circular(8.0),
                                    color: Colors.white,
                                  ),
                                  child: Wrap(
                                    spacing: 6.0,
                                    runSpacing: 6.0,
                                    children: selectedCategories.map((category) {
                                      return Chip(
                                        backgroundColor: Colors.white,
                                        avatar: Text(category.icon,
                                            style:
                                                const TextStyle(fontSize: 14)),
                                        label: Text(category.name),
                                        onDeleted: () {
                                          setState(() {
                                            widget.cardData
                                                .selectedOtherCategoryIds
                                                .remove(category.id);
                                          });
                                          widget.onUpdate(
                                              refreshCategories: false);
                                        },
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 0),
                                        visualDensity: VisualDensity.compact,
                                        labelPadding: const EdgeInsets.symmetric(
                                            horizontal: 4.0),
                                        deleteIconColor: Colors.grey[600],
                                        deleteButtonTooltipMessage:
                                            'Remove category',
                                      );
                                    }).toList(),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              Center(
                                child: TextButton.icon(
                                  icon: const Icon(Icons.add, size: 20),
                                  label: const Text('Assign more categories'),
                                  onPressed: _showOtherCategoriesSelectionDialog,
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      // --- END ADDED ---

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
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8.0)),
                              side: BorderSide(
                                  color: AppColors.backgroundColorDark),
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
                                        color: widget.cardData
                                                    .selectedColorCategoryId !=
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

                      // --- ADDED: Other Color Categories Selection ---
                      ValueListenableBuilder<List<ColorCategory>>(
                        valueListenable: widget.userColorCategoriesNotifier,
                        builder: (context, allColorCategories, child) {
                          final selectedColorCategories = allColorCategories
                              .where((cat) => widget.cardData
                                  .selectedOtherColorCategoryIds
                                  .contains(cat.id))
                              .toList();
                          final hasSelected = selectedColorCategories.isNotEmpty;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(height: hasSelected ? 16 : 1),
                              if (hasSelected) ...[
                                Text('Other Color Categories',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: Colors.grey[600])),
                                const SizedBox(height: 4),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12.0),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: AppColors.backgroundColorDark),
                                    borderRadius: BorderRadius.circular(8.0),
                                    color: Colors.white,
                                  ),
                                  child: Wrap(
                                    spacing: 6.0,
                                    runSpacing: 6.0,
                                    children:
                                        selectedColorCategories.map((category) {
                                      return Chip(
                                        backgroundColor: Colors.white,
                                        avatar: Container(
                                          width: 18,
                                          height: 18,
                                          decoration: BoxDecoration(
                                            color: category.color,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        label: Text(category.name),
                                        onDeleted: () {
                                          setState(() {
                                            widget.cardData
                                                .selectedOtherColorCategoryIds
                                                .remove(category.id);
                                          });
                                          widget.onUpdate(
                                              refreshCategories: false);
                                        },
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 0),
                                        visualDensity: VisualDensity.compact,
                                        labelPadding: const EdgeInsets.symmetric(
                                            horizontal: 4.0),
                                        deleteIconColor: Colors.grey[600],
                                        deleteButtonTooltipMessage:
                                            'Remove color category',
                                      );
                                    }).toList(),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              Center(
                                child: TextButton.icon(
                                  icon: const Icon(Icons.add, size: 20),
                                  label: const Text(
                                      'Assign more color categories'),
                                  onPressed:
                                      _showOtherColorCategoriesSelectionDialog,
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      // --- END ADDED ---

                      SizedBox(height: 16),

                      // Official website
                      TextFormField(
                        controller:
                            websiteController, // Use controller from widget
                        decoration: InputDecoration(
                          labelText: 'Official Website (optional)',
                          hintText: 'https://...',
                          border: OutlineInputBorder(),
                          enabledBorder: const OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.backgroundColorDark,
                            ),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.backgroundColorDark,
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.white,
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
                              if (websiteController.text.isNotEmpty)
                                InkWell(
                                  onTap: withHeavyTap(() {
                                    websiteController.clear();
                                    widget.onUpdate(refreshCategories: false);
                                  }),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Icon(Icons.clear, size: 22),
                                  ),
                                ),
                              // Spacer
                              if (websiteController.text.isNotEmpty)
                                const SizedBox(width: 4),

                              // Paste button (second)
                              InkWell(
                                onTap: withHeavyTap(_pasteWebsiteUrlFromClipboard),
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: const Icon(Icons.content_paste,
                                      size: 22, color: Color(0xFF1F2A44)),
                                ),
                              ),

                              // Spacer
                              const SizedBox(width: 4),

                              // Launch button (last)
                              InkWell(
                                onTap: withHeavyTap(websiteController.text.isNotEmpty &&
                                        _isValidUrl(
                                            websiteController.text.trim())
                                    ? () async {
                                        String urlString =
                                            websiteController.text.trim();
                                        // No need to re-validate here, already checked in condition
                                        try {
                                          await launchUrl(
                                            Uri.parse(urlString),
                                            mode:
                                                LaunchMode.externalApplication,
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
                                    : null),
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      4.0, 4.0, 8.0, 4.0),
                                  child: Icon(Icons.launch, // Use launch icon
                                      size: 22,
                                      color: websiteController
                                                  .text.isNotEmpty &&
                                              _isValidUrl(
                                                  websiteController.text.trim())
                                          ? AppColors.teal
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
                          enabledBorder: const OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.backgroundColorDark,
                            ),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.backgroundColorDark,
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          prefixIcon: Icon(Icons.notes),
                          alignLabelWithHint:
                              true, // Align label top-left for multi-line
                          suffixIcon: widget
                                  .cardData.notesController.text.isNotEmpty
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
      ),
    );
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  String? _sharedOwnerLabel(String? ownerName) {
    if (ownerName == null) return null;
    final trimmed = ownerName.trim();
    if (trimmed.isEmpty) return null;
    return 'Shared by $trimmed';
  }

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<String>.from(widget.initiallySelectedIds);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
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

            // Filter based on search query
            final filteredCategories = _searchQuery.isEmpty
                ? availableCategories
                : availableCategories
                    .where((cat) => cat.name
                        .toLowerCase()
                        .contains(_searchQuery.toLowerCase()))
                    .toList();

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search categories...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: AppColors.backgroundColorDark,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.backgroundColorDark,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.backgroundColorDark,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.backgroundColorDark,
                          width: 2,
                        ),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
                Expanded(
                  child: filteredCategories.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              'No categories found',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filteredCategories.length,
                          itemBuilder: (context, index) {
                            final category = filteredCategories[index];
                            final bool isSelected =
                                _selectedIds.contains(category.id);
                            final sharedLabel =
                                _sharedOwnerLabel(category.sharedOwnerDisplayName);
                            return CheckboxListTile(
                              title: Text(category.name),
                              subtitle: sharedLabel != null
                                  ? Text(
                                      sharedLabel,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.grey[600]),
                                    )
                                  : null,
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
                        icon:
                            Icon(Icons.add, size: 20, color: Colors.blue[700]),
                        label: Text('Add New Category',
                            style: TextStyle(color: Colors.blue[700])),
                        onPressed: () async {
                          FocusScope.of(context).unfocus();
                          Navigator.of(context).pop();
                          await widget.onAddCategory();
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
                          await widget.onEditCategories();
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
            FocusScope.of(context).unfocus();
            Navigator.of(context).pop();
          },
        ),
        TextButton(
          child: const Text('Confirm'),
          onPressed: () {
            FocusScope.of(context).unfocus();
            Navigator.of(context).pop(_selectedIds.toList());
          },
        ),
      ],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}
// --- END ADDED ---

// --- ADDED: Dialog for selecting 'Other Color' categories ---
class _OtherColorCategoriesSelectionDialog extends StatefulWidget {
  final ValueNotifier<List<ColorCategory>> userColorCategoriesNotifier;
  final List<String> initiallySelectedIds;
  final String? primaryColorCategoryId;
  final Future<bool?> Function() onEditColorCategories;
  final Future<void> Function() onAddColorCategory;

  const _OtherColorCategoriesSelectionDialog({
    required this.userColorCategoriesNotifier,
    required this.initiallySelectedIds,
    this.primaryColorCategoryId,
    required this.onEditColorCategories,
    required this.onAddColorCategory,
  });

  @override
  State<_OtherColorCategoriesSelectionDialog> createState() =>
      _OtherColorCategoriesSelectionDialogState();
}

class _OtherColorCategoriesSelectionDialogState
    extends State<_OtherColorCategoriesSelectionDialog> {
  late Set<String> _selectedIds;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  String? _sharedOwnerLabel(String? ownerName) {
    if (ownerName == null) return null;
    final trimmed = ownerName.trim();
    if (trimmed.isEmpty) return null;
    return 'Shared by $trimmed';
  }

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<String>.from(widget.initiallySelectedIds);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Select Other Color Categories'),
      contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: ValueListenableBuilder<List<ColorCategory>>(
          valueListenable: widget.userColorCategoriesNotifier,
          builder: (context, allColorCategories, child) {
            final availableCategories = allColorCategories
                .where((cat) => cat.id != widget.primaryColorCategoryId)
                .toList();

            // Filter based on search query
            final filteredCategories = _searchQuery.isEmpty
                ? availableCategories
                : availableCategories
                    .where((cat) => cat.name
                        .toLowerCase()
                        .contains(_searchQuery.toLowerCase()))
                    .toList();

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search color categories...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: AppColors.backgroundColorDark,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.backgroundColorDark,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.backgroundColorDark,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.backgroundColorDark,
                          width: 2,
                        ),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
                Expanded(
                  child: filteredCategories.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              'No color categories found',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filteredCategories.length,
                          itemBuilder: (context, index) {
                            final category = filteredCategories[index];
                            final bool isSelected =
                                _selectedIds.contains(category.id);
                            final sharedLabel =
                                _sharedOwnerLabel(category.sharedOwnerDisplayName);
                            return CheckboxListTile(
                              title: Text(category.name),
                              subtitle: sharedLabel != null
                                  ? Text(
                                      sharedLabel,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.grey[600]),
                                    )
                                  : null,
                              secondary: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: category.color,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.grey.shade400),
                                ),
                              ),
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
                        icon:
                            Icon(Icons.add, size: 20, color: Colors.blue[700]),
                        label: Text('Add New Color Category',
                            style: TextStyle(color: Colors.blue[700])),
                        onPressed: () async {
                          FocusScope.of(context).unfocus();
                          Navigator.of(context).pop();
                          await widget.onAddColorCategory();
                        },
                        style: TextButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12)),
                      ),
                      TextButton.icon(
                        icon: Icon(Icons.edit,
                            size: 20, color: Colors.orange[700]),
                        label: Text('Edit Color Categories',
                            style: TextStyle(color: Colors.orange[700])),
                        onPressed: () async {
                          await widget.onEditColorCategories();
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
            FocusScope.of(context).unfocus();
            Navigator.of(context).pop();
          },
        ),
        TextButton(
          child: const Text('Confirm'),
          onPressed: () {
            FocusScope.of(context).unfocus();
            Navigator.of(context).pop(_selectedIds.toList());
          },
        ),
      ],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}
// --- END ADDED ---
