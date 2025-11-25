import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'experience.dart';

/// The visibility options that control who can see an event.
enum EventVisibility { private, sharedLink, public }

extension EventVisibilityX on EventVisibility {
  static EventVisibility fromString(String? value) {
    switch (value) {
      case 'sharedLink':
        return EventVisibility.sharedLink;
      case 'public':
        return EventVisibility.public;
      case 'private':
      default:
        return EventVisibility.private;
    }
  }

  String get value => name;
}

/// Available reminder offsets for event notifications.
enum EventNotificationType { fiveMinutes, fifteenMinutes, thirtyMinutes, oneHour, oneDay, custom }

class EventNotificationPreference extends Equatable {
  final EventNotificationType type;
  final Duration? customDuration;

  const EventNotificationPreference({
    this.type = EventNotificationType.oneHour,
    this.customDuration,
  });

  static const EventNotificationPreference defaultPreference =
      EventNotificationPreference(type: EventNotificationType.oneHour);

  Duration get effectiveDuration {
    switch (type) {
      case EventNotificationType.fiveMinutes:
        return const Duration(minutes: 5);
      case EventNotificationType.fifteenMinutes:
        return const Duration(minutes: 15);
      case EventNotificationType.thirtyMinutes:
        return const Duration(minutes: 30);
      case EventNotificationType.oneHour:
        return const Duration(hours: 1);
      case EventNotificationType.oneDay:
        return const Duration(days: 1);
      case EventNotificationType.custom:
        return customDuration ?? const Duration(minutes: 30);
    }
  }

  factory EventNotificationPreference.fromMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      final type = _notificationTypeFromString(data['type'] as String?);
      final customMs = data['customDurationMs'];
      return EventNotificationPreference(
        type: type,
        customDuration: customMs != null ? _parseDuration(customMs) : null,
      );
    }
    return defaultPreference;
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      if (type == EventNotificationType.custom && customDuration != null)
        'customDurationMs': customDuration!.inMilliseconds,
    };
  }

  static EventNotificationType _notificationTypeFromString(String? value) {
    switch (value) {
      case 'fiveMinutes':
        return EventNotificationType.fiveMinutes;
      case 'fifteenMinutes':
        return EventNotificationType.fifteenMinutes;
      case 'thirtyMinutes':
        return EventNotificationType.thirtyMinutes;
      case 'oneDay':
        return EventNotificationType.oneDay;
      case 'custom':
        return EventNotificationType.custom;
      case 'oneHour':
      default:
        return EventNotificationType.oneHour;
    }
  }

  static Duration? _parseDuration(dynamic value) {
    if (value is int) {
      return Duration(milliseconds: value);
    }
    if (value is double) {
      return Duration(milliseconds: value.toInt());
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return Duration(milliseconds: parsed);
      }
    }
    return null;
  }

  @override
  List<Object?> get props => [type, customDuration?.inMilliseconds];
}

/// Represents a single experience entry inside an itinerary.
// Sentinel value to distinguish between "not provided" and "explicitly set to null"
const _undefined = Object();

class EventExperienceEntry extends Equatable {
  final String experienceId;  // Empty string for event-only experiences
  final String? note;
  final DateTime? scheduledTime;
  final String? transportInfo;
  
  // Inline experience data (only used when experienceId is empty)
  final String? inlineName;
  final String? inlineDescription;
  final Location? inlineLocation;
  final String? inlineCategoryId;
  final String? inlineColorCategoryId;
  final String? inlineCategoryIconDenorm;
  final String? inlineColorHexDenorm;
  final List<String> inlineOtherCategoryIds;
  final List<String> inlineOtherColorCategoryIds;

  const EventExperienceEntry({
    required this.experienceId,
    this.note,
    this.scheduledTime,
    this.transportInfo,
    this.inlineName,
    this.inlineDescription,
    this.inlineLocation,
    this.inlineCategoryId,
    this.inlineColorCategoryId,
    this.inlineCategoryIconDenorm,
    this.inlineColorHexDenorm,
    this.inlineOtherCategoryIds = const [],
    this.inlineOtherColorCategoryIds = const [],
  });
  
