import 'package:flutter/material.dart';

import 'package:plendy/widgets/tutorial_save_content_modal.dart';

class TutorialsScreen extends StatelessWidget {
  const TutorialsScreen({super.key});

  static const List<_Tutorial> _tutorials = [
    _Tutorial(
      title: 'Save content and experiences',
      description:
          'You can save content by tapping the + button in the Collections tab or by sharing content you find on other apps to Plendy.',
      icon: Icons.add_circle_outline,
    ),
    _Tutorial(
      title: 'Share an experience',
      description:
          'Tap the share button on any experience or content to share them with your friends!',
      icon: Icons.share_outlined,
    ),
    _Tutorial(
      title: 'Organize collections',
      description:
          'Use Collections to group experiences by trip, event, or theme so they are easy to revisit.',
      icon: Icons.collections_bookmark_outlined,
    ),
    _Tutorial(
      title: 'Invite your friends',
      description:
          'Open My People to send invites or accept requests so you can start sharing together.',
      icon: Icons.people_outline,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: const Text('Tutorials'),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _tutorials.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final tutorial = _tutorials[index];
          return Card(
            elevation: 0,
            color: Colors.grey[50],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey[300]!),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                child: Icon(tutorial.icon),
              ),
              title: Text(
                tutorial.title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(tutorial.description),
              onTap: index == 0
                  ? () => showTutorialSaveContentModal(context)
                  : null,
            ),
          );
        },
      ),
    );
  }
}

class _Tutorial {
  final String title;
  final String description;
  final IconData icon;

  const _Tutorial({
    required this.title,
    required this.description,
    required this.icon,
  });
}
