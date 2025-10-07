const functions = require("firebase-functions");
const admin = require("firebase-admin");

const db = admin.firestore();
const { FieldValue } = admin.firestore;

function isExperiencePermission(data) {
  if (!data) return false;
  const itemType = (data.itemType || "").toString();
  return itemType === "experience";
}

function getExperienceId(data) {
  return (data.itemId || "").toString();
}

function getViewerId(data) {
  return (data.sharedWithUserId || "").toString();
}

// Create: add viewer to experiences/{id}.sharedWithUserIds and best-effort denormalize icon/color
exports.onSharePermissionCreate = functions.firestore
  .document("share_permissions/{permissionId}")
  .onCreate(async (snap, context) => {
    const perm = snap.data() || {};
    if (!isExperiencePermission(perm)) return null;
    const expId = getExperienceId(perm);
    const viewerId = getViewerId(perm);
    if (!expId || !viewerId) return null;
    try {
      const expRef = db.collection("experiences").doc(expId);
      const expSnap = await expRef.get();
      const update = {
        sharedWithUserIds: FieldValue.arrayUnion(viewerId),
        updatedAt: FieldValue.serverTimestamp(),
      };
      if (expSnap.exists) {
        const exp = expSnap.data() || {};
        if (!exp.categoryIconDenorm && exp.categoryId && exp.createdBy) {
          try {
            const cat = await db
              .collection("users").doc(exp.createdBy)
              .collection("categories").doc(exp.categoryId)
              .get();
            if (cat.exists) {
              const icon = (cat.data() || {}).icon;
              if (icon) update.categoryIconDenorm = icon;
            }
          } catch (err) {
            functions.logger.warn(
              `onSharePermissionCreate: category denorm failed for experiences/${expId}:`,
              err,
            );
          }
        }
        if (!exp.colorHexDenorm && exp.colorCategoryId && exp.createdBy) {
          try {
            const cc = await db
              .collection("users").doc(exp.createdBy)
              .collection("color_categories").doc(exp.colorCategoryId)
              .get();
            if (cc.exists) {
              const colorHex = (cc.data() || {}).colorHex;
              if (colorHex) update.colorHexDenorm = colorHex;
            }
          } catch (err) {
            functions.logger.warn(
              `onSharePermissionCreate: color denorm failed for experiences/${expId}:`,
              err,
            );
          }
        }
      }
      await expRef.set(update, { merge: true });
    } catch (e) {
      console.error(
        `onSharePermissionCreate: failed to update experiences/${expId} for viewer ${viewerId}:`,
        e,
      );
    }
    return null;
  });

// Update: if sharedWithUserId field changed (rare because it's part of doc id scheme), ensure membership
exports.onSharePermissionUpdate = functions.firestore
  .document("share_permissions/{permissionId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    if (!isExperiencePermission(after)) return null;
    const expId = getExperienceId(after);
    const viewerIdAfter = getViewerId(after);
    const viewerIdBefore = getViewerId(before);

    // If viewer changed or access escalated/downgraded, ensure the viewer is present.
    if (!expId || !viewerIdAfter) return null;
    if (viewerIdAfter === viewerIdBefore) {
      // No membership change needed for typical accessLevel updates; still ensure presence.
    }
    try {
      await db
        .collection("experiences")
        .doc(expId)
        .set(
          {
            sharedWithUserIds: FieldValue.arrayUnion(viewerIdAfter),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
    } catch (e) {
      console.error(
        `onSharePermissionUpdate: failed to update experiences/${expId} for viewer ${viewerIdAfter}:`,
        e,
      );
    }
    return null;
  });

// Delete: remove viewer from experiences/{id}.sharedWithUserIds
exports.onSharePermissionDelete = functions.firestore
  .document("share_permissions/{permissionId}")
  .onDelete(async (snap, context) => {
    const perm = snap.data() || {};
    if (!isExperiencePermission(perm)) return null;
    const expId = getExperienceId(perm);
    const viewerId = getViewerId(perm);
    if (!expId || !viewerId) return null;
    try {
      await db
        .collection("experiences")
        .doc(expId)
        .set(
          {
            sharedWithUserIds: FieldValue.arrayRemove(viewerId),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
    } catch (e) {
      console.error(
        `onSharePermissionDelete: failed to update experiences/${expId} for viewer ${viewerId}:`,
        e,
      );
    }
    return null;
  });


