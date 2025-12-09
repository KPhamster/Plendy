import 'dart:convert';
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
  
  /// City name (extracted from address)
  final String? city;

  const GoogleMapsLocation({
    required this.placeId,
    required this.name,
    required this.coordinates,
    this.formattedAddress,
    this.types = const [],
    this.uri,
    this.city,
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
      city: json['city'] as String?,
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
      'city': city,
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

    // FALLBACK: If no grounding chunks, try to parse JSON from text response
    // This handles cases where Gemini returns locations in JSON format but
    // Google Maps grounding doesn't verify them (common for landmarks, viewpoints)
    if (locations.isEmpty && text.isNotEmpty) {
      final parsedLocations = _parseLocationsFromText(text);
      locations.addAll(parsedLocations);
      if (parsedLocations.isNotEmpty) {
        print('📍 GEMINI: Parsed ${parsedLocations.length} locations from text response (no grounding)');
      }
    }

    return GeminiGroundingResult(
      responseText: text,
      locations: locations,
      widgetContextToken: widgetToken,
      rawResponse: response,
    );
  }

  /// Parse locations from Gemini's JSON text response
  /// Used as fallback when Google Maps grounding returns no chunks
  static List<GoogleMapsLocation> _parseLocationsFromText(String text) {
    final locations = <GoogleMapsLocation>[];
    
    try {
      // Extract JSON array from text (might be wrapped in ```json ... ```)
      String jsonText = text.trim();
      
      // Remove markdown code block wrapper if present
      if (jsonText.startsWith('```')) {
        final startIndex = jsonText.indexOf('[');
        final endIndex = jsonText.lastIndexOf(']');
        if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
          jsonText = jsonText.substring(startIndex, endIndex + 1);
        }
      }
      
      // Try to find JSON array in text
      if (!jsonText.startsWith('[')) {
        final startIndex = jsonText.indexOf('[');
        final endIndex = jsonText.lastIndexOf(']');
        if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
          jsonText = jsonText.substring(startIndex, endIndex + 1);
        }
      }
      
      if (jsonText.startsWith('[') && jsonText.endsWith(']')) {
        final List<dynamic> jsonList = _parseJsonSafely(jsonText);
        
        for (final item in jsonList) {
          if (item is Map<String, dynamic>) {
            final name = item['name'] as String?;
            if (name != null && name.isNotEmpty) {
              // Create location with available data
              // Note: These won't have Place IDs since grounding failed
              locations.add(GoogleMapsLocation(
                placeId: '', // No Place ID from text parsing
                name: name,
                coordinates: const LatLng(0, 0), // Will need to geocode later
                formattedAddress: _buildAddress(item),
                types: [item['type'] as String? ?? 'point_of_interest'],
                uri: null,
                city: item['city'] as String?,
              ));
            }
          }
        }
      }
    } catch (e) {
      print('⚠️ GEMINI: Error parsing locations from text: $e');
    }
    
    return locations;
  }

  /// Safely parse JSON, handling common issues
  static List<dynamic> _parseJsonSafely(String jsonText) {
    try {
      // First try standard parsing
      return List<dynamic>.from(
        (const JsonDecoder().convert(jsonText)) as List,
      );
    } catch (e) {
      // Try to fix common JSON issues
      try {
        // Remove trailing commas before ] or }
        String fixed = jsonText.replaceAll(RegExp(r',\s*\]'), ']');
        fixed = fixed.replaceAll(RegExp(r',\s*\}'), '}');
        return List<dynamic>.from(
          (const JsonDecoder().convert(fixed)) as List,
        );
      } catch (e2) {
        print('⚠️ GEMINI: JSON parse failed even after fixes: $e2');
        return [];
      }
    }
  }

  /// Build address string from parsed JSON item
  static String? _buildAddress(Map<String, dynamic> item) {
    final parts = <String>[];
    
    if (item['address'] != null && item['address'].toString().isNotEmpty) {
      parts.add(item['address'].toString());
    }
    if (item['city'] != null && item['city'].toString().isNotEmpty) {
      parts.add(item['city'].toString());
    }
    if (item['region'] != null && item['region'].toString().isNotEmpty) {
      parts.add(item['region'].toString());
    }
    
    return parts.isNotEmpty ? parts.join(', ') : null;
  }

  /// Create from Cloud Function response (Vertex AI YouTube analysis)
  /// 
  /// The Cloud Function returns a simpler format:
  /// [{ name, address, city, region, country, type }]
  factory GeminiGroundingResult.fromCloudFunctionResponse(List<dynamic> locationsList) {
    final locations = <GoogleMapsLocation>[];

    for (final item in locationsList) {
      // Handle both Map<String, dynamic> and LinkedHashMap from Firebase
      if (item is Map) {
        final mapItem = Map<String, dynamic>.from(item);
        final name = mapItem['name'] as String?;
        
        if (name != null && name.isNotEmpty) {
          locations.add(GoogleMapsLocation(
            placeId: '', // Will be resolved later via Places API
            name: name,
            coordinates: const LatLng(0, 0), // Placeholder - will be resolved via Places API
            formattedAddress: _buildAddress(mapItem),
            types: [mapItem['type'] as String? ?? 'point_of_interest'],
            uri: null,
            city: mapItem['city'] as String?,
          ));
        }
      }
    }
    
    return GeminiGroundingResult(
      responseText: 'Cloud Function response',
      locations: locations,
      widgetContextToken: null,
      rawResponse: {'locations': locationsList},
    );
  }

  @override
  String toString() {
    return 'GeminiGroundingResult(text: ${responseText.substring(0, responseText.length > 50 ? 50 : responseText.length)}..., locations: $locationCount)';
  }
}
