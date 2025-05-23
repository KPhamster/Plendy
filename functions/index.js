// functions/index.js
const { getFirestore } = require("firebase-admin/firestore"); // For interacting with Firestore
const { onDocumentCreated } = require("firebase-functions/v2/firestore"); // For 2nd gen Firestore triggers
const functions = require("firebase-functions"); // Still needed for logger, config, etc.
const admin = require("firebase-admin");

admin.initializeApp();

const db = getFirestore(); // Use getFirestore() from firebase-admin/firestore
const messaging = admin.messaging();


/**
 * Sends a notification when a new follow request is created (2nd Gen).
 */
exports.sendFollowRequestNotificationV2 = onDocumentCreated(
  "users/{targetUserId}/followRequests/{requesterId}",
  async (event) => {
    const snapshot = event.data; // The DocumentSnapshot
    if (!snapshot) {
      functions.logger.log("No data associated with the event");
      return;
    }
    // const data = snapshot.data(); // Data of the created document

    const targetUserId = event.params.targetUserId;
    const requesterId = event.params.requesterId;

    functions.logger.log(
      `V2: New follow request from ${requesterId} to ${targetUserId}`,
    );

    try {
      const requesterDoc = await db.collection("users").doc(requesterId).get();
      const requesterProfile = requesterDoc.data();
      const requesterName = requesterProfile?.displayName || requesterProfile?.username || "Someone";

      const tokensSnapshot = await db
        .collection("users")
        .doc(targetUserId)
        .collection("fcmTokens")
        .get();

      if (tokensSnapshot.empty) {
        functions.logger.log("V2: No FCM tokens for user:", targetUserId);
        return;
      }
      const tokens = tokensSnapshot.docs.map((doc) => doc.id);

      // Use v1 API with messaging.sendEach for multiple tokens
      const messages = tokens.map((token) => ({
        token: token,
        notification: {
          title: "New Follow Request!",
          body: `${requesterName} wants to follow you.`,
        },
        data: {
          type: "follow_request",
          screen: "/follow_requests",
          requesterId: requesterId,
        },
      }));

      functions.logger.log("V2: Sending FCM to tokens:", tokens, "with messages:", messages);
      const response = await messaging.sendEach(messages);
      functions.logger.log("V2: Successfully sent:", response.successCount, "failed:", response.failureCount);

      // Handle failed tokens (same logic as before)
      const tokensToRemovePromises = [];
      response.responses.forEach((result, index) => {
        if (!result.success) {
          const error = result.error;
          functions.logger.error("V2: Failure sending to", tokens[index], error);
          if (
            error?.code === "messaging/invalid-registration-token" ||
            error?.code === "messaging/registration-token-not-registered"
          ) {
            tokensToRemovePromises.push(
              db.collection("users").doc(targetUserId).collection("fcmTokens").doc(tokens[index]).delete(),
            );
          }
        }
      });
      await Promise.all(tokensToRemovePromises);
      if (tokensToRemovePromises.length > 0) {
        functions.logger.log("V2: Deleted invalid tokens:", tokensToRemovePromises.length);
      }
    } catch (error) {
      functions.logger.error("V2: Error sending follow request notification:", error);
    }
  });


/**
 * Sends a notification when a user gets a new follower (2nd Gen).
 */
