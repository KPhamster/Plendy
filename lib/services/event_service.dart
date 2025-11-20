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

    final now = FieldValue.serverTimestamp();
    final data = event.toMap();
    data['createdAt'] = now;
    data['updatedAt'] = now;

    final docRef = await _eventsCollection.add(data);
    return docRef.id;
  }

  /// Update an existing event
  Future<void> updateEvent(Event event) async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    final data = event.toMap();
    data['updatedAt'] = FieldValue.serverTimestamp();

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

  /// Get events for a user (as planner or collaborator)
  Future<List<Event>> getEventsForUser(String userId) async {
    final plannerQuery = await _eventsCollection
        .where('plannerUserId', isEqualTo: userId)
        .orderBy('startDateTime', descending: true)
        .get();

    final collaboratorQuery = await _eventsCollection
        .where('collaboratorIds', arrayContains: userId)
        .orderBy('startDateTime', descending: true)
        .get();

    final Set<String> seenIds = {};
    final List<Event> events = [];

    for (final doc in [...plannerQuery.docs, ...collaboratorQuery.docs]) {
      if (!seenIds.contains(doc.id)) {
        seenIds.add(doc.id);
        events.add(Event.fromMap(doc.data() as Map<String, dynamic>, id: doc.id));
      }
    }

    events.sort((a, b) => b.startDateTime.compareTo(a.startDateTime));
    return events;
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

