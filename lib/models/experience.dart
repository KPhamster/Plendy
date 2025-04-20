import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:equatable/equatable.dart';
import 'review.dart';
import 'comment.dart';
import 'reel.dart';

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
  final String? displayName; // Business or place display name
  final String? photoUrl; // URL to the place's photo
  final String? website; // Add website field

  Location({
    this.placeId,
    required this.latitude,
    required this.longitude,
    this.address,
    this.city,
    this.state,
    this.country,
    this.zipCode,
    this.displayName,
    this.photoUrl,
    this.website, // Add to constructor
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
        displayName,
        photoUrl,
        website
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
      displayName: map['displayName'] ?? map['name'],
      placeId: map['placeId'],
      photoUrl: map['photoUrl'],
      website: map['website'], // Add from map
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'city': city,
      'state': state,
      'country': country,
      'zipCode': zipCode,
      'displayName': displayName,
      'placeId': placeId,
      'photoUrl': photoUrl,
      'website': website, // Add to map
    };
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
    if (country != null && country!.isNotEmpty && parts.isEmpty)
      parts.add(country!);

    return parts.isNotEmpty ? parts.join(', ') : null;
  }
}

/// Main Experience class that contains all details about an experience
class Experience {
  final String id;
  final String name;
  final String description;
  final Location location;
  final String collection; // RENAMED

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
  final List<String>? sharedMediaPaths; // Added for shared content
  final String? sharedMediaType; // Added for shared content
  final String? additionalNotes; // Added for user notes

  Experience(
      {required this.id,
      required this.name,
      required this.description,
      required this.location,
      required this.collection, // RENAMED
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
      this.sharedMediaPaths, // Added
      this.sharedMediaType, // Added
      this.additionalNotes});

  /// Creates an Experience from a Firestore document
  factory Experience.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return Experience(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      location: Location.fromMap(data['location'] ?? {}),
      collection: data['collection'] ?? 'Other', // RENAMED field in Firestore
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
      sharedMediaPaths: _parseStringList(data['sharedMediaPaths']), // Added
      sharedMediaType: data['sharedMediaType'], // Added
      additionalNotes: data['additionalNotes'], // Added
    );
  }

  /// Converts Experience to a map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'location': location.toMap(),
      'collection': collection, // RENAMED field for Firestore
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
      'sharedMediaPaths': sharedMediaPaths, // Added
      'sharedMediaType': sharedMediaType, // Added
      'additionalNotes': additionalNotes, // Added
    };
  }

  /// Creates a copy of this Experience with updated fields
  Experience copyWith({
    String? name,
    String? description,
    Location? location,
    String? collection, // RENAMED
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
    List<String>? sharedMediaPaths, // Added
    String? sharedMediaType, // Added
    String? additionalNotes, // Added
  }) {
    return Experience(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      location: location ?? this.location,
      collection: collection ?? this.collection, // RENAMED
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
      sharedMediaPaths: sharedMediaPaths ?? this.sharedMediaPaths, // Added
      sharedMediaType: sharedMediaType ?? this.sharedMediaType, // Added
      additionalNotes: additionalNotes ?? this.additionalNotes, // Added
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
