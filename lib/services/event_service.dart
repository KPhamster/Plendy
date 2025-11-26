import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/event.dart';

/// Service for managing Event-related operations
class EventService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference get _eventsCollection => _firestore.collection('events');

  String? get _currentUserId => _auth.currentUser?.uid;

  /// Create a new event
  Future<String> createEvent(Event event) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    print('EventService: Creating event for user $_currentUserId');
    print('EventService: Event title: ${event.title}');
    print('EventService: Event start: ${event.startDateTime}');
    print('EventService: Event planner: ${event.plannerUserId}');

    final now = FieldValue.serverTimestamp();
    final data = event.toMap();
    data['createdAt'] = now;
    data['updatedAt'] = now;
    // Track who created the event (for notification filtering)
    data['lastModifiedByUserId'] = _currentUserId;

    final docRef = await _eventsCollection.add(data);
    print('EventService: Event created with ID: ${docRef.id}');
    return docRef.id;
  }

  /// Update an existing event
  Future<void> updateEvent(Event event) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    final data = event.toMap();
    data['updatedAt'] = FieldValue.serverTimestamp();
    // Track who made the update (for notification filtering)
    data['lastModifiedByUserId'] = _currentUserId;

    await _eventsCollection.doc(event.id).update(data);
  }

  /// Get an event by ID
  Future<Event?> getEvent(String eventId) async {
    final doc = await _eventsCollection.doc(eventId).get();
    if (!doc.exists) {
      return null;
    }
    return Event.fromMap(doc.data() as Map<String, dynamic>, id: doc.id);
  }

  /// Delete an event
  Future<void> deleteEvent(String eventId) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    await _eventsCollection.doc(eventId).delete();
  }

  /// Get events for a user (as planner, collaborator, or invited viewer)
  Future<List<Event>> getEventsForUser(String userId) async {
    try {
      // Query for events where user is the planner (without orderBy to avoid index issues)
      final plannerQuery = await _eventsCollection
          .where('plannerUserId', isEqualTo: userId)
          .get();

      // Query for events where user is a collaborator (without orderBy to avoid index issues)
      final collaboratorQuery = await _eventsCollection
          .where('collaboratorIds', arrayContains: userId)
          .get();

      // Query for events where user is invited as a viewer (without orderBy to avoid index issues)
      final invitedQuery = await _eventsCollection
          .where('invitedUserIds', arrayContains: userId)
          .get();

      final Set<String> seenIds = {};
      final List<Event> events = [];

      // Combine results and deduplicate
      for (final doc in [...plannerQuery.docs, ...collaboratorQuery.docs, ...invitedQuery.docs]) {
        if (!seenIds.contains(doc.id)) {
          seenIds.add(doc.id);
          try {
            events.add(Event.fromMap(doc.data() as Map<String, dynamic>, id: doc.id));
          } catch (e) {
            print('Error parsing event ${doc.id}: $e');
          }
        }
      }

      // Sort in memory instead of in Firestore (most recent first)
      events.sort((a, b) => b.startDateTime.compareTo(a.startDateTime));
      
      print('EventService: Found ${events.length} events for user $userId');
      return events;
    } catch (e, stackTrace) {
      print('EventService: Error fetching events: $e');
      print('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Generate a unique share token for an event
  Future<String> generateShareToken(String eventId) async {
    final token = _generateToken();
    await _eventsCollection.doc(eventId).update({
      'shareToken': token,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return token;
  }

  /// Revoke share token
  Future<void> revokeShareToken(String eventId) async {
    await _eventsCollection.doc(eventId).update({
      'shareToken': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Get event by share token
  Future<Event?> getEventByShareToken(String token) async {
    final query = await _eventsCollection
        .where('shareToken', isEqualTo: token)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      return null;
    }

    return Event.fromMap(query.docs.first.data() as Map<String, dynamic>,
        id: query.docs.first.id);
  }

  String _generateToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = DateTime.now().millisecondsSinceEpoch.toString();
    return random.split('').map((c) => chars[int.parse(c)]).join();
  }
}

