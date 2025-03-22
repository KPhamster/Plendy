import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'review.dart';
import 'comment.dart';
import 'reel.dart';

/// Represents different types of experiences available in the app
enum ExperienceType {
  restaurant,
  cafe,
  bar,
  museum,
  theater,
  park,
  event,
  attraction,
  dateSpot,
  other,
}

/// Extension to provide string values for ExperienceType enum
extension ExperienceTypeExtension on ExperienceType {
  String get displayName {
    switch (this) {
      case ExperienceType.restaurant:
        return 'Restaurant';
      case ExperienceType.cafe:
        return 'Cafe';
      case ExperienceType.bar:
        return 'Bar';
      case ExperienceType.museum:
        return 'Museum';
      case ExperienceType.theater:
        return 'Theater';
      case ExperienceType.park:
        return 'Park';
      case ExperienceType.event:
        return 'Event';
      case ExperienceType.attraction:
        return 'Attraction';
      case ExperienceType.dateSpot:
        return 'Date Spot';
      case ExperienceType.other:
        return 'Other';
    }
  }

  static ExperienceType fromString(String value) {
    return ExperienceType.values.firstWhere(
      (type) => type.displayName.toLowerCase() == value.toLowerCase(),
      orElse: () => ExperienceType.other,
    );
  }
}

/// Represents a geographic location with latitude and longitude
class Location {
  final double latitude;
  final double longitude;
  final String? address;
  final String? city;
  final String? state;
  final String? country;
  final String? zipCode;
  final String? displayName; // Business or place display name

  Location({
    required this.latitude,
    required this.longitude,
    this.address,
    this.city,
    this.state,
    this.country,
    this.zipCode,
    this.displayName,
  });

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
    if (country != null && country!.isNotEmpty && parts.isEmpty) parts.add(country!);
    
    return parts.isNotEmpty ? parts.join(', ') : null;
  }
}

/// Main Experience class that contains all details about an experience
class Experience {
  final String id;
  final String name;
  final String description;
  final Location location;
  final ExperienceType type;
  
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
  final List<String> reelIds;  // IDs of Reel objects
  final List<String> followerIds;  // IDs of users following this experience
  
  // Timestamps
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // Additional fields
  final String? website;
  final String? phoneNumber;
  final Map<String, dynamic>? openingHours; // Format depends on implementation
  final List<String>? tags;
  final String? priceRange; // e.g. "$", "$$", "$$$", "$$$$"
  
  Experience({
    required this.id,
    required this.name,
    required this.description,
    required this.location,
    required this.type,
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
    required this.createdAt,
    required this.updatedAt,
    this.website,
    this.phoneNumber,
    this.openingHours,
    this.tags,
    this.priceRange,
  });

  /// Creates an Experience from a Firestore document
  factory Experience.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return Experience(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      location: Location.fromMap(data['location'] ?? {}),
      type: _parseExperienceType(data['type']),
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
      createdAt: _parseTimestamp(data['createdAt']),
      updatedAt: _parseTimestamp(data['updatedAt']),
      website: data['website'],
      phoneNumber: data['phoneNumber'],
      openingHours: data['openingHours'],
      tags: _parseStringList(data['tags']),
      priceRange: data['priceRange'],
    );
  }

  /// Converts Experience to a map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'location': location.toMap(),
      'type': type.displayName,
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
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'website': website,
      'phoneNumber': phoneNumber,
      'openingHours': openingHours,
      'tags': tags,
      'priceRange': priceRange,
    };
  }

  /// Creates a copy of this Experience with updated fields
  Experience copyWith({
    String? name,
    String? description,
    Location? location,
    ExperienceType? type,
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
    DateTime? updatedAt,
    String? website,
    String? phoneNumber,
    Map<String, dynamic>? openingHours,
    List<String>? tags,
    String? priceRange,
  }) {
    return Experience(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      location: location ?? this.location,
      type: type ?? this.type,
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
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      website: website ?? this.website,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      openingHours: openingHours ?? this.openingHours,
      tags: tags ?? this.tags,
      priceRange: priceRange ?? this.priceRange,
    );
  }
  
  /// Helper method to parse experience type from string
  static ExperienceType _parseExperienceType(dynamic value) {
    if (value == null) return ExperienceType.other;
    
    if (value is String) {
      return ExperienceTypeExtension.fromString(value);
    } else if (value is int && value >= 0 && value < ExperienceType.values.length) {
      return ExperienceType.values[value];
    }
    
    return ExperienceType.other;
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
