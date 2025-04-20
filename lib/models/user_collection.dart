import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Represents a user-defined collection with a name and icon.
class UserCollection extends Equatable {
  final String id; // Document ID from Firestore
  final String name;
  final String icon; // Emoji or identifier for an icon
  final Timestamp? lastUsedTimestamp;
  final int? orderIndex;

  const UserCollection({
    required this.id,
    required this.name,
    required this.icon,
    this.lastUsedTimestamp,
    this.orderIndex,
  });

  @override
  List<Object?> get props => [id, name, icon, lastUsedTimestamp, orderIndex];

  /// Creates a UserCollection from a Firestore document.
  factory UserCollection.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserCollection(
      id: doc.id,
      name: data['name'] ?? 'Unknown',
      icon: data['icon'] ?? '❓', // Default icon if missing
      lastUsedTimestamp: data['lastUsedTimestamp'] as Timestamp?,
      orderIndex: data['orderIndex'] as int?,
    );
  }

  /// Converts UserCollection to a map for Firestore.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'icon': icon,
      'lastUsedTimestamp': lastUsedTimestamp,
      'orderIndex': orderIndex,
      // Consider adding 'createdAt', 'updatedAt' timestamps if needed for management.
    };
  }

  /// Creates a copy with updated fields.
  UserCollection copyWith({
    String? id,
    String? name,
    String? icon,
    Timestamp? lastUsedTimestamp,
    bool setLastUsedTimestampNull = false,
    int? orderIndex,
    bool setOrderIndexNull = false,
  }) {
    return UserCollection(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      lastUsedTimestamp: setLastUsedTimestampNull
          ? null
          : lastUsedTimestamp ?? this.lastUsedTimestamp,
      orderIndex: setOrderIndexNull ? null : orderIndex ?? this.orderIndex,
    );
  }

  /// Default collections based on the original enum.
  /// The key is the collection name, the value is the suggested icon.
  static const Map<String, String> defaultCollections = {
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

  /// Creates the initial list of UserCollection objects for a new user.
  /// Note: These objects won't have Firestore IDs until saved.
  static List<UserCollection> createInitialCollections() {
    return defaultCollections.entries.map((entry) {
      return UserCollection(
        id: '', // No ID yet
        name: entry.key,
        icon: entry.value,
        lastUsedTimestamp: null,
        orderIndex: null,
      );
    }).toList();
  }
}
