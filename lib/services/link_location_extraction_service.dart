import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:any_link_preview/any_link_preview.dart';
import '../models/extracted_location_data.dart';
import '../models/gemini_grounding_result.dart';
import 'gemini_service.dart';
import 'google_maps_service.dart';
import 'instagram_oembed_service.dart';

/// Service for extracting location information from shared URLs
/// 
/// This service orchestrates multiple extraction strategies:
/// 1. URL-specific parsing (fast path for Yelp, Google Maps, etc.)
/// 2. Gemini AI with Google Maps grounding (primary)
/// 3. Google Places API search (fallback)
class LinkLocationExtractionService {
  final GeminiService _gemini = GeminiService();
  final GoogleMapsService _maps = GoogleMapsService();
  final InstagramOEmbedService _instagram = InstagramOEmbedService();

  // Cache to avoid redundant API calls
  final Map<String, List<ExtractedLocationData>> _cache = {};

  // Maximum number of locations to extract per URL/image
  static const int _maxLocationsDefault = 10;

  /// Extract locations from a shared URL
  /// 
  /// [url] - The URL to analyze
  /// [userLocation] - Optional user location for better results
  /// [maxLocations] - Maximum number of locations to return (default: 5)
  /// 
  /// Returns a list of [ExtractedLocationData] objects, one for each
  /// location found in the URL. May return an empty list if no locations found.
  Future<List<ExtractedLocationData>> extractLocationsFromSharedLink(
    String url, {
    LatLng? userLocation,
    int maxLocations = _maxLocationsDefault,
  }) async {
    // Normalize URL for caching
    final normalizedUrl = url.trim().toLowerCase();
    final cacheKey = 'multi:$normalizedUrl';

    // Check cache first
    if (_cache.containsKey(cacheKey)) {
      print('📦 EXTRACTION CACHE: Returning cached result for $url');
      return _cache[cacheKey]!;
    }

    print('🔍 EXTRACTION: Starting location extraction from: $url');
    
    List<ExtractedLocationData> results = [];

    // Strategy 1: URL-specific parsing (fast path)
    final urlSpecificResult = await _tryUrlSpecificExtraction(url);
    if (urlSpecificResult != null) {
      results.add(urlSpecificResult);
      print('✅ EXTRACTION: Found via URL parsing: ${urlSpecificResult.name}');
    }

    // Strategy 2: Gemini extraction (may return multiple locations)
    if (results.isEmpty || _shouldTryGeminiForMoreLocations(url)) {
      final geminiResults = await _tryGeminiMultiLocationExtraction(
        url,
        userLocation,
        maxLocations,
      );
      
      // Add Gemini results that aren't duplicates
      for (final geminiResult in geminiResults) {
        if (!_isDuplicate(geminiResult, results)) {
          results.add(geminiResult);
        }
      }
    }

    // Strategy 3: Places API fallback (only if nothing found)
    if (results.isEmpty) {
      final fallbackResult = await _tryPlacesSearchFallback(url);
      if (fallbackResult != null) {
        results.add(fallbackResult);
        print('✅ EXTRACTION: Found via Places search fallback: ${fallbackResult.name}');
      }
    }

    // Limit results
    if (results.length > maxLocations) {
      results = results.sublist(0, maxLocations);
    }

    // Cache results
    _cache[cacheKey] = results;
    
    print('📍 EXTRACTION: Total ${results.length} location(s) found for $url');
    return results;
  }

