const functions = require("firebase-functions");
const admin = require("firebase-admin");
const cors = require("cors")({ origin: true });

/**
 * An HTTP-triggered Cloud Function to handle user data deletion requests.
 * @param {functions.https.Request} req The request object.
 * @param {functions.https.Response} res The response object.
 */
exports.requestUserDataDeletion = functions.https.onRequest((req, res) => {
  cors(req, res, async () => {
    if (req.method !== "POST") {
      return res.status(405).json({ message: "Method Not Allowed" });
    }

    const { email } = req.body;

    if (!email || typeof email !== "string") {
      return res.status(400)
        .json({ message: "Invalid request: Please provide a valid email." });
    }

    try {
      const userRecord = await admin.auth().getUserByEmail(email);
      const { uid } = userRecord;
      console.log(`Found user ${uid} for email ${email}. Deleting.`);

      await admin.auth().deleteUser(uid);
      console.log(`Successfully initiated deletion for user: ${uid}`);

      return res.status(200).json({
        message: "Request received. Your account will be deleted.",
      });
    } catch (error) {
      if (error.code === "auth/user-not-found") {
        console.log(`No user found with email: ${email}`);
        return res.status(200).json({
          message: "If an account with this email exists, it will be deleted.",
        });
      }
      console.error(`Error processing deletion for ${email}:`, error);
      return res.status(500)
        .json({ message: "An internal error occurred." });
    }
  });
});
