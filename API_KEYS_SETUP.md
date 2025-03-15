# API Keys Setup Guide for Plendy

This guide explains how to securely set up API keys for the Plendy app to avoid exposing them on GitHub.

## Setup Steps

### 1. Create .env file

Copy `.env.example` to `.env` and add your API keys:

```
GOOGLE_MAPS_API_KEY_ANDROID=your_android_api_key_here
GOOGLE_MAPS_API_KEY_IOS=your_ios_api_key_here
GOOGLE_MAPS_API_KEY_WEB=your_web_api_key_here
```

### 2. Android Setup

1. Add the API key to `android/local.properties`:

```
maps.api.key=your_android_api_key_here
```

2. The API key in `AndroidManifest.xml` is already set up with:

```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="${MAPS_API_KEY}" />
```

The app will load this from local.properties at build time.

### 3. iOS Setup

1. Add your API key to `ios/Config.xcconfig`:

```
MAPS_API_KEY=your_ios_api_key_here
```

2. In Xcode:
   - Open the Runner project
   - Go to Project Navigator > Runner > Info
   - Set "Config" to point to your Config.xcconfig file

3. The API key in Info.plist is already set up to use `$(MAPS_API_KEY)`.
4. The AppDelegate.swift is already configured to load from Info.plist.

### 4. Web Setup

For web deployment:

1. Run the appropriate build script:

```bash
# On Unix/Mac/Linux:
./scripts/build_web.sh

# On Windows:
.\scripts\build_web.bat
```

These scripts will:
- Read the API key from your .env file
- Replace the placeholder in index.html
- Build the web app

## Running the App

After setting up your API keys, you can run the app:

```bash
flutter run
```

## Security Best Practices

1. **Never commit sensitive API keys to Git!**
   - All API key files (.env, Config.xcconfig) are in .gitignore

2. **Restrict your API keys in the Google Cloud Console:**
   - For Android: Restrict by app package name
   - For iOS: Restrict by bundle ID
   - For Web: Restrict by HTTP referrer

3. **Use different API keys for different platforms:**
   - This limits the damage if any one key is compromised
   - Allows for platform-specific restrictions

4. **For CI/CD integration:**
   - Store API keys as secrets in your CI/CD platform
   - Inject them during build time

## Troubleshooting

If maps aren't working:

1. Verify API keys are correctly set up in all platform-specific places
2. Ensure you've enabled the necessary APIs in Google Cloud Console:
   - Maps SDK for Android
   - Maps SDK for iOS
   - Maps JavaScript API
   - Places API

3. For Android emulators, ensure Google Play services are installed
4. For iOS simulators, location services might need to be manually enabled
