import 'dart:async';
import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'dart:convert';
import '../config/api_secrets.dart';
import '../models/experience.dart';

/// Service class for Google Maps functionality
class GoogleMapsService {
  static final GoogleMapsService _instance = GoogleMapsService._internal();

  factory GoogleMapsService() {
    return _instance;
  }

  GoogleMapsService._internal();

  // For more advanced API requests
  final Dio _dio = Dio();

  // Cache for Place Details results keyed by Place ID
  final Map<String, Location> _placeDetailsCache = {};

  // Get the API key securely
  static String get apiKey => ApiSecrets.googleMapsApiKey;

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
        final response = await _dio.post(
          'https://places.googleapis.com/v1/places:autocomplete', // CORRECTED ENDPOINT
          data: requestBody,
          options: Options(
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': apiKey,
              // FieldMask for Autocomplete (New) - adjust based on what you need from suggestions
              // This requests common fields from the PlacePrediction part of the suggestion.
              'X-Goog-FieldMask': 'suggestions.placePrediction.placeId,suggestions.placePrediction.text,suggestions.placePrediction.structuredFormat,suggestions.placePrediction.types'
            },
          ),
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

      // Fallback to the standard Places API Text Search if the first approach failed
      try {
        print("🔎 PLACES SEARCH: Trying method 2 - Places Text Search API");

        // Build base URL
        String baseUrl =
            'https://maps.googleapis.com/maps/api/place/textsearch/json';
        String encodedQuery = Uri.encodeComponent(query);
        String url = '$baseUrl?query=$encodedQuery&key=$apiKey';

        // Add location bias parameters if provided
        if (latitude != null && longitude != null) {
          url += '&location=$latitude,$longitude';
          // Use provided radius or default to 50km for legacy API
          url += '&radius=${radius ?? 50000}';
        }

        print(
            "🔎 PLACES SEARCH: Request URL: ${url.replaceAll(apiKey, 'API_KEY')}");

        final response = await http.get(Uri.parse(url));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          print("🔎 PLACES SEARCH: Response status: ${data['status']}");

          if (data['status'] == 'OK' && data['results'] != null) {
            final places = data['results'] as List;
            print(
                "🔎 PLACES SEARCH: Found ${places.length} places via TextSearch");

            // If we have location bias, sort results by distance (approximate)
            if (latitude != null && longitude != null) {
              places.sort((a, b) {
                final locA = a['geometry']?['location'];
                final locB = b['geometry']?['location'];
                if (locA == null || locB == null) return 0;
                final distA = _calculateDistance(
                    latitude, longitude, locA['lat'], locA['lng']);
                final distB = _calculateDistance(
                    latitude, longitude, locB['lat'], locB['lng']);
                return distA.compareTo(distB);
              });
              print("🔎 PLACES SEARCH: Sorted results by distance.");
            }

            // Process and return results (moved logic inside)
            List<Map<String, dynamic>> results = [];
            for (var place in places) {
              String? name = place['name'];
              String? address = place['formatted_address'];
              String? vicinity = place['vicinity'];
              double? rating = place['rating']?.toDouble();
              int? userRatingCount = place['user_ratings_total'];
              List<String>? types = (place['types'] as List?)?.cast<String>();
              bool? isOpen = place['opening_hours']?['open_now'];
              int? priceLevel = place['price_level'];
              Map<String, dynamic>? geometry = place['geometry'];
              Map<String, dynamic>? location = geometry?['location'];
              double? lat = location?['lat'];
              double? lng = location?['lng'];

              if (name != null &&
                  (address != null || vicinity != null) &&
                  lat != null &&
                  lng != null) {
                results.add({
                  'placeId': place['place_id'] ?? '',
                  'description': name +
                      (vicinity != null && vicinity != name
                          ? ' - $vicinity'
                          : ''), // Better description
                  'address': address ?? vicinity,
                  'vicinity': vicinity, // Keep vicinity separately if needed
                  'rating': rating,
                  'userRatingCount': userRatingCount,
                  'types': types,
                  'isOpen': isOpen,
                  'priceLevel': priceLevel,
                  'latitude': lat,
                  'longitude': lng,
                  'place': place
                });
              }
            }

            if (results.isNotEmpty) {
              print(
                  "🔎 PLACES SEARCH: Found ${results.length} verified results using Places Text Search API");
              for (int i = 0; i < min(3, results.length); i++) {
                print(
                    "🔎 PLACES SEARCH: Result ${i + 1}: '${results[i]['description']}' at '${results[i]['address']}'");
              }
              return results;
            } else {
              print(
                  "🔎 PLACES SEARCH: No verified results from Places Text Search API despite OK status");
            }
          } else {
            print(
                "🔎 PLACES SEARCH: API returned non-OK status: ${data['status']}");
            if (data['error_message'] != null) {
              print(
                  "🔎 PLACES SEARCH: Error message: ${data['error_message']}");
            }
          }
        } else {
          print(
              "🔎 PLACES SEARCH: Text Search API returned non-200 status code: ${response.statusCode}");
        }
      } catch (e) {
        print("🔎 PLACES SEARCH: Error with Places Text Search API: $e");
        // Continue to next fallback? (Currently no other fallback here)
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

  /// Get place details by placeId
  Future<Location> getPlaceDetails(String placeId) async {
    // 1. Check cache first
    if (_placeDetailsCache.containsKey(placeId)) {
      print('📍 PLACE DETAILS CACHE HIT for Place ID: $placeId');
      return _placeDetailsCache[placeId]!;
    }

    print('📍 PLACE DETAILS CACHE MISS for Place ID: $placeId. Calling API...');

    // Default location (used if there's an error)
    Location defaultLocation = Location(
      latitude: 0.0,
      longitude: 0.0,
      address: 'Location not found',
      placeId: placeId, // Include the place ID even in the default location
    );

    try {
      final apiKey = _getApiKey();
      if (apiKey.isEmpty) {
        print('Error: No API key available');
        return defaultLocation;
      }

      // Include 'website', 'rating', 'user_ratings_total' in the fields parameter
      final url =
          'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&fields=name,geometry,address_components,formatted_address,vicinity,website,photos,rating,user_ratings_total&key=$apiKey';

      final response = await _dio.get(url);

      if (response.statusCode == 200) {
        final data = response.data;

        // Log the first part of the response
        print(
            'Place Details response: ${data.toString().substring(0, data.toString().length > 100 ? 100 : data.toString().length)}...');

        if (data['status'] == 'OK' && data['result'] != null) {
          final result = data['result'];

          // Extract coordinates
          if (result['geometry'] != null &&
              result['geometry']['location'] != null) {
            final location = result['geometry']['location'];
            final double lat = location['lat'] ?? 0.0;
            final double lng = location['lng'] ?? 0.0;

            // Extract address components
            String? formattedAddress = result['formatted_address'];
            String? vicinity = result['vicinity']; // Simplified address
            String? city;
            String? state;
            String? country;
            String? zipCode;

            if (result['address_components'] != null) {
              // Process address components
              for (var component in result['address_components']) {
                if (component['types'] != null) {
                  List<dynamic> types = component['types'];

                  if (types.contains('locality')) {
                    city = component['long_name'];
                  } else if (types.contains('administrative_area_level_1')) {
                    state =
                        component['short_name']; // Using abbreviation for state
                  } else if (types.contains('country')) {
                    country = component['long_name'];
                  } else if (types.contains('postal_code')) {
                    zipCode = component['long_name'];
                  }
                }
              }
            }

            // Get the name of the place
            String? name = result['name'];

            // Get the website URL if available
            String? websiteUrl = result['website'];
            if (websiteUrl != null) {
              print('Found website URL for place: $websiteUrl');
            }

            // Get rating and userRatingCount
            final double? rating = (result['rating'] as num?)?.toDouble();
            final int? userRatingCount = result['user_ratings_total'] as int?;

            // Get the first photo reference if available
            String? photoReference;
            if (result['photos'] != null &&
                (result['photos'] as List).isNotEmpty) {
              photoReference = result['photos'][0]['photo_reference'];
            }

            // If we have a photo reference, create a photo URL
            String? photoUrl;
            if (photoReference != null) {
              photoUrl =
                  'https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=$photoReference&key=$apiKey';
              print(
                  'Generated photo URL for place: ${photoUrl.substring(0, photoUrl.length > 50 ? 50 : photoUrl.length)}...');
            }

            // Create location object with all available details
            final locationObj = Location(
              latitude: lat,
              longitude: lng,
              address: formattedAddress ?? vicinity,
              city: city,
              state: state,
              country: country,
              zipCode: zipCode,
              displayName: name,
              placeId: placeId, // Save the place ID
              photoUrl: photoUrl, // Save the photo URL
              website: websiteUrl, // Save the website URL directly
              rating: rating, // ADDED
              userRatingCount: userRatingCount, // ADDED
            );

            // 2. Store successful result in cache before returning
            _placeDetailsCache[placeId] = locationObj;
            print('📍 PLACE DETAILS CACHE STORED for Place ID: $placeId');
            return locationObj;
          }
        } else {
          // Don't cache API errors like NOT_FOUND, let it retry next time
          print(
              'Error in API response: ${data['status']} for Place ID: $placeId');
        }
      } else {
        // Don't cache network errors
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
      // Don't cache exceptions
      print('Error getting place details for Place ID $placeId: $e');
      print('Stack trace: $s');
    }

    // Return default location if API call failed or returned error status
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
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': apiKey,
              'X-Goog-FieldMask':
                  'places.id,places.displayName,places.formattedAddress,places.location'
            },
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

        final geocodeResponse = await http.get(geocodeUrl);

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
                final location = await getPlaceDetails(placeId);
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

      final response = await http.get(url);

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

      final response = await _dio.get(
        url,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': apiKey,
            'X-Goog-FieldMask': 'photos,displayName'
          },
        ),
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
          // Get the first photo - each photo has a name field in Places API (New)
          // The name format is 'places/PLACE_ID/photos/PHOTO_REFERENCE'
          final photoResource = data['photos'][0]['name'];
          print('🔍 PLACE IMAGE: Found photo resource: $photoResource');

          // Construct the photo URL using Places API (New) format
          final photoUrl =
              'https://places.googleapis.com/v1/$photoResource/media?maxWidthPx=$maxWidth&maxHeightPx=$maxHeight&key=$apiKey';
          print('🔍 PLACE IMAGE: Photo URL constructed successfully');

          return photoUrl;
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
        'id,displayName,formattedAddress,addressComponents,location,websiteUri,nationalPhoneNumber,regularOpeningHours,currentOpeningHours,businessStatus,reservable,parkingOptions,editorialSummary,rating,userRatingCount,priceLevel,photos';

    final url = 'https://places.googleapis.com/v1/places/$placeId';

    print('📍 PLACES DETAILS (v1): Requesting details for Place ID: $placeId');
    print(
        '📍 PLACES DETAILS (v1): URL: ${url.replaceAll(apiKey, "<API_KEY>")}');
    print('📍 PLACES DETAILS (v1): FieldMask: $fieldMask');

    try {
      final response = await _dio.get(
        url,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': apiKey,
            'X-Goog-FieldMask': fieldMask,
          },
          // Set a reasonable timeout
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
      final response = await http.get(Uri.parse(url));
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
      final response = await http.get(Uri.parse(url));

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
}
