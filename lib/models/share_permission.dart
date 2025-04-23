import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'enums/share_enums.dart'; // Import the enums

/// Represents a permission grant for sharing an Experience or UserCategory.
class SharePermission extends Equatable {
  final String id; // Document ID from Firestore
  final String itemId; // ID of the Experience or UserCategory being shared
  final ShareableItemType itemType; // Type of item (experience or category)
  final String ownerUserId; // User ID of the item's original owner
  final String
      sharedWithUserId; // User ID of the person the item is shared with
  final ShareAccessLevel accessLevel; // Access level (view or edit)
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const SharePermission({
    required this.id,
    required this.itemId,
    required this.itemType,
    required this.ownerUserId,
    required this.sharedWithUserId,
    required this.accessLevel,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [
        id,
        itemId,
        itemType,
        ownerUserId,
        sharedWithUserId,
        accessLevel,
        createdAt,
        updatedAt,
      ];

  /// Creates a SharePermission from a Firestore document.
  factory SharePermission.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Helper to safely convert String to enum, defaulting to view/experience
    ShareableItemType _parseItemType(String? typeStr) {
      if (typeStr == 'category') return ShareableItemType.category;
      // Default to experience if null, empty, or unrecognized
      if (typeStr == null || typeStr.isEmpty || typeStr != 'experience') {
        if (typeStr != 'experience') {
          print(
              "Warning: Unrecognized itemType '$typeStr' in SharePermission ${doc.id}. Defaulting to experience.");
        }
      }
      return ShareableItemType.experience;
    }

    ShareAccessLevel _parseAccessLevel(String? levelStr) {
      if (levelStr == 'edit') return ShareAccessLevel.edit;
      // Default to view if null, empty, or unrecognized
      if (levelStr == null || levelStr.isEmpty || levelStr != 'view') {
        if (levelStr != 'view') {
          print(
              "Warning: Unrecognized accessLevel '$levelStr' in SharePermission ${doc.id}. Defaulting to view.");
        }
      }
      return ShareAccessLevel.view;
    }

    return SharePermission(
      id: doc.id,
      itemId: data['itemId'] ?? '',
      // Convert string from Firestore back to enum
      itemType: _parseItemType(data['itemType'] as String?),
      ownerUserId: data['ownerUserId'] ?? '',
      sharedWithUserId: data['sharedWithUserId'] ?? '',
      // Convert string from Firestore back to enum
      accessLevel: _parseAccessLevel(data['accessLevel'] as String?),
      createdAt: data['createdAt'] ?? Timestamp.now(),
      updatedAt: data['updatedAt'] ?? Timestamp.now(),
    );
  }

  /// Converts SharePermission to a map for Firestore.
  Map<String, dynamic> toMap() {
    // Helper to convert enum to string
    String _itemTypeToString(ShareableItemType type) {
      return type == ShareableItemType.category ? 'category' : 'experience';
    }

    String _accessLevelToString(ShareAccessLevel level) {
      return level == ShareAccessLevel.edit ? 'edit' : 'view';
    }

    return {
      'itemId': itemId,
      'itemType': _itemTypeToString(itemType), // Store enum as string
      'ownerUserId': ownerUserId,
      'sharedWithUserId': sharedWithUserId,
      'accessLevel': _accessLevelToString(accessLevel), // Store enum as string
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      // Add server timestamp fields if needed for auto-update on write
      // 'serverTimestamp': FieldValue.serverTimestamp(),
    };
  }

  /// Creates a copy with updated fields.
  SharePermission copyWith({
    String? id,
    String? itemId,
    ShareableItemType? itemType,
    String? ownerUserId,
    String? sharedWithUserId,
    ShareAccessLevel? accessLevel,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return SharePermission(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      itemType: itemType ?? this.itemType,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      sharedWithUserId: sharedWithUserId ?? this.sharedWithUserId,
      accessLevel: accessLevel ?? this.accessLevel,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
