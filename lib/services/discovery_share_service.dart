import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/public_experience.dart';

class DiscoverySharePayload {
  DiscoverySharePayload({
    required this.token,
    required this.experience,
    required this.mediaUrl,
  });

  final String token;
  final PublicExperience experience;
  final String mediaUrl;
}

class DiscoveryShareService {
  DiscoveryShareService()
      : _firestore = FirebaseFirestore.instance,
        _random = Random.secure();

  final FirebaseFirestore _firestore;
  final Random _random;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('discovery_shares');

  Future<String> createShare({
    required PublicExperience experience,
    required String mediaUrl,
  }) async {
    if (mediaUrl.isEmpty) {
      throw ArgumentError('mediaUrl cannot be empty');
    }

    final String token = _generateToken();
    final Map<String, dynamic> snapshot = {
      'id': experience.id,
      ...experience.toMap(),
    };

    await _collection.doc(token).set({
      'token': token,
      'publicExperienceId': experience.id,
      'mediaUrl': mediaUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'experienceSnapshot': snapshot,
    });

    return 'https://plendy.app/discovery-share/$token';
  }

  Future<DiscoverySharePayload> fetchShare(String token) async {
    final doc = await _collection.doc(token).get();
    if (!doc.exists) {
      throw Exception('Shared discovery preview is no longer available.');
    }

    final data = doc.data();
    if (data == null) {
      throw Exception('Shared discovery preview payload is empty.');
    }

    final String mediaUrl = (data['mediaUrl'] as String?) ?? '';
    if (mediaUrl.isEmpty) {
      throw Exception('Shared discovery preview is missing media URL.');
    }

    final Map<String, dynamic>? snapshot =
        (data['experienceSnapshot'] as Map<String, dynamic>?);
    final String experienceId =
        (data['publicExperienceId'] as String?) ?? snapshot?['id'] ?? '';
    PublicExperience experience;

    if (snapshot != null && snapshot.isNotEmpty) {
      experience = PublicExperience.fromMap(snapshot, experienceId);
    } else {
      experience = await _fetchPublicExperienceById(experienceId);
    }

    // Ensure the shared media is available on the experience for preview parity.
    if (!experience.allMediaPaths.contains(mediaUrl)) {
      final List<String> updated =
          List<String>.from(experience.allMediaPaths);
      updated.insert(0, mediaUrl);
      experience = experience.copyWith(allMediaPaths: updated);
    }

    return DiscoverySharePayload(
      token: token,
      experience: experience,
      mediaUrl: mediaUrl,
    );
  }

  Future<PublicExperience> _fetchPublicExperienceById(String id) async {
    if (id.isEmpty) {
      throw Exception('Shared discovery preview is missing experience data.');
    }
    final doc =
        await _firestore.collection('publicExperiences').doc(id).get();
    if (!doc.exists) {
      throw Exception('This experience is no longer available in discovery.');
    }
    return PublicExperience.fromFirestore(doc);
  }

  String _generateToken() {
    const characters =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List<String>.generate(
      12,
      (_) => characters[_random.nextInt(characters.length)],
    ).join();
  }
}
