# Google Maps Integration for Plendy

This guide describes how to integrate Google Maps into the Plendy app using the `google_maps_flutter` package version 2.10.1.

## File Structure

The Google Maps integration consists of the following key components:

1. `lib/services/google_maps_service.dart` - Main service class for Google Maps functionality
2. `lib/widgets/google_maps_widget.dart` - Reusable widget for displaying and interacting with Google Maps
3. `lib/screens/new_location_picker_screen.dart` - Screen for selecting locations
4. `lib/screens/new_experience_map_screen.dart` - Screen for viewing experiences on a map
5. `lib/screens/google_maps_example_screen.dart` - Example usage of the Google Maps implementation

## Setup Instructions

### 1. API Keys

Make sure you have valid Google Maps API keys for all platforms:

**Android:**
- In `android/app/src/main/AndroidManifest.xml`, the API key is already configured:
  ```xml
  <meta-data
      android:name="com.google.android.geo.API_KEY"
      android:value="${MAPS_API_KEY}" />
  ```
- Set up the Secrets Gradle Plugin to securely store your API key
- Create a `secrets.properties` file in your Android project root with:
  ```
  MAPS_API_KEY=YOUR_ACTUAL_API_KEY
  ```

**iOS:**
- In `ios/Runner/Info.plist`, the API key is already configured:
  ```xml
  <key>GoogleMapsApiKey</key>
  <string>$(MAPS_API_KEY)</string>
  ```
- In `ios/Runner/AppDelegate.swift`, the API key is loaded and initialized

**Web:**
- In `web/index.html`, update the Google Maps API script with your API key:
  ```html
  <script src="https://maps.googleapis.com/maps/api/js?key=YOUR_API_KEY&libraries=places"></script>
  ```

### 2. Usage in Your App

To use the new Google Maps implementation in your app, replace the old map widgets with the new ones:

#### Basic Map Display:

```dart
GoogleMapsWidget(
  initialLocation: location,  // A Location object from models/experience.dart
  showUserLocation: true,
  allowSelection: true,       // Allow tapping to select locations
  onLocationSelected: (location) {
    // Handle selected location
  },
)
```

#### Location Picker:

Replace the old `LocationPickerScreen` with `new_location_picker_screen.dart`:

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => LocationPickerScreen(
      initialLocation: initialLocation,  // Optional
      onLocationSelected: (location) {
        // Handle the selected location
      },
    ),
  ),
);
```

#### Experience Map Screen:

Replace the old `ExperienceMapScreen` with `new_experience_map_screen.dart`:

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => ExperienceMapScreen(
      experience: experience,
    ),
  ),
);
```

### 3. Key Features

The new Google Maps implementation includes:

1. **Established Place Detection** - When tapping on the map, the system will try to identify if an established place (business, POI, etc.) exists at that location
2. **Reverse Geocoding** - Automatically fetches address information for selected coordinates
3. **User Location Tracking** - Shows the user's current location on the map
4. **Camera Controls** - Allows zooming, panning, and animating to specific locations
5. **Custom Markers** - Different marker colors for established places vs. new locations

### 4. POI Detection

The POI (Point of Interest) detection works by:

1. When a user taps on the map, we send those coordinates to the Google Maps Geocoding API
2. The API returns information about any established places at or near those coordinates
3. We check the returned data for place types like 'establishment', 'point_of_interest', 'restaurant', etc.
4. If an established place is found, we use its details (name, address) instead of treating it as a new location

This approach solves the issue where tapping on an existing POI would create a new, undefined location instead of selecting the POI.

## Troubleshooting

If you encounter any issues:

1. **Permissions** - Make sure location permissions are properly requested and granted
2. **API Keys** - Verify your API keys are valid and have the appropriate restrictions
3. **Platform Configuration** - Check platform-specific setup in AndroidManifest.xml and Info.plist
4. **API Quota** - Monitor your Google Maps API usage to avoid hitting quota limits
5. **Log Messages** - Check the debug logs for detailed error messages

## References

- [Google Maps Flutter Package](https://pub.dev/packages/google_maps_flutter)
- [Google Maps Platform Documentation](https://developers.google.com/maps/documentation)
- [Flutter Geocoding Package](https://pub.dev/packages/geocoding)
- [Flutter Geolocator Package](https://pub.dev/packages/geolocator)