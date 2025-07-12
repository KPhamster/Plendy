# iOS Setup Guide for Plendy

This guide covers the iOS-specific setup required after cloning the Plendy repository.

## ⚠️ CRITICAL: Firebase Configuration

### 1. Add GoogleService-Info.plist to Xcode Project
Even if the `GoogleService-Info.plist` file exists in `ios/Runner/`, it MUST be added to the Xcode project:

1. Open your project in Xcode:
   ```bash
   open ios/Runner.xcworkspace
   ```

2. In Xcode:
   - Right-click on the "Runner" folder in the left sidebar
   - Select "Add Files to 'Runner'..."
   - Navigate to and select `GoogleService-Info.plist`
   - ✅ Make sure "Copy items if needed" is checked
   - ✅ Make sure "Runner" target is selected
   - Click "Add"

### 2. Enable Push Notifications Capability
1. In Xcode, select your project in the navigator
2. Select the "Runner" target
3. Go to the "Signing & Capabilities" tab
4. Click "+ Capability"
5. Add "Push Notifications"

### 3. Verify Bundle ID
- Ensure your bundle ID is set to `com.plendy.app` in Xcode
- This should match the bundle ID in:
  - `GoogleService-Info.plist`
  - `lib/firebase_options.dart`
  - Firebase Console

This guide will help you configure all the necessary API keys and settings for the iOS version of Plendy.

## Issues Fixed

✅ **Flutter Local Notifications**: iOS settings have been properly configured in `main.dart`
✅ **Config.xcconfig**: Created template file for API keys
✅ **GoogleService-Info.plist**: Created template file for Firebase configuration
✅ **FacebookClientToken**: Added placeholder to Info.plist

## Required Configuration Steps

### 1. Google Maps API Key

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create or select your project
3. Enable the Maps SDK for iOS
4. Create an API key and restrict it to iOS apps
5. Open `ios/Config.xcconfig` and replace `YOUR_GOOGLE_MAPS_API_KEY_HERE` with your actual API key

### 2. Firebase Configuration

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project `plendy-7df50`
3. Go to Project Settings → General → Your apps
4. Click on the iOS app or add a new iOS app
5. **Important**: Make sure the Bundle ID matches your app's Bundle ID (currently `com.example.plendy`)
6. Download the `GoogleService-Info.plist` file
7. Replace the existing `ios/Runner/GoogleService-Info.plist` with the downloaded file

### 3. Facebook SDK Configuration

1. Go to [Facebook Developers](https://developers.facebook.com/)
2. Select your app
3. Go to Settings → Advanced
4. Copy the Client Token
5. Open `ios/Runner/Info.plist` and replace `YOUR_FACEBOOK_CLIENT_TOKEN_HERE` with your actual client token

### 4. Bundle ID Configuration

The current Bundle ID is `com.example.plendy`. You have two options:

**Option A: Keep current Bundle ID**
1. Update your Firebase project to use `com.example.plendy` as the Bundle ID
2. Re-download the `GoogleService-Info.plist` file

**Option B: Change Bundle ID**
1. Open `ios/Runner.xcodeproj` in Xcode
2. Select the Runner target
3. Go to General → Identity
4. Change the Bundle Identifier to match your Firebase project
5. Update the `GoogleService-Info.plist` file accordingly

### 5. Push Notifications Setup (Optional)

If you want push notifications to work properly:

1. In Xcode, select your project
2. Go to Signing & Capabilities
3. Add the "Push Notifications" capability
4. Add the "Background Modes" capability
5. Enable "Remote notifications" in Background Modes

### 6. Build and Test

After completing the above steps:

1. Clean your project: `flutter clean`
2. Get dependencies: `flutter pub get`
3. Run on iOS: `flutter run`

## File Structure

```
ios/
├── Config.xcconfig              # Google Maps API key (not in git)
├── Runner/
│   ├── GoogleService-Info.plist # Firebase config (not in git)
│   └── Info.plist               # App configuration
└── .gitignore                   # Updated to ignore sensitive files
```

## Security Notes

- `Config.xcconfig` and `GoogleService-Info.plist` are now in `.gitignore` to prevent committing sensitive API keys
- Never commit actual API keys to version control
- The template files contain placeholders that need to be replaced with your actual keys

## Troubleshooting

**"provideAPIKey: requires non-empty API key"**
- Replace the placeholder in `Config.xcconfig` with your actual Google Maps API key

**"Could not locate configuration file: 'GoogleService-Info.plist'"**
- Download the correct file from Firebase Console and replace the template

**"FBSDKLog: Starting with v13 of the SDK, a client token must be embedded"**
- Replace the placeholder in `Info.plist` with your actual Facebook client token

**"The project's Bundle ID is inconsistent"**
- Make sure the Bundle ID in Xcode matches the one in your Firebase project 