/**
 * One-time backfill script to enrich place tags on experiences with fewer
 * than 5 visible tags.
 *
 * For each qualifying experience it:
 *   1. Calls the Google Places API (New) to fetch types/primaryType when missing
 *   2. Merges new types with existing, deduplicating case-insensitively
 *   3. Calls Vertex AI (Gemini) to suggest additional human-friendly tags
 *   4. Persists merged tags to both `experiences` and `public_experiences`
 *
 * Usage:
 *   POST /backfillPlaceTags?dryRun=true                    (preview)
 *   POST /backfillPlaceTags?confirm=yes&batchSize=50       (execute)
 */

const { getFirestore } = require("firebase-admin/firestore");
const { onRequest } = require("firebase-functions/v2/https");
const functions = require("firebase-functions");

const db = getFirestore();

const GEMINI_BASE_URL =
  "https://generativelanguage.googleapis.com/v1beta";
const GEMINI_MODEL = "gemini-2.5-flash";

const HIDDEN_PLACE_TYPES = new Set([
  "establishment",
  "point_of_interest",
  "political",
  "premise",
  "street_address",
  "route",
  "floor",
  "room",
  "post_box",
  "postal_town",
  "postal_code",
  "postal_code_prefix",
  "postal_code_suffix",
  "geocode",
  "subpremise",
  "plus_code",
]);

const VISIBLE_TAG_THRESHOLD = 8;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function getVisibleCount(placeTypes) {
  if (!Array.isArray(placeTypes)) return 0;
  return placeTypes.filter((t) => !HIDDEN_PLACE_TYPES.has(t)).length;
}

function formatPlaceType(type) {
  if (!type) return "";
  return type
    .split("_")
    .map((w) => (w.length > 0 ? w[0].toUpperCase() + w.slice(1) : ""))
    .join(" ");
}

/**
 * Get an OAuth2 access token via Application Default Credentials.
 * Reuses a cached token until it expires.
 */
let _cachedAuth = null;
async function getAccessToken() {
  if (!_cachedAuth) {
    const { GoogleAuth } = require("google-auth-library");
    _cachedAuth = new GoogleAuth({
      scopes: ["https://www.googleapis.com/auth/cloud-platform"],
    });
  }
  const client = await _cachedAuth.getClient();
  const tokenRes = await client.getAccessToken();
  return tokenRes.token;
}

/**
 * Fetch types, primaryType, and primaryTypeDisplayName from Places API (New)
 * using Application Default Credentials (no API key needed).
 */
async function callPlacesApi(placeId) {
  const url =
    `https://places.googleapis.com/v1/places/${placeId}`;
  const fieldMask = "types,primaryType,primaryTypeDisplayName";
  const accessToken = await getAccessToken();

  const res = await fetch(url, {
    method: "GET",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${accessToken}`,
      "X-Goog-FieldMask": fieldMask,
    },
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Places API ${res.status}: ${body}`);
  }

  const data = await res.json();
  return {
    types: Array.isArray(data.types) ? data.types : [],
    primaryType: data.primaryType || null,
    primaryTypeDisplayName:
      data.primaryTypeDisplayName?.text || null,
  };
}

/**
 * Use Google AI (Gemini) REST API to suggest additional human-friendly tags.
 * Mirrors the prompt from GeminiService.suggestAdditionalTags in the Flutter app.
 */
