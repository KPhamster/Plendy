import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_category.dart';
import '../models/color_category.dart';
import '../models/experience.dart';
import '../models/enums/share_enums.dart';
import 'experience_service.dart';
import 'sharing_service.dart';

class CategoryShareService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ExperienceService _experienceService = ExperienceService();
  final SharingService _sharingService = SharingService();

  CollectionReference get _shares => _firestore.collection('category_shares');

  String? get _currentUserId => _auth.currentUser?.uid;

  String _generateToken() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random.secure();
    return List.generate(12, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<List<Experience>> _collectShareableExperiences({
    UserCategory? category,
    ColorCategory? colorCategory,
  }) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    bool matches(Experience exp) {
      if (category != null) {
        if (exp.categoryId == category.id) {
          return true;
        }
        final otherCats = exp.otherCategories;
        return otherCats.contains(category.id);
      }
      if (colorCategory != null) {
        return exp.colorCategoryId == colorCategory.id;
      }
      return false;
    }

    final List<Experience> collected = [];
    final Set<String> seenIds = {};

    void addMatching(Iterable<Experience> experiences) {
      for (final exp in experiences) {
        if (!matches(exp)) {
          continue;
        }
        if (seenIds.add(exp.id)) {
          collected.add(exp);
        }
      }
    }

    try {
      final editorExperiences = await _experienceService.getUserExperiences();
      addMatching(editorExperiences);
    } catch (e) {
      print('CategoryShareService: Failed to load editor experiences: $e');
    }

    try {
      final createdExperiences =
          await _experienceService.getExperiencesByUser(userId, limit: 500);
      addMatching(createdExperiences);
    } catch (e) {
      print('CategoryShareService: Failed to load created experiences: $e');
    }

    return collected;
  }

  Future<String> createLinkShareForCategory({
    required UserCategory category,
    String accessMode = 'view', // 'view' | 'edit'
    bool public = false,
    DateTime? expiresAt,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final token = _generateToken();
    // Build experiences snapshot for this category (minimal fields for preview)
    // Include both primary categoryId and otherCategories membership
    final List<Experience> exps =
        await _collectShareableExperiences(category: category);
    final List<Map<String, dynamic>> experienceSnapshots =
        exps.map((e) => _buildExperienceSnapshot(e)).toList();

    final data = {
      'fromUserId': userId,
      'token': token,
      'visibility': public ? 'public' : 'unlisted',
      'accessMode': accessMode, // 'view' | 'edit'
      'categoryType': 'user', // 'user' | 'color'
      'categoryId': category.id,
      'snapshot': {
        'name': category.name,
        'icon': category.icon,
        'experiences': experienceSnapshots,
      },
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
      'createdAt': FieldValue.serverTimestamp(),
    };

    await _shares.doc(token).set(data);
    return 'https://plendy.app/shared-category/' + token;
  }

  Future<String> createLinkShareForColorCategory({
    required ColorCategory colorCategory,
    String accessMode = 'view', // 'view' | 'edit'
    bool public = false,
    DateTime? expiresAt,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final token = _generateToken();
    // Build experiences snapshot for this color category
    final List<Experience> exps =
        await _collectShareableExperiences(colorCategory: colorCategory);
    final List<Map<String, dynamic>> experienceSnapshots =
        exps.map((e) => _buildExperienceSnapshot(e)).toList();

    final data = {
      'fromUserId': userId,
      'token': token,
      'visibility': public ? 'public' : 'unlisted',
      'accessMode': accessMode, // 'view' | 'edit'
      'categoryType': 'color', // 'user' | 'color'
      'colorCategoryId': colorCategory.id,
      'snapshot': {
        'name': colorCategory.name,
        'color': colorCategory.color.value,
        'experiences': experienceSnapshots,
      },
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
      'createdAt': FieldValue.serverTimestamp(),
    };

    await _shares.doc(token).set(data);
    return 'https://plendy.app/shared-category/' + token;
  }

  Future<String> createLinkShareForMultiple({
    List<UserCategory> userCategories = const [],
    List<ColorCategory> colorCategories = const [],
    String accessMode = 'view', // 'view' | 'edit'
    bool public = false,
    DateTime? expiresAt,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');
    if (userCategories.isEmpty && colorCategories.isEmpty) {
      throw Exception('No categories selected');
    }

    final token = _generateToken();

    // Build snapshots per category
    final List<Map<String, dynamic>> userCategorySnapshots = [];
    for (final category in userCategories) {
      final List<Experience> exps =
          await _collectShareableExperiences(category: category);
      final List<Map<String, dynamic>> experienceSnapshots =
          exps.map((e) => _buildExperienceSnapshot(e)).toList();
      userCategorySnapshots.add({
        'id': category.id,
        'name': category.name,
        'icon': category.icon,
        'experiences': experienceSnapshots,
      });
    }

    final List<Map<String, dynamic>> colorCategorySnapshots = [];
    for (final colorCategory in colorCategories) {
      final List<Experience> exps =
          await _collectShareableExperiences(colorCategory: colorCategory);
      final List<Map<String, dynamic>> experienceSnapshots =
          exps.map((e) => _buildExperienceSnapshot(e)).toList();
      colorCategorySnapshots.add({
        'id': colorCategory.id,
        'name': colorCategory.name,
        'color': colorCategory.color.value,
        'experiences': experienceSnapshots,
      });
    }

    final data = {
      'fromUserId': userId,
      'token': token,
      'visibility': public ? 'public' : 'unlisted',
      'accessMode': accessMode,
      'categoryType': 'multi',
      'userCategoryIds': userCategories.map((c) => c.id).toList(),
      'colorCategoryIds': colorCategories.map((c) => c.id).toList(),
      'snapshot': {
        'userCategories': userCategorySnapshots,
        'colorCategories': colorCategorySnapshots,
      },
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
      'createdAt': FieldValue.serverTimestamp(),
    };

    await _shares.doc(token).set(data);
    return 'https://plendy.app/shared-category/' + token;
  }

  Future<void> grantSharedCategoryToUser({
    required String categoryId,
    required String ownerUserId,
    required String targetUserId,
    required String accessMode,
    required List<String> experienceIds,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (categoryId.isEmpty || ownerUserId.isEmpty || targetUserId.isEmpty) {
      throw Exception('Invalid parameters for saving shared category');
    }

    // If the owner is saving their own shared link, do nothing.
    // They already have ownership; don't create redundant share permissions.
    if (ownerUserId == targetUserId) {
      // Still report a completed no-op to the progress handler for smooth UX
      final int totalSteps = 1 + experienceIds.where((id) => id.isNotEmpty).toSet().length;
      if (onProgress != null) {
        onProgress(totalSteps, totalSteps);
      }
      return;
    }

    final mode = accessMode.toLowerCase();
    const editModes = {'edit', 'edit_category', 'edit_color_category'};
    final ShareAccessLevel accessLevel = editModes.contains(mode)
        ? ShareAccessLevel.edit
        : ShareAccessLevel.view;

    final Set<String> uniqueExperienceIds =
        experienceIds.where((id) => id.isNotEmpty).toSet();
    final int totalSteps = 1 + uniqueExperienceIds.length;
    int completedSteps = 0;

    void reportProgress() {
      if (onProgress != null) {
        onProgress(completedSteps, totalSteps);
      }
    }

    await _sharingService.shareItem(
      itemId: categoryId,
      itemType: ShareableItemType.category,
      ownerUserId: ownerUserId,
      sharedWithUserId: targetUserId,
      accessLevel: accessLevel,
    );
    completedSteps = completedSteps + 1;
    reportProgress();

    for (final experienceId in uniqueExperienceIds) {
      await _sharingService.shareItem(
        itemId: experienceId,
        itemType: ShareableItemType.experience,
        ownerUserId: ownerUserId,
        sharedWithUserId: targetUserId,
        accessLevel: accessLevel,
      );
      completedSteps = completedSteps + 1;
      reportProgress();
    }
  }

  Map<String, dynamic> _buildExperienceSnapshot(Experience exp) {
    return {
      'experienceId': exp.id,
      'name': exp.name,
      'description': exp.description,
      'imageUrls': exp.imageUrls,
      'website': exp.website,
      'plendyRating': exp.plendyRating,
      'googleRating': exp.googleRating,
      'googleReviewCount': exp.googleReviewCount,
      'location': {
        'displayName': exp.location.displayName,
        'address': exp.location.address,
        'city': exp.location.city,
        'state': exp.location.state,
        'country': exp.location.country,
        'placeId': exp.location.placeId,
        'latitude': exp.location.latitude,
        'longitude': exp.location.longitude,
        'website': exp.location.website,
      },
    };
  }
}
