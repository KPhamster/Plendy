import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import '../models/experience.dart';

class ExperiencePageScreen extends StatelessWidget {
  final Experience experience;

  const ExperiencePageScreen({super.key, required this.experience});

  // Helper method to build the header section
  Widget _buildHeader(BuildContext context, Experience experience) {
    // Determine header height (adjust as needed)
    const double headerHeight = 320.0;

    return Container(
      height: headerHeight,
      child: Stack(
        children: [
          // 1. Background Image
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                image: experience.location.photoUrl != null
                    ? DecorationImage(
                        image: NetworkImage(experience.location.photoUrl!),
                        fit: BoxFit.cover,
                      )
                    : null, // No background image if URL is null
                color: experience.location.photoUrl == null
                    ? Colors.grey[400] // Placeholder color if no image
                    : null,
              ),
              // Basic placeholder if no image URL
              child: experience.location.photoUrl == null
                  ? Center(
                      child: Icon(
                      Icons.image_not_supported,
                      color: Colors.white70,
                      size: 50,
                    ))
                  : null,
            ),
          ),

          // 2. Dark Overlay for text visibility
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withOpacity(0.6),
                    Colors.black.withOpacity(0.2),
                    Colors.transparent
                  ],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
            ),
          ),

          // 3. Content (Positioned to add padding)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                // Outer column to stack the top row and buttons
                crossAxisAlignment:
                    CrossAxisAlignment.start, // Align buttons left potentially
                children: [
                  Row(
                      // Main row for Icon + Name/Rating - REMOVED ICON
                      crossAxisAlignment: CrossAxisAlignment
                          .center, // Align items vertically center
                      children: [
                        // REMOVED CircleAvatar
                        // const SizedBox(width: 16), // REMOVED Spacing

                        // Column for Name and Rating
                        Expanded(
                          // Allow text column to take available space
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start, // Align text left
                            mainAxisSize:
                                MainAxisSize.min, // Fit content vertically
                            children: [
                              // Name
                              Text(
                                experience.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      offset: Offset(1.0, 1.0),
                                      blurRadius: 2.0,
                                      color: Colors.black.withOpacity(0.5),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),

                              // Rating
                              Row(
                                children: [
                                  RatingBarIndicator(
                                    rating: experience
                                        .plendyRating, // Use Plendy rating
                                    itemBuilder: (context, index) => const Icon(
                                      Icons.star,
                                      color: Colors.amber,
                                    ),
                                    unratedColor: Colors.white.withOpacity(0.4),
                                    itemCount: 5,
                                    itemSize: 24.0,
                                    direction: Axis.horizontal,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${experience.plendyReviewCount} ratings',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                      color: Colors.white,
                                      shadows: [
                                        Shadow(
                                          offset: Offset(1.0, 1.0),
                                          blurRadius: 2.0,
                                          color: Colors.black.withOpacity(0.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ]),
                  const SizedBox(height: 16), // Spacing below the top row

                  // Action Buttons (Centered)
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.center, // Center the buttons
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
                          minimumSize:
                              Size(140, 36), // Give buttons some minimum width
                        ),
                      ),
                      const SizedBox(width: 16), // Space between buttons
                      ElevatedButton.icon(
                        onPressed: () {
                          // TODO: Implement Add to Itinerary logic
                          print('Add to Itinerary button pressed');
                        },
                        icon: const Icon(
                            Icons.calendar_today_outlined), // Itinerary icon
                        label: const Text('Add to Itinerary'),
                        style: ElevatedButton.styleFrom(
                          // Optional: Add styling if needed (e.g., minimumSize)
                          minimumSize:
                              Size(140, 36), // Give buttons some minimum width
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 4. Back Button (Positioned top-left)
          Positioned(
            top: MediaQuery.of(context)
                .padding
                .top, // Consider status bar height
            left: 8.0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              margin: const EdgeInsets.all(4.0), // Margin around the circle
              child: BackButton(
                color: Colors.white, // Make sure back button is visible
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // REMOVED AppBar
      // appBar: AppBar(...)
      body: SingleChildScrollView(
        // Use SingleChildScrollView to prevent overflow
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
