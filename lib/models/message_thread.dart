import 'package:cloud_firestore/cloud_firestore.dart';
import 'message_thread_participant.dart';

class MessageTextSegment {
  final String text;
  final Uri? uri;

  const MessageTextSegment._(this.text, this.uri);

  factory MessageTextSegment.text(String text) =>
      MessageTextSegment._(text, null);

  factory MessageTextSegment.link(String text, Uri uri) =>
      MessageTextSegment._(text, uri);

  bool get isLink => uri != null;
}

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
  final Map<String, DateTime?> lastReadTimestamps; // userId -> last read timestamp

  static final RegExp _urlRegex = RegExp(
    r'''((?:https?:\/\/|www\.)[^\s<>()\[\]{}"'`]+)''',
    caseSensitive: false,
  );

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
    this.lastReadTimestamps = const {},
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
    
    // Parse lastReadTimestamps
    final lastReadRaw = data['lastReadTimestamps'] as Map<String, dynamic>? ?? {};
    final lastReadTimestamps = <String, DateTime?>{};
    lastReadRaw.forEach((key, value) {
      lastReadTimestamps[key] = _parseTimestamp(value);
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
      lastReadTimestamps: lastReadTimestamps,
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

  /// Check if this thread has unread messages for the given user
  bool hasUnreadMessages(String userId) {
    // If there's no last message, no unread messages
    if (lastMessageTimestamp == null) {
      return false;
    }
    
    // If user is the sender of the last message, it's not unread for them
    if (lastMessageSenderId == userId) {
      return false;
    }
    
    // Check if user has read the thread since the last message
    final lastRead = lastReadTimestamps[userId];
    if (lastRead == null) {
      // Never read, so it's unread
      return true;
    }
    
    // Unread if last message is after last read time
    return lastMessageTimestamp!.isAfter(lastRead);
  }

  static List<MessageTextSegment> extractMessageSegments(String? message) {
    if (message == null || message.isEmpty) {
      return [MessageTextSegment.text('')];
    }

    final matches = _urlRegex.allMatches(message);
    if (matches.isEmpty) {
      return [MessageTextSegment.text(message)];
    }

    final segments = <MessageTextSegment>[];
    var currentIndex = 0;

    for (final match in matches) {
      if (match.start > currentIndex) {
        segments.add(
          MessageTextSegment.text(message.substring(currentIndex, match.start)),
        );
      }

      var urlText = match.group(0) ?? '';

      // Strip trailing punctuation that is unlikely to belong to the URL.
      final trailingBuffer = StringBuffer();
      const trailingCharacters = '.,?!:;)]}\'"';
      while (urlText.isNotEmpty &&
          trailingCharacters.contains(urlText[urlText.length - 1])) {
        trailingBuffer.write(urlText[urlText.length - 1]);
        urlText = urlText.substring(0, urlText.length - 1);
      }

      final normalized = urlText.contains('://') ? urlText : 'https://$urlText';
      final uri = Uri.tryParse(normalized);

      if (uri != null) {
        segments.add(MessageTextSegment.link(urlText, uri));
      } else {
        segments.add(MessageTextSegment.text(urlText));
      }

      final trailing = trailingBuffer.toString();
      if (trailing.isNotEmpty) {
        segments
            .add(MessageTextSegment.text(trailing.split('').reversed.join()));
      }

      currentIndex = match.end;
    }

    if (currentIndex < message.length) {
      segments.add(
        MessageTextSegment.text(message.substring(currentIndex)),
      );
    }

    return segments.where((segment) => segment.text.isNotEmpty).toList();
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
