/**
 * Local backfill script to populate sharedWithUserIds on existing experiences.
 *
 * This runs directly from your machine, avoiding Cloud Function timeout limits.
 *
 * Setup:
 *   1. Download service account key from Firebase Console:
 *      Project Settings > Service Accounts > Generate New Private Key
 *   2. Save as functions/serviceAccountKey.json
 *   3. Run: node run_backfill_local.js
 */

const admin = require("firebase-admin");
const path = require("path");
const fs = require("fs");

// Try to load service account key
const keyPath = path.join(__dirname, "serviceAccountKey.json");
if (!fs.existsSync(keyPath)) {
  console.error("\n❌ ERROR: Service account key not found!");
  console.error("\nPlease follow these steps:");
  console.error("1. Go to Firebase Console > Project Settings > Service Accounts");
  console.error("2. Click 'Generate New Private Key'");
  console.error("3. Save the downloaded file as:");
  console.error(`   ${keyPath}`);
  console.error("\nThen run this script again.\n");
  process.exit(1);
}

const serviceAccount = require("./serviceAccountKey.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

/**
 * Get category IDs that an experience belongs to
 */
function getCategoryIdsForExperience(expData) {
  const categoryIds = new Set();

  if (expData.categoryId) {
    categoryIds.add(expData.categoryId);
  }

  if (Array.isArray(expData.otherCategories)) {
    expData.otherCategories.forEach((id) => categoryIds.add(id));
  }

  if (expData.colorCategoryId) {
    categoryIds.add(expData.colorCategoryId);
  }

  return Array.from(categoryIds);
}

/**
 * Get all user IDs with access to categories
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
    console.error("Error getting users with category access:", error);
  }

  return Array.from(sharedUserIds);
}

/**
 * Main backfill function
 */
async function backfillAllExperiences(dryRun = false) {
  console.log("\n" + "=".repeat(70));
  console.log("BACKFILL SHAREDWITHUSERIDS");
  console.log("=".repeat(70));
  console.log(`Mode: ${dryRun ? "DRY RUN (preview only)" : "LIVE (will update Firestore)"}`);
  console.log(`Started: ${new Date().toLocaleString()}\n`);

  const batchSize = 50;
  let processedCount = 0;
  let updatedCount = 0;
  let lastDoc = null;
  const startMs = Date.now();
  let hasMore = true;

  try {
    while (hasMore) {
      // Fetch next batch of experiences
      let query = db
        .collection("experiences")
        .orderBy("createdAt", "desc")
        .limit(batchSize);

      if (lastDoc) {
        query = query.startAfter(lastDoc);
      }

      const snap = await query.get();

      if (snap.empty) {
        console.log("\n✓ No more experiences to process");
        hasMore = false;
        break;
      }

      // Process this batch
      const writeBatch = db.batch();
      let batchUpdateCount = 0;

      for (const doc of snap.docs) {
        const expData = doc.data();
        const ownerUserId = expData.createdBy;

        if (!ownerUserId) {
          console.log(`  ⚠ Experience ${doc.id} has no createdBy field, skipping`);
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

          if (batchUpdateCount <= 3) {
            // Show first few updates
            console.log(
              `  ✓ Experience "${expData.name}" → ${sharedUserIds.length} shared user(s)`,
            );
          }
        }
      }

      if (!dryRun && batchUpdateCount > 0) {
        await writeBatch.commit();
      }

      processedCount += snap.size;
      updatedCount += batchUpdateCount;
      lastDoc = snap.docs[snap.docs.length - 1];

      console.log(
        `Batch complete: ${processedCount} total processed, ${batchUpdateCount} updated in this batch`,
      );

      // Small delay to avoid overwhelming Firestore
      await new Promise((resolve) => setTimeout(resolve, 200));
    }

    const durationMs = Date.now() - startMs;
    const durationSec = Math.round(durationMs / 1000);

    console.log("\n" + "=".repeat(70));
    console.log("BACKFILL COMPLETE");
    console.log("=".repeat(70));
    console.log(`Total experiences processed: ${processedCount}`);
    console.log(`Experiences updated: ${updatedCount}`);
    console.log(`Duration: ${durationSec} seconds (${Math.round(durationMs / 60000)} minutes)`);
    console.log(`Mode: ${dryRun ? "DRY RUN" : "LIVE"}`);

    if (dryRun) {
      console.log("\n💡 This was a preview. To actually update, run:");
      console.log("   node run_backfill_local.js --confirm");
    } else {
      console.log("\n✅ SUCCESS! sharedWithUserIds populated on all experiences.");
      console.log("\n📱 Next: Test the app Collections screen for faster loading!");
    }

    return {
      success: true,
      processedCount,
      updatedCount,
      durationMs,
      dryRun,
    };
  } catch (error) {
    console.error("\n❌ ERROR during backfill:", error);
    console.error("\nPartial progress:");
    console.error(`  - Processed: ${processedCount} experiences`);
    console.error(`  - Updated: ${updatedCount} experiences`);
    throw error;
  }
}

// Parse command line arguments
const args = process.argv.slice(2);
const dryRun = !args.includes("--confirm");

if (dryRun) {
  console.log("\n⚠️  DRY RUN MODE - No changes will be made");
  console.log("    This will preview what would be updated\n");
} else {
  console.log("\n⚡ LIVE MODE - Firestore will be updated");
  console.log("    Press Ctrl+C within 5 seconds to cancel...\n");
}

// Small delay before starting
setTimeout(() => {
  backfillAllExperiences(dryRun)
    .then((result) => {
      console.log("\nBackfill completed successfully!");
      process.exit(0);
    })
    .catch((error) => {
      console.error("\nBackfill failed:", error);
      process.exit(1);
    });
}, dryRun ? 0 : 5000);

