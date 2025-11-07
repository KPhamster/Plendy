import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType {
  text,
  experienceShare,
}

class ChatMessage {
  final String id;
  final String threadId;
  final String senderId;
  final String text;
  final DateTime createdAt;
  final MessageType type;
  
  // Fields for experience shares
  final Map<String, dynamic>? experienceSnapshot;
  final String? shareId;

  ChatMessage({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.text,
    required this.createdAt,
    this.type = MessageType.text,
    this.experienceSnapshot,
    this.shareId,
  });

  factory ChatMessage.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String threadId,
  ) {
    final data = doc.data() ?? {};
    final typeString = data['type'] as String?;
    final type = typeString == 'experienceShare' 
        ? MessageType.experienceShare 
        : MessageType.text;
    
    return ChatMessage(
      id: doc.id,
      threadId: threadId,
      senderId: data['senderId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      createdAt: _parseTimestamp(data['createdAt']) ?? DateTime.now(),
      type: type,
      experienceSnapshot: data['experienceSnapshot'] as Map<String, dynamic>?,
      shareId: data['shareId'] as String?,
    );
  }

  bool get isExperienceShare => type == MessageType.experienceShare;

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'senderId': senderId,
      'text': text,
      'createdAt': createdAt,
      'type': type == MessageType.experienceShare ? 'experienceShare' : 'text',
    };
    
    if (experienceSnapshot != null) {
      map['experienceSnapshot'] = experienceSnapshot!;
    }
    if (shareId != null) {
      map['shareId'] = shareId!;
    }
    
    return map;
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
