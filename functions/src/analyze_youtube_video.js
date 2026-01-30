/**
 * Cloud Function to analyze YouTube videos using Vertex AI Gemini
 *
 * This function fetches the video transcript (captions) and uses Gemini
 * to extract location information from what's actually said in the video.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { VertexAI } = require("@google-cloud/vertexai");
const { YoutubeTranscript } = require("youtube-transcript");

// Initialize Vertex AI
const PROJECT_ID = "plendy-7df50";
const LOCATION = "us-central1";

// YouTube Data API key (optional - provides title and description)
const YOUTUBE_API_KEY = process.env.YOUTUBE_API_KEY || "";

/**
 * Analyzes a YouTube video to extract location information
 */
exports.analyzeYouTubeVideo = onCall(
  {
    timeoutSeconds: 120,
    memory: "512MiB",
    secrets: ["YOUTUBE_API_KEY"],
  },
  async (request) => {
    // Verify the user is authenticated
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "User must be authenticated to analyze videos",
      );
    }

    const { youtubeUrl } = request.data;

    if (!youtubeUrl) {
      throw new HttpsError(
        "invalid-argument",
        "YouTube URL is required",
      );
    }

    // Extract video ID from URL
    const videoId = extractVideoId(youtubeUrl);
    if (!videoId) {
      throw new HttpsError(
        "invalid-argument",
        "Could not extract video ID from URL",
      );
    }

    console.log(`🎬 Analyzing YouTube video: ${youtubeUrl} (ID: ${videoId})`);

    try {
      // Step 1: Fetch video metadata and transcript in parallel
      const [videoMetadata, transcript] = await Promise.all([
        fetchYouTubeMetadata(videoId),
        fetchYouTubeTranscript(videoId),
      ]);

      if (!videoMetadata && !transcript) {
        console.log("⚠️ Could not fetch any video data");
        return { locations: [], error: "Could not fetch video data" };
      }

      console.log(`📹 Video title: ${videoMetadata?.title || "N/A"}`);
      console.log(`📝 Description: ${videoMetadata?.description?.length || 0} chars`);
      console.log(`🎤 Transcript: ${transcript?.length || 0} chars`);

      // If we have no content at all (not even a title), return empty
      if (!transcript && !videoMetadata?.description && !videoMetadata?.title) {
        console.log("⚠️ No video content available - cannot analyze");
        return { locations: [], error: null };
      }

      // If we only have a title but no actual content, don't try to hallucinate
      if (!transcript && !videoMetadata?.description && videoMetadata?.title) {
        console.log("⚠️ No transcript/description available - only title exists");
        console.log("💡 User should use 'Scan Preview' to capture video content");
        return {
          locations: [],
          error: null,
          message: "No transcript or description available. Try using 'Scan Preview' to capture video content.",
        };
      }

      // Step 2: Use Gemini to analyze the content for locations
      const vertexAI = new VertexAI({
        project: PROJECT_ID,
        location: LOCATION,
      });

      const model = vertexAI.getGenerativeModel({
        model: "gemini-2.0-flash-exp",
        generationConfig: {
          temperature: 0.1,
          topP: 0.8,
          topK: 40,
          maxOutputTokens: 4096,
        },
      });

      const prompt = buildLocationExtractionPrompt(videoMetadata, transcript);

      console.log("🤖 Calling Vertex AI to analyze video content...");

      const result = await model.generateContent({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
      });

      const response = await result.response;
      const text = response.candidates?.[0]?.content?.parts?.[0]?.text;

      if (!text) {
        console.log("⚠️ No text response from Vertex AI");
        return { locations: [], error: null };
      }

      console.log(`📝 Vertex AI Response: ${text.substring(0, 300)}...`);

      const locations = parseLocationsFromResponse(text);

      console.log(`✅ Found ${locations.length} location(s) from YouTube video`);
      if (locations.length > 0) {
        locations.forEach((loc) => {
          console.log(`   📍 ${loc.name} (${loc.city || "no city"})`);
        });
      }

      // Build the analyzed content text for user verification
      // This shows users what text was analyzed to find the locations
      let analyzedContent = "";
      if (videoMetadata?.title) {
        analyzedContent += `Title: ${videoMetadata.title}\n\n`;
      }
      if (videoMetadata?.description) {
        // Truncate long descriptions for display
        const desc = videoMetadata.description.length > 1000 ?
          videoMetadata.description.substring(0, 1000) + "..." :
          videoMetadata.description;
        analyzedContent += `Description:\n${desc}\n\n`;
      }
      if (transcript) {
        // Truncate long transcripts for display
        const truncatedTranscript = transcript.length > 2000 ?
          transcript.substring(0, 2000) + "..." :
          transcript;
        analyzedContent += `Transcript:\n${truncatedTranscript}`;
      }

      return {
        locations,
        error: null,
        analyzedContent: analyzedContent.trim() || null,
      };
    } catch (error) {
      console.error("❌ Error analyzing video:", error.message);
      console.error("Stack:", error.stack);

      return {
        locations: [],
        error: error.message || "Failed to analyze video",
      };
    }
  });

