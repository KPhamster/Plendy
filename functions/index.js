// functions/index.js
const { getFirestore } = require("firebase-admin/firestore"); // For interacting with Firestore
const { onDocumentCreated } = require("firebase-functions/v2/firestore"); // For 2nd gen Firestore triggers
const { onRequest } = require("firebase-functions/v2/https"); // For 2nd gen HTTPS endpoints
const functions = require("firebase-functions"); // Still needed for logger, config, etc.
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

admin.initializeApp();

const db = getFirestore(); // Use getFirestore() from firebase-admin/firestore
const messaging = admin.messaging();

// Import and export share permission maintenance functions
const maintainSharedUserIds = require("./src/maintain_shared_userids");
Object.assign(exports, maintainSharedUserIds);

// Import and export backfill functions
const backfillModule = require("./src/backfill_shared_userids");
Object.assign(exports, backfillModule);


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
        android: {
          notification: {
            channelId: "social",
            priority: "high",
            defaultSound: true,
          },
        },
        apns: {
          payload: {
            aps: {
              category: "social",
              sound: "default",
            },
          },
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
        android: {
          notification: {
            channelId: "social",
            priority: "high",
            defaultSound: true,
          },
        },
        apns: {
          payload: {
            aps: {
              category: "social",
              sound: "default",
            },
          },
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
 * Sends a notification when a new message is sent (2nd Gen).
 */
exports.sendMessageNotificationV2 = onDocumentCreated(
  "message_threads/{threadId}/messages/{messageId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      functions.logger.log("No data associated with the event");
      return;
    }

    const threadId = event.params.threadId;
    const messageId = event.params.messageId;
    const messageData = snapshot.data();
    const senderId = messageData.senderId;

    functions.logger.log(
      `V2: New message ${messageId} in thread ${threadId} from ${senderId}`,
    );

    try {
      // Get the thread data to find participants
      const threadDoc = await db.collection("message_threads").doc(threadId).get();
      if (!threadDoc.exists) {
        functions.logger.error("V2: Thread not found:", threadId);
        return;
      }

      const threadData = threadDoc.data();
      const participants = threadData.participants || [];
      const participantProfiles = threadData.participantProfiles || {};

      // Get sender info
      const senderId = messageData.senderId;
      const senderProfile = participantProfiles[senderId];
      const senderName = senderProfile?.displayName || senderProfile?.username || "Someone";

      // Determine thread title for notification
      let threadTitle = "Chat";
      const otherParticipants = participants.filter((p) => p !== senderId);
      if (otherParticipants.length === 1) {
        // One-on-one chat - use sender name
        threadTitle = senderName;
      } else if (otherParticipants.length > 1) {
        // Group chat - show group info
        const participantNames = otherParticipants
          .slice(0, 2)
          .map((p) => participantProfiles[p]?.displayName || participantProfiles[p]?.username || "User")
          .join(", ");
        if (otherParticipants.length > 2) {
          threadTitle = `${senderName}, ${participantNames} and ${otherParticipants.length - 2} others`;
        } else {
          threadTitle = `${senderName}, ${participantNames}`;
        }
      }

      // Get message preview (truncate if too long)
      const messageText = messageData.text || "";
      const messagePreview = messageText.length > 50 ?
        messageText.substring(0, 47) + "..." :
        messageText;

      // Send notifications to all participants except the sender
      const notificationPromises = participants
        .filter((participantId) => participantId !== senderId)
        .map(async (participantId) => {
          const tokensSnapshot = await db
            .collection("users")
            .doc(participantId)
            .collection("fcmTokens")
            .get();

          if (tokensSnapshot.empty) {
            functions.logger.log("V2: No FCM tokens for user:", participantId);
            return;
          }

          const tokens = tokensSnapshot.docs.map((doc) => doc.id);

          // Create a unique collapse ID per message (not per thread)
          // This ensures duplicate deliveries of the SAME message are collapsed
          // but different messages in the thread are shown
          const collapseId = `${threadId}_${messageId}`;

          const messages = tokens.map((token) => ({
            token: token,
            notification: {
              title: threadTitle,
              body: `${senderName}: ${messagePreview}`,
            },
            data: {
              type: "new_message",
              threadId: threadId,
              senderId: senderId,
              messageId: messageId, // Add messageId for better tracking
              screen: "/messages",
            },
            android: {
              notification: {
                channelId: "messages",
                priority: "high",
                defaultSound: true,
                tag: collapseId, // Use messageId for Android to prevent duplicates of THIS message
              },
            },
            apns: {
              headers: {
                "apns-collapse-id": collapseId, // Use messageId to collapse duplicate deliveries
              },
              payload: {
                aps: {
                  "category": "message",
                  "sound": "default",
                  "thread-id": threadId, // Group notifications by thread
                  "mutable-content": 1,
                },
                senderId: senderId,
                messageId: messageId,
              },
            },
          }));

          functions.logger.log("V2: Sending message notification to", participantId, "tokens:", tokens.length);
          const response = await messaging.sendEach(messages);
          const successCount = response.successCount;
          const failureCount = response.failureCount;
          functions.logger.log("V2: Message notification sent:", successCount, "failed:", failureCount);

          // Handle failed tokens
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
                  db.collection("users").doc(participantId).collection("fcmTokens").doc(tokens[index]).delete(),
                );
              }
            }
          });
          await Promise.all(tokensToRemovePromises);
          if (tokensToRemovePromises.length > 0) {
            functions.logger.log("V2: Deleted invalid tokens:", tokensToRemovePromises.length);
          }
        });

      await Promise.all(notificationPromises);
      functions.logger.log("V2: Message notifications sent to all participants");
    } catch (error) {
      functions.logger.error("V2: Error sending message notification:", error);
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
 * Test function for message notifications
 */
exports.testMessageNotification = functions.https.onRequest(async (req, res) => {
  const userId = req.query.userId;
  const message = req.query.message || "Test message from Cloud Function";

  if (!userId) {
    functions.logger.error("Test: No userId provided.");
    res.status(400).send("No userId provided. Use ?userId=YOUR_USER_ID&message=TEST_MESSAGE");
    return;
  }

  try {
    // Get FCM tokens for the user
    const tokensSnapshot = await db
      .collection("users")
      .doc(userId)
      .collection("fcmTokens")
      .get();

    if (tokensSnapshot.empty) {
      functions.logger.log("Test: No FCM tokens for user:", userId);
      res.status(404).send(`No FCM tokens found for user: ${userId}`);
      return;
    }

    const tokens = tokensSnapshot.docs.map((doc) => doc.id);
    functions.logger.log("Test: Found tokens for user", userId, ":", tokens.length);

    // Send test notification
    const messages = tokens.map((token) => ({
      token: token,
      notification: {
        title: "Test Notification",
        body: `Test: ${message}`,
      },
      data: {
        type: "test_message",
        userId: userId,
        screen: "/messages",
      },
      android: {
        notification: {
          channelId: "messages",
          priority: "high",
          defaultSound: true,
        },
      },
      apns: {
        payload: {
          aps: {
            category: "message",
            sound: "default",
          },
        },
      },
    }));

    functions.logger.log("Test: Sending notifications to", tokens.length, "tokens");
    const response = await messaging.sendEach(messages);
    functions.logger.log("Test: Successfully sent:", response.successCount, "failed:", response.failureCount);

    // Handle failed tokens
    const tokensToRemovePromises = [];
    response.responses.forEach((result, index) => {
      if (!result.success) {
        const error = result.error;
        functions.logger.error("Test: Failure sending to", tokens[index], error);
        if (
          error?.code === "messaging/invalid-registration-token" ||
          error?.code === "messaging/registration-token-not-registered"
        ) {
          tokensToRemovePromises.push(
            db.collection("users").doc(userId).collection("fcmTokens").doc(tokens[index]).delete(),
          );
        }
      }
    });
    await Promise.all(tokensToRemovePromises);
    if (tokensToRemovePromises.length > 0) {
      functions.logger.log("Test: Deleted invalid tokens:", tokensToRemovePromises.length);
    }

    res.status(200).send({
      success: true,
      sent: response.successCount,
      failed: response.failureCount,
      tokens: tokens.length,
      message: `Test notification sent to ${response.successCount} devices`,
    });
  } catch (error) {
    functions.logger.error("Test: Error sending notification:", error);
    res.status(500).send(`Error: ${error.toString()}`);
  }
});

/**
 * Clean up cross-contaminated FCM tokens for a user
 */
exports.cleanupUserFcmTokens = onRequest(async (req, res) => {
  const userId = req.query.userId || req.body?.userId;

  if (!userId) {
    res.status(400).send("userId parameter required");
    return;
  }

  try {
    functions.logger.log("Cleaning up tokens for user:", userId);

    // Get the current user's tokens
    const userTokensSnapshot = await db
      .collection("users")
      .doc(userId)
      .collection("fcmTokens")
      .get();

    const userTokens = userTokensSnapshot.docs.map((doc) => doc.id);
    functions.logger.log("User has", userTokens.length, "tokens");

    // Check all other users for these tokens
    const allUsersSnapshot = await db.collection("users").get();
    let removedCount = 0;

    for (const userDoc of allUsersSnapshot.docs) {
      if (userDoc.id === userId) continue; // Skip the target user

      for (const token of userTokens) {
        const tokenDoc = await userDoc.ref.collection("fcmTokens").doc(token).get();
        if (tokenDoc.exists) {
          functions.logger.log("Found cross-contamination: token under user", userDoc.id);
          await tokenDoc.ref.delete();
          removedCount++;
        }
      }
    }

    functions.logger.log("Cleanup complete. Removed", removedCount, "cross-contaminated tokens");
    res.status(200).json({
      success: true,
      userId: userId,
      userTokenCount: userTokens.length,
      removedFromOtherUsers: removedCount,
    });
  } catch (error) {
    functions.logger.error("Error cleaning up tokens:", error);
    res.status(500).send(error.toString());
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

/**
 * Admin-only bulk delete for share_permissions filtered by sharedWithUserId.
 *
 * Safety features:
 * - Optional shared secret via functions config: maintenance.secret
 * - Dry-run mode using count() aggregation
 * - Batching with configurable batchSize and maxDocs per invocation
 *
 * Usage (GET or POST):
 *   /bulkDeleteSharePermissions?sharedWithUserId=UID&dryRun=true
 *   /bulkDeleteSharePermissions?sharedWithUserId=UID&confirm=yes&batchSize=400&maxDocs=5000
 * If a secret is configured, include &secret=YOUR_SECRET or header x-admin-secret.
 */
exports.bulkDeleteSharePermissions = onRequest({ region: "us-central1" }, async (req, res) => {
  try {
    // Method guard
    if (req.method !== "GET" && req.method !== "POST") {
      res.status(405).send("Method not allowed");
      return;
    }

    // Simple shared-secret guard (optional). For 2nd gen, prefer process.env.
    let configuredSecret = "";
    try {
      configuredSecret = process.env.MAINTENANCE_SECRET || "";
    } catch (e) {
      configuredSecret = "";
    }
    if (configuredSecret) {
      const providedSecret =
        (req.query && (req.query.secret || req.query.apiKey)) ||
        req.get("x-admin-secret") ||
        (req.body && (req.body.secret || req.body.apiKey));
      if (providedSecret !== configuredSecret) {
        res.status(403).json({ ok: false, error: "Forbidden: invalid secret" });
        return;
      }
    }

    const sharedWithUserId = (
      (req.query && req.query.sharedWithUserId) || (req.body && req.body.sharedWithUserId) || ""
    ).toString().trim();
    if (!sharedWithUserId) {
      res.status(400).json({ ok: false, error: "sharedWithUserId is required" });
      return;
    }

    const dryRunRaw = (req.query && req.query.dryRun) || (req.body && req.body.dryRun);
    const dryRun = (typeof dryRunRaw === "string" ? dryRunRaw : String(dryRunRaw || "")).toLowerCase() === "true";
    const confirm = ((req.query && req.query.confirm) || (req.body && req.body.confirm) || "").toString().toLowerCase();
    const batchSizeInput = Number((req.query && req.query.batchSize) || (req.body && req.body.batchSize) || 300);
    const maxDocsInput = Number((req.query && req.query.maxDocs) || (req.body && req.body.maxDocs) || 5000);
    const batchSize = Math.max(1, Math.min(450, isFinite(batchSizeInput) ? batchSizeInput : 300));
    const maxDocs = Math.max(1, Math.min(100000, isFinite(maxDocsInput) ? maxDocsInput : 5000));

    const baseQuery = db
      .collection("share_permissions")
      .where("sharedWithUserId", "==", sharedWithUserId);

    // Dry run: fast count without deleting
    if (dryRun) {
      try {
        const agg = await baseQuery.count().get();
        const total = agg.data().count || 0;
        res.json({ ok: true, sharedWithUserId, dryRun: true, total });
        return;
      } catch (countErr) {
        // Fallback if count() not available in environment
        const snap = await baseQuery.limit(1001).get();
        const estimatedTotal = snap.size;
        const truncated = estimatedTotal >= 1001;
        res.json({ ok: true, sharedWithUserId, dryRun: true, total: estimatedTotal, truncated });
        return;
      }
    }

    if (confirm !== "yes") {
      res.status(400).json({
        ok: false,
        error: "Missing confirm=yes. Use dryRun=true first to see counts.",
        hint: "Add confirm=yes to actually delete. Example: ?sharedWithUserId=UID&confirm=yes",
      });
      return;
    }

    const startedAtMs = Date.now();
    let totalDeleted = 0;
    let batches = 0;

    // Loop deleting in pages until we reach maxDocs or there are no more matches
    while (totalDeleted < maxDocs) {
      const toFetch = Math.min(batchSize, maxDocs - totalDeleted);
      const snap = await baseQuery.limit(toFetch).get();
      if (snap.empty) break;

      const batch = db.batch();
      snap.docs.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();

      totalDeleted += snap.size;
      batches += 1;

      // Small delay to reduce write contention with onDelete triggers
      await new Promise((r) => setTimeout(r, 50));
    }

    const durationMs = Date.now() - startedAtMs;
    res.json({
      ok: true,
      sharedWithUserId,
      deleted: totalDeleted,
      batches,
      batchSize,
      maxDocs,
      ms: durationMs,
      note: "If more documents remain, call again or increase maxDocs.",
    });
  } catch (err) {
    functions.logger.error("bulkDeleteSharePermissions error", err);
    res.status(500).json({ ok: false, error: err && err.message ? err.message : String(err) });
  }
});

/**
 * Sends an email notification when a new report is created (2nd Gen).
 * Configure Gmail App Password via environment variable: GMAIL_APP_PASSWORD
 * Set via: firebase functions:config:set gmail.password="your-app-password"
 * Or use .env for local: GMAIL_APP_PASSWORD=your-app-password
 */
exports.sendReportEmailNotification = onDocumentCreated(
  "reports/{reportId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      functions.logger.log("No data associated with the event");
      return;
    }

    const reportId = event.params.reportId;
    const reportData = snapshot.data();

    functions.logger.log(`New report created: ${reportId}`);

    try {
      // Get reporter user info
      let reporterName = "Unknown User";
      let reporterEmail = "N/A";
      try {
        const reporterDoc = await db.collection("users").doc(reportData.userId).get();
        if (reporterDoc.exists) {
          const reporterProfile = reporterDoc.data();
          reporterName = reporterProfile?.displayName ||
            reporterProfile?.username ||
            reporterProfile?.email ||
            "Unknown User";
          reporterEmail = reporterProfile?.email || "N/A";
        }
      } catch (err) {
        functions.logger.error("Error fetching reporter profile:", err);
      }

      // Get reported experience info
      let experienceName = "Unknown Experience";
      try {
        if (reportData.publicExperienceId) {
          const expDoc = await db.collection("public_experiences").doc(reportData.publicExperienceId).get();
          if (expDoc.exists) {
            const expData = expDoc.data();
            experienceName = expData?.name || "Unknown Experience";
          }
        } else if (reportData.experienceId) {
          const expDoc = await db.collection("experiences").doc(reportData.experienceId).get();
          if (expDoc.exists) {
            const expData = expDoc.data();
            experienceName = expData?.name || "Unknown Experience";
          }
        }
      } catch (err) {
        functions.logger.error("Error fetching experience info:", err);
      }

      // Format the report type
      const reportTypeLabels = {
        "inappropriate": "Inappropriate Content",
        "incorrect": "Incorrect Information",
        "other": "Other",
      };
      const reportTypeLabel = reportTypeLabels[reportData.reportType] || reportData.reportType;

      // Format the timestamp
      const createdAt = reportData.createdAt?.toDate ? reportData.createdAt.toDate() : new Date();
      const formattedDate = createdAt.toLocaleString("en-US", {
        year: "numeric",
        month: "long",
        day: "numeric",
        hour: "2-digit",
        minute: "2-digit",
        timeZone: "America/Los_Angeles",
      });

      // Configure email transporter using Gmail
      // Use environment variable for password
      const gmailPassword = process.env.GMAIL_APP_PASSWORD || "";

      if (!gmailPassword) {
        functions.logger.error("Gmail app password not configured. Set GMAIL_APP_PASSWORD environment variable.");
        return;
      }

      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
          user: "plendy.experience@gmail.com",
          pass: gmailPassword,
        },
      });

      // Build email HTML
      const emailHtml = `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
          <h2 style="color: #d32f2f; border-bottom: 2px solid #d32f2f; padding-bottom: 10px;">
            🚨 New Content Report
          </h2>
          
          <div style="background-color: #f5f5f5; padding: 20px; border-radius: 8px; margin: 20px 0;">
            <h3 style="margin-top: 0; color: #333;">Report Details</h3>
            <table style="width: 100%; border-collapse: collapse;">
              <tr>
                <td style="padding: 8px 0; font-weight: bold; color: #666; width: 160px;">Report ID:</td>
                <td style="padding: 8px 0; color: #333;">${reportId}</td>
              </tr>
              <tr>
                <td style="padding: 8px 0; font-weight: bold; color: #666;">Report Type:</td>
                <td style="padding: 8px 0; color: #d32f2f; font-weight: bold;">${reportTypeLabel}</td>
              </tr>
              <tr>
                <td style="padding: 8px 0; font-weight: bold; color: #666;">Status:</td>
                <td style="padding: 8px 0; color: #333;">${reportData.status || "pending"}</td>
              </tr>
              <tr>
                <td style="padding: 8px 0; font-weight: bold; color: #666;">Submitted:</td>
                <td style="padding: 8px 0; color: #333;">${formattedDate} PST</td>
              </tr>
            </table>
          </div>

          <div style="background-color: #fff3e0; padding: 20px; ` +
        "border-radius: 8px; margin: 20px 0; " +
        `border-left: 4px solid #ff9800;">
            <h3 style="margin-top: 0; color: #333;">Reported Content</h3>
            <table style="width: 100%; border-collapse: collapse;">
              <tr>
                <td style="padding: 8px 0; font-weight: bold; color: #666; width: 160px;">Experience:</td>
                <td style="padding: 8px 0; color: #333;">${experienceName}</td>
              </tr>
              <tr>
                <td style="padding: 8px 0; font-weight: bold; color: #666;">Screen:</td>
                <td style="padding: 8px 0; color: #333;">${reportData.screenReported || "N/A"}</td>
              </tr>
              <tr>
                <td style="padding: 8px 0; font-weight: bold; color: #666;">Preview URL:</td>
                <td style="padding: 8px 0; color: #333; word-break: break-all;">
                  <a href="${reportData.previewURL || "#"}" ` +
        "target=\"_blank\" style=\"color: #1976d2;\">" +
        `${reportData.previewURL || "N/A"}</a>
                </td>
              </tr>
              <tr>
                <td style="padding: 8px 0; font-weight: bold; color: #666;">` +
        `Experience ID:</td>
                <td style="padding: 8px 0; color: #333; ` +
        "font-family: monospace; font-size: 12px;\">" +
        `${reportData.experienceId || "N/A"}</td>
              </tr>
              ${reportData.publicExperienceId ? `
              <tr>
                <td style="padding: 8px 0; font-weight: bold; color: #666;">` +
        `Public Exp ID:</td>
                <td style="padding: 8px 0; color: #333; ` +
        "font-family: monospace; font-size: 12px;\">" +
        `${reportData.publicExperienceId}</td>
              </tr>
              ` : ""}
            </table>
          </div>

          <div style="background-color: #e3f2fd; padding: 20px; ` +
        "border-radius: 8px; margin: 20px 0; " +
        `border-left: 4px solid #2196f3;">
            <h3 style="margin-top: 0; color: #333;">Reporter Information</h3>
            <table style="width: 100%; border-collapse: collapse;">
              <tr>
                <td style="padding: 8px 0; font-weight: bold; color: #666; width: 160px;">Name:</td>
                <td style="padding: 8px 0; color: #333;">${reporterName}</td>
              </tr>
              <tr>
                <td style="padding: 8px 0; font-weight: bold; color: #666;">Email:</td>
                <td style="padding: 8px 0; color: #333;">${reporterEmail}</td>
              </tr>
              <tr>
                <td style="padding: 8px 0; font-weight: bold; color: #666;">` +
        `User ID:</td>
                <td style="padding: 8px 0; color: #333; ` +
        "font-family: monospace; font-size: 12px;\">" +
        `${reportData.userId || "N/A"}</td>
              </tr>
              ${reportData.deviceInfo ? `
              <tr>
                <td style="padding: 8px 0; font-weight: bold; color: #666;">Device:</td>
                <td style="padding: 8px 0; color: #333;">${reportData.deviceInfo}</td>
              </tr>
              ` : ""}
              ${reportData.reportedUserId ? `
              <tr>
                <td style="padding: 8px 0; font-weight: bold; color: #666;">` +
        `Reported User ID:</td>
                <td style="padding: 8px 0; color: #333; ` +
        "font-family: monospace; font-size: 12px;\">" +
        `${reportData.reportedUserId}</td>
              </tr>
              ` : ""}
            </table>
          </div>

          ${reportData.details ? `
          <div style="background-color: #fff; padding: 20px; ` +
        `border-radius: 8px; margin: 20px 0; border: 1px solid #ddd;">
            <h3 style="margin-top: 0; color: #333;">Additional Details</h3>
            <p style="color: #555; line-height: 1.6; white-space: pre-wrap;">${reportData.details}</p>
          </div>
          ` : ""}

          <div style="margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #999; font-size: 12px;">
            <p>This is an automated notification from Plendy's content moderation system.</p>
            <p>Please review this report and take appropriate action in the admin dashboard.</p>
          </div>
        </div>
      `;

      // Send email
      const mailOptions = {
        from: "Plendy Reports <plendy.experience@gmail.com>",
        to: "plendy.experience@gmail.com",
        subject: `🚨 New Report: ${reportTypeLabel} - ${experienceName}`,
        html: emailHtml,
        text: `
