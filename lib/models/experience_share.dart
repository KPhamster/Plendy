import 'package:cloud_firestore/cloud_firestore.dart';

class ExperienceShare {
  final String id;
  final String experienceId;
  final String fromUserId;
  final List<String> toUserIds;
  final String visibility; // public | unlisted | direct
  final bool collaboration;
  final String? message;
  final String? token;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final int openedCount;
  final int clickCount;
  final Map<String, dynamic>? snapshot;

  ExperienceShare({
    required this.id,
    required this.experienceId,
    required this.fromUserId,
    required this.toUserIds,
    required this.visibility,
    required this.collaboration,
    this.message,
    this.token,
    this.expiresAt,
    required this.createdAt,
    this.openedCount = 0,
    this.clickCount = 0,
    this.snapshot,
  });

  factory ExperienceShare.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ExperienceShare(
      id: doc.id,
      experienceId: data['experienceId'] ?? '',
      fromUserId: data['fromUserId'] ?? '',
      toUserIds: (data['toUserIds'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      visibility: data['visibility'] ?? 'unlisted',
      collaboration: data['collaboration'] == true,
      message: data['message'],
      token: data['token'],
      expiresAt: _parseTimestamp(data['expiresAt']),
      createdAt: _parseTimestamp(data['createdAt']) ?? DateTime.now(),
      openedCount: (data['openedCount'] as num?)?.toInt() ?? 0,
      clickCount: (data['clickCount'] as num?)?.toInt() ?? 0,
      snapshot: data['snapshot'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'experienceId': experienceId,
      'fromUserId': fromUserId,
      'toUserIds': toUserIds,
      'visibility': visibility,
      'collaboration': collaboration,
      if (message != null) 'message': message,
      if (token != null) 'token': token,
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt!),
      'createdAt': Timestamp.fromDate(createdAt),
      'openedCount': openedCount,
      'clickCount': clickCount,
      if (snapshot != null) 'snapshot': snapshot,
    };
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}



