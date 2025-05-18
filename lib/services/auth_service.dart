import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'user_service.dart';
import 'experience_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: "449728842508-2o1dfbn37370v03t3qald1756iim4i4f.apps.googleusercontent.com", // Add your Web Client ID here
  );
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
    try {
      print("Signing out from Firebase and Google...");
      await Future.wait([
        _auth.signOut(),
        _googleSignIn.signOut(), // Ensure Google Sign In is also cleared
      ]);
      print("Sign out successful.");
    } catch (e) {
      print("Error during sign out: $e");
      rethrow;
    }
  }
}
