import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_category.dart';
import '../models/color_category.dart';
import '../models/experience.dart';
import '../models/enums/share_enums.dart';
import '../models/share_result.dart';
import '../models/user_profile.dart';
import 'experience_service.dart';
import 'sharing_service.dart';
import 'message_service.dart';
import 'user_service.dart';

class CategoryShareService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ExperienceService _experienceService = ExperienceService();
  final SharingService _sharingService = SharingService();
  final MessageService _messageService = MessageService();
  final UserService _userService = UserService();

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
        if (exp.colorCategoryId == colorCategory.id) {
          return true;
        }
        final otherColorIds = exp.otherColorCategoryIds;
        return otherColorIds.contains(colorCategory.id);
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
        exps.map((e) => _buildExperienceSnapshot(e, categoryIcon: category.icon)).toList();

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
    return 'https://plendy.app/shared-category/$token';
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
    // Convert color to hex string for the snapshot
    final String colorHex = '#${colorCategory.color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
    final List<Map<String, dynamic>> experienceSnapshots =
        exps.map((e) => _buildExperienceSnapshot(e, colorHex: colorHex)).toList();

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
    return 'https://plendy.app/shared-category/$token';
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
          exps.map((e) => _buildExperienceSnapshot(e, categoryIcon: category.icon)).toList();
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
      final String colorHex = '#${colorCategory.color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
      final List<Map<String, dynamic>> experienceSnapshots =
          exps.map((e) => _buildExperienceSnapshot(e, colorHex: colorHex)).toList();
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
    return 'https://plendy.app/shared-category/$token';
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
    
    // After granting category share, update sharedWithUserIds for all experiences in this category
    // This ensures new experiences added after the initial share are also visible
    try {
      await _experienceService.updateSharedUserIdsForCategory(categoryId);
      print('CategoryShareService: Updated sharedWithUserIds for experiences in category $categoryId');
    } catch (e) {
      print('CategoryShareService: Error updating sharedWithUserIds for category $categoryId: $e');
      // Don't throw - the share permission was created successfully
    }
  }

  Map<String, dynamic> _buildExperienceSnapshot(
    Experience exp, {
    String? categoryIcon,
    String? colorHex,
  }) {
    // Use provided category icon/color, or fall back to experience's denormalized values
    final String? finalCategoryIcon = categoryIcon ?? exp.categoryIconDenorm;
    final String? finalColorHex = colorHex ?? exp.colorHexDenorm;
    
    return {
      'experienceId': exp.id,
      'name': exp.name,
      'description': exp.description,
      'imageUrls': exp.imageUrls,
      'website': exp.website,
      'plendyRating': exp.plendyRating,
      'googleRating': exp.googleRating,
      'googleReviewCount': exp.googleReviewCount,
      'categoryIconDenorm': finalCategoryIcon,
      'colorHexDenorm': finalColorHex,
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

  /// Create a direct share for a UserCategory to specific users
  Future<DirectShareResult> createDirectShareForCategory({
    required UserCategory category,
    required List<String> toUserIds,
    String accessMode = 'view', // 'view' | 'edit'
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');
    if (toUserIds.isEmpty) throw Exception('No recipients provided');

    // Build category snapshot with experiences
    final List<Experience> exps =
        await _collectShareableExperiences(category: category);
    final List<Map<String, dynamic>> experienceSnapshots =
        exps.map((e) => _buildExperienceSnapshot(e, categoryIcon: category.icon)).toList();

    final categorySnapshot = {
      'name': category.name,
      'icon': category.icon,
      'categoryId': category.id,
      'categoryType': 'user',
      'accessMode': accessMode,
      'experiences': experienceSnapshots,
    };

    final data = {
      'fromUserId': userId,
      'toUserIds': toUserIds,
      'visibility': 'direct',
      'accessMode': accessMode,
      'categoryType': 'user',
      'categoryId': category.id,
      'snapshot': categorySnapshot,
      'createdAt': FieldValue.serverTimestamp(),
    };

    final shareDocRef = await _shares.add(data);

    // Grant share permissions to recipients
    for (final recipientId in toUserIds) {
      try {
        await grantSharedCategoryToUser(
          categoryId: category.id,
          ownerUserId: userId,
          targetUserId: recipientId,
          accessMode: accessMode,
          experienceIds: exps.map((e) => e.id).toList(),
        );
      } catch (e) {
        print('Failed to grant category share to $recipientId: $e');
      }
    }

    // Track thread IDs and recipient profiles for navigation
    final List<String> threadIds = [];
    final List<UserProfile> recipientProfiles = [];

    // If there's only one recipient, fetch their profile for personalized messaging
    if (toUserIds.length == 1) {
      try {
        final profile = await _userService.getUserProfile(toUserIds.first);
        if (profile != null) {
          recipientProfiles.add(profile);
        }
      } catch (e) {
        // Ignore profile fetch errors - we'll just use generic messaging
        print('Failed to fetch recipient profile: $e');
      }
    }

    // Send message to each recipient
    for (final recipientId in toUserIds) {
      try {
        final thread = await _messageService.createOrGetThread(
          currentUserId: userId,
          participantIds: [recipientId],
        );
        await _messageService.sendCategoryShareMessage(
          threadId: thread.id,
          senderId: userId,
          categorySnapshot: categorySnapshot,
          shareId: shareDocRef.id,
        );
        threadIds.add(thread.id);
      } catch (e) {
        print('Failed to send category share message to $recipientId: $e');
      }
    }

    return DirectShareResult(
      threadIds: threadIds,
      recipientProfiles: recipientProfiles,
    );
  }

  /// Create a direct share for a ColorCategory to specific users
  Future<DirectShareResult> createDirectShareForColorCategory({
    required ColorCategory colorCategory,
    required List<String> toUserIds,
    String accessMode = 'view', // 'view' | 'edit'
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');
    if (toUserIds.isEmpty) throw Exception('No recipients provided');

    // Build category snapshot with experiences
    final List<Experience> exps =
        await _collectShareableExperiences(colorCategory: colorCategory);
    final String colorHex = '#${colorCategory.color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
    final List<Map<String, dynamic>> experienceSnapshots =
        exps.map((e) => _buildExperienceSnapshot(e, colorHex: colorHex)).toList();

    final categorySnapshot = {
      'name': colorCategory.name,
      'color': colorCategory.color.value,
      'categoryId': colorCategory.id,
      'categoryType': 'color',
      'accessMode': accessMode,
      'experiences': experienceSnapshots,
    };

    final data = {
      'fromUserId': userId,
      'toUserIds': toUserIds,
      'visibility': 'direct',
      'accessMode': accessMode,
      'categoryType': 'color',
      'colorCategoryId': colorCategory.id,
      'snapshot': categorySnapshot,
      'createdAt': FieldValue.serverTimestamp(),
    };

    final shareDocRef = await _shares.add(data);

    // Grant share permissions to recipients
    for (final recipientId in toUserIds) {
      try {
        await grantSharedCategoryToUser(
          categoryId: colorCategory.id,
          ownerUserId: userId,
          targetUserId: recipientId,
          accessMode: accessMode,
          experienceIds: exps.map((e) => e.id).toList(),
        );
      } catch (e) {
        print('Failed to grant color category share to $recipientId: $e');
      }
    }

    // Track thread IDs and recipient profiles for navigation
    final List<String> threadIds = [];
    final List<UserProfile> recipientProfiles = [];

    // If there's only one recipient, fetch their profile for personalized messaging
    if (toUserIds.length == 1) {
      try {
        final profile = await _userService.getUserProfile(toUserIds.first);
        if (profile != null) {
          recipientProfiles.add(profile);
        }
      } catch (e) {
        // Ignore profile fetch errors - we'll just use generic messaging
        print('Failed to fetch recipient profile: $e');
      }
    }

    // Send message to each recipient
    for (final recipientId in toUserIds) {
      try {
        final thread = await _messageService.createOrGetThread(
          currentUserId: userId,
          participantIds: [recipientId],
        );
        await _messageService.sendCategoryShareMessage(
          threadId: thread.id,
          senderId: userId,
          categorySnapshot: categorySnapshot,
          shareId: shareDocRef.id,
        );
        threadIds.add(thread.id);
      } catch (e) {
        print('Failed to send color category share message to $recipientId: $e');
      }
    }

    return DirectShareResult(
      threadIds: threadIds,
      recipientProfiles: recipientProfiles,
    );
  }

  /// Create a direct share for a category to existing threads
  Future<DirectShareResult> createDirectShareForCategoryToThreads({
    required UserCategory category,
    required List<String> threadIds,
    String accessMode = 'view',
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');
    if (threadIds.isEmpty) throw Exception('No threads provided');

    // Build category snapshot with experiences
    final List<Experience> exps =
        await _collectShareableExperiences(category: category);
    final List<Map<String, dynamic>> experienceSnapshots =
        exps.map((e) => _buildExperienceSnapshot(e, categoryIcon: category.icon)).toList();

    final categorySnapshot = {
      'name': category.name,
      'icon': category.icon,
      'categoryId': category.id,
      'categoryType': 'user',
      'accessMode': accessMode,
      'experiences': experienceSnapshots,
    };

    final data = {
      'fromUserId': userId,
      'toThreadIds': threadIds,
      'visibility': 'direct',
      'accessMode': accessMode,
      'categoryType': 'user',
      'categoryId': category.id,
      'snapshot': categorySnapshot,
      'createdAt': FieldValue.serverTimestamp(),
    };

    final shareDocRef = await _shares.add(data);

    // Track successful thread IDs
    final List<String> successThreadIds = [];

    // Send message to each thread
    for (final threadId in threadIds) {
      try {
        await _messageService.sendCategoryShareMessage(
          threadId: threadId,
          senderId: userId,
          categorySnapshot: categorySnapshot,
          shareId: shareDocRef.id,
        );
        successThreadIds.add(threadId);
      } catch (e) {
        print('Failed to send category share message to thread $threadId: $e');
      }
    }

    return DirectShareResult(threadIds: successThreadIds);
  }

  /// Create a direct share for a color category to existing threads
  Future<DirectShareResult> createDirectShareForColorCategoryToThreads({
    required ColorCategory colorCategory,
    required List<String> threadIds,
    String accessMode = 'view',
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');
    if (threadIds.isEmpty) throw Exception('No threads provided');

    // Build category snapshot with experiences
    final List<Experience> exps =
        await _collectShareableExperiences(colorCategory: colorCategory);
    final String colorHex = '#${colorCategory.color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
    final List<Map<String, dynamic>> experienceSnapshots =
        exps.map((e) => _buildExperienceSnapshot(e, colorHex: colorHex)).toList();

    final categorySnapshot = {
      'name': colorCategory.name,
      'color': colorCategory.color.value,
      'categoryId': colorCategory.id,
      'categoryType': 'color',
      'accessMode': accessMode,
      'experiences': experienceSnapshots,
    };

    final data = {
      'fromUserId': userId,
      'toThreadIds': threadIds,
      'visibility': 'direct',
      'accessMode': accessMode,
      'categoryType': 'color',
      'colorCategoryId': colorCategory.id,
      'snapshot': categorySnapshot,
      'createdAt': FieldValue.serverTimestamp(),
    };

    final shareDocRef = await _shares.add(data);

    // Track successful thread IDs
    final List<String> successThreadIds = [];

    // Send message to each thread
    for (final threadId in threadIds) {
      try {
        await _messageService.sendCategoryShareMessage(
          threadId: threadId,
          senderId: userId,
          categorySnapshot: categorySnapshot,
          shareId: shareDocRef.id,
        );
        successThreadIds.add(threadId);
      } catch (e) {
        print('Failed to send color category share message to thread $threadId: $e');
      }
    }

    return DirectShareResult(threadIds: successThreadIds);
  }

  /// Create a direct share for a category to a new group chat
  Future<DirectShareResult> createDirectShareForCategoryToNewGroupChat({
    required UserCategory category,
    required List<String> participantIds,
    String accessMode = 'view',
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');
    if (participantIds.isEmpty) throw Exception('No participants provided');

    // Build category snapshot with experiences
    final List<Experience> exps =
        await _collectShareableExperiences(category: category);
    final List<Map<String, dynamic>> experienceSnapshots =
        exps.map((e) => _buildExperienceSnapshot(e, categoryIcon: category.icon)).toList();

    final categorySnapshot = {
      'name': category.name,
      'icon': category.icon,
      'categoryId': category.id,
      'categoryType': 'user',
      'accessMode': accessMode,
      'experiences': experienceSnapshots,
    };

    // Create the group thread first
    final thread = await _messageService.createOrGetThread(
      currentUserId: userId,
      participantIds: participantIds,
    );

    final data = {
      'fromUserId': userId,
      'toUserIds': participantIds,
      'toThreadId': thread.id,
      'visibility': 'direct',
      'accessMode': accessMode,
      'categoryType': 'user',
      'categoryId': category.id,
      'isGroupShare': true,
      'snapshot': categorySnapshot,
      'createdAt': FieldValue.serverTimestamp(),
    };

    final shareDocRef = await _shares.add(data);

    // Grant share permissions to all participants
    for (final recipientId in participantIds) {
      try {
        await grantSharedCategoryToUser(
          categoryId: category.id,
          ownerUserId: userId,
          targetUserId: recipientId,
          accessMode: accessMode,
          experienceIds: exps.map((e) => e.id).toList(),
        );
      } catch (e) {
        print('Failed to grant category share to $recipientId: $e');
      }
    }

    // Send message to the group thread
    await _messageService.sendCategoryShareMessage(
      threadId: thread.id,
      senderId: userId,
      categorySnapshot: categorySnapshot,
      shareId: shareDocRef.id,
    );

    return DirectShareResult.single(thread.id);
  }

  /// Create a direct share for a color category to a new group chat
  Future<DirectShareResult> createDirectShareForColorCategoryToNewGroupChat({
    required ColorCategory colorCategory,
    required List<String> participantIds,
    String accessMode = 'view',
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');
    if (participantIds.isEmpty) throw Exception('No participants provided');

    // Build category snapshot with experiences
    final List<Experience> exps =
        await _collectShareableExperiences(colorCategory: colorCategory);
    final String colorHex = '#${colorCategory.color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
    final List<Map<String, dynamic>> experienceSnapshots =
        exps.map((e) => _buildExperienceSnapshot(e, colorHex: colorHex)).toList();

    final categorySnapshot = {
      'name': colorCategory.name,
      'color': colorCategory.color.value,
      'categoryId': colorCategory.id,
      'categoryType': 'color',
      'accessMode': accessMode,
      'experiences': experienceSnapshots,
    };

    // Create the group thread first
    final thread = await _messageService.createOrGetThread(
      currentUserId: userId,
      participantIds: participantIds,
    );

    final data = {
      'fromUserId': userId,
      'toUserIds': participantIds,
      'toThreadId': thread.id,
      'visibility': 'direct',
      'accessMode': accessMode,
      'categoryType': 'color',
      'colorCategoryId': colorCategory.id,
      'isGroupShare': true,
      'snapshot': categorySnapshot,
      'createdAt': FieldValue.serverTimestamp(),
    };

    final shareDocRef = await _shares.add(data);

    // Grant share permissions to all participants
    for (final recipientId in participantIds) {
      try {
        await grantSharedCategoryToUser(
          categoryId: colorCategory.id,
          ownerUserId: userId,
          targetUserId: recipientId,
          accessMode: accessMode,
          experienceIds: exps.map((e) => e.id).toList(),
        );
      } catch (e) {
        print('Failed to grant color category share to $recipientId: $e');
      }
    }

    // Send message to the group thread
    await _messageService.sendCategoryShareMessage(
      threadId: thread.id,
      senderId: userId,
      categorySnapshot: categorySnapshot,
      shareId: shareDocRef.id,
    );

    return DirectShareResult.single(thread.id);
  }

  /// Create a direct share for multiple categories to specific users
  Future<DirectShareResult> createDirectShareForMultipleCategories({
    List<UserCategory> userCategories = const [],
    List<ColorCategory> colorCategories = const [],
    required List<String> toUserIds,
    String accessMode = 'view',
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');
    if (toUserIds.isEmpty) throw Exception('No recipients provided');
    if (userCategories.isEmpty && colorCategories.isEmpty) {
      throw Exception('No categories selected');
    }

    // Build snapshots for all categories
    final List<Map<String, dynamic>> categorySnapshots = [];

    for (final category in userCategories) {
      final List<Experience> exps =
          await _collectShareableExperiences(category: category);
      final List<Map<String, dynamic>> experienceSnapshots =
          exps.map((e) => _buildExperienceSnapshot(e, categoryIcon: category.icon)).toList();
      categorySnapshots.add({
        'name': category.name,
        'icon': category.icon,
        'categoryId': category.id,
        'categoryType': 'user',
        'accessMode': accessMode,
        'experiences': experienceSnapshots,
      });
    }

    for (final colorCategory in colorCategories) {
      final List<Experience> exps =
          await _collectShareableExperiences(colorCategory: colorCategory);
      final String colorHex = '#${colorCategory.color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
      final List<Map<String, dynamic>> experienceSnapshots =
          exps.map((e) => _buildExperienceSnapshot(e, colorHex: colorHex)).toList();
      categorySnapshots.add({
        'name': colorCategory.name,
        'color': colorCategory.color.value,
        'categoryId': colorCategory.id,
        'categoryType': 'color',
        'accessMode': accessMode,
        'experiences': experienceSnapshots,
      });
    }

    final data = {
      'fromUserId': userId,
      'toUserIds': toUserIds,
      'visibility': 'direct',
      'accessMode': accessMode,
      'categoryType': 'multi',
      'userCategoryIds': userCategories.map((c) => c.id).toList(),
      'colorCategoryIds': colorCategories.map((c) => c.id).toList(),
      'categorySnapshots': categorySnapshots,
      'createdAt': FieldValue.serverTimestamp(),
    };

    final shareDocRef = await _shares.add(data);

    // Grant share permissions to recipients for all categories
    for (final recipientId in toUserIds) {
      for (final category in userCategories) {
        try {
          final exps = await _collectShareableExperiences(category: category);
          await grantSharedCategoryToUser(
            categoryId: category.id,
            ownerUserId: userId,
            targetUserId: recipientId,
            accessMode: accessMode,
            experienceIds: exps.map((e) => e.id).toList(),
          );
        } catch (e) {
          print('Failed to grant category share to $recipientId: $e');
        }
      }
      for (final colorCategory in colorCategories) {
        try {
          final exps = await _collectShareableExperiences(colorCategory: colorCategory);
          await grantSharedCategoryToUser(
            categoryId: colorCategory.id,
            ownerUserId: userId,
            targetUserId: recipientId,
            accessMode: accessMode,
            experienceIds: exps.map((e) => e.id).toList(),
          );
        } catch (e) {
          print('Failed to grant color category share to $recipientId: $e');
        }
      }
    }

    // Track thread IDs
    final List<String> threadIds = [];

    // Send message to each recipient
    for (final recipientId in toUserIds) {
      try {
        final thread = await _messageService.createOrGetThread(
          currentUserId: userId,
          participantIds: [recipientId],
        );
        await _messageService.sendMultiCategoryShareMessage(
          threadId: thread.id,
          senderId: userId,
          categorySnapshots: categorySnapshots,
          shareId: shareDocRef.id,
        );
        threadIds.add(thread.id);
      } catch (e) {
        print('Failed to send multi-category share message to $recipientId: $e');
      }
    }

    return DirectShareResult(threadIds: threadIds);
  }

  /// Create a direct share for multiple categories to existing threads
  Future<DirectShareResult> createDirectShareForMultipleCategoriesToThreads({
    List<UserCategory> userCategories = const [],
    List<ColorCategory> colorCategories = const [],
    required List<String> threadIds,
    String accessMode = 'view',
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');
    if (threadIds.isEmpty) throw Exception('No threads provided');
    if (userCategories.isEmpty && colorCategories.isEmpty) {
      throw Exception('No categories selected');
    }

    // Build snapshots for all categories
    final List<Map<String, dynamic>> categorySnapshots = [];

    for (final category in userCategories) {
      final List<Experience> exps =
          await _collectShareableExperiences(category: category);
      final List<Map<String, dynamic>> experienceSnapshots =
          exps.map((e) => _buildExperienceSnapshot(e, categoryIcon: category.icon)).toList();
      categorySnapshots.add({
        'name': category.name,
        'icon': category.icon,
        'categoryId': category.id,
        'categoryType': 'user',
        'accessMode': accessMode,
        'experiences': experienceSnapshots,
      });
    }

    for (final colorCategory in colorCategories) {
      final List<Experience> exps =
          await _collectShareableExperiences(colorCategory: colorCategory);
      final String colorHex = '#${colorCategory.color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
      final List<Map<String, dynamic>> experienceSnapshots =
          exps.map((e) => _buildExperienceSnapshot(e, colorHex: colorHex)).toList();
      categorySnapshots.add({
        'name': colorCategory.name,
        'color': colorCategory.color.value,
        'categoryId': colorCategory.id,
        'categoryType': 'color',
        'accessMode': accessMode,
        'experiences': experienceSnapshots,
      });
    }

    final data = {
      'fromUserId': userId,
      'toThreadIds': threadIds,
      'visibility': 'direct',
      'accessMode': accessMode,
      'categoryType': 'multi',
      'userCategoryIds': userCategories.map((c) => c.id).toList(),
      'colorCategoryIds': colorCategories.map((c) => c.id).toList(),
      'categorySnapshots': categorySnapshots,
      'createdAt': FieldValue.serverTimestamp(),
    };

    final shareDocRef = await _shares.add(data);

    // Track successful thread IDs
    final List<String> successThreadIds = [];

    // Send message to each thread
    for (final threadId in threadIds) {
      try {
        await _messageService.sendMultiCategoryShareMessage(
          threadId: threadId,
          senderId: userId,
          categorySnapshots: categorySnapshots,
          shareId: shareDocRef.id,
        );
        successThreadIds.add(threadId);
      } catch (e) {
        print('Failed to send multi-category share message to thread $threadId: $e');
      }
    }

    return DirectShareResult(threadIds: successThreadIds);
  }

  /// Create a direct share for multiple categories to a new group chat
  Future<DirectShareResult> createDirectShareForMultipleCategoriesToNewGroupChat({
    List<UserCategory> userCategories = const [],
    List<ColorCategory> colorCategories = const [],
    required List<String> participantIds,
    String accessMode = 'view',
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');
    if (participantIds.isEmpty) throw Exception('No participants provided');
    if (userCategories.isEmpty && colorCategories.isEmpty) {
      throw Exception('No categories selected');
    }

    // Build snapshots for all categories
    final List<Map<String, dynamic>> categorySnapshots = [];

    for (final category in userCategories) {
      final List<Experience> exps =
          await _collectShareableExperiences(category: category);
      final List<Map<String, dynamic>> experienceSnapshots =
          exps.map((e) => _buildExperienceSnapshot(e, categoryIcon: category.icon)).toList();
      categorySnapshots.add({
        'name': category.name,
        'icon': category.icon,
        'categoryId': category.id,
        'categoryType': 'user',
        'accessMode': accessMode,
        'experiences': experienceSnapshots,
      });
    }

    for (final colorCategory in colorCategories) {
      final List<Experience> exps =
          await _collectShareableExperiences(colorCategory: colorCategory);
      final String colorHex = '#${colorCategory.color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
      final List<Map<String, dynamic>> experienceSnapshots =
          exps.map((e) => _buildExperienceSnapshot(e, colorHex: colorHex)).toList();
      categorySnapshots.add({
        'name': colorCategory.name,
        'color': colorCategory.color.value,
        'categoryId': colorCategory.id,
        'categoryType': 'color',
        'accessMode': accessMode,
        'experiences': experienceSnapshots,
      });
    }

    // Create the group thread first
    final thread = await _messageService.createOrGetThread(
      currentUserId: userId,
      participantIds: participantIds,
    );

    final data = {
      'fromUserId': userId,
      'toUserIds': participantIds,
      'toThreadId': thread.id,
      'visibility': 'direct',
      'accessMode': accessMode,
      'categoryType': 'multi',
      'userCategoryIds': userCategories.map((c) => c.id).toList(),
      'colorCategoryIds': colorCategories.map((c) => c.id).toList(),
      'isGroupShare': true,
      'categorySnapshots': categorySnapshots,
      'createdAt': FieldValue.serverTimestamp(),
    };

    final shareDocRef = await _shares.add(data);

    // Grant share permissions to all participants for all categories
    for (final recipientId in participantIds) {
      for (final category in userCategories) {
        try {
          final exps = await _collectShareableExperiences(category: category);
          await grantSharedCategoryToUser(
            categoryId: category.id,
            ownerUserId: userId,
            targetUserId: recipientId,
            accessMode: accessMode,
            experienceIds: exps.map((e) => e.id).toList(),
          );
        } catch (e) {
          print('Failed to grant category share to $recipientId: $e');
        }
      }
      for (final colorCategory in colorCategories) {
        try {
          final exps = await _collectShareableExperiences(colorCategory: colorCategory);
          await grantSharedCategoryToUser(
            categoryId: colorCategory.id,
            ownerUserId: userId,
            targetUserId: recipientId,
            accessMode: accessMode,
            experienceIds: exps.map((e) => e.id).toList(),
          );
        } catch (e) {
          print('Failed to grant color category share to $recipientId: $e');
        }
      }
    }

    // Send message to the group thread
    await _messageService.sendMultiCategoryShareMessage(
      threadId: thread.id,
      senderId: userId,
      categorySnapshots: categorySnapshots,
      shareId: shareDocRef.id,
    );

    return DirectShareResult.single(thread.id);
  }
}
