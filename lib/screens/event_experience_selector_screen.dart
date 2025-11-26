import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import '../models/experience.dart';
import '../models/user_category.dart';
import '../models/color_category.dart';
import '../models/category_sort_type.dart';
import '../models/experience_sort_type.dart';
import '../models/event.dart';
import '../models/shared_media_item.dart';
import '../services/google_maps_service.dart';
import '../services/auth_service.dart';
import '../services/experience_service.dart';
import '../widgets/event_editor_modal.dart';
import '../widgets/shared_media_preview_modal.dart';
import '../screens/map_screen.dart';

/// A reusable full-screen modal for selecting experiences for events.
///
/// This screen provides a two-tab interface (Categories and Experiences) that allows
/// users to browse and select experiences using checkboxes. It mirrors the functionality
/// of the Collections screen but without the Content tab and with persistent checkboxes
/// on all experience items.
///
/// Features:
/// - Search experiences with auto-scroll and highlight
/// - Sort categories by most recent or alphabetical
/// - Sort color categories by most recent or alphabetical
/// - Sort experiences by most recent, alphabetical, distance, or city
/// - Filter experiences by category and/or color category
/// - Pre-select experiences
/// - Inherit initial sort states from parent screen
///
/// Usage:
/// ```dart
/// final result = await Navigator.of(context).push(
///   MaterialPageRoute(
///     builder: (ctx) => EventExperienceSelectorScreen(
///       categories: categories,
///       colorCategories: colorCategories,
///       experiences: experiences,
///       preSelectedExperienceIds: {'exp1', 'exp2'}, // optional
///       title: 'Custom Title', // optional
///       initialCategorySort: CategorySortType.alphabetical, // optional
///       initialColorCategorySort: ColorCategorySortType.mostRecent, // optional
///       initialExperienceSort: ExperienceSortType.distanceFromMe, // optional
///     ),
///     fullscreenDialog: true,
///   ),
/// );
/// if (result != null && result is Set<String>) {
///   // result contains the selected experience IDs
/// }
/// ```
class EventExperienceSelectorScreen extends StatefulWidget {
  final List<UserCategory> categories;
  final List<ColorCategory> colorCategories;
  final List<Experience> experiences;
  final Set<String>? preSelectedExperienceIds;
  final String? title;
  final CategorySortType? initialCategorySort;
  final ColorCategorySortType? initialColorCategorySort;
  final ExperienceSortType? initialExperienceSort;
  final bool returnSelectionOnly;
  final Event? initialEvent; // The event being edited (for map view mode)

  const EventExperienceSelectorScreen({
    super.key,
    required this.categories,
    required this.colorCategories,
    required this.experiences,
    this.preSelectedExperienceIds,
    this.title,
    this.initialCategorySort,
    this.initialColorCategorySort,
    this.initialExperienceSort,
    this.returnSelectionOnly = false,
    this.initialEvent,
  });

  @override
  State<EventExperienceSelectorScreen> createState() =>
      _EventExperienceSelectorScreenState();
}

