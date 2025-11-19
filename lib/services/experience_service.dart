import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/experience.dart';
import '../models/review.dart';
import '../models/comment.dart';
import '../models/reel.dart';
import '../models/user_category.dart';
import '../models/public_experience.dart';
import '../models/user_profile.dart';
import '../models/shared_media_item.dart';
// --- ADDED ---
import '../models/color_category.dart';
// --- END ADDED ---
import '../models/share_permission.dart';
import '../models/enums/share_enums.dart';

class UserCategoryFetchResult {
  const UserCategoryFetchResult({
    required this.categories,
    required this.sharedPermissions,
  });

  final List<UserCategory> categories;
  final Map<String, SharePermission> sharedPermissions;
}

class PublicExperiencePage {
  const PublicExperiencePage({
    required this.experiences,
    this.lastDocument,
    required this.hasMore,
  });

  final List<PublicExperience> experiences;
  final DocumentSnapshot<Object?>? lastDocument;
  final bool hasMore;
}

/// Service for managing Experience-related operations
class ExperienceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Category references
  CollectionReference get _experiencesCollection =>
      _firestore.collection('experiences');
  CollectionReference get _reviewsCollection =>
      _firestore.collection('reviews');
  CollectionReference get _commentsCollection =>
      _firestore.collection('comments');
  CollectionReference get _reelsCollection => _firestore.collection('reels');
  CollectionReference get _usersCollection => _firestore.collection('users');
  CollectionReference get _publicExperiencesCollection =>
      _firestore.collection('public_experiences');
  CollectionReference get _sharedMediaItemsCollection =>
      _firestore.collection('sharedMediaItems');
  CollectionReference get _sharePermissionsCollection =>
      _firestore.collection('share_permissions');

  // User-related operations
  String? get _currentUserId => _auth.currentUser?.uid;

  /// Fetch a user profile by ID
  Future<UserProfile?> getUserProfileById(String userId) async {
    try {
      final doc = await _usersCollection.doc(userId).get();
      if (!doc.exists) return null;
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return null;
      return UserProfile.fromMap(doc.id, data);
    } catch (e) {
      print('getUserProfileById: Error fetching user $userId: $e');
      return null;
    }
  }

  /// Batch fetch multiple user profiles by IDs using whereIn
  Future<List<UserProfile>> getUserProfilesByIds(List<String> userIds) async {
    if (userIds.isEmpty) return [];

    final uniqueIds = userIds.toSet().toList();
    const chunkSize = 30; // Firestore whereIn limit
    final List<UserProfile> results = [];

    // Split into chunks
    for (int i = 0; i < uniqueIds.length; i += chunkSize) {
      final end = (i + chunkSize) > uniqueIds.length
          ? uniqueIds.length
          : (i + chunkSize);
      final chunk = uniqueIds.sublist(i, end);

      try {
        final snapshot = await _usersCollection
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data != null) {
            results.add(UserProfile.fromMap(doc.id, data));
          }
        }
      } catch (e) {
        print('getUserProfilesByIds: Error fetching chunk: $e');
      }
    }

    return results;
  }

  /// Check if a category is shared with the current user and return the owner's userId
  Future<String?> _getCategoryShareOwner(String categoryId) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null || categoryId.isEmpty) return null;

    try {
      // Query for share permissions where this user is the recipient and the item is this category
      final snapshot = await _sharePermissionsCollection
          .where('itemType', isEqualTo: 'category')
          .where('itemId', isEqualTo: categoryId)
          .where('sharedWithUserId', isEqualTo: currentUserId)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;

      final data = snapshot.docs.first.data() as Map<String, dynamic>?;
      return data?['ownerUserId'] as String?;
    } catch (e) {
      debugPrint(
          '_getCategoryShareOwner: Error checking category share for $categoryId: $e');
      return null;
    }
  }

  Future<List<SharePermission>>
      _getEditableCategoryPermissionsForCurrentUser() async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      return [];
    }

    try {
      // Fetch BOTH view and edit permissions so users can see categories shared with them regardless of access level
      final snapshot = await _sharePermissionsCollection
          .where('sharedWithUserId', isEqualTo: currentUserId)
          .where('itemType', isEqualTo: ShareableItemType.category.name)
          .get();

      return snapshot.docs
          .map((doc) => SharePermission.fromFirestore(doc))
          .where((permission) => permission.ownerUserId != currentUserId)
          .toList();
    } catch (e) {
      debugPrint(
          '_getEditableCategoryPermissionsForCurrentUser: Error fetching share permissions: $e');
      return [];
    }
  }

  Future<Map<String, SharePermission>>
      getEditableCategoryPermissionsMap() async {
    final permissions = await _getEditableCategoryPermissionsForCurrentUser();
    final Map<String, SharePermission> map = {};
    for (final permission in permissions) {
      if (permission.itemId.isEmpty) {
        continue;
      }
      map[permission.itemId] = permission;
    }
    return map;
  }

  Future<String> _resolveShareOwnerDisplayName(
      String ownerUserId, Map<String, String> cache) async {
    if (ownerUserId.isEmpty) {
      return 'Someone';
    }
    if (cache.containsKey(ownerUserId)) {
      return cache[ownerUserId]!;
    }
    try {
      final profile = await getUserProfileById(ownerUserId);
      final displayName = profile?.displayName?.trim();
      final username = profile?.username?.trim();
      final resolved = (displayName != null && displayName.isNotEmpty)
          ? displayName
          : (username != null && username.isNotEmpty ? username : 'Someone');
      cache[ownerUserId] = resolved;
      return resolved;
    } catch (e) {
      debugPrint(
          '_resolveShareOwnerDisplayName: Failed to fetch owner name for $ownerUserId: $e');
      cache[ownerUserId] = 'Someone';
      return 'Someone';
    }
  }

  // Helper to get the path to a user's custom categories sub-category
  CollectionReference _userCategoriesCollection(String userId) =>
      _usersCollection.doc(userId).collection('categories');

  Future<UserCategory?> getUserCategoryByOwner(
      String ownerUserId, String categoryId) async {
    if (ownerUserId.isEmpty || categoryId.isEmpty) return null;
    try {
      final currentUserId = _currentUserId;
      final expectedPermissionId =
          '${ownerUserId}_category_${categoryId}_${currentUserId}';
      print(
          'getUserCategoryByOwner: Fetching users/$ownerUserId/categories/$categoryId');
      print(
          'getUserCategoryByOwner: Expected permission doc ID: $expectedPermissionId');
      final doc =
          await _userCategoriesCollection(ownerUserId).doc(categoryId).get();
      if (!doc.exists) {
        print('getUserCategoryByOwner: Document does not exist');
        return null;
      }
      final category = UserCategory.fromFirestore(doc);
      print('getUserCategoryByOwner: Found category: ${category.name}');
      return category;
    } catch (e) {
      print(
          'getUserCategoryByOwner: Failed to fetch $categoryId for $ownerUserId: $e');
      return null;
    }
  }

  // --- ADDED: Helper to get the path to a user's custom color categories sub-collection ---
  CollectionReference _userColorCategoriesCollection(String userId) =>
      _usersCollection.doc(userId).collection('color_categories');
  // --- END ADDED ---

  Future<ColorCategory?> getColorCategoryByOwner(
      String ownerUserId, String categoryId) async {
    if (ownerUserId.isEmpty || categoryId.isEmpty) return null;
    try {
      print(
          'getColorCategoryByOwner: Fetching users/$ownerUserId/color_categories/$categoryId');
      final doc = await _userColorCategoriesCollection(ownerUserId)
          .doc(categoryId)
          .get();
      if (!doc.exists) {
        print('getColorCategoryByOwner: Document does not exist');
        return null;
      }
      final category = ColorCategory.fromFirestore(doc);
      print('getColorCategoryByOwner: Found color category: ${category.name}');
      return category;
    } catch (e) {
      print(
          'getColorCategoryByOwner: Failed to fetch $categoryId for $ownerUserId: $e');
      return null;
    }
  }

  /// Batch fetch multiple user categories by owner and IDs using whereIn
  Future<List<UserCategory>> getUserCategoriesByOwnerAndIds(
      String ownerUserId, List<String> categoryIds) async {
    if (ownerUserId.isEmpty || categoryIds.isEmpty) return [];

    final uniqueIds = categoryIds.toSet().toList();
    const chunkSize = 30; // Firestore whereIn limit
    final List<UserCategory> results = [];

    // Split into chunks
    for (int i = 0; i < uniqueIds.length; i += chunkSize) {
      final end = (i + chunkSize) > uniqueIds.length
          ? uniqueIds.length
          : (i + chunkSize);
      final chunk = uniqueIds.sublist(i, end);

      try {
        final snapshot = await _userCategoriesCollection(ownerUserId)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        results.addAll(
            snapshot.docs.map((doc) => UserCategory.fromFirestore(doc)));
      } catch (e) {
        print(
            'getUserCategoriesByOwnerAndIds: Error fetching chunk for owner $ownerUserId: $e');
      }
    }

    return results;
  }

  /// Batch fetch multiple color categories by owner and IDs using whereIn
  Future<List<ColorCategory>> getColorCategoriesByOwnerAndIds(
      String ownerUserId, List<String> categoryIds) async {
    if (ownerUserId.isEmpty || categoryIds.isEmpty) return [];

    final uniqueIds = categoryIds.toSet().toList();
    const chunkSize = 30; // Firestore whereIn limit
    final List<ColorCategory> results = [];

    // Split into chunks
    for (int i = 0; i < uniqueIds.length; i += chunkSize) {
      final end = (i + chunkSize) > uniqueIds.length
          ? uniqueIds.length
          : (i + chunkSize);
      final chunk = uniqueIds.sublist(i, end);

      try {
        final snapshot = await _userColorCategoriesCollection(ownerUserId)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        results.addAll(
            snapshot.docs.map((doc) => ColorCategory.fromFirestore(doc)));
      } catch (e) {
        print(
            'getColorCategoriesByOwnerAndIds: Error fetching chunk for owner $ownerUserId: $e');
      }
    }

    return results;
  }

  // ======= User Category Operations =======

  /// Fetches the user's custom categories along with metadata about shared permissions.
  /// Set [includeSharedEditable] to true to append categories shared with the user that have edit access.
  Future<UserCategoryFetchResult> getUserCategoriesWithMeta(
      {bool includeSharedEditable = false}) async {
    final userId = _currentUserId;
    print(
        "getUserCategories START - User: $userId | includeSharedEditable: $includeSharedEditable");
    if (userId == null) {
      print("getUserCategories END - No user, returning empty list.");
      return const UserCategoryFetchResult(
        categories: <UserCategory>[],
        sharedPermissions: <String, SharePermission>{},
      );
    }

    final collectionRef = _userCategoriesCollection(userId);
    // UPDATED: Sort by orderIndex first (nulls handled by Firestore or considered last),
    // then by name for consistent ordering of items with the same/no index.
    final snapshot =
        await collectionRef.orderBy('orderIndex').orderBy('name').get();

    final List<UserCategory> ownedCategories =
        snapshot.docs.map((doc) => UserCategory.fromFirestore(doc)).toList();
    print(
        "getUserCategories - Fetched ${ownedCategories.length} owned categories from Firestore.");

    List<UserCategory> sharedCategories = [];
    final Map<String, SharePermission> sharedPermissionMap = {};
    if (includeSharedEditable) {
      final permissions = await _getEditableCategoryPermissionsForCurrentUser();
      print(
          "getUserCategories - Found ${permissions.length} editable shared category permissions.");

      if (permissions.isNotEmpty) {
        final processedKeys = <String>{};
        final fetchFutures = <Future<UserCategory?>>[];
        final fetchPermissions = <SharePermission>[];
        final ownerNameCache = <String, String>{};

        for (final permission in permissions) {
          if (permission.itemId.isEmpty || permission.ownerUserId.isEmpty) {
            continue;
          }
          final key = '${permission.ownerUserId}_${permission.itemId}';
          if (!processedKeys.add(key)) {
            continue;
          }

          fetchPermissions.add(permission);
          fetchFutures.add(() async {
            try {
              final doc =
                  await _userCategoriesCollection(permission.ownerUserId)
                      .doc(permission.itemId)
                      .get();
              if (!doc.exists) {
                debugPrint(
                    'getUserCategories - Shared category ${permission.itemId} not found for owner ${permission.ownerUserId}.');
                return null;
              }
              final category = UserCategory.fromFirestore(doc);
              final ownerName = await _resolveShareOwnerDisplayName(
                  permission.ownerUserId, ownerNameCache);
              return category.copyWith(sharedOwnerDisplayName: ownerName);
            } catch (e) {
              debugPrint(
                  'getUserCategories - Error loading shared category ${permission.itemId} from ${permission.ownerUserId}: $e');
              return null;
            }
          }());
        }

        if (fetchFutures.isNotEmpty) {
          final results = await Future.wait(fetchFutures);
          final List<UserCategory> fetchedShared = [];
          for (int i = 0; i < results.length; i++) {
            final UserCategory? category = results[i];
            final SharePermission permission = fetchPermissions[i];
            if (category != null) {
              fetchedShared.add(category);
              if (permission.itemId.isNotEmpty) {
                sharedPermissionMap[permission.itemId] = permission;
              }
            }
          }
          sharedCategories = fetchedShared;
          sharedCategories.sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        }
      }
    }

    final Map<String, UserCategory> combined = {};

    void addCategories(List<UserCategory> source) {
      for (final category in source) {
        final key = '${category.ownerUserId}_${category.id}';
        combined.putIfAbsent(key, () => category);
      }
    }

    addCategories(ownedCategories);
    addCategories(sharedCategories);

    final finalCategories = combined.values.toList(growable: false);

    print(
        "getUserCategories END - Returning ${finalCategories.length} categories (owned: ${ownedCategories.length}, shared: ${sharedCategories.length}).");
    return UserCategoryFetchResult(
      categories: finalCategories,
      sharedPermissions: sharedPermissionMap,
    );
  }

  /// Fetches the user's custom categories.
  /// Set [includeSharedEditable] to true to append categories shared with the user that have edit access.
  Future<List<UserCategory>> getUserCategories(
          {bool includeSharedEditable = false}) async =>
      (await getUserCategoriesWithMeta(
              includeSharedEditable: includeSharedEditable))
          .categories;

  /// Initializes the default categories for a user in Firestore.
  /// Note: This should now be called explicitly ONCE during user creation flow.
  Future<List<UserCategory>> initializeDefaultUserCategories(
      String userId) async {
    // Pass userId to createInitialCategories
    final defaultCategories = UserCategory.createInitialCategories(userId);
    // Sort defaults alphabetically before assigning index
    defaultCategories.sort((a, b) => a.name.compareTo(b.name));
    final batch = _firestore.batch();
    final collectionRef = _userCategoriesCollection(userId);
    List<UserCategory> createdCategories = [];

    print("INITIALIZING default categories for user $userId.");

    // UPDATED: Assign sequential orderIndex during initialization
    for (int i = 0; i < defaultCategories.length; i++) {
      final category = defaultCategories[i];
      final docRef = collectionRef.doc();
      final data = category.toMap();
      data['orderIndex'] = i; // Assign index
      batch.set(docRef, data);
      createdCategories.add(UserCategory(
          id: docRef.id,
          name: category.name,
          icon: category.icon,
          ownerUserId: userId,
          orderIndex: i // Include index in returned object
          ));
    }

    try {
      await batch.commit();
      print(
          "Successfully initialized ${createdCategories.length} default categories for user $userId.");
      return createdCategories;
    } catch (e) {
      print("Error during default category initialization batch commit: $e");
      // Don't return potentially partially saved categories
      throw Exception("Failed to initialize default categories: $e");
    }
  }

  /// Adds a new custom category for the current user.
  Future<UserCategory> addUserCategory(
    String name,
    String icon, {
    bool isPrivate = false,
  }) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final categoryRef = _userCategoriesCollection(userId);

    // Optional: Check if a type with the same name already exists
    final existing =
        await categoryRef.where('name', isEqualTo: name).limit(1).get();
    if (existing.docs.isNotEmpty) {
      throw Exception('A category with this name already exists.');
    }

    // ADDED: Determine the next order index
    int nextOrderIndex = 0;
    try {
      final querySnapshot = await categoryRef
          .orderBy('orderIndex', descending: true)
          .limit(1)
          .get();
      if (querySnapshot.docs.isNotEmpty) {
        final lastCategory =
            UserCategory.fromFirestore(querySnapshot.docs.first);
        if (lastCategory.orderIndex != null) {
          nextOrderIndex = lastCategory.orderIndex! + 1;
        }
      }
    } catch (e) {
      print(
          "Warning: Could not determine next orderIndex, defaulting to 0. Error: $e");
      // Default to 0 if query fails or no categories exist yet
    }
    print("Assigning next orderIndex: $nextOrderIndex");

    final data = {
      'name': name,
      'icon': icon,
      'ownerUserId': userId, // Ensure owner ID is stored
      'orderIndex': nextOrderIndex, // Set the order index
      'lastUsedTimestamp': null, // Explicitly null initially
      'isPrivate': isPrivate,
    };
    final docRef = await categoryRef.add(data);
    return UserCategory(
        id: docRef.id,
        name: name,
        icon: icon,
        ownerUserId: userId,
        orderIndex: nextOrderIndex, // Return with index
        lastUsedTimestamp: null,
        isPrivate: isPrivate);
  }

  /// Updates an existing custom category for the current user.
  Future<void> updateUserCategory(UserCategory category) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }
    final targetUserId =
        category.ownerUserId.isNotEmpty ? category.ownerUserId : userId;
    print(
        'ExperienceService.updateUserCategory: currentUser=$userId, targetUserId=$targetUserId, categoryOwner=${category.ownerUserId}, categoryId=${category.id}');
    await _userCategoriesCollection(targetUserId)
        .doc(category.id)
        .update(category.toMap());
  }

  /// Deletes a custom category for the current user.
  Future<void> deleteUserCategory(String categoryId) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }
    // Add check: Ensure the user owns this type?
    await _userCategoriesCollection(userId).doc(categoryId).delete();
    // Consider what happens to Experiences using this type. Reassign? Mark as 'Other'?
  }

  // ADDED: Method to update only the last used timestamp for a category
  Future<void> updateCategoryLastUsedTimestamp(String categoryId) async {
    final userId = _currentUserId;
    if (userId == null) {
      // Decide if this should throw or just return silently
      print("Cannot update category timestamp: User not authenticated");
      return;
      // Alternatively: throw Exception('User not authenticated');
    }
    try {
      await _userCategoriesCollection(userId)
          .doc(categoryId)
          .update({'lastUsedTimestamp': FieldValue.serverTimestamp()});
      print("Updated lastUsedTimestamp for category $categoryId");
    } catch (e) {
      print("Error updating lastUsedTimestamp for category $categoryId: $e");
      // Decide if error should be propagated
      // rethrow;
    }
  }

  // ADDED: Method to update the orderIndex for multiple categories
  Future<void> updateCategoryOrder(
      List<Map<String, dynamic>> categoryOrderUpdates) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }
    if (categoryOrderUpdates.isEmpty) {
      print("No category order updates to perform.");
      return;
    }

    final categoryRef = _userCategoriesCollection(userId);
    final batch = _firestore.batch();
    int updatedCount = 0;

    for (final updateData in categoryOrderUpdates) {
      final categoryId = updateData['id'] as String?;
      final orderIndex = updateData['orderIndex'] as int?;

      if (categoryId != null && orderIndex != null) {
        final docRef = categoryRef.doc(categoryId);
        batch.update(docRef, {'orderIndex': orderIndex});
        updatedCount++;
      } else {
        print(
            "Warning: Skipping invalid category order update data: $updateData");
      }
    }

    if (updatedCount > 0) {
      try {
        await batch.commit();
        print("Successfully updated orderIndex for $updatedCount categories.");
      } catch (e) {
        print("Error committing category order update batch: $e");
        // Consider rethrowing or specific error handling
        throw Exception("Failed to save category order: $e");
      }
    } else {
      print("No valid category order updates found in the provided list.");
    }
  }

  // ======= Public Experience Operations =======
  Future<PublicExperiencePage> fetchPublicExperiencesPage({
    DocumentSnapshot<Object?>? startAfter,
    int limit = 50,
  }) async {
    try {
      Query query = _publicExperiencesCollection
          .orderBy(FieldPath.documentId)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      final experiences = snapshot.docs
          .map((doc) => PublicExperience.fromFirestore(doc))
          .toList();

      final DocumentSnapshot<Object?>? lastDoc =
          snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      final hasMore = snapshot.docs.length == limit;

      return PublicExperiencePage(
        experiences: experiences,
        lastDocument: lastDoc,
        hasMore: hasMore,
      );
    } catch (e, stackTrace) {
      debugPrint(
          'fetchPublicExperiencesPage: Error fetching public experiences: $e');
      debugPrint(stackTrace.toString());
      rethrow;
    }
  }

  /// Finds a single PublicExperience document by its Google Place ID.
  /// Returns null if no matching document is found.
  Future<PublicExperience?> findPublicExperienceByPlaceId(
      String placeId) async {
    if (placeId.isEmpty) {
      print("findPublicExperienceByPlaceId: Provided placeId is empty.");
      return null;
    }
    try {
      print("findPublicExperienceByPlaceId: Searching for placeId: $placeId");
      final snapshot = await _publicExperiencesCollection
          .where('placeID', isEqualTo: placeId)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        print(
            "findPublicExperienceByPlaceId: Found existing public experience with ID: ${doc.id}");
        return PublicExperience.fromFirestore(doc);
      } else {
        print(
            "findPublicExperienceByPlaceId: No existing public experience found for placeId: $placeId");
        return null;
      }
    } catch (e) {
      print("Error finding public experience by placeId '$placeId': $e");
      // Depending on desired behavior, could rethrow or return null
      return null;
    }
  }

  /// Fetches a PublicExperience document directly by its document ID.
  Future<PublicExperience?> findPublicExperienceById(String id) async {
    if (id.isEmpty) {
      debugPrint('findPublicExperienceById: Provided ID is empty.');
      return null;
    }
    try {
      final doc = await _publicExperiencesCollection.doc(id).get();
      if (doc.exists && doc.data() != null) {
        debugPrint(
            'findPublicExperienceById: Found public experience with ID: ${doc.id}');
        return PublicExperience.fromFirestore(doc);
      }
      debugPrint(
          'findPublicExperienceById: No public experience found for ID: $id');
      return null;
    } catch (e, stackTrace) {
      debugPrint(
          'findPublicExperienceById: Error fetching public experience $id: $e');
      debugPrint(stackTrace.toString());
      return null;
    }
  }

  /// Creates a new PublicExperience document in Firestore.
  Future<String?> createPublicExperience(
      PublicExperience publicExperience) async {
    try {
      print(
          "createPublicExperience: Attempting to create public experience for placeId: ${publicExperience.placeID}");
      // We don't store the ID within the document data itself
      final data = publicExperience.toMap();
      // Optionally add created/updated timestamps if needed for public experiences
      // data['createdAt'] = FieldValue.serverTimestamp();
      // data['updatedAt'] = FieldValue.serverTimestamp();

      final docRef = await _publicExperiencesCollection.add(data);
      print(
          "createPublicExperience: Successfully created public experience with ID: ${docRef.id}");
      return docRef.id;
    } catch (e) {
      print(
          "Error creating public experience for placeId '${publicExperience.placeID}': $e");
      return null; // Indicate failure
    }
  }

  /// Adds new media paths to an existing PublicExperience document's allMediaPaths field.
  /// Optionally updates the yelpUrl if it's currently null/empty and a new one is provided.
  /// Uses arrayUnion for media paths to avoid duplicates.
  Future<bool> updatePublicExperienceMediaAndMaybeYelp(
      String publicExperienceId, List<String> newMediaPaths,
      {String? newYelpUrl} // Optional Yelp URL from the card
      ) async {
    if (publicExperienceId.isEmpty) {
      print(
          "updatePublicExperienceMediaAndMaybeYelp: Invalid arguments (ID empty)");
      return false;
    }

    // Prepare the data map for the update operation
    Map<String, dynamic> updateData = {};

    // Always add new media paths if provided
    if (newMediaPaths.isNotEmpty) {
      print(
          "updatePublicExperienceMediaAndMaybeYelp: Preparing to add ${newMediaPaths.length} paths to public experience ID: $publicExperienceId");
      updateData['allMediaPaths'] = FieldValue.arrayUnion(newMediaPaths);
    } else {
      print(
          "updatePublicExperienceMediaAndMaybeYelp: No new media paths provided for public experience ID: $publicExperienceId");
    }

    // Optional: Update updatedAt timestamp
    // updateData['updatedAt'] = FieldValue.serverTimestamp();

    // If there are updates to perform, run the transaction
    if (updateData.isNotEmpty ||
        (newYelpUrl != null && newYelpUrl.isNotEmpty)) {
      try {
        // Use a transaction to safely check the current yelpUrl before updating
        await _firestore.runTransaction((transaction) async {
          final docRef = _publicExperiencesCollection.doc(publicExperienceId);
          final snapshot = await transaction.get(docRef);

          if (!snapshot.exists) {
            print(
                "updatePublicExperienceMediaAndMaybeYelp: Document $publicExperienceId does not exist.");
            throw FirebaseException(
                plugin: 'cloud_firestore', code: 'not-found');
          }

          final currentData = snapshot.data() as Map<String, dynamic>?;
          final currentYelpUrl = currentData?['yelpUrl'] as String?;

          // Conditionally add yelpUrl to the updateData if needed
          if (newYelpUrl != null && newYelpUrl.isNotEmpty) {
            if (currentYelpUrl == null || currentYelpUrl.isEmpty) {
              print(
                  "updatePublicExperienceMediaAndMaybeYelp: Current Yelp URL is empty, updating with new URL: $newYelpUrl");
              updateData['yelpUrl'] = newYelpUrl;
            } else {
              print(
                  "updatePublicExperienceMediaAndMaybeYelp: Current Yelp URL already exists ('$currentYelpUrl'), not overwriting.");
            }
          }

          // Perform the actual update only if there's something to update
          if (updateData.isNotEmpty) {
            print(
                "updatePublicExperienceMediaAndMaybeYelp: Applying updates: ${updateData.keys.join(', ')}");
            transaction.update(docRef, updateData);
          } else {
            print(
                "updatePublicExperienceMediaAndMaybeYelp: No fields needed updating after check.");
          }
        });

        print(
            "updatePublicExperienceMediaAndMaybeYelp: Successfully processed updates for public experience ID: $publicExperienceId");
        return true;
      } catch (e) {
        print(
            "Error updating media/yelp for public experience ID '$publicExperienceId': $e");
        return false; // Indicate failure
      }
    } else {
      print(
          "updatePublicExperienceMediaAndMaybeYelp: No updates to perform for ID: $publicExperienceId");
      return true; // Nothing to do, considered successful
    }
  }

  // ======= Shared Media Item Operations =======

  /// Finds a single SharedMediaItem document by its path.
  /// Returns null if no matching document is found.
  Future<SharedMediaItem?> findSharedMediaItemByPath(String path) async {
    if (path.isEmpty) {
      print("findSharedMediaItemByPath: Provided path is empty.");
      return null;
    }
    try {
      print("findSharedMediaItemByPath: Searching for path: $path");
      final snapshot = await _sharedMediaItemsCollection
          .where('path', isEqualTo: path)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        print(
            "findSharedMediaItemByPath: Found existing item with ID: ${doc.id}");
        return SharedMediaItem.fromFirestore(doc);
      } else {
        print(
            "findSharedMediaItemByPath: No existing item found for path: $path");
        return null;
      }
    } catch (e) {
      print("Error finding shared media item by path '$path': $e");
      return null;
    }
  }

  /// Creates a new SharedMediaItem document in Firestore.
  /// Returns the ID of the newly created document.
  Future<String> createSharedMediaItem(SharedMediaItem item) async {
    try {
      print(
          "createSharedMediaItem: Attempting to create item for path: ${item.path}");
      final data = item.toMap();
      final docRef = await _sharedMediaItemsCollection.add(data);
      print(
          "createSharedMediaItem: Successfully created item with ID: ${docRef.id}");
      return docRef.id;
    } catch (e) {
      print("Error creating shared media item for path '${item.path}': $e");
      throw Exception("Failed to create shared media item: $e");
    }
  }

  Future<void> updateSharedMediaPrivacy(
      String mediaItemId, bool isPrivate) async {
    if (mediaItemId.isEmpty) return;
    try {
      await _sharedMediaItemsCollection
          .doc(mediaItemId)
          .update({'isPrivate': isPrivate});
      debugPrint(
          'updateSharedMediaPrivacy: Set media $mediaItemId isPrivate=$isPrivate');
    } catch (e) {
      debugPrint(
          'updateSharedMediaPrivacy: Failed for $mediaItemId (isPrivate=$isPrivate): $e');
    }
  }

  Future<List<SharedMediaItem>> getSharedMediaItemsByPath(
      String path) async {
    if (path.isEmpty) return [];
    try {
      final snapshot = await _sharedMediaItemsCollection
          .where('path', isEqualTo: path)
          .get();
      return snapshot.docs
          .map((doc) => SharedMediaItem.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('getSharedMediaItemsByPath: Failed for $path: $e');
      return [];
    }
  }

  Future<void> removeMediaPathFromPublicExperienceByPlaceId(
      String placeId, String mediaPath) async {
    if (placeId.isEmpty || mediaPath.isEmpty) return;
    try {
      final publicExperience =
          await findPublicExperienceByPlaceId(placeId);
      if (publicExperience == null) {
        debugPrint(
            'removeMediaPathFromPublicExperienceByPlaceId: No public experience for placeId $placeId');
        return;
      }
      await _publicExperiencesCollection.doc(publicExperience.id).update({
        'allMediaPaths': FieldValue.arrayRemove([mediaPath])
      });
      debugPrint(
          'removeMediaPathFromPublicExperienceByPlaceId: Removed $mediaPath for placeId $placeId');
    } catch (e) {
      debugPrint(
          'removeMediaPathFromPublicExperienceByPlaceId: Failed for placeId $placeId, mediaPath $mediaPath: $e');
    }
  }

  Future<void> addMediaPathToPublicExperienceByPlaceId(
      String placeId, String mediaPath,
      {Experience? experienceTemplate}) async {
    if (placeId.isEmpty || mediaPath.isEmpty) return;
    try {
      final publicExperience =
          await findPublicExperienceByPlaceId(placeId);
      if (publicExperience == null) {
        if (experienceTemplate == null) {
          debugPrint(
              'addMediaPathToPublicExperienceByPlaceId: No public experience for placeId $placeId and no template provided');
          return;
        }
        final newPublicExperience = PublicExperience(
          id: '',
          name: experienceTemplate.name,
          location: experienceTemplate.location,
          placeID: placeId,
          yelpUrl: experienceTemplate.yelpUrl,
          website: experienceTemplate.website,
          allMediaPaths: [mediaPath],
        );
        await createPublicExperience(newPublicExperience);
        debugPrint(
            'addMediaPathToPublicExperienceByPlaceId: Created new public experience for placeId $placeId with mediaPath');
        return;
      }
      await _publicExperiencesCollection.doc(publicExperience.id).update({
        'allMediaPaths': FieldValue.arrayUnion([mediaPath])
      });
      debugPrint(
          'addMediaPathToPublicExperienceByPlaceId: Added $mediaPath for placeId $placeId');
    } catch (e) {
      debugPrint(
          'addMediaPathToPublicExperienceByPlaceId: Failed for placeId $placeId, mediaPath $mediaPath: $e');
    }
  }

  /// Adds an experience ID to the experienceIds array of a SharedMediaItem document.
  Future<void> addExperienceLinkToMediaItem(
      String mediaItemId, String experienceId) async {
    if (mediaItemId.isEmpty || experienceId.isEmpty) {
      print("addExperienceLinkToMediaItem: Invalid arguments.");
      return;
    }
    try {
      print(
          "addExperienceLinkToMediaItem: Linking Experience $experienceId to Media $mediaItemId");
      await _sharedMediaItemsCollection.doc(mediaItemId).update({
        'experienceIds': FieldValue.arrayUnion([experienceId])
      });
    } catch (e) {
      print("Error linking experience $experienceId to media $mediaItemId: $e");
      // Consider rethrowing or specific error handling
    }
  }

  /// Removes an experience ID from the experienceIds array of a SharedMediaItem document.
  /// Optionally deletes the media item if it becomes orphaned (no more links).
  Future<void> removeExperienceLinkFromMediaItem(
      String mediaItemId, String experienceId,
      {bool deleteIfOrphaned = true}) async {
    if (mediaItemId.isEmpty || experienceId.isEmpty) {
      print("removeExperienceLinkFromMediaItem: Invalid arguments.");
      return;
    }
    try {
      print(
          "removeExperienceLinkFromMediaItem: Unlinking Experience $experienceId from Media $mediaItemId");
      final docRef = _sharedMediaItemsCollection.doc(mediaItemId);
      await docRef.update({
        'experienceIds': FieldValue.arrayRemove([experienceId])
      });

      // Also remove the media reference from the Experience document
      try {
        await _experiencesCollection.doc(experienceId).update({
          'sharedMediaItemIds': FieldValue.arrayRemove([mediaItemId])
        });
        print(
            "removeExperienceLinkFromMediaItem: Removed media $mediaItemId from experience $experienceId.sharedMediaItemIds");
      } catch (e) {
        print(
            "removeExperienceLinkFromMediaItem: Warning: failed to update experience $experienceId to remove media $mediaItemId: $e");
      }

      if (deleteIfOrphaned) {
        print(
            "removeExperienceLinkFromMediaItem: Checking if media item $mediaItemId is orphaned.");
        final updatedDoc = await docRef.get();
        if (updatedDoc.exists) {
          final data = updatedDoc.data() as Map<String, dynamic>?;
          final List<String> remainingLinks =
              List<String>.from(data?['experienceIds'] ?? []);
          if (remainingLinks.isEmpty) {
            print(
                "removeExperienceLinkFromMediaItem: Media item $mediaItemId is orphaned. Deleting...");
            await docRef.delete();
          } else {
            print(
                "removeExperienceLinkFromMediaItem: Media item $mediaItemId still has ${remainingLinks.length} links.");
          }
        } else {
          print(
              "removeExperienceLinkFromMediaItem: Media item $mediaItemId not found after update (possibly already deleted?).");
        }
      }
    } catch (e) {
      print(
          "Error unlinking experience $experienceId from media $mediaItemId: $e");
      // Consider rethrowing or specific error handling
    }
  }

  /// Fetches a single SharedMediaItem by its ID.
  Future<SharedMediaItem?> getSharedMediaItem(String mediaItemId) async {
    if (mediaItemId.isEmpty) return null;
    try {
      final doc = await _sharedMediaItemsCollection.doc(mediaItemId).get();
      if (!doc.exists) {
        return null;
      }
      return SharedMediaItem.fromFirestore(doc);
    } catch (e) {
      print("Error fetching shared media item $mediaItemId: $e");
      return null;
    }
  }

  /// Fetches multiple SharedMediaItem documents by their IDs.
  /// Handles Firestore 'in' query limits by chunking.
  Future<List<SharedMediaItem>> getSharedMediaItems(
      List<String> mediaItemIds) async {
    if (mediaItemIds.isEmpty) {
      return [];
    }

    // Deduplicate IDs just in case
    final uniqueIds = mediaItemIds.toSet().toList();

    // Firestore 'in' query limit (currently 30, previously 10)
    const chunkSize = 30;
    // Split into chunks
    final List<List<String>> chunks = [];
    for (int i = 0; i < uniqueIds.length; i += chunkSize) {
      final end = (i + chunkSize) > uniqueIds.length
          ? uniqueIds.length
          : (i + chunkSize);
      final chunk = uniqueIds.sublist(i, end);
      if (chunk.isNotEmpty) {
        chunks.add(chunk);
      }
    }

    // Limit concurrency so we don't overwhelm device or Firestore
    const int maxConcurrent = 6;
    final List<SharedMediaItem> results = [];

    for (int i = 0; i < chunks.length; i += maxConcurrent) {
      final batch = chunks.sublist(
          i,
          (i + maxConcurrent) > chunks.length
              ? chunks.length
              : (i + maxConcurrent));
      final futures = batch.map((chunk) async {
        try {
          final snapshot = await _sharedMediaItemsCollection
              .where(FieldPath.documentId, whereIn: chunk)
              .get();
          return snapshot.docs
              .map((doc) => SharedMediaItem.fromFirestore(doc))
              .toList();
        } catch (e) {
          print("Error fetching shared media items chunk: $e");
          return <SharedMediaItem>[];
        }
      }).toList();

      final batchResults = await Future.wait(futures);
      for (final r in batchResults) {
        results.addAll(r);
      }
    }

    return results;
  }

  /// Deletes a SharedMediaItem and removes its ID from all linked Experiences.
  /// This operation is performed atomically using a batch write.
  Future<void> deleteSharedMediaItemAndUnlink(
      String mediaItemId, List<String> experienceIds) async {
    if (mediaItemId.isEmpty) {
      throw ArgumentError("mediaItemId cannot be empty.");
    }

    print(
        "Attempting to delete SharedMediaItem $mediaItemId and unlink from ${experienceIds.length} experiences.");

    final batch = _firestore.batch();

    // 1. Add delete operation for the SharedMediaItem
    final mediaItemRef = _sharedMediaItemsCollection.doc(mediaItemId);
    batch.delete(mediaItemRef);
    print("  - Added delete operation for MediaItem $mediaItemId to batch.");

    // 2. Add update operations for each linked Experience
    if (experienceIds.isNotEmpty) {
      for (final experienceId in experienceIds) {
        if (experienceId.isNotEmpty) {
          final experienceRef = _experiencesCollection.doc(experienceId);
          batch.update(experienceRef, {
            'sharedMediaItemIds': FieldValue.arrayRemove([mediaItemId])
          });
          print(
              "  - Added unlink operation from Experience $experienceId for MediaItem $mediaItemId to batch.");
        } else {
          print(
              "Warning: Skipping unlink operation for an empty experienceId linked to MediaItem $mediaItemId.");
        }
      }
    } else {
      print(
          "Warning: No experience IDs provided for unlinking MediaItem $mediaItemId. It will still be deleted.");
    }

    // 3. Commit the batch
    try {
      await batch.commit();
      print(
          "Successfully deleted MediaItem $mediaItemId and unlinked from experiences.");
    } catch (e) {
      print(
          "Error committing batch delete/unlink for MediaItem $mediaItemId: $e");
      // Rethrow the exception to allow the caller to handle it (e.g., show error message)
      rethrow;
    }
  }

  /// Updates the media IDs and optionally the Yelp URL for a PublicExperience.
  /// Merges the new media item IDs with existing ones.
  Future<bool> updatePublicExperienceMediaIds(
      String publicExperienceId, List<String> newMediaItemIds,
      {String? newYelpUrl}) async {
    if (publicExperienceId.isEmpty) {
      print("updatePublicExperienceMediaIds: Invalid arguments (ID empty)");
      return false;
    }

    Map<String, dynamic> updateData = {};

    // Always add new media item IDs if provided
    if (newMediaItemIds.isNotEmpty) {
      print(
          "updatePublicExperienceMediaIds: Preparing to add ${newMediaItemIds.length} media IDs to public experience ID: $publicExperienceId");
      // Use arrayUnion to merge IDs
      updateData['sharedMediaItemIds'] = FieldValue.arrayUnion(newMediaItemIds);
    } else {
      print(
          "updatePublicExperienceMediaIds: No new media item IDs provided for ID: $publicExperienceId");
    }

    if (updateData.isNotEmpty ||
        (newYelpUrl != null && newYelpUrl.isNotEmpty)) {
      try {
        await _firestore.runTransaction((transaction) async {
          final docRef = _publicExperiencesCollection.doc(publicExperienceId);
          final snapshot = await transaction.get(docRef);

          if (!snapshot.exists) {
            print(
                "updatePublicExperienceMediaIds: Document $publicExperienceId does not exist.");
            throw FirebaseException(
                plugin: 'cloud_firestore', code: 'not-found');
          }

          final currentData = snapshot.data() as Map<String, dynamic>?;
          final currentYelpUrl = currentData?['yelpUrl'] as String?;

          // Conditionally add yelpUrl update
          if (newYelpUrl != null && newYelpUrl.isNotEmpty) {
            if (currentYelpUrl == null || currentYelpUrl.isEmpty) {
              print(
                  "updatePublicExperienceMediaIds: Current Yelp URL is empty, updating with new URL: $newYelpUrl");
              updateData['yelpUrl'] = newYelpUrl;
            } else {
              print(
                  "updatePublicExperienceMediaIds: Current Yelp URL already exists ('$currentYelpUrl'), not overwriting.");
            }
          }

          if (updateData.isNotEmpty) {
            print(
                "updatePublicExperienceMediaIds: Applying updates: ${updateData.keys.join(', ')}");
            transaction.update(docRef, updateData);
          } else {
            print(
                "updatePublicExperienceMediaIds: No fields needed updating after check.");
          }
        });
        print(
            "updatePublicExperienceMediaIds: Successfully processed updates for ID: $publicExperienceId");
        return true;
      } catch (e) {
        print(
            "Error updating media/yelp for public experience ID '$publicExperienceId': $e");
        return false;
      }
    } else {
      print(
          "updatePublicExperienceMediaIds: No updates to perform for ID: $publicExperienceId");
      return true;
    }
  }

  // ======= Experience CRUD Operations =======

  /// Get all users who have access to an experience via category shares
  /// This denormalizes share permissions to populate sharedWithUserIds
  Future<List<String>> _getUsersWithCategoryAccess(
      Experience experience) async {
    final String? ownerUserId = experience.createdBy ?? _currentUserId;
    if (ownerUserId == null || ownerUserId.isEmpty) {
      return [];
    }

    final Set<String> sharedUserIds = {};
    final Set<String> categoriesToCheck = {};

    // Collect all category IDs to check
    if (experience.categoryId != null && experience.categoryId!.isNotEmpty) {
      categoriesToCheck.add(experience.categoryId!);
    }
    categoriesToCheck.addAll(experience.otherCategories);
    categoriesToCheck.addAll(experience.otherColorCategoryIds);
    if (experience.colorCategoryId != null &&
        experience.colorCategoryId!.isNotEmpty) {
      categoriesToCheck.add(experience.colorCategoryId!);
    }

    // For each category, find users who have share access
    for (final categoryId in categoriesToCheck) {
      try {
        final shareSnapshot = await _sharePermissionsCollection
            .where('itemType', isEqualTo: 'category')
            .where('itemId', isEqualTo: categoryId)
            .where('ownerUserId', isEqualTo: ownerUserId)
            .get();

        for (final doc in shareSnapshot.docs) {
          final data = doc.data() as Map<String, dynamic>?;
          final sharedWithUserId = data?['sharedWithUserId'] as String?;
          if (sharedWithUserId != null && sharedWithUserId.isNotEmpty) {
            sharedUserIds.add(sharedWithUserId);
          }
        }
      } catch (e) {
        debugPrint(
            '_getUsersWithCategoryAccess: Error checking category $categoryId: $e');
      }
    }

    return sharedUserIds.toList();
  }

  /// Update sharedWithUserIds for all experiences in a specific category
  /// This should be called when a new category share is granted
  /// NOTE: Cloud Functions (onCategoryShareCreated) now handle this automatically.
  /// This method serves as a backup for manual triggers or if functions fail.
  Future<int> updateSharedUserIdsForCategory(String categoryId,
      {int batchSize = 50}) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    int updatedCount = 0;

    try {
      // Query all experiences that have this category as primary, other, or color category
      // We need to do three separate queries and combine results
      final Set<String> experienceIds = {};

      // Query by primary categoryId
      final primarySnapshot = await _experiencesCollection
          .where('createdBy', isEqualTo: currentUserId)
          .where('categoryId', isEqualTo: categoryId)
          .get();
      experienceIds.addAll(primarySnapshot.docs.map((d) => d.id));

      // Query by otherCategories (array-contains)
      final otherSnapshot = await _experiencesCollection
          .where('createdBy', isEqualTo: currentUserId)
          .where('otherCategories', arrayContains: categoryId)
          .get();
      experienceIds.addAll(otherSnapshot.docs.map((d) => d.id));

      // Query by colorCategoryId
      final colorSnapshot = await _experiencesCollection
          .where('createdBy', isEqualTo: currentUserId)
          .where('colorCategoryId', isEqualTo: categoryId)
          .get();
      experienceIds.addAll(colorSnapshot.docs.map((d) => d.id));
      // Query by otherColorCategoryIds (array-contains)
      final otherColorSnapshot = await _experiencesCollection
          .where('createdBy', isEqualTo: currentUserId)
          .where('otherColorCategoryIds', arrayContains: categoryId)
          .get();
      experienceIds.addAll(otherColorSnapshot.docs.map((d) => d.id));

      debugPrint(
          'updateSharedUserIdsForCategory: Found ${experienceIds.length} experiences for category $categoryId');

      if (experienceIds.isEmpty) {
        return 0;
      }

      // Process in batches
      WriteBatch batch = _firestore.batch();
      int batchCount = 0;

      for (final experienceId in experienceIds) {
        final doc = await _experiencesCollection.doc(experienceId).get();
        if (!doc.exists) continue;

        final experience = Experience.fromFirestore(doc);
        final sharedUserIds = await _getUsersWithCategoryAccess(experience);

        // Update the experience with new sharedWithUserIds
        batch.update(doc.reference, {'sharedWithUserIds': sharedUserIds});
        batchCount++;
        updatedCount++;

        debugPrint(
            '  Updating experience "${experience.name}" with ${sharedUserIds.length} shared users');

        // Commit batch if it reaches the size limit
        if (batchCount >= batchSize) {
          await batch.commit();
          // IMPORTANT: create a fresh batch after committing
          batch = _firestore.batch();
          batchCount = 0;
        }
      }

      // Commit any remaining updates
      if (batchCount > 0) {
        await batch.commit();
      }

      debugPrint(
          'updateSharedUserIdsForCategory: Updated $updatedCount experiences');
      return updatedCount;
    } catch (e) {
      debugPrint('updateSharedUserIdsForCategory: Error: $e');
      rethrow;
    }
  }

  /// Backfill sharedWithUserIds for existing experiences in shared categories
  /// Call this once to fix existing data (can be triggered manually or via admin panel)
  /// NOTE: The Cloud Function backfillSharedUserIds (HTTP endpoint) handles this more efficiently.
  /// This method serves as a client-side alternative for small-scale backfills.
  Future<int> backfillSharedUserIdsForExperiences({int batchSize = 50}) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    int updatedCount = 0;

    try {
      // Get all experiences created by this user
      final snapshot = await _experiencesCollection
          .where('createdBy', isEqualTo: currentUserId)
          .get();

      debugPrint(
          'backfillSharedUserIds: Processing ${snapshot.docs.length} experiences');

      // Process in batches
      WriteBatch batch = _firestore.batch();
      int batchCount = 0;

      for (final doc in snapshot.docs) {
        final experience = Experience.fromFirestore(doc);
        final sharedUserIds = await _getUsersWithCategoryAccess(experience);

        // Only update if there are shared users
        if (sharedUserIds.isNotEmpty) {
          batch.update(doc.reference, {'sharedWithUserIds': sharedUserIds});
          batchCount++;
          updatedCount++;

          debugPrint(
              '  Backfilling experience "${experience.name}" with ${sharedUserIds.length} shared users');

          // Commit batch if it reaches the size limit
          if (batchCount >= batchSize) {
            await batch.commit();
            // IMPORTANT: create a fresh batch after committing
            batch = _firestore.batch();
            batchCount = 0;
          }
        }
      }

      // Commit any remaining updates
      if (batchCount > 0) {
        await batch.commit();
      }

      debugPrint('backfillSharedUserIds: Updated $updatedCount experiences');
      return updatedCount;
    } catch (e) {
      debugPrint('backfillSharedUserIds: Error: $e');
      rethrow;
    }
  }

  /// Create a new experience
  Future<String> createExperience(Experience experience) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    // Prepare data with server timestamps
    final now = FieldValue.serverTimestamp();
    final data = experience.toMap();
    data['createdAt'] = now;
    data['updatedAt'] = now;
    data['createdBy'] = _currentUserId;

    // Denormalize share permissions: populate sharedWithUserIds based on category shares
    final sharedUserIds = await _getUsersWithCategoryAccess(experience);
    if (sharedUserIds.isNotEmpty) {
      data['sharedWithUserIds'] = sharedUserIds;
      debugPrint('createExperience: Adding sharedWithUserIds: $sharedUserIds');
    }

    // Add the experience to Firestore
    final docRef = await _experiencesCollection.add(data);
    debugPrint(
        'createExperience: Created experience ${docRef.id} with ${sharedUserIds.length} shared users');
    return docRef.id;
  }

  /// Get an experience by ID
  Future<Experience?> getExperience(String experienceId,
      {bool forceServerFetch = false}) async {
    final GetOptions? options =
        forceServerFetch ? GetOptions(source: Source.server) : null;
    final doc = options != null
        ? await _experiencesCollection.doc(experienceId).get(options)
        : await _experiencesCollection.doc(experienceId).get();
    if (!doc.exists) {
      return null;
    }
    return Experience.fromFirestore(doc);
  }

  /// Finds an experience for the current user (owned or with edit access)
  /// that matches the provided Google Place ID.
  Future<Experience?> findEditableExperienceByPlaceId(String? placeId) async {
    final String? userId = _currentUserId;
    if (userId == null || placeId == null || placeId.isEmpty) {
      return null;
    }

    try {
      final querySnapshot = await _experiencesCollection
          .where('location.placeId', isEqualTo: placeId)
          .limit(25)
          .get();

      for (final doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final String? createdBy = data['createdBy'] as String?;
        final List<dynamic>? editors = data['editorUserIds'] as List<dynamic>?;
        final bool isOwner = createdBy != null && createdBy == userId;
        final bool hasEditAccess =
            editors != null && editors.contains(userId);
        if (isOwner || hasEditAccess) {
          return Experience.fromFirestore(doc);
        }
      }
    } catch (e) {
      debugPrint(
          'findEditableExperienceByPlaceId: Error fetching experiences for placeId $placeId: $e');
    }
    return null;
  }

  Future<List<Experience>> findEditableExperiencesByPlaceId(
      String? placeId) async {
    final String? userId = _currentUserId;
    if (userId == null || placeId == null || placeId.isEmpty) {
      return [];
    }

    try {
      final querySnapshot = await _experiencesCollection
          .where('location.placeId', isEqualTo: placeId)
          .limit(50)
          .get();

      final List<Experience> results = [];
      for (final doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final String? createdBy = data['createdBy'] as String?;
        final List<dynamic>? editors = data['editorUserIds'] as List<dynamic>?;
        final bool isOwner = createdBy != null && createdBy == userId;
        final bool hasEditAccess =
            editors != null && editors.contains(userId);
        if (isOwner || hasEditAccess) {
          results.add(Experience.fromFirestore(doc));
        }
      }
      return results;
    } catch (e) {
      debugPrint(
          'findEditableExperiencesByPlaceId: Error fetching experiences for placeId $placeId: $e');
    }
    return [];
  }

  Future<List<Experience>> findAccessibleExperiencesByPlaceId(
      String? placeId) async {
    final String? userId = _currentUserId;
    if (userId == null || placeId == null || placeId.isEmpty) {
      return [];
    }

    try {
      final querySnapshot = await _experiencesCollection
          .where('location.placeId', isEqualTo: placeId)
          .limit(50)
          .get();

      final List<Experience> results = [];
      for (final doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final String? createdBy = data['createdBy'] as String?;
        final List<dynamic>? editors = data['editorUserIds'] as List<dynamic>?;
        final List<dynamic>? sharedWith =
            data['sharedWithUserIds'] as List<dynamic>?;
        final bool isOwner = createdBy != null && createdBy == userId;
        final bool hasEditAccess =
            editors != null && editors.contains(userId);
        final bool hasViewAccess =
            sharedWith != null && sharedWith.contains(userId);
        if (isOwner || hasEditAccess || hasViewAccess) {
          results.add(Experience.fromFirestore(doc));
        }
      }
      return results;
    } catch (e) {
      debugPrint(
          'findAccessibleExperiencesByPlaceId: Error fetching experiences for placeId $placeId: $e');
    }
    return [];
  }

  /// Update an existing experience
  Future<void> updateExperience(Experience experience) async {
    // DEBUG: First, read the existing experience to check old category
    String? oldCategoryId;
    try {
      final existingDoc = await _experiencesCollection.doc(experience.id).get();
      if (existingDoc.exists) {
        final existingData = existingDoc.data() as Map<String, dynamic>?;
        oldCategoryId = existingData?['categoryId'] as String?;
        debugPrint(
            'updateExperience: OLD categoryId in Firestore: $oldCategoryId');
      }
    } catch (e) {
      debugPrint('updateExperience: Error reading existing experience: $e');
    }

    final data = experience.toMap();
    data['updatedAt'] = FieldValue.serverTimestamp();
    // Ensure createdBy persists for security rules; default to the signed-in user if missing.
    final createdBy = experience.createdBy ?? _currentUserId;
    if (createdBy != null) {
      data['createdBy'] = createdBy;
    }

    // Denormalize share permissions: update sharedWithUserIds based on current category shares
    final sharedUserIds = await _getUsersWithCategoryAccess(experience);
    data['sharedWithUserIds'] =
        sharedUserIds; // Always set it (empty array if no shares)
    debugPrint(
        'updateExperience: Updating sharedWithUserIds to: $sharedUserIds');

    // DEBUG: Log key fields being sent
    debugPrint('updateExperience DEBUG:');
    debugPrint('  - experienceId: ${experience.id}');
    debugPrint('  - createdBy: $createdBy');
    debugPrint('  - currentUserId: $_currentUserId');
    debugPrint('  - NEW categoryId: ${experience.categoryId}');
    debugPrint('  - OLD categoryId: $oldCategoryId');
    debugPrint('  - location keys: ${data['location']?.keys.toList()}');

    // DEBUG: Check if permission exists for the NEW category
    if (experience.categoryId != null &&
        createdBy != null &&
        _currentUserId != null &&
        createdBy != _currentUserId) {
      final permId =
          '${createdBy}_category_${experience.categoryId}_$_currentUserId';
      debugPrint('  - Checking NEW category permission doc: $permId');
      try {
        final permDoc = await _sharePermissionsCollection.doc(permId).get();
        debugPrint('  - NEW category permission exists: ${permDoc.exists}');
        if (permDoc.exists) {
          final permData = permDoc.data() as Map<String, dynamic>?;
          debugPrint(
              '  - NEW category permission accessLevel: ${permData?['accessLevel']}');
        }
      } catch (e) {
        debugPrint('  - Error checking NEW category permission: $e');
      }
    }

    // DEBUG: Check if permission exists for the OLD category
    if (oldCategoryId != null &&
        createdBy != null &&
        _currentUserId != null &&
        createdBy != _currentUserId) {
      final permId = '${createdBy}_category_${oldCategoryId}_$_currentUserId';
      debugPrint('  - Checking OLD category permission doc: $permId');
      try {
        final permDoc = await _sharePermissionsCollection.doc(permId).get();
        debugPrint('  - OLD category permission exists: ${permDoc.exists}');
        if (permDoc.exists) {
          final permData = permDoc.data() as Map<String, dynamic>?;
          debugPrint(
              '  - OLD category permission accessLevel: ${permData?['accessLevel']}');
        }
      } catch (e) {
        debugPrint('  - Error checking OLD category permission: $e');
      }
    }

    await _experiencesCollection.doc(experience.id).update(data);
  }

  /// Delete an experience
  Future<void> deleteExperience(String experienceId) async {
    // Before deleting, unlink this experience from any shared media items
    try {
      final expDoc = await _experiencesCollection.doc(experienceId).get();
      if (expDoc.exists) {
        final data = expDoc.data() as Map<String, dynamic>?;
        final List<String> mediaItemIds = List<String>.from(
          (data?['sharedMediaItemIds'] as List<dynamic>?)
                  ?.whereType<String>()
                  .toList() ??
              [],
        );

        if (mediaItemIds.isNotEmpty) {
          // Use existing helper to remove link and delete orphaned media
          await Future.wait(mediaItemIds.map((mediaId) =>
              removeExperienceLinkFromMediaItem(mediaId, experienceId,
                  deleteIfOrphaned: true)));
        } else {
          // Fallback: query by arrayContains in case sharedMediaItemIds wasn't populated
          final querySnap = await _sharedMediaItemsCollection
              .where('experienceIds', arrayContains: experienceId)
              .get();
          if (querySnap.docs.isNotEmpty) {
            await Future.wait(querySnap.docs.map((doc) =>
                removeExperienceLinkFromMediaItem(doc.id, experienceId,
                    deleteIfOrphaned: true)));
          }
        }
      }
    } catch (e) {
      print(
          "deleteExperience: Error unlinking shared media for experience $experienceId: $e");
      // Proceed with deletion even if unlinking has partial failures
    }

    // Delete the experience document itself
    await _experiencesCollection.doc(experienceId).delete();

    // Optional: Also delete related reviews, comments, and reels
    // This could be done with a batch or with cloud functions for larger datasets
  }

  /// Get all experiences
  Future<List<Experience>> getAllExperiences({int limit = 20}) async {
    final snapshot = await _experiencesCollection
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs.map((doc) => Experience.fromFirestore(doc)).toList();
  }

  /// Get experiences by user category ID
  /// If the category is shared with the current user, this will fetch all experiences
  /// from the owner's category, including newly added ones.
  Future<List<Experience>> getExperiencesByUserCategoryId(String categoryId,
      {int limit = 100}) async {
    if (categoryId.isEmpty) return [];

    // Check if this category is shared with the current user
    final ownerUserId = await _getCategoryShareOwner(categoryId);

    // If it's a shared category, fetch all experiences from the owner's category
    if (ownerUserId != null && ownerUserId.isNotEmpty) {
      debugPrint(
          'getExperiencesByUserCategoryId: Category $categoryId is shared from owner $ownerUserId. Fetching owner\'s experiences.');
      return getExperiencesForOwnerCategory(
        ownerUserId: ownerUserId,
        categoryId: categoryId,
        isColorCategory: false,
        limitPerQuery: limit,
      );
    }

    // Otherwise, fetch experiences normally (for owned categories)
    final snapshot = await _experiencesCollection
        .where('categoryId', isEqualTo: categoryId)
        .limit(limit)
        .get();
    return snapshot.docs.map((doc) => Experience.fromFirestore(doc)).toList();
  }

  /// Get all experiences linked to a user category, including primary categoryId
  /// and entries where the category is present in otherCategories array.
  /// If the category is shared with the current user, this will fetch all experiences
  /// from the owner's category, including newly added ones.
  Future<List<Experience>> getExperiencesByUserCategoryAll(String categoryId,
      {int limitPerQuery = 100}) async {
    if (categoryId.isEmpty) return [];

    // Check if this category is shared with the current user
    final ownerUserId = await _getCategoryShareOwner(categoryId);

    // If it's a shared category, fetch all experiences from the owner's category
    if (ownerUserId != null && ownerUserId.isNotEmpty) {
      debugPrint(
          'getExperiencesByUserCategoryAll: Category $categoryId is shared from owner $ownerUserId. Fetching owner\'s experiences.');
      return getExperiencesForOwnerCategory(
        ownerUserId: ownerUserId,
        categoryId: categoryId,
        isColorCategory: false,
        limitPerQuery: limitPerQuery,
      );
    }

    // Otherwise, fetch experiences normally (for owned categories)
    final futures = await Future.wait([
      _experiencesCollection
          .where('categoryId', isEqualTo: categoryId)
          .limit(limitPerQuery)
          .get(),
      _experiencesCollection
          .where('otherCategories', arrayContains: categoryId)
          .limit(limitPerQuery)
          .get(),
    ]);
    final List<Experience> results = [];
    final Set<String> seen = {};
    for (final snap in futures) {
      for (final doc in snap.docs) {
        final exp = Experience.fromFirestore(doc);
        if (!seen.contains(exp.id)) {
          seen.add(exp.id);
          results.add(exp);
        }
      }
    }
    return results;
  }

  Future<List<Experience>> getExperiencesForOwnerCategory({
    required String ownerUserId,
    required String categoryId,
    required bool isColorCategory,
    int limitPerQuery = 500,
  }) async {
    if (ownerUserId.isEmpty || categoryId.isEmpty) {
      return const <Experience>[];
    }
    try {
      final String? viewerUserId = _currentUserId;
      final bool isOwnerViewing =
          viewerUserId != null && viewerUserId == ownerUserId;

      if (isColorCategory) {
        if (isOwnerViewing) {
          final futures = await Future.wait([
            _experiencesCollection
                .where('createdBy', isEqualTo: ownerUserId)
                .where('colorCategoryId', isEqualTo: categoryId)
                .limit(limitPerQuery)
                .get(),
            _experiencesCollection
                .where('createdBy', isEqualTo: ownerUserId)
                .where('otherColorCategoryIds', arrayContains: categoryId)
                .limit(limitPerQuery)
                .get(),
          ]);
          final Set<String> seen = {};
          final List<Experience> experiences = [];
          for (final snapshot in futures) {
            for (final doc in snapshot.docs) {
              if (seen.add(doc.id)) {
                experiences.add(Experience.fromFirestore(doc));
              }
            }
          }
          debugPrint(
              'getExperiencesForOwnerCategory: Fetched ${experiences.length} experiences for color category $categoryId (${isOwnerViewing ? 'owner-view' : 'shared-view'})');
          return experiences;
        } else {
          final Map<String, Experience> byId = {};
          try {
            final Query colorQuery = _experiencesCollection
                .where('sharedWithUserIds', arrayContains: viewerUserId)
                .where('colorCategoryId', isEqualTo: categoryId)
                .limit(limitPerQuery);
            final colorSnap = await colorQuery.get();
            for (final doc in colorSnap.docs) {
              byId[doc.id] = Experience.fromFirestore(doc);
            }
          } catch (e) {
            debugPrint(
                'getExperiencesForOwnerCategory: color-specific shared query denied, fallback to broad filter. Error: $e');
          }

          try {
            final broadSnap = await _experiencesCollection
                .where('sharedWithUserIds', arrayContains: viewerUserId)
                .limit(limitPerQuery)
                .get();
            for (final doc in broadSnap.docs) {
              final exp = Experience.fromFirestore(doc);
              final bool matchesPrimary =
                  exp.colorCategoryId != null && exp.colorCategoryId == categoryId;
              final bool matchesOther =
                  exp.otherColorCategoryIds.contains(categoryId);
              if (matchesPrimary || matchesOther) {
                byId.putIfAbsent(exp.id, () => exp);
              }
            }
          } catch (e) {
            debugPrint(
                'getExperiencesForOwnerCategory: broad sharedWith fallback for color categories failed: $e');
          }
          return byId.values.toList();
        }
      }
      List<Experience> results = [];
      if (isOwnerViewing) {
        final Query basePrimary = _experiencesCollection
            .where('createdBy', isEqualTo: ownerUserId)
            .where('categoryId', isEqualTo: categoryId)
            .limit(limitPerQuery);
        final Query baseOther = _experiencesCollection
            .where('createdBy', isEqualTo: ownerUserId)
            .where('otherCategories', arrayContains: categoryId)
            .limit(limitPerQuery);

        final futures = await Future.wait([
          basePrimary.get(),
          baseOther.get(),
        ]);
        final Set<String> seen = <String>{};
        for (final snapshot in futures) {
          for (final doc in snapshot.docs) {
            final experience = Experience.fromFirestore(doc);
            if (seen.add(experience.id)) {
              results.add(experience);
            }
          }
        }
      } else {
        // Non-owner viewer: Avoid multiple array-contains combos that violate Firestore constraints or rules
        // Try the tighter query first; if permission-denied, fall back to a single array-contains and filter client-side
        final Map<String, Experience> byId = {};
        try {
          final Query primaryQuery = _experiencesCollection
              .where('sharedWithUserIds', arrayContains: viewerUserId)
              .where('categoryId', isEqualTo: categoryId)
              .limit(limitPerQuery);
          final primarySnap = await primaryQuery.get();
          for (final d in primarySnap.docs) {
            byId[d.id] = Experience.fromFirestore(d);
          }
        } catch (e) {
          debugPrint(
              'getExperiencesForOwnerCategory: primary query denied, falling back to broad+filter. Error: $e');
        }

        // Broad fetch using single array-contains, then filter in-memory
        try {
          final broadSnap = await _experiencesCollection
              .where('sharedWithUserIds', arrayContains: viewerUserId)
              .limit(limitPerQuery)
              .get();
          for (final d in broadSnap.docs) {
            final exp = Experience.fromFirestore(d);
            final bool matchesPrimary =
                exp.categoryId != null && exp.categoryId == categoryId;
            final bool matchesOther = exp.otherCategories.contains(categoryId);
            if ((matchesPrimary || matchesOther)) {
              byId.putIfAbsent(exp.id, () => exp);
            }
          }
        } catch (e) {
          debugPrint(
              'getExperiencesForOwnerCategory: broad sharedWith fallback failed: $e');
        }

        results = byId.values.toList();
      }
      debugPrint(
          'getExperiencesForOwnerCategory: Fetched ${results.length} experiences for user category $categoryId (${isOwnerViewing ? 'owner-view' : 'shared-view'})');
      if (results.isNotEmpty) {
        debugPrint(
            '  Sample experiences: ${results.take(3).map((e) => e.name).join(", ")}');
      }
      return results;
    } catch (e) {
      debugPrint(
          'ExperienceService.getExperiencesForOwnerCategory: Failed to fetch experiences for $ownerUserId/$categoryId: $e');
      return const <Experience>[];
    }
  }

  /// Get experiences by color category ID
  /// If the category is shared with the current user, this will fetch all experiences
  /// from the owner's category, including newly added ones.
  Future<List<Experience>> getExperiencesByColorCategoryId(
      String colorCategoryId,
      {int limit = 100}) async {
    if (colorCategoryId.isEmpty) return [];

    // Check if this color category is shared with the current user
    final ownerUserId = await _getCategoryShareOwner(colorCategoryId);

    // If it's a shared category, fetch all experiences from the owner's category
    if (ownerUserId != null && ownerUserId.isNotEmpty) {
      debugPrint(
          'getExperiencesByColorCategoryId: Color category $colorCategoryId is shared from owner $ownerUserId. Fetching owner\'s experiences.');
      return getExperiencesForOwnerCategory(
        ownerUserId: ownerUserId,
        categoryId: colorCategoryId,
        isColorCategory: true,
        limitPerQuery: limit,
      );
    }

    // Otherwise, fetch experiences normally (for owned categories)
    final futures = await Future.wait([
      _experiencesCollection
          .where('colorCategoryId', isEqualTo: colorCategoryId)
          .limit(limit)
          .get(),
      _experiencesCollection
          .where('otherColorCategoryIds', arrayContains: colorCategoryId)
          .limit(limit)
          .get(),
    ]);
    final List<Experience> results = [];
    final Set<String> seen = {};
    for (final snapshot in futures) {
      for (final doc in snapshot.docs) {
        if (seen.add(doc.id)) {
          results.add(Experience.fromFirestore(doc));
        }
      }
    }
    return results;
  }

  /// Get experiences by category
  Future<List<Experience>> getExperiencesByCategory(
    String categoryName, {
    int limit = 20,
  }) async {
    final snapshot = await _experiencesCollection
        .where('category', isEqualTo: categoryName)
        .limit(limit)
        .get();

    return snapshot.docs.map((doc) => Experience.fromFirestore(doc)).toList();
  }

  /// Get experiences by category name without ordering (index-free)
  Future<List<Experience>> getExperiencesByCategoryNameUnordered(
      String categoryName,
      {int limit = 100}) async {
    if (categoryName.isEmpty) return [];
    final snapshot = await _experiencesCollection
        .where('category', isEqualTo: categoryName)
        .limit(limit)
        .get();
    return snapshot.docs.map((doc) => Experience.fromFirestore(doc)).toList();
  }

  /// Search for experiences
  Future<List<Experience>> searchExperiences(
    String query, {
    int limit = 20,
  }) async {
    // Basic implementation - can be expanded with more sophisticated search
    final queryLower = query.toLowerCase();

    final snapshot = await _experiencesCollection
        .orderBy('name')
        .startAt([queryLower])
        .endAt(['$queryLower\uf8ff'])
        .limit(limit)
        .get();

    return snapshot.docs.map((doc) => Experience.fromFirestore(doc)).toList();
  }

  /// Get experiences created by a specific user
  Future<List<Experience>> getExperiencesByUser(String userId,
      {int limit = 50, GetOptions? options}) async {
    Query query = _experiencesCollection
        .where('createdBy', isEqualTo: userId)
        .orderBy('createdAt', descending: true);
    if (limit > 0) {
      query = query.limit(limit);
    }

    final snapshot = await query.get(options);

    return snapshot.docs.map((doc) => Experience.fromFirestore(doc)).toList();
  }

  /// Page experiences shared with a specific user, using denormalized sharedWithUserIds.
  /// Returns both items and the last DocumentSnapshot for pagination.
  /// Supports different sort orders via orderByField and descending parameters.
  Future<(List<Experience>, DocumentSnapshot<Object?>?)>
      getExperiencesSharedWith(
    String userId, {
    int limit = 200,
    DocumentSnapshot<Object?>? startAfter,
    String orderByField = 'updatedAt',
    bool descending = true,
  }) async {
    if (userId.isEmpty) return (<Experience>[], null);

    Query query = _experiencesCollection
        .where('sharedWithUserIds', arrayContains: userId)
        .orderBy(orderByField, descending: descending)
        .limit(limit);
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    final snap = await query.get();
    final items = snap.docs.map((d) => Experience.fromFirestore(d)).toList();
    final last = snap.docs.isNotEmpty ? snap.docs.last : null;
    return (items, last);
  }

  /// Get multiple experiences by their document IDs (handles Firestore whereIn limits)
  Future<List<Experience>> getExperiencesByIds(List<String> experienceIds,
      {int chunkSize = 30}) async {
    if (experienceIds.isEmpty) {
      return [];
    }

    final List<String> uniqueIds = experienceIds.toSet().toList();

    // Decide strategy: probe a single whereIn to see if rules allow query-based access.
    // If the probe fails with permission-denied, skip whereIn entirely and do per-doc with concurrency.
    bool canUseWhereIn = true;
    final List<Experience> accumulated = [];

    // Prepare chunks upfront for potential whereIn path
    final List<List<String>> chunks = [];
    for (int i = 0; i < uniqueIds.length; i += chunkSize) {
      final end = (i + chunkSize) > uniqueIds.length
          ? uniqueIds.length
          : (i + chunkSize);
      chunks.add(uniqueIds.sublist(i, end));
    }

    if (chunks.isNotEmpty) {
      final List<String> probeChunk = chunks.first;
      try {
        final probeSnap = await _experiencesCollection
            .where(FieldPath.documentId, whereIn: probeChunk)
            .get();
        accumulated
            .addAll(probeSnap.docs.map((doc) => Experience.fromFirestore(doc)));
      } catch (e) {
        // Prefer structured check when possible
        if (e is FirebaseException && e.code == 'permission-denied') {
          canUseWhereIn = false;
        } else {
          final errText = e.toString().toLowerCase();
          if (errText.contains('permission-denied')) {
            canUseWhereIn = false;
          }
        }
        if (!canUseWhereIn) {
          debugPrint(
              'getExperiencesByIds: whereIn probe denied by rules. Switching to concurrent per-doc reads.');
        }
      }
    }

    if (!canUseWhereIn) {
      // Fast path: concurrent per-doc reads with a safe parallelism cap
      const int perDocParallel = 12; // tune cautiously
      for (int i = 0; i < uniqueIds.length; i += perDocParallel) {
        final sub = uniqueIds.sublist(
            i,
            (i + perDocParallel) > uniqueIds.length
                ? uniqueIds.length
                : (i + perDocParallel));
        final docs = await Future.wait(sub.map((id) async {
          try {
            return await _experiencesCollection.doc(id).get();
          } catch (e) {
            debugPrint('getExperiencesByIds: per-doc get failed for $id: $e');
            return null;
          }
        }));
        for (final doc in docs) {
          if (doc != null && doc.exists) {
            accumulated.add(Experience.fromFirestore(doc));
          }
        }
      }
    } else {
      // Use chunked whereIn with limited concurrency, skipping the first chunk already fetched
      const int maxConcurrent = 6;
      final List<List<String>> remaining = chunks.skip(1).toList();
      for (int i = 0; i < remaining.length; i += maxConcurrent) {
        final batch = remaining.sublist(
            i,
            (i + maxConcurrent) > remaining.length
                ? remaining.length
                : (i + maxConcurrent));
        final futures = batch.map((chunk) async {
          try {
            final snapshot = await _experiencesCollection
                .where(FieldPath.documentId, whereIn: chunk)
                .get();
            return snapshot.docs
                .map((doc) => Experience.fromFirestore(doc))
                .toList();
          } catch (e) {
            // If any later chunk still fails due to rules, fall back to per-doc for just that chunk
            debugPrint(
                'getExperiencesByIds: whereIn denied for chunk of ${chunk.length}. Falling back to per-doc for this chunk. Error: $e');
            const int perDocParallel = 12;
            final List<Experience> perDoc = [];
            for (int j = 0; j < chunk.length; j += perDocParallel) {
              final sub = chunk.sublist(
                  j,
                  (j + perDocParallel) > chunk.length
                      ? chunk.length
                      : (j + perDocParallel));
              final docs = await Future.wait(sub.map((id) async {
                try {
                  return await _experiencesCollection.doc(id).get();
                } catch (inner) {
                  debugPrint(
                      'getExperiencesByIds: per-doc get failed for $id: $inner');
                  return null;
                }
              }));
              for (final doc in docs) {
                if (doc != null && doc.exists) {
                  perDoc.add(Experience.fromFirestore(doc));
                }
              }
            }
            return perDoc;
          }
        }).toList();

        final batchResults = await Future.wait(futures);
        for (final list in batchResults) {
          accumulated.addAll(list);
        }
      }
    }

    // Deduplicate in case of overlaps
    final Map<String, Experience> byId = {
      for (final exp in accumulated) exp.id: exp,
    };
    return byId.values.toList();
  }

  Future<List<Experience>> getUserExperiences() async {
    final userId = _currentUserId;
    if (userId == null) {
      print("getUserExperiences: No user authenticated, returning empty list.");
      return []; // Or throw Exception('User not authenticated');
    }
    print("getUserExperiences: Fetching experiences for user ID: $userId");

    final Map<String, Experience> experiencesById = {};

    Future<void> addExperiencesFromQuery(Query query, String label) async {
      try {
        final snapshot = await query.get();
        print(
            'getUserExperiences: $label query fetched ${snapshot.docs.length} docs for $userId.');
        for (final doc in snapshot.docs) {
          try {
            final exp = Experience.fromFirestore(doc);
            experiencesById[exp.id] = exp;
          } catch (e) {
            print(
                'getUserExperiences: Failed to parse experience ${doc.id} from $label query: $e');
          }
        }
      } on FirebaseException catch (e) {
        print('getUserExperiences: Firebase error during $label query: $e');
        // Continue with other queries even if this one fails
      } catch (e) {
        print('getUserExperiences: Unexpected error during $label query: $e');
      }
    }

    // Primary query: Get experiences created by this user
    await addExperiencesFromQuery(
        _experiencesCollection.where('createdBy', isEqualTo: userId),
        'createdBy');

    // Secondary query: Get experiences owned by this user (for transferred ownership)
    await addExperiencesFromQuery(
        _experiencesCollection.where('ownerUserId', isEqualTo: userId),
        'ownerUserId');

    // Tertiary query: Get experiences where user is an editor (collaborative access)
    await addExperiencesFromQuery(
        _experiencesCollection.where('editorUserIds', arrayContains: userId),
        'editorUserIds');

    final experiences = experiencesById.values.toList()
      ..sort((a, b) {
        // Sort by updatedAt (most recent first)
        return b.updatedAt.compareTo(a.updatedAt);
      });

    print(
        "getUserExperiences: Returning ${experiences.length} deduplicated experiences for user $userId.");
    return experiences;
  }

  /// Get all experiences from shared categories (categories shared with the current user)
  /// This fetches experiences from all categories where the user has been granted access,
  /// including newly added experiences.
  Future<List<Experience>> getExperiencesFromSharedCategories() async {
    final userId = _currentUserId;
    if (userId == null) {
      debugPrint("getExperiencesFromSharedCategories: No user authenticated.");
      return [];
    }

    try {
      // Get all category share permissions for this user
      final shareSnapshot = await _sharePermissionsCollection
          .where('itemType', isEqualTo: 'category')
          .where('sharedWithUserId', isEqualTo: userId)
          .get();

      if (shareSnapshot.docs.isEmpty) {
        debugPrint(
            "getExperiencesFromSharedCategories: No shared categories found for user $userId.");
        return [];
      }

      // Collect all experiences from all shared categories
      final List<Experience> allExperiences = [];
      final Set<String> seenExperienceIds = {};

      for (final doc in shareSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;

        final categoryId = data['itemId'] as String?;
        final ownerUserId = data['ownerUserId'] as String?;

        if (categoryId == null || ownerUserId == null) continue;

        // Try to fetch as user category first, then as color category
        // We need to determine if it's a user category or color category
        // Try both and combine results
        try {
          // Try as user category
          final userCategoryExperiences = await getExperiencesForOwnerCategory(
            ownerUserId: ownerUserId,
            categoryId: categoryId,
            isColorCategory: false,
            limitPerQuery: 500,
          );

          for (final exp in userCategoryExperiences) {
            if (seenExperienceIds.add(exp.id)) {
              allExperiences.add(exp);
            }
          }
        } catch (e) {
          debugPrint(
              "getExperiencesFromSharedCategories: Error fetching user category $categoryId: $e");
        }

        try {
          // Try as color category
          final colorCategoryExperiences = await getExperiencesForOwnerCategory(
            ownerUserId: ownerUserId,
            categoryId: categoryId,
            isColorCategory: true,
            limitPerQuery: 500,
          );

          for (final exp in colorCategoryExperiences) {
            if (seenExperienceIds.add(exp.id)) {
              allExperiences.add(exp);
            }
          }
        } catch (e) {
          debugPrint(
              "getExperiencesFromSharedCategories: Error fetching color category $categoryId: $e");
        }
      }

      debugPrint(
          "getExperiencesFromSharedCategories: Found ${allExperiences.length} experiences from ${shareSnapshot.docs.length} shared categories.");
      return allExperiences;
    } catch (e) {
      debugPrint("getExperiencesFromSharedCategories: Error: $e");
      return [];
    }
  }

  // ======= Review-related operations =======

  /// Add a review to an experience
  Future<String> addReview(Review review) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    // Prepare data with server timestamps
    final now = FieldValue.serverTimestamp();
    final data = review.toMap();
    data['createdAt'] = now;
    data['updatedAt'] = now;

    // Add the review to Firestore
    final docRef = await _reviewsCollection.add(data);

    // Update the experience's average rating
    await _updateExperienceRating(review.experienceId);

    return docRef.id;
  }

  /// Get reviews for an experience
  Future<List<Review>> getReviewsForExperience(
    String experienceId, {
    int limit = 20,
  }) async {
    final snapshot = await _reviewsCollection
        .where('experienceId', isEqualTo: experienceId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs.map((doc) => Review.fromFirestore(doc)).toList();
  }

  /// Update an existing review
  Future<void> updateReview(Review review) async {
    if (_currentUserId == null || _currentUserId != review.userId) {
      throw Exception('Not authorized to update this review');
    }

    final data = review.toMap();
    data['updatedAt'] = FieldValue.serverTimestamp();

    await _reviewsCollection.doc(review.id).update(data);

    // Update the experience's average rating
    await _updateExperienceRating(review.experienceId);
  }

  /// Delete a review
  Future<void> deleteReview(Review review) async {
    if (_currentUserId == null || _currentUserId != review.userId) {
      throw Exception('Not authorized to delete this review');
    }

    await _reviewsCollection.doc(review.id).delete();

    // Update the experience's average rating
    await _updateExperienceRating(review.experienceId);
  }

  /// Like or unlike a review
  Future<void> toggleReviewLike(String reviewId) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    final reviewRef = _reviewsCollection.doc(reviewId);

    return _firestore.runTransaction((transaction) async {
      final reviewDoc = await transaction.get(reviewRef);

      if (!reviewDoc.exists) {
        throw Exception('Review not found');
      }

      final reviewData = reviewDoc.data() as Map<String, dynamic>;
      final List<String> likedBy =
          List<String>.from(reviewData['likedByUserIds'] ?? []);

      if (likedBy.contains(_currentUserId)) {
        // Unlike
        likedBy.remove(_currentUserId);
        transaction.update(reviewRef, {
          'likedByUserIds': likedBy,
          'likeCount': FieldValue.increment(-1),
        });
      } else {
        // Like
        likedBy.add(_currentUserId!);
        transaction.update(reviewRef, {
          'likedByUserIds': likedBy,
          'likeCount': FieldValue.increment(1),
        });
      }
    });
  }

  // ======= Comment-related operations =======

  /// Add a comment to an experience
  Future<String> addComment(Comment comment) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    // Prepare data with server timestamps
    final now = FieldValue.serverTimestamp();
    final data = comment.toMap();
    data['createdAt'] = now;
    data['updatedAt'] = now;

    // Add the comment to Firestore
    final docRef = await _commentsCollection.add(data);
    return docRef.id;
  }

  /// Get comments for an experience
  Future<List<Comment>> getCommentsForExperience(
    String experienceId, {
    int limit = 50,
    String? parentCommentId,
  }) async {
    var query = _commentsCollection
        .where('experienceId', isEqualTo: experienceId)
        .orderBy('createdAt', descending: true);

    if (parentCommentId != null) {
      // Get replies to a specific comment
      query = query.where('parentCommentId', isEqualTo: parentCommentId);
    } else {
      // Get top-level comments
      query = query.where('parentCommentId', isNull: true);
    }

    final snapshot = await query.limit(limit).get();

    return snapshot.docs.map((doc) => Comment.fromFirestore(doc)).toList();
  }

  /// Update a comment
  Future<void> updateComment(Comment comment) async {
    if (_currentUserId == null || _currentUserId != comment.userId) {
      throw Exception('Not authorized to update this comment');
    }

    final data = comment.toMap();
    data['updatedAt'] = FieldValue.serverTimestamp();

    await _commentsCollection.doc(comment.id).update(data);
  }

  /// Delete a comment
  Future<void> deleteComment(Comment comment) async {
    if (_currentUserId == null || _currentUserId != comment.userId) {
      throw Exception('Not authorized to delete this comment');
    }

    await _commentsCollection.doc(comment.id).delete();
  }

  /// Like or unlike a comment
  Future<void> toggleCommentLike(String commentId) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    final commentRef = _commentsCollection.doc(commentId);

    return _firestore.runTransaction((transaction) async {
      final commentDoc = await transaction.get(commentRef);

      if (!commentDoc.exists) {
        throw Exception('Comment not found');
      }

      final commentData = commentDoc.data() as Map<String, dynamic>;
      final List<String> likedBy =
          List<String>.from(commentData['likedByUserIds'] ?? []);

      if (likedBy.contains(_currentUserId)) {
        // Unlike
        likedBy.remove(_currentUserId);
        transaction.update(commentRef, {
          'likedByUserIds': likedBy,
          'likeCount': FieldValue.increment(-1),
        });
      } else {
        // Like
        likedBy.add(_currentUserId!);
        transaction.update(commentRef, {
          'likedByUserIds': likedBy,
          'likeCount': FieldValue.increment(1),
        });
      }
    });
  }

  // ======= Reel-related operations =======

  /// Add a reel for an experience
  Future<String> addReel(Reel reel) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    // Prepare data with server timestamp
    final data = reel.toMap();
    data['createdAt'] = FieldValue.serverTimestamp();

    // Add the reel to Firestore
    final docRef = await _reelsCollection.add(data);

    // Update the experience to include this reel ID
    await _experiencesCollection.doc(reel.experienceId).update({
      'reelIds': FieldValue.arrayUnion([docRef.id]),
    });

    return docRef.id;
  }

  /// Get reels for an experience
  Future<List<Reel>> getReelsForExperience(
    String experienceId, {
    int limit = 20,
  }) async {
    final snapshot = await _reelsCollection
        .where('experienceId', isEqualTo: experienceId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs.map((doc) => Reel.fromFirestore(doc)).toList();
  }

  /// Delete a reel
  Future<void> deleteReel(Reel reel) async {
    if (_currentUserId == null || _currentUserId != reel.userId) {
      throw Exception('Not authorized to delete this reel');
    }

    await _reelsCollection.doc(reel.id).delete();

    // Remove the reel ID from the experience
    await _experiencesCollection.doc(reel.experienceId).update({
      'reelIds': FieldValue.arrayRemove([reel.id]),
    });
  }

  /// Like or unlike a reel
  Future<void> toggleReelLike(String reelId) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    final reelRef = _reelsCollection.doc(reelId);

    return _firestore.runTransaction((transaction) async {
      final reelDoc = await transaction.get(reelRef);

      if (!reelDoc.exists) {
        throw Exception('Reel not found');
      }

      final reelData = reelDoc.data() as Map<String, dynamic>;
      final List<String> likedBy =
          List<String>.from(reelData['likedByUserIds'] ?? []);

      if (likedBy.contains(_currentUserId)) {
        // Unlike
        likedBy.remove(_currentUserId);
        transaction.update(reelRef, {
          'likedByUserIds': likedBy,
          'likeCount': FieldValue.increment(-1),
        });
      } else {
        // Like
        likedBy.add(_currentUserId!);
        transaction.update(reelRef, {
          'likedByUserIds': likedBy,
          'likeCount': FieldValue.increment(1),
        });
      }
    });
  }

  // ======= Follow-related operations =======

  /// Follow an experience
  Future<void> followExperience(String experienceId) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    await _experiencesCollection.doc(experienceId).update({
      'followerIds': FieldValue.arrayUnion([_currentUserId]),
    });
  }

  /// Unfollow an experience
  Future<void> unfollowExperience(String experienceId) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    await _experiencesCollection.doc(experienceId).update({
      'followerIds': FieldValue.arrayRemove([_currentUserId]),
    });
  }

  /// Check if the current user is following an experience
  Future<bool> isFollowingExperience(String experienceId) async {
    if (_currentUserId == null) {
      return false;
    }

    final doc = await _experiencesCollection.doc(experienceId).get();
    if (!doc.exists) {
      return false;
    }

    final data = doc.data() as Map<String, dynamic>;
    final List<String> followers = List<String>.from(data['followerIds'] ?? []);

    return followers.contains(_currentUserId);
  }

  /// Get experiences followed by the current user
  Future<List<Experience>> getFollowedExperiences({int limit = 20}) async {
    if (_currentUserId == null) {
      return [];
    }

    final snapshot = await _experiencesCollection
        .where('followerIds', arrayContains: _currentUserId)
        .limit(limit)
        .get();

    return snapshot.docs.map((doc) => Experience.fromFirestore(doc)).toList();
  }

  // ======= Helper methods =======

  /// Update the average rating of an experience based on all reviews
  Future<void> _updateExperienceRating(String experienceId) async {
    // Get all reviews for this experience
    final reviewsSnapshot = await _reviewsCollection
        .where('experienceId', isEqualTo: experienceId)
        .get();

    // Calculate the average rating
    double totalRating = 0;
    final reviews = reviewsSnapshot.docs;
    final reviewCount = reviews.length;

    if (reviewCount > 0) {
      for (final doc in reviews) {
        final data = doc.data() as Map<String, dynamic>;
        totalRating += (data['rating'] ?? 0).toDouble();
      }

      final averageRating = totalRating / reviewCount;

      // Update the experience with the new rating
      await _experiencesCollection.doc(experienceId).update({
        'plendyRating': averageRating,
        'plendyReviewCount': reviewCount,
      });
    } else {
      // No reviews, reset rating
      await _experiencesCollection.doc(experienceId).update({
        'plendyRating': 0,
        'plendyReviewCount': 0,
      });
    }
  }

  // ======= Color Category Operations =======

  /// Fetches the user's custom color categories.
  /// Set [includeSharedEditable] to true to append color categories shared with the user that have edit access.
  Future<List<ColorCategory>> getUserColorCategories(
      {bool includeSharedEditable = false}) async {
    final userId = _currentUserId;
    print(
        "getUserColorCategories START - User: $userId | includeSharedEditable: $includeSharedEditable");
    if (userId == null) {
      print("getUserColorCategories END - No user, returning empty list.");
      return [];
    }

    final collectionRef = _userColorCategoriesCollection(userId);
    final snapshot =
        await collectionRef.orderBy('orderIndex').orderBy('name').get();

    final List<ColorCategory> ownedCategories =
        snapshot.docs.map((doc) => ColorCategory.fromFirestore(doc)).toList();
    print(
        "getUserColorCategories - Fetched ${ownedCategories.length} owned color categories from Firestore.");

    List<ColorCategory> sharedCategories = [];
    if (includeSharedEditable) {
      final permissions = await _getEditableCategoryPermissionsForCurrentUser();
      print(
          "getUserColorCategories - Evaluating ${permissions.length} editable shared category permissions for color categories.");

      if (permissions.isNotEmpty) {
        final processedKeys = <String>{};
        final fetchFutures = <Future<ColorCategory?>>[];
        final ownerNameCache = <String, String>{};

        for (final permission in permissions) {
          if (permission.itemId.isEmpty || permission.ownerUserId.isEmpty) {
            continue;
          }
          final key = '${permission.ownerUserId}_${permission.itemId}';
          if (!processedKeys.add(key)) {
            continue;
          }

          fetchFutures.add(() async {
            try {
              final doc =
                  await _userColorCategoriesCollection(permission.ownerUserId)
                      .doc(permission.itemId)
                      .get();
              if (!doc.exists) {
                return null;
              }
              final category = ColorCategory.fromFirestore(doc);
              final ownerName = await _resolveShareOwnerDisplayName(
                  permission.ownerUserId, ownerNameCache);
              return category.copyWith(sharedOwnerDisplayName: ownerName);
            } catch (e) {
              debugPrint(
                  'getUserColorCategories - Error loading shared color category ${permission.itemId} from ${permission.ownerUserId}: $e');
              return null;
            }
          }());
        }

        if (fetchFutures.isNotEmpty) {
          final results = await Future.wait(fetchFutures);
          sharedCategories =
              results.whereType<ColorCategory>().toList(growable: false);
          sharedCategories.sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        }
      }
    }

    final Map<String, ColorCategory> combined = {};

    void addCategories(List<ColorCategory> source) {
      for (final category in source) {
        final key = '${category.ownerUserId}_${category.id}';
        combined.putIfAbsent(key, () => category);
      }
    }

    addCategories(ownedCategories);
    addCategories(sharedCategories);

    final finalCategories = combined.values.toList(growable: false);

    print(
        "getUserColorCategories END - Returning ${finalCategories.length} color categories (owned: ${ownedCategories.length}, shared: ${sharedCategories.length}).");
    return finalCategories;
  }

  /// Initializes the default color categories for a user in Firestore.
  Future<List<ColorCategory>> initializeDefaultUserColorCategories(
      String userId) async {
    // Use the ColorCategory initializer
    final defaultCategories =
        ColorCategory.createInitialColorCategories(userId);
    final batch = _firestore.batch();
    // Use the color categories collection helper
    final collectionRef = _userColorCategoriesCollection(userId);
    List<ColorCategory> createdCategories = [];

    print("INITIALIZING default color categories for user $userId.");

    // Assign sequential orderIndex during initialization
    for (int i = 0; i < defaultCategories.length; i++) {
      final category = defaultCategories[i];
      final docRef = collectionRef.doc();
      final data = category.toMap();
      data['orderIndex'] = i; // Assign index
      batch.set(docRef, data);
      // Create the ColorCategory object with the generated ID and index
      createdCategories.add(ColorCategory(
        id: docRef.id,
        name: category.name,
        colorHex: category.colorHex,
        ownerUserId: userId,
        orderIndex: i, // Include index
        lastUsedTimestamp: null, // Ensure this is explicitly null
      ));
    }

    try {
      await batch.commit();
      print(
          "Successfully initialized ${createdCategories.length} default color categories for user $userId.");
      return createdCategories;
    } catch (e) {
      print(
          "Error during default color category initialization batch commit: $e");
      throw Exception("Failed to initialize default color categories: $e");
    }
  }

  /// Adds a new custom color category for the current user.
  Future<ColorCategory> addColorCategory(
    String name,
    String colorHex, {
    bool isPrivate = false,
  }) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final categoryRef = _userColorCategoriesCollection(userId);

    // Check if a category with the same name already exists (case-insensitive)
    final nameLower = name.toLowerCase();
    final existingSnapshot = await categoryRef.get();
    final existingDocs = existingSnapshot.docs;

    // Use try-catch for potential state errors during iteration
    QueryDocumentSnapshot<Object?>? existingDoc;
    try {
      existingDoc = existingDocs.firstWhere(
        (doc) =>
            (doc.data() as Map<String, dynamic>)['name']?.toLowerCase() ==
            nameLower,
      );
    } on StateError {
      existingDoc = null; // No matching element found
    } catch (e) {
      print("Error checking for existing color category: $e");
      existingDoc = null; // Treat other errors as not found for safety
    }

    if (existingDoc != null) {
      throw Exception('A color category with this name already exists.');
    }

    // Determine the next order index
    int nextOrderIndex = 0;
    try {
      final querySnapshot = await categoryRef
          .orderBy('orderIndex', descending: true)
          .limit(1)
          .get();
      if (querySnapshot.docs.isNotEmpty) {
        final lastCategory =
            ColorCategory.fromFirestore(querySnapshot.docs.first);
        if (lastCategory.orderIndex != null) {
          nextOrderIndex = lastCategory.orderIndex! + 1;
        }
      }
    } catch (e) {
      print(
          "Warning: Could not determine next color category orderIndex, defaulting to 0. Error: $e");
    }
    print("Assigning next color category orderIndex: $nextOrderIndex");

    final data = {
      'name': name,
      'colorHex': colorHex,
      'ownerUserId': userId, // Ensure owner ID is stored
      'orderIndex': nextOrderIndex,
      'lastUsedTimestamp': null,
      'isPrivate': isPrivate,
    };
    final docRef = await categoryRef.add(data);
    return ColorCategory(
        id: docRef.id,
        name: name,
        colorHex: colorHex,
        ownerUserId: userId,
        orderIndex: nextOrderIndex,
        lastUsedTimestamp: null,
        isPrivate: isPrivate);
  }

  /// Updates an existing custom color category for the current user.
  Future<void> updateColorCategory(ColorCategory category) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }
    final targetUserId =
        category.ownerUserId.isNotEmpty ? category.ownerUserId : userId;
    print(
        'ExperienceService.updateColorCategory: currentUser=$userId, targetUserId=$targetUserId, categoryOwner=${category.ownerUserId}, categoryId=${category.id}');

    // If updating someone else's category, check if permission exists
    if (targetUserId != userId) {
      final expectedPermissionId =
          '${targetUserId}_category_${category.id}_$userId';
      print(
          'ExperienceService.updateColorCategory: Expected permission doc ID: $expectedPermissionId');

      try {
        final permissionDoc = await _firestore
            .collection('share_permissions')
            .doc(expectedPermissionId)
            .get();
        if (permissionDoc.exists) {
          final data = permissionDoc.data() as Map<String, dynamic>;
          print(
              'ExperienceService.updateColorCategory: Permission doc exists with accessLevel: ${data['accessLevel']}');
        } else {
          print(
              'ExperienceService.updateColorCategory: Permission doc does NOT exist!');
        }
      } catch (e) {
        print(
            'ExperienceService.updateColorCategory: Error checking permission doc: $e');
      }
    }

    await _userColorCategoriesCollection(targetUserId)
        .doc(category.id)
        .update(category.toMap());
  }

  /// Deletes a custom color category for the current user.
  Future<void> deleteColorCategory(String categoryId) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }
    await _userColorCategoriesCollection(userId).doc(categoryId).delete();
    // FUTURE: Consider updating Experiences using this colorCategoryId (set to null?)
  }

  /// Updates only the last used timestamp for a color category.
  Future<void> updateColorCategoryLastUsedTimestamp(String categoryId) async {
    final userId = _currentUserId;
    if (userId == null) {
      print("Cannot update color category timestamp: User not authenticated");
      return;
    }
    try {
      await _userColorCategoriesCollection(userId)
          .doc(categoryId)
          .update({'lastUsedTimestamp': FieldValue.serverTimestamp()});
      print("Updated lastUsedTimestamp for color category $categoryId");
    } catch (e) {
      print(
          "Error updating lastUsedTimestamp for color category $categoryId: $e");
    }
  }

  /// Updates the orderIndex for multiple color categories.
  Future<void> updateColorCategoryOrder(
      List<Map<String, dynamic>> categoryOrderUpdates) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }
    if (categoryOrderUpdates.isEmpty) {
      print("No color category order updates to perform.");
      return;
    }

    final categoryRef = _userColorCategoriesCollection(userId);
    final batch = _firestore.batch();
    int updatedCount = 0;

    for (final updateData in categoryOrderUpdates) {
      final categoryId = updateData['id'] as String?;
      final orderIndex = updateData['orderIndex'] as int?;

      if (categoryId != null && orderIndex != null) {
        final docRef = categoryRef.doc(categoryId);
        batch.update(docRef, {'orderIndex': orderIndex});
        updatedCount++;
      } else {
        print(
            "Warning: Skipping invalid color category order update data: $updateData");
      }
    }

    if (updatedCount > 0) {
      try {
        await batch.commit();
        print(
            "Successfully updated orderIndex for $updatedCount color categories.");
      } catch (e) {
        print("Error committing color category order update batch: $e");
        throw Exception("Failed to save color category order: $e");
      }
    } else {
      print(
          "No valid color category order updates found in the provided list.");
    }
  }

  // Add more helper methods as needed
}