/**
 * Extract video ID from various YouTube URL formats
 */
function extractVideoId(url) {
  const patterns = [
    /(?:youtube\.com\/watch\?.*v=)([a-zA-Z0-9_-]{11})/,
    /(?:youtu\.be\/)([a-zA-Z0-9_-]{11})/,
    /(?:youtube\.com\/embed\/)([a-zA-Z0-9_-]{11})/,
    /(?:youtube\.com\/shorts\/)([a-zA-Z0-9_-]{11})/,
  ];

  for (const pattern of patterns) {
    const match = url.match(pattern);
    if (match && match[1]) {
      return match[1];
    }
  }

  return null;
}

/**
 * Fetch video transcript (auto-generated or manual captions)
 */
async function fetchYouTubeTranscript(videoId) {
  // Try multiple language codes since some videos have different caption languages
  const languageCodes = ["en", "en-US", "en-GB", undefined];

  for (const lang of languageCodes) {
    try {
      console.log(`🎤 Fetching transcript for video: ${videoId} (lang: ${lang || "auto"})`);

      const config = lang ? { lang } : {};
      const transcriptItems = await YoutubeTranscript.fetchTranscript(videoId, config);

      if (!transcriptItems || transcriptItems.length === 0) {
        continue;
      }

      // Combine all transcript segments into one text
      const fullTranscript = transcriptItems
        .map((item) => item.text)
        .join(" ")
        .replace(/\s+/g, " ")
        .trim();

      console.log(`✅ Fetched transcript: ${fullTranscript.length} characters`);

      // Truncate if too long (keep first ~8000 chars)
      if (fullTranscript.length > 8000) {
        return fullTranscript.substring(0, 8000) + "...";
      }

      return fullTranscript;
    } catch (error) {
      console.log(`⚠️ Transcript fetch failed (lang: ${lang || "auto"}): ${error.message}`);
    }
  }

  console.log("⚠️ All transcript fetch attempts failed");
  return null;
}

/**
 * Fetch video metadata from YouTube
 */
