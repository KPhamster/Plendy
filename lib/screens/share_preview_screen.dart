import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_app_check/firebase_app_check.dart';
import '../../firebase_options.dart';
import '../models/experience.dart';
import '../models/user_category.dart';
import '../models/color_category.dart';
import 'experience_page_screen.dart';
import '../models/shared_media_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import '../services/experience_service.dart';
import '../widgets/edit_experience_modal.dart';
import 'main_screen.dart';

class SharePreviewScreen extends StatelessWidget {
  final String token;

  const SharePreviewScreen({super.key, required this.token});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared Experience', style: TextStyle(fontSize: 16)),
        actions: [
          if (kIsWeb)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.black),
                icon: const Icon(Icons.open_in_new, color: Colors.black),
                label: const Text('Open in Plendy', style: TextStyle(color: Colors.black)),
                onPressed: () => _handleOpenInApp(context),
              ),
            ),
        ],
      ),
      body: FutureBuilder<_PreviewPayload>(
        future: _fetchExperienceFromShare(token),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('This share isn\'t available.'));
          }
          final payload = snapshot.data!;
          final experience = payload.experience;
          final placeholderCategory =
              UserCategory(id: 'shared', name: 'Shared', icon: '🌐', ownerUserId: '');
          return ExperiencePageScreen(
            experience: experience,
            category: placeholderCategory,
            userColorCategories: const <ColorCategory>[],
            initialMediaItems: payload.mediaItems,
            // Put the screen into read-only mode so destructive actions are hidden
            readOnlyPreview: true,
            shareBannerFromUserId: payload.fromUserId,
            onSaveExperience: () => _handleSaveExperience(context, payload),
          );
        },
      ),
    );
  }

  Future<void> _handleOpenInApp(BuildContext context) async {
    // Try to open the app via your universal link first (should trigger App/Universal Links)
    final Uri deepLink = Uri.parse('https://plendy.app/shared/' + token);
    final bool launchedDeepLink = await launchUrl(
      deepLink,
      mode: LaunchMode.externalApplication,
    );
    if (launchedDeepLink) {
      return;
    }

    // Fallback: open respective store
    final TargetPlatform platform = Theme.of(context).platform;
    if (platform == TargetPlatform.android) {
      // Prefer Play Store intent; fallback to HTTPS
      final Uri intentUri = Uri.parse(
          'intent://details?id=com.plendy.app#Intent;scheme=market;package=com.android.vending;end');
      final bool intentOk = await launchUrl(intentUri, mode: LaunchMode.externalApplication);
      if (intentOk) return;
      final Uri webPlay = Uri.parse('https://play.google.com/store/apps/details?id=com.plendy.app');
      await launchUrl(webPlay);
    } else if (platform == TargetPlatform.iOS) {
      // Use itms-apps scheme first; fallback to HTTPS
      final Uri itms = Uri.parse('itms-apps://apps.apple.com');
      final bool itmsOk = await launchUrl(itms, mode: LaunchMode.externalApplication);
      if (itmsOk) return;
      final Uri webAppStore = Uri.parse('https://apps.apple.com');
      await launchUrl(webAppStore);
    } else {
      // Default fallback
      final Uri webHome = Uri.parse('https://plendy.app');
      await launchUrl(webHome);
    }
  }

  Future<_PreviewPayload> _fetchExperienceFromShare(String token) async {
    // Use Firestore REST with explicit App Check header to avoid SDK listen flow
    final appCheckToken = await FirebaseAppCheck.instance.getToken(true);
    final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      // Move API key to header instead of URL param
      if (apiKey.isNotEmpty) 'x-goog-api-key': apiKey,
      if (appCheckToken != null && appCheckToken.isNotEmpty)
        'X-Firebase-AppCheck': appCheckToken,
    };

    final projectId = 'plendy-7df50';
    final idParam = Uri.base.queryParameters['id'];

    if (idParam != null && idParam.isNotEmpty) {
      final docUrl = Uri.parse(
          'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/experience_shares/$idParam');
      final resp = await http.get(docUrl, headers: headers);
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body) as Map<String, dynamic>;
        final mapped = _mapRestDoc(body);
        return _payloadFromMapped(mapped);
      }
      // fall through to token query
    }

    final runQueryUrl = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents:runQuery');
    final payload = {
      'structuredQuery': {
        'from': [
          {'collectionId': 'experience_shares'}
        ],
        'where': {
          'compositeFilter': {
            'op': 'AND',
            'filters': [
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'token'},
                  'op': 'EQUAL',
                  'value': {'stringValue': token}
                }
              },
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'visibility'},
                  'op': 'IN',
                  'value': {
                    'arrayValue': {
                      'values': [
                        {'stringValue': 'public'},
                        {'stringValue': 'unlisted'}
                      ]
                    }
                  }
                }
              }
            ]
          }
        },
        'limit': 1
      }
    };
    final resp = await http.post(runQueryUrl, headers: headers, body: json.encode(payload));
    if (resp.statusCode != 200) {
      throw Exception('Share lookup failed (${resp.statusCode})');
    }
    final List results = json.decode(resp.body) as List;
    final Map<String, dynamic>? first = results.cast<Map<String, dynamic>?>().firstWhere(
        (e) => e != null && e.containsKey('document'),
        orElse: () => null);
    if (first == null) {
      throw Exception('Share not found');
    }
    final mapped = _mapRestDoc(first['document'] as Map<String, dynamic>);
    return _payloadFromMapped(mapped);
  }

  Map<String, dynamic> _mapRestDoc(Map<String, dynamic> docJson) {
    // Firestore REST returns fields under document.fields as typed values
    final name = docJson['name'] as String?; // projects/.../documents/experience_shares/{id}
    final shareId = name != null ? name.split('/').last : '';
    final fields = (docJson['fields'] ?? {}) as Map<String, dynamic>;

    dynamic _decodeValue(dynamic value) {
      if (value is! Map<String, dynamic>) return value;
      if (value.containsKey('nullValue')) return null;
      if (value.containsKey('stringValue')) return value['stringValue'];
      if (value.containsKey('booleanValue')) return value['booleanValue'] as bool;
      if (value.containsKey('integerValue')) return int.tryParse(value['integerValue'] as String);
      if (value.containsKey('doubleValue')) return (value['doubleValue'] as num).toDouble();
      if (value.containsKey('timestampValue')) return value['timestampValue'];
      if (value.containsKey('geoPointValue')) return value['geoPointValue'];
      if (value.containsKey('arrayValue')) {
        final list = (value['arrayValue']['values'] as List?) ?? const [];
        return list.map(_decodeValue).toList();
      }
      if (value.containsKey('mapValue')) {
        final m = (value['mapValue']['fields'] as Map<String, dynamic>?) ?? const {};
        return m.map((k, v) => MapEntry(k, _decodeValue(v)));
      }
      return value;
    }

    Map<String, dynamic> _decodeFields(Map<String, dynamic> raw) {
      return raw.map((k, v) => MapEntry(k, _decodeValue(v)));
    }

    final decoded = _decodeFields(fields);

    return {
      'shareId': shareId,
      'experienceId': decoded['experienceId'],
      'fromUserId': decoded['fromUserId'],
      'visibility': decoded['visibility'],
      'snapshot': decoded['snapshot'],
      'message': decoded['message'],
      'createdAt': decoded['createdAt'],
    };
  }

  Experience _experienceFromMapped(Map<String, dynamic> mapped) {
    final snap = (mapped['snapshot'] as Map<String, dynamic>?) ?? const {};
    final loc = (snap['location'] as Map<String, dynamic>?) ?? const {};

    double _toDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0.0;
      return 0.0;
    }

    int? _toInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is String) return int.tryParse(v);
      if (v is num) return v.toInt();
      return null;
    }

    List<String> _toStringList(dynamic v) {
      if (v is List) {
        return v.map((e) => e.toString()).toList();
      }
      return const <String>[];
    }

    final imageFromTop = snap['image'] as String?;
    final imageUrls = _toStringList(snap['imageUrls']);
    final mediaUrls = _toStringList(snap['mediaUrls']);
    final firstImage = imageFromTop?.isNotEmpty == true
        ? imageFromTop
        : (imageUrls.isNotEmpty ? imageUrls.first : null);

    final location = Location(
      placeId: loc['placeId'] as String?,
      latitude: _toDouble(loc['latitude']),
      longitude: _toDouble(loc['longitude']),
      address: loc['address'] as String?,
      city: loc['city'] as String?,
      state: loc['state'] as String?,
      country: loc['country'] as String?,
      displayName: loc['displayName'] as String?,
      photoUrl: firstImage,
      website: snap['website'] as String?,
      rating: (snap['googleRating'] as num?)?.toDouble(),
      userRatingCount: _toInt(snap['googleReviewCount']),
    );

    final now = DateTime.now();
    return Experience(
      id: (mapped['experienceId'] as String?) ?? ('share_${mapped['shareId'] ?? ''}'),
      name: (snap['name'] as String?) ?? 'Experience',
      description: (snap['description'] as String?) ?? '',
      location: location,
      categoryId: null,
      yelpUrl: null,
      yelpRating: null,
      yelpReviewCount: null,
      googleUrl: null,
      googleRating: (snap['googleRating'] as num?)?.toDouble(),
      googleReviewCount: _toInt(snap['googleReviewCount']),
      plendyRating: (snap['plendyRating'] as num?)?.toDouble() ?? 0.0,
      plendyReviewCount: 0,
      imageUrls: imageUrls.isNotEmpty ? imageUrls : mediaUrls,
      reelIds: const <String>[],
      followerIds: const <String>[],
      rating: (snap['plendyRating'] as num?)?.toDouble() ?? 0.0,
      createdAt: now,
      updatedAt: now,
      website: snap['website'] as String?,
      phoneNumber: snap['phone'] as String?,
      openingHours: null,
      tags: null,
      priceRange: snap['priceRange'] as String?,
      sharedMediaItemIds: const <String>[],
      sharedMediaType: null,
      additionalNotes: null,
      editorUserIds: const <String>[],
      colorCategoryId: null,
      otherCategories: const <String>[],
    );
  }

  _PreviewPayload _payloadFromMapped(Map<String, dynamic> mapped) {
    final exp = _experienceFromMapped(mapped);
    final snap = (mapped['snapshot'] as Map<String, dynamic>?) ?? const {};
    final mediaUrls = ((snap['mediaUrls'] as List?) ?? []).map((e) => e.toString()).toList();
    final List<SharedMediaItem> mediaItems = mediaUrls
        .map((u) => SharedMediaItem(
              id: 'preview_${u.hashCode}',
              path: u,
              createdAt: DateTime.now(),
              ownerUserId: 'public',
              experienceIds: [exp.id],
              isTiktokPhoto: null,
            ))
        .toList();
    return _PreviewPayload(
      experience: exp,
      mediaItems: mediaItems,
      fromUserId: (mapped['fromUserId'] as String?) ?? '',
    );
  }

}

  Future<void> _handleSaveExperience(BuildContext context, _PreviewPayload payload) async {
    final expService = ExperienceService();
    final experience = payload.experience;

    try {
      // Build base for modal: clear categories; keep title/location/links/notes
      // Set id to '' so modal treats this as a new item and runs duplicate check
      final Experience baseForModal = experience.copyWith(
        id: '',
        clearCategoryId: true,
        colorCategoryId: null,
        otherCategories: <String>[],
        editorUserIds: const <String>[],
      );

      final Experience? result = await showModalBottomSheet<Experience>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          return EditExperienceModal(
            experience: baseForModal,
            userCategories: const <UserCategory>[],
            userColorCategories: const <ColorCategory>[],
            enableDuplicatePrompt: true,
          );
        },
      );

      if (result == null) return;

      // If the modal ended up editing an existing experience (id set), update; else create
      if (result.id.isNotEmpty) {
        await expService.updateExperience(result);
      } else {
        await expService.createExperience(result);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Experience saved.')),
        );
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const MainScreen()),
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save experience: $e')),
        );
      }
    }
  }

class _PreviewPayload {
  final Experience experience;
  final List<SharedMediaItem> mediaItems;
  final String fromUserId;
  const _PreviewPayload({required this.experience, required this.mediaItems, required this.fromUserId});
}



