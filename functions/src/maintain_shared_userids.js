/**
 * Cloud Functions to maintain sharedWithUserIds on experiences
 * when share_permissions change.
 *
 * This denormalization allows fast queries like:
 *   experiences.where('sharedWithUserIds', array-contains, userId)
 * instead of fetching all category shares and then querying each category.
 */

const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentDeleted,
} = require("firebase-functions/v2/firestore");
const functions = require("firebase-functions");

const db = getFirestore();

/**
 * Helper: Get all experiences that belong to a category (user or color).
 * Handles primary categoryId, otherCategories, and colorCategoryId.
 */
async function getExperiencesForCategory(ownerUserId, categoryId, isColorCategory) {
  const experiencesRef = db.collection("experiences");
  const results = new Map(); // Use map to dedupe by experience ID

  try {
    if (isColorCategory) {
      // Query by colorCategoryId
      const snap = await experiencesRef
        .where("createdBy", "==", ownerUserId)
        .where("colorCategoryId", "==", categoryId)
        .get();

      snap.docs.forEach((doc) => results.set(doc.id, doc));
    } else {
      // Query by primary categoryId
      const primarySnap = await experiencesRef
        .where("createdBy", "==", ownerUserId)
        .where("categoryId", "==", categoryId)
        .get();

      primarySnap.docs.forEach((doc) => results.set(doc.id, doc));

      // Query by otherCategories (array-contains)
      const otherSnap = await experiencesRef
        .where("createdBy", "==", ownerUserId)
        .where("otherCategories", "array-contains", categoryId)
        .get();

      otherSnap.docs.forEach((doc) => results.set(doc.id, doc));
    }

    return Array.from(results.values());
  } catch (error) {
    functions.logger.error(
      `getExperiencesForCategory failed for owner ${ownerUserId}, categoryId ${categoryId}:`,
      error,
    );
    return [];
  }
}

/**
 * Helper: Get all category IDs that an experience belongs to.
 */
function getCategoryIdsForExperience(experienceData) {
  const categoryIds = new Set();

  if (experienceData.categoryId) {
    categoryIds.add(experienceData.categoryId);
  }

  if (Array.isArray(experienceData.otherCategories)) {
    experienceData.otherCategories.forEach((id) => categoryIds.add(id));
  }

  if (experienceData.colorCategoryId) {
    categoryIds.add(experienceData.colorCategoryId);
  }

  return Array.from(categoryIds);
}

/**
 * Helper: Get all user IDs that have access to an experience via category shares.
 */
async function getUsersWithCategoryAccess(ownerUserId, categoryIds) {
  if (!categoryIds || categoryIds.length === 0) return [];

  const sharedUserIds = new Set();

  try {
    // Query share_permissions for category shares
    // Split into chunks of 30 due to 'in' query limit
    const chunkSize = 30;
    for (let i = 0; i < categoryIds.length; i += chunkSize) {
      const chunk = categoryIds.slice(i, i + chunkSize);

      const snap = await db
        .collection("share_permissions")
        .where("itemType", "==", "category")
        .where("itemId", "in", chunk)
        .where("ownerUserId", "==", ownerUserId)
        .get();

      snap.docs.forEach((doc) => {
        const data = doc.data();
        if (data.sharedWithUserId && data.sharedWithUserId !== ownerUserId) {
          sharedUserIds.add(data.sharedWithUserId);
        }
      });
    }
  } catch (error) {
    functions.logger.error("getUsersWithCategoryAccess error:", error);
  }

  return Array.from(sharedUserIds);
}

/**
 * When a CATEGORY share permission is created, add the sharedWithUserId
 * to all experiences in that category.
 */
exports.onCategoryShareCreated = onDocumentCreated(
  "share_permissions/{permissionId}",
  async (event) => {
    const permissionData = event.data.data();

    // Only process category shares
    if (permissionData.itemType !== "category") {
      return;
    }

    const { ownerUserId, itemId: categoryId, sharedWithUserId } = permissionData;

    if (!ownerUserId || !categoryId || !sharedWithUserId) {
      functions.logger.warn("Missing required fields in share permission");
      return;
    }

    // Don't process self-shares
    if (ownerUserId === sharedWithUserId) {
      return;
    }

    functions.logger.log(
      `Category share created: owner=${ownerUserId}, categoryId=${categoryId}, sharedWith=${sharedWithUserId}`,
    );

    try {
      // Determine if this is a color category or user category
      // Try fetching from both collections
      const userCatDoc = await db
        .collection("users")
        .doc(ownerUserId)
        .collection("categories")
        .doc(categoryId)
        .get();

      const colorCatDoc = await db
        .collection("users")
        .doc(ownerUserId)
        .collection("color_categories")
        .doc(categoryId)
        .get();

      const isColorCategory = colorCatDoc.exists && !userCatDoc.exists;

      // Get all experiences in this category
      const experienceDocs = await getExperiencesForCategory(
        ownerUserId,
        categoryId,
        isColorCategory,
      );

      if (experienceDocs.length === 0) {
        functions.logger.log("No experiences found for this category");
        return;
      }

      functions.logger.log(
        `Adding sharedWithUserId to ${experienceDocs.length} experiences`,
      );

      // Update in batches (Firestore batch limit is 500)
      const batchSize = 400;
      for (let i = 0; i < experienceDocs.length; i += batchSize) {
        const batch = db.batch();
        const chunk = experienceDocs.slice(i, i + batchSize);

        chunk.forEach((doc) => {
          batch.update(doc.ref, {
            sharedWithUserIds: FieldValue.arrayUnion(sharedWithUserId),
          });
        });

        await batch.commit();
      }

      functions.logger.log(
        `Successfully updated ${experienceDocs.length} experiences with sharedWithUserId`,
      );
    } catch (error) {
      functions.logger.error("Error in onCategoryShareCreated:", error);
    }
  },
);

