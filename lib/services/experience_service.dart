import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  // Helper to get the path to a user's custom categories sub-category
  CollectionReference _userCategoriesCollection(String userId) =>
      _usersCollection.doc(userId).collection('categories');

  Future<UserCategory?> getUserCategoryByOwner(
      String ownerUserId, String categoryId) async {
    if (ownerUserId.isEmpty || categoryId.isEmpty) return null;
    try {
      final currentUserId = _currentUserId;
      final expectedPermissionId = '${ownerUserId}_category_${categoryId}_${currentUserId}';
      print('getUserCategoryByOwner: Fetching users/$ownerUserId/categories/$categoryId');
      print('getUserCategoryByOwner: Expected permission doc ID: $expectedPermissionId');
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
      print('getColorCategoryByOwner: Fetching users/$ownerUserId/color_categories/$categoryId');
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

  // ======= User Category Operations =======

  /// Fetches the user's custom categories.
  /// Categories are sorted by orderIndex, then by name.
  Future<List<UserCategory>> getUserCategories() async {
    final userId = _currentUserId;
    print("getUserCategories START - User: $userId"); // Log Start
    if (userId == null) {
      print("getUserCategories END - No user, returning empty list.");
      // Return empty list instead of defaults for non-logged-in users
      return [];
    }

    final collectionRef = _userCategoriesCollection(userId);
    // UPDATED: Sort by orderIndex first (nulls handled by Firestore or considered last),
    // then by name for consistent ordering of items with the same/no index.
    final snapshot =
        await collectionRef.orderBy('orderIndex').orderBy('name').get();

    List<UserCategory> fetchedCategories =
        snapshot.docs.map((doc) => UserCategory.fromFirestore(doc)).toList();
    print(
        "getUserCategories - Fetched ${fetchedCategories.length} from Firestore:"); // Log Fetched Raw
    // for (var c in fetchedCategories) {
    //   print("  - ${c.name} (ID: ${c.id})");
    // }

    // De-duplicate the fetched list based on name
    final uniqueCategoriesByName = <String, UserCategory>{};
    for (var category in fetchedCategories) {
      final nameLower = category.name.toLowerCase();
      uniqueCategoriesByName.putIfAbsent(nameLower, () => category);
    }
    final uniqueFetchedCategories = uniqueCategoriesByName.values.toList();
    uniqueFetchedCategories.sort((a, b) => a.name.compareTo(b.name));
    print(
        "getUserCategories - De-duplicated list size: ${uniqueFetchedCategories.length}");

    // Sort the unique list based on the original fetched order (which is now sorted by Firestore)
    final finalCategories = uniqueFetchedCategories.toList();
    finalCategories.sort((a, b) {
      // Find original index in the Firestore-sorted snapshot
      final indexA = fetchedCategories.indexWhere((c) => c.id == a.id);
      final indexB = fetchedCategories.indexWhere((c) => c.id == b.id);
      // If either wasn't found (shouldn't happen), fallback to name sort
      if (indexA == -1 || indexB == -1) return a.name.compareTo(b.name);
      return indexA.compareTo(indexB);
    });

    print(
        "getUserCategories END - Returning ${finalCategories.length} unique categories (sorted by index/name):");
    // for (var c in finalCategories) {
    //   print("  - ${c.name} (ID: ${c.id}, Index: ${c.orderIndex})");
    // }
    return finalCategories;
  }

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
  Future<UserCategory> addUserCategory(String name, String icon) async {
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
      'lastUsedTimestamp': null // Explicitly null initially
    };
    final docRef = await categoryRef.add(data);
    return UserCategory(
        id: docRef.id,
        name: name,
        icon: icon,
        ownerUserId: userId,
        orderIndex: nextOrderIndex, // Return with index
        lastUsedTimestamp: null);
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

    // Add the experience to Firestore
    final docRef = await _experiencesCollection.add(data);
    return docRef.id;
  }

  /// Get an experience by ID
  Future<Experience?> getExperience(String experienceId) async {
    final doc = await _experiencesCollection.doc(experienceId).get();
    if (!doc.exists) {
      return null;
    }
    return Experience.fromFirestore(doc);
  }

  /// Update an existing experience
  Future<void> updateExperience(Experience experience) async {
    final data = experience.toMap();
    data['updatedAt'] = FieldValue.serverTimestamp();

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
  Future<List<Experience>> getExperiencesByUserCategoryId(String categoryId,
      {int limit = 100}) async {
    if (categoryId.isEmpty) return [];
    final snapshot = await _experiencesCollection
        .where('categoryId', isEqualTo: categoryId)
        .limit(limit)
        .get();
    return snapshot.docs.map((doc) => Experience.fromFirestore(doc)).toList();
  }

  /// Get all experiences linked to a user category, including primary categoryId
  /// and entries where the category is present in otherCategories array.
  Future<List<Experience>> getExperiencesByUserCategoryAll(String categoryId,
      {int limitPerQuery = 100}) async {
    if (categoryId.isEmpty) return [];
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

  /// Get experiences by color category ID
  Future<List<Experience>> getExperiencesByColorCategoryId(
      String colorCategoryId,
      {int limit = 100}) async {
    if (colorCategoryId.isEmpty) return [];
    final snapshot = await _experiencesCollection
        .where('colorCategoryId', isEqualTo: colorCategoryId)
        .limit(limit)
        .get();
    return snapshot.docs.map((doc) => Experience.fromFirestore(doc)).toList();
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
    final query = _experiencesCollection
        .where('createdBy', isEqualTo: userId)
        .orderBy('createdAt', descending: true);

    final snapshot = await query.get(options);

    return snapshot.docs.map((doc) => Experience.fromFirestore(doc)).toList();
  }

  /// Get multiple experiences by their document IDs (handles Firestore whereIn limits)
  Future<List<Experience>> getExperiencesByIds(
      List<String> experienceIds,
      {int chunkSize = 30}) async {
    if (experienceIds.isEmpty) {
      return [];
    }

    final List<String> uniqueIds = experienceIds.toSet().toList();

    final List<List<String>> chunks = [];
    for (int i = 0; i < uniqueIds.length; i += chunkSize) {
      final end = (i + chunkSize) > uniqueIds.length ? uniqueIds.length : (i + chunkSize);
      chunks.add(uniqueIds.sublist(i, end));
    }

    final List<Experience> results = [];
    for (final chunk in chunks) {
      try {
        final snapshot = await _experiencesCollection
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        results.addAll(snapshot.docs.map((doc) => Experience.fromFirestore(doc)));
      } catch (e) {
        // Some environments will fail the entire whereIn query if any single
        // document in the chunk is not readable by the current user (per rules).
        // Fall back to per-doc fetches so we still retrieve the allowed ones.
        print(
            "getExperiencesByIds: Error fetching chunk of size ${chunk.length}: $e. Falling back to per-doc reads.");

        for (final id in chunk) {
          try {
            final doc = await _experiencesCollection.doc(id).get();
            if (doc.exists) {
              // Guard: Firestore rules may still block certain docs individually.
              // Only add those we could read.
              results.add(Experience.fromFirestore(doc));
            }
          } catch (inner) {
            // Ignore docs we cannot read due to permissions; continue.
            print(
                "getExperiencesByIds: Skipping $id due to error on per-doc read: $inner");
          }
        }
      }
    }

    // Deduplicate in case of overlaps
    final Map<String, Experience> byId = {
      for (final exp in results) exp.id: exp,
    };
    return byId.values.toList();
  }

  /// Get all experiences created by the current user.
  Future<List<Experience>> getUserExperiences() async {
    final userId = _currentUserId;
    if (userId == null) {
      print("getUserExperiences: No user authenticated, returning empty list.");
      return []; // Or throw Exception('User not authenticated');
    }
    try {
      print(
          "getUserExperiences: Fetching all experiences for user ID: $userId");
      final snapshot = await _experiencesCollection
          .where('editorUserIds',
              arrayContains: userId) // Check if user is an editor
          .orderBy('updatedAt',
              descending: true) // Order by most recently updated
          .get();

      final experiences =
          snapshot.docs.map((doc) => Experience.fromFirestore(doc)).toList();
      print(
          "getUserExperiences: Fetched ${experiences.length} experiences for user $userId.");
      return experiences;
    } catch (e) {
      print("Error fetching user experiences for user $userId: $e");
      return []; // Return empty list on error
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
  /// Categories are sorted by orderIndex, then by name.
  Future<List<ColorCategory>> getUserColorCategories() async {
    final userId = _currentUserId;
    print("getUserColorCategories START - User: $userId");
    if (userId == null) {
      print("getUserColorCategories END - No user, returning empty list.");
      return [];
    }

    final collectionRef = _userColorCategoriesCollection(userId);
    final snapshot =
        await collectionRef.orderBy('orderIndex').orderBy('name').get();

    List<ColorCategory> fetchedCategories =
        snapshot.docs.map((doc) => ColorCategory.fromFirestore(doc)).toList();
    print(
        "getUserColorCategories - Fetched ${fetchedCategories.length} from Firestore:");
    // for (var c in fetchedCategories) {
    //   print("  - ${c.name} (ID: ${c.id}, Color: ${c.colorHex})");
    // }

    // De-duplicate based on name (case-insensitive)
    final uniqueCategoriesByName = <String, ColorCategory>{};
    for (var category in fetchedCategories) {
      final nameLower = category.name.toLowerCase();
      uniqueCategoriesByName.putIfAbsent(nameLower, () => category);
    }
    final uniqueFetchedCategories = uniqueCategoriesByName.values.toList();
    print(
        "getUserColorCategories - De-duplicated list size: ${uniqueFetchedCategories.length}");

    // Sort the unique list based on the original fetched order (which is now sorted by Firestore)
    final finalCategories = uniqueFetchedCategories.toList();
    finalCategories.sort((a, b) {
      final indexA = fetchedCategories.indexWhere((c) => c.id == a.id);
      final indexB = fetchedCategories.indexWhere((c) => c.id == b.id);
      if (indexA == -1 || indexB == -1) return a.name.compareTo(b.name);
      return indexA.compareTo(indexB);
    });

    print(
        "getUserColorCategories END - Returning ${finalCategories.length} unique categories (sorted by index/name):");
    // for (var c in finalCategories) {
    //   print(
    //     "  - ${c.name} (ID: ${c.id}, Index: ${c.orderIndex}, Color: ${c.colorHex})");
    // }
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
  Future<ColorCategory> addColorCategory(String name, String colorHex) async {
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
      'lastUsedTimestamp': null
    };
    final docRef = await categoryRef.add(data);
    return ColorCategory(
        id: docRef.id,
        name: name,
        colorHex: colorHex,
        ownerUserId: userId,
        orderIndex: nextOrderIndex,
        lastUsedTimestamp: null);
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
      final expectedPermissionId = '${targetUserId}_category_${category.id}_$userId';
      print('ExperienceService.updateColorCategory: Expected permission doc ID: $expectedPermissionId');
      
      try {
        final permissionDoc = await _firestore.collection('share_permissions').doc(expectedPermissionId).get();
        if (permissionDoc.exists) {
          final data = permissionDoc.data() as Map<String, dynamic>;
          print('ExperienceService.updateColorCategory: Permission doc exists with accessLevel: ${data['accessLevel']}');
        } else {
          print('ExperienceService.updateColorCategory: Permission doc does NOT exist!');
        }
      } catch (e) {
        print('ExperienceService.updateColorCategory: Error checking permission doc: $e');
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
