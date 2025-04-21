import 'package:flutter/material.dart';
import '../models/experience.dart';

class ExperiencePageScreen extends StatelessWidget {
  final Experience experience;

  const ExperiencePageScreen({super.key, required this.experience});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(experience.name),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Experience Details', // Placeholder title
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Text('Description: ${experience.description}'),
            const SizedBox(height: 8),
            Text('Category: ${experience.category}'),
            const SizedBox(height: 8),
            if (experience.location.displayName != null)
              Text('Location: ${experience.location.displayName}'),
            // Add more details as needed
          ],
        ),
      ),
    );
  }
}
