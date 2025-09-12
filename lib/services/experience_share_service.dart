import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/experience.dart';
import '../models/shared_media_item.dart';
import 'experience_service.dart';

class ExperienceShareService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference get _shares => _firestore.collection('experience_shares');

  String? get _currentUserId => _auth.currentUser?.uid;

  // Generate a short unguessable token if needed for link shares
  String _generateToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random.secure();
    return List.generate(12, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<String> createDirectShare({
    required Experience experience,
    required List<String> toUserIds,
    String? message,
    bool collaboration = false,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');
    if (toUserIds.isEmpty) throw Exception('No recipients provided');

    final snapshot = await _buildSnapshotFromExperienceAsync(experience);

    final data = {
      'experienceId': experience.id,
      'fromUserId': userId,
      'toUserIds': toUserIds,
      'visibility': 'direct',
      'collaboration': collaboration,
      if (message != null && message.isNotEmpty) 'message': message,
      'createdAt': FieldValue.serverTimestamp(),
      'snapshot': snapshot,
    };

    final docRef = await _shares.add(data);
    return docRef.id;
  }

  Future<String> createLinkShare({
    required Experience experience,
    String? message,
    bool public = false,
    DateTime? expiresAt,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final token = _generateToken();
    final snapshot = await _buildSnapshotFromExperienceAsync(experience);

    final data = {
      'experienceId': experience.id,
      'fromUserId': userId,
      'toUserIds': [],
      'visibility': public ? 'public' : 'unlisted',
      'collaboration': false,
      if (message != null && message.isNotEmpty) 'message': message,
      'token': token,
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
      'createdAt': FieldValue.serverTimestamp(),
      'snapshot': snapshot,
    };

    await _shares.add(data);

    // Build a public URL on plendy.app using the token
    final String shareUrl = 'https://plendy.app/shared/' + token;
    return shareUrl;
  }

  Future<Map<String, dynamic>> _buildSnapshotFromExperienceAsync(Experience exp) async {
    // Optionally expand media into share snapshot for web preview without extra reads
    final List<String> mediaUrls = <String>[];
    if (exp.sharedMediaItemIds.isNotEmpty) {
      try {
        final items = await ExperienceService().getSharedMediaItems(exp.sharedMediaItemIds);
        mediaUrls.addAll(items.map((SharedMediaItem i) => i.path));
      } catch (_) {
        // Ignore media expansion errors; preview will fall back to imageUrls
      }
    }

    return {
      'name': exp.name,
      'description': exp.description,
      'image': (exp.imageUrls.isNotEmpty ? exp.imageUrls.first : null),
      'imageUrls': exp.imageUrls, // include gallery images
      'mediaUrls': mediaUrls, // expanded content preview
      'plendyRating': exp.plendyRating,
      'googleRating': exp.googleRating,
      'googleReviewCount': exp.googleReviewCount,
      'priceRange': exp.priceRange,
      'website': exp.website,
      'location': {
        'displayName': exp.location.displayName,
        'address': exp.location.address,
        'city': exp.location.city,
        'state': exp.location.state,
        'country': exp.location.country,
        'placeId': exp.location.placeId,
        'latitude': exp.location.latitude,
        'longitude': exp.location.longitude,
        'website': exp.location.website,
      },
    };
  }
}


