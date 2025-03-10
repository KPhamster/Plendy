import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
}
