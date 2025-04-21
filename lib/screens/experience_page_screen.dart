import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import '../models/experience.dart';

class ExperiencePageScreen extends StatelessWidget {
  final Experience experience;

  const ExperiencePageScreen({super.key, required this.experience});

  // Helper method to build the header section
  Widget _buildHeader(BuildContext context, Experience experience) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        // Outer column to stack the top row and buttons
        crossAxisAlignment:
            CrossAxisAlignment.start, // Align buttons left potentially
        children: [
          Row(
            // Main row for Icon + Name/Rating
            crossAxisAlignment:
                CrossAxisAlignment.center, // Align items vertically center
            children: [
              // Icon (Location Photo)
              CircleAvatar(
                radius: 40,
                backgroundImage: experience.location.photoUrl != null
                    ? NetworkImage(experience.location.photoUrl!)
                    : null, // Use NetworkImage
                // Placeholder/Error handling for the image
                child: experience.location.photoUrl == null
                    ? const Icon(Icons.location_pin,
                        size: 40) // Placeholder icon
                    : null,
              ),
              const SizedBox(width: 16), // Spacing between icon and text column

              // Column for Name and Rating
              Expanded(
                // Allow text column to take available space
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start, // Align text left
                  mainAxisSize: MainAxisSize.min, // Fit content vertically
                  children: [
                    // Name
                    Text(
                      experience.name,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                      // textAlign: TextAlign.center, // Removed, align left now
                    ),
                    const SizedBox(height: 4),

                    // Rating
                    Row(
                      // mainAxisAlignment: MainAxisAlignment.center, // Removed, align left now
                      children: [
                        RatingBarIndicator(
                          rating: experience.plendyRating, // Use Plendy rating
                          itemBuilder: (context, index) => const Icon(
                            Icons.star,
                            color: Colors.amber,
                          ),
                          itemCount: 5,
                          itemSize: 18.0, // Slightly smaller stars
                          direction: Axis.horizontal,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${experience.plendyReviewCount} ratings',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16), // Spacing below the top row

          // Action Buttons (Centered)
          Row(
            mainAxisAlignment: MainAxisAlignment.center, // Center the buttons
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  // TODO: Implement Follow logic
                  print('Follow button pressed');
                },
                icon: const Icon(Icons.add),
                label: const Text('Follow'),
                style: ElevatedButton.styleFrom(
                  // Optional: Add styling if needed (e.g., minimumSize)
                  minimumSize: Size(140, 36), // Give buttons some minimum width
                ),
              ),
              const SizedBox(width: 16), // Space between buttons
              ElevatedButton.icon(
                onPressed: () {
                  // TODO: Implement Add to Itinerary logic
                  print('Add to Itinerary button pressed');
                },
                icon:
                    const Icon(Icons.calendar_today_outlined), // Itinerary icon
                label: const Text('Add to Itinerary'),
                style: ElevatedButton.styleFrom(
                  // Optional: Add styling if needed (e.g., minimumSize)
                  minimumSize: Size(140, 36), // Give buttons some minimum width
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Keep a basic AppBar for the back button and title consistency for now
        // Title can be empty if we want the header name to be primary
        title: null, // Remove the title text
        backgroundColor:
            Colors.transparent, // Make AppBar transparent if needed
        elevation: 0, // Remove shadow if needed
        leading: BackButton(color: Colors.black),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, experience),
            const Divider(),
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('// TODO: Add Details, Quick Actions, Tabs...'),
            )
          ],
        ),
      ),
    );
  }
}
