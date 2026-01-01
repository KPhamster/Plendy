/// Data class representing extracted event information from shared content
class ExtractedEventInfo {
  /// Event name or title (if detected)
  final String? eventName;
  
  /// Event start date and time
  final DateTime startDateTime;
  
  /// Event end date and time
  final DateTime endDateTime;
  
  /// Confidence score from 0.0 to 1.0
  final double confidence;
  
  /// Raw text that was parsed to extract the event info
  final String? rawText;
  
  /// Ticketmaster event URL (if found on Ticketmaster)
  final String? ticketmasterUrl;
  
  /// Ticketmaster event ID (if found on Ticketmaster)
  final String? ticketmasterId;
  
  /// The search term that found results on Ticketmaster (use this for search URL)
  final String? ticketmasterSearchTerm;
  
  /// Ticketmaster event image URL (for cover image)
  final String? ticketmasterImageUrl;

  const ExtractedEventInfo({
    this.eventName,
    required this.startDateTime,
    required this.endDateTime,
    this.confidence = 0.8,
    this.rawText,
    this.ticketmasterUrl,
    this.ticketmasterId,
    this.ticketmasterSearchTerm,
    this.ticketmasterImageUrl,
  });

  /// Create from a map (for JSON deserialization)
  factory ExtractedEventInfo.fromMap(Map<String, dynamic> map) {
    return ExtractedEventInfo(
      eventName: map['event_name'] as String?,
      startDateTime: _parseDateTime(map['start_datetime']) ?? DateTime.now(),
      endDateTime: _parseDateTime(map['end_datetime']) ?? DateTime.now().add(const Duration(hours: 1)),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.8,
      rawText: map['raw_text'] as String?,
      ticketmasterUrl: map['ticketmaster_url'] as String?,
      ticketmasterId: map['ticketmaster_id'] as String?,
      ticketmasterSearchTerm: map['ticketmaster_search_term'] as String?,
      ticketmasterImageUrl: map['ticketmaster_image_url'] as String?,
    );
  }

  /// Convert to map (for JSON serialization)
  Map<String, dynamic> toMap() {
    return {
      'event_name': eventName,
      'start_datetime': startDateTime.toIso8601String(),
      'end_datetime': endDateTime.toIso8601String(),
      'confidence': confidence,
      'raw_text': rawText,
      'ticketmaster_url': ticketmasterUrl,
      'ticketmaster_id': ticketmasterId,
      'ticketmaster_search_term': ticketmasterSearchTerm,
      'ticketmaster_image_url': ticketmasterImageUrl,
    };
  }

  /// Create a copy with updated fields
  ExtractedEventInfo copyWith({
    String? eventName,
    DateTime? startDateTime,
    DateTime? endDateTime,
    double? confidence,
    String? rawText,
    String? ticketmasterUrl,
    String? ticketmasterId,
    String? ticketmasterSearchTerm,
    String? ticketmasterImageUrl,
  }) {
    return ExtractedEventInfo(
      eventName: eventName ?? this.eventName,
      startDateTime: startDateTime ?? this.startDateTime,
      endDateTime: endDateTime ?? this.endDateTime,
      confidence: confidence ?? this.confidence,
      rawText: rawText ?? this.rawText,
      ticketmasterUrl: ticketmasterUrl ?? this.ticketmasterUrl,
      ticketmasterId: ticketmasterId ?? this.ticketmasterId,
      ticketmasterSearchTerm: ticketmasterSearchTerm ?? this.ticketmasterSearchTerm,
      ticketmasterImageUrl: ticketmasterImageUrl ?? this.ticketmasterImageUrl,
    );
  }

  /// Parse datetime from various formats
  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    
    if (value is DateTime) return value;
    
    if (value is String) {
      // Try ISO 8601 format first
      final iso = DateTime.tryParse(value);
      if (iso != null) return iso;
      
      // Try common date/time formats
      // Format: "2024-12-30 14:00" or "12/30/2024 2:00 PM"
      // This is a simplified parser - Gemini should return ISO format
      return null;
    }
    
    if (value is int) {
      // Unix timestamp in milliseconds
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    
    return null;
  }

  /// Check if this is a valid event (end time after start time)
  bool get isValid => endDateTime.isAfter(startDateTime);

  /// Get the duration of the event
  Duration get duration => endDateTime.difference(startDateTime);

  @override
  String toString() {
    return 'ExtractedEventInfo(eventName: $eventName, start: $startDateTime, end: $endDateTime, confidence: $confidence)';
  }
}

