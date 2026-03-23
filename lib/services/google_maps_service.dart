import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart';
import '../config/api_keys.dart';
import '../config/api_secrets.dart';
import '../models/discovery_location_filter.dart';
import '../models/experience.dart';
import 'certificate_pinning_service.dart';

/// Service class for Google Maps functionality
class GoogleMapsService {
  static final GoogleMapsService _instance = GoogleMapsService._internal();

  factory GoogleMapsService() {
    return _instance;
  }

  GoogleMapsService._internal();

  // Pinned to Google root CAs to prevent MITM attacks
  final Dio _dio = CertificatePinningService().createPinnedDio();
  final http.Client _httpClient = CertificatePinningService().createPinnedHttpClient();

  // Cache for Place Details results keyed by Place ID
  final Map<String, Location> _placeDetailsCache = {};

  // Platform channel for retrieving Android signing cert SHA-1 at runtime
  static const _signingChannel = MethodChannel('com.plendy.app/signing');
  static String? _cachedAndroidCertSha1;

  static Future<String?> _getAndroidCertSha1() async {
    if (_cachedAndroidCertSha1 != null) return _cachedAndroidCertSha1;
    try {
      final sha1 =
          await _signingChannel.invokeMethod<String>('getSigningCertSha1');
      _cachedAndroidCertSha1 = sha1;
      return sha1;
    } catch (e) {
      print('⚠️ Failed to get Android signing cert SHA-1: $e');
      return null;
    }
  }

  // Get the API key securely
  static String get apiKey => ApiSecrets.googleMapsApiKey;

  // Helper to build Places v1 media URL from a photo resource name.
  // NOTE: This URL requires platform-specific auth headers on Android/iOS.
  // Prefer resolvePhotoMediaUrl() which returns a direct URL usable without headers.
  static String? buildPlacePhotoUrlFromResourceName(String? resourceName,
      {int? maxWidthPx, int? maxHeightPx}) {
    if (resourceName == null || resourceName.isEmpty) return null;
    final key = apiKey;
    if (key.isEmpty) return null;
    final params = <String>[];
    if (maxWidthPx != null) params.add('maxWidthPx=$maxWidthPx');
    if (maxHeightPx != null) params.add('maxHeightPx=$maxHeightPx');
    final paramStr = params.isNotEmpty ? '&${params.join('&')}' : '';
    return 'https://places.googleapis.com/v1/$resourceName/media?key=$key$paramStr';
  }

  static final Map<String, String> _resolvedPhotoUrlCache = {};
  static final Set<String> _failedResourceNames = {};

  /// Returns a previously resolved direct photo URL from cache, or null.
  /// Use this in synchronous contexts (e.g. build methods) after having
  /// called [resolvePhotoMediaUrl] to populate the cache.
  static String? getCachedResolvedPhotoUrl(String? resourceName) {
    if (resourceName == null || resourceName.isEmpty) return null;
    return _resolvedPhotoUrlCache[resourceName];
  }

  /// Whether a resource name has already been tried and failed (stale/expired).
  static bool isResourceNameKnownBad(String? resourceName) {
    if (resourceName == null || resourceName.isEmpty) return false;
    return _failedResourceNames.contains(resourceName);
  }

  /// Resolves a photo resource name to a direct Google-hosted URL that can be
  /// loaded without authentication headers (e.g. via NetworkImage).
  /// Results are cached in-memory so subsequent calls return instantly.
  /// Stale/expired resource names are tracked so they aren't retried.
  Future<String?> resolvePhotoMediaUrl(String? resourceName,
      {int? maxWidthPx, int? maxHeightPx}) async {
    if (resourceName == null || resourceName.isEmpty) return null;

    final cached = _resolvedPhotoUrlCache[resourceName];
    if (cached != null) return cached;

    if (_failedResourceNames.contains(resourceName)) return null;

    final key = _getApiKey();
    if (key.isEmpty) return null;

    final params = <String>['skipHttpRedirect=true'];
    if (maxWidthPx != null) params.add('maxWidthPx=$maxWidthPx');
    if (maxHeightPx != null) params.add('maxHeightPx=$maxHeightPx');
    final url =
        'https://places.googleapis.com/v1/$resourceName/media?${params.join('&')}';

    try {
      final headers = <String, dynamic>{
        'X-Goog-Api-Key': key,
      };
      if (!kIsWeb && Platform.isAndroid) {
        headers['X-Android-Package'] = 'com.plendy.app';
        final sha1 = await _getAndroidCertSha1();
        if (sha1 != null) headers['X-Android-Cert'] = sha1;
      } else if (!kIsWeb && Platform.isIOS) {
        headers['X-Ios-Bundle-Identifier'] = ApiKeys.firebaseIosBundleId;
      }

      final response = await _dio.get(url, options: Options(headers: headers));
      if (response.statusCode == 200 && response.data is Map) {
        final photoUri = response.data['photoUri'] as String?;
        if (photoUri != null) {
          _resolvedPhotoUrlCache[resourceName] = photoUri;
        }
        return photoUri;
      }
    } catch (e) {
      _failedResourceNames.add(resourceName);
    }
    return null;
  }

  /// Fetches a fresh photo for a place and returns a direct resolved URL.
  /// Use this when the stored photoResourceName is stale/expired.
  Future<String?> fetchAndResolvePhotoForPlace(String placeId,
      {int maxWidthPx = 800, int maxHeightPx = 600}) async {
    try {
      final details = await fetchPlaceDetailsData(placeId);
      if (details == null) return null;
      if (details['photos'] is List &&
          (details['photos'] as List).isNotEmpty) {
        final first = (details['photos'] as List).first;
        if (first is Map<String, dynamic>) {
          final resourceName = first['name'] as String?;
          if (resourceName != null && resourceName.isNotEmpty) {
            return await resolvePhotoMediaUrl(resourceName,
                maxWidthPx: maxWidthPx, maxHeightPx: maxHeightPx);
          }
        }
      }
    } catch (e) {
      print('⚠️ fetchAndResolvePhotoForPlace: Failed for $placeId: $e');
    }
    return null;
  }

