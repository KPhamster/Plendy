import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'user_service.dart';
import 'experience_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'dart:async'; // For Timer

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final UserService _userService = UserService();
  final ExperienceService _experienceService = ExperienceService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  User? _currentUser;
  Stream<User?>? _authStateChanges;

  AuthService() {
    _currentUser = _auth.currentUser;
    _authStateChanges = _auth.authStateChanges();
    _authStateChanges!.listen((User? user) {
      _currentUser = user;
      if (user != null) {
        // Delay FCM setup slightly to allow UI to settle
        Timer(const Duration(milliseconds: 500), () => _setupFcmForUser(user.uid));
      } else {
        // Optional: If user logs out, you might want to delete their old token or handle it.
        // For simplicity, we are not deleting tokens on logout here, but it's a consideration.
      }
      notifyListeners();
    });
    // Initial setup if user is already logged in when AuthService is instantiated
    if (_currentUser != null) {
      // Delay FCM setup slightly for initial logged-in state too
      Timer(const Duration(milliseconds: 500), () => _setupFcmForUser(_currentUser!.uid));
    }
  }

  // Get current user
  User? get currentUser => _currentUser;

  // Auth state changes stream
  Stream<User?>? get authStateChanges => _authStateChanges;

  // Email/Password Sign Up
  Future<UserCredential> signUpWithEmail(String email, String password) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Save user email to Firestore
      if (credential.user != null) {
        await _userService.saveUserEmail(credential.user!.uid, email);

        // Initialize default categories for new user
        try {
          await Future.wait([
            _experienceService
                .initializeDefaultUserCategories(credential.user!.uid),
            _experienceService
                .initializeDefaultUserColorCategories(credential.user!.uid),
          ]);
          print(
              "Default text & color categories initialization awaited for new user: ${credential.user!.uid}");
        } catch (e) {
          print("Error initializing default categories during sign up: $e");
          // Don't rethrow - allow registration to succeed even if category init fails
          // The user might just not have default categories immediately.
          // Rethrowing here might be too strict for registration.
        }
      }

      return credential;
    } catch (e) {
      rethrow;
    }
  }

  // Email/Password Sign In
  Future<UserCredential> signInWithEmail(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      rethrow;
    }
  }

  // Google Sign In
  Future<UserCredential?> signInWithGoogle() async {
    UserCredential? userCredential;
    try {
      if (kIsWeb) {
        // On web, use Firebase Auth popup to avoid null token issues
        final provider = GoogleAuthProvider();
        provider.setCustomParameters({
          'prompt': 'select_account',
        });
        userCredential = await _auth.signInWithPopup(provider);
      } else {
        // On mobile/desktop, use google_sign_in to obtain OAuth tokens
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          print("Google Sign In cancelled by user.");
          return null; // User cancelled the flow
        }

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;

        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        // Authenticate with Firebase
        userCredential = await _auth.signInWithCredential(credential);
      }
      print(
          "Firebase authentication with Google successful for UID: ${userCredential.user?.uid}");

      // Save user email to Firestore (only if user exists)
      if (userCredential.user != null) {
        if (userCredential.user!.email != null) {
          await _userService.saveUserEmail(
              userCredential.user!.uid, userCredential.user!.email!);
        } else {
          print("Warning: Google user has no email address.");
          // Decide how to handle users without email - maybe save a placeholder?
          // await _userService.saveUserEmail(userCredential.user!.uid, "no-email@google.com");
        }

        // Check if this is a new user and initialize default categories if needed
        final bool isNewUser =
            userCredential.additionalUserInfo?.isNewUser ?? false;
        print("Is new Google user? $isNewUser");

        if (isNewUser) {
          print(
              "Attempting to initialize default categories for new Google user...");
          // --- MODIFIED: Rethrow initialization errors --- START ---
          try {
            // Use Future.wait to run initializations concurrently but wait for both
            await Future.wait([
              _experienceService
                  .initializeDefaultUserCategories(userCredential.user!.uid),
              _experienceService.initializeDefaultUserColorCategories(
                  userCredential.user!.uid),
            ]);
            print(
                "Default text & color categories initialization successful for new Google user: ${userCredential.user!.uid}");
          } catch (e) {
            print(
                "CRITICAL ERROR: Failed to initialize default categories for new Google user: $e");
            // Rethrow the error to make the sign-in fail if setup fails.
            // This prevents users being logged in without essential default data.
            rethrow;
          }
          // --- MODIFIED: Rethrow initialization errors --- END ---
        }
      } else {
        print(
            "Warning: userCredential.user is null after Google Sign In. Cannot save email or initialize categories.");
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      print(
          "FirebaseAuthException during Google Sign In: ${e.code} - ${e.message}");
      // Handle specific Firebase errors if needed (e.g., account-exists-with-different-credential)
      rethrow; // Rethrow Firebase specific errors
    } catch (e) {
      print("Generic error during Google Sign In: $e");
      // Also sign out the user from Firebase if an unexpected error occurred after potential sign-in
      // but before initialization finished, to avoid inconsistent state.
      if (userCredential?.user != null) {
        print("Signing out user due to error during post-auth setup...");
        await signOut();
      }
      rethrow; // Rethrow other errors
    }
  }

  // Sign Out
  Future<void> signOut() async {
    // Optional: Before signing out, you might want to delete the current device's FCM token 
    // from the user's list if you have a way to identify it specifically.
    // String? token = await _firebaseMessaging.getToken();
    // if (currentUser != null && token != null) {
    //   await _deleteTokenFromFirestore(currentUser!.uid, token);
    // }
    await _auth.signOut();
    await _googleSignIn.signOut();
    _currentUser = null;
    notifyListeners();
  }

  Future<void> _setupFcmForUser(String userId) async {
    if (kIsWeb) return; // FCM setup for web is different, skipping for now

    try {
      print('Setting up FCM for user: $userId');
      
      // Check current permission status first
      NotificationSettings currentSettings = await _firebaseMessaging.getNotificationSettings();
      print('Current FCM permission status: ${currentSettings.authorizationStatus}');
      
      // Only request permission if not already granted
      if (currentSettings.authorizationStatus == AuthorizationStatus.notDetermined) {
        print('Requesting FCM permission...');
        
        // Request permission with timeout to prevent freezing
        NotificationSettings settings = await _firebaseMessaging.requestPermission(
          alert: true,
          announcement: false,
          badge: true,
          carPlay: false,
          criticalAlert: false,
          provisional: false,
          sound: true,
          providesAppNotificationSettings: true,
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            print('FCM permission request timed out');
            return const NotificationSettings(
              authorizationStatus: AuthorizationStatus.denied,
              alert: AppleNotificationSetting.disabled,
              announcement: AppleNotificationSetting.disabled,
              badge: AppleNotificationSetting.disabled,
              carPlay: AppleNotificationSetting.disabled,
              lockScreen: AppleNotificationSetting.disabled,
              notificationCenter: AppleNotificationSetting.disabled,
              showPreviews: AppleShowPreviewSetting.never,
              timeSensitive: AppleNotificationSetting.disabled,
              criticalAlert: AppleNotificationSetting.disabled,
              sound: AppleNotificationSetting.disabled,
              providesAppNotificationSettings: AppleNotificationSetting.enabled,
            );
          },
        );
        
        print('FCM permission request completed with status: ${settings.authorizationStatus}');
        currentSettings = settings;
      }

      // Handle the permission result
      if (currentSettings.authorizationStatus == AuthorizationStatus.authorized) {
        print('User granted FCM permission');
        await _setupFcmToken(userId);
      } else if (currentSettings.authorizationStatus == AuthorizationStatus.provisional) {
        print('User granted provisional FCM permission');
        await _setupFcmToken(userId);
      } else {
        print('User declined or has not accepted FCM permission: ${currentSettings.authorizationStatus}');
        if (currentSettings.authorizationStatus == AuthorizationStatus.denied) {
          print('FCM: Permission denied. User needs to manually enable notifications in device settings.');
          // TODO: You could show a dialog here guiding the user to enable notifications manually
          // or implement a method to open device settings
        }
        // Don't set up token if permission denied
      }
    } catch (e) {
      print("Error setting up FCM for user $userId: $e");
      // Don't rethrow - FCM setup failure shouldn't break the app
    }
  }

  Future<void> _setupFcmToken(String userId) async {
    try {
      print('DEBUG: Getting FCM token for user $userId...');
      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        print('DEBUG: Got FCM token: ${token.substring(0, 50)}...'); // Show first 50 chars
        await _saveTokenToFirestore(userId, token);
        
        // Listen for token refresh
        _firebaseMessaging.onTokenRefresh.listen((newToken) {
          print('DEBUG: FCM token refreshed: ${newToken.substring(0, 50)}...');
          _saveTokenToFirestore(userId, newToken);
        });
      } else {
        print('DEBUG: Failed to get FCM token - token is null');
      }
    } catch (e) {
      print("DEBUG: Error setting up FCM token for user $userId: $e");
    }
  }

  Future<void> _saveTokenToFirestore(String userId, String token) async {
    if (userId.isEmpty || token.isEmpty) {
      print("DEBUG: Cannot save FCM token - userId: '${userId}', token: '${token.isEmpty ? 'empty' : 'not empty'}'");
      return;
    }
    try {
      print('DEBUG: Saving FCM token to Firestore for user $userId...');
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('fcmTokens')
          .doc(token) // Use token as document ID for easy add/delete
          .set({
            'createdAt': FieldValue.serverTimestamp(),
            'platform': defaultTargetPlatform.toString(), // Optional: store platform
          });
      print("DEBUG: FCM token successfully saved for user $userId");
    } catch (e) {
      print("DEBUG: Error saving FCM token for user $userId: $e");
    }
  }

  // Method to manually check and request FCM permissions
  Future<void> checkAndRequestFcmPermissions() async {
    if (kIsWeb) return;
    
    try {
      print('DEBUG: Checking FCM permission status...');
      NotificationSettings settings = await _firebaseMessaging.getNotificationSettings();
      print('DEBUG: Current FCM permission: ${settings.authorizationStatus}');
      
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        print('DEBUG: FCM permission denied. User needs to enable notifications manually.');
        print('DEBUG: Guide user to: Settings > Apps > Plendy > Notifications > Allow notifications');
      } else if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        print('DEBUG: FCM permission not determined. Requesting permission...');
        final newSettings = await _firebaseMessaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        print('DEBUG: Permission request result: ${newSettings.authorizationStatus}');
      } else {
        print('DEBUG: FCM permission granted: ${settings.authorizationStatus}');
      }
    } catch (e) {
      print('DEBUG: Error checking FCM permissions: $e');
    }
  }
  
  // Method to get FCM token info for debugging
  Future<Map<String, dynamic>> getFcmDebugInfo() async {
    if (kIsWeb) return {'error': 'Web not supported'};
    
    try {
      final user = _currentUser;
      if (user == null) {
        return {'error': 'No user logged in'};
      }
      
      final settings = await _firebaseMessaging.getNotificationSettings();
      final token = await _firebaseMessaging.getToken();
      
      // Check if token exists in Firestore
      final tokensSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('fcmTokens')
          .get();
      
      return {
        'userId': user.uid,
        'permissionStatus': settings.authorizationStatus.toString(),
        'hasToken': token != null,
        'tokenPreview': token?.substring(0, 50) ?? 'null',
        'tokensInFirestore': tokensSnapshot.docs.length,
        'tokenIds': tokensSnapshot.docs.map((doc) => doc.id.substring(0, 20)).toList(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // Optional: Method to delete a specific token (e.g., on sign out for this device)
  // Future<void> _deleteTokenFromFirestore(String userId, String token) async {
  //   if (userId.isEmpty || token.isEmpty) return;
  //   try {
  //     await _firestore
  //         .collection('users')
  //         .doc(userId)
  //         .collection('fcmTokens')
  //         .doc(token)
  //         .delete();
  //     print("FCM token deleted for user $userId: $token");
  //   } catch (e) {
  //     print("Error deleting FCM token for user $userId: $e");
  //   }
  // }
}
