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

  /// Look up an Instagram handle to find the actual business name
  /// 
  /// This uses Google Search grounding to look up what business an Instagram
  /// handle refers to. Useful for handles that are abbreviations or not obvious.
  /// 
  /// For example: "@sofaseattle" → "Social Fabric Cafe & Market"
  ///              "@rockcreek206" → "RockCreek Seafood & Spirits"
  /// 
  /// [handle] - The Instagram handle (with or without @)
  /// [city] - Optional city for disambiguation
  /// 
  /// Returns the actual business name, or null if not found
  Future<String?> lookupInstagramHandle(
    String handle, {
    String? city,
  }) async {
    if (!isConfigured) {
      print('⚠️ GEMINI HANDLE LOOKUP: API key not configured');
      return null;
    }

    try {
      // Clean up the handle
      String cleanHandle = handle.trim();
      if (cleanHandle.startsWith('@')) {
        cleanHandle = cleanHandle.substring(1);
      }
      
      print('🔎 GEMINI HANDLE LOOKUP: Looking up @$cleanHandle${city != null ? " in $city" : ""}...');
      
      // Build search query
      final searchQuery = city != null 
          ? '@$cleanHandle $city instagram business'
          : '@$cleanHandle instagram business';
      
      final prompt = '''
What business does the Instagram account "@$cleanHandle" belong to?
${city != null ? 'Location: $city' : ''}

CRITICAL INSTRUCTIONS:
1. Search for "@$cleanHandle instagram" to find the actual business
2. Look for the OFFICIAL business name, not what the handle literally spells
3. Many handles are abbreviations: "sofa" = "SOcial FAbric", "kwc" = "Know Where Coffee"
4. The handle "@sofaseattle" is "Social Fabric Cafe & Market" (SOFA = SOcial FAbric), NOT a furniture store!

YOUR RESPONSE MUST BE:
- ONLY the business name (e.g., "Social Fabric Cafe & Market")
- NO explanations, NO sentences, NO punctuation except what's in the name
- If unknown, respond with just: UNKNOWN

EXAMPLES OF CORRECT RESPONSES:
- Social Fabric Cafe & Market
- RockCreek Seafood & Spirits
- Nutty Squirrel Gelato
- UNKNOWN

WRONG (do NOT do this):
- "The business is Social Fabric Cafe"
- "@sofaseattle refers to Couch Seattle"
- "Based on my search, it's..."
''';

      // Use Gemini with Google Search grounding to look up the handle
      final response = await _callGeminiWithSearchGrounding(prompt);
      
      if (response == null) {
        print('⚠️ GEMINI HANDLE LOOKUP: No response from API');
        return null;
      }
      
      // Extract the business name from the response
      final businessName = _extractBusinessNameFromResponse(response);
      
      if (businessName != null && businessName.isNotEmpty && businessName != 'UNKNOWN') {
        print('✅ GEMINI HANDLE LOOKUP: @$cleanHandle → "$businessName"');
        return businessName;
      } else {
        print('⚠️ GEMINI HANDLE LOOKUP: Could not determine business for @$cleanHandle');
        return null;
      }
    } catch (e) {
      print('❌ GEMINI HANDLE LOOKUP ERROR: $e');
      return null;
    }
  }

  /// Look up a specific place by context description
  /// 
  /// This uses Google Search grounding to find the actual name of a place
  /// when we only have a description (e.g., "Toy Story themed restaurant at Hollywood Studios")
  /// 
  /// [contextDescription] - The description to search for
  /// [regionContext] - Optional region for disambiguation
  /// 
  /// Returns the actual place name, or null if not found
  Future<String?> lookupPlaceByContext(
    String contextDescription, {
    String? regionContext,
  }) async {
    if (!isConfigured) {
      print('⚠️ GEMINI CONTEXT LOOKUP: API key not configured');
      return null;
    }

    try {
      print('🔎 GEMINI CONTEXT LOOKUP: Searching for "$contextDescription"${regionContext != null ? " in $regionContext" : ""}...');
      
      final searchContext = regionContext != null 
          ? '$contextDescription $regionContext'
          : contextDescription;
      
      final prompt = '''
What is the EXACT NAME of this place: "$searchContext"?

Search online to find the specific establishment being described.

EXAMPLES:
- "Toy Story themed restaurant at Hollywood Studios Florida" → "Roundup Rodeo BBQ"
- "Harry Potter restaurant at Universal Studios" → "Three Broomsticks"
- "best coffee shop at Seattle airport" → "Starbucks Reserve"

YOUR RESPONSE MUST BE:
- ONLY the official business/place name (e.g., "Roundup Rodeo BBQ")
- NO explanations, NO sentences
- If you cannot find the specific place, respond with: UNKNOWN

WRONG (do NOT do this):
- "The restaurant is called Roundup Rodeo BBQ"
- "Based on my search..."
- "I believe it's..."
''';

      final response = await _callGeminiWithSearchGrounding(prompt);
      
      if (response == null) {
        print('⚠️ GEMINI CONTEXT LOOKUP: No response from API');
        return null;
      }
      
      final placeName = _extractBusinessNameFromResponse(response);
      
      if (placeName != null && placeName.isNotEmpty && placeName != 'UNKNOWN') {
        print('✅ GEMINI CONTEXT LOOKUP: "$contextDescription" → "$placeName"');
        return placeName;
      } else {
        print('⚠️ GEMINI CONTEXT LOOKUP: Could not determine place for "$contextDescription"');
        return null;
      }
    } catch (e) {
      print('❌ GEMINI CONTEXT LOOKUP ERROR: $e');
      return null;
    }
  }

  /// Call Gemini API with Google Search grounding (for web lookups)
  Future<Map<String, dynamic>?> _callGeminiWithSearchGrounding(String prompt) async {
    final endpoint = '$_baseUrl/models/$_defaultModel:generateContent';
    
    // Build request with Google Search grounding
    final requestBody = {
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'tools': [
        {
          'googleSearch': {} // Enable Google Search grounding
        }
      ],
      'generationConfig': {
        'temperature': 0.1, // Low temperature for factual lookups
        'topP': 0.8,
        'topK': 40,
        'maxOutputTokens': 256, // Short response expected
      }
    };

    try {
      final response = await _dio.post(
        '$endpoint?key=$_apiKey',
        data: requestBody,
        options: Options(
          headers: {'Content-Type': 'application/json'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      } else {
        print('❌ GEMINI SEARCH: API returned ${response.statusCode}');
        print('   Response: ${jsonEncode(response.data)}');
        return null;
      }
    } on DioException catch (e) {
      print('❌ GEMINI SEARCH DIO ERROR: ${e.message}');
      return null;
    }
  }

  /// Extract business name from Gemini response
  /// Handles various response formats including sentences and markdown
  String? _extractBusinessNameFromResponse(Map<String, dynamic> response) {
    try {
      final candidates = response['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return null;
      
      final candidate = candidates.first as Map<String, dynamic>;
      final content = candidate['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) return null;
      
      final text = parts.first['text'] as String?;
      if (text == null || text.isEmpty) return null;
      
      String businessName = text.trim();
      
      // Strategy 1: Extract from markdown bold **Business Name**
      final boldMatch = RegExp(r'\*\*([^*]+)\*\*').firstMatch(businessName);
      if (boldMatch != null) {
        businessName = boldMatch.group(1)!.trim();
        print('📝 HANDLE PARSE: Extracted from markdown bold: "$businessName"');
      } 
      // Strategy 2: Extract after "refers to" or "is called" or "is"
      else if (businessName.toLowerCase().contains('refers to')) {
        final match = RegExp("refers to\\s+['\"]?([^'\".]+)['\"]?", caseSensitive: false).firstMatch(businessName);
        if (match != null) {
          businessName = match.group(1)!.trim();
          print('📝 HANDLE PARSE: Extracted after "refers to": "$businessName"');
        }
      }
      // Strategy 3: If it's a full sentence, try to extract the business name
      else if (businessName.contains('.') || businessName.toLowerCase().startsWith('based on') || 
               businessName.toLowerCase().startsWith('the ')) {
        // Try to find a capitalized phrase that looks like a business name
        final businessMatch = RegExp("['\"]([A-Z][^'\"]+)['\"]").firstMatch(businessName);
        if (businessMatch != null) {
          businessName = businessMatch.group(1)!.trim();
          print('📝 HANDLE PARSE: Extracted quoted name: "$businessName"');
        } else {
          // Take first line and clean it
          businessName = businessName.split('\n').first.split('.').first.trim();
        }
      }
      
      // Clean up the response
      businessName = businessName.trim();
      
      // Remove surrounding quotes if present
      if ((businessName.startsWith('"') && businessName.endsWith('"')) ||
          (businessName.startsWith("'") && businessName.endsWith("'"))) {
        businessName = businessName.substring(1, businessName.length - 1);
      }
      
      // Remove @ handles that might be in the response
      businessName = businessName.replaceAll(RegExp(r'@\w+'), '').trim();
      
      // Remove common prefixes that indicate it's not just a name
      final badPrefixes = ['based on', 'the business', 'it is', 'this is', 'according to'];
      for (final prefix in badPrefixes) {
        if (businessName.toLowerCase().startsWith(prefix)) {
          businessName = businessName.substring(prefix.length).trim();
        }
      }
      
      // Skip if it looks invalid
      final lowerName = businessName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (lowerName == 'unknown' || lowerName.isEmpty || businessName.length > 100) {
        return null;
      }
      
      return businessName;
    } catch (e) {
      print('⚠️ GEMINI: Error extracting business name: $e');
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

**PRIORITY 3 - HASHTAGS (ONLY for context clues, NOT as locations!):**
- DO NOT extract place names from hashtags as locations to return
- Hashtags like #rurukamakura, #cafelife, #foodie should NOT become location results
- ONLY use hashtags to extract CITY/REGION context for locations found in Priority 1 & 2:
  - #anaheim → set city to "Anaheim" for businesses found above
  - #losangeles, #la → set city to "Los Angeles"
  - #sanfrancisco, #sf → set city to "San Francisco"
  - #newyork, #nyc → set city to "New York"
  - #japan, #tokyo, #kamakura → set region_context appropriately
- If a business is found but no city is explicitly stated, check hashtags for the city
- NEVER return a hashtag itself as a location name (e.g., don't return "Ruru Kamakura" just because you see #rurukamakura)

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
7. NEVER return a hashtag as a location - hashtags are ONLY for context (city/region)
8. If you only see hashtags and no actual place names, return: []
9. NEVER HALLUCINATE or INFER cities - only extract what is EXPLICITLY in the text
10. DO NOT expand #OrangeCounty into Anaheim, Fullerton, Santa Ana, etc. - only use for context
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

  /// Analyze MULTIPLE images together to extract locations
  /// 
  /// This is the preferred method when you have multiple screenshots of the same content
  /// (e.g., Instagram video screenshot + caption screenshot). It combines context from
  /// all images to better understand what location is being featured.
  /// 
  /// **Three-Step Process:**
  /// 1. Analyze ALL images together to understand combined context
  /// 2. Use Google Search grounding to find the actual place name (when name isn't explicit)
  /// 3. Return verified location information
  /// 
  /// [images] - List of image data (bytes and mimeType)
  /// 
  /// Returns a list of extracted locations with the combined region context
  Future<({List<ExtractedLocationInfo> locations, String? regionContext})> extractLocationsFromMultipleImages(
    List<({Uint8List bytes, String mimeType})> images,
  ) async {
    if (!isConfigured) {
      print('⚠️ GEMINI MULTI-IMAGE: API key not configured');
      return (locations: <ExtractedLocationInfo>[], regionContext: null);
    }

    if (images.isEmpty) {
      print('⚠️ GEMINI MULTI-IMAGE: No images provided');
      return (locations: <ExtractedLocationInfo>[], regionContext: null);
    }

    // If only one image, use the standard single-image method
    if (images.length == 1) {
      print('📷 GEMINI MULTI-IMAGE: Single image, using standard extraction');
      final locations = await extractLocationNamesFromImage(
        images.first.bytes,
        mimeType: images.first.mimeType,
      );
      final regionContext = locations.isNotEmpty ? locations.first.regionContext : null;
      return (locations: locations, regionContext: regionContext);
    }

    try {
      print('📷 GEMINI MULTI-IMAGE: Analyzing ${images.length} images together...');
      
      // ========== STEP 1: COMBINED CONTEXT ANALYSIS ==========
      // Analyze all images together to get a unified understanding
      final combinedContext = await _analyzeMultipleImagesContext(images);
      
      if (combinedContext == null) {
        print('⚠️ GEMINI MULTI-IMAGE: Could not analyze combined context, falling back to individual analysis');
        // Fallback: analyze each image separately and merge
        return _fallbackIndividualAnalysis(images);
      }
      
      print('✅ GEMINI MULTI-IMAGE: Combined context analyzed');
      print('   📋 Content Type: ${combinedContext.contentType}');
      print('   🎯 Purpose: ${combinedContext.purpose}');
      print('   🌍 Geographic Focus: ${combinedContext.geographicFocus ?? "Not specified"}');
      print('   🔍 Location Types: ${combinedContext.locationTypesToFind.join(", ")}');
      if (combinedContext.criteria.isNotEmpty) {
        print('   📌 Criteria: ${combinedContext.criteria.join(", ")}');
      }
      if (combinedContext.contextClues.isNotEmpty) {
        print('   💡 Context Clues: ${combinedContext.contextClues.join("; ")}');
      }
      if (combinedContext.contentCreatorHandle != null) {
        print('   👤 Content Creator: @${combinedContext.contentCreatorHandle}');
      }
      if (combinedContext.mentionedPlaceNames.isNotEmpty) {
        print('   🏷️ Mentioned Place Names: ${combinedContext.mentionedPlaceNames.join(", ")}');
      }
      if (combinedContext.searchQuerySuggestion != null) {
        print('   🔍 Search Query Suggestion: ${combinedContext.searchQuerySuggestion}');
      }
      if (combinedContext.businessHandles.isNotEmpty) {
        print('   🏪 Business Handles Found: ${combinedContext.businessHandles.map((h) => "@$h").join(", ")}');
      }
      if (combinedContext.extractedText != null && combinedContext.extractedText!.isNotEmpty) {
        print('   ═══════════════════════════════════════════════════════════');
        print('   📝 FULL EXTRACTED TEXT FROM ALL IMAGES:');
        print('   ───────────────────────────────────────────────────────────');
        // Print the full text, line by line for readability
        final lines = combinedContext.extractedText!.split('\n');
        for (final line in lines) {
          if (line.trim().isNotEmpty) {
            print('      $line');
          }
        }
        print('   ═══════════════════════════════════════════════════════════');
      }
      
      // ========== CHECK FOR MULTI-LOCATION CONTENT ==========
      // Detect if this content contains multiple locations (itineraries, guides, lists)
      // If so, skip Step 2 (single location search) and go directly to Step 3
      final isMultiLocation = _isMultiLocationContent(combinedContext);
      
      if (isMultiLocation) {
        print('📋 GEMINI MULTI-IMAGE: Detected MULTI-LOCATION content, skipping single search (Step 2)');
        print('   → Going directly to multi-location extraction (Step 3)');
      } else {
        // ========== STEP 2: GOOGLE SEARCH FOR ACTUAL NAME ==========
        // If the extracted text has context clues but no explicit place name,
        // use Google Search grounding to find the actual location
        final searchResult = await _searchForActualLocationName(combinedContext);
        
        if (searchResult != null) {
          print('✅ GEMINI MULTI-IMAGE: Google Search found: "${searchResult.name}"');
          return (
            locations: [searchResult],
            regionContext: combinedContext.geographicFocus,
          );
        }
      }
      
      // ========== STEP 3: EXTRACT FROM COMBINED CONTEXT ==========
      // Extract all locations from the combined context (handles both single and multi-location content)
      final locations = await _extractLocationsFromCombinedContext(images, combinedContext);
      
      print('✅ GEMINI MULTI-IMAGE: Extraction complete - found ${locations.length} location(s)');
      for (final loc in locations) {
        print('   📍 ${loc.name} ${loc.city != null ? "(${loc.city})" : ""}');
      }
      
      return (locations: locations, regionContext: combinedContext.geographicFocus);
    } catch (e, stackTrace) {
      print('❌ GEMINI MULTI-IMAGE ERROR: $e');
      print('Stack trace: $stackTrace');
      return (locations: <ExtractedLocationInfo>[], regionContext: null);
    }
  }

  /// Analyze multiple images together to get combined context
  Future<ContentContext?> _analyzeMultipleImagesContext(
    List<({Uint8List bytes, String mimeType})> images,
  ) async {
    try {
      print('🔍 GEMINI MULTI-IMAGE STEP 1: Analyzing combined context from ${images.length} images...');
      
      final response = await _callGeminiVisionMultiImage(
        _buildMultiImageContextAnalysisPrompt(images.length),
        images,
      );
      
      if (response == null) {
        print('⚠️ GEMINI MULTI-IMAGE STEP 1: No response from API');
        return null;
      }
      
      return _parseContextResponse(response);
    } catch (e, stackTrace) {
      print('❌ GEMINI MULTI-IMAGE STEP 1 ERROR: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Detect if content contains multiple locations (itineraries, guides, lists, etc.)
  /// Returns true if we should skip single-location search and extract all locations
  bool _isMultiLocationContent(ContentContext context) {
    final purposeLower = context.purpose.toLowerCase();
    final extractedTextLower = context.extractedText?.toLowerCase() ?? '';
    final extractedText = context.extractedText ?? '';
    
    // Check 1: Purpose indicates multiple locations
    final multiLocationPurposeKeywords = [
      'itinerary',
      'guide',
      'list',
      'top ',
      'best ',
      'roundup',
      'recommendations',
      'recommending', // Added: verb form (e.g., "Recommending unique speakeasies")
      'places to',
      'things to do',
      'must visit',
      'must-visit',
      'bucket list',
      'travel guide',
      'food guide',
      'restaurant guide',
      'where to eat',
      'where to go',
      'spots in',
      'spots to',
      'unique ', // Added: often used in multi-location posts like "unique speakeasies"
    ];
    
    for (final keyword in multiLocationPurposeKeywords) {
      if (purposeLower.contains(keyword)) {
        print('   🔍 Multi-location detected: purpose contains "$keyword"');
        return true;
      }
    }
    
    // Check 2: Multiple different location types (3+ suggests a varied list)
    if (context.locationTypesToFind.length >= 3) {
      print('   🔍 Multi-location detected: ${context.locationTypesToFind.length} different location types');
      return true;
    }
    
    // Check 3: Multiple business handles (2+ strongly indicates multi-location content)
    if (context.businessHandles.length >= 2) {
      print('   🔍 Multi-location detected: ${context.businessHandles.length} business handles found');
      return true;
    }
    
    // Check 4: Multiple address patterns in text (📍 emoji or explicit addresses)
    final addressPinCount = '📍'.allMatches(extractedText).length;
    if (addressPinCount >= 2) {
      print('   🔍 Multi-location detected: $addressPinCount address pin emojis found');
      return true;
    }
    
    // Also check for multiple street address patterns (e.g., "123 Main St")
    final addressPattern = RegExp(r'\d+\s+[A-Za-z]+\s+(St|Street|Ave|Avenue|Blvd|Boulevard|Dr|Drive|Rd|Road|Way|Ln|Lane|Ct|Court)\b', caseSensitive: false);
    final addressMatches = addressPattern.allMatches(extractedText).length;
    if (addressMatches >= 2) {
      print('   🔍 Multi-location detected: $addressMatches street addresses found in text');
      return true;
    }
    
    // Check 5: Extracted text contains day-by-day or numbered patterns
    final dayPatterns = [
      RegExp(r'day\s*[1-9]', caseSensitive: false),
      RegExp(r'day\s*one|day\s*two|day\s*three', caseSensitive: false),
      RegExp(r'stop\s*[1-9]', caseSensitive: false),
      RegExp(r'#[1-9]\s*[:-]', caseSensitive: false),
      RegExp(r'\b[1-9]\.\s+[A-Z]', caseSensitive: false), // "1. Restaurant Name"
      RegExp(r'\b[1-9]\.\)\s*@', caseSensitive: false), // "1.) @handle" format
      RegExp(r'\b[1-9]\)\s*@', caseSensitive: false), // "1) @handle" format
      RegExp(r'\b[1-9]\.\)\s*[A-Z]', caseSensitive: false), // "1.) Name" format
    ];
    
    int dayMatches = 0;
    for (final pattern in dayPatterns) {
      if (pattern.hasMatch(extractedText)) {
        dayMatches++;
      }
    }
    
    if (dayMatches >= 1) {
      print('   🔍 Multi-location detected: found day/numbered patterns in text');
      return true;
    }
    
    // Check 6: Multiple meal mentions (breakfast, lunch, dinner pattern)
    final mealKeywords = ['breakfast', 'lunch', 'dinner', 'brunch'];
    int mealCount = 0;
    for (final meal in mealKeywords) {
      if (extractedTextLower.contains(meal)) {
        mealCount++;
      }
    }
    
    if (mealCount >= 2) {
      print('   🔍 Multi-location detected: multiple meal mentions ($mealCount)');
      return true;
    }
    
    // Check 7: Multiple "visit" or "check out" phrases
    final visitPattern = RegExp(r'visit\s+(?:the\s+)?[A-Z]|check\s+out\s+(?:the\s+)?[A-Z]', caseSensitive: false);
    final visitMatches = visitPattern.allMatches(extractedText).length;
    
    if (visitMatches >= 2) {
      print('   🔍 Multi-location detected: multiple "visit/check out" mentions ($visitMatches)');
      return true;
    }
    
    return false;
  }

  /// Build prompt for analyzing multiple images together
  String _buildMultiImageContextAnalysisPrompt(int imageCount) {
    return '''
You are an expert content analyst. You are given $imageCount screenshots/images that are ALL from the SAME piece of content (e.g., different frames of the same Instagram post or video).

=== YOUR TASK ===
Analyze ALL $imageCount images TOGETHER as a single piece of content. Combine information from all images to understand:

1. What TYPE of content is this? (social media post, travel blog, list article, etc.)
2. What is the PURPOSE/THEME? (e.g., "featuring a unique bookstore", "recommending restaurants")
3. What GEOGRAPHIC REGION is this focused on? (city, state, country, area)
4. What TYPES of locations are being featured? (restaurants, cafes, bookstores, libraries, etc.)
5. Any CRITERIA or filters mentioned? (hidden gem, best of, unique, etc.)
6. What should we EXCLUDE? (unrelated mentions, UI text, etc.)
7. Extract ALL visible TEXT from ALL images that might help identify the location

=== CRITICAL: IDENTIFY BUSINESS HANDLES ===
IMPORTANT: Look for Instagram/social media handles that belong to the LOCATION/BUSINESS being featured (NOT the content creator).

How to distinguish:
- **Content Creator Handle**: The account posting the content (appears at top of post, after "Post by", etc.)
- **Business/Location Handle**: The business being FEATURED (often appears in captions, tagged, mentioned with "check out @...", "dm @... to order", etc.)

Examples:
- "@ariannalakess" posting about "@dolcelunacafe" → dolcelunacafe is the BUSINESS handle
- "@foodblogger" posting about "@joes_pizza_nyc" → joes_pizza_nyc is the BUSINESS handle
- "dm @matchabuckets to order" → matchabuckets is the BUSINESS handle
- "check out her cafe @sweetcafe" → sweetcafe is the BUSINESS handle

=== CRITICAL: COMBINE INFORMATION ===
- One image might show a sign or art piece name (like "POET TREES")
- Another image might describe the location ("library in the redwoods of Big Sur")
- COMBINE these clues: "POET TREES" + "library in Big Sur" = context for searching
- The actual location name might NOT be explicitly visible - provide context clues to search for it

=== OUTPUT FORMAT ===
Return a JSON object with this structure:
{
  "content_type": "Type of content",
  "purpose": "What is being featured or recommended",
  "geographic_focus": "The main region/city/area or null",
  "location_types_to_find": ["bookstore", "library", "attraction"],
  "criteria": ["unique", "hidden gem"],
  "context_clues": ["shows 'POET TREES' sign", "mentions redwoods", "describes as library"],
  "exclusions": ["UI elements", "navigation buttons"],
  "extracted_text": "ALL visible text from ALL images combined. Include signs, captions, overlay text, etc.",
  "mentioned_place_names": ["List of ACTUAL PLACE NAMES explicitly mentioned in the text (e.g., 'Del Mar Plaza', 'Griffith Observatory', 'Pike Place Market'). These are the PLACES being RECOMMENDED, not the content creator."],
  "search_query_suggestion": "A Google search query combining the place name + location (e.g., 'Del Mar Plaza San Diego')",
  "content_creator_handle": "The handle of who posted this content (e.g., 'socalnation', 'ariannalakess') or null",
  "business_handles": ["List of handles that belong to the BUSINESS/LOCATION being featured, NOT the content creator (e.g., ['dolcelunacafe', 'matchabuckets'])"]
}

=== CRITICAL: DISTINGUISH CONTENT CREATOR FROM PLACE BEING RECOMMENDED ===
VERY IMPORTANT: The content creator (who posted) is DIFFERENT from the place being recommended!

Example 1: "@socalnation" posts "Del Mar Plaza might be your next lunch spot"
- content_creator_handle: "socalnation" (the blogger who posted)
- mentioned_place_names: ["Del Mar Plaza"] (the actual place being RECOMMENDED)
- business_handles: [] (no business handle mentioned)
- search_query_suggestion: "Del Mar Plaza San Diego"

Example 2: "@foodblogger" posts "Check out @dolcelunacafe for amazing matcha"
- content_creator_handle: "foodblogger" (the blogger who posted)
- mentioned_place_names: [] (no explicit place name in text)
- business_handles: ["dolcelunacafe"] (the business handle tagged)
- search_query_suggestion: "Dolce Luna Cafe"

PRIORITY ORDER:
1. **mentioned_place_names** - Actual place names in the text are MOST RELIABLE
2. **business_handles** - Tagged business handles (NOT the content creator)
3. **search_query_suggestion** - As a fallback search query

=== EXAMPLES ===

**Example 1: Food blogger featuring a cafe**
If you see:
- Post by @ariannalakess
- Caption: "MATCHA BUCKETS from a home based cafe... dm to order"
- @dolcelunacafe tagged or mentioned
Return:
{
  "content_creator_handle": "ariannalakess",
  "business_handles": ["dolcelunacafe"],
  ...
}

**Example 2: Travel account featuring a restaurant**
If you see:
- Post by @foodie_travels
- Caption: "Best pizza in NYC! @joes_pizza_nyc"
Return:
{
  "content_creator_handle": "foodie_travels",
  "business_handles": ["joes_pizza_nyc"],
  ...
}

=== IMPORTANT ===
- Treat all images as ONE piece of content, not separate items
- Combine clues from different images to form a complete picture
- The "mentioned_place_names" is MOST IMPORTANT - look for actual place names mentioned in captions/text
- The "search_query_suggestion" should combine the place name + geographic context for accurate search
- Business handles are useful ONLY when an actual place name is not mentioned
- The content_creator_handle is the person who POSTED, NOT the place being recommended
- Return ONLY the JSON object, no other text
''';
  }

  /// Use Google Search grounding to find the actual location name based on context
  Future<ExtractedLocationInfo?> _searchForActualLocationName(ContentContext context) async {
    // ========== PRIORITY 1: SEARCH FOR EXPLICITLY MENTIONED PLACE NAMES ==========
    // Actual place names mentioned in text are the MOST RELIABLE way to find the location
    // e.g., "Del Mar Plaza might be your next lunch spot" → search "Del Mar Plaza"
    if (context.mentionedPlaceNames.isNotEmpty) {
      print('🏷️ GEMINI MULTI-IMAGE STEP 2: Found ${context.mentionedPlaceNames.length} explicitly mentioned place name(s)');
      
      for (final placeName in context.mentionedPlaceNames) {
        // Build search query with geographic context for better accuracy
        String searchQuery = placeName;
        if (context.geographicFocus != null) {
          searchQuery = '$placeName ${context.geographicFocus}';
        }
        
        print('🏷️ GEMINI MULTI-IMAGE STEP 2: Searching for mentioned place: "$searchQuery"');
        
        final placeResult = await _searchForPlaceNameWithGrounding(searchQuery, context);
        
        if (placeResult != null) {
          print('✅ GEMINI MULTI-IMAGE STEP 2: Found place from mentioned name "$placeName": "${placeResult.name}"');
          return placeResult;
        }
      }
      
      print('⚠️ GEMINI MULTI-IMAGE STEP 2: Could not find places from mentioned names, trying search query suggestion...');
    }
    
    // ========== PRIORITY 2: USE SEARCH QUERY SUGGESTION ==========
    // The AI's suggested search query often combines place name + location
    if (context.searchQuerySuggestion != null && context.searchQuerySuggestion!.isNotEmpty) {
      print('🔍 GEMINI MULTI-IMAGE STEP 2: Using search query suggestion: "${context.searchQuerySuggestion}"');
      
      final suggestionResult = await _searchForPlaceNameWithGrounding(context.searchQuerySuggestion!, context);
      
      if (suggestionResult != null) {
        print('✅ GEMINI MULTI-IMAGE STEP 2: Found place from search suggestion: "${suggestionResult.name}"');
        return suggestionResult;
      }
      
      print('⚠️ GEMINI MULTI-IMAGE STEP 2: Search query suggestion did not yield results, trying business handles...');
    }
    
    // ========== PRIORITY 3: SEARCH FOR BUSINESS HANDLES ==========
    // Business handles can help find the location when no explicit name is mentioned
    // e.g., @dolcelunacafe → "Dolce Luna Cafe"
    if (context.businessHandles.isNotEmpty) {
      print('🔎 GEMINI MULTI-IMAGE STEP 2: Found ${context.businessHandles.length} business handle(s) to search');
      
      for (final handle in context.businessHandles) {
        print('🔎 GEMINI MULTI-IMAGE STEP 2: Searching for business handle: @$handle');
        
        final handleResult = await _searchForBusinessByHandle(handle, context);
        
        if (handleResult != null) {
          print('✅ GEMINI MULTI-IMAGE STEP 2: Found business from handle @$handle: "${handleResult.name}"');
          return handleResult;
        }
      }
      
      print('⚠️ GEMINI MULTI-IMAGE STEP 2: Could not find business from handles, trying other methods...');
    }
    
    // ========== PRIORITY 4: BUILD SEARCH QUERY FROM CONTEXT ==========
    // Build a search query from the context
    String? searchQuery = context.extractedText;
    
    // Try to extract a search query suggestion if present
    // The context analysis might have suggested a search query
    if (context.contextClues.isNotEmpty) {
      // Look for a suggested search query in context clues
      for (final clue in context.contextClues) {
        if (clue.toLowerCase().contains('search') || clue.toLowerCase().contains('query')) {
          searchQuery = clue;
          break;
        }
      }
    }
    
    // Build search query from available information
    final queryParts = <String>[];
    
    // Add location types
    if (context.locationTypesToFind.isNotEmpty) {
      queryParts.add(context.locationTypesToFind.first);
    }
    
    // Add geographic focus
    if (context.geographicFocus != null) {
      queryParts.add(context.geographicFocus!);
    }
    
    // Add key context clues (but not meta-descriptions)
    for (final clue in context.contextClues) {
      if (!clue.toLowerCase().contains('shows') && 
          !clue.toLowerCase().contains('mentions') &&
          !clue.toLowerCase().contains('describes') &&
          clue.length < 50) {
        queryParts.add(clue);
      }
    }
    
    // Extract key phrases from extracted text
    if (context.extractedText != null && context.extractedText!.isNotEmpty) {
      // Look for potential place name patterns (capitalized words, quoted text)
      final text = context.extractedText!;
      
      // Find capitalized phrases that might be place names
      final capitalizedPhrases = RegExp(r'\b[A-Z][A-Z\s]+\b').allMatches(text);
      for (final match in capitalizedPhrases) {
        final phrase = match.group(0)?.trim();
        if (phrase != null && 
            phrase.length > 3 && 
            phrase.length < 30 &&
            !_isCommonUIText(phrase)) {
          queryParts.add(phrase);
        }
      }
    }
    
    if (queryParts.isEmpty) {
      print('⚠️ GEMINI MULTI-IMAGE STEP 2: No search query could be built');
      return null;
    }
    
    // Deduplicate and join
    final uniqueParts = queryParts.toSet().toList();
    final finalQuery = uniqueParts.join(' ');
    
    print('🔎 GEMINI MULTI-IMAGE STEP 2: Searching for actual location with query: "$finalQuery"');
    
    // Use Google Search grounding to find the actual place name
    final searchResult = await _searchForPlaceNameWithGrounding(finalQuery, context);
    
    return searchResult;
  }
  
  /// Extract street addresses from text using common US address patterns
  /// Returns a list of potential street addresses found in the text
  List<String> _extractAddressesFromText(String? text) {
    if (text == null || text.isEmpty) return [];
    
    final addresses = <String>[];
    
    // Pattern for US street addresses:
    // - Starts with numbers (street number)
    // - Followed by street name words
    // - Optional street type (Ave, St, Blvd, etc.)
    // - City, State ZIP pattern
    final fullAddressPattern = RegExp(
      r'\b(\d+\s+[\w\s]+(?:Ave(?:nue)?|St(?:reet)?|Blvd|Boulevard|Dr(?:ive)?|Rd|Road|Ln|Lane|Way|Pl(?:ace)?|Ct|Court|Cir(?:cle)?|Pkwy|Parkway|Hwy|Highway)\.?\s*,?\s*[\w\s]+,?\s*(?:CA|California|NY|New York|TX|Texas|FL|Florida|WA|Washington|AZ|Arizona|NV|Nevada|OR|Oregon|CO|Colorado|IL|Illinois|PA|Pennsylvania|OH|Ohio|GA|Georgia|NC|North Carolina|MI|Michigan|NJ|New Jersey|VA|Virginia|MA|Massachusetts|TN|Tennessee|IN|Indiana|MO|Missouri|MD|Maryland|WI|Wisconsin|MN|Minnesota|SC|South Carolina|AL|Alabama|LA|Louisiana|KY|Kentucky|OK|Oklahoma|CT|Connecticut|UT|Utah|IA|Iowa|NE|Nebraska|MS|Mississippi|AR|Arkansas|KS|Kansas|NM|New Mexico|ID|Idaho|WV|West Virginia|HI|Hawaii|NH|New Hampshire|ME|Maine|MT|Montana|RI|Rhode Island|DE|Delaware|SD|South Dakota|ND|North Dakota|AK|Alaska|VT|Vermont|WY|Wyoming|DC)\.?\s*\d{5}(?:-\d{4})?)\b',
      caseSensitive: false,
    );
    
    // Simpler pattern: just street address with city and state
    final simpleAddressPattern = RegExp(
      r'\b(\d+\s+[\w\s]+(?:Ave(?:nue)?|St(?:reet)?|Blvd|Boulevard|Dr(?:ive)?|Rd|Road|Ln|Lane|Way|Pl(?:ace)?|Ct|Court|Cir(?:cle)?|Pkwy|Parkway|Hwy|Highway)\.?\s*,?\s*[\w\s]+,?\s*(?:CA|NY|TX|FL|WA|AZ|NV|OR|CO|IL|PA|OH|GA|NC|MI|NJ|VA|MA|TN|IN|MO|MD|WI|MN|SC|AL|LA|KY|OK|CT|UT|IA|NE|MS|AR|KS|NM|ID|WV|HI|NH|ME|MT|RI|DE|SD|ND|AK|VT|WY|DC))\b',
      caseSensitive: false,
    );
    
    // Most complete pattern with ZIP code
    for (final match in fullAddressPattern.allMatches(text)) {
      final address = match.group(1)?.trim();
      if (address != null && address.length > 10) {
        addresses.add(address);
        print('   📍 HANDLE SEARCH: Found address in text: "$address"');
      }
    }
    
    // If no full addresses found, try simpler pattern
    if (addresses.isEmpty) {
      for (final match in simpleAddressPattern.allMatches(text)) {
        final address = match.group(1)?.trim();
        if (address != null && address.length > 10) {
          addresses.add(address);
          print('   📍 HANDLE SEARCH: Found partial address in text: "$address"');
        }
      }
    }
    
    return addresses;
  }

  /// Search for a business by its Instagram/social media handle
  /// Uses Google Search grounding to find the actual business name
  Future<ExtractedLocationInfo?> _searchForBusinessByHandle(
    String handle,
    ContentContext context,
  ) async {
    try {
      // Extract any addresses mentioned in the text - these are CRITICAL for finding the right location
      final extractedAddresses = _extractAddressesFromText(context.extractedText);
      final hasExtractedAddress = extractedAddresses.isNotEmpty;
      
      if (hasExtractedAddress) {
        print('🔎 GEMINI HANDLE SEARCH: Found ${extractedAddresses.length} address(es) in extracted text');
        for (final addr in extractedAddresses) {
          print('   → "$addr"');
        }
      }
      
      // Build address context for the prompt
      String addressContext = '';
      if (hasExtractedAddress) {
        addressContext = '''

=== CRITICAL: SPECIFIC ADDRESS FOUND IN SOURCE ===
The following address(es) were explicitly mentioned in the source content:
${extractedAddresses.map((a) => '• $a').join('\n')}

*** THIS IS THE MOST IMPORTANT SIGNAL ***
The business @$handle is LOCATED AT ONE OF THESE ADDRESSES.
You MUST find the business at this EXACT address, not a similarly-named business elsewhere.
If @$handle operates at "${extractedAddresses.first}", return that location.
''';
      }
      
      final prompt = '''
I need to find the ACTUAL BUSINESS NAME for the Instagram account "@$handle".

${context.geographicFocus != null ? 'Geographic area: ${context.geographicFocus}' : ''}
${context.locationTypesToFind.isNotEmpty ? 'Business type: ${context.locationTypesToFind.join(", ")}' : ''}
$addressContext
=== YOUR TASK ===
Search online to find:
1. What business does @$handle belong to?
2. What is the OFFICIAL business name?
3. Where is it located?${hasExtractedAddress ? '\n4. VERIFY the business is at the address mentioned above!' : ''}

=== SEARCH STRATEGY ===
${hasExtractedAddress ? '''1. FIRST: Search for "@$handle ${extractedAddresses.first}" to confirm the address
2. Search for the address "${extractedAddresses.first}" to find what business is there
3.''' : '1.'} Search for "@$handle instagram"
${hasExtractedAddress ? '4.' : '2.'} Search for "@$handle ${context.geographicFocus ?? ''}"
${hasExtractedAddress ? '5.' : '3.'} Look for the business website, Google listing, or Yelp page

=== OUTPUT FORMAT ===
Return a JSON object:
{
  "found": true or false,
  "name": "The official business name (e.g., 'Dolce Luna Cafe', 'Joe's Pizza')",
  "address": "The full street address if known",
  "city": "City name",
  "region": "State/Region",
  "type": "cafe/restaurant/bakery/etc",
  "confidence": "high/medium/low",
  "explanation": "How you identified this business"${hasExtractedAddress ? ',\n  "address_verified": true or false' : ''}
}

If you cannot find the business with confidence, return:
{"found": false, "name": null, "explanation": "Why it couldn't be found"}

=== RULES ===
- Search for the ACTUAL business name from @$handle
- Do NOT just convert the handle to a name (e.g., don't just return "Dolce Luna Cafe" from @dolcelunacafe without verifying)${hasExtractedAddress ? '\n- The address from the source ("' + extractedAddresses.first + '") is the MOST RELIABLE signal - prioritize it!' : ''}
- Use Google Search to verify the business exists
${hasExtractedAddress ? '- If you find multiple businesses with similar names, choose the one at the specified address' : ''}
- Return ONLY the JSON object, no other text
''';

      final response = await _callGeminiWithSearchGrounding(prompt);
      
      if (response == null) {
        print('⚠️ GEMINI HANDLE SEARCH: No response from search grounding for @$handle');
        return null;
      }
      
      // Parse the response
      final result = _parseSearchGroundingResponse(response, context);
      
      if (result != null) {
        print('✅ GEMINI HANDLE SEARCH: Found business for @$handle: "${result.name}"');
      }
      
      return result;
    } catch (e) {
      print('❌ GEMINI HANDLE SEARCH ERROR for @$handle: $e');
      return null;
    }
  }

  /// Verify a location without printing detailed explanations (for STEP 3)
  Future<ExtractedLocationInfo?> _verifyLocationQuietly(String locationName, ContentContext context, {String? extractedAddress}) async {
    try {
      // Build address context if we have an extracted address
      final addressContext = extractedAddress != null && extractedAddress.isNotEmpty
          ? '''

=== CRITICAL: SPECIFIC ADDRESS PROVIDED ===
The source content explicitly mentions this address for "$locationName":
📍 $extractedAddress

*** THIS ADDRESS IS THE MOST RELIABLE SIGNAL ***
You MUST use this address in your response. Do NOT search for a different address.
The place "$locationName" is located at "$extractedAddress" - verify this is a real address and use it.
'''
          : '';
      
      final prompt = '''
Verify that THIS SPECIFIC place exists: "$locationName"

${context.geographicFocus != null ? 'REGION CONTEXT: ${context.geographicFocus}' : ''}
${context.locationTypesToFind.isNotEmpty ? 'EXPECTED TYPES: ${context.locationTypesToFind.join(", ")}' : ''}
$addressContext
=== OUTPUT FORMAT ===
Return a JSON object:
{
  "found": true or false,
  "name": "The place name (preserve the original, just fix spelling/formatting)",
  "address": "Address or general location description",
  "city": "City name",
  "region": "State/Region",
  "type": "restaurant/museum/park/beach/trail/etc",
  "confidence": "high/medium/low"
}

If you cannot verify the place exists, return:
{"found": false, "name": null}

=== CRITICAL RULES ===
- VERIFY the place "$locationName" exists - do NOT substitute a different place
- Keep the SAME place the user mentioned, just clean up spelling/formatting${extractedAddress != null ? '\n- USE THE PROVIDED ADDRESS "$extractedAddress" - do NOT replace it with a generic location' : ''}
- Do NOT replace natural areas with visitor centers (e.g., "Hoh Rain Forest" should NOT become "Hoh Rain Forest Visitor Center")
- Do NOT replace parks with gift shops, museums, or other buildings within them
- Do NOT replace beaches/trails/mountains with nearby facilities
- For natural areas without street addresses, use a general location (e.g., "Olympic National Park, WA")
- Return ONLY the JSON object, no other text
''';

      final response = await _callGeminiWithSearchGrounding(prompt);

      if (response == null) return null;

      // Parse response but don't print explanations
      final candidates = response['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return null;

      final candidate = candidates.first as Map<String, dynamic>;
      final content = candidate['content'] as Map<String, dynamic>?;
      if (content == null) return null;

      final parts = content['parts'] as List?;
      if (parts == null || parts.isEmpty) return null;

      final text = parts.first['text'] as String? ?? '';

      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (jsonMatch == null) return null;

      try {
        final parsed = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
        final found = parsed['found'] as bool? ?? false;

        if (!found) return null;

        final name = parsed['name'] as String?;
        if (name == null || name.isEmpty) return null;

        final confidence = parsed['confidence'] as String? ?? 'medium';

        // Only return high/medium confidence results
        if (confidence == 'low') return null;

        // Determine which address to use
        final geminiAddress = parsed['address'] as String?;
        String? finalAddress = geminiAddress;
        
        // If we have an extracted address from the source, prefer it over generic Gemini responses
        if (extractedAddress != null && extractedAddress.isNotEmpty) {
          // Check if Gemini's address is too generic (just city/state/region)
          final isGenericAddress = geminiAddress == null || 
              geminiAddress.isEmpty ||
              !RegExp(r'\d+\s+[\w\s]+(Ave|St|Blvd|Dr|Rd|Road|Ln|Lane|Way|Pl|Ct|Cir|Pkwy|Hwy)', caseSensitive: false).hasMatch(geminiAddress);
          
          if (isGenericAddress) {
            finalAddress = extractedAddress;
            print('   📍 Using extracted address (more specific): $extractedAddress');
          } else {
            print('   📍 Grounded address: $geminiAddress');
          }
        } else if (geminiAddress != null && geminiAddress.isNotEmpty) {
          print('   📍 Grounded address: $geminiAddress');
        }

        return ExtractedLocationInfo(
          name: name,
          address: finalAddress,
          city: parsed['city'] as String?,
          type: parsed['type'] as String?,
          regionContext: context.geographicFocus,
        );
      } catch (e) {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// Check if text is common UI text that should be ignored
  bool _isCommonUIText(String text) {
    final commonUI = [
      'SAVE', 'CANCEL', 'FOLLOW', 'SHARE', 'POST', 'COMMENT', 'LIKE',
      'PUBLIC', 'PRIVATE', 'UPLOAD', 'SCREENSHOT', 'PREVIEW', 'SCAN',
      'CONTENT', 'URL', 'HTTP', 'HTTPS', 'WWW', 'COM', 'INSTAGRAM',
    ];
    return commonUI.contains(text.toUpperCase().trim());
  }

  /// Check if a string looks like a real street address vs a place name
  /// Real addresses have patterns like "123 Main St", "1 Casino Way, Avalon, CA"
  /// Place names like "Pier 24", "Flx Biergarten" should NOT be treated as addresses
  bool _looksLikeRealAddress(String text) {
    final trimmed = text.trim();
    
    // Common street type suffixes (full and abbreviated)
    final streetTypes = RegExp(
      r'\b(street|st|avenue|ave|road|rd|boulevard|blvd|drive|dr|lane|ln|'
      r'place|pl|court|ct|way|circle|cir|terrace|ter|parkway|pkwy|highway|hwy|'
      r'trail|trl|loop|pass|crossing|xing|square|sq|alley|aly)\b',
      caseSensitive: false,
    );
    
    // Pattern: starts with a number followed by street name with street type
    // Examples: "123 Main St", "1 Casino Way", "456 Oak Avenue"
    final addressPattern = RegExp(
      r'^\d+\s+\w+.*\b(street|st|avenue|ave|road|rd|boulevard|blvd|drive|dr|'
      r'lane|ln|place|pl|court|ct|way|circle|cir|terrace|ter|parkway|pkwy|'
      r'highway|hwy|trail|trl|loop|pass|crossing|xing|square|sq|alley|aly)\b',
      caseSensitive: false,
    );
    
    // Check for typical address pattern (number + street name + street type)
    if (addressPattern.hasMatch(trimmed)) {
      return true;
    }
    
    // Check for patterns like "Corner of X and Y" which are address-like
    if (trimmed.toLowerCase().startsWith('corner of')) {
      return true;
    }
    
    // Check for city, state, zip pattern (e.g., "Avalon, CA 90704")
    final cityStateZipPattern = RegExp(
      r',\s*[A-Z]{2}\s*\d{5}',
      caseSensitive: false,
    );
    if (cityStateZipPattern.hasMatch(trimmed) && streetTypes.hasMatch(trimmed)) {
      return true;
    }
    
    // Check for "X Street" or "X Avenue" patterns (street names without numbers)
    // but only if they contain common street suffixes
    // This catches partial addresses like "Chimes Tower Rd" or "3rd St"
    final partialAddressPattern = RegExp(
      r'^(\d+\w*\s+)?\w+\s+(street|st|avenue|ave|road|rd|boulevard|blvd|'
      r'drive|dr|lane|ln|place|pl|court|ct|way|circle|cir|terrace|ter|'
      r'parkway|pkwy|highway|hwy|trail|trl|loop|pass|crossing|xing|'
      r'square|sq|alley|aly)(\s|,|$)',
      caseSensitive: false,
    );
    if (partialAddressPattern.hasMatch(trimmed)) {
      return true;
    }
    
    // NOT an address: things like "Pier 24", "Terminal 5", "Gate A4", "Hall 3"
    // These are place names that happen to have numbers
    final placeWithNumberPattern = RegExp(
      r'^(pier|terminal|gate|hall|building|floor|suite|unit|room|level|dock|'
      r'stage|hangar|warehouse|studio|lot|platform|station|track)\s*\d+',
      caseSensitive: false,
    );
    if (placeWithNumberPattern.hasMatch(trimmed)) {
      return false;  // This is a place name, not an address
    }
    
    // If it's just a short text without any address indicators, it's probably a place name
    // Examples: "Flx Biergarten", "Hotel Atwater", "Descanso Beach Club"
    if (!streetTypes.hasMatch(trimmed) && 
        !trimmed.contains(',') && 
        !RegExp(r'^\d+\s').hasMatch(trimmed)) {
      return false;  // No street types, no commas, doesn't start with number = place name
    }
    
    return false;  // Default to treating as place name if uncertain
  }

  /// Use Gemini with Google Search grounding to find the actual place name
  Future<ExtractedLocationInfo?> _searchForPlaceNameWithGrounding(
    String searchQuery,
    ContentContext context,
  ) async {
    try {
      // Extract any addresses mentioned in the text - these are CRITICAL for finding the right location
      final extractedAddresses = _extractAddressesFromText(context.extractedText);
      final hasExtractedAddress = extractedAddresses.isNotEmpty;
      
      if (hasExtractedAddress) {
        print('🔎 GEMINI SEARCH: Found ${extractedAddresses.length} address(es) in extracted text');
        for (final addr in extractedAddresses) {
          print('   → "$addr"');
        }
      }
      
      // Build address context for the prompt
      String addressContext = '';
      if (hasExtractedAddress) {
        addressContext = '''

=== CRITICAL: SPECIFIC ADDRESS FOUND IN SOURCE ===
The following address(es) were explicitly mentioned in the source content:
${extractedAddresses.map((a) => '• $a').join('\n')}

*** THIS IS THE MOST IMPORTANT SIGNAL ***
The place is LOCATED AT ONE OF THESE ADDRESSES.
You MUST verify the business is at this EXACT address, not a similarly-named business elsewhere.
Include this address in your response.
''';
      }
      
      final prompt = '''
I need to find the ACTUAL NAME of a specific place based on these clues:

SEARCH QUERY: $searchQuery

CONTEXT:
- Content Type: ${context.contentType}
- Purpose: ${context.purpose}
- Geographic Focus: ${context.geographicFocus ?? "Unknown"}
- Looking for: ${context.locationTypesToFind.join(", ")}
- Context Clues: ${context.contextClues.join("; ")}

EXTRACTED TEXT FROM CONTENT:
${context.extractedText ?? "None"}
$addressContext
=== YOUR TASK ===
Search online to find the ACTUAL, OFFICIAL NAME of the place being described/featured.

For example:
- "POET TREES" + "library in Big Sur redwoods" → "Henry Miller Memorial Library" (POET TREES is art there)
- "coolest bookstore California Big Sur" → "Henry Miller Memorial Library"

=== OUTPUT FORMAT ===
Return a JSON object:
{
  "found": true or false,
  "name": "The official place name (e.g., 'Henry Miller Memorial Library')",
  "address": "Full street address if known (e.g., '7924 Melrose Ave, Los Angeles, CA 90046')",
  "city": "City name",
  "region": "State/Region",
  "type": "library/bookstore/restaurant/etc",
  "confidence": "high/medium/low",
  "explanation": "Brief explanation of how you identified this place"
}

If you cannot find a specific place with confidence, return:
{"found": false, "name": null, "explanation": "Why it couldn't be found"}

=== RULES ===
- Search for the ACTUAL place name, not just repeat the search query
- Use Google Search to verify the place exists
- If an address was found in the source, VERIFY the business is at that address${hasExtractedAddress ? '\n- The address from the source content is: ${extractedAddresses.first}' : ''}
- Return ONLY the JSON object, no other text
''';

      final response = await _callGeminiWithSearchGrounding(prompt);
      
      if (response == null) {
        print('⚠️ GEMINI SEARCH: No response from search grounding');
        return null;
      }
      
      // Parse the response, passing extracted addresses as fallback
      final result = _parseSearchGroundingResponse(
        response, 
        context, 
        extractedAddressFallback: hasExtractedAddress ? extractedAddresses.first : null,
      );
      
      if (result != null) {
        print('✅ GEMINI SEARCH: Found place via Google Search: "${result.name}"');
        if (result.address != null) {
          print('   📍 Final address: ${result.address}');
        }
      }
      
      return result;
    } catch (e) {
      print('❌ GEMINI SEARCH ERROR: $e');
      return null;
    }
  }

  /// Sanitize JSON text from Gemini responses to handle common issues
  /// 
  /// Gemini sometimes returns JSON with unescaped quotes in string values:
  /// e.g., "explanation": "\"Hole-in-the-Wall" is a sea-carved arch..."
  /// The inner quote after "\"Hole-in-the-Wall should be escaped but isn't.
  /// 
  /// This method attempts to fix such issues to allow successful parsing.
  String _sanitizeGeminiJson(String jsonText) {
    // Try to parse as-is first - if it works, no sanitization needed
    try {
      jsonDecode(jsonText);
      return jsonText; // Valid JSON, return as-is
    } catch (_) {
      // JSON is invalid, try to fix it
    }
    
    // Common pattern: unescaped quotes in string values
    // Match: "key": "value with "quoted text" inside"
    // This regex finds string values and tries to escape internal quotes
    
    // Approach: Find quoted strings after colons and escape any unescaped internal quotes
    // We'll process character by character to handle nested quotes properly
    
    final result = StringBuffer();
    bool inString = false;
    int i = 0;
    
    while (i < jsonText.length) {
      final char = jsonText[i];
      final prevChar = i > 0 ? jsonText[i - 1] : '';
      
      if (char == '"' && prevChar != '\\') {
        if (!inString) {
          // Starting a string
          inString = true;
          result.write(char);
        } else {
          // Ending a string (or embedded quote)
          // Check if this looks like the end of a string value
          // by looking at what comes next (should be , } ] or whitespace followed by one of those)
          int j = i + 1;
          while (j < jsonText.length && (jsonText[j] == ' ' || jsonText[j] == '\n' || jsonText[j] == '\t' || jsonText[j] == '\r')) {
            j++;
          }
          final nextSignificant = j < jsonText.length ? jsonText[j] : '';
          final looksLikeEnd = nextSignificant == ',' || nextSignificant == '}' || nextSignificant == ']' || nextSignificant == ':' || j >= jsonText.length;
          
          if (looksLikeEnd) {
            // This is likely the actual end of the string
            inString = false;
            result.write(char);
          } else {
            // This is likely an embedded quote that should be escaped
            result.write('\\');
            result.write(char);
          }
        }
      } else {
        result.write(char);
      }
      i++;
    }
    
    // Try to parse the result
    final sanitized = result.toString();
    try {
      jsonDecode(sanitized);
      return sanitized;
    } catch (_) {
      // Sanitization didn't help, return original (will fail on parse)
      return jsonText;
    }
  }

  /// Parse the search grounding response
  /// [extractedAddressFallback] is an address extracted from the source content
  /// that will be used if Gemini doesn't return an address
  ExtractedLocationInfo? _parseSearchGroundingResponse(
    Map<String, dynamic> response,
    ContentContext context, {
    String? extractedAddressFallback,
  }) {
    // Extract text early so it's available for fallback in catch block
    String? text;
    try {
      final candidates = response['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return null;

      final candidate = candidates.first as Map<String, dynamic>;
      final content = candidate['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) return null;
      
      text = parts.first['text'] as String?;
      if (text == null || text.isEmpty) return null;

      // Parse JSON
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
      
      // Sanitize JSON to handle common Gemini issues like unescaped quotes
      // e.g., "explanation": "\"Hole-in-the-Wall" is..." → the inner quote needs escaping
      jsonText = _sanitizeGeminiJson(jsonText);

      Map<String, dynamic> parsed;
      try {
        parsed = jsonDecode(jsonText) as Map<String, dynamic>;
      } catch (jsonError) {
        // Log the problematic text for debugging
        final preview = jsonText.length > 200 ? '${jsonText.substring(0, 200)}...' : jsonText;
        print('⚠️ GEMINI SEARCH: JSON parse error after sanitization');
        print('   Raw text preview: $preview');
        rethrow; // Let outer catch handle it with fallback
      }

      final found = parsed['found'] as bool? ?? false;
      if (!found) {
        print('⚠️ GEMINI SEARCH: Search did not find a confident match');
        return null;
      }

      final name = parsed['name'] as String?;
      if (name == null || name.isEmpty) return null;
      
      final confidence = parsed['confidence'] as String? ?? 'medium';
      final explanation = parsed['explanation'] as String?;
      var address = parsed['address'] as String?;
      final addressVerified = parsed['address_verified'] as bool?;
      
      print('   🔍 Search confidence: $confidence');
      if (address != null && address.isNotEmpty) {
        print('   📍 Address from Gemini: $address');
      }
      
      // If Gemini didn't return an address but we have one from the extracted text, use it
      if ((address == null || address.isEmpty) && extractedAddressFallback != null) {
        address = extractedAddressFallback;
        print('   📍 Using extracted address fallback: $address');
      }
      
      if (addressVerified != null) {
        print('   ✅ Address verified: $addressVerified');
      }
      if (explanation != null) {
        print('   📝 Explanation: $explanation');
      }
      
      // Only return high/medium confidence results
      if (confidence == 'low') {
        print('⚠️ GEMINI SEARCH: Low confidence result, skipping');
        return null;
      }
      
      return ExtractedLocationInfo(
        name: name,
        address: address,
        city: parsed['city'] as String?,
        type: parsed['type'] as String?,
        regionContext: context.geographicFocus,
      );
    } catch (e) {
      print('⚠️ GEMINI SEARCH: Error parsing response: $e');
      
      // Try fallback regex extraction when JSON parsing fails
      final fallback = _fallbackExtractFromText(text, context, extractedAddressFallback: extractedAddressFallback);
      if (fallback != null) {
        print('✅ GEMINI SEARCH: Recovered using regex fallback');
        return fallback;
      }
      
      return null;
    }
  }
  
  /// Fallback extraction using regex when JSON parsing fails
  /// This handles cases where Gemini returns malformed JSON due to unescaped quotes
  /// [extractedAddressFallback] is used if no address is found in the response
  ExtractedLocationInfo? _fallbackExtractFromText(
    String? text, 
    ContentContext context, {
    String? extractedAddressFallback,
  }) {
    if (text == null || text.isEmpty) return null;
    
    try {
      // Check if found is true (look for "found": true pattern)
      final foundMatch = RegExp(r'"found"\s*:\s*(true|false)', caseSensitive: false).firstMatch(text);
      if (foundMatch == null || foundMatch.group(1)?.toLowerCase() != 'true') {
        return null; // Not found or can't determine
      }
      
      // Extract name using regex - look for "name": "..." pattern
      final nameMatch = RegExp(r'"name"\s*:\s*"([^"]+)"').firstMatch(text);
      if (nameMatch == null) return null;
      
      final name = nameMatch.group(1);
      if (name == null || name.isEmpty) return null;
      
      // Extract address if present
      final addressMatch = RegExp(r'"address"\s*:\s*"([^"]+)"').firstMatch(text);
      var address = addressMatch?.group(1);
      
      // Use fallback address if no address found in response
      if ((address == null || address.isEmpty) && extractedAddressFallback != null) {
        address = extractedAddressFallback;
        print('   📍 Using extracted address fallback (fallback parser): $address');
      }
      
      // Extract city if present
      final cityMatch = RegExp(r'"city"\s*:\s*"([^"]+)"').firstMatch(text);
      final city = cityMatch?.group(1);
      
      // Extract type if present
      final typeMatch = RegExp(r'"type"\s*:\s*"([^"]+)"').firstMatch(text);
      final type = typeMatch?.group(1);
      
      // Extract confidence if present
      final confidenceMatch = RegExp(r'"confidence"\s*:\s*"([^"]+)"').firstMatch(text);
      final confidence = confidenceMatch?.group(1) ?? 'medium';
      
      // Skip low confidence results
      if (confidence.toLowerCase() == 'low') {
        print('⚠️ GEMINI SEARCH (fallback): Low confidence result, skipping');
        return null;
      }
      
      print('   🔍 Search confidence (fallback): $confidence');
      if (address != null) {
        print('   📍 Address found (fallback): $address');
      }
      
      return ExtractedLocationInfo(
        name: name,
        address: address,
        city: city,
        type: type,
        regionContext: context.geographicFocus,
      );
    } catch (e) {
      print('⚠️ GEMINI SEARCH: Fallback extraction also failed: $e');
      return null;
    }
  }

  /// Extract locations from combined context using Google Search grounding for each location
  /// This applies the same verification process as Step 2, but for multiple locations
  Future<List<ExtractedLocationInfo>> _extractLocationsFromCombinedContext(
    List<({Uint8List bytes, String mimeType})> images,
    ContentContext context,
  ) async {
    try {
      print('🔍 GEMINI MULTI-IMAGE STEP 3: Extracting ALL locations from combined context...');
      
      // Step 3a: First, extract all raw location names (with addresses) mentioned in the text
      final rawLocations = await _extractRawLocationNamesWithAddresses(context);
      
      if (rawLocations.isEmpty) {
        print('⚠️ GEMINI MULTI-IMAGE STEP 3: No location names found in text');
        return [];
      }
      
      print('📋 GEMINI MULTI-IMAGE STEP 3: Found ${rawLocations.length} location mention(s) to verify:');
      for (final loc in rawLocations) {
        if (loc.address != null) {
          print('   • ${loc.name} → 📍 ${loc.address}');
        } else {
          print('   • ${loc.name}');
        }
      }
      
      // Step 3b: Verify each location using Google Search grounding (like Step 2)
      final verifiedLocations = <ExtractedLocationInfo>[];
      
      for (int i = 0; i < rawLocations.length; i++) {
        final rawLoc = rawLocations[i];
        print('🔎 GEMINI STEP 3 [${i + 1}/${rawLocations.length}]: Verifying "${rawLoc.name}"${rawLoc.address != null ? ' (has address: ${rawLoc.address})' : ''}...');
        
        final verified = await _verifyLocationQuietly(rawLoc.name, context, extractedAddress: rawLoc.address);
        
        if (verified != null) {
          // Check for duplicates before adding
          final isDuplicate = verifiedLocations.any((existing) =>
              existing.name.toLowerCase() == verified.name.toLowerCase());
          
          if (!isDuplicate) {
            verifiedLocations.add(verified);
            print('   ✅ Verified: "${verified.name}"${verified.city != null ? " (${verified.city})" : ""}');
          } else {
            print('   ⏭️ Skipped duplicate: "${verified.name}"');
          }
        } else {
          print('   ⚠️ Could not verify: "${rawLoc.name}"');
        }
      }
      
      print('✅ GEMINI MULTI-IMAGE STEP 3: Verified ${verifiedLocations.length}/${rawLocations.length} locations');
      return verifiedLocations;
    } catch (e) {
      print('❌ GEMINI MULTI-IMAGE STEP 3 ERROR: $e');
      return [];
    }
  }
  
  /// Extract raw location names from the extracted text (without verification)
  /// Returns a list of records containing the location name and any associated address
  Future<List<({String name, String? address})>> _extractRawLocationNamesWithAddresses(ContentContext context) async {
    try {
      final prompt = '''
You are extracting location/place names from text content, along with any addresses mentioned near them.

=== EXTRACTED TEXT ===
${context.extractedText ?? "No text available"}

=== CONTEXT ===
- Geographic Focus: ${context.geographicFocus ?? "Not specified"}
- Content Type: ${context.contentType}
- Purpose: ${context.purpose}
- Looking for: ${context.locationTypesToFind.join(", ")}

=== YOUR TASK ===
Extract ALL specific place names mentioned that are:
- Restaurants, cafes, bars, hotels
- Museums, parks, gardens, attractions
- Landmarks, viewpoints, nature centers
- Any specific business or place that someone could visit

=== CRITICAL: DISTINGUISHING ADDRESSES FROM PLACE NAMES ===
A REAL ADDRESS contains:
- A street number + street name (e.g., "123 Main St", "1 Casino Way")
- Street type words like: St, Street, Ave, Avenue, Rd, Road, Blvd, Way, Dr, Drive, Ln, Lane, Pl, Place, Ct, Court
- Often includes city, state, zip (e.g., "Avalon, CA 90704")

A PLACE NAME is NOT an address - it's the name of a business/venue:
- "Pier 24" = PLACE NAME (a restaurant/bar named after a pier number)
- "Hotel Atwater" = PLACE NAME
- "Flx Biergarten" = PLACE NAME
- "Descanso Beach Club" = PLACE NAME

IMPORTANT: When multiple place names are listed together WITHOUT addresses, they are SEPARATE locations!
Example of a LIST of places (NO addresses):
  "Hotel Atwater
   Pier 24
   Flx Biergarten"
→ These are THREE separate places, each with address: null

Example WITH addresses:
  "Catalina Casino
   1 Casino Way, Avalon, CA 90704"
→ "1 Casino Way, Avalon, CA 90704" IS an address (has street number + street name)

=== WHAT TO IGNORE ===
- Generic region names (like "Baton Rouge" or "Louisiana" - only extract SPECIFIC places)
- Hashtags (they are context, not places)
- UI text (Save, Upload, Share, etc.)
- The airport (unless it's a destination itself)

=== CRITICAL: SOCIAL MEDIA HANDLES AS BUSINESS NAMES ===
Social media handles like @businessname are OFTEN the actual business name!
When you see:
- A numbered list with handles (e.g., "1.) @businessname - description")
- A handle followed by 📍 address
- A handle with associated location info
→ Convert the handle to a business name and extract it!

Examples of handles that ARE business names:
- "@youngbloodcocktails" → "Youngblood Cocktails" (convert camelCase to readable name)
- "@bar.kamon" → "Bar Kamon" (convert dots/periods to spaces)
- "@52remedies" → "52 Remedies" (keep numbers, add space where logical)
- "@dolcelunacafe" → "Dolce Luna Cafe"

=== OUTPUT FORMAT ===
Return a JSON object with an array of location objects:
{
  "locations": [
    {"name": "Restaurant Name", "address": "123 Main St, City, ST 12345"},
    {"name": "Museum Name", "address": null},
    {"name": "Park Name", "address": "456 Park Ave, City, ST"}
  ]
}

=== EXAMPLE 1: Places WITH addresses ===
Text:
"Catalina Casino
1 Casino Way, Avalon, CA 90704
El Rancho Escondido
3rd St, Avalon, CA 90704"

Output:
{
  "locations": [
    {"name": "Catalina Casino", "address": "1 Casino Way, Avalon, CA 90704"},
    {"name": "El Rancho Escondido", "address": "3rd St, Avalon, CA 90704"}
  ]
}

=== EXAMPLE 2: List of places WITHOUT addresses ===
Text:
"Here are some recommended restaurants:
Hotel Atwater
Pier 24
Flx Biergarten
Descanso Beach Club"

Output:
{
  "locations": [
    {"name": "Hotel Atwater", "address": null},
    {"name": "Pier 24", "address": null},
    {"name": "Flx Biergarten", "address": null},
    {"name": "Descanso Beach Club", "address": null}
  ]
}
NOTE: "Pier 24" is a PLACE NAME (a restaurant), NOT an address for "Hotel Atwater"!

=== EXAMPLE 3: Social media handles with addresses (IMPORTANT!) ===
Text:
"1.) @youngbloodcocktails - Inside the Neighborhood is a 3-course cocktail experience
📍 777 G St, San Diego, CA 92101
2.) @bar.kamon - Tucked inside Asa Bakery, this place takes you back to 1920s Japan
📍 634 14th St #110, San Diego, CA 92101
3.) @52remedies - Hidden behind a glowing white door inside Common Theory
📍 4805 Convoy St, San Diego, CA 92111"

Output:
{
  "locations": [
    {"name": "Youngblood Cocktails", "address": "777 G St, San Diego, CA 92101"},
    {"name": "Bar Kamon", "address": "634 14th St #110, San Diego, CA 92101"},
    {"name": "52 Remedies", "address": "4805 Convoy St, San Diego, CA 92111"}
  ]
}
NOTE: Each @handle is converted to a readable business name, and the 📍 address below each entry belongs to that business!

=== RULES ===
- Extract the name EXACTLY as written (we'll verify it later)
- Include ALL places mentioned, not just the first one
- When @handles appear with 📍 addresses, extract ALL of them as separate businesses
- Only associate an address if it contains a street number/name pattern
- If the next line is another place name (not an address), both are separate locations
- If no address is near a location, set address to null
- Strip action words ("Visit the Grand Canyon" → "Grand Canyon")
- Strip meal labels ("Lunch at Cocha" → "Cocha Restaurant" or just "Cocha")
- Convert @handles to readable names: @dolcelunacafe → "Dolce Luna Cafe"
- Return ONLY the JSON object, no other text
''';

      final response = await _callGeminiWithSearchGrounding(prompt);
      
      if (response == null) {
        print('⚠️ RAW EXTRACTION: No response from API');
        return [];
      }
      
      // Parse the response
      final candidates = response['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return [];
      
      final candidate = candidates.first as Map<String, dynamic>;
      final content = candidate['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) return [];
      
      final text = parts.first['text'] as String?;
      if (text == null || text.isEmpty) return [];
      
      // Parse JSON
      String jsonText = text.trim();
      if (jsonText.startsWith('```json')) {
        jsonText = jsonText.substring(7);
      } else if (jsonText.startsWith('```')) {
        jsonText = jsonText.substring(3);
      }
      if (jsonText.endsWith('```')) {
        jsonText = jsonText.substring(0, jsonText.length - 3);
      }
      jsonText = jsonText.trim();
      
      // Handle truncated JSON responses from Gemini API
      // Find all complete location objects and reconstruct valid JSON
      Map<String, dynamic> parsed;
      try {
        parsed = json.decode(jsonText) as Map<String, dynamic>;
      } catch (parseError) {
        print('⚠️ RAW EXTRACTION: JSON parse failed, attempting to recover truncated response...');
        
        // Try to extract complete location objects from truncated JSON
        final recoveredLocations = <Map<String, dynamic>>[];
        
        // Match complete location objects: {"name": "...", "address": ...}
        final locationPattern = RegExp(
          r'\{\s*"name"\s*:\s*"([^"]+)"\s*,\s*"address"\s*:\s*(null|"[^"]*")\s*\}',
          multiLine: true,
        );
        
        for (final match in locationPattern.allMatches(jsonText)) {
          final name = match.group(1);
          final addressRaw = match.group(2);
          if (name != null && name.isNotEmpty) {
            String? address;
            if (addressRaw != null && addressRaw != 'null') {
              // Remove quotes from address
              address = addressRaw.replaceAll('"', '');
            }
            recoveredLocations.add({
              'name': name,
              'address': address,
            });
            print('   🔧 Recovered: "$name"${address != null ? " → $address" : ""}');
          }
        }
        
        if (recoveredLocations.isEmpty) {
          print('❌ RAW EXTRACTION: Could not recover any locations from truncated response');
          rethrow;
        }
        
        print('✅ RAW EXTRACTION: Recovered ${recoveredLocations.length} location(s) from truncated JSON');
        parsed = {'locations': recoveredLocations};
      }
      final locations = parsed['locations'] as List?;
      
      if (locations == null) return [];
      
      // Parse location objects with addresses
      final result = <({String name, String? address})>[];
      for (final loc in locations) {
        if (loc is Map<String, dynamic>) {
          final name = loc['name'] as String?;
          if (name != null && name.isNotEmpty) {
            final address = loc['address'] as String?;
            
            // POST-PROCESSING: Check if the "address" is actually a place name, not a real address
            // Real addresses have patterns like "123 Main St" or "1 Casino Way, Avalon, CA"
            // Place names like "Pier 24", "Flx Biergarten" should NOT be treated as addresses
            if (address != null && !_looksLikeRealAddress(address)) {
              print('   ⚠️ Address "$address" for "$name" looks like a place name, treating as separate location');
              // Add the original location without address
              result.add((name: name.trim(), address: null));
              // Add the "address" as a separate location
              result.add((name: address.trim(), address: null));
            } else {
              result.add((name: name.trim(), address: address?.trim()));
            }
          }
        } else if (loc is String && loc.isNotEmpty) {
          // Fallback for simple string format
          result.add((name: loc.trim(), address: null));
        }
      }
      
      return result;
    } catch (e) {
      print('❌ RAW EXTRACTION ERROR: $e');
      return [];
    }
  }
  
  /// Verify a single location name using Google Search grounding
  Future<ExtractedLocationInfo?> _verifyLocationWithGrounding(
    String locationName,
    ContentContext context,
  ) async {
    try {
      final prompt = '''
I need to verify and find the OFFICIAL name for this place:

PLACE TO VERIFY: "$locationName"

CONTEXT:
- Geographic Area: ${context.geographicFocus ?? "Unknown"}
- Type of place: ${context.locationTypesToFind.join(", ")}

=== YOUR TASK ===
Search online to verify this place exists and find its official name.

For example:
- "Cocha Restaurant" in Baton Rouge → verify it exists, get official name "Cocha"
- "Capitol Park Museum" → verify and confirm "Capitol Park Museum" or "Louisiana State Capitol Park Museum"

=== OUTPUT FORMAT ===
Return a JSON object:
{
  "found": true or false,
  "name": "The official place name",
  "city": "City name",
  "region": "State/Region", 
  "type": "restaurant/museum/park/etc",
  "confidence": "high/medium/low",
  "explanation": "Brief note on verification"
}

If you cannot verify the place exists, return:
{"found": false, "name": null, "explanation": "Why it couldn't be verified"}

=== RULES ===
- Use Google Search to verify the place actually exists
- Return the OFFICIAL business/place name
- Return ONLY the JSON object, no other text
''';

      final response = await _callGeminiWithSearchGrounding(prompt);
      
      if (response == null) return null;
      
      return _parseSearchGroundingResponse(response, context);
    } catch (e) {
      print('❌ VERIFY LOCATION ERROR for "$locationName": $e');
      return null;
    }
  }

  /// Fallback: analyze images individually and merge results
  Future<({List<ExtractedLocationInfo> locations, String? regionContext})> _fallbackIndividualAnalysis(
    List<({Uint8List bytes, String mimeType})> images,
  ) async {
    final allLocations = <ExtractedLocationInfo>[];
    String? regionContext;
    
    for (int i = 0; i < images.length; i++) {
      print('📷 GEMINI MULTI-IMAGE FALLBACK: Analyzing image ${i + 1}/${images.length}...');
      final locations = await extractLocationNamesFromImage(
        images[i].bytes,
        mimeType: images[i].mimeType,
      );
      
      for (final loc in locations) {
        // Update region context if found
        if (loc.regionContext != null && regionContext == null) {
          regionContext = loc.regionContext;
        }
        
        // Deduplicate
        final isDuplicate = allLocations.any((existing) =>
            existing.name.toLowerCase() == loc.name.toLowerCase());
        if (!isDuplicate) {
          allLocations.add(loc);
        }
      }
    }
    
    return (locations: allLocations, regionContext: regionContext);
  }

  /// Call Gemini Vision API with multiple images
  Future<Map<String, dynamic>?> _callGeminiVisionMultiImage(
    String prompt,
    List<({Uint8List bytes, String mimeType})> images,
  ) async {
    final endpoint = '$_baseUrl/models/$_defaultModel:generateContent';
    
    // Build parts list: images first, then prompt
    final parts = <Map<String, dynamic>>[];
    
    // Add each image
    for (int i = 0; i < images.length; i++) {
      final base64Image = base64Encode(images[i].bytes);
      final imageSizeKb = (base64Image.length * 0.75 / 1024).toStringAsFixed(1);
      print('📷 GEMINI MULTI-IMAGE: Image ${i + 1} size ~${imageSizeKb}KB');
      
      parts.add({
        'inlineData': {
          'mimeType': images[i].mimeType,
          'data': base64Image,
        }
      });
    }
    
    // Add text prompt
    parts.add({'text': prompt});
    
    final requestBody = {
      'contents': [
        {'parts': parts}
      ],
      'generationConfig': {
        'temperature': 0.2,
        'topP': 0.9,
        'topK': 50,
        'maxOutputTokens': 4096,
      }
    };

    try {
      print('📷 GEMINI MULTI-IMAGE: Calling API with ${images.length} images...');
      
      final response = await _dio.post(
        '$endpoint?key=$_apiKey',
        data: requestBody,
        options: Options(
          headers: {'Content-Type': 'application/json'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200) {
        print('✅ GEMINI MULTI-IMAGE: API returned 200 OK');
        
        final responseData = response.data as Map<String, dynamic>;
        final candidates = responseData['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final candidate = candidates.first as Map<String, dynamic>;
          final content = candidate['content'] as Map<String, dynamic>?;
          final parts = content?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final text = parts.first['text'] as String?;
            if (text != null) {
              print('📝 GEMINI MULTI-IMAGE Response: ${text.length > 500 ? '${text.substring(0, 500)}...' : text}');
            }
          }
        }
        
        return responseData;
      } else {
        print('❌ GEMINI MULTI-IMAGE: API returned ${response.statusCode}');
        print('   Response: ${jsonEncode(response.data)}');
        return null;
      }
    } on DioException catch (e) {
      print('❌ GEMINI MULTI-IMAGE DIO ERROR: ${e.message}');
      return null;
    }
  }

  /// Extract location names/text from an image using Gemini Vision
  /// 
  /// This uses a TWO-STEP approach for better accuracy:
  /// 
  /// **Step 1: Context Understanding**
  /// - Gemini analyzes the image to understand what it's about
  /// - Determines content type (travel blog, restaurant review, etc.)
  /// - Identifies geographic focus and what types of locations to look for
  /// - Extracts all visible text via OCR
  /// 
  /// **Step 2: Context-Aware Location Extraction**
  /// - Using the context from Step 1, Gemini extracts only RELEVANT locations
  /// - Filters out irrelevant mentions (author's local stores, sponsors, etc.)
  /// - Returns structured location data for Places API verification
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
      print('📷 GEMINI VISION: Starting two-step location extraction...');
      
      // Convert image to base64
      final base64Image = base64Encode(imageBytes);
      
      // ========== STEP 1: CONTEXT UNDERSTANDING ==========
      // First, analyze the image to understand what it's about
      final context = await _analyzeContentContext(base64Image, mimeType);
      
      if (context == null) {
        print('⚠️ GEMINI VISION: Could not analyze context, falling back to single-step extraction');
        // Fallback to original single-step approach
        return _extractLocationsLegacy(base64Image, mimeType);
      }
      
      // ========== STEP 2: CONTEXT-AWARE EXTRACTION ==========
      // Now extract locations using the context understanding
      final locations = await _extractLocationsWithContext(base64Image, mimeType, context);
      
      print('✅ GEMINI VISION: Two-step extraction complete - found ${locations.length} location(s)');
      for (final loc in locations) {
        print('   📍 ${loc.name} ${loc.city != null ? "(${loc.city})" : ""}');
      }
      
      return locations;
    } catch (e, stackTrace) {
      print('❌ GEMINI VISION ERROR: $e');
      print('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Legacy single-step extraction (used as fallback if context analysis fails)
  Future<List<ExtractedLocationInfo>> _extractLocationsLegacy(
    String base64Image,
    String mimeType,
  ) async {
    print('📷 GEMINI VISION (LEGACY): Using single-step extraction...');
    
    final response = await _callGeminiVision(
      _buildImageTextExtractionPrompt(),
      base64Image,
      mimeType,
    );
    
    if (response == null) {
      print('⚠️ GEMINI VISION (LEGACY): No response from API');
      return [];
    }

    // Parse the response to extract location names
    final locations = _parseLocationNamesFromResponse(response);
    
    print('✅ GEMINI VISION (LEGACY): Found ${locations.length} location(s) in image');
    return locations;
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

=== CRITICAL: DETERMINE REGIONAL CONTEXT FIRST ===
Before extracting individual locations, analyze the OVERALL content to determine:
1. What state/country/region is this content primarily about?
2. What is the geographic focus of the content?

This is CRITICAL for disambiguation! For example:
- If the content mentions "Olympic Peninsula", "Hoh Rainforest", "Lake Crescent" → region_context = "Washington"
- If the content mentions "Death Valley", "Joshua Tree", "Palm Springs" → region_context = "California"
- If the content mentions "Yellowstone", "Grand Teton" → region_context = "Wyoming"
- If the content mentions "Zion", "Bryce Canyon" → region_context = "Utah"

The region_context helps disambiguate locations like:
- "Portland" → Could be Oregon OR Maine (region_context tells us which!)
- "Tacoma" → The city in Washington, NOT "Tacomasa" restaurant in California
- "Forks" → The town in Washington (from Twilight), NOT a campground elsewhere
- "Devils Punchbowl" → There are multiple across the US

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

**PRIORITY 3 - HASHTAGS (ONLY for context clues, NOT as location names!):**
- DO NOT extract place/business names from hashtags as locations to return
- Hashtags like #rurukamakura, #cafevibes, #foodie should NOT become location results
- ONLY use hashtags to:
  1. Determine the CITY/REGION context for locations found in Priority 1 & 2
  2. Set the region_context field (e.g., #japan, #california, #washington)
  3. Fill in missing city info (e.g., #kamakura → city: "Kamakura" for a business found above)
- Even if you see #bigsur or #hearstcastle, DO NOT return these as location results
- EXCEPTION: Only extract well-known CITY names from hashtags to use as context (not place names)

**COMPLETELY IGNORE - DO NOT EXTRACT:**
- "More posts from [username]" section at the bottom
- Small thumbnail images in the "More posts from" grid
- Any text from these thumbnail images
- Suggested accounts or "You might also like" sections

=== CRITICAL: DO NOT HALLUCINATE OR INFER LOCATIONS ===
ONLY extract locations that are EXPLICITLY VISIBLE in the image. DO NOT:
- Infer cities from a county/region name (seeing "#OrangeCounty" does NOT mean extract Anaheim, Fullerton, Santa Ana, Orange, etc.)
- Generate related or nearby cities that aren't explicitly shown
- Expand a region into its constituent cities
- Add cities you "know" are in a region if they're not visible in the image
- Make up locations based on your knowledge of an area

If you see "#OrangeCounty" or "#SoCal", use that ONLY for region_context, do NOT return individual cities unless they are EXPLICITLY written/visible in the image!

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

=== CRITICAL: AREA CODES IN HANDLES REVEAL LOCATION ===
Many business Instagram handles include their area code, which tells you the city!
Extract the area code and use it to set the city field:

COMMON AREA CODES TO RECOGNIZE:
- 206, 253, 425 → Seattle, Washington
- 310, 323, 213, 818 → Los Angeles, California  
- 415, 628 → San Francisco, California
- 212, 646, 917 → New York City, New York
- 312, 773 → Chicago, Illinois
- 305, 786 → Miami, Florida
- 214, 972 → Dallas, Texas
- 713, 281 → Houston, Texas
- 602, 480 → Phoenix, Arizona
- 404, 678 → Atlanta, Georgia
- 617 → Boston, Massachusetts
- 202 → Washington D.C.
- 503 → Portland, Oregon
- 619, 858 → San Diego, California
- 949, 714 → Orange County, California
- 303, 720 → Denver, Colorado
- 702 → Las Vegas, Nevada
- 512 → Austin, Texas

EXAMPLES:
- "@rockcreek206" → name: "RockCreek", city: "Seattle" (206 = Seattle area code)
- "@pizzashop312" → name: "Pizza Shop", city: "Chicago" (312 = Chicago area code)
- "@taco_stand_619" → name: "Taco Stand", city: "San Diego" (619 = San Diego area code)
- "@bakery_pdx503" → name: "Bakery PDX", city: "Portland" (503 = Portland area code)

When you see a 3-digit number in a handle, check if it's an area code!

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
Return a JSON object with this exact structure:
{
  "region_context": "The state or region this content is primarily about (e.g., 'Washington', 'California', 'Oregon', 'Olympic Peninsula, WA'). This is CRITICAL for disambiguating location searches. If content mentions Seattle, Tacoma, Olympic National Park, etc., region_context should be 'Washington'. Set to null ONLY if you cannot determine a specific region.",
  "locations": [
    {
      "name": "Business or Place Name (converted from handle if applicable)",
      "address": "Street address if visible (or null)",
      "city": "City name if visible (or null)", 
      "type": "restaurant/cafe/store/attraction/park/trail/landmark/region",
      "original_handle": "The ORIGINAL @handle as it appeared in the image (e.g., '@sofaseattle'), or null if name didn't come from a handle. CRITICAL: Include the @ symbol!"
    }
  ]
}

CRITICAL: When the name came from an Instagram handle, you MUST include the original_handle field!
- If you see "@sofaseattle" → name: "Sofa Seattle", original_handle: "@sofaseattle"
- If you see "@rockcreek206" → name: "RockCreek", original_handle: "@rockcreek206"  
- If you see "Pike Place Market" (not a handle) → name: "Pike Place Market", original_handle: null

=== EXAMPLES ===
**WASHINGTON STATE TRAVEL GUIDE EXAMPLE:**
If you see content mentioning: "Lake Crescent", "Sol Duc Falls", "Hoh Rainforest", "Ruby Beach", "Forks", "Seattle", "Tacoma", "Port Angeles"
Return:
{
  "region_context": "Washington",
  "locations": [
    {"name": "Lake Crescent", "address": null, "city": null, "type": "park"},
    {"name": "Sol Duc Falls", "address": null, "city": null, "type": "landmark"},
    {"name": "Hoh Rainforest", "address": null, "city": null, "type": "park"},
    {"name": "Ruby Beach", "address": null, "city": null, "type": "landmark"},
    {"name": "Forks", "address": null, "city": null, "type": "region"},
    {"name": "Seattle", "address": null, "city": null, "type": "region"},
    {"name": "Tacoma", "address": null, "city": null, "type": "region"},
    {"name": "Port Angeles", "address": null, "city": null, "type": "region"}
  ]
}
NOTE: With region_context "Washington", the search for "Tacoma" will find "Tacoma, WA" not "Tacomasa" restaurant in California!

**YOUTUBE EXAMPLE (IMPORTANT!):**
If you see a YouTube video with:
- Title: "Top 10 Orange County Restaurants I've Tried in 2025"  
- Overlaid text on thumbnail: "PARLOR SAN CLEMENTE" (with a pizza image)
Return ONLY the specific restaurant, NOT "Orange County":
{
  "region_context": "Orange County, California",
  "locations": [
    {"name": "Parlor", "address": null, "city": "San Clemente", "type": "restaurant"}
  ]
}
DO NOT return: {"name": "Orange County", ...} - this is too broad!

**CALIFORNIA ROAD TRIP EXAMPLE:**
If you see a list like:
"📍 Point Buchon Trail in Los Osos
📍 Hearst Castle in San Simeon
📍 Bixby Bridge
#california #roadtrip"
Return:
{
  "region_context": "California",
  "locations": [
    {"name": "Point Buchon Trail", "address": null, "city": "Los Osos", "type": "trail"},
    {"name": "Hearst Castle", "address": null, "city": "San Simeon", "type": "landmark"},
    {"name": "Bixby Bridge", "address": null, "city": null, "type": "landmark"}
  ]
}

=== CRITICAL: IDENTIFY THE SUBJECT, NOT JUST THE LOCATION ===
When a post describes "this restaurant at X", "this cafe at X", "a food place at X":
- The SUBJECT is the restaurant/cafe, NOT just X (the general location)
- Try to identify the SPECIFIC place being featured

EXAMPLE - THEMED RESTAURANTS:
If description says: "This Toy Story themed restaurant at Hollywood Studios is so much fun!"
- The SUBJECT is a "Toy Story themed restaurant" (which is "Roundup Rodeo BBQ")
- NOT just "Hollywood Studios" (the theme park)
Return:
{
  "region_context": "Florida",
  "locations": [
    {"name": "Toy Story themed restaurant at Hollywood Studios", "address": null, "city": null, "type": "restaurant", "context_hint": "Toy Story themed restaurant at Hollywood Studios Florida"}
  ]
}

EXAMPLE - SPECIFIC PLACE AT GENERAL LOCATION:
If description says: "Best coffee shop inside the Seattle airport"
- Return: {"name": "coffee shop at Seattle airport", "type": "cafe", "context_hint": "best coffee shop Seattle airport"}
- NOT just: {"name": "Seattle-Tacoma International Airport", "type": "airport"}

When you can't identify the specific name but know the TYPE and CONTEXT:
- Set type to the specific type (restaurant, cafe, bar, etc.)
- Add "context_hint" field with searchable description (e.g., "Toy Story restaurant Hollywood Studios Florida")
- This helps us search for the specific place online

=== CRITICAL: STRIP ACTION WORDS FROM LOCATION NAMES ===
Video content often has call-to-action text like "Drive [location]", "Visit [location]", "Explore [location]".
ALWAYS strip these action/imperative words from the beginning of location names:
- "Drive Kancamagus Highway" → "Kancamagus Highway"
- "Visit Grand Canyon" → "Grand Canyon"
- "Explore Yosemite" → "Yosemite"
- "Go to Pike Place Market" → "Pike Place Market"
- "Check out Joshua Tree" → "Joshua Tree"
- "Discover Big Sur" → "Big Sur"
- "Experience Zion National Park" → "Zion National Park"
- "Tour Alcatraz Island" → "Alcatraz Island"
- "See the Golden Gate Bridge" → "Golden Gate Bridge"
- "Head to Lake Tahoe" → "Lake Tahoe"
- "Stop by Hearst Castle" → "Hearst Castle"

Words to STRIP from the beginning: Drive, Visit, Explore, Go to, Check out, Discover, Experience, Tour, See, Head to, Stop by, Take a trip to, Hike, Swim at, Eat at, Dine at, Stay at

=== RULES ===
- ALWAYS strip action/imperative words from the beginning of location names (see above)
- ALWAYS determine region_context FIRST before extracting locations
- ALWAYS convert @handles to proper business names
- PRIORITIZE specific places (restaurants, cafes) over general locations (theme parks, malls)
- When description mentions "this restaurant/cafe/bar at X", focus on finding the SPECIFIC place
- Extract EVERY distinct location mentioned (from Priority 1 and 2 sections)
- Include partial information - even just a business name is useful
- For video text overlays, read character by character if needed
- Prioritize text that appears to name specific places
- SKIP generic regions/states/countries/counties if specific locations exist
- For YouTube: text OVERLAID on the video thumbnail is MORE important than the video title
- For YouTube: NEVER return just a county/region name if a business name is visible on the thumbnail
- IGNORE "More posts from" section and its thumbnails entirely
- NEVER extract place names from hashtags - hashtags are ONLY for city/region context
- If you only see a place name in a hashtag (e.g., #rurukamakura), do NOT return it as a location
- NEVER HALLUCINATE or INFER cities - only extract what is EXPLICITLY VISIBLE
- DO NOT expand #OrangeCounty or similar into Anaheim, Fullerton, Santa Ana, etc.
- Return ONLY the JSON object with region_context and locations array, no other text
- If absolutely no locations found, return: {"region_context": null, "locations": []}
''';
  }

  /// Build prompt for Step 1: Context Analysis
  /// This analyzes the image to understand what it's about BEFORE extracting locations
  String _buildContextAnalysisPrompt() {
    return '''
You are an expert content analyst. Your job is to UNDERSTAND what this image/screenshot is about BEFORE we extract any locations.

=== YOUR TASK ===
Analyze this image and tell me:
1. What TYPE of content is this? (social media post, travel blog screenshot, list article, restaurant review, map, etc.)
2. What is the PURPOSE/THEME? (e.g., "top restaurants in a city", "road trip itinerary", "food recommendations", "travel guide")
3. What GEOGRAPHIC REGION is this focused on? (city, state, country, or area)
4. What TYPES of locations should we look for? (restaurants, cafes, hotels, attractions, trails, landmarks, etc.)
5. Any CRITERIA or filters mentioned? (budget, family-friendly, Michelin-starred, hidden gems, etc.)
6. What should we EXCLUDE? (author's local stores, sponsor mentions, unrelated locations)
7. Extract any visible TEXT that might contain location names (OCR the image)

=== IMPORTANT ===
- DO NOT extract or list specific locations yet - that's the next step
- Focus on UNDERSTANDING the content first
- Read ALL visible text in the image using OCR
- Identify the context so we know what to look for

=== OUTPUT FORMAT ===
Return a JSON object with this structure:
{
  "content_type": "Type of content (e.g., 'Instagram travel post', 'YouTube video screenshot', 'food blog list')",
  "purpose": "What is this content trying to share? (e.g., 'Top 10 restaurants in San Francisco', 'Hidden gem cafes to try')",
  "geographic_focus": "The main region/city/area (e.g., 'San Francisco, California', 'Olympic Peninsula, Washington') or null if unclear",
  "location_types_to_find": ["restaurant", "cafe", "attraction"],
  "criteria": ["budget-friendly", "family-friendly"],
  "context_clues": ["mentions 'best of 2024'", "author is a food blogger", "focused on Italian cuisine"],
  "exclusions": ["grocery stores mentioned for trip prep", "author's hometown recommendations"],
  "extracted_text": "ALL visible text from the image that might contain location names or addresses. Include post captions, titles, overlay text, signs, etc."
}

=== EXAMPLES ===

**Example 1: Instagram food post**
{
  "content_type": "Instagram food post",
  "purpose": "Recommending a specific restaurant",
  "geographic_focus": "San Clemente, California",
  "location_types_to_find": ["restaurant", "pizzeria"],
  "criteria": [],
  "context_clues": ["shows pizza", "tagged location visible"],
  "exclusions": [],
  "extracted_text": "PARLOR SAN CLEMENTE - Best pizza on the coast! 📍 San Clemente..."
}

**Example 2: Travel blog screenshot**
{
  "content_type": "Travel blog article screenshot",
  "purpose": "3-day Death Valley itinerary with places to visit and stay",
  "geographic_focus": "Death Valley, California",
  "location_types_to_find": ["hotel", "campground", "viewpoint", "attraction", "restaurant"],
  "criteria": ["must-see spots", "places to stay"],
  "context_clues": ["day-by-day itinerary", "includes accommodations"],
  "exclusions": ["author's local grocery stores for trip prep", "Amazon links for supplies"],
  "extracted_text": "Day 1: Zabriskie Point, Badwater Basin, Artist's Palette. Stay at The Inn at Death Valley..."
}

**Example 3: YouTube video thumbnail**
{
  "content_type": "YouTube video thumbnail/screenshot",
  "purpose": "Top 10 restaurants in Orange County",
  "geographic_focus": "Orange County, California",
  "location_types_to_find": ["restaurant"],
  "criteria": ["ranked list", "best of"],
  "context_clues": ["video title mentions 'Top 10'", "thumbnail shows restaurant interior"],
  "exclusions": [],
  "extracted_text": "TOP 10 ORANGE COUNTY RESTAURANTS 2025 - Parlor San Clemente shown on thumbnail"
}

=== RULES ===
- Focus on understanding, not extracting locations yet
- Be thorough with OCR - read ALL text in the image
- Identify the geographic scope to help filter relevant locations later
- Return ONLY the JSON object, no other text
''';
  }

  /// Build prompt for Step 2: Context-Aware Location Extraction
  /// Uses the context from Step 1 to extract only relevant locations
  String _buildContextAwareLocationExtractionPrompt(ContentContext context) {
    return '''
You are an expert at extracting location information. Based on the context analysis below, extract ONLY the locations that are RELEVANT to this content.

=== CONTEXT ANALYSIS (from Step 1) ===
${context.toPromptSummary()}

${context.extractedText != null ? '''=== EXTRACTED TEXT FROM IMAGE ===
${context.extractedText}
''' : ''}

=== YOUR TASK ===
Based on the context above, extract ONLY the locations that match:
- The PURPOSE: ${context.purpose}
- The GEOGRAPHIC FOCUS: ${context.geographicFocus ?? 'Not specified'}
- The TYPES TO FIND: ${context.locationTypesToFind.join(', ')}

=== WHAT TO EXTRACT ===
✅ INCLUDE:
- Specific businesses, restaurants, cafes, hotels mentioned as recommendations
- Attractions, landmarks, viewpoints that are part of the main content
- Any place that matches the purpose: "${context.purpose}"
${context.criteria.isNotEmpty ? '- Places matching these criteria: ${context.criteria.join(", ")}' : ''}

❌ EXCLUDE:
- Locations outside the geographic focus (${context.geographicFocus ?? 'any region'})
${context.exclusions.map((e) => '- $e').join('\n')}
- Generic region names if specific places exist (don't return "Orange County" if "Parlor San Clemente" is mentioned)
- Author's local/personal recommendations unrelated to the main content
- Sponsor mentions or ads
- Hashtags as locations (hashtags are ONLY for context, not location results)

=== HANDLE CONVERSION RULES ===
If you see @handles, convert them to business names:
- "@oldferrydonut.us" → "Old Ferry Donut"
- "@kuyalord_la" → "Kuya Lord" (remove _la suffix, split concatenated words)
- Remove: _la, _nyc, _sf, .us, .co, .official suffixes
- Replace dots/underscores with spaces, apply Title Case

=== OUTPUT FORMAT ===
{
  "region_context": "${context.geographicFocus ?? 'null'}",
  "locations": [
    {
      "name": "Business or Place Name",
      "address": "Street address if visible (or null)",
      "city": "City name if visible (or null)",
      "type": "restaurant/cafe/hotel/attraction/park/trail/landmark",
      "original_handle": "@handle if name came from a handle (or null)",
      "relevance_reason": "Brief explanation of why this matches the context"
    }
  ]
}

=== RULES ===
- ONLY extract locations that match the context analysis
- Each location should have a "relevance_reason" explaining why it belongs
- Strip action words from names ("Visit Grand Canyon" → "Grand Canyon")
- Convert @handles to proper business names
- Return ONLY the JSON object, no other text
- If no relevant locations found, return: {"region_context": null, "locations": []}
''';
  }

  /// Step 1: Analyze image context to understand what it's about
  Future<ContentContext?> _analyzeContentContext(
    String base64Image,
    String mimeType,
  ) async {
    try {
      print('🔍 GEMINI VISION STEP 1: Analyzing content context...');
      
      final response = await _callGeminiVision(
        _buildContextAnalysisPrompt(),
        base64Image,
        mimeType,
      );
      
      if (response == null) {
        print('⚠️ GEMINI VISION STEP 1: No response from API');
        return null;
      }
      
      // Parse the context response
      final context = _parseContextResponse(response);
      
      if (context != null) {
        print('✅ GEMINI VISION STEP 1: Context analyzed');
        print('   📋 Content Type: ${context.contentType}');
        print('   🎯 Purpose: ${context.purpose}');
        print('   🌍 Geographic Focus: ${context.geographicFocus ?? "Not specified"}');
        print('   🔍 Looking for: ${context.locationTypesToFind.join(", ")}');
        if (context.extractedText != null && context.extractedText!.isNotEmpty) {
          final previewLength = context.extractedText!.length > 200 ? 200 : context.extractedText!.length;
          print('   📝 Extracted text: ${context.extractedText!.substring(0, previewLength)}...');
        }
      }
      
      return context;
    } catch (e, stackTrace) {
      print('❌ GEMINI VISION STEP 1 ERROR: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Parse the context analysis response from Gemini
  ContentContext? _parseContextResponse(Map<String, dynamic> response) {
    try {
      final candidates = response['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return null;
      
      final candidate = candidates.first as Map<String, dynamic>;
      final content = candidate['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) return null;
      
      final text = parts.first['text'] as String?;
      if (text == null || text.isEmpty) return null;
      
      // Parse JSON
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
      
      final parsed = jsonDecode(jsonText) as Map<String, dynamic>;
      
      // Parse business handles - clean them up (remove @ if present)
      final rawBusinessHandles = (parsed['business_handles'] as List?)
          ?.map((e) => e.toString().replaceAll('@', '').trim())
          .where((h) => h.isNotEmpty)
          .toList() ?? [];
      
      // Parse content creator handle - clean it up
      String? creatorHandle = parsed['content_creator_handle'] as String?;
      if (creatorHandle != null) {
        creatorHandle = creatorHandle.replaceAll('@', '').trim();
        if (creatorHandle.isEmpty) creatorHandle = null;
      }
      
      // Parse search query suggestion
      String? searchQuerySuggestion = parsed['search_query_suggestion'] as String?;
      if (searchQuerySuggestion != null) {
        searchQuerySuggestion = searchQuerySuggestion.trim();
        if (searchQuerySuggestion.isEmpty) searchQuerySuggestion = null;
      }
      
      // Parse explicitly mentioned place names
      final mentionedPlaceNames = (parsed['mentioned_place_names'] as List?)
          ?.map((e) => e.toString().trim())
          .where((p) => p.isNotEmpty)
          .toList() ?? [];

      return ContentContext(
        contentType: parsed['content_type'] as String? ?? 'unknown',
        purpose: parsed['purpose'] as String? ?? 'unknown',
        geographicFocus: parsed['geographic_focus'] as String?,
        locationTypesToFind: (parsed['location_types_to_find'] as List?)
            ?.map((e) => e.toString())
            .toList() ?? ['restaurant', 'cafe', 'attraction'],
        criteria: (parsed['criteria'] as List?)
            ?.map((e) => e.toString())
            .toList() ?? [],
        contextClues: (parsed['context_clues'] as List?)
            ?.map((e) => e.toString())
            .toList() ?? [],
        exclusions: (parsed['exclusions'] as List?)
            ?.map((e) => e.toString())
            .toList() ?? [],
        extractedText: parsed['extracted_text'] as String?,
        contentCreatorHandle: creatorHandle,
        businessHandles: rawBusinessHandles,
        searchQuerySuggestion: searchQuerySuggestion,
        mentionedPlaceNames: mentionedPlaceNames,
      );
    } catch (e) {
      print('⚠️ GEMINI VISION: Error parsing context response: $e');
      return null;
    }
  }

  /// Step 2: Extract locations using the context from Step 1
  Future<List<ExtractedLocationInfo>> _extractLocationsWithContext(
    String base64Image,
    String mimeType,
    ContentContext context,
  ) async {
    try {
      print('🔍 GEMINI VISION STEP 2: Extracting locations with context...');
      
      final response = await _callGeminiVision(
        _buildContextAwareLocationExtractionPrompt(context),
        base64Image,
        mimeType,
      );
      
      if (response == null) {
        print('⚠️ GEMINI VISION STEP 2: No response from API');
        return [];
      }
      
      // Parse locations using existing method
      final locations = _parseLocationNamesFromResponse(response);
      
      print('✅ GEMINI VISION STEP 2: Found ${locations.length} relevant location(s)');
      for (final loc in locations) {
        print('   📍 ${loc.name} ${loc.city != null ? "(${loc.city})" : ""}');
      }
      
      return locations;
    } catch (e, stackTrace) {
      print('❌ GEMINI VISION STEP 2 ERROR: $e');
      print('Stack trace: $stackTrace');
      return [];
    }
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
          jsonText == '{"region_context": null, "locations": []}' ||
          jsonText.toLowerCase().contains('no location') ||
          jsonText.toLowerCase().contains('no places')) {
        print('📷 GEMINI VISION: No locations found in image');
        return results;
      }
      
      // Parse JSON - can be either array (legacy) or object with region_context (new format)
      final parsed = jsonDecode(jsonText);
      
      String? regionContext;
      List<dynamic>? locationsList;
      
      if (parsed is Map<String, dynamic>) {
        // New format: { "region_context": "...", "locations": [...] }
        regionContext = parsed['region_context'] as String?;
        locationsList = parsed['locations'] as List?;
        
        if (regionContext != null && regionContext.isNotEmpty) {
          print('🌍 GEMINI VISION: Detected region context: "$regionContext"');
        }
      } else if (parsed is List) {
        // Legacy format: just an array
        locationsList = parsed;
      }
      
      if (locationsList != null) {
        for (final item in locationsList) {
          if (item is Map<String, dynamic>) {
            String? name = item['name'] as String?;
            if (name != null && name.isNotEmpty) {
              // Extract original handle if present (for later lookup)
              String? originalHandle = item['original_handle'] as String?;
              
              // Extract context hint if present (for searching when name is vague)
              String? contextHint = item['context_hint'] as String?;
              
              // Clean up the name - convert handles to business names if needed
              name = _convertHandleToBusinessName(name);
              
              // Strip action words from the beginning (e.g., "Drive Kancamagus Highway" → "Kancamagus Highway")
              name = _stripActionWordsFromName(name);
              
              // Log if we have a handle for debugging
              if (originalHandle != null && originalHandle.isNotEmpty) {
                print('📱 GEMINI VISION: Name "$name" came from handle: $originalHandle');
              }
              
              // Log if we have a context hint for debugging
              if (contextHint != null && contextHint.isNotEmpty) {
                print('🔍 GEMINI VISION: Context hint for "$name": "$contextHint"');
              }
              
              results.add(ExtractedLocationInfo(
                name: name,
                address: item['address'] as String?,
                city: item['city'] as String?,
                type: item['type'] as String?,
                regionContext: regionContext, // Pass region context to each location
                originalHandle: originalHandle,
                contextHint: contextHint,
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

  /// Strip action/imperative words from the beginning of location names
  /// e.g., "Drive Kancamagus Highway" → "Kancamagus Highway"
  /// e.g., "Visit Grand Canyon" → "Grand Canyon"
  String _stripActionWordsFromName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return trimmed;
    
    // Action words to strip from the beginning (case-insensitive)
    // Order matters - longer phrases first to avoid partial matches
    final actionPhrases = [
      'take a trip to',
      'go to',
      'head to',
      'stop by',
      'check out',
      'swim at',
      'eat at',
      'dine at',
      'stay at',
      'hike',
      'drive',
      'visit',
      'explore',
      'discover',
      'experience',
      'tour',
      'see',
    ];
    
    final lowerName = trimmed.toLowerCase();
    
    for (final phrase in actionPhrases) {
      if (lowerName.startsWith(phrase)) {
        // Check if followed by a space (to avoid stripping "Driveway" from "Driveway Inn")
        final afterPhrase = trimmed.substring(phrase.length);
        if (afterPhrase.isEmpty) continue; // Nothing left after stripping
        
        // Must be followed by whitespace
        if (afterPhrase.startsWith(' ') || afterPhrase.startsWith('\t')) {
          final strippedName = afterPhrase.trim();
          if (strippedName.isNotEmpty) {
            print('📝 ACTION WORD STRIPPED: "$trimmed" → "$strippedName"');
            return strippedName;
          }
        }
      }
    }
    
    return trimmed;
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

  // ============ AI RERANKING METHODS ============

  /// Rerank Places API candidates using AI when initial scoring is weak
  /// 
  /// This method uses Gemini to compare multiple place candidates and select
  /// the best match based on semantic understanding of the context.
  /// 
  /// [originalLocationCue] - The original location name/handle/context being searched
  /// [candidates] - List of Places API results to rerank (top N, typically 5-8)
  /// [regionContext] - Geographic context (e.g., "Seattle, WA", "California")
  /// [surroundingText] - Caption text, page content, or other contextual text
  /// [expectedType] - The expected type of place (restaurant, hotel, park, etc.)
  /// [userLocationBias] - Optional user location for disambiguation
  /// 
  /// Returns the index of the best candidate (0-based), or -1 if none fit well
  Future<({int selectedIndex, double confidence, String? reason})> rerankPlaceCandidates({
    required String originalLocationCue,
    required List<Map<String, dynamic>> candidates,
    String? regionContext,
    String? surroundingText,
    String? expectedType,
    LatLng? userLocationBias,
  }) async {
    if (!isConfigured) {
      print('⚠️ GEMINI RERANK: API key not configured');
      return (selectedIndex: 0, confidence: 0.5, reason: 'API not configured');
    }

    if (candidates.isEmpty) {
      return (selectedIndex: -1, confidence: 0.0, reason: 'No candidates');
    }

    if (candidates.length == 1) {
      // Only one candidate, return it but with moderate confidence
      return (selectedIndex: 0, confidence: 0.6, reason: 'Single candidate');
    }

    try {
      print('🤖 GEMINI RERANK: Reranking ${candidates.length} candidates for "$originalLocationCue"');
      
      // STEP 1: Get search-grounded description for better context
      // This uses Google Search to understand what the place ACTUALLY is
      print('🔍 GEMINI RERANK: Getting search-grounded description first...');
      final groundedDescription = await getSearchGroundedDescription(
        placeName: originalLocationCue,
        regionContext: regionContext,
        expectedType: expectedType,
      );
      
      if (groundedDescription != null) {
        print('✅ GEMINI RERANK: Got grounded description for context');
      } else {
        print('⚠️ GEMINI RERANK: No grounded description available, using basic context');
      }
      
      // Build candidate descriptions for the prompt
      final candidateDescriptions = StringBuffer();
      for (int i = 0; i < candidates.length && i < 8; i++) {
        final candidate = candidates[i];
        final name = candidate['name'] ?? candidate['description']?.toString().split(',').first ?? 'Unknown';
        final address = candidate['address'] ?? candidate['description'] ?? '';
        final types = (candidate['types'] as List?)?.cast<String>() ?? [];
        
        candidateDescriptions.writeln('[$i] $name');
        candidateDescriptions.writeln('    Address: $address');
        if (types.isNotEmpty) {
          candidateDescriptions.writeln('    Types: ${types.take(5).join(", ")}');
        }
        candidateDescriptions.writeln();
      }

      final prompt = '''
You are an expert at matching location search results to the intended place.

=== SEARCH CONTEXT ===
Original search term: "$originalLocationCue"
${regionContext != null ? 'Region/Area: $regionContext' : ''}
${expectedType != null ? 'Expected place type: $expectedType' : ''}
${groundedDescription != null ? '''

=== VERIFIED PLACE INFORMATION (from web search) ===
$groundedDescription
''' : ''}
${surroundingText != null && surroundingText.isNotEmpty ? '''

Surrounding context from content:
"""
${surroundingText.length > 500 ? '${surroundingText.substring(0, 500)}...' : surroundingText}
"""
''' : ''}

=== CANDIDATES ===
${candidateDescriptions.toString()}

=== TASK ===
Select the candidate that best matches the search context. ${groundedDescription != null ? 'Use the VERIFIED PLACE INFORMATION above to identify the correct match.' : ''}

Consider:
1. Name similarity to the search term (exact matches preferred)
2. Whether the place type matches the expected type
3. Geographic relevance (matches the region context)
${groundedDescription != null ? '4. Match to the verified place information - this is the MOST RELIABLE source' : '4. Semantic relevance to the surrounding context'}

RESPOND WITH ONLY A JSON OBJECT in this exact format:
{
  "selected_index": <number from 0 to ${candidates.length - 1}, or -1 if none fit>,
  "confidence": <number from 0.0 to 1.0>,
  "reason": "<brief explanation of why this was selected or why none fit>"
}

If the search term appears to be a social media handle and none of the candidates match that business, return -1.
If the search seems to be for a specific named business and none match, return -1.
''';

      final response = await _callGeminiDirect(prompt);
      
      if (response == null) {
        print('⚠️ GEMINI RERANK: No response from API');
        return (selectedIndex: 0, confidence: 0.5, reason: 'API returned no response');
      }

      // Parse the response
      final result = _parseRerankResponse(response);
      
      print('✅ GEMINI RERANK: Selected index ${result.selectedIndex} with confidence ${result.confidence}');
      if (result.reason != null) {
        print('   Reason: ${result.reason}');
      }
      
      return result;
    } catch (e) {
      print('❌ GEMINI RERANK ERROR: $e');
      return (selectedIndex: 0, confidence: 0.5, reason: 'Error: $e');
    }
  }

  /// Parse the rerank response from Gemini
  ({int selectedIndex, double confidence, String? reason}) _parseRerankResponse(
    Map<String, dynamic> response,
  ) {
    try {
      // Extract the text content from Gemini response
      final candidates = response['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        return (selectedIndex: 0, confidence: 0.5, reason: 'No candidates in response');
      }

      final content = candidates[0]['content'] as Map<String, dynamic>?;
      if (content == null) {
        return (selectedIndex: 0, confidence: 0.5, reason: 'No content in response');
      }

      final parts = content['parts'] as List?;
      if (parts == null || parts.isEmpty) {
        return (selectedIndex: 0, confidence: 0.5, reason: 'No parts in response');
      }

      final text = parts[0]['text'] as String? ?? '';
      
      // Extract JSON from the response
      final jsonMatch = RegExp(r'\{[^}]+\}').firstMatch(text);
      if (jsonMatch == null) {
        print('⚠️ GEMINI RERANK: Could not find JSON in response: $text');
        return (selectedIndex: 0, confidence: 0.5, reason: 'Could not parse response');
      }

      final jsonStr = jsonMatch.group(0)!;
      final parsed = json.decode(jsonStr) as Map<String, dynamic>;
      
      final selectedIndex = (parsed['selected_index'] as num?)?.toInt() ?? 0;
      final confidence = (parsed['confidence'] as num?)?.toDouble() ?? 0.5;
      final reason = parsed['reason'] as String?;
      
      return (selectedIndex: selectedIndex, confidence: confidence, reason: reason);
    } catch (e) {
      print('⚠️ GEMINI RERANK: Error parsing response: $e');
      return (selectedIndex: 0, confidence: 0.5, reason: 'Parse error: $e');
    }
  }

  /// Get a search-grounded description of a place for better reranking context
  /// 
  /// Uses Google Search grounding to get real-world information about what a place
  /// actually is, which helps disambiguate between similar-sounding candidates.
  /// 
  /// For example:
  /// - "Hole-in-the-Wall" → "Hole-in-the-Wall is a sea-carved arch on the Olympic Peninsula coast..."
  /// - "Cape Flattery" → "Cape Flattery is the northwesternmost point of the contiguous US..."
  Future<String?> getSearchGroundedDescription({
    required String placeName,
    String? regionContext,
    String? expectedType,
  }) async {
    if (!isConfigured) {
      print('⚠️ GEMINI GROUNDED DESC: API key not configured');
      return null;
    }

    try {
      print('🔍 GEMINI GROUNDED DESC: Getting description for "$placeName"...');
      
      final prompt = '''
I need a brief factual description of this place to help identify it among search results.

PLACE NAME: $placeName
${regionContext != null ? 'REGION CONTEXT: $regionContext' : ''}
${expectedType != null ? 'EXPECTED TYPE: $expectedType' : ''}

=== YOUR TASK ===
Search online and provide a 1-2 sentence factual description of this place that includes:
1. What type of place it is (landmark, beach, restaurant, park, etc.)
2. Its specific location (city, state, or notable nearby landmarks)
3. What makes it distinctive or recognizable

=== OUTPUT FORMAT ===
Return ONLY a JSON object:
{
  "found": true or false,
  "description": "Brief factual description of the place",
  "official_name": "The official/full name if different from search term",
  "location_details": "Specific location info (city, state, nearby landmarks)"
}

If you cannot find reliable information about this specific place, return:
{"found": false, "description": null}

=== RULES ===
- Use Google Search to find accurate, current information
- Be specific - distinguish between places with similar names
- Focus on facts that help identify THIS specific place vs others with similar names
- Return ONLY the JSON object, no other text
''';

      final response = await _callGeminiWithSearchGrounding(prompt);
      
      if (response == null) {
        print('⚠️ GEMINI GROUNDED DESC: No response from API');
        return null;
      }

      // Parse the response to extract description
      final candidates = response['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return null;

      final candidate = candidates.first as Map<String, dynamic>;
      final content = candidate['content'] as Map<String, dynamic>?;
      if (content == null) return null;

      final parts = content['parts'] as List?;
      if (parts == null || parts.isEmpty) return null;

      final text = parts.first['text'] as String? ?? '';
      
      // Extract JSON from response
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (jsonMatch == null) {
        print('⚠️ GEMINI GROUNDED DESC: Could not find JSON in response');
        return null;
      }

      try {
        final parsed = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
        final found = parsed['found'] as bool? ?? false;
        
        if (!found) {
          print('⚠️ GEMINI GROUNDED DESC: Place not found via search');
          return null;
        }

        final description = parsed['description'] as String?;
        final officialName = parsed['official_name'] as String?;
        final locationDetails = parsed['location_details'] as String?;
        
        // Build a comprehensive description string
        final descParts = <String>[];
        if (officialName != null && officialName.isNotEmpty && officialName.toLowerCase() != placeName.toLowerCase()) {
          descParts.add('Official name: $officialName');
        }
        if (description != null && description.isNotEmpty) {
          descParts.add(description);
        }
        if (locationDetails != null && locationDetails.isNotEmpty) {
          descParts.add('Location: $locationDetails');
        }
        
        final fullDescription = descParts.join('. ');
        
        if (fullDescription.isNotEmpty) {
          print('✅ GEMINI GROUNDED DESC: "$fullDescription"');
          return fullDescription;
        }
        
        return null;
      } catch (e) {
        print('⚠️ GEMINI GROUNDED DESC: Error parsing response: $e');
        return null;
      }
    } catch (e) {
      print('❌ GEMINI GROUNDED DESC ERROR: $e');
      return null;
    }
  }

  /// Call Gemini API directly without any grounding (for simple text analysis)
  Future<Map<String, dynamic>?> _callGeminiDirect(String prompt) async {
    final endpoint = '$_baseUrl/models/$_defaultModel:generateContent';

    final requestBody = {
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.1,  // Low temperature for more deterministic responses
        'maxOutputTokens': 256,  // Keep responses short
      },
    };

    try {
      final response = await _dio.post(
        '$endpoint?key=$_apiKey',
        data: requestBody,
        options: Options(
          headers: {'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      } else {
        print('❌ GEMINI DIRECT: API returned status ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ GEMINI DIRECT ERROR: $e');
      return null;
    }
  }

  // ============ END AI RERANKING METHODS ============
}

/// Simple class to hold extracted location info from images
class ExtractedLocationInfo {
  final String name;
  final String? address;
  final String? city;
  final String? type;
  /// Regional context extracted from the overall content (e.g., "Washington", "Olympic Peninsula, WA")
  /// This helps disambiguate locations when searching Places API
  final String? regionContext;
  /// Original Instagram/social media handle if the name was derived from one
  /// e.g., "@sofaseattle" - useful for looking up the actual business name online
  final String? originalHandle;
  /// Context hint for searching when the specific name isn't known
  /// e.g., "Toy Story themed restaurant at Hollywood Studios Florida"
  /// Used to do a Google Search to find the actual place name
  final String? contextHint;

  ExtractedLocationInfo({
    required this.name,
    this.address,
    this.city,
    this.type,
    this.regionContext,
    this.originalHandle,
    this.contextHint,
  });

  @override
  String toString() => 'ExtractedLocationInfo(name: $name, address: $address, city: $city, type: $type, regionContext: $regionContext, handle: $originalHandle, contextHint: $contextHint)';
}

/// Holds the contextual understanding of image/content before location extraction
/// This is Step 1 of the two-step extraction process
class ContentContext {
  /// What type of content is this? (e.g., "travel blog", "restaurant review", "list of cafes", "trip itinerary")
  final String contentType;
  
  /// What is the primary purpose/theme? (e.g., "best restaurants in NYC", "road trip through California", "hidden gem coffee shops")
  final String purpose;
  
  /// What geographic region/area is the content focused on?
  final String? geographicFocus;
  
  /// What types of locations should we look for? (e.g., ["restaurants", "hotels"], ["hiking trails", "viewpoints"])
  final List<String> locationTypesToFind;
  
  /// Any specific criteria or filters mentioned (e.g., "budget-friendly", "family-friendly", "Michelin-starred")
  final List<String> criteria;
  
  /// Key context clues that help identify relevant locations
  final List<String> contextClues;
  
  /// What should be EXCLUDED from extraction (e.g., "author's local grocery stores", "sponsor mentions")
  final List<String> exclusions;
  
  /// Raw extracted text from the image that might contain location names
  final String? extractedText;
  
  /// The handle of the content creator (who posted) - NOT the business being featured
  final String? contentCreatorHandle;
  
  /// Instagram/social media handles that likely belong to the BUSINESS/LOCATION being featured
  /// These are NOT the content creator, but the actual place being recommended
  /// e.g., ["dolcelunacafe", "matchabuckets", "joes_pizza_nyc"]
  final List<String> businessHandles;
  
  /// A suggested Google search query to find the actual location name
  /// e.g., "Del Mar Plaza San Diego" or "Blue Bottle Coffee Hayes Valley"
  final String? searchQuerySuggestion;
  
  /// Explicitly mentioned place names in the content that should be searched for
  /// These are proper nouns that refer to actual places (not handles)
  /// e.g., ["Del Mar Plaza", "Griffith Observatory", "Pike Place Market"]
  final List<String> mentionedPlaceNames;

  ContentContext({
    required this.contentType,
    required this.purpose,
    this.geographicFocus,
    required this.locationTypesToFind,
    this.criteria = const [],
    this.contextClues = const [],
    this.exclusions = const [],
    this.extractedText,
    this.contentCreatorHandle,
    this.businessHandles = const [],
    this.searchQuerySuggestion,
    this.mentionedPlaceNames = const [],
  });

  @override
  String toString() => '''ContentContext(
  contentType: $contentType,
  purpose: $purpose,
  geographicFocus: $geographicFocus,
  locationTypesToFind: $locationTypesToFind,
  criteria: $criteria,
  contextClues: $contextClues,
  exclusions: $exclusions,
  contentCreatorHandle: $contentCreatorHandle,
  businessHandles: $businessHandles,
  searchQuerySuggestion: $searchQuerySuggestion,
  mentionedPlaceNames: $mentionedPlaceNames,
  extractedText: ${extractedText != null && extractedText!.length > 100 ? '${extractedText!.substring(0, 100)}...' : extractedText}
)''';

  /// Convert to a summary string for use in the location extraction prompt
  String toPromptSummary() {
    final buffer = StringBuffer();
    buffer.writeln('CONTENT TYPE: $contentType');
    buffer.writeln('PURPOSE: $purpose');
    if (geographicFocus != null) {
      buffer.writeln('GEOGRAPHIC FOCUS: $geographicFocus');
    }
    buffer.writeln('LOCATION TYPES TO FIND: ${locationTypesToFind.join(", ")}');
    if (criteria.isNotEmpty) {
      buffer.writeln('CRITERIA: ${criteria.join(", ")}');
    }
    if (contextClues.isNotEmpty) {
      buffer.writeln('CONTEXT CLUES: ${contextClues.join(", ")}');
    }
    if (exclusions.isNotEmpty) {
      buffer.writeln('EXCLUDE: ${exclusions.join(", ")}');
    }
    if (businessHandles.isNotEmpty) {
      buffer.writeln('BUSINESS HANDLES TO SEARCH: ${businessHandles.map((h) => "@$h").join(", ")}');
    }
    return buffer.toString();
  }
}