  /// Check and request location permissions
  Future<LocationPermission> checkAndRequestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }

    return permission;
  }

  /// Get current user location
  Future<Position> getCurrentLocation() async {
    await checkAndRequestLocationPermission();
    return await Geolocator.getCurrentPosition();
  }

  /// Convert Location model to LatLng for Google Maps
  LatLng locationToLatLng(Location location) {
    return LatLng(location.latitude, location.longitude);
  }

  /// Convert LatLng to Location model
  Location latLngToLocation(LatLng latLng, {String? address}) {
    return Location(
      latitude: latLng.latitude,
      longitude: latLng.longitude,
      address: address,
    );
  }

  /// Search for places using Google Places API
  Future<List<Map<String, dynamic>>> searchPlaces(
    String query, {
    double? latitude, // Optional latitude for location bias
    double? longitude, // Optional longitude for location bias
    double? radius, // Optional radius for location bias (meters)
  }) async {
    if (query.isEmpty) {
      return [];
    }

    print("\n🔎 PLACES SEARCH: Starting search for query: '$query'");
    // Log location bias if provided
    if (latitude != null && longitude != null) {
      print(
          "🔎 PLACES SEARCH: Using location bias: lat=$latitude, lng=$longitude, radius=${radius ?? 'default'}m");
    }
    print(
        "🔎 PLACES SEARCH: API key length: ${apiKey.length} chars, starts with: ${apiKey.substring(0, min(5, apiKey.length))}...");

    try {
      // We no longer need to fetch current position here, it's passed in
      // Position? position;
      // try {
      //   position = await getCurrentLocation();
      //   print("🔎 PLACES SEARCH: Got user location: ${position.latitude}, ${position.longitude}");
      // } catch (e) {
      //   print("🔎 PLACES SEARCH: Unable to get current position: $e");
      // }

      // First try the newer Places API for better results
      try {
        print("🔎 PLACES SEARCH: Trying method 1 - Places Autocomplete API V1 (Corrected Endpoint)");

        // Prepare request body for Autocomplete
        Map<String, dynamic> requestBody = {
          "input": query,
          // "inputType": "textQuery", // Not used by Autocomplete (New) API
        };

        // Add location bias if provided
        if (latitude != null && longitude != null) {
          requestBody["locationBias"] = {
            "circle": {
              "center": {"latitude": latitude, "longitude": longitude},
              "radius": radius ?? 50000.0 
            }
          };
        } else {
          // Default bias if no specific location given (e.g., Southern California)
          requestBody["locationBias"] = {
            "circle": {
              "center": {"latitude": 33.6846, "longitude": -117.8265},
              "radius": 50000.0
            }
          };
        }
        
        // Optionally, you can include the session token if you are managing sessions
        // requestBody["sessionToken"] = "YOUR_SESSION_TOKEN"; // Example

        print("🔎 PLACES SEARCH: Autocomplete Request body: ${jsonEncode(requestBody)}");

        // Call Google Places Autocomplete API (New)
        final autocompleteHeaders = await _placesApiHeaders(
          apiKey,
          'suggestions.placePrediction.placeId,suggestions.placePrediction.text,suggestions.placePrediction.structuredFormat,suggestions.placePrediction.types',
        );
        final response = await _dio.post(
          'https://places.googleapis.com/v1/places:autocomplete',
          data: requestBody,
          options: Options(headers: autocompleteHeaders),
        );

        if (response.statusCode == 200) {
          print("🔎 PLACES SEARCH (Autocomplete): API returned status code 200");
          final data = response.data;
          // print("🔎 PLACES SEARCH (Autocomplete): Response data: ${jsonEncode(data).substring(0, min(200, jsonEncode(data).length))}...");

          List<Map<String, dynamic>> results = [];

          if (data['suggestions'] != null) {
            final suggestions = data['suggestions'] as List;
            print("🔎 PLACES SEARCH (Autocomplete): Found ${suggestions.length} suggestions");

            for (var suggestion in suggestions) {
              final placePrediction = suggestion['placePrediction'];
              if (placePrediction != null) {
                String? placeId = placePrediction['placeId'];
                String? description = placePrediction['text']?['text']; // Main text of the suggestion
                String? mainText = placePrediction['structuredFormat']?['mainText']?['text'];
                String? secondaryText = placePrediction['structuredFormat']?['secondaryText']?['text'];
                List<String>? types = (placePrediction['types'] as List?)?.map((item) => item as String).toList();


                // For Autocomplete, the 'description' is often a good combined field.
                // 'address' might not be directly available here; usually, you get Place Details later using placeId.
                // We can construct a meaningful description from main and secondary text if needed.
                String displayDescription = description ?? (mainText != null ? (secondaryText != null ? "$mainText, $secondaryText" : mainText) : "Unknown suggestion");

                if (placeId != null && displayDescription.isNotEmpty) {
                  results.add({
                    'placeId': placeId,
                    'name': mainText, // The actual place name from structured format (e.g., "ruru kamakura")
                    'description': displayDescription, // This is the primary text from suggestion
                    'address': secondaryText, // Secondary text often contains address-like info
                    'types': types, 
                    // For Autocomplete, lat/lng are not directly in suggestions.
                    // They are fetched later with getPlaceDetails if the user selects this suggestion.
                    // We need to ensure our LocationPickerScreen's _selectSearchResult handles this.
                  });
                }
              }
            }
          }

          if (results.isNotEmpty) {
            print("🔎 PLACES SEARCH (Autocomplete): Found ${results.length} processed suggestions");
            // Log first few results for verification
            for (int i = 0; i < min(3, results.length); i++) {
              print("🔎 PLACES SEARCH (Autocomplete): Suggestion ${i + 1}: '${results[i]['description']}' (ID: ${results[i]['placeId']})");
            }
            return results; // Return suggestions
          } else {
            print("🔎 PLACES SEARCH (Autocomplete): No suggestions from Autocomplete API despite 200 status, or suggestions could not be processed.");
          }
        } else {
          print("🔎 PLACES SEARCH (Autocomplete): API returned non-200 status code: ${response.statusCode}, Data: ${response.data}");
        }
      } catch (e) {
        print("🔎 PLACES SEARCH: Error with Places API: $e");
        // Continue to fallback method
      }

      // Fallback to the v1 Text Search API if Autocomplete failed
      try {
        print("🔎 PLACES SEARCH: Trying method 2 - Places Text Search API (v1)");

        const fieldMask =
            'places.id,places.displayName,places.formattedAddress,places.location,'
            'places.rating,places.userRatingCount,places.types,'
            'places.currentOpeningHours,places.priceLevel';

        final body = <String, dynamic>{
          'textQuery': query,
        };
        if (latitude != null && longitude != null) {
          body['locationBias'] = {
            'circle': {
              'center': {'latitude': latitude, 'longitude': longitude},
              'radius': radius ?? 50000.0,
            }
          };
        }

        final textSearchHeaders = await _placesApiHeaders(apiKey, fieldMask);
        final response = await _dio.post(
          'https://places.googleapis.com/v1/places:searchText',
          data: body,
          options: Options(headers: textSearchHeaders),
        );

        if (response.statusCode == 200) {
          final data = response.data as Map<String, dynamic>;
          final places = data['places'] as List<dynamic>? ?? [];
          print(
              "🔎 PLACES SEARCH: Found ${places.length} places via Text Search (v1)");

          if (latitude != null && longitude != null) {
            places.sort((a, b) {
              final locA = a['location'] as Map<String, dynamic>?;
              final locB = b['location'] as Map<String, dynamic>?;
              if (locA == null || locB == null) return 0;
              final distA = _calculateDistance(
                  latitude, longitude, locA['latitude'], locA['longitude']);
              final distB = _calculateDistance(
                  latitude, longitude, locB['latitude'], locB['longitude']);
              return distA.compareTo(distB);
            });
            print("🔎 PLACES SEARCH: Sorted results by distance.");
          }

          List<Map<String, dynamic>> results = [];
          for (var place in places) {
            final nameMap = place['displayName'] as Map<String, dynamic>?;
            String? name = nameMap?['text'] as String?;
            String? address = place['formattedAddress'] as String?;
            double? rating = (place['rating'] as num?)?.toDouble();
            int? userRatingCount =
                (place['userRatingCount'] as num?)?.toInt();
            List<String>? types =
                (place['types'] as List<dynamic>?)?.cast<String>();
            bool? isOpen = (place['currentOpeningHours']
                as Map<String, dynamic>?)?['openNow'] as bool?;
            final priceLevelStr = place['priceLevel'] as String?;
            int? priceLevel;
            if (priceLevelStr != null) {
              const priceLevelMap = {
                'PRICE_LEVEL_FREE': 0,
                'PRICE_LEVEL_INEXPENSIVE': 1,
                'PRICE_LEVEL_MODERATE': 2,
                'PRICE_LEVEL_EXPENSIVE': 3,
                'PRICE_LEVEL_VERY_EXPENSIVE': 4,
              };
              priceLevel = priceLevelMap[priceLevelStr];
            }
            final loc = place['location'] as Map<String, dynamic>?;
            double? lat = (loc?['latitude'] as num?)?.toDouble();
            double? lng = (loc?['longitude'] as num?)?.toDouble();

            final rawId = place['id'] as String? ?? '';
            final placeId =
                rawId.startsWith('places/') ? rawId.substring(7) : rawId;

            if (name != null && address != null && lat != null && lng != null) {
              results.add({
                'placeId': placeId,
                'description': name,
                'address': address,
                'vicinity': address,
                'rating': rating,
                'userRatingCount': userRatingCount,
                'types': types,
                'isOpen': isOpen,
                'priceLevel': priceLevel,
                'latitude': lat,
                'longitude': lng,
                'place': place,
              });
            }
          }

          if (results.isNotEmpty) {
            print(
                "🔎 PLACES SEARCH: Found ${results.length} verified results using Text Search (v1)");
            for (int i = 0; i < min(3, results.length); i++) {
              print(
                  "🔎 PLACES SEARCH: Result ${i + 1}: '${results[i]['description']}' at '${results[i]['address']}'");
            }
            return results;
          } else {
            print(
                "🔎 PLACES SEARCH: No verified results from Text Search (v1)");
          }
        } else {
          print(
              "🔎 PLACES SEARCH: Text Search (v1) returned non-200 status code: ${response.statusCode}");
        }
      } catch (e) {
        print("🔎 PLACES SEARCH: Error with Text Search (v1): $e");
      }

      // If we got here, all search methods inside this function failed
      print(
          "🔎 PLACES SEARCH: All Places API search methods failed for query: $query");
      return [];
    } catch (e) {
      print("🔎 PLACES SEARCH ERROR: Top-level error: $e");
      return [];
    }
  }

  /// Search for places using the Text Search API (v1, bypasses Autocomplete)
  Future<List<Map<String, dynamic>>> searchPlacesTextSearch(
    String query, {
    double? latitude,
    double? longitude,
    double? radius,
  }) async {
    if (query.isEmpty) {
      return [];
    }

    print("\n🔎 TEXT SEARCH: Starting direct text search for query: '$query'");

    try {
      final key = _getApiKey();
      if (key.isEmpty) {
        print("🔎 TEXT SEARCH: No API key available");
        return [];
      }

      const fieldMask =
          'places.id,places.displayName,places.formattedAddress,places.location,'
          'places.rating,places.userRatingCount,places.types,'
          'places.currentOpeningHours,places.priceLevel';

      final body = <String, dynamic>{
        'textQuery': query,
      };
      if (latitude != null && longitude != null) {
        body['locationBias'] = {
          'circle': {
            'center': {'latitude': latitude, 'longitude': longitude},
            'radius': radius ?? 50000.0,
          }
        };
      }

      print("🔎 TEXT SEARCH: Calling v1 searchText API");

      final headers = await _placesApiHeaders(key, fieldMask);
      final response = await _dio.post(
        'https://places.googleapis.com/v1/places:searchText',
        data: body,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final places = data['places'] as List<dynamic>? ?? [];
        print("🔎 TEXT SEARCH: Found ${places.length} places");

        if (latitude != null && longitude != null) {
          places.sort((a, b) {
            final locA = a['location'] as Map<String, dynamic>?;
            final locB = b['location'] as Map<String, dynamic>?;
            if (locA == null || locB == null) return 0;
            final distA = _calculateDistance(
                latitude, longitude, locA['latitude'], locA['longitude']);
            final distB = _calculateDistance(
                latitude, longitude, locB['latitude'], locB['longitude']);
            return distA.compareTo(distB);
          });
        }

        List<Map<String, dynamic>> results = [];
        for (var place in places) {
          final nameMap = place['displayName'] as Map<String, dynamic>?;
          String? name = nameMap?['text'] as String?;
          String? address = place['formattedAddress'] as String?;
          double? rating = (place['rating'] as num?)?.toDouble();
          int? userRatingCount = (place['userRatingCount'] as num?)?.toInt();
          List<String>? types =
              (place['types'] as List<dynamic>?)?.cast<String>();
          bool? isOpen = (place['currentOpeningHours']
              as Map<String, dynamic>?)?['openNow'] as bool?;
          final priceLevelStr = place['priceLevel'] as String?;
          int? priceLevel;
          if (priceLevelStr != null) {
            const priceLevelMap = {
              'PRICE_LEVEL_FREE': 0,
              'PRICE_LEVEL_INEXPENSIVE': 1,
              'PRICE_LEVEL_MODERATE': 2,
              'PRICE_LEVEL_EXPENSIVE': 3,
              'PRICE_LEVEL_VERY_EXPENSIVE': 4,
            };
            priceLevel = priceLevelMap[priceLevelStr];
          }
          final loc = place['location'] as Map<String, dynamic>?;
          double? lat = (loc?['latitude'] as num?)?.toDouble();
          double? lng = (loc?['longitude'] as num?)?.toDouble();

          final rawId = place['id'] as String? ?? '';
          final placeId =
              rawId.startsWith('places/') ? rawId.substring(7) : rawId;

          if (name != null && address != null && lat != null && lng != null) {
            results.add({
              'placeId': placeId,
              'name': name,
              'description': name,
              'address': address,
              'vicinity': address,
              'rating': rating,
              'userRatingCount': userRatingCount,
              'types': types,
              'isOpen': isOpen,
              'priceLevel': priceLevel,
              'latitude': lat,
              'longitude': lng,
              'place': place,
            });
          }
        }

        if (results.isNotEmpty) {
          print("🔎 TEXT SEARCH: Found ${results.length} verified results");
          for (int i = 0; i < min(3, results.length); i++) {
            print(
                "🔎 TEXT SEARCH: Result ${i + 1}: '${results[i]['name']}' at '${results[i]['address']}'");
          }
          return results;
        }
      } else {
        print("🔎 TEXT SEARCH: HTTP error: ${response.statusCode}");
      }
    } catch (e) {
      print("🔎 TEXT SEARCH ERROR: $e");
    }

    return [];
  }

  // Helper function to calculate distance between two coordinates (Haversine formula)
  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295; // Pi / 180
    const c = cos;
    final a = 0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // 2 * R; R = 6371 km
  }

  /// Haversine distance between two WGS84 points in kilometers.
  double distanceBetweenKm(
      double lat1, double lon1, double lat2, double lon2) {
    return _calculateDistance(lat1, lon1, lat2, lon2);
  }

  /// Fetches place center, viewport, and types for Discovery area filtering.
  Future<DiscoveryAreaFilter?> fetchDiscoveryAreaFromPlace(
    String placeId,
    String label,
  ) async {
    if (placeId.isEmpty) return null;
    try {
      final key = _getApiKey();
      if (key.isEmpty) return null;

      const String fieldMask = 'id,displayName,location,viewport,types';
      final url = 'https://places.googleapis.com/v1/places/$placeId';
      final headers = await _placesApiHeaders(key, fieldMask);
      final response =
          await _dio.get(url, options: Options(headers: headers));
      if (response.statusCode != 200) return null;
      final data = response.data as Map<String, dynamic>?;
      if (data == null) return null;
      final Map<String, dynamic>? loc = data['location'] as Map<String, dynamic>?;
      if (loc == null) return null;
      final double lat = (loc['latitude'] as num?)?.toDouble() ?? 0.0;
      final double lng = (loc['longitude'] as num?)?.toDouble() ?? 0.0;
      if (!discoveryHasPlausibleCoordinates(lat, lng)) return null;

      DiscoveryMapBounds? bounds;
      final Map<String, dynamic>? vp = data['viewport'] as Map<String, dynamic>?;
      if (vp != null) {
        final Map<String, dynamic>? low = vp['low'] as Map<String, dynamic>?;
        final Map<String, dynamic>? high = vp['high'] as Map<String, dynamic>?;
        if (low != null && high != null) {
          final double? sl = (low['latitude'] as num?)?.toDouble();
          final double? wl = (low['longitude'] as num?)?.toDouble();
          final double? nl = (high['latitude'] as num?)?.toDouble();
          final double? el = (high['longitude'] as num?)?.toDouble();
          if (sl != null && wl != null && nl != null && el != null) {
            bounds = DiscoveryMapBounds(
              southLat: sl,
              westLng: wl,
              northLat: nl,
              eastLng: el,
            );
          }
        }
      }

      final List<String> types =
          (data['types'] as List<dynamic>?)?.cast<String>() ??
              const <String>[];
      final Map<String, dynamic>? dn =
          data['displayName'] as Map<String, dynamic>?;
      final String resolvedLabel = dn?['text'] as String? ?? label;

      return DiscoveryAreaFilter(
        placeId: placeId,
        label: resolvedLabel,
        latitude: lat,
        longitude: lng,
        viewport: bounds,
        types: types,
      );
    } catch (e, st) {
      debugPrint('fetchDiscoveryAreaFromPlace: $e\n$st');
      return null;
    }
  }

  /// Get place details by placeId
  /// [includePhotoUrl] - Whether to generate photo URLs (can be expensive and unnecessary for some use cases)
  Future<Location> getPlaceDetails(String placeId, {bool includePhotoUrl = true}) async {
    // 1. Check cache first
    if (_placeDetailsCache.containsKey(placeId)) {
      print('📍 PLACE DETAILS CACHE HIT for Place ID: $placeId');
      return _placeDetailsCache[placeId]!;
    }

    print('📍 PLACE DETAILS CACHE MISS for Place ID: $placeId. Calling API...');

    Location defaultLocation = Location(
      latitude: 0.0,
      longitude: 0.0,
      address: 'Location not found',
      placeId: placeId,
    );

    try {
      final key = _getApiKey();
      if (key.isEmpty) {
        print('Error: No API key available');
        return defaultLocation;
      }

      final fieldMask = [
        'id',
        'displayName',
        'formattedAddress',
        'addressComponents',
        'location',
        'websiteUri',
        'rating',
        'userRatingCount',
        'types',
        'primaryType',
        'primaryTypeDisplayName',
        if (includePhotoUrl) 'photos',
      ].join(',');

      final url = 'https://places.googleapis.com/v1/places/$placeId';
      final headers = await _placesApiHeaders(key, fieldMask);

      final response = await _dio.get(
        url,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        print('Place Details (v1) response OK for Place ID: $placeId');

        final loc = data['location'] as Map<String, dynamic>?;
        if (loc != null) {
          final double lat = (loc['latitude'] as num?)?.toDouble() ?? 0.0;
          final double lng = (loc['longitude'] as num?)?.toDouble() ?? 0.0;

          String? formattedAddress = data['formattedAddress'] as String?;
          String? city;
          String? state;
          String? country;
          String? zipCode;

          final addressComponents = data['addressComponents'] as List<dynamic>?;
          if (addressComponents != null) {
            for (var component in addressComponents) {
              final types = (component['types'] as List<dynamic>?) ?? [];
              final longText = component['longText'] as String?;
              final shortText = component['shortText'] as String?;

              if (types.contains('locality')) {
                city = longText;
              } else if (types.contains('administrative_area_level_1')) {
                state = shortText;
              } else if (types.contains('country')) {
                country = longText;
              } else if (types.contains('postal_code')) {
                zipCode = longText;
              }
            }
          }

          final displayNameMap = data['displayName'] as Map<String, dynamic>?;
          String? name = displayNameMap?['text'] as String?;

          String? websiteUrl = data['websiteUri'] as String?;
          if (websiteUrl != null) {
            print('Found website URL for place: $websiteUrl');
          }

          final double? rating = (data['rating'] as num?)?.toDouble();
          final int? userRatingCount = (data['userRatingCount'] as num?)?.toInt();

          final List<String>? placeTypes =
              (data['types'] as List<dynamic>?)?.cast<String>();

          final String? primaryType = data['primaryType'] as String?;
          final primaryTypeDisplayNameMap =
              data['primaryTypeDisplayName'] as Map<String, dynamic>?;
          final String? primaryTypeDisplayName =
              primaryTypeDisplayNameMap?['text'] as String?;

          String? photoUrl;
          if (includePhotoUrl) {
            final photos = data['photos'] as List<dynamic>?;
            if (photos != null && photos.isNotEmpty) {
              final photoName = photos[0]['name'] as String?;
              if (photoName != null) {
                photoUrl =
                    'https://places.googleapis.com/v1/$photoName/media?maxWidthPx=400&key=$key';
                print(
                    'Generated photo URL for place: ${photoUrl.substring(0, photoUrl.length > 50 ? 50 : photoUrl.length)}...');
              }
            }
          }

          final locationObj = Location(
            latitude: lat,
            longitude: lng,
            address: formattedAddress,
            city: city,
            state: state,
            country: country,
            zipCode: zipCode,
            displayName: name,
            placeId: placeId,
            photoUrl: photoUrl,
            website: websiteUrl,
            rating: rating,
            userRatingCount: userRatingCount,
            placeTypes: placeTypes,
            primaryType: primaryType,
            primaryTypeDisplayName: primaryTypeDisplayName,
          );

          _placeDetailsCache[placeId] = locationObj;
          print('📍 PLACE DETAILS CACHE STORED for Place ID: $placeId');
          return locationObj;
        } else {
          print('No location coordinates in v1 response for Place ID: $placeId');
        }
      } else {
        print(
            'Failed with status code: ${response.statusCode} for Place ID: $placeId');
      }
    } on DioException catch (e, s) {
      print('DioError getting place details for Place ID $placeId: ${e.message}');
      print('Stack trace: $s');
      if (e.response != null) {
        print('DioError response: ${e.response?.data}');
      }
    } catch (e, s) {
      print('Error getting place details for Place ID $placeId: $e');
      print('Stack trace: $s');
    }

    return defaultLocation;
  }

  /// Find a place near the tapped position - this improves POI selection
  Future<Location> findPlaceNearPosition(LatLng position) async {
    try {
      print(
          '📍 API SEARCH: Looking for POIs near ${position.latitude}, ${position.longitude}');

      // First try using the Places API to find nearby places (more accurate for POIs)
      try {
        // Search for places near the tapped location using the Places API v1
        final nearbyResponse = await _dio.post(
          'https://places.googleapis.com/v1/places:searchNearby',
          data: {
            "includedTypes": [
              "restaurant",
              "cafe",
              "store",
              "establishment",
              "point_of_interest",
              "food",
              "shop",
              "business",
              "bar",
              "lodging",
              "gym",
              "spa",
              "attraction"
            ], // Extended types to search for
            "locationRestriction": {
              "circle": {
                "center": {
                  "latitude": position.latitude,
                  "longitude": position.longitude
                },
                "radius":
                    100.0 // 100 meters radius to find the closest POI (increased from 50m)
              }
            },
            "rankPreference":
                "DISTANCE" // Prioritize places closest to the tapped point
          },
          options: Options(
            headers: await _placesApiHeaders(
              apiKey,
              'places.id,places.displayName,places.formattedAddress,places.location',
            ),
          ),
        );

        print(
            '📍 API RESPONSE: Places API nearby search response: ${nearbyResponse.data}');

        // Check if we found any places nearby
        if (nearbyResponse.statusCode == 200 &&
            nearbyResponse.data != null &&
            nearbyResponse.data['places'] != null &&
            (nearbyResponse.data['places'] as List).isNotEmpty) {
          // Get the closest place (first result when using DISTANCE ranking)
          final place = nearbyResponse.data['places'][0];

          // Extract place details
          String? placeName;
          if (place['displayName'] != null &&
              place['displayName']['text'] != null) {
            placeName = place['displayName']['text'];
            print('📍 API SUCCESS: Found nearby POI: $placeName');
          }

          String? address = place['formattedAddress'];
          double lat = place['location']?['latitude'] ?? position.latitude;
          double lng = place['location']?['longitude'] ?? position.longitude;

          print('📍 API COORDINATES: POI is at $lat, $lng');

          // Create a location with the POI's coordinates (not the tapped coordinates)
          return Location(
            latitude: lat,
            longitude: lng,
            address: address,
            displayName: placeName,
          );
        } else {
          print(
              '📍 API FALLBACK: No nearby places found, falling back to geocoding');
        }
      } catch (e) {
        print('📍 API ERROR: Error searching for nearby places: $e');
        // Continue with geocoding as fallback
      }

      // If Places API didn't find anything, fall back to geocoding
      print('📍 GEOCODING FALLBACK: Trying geocoding API instead');
      Location? geocodedLocation;
      try {
        final placeDetailsMap =
            await findPlaceDetails(position.latitude, position.longitude);

        if (placeDetailsMap != null) {
          double lat = placeDetailsMap['latitude'] as double? ?? position.latitude;
          double lng = placeDetailsMap['longitude'] as double? ?? position.longitude;
          print('📍 GEOCODING RESULT: Found place at $lat, $lng');
          geocodedLocation = Location(
            latitude: lat,
            longitude: lng,
            address: placeDetailsMap['address'] as String?,
            displayName: placeDetailsMap['name'] as String?,
            placeId: placeDetailsMap['placeId'] as String?,
          );
        }
      } catch (e) {
        print('📍 GEOCODING FALLBACK ERROR: Error during findPlaceDetails: $e');
      }

      if (geocodedLocation != null) {
        return geocodedLocation;
      }

      // Last resort - return a basic location with the original coordinates
      print('📍 FALLBACK: Using original tap coordinates (no POI found)');
      return Location(
        latitude: position.latitude,
        longitude: position.longitude,
        address:
            'Location at ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
        displayName: 'Selected Location',
      );
    } catch (e) {
      print('Error finding place near position: $e');

      // Return a basic location with the coordinates
      return Location(
        latitude: position.latitude,
        longitude: position.longitude,
        address:
            'Location at ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
        displayName: 'Selected Location',
      );
    }
  }

  /// Find place details using Google Places API via coordinates
  Future<Map<String, dynamic>?> findPlaceDetails(
      double latitude, double longitude) async {
    try {
      // Try using the Places API first (better business info)
      try {
        print('📍 Looking up place at coordinates using Places API v1');

        // First try to get a Place ID using reverse geocoding
        final geocodeUrl = Uri.parse(
            'https://maps.googleapis.com/maps/api/geocode/json?latlng=$latitude,$longitude&key=$apiKey');

        final geocodeResponse = await _httpClient.get(geocodeUrl);

        if (geocodeResponse.statusCode == 200) {
          final geocodeData = json.decode(geocodeResponse.body);
          print('📍 Geocoding response: $geocodeData');

          if (geocodeData['status'] == 'OK' &&
              geocodeData['results'] != null &&
              geocodeData['results'].isNotEmpty) {
            // Find result with establishment type
            Map<String, dynamic>? estResult;
            String? placeId;

            for (var result in geocodeData['results']) {
              final types = result['types'] as List? ?? [];
              if (types.contains('establishment') ||
                  types.contains('point_of_interest') ||
                  types.contains('restaurant') ||
                  types.contains('store')) {
                estResult = result;
                placeId = result['place_id'];
                print('📍 Found establishment with Place ID: $placeId');
                break;
              }
            }

            // If found a Place ID for an establishment, get details from Places API v1
            if (placeId != null) {
              try {
                final location = await getPlaceDetails(placeId, includePhotoUrl: false);
                if (location.displayName != null) {
                  print(
                      '📍 Successfully retrieved establishment name: ${location.displayName}');
                  return {
                    'placeId': placeId,
                    'name': location.displayName!,
                    'address': location.address ?? '',
                    // IMPORTANT: Use the location coordinates from the Places API
                    'latitude': location.latitude,
                    'longitude': location.longitude,
                    'types': estResult!['types'] as List? ?? []
                  };
                }
              } catch (e) {
                print('📍 Error getting details from Place ID: $e');
                // Continue with regular geocoding as fallback
              }
            }

            // Fallback to regular geocoding if Places API didn't work
            Map<String, dynamic>? placeResult;

            // If we already found an establishment, use that
            if (estResult != null) {
              placeResult = estResult;
            } else {
              // Otherwise look through all results
              for (var result in geocodeData['results']) {
                final types = result['types'] as List? ?? [];
                if (types.contains('establishment') ||
                    types.contains('point_of_interest') ||
                    types.contains('restaurant') ||
                    types.contains('store')) {
                  placeResult = result;
                  break;
                }
              }

              // If no establishment found, use the first result
              placeResult ??= geocodeData['results'][0];
            }

            // Try to extract business name or a meaningful place name
            String placeName = "Unknown Place";

            // First check for name in the result (rare for geocoding)
            if (placeResult != null) {
              if (placeResult['name'] != null) {
                placeName = placeResult['name'] as String;
                print('📍 REVERSE GEOCODING - Found name: $placeName');
              } else if (placeResult['formatted_address'] != null) {
                // Get first part of address (often contains business name)
                final address = placeResult['formatted_address'] as String;
                if (address.contains(',')) {
                  placeName = address.split(',')[0].trim();
                } else {
                  placeName = address;
                }
                print('📍 REVERSE GEOCODING - Using address part: $placeName');
              } else {
                print('📍 REVERSE GEOCODING - No name or address found');
              }

              // IMPORTANT: Get the actual coordinates from the geocoding result
              final location = placeResult['geometry']?['location'];
              final lat = location?['lat'] ?? latitude;
              final lng = location?['lng'] ?? longitude;

              return {
                'placeId': placeResult['place_id'] ?? '',
                'name': placeName,
                'address': placeResult['formatted_address'] ?? '',
                'latitude': lat,
                'longitude': lng,
                'types': placeResult['types'] as List? ?? []
              };
            }
          }
        }
      } catch (e) {
        print('📍 Error in Places API lookup: $e, falling back to geocoding');
      }

      // Fallback to basic geocoding if Places API didn't work
      final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json?latlng=$latitude,$longitude&key=$apiKey');

      final response = await _httpClient.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK' &&
            data['results'] != null &&
            data['results'].isNotEmpty) {
          final results = data['results'] as List;

          // Look for establishment or point of interest results
          Map<String, dynamic>? placeResult;

          for (var result in results) {
            final types = result['types'] as List? ?? [];
            if (types.contains('establishment') ||
                types.contains('point_of_interest') ||
                types.contains('restaurant') ||
                types.contains('store')) {
              placeResult = result;
              break;
            }
          }

          // If no establishment found, use the first result
          placeResult ??= results[0];

          // Try to extract business name or a meaningful place name
          String placeName = "Unknown Place";

          // Check if placeResult is not null before accessing its properties
          if (placeResult != null) {
            // First check for business name in the result (most specific)
            if (placeResult['name'] != null) {
              placeName = placeResult['name'] as String;
              print('📍 REVERSE GEOCODING FALLBACK - Found name: $placeName');
            } else if (placeResult['formatted_address'] != null) {
              // Get first part of address (often contains business name)
              final address = placeResult['formatted_address'] as String;
              if (address.contains(',')) {
                placeName = address.split(',')[0].trim();
              } else {
                placeName = address;
              }
              print(
                  '📍 REVERSE GEOCODING FALLBACK - Using address part: $placeName');
            } else {
              print('📍 REVERSE GEOCODING FALLBACK - No name or address found');
            }

            // IMPORTANT: Get the geocoded coordinates, not the original
            final location = placeResult['geometry']?['location'];
            final lat = location?['lat'] ?? latitude;
            final lng = location?['lng'] ?? longitude;

            return {
              'placeId': placeResult['place_id'] ?? '',
              'name': placeName,
              'address': placeResult['formatted_address'] ?? '',
              'latitude': lat,
              'longitude': lng,
              'types': placeResult['types'] as List? ?? []
            };
          }
        }
      }

      // If we couldn't get any valid place information, return a minimal result with coordinates
      return {
        'placeId': '',
        'name': 'Selected Location',
        'address':
            'Location at ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
        'latitude': latitude,
        'longitude': longitude,
        'types': []
      };
    } catch (e) {
      print('Error finding place details: $e');

      // Even in case of error, return minimal coordinates to avoid null issues
      return {
        'placeId': '',
        'name': 'Selected Location',
        'address':
            'Location at ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
        'latitude': latitude,
        'longitude': longitude,
        'types': []
      };
    }
  }

  /// More detailed place search at coordinates
  Future<Map<String, dynamic>?> findPlaceAtCoordinates(
      double latitude, double longitude) async {
    try {
      // Try using reverse geocoding
      final geocodeResponse = await _dio.get(
          'https://maps.googleapis.com/maps/api/geocode/json',
          queryParameters: {
            'latlng': '$latitude,$longitude',
            'key': apiKey,
            'radius': '50' // Increase search radius to 50 meters
          });

      if (geocodeResponse.statusCode == 200 &&
          geocodeResponse.data?['status'] == 'OK' &&
          geocodeResponse.data?['results'] != null) {
        final List<dynamic> geocodeResults =
            (geocodeResponse.data?['results'] as List?) ?? [];

        // Look for results with establishment or point_of_interest types
        Map<String, dynamic>? placeResult;

        if (geocodeResults.isNotEmpty) {
          for (var result in geocodeResults) {
            List<dynamic> types = result['types'] as List? ?? [];
            if (types.contains('establishment') ||
                types.contains('point_of_interest') ||
                types.contains('restaurant') ||
                types.contains('store') ||
                types.contains('bakery') ||
                types.contains('cafe')) {
              placeResult = result;
              break;
            }
          }

          // If we didn't find an establishment, use the most specific result
          if (placeResult == null && geocodeResults.isNotEmpty) {
            placeResult = geocodeResults[0];
          }
        }

        if (placeResult != null) {
          // IMPORTANT: Get the actual POI coordinates
          final location = placeResult['geometry']?['location'];
          final lat = location?['lat'] ?? latitude;
          final lng = location?['lng'] ?? longitude;

          // Create a clean result object
          final result = {
            'placeId': placeResult['place_id'] ?? '',
            'name': _extractPlaceName(placeResult),
            'address': placeResult['formatted_address'] ?? '',
            'latitude': lat,
            'longitude': lng,
            'types': placeResult['types'] as List? ?? []
          };

          return result;
        }
      }

      // If we couldn't get any valid place information, return a minimal result with coordinates
      return {
        'placeId': '',
        'name': 'Selected Location',
        'address':
            'Location at ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
        'latitude': latitude,
        'longitude': longitude,
        'types': []
      };
    } catch (e) {
      print('Error finding place at coordinates: $e');

      // Even in case of error, return minimal coordinates to avoid null issues
      return {
        'placeId': '',
        'name': 'Selected Location',
        'address':
            'Location at ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
        'latitude': latitude,
        'longitude': longitude,
        'types': []
      };
    }
  }

  /// Helper to extract a meaningful name from geocoding result
  String _extractName(Map<String, dynamic> result) {
    // First try to get the name of the establishment
    if (result['address_components'] != null &&
        (result['address_components'] as List).isNotEmpty) {
      return result['address_components'][0]['long_name'] as String? ??
          'Unknown Place';
    }

    // Fallback to first part of the address
    if (result['formatted_address'] != null) {
      final address = result['formatted_address'] as String;
      if (address.contains(',')) {
        return address.split(',')[0].trim();
      }
      return address;
    }

    return 'Unknown Place';
  }

  /// Helper method to extract a place name from geocoding result
  String _extractPlaceName(Map<String, dynamic> geocodeResult) {
    // First check if there's a name in the result (rare for geocoding)
    if (geocodeResult.containsKey('name') && geocodeResult['name'] != null) {
      return geocodeResult['name'] as String;
    }

    // Try to get the most specific component
    if (geocodeResult['address_components'] != null &&
        (geocodeResult['address_components'] as List).isNotEmpty) {
      // First component is usually the most specific (name of place)
      return geocodeResult['address_components'][0]['long_name'] as String;
    }

    // If we can't get a name, use the formatted address
    if (geocodeResult['formatted_address'] != null) {
      String address = geocodeResult['formatted_address'] as String;
      // Take only the first part of the address (before the first comma)
      if (address.contains(',')) {
        return address.split(',')[0].trim();
      }
      return address;
    }

    // Fallback
    return 'Selected Place';
  }

  /// Get place details from geocoding service, ensuring Place ID is included.
  Future<Location> getAddressFromLatLng(LatLng position) async {
    print(
        "🗺️ GEOCODING: Getting address details for LatLng: ${position.latitude}, ${position.longitude}");
    try {
      final placeDetails =
          await findPlaceDetails(position.latitude, position.longitude);

      if (placeDetails != null) {
        print(
            "🗺️ GEOCODING: Found details: Name='${placeDetails['name']}', Address='${placeDetails['address']}', PlaceID='${placeDetails['placeId']}'");
        return Location(
          // Use the coordinates from the result, which might be snapped to a POI
          latitude: placeDetails['latitude'] as double? ?? position.latitude,
          longitude: placeDetails['longitude'] as double? ?? position.longitude,
          address: placeDetails['address'] as String?,
          displayName: placeDetails['name'] as String?,
          // Ensure placeId is passed through
          placeId: placeDetails['placeId'] as String?,
        );
      } else {
        print(
            "🗺️ GEOCODING: findPlaceDetails returned null. Creating basic location.");
      }

      // If we couldn't get details, return a basic location
      return Location(
        latitude: position.latitude,
        longitude: position.longitude,
        address:
            'Location at ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
        displayName: 'Tapped Location', // More specific default name
        placeId: null, // Explicitly null if no details found
      );
    } catch (e) {
      print('🗺️ GEOCODING ERROR: Error getting address: $e');

      // Even in case of error, return a basic location to avoid null issues
      return Location(
        latitude: position.latitude,
        longitude: position.longitude,
        address: 'Error finding location details', // Indicate error in address
        displayName: 'Tapped Location',
        placeId: null,
      );
    }
  }

  /// Generate a static map image URL
  String getStaticMapUrl(double latitude, double longitude,
      {int zoom = 14, int width = 600, int height = 300}) {
    return 'https://maps.googleapis.com/maps/api/staticmap?center=$latitude,$longitude&zoom=$zoom&size=${width}x$height&markers=color:red%7C$latitude,$longitude&key=$apiKey';
  }

  /// Alias for static map URL
  String getStaticMapImageUrl(double latitude, double longitude,
      {int zoom = 14, int width = 600, int height = 300}) {
    final apiKey = _getApiKey();

    // Debug the domain
    final baseUrl = 'https://maps.googleapis.com/maps/api/staticmap';
    print('🗺️ MAP DEBUG: Using base URL: $baseUrl');

    return '$baseUrl?'
        'center=$latitude,$longitude'
        '&zoom=$zoom'
        '&size=${width}x$height'
        '&markers=color:red%7C$latitude,$longitude'
        '&key=$apiKey';
  }

  /// Get place image from Google Places API using place ID
  Future<String?> getPlaceImageUrl(String placeId,
      {int maxWidth = 600, int maxHeight = 300}) async {
    print('🔍 PLACE IMAGE: Fetching image for place ID: $placeId');

    try {
      final apiKey = _getApiKey();
      print('🔍 PLACE IMAGE: Using Places API (new) to get image');

      // Use the Places API (New) specifically for better chain location support
      final url = 'https://places.googleapis.com/v1/places/$placeId';
      print(
          '🔍 PLACE IMAGE: Request URL: ${url.replaceAll(apiKey, "API_KEY_HIDDEN")}');

      final photoHeaders = await _placesApiHeaders(apiKey, 'photos,displayName');
      final response = await _dio.get(
        url,
        options: Options(headers: photoHeaders),
      );

      if (response.statusCode == 200) {
        final data = response.data;

        // Log display name to verify we have the right location
        if (data['displayName'] != null &&
            data['displayName']['text'] != null) {
          final displayName = data['displayName']['text'];
          print('🔍 PLACE IMAGE: Location display name: $displayName');

          // Check if this might be a chain location like McDonald's
          final possibleChainNames = [
            'McDonald',
            'Starbucks',
            'Subway',
            'KFC',
            'Burger King',
            'Wendy',
            'Taco Bell',
            'Pizza Hut',
            'Domino',
            'Dunkin',
            'Chipotle',
            'Chick-fil-A',
            'Popeyes',
            'Panera',
            'Baskin',
            'Dairy Queen',
            'Papa John',
            'Panda Express',
            'Sonic',
            'Arby'
          ];

          bool isChain = false;
          for (final chain in possibleChainNames) {
            if (displayName.toLowerCase().contains(chain.toLowerCase())) {
              isChain = true;
              print('🔍 PLACE IMAGE: Detected chain business: $chain');
              break;
            }
          }

          if (isChain) {
            print(
                '🔍 PLACE IMAGE: This is a chain location - ensuring we get the right branch image');
          }
        }

        // Check if place has photos
        if (data['photos'] != null && data['photos'].isNotEmpty) {
          final photoResource = data['photos'][0]['name'] as String?;
          if (photoResource != null) {
            final resolved = await resolvePhotoMediaUrl(photoResource,
                maxWidthPx: maxWidth, maxHeightPx: maxHeight);
            if (resolved != null) return resolved;
          }

          final fallbackUrl = buildPlacePhotoUrlFromResourceName(
              photoResource,
              maxWidthPx: maxWidth,
              maxHeightPx: maxHeight);
          if (fallbackUrl != null) return fallbackUrl;
        } else {
          print(
              '🔍 PLACE IMAGE: No photos available in Places API (New), trying legacy API');

          // Try the legacy Places API as a fallback
          final photoUrl = await getPlacePhoto(placeId);
          if (photoUrl != null) {
            print(
                '🔍 PLACE IMAGE: Successfully found photo using legacy Places API');
            return photoUrl;
          } else {
            print('🔍 PLACE IMAGE: No photos available in legacy API either');
          }
        }
      } else {
        print(
            '🔍 PLACE IMAGE: Failed with status code: ${response.statusCode}');

        // Try legacy API as fallback
        print('🔍 PLACE IMAGE: Trying legacy Places API as fallback');
        final photoUrl = await getPlacePhoto(placeId);
        if (photoUrl != null) {
          return photoUrl;
        }
      }
    } catch (e, stack) {
      print('🔍 PLACE IMAGE ERROR: $e');
      print('🔍 PLACE IMAGE ERROR STACK: $stack');

      // Try legacy API as fallback
      try {
        print(
            '🔍 PLACE IMAGE: Trying legacy Places API as fallback after error');
        final photoUrl = await getPlacePhoto(placeId);
        if (photoUrl != null) {
          return photoUrl;
        }
      } catch (fallbackError) {
        print('🔍 PLACE IMAGE: Fallback also failed: $fallbackError');
      }
    }

    // Fallback to static map if no place photos available
    return null;
  }

  /// Generate directions URL
  String getDirectionsUrl(Location location) {
    // Prioritize using the address if available and seems valid
    String destination;
    if (location.address != null &&
        location.address!.isNotEmpty &&
        !location.address!.contains('Coordinates:')) {
      // Added check to avoid using placeholder address
      destination = Uri.encodeComponent(location.address!);
      print(
          '🧭 DIRECTIONS SERVICE: Using address for destination: ${location.address}');
    } else {
      // Fallback to coordinates
      destination = '${location.latitude},${location.longitude}';
      print(
          '🧭 DIRECTIONS SERVICE: Using coordinates for destination: $destination');
    }

    // Construct the URL
    final url =
        'https://www.google.com/maps/dir/?api=1&destination=$destination';
    return url;
  }

  /// Get directions URL between two coordinates (legacy method signature for compatibility)
  String getDirectionsUrlFromCoordinates(
      double startLat, double startLng, double endLat, double endLng) {
    return getDirectionsUrl(Location(
      latitude: endLat,
      longitude: endLng,
    ));
  }

  // Check if place has photos and return the first photo reference
  Future<String?> getPlacePhoto(String placeId) async {
    print('🔍 PHOTOS: Fetching photos for place ID: $placeId');

    try {
      final apiKey = _getApiKey();
      print(
          '🔍 PHOTOS: API key length: ${apiKey.length}, starts with: ${apiKey.substring(0, min(5, apiKey.length))}...');

      if (apiKey.isEmpty) {
        print('🔍 PHOTOS: No API key available');
        return null;
      }

      // First, get place details to retrieve photo references
      final url =
          'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&fields=photos&key=$apiKey';

      print(
          '🔍 PHOTOS: Sending request to: ${url.replaceAll(apiKey, "API_KEY")}');
      final response = await _dio.get(url);

      if (response.statusCode == 200) {
        final data = response.data;
        final dataString = data.toString();
        print(
            '🔍 PHOTOS: Got response: ${dataString.substring(0, dataString.length > 200 ? 200 : dataString.length)}...');

        // Check specifically for API key issues
        if (data['status'] == 'REQUEST_DENIED') {
          print(
              '🔍 PHOTOS ERROR: API request denied. Error message: ${data['error_message']}');
          return null;
        }

        if (data['status'] == 'OK') {
          // Check if place has photos
          if (data['result'] != null &&
              data['result']['photos'] != null &&
              data['result']['photos'].isNotEmpty) {
            // Get the first photo reference
            final photoReference =
                data['result']['photos'][0]['photo_reference'].toString();
            print(
                '🔍 PHOTOS: Found photo reference: ${photoReference.substring(0, photoReference.length > 30 ? 30 : photoReference.length)}...');

            // Construct the photo URL
            final photoUrl =
                'https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&maxheight=400&photo_reference=$photoReference&key=$apiKey';
            print('🔍 PHOTOS: Photo URL constructed successfully');

            return photoUrl;
          } else {
            print('🔍 PHOTOS: No photos available for this place');
          }
        } else {
          print('🔍 PHOTOS: Error in API response: ${data['status']}');
        }
      } else {
        print('🔍 PHOTOS: Failed with status code: ${response.statusCode}');
      }
    } catch (e, stack) {
      print('🔍 PHOTOS ERROR: $e');
      print('🔍 PHOTOS ERROR STACK: $stack');
    }

    return null;
  }

  // Retrieve multiple photo references for a place (up to limit)
  Future<List<String>> getPlacePhotoReferences(String placeId,
      {int limit = 5}) async {
    print('🔍 PHOTOS: Fetching multiple photos for place ID: $placeId');

    try {
      final apiKey = _getApiKey();
      print(
          '🔍 PHOTOS: API key length: ${apiKey.length}, starts with: ${apiKey.substring(0, min(5, apiKey.length))}...');

      if (apiKey.isEmpty) {
        print('🔍 PHOTOS: No API key available');
        return [];
      }

      // Get place details with photos field
      final url =
          'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&fields=photos&key=$apiKey';
      print('🔍 PHOTOS: Request URL: ${url.replaceAll(apiKey, "API_KEY")}');

      final response = await _dio.get(url);

      if (response.statusCode == 200) {
        final data = response.data;

        // Debug output for the response
        final responseStr = data.toString();
        print(
            '🔍 PHOTOS: Response: ${responseStr.substring(0, min(200, responseStr.length))}...');

        // Check specifically for API key issues
        if (data['status'] == 'REQUEST_DENIED') {
          print(
              '🔍 PHOTOS ERROR: API request denied. Error message: ${data['error_message']}');
          return [];
        }

        if (data['status'] == 'OK' &&
            data['result'] != null &&
            data['result']['photos'] != null) {
          // Extract photo references
          List<String> photoUrls = [];
          final photos = data['result']['photos'];

          print('🔍 PHOTOS: Found ${photos.length} photos for this place');

          // Get up to limit photos
          final int photoCount = photos.length as int;
          final int count = photoCount < limit ? photoCount : limit;

          for (var i = 0; i < count; i++) {
            final photoReference = photos[i]['photo_reference'];
            if (photoReference != null) {
              final photoUrl =
                  'https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&maxheight=400&photo_reference=$photoReference&key=$apiKey';
              photoUrls.add(photoUrl);
              print('🔍 PHOTOS: Added photo URL #${i + 1}');
            }
          }

          print(
              '🔍 PHOTOS: Successfully retrieved ${photoUrls.length} photo URLs');
          return photoUrls;
        } else {
          print(
              '🔍 PHOTOS: No photos found in API response. Status: ${data['status']}');
        }
      } else {
        print(
            '🔍 PHOTOS: API request failed with status code: ${response.statusCode}');
      }
    } catch (e, stack) {
      print('🔍 PHOTOS ERROR: $e');
      print('🔍 PHOTOS ERROR STACK: $stack');
    }

    return [];
  }

  // Retrieve API key for Google Maps API
  String _getApiKey() {
    // Use the same API key that's used elsewhere in the service
    return apiKey;
  }

  /// Builds standard headers for Places API (New) REST calls.
  /// On iOS/Android, includes the platform bundle/package identifier so
  /// platform-restricted API keys are accepted by Google
  /// (Dio requests don't send these automatically like the native SDK does).
  Future<Map<String, String>> _placesApiHeaders(
      String key, String fieldMask) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': key,
      'X-Goog-FieldMask': fieldMask,
    };
    if (!kIsWeb && Platform.isIOS) {
      headers['X-Ios-Bundle-Identifier'] = ApiKeys.firebaseIosBundleId;
    } else if (!kIsWeb && Platform.isAndroid) {
      headers['X-Android-Package'] = 'com.plendy.app';
      final sha1 = await _getAndroidCertSha1();
      if (sha1 != null) {
        headers['X-Android-Cert'] = sha1;
        print('🔑 PLACES API: Android cert SHA-1: $sha1');
      } else {
        print('⚠️ PLACES API: Android cert SHA-1 is null — header not sent');
      }
    }
    return headers;
  }

  /// Fetches detailed place information using the Places API (New).
  ///
  /// Returns a Map containing the fetched data, or null if an error occurs.
  Future<Map<String, dynamic>?> fetchPlaceDetailsData(String placeId) async {
    // Ensure API key is available
    final apiKey = _getApiKey();
    if (apiKey.isEmpty) {
      print('❌ PLACES DETAILS (v1): No API key available');
      return null;
    }

    // Define the fields to request using FieldMask syntax
    const String fieldMask =
        'id,displayName,formattedAddress,addressComponents,location,websiteUri,nationalPhoneNumber,regularOpeningHours,currentOpeningHours,businessStatus,reservable,parkingOptions,editorialSummary,rating,userRatingCount,priceLevel,photos,types,primaryType,primaryTypeDisplayName';

    final url = 'https://places.googleapis.com/v1/places/$placeId';

    print('📍 PLACES DETAILS (v1): Requesting details for Place ID: $placeId');
    print(
        '📍 PLACES DETAILS (v1): URL: ${url.replaceAll(apiKey, "<API_KEY>")}');
    print('📍 PLACES DETAILS (v1): FieldMask: $fieldMask');

    try {
      final detailsHeaders = await _placesApiHeaders(apiKey, fieldMask);
      final response = await _dio.get(
        url,
        options: Options(
          headers: detailsHeaders,
          sendTimeout: Duration(seconds: 10),
          receiveTimeout: Duration(seconds: 10),
        ),
      );

      print(
          '📍 PLACES DETAILS (v1): Response Status Code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = response.data;
        // Log small part of response for verification
        // print('📍 PLACES DETAILS (v1): Response Data: ${jsonEncode(data).substring(0, min(300, jsonEncode(data).length))}...');
        print(
            '📍 PLACES DETAILS (v1): Successfully fetched details for ${data?['displayName']?['text']}');
        return data as Map<String, dynamic>;
      } else {
        print(
            '❌ PLACES DETAILS (v1): API Error - Status Code: ${response.statusCode}, Response: ${response.data}');
        return null;
      }
    } on DioException catch (e) {
      // Handle Dio specific errors (timeouts, network issues, etc.)
      print('❌ PLACES DETAILS (v1): DioException - ${e.type}: ${e.message}');
      if (e.response != null) {
        print(
            '❌ PLACES DETAILS (v1): DioException Response: ${e.response?.data}');
      }
      return null;
    } catch (e) {
      print('❌ PLACES DETAILS (v1): Generic Exception - $e');
      return null;
    }
  }

  /// Search for places near the given coordinates
  Future<List<Map<String, dynamic>>> searchNearbyPlaces(
      double latitude, double longitude,
      [int radius = 50, String query = '']) async {
    final apiKey = _getApiKey();
    print(
        "🔍 NEARBY SEARCH: Searching near lat=$latitude, lng=$longitude within ${radius}m radius");
    if (query.isNotEmpty) {
      print("🔍 NEARBY SEARCH: With query: '$query'");
    }
    print("🔍 NEARBY SEARCH: Using API key: ${_maskApiKey(apiKey)}");

    // Build the URL, adding the query if provided
    String url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
        '?location=$latitude,$longitude'
        '&radius=$radius';

    // Add keyword or name parameter if query is provided
    if (query.isNotEmpty) {
      // If the query looks like a business name, use name parameter for better specificity
      // Otherwise, use keyword for broader matches
      if (_isLikelyBusinessName(query)) {
        url += '&name=${Uri.encodeComponent(query)}';
      } else {
        url += '&keyword=${Uri.encodeComponent(query)}';
      }
    }

    // Add the API key
    url += '&key=$apiKey';

    try {
      final response = await _httpClient.get(Uri.parse(url));
      print(
          "🔍 NEARBY SEARCH: API response status code: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK' && data['results'] != null) {
          print(
              "🔍 NEARBY SEARCH: Found ${data['results'].length} nearby places");

          // Transform and return the results
          List<Map<String, dynamic>> places = [];
          for (var place in data['results']) {
            Map<String, dynamic> placeData = {
              'placeId': place['place_id'],
              'name': place['name'],
              'description': place['name'] +
                  (place['vicinity'] != null ? ' - ' + place['vicinity'] : ''),
              'vicinity': place['vicinity'],
              'latitude': place['geometry']?['location']?['lat'],
              'longitude': place['geometry']?['location']?['lng'],
            };
            places.add(placeData);
          }

          return places;
        } else {
          print(
              "🔍 NEARBY SEARCH ERROR: API returned status: ${data['status']}");
          return [];
        }
      } else {
        print(
            "🔍 NEARBY SEARCH ERROR: Failed with status code: ${response.statusCode}");
        return [];
      }
    } catch (e) {
      print("🔍 NEARBY SEARCH ERROR: Exception during API call: $e");
      return [];
    }
  }

  // Helper to determine if a query is likely a business name
  bool _isLikelyBusinessName(String query) {
    // If it contains common business indicators
    if (query.contains("restaurant") ||
        query.contains("cafe") ||
        query.contains("bar") ||
        query.contains("shop") ||
        query.contains("store")) {
      return false; // These are likely general searches
    }

    // If it has quotes, it's explicitly looking for exact name
    if (query.contains('"')) {
      return true;
    }

    // If it's short (1-3 words) and doesn't have special search operators
    final words = query.split(' ');
    if (words.length <= 3 &&
        !query.contains("near") &&
        !query.contains("around") &&
        !query.contains("in")) {
      return true;
    }

    return false;
  }

  // Helper to mask the API key for logging
  String _maskApiKey(String key) {
    if (key.length <= 8) return "***";
    return "${key.substring(0, 4)}...${key.substring(key.length - 4)}";
  }

  // Get the address from coordinates using reverse geocoding
  Future<String?> getAddressFromCoordinates(
      double latitude, double longitude) async {
    final apiKey = _getApiKey();
    final url =
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=$latitude,$longitude&key=$apiKey';

    try {
      final response = await _httpClient.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK' &&
            data['results'] != null &&
            data['results'].isNotEmpty) {
          // Get the first result (most specific)
          final result = data['results'][0];
          return result['formatted_address'] as String?;
        }
      }

      return null;
    } catch (e) {
      print('ERROR: Failed to get address from coordinates: $e');
      return null;
    }
  }

  /// Fetches the best available summary for a place using Places API (New).
  /// Priority: editorialSummary → reviewSummary → generativeSummary
  /// Returns null if no summary is available.
  Future<String?> fetchPlaceSummary(String placeId) async {
    final apiKey = _getApiKey();
    if (apiKey.isEmpty) {
      print('❌ PLACE SUMMARY: No API key available');
      return null;
    }

    // Request all three summary fields
    const String fieldMask = 'editorialSummary,reviewSummary,generativeSummary';
    final url = 'https://places.googleapis.com/v1/places/$placeId';

    print('📝 PLACE SUMMARY: Fetching summaries for Place ID: $placeId');

    try {
      final summaryHeaders = await _placesApiHeaders(apiKey, fieldMask);
      final response = await _dio.get(
        url,
        options: Options(
          headers: summaryHeaders,
          sendTimeout: Duration(seconds: 10),
          receiveTimeout: Duration(seconds: 10),
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>?;
        if (data == null) {
          print('📝 PLACE SUMMARY: Empty response data');
          return null;
        }

        // Helper to safely extract text from a summary field
        String? extractText(dynamic summaryField) {
          if (summaryField == null) return null;
          
          // If it's directly a String, return it
          if (summaryField is String) {
            return summaryField.isNotEmpty ? summaryField : null;
          }
          
          // If it's a Map, try to get the 'text' field
          if (summaryField is Map) {
            final textValue = summaryField['text'];
            // 'text' could be a String or another Map with 'text'
            if (textValue is String && textValue.isNotEmpty) {
              return textValue;
            }
            // Handle nested structure where text itself is a LocalizedText object
            if (textValue is Map && textValue['text'] is String) {
              final nestedText = textValue['text'] as String;
              return nestedText.isNotEmpty ? nestedText : null;
            }
          }
          
          return null;
        }

        // Priority 1: editorialSummary (human-written, no AI attribution needed)
        final editorialText = extractText(data['editorialSummary']);
        if (editorialText != null) {
          print('📝 PLACE SUMMARY: Found editorialSummary');
          return editorialText;
        }

        // Priority 2: reviewSummary (AI-generated synthesis of reviews)
        final reviewText = extractText(data['reviewSummary']);
        if (reviewText != null) {
          print('📝 PLACE SUMMARY: Found reviewSummary');
          return reviewText;
        }

        // Priority 3: generativeSummary (AI-generated place description)
        if (data['generativeSummary'] != null) {
          final generativeSummary = data['generativeSummary'];
          if (generativeSummary is Map) {
            // Try overview first
            final overviewText = extractText(generativeSummary['overview']);
            if (overviewText != null) {
              print('📝 PLACE SUMMARY: Found generativeSummary.overview');
              return overviewText;
            }
            // Try description as fallback
            final descriptionText = extractText(generativeSummary['description']);
            if (descriptionText != null) {
              print('📝 PLACE SUMMARY: Found generativeSummary.description');
              return descriptionText;
            }
          }
        }

        print('📝 PLACE SUMMARY: No summaries available for this place');
        return null;
      } else {
        print('❌ PLACE SUMMARY: API Error - Status Code: ${response.statusCode}');
        return null;
      }
    } on DioException catch (e) {
      print('❌ PLACE SUMMARY: DioException - ${e.type}: ${e.message}');
      return null;
    } catch (e) {
      print('❌ PLACE SUMMARY: Generic Exception - $e');
      return null;
    }
  }
}