async function fetchYouTubeMetadata(videoId) {
  // Try YouTube Data API first (provides description)
  if (YOUTUBE_API_KEY) {
    try {
      console.log("🔑 Using YouTube Data API to fetch metadata");
      const apiUrl = "https://www.googleapis.com/youtube/v3/videos?" +
        `part=snippet&id=${videoId}&key=${YOUTUBE_API_KEY}`;

      const response = await fetch(apiUrl);
      const data = await response.json();

      if (data.items && data.items.length > 0) {
        const snippet = data.items[0].snippet;
        return {
          title: snippet.title || "",
          description: snippet.description || "",
          channelTitle: snippet.channelTitle || "",
          tags: snippet.tags || [],
        };
      }
    } catch (error) {
      console.log("⚠️ YouTube Data API failed:", error.message);
    }
  } else {
    console.log("⚠️ YOUTUBE_API_KEY not set, trying web scraping fallback");
  }

  // Try web scraping to get the description
  try {
    console.log("🌐 Fetching video page to scrape metadata...");
    const videoUrl = `https://www.youtube.com/watch?v=${videoId}`;
    const userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " +
      "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
    const response = await fetch(videoUrl, {
      headers: {
        "User-Agent": userAgent,
        "Accept-Language": "en-US,en;q=0.9",
      },
    });

    const html = await response.text();

    // Extract title from og:title or title tag
    let title = "";
    const ogTitleMatch = html.match(/<meta property="og:title" content="([^"]+)"/);
    if (ogTitleMatch) {
      title = decodeHTMLEntities(ogTitleMatch[1]);
    }

    // Extract description from og:description or meta description
    let description = "";
    const ogDescMatch = html.match(/<meta property="og:description" content="([^"]+)"/);
    if (ogDescMatch) {
      description = decodeHTMLEntities(ogDescMatch[1]);
    }

    // Try to get full description from the page's JSON data
    const jsonMatch = html.match(/var ytInitialPlayerResponse\s*=\s*({.+?});/);
    if (jsonMatch) {
      try {
        const playerData = JSON.parse(jsonMatch[1]);
        const fullDesc = playerData?.videoDetails?.shortDescription;
        if (fullDesc) {
          description = fullDesc;
          console.log(`✅ Found full description from player data: ${description.length} chars`);
        }
      } catch (e) {
        // JSON parsing failed, use og:description
      }
    }

    // Also try ytInitialData for more complete description
    const initialDataMatch = html.match(/var ytInitialData\s*=\s*({.+?});/);
    if (initialDataMatch && !description) {
      try {
        const initialData = JSON.parse(initialDataMatch[1]);
        // Navigate to description in the complex YouTube data structure
        const descObj = initialData?.contents?.twoColumnWatchNextResults?.results?.results?.contents;
        if (descObj) {
          for (const content of descObj) {
            const desc = content?.videoSecondaryInfoRenderer?.attributedDescription?.content;
            if (desc) {
              description = desc;
              console.log(`✅ Found description from initialData: ${description.length} chars`);
              break;
            }
          }
        }
      } catch (e) {
        // JSON parsing failed
      }
    }

    // Extract channel name
    let channelTitle = "";
    const channelMatch = html.match(/<link itemprop="name" content="([^"]+)"/);
    if (channelMatch) {
      channelTitle = decodeHTMLEntities(channelMatch[1]);
    }

    if (title || description) {
      console.log(`✅ Scraped metadata - Title: ${title.length} chars, Description: ${description.length} chars`);
      return {
        title: title,
        description: description,
        channelTitle: channelTitle,
        tags: [],
      };
    }
  } catch (error) {
    console.log("⚠️ Web scraping failed:", error.message);
  }

  // Final fallback to oEmbed (only provides title and author, no description)
  try {
    console.log("📦 Falling back to oEmbed (no description available)");
    const oembedUrl = "https://www.youtube.com/oembed?" +
      `url=https://www.youtube.com/watch?v=${videoId}&format=json`;

    const response = await fetch(oembedUrl);
    const data = await response.json();

    return {
      title: data.title || "",
      description: "",
      channelTitle: data.author_name || "",
      tags: [],
    };
  } catch (error) {
    console.error("❌ Failed to fetch YouTube metadata:", error.message);
    return null;
  }
}

/**
 * Decode HTML entities in a string
 */
function decodeHTMLEntities(text) {
  const entities = {
    "&amp;": "&",
    "&lt;": "<",
    "&gt;": ">",
    "&quot;": "\"",
    "&#39;": "'",
    "&#x27;": "'",
    "&#x2F;": "/",
    "&#32;": " ",
    "&nbsp;": " ",
  };

  return text.replace(/&[^;]+;/g, (entity) => {
    return entities[entity] || entity;
  });
}

/**
 * Build the prompt for extracting locations from video content
 */