  /// Extract single location (convenience method)
  Future<ExtractedLocationData?> extractSingleLocation(
    String url, {
    LatLng? userLocation,
  }) async {
    final results = await extractLocationsFromSharedLink(
      url,
      userLocation: userLocation,
      maxLocations: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Clear the cache
  void clearCache() {
    _cache.clear();
    print('🗑️ EXTRACTION: Cache cleared');
  }

  /// Extract locations from social media caption/description text
  /// 
  /// [caption] - The caption/description text from the social media post
  /// [platform] - The platform name (e.g., "TikTok", "Instagram") for context
  /// [authorName] - Optional author name (useful for business accounts)
  /// [sourceUrl] - Optional source URL for caching and context
  /// [userLocation] - Optional user location for better results
  /// [maxLocations] - Maximum number of locations to return (default: 5)
  /// 
  /// Returns a list of [ExtractedLocationData] objects found in the caption.
  Future<List<ExtractedLocationData>> extractLocationsFromCaption(
    String caption, {
    String platform = 'social media',
    String? authorName,
    String? sourceUrl,
    LatLng? userLocation,
    int maxLocations = _maxLocationsDefault,
  }) async {
    // Check cache if we have a source URL
    if (sourceUrl != null) {
      final cacheKey = 'caption:${sourceUrl.trim().toLowerCase()}';
      if (_cache.containsKey(cacheKey)) {
        print('📦 CAPTION CACHE: Returning cached result for $sourceUrl');
        return _cache[cacheKey]!;
      }
    }

    print('🎬 CAPTION EXTRACTION: Analyzing $platform caption...');
    print('📝 Caption preview: ${caption.length > 100 ? caption.substring(0, 100) + "..." : caption}');
    
    List<ExtractedLocationData> results = [];

    try {
      // Build context-rich prompt for Gemini
      final contextualCaption = _buildCaptionContext(
        caption: caption,
        platform: platform,
        authorName: authorName,
      );
      
      // Use Gemini to extract locations from the caption text
      final geminiResult = await _gemini.extractLocationsFromText(
        contextualCaption,
        userLocation: userLocation,
      );
      
      // Extract city/location context from the caption for better Places API searches
      final locationContext = _extractLocationContext(caption);
      if (locationContext != null) {
        print('📍 CAPTION: Detected location context: "$locationContext"');
      }
      
      // Track seen locations to avoid duplicates
      final Set<String> seenPlaceIds = {};
      final Set<String> seenLocationNames = {};
      
      // Check if we have grounding chunks with location data
      // BUT validate that the grounding chunks are actually relevant to the caption
      // (Gemini sometimes returns unrelated businesses based on keywords)
      if (geminiResult != null && geminiResult.locations.isNotEmpty) {
        // Filter grounding chunks to only include ones whose names appear in the caption
        final lowerCaption = caption.toLowerCase();
        final relevantLocations = geminiResult.locations.where((location) {
          final nameParts = location.name.toLowerCase().split(' ');
          // Check if at least 2 words from the location name appear in the caption
          // (or all words if name has fewer than 2 words)
          final requiredMatches = nameParts.length >= 2 ? 2 : nameParts.length;
          int matchCount = 0;
          for (final part in nameParts) {
            if (part.length > 2 && lowerCaption.contains(part)) {
              matchCount++;
            }
          }
          final isRelevant = matchCount >= requiredMatches;
          if (!isRelevant) {
            print('⏭️ CAPTION: Skipping unrelated grounding result: "${location.name}" (not mentioned in caption)');
          }
          return isRelevant;
        }).toList();
        
        if (relevantLocations.isNotEmpty) {
          print('✅ CAPTION EXTRACTION: Found ${relevantLocations.length} relevant location(s) from grounding (filtered from ${geminiResult.locations.length})');
        
        // Convert and verify each location has valid coordinates
        for (final location in relevantLocations.take(maxLocations)) {
          // Skip if we've already processed a location with the same name (case-insensitive)
          final normalizedName = location.name.toLowerCase().trim();
          if (seenLocationNames.contains(normalizedName)) {
            print('⏭️ CAPTION: Skipping duplicate location name: "${location.name}"');
            continue;
          }
          seenLocationNames.add(normalizedName);
          
          final hasValidCoords = location.coordinates.latitude != 0.0 || 
                                  location.coordinates.longitude != 0.0;
          
          if (hasValidCoords && location.placeId.isNotEmpty) {
            // Skip if we've already added this Place ID
            if (seenPlaceIds.contains(location.placeId)) {
              print('⏭️ CAPTION: Skipping duplicate Place ID: ${location.placeId}');
              continue;
            }
            seenPlaceIds.add(location.placeId);
            
            // Location has valid coordinates and Place ID from grounding
            print('📍 CAPTION: "${location.name}" has valid coords from grounding');
            results.add(ExtractedLocationData(
              placeId: location.placeId,
              name: location.name,
              address: location.formattedAddress,
              coordinates: location.coordinates,
              type: ExtractedLocationData.inferPlaceType(location.types),
              source: ExtractionSource.geminiGrounding,
              confidence: 0.9,
              googleMapsUri: location.uri,
              placeTypes: location.types,
            ));
          } else {
            // Location needs Places API lookup for coordinates
            // Include location context from caption for better results
            print('🔍 CAPTION: "${location.name}" missing coords, searching Places API...');
            final resolvedLocation = await _resolveLocationWithPlacesApi(
              location.name,
              address: location.formattedAddress,
              locationContext: locationContext, // Add city/region context
              userLocation: userLocation,
            );
            
            if (resolvedLocation != null) {
              // Skip if we've already added this Place ID
              if (resolvedLocation.placeId != null && seenPlaceIds.contains(resolvedLocation.placeId)) {
                print('⏭️ CAPTION: Skipping duplicate resolved Place ID: ${resolvedLocation.placeId}');
                continue;
              }
              if (resolvedLocation.placeId != null) {
                seenPlaceIds.add(resolvedLocation.placeId!);
              }
              
              print('✅ CAPTION: Resolved "${location.name}" via Places API');
              results.add(resolvedLocation);
            } else {
              // Still add the location even without coords - user can manually set
              print('⚠️ CAPTION: Could not resolve "${location.name}", adding without coords');
              results.add(ExtractedLocationData(
                placeId: location.placeId.isNotEmpty ? location.placeId : null,
                name: location.name,
                address: location.formattedAddress,
                coordinates: null, // No valid coordinates
                type: ExtractedLocationData.inferPlaceType(location.types),
                source: ExtractionSource.geminiGrounding,
                confidence: 0.5, // Lower confidence without coords
                placeTypes: location.types,
              ));
            }
          }
        }
        } else {
          print('⚠️ CAPTION EXTRACTION: Grounding returned ${geminiResult.locations.length} results but none matched caption text');
        }
      } 
      
      // Fallback: Parse JSON from Gemini's text response when:
      // 1. No grounding chunks were returned, OR
      // 2. Grounding chunks were irrelevant (filtered out above)
      if (results.isEmpty && geminiResult != null && geminiResult.responseText.isNotEmpty) {
        print('🔄 CAPTION EXTRACTION: No grounding chunks, parsing JSON from response text...');
        
        final parsedLocations = _parseLocationsFromJsonResponse(geminiResult.responseText);
        
        if (parsedLocations.isNotEmpty) {
          print('✅ CAPTION EXTRACTION: Parsed ${parsedLocations.length} location(s) from JSON response');
          
          for (final parsed in parsedLocations.take(maxLocations)) {
            final name = parsed['name'] as String?;
            if (name == null || name.isEmpty) continue;
            
            // Skip duplicates by name
            final normalizedName = name.toLowerCase().trim();
            if (seenLocationNames.contains(normalizedName)) {
              print('⏭️ CAPTION: Skipping duplicate location name: "$name"');
              continue;
            }
            seenLocationNames.add(normalizedName);
            
            final city = parsed['city'] as String?;
            final region = parsed['region'] as String?;
            final address = parsed['address'] as String?;
            
            // Build location context from parsed JSON (prioritize parsed city over caption context)
            String? effectiveContext = city ?? locationContext;
            if (effectiveContext == null && region != null) {
              effectiveContext = region;
            }
            
            print('🔍 CAPTION: Resolving "$name" with context "$effectiveContext" via Places API...');
            
            final resolvedLocation = await _resolveLocationWithPlacesApi(
              name,
              address: address,
              locationContext: effectiveContext,
              userLocation: userLocation,
            );
            
            if (resolvedLocation != null) {
              // Skip if we've already added this Place ID
              if (resolvedLocation.placeId != null && seenPlaceIds.contains(resolvedLocation.placeId)) {
                print('⏭️ CAPTION: Skipping duplicate resolved Place ID: ${resolvedLocation.placeId}');
                continue;
              }
              if (resolvedLocation.placeId != null) {
                seenPlaceIds.add(resolvedLocation.placeId!);
              }
              
              print('✅ CAPTION: Resolved "$name" via Places API');
              results.add(resolvedLocation);
            } else {
              // Add location without coordinates - user can manually set
              print('⚠️ CAPTION: Could not resolve "$name", adding without coords');
              results.add(ExtractedLocationData(
                placeId: null,
                name: name,
                address: address ?? (city != null ? '$city${region != null ? ", $region" : ""}' : null),
                coordinates: null,
                type: PlaceType.unknown,
                source: ExtractionSource.geminiGrounding, // From Gemini, even though grounding chunks were empty
                confidence: 0.5,
              ));
            }
          }
        } else {
          print('⚠️ CAPTION EXTRACTION: Could not parse any locations from JSON response');
        }
      }
      
      // Final check - if still no results
      if (results.isEmpty) {
        if (geminiResult == null) {
          print('⚠️ CAPTION EXTRACTION: Gemini returned no results');
        } else {
          print('⚠️ CAPTION EXTRACTION: No locations could be extracted from caption');
        }
      }
      
      print('📍 CAPTION EXTRACTION: Returning ${results.length} unique location(s)');
    } catch (e) {
      print('❌ CAPTION EXTRACTION ERROR: $e');
    }

    // Cache results if we have a source URL
    if (sourceUrl != null) {
      final cacheKey = 'caption:${sourceUrl.trim().toLowerCase()}';
      _cache[cacheKey] = results;
    }

    return results;
  }
  
  /// Extract city/region context from caption text
  /// Returns the most specific location mentioned (city > region > state)
  String? _extractLocationContext(String caption) {
    final lowerCaption = caption.toLowerCase();
    
    // Common California cities (prioritize specific cities)
    final caCities = [
      'anaheim', 'los angeles', 'la', 'san diego', 'san francisco', 'sf',
      'san jose', 'irvine', 'santa monica', 'burbank', 'glendale', 'pasadena',
      'long beach', 'oakland', 'berkeley', 'hollywood', 'west hollywood',
      'beverly hills', 'costa mesa', 'newport beach', 'laguna beach',
      'huntington beach', 'fullerton', 'garden grove', 'santa ana',
      'alhambra', 'arcadia', 'torrance', 'downey', 'el monte', 'pomona',
      'ontario', 'riverside', 'corona', 'temecula', 'oceanside', 'carlsbad',
      'escondido', 'chula vista', 'sacramento', 'fresno', 'bakersfield',
      'whittier', 'buena park', 'cypress', 'la habra', 'placentia', 'yorba linda',
      'brea', 'diamond bar', 'rowland heights', 'walnut', 'west covina', 'covina',
      'monrovia', 'azusa', 'glendora', 'san dimas', 'claremont', 'upland', 'rancho cucamonga',
    ];
    
    // Common US cities
    final usCities = [
      'new york', 'nyc', 'manhattan', 'brooklyn', 'queens',
      'chicago', 'houston', 'phoenix', 'philadelphia', 'san antonio',
      'dallas', 'austin', 'seattle', 'denver', 'boston', 'atlanta',
      'miami', 'tampa', 'orlando', 'las vegas', 'portland', 'detroit',
      'minneapolis', 'charlotte', 'raleigh', 'nashville', 'memphis',
      'new orleans', 'salt lake city', 'honolulu', 'anchorage',
    ];
    
    // Regional abbreviations  
    final regions = {
      'oc': 'Orange County, CA',
      'orange county': 'Orange County, CA',
      'socal': 'Southern California',
      'norcal': 'Northern California',
      'bay area': 'Bay Area, CA',
      'silicon valley': 'Silicon Valley, CA',
      'inland empire': 'Inland Empire, CA',
    };
    
    // Check for parenthetical city format first: (city, state) or (city,state)
    // Examples: (whittier,ca), (Anaheim, CA), (Los Angeles, California)
    final parenCityPattern = RegExp(r'\(([a-zA-Z\s]+)[,\s]+(ca|california|tx|texas|ny|new york|fl|florida|wa|washington)\)', caseSensitive: false);
    final parenMatch = parenCityPattern.firstMatch(lowerCaption);
    if (parenMatch != null) {
      final possibleCity = parenMatch.group(1)?.trim().toLowerCase();
      if (possibleCity != null && (caCities.contains(possibleCity) || usCities.contains(possibleCity))) {
        print('🏙️ CONTEXT: Found city in parentheses: $possibleCity');
        return possibleCity;
      }
    }
    
    // Check hashtags (most specific intent)
    final hashtagPattern = RegExp(r'#(\w+)');
    final hashtags = hashtagPattern.allMatches(lowerCaption)
        .map((m) => m.group(1)?.toLowerCase() ?? '')
        .toList();
    
    // Check hashtags for city names
    for (final city in caCities) {
      final cityNoSpaces = city.replaceAll(' ', '');
      if (hashtags.contains(cityNoSpaces) || hashtags.contains(city)) {
        print('🏙️ CONTEXT: Found city in hashtag: $city');
        return city;
      }
    }
    for (final city in usCities) {
      final cityNoSpaces = city.replaceAll(' ', '');
      if (hashtags.contains(cityNoSpaces) || hashtags.contains(city)) {
        print('🏙️ CONTEXT: Found city in hashtag: $city');
        return city;
      }
    }
    
    // Check caption text for "in [City]" pattern
    final inCityPattern = RegExp(r'\bin\s+([A-Z][a-zA-Z\s]+?)(?:\s*[!.,#✨🎉]|\s+(?:just|is|has|and|the|at|on)|\s*$)', caseSensitive: false);
    final inCityMatches = inCityPattern.allMatches(caption);
    for (final match in inCityMatches) {
      final possibleCity = match.group(1)?.trim().toLowerCase();
      if (possibleCity != null) {
        // Check if it's a known city
        if (caCities.contains(possibleCity) || usCities.contains(possibleCity)) {
          print('🏙️ CONTEXT: Found "in $possibleCity" pattern');
          return possibleCity;
        }
      }
    }
    
    // Check for regional abbreviations
    for (final entry in regions.entries) {
      if (lowerCaption.contains(entry.key)) {
        print('🏙️ CONTEXT: Found region: ${entry.key}');
        // For regions like "OC", try to find a more specific city
        // If "OC" is found, look for nearby city mentions
        if (entry.key == 'oc' || entry.key == 'orange county') {
          // Check for specific OC cities
          for (final city in ['anaheim', 'irvine', 'santa ana', 'costa mesa', 
                              'newport beach', 'huntington beach', 'fullerton', 
                              'garden grove', 'orange', 'tustin']) {
            if (lowerCaption.contains(city)) {
              print('🏙️ CONTEXT: Found specific OC city: $city');
              return city;
            }
          }
        }
        return entry.value;
      }
    }
    
    // Check caption text for any city mention
    for (final city in caCities) {
      if (lowerCaption.contains(city)) {
        print('🏙️ CONTEXT: Found city mention: $city');
        return city;
      }
    }
    for (final city in usCities) {
      if (lowerCaption.contains(city)) {
        print('🏙️ CONTEXT: Found city mention: $city');
        return city;
      }
    }
    
    return null;
  }

  /// Parse locations from Gemini's JSON response text
  /// Handles cases where Gemini returns JSON but Maps grounding didn't return chunks
  List<Map<String, dynamic>> _parseLocationsFromJsonResponse(String responseText) {
    try {
      // Find JSON array in the response (may be wrapped in markdown code blocks)
      String jsonStr = responseText.trim();
      
      // Remove markdown code block wrapper if present
      if (jsonStr.contains('```json')) {
        final start = jsonStr.indexOf('```json') + 7;
        final end = jsonStr.indexOf('```', start);
        if (end > start) {
          jsonStr = jsonStr.substring(start, end).trim();
        }
      } else if (jsonStr.contains('```')) {
        final start = jsonStr.indexOf('```') + 3;
        final end = jsonStr.indexOf('```', start);
        if (end > start) {
          jsonStr = jsonStr.substring(start, end).trim();
        }
      }
      
      // Find the JSON array bounds
      final arrayStart = jsonStr.indexOf('[');
      final arrayEnd = jsonStr.lastIndexOf(']');
      
      if (arrayStart == -1 || arrayEnd == -1 || arrayEnd <= arrayStart) {
        print('⚠️ JSON PARSE: No valid JSON array found in response');
        return [];
      }
      
      jsonStr = jsonStr.substring(arrayStart, arrayEnd + 1);
      
      // Parse the JSON
      final decoded = jsonDecode(jsonStr);
      
      if (decoded is List) {
        final results = <Map<String, dynamic>>[];
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            results.add(item);
          }
        }
        print('✅ JSON PARSE: Successfully parsed ${results.length} location(s)');
        return results;
      }
      
      return [];
    } catch (e) {
      print('❌ JSON PARSE ERROR: $e');
      return [];
    }
  }

