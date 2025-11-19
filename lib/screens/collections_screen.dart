import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../models/experience.dart';
import '../models/user_category.dart';
import '../models/color_category.dart';
import '../models/user_profile.dart'; // ADDED: Import for UserProfile
import '../widgets/add_color_category_modal.dart';
import '../services/auth_service.dart';
import '../services/experience_service.dart';
import '../services/experience_share_service.dart';
import '../widgets/add_category_modal.dart';
import '../widgets/add_experience_modal.dart'; // ADDED: Import for AddExperienceModal
import 'experience_page_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async'; // <-- ADDED Import for TimeoutException
import 'package:url_launcher/url_launcher.dart'; // ADDED for launching URLs
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; // ADDED for icons
// ADDED: Import Instagram Preview Widget (adjust alias if needed)
import 'receive_share/widgets/instagram_preview_widget.dart'
    as instagram_widget;
import 'receive_share_screen.dart';
import 'package:provider/provider.dart';
import '../providers/receive_share_provider.dart';
import '../providers/category_save_progress_notifier.dart';
import 'receive_share/widgets/tiktok_preview_widget.dart';
import 'receive_share/widgets/facebook_preview_widget.dart';
import 'receive_share/widgets/youtube_preview_widget.dart';
import 'receive_share/widgets/generic_url_preview_widget.dart';
import 'receive_share/widgets/web_url_preview_widget.dart';
import 'receive_share/widgets/maps_preview_widget.dart';
import 'receive_share/widgets/yelp_preview_widget.dart';
import '../models/shared_media_item.dart'; // ADDED Import
import '../widgets/shared_media_preview_modal.dart';
import '../models/share_permission.dart'; // ADDED Import for SharePermission
import '../models/enums/share_enums.dart'; // ADDED Import for ShareableItemType and ShareAccessLevel
import '../models/category_sort_type.dart';
import 'package:collection/collection.dart'; // ADDED: Import for groupBy
import 'map_screen.dart'; // ADDED: Import for MapScreen
import 'package:flutter/foundation.dart'; // ADDED: Import for kIsWeb
import 'package:flutter/gestures.dart'; // ADDED Import for PointerScrollEvent
import 'package:flutter/rendering.dart'; // ADDED Import for Scrollable
import '../services/google_maps_service.dart';
import '../services/category_share_service.dart';
import '../services/sharing_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/web_media_preview_card.dart'; // ADDED: Import for WebMediaPreviewCard
import '../widgets/privacy_toggle_button.dart';

// Helper classes for shared data
class _SharedCategoryData {
  final UserCategory? userCategory;
  final ColorCategory? colorCategory;
  final SharePermission permission;
  final String ownerDisplayName;

  _SharedCategoryData({
    this.userCategory,
    this.colorCategory,
    required this.permission,
    required this.ownerDisplayName,
  });

  String get categoryId => userCategory?.id ?? colorCategory?.id ?? '';
  bool get isColorCategory => colorCategory != null;
}

class _SharedExperienceData {
  final Experience experience;
  final SharePermission permission;
  final String ownerDisplayName;

  _SharedExperienceData({
    required this.experience,
    required this.permission,
    required this.ownerDisplayName,
  });
}

class _ShareParticipantInfo {
  final String userId;
  final String displayName;
  final ShareAccessLevel accessLevel;
  final bool isCurrentUser;

  const _ShareParticipantInfo({
    required this.userId,
    required this.displayName,
    required this.accessLevel,
    required this.isCurrentUser,
  });
}

class _ShareAccessDetails {
  final String ownerUserId;
  final String ownerDisplayName;
  final bool ownerIsCurrentUser;
  final List<_ShareParticipantInfo> participants;

  const _ShareAccessDetails({
    required this.ownerUserId,
    required this.ownerDisplayName,
    required this.ownerIsCurrentUser,
    required this.participants,
  });
}

// Helper function to parse hex color string (copied from map_screen)
Color _parseColor(String hexColor) {
  hexColor = hexColor.toUpperCase().replaceAll("#", "");
  if (hexColor.length == 6) {
    hexColor = "FF$hexColor"; // Add alpha if missing
  }
  if (hexColor.length == 8) {
    try {
      return Color(int.parse("0x$hexColor"));
    } catch (e) {
      return Colors.grey; // Default color on parsing error
    }
  }
  return Colors.grey; // Default color on invalid format
}

// ADDED: Enum for experience sort types
enum ExperienceSortType { mostRecent, alphabetical, distanceFromMe, city }

// ADDED: Enum for content sort types
enum ContentSortType { mostRecent, alphabetical, distanceFromMe, city }

// ADDED: New helper class to hold grouped content
class GroupedContentItem {
  final SharedMediaItem mediaItem;
  final List<Experience> associatedExperiences;
  double? minDistance; // Used for distance sorting

  GroupedContentItem({
    required this.mediaItem,
    required this.associatedExperiences,
    this.minDistance,
  });

  GroupedContentItem copyWith({
    SharedMediaItem? mediaItem,
    List<Experience>? associatedExperiences,
    double? minDistance,
  }) {
    return GroupedContentItem(
      mediaItem: mediaItem ?? this.mediaItem,
      associatedExperiences:
          associatedExperiences ?? this.associatedExperiences,
      minDistance: minDistance ?? this.minDistance,
    );
  }
}

class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => CollectionsScreenState();
}