/**
 * When an EXPERIENCE share permission is created, add the sharedWithUserId
 * to that experience.
 */
exports.onExperienceShareCreated = onDocumentCreated(
  "share_permissions/{permissionId}",
  async (event) => {
    const permissionData = event.data.data();

    // Only process experience shares
    if (permissionData.itemType !== "experience") {
      return;
    }

    const { itemId: experienceId, sharedWithUserId, ownerUserId } = permissionData;

    if (!experienceId || !sharedWithUserId) {
      functions.logger.warn("Missing required fields in experience share");
      return;
    }

    // Don't process self-shares
    if (ownerUserId === sharedWithUserId) {
      return;
    }

    functions.logger.log(
      `Experience share created: experienceId=${experienceId}, sharedWith=${sharedWithUserId}`,
    );

    try {
      await db
        .collection("experiences")
        .doc(experienceId)
        .update({
          sharedWithUserIds: FieldValue.arrayUnion(sharedWithUserId),
        });

      functions.logger.log("Successfully updated experience with sharedWithUserId");
    } catch (error) {
      functions.logger.error("Error in onExperienceShareCreated:", error);
    }
  },
);

/**
 * When a share permission is deleted, remove the sharedWithUserId from the experience(s).
 */
exports.onSharePermissionDeleted = onDocumentDeleted(
  "share_permissions/{permissionId}",
  async (event) => {
    const permissionData = event.data.data();

    const { itemType, itemId, ownerUserId, sharedWithUserId } = permissionData;

    if (!itemType || !itemId || !sharedWithUserId) {
      functions.logger.warn("Missing required fields in deleted permission");
      return;
    }

    // Don't process self-shares
    if (ownerUserId === sharedWithUserId) {
      return;
    }

    functions.logger.log(
      `Share permission deleted: type=${itemType}, itemId=${itemId}, sharedWith=${sharedWithUserId}`,
    );

    try {
      if (itemType === "category") {
        // Check if user still has access via other category shares
        const userCatDoc = await db
          .collection("users")
          .doc(ownerUserId)
          .collection("categories")
          .doc(itemId)
          .get();

        const colorCatDoc = await db
          .collection("users")
          .doc(ownerUserId)
          .collection("color_categories")
          .doc(itemId)
          .get();

        const isColorCategory = colorCatDoc.exists && !userCatDoc.exists;

        // Get all experiences in this category
        const experienceDocs = await getExperiencesForCategory(
          ownerUserId,
          itemId,
          isColorCategory,
        );

        if (experienceDocs.length === 0) {
          return;
        }

        // For each experience, check if user still has access via other categories
        const batchSize = 400;
        for (let i = 0; i < experienceDocs.length; i += batchSize) {
          const batch = db.batch();
          const chunk = experienceDocs.slice(i, i + batchSize);

          for (const doc of chunk) {
            const expData = doc.data();
            const categoryIds = getCategoryIdsForExperience(expData);

            // Get all users with access to this experience via any of its categories
            const usersWithAccess = await getUsersWithCategoryAccess(
              ownerUserId,
              categoryIds,
            );

            // If user no longer has access via any category, remove them
            if (!usersWithAccess.includes(sharedWithUserId)) {
              batch.update(doc.ref, {
                sharedWithUserIds: FieldValue.arrayRemove(sharedWithUserId),
              });
            }
          }

          await batch.commit();
        }

        functions.logger.log(
          `Processed ${experienceDocs.length} experiences for removed category share`,
        );
      } else if (itemType === "experience") {
        // For direct experience share removal, just remove the userId
        await db
          .collection("experiences")
          .doc(itemId)
          .update({
            sharedWithUserIds: FieldValue.arrayRemove(sharedWithUserId),
          });

        functions.logger.log("Removed sharedWithUserId from experience");
      }
    } catch (error) {
      functions.logger.error("Error in onSharePermissionDeleted:", error);
    }
  },
);

/**
 * When a share permission's access level is updated,
 * we don't need to change sharedWithUserIds (just the access level metadata).
 * This function is a placeholder for future access-level-specific logic.
 */
exports.onSharePermissionUpdated = onDocumentUpdated(
  "share_permissions/{permissionId}",
  async (event) => {
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();

    // Check if accessLevel changed
    if (beforeData.accessLevel !== afterData.accessLevel) {
      const msg = `Access level changed: ${beforeData.accessLevel} -> ` +
        `${afterData.accessLevel} for item ${afterData.itemId}`;
      functions.logger.log(msg);
      // For now, sharedWithUserIds doesn't change, only the permission level
      // If we wanted to store access level in experiences, we'd update here
    }
  },
);

