# Instagram Caption Fetching Setup

⚠️ **UPDATE: Instagram oEmbed API now requires Facebook App Review**

## Current Status: Not Available Without Review ❌

As of 2025, Meta requires **App Review approval** to use the Instagram oEmbed API:
- Requires "Meta oEmbed Read" permission
- Review process takes days to weeks
- Must provide detailed use case justification
- May be rejected if use case doesn't meet Meta's criteria

## Recommended Approach: Manual Caption Entry ✅

**Instead of automatic caption fetching, users can:**
1. Open Instagram post and copy the caption text
2. Paste caption text into Plendy's URL field
3. AI extracts location from the text automatically

**This works just as well** without requiring app review!

## Alternative: If You Want to Apply for App Review

If you still want automatic Instagram caption fetching, you'll need to go through Facebook's app review process.

### Setup Steps (Then Apply for Review)

### Step 1: Create a Facebook App

1. Go to https://developers.facebook.com/apps/
2. Click **"Create App"**
3. Choose **"Other"** as the use case
4. Choose **"Business"** as the app type
5. Fill in:
   - **App name**: "Plendy" (or your choice)
   - **App contact email**: Your email
6. Click **"Create App"**

### Step 2: Get Your Credentials

After creating the app:

1. You'll see your **Dashboard**
2. In the left sidebar, click **"Settings"** → **"Basic"**
3. Copy these two values:
   - **App ID**: A number like `123456789012345`
   - **App Secret**: Click **"Show"** to reveal it (like `abc123def456...`)

### Step 3: Add to Plendy

Open `lib/config/api_keys.dart` and update:

```dart
// Facebook/Instagram App credentials (for Instagram oEmbed API)
static const String facebookAppId = '123456789012345'; // ← Your App ID
static const String facebookAppSecret = 'abc123def456...'; // ← Your App Secret
```

### Step 4: Test It

1. Run the app
2. Share an Instagram reel/post URL
3. Check logs for:
   ```
   📸 INSTAGRAM: Fetching caption from oEmbed API...
   ✅ INSTAGRAM: Got caption (XX chars)
   📍 Location found: [Place Name]
   ```

## Important Notes

### What This API Can Do ✅
- Fetch captions from **public** Instagram posts/reels/IGTV
- No user authentication required
- No rate limits for reasonable usage
- Official Instagram API (not scraping)

### What This API Cannot Do ❌
- **Private posts**: Won't work (returns 400 error)
- **Location tags**: Instagram removed these from API in 2025
- **Images/videos**: Only gets text caption
- **Stories**: Not supported by oEmbed

### Privacy & Compliance

This API is:
- ✅ **Official Instagram API** - Not scraping or violating ToS
- ✅ **Public data only** - Only works for public posts
- ✅ **No user data** - Doesn't require user login or permissions
- ✅ **Free** - No costs from Instagram/Facebook

### Troubleshooting

**"API not configured" error:**
- Check that App ID and Secret are in `api_keys.dart`
- Make sure you removed `YOUR_` placeholder text

**"Bad request - possibly private post":**
- The post is private or the URL is invalid
- Try with a public Instagram post

**No caption extracted:**
- Post might not have a caption
- Caption might be in HTML format we can't parse (rare)

## Alternative: Manual Caption Entry

If you don't want to set up the API, users can:
1. Open Instagram post
2. Copy the caption text
3. Paste into Plendy's URL field
4. AI will extract location from the text

## Need Help?

- Facebook Developer Docs: https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/oembed
- Check logs for detailed error messages
- Look for `📸 INSTAGRAM` and `❌ INSTAGRAM` tags in console
