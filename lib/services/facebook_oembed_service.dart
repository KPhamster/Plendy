import 'package:dio/dio.dart';
import '../config/api_secrets.dart';

/// Service for fetching Facebook content data using the Meta oEmbed API
/// 
/// This service uses Facebook's oEmbed API to get post/video/page previews
/// and metadata for embedding in the app.
/// 
/// Supported content types:
/// - Facebook Posts (oembed_post)
/// - Facebook Videos/Reels (oembed_video)
/// - Facebook Pages (oembed_page)
class FacebookOEmbedService {
  static final FacebookOEmbedService _instance = FacebookOEmbedService._internal();

  factory FacebookOEmbedService() => _instance;

  FacebookOEmbedService._internal();

  final Dio _dio = Dio();

  /// Base URLs for Facebook oEmbed API endpoints
  static const String _oembedPostUrl = 'https://graph.facebook.com/v21.0/oembed_post';
  static const String _oembedVideoUrl = 'https://graph.facebook.com/v21.0/oembed_video';
  static const String _oembedPageUrl = 'https://graph.facebook.com/v21.0/oembed_page';

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
  FacebookContentType getContentType(String url) {
    final lower = url.toLowerCase();
    
    // Videos and Reels
    if (lower.contains('/reel/') || 
        lower.contains('/reels/') ||
        lower.contains('/videos/') ||
        lower.contains('/watch/') ||
        lower.contains('fb.watch/')) {
      return FacebookContentType.video;
    }
    
    // Posts
    if (lower.contains('/posts/') ||
        lower.contains('/photo') ||
        lower.contains('story_fbid=') ||
        lower.contains('/permalink/')) {
      return FacebookContentType.post;
    }
    
    // Pages (profile URLs without specific content)
    if (RegExp(r'facebook\.com/[^/]+/?$').hasMatch(lower) ||
        lower.contains('/pages/')) {
      return FacebookContentType.page;
    }
    
    // Default to post for other URLs
    return FacebookContentType.post;
  }

  /// Get the appropriate oEmbed endpoint URL for the content type
  String _getEndpointUrl(FacebookContentType type) {
    switch (type) {
      case FacebookContentType.video:
        return _oembedVideoUrl;
      case FacebookContentType.page:
        return _oembedPageUrl;
      case FacebookContentType.post:
      default:
        return _oembedPostUrl;
    }
  }

  /// Get oEmbed data for a Facebook URL
  /// 
  /// [url] - The Facebook post/video/reel/page URL
  /// 
  /// Returns a map containing the oEmbed response data including HTML embed code,
  /// or null if unavailable or on error.
  Future<Map<String, dynamic>?> getOEmbedData(String url) async {
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
      
      final response = await _dio.get(
        endpoint,
        queryParameters: {
          'url': url,
          'access_token': ApiSecrets.facebookAccessToken,
          'omitscript': 'false', // Include Facebook SDK script reference
        },
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        print('✅ FACEBOOK: Got oEmbed response');
        
        if (data['html'] != null) {
          print('   HTML length: ${(data['html'] as String).length} chars');
        }
        if (data['author_name'] != null) {
          print('   Author: ${data['author_name']}');
        }
        
        return data;
      } else if (response.statusCode == 400) {
        print('❌ FACEBOOK: Bad request - possibly private content or invalid URL');
        print('   Error: ${response.data}');
        return null;
      } else {
        print('❌ FACEBOOK: API returned ${response.statusCode}');
        print('   Response: ${response.data}');
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

/// Types of Facebook content supported by oEmbed
enum FacebookContentType {
  post,
  video,
  page,
}
