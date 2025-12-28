import 'dart:convert';
import 'package:dio/dio.dart';
import '../config/api_secrets.dart';

/// Service for fetching Instagram post data using Meta's oEmbed Read API
/// 
/// This service uses Instagram's oEmbed API to get post captions, metadata,
/// and embed HTML without requiring user OAuth - just an App Access Token.
/// 
/// Requirements:
/// - Facebook App with "oEmbed Read" permission approved
/// - App ID and App Secret configured in ApiSecrets
/// 
/// Supported URL formats:
/// - instagram.com/p/{shortcode}/ (posts)
/// - instagram.com/reel/{shortcode}/ (reels)
/// - instagram.com/tv/{shortcode}/ (IGTV)
class InstagramOEmbedService {
  static final InstagramOEmbedService _instance = InstagramOEmbedService._internal();

  factory InstagramOEmbedService() => _instance;

  InstagramOEmbedService._internal();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// Base URL for Instagram oEmbed API (Meta Graph API)
  static const String _oembedBaseUrl = 'https://graph.facebook.com/v21.0/instagram_oembed';

  /// Check if the service is properly configured
  bool get isConfigured {
    final appId = ApiSecrets.facebookAppId;
    final appSecret = ApiSecrets.facebookAppSecret;
    return appId.isNotEmpty &&
           appSecret.isNotEmpty &&
           !appId.contains('YOUR_') &&
           !appSecret.contains('YOUR_');
  }

  /// Extract caption from an Instagram post URL
  /// 
  /// [url] - The Instagram post/reel URL
  /// 
  /// Returns the caption text, or null if unavailable or on error.
  Future<String?> getCaptionFromUrl(String url) async {
    if (!isConfigured) {
      print('⚠️ INSTAGRAM: API not configured. Add Facebook App ID and Secret.');
      return null;
    }

    if (!_isInstagramUrl(url)) {
      print('⚠️ INSTAGRAM: Not an Instagram URL: $url');
      return null;
    }

    try {
      print('📸 INSTAGRAM: Fetching caption from oEmbed API...');
      
      final response = await _dio.get(
        _oembedBaseUrl,
        queryParameters: {
          'url': url,
          'access_token': ApiSecrets.facebookAccessToken,
          'omitscript': 'true', // Exclude Instagram embed script
        },
        options: Options(
          validateStatus: (status) => status != null && status < 500,
          responseType: ResponseType.json, // Ensure JSON parsing
        ),
      );

      if (response.statusCode == 200) {
        // Handle both Map and String responses
        final data = _parseResponseData(response.data);
        if (data == null) {
          print('❌ INSTAGRAM: Failed to parse response');
          return null;
        }
        
        // Debug: Log all fields returned by the API
        print('📸 INSTAGRAM OEMBED RESPONSE:');
        for (final key in data.keys) {
          final value = data[key];
          if (key == 'html') {
            print('  $key: [${(value as String?)?.length ?? 0} chars]');
          } else {
            print('  $key: $value');
          }
        }
        
        // Check if there's a title field (some posts may have it)
        final title = data['title'] as String?;
        if (title != null && title.isNotEmpty) {
          print('✅ INSTAGRAM: Got caption from title field: ${title.length} chars');
          return title;
        }
        
        // The caption is embedded in the HTML response
        final html = data['html'] as String?;
        
        if (html != null && html.isNotEmpty) {
          final caption = _extractCaptionFromHtml(html);
          
          if (caption != null && caption.isNotEmpty) {
            print('✅ INSTAGRAM: Got caption (${caption.length} chars)');
            return caption;
          } else {
            print('⚠️ INSTAGRAM: No caption found in HTML');
          }
        } else {
          print('⚠️ INSTAGRAM: No HTML in oEmbed response');
        }
        
        return null;
      } else if (response.statusCode == 400) {
        print('❌ INSTAGRAM: Bad request - possibly private post or invalid URL');
        print('   Error: ${response.data}');
        return null;
      } else {
        print('❌ INSTAGRAM: API returned ${response.statusCode}');
        print('   Response: ${response.data}');
        return null;
      }
    } on DioException catch (e) {
      print('❌ INSTAGRAM DIO ERROR: ${e.message}');
      if (e.response != null) {
        print('   Status: ${e.response?.statusCode}');
        print('   Data: ${e.response?.data}');
      }
      return null;
    } catch (e) {
      print('❌ INSTAGRAM ERROR: $e');
      return null;
    }
  }

