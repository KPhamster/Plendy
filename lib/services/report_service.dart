import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/report.dart';

/// Service for managing Report-related operations
class ReportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _reportsCollection =>
      _firestore.collection('reports');

  /// Submit a new report
  Future<String> submitReport(Report report) async {
    try {
      final docRef = await _reportsCollection.add(report.toMap());
      debugPrint('ReportService: Report submitted successfully: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('ReportService: Failed to submit report: $e');
      rethrow;
    }
  }

  /// Check if a user has already reported this specific content recently
  /// Returns the existing report if found, null otherwise
  Future<Report?> findExistingReport({
    required String userId,
    required String experienceId,
    required String previewURL,
    Duration withinDuration = const Duration(days: 30),
  }) async {
    try {
      final cutoffDate =
          DateTime.now().subtract(withinDuration);
      
      final querySnapshot = await _reportsCollection
          .where('userId', isEqualTo: userId)
          .where('experienceId', isEqualTo: experienceId)
          .where('previewURL', isEqualTo: previewURL)
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(cutoffDate))
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return null;
      }

      return Report.fromFirestore(
        querySnapshot.docs.first as DocumentSnapshot<Map<String, dynamic>>,
      );
    } catch (e) {
      debugPrint('ReportService: Error checking for existing report: $e');
      return null;
    }
  }

  /// Get all reports submitted by a specific user
  Future<List<Report>> getUserReports(String userId) async {
    try {
      final querySnapshot = await _reportsCollection
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) =>
              Report.fromFirestore(doc as DocumentSnapshot<Map<String, dynamic>>))
          .toList();
    } catch (e) {
      debugPrint('ReportService: Failed to fetch user reports: $e');
      return [];
    }
  }

  /// Get pending reports (admin function)
  Future<List<Report>> getPendingReports({int limit = 50}) async {
    try {
      final querySnapshot = await _reportsCollection
          .where('status', isEqualTo: Report.statusPending)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return querySnapshot.docs
          .map((doc) =>
              Report.fromFirestore(doc as DocumentSnapshot<Map<String, dynamic>>))
          .toList();
    } catch (e) {
      debugPrint('ReportService: Failed to fetch pending reports: $e');
      return [];
    }
  }

  /// Update report status (admin function)
  Future<void> updateReportStatus({
    required String reportId,
    required String status,
    String? reviewedBy,
    String? reviewNotes,
  }) async {
    try {
      final updates = <String, dynamic>{
        'status': status,
        'reviewedAt': Timestamp.now(),
      };

      if (reviewedBy != null) {
        updates['reviewedBy'] = reviewedBy;
      }

      if (reviewNotes != null) {
        updates['reviewNotes'] = reviewNotes;
      }

      await _reportsCollection.doc(reportId).update(updates);
      debugPrint('ReportService: Report $reportId updated to status: $status');
    } catch (e) {
      debugPrint('ReportService: Failed to update report status: $e');
      rethrow;
    }
  }

  /// Delete a report (admin function)
  Future<void> deleteReport(String reportId) async {
    try {
      await _reportsCollection.doc(reportId).delete();
      debugPrint('ReportService: Report $reportId deleted');
    } catch (e) {
      debugPrint('ReportService: Failed to delete report: $e');
      rethrow;
    }
  }

  /// Get reports for a specific experience (admin function)
  Future<List<Report>> getReportsForExperience(String experienceId) async {
    try {
      final querySnapshot = await _reportsCollection
          .where('experienceId', isEqualTo: experienceId)
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) =>
              Report.fromFirestore(doc as DocumentSnapshot<Map<String, dynamic>>))
          .toList();
    } catch (e) {
      debugPrint(
          'ReportService: Failed to fetch reports for experience: $e');
      return [];
    }
  }

  /// Get reports by a specific reported user (admin function)
  Future<List<Report>> getReportsByReportedUser(String reportedUserId) async {
    try {
      final querySnapshot = await _reportsCollection
          .where('reportedUserId', isEqualTo: reportedUserId)
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) =>
              Report.fromFirestore(doc as DocumentSnapshot<Map<String, dynamic>>))
          .toList();
    } catch (e) {
      debugPrint(
          'ReportService: Failed to fetch reports by reported user: $e');
      return [];
    }
  }
}

