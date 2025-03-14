import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a user comment on an Experience
class Comment {
  final String id;
  final String experienceId;
  final String userId;
  final String? userName; // Display name of the commenter
  final String? userPhotoUrl; // Profile photo URL of the commenter
  final String content; // Comment text
  final String? parentCommentId; // For replies to other comments
  final int likeCount; // Number of likes this comment has received
  final List<String> likedByUserIds; // IDs of users who liked this comment
  final DateTime createdAt;
  final DateTime updatedAt;

  Comment({
    required this.id,
    required this.experienceId,
    required this.userId,
    this.userName,
    this.userPhotoUrl,
    required this.content,
    this.parentCommentId,
    this.likeCount = 0,
    this.likedByUserIds = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create a Comment from Firestore data
  factory Comment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return Comment(
      id: doc.id,
      experienceId: data['experienceId'] ?? '',
      userId: data['userId'] ?? '',
      userName: data['userName'],
      userPhotoUrl: data['userPhotoUrl'],
      content: data['content'] ?? '',
      parentCommentId: data['parentCommentId'],
      likeCount: data['likeCount'] ?? 0,
      likedByUserIds: _parseStringList(data['likedByUserIds']),
      createdAt: _parseTimestamp(data['createdAt']),
      updatedAt: _parseTimestamp(data['updatedAt']),
    );
  }

  /// Convert Comment to a map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'experienceId': experienceId,
      'userId': userId,
      'userName': userName,
      'userPhotoUrl': userPhotoUrl,
      'content': content,
      'parentCommentId': parentCommentId,
      'likeCount': likeCount,
      'likedByUserIds': likedByUserIds,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  /// Create a copy of this Comment with updated fields
  Comment copyWith({
    String? experienceId,
    String? userId,
    String? userName,
    String? userPhotoUrl,
    String? content,
    String? parentCommentId,
    int? likeCount,
    List<String>? likedByUserIds,
    DateTime? updatedAt,
  }) {
    return Comment(
      id: this.id,
      experienceId: experienceId ?? this.experienceId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userPhotoUrl: userPhotoUrl ?? this.userPhotoUrl,
      content: content ?? this.content,
      parentCommentId: parentCommentId ?? this.parentCommentId,
      likeCount: likeCount ?? this.likeCount,
      likedByUserIds: likedByUserIds ?? this.likedByUserIds,
      createdAt: this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
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
