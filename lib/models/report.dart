import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Represents a user report for content moderation
class Report extends Equatable {
  // Core report data
  final String id;
  final String userId;
  final String screenReported;
  final String previewURL;
  final String experienceId;
  final String reportType;
  final String details;
  final DateTime createdAt;

  // Report status tracking
  final String status; // "pending", "reviewed", "resolved", "dismissed"

  // Additional context
  final String? reportedUserId; // User ID of content creator
  final String? publicExperienceId; // Original public experience ID if from discovery

  // Review information
  final String? reviewedBy; // Admin/moderator user ID
  final DateTime? reviewedAt;
  final String? reviewNotes; // Internal admin notes

  // Device/platform info
  final String? deviceInfo; // e.g., "iOS 17.0", "Android 13", "Web - Chrome"

  // Status constants
  static const String statusPending = 'pending';
  static const String statusReviewed = 'reviewed';
  static const String statusResolved = 'resolved';
  static const String statusDismissed = 'dismissed';

  const Report({
    required this.id,
    required this.userId,
    required this.screenReported,
    required this.previewURL,
    required this.experienceId,
    required this.reportType,
    required this.details,
    required this.createdAt,
    this.status = statusPending,
    this.reportedUserId,
    this.publicExperienceId,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNotes,
    this.deviceInfo,
  });

  @override
  List<Object?> get props => [
        id,
        userId,
        screenReported,
        previewURL,
        experienceId,
        reportType,
        details,
        createdAt,
        status,
        reportedUserId,
        publicExperienceId,
        reviewedBy,
        reviewedAt,
        reviewNotes,
        deviceInfo,
      ];

  factory Report.fromMap(Map<String, dynamic> map, {String? id}) {
    return Report(
      id: id ?? map['id'] ?? '',
      userId: map['userId'] ?? '',
      screenReported: map['screenReported'] ?? '',
      previewURL: map['previewURL'] ?? '',
      experienceId: map['experienceId'] ?? '',
      reportType: map['reportType'] ?? '',
      details: map['details'] ?? '',
      createdAt: _parseTimestamp(map['createdAt']),
      status: map['status'] ?? statusPending,
      reportedUserId: map['reportedUserId'],
      publicExperienceId: map['publicExperienceId'],
      reviewedBy: map['reviewedBy'],
      reviewedAt: _parseNullableTimestamp(map['reviewedAt']),
      reviewNotes: map['reviewNotes'],
      deviceInfo: map['deviceInfo'],
    );
  }

  factory Report.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw Exception('Document data is null for report ${doc.id}');
    }
    return Report.fromMap(data, id: doc.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'screenReported': screenReported,
      'previewURL': previewURL,
      'experienceId': experienceId,
      'reportType': reportType,
      'details': details,
      'createdAt': Timestamp.fromDate(createdAt),
      'status': status,
      if (reportedUserId != null) 'reportedUserId': reportedUserId,
      if (publicExperienceId != null) 'publicExperienceId': publicExperienceId,
      if (reviewedBy != null) 'reviewedBy': reviewedBy,
      if (reviewedAt != null) 'reviewedAt': Timestamp.fromDate(reviewedAt!),
      if (reviewNotes != null) 'reviewNotes': reviewNotes,
      if (deviceInfo != null) 'deviceInfo': deviceInfo,
    };
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value == null) {
      return DateTime.now();
    }
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  static DateTime? _parseNullableTimestamp(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  Report copyWith({
    String? id,
    String? userId,
    String? screenReported,
    String? previewURL,
    String? experienceId,
    String? reportType,
    String? details,
    DateTime? createdAt,
    String? status,
    String? reportedUserId,
    String? publicExperienceId,
    String? reviewedBy,
    DateTime? reviewedAt,
    String? reviewNotes,
    String? deviceInfo,
  }) {
    return Report(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      screenReported: screenReported ?? this.screenReported,
      previewURL: previewURL ?? this.previewURL,
      experienceId: experienceId ?? this.experienceId,
      reportType: reportType ?? this.reportType,
      details: details ?? this.details,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      reportedUserId: reportedUserId ?? this.reportedUserId,
      publicExperienceId: publicExperienceId ?? this.publicExperienceId,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewNotes: reviewNotes ?? this.reviewNotes,
      deviceInfo: deviceInfo ?? this.deviceInfo,
    );
  }
}

