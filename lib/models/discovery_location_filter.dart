/// How discovery orders the client-side public experience pool.
enum DiscoverySortMode {
  random,
  nearest,
}

/// How selected geographic areas constrain the pool.
enum DiscoveryAreaMatchMode {
  /// Experience must fall inside viewport (or fallback circle around area center).
  strictBounds,

  /// Experience within [radiusMiles] of at least one selected area center.
  withinRadius,
}

/// Axis-aligned bounds from Places API `viewport` (low = southwest, high = northeast).
class DiscoveryMapBounds {
  const DiscoveryMapBounds({
    required this.southLat,
    required this.westLng,
    required this.northLat,
    required this.eastLng,
  });

  final double southLat;
  final double westLng;
  final double northLat;
  final double eastLng;

  factory DiscoveryMapBounds.fromJson(Map<String, dynamic> json) {
    return DiscoveryMapBounds(
      southLat: (json['southLat'] as num).toDouble(),
      westLng: (json['westLng'] as num).toDouble(),
      northLat: (json['northLat'] as num).toDouble(),
      eastLng: (json['eastLng'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'southLat': southLat,
      'westLng': westLng,
      'northLat': northLat,
      'eastLng': eastLng,
    };
  }

  bool contains(double lat, double lng) {
    if (lat < southLat || lat > northLat) return false;
    if (westLng <= eastLng) {
      return lng >= westLng && lng <= eastLng;
    }
    return lng >= westLng || lng <= eastLng;
  }
}

/// A city/region (or similar) the user chose for discovery filtering.
class DiscoveryAreaFilter {
  const DiscoveryAreaFilter({
    required this.placeId,
    required this.label,
    required this.latitude,
    required this.longitude,
    this.viewport,
    this.types = const <String>[],
  });

  final String placeId;
  final String label;
  final double latitude;
  final double longitude;
  final DiscoveryMapBounds? viewport;
  final List<String> types;

  factory DiscoveryAreaFilter.fromJson(Map<String, dynamic> json) {
    return DiscoveryAreaFilter(
      placeId: json['placeId'] as String,
      label: json['label'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      viewport: json['viewport'] is Map<String, dynamic>
          ? DiscoveryMapBounds.fromJson(
              json['viewport'] as Map<String, dynamic>,
            )
          : null,
      types: (json['types'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'placeId': placeId,
      'label': label,
      'latitude': latitude,
      'longitude': longitude,
      'viewport': viewport?.toJson(),
      'types': types,
    };
  }

  DiscoveryAreaFilter copyWith({
    String? placeId,
    String? label,
    double? latitude,
    double? longitude,
    DiscoveryMapBounds? viewport,
    List<String>? types,
  }) {
    return DiscoveryAreaFilter(
      placeId: placeId ?? this.placeId,
      label: label ?? this.label,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      viewport: viewport ?? this.viewport,
      types: types ?? this.types,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DiscoveryAreaFilter && other.placeId == placeId;
  }

  @override
  int get hashCode => placeId.hashCode;
}

/// Default search radius (km) around area center when viewport is missing.
double discoveryFallbackRadiusKmForTypes(List<String> types) {
  if (types.any((t) => t == 'country' || t.contains('country'))) {
    return 400;
  }
  if (types.any((t) =>
      t == 'administrative_area_level_1' ||
      t.contains('administrative_area'))) {
    return 120;
  }
  if (types.any((t) =>
      t == 'locality' || t == 'postal_town' || t.contains('sublocality'))) {
    return 18;
  }
  return 35;
}

bool discoveryHasPlausibleCoordinates(double lat, double lng) {
  if (lat.abs() < 1e-5 && lng.abs() < 1e-5) return false;
  return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
}

double milesToKm(double miles) => miles * 1.609344;
