import 'dart:math';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Service for preloading and caching Discovery screen cover background images
class DiscoveryCoverService {
  static const String _coverBackgroundFolder = 'cover_photos';
  static final DiscoveryCoverService _instance = DiscoveryCoverService._internal();
  factory DiscoveryCoverService() => _instance;
  DiscoveryCoverService._internal();

  final Random _random = Random();
  List<Reference>? _coverBackgroundRefs;
  final List<String> _preloadedUrls = [];
  bool _isInitialized = false;
  bool _isBackgroundPreloadComplete = false;

  /// Get whether the service has been initialized with cover references
  bool get isInitialized => _isInitialized;

  /// Get whether background preloading is complete
  bool get isBackgroundPreloadComplete => _isBackgroundPreloadComplete;

  /// Get all preloaded URLs
  List<String> get preloadedUrls => List.unmodifiable(_preloadedUrls);

  /// Initialize by fetching the list of cover background references from Firebase Storage
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final ListResult result =
          await FirebaseStorage.instance.ref(_coverBackgroundFolder).listAll();
      
      if (result.items.isEmpty) {
        debugPrint('DiscoveryCoverService: No cover backgrounds found in $_coverBackgroundFolder');
        return;
      }

      _coverBackgroundRefs = result.items;
      _isInitialized = true;
      debugPrint('DiscoveryCoverService: Initialized with ${_coverBackgroundRefs!.length} cover images');
    } catch (e) {
      debugPrint('DiscoveryCoverService: Failed to initialize: $e');
    }
  }

  /// Preload a single random cover image (for splash screen)
  /// Returns the URL of the preloaded image, or null if failed
  Future<String?> preloadSingleImage(BuildContext context) async {
    if (!_isInitialized || _coverBackgroundRefs == null || _coverBackgroundRefs!.isEmpty) {
      await initialize();
      if (!_isInitialized || _coverBackgroundRefs == null || _coverBackgroundRefs!.isEmpty) {
        return null;
      }
    }

    try {
      final randomRef = _coverBackgroundRefs![_random.nextInt(_coverBackgroundRefs!.length)];
      final url = await randomRef.getDownloadURL();
      
      // Precache the image using CachedNetworkImage provider for consistency
      await precacheImage(CachedNetworkImageProvider(url), context);
      
      // Track the preloaded URL
      if (!_preloadedUrls.contains(url)) {
        _preloadedUrls.add(url);
      }
      
      debugPrint('DiscoveryCoverService: Preloaded splash image (${_preloadedUrls.length} total cached)');
      return url;
    } catch (e) {
      debugPrint('DiscoveryCoverService: Failed to preload splash image: $e');
      return null;
    }
  }

  /// Preload multiple random cover images in the background (post-splash)
  /// Images are cached and URLs are tracked for future use
  Future<void> preloadBackgroundImages(BuildContext context, {int count = 5}) async {
    if (_isBackgroundPreloadComplete) {
      debugPrint('DiscoveryCoverService: Background preload already complete');
      return;
    }

    if (!_isInitialized || _coverBackgroundRefs == null || _coverBackgroundRefs!.isEmpty) {
      await initialize();
      if (!_isInitialized || _coverBackgroundRefs == null || _coverBackgroundRefs!.isEmpty) {
        return;
      }
    }

    try {
      // Get random indices to preload, excluding any already preloaded
      final availableRefs = List<Reference>.from(_coverBackgroundRefs!);
      availableRefs.shuffle(_random);

      int preloaded = 0;
      for (final ref in availableRefs) {
        if (preloaded >= count) break;

        try {
          final url = await ref.getDownloadURL();
          
          // Skip if already preloaded
          if (_preloadedUrls.contains(url)) continue;

          // Precache the image using CachedNetworkImage provider for consistency
          await precacheImage(CachedNetworkImageProvider(url), context);
          _preloadedUrls.add(url);
          preloaded++;

          debugPrint('DiscoveryCoverService: Background preloaded $preloaded/$count images');
        } catch (e) {
          debugPrint('DiscoveryCoverService: Failed to preload background image: $e');
        }
      }

      _isBackgroundPreloadComplete = true;
      debugPrint('DiscoveryCoverService: Background preload complete (${_preloadedUrls.length} total cached)');
    } catch (e) {
      debugPrint('DiscoveryCoverService: Failed to preload background images: $e');
    }
  }

  /// Get a random preloaded URL, or null if none available
  String? getRandomPreloadedUrl() {
    if (_preloadedUrls.isEmpty) return null;
    return _preloadedUrls[_random.nextInt(_preloadedUrls.length)];
  }

  /// Get a random cover URL (fetches on demand if not preloaded)
  Future<String?> getRandomCoverUrl() async {
    // Prefer preloaded URLs
    if (_preloadedUrls.isNotEmpty) {
      return getRandomPreloadedUrl();
    }

    // Fallback: fetch on demand
    if (!_isInitialized || _coverBackgroundRefs == null || _coverBackgroundRefs!.isEmpty) {
      await initialize();
      if (!_isInitialized || _coverBackgroundRefs == null || _coverBackgroundRefs!.isEmpty) {
        return null;
      }
    }

    try {
      final randomRef = _coverBackgroundRefs![_random.nextInt(_coverBackgroundRefs!.length)];
      return await randomRef.getDownloadURL();
    } catch (e) {
      debugPrint('DiscoveryCoverService: Failed to get random cover URL: $e');
      return null;
    }
  }

  /// Clear all cached data (for testing or reset)
  void clear() {
    _preloadedUrls.clear();
    _isBackgroundPreloadComplete = false;
    debugPrint('DiscoveryCoverService: Cleared cache');
  }
}
