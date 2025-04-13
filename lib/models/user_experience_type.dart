import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Represents a user-defined experience type with a name and icon.
class UserExperienceType extends Equatable {
  final String id; // Document ID from Firestore
  final String name;
  final String icon; // Emoji or identifier for an icon

  const UserExperienceType({
    required this.id,
    required this.name,
    required this.icon,
  });

  @override
  List<Object?> get props => [id, name, icon];

  /// Creates a UserExperienceType from a Firestore document.
  factory UserExperienceType.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserExperienceType(
      id: doc.id,
      name: data['name'] ?? 'Unknown',
      icon: data['icon'] ?? '❓', // Default icon if missing
    );
  }

  /// Converts UserExperienceType to a map for Firestore.
  /// Note: 'id' is typically not stored *in* the document itself.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'icon': icon,
      // No 'id' here, it's the document reference.
      // Add 'createdAt', 'updatedAt' timestamps if needed for management.
    };
  }

  /// Creates a copy with updated fields.
  UserExperienceType copyWith({
    String? id,
    String? name,
    String? icon,
  }) {
    return UserExperienceType(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
    );
  }

  /// Default experience types based on the original enum.
  /// The key is the type name, the value is the suggested icon.
  static const Map<String, String> defaultTypes = {
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

  /// Creates the initial list of UserExperienceType objects for a new user.
  /// Note: These objects won't have Firestore IDs until saved.
  static List<UserExperienceType> createInitialTypes() {
    return defaultTypes.entries.map((entry) {
      return UserExperienceType(
        id: '', // No ID yet
        name: entry.key,
        icon: entry.value,
      );
    }).toList();
  }
}