  /// Helper to determine if this is an event-only experience
  bool get isEventOnly => 
      experienceId.isEmpty && 
      inlineName != null && 
      inlineName!.isNotEmpty;

  factory EventExperienceEntry.fromMap(Map<String, dynamic> map) {
    // Handle experienceId: Firestore might convert empty strings to null
    final experienceIdValue = map['experienceId'];
    final experienceId = experienceIdValue == null || experienceIdValue == '' 
        ? '' 
        : experienceIdValue.toString();
    
    return EventExperienceEntry(
      experienceId: experienceId,
      note: map['note'],
      scheduledTime: _parseNullableTimestamp(map['scheduledTime']),
      transportInfo: map['transportInfo'],
      inlineName: map['inlineName'],
      inlineDescription: map['inlineDescription'],
      inlineLocation: map['inlineLocation'] != null 
          ? Location.fromMap(map['inlineLocation'] as Map<String, dynamic>)
          : null,
      inlineCategoryId: map['inlineCategoryId'],
      inlineColorCategoryId: map['inlineColorCategoryId'],
      inlineCategoryIconDenorm: map['inlineCategoryIconDenorm'],
      inlineColorHexDenorm: map['inlineColorHexDenorm'],
      inlineOtherCategoryIds: _stringList(map['inlineOtherCategoryIds']),
      inlineOtherColorCategoryIds: _stringList(map['inlineOtherColorCategoryIds']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      // Always include experienceId, even if empty (for event-only experiences)
      'experienceId': experienceId.isEmpty ? '' : experienceId,
      if (note != null) 'note': note,
      if (scheduledTime != null)
        'scheduledTime': Timestamp.fromDate(scheduledTime!),
      if (transportInfo != null) 'transportInfo': transportInfo,
      // Always include inlineName if this is an event-only experience
      if (inlineName != null && inlineName!.isNotEmpty) 'inlineName': inlineName,
      if (inlineDescription != null && inlineDescription!.isNotEmpty) 'inlineDescription': inlineDescription,
      if (inlineLocation != null) 'inlineLocation': inlineLocation!.toMap(),
      if (inlineCategoryId != null && inlineCategoryId!.isNotEmpty) 'inlineCategoryId': inlineCategoryId,
      if (inlineColorCategoryId != null && inlineColorCategoryId!.isNotEmpty) 'inlineColorCategoryId': inlineColorCategoryId,
      if (inlineCategoryIconDenorm != null && inlineCategoryIconDenorm!.isNotEmpty) 'inlineCategoryIconDenorm': inlineCategoryIconDenorm,
      if (inlineColorHexDenorm != null && inlineColorHexDenorm!.isNotEmpty) 'inlineColorHexDenorm': inlineColorHexDenorm,
      if (inlineOtherCategoryIds.isNotEmpty) 'inlineOtherCategoryIds': inlineOtherCategoryIds,
      if (inlineOtherColorCategoryIds.isNotEmpty) 'inlineOtherColorCategoryIds': inlineOtherColorCategoryIds,
    };
  }

  EventExperienceEntry copyWith({
    String? experienceId,
    Object? note = _undefined,
    Object? scheduledTime = _undefined,
    Object? transportInfo = _undefined,
    Object? inlineName = _undefined,
    Object? inlineDescription = _undefined,
    Object? inlineLocation = _undefined,
    Object? inlineCategoryId = _undefined,
    Object? inlineColorCategoryId = _undefined,
    Object? inlineCategoryIconDenorm = _undefined,
    Object? inlineColorHexDenorm = _undefined,
    List<String>? inlineOtherCategoryIds,
    List<String>? inlineOtherColorCategoryIds,
  }) {
    return EventExperienceEntry(
      experienceId: experienceId ?? this.experienceId,
      note: note == _undefined ? this.note : note as String?,
      scheduledTime: scheduledTime == _undefined ? this.scheduledTime : scheduledTime as DateTime?,
      transportInfo: transportInfo == _undefined ? this.transportInfo : transportInfo as String?,
      inlineName: inlineName == _undefined ? this.inlineName : inlineName as String?,
      inlineDescription: inlineDescription == _undefined ? this.inlineDescription : inlineDescription as String?,
      inlineLocation: inlineLocation == _undefined ? this.inlineLocation : inlineLocation as Location?,
      inlineCategoryId: inlineCategoryId == _undefined ? this.inlineCategoryId : inlineCategoryId as String?,
      inlineColorCategoryId: inlineColorCategoryId == _undefined ? this.inlineColorCategoryId : inlineColorCategoryId as String?,
      inlineCategoryIconDenorm: inlineCategoryIconDenorm == _undefined ? this.inlineCategoryIconDenorm : inlineCategoryIconDenorm as String?,
      inlineColorHexDenorm: inlineColorHexDenorm == _undefined ? this.inlineColorHexDenorm : inlineColorHexDenorm as String?,
      inlineOtherCategoryIds: inlineOtherCategoryIds ?? this.inlineOtherCategoryIds,
      inlineOtherColorCategoryIds: inlineOtherColorCategoryIds ?? this.inlineOtherColorCategoryIds,
    );
  }

  @override
  List<Object?> get props => [
        experienceId,
        note,
        scheduledTime,
        transportInfo,
        inlineName,
        inlineDescription,
        inlineLocation,
        inlineCategoryId,
        inlineColorCategoryId,
        inlineCategoryIconDenorm,
        inlineColorHexDenorm,
        inlineOtherCategoryIds,
        inlineOtherColorCategoryIds,
      ];
}

/// Represents a comment left on an event, optionally targeting a specific experience.
class EventComment extends Equatable {
  final String commentId;
  final String authorId;
  final String? experienceId;
  final String text;
  final DateTime createdAt;

