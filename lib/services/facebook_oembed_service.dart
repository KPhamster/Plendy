import 'dart:convert';
import 'package:dio/dio.dart';
import '../config/api_secrets.dart';

/// Service for fetching Facebook content data using the Meta oEmbed API
/// 
/// This service uses Facebook's Graph API oEmbed endpoints to get post/video previews
/// and metadata for embedding in the app.
/// 
/// Supported content types (per official Meta Graph API v24.0):
/// - Facebook Posts (oembed_post) - for posts, photos, permalinks
/// - Facebook Videos/Reels (oembed_video) - for videos, reels, watch content
/// 
/// Note: oembed_page endpoint does not exist in the official API.
/// Page URLs will fall back to oembed_post.
/// 
/// API Reference: https://developers.facebook.com/docs/graph-api/reference/oembed-video
///                https://developers.facebook.com/docs/graph-api/reference/oembed-post
class FacebookOEmbedService {
  static final FacebookOEmbedService _instance = FacebookOEmbedService._internal();

  factory FacebookOEmbedService() => _instance;

  FacebookOEmbedService._internal();

  final Dio _dio = Dio();

  /// Base URLs for Facebook oEmbed API endpoints (v24.0 - latest as of 2026)
  static const String _oembedPostUrl = 'https://graph.facebook.com/v24.0/oembed_post';
  static const String _oembedVideoUrl = 'https://graph.facebook.com/v24.0/oembed_video';

  /// Check if the service is properly configured
  bool get isConfigured {
    final appId = ApiSecrets.facebookAppId;
    final appSecret = ApiSecrets.facebookAppSecret;
    return appId.isNotEmpty &&
           appSecret.isNotEmpty &&
           !appId.contains('YOUR_') &&
           !appSecret.contains('YOUR_');
  }

  /// Determine the content type from a Facebook URL
  /// 
  /// Per Meta Graph API documentation, only two oEmbed endpoints exist:
  /// - oembed_video: for videos, reels, watch content
  /// - oembed_post: for posts, photos, permalinks (and fallback for other content)
  FacebookContentType getContentType(String url) {
    final lower = url.toLowerCase();
    
    // Videos and Reels -> use oembed_video endpoint
    if (lower.contains('/reel/') || 
        lower.contains('/reels/') ||
        lower.contains('/videos/') ||
        lower.contains('/watch/') ||
        lower.contains('fb.watch/')) {
      return FacebookContentType.video;
    }
    
    // Everything else uses oembed_post (posts, photos, permalinks, pages, etc.)
    // Note: Page URLs may not return embed data, but oembed_post is the closest match
    return FacebookContentType.post;
  }

  /// Get the appropriate oEmbed endpoint URL for the content type
  String _getEndpointUrl(FacebookContentType type) {
    switch (type) {
      case FacebookContentType.video:
        return _oembedVideoUrl;
      case FacebookContentType.post:
        return _oembedPostUrl;
    }
  }

