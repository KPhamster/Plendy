import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Enum representing the source of location extraction
enum ExtractionSource {
  /// Location extracted via Gemini AI with Google Maps grounding
  geminiGrounding,
  
  /// Location parsed directly from URL structure (Yelp, Google Maps links)
  urlParsing,
  
  /// Location found via Google Places API search (fallback)
  placesSearch,
  
  /// Location from Google Knowledge Graph
  knowledgeGraph,
}

/// Enum representing the type of place
enum PlaceType {
  restaurant,
  cafe,
  bar,
  attraction,
  landmark,
  museum,
  hotel,
  lodging,
  store,
  shopping,
  park,
  event,
  entertainment,
  unknown,
}

/// Data class representing extracted location information from a shared URL
class ExtractedLocationData {
  /// Google Place ID for precise location identification
  final String? placeId;
  
  /// Name of the business or place
  final String name;
  
  /// Full formatted address
  final String? address;
  
  /// Geographic coordinates
  final LatLng? coordinates;
  
  /// Type of place (restaurant, attraction, etc.)
  final PlaceType type;
  
  /// How the location was extracted
  final ExtractionSource source;
  
  /// Confidence score from 0.0 to 1.0
  final double confidence;
  
  /// Additional metadata from extraction
  final Map<String, dynamic>? metadata;
  
  /// Google Maps URI for the place
  final String? googleMapsUri;
  
  /// Original URL types from Google Places
  final List<String>? placeTypes;
  
  /// Website URL for the place
  final String? website;

  const ExtractedLocationData({
    this.placeId,
    required this.name,
    this.address,
    this.coordinates,
    required this.type,
    required this.source,
    required this.confidence,
    this.metadata,
    this.googleMapsUri,
    this.placeTypes,
    this.website,
  });

  /// Create from a map (for JSON deserialization)
  factory ExtractedLocationData.fromMap(Map<String, dynamic> map) {
    return ExtractedLocationData(
      placeId: map['placeId'] as String?,
      name: map['name'] as String? ?? 'Unknown',
      address: map['address'] as String?,
      coordinates: map['latitude'] != null && map['longitude'] != null
          ? LatLng(
              (map['latitude'] as num).toDouble(),
              (map['longitude'] as num).toDouble(),
            )
          : null,
      type: _placeTypeFromString(map['type'] as String?),
      source: _sourceFromString(map['source'] as String?),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.5,
      metadata: map['metadata'] as Map<String, dynamic>?,
      googleMapsUri: map['googleMapsUri'] as String?,
      placeTypes: (map['placeTypes'] as List?)?.cast<String>(),
      website: map['website'] as String?,
    );
  }

  /// Convert to map (for JSON serialization)
  Map<String, dynamic> toMap() {
    return {
      'placeId': placeId,
      'name': name,
      'address': address,
      'latitude': coordinates?.latitude,
      'longitude': coordinates?.longitude,
      'type': type.name,
      'source': source.name,
      'confidence': confidence,
      'metadata': metadata,
      'googleMapsUri': googleMapsUri,
      'placeTypes': placeTypes,
      'website': website,
    };
  }

  /// Create a copy with updated fields
  ExtractedLocationData copyWith({
    String? placeId,
    String? name,
    String? address,
    LatLng? coordinates,
    PlaceType? type,
    ExtractionSource? source,
    double? confidence,
    Map<String, dynamic>? metadata,
    String? googleMapsUri,
    List<String>? placeTypes,
    String? website,
  }) {
    return ExtractedLocationData(
      placeId: placeId ?? this.placeId,
      name: name ?? this.name,
      address: address ?? this.address,
      coordinates: coordinates ?? this.coordinates,
      type: type ?? this.type,
      source: source ?? this.source,
      confidence: confidence ?? this.confidence,
      metadata: metadata ?? this.metadata,
      googleMapsUri: googleMapsUri ?? this.googleMapsUri,
      placeTypes: placeTypes ?? this.placeTypes,
      website: website ?? this.website,
    );
  }

  /// Infer PlaceType from Google Places types
  static PlaceType inferPlaceType(List<String>? types) {
    if (types == null || types.isEmpty) return PlaceType.unknown;

    final typeSet = types.map((t) => t.toLowerCase()).toSet();

    if (typeSet.any((t) => t.contains('restaurant'))) {
      return PlaceType.restaurant;
    }
    if (typeSet.any((t) => t.contains('cafe') || t.contains('coffee'))) {
      return PlaceType.cafe;
    }
    if (typeSet.any((t) => t.contains('bar') || t.contains('night_club'))) {
      return PlaceType.bar;
    }
    if (typeSet.any((t) => t.contains('museum'))) {
      return PlaceType.museum;
    }
    if (typeSet.any((t) => t.contains('park'))) {
      return PlaceType.park;
    }
    if (typeSet.any((t) => t.contains('hotel') || t.contains('lodging'))) {
      return PlaceType.hotel;
    }
    if (typeSet.any((t) => t.contains('store') || t.contains('shop'))) {
      return PlaceType.store;
    }
    if (typeSet.any((t) => 
        t.contains('tourist_attraction') || 
        t.contains('landmark') ||
        t.contains('point_of_interest'))) {
      return PlaceType.attraction;
    }

    return PlaceType.unknown;
  }

  static PlaceType _placeTypeFromString(String? value) {
    if (value == null) return PlaceType.unknown;
    return PlaceType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PlaceType.unknown,
    );
  }

  static ExtractionSource _sourceFromString(String? value) {
    if (value == null) return ExtractionSource.placesSearch;
    return ExtractionSource.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ExtractionSource.placesSearch,
    );
  }

  @override
  String toString() {
    return 'ExtractedLocationData(name: $name, placeId: $placeId, source: $source, confidence: $confidence)';
  }
}