  /// Resolve a location name to full details using Places API
  Future<ExtractedLocationData?> _resolveLocationWithPlacesApi(
    String locationName, {
    String? address,
    String? locationContext,
    LatLng? userLocation,
  }) async {
    try {
      // Build search query - combine name with location context for better results
      String searchQuery = locationName;
      
      // Prioritize location context over generic address
      if (locationContext != null && locationContext.isNotEmpty) {
        // Use comma-separated format for more specific matching
        searchQuery = '$locationName, $locationContext';
        print('🔍 PLACES RESOLVE: Using location context: "$searchQuery"');
      } else if (address != null && address.isNotEmpty) {
        searchQuery = '$locationName $address';
      }
      
      print('🔍 PLACES RESOLVE: Searching for "$searchQuery"');
      
      final results = await _maps.searchPlaces(searchQuery);
      if (results.isEmpty) {
        print('⚠️ PLACES RESOLVE: No results for "$searchQuery"');
        return null;
      }

      // Find the best matching result based on location context
      Map<String, dynamic> bestResult = results.first;
      
      if (locationContext != null && locationContext.isNotEmpty && results.length > 1) {
        // Look for a result that contains the location context in its description/address
        final lowerContext = locationContext.toLowerCase();
        
        for (final result in results) {
          final description = (result['description'] as String? ?? '').toLowerCase();
          final resultAddress = (result['address'] as String? ?? '').toLowerCase();
          
          // Check if this result matches the city context
          if (description.contains(lowerContext) || resultAddress.contains(lowerContext)) {
            print('🎯 PLACES RESOLVE: Found city-matching result: ${result['description']}');
            bestResult = result;
            break;
          }
        }
        
        // If no exact match, log what we're using
        if (bestResult == results.first) {
          print('⚠️ PLACES RESOLVE: No result matched city "$locationContext", using first result');
          // Log all results for debugging
          for (int i = 0; i < results.length && i < 3; i++) {
            print('   Result ${i + 1}: ${results[i]['description']}');
          }
        }
      }

      final placeId = bestResult['placeId'] as String?;
      
      // Autocomplete doesn't return coordinates - need to call Place Details API
      LatLng? coords;
      String? resolvedAddress;
      String? resolvedName;
      
      if (placeId != null && placeId.isNotEmpty) {
        print('🔍 PLACES RESOLVE: Getting details for Place ID: $placeId');
        try {
          final placeDetails = await _maps.getPlaceDetails(placeId);
          
          // Extract coordinates from place details
          if (placeDetails.latitude != 0.0 || placeDetails.longitude != 0.0) {
            coords = LatLng(placeDetails.latitude, placeDetails.longitude);
          }
          
          resolvedAddress = placeDetails.address;
          resolvedName = placeDetails.displayName ?? bestResult['description'] as String?;
          
          print('✅ PLACES RESOLVE: Got details - "${resolvedName}" at $coords');
        } catch (e) {
          print('⚠️ PLACES RESOLVE: Could not get place details: $e');
          // Fall back to autocomplete data
          resolvedName = bestResult['description'] as String?;
          resolvedAddress = bestResult['address'] as String?;
        }
      } else {
        resolvedName = bestResult['description'] as String?;
        resolvedAddress = bestResult['address'] as String?;
      }
      
      print('✅ PLACES RESOLVE: Final result "${resolvedName}" at $coords');

      return ExtractedLocationData(
        placeId: placeId,
        name: resolvedName ?? locationName,
        address: resolvedAddress,
        coordinates: coords,
        type: PlaceType.unknown,
        source: ExtractionSource.placesSearch,
        confidence: coords != null ? 0.85 : 0.6, // Higher confidence with coords
        metadata: {'original_query': locationName, 'location_context': locationContext},
      );
    } catch (e) {
      print('❌ PLACES RESOLVE ERROR: $e');
      return null;
    }
  }

