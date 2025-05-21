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

      const payload = {
        notification: {
          title: "New Follow Request! (V2)",
          body: `${requesterName} wants to follow you.`,
        },
        data: {
          type: "follow_request",
          screen: "/follow_requests",
          requesterId: requesterId,
        },
      };

      functions.logger.log("V2: Sending FCM to tokens:", tokens, "with payload:", payload);
      const response = await messaging.sendToDevice(tokens, payload);
      functions.logger.log("V2: Successfully sent:", response.successCount);

      const tokensToRemovePromises = [];
      response.results.forEach((result, index) => {
        const error = result.error;
        if (error) {
          functions.logger.error("V2: Failure sending to", tokens[index], error);
          if (
            error.code === "messaging/invalid-registration-token" ||
                    error.code === "messaging/registration-token-not-registered"
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

      const payload = {
        notification: {
          title: "New Follower! (V2)",
          body: `${followerName} started following you.`,
        },
        data: {
          type: "new_follower",
          followerId: followerId,
          screen: `/user_profile/${followerId}`,
        },
      };

      functions.logger.log("V2: Sending FCM to tokens:", tokens, "with payload:", payload);
      const response = await messaging.sendToDevice(tokens, payload);
      functions.logger.log("V2: Successfully sent:", response.successCount);

      const tokensToRemovePromises = [];
      response.results.forEach((result, index) => {
        const error = result.error;
        if (error) {
          functions.logger.error("V2: Failure sending to", tokens[index], error);
          if (
            error.code === "messaging/invalid-registration-token" ||
                    error.code === "messaging/registration-token-not-registered"
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
