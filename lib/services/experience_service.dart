import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/experience.dart';
import '../models/review.dart';
import '../models/comment.dart';
import '../models/reel.dart';
import '../models/user_experience_type.dart';

/// Service for managing Experience-related operations
class ExperienceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Collection references
  CollectionReference get _experiencesCollection =>
      _firestore.collection('experiences');
  CollectionReference get _reviewsCollection =>
      _firestore.collection('reviews');
  CollectionReference get _commentsCollection =>
      _firestore.collection('comments');
  CollectionReference get _reelsCollection => _firestore.collection('reels');
  CollectionReference get _usersCollection => _firestore.collection('users');

  // User-related operations
  String? get _currentUserId => _auth.currentUser?.uid;

  // Helper to get the path to a user's custom experience types sub-collection
  CollectionReference _userExperienceTypesCollection(String userId) =>
      _usersCollection.doc(userId).collection('experienceTypes');

  // ======= User Experience Type Operations =======

  /// Fetches the user's custom experience types.
  /// If none exist, it initializes them with defaults and returns the defaults.
  Future<List<UserExperienceType>> getUserExperienceTypes() async {
    final userId = _currentUserId;
    if (userId == null) {
      // Return default types for non-logged-in users or handle as error
      print(
          "Warning: No authenticated user. Returning default experience types.");
      return UserExperienceType.createInitialTypes();
    }

    final snapshot = await _userExperienceTypesCollection(userId)
        .orderBy('name') // Optional: Order by name
        .get();

    if (snapshot.docs.isEmpty) {
      // No custom types found, initialize with defaults
      print("No custom types found for user $userId. Initializing defaults.");
      return initializeDefaultUserExperienceTypes(userId);
    }

    // Map Firestore documents to UserExperienceType objects
    return snapshot.docs
        .map((doc) => UserExperienceType.fromFirestore(doc))
        .toList();
  }

  /// Initializes the default experience types for a user in Firestore.
  /// This is typically called once when needed (e.g., on first fetch if empty).
  Future<List<UserExperienceType>> initializeDefaultUserExperienceTypes(
      String userId) async {
    final defaultTypes = UserExperienceType.createInitialTypes();
    final batch = _firestore.batch();
    final collectionRef = _userExperienceTypesCollection(userId);

    List<UserExperienceType> createdTypes = [];

    for (final type in defaultTypes) {
      final docRef = collectionRef.doc(); // Auto-generate ID
      batch.set(docRef, type.toMap());
      // Create the object with the generated ID to return it immediately
      createdTypes.add(
          UserExperienceType(id: docRef.id, name: type.name, icon: type.icon));
    }

    await batch.commit();
    print(
        "Successfully initialized ${createdTypes.length} default types for user $userId.");
    return createdTypes;
  }

  /// Adds a new custom experience type for the current user.
  Future<UserExperienceType> addUserExperienceType(
      String name, String icon) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Optional: Check if a type with the same name already exists
    final existing = await _userExperienceTypesCollection(userId)
        .where('name', isEqualTo: name)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      throw Exception('An experience type with this name already exists.');
    }

    final data = {'name': name, 'icon': icon};
    final docRef = await _userExperienceTypesCollection(userId).add(data);
    return UserExperienceType(id: docRef.id, name: name, icon: icon);
  }

  /// Updates an existing custom experience type for the current user.
  Future<void> updateUserExperienceType(UserExperienceType type) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }
    // Add check: Ensure the user owns this type? (Maybe not needed if path includes userId)
    await _userExperienceTypesCollection(userId)
        .doc(type.id)
        .update(type.toMap());
  }

  /// Deletes a custom experience type for the current user.
  Future<void> deleteUserExperienceType(String typeId) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }
    // Add check: Ensure the user owns this type?
    await _userExperienceTypesCollection(userId).doc(typeId).delete();
    // Consider what happens to Experiences using this type. Reassign? Mark as 'Other'?
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

  /// Get experiences by type
  Future<List<Experience>> getExperiencesByType(
    String typeName, {
    int limit = 20,
  }) async {
    final snapshot = await _experiencesCollection
        .where('userExperienceTypeName', isEqualTo: typeName)
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