  /// Build a context-rich prompt for caption-based extraction
  String _buildCaptionContext({
    required String caption,
    required String platform,
    String? authorName,
  }) {
    final buffer = StringBuffer();
    
    buffer.writeln('$platform post caption:');
    buffer.writeln();
    buffer.writeln(caption);
    
    if (authorName != null && authorName.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Posted by: $authorName');
      buffer.writeln('(Note: The author name might be a business name if this is a business account)');
    }
    
    return buffer.toString();
  }

  // ============ EXTRACTION STRATEGIES ============

  /// Strategy 1: URL-specific parsing (fast path for known platforms)
  Future<ExtractedLocationData?> _tryUrlSpecificExtraction(String url) async {
    try {
      // Google Maps URLs
      if (_isGoogleMapsUrl(url)) {
        return await _extractFromGoogleMapsUrl(url);
      }

      // Yelp URLs
      if (_isYelpUrl(url)) {
        return await _extractFromYelpUrl(url);
      }

      // Instagram location URLs
      if (_isInstagramLocationUrl(url)) {
        return await _extractFromInstagramLocationUrl(url);
      }

      return null;
    } catch (e) {
      print('⚠️ URL PARSING ERROR: $e');
      return null;
    }
  }

  /// Strategy 2: Gemini AI extraction with Maps grounding
  Future<List<ExtractedLocationData>> _tryGeminiMultiLocationExtraction(
    String url,
    LatLng? userLocation,
    int maxLocations,
  ) async {
    try {
      // NOTE: Instagram oEmbed API requires Facebook App Review (Meta oEmbed Read permission)
      // Disabled for now - requires app review which takes days/weeks
      // 
      // For Instagram URLs, try to get caption via oEmbed API first
      // if (_isInstagramUrl(url)) {
      //   print('📸 EXTRACTION: Fetching Instagram caption...');
      //   final caption = await _instagram.getCaptionFromUrl(url);
      //   
      //   if (caption != null && caption.isNotEmpty) {
      //     print('✅ EXTRACTION: Got Instagram caption: ${caption.length} chars');
      //     
      //     // Use Gemini to extract locations from caption
      //     final textResult = await _gemini.extractLocationsFromText(
      //       'Instagram post caption:\n\n$caption',
      //       userLocation: userLocation,
      //     );
      //     
      //     if (textResult != null && textResult.locations.isNotEmpty) {
      //       print('✅ EXTRACTION: Found locations from Instagram caption');
      //       return _convertGeminiResultToExtracted(textResult, maxLocations);
      //     }
      //   } else {
      //     print('⚠️ EXTRACTION: Could not get Instagram caption');
      //   }
      // }
      
      // For other social media URLs, try to get page metadata
      String? pageDescription;
      if (_isSocialMediaUrl(url) && !_isInstagramUrl(url)) {
        print('📄 EXTRACTION: Fetching metadata for social media URL...');
        try {
          final metadata = await AnyLinkPreview.getMetadata(link: url);
          if (metadata != null) {
            // Combine title and description for context
            final title = metadata.title ?? '';
            final description = metadata.desc ?? '';
            pageDescription = '$title $description'.trim();
            
            if (pageDescription.isNotEmpty) {
              print('📄 EXTRACTION: Got metadata: ${pageDescription.length} chars');
              
              // If we have description, use text extraction instead
              final textResult = await _gemini.extractLocationsFromText(
                'Content from $url:\n\n$pageDescription',
                userLocation: userLocation,
              );
              
              if (textResult != null && textResult.locations.isNotEmpty) {
                print('✅ EXTRACTION: Found locations from page metadata');
                return _convertGeminiResultToExtracted(textResult, maxLocations);
              }
            }
          }
        } catch (e) {
          print('⚠️ EXTRACTION: Could not fetch metadata: $e');
        }
      }
      
      // Fall back to URL-based extraction
      final result = await _gemini.extractLocationFromUrl(
        url,
        userLocation: userLocation,
      );

      if (result == null || result.locations.isEmpty) {
        return [];
      }

      return _convertGeminiResultToExtracted(result, maxLocations);
    } catch (e) {
      print('❌ GEMINI EXTRACTION ERROR: $e');
      return [];
    }
  }

  /// Convert Gemini result to ExtractedLocationData list
  List<ExtractedLocationData> _convertGeminiResultToExtracted(
    GeminiGroundingResult result,
    int maxLocations,
  ) {
    final extractedList = <ExtractedLocationData>[];

    for (final location in result.locations.take(maxLocations)) {
      extractedList.add(ExtractedLocationData(
        placeId: location.placeId.isNotEmpty ? location.placeId : null,
        name: location.name,
        address: location.formattedAddress,
        coordinates: location.coordinates,
        type: ExtractedLocationData.inferPlaceType(location.types),
        source: ExtractionSource.geminiGrounding,
        confidence: 0.9, // High confidence for grounded results
        googleMapsUri: location.uri,
        placeTypes: location.types,
        metadata: {
          'gemini_response': result.responseText,
          'widget_token': result.widgetContextToken,
          'location_index': extractedList.length,
        },
      ));
    }

    return extractedList;
  }

