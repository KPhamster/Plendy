import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import '../models/experience.dart';
import '../config/api_secrets.dart';

class MapService {
  static final MapService _instance = MapService._internal();
  
  factory MapService() {
    return _instance;
  }
  
  MapService._internal();
  
  final Dio _dio = Dio();
  
  // Get the API key securely from ApiSecrets
  static String get apiKey => ApiSecrets.googleMapsApiKey;
  
  // Get current location after checking/requesting permissions
  Future<Position?> getCurrentLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return null;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return null;
    }
    
    if (permission == LocationPermission.whileInUse || 
        permission == LocationPermission.always) {
      try {
        return await Geolocator.getCurrentPosition();
      } catch (e) {
        print('Error getting current location: $e');
        return null;
      }
    }
    
    return null;
  }
  
  // Search for places using Google Places API
  Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    if (query.isEmpty) {
      return [];
    }
    
    try {
      // Get location for better results
      Position? position = await getCurrentLocation();
      
      // Prepare request body
      Map<String, dynamic> requestBody = {"input": query};
      
      // Add location bias if we have position
      if (position != null) {
        requestBody["locationBias"] = {
          "circle": {
            "center": {
              "latitude": position.latitude,
              "longitude": position.longitude
            },
            "radius": 50000.0 // 50km radius
          }
        };
      }
      
      // Call Google Places Autocomplete API
      final response = await _dio.post(
        'https://places.googleapis.com/v1/places:autocomplete',
        data: requestBody,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': apiKey,
            'X-Goog-FieldMask':
                'suggestions.placePrediction.place,suggestions.placePrediction.placeId,suggestions.placePrediction.text'
          },
        ),
      );
      
      if (response.statusCode == 200) {
        final data = response.data;
        List<Map<String, dynamic>> results = [];
        
        if (data['suggestions'] != null) {
          for (var suggestion in data['suggestions']) {
            if (suggestion['placePrediction'] != null) {
              final placePrediction = suggestion['placePrediction'];
              results.add({
                'placeId': placePrediction['placeId'],
                'description': placePrediction['text']['text'],
                'place': placePrediction['place']
              });
            }
          }
        }
        
        return results;
      }
      
      return [];
    } catch (e) {
      print('Error searching places: $e');
      return [];
    }
  }
  
  // Get place details by placeId
  Future<Location?> getPlaceDetails(String placeId) async {
    try {
      // Call Google Places Details API
      final response = await _dio.get(
        'https://places.googleapis.com/v1/places/$placeId',
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': apiKey,
            'X-Goog-FieldMask':
                'id,displayName,formattedAddress,location,addressComponents'
          },
        ),
      );
      
      if (response.statusCode == 200) {
        final data = response.data;
        
        // Extract coordinates
        final location = data['location'];
        final lat = location['latitude'];
        final lng = location['longitude'];
        
        // Extract address components
        String? address = data['formattedAddress'];
        String? city, state, country, zipCode;
        
        if (data['addressComponents'] != null) {
          for (var component in data['addressComponents']) {
            List<dynamic> types = component['types'];
            if (types.contains('locality')) {
              city = component['longText'];
            } else if (types.contains('administrative_area_level_1')) {
              state = component['shortText']; // Using short name for state
            } else if (types.contains('country')) {
              country = component['longText'];
            } else if (types.contains('postal_code')) {
              zipCode = component['longText'];
            }
          }
        }
        
        return Location(
          latitude: lat,
          longitude: lng,
          address: address,
          city: city,
          state: state,
          country: country,
          zipCode: zipCode,
        );
      }
      
      return null;
    } catch (e) {
      print('Error getting place details: $e');
      return null;
    }
  }
  
  // Get static map image URL for a location
  String getStaticMapImageUrl(double latitude, double longitude, {int zoom = 15, int width = 600, int height = 300}) {
    return 'https://maps.googleapis.com/maps/api/staticmap?center=$latitude,$longitude&zoom=$zoom&size=${width}x$height&markers=color:red%7C$latitude,$longitude&key=$apiKey';
  }
  
  // Generate directions URL
  String getDirectionsUrl(double destLat, double destLng, {double? originLat, double? originLng}) {
    if (originLat != null && originLng != null) {
      return 'https://www.google.com/maps/dir/?api=1&origin=$originLat,$originLng&destination=$destLat,$destLng';
    } else {
      return 'https://www.google.com/maps/dir/?api=1&destination=$destLat,$destLng';
    }
  }
  
  // Generate static map URL for a location (legacy method name for compatibility)
  String getStaticMapUrl(double latitude, double longitude, {int zoom = 15, int width = 600, int height = 300}) {
    return getStaticMapImageUrl(latitude, longitude, zoom: zoom, width: width, height: height);
  }
  
  // Get directions URL between two coordinates (legacy method signature for compatibility)
  String getDirectionsUrlFromCoordinates(double startLat, double startLng, double endLat, double endLng) {
    return getDirectionsUrl(endLat, endLng, originLat: startLat, originLng: startLng);
  }
  
  // Find place directly at the tapped coordinates
  Future<Map<String, dynamic>?> findPlaceAtCoordinates(double latitude, double longitude) async {
    print('API REQUEST: Searching for place at coordinates: $latitude, $longitude');
    // Debug the API key (first 8 chars only for security)
    print('API REQUEST: Using API key starting with: ${apiKey.substring(0, 8)}...');
    
    try {
      // Try using reverse geocoding first - this is more reliable
      print('API REQUEST: Using reverse geocoding API');
      
      final geocodeResponse = await _dio.get(
        'https://maps.googleapis.com/maps/api/geocode/json',
        queryParameters: {
          'latlng': '$latitude,$longitude',
          'key': apiKey
        }
      );
      
      print('GEOCODE RESPONSE: Status: ${geocodeResponse.data?['status'] ?? 'Unknown'}');
      print('GEOCODE RESPONSE: Full data: ${geocodeResponse.data}');
      
      if (geocodeResponse.statusCode == 200 && 
          geocodeResponse.data?['status'] == 'OK' &&
          geocodeResponse.data?['results'] != null) {
        
        // Get the results array safely with null checks
        final List<dynamic> geocodeResults = (geocodeResponse.data?['results'] as List?) ?? [];
        print('GEOCODE RESPONSE: Found ${geocodeResults.length} results');
        
        // Look for results with establishment or point_of_interest types
        Map<String, dynamic>? placeResult;
        
        if (geocodeResults.isNotEmpty) {
          for (var result in geocodeResults) {
            print('GEOCODE RESULT: Types: ${result['types']}');
            
            List<dynamic> types = result['types'] as List? ?? [];
            if (types.contains('establishment') || 
                types.contains('point_of_interest') ||
                types.contains('restaurant') ||
                types.contains('store') ||
                types.contains('bakery') ||
                types.contains('cafe')) {
              
              placeResult = result;
              print('GEOCODE RESPONSE: Found establishment: ${result?['formatted_address'] ?? 'No address available'}');
              break;
            }
          }
          
          // If we didn't find an establishment, use the most specific result (usually the first one)
          if (placeResult == null && geocodeResults.isNotEmpty) {
            placeResult = geocodeResults[0];
            print('GEOCODE RESPONSE: Using most specific result: ${placeResult?['formatted_address'] ?? 'No address available'}');
          }
        }
        
        if (placeResult != null) {
          // Create a clean result object
          final result = {
            'placeId': placeResult['place_id'] ?? '',
            'name': _extractPlaceName(placeResult),
            'address': placeResult['formatted_address'] ?? '',
            'latitude': placeResult['geometry']?['location']?['lat'] ?? latitude,
            'longitude': placeResult['geometry']?['location']?['lng'] ?? longitude,
            'types': placeResult['types'] as List? ?? []
          };
          
          print('GEOCODE RESPONSE: Final result: $result');
          return result;
        }
      } else {
        print('GEOCODE RESPONSE: No results or error status: ${geocodeResponse.data['status']}');
      }
      
      return null;
    } catch (e) {
      print('API ERROR: Error finding place at coordinates: $e');
      return null;
    }
  }
  
  // Helper method to extract a place name from geocoding result
  String _extractPlaceName(Map<String, dynamic> geocodeResult) {
    // First check if there's a name in the result (rare for geocoding)
    if (geocodeResult.containsKey('name') && geocodeResult['name'] != null) {
      return geocodeResult['name'] as String;
    }
    
    // Try to get the most specific component (first component is usually the place name)
    if (geocodeResult['address_components'] != null && 
        (geocodeResult['address_components'] as List).isNotEmpty) {
      
      // For establishments, the first component is usually the most specific (name of place)
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
}