  const EventComment({
    required this.commentId,
    required this.authorId,
    required this.text,
    required this.createdAt,
    this.experienceId,
  });

  factory EventComment.fromMap(Map<String, dynamic> map) {
    return EventComment(
      commentId: map['commentId'] ?? '',
      authorId: map['authorId'] ?? '',
      experienceId: map['experienceId'],
      text: map['text'] ?? '',
      createdAt: _parseTimestamp(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'commentId': commentId,
      'authorId': authorId,
      'text': text,
      'createdAt': Timestamp.fromDate(createdAt),
      if (experienceId != null) 'experienceId': experienceId,
    };
  }

  EventComment copyWith({
    String? commentId,
    String? authorId,
    String? experienceId,
    String? text,
    DateTime? createdAt,
  }) {
    return EventComment(
      commentId: commentId ?? this.commentId,
      authorId: authorId ?? this.authorId,
      experienceId: experienceId ?? this.experienceId,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [commentId, authorId, experienceId, text, createdAt];
}

/// Core event object that groups experiences into an itinerary.
class Event extends Equatable {
  final String id;
  final String title;
  final String description;
  final DateTime startDateTime;
  final DateTime endDateTime;
  final String? coverImageUrl;
  final String plannerUserId;
  final List<String> collaboratorIds;
  final List<EventExperienceEntry> experiences;
  final EventVisibility visibility;
  final List<String> invitedUserIds;
  final int? capacity;
  final int rsvpCount;
  final EventNotificationPreference notificationPreference;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? shareToken;
  final List<EventComment> comments;

  const Event({
    required this.id,
    required this.title,
    required this.description,
    required this.startDateTime,
    required this.endDateTime,
    required this.plannerUserId,
    required this.createdAt,
    required this.updatedAt,
    this.coverImageUrl,
    this.collaboratorIds = const [],
    this.experiences = const [],
    this.visibility = EventVisibility.private,
    this.invitedUserIds = const [],
    this.capacity,
    this.rsvpCount = 0,
    this.notificationPreference = EventNotificationPreference.defaultPreference,
    this.shareToken,
    this.comments = const [],
  });

  factory Event.fromMap(Map<String, dynamic> map, {String? id}) {
    return Event(
      id: id ?? map['id'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      startDateTime: _parseTimestamp(map['startDateTime']),
      endDateTime: _parseTimestamp(map['endDateTime']),
      coverImageUrl: map['coverImageUrl'],
      plannerUserId: map['plannerUserId'] ?? '',
      collaboratorIds: _stringList(map['collaboratorIds']),
      experiences: _entriesFromList(map['experiences']),
      visibility: EventVisibilityX.fromString(map['visibility'] as String?),
      invitedUserIds: _stringList(map['invitedUserIds']),
      capacity: _parseInt(map['capacity']),
      rsvpCount: _parseInt(map['rsvpCount']) ?? 0,
      notificationPreference: EventNotificationPreference.fromMap(
        map['notificationPreference'],
      ),
      createdAt: _parseTimestamp(map['createdAt']),
      updatedAt: _parseTimestamp(map['updatedAt']),
      shareToken: map['shareToken'],
      comments: _commentsFromList(map['comments']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'startDateTime': Timestamp.fromDate(startDateTime),
      'endDateTime': Timestamp.fromDate(endDateTime),
      'plannerUserId': plannerUserId,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'visibility': visibility.value,
      'collaboratorIds': collaboratorIds,
      'experiences': experiences.map((e) => e.toMap()).toList(),
      'invitedUserIds': invitedUserIds,
      'rsvpCount': rsvpCount,
      'notificationPreference': notificationPreference.toMap(),
      'comments': comments.map((c) => c.toMap()).toList(),
      if (coverImageUrl != null) 'coverImageUrl': coverImageUrl,
      if (capacity != null) 'capacity': capacity,
      if (shareToken != null) 'shareToken': shareToken,
    };
  }

  Event copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? startDateTime,
    DateTime? endDateTime,
    String? coverImageUrl,
    String? plannerUserId,
    List<String>? collaboratorIds,
    List<EventExperienceEntry>? experiences,
    EventVisibility? visibility,
    List<String>? invitedUserIds,
    int? capacity,
    int? rsvpCount,
    EventNotificationPreference? notificationPreference,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? shareToken,
    List<EventComment>? comments,
  }) {
    return Event(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      startDateTime: startDateTime ?? this.startDateTime,
      endDateTime: endDateTime ?? this.endDateTime,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      plannerUserId: plannerUserId ?? this.plannerUserId,
      collaboratorIds: collaboratorIds ?? this.collaboratorIds,
      experiences: experiences ?? this.experiences,
      visibility: visibility ?? this.visibility,
      invitedUserIds: invitedUserIds ?? this.invitedUserIds,
      capacity: capacity ?? this.capacity,
      rsvpCount: rsvpCount ?? this.rsvpCount,
      notificationPreference:
          notificationPreference ?? this.notificationPreference,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      shareToken: shareToken ?? this.shareToken,
      comments: comments ?? this.comments,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        startDateTime,
        endDateTime,
        coverImageUrl,
        plannerUserId,
        collaboratorIds,
        experiences,
        visibility,
        invitedUserIds,
        capacity,
        rsvpCount,
        notificationPreference,
        createdAt,
        updatedAt,
        shareToken,
        comments,
      ];

  static List<EventExperienceEntry> _entriesFromList(dynamic data) {
    if (data is List) {
      return data
          .map((entry) => _mapFromDynamic(entry))
          .whereType<Map<String, dynamic>>()
          .map(EventExperienceEntry.fromMap)
          .toList();
    }
    return const [];
  }

  static List<EventComment> _commentsFromList(dynamic data) {
    if (data is List) {
      return data
          .map((entry) => _mapFromDynamic(entry))
          .whereType<Map<String, dynamic>>()
          .map(EventComment.fromMap)
          .toList();
    }
    return const [];
  }
}

DateTime _parseTimestamp(dynamic value) {
  final fallback = DateTime.now();
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is String) {
    return DateTime.tryParse(value) ?? fallback;
  }
  if (value is DateTime) {
    return value;
  }
  return fallback;
}

DateTime? _parseNullableTimestamp(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  if (value is DateTime) {
    return value;
  }
  return null;
}

int? _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

List<String> _stringList(dynamic data) {
  if (data is Iterable) {
    return data
        .map<String?>((e) => e?.toString())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toList();
  }
  return const [];
}

Map<String, dynamic>? _mapFromDynamic(dynamic data) {
  if (data is Map<String, dynamic>) {
    return data;
  }
  if (data is Map) {
    return data.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}