  /// Get oEmbed data for a Facebook URL
  /// 
  /// [url] - The Facebook post/video/reel URL (required)
  /// [maxWidth] - Maximum width of returned embed (optional)
  /// [useIframe] - If true, returns iframe-based embed instead of XFBML (optional, defaults to false)
  /// 
  /// Returns a map containing the oEmbed response data including:
  /// - html: The HTML embed code
  /// - author_name: Name of the content owner
  /// - author_url: URL of the author's profile
  /// - width/height: Dimensions of the embed
  /// - provider_name/provider_url: Facebook info
  /// - type: oEmbed resource type
  /// - version: Always "1.0"
  /// 
  /// Returns null if unavailable, private content, or on error.
  Future<Map<String, dynamic>?> getOEmbedData(
    String url, {
    int? maxWidth,
    bool useIframe = false,
  }) async {
    if (!isConfigured) {
      print('⚠️ FACEBOOK: API not configured. Add Facebook App ID and Secret.');
      return null;
    }

    if (!_isFacebookUrl(url)) {
      print('⚠️ FACEBOOK: Not a Facebook URL: $url');
      return null;
    }

    final contentType = getContentType(url);
    final endpoint = _getEndpointUrl(contentType);

    try {
      print('📘 FACEBOOK: Fetching oEmbed data for ${contentType.name} from $endpoint');
      
      // Build query parameters per Meta Graph API v24.0 spec
      final queryParams = <String, dynamic>{
        'url': url,
        'access_token': ApiSecrets.facebookAccessToken,
        'omitscript': 'false', // Include Facebook SDK script reference
      };
      
      // Add optional parameters if provided
      if (maxWidth != null) {
        queryParams['maxwidth'] = maxWidth;
      }
      if (useIframe) {
        queryParams['useiframe'] = 'true';
      }
      
      final response = await _dio.get(
        endpoint,
        queryParameters: queryParams,
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200) {
        // Handle response.data which could be String or Map depending on Dio config
        Map<String, dynamic> data;
        if (response.data is String) {
          // Parse JSON string to Map
          try {
            data = jsonDecode(response.data as String) as Map<String, dynamic>;
          } catch (e) {
            print('❌ FACEBOOK: Failed to parse JSON response: $e');
            print('   Raw response: ${response.data}');
            return null;
          }
        } else if (response.data is Map<String, dynamic>) {
          data = response.data as Map<String, dynamic>;
        } else {
          print('❌ FACEBOOK: Unexpected response type: ${response.data.runtimeType}');
          return null;
        }
        
        print('✅ FACEBOOK: Got oEmbed response');
        
        if (data['html'] != null) {
          print('   HTML length: ${(data['html'] as String).length} chars');
        }
        if (data['author_name'] != null) {
          print('   Author: ${data['author_name']}');
        }
        
        return data;
      } else {
        // Handle error responses - parse error data for better diagnostics
        Map<String, dynamic>? errorData;
        if (response.data is String) {
          try {
            errorData = jsonDecode(response.data as String) as Map<String, dynamic>;
          } catch (_) {}
        } else if (response.data is Map<String, dynamic>) {
          errorData = response.data as Map<String, dynamic>;
        }
        
        // Extract Facebook API error code if available
        final fbError = errorData?['error'] as Map<String, dynamic>?;
        final errorCode = fbError?['code'];
        final errorMessage = fbError?['message'] ?? response.data;
        
        // Handle specific Facebook API error codes per official docs
        switch (errorCode) {
          case 100:
            print('❌ FACEBOOK: Invalid parameter (code 100) - URL may be malformed');
            break;
          case 190:
            print('❌ FACEBOOK: Invalid OAuth 2.0 Access Token (code 190) - check API credentials');
            break;
          case 200:
            print('❌ FACEBOOK: Permissions error (code 200) - content may be private');
            break;
          default:
            print('❌ FACEBOOK: API returned ${response.statusCode}');
        }
        print('   Error: $errorMessage');
        return null;
      }
    } on DioException catch (e) {
      print('❌ FACEBOOK DIO ERROR: ${e.message}');
      if (e.response != null) {
        print('   Status: ${e.response?.statusCode}');
        print('   Data: ${e.response?.data}');
      }
      return null;
    } catch (e) {
      print('❌ FACEBOOK ERROR: $e');
      return null;
    }
  }

  /// Get HTML embed code for a Facebook URL
  /// 
  /// This is a convenience method that extracts just the HTML from oEmbed response.
  Future<String?> getEmbedHtml(String url) async {
    final data = await getOEmbedData(url);
    return data?['html'] as String?;
  }

  /// Extract text/caption from Facebook oEmbed HTML response
  /// 
  /// Facebook oEmbed responses include text content in the HTML that can be
  /// parsed to extract post captions or descriptions.
  String? extractTextFromHtml(String html) {
    try {
      // Remove script tags
      String cleaned = html.replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '');
      
      // Extract text from blockquote if present
      final blockquoteMatch = RegExp(
        r'<blockquote[^>]*>(.*?)</blockquote>',
        dotAll: true,
        multiLine: true,
      ).firstMatch(cleaned);
      
      if (blockquoteMatch != null) {
        String content = blockquoteMatch.group(1) ?? '';
        
        // Remove HTML tags but preserve text
        content = content
            .replaceAll(RegExp(r'<br\s*/?>'), '\n')
            .replaceAll(RegExp(r'<[^>]+>'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        
        if (content.isNotEmpty) {
          return content;
        }
      }
      
      // Fallback: extract all text content
      String plainText = cleaned
          .replaceAll(RegExp(r'<br\s*/?>'), '\n')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      
      return plainText.isNotEmpty ? plainText : null;
    } catch (e) {
      print('⚠️ FACEBOOK: Error extracting text from HTML: $e');
      return null;
    }
  }

  /// Check if URL is a Facebook URL
  bool _isFacebookUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('facebook.com') ||
           lower.contains('fb.com') ||
           lower.contains('fb.watch');
  }

  /// Check if the URL is likely to be supported by oEmbed
  bool isSupportedUrl(String url) {
    if (!_isFacebookUrl(url)) return false;
    
    final lower = url.toLowerCase();
    
    // These are supported
    if (lower.contains('/posts/') ||
        lower.contains('/videos/') ||
        lower.contains('/reel/') ||
        lower.contains('/reels/') ||
        lower.contains('/watch/') ||
        lower.contains('/photo') ||
        lower.contains('/permalink/') ||
        lower.contains('story_fbid=') ||
        lower.contains('fb.watch/')) {
      return true;
    }
    
    return true; // Try anyway for other Facebook URLs
  }
}

/// Types of Facebook content supported by Meta oEmbed API
/// 
/// Per official Graph API v24.0 documentation:
/// - post: Uses /oembed_post endpoint for posts, photos, permalinks
/// - video: Uses /oembed_video endpoint for videos, reels, watch content
enum FacebookContentType {
  post,
  video,
}