class CollectionsScreenState extends State<CollectionsScreen>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  final _experienceService = ExperienceService();
  final TextEditingController _searchController = TextEditingController();

  // Bottom padding to keep last item above the FAB
  static const double _bottomListPadding = 80.0;

  late TabController _tabController;
  int _currentTabIndex = 0;
  // ADDED: Flag to clear TypeAhead controller on next build
  bool _clearSearchOnNextBuild = false;

  bool _isLoading = true;
  List<UserCategory> _categories = [];
  List<Experience> _experiences = [];
  // ADDED: State for color categories
  List<ColorCategory> _colorCategories = [];
  bool _showingColorCategories = false; // Flag to toggle view in first tab
  final SharingService _sharingService = SharingService();
  final Map<String, SharePermission> _sharedCategoryPermissions = {};
  final Map<String, SharePermission> _sharedExperiencePermissions = {};
  final Map<String, String> _shareOwnerNames = {};
  final Map<String, bool> _sharedCategoryIsColor = {};
  final Set<String> _ownedSharedCategoryIds = {};
  final Set<String> _ownedSharedColorCategoryIds = {};
  final Set<String> _ownedSharedExperienceIds = {};
  List<UserCategory> _sharedCategories = [];
  List<ColorCategory> _sharedColorCategories = [];
  List<Experience> _sharedExperiences = [];
  CategorySaveProgressNotifier? _categorySaveNotifier;

  // Selection mode for Categories/Color Categories in the first tab
  bool _isSelectingCategories = false;
  bool _isSelectingExperiences = false;
  final Set<String> _selectedExperienceIds = <String>{};

  // Cache resolved shared media to avoid refetching when previewing content
  final Map<String, List<SharedMediaItem>> _experienceMediaCache = {};

  // Pagination state for Experiences tab
  static const int _experiencesPageSize = 100;
  DocumentSnapshot<Object?>? _lastExperienceDoc;
  bool _hasMoreExperiences = true;
  bool _isLoadingMoreExperiences = false;
  final ScrollController _experiencesScrollController = ScrollController();

  bool _isSharedCategory(UserCategory category) =>
      _sharedCategoryPermissions.containsKey(category.id);

  Timestamp? _sharedCategoryCreatedAt(UserCategory category) =>
      _sharedCategoryPermissions[category.id]?.createdAt;

  bool _isSharedExperience(Experience experience) =>
      _sharedExperiencePermissions.containsKey(experience.id);

  DateTime _sharedExperienceUpdatedAt(Experience experience) =>
      experience.updatedAt;

  UserCategory _resolveCategoryForExperience(Experience experience) {
    final existing =
        _categories.firstWhereOrNull((cat) => cat.id == experience.categoryId);
    if (existing != null) {
      return existing;
    }

    final fallbackName =
        experience.categoryId != null ? 'Category Not Found' : 'Uncategorized';

    return UserCategory(
      id: experience.categoryId ?? 'uncategorized',
      name: fallbackName,
      icon: existing?.icon ?? '?',
      ownerUserId: existing?.ownerUserId ??
          _authService.currentUser?.uid ??
          'system_default',
      orderIndex: existing?.orderIndex ?? 9999,
    );
  }

  Future<void> _openExperience(Experience experience) async {
    final sharePermission = _sharedExperiencePermissions[experience.id];
    final bool isShared = sharePermission != null;
    final bool hasEditAccess = _experienceHasEditAccess(experience);

    final UserCategory resolvedCategory =
        _resolveCategoryForExperience(experience);

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => ExperiencePageScreen(
          experience: experience,
          category: resolvedCategory,
          userColorCategories: _colorCategories,
          shareBannerFromUserId: sharePermission?.ownerUserId,
          shareAccessMode: isShared ? (hasEditAccess ? 'edit' : 'view') : null,
        ),
      ),
    );

    if (result == true && mounted) {
      _loadData();
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

    final UserCategory? category = _categories.firstWhereOrNull(
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
          userColorCategories: _colorCategories,
        );
      },
    );
  }

  int _compareCategoriesForSort(
      UserCategory a, UserCategory b, CategorySortType sortType) {
    if (sortType == CategorySortType.alphabetical) {
      final cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (cmp != 0) return cmp;
      return a.id.compareTo(b.id);
    }

    if (sortType == CategorySortType.mostRecent) {
      final tsA = _isSharedCategory(a)
          ? _sharedCategoryCreatedAt(a)
          : a.lastUsedTimestamp;
      final tsB = _isSharedCategory(b)
          ? _sharedCategoryCreatedAt(b)
          : b.lastUsedTimestamp;

      if (tsA == null && tsB == null) {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      if (tsA == null) return 1;
      if (tsB == null) return -1;
      final cmp = tsB.compareTo(tsA);
      if (cmp != 0) return cmp;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }

    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  // ADDED: State variable for experience sort type
  ExperienceSortType _experienceSortType = ExperienceSortType.mostRecent;
  // ADDED: State variable for content sort type
  ContentSortType _contentSortType = ContentSortType.mostRecent;
  // ADDED: State variables for category sort types
  CategorySortType _categorySortType = CategorySortType.mostRecent;
  ColorCategorySortType _colorCategorySortType =
      ColorCategorySortType.mostRecent;
  String? _userEmail;
  // ADDED: State variable to track the selected category in the first tab
  UserCategory? _selectedCategory;
  // --- ADDED: State variable for selected color category ---
  ColorCategory? _selectedColorCategory;
  // --- END ADDED ---
  // ADDED: State variable to hold grouped list of content items
  List<GroupedContentItem> _groupedContentItems = [];
  // Track the currently expanded content preview (only one at a time)
  String? _expandedContentMediaPath;
  // ADDED: City header expansion states
  final Map<String, bool> _cityExpansionExperiences = {};
  final Map<String, bool> _cityExpansionContent = {};
  // NEW: Generic expansion maps for dynamic multi-level grouping
  final Map<String, bool> _locationExpansionExperiences = {};
  final Map<String, bool> _locationExpansionContent = {};
  bool _groupByCityExperiences = false;
  bool _groupByCityContent = false;
  List<String> _manualCategoryOrder = [];
  List<String> _manualColorCategoryOrder = [];
  bool _useManualCategoryOrder = false;
  bool _useManualColorCategoryOrder = false;

  // --- Persistent sort preference keys ---
  static const String _prefsKeyCategorySort = 'collections_category_sort';
  static const String _prefsKeyColorCategorySort =
      'collections_color_category_sort';
  static const String _prefsKeyExperienceSort = 'collections_experience_sort';
  static const String _prefsKeyContentSort = 'collections_content_sort';
  static const String _prefsKeyGroupByLocationExperiences =
      'collections_group_by_location_experiences';
  static const String _prefsKeyGroupByLocationContent =
      'collections_group_by_location_content';
  static const String _prefsKeyCategoryOrderPrefix =
      'collections_category_order_';
  static const String _prefsKeyColorCategoryOrderPrefix =
      'collections_color_category_order_';
  static const String _prefsKeyUseManualCategoryOrderPrefix =
      'collections_use_manual_category_order_';
  static const String _prefsKeyUseManualColorCategoryOrderPrefix =
      'collections_use_manual_color_category_order_';

  Future<void> _loadSortPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cat = prefs.getString(_prefsKeyCategorySort);
      final colorCat = prefs.getString(_prefsKeyColorCategorySort);
      final exp = prefs.getString(_prefsKeyExperienceSort);
      final content = prefs.getString(_prefsKeyContentSort);
      final groupExp = prefs.getBool(_prefsKeyGroupByLocationExperiences);
      final groupContent = prefs.getBool(_prefsKeyGroupByLocationContent);
      final String? userId = _authService.currentUser?.uid;
      List<String>? manualCategoryOrder;
      List<String>? manualColorCategoryOrder;
      bool? manualCategoryOrderEnabled;
      bool? manualColorCategoryOrderEnabled;
      if (userId != null && userId.isNotEmpty) {
        manualCategoryOrder =
            prefs.getStringList('$_prefsKeyCategoryOrderPrefix$userId');
        manualColorCategoryOrder =
            prefs.getStringList('$_prefsKeyColorCategoryOrderPrefix$userId');
        manualCategoryOrderEnabled =
            prefs.getBool('$_prefsKeyUseManualCategoryOrderPrefix$userId');
        manualColorCategoryOrderEnabled =
            prefs.getBool('$_prefsKeyUseManualColorCategoryOrderPrefix$userId');
      }

      setState(() {
        if (cat != null) {
          _categorySortType = CategorySortType.values.firstWhere(
              (e) => e.name == cat,
              orElse: () => _categorySortType);
        }
        if (colorCat != null) {
          _colorCategorySortType = ColorCategorySortType.values.firstWhere(
              (e) => e.name == colorCat,
              orElse: () => _colorCategorySortType);
        }
        if (exp != null) {
          _experienceSortType = ExperienceSortType.values.firstWhere(
              (e) => e.name == exp,
              orElse: () => _experienceSortType);
          print('[Collections] Loaded experience sort preference: $exp -> $_experienceSortType');
        } else {
          print('[Collections] No saved experience sort preference, using default: $_experienceSortType');
        }
        if (content != null) {
          _contentSortType = ContentSortType.values.firstWhere(
              (e) => e.name == content,
              orElse: () => _contentSortType);
        }
        if (groupExp != null) {
          _groupByLocationExperiences = groupExp;
        }
        if (groupContent != null) {
          _groupByLocationContent = groupContent;
        }
        if (manualCategoryOrder != null) {
          _manualCategoryOrder = List<String>.from(manualCategoryOrder);
        }
        if (manualColorCategoryOrder != null) {
          _manualColorCategoryOrder =
              List<String>.from(manualColorCategoryOrder);
        }
        if (manualCategoryOrderEnabled != null) {
          _useManualCategoryOrder = manualCategoryOrderEnabled;
        }
        if (manualColorCategoryOrderEnabled != null) {
          _useManualColorCategoryOrder = manualColorCategoryOrderEnabled;
        }
      });
    } catch (_) {}
  }

  Future<void> _saveCategorySort(CategorySortType sortType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyCategorySort, sortType.name);
    } catch (_) {}
  }

  Future<void> _saveColorCategorySort(ColorCategorySortType sortType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyColorCategorySort, sortType.name);
    } catch (_) {}
  }

  Future<void> _saveExperienceSort(ExperienceSortType sortType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyExperienceSort, sortType.name);
      print('[Collections] Saved experience sort preference: ${sortType.name}');
    } catch (e) {
      print('[Collections] Error saving experience sort preference: $e');
    }
  }

  Future<void> _saveContentSort(ContentSortType sortType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyContentSort, sortType.name);
    } catch (_) {}
  }

  Future<void> _saveGroupByLocationExperiences(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKeyGroupByLocationExperiences, enabled);
    } catch (_) {}
  }

  Future<void> _saveGroupByLocationContent(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKeyGroupByLocationContent, enabled);
    } catch (_) {}
  }

  String? _userSpecificPrefsKey(String prefix) {
    final String? userId = _authService.currentUser?.uid;
    if (userId == null || userId.isEmpty) {
      return null;
    }
    return '$prefix$userId';
  }

  Future<void> _persistManualCategoryOrder() async {
    final String? key = _userSpecificPrefsKey(_prefsKeyCategoryOrderPrefix);
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_manualCategoryOrder.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setStringList(key, List<String>.from(_manualCategoryOrder));
      }
    } catch (_) {}
  }

  Future<void> _persistManualColorCategoryOrder() async {
    final String? key =
        _userSpecificPrefsKey(_prefsKeyColorCategoryOrderPrefix);
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_manualColorCategoryOrder.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setStringList(
            key, List<String>.from(_manualColorCategoryOrder));
      }
    } catch (_) {}
  }

  Future<void> _persistUseManualCategoryOrder() async {
    final String? key =
        _userSpecificPrefsKey(_prefsKeyUseManualCategoryOrderPrefix);
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, _useManualCategoryOrder);
    } catch (_) {}
  }

  Future<void> _persistUseManualColorCategoryOrder() async {
    final String? key =
        _userSpecificPrefsKey(_prefsKeyUseManualColorCategoryOrderPrefix);
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, _useManualColorCategoryOrder);
    } catch (_) {}
  }

  List<String> _syncManualOrderList(
    List<String> existing,
    Iterable<String> currentIds,
  ) {
    if (existing.isEmpty) {
      return <String>[];
    }
    final Set<String> currentSet = currentIds.toSet();
    final List<String> filtered = [
      for (final id in existing)
        if (currentSet.contains(id)) id,
    ];
    for (final id in currentIds) {
      if (!filtered.contains(id)) {
        filtered.add(id);
      }
    }
    return filtered;
  }

  List<T> _applyManualOrder<T>({
    required List<T> items,
    required List<String> manualOrderIds,
    required String Function(T) idSelector,
  }) {
    if (manualOrderIds.isEmpty) {
      return items;
    }
    final Map<String, T> itemById = {
      for (final item in items) idSelector(item): item
    };
    final List<T> ordered = [];
    final Set<String> seen = {};
    for (final id in manualOrderIds) {
      final T? item = itemById[id];
      if (item != null) {
        ordered.add(item);
        seen.add(id);
      }
    }
    for (final item in items) {
      final String id = idSelector(item);
      if (!seen.contains(id)) {
        ordered.add(item);
      }
    }
    return ordered;
  }

  void _applyCategorySortInMemory() {
    List<UserCategory> sorted = List<UserCategory>.from(_categories);
    if (_useManualCategoryOrder && _manualCategoryOrder.isNotEmpty) {
      sorted = _applyManualOrder<UserCategory>(
        items: sorted,
        manualOrderIds: _manualCategoryOrder,
        idSelector: (category) => category.id,
      );
    } else {
      sorted.sort((a, b) => _compareCategoriesForSort(a, b, _categorySortType));
    }
    setState(() {
      _categories = sorted;
      _updateLocalOrderIndices();
    });
  }

  void _applyColorCategorySortInMemory() {
    List<ColorCategory> sorted = List<ColorCategory>.from(_colorCategories);
    if (_useManualColorCategoryOrder && _manualColorCategoryOrder.isNotEmpty) {
      sorted = _applyManualOrder<ColorCategory>(
        items: sorted,
        manualOrderIds: _manualColorCategoryOrder,
        idSelector: (category) => category.id,
      );
    } else if (_colorCategorySortType == ColorCategorySortType.alphabetical) {
      sorted
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else {
      sorted.sort((a, b) {
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
    setState(() {
      _colorCategories = sorted;
      _updateLocalColorOrderIndices();
    });
  }

  // --- ADDED: Country grouping state and expansion maps ---
  final Map<String, bool> _countryExpansionExperiences = {};
  final Map<String, bool> _countryExpansionContent = {};
  bool _groupByCountryExperiences = false;
  bool _groupByCountryContent = false;
  // --- ADDED: No-location expansion flags ---
  bool _noLocationExperiencesExpanded = true;
  bool _noLocationContentExpanded = true;
  // --- NEW: Unified grouping flags and state expansion maps ---
  bool _groupByLocationExperiences = false;
  bool _groupByLocationContent = false;
  final Map<String, bool> _stateExpansionExperiences = {};
  final Map<String, bool> _stateExpansionContent = {};
  // ADDED: Track attempted photo refreshes to avoid repeated requests
  final Set<String> _photoRefreshAttempts = {};
  // Maps preview futures cache
  final Map<String, Future<Map<String, dynamic>?>> _mapsPreviewFutures = {};
  // Track filled business data to avoid duplicates but also cache results
  final Map<String, Map<String, dynamic>> _businessDataCache = {};
  // Perf logging toggle
  static const bool _perfLogs = true;
  // Lazy-load Content tab
  bool _contentLoaded = false;
  bool _isContentLoading = false;
  bool _isExperiencesLoading = false;
  bool _contentPreloadRequested = false;

  String _buildSharedByLabel({
    required SharePermission permission,
    required String ownerName,
    ShareAccessLevel? overrideAccessLevel,
  }) {
    final ShareAccessLevel accessLevel =
        overrideAccessLevel ?? permission.accessLevel;
    final String accessText =
        accessLevel == ShareAccessLevel.edit ? 'edit access' : 'view access';
    return 'Shared by $ownerName ($accessText)';
  }

  bool _experienceHasEditAccess(Experience experience) {
    final SharePermission? directPermission =
        _sharedExperiencePermissions[experience.id];
    if (directPermission == null) {
      return true;
    }
    if (directPermission.accessLevel == ShareAccessLevel.edit) {
      return true;
    }

    bool categoryGrantsEdit(String? categoryId) {
      if (categoryId == null || categoryId.isEmpty) {
        return false;
      }
      final SharePermission? permission =
          _sharedCategoryPermissions[categoryId];
      if (permission == null) {
        return false;
      }
      final bool isColorCategory = _sharedCategoryIsColor[categoryId] ?? false;
      if (isColorCategory) {
        return false;
      }
      return permission.accessLevel == ShareAccessLevel.edit;
    }

    if (categoryGrantsEdit(experience.categoryId)) {
      return true;
    }

    for (final otherCategoryId in experience.otherCategories) {
      if (categoryGrantsEdit(otherCategoryId)) {
        return true;
      }
    }

    bool colorCategoryGrantsEdit(String? colorCategoryId) {
      if (colorCategoryId == null || colorCategoryId.isEmpty) {
        return false;
      }
      final SharePermission? permission =
          _sharedCategoryPermissions[colorCategoryId];
      if (permission == null) {
        return false;
      }
      final bool isColorCategory =
          _sharedCategoryIsColor[colorCategoryId] ?? false;
      if (!isColorCategory) {
        return false;
      }
      return permission.accessLevel == ShareAccessLevel.edit;
    }

    if (colorCategoryGrantsEdit(experience.colorCategoryId)) {
      return true;
    }

    return false;
  }

  ShareAccessLevel _effectiveAccessLevelForExperience(Experience experience) {
    return _experienceHasEditAccess(experience)
        ? ShareAccessLevel.edit
        : ShareAccessLevel.view;
  }
  // ADDED: Background refresh helper for photo resource names
  Future<void> _refreshPhotoResourceNameForExperience(
      Experience experience) async {
    try {
      final placeId = experience.location.placeId;
      if (placeId == null || placeId.isEmpty) return;
      final details = await GoogleMapsService().fetchPlaceDetailsData(placeId);
      if (details == null) return;
      String? resourceName;
      if (details['photos'] is List && (details['photos'] as List).isNotEmpty) {
        final first = (details['photos'] as List).first;
        if (first is Map<String, dynamic>) {
          resourceName = first['name'] as String?;
        }
      }
      if (resourceName != null && resourceName.isNotEmpty) {
        final updatedLocation = Location(
          placeId: experience.location.placeId,
          latitude: experience.location.latitude,
          longitude: experience.location.longitude,
          address: experience.location.address,
          city: experience.location.city,
          state: experience.location.state,
          country: experience.location.country,
          zipCode: experience.location.zipCode,
          displayName: experience.location.displayName,
          photoUrl: experience.location.photoUrl, // keep existing URL field
          photoResourceName: resourceName,
          website: experience.location.website,
          rating: experience.location.rating,
          userRatingCount: experience.location.userRatingCount,
        );
        final updated = experience.copyWith(location: updatedLocation);
        await _experienceService.updateExperience(updated);
        if (mounted) {
          // Update local state: replace the experience in lists
          setState(() {
            final idx = _experiences.indexWhere((e) => e.id == experience.id);
            if (idx != -1) {
              _experiences[idx] = updated;
            }
            final fidx =
                _filteredExperiences.indexWhere((e) => e.id == experience.id);
            if (fidx != -1) {
              _filteredExperiences[fidx] = updated;
            }
          });
        }
      }
    } catch (e) {
      // Swallow errors; UI already shows placeholders
      // Optionally log
      // print('Photo refresh failed for experience ${experience.id}: $e');
    }
  }

  // --- ADDED: Filter State ---
  Set<String> _selectedCategoryIds =
      {}; // Empty set means no filter (copied from map_screen)
  Set<String> _selectedColorCategoryIds =
      {}; // Empty set means no filter (copied from map_screen)
  List<Experience> _filteredExperiences =
      []; // To hold filtered experiences for tab 1
  List<GroupedContentItem> _filteredGroupedContentItems =
      []; // To hold filtered content for tab 2
  // --- END Filter State ---

  bool get _hasActiveFilters =>
      _selectedCategoryIds.isNotEmpty || _selectedColorCategoryIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _userEmail = _authService.currentUser?.email ?? 'Guest';
    _tabController = TabController(length: 3, vsync: this);
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
      // Trigger lazy load for Content tab when first viewed
      if (_tabController.index == 2) {
        startContentPreload();
      }
    });
    
    // Set up infinite scroll for Experiences tab
    _experiencesScrollController.addListener(_onExperiencesScroll);
    
    _loadSortPreferences().whenComplete(() {
      _loadData();
    });
    startContentPreload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final CategorySaveProgressNotifier notifier =
        Provider.of<CategorySaveProgressNotifier>(context, listen: false);
    if (!identical(_categorySaveNotifier, notifier)) {
      _categorySaveNotifier?.removeListener(_handleCategorySaveProgress);
      _categorySaveNotifier = notifier;
      _categorySaveNotifier?.addListener(_handleCategorySaveProgress);
      _handleCategorySaveProgress();
    }
  }

  void _handleCategorySaveProgress() {
    final CategorySaveProgressNotifier? notifier = _categorySaveNotifier;
    if (!mounted || notifier == null) {
      return;
    }
    while (true) {
      final CategorySaveMessage? message = notifier.takeNextMessage();
      if (message == null) {
        break;
      }
      final SnackBar snackBar = SnackBar(
        content: Text(message.text),
        backgroundColor:
            message.isError ? Theme.of(context).colorScheme.error : null,
      );
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
      if (!message.isError && message.snapshot != null) {
        unawaited(_applySavedCategorySnapshot(message.snapshot!));
      }
    }
  }

  Future<void> _applySavedCategorySnapshot(
      CategorySaveTaskSnapshot snapshot) async {
    final String? currentUserId = _authService.currentUser?.uid;
    if (currentUserId == null) {
      return;
    }

    await _updateSharedCategoryData(snapshot, currentUserId);
    await _updateSharedExperiencesData(snapshot, currentUserId);

    if (!mounted) {
      return;
    }
    setState(() {
      if (_hasActiveFilters) {
        _applyFiltersAndUpdateLists();
      } else {
        _filteredExperiences = List<Experience>.from(_experiences);
      }
    });
    unawaited(
        _applyExperienceSort(_experienceSortType, applyToFiltered: false));
  }

  Future<void> _updateSharedCategoryData(
      CategorySaveTaskSnapshot snapshot, String currentUserId) async {
    try {
      final SharePermission? permission =
          await _sharingService.getPermissionForUserAndItem(
        userId: currentUserId,
        itemId: snapshot.categoryId,
      );
      if (permission == null) {
        return;
      }
      final List<_SharedCategoryData> resolved =
          await _resolveSharedCategories(<SharePermission>[permission]);
      if (resolved.isEmpty || !mounted) {
        return;
      }
      final _SharedCategoryData data = resolved.first;
      setState(() {
        if (data.isColorCategory) {
          final color = data.colorCategory;
          if (color != null &&
              !_sharedColorCategories.any((c) => c.id == color.id)) {
            _sharedColorCategories = List<ColorCategory>.from(
              _sharedColorCategories,
            )..add(color);
          }
          if (color != null && !_colorCategories.any((c) => c.id == color.id)) {
            _colorCategories = List<ColorCategory>.from(_colorCategories)
              ..add(color);
          }
          _colorCategories = List<ColorCategory>.from(_colorCategories)
            ..sort((a, b) {
              if (_colorCategorySortType ==
                  ColorCategorySortType.alphabetical) {
                return a.name.toLowerCase().compareTo(b.name.toLowerCase());
              }
              final tsA = a.lastUsedTimestamp;
              final tsB = b.lastUsedTimestamp;
              if (tsA == null && tsB == null) return 0;
              if (tsA == null) return 1;
              if (tsB == null) return -1;
              return tsB.compareTo(tsA);
            });
        } else {
          final category = data.userCategory;
          if (category != null &&
              !_sharedCategories.any((c) => c.id == category.id)) {
            _sharedCategories = List<UserCategory>.from(_sharedCategories)
              ..add(category);
          }
          if (category != null &&
              !_categories.any((c) => c.id == category.id)) {
            _categories = List<UserCategory>.from(_categories)..add(category);
          }
          _categories = List<UserCategory>.from(_categories)
            ..sort(
                (a, b) => _compareCategoriesForSort(a, b, _categorySortType));
          _updateLocalOrderIndices();
        }
        _sharedCategoryPermissions[data.categoryId] = data.permission;
        _sharedCategoryIsColor[data.categoryId] = data.isColorCategory;
        final Set<String> categoryIdsNow = _currentCategoryIdSet();
        final Set<String> colorIdsNow = _currentColorCategoryIdSet();
        _sharedExperiences = _filterExperiencesWithAssignments(
          _sharedExperiences,
          categoryIdsNow,
          colorIdsNow,
        );
        _experiences = _filterExperiencesWithAssignments(
          _experiences,
          categoryIdsNow,
          colorIdsNow,
        );
        _filteredExperiences = _filterExperiencesWithAssignments(
          _filteredExperiences,
          categoryIdsNow,
          colorIdsNow,
        );
      });
    } catch (e) {
      debugPrint(
          'Collections: failed to update shared category after save: $e');
    }
  }

  Future<void> _updateSharedExperiencesData(
      CategorySaveTaskSnapshot snapshot, String currentUserId) async {
    if (snapshot.experienceIds.isEmpty) {
      return;
    }
    try {
      final List<Future<SharePermission?>> futures = snapshot.experienceIds
          .map((expId) => _sharingService.getPermissionForUserAndItem(
                userId: currentUserId,
                itemId: expId,
              ))
          .toList();
      final List<SharePermission> permissions =
          (await Future.wait(futures)).whereType<SharePermission>().toList();
      if (permissions.isEmpty) {
        return;
      }
      final List<_SharedExperienceData> resolved =
          await _resolveSharedExperiences(permissions);
      if (!mounted || resolved.isEmpty) {
        return;
      }
      final Set<String> categoryIds = _currentCategoryIdSet();
      final Set<String> colorCategoryIds = _currentColorCategoryIdSet();
      setState(() {
        for (final data in resolved) {
          final experience = data.experience;
          _sharedExperiencePermissions[experience.id] = data.permission;
          if (!_sharedExperiences.any((e) => e.id == experience.id)) {
            _sharedExperiences = List<Experience>.from(_sharedExperiences)
              ..add(experience);
          }
        }
        _sharedExperiences = _filterExperiencesWithAssignments(
          _sharedExperiences,
          categoryIds,
          colorCategoryIds,
        );
        _experiences = _combineExperiencesWithShared(_experiences);
        _experiences = _filterExperiencesWithAssignments(
          _experiences,
          categoryIds,
          colorCategoryIds,
        );
        _filteredExperiences = _filterExperiencesWithAssignments(
          _filteredExperiences,
          categoryIds,
          colorCategoryIds,
        );
      });
    } catch (e) {
      debugPrint(
          'Collections: failed to update shared experiences after save: $e');
    }
  }

  Widget _buildCategorySaveProgressTile(
      BuildContext context, CategorySaveTask task) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color background = scheme.surfaceVariant.withOpacity(0.6);
    final double? progress = task.progress;
    final int totalExperiences = task.totalUnits > 0 ? task.totalUnits - 1 : 0;
    final int rawCompletedExperiences =
        task.completedUnits > 0 ? task.completedUnits - 1 : 0;
    final int completedExperiences = rawCompletedExperiences < 0
        ? 0
        : (rawCompletedExperiences > totalExperiences
            ? totalExperiences
            : rawCompletedExperiences);
    final bool showExperienceCounts = totalExperiences > 0;

    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.primary,
                  value: progress,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Saving ' + task.categoryName + ' Category',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (showExperienceCounts)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                '$completedExperiences of $totalExperiences experiences saved',
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            color: scheme.primary,
            backgroundColor: scheme.surfaceVariant.withOpacity(0.3),
          ),
        ],
      ),
    );
  }

  void _onExperiencesScroll() {
    if (_experiencesScrollController.position.pixels >=
        _experiencesScrollController.position.maxScrollExtent * 0.8) {
      // When user scrolls to 80% of the list, load more
      if (_hasMoreExperiences && !_isLoadingMoreExperiences) {
        _loadExperiencesPage(isInitialLoad: false);
      }
    }
  }

  @override
  void dispose() {
    _categorySaveNotifier?.removeListener(_handleCategorySaveProgress);
    _categorySaveNotifier = null;
    _tabController.dispose();
    _searchController.dispose();
    _experiencesScrollController.dispose();
    super.dispose();
  }

  // Build fully dynamic grouping for Experiences tab (Country -> L1..L7 -> LOC)
  List<Map<String, Object>> _buildDynamicExperienceGrouping() {
    String n(String? s) => (s ?? '').trim();
    // Collect per-country paths
    final Map<String, List<Map<String, dynamic>>> byCountry = {};
    final List<Experience> noLoc = [];
    for (final exp in _filteredExperiences) {
      final c = n(exp.location.country);
      String l1 = n(exp.location.state);
      final l2 = n(exp.location.administrativeAreaLevel2);
      final l3 = n(exp.location.administrativeAreaLevel3);
      final l4 = n(exp.location.administrativeAreaLevel4);
      final l5 = n(exp.location.administrativeAreaLevel5);
      final l6 = n(exp.location.administrativeAreaLevel6);
      final l7 = n(exp.location.administrativeAreaLevel7);
      String loc = n(exp.location.city);
      final displayName = n(exp.location.displayName);
      // Fallbacks: if state or city missing, use displayName at that level
      if (l1.isEmpty && displayName.isNotEmpty) {
        l1 = displayName;
      }
      if (loc.isEmpty && displayName.isNotEmpty) {
        loc = displayName;
      }
      if ([c, l1, l2, l3, l4, l5, l6, l7, loc].every((v) => v.isEmpty)) {
        noLoc.add(exp);
        continue;
      }
      final keyC = c.toLowerCase();
      byCountry.putIfAbsent(keyC, () => []);
      byCountry[keyC]!.add({
        'labels': {
          'C': c,
          'L1': l1,
          'L2': l2,
          'L3': l3,
          'L4': l4,
          'L5': l5,
          'L6': l6,
          'L7': l7,
          'LOC': loc,
        },
        'data': exp,
      });
    }

    String sortKeyFor(String s) => s.toLowerCase();
    final List<Map<String, Object>> flat = [];
    // Precompute global index for distance-based group ordering
    final Map<String, int> expIndexMap = {};
    if (_experienceSortType == ExperienceSortType.distanceFromMe) {
      for (int i = 0; i < _filteredExperiences.length; i++) {
        expIndexMap[_filteredExperiences[i].id] = i;
      }
    }
    final countries = byCountry.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty && b.isEmpty) return 0;
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        if (_experienceSortType == ExperienceSortType.mostRecent) {
          DateTime maxA = DateTime.fromMillisecondsSinceEpoch(0);
          for (final p in byCountry[a]!) {
            final d = (p['data'] as Experience).updatedAt;
            if (d.isAfter(maxA)) maxA = d;
          }
          DateTime maxB = DateTime.fromMillisecondsSinceEpoch(0);
          for (final p in byCountry[b]!) {
            final d = (p['data'] as Experience).updatedAt;
            if (d.isAfter(maxB)) maxB = d;
          }
          return maxB.compareTo(maxA);
        } else if (_experienceSortType == ExperienceSortType.alphabetical ||
            _experienceSortType == ExperienceSortType.city) {
          final dispA =
              (byCountry[a]!.first['labels'] as Map<String, String?>)['C'] ??
                  '';
          final dispB =
              (byCountry[b]!.first['labels'] as Map<String, String?>)['C'] ??
                  '';
          if (dispA.isEmpty && dispB.isEmpty) return 0;
          if (dispA.isEmpty) return 1;
          if (dispB.isEmpty) return -1;
          return dispA.toLowerCase().compareTo(dispB.toLowerCase());
        } else {
          // distanceFromMe
          int minA = 1 << 30;
          for (final p in byCountry[a]!) {
            final idx = expIndexMap[(p['data'] as Experience).id];
            if (idx != null && idx < minA) minA = idx;
          }
          int minB = 1 << 30;
          for (final p in byCountry[b]!) {
            final idx = expIndexMap[(p['data'] as Experience).id];
            if (idx != null && idx < minB) minB = idx;
          }
          return minA.compareTo(minB);
        }
      });
    for (final ck in countries) {
      final dispCountry =
          (byCountry[ck]!.first['labels'] as Map<String, String?>)['C'] ??
              'Unknown country';
      final countryKey = 'C:$ck';
      flat.add({'header': dispCountry, 'level': 'country', 'key': countryKey});
      _locationExpansionExperiences.putIfAbsent(countryKey, () => false);
      if (!(_locationExpansionExperiences[countryKey] ?? false)) continue;

      // Determine which levels exist in this country
      final levels = ['L1', 'L2', 'L3', 'L4', 'L5', 'L6', 'L7', 'LOC'];
      final List<String> presentLevels = levels.where((lvl) {
        return byCountry[ck]!.any(
            (p) => n((p['labels'] as Map<String, String?>)[lvl]).isNotEmpty);
      }).toList();

      // Recursive build
      void buildLevel(
          String prefixKey, String level, List<Map<String, dynamic>> items) {
        // Find the next present level starting from the requested level
        String useLevel = level;
        while (!presentLevels.contains(useLevel)) {
          useLevel = _nextLevel(useLevel);
          if (useLevel == '__end__') break;
        }
        // If we ran out of levels, output items as leaf
        if (useLevel == '__end__') {
          final leaf = items.map((p) => p['data'] as Experience).toList();
          if (_experienceSortType == ExperienceSortType.alphabetical) {
            leaf.sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          } else if (_experienceSortType == ExperienceSortType.mostRecent) {
            leaf.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          }
          for (final e in leaf) flat.add({'item': e, 'key': prefixKey});
          return;
        }
        // Group by the resolved present level
        final Map<String, List<Map<String, dynamic>>> buckets = {};
        for (final p in items) {
          final label = n((p['labels'] as Map<String, String?>)[useLevel]);
          final k = label.toLowerCase();
          buckets.putIfAbsent(k, () => []).add(p);
        }
        final keys = buckets.keys.toList()
          ..sort((a, b) {
            if (_experienceSortType == ExperienceSortType.mostRecent) {
              DateTime maxA = DateTime.fromMillisecondsSinceEpoch(0);
              for (final p in buckets[a]!) {
                final d = (p['data'] as Experience).updatedAt;
                if (d.isAfter(maxA)) maxA = d;
              }
              DateTime maxB = DateTime.fromMillisecondsSinceEpoch(0);
              for (final p in buckets[b]!) {
                final d = (p['data'] as Experience).updatedAt;
                if (d.isAfter(maxB)) maxB = d;
              }
              // Unknown/empty last
              if (a.isEmpty && b.isEmpty) return 0;
              if (a.isEmpty) return 1;
              if (b.isEmpty) return -1;
              return maxB.compareTo(maxA);
            } else if (_experienceSortType == ExperienceSortType.alphabetical ||
                _experienceSortType == ExperienceSortType.city) {
              final dispA = n((buckets[a]!.first['labels']
                  as Map<String, String?>)[useLevel]);
              final dispB = n((buckets[b]!.first['labels']
                  as Map<String, String?>)[useLevel]);
              if (dispA.isEmpty && dispB.isEmpty) return 0;
              if (dispA.isEmpty) return 1;
              if (dispB.isEmpty) return -1;
              return dispA.toLowerCase().compareTo(dispB.toLowerCase());
            } else {
              // distanceFromMe
              int minA = 1 << 30;
              for (final p in buckets[a]!) {
                final idx = expIndexMap[(p['data'] as Experience).id];
                if (idx != null && idx < minA) minA = idx;
              }
              int minB = 1 << 30;
              for (final p in buckets[b]!) {
                final idx = expIndexMap[(p['data'] as Experience).id];
                if (idx != null && idx < minB) minB = idx;
              }
              if (a.isEmpty && b.isEmpty) return 0;
              if (a.isEmpty) return 1;
              if (b.isEmpty) return -1;
              return minA.compareTo(minB);
            }
          });
        for (final k in keys) {
          final disp = n(
              (buckets[k]!.first['labels'] as Map<String, String?>)[useLevel]);
          if (disp.isEmpty) {
            // Missing level for these items: drop deeper to next present level/leaf
            buildLevel(prefixKey, _nextLevel(useLevel), buckets[k]!);
          } else {
            final key = '$prefixKey|$useLevel:${k}';
            flat.add({'header': disp, 'level': useLevel, 'key': key});
            _locationExpansionExperiences.putIfAbsent(key, () => false);
            if (!(_locationExpansionExperiences[key] ?? false)) continue;
            buildLevel(key, _nextLevel(useLevel), buckets[k]!);
          }
        }
      }

      buildLevel(countryKey, 'L1', byCountry[ck]!);
    }

    if (noLoc.isNotEmpty) {
      final key = 'C:noloc';
      flat.add(
          {'header': 'No Location Specified', 'level': 'country', 'key': key});
      _locationExpansionExperiences.putIfAbsent(key, () => false);
      if (_locationExpansionExperiences[key] ?? false) {
        final items = List<Experience>.from(noLoc);
        if (_experienceSortType == ExperienceSortType.alphabetical) {
          items.sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        } else if (_experienceSortType == ExperienceSortType.mostRecent) {
          items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        }
        for (final e in items) flat.add({'item': e, 'key': key});
      }
    }
    return flat;
  }
  // Build fully dynamic grouping for Content tab (Country -> L1..L7 -> LOC)
  List<Map<String, Object>> _buildDynamicContentGrouping() {
    String n(String? s) => (s ?? '').trim();
    final Map<String, List<Map<String, dynamic>>> byCountry = {};
    final List<GroupedContentItem> noLoc = [];

    for (final group in _filteredGroupedContentItems) {
      // Exclusive No-Location rule: if any associated experience lacks all levels, put this group only under No Location
      final bool anyNoLoc = group.associatedExperiences.any((exp) {
        final c = n(exp.location.country);
        String l1 = n(exp.location.state);
        final l2 = n(exp.location.administrativeAreaLevel2);
        final l3 = n(exp.location.administrativeAreaLevel3);
        final l4 = n(exp.location.administrativeAreaLevel4);
        final l5 = n(exp.location.administrativeAreaLevel5);
        final l6 = n(exp.location.administrativeAreaLevel6);
        final l7 = n(exp.location.administrativeAreaLevel7);
        String loc = n(exp.location.city);
        final displayName = n(exp.location.displayName);
        if (l1.isEmpty && displayName.isNotEmpty) {
          l1 = displayName;
        }
        if (loc.isEmpty && displayName.isNotEmpty) {
          loc = displayName;
        }
        return [c, l1, l2, l3, l4, l5, l6, l7, loc].every((v) => v.isEmpty);
      });
      if (anyNoLoc) {
        noLoc.add(group);
        continue;
      }

      // Otherwise, place this group under all location paths for its associated experiences
      for (final exp in group.associatedExperiences) {
        final c = n(exp.location.country);
        if (c.isEmpty)
          continue; // without country, treat as noloc but we already handled
        String l1 = n(exp.location.state);
        final l2 = n(exp.location.administrativeAreaLevel2);
        final l3 = n(exp.location.administrativeAreaLevel3);
        final l4 = n(exp.location.administrativeAreaLevel4);
        final l5 = n(exp.location.administrativeAreaLevel5);
        final l6 = n(exp.location.administrativeAreaLevel6);
        final l7 = n(exp.location.administrativeAreaLevel7);
        String loc = n(exp.location.city);
        final displayName = n(exp.location.displayName);
        if (l1.isEmpty && displayName.isNotEmpty) {
          l1 = displayName;
        }
        if (loc.isEmpty && displayName.isNotEmpty) {
          loc = displayName;
        }

        final keyC = c.toLowerCase();
        byCountry.putIfAbsent(keyC, () => []);
        byCountry[keyC]!.add({
          'labels': {
            'C': c,
            'L1': l1,
            'L2': l2,
            'L3': l3,
            'L4': l4,
            'L5': l5,
            'L6': l6,
            'L7': l7,
            'LOC': loc,
          },
          'gid': group.mediaItem.id,
          'data': group,
        });
      }
    }

    String sortKeyFor(String s) => s.toLowerCase();
    final List<Map<String, Object>> flat = [];
    // Precompute global index for distance-based group ordering (by content list order)
    final Map<String, int> contentIndexMap = {};
    if (_contentSortType == ContentSortType.distanceFromMe) {
      for (int i = 0; i < _filteredGroupedContentItems.length; i++) {
        contentIndexMap[_filteredGroupedContentItems[i].mediaItem.id] = i;
      }
    }
    final countries = byCountry.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty && b.isEmpty) return 0;
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        if (_contentSortType == ContentSortType.mostRecent) {
          DateTime maxA = DateTime.fromMillisecondsSinceEpoch(0);
          for (final p in byCountry[a]!) {
            final d = (p['data'] as GroupedContentItem).mediaItem.createdAt;
            if (d.isAfter(maxA)) maxA = d;
          }
          DateTime maxB = DateTime.fromMillisecondsSinceEpoch(0);
          for (final p in byCountry[b]!) {
            final d = (p['data'] as GroupedContentItem).mediaItem.createdAt;
            if (d.isAfter(maxB)) maxB = d;
          }
          return maxB.compareTo(maxA);
        } else if (_contentSortType == ContentSortType.alphabetical ||
            _contentSortType == ContentSortType.city) {
          final dispA =
              (byCountry[a]!.first['labels'] as Map<String, String?>)['C'] ??
                  '';
          final dispB =
              (byCountry[b]!.first['labels'] as Map<String, String?>)['C'] ??
                  '';
          if (dispA.isEmpty && dispB.isEmpty) return 0;
          if (dispA.isEmpty) return 1;
          if (dispB.isEmpty) return -1;
          return dispA.toLowerCase().compareTo(dispB.toLowerCase());
        } else {
          // distanceFromMe
          int minA = 1 << 30;
          for (final p in byCountry[a]!) {
            final idx = contentIndexMap[(p['gid'] as String?) ??
                (p['data'] as GroupedContentItem).mediaItem.id];
            if (idx != null && idx < minA) minA = idx;
          }
          int minB = 1 << 30;
          for (final p in byCountry[b]!) {
            final idx = contentIndexMap[(p['gid'] as String?) ??
                (p['data'] as GroupedContentItem).mediaItem.id];
            if (idx != null && idx < minB) minB = idx;
          }
          return minA.compareTo(minB);
        }
      });
    for (final ck in countries) {
      final dispCountry =
          (byCountry[ck]!.first['labels'] as Map<String, String?>)['C'] ??
              'Unknown country';
      final countryKey = 'C:$ck';
      flat.add({'header': dispCountry, 'level': 'country', 'key': countryKey});
      _locationExpansionContent.putIfAbsent(countryKey, () => false);
      if (!(_locationExpansionContent[countryKey] ?? false)) continue;

      // Determine which levels exist in this country
      final levels = ['L1', 'L2', 'L3', 'L4', 'L5', 'L6', 'L7', 'LOC'];
      final List<String> presentLevels = levels.where((lvl) {
        return byCountry[ck]!.any(
            (p) => n((p['labels'] as Map<String, String?>)[lvl]).isNotEmpty);
      }).toList();

      void buildLevel(
          String prefixKey, String level, List<Map<String, dynamic>> items) {
        // Find the next present level starting from the requested level
        String useLevel = level;
        while (!presentLevels.contains(useLevel)) {
          useLevel = _nextLevel(useLevel);
          if (useLevel == '__end__') break;
        }
        // If we ran out of levels, this branch is a leaf: dedupe and sort
        if (useLevel == '__end__') {
          final Map<String, GroupedContentItem> seen = {};
          for (final p in items) {
            final gid = p['gid'] as String? ??
                (p['data'] as GroupedContentItem).mediaItem.id;
            seen.putIfAbsent(gid, () => p['data'] as GroupedContentItem);
          }
          final leaf = seen.values.toList();
          if (_contentSortType == ContentSortType.alphabetical) {
            leaf.sort((a, b) {
              final an = a.associatedExperiences.isNotEmpty
                  ? a.associatedExperiences.first.name.toLowerCase()
                  : '';
              final bn = b.associatedExperiences.isNotEmpty
                  ? b.associatedExperiences.first.name.toLowerCase()
                  : '';
              return an.compareTo(bn);
            });
          } else {
            leaf.sort((a, b) =>
                b.mediaItem.createdAt.compareTo(a.mediaItem.createdAt));
          }
          int ordinal = 0;
          for (final g in leaf) {
            flat.add({'item': g, 'pathKey': prefixKey, 'ordinal': ordinal});
            ordinal++;
          }
          return;
        }
        // Group by the resolved present level
        final Map<String, List<Map<String, dynamic>>> buckets = {};
        for (final p in items) {
          final label = n((p['labels'] as Map<String, String?>)[useLevel]);
          final k = label.toLowerCase();
          buckets.putIfAbsent(k, () => []).add(p);
        }
        final keys = buckets.keys.toList()
          ..sort((a, b) {
            if (_contentSortType == ContentSortType.mostRecent) {
              DateTime maxA = DateTime.fromMillisecondsSinceEpoch(0);
              for (final p in buckets[a]!) {
                final d = (p['data'] as GroupedContentItem).mediaItem.createdAt;
                if (d.isAfter(maxA)) maxA = d;
              }
              DateTime maxB = DateTime.fromMillisecondsSinceEpoch(0);
              for (final p in buckets[b]!) {
                final d = (p['data'] as GroupedContentItem).mediaItem.createdAt;
                if (d.isAfter(maxB)) maxB = d;
              }
              if (a.isEmpty && b.isEmpty) return 0;
              if (a.isEmpty) return 1;
              if (b.isEmpty) return -1;
              return maxB.compareTo(maxA);
            } else if (_contentSortType == ContentSortType.alphabetical ||
                _contentSortType == ContentSortType.city) {
              final dispA = n((buckets[a]!.first['labels']
                  as Map<String, String?>)[useLevel]);
              final dispB = n((buckets[b]!.first['labels']
                  as Map<String, String?>)[useLevel]);
              if (dispA.isEmpty && dispB.isEmpty) return 0;
              if (dispA.isEmpty) return 1;
              if (dispB.isEmpty) return -1;
              return dispA.toLowerCase().compareTo(dispB.toLowerCase());
            } else {
              // distanceFromMe
              int minA = 1 << 30;
              for (final p in buckets[a]!) {
                final gid = (p['gid'] as String?) ??
                    (p['data'] as GroupedContentItem).mediaItem.id;
                final idx = contentIndexMap[gid];
                if (idx != null && idx < minA) minA = idx;
              }
              int minB = 1 << 30;
              for (final p in buckets[b]!) {
                final gid = (p['gid'] as String?) ??
                    (p['data'] as GroupedContentItem).mediaItem.id;
                final idx = contentIndexMap[gid];
                if (idx != null && idx < minB) minB = idx;
              }
              if (a.isEmpty && b.isEmpty) return 0;
              if (a.isEmpty) return 1;
              if (b.isEmpty) return -1;
              return minA.compareTo(minB);
            }
          });
        for (final k in keys) {
          final disp = n(
              (buckets[k]!.first['labels'] as Map<String, String?>)[useLevel]);
          if (disp.isEmpty) {
            buildLevel(prefixKey, _nextLevel(useLevel), buckets[k]!);
          } else {
            final key = '$prefixKey|$useLevel:${k}';
            flat.add({'header': disp, 'level': useLevel, 'key': key});
            _locationExpansionContent.putIfAbsent(key, () => false);
            if (!(_locationExpansionContent[key] ?? false)) continue;
            buildLevel(key, _nextLevel(useLevel), buckets[k]!);
          }
        }
      }

      buildLevel(countryKey, 'L1', byCountry[ck]!);
    }

    if (noLoc.isNotEmpty) {
      final key = 'C:noloc';
      flat.add(
          {'header': 'No Location Specified', 'level': 'country', 'key': key});
      _locationExpansionContent.putIfAbsent(key, () => false);
      if (_locationExpansionContent[key] ?? false) {
        final items = List<GroupedContentItem>.from(noLoc);
        if (_contentSortType == ContentSortType.alphabetical) {
          items.sort((a, b) {
            final an = a.associatedExperiences.isNotEmpty
                ? a.associatedExperiences.first.name.toLowerCase()
                : '';
            final bn = b.associatedExperiences.isNotEmpty
                ? b.associatedExperiences.first.name.toLowerCase()
                : '';
            return an.compareTo(bn);
          });
        } else {
          items.sort(
              (a, b) => b.mediaItem.createdAt.compareTo(a.mediaItem.createdAt));
        }
        int ordinal = 0;
        for (final g in items) {
          flat.add({'item': g, 'pathKey': key, 'ordinal': ordinal});
          ordinal++;
        }
      }
    }

    return flat;
  }

  String _nextLevel(String level) {
    const order = ['L1', 'L2', 'L3', 'L4', 'L5', 'L6', 'L7', 'LOC'];
    final i = order.indexOf(level);
    return i >= 0 && i < order.length - 1 ? order[i + 1] : '__end__';
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    final totalSw = Stopwatch()..start();

    final userId = _authService.currentUser?.uid;
    try {
      final fetchSw = Stopwatch()..start();
      final results = await Future.wait([
        _experienceService.getUserCategories(includeSharedEditable: true),
        _experienceService.getUserColorCategories(includeSharedEditable: true),
      ]);
      if (_perfLogs) {
        fetchSw.stop();
        final ms = fetchSw.elapsedMilliseconds;
        print(
            '[Perf][Collections] Firestore fetch (categories, color categories) took ${ms}ms');
      }

      final List<UserCategory> ownCategories = results[0] as List<UserCategory>;
      final List<ColorCategory> ownColorCategories =
          results[1] as List<ColorCategory>;

      List<_SharedCategoryData> sharedCategoryData = [];
      List<_SharedExperienceData> sharedExperienceData = [];
      final Set<String> ownedSharedCategoryIds = {};
      final Set<String> ownedSharedColorCategoryIds = {};
      final Set<String> ownedSharedExperienceIds = {};

      if (userId != null) {
        try {
          print('[Collections] Loading shared permissions for user: $userId');
          final sharedPermissions =
              await _sharingService.getSharedItemsForUser(userId);
          print(
              '[Collections] Found ${sharedPermissions.length} shared permissions');
          if (sharedPermissions.isNotEmpty) {
            // Prefetch all unique owner names in one batch
            final uniqueOwnerIds =
                sharedPermissions.map((p) => p.ownerUserId).toSet();
            await _prefetchOwnerDisplayNames(uniqueOwnerIds);

            final categoryPermissions = sharedPermissions
                .where((perm) => perm.itemType == ShareableItemType.category)
                .toList();
            final experiencePermissions = sharedPermissions
                .where((perm) => perm.itemType == ShareableItemType.experience)
                .toList();

            print(
                '[Collections] Category permissions: ${categoryPermissions.length}');
            print(
                '[Collections] Experience permissions: ${experiencePermissions.length}');

            if (categoryPermissions.isNotEmpty) {
              print('[Collections] Resolving shared categories...');
              sharedCategoryData =
                  await _resolveSharedCategories(categoryPermissions);
              print(
                  '[Collections] Resolved ${sharedCategoryData.length} shared categories');
            }
            // OPTIMIZATION: Skip direct experience resolution if we have many
            // The broad fetch in _combineSharedExperiences will get them via sharedWithUserIds
            if (experiencePermissions.isNotEmpty && experiencePermissions.length < 100) {
              print('[Collections] Resolving ${experiencePermissions.length} shared experiences (small set)...');
              sharedExperienceData =
                  await _resolveSharedExperiences(experiencePermissions);
              print(
                  '[Collections] Resolved ${sharedExperienceData.length} shared experiences');
            } else if (experiencePermissions.isNotEmpty) {
              print('[Collections] Skipping direct experience resolution (${experiencePermissions.length} items) - will use broad fetch instead');
            }
          }
        } catch (e) {
          print('[Collections] Failed to load shared permissions: $e');
        }

        try {
          print(
              '[Collections] Loading owned share permissions for user: $userId');
          final ownedPermissions =
              await _sharingService.getOwnedSharePermissions(userId);
          print(
              '[Collections] Found ${ownedPermissions.length} owned share permissions');
          if (ownedPermissions.isNotEmpty) {
            final Set<String> ownedCategoryIds = {};
            final Set<String> ownedExperienceIds = {};
            for (final permission in ownedPermissions) {
              if (permission.itemType == ShareableItemType.category) {
                ownedCategoryIds.add(permission.itemId);
              } else if (permission.itemType == ShareableItemType.experience) {
                ownedExperienceIds.add(permission.itemId);
              }
            }

            final Set<String> ownCategoryIds =
                ownCategories.map((c) => c.id).toSet();
            final Set<String> ownColorCategoryIds =
                ownColorCategories.map((c) => c.id).toSet();

            for (final id in ownedCategoryIds) {
              if (ownCategoryIds.contains(id)) {
                ownedSharedCategoryIds.add(id);
              } else if (ownColorCategoryIds.contains(id)) {
                ownedSharedColorCategoryIds.add(id);
              }
            }

            ownedSharedExperienceIds.addAll(ownedExperienceIds);
          }
        } catch (e) {
          print('[Collections] Failed to load owned share permissions: $e');
        }
      }

      final List<UserCategory> sharedUserCategories = [
        for (final data in sharedCategoryData)
          if (!data.isColorCategory && data.userCategory != null)
            data.userCategory!
      ];
      final List<ColorCategory> sharedColorCategories = [
        for (final data in sharedCategoryData)
          if (data.isColorCategory && data.colorCategory != null)
            data.colorCategory!
      ];

      final Map<String, SharePermission> categoryPermissionMap = {};
      final Map<String, bool> sharedCategoryIsColorMap = {};
      for (final data in sharedCategoryData) {
        final id = data.categoryId;
        if (id.isEmpty) continue;
        categoryPermissionMap[id] = data.permission;
        sharedCategoryIsColorMap[id] = data.isColorCategory;
      }

      final Map<String, _SharedExperienceData> combinedSharedExperienceData =
          await _combineSharedExperiences(
        directSharedExperiences: sharedExperienceData,
        sharedCategoryData: sharedCategoryData,
      );
      print(
          '[Collections] Combined shared experiences total: ${combinedSharedExperienceData.length}');

      final Map<String, SharePermission> experiencePermissionMap = {};
      final List<Experience> sharedExperiences = [];
      combinedSharedExperienceData
          .forEach((experienceId, _SharedExperienceData data) {
        experiencePermissionMap[experienceId] = data.permission;
        sharedExperiences.add(data.experience);
      });

      print(
          '[Collections] DEBUG: Total shared experiences from categories: ${sharedExperiences.length}');
      print(
          '[Collections] DEBUG: Experience IDs: ${sharedExperiences.map((e) => e.id).take(5).join(", ")}...');
      print(
          '[Collections] DEBUG: Experience names: ${sharedExperiences.map((e) => e.name).take(5).join(", ")}...');

      final List<UserCategory> combinedCategories = List.of(ownCategories);
      for (final shared in sharedUserCategories) {
        if (!combinedCategories.any((c) => c.id == shared.id)) {
          combinedCategories.add(shared);
        }
      }

      final List<ColorCategory> combinedColorCategories =
          List.of(ownColorCategories);
      for (final shared in sharedColorCategories) {
        if (!combinedColorCategories.any((c) => c.id == shared.id)) {
          combinedColorCategories.add(shared);
        }
      }

      final List<String> combinedCategoryIdList =
          combinedCategories.map((c) => c.id).toList();
      final List<String> combinedColorCategoryIdList =
          combinedColorCategories.map((c) => c.id).toList();
      final List<String> updatedManualCategoryOrder =
          _syncManualOrderList(_manualCategoryOrder, combinedCategoryIdList);
      final List<String> updatedManualColorCategoryOrder = _syncManualOrderList(
          _manualColorCategoryOrder, combinedColorCategoryIdList);
      final Set<String> combinedCategoryIds = combinedCategoryIdList.toSet();
      final Set<String> combinedColorCategoryIds =
          combinedColorCategoryIdList.toSet();

      print(
          '[Collections] DEBUG: Combined categories count: ${combinedCategoryIds.length}');
      print(
          '[Collections] DEBUG: Combined color categories count: ${combinedColorCategoryIds.length}');
      print(
          '[Collections] DEBUG: Combined category IDs: ${combinedCategoryIds.take(5).join(", ")}...');

      // Filter shared experiences, but pass the new permission map so filtering can check it
      final List<Experience> filteredSharedExperiences =
          _filterExperiencesWithAssignments(
        sharedExperiences,
        combinedCategoryIds,
        combinedColorCategoryIds,
        permissionsToCheck: experiencePermissionMap,
      );

      print(
          '[Collections] DEBUG: After filtering - Shared experiences: ${filteredSharedExperiences.length}');
      if (sharedExperiences.length != filteredSharedExperiences.length) {
        print(
            '[Collections] DEBUG WARNING: ${sharedExperiences.length - filteredSharedExperiences.length} experiences were filtered out!');
        final filtered = sharedExperiences
            .where((e) => !filteredSharedExperiences.contains(e))
            .toList();
        for (final exp in filtered.take(3)) {
          print(
              '[Collections] DEBUG: Filtered out: "${exp.name}" - categoryId: ${exp.categoryId}, colorCategoryId: ${exp.colorCategoryId}');
        }
      }

      final bool hadFilters = _hasActiveFilters;

      if (mounted) {
        setState(() {
          _manualCategoryOrder = List<String>.from(updatedManualCategoryOrder);
          _manualColorCategoryOrder =
              List<String>.from(updatedManualColorCategoryOrder);
          _categories = combinedCategories;
          _sharedCategories = sharedUserCategories;
          _colorCategories = combinedColorCategories;
          _sharedColorCategories = sharedColorCategories;
          _sharedCategoryPermissions
            ..clear()
            ..addAll(categoryPermissionMap);
          _sharedCategoryIsColor
            ..clear()
            ..addAll(sharedCategoryIsColorMap);
          _sharedExperiencePermissions
            ..clear()
            ..addAll(experiencePermissionMap);
          _sharedExperiences = filteredSharedExperiences;
          final List<Experience> combinedExperienceList =
              _combineExperiencesWithShared(_experiences);
          _experiences = _filterExperiencesWithAssignments(
            combinedExperienceList,
            combinedCategoryIds,
            combinedColorCategoryIds,
          );
          _filteredExperiences = _filterExperiencesWithAssignments(
            _filteredExperiences,
            combinedCategoryIds,
            combinedColorCategoryIds,
          );
          _isLoading = false;
          _selectedCategory = null;
          _selectedColorCategory = null;
          _contentLoaded = false;
          // Reset pagination state
          _lastExperienceDoc = null;
          _hasMoreExperiences = true;
        });
        if (_useManualCategoryOrder && _manualCategoryOrder.isNotEmpty) {
          unawaited(_persistManualCategoryOrder());
        }
        if (_useManualColorCategoryOrder &&
            _manualColorCategoryOrder.isNotEmpty) {
          unawaited(_persistManualColorCategoryOrder());
        }
        // Apply persisted sorts immediately to combined lists so shared items are included
        _applyCategorySortInMemory();
        _applyColorCategorySortInMemory();
        // Note: Experience sorting is now handled by pagination (_loadExperiencesPage)
        // which uses server-side ordering. Skip the old sort logic here.
        if (_perfLogs) {
          totalSw.stop();
          print(
              '[Perf][Collections] _loadData total time ${totalSw.elapsedMilliseconds}ms');
        }
      }

      if (userId != null) {
        _loadExperiences(userId);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  List<Experience> _combineExperiencesWithShared(List<Experience> base) {
    final Map<String, Experience> experienceById = {
      for (final exp in base) exp.id: exp
    };
    for (final shared in _sharedExperiences) {
      experienceById.putIfAbsent(shared.id, () => shared);
    }
    return experienceById.values.toList();
  }

  bool _experienceHasValidAssignment(
    Experience experience,
    Set<String> categoryIds,
    Set<String> colorCategoryIds, {
    Map<String, SharePermission>? permissionsToCheck,
  }) {
    // First check: if this experience was fetched from a shared category,
    // it should always be visible regardless of its color category assignment
    // Check both the instance variable and the optional parameter
    if (_sharedExperiencePermissions.containsKey(experience.id)) {
      return true;
    }
    if (permissionsToCheck != null &&
        permissionsToCheck.containsKey(experience.id)) {
      return true;
    }

    final String? primary = experience.categoryId;
    if (primary != null &&
        primary.isNotEmpty &&
        categoryIds.contains(primary)) {
      return true;
    }

    for (final String otherId in experience.otherCategories) {
      if (categoryIds.contains(otherId)) {
        return true;
      }
    }

    final String? colorId = experience.colorCategoryId;
    if (colorId != null &&
        colorId.isNotEmpty &&
        colorCategoryIds.contains(colorId)) {
      return true;
    }

    return false;
  }

  List<Experience> _filterExperiencesWithAssignments(
    List<Experience> experiences,
    Set<String> categoryIds,
    Set<String> colorCategoryIds, {
    Map<String, SharePermission>? permissionsToCheck,
  }) {
    if (experiences.isEmpty) {
      return experiences;
    }
    return experiences
        .where((exp) => _experienceHasValidAssignment(
            exp, categoryIds, colorCategoryIds,
            permissionsToCheck: permissionsToCheck))
        .toList();
  }

  Set<String> _currentCategoryIdSet() =>
      _categories.map((category) => category.id).toSet();

  Set<String> _currentColorCategoryIdSet() =>
      _colorCategories.map((category) => category.id).toSet();

  Future<int> _deleteOrphanedExperiences({
    Set<String>? removedCategoryIds,
    Set<String>? removedColorCategoryIds,
  }) async {
    final String? currentUserId = _authService.currentUser?.uid;
    if (currentUserId == null) {
      return 0;
    }

    try {
      final List<Experience> userExperiences =
          await _experienceService.getExperiencesByUser(
        currentUserId,
        limit: 500,
      );
      final Set<String> categoryIds = _currentCategoryIdSet();
      final Set<String> colorIds = _currentColorCategoryIdSet();
      if (removedCategoryIds != null && removedCategoryIds.isNotEmpty) {
        categoryIds.removeAll(removedCategoryIds);
      }
      if (removedColorCategoryIds != null &&
          removedColorCategoryIds.isNotEmpty) {
        colorIds.removeAll(removedColorCategoryIds);
      }
      final List<Experience> orphans = userExperiences
          .where((exp) => !_experienceHasValidAssignment(
                exp,
                categoryIds,
                colorIds,
              ))
          .toList();

      if (orphans.isEmpty) {
        return 0;
      }

      for (final Experience experience in orphans) {
        await _experienceService.deleteExperience(experience.id);
      }

      if (mounted) {
        setState(() {
          final Set<String> orphanIds =
              orphans.map((experience) => experience.id).toSet();
          _experiences
              .removeWhere((experience) => orphanIds.contains(experience.id));
          _filteredExperiences
              .removeWhere((experience) => orphanIds.contains(experience.id));
          _sharedExperiences
              .removeWhere((experience) => orphanIds.contains(experience.id));
        });
      }

      return orphans.length;
    } catch (e) {
      debugPrint('Collections: failed to delete orphan experiences: $e');
      return 0;
    }
  }
  Future<List<_SharedCategoryData>> _resolveSharedCategories(
      List<SharePermission> permissions) async {
    if (permissions.isEmpty) return [];

    print(
        '[Collections] Resolving ${permissions.length} shared categories (batched by owner)...');
    final sw = Stopwatch()..start();

    // Group permissions by owner
    final Map<String, List<SharePermission>> byOwner = {};
    final Set<String> uniqueOwnerIds = {};
    for (final perm in permissions) {
      byOwner.putIfAbsent(perm.ownerUserId, () => []).add(perm);
      uniqueOwnerIds.add(perm.ownerUserId);
    }

    // Prefetch all owner names in parallel
    await Future.wait(
        uniqueOwnerIds.map((ownerId) => _getOwnerDisplayName(ownerId)));

    // Process each owner's categories in batched queries
    final List<_SharedCategoryData> allResults = [];
    final fetchSw = Stopwatch()..start();

    for (final entry in byOwner.entries) {
      final ownerId = entry.key;
      final ownerPerms = entry.value;
      final categoryIds = ownerPerms.map((p) => p.itemId).toList();

      // Batch fetch both user and color categories for this owner
      final results = await Future.wait([
        _experienceService.getUserCategoriesByOwnerAndIds(ownerId, categoryIds),
        _experienceService.getColorCategoriesByOwnerAndIds(ownerId, categoryIds),
      ]);

      final List<UserCategory> userCategories =
          results[0] as List<UserCategory>;
      final List<ColorCategory> colorCategories =
          results[1] as List<ColorCategory>;

      // Build lookup maps
      final Map<String, UserCategory> userCatById = {
        for (final cat in userCategories) cat.id: cat
      };
      final Map<String, ColorCategory> colorCatById = {
        for (final cat in colorCategories) cat.id: cat
      };

      final ownerName = _shareOwnerNames[ownerId] ?? 'Someone';

      // Match permissions to fetched categories
      for (final perm in ownerPerms) {
        final userCat = userCatById[perm.itemId];
        final colorCat = colorCatById[perm.itemId];

        if (userCat == null && colorCat == null) {
          print(
              '[Collections] No category found for ${perm.itemId} from owner $ownerId');
          continue;
        }

        allResults.add(_SharedCategoryData(
          userCategory: userCat,
          colorCategory: colorCat,
          permission: perm,
          ownerDisplayName: ownerName,
        ));
      }
    }

    fetchSw.stop();
    sw.stop();
    print(
        '[Collections] Resolved ${allResults.length} shared categories in ${sw.elapsedMilliseconds}ms (fetch: ${fetchSw.elapsedMilliseconds}ms)');

    return allResults;
  }
  Future<List<_SharedExperienceData>> _resolveSharedExperiences(
      List<SharePermission> permissions) async {
    if (permissions.isEmpty) return [];

    print(
        '[Collections] Resolving ${permissions.length} shared experiences (batched)...');
    final sw = Stopwatch()..start();

    // Collect unique experience IDs and owner IDs
    final List<String> experienceIds =
        permissions.map((p) => p.itemId).toList();
    final Set<String> uniqueOwnerIds =
        permissions.map((p) => p.ownerUserId).toSet();

    // Batch fetch all experiences and owner names
    final fetchSw = Stopwatch()..start();
    final fetchResults = await Future.wait([
      _experienceService.getExperiencesByIds(experienceIds),
      Future.wait(
          uniqueOwnerIds.map((ownerId) => _getOwnerDisplayName(ownerId))),
    ]);
    fetchSw.stop();

    final List<Experience> experiences =
        fetchResults[0] as List<Experience>;
    print(
        '[Collections] Batched fetch: ${experiences.length} experiences in ${fetchSw.elapsedMilliseconds}ms (${experienceIds.length} requested)');

    // Build experience map for fast lookup
    final Map<String, Experience> experienceById = {
      for (final exp in experiences) exp.id: exp
    };

    // Build results by matching permissions to fetched experiences
    final List<_SharedExperienceData> results = [];
    for (final permission in permissions) {
      final experience = experienceById[permission.itemId];
      if (experience == null) {
        print(
            '[Collections] WARNING: Experience ${permission.itemId} not found');
        continue;
      }

      final ownerName = _shareOwnerNames[permission.ownerUserId] ?? 'Someone';

      results.add(_SharedExperienceData(
        experience: experience,
        permission: permission,
        ownerDisplayName: ownerName,
      ));
    }

    sw.stop();
    print(
        '[Collections] Resolved ${results.length} shared experiences in ${sw.elapsedMilliseconds}ms total');

    return results;
  }

  Future<Map<String, _SharedExperienceData>> _combineSharedExperiences({
    required List<_SharedExperienceData> directSharedExperiences,
    required List<_SharedCategoryData> sharedCategoryData,
  }) async {
    final Map<String, _SharedExperienceData> combined = {
      for (final data in directSharedExperiences) data.experience.id: data,
    };

    final List<_SharedCategoryData> categoriesToProcess =
        sharedCategoryData.where((data) => data.categoryId.isNotEmpty).toList();
    if (categoriesToProcess.isEmpty) {
      return combined;
    }

    final String? userId = _authService.currentUser?.uid;
    if (userId == null) return combined;

    // OPTIMIZED: Broad fetch all experiences shared with current user
    print(
        '[Collections] Broad-fetching all shared experiences for user $userId...');
    final broadSw = Stopwatch()..start();
    final List<Experience> allSharedExperiences = [];
    DocumentSnapshot<Object?>? lastDoc;
    int pageCount = 0;

    // Paginate internally to load all shared experiences (no UI pagination)
    while (true) {
      final (pageExps, last) = await _experienceService.getExperiencesSharedWith(
        userId,
        limit: 500,
        startAfter: lastDoc,
      );
      allSharedExperiences.addAll(pageExps);
      pageCount++;
      if (pageExps.length < 500 || last == null) {
        break; // No more pages
      }
      lastDoc = last;
    }
    broadSw.stop();
    print(
        '[Collections] Broad fetch complete: ${allSharedExperiences.length} shared experiences in ${broadSw.elapsedMilliseconds}ms ($pageCount pages)');

    // Build lookup map for fast filtering
    final Map<String, Experience> allSharedById = {
      for (final exp in allSharedExperiences) exp.id: exp
    };

    // Process each category and filter from the broad fetch
    for (final categoryData in categoriesToProcess) {
      final categoryId = categoryData.categoryId;
      final isColorCategory = categoryData.isColorCategory;

      // Filter experiences that match this category
      final List<Experience> categoryExperiences = allSharedExperiences.where((exp) {
        if (isColorCategory) {
          return exp.colorCategoryId == categoryId;
        } else {
          return exp.categoryId == categoryId ||
              exp.otherCategories.contains(categoryId);
        }
      }).toList();

      print(
          '[Collections] Filtered ${categoryExperiences.length} experiences for ${isColorCategory ? "color" : "user"} category $categoryId from broad fetch');

      // If broad fetch returned nothing but we expect experiences, fall back to per-category query
      if (categoryExperiences.isEmpty && allSharedExperiences.length < 200) {
        print(
            '[Collections] Broad fetch incomplete or empty, trying fallback per-category query for $categoryId');
        try {
          final fallbackExps =
              await _experienceService.getExperiencesForOwnerCategory(
            ownerUserId: categoryData.permission.ownerUserId,
            categoryId: categoryId,
            isColorCategory: isColorCategory,
            limitPerQuery: 500,
          );
          categoryExperiences.addAll(fallbackExps);
          print(
              '[Collections] Fallback fetched ${fallbackExps.length} experiences');
        } catch (e) {
          print('[Collections] Fallback fetch failed: $e');
        }
      }

      if (categoryExperiences.isEmpty) {
        continue;
      }

      final ShareAccessLevel categoryAccess =
          categoryData.permission.accessLevel;
      final String ownerId = categoryData.permission.ownerUserId;
      _shareOwnerNames[ownerId] = categoryData.ownerDisplayName;

      for (final Experience experience in categoryExperiences) {
        final _SharedExperienceData? existing = combined[experience.id];
        if (existing != null) {
          final bool upgradeToEdit =
              existing.permission.accessLevel == ShareAccessLevel.view &&
                  categoryAccess == ShareAccessLevel.edit;
          if (upgradeToEdit) {
            combined[experience.id] = _SharedExperienceData(
              experience: existing.experience,
              permission: existing.permission.copyWith(
                accessLevel: ShareAccessLevel.edit,
                updatedAt: categoryData.permission.updatedAt,
              ),
              ownerDisplayName: existing.ownerDisplayName,
            );
          }
          continue;
        }

        final SharePermission syntheticPermission = SharePermission(
          id: 'category_${categoryData.permission.id}_${experience.id}',
          itemId: experience.id,
          itemType: ShareableItemType.experience,
          ownerUserId: ownerId,
          sharedWithUserId: categoryData.permission.sharedWithUserId,
          accessLevel: categoryAccess,
          createdAt: categoryData.permission.createdAt,
          updatedAt: categoryData.permission.updatedAt,
        );

        combined[experience.id] = _SharedExperienceData(
          experience: experience,
          permission: syntheticPermission,
          ownerDisplayName: categoryData.ownerDisplayName,
        );
      }
    }

    return combined;
  }

  Future<String> _getOwnerDisplayName(String userId) async {
    if (_shareOwnerNames.containsKey(userId)) {
      return _shareOwnerNames[userId]!;
    }
    final profile = await _experienceService.getUserProfileById(userId);
    final name = profile?.displayName ?? profile?.username ?? 'Someone';
    _shareOwnerNames[userId] = name;
    return name;
  }

  /// Batch prefetch owner display names for a list of user IDs
  Future<void> _prefetchOwnerDisplayNames(Set<String> userIds) async {
    // Filter out already-cached IDs
    final uncachedIds =
        userIds.where((id) => !_shareOwnerNames.containsKey(id)).toList();
    if (uncachedIds.isEmpty) return;

    print(
        '[Collections] Prefetching ${uncachedIds.length} owner display names...');
    final sw = Stopwatch()..start();

    try {
      final profiles =
          await _experienceService.getUserProfilesByIds(uncachedIds);
      final Map<String, UserProfile> profileById = {
        for (final p in profiles) p.id: p
      };

      for (final userId in uncachedIds) {
        final profile = profileById[userId];
        final name = profile?.displayName ?? profile?.username ?? 'Someone';
        _shareOwnerNames[userId] = name;
      }

      sw.stop();
      print(
          '[Collections] Prefetched ${profiles.length} owner names in ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      print('[Collections] Error prefetching owner names: $e');
    }
  }

  Future<void> _showAddCategoryModal() async {
    final result = await showModalBottomSheet<UserCategory>(
      context: context,
      builder: (_) => const AddCategoryModal(),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );

    if (result != null) {
      _loadData();
    } else {}
  }

  // ADDED: Method to show add experience modal
  Future<void> _showAddExperienceModal() async {
    final result = await showModalBottomSheet<Experience>(
      context: context,
      builder: (_) => AddExperienceModal(
        userCategories: _categories,
        userColorCategories: _colorCategories,
      ),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );

    if (result != null) {
      _loadData();
    } else {}
  }

  Future<void> _showEditSingleCategoryModal(UserCategory category) async {
    final result = await showModalBottomSheet<UserCategory>(
      context: context,
      builder: (_) => AddCategoryModal(categoryToEdit: category),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );

    if (result != null) {
      _loadData();
    } else {}
  }

  Future<void> _showDeleteCategoryConfirmation(UserCategory category) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category?'),
        content: Text(
            'Are you sure you want to delete the "${category.name}" category? Associated experiences will NOT be deleted but will lose this category tag. This cannot be undone.'),
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
      try {
        await _experienceService.deleteUserCategory(category.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${category.name}" category deleted.')),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting category: $e')),
          );
        }
      }
    }
  }

  // Determine which shared experiences lose their last matching category/color category
  List<SharePermission> _collectExperiencePermissionsToRemove({
    String? categoryId,
    String? colorCategoryId,
  }) {
    assert(categoryId != null || colorCategoryId != null,
        'categoryId or colorCategoryId must be provided');

    final Set<String> remainingCategoryIds =
        _categories.map((c) => c.id).toSet();
    final Set<String> remainingColorCategoryIds =
        _colorCategories.map((c) => c.id).toSet();

    if (categoryId != null) {
      remainingCategoryIds.remove(categoryId);
    }
    if (colorCategoryId != null) {
      remainingColorCategoryIds.remove(colorCategoryId);
    }

    final List<SharePermission> candidates = [];

    for (final experience in _sharedExperiences) {
      final SharePermission? permission =
          _sharedExperiencePermissions[experience.id];
      if (permission == null) {
        continue;
      }

      bool associatedWithRemoval = false;
      if (categoryId != null &&
          (experience.categoryId == categoryId ||
              experience.otherCategories.contains(categoryId))) {
        associatedWithRemoval = true;
      }

      if (colorCategoryId != null &&
          experience.colorCategoryId == colorCategoryId) {
        associatedWithRemoval = true;
      }

      if (!associatedWithRemoval) {
        continue;
      }

      final bool hasOtherCategory = () {
        final String? primary = experience.categoryId;
        if (primary != null &&
            primary.isNotEmpty &&
            primary != categoryId &&
            remainingCategoryIds.contains(primary)) {
          return true;
        }
        for (final otherId in experience.otherCategories) {
          if (otherId == categoryId) {
            continue;
          }
          if (remainingCategoryIds.contains(otherId)) {
            return true;
          }
        }
        return false;
      }();

      final bool hasOtherColorCategory = () {
        final String? colorId = experience.colorCategoryId;
        if (colorId != null &&
            colorId.isNotEmpty &&
            colorId != colorCategoryId &&
            remainingColorCategoryIds.contains(colorId)) {
          return true;
        }
        return false;
      }();

      if (!hasOtherCategory && !hasOtherColorCategory) {
        candidates.add(permission);
      }
    }

    return candidates;
  }

  Future<int> _removeSharedUserCategory(
      UserCategory category, SharePermission permission) async {
    final List<SharePermission> experiencePermissionsToRemove =
        _collectExperiencePermissionsToRemove(categoryId: category.id);
    if (experiencePermissionsToRemove.isNotEmpty) {
      print(
          '[Collections] Removing ${experiencePermissionsToRemove.length} shared experience(s) with only "${category.name}" as a matching category.');
    }

    await _sharingService.removeShare(permission.id);

    int removedExperienceCount = 0;
    for (final SharePermission permissionToRemove
        in experiencePermissionsToRemove) {
      await _sharingService.removeShare(permissionToRemove.id);
      removedExperienceCount++;
    }

    return removedExperienceCount;
  }

  Future<int> _removeSharedColorCategory(
      ColorCategory category, SharePermission permission) async {
    final List<SharePermission> experiencePermissionsToRemove =
        _collectExperiencePermissionsToRemove(colorCategoryId: category.id);
    if (experiencePermissionsToRemove.isNotEmpty) {
      print(
          '[Collections] Removing ${experiencePermissionsToRemove.length} shared experience(s) with only "${category.name}" as a color category.');
    }

    await _sharingService.removeShare(permission.id);

    int removedExperienceCount = 0;
    for (final SharePermission permissionToRemove
        in experiencePermissionsToRemove) {
      await _sharingService.removeShare(permissionToRemove.id);
      removedExperienceCount++;
    }

    return removedExperienceCount;
  }

  Future<void> _showRemoveSharedUserCategoryConfirmation(
      UserCategory category, SharePermission permission) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Shared Category?'),
        content: Text(
            'Are you sure you want to remove the "${category.name}" category from your collections? You will lose access to the experiences shared with it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() {
        _isLoading = true;
      });
      try {
        final int removedExperienceCount =
            await _removeSharedUserCategory(category, permission);
        if (!mounted) {
          return;
        }
        final String experienceMessage = removedExperienceCount > 0
            ? ' Removed $removedExperienceCount experience${removedExperienceCount == 1 ? '' : 's'} without other category access.'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '"${category.name}" removed from your categories.$experienceMessage'),
          ),
        );
        await _loadData();
      } catch (e) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing shared category: $e')),
        );
      }
    }
  }

  // ADDED: Helper to update local orderIndex properties
  void _updateLocalOrderIndices() {
    int nextOrder = 0;
    for (int i = 0; i < _categories.length; i++) {
      final category = _categories[i];
      if (_isSharedCategory(category)) {
        continue;
      }
      _categories[i] = category.copyWith(orderIndex: nextOrder);
      nextOrder++;
    }
  }

  // ADDED: Method to save the new category order to Firestore
  Future<void> _saveCategoryOrder() async {
    final List<Map<String, dynamic>> updates = [];
    for (final category in _categories) {
      if (_isSharedCategory(category)) {
        continue;
      }
      if (category.id.isNotEmpty && category.orderIndex != null) {
        updates.add({
          'id': category.id,
          'orderIndex': category.orderIndex!,
        });
      }
    }

    if (updates.isEmpty) {
      return;
    }

    try {
      await _experienceService.updateCategoryOrder(updates);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving category order: $e")),
        );
        _loadData();
      }
    }
  }

  int _getExperienceCountForCategory(UserCategory category) {
    // MODIFIED: Include experiences with this category as primary OR in otherCategories
    return _experiences
        .where((exp) =>
            exp.categoryId == category.id ||
            exp.otherCategories.contains(category.id))
        .length;
  }

  bool _canModifyPrivacy(String ownerUserId) {
    final String? currentUserId = _authService.currentUser?.uid;
    return currentUserId != null && currentUserId == ownerUserId;
  }

  Widget _buildPrivacyIconToggle({
    required bool isPrivate,
    required bool isEnabled,
    required VoidCallback onToggle,
    required String subjectLabel,
  }) {
    final IconData iconData = isPrivate ? Icons.lock : Icons.public;
    final Color iconColor =
        isPrivate ? Colors.grey.shade600 : Colors.black87;
    final String tooltip = isEnabled
        ? 'Make $subjectLabel ${isPrivate ? 'public' : 'private'}'
        : 'Only the owner can change privacy';
    final Widget icon = Padding(
      padding: const EdgeInsets.all(6.0),
      child: Icon(
        iconData,
        color: iconColor,
        size: 22,
      ),
    );
    if (!isEnabled) {
      return Tooltip(message: tooltip, child: icon);
    }
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onToggle,
        child: icon,
      ),
    );
  }

  Future<void> _toggleCategoryPrivacy(UserCategory category) async {
    if (!_canModifyPrivacy(category.ownerUserId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Only the owner can change this category privacy.')),
        );
      }
      return;
    }
    final UserCategory updated =
        category.copyWith(isPrivate: !category.isPrivate);
    try {
      await _experienceService.updateUserCategory(updated);
      if (!mounted) return;
      setState(() {
        final int index =
            _categories.indexWhere((element) => element.id == category.id);
        if (index != -1) {
          _categories[index] = updated;
        }
        if (_selectedCategory?.id == category.id) {
          _selectedCategory = updated;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update privacy: $e')),
        );
      }
    }
  }

  Future<void> _toggleColorCategoryPrivacy(ColorCategory category) async {
    if (!_canModifyPrivacy(category.ownerUserId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Only the owner can change this color category privacy.')),
        );
      }
      return;
    }
    final ColorCategory updated =
        category.copyWith(isPrivate: !category.isPrivate);
    try {
      await _experienceService.updateColorCategory(updated);
      if (!mounted) return;
      setState(() {
        final int index =
            _colorCategories.indexWhere((element) => element.id == category.id);
        if (index != -1) {
          _colorCategories[index] = updated;
        }
        if (_selectedColorCategory?.id == category.id) {
          _selectedColorCategory = updated;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update privacy: $e')),
        );
      }
    }
  }

  // ADDED: Widget builder for a Category Grid Item (for web)
  Widget _buildCategoryGridItem(UserCategory category) {
    final count = _getExperienceCountForCategory(category);
    final SharePermission? permission = _sharedCategoryPermissions[category.id];
    final bool isShared = permission != null;
    final bool isOwnerShared = _ownedSharedCategoryIds.contains(category.id);
    final String? ownerName = isShared
        ? (_shareOwnerNames[permission!.ownerUserId] ?? 'Someone')
        : null;
    final String? shareLabel = isShared
        ? _buildSharedByLabel(
            permission: permission!,
            ownerName: ownerName ?? 'Someone',
          )
        : (isOwnerShared ? 'Shared' : null);
    final bool isSelected = _selectedCategoryIds.contains(category.id);
    final bool canTogglePrivacy = _canModifyPrivacy(category.ownerUserId);
    return Card(
      key: ValueKey('category_grid_${category.id}'),
      clipBehavior: Clip.antiAlias,
      elevation: 2.0,
      child: Stack(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                if (_isSelectingCategories) {
                  if (isSelected) {
                    _selectedCategoryIds.remove(category.id);
                  } else {
                    _selectedCategoryIds.add(category.id);
                  }
                } else {
                  _selectedCategory = category;
                  _showingColorCategories = false;
                  _selectedColorCategory = null;
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Text(
                    category.icon,
                    style: const TextStyle(fontSize: 32),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    category.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$count ${count == 1 ? "exp" : "exps"}',
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (shareLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        shareLabel,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: _buildPrivacyIconToggle(
            isPrivate: category.isPrivate,
            isEnabled: canTogglePrivacy,
            onToggle: () => _toggleCategoryPrivacy(category),
            subjectLabel: 'category',
          ),
        ),
        if (_isSelectingCategories)
          Positioned(
              top: 4,
              left: 4,
              child: Checkbox(
                value: isSelected,
                onChanged: (bool? value) {
                  setState(() {
                    if (value == true) {
                      _selectedCategoryIds.add(category.id);
                    } else {
                      _selectedCategoryIds.remove(category.id);
                    }
                  });
                },
              ),
            ),
        ],
      ),
    );
  }
  Widget _buildCategoriesList() {
    if (_categories.isEmpty) {
      return const Center(child: Text('No categories found.'));
    }

    final bool isDesktopWeb = kIsWeb && MediaQuery.of(context).size.width > 600;

    if (isDesktopWeb) {
      final screenWidth = MediaQuery.of(context).size.width;
      const double contentMaxWidth = 1200.0;
      const double defaultPadding = 12.0;

      double horizontalPadding;
      if (screenWidth > contentMaxWidth) {
        horizontalPadding = (screenWidth - contentMaxWidth) / 2;
      } else {
        horizontalPadding = defaultPadding;
      }

      return GridView.builder(
        padding: EdgeInsets.fromLTRB(horizontalPadding, defaultPadding,
            horizontalPadding, defaultPadding + _bottomListPadding),
        itemCount: _categories.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: 10.0,
          crossAxisSpacing: 10.0,
          childAspectRatio: 3 / 3.5,
        ),
        itemBuilder: (context, index) {
          final category = _categories[index];
          return _buildCategoryGridItem(category);
        },
      );
    } else {
      return ReorderableListView.builder(
        padding: const EdgeInsets.only(bottom: _bottomListPadding),
        buildDefaultDragHandles: false,
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final count = _getExperienceCountForCategory(category);
          final SharePermission? permission =
              _sharedCategoryPermissions[category.id];
          final bool isShared = permission != null;
          final bool canEditCategory =
              !isShared || permission!.accessLevel == ShareAccessLevel.edit;
          final bool canManageCategory = !isShared;
          final bool isOwnerShared =
              _ownedSharedCategoryIds.contains(category.id);
          final String? ownerName = isShared
              ? (_shareOwnerNames[permission!.ownerUserId] ?? 'Someone')
              : null;
          final String? shareLabel = isShared
              ? _buildSharedByLabel(
                  permission: permission!,
                  ownerName: ownerName ?? 'Someone',
                )
              : (isOwnerShared ? 'Shared' : null);
          final bool isSelected = _selectedCategoryIds.contains(category.id);
          final bool canTogglePrivacy = _canModifyPrivacy(category.ownerUserId);

          final Widget iconWidget = Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Text(
              category.icon,
              style: const TextStyle(fontSize: 24),
            ),
          );

          final Widget leadingWidget = _isSelectingCategories
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: isSelected,
                      onChanged: (bool? value) {
                        setState(() {
                          if (value == true) {
                            _selectedCategoryIds.add(category.id);
                          } else {
                            _selectedCategoryIds.remove(category.id);
                          }
                        });
                      },
                    ),
                    iconWidget,
                  ],
                )
              : iconWidget;

          final Widget subtitleWidget = shareLabel != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$count ${count == 1 ? "experience" : "experiences"}'),
                    Text(
                      shareLabel,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                )
              : Text('$count ${count == 1 ? "experience" : "experiences"}');

          final Widget popupMenu = PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Category Options',
            color: Colors.white,
            onSelected: (String result) {
              switch (result) {
                case 'edit':
                  _showEditSingleCategoryModal(category);
                  break;
                case 'share':
                  _showShareCategoryBottomSheet(category);
                  break;
                case 'remove':
                  if (permission != null) {
                    _showRemoveSharedUserCategoryConfirmation(
                        category, permission);
                  }
                  break;
                case 'delete':
                  _showDeleteCategoryConfirmation(category);
                  break;
              }
            },
            itemBuilder: (BuildContext context) {
              final List<PopupMenuEntry<String>> items = [
                PopupMenuItem<String>(
                  value: 'edit',
                  enabled: canEditCategory,
                  child: const ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'share',
                  enabled: canManageCategory,
                  child: const ListTile(
                    leading: Icon(Icons.ios_share),
                    title: Text('Share'),
                  ),
                ),
              ];
              if (isShared && permission != null) {
                items.add(
                  const PopupMenuItem<String>(
                    value: 'remove',
                    child: ListTile(
                      leading: Icon(Icons.remove_circle_outline,
                          color: Colors.red),
                      title: Text('Remove', style: TextStyle(color: Colors.red)),
                    ),
                  ),
                );
              } else {
                items.add(
                  PopupMenuItem<String>(
                    value: 'delete',
                    enabled: canManageCategory,
                    child: const ListTile(
                      leading: Icon(Icons.delete_outline, color: Colors.red),
                      title: Text('Delete', style: TextStyle(color: Colors.red)),
                    ),
                  ),
                );
              }
              return items;
            },
          );

          final listTile = ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 7.0),
            minLeadingWidth: 24,
            leading: leadingWidget,
            title: Text(category.name),
            subtitle: subtitleWidget,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPrivacyIconToggle(
                  isPrivate: category.isPrivate,
                  isEnabled: canTogglePrivacy,
                  onToggle: () => _toggleCategoryPrivacy(category),
                  subjectLabel: 'category',
                ),
                const SizedBox(width: 4),
                popupMenu,
              ],
            ),
            onTap: () {
              setState(() {
                if (_isSelectingCategories) {
                  if (isSelected) {
                    _selectedCategoryIds.remove(category.id);
                  } else {
                    _selectedCategoryIds.add(category.id);
                  }
                } else {
                  _selectedCategory = category;
                  _showingColorCategories = false;
                  _selectedColorCategory = null;
                }
              });
            },
          );

          return ReorderableDelayedDragStartListener(
            key: ValueKey(category.id),
            index: index,
            enabled: !_isSelectingCategories,
            child: listTile,
          );
        },
        onReorder: (int oldIndex, int newIndex) {
          if (newIndex > oldIndex) {
            newIndex -= 1;
          }
          if (oldIndex < 0 ||
              oldIndex >= _categories.length ||
              newIndex < 0 ||
              newIndex >= _categories.length) {
            return;
          }
          setState(() {
            final UserCategory item = _categories.removeAt(oldIndex);
            _categories.insert(newIndex, item);
            _manualCategoryOrder =
                List<String>.from(_categories.map((c) => c.id));
            _useManualCategoryOrder = true;
            _updateLocalOrderIndices();
          });
          unawaited(_persistManualCategoryOrder());
          unawaited(_persistUseManualCategoryOrder());
          _saveCategoryOrder();
        },
      );
    }
  }

  // ADDED: Method to apply sorting and save the new order
  Future<void> _applySortAndSave(CategorySortType sortType) async {
    final List<UserCategory> sorted = List<UserCategory>.from(_categories);
    sorted.sort((a, b) => _compareCategoriesForSort(a, b, sortType));

    setState(() {
      _categorySortType = sortType;
      _useManualCategoryOrder = false;
      _manualCategoryOrder = [];
      _categories = sorted;
      _updateLocalOrderIndices();
    });

    await _saveCategoryOrder();
    // Persist user preference so it applies next time
    unawaited(_saveCategorySort(sortType));
    unawaited(_persistManualCategoryOrder());
    unawaited(_persistUseManualCategoryOrder());
  }

  // MODIFIED: Method to apply sorting to the experiences list
  // Takes the desired sort type as an argument
  // ADDED: Optional parameter to apply sort to the filtered list
  Future<void> _applyExperienceSort(ExperienceSortType sortType,
      {bool applyToFiltered = false}) async {
    // If sort type changed and not just applying to filtered, reset pagination and reload
    final bool sortChanged = sortType != _experienceSortType && !applyToFiltered;
    
    // If not changed, and we're not applying to filtered, just return (avoid redundant work)
    if (!sortChanged && !applyToFiltered) {
      return;
    }
    
    setState(() {
      _experienceSortType = sortType;
      // Only show loading indicator if sorting the main list by distance
      _isLoading =
          (sortType == ExperienceSortType.distanceFromMe && !applyToFiltered);
      // Initialize city expansion states to collapsed when switching to city sort
      if (!applyToFiltered && sortType == ExperienceSortType.city) {
        _cityExpansionExperiences.clear();
        // Build keys from current filtered list so headers render collapsed by default
        for (final exp in _filteredExperiences) {
          final key = (exp.location.city ?? '').trim().toLowerCase();
          _cityExpansionExperiences.putIfAbsent(key, () => false);
        }
        // Ensure unknown city key exists
        _cityExpansionExperiences.putIfAbsent('', () => false);
      }
      
      // Reset pagination when sort changes
      if (sortChanged) {
        _lastExperienceDoc = null;
        _hasMoreExperiences = true;
        _experiences = [];
        _filteredExperiences = [];
      }
    });
    
    // If sort changed, reload with new ordering
    if (sortChanged) {
      // Persist the new sort preference
      unawaited(_saveExperienceSort(sortType));
      
      final userId = _authService.currentUser?.uid;
      if (userId != null) {
        await _loadExperiencesPage(isInitialLoad: true);
      }
      return;
    }

    // Determine which list to sort
    List<Experience> listToSort =
        applyToFiltered ? _filteredExperiences : _experiences;

    try {
      if (sortType == ExperienceSortType.alphabetical) {
        listToSort.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      } else if (sortType == ExperienceSortType.mostRecent) {
        listToSort.sort((a, b) {
          final DateTime tsA = _sharedExperienceUpdatedAt(a);
          final DateTime tsB = _sharedExperienceUpdatedAt(b);
          final int cmp = tsB.compareTo(tsA);
          if (cmp != 0) return cmp;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      } else if (sortType == ExperienceSortType.distanceFromMe) {
        // --- MODIFIED: Distance Sorting Logic now operates on listToSort ---
        await _sortExperiencesByDistance(listToSort);
        // --- END MODIFIED ---
      } else if (sortType == ExperienceSortType.city) {
        String normalizeCity(String? city) => (city ?? '').trim().toLowerCase();
        listToSort.sort((a, b) {
          final ca = normalizeCity(a.location.city);
          final cb = normalizeCity(b.location.city);
          final aEmpty = ca.isEmpty;
          final bEmpty = cb.isEmpty;
          if (aEmpty && bEmpty) return 0;
          if (aEmpty) return 1; // Empty cities last
          if (bEmpty) return -1;
          final cmp = ca.compareTo(cb);
          if (cmp != 0) return cmp;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      }

      // Ensure filtered list reflects the same ordering when sorting main list
      if (!applyToFiltered) {
        if (sortType == ExperienceSortType.alphabetical) {
          _filteredExperiences.sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        } else if (sortType == ExperienceSortType.mostRecent) {
          _filteredExperiences
              .sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        } else if (sortType == ExperienceSortType.distanceFromMe) {
          await _sortExperiencesByDistance(_filteredExperiences);
        } else if (sortType == ExperienceSortType.city) {
          String normalizeCity(String? city) =>
              (city ?? '').trim().toLowerCase();
          _filteredExperiences.sort((a, b) {
            final ca = normalizeCity(a.location.city);
            final cb = normalizeCity(b.location.city);
            final aEmpty = ca.isEmpty;
            final bEmpty = cb.isEmpty;
            if (aEmpty && bEmpty) return 0;
            if (aEmpty) return 1;
            if (bEmpty) return -1;
            final cmp = ca.compareTo(cb);
            if (cmp != 0) return cmp;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
        }
      }
      // Persist user preference so it applies next time
      if (!applyToFiltered) {
        unawaited(_saveExperienceSort(sortType));
      }
      // Add other sort types here if needed
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sorting experiences: $e')),
        );
      }
    } finally {
      // Ensure loading indicator is turned off and UI rebuilds
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // --- ADDED: Method to sort experiences by distance ---
  // MODIFIED: Takes the list to sort as a parameter
  Future<void> _sortExperiencesByDistance(
      List<Experience> experiencesToSort) async {
    Position? currentPosition;
    bool locationPermissionGranted = false;

    try {
      // 1. Check Location Services
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Location services are disabled. Please enable them.')));
        return; // Stop if services are disabled
      }

      // 2. Check and Request Permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Location permission denied. Cannot sort by distance.')));
        }
        return; // Stop if permission denied
      }

      locationPermissionGranted = true;

      // 3. Get Current Location (with timeout)
      currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy:
            LocationAccuracy.medium, // Medium accuracy is often faster
        timeLimit: Duration(seconds: 10), // Add a timeout
      );
    } catch (e) {
      if (mounted) {
        String message = 'Could not get current location.';
        if (e is TimeoutException) {
          message = 'Could not get current location: Request timed out.';
        } else if (!locationPermissionGranted) {
          // This case is unlikely if permission check above is robust,
          // but kept for safety.
          message = 'Location permission denied. Cannot sort by distance.';
        } else {
          message = 'Error getting location: ${e.toString()}';
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
      return; // Stop if location couldn't be determined
    }

    // 4. Calculate Distances and Sort
    // Use a temporary list or map to store experiences with distances
    List<Map<String, dynamic>> experiencesWithDistance = [];

    // Use the passed-in list
    for (var exp in experiencesToSort) {
      double? distance;
      // Check if the experience has valid coordinates
      if (exp.location.latitude != 0.0 || exp.location.longitude != 0.0) {
        try {
          distance = Geolocator.distanceBetween(
            currentPosition.latitude,
            currentPosition.longitude,
            exp.location.latitude,
            exp.location.longitude,
          );
        } catch (e) {
          distance = null; // Treat calculation error as unknown distance
        }
      } else {
        distance = null; // No coordinates, unknown distance
      }
      experiencesWithDistance.add({'experience': exp, 'distance': distance});
    }

    // Sort the temporary list
    experiencesWithDistance.sort((a, b) {
      final distA = a['distance'] as double?;
      final distB = b['distance'] as double?;

      // Handle null distances (experiences w/o location or errors)
      if (distA == null && distB == null) return 0; // Keep relative order
      if (distA == null) return 1; // Nulls go to the end
      if (distB == null) return -1; // Nulls go to the end

      return distA.compareTo(distB); // Sort by distance ascending
    });

    // Update the *original* list passed in (experiencesToSort) with the sorted order
    // This modifies the list in place (either _experiences or _filteredExperiences)
    experiencesToSort.clear();
    experiencesToSort.addAll(experiencesWithDistance
        .map((item) => item['experience'] as Experience)
        .toList());
  }

  // --- END ADDED ---
  // --- REFACTORED: Method to apply sorting to the grouped content items list ---
  // ADDED: Optional parameter to apply sort to the filtered list
  Future<void> _applyContentSort(ContentSortType sortType,
      {bool applyToFiltered = false}) async {
    setState(() {
      _contentSortType = sortType;
      // Show loading only for distance sort on the main list
      if (sortType == ContentSortType.distanceFromMe && !applyToFiltered) {
        _isLoading = true;
      }
    });

    // Determine which list to sort
    List<GroupedContentItem> listToSort =
        applyToFiltered ? _filteredGroupedContentItems : _groupedContentItems;

    try {
      if (sortType == ContentSortType.mostRecent) {
        // Sort by media item creation date (descending)
        listToSort.sort((a, b) {
          final comparison =
              b.mediaItem.createdAt.compareTo(a.mediaItem.createdAt);
          // Show first few comparisons for debugging
          if (listToSort.indexOf(a) < 5 || listToSort.indexOf(b) < 5) {
            final aPath = a.mediaItem.path.length > 30
                ? a.mediaItem.path.substring(0, 30) + "..."
                : a.mediaItem.path;
            final bPath = b.mediaItem.path.length > 30
                ? b.mediaItem.path.substring(0, 30) + "..."
                : b.mediaItem.path;
          }
          return comparison;
        });

        // Debug logging to show final sort order with more detail
        for (int i = 0; i < listToSort.length && i < 20; i++) {
          final item = listToSort[i];
          final expNames =
              item.associatedExperiences.map((e) => e.name).join(', ');
        }

        // Also search for specific items we're interested in
        for (int i = 0; i < listToSort.length; i++) {
          final item = listToSort[i];
          if (item.mediaItem.createdAt.toString().contains('23:53:15') ||
              item.mediaItem.createdAt.toString().contains('23:52:19')) {
            final expNames =
                item.associatedExperiences.map((e) => e.name).join(', ');
          }
        }
      } else if (sortType == ContentSortType.alphabetical) {
        // Sort by the name of the *first* associated experience (ascending)
        listToSort.sort((a, b) {
          if (a.associatedExperiences.isEmpty &&
              b.associatedExperiences.isEmpty) {
            return 0;
          }
          if (a.associatedExperiences.isEmpty) {
            return 1; // Items without experiences go last
          }
          if (b.associatedExperiences.isEmpty) return -1;
          return a.associatedExperiences.first.name
              .toLowerCase()
              .compareTo(b.associatedExperiences.first.name.toLowerCase());
        });
      } else if (sortType == ContentSortType.distanceFromMe) {
        // Sort by the minimum distance calculated in _sortContentByDistance
        // --- MODIFIED: Pass the list to sort ---
        await _sortContentByDistance(listToSort);
        // --- END MODIFIED ---
      } else if (sortType == ContentSortType.city) {
        String cityOf(GroupedContentItem g) {
          for (final exp in g.associatedExperiences) {
            final c = (exp.location.city ?? '').trim();
            if (c.isNotEmpty) return c.toLowerCase();
          }
          return '';
        }

        listToSort.sort((a, b) {
          final ca = cityOf(a);
          final cb = cityOf(b);
          final aEmpty = ca.isEmpty;
          final bEmpty = cb.isEmpty;
          if (aEmpty && bEmpty) return 0;
          if (aEmpty) return 1; // Empty cities last
          if (bEmpty) return -1;
          final cmp = ca.compareTo(cb);
          if (cmp != 0) return cmp;
          return b.mediaItem.createdAt.compareTo(a.mediaItem.createdAt);
        });
      }
      // Apply the same sort to the filtered list using the same logic
      if (!applyToFiltered) {
        await _applyContentSort(sortType, applyToFiltered: true);
      }
      // Persist user preference so it applies next time
      if (!applyToFiltered) {
        unawaited(_saveContentSort(sortType));
      }
    } catch (e, stackTrace) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sorting content: $e')),
        );
      }
    } finally {
      // Ensure loading indicator is turned off and UI rebuilds
      if (mounted && _isLoading && sortType == ContentSortType.distanceFromMe) {
        setState(() {
          _isLoading = false;
        });
      }
    }
    // Need setState to rebuild the list after sorting (unless isLoading was already true)
    if (mounted && sortType != ContentSortType.distanceFromMe) {
      setState(() {});
    }
    final displayList =
        applyToFiltered ? _filteredGroupedContentItems : _groupedContentItems;
    for (int i = 0; i < displayList.length && i < 10; i++) {
      final item = displayList[i];
      final expNames = item.associatedExperiences.map((e) => e.name).join(', ');
    }
  }

  // --- REFACTORED: Method to sort grouped content items by distance --- ///
  // MODIFIED: Takes the list to sort as a parameter
  Future<void> _sortContentByDistance(
      List<GroupedContentItem> contentToSort) async {
    Position? currentPosition;
    bool locationPermissionGranted = false;

    // Much of this logic is duplicated from _sortExperiencesByDistance
    // Consider refactoring into a shared location service/helper in the future
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Location services are disabled. Please enable them.')));
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Location permission denied. Cannot sort by distance.')));
        }
        return;
      }

      locationPermissionGranted = true;

      currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 10),
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

    // Calculate minimum distance for each grouped item in the list to sort
    for (var group in contentToSort) {
      double? minGroupDistance;
      for (var exp in group.associatedExperiences) {
        double? distance;
        final location = exp.location;
        if (location.latitude != 0.0 || location.longitude != 0.0) {
          try {
            distance = Geolocator.distanceBetween(
              currentPosition.latitude,
              currentPosition.longitude,
              location.latitude,
              location.longitude,
            );
            // Update minimum distance for the group
            if (minGroupDistance == null || distance < minGroupDistance) {
              minGroupDistance = distance;
            }
          } catch (e) {}
        } else {}
      }
      // Store the calculated minimum distance in the object
      group.minDistance = minGroupDistance;
    }

    // Sort the list passed in (contentToSort) based on the calculated minDistance
    contentToSort.sort((a, b) {
      final distA = a.minDistance;
      final distB = b.minDistance;

      if (distA == null && distB == null) {
        return 0; // Keep relative order if both unknown
      }
      if (distA == null) return 1; // Nulls (unknown distances) go to the end
      if (distB == null) return -1; // Nulls go to the end

      return distA.compareTo(distB); // Sort by distance ascending
    });
  }
  // --- END REFACTORED ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Collection'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          // ADDED: Map Button with text label
          Tooltip(
            message: 'View Map',
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.black),
              icon: const Icon(Icons.map_outlined),
              label: const Text('Map'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const MapScreen()),
                );
              },
            ),
          ),
          // --- MODIFIED: Conditionally show sort button for first tab ---
          if (_currentTabIndex == 0 &&
              _selectedCategory == null &&
              !_showingColorCategories)
            PopupMenuButton<CategorySortType>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort Categories',
              color: Colors.white,
              onSelected: (CategorySortType result) {
                _applySortAndSave(result); // Saves text category order
              },
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<CategorySortType>>[
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
            ),
          // --- ADDED: Sort button for Color Categories --- START ---
          if (_currentTabIndex == 0 &&
              _selectedCategory == null &&
              _showingColorCategories)
            PopupMenuButton<ColorCategorySortType>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort Color Categories',
              color: Colors.white,
              onSelected: (ColorCategorySortType result) {
                _applyColorSortAndSave(result); // Saves color category order
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
            ),
          // --- ADDED: Sort button for Color Categories --- END ---
          if (_currentTabIndex == 1)
            PopupMenuButton<ExperienceSortType>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort Experiences',
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
                const PopupMenuItem<ExperienceSortType>(
                  enabled: false,
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.5,
                      child: Divider(height: 1),
                    ),
                  ),
                ),
                // --- Group by Location (single checkbox) ---
                PopupMenuItem<ExperienceSortType>(
                  onTap: () {
                    setState(() {
                      _groupByLocationExperiences =
                          !_groupByLocationExperiences;
                      _countryExpansionExperiences.clear();
                      _stateExpansionExperiences.clear();
                      _cityExpansionExperiences.clear();
                      _locationExpansionExperiences.clear();
                    });
                    unawaited(_saveGroupByLocationExperiences(
                        _groupByLocationExperiences));
                  },
                  child: Row(
                    children: [
                      Checkbox(
                        value: _groupByLocationExperiences,
                        onChanged: (_) {},
                      ),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Group by Location')),
                    ],
                  ),
                ),
              ],
            ),
          if (_currentTabIndex == 2)
            PopupMenuButton<ContentSortType>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort Content',
              color: Colors.white,
              onSelected: (ContentSortType result) {
                _applyContentSort(result); // Use the new sort function
              },
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<ContentSortType>>[
                _buildPopupMenuItem<ContentSortType>(
                  value: ContentSortType.mostRecent,
                  text: 'Sort by Most Recent Added',
                  currentValue: _contentSortType,
                ),
                _buildPopupMenuItem<ContentSortType>(
                  value: ContentSortType.alphabetical,
                  text: 'Sort Alphabetically (by Experience)',
                  currentValue: _contentSortType,
                ),
                _buildPopupMenuItem<ContentSortType>(
                  value: ContentSortType.distanceFromMe,
                  text: 'Sort by Distance (from Experience)',
                  currentValue: _contentSortType,
                ),
                const PopupMenuItem<ContentSortType>(
                  enabled: false,
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.5,
                      child: Divider(height: 1),
                    ),
                  ),
                ),
                // --- Group by Location (single checkbox) ---
                PopupMenuItem<ContentSortType>(
                  onTap: () {
                    setState(() {
                      _groupByLocationContent = !_groupByLocationContent;
                      _countryExpansionContent.clear();
                      _stateExpansionContent.clear();
                      _cityExpansionContent.clear();
                      _locationExpansionContent.clear();
                    });
                    unawaited(
                        _saveGroupByLocationContent(_groupByLocationContent));
                  },
                  child: Row(
                    children: [
                      Checkbox(
                        value: _groupByLocationContent,
                        onChanged: (_) {},
                      ),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Group by Location')),
                    ],
                  ),
                ),
              ],
            ),
          // --- ADDED: Filter Button for Experiences and Content tabs ---
          if (_currentTabIndex == 1 || _currentTabIndex == 2)
            IconButton(
              icon: const Icon(Icons.filter_list),
              tooltip: 'Filter Items',
              onPressed: () {
                _showFilterDialog();
              },
            ),
        ],
      ),
      body: _isLoading
          ? Container(
              color: Colors.white,
              child: Center(
                child: CircularProgressIndicator(color: Colors.black54),
              ),
            )
          : Container(
              color: Colors.white,
              child: Column(
                children: [
                  // ADDED: Search Bar Area
                  Builder(// ADDED Builder for conditional width
                      builder: (context) {
                    final bool isDesktopWeb =
                        kIsWeb && MediaQuery.of(context).size.width > 600;

                    // Original search bar widget (TypeAheadField wrapped in Padding)
                    // This definition includes the original Padding and TypeAheadField configuration.
                    Widget searchBarWidget = Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12.0, vertical: 4.0),
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
                            // ADDED: Clear the TypeAhead controller when requested
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
                              controller:
                                  controller, // This is TypeAhead's controller
                              focusNode: focusNode,
                              autofocus: false,
                              decoration: InputDecoration(
                                labelText: 'Search your experiences',
                                prefixIcon: Icon(Icons.search,
                                    color: Theme.of(context).primaryColor),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(25.0),
                                ),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.clear),
                                  tooltip: 'Clear Search',
                                  onPressed: () {
                                    controller
                                        .clear(); // Clear TypeAhead's controller
                                    _searchController
                                        .clear(); // Clear state's controller
                                    FocusScope.of(context).unfocus();
                                    // setState(() {}); // Removed as TypeAheadField/TextField should update with controller
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
                            await _openExperience(suggestion);
                            if (mounted) {
                              setState(() {
                                _clearSearchOnNextBuild = true;
                              });
                            }
                            _searchController.clear();
                            FocusScope.of(context).unfocus();
                          },
                          emptyBuilder: (context) => const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Text('No experiences found.',
                                style: TextStyle(color: Colors.grey)),
                          ),
                        ),
                      ),
                    );

                    if (isDesktopWeb) {
                      return Center(
                        // Center the search bar on desktop
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width *
                              0.3, // 50% of screen width
                          child: searchBarWidget,
                        ),
                      );
                    } else {
                      return searchBarWidget; // Original layout for mobile/mobile-web
                    }
                  }),
                  // ADDED: TabBar placed here in the body's Column
                  Container(
                    color: Colors.white,
                    child: TabBar(
                      controller: _tabController,
                      tabs: const [
                        Tab(text: 'Categories'),
                        Tab(text: 'Experiences'),
                        Tab(text: 'Content'),
                      ],
                      labelColor: Theme.of(context).primaryColor,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: Theme.of(context).primaryColor,
                    ),
                  ),
                  // Existing TabBarView wrapped in Expanded
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // MODIFIED: Conditionally show category list or category experiences
                        // _selectedCategory == null
                        //     ? _buildCategoriesList()
                        //     : _buildCategoryExperiencesList(_selectedCategory!),
                        // --- MODIFIED: First tab now uses Column and toggle ---
                        Container(
                          color: Colors.white,
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7.0, vertical: 8.0),
                                child: Row(
                                  children: [
                                    if (_selectedCategory == null &&
                                        _selectedColorCategory == null)
                                      Builder(builder: (context) {
                                        final bool isViewingColor =
                                            _showingColorCategories;
                                        final int totalCount = isViewingColor
                                            ? _colorCategories.length
                                            : _categories.length;
                                        final int selectedCount = isViewingColor
                                            ? _selectedColorCategoryIds.length
                                            : _selectedCategoryIds.length;
                                        final bool allSelected =
                                            totalCount > 0 &&
                                                selectedCount == totalCount;
                                        final bool someSelected =
                                            selectedCount > 0 &&
                                                selectedCount < totalCount;

                                        if (_isSelectingCategories) {
                                          return Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Space to align with icon column (checkbox width ~40px + padding)
                                              Checkbox(
                                                value: allSelected
                                                    ? true
                                                    : (someSelected
                                                        ? null
                                                        : false),
                                                tristate: true,
                                                onChanged: (bool? newValue) {
                                                  setState(() {
                                                    // Interpret tap based on current aggregate state for intuitive UX
                                                    final bool selectAllNow =
                                                        someSelected
                                                            ? true // some -> all
                                                            : (allSelected
                                                                ? false // all -> none
                                                                : (newValue ==
                                                                    true)); // none -> all

                                                    if (isViewingColor) {
                                                      if (selectAllNow) {
                                                        _selectedColorCategoryIds
                                                          ..clear()
                                                          ..addAll(
                                                              _colorCategories
                                                                  .map((c) =>
                                                                      c.id));
                                                      } else {
                                                        _selectedColorCategoryIds
                                                            .clear();
                                                      }
                                                    } else {
                                                      if (selectAllNow) {
                                                        _selectedCategoryIds
                                                          ..clear()
                                                          ..addAll(
                                                              _categories.map(
                                                                  (c) => c.id));
                                                      } else {
                                                        _selectedCategoryIds
                                                            .clear();
                                                      }
                                                    }
                                                  });
                                                },
                                              ),
                                              const SizedBox(width: 6),
                                              IconButton(
                                                tooltip: 'Cancel selection',
                                                icon: const Icon(Icons.close),
                                                onPressed: () {
                                                  setState(() {
                                                    _isSelectingCategories =
                                                        false;
                                                    _selectedCategoryIds
                                                        .clear();
                                                    _selectedColorCategoryIds
                                                        .clear();
                                                  });
                                                },
                                              ),
                                              const SizedBox(width: 6),
                                              Builder(
                                                builder: (context) {
                                                  final VoidCallback?
                                                      onSharePressed =
                                                      selectedCount == 0
                                                          ? null
                                                          : () {
                                                              if (isViewingColor) {
                                                                final List<
                                                                        ColorCategory>
                                                                    selected =
                                                                    _colorCategories
                                                                        .where((c) =>
                                                                            _selectedColorCategoryIds.contains(c.id))
                                                                        .toList();
                                                                _showShareSelectedCategoriesBottomSheet(
                                                                  colorCategories:
                                                                      selected,
                                                                );
                                                              } else {
                                                                final List<
                                                                        UserCategory>
                                                                    selected =
                                                                    _categories
                                                                        .where((c) =>
                                                                            _selectedCategoryIds.contains(c.id))
                                                                        .toList();
                                                                _showShareSelectedCategoriesBottomSheet(
                                                                  userCategories:
                                                                      selected,
                                                                );
                                                              }
                                                            };
                                                  // In selection mode, always use compact icon-only to avoid overflow
                                                  return IconButton(
                                                    tooltip: 'Share',
                                                    icon: const Icon(
                                                        Icons.ios_share),
                                                    onPressed: onSharePressed,
                                                  );
                                                },
                                              ),
                                              const SizedBox(width: 6),
                                              Builder(
                                                builder: (context) {
                                                  final bool hasSelection =
                                                      selectedCount > 0;
                                                  final String tooltip = isViewingColor
                                                      ? 'Delete selected color categories'
                                                      : 'Delete selected categories';
                                                  return IconButton(
                                                    tooltip: tooltip,
                                                    icon: const Icon(
                                                        Icons.delete_outline),
                                                    color: Colors.red,
                                                    onPressed: hasSelection
                                                        ? () {
                                                            if (isViewingColor) {
                                                              _handleBulkDeleteSelectedColorCategories();
                                                            } else {
                                                              _handleBulkDeleteSelectedUserCategories();
                                                            }
                                                          }
                                                        : null,
                                                  );
                                                },
                                              ),
                                            ],
                                          );
                                        }
                                        return Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              tooltip: 'Select',
                                              icon: const Icon(
                                                  Icons.check_box_outlined),
                                              onPressed: () {
                                                setState(() {
                                                  _isSelectingCategories = true;
                                                });
                                              },
                                            ),
                                          ],
                                        );
                                      }),
                                    Expanded(child: SizedBox()),
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
                                              _selectedCategory =
                                                  null; // Clear selected text category when switching views
                                              _selectedColorCategory =
                                                  null; // Clear selected color category when switching views
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
                              Consumer<CategorySaveProgressNotifier>(
                                builder: (context, notifier, _) {
                                  final tasks = notifier.activeTasks;
                                  if (tasks.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0,
                                      vertical: 4.0,
                                    ),
                                    child: ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxHeight: 200),
                                      child: ListView.separated(
                                        shrinkWrap: true,
                                        physics: const ClampingScrollPhysics(),
                                        itemCount: tasks.length,
                                        itemBuilder: (context, index) =>
                                            _buildCategorySaveProgressTile(
                                                context, tasks[index]),
                                        separatorBuilder: (context, index) =>
                                            const SizedBox(height: 8),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              // Show reorder hint only when viewing main category lists (not individual category experiences)
                              // and only on mobile devices where reordering is available
                              if (_selectedCategory == null &&
                                  _selectedColorCategory == null &&
                                  !_isSelectingCategories &&
                                  !(kIsWeb &&
                                      MediaQuery.of(context).size.width > 600))
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 4.0),
                                  child: Text(
                                    'Tap and hold to reorder',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Colors.grey[600],
                                          fontStyle: FontStyle.italic,
                                        ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              Expanded(
                                child: _selectedCategory != null
                                    ? _buildCategoryExperiencesList(
                                        _selectedCategory!) // Still show experiences if a text category was selected
                                    // --- MODIFIED: Check for selected color category first --- START ---
                                    : _selectedColorCategory != null
                                        ? _buildColorCategoryExperiencesList(
                                            _selectedColorCategory!) // Show color experiences
                                        : _showingColorCategories
                                            ? _buildColorCategoriesList() // Show color list
                                            : _buildCategoriesList(), // Show text list
                                // --- MODIFIED: Check for selected color category first --- END ---
                              ),
                            ],
                          ),
                        ),
                        // --- END MODIFIED ---
                        Container(
                          color: Colors.white,
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7.0, vertical: 8.0),
                                child: Row(
                                  children: [
                                    Builder(builder: (context) {
                                      final int totalCount =
                                          _filteredExperiences.length;
                                      final int selectedCount =
                                          _selectedExperienceIds.length;
                                      final bool selecting =
                                          _isSelectingExperiences;
                                      final bool allSelected = selecting &&
                                          totalCount > 0 &&
                                          selectedCount == totalCount;
                                      final bool someSelected = selecting &&
                                          selectedCount > 0 &&
                                          !allSelected;

                                      if (!selecting) {
                                        return Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              tooltip: 'Select experiences',
                                              icon: const Icon(
                                                  Icons.check_box_outlined),
                                              onPressed: () {
                                                setState(() {
                                                  _isSelectingExperiences =
                                                      true;
                                                  _selectedExperienceIds
                                                      .clear();
                                                });
                                              },
                                            ),
                                          ],
                                        );
                                      }

                                      return Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Checkbox(
                                            value: allSelected
                                                ? true
                                                : (someSelected ? null : false),
                                            tristate: true,
                                            onChanged: totalCount == 0
                                                ? null
                                                : (bool? value) {
                                                    setState(() {
                                                      final bool selectAllNow =
                                                          someSelected
                                                              ? true
                                                              : (allSelected
                                                                  ? false
                                                                  : (value ??
                                                                      true));
                                                      if (selectAllNow) {
                                                        _selectedExperienceIds
                                                          ..clear()
                                                          ..addAll(
                                                              _filteredExperiences
                                                                  .map((e) =>
                                                                      e.id));
                                                      } else {
                                                        _selectedExperienceIds
                                                            .clear();
                                                      }
                                                    });
                                                  },
                                          ),
                                          const SizedBox(width: 6),
                                          IconButton(
                                            tooltip: 'Cancel selection',
                                            icon: const Icon(Icons.close),
                                            onPressed: () {
                                              setState(() {
                                                _isSelectingExperiences = false;
                                                _selectedExperienceIds.clear();
                                              });
                                            },
                                          ),
                                          const SizedBox(width: 6),
                                          IconButton(
                                            tooltip:
                                                'Share selected experiences',
                                            icon: const Icon(Icons.ios_share),
                                            onPressed: selectedCount == 0
                                                ? null
                                                : () {
                                                    unawaited(
                                                        _handleShareSelectedExperiences());
                                                  },
                                          ),
                                          const SizedBox(width: 6),
                                          IconButton(
                                            tooltip:
                                                'Delete selected experiences',
                                            icon: const Icon(
                                                Icons.delete_outline),
                                            color: Colors.red,
                                            onPressed: selectedCount == 0
                                                ? null
                                                : () {
                                                    unawaited(
                                                        _handleBulkDeleteSelectedExperiences());
                                                  },
                                          ),
                                        ],
                                      );
                                    }),
                                    const Expanded(child: SizedBox()),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: _buildExperiencesListView(),
                              ),
                            ],
                          ),
                        ),
                        // MODIFIED: Call builder for Content tab
                        Container(
                          color: Colors.white,
                          child: _buildContentTabBody(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddMenu,
        tooltip: 'Add',
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        child: const Icon(Icons.add),
      ),
    );
  }
  void _showAddMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.category_outlined),
                title: const Text('Add Category'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _showAddCategoryModal();
                },
              ),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Add Color Category'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _showAddColorCategoryModal();
                },
              ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('Add Experience'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _showAddExperienceModal();
                },
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Add Content'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _showAddContentModal();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddContentModal() async {
    // Open ReceiveShareScreen as a modal, with UI disabled until URL entered
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.95,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return ChangeNotifierProvider(
              create: (_) => ReceiveShareProvider(),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: ReceiveShareScreen(
                  sharedFiles: const [],
                  onCancel: () => Navigator.of(context).pop(),
                  requireUrlFirst: true,
                ),
              ),
            );
          },
        );
      },
    );
  }

  // REFACTORED: Extracted list item builder for reuse
  Widget _buildExperienceListItem(Experience experience) {
    // Find the matching category icon and name using categoryId
    final UserCategory category = _categories.firstWhere(
      (cat) => cat.id == experience.categoryId,
      orElse: () => UserCategory(
        id: '',
        name: 'Uncategorized',
        icon: '?',
        ownerUserId: '',
      ),
    );
    final categoryIcon = category.icon;
    final categoryName = category.name;

    // Get the full address
    final fullAddress = experience.location.address;
    // Determine leading box background color from color category with opacity
    final colorCategoryForBox = _colorCategories.firstWhereOrNull(
      (cc) => cc.id == experience.colorCategoryId,
    );
    final Color leadingBoxColor = colorCategoryForBox != null
        ? _parseColor(colorCategoryForBox.colorHex).withOpacity(0.5)
        : Colors.white;
    // Number of related content items
    final int contentCount = experience.sharedMediaItemIds.length;
    final SharePermission? sharePermission =
        _sharedExperiencePermissions[experience.id];
    final bool isShared = sharePermission != null;
    final bool isOwnerShared =
        _ownedSharedExperienceIds.contains(experience.id);
    final String? ownerName = isShared
        ? (_shareOwnerNames[sharePermission!.ownerUserId] ?? 'Someone')
        : null;
    final ShareAccessLevel effectiveAccessLevel =
        _effectiveAccessLevelForExperience(experience);
    final String? shareLabel = isShared
        ? _buildSharedByLabel(
            permission: sharePermission!,
            ownerName: ownerName ?? 'Someone',
            overrideAccessLevel: effectiveAccessLevel,
          )
        : (isOwnerShared ? 'Shared' : null);

    final bool isSelecting = _isSelectingExperiences;
    final bool isSelected = _selectedExperienceIds.contains(experience.id);
    const double playButtonDiameter = 36.0;
    const double playIconSize = 20.0;
    const double badgeDiameter = 18.0;
    const double badgeFontSize = 11.0;
    const double badgeBorderWidth = 2.0;
    const double badgeOffset = -3.0;

    final List<ColorCategory> otherColorCategories = experience
        .otherColorCategoryIds
        .map((id) => _colorCategories.firstWhereOrNull((cc) => cc.id == id))
        .whereType<ColorCategory>()
        .toList();
    final bool hasOtherCategories = experience.otherCategories.isNotEmpty;
    final bool hasOtherColorCategories = otherColorCategories.isNotEmpty;
    final bool hasNotes = experience.additionalNotes != null &&
        experience.additionalNotes!.isNotEmpty;
    final bool shouldShowSubRow = hasOtherCategories ||
        hasOtherColorCategories ||
        contentCount > 0 ||
        (hasNotes && !hasOtherCategories && !hasOtherColorCategories);

    final Widget leadingBase = Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: leadingBoxColor,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                categoryIcon,
                style: const TextStyle(fontSize: 28),
              ),
            ],
          ),
        ),
      ),
    );

    final Widget leadingWidget = isSelecting
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: isSelected,
                onChanged: (bool? value) {
                  setState(() {
                    if (value ?? false) {
                      _selectedExperienceIds.add(experience.id);
                    } else {
                      _selectedExperienceIds.remove(experience.id);
                    }
                  });
                },
              ),
              const SizedBox(width: 4),
              leadingBase,
            ],
          )
        : leadingBase;

    return ListTile(
      key: ValueKey(experience.id), // Use experience ID as key
      contentPadding: const EdgeInsets.symmetric(horizontal: 8.0),
      visualDensity: const VisualDensity(horizontal: -4),
      isThreeLine: true,
      titleAlignment: ListTileTitleAlignment.threeLine,
      leading: leadingWidget,
      minLeadingWidth: 56,
      selected: isSelecting && isSelected,
      title: Text(
        experience.name,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (shareLabel != null)
            Text(
              shareLabel,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
          if (fullAddress != null && fullAddress.isNotEmpty)
            Text(
              fullAddress,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          // Row for subcategory icons and/or content count; also lift notes here when no subcategories
          if (shouldShowSubRow)
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
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
                              ...experience.otherCategories
                                  .map((categoryId) {
                                final otherCategory =
                                    _categories.firstWhereOrNull(
                                  (cat) => cat.id == categoryId,
                                );
                                if (otherCategory != null) {
                                  return Text(
                                    otherCategory.icon,
                                    style: const TextStyle(fontSize: 14),
                                  );
                                }
                                return const SizedBox.shrink();
                              }),
                              ...otherColorCategories.map((colorCategory) {
                                final Color chipColor = colorCategory.color;
                                return Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: chipColor,
                                    shape: BoxShape.circle,
                                  ),
                                );
                              }),
                            ],
                          ),
                        if (experience.additionalNotes != null &&
                            experience.additionalNotes!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(Icons.notes,
                                    size: 14, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    experience.additionalNotes!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(fontStyle: FontStyle.italic),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
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
                            child: Icon(
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
          // Separate notes block is suppressed because notes render in the subcategory row
          if (experience.additionalNotes != null &&
              experience.additionalNotes!.isNotEmpty &&
              false)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                experience.additionalNotes!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
      onTap: () async {
        if (_isSelectingExperiences) {
          setState(() {
            if (_selectedExperienceIds.contains(experience.id)) {
              _selectedExperienceIds.remove(experience.id);
            } else {
              _selectedExperienceIds.add(experience.id);
            }
          });
        } else {
          await _openExperience(experience);
        }
      },
      onLongPress: () {
        if (!_isSelectingExperiences) {
          setState(() {
            _isSelectingExperiences = true;
            _selectedExperienceIds
              ..clear()
              ..add(experience.id);
          });
        }
      },
    );
  }

  // ADDED: Widget builder for an Experience Grid Item (for web)
  Widget _buildExperienceGridItem(Experience experience, bool isDesktopWeb) {
    // ADDED isDesktopWeb parameter
    final category =
        _categories.firstWhereOrNull((cat) => cat.id == experience.categoryId);
    final categoryIcon = category?.icon ?? 'Γ¥ô';
    final colorCategory = _colorCategories
        .firstWhereOrNull((cc) => cc.id == experience.colorCategoryId);
    final color = colorCategory != null
        ? _parseColor(colorCategory.colorHex)
        : Theme.of(context).disabledColor;
    final String? locationArea = experience.location.getFormattedArea();
    final SharePermission? sharePermission =
        _sharedExperiencePermissions[experience.id];

    final String? ownerName = sharePermission != null
        ? (_shareOwnerNames[sharePermission.ownerUserId] ?? 'Someone')
        : null;

    String? photoUrl;
    if (experience.location.photoResourceName != null &&
        experience.location.photoResourceName!.isNotEmpty) {
      photoUrl = GoogleMapsService.buildPlacePhotoUrlFromResourceName(
        experience.location.photoResourceName,
        maxWidthPx: 600,
        maxHeightPx: 400,
      );
    }
    photoUrl ??= experience.location.photoUrl;
    if ((photoUrl == null || photoUrl.isEmpty) &&
        (experience.location.placeId != null &&
            experience.location.placeId!.isNotEmpty) &&
        !_photoRefreshAttempts.contains(experience.id)) {
      _photoRefreshAttempts.add(experience.id);
      _refreshPhotoResourceNameForExperience(experience);
    }

    Widget categoryIconWidget = Container(
      height: 60, // MODIFIED: Reduced height
      color: color.withOpacity(0.15),
      padding: const EdgeInsets.symmetric(horizontal: 8.0), // Add some padding
      child: Center(
        child: Row(
          // MODIFIED: Use a Row for icon and text on the same line
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Text(
              categoryIcon,
              style: TextStyle(
                  fontSize: 20, color: color), // MODIFIED: Smaller icon size
            ),
            const SizedBox(width: 8), // Space between icon and text
            if (category != null) // Add category name if category exists
              Expanded(
                // Use Expanded to handle long names
                child: Text(
                  category.name,
                  style: TextStyle(
                      fontSize: 14,
                      color:
                          color.withOpacity(0.9)), // MODIFIED: Style for name
                  textAlign: TextAlign.left, // Align to left after icon
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );

    // Content (name, location, color category)
    Widget textContentColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 4.0),
          child: Text(
            experience.name,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  // Conditional color will be applied if it's part of a stack with background
                ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (locationArea != null && locationArea.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              locationArea,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const Spacer(),
        if (colorCategory != null)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Icon(Icons.circle,
                    color:
                        colorCategory.color /* Use parsed color from model */,
                    size: 10),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    colorCategory.name,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorCategory.color /* Use parsed color */),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    Widget lowerSectionContent;
    if (isDesktopWeb && photoUrl != null && photoUrl.isNotEmpty) {
      // Apply white text color for contrast against photo background
      Widget textContentWithWhiteColor = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 4.0),
            child: Text(
              experience.name,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white, // White text
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (locationArea != null && locationArea.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                locationArea,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white70), // White text
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const Spacer(),
          if (colorCategory != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  // Use a white circle or icon if colorCategory.color is too dark for the overlay
                  Icon(Icons.circle,
                      color: colorCategory.color,
                      size: 10), // MODIFIED: Use actual category color
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      colorCategory.name,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white), // White text for label
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );

      lowerSectionContent = Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Image.network(
              photoUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2.0));
              },
              errorBuilder: (context, error, stackTrace) {
                if (!_photoRefreshAttempts.contains(experience.id) &&
                    (experience.location.placeId != null &&
                        experience.location.placeId!.isNotEmpty)) {
                  _photoRefreshAttempts.add(experience.id);
                  _refreshPhotoResourceNameForExperience(experience);
                }
                return Container(
                  color: Colors.grey[300], // Placeholder if image fails
                  child: Center(
                      child: Icon(Icons.broken_image_outlined,
                          color: Colors.grey[500])),
                );
              },
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black
                  .withOpacity(0.5), // Dark overlay for text readability
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(
                0), // Padding is handled by textContentWithWhiteColor
            child: textContentWithWhiteColor,
          ),
        ],
      );
    } else {
      // If not desktop web or no photo, use the original textContentColumn directly
      lowerSectionContent = textContentColumn;
    }

    final bool isSelecting = _isSelectingExperiences;
    final bool isSelected = _selectedExperienceIds.contains(experience.id);

    final ShapeBorder cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12.0),
      side: isSelecting && isSelected
          ? BorderSide(color: Theme.of(context).primaryColor, width: 2)
          : BorderSide(color: Colors.transparent, width: 1),
    );

    final Widget card = Card(
      key: ValueKey('experience_grid_${experience.id}'),
      clipBehavior: Clip.antiAlias,
      elevation: 2.0,
      shape: cardShape,
      child: InkWell(
        onTap: () async {
          if (_isSelectingExperiences) {
            setState(() {
              if (_selectedExperienceIds.contains(experience.id)) {
                _selectedExperienceIds.remove(experience.id);
              } else {
                _selectedExperienceIds.add(experience.id);
              }
            });
          } else {
            await _openExperience(experience);
          }
        },
        onLongPress: () {
          if (!_isSelectingExperiences) {
            setState(() {
              _isSelectingExperiences = true;
              _selectedExperienceIds
                ..clear()
                ..add(experience.id);
            });
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            categoryIconWidget, // Category icon always on top
            Expanded(
                child:
                    lowerSectionContent), // Lower section takes remaining space
            // Padding(
            //   padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 4.0),
            //   child: Text(
            // ... existing code ...
          ],
        ),
      ),
    );

    if (!isSelecting) {
      return card;
    }

    return Stack(
      children: [
        card,
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Checkbox(
              value: isSelected,
              onChanged: (bool? value) {
                setState(() {
                  if (value ?? false) {
                    _selectedExperienceIds.add(experience.id);
                  } else {
                    _selectedExperienceIds.remove(experience.id);
                  }
                });
              },
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
      ],
    );
  }
  // MODIFIED: Widget builder for the Experience List View uses the refactored item builder
  Widget _buildExperiencesListView() {
    if (_filteredExperiences.isEmpty) {
      bool filtersActive = _selectedCategoryIds.isNotEmpty ||
          _selectedColorCategoryIds.isNotEmpty;
      return Center(
          child: Text(filtersActive
              ? 'No experiences match the current filters.'
              : 'No experiences found. Add some!'));
    }

    final bool isDesktopWeb = kIsWeb && MediaQuery.of(context).size.width > 600;

    // Build count header widget
    Widget countHeader = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Text(
        '${_filteredExperiences.length} ${_filteredExperiences.length == 1 ? 'Experience' : 'Experiences'}',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w400,
              color: Colors.grey,
            ),
        textAlign: TextAlign.center,
      ),
    );

    if (isDesktopWeb) {
      final screenWidth = MediaQuery.of(context).size.width;
      const double contentMaxWidth = 1200.0;
      const double defaultPadding = 12.0;

      double horizontalPadding;
      if (screenWidth > contentMaxWidth) {
        horizontalPadding = (screenWidth - contentMaxWidth) / 2;
      } else {
        horizontalPadding = defaultPadding;
      }

      // Web: Use CustomScrollView with Slivers to include header
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: countHeader),
          SliverPadding(
            padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding, vertical: defaultPadding),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12.0,
                crossAxisSpacing: 12.0,
                childAspectRatio: 0.75,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return _buildExperienceGridItem(
                      _filteredExperiences[index], isDesktopWeb);
                },
                childCount: _filteredExperiences.length,
              ),
            ),
          ),
          // Spacer to avoid overlap with FAB
          SliverToBoxAdapter(child: SizedBox(height: _bottomListPadding)),
        ],
      );
    } else {
      // Mobile: Use ListView with header as first item
      // When grouping, build a flattened list of headers + items ordered by the primary sort.
      List<Map<String, Object>>? expRegionStructured;
      if (_groupByLocationExperiences) {
        expRegionStructured = _buildDynamicExperienceGrouping();
      } else if (_groupByCityExperiences) {
        final Map<String, List<Experience>> cityItems = {};
        final Map<String, String> cityDisplay = {};
        // Group experiences by city key
        for (final exp in _filteredExperiences) {
          final display = (exp.location.city ?? '').trim();
          final key = display.isEmpty ? '' : display.toLowerCase();
          cityDisplay[key] = display.isEmpty ? 'Unknown city' : display;
          cityItems.putIfAbsent(key, () => <Experience>[]).add(exp);
        }
        // Sort items within each city by the selected primary sort
        for (final entry in cityItems.entries) {
          final list = entry.value;
          if (_experienceSortType == ExperienceSortType.mostRecent) {
            list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          } else if (_experienceSortType == ExperienceSortType.alphabetical) {
            list.sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          } else if (_experienceSortType == ExperienceSortType.distanceFromMe) {
            // Keep the global order, which is already distance-ascending due to prior sort
            // So no per-city re-sort is needed
          }
        }
        // Determine city header ordering by primary sort
        List<String> cityKeys = cityItems.keys.toList();
        if (_experienceSortType == ExperienceSortType.mostRecent) {
          cityKeys.sort((ka, kb) {
            final maxA = cityItems[ka]!.map((e) => e.updatedAt).fold<DateTime?>(
                    null, (p, c) => p == null || c.isAfter(p) ? c : p) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final maxB = cityItems[kb]!.map((e) => e.updatedAt).fold<DateTime?>(
                    null, (p, c) => p == null || c.isAfter(p) ? c : p) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            if (ka.isEmpty && kb.isEmpty) return 0;
            if (ka.isEmpty) return 1; // Unknown last
            if (kb.isEmpty) return -1;
            return maxB.compareTo(maxA);
          });
        } else if (_experienceSortType == ExperienceSortType.alphabetical) {
          cityKeys.sort((ka, kb) {
            if (ka.isEmpty && kb.isEmpty) return 0;
            if (ka.isEmpty) return 1;
            if (kb.isEmpty) return -1;
            return cityDisplay[ka]!
                .toLowerCase()
                .compareTo(cityDisplay[kb]!.toLowerCase());
          });
        } else if (_experienceSortType == ExperienceSortType.distanceFromMe) {
          // Use the index of the first occurrence in the globally distance-sorted list
          final Map<String, int> firstIndex = {};
          for (int i = 0; i < _filteredExperiences.length; i++) {
            final exp = _filteredExperiences[i];
            final key = (exp.location.city ?? '').trim().toLowerCase();
            firstIndex.putIfAbsent(key, () => i);
          }
          cityKeys.sort((ka, kb) {
            if (ka.isEmpty && kb.isEmpty) return 0;
            if (ka.isEmpty) return 1;
            if (kb.isEmpty) return -1;
            return (firstIndex[ka] ?? 1 << 30)
                .compareTo(firstIndex[kb] ?? 1 << 30);
          });
        }
        // Build flattened list
        final List<Map<String, Object>> flattened = [];
        for (final key in cityKeys) {
          final display = cityDisplay[key] ?? 'Unknown city';
          flattened.add({'header': display, 'key': key});
          for (final exp in cityItems[key]!) {
            flattened.add({'item': exp, 'key': key});
          }
        }
        expRegionStructured = flattened;
      } else if (_groupByCountryExperiences) {
        final Map<String, List<Experience>> countryItems = {};
        final Map<String, String> countryDisplay = {};
        // Group experiences by country key
        for (final exp in _filteredExperiences) {
          final display = (exp.location.country ?? '').trim();
          final key = display.isEmpty ? '' : display.toLowerCase();
          countryDisplay[key] = display.isEmpty ? 'Unknown country' : display;
          countryItems.putIfAbsent(key, () => <Experience>[]).add(exp);
        }
        // Sort items within each country by the selected primary sort
        for (final entry in countryItems.entries) {
          final list = entry.value;
          if (_experienceSortType == ExperienceSortType.mostRecent) {
            list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          } else if (_experienceSortType == ExperienceSortType.alphabetical) {
            list.sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          } else if (_experienceSortType == ExperienceSortType.distanceFromMe) {
            // Keep the global order (no per-country re-sort needed)
          }
        }
        // Determine country header ordering by primary sort
        List<String> countryKeys = countryItems.keys.toList();
        if (_experienceSortType == ExperienceSortType.mostRecent) {
          countryKeys.sort((ka, kb) {
            final maxA = countryItems[ka]!
                    .map((e) => e.updatedAt)
                    .fold<DateTime?>(
                        null, (p, c) => p == null || c.isAfter(p) ? c : p) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final maxB = countryItems[kb]!
                    .map((e) => e.updatedAt)
                    .fold<DateTime?>(
                        null, (p, c) => p == null || c.isAfter(p) ? c : p) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            if (ka.isEmpty && kb.isEmpty) return 0;
            if (ka.isEmpty) return 1; // Unknown last
            if (kb.isEmpty) return -1;
            return maxB.compareTo(maxA);
          });
        } else if (_experienceSortType == ExperienceSortType.alphabetical) {
          countryKeys.sort((ka, kb) {
            if (ka.isEmpty && kb.isEmpty) return 0;
            if (ka.isEmpty) return 1;
            if (kb.isEmpty) return -1;
            return (countryDisplay[ka] ?? '')
                .toLowerCase()
                .compareTo((countryDisplay[kb] ?? '').toLowerCase());
          });
        } else if (_experienceSortType == ExperienceSortType.distanceFromMe) {
          // Use the index of the first occurrence in the globally distance-sorted list
          final Map<String, int> firstIndex = {};
          for (int i = 0; i < _filteredExperiences.length; i++) {
            final exp = _filteredExperiences[i];
            final key = (exp.location.country ?? '').trim().toLowerCase();
            firstIndex.putIfAbsent(key, () => i);
          }
          countryKeys.sort((ka, kb) {
            if (ka.isEmpty && kb.isEmpty) return 0;
            if (ka.isEmpty) return 1;
            if (kb.isEmpty) return -1;
            return (firstIndex[ka] ?? 1 << 30)
                .compareTo(firstIndex[kb] ?? 1 << 30);
          });
        }
        // Build flattened list
        final List<Map<String, Object>> flattened = [];
        for (final key in countryKeys) {
          final display = countryDisplay[key] ?? 'Unknown country';
          flattened.add({'header': display, 'key': key});
          for (final exp in countryItems[key]!) {
            flattened.add({'item': exp, 'key': key});
          }
        }
        expRegionStructured = flattened;
      }

      return ListView.builder(
        key: ValueKey('experiences_${_filteredExperiences.length}_${_filteredExperiences.hashCode}'),
        controller: _experiencesScrollController,
        padding: const EdgeInsets.only(bottom: _bottomListPadding),
        itemCount: (expRegionStructured != null
                ? expRegionStructured.length
                : _filteredExperiences.length) +
            1 + // +1 for header
            (_isLoadingMoreExperiences ? 1 : 0), // +1 for loading indicator
        itemBuilder: (context, index) {
          if (index == 0) {
            return countHeader;
          }
          
          // Check if this is the loading indicator at the end
          final int dataCount = (expRegionStructured != null
              ? expRegionStructured.length
              : _filteredExperiences.length) + 1;
          if (index == dataCount && _isLoadingMoreExperiences) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: CircularProgressIndicator(color: Colors.black54),
              ),
            );
          }
          
          if (expRegionStructured != null) {
            final entry = expRegionStructured[index - 1];
            if (entry.containsKey('header')) {
              final level = entry['level'] as String?;
              final key = entry['key'] as String;
              final displayRegion = entry['header'] as String;
              if (_groupByLocationExperiences && level != null) {
                // Dynamic grouping: use unified expansion map and hierarchical levels
                final bool isExpanded =
                    _locationExpansionExperiences[key] ?? false;
                final TextStyle base = Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700]) ??
                    const TextStyle(fontWeight: FontWeight.bold);
                const order = [
                  'country',
                  'L1',
                  'L2',
                  'L3',
                  'L4',
                  'L5',
                  'L6',
                  'L7',
                  'LOC'
                ];
                int depth = order.indexOf(level);
                depth = depth < 0 ? 0 : depth;
                final TextStyle style = level == 'country'
                    ? base.copyWith(fontSize: (base.fontSize ?? 14) + 4)
                    : base.copyWith(
                        fontSize: (base.fontSize ?? 14) + (depth >= 1 ? 2 : 0));
                final double leftPadding = (depth * 16).toDouble();
                return InkWell(
                  onTap: () {
                    setState(() {
                      _locationExpansionExperiences[key] = !isExpanded;
                    });
                  },
                  child: Container(
                    width: double.infinity,
                    color: Colors.white,
                    padding: EdgeInsets.fromLTRB(16 + leftPadding, 12, 16, 6),
                    child: Row(
                      children: [
                        Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                            color: Colors.grey[700], size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            displayRegion,
                            style: style,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              } else {
                // Legacy country/state/city grouping path
                final bool isExpanded = (level == 'country')
                    ? (_countryExpansionExperiences[key] ?? false)
                    : (level == 'state')
                        ? (_stateExpansionExperiences[key] ?? false)
                        : (level == 'city')
                            ? (_cityExpansionExperiences[key] ?? false)
                            : (_noLocationExperiencesExpanded);
                final TextStyle base = Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700]) ??
                    const TextStyle(fontWeight: FontWeight.bold);
                final TextStyle style = level == 'country'
                    ? base.copyWith(fontSize: (base.fontSize ?? 14) + 4)
                    : level == 'state'
                        ? base.copyWith(fontSize: (base.fontSize ?? 14) + 2)
                        : base;
                final double leftPadding = level == 'country'
                    ? 0
                    : level == 'state'
                        ? 16
                        : 32;
                return InkWell(
                  onTap: () {
                    setState(() {
                      if (level == 'country') {
                        _countryExpansionExperiences[key] = !isExpanded;
                      } else if (level == 'state') {
                        _stateExpansionExperiences[key] = !isExpanded;
                      } else if (level == 'city') {
                        _cityExpansionExperiences[key] = !isExpanded;
                      } else {
                        _noLocationExperiencesExpanded = !isExpanded;
                      }
                    });
                  },
                  child: Container(
                    width: double.infinity,
                    color: Colors.white,
                    padding: EdgeInsets.fromLTRB(16 + leftPadding, 12, 16, 6),
                    child: Row(
                      children: [
                        Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                            color: Colors.grey[700], size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            displayRegion,
                            style: style,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
            } else {
              final exp = entry['item'] as Experience;
              return _buildExperienceListItem(exp);
            }
          }
          // Not grouped: simple list
          final exp = _filteredExperiences[index - 1];
          return _buildExperienceListItem(exp);
        },
      );
    }
  }

  // ADDED: Widget to display experiences for a specific category
  Widget _buildCategoryExperiencesList(UserCategory category) {
    final categoryExperiences = _experiences
        .where((exp) =>
            exp.categoryId == category.id ||
            exp.otherCategories.contains(category
                .id)) // MODIFIED: Include experiences with this category as primary OR in otherCategories
        .toList(); // Filter experiences

    // Apply the current experience sort order to this sublist
    // Note: This creates a sorted copy, doesn't modify the original _experiences
    if (_experienceSortType == ExperienceSortType.alphabetical) {
      categoryExperiences
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else if (_experienceSortType == ExperienceSortType.mostRecent) {
      categoryExperiences.sort((a, b) {
        return b.updatedAt.compareTo(a.updatedAt);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row with back button and category name
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to Categories',
                onPressed: () {
                  setState(() {
                    _selectedCategory = null; // Go back to category list
                  });
                },
              ),
              const SizedBox(width: 8),
              // Category title with icon, and optional shared-by subtext
              Expanded(
                child: Builder(builder: (context) {
                  final SharePermission? permission =
                      _sharedCategoryPermissions[category.id];
                  final bool isShared = permission != null;
                  final String? ownerName = isShared
                      ? (_shareOwnerNames[permission!.ownerUserId] ?? 'Someone')
                      : null;
                  final String? shareLabel = isShared
                      ? _buildSharedByLabel(
                          permission: permission!,
                          ownerName: ownerName ?? 'Someone',
                        )
                      : null;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            child: Center(child: Text(category.icon)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              category.name,
                              style: Theme.of(context).textTheme.titleLarge,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (shareLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 28),
                          child: Text(
                            shareLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                    ],
                  );
                }),
              ),

              Builder(builder: (context) {
                final SharePermission? permission =
                    _sharedCategoryPermissions[category.id];
                final bool isShared = permission != null;
                final bool canEditCategory = !isShared ||
                    permission!.accessLevel == ShareAccessLevel.edit;
                final bool canManageCategory = !isShared;
                return PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'Category Options',
                  color: Colors.white,
                  onSelected: (String result) {
                    switch (result) {
                      case 'edit':
                        _showEditSingleCategoryModal(category);
                        break;
                      case 'share':
                        _showShareCategoryBottomSheet(category);
                        break;
                      case 'delete':
                        _showDeleteCategoryConfirmation(category);
                        break;
                    }
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'edit',
                      enabled: canEditCategory,
                      child: const ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'share',
                      enabled: canManageCategory,
                      child: const ListTile(
                        leading: Icon(Icons.ios_share),
                        title: Text('Share'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      enabled: canManageCategory,
                      child: const ListTile(
                        leading: Icon(Icons.delete_outline, color: Colors.red),
                        title:
                            Text('Delete', style: TextStyle(color: Colors.red)),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
        const Divider(height: 1),
        // List of experiences for this category
        Expanded(
          child: categoryExperiences.isEmpty
              ? Center(
                  child: Text(
                      'No experiences found in the "${category.name}" category.'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: _bottomListPadding),
                  itemCount: categoryExperiences.length,
                  itemBuilder: (context, index) {
                    // Use the refactored item builder
                    return _buildExperienceListItem(categoryExperiences[index]);
                  },
                ),
        ),
      ],
    );
  }

  // --- REFACTORED: Widget builder for the Content Tab Body --- ///
  Widget _buildContentTabBody() {
    if (!_contentLoaded || _isContentLoading) {
      // Show loader on first open while content is being fetched/grouped
      return Container(
        color: Colors.white,
        child: Center(
          child: CircularProgressIndicator(color: Colors.black54),
        ),
      );
    }
    if (_filteredGroupedContentItems.isEmpty) {
      final bool filtersActive = _selectedCategoryIds.isNotEmpty ||
          _selectedColorCategoryIds.isNotEmpty;
      return Center(
          child: Text(filtersActive
              ? 'No content matches the current filters.'
              : 'No shared content found across experiences.'));
    }

    final bool isDesktopWeb = kIsWeb && MediaQuery.of(context).size.width > 600;

    // Build count header widget
    Widget countHeader = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Text(
        '${_filteredGroupedContentItems.length} ${_filteredGroupedContentItems.length == 1 ? 'Saved Content' : 'Saved Content'}',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w400,
              color: Colors.grey,
            ),
        textAlign: TextAlign.center,
      ),
    );

    if (isDesktopWeb) {
      final screenWidth = MediaQuery.of(context).size.width;
      const double contentMaxWidth = 1200.0;
      const double defaultPadding = 10.0;

      double horizontalPadding;
      if (screenWidth > contentMaxWidth) {
        horizontalPadding = (screenWidth - contentMaxWidth) / 2;
      } else {
        horizontalPadding = defaultPadding;
      }

      // Web: Use CustomScrollView with Slivers to include header
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: countHeader),
          SliverPadding(
            padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding, vertical: defaultPadding),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10.0,
                crossAxisSpacing: 10.0,
                childAspectRatio: 0.6,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return _buildContentGridItem(
                      _filteredGroupedContentItems[index], index);
                },
                childCount: _filteredGroupedContentItems.length,
              ),
            ),
          ),
        ],
      );
    } else {
      // Mobile or Mobile Web
      if (_groupByLocationContent) {
        final List<Map<String, Object>> flat = _buildDynamicContentGrouping();
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          itemCount: flat.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: countHeader,
              );
            }
            final Map<String, Object> entry =
                flat[index - 1] as Map<String, Object>;
            if (entry.containsKey('header')) {
              final display = entry['header'] as String;
              final level = entry['level'] as String;
              final key = entry['key'] as String;
              final bool isExpanded = _locationExpansionContent[key] ?? false;
              final TextStyle base = Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700]) ??
                  const TextStyle(fontWeight: FontWeight.bold);
              int depth = 0;
              const order = [
                'country',
                'L1',
                'L2',
                'L3',
                'L4',
                'L5',
                'L6',
                'L7',
                'LOC'
              ];
              depth = order.indexOf(level);
              depth = depth < 0 ? 0 : depth;
              final TextStyle style = level == 'country'
                  ? base.copyWith(fontSize: (base.fontSize ?? 14) + 4)
                  : base.copyWith(
                      fontSize: (base.fontSize ?? 14) + (depth >= 1 ? 2 : 0));
              final double leftPadding = (depth * 16).toDouble();
              return InkWell(
                onTap: () {
                  setState(() {
                    _locationExpansionContent[key] = !isExpanded;
                  });
                },
                child: Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding: EdgeInsets.fromLTRB(leftPadding, 8, 0, 8),
                  child: Row(
                    children: [
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: Colors.grey[700],
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          display,
                          style: style,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            } else {
              final group = entry['item'] as GroupedContentItem;
              final pathKey = entry['pathKey'] as String;
              final bool expanded = _locationExpansionContent[pathKey] ?? false;
              if (!expanded) return const SizedBox.shrink();
              final int ordinal = (entry['ordinal'] as int?) ?? (index - 1);
              return _buildContentListItem(group, ordinal);
            }
          },
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        itemCount: _filteredGroupedContentItems.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: countHeader,
            );
          }
          final group = _filteredGroupedContentItems[index - 1];
          return _buildContentListItem(group, index - 1);
        },
      );
    }
  }
  // --- ADDED: Method to show delete confirmation dialog for content ---
  Future<void> _showDeleteContentConfirmation(GroupedContentItem group) async {
    final mediaItem = group.mediaItem;
    final associatedExperiences = group.associatedExperiences;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Content?'),
        content: Column(
          // Use Column for better layout
          mainAxisSize: MainAxisSize.min, // Prevent excessive height
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to permanently delete this content?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // Display the content path or a placeholder
            Text(
              mediaItem.path.contains('instagram.com')
                  ? 'Instagram Post'
                  : mediaItem.path.contains('facebook.com') ||
                          mediaItem.path.contains('fb.com') ||
                          mediaItem.path.contains('fb.watch')
                      ? 'Facebook Post'
                      : mediaItem.path.contains('tiktok.com') ||
                              mediaItem.path.contains('vm.tiktok.com')
                          ? 'TikTok Post'
                          : mediaItem.path.contains('youtube.com') ||
                                  mediaItem.path.contains('youtu.be')
                              ? 'YouTube Video'
                              : mediaItem.path
                                  .split('/')
                                  .last, // Show filename if possible
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontStyle: FontStyle.italic),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            Text(
                'It will also be unlinked from the following ${associatedExperiences.length} experience(s):'),
            const SizedBox(height: 8),
            // List associated experiences concisely
            Container(
              constraints: BoxConstraints(maxHeight: 100), // Limit height
              child: SingleChildScrollView(
                // Make it scrollable if many
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: associatedExperiences
                      .map((exp) => Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: Text('ΓÇó ${exp.name}',
                                style: Theme.of(context).textTheme.bodySmall),
                          ))
                      .toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'This action cannot be undone.',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
        ),
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
      // Show loading indicator while deleting
      setState(() => _isLoading = true);
      try {
        // --- Call ExperienceService method ---
        await _experienceService.deleteSharedMediaItemAndUnlink(
          mediaItem.id,
          associatedExperiences.map((e) => e.id).toList(),
        );

        if (mounted) {
          // Hide loading indicator
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Content deleted.')),
          );
          _loadData(); // Refresh the screen
        }
      } catch (e) {
        if (mounted) {
          // Hide loading indicator
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting content: $e')),
          );
        }
      }
    }
  }
  // --- END ADDED ---

  Future<void> _handleShareSelectedExperiences() async {
    final List<Experience> selectedExperiences = _experiences
        .where((experience) => _selectedExperienceIds.contains(experience.id))
        .toList();
    if (selectedExperiences.isEmpty) {
      return;
    }

    final List<Experience> shareableExperiences = selectedExperiences
        .where(
            (experience) => _sharedExperiencePermissions[experience.id] == null)
        .toList();
    final List<Experience> restrictedExperiences = selectedExperiences
        .where(
            (experience) => _sharedExperiencePermissions[experience.id] != null)
        .toList();

    if (shareableExperiences.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'You can only create shareable links for experiences you own.')),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final ExperienceShareService shareService = ExperienceShareService();
    final List<MapEntry<Experience, String>> createdLinks = [];
    final List<String> errors = [];
    String? bulkUrl;
    List<Experience> bulkExperiences = const <Experience>[];

    if (shareableExperiences.length > 1) {
      bulkExperiences = List<Experience>.from(shareableExperiences);
      try {
        bulkUrl = await shareService.createLinkShareForMultiple(
          experiences: shareableExperiences,
          expiresAt: DateTime.now().add(const Duration(days: 30)),
          grantEdit: false,
        );
      } catch (e) {
        errors.add('Multi-share: $e');
      }
    } else {
      final Experience experience = shareableExperiences.first;
      try {
        final String url = await shareService.createLinkShare(
          experience: experience,
          expiresAt: DateTime.now().add(const Duration(days: 30)),
          linkMode: 'separate_copy',
          grantEdit: false,
        );
        createdLinks.add(MapEntry(experience, url));
      } catch (e) {
        errors.add('${experience.name}: $e');
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = false;
    });

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    if (bulkUrl != null) {
      final String multiUrl = bulkUrl!;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Shareable link created'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Included experiences (${bulkExperiences.length}):',
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  ...bulkExperiences.map(
                    (exp) => Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle_outline,
                              size: 16, color: Colors.green),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              exp.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Share link',
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SelectableText(
                          multiUrl,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy link',
                        icon: const Icon(Icons.copy),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: multiUrl),
                          );
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(content: Text('Link copied')),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await Share.share(multiUrl);
                  Navigator.of(ctx).pop();
                },
                child: const Text('Share'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } else if (createdLinks.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text(createdLinks.length == 1
                ? 'Shareable link created'
                : 'Shareable links created'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: createdLinks.map((entry) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      entry.key.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: SelectableText(
                        entry.value,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: 'Copy link',
                      icon: const Icon(Icons.copy),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: entry.value),
                        );
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content:
                                Text('Link copied for "${entry.key.name}".'),
                          ),
                        );
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    }

    final List<String> messageParts = [];
    if (bulkUrl != null) {
      final int count = bulkExperiences.length;
      messageParts.add(
          'Created 1 shareable link for $count ${count == 1 ? 'experience' : 'experiences'}');
    } else if (createdLinks.isNotEmpty) {
      messageParts.add(
          'Created ${createdLinks.length} ${createdLinks.length == 1 ? 'shareable link' : 'shareable links'}');
    }
    if (restrictedExperiences.isNotEmpty) {
      messageParts.add(
          'Skipped ${restrictedExperiences.length} shared ${restrictedExperiences.length == 1 ? 'experience' : 'experiences'} you do not own');
    }
    if (errors.isNotEmpty) {
      final String errorText = errors.first;
      final int remaining = errors.length - 1;
      final String suffix = remaining > 0
          ? ' (and $remaining more issue${remaining == 1 ? '' : 's'})'
          : '';
      messageParts.add('Some links failed: $errorText$suffix');
    }

    if (messageParts.isNotEmpty && mounted) {
      final String message = messageParts.join('. ');
      final String displayMessage =
          message.endsWith('.') ? message : '$message.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(displayMessage)));
    }
  }

  Future<void> _removeSharedExperience(SharePermission permission) async {
    await _sharingService.removeShare(permission.id);
  }

  Future<void> _handleBulkDeleteSelectedExperiences() async {
    final List<Experience> selectedExperiences = _experiences
        .where((experience) => _selectedExperienceIds.contains(experience.id))
        .toList();
    if (selectedExperiences.isEmpty) {
      return;
    }

    final List<Experience> ownedExperiences = [];
    final List<MapEntry<Experience, SharePermission>> sharedExperiences = [];

    for (final Experience experience in selectedExperiences) {
      final SharePermission? permission =
          _sharedExperiencePermissions[experience.id];
      if (permission != null) {
        sharedExperiences.add(MapEntry(experience, permission));
      } else {
        ownedExperiences.add(experience);
      }
    }

    if (ownedExperiences.isEmpty && sharedExperiences.isEmpty) {
      return;
    }

    String plural(int count, String singular, String plural) =>
        count == 1 ? singular : plural;

    final List<String> dialogLines = [];
    if (ownedExperiences.isNotEmpty) {
      dialogLines.add(
          'Delete ${ownedExperiences.length} ${plural(ownedExperiences.length, 'experience you own', 'experiences you own')}. Any linked media will also be removed.');
    }
    if (sharedExperiences.isNotEmpty) {
      dialogLines.add(
          'Remove ${sharedExperiences.length} ${plural(sharedExperiences.length, 'shared experience', 'shared experiences')}. You will lose access unless another shared category still grants it.');
    }
    dialogLines.add('This cannot be undone.');

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Remove Selected Experiences?'),
        content: Text(dialogLines.join('\n\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final List<String> errors = [];
    int deletedOwnedCount = 0;
    int removedSharedCount = 0;

    for (final Experience experience in ownedExperiences) {
      try {
        await _experienceService.deleteExperience(experience.id);
        deletedOwnedCount++;
      } catch (e) {
        errors.add('Delete "${experience.name}": $e');
      }
    }

    for (final MapEntry<Experience, SharePermission> entry
        in sharedExperiences) {
      try {
        await _removeSharedExperience(entry.value);
        removedSharedCount++;
      } catch (e) {
        errors.add('Remove "${entry.key.name}": $e');
      }
    }

    final bool anySuccess = deletedOwnedCount > 0 || removedSharedCount > 0;
    if (!anySuccess) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        if (errors.isNotEmpty) {
          final String errorText = errors.first;
          final int remaining = errors.length - 1;
          final String suffix = remaining > 0
              ? ' (and $remaining more issue${remaining == 1 ? '' : 's'})'
              : '';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('Failed to remove experiences: $errorText$suffix')),
          );
        }
      }
      return;
    }

    if (mounted) {
      setState(() {
        _selectedExperienceIds.clear();
        _isSelectingExperiences = false;
      });

      final List<String> messageParts = [];
      if (deletedOwnedCount > 0) {
        messageParts.add(
            'Deleted $deletedOwnedCount ${plural(deletedOwnedCount, 'experience you own', 'experiences you own')}');
      }
      if (removedSharedCount > 0) {
        messageParts.add(
            'Removed $removedSharedCount ${plural(removedSharedCount, 'shared experience', 'shared experiences')}');
      }
      if (errors.isNotEmpty) {
        final String errorText = errors.first;
        final int remaining = errors.length - 1;
        final String suffix = remaining > 0
            ? ' (and $remaining more issue${remaining == 1 ? '' : 's'})'
            : '';
        messageParts.add('Some removals failed: $errorText$suffix');
      }

      final String message = messageParts.join('. ');
      final String displayMessage = message.isEmpty
          ? 'Experiences updated.'
          : (message.endsWith('.') ? message : '$message.');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(displayMessage)));
    }

    if (mounted) {
      await _loadData();
    }
  }

  // --- ADDED: Methods for Color Category Editing --- START ---

  Future<void> _showAddColorCategoryModal() async {
    final result = await showModalBottomSheet<ColorCategory>(
      context: context,
      builder: (_) => const AddColorCategoryModal(),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );

    if (result != null) {
      _loadData(); // Refresh both lists
    }
  }

  Future<void> _showEditSingleColorCategoryModal(ColorCategory category) async {
    final result = await showModalBottomSheet<ColorCategory>(
      context: context,
      builder: (_) => AddColorCategoryModal(categoryToEdit: category),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );

    if (result != null) {
      _loadData();
    } else {}
  }

  Future<void> _showDeleteColorCategoryConfirmation(
      ColorCategory category) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Color Category?'),
        content: Text(
            'Are you sure you want to delete the "${category.name}" category? Experiences using this color will lose it. This cannot be undone.'),
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
      try {
        await _experienceService.deleteColorCategory(category.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${category.name}" category deleted.')),
          );
          _loadData(); // Refresh data
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting color category: $e')),
          );
        }
      }
    }
  }

  Future<void> _showRemoveSharedColorCategoryConfirmation(
      ColorCategory category, SharePermission permission) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Shared Color Category?'),
        content: Text(
            'Are you sure you want to remove the "${category.name}" color category from your collections? You will lose access to the experiences shared with it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() {
        _isLoading = true;
      });
      try {
        final int removedExperienceCount =
            await _removeSharedColorCategory(category, permission);
        if (!mounted) {
          return;
        }
        final String experienceMessage = removedExperienceCount > 0
            ? ' Removed $removedExperienceCount experience${removedExperienceCount == 1 ? '' : 's'} without other category access.'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '"${category.name}" removed from your color categories.$experienceMessage'),
          ),
        );
        await _loadData();
      } catch (e) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing shared color category: $e')),
        );
      }
    }
  }
  Future<void> _handleBulkDeleteSelectedUserCategories() async {
    final List<UserCategory> selectedCategories = _categories
        .where((category) => _selectedCategoryIds.contains(category.id))
        .toList();
    if (selectedCategories.isEmpty) {
      return;
    }

    final List<UserCategory> ownedCategories = [];
    final List<MapEntry<UserCategory, SharePermission>> sharedCategories = [];

    for (final UserCategory category in selectedCategories) {
      final SharePermission? permission =
          _sharedCategoryPermissions[category.id];
      if (permission != null) {
        sharedCategories.add(MapEntry(category, permission));
      } else {
        ownedCategories.add(category);
      }
    }

    if (ownedCategories.isEmpty && sharedCategories.isEmpty) {
      return;
    }

    String plural(int count, String single, String plural) =>
        count == 1 ? single : plural;

    final List<String> dialogLines = [];
    if (ownedCategories.isNotEmpty) {
      dialogLines.add(
          'Delete ${ownedCategories.length} ${plural(ownedCategories.length, 'category you own', 'categories you own')}. Experiences will keep their other tags but lose these categories.');
    }
    if (sharedCategories.isNotEmpty) {
      dialogLines.add(
          'Remove ${sharedCategories.length} ${plural(sharedCategories.length, 'shared category', 'shared categories')}. You will lose access to experiences available only through them.');
    }
    dialogLines.add('This cannot be undone.');

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Remove Selected Categories?'),
        content: Text(dialogLines.join('\n\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final List<String> errors = [];
    int deletedOwnedCount = 0;
    int removedSharedCount = 0;
    int removedExperiencesCount = 0;
    int deletedOrphanExperienceCount = 0;
    for (final UserCategory category in ownedCategories) {
      try {
        await _experienceService.deleteUserCategory(category.id);
        deletedOwnedCount++;
      } catch (e) {
        errors.add('Delete "${category.name}": $e');
      }
    }

    for (final MapEntry<UserCategory, SharePermission> entry
        in sharedCategories) {
      try {
        removedExperiencesCount +=
            await _removeSharedUserCategory(entry.key, entry.value);
        removedSharedCount++;
      } catch (e) {
        errors.add('Remove "${entry.key.name}": $e');
      }
    }

    final bool anySuccess = deletedOwnedCount > 0 || removedSharedCount > 0;
    if (!anySuccess) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        if (errors.isNotEmpty) {
          final String errorText = errors.first;
          final int remaining = errors.length - 1;
          final String suffix = remaining > 0
              ? ' (and $remaining more issue${remaining == 1 ? '' : 's'})'
              : '';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('Failed to remove categories: $errorText$suffix')),
          );
        }
      }
      return;
    }

    final Set<String> removedCategoryIds = {
      ...ownedCategories.map((c) => c.id),
      ...sharedCategories.map((entry) => entry.key.id),
    }..removeWhere((id) => id.isEmpty);
    deletedOrphanExperienceCount = await _deleteOrphanedExperiences(
      removedCategoryIds: removedCategoryIds,
    );

    if (mounted) {
      setState(() {
        _selectedCategoryIds.clear();
        _selectedColorCategoryIds.clear();
        _isSelectingCategories = false;
      });

      final List<String> messageParts = [];
      if (deletedOwnedCount > 0) {
        messageParts.add(
            'Deleted $deletedOwnedCount ${plural(deletedOwnedCount, 'category you own', 'categories you own')}');
      }
      if (removedSharedCount > 0) {
        messageParts.add(
            'Removed $removedSharedCount ${plural(removedSharedCount, 'shared category', 'shared categories')}');
      }
      if (removedExperiencesCount > 0) {
        messageParts.add(
            'Removed $removedExperiencesCount shared experience${removedExperiencesCount == 1 ? '' : 's'} without other category access');
      }
      if (deletedOrphanExperienceCount > 0) {
        messageParts.add(
            'Deleted $deletedOrphanExperienceCount ${plural(deletedOrphanExperienceCount, 'experience with no tags', 'experiences with no tags')}');
      }
      if (errors.isNotEmpty) {
        final String errorText = errors.first;
        final int remaining = errors.length - 1;
        final String suffix = remaining > 0
            ? ' (and $remaining more issue${remaining == 1 ? '' : 's'})'
            : '';
        messageParts.add('Some removals failed: $errorText$suffix');
      }

      final String message = messageParts.join('. ');
      final String displayMessage =
          message.endsWith('.') ? message : '$message.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(displayMessage)),
      );
    }

    if (mounted) {
      await _loadData();
    }
  }

  Future<void> _handleBulkDeleteSelectedColorCategories() async {
    final List<ColorCategory> selectedCategories = _colorCategories
        .where((category) => _selectedColorCategoryIds.contains(category.id))
        .toList();
    if (selectedCategories.isEmpty) {
      return;
    }

    final List<ColorCategory> ownedCategories = [];
    final List<MapEntry<ColorCategory, SharePermission>> sharedCategories = [];

    for (final ColorCategory category in selectedCategories) {
      final SharePermission? permission =
          _sharedCategoryPermissions[category.id];
      if (permission != null) {
        sharedCategories.add(MapEntry(category, permission));
      } else {
        ownedCategories.add(category);
      }
    }

    if (ownedCategories.isEmpty && sharedCategories.isEmpty) {
      return;
    }

    String plural(int count, String single, String plural) =>
        count == 1 ? single : plural;

    final List<String> dialogLines = [];
    if (ownedCategories.isNotEmpty) {
      dialogLines.add(
          'Delete ${ownedCategories.length} ${plural(ownedCategories.length, 'color category you own', 'color categories you own')}. Experiences will lose this color tag.');
    }
    if (sharedCategories.isNotEmpty) {
      dialogLines.add(
          'Remove ${sharedCategories.length} ${plural(sharedCategories.length, 'shared color category', 'shared color categories')}. You will lose access to experiences available only through them.');
    }
    dialogLines.add('This cannot be undone.');

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Remove Selected Color Categories?'),
        content: Text(dialogLines.join('\n\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final List<String> errors = [];
    int deletedOwnedCount = 0;
    int removedSharedCount = 0;
    int removedExperiencesCount = 0;

    int deletedOrphanExperienceCount = 0;

    for (final ColorCategory category in ownedCategories) {
      try {
        await _experienceService.deleteColorCategory(category.id);
        deletedOwnedCount++;
      } catch (e) {
        errors.add('Delete "${category.name}": $e');
      }
    }

    for (final MapEntry<ColorCategory, SharePermission> entry
        in sharedCategories) {
      try {
        removedExperiencesCount +=
            await _removeSharedColorCategory(entry.key, entry.value);
        removedSharedCount++;
      } catch (e) {
        errors.add('Remove "${entry.key.name}": $e');
      }
    }

    final bool anySuccess = deletedOwnedCount > 0 || removedSharedCount > 0;
    if (!anySuccess) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        if (errors.isNotEmpty) {
          final String errorText = errors.first;
          final int remaining = errors.length - 1;
          final String suffix = remaining > 0
              ? ' (and $remaining more issue${remaining == 1 ? '' : 's'})'
              : '';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Failed to remove color categories: $errorText$suffix')),
          );
        }
      }
      return;
    }

    final Set<String> removedCategoryIds = <String>{};
    final Set<String> removedColorCategoryIds = {
      ...ownedCategories.map((c) => c.id),
      ...sharedCategories.map((entry) => entry.key.id),
    }..removeWhere((id) => id.isEmpty);
    deletedOrphanExperienceCount = await _deleteOrphanedExperiences(
      removedCategoryIds: removedCategoryIds,
      removedColorCategoryIds: removedColorCategoryIds,
    );

    if (mounted) {
      setState(() {
        _selectedCategoryIds.clear();
        _selectedColorCategoryIds.clear();
        _isSelectingCategories = false;
      });

      final List<String> messageParts = [];
      if (deletedOwnedCount > 0) {
        messageParts.add(
            'Deleted $deletedOwnedCount ${plural(deletedOwnedCount, 'color category you own', 'color categories you own')}');
      }
      if (removedSharedCount > 0) {
        messageParts.add(
            'Removed $removedSharedCount ${plural(removedSharedCount, 'shared color category', 'shared color categories')}');
      }
      if (removedExperiencesCount > 0) {
        messageParts.add(
            'Removed $removedExperiencesCount shared experience${removedExperiencesCount == 1 ? '' : 's'} without other category access');
      }
      if (deletedOrphanExperienceCount > 0) {
        messageParts.add(
            'Deleted $deletedOrphanExperienceCount ${plural(deletedOrphanExperienceCount, 'experience with no tags', 'experiences with no tags')}');
      }
      if (errors.isNotEmpty) {
        final String errorText = errors.first;
        final int remaining = errors.length - 1;
        final String suffix = remaining > 0
            ? ' (and $remaining more issue${remaining == 1 ? '' : 's'})'
            : '';
        messageParts.add('Some removals failed: $errorText$suffix');
      }

      final String message = messageParts.join('. ');
      final String displayMessage =
          message.endsWith('.') ? message : '$message.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(displayMessage)),
      );
    }

    if (mounted) {
      await _loadData();
    }
  }

  void _updateLocalColorOrderIndices() {
    final String? currentUserId = _authService.currentUser?.uid;
    if (currentUserId == null || currentUserId.isEmpty) {
      return;
    }
    int nextOrder = 0;
    for (int i = 0; i < _colorCategories.length; i++) {
      final ColorCategory category = _colorCategories[i];
      if (category.ownerUserId != currentUserId) {
        continue;
      }
      _colorCategories[i] = category.copyWith(orderIndex: nextOrder);
      nextOrder++;
    }
  }

  Future<void> _saveColorCategoryOrder() async {
    final String? currentUserId = _authService.currentUser?.uid;
    if (currentUserId == null || currentUserId.isEmpty) {
      return;
    }
    final List<Map<String, dynamic>> updates = [];
    for (final category in _colorCategories) {
      if (category.ownerUserId != currentUserId) {
        continue;
      }
      if (category.id.isNotEmpty && category.orderIndex != null) {
        updates.add({
          'id': category.id,
          'orderIndex': category.orderIndex!,
        });
      }
    }

    if (updates.isEmpty) {
      return;
    }

    try {
      await _experienceService.updateColorCategoryOrder(updates);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving color category order: $e")),
        );
        _loadData(); // Revert on error
      }
    }
  }

  Future<void> _applyColorSortAndSave(ColorCategorySortType sortType) async {
    final List<ColorCategory> sorted =
        List<ColorCategory>.from(_colorCategories);
    if (sortType == ColorCategorySortType.alphabetical) {
      sorted
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else {
      sorted.sort((a, b) {
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

    setState(() {
      _colorCategorySortType = sortType;
      _useManualColorCategoryOrder = false;
      _manualColorCategoryOrder = [];
      _colorCategories = sorted;
      _updateLocalColorOrderIndices();
    });
    await _saveColorCategoryOrder();
    // Persist user preference so it applies next time
    unawaited(_saveColorCategorySort(sortType));
    unawaited(_persistManualColorCategoryOrder());
    unawaited(_persistUseManualColorCategoryOrder());
  }

  // --- ADDED: Helper to count experiences for a specific color category --- START ---
  int _getExperienceCountForColorCategory(ColorCategory category) {
    // Filter experiences where colorCategoryId matches the category's ID
    return _experiences
        .where((exp) => exp.colorCategoryId == category.id)
        .length;
  }
  // --- ADDED: Helper to count experiences for a specific color category --- END ---

  // --- ADDED: Widget builder for a Color Category Grid Item (for web) ---
  Widget _buildColorCategoryGridItem(ColorCategory category) {
    final count = _getExperienceCountForColorCategory(category);
    final bool isShared = _sharedCategoryIsColor[category.id] ?? false;
    final SharePermission? permission =
        isShared ? _sharedCategoryPermissions[category.id] : null;
    final bool isOwnerShared =
        _ownedSharedColorCategoryIds.contains(category.id);
    final String? ownerName = isShared
        ? (_shareOwnerNames[permission!.ownerUserId] ?? 'Someone')
        : null;
    final String? shareLabel = isShared && permission != null
        ? _buildSharedByLabel(
            permission: permission,
            ownerName: ownerName ?? 'Someone',
          )
        : (isOwnerShared ? 'Shared' : null);
    final bool isSelected = _selectedColorCategoryIds.contains(category.id);
    final bool canTogglePrivacy = _canModifyPrivacy(category.ownerUserId);
    return Card(
      key: ValueKey('color_category_grid_${category.id}'),
      clipBehavior: Clip.antiAlias,
      elevation: 2.0,
      child: Stack(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                if (_isSelectingCategories) {
                  if (isSelected) {
                    _selectedColorCategoryIds.remove(category.id);
                  } else {
                    _selectedColorCategoryIds.add(category.id);
                  }
                } else {
                  _selectedColorCategory = category;
                  _showingColorCategories = true;
                  _selectedCategory = null;
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: category.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    category.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$count ${count == 1 ? "exp" : "exps"}',
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (shareLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        shareLabel,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: _buildPrivacyIconToggle(
            isPrivate: category.isPrivate,
            isEnabled: canTogglePrivacy,
            onToggle: () => _toggleColorCategoryPrivacy(category),
            subjectLabel: 'color category',
          ),
        ),
        if (_isSelectingCategories)
          Positioned(
              top: 4,
              left: 4,
              child: Checkbox(
                value: isSelected,
                onChanged: (bool? value) {
                  setState(() {
                    if (value == true) {
                      _selectedColorCategoryIds.add(category.id);
                    } else {
                      _selectedColorCategoryIds.remove(category.id);
                    }
                  });
                },
              ),
            ),
        ],
      ),
    );
  }

  // --- ADDED: Builder for Color Category List --- START ---
  Widget _buildColorCategoriesList() {
    if (_colorCategories.isEmpty) {
      return const Center(child: Text('No color categories found.'));
    }

    final bool isDesktopWeb = kIsWeb && MediaQuery.of(context).size.width > 600;

    if (isDesktopWeb) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(
            12.0, 12.0, 12.0, 12.0 + _bottomListPadding),
        itemCount: _colorCategories.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10.0,
          crossAxisSpacing: 10.0,
          childAspectRatio: 3 / 3,
        ),
        itemBuilder: (context, index) {
          final category = _colorCategories[index];
          return _buildColorCategoryGridItem(category);
        },
      );
    } else {
      return ReorderableListView.builder(
        padding: const EdgeInsets.only(bottom: _bottomListPadding),
        buildDefaultDragHandles: false,
        itemCount: _colorCategories.length,
        itemBuilder: (context, index) {
          final category = _colorCategories[index];
          final count = _getExperienceCountForColorCategory(category);
          final bool isShared = _sharedCategoryIsColor[category.id] ?? false;
          final SharePermission? permission =
              isShared ? _sharedCategoryPermissions[category.id] : null;
          final bool canEditCategory =
              !isShared || permission!.accessLevel == ShareAccessLevel.edit;
          final bool canManageCategory = !isShared;
          final bool isOwnerShared =
              _ownedSharedColorCategoryIds.contains(category.id);
          final String? ownerName = isShared
              ? (_shareOwnerNames[permission!.ownerUserId] ?? 'Someone')
              : null;
          final String? shareLabel = isShared && permission != null
              ? _buildSharedByLabel(
                  permission: permission,
                  ownerName: ownerName ?? 'Someone',
                )
              : (isOwnerShared ? 'Shared' : null);
          final bool isSelected =
              _selectedColorCategoryIds.contains(category.id);
          final bool canTogglePrivacy =
              _canModifyPrivacy(category.ownerUserId);

          final Widget colorDot = Padding(
            padding: const EdgeInsets.only(left: 9.0),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: category.color,
                shape: BoxShape.circle,
              ),
            ),
          );

          final Widget leadingWidget = _isSelectingCategories
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: isSelected,
                      onChanged: (bool? value) {
                        setState(() {
                          if (value == true) {
                            _selectedColorCategoryIds.add(category.id);
                          } else {
                            _selectedColorCategoryIds.remove(category.id);
                          }
                        });
                      },
                    ),
                    colorDot,
                  ],
                )
              : colorDot;

          final Widget subtitleWidget = shareLabel != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$count ${count == 1 ? "experience" : "experiences"}'),
                    Text(
                      shareLabel,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                )
              : Text('$count ${count == 1 ? "experience" : "experiences"}');

          final Widget popupMenu = PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Color Category Options',
            color: Colors.white,
            onSelected: (String result) {
              switch (result) {
                case 'edit':
                  _showEditSingleColorCategoryModal(category);
                  break;
                case 'share':
                  _showShareColorCategoryBottomSheet(category);
                  break;
                case 'remove':
                  if (permission != null) {
                    _showRemoveSharedColorCategoryConfirmation(
                        category, permission);
                  }
                  break;
                case 'delete':
                  _showDeleteColorCategoryConfirmation(category);
                  break;
              }
            },
            itemBuilder: (BuildContext context) {
              final List<PopupMenuEntry<String>> items = [
                PopupMenuItem<String>(
                  value: 'edit',
                  enabled: canEditCategory,
                  child: const ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'share',
                  enabled: canManageCategory,
                  child: const ListTile(
                    leading: Icon(Icons.ios_share),
                    title: Text('Share'),
                  ),
                ),
              ];
              if (isShared && permission != null) {
                items.add(
                  const PopupMenuItem<String>(
                    value: 'remove',
                    child: ListTile(
                      leading: Icon(Icons.remove_circle_outline,
                          color: Colors.red),
                      title: Text('Remove', style: TextStyle(color: Colors.red)),
                    ),
                  ),
                );
              } else {
                items.add(
                  PopupMenuItem<String>(
                    value: 'delete',
                    enabled: canManageCategory,
                    child: const ListTile(
                      leading: Icon(Icons.delete_outline, color: Colors.red),
                      title: Text('Delete', style: TextStyle(color: Colors.red)),
                    ),
                  ),
                );
              }
              return items;
            },
          );

          final listTile = ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 7.0),
            minLeadingWidth: 24,
            leading: leadingWidget,
            title: Text(category.name),
            subtitle: subtitleWidget,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPrivacyIconToggle(
                  isPrivate: category.isPrivate,
                  isEnabled: canTogglePrivacy,
                  onToggle: () => _toggleColorCategoryPrivacy(category),
                  subjectLabel: 'color category',
                ),
                const SizedBox(width: 4),
                popupMenu,
              ],
            ),
            onTap: () {
              setState(() {
                if (_isSelectingCategories) {
                  if (isSelected) {
                    _selectedColorCategoryIds.remove(category.id);
                  } else {
                    _selectedColorCategoryIds.add(category.id);
                  }
                } else {
                  _selectedColorCategory = category;
                  _showingColorCategories = true;
                  _selectedCategory = null;
                }
              });
            },
          );
          return ReorderableDelayedDragStartListener(
            key: ValueKey(category.id),
            index: index,
            enabled: !_isSelectingCategories,
            child: listTile,
          );
        },
        onReorder: (int oldIndex, int newIndex) {
          if (newIndex > oldIndex) {
            newIndex -= 1;
          }
          if (oldIndex < 0 ||
              oldIndex >= _colorCategories.length ||
              newIndex < 0 ||
              newIndex >= _colorCategories.length) {
            return;
          }
          setState(() {
            final ColorCategory item = _colorCategories.removeAt(oldIndex);
            _colorCategories.insert(newIndex, item);
            _manualColorCategoryOrder =
                List<String>.from(_colorCategories.map((c) => c.id));
            _useManualColorCategoryOrder = true;
            _updateLocalColorOrderIndices();
          });
          unawaited(_persistManualColorCategoryOrder());
          unawaited(_persistUseManualColorCategoryOrder());
          _saveColorCategoryOrder();
        },
      );
    }
  }
  // --- ADDED: Builder for Color Category List --- END ---
  // --- ADDED: Widget to display experiences for a specific color category --- START ---
  Widget _buildColorCategoryExperiencesList(ColorCategory category) {
    final categoryExperiences = _experiences
        .where((exp) => exp.colorCategoryId == category.id)
        .toList(); // Filter experiences by colorCategoryId

    // Apply the current experience sort order (reuse existing logic if applicable)
    // Note: This creates a sorted copy
    if (_experienceSortType == ExperienceSortType.alphabetical) {
      categoryExperiences
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else if (_experienceSortType == ExperienceSortType.mostRecent) {
      categoryExperiences.sort((a, b) {
        return b.createdAt.compareTo(a.createdAt);
      });
    } // TODO: Implement distance sort for this view if needed

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row with back button and color category name
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to Color Categories',
                onPressed: () {
                  setState(() {
                    _selectedColorCategory =
                        null; // Go back to color category list
                  });
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Builder(builder: (context) {
                  final SharePermission? permission =
                      _sharedCategoryPermissions[category.id];
                  final bool isShared = permission != null;
                  final String? ownerName = isShared
                      ? (_shareOwnerNames[permission!.ownerUserId] ?? 'Someone')
                      : null;
                  final String? shareLabel = isShared
                      ? _buildSharedByLabel(
                          permission: permission!,
                          ownerName: ownerName ?? 'Someone',
                        )
                      : null;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: category.color,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.grey),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              category.name,
                              style: Theme.of(context).textTheme.titleLarge,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (shareLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 28),
                          child: Text(
                            shareLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                    ],
                  );
                }),
              ),
              Builder(builder: (context) {
                final SharePermission? permission =
                    _sharedCategoryPermissions[category.id];
                final bool isShared = permission != null;
                final bool canEditCategory = !isShared ||
                    permission!.accessLevel == ShareAccessLevel.edit;
                final bool canManageCategory = !isShared;
                return PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'Color Category Options',
                  color: Colors.white,
                  onSelected: (String result) {
                    switch (result) {
                      case 'edit':
                        _showEditSingleColorCategoryModal(category);
                        break;
                      case 'share':
                        _showShareColorCategoryBottomSheet(category);
                        break;
                      case 'delete':
                        _showDeleteColorCategoryConfirmation(category);
                        break;
                    }
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'edit',
                      enabled: canEditCategory,
                      child: const ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'share',
                      enabled: canManageCategory,
                      child: const ListTile(
                        leading: Icon(Icons.ios_share),
                        title: Text('Share'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      enabled: canManageCategory,
                      child: const ListTile(
                        leading: Icon(Icons.delete_outline, color: Colors.red),
                        title:
                            Text('Delete', style: TextStyle(color: Colors.red)),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
        const Divider(height: 1),
        // List of experiences for this color category
        Expanded(
          child: categoryExperiences.isEmpty
              ? Center(
                  child: Text(
                      'No experiences found with the "${category.name}" color category.'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: _bottomListPadding),
                  itemCount: categoryExperiences.length,
                  itemBuilder: (context, index) {
                    // Reuse the existing list item builder
                    return _buildExperienceListItem(categoryExperiences[index]);
                  },
                ),
        ),
      ],
    );
  }

  // --- ADDED: Widget to display experiences for a specific color category --- END ---
  // ADDED: Helper function to build popup menu items with visual indicators
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

  // --- ADDED: Filter Dialog & Logic (Adapted from map_screen) --- START ---
  Future<void> _showFilterDialog() async {
    // Temporary sets for dialog state
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
                    if (_categories.isEmpty)
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text('No categories available.')),
                    ...(_categories.toList()
                          ..sort((a, b) => a.name.compareTo(b.name)))
                        .map((category) {
                      final SharePermission? permission =
                          _sharedCategoryPermissions[category.id];
                      final bool isShared = permission != null;
                      final String? ownerName = isShared
                          ? (_shareOwnerNames[permission!.ownerUserId] ??
                              'Someone')
                          : null;
                      final String? shareLabel = isShared
                          ? 'Shared by ${ownerName ?? 'Someone'}'
                          : null;

                      return CheckboxListTile(
                        title: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 16,
                                  child: Center(child: Text(category.icon)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    category.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (shareLabel != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 28),
                                child: Text(
                                  shareLabel,
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[600]),
                                ),
                              ),
                          ],
                        ),
                        subtitle: null,
                        value: tempSelectedCategoryIds.contains(category.id),
                        controlAffinity:
                            ListTileControlAffinity.leading, // Checkbox on left
                        contentPadding:
                            EdgeInsets.zero, // Remove default padding
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
                    if (_colorCategories.isEmpty)
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text('No color categories available.')),
                    ...(_colorCategories.toList()
                          ..sort((a, b) => a.name.compareTo(b.name)))
                        .map((colorCategory) {
                      final SharePermission? permission =
                          _sharedCategoryPermissions[colorCategory.id];
                      final bool isShared = permission != null;
                      final String? ownerName = isShared
                          ? (_shareOwnerNames[permission!.ownerUserId] ??
                              'Someone')
                          : null;
                      final String? shareLabel = isShared
                          ? 'Shared by ${ownerName ?? 'Someone'}'
                          : null;

                      return CheckboxListTile(
                        controlAffinity:
                            ListTileControlAffinity.leading, // Checkbox on left
                        contentPadding:
                            EdgeInsets.zero, // Remove default padding
                        title: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: _parseColor(
                                        colorCategory.colorHex), // Use helper
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.grey),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    colorCategory.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (shareLabel != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 28),
                                child: Text(
                                  shareLabel,
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[600]),
                                ),
                              ),
                          ],
                        ),
                        subtitle: null,
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
                // Clear temporary selections
                tempSelectedCategoryIds.clear();
                tempSelectedColorCategoryIds.clear();
                // Apply cleared filters directly
                setState(() {
                  _selectedCategoryIds = tempSelectedCategoryIds;
                  _selectedColorCategoryIds = tempSelectedColorCategoryIds;
                });
                Navigator.of(context).pop(); // Close dialog
                _applyFiltersAndUpdateLists(); // Update lists
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
                // Apply filters from dialog state
                setState(() {
                  _selectedCategoryIds = tempSelectedCategoryIds;
                  _selectedColorCategoryIds = tempSelectedColorCategoryIds;
                });
                Navigator.of(context).pop(); // Close dialog
                _applyFiltersAndUpdateLists(); // Update lists
              },
            ),
          ],
        );
      },
    );
  }

  void _applyFiltersAndUpdateLists() {
    final filteredExperiences = _experiences.where((exp) {
      // MODIFIED: Also check otherCategories for a match
      final bool categoryMatch = _selectedCategoryIds.isEmpty ||
          (exp.categoryId != null &&
              _selectedCategoryIds.contains(exp.categoryId)) ||
          (exp.otherCategories
              .any((catId) => _selectedCategoryIds.contains(catId)));

      final bool colorMatch = _selectedColorCategoryIds.isEmpty ||
          (exp.colorCategoryId != null &&
              _selectedColorCategoryIds.contains(exp.colorCategoryId));

      return categoryMatch && colorMatch;
    }).toList();

    // Filter grouped content items
    final filteredGroupedContent = _groupedContentItems.where((group) {
      // Include the group if ANY of its associated experiences match the filters
      return group.associatedExperiences.any((exp) {
        // MODIFIED: Also check otherCategories for a match
        final bool categoryMatch = _selectedCategoryIds.isEmpty ||
            (exp.categoryId != null &&
                _selectedCategoryIds.contains(exp.categoryId)) ||
            (exp.otherCategories
                .any((catId) => _selectedCategoryIds.contains(catId)));

        final bool colorMatch = _selectedColorCategoryIds.isEmpty ||
            (exp.colorCategoryId != null &&
                _selectedColorCategoryIds.contains(exp.colorCategoryId));

        return categoryMatch && colorMatch;
      });
    }).toList();

    setState(() {
      _filteredExperiences = filteredExperiences;
      _filteredGroupedContentItems = filteredGroupedContent;
    });

    // Re-apply sorting to the newly filtered lists
    // This ensures the sort order is maintained after filtering
    _applyExperienceSort(_experienceSortType, applyToFiltered: true);
    _applyContentSort(_contentSortType, applyToFiltered: true);
  }
  // --- ADDED: Filter Dialog & Logic (Adapted from map_screen) --- END ---

  // --- ADDED: Helper method for launching URLs (restored) ---
  Future<void> _launchUrl(String urlString) async {
    // Skip invalid URLs
    if (urlString.isEmpty ||
        urlString == 'about:blank' ||
        urlString == 'https://about:blank') {
      print('Skipping invalid URL: $urlString');
      return;
    }

    // Ensure URL starts with http/https for launchUrl
    String launchableUrl = urlString;
    if (!launchableUrl.startsWith('http://') &&
        !launchableUrl.startsWith('https://')) {
      // Assume https if no scheme provided
      launchableUrl = 'https://$launchableUrl';
    }

    try {
      final Uri uri = Uri.parse(launchableUrl);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        print('Could not launch $uri');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open link: $urlString')),
          );
        }
      }
    } catch (e) {
      print('Error parsing URL: $urlString - $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid URL: $urlString')),
        );
      }
    }
  }
  // --- END ADDED ---

  // --- ADDED: Function to get search suggestions (restored) ---
  Future<List<Experience>> _getExperienceSuggestions(String pattern) async {
    if (pattern.isEmpty) {
      return [];
    }
    // Simple case-insensitive search on the name (using the full list)
    List<Experience> suggestions = _experiences
        .where((exp) => exp.name.toLowerCase().contains(pattern.toLowerCase()))
        .toList();

    // Sort suggestions: those matching _selectedCategoryIds first, then by name
    if (_selectedCategory != null) {
      suggestions.sort((a, b) {
        bool aMatchesSelected = a.categoryId == _selectedCategory!.id;
        bool bMatchesSelected = b.categoryId == _selectedCategory!.id;
        if (aMatchesSelected && !bMatchesSelected) return -1;
        if (!aMatchesSelected && bMatchesSelected) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    } else {
      suggestions
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return suggestions;
  }
  // --- END ADDED ---

  // ADDED: Widget builder for a Content Grid Item (for web)
  Widget _buildContentGridItem(GroupedContentItem group, int index) {
    final mediaItem = group.mediaItem;
    final mediaPath = mediaItem.path;
    final isInstagramUrl = mediaPath.toLowerCase().contains('instagram.com');
    final isTikTokUrl = mediaPath.toLowerCase().contains('tiktok.com') ||
        mediaPath.toLowerCase().contains('vm.tiktok.com');
    final isFacebookUrl = mediaPath.toLowerCase().contains('facebook.com') ||
        mediaPath.toLowerCase().contains('fb.com') ||
        mediaPath.toLowerCase().contains('fb.watch');
    final isYouTubeUrl = mediaPath.toLowerCase().contains('youtube.com') ||
        mediaPath.toLowerCase().contains('youtu.be') ||
        mediaPath.toLowerCase().contains('youtube.com/shorts');
    final bool isNetworkUrl =
        mediaPath.startsWith('http') || mediaPath.startsWith('https');

    Widget mediaDisplayWidget;
    if (isTikTokUrl) {
      mediaDisplayWidget = kIsWeb
          ? WebMediaPreviewCard(
            url: mediaPath,
            experienceName: group.associatedExperiences.isNotEmpty 
              ? group.associatedExperiences.first.name 
              : null,
            onOpenPressed: () => _launchUrl(mediaPath),
          )
          : TikTokPreviewWidget(
        url: mediaPath,
        launchUrlCallback: _launchUrl,
      );
    } else if (isInstagramUrl) {
      mediaDisplayWidget = kIsWeb
          ? WebMediaPreviewCard(
            url: mediaPath,
            experienceName: group.associatedExperiences.isNotEmpty 
              ? group.associatedExperiences.first.name 
              : null,
            onOpenPressed: () => _launchUrl(mediaPath),
          )
          : instagram_widget.InstagramWebView(
        url: mediaPath,
        height: 640.0, // Height for InstagramWebView
        launchUrlCallback: _launchUrl,
        onWebViewCreated: (_) {},
        onPageFinished: (_) {},
      );
      if (kIsWeb) {
        mediaDisplayWidget = Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: mediaDisplayWidget,
          ),
        );
      }
    } else if (isFacebookUrl) {
      mediaDisplayWidget = kIsWeb
          ? WebMediaPreviewCard(
            url: mediaPath,
            experienceName: group.associatedExperiences.isNotEmpty 
              ? group.associatedExperiences.first.name 
              : null,
            onOpenPressed: () => _launchUrl(mediaPath),
          )
          : FacebookPreviewWidget(
        url: mediaPath,
        height: 500.0, // Height for FacebookPreviewWidget
        launchUrlCallback: _launchUrl,
        onWebViewCreated: (_) {},
        onPageFinished: (_) {},
      );
    } else if (isYouTubeUrl) {
      mediaDisplayWidget = kIsWeb
          ? WebMediaPreviewCard(
            url: mediaPath,
            experienceName: group.associatedExperiences.isNotEmpty 
              ? group.associatedExperiences.first.name 
              : null,
            onOpenPressed: () => _launchUrl(mediaPath),
          )
          : YouTubePreviewWidget(
        url: mediaPath,
        launchUrlCallback: _launchUrl,
      );
    } else if (isNetworkUrl) {
      // Check if it's an image URL
      if (mediaPath.toLowerCase().endsWith('.jpg') ||
          mediaPath.toLowerCase().endsWith('.jpeg') ||
          mediaPath.toLowerCase().endsWith('.png') ||
          mediaPath.toLowerCase().endsWith('.gif') ||
          mediaPath.toLowerCase().endsWith('.webp')) {
        mediaDisplayWidget = Image.network(
          mediaPath,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const Center(child: CircularProgressIndicator());
          },
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[200],
              height: 200,
              child: Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: Colors.grey[600], size: 40)),
            );
          },
        );
      } else {
        // Use generic URL preview for other network URLs
        mediaDisplayWidget = GenericUrlPreviewWidget(
          url: mediaPath,
          launchUrlCallback: _launchUrl,
        );
      }
    } else {
      mediaDisplayWidget = Container(
        color: Colors.grey[300],
        height: 150,
        child: Center(
            child: Icon(Icons.description, color: Colors.grey[700], size: 40)),
      );
    }

    return Card(
      // Card is the root, making the whole area clickable via InkWell
      key: ValueKey('content_grid_${mediaItem.id}_$index'),
      clipBehavior: Clip.antiAlias,
      elevation: 2.0,
      margin: EdgeInsets
          .zero, // Remove card's own margin to better fit GridView cell
      child: InkWell(
        onTap: () {
          _showMediaDetailsDialog(group);
        },
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch, // Ensure children fill width
          children: <Widget>[
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 4.0), // Text padding
              child: Text(
                'Linked Experiences (${group.associatedExperiences.length})',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: mediaDisplayWidget, // Media preview takes remaining space
            ),
          ],
        ),
      ),
    );
  }

  // ADDED: Reusable Content List Item builder (mobile) to keep grouped and flat views consistent
  void _toggleContentPreview(String mediaPath) {
    setState(() {
      if (_expandedContentMediaPath == mediaPath) {
        _expandedContentMediaPath = null;
      } else {
        _expandedContentMediaPath = mediaPath;
      }
    });
  }

  Widget _buildContentPreviewToggleButton({
    required String mediaPath,
    required bool isExpanded,
  }) {
    return Tooltip(
      message: isExpanded ? 'Hide preview' : 'Show preview',
      child: GestureDetector(
        onTap: () => _toggleContentPreview(mediaPath),
        child: CircleAvatar(
          radius: 18,
          backgroundColor: Theme.of(context).primaryColor,
          child: Icon(
            isExpanded ? Icons.stop : Icons.play_arrow,
            size: 20,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
  Widget _buildContentListItem(GroupedContentItem group, int index) {
    final mediaItem = group.mediaItem;
    final String mediaPath = mediaItem.path;
    final associatedExperiences = group.associatedExperiences;
    final bool isExpanded = _expandedContentMediaPath == mediaPath;

    final String lowerPath = mediaPath.toLowerCase();
    final bool isInstagramUrl = lowerPath.contains('instagram.com');
    final bool isTikTokUrl =
        lowerPath.contains('tiktok.com') || lowerPath.contains('vm.tiktok.com');
    final bool isFacebookUrl = lowerPath.contains('facebook.com') ||
        lowerPath.contains('fb.com') ||
        lowerPath.contains('fb.watch');
    final bool isYouTubeUrl = lowerPath.contains('youtube.com') ||
        lowerPath.contains('youtu.be') ||
        lowerPath.contains('youtube.com/shorts');
    final bool isNetworkUrl =
        mediaPath.startsWith('http') || mediaPath.startsWith('https');
    final bool isYelpUrl =
        lowerPath.contains('yelp.com/biz') || lowerPath.contains('yelp.to/');
    final bool isMapsUrl = lowerPath.contains('google.com/maps') ||
        lowerPath.contains('maps.app.goo.gl') ||
        lowerPath.contains('goo.gl/maps') ||
        lowerPath.contains('g.co/kgs/') ||
        lowerPath.contains('share.google/');

    Widget _buildActionAvatar({
      required Widget icon,
      required String tooltip,
      required VoidCallback onTap,
      Color? backgroundColor,
    }) {
      return Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: CircleAvatar(
            radius: 18,
            backgroundColor: backgroundColor ?? Colors.white,
            child: icon,
          ),
        ),
      );
    }

    Widget? actionButton;
    if (isInstagramUrl) {
      actionButton = _buildActionAvatar(
        icon: const FaIcon(
          FontAwesomeIcons.instagram,
          color: Colors.white,
          size: 20,
        ),
        tooltip: 'Open in Instagram',
        onTap: () => _launchUrl(mediaPath),
        backgroundColor: const Color(0xFFE4405F),
      );
    } else if (isTikTokUrl) {
      actionButton = _buildActionAvatar(
        icon: const FaIcon(
          FontAwesomeIcons.tiktok,
          color: Colors.white,
          size: 20,
        ),
        tooltip: 'Open in TikTok',
        onTap: () => _launchUrl(mediaPath),
        backgroundColor: Colors.black,
      );
    } else if (isYelpUrl) {
      actionButton = _buildActionAvatar(
        icon: const FaIcon(
          FontAwesomeIcons.yelp,
          color: Colors.white,
          size: 20,
        ),
        tooltip: 'Open in Yelp',
        onTap: () => _launchUrl(mediaPath),
        backgroundColor: const Color(0xFFD32323),
      );
    } else if (isMapsUrl) {
      actionButton = _buildActionAvatar(
        icon: const FaIcon(
          FontAwesomeIcons.google,
          color: Colors.white,
          size: 20,
        ),
        tooltip: 'Open in Google Maps',
        onTap: () => _launchUrl(mediaPath),
        backgroundColor: const Color(0xFF4285F4),
      );
    } else if (isNetworkUrl) {
      actionButton = _buildActionAvatar(
        icon: const Icon(
          Icons.open_in_new,
          color: Colors.white,
          size: 20,
        ),
        tooltip: 'Open Link',
        onTap: () => _launchUrl(mediaPath),
        backgroundColor: Colors.blue.shade700,
      );
    }

    Widget? mediaWidget;
    if (isExpanded) {
      if (isTikTokUrl) {
        mediaWidget = kIsWeb
            ? WebMediaPreviewCard(
                url: mediaPath,
                experienceName: group.associatedExperiences.isNotEmpty 
                  ? group.associatedExperiences.first.name 
                  : null,
                onOpenPressed: () => _launchUrl(mediaPath),
              )
            : TikTokPreviewWidget(
                url: mediaPath,
                launchUrlCallback: _launchUrl,
              );
      } else if (isInstagramUrl) {
        mediaWidget = kIsWeb
            ? WebMediaPreviewCard(
                url: mediaPath,
                experienceName: group.associatedExperiences.isNotEmpty 
                  ? group.associatedExperiences.first.name 
                  : null,
                onOpenPressed: () => _launchUrl(mediaPath),
              )
            : instagram_widget.InstagramWebView(
                url: mediaPath,
                height: 640.0,
                launchUrlCallback: _launchUrl,
                onWebViewCreated: (_) {},
                onPageFinished: (_) {},
              );
        if (kIsWeb) {
          mediaWidget = Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: mediaWidget,
            ),
          );
        }
      } else if (isFacebookUrl) {
        mediaWidget = kIsWeb
            ? WebMediaPreviewCard(
                url: mediaPath,
                experienceName: group.associatedExperiences.isNotEmpty 
                  ? group.associatedExperiences.first.name 
                  : null,
                onOpenPressed: () => _launchUrl(mediaPath),
              )
            : FacebookPreviewWidget(
                url: mediaPath,
                height: 500.0,
                launchUrlCallback: _launchUrl,
                onWebViewCreated: (_) {},
                onPageFinished: (_) {},
              );
      } else if (isYouTubeUrl) {
        mediaWidget = kIsWeb
            ? WebMediaPreviewCard(
                url: mediaPath,
                experienceName: group.associatedExperiences.isNotEmpty 
                  ? group.associatedExperiences.first.name 
                  : null,
                onOpenPressed: () => _launchUrl(mediaPath),
              )
            : YouTubePreviewWidget(
                url: mediaPath,
                launchUrlCallback: _launchUrl,
              );
      } else if (isNetworkUrl) {
        if (lowerPath.endsWith('.jpg') ||
            lowerPath.endsWith('.jpeg') ||
            lowerPath.endsWith('.png') ||
            lowerPath.endsWith('.gif') ||
            lowerPath.endsWith('.webp')) {
          mediaWidget = Image.network(
            mediaPath,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(child: CircularProgressIndicator());
            },
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey[200],
                height: 200,
                child: Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: Colors.grey[600], size: 40)),
              );
            },
          );
        } else if (isYelpUrl) {
          mediaWidget = YelpPreviewWidget(
            yelpUrl: mediaPath,
            launchUrlCallback: _launchUrl,
          );
        } else if (isMapsUrl) {
          if (!_mapsPreviewFutures.containsKey(mediaPath) &&
              associatedExperiences.isNotEmpty) {
            final exp = associatedExperiences.first;
            _mapsPreviewFutures[mediaPath] = Future.value({
              'location': exp.location,
              'placeName': exp.name,
              'mapsUrl': mediaPath,
              'website': exp.location.website,
            });
          }
          mediaWidget = MapsPreviewWidget(
            mapsUrl: mediaPath,
            mapsPreviewFutures: _mapsPreviewFutures,
            getLocationFromMapsUrl: _getLocationFromMapsUrl,
            launchUrlCallback: _launchUrl,
            mapsService: GoogleMapsService(),
          );
        } else {
          mediaWidget = GenericUrlPreviewWidget(
            url: mediaPath,
            launchUrlCallback: _launchUrl,
          );
        }
      } else {
        mediaWidget = Container(
          color: Colors.grey[300],
          height: 150,
          child: Center(
              child: Icon(Icons.description, color: Colors.grey[700], size: 40)),
        );
      }
    }

    final bool showPrivacyToggle = group.mediaItem.id.isNotEmpty;
    final circleAvatar = CircleAvatar(
      radius: 14,
      backgroundColor: Theme.of(context).primaryColor.withOpacity(0.8),
      child: Text(
        '${index + 1}',
        style: const TextStyle(
          fontSize: 14.0,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );

    final Widget indexHeader = SizedBox(
      height: 32,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          circleAvatar,
          if (showPrivacyToggle)
            Positioned(
              right: 0,
              child: PrivacyToggleButton(
                isPrivate: group.mediaItem.isPrivate,
                showLabel: false,
                onPressed: () => _toggleGroupedContentPrivacy(group),
              ),
            ),
        ],
      ),
    );

    return Padding(
      key: ValueKey(mediaPath),
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: indexHeader,
          ),
          Container(
            margin: EdgeInsets.zero,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4.0,
                  offset: const Offset(0, -2),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4.0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  color: Theme.of(context).primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 8.0,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          mediaPath,
                          style: const TextStyle(color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12.0, vertical: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (associatedExperiences.length > 1)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6.0),
                                child: Text(
                                  'Linked Experiences (${associatedExperiences.length}):',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                ),
                              ),
                            ...associatedExperiences.map((exp) {
                              final category = _categories.firstWhereOrNull(
                                  (cat) => cat.id == exp.categoryId);
                              final categoryIcon = category?.icon ?? '?';
                              final colorCategory = _colorCategories
                                  .firstWhereOrNull(
                                      (cc) => cc.id == exp.colorCategoryId);
                              final color = colorCategory != null
                                  ? _parseColor(colorCategory.colorHex)
                                  : Theme.of(context).disabledColor;

                              return InkWell(
                                onTap: () {
                                  _openExperience(exp);
                                },
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4.0),
                                  child: Row(
                                    children: [
                                      Text(categoryIcon,
                                          style: const TextStyle(fontSize: 16)),
                                      const SizedBox(width: 6),
                                      if (colorCategory != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(right: 6.0),
                                          child: Icon(Icons.circle,
                                              color: color, size: 10),
                                        ),
                                      Expanded(
                                        child: Text(
                                          exp.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right,
                                          color: Colors.grey, size: 18),
                                    ],
                                  ),
                                ),
                              );
                            }),
                            if (associatedExperiences.isEmpty)
                              const Text('No linked experiences.',
                                  style: TextStyle(fontStyle: FontStyle.italic)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (actionButton != null) actionButton,
                          if (actionButton != null)
                            const SizedBox(width: 8.0),
                          _buildContentPreviewToggleButton(
                            mediaPath: mediaPath,
                            isExpanded: isExpanded,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isExpanded && mediaWidget != null) mediaWidget!,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleGroupedContentPrivacy(GroupedContentItem group) async {
    final String mediaId = group.mediaItem.id;
    if (mediaId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This content item cannot be updated yet.')),
      );
      return;
    }
    final bool newValue = !group.mediaItem.isPrivate;
    final previousGrouped = List<GroupedContentItem>.from(_groupedContentItems);
    final previousFiltered =
        List<GroupedContentItem>.from(_filteredGroupedContentItems);
    setState(() {
      _groupedContentItems = _groupedContentItems
          .map((item) => item.mediaItem.id == mediaId
              ? item.copyWith(
                  mediaItem: item.mediaItem.copyWith(isPrivate: newValue))
              : item)
          .toList();
      _filteredGroupedContentItems = _filteredGroupedContentItems
          .map((item) => item.mediaItem.id == mediaId
              ? item.copyWith(
                  mediaItem: item.mediaItem.copyWith(isPrivate: newValue))
              : item)
          .toList();
    });
    try {
      await _experienceService.updateSharedMediaPrivacy(mediaId, newValue);
      final Set<String> placeIds = group.associatedExperiences
          .map((exp) => exp.location.placeId)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
      if (placeIds.isNotEmpty && group.mediaItem.path.isNotEmpty) {
        unawaited(_maybeSyncPublicMediaPathForGroup(
          mediaPath: group.mediaItem.path,
          toggledMediaId: mediaId,
          newIsPrivate: newValue,
          placeIds: placeIds,
          associatedExperiences: group.associatedExperiences,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _groupedContentItems = previousGrouped;
        _filteredGroupedContentItems = previousFiltered;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to update privacy. Please try again.')),
      );
    }
  }

  Future<void> _maybeSyncPublicMediaPathForGroup({
    required String mediaPath,
    required String toggledMediaId,
    required bool newIsPrivate,
    required Set<String> placeIds,
    required List<Experience> associatedExperiences,
  }) async {
    if (mediaPath.isEmpty || toggledMediaId.isEmpty || placeIds.isEmpty) {
      return;
    }
    try {
      final items =
          await _experienceService.getSharedMediaItemsByPath(mediaPath);
      final bool otherHasPublic = items.any((media) {
        if (media.id == toggledMediaId) {
          return false;
        }
        return !media.isPrivate;
      });

      if (newIsPrivate) {
        if (otherHasPublic) return;
        for (final placeId in placeIds) {
          await _experienceService
              .removeMediaPathFromPublicExperienceByPlaceId(placeId, mediaPath);
        }
      } else {
        if (otherHasPublic) return;
        for (final placeId in placeIds) {
          Experience? template;
          try {
            template = associatedExperiences
                .firstWhere((exp) => exp.location.placeId == placeId);
          } catch (_) {
            if (associatedExperiences.isNotEmpty) {
              template = associatedExperiences.first;
            }
          }
          await _experienceService.addMediaPathToPublicExperienceByPlaceId(
            placeId,
            mediaPath,
            experienceTemplate:
                (template != null && template.location.placeId == placeId)
                    ? template
                    : null,
          );
        }
      }
    } catch (e) {
      debugPrint(
          '_maybeSyncPublicMediaPathForGroup: Failed cleanup for $mediaPath -> $e');
    }
  }

  // ADDED: Dialog to show media details (associated experiences)
  void _showMediaDetailsDialog(GroupedContentItem group) {
    showDialog(
      context: context, // This 'context' is from CollectionsScreenState
      builder: (BuildContext dialogContext) {
        // Use a different name for dialog's own context
        return AlertDialog(
          title: Text(group.mediaItem.path.contains("instagram.com")
              ? "Instagram Post Details"
              : group.mediaItem.path.contains('facebook.com') ||
                      group.mediaItem.path.contains('fb.com') ||
                      group.mediaItem.path.contains('fb.watch')
                  ? 'Facebook Post Details'
                  : group.mediaItem.path.contains('tiktok.com') ||
                          group.mediaItem.path.contains('vm.tiktok.com')
                      ? 'TikTok Post Details'
                      : group.mediaItem.path.contains('youtube.com') ||
                              group.mediaItem.path.contains('youtu.be')
                          ? 'YouTube Video Details'
                          : "Shared Media Details"),
          content: SizedBox(
            // Wrap the Column with SizedBox to constrain its width
            width: MediaQuery.of(dialogContext).size.width *
                0.2, // Example: 80% of screen width
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  "Linked Experiences (${group.associatedExperiences.length}):",
                  style: Theme.of(dialogContext)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (group.associatedExperiences.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text("No experiences linked to this media."),
                  ),
                if (group.associatedExperiences.isNotEmpty)
                  ListView.builder(
                    shrinkWrap: true,
                    itemCount: group.associatedExperiences.length,
                    itemBuilder: (context, index) {
                      final exp = group.associatedExperiences[index];
                      final category = _categories
                          .firstWhereOrNull((cat) => cat.id == exp.categoryId);
                      final categoryIcon = category?.icon ?? 'Γ¥ô';
                      final colorCategory = _colorCategories.firstWhereOrNull(
                          (cc) => cc.id == exp.colorCategoryId);
                      final color = colorCategory != null
                          ? _parseColor(colorCategory.colorHex)
                          : Theme.of(dialogContext).disabledColor;

                      return ListTile(
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(categoryIcon,
                                style: const TextStyle(fontSize: 20)),
                            if (colorCategory != null) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.circle, color: color, size: 12),
                            ]
                          ],
                        ),
                        title: Text(exp.name,
                            style: Theme.of(dialogContext).textTheme.bodyLarge),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(dialogContext)
                              .pop(); // Close dialog first
                          final resolvedCategory = category ??
                              UserCategory(
                                id: exp.categoryId ?? 'uncategorized',
                                name: category?.name ?? 'Uncategorized',
                                icon: categoryIcon,
                                ownerUserId: category?.ownerUserId ??
                                    _authService.currentUser?.uid ??
                                    'system_default',
                                orderIndex: category?.orderIndex ?? 9999,
                              );
                          Navigator.push<bool>(
                            this.context, // Use CollectionsScreenState's context for navigation
                            MaterialPageRoute(
                              builder: (ctx) => ExperiencePageScreen(
                                // Use 'ctx' for clarity
                                experience: exp,
                                category: resolvedCategory,
                                userColorCategories: _colorCategories,
                              ),
                            ),
                          ).then((result) {
                            if (result == true && mounted) {
                              _loadData();
                            }
                          });
                        },
                      );
                    },
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void startContentPreload() {
    _contentPreloadRequested = true;
    if (!_contentLoaded && !_isContentLoading && _experiences.isNotEmpty) {
      unawaited(_loadGroupedContent());
    }
  }

  Future<void> _loadGroupedContent() async {
    if (_isContentLoading || _contentLoaded) return;
    // Wait until experiences are available if they are still loading
    if (_experiences.isEmpty && _isExperiencesLoading) {
      return;
    }
    _isContentLoading = true;
    try {
      final experiences = _experiences;
      final groupSw = Stopwatch()..start();
      List<GroupedContentItem> groupedContent = [];
      if (experiences.isNotEmpty) {
        final Set<String> allMediaItemIds = {};
        for (final exp in experiences) {
          allMediaItemIds.addAll(exp.sharedMediaItemIds);
        }

        if (allMediaItemIds.isNotEmpty) {
          final mediaFetchSw = Stopwatch()..start();
          final List<SharedMediaItem> allMediaItems = await _experienceService
              .getSharedMediaItems(allMediaItemIds.toList());
          if (_perfLogs) {
            mediaFetchSw.stop();
            print(
                '[Perf][Collections] sharedMediaItems fetch (${allMediaItemIds.length} ids) took ${mediaFetchSw.elapsedMilliseconds}ms');
          }

          final Map<String, SharedMediaItem> mediaItemMap = {
            for (var item in allMediaItems) item.id: item
          };

          final List<Map<String, dynamic>> pathExperiencePairs = [];
          for (final exp in experiences) {
            for (final mediaId in exp.sharedMediaItemIds) {
              final mediaItem = mediaItemMap[mediaId];
              if (mediaItem != null) {
                pathExperiencePairs.add({
                  'path': mediaItem.path,
                  'mediaItem': mediaItem,
                  'experience': exp,
                });
              }
            }
          }

          final groupedByPath =
              groupBy(pathExperiencePairs, (pair) => pair['path'] as String);

          groupedByPath.forEach((path, pairs) {
            if (pairs.isNotEmpty) {
              final firstPair = pairs.first;
              final mediaItem = firstPair['mediaItem'] as SharedMediaItem;
              final associatedExperiences = pairs
                  .map((pair) => pair['experience'] as Experience)
                  .toList();
              associatedExperiences.sort((a, b) =>
                  a.name.toLowerCase().compareTo(b.name.toLowerCase()));

              groupedContent.add(GroupedContentItem(
                mediaItem: mediaItem,
                associatedExperiences: associatedExperiences,
              ));
            }
          });
        }
      }
      if (_perfLogs) {
        groupSw.stop();
        print(
            '[Perf][Collections] Grouping content took ${groupSw.elapsedMilliseconds}ms (items=${groupedContent.length})');
      }

      if (mounted) {
        setState(() {
          _groupedContentItems = groupedContent;
          _filteredGroupedContentItems = List.from(_groupedContentItems);
          _contentLoaded = true;
          _isContentLoading = false;
        });
      }

      await _applyContentSort(_contentSortType);
      // Ensure Content tab reflects filters on initial load as well
      if (_hasActiveFilters) {
        _applyFiltersAndUpdateLists();
      }
    } catch (e) {
      _isContentLoading = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading content: $e')),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _getLocationFromMapsUrl(String mapsUrl) async {
    final String originalUrlKey = mapsUrl.trim();

    if (_businessDataCache.containsKey(originalUrlKey)) {
      return _businessDataCache[originalUrlKey];
    }

    String resolvedUrl = mapsUrl;
    if (!resolvedUrl.contains('google.com/maps')) {
      return null;
    }

    Map<String, dynamic>? placeData;
    String? placeIdToLookup;

    try {
      String searchQuery = resolvedUrl;
      try {
        final Uri uri = Uri.parse(resolvedUrl);
        final placeSegmentIndex = uri.pathSegments.indexOf('place');
        if (placeSegmentIndex != -1 &&
            placeSegmentIndex < uri.pathSegments.length - 1) {
          String placePathInfo = uri.pathSegments[placeSegmentIndex + 1];
          placePathInfo =
              Uri.decodeComponent(placePathInfo).replaceAll('+', ' ');
          placePathInfo = placePathInfo.split('@')[0].trim();

          if (placePathInfo.isNotEmpty) {
            searchQuery = placePathInfo;
          }
        }
      } catch (e) {
        // Continue with original URL as search query
      }

      final results = await GoogleMapsService().searchPlaces(searchQuery);
      if (results.isNotEmpty) {
        placeData = results.first;
        placeIdToLookup = placeData['place_id'] as String?;
      }
    } catch (e) {
      return null;
    }

    if (placeData != null && placeIdToLookup != null) {
      final locationData = {
        'name': placeData['name'] ?? '',
        'address': placeData['formatted_address'] ?? '',
        'placeId': placeIdToLookup,
        'latitude': placeData['geometry']?['location']?['lat'] ?? 0.0,
        'longitude': placeData['geometry']?['location']?['lng'] ?? 0.0,
        'city': '',
        'state': '',
        'country': '',
        'zipCode': '',
        'photoUrl': '',
        'photoResourceName': '',
        'website': '',
        'rating': placeData['rating']?.toDouble() ?? 0.0,
        'userRatingCount': placeData['user_ratings_total'] ?? 0,
      };
      _businessDataCache[originalUrlKey] = locationData;
      return locationData;
    }

    return null;
  }

  /// Refresh shared experiences from shared categories to pick up newly added experiences
  Future<void> _refreshSharedExperiencesFromCategories() async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) return;

    try {
      // Get shared category permissions
      final List<SharePermission> categoryPermissions =
          await _sharingService.getSharedItemsForUser(userId);

      final categoryPermsOnly = categoryPermissions
          .where((p) => p.itemType == ShareableItemType.category)
          .toList();

      if (categoryPermsOnly.isEmpty) return;

      // Use optimized batch resolution
      final List<_SharedCategoryData> sharedCategoryData =
          await _resolveSharedCategories(categoryPermsOnly);

      // OPTIMIZED: Broad fetch all shared experiences
      print(
          '[Collections] (Refresh) Broad-fetching all shared experiences for user $userId...');
      final broadSw = Stopwatch()..start();
      final List<Experience> allSharedExperiences = [];
      DocumentSnapshot<Object?>? lastDoc;
      int pageCount = 0;

      while (true) {
        final (pageExps, last) =
            await _experienceService.getExperiencesSharedWith(
          userId,
          limit: 500,
          startAfter: lastDoc,
        );
        allSharedExperiences.addAll(pageExps);
        pageCount++;
        if (pageExps.length < 500 || last == null) break;
        lastDoc = last;
      }
      broadSw.stop();
      print(
          '[Collections] (Refresh) Broad fetch: ${allSharedExperiences.length} experiences in ${broadSw.elapsedMilliseconds}ms ($pageCount pages)');

      // Update shared experiences and permissions
      final Map<String, SharePermission> newExperiencePermissions = {};
      final List<Experience> newSharedExperiences = [];
      final Set<String> seenIds = {};

      // Process each category and filter from broad fetch
      for (final categoryData in sharedCategoryData) {
        final categoryId = categoryData.categoryId;
        final isColorCategory = categoryData.isColorCategory;

        final categoryExperiences = allSharedExperiences.where((exp) {
          if (isColorCategory) {
            return exp.colorCategoryId == categoryId;
          } else {
            return exp.categoryId == categoryId ||
                exp.otherCategories.contains(categoryId);
          }
        }).toList();

        for (final experience in categoryExperiences) {
          if (!seenIds.add(experience.id)) continue;

          final syntheticPermission = SharePermission(
            id: 'category_${categoryData.permission.id}_${experience.id}',
            itemId: experience.id,
            itemType: ShareableItemType.experience,
            ownerUserId: categoryData.permission.ownerUserId,
            sharedWithUserId: userId,
            accessLevel: categoryData.permission.accessLevel,
            createdAt: categoryData.permission.createdAt,
            updatedAt: categoryData.permission.updatedAt,
          );

          newExperiencePermissions[experience.id] = syntheticPermission;
          newSharedExperiences.add(experience);
        }
      }

      // Update state if mounted
      if (mounted) {
        setState(() {
          _sharedExperiencePermissions.addAll(newExperiencePermissions);

          final Map<String, Experience> experienceMap = {
            for (final exp in _sharedExperiences) exp.id: exp,
          };
          for (final exp in newSharedExperiences) {
            experienceMap[exp.id] = exp;
          }
          _sharedExperiences = experienceMap.values.toList();
        });
      }
    } catch (e) {
      debugPrint(
          '_refreshSharedExperiencesFromCategories: Error refreshing shared experiences: $e');
    }
  }
  /// Fetch a paginated set of experiences based on current sort type
  Future<void> _loadExperiencesPage({bool isInitialLoad = false}) async {
    if (_isLoadingMoreExperiences && !isInitialLoad) return;
    if (!_hasMoreExperiences && !isInitialLoad) return;

    final userId = _authService.currentUser?.uid;
    if (userId == null) return;

    setState(() {
      if (isInitialLoad) {
        _isLoading = true;
      } else {
        _isLoadingMoreExperiences = true;
      }
    });

    try {
      final Set<String> currentCategoryIds = _currentCategoryIdSet();
      final Set<String> currentColorCategoryIds = _currentColorCategoryIdSet();

      // Determine sort parameters based on current sort type
      String orderByField;
      bool descending;
      bool requiresClientSort = false;

      switch (_experienceSortType) {
        case ExperienceSortType.mostRecent:
          orderByField = 'updatedAt';
          descending = true;
          break;
        case ExperienceSortType.alphabetical:
          orderByField = 'name';
          descending = false;
          break;
        case ExperienceSortType.city:
          orderByField = 'location.city';
          descending = false;
          break;
        case ExperienceSortType.distanceFromMe:
          // Distance requires client-side sorting; load more docs
          orderByField = 'updatedAt';
          descending = true;
          requiresClientSort = true;
          break;
      }

      final int pageLimit = requiresClientSort ? 500 : _experiencesPageSize;

      List<Experience> ownedExperiences = [];
      
      // Only fetch owned experiences on initial load
      if (isInitialLoad) {
        ownedExperiences = await _experienceService.getExperiencesByUser(
          userId,
          limit: 500, // Load all owned (usually smaller set)
        );
      }

      // Fetch paginated shared experiences with server-side sorting
      final (sharedExperiences, lastDoc) =
          await _experienceService.getExperiencesSharedWith(
        userId,
        limit: pageLimit,
        startAfter: isInitialLoad ? null : _lastExperienceDoc,
        orderByField: orderByField,
        descending: descending,
      );

      print(
          '[Collections] Loaded ${sharedExperiences.length} shared experiences (page ${isInitialLoad ? 'initial' : 'more'})');

      if (mounted) {
        setState(() {
          if (isInitialLoad) {
            // First load: combine owned + first page of shared
            final combinedExperiences = _combineExperiencesWithShared(ownedExperiences);
            
            // Add shared experiences to combined list
            final Map<String, Experience> experienceMap = {
              for (final exp in combinedExperiences) exp.id: exp
            };
            for (final exp in sharedExperiences) {
              experienceMap[exp.id] = exp;
            }
            final allExperiences = experienceMap.values.toList();

            final filteredExperiences = _filterExperiencesWithAssignments(
              allExperiences,
              currentCategoryIds,
              currentColorCategoryIds,
            );
            
            _experiences = filteredExperiences;
            _filteredExperiences = List.from(_experiences);
            _lastExperienceDoc = lastDoc;
            _hasMoreExperiences = sharedExperiences.length >= pageLimit;
            _isLoading = false;
          } else {
            // Append next page of shared experiences
            final Map<String, Experience> existing = {
              for (final exp in _experiences) exp.id: exp
            };
            for (final exp in sharedExperiences) {
              existing[exp.id] = exp;
            }
            
            final allExperiences = existing.values.toList();
            final filteredExperiences = _filterExperiencesWithAssignments(
              allExperiences,
              currentCategoryIds,
              currentColorCategoryIds,
            );
            
            _experiences = filteredExperiences;
            _filteredExperiences = List.from(_experiences);
            _lastExperienceDoc = lastDoc;
            _hasMoreExperiences = sharedExperiences.length >= pageLimit;
            _isLoadingMoreExperiences = false;
          }
        });

        // Sort the combined list (owned + shared) by the selected sort type
        // This ensures owned and shared experiences are interleaved correctly
        if (!requiresClientSort) {
          // For server-sortable types, apply the same sort client-side to merge owned+shared correctly
          _experiences.sort((a, b) {
            if (_experienceSortType == ExperienceSortType.alphabetical) {
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            } else if (_experienceSortType == ExperienceSortType.city) {
              final ca = (a.location.city ?? '').trim().toLowerCase();
              final cb = (b.location.city ?? '').trim().toLowerCase();
              if (ca.isEmpty && cb.isEmpty) return 0;
              if (ca.isEmpty) return 1;
              if (cb.isEmpty) return -1;
              final cmp = ca.compareTo(cb);
              if (cmp != 0) return cmp;
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            } else {
              // Most Recent (default)
              return b.updatedAt.compareTo(a.updatedAt);
            }
          });
          _filteredExperiences = List.from(_experiences);
        } else if (requiresClientSort && isInitialLoad) {
          // For distance sort, show data first, then calculate distances in background
          _filteredExperiences = List.from(_experiences);
          print('[Collections] Distance sort: Showing ${_experiences.length} experiences, calculating distances in background...');
          // Calculate distances asynchronously without blocking
          Future.microtask(() async {
            if (mounted && _experienceSortType == ExperienceSortType.distanceFromMe) {
              print('[Collections] Starting distance calculation for ${_experiences.length} experiences...');
              try {
                // Sort the main list
                await _sortExperiencesByDistance(_experiences);
                if (mounted) {
                  setState(() {
                    // Create new list instances to force ListView rebuild
                    _experiences = List.from(_experiences);
                    _filteredExperiences = List.from(_experiences);
                    print('[Collections] Distance sort complete: ${_experiences.length} experiences sorted');
                  });
                  print('[Collections] UI updated with distance-sorted experiences');
                }
              } catch (e) {
                print('[Collections] Distance sort failed: $e');
              }
            }
          });
        }

        // Apply filters if active
        if (_hasActiveFilters) {
          _applyFiltersAndUpdateLists();
        }
        
        print(
            '[Collections] Pagination: ${_experiences.length} total, hasMore=$_hasMoreExperiences');
      }
    } catch (e) {
      print('[Collections] Error loading experiences page: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMoreExperiences = false;
          _hasMoreExperiences = false;
        });
      }
    }
  }

  Future<void> _loadExperiences(String userId) async {
    _isExperiencesLoading = true;
    bool experiencesLoaded = false;
    try {
      // Use new paginated fetch for initial load
      await _loadExperiencesPage(isInitialLoad: true);
      experiencesLoaded = true;
    } finally {
      _isExperiencesLoading = false;
    }

    if (experiencesLoaded &&
        _contentPreloadRequested &&
        !_contentLoaded &&
        !_isContentLoading) {
      // Trigger Content tab resolution even when there are zero experiences
      await _loadGroupedContent();
    }
  }

  // --- Share Bottom Sheets for Category and Color Category ---
  void _showShareCategoryBottomSheet(UserCategory _category) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return _ShareBottomSheetContent(
            title: 'Share Category', userCategory: _category);
      },
    );
  }

  void _showShareColorCategoryBottomSheet(ColorCategory _colorCategory) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return _ShareBottomSheetContent(
            title: 'Share Color Category', colorCategory: _colorCategory);
      },
    );
  }

  void _showShareSelectedCategoriesBottomSheet({
    List<UserCategory>? userCategories,
    List<ColorCategory>? colorCategories,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return _BulkShareBottomSheetContent(
          userCategories: userCategories,
          colorCategories: colorCategories,
        );
      },
    );
  }
}

