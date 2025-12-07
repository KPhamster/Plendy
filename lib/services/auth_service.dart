import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'user_service.dart';
import 'experience_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'dart:async'; // For Timer
import 'notification_state_service.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final UserService _userService = UserService();
  final ExperienceService _experienceService = ExperienceService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  User? _currentUser;
  Stream<User?>? _authStateChanges;
  
  // Prevent duplicate FCM setup
  bool _fcmSetupComplete = false;
  Future<void>? _fcmSetupInProgress;
  StreamSubscription<String>? _tokenRefreshSubscription;

  AuthService() {
    _currentUser = _auth.currentUser;
    _authStateChanges = _auth.authStateChanges();
    _authStateChanges!.listen((User? user) {
      _currentUser = user;
      if (user != null) {
        // Delay FCM setup slightly to allow UI to settle
        Timer(const Duration(milliseconds: 500),
            () => _setupFcmForUser(user.uid));
        // Update timezone if not already stored
        Timer(const Duration(milliseconds: 500),
            () => _ensureTimezoneStored(user.uid));
      } else {
        // Optional: If user logs out, you might want to delete their old token or handle it.
        // For simplicity, we are not deleting tokens on logout here, but it's a consideration.
      }
      notifyListeners();
    });
    // Initial setup if user is already logged in when AuthService is instantiated
    if (_currentUser != null) {
      // Delay FCM setup slightly for initial logged-in state too
      Timer(const Duration(milliseconds: 500),
          () => _setupFcmForUser(_currentUser!.uid));
      Timer(const Duration(milliseconds: 500),
          () => _ensureTimezoneStored(_currentUser!.uid));
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
        // Capture timezone on first sign up
        final timezoneOffsetMinutes = -DateTime.now().timeZoneOffset.inMinutes;
        await _userService.updateUserCoreData(credential.user!.uid, {
          'hasCompletedOnboarding': false,
          'hasFinishedOnboardingFlow': false,
          'timezoneOffsetMinutes': timezoneOffsetMinutes,
          'emailVerified': false,
          'emailVerificationSentAt': FieldValue.serverTimestamp(),
          'emailVerificationResendCount': 0,
        });

        // Send email verification immediately after signup
        await sendEmailVerification();

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

  // Send Password Reset Email using Firebase Auth
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      print('DEBUG: Attempting to send password reset email to: $email');
      
      // Use Firebase Auth's built-in password reset email
      await _auth.sendPasswordResetEmail(email: email.trim());
      
      print('DEBUG: Password reset email sent successfully to: $email');
    } on FirebaseAuthException catch (e) {
      print('DEBUG: Firebase Auth error: ${e.code} - ${e.message}');
      
      String message;
      switch (e.code) {
        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;
        case 'user-not-found':
          // For security, don't reveal if user exists or not
          message = 'If an account exists with this email, a password reset link has been sent.';
          break;
        case 'too-many-requests':
          message = 'Too many attempts. Please try again later.';
          break;
        default:
          message = e.message ?? 'Failed to send reset email. Please try again.';
      }
      throw Exception(message);
    } catch (e) {
      print('DEBUG: Generic error during password reset: $e');
      throw Exception('Failed to send reset email. Please try again.');
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
          // Capture timezone on first sign in
          final timezoneOffsetMinutes = -DateTime.now().timeZoneOffset.inMinutes;
          await _userService.updateUserCoreData(userCredential.user!.uid, {
            'hasCompletedOnboarding': false,
            'hasFinishedOnboardingFlow': false,
            'timezoneOffsetMinutes': timezoneOffsetMinutes,
          });
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

  // Apple Sign In
  Future<UserCredential?> signInWithApple() async {
    UserCredential? userCredential;
    try {
      // Request Apple ID credential
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      // Create an OAuth credential for Firebase
      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      // Sign in to Firebase with the Apple credential
      userCredential = await _auth.signInWithCredential(oauthCredential);
      print(
          "Firebase authentication with Apple successful for UID: ${userCredential.user?.uid}");

      // Save user email to Firestore (only if user exists)
      if (userCredential.user != null) {
        // For Apple Sign In, email might be null if user chose to hide it
        // Use the email from appleCredential if available
        String? email = userCredential.user!.email ?? appleCredential.email;
        
        if (email != null && email.isNotEmpty) {
          await _userService.saveUserEmail(userCredential.user!.uid, email);
        } else {
          print("Warning: Apple user has no email address.");
        }

        // Check if this is a new user and initialize default categories if needed
        final bool isNewUser =
            userCredential.additionalUserInfo?.isNewUser ?? false;
        print("Is new Apple user? $isNewUser");

        if (isNewUser) {
          print(
              "Attempting to initialize default categories for new Apple user...");
          // Capture timezone on first sign in
          final timezoneOffsetMinutes = -DateTime.now().timeZoneOffset.inMinutes;
          await _userService.updateUserCoreData(userCredential.user!.uid, {
            'hasCompletedOnboarding': false,
            'hasFinishedOnboardingFlow': false,
            'timezoneOffsetMinutes': timezoneOffsetMinutes,
          });
          
          try {
            // Use Future.wait to run initializations concurrently but wait for both
            await Future.wait([
              _experienceService
                  .initializeDefaultUserCategories(userCredential.user!.uid),
              _experienceService.initializeDefaultUserColorCategories(
                  userCredential.user!.uid),
            ]);
            print(
                "Default text & color categories initialization successful for new Apple user: ${userCredential.user!.uid}");
          } catch (e) {
            print(
                "CRITICAL ERROR: Failed to initialize default categories for new Apple user: $e");
            // Rethrow the error to make the sign-in fail if setup fails.
            rethrow;
          }
        }
      } else {
        print(
            "Warning: userCredential.user is null after Apple Sign In. Cannot save email or initialize categories.");
      }

      return userCredential;
    } on SignInWithAppleAuthorizationException catch (e) {
      print("Apple Sign In authorization error: ${e.code} - ${e.message}");
      // User cancelled or authorization failed
      if (e.code == AuthorizationErrorCode.canceled) {
        print("Apple Sign In cancelled by user.");
        return null;
      }
      rethrow;
    } on FirebaseAuthException catch (e) {
      print(
          "FirebaseAuthException during Apple Sign In: ${e.code} - ${e.message}");
      rethrow;
    } catch (e) {
      print("Generic error during Apple Sign In: $e");
      // Sign out the user from Firebase if an unexpected error occurred
      if (userCredential?.user != null) {
        print("Signing out user due to error during post-auth setup...");
        await signOut();
      }
      rethrow;
    }
  }

  // Send Email Verification
  Future<void> sendEmailVerification() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('No user logged in');
      }

      if (user.emailVerified) {
        print('DEBUG: User email already verified');
        return;
      }

      // Check rate limiting
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final userData = userDoc.data();
        final resendCount = userData?['emailVerificationResendCount'] ?? 0;
        final lastResendAt = userData?['emailVerificationLastResendAt'] as Timestamp?;

        // Rate limit: max 3 resends per hour
        if (lastResendAt != null && resendCount >= 3) {
          final hourAgo = DateTime.now().subtract(const Duration(hours: 1));
          if (lastResendAt.toDate().isAfter(hourAgo)) {
            throw Exception('Too many verification emails sent. Please try again later.');
          }
        }
      }

      // Send email verification (simple mode without dynamic links)
      await user.sendEmailVerification();
      
      print('DEBUG: Email verification sent to ${user.email}');

      // Update Firestore with send tracking
      await _firestore.collection('users').doc(user.uid).update({
        'emailVerificationLastResendAt': FieldValue.serverTimestamp(),
        'emailVerificationResendCount': FieldValue.increment(1),
      });
    } on FirebaseAuthException catch (e) {
      print('DEBUG: Firebase Auth error sending verification: ${e.code} - ${e.message}');
      if (e.code == 'too-many-requests') {
        throw Exception('Too many requests. Please wait a few minutes before trying again.');
      }
      rethrow;
    } catch (e) {
      print('DEBUG: Error sending email verification: $e');
      rethrow;
    }
  }

  // Check if current user's email is verified
  Future<bool> checkEmailVerified() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // Reload user to get fresh email verification status
      await user.reload();
      final refreshedUser = _auth.currentUser;
      
      if (refreshedUser != null && refreshedUser.emailVerified) {
        // Update Firestore to reflect verification
        await _firestore.collection('users').doc(refreshedUser.uid).update({
          'emailVerified': true,
          'emailVerifiedAt': FieldValue.serverTimestamp(),
        });
        return true;
      }
      
      return false;
    } catch (e) {
      print('DEBUG: Error checking email verification: $e');
      return false;
    }
  }

  // Get email verification status without reloading
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  // Resend verification email with rate limiting
  Future<void> resendVerificationEmail() async {
    await sendEmailVerification();
  }

  // Sign Out
  Future<void> signOut() async {
    // Clean up notification state service listeners BEFORE signing out
    // to prevent permission-denied errors from active Firestore listeners
    final notificationService = NotificationStateService();
    notificationService.cleanup();

    // Clean up FCM state
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _fcmSetupComplete = false;
    _fcmSetupInProgress = null;

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

  Future<void> reloadCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.reload();
    _currentUser = _auth.currentUser;
    notifyListeners();
  }

  Future<void> _setupFcmForUser(String userId) async {
    if (kIsWeb) return; // FCM setup for web is different, skipping for now

    // Prevent duplicate setup - if already complete, skip
    if (_fcmSetupComplete) {
      print('DEBUG: FCM already set up, skipping duplicate setup');
      return;
    }

    // If setup is in progress, wait for it to complete instead of starting a new one
    if (_fcmSetupInProgress != null) {
      print('DEBUG: FCM setup already in progress, waiting for it to complete...');
      await _fcmSetupInProgress;
      return;
    }

    // Mark as in-progress immediately to prevent concurrent calls
    _fcmSetupInProgress = _performFcmSetup(userId);
    await _fcmSetupInProgress;
    _fcmSetupInProgress = null;
  }

  Future<void> _performFcmSetup(String userId) async {
    _fcmSetupComplete = true; // Set immediately to prevent retries

    try {
      print('Setting up FCM for user: $userId');

      // Check current permission status first
      NotificationSettings currentSettings =
          await _firebaseMessaging.getNotificationSettings();
      print(
          'Current FCM permission status: ${currentSettings.authorizationStatus}');

      // Only request permission if not already granted
      if (currentSettings.authorizationStatus ==
          AuthorizationStatus.notDetermined) {
        print('Requesting FCM permission...');

        // Request permission with timeout to prevent freezing
        NotificationSettings settings = await _firebaseMessaging
            .requestPermission(
          alert: true,
          announcement: false,
          badge: true,
          carPlay: false,
          criticalAlert: false,
          provisional: false,
          sound: true,
          providesAppNotificationSettings: true,
        )
            .timeout(
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

        print(
            'FCM permission request completed with status: ${settings.authorizationStatus}');
        currentSettings = settings;
      }

      // Handle the permission result
      if (currentSettings.authorizationStatus ==
          AuthorizationStatus.authorized) {
        print('User granted FCM permission');
        await _setupFcmToken(userId);
      } else if (currentSettings.authorizationStatus ==
          AuthorizationStatus.provisional) {
        print('User granted provisional FCM permission');
        await _setupFcmToken(userId);
      } else {
        print(
            'User declined or has not accepted FCM permission: ${currentSettings.authorizationStatus}');
        if (currentSettings.authorizationStatus == AuthorizationStatus.denied) {
          print(
              'FCM: Permission denied. User needs to manually enable notifications in device settings.');
          // TODO: You could show a dialog here guiding the user to enable notifications manually
          // or implement a method to open device settings
        }
        // Don't set up token if permission denied
        _fcmSetupComplete = false; // Reset flag if permission denied
      }
    } catch (e) {
      print("Error setting up FCM for user $userId: $e");
      _fcmSetupComplete = false; // Reset flag on error
      // Don't rethrow - FCM setup failure shouldn't break the app
    }
  }

  Future<void> _setupFcmToken(String userId) async {
    try {
      print('DEBUG: Getting FCM token for user $userId...');
      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        print(
            'DEBUG: Got FCM token: ${token.substring(0, 50)}...'); // Show first 50 chars
        await _saveTokenToFirestore(userId, token);

        // Cancel any existing token refresh subscription
        await _tokenRefreshSubscription?.cancel();
        
        // Listen for token refresh (only once)
        _tokenRefreshSubscription = _firebaseMessaging.onTokenRefresh.listen((newToken) {
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

  /// Ensure user's timezone is stored in their profile
  Future<void> _ensureTimezoneStored(String userId) async {
    try {
      // Check if timezone is already stored
      final userDoc = await _firestore.collection('users').doc(userId).get();
      
      if (!userDoc.exists) {
        print('DEBUG: User doc does not exist for $userId');
        return;
      }
      
      final userData = userDoc.data();
      if (userData == null) {
        print('DEBUG: User data is null for $userId');
        return;
      }
      
      // If timezone is already stored, skip
      if (userData.containsKey('timezoneOffsetMinutes') && 
          userData['timezoneOffsetMinutes'] != null) {
        print('DEBUG: Timezone already stored for user $userId');
        return;
      }
      
      // Capture and store current timezone
      final timezoneOffsetMinutes = -DateTime.now().timeZoneOffset.inMinutes;
      await _userService.updateUserCoreData(userId, {
        'timezoneOffsetMinutes': timezoneOffsetMinutes,
      });
      print('DEBUG: Stored timezone offset $timezoneOffsetMinutes minutes for user $userId');
    } catch (e) {
      print('DEBUG: Error ensuring timezone stored for $userId: $e');
      // Don't rethrow - timezone storage failure shouldn't break the app
    }
  }

  Future<void> _saveTokenToFirestore(String userId, String token) async {
    if (userId.isEmpty || token.isEmpty) {
      print(
          "DEBUG: Cannot save FCM token - userId: '${userId}', token: '${token.isEmpty ? 'empty' : 'not empty'}'");
      return;
    }
    try {
      print('DEBUG: Saving FCM token to Firestore for user $userId...');
      
      // Check if this exact token already exists - if so, skip
      final tokenDoc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('fcmTokens')
          .doc(token)
          .get();
      
      if (tokenDoc.exists) {
        print('DEBUG: Token already exists in Firestore, skipping save');
        return;
      }
      
      // Use a batch write to ensure atomicity
      final batch = _firestore.batch();
      
      // Get all existing tokens for this device/platform and delete them
      final existingTokens = await _firestore
          .collection('users')
          .doc(userId)
          .collection('fcmTokens')
          .where('platform', isEqualTo: defaultTargetPlatform.toString())
          .get();
      
      // Delete old tokens for this platform in the batch
      int deletedCount = 0;
      for (var doc in existingTokens.docs) {
        if (doc.id != token) {
          batch.delete(doc.reference);
          deletedCount++;
          print('DEBUG: Marked old FCM token for deletion: ${doc.id.substring(0, 20)}...');
        }
      }
      
      // Save the new token in the batch
      final tokenRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('fcmTokens')
          .doc(token);
      
      batch.set(tokenRef, {
        'createdAt': FieldValue.serverTimestamp(),
        'platform': defaultTargetPlatform.toString(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      // Commit the batch
      await batch.commit();
      print("DEBUG: FCM token successfully saved for user $userId (deleted $deletedCount old tokens)");
    } catch (e) {
      print("DEBUG: Error saving FCM token for user $userId: $e");
    }
  }

  // Method to manually check and request FCM permissions
  Future<void> checkAndRequestFcmPermissions() async {
    if (kIsWeb) return;

    try {
      print('DEBUG: Checking FCM permission status...');
      NotificationSettings settings =
          await _firebaseMessaging.getNotificationSettings();
      print('DEBUG: Current FCM permission: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        print(
            'DEBUG: FCM permission denied. User needs to enable notifications manually.');
        print(
            'DEBUG: Guide user to: Settings > Apps > Plendy > Notifications > Allow notifications');
      } else if (settings.authorizationStatus ==
          AuthorizationStatus.notDetermined) {
        print('DEBUG: FCM permission not determined. Requesting permission...');
        final newSettings = await _firebaseMessaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        print(
            'DEBUG: Permission request result: ${newSettings.authorizationStatus}');
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
        'tokenIds':
            tokensSnapshot.docs.map((doc) => doc.id.substring(0, 20)).toList(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Clean up duplicate FCM tokens manually
  Future<void> cleanupDuplicateFcmTokens() async {
    if (kIsWeb) return;
    
    try {
      final user = _currentUser;
      if (user == null) {
        print('DEBUG: Cannot cleanup tokens - no user logged in');
        return;
      }

      final currentToken = await _firebaseMessaging.getToken();
      if (currentToken == null) {
        print('DEBUG: Cannot cleanup tokens - no current token');
        return;
      }

      print('DEBUG: Cleaning up duplicate FCM tokens...');
      print('DEBUG: Current user: ${user.uid}');
      print('DEBUG: Current token: ${currentToken.substring(0, 30)}...');
      
      // Get all tokens for this user
      final tokensSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('fcmTokens')
          .get();

      print('DEBUG: Found ${tokensSnapshot.docs.length} tokens in Firestore for this user');

      // Delete all tokens except the current one
      int deletedCount = 0;
      for (var doc in tokensSnapshot.docs) {
        if (doc.id != currentToken) {
          await doc.reference.delete();
          deletedCount++;
          print('DEBUG: Deleted token: ${doc.id.substring(0, 20)}...');
        }
      }

      print('DEBUG: Cleanup complete - deleted $deletedCount duplicate tokens');
      print('DEBUG: ✅ Token cleanup finished');
    } catch (e) {
      print('DEBUG: Error cleaning up FCM tokens: $e');
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
