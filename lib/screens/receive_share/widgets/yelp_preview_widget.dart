import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../../models/experience.dart';
import '../../receive_share_screen.dart'; // Corrected path
import '../../../services/google_maps_service.dart';

class YelpPreviewWidget extends StatefulWidget {
  final String yelpUrl;
  final ExperienceCardData card;
  final Map<String, Future<Map<String, dynamic>?>> yelpPreviewFutures;
  final Future<Map<String, dynamic>?> Function(String) getBusinessFromYelpUrl;
  final Future<void> Function(String) launchUrlCallback;
  final GoogleMapsService mapsService;

  const YelpPreviewWidget({
    super.key,
    required this.yelpUrl,
    required this.card,
    required this.yelpPreviewFutures,
    required this.getBusinessFromYelpUrl,
    required this.launchUrlCallback,
    required this.mapsService,
  });

  @override
  State<YelpPreviewWidget> createState() => _YelpPreviewWidgetState();
}

class _YelpPreviewWidgetState extends State<YelpPreviewWidget> {
  // Build a preview widget for a Yelp URL
  @override
  Widget build(BuildContext context) {
    // Determine the primary key for this preview: use placeId if available, else the original URL
    final String previewKey = widget.card.placeIdForPreview ?? widget.yelpUrl;
    // Create a stable key for the FutureBuilder based on the determined preview key
    final String futureBuilderKey =
        previewKey.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

    // Try to extract business name from URL for fallback display
    String fallbackBusinessName =
        _extractBusinessNameFromYelpUrl(widget.yelpUrl);

    print(
        "🔍 YELP PREVIEW WIDGET: Starting preview generation for URL: ${widget.yelpUrl}");
    print(
        "🔍 YELP PREVIEW WIDGET: Using preview key (placeId or URL): $previewKey");
    print(
        "🔍 YELP PREVIEW WIDGET: Extracted fallback business name: $fallbackBusinessName");

    // Get or create the future using the previewKey
    if (!widget.yelpPreviewFutures.containsKey(previewKey)) {
      print("🔍 YELP PREVIEW WIDGET: Creating new future for key: $previewKey");
      // If the key is the original URL (meaning placeId is not set yet),
      // fetch using the URL. If the key IS a placeId, we assume the future
      // was already populated by _showLocationPicker and log a warning if not.
      if (previewKey == widget.yelpUrl) {
        widget.yelpPreviewFutures[previewKey] =
            widget.getBusinessFromYelpUrl(widget.yelpUrl);
      } else {
        // This case should ideally not happen if _showLocationPicker updated the future map correctly
        print(
            "🔍 YELP PREVIEW WIDGET WARNING: Future not found for placeId key '$previewKey'. Re-fetching using original URL '${widget.yelpUrl}'.");
        widget.yelpPreviewFutures[previewKey] =
            widget.getBusinessFromYelpUrl(widget.yelpUrl);
      }
    } else {
      print("🔍 YELP PREVIEW WIDGET: Using cached future for key: $previewKey");
    }

    return FutureBuilder<Map<String, dynamic>?>(
      // Use the dynamic key based on placeId or URL
      key: ValueKey('yelp_preview_$futureBuilderKey'),
      // Access the future using the dynamic key
      future: widget.yelpPreviewFutures[previewKey],
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          print("🔍 YELP PREVIEW WIDGET: Loading state - waiting for data");
          return _buildYelpLoadingPreview();
        }

        // If we have data, build the complete preview
        if (snapshot.data != null) {
          final data = snapshot.data!;
          final location = data['location'] as Location;
          final businessName = data['businessName'] as String;
          final yelpUrl = data['yelpUrl'] as String;

          print("🔍 YELP PREVIEW WIDGET: Success! Building detailed preview");
          print("🔍 YELP PREVIEW WIDGET: Business name: $businessName");
          print(
              "🔍 YELP PREVIEW WIDGET: Location data: lat=${location.latitude}, lng=${location.longitude}");
          print("🔍 YELP PREVIEW WIDGET: Address: ${location.address}");

          return _buildYelpDetailedPreview(location, businessName, yelpUrl);
        }

        // If snapshot has error, log it
        if (snapshot.hasError) {
          print("🔍 YELP PREVIEW WIDGET ERROR: ${snapshot.error}");
          print("🔍 YELP PREVIEW WIDGET: Using fallback preview due to error");
        } else {
          print(
              "🔍 YELP PREVIEW WIDGET: No data received, using fallback preview");
        }

        // If we have an error or no data, build a fallback preview
        return _buildYelpFallbackPreview(widget.yelpUrl, fallbackBusinessName);
      },
    );
  }

  // <<< START METHOD DEFINITIONS >>>
  // Extract a readable business name from a Yelp URL
  String _extractBusinessNameFromYelpUrl(String url) {
    try {
      String businessName = "Yelp Business";

      // For standard Yelp URLs with business name in the path
      if (url.contains('/biz/')) {
        // Extract the business part from URL (e.g., https://www.yelp.com/biz/business-name-location)
        final bizPath = url.split('/biz/')[1].split('?')[0];

        // Convert hyphenated business name to spaces and capitalize words
        businessName = bizPath
            .split('-')
            .map((word) => word.isNotEmpty
                ? word[0].toUpperCase() + word.substring(1)
                : '')
            .join(' ');

        // If there's a location suffix at the end (like "restaurant-city"), remove it
        if (businessName.contains('/')) {
          businessName = businessName.split('/')[0];
        }
      }
      // For short URLs, use the code as part of the name
      else if (url.contains('yelp.to/')) {
        final shortCode =
            url.split('yelp.to/').last.split('?')[0].split('/')[0];
        if (shortCode.isNotEmpty) {
          businessName = "Yelp Business ($shortCode)";
        }
      }

      return businessName;
    } catch (e) {
      return "Yelp Business";
    }
  }

  // Loading state for Yelp preview
  Widget _buildYelpLoadingPreview() {
    return SizedBox(
      height: 250,
      width: double.infinity,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFFD32323)),
              SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FaIcon(FontAwesomeIcons.yelp,
                      color: Color(0xFFD32323), size: 18),
                  SizedBox(width: 8),
                  Text('Loading business information...'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Detailed preview when we have location data
  Widget _buildYelpDetailedPreview(
      Location location, String businessName, String yelpUrl) {
    print('🏢 PREVIEW WIDGET: Building detailed Yelp preview');
    print(
        '🏢 PREVIEW WIDGET: Business name (from initial Yelp parse): "$businessName"');
    print(
        '🏢 PREVIEW WIDGET: Location Display Name: "${location.displayName}"');
    print('🏢 PREVIEW WIDGET: Location Address: "${location.address}"');
    print('🏢 PREVIEW WIDGET: Location Website: "${location.website}"');
    print(
        '🏢 PREVIEW WIDGET: Location Coords: ${location.latitude}, ${location.longitude}');
    print('🏢 PREVIEW WIDGET: Location Place ID: ${location.placeId}');
    print('🏢 PREVIEW WIDGET: Yelp URL: $yelpUrl');

    // Determine the final name and address to display in the preview
    final String finalDisplayName = location.displayName ?? businessName;
    final String finalAddress = location.address ?? 'Address not available';

    print('====> ✨ PREVIEW Log: Final Name to display: "$finalDisplayName"');
    print('====> ✨ PREVIEW Log: Final Address to display: "$finalAddress"');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Preview container with tap functionality
        InkWell(
          onTap: () => _openYelpUrl(yelpUrl),
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
                // Business photo instead of map
                Container(
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
                        // Business photo based on location
                        _getBusinessPhotoWidget(location, businessName),

                        // Yelp branding overlay in top-right corner
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Color(0xFFD32323),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FaIcon(FontAwesomeIcons.yelp,
                                    color: Colors.white, size: 12),
                                SizedBox(width: 4),
                                Text(
                                  'Yelp',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
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

                // Business details
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Yelp logo and business name
                      Row(
                        children: [
                          FaIcon(FontAwesomeIcons.yelp,
                              color: Colors.red, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              finalDisplayName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),

                      // Address
                      if (finalAddress != null && finalAddress.isNotEmpty) ...[
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
                                  if (location.placeId != null &&
                                      location.placeId!.isNotEmpty) {
                                    // Use the Google Maps search API with place_id format
                                    final placeUrl =
                                        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(finalDisplayName)}&query_place_id=${location.placeId}';
                                    print(
                                        '🧭 ADDRESS WIDGET: Opening URL with placeId: $placeUrl');
                                    await widget.launchUrlCallback(placeUrl);
                                  } else {
                                    // Fallback to coordinate-based URL with zoom parameter
                                    final zoom = 18;
                                    final url =
                                        'https://www.google.com/maps/search/?api=1&query=${location.latitude},${location.longitude}';
                                    print(
                                        '🧭 ADDRESS WIDGET: Opening URL with coordinates: $url');
                                    await widget.launchUrlCallback(url);
                                  }
                                },
                                child: Text(
                                  finalAddress,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[800],
                                    decoration: TextDecoration.underline,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),

                        // Directions Button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: Icon(Icons.directions, size: 18),
                            label: Text('Get Directions'),
                            onPressed: () async {
                              print(
                                  '🧭 DIRECTIONS WIDGET: Getting directions for ${location.latitude}, ${location.longitude}');
                              // Pass the entire Location object
                              final url =
                                  widget.mapsService.getDirectionsUrl(location);
                              print('🧭 DIRECTIONS WIDGET: Opening URL: $url');
                              await widget.launchUrlCallback(url);
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue,
                              padding: EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                      ],
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

  /// Get a widget displaying a business photo
  Widget _getBusinessPhotoWidget(Location location, String businessName) {
    print('🖼️ PHOTO WIDGET: Getting business photo for "$businessName"');
    print(
        '🖼️ PHOTO WIDGET: Location data - lat: ${location.latitude}, lng: ${location.longitude}');
    print('🖼️ PHOTO WIDGET: Place ID: ${location.placeId ?? "null"}');
    print('🖼️ PHOTO WIDGET: Address: ${location.address ?? "null"}');
    print(
        '🖼️ PHOTO WIDGET: Photo URL from location: ${location.photoUrl ?? "null"}');

    // First check if the location already has a photoUrl (from our updated Location object)
    if (location.photoUrl != null && location.photoUrl!.isNotEmpty) {
      print('🖼️ PHOTO WIDGET: Using photo URL directly from location object');
      return _buildSinglePhoto(location.photoUrl!, businessName);
    }

    // Get the place ID, which should be available in the location object
    final String? placeId = location.placeId;
    if (placeId == null || placeId.isEmpty) {
      print('🖼️ PHOTO WIDGET: No place ID available, using fallback');
      return _buildPhotoFallback(businessName);
    }

    // For diagnostics, check the API key
    final apiKey = GoogleMapsService.apiKey; // Access static key
    print(
        '🖼️ PHOTO WIDGET: API key length: ${apiKey.length} chars, starts with: ${apiKey.substring(0, min(5, apiKey.length))}...');

    // Create a unique photo query using both business name and address
    String photoQuery = businessName;

    // Include address in the query if available
    if (location.address != null && location.address!.isNotEmpty) {
      String streetAddress = location.address!;
      if (streetAddress.contains(',')) {
        streetAddress = streetAddress.substring(0, streetAddress.indexOf(','));
      }
      photoQuery = '$businessName, $streetAddress';
      print(
          '🖼️ PHOTO WIDGET: Enhanced photo query with address: "$photoQuery"');
    }

    // First try to get photos by place ID
    return FutureBuilder<List<String>>(
      future: widget.mapsService.getPlacePhotoReferences(placeId),
      builder: (context, snapshot) {
        // If we have photo URLs, display them
        if (snapshot.hasData &&
            snapshot.data != null &&
            snapshot.data!.isNotEmpty) {
          final List<String> photoUrls = snapshot.data!;
          print(
              '🖼️ PHOTO WIDGET: Got ${photoUrls.length} photos from Places API');

          if (photoUrls.length > 1) {
            return _buildPhotoCarousel(photoUrls, businessName);
          }
          return _buildSinglePhoto(photoUrls.first, businessName);
        }

        if (snapshot.hasError) {
          print(
              '🖼️ PHOTO WIDGET ERROR: Error fetching photos: ${snapshot.error}');
        }

        // If no photos found via place ID, try a search approach
        if (snapshot.connectionState == ConnectionState.done &&
            (snapshot.data == null || snapshot.data!.isEmpty)) {
          print(
              '🖼️ PHOTO WIDGET: No photos via place ID, trying search approach with "$photoQuery"');

          return FutureBuilder<List<Map<String, dynamic>>>(
              future: widget.mapsService.searchPlaces(photoQuery),
              builder: (context, searchSnapshot) {
                if (searchSnapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFD32323),
                    ),
                  );
                }

                if (searchSnapshot.hasData &&
                    searchSnapshot.data != null &&
                    searchSnapshot.data!.isNotEmpty) {
                  final String? foundPlaceId =
                      searchSnapshot.data!.first['placeId'] as String?;

                  if (foundPlaceId != null && foundPlaceId.isNotEmpty) {
                    print(
                        '🖼️ PHOTO WIDGET: Found place ID via search: $foundPlaceId');

                    return FutureBuilder<List<String>>(
                        future: widget.mapsService
                            .getPlacePhotoReferences(foundPlaceId),
                        builder: (context, photoSnapshot) {
                          if (photoSnapshot.connectionState ==
                              ConnectionState.waiting) {
                            return Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFFD32323),
                              ),
                            );
                          }

                          if (photoSnapshot.hasData &&
                              photoSnapshot.data != null &&
                              photoSnapshot.data!.isNotEmpty) {
                            final List<String> photoUrls = photoSnapshot.data!;
                            print(
                                '🖼️ PHOTO WIDGET: Got ${photoUrls.length} photos via search approach');

                            if (photoUrls.length > 1) {
                              return _buildPhotoCarousel(
                                  photoUrls, businessName);
                            }
                            return _buildSinglePhoto(
                                photoUrls.first, businessName);
                          }

                          print(
                              '🖼️ PHOTO WIDGET: No photos found via search approach either');
                          final String businessSeed =
                              _createPhotoSeed(businessName, location);
                          final String photoUrl =
                              _getBusinessPhotoUrl(businessName, businessSeed);
                          return _buildSinglePhoto(photoUrl, businessName);
                        });
                  }
                }

                print(
                    '🖼️ PHOTO WIDGET: Search approach failed, using category-based fallback');
                final String businessSeed =
                    _createPhotoSeed(businessName, location);
                final String photoUrl =
                    _getBusinessPhotoUrl(businessName, businessSeed);
                return _buildSinglePhoto(photoUrl, businessName);
              });
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          print('🖼️ PHOTO WIDGET: Loading photos...');
          return Center(
            child: CircularProgressIndicator(
              color: Color(0xFFD32323),
            ),
          );
        }

        print('🖼️ PHOTO WIDGET: Using category-based fallback');
        final String businessSeed = _createPhotoSeed(businessName, location);
        final String photoUrl =
            _getBusinessPhotoUrl(businessName, businessSeed);
        return _buildSinglePhoto(photoUrl, businessName);
      },
    );
  }

  // Build a carousel to display multiple photos
  Widget _buildPhotoCarousel(List<String> photoUrls, String businessName) {
    return Stack(
      children: [
        PageView.builder(
          itemCount: photoUrls.length,
          itemBuilder: (context, index) {
            return _buildSinglePhoto(photoUrls[index], businessName);
          },
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.photo, size: 14, color: Colors.white),
                SizedBox(width: 4),
                Text(
                  '${photoUrls.length}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Build a single photo display
  Widget _buildSinglePhoto(String photoUrl, String businessName) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: Color(0xFFEEEEEE)),
        Image.network(
          photoUrl,
          key: ValueKey(photoUrl), // Add key based on URL
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              print('🖼️ PHOTO WIDGET: Image loaded successfully!');
              return child;
            }
            print(
                '🖼️ PHOTO WIDGET: Loading progress: ${loadingProgress.cumulativeBytesLoaded}/${loadingProgress.expectedTotalBytes ?? 'unknown'}');
            return Center(
              child: CircularProgressIndicator(
                color: Color(0xFFD32323),
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            print('🖼️ PHOTO WIDGET ERROR: Failed to load image: $error');
            return _buildPhotoFallback(businessName);
          },
        ),
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
                stops: [0.7, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Generate a seed for consistent photo selection
  String _createPhotoSeed(String businessName, Location location) {
    String seed = businessName;
    if (location.latitude != null && location.longitude != null) {
      String locationStr =
          '${location.latitude!.toStringAsFixed(3)}_${location.longitude!.toStringAsFixed(3)}';
      seed = '$seed-$locationStr';
    }
    return seed.hashCode.abs().toString();
  }

  // Get a photo URL based on business type
  String _getBusinessPhotoUrl(String businessName, String seed) {
    final String businessNameLower = businessName.toLowerCase();
    int seedNumber = int.tryParse(seed) ?? 0;
    String category = 'business';

    if (businessNameLower.contains('restaurant') ||
        businessNameLower.contains('grill') ||
        businessNameLower.contains('pizza') ||
        businessNameLower.contains('kitchen') ||
        businessNameLower.contains('cafe') ||
        businessNameLower.contains('coffee')) {
      category = 'restaurant';
    } else if (businessNameLower.contains('bar') ||
        businessNameLower.contains('pub') ||
        businessNameLower.contains('lounge')) {
      category = 'bar';
    } else if (businessNameLower.contains('shop') ||
        businessNameLower.contains('store') ||
        businessNameLower.contains('market')) {
      category = 'retail';
    } else if (businessNameLower.contains('hotel') ||
        businessNameLower.contains('inn') ||
        businessNameLower.contains('suites')) {
      category = 'hotel';
    }

    Map<String, List<String>> categoryImages = {
      'restaurant': [
        'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1552566626-52f8b828add9?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1600891964599-f61ba0e24092?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1466978913421-dad2ebd01d17?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1592861956120-e524fc739696?w=800&h=400&fit=crop'
      ],
      'bar': [
        'https://images.unsplash.com/photo-1514933651103-005eec06c04b?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1543007630917-64674bd600d8?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1470337458703-46ad1756a187?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1572116469696-31de0f17cc34?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1575444758702-4a6b9222336e?w=800&h=400&fit=crop'
      ],
      'retail': [
        'https://images.unsplash.com/photo-1441986300917-64674bd600d8?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1604719312566-8912e9c8a213?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1567401893414-76b7b1e5a7a5?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1534452203293-494d7ddbf7e0?w=800&h=400&fit=crop'
      ],
      'hotel': [
        'https://images.unsplash.com/photo-1582719508461-905c673771fd?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1566073771259-6a8506099945?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1445019980597-93fa8acb246c?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1520250497591-112f2f40a3f4?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1551882547-ff40c63fe5fa?w=800&h=400&fit=crop'
      ],
      'business': [
        'https://images.unsplash.com/photo-1497366754035-f200968a6e72?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1497215842964-222b430dc094?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1504328345606-18bbc8c9d7d8?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1497366811353-6870744d04b2?w=800&h=400&fit=crop',
        'https://images.unsplash.com/photo-1568992687947-868a62a9f521?w=800&h=400&fit=crop'
      ]
    };

    List<String> images =
        categoryImages[category] ?? categoryImages['business']!;
    int imageIndex = seedNumber % images.length;
    return images[imageIndex];
  }

  // Fallback when image fails to load
  Widget _buildPhotoFallback(String businessName) {
    print('⚠️ FALLBACK WIDGET: Building fallback photo for "$businessName"');
    return Container(
      color: Color(0xFFE8E8E8),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.business,
              size: 48,
              color: Color(0xFFD32323),
            ),
            SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                businessName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF333333),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Detailed preview when we don't have location data
  Widget _buildYelpFallbackPreview(String url, String businessName) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Fallback container with Yelp styling
        InkWell(
          onTap: () => _openYelpUrl(url),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Yelp Logo
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Color(0xFFD32323),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: FaIcon(FontAwesomeIcons.yelp,
                        size: 40, color: Colors.white),
                  ),
                ),
                SizedBox(height: 16),

                // Business Name
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    businessName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(height: 8),

                // Yelp URL
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Text(
                    url.length > 30 ? '${url.substring(0, 30)}...' : url,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ),
                SizedBox(height: 24),

                // Small helper text
                Text(
                  'Tap to view this business on Yelp',
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),

        SizedBox(height: 8),
      ],
    );
  }
  // <<< END METHOD DEFINITIONS >>>

  /// Opens Yelp URL or Yelp.com if no URL is provided using the callback
  Future<void> _openYelpUrl(String yelpUrl) async {
    String url = yelpUrl.trim();

    // If empty, use Yelp.com
    if (url.isEmpty) {
      url = 'https://yelp.com';
    } else if (!url.startsWith('http')) {
      // Make sure it starts with http:// or https://
      url = 'https://' + url;
    }

    // Check if this is a Yelp URL for potential app deep linking
    bool isYelpUrl = url.contains('yelp.com');

    try {
      // Parse the regular web URL
      final Uri webUri = Uri.parse(url);

      // For mobile platforms, try to create a deep link URI
      if (!kIsWeb && isYelpUrl) {
        // Extract business ID for deep linking if present in the URL
        String? yelpAppUrl;

        if (url.contains('/biz/')) {
          final bizPath = url.split('/biz/')[1].split('?')[0];

          if (Platform.isIOS) {
            yelpAppUrl = 'yelp:///biz/$bizPath';
          } else if (Platform.isAndroid) {
            yelpAppUrl = 'yelp://biz/$bizPath';
          }
        }

        // Try opening the app URL first if available
        if (yelpAppUrl != null) {
          try {
            final appUri = Uri.parse(yelpAppUrl);
            // Use the general launchUrl callback to attempt opening
            await widget.launchUrlCallback(appUri.toString());
            return; // Exit if app opens successfully (or attempt was made)
            // Note: canLaunchUrl might not be reliable for custom schemes, so we attempt launch directly
          } catch (e) {
            print('Error opening Yelp app via deep link: $e');
            // Continue to open the web URL as fallback
          }
        }
      }

      // Open web URL as fallback using the callback
      await widget.launchUrlCallback(webUri.toString());
    } catch (e) {
      print('Error launching URL via callback: $e');
      // Optionally show snackbar or handle error in the parent widget if needed
      // ScaffoldMessenger.of(context).showSnackBar(
      //   SnackBar(content: Text('Could not open Yelp: $e')),
      // );
    }
  }
}
