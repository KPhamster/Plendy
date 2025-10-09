import 'package:flutter/material.dart';
import '../services/experience_service.dart';

/// Utility widget to backfill sharedWithUserIds for existing experiences
/// This is a one-time migration tool that User A can run to fix existing experiences
class BackfillSharedUserIdsButton extends StatefulWidget {
  const BackfillSharedUserIdsButton({super.key});

  @override
  State<BackfillSharedUserIdsButton> createState() => _BackfillSharedUserIdsButtonState();
}

class _BackfillSharedUserIdsButtonState extends State<BackfillSharedUserIdsButton> {
  final ExperienceService _experienceService = ExperienceService();
  bool _isProcessing = false;
  String? _result;

  Future<void> _runBackfill() async {
    setState(() {
      _isProcessing = true;
      _result = null;
    });

    try {
      final count = await _experienceService.backfillSharedUserIdsForExperiences();
      
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _result = 'Successfully updated $count experience(s)';
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backfill complete! Updated $count experiences'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _result = 'Error: $e';
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error during backfill: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Shared Category Fix',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'If you\'ve shared categories with others, run this one-time migration to ensure they can see all your experiences in those categories.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _runBackfill,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.sync),
              label: Text(_isProcessing ? 'Processing...' : 'Backfill Shared Experiences'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
            if (_result != null) ...[
              const SizedBox(height: 12),
              Text(
                _result!,
                style: TextStyle(
                  color: _result!.startsWith('Error') ? Colors.red : Colors.green,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

