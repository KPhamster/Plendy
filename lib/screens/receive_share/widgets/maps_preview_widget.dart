import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math'; // For min function in API key logging if needed

import '../../../models/experience.dart';
import '../../receive_share_screen.dart'; // Assuming ExperienceCardData might be needed later
import '../../../services/google_maps_service.dart';

class MapsPreviewWidget extends StatefulWidget {
  final String mapsUrl;
  // Using the existing futures map for now, might rename later
  final Map<String, Future<Map<String, dynamic>?>> mapsPreviewFutures;
  final Future<Map<String, dynamic>?> Function(String) getLocationFromMapsUrl;
  final Future<void> Function(String) launchUrlCallback;
  final GoogleMapsService mapsService;

  const MapsPreviewWidget({
    super.key,
    required this.mapsUrl,
    required this.mapsPreviewFutures,
    required this.getLocationFromMapsUrl,
    required this.launchUrlCallback,
    required this.mapsService,
  });

  @override
  State<MapsPreviewWidget> createState() => _MapsPreviewWidgetState();
}

class _MapsPreviewWidgetState extends State<MapsPreviewWidget> {
  @override
  Widget build(BuildContext context) {
    // Create a stable key for the FutureBuilder to prevent unnecessary rebuilds
    final String urlKey =
        widget.mapsUrl.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

    // Try to extract location name from URL for fallback display
    String fallbackPlaceName = _extractLocationNameFromMapsUrl(widget.mapsUrl);

    print(
        "🗺️ MAPS PREVIEW WIDGET: Starting preview generation for URL: ${widget.mapsUrl}");
    print(
        "🗺️ MAPS PREVIEW WIDGET: Extracted fallback place name: $fallbackPlaceName");

    // Get or create the future - prevents reloading when the experience card is expanded/collapsed
    if (!widget.mapsPreviewFutures.containsKey(widget.mapsUrl)) {
      print(
          "🗺️ MAPS PREVIEW WIDGET: Creating new future for URL: ${widget.mapsUrl}");
      widget.mapsPreviewFutures[widget.mapsUrl] =
          widget.getLocationFromMapsUrl(widget.mapsUrl);
    } else {
      print(
          "🗺️ MAPS PREVIEW WIDGET: Using cached future for URL: ${widget.mapsUrl}");
    }

    return FutureBuilder<Map<String, dynamic>?>(
      key: ValueKey('maps_preview_$urlKey'),
      future: widget.mapsPreviewFutures[widget.mapsUrl],
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          print("🗺️ MAPS PREVIEW WIDGET: Loading state - waiting for data");
          return _buildMapsLoadingPreview();
        }

        // If we have data, build the complete preview
        if (snapshot.hasData && snapshot.data != null) {
          final data = snapshot.data!;
          // Ensure location data is correctly cast
          if (data['location'] is Location) {
            final location = data['location'] as Location;
            final placeName = data['placeName'] as String? ??
                'Shared Location'; // Handle null placeName
            final mapsUrl = data['mapsUrl'] as String? ??
                widget.mapsUrl; // Handle null mapsUrl
            final website = data['website'] as String? ?? '';

            print(
                "🗺️ MAPS PREVIEW WIDGET: Success! Building detailed preview");
            print("🗺️ MAPS PREVIEW WIDGET: Place name: $placeName");
            print(
                "🗺️ MAPS PREVIEW WIDGET: Location data: lat=${location.latitude}, lng=${location.longitude}");
            print("🗺️ MAPS PREVIEW WIDGET: Address: ${location.address}");
            print("🗺️ MAPS PREVIEW WIDGET: Website URL: $website");

            return _buildMapsDetailedPreview(location, placeName, mapsUrl,
                websiteUrl: website);
          } else {
            print(
                "🗺️ MAPS PREVIEW WIDGET ERROR: Invalid location data format in snapshot.");
            print(
                "🗺️ MAPS PREVIEW WIDGET: Using fallback preview due to data error.");
            return _buildMapsFallbackPreview(widget.mapsUrl, fallbackPlaceName);
          }
        }

        // If snapshot has error, log it
        if (snapshot.hasError) {
          print("🗺️ MAPS PREVIEW WIDGET ERROR: ${snapshot.error}");
          print("🗺️ MAPS PREVIEW WIDGET: Using fallback preview due to error");
        } else if (!snapshot.hasData || snapshot.data == null) {
          print(
              "🗺️ MAPS PREVIEW WIDGET: No data received (snapshot.data is null), using fallback preview");
        } else {
          print(
              "🗺️ MAPS PREVIEW WIDGET: Unknown state, using fallback preview");
        }

        // If we have an error or no data, build a fallback preview
        return _buildMapsFallbackPreview(widget.mapsUrl, fallbackPlaceName);
      },
    );
  }

  // <<< START HELPER METHODS >>>

  // Extract a location name from a Google Maps URL
  String _extractLocationNameFromMapsUrl(String url) {
    try {
      String locationName = "Shared Location";

      // Try to extract a place name from query parameter
      final Uri uri = Uri.parse(url);
      final queryParams = uri.queryParameters;

      if (queryParams.containsKey('q')) {
        final query = queryParams['q']!;
        if (query.isNotEmpty && !_containsOnlyCoordinates(query)) {
          locationName = query;
        }
      }

      return locationName;
    } catch (e) {
      return "Shared Location";
    }
  }

  // Check if a string contains only coordinates
  bool _containsOnlyCoordinates(String text) {
    // Pattern for latitude,longitude format
    RegExp coordPattern = RegExp(r'^-?\\d+\\.\\d+,-?\\d+\\.\\d+\$');
    return coordPattern.hasMatch(text);
  }

  // Loading state for Maps preview
  Widget _buildMapsLoadingPreview() {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        height: 350,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.blue),
            SizedBox(height: 16),
            Text(
              'Loading location details...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Detailed preview when we have location data for Maps
  Widget _buildMapsDetailedPreview(
      Location location, String placeName, String mapsUrl,
      {String? websiteUrl}) {
    print('🗺️ PREVIEW WIDGET: Building detailed Maps preview');
    print('🗺️ PREVIEW WIDGET: Place name: "$placeName"');
    print(
        '🗺️ PREVIEW WIDGET: Location - lat: ${location.latitude}, lng: ${location.longitude}');
    print('🗺️ PREVIEW WIDGET: Address: ${location.address}');
    print('🗺️ PREVIEW WIDGET: Maps URL: $mapsUrl');
    print('🗺️ PREVIEW WIDGET: Website URL: ${websiteUrl ?? "Not available"}');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Preview container with tap functionality
        InkWell(
          onTap: () => widget.launchUrlCallback(mapsUrl), // Use callback
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Photo or map preview
                SizedBox(
                  height: 180,
                  width: double.infinity,
                  child: ClipRRect(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Use actual photo if available, otherwise fall back to static map
                        if (location.photoUrl != null &&
                            location.photoUrl!.isNotEmpty)
                          Image.network(
                            location.photoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              print('Error loading photo: $error');
                              return _getLocationMapImage(location);
                            },
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                color: Colors.grey[200],
                                child: Center(
                                  child: CircularProgressIndicator(
                                    value: loadingProgress.expectedTotalBytes !=
                                            null
                                        ? loadingProgress
                                                .cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!
                                        : null,
                                  ),
                                ),
                              );
                            },
                          )
                        else
                          _getLocationMapImage(location),
                        // Gradient overlay
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.3),
                                  ],
                                  stops: [
                                    0.7,
                                    1.0
                                  ] // Adjust stops for desired effect
                                  ),
                            ),
                          ),
                        ),
                        // Google Maps branding overlay in top-right corner
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(4),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 2,
                                    offset: Offset(0, 1),
                                  )
                                ]),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.map_outlined,
                                    color: Colors.blue[700],
                                    size: 14), // Use outlined map icon
                                SizedBox(width: 4),
                                Text(
                                  'Google Maps',
                                  style: TextStyle(
                                    color: Colors.grey[800],
                                    fontWeight:
                                        FontWeight.w500, // Slightly bolder
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Location details
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Place name (no icon needed here, redundant with overlay)
                      Text(
                        location.displayName ?? placeName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 8),

                      // Address
                      if (location.address != null) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.location_on,
                                size: 16, color: Colors.grey[600]),
                            SizedBox(width: 6),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  print(
                                      '🧭 ADDRESS WIDGET: Opening map for ${location.latitude}, ${location.longitude}');
                                  // Open map to show location with higher zoom level
                                  final String mapUrl;
                                  if (location.placeId != null &&
                                      location.placeId!.isNotEmpty) {
                                    // Use the Google Maps search API with place_id format
                                    mapUrl =
                                        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(location.displayName ?? placeName)}&query_place_id=${location.placeId}';
                                    print(
                                        '🧭 ADDRESS WIDGET: Opening URL with placeId: $mapUrl');
                                  } else {
                                    // Fallback to coordinate-based URL
                                    mapUrl =
                                        'https://www.google.com/maps/search/?api=1&query=${location.latitude},${location.longitude}';
                                    print(
                                        '🧭 ADDRESS WIDGET: Opening URL with coordinates: $mapUrl');
                                  }
                                  await widget.launchUrlCallback(
                                      mapUrl); // Use callback
                                },
                                child: Text(
                                  location.address!,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[800],
                                    decoration: TextDecoration
                                        .underline, // Make address look clickable
                                    decorationColor: Colors.blue,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12), // Add space before button
                      ],

                      // Directions Button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: Icon(Icons.directions, size: 18),
                          label: Text('Get Directions'),
                          onPressed: () async {
                            print(
                                '🧭 DIRECTIONS WIDGET: Getting directions for ${location.latitude}, ${location.longitude}');
                            // Pass the full location object
                            final url =
                                widget.mapsService.getDirectionsUrl(location);
                            print('🧭 DIRECTIONS WIDGET: Opening URL: $url');
                            await widget.launchUrlCallback(url); // Use callback
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                Colors.blue, // Keep blue color for directions
                            side: BorderSide(
                                color: Colors.blue.shade200), // Lighter border
                            padding: EdgeInsets.symmetric(
                                vertical: 10), // Adjust padding
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Widget to display a static map image or Places API image
  Widget _getLocationMapImage(Location location) {
    print(
        '🗺️ MAP IMAGE WIDGET: Getting map image for coordinates: ${location.latitude}, ${location.longitude}');
    print(
        '🗺️ MAP IMAGE WIDGET: Location display name: ${location.displayName ?? "Not available"}');

    // Check if placeId is valid before attempting Places API call
    if (location.placeId != null && location.placeId!.isNotEmpty) {
      print(
          '🗺️ MAP IMAGE WIDGET: Valid placeId found (${location.placeId}), attempting Places API image fetch.');
      // Use getPlaceImageUrl from the injected service
      return FutureBuilder<String?>(
        future: widget.mapsService.getPlaceImageUrl(
            location.placeId!), // Non-null assertion is safe here
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // Show loading only if we are actually fetching a place image
            return Container(
              color: Colors.grey[200],
              child: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasData &&
              snapshot.data != null &&
              snapshot.data!.isNotEmpty) {
            final imageUrl = snapshot.data!;
            print(
                '🗺️ MAP IMAGE WIDGET: Places API returned image URL: $imageUrl');

            return Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                print(
                    '🗺️ MAP IMAGE WIDGET ERROR: Could not load place image: $error');
                // Fall back to static map on error
                return _getStaticMapImage(location);
              },
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  color: Colors.grey[200],
                  child: Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  ),
                );
              },
            );
          } else {
            // Fall back to static map if no place image found via API
            print(
                '🗺️ MAP IMAGE WIDGET: No place image found via Places API, using static map fallback');
            return _getStaticMapImage(location);
          }
        },
      );
    } else {
      // Fall back to static map if no placeId
      print(
          '🗺️ MAP IMAGE WIDGET: No placeId available, using static map directly.');
      return _getStaticMapImage(location);
    }
  }

  // Helper to get a static map image (fallback)
  Widget _getStaticMapImage(Location location) {
    // Get API key via the injected service
    final apiKey = GoogleMapsService
        .apiKey; // Assuming static access is okay here, or pass service instance if needed

    // Construct the URL for Static Maps API
    final mapUrl = 'https://maps.googleapis.com/maps/api/staticmap'
        '?center=${location.latitude},${location.longitude}'
        '&zoom=15' // Adjust zoom level as needed
        '&size=600x300' // Adjust size as needed
        '&markers=color:red%7C${location.latitude},${location.longitude}'
        '&key=$apiKey';

    // Debug: Print the full map URL (masking API key)
    print(
        '🗺️ STATIC MAP WIDGET: Using map URL: ${mapUrl.replaceAll(apiKey, "API_KEY_HIDDEN")}');

    return Image.network(
      mapUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        print('🗺️ STATIC MAP WIDGET ERROR: Could not load map image: $error');
        // Fallback display if static map fails
        return Container(
          color: Colors.grey[300],
          child: Center(
            child: Icon(Icons.map_outlined,
                size: 64, color: Colors.blue), // Use outlined icon
          ),
        );
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: Colors.grey[200],
          child: Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
    );
  }

  // Fallback preview when we don't have location data
  Widget _buildMapsFallbackPreview(String url, String placeName) {
    print('🗺️ FALLBACK WIDGET: Building fallback preview for URL: $url');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Fallback container with Maps styling
        InkWell(
          onTap: () => widget.launchUrlCallback(url), // Use callback
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            height: 250, // Give fallback a defined height
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white, // Use white background
            ),
            child: Padding(
              // Add padding for content
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Google Maps Logo Icon
                  Icon(Icons.map_outlined,
                      size: 60, color: Colors.blue[700]), // Use outlined icon
                  SizedBox(height: 16),

                  // Place Name
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      'Failed to load location details. Try refreshing.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18, // Slightly smaller font
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(height: 8),

                  // Maps URL (truncated)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      url.length > 40
                          ? '${url.substring(0, 40)}...'
                          : url, // Show more of URL
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ),
                  SizedBox(height: 16), // Reduced spacing

                  // Small helper text
                  Text(
                    'Tap to view on Google Maps',
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: 8), // Consistent spacing below
      ],
    );
  }
  // <<< END HELPER METHODS >>>
}
