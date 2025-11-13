const functions = require("firebase-functions");
const admin = require("firebase-admin");

const db = admin.firestore();
const cors = require("cors")({ origin: true });

// Helper to safely get array
function asArray(value) {
  if (!value) return [];
  if (Array.isArray(value)) return value;
  return [value].filter(Boolean);
}

// On create of an experience share, denormalize for direct shares and send FCM
exports.onExperienceShareCreate = functions.firestore
  .document("experience_shares/{shareId}")
  .onCreate(async (snap, context) => {
    const share = snap.data() || {};
    const shareId = context.params.shareId;

    const visibility = share.visibility || "unlisted";
    const fromUserId = share.fromUserId;
    const toUserIds = asArray(share.toUserIds);

    try {
      // For direct shares, write denormalized docs and send notifications
      if (visibility === "direct" && toUserIds.length > 0) {
        const batch = db.batch();
        toUserIds.forEach((uid) => {
          const ref = db
            .collection("users")
            .doc(uid)
            .collection("received_shares")
            .doc(shareId);
          batch.set(ref, {
            shareId,
            experienceId: share.experienceId,
            fromUserId,
            visibility,
            message: share.message || null,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            snapshot: share.snapshot || null,
            seen: false,
          });
        });
        // Denormalize sharedWithUserIds for query-friendly rules
        if (share.experienceId) {
          const expRef = db.collection("experiences").doc(share.experienceId);
          batch.set(
            expRef,
            {
              sharedWithUserIds: admin.firestore.FieldValue.arrayUnion(...toUserIds),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        }
        await batch.commit();

        // Send FCM notifications
        const tokensSnap = await db
          .collection("users")
          .doc(fromUserId)
          .get();
        const fromUser = tokensSnap.exists ? tokensSnap.data() : null;
        const titleName = (fromUser && (fromUser.displayName || fromUser.username)) || "Someone";

        // Collect tokens from each recipient's fcmTokens subcollection
        const tokenDocs = await Promise.all(
          toUserIds.map((uid) =>
            db
              .collection("users")
              .doc(uid)
              .collection("fcmTokens")
              .get(),
          ),
        );

        const tokens = tokenDocs
          .flatMap((qs) => qs.docs.map((d) => d.id))
          .filter(Boolean);

        if (tokens.length > 0) {
          const payload = {
            notification: {
              title: `${titleName} shared an experience with you`,
              body: share.snapshot?.name || "Open to view",
            },
            data: {
              type: "share",
              shareId,
              experienceId: share.experienceId || "",
            },
            android: {
              notification: {
                channelId: "shares",
                priority: "high",
                defaultSound: true,
              },
            },
            apns: {
              payload: {
                aps: {
                  category: "share",
                  sound: "default",
                },
              },
            },
          };
          await admin.messaging().sendEachForMulticast({ tokens, ...payload });
        }
      }

      return null;
    } catch (err) {
      console.error("onExperienceShareCreate error", err);
      return null;
    }
  });

// HTTPS callable to accept collaboration invite and add recipient to editorUserIds
exports.onExperienceShareAcceptCollab = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Auth required");
  }
  const { shareId } = data || {};
  if (!shareId) {
    throw new functions.https.HttpsError("invalid-argument", "shareId required");
  }

  const shareRef = db.collection("experience_shares").doc(shareId);
  const shareSnap = await shareRef.get();
  if (!shareSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Share not found");
  }
  const share = shareSnap.data();
  const uid = context.auth.uid;

  if (share.visibility !== "direct" || !asArray(share.toUserIds).includes(uid)) {
    throw new functions.https.HttpsError("permission-denied", "Not a recipient");
  }
  if (!share.collaboration) {
    throw new functions.https.HttpsError("failed-precondition", "This share is not a collaboration invite");
  }

  const expId = share.experienceId;
  if (!expId) {
    throw new functions.https.HttpsError("failed-precondition", "Missing experienceId on share");
  }

  const expRef = db.collection("experiences").doc(expId);
  await expRef.update({
    editorUserIds: admin.firestore.FieldValue.arrayUnion(uid),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { success: true };
});

// Public HTTP endpoint to fetch share snapshot by token for web fallback
exports.publicShare = functions.https.onRequest(async (req, res) => {
  return cors(req, res, async () => {
    try {
      const token = req.query.token;
      if (!token || typeof token !== "string" || token.length < 6) {
        res.status(400).json({ error: "Missing or invalid token" });
        return;
      }

      const snap = await db
        .collection("experience_shares")
        .where("token", "==", token)
        .limit(1)
        .get();

      if (snap.empty) {
        res.status(404).json({ error: "Share not found" });
        return;
      }

      const doc = snap.docs[0];
      const share = doc.data() || {};
      const visibility = share.visibility || "unlisted";

      if (!(visibility === "public" || visibility === "unlisted")) {
        res.status(403).json({ error: "Share is not public" });
        return;
      }

      res.json({
        shareId: doc.id,
        experienceId: share.experienceId || null,
        visibility,
        snapshot: share.snapshot || null,
        message: share.message || null,
        createdAt: share.createdAt || null,
      });
    } catch (e) {
      console.error("publicShare error", e);
      res.status(500).json({ error: "Internal error" });
    }
  });
});


