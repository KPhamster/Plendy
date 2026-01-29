const { user } = require("firebase-functions/v1/auth");
const admin = require("firebase-admin");
const functions = require("firebase-functions");

/**
 * Deletes all data associated with a user from Firestore and Storage.
 *
 * This function is triggered when a user account is deleted from Firebase Authentication.
 * It recursively deletes all collections and documents associated with the user.
 */
exports.deleteUserData = user().onDelete(async (userRecord) => {
  const { uid } = userRecord;
  functions.logger.log(`Starting deletion for user: ${uid}`);

  try {
    const db = admin.firestore();

    // Path to the user's document in the 'users' collection
    const userDocRef = db.collection("users").doc(uid);

    // First, fetch the user document to get the username for cleanup
    const userDoc = await userDocRef.get();
    let lowercaseUsername = null;

    if (userDoc.exists) {
      const userData = userDoc.data();
      lowercaseUsername = userData?.lowercaseUsername;
      functions.logger.log(`Found user document with lowercaseUsername: ${lowercaseUsername}`);
    } else {
      functions.logger.log(`User document not found for uid: ${uid}`);
    }

    // Delete the username reservation document if it exists
    if (lowercaseUsername) {
      const usernameDocRef = db.collection("usernames").doc(lowercaseUsername);
      await usernameDocRef.delete();
      functions.logger.log(`Successfully deleted username document: ${lowercaseUsername}`);
    }

    // Recursively delete the user's document and all its subcollections
    await db.recursiveDelete(userDocRef);
    functions.logger.log(`Successfully deleted all Firestore data for user: ${uid}`);

    // Delete user's files from Firebase Storage
    const bucket = admin.storage().bucket();
    const userPhotoFolder = `user_photos/${uid}`;
    await bucket.deleteFiles({ prefix: userPhotoFolder });
    functions.logger.log(`Successfully deleted storage folder: ${userPhotoFolder}`);
  } catch (error) {
    functions.logger.error(`Error deleting user data for ${uid}:`, error);
  }
});