New Content Report Received

Report ID: ${reportId}
Report Type: ${reportTypeLabel}
Status: ${reportData.status || "pending"}
Submitted: ${formattedDate} PST

Reported Content:
- Experience: ${experienceName}
- Screen: ${reportData.screenReported || "N/A"}
- Preview URL: ${reportData.previewURL || "N/A"}
- Experience ID: ${reportData.experienceId || "N/A"}
${reportData.publicExperienceId ? `- Public Experience ID: ${reportData.publicExperienceId}\n` : ""}

Reporter Information:
- Name: ${reporterName}
- Email: ${reporterEmail}
- User ID: ${reportData.userId || "N/A"}
${reportData.deviceInfo ? `- Device: ${reportData.deviceInfo}\n` : ""}
${reportData.reportedUserId ? `- Reported User ID: ${reportData.reportedUserId}\n` : ""}

Additional Details:
${reportData.details || "No additional details provided."}

---
This is an automated notification from Plendy's content moderation system.
        `.trim(),
      };

      await transporter.sendMail(mailOptions);
      functions.logger.log(`Report email sent successfully for report ${reportId}`);
    } catch (error) {
      functions.logger.error("Error sending report email notification:", error);
      // Don't throw - we don't want the function to fail if email fails
      // The report is still saved in Firestore
    }
  });