  /// Extract caption text from Instagram embed HTML
  /// 
  /// The oEmbed API returns HTML that contains the caption text.
  /// We need to parse it carefully to extract just the caption.
  /// 
  /// Supports both regular posts and Reels which have different HTML structures.
  String? _extractCaptionFromHtml(String html) {
    try {
      print('📸 INSTAGRAM PARSE: Attempting to extract caption from ${html.length} chars of HTML');
      
      // Debug: Print a snippet of the HTML to understand structure
      if (html.length > 500) {
        print('📸 INSTAGRAM PARSE: HTML preview: ${html.substring(0, 500)}...');
      }
      
      // Method 1: Look for <p> tags inside blockquote (common for posts with captions)
      // Instagram embeds typically have: <blockquote>...<p>CAPTION HERE</p>...</blockquote>
      final pTagMatch = RegExp(
        r'<p[^>]*>([^<]+)</p>',
        dotAll: true,
        multiLine: true,
      ).allMatches(html);
      
      if (pTagMatch.isNotEmpty) {
        final captionParts = <String>[];
        for (final match in pTagMatch) {
          final content = match.group(1)?.trim() ?? '';
          // Skip attribution lines
          if (content.isEmpty) continue;
          if (content.startsWith('A post shared by')) continue;
          if (content.startsWith('A reel shared by')) continue;
          if (content.startsWith('View this')) continue;
          if (content.contains('(@') && content.length < 50) continue; // Skip short author mentions
          
          captionParts.add(content);
        }
        
        if (captionParts.isNotEmpty) {
          final caption = captionParts.join('\n').trim();
          print('✅ INSTAGRAM PARSE: Found caption in <p> tags: ${caption.length} chars');
          return caption;
        }
      }
      
      // Method 2: Look for blockquote content and extract text
      final blockquoteMatch = RegExp(
        r'<blockquote[^>]*>(.*?)</blockquote>',
        dotAll: true,
        multiLine: true,
      ).firstMatch(html);
      
      if (blockquoteMatch != null) {
        String blockquoteContent = blockquoteMatch.group(1) ?? '';
        
        // Remove script tags first
        blockquoteContent = blockquoteContent.replaceAll(
          RegExp(r'<script[^>]*>.*?</script>', dotAll: true), 
          ''
        );
        
        // Remove HTML tags but keep newlines
        blockquoteContent = blockquoteContent
            .replaceAll(RegExp(r'<br\s*/?>'), '\n')
            .replaceAll(RegExp(r'<[^>]+>'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        
        // Split by common separator phrases
        final lines = blockquoteContent.split(RegExp(r'[\n\r]+|\s{2,}'));
        final captionLines = <String>[];
        
        for (final line in lines) {
          final trimmedLine = line.trim();
          
          // Skip empty lines
          if (trimmedLine.isEmpty) continue;
          
          // Stop at common attribution markers
          if (trimmedLine.startsWith('A post shared by')) break;
          if (trimmedLine.startsWith('A reel shared by')) break;
          if (trimmedLine.startsWith('View this post on')) break;
          if (trimmedLine.startsWith('View this reel on')) break;
          if (RegExp(r'^\(@[\w.]+\)$').hasMatch(trimmedLine)) break; // Just @username
          
          // Skip if it's just a short author mention
          if (trimmedLine.contains('(@') && trimmedLine.length < 50) continue;
          
          captionLines.add(trimmedLine);
        }
        
        if (captionLines.isNotEmpty) {
          final caption = captionLines.join(' ').trim();
          print('✅ INSTAGRAM PARSE: Found caption in blockquote: ${caption.length} chars');
          return caption;
        }
      }
      
      // Method 3: Extract ALL text content and look for meaningful content
      String plainText = html
          .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
          .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
          .replaceAll(RegExp(r'<br\s*/?>'), '\n')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      
      print('📸 INSTAGRAM PARSE: Plain text extracted: ${plainText.length} chars');
      if (plainText.length > 200) {
        print('📸 INSTAGRAM PARSE: Plain text preview: ${plainText.substring(0, 200)}...');
      } else {
        print('📸 INSTAGRAM PARSE: Plain text: $plainText');
      }
      
      // Look for caption before attribution markers
      final attributionPatterns = [
        r'A post shared by',
        r'A reel shared by', 
        r'View this post on Instagram',
        r'View this reel on Instagram',
        r'on \w+ \d+, \d{4}', // Date pattern like "on Jan 15, 2024"
      ];
      
      for (final pattern in attributionPatterns) {
        final captionMatch = RegExp(
          '^(.*?)(?:$pattern)',
          dotAll: true,
          caseSensitive: false,
        ).firstMatch(plainText);
        
        if (captionMatch != null) {
          final caption = captionMatch.group(1)?.trim();
          if (caption != null && caption.length > 5) {
            print('✅ INSTAGRAM PARSE: Found caption before "$pattern": ${caption.length} chars');
            return caption;
          }
        }
      }
      
      // Method 4: If plain text is substantial, return it (minus known boilerplate)
      if (plainText.length > 20) {
        // Remove common Instagram embed boilerplate
        plainText = plainText
            .replaceAll(RegExp(r'View this post on Instagram', caseSensitive: false), '')
            .replaceAll(RegExp(r'View this reel on Instagram', caseSensitive: false), '')
            .replaceAll(RegExp(r'A post shared by.*$', caseSensitive: false), '')
            .replaceAll(RegExp(r'A reel shared by.*$', caseSensitive: false), '')
            .trim();
        
        if (plainText.length > 10) {
          print('✅ INSTAGRAM PARSE: Using cleaned plain text: ${plainText.length} chars');
          return plainText;
        }
      }
      
      print('⚠️ INSTAGRAM PARSE: No caption could be extracted');
      return null;
    } catch (e) {
      print('❌ INSTAGRAM PARSE: Error extracting caption from HTML: $e');
      return null;
    }
  }

  /// Check if URL is an Instagram URL
  bool _isInstagramUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('instagram.com/p/') ||
           lower.contains('instagram.com/reel/') ||
           lower.contains('instagram.com/tv/');
  }

  /// Get post metadata and embed HTML
  /// 
  /// Returns a map with:
  /// - `html`: The embed HTML (blockquote with Instagram embed.js)
  /// - `author_name`: The author's display name
  /// - `provider_name`: "Instagram"
  /// - `thumbnail_url`: Thumbnail image URL (if available)
  /// - `thumbnail_width`/`thumbnail_height`: Thumbnail dimensions
  /// - `width`: Embed width (null for responsive)
  /// 
  /// [maxWidth] - Optional max width for the embed (320-658 pixels)
  Future<Map<String, dynamic>?> getPostMetadata(String url, {int? maxWidth}) async {
    if (!isConfigured) {
      print('⚠️ INSTAGRAM: API not configured for metadata fetch');
      return null;
    }
    if (!_isInstagramUrl(url)) {
      print('⚠️ INSTAGRAM: Invalid URL for metadata: $url');
      return null;
    }

    try {
      final queryParams = <String, dynamic>{
        'url': url,
        'access_token': ApiSecrets.facebookAccessToken,
      };
      
      // Add maxwidth if specified (useful for responsive embeds)
      if (maxWidth != null && maxWidth >= 320 && maxWidth <= 658) {
        queryParams['maxwidth'] = maxWidth;
      }
      
      final response = await _dio.get(
        _oembedBaseUrl,
        queryParameters: queryParams,
        options: Options(
          validateStatus: (status) => status != null && status < 500,
          responseType: ResponseType.json, // Ensure JSON parsing
        ),
      );

      if (response.statusCode == 200) {
        // Handle both Map and String responses (Dio may return either)
        final data = _parseResponseData(response.data);
        if (data == null) {
          print('❌ INSTAGRAM METADATA: Failed to parse response');
          return null;
        }
        
        // Note: Meta oEmbed API may not return author_name or thumbnail_url
        // for all content types. The HTML field is always returned and contains
        // the embed data we can parse for author/caption.
        final hasHtml = data['html'] != null;
        print('✅ INSTAGRAM: Got metadata - html: $hasHtml, '
              'author: ${data['author_name'] ?? 'N/A'}, '
              'thumbnail: ${data['thumbnail_url'] != null}');
        
        return data;
      } else if (response.statusCode == 400) {
        final error = _parseResponseData(response.data);
        final errorMsg = error?['error']?['message'] ?? response.data;
        final errorCode = error?['error']?['code'];
        final errorSubcode = error?['error']?['error_subcode'];
        final errorType = error?['error']?['type'];
        print('❌ INSTAGRAM METADATA: Bad request - $errorMsg');
        print('   Error code: $errorCode, subcode: $errorSubcode, type: $errorType');
        print('   Full error: ${response.data}');
        print('   Request URL: $url');
        print('   Access token format: App ID|App Secret (${ApiSecrets.facebookAppId.length} chars | ${ApiSecrets.facebookAppSecret.length} chars)');
        return null;
      } else {
        print('❌ INSTAGRAM METADATA: API returned ${response.statusCode}');
        return null;
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        print('❌ INSTAGRAM METADATA: Request timed out');
      } else {
        print('❌ INSTAGRAM METADATA ERROR: ${e.message}');
      }
      return null;
    } catch (e) {
      print('❌ INSTAGRAM METADATA ERROR: $e');
      return null;
    }
  }
  
  /// Parse response data that could be either a Map or a JSON String
  Map<String, dynamic>? _parseResponseData(dynamic data) {
    if (data == null) return null;
    
    if (data is Map<String, dynamic>) {
      return data;
    }
    
    if (data is String) {
      try {
        final parsed = json.decode(data);
        if (parsed is Map<String, dynamic>) {
          return parsed;
        }
      } catch (e) {
        print('⚠️ INSTAGRAM: Failed to parse JSON string: $e');
      }
    }
    
    return null;
  }

  /// Check if a URL is an Instagram post/reel URL
  bool isInstagramPostUrl(String url) => _isInstagramUrl(url);
}
