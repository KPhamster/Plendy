import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Represents a geographic location with latitude and longitude
class Location extends Equatable {
  final String? placeId;
  final double latitude;
  final double longitude;
  final String? address;
  final String? city;
  final String? state;
  final String? country;
  final String? zipCode;
  // Additional admin levels for richer grouping
  final String? administrativeAreaLevel2; // e.g., county/district
  final String? administrativeAreaLevel3;
  final String? administrativeAreaLevel4;
  final String? administrativeAreaLevel5;
  final String? administrativeAreaLevel6;
  final String? administrativeAreaLevel7;
  final String? displayName; // Business or place display name
  final String? photoUrl; // URL to the place's photo
  // ADDED: Google Places photo resource name (e.g., places/PLACE_ID/photos/PHOTO_REFERENCE)
  final String? photoResourceName;
  final DateTime? photoResourceLastSyncedAt;
  final String? website; // Add website field
  final double? rating; // ADDED: Google Maps rating for the place
  final int? userRatingCount; // ADDED: Number of ratings

  const Location({
    this.placeId,
    required this.latitude,
    required this.longitude,
    this.address,
    this.city,
    this.state,
    this.country,
    this.zipCode,
    this.administrativeAreaLevel2,
    this.administrativeAreaLevel3,
    this.administrativeAreaLevel4,
    this.administrativeAreaLevel5,
    this.administrativeAreaLevel6,
    this.administrativeAreaLevel7,
    this.displayName,
    this.photoUrl,
    this.photoResourceName,
    this.photoResourceLastSyncedAt,
    this.website, // Add to constructor
    this.rating, // ADDED
    this.userRatingCount, // ADDED
  });

  @override
  List<Object?> get props => [
        placeId,
        latitude,
        longitude,
        address,
        city,
        state,
        country,
        zipCode,
        administrativeAreaLevel2,
        administrativeAreaLevel3,
        administrativeAreaLevel4,
        administrativeAreaLevel5,
        administrativeAreaLevel6,
        administrativeAreaLevel7,
        displayName,
        photoUrl,
        photoResourceName,
        photoResourceLastSyncedAt,
        website,
        rating, // ADDED
        userRatingCount, // ADDED
      ];

  factory Location.fromMap(Map<String, dynamic> map) {
    return Location(
      latitude: map['latitude'] ?? 0.0,
      longitude: map['longitude'] ?? 0.0,
      address: map['address'],
      city: map['city'],
      state: map['state'],
      country: map['country'],
      zipCode: map['zipCode'],
      administrativeAreaLevel2: map['administrativeAreaLevel2'],
      administrativeAreaLevel3: map['administrativeAreaLevel3'],
      administrativeAreaLevel4: map['administrativeAreaLevel4'],
      administrativeAreaLevel5: map['administrativeAreaLevel5'],
      administrativeAreaLevel6: map['administrativeAreaLevel6'],
      administrativeAreaLevel7: map['administrativeAreaLevel7'],
      displayName: map['displayName'] ?? map['name'],
      placeId: map['placeId'],
      photoUrl: map['photoUrl'],
      photoResourceName: map['photoResourceName'],
      photoResourceLastSyncedAt:
          _parseNullableTimestamp(map['photoResourceLastSyncedAt']),
      website: map['website'], // Add from map
      rating: (map['rating'] as num?)?.toDouble(), // ADDED
      userRatingCount: map['userRatingCount'] as int?, // ADDED
    );
  }

  Map<String, dynamic> toMap() {
    final Map<String, dynamic> map = {
      'latitude': latitude,
      'longitude': longitude,
    };

    if (address != null) map['address'] = address;
    if (city != null) map['city'] = city;
    if (state != null) map['state'] = state;
    if (country != null) map['country'] = country;
    if (zipCode != null) map['zipCode'] = zipCode;

    if (administrativeAreaLevel2 != null) {
      map['administrativeAreaLevel2'] = administrativeAreaLevel2;
    }
    if (administrativeAreaLevel3 != null) {
      map['administrativeAreaLevel3'] = administrativeAreaLevel3;
    }
    if (administrativeAreaLevel4 != null) {
      map['administrativeAreaLevel4'] = administrativeAreaLevel4;
    }
    if (administrativeAreaLevel5 != null) {
      map['administrativeAreaLevel5'] = administrativeAreaLevel5;
    }
    if (administrativeAreaLevel6 != null) {
      map['administrativeAreaLevel6'] = administrativeAreaLevel6;
    }
    if (administrativeAreaLevel7 != null) {
      map['administrativeAreaLevel7'] = administrativeAreaLevel7;
    }

    if (displayName != null) map['displayName'] = displayName;
    if (placeId != null) map['placeId'] = placeId;
    if (photoUrl != null) map['photoUrl'] = photoUrl;
    if (photoResourceName != null) map['photoResourceName'] = photoResourceName;
    if (photoResourceLastSyncedAt != null) {
      map['photoResourceLastSyncedAt'] =
          Timestamp.fromDate(photoResourceLastSyncedAt!);
    }
    if (website != null) map['website'] = website; // Add to map
    if (rating != null) map['rating'] = rating; // ADDED
    if (userRatingCount != null)
      map['userRatingCount'] = userRatingCount; // ADDED

    return map;
  }