// --- Share Bottom Sheet Content (UI-only, no functionality) ---
class _ShareBottomSheetContent extends StatefulWidget {
  final String title; // e.g., 'Share Category' or 'Share Color Category'
  // When provided, one of these will be non-null to identify what we're sharing
  final UserCategory? userCategory;
  final ColorCategory? colorCategory;

  const _ShareBottomSheetContent(
      {required this.title, this.userCategory, this.colorCategory});

  @override
  State<_ShareBottomSheetContent> createState() =>
      _ShareBottomSheetContentState();
}

class _ShareBottomSheetContentState extends State<_ShareBottomSheetContent> {
  String _shareMode = 'view_access'; // 'view_access' | 'edit_access'
  bool _giveEditAccess = false;
  final SharingService _sharingService = SharingService();
  final ExperienceService _experienceService = ExperienceService();
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  bool _creating = false;
  bool _isLoadingShareDetails = false;
  _ShareAccessDetails? _shareAccessDetails;
  String? _shareDetailsError;
  String? _shareDetailsInfo;

  @override
  void initState() {
    super.initState();
    _loadShareAccessDetails();
  }

  Future<List<Experience>> _getExperiencesForCurrentCategory(
      String ownerUserId, String categoryId) async {
    List<Experience> allOwned = [];
    try {
      // Use owner-based fetch to satisfy Firestore security rules
      allOwned = await _experienceService.getExperiencesByUser(
        ownerUserId,
        limit: 500,
      );
    } catch (e) {
      _log('Failed to load owner experiences for cascading: ' + e.toString());
      return [];
    }

    if (widget.userCategory != null) {
      return allOwned.where((exp) {
        final bool inPrimary = (exp.categoryId == categoryId);
        final bool inOther = exp.otherCategories.contains(categoryId);
        return inPrimary || inOther;
      }).toList();
    } else if (widget.colorCategory != null) {
      return allOwned
          .where((exp) => exp.colorCategoryId == categoryId)
          .toList();
    }
    return [];
  }

