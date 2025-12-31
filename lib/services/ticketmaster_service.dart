import 'package:dio/dio.dart';
import '../config/api_keys.dart';

/// Result of a Ticketmaster event search
class TicketmasterEventResult {
  final String id;
  final String name;
  final String? url;
  final DateTime? startDateTime;
  final String? venueName;
  final String? imageUrl;

  TicketmasterEventResult({
    required this.id,
    required this.name,
    this.url,
    this.startDateTime,
    this.venueName,
    this.imageUrl,
  });

  factory TicketmasterEventResult.fromJson(Map<String, dynamic> json) {
    // Parse start date/time
    DateTime? startDateTime;
    final dates = json['dates'] as Map<String, dynamic>?;
    if (dates != null) {
      final start = dates['start'] as Map<String, dynamic>?;
      if (start != null) {
        final dateTime = start['dateTime'] as String?;
        if (dateTime != null) {
          startDateTime = DateTime.tryParse(dateTime);
        } else {
          // Try to parse localDate + localTime
          final localDate = start['localDate'] as String?;
          final localTime = start['localTime'] as String?;
          if (localDate != null) {
            if (localTime != null) {
              startDateTime = DateTime.tryParse('${localDate}T$localTime');
            } else {
              startDateTime = DateTime.tryParse(localDate);
            }
          }
        }
      }
    }

    // Get venue name
    String? venueName;
    final embedded = json['_embedded'] as Map<String, dynamic>?;
    if (embedded != null) {
      final venues = embedded['venues'] as List<dynamic>?;
      if (venues != null && venues.isNotEmpty) {
        venueName = venues[0]['name'] as String?;
      }
    }

    // Get image URL (prefer larger images)
    String? imageUrl;
    final images = json['images'] as List<dynamic>?;
    if (images != null && images.isNotEmpty) {
      // Sort by width descending and pick the largest
      final sortedImages = List<Map<String, dynamic>>.from(
        images.map((e) => e as Map<String, dynamic>),
      )..sort((a, b) {
          final aWidth = (a['width'] as num?) ?? 0;
          final bWidth = (b['width'] as num?) ?? 0;
          return bWidth.compareTo(aWidth);
        });
      imageUrl = sortedImages.first['url'] as String?;
    }

    return TicketmasterEventResult(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String?,
      startDateTime: startDateTime,
      venueName: venueName,
      imageUrl: imageUrl,
    );
  }
}

/// Service for interacting with Ticketmaster Discovery API
class TicketmasterService {
  static const String _baseUrl = 'https://app.ticketmaster.com/discovery/v2';
  
  final Dio _dio;
  
  TicketmasterService() : _dio = Dio();

  /// Get API key from config
  String get _apiKey => ApiKeys.ticketmasterApiKey;

