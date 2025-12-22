import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_app_check/firebase_app_check.dart';
import '../../firebase_options.dart';

import '../models/experience.dart';
import '../models/user_category.dart';
import '../models/user_profile.dart';
import '../models/color_category.dart';
import '../models/shared_media_item.dart';
import '../models/review.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/experience_service.dart';
import '../services/message_service.dart';
import '../widgets/shared_media_preview_modal.dart';
import '../widgets/share_experience_bottom_sheet.dart';
import '../widgets/cached_profile_avatar.dart';
import '../models/share_result.dart';
import 'auth_screen.dart';
import 'experience_page_screen.dart';
import 'main_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/colors.dart';

// Helper function to parse hex color string
Color _parseColor(String hexColor) {
  hexColor = hexColor.toUpperCase().replaceAll("#", "");
  if (hexColor.length == 6) {
    hexColor = "FF$hexColor"; // Add alpha if missing
  }
  if (hexColor.length == 8) {
    try {
      return Color(int.parse("0x$hexColor"));
    } catch (e) {
      return Colors.grey; // Default color on parsing error
    }
  }
  return Colors.grey; // Default color on invalid format
}

class PublicProfileScreen extends StatefulWidget {
  final String userId;

  const PublicProfileScreen({super.key, required this.userId});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen>
    with SingleTickerProviderStateMixin {
  final UserService _userService = UserService();
  final ExperienceService _experienceService = ExperienceService();

  UserProfile? _profile;
  int _followersCount = 0;
  int _followingCount = 0;
  List<String> _followerIds = [];
  List<String> _followingIds = [];
  List<UserCategory> _publicCategories = [];
  List<ColorCategory> _publicColorCategories = [];
  Map<String, List<Experience>> _categoryExperiences = {};
  bool _isLoading = true;
  bool _isLoadingCollections = true;
  int _publicExperienceCount = 0;
  bool _isProcessingFollow = false;
  bool _isFollowing = false;
  bool _ownerFollowsViewer = false;
  bool _hasPendingRequest = false;
  String? _currentUserId;
  bool _initialized = false;
  late final TabController _tabController;
  UserCategory? _selectedCategory;
  ColorCategory? _selectedColorCategory;
  bool _showingColorCategories = false;

  // Media cache for experience content previews
  final Map<String, List<SharedMediaItem>> _experienceMediaCache = {};
  final Set<String> _mediaPrefetchInFlight = {};

  // User reviews
  List<Review> _userReviews = [];
  bool _isLoadingReviews = false;
  // Cache for experience data associated with reviews
  final Map<String, Experience> _reviewExperienceCache = {};
  // Cache for categories from other users (experience owners)
  final Map<String, UserCategory> _externalCategoryCache = {};
  final Map<String, ColorCategory> _externalColorCategoryCache = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authService = Provider.of<AuthService>(context);
    final viewerId = authService.currentUser?.uid;
    final shouldLoad = !_initialized || _currentUserId != viewerId;
    _currentUserId = viewerId;
    if (shouldLoad) {
      _initialized = true;
      _loadProfile();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _navigateToMainScreen() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainScreen(initialIndex: 3)),
      (route) => false,
    );
  }

  Future<bool> _handleBackNavigation() async {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else if (_currentUserId == null) {
      // Unauthenticated user with no previous screen - go to auth
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (route) => false,
      );
    } else {
      _navigateToMainScreen();
    }
    return false;
  }

  Future<void> _loadProfile({bool showFullPageLoader = true}) async {
    if (showFullPageLoader && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final profile = await _userService.getUserProfile(widget.userId);

      // Try to load followers/following, but handle permission errors gracefully
      List<String> followers = [];
      List<String> following = [];

      try {
        followers = await _userService.getFollowerIds(widget.userId);
      } catch (e) {
        debugPrint('Error getting follower IDs: $e');
        // Continue with empty list
      }

      try {
        following = await _userService.getFollowingIds(widget.userId);
      } catch (e) {
        debugPrint('Error getting following IDs: $e');
        // Continue with empty list
      }

      bool isFollowing = false;
      bool ownerFollowsViewer = false;
      bool hasPendingRequest = false;
      final viewerId = _currentUserId;

      if (viewerId != null && viewerId != widget.userId) {
        try {
          isFollowing = await _userService.isFollowing(viewerId, widget.userId);
        } catch (e) {
          debugPrint('Error checking if following: $e');
        }

        try {
          ownerFollowsViewer =
              await _userService.isFollowing(widget.userId, viewerId);
        } catch (e) {
          debugPrint('Error checking if owner follows viewer: $e');
        }

        try {
          hasPendingRequest =
              await _userService.hasPendingRequest(viewerId, widget.userId);
        } catch (e) {
          debugPrint('Error checking pending request: $e');
        }
      }

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _followerIds = followers;
        _followingIds = following;
        _followersCount = followers.length;
        _followingCount = following.length;
        _isFollowing = isFollowing;
        _ownerFollowsViewer = ownerFollowsViewer;
        _hasPendingRequest = hasPendingRequest;
        _isLoading = false;
      });
      // Load collections and reviews in parallel
      await Future.wait([
        _loadPublicCollections(),
        _loadUserReviews(),
      ]);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to load public profile. Please try again.')),
      );
    }
  }

  Future<void> _loadPublicCollections() async {
    if (!mounted) return;

    // Skip loading collections if profile is private and viewer doesn't have access
    final bool isPrivate = _profile?.isPrivate ?? false;
    final bool isOwner =
        _currentUserId != null && _currentUserId == widget.userId;
    if (isPrivate && !isOwner && !_isFollowing) {
      setState(() {
        _publicCategories = [];
        _publicColorCategories = [];
        _categoryExperiences = {};
        _publicExperienceCount = 0;
        _isLoadingCollections = false;
      });
      return;
    }

    setState(() => _isLoadingCollections = true);

    // For unauthenticated users, use REST API
    final bool isUnauthenticated = _currentUserId == null;
    if (isUnauthenticated) {
      await _loadPublicCollectionsViaRest();
      return;
    }

    try {
      // Load categories and experiences - color categories may fail due to permissions
      final categoriesSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('categories')
          .get();

      final experiencesSnapshot = await FirebaseFirestore.instance
          .collection('experiences')
          .where('createdBy', isEqualTo: widget.userId)
          .get();

      final List<UserCategory> categories = [];
      for (final doc in categoriesSnapshot.docs) {
        try {
          final category = UserCategory.fromFirestore(doc);
          if (category.isPrivate) continue;
          categories.add(category);
        } catch (e) {
          debugPrint(
              'PublicProfileScreen: skipping invalid category ${doc.id} - $e');
        }
      }

      categories
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      // Parse experiences first
      final List<Experience> experiences = [];
      for (final doc in experiencesSnapshot.docs) {
        try {
          final experience = Experience.fromFirestore(doc);
          if (experience.isPrivate) continue;
          experiences.add(experience);
        } catch (e) {
          debugPrint(
              'PublicProfileScreen: skipping invalid experience ${doc.id} - $e');
        }
      }

      // Sort experiences alphabetically for consistent display
      experiences.sort((a, b) {
        final aName = (a.name ?? '').toLowerCase();
        final bName = (b.name ?? '').toLowerCase();
        return aName.compareTo(bName);
      });
      final int totalPublicExperiences = experiences.length;

      // Build color categories list from public experiences (avoid permission issues)
      final Set<String> colorCategoryIds = {};
      for (final experience in experiences) {
        if (experience.colorCategoryId != null &&
            experience.colorCategoryId!.isNotEmpty) {
          colorCategoryIds.add(experience.colorCategoryId!);
        }
        // Also collect from other color categories
        for (final colorId in experience.otherColorCategoryIds) {
          if (colorId.isNotEmpty) {
            colorCategoryIds.add(colorId);
          }
        }
      }

      // Fetch only the color categories that are actually used by public experiences
      final List<ColorCategory> colorCategories = [];
      if (colorCategoryIds.isNotEmpty) {
        try {
          // Fetch color categories from their owner using the service
          final fetchedColors =
              await _experienceService.getColorCategoriesByOwnerAndIds(
                  widget.userId, colorCategoryIds.toList());

          // Only include non-private color categories
          for (final colorCategory in fetchedColors) {
            if (!colorCategory.isPrivate) {
              colorCategories.add(colorCategory);
            }
          }

          debugPrint(
              'PublicProfileScreen: Loaded ${colorCategories.length} public color categories from experiences');
        } catch (e) {
          debugPrint(
              'PublicProfileScreen: Could not load color categories - $e');
        }
      }

      final Map<String, List<Experience>> catExperiences = {
        for (final category in categories) category.id: []
      };
      final categoryIds = catExperiences.keys.toSet();

      for (final experience in experiences) {
        final Set<String> relevantCategoryIds = {
          if (experience.categoryId != null) experience.categoryId!,
          ...experience.otherCategories,
        };
        for (final categoryId in relevantCategoryIds) {
          if (!categoryIds.contains(categoryId)) continue;
          catExperiences[categoryId]!.add(experience);
        }
      }

      // Also build color category -> experiences map
      final Map<String, List<Experience>> colorCatExperiences = {
        for (final colorCategory in colorCategories) colorCategory.id: []
      };
      final validColorCategoryIds = colorCatExperiences.keys.toSet();

      for (final experience in experiences) {
        final Set<String> associatedColorIds = {
          if (experience.colorCategoryId != null &&
              experience.colorCategoryId!.isNotEmpty)
            experience.colorCategoryId!,
          ...experience.otherColorCategoryIds.where((id) => id.isNotEmpty),
        };
        for (final colorId in associatedColorIds) {
          if (validColorCategoryIds.contains(colorId)) {
            colorCatExperiences[colorId]!.add(experience);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _publicCategories = categories;
        _publicColorCategories = colorCategories;
        _categoryExperiences = catExperiences;
        _publicExperienceCount = totalPublicExperiences;
        // Store color category experiences in the same map for consistency
        _categoryExperiences.addAll(colorCatExperiences);
        _isLoadingCollections = false;
      });
    } catch (e) {
      debugPrint('PublicProfileScreen: error loading collections - $e');
      if (!mounted) return;
      setState(() {
        _publicCategories = [];
        _publicColorCategories = [];
        _categoryExperiences = {};
        _isLoadingCollections = false;
        _publicExperienceCount = 0;
      });
    }
  }

  /// Load public collections using REST API (for unauthenticated users)
  Future<void> _loadPublicCollectionsViaRest() async {
    try {
      final appCheckToken = await FirebaseAppCheck.instance.getToken(true);
      final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (apiKey.isNotEmpty) 'x-goog-api-key': apiKey,
        if (appCheckToken != null && appCheckToken.isNotEmpty)
          'X-Firebase-AppCheck': appCheckToken,
      };

      const projectId = 'plendy-7df50';

      // Fetch categories via REST
      final categoriesUrl = Uri.parse(
          'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/users/${widget.userId}/categories');
      final categoriesResp = await http.get(categoriesUrl, headers: headers);

      // Fetch experiences via REST query with pagination
      final experiencesQueryUrl = Uri.parse(
          'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents:runQuery');

      // Fetch all experiences using pagination
      final List<Map<String, dynamic>> allExperienceResults = [];
      String? lastDocPath;
      bool hasMore = true;
      const int pageSize = 500;

      while (hasMore) {
        final Map<String, dynamic> structuredQuery = {
          'from': [
            {'collectionId': 'experiences'}
          ],
          'where': {
            'fieldFilter': {
              'field': {'fieldPath': 'createdBy'},
              'op': 'EQUAL',
              'value': {'stringValue': widget.userId}
            }
          },
          'orderBy': [
            {
              'field': {'fieldPath': '__name__'},
              'direction': 'ASCENDING'
            }
          ],
          'limit': pageSize,
        };

        // Add startAfter for pagination
        if (lastDocPath != null) {
          structuredQuery['startAt'] = {
            'values': [
              {'referenceValue': lastDocPath}
            ],
            'before': false, // startAfter behavior
          };
        }

        final experiencesPayload = {'structuredQuery': structuredQuery};
        final experiencesResp = await http.post(
          experiencesQueryUrl,
          headers: headers,
          body: json.encode(experiencesPayload),
        );

        if (experiencesResp.statusCode == 200) {
          final results = json.decode(experiencesResp.body) as List;
          final pageResults = results
              .whereType<Map<String, dynamic>>()
              .where((r) => r.containsKey('document'))
              .toList();

          allExperienceResults.addAll(pageResults);

          if (pageResults.length < pageSize) {
            hasMore = false;
          } else {
            // Get the last document path for the next page
            final lastDoc =
                pageResults.last['document'] as Map<String, dynamic>;
            lastDocPath = lastDoc['name'] as String?;
            if (lastDocPath == null) {
              hasMore = false;
            }
          }
        } else {
          debugPrint(
              'PublicProfileScreen: Experiences query returned ${experiencesResp.statusCode}');
          hasMore = false;
        }
      }

      debugPrint(
          'PublicProfileScreen: Fetched ${allExperienceResults.length} total experience results via REST');

      // Parse categories
      final List<UserCategory> categories = [];
      if (categoriesResp.statusCode == 200) {
        final body = json.decode(categoriesResp.body) as Map<String, dynamic>;
        final docs = (body['documents'] as List?) ?? [];
        for (final doc in docs) {
          try {
            final category =
                _parseCategoryFromRest(doc as Map<String, dynamic>);
            if (category != null && !category.isPrivate) {
              categories.add(category);
            }
          } catch (e) {
            debugPrint(
                'PublicProfileScreen: skipping invalid category via REST - $e');
          }
        }
      }

      categories
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      debugPrint(
          'PublicProfileScreen: Loaded ${categories.length} categories via REST');

      // Parse experiences from paginated results
      final List<Experience> experiences = [];
      for (final result in allExperienceResults) {
        try {
          final experience = _parseExperienceFromRest(
              result['document'] as Map<String, dynamic>);
          if (experience != null && !experience.isPrivate) {
            experiences.add(experience);
          }
        } catch (e) {
          debugPrint(
              'PublicProfileScreen: skipping invalid experience via REST - $e');
        }
      }
      debugPrint(
          'PublicProfileScreen: Loaded ${experiences.length} public experiences via REST');

      // Sort experiences alphabetically
      experiences.sort((a, b) {
        final aName = a.name.toLowerCase();
        final bName = b.name.toLowerCase();
        return aName.compareTo(bName);
      });
      final int totalPublicExperiences = experiences.length;

      // Build color categories list from public experiences
      final Set<String> colorCategoryIds = {};
      for (final experience in experiences) {
        if (experience.colorCategoryId != null &&
            experience.colorCategoryId!.isNotEmpty) {
          colorCategoryIds.add(experience.colorCategoryId!);
        }
        for (final colorId in experience.otherColorCategoryIds) {
          if (colorId.isNotEmpty) {
            colorCategoryIds.add(colorId);
          }
        }
      }

      // Fetch color categories via REST
      final List<ColorCategory> colorCategories = [];
      if (colorCategoryIds.isNotEmpty) {
        try {
          final colorCategoriesUrl = Uri.parse(
              'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/users/${widget.userId}/color_categories');
          final colorCategoriesResp =
              await http.get(colorCategoriesUrl, headers: headers);

          if (colorCategoriesResp.statusCode == 200) {
            final body =
                json.decode(colorCategoriesResp.body) as Map<String, dynamic>;
            final docs = (body['documents'] as List?) ?? [];
            for (final doc in docs) {
              try {
                final colorCategory =
                    _parseColorCategoryFromRest(doc as Map<String, dynamic>);
                if (colorCategory != null &&
                    !colorCategory.isPrivate &&
                    colorCategoryIds.contains(colorCategory.id)) {
                  colorCategories.add(colorCategory);
                }
              } catch (e) {
                debugPrint(
                    'PublicProfileScreen: skipping invalid color category via REST - $e');
              }
            }
          }
        } catch (e) {
          debugPrint(
              'PublicProfileScreen: Could not load color categories via REST - $e');
        }
      }

      // Build category -> experiences map
      final Map<String, List<Experience>> catExperiences = {
        for (final category in categories) category.id: []
      };
      final categoryIds = catExperiences.keys.toSet();

      for (final experience in experiences) {
        final Set<String> relevantCategoryIds = {
          if (experience.categoryId != null) experience.categoryId!,
          ...experience.otherCategories,
        };
        for (final categoryId in relevantCategoryIds) {
          if (!categoryIds.contains(categoryId)) continue;
          catExperiences[categoryId]!.add(experience);
        }
      }

      // Build color category -> experiences map
      final Map<String, List<Experience>> colorCatExperiences = {
        for (final colorCategory in colorCategories) colorCategory.id: []
      };
      final validColorCategoryIds = colorCatExperiences.keys.toSet();

      for (final experience in experiences) {
        final Set<String> associatedColorIds = {
          if (experience.colorCategoryId != null &&
              experience.colorCategoryId!.isNotEmpty)
            experience.colorCategoryId!,
          ...experience.otherColorCategoryIds.where((id) => id.isNotEmpty),
        };
        for (final colorId in associatedColorIds) {
          if (validColorCategoryIds.contains(colorId)) {
            colorCatExperiences[colorId]!.add(experience);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _publicCategories = categories;
        _publicColorCategories = colorCategories;
        _categoryExperiences = catExperiences;
        _publicExperienceCount = totalPublicExperiences;
        _categoryExperiences.addAll(colorCatExperiences);
        _isLoadingCollections = false;
      });
    } catch (e) {
      debugPrint(
          'PublicProfileScreen: error loading collections via REST - $e');
      if (!mounted) return;
      setState(() {
        _publicCategories = [];
        _publicColorCategories = [];
        _categoryExperiences = {};
        _isLoadingCollections = false;
        _publicExperienceCount = 0;
      });
    }
  }

  /// Load reviews posted by this user
  Future<void> _loadUserReviews() async {
    if (!mounted) return;

    // Skip loading reviews if profile is private and viewer doesn't have access
    final bool isPrivate = _profile?.isPrivate ?? false;
    final bool isOwner =
        _currentUserId != null && _currentUserId == widget.userId;
    if (isPrivate && !isOwner && !_isFollowing) {
      setState(() {
        _userReviews = [];
        _isLoadingReviews = false;
      });
      return;
    }

    setState(() => _isLoadingReviews = true);

    try {
      final reviews = await _experienceService.getReviewsByUser(widget.userId);

      // Fetch experience data for each review
      final Set<String> experienceIds = reviews
          .map((r) => r.experienceId)
          .where((id) => id.isNotEmpty)
          .toSet();

      for (final expId in experienceIds) {
        if (!_reviewExperienceCache.containsKey(expId)) {
          try {
            final experience = await _experienceService.getExperience(expId);
            if (experience != null) {
              _reviewExperienceCache[expId] = experience;

              // If denormalized fields are missing, fetch category from owner
              await _fetchExperienceCategoryIfNeeded(experience);
            }
          } catch (e) {
            debugPrint(
                'PublicProfileScreen: Could not load experience $expId for review - $e');
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _userReviews = reviews;
        _isLoadingReviews = false;
      });
    } catch (e) {
      debugPrint('PublicProfileScreen: error loading user reviews - $e');
      if (!mounted) return;
      setState(() {
        _userReviews = [];
        _isLoadingReviews = false;
      });
    }
  }

  /// Fetch category and color category from experience owner if denormalized fields are missing
  Future<void> _fetchExperienceCategoryIfNeeded(Experience experience) async {
    final ownerId = experience.createdBy;
    if (ownerId == null || ownerId.isEmpty) return;

    // Check if we need to fetch category
    final bool needsCategory = (experience.categoryIconDenorm == null ||
            experience.categoryIconDenorm!.isEmpty) &&
        experience.categoryId != null &&
        experience.categoryId!.isNotEmpty &&
        !_externalCategoryCache.containsKey(experience.categoryId);

    // Check if we need to fetch color category
    final bool needsColorCategory = (experience.colorHexDenorm == null ||
            experience.colorHexDenorm!.isEmpty) &&
        experience.colorCategoryId != null &&
        experience.colorCategoryId!.isNotEmpty &&
        !_externalColorCategoryCache.containsKey(experience.colorCategoryId);

    if (!needsCategory && !needsColorCategory) return;

    try {
      // Fetch category from owner's categories subcollection
      if (needsCategory && experience.categoryId != null) {
        final categoryDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(ownerId)
            .collection('categories')
            .doc(experience.categoryId)
            .get();

        if (categoryDoc.exists) {
          final category = UserCategory.fromFirestore(categoryDoc);
          _externalCategoryCache[experience.categoryId!] = category;
        }
      }

      // Fetch color category from owner's color_categories subcollection
      if (needsColorCategory && experience.colorCategoryId != null) {
        final colorCategoryDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(ownerId)
            .collection('color_categories')
            .doc(experience.colorCategoryId)
            .get();

        if (colorCategoryDoc.exists) {
          final colorCategory = ColorCategory.fromFirestore(colorCategoryDoc);
          _externalColorCategoryCache[experience.colorCategoryId!] =
              colorCategory;
        }
      }
    } catch (e) {
      debugPrint(
          'PublicProfileScreen: Could not fetch category info for experience ${experience.id} - $e');
    }
  }

  /// Parse a UserCategory from Firestore REST API response
  UserCategory? _parseCategoryFromRest(Map<String, dynamic> doc) {
    final name = doc['name'] as String?;
    if (name == null) return null;

    final fields = (doc['fields'] as Map<String, dynamic>?) ?? {};
    final docId = name.split('/').last;

    return UserCategory(
      id: docId,
      name: _getStringField(fields, 'name') ?? '',
      icon: _getStringField(fields, 'icon') ?? '📁',
      ownerUserId: widget.userId,
      isPrivate: _getBoolField(fields, 'isPrivate') ?? false,
    );
  }

  /// Parse an Experience from Firestore REST API response
  Experience? _parseExperienceFromRest(Map<String, dynamic> doc) {
    final name = doc['name'] as String?;
    if (name == null) return null;

    final fields = (doc['fields'] as Map<String, dynamic>?) ?? {};
    final docId = name.split('/').last;

    final locFields = _getMapField(fields, 'location') ?? {};
    final location = Location(
      placeId: _getStringField(locFields, 'placeId'),
      latitude: _getDoubleField(locFields, 'latitude') ?? 0.0,
      longitude: _getDoubleField(locFields, 'longitude') ?? 0.0,
      address: _getStringField(locFields, 'address'),
      city: _getStringField(locFields, 'city'),
      state: _getStringField(locFields, 'state'),
      country: _getStringField(locFields, 'country'),
      displayName: _getStringField(locFields, 'displayName'),
    );

    return Experience(
      id: docId,
      name: _getStringField(fields, 'name') ?? '',
      description: _getStringField(fields, 'description') ?? '',
      location: location,
      categoryId: _getStringField(fields, 'categoryId'),
      imageUrls: _getStringListField(fields, 'imageUrls'),
      plendyRating: _getDoubleField(fields, 'plendyRating') ?? 0.0,
      rating: _getDoubleField(fields, 'plendyRating') ?? 0.0,
      createdAt: _getTimestampField(fields, 'createdAt') ?? DateTime.now(),
      updatedAt: _getTimestampField(fields, 'updatedAt') ?? DateTime.now(),
      colorCategoryId: _getStringField(fields, 'colorCategoryId'),
      otherCategories: _getStringListField(fields, 'otherCategories'),
      otherColorCategoryIds:
          _getStringListField(fields, 'otherColorCategoryIds'),
      isPrivate: _getBoolField(fields, 'isPrivate') ?? false,
      categoryIconDenorm: _getStringField(fields, 'categoryIconDenorm'),
      colorHexDenorm: _getStringField(fields, 'colorHexDenorm'),
      editorUserIds: _getStringListField(fields, 'editorUserIds'),
      sharedMediaItemIds: _getStringListField(fields, 'sharedMediaItemIds'),
    );
  }

  /// Parse a ColorCategory from Firestore REST API response
  ColorCategory? _parseColorCategoryFromRest(Map<String, dynamic> doc) {
    final name = doc['name'] as String?;
    if (name == null) return null;

    final fields = (doc['fields'] as Map<String, dynamic>?) ?? {};
    final docId = name.split('/').last;

    // Get color as hex string - try both 'colorHex' and 'color' fields
    String colorHex = _getStringField(fields, 'colorHex') ?? '';
    if (colorHex.isEmpty) {
      // Fallback: try to get color as integer and convert to hex
      final colorValue = _getIntField(fields, 'color');
      if (colorValue != null) {
        colorHex = colorValue.toRadixString(16).padLeft(8, '0').toUpperCase();
      } else {
        colorHex = 'FF808080'; // Default gray
      }
    }

    return ColorCategory(
      id: docId,
      name: _getStringField(fields, 'name') ?? '',
      colorHex: colorHex,
      ownerUserId: widget.userId,
      isPrivate: _getBoolField(fields, 'isPrivate') ?? false,
    );
  }

  // REST API field parsing helpers
  String? _getStringField(Map<String, dynamic> fields, String fieldName) {
    final field = fields[fieldName] as Map<String, dynamic>?;
    if (field == null) return null;
    return field['stringValue'] as String?;
  }

  bool? _getBoolField(Map<String, dynamic> fields, String fieldName) {
    final field = fields[fieldName] as Map<String, dynamic>?;
    if (field == null) return null;
    return field['booleanValue'] as bool?;
  }

  double? _getDoubleField(Map<String, dynamic> fields, String fieldName) {
    final field = fields[fieldName] as Map<String, dynamic>?;
    if (field == null) return null;
    if (field.containsKey('doubleValue')) {
      return (field['doubleValue'] as num?)?.toDouble();
    }
    if (field.containsKey('integerValue')) {
      return double.tryParse(field['integerValue'] as String? ?? '');
    }
    return null;
  }

  int? _getIntField(Map<String, dynamic> fields, String fieldName) {
    final field = fields[fieldName] as Map<String, dynamic>?;
    if (field == null) return null;
    if (field.containsKey('integerValue')) {
      return int.tryParse(field['integerValue'] as String? ?? '');
    }
    return null;
  }

  DateTime? _getTimestampField(Map<String, dynamic> fields, String fieldName) {
    final field = fields[fieldName] as Map<String, dynamic>?;
    if (field == null) return null;
    final timestamp = field['timestampValue'] as String?;
    if (timestamp == null) return null;
    return DateTime.tryParse(timestamp);
  }

  List<String> _getStringListField(
      Map<String, dynamic> fields, String fieldName) {
    final field = fields[fieldName] as Map<String, dynamic>?;
    if (field == null) return [];
    final arrayValue = field['arrayValue'] as Map<String, dynamic>?;
    if (arrayValue == null) return [];
    final values = arrayValue['values'] as List?;
    if (values == null) return [];
    return values
        .map((v) => (v as Map<String, dynamic>)['stringValue'] as String?)
        .where((s) => s != null)
        .cast<String>()
        .toList();
  }

  Map<String, dynamic>? _getMapField(
      Map<String, dynamic> fields, String fieldName) {
    final field = fields[fieldName] as Map<String, dynamic>?;
    if (field == null) return null;
    final mapValue = field['mapValue'] as Map<String, dynamic>?;
    if (mapValue == null) return null;
    return mapValue['fields'] as Map<String, dynamic>?;
  }

  Future<void> _shareProfile(UserProfile profile) async {
    if (!mounted) return;

    await showShareExperienceBottomSheet(
      context: context,
      titleText: 'Share Profile',
      onDirectShare: () => _directShareProfile(profile),
      onCreateLink: ({
        required String shareMode,
        required bool giveEditAccess,
      }) =>
          _createLinkShareForProfile(profile),
    );
  }

  Future<void> _directShareProfile(UserProfile profile) async {
    if (!mounted) return;

    final String displayName =
        profile.displayName ?? profile.username ?? 'User';

    final result = await showShareToFriendsModal(
      context: context,
      subjectLabel: displayName,
      onSubmit: (recipientIds) async {
        final threadIds = await _sendProfileShareToUsers(profile, recipientIds);
        return DirectShareResult(threadIds: threadIds);
      },
      onSubmitToThreads: (threadIds) async {
        final successThreadIds =
            await _sendProfileShareToThreads(profile, threadIds);
        return DirectShareResult(threadIds: successThreadIds);
      },
      onSubmitToNewGroupChat: (participantIds) async {
        final threadId =
            await _sendProfileShareToNewGroupChat(profile, participantIds);
        return DirectShareResult(threadIds: threadId != null ? [threadId] : []);
      },
    );

    if (!mounted) return;
    if (result != null) {
      showSharedWithFriendsSnackbar(context, result);
    }
  }

  Map<String, dynamic> _buildProfileSnapshot(UserProfile profile) {
    return {
      'userId': profile.id,
      'displayName': profile.displayName,
      'username': profile.username,
      'photoURL': profile.photoURL,
      'bio': profile.bio,
    };
  }

  Future<List<String>> _sendProfileShareToUsers(
    UserProfile profile,
    List<String> recipientIds,
  ) async {
    if (_currentUserId == null) return [];
    final messageService = MessageService();
    final profileSnapshot = _buildProfileSnapshot(profile);
    final List<String> threadIds = [];

    for (final recipientId in recipientIds) {
      try {
        final thread = await messageService.createOrGetThread(
          currentUserId: _currentUserId!,
          participantIds: [recipientId],
        );
        await messageService.sendProfileShareMessage(
          threadId: thread.id,
          senderId: _currentUserId!,
          profileSnapshot: profileSnapshot,
        );
        threadIds.add(thread.id);
      } catch (e) {
        debugPrint('Failed to send profile share to $recipientId: $e');
      }
    }
    return threadIds;
  }

  Future<List<String>> _sendProfileShareToThreads(
    UserProfile profile,
    List<String> threadIds,
  ) async {
    if (_currentUserId == null) return [];
    final messageService = MessageService();
    final profileSnapshot = _buildProfileSnapshot(profile);
    final List<String> successThreadIds = [];

    for (final threadId in threadIds) {
      try {
        await messageService.sendProfileShareMessage(
          threadId: threadId,
          senderId: _currentUserId!,
          profileSnapshot: profileSnapshot,
        );
        successThreadIds.add(threadId);
      } catch (e) {
        debugPrint('Failed to send profile share to thread $threadId: $e');
      }
    }
    return successThreadIds;
  }

  Future<String?> _sendProfileShareToNewGroupChat(
    UserProfile profile,
    List<String> participantIds,
  ) async {
    if (_currentUserId == null) return null;
    final messageService = MessageService();
    final profileSnapshot = _buildProfileSnapshot(profile);

    try {
      final thread = await messageService.createOrGetThread(
        currentUserId: _currentUserId!,
        participantIds: participantIds,
      );
      await messageService.sendProfileShareMessage(
        threadId: thread.id,
        senderId: _currentUserId!,
        profileSnapshot: profileSnapshot,
      );
      return thread.id;
    } catch (e) {
      debugPrint('Failed to create group chat for profile share: $e');
      return null;
    }
  }

  Future<void> _createLinkShareForProfile(UserProfile profile) async {
    if (!mounted) return;

    final String displayName =
        profile.displayName ?? profile.username ?? 'this user';
    final String profileUrl = 'https://plendy.app/profile/${profile.id}';

    Navigator.of(context).pop(); // Close the bottom sheet
    await Share.share(
        'Check out $displayName\'s profile on Plendy! $profileUrl');
  }

  Future<void> _handleFollowButton() async {
    if (_currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to follow users.')),
      );
      return;
    }

    setState(() {
      _isProcessingFollow = true;
    });

    try {
      if (_isFollowing) {
        await _userService.unfollowUser(_currentUserId!, widget.userId);
      } else {
        await _userService.followUser(_currentUserId!, widget.userId);
      }
      await _loadProfile(showFullPageLoader: false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Unable to update follow status. ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingFollow = false;
        });
      }
    }
  }

  Future<void> _prefetchExperienceMedia(Experience experience) async {
    if (experience.sharedMediaItemIds.isEmpty) {
      return;
    }
    if (_experienceMediaCache.containsKey(experience.id)) {
      return;
    }
    if (_mediaPrefetchInFlight.contains(experience.id)) {
      return;
    }
    _mediaPrefetchInFlight.add(experience.id);
    try {
      final items = await _experienceService
          .getSharedMediaItems(experience.sharedMediaItemIds);
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _experienceMediaCache[experience.id] = items;
      });
    } catch (e) {
      debugPrint('Error prefetching media for ${experience.name}: $e');
    } finally {
      _mediaPrefetchInFlight.remove(experience.id);
    }
  }

  Future<void> _navigateToExperience(
      Experience experience, UserCategory category) async {
    // Navigate to experience page in read-only mode
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => ExperiencePageScreen(
          experience: experience,
          category: category,
          userColorCategories: _publicColorCategories,
          additionalUserCategories: _publicCategories,
          readOnlyPreview: true,
        ),
      ),
    );

    if (result == true && mounted) {
      // Reload data if changes were made
      await _loadPublicCollections();
    }
  }

  Future<void> _showMediaPreview(
      Experience experience, UserCategory category) async {
    final List<SharedMediaItem>? cachedItems =
        _experienceMediaCache[experience.id];
    late final List<SharedMediaItem> resolvedItems;

    if (cachedItems == null) {
      if (experience.sharedMediaItemIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'No saved content available yet for this experience.')),
          );
        }
        return;
      }
      try {
        final fetched = await _experienceService
            .getSharedMediaItems(experience.sharedMediaItemIds);
        fetched.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        resolvedItems = fetched;
        if (mounted) {
          setState(() {
            _experienceMediaCache[experience.id] = fetched;
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not load content preview: $e')),
          );
        }
        return;
      }
    } else {
      resolvedItems = cachedItems;
    }

    if (resolvedItems.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('No saved content available yet for this experience.')),
        );
      }
      return;
    }

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      builder: (modalContext) {
        return SharedMediaPreviewModal(
          experience: experience,
          mediaItem: resolvedItems.first,
          mediaItems: resolvedItems,
          onLaunchUrl: _launchUrl,
          category: category,
          userColorCategories: _publicColorCategories,
          additionalUserCategories: _publicCategories,
        );
      },
    );
  }

  Future<void> _launchUrl(String urlString) async {
    // Skip invalid URLs
    if (urlString.isEmpty ||
        urlString == 'about:blank' ||
        urlString == 'https://about:blank') {
      return;
    }

    // Ensure URL starts with http/https
    String launchableUrl = urlString;
    if (!launchableUrl.startsWith('http://') &&
        !launchableUrl.startsWith('https://')) {
      launchableUrl = 'https://$launchableUrl';
    }

    try {
      final Uri uri = Uri.parse(launchableUrl);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open link: $urlString')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid URL: $urlString')),
        );
      }
    }
  }

  String _getProfileInitial(UserProfile profile) {
    final displayName = profile.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName[0].toUpperCase();
    }
    final username = profile.username?.trim();
    if (username != null && username.isNotEmpty) {
      return username[0].toUpperCase();
    }
    return '?';
  }

  Widget _buildAvatar(UserProfile profile) {
    final fallbackLetter = _getProfileInitial(profile);

    return CachedProfileAvatar(
      photoUrl: profile.photoURL,
      radius: 60,
      fallbackText: fallbackLetter,
      backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
    );
  }

  Widget _buildCountTile({
    required String label,
    required int count,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$count',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<UserProfile>> _fetchProfiles(List<String> userIds) async {
    if (userIds.isEmpty) return [];
    final profiles = await Future.wait(
      userIds.map((id) => _userService.getUserProfile(id)),
    );
    return profiles.whereType<UserProfile>().toList();
  }

  Widget _buildProfileAvatar(UserProfile profile, {double size = 40}) {
    final fallbackLetter = _getProfileInitial(profile);

    return CachedProfileAvatar(
      photoUrl: profile.photoURL,
      radius: size / 2,
      fallbackText: fallbackLetter,
    );
  }

  void _showProfilePhotoDialog(UserProfile profile) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final photoUrl = profile.photoURL;
        final hasPhoto = photoUrl?.isNotEmpty ?? false;
        final fallbackLetter = _getProfileInitial(profile);
        final Widget photoContent = hasPhoto
            ? InteractiveViewer(
                child: Image.network(
                  photoUrl!,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Center(child: CircularProgressIndicator());
                  },
                  errorBuilder: (context, _, __) {
                    return Center(
                      child: Text(
                        fallbackLetter,
                        style: const TextStyle(
                          fontSize: 100,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    );
                  },
                ),
              )
            : Center(
                child: Text(
                  fallbackLetter,
                  style: const TextStyle(
                    fontSize: 100,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              );

        return Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  color: Colors.black,
                  width: double.infinity,
                  height: 320,
                  alignment: Alignment.center,
                  child: photoContent,
                ),
                Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Center(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Theme.of(context).primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        child: Text('Close'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showUserListDialog({
    required String title,
    required List<String> userIds,
    required String emptyMessage,
  }) async {
    final parentContext = context;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final maxHeight = MediaQuery.of(dialogContext).size.height * 0.6;
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: FutureBuilder<List<UserProfile>>(
                future: _fetchProfiles(userIds),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final profiles = snapshot.data ?? [];
                  if (profiles.isEmpty) {
                    return Center(
                      child: Text(
                        emptyMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: profiles.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final profile = profiles[index];
                      final bool hasDisplayName =
                          profile.displayName?.isNotEmpty ?? false;
                      final bool hasUsername =
                          profile.username?.isNotEmpty ?? false;
                      final String titleText = hasDisplayName
                          ? profile.displayName!
                          : (hasUsername
                              ? '@${profile.username!}'
                              : 'Plendy user');
                      final String? subtitleText = hasDisplayName && hasUsername
                          ? '@${profile.username!}'
                          : null;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _buildProfileAvatar(profile),
                        title: Text(titleText),
                        subtitle:
                            subtitleText != null ? Text(subtitleText) : null,
                        onTap: () {
                          Navigator.of(dialogContext).pop();
                          Navigator.of(parentContext).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  PublicProfileScreen(userId: profile.id),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openFollowingDialog() async {
    await _showUserListDialog(
      title: 'Following',
      userIds: _followingIds,
      emptyMessage: 'Not following anyone yet.',
    );
  }

  Future<void> _openFollowersDialog() async {
    await _showUserListDialog(
      title: 'Followers',
      userIds: _followerIds,
      emptyMessage: 'No one follows this profile yet.',
    );
  }

  Widget _buildFollowButton() {
    if (_currentUserId == null || _currentUserId == widget.userId) {
      return const SizedBox.shrink();
    }

    String label;
    Color backgroundColor;
    Color foregroundColor;
    VoidCallback? onPressed = _handleFollowButton;

    if (_isFollowing) {
      label = 'Unfollow';
      backgroundColor = Colors.grey[200]!;
      foregroundColor = Colors.black87;
    } else if (_hasPendingRequest) {
      label = 'Requested';
      backgroundColor = Colors.grey[300]!;
      foregroundColor = Colors.black54;
      onPressed = null;
    } else if (_ownerFollowsViewer) {
      label = 'Follow back';
      backgroundColor = Theme.of(context).primaryColor;
      foregroundColor = Colors.white;
    } else {
      label = 'Follow';
      backgroundColor = Theme.of(context).primaryColor;
      foregroundColor = Colors.white;
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed:
            (_isProcessingFollow || onPressed == null) ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: backgroundColor,
          disabledForegroundColor: foregroundColor,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: _isProcessingFollow
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: foregroundColor),
              )
            : Text(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final bool viewingOwnProfile =
        _currentUserId != null && _currentUserId == widget.userId;

    // Check if profile is private and viewer doesn't have access
    final bool isPrivateProfile = profile?.isPrivate ?? false;
    final bool canViewPrivateProfile = viewingOwnProfile || _isFollowing;
    final bool showPrivateMessage = isPrivateProfile && !canViewPrivateProfile;

    Widget content;
    if (_isLoading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (profile == null) {
      content = const Center(child: Text('This profile is not available.'));
    } else if (showPrivateMessage) {
      // Show private profile message
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildAvatar(profile),
              const SizedBox(height: 16),
              if (profile.displayName?.isNotEmpty == true)
                Text(
                  profile.displayName!,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
              if (profile.username?.isNotEmpty == true)
                Text(
                  '@${profile.username!}',
                  style: TextStyle(color: Colors.grey[700]),
                ),
              const SizedBox(height: 24),
              const Icon(Icons.lock_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'This profile is private',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _currentUserId == null
                    ? 'Sign in and follow this user to see their profile.'
                    : 'Follow this user to see their profile.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              _buildFollowButton(),
            ],
          ),
        ),
      );
    } else {
      final bool hasDisplayName = profile.displayName?.isNotEmpty ?? false;
      final bool hasUsername = profile.username?.isNotEmpty ?? false;
      final String? bioText = profile.bio?.trim();
      final bool hasBio = bioText?.isNotEmpty ?? false;
      final bool hasIdentityText = hasDisplayName || hasUsername;
      content = SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _showProfilePhotoDialog(profile),
                  child: _buildAvatar(profile),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasDisplayName)
                        Text(
                          profile.displayName!,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      if (hasDisplayName) const SizedBox(height: 4),
                      if (hasUsername)
                        Text(
                          '@${profile.username!}',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      if (hasIdentityText) const SizedBox(height: 8),
                      if (hasIdentityText) const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildCountTile(
                              label: 'Following',
                              count: _followingCount,
                              onTap: _openFollowingDialog,
                            ),
                          ),
                          Expanded(
                            child: _buildCountTile(
                              label: 'Followers',
                              count: _followersCount,
                              onTap: _openFollowersDialog,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildFollowButton(),
            if (hasBio) ...[
              const SizedBox(height: 24),
              Text(
                bioText!,
                style: const TextStyle(fontSize: 16),
              ),
            ],
            const SizedBox(height: 24),
            _buildProfileTabs(),
          ],
        ),
      );
    }

    return WillPopScope(
      onWillPop: _handleBackNavigation,
      child: Scaffold(
        backgroundColor: AppColors.backgroundColor,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _handleBackNavigation(),
          ),
          title: viewingOwnProfile ? const Text('Public Profile') : null,
          backgroundColor: AppColors.backgroundColor,
          foregroundColor: Colors.black,
          elevation: 0,
          actions: [
            if (profile != null)
              IconButton(
                icon: const Icon(Icons.share_outlined, color: Colors.blue),
                tooltip: 'Share Profile',
                onPressed: () => _shareProfile(profile),
              ),
          ],
        ),
        body: SafeArea(child: content),
      ),
    );
  }

  Widget _buildProfileTabs() {
    final theme = Theme.of(context);
    final tabBar = TabBar(
      controller: _tabController,
      labelColor: theme.primaryColor,
      unselectedLabelColor: Colors.grey[600],
      indicatorColor: theme.primaryColor,
      tabs: const [
        Tab(
          icon: Icon(Icons.collections_outlined),
          text: 'Collection',
        ),
        Tab(
          icon: Icon(Icons.rate_review_outlined),
          text: 'Reviews',
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tabBar,
        const SizedBox(height: 12),
        SizedBox(
          height: 400,
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildCollectionTab(),
              _buildReviewsTab(),
            ],
          ),
        ),
      ],
    );
  }

  /// Build the reviews tab showing all reviews posted by this user
  Widget _buildReviewsTab() {
    if (_isLoadingReviews) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_userReviews.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.rate_review_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No reviews yet',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _userReviews.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildReviewCountHeader(_userReviews.length);
        }
        final review = _userReviews[index - 1];
        return _buildUserReviewCard(review);
      },
    );
  }

  /// Build the header showing total review count
  Widget _buildReviewCountHeader(int count) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: const BoxDecoration(color: Colors.white),
      child: Text(
        '$count ${count == 1 ? 'Review' : 'Reviews'}',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w400,
              color: Colors.grey,
            ),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// Build a review card that shows experience info instead of user info
  Widget _buildUserReviewCard(Review review) {
    final experience = _reviewExperienceCache[review.experienceId];
    final timeAgo = _formatTimeAgo(review.createdAt);

    // Get category icon and color from experience
    String categoryIcon = '📍';
    Color leadingBoxColor = Colors.grey.withOpacity(0.3);

    if (experience != null) {
      // Try to get icon from denormalized field first
      if (experience.categoryIconDenorm != null &&
          experience.categoryIconDenorm!.isNotEmpty) {
        categoryIcon = experience.categoryIconDenorm!;
      } else if (experience.categoryId != null) {
        // Try profile owner's categories first
        final category = _publicCategories.firstWhereOrNull(
          (cat) => cat.id == experience.categoryId,
        );
        if (category != null) {
          categoryIcon = category.icon;
        } else {
          // Fallback to external category cache (from experience owner)
          final externalCategory =
              _externalCategoryCache[experience.categoryId];
          if (externalCategory != null) {
            categoryIcon = externalCategory.icon;
          }
        }
      }

      // Get color from denormalized field first
      if (experience.colorHexDenorm != null &&
          experience.colorHexDenorm!.isNotEmpty) {
        leadingBoxColor =
            _parseColor(experience.colorHexDenorm!).withOpacity(0.5);
      } else if (experience.colorCategoryId != null) {
        // Try profile owner's color categories first
        final colorCategory = _publicColorCategories.firstWhereOrNull(
          (cc) => cc.id == experience.colorCategoryId,
        );
        if (colorCategory != null) {
          leadingBoxColor = colorCategory.color.withOpacity(0.5);
        } else {
          // Fallback to external color category cache (from experience owner)
          final externalColorCategory =
              _externalColorCategoryCache[experience.colorCategoryId];
          if (externalColorCategory != null) {
            leadingBoxColor = externalColorCategory.color.withOpacity(0.5);
          }
        }
      }
    }

    // Experience name and address
    final String experienceName = experience?.name ?? 'Unknown Experience';
    final String? experienceAddress = experience?.location.address;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 1,
      color: const Color.fromARGB(225, 250, 250, 250),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Category icon box, Experience name, Address, Time
            InkWell(
              onTap: experience != null
                  ? () => _navigateToExperienceFromReview(experience)
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  // Category icon box (replaces user avatar)
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: leadingBoxColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      categoryIcon,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Experience Name and Address (replaces user name)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          experienceName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (experienceAddress != null &&
                            experienceAddress.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            experienceAddress,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 2),
                        Text(
                          timeAgo,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Rating Icon
                  if (review.isPositive != null)
                    Icon(
                      review.isPositive! ? Icons.thumb_up : Icons.thumb_down,
                      color: review.isPositive! ? Colors.green : Colors.red,
                      size: 18,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Review Content
            Text(
              review.content,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
              ),
            ),
            // Review Photos
            if (review.imageUrls.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildReviewPhotoGallery(review.imageUrls),
            ],
          ],
        ),
      ),
    );
  }

  /// Navigate to experience page from a review card
  Future<void> _navigateToExperienceFromReview(Experience experience) async {
    // Find the category for this experience
    final UserCategory? category = _publicCategories.firstWhereOrNull(
      (cat) => cat.id == experience.categoryId,
    );

    // Create a fallback category if not found
    final UserCategory displayCategory = category ??
        UserCategory(
          id: experience.categoryId ?? '',
          name: 'Uncategorized',
          icon: experience.categoryIconDenorm ?? '📍',
          ownerUserId: widget.userId,
        );

    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => ExperiencePageScreen(
          experience: experience,
          category: displayCategory,
          userColorCategories: _publicColorCategories,
          additionalUserCategories: _publicCategories,
          readOnlyPreview: true,
        ),
      ),
    );
  }

  /// Build a photo gallery for review images
  Widget _buildReviewPhotoGallery(List<String> imageUrls) {
    if (imageUrls.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: imageUrls.length,
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () => _showFullScreenReviewImage(imageUrls, index),
            child: Container(
              width: 80,
              height: 80,
              margin:
                  EdgeInsets.only(right: index < imageUrls.length - 1 ? 8 : 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                image: DecorationImage(
                  image: NetworkImage(imageUrls[index]),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Show full screen review image viewer
  void _showFullScreenReviewImage(List<String> imageUrls, int initialIndex) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: PageController(initialPage: initialIndex),
              itemCount: imageUrls.length,
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  child: Center(
                    child: Image.network(
                      imageUrls[index],
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Format a DateTime as a human-readable time ago string
  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 365) {
      final years = (difference.inDays / 365).floor();
      return '$years ${years == 1 ? 'year' : 'years'} ago';
    } else if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    } else {
      return 'Just now';
    }
  }

  Widget _buildCollectionTab() {
    return Column(
      children: [
        // Toggle button row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 8.0),
          child: Row(
            children: [
              const Expanded(child: SizedBox()),
              Flexible(
                child: Builder(
                  builder: (context) {
                    final IconData toggleIcon = _showingColorCategories
                        ? Icons.category_outlined
                        : Icons.color_lens_outlined;
                    final String toggleLabel = _showingColorCategories
                        ? 'Categories'
                        : 'Color Categories';

                    void onToggle() {
                      setState(() {
                        _showingColorCategories = !_showingColorCategories;
                        _selectedCategory = null;
                        _selectedColorCategory = null;
                      });
                    }

                    return Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: const VisualDensity(
                                horizontal: -2, vertical: -2),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8.0),
                          ),
                          icon: Icon(toggleIcon),
                          label: Text(toggleLabel),
                          onPressed: onToggle,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        // Main content area
        Expanded(
          child: _buildCollectionContent(),
        ),
      ],
    );
  }

  Widget _buildCollectionContent() {
    // Show selected category's experiences
    if (_selectedCategory != null) {
      return _buildSelectedCategoryExperiencesView();
    }

    // Show selected color category's experiences
    if (_selectedColorCategory != null) {
      return _buildSelectedColorCategoryExperiencesView();
    }

    // Show color categories list or regular categories list
    if (_showingColorCategories) {
      return _buildPublicColorCategoriesList();
    }

    return _buildPublicCategoriesList();
  }

  Widget _buildPublicCategoriesList() {
    if (_isLoadingCollections) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_publicCategories.isEmpty) {
      return const Center(child: Text('No public categories to share yet.'));
    }

    final bool isDesktopWeb = MediaQuery.of(context).size.width > 600;
    final bool showCountHeader = _publicExperienceCount > 0;

    if (isDesktopWeb) {
      final screenWidth = MediaQuery.of(context).size.width;
      const double contentMaxWidth = 1200.0;
      const double defaultPadding = 12.0;

      double horizontalPadding;
      if (screenWidth > contentMaxWidth) {
        horizontalPadding = (screenWidth - contentMaxWidth) / 2;
      } else {
        horizontalPadding = defaultPadding;
      }

      return CustomScrollView(
        slivers: [
          if (showCountHeader)
            SliverToBoxAdapter(
                child: _buildExperienceCountHeader(_publicExperienceCount)),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horizontalPadding, defaultPadding,
                horizontalPadding, defaultPadding),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 10.0,
                crossAxisSpacing: 10.0,
                childAspectRatio: 3 / 3.5,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final category = _publicCategories[index];
                  final experiences = _categoryExperiences[category.id] ?? [];
                  final bool isSelected = _selectedCategory?.id == category.id;

                  return Card(
                    key: ValueKey('category_grid_${category.id}'),
                    clipBehavior: Clip.antiAlias,
                    elevation: 2.0,
                    color: isSelected
                        ? Theme.of(context).primaryColor.withOpacity(0.1)
                        : null,
                    shape: isSelected
                        ? RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4.0),
                            side: BorderSide(
                              color: Theme.of(context).primaryColor,
                              width: 2,
                            ),
                          )
                        : null,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedCategory = null;
                          } else {
                            _selectedCategory = category;
                          }
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: <Widget>[
                            Text(
                              category.icon,
                              style: const TextStyle(fontSize: 32),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              category.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${experiences.length} ${experiences.length == 1 ? "exp" : "exps"}',
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                childCount: _publicCategories.length,
              ),
            ),
          ),
        ],
      );
    }

    final int headerOffset = showCountHeader ? 1 : 0;
    return ListView.builder(
      itemCount: _publicCategories.length + headerOffset,
      itemBuilder: (context, index) {
        if (showCountHeader && index == 0) {
          return _buildExperienceCountHeader(_publicExperienceCount);
        }
        final category = _publicCategories[index - headerOffset];
        final experiences = _categoryExperiences[category.id] ?? [];
        final bool isSelected = _selectedCategory?.id == category.id;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: Padding(
            padding: const EdgeInsets.only(left: 4, right: 8),
            child: Text(
              category.icon,
              style: const TextStyle(fontSize: 24),
            ),
          ),
          title: Text(category.name),
          subtitle: Text(
            '${experiences.length} ${experiences.length == 1 ? 'experience' : 'experiences'}',
          ),
          trailing: isSelected
              ? Icon(Icons.check_circle, color: Theme.of(context).primaryColor)
              : null,
          selected: isSelected,
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedCategory = null;
              } else {
                _selectedCategory = category;
              }
            });
          },
        );
      },
    );
  }

  Widget _buildExperienceListItem(
      Experience experience, UserCategory category) {
    // Determine the true primary category for the experience
    final UserCategory? primaryCategory = _publicCategories.firstWhereOrNull(
      (cat) => cat.id == experience.categoryId,
    );
    final UserCategory displayCategory = primaryCategory ?? category;
    final String categoryIcon = displayCategory.icon;

    // Get the full address
    final fullAddress = experience.location.address;

    // Determine leading box background color from color category with opacity
    final colorCategoryForBox = _publicColorCategories.firstWhereOrNull(
      (cc) => cc.id == experience.colorCategoryId,
    );
    final Color leadingBoxColor = colorCategoryForBox != null
        ? _parseColor(colorCategoryForBox.colorHex).withOpacity(0.5)
        : Colors.white;

    // Number of related content items
    final int contentCount = experience.sharedMediaItemIds.length;

    const double playButtonDiameter = 36.0;
    const double playIconSize = 20.0;
    const double badgeDiameter = 18.0;
    const double badgeFontSize = 11.0;
    const double badgeBorderWidth = 2.0;
    const double badgeOffset = -3.0;

    final List<ColorCategory> otherColorCategories = experience
        .otherColorCategoryIds
        .map((id) =>
            _publicColorCategories.firstWhereOrNull((cc) => cc.id == id))
        .whereType<ColorCategory>()
        .toList();
    final bool hasOtherCategories = experience.otherCategories.isNotEmpty;
    final bool hasOtherColorCategories = otherColorCategories.isNotEmpty;
    final bool hasNotes = experience.additionalNotes != null &&
        experience.additionalNotes!.isNotEmpty;
    final bool shouldShowSubRow = hasOtherCategories ||
        hasOtherColorCategories ||
        contentCount > 0 ||
        (hasNotes && !hasOtherCategories && !hasOtherColorCategories);

    final Widget leadingWidget = Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: leadingBoxColor,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.0)),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                categoryIcon,
                style: const TextStyle(fontSize: 28),
              ),
            ],
          ),
        ),
      ),
    );

    return ListTile(
      key: ValueKey(experience.id),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8.0),
      visualDensity: const VisualDensity(horizontal: -4),
      isThreeLine: true,
      titleAlignment: ListTileTitleAlignment.threeLine,
      leading: leadingWidget,
      minLeadingWidth: 56,
      title: Text(
        experience.name,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fullAddress != null && fullAddress.isNotEmpty)
            Text(
              fullAddress,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          // Row for subcategory icons and/or content count
          if (shouldShowSubRow)
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasOtherCategories || hasOtherColorCategories)
                          Wrap(
                            spacing: 6.0,
                            runSpacing: 2.0,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ...experience.otherCategories.map((categoryId) {
                                final otherCategory =
                                    _publicCategories.firstWhereOrNull(
                                  (cat) => cat.id == categoryId,
                                );
                                if (otherCategory != null) {
                                  return Text(
                                    otherCategory.icon,
                                    style: const TextStyle(fontSize: 14),
                                  );
                                }
                                return const SizedBox.shrink();
                              }),
                              ...otherColorCategories.map((colorCategory) {
                                final Color chipColor = colorCategory.color;
                                return Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: chipColor,
                                    shape: BoxShape.circle,
                                  ),
                                );
                              }),
                            ],
                          ),
                        if (experience.additionalNotes != null &&
                            experience.additionalNotes!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(Icons.notes,
                                    size: 14, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    experience.additionalNotes!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(fontStyle: FontStyle.italic),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (contentCount > 0) ...[
                    const SizedBox(width: 12),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () async {
                        // Prefetch media if not cached, then show preview
                        if (!_experienceMediaCache.containsKey(experience.id)) {
                          await _prefetchExperienceMedia(experience);
                        }
                        await _showMediaPreview(experience, displayCategory);
                      },
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: playButtonDiameter,
                            height: playButtonDiameter,
                            decoration: BoxDecoration(
                              color: Theme.of(context).primaryColor,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              size: playIconSize,
                            ),
                          ),
                          Positioned(
                            bottom: badgeOffset,
                            right: badgeOffset,
                            child: Container(
                              width: badgeDiameter,
                              height: badgeDiameter,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Theme.of(context).primaryColor,
                                  width: badgeBorderWidth,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  contentCount.toString(),
                                  style: TextStyle(
                                    color: Theme.of(context).primaryColor,
                                    fontSize: badgeFontSize,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
      onTap: () async {
        // Prefetch media in background for faster loading
        if (contentCount > 0 &&
            !_experienceMediaCache.containsKey(experience.id)) {
          unawaited(_prefetchExperienceMedia(experience));
        }
        await _navigateToExperience(experience, displayCategory);
      },
    );
  }

  Widget _buildPublicColorCategoriesList() {
    if (_isLoadingCollections) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_publicColorCategories.isEmpty) {
      return const Center(
          child: Text('No public color categories to share yet.'));
    }

    final bool isDesktopWeb = MediaQuery.of(context).size.width > 600;
    final bool showCountHeader = _publicExperienceCount > 0;

    if (isDesktopWeb) {
      // Desktop: Grid view with scrolling header
      final screenWidth = MediaQuery.of(context).size.width;
      const double contentMaxWidth = 1200.0;
      const double defaultPadding = 12.0;

      double horizontalPadding;
      if (screenWidth > contentMaxWidth) {
        horizontalPadding = (screenWidth - contentMaxWidth) / 2;
      } else {
        horizontalPadding = defaultPadding;
      }

      return CustomScrollView(
        slivers: [
          if (showCountHeader)
            SliverToBoxAdapter(
                child: _buildExperienceCountHeader(_publicExperienceCount)),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horizontalPadding, defaultPadding,
                horizontalPadding, defaultPadding),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 10.0,
                crossAxisSpacing: 10.0,
                childAspectRatio: 3 / 3.5,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final colorCategory = _publicColorCategories[index];
                  final experiences =
                      _categoryExperiences[colorCategory.id] ?? [];
                  final bool isSelected =
                      _selectedColorCategory?.id == colorCategory.id;

                  return Card(
                    key: ValueKey('color_category_grid_${colorCategory.id}'),
                    clipBehavior: Clip.antiAlias,
                    elevation: 2.0,
                    color: isSelected
                        ? Theme.of(context).primaryColor.withOpacity(0.1)
                        : null,
                    shape: isSelected
                        ? RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4.0),
                            side: BorderSide(
                              color: Theme.of(context).primaryColor,
                              width: 2,
                            ),
                          )
                        : null,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedColorCategory = null;
                          } else {
                            _selectedColorCategory = colorCategory;
                            _showingColorCategories = true;
                            _selectedCategory = null;
                          }
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: <Widget>[
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: colorCategory.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              colorCategory.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${experiences.length} ${experiences.length == 1 ? "exp" : "exps"}',
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                childCount: _publicColorCategories.length,
              ),
            ),
          ),
        ],
      );
    }

    final int headerOffset = showCountHeader ? 1 : 0;
    return ListView.separated(
      itemCount: _publicColorCategories.length + headerOffset,
      separatorBuilder: (context, index) {
        if (showCountHeader && index == 0) {
          return const SizedBox.shrink();
        }
        return const Divider(height: 1);
      },
      itemBuilder: (context, index) {
        if (showCountHeader && index == 0) {
          return _buildExperienceCountHeader(_publicExperienceCount);
        }
        final colorCategory = _publicColorCategories[index - headerOffset];
        final experiences = _categoryExperiences[colorCategory.id] ?? [];
        final bool isSelected = _selectedColorCategory?.id == colorCategory.id;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: Padding(
            padding: const EdgeInsets.only(left: 9.0),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: colorCategory.color,
                shape: BoxShape.circle,
              ),
            ),
          ),
          title: Text(colorCategory.name),
          subtitle: Text(
            '${experiences.length} ${experiences.length == 1 ? 'experience' : 'experiences'}',
          ),
          trailing: isSelected
              ? Icon(Icons.check_circle, color: Theme.of(context).primaryColor)
              : null,
          selected: isSelected,
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedColorCategory = null;
              } else {
                _selectedColorCategory = colorCategory;
                _showingColorCategories = true;
                _selectedCategory = null;
              }
            });
          },
        );
      },
    );
  }

  Widget _buildExperienceCountHeader(int count) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: const BoxDecoration(color: AppColors.backgroundColor),
      child: Text(
        '$count ${count == 1 ? 'Experience' : 'Experiences'}',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w400,
              color: Colors.grey,
            ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildSelectedCategoryExperiencesView() {
    final category = _selectedCategory!;
    final experiences = _categoryExperiences[category.id] ?? <Experience>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row with back button and category name
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to Categories',
                onPressed: () {
                  setState(() {
                    _selectedCategory = null;
                  });
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      child: Center(child: Text(category.icon)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        category.name,
                        style: Theme.of(context).textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // List of experiences for this category
        Expanded(
          child: experiences.isEmpty
              ? Center(
                  child: Text(
                    'No public experiences in "${category.name}" yet.',
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: experiences.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildExperienceCountHeader(experiences.length);
                    }
                    final experience = experiences[index - 1];
                    return _buildExperienceListItem(experience, category);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSelectedColorCategoryExperiencesView() {
    final colorCategory = _selectedColorCategory!;
    final experiences =
        _categoryExperiences[colorCategory.id] ?? <Experience>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row with back button and color category name
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to Color Categories',
                onPressed: () {
                  setState(() {
                    _selectedColorCategory = null;
                  });
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: colorCategory.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        colorCategory.name,
                        style: Theme.of(context).textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // List of experiences for this color category
        Expanded(
          child: experiences.isEmpty
              ? Center(
                  child: Text(
                    'No public experiences with "${colorCategory.name}" yet.',
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: experiences.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildExperienceCountHeader(experiences.length);
                    }
                    final experience = experiences[index - 1];
                    // Use fallback category for navigation
                    final category = _publicCategories.firstWhereOrNull(
                          (cat) => cat.id == experience.categoryId,
                        ) ??
                        UserCategory(
                          id: experience.categoryId ?? '',
                          name: 'Uncategorized',
                          icon: '?',
                          ownerUserId: widget.userId,
                        );
                    return _buildExperienceListItem(experience, category);
                  },
                ),
        ),
      ],
    );
  }
}
