import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
  String _buildTextLocationExtractionPrompt(String text) {
    return '''
Extract ALL location information from the following text:

$text

For EACH distinct place, business, or location mentioned, identify:
1. The exact business or place name
2. The full address if available
3. The type of place
4. Any additional location context

If multiple places are mentioned, extract all of them.
Provide accurate, verified location information only.
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
              print('📝 GEMINI VISION Response: ${text.length > 200 ? text.substring(0, 200) + "..." : text}');
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

Rules for conversion:
1. Remove the @ symbol
2. Remove domain suffixes (.us, .co, .nyc, .la, .official, .shop, etc.)
3. Replace dots (.) and underscores (_) with spaces
4. Capitalize each word properly (Title Case)
5. Remove "the" prefix if it makes sense
6. The result should be a human-readable business name

=== LOOK FOR THESE LOCATION TYPES ===
1. Business names (restaurants, cafes, shops, bars, hotels)
2. Street addresses (even partial - "123 Main St", "on Broadway")
3. City/state/country names
4. Neighborhood names
5. Famous landmarks or tourist attractions
6. Tagged locations from social media (📍 location markers)
7. Signs, storefronts, menus showing business names
8. Text mentioning "at", "visited", "went to", "check out"

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
    "type": "restaurant/cafe/store/attraction/etc"
  }
]

=== EXAMPLES ===
If you see: "@oldferrydonut.us - 6982 Beach Blvd"
Return: {"name": "Old Ferry Donut", "address": "6982 Beach Blvd", "city": null, "type": "restaurant"}

If you see: "📍 @matecoffeebar"
Return: {"name": "Mate Coffee Bar", "address": null, "city": null, "type": "cafe"}

=== RULES ===
- ALWAYS convert @handles to proper business names
- Extract EVERY distinct location mentioned
- Include partial information - even just a business name is useful
- For video text overlays, read character by character if needed
- Prioritize text that appears to name specific places
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
  String _convertHandleToBusinessName(String name) {
    String result = name.trim();
    
    // If it doesn't look like a handle, return as-is
    if (!result.startsWith('@') && !result.contains('.') && !result.contains('_')) {
      return result;
    }
    
    // Remove @ symbol
    if (result.startsWith('@')) {
      result = result.substring(1);
    }
    
    // Remove common domain/location suffixes
    final suffixesToRemove = [
      '.us', '.co', '.uk', '.ca', '.au', '.de', '.fr', '.es', '.it', '.jp',
      '.nyc', '.la', '.sf', '.chi', '.dc', '.atl', '.mia', '.dal', '.hou', '.phx',
      '.official', '.shop', '.store', '.cafe', '.restaurant', '.bar', '.food',
      '.eats', '.kitchen', '.bakery', '.coffee', '.pizza', '.tacos', '.burgers',
      '_official', '_us', '_nyc', '_la',
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
