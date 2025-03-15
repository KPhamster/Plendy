# Google Maps Components in Plendy

This document provides an overview of the consolidated Google Maps implementation in the Plendy app.

## Map Service

The app now uses a single, centralized map service:

- `lib/services/map_service.dart` - This is the main service for all map-related functionality.

The old service (`lib/services/maps/maps_service.dart`) has been deprecated and renamed to `.bak`.

## Map Components

### Map Widgets

The app has several map-related widgets:

1. **PlendyMapWidget** (`lib/widgets/map_widget.dart`)
   - A fully-featured interactive map widget
   - Includes search, location selection, and user location features
   - Used in various screens throughout the app

2. **StaticMap** (`lib/widgets/maps/static_map.dart`)
   - A lightweight widget that displays a static map image
   - Ideal for previews and cards where an interactive map isn't needed

3. **MapView** (`lib/widgets/maps/map_view.dart`)
   - A reusable Google Maps widget that can display one or more locations
   - Simpler than PlendyMapWidget but still interactive

### Map Screens

1. **LocationPickerScreen** (`lib/screens/location_picker_screen.dart`)
   - A full-screen location picker with search functionality
   - Uses PlendyMapWidget internally

2. **ExperienceMapScreen** (`lib/screens/experience_map_screen.dart`)
   - Shows a specific experience location on the map
   - Provides directions and information about the location

## Deprecated Components

The following components have been deprecated:

- `lib/services/maps/maps_service.dart` → Use `MapService` instead
- `lib/widgets/maps/location_picker.dart` → Use `LocationPickerScreen` instead

## API Key Management

API keys are managed through `lib/config/api_keys.dart` which provides platform-specific keys.

## Usage Examples

### Using the Map Service

```dart
import '../services/map_service.dart';

final _mapService = MapService();

// Get current location
final position = await _mapService.getCurrentLocation();

// Search for places
final results = await _mapService.searchPlaces("coffee shop");

// Get place details
final location = await _mapService.getPlaceDetails(placeId);

// Get a static map image URL
final mapImageUrl = _mapService.getStaticMapImageUrl(
  latitude, 
  longitude,
  zoom: 15,
  width: 600,
  height: 300
);
```

### Using the Location Picker Screen

```dart
Future<void> _pickLocation() async {
  final Location? result = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => LocationPickerScreen(
        initialLocation: _currentLocation,
        onLocationSelected: (location) => location,
      ),
    ),
  );
  
  if (result != null) {
    // Do something with the selected location
    setState(() {
      _selectedLocation = result;
    });
  }
}
```

### Using the Map Widget

```dart
PlendyMapWidget(
  initialLocation: experienceLocation,
  showUserLocation: true,
  allowSelection: true,
  onLocationSelected: (location) {
    // Handle location selection
    print('Selected location: ${location.address}');
  },
)
```

### Using the Static Map

```dart
StaticMap(
  location: experience.location,
  height: 180,
  width: double.infinity,
  zoom: 15,
  onTap: () {
    // Navigate to full map view
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExperienceMapScreen(
          experience: experience,
        ),
      ),
    );
  },
)
```