  /// Get the human-friendly place name to display
  String getPlaceName() {
    // First try to use the display name (usually a business name like "Costco")
    if (displayName != null && displayName!.isNotEmpty) {
      return displayName!;
    }

    // If no display name, try using the first part of the address
    if (address != null && address!.isNotEmpty) {
      final parts = address!.split(',');
      return parts[0].trim();
    }

    // Fallback for locations that don't have either
    return 'Selected Location';
  }

  /// Get a formatted representation of the area (city, state, country)
  String? getFormattedArea() {
    List<String> parts = [];

    if (city != null && city!.isNotEmpty) parts.add(city!);
    if (state != null && state!.isNotEmpty) parts.add(state!);
    if (country != null && country!.isNotEmpty && parts.isEmpty) {
      parts.add(country!);
    }

    return parts.isNotEmpty ? parts.join(', ') : null;
  }

  Location copyWith({
    String? placeId,
    double? latitude,
    double? longitude,
    String? address,
    String? city,
    String? state,
    String? country,
    String? zipCode,
    String? administrativeAreaLevel2,
    String? administrativeAreaLevel3,
    String? administrativeAreaLevel4,
    String? administrativeAreaLevel5,
    String? administrativeAreaLevel6,
    String? administrativeAreaLevel7,
    String? displayName,
    String? photoUrl,
    String? photoResourceName,
    DateTime? photoResourceLastSyncedAt,
    String? website,
    double? rating,
    int? userRatingCount,
  }) {
    return Location(
      placeId: placeId ?? this.placeId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      country: country ?? this.country,
      zipCode: zipCode ?? this.zipCode,
      administrativeAreaLevel2:
          administrativeAreaLevel2 ?? this.administrativeAreaLevel2,
      administrativeAreaLevel3:
          administrativeAreaLevel3 ?? this.administrativeAreaLevel3,
      administrativeAreaLevel4:
          administrativeAreaLevel4 ?? this.administrativeAreaLevel4,
      administrativeAreaLevel5:
          administrativeAreaLevel5 ?? this.administrativeAreaLevel5,
      administrativeAreaLevel6:
          administrativeAreaLevel6 ?? this.administrativeAreaLevel6,
      administrativeAreaLevel7:
          administrativeAreaLevel7 ?? this.administrativeAreaLevel7,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      photoResourceName: photoResourceName ?? this.photoResourceName,
      photoResourceLastSyncedAt:
          photoResourceLastSyncedAt ?? this.photoResourceLastSyncedAt,
      website: website ?? this.website,
      rating: rating ?? this.rating,
      userRatingCount: userRatingCount ?? this.userRatingCount,
    );
  }

  static DateTime? _parseNullableTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }
}

/// Main Experience class that contains all details about an experience
class Experience {
  final String id;
  final String name;
  final String description;
  final Location location;
  final String? categoryId; // NEW: Stores the ID of the UserCategory
  final List<String> editorUserIds;

  // External ratings and links
  final String? yelpUrl;
  final double? yelpRating;
  final int? yelpReviewCount;

  final String? googleUrl;
  final double? googleRating;
  final int? googleReviewCount;

  // Plendy app specific data
  final double plendyRating;
  final int plendyReviewCount;
  final List<String> imageUrls;
  final List<String> reelIds; // IDs of Reel objects
  final List<String> followerIds; // IDs of users following this experience
  final double rating; // Added for compatibility with ReceiveShareScreen

  // Timestamps
  final DateTime createdAt;
  final DateTime updatedAt;

  // Additional fields
  final String? website;
  final String? phoneNumber;
  final Map<String, dynamic>? openingHours; // Format depends on implementation
  final List<String>? tags;
  final String? priceRange; // e.g. "$", "$$", "$$$", "$$$$"
  final List<String> sharedMediaItemIds;
  final String? sharedMediaType; // Added for shared content
  final String? additionalNotes; // Added for user notes
  final bool isPrivate; // Controls whether the experience is private
  final bool hasExplicitPrivacy; // Indicates whether Firestore stored the privacy flag

