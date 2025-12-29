import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'experience.dart'; // Import Location definition
import 'shared_media_item.dart';

class PublicExperience {
  final String id; // Document ID from Firestore
  final String name;
  final Location location; // Reusing the Location model from Experience
  final String placeID; // Google Place ID
  final String? yelpUrl;
  final String? website;
  final List<String> allMediaPaths; // List of media URLs/paths
  // Aggregated thumbs up/down counts from all users
  final int thumbsUpCount;
  final int thumbsDownCount;
  // Track which users have voted (for preventing duplicates and restoring state)
  final List<String> thumbsUpUserIds;
  final List<String> thumbsDownUserIds;
  // Category icon (emoji) derived from experiences with the same placeID
  final String? icon;
  // Google Places API types for auto-categorization
  final List<String>? placeTypes;
  // Editorial/review/generative summary from Google Places API (cached)
  final String? description;

  PublicExperience({
    required this.id,
    required this.name,
    required this.location,
    required this.placeID,
    this.yelpUrl,
    this.website,
    required this.allMediaPaths,
    this.thumbsUpCount = 0,
    this.thumbsDownCount = 0,
    this.thumbsUpUserIds = const [],
    this.thumbsDownUserIds = const [],
    this.icon,
    this.placeTypes,
    this.description,
  });

  // CopyWith method for immutability
  PublicExperience copyWith({
    String? id,
    String? name,
    Location? location,
    String? placeID,
    String? yelpUrl,
    String? website,
    List<String>? allMediaPaths,
    int? thumbsUpCount,
    int? thumbsDownCount,
    List<String>? thumbsUpUserIds,
    List<String>? thumbsDownUserIds,
    String? icon,
    List<String>? placeTypes,
    String? description,
  }) {
    return PublicExperience(
      id: id ?? this.id,
      name: name ?? this.name,
      location: location ?? this.location,
      placeID: placeID ?? this.placeID,
      yelpUrl: yelpUrl ?? this.yelpUrl,
      website: website ?? this.website,
      allMediaPaths: allMediaPaths ?? this.allMediaPaths,
      thumbsUpCount: thumbsUpCount ?? this.thumbsUpCount,
      thumbsDownCount: thumbsDownCount ?? this.thumbsDownCount,
      thumbsUpUserIds: thumbsUpUserIds ?? this.thumbsUpUserIds,
      thumbsDownUserIds: thumbsDownUserIds ?? this.thumbsDownUserIds,
      icon: icon ?? this.icon,
      placeTypes: placeTypes ?? this.placeTypes,
      description: description ?? this.description,
    );
  }

