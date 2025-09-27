import 'package:cloud_firestore/cloud_firestore.dart';
import 'message_thread_participant.dart';

class MessageThread {
  final String id;
  final List<String> participantIds;
  final Map<String, MessageThreadParticipant> participantProfiles;
  final String? lastMessage;
  final String? lastMessageSenderId;
  final DateTime? lastMessageTimestamp;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String participantsKey;

  MessageThread({
    required this.id,
    required this.participantIds,
    required this.participantProfiles,
    required this.participantsKey,
    this.lastMessage,
    this.lastMessageSenderId,
    this.lastMessageTimestamp,
    this.createdAt,
    this.updatedAt,
  });

  factory MessageThread.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final profilesRaw =
        data['participantProfiles'] as Map<String, dynamic>? ?? {};
    final profiles = <String, MessageThreadParticipant>{};
    profilesRaw.forEach((key, value) {
      profiles[key] =
          MessageThreadParticipant.fromMap(key, value as Map<String, dynamic>?);
    });
    return MessageThread(
      id: doc.id,
      participantIds:
          List<String>.from(data['participants'] as List<dynamic>? ?? const []),
      participantProfiles: profiles,
      participantsKey: data['participantsKey'] as String? ?? '',
      lastMessage: data['lastMessage'] as String?,
      lastMessageSenderId: data['lastMessageSenderId'] as String?,
      lastMessageTimestamp: _parseTimestamp(data['lastMessageTimestamp']),
      createdAt: _parseTimestamp(data['createdAt']),
      updatedAt: _parseTimestamp(data['updatedAt']),
    );
  }

  bool get isGroup => participantIds.length > 2;

  List<MessageThreadParticipant> otherParticipants(String currentUserId) {
    final others = participantIds.where((id) => id != currentUserId);
    return others
        .map(
            (id) => participantProfiles[id] ?? MessageThreadParticipant(id: id))
        .toList();
  }

  MessageThreadParticipant? participant(String userId) {
    return participantProfiles[userId];
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }
}