  // --- ADDED ---
  final String? colorCategoryId; // ID linking to the selected ColorCategory
  final List<String> otherColorCategoryIds; // ADDED: secondary color category IDs
  final List<String> otherCategories; // List of other category IDs
  // --- END ADDED ---

  // --- DENORMALIZED for fast map rendering ---
  final String?
      categoryIconDenorm; // Emoji/icon denormalized from owner category
  final String?
      colorHexDenorm; // Hex color denormalized from owner color category
  // --- END DENORMALIZED ---

  // Owner
  final String? createdBy;

  Experience({
    required this.id,
    required this.name,
    required this.description,
    required this.location,
    this.categoryId, // NEW
    this.yelpUrl,
    this.yelpRating,
    this.yelpReviewCount,
    this.googleUrl,
    this.googleRating,
    this.googleReviewCount,
    this.plendyRating = 0.0,
    this.plendyReviewCount = 0,
    this.imageUrls = const [],
    this.reelIds = const [],
    this.followerIds = const [],
    this.rating = 0.0, // Added
    required this.createdAt,
    required this.updatedAt,
    this.website,
    this.phoneNumber,
    this.openingHours,
    this.tags,
    this.priceRange,
    this.sharedMediaItemIds = const [],
    this.sharedMediaType,
    this.additionalNotes,
    required this.editorUserIds,
    this.isPrivate = false,
    this.hasExplicitPrivacy = true,
    this.colorCategoryId,
    this.otherColorCategoryIds = const [],
    this.otherCategories = const [], // Default to empty list
    this.categoryIconDenorm,
    this.colorHexDenorm,
    this.createdBy,
  });

  /// Creates an Experience from a Firestore document
  factory Experience.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final bool hasPrivacyFlag = data.containsKey('isPrivate');
    final bool isPrivateValue = data['isPrivate'] == true;

