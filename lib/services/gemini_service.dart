import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../config/api_secrets.dart';
import '../models/gemini_grounding_result.dart';

/// Service for interacting with Google's Gemini API with Maps grounding
/// 
/// This service uses the Gemini API to extract location information from URLs
/// using Google Maps grounding, which provides verified Place IDs and coordinates.
class GeminiService {
  static final GeminiService _instance = GeminiService._internal();

  factory GeminiService() => _instance;

  GeminiService._internal();

  final Dio _dio = Dio();
  
  // Gemini API base URL
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta';
  
  // Default model - using flash for speed and cost efficiency
  static const String _defaultModel = 'gemini-2.0-flash';

  /// Get the API key
  static String get _apiKey => ApiSecrets.geminiApiKey;

  /// Check if the service is properly configured
  bool get isConfigured {
    final key = _apiKey;
    return key.isNotEmpty && 
           !key.contains('YOUR_') && 
           key.length > 20;
  }

  /// Extract location information from a URL using Gemini with Maps grounding
  /// 
  /// [url] - The URL to analyze for location information
  /// [userLocation] - Optional user location for better results
  /// 
  /// Returns a [GeminiGroundingResult] containing extracted locations,
  /// or null if extraction fails or no locations are found.
  Future<GeminiGroundingResult?> extractLocationFromUrl(
    String url, {
    LatLng? userLocation,
  }) async {
    if (!isConfigured) {
      print('⚠️ GEMINI: API key not configured. Please add your Gemini API key.');
      return null;
    }

    try {
      final prompt = _buildLocationExtractionPrompt(url);
      
      print('🤖 GEMINI: Extracting location from URL: $url');
      
      final response = await _callGeminiWithMapsGrounding(
        prompt,
        userLocation: userLocation,
      );
      
      if (response == null) {
        print('⚠️ GEMINI: No response from API');
        return null;
      }

      final result = GeminiGroundingResult.fromApiResponse(response);
      
      print('✅ GEMINI: Found ${result.locationCount} location(s)');
      for (final loc in result.locations) {
        print('   📍 ${loc.name} (${loc.placeId})');
      }
      
      return result;
    } catch (e, stackTrace) {
      print('❌ GEMINI ERROR: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Extract locations from general text content
  Future<GeminiGroundingResult?> extractLocationsFromText(
    String text, {
    LatLng? userLocation,
  }) async {
    if (!isConfigured) {
      print('⚠️ GEMINI: API key not configured');
      return null;
    }

    try {
      final prompt = _buildTextLocationExtractionPrompt(text);
      
      print('🤖 GEMINI: Extracting locations from text');
      
      final response = await _callGeminiWithMapsGrounding(
        prompt,
        userLocation: userLocation,
      );
      
      if (response == null) return null;

      return GeminiGroundingResult.fromApiResponse(response);
    } catch (e) {
      print('❌ GEMINI ERROR: $e');
      return null;
    }
  }

  /// Extract ALL locations from a web page's content
  /// Optimized for articles like "50 best restaurants" or travel guides
  Future<GeminiGroundingResult?> extractLocationsFromWebPage(
    String pageContent, {
    String? pageUrl,
    LatLng? userLocation,
  }) async {
    if (!isConfigured) {
      print('⚠️ GEMINI: API key not configured');
      return null;
    }

    try {
      final prompt = _buildWebPageLocationExtractionPrompt(pageContent, pageUrl: pageUrl);
      
      print('🤖 GEMINI: Extracting ALL locations from web page content (${pageContent.length} chars)');
      
      final response = await _callGeminiWithMapsGrounding(
        prompt,
        userLocation: userLocation,
      );
      
      if (response == null) return null;

      final result = GeminiGroundingResult.fromApiResponse(response);
      print('✅ GEMINI: Found ${result.locationCount} location(s) from web page');
      
      return result;
    } catch (e) {
      print('❌ GEMINI ERROR: $e');
      return null;
    }
  }

  /// Extract locations from a YouTube video using Vertex AI via Cloud Function
  /// 
  /// This method calls a Firebase Cloud Function that uses Vertex AI to analyze
  /// the actual video content (both audio and visuals) to extract location information.
  /// 
  /// [youtubeUrl] - The YouTube video URL to analyze
  /// [userLocation] - Optional user location for better results
  /// 
  /// Returns a [GeminiGroundingResult] containing extracted locations,
  /// or null if extraction fails or no locations are found.
  Future<GeminiGroundingResult?> extractLocationsFromYouTubeVideo(
    String youtubeUrl, {
    LatLng? userLocation,
  }) async {
    // Validate YouTube URL
    if (!_isValidYouTubeUrl(youtubeUrl)) {
      print('⚠️ GEMINI: Invalid YouTube URL: $youtubeUrl');
      return null;
    }

    try {
      print('🎬 VERTEX AI: Analyzing YouTube video via Cloud Function: $youtubeUrl');
      
      // Call the Cloud Function
      final callable = FirebaseFunctions.instance.httpsCallable(
        'analyzeYouTubeVideo',
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 120),
        ),
      );
      
      final response = await callable.call<Map<String, dynamic>>({
        'youtubeUrl': youtubeUrl,
        if (userLocation != null) 'userLocation': {
          'lat': userLocation.latitude,
          'lng': userLocation.longitude,
        },
      });
      
      final data = response.data;
      
      // Check for errors
      if (data['error'] != null && data['error'].toString().isNotEmpty) {
        print('⚠️ VERTEX AI: Cloud Function returned error: ${data['error']}');
        return null;
      }
      
      // Parse locations from response
      final locationsList = data['locations'] as List<dynamic>?;
      if (locationsList == null || locationsList.isEmpty) {
        print('⚠️ VERTEX AI: No locations found in YouTube video');
        return null;
      }
      
      // Convert to GeminiGroundingResult format
      final result = GeminiGroundingResult.fromCloudFunctionResponse(locationsList);
      
      print('✅ VERTEX AI: Found ${result.locationCount} location(s) from YouTube video');
      for (final loc in result.locations) {
        print('   📍 ${loc.name} (${loc.city ?? 'unknown city'})');
      }
      
      return result;
    } on FirebaseFunctionsException catch (e) {
      print('❌ VERTEX AI Cloud Function ERROR: ${e.code} - ${e.message}');
      print('   Details: ${e.details}');
      return null;
    } catch (e, stackTrace) {
      print('❌ VERTEX AI YouTube ERROR: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Validate if a URL is a valid YouTube URL
  bool _isValidYouTubeUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('youtube.com/watch') ||
           lower.contains('youtube.com/shorts') ||
           lower.contains('youtu.be/') ||
           lower.contains('youtube.com/embed');
  }

  /// Build prompt for YouTube video location extraction
  String _buildYouTubeLocationExtractionPrompt() {
    return '''
You are an expert at extracting location and place information from videos.
Analyze this YouTube video thoroughly - both the AUDIO (speech, narration) and VISUAL content (on-screen text, locations shown, signage).

=== WHAT TO LOOK FOR ===

**AUDIO/SPEECH:**
- Location names mentioned by the speaker
- Addresses read aloud
- City, neighborhood, or area names
- Business names (restaurants, hotels, attractions, stores)
- "We're here at...", "This is...", "Welcome to..."

**VISUAL CONTENT:**
- Text overlays showing location names or addresses
- Signs, storefronts, or landmarks visible on screen
- Location tags or captions added by the creator
- Maps or directions shown in the video
- Business names visible on buildings or menus

**VIDEO DESCRIPTION/TITLE:**
- Location information from the video title
- Places mentioned in any on-screen text

=== OUTPUT REQUIREMENTS ===

For EACH distinct place, business, or location found, provide:
1. The exact business or place name
2. The full street address if mentioned/shown
3. The city, state/province, and country
4. The type of place (restaurant, cafe, attraction, hotel, store, park, etc.)

=== OUTPUT FORMAT ===
Return a JSON array with all locations found:

[
  {
    "name": "Business or Place Name",
    "address": "Street address or null",
    "city": "City name",
    "region": "State/Region or null",
    "country": "Country or null",
    "type": "restaurant/cafe/bar/hotel/attraction/store/park/landmark"
  }
]

=== IMPORTANT ===
- Extract ALL locations mentioned or shown, not just the main one
- If a video is a "Top 10" or list, extract all items on the list
- Include timestamps if helpful (e.g., "mentioned at 2:30")
- If no location information found, return: []
- Return ONLY the JSON array, no other text
- Use Google Maps data to verify locations and provide accurate Place IDs
''';
  }

  /// Call Gemini API with YouTube video URL using file_data format
  /// 
  /// This uses the native YouTube URL support added in March 2025
  Future<Map<String, dynamic>?> _callGeminiWithYouTubeVideo(
    String youtubeUrl,
    String prompt, {
    LatLng? userLocation,
  }) async {
    final endpoint = '$_baseUrl/models/$_defaultModel:generateContent';
    
    // Build request body with YouTube video as file_data
    final requestBody = {
      'contents': [
        {
          'parts': [
            // The prompt/instruction
            {'text': prompt},
            // The YouTube video URL using file_data format
            {
              'file_data': {
                'file_uri': youtubeUrl,
              }
            }
          ]
        }
      ],
      // Enable Google Maps grounding for location verification
      'tools': [
        {
          'googleMaps': {}
        }
      ],
      'toolConfig': {
        'functionCallingConfig': {
          'mode': 'ANY'
        }
      },
      'generationConfig': {
        'temperature': 0.1,
        'topP': 0.8,
        'topK': 40,
        'maxOutputTokens': 4096, // Higher limit for video content
      }
    };

    // Add user location for better grounding results
    if (userLocation != null) {
      requestBody['toolConfig'] = {
        ...requestBody['toolConfig'] as Map<String, dynamic>,
        'retrievalConfig': {
          'latLng': {
            'latitude': userLocation.latitude,
            'longitude': userLocation.longitude,
          }
        }
      };
    }

    try {
      print('🎬 GEMINI: Calling API with YouTube video URL...');
      print('   Video: $youtubeUrl');
      
      final response = await _dio.post(
        '$endpoint?key=$_apiKey',
        data: requestBody,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
          // YouTube video analysis can take longer
          sendTimeout: const Duration(seconds: 120),
          receiveTimeout: const Duration(seconds: 120),
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200) {
        print('✅ GEMINI: YouTube video analysis returned 200 OK');
        
        final responseData = response.data as Map<String, dynamic>;
        final candidates = responseData['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final candidate = candidates.first as Map<String, dynamic>;
          final content = candidate['content'] as Map<String, dynamic>?;
          final parts = content?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final text = parts.first['text'] as String?;
            if (text != null && text.length > 100) {
              print('📝 GEMINI YouTube Response: ${text.substring(0, 100)}...');
            } else if (text != null) {
              print('📝 GEMINI YouTube Response: $text');
            }
          }
          
          // Log grounding metadata
          final groundingMetadata = candidate['groundingMetadata'];
          if (groundingMetadata != null) {
            final chunks = groundingMetadata['groundingChunks'];
            print('🗺️ GEMINI: YouTube grounding chunks found: ${chunks?.length ?? 0}');
          }
        }
        
        return responseData;
      } else {
        print('❌ GEMINI: YouTube API returned ${response.statusCode}');
        print('   Response: ${jsonEncode(response.data)}');
        return null;
      }
    } on DioException catch (e) {
      print('❌ GEMINI YouTube DIO ERROR: ${e.message}');
      if (e.response != null) {
        print('   Status: ${e.response?.statusCode}');
        print('   Data: ${e.response?.data}');
      }
      return null;
    }
  }

  /// Build prompt for extracting locations from web page content
  /// Optimized for articles, listicles, and guides
  String _buildWebPageLocationExtractionPrompt(String pageContent, {String? pageUrl}) {
    // Extract the page title from the content for context-aware filtering
    String? pageTitle;
    final titleMatch = RegExp(r'Page Title:\s*(.+?)(?:\n|$)').firstMatch(pageContent);
    if (titleMatch != null) {
      pageTitle = titleMatch.group(1)?.trim();
    }
    
    // Extract main heading if different from title
    String? mainHeading;
    final headingMatch = RegExp(r'Main Heading:\s*(.+?)(?:\n|$)').firstMatch(pageContent);
    if (headingMatch != null) {
      mainHeading = headingMatch.group(1)?.trim();
    }
    
    // Determine the article topic for filtering
    final articleTopic = mainHeading ?? pageTitle ?? 'the main article';
    
    return '''
You are an expert at extracting location and place information from web pages.
Your task is to find places that are DIRECTLY RELEVANT to the main article topic.

${pageUrl != null ? 'Source URL: $pageUrl\n' : ''}
${pageTitle != null ? 'Article Title: $pageTitle\n' : ''}
${mainHeading != null && mainHeading != pageTitle ? 'Main Heading: $mainHeading\n' : ''}

=== WEB PAGE CONTENT ===
$pageContent

=== CRITICAL RELEVANCE FILTER ===

**ONLY include locations that are DIRECTLY PART OF "$articleTopic".**

❌ **EXCLUDE these types of mentions:**
- Author bio locations (where the blogger lives, their favorite local stores)
- Grocery stores, supermarkets, or supply stores mentioned for "trip prep" or "packing"
- Generic shopping recommendations (Amazon, Walmart, Costco, etc.)
- Locations from "Related Posts" or "You May Also Like" sections
- Sponsor/advertisement locations
- The author's home city or local recommendations unrelated to the article topic
- Airports UNLESS the article is specifically about traveling to a destination and mentions the airport as part of the itinerary

✅ **INCLUDE these types of locations:**
- Places that are the main subject of the article (e.g., Death Valley attractions for a Death Valley guide)
- Restaurants, hotels, and attractions AT THE DESTINATION being discussed
- Specific stops, viewpoints, or experiences described in the itinerary/guide
- Places with detailed descriptions, reviews, or recommendations in the main content

=== EXTRACTION INSTRUCTIONS ===

1. **Determine the Geographic Focus**: What location/region is this article primarily about?
   - Only extract places IN or NEAR that region
   - If it's a "Death Valley Itinerary", only include Death Valley area locations
   - If it's "Best Restaurants in NYC", only include NYC restaurants

2. **For "Best Of" Lists or Rankings**: Extract all listed items that match the article's topic.

3. **For Each Place Extract**:
   - Name: The exact business/place name
   - Address: Street address if mentioned
   - City: City name (should match the article's geographic focus)
   - Region: State/province if mentioned
   - Type: restaurant/cafe/bar/hotel/attraction/store/park/landmark
   - Description: Brief description if provided (one sentence max)

4. **What to Include**:
   - Restaurants, cafes, bars at the DESTINATION
   - Hotels, resorts where travelers would STAY at the destination
   - Attractions, museums, landmarks at the DESTINATION
   - Parks, viewpoints, hiking trails at the DESTINATION
   - Any venue that is part of the recommended experience

5. **What to EXCLUDE**:
   - The author's local grocery stores (R Ranch, Amazon Fresh, Trader Joe's for "packing")
   - The author's hometown businesses
   - Generic chain stores mentioned for supplies
   - Any location more than 100 miles from the article's main geographic focus
   - Locations only mentioned in passing without recommendation

=== OUTPUT FORMAT ===
Return a JSON array with ONLY relevant locations:

[
  {
    "name": "Place Name",
    "address": "Street address or null",
    "city": "City name",
    "region": "State/Region or null",
    "type": "restaurant/cafe/bar/hotel/attraction/store/park/landmark",
    "description": "Brief description or null"
  }
]

=== IMPORTANT ===
- Quality over quantity - only include places RELEVANT to the article topic
- When in doubt, ask: "Is this place part of the itinerary/guide, or just mentioned for other reasons?"
- Use Google Maps grounding to verify locations and get accurate Place IDs
- If no relevant locations found, return: []
- Return ONLY the JSON array, no other text
''';
  }

  /// Call Gemini API with Google Maps grounding enabled
  Future<Map<String, dynamic>?> _callGeminiWithMapsGrounding(
    String prompt, {
    LatLng? userLocation,
  }) async {
    final endpoint = '$_baseUrl/models/$_defaultModel:generateContent';
    
    // Build the request body with Maps grounding tool
    final requestBody = {
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      // Enable Google Maps grounding tool
      'tools': [
        {
          'googleMaps': {}
        }
      ],
      // Configure tool usage
      'toolConfig': {
        'functionCallingConfig': {
          'mode': 'ANY'
        }
      },
      // Generation config for factual responses
      'generationConfig': {
        'temperature': 0.1,
        'topP': 0.8,
        'topK': 40,
        'maxOutputTokens': 2048,
      }
    };

    // Add user location for better grounding results
    if (userLocation != null) {
      requestBody['toolConfig'] = {
        ...requestBody['toolConfig'] as Map<String, dynamic>,
        'retrievalConfig': {
          'latLng': {
            'latitude': userLocation.latitude,
            'longitude': userLocation.longitude,
          }
        }
      };
    }

    try {
      print('🤖 GEMINI: Calling API with Maps grounding...');
      
      final response = await _dio.post(
        '$endpoint?key=$_apiKey',
        data: requestBody,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200) {
        print('✅ GEMINI: API returned 200 OK');
        
        // Log the actual response for debugging
        final responseData = response.data as Map<String, dynamic>;
        final candidates = responseData['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final candidate = candidates.first as Map<String, dynamic>;
          final content = candidate['content'] as Map<String, dynamic>?;
          final parts = content?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final text = parts.first['text'] as String?;
            if (text != null && text.length > 100) {
              print('📝 GEMINI Response: ${text.substring(0, 100)}...');
            } else if (text != null) {
              print('📝 GEMINI Response: $text');
            }
          }
          
          // Log grounding metadata
          final groundingMetadata = candidate['groundingMetadata'];
          if (groundingMetadata != null) {
            final chunks = groundingMetadata['groundingChunks'];
            print('🗺️ GEMINI: Grounding chunks found: ${chunks?.length ?? 0}');
          } else {
            print('⚠️ GEMINI: No grounding metadata in response');
          }
        }
        
        return responseData;
      } else {
        print('❌ GEMINI: API returned ${response.statusCode}');
        print('   Response: ${jsonEncode(response.data)}');
        return null;
      }
    } on DioException catch (e) {
      print('❌ GEMINI DIO ERROR: ${e.message}');
      if (e.response != null) {
        print('   Status: ${e.response?.statusCode}');
        print('   Data: ${e.response?.data}');
      }
      return null;
    }
  }

  /// Build prompt for URL-based location extraction
  String _buildLocationExtractionPrompt(String url) {
    return '''
Visit and analyze the content at this URL to extract location information: $url

IMPORTANT: You need to access and read the actual web page content, not just look at the URL structure.

For social media posts (Instagram, TikTok, YouTube, Facebook):
- Look at the post caption/description for location mentions
- Check for tagged locations or check-ins
- Look for business names, addresses, or place names in the text
- Check comments if they contain location information

For EACH distinct place, business, or location found, provide:
1. The exact business or place name
2. The full street address if available
3. The city, state/province, and country
4. The type of place (restaurant, cafe, attraction, hotel, store, park, etc.)

If this content mentions multiple places (e.g., a "Top 10" list, multiple tagged locations, or a travel guide), extract information for ALL of them.

If you cannot access the page content or if the page contains no location information, clearly state: "No location information found on this page."

Use Google Maps data to verify locations and provide accurate Place IDs whenever possible.
''';
  }

  /// Build prompt for text-based location extraction
  /// Enhanced prompt with priority system matching Instagram screenshot analysis
  String _buildTextLocationExtractionPrompt(String text) {
    return '''
You are an expert at extracting location and place information from social media captions.
Analyze the following text and extract ALL location and place information.

=== TEXT TO ANALYZE ===
$text

=== EXTRACTION PRIORITY (Follow this order!) ===

**PRIORITY 1 - EXPLICIT LOCATIONS WITH CITY CONTEXT:**
Look for patterns that mention a place WITH its city/location:
- "store in Anaheim" → Extract: name="[store name]", city="Anaheim"
- "opened in San Francisco" → city="San Francisco"
- "located in [City]" → city="[City]"
- "at [Place] in [City]" → Extract both place and city
- "📍 [Place Name]" with city mentioned nearby

CRITICAL: When you find "[Business Name] in [City]", ALWAYS include the city!

**PRIORITY 2 - BUSINESS/PLACE NAMES:**
- Named businesses, restaurants, cafes, stores, attractions
- Names following "at", "visited", "went to", "check out", "just opened"
- Names with location pin emoji 📍
- @handles that are business names (convert them!)

**PRIORITY 3 - HASHTAGS (Use for city context):**
- Extract city names from hashtags: #anaheim → "Anaheim", #orangecounty → "Orange County"
- #losangeles, #la → "Los Angeles"
- #sanfrancisco, #sf → "San Francisco"  
- #newyork, #nyc → "New York"
- Use hashtag cities to provide context for businesses found in Priority 1 & 2
- If a business is found but no city is explicitly stated, check hashtags for the city

=== SOCIAL MEDIA HANDLE CONVERSION ===
Convert @handles to proper business names:
- "@ebisu_life_store" → "Ebisu Life Store"
- "@joes_pizza_nyc" → "Joe's Pizza" (remove _nyc suffix)
- "@cafe.luna.la" → "Cafe Luna" (remove .la suffix)
- Remove location suffixes: _la, _nyc, _sf, .us, .co, etc.
- Replace dots and underscores with spaces
- Apply Title Case

=== OUTPUT FORMAT ===
Return a JSON array. IMPORTANT: Include the city in the response!

[
  {
    "name": "Business or Place Name",
    "address": "Street address if mentioned (or null)",
    "city": "City name from text or hashtags (IMPORTANT - extract this!)",
    "region": "State/region if mentioned (or null)",
    "type": "restaurant/cafe/store/attraction/park/landmark"
  }
]

=== EXAMPLES ===

Example 1 - Caption: "new Japanese store in Anaheim! Ebisu life store just opened #orangecounty #anaheim"
Output:
[{"name": "Ebisu Life Store", "address": null, "city": "Anaheim", "region": "Orange County", "type": "store"}]

Example 2 - Caption: "best coffee ☕ @bluebottle in SF #sanfrancisco"
Output:
[{"name": "Blue Bottle", "address": null, "city": "San Francisco", "region": null, "type": "cafe"}]

Example 3 - Caption: "📍 Hearst Castle in San Simeon, amazing views! #california #roadtrip"
Output:
[{"name": "Hearst Castle", "address": null, "city": "San Simeon", "region": "California", "type": "landmark"}]

=== RULES ===
1. ALWAYS extract city context when available (from "in [City]" or hashtags)
2. Deduplicate - same place mentioned twice = one result
3. Skip generic regions (California, USA) if specific cities exist
4. Convert all @handles to readable business names
5. Return ONLY the JSON array, no other text
6. If no locations found, return: []
''';
  }

  /// Check if text likely contains location information
  Future<bool> hasLocationContext(String text) async {
    // Quick heuristic check for location indicators
    final locationIndicators = [
      RegExp(r'\d+\s+\w+\s+(street|st|ave|avenue|blvd|boulevard|road|rd|way|drive|dr|lane|ln)', caseSensitive: false),
      RegExp(r'\b(restaurant|cafe|hotel|museum|park|store|shop|bar|club)\b', caseSensitive: false),
      RegExp(r'\b(visit|went to|at|located at|near|in)\s+\w+', caseSensitive: false),
      RegExp(r'@\w+', caseSensitive: false), // Social media location tags
    ];

    for (final pattern in locationIndicators) {
      if (pattern.hasMatch(text)) {
        return true;
      }
    }

    return false;
  }

  // ============ VISION/IMAGE ANALYSIS METHODS ============

  /// Extract location names/text from an image using Gemini Vision
  /// 
  /// This uses a two-step approach:
  /// 1. Gemini Vision extracts location names/addresses from the image
  /// 2. The caller uses Places API to verify and get place details
  /// 
  /// [imageBytes] - The raw bytes of the image to analyze
  /// [mimeType] - The MIME type of the image (e.g., 'image/jpeg', 'image/png')
  /// 
  /// Returns a list of extracted location names/descriptions, or empty list if none found.
  Future<List<ExtractedLocationInfo>> extractLocationNamesFromImage(
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
  }) async {
    if (!isConfigured) {
      print('⚠️ GEMINI VISION: API key not configured');
      return [];
    }

    try {
      print('📷 GEMINI VISION: Analyzing image for location text...');
      
      // Convert image to base64
      final base64Image = base64Encode(imageBytes);
      
      // Step 1: Use Vision API WITHOUT Maps grounding (Maps grounding doesn't work with images)
      final response = await _callGeminiVision(
        _buildImageTextExtractionPrompt(),
        base64Image,
        mimeType,
      );
      
      if (response == null) {
        print('⚠️ GEMINI VISION: No response from API');
        return [];
      }

      // Parse the response to extract location names
      final locations = _parseLocationNamesFromResponse(response);
      
      print('✅ GEMINI VISION: Found ${locations.length} location(s) in image');
      for (final loc in locations) {
        print('   📍 ${loc.name} ${loc.address != null ? "(${loc.address})" : ""}');
      }
      
      return locations;
    } catch (e, stackTrace) {
      print('❌ GEMINI VISION ERROR: $e');
      print('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Extract locations from an image file
  Future<List<ExtractedLocationInfo>> extractLocationNamesFromImageFile(
    File imageFile,
  ) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final mimeType = _getMimeTypeFromPath(imageFile.path);
      return extractLocationNamesFromImage(bytes, mimeType: mimeType);
    } catch (e) {
      print('❌ GEMINI VISION: Error reading image file: $e');
      return [];
    }
  }

  /// Get MIME type from file path
  String _getMimeTypeFromPath(String path) {
    final extension = path.toLowerCase().split('.').last;
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  /// Call Gemini Vision API (without Maps grounding - for image analysis)
  Future<Map<String, dynamic>?> _callGeminiVision(
    String prompt,
    String base64Image,
    String mimeType,
  ) async {
    final endpoint = '$_baseUrl/models/$_defaultModel:generateContent';
    
    // Log image size for debugging
    final imageSizeKb = (base64Image.length * 0.75 / 1024).toStringAsFixed(1);
    print('📷 GEMINI VISION: Image size ~${imageSizeKb}KB');
    
    // Build request WITHOUT Maps grounding (Maps grounding doesn't work with inline images)
    final requestBody = {
      'contents': [
        {
          'parts': [
            // Image part first
            {
              'inlineData': {
                'mimeType': mimeType,
                'data': base64Image,
              }
            },
            // Text prompt
            {'text': prompt}
          ]
        }
      ],
      // Generation config - slightly higher temperature for better OCR creativity
      'generationConfig': {
        'temperature': 0.2,  // Slightly higher for better text recognition
        'topP': 0.9,         // More diverse outputs 
        'topK': 50,          // Wider selection
        'maxOutputTokens': 4096,  // More room for multiple locations
      }
    };

    try {
      print('📷 GEMINI VISION: Calling API for image analysis...');
      
      final response = await _dio.post(
        '$endpoint?key=$_apiKey',
        data: requestBody,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200) {
        print('✅ GEMINI VISION: API returned 200 OK');
        
        final responseData = response.data as Map<String, dynamic>;
        final candidates = responseData['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final candidate = candidates.first as Map<String, dynamic>;
          final content = candidate['content'] as Map<String, dynamic>?;
          final parts = content?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final text = parts.first['text'] as String?;
            if (text != null) {
              // Show full response for debugging (up to 1000 chars)
              print('📝 GEMINI VISION Response: ${text.length > 1000 ? text.substring(0, 1000) + "..." : text}');
            }
          }
        }
        
        return responseData;
      } else {
        print('❌ GEMINI VISION: API returned ${response.statusCode}');
        print('   Response: ${jsonEncode(response.data)}');
        return null;
      }
    } on DioException catch (e) {
      print('❌ GEMINI VISION DIO ERROR: ${e.message}');
      if (e.response != null) {
        print('   Status: ${e.response?.statusCode}');
        print('   Data: ${e.response?.data}');
      }
      return null;
    }
  }

  /// Build prompt for extracting location text from images
  String _buildImageTextExtractionPrompt() {
    return '''
You are an expert at OCR (Optical Character Recognition) and location extraction. 
Analyze this screenshot/image and extract ALL location and place information.

=== YOUTUBE VIDEO SCREENSHOTS (HIGHEST PRIORITY) ===
For YouTube video screenshots/thumbnails, follow this strict priority:

**PRIORITY 1 - TEXT OVERLAID ON VIDEO THUMBNAIL (MOST IMPORTANT!):**
- Look for business/restaurant names as large text OVERLAID on the video image
- These are often styled text with the place name (e.g., "PARLOR SAN CLEMENTE", "JOE'S PIZZA")
- This is the MOST important source - extract these names first
- The text is usually in the CENTER of the video thumbnail
- May be styled, have shadows, or be in distinctive fonts

**PRIORITY 2 - Location tags below video:**
- Location names appearing below or near the video player
- Text near map pins or location icons

**PRIORITY 3 - Video title (LOWEST PRIORITY):**
- The video title like "Top 10 Restaurants..."
- ONLY use this if NO specific business names are found in Priority 1 or 2
- NEVER extract broad regions (like "Orange County", "Los Angeles") from titles if specific places exist

=== INSTAGRAM PREVIEW STRUCTURE ===
Instagram preview images typically have THREE sections. Process them in this priority order:

**PRIORITY 1 - MAIN CONTENT (Focus here first!):**
- The large main image or video thumbnail at the top
- Text overlaid on the main image/video (location text, captions burned into video)
- Location pin icons 📍 with place names near the top
- Any signs, storefronts, or business names visible in the main image

**PRIORITY 2 - POST CAPTION (Secondary focus):**
- The caption text below the main image (before hashtags)
- Look for location names, business names, addresses mentioned naturally
- Text like "visited", "at", "went to", "check out" followed by place names
- Lists of places (e.g., "📍 Point Buchon Trail", "📍 Hearst Castle")

**PRIORITY 3 - HASHTAGS (Only if nothing found above):**
- Hashtags at the end of captions (#locationname, #cityname)
- ONLY extract from hashtags if ZERO locations were found in Priority 1 and 2
- Convert hashtag to readable name: #bigsur → "Big Sur", #sanfrancisco → "San Francisco"

**COMPLETELY IGNORE - DO NOT EXTRACT:**
- "More posts from [username]" section at the bottom
- Small thumbnail images in the "More posts from" grid
- Any text from these thumbnail images
- Suggested accounts or "You might also like" sections

=== CRITICAL: READ ALL TEXT IN THE IMAGE ===
Use your OCR capabilities to detect and read ALL visible text, including:
- Text overlaid on video frames (like TikTok/Instagram Reels captions)
- Styled text, animated text captions, or text with effects
- Text on images, memes, or graphics
- Small text, watermarks, and subtitles
- Location tags (usually at top of social media posts with a pin icon 📍)
- Username handles that ARE business names (@businessname)

=== CRITICAL: CONVERT SOCIAL MEDIA HANDLES TO BUSINESS NAMES ===
Social media handles (@username) are often business names! ALWAYS convert them:
- "@oldferrydonut.us" → "Old Ferry Donut"
- "@joes_pizza_nyc" → "Joe's Pizza"
- "@thebluebottlecoffee" → "Blue Bottle Coffee"
- "@matecoffeebar" → "Mate Coffee Bar"
- "@taco.bell.official" → "Taco Bell"
- "@kuyalord_la" → "Kuya Lord" (NOT "Kuyalord La"!)
- "@carlitosgardel" → "Carlitos Gardel"
- "@kissa_cora" → "Kissa Cora"
- "@flowersfinest_" → "Flowers Finest"

Rules for conversion:
1. Remove the @ symbol
2. REMOVE city/location suffixes: _la, _nyc, _sf, _chi, _atl, _mia, _dc, _phx, etc.
3. REMOVE domain suffixes: .us, .co, .official, .shop, etc.
4. Replace remaining dots (.) and underscores (_) with spaces
5. Split camelCase or concatenated words: "kuyalord" → "Kuya Lord", "carlitosgardel" → "Carlitos Gardel"
6. Capitalize each word properly (Title Case)
7. The result should be a human-readable business name

IMPORTANT: When you see "@kuyalord_la (East Hollywood)", the name is "Kuya Lord" NOT "Kuyalord La"!
The "_la" is a location suffix meaning Los Angeles, it is NOT part of the business name!

=== LOOK FOR THESE LOCATION TYPES ===
1. Business names (restaurants, cafes, shops, bars, hotels)
2. Street addresses (even partial - "123 Main St", "on Broadway")
3. City/state/country names
4. Neighborhood names
5. Famous landmarks or tourist attractions
6. Tagged locations from social media (📍 location markers)
7. Signs, storefronts, menus showing business names
8. Text mentioning "at", "visited", "went to", "check out"

=== FILTER OUT GENERIC/NON-SPECIFIC LOCATIONS (CRITICAL!) ===
ALWAYS skip broad regions/counties when specific business names exist:
- ALWAYS Skip: "Orange County", "Los Angeles County", "San Diego County" (counties are too broad)
- ALWAYS Skip: "California", "USA", "Central Coast", "Southern California", "SoCal", "NorCal"
- ALWAYS Skip: General city names when a specific business in that city is visible
- Keep: "Parlor San Clemente" (specific restaurant), NOT "Orange County"
- Keep: "Carmel-by-the-Sea", "San Simeon", "Big Sur" (specific small cities/areas)
- Keep: "Hearst Castle", "Bixby Bridge", "Point Lobos" (specific landmarks)

IMPORTANT: If you see "PARLOR SAN CLEMENTE" on a video and "Orange County" in the title:
- Return "Parlor" with city "San Clemente" (the specific restaurant)
- DO NOT return "Orange County" (the broad region)

If a video shows a specific restaurant/business name, ONLY return that business, not the region!

=== SOCIAL MEDIA SPECIFIC ===
For TikTok/Instagram/Facebook screenshots:
- ALWAYS read text burned into the video frame (center/bottom text overlays)
- Check for location pin icons 📍 followed by place names
- CONVERT @handles next to addresses into proper business names
- Look at creator captions below the video
- Read any visible comments mentioning places
- Business watermarks or logos visible in video

=== OUTPUT FORMAT ===
Return a JSON array with this exact structure:
[
  {
    "name": "Business or Place Name (NOT the @handle, use converted name)",
    "address": "Street address if visible (or null)",
    "city": "City name if visible (or null)", 
    "type": "restaurant/cafe/store/attraction/park/trail/landmark/region"
  }
]

=== EXAMPLES ===
**YOUTUBE EXAMPLE (IMPORTANT!):**
If you see a YouTube video with:
- Title: "Top 10 Orange County Restaurants I've Tried in 2025"  
- Overlaid text on thumbnail: "PARLOR SAN CLEMENTE" (with a pizza image)
Return ONLY the specific restaurant, NOT "Orange County":
[
  {"name": "Parlor", "address": null, "city": "San Clemente", "type": "restaurant"}
]
DO NOT return: {"name": "Orange County", ...} - this is too broad!

If you see: "@oldferrydonut.us - 6982 Beach Blvd"
Return: {"name": "Old Ferry Donut", "address": "6982 Beach Blvd", "city": null, "type": "restaurant"}

If you see: "📍 @matecoffeebar"
Return: {"name": "Mate Coffee Bar", "address": null, "city": null, "type": "cafe"}

If you see a list like:
"📍 Point Buchon Trail in Los Osos
📍 Hearst Castle in San Simeon
📍 Bixby Bridge
#california #roadtrip"
Return only the specific locations, NOT "California":
[
  {"name": "Point Buchon Trail", "address": null, "city": "Los Osos", "type": "trail"},
  {"name": "Hearst Castle", "address": null, "city": "San Simeon", "type": "landmark"},
  {"name": "Bixby Bridge", "address": null, "city": null, "type": "landmark"}
]

=== RULES ===
- ALWAYS convert @handles to proper business names
- Extract EVERY distinct location mentioned (from Priority 1 and 2 sections)
- Include partial information - even just a business name is useful
- For video text overlays, read character by character if needed
- Prioritize text that appears to name specific places
- SKIP generic regions/states/countries/counties if specific locations exist
- For YouTube: text OVERLAID on the video thumbnail is MORE important than the video title
- For YouTube: NEVER return just a county/region name if a business name is visible on the thumbnail
- IGNORE "More posts from" section and its thumbnails entirely
- Return ONLY the JSON array, no other text
- If absolutely no locations found, return: []
''';
  }

  /// Parse location names from Gemini Vision response
  List<ExtractedLocationInfo> _parseLocationNamesFromResponse(Map<String, dynamic> response) {
    final results = <ExtractedLocationInfo>[];
    
    try {
      final candidates = response['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return results;
      
      final candidate = candidates.first as Map<String, dynamic>;
      final content = candidate['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) return results;
      
      final text = parts.first['text'] as String?;
      if (text == null || text.isEmpty) return results;
      
      // Try to parse as JSON
      String jsonText = text.trim();
      
      // Handle markdown code blocks
      if (jsonText.startsWith('```json')) {
        jsonText = jsonText.substring(7);
      } else if (jsonText.startsWith('```')) {
        jsonText = jsonText.substring(3);
      }
      if (jsonText.endsWith('```')) {
        jsonText = jsonText.substring(0, jsonText.length - 3);
      }
      jsonText = jsonText.trim();
      
      // Check for "no locations" responses
      if (jsonText == '[]' || 
          jsonText.toLowerCase().contains('no location') ||
          jsonText.toLowerCase().contains('no places')) {
        print('📷 GEMINI VISION: No locations found in image');
        return results;
      }
      
      // Parse JSON array
      final parsed = jsonDecode(jsonText);
      if (parsed is List) {
        for (final item in parsed) {
          if (item is Map<String, dynamic>) {
            String? name = item['name'] as String?;
            if (name != null && name.isNotEmpty) {
              // Clean up the name - convert handles to business names if needed
              name = _convertHandleToBusinessName(name);
              
              results.add(ExtractedLocationInfo(
                name: name,
                address: item['address'] as String?,
                city: item['city'] as String?,
                type: item['type'] as String?,
              ));
            }
          }
        }
      }
    } catch (e) {
      print('⚠️ GEMINI VISION: Error parsing response: $e');
      // Try fallback parsing for non-JSON responses
      _tryFallbackParsing(response, results);
    }
    
    return results;
  }

  /// Convert a social media handle to a proper business name
  /// e.g., "@oldferrydonut.us" → "Old Ferry Donut"
  /// e.g., "@kuyalord_la" → "Kuya Lord"
  String _convertHandleToBusinessName(String name) {
    String result = name.trim();
    
    // If it doesn't look like a handle or concatenated name, return as-is
    // But still try to improve concatenated words like "Kuyalord La"
    if (!result.startsWith('@') && !result.contains('.') && !result.contains('_')) {
      // Check if it looks like a concatenated name followed by a city code
      // e.g., "Kuyalord La" -> should become "Kuya Lord"
      final cityCodePattern = RegExp(r'\s+(la|nyc|sf|chi|dc|atl|mia|dal|hou|phx)$', caseSensitive: false);
      if (cityCodePattern.hasMatch(result)) {
        result = result.replaceFirst(cityCodePattern, '');
        // Try to split concatenated name
        result = _splitConcatenatedWords(result);
        print('📝 HANDLE CONVERSION: "$name" → "$result" (removed trailing city code)');
        return result;
      }
      return result;
    }
    
    // Remove @ symbol
    if (result.startsWith('@')) {
      result = result.substring(1);
    }
    
    // Remove common domain/location suffixes (including underscore versions)
    final suffixesToRemove = [
      // Underscore versions first (more specific)
      '_official', '_us', '_uk', '_ca', '_au',
      '_nyc', '_la', '_sf', '_chi', '_dc', '_atl', '_mia', '_dal', '_hou', '_phx',
      '_shop', '_store', '_cafe', '_restaurant', '_bar', '_food', '_eats',
      // Dot versions
      '.us', '.co', '.uk', '.ca', '.au', '.de', '.fr', '.es', '.it', '.jp',
      '.nyc', '.la', '.sf', '.chi', '.dc', '.atl', '.mia', '.dal', '.hou', '.phx',
      '.official', '.shop', '.store', '.cafe', '.restaurant', '.bar', '.food',
      '.eats', '.kitchen', '.bakery', '.coffee', '.pizza', '.tacos', '.burgers',
    ];
    
    for (final suffix in suffixesToRemove) {
      if (result.toLowerCase().endsWith(suffix)) {
        result = result.substring(0, result.length - suffix.length);
        break; // Only remove one suffix
      }
    }
    
    // Replace dots and underscores with spaces
    result = result.replaceAll('.', ' ').replaceAll('_', ' ');
    
    // Remove multiple consecutive spaces
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    // Try to split concatenated words for each word (e.g., "kuyalord" -> "Kuya Lord")
    result = result.split(' ').map((word) {
      return _splitConcatenatedWords(word);
    }).join(' ');
    
    // Convert to Title Case
    result = result.split(' ').map((word) {
      if (word.isEmpty) return word;
      // Keep short words like "the", "of", "and" lowercase unless first word
      final lowerWords = ['the', 'of', 'and', 'a', 'an', 'in', 'on', 'at', 'to', 'for'];
      if (lowerWords.contains(word.toLowerCase())) {
        return word.toLowerCase();
      }
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
    
    // Capitalize first letter always
    if (result.isNotEmpty) {
      result = result[0].toUpperCase() + result.substring(1);
    }
    
    // Handle special cases - remove "the" at start if it makes sense
    if (result.toLowerCase().startsWith('the ') && result.length > 5) {
      // Keep "the" for now, let Places API handle it
    }
    
    print('📝 HANDLE CONVERSION: "$name" → "$result"');
    
    return result;
  }
  
  /// Try to split concatenated words like "kuyalord" into "Kuya Lord"
  /// Uses common word patterns and dictionary checks
  String _splitConcatenatedWords(String word) {
    if (word.length < 4) return word;
    
    // Common business name prefixes/suffixes to look for
    final commonPrefixes = [
      'kuya', 'tita', 'tito', 'chef', 'mama', 'papa', 'uncle', 'aunt',
      'casa', 'cafe', 'chez', 'el', 'la', 'los', 'las', 'don', 'dona',
      'old', 'new', 'big', 'little', 'golden', 'silver', 'blue', 'red',
      'happy', 'lucky', 'good', 'best', 'first', 'royal', 'king', 'queen',
    ];
    
    final commonSuffixes = [
      'lord', 'king', 'queen', 'house', 'place', 'spot', 'kitchen', 'grill',
      'cafe', 'bar', 'pub', 'inn', 'deli', 'bistro', 'eatery', 'joint',
      'gardel', 'bella', 'bello', 'grande', 'lindo', 'rico', 'bueno',
    ];
    
    final wordLower = word.toLowerCase();
    
    // Try to find known prefix + suffix combinations
    for (final prefix in commonPrefixes) {
      if (wordLower.startsWith(prefix) && wordLower.length > prefix.length) {
        final remainder = wordLower.substring(prefix.length);
        // Check if remainder is a known suffix or looks like a word
        for (final suffix in commonSuffixes) {
          if (remainder == suffix) {
            return '${prefix[0].toUpperCase()}${prefix.substring(1)} ${suffix[0].toUpperCase()}${suffix.substring(1)}';
          }
        }
        // If remainder is at least 3 chars, try splitting
        if (remainder.length >= 3) {
          return '${prefix[0].toUpperCase()}${prefix.substring(1)} ${remainder[0].toUpperCase()}${remainder.substring(1)}';
        }
      }
    }
    
    // Try suffix matching from the end
    for (final suffix in commonSuffixes) {
      if (wordLower.endsWith(suffix) && wordLower.length > suffix.length) {
        final prefix = wordLower.substring(0, wordLower.length - suffix.length);
        if (prefix.length >= 3) {
          return '${prefix[0].toUpperCase()}${prefix.substring(1)} ${suffix[0].toUpperCase()}${suffix.substring(1)}';
        }
      }
    }
    
    // Handle specific known business names that we've seen
    final knownMappings = {
      'kuyalord': 'Kuya Lord',
      'carlitosgardel': 'Carlitos Gardel',
      'kissacora': 'Kissa Cora',
      'flowersfinest': 'Flowers Finest',
      'leannalinswonderland': 'Leanna Lins Wonderland',
      'hongkong': 'Hong Kong',
    };
    
    if (knownMappings.containsKey(wordLower)) {
      return knownMappings[wordLower]!;
    }
    
    return word;
  }

  /// Fallback parsing for non-JSON responses
  void _tryFallbackParsing(Map<String, dynamic> response, List<ExtractedLocationInfo> results) {
    try {
      final candidates = response['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return;
      
      final candidate = candidates.first as Map<String, dynamic>;
      final content = candidate['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) return;
      
      final text = parts.first['text'] as String?;
      if (text == null || text.isEmpty) return;
      
      // Look for patterns like "Name: xxx" or "- xxx" in the response
      final lines = text.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        
        // Look for name patterns
        final nameMatch = RegExp(r'(?:name|place|business|restaurant|location):\s*(.+)', caseSensitive: false).firstMatch(trimmed);
        if (nameMatch != null) {
          String? name = nameMatch.group(1)?.trim();
          if (name != null && name.isNotEmpty && name.length < 100) {
            name = _convertHandleToBusinessName(name);
            results.add(ExtractedLocationInfo(name: name));
          }
        }
        // Look for bullet points with place-like names
        else if (trimmed.startsWith('-') || trimmed.startsWith('•') || trimmed.startsWith('*')) {
          String name = trimmed.substring(1).trim();
          // Basic heuristic: if it looks like a place name (capitalized, reasonable length)
          if (name.isNotEmpty && name.length < 100 && name[0] == name[0].toUpperCase()) {
            // Skip common non-place words
            if (!RegExp(r'^(the|a|an|no|none|null|n\/a)$', caseSensitive: false).hasMatch(name)) {
              name = _convertHandleToBusinessName(name);
              results.add(ExtractedLocationInfo(name: name));
            }
          }
        }
      }
    } catch (e) {
      print('⚠️ GEMINI VISION: Fallback parsing also failed: $e');
    }
  }

  // ============ END VISION/IMAGE ANALYSIS METHODS ============
}

/// Simple class to hold extracted location info from images
class ExtractedLocationInfo {
  final String name;
  final String? address;
  final String? city;
  final String? type;

  ExtractedLocationInfo({
    required this.name,
    this.address,
    this.city,
    this.type,
  });

  @override
  String toString() => 'ExtractedLocationInfo(name: $name, address: $address, city: $city, type: $type)';
}
