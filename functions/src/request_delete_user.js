const functions = require("firebase-functions");
const admin = require("firebase-admin");
const cors = require("cors")({ origin: true });

/**
 * An HTTP-triggered Cloud Function to handle user data deletion requests.
 * Requires a valid Firebase Auth ID token in the Authorization header.
 * Only the authenticated user can delete their own account.
 */
exports.requestUserDataDeletion = functions.https.onRequest((req, res) => {
  cors(req, res, async () => {
    if (req.method !== "POST") {
      return res.status(405).json({ message: "Method Not Allowed" });
    }

    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return res.status(401).json({
        message: "Unauthorized: Please sign in to delete your account.",
      });
    }

    const idToken = authHeader.split("Bearer ")[1];

    try {
      const decodedToken = await admin.auth().verifyIdToken(idToken);
      const { uid } = decodedToken;
      console.log(`Authenticated deletion request from user: ${uid}`);

      await admin.auth().deleteUser(uid);
      console.log(`Successfully deleted user: ${uid}`);

      return res.status(200).json({
        message: "Your account has been successfully deleted.",
      });
    } catch (error) {
      if (
        error.code === "auth/id-token-expired" ||
        error.code === "auth/id-token-revoked"
      ) {
        return res.status(401).json({
          message: "Session expired. Please sign in again.",
        });
      }
      if (
        error.code === "auth/invalid-id-token" ||
        error.code === "auth/argument-error"
      ) {
        return res.status(401).json({
          message: "Invalid authentication. Please sign in again.",
        });
      }
      console.error("Error processing deletion:", error);
      return res.status(500)
        .json({ message: "An internal error occurred." });
    }
  });
});
