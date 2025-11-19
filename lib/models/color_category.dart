import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart'; // Import Material for Color

/// Represents a user-defined color category with a name and color.
class ColorCategory extends Equatable {
  final String id; // Document ID from Firestore
  final String name;
  final String colorHex; // Hex string for the color (e.g., "FF00FF00")
  final String ownerUserId; // ID of the user who owns this category
  final String? sharedOwnerDisplayName; // Display name when category is shared
  final Timestamp? lastUsedTimestamp;
  final int? orderIndex;
  final bool isPrivate;

  const ColorCategory({
    required this.id,
    required this.name,
    required this.colorHex,
    required this.ownerUserId,
    this.sharedOwnerDisplayName,
    this.lastUsedTimestamp,
    this.orderIndex,
    this.isPrivate = false,
  });

  @override
  List<Object?> get props => [
        id,
        name,
        colorHex,
        ownerUserId,
        sharedOwnerDisplayName,
        lastUsedTimestamp,
        orderIndex,
        isPrivate,
      ];

  /// Creates a ColorCategory from a Firestore document.
  factory ColorCategory.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final ownerId = data['ownerUserId'] as String?;
    if (ownerId == null) {
      throw FormatException(
          'ColorCategory document ${doc.id} is missing the required ownerUserId field.');
    }
    final colorHex = data['colorHex'] as String?;
    if (colorHex == null) {
      throw FormatException(
          'ColorCategory document ${doc.id} is missing the required colorHex field.');
    }

    return ColorCategory(
      id: doc.id,
      name: data['name'] ?? 'Unnamed Color',
      colorHex:
          colorHex, // Default color if missing? Or throw error? Let's throw for now.
      ownerUserId: ownerId,
      sharedOwnerDisplayName: null,
      lastUsedTimestamp: data['lastUsedTimestamp'] as Timestamp?,
      orderIndex: data['orderIndex'] as int?,
      isPrivate: data['isPrivate'] == true,
    );
  }

  /// Converts ColorCategory to a map for Firestore.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'colorHex': colorHex,
      'ownerUserId': ownerUserId,
      'lastUsedTimestamp': lastUsedTimestamp,
      'orderIndex': orderIndex,
      'isPrivate': isPrivate,
      // sharedOwnerDisplayName is derived metadata; omit from persistence.
    };
  }

  /// Creates a copy with updated fields.
  ColorCategory copyWith({
    String? id,
    String? name,
    String? colorHex,
    String? ownerUserId,
    String? sharedOwnerDisplayName,
    Timestamp? lastUsedTimestamp,
    bool setLastUsedTimestampNull = false,
    int? orderIndex,
    bool setOrderIndexNull = false,
    bool? isPrivate,
  }) {
    return ColorCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      sharedOwnerDisplayName:
          sharedOwnerDisplayName ?? this.sharedOwnerDisplayName,
      lastUsedTimestamp: setLastUsedTimestampNull
          ? null
          : lastUsedTimestamp ?? this.lastUsedTimestamp,
      orderIndex: setOrderIndexNull ? null : orderIndex ?? this.orderIndex,
      isPrivate: isPrivate ?? this.isPrivate,
    );
  }

  // Helper to get the Color object from the hex string
  Color get color {
    final buffer = StringBuffer();
    if (colorHex.length == 6 || colorHex.length == 7) {
      buffer.write('ff'); // Add alpha if missing
    }
    buffer.write(colorHex.replaceFirst('#', ''));
    try {
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (e) {
      print("Error parsing color hex '$colorHex': $e");
      return Colors.grey; // Default fallback color
    }
  }

  // --- ADDED: Default Color Categories ---
  static const Map<String, String> defaultColorCategories = {
    'Want to go': 'E52020', // Red
    'Been here already': '24C924', // Green
    'Favorite': 'F479DA', // Pink
  };
  // --- END ADDED ---

  // --- ADDED: Initializer for default Color Categories ---
  /// Creates the initial list of default ColorCategory objects for a new user.
  static List<ColorCategory> createInitialColorCategories(String ownerId) {
    int index = 0;
    return defaultColorCategories.entries.map((entry) {
      return ColorCategory(
        id: '', // No ID yet
        name: entry.key,
        colorHex: entry.value,
        ownerUserId: ownerId,
        sharedOwnerDisplayName: null,
        lastUsedTimestamp: null,
        orderIndex: index++, // Assign initial order
        isPrivate: false,
      );
    }).toList();
  }
  // --- END ADDED ---
}