async function callGeminiForTags(
  placeName,
  existingTypes,
  primaryTypeDisplayName,
  locationContext,
  geminiApiKey,
) {
  const existingFormatted = (existingTypes || [])
    .map(formatPlaceType)
    .filter((s) => s.length > 0);

  if (primaryTypeDisplayName) {
    existingFormatted.unshift(primaryTypeDisplayName);
  }

  const contextClause = locationContext ?
    ` located in ${locationContext}` :
    "";

  const existingLabel = existingFormatted.length > 0 ?
    existingFormatted.join(", ") :
    "None";

  const prompt = [
    "You are a place tagging assistant. Given a place and its",
    "existing tags, suggest 3-5 additional short descriptive tags",
    "that would help someone browsing a list of saved places.",
    "",
    "PRIORITY ORDER for tags:",
    "1. Specific cuisine or food type (e.g. \"Sushi\", \"Tacos\",",
    "   \"Omakase\", \"BBQ\", \"Ramen\") — ALWAYS include at least",
    "   one if it's a food/drink venue",
    "2. Dining style or format (e.g. \"Fine Dining\", \"Casual\",",
    "   \"Counter Service\", \"Omakase\")",
    "3. Ambiance or vibe (e.g. \"Date Night\", \"Cozy\",",
    "   \"Rooftop\")",
    "4. Distinguishing features (e.g. \"Craft Cocktails\",",
    "   \"Reservations Required\", \"Outdoor Seating\")",
    "",
    "Each tag should be 1-3 words, Title Case, no hashtags.",
    "",
    "Do NOT repeat any existing tags. Do NOT include generic",
    "labels like \"Establishment\", \"Point Of Interest\", \"Food\",",
    "or \"Restaurant\". Do NOT include the place name itself.",
    "",
    `Place: "${placeName}"${contextClause}`,
    `Existing tags: ${existingLabel}`,
    "",
    "Return ONLY a JSON array of strings, nothing else.",
    "Example: [\"Sushi\", \"Omakase\", \"Fine Dining\",",
    "\"Intimate Setting\"]",
  ].join("\n");

  const url =
    `${GEMINI_BASE_URL}/models/${GEMINI_MODEL}:generateContent` +
    `?key=${geminiApiKey}`;

  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: {
        temperature: 0.3,
        maxOutputTokens: 256,
      },
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Gemini API ${res.status}: ${body}`);
  }

  const data = await res.json();
  const text =
    data.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) return [];

  const jsonMatch = text.match(/\[.*\]/s);
  if (!jsonMatch) return [];

  try {
    const parsed = JSON.parse(jsonMatch[0]);
    return parsed
      .filter((s) => typeof s === "string")
      .map((s) => s.trim())
      .filter((s) => s.length > 0 && s.length <= 30);
  } catch {
    return [];
  }
}

/**
 * Merge new tags into existing, deduplicating case-insensitively.
 */
function mergeTags(existing, incoming) {
  const lowerSet = new Set((existing || []).map((t) => t.toLowerCase()));
  const merged = [...(existing || [])];
  for (const tag of incoming || []) {
    if (!lowerSet.has(tag.toLowerCase())) {
      merged.push(tag);
      lowerSet.add(tag.toLowerCase());
    }
  }
  return merged;
}

// ---------------------------------------------------------------------------
// Core backfill logic
// ---------------------------------------------------------------------------

async function backfillAllPlaceTags(options = {}) {
  const {
    batchSize = 50,
    maxExperiences = 5000,
    dryRun = false,
    geminiApiKey = "",
    startAfterDocId = null,
  } = options;

  functions.logger.log(
    `Starting place-tag backfill: batchSize=${batchSize}, ` +
    `max=${maxExperiences}, dryRun=${dryRun}` +
    (startAfterDocId ? `, startAfter=${startAfterDocId}` : ""),
  );

  const startMs = Date.now();
  let scanned = 0;
  let enriched = 0;
  let placesApiCalls = 0;
  let geminiCalls = 0;
  let skipped = 0;
  let errors = 0;
  const errorDetails = [];
  let lastDoc = null;
  let lastDocId = null;

  if (startAfterDocId) {
    const cursorDoc = await db
      .collection("experiences")
      .doc(startAfterDocId)
      .get();
    if (cursorDoc.exists) {
      lastDoc = cursorDoc;
    } else {
      functions.logger.warn(
        `startAfter doc ${startAfterDocId} not found, ` +
        "starting from beginning.",
      );
    }
  }

  while (scanned < maxExperiences) {
    const limit = Math.min(batchSize, maxExperiences - scanned);
    let query = db
      .collection("experiences")
      .orderBy("__name__")
      .limit(limit);

    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snap = await query.get();
    if (snap.empty) {
      functions.logger.log("No more experiences to process.");
      lastDocId = null;
      break;
    }

    for (const doc of snap.docs) {
      const data = doc.data();
      const location = data.location || {};
      const placeId = location.placeId;
      const existingTypes = Array.isArray(location.placeTypes) ?
        location.placeTypes :
        [];
      const visibleCount = getVisibleCount(existingTypes);

      if (!placeId) {
        skipped++;
        continue;
      }

      if (visibleCount >= VISIBLE_TAG_THRESHOLD) {
        skipped++;
        continue;
      }

      // Dry-run: just count qualifying experiences, no API calls
      if (dryRun) {
        enriched++;
        continue;
      }

      const placeName = location.displayName ||
        location.name ||
        data.name ||
        "Unknown";
      const locationContext = location.city || location.address || null;

      try {
        let mergedTypes = [...existingTypes];
        let effectivePrimaryType = location.primaryType || null;
        let effectivePrimaryTypeDisplayName =
          location.primaryTypeDisplayName || null;

        // Step 1: Call Places API if we have no types at all
        if (existingTypes.length === 0) {
          const placesData = await callPlacesApi(placeId);
          placesApiCalls++;

          mergedTypes = mergeTags(mergedTypes, placesData.types);
          if (!effectivePrimaryType && placesData.primaryType) {
            effectivePrimaryType = placesData.primaryType;
          }
          if (!effectivePrimaryTypeDisplayName &&
              placesData.primaryTypeDisplayName) {
            effectivePrimaryTypeDisplayName =
              placesData.primaryTypeDisplayName;
          }

          await sleep(200);
        }

        // Step 2: Call Gemini if still under threshold
        const visibleAfterPlaces = getVisibleCount(mergedTypes);
        if (visibleAfterPlaces < VISIBLE_TAG_THRESHOLD) {
          const suggested = await callGeminiForTags(
            placeName,
            mergedTypes,
            effectivePrimaryTypeDisplayName,
            locationContext,
            geminiApiKey,
          );
          geminiCalls++;

          mergedTypes = mergeTags(mergedTypes, suggested);
          await sleep(300);
        }

        // Check if anything actually changed
        const tagsChanged =
          mergedTypes.length !== existingTypes.length ||
          effectivePrimaryType !== (location.primaryType || null) ||
          effectivePrimaryTypeDisplayName !==
            (location.primaryTypeDisplayName || null);

        if (!tagsChanged) {
          skipped++;
          continue;
        }

        functions.logger.log(
          `[${doc.id}] "${placeName}": ${existingTypes.length} → ` +
          `${mergedTypes.length} tags (visible: ${visibleCount} → ` +
          `${getVisibleCount(mergedTypes)})`,
        );

        if (!dryRun) {
          // Update the experience document
          const locationUpdate = {
            "location.placeTypes": mergedTypes,
          };
          if (effectivePrimaryType) {
            locationUpdate["location.primaryType"] = effectivePrimaryType;
          }
          if (effectivePrimaryTypeDisplayName) {
            locationUpdate["location.primaryTypeDisplayName"] =
              effectivePrimaryTypeDisplayName;
          }
          await doc.ref.update(locationUpdate);

          // Update matching public_experiences document
          if (placeId) {
            try {
              const pubSnap = await db
                .collection("public_experiences")
                .where("placeID", "==", placeId)
                .limit(1)
                .get();

              if (!pubSnap.empty) {
                const pubDoc = pubSnap.docs[0];
                const pubUpdate = {
                  "placeTypes": mergedTypes,
                  "location.placeTypes": mergedTypes,
                };
                if (effectivePrimaryType) {
                  pubUpdate["location.primaryType"] = effectivePrimaryType;
                }
                if (effectivePrimaryTypeDisplayName) {
                  pubUpdate["location.primaryTypeDisplayName"] =
                    effectivePrimaryTypeDisplayName;
                }
                await pubDoc.ref.update(pubUpdate);
              }
            } catch (pubErr) {
              functions.logger.warn(
                `[${doc.id}] Error updating public_experiences: ${pubErr.message}`,
              );
            }
          }
        }

        enriched++;
      } catch (err) {
        errors++;
        errorDetails.push({ id: doc.id, error: err.message });
        functions.logger.error(
          `[${doc.id}] Error enriching "${placeName}": ${err.message}`,
        );
      }
    }

    scanned += snap.size;
    lastDoc = snap.docs[snap.docs.length - 1];
    lastDocId = lastDoc.id;

    functions.logger.log(
      `Batch done: scanned=${scanned}, enriched=${enriched}, ` +
      `skipped=${skipped}, errors=${errors}`,
    );

    await sleep(100);
  }

  const durationMs = Date.now() - startMs;
  const summary = {
    success: true,
    scanned,
    enriched,
    skipped,
    errors,
    placesApiCalls,
    geminiCalls,
    durationMs,
    dryRun,
    ...(lastDocId && { lastDocId }),
    ...(errorDetails.length > 0 && {
      errorSamples: errorDetails.slice(0, 20),
    }),
  };

  functions.logger.log("Place-tag backfill complete:", summary);
  return summary;
}

// ---------------------------------------------------------------------------
// HTTP endpoint
// ---------------------------------------------------------------------------

exports.backfillPlaceTags = onRequest(
  {
    region: "us-central1",
    memory: "1GiB",
    timeoutSeconds: 540,
    secrets: ["GEMINI_API_KEY"],
  },
  async (req, res) => {
    try {
      // Optional shared-secret guard
      const configuredSecret = process.env.MAINTENANCE_SECRET || "";
      if (configuredSecret) {
        const provided =
          req.query.secret ||
          req.body?.secret ||
          req.get("x-admin-secret");
        if (provided !== configuredSecret) {
          res
            .status(403)
            .json({ ok: false, error: "Forbidden: invalid secret" });
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
          error:
            "Missing confirm=yes. Use dryRun=true first to preview.",
          hint: "Add confirm=yes to actually update.",
        });
        return;
      }

      const batchSize = Number(
        req.query.batchSize || req.body?.batchSize || 50,
      );
      const maxExperiences = Number(
        req.query.maxExperiences || req.body?.maxExperiences || 5000,
      );

      const geminiApiKey = process.env.GEMINI_API_KEY || "";
      const startAfterDocId =
        (req.query.startAfter || req.body?.startAfter || "")
          .toString()
          .trim() || null;

      const result = await backfillAllPlaceTags({
        batchSize,
        maxExperiences,
        dryRun,
        geminiApiKey,
        startAfterDocId,
      });

      res.status(200).json(result);
    } catch (error) {
      functions.logger.error("backfillPlaceTags endpoint error:", error);
      res.status(500).json({
        ok: false,
        error: error.message || String(error),
      });
    }
  },
);
