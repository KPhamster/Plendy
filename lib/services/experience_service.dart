import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/experience.dart';
import '../models/review.dart';
import '../models/comment.dart';
import '../models/reel.dart';
import '../models/user_category.dart';
import '../models/public_experience.dart';

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

  // User-related operations
  String? get _currentUserId => _auth.currentUser?.uid;

  // Helper to get the path to a user's custom categories sub-category
  CollectionReference _userCategoriesCollection(String userId) =>
      _usersCollection.doc(userId).collection('categories');

  // ======= User Category Operations =======

  /// Fetches the user's custom categories.
  /// Categories are sorted by orderIndex, then by name.
  Future<List<UserCategory>> getUserCategories() async {
    final userId = _currentUserId;
    print("getUserCategories START - User: $userId"); // Log Start
    if (userId == null) {
      print("getUserCategories END - No user, returning static defaults.");
      // Sort defaults alphabetically for consistency when not logged in
      var defaults = UserCategory.createInitialCategories();
      defaults.sort((a, b) => a.name.compareTo(b.name));
      return defaults;
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
    fetchedCategories.forEach((c) => print("  - ${c.name} (ID: ${c.id})"));

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
    finalCategories.forEach(
        (c) => print("  - ${c.name} (ID: ${c.id}, Index: ${c.orderIndex})"));
    return finalCategories;
  }

  /// Initializes the default categories for a user in Firestore.
  /// Note: This should now be called explicitly ONCE during user creation flow.
  Future<List<UserCategory>> initializeDefaultUserCategories(
      String userId) async {
    final defaultCategories = UserCategory.createInitialCategories();
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
      'orderIndex': nextOrderIndex, // Set the order index
      'lastUsedTimestamp': null // Explicitly null initially
    };
    final docRef = await categoryRef.add(data);
    return UserCategory(
        id: docRef.id,
        name: name,
        icon: icon,
        orderIndex: nextOrderIndex, // Return with index
        lastUsedTimestamp: null);
  }

  /// Updates an existing custom category for the current user.
  Future<void> updateUserCategory(UserCategory category) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }
    // Add check: Ensure the user owns this type? (Maybe not needed if path includes userId)
    await _userCategoriesCollection(userId)
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
    // Consider adding a check for ownership or admin rights

    // Delete the experience
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

  /// Get experiences by category
  Future<List<Experience>> getExperiencesByCategory(
    String categoryName, {
    int limit = 20,
  }) async {
    final snapshot = await _experiencesCollection
        .where('category', isEqualTo: categoryName)
        .orderBy('plendyRating', descending: true)
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
      {int limit = 50}) async {
    final snapshot = await _experiencesCollection
        .where('createdBy', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs.map((doc) => Experience.fromFirestore(doc)).toList();
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

  // Add more helper methods as needed
}