  /// Search for events by keyword and optional filters
  /// 
  /// [keyword] - Search term (event name, artist, etc.)
  /// [startDateTime] - Filter events starting on or after this date (ISO 8601 format)
  /// [endDateTime] - Filter events starting on or before this date (ISO 8601 format)
  /// [city] - Filter by city name
  /// [stateCode] - Filter by state/province code (e.g., 'CA', 'NY')
  /// [countryCode] - Filter by country code (e.g., 'US', 'CA')
  /// [latLong] - Filter by latitude,longitude (e.g., '34.0522,-118.2437')
  /// [radius] - Radius in miles to search around latLong (default 50)
  Future<List<TicketmasterEventResult>> searchEvents({
    required String keyword,
    DateTime? startDateTime,
    DateTime? endDateTime,
    String? city,
    String? stateCode,
    String? countryCode,
    String? latLong,
    int? radius,
    int size = 5,
  }) async {
    if (_apiKey.isEmpty || _apiKey.contains('YOUR_')) {
      print('⚠️ Ticketmaster API key not configured');
      return [];
    }

    try {
      final queryParams = <String, dynamic>{
        'apikey': _apiKey,
        'keyword': keyword,
        'size': size,
        'sort': 'relevance,desc',
      };

      if (startDateTime != null) {
        // Format: 2024-01-01T00:00:00Z
        queryParams['startDateTime'] = startDateTime.toUtc().toIso8601String().split('.')[0] + 'Z';
      }
      if (endDateTime != null) {
        queryParams['endDateTime'] = endDateTime.toUtc().toIso8601String().split('.')[0] + 'Z';
      }
      if (city != null && city.isNotEmpty) {
        queryParams['city'] = city;
      }
      if (stateCode != null && stateCode.isNotEmpty) {
        queryParams['stateCode'] = stateCode;
      }
      if (countryCode != null && countryCode.isNotEmpty) {
        queryParams['countryCode'] = countryCode;
      }
      if (latLong != null && latLong.isNotEmpty) {
        queryParams['latlong'] = latLong;
        queryParams['radius'] = radius ?? 50;
        queryParams['unit'] = 'miles';
      }

      print('🎫 Searching Ticketmaster for: $keyword');
      
      final response = await _dio.get(
        '$_baseUrl/events.json',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final embedded = data['_embedded'] as Map<String, dynamic>?;
        
        if (embedded == null) {
          print('🎫 No Ticketmaster events found for: $keyword');
          return [];
        }

        final events = embedded['events'] as List<dynamic>?;
        if (events == null || events.isEmpty) {
          print('🎫 No Ticketmaster events found for: $keyword');
          return [];
        }

        final results = events
            .map((e) => TicketmasterEventResult.fromJson(e as Map<String, dynamic>))
            .toList();
        
        print('🎫 Found ${results.length} Ticketmaster events for: $keyword');
        return results;
      } else {
        print('🎫 Ticketmaster API error: ${response.statusCode}');
        return [];
      }
    } on DioException catch (e) {
      print('🎫 Ticketmaster API error: ${e.message}');
      if (e.response?.statusCode == 401) {
        print('🎫 Invalid Ticketmaster API key');
      }
      return [];
    } catch (e) {
      print('🎫 Ticketmaster search error: $e');
      return [];
    }
  }

  /// Search for an event by name and date, returning the best match
  /// 
  /// This method attempts to find an event that matches both the name and date
  /// as closely as possible.
  Future<TicketmasterEventResult?> findEventByNameAndDate({
    required String eventName,
    required DateTime eventDate,
    String? city,
    String? stateCode,
    String? countryCode,
    double? latitude,
    double? longitude,
  }) async {
    // Create a date window around the event date (±3 days for flexibility)
    final startWindow = eventDate.subtract(const Duration(days: 3));
    final endWindow = eventDate.add(const Duration(days: 3));

    String? latLong;
    if (latitude != null && longitude != null) {
      latLong = '$latitude,$longitude';
    }

    final results = await searchEvents(
      keyword: eventName,
      startDateTime: startWindow,
      endDateTime: endWindow,
      city: city,
      stateCode: stateCode,
      countryCode: countryCode,
      latLong: latLong,
      radius: 100, // 100 mile radius for flexibility
      size: 10,
    );

    if (results.isEmpty) {
      // Try again without date filter (event might have different dates)
      final fallbackResults = await searchEvents(
        keyword: eventName,
        city: city,
        stateCode: stateCode,
        countryCode: countryCode,
        latLong: latLong,
        radius: 100,
        size: 5,
      );
      
      if (fallbackResults.isEmpty) {
        return null;
      }
      
      // Return the first (most relevant) result
      return fallbackResults.first;
    }

    // Find the best match by date proximity
    TicketmasterEventResult? bestMatch;
    Duration? closestDiff;

    for (final result in results) {
      if (result.startDateTime != null) {
        final diff = result.startDateTime!.difference(eventDate).abs();
        if (closestDiff == null || diff < closestDiff) {
          closestDiff = diff;
          bestMatch = result;
        }
      }
    }

    // If no result with date, just return the first (most relevant by API)
    return bestMatch ?? results.first;
  }
}

