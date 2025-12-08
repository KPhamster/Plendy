import 'package:dio/dio.dart';
import '../config/api_secrets.dart';

/// Service for fetching Instagram post data using the public oEmbed API
/// 
/// This service uses Instagram's oEmbed API to get post captions and metadata
/// without requiring OAuth authentication - just an App ID and Secret.
class InstagramOEmbedService {
  static final InstagramOEmbedService _instance = InstagramOEmbedService._internal();

  factory InstagramOEmbedService() => _instance;

  InstagramOEmbedService._internal();

  final Dio _dio = Dio();

  /// Base URL for Instagram oEmbed API
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
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        
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
  String? _extractCaptionFromHtml(String html) {
    try {
      // Instagram embeds include data-instgrm-caption-id attribute
      // and the caption is typically in a specific structure
      
      // Try to find text after "A post shared by" or similar markers
      // The caption is usually before the author attribution
      
      // Method 1: Look for blockquote content (most reliable)
      final blockquoteMatch = RegExp(
        r'<blockquote[^>]*>(.*?)</blockquote>',
        dotAll: true,
        multiLine: true,
      ).firstMatch(html);
      
      if (blockquoteMatch != null) {
        String blockquoteContent = blockquoteMatch.group(1) ?? '';
        
        // Remove HTML tags but keep newlines
        blockquoteContent = blockquoteContent
            .replaceAll(RegExp(r'<br\s*/?>'), '\n')
            .replaceAll(RegExp(r'<[^>]+>'), '')
            .trim();
        
        // Split by common separator phrases
        final lines = blockquoteContent.split('\n');
        final captionLines = <String>[];
        
        for (final line in lines) {
          final trimmedLine = line.trim();
          
          // Stop at common attribution markers
          if (trimmedLine.isEmpty) continue;
          if (trimmedLine.startsWith('A post shared by')) break;
          if (trimmedLine.startsWith('View this post on')) break;
          if (trimmedLine.contains('(@')) break; // Usually author mention
          
          captionLines.add(trimmedLine);
        }
        
        if (captionLines.isNotEmpty) {
          return captionLines.join('\n').trim();
        }
      }
      
      // Method 2: Try to extract from plain text (fallback)
      String plainText = html
          .replaceAll(RegExp(r'<br\s*/?>'), '\n')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      
      // Look for caption patterns
      final captionMatch = RegExp(
        r'^(.*?)(?:A post shared by|View this post on Instagram)',
        dotAll: true,
      ).firstMatch(plainText);
      
      if (captionMatch != null) {
        final caption = captionMatch.group(1)?.trim();
        if (caption != null && caption.isNotEmpty) {
          return caption;
        }
      }
      
      return null;
    } catch (e) {
      print('⚠️ INSTAGRAM: Error extracting caption from HTML: $e');
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

  /// Get post metadata (author, timestamp, etc.)
  Future<Map<String, dynamic>?> getPostMetadata(String url) async {
    if (!isConfigured) return null;
    if (!_isInstagramUrl(url)) return null;

    try {
      final response = await _dio.get(
        _oembedBaseUrl,
        queryParameters: {
          'url': url,
          'access_token': ApiSecrets.facebookAccessToken,
        },
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      
      return null;
    } catch (e) {
      print('❌ INSTAGRAM METADATA ERROR: $e');
      return null;
    }
  }
}
