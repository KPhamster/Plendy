import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a user review for an Experience
class Review {
  final String id;
  final String experienceId;
  final String userId;
  final String? userName; // Display name of the reviewer
  final String? userPhotoUrl; // Profile photo URL of the reviewer
  final double rating; // 1-5 rating
  final String content; // Review text
  final List<String> imageUrls; // Optional photos attached to the review
  final int likeCount; // Number of likes this review has received
  final List<String> likedByUserIds; // IDs of users who liked this review
  final DateTime createdAt;
  final DateTime updatedAt;

  Review({
    required this.id,
    required this.experienceId,
    required this.userId,
    this.userName,
    this.userPhotoUrl,
    required this.rating,
    required this.content,
    this.imageUrls = const [],
    this.likeCount = 0,
    this.likedByUserIds = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create a Review from Firestore data
  factory Review.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return Review(
      id: doc.id,
      experienceId: data['experienceId'] ?? '',
      userId: data['userId'] ?? '',
      userName: data['userName'],
      userPhotoUrl: data['userPhotoUrl'],
      rating: _parseRating(data['rating']),
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
      'userId': userId,
      'userName': userName,
      'userPhotoUrl': userPhotoUrl,
      'rating': rating,
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
    String? userId,
    String? userName,
    String? userPhotoUrl,
    double? rating,
    String? content,
    List<String>? imageUrls,
    int? likeCount,
    List<String>? likedByUserIds,
    DateTime? updatedAt,
  }) {
    return Review(
      id: id,
      experienceId: experienceId ?? this.experienceId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userPhotoUrl: userPhotoUrl ?? this.userPhotoUrl,
      rating: rating ?? this.rating,
      content: content ?? this.content,
      imageUrls: imageUrls ?? this.imageUrls,
      likeCount: likeCount ?? this.likeCount,
      likedByUserIds: likedByUserIds ?? this.likedByUserIds,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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
