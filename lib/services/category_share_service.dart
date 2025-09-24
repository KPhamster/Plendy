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

  Future<void> grantSharedCategoryToUser({
    required String categoryId,
    required String ownerUserId,
    required String targetUserId,
    required String accessMode,
    required List<String> experienceIds,
  }) async {
    if (categoryId.isEmpty || ownerUserId.isEmpty || targetUserId.isEmpty) {
      throw Exception('Invalid parameters for saving shared category');
    }

    final mode = accessMode.toLowerCase();
    const editModes = {'edit', 'edit_category', 'edit_color_category'};
    final ShareAccessLevel accessLevel = editModes.contains(mode)
        ? ShareAccessLevel.edit
        : ShareAccessLevel.view;

    await _sharingService.shareItem(
      itemId: categoryId,
      itemType: ShareableItemType.category,
      ownerUserId: ownerUserId,
      sharedWithUserId: targetUserId,
      accessLevel: accessLevel,
    );

    final Set<String> uniqueExperienceIds =
        experienceIds.where((id) => id.isNotEmpty).toSet();

    if (uniqueExperienceIds.isEmpty) {
      return;
    }

    await Future.wait(uniqueExperienceIds.map((experienceId) async {
      await _sharingService.shareItem(
        itemId: experienceId,
        itemType: ShareableItemType.experience,
        ownerUserId: ownerUserId,
        sharedWithUserId: targetUserId,
        accessLevel: accessLevel,
      );
    }));
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
