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
  // Add other potential metadata if needed (e.g., mediaType, thumbnail?)

  const SharedMediaItem({
    required this.id,
    required this.path,
    required this.createdAt,
    required this.ownerUserId,
    required this.experienceIds,
  });

  @override
  List<Object?> get props => [id, path, createdAt, ownerUserId, experienceIds];

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
    );
  }

  /// Converts SharedMediaItem to a map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'createdAt': Timestamp.fromDate(createdAt),
      'ownerUserId': ownerUserId,
      'experienceIds': experienceIds,
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
  }) {
    return SharedMediaItem(
      id: id ?? this.id,
      path: path ?? this.path,
      createdAt: createdAt ?? this.createdAt,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      experienceIds: experienceIds ?? this.experienceIds,
    );
  }
}
