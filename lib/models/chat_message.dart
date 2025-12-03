import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType {
  text,
  experienceShare,
  multiExperienceShare,
  categoryShare,
  multiCategoryShare,
  eventShare,
  profileShare,
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
  
  // Fields for multi-experience shares
  final List<Map<String, dynamic>>? experienceSnapshots;
  
  // Fields for category shares
  final Map<String, dynamic>? categorySnapshot;
  
  // Fields for multi-category shares
  final List<Map<String, dynamic>>? categorySnapshots;
  
  // Fields for event shares
  final Map<String, dynamic>? eventSnapshot;
  
  // Fields for profile shares
  final Map<String, dynamic>? profileSnapshot;

  ChatMessage({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.text,
    required this.createdAt,
    this.type = MessageType.text,
    this.experienceSnapshot,
    this.shareId,
    this.experienceSnapshots,
    this.categorySnapshot,
    this.categorySnapshots,
    this.eventSnapshot,
    this.profileSnapshot,
  });

  factory ChatMessage.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String threadId,
  ) {
    final data = doc.data() ?? {};
    final typeString = data['type'] as String?;
    MessageType type;
    if (typeString == 'multiExperienceShare') {
      type = MessageType.multiExperienceShare;
    } else if (typeString == 'experienceShare') {
      type = MessageType.experienceShare;
    } else if (typeString == 'categoryShare') {
      type = MessageType.categoryShare;
    } else if (typeString == 'multiCategoryShare') {
      type = MessageType.multiCategoryShare;
    } else if (typeString == 'eventShare') {
      type = MessageType.eventShare;
    } else if (typeString == 'profileShare') {
      type = MessageType.profileShare;
    } else {
      type = MessageType.text;
    }
    
    // Parse experienceSnapshots for multi-experience shares
    List<Map<String, dynamic>>? experienceSnapshots;
    final rawSnapshots = data['experienceSnapshots'];
    if (rawSnapshots is List) {
      experienceSnapshots = rawSnapshots
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    
    // Parse categorySnapshots for multi-category shares
    List<Map<String, dynamic>>? categorySnapshots;
    final rawCategorySnapshots = data['categorySnapshots'];
    if (rawCategorySnapshots is List) {
      categorySnapshots = rawCategorySnapshots
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    
    return ChatMessage(
      id: doc.id,
      threadId: threadId,
      senderId: data['senderId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      createdAt: _parseTimestamp(data['createdAt']) ?? DateTime.now(),
      type: type,
      experienceSnapshot: data['experienceSnapshot'] as Map<String, dynamic>?,
      shareId: data['shareId'] as String?,
      experienceSnapshots: experienceSnapshots,
      categorySnapshot: data['categorySnapshot'] as Map<String, dynamic>?,
      categorySnapshots: categorySnapshots,
      eventSnapshot: data['eventSnapshot'] as Map<String, dynamic>?,
      profileSnapshot: data['profileSnapshot'] as Map<String, dynamic>?,
    );
  }

  bool get isExperienceShare => type == MessageType.experienceShare;
  bool get isMultiExperienceShare => type == MessageType.multiExperienceShare;
  bool get isCategoryShare => type == MessageType.categoryShare;
  bool get isMultiCategoryShare => type == MessageType.multiCategoryShare;
  bool get isEventShare => type == MessageType.eventShare;
  bool get isProfileShare => type == MessageType.profileShare;

  Map<String, dynamic> toMap() {
    String typeString;
    switch (type) {
      case MessageType.experienceShare:
        typeString = 'experienceShare';
        break;
      case MessageType.multiExperienceShare:
        typeString = 'multiExperienceShare';
        break;
      case MessageType.categoryShare:
        typeString = 'categoryShare';
        break;
      case MessageType.multiCategoryShare:
        typeString = 'multiCategoryShare';
        break;
      case MessageType.eventShare:
        typeString = 'eventShare';
        break;
      case MessageType.profileShare:
        typeString = 'profileShare';
        break;
      default:
        typeString = 'text';
    }
    
    final map = <String, dynamic>{
      'senderId': senderId,
      'text': text,
      'createdAt': createdAt,
      'type': typeString,
    };
    
    if (experienceSnapshot != null) {
      map['experienceSnapshot'] = experienceSnapshot!;
    }
    if (shareId != null) {
      map['shareId'] = shareId!;
    }
    if (experienceSnapshots != null && experienceSnapshots!.isNotEmpty) {
      map['experienceSnapshots'] = experienceSnapshots!;
    }
    if (categorySnapshot != null) {
      map['categorySnapshot'] = categorySnapshot!;
    }
    if (categorySnapshots != null && categorySnapshots!.isNotEmpty) {
      map['categorySnapshots'] = categorySnapshots!;
    }
    if (eventSnapshot != null) {
      map['eventSnapshot'] = eventSnapshot!;
    }
    if (profileSnapshot != null) {
      map['profileSnapshot'] = profileSnapshot!;
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
