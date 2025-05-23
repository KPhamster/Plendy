import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_profile.dart';
import 'dart:async'; // For StreamController if mapping manually, or for rxdart if used

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Check if username is available
  Future<bool> isUsernameAvailable(String username) async {
    final doc = await _firestore
        .collection('usernames')
        .doc(username.toLowerCase())
        .get();
    return !doc.exists;
  }

  // Reserve username and link to user
  Future<bool> setUsername(String userId, String username) async {
    final lowercaseUsername = username.toLowerCase();
    final email = _auth.currentUser?.email;
    final currentUsernameDoc = await _firestore.collection('users').doc(userId).get();
    
    // Safely get the current lowercase username
    String? initialLowercaseUsername;
    if (currentUsernameDoc.exists && currentUsernameDoc.data() != null) {
      final data = Map<String, dynamic>.from(currentUsernameDoc.data()!);
      initialLowercaseUsername = data['lowercaseUsername'] as String?;
    }

    try {
      // If the username hasn't actually changed (case-insensitively), only update the main user doc if needed.
      if (initialLowercaseUsername == lowercaseUsername) {
        // Update user's profile (e.g. if casing of username changed but not lowercase, or other fields)
        // This part might be redundant if updateUserCoreData is always called after, but ensures consistency.
        await _firestore.collection('users').doc(userId).set(
            {
              'username': username, // Potentially update casing
              'lowercaseUsername': lowercaseUsername,
              'email': email, 
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
        return true; // Username is the same (case-insensitively), no need for username transaction.
      }

      // If username has changed, proceed with transaction to claim new or update old.
      await _firestore.runTransaction((transaction) async {
        // 1. Check if the new username is taken by someone else
        final newUsernameDocRef = _firestore.collection('usernames').doc(lowercaseUsername);
        final newUsernameDoc = await transaction.get(newUsernameDocRef);

        if (newUsernameDoc.exists) {
          // Safely check the userId
          final rawData = newUsernameDoc.data();
          final data = rawData != null ? Map<String, dynamic>.from(rawData) : null;
          final existingUserId = data?['userId'];
          if (existingUserId != userId) {
            throw Exception('Username already taken by another user');
          }
        }

        // 2. If the user had an old username, release it from the 'usernames' collection
        if (initialLowercaseUsername != null && initialLowercaseUsername.isNotEmpty) {
          final oldUsernameDocRef = _firestore.collection('usernames').doc(initialLowercaseUsername);
          transaction.delete(oldUsernameDocRef);
        }

        // 3. Create new username reservation
        transaction.set(newUsernameDocRef, {
          'userId': userId,
          'username': username, // Store preferred casing
          'createdAt': FieldValue.serverTimestamp(),
        });

        // 4. Update user's profile in 'users' collection
        transaction.set(
            _firestore.collection('users').doc(userId),
            {
              'username': username,
              'lowercaseUsername': lowercaseUsername,
              'email': email, 
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
      });

      return true;
    } catch (e) {
      print('Error setting username: $e');
      return false;
    }
  }

  // Get user's current username
  Future<String?> getUserUsername(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    if (doc.exists && doc.data() != null) {
      // Safely cast the data to Map<String, dynamic> to avoid type casting errors
      final data = Map<String, dynamic>.from(doc.data()!);
      return data['username'] as String?;
    }
    return null;
  }

  // Save user email when they register
  Future<void> saveUserEmail(String userId, String email) async {
    try {
      await _firestore.collection('users').doc(userId).set({
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error saving user email: $e');
    }
  }

  // Get IDs of users who are following the given userId
  Future<List<String>> getFollowerIds(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('followers')
          .get();
      return snapshot.docs.map((doc) => doc.id).toList();
    } catch (e) {
      print('Error getting follower IDs: $e');
      return [];
    }
  }

  // Get IDs of users whom the given userId is following
  Future<List<String>> getFollowingIds(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('following')
          .get();
      return snapshot.docs.map((doc) => doc.id).toList();
    } catch (e) {
      print('Error getting following IDs: $e');
      return [];
    }
  }

  // Get IDs of users who are friends with the given userId (mutual followers)
  Future<List<String>> getFriendIds(String userId) async {
    try {
      final followingIds = await getFollowingIds(userId);
      if (followingIds.isEmpty) {
        return [];
      }

      List<String> friendIds = [];
      // For each user the current user is following, check if they follow back
      for (String followedUserId in followingIds) {
        final theirFollowersSnapshot = await _firestore
            .collection('users')
            .doc(followedUserId)
            .collection('followers')
            .doc(userId) // Check if the current user (userId) is in their followers list
            .get();
        
        if (theirFollowersSnapshot.exists) {
          friendIds.add(followedUserId);
        }
      }
      return friendIds;
    } catch (e) {
      print('Error getting friend IDs: $e');
      return [];
    }
  }

  // Get user profile details
  Future<UserProfile?> getUserProfile(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists && doc.data() != null) {
        // Safely cast the data to Map<String, dynamic> to avoid type casting errors
        final data = Map<String, dynamic>.from(doc.data()!);
        return UserProfile.fromMap(doc.id, data);
      }
      return null;
    } catch (e) {
      print('Error getting user profile for $userId: $e');
      return null;
    }
  }

  // Follow a user (handles public/private profiles)
  Future<void> followUser(String currentUserId, String targetUserId) async {
    if (currentUserId == targetUserId) return; // Cannot follow self

    print('DEBUG: followUser called - current: $currentUserId, target: $targetUserId');

    try {
      final targetUserProfile = await getUserProfile(targetUserId);
      if (targetUserProfile == null) {
        throw Exception('Target user profile not found.');
      }

      print('DEBUG: Target user profile found - isPrivate: ${targetUserProfile.isPrivate}');

      // Check if this is a "follow back" scenario (target is already following current user)
      bool isFollowBack = await isFollowing(targetUserId, currentUserId);
      print('DEBUG: Is follow back scenario: $isFollowBack');

      if (targetUserProfile.isPrivate && !isFollowBack) {
        // Only send follow request for private profiles if it's NOT a follow back
        print('DEBUG: Target is private and not follow back, attempting sendFollowRequest...');
        await sendFollowRequest(currentUserId, targetUserId);
        print('DEBUG: sendFollowRequest completed successfully.');
      } else {
        // Directly follow in these cases:
        // 1. Target has public profile
        // 2. Target has private profile but this is a follow back (they already follow us)
        print('DEBUG: Following directly (public profile or follow back scenario)...');
        
        print('DEBUG: Adding $targetUserId to $currentUserId following list...');
        await _firestore
            .collection('users')
            .doc(currentUserId)
            .collection('following')
            .doc(targetUserId)
            .set(<String, dynamic>{}); 
        print('DEBUG: Following list updated successfully.');

        print('DEBUG: Adding $currentUserId to $targetUserId followers list...');
        await _firestore
            .collection('users')
            .doc(targetUserId)
            .collection('followers')
            .doc(currentUserId)
            .set(<String, dynamic>{});
        print('DEBUG: Followers list updated successfully.');
      }
      
      print('DEBUG: followUser completed successfully.');
    } catch (e) {
      print('Error in followUser for $targetUserId: $e');
      rethrow; 
    }
  }

  // Unfollow a user
  Future<void> unfollowUser(String currentUserId, String targetUserId) async {
    if (currentUserId == targetUserId) return; // Cannot unfollow self
    try {
      // Remove target from current user's following list
      await _firestore
          .collection('users')
          .doc(currentUserId)
          .collection('following')
          .doc(targetUserId)
          .delete();

      // Remove current user from target's followers list
      await _firestore
          .collection('users')
          .doc(targetUserId)
          .collection('followers')
          .doc(currentUserId)
          .delete();
    } catch (e) {
      print('Error unfollowing user $targetUserId: $e');
      rethrow;
    }
  }

  // Check if current user is following target user
  Future<bool> isFollowing(String currentUserId, String targetUserId) async {
    if (currentUserId == targetUserId) return false;
    try {
      final doc = await _firestore
          .collection('users')
          .doc(currentUserId)
          .collection('following')
          .doc(targetUserId)
          .get();
      return doc.exists;
    } catch (e) {
      print('Error checking if following user $targetUserId: $e');
      return false; // Default to false on error
    }
  }

  // Send a follow request to a private profile
  Future<void> sendFollowRequest(String currentUserId, String targetUserId) async {
    if (currentUserId == targetUserId) return;
    
    print('DEBUG: sendFollowRequest called - from: $currentUserId to: $targetUserId');
    
    try {
      await _firestore
          .collection('users')
          .doc(targetUserId) // The user receiving the request
          .collection('followRequests')
          .doc(currentUserId) // The user sending the request
          .set({'requestedAt': FieldValue.serverTimestamp()});
      print('DEBUG: sendFollowRequest successfully wrote to Firestore for $targetUserId from $currentUserId');
    } catch (e) {
      print('DEBUG: sendFollowRequest failed - error type: ${e.runtimeType}');
      print('DEBUG: sendFollowRequest failed - error details: $e');
      print('Error sending follow request to $targetUserId from $currentUserId: $e');
      rethrow;
    }
  }

  // Check if a follow request is pending from currentUserId to targetUserId
  Future<bool> hasPendingRequest(String currentUserId, String targetUserId) async {
    if (currentUserId == targetUserId) return false;
    try {
      final doc = await _firestore
          .collection('users')
          .doc(targetUserId)
          .collection('followRequests')
          .doc(currentUserId)
          .get();
      return doc.exists;
    } catch (e) {
      print('Error checking pending follow request for $targetUserId: $e');
      return false;
    }
  }

  // Get list of user profiles who have requested to follow the targetUserId
  Future<List<UserProfile>> getFollowRequests(String targetUserId) async {
    List<UserProfile> requestProfiles = [];
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(targetUserId)
          .collection('followRequests')
          .orderBy('requestedAt', descending: true) // Optional: order by newest first
          .get();
      
      for (var doc in snapshot.docs) {
        final requesterId = doc.id;
        final userProfile = await getUserProfile(requesterId);
        if (userProfile != null) {
          requestProfiles.add(userProfile);
        }
      }
      return requestProfiles;
    } catch (e) {
      print('Error getting follow requests for $targetUserId: $e');
      return [];
    }
  }

  // Stream of follow requests (UserProfile list)
  Stream<List<UserProfile>> getFollowRequestsStream(String targetUserId) {
    return _firestore
        .collection('users')
        .doc(targetUserId)
        .collection('followRequests')
        .orderBy('requestedAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
      List<UserProfile> requestProfiles = [];
      for (var doc in snapshot.docs) {
        final requesterId = doc.id;
        final userProfile = await getUserProfile(requesterId);
        if (userProfile != null) {
          requestProfiles.add(userProfile);
        }
      }
      return requestProfiles;
    });
  }

  // Stream of follow request count
  Stream<int> getFollowRequestsCountStream(String targetUserId) {
    return _firestore
        .collection('users')
        .doc(targetUserId)
        .collection('followRequests')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // Accept a follow request
  Future<void> acceptFollowRequest(String targetUserId, String requesterId) async {
    try {
      // 1. Add to followers/following lists (atomic batch write recommended here)
      WriteBatch batch = _firestore.batch();

      DocumentReference targetFollowersRef = _firestore
          .collection('users')
          .doc(targetUserId)
          .collection('followers')
          .doc(requesterId);
      batch.set(targetFollowersRef, <String, dynamic>{});

      DocumentReference requesterFollowingRef = _firestore
          .collection('users')
          .doc(requesterId)
          .collection('following')
          .doc(targetUserId);
      batch.set(requesterFollowingRef, <String, dynamic>{});

      // 2. Delete the follow request
      DocumentReference requestRef = _firestore
          .collection('users')
          .doc(targetUserId)
          .collection('followRequests')
          .doc(requesterId);
      batch.delete(requestRef);

      await batch.commit();
      
    } catch (e) {
      print('Error accepting follow request from $requesterId to $targetUserId: $e');
      rethrow;
    }
  }

  // Deny a follow request
  Future<void> denyFollowRequest(String targetUserId, String requesterId) async {
    try {
      await _firestore
          .collection('users')
          .doc(targetUserId)
          .collection('followRequests')
          .doc(requesterId)
          .delete();
    } catch (e) {
      print('Error denying follow request from $requesterId to $targetUserId: $e');
      rethrow;
    }
  }

  // Accept all pending follow requests for a user (e.g., when switching to public)
  Future<void> acceptAllPendingRequests(String userId) async {
    try {
      final requestsSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('followRequests')
          .get();

      if (requestsSnapshot.docs.isEmpty) {
        return; // No pending requests
      }

      WriteBatch batch = _firestore.batch();

      for (var requestDoc in requestsSnapshot.docs) {
        final requesterId = requestDoc.id;

        // Add to target's (userId) followers list
        DocumentReference targetFollowersRef = _firestore
            .collection('users')
            .doc(userId)
            .collection('followers')
            .doc(requesterId);
        batch.set(targetFollowersRef, <String, dynamic>{});

        // Add target (userId) to requester's following list
        DocumentReference requesterFollowingRef = _firestore
            .collection('users')
            .doc(requesterId)
            .collection('following')
            .doc(userId);
        batch.set(requesterFollowingRef, <String, dynamic>{});

        // Delete the follow request
        batch.delete(requestDoc.reference);
      }

      await batch.commit();
      print('Accepted all pending requests for user $userId');
    } catch (e) {
      print('Error accepting all pending requests for $userId: $e');
      rethrow;
    }
  }

  // Search for users by username or display name
  Future<List<UserProfile>> searchUsers(String query) async {
    if (query.isEmpty) {
      return [];
    }
    final String lowercaseQuery = query.toLowerCase();
    List<UserProfile> users = [];
    Set<String> userIds = {}; // To avoid duplicates

    try {
      // Search by lowercaseUsername (starts with)
      final usernameSnapshot = await _firestore
          .collection('users')
          .where('lowercaseUsername', isGreaterThanOrEqualTo: lowercaseQuery)
          .where('lowercaseUsername', isLessThanOrEqualTo: '${lowercaseQuery}\uf8ff')
          .limit(10) // Limit results for performance
          .get();

      for (var doc in usernameSnapshot.docs) {
        if (doc.data() != null && !userIds.contains(doc.id)) {
          // Safely cast the data to Map<String, dynamic> to avoid type casting errors
          final data = Map<String, dynamic>.from(doc.data()!);
          users.add(UserProfile.fromMap(doc.id, data));
          userIds.add(doc.id);
        }
      }

      // Search by displayName (starts with)
      // Note: Firestore string comparisons are case-sensitive.
      // For true case-insensitive "starts with" on displayName, store a lowercaseDisplayName field.
      // This query is case-sensitive for the first letter, but less sensitive for subsequent letters.
      final displayNameSnapshot = await _firestore
          .collection('users')
          .where('displayName', isGreaterThanOrEqualTo: query)
          .where('displayName', isLessThanOrEqualTo: '${query}\uf8ff')
          .limit(10) // Limit results
          .get();

      for (var doc in displayNameSnapshot.docs) {
        if (doc.data() != null && !userIds.contains(doc.id)) {
          // Safely cast the data to Map<String, dynamic> to avoid type casting errors
          final data = Map<String, dynamic>.from(doc.data()!);
          users.add(UserProfile.fromMap(doc.id, data));
          userIds.add(doc.id);
        }
      }
      
      // TODO: Consider searching by full username if no displayName is set or vice-versa.
      // TODO: Ensure `displayName` field exists in user documents for this query to be effective.
      //       Users update their displayName via Auth, ensure it's synced to Firestore user doc.

      return users;
    } catch (e) {
      print('Error searching users: $e');
      return [];
    }
  }

  // Update core user data in Firestore (like displayName, photoURL)
  Future<void> updateUserCoreData(String userId, Map<String, dynamic> dataToUpdate) async {
    try {
      Map<String, dynamic> data = Map.from(dataToUpdate); // Create a mutable copy
      data['updatedAt'] = FieldValue.serverTimestamp();
      await _firestore.collection('users').doc(userId).set(
        data,
        SetOptions(merge: true),
      );
    } catch (e) {
      print('Error updating user core data for $userId: $e');
      rethrow;
    }
  }
}
