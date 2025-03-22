import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a video reel associated with an Experience
class Reel {
  final String id;
  final String experienceId;
  final String userId;
  final String? userName; // Display name of the user who posted the reel
  final String? userPhotoUrl; // Profile photo URL of the user who posted the reel
  final String videoUrl; // URL to the video file
  final String? thumbnailUrl; // URL to the thumbnail image
  final String? caption; // Optional caption text
  final int viewCount; // Number of views this reel has received
  final int likeCount; // Number of likes this reel has received
  final List<String> likedByUserIds; // IDs of users who liked this reel
  final DateTime createdAt;
  final Duration? duration; // Duration of the video

  Reel({
    required this.id,
    required this.experienceId,
    required this.userId,
    this.userName,
    this.userPhotoUrl,
    required this.videoUrl,
    this.thumbnailUrl,
    this.caption,
    this.viewCount = 0,
    this.likeCount = 0,
    this.likedByUserIds = const [],
    required this.createdAt,
    this.duration,
  });

  /// Create a Reel from Firestore data
  factory Reel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Parse duration if available
    Duration? parsedDuration;
    if (data['durationSeconds'] != null) {
      parsedDuration = Duration(seconds: data['durationSeconds']);
    }

    return Reel(
      id: doc.id,
      experienceId: data['experienceId'] ?? '',
      userId: data['userId'] ?? '',
      userName: data['userName'],
      userPhotoUrl: data['userPhotoUrl'],
      videoUrl: data['videoUrl'] ?? '',
      thumbnailUrl: data['thumbnailUrl'],
      caption: data['caption'],
      viewCount: data['viewCount'] ?? 0,
      likeCount: data['likeCount'] ?? 0,
      likedByUserIds: _parseStringList(data['likedByUserIds']),
      createdAt: _parseTimestamp(data['createdAt']),
      duration: parsedDuration,
    );
  }

  /// Convert Reel to a map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'experienceId': experienceId,
      'userId': userId,
      'userName': userName,
      'userPhotoUrl': userPhotoUrl,
      'videoUrl': videoUrl,
      'thumbnailUrl': thumbnailUrl,
      'caption': caption,
      'viewCount': viewCount,
      'likeCount': likeCount,
      'likedByUserIds': likedByUserIds,
      'createdAt': createdAt,
      'durationSeconds': duration?.inSeconds,
    };
  }

  /// Create a copy of this Reel with updated fields
  Reel copyWith({
    String? experienceId,
    String? userId,
    String? userName,
    String? userPhotoUrl,
    String? videoUrl,
    String? thumbnailUrl,
    String? caption,
    int? viewCount,
    int? likeCount,
    List<String>? likedByUserIds,
    Duration? duration,
  }) {
    return Reel(
      id: id,
      experienceId: experienceId ?? this.experienceId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userPhotoUrl: userPhotoUrl ?? this.userPhotoUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      caption: caption ?? this.caption,
      viewCount: viewCount ?? this.viewCount,
      likeCount: likeCount ?? this.likeCount,
      likedByUserIds: likedByUserIds ?? this.likedByUserIds,
      createdAt: createdAt,
      duration: duration ?? this.duration,
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