  // Convert PublicExperience object to a Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'location': location.toMap(), // Assuming Location has a toMap method
      'placeID': placeID,
      'yelpUrl': yelpUrl,
      'website': website,
      'allMediaPaths': allMediaPaths,
      'thumbsUpCount': thumbsUpCount,
      'thumbsDownCount': thumbsDownCount,
      'thumbsUpUserIds': thumbsUpUserIds,
      'thumbsDownUserIds': thumbsDownUserIds,
      'icon': icon,
      'placeTypes': placeTypes,
      'description': description,
      // id is not stored in the document data itself
    };
  }

  // Create a PublicExperience object from a Firestore DocumentSnapshot
  factory PublicExperience.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return PublicExperience(
      id: doc.id,
      name: data['name'] ?? 'Unnamed Experience',
      location:
          Location.fromMap(data['location'] ?? {}), // Handle potential null
      placeID: data['placeID'] ?? '', // Handle potential null
      yelpUrl: data['yelpUrl'], // Can be null
      website: data['website'], // Can be null
      allMediaPaths: List<String>.from(
          data['allMediaPaths'] ?? []), // Handle potential null
      thumbsUpCount: data['thumbsUpCount'] ?? 0,
      thumbsDownCount: data['thumbsDownCount'] ?? 0,
      thumbsUpUserIds: List<String>.from(data['thumbsUpUserIds'] ?? []),
      thumbsDownUserIds: List<String>.from(data['thumbsDownUserIds'] ?? []),
      icon: data['icon'] as String?,
      placeTypes: (data['placeTypes'] as List<dynamic>?)?.cast<String>(),
      description: data['description'] as String?,
    );
  }

  // Create a PublicExperience object from a Map (e.g., after JSON decoding)
  factory PublicExperience.fromMap(
      Map<String, dynamic> map, String documentId) {
    return PublicExperience(
      id: documentId,
      name: map['name'] ?? 'Unnamed Experience',
      location: Location.fromMap(map['location'] ?? {}),
      placeID: map['placeID'] ?? '',
      yelpUrl: map['yelpUrl'],
      website: map['website'],
      allMediaPaths: List<String>.from(map['allMediaPaths'] ?? []),
      thumbsUpCount: map['thumbsUpCount'] ?? 0,
      thumbsDownCount: map['thumbsDownCount'] ?? 0,
      thumbsUpUserIds: List<String>.from(map['thumbsUpUserIds'] ?? []),
      thumbsDownUserIds: List<String>.from(map['thumbsDownUserIds'] ?? []),
      icon: map['icon'] as String?,
      placeTypes: (map['placeTypes'] as List<dynamic>?)?.cast<String>(),
      description: map['description'] as String?,
    );
  }
  
  /// Gets the user's current rating from the public experience
  /// Returns true for thumbs up, false for thumbs down, null if no rating
  bool? getUserRating(String userId) {
    if (thumbsUpUserIds.contains(userId)) {
      return true;
    } else if (thumbsDownUserIds.contains(userId)) {
      return false;
    }
    return null;
  }

  /// Builds a lightweight [Experience] instance for read-only previews.
  Experience toExperienceDraft() {
    final now = DateTime.now();
    final List<String> mediaPaths =
        allMediaPaths.where((path) => path.isNotEmpty).toList();

    // Include placeTypes in the location for auto-categorization
    final locationWithPlaceTypes = placeTypes != null && placeTypes!.isNotEmpty
        ? location.copyWith(placeTypes: placeTypes)
        : location;

    return Experience(
      id: '',
      name: name,
      description: description ?? '',
      location: locationWithPlaceTypes,
      categoryId: null,
      yelpUrl: yelpUrl,
      googleUrl: null,
      plendyRating: 0,
      plendyReviewCount: 0,
      imageUrls: mediaPaths,
      reelIds: const <String>[],
      followerIds: const <String>[],
      rating: 0,
      createdAt: now,
      updatedAt: now,
      website: website,
      phoneNumber: null,
      openingHours: null,
      tags: null,
      priceRange: null,
      sharedMediaItemIds: const <String>[],
      sharedMediaType: null,
      additionalNotes: null,
      editorUserIds: const <String>[],
      colorCategoryId: null,
      otherColorCategoryIds: const <String>[],
      otherCategories: const <String>[],
      categoryIconDenorm: null,
      colorHexDenorm: null,
      createdBy: null,
    );
  }

  /// Builds lightweight [SharedMediaItem]s from [allMediaPaths] for previews.
  List<SharedMediaItem> buildMediaItemsForPreview() {
    if (allMediaPaths.isEmpty) {
      return const <SharedMediaItem>[];
    }

    final String baseId =
        id.isNotEmpty ? id : (placeID.isNotEmpty ? placeID : 'public_exp');

    final LinkedHashMap<String, String> uniquePaths =
        LinkedHashMap<String, String>();
    for (final path in allMediaPaths) {
      final String trimmedPath = path.trim();
      if (trimmedPath.isEmpty) continue;
      final String normalizedKey = _normalizeMediaPathForComparison(trimmedPath);
      if (normalizedKey.isEmpty) continue;
      uniquePaths.putIfAbsent(normalizedKey, () => trimmedPath);
    }

    return uniquePaths.values.toList().asMap().entries.map((entry) {
      final String trimmedPath = entry.value;
      final int index = entry.key;
      return SharedMediaItem(
        id: 'public_${baseId}_$index',
        path: trimmedPath,
        createdAt: DateTime.fromMillisecondsSinceEpoch(index),
        ownerUserId: 'public_experience',
        experienceIds: const <String>[],
        isPrivate: false,
      );
    }).toList();
  }

  static String _normalizeMediaPathForComparison(String path) {
    final String trimmed = path.trim();
    if (trimmed.isEmpty) return '';

    final Uri? uri = _tryParseUri(trimmed);
    if (uri == null || uri.host.isEmpty) {
      return _stripTrailingSlash(trimmed);
    }

    final String host = _normalizeHost(uri.host);
    final String scheme = uri.scheme.isNotEmpty ? uri.scheme.toLowerCase() : 'https';
    final String rawPath = uri.path.isEmpty ? '/' : uri.path;

    if (_isInstagramHost(host)) {
      final String normalizedHost = _normalizeSocialHost(host);
      final String normalizedPath = _normalizeInstagramPath(rawPath);
      return '$scheme://$normalizedHost$normalizedPath';
    }

    if (_isTikTokHost(host) || _isFacebookHost(host)) {
      final String normalizedHost = _normalizeSocialHost(host);
      final String normalizedPath = _stripTrailingSlash(rawPath);
      return '$scheme://$normalizedHost$normalizedPath';
    }

    final String? youtubeKey = _extractYouTubeKey(uri, host);
    if (youtubeKey != null) {
      return youtubeKey;
    }

    return _stripTrailingSlash(trimmed);
  }

  static Uri? _tryParseUri(String value) {
    final Uri? direct = Uri.tryParse(value);
    if (direct != null && direct.host.isNotEmpty) {
      return direct;
    }
    final Uri? withScheme = Uri.tryParse('https://$value');
    if (withScheme != null && withScheme.host.isNotEmpty) {
      return withScheme;
    }
    return direct;
  }

  static String _normalizeHost(String host) {
    String normalized = host.toLowerCase();
    if (normalized.startsWith('www.')) {
      normalized = normalized.substring(4);
    }
    return normalized;
  }

  static String _normalizeSocialHost(String host) {
    String normalized = _normalizeHost(host);
    if (normalized.startsWith('m.')) {
      normalized = normalized.substring(2);
    }
    return normalized;
  }

  static bool _isInstagramHost(String host) {
    return host.contains('instagram.com');
  }

  static bool _isTikTokHost(String host) {
    return host.contains('tiktok.com');
  }

  static bool _isFacebookHost(String host) {
    return host.contains('facebook.com') ||
        host == 'fb.com' ||
        host == 'fb.watch';
  }

  static String? _extractYouTubeKey(Uri uri, String host) {
    if (!host.contains('youtube.com') && !host.contains('youtu.be')) {
      return null;
    }

    final List<String> segments =
        uri.pathSegments.where((segment) => segment.isNotEmpty).toList();

    if (host.contains('youtu.be') && segments.isNotEmpty) {
      return 'youtube:${segments.first}';
    }

    if (segments.isEmpty) return null;

    if (segments.first == 'watch') {
      final String? videoId = uri.queryParameters['v'];
      if (videoId != null && videoId.isNotEmpty) {
        return 'youtube:$videoId';
      }
    }

    if (segments.first == 'shorts' && segments.length > 1) {
      return 'youtube:${segments[1]}';
    }

    if (segments.first == 'embed' && segments.length > 1) {
      return 'youtube:${segments[1]}';
    }

    return null;
  }

  static String _normalizeInstagramPath(String path) {
    String normalized = _stripTrailingSlash(path);
    if (normalized.contains('/reel/')) {
      normalized = normalized.replaceFirst('/reel/', '/p/');
    }
    if (normalized.contains('/tv/')) {
      normalized = normalized.replaceFirst('/tv/', '/p/');
    }
    return _stripTrailingSlash(normalized);
  }

  static String _stripTrailingSlash(String value) {
    if (value.length > 1 && value.endsWith('/')) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }

  // Optional: toString for debugging
  @override
  String toString() {
    return 'PublicExperience(id: $id, name: $name, placeID: $placeID, location: ${location.address}, paths: ${allMediaPaths.length}, thumbsUp: $thumbsUpCount, thumbsDown: $thumbsDownCount, description: ${description?.substring(0, description!.length > 30 ? 30 : description!.length) ?? 'null'})';
  }

  // Optional: Equality and hashCode
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PublicExperience &&
        other.id == id &&
        other.name == name &&
        other.location == location &&
        other.placeID == placeID &&
        other.yelpUrl == yelpUrl &&
        other.website == website &&
        // Compare lists for equality (order matters)
        ListEquality().equals(other.allMediaPaths, allMediaPaths) &&
        other.thumbsUpCount == thumbsUpCount &&
        other.thumbsDownCount == thumbsDownCount &&
        ListEquality().equals(other.thumbsUpUserIds, thumbsUpUserIds) &&
        ListEquality().equals(other.thumbsDownUserIds, thumbsDownUserIds) &&
        other.icon == icon &&
        ListEquality().equals(other.placeTypes, placeTypes) &&
        other.description == description;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        name.hashCode ^
        location.hashCode ^
        placeID.hashCode ^
        yelpUrl.hashCode ^
        website.hashCode ^
        // Generate hash code for list
        ListEquality().hash(allMediaPaths) ^
        thumbsUpCount.hashCode ^
        thumbsDownCount.hashCode ^
        ListEquality().hash(thumbsUpUserIds) ^
        ListEquality().hash(thumbsDownUserIds) ^
        icon.hashCode ^
        ListEquality().hash(placeTypes) ^
        description.hashCode;
  }
}

// Helper class for comparing lists, needs 'collection' package
// import 'package:collection/collection.dart';
class ListEquality {
  bool equals(List? list1, List? list2) {
    if (identical(list1, list2)) return true;
    if (list1 == null || list2 == null) return false;
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) return false;
    }
    return true;
  }

  int hash(List? list) {
    if (list == null) return 0;
    int result = 17;
    for (var element in list) {
      result = 31 * result + element.hashCode;
    }
    return result;
  }
}
