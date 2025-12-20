import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen for user data deletion instructions (required by Facebook App Review)
/// 
/// This screen provides clear instructions on how users can request deletion
/// of their data from Plendy, as required by Facebook/Meta for app permissions.
class DataDeletionScreen extends StatelessWidget {
  const DataDeletionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delete My Data'),
        backgroundColor: const Color(0xFFD40000),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const Icon(
              Icons.privacy_tip,
              size: 64,
              color: Color(0xFFD40000),
            ),
            const SizedBox(height: 24),
            
            Text(
              'Your Privacy Matters',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            Text(
              'You have the right to request deletion of your personal data from Plendy at any time.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 24),
            
            // What gets deleted section
            Text(
              'What Gets Deleted',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            _buildBulletPoint(context, 'Your Plendy account and profile'),
            _buildBulletPoint(context, 'All experiences and places you\'ve saved'),
            _buildBulletPoint(context, 'Your reviews and comments'),
            _buildBulletPoint(context, 'Uploaded photos and media'),
            _buildBulletPoint(context, 'Personal preferences and settings'),
            _buildBulletPoint(context, 'Authentication data (email, password hash)'),
            
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),
            
            // How to request deletion
            Text(
              'How to Request Deletion',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            Text(
              'Choose one of the following methods:',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            
            // Method 1: In-app deletion
            _buildDeletionMethod(
              context,
              icon: Icons.phone_android,
              title: 'Method 1: Delete from App',
              steps: [
                'Open the Plendy app',
                'Go to Profile → Settings',
                'Tap "Delete Account"',
                'Confirm deletion',
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Method 2: Email request
            _buildDeletionMethod(
              context,
              icon: Icons.email,
              title: 'Method 2: Email Request',
              steps: [
                'Send an email to: admin@plendy.app',
                'Subject: "Delete My Plendy Account"',
                'Include your registered email address',
                'We\'ll process within 30 days',
              ],
              actionButton: _buildEmailButton(context),
            ),
            
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 24),
            
            // Timeline
            Text(
              'Deletion Timeline',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            _buildTimelineItem(
              context,
              '1. Request Received',
              'We confirm receipt of your deletion request',
            ),
            _buildTimelineItem(
              context,
              '2. Processing (1-7 days)',
              'Account deactivated and deletion queued',
            ),
            _buildTimelineItem(
              context,
              '3. Complete (within 30 days)',
              'All personal data permanently deleted',
            ),
            
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 24),
            
            // Contact info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.help_outline, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(
                        'Questions?',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[900],
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Contact us at admin@plendy.app for any questions about data deletion or privacy.',
                    style: TextStyle(color: Colors.blue[900]),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildBulletPoint(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, size: 20, color: Colors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeletionMethod(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<String> steps,
    Widget? actionButton,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFFD40000)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...steps.asMap().entries.map((entry) {
            final index = entry.key;
            final step = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD40000),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(step),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (actionButton != null) ...[
            const SizedBox(height: 16),
            actionButton,
          ],
        ],
      ),
    );
  }

  Widget _buildEmailButton(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () async {
        final email = 'admin@plendy.app';
        final subject = 'Delete My Plendy Account';
        final body = 'Please delete my Plendy account and all associated data.\n\n'
            'My registered email: [ENTER YOUR EMAIL HERE]';
        
        final uri = Uri(
          scheme: 'mailto',
          path: email,
          query: 'subject=$subject&body=${Uri.encodeComponent(body)}',
        );
        
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        } else {
          // Fallback: Copy email to clipboard
          await Clipboard.setData(ClipboardData(text: email));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Email address copied to clipboard'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      },
      icon: const Icon(Icons.email),
      label: const Text('Send Email Request'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFD40000),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    );
  }

  Widget _buildTimelineItem(
    BuildContext context,
    String title,
    String description,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20, left: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFD40000).withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFD40000),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.timeline,
              color: Color(0xFFD40000),
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
