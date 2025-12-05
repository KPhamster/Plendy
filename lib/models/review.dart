import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a user review for an Experience
class Review {
  final String id;
  final String experienceId;
  final String placeId; // Place ID for public experience association
  final String userId;
  final String? userName; // Display name of the reviewer
  final String? userPhotoUrl; // Profile photo URL of the reviewer
  final bool? isPositive; // true = thumbs up, false = thumbs down, null = no rating
  final String content; // Review text
  final List<String> imageUrls; // Optional photos attached to the review
  final int likeCount; // Number of likes this review has received
  final List<String> likedByUserIds; // IDs of users who liked this review
  final DateTime createdAt;
  final DateTime updatedAt;

  Review({
    required this.id,
    required this.experienceId,
    this.placeId = '',
    required this.userId,
    this.userName,
    this.userPhotoUrl,
    this.isPositive,
    required this.content,
    this.imageUrls = const [],
    this.likeCount = 0,
    this.likedByUserIds = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  // Legacy getter for backward compatibility
  double get rating => isPositive == true ? 5.0 : (isPositive == false ? 1.0 : 0.0);

  /// Create a Review from Firestore data
  factory Review.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return Review(
      id: doc.id,
      experienceId: data['experienceId'] ?? '',
      placeId: data['placeId'] ?? '',
      userId: data['userId'] ?? '',
      userName: data['userName'],
      userPhotoUrl: data['userPhotoUrl'],
      isPositive: _parseIsPositive(data['isPositive'], data['rating']),
      content: data['content'] ?? '',
      imageUrls: _parseStringList(data['imageUrls']),
      likeCount: data['likeCount'] ?? 0,
      likedByUserIds: _parseStringList(data['likedByUserIds']),
      createdAt: _parseTimestamp(data['createdAt']),
      updatedAt: _parseTimestamp(data['updatedAt']),
    );
  }

  /// Convert Review to a map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'experienceId': experienceId,
      'placeId': placeId,
      'userId': userId,
      'userName': userName,
      'userPhotoUrl': userPhotoUrl,
      'isPositive': isPositive,
      'content': content,
      'imageUrls': imageUrls,
      'likeCount': likeCount,
      'likedByUserIds': likedByUserIds,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  /// Create a copy of this Review with updated fields
  Review copyWith({
    String? experienceId,
    String? placeId,
    String? userId,
    String? userName,
    String? userPhotoUrl,
    bool? isPositive,
    bool clearIsPositive = false,
    String? content,
    List<String>? imageUrls,
    int? likeCount,
    List<String>? likedByUserIds,
    DateTime? updatedAt,
  }) {
    return Review(
      id: id,
      experienceId: experienceId ?? this.experienceId,
      placeId: placeId ?? this.placeId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userPhotoUrl: userPhotoUrl ?? this.userPhotoUrl,
      isPositive: clearIsPositive ? null : (isPositive ?? this.isPositive),
      content: content ?? this.content,
      imageUrls: imageUrls ?? this.imageUrls,
      likeCount: likeCount ?? this.likeCount,
      likedByUserIds: likedByUserIds ?? this.likedByUserIds,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Helper method to parse isPositive from Firestore
  /// Also handles legacy rating field for backward compatibility
  static bool? _parseIsPositive(dynamic isPositiveValue, dynamic ratingValue) {
    // First try the new isPositive field
    if (isPositiveValue != null) {
      if (isPositiveValue is bool) {
        return isPositiveValue;
      }
    }
    
    // Fall back to legacy rating field
    if (ratingValue != null) {
      double rating = 0.0;
      if (ratingValue is int) {
        rating = ratingValue.toDouble();
      } else if (ratingValue is double) {
        rating = ratingValue;
      } else if (ratingValue is String) {
        rating = double.tryParse(ratingValue) ?? 0.0;
    }
    
      // Convert: 4-5 = positive, 1-2 = negative, 3 = neutral (null)
      if (rating >= 4.0) return true;
      if (rating <= 2.0) return false;
    }
    
    return null;
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
