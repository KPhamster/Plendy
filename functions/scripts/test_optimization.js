/**
 * Test script to validate the optimization works correctly.
 *
 * This script can be run locally with Firebase Admin SDK to:
 * 1. Create test data (categories, experiences, shares)
 * 2. Verify sharedWithUserIds is maintained correctly
 * 3. Clean up test data
 *
 * Usage:
 *   node scripts/test_optimization.js
 */

const admin = require("firebase-admin");
const serviceAccount = require("../path/to/serviceAccountKey.json"); // Update path

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

async function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function runTests() {
  console.log("Starting optimization tests...\n");

  const testOwnerUserId = "test_owner_" + Date.now();
  const testSharedUserId = "test_shared_" + Date.now();

  try {
    // 1. Create a test category
    console.log("1. Creating test category...");
    const categoryRef = await db
      .collection("users")
      .doc(testOwnerUserId)
      .collection("categories")
      .add({
        name: "Test Category",
        icon: "🧪",
        ownerUserId: testOwnerUserId,
        orderIndex: 0,
      });
    const categoryId = categoryRef.id;
    console.log(`   Created category: ${categoryId}`);

    // 2. Create test experiences in the category
    console.log("\n2. Creating 5 test experiences...");
    const experienceIds = [];
    for (let i = 0; i < 5; i++) {
      const expRef = await db.collection("experiences").add({
        name: `Test Experience ${i + 1}`,
        description: "Test",
        categoryId: categoryId,
        createdBy: testOwnerUserId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        location: {
          latitude: 0,
          longitude: 0,
        },
        sharedMediaItemIds: [],
        otherCategories: [],
        editorUserIds: [],
      });
      experienceIds.push(expRef.id);
      console.log(`   Created experience ${i + 1}: ${expRef.id}`);
    }

    // 3. Create a share permission for the category
    console.log("\n3. Creating category share permission...");
    const permissionId = `${testOwnerUserId}_category_${categoryId}_${testSharedUserId}`;
    await db.collection("share_permissions").doc(permissionId).set({
      itemId: categoryId,
      itemType: "category",
      ownerUserId: testOwnerUserId,
      sharedWithUserId: testSharedUserId,
      accessLevel: "view",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`   Created permission: ${permissionId}`);

    // 4. Wait for Cloud Function to trigger and update experiences
    console.log("\n4. Waiting 5 seconds for Cloud Function to process...");
    await sleep(5000);

    // 5. Verify all experiences have sharedWithUserIds updated
    console.log("\n5. Verifying experiences have sharedWithUserIds...");
    let successCount = 0;
    let failCount = 0;

    for (const expId of experienceIds) {
      const expDoc = await db.collection("experiences").doc(expId).get();
      const data = expDoc.data();

      if (
        data &&
        Array.isArray(data.sharedWithUserIds) &&
        data.sharedWithUserIds.includes(testSharedUserId)
      ) {
        console.log(`   ✓ Experience ${expId} has sharedWithUserIds`);
        successCount++;
      } else {
        console.log(
          `   ✗ Experience ${expId} missing sharedWithUserIds:`,
          data?.sharedWithUserIds,
        );
        failCount++;
      }
    }

    console.log(
      `\n   Results: ${successCount} success, ${failCount} failures`,
    );

    // 6. Test deletion
    console.log("\n6. Deleting share permission...");
    await db.collection("share_permissions").doc(permissionId).delete();
    console.log("   Deleted permission");

    console.log("\n7. Waiting 5 seconds for cleanup Cloud Function...");
    await sleep(5000);

    // 8. Verify sharedWithUserIds removed
    console.log("\n8. Verifying sharedWithUserIds removed...");
    let removeSuccessCount = 0;
    let removeFailCount = 0;

    for (const expId of experienceIds) {
      const expDoc = await db.collection("experiences").doc(expId).get();
      const data = expDoc.data();

      if (
        !data ||
        !data.sharedWithUserIds ||
        !data.sharedWithUserIds.includes(testSharedUserId)
      ) {
        console.log(
          `   ✓ Experience ${expId} has sharedWithUserIds removed`,
        );
        removeSuccessCount++;
      } else {
        console.log(
          `   ✗ Experience ${expId} still has sharedWithUserIds:`,
          data.sharedWithUserIds,
        );
        removeFailCount++;
      }
    }

    console.log(
      `\n   Results: ${removeSuccessCount} success, ${removeFailCount} failures`,
    );

    // 9. Cleanup
    console.log("\n9. Cleaning up test data...");
    const batch = db.batch();

    // Delete category
    batch.delete(
      db
        .collection("users")
        .doc(testOwnerUserId)
        .collection("categories")
        .doc(categoryId),
    );

    // Delete experiences
    for (const expId of experienceIds) {
      batch.delete(db.collection("experiences").doc(expId));
    }

    await batch.commit();
    console.log("   Cleanup complete");

    // Final summary
    console.log("\n" + "=".repeat(60));
    console.log("TEST SUMMARY");
    console.log("=".repeat(60));
    console.log(`Share creation test: ${successCount}/${experienceIds.length} passed`);
    console.log(`Share deletion test: ${removeSuccessCount}/${experienceIds.length} passed`);

    if (successCount === experienceIds.length && removeSuccessCount === experienceIds.length) {
      console.log("\n✅ ALL TESTS PASSED");
      console.log("\nThe optimization is working correctly!");
      console.log("Cloud Functions are maintaining sharedWithUserIds properly.");
    } else {
      console.log("\n❌ SOME TESTS FAILED");
      console.log("\nPossible issues:");
      console.log("- Cloud Functions not deployed");
      console.log("- Functions experiencing errors (check Firebase Console logs)");
      console.log("- Timing issues (try increasing wait times)");
    }
  } catch (error) {
    console.error("\nTest error:", error);
    console.log("\nAttempting cleanup...");

    try {
      // Best-effort cleanup
      const batch = db.batch();
      const categorySnap = await db
        .collection("users")
        .doc(testOwnerUserId)
        .collection("categories")
        .get();
      categorySnap.docs.forEach((doc) => batch.delete(doc.ref));

      const expSnap = await db
        .collection("experiences")
        .where("createdBy", "==", testOwnerUserId)
        .get();
      expSnap.docs.forEach((doc) => batch.delete(doc.ref));

      const permSnap = await db
        .collection("share_permissions")
        .where("ownerUserId", "==", testOwnerUserId)
        .get();
      permSnap.docs.forEach((doc) => batch.delete(doc.ref));

      await batch.commit();
      console.log("Cleanup complete");
    } catch (cleanupError) {
      console.error("Cleanup error:", cleanupError);
    }
  }

  process.exit(0);
}

runTests();

