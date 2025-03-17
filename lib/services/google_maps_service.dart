import 'dart:async';
import 'package:flutter/material.dart';
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
  Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    if (query.isEmpty) {
      return [];
    }
    
    try {
      // Get location for better results
      Position? position;
      try {
        position = await getCurrentLocation();
      } catch (e) {
        // Continue without position if we can't get it
        print('Unable to get current position: $e');
      }
      
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
                'placeId': placePrediction['placeId'] ?? '',
                'description': placePrediction['text']?['text'] ?? '',
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
  
  /// Get place details by placeId
  Future<Location> getPlaceDetails(String placeId) async {
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
        
        // Debug data received from Places API
        print('📍 PLACES API RESPONSE: $data');
        
        // Extract place name - the displayName should contain the actual business name
        String? placeName;
        if (data['displayName'] != null && data['displayName']['text'] != null) {
          placeName = data['displayName']['text'];
          print('📍 FOUND BUSINESS NAME: $placeName');
        } else {
          print('📍 NO DISPLAY NAME FOUND IN RESPONSE');
        }
        
        // Extract coordinates
        final location = data['location'];
        final lat = location?['latitude'] ?? 0.0;
        final lng = location?['longitude'] ?? 0.0;
        
        // Extract address components
        String? address = data['formattedAddress'];
        String? city, state, country, zipCode;
        
        if (data['addressComponents'] != null) {
          for (var component in data['addressComponents']) {
            List<dynamic> types = component['types'] ?? [];
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
          displayName: placeName,
        );
      }
      
      print('📍 NO VALID RESPONSE FROM PLACES API');
      // If we couldn't get any valid place information, return a minimal location with coordinates
      return Location(
        latitude: 0.0, 
        longitude: 0.0,
        address: 'Unknown location',
        displayName: 'Unknown Location',
      );
    } catch (e) {
      print('Error getting place details: $e');
      
      // Even in case of error, return a basic location with coordinates
      return Location(
        latitude: 0.0, 
        longitude: 0.0,
        address: 'Unknown location',
        displayName: 'Unknown Location',
      );
    }
  }
  
  /// Find place details using Google Places API via coordinates
  Future<Map<String, dynamic>?> findPlaceDetails(double latitude, double longitude) async {
    try {
      // Try using the Places API first (better business info)
      try {
        print('📍 Looking up place at coordinates using Places API v1');
        
        // First try to get a Place ID using reverse geocoding
        final geocodeUrl = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json?latlng=$latitude,$longitude&key=$apiKey'
        );
        
        final geocodeResponse = await http.get(geocodeUrl);
        
        if (geocodeResponse.statusCode == 200) {
          final geocodeData = json.decode(geocodeResponse.body);
          print('📍 Geocoding response: $geocodeData');
          
          if (geocodeData['status'] == 'OK' && geocodeData['results'] != null && geocodeData['results'].isNotEmpty) {
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
                  print('📍 Successfully retrieved establishment name: ${location.displayName}');
                  return {
                    'placeId': placeId,
                    'name': location.displayName!,
                    'address': location.address ?? '',
                    'latitude': latitude,
                    'longitude': longitude,
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
              
              return {
                'placeId': placeResult['place_id'] ?? '',
                'name': placeName,
                'address': placeResult['formatted_address'] ?? '',
                'latitude': latitude,
                'longitude': longitude,
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
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=$latitude,$longitude&key=$apiKey'
      );
      
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' && data['results'] != null && data['results'].isNotEmpty) {
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
              print('📍 REVERSE GEOCODING FALLBACK - Using address part: $placeName');
            } else {
              print('📍 REVERSE GEOCODING FALLBACK - No name or address found');
            }
            
            return {
              'placeId': placeResult['place_id'] ?? '',
              'name': placeName,
              'address': placeResult['formatted_address'] ?? '',
              'latitude': latitude,
              'longitude': longitude,
              'types': placeResult['types'] as List? ?? []
            };
          }
        }
      }
      
      // If we couldn't get any valid place information, return a minimal result with coordinates
      return {
        'placeId': '',
        'name': 'Selected Location',
        'address': 'Location at ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
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
        'address': 'Location at ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
        'latitude': latitude,
        'longitude': longitude,
        'types': []
      };
    }
  }
  
  /// More detailed place search at coordinates
  Future<Map<String, dynamic>?> findPlaceAtCoordinates(double latitude, double longitude) async {
    try {
      // Try using reverse geocoding
      final geocodeResponse = await _dio.get(
        'https://maps.googleapis.com/maps/api/geocode/json',
        queryParameters: {
          'latlng': '$latitude,$longitude',
          'key': apiKey,
          'radius': '50' // Increase search radius to 50 meters
        }
      );
      
      if (geocodeResponse.statusCode == 200 && 
          geocodeResponse.data?['status'] == 'OK' &&
          geocodeResponse.data?['results'] != null) {
        
        final List<dynamic> geocodeResults = (geocodeResponse.data?['results'] as List?) ?? [];
        
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
          // Create a clean result object
          final result = {
            'placeId': placeResult['place_id'] ?? '',
            'name': _extractPlaceName(placeResult),
            'address': placeResult['formatted_address'] ?? '',
            'latitude': placeResult['geometry']?['location']?['lat'] ?? latitude,
            'longitude': placeResult['geometry']?['location']?['lng'] ?? longitude,
            'types': placeResult['types'] as List? ?? []
          };
          
          return result;
        }
      }
      
      // If we couldn't get any valid place information, return a minimal result with coordinates
      return {
        'placeId': '',
        'name': 'Selected Location',
        'address': 'Location at ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
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
        'address': 'Location at ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
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
      return result['address_components'][0]['long_name'] as String? ?? 'Unknown Place';
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
  
  /// Get place details from geocoding service
  Future<Location> getAddressFromLatLng(LatLng position) async {
    try {
      final placeDetails = await findPlaceDetails(
        position.latitude,
        position.longitude
      );
      
      if (placeDetails != null) {
        return Location(
          latitude: placeDetails['latitude'] as double,
          longitude: placeDetails['longitude'] as double,
          address: placeDetails['address'] as String?,
          displayName: placeDetails['name'] as String?,
        );
      }
      
      // If we couldn't get details, return a basic location
      return Location(
        latitude: position.latitude,
        longitude: position.longitude,
        address: 'Location at ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
        displayName: 'Selected Location',
      );
    } catch (e) {
      print('Error getting address: $e');
      
      // Even in case of error, return a basic location to avoid null issues
      return Location(
        latitude: position.latitude,
        longitude: position.longitude,
        address: 'Location at ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
        displayName: 'Selected Location',
      );
    }
  }
  
  /// Generate a static map image URL
  String getStaticMapUrl(double latitude, double longitude, {int zoom = 14, int width = 600, int height = 300}) {
    return 'https://maps.googleapis.com/maps/api/staticmap?center=$latitude,$longitude&zoom=$zoom&size=${width}x$height&markers=color:red%7C$latitude,$longitude&key=$apiKey';
  }
  
  /// Alias for static map URL
  String getStaticMapImageUrl(double latitude, double longitude, {int zoom = 15, int width = 600, int height = 300}) {
    return getStaticMapUrl(latitude, longitude, zoom: zoom, width: width, height: height);
  }
  
  /// Generate directions URL
  String getDirectionsUrl(double destLat, double destLng, {double? originLat, double? originLng}) {
    if (originLat != null && originLng != null) {
      return 'https://www.google.com/maps/dir/?api=1&origin=$originLat,$originLng&destination=$destLat,$destLng';
    } else {
      return 'https://www.google.com/maps/dir/?api=1&destination=$destLat,$destLng';
    }
  }
  
  /// Get directions URL between two coordinates (legacy method signature for compatibility)
  String getDirectionsUrlFromCoordinates(double startLat, double startLng, double endLat, double endLng) {
    return getDirectionsUrl(endLat, endLng, originLat: startLat, originLng: startLng);
  }
}