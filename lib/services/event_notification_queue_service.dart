import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/event.dart';

/// Handles enqueueing event reminder notifications for attendees.
class EventNotificationQueueService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Queue reminder notifications for all attendees of [event].
  ///
  /// This writes/updates per-user documents in the `event_notification_queue`
  /// collection so Cloud Functions can deliver push notifications when the
  /// reminder window is reached.
  Future<void> queueEventNotifications(Event event) async {
    if (event.id.isEmpty) return;

    final attendees = <String>{
      event.plannerUserId,
      ...event.collaboratorIds,
      ...event.invitedUserIds,
    }..removeWhere((id) => id.isEmpty);

    if (attendees.isEmpty) return;

    // Determine when the reminder should be delivered.
    final Duration leadTime = event.notificationPreference.effectiveDuration;
    DateTime sendAt = event.startDateTime.subtract(leadTime);

    final DateTime now = DateTime.now();
    if (sendAt.isBefore(now)) {
      // If the reminder window is already in the past, fire immediately.
      sendAt = now.add(const Duration(seconds: 5));
    }

    final Timestamp sendAtTimestamp = Timestamp.fromDate(sendAt);
    final Timestamp startTimestamp = Timestamp.fromDate(event.startDateTime);

    final batch = _firestore.batch();

    for (final userId in attendees) {
      final docRef = _firestore
          .collection('event_notification_queue')
          .doc('${event.id}_$userId');

      batch.set(docRef, {
        'eventId': event.id,
        'userId': userId,
        'eventTitle': event.title,
        'eventStartTime': startTimestamp,
        'sendAt': sendAtTimestamp,
        'notificationType': event.notificationPreference.type.name,
        'customDurationMs':
            event.notificationPreference.customDuration?.inMilliseconds,
        'status': 'pending',
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }
}
