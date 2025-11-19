import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/chat_message.dart';
import '../models/message_thread.dart';
import '../models/message_thread_participant.dart';
import '../models/user_profile.dart';
import 'user_service.dart';

class MessageService {
  MessageService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    UserService? userService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _userService = userService ?? UserService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final UserService _userService;

  CollectionReference<Map<String, dynamic>> get _threads =>
      _firestore.collection('message_threads');

  String? get currentUserId => _auth.currentUser?.uid;

  Stream<List<MessageThread>> watchThreadsForUser(String userId) {
    return _threads
        .where('participants', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
      final threads =
          snapshot.docs.map((doc) => MessageThread.fromFirestore(doc)).toList();
      threads.sort((a, b) {
        final aTime = a.lastMessageTimestamp ?? a.updatedAt ?? a.createdAt;
        final bTime = b.lastMessageTimestamp ?? b.updatedAt ?? b.createdAt;
        if (aTime == null && bTime == null) {
          return a.id.compareTo(b.id);
        }
        if (aTime == null) {
          return 1;
        }
        if (bTime == null) {
          return -1;
        }
        return bTime.compareTo(aTime);
      });
      return threads;
    });
  }

  Stream<List<ChatMessage>> watchMessages(String threadId) {
    return _threads
        .doc(threadId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ChatMessage.fromFirestore(doc, threadId))
            .toList());
  }

  Stream<MessageThread?> watchThread(String threadId) {
    return _threads.doc(threadId).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }
      return MessageThread.fromFirestore(snapshot);
    });
  }

  Future<MessageThread> createOrGetThread({
    required String currentUserId,
    required List<String> participantIds,
    String? initialMessage,
  }) async {
    if (participantIds.isEmpty) {
      throw ArgumentError('participantIds cannot be empty');
    }

    final allParticipantIds = {
      currentUserId,
      ...participantIds,
    }.toList()
      ..sort();
    final participantsKey = allParticipantIds.join('_');

    final existingSnapshot = await _threads
        .where('participantsKey', isEqualTo: participantsKey)
        .limit(1)
        .get();

    if (existingSnapshot.docs.isNotEmpty) {
      final existingDoc = existingSnapshot.docs.first;
      if (initialMessage != null && initialMessage.trim().isNotEmpty) {
        await sendMessage(
          threadId: existingDoc.id,
          senderId: currentUserId,
          text: initialMessage,
        );
        final refreshed = await existingDoc.reference.get();
        return MessageThread.fromFirestore(refreshed);
      }
      return MessageThread.fromFirestore(existingDoc);
    }

    final participantProfiles =
        await _buildParticipantProfiles(allParticipantIds);
    final now = FieldValue.serverTimestamp();

    final threadRef = await _threads.add({
      'participants': allParticipantIds,
      'participantsKey': participantsKey,
      'participantProfiles':
          participantProfiles.map((key, value) => MapEntry(key, value.toMap())),
      'createdAt': now,
      'updatedAt': now,
      'lastMessage': null,
      'lastMessageSenderId': null,
      'lastMessageTimestamp': null,
    });

    if (initialMessage != null && initialMessage.trim().isNotEmpty) {
      await sendMessage(
        threadId: threadRef.id,
        senderId: currentUserId,
        text: initialMessage,
      );
    }

    final snapshot = await threadRef.get();
    return MessageThread.fromFirestore(snapshot);
  }

  Future<String> sendMessage({
    required String threadId,
    required String senderId,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Message text cannot be empty');
    }

    final threadRef = _threads.doc(threadId);
    final messageRef = threadRef.collection('messages').doc();
    final now = FieldValue.serverTimestamp();

    await _firestore.runTransaction((transaction) async {
      transaction.set(messageRef, {
        'senderId': senderId,
        'text': trimmed,
        'createdAt': now,
        'type': 'text',
      });

      transaction.update(threadRef, {
        'lastMessage': trimmed,
        'lastMessageSenderId': senderId,
        'lastMessageTimestamp': now,
        'updatedAt': now,
      });
    });

    return messageRef.id;
  }

  Future<String> sendExperienceShareMessage({
    required String threadId,
    required String senderId,
    required Map<String, dynamic> experienceSnapshot,
    required String shareId,
  }) async {
    final experienceName = experienceSnapshot['name'] as String? ?? 'an experience';
    final messageText = 'Shared $experienceName';

    final threadRef = _threads.doc(threadId);
    final messageRef = threadRef.collection('messages').doc();
    final now = FieldValue.serverTimestamp();

    await _firestore.runTransaction((transaction) async {
      transaction.set(messageRef, {
        'senderId': senderId,
        'text': messageText,
        'createdAt': now,
        'type': 'experienceShare',
        'experienceSnapshot': experienceSnapshot,
        'shareId': shareId,
      });

      transaction.update(threadRef, {
        'lastMessage': messageText,
        'lastMessageSenderId': senderId,
        'lastMessageTimestamp': now,
        'updatedAt': now,
      });
    });

    return messageRef.id;
  }

  Future<void> refreshParticipantProfile(
    String threadId,
    String userId,
  ) async {
    final profile = await _buildParticipantProfile(userId);
    await _threads.doc(threadId).update({
      'participantProfiles.$userId': profile.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateThreadTitle({
    required String threadId,
    required String title,
  }) async {
    final trimmed = title.trim();
    final Map<String, dynamic> updates = {
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (trimmed.isEmpty) {
      updates['title'] = FieldValue.delete();
    } else {
      updates['title'] = trimmed;
    }

    await _threads.doc(threadId).update(updates);
  }

  Future<Map<String, MessageThreadParticipant>> _buildParticipantProfiles(
    List<String> userIds,
  ) async {
    final futures = userIds.map(_buildParticipantProfile);
    final participants = await Future.wait(futures);
    final map = <String, MessageThreadParticipant>{};
    for (final participant in participants) {
      map[participant.id] = participant;
    }
    return map;
  }

  Future<MessageThreadParticipant> _buildParticipantProfile(
      String userId) async {
    UserProfile? profile;
    try {
      profile = await _userService.getUserProfile(userId);
    } catch (_) {
      profile = null;
    }

    return MessageThreadParticipant(
      id: userId,
      username: profile?.username,
      displayName: profile?.displayName,
      photoUrl: profile?.photoURL,
    );
  }

  /// Mark a thread as read by the current user
  Future<void> markThreadAsRead(String threadId, String userId) async {
    await _threads.doc(threadId).update({
      'lastReadTimestamps.$userId': FieldValue.serverTimestamp(),
    });
  }

  /// Get the count of unread threads for a user
  Stream<int> watchUnreadCount(String userId) {
    return watchThreadsForUser(userId).map((threads) {
      return threads.where((thread) => thread.hasUnreadMessages(userId)).length;
    });
  }
}
