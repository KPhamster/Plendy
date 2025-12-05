import 'package:flutter/material.dart';
import 'package:plendy/models/experience.dart';
import 'package:plendy/models/user_category.dart';
import 'package:plendy/models/experience_card_data.dart';
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
import 'package:plendy/services/category_ordering_service.dart';
import 'package:collection/collection.dart'; // ADDED: Import for firstWhereOrNull
import 'package:plendy/screens/location_picker_screen.dart'; // ADDED: Import for LocationPickerScreen
import 'package:firebase_auth/firebase_auth.dart';
import 'package:plendy/models/share_permission.dart';
import 'package:plendy/models/enums/share_enums.dart';
import 'package:plendy/widgets/privacy_toggle_button.dart';

class EditExperienceModal extends StatefulWidget {
  final Experience experience;
  final List<UserCategory> userCategories;
  final List<ColorCategory> userColorCategories;
  final bool requireCategorySelection;
  final ScaffoldMessengerState? scaffoldMessenger;
  final bool
      enableDuplicatePrompt; // When true, check duplicate on open and allow switching to existing

  const EditExperienceModal({
    super.key,
    required this.experience,
    required this.userCategories,
    required this.userColorCategories,
    this.requireCategorySelection = false,
    this.scaffoldMessenger,
    this.enableDuplicatePrompt = false,
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
  final CategoryOrderingService _categoryOrderingService =
      CategoryOrderingService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Map<String, SharePermission> _editableCategoryPermissions = {};
  List<UserCategory> _currentUserCategories = [];
  List<ColorCategory> _currentColorCategories = [];
  bool _isLoadingCategories = true; // Loading indicator for categories

  // --- ADDED: ValueNotifiers for reactive category updates ---
  late ValueNotifier<List<UserCategory>> _userCategoriesNotifier;
  late ValueNotifier<List<ColorCategory>> _colorCategoriesNotifier;
  // --- END ADDED ---

  // --- ADDED Color Category constants ---
  static const String _addColorCategoryValue = '__add_new_color_category__';
  static const String _editColorCategoriesValue = '__edit_color_categories__';
  // --- END ADDED ---

  final GlobalKey<ScaffoldMessengerState> _localMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  bool get _requiresCategorySelection => widget.requireCategorySelection;
  bool get _hasPrimaryCategory =>
      _cardData.selectedCategoryId?.isNotEmpty ?? false;
  bool get _hasColorCategory =>
      _cardData.selectedColorCategoryId?.isNotEmpty ?? false;
  bool get _isSaveEnabled =>
      !_requiresCategorySelection || (_hasPrimaryCategory && _hasColorCategory);

  void _populateNotesController(Experience source) {
    final String? notes = source.additionalNotes;
    _cardData.notesController.text =
        (notes != null && notes.isNotEmpty) ? notes : '';
  }

  String _buildCategoryWarningMessage() {
    if (_hasPrimaryCategory && _hasColorCategory) {
      return '';
    }
    if (!_hasPrimaryCategory && !_hasColorCategory) {
      return 'Select both a primary category and a color category before saving.';
    }
    if (!_hasPrimaryCategory) {
      return 'Select a primary category before saving.';
    }
    return 'Select a color category before saving.';
  }

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
    _populateNotesController(widget.experience);
    _cardData.selectedCategoryId = widget.experience.categoryId;
    _cardData.selectedColorCategoryId = widget.experience.colorCategoryId;
    _cardData.selectedOtherCategoryIds = List<String>.from(
        widget.experience.otherCategories); // Initialize other categories
    _cardData.selectedOtherColorCategoryIds =
        List<String>.from(widget.experience.otherColorCategoryIds);
    _cardData.isPrivate = widget.experience.isPrivate;
    _cardData.selectedLocation = widget.experience.location;
    _cardData.locationEnabled.value =
        widget.experience.location.latitude != 0.0 ||
            widget.experience.location.longitude != 0.0;

    // If location exists, pre-fill searchController for display consistency (optional)
    if (_cardData.selectedLocation?.address != null) {
      _cardData.searchController.text = _cardData.selectedLocation!.address!;
    }

    // --- ADDED: Initialize ValueNotifiers ---
    _userCategoriesNotifier = ValueNotifier<List<UserCategory>>([]);
    _colorCategoriesNotifier = ValueNotifier<List<ColorCategory>>([]);
    // --- END ADDED ---

    // --- ADDED: Listener for Website URL ---
    _cardData.websiteController.addListener(_triggerRebuild);
    // --- END ADDED ---

    // --- ADDED: Load categories on init ---
    _loadAllCategories();
    // --- END ADDED ---

    // --- ADDED: Check for potential duplicate after first frame if enabled ---
    if (widget.enableDuplicatePrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybePromptDuplicateOnOpen();
      });
    }
  }

  @override
  void dispose() {
    // Dispose controllers managed by _cardData
    _cardData.dispose();
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

  List<UserCategory> _filterEditableUserCategories(
      List<UserCategory> categories) {
    if (categories.isEmpty) {
      return categories;
    }
    final String? currentUserId = _auth.currentUser?.uid;
    return categories.where((category) {
      if (currentUserId != null && category.ownerUserId == currentUserId) {
        return true;
      }
      final SharePermission? permission =
          _editableCategoryPermissions[category.id];
      return permission?.accessLevel == ShareAccessLevel.edit;
    }).toList();
  }

  List<ColorCategory> _filterEditableColorCategories(
      List<ColorCategory> categories) {
    if (categories.isEmpty) {
      return categories;
    }
    final String? currentUserId = _auth.currentUser?.uid;
    return categories.where((category) {
      if (currentUserId != null && category.ownerUserId == currentUserId) {
        return true;
      }
      final SharePermission? permission =
          _editableCategoryPermissions[category.id];
      return permission?.accessLevel == ShareAccessLevel.edit;
    }).toList();
  }

  Future<void> _applyCollectionsOrderingToCurrentLists() async {
    final orderedCategories = await _categoryOrderingService
        .orderUserCategories(_currentUserCategories);
    final orderedColorCategories = await _categoryOrderingService
        .orderColorCategories(_currentColorCategories);
    final filteredCategories = _filterEditableUserCategories(orderedCategories);
    final filteredColorCategories =
        _filterEditableColorCategories(orderedColorCategories);
    if (!mounted) {
      return;
    }
    setState(() {
      _currentUserCategories = filteredCategories;
      _currentColorCategories = filteredColorCategories;
    });
    _userCategoriesNotifier.value = filteredCategories;
    _colorCategoriesNotifier.value = filteredColorCategories;
  }

  String? _sharedOwnerLabel(String? ownerName) {
    if (ownerName == null) return null;
    final trimmed = ownerName.trim();
    if (trimmed.isEmpty) return null;
    return 'Shared by $trimmed';
  }
  // --- END ADDED ---

  // --- ADDED: Methods to load categories locally ---
  Future<void> _loadAllCategories() async {
    setState(() => _isLoadingCategories = true);
    try {
      final categoryResultFuture =
          _experienceService.getUserCategoriesWithMeta(
        includeSharedEditable: true,
      );
      final colorCategoriesFuture =
          _experienceService.getUserColorCategories(
        includeSharedEditable: true,
      );
      final permissionsFuture =
          _experienceService.getEditableCategoryPermissionsMap();

      final UserCategoryFetchResult categoryResult =
          await categoryResultFuture;
      Map<String, SharePermission> editablePermissions = {};
      try {
        editablePermissions = await permissionsFuture;
      } catch (e) {
        print(
            "EditExperienceModal: Failed to load editable category permissions: $e");
      }
      _editableCategoryPermissions = {
        ...editablePermissions,
        ...categoryResult.sharedPermissions,
      };

      final orderedCategories = await _categoryOrderingService
          .orderUserCategories(categoryResult.categories,
              sharedPermissions: categoryResult.sharedPermissions);
      final filteredCategories =
          _filterEditableUserCategories(orderedCategories);

      final colorCategories = await colorCategoriesFuture;
      final orderedColorCategories =
          await _categoryOrderingService.orderColorCategories(colorCategories);
      final filteredColorCategories =
          _filterEditableColorCategories(orderedColorCategories);
      if (mounted) {
        setState(() {
          _currentUserCategories = filteredCategories;
          _currentColorCategories = filteredColorCategories;
          _isLoadingCategories = false;
        });
        // --- ADDED: Update ValueNotifiers ---
        _userCategoriesNotifier.value = filteredCategories;
        _colorCategoriesNotifier.value = filteredColorCategories;
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

  // --- ADDED: Duplicate handling on modal open ---
  Future<void> _maybePromptDuplicateOnOpen() async {
    try {
      final placeId = _cardData.selectedLocation?.placeId;
      if (placeId == null || placeId.isEmpty) return;

      // Avoid re-prompt if we already bound to an existing experience id
      if ((_cardData.existingExperienceId != null &&
          _cardData.existingExperienceId!.isNotEmpty)) {
        return;
      }

      final userExperiences = await _experienceService.getUserExperiences();
      final duplicate = userExperiences
          .where((e) => e.location.placeId == placeId)
          .cast<Experience?>()
          .firstOrNull;
      if (duplicate == null) return;

      final bool? useExisting = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('Potential Duplicate Found'),
            content: Text(
                'You already saved an experience named "${duplicate.name}" located at "${duplicate.location.address ?? 'No address provided'}." Do you want to use this existing experience?'),
            actions: <Widget>[
              TextButton(
                child: const Text('Create New'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              ElevatedButton(
                child: const Text('Use Existing'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          );
        },
      );
      if (useExisting == true && mounted) {
        _applyExperienceToForm(duplicate);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Loaded your existing experience for editing.')),
        );
      }
    } catch (e) {
      // Non-fatal
      // print('Duplicate check failed: $e');
    }
  }

  void _applyExperienceToForm(Experience src) {
    setState(() {
      _cardData.existingExperienceId = src.id; // Switch to editing existing
      _cardData.titleController.text = src.name;
      _cardData.yelpUrlController.text = src.yelpUrl ?? '';
      _cardData.websiteController.text = src.website ?? '';
      _populateNotesController(src);
      _cardData.selectedCategoryId = src.categoryId;
      _cardData.selectedColorCategoryId = src.colorCategoryId;
      _cardData.selectedOtherCategoryIds =
          List<String>.from(src.otherCategories);
      _cardData.selectedOtherColorCategoryIds =
          List<String>.from(src.otherColorCategoryIds);
      _cardData.selectedLocation = src.location;
      _cardData.locationEnabled.value =
          src.location.latitude != 0.0 || src.location.longitude != 0.0;
      if (_cardData.selectedLocation?.address != null) {
        _cardData.searchController.text = _cardData.selectedLocation!.address!;
      }
    });
  }

  Future<void> _loadUserCategories() async {
    // Simplified version for targeted refresh
    setState(() => _isLoadingCategories = true);
    try {
      final categoryResultFuture =
          _experienceService.getUserCategoriesWithMeta(
        includeSharedEditable: true,
      );
      final permissionsFuture =
          _experienceService.getEditableCategoryPermissionsMap();
      final UserCategoryFetchResult categoryResult =
          await categoryResultFuture;
      Map<String, SharePermission> editablePermissions = {};
      try {
        editablePermissions = await permissionsFuture;
      } catch (e) {
        print(
            "EditExperienceModal: Failed to load editable category permissions during refresh: $e");
      }
      _editableCategoryPermissions = {
        ...editablePermissions,
        ...categoryResult.sharedPermissions,
      };
      final orderedCategories = await _categoryOrderingService
          .orderUserCategories(categoryResult.categories,
              sharedPermissions: categoryResult.sharedPermissions);
      final filteredCategories =
          _filterEditableUserCategories(orderedCategories);
      if (mounted) {
        setState(() {
          _currentUserCategories = filteredCategories;
          _isLoadingCategories = false;
        });
        // --- ADDED: Update ValueNotifier ---
        _userCategoriesNotifier.value = filteredCategories;
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
      final categoriesFuture = _experienceService.getUserColorCategories(
        includeSharedEditable: true,
      );
      Map<String, SharePermission> editablePermissions = {};
      bool permissionsLoaded = true;
      try {
        editablePermissions =
            await _experienceService.getEditableCategoryPermissionsMap();
      } catch (e) {
        permissionsLoaded = false;
        print(
            "EditExperienceModal: Failed to refresh editable permissions for color categories: $e");
      }
      if (permissionsLoaded) {
        _editableCategoryPermissions = editablePermissions;
      }
      final categories = await categoriesFuture;
      final orderedCategories =
          await _categoryOrderingService.orderColorCategories(categories);
      final filteredCategories =
          _filterEditableColorCategories(orderedCategories);
      if (mounted) {
        setState(() {
          _currentColorCategories = filteredCategories;
          _isLoadingCategories = false;
        });
        // --- ADDED: Update ValueNotifier ---
        _colorCategoriesNotifier.value = filteredCategories;
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

    if (result == null || !mounted) {
      return;
    }

    Future.microtask(() {
      if (mounted) {
        FocusScope.of(context).unfocus();
      }
    });

    if (!mounted) return;

    setState(() {
      _cardData.isSelectingLocation = true;
    });

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
        _cardData.titleController.text =
            detailedLocation.getPlaceName(); // Update title? Discuss if needed
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
    } finally {
      if (mounted) {
        setState(() {
          _cardData.isSelectingLocation = false;
        });
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
                              final newCategory =
                                  await showModalBottomSheet<UserCategory>(
                                context: stfContext,
                                backgroundColor: Colors.white,
                                builder: (context) => const AddCategoryModal(),
                                isScrollControlled: true,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(16)),
                                ),
                              );
                              if (newCategory != null && mounted) {
              print(
                  "Edit Modal: New user category added: ${newCategory.name} (${newCategory.icon})");
              setState(() {
                _cardData.selectedCategoryId = newCategory.id;
              });
              await _loadUserCategories();
                                // Refresh the dialog
                                stfSetState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'Category "${newCategory.name}" added and selected.')),
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
                              final bool? categoriesChanged =
                                  await showModalBottomSheet<bool>(
                                context: stfContext,
                                backgroundColor: Colors.white,
                                builder: (context) =>
                                    const EditCategoriesModal(),
                                isScrollControlled: true,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(16)),
                                ),
                              );
                              if (categoriesChanged == true && mounted) {
                                print(
                                    "Edit Modal: User Categories potentially changed.");
                                await _loadUserCategories();
                                // Check if current selection still exists
                                final currentSelectionExists =
                                    _currentUserCategories.any((cat) =>
                                        cat.id == _cardData.selectedCategoryId);
                                if (!currentSelectionExists &&
                                    _cardData.selectedCategoryId != null) {
                                  setState(() {
                                    _cardData.selectedCategoryId = null;
                                  });
                                }
                                // Refresh the dialog
                                stfSetState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Category list updated. Please review your selection.')),
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
          (yelpUrlString.toLowerCase().contains('yelp.com/biz') ||
              yelpUrlString.toLowerCase().contains('yelp.to/'))) {
        // Ensure it's a Yelp specific link for direct launch
        uri = Uri.parse(yelpUrlString);
      } else {
        // Fallback to Yelp homepage if URL in field is invalid or not a specific Yelp business link
        // Or, consider showing an error: "Please enter a valid Yelp business page URL."
        uri = Uri.parse('https://www.yelp.com');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Invalid or non-specific Yelp URL. Opening Yelp home.')),
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
          uri = Uri.parse(
              'https://www.yelp.com/search?find_desc=$searchDesc&find_loc=$searchLoc');
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
      bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
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
  Future<void> _handleAddColorCategory({bool selectAfterAdding = true}) async {
    FocusScope.of(context).unfocus();
    final newCategory = await showModalBottomSheet<ColorCategory>(
      context: context,
      backgroundColor: Colors.white,
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
      if (selectAfterAdding) {
        setState(() {
          _cardData.selectedColorCategoryId = newCategory.id;
          // Assume widget.userColorCategories might update via provider
        });
      }
      // --- MODIFIED: Refresh local list ---
      _loadColorCategories(); // Refresh the list within this modal
      // --- END MODIFICATION ---
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Color Category "${newCategory.name}" added.${selectAfterAdding ? " It has been selected." : ""}')),
      );
    }
  }

  // Method to handle editing color categories
  Future<bool?> _handleEditColorCategories() async {
    FocusScope.of(context).unfocus();
    final bool? categoriesChanged = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
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
    return categoriesChanged;
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
          backgroundColor: Colors.white,
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
                      final sharedLabel =
                          _sharedOwnerLabel(category.sharedOwnerDisplayName);
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
              backgroundColor: Colors.white,
              builder: (context) => const EditCategoriesModal(),
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
            );
            if (categoriesChanged == true && mounted) {
              print(
                  "Edit Modal: User Categories potentially changed from Other Categories dialog.");
              await _loadUserCategories();
              // Check if current selection still exists
              final currentSelectionExists = _currentUserCategories
                  .any((cat) => cat.id == _cardData.selectedCategoryId);
              if (!currentSelectionExists &&
                  _cardData.selectedCategoryId != null) {
                setState(() {
                  _cardData.selectedCategoryId = null;
                });
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text(
                        'Category list updated. Please review your selection.')),
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
              backgroundColor: Colors.white,
              builder: (context) => const AddCategoryModal(),
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
            );
            if (newCategory != null && mounted) {
              print(
                  "Edit Modal: New user category added from Other Categories dialog: ${newCategory.name} (${newCategory.icon})");
              await _loadUserCategories();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text('Category "${newCategory.name}" added.')),
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

  Future<void> _showOtherColorCategoriesSelectionDialog() async {
    FocusScope.of(context).unfocus();

    final result = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return _OtherColorCategoriesSelectionDialog(
          colorCategoriesNotifier: _colorCategoriesNotifier,
          initiallySelectedIds: _cardData.selectedOtherColorCategoryIds,
          primaryColorCategoryId: _cardData.selectedColorCategoryId,
          onEditColorCategories: () async {
            final bool? categoriesChanged =
                await _handleEditColorCategories();
            if (categoriesChanged == true && mounted) {
              _showOtherColorCategoriesSelectionDialog();
            }
            return categoriesChanged;
          },
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
        _cardData.selectedOtherColorCategoryIds = result;
      });
    }
  }
  // --- END ADDED ---

  void _saveAndClose() {
    if (_requiresCategorySelection &&
        (!_hasPrimaryCategory || !_hasColorCategory)) {
      _showSaveDisabledMessage();
      return;
    }

    if (_formKey.currentState!.validate()) {
      // Construct the updated Experience object
      final Location locationToSave = (_cardData.locationEnabled.value &&
              _cardData.selectedLocation != null)
          ? _cardData.selectedLocation!
          : Location(
              latitude: 0.0,
              longitude: 0.0,
              address: 'No location specified'); // Default/disabled location

      final String trimmedNotes = _cardData.notesController.text.trim();
      final bool shouldClearNotes = trimmedNotes.isEmpty;

      final updatedExperience = widget.experience.copyWith(
        id: _cardData.existingExperienceId?.isNotEmpty == true
            ? _cardData.existingExperienceId
            : widget.experience.id,
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
        otherColorCategoryIds: _cardData.selectedOtherColorCategoryIds,
        otherCategories: _cardData.selectedOtherCategoryIds,
        additionalNotes: shouldClearNotes ? null : trimmedNotes,
        clearAdditionalNotes: shouldClearNotes,
        isPrivate: _cardData.isPrivate,
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

  void _handleSavePressed() {
    if (_isSaveEnabled) {
      _saveAndClose();
    } else {
      _showSaveDisabledMessage();
    }
  }

  void _showSaveDisabledMessage() {
    if (!mounted) {
      return;
    }
    final String message = _buildCategoryWarningMessage();
    final ScaffoldMessengerState? messenger =
        _localMessengerKey.currentState ??
            widget.scaffoldMessenger ??
            ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }
    messenger.hideCurrentSnackBar();
    final mediaQuery = MediaQuery.maybeOf(context);
    final double bottomInset = mediaQuery?.viewInsets.bottom ?? 0.0;
    final double bottomMargin =
        bottomInset > 0 ? bottomInset + 16.0 : 16.0; // keep visible inside sheet
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: bottomMargin,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isSaveEnabled = _isSaveEnabled;
    // Make modal content scrollable and handle keyboard padding
    return ScaffoldMessenger(
      key: _localMessengerKey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Material(
          color: Colors.white,
          child: Padding(
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
                    Align(
                      alignment: Alignment.centerRight,
                      child: PrivacyToggleButton(
                        isPrivate: _cardData.isPrivate,
                        onPressed: () {
                          setState(() {
                            _cardData.isPrivate = !_cardData.isPrivate;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                // --- Form Fields (Similar to ExperienceCardForm) ---

                // Location selection (using adapted widget/logic)
                GestureDetector(
                  onTap: (_cardData.locationEnabled.value &&
                          !_cardData.isSelectingLocation)
                      ? _showLocationPicker
                      : null,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
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
                                            color:
                                                _cardData.locationEnabled.value
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
                        if (_cardData.isSelectingLocation)
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
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a title';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 8),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Search location on Yelp for reference',
                      textAlign: TextAlign.right,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.black87),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: _launchYelpUrl,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Icon(
                          FontAwesomeIcons.yelp,
                          size: 22,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
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
                  onPressed: _isLoadingCategories
                      ? null
                      : _showCategorieselectionDialog,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0)),
                    side: BorderSide(color: Colors.grey),
                    alignment: Alignment.centerLeft,
                    backgroundColor: Colors.white,
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
                            _currentUserCategories
                                    .firstWhereOrNull((cat) =>
                                        cat.id == _cardData.selectedCategoryId)
                                    ?.name ??
                                'Select Category',
                            style: TextStyle(
                                color: _cardData.selectedCategoryId != null
                                    ? Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.color
                                    : Colors.grey[600]),
                          ),
                        ],
                      ),
                      const Icon(Icons.arrow_drop_down, color: Colors.grey),
                    ],
                  ),
                ),
                // TODO: Add validation message display if needed
                SizedBox(height: _cardData.selectedOtherCategoryIds.isNotEmpty ? 16 : 1),

                // --- ADDED: Other Categories Selection ---
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_cardData.selectedOtherCategoryIds.isNotEmpty) ...[
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
                          color: Colors.white,
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: Wrap(
                          spacing: 6.0,
                          runSpacing: 6.0,
                          children: _cardData.selectedOtherCategoryIds
                              .map((categoryId) {
                            final category = _currentUserCategories
                                .firstWhereOrNull((cat) => cat.id == categoryId);
                            if (category == null) return const SizedBox.shrink();
                            return Chip(
                              backgroundColor: Colors.white,
                              avatar: Text(category.icon,
                                  style: const TextStyle(fontSize: 14)),
                              label: Text(category.name),
                              onDeleted: () {
                                setState(() {
                                  _cardData.selectedOtherCategoryIds
                                      .remove(categoryId);
                                });
                              },
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 0),
                              visualDensity: VisualDensity.compact,
                              labelPadding:
                                  const EdgeInsets.symmetric(horizontal: 4.0),
                              deleteIconColor: Colors.grey[600],
                              deleteButtonTooltipMessage: 'Remove category',
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
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                // --- END ADDED ---

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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0)),
                    side: BorderSide(color: Colors.grey),
                    alignment: Alignment.centerLeft,
                    backgroundColor: Colors.white,
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
                SizedBox(height: _cardData.selectedOtherColorCategoryIds.isNotEmpty ? 16 : 1),

                // --- ADDED: Other Color Categories Selection ---
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_cardData.selectedOtherColorCategoryIds.isNotEmpty) ...[
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
                          color: Colors.white,
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: Wrap(
                          spacing: 6.0,
                          runSpacing: 6.0,
                          children: _cardData.selectedOtherColorCategoryIds
                              .map((colorCategoryId) {
                            final colorCategory = _currentColorCategories
                                .firstWhereOrNull(
                                    (cat) => cat.id == colorCategoryId);
                            if (colorCategory == null) {
                              return const SizedBox.shrink();
                            }
                            return Chip(
                              backgroundColor: Colors.white,
                              avatar: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: colorCategory.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              label: Text(colorCategory.name),
                              onDeleted: () {
                                setState(() {
                                  _cardData.selectedOtherColorCategoryIds
                                      .remove(colorCategoryId);
                                });
                              },
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 0),
                              visualDensity: VisualDensity.compact,
                              labelPadding:
                                  const EdgeInsets.symmetric(horizontal: 4.0),
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
                        label:
                            const Text('Assign more color categories'),
                        onPressed: _showOtherColorCategoriesSelectionDialog,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                // --- END ADDED ---

                SizedBox(height: 16),

                // Official website
                TextFormField(
                  controller: _cardData.websiteController,
                  decoration: InputDecoration(
                      labelText: 'Official Website (optional)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.language),
                      filled: true,
                      fillColor: Colors.white,
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
                                padding: const EdgeInsets.all(4.0),
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
                            onTap: _cardData
                                        .websiteController.text.isNotEmpty &&
                                    _isValidUrl(
                                        _cardData.websiteController.text.trim())
                                ? () => _launchUrl(
                                    _cardData.websiteController.text.trim())
                                : null,
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(4.0, 4.0, 8.0, 4.0),
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
                    filled: true,
                    fillColor: Colors.white,
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
                      onPressed: _handleSavePressed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSaveEnabled
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface
                                .withValues(alpha: 0.12),
                        foregroundColor: isSaveEnabled
                            ? Colors.white
                            : theme.colorScheme.onSurface
                                .withValues(alpha: 0.38),
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

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: availableCategories.length,
                    itemBuilder: (context, index) {
                      final category = availableCategories[index];
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

class _OtherColorCategoriesSelectionDialog extends StatefulWidget {
  final ValueNotifier<List<ColorCategory>> colorCategoriesNotifier;
  final List<String> initiallySelectedIds;
  final String? primaryColorCategoryId;
  final Future<bool?> Function() onEditColorCategories;
  final Future<void> Function() onAddColorCategory;

  const _OtherColorCategoriesSelectionDialog({
    required this.colorCategoriesNotifier,
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
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Select Other Color Categories'),
      contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: ValueListenableBuilder<List<ColorCategory>>(
          valueListenable: widget.colorCategoriesNotifier,
          builder: (context, allCategories, child) {
            final availableCategories = allCategories
                .where((cat) => cat.id != widget.primaryColorCategoryId)
                .toList();

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: availableCategories.length,
                    itemBuilder: (context, index) {
                      final category = availableCategories[index];
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
