import 'package:dio/dio.dart';
import '../config/api_keys.dart';

/// Detailed venue information from Ticketmaster
class TicketmasterVenue {
  final String? id;
  final String? name;
  final String? address;
  final String? city;
  final String? state;
  final String? stateCode;
  final String? country;
  final String? countryCode;
  final String? postalCode;
  final double? latitude;
  final double? longitude;
  final String? timezone;

  TicketmasterVenue({
    this.id,
    this.name,
    this.address,
    this.city,
    this.state,
    this.stateCode,
    this.country,
    this.countryCode,
    this.postalCode,
    this.latitude,
    this.longitude,
    this.timezone,
  });

  /// Get a formatted full address
  String? get fullAddress {
    final parts = <String>[];
    if (address != null && address!.isNotEmpty) parts.add(address!);
    if (city != null && city!.isNotEmpty) parts.add(city!);
    if (stateCode != null && stateCode!.isNotEmpty) {
      parts.add(stateCode!);
    } else if (state != null && state!.isNotEmpty) {
      parts.add(state!);
    }
    if (postalCode != null && postalCode!.isNotEmpty) parts.add(postalCode!);
    if (countryCode != null && countryCode!.isNotEmpty && countryCode != 'US') {
      parts.add(countryCode!);
    }
    return parts.isNotEmpty ? parts.join(', ') : null;
  }

  factory TicketmasterVenue.fromJson(Map<String, dynamic> json) {
    // Parse location coordinates
    double? latitude;
    double? longitude;
    final location = json['location'] as Map<String, dynamic>?;
    if (location != null) {
      latitude = double.tryParse(location['latitude']?.toString() ?? '');
      longitude = double.tryParse(location['longitude']?.toString() ?? '');
    }

    // Parse city
    String? city;
    final cityData = json['city'] as Map<String, dynamic>?;
    if (cityData != null) {
      city = cityData['name'] as String?;
    }

    // Parse state
    String? state;
    String? stateCode;
    final stateData = json['state'] as Map<String, dynamic>?;
    if (stateData != null) {
      state = stateData['name'] as String?;
      stateCode = stateData['stateCode'] as String?;
    }

    // Parse country
    String? country;
    String? countryCode;
    final countryData = json['country'] as Map<String, dynamic>?;
    if (countryData != null) {
      country = countryData['name'] as String?;
      countryCode = countryData['countryCode'] as String?;
    }

    // Parse address
    String? address;
    final addressData = json['address'] as Map<String, dynamic>?;
    if (addressData != null) {
      address = addressData['line1'] as String?;
    }

    return TicketmasterVenue(
      id: json['id'] as String?,
      name: json['name'] as String?,
      address: address,
      city: city,
      state: state,
      stateCode: stateCode,
      country: country,
      countryCode: countryCode,
      postalCode: json['postalCode'] as String?,
      latitude: latitude,
      longitude: longitude,
      timezone: json['timezone'] as String?,
    );
  }
}

/// Complete event details from Ticketmaster
class TicketmasterEventDetails {
  final String id;
  final String name;
  final String? url;
  final DateTime? startDateTime;
  final DateTime? endDateTime;
  final String? timezone;
  final TicketmasterVenue? venue;
  final String? imageUrl;
  final String? info;
  final String? pleaseNote;
  final List<String> attractions;

  TicketmasterEventDetails({
    required this.id,
    required this.name,
    this.url,
    this.startDateTime,
    this.endDateTime,
    this.timezone,
    this.venue,
    this.imageUrl,
    this.info,
    this.pleaseNote,
    this.attractions = const [],
  });

