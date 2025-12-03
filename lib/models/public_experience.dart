import 'package:cloud_firestore/cloud_firestore.dart';

import 'experience.dart'; // Import Location definition
import 'shared_media_item.dart';

class PublicExperience {
  final String id; // Document ID from Firestore
  final String name;
  final Location location; // Reusing the Location model from Experience
  final String placeID; // Google Place ID
  final String? yelpUrl;
  final String? website;
  final List<String> allMediaPaths; // List of media URLs/paths
  // Aggregated thumbs up/down counts from all users
  final int thumbsUpCount;
  final int thumbsDownCount;

  PublicExperience({
    required this.id,
    required this.name,
    required this.location,
    required this.placeID,
    this.yelpUrl,
    this.website,
    required this.allMediaPaths,
    this.thumbsUpCount = 0,
    this.thumbsDownCount = 0,
  });

  // CopyWith method for immutability
  PublicExperience copyWith({
    String? id,
    String? name,
    Location? location,
    String? placeID,
    String? yelpUrl,
    String? website,
    List<String>? allMediaPaths,
    int? thumbsUpCount,
    int? thumbsDownCount,
  }) {
    return PublicExperience(
      id: id ?? this.id,
      name: name ?? this.name,
      location: location ?? this.location,
      placeID: placeID ?? this.placeID,
      yelpUrl: yelpUrl ?? this.yelpUrl,
      website: website ?? this.website,
      allMediaPaths: allMediaPaths ?? this.allMediaPaths,
      thumbsUpCount: thumbsUpCount ?? this.thumbsUpCount,
      thumbsDownCount: thumbsDownCount ?? this.thumbsDownCount,
    );
  }

  // Convert PublicExperience object to a Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'location': location.toMap(), // Assuming Location has a toMap method
      'placeID': placeID,
      'yelpUrl': yelpUrl,
      'website': website,
      'allMediaPaths': allMediaPaths,
      'thumbsUpCount': thumbsUpCount,
      'thumbsDownCount': thumbsDownCount,
      // id is not stored in the document data itself
    };
  }

  // Create a PublicExperience object from a Firestore DocumentSnapshot
  factory PublicExperience.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return PublicExperience(
      id: doc.id,
      name: data['name'] ?? 'Unnamed Experience',
      location:
          Location.fromMap(data['location'] ?? {}), // Handle potential null
      placeID: data['placeID'] ?? '', // Handle potential null
      yelpUrl: data['yelpUrl'], // Can be null
      website: data['website'], // Can be null
      allMediaPaths: List<String>.from(
          data['allMediaPaths'] ?? []), // Handle potential null
      thumbsUpCount: data['thumbsUpCount'] ?? 0,
      thumbsDownCount: data['thumbsDownCount'] ?? 0,
    );
  }

  // Create a PublicExperience object from a Map (e.g., after JSON decoding)
  factory PublicExperience.fromMap(
      Map<String, dynamic> map, String documentId) {
    return PublicExperience(
      id: documentId,
      name: map['name'] ?? 'Unnamed Experience',
      location: Location.fromMap(map['location'] ?? {}),
      placeID: map['placeID'] ?? '',
      yelpUrl: map['yelpUrl'],
      website: map['website'],
      allMediaPaths: List<String>.from(map['allMediaPaths'] ?? []),
      thumbsUpCount: map['thumbsUpCount'] ?? 0,
      thumbsDownCount: map['thumbsDownCount'] ?? 0,
    );
  }

  /// Builds a lightweight [Experience] instance for read-only previews.
  Experience toExperienceDraft() {
    final now = DateTime.now();
    final List<String> mediaPaths =
        allMediaPaths.where((path) => path.isNotEmpty).toList();

    return Experience(
      id: '',
      name: name,
      description: '',
      location: location,
      categoryId: null,
      yelpUrl: yelpUrl,
      googleUrl: null,
      plendyRating: 0,
      plendyReviewCount: 0,
      imageUrls: mediaPaths,
      reelIds: const <String>[],
      followerIds: const <String>[],
      rating: 0,
      createdAt: now,
      updatedAt: now,
      website: website,
      phoneNumber: null,
      openingHours: null,
      tags: null,
      priceRange: null,
      sharedMediaItemIds: const <String>[],
      sharedMediaType: null,
      additionalNotes: null,
      editorUserIds: const <String>[],
      colorCategoryId: null,
      otherColorCategoryIds: const <String>[],
      otherCategories: const <String>[],
      categoryIconDenorm: null,
      colorHexDenorm: null,
      createdBy: null,
    );
  }

  /// Builds lightweight [SharedMediaItem]s from [allMediaPaths] for previews.
  List<SharedMediaItem> buildMediaItemsForPreview() {
    if (allMediaPaths.isEmpty) {
      return const <SharedMediaItem>[];
    }

    final String baseId =
        id.isNotEmpty ? id : (placeID.isNotEmpty ? placeID : 'public_exp');

    return allMediaPaths.asMap().entries
        // Filter any empty or whitespace-only entries
        .where((entry) => entry.value.trim().isNotEmpty)
        .map((entry) {
      final String trimmedPath = entry.value.trim();
      final int index = entry.key;
      return SharedMediaItem(
        id: 'public_${baseId}_$index',
        path: trimmedPath,
        createdAt: DateTime.fromMillisecondsSinceEpoch(index),
        ownerUserId: 'public_experience',
        experienceIds: const <String>[],
        isPrivate: false,
      );
    }).toList();
  }

  // Optional: toString for debugging
  @override
  String toString() {
    return 'PublicExperience(id: $id, name: $name, placeID: $placeID, location: ${location.address}, paths: ${allMediaPaths.length}, thumbsUp: $thumbsUpCount, thumbsDown: $thumbsDownCount)';
  }

  // Optional: Equality and hashCode
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PublicExperience &&
        other.id == id &&
        other.name == name &&
        other.location == location &&
        other.placeID == placeID &&
        other.yelpUrl == yelpUrl &&
        other.website == website &&
        // Compare lists for equality (order matters)
        ListEquality().equals(other.allMediaPaths, allMediaPaths) &&
        other.thumbsUpCount == thumbsUpCount &&
        other.thumbsDownCount == thumbsDownCount;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        name.hashCode ^
        location.hashCode ^
        placeID.hashCode ^
        yelpUrl.hashCode ^
        website.hashCode ^
        // Generate hash code for list
        ListEquality().hash(allMediaPaths) ^
        thumbsUpCount.hashCode ^
        thumbsDownCount.hashCode;
  }
}

// Helper class for comparing lists, needs 'collection' package
// import 'package:collection/collection.dart';
class ListEquality {
  bool equals(List? list1, List? list2) {
    if (identical(list1, list2)) return true;
    if (list1 == null || list2 == null) return false;
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) return false;
    }
    return true;
  }

  int hash(List? list) {
    if (list == null) return 0;
    int result = 17;
    for (var element in list) {
      result = 31 * result + element.hashCode;
    }
    return result;
  }
}
