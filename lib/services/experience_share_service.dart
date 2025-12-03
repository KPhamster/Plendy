import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/experience.dart';
import '../models/share_result.dart';
import '../models/shared_media_item.dart';
import '../models/user_profile.dart';
import 'experience_service.dart';
import 'message_service.dart';
import 'user_service.dart';

class ExperienceShareService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final MessageService _messageService = MessageService();
  final UserService _userService = UserService();

  CollectionReference get _shares => _firestore.collection('experience_shares');

  String? get _currentUserId => _auth.currentUser?.uid;

  // Generate a short unguessable token if needed for link shares
  String _generateToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random.secure();
    return List.generate(12, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<DirectShareResult> createDirectShare({
    required Experience experience,
    required List<String> toUserIds,
    String? message,
    bool collaboration = false,
    String? highlightedMediaUrl, // For discovery preview shares
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');
    if (toUserIds.isEmpty) throw Exception('No recipients provided');

    final snapshot = await _buildSnapshotFromExperienceAsync(experience);
    
    // Add highlighted media URL to snapshot if provided (for discovery shares)
    if (highlightedMediaUrl != null && highlightedMediaUrl.isNotEmpty) {
      snapshot['highlightedMediaUrl'] = highlightedMediaUrl;
    }

    final data = {
      'experienceId': experience.id,
      'fromUserId': userId,
      'toUserIds': toUserIds,
      'visibility': 'direct',
      'collaboration': collaboration,
      if (message != null && message.isNotEmpty) 'message': message,
      'createdAt': FieldValue.serverTimestamp(),
      'snapshot': snapshot,
      if (highlightedMediaUrl != null && highlightedMediaUrl.isNotEmpty)
        'highlightedMediaUrl': highlightedMediaUrl,
    };

    // Write to the main experience_shares collection for record keeping
    final shareDocRef = await _shares.add(data);
    
    // Track thread IDs and recipient profiles for navigation
    final List<String> threadIds = [];
    final List<UserProfile> recipientProfiles = [];

    // If there's only one recipient, fetch their profile for personalized messaging
    if (toUserIds.length == 1) {
      try {
        final profile = await _userService.getUserProfile(toUserIds.first);
        if (profile != null) {
          recipientProfiles.add(profile);
        }
      } catch (e) {
        // Ignore profile fetch errors - we'll just use generic messaging
        print('Failed to fetch recipient profile: $e');
      }
    }

    // Send experience share message to each recipient via their message thread
    for (final recipientId in toUserIds) {
      try {
        // Get or create a thread between sender and recipient
        final thread = await _messageService.createOrGetThread(
          currentUserId: userId,
          participantIds: [recipientId],
        );

        // Send the experience share as a message
        await _messageService.sendExperienceShareMessage(
          threadId: thread.id,
          senderId: userId,
          experienceSnapshot: snapshot,
          shareId: shareDocRef.id,
        );

        threadIds.add(thread.id);
      } catch (e) {
        // Log error but don't fail the entire share
        print('Failed to send share message to $recipientId: $e');
      }
    }

    return DirectShareResult(
      threadIds: threadIds,
      recipientProfiles: recipientProfiles,
    );
  }

  /// Share to existing message threads (group chats or individual chats)
  Future<DirectShareResult> createDirectShareToThreads({
    required Experience experience,
    required List<String> threadIds,
    String? highlightedMediaUrl,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');
    if (threadIds.isEmpty) throw Exception('No threads provided');

    final snapshot = await _buildSnapshotFromExperienceAsync(experience);
    
    if (highlightedMediaUrl != null && highlightedMediaUrl.isNotEmpty) {
      snapshot['highlightedMediaUrl'] = highlightedMediaUrl;
    }

    final data = {
      'experienceId': experience.id,
      'fromUserId': userId,
      'toThreadIds': threadIds,
      'visibility': 'direct',
      'collaboration': false,
      'createdAt': FieldValue.serverTimestamp(),
      'snapshot': snapshot,
      if (highlightedMediaUrl != null && highlightedMediaUrl.isNotEmpty)
        'highlightedMediaUrl': highlightedMediaUrl,
    };

    final shareDocRef = await _shares.add(data);
    
    // Track successful thread IDs
    final List<String> successThreadIds = [];
    
    // Send experience share message to each thread
    for (final threadId in threadIds) {
      try {
        await _messageService.sendExperienceShareMessage(
          threadId: threadId,
          senderId: userId,
          experienceSnapshot: snapshot,
          shareId: shareDocRef.id,
        );
        successThreadIds.add(threadId);
      } catch (e) {
        print('Failed to send share message to thread $threadId: $e');
      }
    }
    
    return DirectShareResult(threadIds: successThreadIds);
  }

  /// Share to a new group chat with multiple users
  Future<DirectShareResult> createDirectShareToNewGroupChat({
    required Experience experience,
    required List<String> participantIds,
    String? highlightedMediaUrl,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');
    if (participantIds.isEmpty) throw Exception('No participants provided');

    final snapshot = await _buildSnapshotFromExperienceAsync(experience);
    
    if (highlightedMediaUrl != null && highlightedMediaUrl.isNotEmpty) {
      snapshot['highlightedMediaUrl'] = highlightedMediaUrl;
    }

    // Create a new group chat thread with all participants
    final thread = await _messageService.createOrGetThread(
      currentUserId: userId,
      participantIds: participantIds,
    );

    final data = {
      'experienceId': experience.id,
      'fromUserId': userId,
      'toUserIds': participantIds,
      'toThreadId': thread.id,
      'visibility': 'direct',
      'collaboration': false,
      'isGroupShare': true,
      'createdAt': FieldValue.serverTimestamp(),
      'snapshot': snapshot,
      if (highlightedMediaUrl != null && highlightedMediaUrl.isNotEmpty)
        'highlightedMediaUrl': highlightedMediaUrl,
    };

    final shareDocRef = await _shares.add(data);
    
    // Send experience share message to the group chat
    await _messageService.sendExperienceShareMessage(
      threadId: thread.id,
      senderId: userId,
      experienceSnapshot: snapshot,
      shareId: shareDocRef.id,
    );
    
    return DirectShareResult.single(thread.id);
  }

  /// Direct share multiple experiences as a single message card to individual users
  Future<DirectShareResult> createDirectShareForMultiple({
    required List<Experience> experiences,
    required List<String> toUserIds,
    String? message,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');
    if (toUserIds.isEmpty) throw Exception('No recipients provided');
    if (experiences.isEmpty) throw Exception('No experiences provided');

    // Build snapshots for all experiences
    final snapshots = await Future.wait(experiences.map((Experience exp) async {
      final snapshot = await _buildSnapshotFromExperienceAsync(exp);
      return {
        'experienceId': exp.id,
        'snapshot': snapshot,
      };
    }));
    
    final experienceIds = experiences
        .map((e) => e.id)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final data = {
      'experienceIds': experienceIds,
      'fromUserId': userId,
      'toUserIds': toUserIds,
      'visibility': 'direct',
      'collaboration': false,
      if (message != null && message.isNotEmpty) 'message': message,
      'createdAt': FieldValue.serverTimestamp(),
      'experienceSnapshots': snapshots,
      'payloadType': 'multi_experience',
    };

    // Write to the main experience_shares collection for record keeping
    final shareDocRef = await _shares.add(data);
    
    // Track thread IDs and recipient profiles for navigation
    final List<String> threadIds = [];
    final List<UserProfile> recipientProfiles = [];

    // If there's only one recipient, fetch their profile for personalized messaging
    if (toUserIds.length == 1) {
      try {
        final profile = await _userService.getUserProfile(toUserIds.first);
        if (profile != null) {
          recipientProfiles.add(profile);
        }
      } catch (e) {
        // Ignore profile fetch errors - we'll just use generic messaging
        print('Failed to fetch recipient profile: $e');
      }
    }

    // Send multi-experience share message to each recipient via their message thread
    for (final recipientId in toUserIds) {
      try {
        final thread = await _messageService.createOrGetThread(
          currentUserId: userId,
          participantIds: [recipientId],
        );

        await _messageService.sendMultiExperienceShareMessage(
          threadId: thread.id,
          senderId: userId,
          experienceSnapshots: snapshots,
          shareId: shareDocRef.id,
        );

        threadIds.add(thread.id);
      } catch (e) {
        print('Failed to send multi-experience share message to $recipientId: $e');
      }
    }

    return DirectShareResult(
      threadIds: threadIds,
      recipientProfiles: recipientProfiles,
    );
  }

  /// Direct share multiple experiences to existing threads
  Future<DirectShareResult> createDirectShareForMultipleToThreads({
    required List<Experience> experiences,
    required List<String> threadIds,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');
    if (threadIds.isEmpty) throw Exception('No threads provided');
    if (experiences.isEmpty) throw Exception('No experiences provided');

    final snapshots = await Future.wait(experiences.map((Experience exp) async {
      final snapshot = await _buildSnapshotFromExperienceAsync(exp);
      return {
        'experienceId': exp.id,
        'snapshot': snapshot,
      };
    }));
    
    final experienceIds = experiences
        .map((e) => e.id)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final data = {
      'experienceIds': experienceIds,
      'fromUserId': userId,
      'toThreadIds': threadIds,
      'visibility': 'direct',
      'collaboration': false,
      'createdAt': FieldValue.serverTimestamp(),
      'experienceSnapshots': snapshots,
      'payloadType': 'multi_experience',
    };

    final shareDocRef = await _shares.add(data);
    
    // Track successful thread IDs
    final List<String> successThreadIds = [];
    
    for (final threadId in threadIds) {
      try {
        await _messageService.sendMultiExperienceShareMessage(
          threadId: threadId,
          senderId: userId,
          experienceSnapshots: snapshots,
          shareId: shareDocRef.id,
        );
        successThreadIds.add(threadId);
      } catch (e) {
        print('Failed to send multi-experience share message to thread $threadId: $e');
      }
    }
    
    return DirectShareResult(threadIds: successThreadIds);
  }

  /// Direct share multiple experiences to a new group chat
  Future<DirectShareResult> createDirectShareForMultipleToNewGroupChat({
    required List<Experience> experiences,
    required List<String> participantIds,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');
    if (participantIds.isEmpty) throw Exception('No participants provided');
    if (experiences.isEmpty) throw Exception('No experiences provided');

    final snapshots = await Future.wait(experiences.map((Experience exp) async {
      final snapshot = await _buildSnapshotFromExperienceAsync(exp);
      return {
        'experienceId': exp.id,
        'snapshot': snapshot,
      };
    }));
    
    final experienceIds = experiences
        .map((e) => e.id)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    // Create a new group chat thread with all participants
    final thread = await _messageService.createOrGetThread(
      currentUserId: userId,
      participantIds: participantIds,
    );

    final data = {
      'experienceIds': experienceIds,
      'fromUserId': userId,
      'toUserIds': participantIds,
      'toThreadId': thread.id,
      'visibility': 'direct',
      'collaboration': false,
      'isGroupShare': true,
      'createdAt': FieldValue.serverTimestamp(),
      'experienceSnapshots': snapshots,
      'payloadType': 'multi_experience',
    };

    final shareDocRef = await _shares.add(data);
    
    await _messageService.sendMultiExperienceShareMessage(
      threadId: thread.id,
      senderId: userId,
      experienceSnapshots: snapshots,
      shareId: shareDocRef.id,
    );
    
    return DirectShareResult.single(thread.id);
  }

  Future<String> createLinkShare({
    required Experience experience,
    String? message,
    bool public = false,
    DateTime? expiresAt,
    String linkMode = 'separate_copy', // 'my_copy' | 'separate_copy'
    bool grantEdit = false,
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
      'shareType': linkMode, // 'my_copy' or 'separate_copy'
      'accessMode': grantEdit ? 'edit' : 'view',
      if (message != null && message.isNotEmpty) 'message': message,
      'token': token,
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
      'createdAt': FieldValue.serverTimestamp(),
      'snapshot': snapshot,
    };

    await _shares.add(data);

    // Build a public URL on plendy.app using the token
    final String shareUrl = 'https://plendy.app/shared/$token';
    return shareUrl;
  }

  Future<String> createLinkShareForMultiple({
    required List<Experience> experiences,
    String? message,
    bool public = false,
    DateTime? expiresAt,
    bool grantEdit = false,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');
    if (experiences.isEmpty) throw Exception('No experiences provided');

    final token = _generateToken();
    final snapshots = await Future.wait(experiences.map((Experience exp) async {
      final snapshot = await _buildSnapshotFromExperienceAsync(exp);
      return {
        'experienceId': exp.id,
        'snapshot': snapshot,
      };
    }));
    final experienceIds = experiences
        .map((e) => e.id)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final data = {
      'experienceIds': experienceIds,
      'fromUserId': userId,
      'toUserIds': [],
      'visibility': public ? 'public' : 'unlisted',
      'collaboration': false,
      'shareType': 'separate_copy',
      'accessMode': grantEdit ? 'edit' : 'view',
      if (message != null && message.isNotEmpty) 'message': message,
      'token': token,
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
      'createdAt': FieldValue.serverTimestamp(),
      'experienceSnapshots': snapshots,
      'payloadType': 'multi_experience',
    };

    await _shares.add(data);
    return 'https://plendy.app/shared/$token';
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

    // Resolve category icon and color if not already denormalized on the experience
    String? categoryIcon = exp.categoryIconDenorm;
    String? colorHex = exp.colorHexDenorm;
    
    final experienceService = ExperienceService();
    final ownerId = exp.createdBy ?? _currentUserId;
    
    // Look up category icon if needed
    if ((categoryIcon == null || categoryIcon.isEmpty) && exp.categoryId != null && ownerId != null) {
      try {
        final category = await experienceService.getUserCategoryByOwner(ownerId, exp.categoryId!);
        if (category != null) {
          categoryIcon = category.icon;
        }
      } catch (_) {
        // Ignore lookup errors
      }
    }
    
    // Look up color hex if needed
    if ((colorHex == null || colorHex.isEmpty) && exp.colorCategoryId != null && ownerId != null) {
      try {
        final colorCategory = await experienceService.getColorCategoryByOwner(ownerId, exp.colorCategoryId!);
        if (colorCategory != null) {
          // Convert Color to hex string
          colorHex = '#${colorCategory.color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
        }
      } catch (_) {
        // Ignore lookup errors
      }
    }

    return {
      'id': exp.id,
      'name': exp.name,
      'description': exp.description,
      'image': (exp.imageUrls.isNotEmpty ? exp.imageUrls.first : null),
      'imageUrls': exp.imageUrls, // include gallery images
      'mediaUrls': mediaUrls, // expanded content preview
      'sharedMediaItemIds': exp.sharedMediaItemIds, // Include media item IDs for content tab
      'plendyRating': exp.plendyRating,
      'googleRating': exp.googleRating,
      'googleReviewCount': exp.googleReviewCount,
      'priceRange': exp.priceRange,
      'website': exp.website,
      'createdBy': exp.createdBy,
      'editorUserIds': exp.editorUserIds,
      // Category and color denormalized fields for preview display
      'categoryIconDenorm': categoryIcon,
      'colorHexDenorm': colorHex,
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
