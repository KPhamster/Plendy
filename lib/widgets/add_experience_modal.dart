import 'package:flutter/material.dart';
import 'package:plendy/models/experience.dart';
import 'package:plendy/models/user_category.dart';
import 'package:plendy/models/color_category.dart';
import 'package:plendy/screens/receive_share_screen.dart' show ExperienceCardData;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:plendy/services/google_maps_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:plendy/widgets/add_color_category_modal.dart';
import 'package:plendy/widgets/edit_color_categories_modal.dart';
import 'package:plendy/widgets/add_category_modal.dart';
import 'package:plendy/widgets/edit_categories_modal.dart';
import 'package:plendy/services/experience_service.dart';
import 'package:plendy/services/auth_service.dart';
import 'package:collection/collection.dart';
import 'package:plendy/screens/location_picker_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plendy/config/app_constants.dart';

class AddExperienceModal extends StatefulWidget {
  final List<UserCategory> userCategories;
  final List<ColorCategory> userColorCategories;

  const AddExperienceModal({
    super.key,
    required this.userCategories,
    required this.userColorCategories,
  });

  @override
  State<AddExperienceModal> createState() => _AddExperienceModalState();
}

class _AddExperienceModalState extends State<AddExperienceModal> {
  // Use ExperienceCardData to manage form state internally
  late ExperienceCardData _cardData;
  final _formKey = GlobalKey<FormState>();
  final GoogleMapsService _mapsService = GoogleMapsService();
  final ExperienceService _experienceService = ExperienceService();
  final AuthService _authService = AuthService();

  List<UserCategory> _currentUserCategories = [];
  List<ColorCategory> _currentColorCategories = [];
  bool _isLoadingCategories = true;
  bool _isSaving = false;
  
  late ValueNotifier<List<UserCategory>> _userCategoriesNotifier;
  late ValueNotifier<List<ColorCategory>> _colorCategoriesNotifier;

  static const String _addCategoryValue = '__add_new_category__';
  static const String _editCategoriesValue = '__edit_categories__';
  static const String _addColorCategoryValue = '__add_new_color_category__';
  static const String _editColorCategoriesValue = '__edit_color_categories__';
  
  @override
  void initState() {
    super.initState();
    _cardData = ExperienceCardData();
    
    // Set default values for a new experience
    _cardData.locationEnabled.value = true;
    
    // Initialize with passed categories
    _currentUserCategories = widget.userCategories;
    _currentColorCategories = widget.userColorCategories;
    
    _userCategoriesNotifier = ValueNotifier<List<UserCategory>>(_currentUserCategories);
    _colorCategoriesNotifier = ValueNotifier<List<ColorCategory>>(_currentColorCategories);
    
    _cardData.yelpUrlController.addListener(_triggerRebuild);
    _cardData.websiteController.addListener(_triggerRebuild);
    
    // Categories are already loaded from parent, so set loading to false
    _isLoadingCategories = false;
    
    // ADDED: Method to load defaults from SharedPreferences
    _loadDefaults();
  }

  @override
  void dispose() {
    _cardData.dispose();
    _cardData.yelpUrlController.removeListener(_triggerRebuild);
    _cardData.websiteController.removeListener(_triggerRebuild);
    _userCategoriesNotifier.dispose();
    _colorCategoriesNotifier.dispose();
    super.dispose();
  }