exports.sendNewFollowerNotificationV2 = onDocumentCreated(
  "users/{targetUserId}/followers/{followerId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      functions.logger.log("No data associated with the event");
      return;
    }

    const targetUserId = event.params.targetUserId;
    const followerId = event.params.followerId;

    functions.logger.log(
      `V2: New follower: ${followerId} for ${targetUserId}`,
    );

    try {
      const followerDoc = await db.collection("users").doc(followerId).get();
      const followerProfile = followerDoc.data();
      const followerName = followerProfile?.displayName || followerProfile?.username || "Someone";

      const tokensSnapshot = await db
        .collection("users")
        .doc(targetUserId)
        .collection("fcmTokens")
        .get();

      if (tokensSnapshot.empty) {
        functions.logger.log("V2: No FCM tokens for user:", targetUserId);
        return;
      }
      const tokens = tokensSnapshot.docs.map((doc) => doc.id);

      // Use v1 API with messaging.sendEach for multiple tokens
      const messages = tokens.map((token) => ({
        token: token,
        notification: {
          title: "New Follower!",
          body: `${followerName} started following you.`,
        },
        data: {
          type: "new_follower",
          followerId: followerId,
          screen: `/user_profile/${followerId}`,
        },
      }));

      functions.logger.log("V2: Sending FCM to tokens:", tokens, "with messages:", messages);
      const response = await messaging.sendEach(messages);
      functions.logger.log("V2: Successfully sent:", response.successCount, "failed:", response.failureCount);

      // Handle failed tokens (same logic as before)
      const tokensToRemovePromises = [];
      response.responses.forEach((result, index) => {
        if (!result.success) {
          const error = result.error;
          functions.logger.error("V2: Failure sending to", tokens[index], error);
          if (
            error?.code === "messaging/invalid-registration-token" ||
            error?.code === "messaging/registration-token-not-registered"
          ) {
            tokensToRemovePromises.push(
              db.collection("users").doc(targetUserId).collection("fcmTokens").doc(tokens[index]).delete(),
            );
          }
        }
      });
      await Promise.all(tokensToRemovePromises);
      if (tokensToRemovePromises.length > 0) {
        functions.logger.log("V2: Deleted invalid tokens:", tokensToRemovePromises.length);
      }
    } catch (error) {
      functions.logger.error("V2: Error sending new follower notification:", error);
    }
  });

/**
 * Minimal test function to diagnose FCM 404 issue (1st Gen)
 */
exports.testFcmSend1stGen = functions.https.onRequest(async (req, res) => {
  const defaultToken = "dxOkUz9DQLe3enHKhzZ3Tt:APA91bEwTSpJn5QJg7at4-szgDHCnr9oeiycGzR7pxW5n4NE8pXxlRDYaw3o7i" +
    "QW7puTP6bUV57PzODMDEQfZpsPvc3R9kc06vYADQlrIoYphxRMT4nC9rA";
  const targetToken = req.query.token || defaultToken;

  if (!targetToken) {
    functions.logger.error("Test 1st Gen: No token provided.");
    res.status(400).send("No token");
    return;
  }

  const payload = {
    notification: {
      title: "Test Notification from 1st Gen Cloud Function",
      body: "This is a test from the 1st Gen testFcmSend Cloud Function.",
    },
    data: {
      test: "true",
      generation: "1st",
    },
  };

  try {
    functions.logger.log("Test 1st Gen: Sending FCM to token:", targetToken, "with payload:", payload);
    const response = await messaging.sendToDevice(targetToken, payload);
    functions.logger.log("Test 1st Gen: Successfully sent:", response);
    res.status(200).send(`1st Gen - Successfully sent: ${JSON.stringify(response)}`);
  } catch (error) {
    functions.logger.error("Test 1st Gen: Error sending notification:", error);
    res.status(500).send(`1st Gen Error: ${error.toString()}`);
  }
});

/**
 * Test function using FCM v1 API instead of legacy sendToDevice
 */
exports.testFcmV1Send = functions.https.onRequest(async (req, res) => {
  const defaultToken = "dxOkUz9DQLe3enHKhzZ3Tt:APA91bEwTSpJn5QJg7at4-szgDHCnr9oeiycGzR7pxW5n4NE8pXxlRDYaw3o7i" +
    "QW7puTP6bUV57PzODMDEQfZpsPvc3R9kc06vYADQlrIoYphxRMT4nC9rA";
  const targetToken = req.query.token || defaultToken;

  if (!targetToken) {
    functions.logger.error("Test v1: No token provided.");
    res.status(400).send("No token");
    return;
  }

  const message = {
    token: targetToken,
    notification: {
      title: "Test Notification using FCM v1 API",
      body: "This is a test using the v1 API instead of sendToDevice.",
    },
    data: {
      test: "true",
      api_version: "v1",
    },
  };

  try {
    functions.logger.log("Test v1: Sending FCM message:", message);
    const response = await messaging.send(message);
    functions.logger.log("Test v1: Successfully sent, message ID:", response);
    res.status(200).send(`v1 API - Successfully sent: ${response}`);
  } catch (error) {
    functions.logger.error("Test v1: Error sending notification:", error);
    res.status(500).send(`v1 API Error: ${error.toString()}`);
  }
});