class _EventExperienceSelectorScreenState
    extends State<EventExperienceSelectorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentTabIndex = 1;
  late Set<String> _selectedExperienceIds;
  UserCategory? _selectedCategory;
  ColorCategory? _selectedColorCategory;
  bool _showingColorCategories = false;

  // Sorting state
  late CategorySortType _categorySortType;
  late ColorCategorySortType _colorCategorySortType;
  late ExperienceSortType _experienceSortType;

  // Filtering state
  Set<String> _selectedCategoryIds = {};
  Set<String> _selectedColorCategoryIds = {};

  // Sorted/filtered lists
  late List<UserCategory> _sortedCategories;
  late List<ColorCategory> _sortedColorCategories;
  late List<Experience> _sortedExperiences;
  late List<Experience> _filteredExperiences;

  bool _isLoading = false;
  
  // Search functionality
  final TextEditingController _searchController = TextEditingController();
  bool _clearSearchOnNextBuild = false;
  
  // Scroll controller for auto-scrolling to experiences
  final ScrollController _experiencesScrollController = ScrollController();
  
  // Flash state for highlighting selected experience
  String? _flashingExperienceId;
  Timer? _flashTimer;
  
  // Track the order in which experiences were selected
  final List<String> _selectionOrder = [];

  Event? _draftEvent;
  
  // Services
  final _authService = AuthService();
  final _experienceService = ExperienceService();
  final Map<String, List<SharedMediaItem>> _experienceMediaCache = {};

  bool get _hasActiveFilters =>
      _selectedCategoryIds.isNotEmpty || _selectedColorCategoryIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _selectedExperienceIds = widget.preSelectedExperienceIds != null
        ? Set.from(widget.preSelectedExperienceIds!)
        : {};

    // Initialize selection order from the existing event's experience order
    // This ensures existing experiences maintain their order and new selections are appended
    if (widget.initialEvent != null) {
      for (final entry in widget.initialEvent!.experiences) {
        if (entry.experienceId.isNotEmpty && 
            _selectedExperienceIds.contains(entry.experienceId)) {
          _selectionOrder.add(entry.experienceId);
        }
      }
    } else if (widget.preSelectedExperienceIds != null) {
      // If no initialEvent but we have preSelectedIds, preserve order from experiences list
      for (final exp in widget.experiences) {
        if (widget.preSelectedExperienceIds!.contains(exp.id)) {
          _selectionOrder.add(exp.id);
        }
      }
    }

    // Initialize sort types from parent or use defaults
    _categorySortType =
        widget.initialCategorySort ?? CategorySortType.mostRecent;
    _colorCategorySortType =
        widget.initialColorCategorySort ?? ColorCategorySortType.mostRecent;
    _experienceSortType =
        widget.initialExperienceSort ?? ExperienceSortType.mostRecent;

    // Initialize sorted lists - preserve the incoming order from parent
    // The parent (collections_screen) has already applied any custom ordering
    _sortedCategories = List.from(widget.categories);
    _sortedColorCategories = List.from(widget.colorCategories);
    _sortedExperiences = List.from(widget.experiences);
    _filteredExperiences = List.from(widget.experiences);

    // Do NOT apply sorting in initState - preserve the order from the parent screen
    // Sorting will only be applied when user explicitly changes sort via dropdown

    _tabController = TabController(length: 2, vsync: this, initialIndex: 1);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _currentTabIndex = _tabController.index;
        });
      } else {
        if (_currentTabIndex != _tabController.index) {
          setState(() {
            _currentTabIndex = _tabController.index;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _experiencesScrollController.dispose();
    _flashTimer?.cancel();
    super.dispose();
  }

  // Helper to parse hex color string
  Color _parseColor(String hexColor) {
    hexColor = hexColor.toUpperCase().replaceAll("#", "");
    if (hexColor.length == 6) {
      hexColor = "FF$hexColor";
    }
    if (hexColor.length == 8) {
      try {
        return Color(int.parse("0x$hexColor"));
      } catch (e) {
        return Colors.grey;
      }
    }
    return Colors.grey;
  }

  // Sorting methods
  void _applyCategorySort(CategorySortType sortType) {
    setState(() {
      _categorySortType = sortType;
      _sortedCategories = List.from(widget.categories);

      if (sortType == CategorySortType.alphabetical) {
        _sortedCategories.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      } else {
        // mostRecent
        _sortedCategories.sort((a, b) {
          final tsA = a.lastUsedTimestamp;
          final tsB = b.lastUsedTimestamp;
          if (tsA == null && tsB == null) {
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }
          if (tsA == null) return 1;
          if (tsB == null) return -1;
          return tsB.compareTo(tsA);
        });
      }
    });
  }

  void _applyColorCategorySort(ColorCategorySortType sortType) {
    setState(() {
      _colorCategorySortType = sortType;
      _sortedColorCategories = List.from(widget.colorCategories);

      if (sortType == ColorCategorySortType.alphabetical) {
        _sortedColorCategories.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      } else {
        // mostRecent
        _sortedColorCategories.sort((a, b) {
          final tsA = a.lastUsedTimestamp;
          final tsB = b.lastUsedTimestamp;
          if (tsA == null && tsB == null) {
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }
          if (tsA == null) return 1;
          if (tsB == null) return -1;
          return tsB.compareTo(tsA);
        });
      }
    });
  }

  Future<void> _applyExperienceSort(ExperienceSortType sortType) async {
    setState(() {
      _experienceSortType = sortType;
      _isLoading = sortType == ExperienceSortType.distanceFromMe;
    });

    try {
      if (sortType == ExperienceSortType.alphabetical) {
        _sortedExperiences.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _filteredExperiences.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      } else if (sortType == ExperienceSortType.mostRecent) {
        _sortedExperiences.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        _filteredExperiences.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      } else if (sortType == ExperienceSortType.distanceFromMe) {
        await _sortExperiencesByDistance(_sortedExperiences);
        await _sortExperiencesByDistance(_filteredExperiences);
      } else if (sortType == ExperienceSortType.city) {
        String normalizeCity(String? city) => (city ?? '').trim().toLowerCase();
        _sortedExperiences.sort((a, b) {
          final ca = normalizeCity(a.location.city);
          final cb = normalizeCity(b.location.city);
          if (ca.isEmpty && cb.isEmpty) return 0;
          if (ca.isEmpty) return 1;
          if (cb.isEmpty) return -1;
          final cmp = ca.compareTo(cb);
          if (cmp != 0) return cmp;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        _filteredExperiences.sort((a, b) {
          final ca = normalizeCity(a.location.city);
          final cb = normalizeCity(b.location.city);
          if (ca.isEmpty && cb.isEmpty) return 0;
          if (ca.isEmpty) return 1;
          if (cb.isEmpty) return -1;
          final cmp = ca.compareTo(cb);
          if (cmp != 0) return cmp;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sorting experiences: $e')),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sortExperiencesByDistance(
      List<Experience> experiencesToSort) async {
    Position? currentPosition;
    bool locationPermissionGranted = false;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Location services are disabled. Please enable them.')),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Location permission denied. Cannot sort by distance.')),
          );
        }
        return;
      }

      locationPermissionGranted = true;

      currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      if (mounted) {
        String message = 'Could not get current location.';
        if (e is TimeoutException) {
          message = 'Could not get current location: Request timed out.';
        } else if (!locationPermissionGranted) {
          message = 'Location permission denied. Cannot sort by distance.';
        } else {
          message = 'Error getting location: ${e.toString()}';
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
      return;
    }

    List<Map<String, dynamic>> experiencesWithDistance = [];
    for (var exp in experiencesToSort) {
      double? distance;
      if (exp.location.latitude != 0.0 || exp.location.longitude != 0.0) {
        try {
          distance = Geolocator.distanceBetween(
            currentPosition.latitude,
            currentPosition.longitude,
            exp.location.latitude,
            exp.location.longitude,
          );
        } catch (e) {
          distance = null;
        }
      } else {
        distance = null;
      }
      experiencesWithDistance.add({'experience': exp, 'distance': distance});
    }

    experiencesWithDistance.sort((a, b) {
      final distA = a['distance'] as double?;
      final distB = b['distance'] as double?;
      if (distA == null && distB == null) return 0;
      if (distA == null) return 1;
      if (distB == null) return -1;
      return distA.compareTo(distB);
    });

    experiencesToSort.clear();
    experiencesToSort.addAll(experiencesWithDistance
        .map((item) => item['experience'] as Experience)
        .toList());
  }

  void _applyFiltersAndUpdateLists() {
    final filteredExperiences = _sortedExperiences.where((exp) {
      final bool categoryMatch = _selectedCategoryIds.isEmpty ||
          (exp.categoryId != null &&
              _selectedCategoryIds.contains(exp.categoryId)) ||
          (exp.otherCategories
              .any((catId) => _selectedCategoryIds.contains(catId)));

      final bool matchesPrimaryColor = exp.colorCategoryId != null &&
          _selectedColorCategoryIds.contains(exp.colorCategoryId);
      final bool matchesOtherColor = exp.otherColorCategoryIds
          .any((colorId) => _selectedColorCategoryIds.contains(colorId));
      final bool colorMatch = _selectedColorCategoryIds.isEmpty ||
          matchesPrimaryColor ||
          matchesOtherColor;

      return categoryMatch && colorMatch;
    }).toList();

    setState(() {
      _filteredExperiences = filteredExperiences;
    });
  }

  Future<void> _showFilterDialog() async {
    Set<String> tempSelectedCategoryIds = Set.from(_selectedCategoryIds);
    Set<String> tempSelectedColorCategoryIds =
        Set.from(_selectedColorCategoryIds);

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Filter Items'),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setStateDialog) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('By Category:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    if (_sortedCategories.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text('No categories available.'),
                      ),
                    ...(_sortedCategories.toList()
                          ..sort((a, b) => a.name.compareTo(b.name)))
                        .map((category) {
                      return CheckboxListTile(
                        title: Row(
                          children: [
                            SizedBox(
                                width: 16,
                                child: Center(child: Text(category.icon))),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Text(category.name,
                                    overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                        value: tempSelectedCategoryIds.contains(category.id),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (bool? selected) {
                          setStateDialog(() {
                            if (selected == true) {
                              tempSelectedCategoryIds.add(category.id);
                            } else {
                              tempSelectedCategoryIds.remove(category.id);
                            }
                          });
                        },
                      );
                    }),
                    const SizedBox(height: 16),
                    const Text('By Color:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    if (_sortedColorCategories.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text('No color categories available.'),
                      ),
                    ...(_sortedColorCategories.toList()
                          ..sort((a, b) => a.name.compareTo(b.name)))
                        .map((colorCategory) {
                      return CheckboxListTile(
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: _parseColor(colorCategory.colorHex),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.grey),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Text(colorCategory.name,
                                    overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                        value: tempSelectedColorCategoryIds
                            .contains(colorCategory.id),
                        onChanged: (bool? selected) {
                          setStateDialog(() {
                            if (selected == true) {
                              tempSelectedColorCategoryIds
                                  .add(colorCategory.id);
                            } else {
                              tempSelectedColorCategoryIds
                                  .remove(colorCategory.id);
                            }
                          });
                        },
                      );
                    }),
                  ],
                ),
              );
            },
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Show All'),
              onPressed: () {
                tempSelectedCategoryIds.clear();
                tempSelectedColorCategoryIds.clear();
                setState(() {
                  _selectedCategoryIds = tempSelectedCategoryIds;
                  _selectedColorCategoryIds = tempSelectedColorCategoryIds;
                });
                Navigator.of(context).pop();
                _applyFiltersAndUpdateLists();
              },
            ),
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Apply'),
              onPressed: () {
                setState(() {
                  _selectedCategoryIds = tempSelectedCategoryIds;
                  _selectedColorCategoryIds = tempSelectedColorCategoryIds;
                });
                Navigator.of(context).pop();
                _applyFiltersAndUpdateLists();
              },
            ),
          ],
        );
      },
    );
  }

  PopupMenuItem<T> _buildPopupMenuItem<T>({
    required T value,
    required String text,
    required T currentValue,
  }) {
    final bool isSelected = value == currentValue;
    return PopupMenuItem<T>(
      value: value,
      child: Row(
        children: [
          Icon(
            isSelected ? Icons.check : Icons.radio_button_off,
            color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? Theme.of(context).primaryColor : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<List<Experience>> _getExperienceSuggestions(String pattern) async {
    if (pattern.isEmpty) {
      return [];
    }
    
    // Search through all experiences (not just filtered)
    List<Experience> suggestions = _sortedExperiences
        .where((exp) => exp.name.toLowerCase().contains(pattern.toLowerCase()))
        .toList();

    // Sort suggestions alphabetically
    suggestions.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    
    return suggestions;
  }

  Future<void> _onExperienceSelectedFromSearch(Experience experience) async {
    // Clear search
    if (mounted) {
      setState(() {
        _clearSearchOnNextBuild = true;
      });
    }
    _searchController.clear();
    FocusScope.of(context).unfocus();

    // Switch to Experiences tab
    if (_currentTabIndex != 1) {
      _tabController.animateTo(1);
      // Wait for tab animation to complete
      await Future.delayed(const Duration(milliseconds: 300));
    }

    if (!mounted) return;

    // Find the experience in the filtered list
    final experienceIndex = _filteredExperiences.indexWhere((exp) => exp.id == experience.id);
    
    if (experienceIndex == -1) {
      // Experience not in filtered list - could be filtered out
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Experience is hidden by current filters.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Move the selected experience to the top of the filtered list
    setState(() {
      final selectedExp = _filteredExperiences.removeAt(experienceIndex);
      _filteredExperiences.insert(0, selectedExp);
    });

    // Wait a frame for the list to rebuild
    await Future.delayed(const Duration(milliseconds: 50));
    
    // Scroll to the top of the list
    if (_experiencesScrollController.hasClients) {
      await _experiencesScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    // Flash the experience tile
    if (mounted) {
      setState(() {
        _flashingExperienceId = experience.id;
      });

      // Cancel any existing flash timer
      _flashTimer?.cancel();
      
      // Clear flash after a brief moment
      _flashTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() {
            _flashingExperienceId = null;
          });
        }
      });
    }
  }

  Widget _buildTopActionRow() {
    final actions = <Widget>[];
    if (_currentTabIndex == 0 &&
        _selectedCategory == null &&
        !_showingColorCategories) {
      actions.add(_buildCategorySortMenuButton());
    }
    if (_currentTabIndex == 0 &&
        _selectedCategory == null &&
        _showingColorCategories) {
      actions.add(_buildColorCategorySortMenuButton());
    }
    if (_currentTabIndex == 1) {
      actions.add(_buildExperienceSortMenuButton());
      actions.add(_buildFilterActionButton());
    }

    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    final rowChildren = <Widget>[];
    for (var action in actions) {
      if (rowChildren.isNotEmpty) {
        rowChildren.add(const SizedBox(width: 8));
      }
      rowChildren.add(action);
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8.0, 4.0, 8.0, 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: rowChildren,
      ),
    );
  }

  Widget _buildCategorySortMenuButton() {
    return PopupMenuButton<CategorySortType>(
      icon: const Icon(Icons.sort),
      tooltip: 'Sort Categories',
      padding: EdgeInsets.zero,
      color: Colors.white,
      onSelected: (CategorySortType result) {
        _applyCategorySort(result);
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<CategorySortType>>[
        _buildPopupMenuItem<CategorySortType>(
          value: CategorySortType.mostRecent,
          text: 'Sort by Most Recent',
          currentValue: _categorySortType,
        ),
        _buildPopupMenuItem<CategorySortType>(
          value: CategorySortType.alphabetical,
          text: 'Sort Alphabetically',
          currentValue: _categorySortType,
        ),
      ],
    );
  }

  Widget _buildColorCategorySortMenuButton() {
    return PopupMenuButton<ColorCategorySortType>(
      icon: const Icon(Icons.sort),
      tooltip: 'Sort Color Categories',
      padding: EdgeInsets.zero,
      color: Colors.white,
      onSelected: (ColorCategorySortType result) {
        _applyColorCategorySort(result);
      },
      itemBuilder: (BuildContext context) =>
          <PopupMenuEntry<ColorCategorySortType>>[
        _buildPopupMenuItem<ColorCategorySortType>(
          value: ColorCategorySortType.mostRecent,
          text: 'Sort by Most Recent',
          currentValue: _colorCategorySortType,
        ),
        _buildPopupMenuItem<ColorCategorySortType>(
          value: ColorCategorySortType.alphabetical,
          text: 'Sort Alphabetically',
          currentValue: _colorCategorySortType,
        ),
      ],
    );
  }


  Widget _buildExperienceSortMenuButton() {
    return PopupMenuButton<ExperienceSortType>(
      icon: const Icon(Icons.sort),
      tooltip: 'Sort Experiences',
      padding: EdgeInsets.zero,
      color: Colors.white,
      onSelected: (ExperienceSortType result) {
        _applyExperienceSort(result);
      },
      itemBuilder: (BuildContext context) =>
          <PopupMenuEntry<ExperienceSortType>>[
        _buildPopupMenuItem<ExperienceSortType>(
          value: ExperienceSortType.mostRecent,
          text: 'Sort by Most Recent',
          currentValue: _experienceSortType,
        ),
        _buildPopupMenuItem<ExperienceSortType>(
          value: ExperienceSortType.alphabetical,
          text: 'Sort Alphabetically',
          currentValue: _experienceSortType,
        ),
        _buildPopupMenuItem<ExperienceSortType>(
          value: ExperienceSortType.distanceFromMe,
          text: 'Sort by Distance',
          currentValue: _experienceSortType,
        ),
      ],
    );
  }

  Widget _buildFilterActionButton() {
    return IconButton(
      icon: const Icon(Icons.filter_list),
      tooltip: 'Filter Items',
      onPressed: _showFilterDialog,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Select Experiences for Event'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          // Map button (only show when there are selected experiences)
          if (_selectedExperienceIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: 'View selected experiences on map',
                child: ActionChip(
                  avatar: Image.asset(
                    'assets/icon/icon-cropped.png',
                    height: 18,
                  ),
                  label: const SizedBox.shrink(),
                  labelPadding: EdgeInsets.zero,
                  onPressed: () => _openMapWithSelectedExperiences(),
                  tooltip: 'View selected experiences on map',
                  backgroundColor: Colors.white,
                  shape: StadiumBorder(
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.all(4),
                ),
              ),
            ),
          // Done button
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedExperienceIds.isEmpty
                    ? Colors.grey.shade300
                    : Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.fromLTRB(12, 6, 16, 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: _selectedExperienceIds.isEmpty
                  ? null
                  : () async {
                      if (widget.returnSelectionOnly) {
                        Navigator.of(context)
                            .pop(_orderedSelectedExperienceIds());
                        return;
                      }
                      await _navigateToEditor();
                    },
              child: Text('Done (${_selectedExperienceIds.length})'),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? Container(
              color: Colors.white,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.black54),
              ),
            )
          : Container(
              color: Colors.white,
              child: Column(
                children: [
                  // Search Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        cardColor: Colors.white,
                        canvasColor: Colors.white,
                        colorScheme: Theme.of(context).colorScheme.copyWith(
                          surface: Colors.white,
                          background: Colors.white,
                        ),
                      ),
                      child: TypeAheadField<Experience>(
                        builder: (context, controller, focusNode) {
                          if (_clearSearchOnNextBuild) {
                            controller.clear();
                            focusNode.unfocus();
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                setState(() {
                                  _clearSearchOnNextBuild = false;
                                });
                              }
                            });
                          }
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            autofocus: false,
                            decoration: InputDecoration(
                              labelText: 'Search experiences',
                              prefixIcon: Icon(Icons.search,
                                  color: Theme.of(context).primaryColor),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(25.0),
                              ),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.clear),
                                tooltip: 'Clear Search',
                                onPressed: () {
                                  controller.clear();
                                  _searchController.clear();
                                  FocusScope.of(context).unfocus();
                                },
                              ),
                            ),
                          );
                        },
                        suggestionsCallback: (pattern) async {
                          return await _getExperienceSuggestions(pattern);
                        },
                        itemBuilder: (context, suggestion) {
                          return Container(
                            color: Colors.white,
                            child: ListTile(
                              leading: const Icon(Icons.history),
                              title: Text(suggestion.name),
                            ),
                          );
                        },
                        onSelected: (suggestion) async {
                          await _onExperienceSelectedFromSearch(suggestion);
                        },
                        emptyBuilder: (context) => const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text('No experiences found.',
                              style: TextStyle(color: Colors.grey)),
                        ),
                      ),
                    ),
                  ),
                  _buildTopActionRow(),
                  Container(
                    color: Colors.white,
                    child: TabBar(
                      controller: _tabController,
                      tabs: const [
                        Tab(text: 'Categories'),
                        Tab(text: 'Experiences'),
                      ],
                      labelColor: Theme.of(context).primaryColor,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: Theme.of(context).primaryColor,
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // Categories Tab
                        Container(
                          color: Colors.white,
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7.0, vertical: 8.0),
                                child: Row(
                                  children: [
                                    const Expanded(child: SizedBox()),
                                    Flexible(
                                      child: Builder(
                                        builder: (context) {
                                          final IconData toggleIcon =
                                              _showingColorCategories
                                                  ? Icons.category_outlined
                                                  : Icons.color_lens_outlined;
                                          final String toggleLabel =
                                              _showingColorCategories
                                                  ? 'Categories'
                                                  : 'Color Categories';
                                          void onToggle() {
                                            setState(() {
                                              _showingColorCategories =
                                                  !_showingColorCategories;
                                              _selectedCategory = null;
                                              _selectedColorCategory = null;
                                            });
                                          }

                                          return Align(
                                            alignment: Alignment.centerRight,
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: TextButton.icon(
                                                style: TextButton.styleFrom(
                                                  visualDensity:
                                                      const VisualDensity(
                                                          horizontal: -2,
                                                          vertical: -2),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8.0),
                                                ),
                                                icon: Icon(toggleIcon),
                                                label: Text(toggleLabel),
                                                onPressed: onToggle,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: _selectedCategory != null
                                    ? _buildCategoryExperiencesView()
                                    : _selectedColorCategory != null
                                        ? _buildColorCategoryExperiencesView()
                                        : _showingColorCategories
                                            ? _buildColorCategoriesList()
                                            : _buildCategoriesList(),
                              ),
                            ],
                          ),
                        ),
                        // Experiences Tab
                        Container(
                          color: Colors.white,
                          child: _buildExperiencesListView(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildCategoriesList() {
    if (_sortedCategories.isEmpty) {
      return const Center(child: Text('No categories found.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80.0),
      itemCount: _sortedCategories.length,
      itemBuilder: (context, index) {
        final category = _sortedCategories[index];
        final count = widget.experiences
            .where((exp) =>
                exp.categoryId == category.id ||
                exp.otherCategories.contains(category.id))
            .length;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
          leading: Text(category.icon, style: const TextStyle(fontSize: 24)),
          title: Text(category.name),
          subtitle: Text('$count ${count == 1 ? "experience" : "experiences"}'),
          onTap: () {
            setState(() {
              _selectedCategory = category;
              _showingColorCategories = false;
              _selectedColorCategory = null;
            });
          },
        );
      },
    );
  }

  Widget _buildColorCategoriesList() {
    if (_sortedColorCategories.isEmpty) {
      return const Center(child: Text('No color categories found.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80.0),
      itemCount: _sortedColorCategories.length,
      itemBuilder: (context, index) {
        final category = _sortedColorCategories[index];
        final count = widget.experiences.where((exp) {
          final bool isPrimary = exp.colorCategoryId == category.id;
          final bool isOther = exp.otherColorCategoryIds.contains(category.id);
          return isPrimary || isOther;
        }).length;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
          leading: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: category.color,
              shape: BoxShape.circle,
            ),
          ),
          title: Text(category.name),
          subtitle: Text('$count ${count == 1 ? "experience" : "experiences"}'),
          onTap: () {
            setState(() {
              _selectedColorCategory = category;
              _showingColorCategories = true;
              _selectedCategory = null;
            });
          },
        );
      },
    );
  }

  Widget _buildCategoryExperiencesView() {
    // Use sorted/filtered experiences list
    final categoryExperiences = _sortedExperiences
        .where((exp) =>
            exp.categoryId == _selectedCategory!.id ||
            exp.otherCategories.contains(_selectedCategory!.id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to Categories',
                onPressed: () {
                  setState(() {
                    _selectedCategory = null;
                  });
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedCategory!.name,
                  style: Theme.of(context).textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: categoryExperiences.isEmpty
              ? Center(
                  child: Text(
                      'No experiences found in the "${_selectedCategory!.name}" category.'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80.0),
                  itemCount: categoryExperiences.length,
                  itemBuilder: (context, index) {
                    return _buildExperienceListItem(categoryExperiences[index]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildColorCategoryExperiencesView() {
    // Use sorted/filtered experiences list
    final categoryExperiences = _sortedExperiences.where((exp) {
      final bool isPrimary = exp.colorCategoryId == _selectedColorCategory!.id;
      final bool isOther =
          exp.otherColorCategoryIds.contains(_selectedColorCategory!.id);
      return isPrimary || isOther;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to Color Categories',
                onPressed: () {
                  setState(() {
                    _selectedColorCategory = null;
                  });
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedColorCategory!.name,
                  style: Theme.of(context).textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: categoryExperiences.isEmpty
              ? Center(
                  child: Text(
                      'No experiences found with the "${_selectedColorCategory!.name}" color category.'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80.0),
                  itemCount: categoryExperiences.length,
                  itemBuilder: (context, index) {
                    return _buildExperienceListItem(categoryExperiences[index]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildExperiencesListView() {
    if (_filteredExperiences.isEmpty) {
      return Center(
        child: Text(_hasActiveFilters
            ? 'No experiences match the current filters.'
            : 'No experiences found. Add some!'),
      );
    }

    return ListView.builder(
      controller: _experiencesScrollController,
      padding: const EdgeInsets.only(bottom: 80.0),
      itemCount: _filteredExperiences.length,
      itemBuilder: (context, index) {
        return _buildExperienceListItem(_filteredExperiences[index]);
      },
    );
  }

  Widget _buildExperienceListItem(Experience experience) {
    final category = _sortedCategories.firstWhereOrNull(
      (cat) => cat.id == experience.categoryId,
    );
    final categoryIcon = category?.icon ?? '?';

    final colorCategoryForBox = _sortedColorCategories.firstWhereOrNull(
      (cc) => cc.id == experience.colorCategoryId,
    );
    final Color leadingBoxColor = colorCategoryForBox != null
        ? _parseColor(colorCategoryForBox.colorHex).withOpacity(0.5)
        : Colors.white;

    final List<UserCategory> otherCategories = experience.otherCategories
        .map(
          (categoryId) => _sortedCategories.firstWhereOrNull(
            (cat) => cat.id == categoryId,
          ),
        )
        .whereType<UserCategory>()
        .toList();
    final List<ColorCategory> otherColorCategories = experience
        .otherColorCategoryIds
        .map(
          (colorCategoryId) => _sortedColorCategories.firstWhereOrNull(
            (cc) => cc.id == colorCategoryId,
          ),
        )
        .whereType<ColorCategory>()
        .toList();

    final String? address = experience.location.address;
    final bool hasAddress = address != null && address.isNotEmpty;
    final bool hasOtherCategories = otherCategories.isNotEmpty;
    final bool hasOtherColorCategories = otherColorCategories.isNotEmpty;
    final int contentCount = experience.sharedMediaItemIds.length;
    final bool shouldShowSubRow =
        hasOtherCategories || hasOtherColorCategories || contentCount > 0;
    const double playButtonDiameter = 36.0;
    const double playIconSize = 20.0;
    const double badgeDiameter = 18.0;
    const double badgeFontSize = 11.0;
    const double badgeBorderWidth = 2.0;
    const double badgeOffset = -3.0;

    final List<Widget> subtitleChildren = [];
    if (hasAddress) {
      subtitleChildren.add(
        Text(
          address,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    if (shouldShowSubRow) {
      subtitleChildren.add(
        Padding(
          padding: EdgeInsets.only(top: hasAddress ? 2.0 : 0.0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasOtherCategories || hasOtherColorCategories)
                      Wrap(
                        spacing: 6.0,
                        runSpacing: 2.0,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ...otherCategories.map(
                            (otherCategory) => Text(
                              otherCategory.icon,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          ...otherColorCategories.map(
                            (colorCategory) => Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _parseColor(colorCategory.colorHex),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (contentCount > 0) ...[
                const SizedBox(width: 12),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openExperienceContentPreview(experience),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: playButtonDiameter,
                        height: playButtonDiameter,
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: playIconSize,
                        ),
                      ),
                      Positioned(
                        bottom: badgeOffset,
                        right: badgeOffset,
                        child: Container(
                          width: badgeDiameter,
                          height: badgeDiameter,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).primaryColor,
                              width: badgeBorderWidth,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              contentCount.toString(),
                              style: TextStyle(
                                color: Theme.of(context).primaryColor,
                                fontSize: badgeFontSize,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final bool isSelected = _selectedExperienceIds.contains(experience.id);
    final bool isFlashing = _flashingExperienceId == experience.id;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: isFlashing 
          ? Theme.of(context).primaryColor.withOpacity(0.2)
          : Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8.0),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
            value: isSelected,
            onChanged: (bool? value) {
              setState(() {
                if (value ?? false) {
                  _selectedExperienceIds.add(experience.id);
                  // Track selection order
                  if (!_selectionOrder.contains(experience.id)) {
                    _selectionOrder.add(experience.id);
                  }
                } else {
                  _selectedExperienceIds.remove(experience.id);
                  // Don't remove from order - preserve check order
                }
              });
            },
            ),
            const SizedBox(width: 4),
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: leadingBoxColor,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Text(
                categoryIcon,
                style: const TextStyle(fontSize: 28),
              ),
            ),
          ],
        ),
        title: Text(
          experience.name,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        subtitle: subtitleChildren.isEmpty
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: subtitleChildren,
              ),
      onTap: () {
        setState(() {
          if (_selectedExperienceIds.contains(experience.id)) {
            _selectedExperienceIds.remove(experience.id);
            // Don't remove from order - preserve check order
          } else {
            _selectedExperienceIds.add(experience.id);
            // Track selection order
            if (!_selectionOrder.contains(experience.id)) {
              _selectionOrder.add(experience.id);
            }
          }
        });
      },
      ),
    );
  }

  List<String> _orderedSelectedExperienceIds() {
    final Set<String> remainingIds = Set.from(_selectedExperienceIds);
    final List<String> orderedIds = [];

    for (final expId in _selectionOrder) {
      if (remainingIds.remove(expId)) {
        orderedIds.add(expId);
      }
    }

    if (remainingIds.isNotEmpty) {
      for (final exp in widget.experiences) {
        if (remainingIds.remove(exp.id)) {
          orderedIds.add(exp.id);
        }
        if (remainingIds.isEmpty) break;
      }
    }

    return orderedIds;
  }

  List<EventExperienceEntry> _buildEventExperienceEntries(
      List<EventExperienceEntry> existingEntries) {
    final Map<String, EventExperienceEntry> existingMap = {
      for (final entry in existingEntries) entry.experienceId: entry,
    };

    final List<EventExperienceEntry> updatedEntries = [];
    for (final experienceId in _orderedSelectedExperienceIds()) {
      final existingEntry = existingMap[experienceId];
      if (existingEntry != null) {
        updatedEntries.add(existingEntry);
      } else {
        updatedEntries.add(EventExperienceEntry(experienceId: experienceId));
      }
    }
    return updatedEntries;
  }

  String? _deriveCoverImageFromEntries(
      List<EventExperienceEntry> experienceEntries) {
    if (experienceEntries.isEmpty) return null;
    final firstExpId = experienceEntries.first.experienceId;
    final firstExp = widget.experiences
        .firstWhereOrNull((exp) => exp.id == firstExpId);

    if (firstExp == null) return null;

    String? coverImageUrl;
    final resourceName = firstExp.location.photoResourceName;
    if (resourceName != null && resourceName.isNotEmpty) {
      coverImageUrl = GoogleMapsService.buildPlacePhotoUrlFromResourceName(
        resourceName,
        maxWidthPx: 800,
        maxHeightPx: 600,
      );
    }
    coverImageUrl ??= firstExp.location.photoUrl;
    return coverImageUrl;
  }

  Event _buildEventForEditor(String currentUserId) {
    final DateTime now = DateTime.now();
    // Use initialEvent if provided (editing existing event), then draft, then create new
    final Event baseEvent = _draftEvent ??
        widget.initialEvent ??
        Event(
          id: '',
          title: 'Untitled Event',
          description: '',
          startDateTime: now,
          endDateTime: now.add(const Duration(hours: 2)),
          coverImageUrl: null,
          plannerUserId: currentUserId,
          experiences: const [],
          createdAt: now,
          updatedAt: now,
        );

    final List<EventExperienceEntry> updatedEntries =
        _buildEventExperienceEntries(baseEvent.experiences);
    final String? coverImageUrl =
        baseEvent.coverImageUrl ?? _deriveCoverImageFromEntries(updatedEntries);

    return baseEvent.copyWith(
      experiences: updatedEntries,
      coverImageUrl: coverImageUrl,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _openMapWithSelectedExperiences() async {
    if (_selectedExperienceIds.isEmpty) return;

    final currentUserId = _authService.currentUser?.uid;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not authenticated')),
      );
      return;
    }

    // Build an event with the currently selected experiences
    final Event event = _buildEventForEditor(currentUserId);

    final result = await Navigator.push<Event>(
      context,
      MaterialPageRoute(
        builder: (context) => MapScreen(
          initialEvent: event,
        ),
      ),
    );

    // Handle returned event with updated itinerary
    if (result != null && mounted) {
      // Extract experience IDs from the returned event
      final updatedExperienceIds = result.experiences
          .where((entry) => entry.experienceId.isNotEmpty)
          .map((entry) => entry.experienceId)
          .toSet();

      setState(() {
        _selectedExperienceIds = updatedExperienceIds;
        
        // Update selection order to match the event's itinerary order
        _selectionOrder.clear();
        for (final entry in result.experiences) {
          if (entry.experienceId.isNotEmpty) {
            _selectionOrder.add(entry.experienceId);
          }
        }
        
        // Store the draft event
        _draftEvent = result;
      });

      // Show feedback
      if (_selectedExperienceIds.length != event.experiences.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Updated: ${_selectedExperienceIds.length} experience${_selectedExperienceIds.length != 1 ? 's' : ''} selected',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _openExperienceContentPreview(Experience experience) async {
    if (experience.sharedMediaItemIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('No saved content available yet for this experience.'),
          ),
        );
      }
      return;
    }

    final cachedItems = _experienceMediaCache[experience.id];
    late final List<SharedMediaItem> resolvedItems;

    if (cachedItems == null) {
      try {
        final fetched = await _experienceService
            .getSharedMediaItems(experience.sharedMediaItemIds);
        fetched.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        resolvedItems = fetched;
        _experienceMediaCache[experience.id] = fetched;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not load content preview: $e')),
          );
        }
        return;
      }
    } else {
      resolvedItems = cachedItems;
    }

    if (resolvedItems.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('No saved content available yet for this experience.'),
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    final UserCategory? category = widget.categories.firstWhereOrNull(
      (cat) => cat.id == experience.categoryId,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      builder: (modalContext) {
        final SharedMediaItem initialMedia = resolvedItems.first;
        return SharedMediaPreviewModal(
          experience: experience,
          mediaItem: initialMedia,
          mediaItems: resolvedItems,
          onLaunchUrl: _launchUrl,
          category: category,
          userColorCategories: widget.colorCategories,
        );
      },
    );
  }

  Future<void> _launchUrl(String urlString) async {
    if (urlString.isEmpty ||
        urlString == 'about:blank' ||
        urlString == 'https://about:blank') {
      return;
    }

    String launchableUrl = urlString;
    if (!launchableUrl.startsWith('http://') &&
        !launchableUrl.startsWith('https://')) {
      launchableUrl = 'https://$launchableUrl';
    }

    try {
      final Uri uri = Uri.parse(launchableUrl);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch $launchableUrl');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link: $urlString')),
        );
      }
    }
  }

  Future<void> _navigateToEditor() async {
    if (_selectedExperienceIds.isEmpty) return;

    final currentUserId = _authService.currentUser?.uid;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not authenticated')),
      );
      return;
    }

    final Event event = _buildEventForEditor(currentUserId);

    final result = await Navigator.of(context).push<EventEditorResult>(
      MaterialPageRoute(
        builder: (ctx) => EventEditorModal(
          event: event,
          experiences: widget.experiences
              .where((exp) => _selectedExperienceIds.contains(exp.id))
              .toList(),
          categories: widget.categories,
          colorCategories: widget.colorCategories,
          returnToSelectorOnItineraryTap: true,
        ),
        fullscreenDialog: true,
      ),
    );

    if (!mounted || result == null) return;

    if (result.wasSaved && result.savedEvent != null) {
      Navigator.of(context).pop(result.savedEvent);
    } else if (result.draftEvent != null) {
      setState(() {
        _draftEvent = result.draftEvent;
      });
    }
  }
}
