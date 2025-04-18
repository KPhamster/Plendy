import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Represents a user-defined category with a name and icon.
class UserCategory extends Equatable {
  final String id; // Document ID from Firestore
  final String name;
  final String icon; // Emoji or identifier for an icon

  const UserCategory({
    required this.id,
    required this.name,
    required this.icon,
  });

  @override
  List<Object?> get props => [id, name, icon];

  /// Creates a UserCategory from a Firestore document.
  factory UserCategory.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserCategory(
      id: doc.id,
      name: data['name'] ?? 'Unknown',
      icon: data['icon'] ?? '❓', // Default icon if missing
    );
  }

  /// Converts UserCategory to a map for Firestore.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'icon': icon,
      // Consider adding 'createdAt', 'updatedAt' timestamps if needed for management.
    };
  }

  /// Creates a copy with updated fields.
  UserCategory copyWith({
    String? id,
    String? name,
    String? icon,
  }) {
    return UserCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
    );
  }

  /// Default categories based on the original enum.
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
  /// Note: These objects won't have Firestore IDs until saved.
  static List<UserCategory> createInitialCategories() {
    return defaultCategories.entries.map((entry) {
      return UserCategory(
        id: '', // No ID yet
        name: entry.key,
        icon: entry.value,
      );
    }).toList();
  }
}