function buildLocationExtractionPrompt(metadata, transcript) {
  // Check if this is a "Top 10" or list-style video
  const title = metadata?.title || "";
  const isTopListVideo = /top\s*\d+|best\s*\d+|\d+\s*best/i.test(title);

  let prompt = `You are an expert at extracting location and place information from text.
Analyze this YouTube video's content to identify any locations, businesses, restaurants,
attractions, or places mentioned.

=== VIDEO INFORMATION ===
`;

  if (metadata) {
    prompt += `\n**Title:** ${metadata.title}\n`;
    prompt += `**Channel:** ${metadata.channelTitle}\n`;

    if (metadata.description) {
      const truncatedDesc = metadata.description.length > 2000 ?
        metadata.description.substring(0, 2000) + "..." :
        metadata.description;
      prompt += `\n**Description:**\n${truncatedDesc}\n`;
    }

    if (metadata.tags && metadata.tags.length > 0) {
      prompt += `\n**Tags:** ${metadata.tags.slice(0, 20).join(", ")}\n`;
    }
  }

  if (transcript) {
    prompt += `
=== VIDEO TRANSCRIPT (What is said in the video) ===

${transcript}

`;
  }

  prompt += `
=== WHAT TO LOOK FOR ===
`;

  if (isTopListVideo && !transcript) {
    prompt += `
**IMPORTANT:** This appears to be a "Top 10" or list-style video.
Since no transcript is available, ONLY extract locations that are EXPLICITLY mentioned
in the description or tags. DO NOT guess or infer what places might be in the video.

If there's no description or transcript, return an empty array: []

Look for specific mentions of:`;
  } else if (transcript) {
    prompt += `
**IMPORTANT:** Focus on the TRANSCRIPT above - this is what the person actually says.

Look for specific mentions of:`;
  } else {
    prompt += `
**IMPORTANT:** Based on the title and description provided.

Look for specific mentions of:`;
  }

  prompt += `

- Restaurant, cafe, bar, or food establishment names (e.g., "We're at Joe's Pizza")
- Hotel, resort, or accommodation names
- Tourist attractions, landmarks, or points of interest
- Store, shop, or business names
- Parks, beaches, or natural areas
- Specific addresses or location names mentioned verbally
- City and neighborhood names WITH specific places

**DO NOT extract:**
- Generic city names without specific places
- Generic terms like "restaurant" or "cafe" without names
- Places that are only possibilities or suggestions, not actual visits

=== OUTPUT REQUIREMENTS ===

For EACH distinct place found, provide:
1. The exact business or place name as mentioned
2. The city if mentioned or can be inferred
3. The type of place

=== OUTPUT FORMAT ===

Return ONLY a valid JSON array. No other text before or after.

[
  {
    "name": "Business or Place Name",
    "address": null,
    "city": "City name or null",
    "region": "State/Region or null",
    "country": "Country or null",
    "type": "restaurant/cafe/bar/hotel/attraction/store/park/landmark"
  }
]

=== IMPORTANT ===

- Extract ONLY locations that are EXPLICITLY mentioned in the transcript or description
- DO NOT guess or infer locations based on the video title alone
- DO NOT hallucinate or make up restaurants that might be in the video
- If the video reviews multiple restaurants, extract ALL that are explicitly mentioned
- If someone says "we went to Shake Shack", extract "Shake Shack"
- If no specific location information is EXPLICITLY stated, return: []
- Return ONLY the JSON array, no markdown code blocks`;

  return prompt;
}

/**
 * Parse locations from the AI response text
 */
function parseLocationsFromResponse(text) {
  try {
    let jsonText = text.trim();

    if (jsonText.startsWith("```json")) {
      jsonText = jsonText.slice(7);
    } else if (jsonText.startsWith("```")) {
      jsonText = jsonText.slice(3);
    }
    if (jsonText.endsWith("```")) {
      jsonText = jsonText.slice(0, -3);
    }
    jsonText = jsonText.trim();

    const arrayMatch = jsonText.match(/\[[\s\S]*\]/);
    if (arrayMatch) {
      jsonText = arrayMatch[0];
    }

    const parsed = JSON.parse(jsonText);

    if (!Array.isArray(parsed)) {
      console.log("⚠️ Response is not an array");
      return [];
    }

    return parsed.map((loc) => ({
      name: loc.name || null,
      address: loc.address || null,
      city: loc.city || null,
      region: loc.region || null,
      country: loc.country || null,
      type: loc.type || "unknown",
    })).filter((loc) => loc.name);
  } catch (parseError) {
    console.error("❌ Failed to parse locations JSON:", parseError.message);
    console.log("Raw text:", text);
    return [];
  }
}
