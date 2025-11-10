const functions = require("firebase-functions");
const admin = require("firebase-admin");

/**
 * Deletes all data associated with a user from Firestore and Storage.
 *
 * This function is triggered when a user account is deleted from Firebase Authentication.
 * It recursively deletes all collections and documents associated with the user.
 */
exports.deleteUserData = functions.auth.user().onDelete(async (user) => {
  const { uid } = user;
  console.log(`Starting deletion for user: ${uid}`);

  try {
    // Path to the user's document in the 'users' collection
    const userDocRef = admin.firestore().collection("users").doc(uid);

    // Recursively delete the user's document and all its subcollections
    await admin.firestore().recursiveDelete(userDocRef);
    console.log(`Successfully deleted all Firestore data for user: ${uid}`);

    // Delete user's files from Firebase Storage
    const bucket = admin.storage().bucket();
    const userPhotoFolder = `user_photos/${uid}`;
    await bucket.deleteFiles({ prefix: userPhotoFolder });
    console.log(`Successfully deleted storage folder: ${userPhotoFolder}`);

    // You can add more deletion logic here for other storage paths if needed
    // For example, if users can upload to other folders:
    // const userUploadsFolder = `user_uploads/${uid}`;
    // await bucket.deleteFiles({ prefix: userUploadsFolder });
    // console.log(`Successfully deleted storage folder: ${userUploadsFolder}`);
  } catch (error) {
    console.error(`Error deleting user data for ${uid}:`, error);
  }
});