  /// Check if URL is from Instagram
  bool _isInstagramUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('instagram.com/p/') ||
           lower.contains('instagram.com/reel/') ||
           lower.contains('instagram.com/tv/');
  }

  /// Check if URL is from a social media platform
  bool _isSocialMediaUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('instagram.com') ||
           lower.contains('tiktok.com') ||
           lower.contains('youtube.com') ||
           lower.contains('facebook.com') ||
           lower.contains('twitter.com') ||
           lower.contains('x.com');
  }

  /// Strategy 3: Places API fallback
  Future<ExtractedLocationData?> _tryPlacesSearchFallback(String url) async {
    // Extract potential search query from URL
    final searchQuery = _extractSearchQueryFromUrl(url);
    if (searchQuery == null || searchQuery.isEmpty) {
      return null;
    }

    try {
      print('🔍 PLACES FALLBACK: Searching for "$searchQuery"');
      
      final results = await _maps.searchPlaces(searchQuery);
      if (results.isEmpty) {
        print('⚠️ PLACES FALLBACK: No results found');
        return null;
      }

      final firstResult = results.first;
      
      // Get coordinates
      double? lat;
      double? lng;
      if (firstResult['geometry'] != null) {
        final geometry = firstResult['geometry'] as Map<String, dynamic>;
        final location = geometry['location'] as Map<String, dynamic>?;
        if (location != null) {
          lat = (location['lat'] as num?)?.toDouble();
          lng = (location['lng'] as num?)?.toDouble();
        }
      }

      return ExtractedLocationData(
        placeId: firstResult['placeId'] as String?,
        name: firstResult['description'] as String? ?? searchQuery,
        address: firstResult['address'] as String?,
        coordinates: (lat != null && lng != null) ? LatLng(lat, lng) : null,
        type: PlaceType.unknown,
        source: ExtractionSource.placesSearch,
        confidence: 0.6, // Lower confidence for search-based results
        metadata: {'search_query': searchQuery},
      );
    } catch (e) {
      print('❌ PLACES FALLBACK ERROR: $e');
      return null;
    }
  }

  // ============ URL PATTERN DETECTION ============

  bool _isGoogleMapsUrl(String url) {
    return url.contains('google.com/maps') ||
           url.contains('maps.google.com') ||
           url.contains('goo.gl/maps');
  }

  bool _isYelpUrl(String url) {
    return url.contains('yelp.com/biz/');
  }

  bool _isInstagramLocationUrl(String url) {
    return url.contains('instagram.com/explore/locations/');
  }

  bool _shouldTryGeminiForMoreLocations(String url) {
    // URLs that might contain multiple locations
    final multiLocationPatterns = [
      RegExp(r'(top|best|guide|list|favorites?)\s*\d*', caseSensitive: false),
      RegExp(r'\d+\s*(places?|restaurants?|spots?|things?)', caseSensitive: false),
      RegExp(r'(blog|article|post)', caseSensitive: false),
    ];

    for (final pattern in multiLocationPatterns) {
      if (pattern.hasMatch(url)) {
        return true;
      }
    }

    // Social media URLs often have additional context
    if (url.contains('instagram.com') ||
        url.contains('tiktok.com') ||
        url.contains('youtube.com') ||
        url.contains('facebook.com')) {
      return true;
    }

    return false;
  }

  // ============ URL-SPECIFIC EXTRACTORS ============

  Future<ExtractedLocationData?> _extractFromGoogleMapsUrl(String url) async {
    try {
      // Try to extract place ID from URL
      // Format: https://www.google.com/maps/place/.../@lat,lng,.../data=!...!1s0x...:0x...
      final placeIdMatch = RegExp(r'!1s(0x[a-fA-F0-9]+:0x[a-fA-F0-9]+)').firstMatch(url);
      
      // Try CID format: ?cid=...
      final cidMatch = RegExp(r'[?&]cid=(\d+)').firstMatch(url);
      
      // Try place_id format: place_id=...
      final directPlaceIdMatch = RegExp(r'place_id=([^&]+)').firstMatch(url);
      
      String? placeId;
      if (directPlaceIdMatch != null) {
        placeId = directPlaceIdMatch.group(1);
      } else if (placeIdMatch != null) {
        placeId = placeIdMatch.group(1);
      }

      // Extract coordinates from URL
      final coordsMatch = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(url);
      LatLng? coordinates;
      if (coordsMatch != null) {
        final lat = double.tryParse(coordsMatch.group(1)!);
        final lng = double.tryParse(coordsMatch.group(2)!);
        if (lat != null && lng != null) {
          coordinates = LatLng(lat, lng);
        }
      }

      // Extract name from URL path
      final nameMatch = RegExp(r'/place/([^/@]+)').firstMatch(url);
      String name = 'Unknown Location';
      if (nameMatch != null) {
        name = Uri.decodeComponent(nameMatch.group(1)!).replaceAll('+', ' ');
      }

      if (placeId != null || coordinates != null) {
        return ExtractedLocationData(
          placeId: placeId,
          name: name,
          coordinates: coordinates,
          type: PlaceType.unknown,
          source: ExtractionSource.urlParsing,
          confidence: 0.85,
          googleMapsUri: url,
        );
      }

      return null;
    } catch (e) {
      print('⚠️ GOOGLE MAPS URL PARSING ERROR: $e');
      return null;
    }
  }

  Future<ExtractedLocationData?> _extractFromYelpUrl(String url) async {
    try {
      // Extract business ID from Yelp URL
      // Format: https://www.yelp.com/biz/business-name-city
      final bizMatch = RegExp(r'yelp\.com/biz/([^/?#]+)').firstMatch(url);
      if (bizMatch == null) return null;

      final businessId = bizMatch.group(1)!;
      
      // Convert business ID to readable name
      final name = businessId
          .replaceAll('-', ' ')
          .split(' ')
          .map((word) => word.isNotEmpty 
              ? '${word[0].toUpperCase()}${word.substring(1)}' 
              : '')
          .join(' ');

      return ExtractedLocationData(
        name: name,
        type: PlaceType.restaurant, // Most Yelp URLs are restaurants
        source: ExtractionSource.urlParsing,
        confidence: 0.75, // Need Places API to verify
        metadata: {'yelp_business_id': businessId},
      );
    } catch (e) {
      print('⚠️ YELP URL PARSING ERROR: $e');
      return null;
    }
  }

  Future<ExtractedLocationData?> _extractFromInstagramLocationUrl(String url) async {
    try {
      // Extract location ID from Instagram URL
      // Format: https://www.instagram.com/explore/locations/123456/location-name/
      final locationMatch = RegExp(r'locations/(\d+)/([^/?#]+)?').firstMatch(url);
      if (locationMatch == null) return null;

      final locationId = locationMatch.group(1)!;
      final locationName = locationMatch.group(2);

      String name = 'Instagram Location';
      if (locationName != null) {
        name = Uri.decodeComponent(locationName).replaceAll('-', ' ');
      }

      return ExtractedLocationData(
        name: name,
        type: PlaceType.unknown,
        source: ExtractionSource.urlParsing,
        confidence: 0.7,
        metadata: {'instagram_location_id': locationId},
      );
    } catch (e) {
      print('⚠️ INSTAGRAM URL PARSING ERROR: $e');
      return null;
    }
  }

  // ============ HELPER METHODS ============

  String? _extractSearchQueryFromUrl(String url) {
    // Try to extract meaningful text from URL for search
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    // Check query parameters
    final qParam = uri.queryParameters['q'] ?? 
                   uri.queryParameters['query'] ??
                   uri.queryParameters['search'];
    if (qParam != null && qParam.isNotEmpty) {
      return Uri.decodeComponent(qParam);
    }

    // Extract from path
    final pathSegments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (pathSegments.isNotEmpty) {
      // Get the last meaningful segment
      for (int i = pathSegments.length - 1; i >= 0; i--) {
        final segment = pathSegments[i];
        // Skip common URL parts
        if (!['www', 'com', 'explore', 'p', 'reel', 'video', 'watch'].contains(segment)) {
          return Uri.decodeComponent(segment).replaceAll('-', ' ').replaceAll('_', ' ');
        }
      }
    }

    return null;
  }

  bool _isDuplicate(ExtractedLocationData newLocation, List<ExtractedLocationData> existing) {
    for (final loc in existing) {
      // Check by place ID
      if (newLocation.placeId != null && 
          loc.placeId != null && 
          newLocation.placeId == loc.placeId) {
        print('⚠️ DUPLICATE CHECK: Same place ID: ${newLocation.placeId}');
        return true;
      }

      // Check by name similarity (exact match only)
      if (_areNamesSimilar(newLocation.name, loc.name)) {
        print('⚠️ DUPLICATE CHECK: Similar names: "${newLocation.name}" vs "${loc.name}"');
        return true;
      }

      // Check by coordinates proximity
      if (newLocation.coordinates != null && loc.coordinates != null) {
        final distance = _calculateDistance(
          newLocation.coordinates!, 
          loc.coordinates!,
        );
        if (distance < 50) { // Within 50 meters
          print('⚠️ DUPLICATE CHECK: Too close (${distance.toStringAsFixed(0)}m): "${newLocation.name}" vs "${loc.name}"');
          return true;
        }
      }
    }
    return false;
  }

  bool _areNamesSimilar(String name1, String name2) {
    final n1 = name1.toLowerCase().trim();
    final n2 = name2.toLowerCase().trim();
    
    // Exact match
    if (n1 == n2) return true;
    
    // Only check containment for short names (to avoid "Cafe" matching everything)
    // And require at least 80% overlap
    if (n1.length >= 5 && n2.length >= 5) {
      if (n1.contains(n2) && n2.length >= n1.length * 0.8) return true;
      if (n2.contains(n1) && n1.length >= n2.length * 0.8) return true;
    }
    
    return false;
  }

  double _calculateDistance(LatLng point1, LatLng point2) {
    // Haversine formula for distance calculation
    const double earthRadius = 6371000; // meters
    
    final lat1Rad = point1.latitude * math.pi / 180;
    final lat2Rad = point2.latitude * math.pi / 180;
    final dLatRad = (point2.latitude - point1.latitude) * math.pi / 180;
    final dLngRad = (point2.longitude - point1.longitude) * math.pi / 180;

    final a = math.sin(dLatRad / 2) * math.sin(dLatRad / 2) +
              math.cos(lat1Rad) * math.cos(lat2Rad) * 
              math.sin(dLngRad / 2) * math.sin(dLngRad / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  // ============ IMAGE/SCREENSHOT EXTRACTION METHODS ============

  /// Extract locations from an image file (e.g., screenshot)
  /// 
  /// This uses a two-step approach:
  /// 1. Gemini Vision extracts location names/text from the image
  /// 2. Google Places API verifies and gets full place details
  /// 
  /// [imageFile] - The image file to analyze
  /// [userLocation] - Optional user location for better results
  /// No limit on number of locations - extracts all found locations
  Future<List<ExtractedLocationData>> extractLocationsFromImage(
    File imageFile, {
    LatLng? userLocation,
  }) async {
    print('📷 IMAGE EXTRACTION: Starting extraction from image...');
    
    try {
      // Step 1: Use Gemini Vision to extract location names/text from the image
      final extractedNames = await _gemini.extractLocationNamesFromImageFile(imageFile);

      if (extractedNames.isEmpty) {
        print('⚠️ IMAGE EXTRACTION: Gemini Vision found no locations in image');
        return [];
      }

      print('📷 IMAGE EXTRACTION: Gemini found ${extractedNames.length} potential location(s), verifying with Places API...');

      // Step 2: Verify each location with Google Places API
      final results = <ExtractedLocationData>[];
      
      for (final locationInfo in extractedNames) {
        
        // Build search query from extracted info
        String searchQuery = locationInfo.name;
        if (locationInfo.address != null) {
          searchQuery += ' ${locationInfo.address}';
        }
        if (locationInfo.city != null) {
          searchQuery += ' ${locationInfo.city}';
        }
        
        print('📷 IMAGE EXTRACTION: Searching Places API for: $searchQuery');
        
        // Search Places API
        final placeResults = await _maps.searchPlaces(
          searchQuery,
          latitude: userLocation?.latitude,
          longitude: userLocation?.longitude,
        );
        
        final placeResult = placeResults.isNotEmpty ? placeResults.first : null;
        
        if (placeResult != null) {
          // Note: searchPlaces returns 'placeId' (camelCase) for autocomplete results
          // and 'place_id' (snake_case) for TextSearch results
          final placeId = (placeResult['placeId'] ?? placeResult['place_id']) as String?;
          var coordinates = _extractCoordinates(placeResult);
          // Autocomplete uses 'address' or 'description', TextSearch uses 'formatted_address'
          var address = (placeResult['formatted_address'] ?? placeResult['address'] ?? placeResult['description']) as String? ?? locationInfo.address;
          // Autocomplete uses 'description', TextSearch uses 'name'
          var name = (placeResult['name'] ?? placeResult['description']?.toString().split(',').first) as String? ?? locationInfo.name;
          
          // Check if the name looks like just an address (contains street number and street name pattern)
          var isJustAddress = _isAddressOnly(name ?? '');
          String? website;
          
          // Always fetch place details if:
          // 1. We have a placeId but no coordinates, OR
          // 2. The name appears to be just an address (we need the actual business name)
          if (placeId != null && placeId.isNotEmpty && 
              (coordinates == null || isJustAddress)) {
            final reason = coordinates == null 
                ? 'No coordinates in search result'
                : 'Name appears to be just an address, fetching business name';
            print('📷 IMAGE EXTRACTION: $reason, fetching place details for: $placeId');
            try {
              final placeDetails = await _maps.getPlaceDetails(placeId);
              if (placeDetails.latitude != 0.0 || placeDetails.longitude != 0.0) {
                coordinates = LatLng(placeDetails.latitude, placeDetails.longitude);
                address = placeDetails.address ?? address;
                website = placeDetails.website;
                // Use the business name from place details if we had just an address
                final businessName = placeDetails.displayName ?? placeDetails.getPlaceName();
                if (isJustAddress && businessName.isNotEmpty) {
                  name = businessName;
                  print('📷 IMAGE EXTRACTION: Found business name from place details: $name');
                } else if (name == null || name.isEmpty) {
                  name = businessName;
                }
                print('📷 IMAGE EXTRACTION: Got coordinates from place details: ${coordinates.latitude}, ${coordinates.longitude}');
                if (website != null) {
                  print('📷 IMAGE EXTRACTION: Got website from place details: $website');
                }
              }
            } catch (e) {
              print('⚠️ IMAGE EXTRACTION: Error fetching place details: $e');
            }
          }
          
          // If we have a placeId but no website yet, fetch place details to get website
          if (placeId != null && placeId.isNotEmpty && website == null) {
            try {
              final placeDetails = await _maps.getPlaceDetails(placeId);
              website = placeDetails.website;
              if (website != null) {
                print('📷 IMAGE EXTRACTION: Fetched website: $website');
              }
            } catch (e) {
              print('⚠️ IMAGE EXTRACTION: Error fetching website from place details: $e');
            }
          }
          
          // If name is still just an address, try Nearby Search to find actual business at this location
          isJustAddress = _isAddressOnly(name ?? '');
          if (isJustAddress && coordinates != null) {
            print('📷 IMAGE EXTRACTION: Name is still an address, trying Nearby Search at coordinates...');
            try {
              // Use the original Gemini-extracted name as a hint for nearby search
              final nearbyResults = await _maps.searchNearbyPlaces(
                coordinates.latitude,
                coordinates.longitude,
                30, // 30 meter radius - very tight to get exact location
                locationInfo.name, // Use original name as search hint
              );
              
              if (nearbyResults.isNotEmpty) {
                final nearbyPlace = nearbyResults.first;
                final nearbyName = nearbyPlace['name'] as String?;
                if (nearbyName != null && nearbyName.isNotEmpty && !_isAddressOnly(nearbyName)) {
                  name = nearbyName;
                  // Update placeId if we got a new one
                  final nearbyPlaceId = nearbyPlace['placeId'] as String?;
                  print('📷 IMAGE EXTRACTION: Found business via Nearby Search: $name (placeId: $nearbyPlaceId)');
                  
                  // Fetch website for the nearby place if we got a new placeId
                  if (nearbyPlaceId != null && nearbyPlaceId.isNotEmpty) {
                    try {
                      final nearbyDetails = await _maps.getPlaceDetails(nearbyPlaceId);
                      website = nearbyDetails.website;
                      if (website != null) {
                        print('📷 IMAGE EXTRACTION: Got website from nearby place: $website');
                      }
                    } catch (e) {
                      print('⚠️ IMAGE EXTRACTION: Error fetching nearby place details: $e');
                    }
                  }
                }
              } else {
                print('📷 IMAGE EXTRACTION: No businesses found via Nearby Search, keeping address as name');
              }
            } catch (e) {
              print('⚠️ IMAGE EXTRACTION: Error during Nearby Search: $e');
            }
          }
          
          final extractedData = ExtractedLocationData(
            placeId: placeId,
            name: name,
            address: address,
            coordinates: coordinates,
            type: _inferPlaceTypeFromResult(placeResult, locationInfo.type),
            source: ExtractionSource.placesSearch,
            confidence: coordinates != null ? 0.85 : 0.60, // Higher confidence with coordinates
            placeTypes: (placeResult['types'] as List?)?.cast<String>(),
            website: website,
          );
          
          // Avoid duplicates
          if (!_isDuplicate(extractedData, results)) {
            results.add(extractedData);
            print('✅ IMAGE EXTRACTION: Verified location: ${extractedData.name} at ${coordinates?.latitude}, ${coordinates?.longitude}');
          }
        } else {
          // If Places API doesn't find it, still add with what we have
          print('⚠️ IMAGE EXTRACTION: Places API did not find match for: ${locationInfo.name}');
          
          // Add unverified location with lower confidence
          final unverifiedData = ExtractedLocationData(
            name: locationInfo.name,
            address: locationInfo.address,
            type: PlaceType.unknown,
            source: ExtractionSource.urlParsing, // Mark as unverified
            confidence: 0.50,
          );
          
          if (!_isDuplicate(unverifiedData, results)) {
            results.add(unverifiedData);
            print('📍 IMAGE EXTRACTION: Added unverified location: ${locationInfo.name}');
          }
        }
      }

      print('📷 IMAGE EXTRACTION: Extracted ${results.length} location(s) total');
      return results;
    } catch (e) {
      print('❌ IMAGE EXTRACTION ERROR: $e');
      return [];
    }
  }

  /// Extract locations from image bytes
  /// No limit on number of locations - extracts all found locations
  Future<List<ExtractedLocationData>> extractLocationsFromImageBytes(
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
    LatLng? userLocation,
  }) async {
    print('📷 IMAGE EXTRACTION: Starting extraction from image bytes...');
    
    try {
      // Step 1: Use Gemini Vision to extract location names
      final extractedNames = await _gemini.extractLocationNamesFromImage(
        imageBytes,
        mimeType: mimeType,
      );

      if (extractedNames.isEmpty) {
        print('⚠️ IMAGE EXTRACTION: No locations found in image');
        return [];
      }

      // Step 2: Verify with Places API
      final results = <ExtractedLocationData>[];
      
      for (final locationInfo in extractedNames) {
        
        // Strategy: Try multiple search queries to get the best result
        // 1. First try just the name (most specific, avoids locality confusion)
        // 2. If no good results, try name + city
        // 3. If still no results, try name + "Los Angeles" or other broad context
        
        List<Map<String, dynamic>> placeResults = [];
        Map<String, dynamic>? placeResult;
        
        // Attempt 1: Search with just the name
        print('📷 IMAGE EXTRACTION: Searching Places API for: ${locationInfo.name}');
        placeResults = await _maps.searchPlaces(
          locationInfo.name,
          latitude: userLocation?.latitude,
          longitude: userLocation?.longitude,
        );
        placeResult = _selectBestPlaceResult(placeResults, locationInfo.name);
        
        // Check if we got a good establishment result (not just a locality)
        bool gotGoodResult = false;
        if (placeResult != null) {
          final types = (placeResult['types'] as List?)?.cast<String>() ?? [];
          final isEstablishment = types.any((t) => 
            t == 'establishment' || t == 'point_of_interest' || t == 'food' || 
            t == 'restaurant' || t == 'cafe' || t == 'bar' || t == 'store');
          final isLocality = types.any((t) => 
            t == 'locality' || t == 'sublocality' || t == 'neighborhood' || t == 'political');
          gotGoodResult = isEstablishment || !isLocality;
        }
        
        // Attempt 2: If no good result and we have a city, try with city
        if (!gotGoodResult && locationInfo.city != null && locationInfo.city!.isNotEmpty) {
          final queryWithCity = '${locationInfo.name} ${locationInfo.city}';
          print('📷 IMAGE EXTRACTION: Retrying with city: $queryWithCity');
          final resultsWithCity = await _maps.searchPlaces(
            queryWithCity,
            latitude: userLocation?.latitude,
            longitude: userLocation?.longitude,
          );
          final resultWithCity = _selectBestPlaceResult(resultsWithCity, locationInfo.name);
          
          // Only use this result if it's better (is an establishment)
          if (resultWithCity != null) {
            final types = (resultWithCity['types'] as List?)?.cast<String>() ?? [];
            final isEstablishment = types.any((t) => 
              t == 'establishment' || t == 'point_of_interest' || t == 'food' || 
              t == 'restaurant' || t == 'cafe' || t == 'bar' || t == 'store');
            if (isEstablishment || placeResult == null) {
              placeResult = resultWithCity;
              gotGoodResult = true;
            }
          }
        }
        
        // Attempt 3: If still no results and we have type info, try name + type
        if (placeResult == null && locationInfo.type != null) {
          final queryWithType = '${locationInfo.name} ${locationInfo.type}';
          print('📷 IMAGE EXTRACTION: Retrying with type: $queryWithType');
          final resultsWithType = await _maps.searchPlaces(
            queryWithType,
            latitude: userLocation?.latitude,
            longitude: userLocation?.longitude,
          );
          placeResult = _selectBestPlaceResult(resultsWithType, locationInfo.name);
        }
        
        if (placeResult != null) {
          // Handle both camelCase and snake_case field names
          final placeId = (placeResult['placeId'] ?? placeResult['place_id']) as String?;
          var coordinates = _extractCoordinates(placeResult);
          var address = (placeResult['formatted_address'] ?? placeResult['address'] ?? placeResult['description']) as String?;
          var name = (placeResult['name'] ?? placeResult['description']?.toString().split(',').first) as String? ?? locationInfo.name;
          
          // Check if the name looks like just an address (contains street number and street name pattern)
          var isJustAddress = _isAddressOnly(name ?? '');
          String? website;
          
          // Always fetch place details if:
          // 1. We have a placeId but no coordinates, OR
          // 2. The name appears to be just an address (we need the actual business name)
          if (placeId != null && placeId.isNotEmpty && 
              (coordinates == null || isJustAddress)) {
            final reason = coordinates == null 
                ? 'No coordinates in search result'
                : 'Name appears to be just an address, fetching business name';
            print('📷 IMAGE EXTRACTION: $reason, fetching place details for: $placeId');
            try {
              final placeDetails = await _maps.getPlaceDetails(placeId);
              if (placeDetails.latitude != 0.0 || placeDetails.longitude != 0.0) {
                coordinates = LatLng(placeDetails.latitude, placeDetails.longitude);
                address = placeDetails.address ?? address;
                website = placeDetails.website;
                // Use the business name from place details if we had just an address
                final businessName = placeDetails.displayName ?? placeDetails.getPlaceName();
                if (isJustAddress && businessName.isNotEmpty) {
                  name = businessName;
                  print('📷 IMAGE EXTRACTION: Found business name from place details: $name');
                } else if (name == null || name.isEmpty) {
                  name = businessName;
                }
                if (website != null) {
                  print('📷 IMAGE EXTRACTION: Got website from place details: $website');
                }
              }
            } catch (e) {
              print('⚠️ IMAGE EXTRACTION: Error fetching place details: $e');
            }
          }
          
          // If we have a placeId but no website yet, fetch place details to get website
          if (placeId != null && placeId.isNotEmpty && website == null) {
            try {
              final placeDetails = await _maps.getPlaceDetails(placeId);
              website = placeDetails.website;
              if (website != null) {
                print('📷 IMAGE EXTRACTION: Fetched website: $website');
              }
            } catch (e) {
              print('⚠️ IMAGE EXTRACTION: Error fetching website from place details: $e');
            }
          }
          
          // If name is still just an address, try Nearby Search to find actual business at this location
          isJustAddress = _isAddressOnly(name ?? '');
          if (isJustAddress && coordinates != null) {
            print('📷 IMAGE EXTRACTION: Name is still an address, trying Nearby Search at coordinates...');
            try {
              // Use the original Gemini-extracted name as a hint for nearby search
              final nearbyResults = await _maps.searchNearbyPlaces(
                coordinates.latitude,
                coordinates.longitude,
                30, // 30 meter radius - very tight to get exact location
                locationInfo.name, // Use original name as search hint
              );
              
              if (nearbyResults.isNotEmpty) {
                final nearbyPlace = nearbyResults.first;
                final nearbyName = nearbyPlace['name'] as String?;
                if (nearbyName != null && nearbyName.isNotEmpty && !_isAddressOnly(nearbyName)) {
                  name = nearbyName;
                  print('📷 IMAGE EXTRACTION: Found business via Nearby Search: $name');
                  
                  // Fetch website for the nearby place if we got a new placeId
                  final nearbyPlaceId = nearbyPlace['placeId'] as String?;
                  if (nearbyPlaceId != null && nearbyPlaceId.isNotEmpty) {
                    try {
                      final nearbyDetails = await _maps.getPlaceDetails(nearbyPlaceId);
                      website = nearbyDetails.website;
                      if (website != null) {
                        print('📷 IMAGE EXTRACTION: Got website from nearby place: $website');
                      }
                    } catch (e) {
                      print('⚠️ IMAGE EXTRACTION: Error fetching nearby place details: $e');
                    }
                  }
                }
              } else {
                print('📷 IMAGE EXTRACTION: No businesses found via Nearby Search, keeping address as name');
              }
            } catch (e) {
              print('⚠️ IMAGE EXTRACTION: Error during Nearby Search: $e');
            }
          }
          
          final extractedData = ExtractedLocationData(
            placeId: placeId,
            name: name,
            address: address,
            coordinates: coordinates,
            type: _inferPlaceTypeFromResult(placeResult, locationInfo.type),
            source: ExtractionSource.placesSearch,
            confidence: coordinates != null ? 0.85 : 0.60,
            placeTypes: (placeResult['types'] as List?)?.cast<String>(),
            website: website,
          );
          
          if (!_isDuplicate(extractedData, results)) {
            results.add(extractedData);
          }
        }
      }

      print('📷 IMAGE EXTRACTION: Extracted ${results.length} location(s)');
      return results;
    } catch (e) {
      print('❌ IMAGE EXTRACTION ERROR: $e');
      return [];
    }
  }

  /// Select the best place result from a list, preferring businesses over neighborhoods
  /// 
  /// When searching for "@kuyalord_la (East Hollywood)", we might get:
  /// 1. "East Hollywood, LA, CA, USA" (locality - NOT what we want)
  /// 2. "Kuya Lord, Melrose Avenue..." (establishment - WHAT WE WANT)
  /// 
  /// This method picks the best match by:
  /// 1. Preferring establishments (restaurants, cafes, shops) over localities/neighborhoods
  /// 2. Preferring results whose name contains the original search term
  Map<String, dynamic>? _selectBestPlaceResult(
    List<Map<String, dynamic>> results,
    String originalName,
  ) {
    if (results.isEmpty) return null;
    if (results.length == 1) return results.first;
    
    // Normalize the original name for comparison
    final normalizedOriginal = _normalizeForComparison(originalName);
    
    // Types that indicate a locality/neighborhood (NOT what we want)
    const localityTypes = [
      'locality',
      'sublocality',
      'sublocality_level_1',
      'neighborhood',
      'administrative_area_level_1',
      'administrative_area_level_2',
      'administrative_area_level_3',
      'political',
    ];
    
    // Types that indicate an establishment/business (what we WANT)
    const establishmentTypes = [
      'establishment',
      'point_of_interest',
      'food',
      'restaurant',
      'cafe',
      'bar',
      'store',
      'shopping_mall',
      'meal_delivery',
      'meal_takeaway',
      'bakery',
      'night_club',
      'tourist_attraction',
      'museum',
      'park',
    ];
    
    Map<String, dynamic>? bestResult;
    int bestScore = -1;
    
    for (final result in results) {
      int score = 0;
      
      // Get the result name and types
      final resultName = (result['name'] ?? result['description']?.toString().split(',').first ?? '') as String;
      final normalizedResultName = _normalizeForComparison(resultName);
      final types = (result['types'] as List?)?.cast<String>() ?? [];
      
      // Score based on name similarity
      if (normalizedResultName.contains(normalizedOriginal) || 
          normalizedOriginal.contains(normalizedResultName)) {
        score += 50; // Strong match
      }
      
      // Check if the original name words appear in the result
      final originalWords = normalizedOriginal.split(RegExp(r'\s+')).where((w) => w.length > 2);
      for (final word in originalWords) {
        if (normalizedResultName.contains(word)) {
          score += 10;
        }
      }
      
      // Penalize locality/neighborhood results
      for (final type in types) {
        if (localityTypes.contains(type)) {
          score -= 30;
          break;
        }
      }
      
      // Boost establishment/business results
      for (final type in types) {
        if (establishmentTypes.contains(type)) {
          score += 25;
          break;
        }
      }
      
      // Log scoring for debugging
      print('📷 IMAGE EXTRACTION: Scoring "$resultName" = $score (types: ${types.take(3).join(", ")})');
      
      if (score > bestScore) {
        bestScore = score;
        bestResult = result;
      }
    }
    
    if (bestResult != null) {
      final selectedName = (bestResult['name'] ?? bestResult['description']?.toString().split(',').first ?? '') as String;
      print('📷 IMAGE EXTRACTION: Selected best result: "$selectedName" (score: $bestScore)');
    }
    
    return bestResult ?? results.first;
  }
  
  /// Normalize a string for comparison (lowercase, remove special chars)
  String _normalizeForComparison(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Extract coordinates from Places API result
  /// Handles multiple possible structures from different Places API versions
  LatLng? _extractCoordinates(Map<String, dynamic> placeResult) {
    try {
      // Try legacy Places API structure first: geometry.location.lat/lng
      final geometry = placeResult['geometry'] as Map<String, dynamic>?;
      if (geometry != null) {
        final location = geometry['location'] as Map<String, dynamic>?;
        if (location != null) {
          final lat = (location['lat'] as num?)?.toDouble();
          final lng = (location['lng'] as num?)?.toDouble();
          if (lat != null && lng != null && (lat != 0.0 || lng != 0.0)) {
            print('📍 IMAGE EXTRACTION: Extracted coordinates (legacy): $lat, $lng');
            return LatLng(lat, lng);
          }
        }
      }

      // Try new Places API v1 structure: location.latitude/longitude
      final locationV1 = placeResult['location'] as Map<String, dynamic>?;
      if (locationV1 != null) {
        final lat = (locationV1['latitude'] as num?)?.toDouble();
        final lng = (locationV1['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null && (lat != 0.0 || lng != 0.0)) {
          print('📍 IMAGE EXTRACTION: Extracted coordinates (v1): $lat, $lng');
          return LatLng(lat, lng);
        }
      }

      // Try direct lat/lng fields (some responses have these at top level)
      final directLat = (placeResult['lat'] as num?)?.toDouble();
      final directLng = (placeResult['lng'] as num?)?.toDouble();
      if (directLat != null && directLng != null && (directLat != 0.0 || directLng != 0.0)) {
        print('📍 IMAGE EXTRACTION: Extracted coordinates (direct): $directLat, $directLng');
        return LatLng(directLat, directLng);
      }

      print('⚠️ IMAGE EXTRACTION: No valid coordinates found in place result');
    } catch (e) {
      print('⚠️ IMAGE EXTRACTION: Error extracting coordinates: $e');
    }
    return null;
  }

  /// Check if a string appears to be just an address (not a business name)
  /// Returns true if it contains a street number and street suffix (Blvd, St, Ave, etc.)
  bool _isAddressOnly(String text) {
    if (text.isEmpty) return false;
    
    // Common street suffixes
    final streetSuffixes = [
      'blvd', 'boulevard', 'st', 'street', 'ave', 'avenue', 'rd', 'road',
      'dr', 'drive', 'ln', 'lane', 'ct', 'court', 'pl', 'place', 'way',
      'pkwy', 'parkway', 'cir', 'circle', 'ter', 'terrace', 'hwy', 'highway'
    ];
    
    // Check if text contains a street number pattern (digits followed by optional letter)
    // and a street suffix
    final hasStreetNumber = RegExp(r'^\d+[a-z]?\s+', caseSensitive: false).hasMatch(text);
    final hasStreetSuffix = streetSuffixes.any((suffix) => 
      text.toLowerCase().contains(suffix));
    
    // If it has both a street number and suffix, it's likely just an address
    if (hasStreetNumber && hasStreetSuffix) {
      // But exclude cases where it's clearly a business name with address
      // (e.g., "McDonald's 123 Main St" - has business name first)
      final words = text.split(RegExp(r'\s+'));
      // If first word is a number, it's likely just an address
      if (words.isNotEmpty && RegExp(r'^\d+').hasMatch(words.first)) {
        return true;
      }
    }
    
    return false;
  }

  /// Infer place type from Places API result and Vision hint
  PlaceType _inferPlaceTypeFromResult(Map<String, dynamic> placeResult, String? visionHint) {
    final types = (placeResult['types'] as List?)?.cast<String>() ?? [];
    
    // Use Places API types first
    if (types.isNotEmpty) {
      return ExtractedLocationData.inferPlaceType(types);
    }
    
    // Fall back to Vision hint
    if (visionHint != null) {
      final hint = visionHint.toLowerCase();
      if (hint.contains('restaurant') || hint.contains('food')) return PlaceType.restaurant;
      if (hint.contains('cafe') || hint.contains('coffee')) return PlaceType.cafe;
      if (hint.contains('bar') || hint.contains('pub')) return PlaceType.bar;
      if (hint.contains('hotel') || hint.contains('lodging')) return PlaceType.hotel;
      if (hint.contains('store') || hint.contains('shop')) return PlaceType.store;
      if (hint.contains('museum')) return PlaceType.museum;
      if (hint.contains('park')) return PlaceType.park;
      if (hint.contains('attraction') || hint.contains('landmark')) return PlaceType.attraction;
    }
    
    return PlaceType.unknown;
  }

  // ============ END IMAGE/SCREENSHOT EXTRACTION METHODS ============
}
