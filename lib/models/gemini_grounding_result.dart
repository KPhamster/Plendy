import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Represents a single location from Google Maps grounding
class GoogleMapsLocation {
  /// Google Place ID
  final String placeId;
  
  /// Name of the place
  final String name;
  
  /// Geographic coordinates
  final LatLng coordinates;
  
  /// Full formatted address
  final String? formattedAddress;
  
  /// Place types from Google
  final List<String> types;
  
  /// Google Maps URI for the place
  final String? uri;

  const GoogleMapsLocation({
    required this.placeId,
    required this.name,
    required this.coordinates,
    this.formattedAddress,
    this.types = const [],
    this.uri,
  });

  /// Create from JSON map (from Gemini API response)
  factory GoogleMapsLocation.fromJson(Map<String, dynamic> json) {
    // Handle different response formats from Gemini grounding
    final coords = json['coordinates'] ?? json['location'] ?? {};
    final lat = (coords['latitude'] as num?)?.toDouble() ?? 0.0;
    final lng = (coords['longitude'] as num?)?.toDouble() ?? 0.0;

    return GoogleMapsLocation(
      placeId: json['placeId'] as String? ?? json['place_id'] as String? ?? '',
      name: json['name'] as String? ?? json['title'] as String? ?? 'Unknown',
      coordinates: LatLng(lat, lng),
      formattedAddress: json['formattedAddress'] as String? ?? 
                        json['formatted_address'] as String? ??
                        json['address'] as String?,
      types: (json['types'] as List?)?.cast<String>() ?? [],
      uri: json['uri'] as String? ?? json['url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'placeId': placeId,
      'name': name,
      'coordinates': {
        'latitude': coordinates.latitude,
        'longitude': coordinates.longitude,
      },
      'formattedAddress': formattedAddress,
      'types': types,
      'uri': uri,
    };
  }

  @override
  String toString() {
    return 'GoogleMapsLocation(name: $name, placeId: $placeId, address: $formattedAddress)';
  }
}

/// Result from Gemini API with Google Maps grounding
class GeminiGroundingResult {
  /// The text response from Gemini
  final String responseText;
  
  /// List of Google Maps locations extracted
  final List<GoogleMapsLocation> locations;
  
  /// Context token for rendering Google Maps widget (if available)
  final String? widgetContextToken;
  
  /// Raw response data for debugging
  final Map<String, dynamic> rawResponse;

  const GeminiGroundingResult({
    required this.responseText,
    required this.locations,
    this.widgetContextToken,
    this.rawResponse = const {},
  });

  /// Whether any locations were found
  bool get hasLocations => locations.isNotEmpty;

  /// Number of locations found
  int get locationCount => locations.length;

  /// Get the first location (or null if none)
  GoogleMapsLocation? get firstLocation => 
      locations.isNotEmpty ? locations.first : null;

  /// Create from Gemini API response
  factory GeminiGroundingResult.fromApiResponse(Map<String, dynamic> response) {
    final candidates = response['candidates'] as List? ?? [];
    if (candidates.isEmpty) {
      return GeminiGroundingResult(
        responseText: '',
        locations: [],
        rawResponse: response,
      );
    }

    final candidate = candidates.first as Map<String, dynamic>;
    final content = candidate['content'] as Map<String, dynamic>? ?? {};
    final parts = content['parts'] as List? ?? [];
    
    // Extract text response
    String text = '';
    for (final part in parts) {
      if (part is Map<String, dynamic> && part['text'] != null) {
        text += part['text'] as String;
      }
    }

    // Extract grounding metadata
    final groundingMetadata = candidate['groundingMetadata'] as Map<String, dynamic>?;
    final locations = <GoogleMapsLocation>[];
    String? widgetToken;

    if (groundingMetadata != null) {
      // Extract Google Maps locations from grounding chunks
      final groundingChunks = groundingMetadata['groundingChunks'] as List? ?? [];
      
      for (final chunk in groundingChunks) {
        if (chunk is Map<String, dynamic>) {
          final maps = chunk['maps'] as Map<String, dynamic>?;
          if (maps != null) {
            locations.add(GoogleMapsLocation.fromJson(maps));
          }
        }
      }

      // Extract widget context token
      widgetToken = groundingMetadata['googleMapsWidgetContextToken'] as String?;
    }

    return GeminiGroundingResult(
      responseText: text,
      locations: locations,
      widgetContextToken: widgetToken,
      rawResponse: response,
    );
  }

  @override
  String toString() {
    return 'GeminiGroundingResult(text: ${responseText.substring(0, responseText.length > 50 ? 50 : responseText.length)}..., locations: $locationCount)';
  }
}
