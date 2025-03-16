# Plendy

A new Flutter project for sharing and exploring experiences.

## Setup Instructions

### API Keys Setup

1. Copy the template file for API keys:
   ```
   cp lib/config/api_keys.template.dart lib/config/api_keys.dart
   ```

2. Edit the `lib/config/api_keys.dart` file with your actual API keys:
   - Visit [Google Cloud Console](https://console.cloud.google.com/) to set up your API keys
   - Enable the following APIs in your Google Cloud project:
     - Places API
     - Maps SDK for Android and/or iOS
   - Configure the API key restrictions appropriately for your platform

### If your API keys were previously committed to Git

If you've already committed the API keys file, run the following command to stop tracking it:
```
git update-index --assume-unchanged lib/config/api_keys.dart
```

## Running the App

```
flutter pub get
flutter run
```
