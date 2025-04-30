import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'user_service.dart';
import 'experience_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final UserService _userService = UserService();
  final ExperienceService _experienceService = ExperienceService();

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state changes stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

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
          await _experienceService
              .initializeDefaultUserCategories(credential.user!.uid);
          print(
              "Default categories initialized for new user: ${credential.user!.uid}");
          await _experienceService
              .initializeDefaultUserColorCategories(credential.user!.uid);
          print(
              "Default COLOR categories initialized for new user: ${credential.user!.uid}");
        } catch (e) {
          print("Error initializing default categories: $e");
          // Don't rethrow - allow registration to succeed even if category init fails
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
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);

      // Save user email to Firestore
      if (userCredential.user != null && userCredential.user!.email != null) {
        await _userService.saveUserEmail(
            userCredential.user!.uid, userCredential.user!.email!);

        // Check if this is a new user and initialize default categories if needed
        if (userCredential.additionalUserInfo?.isNewUser == true) {
          try {
            await _experienceService
                .initializeDefaultUserCategories(userCredential.user!.uid);
            print(
                "Default categories initialized for new Google user: ${userCredential.user!.uid}");
            await _experienceService
                .initializeDefaultUserColorCategories(userCredential.user!.uid);
            print(
                "Default COLOR categories initialized for new Google user: ${userCredential.user!.uid}");
          } catch (e) {
            print("Error initializing default categories: $e");
            // Don't rethrow - allow sign-in to succeed even if category init fails
          }
        }
      }

      return userCredential;
    } catch (e) {
      rethrow;
    }
  }

  // Sign Out
  Future<void> signOut() async {
    try {
      await Future.wait([
        _auth.signOut(),
        _googleSignIn.signOut(),
      ]);
    } catch (e) {
      rethrow;
    }
  }
}
