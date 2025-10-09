import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:plendy/models/category_sort_type.dart';
import 'package:plendy/models/color_category.dart';
import 'package:plendy/models/share_permission.dart';
import 'package:plendy/models/user_category.dart';
import 'package:plendy/services/experience_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CategoryOrderingService {
  CategoryOrderingService({
    FirebaseAuth? auth,
    ExperienceService? experienceService,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _experienceService = experienceService ?? ExperienceService();

  final FirebaseAuth _auth;
  final ExperienceService _experienceService;

  static const String _prefsKeyCategorySort = 'collections_category_sort';
  static const String _prefsKeyColorCategorySort =
      'collections_color_category_sort';
  static const String _prefsKeyCategoryOrderPrefix =
      'collections_category_order_';
  static const String _prefsKeyColorCategoryOrderPrefix =
      'collections_color_category_order_';
  static const String _prefsKeyUseManualCategoryOrderPrefix =
      'collections_use_manual_category_order_';
  static const String _prefsKeyUseManualColorCategoryOrderPrefix =
      'collections_use_manual_color_category_order_';

  String? get _currentUserId => _auth.currentUser?.uid;

  Future<List<UserCategory>> orderUserCategories(
    List<UserCategory> categories, {
    Map<String, SharePermission>? sharedPermissions,
  }) async {
    if (categories.length <= 1) {
      return List<UserCategory>.from(categories);
    }

    final prefs = await _loadCategoryOrderingPreferences();
    final List<UserCategory> copy = List<UserCategory>.from(categories);
    final List<String> syncedManualOrder = _syncManualOrderList(
      prefs.manualOrder,
      copy.map((category) => category.id),
    );

    if (prefs.useManualOrder && syncedManualOrder.isNotEmpty) {
      return _applyManualOrder<UserCategory>(
        items: copy,
        manualOrderIds: syncedManualOrder,
        idSelector: (category) => category.id,
      );
    }

    final Map<String, SharePermission> permissionMap = sharedPermissions ??
        await _experienceService.getEditableCategoryPermissionsMap();

    copy.sort((a, b) => _compareCategoriesForSort(
          a,
          b,
          prefs.sortType,
          permissionMap,
          _currentUserId,
        ));
    return copy;
  }

  Future<List<ColorCategory>> orderColorCategories(
      List<ColorCategory> categories) async {
    if (categories.length <= 1) {
      return List<ColorCategory>.from(categories);
    }

    final prefs = await _loadColorCategoryOrderingPreferences();
    final List<ColorCategory> copy = List<ColorCategory>.from(categories);
    final List<String> syncedManualOrder = _syncManualOrderList(
      prefs.manualOrder,
      copy.map((category) => category.id),
    );

    if (prefs.useManualOrder && syncedManualOrder.isNotEmpty) {
      return _applyManualOrder<ColorCategory>(
        items: copy,
        manualOrderIds: syncedManualOrder,
        idSelector: (category) => category.id,
      );
    }

    copy.sort((a, b) => _compareColorCategoriesForSort(
          a,
          b,
          prefs.sortType,
        ));
    return copy;
  }

  Future<_CategoryOrderingPreferences>
      _loadCategoryOrderingPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    CategorySortType sortType = CategorySortType.mostRecent;
    final storedSort = prefs.getString(_prefsKeyCategorySort);
    if (storedSort != null) {
      sortType = CategorySortType.values.firstWhere(
        (value) => value.name == storedSort,
        orElse: () => CategorySortType.mostRecent,
      );
    }

    List<String> manualOrder = [];
    bool useManual = false;
    final userId = _currentUserId;
    if (userId != null && userId.isNotEmpty) {
      final storedOrder =
          prefs.getStringList('$_prefsKeyCategoryOrderPrefix$userId');
      if (storedOrder != null) {
        manualOrder = List<String>.from(storedOrder);
      }
      useManual =
          prefs.getBool('$_prefsKeyUseManualCategoryOrderPrefix$userId') ??
              false;
    }

    return _CategoryOrderingPreferences(
      sortType: sortType,
      manualOrder: manualOrder,
      useManualOrder: useManual,
    );
  }

  Future<_ColorCategoryOrderingPreferences>
      _loadColorCategoryOrderingPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    ColorCategorySortType sortType = ColorCategorySortType.mostRecent;
    final storedSort = prefs.getString(_prefsKeyColorCategorySort);
    if (storedSort != null) {
      sortType = ColorCategorySortType.values.firstWhere(
        (value) => value.name == storedSort,
        orElse: () => ColorCategorySortType.mostRecent,
      );
    }

    List<String> manualOrder = [];
    bool useManual = false;
    final userId = _currentUserId;
    if (userId != null && userId.isNotEmpty) {
      final storedOrder =
          prefs.getStringList('$_prefsKeyColorCategoryOrderPrefix$userId');
      if (storedOrder != null) {
        manualOrder = List<String>.from(storedOrder);
      }
      useManual =
          prefs.getBool('$_prefsKeyUseManualColorCategoryOrderPrefix$userId') ??
              false;
    }

    return _ColorCategoryOrderingPreferences(
      sortType: sortType,
      manualOrder: manualOrder,
      useManualOrder: useManual,
    );
  }

  List<String> _syncManualOrderList(
      List<String> existingOrder, Iterable<String> currentIds) {
    final Set<String> currentIdSet = currentIds.toSet();
    final List<String> filtered = [
      for (final id in existingOrder)
        if (currentIdSet.contains(id)) id,
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
    required String Function(T item) idSelector,
  }) {
    final Map<String, T> byId = {
      for (final item in items) idSelector(item): item,
    };
    final List<T> ordered = [];
    final Set<String> seen = {};
    for (final id in manualOrderIds) {
      final T? item = byId[id];
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

  int _compareCategoriesForSort(
    UserCategory a,
    UserCategory b,
    CategorySortType sortType,
    Map<String, SharePermission> sharedPermissions,
    String? currentUserId,
  ) {
    if (sortType == CategorySortType.alphabetical) {
      final cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (cmp != 0) return cmp;
      return a.id.compareTo(b.id);
    }

    final bool aIsShared = _isSharedCategory(a, currentUserId);
    final bool bIsShared = _isSharedCategory(b, currentUserId);
    final Timestamp? tsA =
        aIsShared ? sharedPermissions[a.id]?.createdAt : a.lastUsedTimestamp;
    final Timestamp? tsB =
        bIsShared ? sharedPermissions[b.id]?.createdAt : b.lastUsedTimestamp;

    if (tsA == null && tsB == null) {
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }
    if (tsA == null) return 1;
    if (tsB == null) return -1;
    final cmp = tsB.compareTo(tsA);
    if (cmp != 0) return cmp;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  int _compareColorCategoriesForSort(
      ColorCategory a, ColorCategory b, ColorCategorySortType sortType) {
    if (sortType == ColorCategorySortType.alphabetical) {
      final cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (cmp != 0) return cmp;
      return a.id.compareTo(b.id);
    }

    final Timestamp? tsA = a.lastUsedTimestamp;
    final Timestamp? tsB = b.lastUsedTimestamp;
    if (tsA == null && tsB == null) {
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }
    if (tsA == null) return 1;
    if (tsB == null) return -1;
    final cmp = tsB.compareTo(tsA);
    if (cmp != 0) return cmp;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  bool _isSharedCategory(UserCategory category, String? currentUserId) {
    if (currentUserId == null || currentUserId.isEmpty) {
      return false;
    }
    return category.ownerUserId != currentUserId;
  }
}

class _CategoryOrderingPreferences {
  const _CategoryOrderingPreferences({
    required this.sortType,
    required this.manualOrder,
    required this.useManualOrder,
  });

  final CategorySortType sortType;
  final List<String> manualOrder;
  final bool useManualOrder;
}

class _ColorCategoryOrderingPreferences {
  const _ColorCategoryOrderingPreferences({
    required this.sortType,
    required this.manualOrder,
    required this.useManualOrder,
  });

  final ColorCategorySortType sortType;
  final List<String> manualOrder;
  final bool useManualOrder;
}
