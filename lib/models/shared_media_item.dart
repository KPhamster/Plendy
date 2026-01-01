import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Represents a media item stored centrally, linked to one or more experiences.
class SharedMediaItem extends Equatable {
  final String id; // Document ID in the central collection
  final String path; // The actual URL or path to the media
  final DateTime createdAt; // Timestamp when this item was first added
  final String ownerUserId; // User who first added this media
  final List<String>
      experienceIds; // List of Experience IDs this media belongs to
  final bool? isTiktokPhoto; // Whether this TikTok URL is a photo carousel (null for non-TikTok items)
  final bool isPrivate;
  final String? caption; // Caption text extracted from social media posts (Instagram, TikTok, Facebook)
  
  // Ticketmaster event metadata (cached to avoid repeated API calls)
  final String? ticketmasterEventName;
  final String? ticketmasterVenueName;
  final DateTime? ticketmasterEventDate;
  final String? ticketmasterImageUrl;
  final String? ticketmasterEventId;

  const SharedMediaItem({
    required this.id,
    required this.path,
    required this.createdAt,
    required this.ownerUserId,
    required this.experienceIds,
    this.isTiktokPhoto,
    this.isPrivate = false,
    this.caption,
    this.ticketmasterEventName,
    this.ticketmasterVenueName,
    this.ticketmasterEventDate,
    this.ticketmasterImageUrl,
    this.ticketmasterEventId,
  });

  @override
  List<Object?> get props => [
        id,
        path,
        createdAt,
        ownerUserId,
        experienceIds,
        isTiktokPhoto,
        isPrivate,
        caption,
        ticketmasterEventName,
        ticketmasterVenueName,
        ticketmasterEventDate,
        ticketmasterImageUrl,
        ticketmasterEventId,
      ];

  /// Creates a SharedMediaItem from a Firestore document
  factory SharedMediaItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SharedMediaItem(
      id: doc.id,
      path: data['path'] ?? '',
      createdAt: _parseTimestamp(data['createdAt']), // Use helper
      ownerUserId: data['ownerUserId'] ?? '',
      // Ensure experienceIds is always a List<String>, even if null/empty in Firestore
      experienceIds: List<String>.from(data['experienceIds'] ?? []),
      isTiktokPhoto: data['isTiktokPhoto'] as bool?,
      isPrivate: data['isPrivate'] == true,
      caption: data['caption'] as String?,
      // Ticketmaster metadata
      ticketmasterEventName: data['ticketmasterEventName'] as String?,
      ticketmasterVenueName: data['ticketmasterVenueName'] as String?,
      ticketmasterEventDate: data['ticketmasterEventDate'] != null 
          ? _parseTimestamp(data['ticketmasterEventDate']) 
          : null,
      ticketmasterImageUrl: data['ticketmasterImageUrl'] as String?,
      ticketmasterEventId: data['ticketmasterEventId'] as String?,
    );
  }

  /// Converts SharedMediaItem to a map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'createdAt': Timestamp.fromDate(createdAt),
      'ownerUserId': ownerUserId,
      'experienceIds': experienceIds,
      if (isTiktokPhoto != null) 'isTiktokPhoto': isTiktokPhoto,
      'isPrivate': isPrivate,
      if (caption != null) 'caption': caption,
      // Ticketmaster metadata
      if (ticketmasterEventName != null) 'ticketmasterEventName': ticketmasterEventName,
      if (ticketmasterVenueName != null) 'ticketmasterVenueName': ticketmasterVenueName,
      if (ticketmasterEventDate != null) 'ticketmasterEventDate': Timestamp.fromDate(ticketmasterEventDate!),
      if (ticketmasterImageUrl != null) 'ticketmasterImageUrl': ticketmasterImageUrl,
      if (ticketmasterEventId != null) 'ticketmasterEventId': ticketmasterEventId,
      // Note: 'id' is the document ID, not stored as a field within the document
    };
  }

  // Helper method to parse timestamps
  static DateTime _parseTimestamp(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    // Handle potential String representation if needed during migration/parsing
    return DateTime.now();
  }

  /// Creates a copy of this SharedMediaItem with updated fields
  SharedMediaItem copyWith({
    String? id,
    String? path,
    DateTime? createdAt,
    String? ownerUserId,
    List<String>? experienceIds,
    bool? isTiktokPhoto,
    bool? isPrivate,
    String? caption,
    String? ticketmasterEventName,
    String? ticketmasterVenueName,
    DateTime? ticketmasterEventDate,
    String? ticketmasterImageUrl,
    String? ticketmasterEventId,
  }) {
    return SharedMediaItem(
      id: id ?? this.id,
      path: path ?? this.path,
      createdAt: createdAt ?? this.createdAt,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      experienceIds: experienceIds ?? this.experienceIds,
      isTiktokPhoto: isTiktokPhoto ?? this.isTiktokPhoto,
      isPrivate: isPrivate ?? this.isPrivate,
      caption: caption ?? this.caption,
      ticketmasterEventName: ticketmasterEventName ?? this.ticketmasterEventName,
      ticketmasterVenueName: ticketmasterVenueName ?? this.ticketmasterVenueName,
      ticketmasterEventDate: ticketmasterEventDate ?? this.ticketmasterEventDate,
      ticketmasterImageUrl: ticketmasterImageUrl ?? this.ticketmasterImageUrl,
      ticketmasterEventId: ticketmasterEventId ?? this.ticketmasterEventId,
    );
  }
}
