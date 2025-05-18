import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_profile.dart';

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

    try {
      // Try to create the username document
      await _firestore.runTransaction((transaction) async {
        final usernameDoc = await transaction
            .get(_firestore.collection('usernames').doc(lowercaseUsername));

        if (usernameDoc.exists) {
          throw Exception('Username already taken');
        }

        // Create username reservation
        transaction
            .set(_firestore.collection('usernames').doc(lowercaseUsername), {
          'userId': userId,
          'username': username,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Update user's profile
        transaction.set(
            _firestore.collection('users').doc(userId),
            {
              'username': username,
              'lowercaseUsername': lowercaseUsername,
              'email': email, // Store the user's email
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
    return doc.data()?['username'] as String?;
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
        return UserProfile.fromMap(doc.id, doc.data()!);
      }
      return null;
    } catch (e) {
      print('Error getting user profile for $userId: $e');
      return null;
    }
  }

  // Follow a user
  Future<void> followUser(String currentUserId, String targetUserId) async {
    if (currentUserId == targetUserId) return; // Cannot follow self
    try {
      // Add target to current user's following list
      await _firestore
          .collection('users')
          .doc(currentUserId)
          .collection('following')
          .doc(targetUserId)
          .set({}); // Using an empty map, can add timestamp if needed

      // Add current user to target's followers list
      await _firestore
          .collection('users')
          .doc(targetUserId)
          .collection('followers')
          .doc(currentUserId)
          .set({});
    } catch (e) {
      print('Error following user $targetUserId: $e');
      rethrow; // Rethrow to allow UI to handle it
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
}