  factory TicketmasterEventDetails.fromJson(Map<String, dynamic> json) {
    // Parse start date/time
    // IMPORTANT: Prefer localDate + localTime over dateTime (UTC)
    // localDate/localTime represent the event time in the venue's timezone,
    // which is what users expect to see on tickets and at the venue.
    DateTime? startDateTime;
    DateTime? endDateTime;
    String? timezone;
    final dates = json['dates'] as Map<String, dynamic>?;
    if (dates != null) {
      timezone = dates['timezone'] as String?;
      
      final start = dates['start'] as Map<String, dynamic>?;
      if (start != null) {
        // First try localDate + localTime (venue's local time)
        final localDate = start['localDate'] as String?;
        final localTime = start['localTime'] as String?;
        if (localDate != null) {
          if (localTime != null) {
            // Parse as local time (no 'Z' suffix = local, not UTC)
            startDateTime = DateTime.tryParse('${localDate}T$localTime');
          } else {
            // Only date, no time - default to a reasonable evening time (7 PM)
            startDateTime = DateTime.tryParse(localDate);
            if (startDateTime != null) {
              startDateTime = DateTime(startDateTime.year, startDateTime.month, startDateTime.day, 19, 0);
            }
          }
        }
        
        // Fall back to UTC dateTime only if local fields aren't available
        if (startDateTime == null) {
          final dateTime = start['dateTime'] as String?;
          if (dateTime != null) {
            // This is UTC time - convert to local
            final utcTime = DateTime.tryParse(dateTime);
            if (utcTime != null) {
              startDateTime = utcTime.toLocal();
            }
          }
        }
      }

      final end = dates['end'] as Map<String, dynamic>?;
      if (end != null) {
        // First try localDate + localTime
        final localDate = end['localDate'] as String?;
        final localTime = end['localTime'] as String?;
        if (localDate != null) {
          if (localTime != null) {
            endDateTime = DateTime.tryParse('${localDate}T$localTime');
          } else {
            endDateTime = DateTime.tryParse(localDate);
          }
        }
        
        // Fall back to UTC dateTime
        if (endDateTime == null) {
          final dateTime = end['dateTime'] as String?;
          if (dateTime != null) {
            final utcTime = DateTime.tryParse(dateTime);
            if (utcTime != null) {
              endDateTime = utcTime.toLocal();
            }
          }
        }
      }
    }

    // Get venue
    TicketmasterVenue? venue;
    final embedded = json['_embedded'] as Map<String, dynamic>?;
    if (embedded != null) {
      final venues = embedded['venues'] as List<dynamic>?;
      if (venues != null && venues.isNotEmpty) {
        venue = TicketmasterVenue.fromJson(venues[0] as Map<String, dynamic>);
      }
    }

    // Get attractions list
    List<String> attractions = [];
    if (embedded != null) {
      final attractionsList = embedded['attractions'] as List<dynamic>?;
      if (attractionsList != null) {
        attractions = attractionsList
            .map((a) => (a as Map<String, dynamic>)['name'] as String?)
            .whereType<String>()
            .toList();
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

    return TicketmasterEventDetails(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String?,
      startDateTime: startDateTime,
      endDateTime: endDateTime,
      timezone: timezone,
      venue: venue,
      imageUrl: imageUrl,
      info: json['info'] as String?,
      pleaseNote: json['pleaseNote'] as String?,
      attractions: attractions,
    );
  }
}

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
    // Parse start date/time - prefer local time over UTC
    DateTime? startDateTime;
    final dates = json['dates'] as Map<String, dynamic>?;
    if (dates != null) {
      final start = dates['start'] as Map<String, dynamic>?;
      if (start != null) {
        // First try localDate + localTime (venue's local time)
        final localDate = start['localDate'] as String?;
        final localTime = start['localTime'] as String?;
        if (localDate != null) {
          if (localTime != null) {
            startDateTime = DateTime.tryParse('${localDate}T$localTime');
          } else {
            startDateTime = DateTime.tryParse(localDate);
            if (startDateTime != null) {
              startDateTime = DateTime(startDateTime.year, startDateTime.month, startDateTime.day, 19, 0);
            }
          }
        }
        
        // Fall back to UTC dateTime
        if (startDateTime == null) {
          final dateTime = start['dateTime'] as String?;
          if (dateTime != null) {
            final utcTime = DateTime.tryParse(dateTime);
            if (utcTime != null) {
              startDateTime = utcTime.toLocal();
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

  /// Extract event ID from a Ticketmaster URL
  /// 
  /// Supports various URL formats:
  /// - https://www.ticketmaster.com/event/1234567890ABCDEF
  /// - https://www.ticketmaster.com/some-event-name/event/1234567890ABCDEF
  /// - https://ticketmaster.com/artist-name-city-date/event/1234567890ABCDEF
  /// - https://www.ticketmaster.co.uk/event/1234567890ABCDEF
  static String? extractEventIdFromUrl(String url) {
    if (url.isEmpty) return null;

    try {
      // Pattern to match event ID in various Ticketmaster URL formats
      // Event IDs can vary in length (typically 7-20 alphanumeric characters)
      final patterns = [
        // /event/EVENTID at the end (with optional query string, hash, or end of string)
        RegExp(r'/event/([A-Za-z0-9_-]{5,25})(?:\?|$|#)', caseSensitive: false),
        // /event/EVENTID in the middle (followed by /)
        RegExp(r'/event/([A-Za-z0-9_-]{5,25})/', caseSensitive: false),
        // eventId= query parameter
        RegExp(r'[?&]eventId=([A-Za-z0-9_-]{5,25})(?:&|$)', caseSensitive: false),
      ];

      for (final pattern in patterns) {
        final match = pattern.firstMatch(url);
        if (match != null) {
          final eventId = match.group(1);
          if (eventId != null && eventId.isNotEmpty) {
            print('🎫 TICKETMASTER: Extracted event ID: $eventId from URL');
            return eventId;
          }
        }
      }

      print('🎫 TICKETMASTER: Could not extract event ID from URL: $url');
      return null;
    } catch (e) {
      print('🎫 TICKETMASTER: Error extracting event ID: $e');
      return null;
    }
  }

  /// Check if a URL is a Ticketmaster URL
  static bool isTicketmasterUrl(String url) {
    if (url.isEmpty) return false;
    final lower = url.toLowerCase();
    return lower.contains('ticketmaster.com') ||
           lower.contains('ticketmaster.co.uk') ||
           lower.contains('ticketmaster.ca') ||
           lower.contains('ticketmaster.com.au') ||
           lower.contains('ticketmaster.de') ||
           lower.contains('ticketmaster.es') ||
           lower.contains('ticketmaster.fr') ||
           lower.contains('ticketmaster.ie') ||
           lower.contains('ticketmaster.nl') ||
           lower.contains('ticketmaster.be') ||
           lower.contains('ticketmaster.at') ||
           lower.contains('ticketmaster.ch') ||
           lower.contains('livenation.com'); // LiveNation often redirects to Ticketmaster
  }

  /// Get full event details by event ID
  /// 
  /// Returns comprehensive event information including venue location,
  /// date/time, and attractions.
  Future<TicketmasterEventDetails?> getEventById(String eventId) async {
    if (_apiKey.isEmpty || _apiKey.contains('YOUR_')) {
      print('⚠️ Ticketmaster API key not configured');
      return null;
    }

    try {
      print('🎫 TICKETMASTER: Fetching event details for ID: $eventId');
      
      final response = await _dio.get(
        '$_baseUrl/events/$eventId.json',
        queryParameters: {
          'apikey': _apiKey,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final details = TicketmasterEventDetails.fromJson(data);
        
        print('🎫 TICKETMASTER: Found event: ${details.name}');
        if (details.venue != null) {
          final venue = details.venue!;
          print('🎫 TICKETMASTER: Venue: ${venue.name}');
          print('🎫 TICKETMASTER: Venue address: ${venue.fullAddress}');
          print('🎫 TICKETMASTER: Venue city: ${venue.city}, state: ${venue.state}');
          if (venue.latitude != null && venue.longitude != null) {
            print('🎫 TICKETMASTER: Venue location: ${venue.latitude}, ${venue.longitude}');
          } else {
            print('🎫 TICKETMASTER: ⚠️ Venue has no lat/lng coordinates');
          }
        } else {
          print('🎫 TICKETMASTER: ⚠️ No venue data in API response');
        }
        
        return details;
      } else {
        print('🎫 TICKETMASTER: API error: ${response.statusCode}');
        return null;
      }
    } on DioException catch (e) {
      print('🎫 TICKETMASTER: API error: ${e.message}');
      if (e.response?.statusCode == 401) {
        print('🎫 TICKETMASTER: Invalid API key');
      } else if (e.response?.statusCode == 404) {
        print('🎫 TICKETMASTER: Event not found');
      }
      return null;
    } catch (e) {
      print('🎫 TICKETMASTER: Error fetching event: $e');
      return null;
    }
  }

  /// Get event details from a Ticketmaster URL
  /// 
  /// Extracts the event ID from the URL and fetches full details.
  /// If direct ID lookup fails, falls back to searching by event name/date/city
  /// extracted from the URL slug.
  Future<TicketmasterEventDetails?> getEventFromUrl(String url) async {
    final eventId = extractEventIdFromUrl(url);
    if (eventId == null) {
      print('🎫 TICKETMASTER: Could not extract event ID from URL');
      return null;
    }
    
    // Step 1: Try direct event ID lookup
    TicketmasterEventDetails? details = await getEventById(eventId);
    
    // Step 2: If direct lookup failed, try searching by event info from URL
    if (details == null) {
      print('🎫 TICKETMASTER: Direct ID lookup failed, trying search fallback...');
      details = await _searchEventFromUrlFallback(url);
    }
    
    return details;
  }
  
  /// Fallback: Search for event using info extracted from URL slug
  Future<TicketmasterEventDetails?> _searchEventFromUrlFallback(String url) async {
    try {
      // Extract event info from URL
      final urlInfo = _extractEventInfoFromUrl(url);
      if (urlInfo == null) {
        print('🎫 TICKETMASTER SEARCH: Could not extract info from URL');
        return null;
      }
      
      final eventName = urlInfo['eventName'] as String?;
      final city = urlInfo['city'] as String?;
      final state = urlInfo['state'] as String?;
      final date = urlInfo['date'] as DateTime?;
      
      if (eventName == null || eventName.isEmpty) {
        print('🎫 TICKETMASTER SEARCH: No event name extracted');
        return null;
      }
      
      print('🎫 TICKETMASTER SEARCH: Searching for "$eventName" in $city, $state on $date');
      
      // Get state code for API (e.g., "California" -> "CA")
      final stateCode = _getStateCode(state);
      
      // Search for the event
      final searchResults = await searchEvents(
        keyword: eventName,
        city: city,
        stateCode: stateCode,
        startDateTime: date?.subtract(const Duration(days: 1)),
        endDateTime: date?.add(const Duration(days: 1)),
        size: 5,
      );
      
      if (searchResults.isEmpty) {
        print('🎫 TICKETMASTER SEARCH: No results found');
        return null;
      }
      
      // Find best match by name similarity
      TicketmasterEventResult? bestMatch;
      final eventNameLower = eventName.toLowerCase();
      
      for (final result in searchResults) {
        final resultNameLower = result.name.toLowerCase();
        if (resultNameLower.contains(eventNameLower) || 
            eventNameLower.contains(resultNameLower)) {
          bestMatch = result;
          break;
        }
      }
      
      // If no close name match, use first result
      bestMatch ??= searchResults.first;
      
      print('🎫 TICKETMASTER SEARCH: Found match: ${bestMatch.name} (ID: ${bestMatch.id})');
      
      // Fetch full details using the found event ID
      return await getEventById(bestMatch.id);
    } catch (e) {
      print('🎫 TICKETMASTER SEARCH: Error in search fallback: $e');
      return null;
    }
  }
  
  /// Extract event info from Ticketmaster URL slug
  /// URL format: https://www.ticketmaster.com/event-name-city-state-MM-DD-YYYY/event/ID
  Map<String, dynamic>? _extractEventInfoFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      
      // Find the segment before "event"
      String? slug;
      for (int i = 0; i < pathSegments.length; i++) {
        if (pathSegments[i] == 'event' && i > 0) {
          slug = pathSegments[i - 1];
          break;
        }
      }
      
      if (slug == null || slug.isEmpty) {
        return null;
      }
      
      final parts = slug.split('-');
      if (parts.length < 3) {
        return null;
      }
      
      // Try to extract date from the end (MM-DD-YYYY pattern)
      DateTime? eventDate;
      int dateStartIndex = parts.length;
      
      if (parts.length >= 3) {
        // Check for date pattern at the end
        final lastThree = parts.sublist(parts.length - 3);
        final month = int.tryParse(lastThree[0]);
        final day = int.tryParse(lastThree[1]);
        final year = int.tryParse(lastThree[2]);
        
        if (month != null && day != null && year != null &&
            month >= 1 && month <= 12 &&
            day >= 1 && day <= 31 &&
            year >= 2020 && year <= 2100) {
          eventDate = DateTime(year, month, day);
          dateStartIndex = parts.length - 3;
        }
      }
      
      // Find city and state (usually last 2 elements before date, or at end)
      String? city;
      String? state;
      
      if (dateStartIndex >= 2) {
        final potentialState = parts[dateStartIndex - 1];
        if (_isLikelyUSState(potentialState)) {
          state = _capitalizeWord(potentialState);
          if (dateStartIndex >= 2) {
            city = _capitalizeWord(parts[dateStartIndex - 2]);
          }
        } else if (dateStartIndex >= 1) {
          // Maybe just city, no state
          city = _capitalizeWord(parts[dateStartIndex - 1]);
        }
      }
      
      // Extract event name (everything before city/state)
      int nameEndIndex = dateStartIndex;
      if (state != null) {
        nameEndIndex = dateStartIndex - 2;
      } else if (city != null) {
        nameEndIndex = dateStartIndex - 1;
      }
      
      if (nameEndIndex <= 0) {
        nameEndIndex = dateStartIndex;
      }
      
      final eventNameParts = parts.sublist(0, nameEndIndex);
      final eventName = eventNameParts
          .map((word) => _capitalizeWord(word))
          .join(' ');
      
      return {
        'eventName': eventName.isNotEmpty ? eventName : null,
        'city': city,
        'state': state,
        'date': eventDate,
      };
    } catch (e) {
      print('🎫 TICKETMASTER: Error extracting URL info: $e');
      return null;
    }
  }
  
  /// Helper to capitalize a word
  String _capitalizeWord(String word) {
    if (word.isEmpty) return word;
    return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
  }
  
  /// Check if a string looks like a US state name
  bool _isLikelyUSState(String word) {
    const usStates = {
      'alabama', 'alaska', 'arizona', 'arkansas', 'california',
      'colorado', 'connecticut', 'delaware', 'florida', 'georgia',
      'hawaii', 'idaho', 'illinois', 'indiana', 'iowa',
      'kansas', 'kentucky', 'louisiana', 'maine', 'maryland',
      'massachusetts', 'michigan', 'minnesota', 'mississippi', 'missouri',
      'montana', 'nebraska', 'nevada', 'hampshire', 'jersey',
      'mexico', 'york', 'carolina', 'dakota', 'ohio',
      'oklahoma', 'oregon', 'pennsylvania', 'island', 'tennessee',
      'texas', 'utah', 'vermont', 'virginia', 'washington',
      'wisconsin', 'wyoming', 'dc', 'columbia',
    };
    return usStates.contains(word.toLowerCase());
  }
  
  /// Get state code from state name
  String? _getStateCode(String? stateName) {
    if (stateName == null || stateName.isEmpty) return null;
    
    const stateCodeMap = {
      'alabama': 'AL', 'alaska': 'AK', 'arizona': 'AZ', 'arkansas': 'AR',
      'california': 'CA', 'colorado': 'CO', 'connecticut': 'CT', 'delaware': 'DE',
      'florida': 'FL', 'georgia': 'GA', 'hawaii': 'HI', 'idaho': 'ID',
      'illinois': 'IL', 'indiana': 'IN', 'iowa': 'IA', 'kansas': 'KS',
      'kentucky': 'KY', 'louisiana': 'LA', 'maine': 'ME', 'maryland': 'MD',
      'massachusetts': 'MA', 'michigan': 'MI', 'minnesota': 'MN', 'mississippi': 'MS',
      'missouri': 'MO', 'montana': 'MT', 'nebraska': 'NE', 'nevada': 'NV',
      'new hampshire': 'NH', 'new jersey': 'NJ', 'new mexico': 'NM', 'new york': 'NY',
      'north carolina': 'NC', 'north dakota': 'ND', 'ohio': 'OH', 'oklahoma': 'OK',
      'oregon': 'OR', 'pennsylvania': 'PA', 'rhode island': 'RI', 'south carolina': 'SC',
      'south dakota': 'SD', 'tennessee': 'TN', 'texas': 'TX', 'utah': 'UT',
      'vermont': 'VT', 'virginia': 'VA', 'washington': 'WA', 'west virginia': 'WV',
      'wisconsin': 'WI', 'wyoming': 'WY', 'district of columbia': 'DC',
    };
    
    return stateCodeMap[stateName.toLowerCase()];
  }
}

