import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_category.dart';
import '../models/color_category.dart';
import '../models/experience.dart';
import 'experience_service.dart';

class CategoryShareService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference get _shares => _firestore.collection('category_shares');

  String? get _currentUserId => _auth.currentUser?.uid;

  String _generateToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random.secure();
    return List.generate(12, (_) => chars[rnd.nextInt(chars.length)]).join();
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
    final service = ExperienceService();
    // Include both primary categoryId and otherCategories membership
    final List<Experience> exps = await service.getExperiencesByUserCategoryAll(category.id);
    final List<Map<String, dynamic>> experienceSnapshots = exps.map((e) => _buildExperienceSnapshot(e)).toList();

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
    final service = ExperienceService();
    final List<Experience> exps = await service.getExperiencesByColorCategoryId(colorCategory.id);
    final List<Map<String, dynamic>> experienceSnapshots = exps.map((e) => _buildExperienceSnapshot(e)).toList();

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


