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


  /// Extract locations from a shared URL
  ///
  /// [url] - The URL to analyze
  /// [userLocation] - Optional user location for better results
  /// [maxLocations] - Maximum number of locations to return (default: 10, null = unlimited)
  ///
  /// Returns a list of [ExtractedLocationData] objects, one for each
  /// location found in the URL. May return an empty list if no locations found.
  Future<List<ExtractedLocationData>> extractLocationsFromSharedLink(
    String url, {
    LatLng? userLocation,
    int? maxLocations,
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

    // Limit results (only if maxLocations is specified)
    if (maxLocations != null && results.length > maxLocations) {
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
  /// [maxLocations] - Maximum number of locations to return (default: 10, null = unlimited)
  ///
  /// Returns a list of [ExtractedLocationData] objects found in the caption.
  Future<List<ExtractedLocationData>> extractLocationsFromCaption(
    String caption, {
    String platform = 'social media',
    String? authorName,
    String? sourceUrl,
    LatLng? userLocation,
    int? maxLocations,
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
        // Generic regions/counties to skip - these are too vague to be useful
        final genericRegions = {
          'orange county', 'los angeles county', 'san diego county', 'riverside county',
          'san bernardino county', 'ventura county', 'santa barbara county',
          'california', 'southern california', 'northern california',
          'united states', 'usa', 'america',
        };
        
        // Filter grounding chunks to only include ones whose names appear in the caption
        final lowerCaption = caption.toLowerCase();
        final relevantLocations = geminiResult.locations.where((location) {
          final nameLower = location.name.toLowerCase().trim();
          
          // Skip generic region/county names
          if (genericRegions.contains(nameLower)) {
            print('⏭️ CAPTION: Skipping generic region/county: "${location.name}"');
            return false;
          }
          
          final nameParts = nameLower.split(' ');
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
        final locationsToProcess = maxLocations != null ? relevantLocations.take(maxLocations) : relevantLocations;
        for (final location in locationsToProcess) {
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
          
          // Filter parsed locations to only include ones that are actually meaningful
          // (not Facebook UI noise like "University of... 1" or generic words)
          final filteredParsed = parsedLocations.where((parsed) {
            final name = parsed['name'] as String?;
            if (name == null || name.isEmpty) return false;
            
            final nameLower = name.toLowerCase();
            
            // Skip generic single-word names that are too vague
            final genericSingleWords = ['university', 'restaurant', 'cafe', 'store', 'shop', 'hotel', 'bar', 'club', 'gym', 'park'];
            if (!nameLower.contains(' ') && genericSingleWords.contains(nameLower)) {
              print('⏭️ CAPTION: Skipping generic single-word location: "$name"');
              return false;
            }
            
            // Skip generic region/county names - these are too vague to be useful
            final genericRegions = [
              'orange county', 'los angeles county', 'san diego county', 'riverside county',
              'san bernardino county', 'ventura county', 'santa barbara county',
              'california', 'southern california', 'northern california',
              'united states', 'usa', 'america',
              'los angeles', 'new york city', 'san francisco', // Skip cities when they appear alone as the only result
            ];
            if (genericRegions.contains(nameLower)) {
              print('⏭️ CAPTION: Skipping generic region/county: "$name"');
              return false;
            }
            
            // Verify the location name actually appears in the caption meaningfully
            // (not just scattered words or partial matches)
            final lowerCaption = caption.toLowerCase();
            
            // For multi-word names, check if at least 2 significant words appear together or nearby
            final nameWords = nameLower.split(' ').where((w) => w.length > 2).toList();
            if (nameWords.length >= 2) {
              int matchCount = 0;
              for (final word in nameWords) {
                if (lowerCaption.contains(word)) {
                  matchCount++;
                }
              }
              // Require at least 60% of words to be present
              if (matchCount / nameWords.length < 0.6) {
                print('⏭️ CAPTION: Skipping "$name" - not enough words found in caption ($matchCount/${nameWords.length})');
                return false;
              }
            }
            
            return true;
          }).toList();
          
          if (filteredParsed.isEmpty && parsedLocations.isNotEmpty) {
            print('⚠️ CAPTION EXTRACTION: All ${parsedLocations.length} parsed location(s) were filtered out as noise');
          }
          
          final parsedToProcess = maxLocations != null ? filteredParsed.take(maxLocations) : filteredParsed;
          for (final parsed in parsedToProcess) {
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
    // Note: Short abbreviations like 'la', 'sf', 'oc' are handled separately with word boundary checks
    final caCities = [
      'anaheim', 'los angeles', 'san diego', 'san francisco',
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
      'westminster', 'fountain valley', 'tustin', 'lake forest', 'mission viejo',
      'rancho santa margarita', 'aliso viejo', 'dana point', 'san clemente',
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
    
    // Check for regional abbreviations (use word boundaries for short ones)
    for (final entry in regions.entries) {
      // Use word boundary matching for short region keys (< 4 chars) to avoid false matches
      bool hasMatch;
      if (entry.key.length < 4) {
        final regionPattern = RegExp(r'\b' + RegExp.escape(entry.key) + r'\b', caseSensitive: false);
        hasMatch = regionPattern.hasMatch(lowerCaption);
      } else {
        hasMatch = lowerCaption.contains(entry.key);
      }
      
      if (hasMatch) {
        print('🏙️ CONTEXT: Found region: ${entry.key}');
        // For regions like "OC", try to find a more specific city
        // If "OC" is found, look for nearby city mentions
        if (entry.key == 'oc' || entry.key == 'orange county') {
          // Check for specific OC cities
          for (final city in ['anaheim', 'irvine', 'santa ana', 'costa mesa', 
                              'newport beach', 'huntington beach', 'fullerton', 
                              'garden grove', 'orange', 'tustin', 'westminster',
                              'fountain valley', 'garden grove']) {
            final cityPattern = RegExp(r'\b' + RegExp.escape(city) + r'\b', caseSensitive: false);
            if (cityPattern.hasMatch(lowerCaption)) {
              print('🏙️ CONTEXT: Found specific OC city: $city');
              return city;
            }
          }
        }
        return entry.value;
      }
    }
    
    // Check caption text for any city mention (use word boundary matching)
    for (final city in caCities) {
      // Use word boundary regex to avoid matching "la" inside "La Verne" or "Lam Dong"
      final cityPattern = RegExp(r'\b' + RegExp.escape(city) + r'\b', caseSensitive: false);
      if (cityPattern.hasMatch(lowerCaption)) {
        print('🏙️ CONTEXT: Found city mention: $city');
        return city;
      }
    }
    for (final city in usCities) {
      final cityPattern = RegExp(r'\b' + RegExp.escape(city) + r'\b', caseSensitive: false);
      if (cityPattern.hasMatch(lowerCaption)) {
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
      
      // Search with user location bias if available
      List<Map<String, dynamic>> results;
      if (userLocation != null) {
        results = await _maps.searchPlaces(
          searchQuery,
          latitude: userLocation.latitude,
          longitude: userLocation.longitude,
        );
      } else {
        results = await _maps.searchPlaces(searchQuery);
      }
      
      if (results.isEmpty) {
        print('⚠️ PLACES RESOLVE: No results for "$searchQuery"');
        return null;
      }

      // Use the sophisticated scoring method to find the best match
      // This properly handles name matching with compact comparison
      final bestResult = _selectBestPlaceResult(results, locationName);
      
      if (bestResult == null) {
        print('⚠️ PLACES RESOLVE: No good match found for "$locationName"');
        return null;
      }
      
      // Validate the result is actually a good match (not just any result)
      final resultName = (bestResult['name'] ?? bestResult['description']?.toString().split(',').first ?? '') as String;
      final normalizedResultName = _normalizeCompact(resultName);
      final normalizedLocationName = _normalizeCompact(locationName);
      
      // Check if the names have reasonable overlap
      // Include ALL significant words (length > 1 to include "My" in "Thanh My Restaurant")
      final locationWords = locationName.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
      final resultNameLower = resultName.toLowerCase();
      int matchedWords = 0;
      for (final word in locationWords) {
        if (resultNameLower.contains(word)) {
          matchedWords++;
        }
      }
      
      final matchRatio = locationWords.isEmpty ? 0.0 : matchedWords / locationWords.length;
      
      // Stricter validation for specific place names:
      // 1. Exact compact match is always good
      // 2. If result is much shorter than search term, require higher word match
      // 3. Generic words like "Restaurant" alone are not good matches for specific names
      final bool isExactMatch = normalizedResultName == normalizedLocationName;
      final bool resultContainsSearch = normalizedResultName.contains(normalizedLocationName);
      final bool searchContainsResult = normalizedLocationName.contains(normalizedResultName);
      
      // If search contains result (e.g., "thanhmyrestaurant" contains "restaurant"),
      // check if result is significantly shorter - if so, it's probably too generic
      bool hasGoodNameMatch = false;
      if (isExactMatch) {
        hasGoodNameMatch = true;
        print('🎯 PLACES RESOLVE: Exact name match');
      } else if (resultContainsSearch) {
        hasGoodNameMatch = true;
        print('🎯 PLACES RESOLVE: Result contains full search term');
      } else if (searchContainsResult) {
        // Result is shorter - check if it's a reasonable match
        final lengthRatio = normalizedResultName.length / normalizedLocationName.length;
        // Require result to be at least 60% of the search term length
        // AND at least 60% word match
        if (lengthRatio >= 0.6 && matchRatio >= 0.6) {
          hasGoodNameMatch = true;
          print('🎯 PLACES RESOLVE: Partial match with good overlap (length: ${(lengthRatio * 100).toInt()}%, words: ${(matchRatio * 100).toInt()}%)');
        } else {
          print('⚠️ PLACES RESOLVE: Result "$resultName" is too short/generic for "$locationName" (length: ${(lengthRatio * 100).toInt()}%, words: ${(matchRatio * 100).toInt()}%)');
        }
      } else if (matchRatio >= 0.7) {
        // High word match even without containment
        hasGoodNameMatch = true;
        print('🎯 PLACES RESOLVE: High word match (${(matchRatio * 100).toInt()}%)');
      }
      
      if (!hasGoodNameMatch) {
        print('⚠️ PLACES RESOLVE: Best result "$resultName" doesn\'t match "$locationName" well enough');
        print('   Will add location without coordinates (user can set manually)');
        return null;
      }
      
      print('🎯 PLACES RESOLVE: Selected best match: "$resultName"');

      final placeId = bestResult['placeId'] as String?;
      
      // Autocomplete doesn't return coordinates - need to call Place Details API
      LatLng? coords;
      String? resolvedAddress;
      String? resolvedName;
      String? website;
      
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
          website = placeDetails.website;
          
          print('✅ PLACES RESOLVE: Got details - "${resolvedName}" at $coords');
          if (website != null) {
            print('🌐 PLACES RESOLVE: Got website: $website');
          }
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
        website: website,
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
    int? maxLocations,
  ) async {
    try {
      // YouTube URLs: Use native video analysis (Gemini can watch the video!)
      if (_isYouTubeUrl(url)) {
        print('🎬 EXTRACTION: Detected YouTube URL - using native video analysis');
        final youtubeResult = await _gemini.extractLocationsFromYouTubeVideo(
          url,
          userLocation: userLocation,
        );
        
        if (youtubeResult != null && youtubeResult.locations.isNotEmpty) {
          print('✅ EXTRACTION: Found ${youtubeResult.locationCount} location(s) from YouTube video');
          
          // Resolve each location via Places API to get real coordinates
          final resolvedLocations = await _resolveYouTubeLocations(
            youtubeResult.locations,
            userLocation: userLocation,
            maxLocations: maxLocations,
          );
          
          if (resolvedLocations.isNotEmpty) {
            return resolvedLocations;
          }
        } else {
          print('⚠️ EXTRACTION: No locations found in YouTube video, trying metadata fallback');
          // Fall through to metadata extraction as backup
        }
      }

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
      if (_isSocialMediaUrl(url) && !_isInstagramUrl(url) && !_isYouTubeUrl(url)) {
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
    int? maxLocations,
  ) {
    final extractedList = <ExtractedLocationData>[];

    // Take all locations if maxLocations is null (unlimited), otherwise take the specified limit
    final locationsToProcess = maxLocations != null ? result.locations.take(maxLocations) : result.locations;

    for (final location in locationsToProcess) {
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

  /// Resolve YouTube video locations via Places API
  ///
  /// YouTube video analysis returns location names and cities, but not coordinates.
  /// This method resolves each location to get real Place IDs and coordinates.
  Future<List<ExtractedLocationData>> _resolveYouTubeLocations(
    List<GoogleMapsLocation> locations,
    {LatLng? userLocation, int? maxLocations}
  ) async {
    final results = <ExtractedLocationData>[];
    final seenPlaceIds = <String>{};
    final seenNames = <String>{};
    
    print('🎬 YOUTUBE: Resolving ${locations.length} location(s) via Places API...');

    // Take all locations if maxLocations is null (unlimited), otherwise take the specified limit
    final locationsToProcess = maxLocations != null ? locations.take(maxLocations) : locations;

    for (final location in locationsToProcess) {
      // Skip duplicates by name
      final normalizedName = location.name.toLowerCase().trim();
      if (seenNames.contains(normalizedName)) {
        print('⏭️ YOUTUBE: Skipping duplicate name: "${location.name}"');
        continue;
      }
      seenNames.add(normalizedName);
      
      // Build location context from city info
      final locationContext = location.city;
      
      print('🔍 YOUTUBE: Resolving "${location.name}" (${locationContext ?? "no city"})...');
      
      final resolvedLocation = await _resolveLocationWithPlacesApi(
        location.name,
        address: location.formattedAddress,
        locationContext: locationContext,
        userLocation: userLocation,
      );
      
      if (resolvedLocation != null) {
        // Skip if we've already added this Place ID
        if (resolvedLocation.placeId != null && seenPlaceIds.contains(resolvedLocation.placeId)) {
          print('⏭️ YOUTUBE: Skipping duplicate Place ID: ${resolvedLocation.placeId}');
          continue;
        }
        if (resolvedLocation.placeId != null) {
          seenPlaceIds.add(resolvedLocation.placeId!);
        }
        
        print('✅ YOUTUBE: Resolved "${location.name}" → ${resolvedLocation.name} (${resolvedLocation.coordinates?.latitude}, ${resolvedLocation.coordinates?.longitude})');
        results.add(resolvedLocation);
      } else {
        // Still add without coordinates - user can manually set location
        print('⚠️ YOUTUBE: Could not resolve "${location.name}", adding without coords');
        results.add(ExtractedLocationData(
          placeId: null,
          name: location.name,
          address: location.city != null ? location.city : null,
          coordinates: null, // No coordinates - don't use placeholder (0,0)
          type: PlaceType.unknown,
          source: ExtractionSource.geminiGrounding,
          confidence: 0.5, // Lower confidence without coords
        ));
      }
    }
    
    print('🎬 YOUTUBE: Resolved ${results.length}/${locations.length} location(s)');
    return results;
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

      // Use best result selection for consistent scoring across all preview scans
      final firstResult = _selectBestPlaceResult(results, searchQuery) ?? results.first;
      
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

  /// Check if URL is a YouTube video URL
  bool _isYouTubeUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('youtube.com/watch') ||
           lower.contains('youtube.com/shorts') ||
           lower.contains('youtu.be/') ||
           lower.contains('youtube.com/embed');
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

  /// Check if a Places API result is just a city/locality rather than a specific business
  bool _isJustCityResult(String description, String cityContext) {
    final lower = description.toLowerCase();
    
    // Common patterns for city-only results
    // e.g., "Costa Mesa, CA, USA" or "Newport Beach, California, USA"
    final cityPatterns = [
      RegExp(r'^[^,]+,\s*(ca|california|tx|texas|ny|new york|fl|florida|az|arizona)[,\s]', caseSensitive: false),
      RegExp(r'^[^,]+,\s*[a-z]{2},\s*usa$', caseSensitive: false),
    ];
    
    for (final pattern in cityPatterns) {
      if (pattern.hasMatch(lower)) {
        // Make sure it's not a business with a comma in the name
        final firstPart = lower.split(',').first.trim();
        // If the first part exactly matches the city context, it's just a city
        if (cityContext.isNotEmpty && firstPart == cityContext.toLowerCase()) {
          return true;
        }
        // Check if it looks like just "CityName, State, Country"
        final parts = lower.split(',').map((p) => p.trim()).toList();
        if (parts.length <= 3 && parts.first.split(' ').length <= 3) {
          // Likely just a city (e.g., "Costa Mesa, CA, USA")
          return true;
        }
      }
    }
    
    return false;
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

      // Check by coordinates proximity (skip if either has placeholder coordinates 0,0)
      // Only consider as duplicate if BOTH names are similar AND coordinates are close
      // This allows different businesses in the same shopping center to be extracted
      if (newLocation.coordinates != null && loc.coordinates != null) {
        // Skip if either location has placeholder coordinates (0, 0)
        final isNewPlaceholder = newLocation.coordinates!.latitude == 0 && newLocation.coordinates!.longitude == 0;
        final isExistingPlaceholder = loc.coordinates!.latitude == 0 && loc.coordinates!.longitude == 0;
        
        if (!isNewPlaceholder && !isExistingPlaceholder) {
          final distance = _calculateDistance(
            newLocation.coordinates!, 
            loc.coordinates!,
          );
          // Only flag as duplicate if VERY close (< 10m) - same exact location
          // Different restaurants in same mall (20-50m apart) should NOT be duplicates
          if (distance < 10) {
            print('⚠️ DUPLICATE CHECK: Same location (${distance.toStringAsFixed(0)}m): "${newLocation.name}" vs "${loc.name}"');
            return true;
          }
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

      // Get the region context from the first location (all locations share the same context)
      final regionContext = extractedNames.isNotEmpty ? extractedNames.first.regionContext : null;
      
      print('📷 IMAGE EXTRACTION: Gemini found ${extractedNames.length} potential location(s), verifying with Places API...');
      if (regionContext != null) {
        print('🌍 IMAGE EXTRACTION: Region context: "$regionContext"');
      }

      // Step 2: Verify each location with Google Places API
      final results = <ExtractedLocationData>[];
      
      for (final locationInfo in extractedNames) {
        
        // Build search query from extracted info - USE REGION CONTEXT for disambiguation
        // This is CRITICAL: "Tacoma" + "Washington" → Tacoma, WA (correct)
        //                   "Tacoma" alone with CA location bias → Tacomasa restaurant (WRONG!)
        final effectiveRegionContext = locationInfo.regionContext ?? regionContext;
        
        String searchQuery = locationInfo.name;
        if (locationInfo.address != null) {
          searchQuery += ' ${locationInfo.address}';
        }
        if (locationInfo.city != null) {
          searchQuery += ', ${locationInfo.city}';
        }
        // Add region context for better disambiguation
        if (effectiveRegionContext != null && effectiveRegionContext.isNotEmpty) {
          searchQuery += ', $effectiveRegionContext';
        }
        
        print('📷 IMAGE EXTRACTION: Searching Places API for: $searchQuery');
        
        // Search Places API
        final placeResults = await _maps.searchPlaces(
          searchQuery,
          latitude: userLocation?.latitude,
          longitude: userLocation?.longitude,
        );
        
        // Use best result selection to prefer exact name matches and respect Gemini's type hints
        final placeResult = _selectBestPlaceResult(placeResults, locationInfo.name, geminiType: locationInfo.type);
        
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

      // Get the region context from the first location (all locations share the same context)
      final regionContext = extractedNames.isNotEmpty ? extractedNames.first.regionContext : null;
      
      // Log what Gemini found for debugging
      print('📷 IMAGE EXTRACTION: Gemini returned ${extractedNames.length} location(s):');
      if (regionContext != null) {
        print('🌍 IMAGE EXTRACTION: Region context: "$regionContext"');
      }
      for (final loc in extractedNames) {
        print('   📍 Name: "${loc.name}", City: "${loc.city}", Type: "${loc.type}", Address: "${loc.address}"');
      }

      // Step 2: Verify with Places API
      final results = <ExtractedLocationData>[];
      
      for (final locationInfo in extractedNames) {
        
        // Strategy: Try multiple search queries to get the best result
        // 1. First try name + region context (most accurate for disambiguation)
        // 2. If no good results, try name + city
        // 3. If still no results, try just the name
        
        List<Map<String, dynamic>> placeResults = [];
        Map<String, dynamic>? placeResult;
        
        // Build search query - use region context for disambiguation
        // This is CRITICAL: "Tacoma" + "Washington" → Tacoma, WA (correct)
        //                   "Tacoma" alone with CA location bias → Tacomasa restaurant (WRONG!)
        String searchQuery = locationInfo.name;
        
        // Use region context if available (from Gemini's analysis of overall content)
        final effectiveRegionContext = locationInfo.regionContext ?? regionContext;
        
        if (effectiveRegionContext != null && effectiveRegionContext.isNotEmpty) {
          // Append region context to help Places API find the right location
          searchQuery = '${locationInfo.name}, $effectiveRegionContext';
          print('📷 IMAGE EXTRACTION: Searching Places API for: $searchQuery (with region context)');
        } else if (locationInfo.city != null && locationInfo.city!.isNotEmpty) {
          searchQuery = '${locationInfo.name}, ${locationInfo.city}';
          print('📷 IMAGE EXTRACTION: Searching Places API for: $searchQuery (with city)');
        } else {
          print('📷 IMAGE EXTRACTION: Searching Places API for: ${locationInfo.name}');
        }
        
        placeResults = await _maps.searchPlaces(
          searchQuery,
          latitude: userLocation?.latitude,
          longitude: userLocation?.longitude,
        );
        placeResult = _selectBestPlaceResult(placeResults, locationInfo.name, geminiType: locationInfo.type);
        
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
        
        // Attempt 2: If no good result and we have a city, try with city (+ region context)
        if (!gotGoodResult && locationInfo.city != null && locationInfo.city!.isNotEmpty) {
          // Include region context for better disambiguation
          String queryWithCity = '${locationInfo.name}, ${locationInfo.city}';
          if (effectiveRegionContext != null && effectiveRegionContext.isNotEmpty) {
            queryWithCity = '${locationInfo.name}, ${locationInfo.city}, $effectiveRegionContext';
          }
          print('📷 IMAGE EXTRACTION: Retrying with city: $queryWithCity');
          final resultsWithCity = await _maps.searchPlaces(
            queryWithCity,
            latitude: userLocation?.latitude,
            longitude: userLocation?.longitude,
          );
          final resultWithCity = _selectBestPlaceResult(resultsWithCity, locationInfo.name, geminiType: locationInfo.type);
          
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
        
        // Attempt 3: If still no results and we have type info, try name + type (+ region context)
        if (placeResult == null && locationInfo.type != null) {
          String queryWithType = '${locationInfo.name} ${locationInfo.type}';
          if (effectiveRegionContext != null && effectiveRegionContext.isNotEmpty) {
            queryWithType = '${locationInfo.name} ${locationInfo.type}, $effectiveRegionContext';
          }
          print('📷 IMAGE EXTRACTION: Retrying with type: $queryWithType');
          final resultsWithType = await _maps.searchPlaces(
            queryWithType,
            latitude: userLocation?.latitude,
            longitude: userLocation?.longitude,
          );
          placeResult = _selectBestPlaceResult(resultsWithType, locationInfo.name, geminiType: locationInfo.type);
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

  /// Select the best place result from a list, preferring exact name matches and respecting Gemini's type hints
  /// 
  /// When searching for "@kuyalord_la (East Hollywood)", we might get:
  /// 1. "East Hollywood, LA, CA, USA" (locality - NOT what we want)
  /// 2. "Kuya Lord, Melrose Avenue..." (establishment - WHAT WE WANT)
  /// 
  /// When searching for "Hoh Rainforest" (park type), we might get:
  /// 1. "Hoh Rainforest Visitor Center" (establishment)
  /// 2. "Hoh Rain Forest" (national_park) - WHAT WE WANT
  /// 
  /// This method picks the best match by:
  /// 1. STRONGLY preferring exact/close name matches (most important!)
  /// 2. Using Gemini's type hint to prefer matching place types
  /// 3. Avoiding localities when searching for specific places
  Map<String, dynamic>? _selectBestPlaceResult(
    List<Map<String, dynamic>> results,
    String originalName, {
    String? geminiType,
  }) {
    if (results.isEmpty) return null;
    if (results.length == 1) return results.first;
    
    // Normalize the original name for comparison
    final normalizedOriginal = _normalizeForComparison(originalName);
    
    // Types that indicate a locality/neighborhood (usually NOT what we want for specific places)
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
    
    // Types that indicate natural features/outdoor attractions
    const naturalFeatureTypes = [
      'natural_feature',
      'park',
      'national_park',
      'state_park',
      'campground',
      'hiking_area',
      'beach',
    ];
    
    // Types that indicate visitor-related establishments (less preferred when searching for nature)
    const visitorEstablishmentTypes = [
      'visitor_center',
      'travel_agency',
      'tour_agency',
      'tourist_information',
    ];
    
    Map<String, dynamic>? bestResult;
    int bestScore = -1;
    
    // Check if Gemini identified this as a natural feature type
    final geminiTypeLower = geminiType?.toLowerCase() ?? '';
    final isNatureSearch = geminiTypeLower == 'park' || 
                          geminiTypeLower == 'landmark' ||
                          geminiTypeLower == 'trail' ||
                          geminiTypeLower == 'beach' ||
                          geminiTypeLower == 'natural_feature';
    final isCitySearch = geminiTypeLower == 'city' || 
                        geminiTypeLower == 'locality' ||
                        geminiTypeLower == 'neighborhood' ||
                        geminiTypeLower == 'region';
    
    if (isNatureSearch && bestScore == -1) {
      print('📷 IMAGE EXTRACTION: Nature/landmark search mode (geminiType: $geminiType)');
    } else if (isCitySearch && bestScore == -1) {
      print('📷 IMAGE EXTRACTION: City/locality search mode (geminiType: $geminiType)');
    }
    
    // Also create compact versions for compound word matching
    final compactOriginal = _normalizeCompact(originalName);
    
    for (final result in results) {
      int score = 0;
      
      // Get the result name and types
      final resultName = (result['name'] ?? result['description']?.toString().split(',').first ?? '') as String;
      final normalizedResultName = _normalizeForComparison(resultName);
      final compactResultName = _normalizeCompact(resultName);
      final types = (result['types'] as List?)?.cast<String>() ?? [];
      
      // === CRITICAL: NAME MATCHING (highest priority) ===
      // Use COMPACT comparison to handle compound word variations:
      // "James Island Viewpoint" vs "James Island View Point" → both become "jamesislandviewpoint"
      // "Hoh Rainforest" vs "Hoh Rain Forest" → both become "hohrainforest"
      
      // Exact match (using compact comparison) gets huge bonus
      if (compactResultName == compactOriginal) {
        score += 100; // Exact match - very strong
        print('📷 IMAGE EXTRACTION:   → Exact compact match bonus: +100');
      } 
      // Close match - one contains the other (using compact comparison)
      else if (compactResultName.contains(compactOriginal) || 
               compactOriginal.contains(compactResultName)) {
        // Calculate how close the match is based on character length difference
        final lengthDifference = (compactResultName.length - compactOriginal.length).abs();
        
        // Closer matches score higher - penalize extra characters
        // If result has many more characters than original, it's probably not what we want
        // e.g., "hohrainforestvisitorcenter" vs "hohrainforest" = diff 13 chars
        if (lengthDifference <= 5) {
          score += 80; // Very close match
          print('📷 IMAGE EXTRACTION:   → Close compact match bonus: +80 (diff: $lengthDifference chars)');
        } else if (lengthDifference <= 15) {
          score += 50 - (lengthDifference ~/ 2); // Medium match
          print('📷 IMAGE EXTRACTION:   → Medium compact match bonus: +${50 - (lengthDifference ~/ 2)} (diff: $lengthDifference chars)');
        } else {
          score += 20; // Weak containment
        }
      }
      
      // Also check word-based matching for partial matches
      final originalWordsList = normalizedOriginal.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
      int matchedWords = 0;
      for (final word in originalWordsList) {
        if (normalizedResultName.contains(word)) {
          matchedWords++;
        }
      }
      // Bonus for word matches
      if (originalWordsList.isNotEmpty) {
        final matchRatio = matchedWords / originalWordsList.length;
        score += (matchRatio * 20).round();
      }
      
      // === TYPE-BASED SCORING ===
      if (isCitySearch) {
        // When searching for a city, prefer localities
        for (final type in types) {
          if (localityTypes.contains(type)) {
            score += 40;
            break;
          }
        }
      } else if (isNatureSearch) {
        // When searching for nature (parks, trails, beaches), prefer natural features
        for (final type in types) {
          if (naturalFeatureTypes.contains(type)) {
            score += 30; // Boost natural features
            break;
          }
        }
        // Penalize visitor centers/agencies when searching for nature
        for (final type in types) {
          if (visitorEstablishmentTypes.contains(type)) {
            score -= 25; // Penalize visitor centers
            break;
          }
        }
      } else {
        // Default: Penalize localities, slight boost for establishments
        for (final type in types) {
          if (localityTypes.contains(type)) {
            score -= 30;
            break;
          }
        }
        // Only boost establishments for non-nature searches
        final hasEstablishment = types.any((t) => 
          t == 'establishment' || t == 'point_of_interest');
        if (hasEstablishment) {
          score += 15;
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
  
  /// Normalize for compact comparison - removes ALL spaces to handle compound word variations
  /// e.g., "James Island View Point" and "James Island Viewpoint" both become "jamesislandviewpoint"
  /// e.g., "Hoh Rain Forest" and "Hoh Rainforest" both become "hohrainforest"
  String _normalizeCompact(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), ''); // Remove ALL non-alphanumeric including spaces
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
