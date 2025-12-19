import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Represents a user-defined category with a name and icon.
class UserCategory extends Equatable {
  final String id; // Document ID from Firestore
  final String name;
  final String icon; // Emoji or identifier for an icon
  final String ownerUserId; // ID of the user who owns this category
  final String? sharedOwnerDisplayName; // Display name of owner when shared
  final Timestamp? lastUsedTimestamp;
  final int? orderIndex;
  final bool isPrivate;

  const UserCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.ownerUserId, // Make ownerUserId required
    this.sharedOwnerDisplayName,
    this.lastUsedTimestamp,
    this.orderIndex,
    this.isPrivate = false,
  });

  @override
  List<Object?> get props => [
        id,
        name,
        icon,
        ownerUserId,
        sharedOwnerDisplayName,
        lastUsedTimestamp,
        orderIndex,
        isPrivate,
      ]; // Add ownerUserId to props

  /// Creates a UserCategory from a Firestore document.
  factory UserCategory.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    // Attempt to read ownerUserId. It might not exist in older documents.
    // Fallback or error handling might be needed depending on application logic.
    final ownerId = data['ownerUserId'] as String?;
    if (ownerId == null) {
      // Handle cases where ownerUserId might be missing.
      // Option 1: Throw an error if it's absolutely required
      // throw Exception('Missing ownerUserId for UserCategory ${doc.id}');
      // Option 2: Log a warning and maybe use a default/placeholder if appropriate
      print(
          "Warning: Missing ownerUserId for UserCategory ${doc.id}. Firestore data: $data");
      // Depending on your app's logic, you might need a more robust fallback.
      // For now, let's throw, assuming it should always be present going forward.
      throw FormatException(
          'UserCategory document ${doc.id} is missing the required ownerUserId field.');
    }

    return UserCategory(
      id: doc.id,
      name: data['name'] ?? 'Unknown',
      icon: data['icon'] ?? '❓', // Default icon if missing
      ownerUserId: ownerId, // Use the fetched ownerId
      sharedOwnerDisplayName: null,
      lastUsedTimestamp: data['lastUsedTimestamp'] as Timestamp?,
      orderIndex: data['orderIndex'] as int?,
      isPrivate: data['isPrivate'] == true,
    );
  }

  /// Converts UserCategory to a map for Firestore.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'icon': icon,
      'ownerUserId': ownerUserId, // Add ownerUserId to map
      'lastUsedTimestamp': lastUsedTimestamp,
      'orderIndex': orderIndex,
      'isPrivate': isPrivate,
      // sharedOwnerDisplayName is derived metadata; don't persist to Firestore.
      // Consider adding 'createdAt', 'updatedAt' timestamps if needed for management.
    };
  }

  /// Creates a copy with updated fields.
  UserCategory copyWith({
    String? id,
    String? name,
    String? icon,
    String? ownerUserId, // Add ownerUserId to copyWith
    Timestamp? lastUsedTimestamp,
    String? sharedOwnerDisplayName,
    bool setLastUsedTimestampNull = false,
    int? orderIndex,
    bool setOrderIndexNull = false,
    bool? isPrivate,
  }) {
    return UserCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      ownerUserId: ownerUserId ?? this.ownerUserId, // Handle ownerUserId copy
      sharedOwnerDisplayName:
          sharedOwnerDisplayName ?? this.sharedOwnerDisplayName,
      lastUsedTimestamp: setLastUsedTimestampNull
          ? null
          : lastUsedTimestamp ?? this.lastUsedTimestamp,
      orderIndex: setOrderIndexNull ? null : orderIndex ?? this.orderIndex,
      isPrivate: isPrivate ?? this.isPrivate,
    );
  }

  /// Default Categories based on the original enum.
  /// The key is the category name, the value is the suggested icon.
  static const Map<String, String> defaultCategories = {
    'Restaurant': '🍽️',
    'Cafe': '☕',
    'Bar': '🍺',
    'Museum': '🏛️',
    'Theater': '🎭',
    'Park': '🌳',
    'Event': '🎉',
    'Attraction': '⭐',
    'Date Spot': '💖',
    'Other': '📍', // Generic location pin for 'Other'
  };

  /// Creates the initial list of UserCategory objects for a new user.
  /// Note: These objects won't have Firestore IDs or ownerUserId until saved.
  static List<UserCategory> createInitialCategories(String ownerId) {
    return defaultCategories.entries.map((entry) {
      return UserCategory(
        id: '', // No ID yet
        name: entry.key,
        icon: entry.value,
        ownerUserId: ownerId, // Assign ownerId here
        sharedOwnerDisplayName: null,
        lastUsedTimestamp: null,
        orderIndex: null,
        isPrivate: false,
      );
    }).toList();
  }

  // ADDED: Helper method to build text widget for icon
  static Widget buildIconText(String icon, {double? fontSize, Color? color}) {
    return Text(
      icon,
      style: TextStyle(
        fontSize: fontSize,
        color: color,
      ),
    );
  }
}