  void _log(String message) {
    debugPrint('[ShareSheet] ' + widget.title + ': ' + message);
  }

  String? _resolveOwnerUserId() {
    return widget.userCategory?.ownerUserId ??
        widget.colorCategory?.ownerUserId;
  }

  Future<String> _fetchOwnerName(String ownerId) async {
    final profile = await _experienceService.getUserProfileById(ownerId);
    final ownerName = profile?.displayName ?? profile?.username ?? 'Someone';
    _log('Resolved owner ' + ownerId + ' to name "' + ownerName + '"');
    return ownerName;
  }

  Future<_ShareAccessDetails> _composeShareDetails({
    required String ownerId,
    required String ownerName,
    required List<SharePermission> permissions,
    required String? currentUserId,
  }) async {
    final Map<String, SharePermission> latestByUser = {};
    for (final permission in permissions) {
      final existing = latestByUser[permission.sharedWithUserId];
      if (existing == null ||
          permission.updatedAt.compareTo(existing.updatedAt) > 0) {
        latestByUser[permission.sharedWithUserId] = permission;
      }
    }

    final List<_ShareParticipantInfo> participants = [];
    for (final entry in latestByUser.entries) {
      final profile = await _experienceService.getUserProfileById(entry.key);
      final displayName =
          profile?.displayName ?? profile?.username ?? 'Someone';
      _log('Participant ' +
          entry.key +
          ' resolved to "' +
          displayName +
          '" with access ' +
          entry.value.accessLevel.toString());
      participants.add(_ShareParticipantInfo(
        userId: entry.key,
        displayName: displayName,
        accessLevel: entry.value.accessLevel,
        isCurrentUser: entry.key == currentUserId,
      ));
    }

    participants.sort((a, b) => a.displayName.compareTo(b.displayName));
    final filteredParticipants =
        participants.where((p) => p.userId != ownerId).toList();

    return _ShareAccessDetails(
      ownerUserId: ownerId,
      ownerDisplayName: ownerName,
      ownerIsCurrentUser: ownerId == currentUserId,
      participants: filteredParticipants,
    );
  }

