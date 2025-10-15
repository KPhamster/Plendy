/**
 * One-time backfill script to populate sharedWithUserIds on existing experiences.
 *
 * This can be run as an HTTP Cloud Function or as a local admin script.
 *
 * Usage:
 *   Deploy as HTTP function and call:
 *   POST /backfillSharedUserIds?confirm=yes&batchSize=100&maxExperiences=1000
 *
 * Or run locally with Firebase Admin SDK.
 */

const { getFirestore } = require("firebase-admin/firestore");
const { onRequest } = require("firebase-functions/v2/https");
const functions = require("firebase-functions");

const db = getFirestore();

/**
 * Helper: Get category IDs that an experience belongs to.
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
 * Helper: Get all user IDs with access to an experience via category shares.
 */
async function getUsersWithCategoryAccess(ownerUserId, categoryIds) {
  if (!categoryIds || categoryIds.length === 0) return [];

  const sharedUserIds = new Set();

  try {
    // Query share_permissions for category shares in chunks
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

    // Also check for direct experience shares
    const expShareSnap = await db
      .collection("share_permissions")
      .where("itemType", "==", "experience")
      .where("ownerUserId", "==", ownerUserId)
      .get();

    expShareSnap.docs.forEach((doc) => {
      const data = doc.data();
      if (data.sharedWithUserId && data.sharedWithUserId !== ownerUserId) {
        sharedUserIds.add(data.sharedWithUserId);
      }
    });
  } catch (error) {
    functions.logger.error("getUsersWithCategoryAccess error:", error);
  }

  return Array.from(sharedUserIds);
}

/**
 * Backfill sharedWithUserIds for all experiences.
 */
async function backfillAllExperiences(options = {}) {
  const {
    batchSize = 100,
    maxExperiences = 1000,
    dryRun = false,
  } = options;

  functions.logger.log(
    `Starting backfill: batchSize=${batchSize}, maxExperiences=${maxExperiences}, dryRun=${dryRun}`,
  );

  const startMs = Date.now();
  let processedCount = 0;
  let updatedCount = 0;
  let lastDoc = null;

  try {
    while (processedCount < maxExperiences) {
      const limit = Math.min(batchSize, maxExperiences - processedCount);

      let query = db
        .collection("experiences")
        .orderBy("createdAt", "desc")
        .limit(limit);

      if (lastDoc) {
        query = query.startAfter(lastDoc);
      }

      const snap = await query.get();

      if (snap.empty) {
        functions.logger.log("No more experiences to process");
        break;
      }

      // Process this batch
      const writeBatch = db.batch();
      let batchUpdateCount = 0;

      for (const doc of snap.docs) {
        const expData = doc.data();
        const ownerUserId = expData.createdBy;

        if (!ownerUserId) {
          functions.logger.warn(`Experience ${doc.id} has no createdBy field`);
          continue;
        }

        // Get all category IDs for this experience
        const categoryIds = getCategoryIdsForExperience(expData);

        // Get all users with access via category shares
        const sharedUserIds = await getUsersWithCategoryAccess(
          ownerUserId,
          categoryIds,
        );

        // Only update if there are shared users
        if (sharedUserIds.length > 0) {
          if (!dryRun) {
            writeBatch.update(doc.ref, {
              sharedWithUserIds: sharedUserIds,
            });
          }
          batchUpdateCount++;
        }
      }

      if (!dryRun && batchUpdateCount > 0) {
        await writeBatch.commit();
      }

      processedCount += snap.size;
      updatedCount += batchUpdateCount;
      lastDoc = snap.docs[snap.docs.length - 1];

      functions.logger.log(
        `Processed batch: ${processedCount} total, ${batchUpdateCount} updated in this batch`,
      );

      // Small delay to avoid overwhelming Firestore
      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    const durationMs = Date.now() - startMs;
    const summary = {
      success: true,
      processedCount,
      updatedCount,
      durationMs,
      dryRun,
    };

    functions.logger.log("Backfill complete:", summary);
    return summary;
  } catch (error) {
    functions.logger.error("Backfill error:", error);
    throw error;
  }
}

/**
 * HTTP endpoint to trigger the backfill.
 */
exports.backfillSharedUserIds = onRequest({
  region: "us-central1",
  memory: "1GiB",
  timeoutSeconds: 540,
}, async (req, res) => {
  try {
    // Simple auth check (optional)
    const secret = process.env.MAINTENANCE_SECRET || "";
    if (secret) {
      const providedSecret =
        req.query.secret || req.body?.secret || req.get("x-admin-secret");
      if (providedSecret !== secret) {
        res.status(403).json({ ok: false, error: "Forbidden: invalid secret" });
        return;
      }
    }

    const dryRunRaw = req.query.dryRun || req.body?.dryRun;
    const dryRun =
      typeof dryRunRaw === "string" ?
        dryRunRaw.toLowerCase() === "true" :
        Boolean(dryRunRaw);

    const confirm = (req.query.confirm || req.body?.confirm || "")
      .toString()
      .toLowerCase();

    if (!dryRun && confirm !== "yes") {
      res.status(400).json({
        ok: false,
        error: "Missing confirm=yes. Use dryRun=true first to preview.",
        hint: "Add confirm=yes to actually update. Example: ?confirm=yes",
      });
      return;
    }

    const batchSize = Number(req.query.batchSize || req.body?.batchSize || 100);
    const maxExperiences = Number(
      req.query.maxExperiences || req.body?.maxExperiences || 1000,
    );

    const result = await backfillAllExperiences({
      batchSize,
      maxExperiences,
      dryRun,
    });

    res.status(200).json(result);
  } catch (error) {
    functions.logger.error("backfillSharedUserIds endpoint error:", error);
    res.status(500).json({
      ok: false,
      error: error.message || String(error),
    });
  }
});

// Export the backfill function for use in other contexts
exports.backfillAllExperiences = backfillAllExperiences;

