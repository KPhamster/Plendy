# AI Location Extraction Feature

## Overview
Plendy uses Google's Gemini AI with Maps grounding to automatically extract location information from shared URLs and create experience cards.

## What Works Best ✅

### Excellent Results:
1. **Blog posts and articles** mentioning restaurants, cafes, attractions
   - Example: "Top 10 Restaurants in NYC" → Creates 10 cards
   
2. **Yelp URLs** - Direct business pages
   - Fast path extraction + AI verification
   
3. **Google Maps URLs** - Direct place links
   - Extracts Place ID directly
   
4. **YouTube videos** with locations in title/description
   - Example: "Best Pizza in Chicago - Joe's Pizza"
   
5. **Websites** with clear location mentions
   - Business websites, travel guides, etc.

### Good Results:
- TikTok videos (if caption mentions location)
- Facebook posts (if accessible)
- Twitter/X posts with location tags

### Limited Results:
- **Instagram reels/posts**: Often blocked from metadata fetching
- **Private social media posts**: Cannot access content
- **Paywalled content**: Cannot read behind paywall

## How It Works

1. **User pastes URL** in the share screen
2. **Extraction strategies** (in order):
   - **Strategy 1**: Direct URL parsing (Yelp, Google Maps, Instagram locations)
   - **Strategy 2**: Fetch page metadata + Gemini AI with Maps grounding
   - **Strategy 3**: Google Places API search fallback

3. **Results**:
   - **Single location**: Auto-fills first experience card
   - **Multiple locations**: Shows dialog to create separate cards

## API Usage

- **Free tier**: 500 requests/day
- **Cost**: $25 per 1,000 grounded prompts (only charged when Maps data returned)
- **Caching**: Results are cached to minimize API calls

## Instagram Workaround 💡

### The Challenge
Instagram oEmbed API **requires Facebook App Review** to use:
- Meta requires "oEmbed Read" permission approval
- Review process takes days to weeks
- Requires detailed justification

### Current Solution: Manual Caption Entry
For Instagram posts with locations:

1. **Open the Instagram post** in app or browser
2. **Copy the caption text** (long-press on caption)
3. **Paste into Plendy's URL field** instead of or with the URL
4. **AI extracts location** from the caption text

**Example:**
```
Instead of just pasting:
https://www.instagram.com/reel/ABC123/

Paste the caption text:
"Amazing lunch at Joe's Pizza 🍕 123 Main St, NYC"
```

### Instagram Location URLs Still Work
These URLs extract locations directly:
- `instagram.com/explore/locations/123456/place-name/`
- Direct location page URLs (not post URLs)

## Configuration

### Required: Gemini API Key
Add your Gemini API key in `lib/config/api_keys.dart`:
```dart
static const String geminiApiKey = 'YOUR_KEY_HERE';
```
Get your key: https://aistudio.google.com/app/apikey

### Optional: Instagram Caption Fetching
For automatic Instagram caption extraction, set up a Facebook App:
```dart
static const String facebookAppId = 'YOUR_APP_ID';
static const String facebookAppSecret = 'YOUR_APP_SECRET';
```

See **SETUP_INSTAGRAM_API.md** for detailed instructions (takes 5 minutes).

Without this, Instagram posts will require manual caption entry.

## Debugging

Enable verbose logging to see:
- What Gemini returned
- Grounding metadata
- Extraction strategy used
- Cache hits/misses

Look for these log tags:
- `🤖 GEMINI` - AI service calls
- `🔍 EXTRACTION` - Extraction service
- `📄 EXTRACTION` - Metadata fetching
- `📍 EXTRACTION` - Results summary