  void _triggerRebuild() {
    if (mounted) {
      setState(() {});
    }
  }

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
        _userCategoriesNotifier.value = _currentUserCategories;
        _colorCategoriesNotifier.value = _currentColorCategories;
      }
    } catch (e) {
      print("AddExperienceModal: Error loading categories: $e");
      if (mounted) {
        setState(() => _isLoadingCategories = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading categories: $e")),
        );
      }
    }
  }

  Future<void> _loadUserCategories() async {
    setState(() => _isLoadingCategories = true);
    try {
      final categories = await _experienceService.getUserCategories();
      if (mounted) {
        setState(() {
          _currentUserCategories = categories;
          _isLoadingCategories = false;
        });
        _userCategoriesNotifier.value = _currentUserCategories;
      }
    } catch (e) {
      print("AddExperienceModal: Error loading user categories: $e");
      if (mounted) {
        setState(() => _isLoadingCategories = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading user categories: $e")),
        );
      }
    }
  }

  Future<void> _loadColorCategories() async {
    setState(() => _isLoadingCategories = true);
    try {
      final categories = await _experienceService.getUserColorCategories();
      if (mounted) {
        setState(() {
          _currentColorCategories = categories;
          _isLoadingCategories = false;
        });
        _colorCategoriesNotifier.value = _currentColorCategories;
      }
    } catch (e) {
      print("AddExperienceModal: Error loading color categories: $e");
      if (mounted) {
        setState(() => _isLoadingCategories = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading color categories: $e")),
        );
      }
    }
  }

  bool _isValidUrl(String text) {
    final uri = Uri.tryParse(text);
    return uri != null && (uri.isScheme('http') || uri.isScheme('https'));
  }

  Future<void> _showLocationPicker() async {
    FocusScope.of(context).unfocus();

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          initialLocation: _cardData.selectedLocation,
          onLocationSelected: (location) {},
          businessNameHint: _cardData.titleController.text,
        ),
      ),
    );

    if (result != null && mounted) {
      Future.microtask(() => FocusScope.of(context).unfocus());

      final Location selectedLocation =
          result is Map ? result['location'] : result as Location;

      try {
        if (selectedLocation.placeId == null ||
            selectedLocation.placeId!.isEmpty) {
          print("WARN: Location picked has no Place ID. Performing basic update.");
          setState(() {
            _cardData.selectedLocation = selectedLocation;
            _cardData.searchController.text =
                selectedLocation.address ?? 'Selected Location';
            _cardData.locationEnabled.value = true;
          });
          return;
        }

        Location detailedLocation =
            await _mapsService.getPlaceDetails(selectedLocation.placeId!);
        print("Add Modal: Fetched details for picked location: ${detailedLocation.displayName}");

        setState(() {
          _cardData.selectedLocation = detailedLocation;
          if (_cardData.titleController.text.isEmpty) {
            _cardData.titleController.text = detailedLocation.getPlaceName();
          }
          if (_cardData.websiteController.text.isEmpty && detailedLocation.website != null) {
            _cardData.websiteController.text = detailedLocation.website!;
          }
          _cardData.searchController.text = detailedLocation.address ?? '';
          _cardData.locationEnabled.value = true;
        });
      } catch (e) {
        print("Error getting place details after picking location: $e");
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

  Future<void> _showCategorieselectionDialog() async {
    FocusScope.of(context).unfocus();

    final String? selectedValue = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
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
                              final newCategory = await showModalBottomSheet<UserCategory>(
                                context: stfContext,
                                builder: (context) => const AddCategoryModal(),
                                isScrollControlled: true,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                                ),
                              );
                              if (newCategory != null && mounted) {
                                print("Add Modal: New user category added: ${newCategory.name} (${newCategory.icon})");
                                setState(() {
                                  _cardData.selectedCategoryId = newCategory.id;
                                });
                                await _loadUserCategories();
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
                                print("Add Modal: User Categories potentially changed.");
                                await _loadUserCategories();
                                final currentSelectionExists = _currentUserCategories
                                    .any((cat) => cat.id == _cardData.selectedCategoryId);
                                if (!currentSelectionExists && _cardData.selectedCategoryId != null) {
                                  setState(() {
                                    _cardData.selectedCategoryId = null;
                                  });
                                }
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

    if (selectedValue != null) {
      if (_cardData.selectedCategoryId != selectedValue) { 
        setState(() {
          _cardData.selectedCategoryId = selectedValue; 
        });
      }
    }
  }

  String _getIconForSelectedCategory() {
    final selectedId = _cardData.selectedCategoryId; 
    if (selectedId == null) return '❓'; 
    try {
      final matchingCategory = _currentUserCategories.firstWhere(
        (category) => category.id == selectedId,
      );
      return matchingCategory.icon;
    } catch (e) {
      return '❓';
    }
  }

  bool _isYelpUrl(String url) {
    if (url.isEmpty) return false;
    String urlLower = url.toLowerCase();
    return urlLower.contains('yelp.com/biz') || urlLower.contains('yelp.to/');
  }

  String? _extractFirstUrl(String text) {
    if (text.isEmpty) return null;
    final RegExp urlRegex = RegExp(
        r"(?:(?:https?|ftp):\/\/|www\.)[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)",
        caseSensitive: false);
    final match = urlRegex.firstMatch(text);
    return match?.group(0);
  }

  Future<void> _launchYelpUrl() async {
    String yelpUrlString = _cardData.yelpUrlController.text.trim();
    Uri uri;

    if (yelpUrlString.isNotEmpty) {
      if (_isValidUrl(yelpUrlString) &&
          (yelpUrlString.toLowerCase().contains('yelp.com/biz') || yelpUrlString.toLowerCase().contains('yelp.to/'))) {
        uri = Uri.parse(yelpUrlString);
      } else {
        uri = Uri.parse('https://www.yelp.com');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Invalid or non-specific Yelp URL. Opening Yelp home.')),
          );
        }
      }
    } else {
      String titleString = _cardData.titleController.text.trim();
      Location? currentLocation = _cardData.selectedLocation;
      String? addressString = currentLocation?.address?.trim();

      if (titleString.isNotEmpty) {
        String searchDesc = Uri.encodeComponent(titleString);
        if (addressString != null && addressString.isNotEmpty) {
          String searchLoc = Uri.encodeComponent(addressString);
          uri = Uri.parse('https://www.yelp.com/search?find_desc=$searchDesc&find_loc=$searchLoc');
        } else {
          uri = Uri.parse('https://www.yelp.com/search?find_desc=$searchDesc');
        }
      } else {
        uri = Uri.parse('https://www.yelp.com');
      }
    }

    try {
      bool launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open Yelp link/search')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening link: $e')),
        );
      }
    }
  }

  Future<void> _pasteYelpUrlFromClipboard() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final clipboardText = clipboardData?.text;

    if (clipboardText != null && clipboardText.isNotEmpty) {
      final extractedUrl = _extractFirstUrl(clipboardText);

      if (extractedUrl != null) {
        final isYelp = _isYelpUrl(extractedUrl);
        if (isYelp) {
          final isValid = _isValidUrl(extractedUrl);
          if (isValid) {
            setState(() {
              _cardData.yelpUrlController.text = extractedUrl;
            });
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
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard is empty.')),
      );
    }
  }

  Future<void> _pasteWebsiteUrlFromClipboard() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final clipboardText = clipboardData?.text;

    if (clipboardText != null && clipboardText.isNotEmpty) {
      setState(() {
        _cardData.websiteController.text = clipboardText;
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

  Color _getColorForSelectedCategory() {
    final selectedId = _cardData.selectedColorCategoryId;
    if (selectedId == null) {
      return Colors.grey.shade400;
    }
    final matchingCategory = _currentColorCategories.firstWhere(
      (category) => category.id == selectedId,
      orElse: () => const ColorCategory(
          id: '',
          name: '',
          colorHex: 'FF9E9E9E',
          ownerUserId: ''),
    );
    return matchingCategory.color;
  }

  ColorCategory? _getSelectedColorCategoryObject() {
    final selectedId = _cardData.selectedColorCategoryId;
    if (selectedId == null) {
      return null;
    }
    try {
      return _currentColorCategories.firstWhere((cat) => cat.id == selectedId);
    } catch (e) {
      return null;
    }
  }

  Future<void> _handleAddColorCategory() async {
    FocusScope.of(context).unfocus();
    final newCategory = await showModalBottomSheet<ColorCategory>(
      context: context,
      builder: (context) => const AddColorCategoryModal(),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );
    if (newCategory != null && mounted) {
      print(
          "Add Modal: New color category added: ${newCategory.name} (${newCategory.colorHex})");
      setState(() {
        _cardData.selectedColorCategoryId = newCategory.id;
      });
      _loadColorCategories();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Color Category "${newCategory.name}" added. It has been selected.')),
      );
    }
  }

  Future<void> _handleEditColorCategories() async {
    FocusScope.of(context).unfocus();
    final bool? categoriesChanged = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => const EditColorCategoriesModal(),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );

    if (categoriesChanged == true && mounted) {
      print("Add Modal: Color Categories potentially changed.");
      final currentSelectionExists = _currentColorCategories
          .any((cat) => cat.id == _cardData.selectedColorCategoryId);
      if (!currentSelectionExists &&
          _cardData.selectedColorCategoryId != null) {
        setState(() {
          _cardData.selectedColorCategoryId = null;
        });
      } else {
        setState(() {});
      }
      _loadColorCategories();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Color Category list updated. Please review your selection.')),
      );
    }
  }

  Future<void> _showColorCategorySelectionDialog() async {
    FocusScope.of(context).unfocus();

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
                          _cardData.selectedColorCategoryId;
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
                              context, category.id);
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
                              context, _addColorCategoryValue);
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
                              _editColorCategoriesValue);
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

    if (selectedValue != null) {
      if (selectedValue == _addColorCategoryValue) {
        _handleAddColorCategory();
      } else if (selectedValue == _editColorCategoriesValue) {
        _handleEditColorCategories();
      } else {
        if (_cardData.selectedColorCategoryId != selectedValue) {
          setState(() {
            _cardData.selectedColorCategoryId = selectedValue;
          });
        }
      }
    }
  }

  Future<void> _showOtherCategoriesSelectionDialog() async {
    FocusScope.of(context).unfocus();

    final result = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
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
              print("Add Modal: User Categories potentially changed from Other Categories dialog.");
              await _loadUserCategories();
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
              print("Add Modal: New user category added from Other Categories dialog: ${newCategory.name} (${newCategory.icon})");
              await _loadUserCategories();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Category "${newCategory.name}" added.')),
              );
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

  void _saveAndClose() async {
    if (_formKey.currentState!.validate()) {
      if (_cardData.selectedCategoryId == null || _cardData.selectedCategoryId!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a category.')),
        );
        return;
      }

      setState(() {
        _isSaving = true;
      });

      try {
        final String? currentUserId = _authService.currentUser?.uid;
        if (currentUserId == null) {
          throw Exception('User not authenticated');
        }

        final Location locationToSave = (_cardData.locationEnabled.value &&
                _cardData.selectedLocation != null)
            ? _cardData.selectedLocation!
            : Location(
                latitude: 0.0,
                longitude: 0.0,
                address: 'No location specified');

        final now = DateTime.now();
        final newExperience = Experience(
          id: '',
          name: _cardData.titleController.text.trim(),
          description: _cardData.notesController.text.trim().isEmpty
              ? 'Created from Plendy'
              : _cardData.notesController.text.trim(),
          categoryId: _cardData.selectedCategoryId!,
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
          sharedMediaItemIds: [],
          createdAt: now,
          updatedAt: now,
          editorUserIds: [currentUserId],
        );

        final createdExperienceId = await _experienceService.createExperience(newExperience);
        
        // Fetch the created experience to return it
        final createdExperience = await _experienceService.getExperience(createdExperienceId);
        
        // Update category timestamps
        if (_cardData.selectedCategoryId != null) {
          await _experienceService.updateCategoryLastUsedTimestamp(_cardData.selectedCategoryId!);
        }
        for (final otherId in _cardData.selectedOtherCategoryIds) {
          await _experienceService.updateCategoryLastUsedTimestamp(otherId);
        }
        if (_cardData.selectedColorCategoryId != null) {
          await _experienceService.updateColorCategoryLastUsedTimestamp(_cardData.selectedColorCategoryId!);
        }

        // ADDED: Save last used categories to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        if (_cardData.selectedCategoryId != null) {
          await prefs.setString(AppConstants.lastUsedCategoryKey, _cardData.selectedCategoryId!);
        }
        if (_cardData.selectedColorCategoryId != null) {
          await prefs.setString(AppConstants.lastUsedColorCategoryKey, _cardData.selectedColorCategoryId!);
        }
        print("ADD_MODAL_SAVE: Saving other categories: ${_cardData.selectedOtherCategoryIds}");
        await prefs.setStringList(AppConstants.lastUsedOtherCategoriesKey, _cardData.selectedOtherCategoryIds);
        // --- END ADDED ---

        if (mounted) {
          Navigator.of(context).pop(createdExperience);
        }
      } catch (e) {
        print("Error creating experience: $e");
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error creating experience: $e')),
          );
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fix the errors in the form.')),
      );
    }
  }

  Future<void> _launchUrl(String urlString) async {
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

  @override
  Widget build(BuildContext context) {
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
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Experience',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),

              // Location selection
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
                                    _cardData.selectedLocation!.getPlaceName(),
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
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                              color: _getColorForSelectedCategory(),
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

              // Other Categories Selection
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
              SizedBox(height: 16),

              // Yelp URL
              TextFormField(
                controller: _cardData.yelpUrlController,
                decoration: InputDecoration(
                    labelText: 'Yelp URL (optional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(FontAwesomeIcons.yelp),
                    suffixIconConstraints: BoxConstraints.tightFor(
                        width: 110,
                        height: 48),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        if (_cardData.yelpUrlController.text.isNotEmpty)
                          InkWell(
                            onTap: () {
                              _cardData.yelpUrlController.clear();
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Icon(Icons.clear, size: 22),
                            ),
                          ),
                        if (_cardData.yelpUrlController.text.isNotEmpty)
                          const SizedBox(width: 4),
                        InkWell(
                          onTap: _pasteYelpUrlFromClipboard,
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(Icons.content_paste,
                                size: 22, color: Colors.blue[700]),
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: _launchYelpUrl,
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4.0, 4.0, 8.0, 4.0),
                            child: Icon(FontAwesomeIcons.yelp,
                                size: 22,
                                color: Colors.red[700]),
                          ),
                        ),
                      ],
                    )),
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
                    suffixIconConstraints: BoxConstraints.tightFor(
                        width: 110,
                        height: 48),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
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
                        if (_cardData.websiteController.text.isNotEmpty)
                          const SizedBox(width: 4),
                        InkWell(
                          onTap: _pasteWebsiteUrlFromClipboard,
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(Icons.content_paste,
                                size: 22, color: Colors.blue[700]),
                          ),
                        ),
                        const SizedBox(width: 4),
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
                    )),
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

              // Notes field
              TextFormField(
                controller: _cardData.notesController,
                decoration: InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.notes),
                  alignLabelWithHint: true,
                ),
                keyboardType: TextInputType.multiline,
                minLines: 3,
                maxLines: null,
              ),
              SizedBox(height: 24),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveAndClose,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Add Experience'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ADDED: Method to load defaults from SharedPreferences
  Future<void> _loadDefaults() async {
    final prefs = await SharedPreferences.getInstance();

    final lastUsedCategoryId = prefs.getString(AppConstants.lastUsedCategoryKey);
    final lastUsedColorCategoryId = prefs.getString(AppConstants.lastUsedColorCategoryKey);
    final lastUsedOtherCategoryIds = prefs.getStringList(AppConstants.lastUsedOtherCategoriesKey);
    print("ADD_MODAL_LOAD: Read other categories from prefs: $lastUsedOtherCategoryIds");

    if (mounted) {
      setState(() {
        // Apply primary category default
        if (lastUsedCategoryId != null && _currentUserCategories.any((cat) => cat.id == lastUsedCategoryId)) {
          _cardData.selectedCategoryId = lastUsedCategoryId;
        } else if (_currentUserCategories.isNotEmpty) {
          // Fallback to first category if preference is not found or invalid
          _cardData.selectedCategoryId = _currentUserCategories.first.id;
        }

        // Apply color category default
        if (lastUsedColorCategoryId != null && _currentColorCategories.any((cat) => cat.id == lastUsedColorCategoryId)) {
          _cardData.selectedColorCategoryId = lastUsedColorCategoryId;
        }

        // Apply other categories default
        if (lastUsedOtherCategoryIds != null) {
          // Filter out any IDs that no longer exist
          final validOtherIds = lastUsedOtherCategoryIds
              .where((id) => _currentUserCategories.any((cat) => cat.id == id))
              .toList();
          _cardData.selectedOtherCategoryIds = validOtherIds;
          print("ADD_MODAL_LOAD: Setting other categories in setState: $validOtherIds");
        }
      });
    }
  }
}

// Helper extension for Location
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
        RegExp(r'-?\d+\.\d+ ?, ?-?\d+\.\d+');
    return coordRegex.hasMatch(text);
  }
}

// Dialog for selecting 'Other' categories (copied from EditExperienceModal)
class _OtherCategoriesSelectionDialog extends StatefulWidget {
  final ValueNotifier<List<UserCategory>> userCategoriesNotifier;
  final List<String> initiallySelectedIds;
  final String? primaryCategoryId;
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
            final uniqueCategoriesByName = <String, UserCategory>{};
            for (var category in allCategories) {
              uniqueCategoriesByName[category.name] = category;
            }
            final uniqueCategoryList = uniqueCategoriesByName.values.toList();
            
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
                            Navigator.of(context).pop();
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