  Future<void> _loadShareAccessDetails() async {
    final String categoryId =
        widget.userCategory?.id ?? widget.colorCategory?.id ?? '';
    final String? initialOwnerId = _resolveOwnerUserId();
    final String? currentUserId = _firebaseAuth.currentUser?.uid;
    _log('Loading share access for categoryId=' +
        categoryId +
        ' ownerId=' +
        (initialOwnerId ?? 'null') +
        ' currentUserId=' +
        (currentUserId ?? 'null'));

    if (categoryId.isEmpty) {
      _log('No categoryId available, skipping share access load');
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingShareDetails = true;
        _shareDetailsError = null;
        _shareDetailsInfo = null;
        _shareAccessDetails = null;
      });
    }

    try {
      List<SharePermission> permissions =
          await _sharingService.getPermissionsForItem(categoryId);
      _log('Primary permission query returned ' +
          permissions.length.toString() +
          ' record(s)');

      if (permissions.isEmpty &&
          initialOwnerId != null &&
          initialOwnerId == currentUserId) {
        final ownedPermissions =
            await _sharingService.getOwnedSharePermissions(initialOwnerId);
        permissions = ownedPermissions
            .where((perm) =>
                perm.itemId == categoryId &&
                perm.itemType == ShareableItemType.category)
            .toList();
        _log('Owner fallback query returned ' +
            permissions.length.toString() +
            ' record(s) for item ' +
            categoryId);
      }

      if (permissions.isEmpty) {
        final ownerId = initialOwnerId ?? currentUserId ?? '';
        final ownerName =
            ownerId.isNotEmpty ? await _fetchOwnerName(ownerId) : 'Someone';
        if (!mounted) return;
        setState(() {
          _isLoadingShareDetails = false;
          _shareAccessDetails = _ShareAccessDetails(
            ownerUserId: ownerId,
            ownerDisplayName: ownerName,
            ownerIsCurrentUser: ownerId == currentUserId,
            participants: const [],
          );
          _shareDetailsInfo = 'No other Plendy users have direct access yet.';
          _shareDetailsError = null;
        });
        return;
      }

      final ownerId = initialOwnerId ?? permissions.first.ownerUserId;
      final ownerName = await _fetchOwnerName(ownerId);
      final details = await _composeShareDetails(
        ownerId: ownerId,
        ownerName: ownerName,
        permissions: permissions,
        currentUserId: currentUserId,
      );
      if (!mounted) return;
      setState(() {
        _isLoadingShareDetails = false;
        _shareAccessDetails = details;
        _shareDetailsInfo = details.participants.isEmpty
            ? 'No other Plendy users have direct access yet.'
            : null;
        _shareDetailsError = null;
      });
    } catch (e, stackTrace) {
      _log('Failed to load share access: ' + e.toString());
      debugPrint(stackTrace.toString());

      if (initialOwnerId != null && initialOwnerId == currentUserId) {
        final fallbackOwnerId = initialOwnerId!;
        _log('Attempting owner fallback after permission failure...');
        try {
          final ownedPermissions =
              await _sharingService.getOwnedSharePermissions(fallbackOwnerId);
          final ownerPermissions = ownedPermissions
              .where((perm) =>
                  perm.itemId == categoryId &&
                  perm.itemType == ShareableItemType.category)
              .toList();
          _log('Owner fallback query returned ' +
              ownerPermissions.length.toString() +
              ' record(s)');
          if (ownerPermissions.isNotEmpty) {
            final ownerName = await _fetchOwnerName(fallbackOwnerId);
            final details = await _composeShareDetails(
              ownerId: fallbackOwnerId,
              ownerName: ownerName,
              permissions: ownerPermissions,
              currentUserId: currentUserId,
            );
            if (!mounted) return;
            setState(() {
              _isLoadingShareDetails = false;
              _shareAccessDetails = details;
              _shareDetailsInfo = details.participants.isEmpty
                  ? 'No other Plendy users have direct access yet.'
                  : null;
              _shareDetailsError = null;
            });
            return;
          }
        } catch (fallbackError, fallbackStackTrace) {
          _log('Owner fallback failed: ' + fallbackError.toString());
          debugPrint(fallbackStackTrace.toString());
        }
      }

      final ownerId = initialOwnerId ?? currentUserId ?? '';
      String ownerName = 'Someone';
      if (ownerId.isNotEmpty) {
        try {
          ownerName = await _fetchOwnerName(ownerId);
        } catch (err) {
          _log('Fallback owner name lookup failed: ' + err.toString());
        }
      }
      if (!mounted) return;
      setState(() {
        _isLoadingShareDetails = false;
        _shareAccessDetails = ownerId.isEmpty
            ? null
            : _ShareAccessDetails(
                ownerUserId: ownerId,
                ownerDisplayName: ownerName,
                ownerIsCurrentUser: ownerId == currentUserId,
                participants: const [],
              );
        _shareDetailsInfo = ownerId.isNotEmpty
            ? 'No other Plendy users have direct access yet.'
            : null;
        _shareDetailsError = 'Unable to load shared access';
      });
    }
  }

  Widget _buildOwnerRow(_ShareAccessDetails details) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
      leading: const Icon(Icons.verified_user, color: Colors.black54),
      title: Text(details.ownerDisplayName),
      subtitle: Text(details.ownerIsCurrentUser ? 'Owner (you)' : 'Owner'),
    );
  }

  Widget _buildParticipantRow(_ShareParticipantInfo participant) {
    final bool canEdit = participant.accessLevel == ShareAccessLevel.edit;
    final bool ownerIsCurrentUser =
        _shareAccessDetails?.ownerIsCurrentUser == true;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
      leading: const Icon(Icons.person_outline, color: Colors.black54),
      title: Text(participant.displayName),
      subtitle: Text(canEdit ? 'Edit access' : 'View access'),
      trailing: participant.isCurrentUser
          ? const Text('you', style: TextStyle(color: Colors.grey))
          : (ownerIsCurrentUser
              ? const Icon(Icons.more_horiz, color: Colors.black45)
              : null),
      onTap: ownerIsCurrentUser && !participant.isCurrentUser
          ? () => _showManageAccessDialog(participant)
          : null,
    );
  }

  Future<void> _showManageAccessDialog(
      _ShareParticipantInfo participant) async {
    final String categoryId =
        widget.userCategory?.id ?? widget.colorCategory?.id ?? '';
    if (categoryId.isEmpty) return;

    final String? ownerUserId = _shareAccessDetails?.ownerUserId ??
        _resolveOwnerUserId() ??
        _firebaseAuth.currentUser?.uid;
    if (ownerUserId == null || ownerUserId.isEmpty) return;

    final String? choice = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Text('Manage access for ' + participant.displayName),
          content:
              const Text('Change what this person can do in this category.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('remove'),
              child: const Text('Remove access'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('view'),
              child: const Text('View'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop('edit'),
              child: const Text('Edit'),
            ),
          ],
        );
      },
    );

    if (choice == null) return;

    setState(() {
      _isLoadingShareDetails = true;
    });

    try {
      final String permissionDocId =
          ownerUserId + '_category_' + categoryId + '_' + participant.userId;

      if (choice == 'remove') {
        await _sharingService.removeShare(permissionDocId);
      } else {
        final ShareAccessLevel newLevel =
            choice == 'edit' ? ShareAccessLevel.edit : ShareAccessLevel.view;

        try {
          await _sharingService.updatePermissionAccessLevel(
            permissionId: permissionDocId,
            newAccessLevel: newLevel,
          );
        } catch (e) {
          // If update fails because doc doesn't exist, create it
          await _sharingService.shareItem(
            itemId: categoryId,
            itemType: ShareableItemType.category,
            ownerUserId: ownerUserId,
            sharedWithUserId: participant.userId,
            accessLevel: newLevel,
          );
        }

        // If downgrading category access from edit -> view, cascade to experiences
        final bool wasEditForThisCategory =
            participant.accessLevel == ShareAccessLevel.edit;
        if (newLevel == ShareAccessLevel.view && wasEditForThisCategory) {
          // Fetch experiences under this category (user or color) using owner-based fetch
          final List<Experience> experiences =
              await _getExperiencesForCurrentCategory(ownerUserId, categoryId);

          // Find other categories (user or color) that still grant EDIT to this participant
          final ownedPerms =
              await _sharingService.getOwnedSharePermissions(ownerUserId);
          final Set<String> otherEditCategoryIds = ownedPerms
              .where((p) =>
                  p.itemType == ShareableItemType.category &&
                  p.sharedWithUserId == participant.userId &&
                  p.accessLevel == ShareAccessLevel.edit &&
                  p.itemId != categoryId)
              .map((p) => p.itemId)
              .toSet();

          // For each experience, downgrade to view unless another shared category still gives edit
          final List<Future<void>> experienceUpdates = [];
          for (final exp in experiences) {
            bool keepEdit = false;
            if (exp.categoryId != null &&
                otherEditCategoryIds.contains(exp.categoryId)) {
              keepEdit = true;
            }
            if (!keepEdit && exp.otherCategories.isNotEmpty) {
              for (final otherCatId in exp.otherCategories) {
                if (otherEditCategoryIds.contains(otherCatId)) {
                  keepEdit = true;
                  break;
                }
              }
            }
            if (!keepEdit && exp.colorCategoryId != null) {
              if (otherEditCategoryIds.contains(exp.colorCategoryId)) {
                keepEdit = true;
              }
            }

            if (!keepEdit) {
              final String expPermissionId = ownerUserId +
                  '_experience_' +
                  exp.id +
                  '_' +
                  participant.userId;
              experienceUpdates.add(_sharingService
                  .updatePermissionAccessLevel(
                permissionId: expPermissionId,
                newAccessLevel: ShareAccessLevel.view,
              )
                  .catchError((_) async {
                // If missing, no explicit edit permission exists; nothing to downgrade
              }));
            }
          }
          if (experienceUpdates.isNotEmpty) {
            await Future.wait(experienceUpdates);
          }
        } else if (newLevel == ShareAccessLevel.edit &&
            participant.accessLevel != ShareAccessLevel.edit) {
          // Upgrading from view -> edit: grant EDIT to all experiences in this category
          final List<Experience> experiences =
              await _getExperiencesForCurrentCategory(ownerUserId, categoryId);

          final List<Future<void>> experienceEdits = [];
          for (final exp in experiences) {
            final String expPermissionId = ownerUserId +
                '_experience_' +
                exp.id +
                '_' +
                participant.userId;

            // Try to update to edit; if doc is missing, create it
            experienceEdits.add(_sharingService
                .updatePermissionAccessLevel(
              permissionId: expPermissionId,
              newAccessLevel: ShareAccessLevel.edit,
            )
                .catchError((_) async {
              await _sharingService.shareItem(
                itemId: exp.id,
                itemType: ShareableItemType.experience,
                ownerUserId: ownerUserId,
                sharedWithUserId: participant.userId,
                accessLevel: ShareAccessLevel.edit,
              );
            }));
          }
          if (experienceEdits.isNotEmpty) {
            await Future.wait(experienceEdits);
          }
        }
      }

      await _loadShareAccessDetails();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(choice == 'remove' ? 'Access removed' : 'Access updated'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingShareDetails = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update access: ' + e.toString())),
      );
    }
  }
  void _showShareUrlOptions(BuildContext context, String url) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Share link',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(url, style: const TextStyle(fontSize: 14)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () async {
                        await Share.share(url);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      },
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Share'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(ctx).primaryColor,
                          foregroundColor: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: url));
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('Link copied')));
                        }
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy'),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_isLoadingShareDetails)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  children: const [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Loading shared access...'),
                  ],
                ),
              )
            else if (_shareAccessDetails != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Shared access',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildOwnerRow(_shareAccessDetails!),
                    if (_shareDetailsInfo != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _shareDetailsInfo!,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ..._shareAccessDetails!.participants
                        .map(_buildParticipantRow),
                  ],
                ),
              )
            else if (_shareDetailsError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Text(
                  _shareDetailsError!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.redAccent,
                  ),
                ),
              ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
              minLeadingWidth: 24,
              leading: SizedBox(
                width: 24,
                child: Center(
                  child: Radio<String>(
                    value: 'view_access',
                    groupValue: _shareMode,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) => setState(() => _shareMode = v!),
                  ),
                ),
              ),
              title: const Text('Share view access only'),
              onTap: () => setState(() => _shareMode = 'view_access'),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
              minLeadingWidth: 24,
              leading: SizedBox(
                width: 24,
                child: Center(
                  child: Radio<String>(
                    value: 'edit_access',
                    groupValue: _shareMode,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) => setState(() => _shareMode = v!),
                  ),
                ),
              ),
              title: const Text('Share edit access'),
              onTap: () => setState(() => _shareMode = 'edit_access'),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.send_outlined),
              title: const Text('Share to Plendy friends'),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Coming soon.')),
                );
              },
            ),
            ListTile(
              leading: _creating
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link_outlined),
              title:
                  Text(_creating ? 'Creating link...' : 'Get shareable link'),
              onTap: _creating
                  ? null
                  : () async {
                      setState(() => _creating = true);
                      final bool grantEdit = _shareMode == 'edit_access';
                      try {
                        final DateTime expiresAt =
                            DateTime.now().add(const Duration(days: 30));
                        final shareService = CategoryShareService();
                        late final String url;
                        final BuildContext rootContext =
                            Navigator.of(context, rootNavigator: true).context;
                        if (widget.userCategory != null) {
                          url = await shareService.createLinkShareForCategory(
                            category: widget.userCategory!,
                            accessMode: grantEdit ? 'edit' : 'view',
                            expiresAt: expiresAt,
                          );
                        } else if (widget.colorCategory != null) {
                          url = await shareService
                              .createLinkShareForColorCategory(
                            colorCategory: widget.colorCategory!,
                            accessMode: grantEdit ? 'edit' : 'view',
                            expiresAt: expiresAt,
                          );
                        } else {
                          throw Exception('No category provided');
                        }
                        if (mounted) {
                          Navigator.of(context).pop();
                        }
                        _showShareUrlOptions(rootContext, url);
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Failed to create link: ' + e.toString()),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _creating = false);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}

class _BulkShareBottomSheetContent extends StatefulWidget {
  final List<UserCategory>? userCategories;
  final List<ColorCategory>? colorCategories;

  const _BulkShareBottomSheetContent({
    this.userCategories,
    this.colorCategories,
  });

  @override
  State<_BulkShareBottomSheetContent> createState() =>
      _BulkShareBottomSheetContentState();
}

class _BulkShareBottomSheetContentState
    extends State<_BulkShareBottomSheetContent> {
  String _shareMode = 'view_access';
  bool _creating = false;

  void _showShareUrlOptionsLocal(BuildContext context, String url) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Share link',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(url, style: const TextStyle(fontSize: 14)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () async {
                        await Share.share(url);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      },
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Share'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(ctx).primaryColor,
                          foregroundColor: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: url));
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('Link copied')));
                        }
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy'),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final int count = (widget.userCategories?.length ?? 0) +
        (widget.colorCategories?.length ?? 0);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Share ${count} ${count == 1 ? 'category' : 'categories'}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if ((widget.userCategories?.isNotEmpty ?? false) ||
                (widget.colorCategories?.isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Text(
                  'Selected:',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            if (widget.userCategories != null)
              ...widget.userCategories!.map((c) => ListTile(
                    dense: true,
                    visualDensity:
                        const VisualDensity(horizontal: -4, vertical: -4),
                    leading: const Icon(Icons.label_outline),
                    title: Text(c.name, overflow: TextOverflow.ellipsis),
                    subtitle: Text('Category',
                        style: Theme.of(context).textTheme.bodySmall),
                  )),
            if (widget.colorCategories != null)
              ...widget.colorCategories!.map((c) => ListTile(
                    dense: true,
                    visualDensity:
                        const VisualDensity(horizontal: -4, vertical: -4),
                    leading: const Icon(Icons.color_lens_outlined),
                    title: Text(c.name, overflow: TextOverflow.ellipsis),
                    subtitle: Text('Color Category',
                        style: Theme.of(context).textTheme.bodySmall),
                  )),
            const Divider(height: 24),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
              minLeadingWidth: 24,
              leading: SizedBox(
                width: 24,
                child: Center(
                  child: Radio<String>(
                    value: 'view_access',
                    groupValue: _shareMode,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) => setState(() => _shareMode = v!),
                  ),
                ),
              ),
              title: const Text('Share view access only'),
              onTap: () => setState(() => _shareMode = 'view_access'),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
              minLeadingWidth: 24,
              leading: SizedBox(
                width: 24,
                child: Center(
                  child: Radio<String>(
                    value: 'edit_access',
                    groupValue: _shareMode,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) => setState(() => _shareMode = v!),
                  ),
                ),
              ),
              title: const Text('Share edit access'),
              onTap: () => setState(() => _shareMode = 'edit_access'),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: _creating
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link_outlined),
              title:
                  Text(_creating ? 'Creating link...' : 'Get shareable link'),
              onTap: _creating
                  ? null
                  : () async {
                      setState(() => _creating = true);
                      try {
                        final service = CategoryShareService();
                        final DateTime expiresAt =
                            DateTime.now().add(const Duration(days: 30));
                        final String mode =
                            _shareMode == 'edit_access' ? 'edit' : 'view';
                        final String url =
                            await service.createLinkShareForMultiple(
                          userCategories: widget.userCategories ?? const [],
                          colorCategories: widget.colorCategories ?? const [],
                          accessMode: mode,
                          expiresAt: expiresAt,
                        );
                        if (!mounted) return;
                        Navigator.of(context).pop();
                        _showShareUrlOptionsLocal(context, url);
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  'Failed to create link: ' + e.toString())),
                        );
                      } finally {
                        if (mounted) setState(() => _creating = false);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}
