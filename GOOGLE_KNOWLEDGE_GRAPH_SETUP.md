# Google Knowledge Graph API Integration

This guide explains how to set up and use the Google Knowledge Graph API integration in Plendy for enhanced sharing from Google search results.

## Overview

When sharing from Google search results, the app now uses the Google Knowledge Graph API to:
- Identify if the shared entity is a place
- Extract detailed descriptions and metadata
- Get official website URLs
- Retrieve entity images

## Setup Instructions

### 1. Get a Google Knowledge Graph API Key

1. Go to the [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Enable the **Knowledge Graph Search API**:
   - Go to "APIs & Services" > "Library"
   - Search for "Knowledge Graph Search API"
   - Click on it and press "Enable"
4. Create credentials:
   - Go to "APIs & Services" > "Credentials"
   - Click "Create Credentials" > "API Key"
   - Copy the generated API key

### 2. Add the API Key to Your Project

1. Copy `lib/config/api_secrets.template.dart` to `lib/config/api_secrets.dart`
2. Open `lib/config/api_secrets.dart` and add your API key:

```dart
class ApiSecrets {
  // Google Maps API Key
  static const String googleMapsApiKey = 'YOUR_GOOGLE_MAPS_API_KEY';
  
  // Google Knowledge Graph API Key
  static const String googleKnowledgeGraphApiKey = 'YOUR_ACTUAL_KG_API_KEY_HERE';
  
  // Add other API keys and secrets here
}
```

3. Make sure `lib/config/api_secrets.dart` is in your `.gitignore` (it should already be there)

## How It Works

When you share from Google (e.g., searching for "Hildene, The Lincoln Family Home"):

1. The app detects the `g.co/kgs/` URL pattern
2. Extracts the entity name from the shared text
3. Queries the Knowledge Graph API to get entity information
4. If the entity is a place:
   - Searches Google Places API for location details
   - Fills the experience form with combined data
   - Adds Knowledge Graph description to notes (if available)
   - Uses Knowledge Graph website URL if Maps doesn't have one

## Example Share Flow

1. Search for a place on Google (e.g., "Statue of Liberty")
2. Share the result to Plendy
3. The app will:
   - Recognize it's a Google Knowledge Graph share
   - Fetch entity data from Knowledge Graph API
   - Find the location on Google Maps
   - Pre-fill the experience form with all available data

## API Quotas and Limits

- The Knowledge Graph Search API has usage quotas
- Default quota is typically 100,000 requests per day
- Monitor your usage in the Google Cloud Console

## Troubleshooting

### API Key Not Working
- Ensure the Knowledge Graph Search API is enabled in your Google Cloud project
- Check that the API key has no restrictions or includes your app's package name/bundle ID

### No Results Found
- The Knowledge Graph API may not recognize all entities as places
- Some entities might not have location data
- The app will fall back to searching by name in Google Places

### Console Messages
Look for these debug messages in the console:
- `🔍 KNOWLEDGE GRAPH: Searching for "entity name"`
- `🔍 KNOWLEDGE GRAPH: Found place entity`
- `🔍 KNOWLEDGE GRAPH: No place entities found`

## Benefits

- **Richer Data**: Get Wikipedia descriptions and official websites
- **Better Accuracy**: Knowledge Graph helps identify the correct entity
- **Seamless Experience**: Works just like sharing from Google Maps
- **Automatic Notes**: Descriptions are added to the notes field

## Fallback Behavior

If the Knowledge Graph API is not configured or fails:
1. The app attempts to resolve the shortened URL
2. If it resolves to Google Maps, processes as a Maps share
3. Otherwise, searches Google Places by the entity name
4. If all else fails, treats it as a generic URL share 