    return Experience(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      location: Location.fromMap(data['location'] ?? {}),
      categoryId: data['categoryId'] as String?, // NEW field from Firestore
      yelpUrl: data['yelpUrl'],
      yelpRating: _parseRating(data['yelpRating']),
      yelpReviewCount: data['yelpReviewCount'],
      googleUrl: data['googleUrl'],
      googleRating: _parseRating(data['googleRating']),
      googleReviewCount: data['googleReviewCount'],
      plendyRating: _parseRating(data['plendyRating']),
      plendyReviewCount: data['plendyReviewCount'] ?? 0,
      imageUrls: _parseStringList(data['imageUrls']),
      reelIds: _parseStringList(data['reelIds']),
      followerIds: _parseStringList(data['followerIds']),
      rating: _parseRating(data['rating']), // Added
      createdAt: _parseTimestamp(data['createdAt']),
      updatedAt: _parseTimestamp(data['updatedAt']),
      website: data['website'],
      phoneNumber: data['phoneNumber'],
      openingHours: data['openingHours'],
      tags: _parseStringList(data['tags']),
      priceRange: data['priceRange'],
      sharedMediaItemIds: _parseStringList(data['sharedMediaItemIds']),
      sharedMediaType: data['sharedMediaType'],
      additionalNotes: data['additionalNotes'],
      editorUserIds: _parseStringList(data['editorUserIds']),
      isPrivate: isPrivateValue,
      hasExplicitPrivacy: hasPrivacyFlag,
      colorCategoryId: data['colorCategoryId'] as String?,
      otherColorCategoryIds:
          _parseStringList(data['otherColorCategoryIds']), // ADDED
      otherCategories: _parseStringList(data['otherCategories']),
      categoryIconDenorm: data['categoryIconDenorm'] as String?,
      colorHexDenorm: data['colorHexDenorm'] as String?,
      createdBy: data['createdBy'] as String?,
    );
  }

  /// Converts Experience to a map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'location': location.toMap(),
      'categoryId': categoryId, // NEW field for Firestore
      'editorUserIds': editorUserIds,
      'yelpUrl': yelpUrl,
      'yelpRating': yelpRating,
      'yelpReviewCount': yelpReviewCount,
      'googleUrl': googleUrl,
      'googleRating': googleRating,
      'googleReviewCount': googleReviewCount,
      'plendyRating': plendyRating,
      'plendyReviewCount': plendyReviewCount,
      'imageUrls': imageUrls,
      'reelIds': reelIds,
      'followerIds': followerIds,
      'rating': rating, // Added
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'website': website,
      'phoneNumber': phoneNumber,
      'openingHours': openingHours,
      'tags': tags,
      'priceRange': priceRange,
      'sharedMediaItemIds': sharedMediaItemIds,
      'sharedMediaType': sharedMediaType,
      'additionalNotes': additionalNotes,
      'isPrivate': isPrivate,
      'colorCategoryId': colorCategoryId,
      'otherColorCategoryIds': otherColorCategoryIds,
      'otherCategories': otherCategories,
      'categoryIconDenorm': categoryIconDenorm,
      'colorHexDenorm': colorHexDenorm,
      'createdBy': createdBy,
    };
  }

  /// Creates a copy of this Experience with updated fields
  Experience copyWith({
    String? id,
    String? name,
    String? description,
    Location? location,
    String? categoryId, // NEW
    bool clearCategoryId = false, // Option to explicitly set categoryId to null
    String? yelpUrl,
    double? yelpRating,
    int? yelpReviewCount,
    String? googleUrl,
    double? googleRating,
    int? googleReviewCount,
    double? plendyRating,
    int? plendyReviewCount,
    List<String>? imageUrls,
    List<String>? reelIds,
    List<String>? followerIds,
    double? rating, // Added
    DateTime? updatedAt,
    String? website,
    String? phoneNumber,
    Map<String, dynamic>? openingHours,
    List<String>? tags,
    String? priceRange,
    List<String>? sharedMediaItemIds,
    String? sharedMediaType,
    String? additionalNotes,
    List<String>? editorUserIds,
    bool? isPrivate,
    bool? hasExplicitPrivacy,
    String? colorCategoryId,
    List<String>? otherColorCategoryIds,
    List<String>? otherCategories,
    String? categoryIconDenorm,
    String? colorHexDenorm,
    String? createdBy,
  }) {
    return Experience(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      location: location ?? this.location,
      categoryId:
          clearCategoryId ? null : (categoryId ?? this.categoryId), // NEW
      yelpUrl: yelpUrl ?? this.yelpUrl,
      yelpRating: yelpRating ?? this.yelpRating,
      yelpReviewCount: yelpReviewCount ?? this.yelpReviewCount,
      googleUrl: googleUrl ?? this.googleUrl,
      googleRating: googleRating ?? this.googleRating,
      googleReviewCount: googleReviewCount ?? this.googleReviewCount,
      plendyRating: plendyRating ?? this.plendyRating,
      plendyReviewCount: plendyReviewCount ?? this.plendyReviewCount,
      imageUrls: imageUrls ?? this.imageUrls,
      reelIds: reelIds ?? this.reelIds,
      followerIds: followerIds ?? this.followerIds,
      rating: rating ?? this.rating, // Added
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      website: website ?? this.website,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      openingHours: openingHours ?? this.openingHours,
      tags: tags ?? this.tags,
      priceRange: priceRange ?? this.priceRange,
      sharedMediaItemIds: sharedMediaItemIds ?? this.sharedMediaItemIds,
      sharedMediaType: sharedMediaType ?? this.sharedMediaType,
      additionalNotes: additionalNotes,
      editorUserIds: editorUserIds ?? this.editorUserIds,
      isPrivate: isPrivate ?? this.isPrivate,
      hasExplicitPrivacy: hasExplicitPrivacy ?? this.hasExplicitPrivacy,
      colorCategoryId: colorCategoryId ?? this.colorCategoryId,
      otherColorCategoryIds:
          otherColorCategoryIds ?? this.otherColorCategoryIds,
      otherCategories: otherCategories ?? this.otherCategories,
      categoryIconDenorm: categoryIconDenorm ?? this.categoryIconDenorm,
      colorHexDenorm: colorHexDenorm ?? this.colorHexDenorm,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  /// Helper method to parse rating values
  static double _parseRating(dynamic value) {
    if (value == null) return 0.0;

    if (value is int) {
      return value.toDouble();
    } else if (value is double) {
      return value;
    } else if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }

    return 0.0;
  }

  /// Helper method to parse string lists
  static List<String> _parseStringList(dynamic value) {
    if (value == null) return [];

    if (value is List) {
      return value.map((item) => item.toString()).toList();
    }

    return [];
  }

  /// Helper method to parse timestamps
  static DateTime _parseTimestamp(dynamic value) {
    if (value == null) return DateTime.now();

    if (value is Timestamp) {
      return value.toDate();
    } else if (value is DateTime) {
      return value;
    }

    return DateTime.now();
  }
}
