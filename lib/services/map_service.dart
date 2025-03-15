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
}
