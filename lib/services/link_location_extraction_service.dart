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

/// Callback type for reporting extraction progress
/// [current] is the current item being processed (1-indexed)
/// [total] is the total number of items to process
/// [phase] describes what phase of extraction is happening
typedef ExtractionProgressCallback = void Function(int current, int total, String phase);

/// Geographic hints extracted from caption for location disambiguation
/// Used when multiple locations share the same name (e.g., "Jurassic World" in London vs Bangkok)
class GeographicHints {
  final Set<String> countries;
  final Set<String> cities;
  final Set<String> regions;
  
  GeographicHints({
    Set<String>? countries,
    Set<String>? cities,
    Set<String>? regions,
  }) : countries = countries ?? {},
       cities = cities ?? {},
       regions = regions ?? {};
  
  bool get isEmpty => countries.isEmpty && cities.isEmpty && regions.isEmpty;
  bool get isNotEmpty => !isEmpty;
  
  @override
  String toString() => 'GeographicHints(countries: $countries, cities: $cities, regions: $regions)';
}

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
  
  /// The last analyzed content from video/page extraction
  /// This contains the actual text (title, description, transcript) that was
  /// analyzed to find locations. Useful for showing users what was scanned.
  String? _lastAnalyzedContent;
  
  /// Get the last analyzed content (for YouTube videos: title + description + transcript)
  String? get lastAnalyzedContent => _lastAnalyzedContent;


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
    
    // Clear any previous analyzed content
    _lastAnalyzedContent = null;
    
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
  /// [geographicHints] - Optional pre-extracted geographic hints for disambiguation
  ///
  /// Returns a list of [ExtractedLocationData] objects found in the caption.
  Future<List<ExtractedLocationData>> extractLocationsFromCaption(
    String caption, {
    String platform = 'social media',
    String? authorName,
    String? sourceUrl,
    LatLng? userLocation,
    int? maxLocations,
    GeographicHints? geographicHints,
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
    print('📝 Caption preview: ${caption.length > 100 ? "${caption.substring(0, 100)}..." : caption}');
    
    // Extract mentions (@handles) from caption for tracking original sources
    final mentions = _extractMentionsFromCaption(caption);
    if (mentions.isNotEmpty) {
      print('📸 CAPTION EXTRACTION: Found ${mentions.length} mention(s): ${mentions.take(5).join(", ")}');
    }
    
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
      // Prioritize grounding results (with valid placeId) over text-parsed results
      // Google's Maps grounding uses semantic understanding - trust it more
      if (geminiResult != null && geminiResult.locations.isNotEmpty) {
        // Generic regions/counties to skip - these are too vague to be useful
        final genericRegions = {
          'orange county', 'los angeles county', 'san diego county', 'riverside county',
          'san bernardino county', 'ventura county', 'santa barbara county',
          'california', 'southern california', 'northern california',
          'united states', 'usa', 'america',
        };
        
        // Separate grounding chunks (have placeId) from text-parsed results (no placeId)
        // Grounding chunks come from Google Maps semantic understanding - trust them
        // Text-parsed results are from Gemini's JSON response - need validation
        final groundingChunks = geminiResult.locations.where((loc) => loc.placeId.isNotEmpty).toList();
        final textParsedLocations = geminiResult.locations.where((loc) => loc.placeId.isEmpty).toList();
        
        print('🔍 CAPTION: ${groundingChunks.length} grounding chunks (trusted), ${textParsedLocations.length} text-parsed');
        
        // Filter grounding chunks - only skip generic regions, trust semantic matching
        final relevantGroundingChunks = groundingChunks.where((location) {
          final nameLower = location.name.toLowerCase().trim();
          
          // Skip generic region/county names
          if (genericRegions.contains(nameLower)) {
            print('⏭️ CAPTION: Skipping generic region/county: "${location.name}"');
            return false;
          }
          
          // Trust grounding chunks - Google Maps semantic understanding already validated them
          print('✅ CAPTION: Trusting grounding chunk: "${location.name}" (placeId: ${location.placeId.substring(0, location.placeId.length > 10 ? 10 : location.placeId.length)}...)');
          return true;
        }).toList();
        
        // Filter text-parsed locations more strictly - require caption text match
        final lowerCaption = caption.toLowerCase();
        final relevantTextParsed = textParsedLocations.where((location) {
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
            print('⏭️ CAPTION: Skipping unrelated text-parsed result: "${location.name}" (not mentioned in caption)');
          }
          return isRelevant;
        }).toList();
        
        // Prioritize grounding chunks over text-parsed results
        // Grounding chunks have verified placeId from Google Maps
        final relevantLocations = [...relevantGroundingChunks, ...relevantTextParsed];
        
        if (relevantLocations.isNotEmpty) {
          print('✅ CAPTION EXTRACTION: Found ${relevantLocations.length} location(s) - ${relevantGroundingChunks.length} from grounding (trusted), ${relevantTextParsed.length} from text parsing');
        
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
            
            // Check if this location name came from a mention
            final matchingMention = _findMatchingMention(location.name, mentions);
            if (matchingMention != null) {
              print('📸 CAPTION: Location "${location.name}" matched mention: $matchingMention');
            }
            
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
              originalQuery: matchingMention,
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
              geographicHints: geographicHints, // Pass geographic hints for disambiguation
            );
            
            // Check if this location name came from a mention
            final matchingMention = _findMatchingMention(location.name, mentions);
            if (matchingMention != null) {
              print('📸 CAPTION: Location "${location.name}" matched mention: $matchingMention');
            }
            
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
              // Add with mention as originalQuery if found, otherwise use whatever originalQuery the resolver set
              results.add(resolvedLocation.copyWith(
                originalQuery: matchingMention ?? resolvedLocation.originalQuery,
              ));
            } else {
              // Could not resolve via Places API - skip it entirely
              // We never return results without actual coordinates (e.g., generic regions like "Vancouver", "Banff", "Utah")
              print('⏭️ CAPTION: Skipping "${location.name}" - could not resolve to a place with coordinates');
            }
          }
        }
        } else {
          print('⚠️ CAPTION EXTRACTION: ${geminiResult.locations.length} locations found but all were generic regions');
        }
      } 
      
      // Fallback: Parse JSON from Gemini's text response when:
      // 1. No grounding chunks were returned, OR
      // 2. All locations were filtered out (generic regions only)
      if (results.isEmpty && geminiResult != null && geminiResult.responseText.isNotEmpty) {
        print('🔄 CAPTION EXTRACTION: No valid locations from grounding, parsing JSON from response text...');
        
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
              geographicHints: geographicHints, // Pass geographic hints for disambiguation
            );
            
            // Check if this location name came from a mention
            final matchingMention = _findMatchingMention(name, mentions);
            if (matchingMention != null) {
              print('📸 CAPTION: Location "$name" matched mention: $matchingMention');
            }
            
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
              // Add with mention as originalQuery if found
              results.add(resolvedLocation.copyWith(
                originalQuery: matchingMention ?? resolvedLocation.originalQuery,
              ));
            } else {
              // Could not resolve via Places API - skip it entirely
              // We never return results without actual coordinates (e.g., generic regions like "Vancouver", "Banff", "Utah")
              print('⏭️ CAPTION: Skipping "$name" - could not resolve to a place with coordinates');
            }
          }
        } else {
          print('⚠️ CAPTION EXTRACTION: Could not parse any locations from JSON response');
        }
      }
      
      // === FALLBACK: Handle lookup when no locations found ===
      // If we have mentions (@handles) but no results yet, try looking them up
      // This handles cases where Gemini grounding fails but the handle IS a business
      if (results.isEmpty && mentions.isNotEmpty) {
        print('🔄 CAPTION EXTRACTION: No locations found, trying handle lookup fallback...');
        print('📸 CAPTION EXTRACTION: Looking up ${mentions.length} handle(s): ${mentions.take(3).join(", ")}${mentions.length > 3 ? "..." : ""}');
        
        // Use location context already extracted above (line ~201) for disambiguation
        // locationContext is already defined in this scope
        
        for (final handle in mentions.take(5)) { // Limit to first 5 handles
          print('🔍 CAPTION EXTRACTION: Looking up @$handle...');
          
          // Use Gemini to look up what business this handle refers to
          final handleResult = await _gemini.lookupInstagramHandleWithContext(
            handle,
            captionText: caption,
            geographicHints: locationContext != null ? [locationContext] : null,
          );
          
          if (handleResult != null && handleResult.name.isNotEmpty) {
            print('📸 CAPTION EXTRACTION: @$handle → "${handleResult.name}"${handleResult.address != null ? " at ${handleResult.address}" : ""}');
            
            // Verify with Places API
            final verified = await _verifyLocationWithPlacesAPI(
              name: handleResult.name,
              groundedAddress: handleResult.address,
              geminiType: handleResult.type,
              regionContext: locationContext ?? handleResult.city,
              userLocation: userLocation,
            );
            
            if (verified != null) {
              // Skip duplicates
              if (verified.placeId != null && seenPlaceIds.contains(verified.placeId)) {
                print('⏭️ CAPTION EXTRACTION: Skipping duplicate Place ID from handle lookup');
                continue;
              }
              if (verified.placeId != null) {
                seenPlaceIds.add(verified.placeId!);
              }
              
              print('✅ CAPTION EXTRACTION: Verified @$handle → "${verified.name}" at ${verified.address}');
              // Add with the original handle as the query
              results.add(verified.copyWith(
                originalQuery: '@$handle',
              ));
              
              // If we found a result and have a max limit, check if we're done
              if (maxLocations != null && results.length >= maxLocations) {
                print('📍 CAPTION EXTRACTION: Reached max locations ($maxLocations) from handle lookup');
                break;
              }
            } else {
              print('⚠️ CAPTION EXTRACTION: Could not verify @$handle via Places API');
            }
          } else {
            print('⚠️ CAPTION EXTRACTION: Could not resolve @$handle to a business name');
          }
        }
        
        if (results.isNotEmpty) {
          print('✅ CAPTION EXTRACTION: Handle lookup found ${results.length} location(s)');
        } else {
          print('⚠️ CAPTION EXTRACTION: Handle lookup did not find any locations');
        }
      }
      
      // Final check - if still no results
      if (results.isEmpty) {
        if (geminiResult == null) {
          print('⚠️ CAPTION EXTRACTION: Gemini returned no results');
        } else if (mentions.isEmpty) {
          print('⚠️ CAPTION EXTRACTION: No locations could be extracted from caption (no handles to try)');
        } else {
          print('⚠️ CAPTION EXTRACTION: No locations could be extracted from caption (handle lookup also failed)');
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
  
  /// Extract geographic hints (countries, major cities) from caption text
  /// Used to disambiguate locations when multiple places share the same name
  /// This is a public method so it can be called from receive_share_screen.dart
  GeographicHints extractGeographicHints(String caption) {
    final lowerCaption = caption.toLowerCase();
    final countries = <String>{};
    final cities = <String>{};
    final regions = <String>{};
    
    // Extract hashtags for checking
    final hashtagPattern = RegExp(r'#(\w+)');
    final hashtags = hashtagPattern.allMatches(lowerCaption)
        .map((m) => m.group(1)?.toLowerCase() ?? '')
        .toSet();
    
    // === US CONTEXT DETECTION ===
    // Check if there's strong US context that would override international city mappings
    // This prevents "Venice" in "Venice, CA" from being interpreted as Venice, Italy
    final hasUsContext = _detectUsContext(lowerCaption, hashtags);
    
    // Cities that exist in both US and internationally
    // These should NOT trigger international mappings when US context is present
    const usDuplicateCities = {
      'venice',     // Venice, CA (LA neighborhood) vs Venice, Italy
      'naples',     // Naples, FL vs Naples, Italy
      'paris',      // Paris, TX vs Paris, France
      'florence',   // Florence, SC/AL/KY vs Florence, Italy
      'rome',       // Rome, GA vs Rome, Italy
      'milan',      // Milan, IL vs Milan, Italy
      'athens',     // Athens, GA vs Athens, Greece
      'dublin',     // Dublin, CA/OH vs Dublin, Ireland
      'cambridge',  // Cambridge, MA vs Cambridge, UK
      'oxford',     // Oxford, MS vs Oxford, UK
      'manchester', // Manchester, NH vs Manchester, UK
      'birmingham', // Birmingham, AL vs Birmingham, UK
      'london',     // London, KY/OH vs London, UK
    };
    
    // International countries (common travel destinations)
    const internationalCountries = {
      'thailand': 'Thailand',
      'japan': 'Japan',
      'korea': 'South Korea',
      'southkorea': 'South Korea',
      'china': 'China',
      'vietnam': 'Vietnam',
      'singapore': 'Singapore',
      'malaysia': 'Malaysia',
      'indonesia': 'Indonesia',
      'philippines': 'Philippines',
      'taiwan': 'Taiwan',
      'india': 'India',
      'australia': 'Australia',
      'newzealand': 'New Zealand',
      'uk': 'United Kingdom',
      'unitedkingdom': 'United Kingdom',
      'england': 'England',
      'london': 'United Kingdom', // City but strong country indicator
      'france': 'France',
      'paris': 'France', // City but strong country indicator
      'germany': 'Germany',
      'italy': 'Italy',
      'spain': 'Spain',
      'portugal': 'Portugal',
      'greece': 'Greece',
      'turkey': 'Turkey',
      'mexico': 'Mexico',
      'canada': 'Canada',
      'brazil': 'Brazil',
      'argentina': 'Argentina',
      'dubai': 'United Arab Emirates',
      'uae': 'United Arab Emirates',
      'egypt': 'Egypt',
      'morocco': 'Morocco',
      'southafrica': 'South Africa',
    };
    
    // Major international cities with their countries
    const internationalCities = {
      'bangkok': 'Thailand',
      'phuket': 'Thailand',
      'chiangmai': 'Thailand',
      'pattaya': 'Thailand',
      'tokyo': 'Japan',
      'osaka': 'Japan',
      'kyoto': 'Japan',
      'seoul': 'South Korea',
      'busan': 'South Korea',
      'beijing': 'China',
      'shanghai': 'China',
      'hongkong': 'China',
      'taipei': 'Taiwan',
      'hanoi': 'Vietnam',
      'hochiminh': 'Vietnam',
      'saigon': 'Vietnam',
      'kualalumpur': 'Malaysia',
      'bali': 'Indonesia',
      'jakarta': 'Indonesia',
      'manila': 'Philippines',
      'mumbai': 'India',
      'delhi': 'India',
      'sydney': 'Australia',
      'melbourne': 'Australia',
      'auckland': 'New Zealand',
      'london': 'United Kingdom',
      'manchester': 'United Kingdom',
      'edinburgh': 'United Kingdom',
      'paris': 'France',
      'nice': 'France',
      'berlin': 'Germany',
      'munich': 'Germany',
      'rome': 'Italy',
      'milan': 'Italy',
      'venice': 'Italy',
      'florence': 'Italy',
      'barcelona': 'Spain',
      'madrid': 'Spain',
      'lisbon': 'Portugal',
      'athens': 'Greece',
      'istanbul': 'Turkey',
      'dubai': 'United Arab Emirates',
      'abudhabi': 'United Arab Emirates',
      'cairo': 'Egypt',
      'marrakech': 'Morocco',
      'capetown': 'South Africa',
      'toronto': 'Canada',
      'vancouver': 'Canada',
      'montreal': 'Canada',
      'mexicocity': 'Mexico',
      'cancun': 'Mexico',
      'riodejaneiro': 'Brazil',
      'saopaulo': 'Brazil',
      'buenosaires': 'Argentina',
    };
    
    // Check hashtags and caption text for countries
    for (final entry in internationalCountries.entries) {
      final keyword = entry.key;
      final country = entry.value;
      
      // Check hashtags
      if (hashtags.contains(keyword)) {
        countries.add(country);
        print('🌍 GEO HINTS: Found country in hashtag: #$keyword → $country');
      }
      // Check caption text (with word boundary for longer words)
      else if (keyword.length >= 4) {
        final pattern = RegExp(r'\b' + RegExp.escape(keyword) + r'\b', caseSensitive: false);
        if (pattern.hasMatch(lowerCaption)) {
          countries.add(country);
          print('🌍 GEO HINTS: Found country in text: $keyword → $country');
        }
      }
    }
    
    // Check hashtags and caption text for cities
    for (final entry in internationalCities.entries) {
      final cityKey = entry.key;
      final country = entry.value;
      
      // Skip international mapping for cities that also exist in US when US context is detected
      if (hasUsContext && usDuplicateCities.contains(cityKey)) {
        print('🌍 GEO HINTS: Skipping international mapping for "$cityKey" - US context detected');
        continue;
      }
      
      // Check hashtags
      if (hashtags.contains(cityKey)) {
        cities.add(cityKey);
        countries.add(country); // City implies country
        print('🌍 GEO HINTS: Found city in hashtag: #$cityKey → $country');
      }
      // Check caption text
      else if (cityKey.length >= 4) {
        final pattern = RegExp(r'\b' + RegExp.escape(cityKey) + r'\b', caseSensitive: false);
        if (pattern.hasMatch(lowerCaption)) {
          cities.add(cityKey);
          countries.add(country);
          print('🌍 GEO HINTS: Found city in text: $cityKey → $country');
        }
      }
    }
    
    // Check for well-known landmarks/places that indicate countries
    const landmarkIndicators = {
      'asiatique': 'Thailand', // Asiatique The Riverfront in Bangkok
      'chatuchak': 'Thailand',
      'sukhumvit': 'Thailand',
      'shibuya': 'Japan',
      'shinjuku': 'Japan',
      'akihabara': 'Japan',
      'harajuku': 'Japan',
      'gangnam': 'South Korea',
      'myeongdong': 'South Korea',
      'bigben': 'United Kingdom',
      'eiffeltower': 'France',
      'colosseum': 'Italy',
      'sagradafamilia': 'Spain',
    };
    
    for (final entry in landmarkIndicators.entries) {
      if (hashtags.contains(entry.key) || lowerCaption.contains(entry.key)) {
        countries.add(entry.value);
        print('🌍 GEO HINTS: Found landmark indicator: ${entry.key} → ${entry.value}');
      }
    }
    
    final hints = GeographicHints(countries: countries, cities: cities, regions: regions);
    if (hints.isNotEmpty) {
      print('🌍 GEO HINTS: Extracted hints: $hints');
    }
    return hints;
  }

  /// Detect if caption/hashtags contain strong US context
  /// Used to disambiguate cities that exist in both US and internationally
  bool _detectUsContext(String lowerCaption, Set<String> hashtags) {
    // Strong US indicators in hashtags
    const usHashtagIndicators = {
      'la', 'losangeles', 'california', 'ca', 'socal', 'norcal',
      'sf', 'sanfrancisco', 'bayarea', 'siliconvalley',
      'nyc', 'newyork', 'newyorkcity', 'brooklyn', 'manhattan',
      'lafoodie', 'larestaurants', 'laeats', 'lafood',
      'sffoodie', 'nycfoodie', 'nycrestaurants',
      'orangecounty', 'oc', 'ocfoodie',
      'sandiego', 'sd', 'sdfoodie',
      'usa', 'america', 'american',
      'chicago', 'miami', 'austin', 'seattle', 'portland',
      'denver', 'boston', 'atlanta', 'dallas', 'houston', 'phoenix',
      'lasvegas', 'vegas',
      'datenightla', 'datenight', 'fairfaxdistrict', 'thegrove',
      'westla', 'eastla', 'dtla', 'downtownla',
    };
    
    // Check hashtags for US indicators
    for (final indicator in usHashtagIndicators) {
      if (hashtags.contains(indicator)) {
        print('🌍 US CONTEXT: Detected via hashtag #$indicator');
        return true;
      }
    }
    
    // Strong US text patterns
    final usTextPatterns = [
      RegExp(r'\blos angeles\b', caseSensitive: false),
      RegExp(r'\bla,?\s*ca\b', caseSensitive: false),
      RegExp(r'\bcalifornia\b', caseSensitive: false),
      RegExp(r',\s*ca\s*\d{5}', caseSensitive: false), // CA ZIP code
      RegExp(r'\bsan francisco\b', caseSensitive: false),
      RegExp(r'\bsf,?\s*ca\b', caseSensitive: false),
      RegExp(r'\bnew york\b', caseSensitive: false),
      RegExp(r'\bnyc\b', caseSensitive: false),
      RegExp(r',\s*ny\s*\d{5}', caseSensitive: false), // NY ZIP code
      RegExp(r'\borange county\b', caseSensitive: false),
      RegExp(r'\bthe grove\b', caseSensitive: false), // Famous LA shopping center
      RegExp(r'\bsanta monica\b', caseSensitive: false),
      RegExp(r'\bhollywood\b', caseSensitive: false),
      RegExp(r'\bbeverly hills\b', caseSensitive: false),
      RegExp(r'\bwest hollywood\b', caseSensitive: false),
      RegExp(r'\bvenice beach\b', caseSensitive: false), // Specifically Venice Beach, CA
      RegExp(r'\bvenice,?\s*ca\b', caseSensitive: false), // Venice, CA
      RegExp(r'\bvenice,?\s*california\b', caseSensitive: false),
      RegExp(r'\busa\b', caseSensitive: false),
      RegExp(r'\bunited states\b', caseSensitive: false),
    ];
    
    for (final pattern in usTextPatterns) {
      if (pattern.hasMatch(lowerCaption)) {
        print('🌍 US CONTEXT: Detected via text pattern: ${pattern.pattern}');
        return true;
      }
    }
    
    // Check for US state abbreviations with ZIP codes
    final stateZipPattern = RegExp(r',\s*(AL|AK|AZ|AR|CA|CO|CT|DE|FL|GA|HI|ID|IL|IN|IA|KS|KY|LA|ME|MD|MA|MI|MN|MS|MO|MT|NE|NV|NH|NJ|NM|NY|NC|ND|OH|OK|OR|PA|RI|SC|SD|TN|TX|UT|VT|VA|WA|WV|WI|WY)\s*\d{5}', caseSensitive: false);
    if (stateZipPattern.hasMatch(lowerCaption)) {
      print('🌍 US CONTEXT: Detected via state+ZIP pattern');
      return true;
    }
    
    return false;
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
    String? surroundingText, // Optional caption/page text for AI reranking context
    String? geminiType, // Optional expected type from Gemini extraction
    GeographicHints? geographicHints, // Optional geographic hints for disambiguation
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

      // Merge locationContext into geographic hints for better city matching
      // This ensures that when we search for "Mokkoji, san diego", San Diego results get a boost
      GeographicHints? effectiveHints = geographicHints;
      if (locationContext != null && locationContext.isNotEmpty) {
        final contextLower = locationContext.toLowerCase().trim();
        // Create or extend hints with the location context as a city hint
        if (effectiveHints == null || effectiveHints.isEmpty) {
          effectiveHints = GeographicHints(cities: {contextLower});
        } else if (!effectiveHints.cities.contains(contextLower)) {
          // Add the location context city to existing hints
          effectiveHints = GeographicHints(
            countries: effectiveHints.countries,
            cities: {...effectiveHints.cities, contextLower},
          );
        }
        print('📍 PLACES RESOLVE: Added location context "$contextLower" to city hints');
      }

      // Use the sophisticated scoring method to find the best match
      // This properly handles name matching with compact comparison
      // Pass geographic hints for disambiguation of same-name locations
      // Pass grounded address for location name matching (e.g., "The Grove" in address)
      final bestResult = _selectBestPlaceResult(results, locationName, geminiType: geminiType, geographicHints: effectiveHints, groundedAddress: address);
      
      if (bestResult == null) {
        print('⚠️ PLACES RESOLVE: No good match found for "$locationName"');
        return null;
      }
      
      // Find the index of the selected result for potential AI reranking
      final selectedIndex = results.indexOf(bestResult);
      
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
      
      // === AI RERANKING: Trigger when initial match quality is low ===
      Map<String, dynamic> finalResult = bestResult;
      double finalConfidence = 0.85;
      bool needsConfirmation = false;
      
      // Check if we need AI reranking
      final rerankResult = await _maybeAIRerank(
        originalName: locationName,
        candidates: results,
        selectedIndex: selectedIndex,
        geminiType: geminiType,
        regionContext: locationContext,
        surroundingText: surroundingText,
        userLocation: userLocation,
        usedBroaderSearch: !hasGoodNameMatch,
      );
      
      // Use the reranked result
      if (rerankResult.selectedResult != null) {
        finalResult = rerankResult.selectedResult!;
        finalConfidence = rerankResult.confidence;
        needsConfirmation = rerankResult.needsConfirmation;
        
        if (rerankResult.usedAIRerank) {
          print('🤖 PLACES RESOLVE: AI reranking applied (confidence: ${(finalConfidence * 100).toInt()}%)');
        }
      }
      
      // If still no good name match and AI couldn't improve it, return null
      if (!hasGoodNameMatch && !rerankResult.usedAIRerank) {
        print('⚠️ PLACES RESOLVE: Best result "$resultName" doesn\'t match "$locationName" well enough');
        print('   Will add location without coordinates (user can set manually)');
        return null;
      }
      
      // CRITICAL: If AI reranking explicitly said NO candidates match (needsConfirmation=true 
      // with very low confidence), return null so caller can use Gemini's address for geocoding.
      // This handles cases where the place doesn't exist in Google Places (closed, new, etc.)
      // e.g., "Rising Sun Collective" not in Places → should geocode "3914 30th St, San Diego"
      if (rerankResult.needsConfirmation && rerankResult.confidence < 0.3) {
        print('⚠️ PLACES RESOLVE: AI reranking found NO good matches (confidence: ${(rerankResult.confidence * 100).toInt()}%)');
        print('   Place may not exist in Google Places. Will use Gemini\'s address for geocoding.');
        return null;
      }
      
      // Get the final result name
      final finalResultName = (finalResult['name'] ?? finalResult['description']?.toString().split(',').first ?? '') as String;
      print('🎯 PLACES RESOLVE: Selected best match: "$finalResultName"');

      final placeId = finalResult['placeId'] as String?;
      
      // Autocomplete doesn't return coordinates - need to call Place Details API
      LatLng? coords;
      String? resolvedAddress;
      String? resolvedName;
      String? website;
      List<String>? placeTypes;
      
      if (placeId != null && placeId.isNotEmpty) {
        print('🔍 PLACES RESOLVE: Getting details for Place ID: $placeId');
        try {
          final placeDetails = await _maps.getPlaceDetails(placeId, includePhotoUrl: false);
          
          // Extract coordinates from place details
          if (placeDetails.latitude != 0.0 || placeDetails.longitude != 0.0) {
            coords = LatLng(placeDetails.latitude, placeDetails.longitude);
          }
          
          resolvedAddress = placeDetails.address;
          resolvedName = placeDetails.displayName ?? finalResult['description'] as String?;
          website = placeDetails.website;
          
          // Get place types from Place Details API (preferred) or fall back to autocomplete
          placeTypes = placeDetails.placeTypes ?? 
              (finalResult['types'] as List<dynamic>?)?.cast<String>();
          
          print('✅ PLACES RESOLVE: Got details - "$resolvedName" at $coords');
          if (website != null) {
            print('🌐 PLACES RESOLVE: Got website: $website');
          }
          if (placeTypes != null && placeTypes.isNotEmpty) {
            print('📋 PLACES RESOLVE: Got types: ${placeTypes.take(5).join(", ")}');
          }
        } catch (e) {
          print('⚠️ PLACES RESOLVE: Could not get place details: $e');
          // Fall back to autocomplete data
          resolvedName = finalResult['description'] as String?;
          resolvedAddress = finalResult['address'] as String?;
          placeTypes = (finalResult['types'] as List<dynamic>?)?.cast<String>();
        }
      } else {
        resolvedName = finalResult['description'] as String?;
        resolvedAddress = finalResult['address'] as String?;
        placeTypes = (finalResult['types'] as List<dynamic>?)?.cast<String>();
      }
      
      print('✅ PLACES RESOLVE: Final result "$resolvedName" at $coords');
      
      // Store original query only if it's different from the resolved name
      final originalQueryText = (resolvedName != null && resolvedName != locationName) ? locationName : null;

      return ExtractedLocationData(
        placeId: placeId,
        name: resolvedName ?? locationName,
        address: resolvedAddress,
        coordinates: coords,
        type: ExtractedLocationData.inferPlaceType(placeTypes ?? []),
        source: ExtractionSource.placesSearch,
        confidence: coords != null ? finalConfidence : finalConfidence * 0.7, // Higher confidence with coords
        metadata: {'original_query': locationName, 'location_context': locationContext},
        website: website,
        needsConfirmation: needsConfirmation,
        originalQuery: originalQueryText,
        placeTypes: placeTypes,
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

  /// Extract @mentions from caption text
  /// Returns list of mentions without the @ symbol
  List<String> _extractMentionsFromCaption(String caption) {
    final mentionRegex = RegExp(r'@([a-zA-Z0-9_.]+)');
    final matches = mentionRegex.allMatches(caption);
    return matches.map((m) => m.group(1)!.toLowerCase()).toList();
  }

  /// Find a matching mention for a location name
  /// Returns the original mention (with @) if found, null otherwise
  String? _findMatchingMention(String locationName, List<String> mentions) {
    if (mentions.isEmpty) return null;
    
    final nameLower = locationName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    
    for (final mention in mentions) {
      // Clean the mention for comparison
      final mentionClean = mention.replaceAll(RegExp(r'[^a-z0-9]'), '');
      
      // Check if mention contains the name or vice versa
      // "origenorigenorigen" contains "origen" -> match
      // "origen" is contained in "origenorigenorigen" -> match
      if (mentionClean.contains(nameLower) || nameLower.contains(mentionClean)) {
        return '@$mention';
      }
      
      // Also check if words from the name appear in the mention
      final nameWords = locationName.toLowerCase().split(RegExp(r'[^a-z0-9]+'));
      for (final word in nameWords) {
        if (word.length >= 3 && mentionClean.contains(word)) {
          return '@$mention';
        }
      }
    }
    
    return null;
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
          
          // Store the analyzed content (video title, description, transcript)
          // This is what the AI analyzed to find the locations
          if (youtubeResult.analyzedContent != null && youtubeResult.analyzedContent!.isNotEmpty) {
            _lastAnalyzedContent = youtubeResult.analyzedContent;
            print('📝 EXTRACTION: Stored analyzed content (${_lastAnalyzedContent!.length} chars)');
          }
          
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
        // Could not resolve via Places API - skip it entirely
        // We never return results without actual coordinates (e.g., generic regions like "Vancouver", "Banff", "Utah")
        print('⏭️ YOUTUBE: Skipping "${location.name}" - could not resolve to a place with coordinates');
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

  /// Check if a place name should be skipped during verification
  /// because it matches a pre-confirmed location name
  /// 
  /// Uses fuzzy matching to handle slight variations in naming
  /// (e.g., "The Grove" vs "Grove", "Meraki Cafe" vs "Meraki Café")
  bool _shouldSkipLocation(String placeName, Set<String> confirmedNames) {
    final normalizedPlaceName = _normalizeForComparison(placeName);
    
    for (final confirmedName in confirmedNames) {
      final normalizedConfirmed = _normalizeForComparison(confirmedName);
      
      // Exact match after normalization
      if (normalizedPlaceName == normalizedConfirmed) {
        return true;
      }
      
      // One contains the other (handles "The Grove" vs "Grove")
      if (normalizedPlaceName.contains(normalizedConfirmed) ||
          normalizedConfirmed.contains(normalizedPlaceName)) {
        // Only skip if the shorter name is at least 60% of the longer
        final shorter = normalizedPlaceName.length <= normalizedConfirmed.length 
            ? normalizedPlaceName : normalizedConfirmed;
        final longer = normalizedPlaceName.length > normalizedConfirmed.length 
            ? normalizedPlaceName : normalizedConfirmed;
        if (shorter.length >= longer.length * 0.6) {
          return true;
        }
      }
      
      // Use existing name similarity check for fuzzy matching
      if (_areNamesSimilar(placeName, confirmedName)) {
        return true;
      }
    }
    
    return false;
  }
  
  /// Normalize a string for comparison (lowercase, remove special chars, normalize whitespace)
  String _normalizeForComparison(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '') // Remove special characters
        .replaceAll(RegExp(r'\s+'), ' ')    // Normalize whitespace
        .trim();
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

  // ============ UNIFIED TEXT EXTRACTION (SAME AS PREVIEW SCAN) ============
  
  /// Extract locations from text using the SAME sophisticated verification as Preview Scan
  /// 
  /// This is the UNIFIED extraction method that all paths should use after getting text.
  /// It uses the same verification flow as extractLocationsFromMultipleImages:
  /// 1. Analyzes text to extract rich context (place names, addresses, types, region)
  /// 2. Searches Places API using multiple strategies (address first, then context, then exact)
  /// 3. Uses _selectBestPlaceResultWithContext with sophisticated scoring
  /// 4. Applies location name bonuses, grounded address matching, etc.
  /// 
  /// [text] - The text/caption to extract locations from
  /// [userLocation] - Optional user location for better results
  /// [onProgress] - Optional callback for progress updates
  /// [skipLocationNames] - Optional set of location names to skip verification for
  ///                       (used when user has already confirmed certain locations)
  /// 
  /// Returns verified locations with placeId, coordinates, and full details
  Future<({List<ExtractedLocationData> locations, String? regionContext, String? extractedText})> extractLocationsFromTextUnified(
    String text, {
    LatLng? userLocation,
    ExtractionProgressCallback? onProgress,
    Set<String>? skipLocationNames,
  }) async {
    print('🔄 UNIFIED TEXT EXTRACTION: Starting extraction (${text.length} chars)...');
    if (skipLocationNames != null && skipLocationNames.isNotEmpty) {
      print('📍 UNIFIED TEXT EXTRACTION: Will skip verification for ${skipLocationNames.length} pre-confirmed location(s)');
    }

    try {
      // Step 1: Use Gemini to analyze text and extract rich context
      // This gets: place names, grounded addresses, types, region context
      onProgress?.call(0, 1, 'Analyzing text with AI...');
      final context = await _gemini.analyzeTextForLocations(text);
      
      if (context == null) {
        print('⚠️ UNIFIED TEXT EXTRACTION: Could not analyze text context');
        return (locations: <ExtractedLocationData>[], regionContext: null, extractedText: text);
      }

      // Log the extracted context
      if (context.mentionedPlaceNames.isNotEmpty) {
        print('📍 UNIFIED TEXT EXTRACTION: Found ${context.mentionedPlaceNames.length} place name(s)');
        for (final name in context.mentionedPlaceNames) {
          final address = context.placeAddresses[name];
          final type = context.placeTypes[name];
          print('   → "$name"${address != null ? " at $address" : ""}${type != null ? " ($type)" : ""}');
        }
      }
      if (context.businessHandles.isNotEmpty) {
        print('📍 UNIFIED TEXT EXTRACTION: Found ${context.businessHandles.length} business handle(s): ${context.businessHandles.map((h) => "@$h").join(", ")}');
      }
      if (context.geographicFocus != null) {
        print('🌍 UNIFIED TEXT EXTRACTION: Region context: "${context.geographicFocus}"');
      }

      // Step 2: Verify each location with Places API using sophisticated scoring
      // This is the SAME flow as extractLocationsFromMultipleImages
      final results = <ExtractedLocationData>[];
      final totalLocations = context.mentionedPlaceNames.length + context.businessHandles.length;
      var currentIndex = 0;

      // === Process mentioned place names first (most reliable) ===
      for (final placeName in context.mentionedPlaceNames) {
        currentIndex++;
        
        // Check if this location should be skipped (already confirmed by user)
        if (skipLocationNames != null && _shouldSkipLocation(placeName, skipLocationNames)) {
          print('⏭️ UNIFIED TEXT EXTRACTION: Skipping "$placeName" (pre-confirmed by user)');
          onProgress?.call(currentIndex, totalLocations, 'Skipping $placeName (already confirmed)...');
          continue;
        }
        
        onProgress?.call(currentIndex, totalLocations, 'Verifying $placeName...');
        
        var address = context.placeAddresses[placeName];
        final type = context.placeTypes[placeName];
        
        print('📍 UNIFIED TEXT EXTRACTION: Verifying "$placeName"...');
        
        // === KEY FIX: Use Google Search grounding to find address if not explicitly provided ===
        // This is the same approach used by the multi-image/Scan Preview flow
        // Without this, we rely only on Places API which can return wrong locations
        // (e.g., "Meraki Cafe" in Indonesia instead of San Diego)
        if (address == null || address.isEmpty) {
          print('📍 UNIFIED TEXT EXTRACTION: No explicit address, using Google Search grounding...');
          
          final groundedResult = await _gemini.searchPlaceWithGrounding(
            placeName: placeName,
            geographicFocus: context.geographicFocus,
            placeType: type,
            extractedText: text,
          );
          
          if (groundedResult != null && groundedResult.address != null) {
            address = groundedResult.address;
            print('📍 UNIFIED TEXT EXTRACTION: Found grounded address via search: "$address"');
          }
        } else {
          print('📍 UNIFIED TEXT EXTRACTION: Using explicit address from text: "$address"');
        }
        
        final verified = await _verifyLocationWithPlacesAPI(
          name: placeName,
          groundedAddress: address,
          geminiType: type,
          regionContext: context.geographicFocus,
          userLocation: userLocation,
        );
        
        if (verified != null && !_isDuplicate(verified, results)) {
          results.add(verified);
          print('✅ UNIFIED TEXT EXTRACTION: Verified "$placeName" → "${verified.name}" at ${verified.address}');
        }
      }

      // === Process business handles (if no place names found results) ===
      if (results.isEmpty && context.businessHandles.isNotEmpty) {
        print('📍 UNIFIED TEXT EXTRACTION: No places from names, trying business handles...');
        
        for (final handle in context.businessHandles) {
          currentIndex++;
          onProgress?.call(currentIndex, totalLocations, 'Looking up @$handle...');
          
          // Use handle lookup to get the business name
          final handleResult = await _gemini.lookupInstagramHandleWithContext(
            handle,
            captionText: text,
            geographicHints: context.geographicFocus != null ? [context.geographicFocus!] : null,
          );
          
          if (handleResult != null && handleResult.name.isNotEmpty) {
            print('📍 UNIFIED TEXT EXTRACTION: @$handle → "${handleResult.name}"');
            
            // Verify with Places API using the same sophisticated scoring
            final verified = await _verifyLocationWithPlacesAPI(
              name: handleResult.name,
              groundedAddress: handleResult.address,
              geminiType: handleResult.type,
              regionContext: context.geographicFocus ?? handleResult.city,
              userLocation: userLocation,
            );
            
            if (verified != null && !_isDuplicate(verified, results)) {
              results.add(verified);
              print('✅ UNIFIED TEXT EXTRACTION: Verified "@$handle" → "${verified.name}" at ${verified.address}');
            }
          }
        }
      }

      print('📍 UNIFIED TEXT EXTRACTION: Final result - ${results.length} verified location(s)');
      return (locations: results, regionContext: context.geographicFocus, extractedText: text);
    } catch (e, stackTrace) {
      print('❌ UNIFIED TEXT EXTRACTION ERROR: $e');
      print('Stack trace: $stackTrace');
      return (locations: <ExtractedLocationData>[], regionContext: null, extractedText: text);
    }
  }

  /// Verify a location with Places API using the SAME sophisticated scoring as Preview Scan
  /// 
  /// This uses _selectBestPlaceResultWithContext with:
  /// - Grounded address matching (+250 bonus)
  /// - Location name in candidate bonus (+120 for "The Grove" etc.)
  /// - Name similarity scoring
  /// - Type compatibility
  /// - Geographic context (city/state bonuses)
  Future<ExtractedLocationData?> _verifyLocationWithPlacesAPI({
    required String name,
    String? groundedAddress,
    String? geminiType,
    String? regionContext,
    LatLng? userLocation,
  }) async {
    print('🔍 VERIFY LOCATION: "$name"${groundedAddress != null ? " at $groundedAddress" : ""}');
    
    Map<String, dynamic>? placeResult;
    var placeResults = <Map<String, dynamic>>[];
    
    // Extract state from region context for search queries
    final stateFromContext = _extractStateFromContext(regionContext);
    final broaderRegion = stateFromContext == null ? _extractBroaderRegion(regionContext) : null;
    
    // === STRATEGY 1: Search by grounded address FIRST (most reliable) ===
    if (groundedAddress != null && groundedAddress.isNotEmpty) {
      print('🔍 VERIFY LOCATION: PRIORITY SEARCH by grounded address: "$groundedAddress"');
      
      final addressResults = await _maps.searchPlaces(
        groundedAddress,
        latitude: userLocation?.latitude,
        longitude: userLocation?.longitude,
      );
      
      if (addressResults.isNotEmpty) {
        print('🔍 VERIFY LOCATION: Found ${addressResults.length} candidates from address search');
        
        placeResult = _selectBestPlaceResultWithContext(
          addressResults,
          name,
          geminiType: geminiType,
          regionContext: regionContext,
          groundedAddress: groundedAddress,
        );
        
        if (placeResult != null) {
          final foundName = (placeResult['name'] ?? placeResult['description']?.toString().split(',').first ?? '') as String;
          final foundAddress = (placeResult['formatted_address'] ?? placeResult['description'] ?? '') as String;
          final addressMatchScore = _calculateAddressSimilarity(groundedAddress, foundAddress);
          
          print('🔍 VERIFY LOCATION: Best candidate: "$foundName" (address match: ${(addressMatchScore * 100).toInt()}%)');
          
          if (addressMatchScore >= 0.6) {
            placeResults = addressResults;
          } else {
            placeResult = null; // Reset to try name search
          }
        }
      }
    }
    
    // === STRATEGY 2: Search with region context ===
    if (placeResults.isEmpty && (stateFromContext != null || broaderRegion != null)) {
      final contextSearchQuery = stateFromContext != null 
          ? '$name, $stateFromContext'
          : '$name, $broaderRegion';
      print('🔍 VERIFY LOCATION: Searching with context: "$contextSearchQuery"');
      
      placeResults = await _maps.searchPlaces(
        contextSearchQuery,
        latitude: userLocation?.latitude,
        longitude: userLocation?.longitude,
      );
      
      if (placeResults.isNotEmpty) {
        print('🔍 VERIFY LOCATION: Found ${placeResults.length} candidates from context search');
        
        placeResult = _selectBestPlaceResultWithContext(
          placeResults,
          name,
          geminiType: geminiType,
          regionContext: regionContext,
          groundedAddress: groundedAddress,
        );
      }
    }
    
    // === STRATEGY 3: Search exact term only ===
    if (placeResults.isEmpty) {
      print('🔍 VERIFY LOCATION: Searching exact term: "$name"');
      
      placeResults = await _maps.searchPlaces(
        name,
        latitude: userLocation?.latitude,
        longitude: userLocation?.longitude,
      );
      
      if (placeResults.isNotEmpty) {
        print('🔍 VERIFY LOCATION: Found ${placeResults.length} candidates from exact search');
        
        placeResult = _selectBestPlaceResultWithContext(
          placeResults,
          name,
          geminiType: geminiType,
          regionContext: regionContext,
          groundedAddress: groundedAddress,
        );
      }
    }
    
    // === STRATEGY 4: Text Search for more candidates if match quality is low ===
    if (placeResult != null) {
      final foundName = (placeResult['name'] ?? placeResult['description']?.toString().split(',').first ?? '') as String;
      final matchQuality = _checkNameMatchQuality(name, foundName);
      final placeTypes = (placeResult['types'] as List?)?.cast<String>() ?? [];
      final isTypeCompatible = _isTypeCompatible(geminiType, placeTypes);
      
      if (matchQuality.matchScore < 0.95 || !isTypeCompatible) {
        print('🔍 VERIFY LOCATION: Match quality ${(matchQuality.matchScore * 100).toInt()}% < 95%, running Text Search...');
        
        final textSearchQuery = stateFromContext != null 
            ? '$name, $stateFromContext'
            : (broaderRegion != null ? '$name, $broaderRegion' : name);
        
        final textSearchResults = await _maps.searchPlacesTextSearch(
          textSearchQuery,
          latitude: userLocation?.latitude,
          longitude: userLocation?.longitude,
        );
        
        if (textSearchResults.isNotEmpty) {
          print('🔍 VERIFY LOCATION: Text Search found ${textSearchResults.length} candidates');
          
          // Combine with existing candidates
          final existingPlaceIds = placeResults.map((r) => r['placeId'] as String?).toSet();
          for (final result in textSearchResults) {
            final placeId = result['placeId'] as String?;
            if (placeId != null && !existingPlaceIds.contains(placeId)) {
              placeResults.add(result);
              existingPlaceIds.add(placeId);
            }
          }
          
          // Re-select best from combined candidates
          placeResult = _selectBestPlaceResultWithContext(
            placeResults,
            name,
            geminiType: geminiType,
            regionContext: regionContext,
            groundedAddress: groundedAddress,
          );
        }
      }
    }
    
    if (placeResult == null) {
      print('⚠️ VERIFY LOCATION: Could not verify "$name"');
      return null;
    }
    
    // === Extract coordinates and details ===
    final placeId = (placeResult['placeId'] ?? placeResult['place_id']) as String?;
    var coordinates = _extractCoordinates(placeResult);
    var address = (placeResult['formatted_address'] ?? placeResult['address'] ?? placeResult['description']) as String?;
    var resultName = (placeResult['name'] ?? placeResult['description']?.toString().split(',').first) as String? ?? name;
    String? website;
    
    // Fetch place details if needed
    if (placeId != null && placeId.isNotEmpty && coordinates == null) {
      print('🔍 VERIFY LOCATION: Fetching place details for: $placeId');
      try {
        final placeDetails = await _maps.getPlaceDetails(placeId, includePhotoUrl: false);
        if (placeDetails.latitude != 0.0 || placeDetails.longitude != 0.0) {
          coordinates = LatLng(placeDetails.latitude, placeDetails.longitude);
          address = placeDetails.address ?? address;
          website = placeDetails.website;
          final businessName = placeDetails.displayName ?? placeDetails.getPlaceName();
          if (businessName.isNotEmpty) {
            resultName = businessName;
          }
        }
      } catch (e) {
        print('⚠️ VERIFY LOCATION: Error fetching place details: $e');
      }
    }
    
    return ExtractedLocationData(
      placeId: placeId,
      name: resultName,
      address: address,
      coordinates: coordinates,
      type: _inferPlaceTypeFromResult(placeResult, geminiType),
      source: ExtractionSource.placesSearch,
      confidence: coordinates != null ? 0.85 : 0.6,
      placeTypes: (placeResult['types'] as List?)?.cast<String>(),
      website: website,
      originalQuery: name != resultName ? name : null,
    );
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
  /// [onProgress] - Optional callback for progress updates during location verification
  /// No limit on number of locations - extracts all found locations
  /// 
  /// Returns a tuple with locations and the raw extracted text from OCR (for user verification).
  Future<({List<ExtractedLocationData> locations, String? extractedText})> extractLocationsFromImage(
    File imageFile, {
    LatLng? userLocation,
    ExtractionProgressCallback? onProgress,
  }) async {
    print('📷 IMAGE EXTRACTION: Starting extraction from image...');
    
    try {
      // Step 1: Use Gemini Vision to extract location names/text from the image
      onProgress?.call(0, 1, 'Analyzing image with AI...');
      final geminiResult = await _gemini.extractLocationNamesFromImageFile(imageFile);
      final extractedNames = geminiResult.locations;
      final extractedText = geminiResult.extractedText;

      if (extractedNames.isEmpty) {
        print('⚠️ IMAGE EXTRACTION: Gemini Vision found no locations in image');
        return (locations: <ExtractedLocationData>[], extractedText: extractedText);
      }

      // Get the region context from the first location (all locations share the same context)
      final regionContext = extractedNames.isNotEmpty ? extractedNames.first.regionContext : null;
      
      print('📷 IMAGE EXTRACTION: Gemini found ${extractedNames.length} potential location(s), verifying with Places API...');
      if (regionContext != null) {
        print('🌍 IMAGE EXTRACTION: Region context: "$regionContext"');
      }

      // Step 2: Verify each location with Google Places API
      final results = <ExtractedLocationData>[];
      final totalLocations = extractedNames.length;
      var currentIndex = 0;
      
      for (final locationInfo in extractedNames) {
        currentIndex++;
        onProgress?.call(currentIndex, totalLocations, 'Verifying ${locationInfo.name}...');
        
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
        // Add region context for better disambiguation, BUT only if not already in the name
        // This prevents "White Mountains, New Hampshire" + "New Hampshire" → "White Mountains, New Hampshire, New Hampshire"
        if (effectiveRegionContext != null && effectiveRegionContext.isNotEmpty) {
          final nameLower = locationInfo.name.toLowerCase();
          final contextLower = effectiveRegionContext.toLowerCase();
          if (!nameLower.contains(contextLower)) {
            searchQuery += ', $effectiveRegionContext';
            print('📷 IMAGE EXTRACTION: Searching Places API for: $searchQuery (with region context)');
          } else {
            print('📷 IMAGE EXTRACTION: Searching Places API for: $searchQuery (region already in name)');
          }
        } else {
          print('📷 IMAGE EXTRACTION: Searching Places API for: $searchQuery');
        }
        
        // Search Places API
        var placeResults = await _maps.searchPlaces(
          searchQuery,
          latitude: userLocation?.latitude,
          longitude: userLocation?.longitude,
        );
        
        // Use sophisticated scoring with context (same as multi-image extraction)
        // Pass grounded address for location name matching (e.g., "The Grove" in address)
        var placeResult = _selectBestPlaceResultWithContext(
          placeResults,
          locationInfo.name,
          geminiType: locationInfo.type,
          city: locationInfo.city,
          regionContext: effectiveRegionContext,
          groundedAddress: locationInfo.address,
        );
        bool usedBroaderSearch = false;
        
        // Check if the found result is a good name AND type match
        // This handles cases like:
        // - Searching for "Afton Villa Gardens" but finding "Afton Villa Offices"
        // - Searching for "Lake Crescent" (Lake) but finding "Lake Crescent Road" (route)
        if (placeResult != null && effectiveRegionContext != null) {
          final foundName = (placeResult['name'] ?? placeResult['description']?.toString().split(',').first ?? '') as String;
          final matchQuality = _checkNameMatchQuality(locationInfo.name, foundName);
          
          // Also check type compatibility
          final placeTypes = (placeResult['types'] as List?)?.cast<String>() ?? [];
          final isTypeCompatible = _isTypeCompatible(locationInfo.type, placeTypes);
          
          // Consider it a poor match if either name OR type doesn't match
          final isGoodMatch = matchQuality.isGoodMatch && isTypeCompatible;
          
          if (!isGoodMatch) {
            final reason = !matchQuality.isGoodMatch 
                ? 'Poor name match (${(matchQuality.matchScore * 100).toInt()}%)'
                : 'Type mismatch (expected ${locationInfo.type}, got ${placeTypes.take(3).join(", ")})';
            print('⚠️ IMAGE EXTRACTION: $reason: "${locationInfo.name}" → "$foundName"');
            
            // Try a broader regional search (e.g., just "Louisiana" instead of "Baton Rouge, Louisiana")
            final broaderRegion = _extractBroaderRegion(effectiveRegionContext);
            if (broaderRegion != null) {
              print('🔄 IMAGE EXTRACTION: Trying broader search with region: $broaderRegion');
              
              String broaderSearchQuery = locationInfo.name;
              if (locationInfo.address != null) {
                broaderSearchQuery += ' ${locationInfo.address}';
              }
              broaderSearchQuery += ', $broaderRegion';
              
              print('📷 IMAGE EXTRACTION: Broader search: $broaderSearchQuery');
              
              final broaderResults = await _maps.searchPlaces(
                broaderSearchQuery,
                latitude: userLocation?.latitude,
                longitude: userLocation?.longitude,
              );
              
              if (broaderResults.isNotEmpty) {
                final broaderResult = _selectBestPlaceResultWithContext(
                  broaderResults,
                  locationInfo.name,
                  geminiType: locationInfo.type,
                  city: locationInfo.city,
                  regionContext: effectiveRegionContext,
                  groundedAddress: locationInfo.address,
                );
                
                if (broaderResult != null) {
                  final broaderFoundName = (broaderResult['name'] ?? broaderResult['description']?.toString().split(',').first ?? '') as String;
                  final broaderMatchQuality = _checkNameMatchQuality(locationInfo.name, broaderFoundName);
                  final broaderPlaceTypes = (broaderResult['types'] as List?)?.cast<String>() ?? [];
                  final broaderIsTypeCompatible = _isTypeCompatible(locationInfo.type, broaderPlaceTypes);
                  
                  print('📷 IMAGE EXTRACTION: Broader search found: "$broaderFoundName" (match: ${(broaderMatchQuality.matchScore * 100).toInt()}%, type compatible: $broaderIsTypeCompatible)');
                  
                  // Use broader result if it's a better match (either better name OR better type)
                  final broaderIsBetter = (broaderMatchQuality.matchScore > matchQuality.matchScore) ||
                      (broaderIsTypeCompatible && !isTypeCompatible);
                  if (broaderIsBetter) {
                    print('✅ IMAGE EXTRACTION: Using broader search result (better match)');
                    placeResult = broaderResult;
                    usedBroaderSearch = true;
                  } else {
                    print('📷 IMAGE EXTRACTION: Keeping original result (broader search not better)');
                  }
                }
              }
            }
          }
        } else if (placeResult == null && effectiveRegionContext != null) {
          // No results with full region context, try broader search
          final broaderRegion = _extractBroaderRegion(effectiveRegionContext);
          if (broaderRegion != null) {
            print('🔄 IMAGE EXTRACTION: No results, trying broader search with: $broaderRegion');
            
            String broaderSearchQuery = locationInfo.name;
            if (locationInfo.address != null) {
              broaderSearchQuery += ' ${locationInfo.address}';
            }
            broaderSearchQuery += ', $broaderRegion';
            
            placeResults = await _maps.searchPlaces(
              broaderSearchQuery,
              latitude: userLocation?.latitude,
              longitude: userLocation?.longitude,
            );
            
            if (placeResults.isNotEmpty) {
              placeResult = _selectBestPlaceResultWithContext(
                placeResults,
                locationInfo.name,
                geminiType: locationInfo.type,
                city: locationInfo.city,
                regionContext: effectiveRegionContext,
                groundedAddress: locationInfo.address,
              );
              usedBroaderSearch = true;
            }
          }
        }
        
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
              final placeDetails = await _maps.getPlaceDetails(placeId, includePhotoUrl: false);
              if (placeDetails.latitude != 0.0 || placeDetails.longitude != 0.0) {
                coordinates = LatLng(placeDetails.latitude, placeDetails.longitude);
                address = placeDetails.address ?? address;
                website = placeDetails.website;
                // Use the business name from place details if we had just an address
                final businessName = placeDetails.displayName ?? placeDetails.getPlaceName();
                if (isJustAddress && businessName.isNotEmpty) {
                  name = businessName;
                  print('📷 IMAGE EXTRACTION: Found business name from place details: $name');
                } else if (name.isEmpty) {
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
              final placeDetails = await _maps.getPlaceDetails(placeId, includePhotoUrl: false);
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
          
          // === AI RERANKING: Apply when initial match quality is low ===
          // Collect all candidate results for potential AI reranking
          final allCandidates = [...placeResults];
          final selectedIndex = allCandidates.indexOf(placeResult);
          
          // Check if we need AI reranking based on match quality
          final rerankResult = await _maybeAIRerank(
            originalName: locationInfo.name,
            candidates: allCandidates,
            selectedIndex: selectedIndex >= 0 ? selectedIndex : 0,
            geminiType: locationInfo.type,
            regionContext: effectiveRegionContext,
            surroundingText: null, // Could pass caption text here if available
            userLocation: userLocation,
            usedBroaderSearch: usedBroaderSearch,
          );
          
          // Update result based on AI reranking
          var finalPlaceResult = placeResult;
          var finalConfidence = coordinates != null ? (usedBroaderSearch ? 0.80 : 0.85) : 0.60;
          var needsConfirmation = false;
          
          if (rerankResult.usedAIRerank && rerankResult.selectedResult != null) {
            finalPlaceResult = rerankResult.selectedResult!;
            finalConfidence = rerankResult.confidence;
            needsConfirmation = rerankResult.needsConfirmation;
            
            // If AI selected a different result, update placeId and refetch details
            if (finalPlaceResult != placeResult) {
              final newPlaceId = (finalPlaceResult['placeId'] ?? finalPlaceResult['place_id']) as String?;
              if (newPlaceId != null && newPlaceId.isNotEmpty) {
                print('🤖 IMAGE EXTRACTION: AI reranking selected different result, fetching details for: $newPlaceId');
                try {
                  final newPlaceDetails = await _maps.getPlaceDetails(newPlaceId);
                  if (newPlaceDetails.latitude != 0.0 || newPlaceDetails.longitude != 0.0) {
                    coordinates = LatLng(newPlaceDetails.latitude, newPlaceDetails.longitude);
                    address = newPlaceDetails.address ?? address;
                    website = newPlaceDetails.website ?? website;
                    name = newPlaceDetails.displayName ?? finalPlaceResult['name'] as String? ?? name;
                    print('✅ IMAGE EXTRACTION: AI-reranked result: "$name" at ${coordinates.latitude}, ${coordinates.longitude}');
                  }
                } catch (e) {
                  print('⚠️ IMAGE EXTRACTION: Error fetching AI-reranked place details: $e');
                }
              }
            }
          }
          
          // Store original query only if it's different from the resolved name
          final originalQueryText = locationInfo.name != name ? locationInfo.name : null;
          
          final extractedData = ExtractedLocationData(
            placeId: placeId,
            name: name,
            address: address,
            coordinates: coordinates,
            type: _inferPlaceTypeFromResult(finalPlaceResult, locationInfo.type),
            source: ExtractionSource.placesSearch,
            confidence: coordinates != null ? finalConfidence : finalConfidence * 0.7, // Higher confidence with coordinates
            placeTypes: (finalPlaceResult['types'] as List?)?.cast<String>(),
            website: website,
            needsConfirmation: needsConfirmation,
            originalQuery: originalQueryText,
          );
          
          // Avoid duplicates
          if (!_isDuplicate(extractedData, results)) {
            results.add(extractedData);
            final searchType = usedBroaderSearch ? ' (via broader search)' : '';
            final rerankType = rerankResult.usedAIRerank ? ' (AI reranked)' : '';
            print('✅ IMAGE EXTRACTION: Verified location: ${extractedData.name} at ${coordinates?.latitude}, ${coordinates?.longitude}$searchType$rerankType');
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
      return (locations: results, extractedText: extractedText);
    } catch (e) {
      print('❌ IMAGE EXTRACTION ERROR: $e');
      return (locations: <ExtractedLocationData>[], extractedText: null);
    }
  }

  /// Extract locations from MULTIPLE images analyzed TOGETHER
  /// 
  /// This is the preferred method when you have multiple screenshots from the same content
  /// (e.g., Instagram video frame + caption screenshot). It analyzes all images together
  /// to understand the combined context and find the actual location.
  /// 
  /// **Why this is better than analyzing separately:**
  /// - Image 1 might show "POET TREES" sign (art at the location)
  /// - Image 2 might describe "library in the redwoods of Big Sur"
  /// - Together, this should find "Henry Miller Memorial Library"
  /// - Separately, neither image has enough context
  /// 
  /// [images] - List of image data (bytes and mimeType)
  /// [userLocation] - Optional user location for better Places API results
  /// [onProgress] - Optional callback for progress updates during location verification
  /// 
  /// Returns extracted locations with combined region context and extracted text
  Future<({List<ExtractedLocationData> locations, String? regionContext, String? extractedText})> extractLocationsFromMultipleImages(
    List<({Uint8List bytes, String mimeType})> images, {
    LatLng? userLocation,
    ExtractionProgressCallback? onProgress,
  }) async {
    print('📷 MULTI-IMAGE EXTRACTION: Analyzing ${images.length} images together...');

    try {
      // Step 1: Use Gemini to analyze all images together
      onProgress?.call(0, 1, 'Analyzing images with AI...');
      final geminiResult = await _gemini.extractLocationsFromMultipleImages(images);
      
      if (geminiResult.locations.isEmpty) {
        print('⚠️ MULTI-IMAGE EXTRACTION: No locations found in combined analysis');
        return (locations: <ExtractedLocationData>[], regionContext: geminiResult.regionContext, extractedText: geminiResult.extractedText);
      }

      print('📷 MULTI-IMAGE EXTRACTION: Gemini found ${geminiResult.locations.length} location(s)');
      if (geminiResult.regionContext != null) {
        print('🌍 MULTI-IMAGE EXTRACTION: Region context: "${geminiResult.regionContext}"');
      }

      // Step 2: Verify with Places API using "broader first, then filter" strategy
      // This approach gets more candidates by starting broad, then uses specific details to rank them
      final results = <ExtractedLocationData>[];
      final totalLocations = geminiResult.locations.length;
      var currentIndex = 0;

      for (final locationInfo in geminiResult.locations) {
        currentIndex++;
        onProgress?.call(currentIndex, totalLocations, 'Verifying ${locationInfo.name}...');
        print('📷 MULTI-IMAGE EXTRACTION: Verifying "${locationInfo.name}" with Places API...');
        if (locationInfo.address != null && locationInfo.address!.isNotEmpty) {
          print('📷 MULTI-IMAGE EXTRACTION: Using grounded address for scoring: "${locationInfo.address}"');
        }
        
        // Extract STATE specifically from context for search queries
        // This is more reliable than using arbitrary "broader region" which might return
        // things like "Neah Bay, Olympic National Park" instead of "Washington"
        final stateFromContext = _extractStateFromContext(geminiResult.regionContext) ??
            _extractStateFromContext(locationInfo.regionContext) ??
            _extractStateFromContext(locationInfo.city);
        
        // Fall back to broader region only if no state found (for international locations)
        final broaderRegion = stateFromContext == null ? _extractBroaderRegion(geminiResult.regionContext) : null;
        
        // STRATEGY: Search with region context first (if available), then fall back to exact term
        // This helps disambiguate common names like "Hole-in-the-Wall" by including geographic context
        
        Map<String, dynamic>? placeResult;
        var placeResults = <Map<String, dynamic>>[];
        bool usedBroaderSearch = false;
        
        // Build context search query: ALWAYS use "name, state" format
        // Adding city makes searches too specific and returns wrong results
        // For "Makah Reservation" with context "Neah Bay, Washington"
        // Search "Makah Reservation, Washington" NOT "Makah Reservation, Neah Bay, Washington"
        final contextSearchParts = <String>[locationInfo.name];
        if (stateFromContext != null) {
          // Best case: we found a state, use "name, state" format
          contextSearchParts.add(stateFromContext);
        } else if (broaderRegion != null) {
          // Fallback: no state found, use broader region (for international locations)
          contextSearchParts.add(broaderRegion);
        }
        final hasRegionContext = stateFromContext != null || broaderRegion != null;
        
        // Step 0 (NEW): If we have a grounded address, search by address FIRST for best accuracy
        // This catches cases where the business name returned by Gemini is incorrect,
        // but the address in the extracted text is correct (e.g., Mother's Kitchen vs Mother's Market & Kitchen)
        if (locationInfo.address != null && locationInfo.address!.isNotEmpty) {
          final addressQuery = locationInfo.address!;
          print('📷 MULTI-IMAGE EXTRACTION: PRIORITY SEARCH by grounded address: "$addressQuery"');
          
          final addressResults = await _maps.searchPlaces(
            addressQuery,
            latitude: userLocation?.latitude,
            longitude: userLocation?.longitude,
          );
          
          if (addressResults.isNotEmpty) {
            print('📷 MULTI-IMAGE EXTRACTION: Found ${addressResults.length} candidates from address search');
            
            // For address search, prioritize exact address matches
            placeResult = _selectBestPlaceResultWithContext(
              addressResults,
              locationInfo.name,
              geminiType: locationInfo.type,
              city: locationInfo.city,
              regionContext: geminiResult.regionContext,
              groundedAddress: locationInfo.address,
            );
            
            if (placeResult != null) {
              final foundName = (placeResult['name'] ?? placeResult['description']?.toString().split(',').first ?? '') as String;
              final foundAddress = (placeResult['formatted_address'] ?? placeResult['description'] ?? '') as String;
              final addressMatchScore = _calculateAddressSimilarity(locationInfo.address!, foundAddress);
              
              print('📷 MULTI-IMAGE EXTRACTION: Best candidate from address search: "$foundName"');
              print('📷 MULTI-IMAGE EXTRACTION: Address match: ${(addressMatchScore * 100).toInt()}%');
              
              // If address match is good (>60%), use this result even if name doesn't match
              if (addressMatchScore >= 0.6) {
                print('✅ MULTI-IMAGE EXTRACTION: Using address-verified result (name may differ from Gemini search)');
                placeResults = addressResults;
              } else {
                print('⚠️ MULTI-IMAGE EXTRACTION: Address match too low, will try name search');
                placeResult = null; // Reset to try name search
              }
            }
          }
        }
        
        // Step 1: If we have region context (and no good address match yet), search with it
        if (placeResults.isEmpty && hasRegionContext) {
          final contextSearchQuery = contextSearchParts.join(', ');
          print('📷 MULTI-IMAGE EXTRACTION: Searching with region context: "$contextSearchQuery"');
          
          placeResults = await _maps.searchPlaces(
            contextSearchQuery,
            latitude: userLocation?.latitude,
            longitude: userLocation?.longitude,
          );
          
          if (placeResults.isNotEmpty) {
            print('📷 MULTI-IMAGE EXTRACTION: Found ${placeResults.length} candidates from context search');
            
            // Use context clues to filter and score the candidates
            placeResult = _selectBestPlaceResultWithContext(
              placeResults,
              locationInfo.name,
              geminiType: locationInfo.type,
              city: locationInfo.city,
              regionContext: geminiResult.regionContext,
              groundedAddress: locationInfo.address,
            );
            
            if (placeResult != null) {
              final foundName = (placeResult['name'] ?? placeResult['description']?.toString().split(',').first ?? '') as String;
              final matchQuality = _checkNameMatchQuality(locationInfo.name, foundName);
              final placeTypes = (placeResult['types'] as List?)?.cast<String>() ?? [];
              final isTypeCompatible = _isTypeCompatible(locationInfo.type, placeTypes);
              
              print('📷 MULTI-IMAGE EXTRACTION: Best candidate: "$foundName" (match: ${(matchQuality.matchScore * 100).toInt()}%, type compatible: $isTypeCompatible)');
            }
          } else {
            print('📷 MULTI-IMAGE EXTRACTION: No results from context search');
          }
        }
        
        // Step 2: If no results from context search (or no context available), try exact term only
        if (placeResults.isEmpty) {
          print('📷 MULTI-IMAGE EXTRACTION: Searching exact term: "${locationInfo.name}"');
          
          placeResults = await _maps.searchPlaces(
            locationInfo.name,
            latitude: userLocation?.latitude,
            longitude: userLocation?.longitude,
          );
          usedBroaderSearch = true; // Mark as broader since we lost region specificity
          
          if (placeResults.isNotEmpty) {
            print('📷 MULTI-IMAGE EXTRACTION: Found ${placeResults.length} candidates from exact search');
            
            // Use context clues (type, city, region) to filter and score the candidates
            placeResult = _selectBestPlaceResultWithContext(
              placeResults,
              locationInfo.name,
              geminiType: locationInfo.type,
              city: locationInfo.city,
              regionContext: geminiResult.regionContext,
              groundedAddress: locationInfo.address,
            );
            
            if (placeResult != null) {
              final foundName = (placeResult['name'] ?? placeResult['description']?.toString().split(',').first ?? '') as String;
              final matchQuality = _checkNameMatchQuality(locationInfo.name, foundName);
              final placeTypes = (placeResult['types'] as List?)?.cast<String>() ?? [];
              final isTypeCompatible = _isTypeCompatible(locationInfo.type, placeTypes);
              
              print('📷 MULTI-IMAGE EXTRACTION: Best candidate: "$foundName" (match: ${(matchQuality.matchScore * 100).toInt()}%, type compatible: $isTypeCompatible)');
            }
          }
        }
        
        // Step 3: If match quality is below 95% or type incompatible, run Text Search for more candidates
        var allCandidates = [...placeResults];
        if (placeResult != null) {
          final foundName = (placeResult['name'] ?? placeResult['description']?.toString().split(',').first ?? '') as String;
          final matchQuality = _checkNameMatchQuality(locationInfo.name, foundName);
          final placeTypes = (placeResult['types'] as List?)?.cast<String>() ?? [];
          final isTypeCompatible = _isTypeCompatible(locationInfo.type, placeTypes);
          
          // If below 95% match OR type incompatible, get more results from Text Search API
          if (matchQuality.matchScore < 0.95 || !isTypeCompatible) {
            print('🔍 MULTI-IMAGE EXTRACTION: Match quality ${(matchQuality.matchScore * 100).toInt()}% < 95% or type incompatible, running Text Search for more candidates...');
            
            // Build search query with state context for text search
            // ALWAYS use "name, state" format - never include city
            final textSearchParts = <String>[locationInfo.name];
            if (stateFromContext != null) {
              textSearchParts.add(stateFromContext);
            } else if (broaderRegion != null) {
              textSearchParts.add(broaderRegion);
            }
            final textSearchQuery = textSearchParts.join(', ');

            print('🔍 MULTI-IMAGE EXTRACTION: Running Text Search with query: "$textSearchQuery"');

            final textSearchResults = await _maps.searchPlacesTextSearch(
              textSearchQuery,
              latitude: userLocation?.latitude,
              longitude: userLocation?.longitude,
            );

            print('🔍 MULTI-IMAGE EXTRACTION: Text Search returned ${textSearchResults.length} raw results');

            // Log each text search result
            for (int i = 0; i < textSearchResults.length; i++) {
              final result = textSearchResults[i];
              final name = (result['name'] ?? result['description']?.toString().split(',').first ?? 'Unknown') as String;
              final placeId = result['placeId'] as String?;
              final types = (result['types'] as List?)?.cast<String>() ?? [];
              print('🔍 MULTI-IMAGE EXTRACTION: Text Search result ${i+1}: "$name" (ID: ${placeId ?? 'null'}, types: ${types.take(2).join(', ')})');
            }

            if (textSearchResults.isEmpty) {
              print('🔍 MULTI-IMAGE EXTRACTION: Text Search found no additional candidates');
            }

            if (textSearchResults.isNotEmpty) {
              print('🔍 MULTI-IMAGE EXTRACTION: Text Search found ${textSearchResults.length} additional candidates');

              // Add text search results that aren't duplicates (by placeId)
              final existingPlaceIds = placeResults.map((r) => r['placeId'] as String?).toSet();
              int addedCount = 0;
              int duplicateCount = 0;

              for (final result in textSearchResults) {
                final placeId = result['placeId'] as String?;
                final name = (result['name'] ?? result['description']?.toString().split(',').first ?? 'Unknown') as String;

                if (placeId != null && !existingPlaceIds.contains(placeId)) {
                  allCandidates.add(result);
                  existingPlaceIds.add(placeId);
                  addedCount++;
                  print('✅ MULTI-IMAGE EXTRACTION: Added new candidate: "$name" (ID: $placeId)');
                } else if (placeId != null) {
                  duplicateCount++;
                  print('⏭️ MULTI-IMAGE EXTRACTION: Skipped duplicate: "$name" (ID: $placeId)');
                } else {
                  print('⚠️ MULTI-IMAGE EXTRACTION: Skipped result with no placeId: "$name"');
                }
              }

              print('🔍 MULTI-IMAGE EXTRACTION: Added $addedCount new candidates, skipped $duplicateCount duplicates');
              print('🔍 MULTI-IMAGE EXTRACTION: Combined ${allCandidates.length} total candidates for AI reranking');
              
              // Re-select best result from combined candidates
              final combinedBestResult = _selectBestPlaceResultWithContext(
                allCandidates,
                locationInfo.name,
                geminiType: locationInfo.type,
                city: locationInfo.city,
                regionContext: geminiResult.regionContext,
                groundedAddress: locationInfo.address,
              );
              
              if (combinedBestResult != null) {
                final combinedFoundName = (combinedBestResult['name'] ?? combinedBestResult['description']?.toString().split(',').first ?? '') as String;
                final combinedMatchQuality = _checkNameMatchQuality(locationInfo.name, combinedFoundName);
                final combinedPlaceTypes = (combinedBestResult['types'] as List?)?.cast<String>() ?? [];
                final combinedIsTypeCompatible = _isTypeCompatible(locationInfo.type, combinedPlaceTypes);
                
                print('🔍 MULTI-IMAGE EXTRACTION: Combined best candidate: "$combinedFoundName" (match: ${(combinedMatchQuality.matchScore * 100).toInt()}%, type compatible: $combinedIsTypeCompatible)');
                placeResult = combinedBestResult;
              }
            }
          }
        }
        
        if (placeResult != null) {
          // === AI RERANKING: Apply when initial match quality is low ===
          // IMPORTANT: Use all candidates (from both Autocomplete and Text Search)
          final selectedIndex = allCandidates.indexOf(placeResult);
          
          final rerankResult = await _maybeAIRerank(
            originalName: locationInfo.name,
            candidates: allCandidates,
            selectedIndex: selectedIndex >= 0 ? selectedIndex : 0,
            geminiType: locationInfo.type,
            regionContext: geminiResult.regionContext,
            surroundingText: null,
            userLocation: userLocation,
            usedBroaderSearch: usedBroaderSearch,
          );
          
          // Update result based on AI reranking
          var finalPlaceResult = placeResult;
          var finalConfidence = 0.85;
          var needsConfirmation = false;
          
          if (rerankResult.usedAIRerank && rerankResult.selectedResult != null) {
            finalPlaceResult = rerankResult.selectedResult!;
            finalConfidence = rerankResult.confidence;
            needsConfirmation = rerankResult.needsConfirmation;
            print('🤖 MULTI-IMAGE EXTRACTION: AI reranking applied (confidence: ${(finalConfidence * 100).toInt()}%)');
          } else {
            finalConfidence = 0.85;
          }
          
          // Extract coordinates and details from final place result
          final placeId = (finalPlaceResult['placeId'] ?? finalPlaceResult['place_id']) as String?;
          var coordinates = _extractCoordinates(finalPlaceResult);
          var address = (finalPlaceResult['formatted_address'] ?? finalPlaceResult['address'] ?? finalPlaceResult['description']) as String?;
          var name = (finalPlaceResult['name'] ?? finalPlaceResult['description']?.toString().split(',').first) as String? ?? locationInfo.name;
          String? website;
          
          // Fetch place details if needed (skip photo URLs for efficiency)
          if (placeId != null && placeId.isNotEmpty && coordinates == null) {
            print('📷 MULTI-IMAGE EXTRACTION: Fetching place details for: $placeId');
            try {
              final placeDetails = await _maps.getPlaceDetails(placeId, includePhotoUrl: false);
              if (placeDetails.latitude != 0.0 || placeDetails.longitude != 0.0) {
                coordinates = LatLng(placeDetails.latitude, placeDetails.longitude);
                address = placeDetails.address ?? address;
                website = placeDetails.website;
                final businessName = placeDetails.displayName ?? placeDetails.getPlaceName();
                if (businessName.isNotEmpty) {
                  name = businessName;
                }
              }
            } catch (e) {
              print('⚠️ MULTI-IMAGE EXTRACTION: Error fetching place details: $e');
            }
          }
          
          // Store original query only if it's different from the resolved name
          final originalQueryText = locationInfo.name != name ? locationInfo.name : null;
          
          final extractedData = ExtractedLocationData(
            placeId: placeId,
            name: name,
            address: address,
            coordinates: coordinates,
            type: _inferPlaceTypeFromResult(finalPlaceResult, locationInfo.type),
            source: ExtractionSource.placesSearch,
            confidence: coordinates != null ? finalConfidence : finalConfidence * 0.7,
            placeTypes: (finalPlaceResult['types'] as List?)?.cast<String>(),
            website: website,
            needsConfirmation: needsConfirmation,
            originalQuery: originalQueryText,
          );
          
          if (!_isDuplicate(extractedData, results)) {
            results.add(extractedData);
            final searchType = usedBroaderSearch ? ' (via context search)' : ' (via exact search)';
            final rerankType = rerankResult.usedAIRerank ? ' (AI reranked)' : '';
            print('✅ MULTI-IMAGE EXTRACTION: Verified "${extractedData.name}" at ${extractedData.address}$searchType$rerankType');
          }
        } else {
          print('⚠️ MULTI-IMAGE EXTRACTION: Could not verify "${locationInfo.name}" with Places API');
        }
      }

      print('📷 MULTI-IMAGE EXTRACTION: Final result - ${results.length} verified location(s)');
      return (locations: results, regionContext: geminiResult.regionContext, extractedText: geminiResult.extractedText);
    } catch (e, stackTrace) {
      print('❌ MULTI-IMAGE EXTRACTION ERROR: $e');
      print('Stack trace: $stackTrace');
      return (locations: <ExtractedLocationData>[], regionContext: null, extractedText: null);
    }
  }

  /// Extract locations from image bytes
  /// No limit on number of locations - extracts all found locations
  ///
  /// [regionContextHint] - Optional region context from previous screenshots in the same scan.
  /// This is used when the current image doesn't have its own region context but we know
  /// from other images in the same content what region we're looking at.
  /// [onProgress] - Optional callback for progress updates during location verification
  ///
  /// Returns a tuple-like result: the list of locations, the detected region context, and
  /// the raw extracted text from OCR. The region context can be used for subsequent screenshot analysis.
  /// The extractedText can be shown to users to verify what was scanned.
  Future<({List<ExtractedLocationData> locations, String? regionContext, String? extractedText})> extractLocationsFromImageBytes(
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
    LatLng? userLocation,
    String? regionContextHint,
    ExtractionProgressCallback? onProgress,
  }) async {
    print('📷 IMAGE EXTRACTION: Starting extraction from image bytes...');
    if (regionContextHint != null) {
      print('📷 IMAGE EXTRACTION: Using region context hint: "$regionContextHint"');
    }
    
    try {
      // Step 1: Use Gemini Vision to extract location names
      onProgress?.call(0, 1, 'Analyzing image with AI...');
      final geminiResult = await _gemini.extractLocationNamesFromImage(
        imageBytes,
        mimeType: mimeType,
      );
      final extractedNames = geminiResult.locations;
      final extractedText = geminiResult.extractedText;

      if (extractedNames.isEmpty) {
        print('⚠️ IMAGE EXTRACTION: No locations found in image');
        return (locations: <ExtractedLocationData>[], regionContext: regionContextHint, extractedText: extractedText);
      }

      // Get the region context from the first location (all locations share the same context)
      // If not found, use the hint from previous screenshots
      final detectedRegionContext = extractedNames.isNotEmpty ? extractedNames.first.regionContext : null;
      final regionContext = detectedRegionContext ?? regionContextHint;
      
      // Log what Gemini found for debugging
      print('📷 IMAGE EXTRACTION: Gemini returned ${extractedNames.length} location(s):');
      if (regionContext != null) {
        print('🌍 IMAGE EXTRACTION: Region context: "$regionContext"${detectedRegionContext == null && regionContextHint != null ? " (from hint)" : ""}');
      }
      for (final loc in extractedNames) {
        print('   📍 Name: "${loc.name}", City: "${loc.city}", Type: "${loc.type}", Address: "${loc.address}"');
      }

      // Step 2: Verify with Places API
      final results = <ExtractedLocationData>[];
      final totalLocations = extractedNames.length;
      var currentIndex = 0;
      
      for (final locationInfo in extractedNames) {
        currentIndex++;
        onProgress?.call(currentIndex, totalLocations, 'Verifying ${locationInfo.name}...');
        
        // Strategy: Try multiple search queries to get the best result
        // 1. First try name + type + city + region (for restaurants/food)
        // 2. Then try name + region context
        // 3. If no good results, try name + city
        // 4. If still no results, try name + type
        
        List<Map<String, dynamic>> placeResults = [];
        Map<String, dynamic>? placeResult;
        
        // Use region context if available (from Gemini's analysis of overall content OR from hint)
        final effectiveRegionContext = locationInfo.regionContext ?? regionContext;
        
        // Check if Gemini identified this as a food establishment
        final typeLower = locationInfo.type?.toLowerCase() ?? '';
        final isRestaurantType = typeLower == 'restaurant' ||
                                 typeLower == 'cafe' ||
                                 typeLower == 'bar' ||
                                 typeLower == 'food' ||
                                 typeLower == 'bakery' ||
                                 typeLower == 'coffee_shop';
        // Check if Gemini identified this as a hotel/lodging
        final isHotelType = typeLower == 'hotel' ||
                            typeLower == 'lodging' ||
                            typeLower == 'resort' ||
                            typeLower == 'inn' ||
                            typeLower == 'motel';
        
        // Build search query - use ALL available context for food establishments
        // This is CRITICAL for cases like "@rockcreek206" → "RockCreek - Seafood & Spirits"
        // Search: "Rockcreek restaurant Seattle Washington" instead of just "Rockcreek, Washington"
        String searchQuery;
        
        if (isRestaurantType && locationInfo.city != null && locationInfo.city!.isNotEmpty) {
          // For restaurants: include type and city in initial search
          // "Rockcreek restaurant Seattle Washington" is much more specific
          searchQuery = '${locationInfo.name} ${locationInfo.type}';
          searchQuery += ', ${locationInfo.city}';
          // Only add region context if not already in name or city
          if (effectiveRegionContext != null && effectiveRegionContext.isNotEmpty) {
            final nameLower = locationInfo.name.toLowerCase();
            final cityLower = locationInfo.city!.toLowerCase();
            final contextLower = effectiveRegionContext.toLowerCase();
            if (!nameLower.contains(contextLower) && !cityLower.contains(contextLower)) {
              searchQuery += ', $effectiveRegionContext';
            }
          }
          print('📷 IMAGE EXTRACTION: Searching Places API for: $searchQuery (restaurant with city)');
        } else if (effectiveRegionContext != null && effectiveRegionContext.isNotEmpty) {
          // Append region context to help Places API find the right location
          // BUT only if not already in the name to avoid "Stowe, Vermont, Vermont"
          final nameLower = locationInfo.name.toLowerCase();
          final contextLower = effectiveRegionContext.toLowerCase();
          if (!nameLower.contains(contextLower)) {
            searchQuery = '${locationInfo.name}, $effectiveRegionContext';
            print('📷 IMAGE EXTRACTION: Searching Places API for: $searchQuery (with region context)');
          } else {
            searchQuery = locationInfo.name;
            print('📷 IMAGE EXTRACTION: Searching Places API for: $searchQuery (region already in name)');
          }
        } else if (locationInfo.city != null && locationInfo.city!.isNotEmpty) {
          searchQuery = '${locationInfo.name}, ${locationInfo.city}';
          print('📷 IMAGE EXTRACTION: Searching Places API for: $searchQuery (with city)');
        } else {
          searchQuery = locationInfo.name;
          print('📷 IMAGE EXTRACTION: Searching Places API for: ${locationInfo.name}');
        }
        
        placeResults = await _maps.searchPlaces(
          searchQuery,
          latitude: userLocation?.latitude,
          longitude: userLocation?.longitude,
        );
        // Use sophisticated scoring with context (same as multi-image extraction)
        placeResult = _selectBestPlaceResultWithContext(
          placeResults,
          locationInfo.name,
          geminiType: locationInfo.type,
          city: locationInfo.city,
          regionContext: effectiveRegionContext,
          groundedAddress: locationInfo.address,
        );
        
        // Check if we got a good result appropriate for the type we're searching for
        bool gotGoodResult = false;
        if (placeResult != null) {
          final types = (placeResult['types'] as List?)?.cast<String>() ?? [];
          final isFood = types.any((t) => 
            t == 'food' || t == 'restaurant' || t == 'cafe' || t == 'bar' || 
            t == 'bakery' || t == 'meal_takeaway' || t == 'meal_delivery');
          final isEstablishment = types.any((t) => 
            t == 'establishment' || t == 'point_of_interest' || t == 'store');
          final isLocality = types.any((t) => 
            t == 'locality' || t == 'sublocality' || t == 'neighborhood' || t == 'political');
          final isRoute = types.any((t) => t == 'route' || t == 'geocode');
          final isHotel = types.any((t) => 
            t == 'hotel' || t == 'lodging' || t == 'resort');
          final isNaturalFeature = types.any((t) => 
            t == 'natural_feature' || t == 'park' || t == 'national_park');
          
          // For restaurant searches, we need a food establishment, not just any establishment
          if (isRestaurantType) {
            gotGoodResult = isFood;
            if (!gotGoodResult && !isRoute && isEstablishment) {
              gotGoodResult = true; // Accept other establishments as fallback
            }
          } else if (isHotelType) {
            // For hotel searches, we need a lodging establishment
            gotGoodResult = isHotel;
            if (!gotGoodResult && isEstablishment) {
              gotGoodResult = true; // Accept other establishments as fallback
            }
          } else if (typeLower == 'region' || typeLower == 'city' || typeLower == 'locality') {
            // CRITICAL: For region/city searches, localities ARE good results!
            // This prevents "NYC" (score 160) from being replaced by "City Island" (score 35)
            gotGoodResult = isLocality || isNaturalFeature;
          } else {
            gotGoodResult = isEstablishment || !isLocality;
          }
        }
        
        // Attempt 2: If searching for restaurant but didn't get a food result, try with just type
        if (!gotGoodResult && isRestaurantType) {
          String queryWithType = '${locationInfo.name} restaurant';
          if (locationInfo.city != null && locationInfo.city!.isNotEmpty) {
            queryWithType += ' ${locationInfo.city}';
          }
          // Only add region context if not already in name or city
          if (effectiveRegionContext != null && effectiveRegionContext.isNotEmpty) {
            final nameLower = locationInfo.name.toLowerCase();
            final cityLower = (locationInfo.city ?? '').toLowerCase();
            final contextLower = effectiveRegionContext.toLowerCase();
            if (!nameLower.contains(contextLower) && !cityLower.contains(contextLower)) {
              queryWithType += ', $effectiveRegionContext';
            }
          }
          print('📷 IMAGE EXTRACTION: Retrying restaurant search: $queryWithType');
          final resultsWithType = await _maps.searchPlaces(
            queryWithType,
            latitude: userLocation?.latitude,
            longitude: userLocation?.longitude,
          );
          final resultWithType = _selectBestPlaceResultWithContext(
            resultsWithType,
            locationInfo.name,
            geminiType: locationInfo.type,
            city: locationInfo.city,
            regionContext: effectiveRegionContext,
            groundedAddress: locationInfo.address,
          );
          
          if (resultWithType != null) {
            final types = (resultWithType['types'] as List?)?.cast<String>() ?? [];
            final isFood = types.any((t) => 
              t == 'food' || t == 'restaurant' || t == 'cafe' || t == 'bar' || 
              t == 'bakery' || t == 'meal_takeaway' || t == 'meal_delivery');
            final isEstablishment = types.any((t) => t == 'establishment' || t == 'point_of_interest');
            if (isFood || isEstablishment) {
              placeResult = resultWithType;
              gotGoodResult = true;
            }
          }
        }
        
        // Attempt 3: If no good result and we have a city, try with city (+ region context)
        if (!gotGoodResult && locationInfo.city != null && locationInfo.city!.isNotEmpty) {
          // Include region context for better disambiguation, but avoid redundancy
          String queryWithCity = '${locationInfo.name}, ${locationInfo.city}';
          if (effectiveRegionContext != null && effectiveRegionContext.isNotEmpty) {
            final nameLower = locationInfo.name.toLowerCase();
            final cityLower = locationInfo.city!.toLowerCase();
            final contextLower = effectiveRegionContext.toLowerCase();
            if (!nameLower.contains(contextLower) && !cityLower.contains(contextLower)) {
              queryWithCity = '${locationInfo.name}, ${locationInfo.city}, $effectiveRegionContext';
            }
          }
          print('📷 IMAGE EXTRACTION: Retrying with city: $queryWithCity');
          final resultsWithCity = await _maps.searchPlaces(
            queryWithCity,
            latitude: userLocation?.latitude,
            longitude: userLocation?.longitude,
          );
          final resultWithCity = _selectBestPlaceResultWithContext(
            resultsWithCity,
            locationInfo.name,
            geminiType: locationInfo.type,
            city: locationInfo.city,
            regionContext: effectiveRegionContext,
            groundedAddress: locationInfo.address,
          );
          
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
        
        // Attempt 4: Handle lookup - ALWAYS do this when we have an original handle
        // This helps resolve handles like "@sofaseattle" → "Social Fabric Cafe & Market"
        // CRITICAL: Handle lookup also finds the correct LOCATION for chain businesses
        // e.g., "@swingersus" in DC context → "Swingers" in Washington DC (not LA)
        final hasOriginalHandle = locationInfo.originalHandle != null && locationInfo.originalHandle!.isNotEmpty;
        
        // Always lookup handles - this is critical for finding correct locations
        // Chain businesses like "Swingers", "Beat The Bomb", "Muse Paintbar" have multiple locations
        if (hasOriginalHandle) {
          final lookupQuery = locationInfo.originalHandle!;
          print('🔎 HANDLE LOOKUP: Looking up "$lookupQuery" online...');
          
          try {
            // Look up the handle using Google Search - include region context for disambiguation
            final lookupCity = locationInfo.city ?? effectiveRegionContext?.split(',').first;
            final actualBusinessName = await _gemini.lookupInstagramHandle(
              lookupQuery,
              city: lookupCity,
            );
            
            if (actualBusinessName != null && actualBusinessName.isNotEmpty) {
              print('✅ HANDLE LOOKUP: $lookupQuery → "$actualBusinessName"');
              
              // Search for the actual business name WITH region context
              // This is critical for chain businesses to find the correct location
              String handleSearchQuery = actualBusinessName;
              if (locationInfo.type != null && locationInfo.type!.isNotEmpty && 
                  locationInfo.type != 'business' && locationInfo.type != 'unknown') {
                handleSearchQuery += ' ${locationInfo.type}';
              }
              if (locationInfo.city != null && locationInfo.city!.isNotEmpty) {
                handleSearchQuery += ', ${locationInfo.city}';
              }
              // Only add region context if not already in business name or city
              if (effectiveRegionContext != null && effectiveRegionContext.isNotEmpty) {
                final nameLower = actualBusinessName.toLowerCase();
                final cityLower = (locationInfo.city ?? '').toLowerCase();
                final contextLower = effectiveRegionContext.toLowerCase();
                if (!nameLower.contains(contextLower) && !cityLower.contains(contextLower)) {
                  handleSearchQuery += ', $effectiveRegionContext';
                }
              }
              
              print('🔎 HANDLE LOOKUP: Searching for: $handleSearchQuery');
              final handleResults = await _maps.searchPlaces(
                handleSearchQuery,
                latitude: userLocation?.latitude,
                longitude: userLocation?.longitude,
              );
              
              if (handleResults.isNotEmpty) {
                print('🔎 HANDLE LOOKUP: Got ${handleResults.length} result(s) from Places API');
                
                // First, check if any result directly matches the business name we searched for
                // This is more reliable than scoring since we searched for an exact name
                final actualNormalized = _normalizeCompact(actualBusinessName);
                Map<String, dynamic>? bestMatch;
                
                for (final result in handleResults) {
                  // Get name from either 'name' or 'description' field (autocomplete uses description)
                  final resultName = (result['name'] ?? result['description']?.toString().split(',').first ?? '') as String;
                  final resultNormalized = _normalizeCompact(resultName);
                  
                  print('🔎 HANDLE LOOKUP: Checking result: "$resultName"');
                  
                  // Check if this result matches the business name we looked up
                  if (actualNormalized.isNotEmpty && resultNormalized.isNotEmpty &&
                      (resultNormalized.contains(actualNormalized) || actualNormalized.contains(resultNormalized))) {
                    print('✅ HANDLE LOOKUP: Direct match found: "$resultName"');
                    bestMatch = result;
                    break; // Found exact match, use it
                  }
                }
                
                // If no direct match, use scoring with context but VALIDATE the result
                if (bestMatch == null) {
                  bestMatch = _selectBestPlaceResultWithContext(
                    handleResults,
                    actualBusinessName,
                    geminiType: locationInfo.type,
                    city: locationInfo.city,
                    regionContext: effectiveRegionContext,
                    groundedAddress: locationInfo.address,
                  );
                  
                  // CRITICAL: Validate that the result actually matches the business name
                  // This prevents "@followmeawaytravel" → "Follow Me Away" → "Miracle-Ear Hearing Aid Center"
                  if (bestMatch != null) {
                    final resultName = (bestMatch['name'] ?? bestMatch['description']?.toString().split(',').first ?? '') as String;
                    final resultNormalized = _normalizeCompact(resultName);
                    final searchNormalized = _normalizeCompact(actualBusinessName);
                    
                    // Check if there's any word overlap between result and what we searched for
                    final searchWords = actualBusinessName.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
                    final resultWords = resultName.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
                    final commonWords = searchWords.intersection(resultWords);
                    
                    // Also check compact containment
                    final hasCompactMatch = resultNormalized.contains(searchNormalized) || 
                                           searchNormalized.contains(resultNormalized);
                    
                    if (commonWords.isEmpty && !hasCompactMatch) {
                      // No word overlap AND no compact match - this is likely a false positive
                      print('⚠️ HANDLE LOOKUP: Rejecting "$resultName" - no match with searched name "$actualBusinessName"');
                      bestMatch = null;
                    }
                  }
                }
                
                if (bestMatch != null) {
                  final handleResultName = (bestMatch['name'] ?? bestMatch['description']?.toString().split(',').first ?? '') as String;
                  
                  if (handleResultName.isNotEmpty) {
                    print('✅ HANDLE LOOKUP: Using business: "$handleResultName"');
                    placeResult = bestMatch;
                    gotGoodResult = true;
                  }
                }
              }
            }
          } catch (e) {
            print('⚠️ HANDLE LOOKUP: Error during lookup: $e');
          }
        }
        
        // Attempt 5: Context-based lookup - when we have a context hint or generic attraction type
        // This helps find specific places like "Toy Story restaurant at Hollywood Studios" → "Roundup Rodeo BBQ"
        final hasContextHint = locationInfo.contextHint != null && locationInfo.contextHint!.isNotEmpty;
        final isGenericAttraction = typeLower == 'attraction' || typeLower == 'theme_park' || 
                                    typeLower == 'amusement_park' || typeLower == 'tourist_attraction';
        
        // Check if the name suggests a more specific place type (e.g., "restaurant at X", "cafe at X")
        final nameLower = locationInfo.name.toLowerCase();
        final nameContainsPlaceType = nameLower.contains('restaurant') || nameLower.contains('cafe') ||
                                       nameLower.contains('coffee') || nameLower.contains('bar') ||
                                       nameLower.contains('food') || nameLower.contains('themed');
        
        if (hasContextHint || (isGenericAttraction && nameContainsPlaceType)) {
          try {
            // Use context hint if available, otherwise construct from name
            final contextQuery = hasContextHint 
                ? locationInfo.contextHint!
                : '${locationInfo.name} ${effectiveRegionContext ?? ""}';
            
            print('🔍 CONTEXT LOOKUP: Searching for specific place from context: "$contextQuery"');
            
            final specificPlaceName = await _gemini.lookupPlaceByContext(
              contextQuery,
              regionContext: effectiveRegionContext,
            );
            
            if (specificPlaceName != null && specificPlaceName.isNotEmpty) {
              print('✅ CONTEXT LOOKUP: Found "$specificPlaceName"');
              
              // Search Places API for the specific place
              // Only add region context if not already in the place name
              String contextSearchQuery = specificPlaceName;
              if (effectiveRegionContext != null && effectiveRegionContext.isNotEmpty) {
                final nameLower = specificPlaceName.toLowerCase();
                final contextLower = effectiveRegionContext.toLowerCase();
                if (!nameLower.contains(contextLower)) {
                  contextSearchQuery += ', $effectiveRegionContext';
                }
              }
              
              print('🔍 CONTEXT LOOKUP: Searching Places API for: $contextSearchQuery');
              final contextResults = await _maps.searchPlaces(
                contextSearchQuery,
                latitude: userLocation?.latitude,
                longitude: userLocation?.longitude,
              );
              
              if (contextResults.isNotEmpty) {
                print('🔍 CONTEXT LOOKUP: Got ${contextResults.length} result(s) from Places API');
                
                // Find the best matching result
                final specificNormalized = _normalizeCompact(specificPlaceName);
                Map<String, dynamic>? bestMatch;
                
                for (final result in contextResults) {
                  final resultName = (result['name'] ?? result['description']?.toString().split(',').first ?? '') as String;
                  final resultNormalized = _normalizeCompact(resultName);
                  
                  print('🔍 CONTEXT LOOKUP: Checking result: "$resultName"');
                  
                  if (specificNormalized.isNotEmpty && resultNormalized.isNotEmpty &&
                      (resultNormalized.contains(specificNormalized) || specificNormalized.contains(resultNormalized))) {
                    print('✅ CONTEXT LOOKUP: Direct match found: "$resultName"');
                    bestMatch = result;
                    break;
                  }
                }
                
                // If no direct match, use scoring with context
                bestMatch ??= _selectBestPlaceResultWithContext(
                  contextResults,
                  specificPlaceName,
                  geminiType: 'restaurant',
                  city: locationInfo.city,
                  regionContext: effectiveRegionContext,
                  groundedAddress: locationInfo.address,
                );
                
                if (bestMatch != null) {
                  final contextResultName = (bestMatch['name'] ?? bestMatch['description']?.toString().split(',').first ?? '') as String;
                  
                  if (contextResultName.isNotEmpty) {
                    print('✅ CONTEXT LOOKUP: Using place: "$contextResultName"');
                    placeResult = bestMatch;
                    gotGoodResult = true;
                  }
                }
              }
            }
          } catch (e) {
            print('⚠️ CONTEXT LOOKUP: Error during lookup: $e');
          }
        }
        
        // Attempt 6: If still no results and we have type info, try name + type (+ region context)
        if (placeResult == null && locationInfo.type != null) {
          String queryWithType = '${locationInfo.name} ${locationInfo.type}';
          // Only add region context if not already in name
          if (effectiveRegionContext != null && effectiveRegionContext.isNotEmpty) {
            final nameLower = locationInfo.name.toLowerCase();
            final contextLower = effectiveRegionContext.toLowerCase();
            if (!nameLower.contains(contextLower)) {
              queryWithType = '${locationInfo.name} ${locationInfo.type}, $effectiveRegionContext';
            }
          }
          print('📷 IMAGE EXTRACTION: Retrying with type: $queryWithType');
          final resultsWithType = await _maps.searchPlaces(
            queryWithType,
            latitude: userLocation?.latitude,
            longitude: userLocation?.longitude,
          );
          placeResult = _selectBestPlaceResultWithContext(
            resultsWithType,
            locationInfo.name,
            geminiType: locationInfo.type,
            city: locationInfo.city,
            regionContext: effectiveRegionContext,
            groundedAddress: locationInfo.address,
          );
        }
        
        // CRITICAL: Skip locations from social media handles that couldn't be resolved
        // If the name came from an @handle and we didn't find a good match, skip it entirely
        // This prevents "@followmeawaytravel" → random unrelated businesses like "Miracle-Ear"
        if (hasOriginalHandle && !gotGoodResult && placeResult != null) {
          final resultName = (placeResult['name'] ?? placeResult['description']?.toString().split(',').first ?? '') as String;
          print('⚠️ IMAGE EXTRACTION: Skipping handle-derived location "$resultName" - handle "@${locationInfo.originalHandle}" could not be resolved to a real business');
          continue; // Skip this location entirely
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
              final placeDetails = await _maps.getPlaceDetails(placeId, includePhotoUrl: false);
              if (placeDetails.latitude != 0.0 || placeDetails.longitude != 0.0) {
                coordinates = LatLng(placeDetails.latitude, placeDetails.longitude);
                address = placeDetails.address ?? address;
                website = placeDetails.website;
                // Use the business name from place details if we had just an address
                final businessName = placeDetails.displayName ?? placeDetails.getPlaceName();
                if (isJustAddress && businessName.isNotEmpty) {
                  name = businessName;
                  print('📷 IMAGE EXTRACTION: Found business name from place details: $name');
                } else if (name.isEmpty) {
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
              final placeDetails = await _maps.getPlaceDetails(placeId, includePhotoUrl: false);
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
          
          // === AI RERANKING: Apply when initial match quality is questionable ===
          // Even after all retry attempts, the match quality might be uncertain
          final allCandidates = [...placeResults];
          final selectedIndex = allCandidates.indexOf(placeResult);
          
          // Build surrounding context for AI reranking
          final contextForRerank = [
            if (locationInfo.city != null) 'City: ${locationInfo.city}',
            if (effectiveRegionContext != null) 'Region: $effectiveRegionContext',
            if (locationInfo.originalHandle != null) 'Handle: @${locationInfo.originalHandle}',
          ].join(', ');
          
          final rerankResult = await _maybeAIRerank(
            originalName: locationInfo.name,
            candidates: allCandidates,
            selectedIndex: selectedIndex >= 0 ? selectedIndex : 0,
            geminiType: locationInfo.type,
            regionContext: effectiveRegionContext,
            surroundingText: contextForRerank.isNotEmpty ? contextForRerank : null,
            userLocation: userLocation,
            usedBroaderSearch: !gotGoodResult, // Signal uncertainty if no good result was found
          );
          
          // Update result based on AI reranking
          var finalPlaceResult = placeResult;
          var finalConfidence = 0.85;
          var needsConfirmation = false;
          
          if (rerankResult.usedAIRerank && rerankResult.selectedResult != null) {
            finalPlaceResult = rerankResult.selectedResult!;
            finalConfidence = rerankResult.confidence;
            needsConfirmation = rerankResult.needsConfirmation;
            
            // If AI selected a different result, update details
            if (finalPlaceResult != placeResult) {
              final newPlaceId = (finalPlaceResult['placeId'] ?? finalPlaceResult['place_id']) as String?;
              if (newPlaceId != null && newPlaceId.isNotEmpty) {
                print('🤖 IMAGE EXTRACTION: AI reranking selected different result, updating details');
                try {
                  final newPlaceDetails = await _maps.getPlaceDetails(newPlaceId);
                  if (newPlaceDetails.latitude != 0.0 || newPlaceDetails.longitude != 0.0) {
                    coordinates = LatLng(newPlaceDetails.latitude, newPlaceDetails.longitude);
                    address = newPlaceDetails.address ?? address;
                    website = newPlaceDetails.website ?? website;
                    name = newPlaceDetails.displayName ?? finalPlaceResult['name'] as String? ?? name;
                    print('✅ IMAGE EXTRACTION: AI-reranked result: "$name"');
                  }
                } catch (e) {
                  print('⚠️ IMAGE EXTRACTION: Error fetching AI-reranked place details: $e');
                }
              }
            }
            print('🤖 IMAGE EXTRACTION: AI reranking result - confidence: ${(finalConfidence * 100).toInt()}%');
          }
          
          // Store original query only if it's different from the resolved name
          final originalQueryText = locationInfo.name != name ? locationInfo.name : null;
          
          final extractedData = ExtractedLocationData(
            placeId: placeId,
            name: name,
            address: address,
            coordinates: coordinates,
            type: _inferPlaceTypeFromResult(finalPlaceResult, locationInfo.type),
            source: ExtractionSource.placesSearch,
            confidence: coordinates != null ? finalConfidence : finalConfidence * 0.7,
            placeTypes: (finalPlaceResult['types'] as List?)?.cast<String>(),
            website: website,
            needsConfirmation: needsConfirmation,
            originalQuery: originalQueryText,
          );
          
          if (!_isDuplicate(extractedData, results)) {
            results.add(extractedData);
            final rerankType = rerankResult.usedAIRerank ? ' (AI reranked)' : '';
            print('✅ IMAGE EXTRACTION: Added "${extractedData.name}"$rerankType');
          }
        }
      }

      print('📷 IMAGE EXTRACTION: Extracted ${results.length} location(s)');
      return (locations: results, regionContext: regionContext, extractedText: extractedText);
    } catch (e) {
      print('❌ IMAGE EXTRACTION ERROR: $e');
      return (locations: <ExtractedLocationData>[], regionContext: regionContextHint, extractedText: null);
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
  /// 4. Boosting results that match geographic hints (country/city from caption)
  Map<String, dynamic>? _selectBestPlaceResult(
    List<Map<String, dynamic>> results,
    String originalName, {
    String? geminiType,
    GeographicHints? geographicHints,
    String? groundedAddress,
  }) {
    if (results.isEmpty) return null;
    // IMPORTANT: Don't skip scoring for single results!
    // Even with 1 result, we need to validate it matches the search type.
    // e.g., searching for "Lake Crescent" (Lake type) should NOT accept "Lake Crescent Road"
    
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
    // Use contains() for compound types like "scenic viewpoint", "mountain/hiking trail"
    final geminiTypeLower = geminiType?.toLowerCase() ?? '';
    final isNatureSearch = geminiTypeLower == 'park' || 
                          geminiTypeLower == 'landmark' ||
                          geminiTypeLower == 'trail' ||
                          geminiTypeLower == 'beach' ||
                          geminiTypeLower == 'natural_feature' ||
                          geminiTypeLower == 'lake' ||
                          geminiTypeLower == 'waterfall' ||
                          geminiTypeLower == 'mountain' ||
                          geminiTypeLower == 'rainforest' ||
                          geminiTypeLower == 'viewpoint' ||
                          geminiTypeLower.contains('viewpoint') ||  // "scenic viewpoint"
                          geminiTypeLower.contains('trail') ||      // "hiking trail"
                          geminiTypeLower.contains('beach') ||      // "scenic beach"
                          geminiTypeLower.contains('waterfall') ||
                          geminiTypeLower.contains('lake') ||
                          geminiTypeLower.contains('mountain');
    // "region" is handled separately since it could be a geographic region (mountain range, valley)
    // OR an administrative region (state, county)
    final isRegionSearch = geminiTypeLower == 'region';
    // City/Town search - when user is searching for a locality, not a specific POI
    // IMPORTANT: Handle compound types like "City with Attractions, Parks..."
    final isCitySearch = geminiTypeLower == 'city' || 
                        geminiTypeLower == 'town' ||  // Added 'town' for places like "Forks"
                        geminiTypeLower == 'locality' ||
                        geminiTypeLower == 'neighborhood' ||
                        geminiTypeLower.startsWith('city ') ||    // "City with Attractions..."
                        geminiTypeLower.startsWith('town ') ||    // "Town with..."
                        RegExp(r'^city\b').hasMatch(geminiTypeLower);  // "city" as first word
    // Check if Gemini identified this as a restaurant/food establishment
    final isRestaurantSearch = geminiTypeLower == 'restaurant' ||
                               geminiTypeLower == 'cafe' ||
                               geminiTypeLower == 'bar' ||
                               geminiTypeLower == 'food' ||
                               geminiTypeLower == 'bakery' ||
                               geminiTypeLower == 'coffee_shop';
    // Check if Gemini identified this as a hotel/lodging
    final isHotelSearch = geminiTypeLower == 'hotel' ||
                          geminiTypeLower == 'lodging' ||
                          geminiTypeLower == 'resort' ||
                          geminiTypeLower == 'inn' ||
                          geminiTypeLower == 'motel';
    
    // Types that are NOT restaurants (should be heavily penalized in restaurant searches)
    const nonRestaurantTypes = [
      'route',           // Streets, drives, roads
      'geocode',         // Generic geocoding result
      'locality',        // Cities/towns
      'sublocality',
      'neighborhood',
      'political',
      'administrative_area_level_1',
      'administrative_area_level_2',
      'park',            // Parks when searching for restaurants
      'natural_feature',
      'airport',
      'transit_station',
    ];
    
    // Types that indicate food establishments
    const foodTypes = [
      'restaurant',
      'food',
      'cafe',
      'bar',
      'bakery',
      'meal_takeaway',
      'meal_delivery',
      'night_club',
      'coffee_shop',
    ];
    
    // Types that indicate hotel/lodging establishments
    const hotelTypes = [
      'hotel',
      'lodging',
      'resort',
      'motel',
      'inn',
      'bed_and_breakfast',
      'guest_house',
      'hostel',
    ];
    
    // Types that are NOT hotels (should be penalized in hotel searches)
    // This prevents "Von Trapp Lodge Gift Shop" from beating "von Trapp Family Lodge & Resort"
    const nonHotelTypes = [
      'store',
      'gift_shop',
      'shopping_mall',
      'restaurant',      // Dining rooms inside hotels shouldn't beat the hotel itself
      'food',
      'cafe',
      'bar',
      'veterinary_care', // "VON TRAPP ANIMAL LODGE"
      'health',
      'doctor',
      'sports_complex',
      'sports_activity_location',
    ];
    
    // Types that are NOT natural features (should be heavily penalized in nature searches)
    // This prevents "Lake Crescent Road" from beating "Lake Crescent" (the actual lake)
    const nonNatureTypes = [
      'route',           // Roads, streets, highways
      'geocode',         // Generic geocoding result
      'street_address',  // Street addresses
      'intersection',    // Road intersections
      'premise',         // Buildings, offices
      'subpremise',      // Floors, suites
      'hotel',           // Hotels (e.g., "Super 8 by Wyndham Port Angeles")
      'lodging',
      'motel',
      'store',
      'gift_shop',
      'restaurant',
    ];
    
    // Types that are NOT cities/towns (should be penalized when searching for localities)
    // This prevents "Forks Motel" from beating "Forks" (the actual town)
    const nonCityTypes = [
      'establishment',   // Businesses, POIs
      'point_of_interest',
      'lodging',
      'hotel',
      'motel',
      'restaurant',
      'store',
      'food',
      'route',           // Roads
      'street_address',
      'park',            // Parks are not cities
      'tourist_attraction', // Attractions are not cities
    ];
    
    if (isNatureSearch && bestScore == -1) {
      print('📷 IMAGE EXTRACTION: Nature/landmark search mode (geminiType: $geminiType)');
    } else if (isRegionSearch && bestScore == -1) {
      print('📷 IMAGE EXTRACTION: Region search mode (geminiType: $geminiType) - accepts localities AND natural features');
    } else if (isCitySearch && bestScore == -1) {
      print('📷 IMAGE EXTRACTION: City/locality search mode (geminiType: $geminiType)');
    } else if (isRestaurantSearch && bestScore == -1) {
      print('📷 IMAGE EXTRACTION: Restaurant/food search mode (geminiType: $geminiType)');
    } else if (isHotelSearch && bestScore == -1) {
      print('📷 IMAGE EXTRACTION: Hotel/lodging search mode (geminiType: $geminiType)');
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
      
      // === GROUNDED ADDRESS MATCHING ===
      // When we have a specific address from the source (like "189 The Grove Dr"),
      // boost candidates whose name or address contains that location name
      if (groundedAddress != null && groundedAddress.isNotEmpty) {
        final resultAddress = (result['formatted_address'] ?? result['address'] ?? result['description'] ?? '') as String;
        
        // Check address similarity
        final addressSimilarity = _calculateAddressSimilarity(groundedAddress, resultAddress);
        if (addressSimilarity >= 0.8) {
          score += 150;
          print('📷 IMAGE EXTRACTION:   → Grounded address match: +150 (similarity: ${(addressSimilarity * 100).toInt()}%)');
        } else if (addressSimilarity >= 0.6) {
          score += 100;
          print('📷 IMAGE EXTRACTION:   → Grounded address partial match: +100 (similarity: ${(addressSimilarity * 100).toInt()}%)');
        } else if (addressSimilarity >= 0.4) {
          score += 50;
          print('📷 IMAGE EXTRACTION:   → Grounded address weak match: +50 (similarity: ${(addressSimilarity * 100).toInt()}%)');
        }
        
        // Also check if candidate name/address contains location name from grounded address
        // e.g., "American Beauty - The Grove" should get bonus when address is "189 The Grove Dr"
        final locationNameFromAddress = _extractLocationNameFromAddress(groundedAddress);
        if (locationNameFromAddress != null) {
          final normalizedLocation = locationNameFromAddress.toLowerCase();
          final normalizedCandidateName = resultName.toLowerCase();
          final normalizedCandidateAddress = resultAddress.toLowerCase();
          
          if (normalizedCandidateName.contains(normalizedLocation)) {
            score += 120;
            print('📷 IMAGE EXTRACTION:   → Location name in candidate: +120 ("$locationNameFromAddress" in name)');
          } else if (normalizedCandidateAddress.contains(normalizedLocation)) {
            score += 60;
            print('📷 IMAGE EXTRACTION:   → Location name in candidate address: +60 ("$locationNameFromAddress" in address)');
          }
        }
      }
      
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
      if (isRegionSearch) {
        // When searching for a region, accept BOTH localities AND natural features
        // "White Mountains" is a natural feature, "New Hampshire" is a locality
        bool foundMatch = false;
        for (final type in types) {
          if (localityTypes.contains(type)) {
            score += 40;
            foundMatch = true;
            break;
          }
        }
        if (!foundMatch) {
          for (final type in types) {
            if (naturalFeatureTypes.contains(type)) {
              score += 35; // Slightly lower than locality but still valid for regions
              break;
            }
          }
        }
      } else if (isCitySearch) {
        // CRITICAL: When searching for a city/town, STRONGLY prefer localities
        // This prevents "Forks Motel" from beating "Forks" (the actual town)
        // and "City of Port Townsend Parks Dept" from beating "Port Townsend" (the city)
        final isLocality = types.any((t) => localityTypes.contains(t));
        final isNonCity = types.any((t) => nonCityTypes.contains(t));
        
        if (isLocality) {
          score += 80; // Strong boost for actual localities/cities - must beat name-match bonuses
          print('📷 IMAGE EXTRACTION:   → Locality type match bonus: +80');
        }
        
        // HEAVILY penalize non-localities when searching for a city
        // "Forks Motel" should NOT beat "Forks" just because it has "Forks" in the name
        if (isNonCity && !isLocality) {
          score -= 60; // Heavy penalty for hotels, restaurants, POIs when searching for cities
          print('📷 IMAGE EXTRACTION:   → Non-city penalty: -60');
        }
      } else if (isNatureSearch) {
        // CRITICAL: When searching for nature (lakes, parks, trails, beaches), prefer natural features
        // This prevents "Lake Crescent Road" from beating "Lake Crescent" (the actual lake)
        final isNature = types.any((t) => naturalFeatureTypes.contains(t));
        final isNonNature = types.any((t) => nonNatureTypes.contains(t));
        final isVisitorEstablishment = types.any((t) => visitorEstablishmentTypes.contains(t));
        
        if (isNature) {
          score += 50; // Strong boost for natural features
          print('📷 IMAGE EXTRACTION:   → Nature type match bonus: +50');
        }
        
        // HEAVILY penalize roads/routes when searching for natural features
        // "Lake Crescent Road" should NOT beat "Lake Crescent" (the lake)
        if (isNonNature && !isNature) {
          score -= 70; // Heavy penalty for roads, hotels, etc.
          print('📷 IMAGE EXTRACTION:   → Non-nature penalty: -70');
        }
        
        // Penalize visitor centers/agencies when searching for nature
        if (isVisitorEstablishment) {
          score -= 25; // Penalize visitor centers
          print('📷 IMAGE EXTRACTION:   → Visitor establishment penalty: -25');
        }
      } else if (isRestaurantSearch) {
        // CRITICAL: When searching for a restaurant, heavily penalize non-establishments
        // This prevents "Rockcreek Drive" (a street) from beating "RockCreek Seafood" (restaurant)
        final isNonRestaurant = types.any((t) => nonRestaurantTypes.contains(t));
        final isFood = types.any((t) => foodTypes.contains(t));
        final isEstablishment = types.any((t) => t == 'establishment' || t == 'point_of_interest');
        
        if (isFood) {
          score += 60; // Strong boost for food establishments
          print('📷 IMAGE EXTRACTION:   → Restaurant type match bonus: +60');
        } else if (isEstablishment && !isNonRestaurant) {
          score += 30; // Moderate boost for other establishments
          print('📷 IMAGE EXTRACTION:   → Establishment bonus: +30');
        }
        
        if (isNonRestaurant && !isEstablishment) {
          score -= 80; // Heavy penalty for routes, localities, geocodes
          print('📷 IMAGE EXTRACTION:   → Non-restaurant penalty: -80');
        } else if (isNonRestaurant) {
          score -= 40; // Moderate penalty if it's also an establishment but wrong type
          print('📷 IMAGE EXTRACTION:   → Wrong type penalty: -40');
        }
      } else if (isHotelSearch) {
        // CRITICAL: When searching for a hotel, boost lodging and penalize non-lodging
        // This prevents "Von Trapp Lodge Gift Shop" from beating "von Trapp Family Lodge & Resort"
        final isHotel = types.any((t) => hotelTypes.contains(t));
        final isNonHotel = types.any((t) => nonHotelTypes.contains(t));
        final isEstablishment = types.any((t) => t == 'establishment' || t == 'point_of_interest');
        
        if (isHotel) {
          score += 60; // Strong boost for hotel/lodging establishments
          print('📷 IMAGE EXTRACTION:   → Hotel type match bonus: +60');
        } else if (isEstablishment && !isNonHotel) {
          score += 20; // Small boost for other establishments
          print('📷 IMAGE EXTRACTION:   → Establishment bonus: +20');
        }
        
        if (isNonHotel) {
          score -= 50; // Penalty for gift shops, restaurants, etc. inside hotel complexes
          print('📷 IMAGE EXTRACTION:   → Non-hotel penalty: -50');
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
      
      // === GEOGRAPHIC HINTS SCORING ===
      // When we have geographic hints from the caption (countries/cities),
      // boost results that match those hints. This helps disambiguate
      // locations with the same name in different countries.
      // e.g., "Jurassic World: The Experience" exists in London, Bangkok, Madrid
      // If caption mentions #thailand, boost the Bangkok location.
      if (geographicHints != null && geographicHints.isNotEmpty) {
        final resultDescription = (result['description'] ?? result['formatted_address'] ?? '') as String;
        final lowerDescription = resultDescription.toLowerCase();
        
        // Country matching - check if result address contains a hinted country
        for (final country in geographicHints.countries) {
          final countryLower = country.toLowerCase();
          
          // Check for country name in address
          if (lowerDescription.contains(countryLower)) {
            score += 60; // Strong bonus for matching country
            print('🌍 GEO SCORING: +60 country match ("$country" found in address)');
            break;
          }
          
          // Check for country-specific city names that indicate the country
          // e.g., "Bangkok" in address indicates Thailand
          final countryIndicators = _getCountryIndicators(country);
          for (final indicator in countryIndicators) {
            if (lowerDescription.contains(indicator)) {
              score += 60;
              print('🌍 GEO SCORING: +60 country indicator match ("$indicator" → $country)');
              break;
            }
          }
        }
        
        // City matching - check if result address contains a hinted city
        // Also penalize results that DON'T match when we have a city hint
        bool foundCityMatch = false;
        for (final city in geographicHints.cities) {
          if (lowerDescription.contains(city)) {
            score += 80; // Strong bonus for matching city - should overcome name match differences
            print('🌍 GEO SCORING: +80 city match ("$city" found in address)');
            foundCityMatch = true;
            break;
          }
        }
        
        // Penalize results that don't match ANY hinted city when city hints are provided
        // This helps disambiguate same-name places in different cities
        // e.g., "Mokkoji Shabu Shabu Bar" in Orange vs San Diego
        if (!foundCityMatch && geographicHints.cities.isNotEmpty && lowerDescription.isNotEmpty) {
          // Check if this result is in a DIFFERENT city than what we're looking for
          // Common US city patterns in addresses
          final commonCities = ['orange', 'costa mesa', 'irvine', 'tustin', 'anaheim', 
                               'garden grove', 'santa ana', 'huntington beach', 'newport beach',
                               'los angeles', 'san diego', 'san francisco', 'seattle'];
          for (final otherCity in commonCities) {
            if (lowerDescription.contains(otherCity) && 
                !geographicHints.cities.any((hintedCity) => otherCity.contains(hintedCity) || hintedCity.contains(otherCity))) {
              score -= 50; // Penalty for being in a different city
              print('🌍 GEO SCORING: -50 wrong city penalty ("$otherCity" in address, wanted: ${geographicHints.cities})');
              break;
            }
          }
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
  
  /// Helper to get city/region indicators for a country
  /// Used to detect country from city names in addresses
  List<String> _getCountryIndicators(String country) {
    const indicators = <String, List<String>>{
      'Thailand': ['bangkok', 'phuket', 'chiang mai', 'pattaya', 'krabi', 'thailand'],
      'Japan': ['tokyo', 'osaka', 'kyoto', 'japan', 'jp'],
      'South Korea': ['seoul', 'busan', 'korea', 'kr'],
      'China': ['beijing', 'shanghai', 'china', 'cn'],
      'United Kingdom': ['london', 'uk', 'united kingdom', 'england', 'gb'],
      'France': ['paris', 'france', 'fr'],
      'Germany': ['berlin', 'munich', 'germany', 'de'],
      'Italy': ['rome', 'milan', 'italy', 'it'],
      'Spain': ['madrid', 'barcelona', 'spain', 'es'],
      'Australia': ['sydney', 'melbourne', 'australia', 'au'],
      'Singapore': ['singapore', 'sg'],
      'Malaysia': ['kuala lumpur', 'malaysia', 'my'],
      'Indonesia': ['bali', 'jakarta', 'indonesia', 'id'],
      'Vietnam': ['hanoi', 'ho chi minh', 'vietnam', 'vn'],
      'Philippines': ['manila', 'philippines', 'ph'],
      'India': ['mumbai', 'delhi', 'india', 'in'],
      'United Arab Emirates': ['dubai', 'abu dhabi', 'uae'],
      'Mexico': ['mexico city', 'cancun', 'mexico', 'mx'],
      'Canada': ['toronto', 'vancouver', 'canada', 'ca'],
      'Brazil': ['rio', 'sao paulo', 'brazil', 'br'],
    };
    return indicators[country] ?? [country.toLowerCase()];
  }
  
  /// Extended version of _selectBestPlaceResult that uses additional context
  /// (city, region) to better filter/score candidates from broader searches.
  /// 
  /// This is used in the "broader first, then filter" strategy where we:
  /// 1. Search broadly (name + type + state/country)
  /// 2. Use specific details (city, full region) to score/filter candidates
  /// US state name to abbreviation mapping (and common variants)
  static const Map<String, List<String>> _stateNameVariants = {
    'alabama': ['al', 'ala'],
    'alaska': ['ak'],
    'arizona': ['az', 'ariz'],
    'arkansas': ['ar', 'ark'],
    'california': ['ca', 'calif', 'cal'],
    'colorado': ['co', 'colo'],
    'connecticut': ['ct', 'conn'],
    'delaware': ['de', 'del'],
    'florida': ['fl', 'fla'],
    'georgia': ['ga'],
    'hawaii': ['hi'],
    'idaho': ['id'],
    'illinois': ['il', 'ill'],
    'indiana': ['in', 'ind'],
    'iowa': ['ia'],
    'kansas': ['ks', 'kan', 'kans'],
    'kentucky': ['ky', 'ken', 'kent'],
    'louisiana': ['la'],
    'maine': ['me'],
    'maryland': ['md'],
    'massachusetts': ['ma', 'mass'],
    'michigan': ['mi', 'mich'],
    'minnesota': ['mn', 'minn'],
    'mississippi': ['ms', 'miss'],
    'missouri': ['mo'],
    'montana': ['mt', 'mont'],
    'nebraska': ['ne', 'neb', 'nebr'],
    'nevada': ['nv', 'nev'],
    'new hampshire': ['nh'],
    'new jersey': ['nj'],
    'new mexico': ['nm'],
    'new york': ['ny'],
    'north carolina': ['nc'],
    'north dakota': ['nd'],
    'ohio': ['oh'],
    'oklahoma': ['ok', 'okla'],
    'oregon': ['or', 'ore', 'oreg'],
    'pennsylvania': ['pa', 'penn', 'penna'],
    'rhode island': ['ri'],
    'south carolina': ['sc'],
    'south dakota': ['sd'],
    'tennessee': ['tn', 'tenn'],
    'texas': ['tx', 'tex'],
    'utah': ['ut'],
    'vermont': ['vt'],
    'virginia': ['va'],
    'washington': ['wa', 'wash'],
    'west virginia': ['wv'],
    'wisconsin': ['wi', 'wis', 'wisc'],
    'wyoming': ['wy', 'wyo'],
    // Territories
    'district of columbia': ['dc'],
    'puerto rico': ['pr'],
    'guam': ['gu'],
    'virgin islands': ['vi'],
  };
  
  /// Check if a description contains a state/region match (handles abbreviations)
  bool _descriptionContainsRegion(String normalizedDescription, String regionPart) {
    // Direct match first
    if (normalizedDescription.contains(regionPart)) {
      return true;
    }
    
    // Check if regionPart is a state name or abbreviation
    final cleanedPart = regionPart.replaceAll(RegExp(r'\s*(state|st\.?)$'), '').trim();
    
    // If it's a full state name, check for abbreviation matches
    if (_stateNameVariants.containsKey(cleanedPart)) {
      final variants = _stateNameVariants[cleanedPart]!;
      for (final variant in variants) {
        // Match abbreviation with word boundary (e.g., ", WA," or ", WA " or ending with ", WA")
        final pattern = RegExp('(,\\s*|\\s)$variant(,|\\s|\$)', caseSensitive: false);
        if (pattern.hasMatch(normalizedDescription)) {
          return true;
        }
      }
    }
    
    // If it's an abbreviation, check for full state name matches
    for (final entry in _stateNameVariants.entries) {
      if (entry.value.contains(cleanedPart)) {
        // Found abbreviation, check if description contains full name
        if (normalizedDescription.contains(entry.key)) {
          return true;
        }
      }
    }
    
    return false;
  }
  
  Map<String, dynamic>? _selectBestPlaceResultWithContext(
    List<Map<String, dynamic>> results,
    String originalName, {
    String? geminiType,
    String? city,
    String? regionContext,
    String? groundedAddress,
  }) {
    if (results.isEmpty) return null;
    
    // First, use the base scoring to get initial scores
    // We'll enhance this with context-based scoring
    
    final normalizedCity = city?.toLowerCase().trim();
    final normalizedRegion = regionContext?.toLowerCase().trim();
    
    // Extract location components from region context
    // e.g., "Neah Bay, Washington State, USA" → ["neah bay", "washington state", "usa"]
    final regionParts = normalizedRegion?.split(',').map((p) => p.trim()).toList() ?? [];
    
    Map<String, dynamic>? bestResult;
    int bestScore = -999;
    
    for (final result in results) {
      // Get base score from _selectBestPlaceResult logic (includes grounded address matching)
      final baseScore = _getPlaceScore(result, originalName, geminiType: geminiType, groundedAddress: groundedAddress);
      int contextScore = 0;
      
      // Get the result's address/description for context matching
      final resultDescription = (result['description'] ?? result['formatted_address'] ?? '') as String;
      final normalizedDescription = resultDescription.toLowerCase();
      
      // === CONTEXT-BASED SCORING ===
      
      // Bonus for matching city
      if (normalizedCity != null && normalizedCity.isNotEmpty) {
        if (normalizedDescription.contains(normalizedCity)) {
          contextScore += 30;
          print('📷 IMAGE EXTRACTION:   → City match bonus: +30 (found "$city" in address)');
        }
      }
      
      // Bonus for matching region parts (with state abbreviation support)
      for (final part in regionParts) {
        if (part.isNotEmpty && _descriptionContainsRegion(normalizedDescription, part)) {
          // Give higher bonus for state-level matches (more specific than country)
          final cleanedPart = part.replaceAll(RegExp(r'\s*(state|st\.?)$'), '').trim();
          final isStateName = _stateNameVariants.containsKey(cleanedPart) ||
              _stateNameVariants.values.any((variants) => variants.contains(cleanedPart));
          
          if (isStateName) {
            contextScore += 40;
            print('📷 IMAGE EXTRACTION:   → State match bonus: +40 (found "$part" in address)');
          } else {
            contextScore += 15;
            print('📷 IMAGE EXTRACTION:   → Region match bonus: +15 (found "$part" in address)');
          }
        }
      }
      
      final totalScore = baseScore + contextScore;
      final resultName = (result['name'] ?? result['description']?.toString().split(',').first ?? '') as String;
      print('📷 IMAGE EXTRACTION: Context scoring "$resultName" = $totalScore (base: $baseScore, context: $contextScore)');
      
      if (totalScore > bestScore) {
        bestScore = totalScore;
        bestResult = result;
      }
    }
    
    if (bestResult != null) {
      final selectedName = (bestResult['name'] ?? bestResult['description']?.toString().split(',').first ?? '') as String;
      print('📷 IMAGE EXTRACTION: Selected best result with context: "$selectedName" (score: $bestScore)');
    }
    
    return bestResult ?? results.first;
  }
  
  /// Get the base score for a place result (used by _selectBestPlaceResultWithContext)
  /// This is a simplified scoring version that returns the score instead of tracking best result
  int _getPlaceScore(Map<String, dynamic> result, String originalName, {String? geminiType, String? groundedAddress}) {
    int score = 0;
    
    final resultName = (result['name'] ?? result['description']?.toString().split(',').first ?? '') as String;
    final normalizedOriginal = _normalizeForComparison(originalName);
    final normalizedResultName = _normalizeForComparison(resultName);
    final compactOriginal = _normalizeCompact(originalName);
    final compactResultName = _normalizeCompact(resultName);
    final types = (result['types'] as List?)?.cast<String>() ?? [];

    // === GROUNDED ADDRESS MATCHING (HIGHEST priority) ===
    // If we have a grounded address from the source content (e.g., "7924 Melrose Ave, Los Angeles, CA"),
    // this is the MOST reliable signal and should override name matching.
    // A location with same name but different address should NOT beat the correct address.
    if (groundedAddress != null && groundedAddress.isNotEmpty) {
      final resultAddress = (result['formatted_address'] ?? result['address'] ?? result['description'] ?? '') as String;
      if (resultAddress.isNotEmpty) {
        final addressSimilarity = _calculateAddressSimilarity(groundedAddress, resultAddress);
        if (addressSimilarity >= 0.8) {
          // Strong match - this should be definitive
          score += 250;
          print('📷 IMAGE EXTRACTION:   → Grounded address match bonus: +250 (similarity: ${(addressSimilarity * 100).toInt()}%)');
        } else if (addressSimilarity >= 0.6) {
          // Partial match - still significant
          score += 150;
          print('📷 IMAGE EXTRACTION:   → Grounded address partial match: +150 (similarity: ${(addressSimilarity * 100).toInt()}%)');
        } else if (addressSimilarity >= 0.4) {
          // Weak match - some bonus
          score += 75;
          print('📷 IMAGE EXTRACTION:   → Grounded address weak match: +75 (similarity: ${(addressSimilarity * 100).toInt()}%)');
        } else if (addressSimilarity < 0.2) {
          // Address mismatch penalty - this location is likely wrong
          score -= 100;
          print('📷 IMAGE EXTRACTION:   → Address mismatch PENALTY: -100 (similarity: ${(addressSimilarity * 100).toInt()}%)');
        }
      }
      
      // === LOCATION NAME IN ADDRESS MATCHING ===
      // When grounded address contains a distinctive location name (like "The Grove", "Century City"),
      // check if the candidate's name contains that location. This helps when the address
      // is at a well-known complex/mall and the business name includes the location.
      // e.g., "189 The Grove Dr" should boost "American Beauty - The Grove" over just "American Beauty"
      final locationNameFromAddress = _extractLocationNameFromAddress(groundedAddress);
      if (locationNameFromAddress != null) {
        final normalizedLocation = locationNameFromAddress.toLowerCase();
        final normalizedCandidateName = resultName.toLowerCase();
        final normalizedCandidateAddress = (result['formatted_address'] ?? result['description'] ?? '').toString().toLowerCase();
        
        if (normalizedCandidateName.contains(normalizedLocation)) {
          // Candidate name contains the location from grounded address - strong signal
          score += 120;
          print('📷 IMAGE EXTRACTION:   → Location name in candidate bonus: +120 ("$locationNameFromAddress" in name)');
        } else if (normalizedCandidateAddress.contains(normalizedLocation)) {
          // Candidate address contains the location - moderate signal
          score += 60;
          print('📷 IMAGE EXTRACTION:   → Location name in candidate address bonus: +60 ("$locationNameFromAddress" in address)');
        }
      }
    }
    
    // === NAME MATCHING ===

    // Calculate name similarity score to determine the "closest" match
    // This gives the EXACT bonus (+150) to the candidate with the highest similarity
    final similarityScore = _calculateNameSimilarity(originalName, resultName);
    if (similarityScore >= 0.9) {  // Very close match (90%+ similarity)
      score += 150;
      print('📷 IMAGE EXTRACTION:   → EXACT match bonus: +150 (similarity: ${(similarityScore * 100).toInt()}%)');
    } else if (similarityScore >= 0.8) {  // Close match (80-89% similarity)
      score += 120;
      print('📷 IMAGE EXTRACTION:   → Very close match bonus: +120 (similarity: ${(similarityScore * 100).toInt()}%)');
    } else if (similarityScore >= 0.7) {  // Moderate match (70-79% similarity)
      score += 100;
      print('📷 IMAGE EXTRACTION:   → Close match bonus: +100 (similarity: ${(similarityScore * 100).toInt()}%)');
    }

    // Additional bonuses for compact matching (these stack with similarity bonuses)
    if (compactResultName == compactOriginal) {
      score += 50; // Smaller bonus since similarity already accounts for this
      print('📷 IMAGE EXTRACTION:   → Exact compact match bonus: +50');
    } else if (compactResultName.contains(compactOriginal) || 
               compactOriginal.contains(compactResultName)) {
      final lengthDifference = (compactResultName.length - compactOriginal.length).abs();
      if (lengthDifference <= 5) {
        score += 30;
        print('📷 IMAGE EXTRACTION:   → Close compact match bonus: +30 (diff: $lengthDifference chars)');
      } else if (lengthDifference <= 15) {
        score += 20 - (lengthDifference ~/ 3);
        print('📷 IMAGE EXTRACTION:   → Medium compact match bonus: +${20 - (lengthDifference ~/ 3)} (diff: $lengthDifference chars)');
      } else {
        score += 10;
      }
    }
    
    // Word matching (additional bonus)
    final originalWordsList = normalizedOriginal.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
    int matchedWords = 0;
    for (final word in originalWordsList) {
      if (normalizedResultName.contains(word)) {
        matchedWords++;
      }
    }
    if (originalWordsList.isNotEmpty) {
      final matchRatio = matchedWords / originalWordsList.length;
      score += (matchRatio * 15).round();  // Reduced from 20 to avoid over-scoring
    }
    
    // === TYPE-BASED SCORING (simplified) ===
    final geminiTypeLower = geminiType?.toLowerCase() ?? '';
    
    const localityTypes = ['locality', 'sublocality', 'neighborhood', 'political', 'administrative_area_level_1', 'administrative_area_level_2'];
    const naturalFeatureTypes = ['natural_feature', 'park', 'national_park', 'state_park', 'campground', 'beach'];
    const foodTypes = ['restaurant', 'food', 'cafe', 'bar', 'bakery', 'meal_takeaway'];
    const hotelTypes = ['hotel', 'lodging', 'resort', 'motel', 'inn'];
    // Types that indicate businesses NEAR natural features, NOT the feature itself
    // e.g., "Lake Crescent Lodge Dining Room" is a restaurant near Lake Crescent, not the lake
    const nonNatureTypes = [
      'route', 'geocode', 'street_address',
      'hotel', 'lodging', 'resort', 'motel',  // Hotels/lodging near features
      'restaurant', 'food', 'cafe', 'bar', 'bakery', 'meal_takeaway',  // Food businesses
      'store', 'shopping_mall', 'clothing_store', 'convenience_store',  // Retail
    ];
    
    final isNatureSearch = geminiTypeLower.contains('park') || geminiTypeLower.contains('lake') || 
                          geminiTypeLower.contains('trail') || geminiTypeLower.contains('beach') ||
                          geminiTypeLower.contains('mountain') || geminiTypeLower.contains('viewpoint') ||
                          geminiTypeLower.contains('waterfall') || geminiTypeLower.contains('rainforest');
    final isCitySearch = geminiTypeLower == 'city' || geminiTypeLower == 'town' || geminiTypeLower == 'locality';
    final isRestaurantSearch = foodTypes.any((t) => geminiTypeLower.contains(t));
    final isHotelSearch = hotelTypes.any((t) => geminiTypeLower.contains(t));
    
    if (isCitySearch) {
      if (types.any((t) => localityTypes.contains(t))) {
        score += 80;
        print('📷 IMAGE EXTRACTION:   → Locality type match bonus: +80');
      }
      if (types.any((t) => ['establishment', 'lodging', 'hotel', 'restaurant'].contains(t))) {
        score -= 60;
        print('📷 IMAGE EXTRACTION:   → Non-city penalty: -60');
      }
    } else if (isNatureSearch) {
      if (types.any((t) => naturalFeatureTypes.contains(t))) {
        score += 50;
        print('📷 IMAGE EXTRACTION:   → Nature type match bonus: +50');
      }
      // HEAVY penalty for businesses when searching for natural features
      // "Lake Crescent Lodge Dining Room" (restaurant) should NOT match "Lake Crescent" (lake)
      if (types.any((t) => nonNatureTypes.contains(t))) {
        score -= 100;
        print('📷 IMAGE EXTRACTION:   → Non-nature penalty: -100');
      }
    } else if (isRestaurantSearch) {
      if (types.any((t) => foodTypes.contains(t))) {
        score += 60;
        print('📷 IMAGE EXTRACTION:   → Restaurant type match bonus: +60');
      }
      if (types.any((t) => ['route', 'geocode', 'locality'].contains(t))) {
        score -= 80;
        print('📷 IMAGE EXTRACTION:   → Non-restaurant penalty: -80');
      }
    } else if (isHotelSearch) {
      if (types.any((t) => hotelTypes.contains(t))) {
        score += 60;
        print('📷 IMAGE EXTRACTION:   → Hotel type match bonus: +60');
      }
      if (types.any((t) => ['store', 'gift_shop', 'restaurant'].contains(t))) {
        score -= 50;
        print('📷 IMAGE EXTRACTION:   → Non-hotel penalty: -50');
      }
    } else {
      // Default scoring
      if (types.any((t) => localityTypes.contains(t))) {
        score -= 30;
        print('📷 IMAGE EXTRACTION:   → Locality penalty: -30');
      }
      if (types.any((t) => t == 'establishment' || t == 'point_of_interest')) {
        score += 15;
        print('📷 IMAGE EXTRACTION:   → Establishment bonus: +15');
      }
    }
    
    return score;
  }
  
  /// Calculate similarity score between two place names (0.0 to 1.0)
  /// Used to determine which candidate is "closest" to the original search term
  double _calculateNameSimilarity(String original, String candidate) {
    if (original.isEmpty || candidate.isEmpty) return 0.0;

    // Normalize both strings
    final normOriginal = _normalizeForComparison(original);
    final normCandidate = _normalizeForComparison(candidate);

    // Exact match after normalization
    if (normOriginal == normCandidate) return 1.0;

    // Case-insensitive exact match (preserves punctuation)
    if (original.trim().toLowerCase() == candidate.trim().toLowerCase()) return 0.95;

    // Calculate Levenshtein distance for edit similarity
    final maxLength = math.max(normOriginal.length, normCandidate.length);
    if (maxLength == 0) return 1.0;

    final distance = _levenshteinDistance(normOriginal, normCandidate);
    final editSimilarity = 1.0 - (distance / maxLength);

    // Calculate longest common substring ratio
    final lcsLength = _longestCommonSubstring(normOriginal, normCandidate).length;
    final lcsRatio = lcsLength / math.max(normOriginal.length, normCandidate.length);

    // Word overlap similarity
    final originalWords = normOriginal.split(RegExp(r'\s+')).toSet();
    final candidateWords = normCandidate.split(RegExp(r'\s+')).toSet();
    final commonWords = originalWords.intersection(candidateWords).length;
    final maxWordCount = math.max<int>(originalWords.length, candidateWords.length);
    final wordOverlap = maxWordCount > 0 ? commonWords / maxWordCount : 0.0;

    // Weighted combination of factors
    final similarity = (editSimilarity * 0.4) + (lcsRatio * 0.4) + (wordOverlap * 0.2);

    return math.max(0.0, math.min(1.0, similarity));
  }

  /// Calculate Levenshtein distance between two strings
  int _levenshteinDistance(String s1, String s2) {
    final len1 = s1.length;
    final len2 = s2.length;

    final matrix = List.generate(len1 + 1, (_) => List<int>.filled(len2 + 1, 0));

    for (int i = 0; i <= len1; i++) {
      matrix[i][0] = i;
    }
    for (int j = 0; j <= len2; j++) {
      matrix[0][j] = j;
    }

    for (int i = 1; i <= len1; i++) {
      for (int j = 1; j <= len2; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        matrix[i][j] = math.min(
          matrix[i - 1][j] + 1,      // deletion
          math.min(
            matrix[i][j - 1] + 1,    // insertion
            matrix[i - 1][j - 1] + cost, // substitution
          ),
        );
      }
    }

    return matrix[len1][len2];
  }

  /// Find longest common substring between two strings
  String _longestCommonSubstring(String s1, String s2) {
    final len1 = s1.length;
    final len2 = s2.length;

    final dp = List.generate(len1 + 1, (_) => List<int>.filled(len2 + 1, 0));
    int maxLength = 0;
    int endIndex = 0;

    for (int i = 1; i <= len1; i++) {
      for (int j = 1; j <= len2; j++) {
        if (s1[i - 1] == s2[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
          if (dp[i][j] > maxLength) {
            maxLength = dp[i][j];
            endIndex = i;
          }
        }
      }
    }

    return maxLength > 0 ? s1.substring(endIndex - maxLength, endIndex) : '';
  }

  /// Calculate similarity between two addresses (0.0 to 1.0)
  /// Used to match Gemini's grounded address against Places API candidate addresses
  double _calculateAddressSimilarity(String groundedAddress, String candidateAddress) {
    if (groundedAddress.isEmpty || candidateAddress.isEmpty) return 0.0;

    // Normalize addresses for comparison
    final normGrounded = _normalizeAddress(groundedAddress);
    final normCandidate = _normalizeAddress(candidateAddress);

    // Exact match
    if (normGrounded == normCandidate) return 1.0;

    // Extract address components for matching
    final groundedParts = _extractAddressParts(groundedAddress);
    final candidateParts = _extractAddressParts(candidateAddress);

    double score = 0.0;
    int matchedComponents = 0;
    int totalComponents = 0;

    // Check street match (most important)
    if (groundedParts['street'] != null && candidateParts['street'] != null) {
      totalComponents++;
      final streetSimilarity = _calculateNameSimilarity(
        groundedParts['street']!,
        candidateParts['street']!,
      );
      if (streetSimilarity >= 0.7) {
        matchedComponents++;
        score += 0.4 * streetSimilarity;
      }
    }

    // Check city match
    if (groundedParts['city'] != null && candidateParts['city'] != null) {
      totalComponents++;
      if (groundedParts['city']!.toLowerCase() == candidateParts['city']!.toLowerCase()) {
        matchedComponents++;
        score += 0.25;
      }
    }

    // Check state match
    if (groundedParts['state'] != null && candidateParts['state'] != null) {
      totalComponents++;
      if (_statesMatch(groundedParts['state']!, candidateParts['state']!)) {
        matchedComponents++;
        score += 0.2;
      }
    }

    // Check zip code match (if available)
    if (groundedParts['zip'] != null && candidateParts['zip'] != null) {
      totalComponents++;
      if (groundedParts['zip'] == candidateParts['zip']) {
        matchedComponents++;
        score += 0.15;
      }
    }

    // Fallback: use general string similarity if component matching fails
    if (totalComponents == 0 || matchedComponents == 0) {
      final editSimilarity = 1.0 - (_levenshteinDistance(normGrounded, normCandidate) / 
          math.max(normGrounded.length, normCandidate.length));
      return math.max(0.0, editSimilarity);
    }

    return math.min(1.0, score);
  }

  /// Normalize an address string for comparison
  String _normalizeAddress(String address) {
    return address
        .toLowerCase()
        .replaceAll(RegExp(r'\bstreet\b'), 'st')
        .replaceAll(RegExp(r'\broad\b'), 'rd')
        .replaceAll(RegExp(r'\bavenue\b'), 'ave')
        .replaceAll(RegExp(r'\bdrive\b'), 'dr')
        .replaceAll(RegExp(r'\bboulevard\b'), 'blvd')
        .replaceAll(RegExp(r'\blane\b'), 'ln')
        .replaceAll(RegExp(r'\bcourt\b'), 'ct')
        .replaceAll(RegExp(r'\bnorth\b'), 'n')
        .replaceAll(RegExp(r'\bsouth\b'), 's')
        .replaceAll(RegExp(r'\beast\b'), 'e')
        .replaceAll(RegExp(r'\bwest\b'), 'w')
        .replaceAll(RegExp(r'[,.]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Extract address components (street, city, state, zip)
  Map<String, String?> _extractAddressParts(String address) {
    final parts = <String, String?>{};
    final cleanAddress = address.trim();

    // Try to extract zip code (5 digits or 5+4 format)
    final zipMatch = RegExp(r'\b(\d{5})(?:-\d{4})?\b').firstMatch(cleanAddress);
    if (zipMatch != null) {
      parts['zip'] = zipMatch.group(1);
    }

    // Split by comma to get components
    final components = cleanAddress.split(',').map((c) => c.trim()).toList();

    if (components.isNotEmpty) {
      // First component is usually street address
      parts['street'] = components[0];
    }

    if (components.length >= 2) {
      // Second component is usually city
      parts['city'] = components[1];
    }

    if (components.length >= 3) {
      // Third component often has state and zip
      final stateZip = components[2].trim();
      // Extract state (2-letter abbreviation or full name)
      final stateMatch = RegExp(r'\b([A-Z]{2})\b').firstMatch(stateZip.toUpperCase());
      if (stateMatch != null) {
        parts['state'] = stateMatch.group(1);
      } else {
        // Try to match state name
        for (final stateName in _stateNameVariants.keys) {
          if (stateZip.toLowerCase().contains(stateName)) {
            parts['state'] = _stateNameVariants[stateName]?.first ?? stateName;
            break;
          }
        }
      }
    }

    return parts;
  }

  /// Check if two state references match (handles abbreviations and full names)
  bool _statesMatch(String state1, String state2) {
    final s1 = state1.toLowerCase().trim();
    final s2 = state2.toLowerCase().trim();

    if (s1 == s2) return true;

    // Check against state name variants
    for (final entry in _stateNameVariants.entries) {
      final variants = [entry.key, ...entry.value];
      final s1Match = variants.any((v) => v == s1 || s1.contains(v));
      final s2Match = variants.any((v) => v == s2 || s2.contains(v));
      if (s1Match && s2Match) return true;
    }

    return false;
  }
  
  /// Extract a distinctive location name from an address
  /// e.g., "189 The Grove Dr" → "The Grove"
  /// e.g., "100 Century City Plaza" → "Century City"
  /// Used to match businesses that include location names (like "American Beauty - The Grove")
  String? _extractLocationNameFromAddress(String address) {
    final lowerAddress = address.toLowerCase();
    
    // Well-known LA/CA shopping centers and complexes
    const knownLocations = [
      'the grove',
      'century city',
      'santa monica place',
      'westfield',
      'glendale galleria',
      'americana at brand',
      'beverly center',
      'fashion island',
      'south coast plaza',
      'irvine spectrum',
      'fashion valley',
      'del amo',
      'topanga',
      'stanford shopping center',
      'valley fair',
      'downtown disney',
      'citadel outlets',
      'ontario mills',
      'fashion square',
    ];
    
    for (final location in knownLocations) {
      if (lowerAddress.contains(location)) {
        // Return with proper capitalization
        return location.split(' ').map((word) => 
          word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1)}' : word
        ).join(' ');
      }
    }
    
    // Try to extract location names from common patterns
    // Pattern: "[number] [Location Name] Dr/Drive/Blvd/Ave"
    final locationPatterns = [
      // "189 The Grove Dr" → "The Grove"
      RegExp(r'\d+\s+(the\s+\w+)\s+(?:dr|drive|blvd|boulevard|ave|avenue|rd|road|way|pl|plaza)', caseSensitive: false),
      // "100 Century City Mall" → "Century City"
      RegExp(r'\d+\s+(\w+\s+city)\b', caseSensitive: false),
      // Extract from address that has "at [Location]"
      RegExp(r'\bat\s+(the\s+\w+)\b', caseSensitive: false),
    ];
    
    for (final pattern in locationPatterns) {
      final match = pattern.firstMatch(address);
      if (match != null && match.group(1) != null) {
        final extracted = match.group(1)!;
        // Return with proper capitalization
        return extracted.split(' ').map((word) => 
          word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}' : word
        ).join(' ');
      }
    }
    
    return null;
  }
  
  /// Normalize for compact comparison - removes ALL spaces to handle compound word variations
  /// AND expands common abbreviations to handle cases like:
  /// - "Mt Storm King" and "Mount Storm King" → both become "mountstormking"
  /// - "James Island View Point" and "James Island Viewpoint" → both become "jamesislandviewpoint"
  /// - "Hoh Rain Forest" and "Hoh Rainforest" → both become "hohrainforest"
  String _normalizeCompact(String text) {
    var normalized = text.toLowerCase();
    
    // Expand common abbreviations BEFORE removing spaces
    // This allows "Mt Storm King" to become "Mount Storm King" first
    normalized = normalized
        .replaceAll(RegExp(r'\bmt\b'), 'mount')      // Mt → Mount
        .replaceAll(RegExp(r'\brd\b'), 'road')       // Rd → Road
        .replaceAll(RegExp(r'\bst\b'), 'street')     // St → Street (but not "Saint")
        .replaceAll(RegExp(r'\bdr\b'), 'drive')      // Dr → Drive
        .replaceAll(RegExp(r'\bave\b'), 'avenue')    // Ave → Avenue
        .replaceAll(RegExp(r'\bblvd\b'), 'boulevard') // Blvd → Boulevard
        .replaceAll(RegExp(r'\bhwy\b'), 'highway')   // Hwy → Highway
        .replaceAll(RegExp(r'\bpt\b'), 'point')      // Pt → Point
        .replaceAll(RegExp(r'\bnp\b'), 'nationalpark'); // NP → National Park
    
    // Remove ALL non-alphanumeric including spaces
    return normalized.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// Extract the broader region (typically state/country) from a region context.
  /// 
  /// IMPORTANT: This now returns the STATE level first, not jumping straight to country.
  /// For example:
  /// - "Port Angeles, Washington State, USA" → "Washington State" (NOT "USA")
  /// - "Washington State, USA" → "Washington" (drop "State" suffix), or "Washington State" if no suffix
  /// - "Baton Rouge, Louisiana" → "Louisiana"
  /// - "Seattle, Washington, USA" → "Washington"
  /// - "Paris, France" → "France"
  ///
  /// This is used for fallback searches when a location is in the broader region
  /// but not in the specific city (e.g., Lake Crescent is in Washington State but
  /// searching with "Port Angeles" doesn't find it).
  String? _extractBroaderRegion(String? regionContext) {
    if (regionContext == null || regionContext.isEmpty) return null;

    // Split by comma and take everything after the first part (the city)
    final parts = regionContext.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

    if (parts.length <= 1) {
      // Single part like "Louisiana" or "France" - no broader region to extract
      return null;
    }

    // CRITICAL FIX: Return the STATE/REGION level, NOT the country
    // "Washington State, USA" → "Washington State" (or just "Washington")
    // "Port Angeles, Washington State, USA" → "Washington State"
    // This prevents searches from going too broad (USA) and finding wrong places
    // like "Storm King Mountain, NY" instead of "Mt Storm King, WA"
    
    // If we have 3+ parts like "Port Angeles, Washington State, USA"
    // Return the middle part(s) without the country (USA)
    if (parts.length >= 3) {
      // Check if last part is a country (USA, United States, etc.)
      final lastPart = parts.last.toLowerCase();
      if (lastPart == 'usa' || lastPart == 'united states' || 
          lastPart == 'us' || lastPart == 'america') {
        // Return parts[1] to parts[n-1] - the state/region without the country
        // "Port Angeles, Washington State, USA" → "Washington State"
        final stateParts = parts.sublist(1, parts.length - 1);
        if (stateParts.isNotEmpty) {
          return stateParts.join(', ');
        }
      }
    }
    
    // For 2 parts like "Washington State, USA" or "Baton Rouge, Louisiana"
    // Return the second part (state)
    if (parts.length == 2) {
      final secondPart = parts[1];
      // If it's just "USA" or similar country, we have nowhere broader to go
      final lower = secondPart.toLowerCase();
      if (lower == 'usa' || lower == 'united states' || lower == 'us' || lower == 'america') {
        // Try stripping "State" from the first part if present
        // "Washington State" → "Washington"
        final firstPart = parts[0];
        if (firstPart.toLowerCase().endsWith(' state')) {
          return firstPart.substring(0, firstPart.length - 6).trim();
        }
        return null; // Can't go broader
      }
      return secondPart;
    }

    // Fallback: return everything except the first part
    return parts.sublist(1).join(', ');
  }

  /// Major landmarks/parks that imply a specific US state.
  /// When state isn't explicitly mentioned, these help infer the correct state.
  static const Map<String, String> _landmarkToState = {
    // Washington State
    'olympic national park': 'Washington',
    'olympic peninsula': 'Washington',
    'mount rainier': 'Washington',
    'mt rainier': 'Washington',
    'north cascades': 'Washington',
    'san juan islands': 'Washington',
    'puget sound': 'Washington',
    'makah reservation': 'Washington',
    'neah bay': 'Washington',
    'shi shi beach': 'Washington',
    'cape flattery': 'Washington',
    // California
    'yosemite': 'California',
    'death valley': 'California',
    'joshua tree': 'California',
    'sequoia national': 'California',
    'kings canyon': 'California',
    'redwood national': 'California',
    'channel islands': 'California',
    'pinnacles national': 'California',
    'lassen volcanic': 'California',
    'point reyes': 'California',
    // Oregon
    'crater lake': 'Oregon',
    'columbia river gorge': 'Oregon',
    'mount hood': 'Oregon',
    'mt hood': 'Oregon',
    // Arizona
    'grand canyon': 'Arizona',
    'saguaro national': 'Arizona',
    'petrified forest': 'Arizona',
    'monument valley': 'Arizona',
    // Utah
    'zion national': 'Utah',
    'bryce canyon': 'Utah',
    'arches national': 'Utah',
    'canyonlands': 'Utah',
    'capitol reef': 'Utah',
    // Colorado
    'rocky mountain national': 'Colorado',
    'mesa verde': 'Colorado',
    'great sand dunes': 'Colorado',
    'black canyon': 'Colorado',
    // Wyoming
    'yellowstone': 'Wyoming',
    'grand teton': 'Wyoming',
    "devil's tower": 'Wyoming',
    'devils tower': 'Wyoming',
    // Montana
    'glacier national park': 'Montana',
    // Nevada
    'great basin national': 'Nevada',
    'lake tahoe': 'Nevada', // Also California, but Nevada is common reference
    // Hawaii
    'hawaii volcanoes': 'Hawaii',
    'haleakala': 'Hawaii',
    // Alaska
    'denali': 'Alaska',
    'glacier bay': 'Alaska',
    'kenai fjords': 'Alaska',
    'katmai': 'Alaska',
    // Florida
    'everglades': 'Florida',
    'dry tortugas': 'Florida',
    'biscayne national': 'Florida',
    // Other notable
    'acadia': 'Maine',
    'shenandoah': 'Virginia',
    'great smoky': 'Tennessee', // Also NC
    'mammoth cave': 'Kentucky',
    'hot springs national': 'Arkansas',
    'badlands': 'South Dakota',
    'wind cave': 'South Dakota',
    'theodore roosevelt': 'North Dakota',
    'voyageurs': 'Minnesota',
    'isle royale': 'Michigan',
    'cuyahoga valley': 'Ohio',
    'new river gorge': 'West Virginia',
    'big bend': 'Texas',
    'guadalupe mountains': 'Texas',
    'carlsbad caverns': 'New Mexico',
    'white sands': 'New Mexico',
  };

  /// Extract US state name from context string.
  /// 
  /// Given context like "Makah Reservation, Neah Bay, Olympic National Park" or 
  /// "Port Angeles, Washington State, USA", extracts the state name.
  /// 
  /// Returns the capitalized state name (e.g., "Washington", "California") or null if not found.
  String? _extractStateFromContext(String? context) {
    if (context == null || context.isEmpty) return null;
    
    final contextLower = context.toLowerCase();
    
    // First, check each state name and its variants (explicit state mentions)
    for (final entry in _stateNameVariants.entries) {
      final stateName = entry.key;
      final variants = entry.value;
      
      // Check full state name (with word boundaries to avoid partial matches)
      // e.g., "washington" should match but not "washington dc" matching just "dc"
      final statePattern = RegExp(r'\b' + RegExp.escape(stateName) + r'(\s+state)?\b', caseSensitive: false);
      if (statePattern.hasMatch(contextLower)) {
        // Return properly capitalized state name
        return stateName.split(' ').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
      }
      
      // Check abbreviations (must be standalone, not part of another word)
      for (final abbrev in variants) {
        // For 2-letter abbreviations, require word boundaries
        // e.g., "WA" should match but "WATER" should not match "WA"
        final abbrevPattern = RegExp(r'\b' + RegExp.escape(abbrev) + r'\b', caseSensitive: false);
        if (abbrevPattern.hasMatch(contextLower)) {
          return stateName.split(' ').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
        }
      }
    }
    
    // Second, check for major landmarks that imply a state
    // This handles cases like "Olympic National Park" → Washington
    for (final entry in _landmarkToState.entries) {
      if (contextLower.contains(entry.key)) {
        return entry.value;
      }
    }
    
    return null;
  }

  /// Check if the found place name is a good match for the original search name.
  /// Returns true if the match is good, false if we should try a broader search.
  /// 
  /// This helps detect cases like:
  /// - Searching for "Afton Villa Gardens" but finding "Afton Villa Offices"
  /// - The names share "Afton Villa" but "Gardens" vs "Offices" is a significant difference
  /// 
  /// BUT it should NOT flag as poor match when:
  /// - Searching for "The Vintage" and finding "The Vintage Baton Rouge"
  /// - The found name is the original + city name for disambiguation
  ({bool isGoodMatch, double matchScore}) _checkNameMatchQuality(String originalName, String foundName) {
    final compactOriginal = _normalizeCompact(originalName);
    final compactFound = _normalizeCompact(foundName);
    
    // Exact match is always good
    if (compactOriginal == compactFound) {
      return (isGoodMatch: true, matchScore: 1.0);
    }
    
    // Get word counts to detect when extra words indicate a DIFFERENT thing
    final originalWords = originalName.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
    final foundWords = foundName.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
    final extraWordCount = foundWords.length - originalWords.length;
    
    // Words that indicate the found result is a DIFFERENT THING than the original
    // e.g., "Lake Crescent" vs "Lake Crescent Lodge Dining Room" - the lodge/dining room
    // is a business NEAR Lake Crescent, not the lake itself
    const differentThingIndicators = [
      'lodge', 'hotel', 'motel', 'inn', 'resort', 'cabin', 'cabins',
      'restaurant', 'dining', 'room', 'cafe', 'coffee', 'bar', 'grill', 'kitchen', 'eatery',
      'store', 'shop', 'outlet', 'outlets', 'mall', 'market', 'grocery',
      'trail', 'trailhead', 'road', 'drive', 'street', 'avenue', 'highway', 'route',
      'parking', 'lot', 'garage',
      'office', 'offices', 'center', 'building',
      'airport', 'station', 'terminal',
    ];
    
    // Check if extra words indicate a different thing
    bool hasDifferentThingIndicator = false;
    if (extraWordCount > 0) {
      // Get the extra words (words in found but not matching original)
      final extraWords = foundWords.where((fw) => 
        !originalWords.any((ow) => fw.contains(ow) || ow.contains(fw))
      ).toList();
      
      hasDifferentThingIndicator = extraWords.any((w) => 
        differentThingIndicators.contains(w)
      );
    }
    
    // If found name STARTS WITH original name, check the extra content
    if (compactFound.startsWith(compactOriginal)) {
      // If extra words indicate a different thing (lodge, restaurant, trail near the place),
      // this is NOT a good match - it's a business/road near the actual place
      if (hasDifferentThingIndicator) {
        print('📷 NAME MATCH: "$foundName" contains "$originalName" but has different-thing indicators');
        // Low score - this is likely a business near the place, not the place itself
        return (isGoodMatch: false, matchScore: 0.4);
      }
      
      // If just 1-2 extra words (likely city/brand suffix), still a good match
      // e.g., "The Vintage" → "The Vintage Baton Rouge"
      if (extraWordCount <= 2) {
        return (isGoodMatch: true, matchScore: 0.95);
      }
      
      // 3+ extra words without indicators - moderate match, needs review
      return (isGoodMatch: false, matchScore: 0.6);
    }
    
    // If original contains found completely (found is a subset), also good
    // e.g., searching for "The Vintage Baton Rouge" finds "The Vintage"
    if (compactOriginal.startsWith(compactFound)) {
      // Found name is a prefix of what we searched for
      final matchRatio = compactFound.length / compactOriginal.length;
      return (isGoodMatch: matchRatio >= 0.5, matchScore: matchRatio);
    }
    
    // If one contains the other but not at the start, check more carefully
    if (compactFound.contains(compactOriginal)) {
      // Original is contained but not at start
      // Check for different-thing indicators
      if (hasDifferentThingIndicator) {
        print('📷 NAME MATCH: "$foundName" contains "$originalName" (not at start) but has different-thing indicators');
        return (isGoodMatch: false, matchScore: 0.35);
      }
      return (isGoodMatch: true, matchScore: 0.85);
    }
    
    if (compactOriginal.contains(compactFound)) {
      // Found is contained in original
      final matchRatio = compactFound.length / compactOriginal.length;
      return (isGoodMatch: matchRatio >= 0.6, matchScore: matchRatio);
    }
    
    // No containment - check word-by-word matching
    if (originalWords.isEmpty) {
      return (isGoodMatch: false, matchScore: 0.0);
    }
    
    int matchedWords = 0;
    for (final word in originalWords) {
      if (foundWords.any((fw) => fw.contains(word) || word.contains(fw))) {
        matchedWords++;
      }
    }
    
    final matchRatio = matchedWords / originalWords.length;
    
    // We need at least 70% word match for a good result
    // "Afton Villa Gardens" vs "Afton Villa Offices" = 2/3 = 66% (not good enough)
    return (isGoodMatch: matchRatio >= 0.7, matchScore: matchRatio);
  }

  /// Check if the place result type is compatible with the expected Gemini type
  /// 
  /// This prevents cases like:
  /// - Searching for "Lake Crescent" (Lake) but finding "Lake Crescent Road" (route)
  /// - Searching for "Cape Flattery" (Scenic viewpoint) but finding "Cape Flattery Road" (route)
  /// - Searching for "Forks" (Town) but finding "Forks Motel" (lodging)
  /// - Searching for "Port Angeles" (City) but finding "Super 8 Port Angeles" (hotel)
  /// 
  /// Returns true if types are compatible, false if there's a type mismatch
  bool _isTypeCompatible(String? geminiType, List<String> placeTypes) {
    if (geminiType == null || geminiType.isEmpty) return true; // No type hint, assume compatible
    
    final geminiTypeLower = geminiType.toLowerCase();
    
    // Define type compatibility mappings
    // Nature types should match nature place types, NOT roads/routes
    // Use contains() checks for compound types like "scenic viewpoint", "hiking trail"
    final isNatureGeminiType = geminiTypeLower == 'lake' ||
        geminiTypeLower == 'waterfall' ||
        geminiTypeLower == 'mountain' ||
        geminiTypeLower == 'trail' ||
        geminiTypeLower == 'beach' ||
        geminiTypeLower == 'park' ||
        geminiTypeLower == 'rainforest' ||
        geminiTypeLower == 'viewpoint' ||
        geminiTypeLower == 'natural_feature' ||
        geminiTypeLower == 'landmark' ||
        geminiTypeLower.contains('viewpoint') ||  // "scenic viewpoint"
        geminiTypeLower.contains('trail') ||      // "hiking trail"
        geminiTypeLower.contains('beach') ||      // "scenic beach"
        geminiTypeLower.contains('waterfall') ||  // "scenic waterfall"
        geminiTypeLower.contains('lake') ||       // "scenic lake"
        geminiTypeLower.contains('mountain');     // "mountain/hiking trail"
    
    final naturePlaceTypes = ['natural_feature', 'park', 'national_park', 'state_park', 'beach', 'campground', 'hiking_area', 'tourist_attraction'];
    final roadTypes = ['route', 'street_address', 'intersection', 'premise'];
    // Note: 'geocode' alone is not always bad - some natural features have geocode type
    
    // City/Town types should match locality types, NOT businesses or parks
    // IMPORTANT: Match compound types like "City with Attractions, Parks..." 
    // by checking if geminiType STARTS with city-related words
    final isCityGeminiType = geminiTypeLower == 'city' ||
        geminiTypeLower == 'town' ||
        geminiTypeLower == 'locality' ||
        geminiTypeLower == 'neighborhood' ||
        geminiTypeLower.startsWith('city ') ||    // "City with Attractions..."
        geminiTypeLower.startsWith('town ') ||    // "Town with..."
        RegExp(r'^city\b').hasMatch(geminiTypeLower);  // "city" as first word
    
    final cityPlaceTypes = ['locality', 'sublocality', 'neighborhood', 'political', 'administrative_area_level_1', 'administrative_area_level_2', 'administrative_area_level_3'];
    
    // Check nature type compatibility
    if (isNatureGeminiType) {
      // If searching for a nature type (lake, beach, mountain, etc.), reject:
      // 1. Roads/routes - "Lake Crescent Road" is not "Lake Crescent"
      // 2. Restaurants/food - "Lake Crescent Lodge Dining Room" is not the lake
      // 3. Hotels/lodging - "Lake Crescent Lodge" is a business NEAR the lake
      // 4. Stores/shopping - "Seattle Premium Outlets" is not "Seattle" the city
      final hasRoadType = placeTypes.any((t) => roadTypes.contains(t));
      final hasNatureType = placeTypes.any((t) => naturePlaceTypes.contains(t));
      
      // Types that indicate a business NEAR the natural feature, not the feature itself
      const businessTypes = [
        'restaurant', 'food', 'cafe', 'bar', 'bakery', 'meal_takeaway', 'meal_delivery',
        'lodging', 'hotel', 'motel', 'resort', 'rv_park',
        'store', 'shopping_mall', 'clothing_store', 'convenience_store', 'supermarket',
        'gas_station', 'car_repair', 'car_wash',
      ];
      final hasBusinessType = placeTypes.any((t) => businessTypes.contains(t));
      
      // Reject if it's a road OR a business type (without being an actual nature type)
      if ((hasRoadType || hasBusinessType) && !hasNatureType) {
        final reason = hasRoadType ? 'road/route' : 'business (${placeTypes.take(3).join(', ')})';
        print('📷 TYPE CHECK: Incompatible - searching for "$geminiType" but found $reason');
        return false;
      }
    }
    
    // Check city/town type compatibility - STRICT: must have locality type
    if (isCityGeminiType) {
      final hasCityType = placeTypes.any((t) => cityPlaceTypes.contains(t));
      
      // For city searches, we REQUIRE a locality type - not just reject businesses
      // This prevents "Portland" matching "Portland Women's Forum State Scenic Viewpoint"
      if (!hasCityType) {
        print('📷 TYPE CHECK: Incompatible - searching for city/town but found non-locality (types: ${placeTypes.join(', ')})');
        return false;
      }
    }
    
    return true; // Types are compatible or no specific type check applies
  }

  /// Check if a name looks like it was derived from an Instagram/social media handle
  /// These often need to be looked up online to find the actual business name
  /// 
  /// Examples:
  /// - "Sofa Seattle" (from @sofaseattle) → looks like handle (sofa = abbreviation)
  /// - "Rockcreek" (from @rockcreek206) → looks like handle
  /// - "Kuya Lord" (from @kuyalord_la) → already converted, but original was handle
  /// 
  /// Patterns that suggest a handle-derived name:
  /// 1. Short name (1-2 words) + city name
  /// 2. Concatenated words that don't form a common phrase
  /// 3. Unusual capitalization or word breaks
  bool _looksLikeHandleDerivedName(String name) {
    if (name.isEmpty) return false;
    
    final words = name.trim().split(RegExp(r'\s+'));
    final lowerName = name.toLowerCase();
    
    // Common city names that might be appended to handles
    const citySuffixes = [
      'seattle', 'portland', 'la', 'nyc', 'sf', 'chicago', 'miami',
      'denver', 'austin', 'dallas', 'houston', 'phoenix', 'atlanta',
      'boston', 'dc', 'vegas', 'san diego', 'san francisco',
    ];
    
    // Check if it ends with a city name (common handle pattern)
    for (final city in citySuffixes) {
      if (lowerName.endsWith(city) && words.length <= 3) {
        return true;
      }
    }
    
    // Check for short names that might be abbreviations
    // "Sofa Seattle" = 2 words, first word is short (4 chars) and unusual
    if (words.length == 2) {
      final firstWord = words[0].toLowerCase();
      final secondWord = words[1].toLowerCase();
      
      // First word is short (likely abbreviation) and second is a city
      if (firstWord.length <= 5 && citySuffixes.contains(secondWord)) {
        return true;
      }
    }
    
    // Very short single-word names that aren't common words
    if (words.length == 1 && name.length <= 10) {
      // This could be a handle-derived name like "Rockcreek"
      return true;
    }
    
    return false;
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

  // ============ AI RERANKING METHODS ============

  /// Evaluate the overall match quality of a Places API result
  /// 
  /// This combines multiple signals into a single quality assessment:
  /// - Name match quality (from _checkNameMatchQuality)
  /// - Type compatibility (from _isTypeCompatible)
  /// - Whether a broader search fallback was used
  /// - Confidence score
  /// 
  /// Returns a record with:
  /// - needsRerank: true if the match quality is low enough to warrant AI reranking
  /// - combinedConfidence: overall confidence score
  /// - reason: explanation for the assessment
  ({bool needsRerank, double combinedConfidence, String reason}) _evaluateMatchQuality({
    required String originalName,
    required Map<String, dynamic>? selectedResult,
    String? geminiType,
    bool usedBroaderSearch = false,
    double baseConfidence = 0.85,
  }) {
    if (selectedResult == null) {
      return (
        needsRerank: false, // No result to rerank
        combinedConfidence: 0.0,
        reason: 'No result found',
      );
    }

    final foundName = (selectedResult['name'] ?? 
        selectedResult['description']?.toString().split(',').first ?? '') as String;
    final placeTypes = (selectedResult['types'] as List?)?.cast<String>() ?? [];
    
    // Check name match quality
    final nameQuality = _checkNameMatchQuality(originalName, foundName);
    
    // Check type compatibility
    final isTypeOk = _isTypeCompatible(geminiType, placeTypes);
    
    // Calculate combined confidence
    double confidence = baseConfidence;
    final reasons = <String>[];
    
    // Penalize for poor name match
    if (!nameQuality.isGoodMatch) {
      confidence *= 0.6;
      reasons.add('poor name match (${(nameQuality.matchScore * 100).toInt()}%)');
    } else if (nameQuality.matchScore < 0.8) {
      confidence *= 0.85;
      reasons.add('moderate name match (${(nameQuality.matchScore * 100).toInt()}%)');
    }
    
    // Penalize for type mismatch
    if (!isTypeOk) {
      confidence *= 0.5;
      reasons.add('type mismatch');
    }
    
    // Penalize for broader search fallback
    if (usedBroaderSearch) {
      confidence *= 0.85;
      reasons.add('used broader search');
    }
    
    // Determine if we need AI reranking
    // Threshold: confidence <= 0.8 OR name match < 0.7 OR type mismatch
    final needsRerank = confidence <= 0.8 || 
        nameQuality.matchScore < 0.7 || 
        !isTypeOk ||
        (usedBroaderSearch && nameQuality.matchScore < 0.85);
    
    return (
      needsRerank: needsRerank,
      combinedConfidence: confidence,
      reason: reasons.isEmpty ? 'Good match' : reasons.join(', '),
    );
  }

  /// Attempt AI reranking of Places API candidates when initial scoring is weak
  /// 
  /// This method calls Gemini to semantically compare candidates and select
  /// the best match based on contextual understanding.
  /// 
  /// [originalName] - The original location name being searched
  /// [candidates] - List of Places API results to rerank
  /// [selectedIndex] - The currently selected index from initial scoring
  /// [geminiType] - Expected type from Gemini extraction
  /// [regionContext] - Geographic context
  /// [surroundingText] - Caption or page text for context
  /// [userLocation] - User location for disambiguation
  /// 
  /// Returns a record with:
  /// - selectedResult: The chosen result (may be different from initial selection)
  /// - selectedIndex: Index of the chosen result
  /// - confidence: Final confidence score
  /// - usedAIRerank: Whether AI reranking changed the selection
  /// - needsConfirmation: Whether the result should be flagged for user review
  Future<({
    Map<String, dynamic>? selectedResult,
    int selectedIndex,
    double confidence,
    bool usedAIRerank,
    bool needsConfirmation,
  })> _maybeAIRerank({
    required String originalName,
    required List<Map<String, dynamic>> candidates,
    required int selectedIndex,
    String? geminiType,
    String? regionContext,
    String? surroundingText,
    LatLng? userLocation,
    bool usedBroaderSearch = false,
  }) async {
    if (candidates.isEmpty) {
      return (
        selectedResult: null,
        selectedIndex: -1,
        confidence: 0.0,
        usedAIRerank: false,
        needsConfirmation: true,
      );
    }

    // Get the initially selected result
    final initialResult = selectedIndex >= 0 && selectedIndex < candidates.length 
        ? candidates[selectedIndex] 
        : candidates.first;
    
    // Evaluate if we need reranking
    final quality = _evaluateMatchQuality(
      originalName: originalName,
      selectedResult: initialResult,
      geminiType: geminiType,
      usedBroaderSearch: usedBroaderSearch,
    );
    
    print('🔍 RERANK CHECK: "$originalName" - ${quality.reason}');
    print('   Combined confidence: ${(quality.combinedConfidence * 100).toInt()}%');
    print('   Needs rerank: ${quality.needsRerank}');
    
    if (!quality.needsRerank) {
      // No reranking needed, return initial selection
      return (
        selectedResult: initialResult,
        selectedIndex: selectedIndex,
        confidence: quality.combinedConfidence,
        usedAIRerank: false,
        needsConfirmation: false,
      );
    }
    
    // Take top N candidates for reranking (5-8)
    final topCandidates = candidates.take(math.min(8, candidates.length)).toList();
    
    print('🤖 AI RERANK: Triggering for "$originalName" with ${topCandidates.length} candidates');
    
    try {
      final rerankResult = await _gemini.rerankPlaceCandidates(
        originalLocationCue: originalName,
        candidates: topCandidates,
        regionContext: regionContext,
        surroundingText: surroundingText,
        expectedType: geminiType,
        userLocationBias: userLocation,
      );
      
      print('✅ AI RERANK: Selected index ${rerankResult.selectedIndex}, confidence ${(rerankResult.confidence * 100).toInt()}%');
      if (rerankResult.reason != null) {
        print('   Reason: ${rerankResult.reason}');
      }
      
      // Handle "none fit" response
      if (rerankResult.selectedIndex < 0) {
        print('⚠️ AI RERANK: No good match found, keeping original but flagging for confirmation');
        return (
          selectedResult: initialResult,
          selectedIndex: selectedIndex,
          confidence: quality.combinedConfidence * 0.5, // Further reduce confidence
          usedAIRerank: true,
          needsConfirmation: true, // Flag for user confirmation
        );
      }
      
      // Get the AI-selected result
      final aiSelectedResult = topCandidates[rerankResult.selectedIndex];
      final aiSelectedName = (aiSelectedResult['name'] ?? 
          aiSelectedResult['description']?.toString().split(',').first ?? '') as String;
      
      // Check if AI selected a different result than initial scoring
      final changedSelection = rerankResult.selectedIndex != selectedIndex;
      if (changedSelection) {
        print('🔄 AI RERANK: Changed selection from "${ (initialResult['name'] ?? initialResult['description']?.toString().split(',').first ?? '')}" to "$aiSelectedName"');
      }
      
      // Validate the AI selection through existing type checks
      final aiPlaceTypes = (aiSelectedResult['types'] as List?)?.cast<String>() ?? [];
      final aiTypeOk = _isTypeCompatible(geminiType, aiPlaceTypes);
      
      // If AI selection also has type mismatch, flag for confirmation
      final needsConfirmation = !aiTypeOk || rerankResult.confidence < 0.6;
      
      return (
        selectedResult: aiSelectedResult,
        selectedIndex: rerankResult.selectedIndex,
        confidence: rerankResult.confidence,
        usedAIRerank: true,
        needsConfirmation: needsConfirmation,
      );
    } catch (e) {
      print('❌ AI RERANK ERROR: $e');
      // Fall back to initial selection with low confidence
      return (
        selectedResult: initialResult,
        selectedIndex: selectedIndex,
        confidence: quality.combinedConfidence * 0.7, // Reduce confidence due to error
        usedAIRerank: false,
        needsConfirmation: true,
      );
    }
  }

  // ============ END AI RERANKING METHODS ============
}
