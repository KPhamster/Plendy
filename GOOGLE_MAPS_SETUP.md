# Google Maps Integration Setup for Plendy

This guide will help you properly configure Google Maps in your Flutter app for both Android and iOS platforms.

## Prerequisites

1. A Google Maps API key from the [Google Cloud Console](https://console.cloud.google.com/)
2. Enabled Google Maps SDK for Android and iOS platforms
3. Enabled Places API for location search functionality

## Android Setup

1. Copy the contents from `android/app/src/main/AndroidManifest.xml.example` to your actual `AndroidManifest.xml` file.

2. Replace the placeholder API key with your actual Google Maps API key:
   ```xml
   <meta-data
       android:name="com.google.android.geo.API_KEY"
       android:value="YOUR_ACTUAL_API_KEY"/>
   ```

3. Make sure you have these permissions in your AndroidManifest.xml:
   ```xml
   <uses-permission android:name="android.permission.INTERNET"/>
   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
   <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
   ```

## iOS Setup

1. Copy the contents from `ios/Runner/Info.plist.example` to your actual `Info.plist` file.

2. Replace the placeholder API key with your actual Google Maps API key:
   ```xml
   <key>GMSApiKey</key>
   <string>YOUR_ACTUAL_API_KEY</string>
   ```

3. Make sure you have these permissions in your Info.plist:
   ```xml
   <key>NSLocationWhenInUseUsageDescription</key>
   <string>This app needs access to location when open to show you nearby experiences.</string>
   <key>NSLocationAlwaysUsageDescription</key>
   <string>This app needs access to location when in the background.</string>
   ```

4. Add this to enable Metal rendering (helps performance on iOS):
   ```xml
   <key>io.flutter.embedded_views_preview</key>
   <true/>
   ```

## Secure Your API Keys

For production, please secure your API keys:

1. For Android, use gradle properties to store your API key
2. For iOS, use build configurations to store your API key
3. Consider implementing API key restrictions in the Google Cloud Console

## Using Maps in the App

This app now has three main map components you can use:

1. **PlendyMapWidget** (in `lib/widgets/map_widget.dart`): A reusable widget that can be embedded in any screen to display a map with location selection.

2. **LocationPickerScreen** (in `lib/screens/location_picker_screen.dart`): A full-screen location picker with search functionality.

3. **ExperienceMapScreen** (in `lib/screens/experience_map_screen.dart`): Shows a specific experience on the map with directions functionality.

4. **MapService** (in `lib/services/map_service.dart`): A service class that handles all map-related functionality such as getting the current location, searching for places, etc.

## Example Usage

To add a map to a new screen:

```dart
import '../widgets/map_widget.dart';
import '../models/experience.dart';

class MyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Map Example')),
      body: Container(
        height: 300,
        child: PlendyMapWidget(
          showUserLocation: true,
          allowSelection: true,
          onLocationSelected: (Location location) {
            print('Selected location: ${location.latitude}, ${location.longitude}');
          },
        ),
      ),
    );
  }
}
```

To open the full-screen location picker:

```dart
Future<void> _pickLocation() async {
  final Location? result = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => LocationPickerScreen(
        onLocationSelected: (location) => location,
      ),
    ),
  );
  
  if (result != null) {
    // Do something with the selected location
    print('Selected location: ${result.address}');
  }
}
```

To show an experience on the map:

```dart
void _showOnMap(Experience experience) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => ExperienceMapScreen(
        experience: experience,
      ),
    ),
  );
}
```
