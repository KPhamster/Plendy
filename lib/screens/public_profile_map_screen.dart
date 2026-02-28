import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/experience.dart';
import '../models/user_category.dart';
import '../models/color_category.dart';
import '../models/shared_media_item.dart';
import '../services/experience_service.dart';
import '../services/google_maps_service.dart';
import '../widgets/shared_media_preview_modal.dart';
import '../config/colors.dart';
import 'experience_page_screen.dart';
import '../config/public_profile_map_help_content.dart';
import '../models/public_profile_map_help_target.dart';
import '../widgets/screen_help_controller.dart';

// Helper function to parse hex color string
Color _parseColor(String hexColor) {
  hexColor = hexColor.toUpperCase().replaceAll("#", "");
  if (hexColor.length == 6) {
    hexColor = "FF$hexColor"; // Add alpha if missing
  }
  if (hexColor.length == 8) {
    try {
      return Color(int.parse("0x$hexColor"));
    } catch (e) {
      return Colors.grey; // Default color on parsing error
    }
  }
  return Colors.grey; // Default color on invalid format
}

/// A read-only map screen for viewing a public profile user's experiences.
class PublicProfileMapScreen extends StatefulWidget {
  final String userName;
  final List<Experience> experiences;
  final List<UserCategory> categories;
  final List<ColorCategory> colorCategories;

  const PublicProfileMapScreen({
    super.key,
    required this.userName,
    required this.experiences,
    required this.categories,
    required this.colorCategories,
  });

  @override
  State<PublicProfileMapScreen> createState() => _PublicProfileMapScreenState();
}

class _PublicProfileMapScreenState extends State<PublicProfileMapScreen>
    with TickerProviderStateMixin {
  final Completer<GoogleMapController> _mapControllerCompleter = Completer();
  final ExperienceService _experienceService = ExperienceService();
  final GoogleMapsService _mapsService = GoogleMapsService();
  final Map<String, Marker> _markers = {};
  final Map<String, BitmapDescriptor> _iconCache = {};
  final Map<String, List<SharedMediaItem>> _mediaCache = {};
  bool _isLoading = true;
  LatLng? _initialCenter;
  LatLngBounds? _clusterBounds;
  final Set<String> _clusterExperienceIds = {};

  // State for tapped experience
  Experience? _tappedExperience;
  UserCategory? _tappedCategory;
  Marker? _selectedMarker;
  bool _isLoadingMedia = false;
  late final ScreenHelpController<PublicProfileMapHelpTargetId> _help;

  @override
  void initState() {
    super.initState();
    _help = ScreenHelpController<PublicProfileMapHelpTargetId>(
      vsync: this,
      content: publicProfileMapHelpContent,
      setState: setState,
      isMounted: () => mounted,
      defaultFirstTarget: PublicProfileMapHelpTargetId.helpButton,
    );
    _buildMarkers();
  }

  @override
  void dispose() {
    _help.dispose();
    super.dispose();
  }

  Future<void> _buildMarkers() async {
    if (widget.experiences.isEmpty) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    // Build markers for each experience
    for (final experience in widget.experiences) {
      final marker = await _createMarkerForExperience(experience);
      if (marker != null) {
        _markers[experience.id] = marker;
      }
    }

    // Calculate the bounds of the densest cluster for initial camera
    _initialCenter = _calculateDensestClusterBounds();

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Finds the optimal viewing area that shows the maximum number of experiences
  /// within a reasonable zoom level (max ~50km / 0.5 degrees viewable area).
  LatLng _calculateDensestClusterBounds() {
    final experiences = widget.experiences;

    if (experiences.isEmpty) {
      return const LatLng(37.7749, -122.4194);
    }

    if (experiences.length == 1) {
      return LatLng(
        experiences.first.location.latitude,
        experiences.first.location.longitude,
      );
    }

    // Maximum radius for the viewable area (roughly 25km radius = 50km diameter)
    // 0.25 degrees latitude ≈ 27.75 km
    const double maxViewRadius = 0.25;

    // For each experience, count how many others are within the max view radius
    // This finds the center point that would show the most experiences
    int maxCount = 0;
    int bestCenterIndex = 0;

    for (int i = 0; i < experiences.length; i++) {
      final centerLoc = experiences[i].location;
      int count = 1; // Include self

      for (int j = 0; j < experiences.length; j++) {
        if (i == j) continue;
        final loc = experiences[j].location;
        final latDiff = (centerLoc.latitude - loc.latitude).abs();
        final lngDiff = (centerLoc.longitude - loc.longitude).abs();

        if (latDiff <= maxViewRadius && lngDiff <= maxViewRadius) {
          count++;
        }
      }

      if (count > maxCount) {
        maxCount = count;
        bestCenterIndex = i;
      }
    }

    // Get all experiences within the max view radius of the best center
    final bestCenter = experiences[bestCenterIndex].location;

    _clusterExperienceIds.clear();

    double clusterMinLat = bestCenter.latitude;
    double clusterMaxLat = bestCenter.latitude;
    double clusterMinLng = bestCenter.longitude;
    double clusterMaxLng = bestCenter.longitude;

    for (final exp in experiences) {
      final loc = exp.location;
      final latDiff = (bestCenter.latitude - loc.latitude).abs();
      final lngDiff = (bestCenter.longitude - loc.longitude).abs();

      if (latDiff <= maxViewRadius && lngDiff <= maxViewRadius) {
        _clusterExperienceIds.add(exp.id);
        if (loc.latitude < clusterMinLat) clusterMinLat = loc.latitude;
        if (loc.latitude > clusterMaxLat) clusterMaxLat = loc.latitude;
        if (loc.longitude < clusterMinLng) clusterMinLng = loc.longitude;
        if (loc.longitude > clusterMaxLng) clusterMaxLng = loc.longitude;
      }
    }

    // Store cluster bounds for use in _fitBoundsToMarkers
    _clusterBounds = LatLngBounds(
      southwest: LatLng(clusterMinLat, clusterMinLng),
      northeast: LatLng(clusterMaxLat, clusterMaxLng),
    );

    return LatLng(
      (clusterMinLat + clusterMaxLat) / 2,
      (clusterMinLng + clusterMaxLng) / 2,
    );
  }

  Future<Marker?> _createMarkerForExperience(Experience experience) async {
    final location = experience.location;
    final position = LatLng(location.latitude, location.longitude);

    // Get marker background color from color category
    final Color backgroundColor = _getBackgroundColorForExperience(experience);

    // Get the icon/emoji for this experience
    final String iconText = _getIconTextForExperience(experience);

    // Resolve the category for this experience
    final category = _resolveCategoryForExperience(experience);

    // Generate the bitmap icon
    final icon = await _getOrCreateIcon(iconText, backgroundColor);

    return Marker(
      markerId: MarkerId(experience.id),
      position: position,
      icon: icon,
      onTap: () =>
          _onMarkerTapped(experience, category, iconText, backgroundColor),
    );
  }

  Future<void> _onMarkerTapped(
    Experience experience,
    UserCategory category,
    String iconText,
    Color backgroundColor,
  ) async {
    final location = experience.location;
    final position = LatLng(location.latitude, location.longitude);

    // Create a slightly larger selected marker
    final selectedIcon = await _getOrCreateIcon(
      iconText,
      backgroundColor,
      size: 80,
      opacity: 1.0,
    );

    final selectedMarker = Marker(
      markerId: const MarkerId('selected_experience'),
      position: position,
      icon: selectedIcon,
      zIndex: 1.0,
      onTap: () =>
          _onMarkerTapped(experience, category, iconText, backgroundColor),
    );

    setState(() {
      _tappedExperience = experience;
      _tappedCategory = category;
      _selectedMarker = selectedMarker;
    });

    // Prefetch media for this experience
    _prefetchMedia(experience);

    // Animate camera to the tapped marker
    final controller = await _mapControllerCompleter.future;
    await controller.animateCamera(
      CameraUpdate.newLatLng(position),
    );
  }

  Future<void> _prefetchMedia(Experience experience) async {
    if (experience.sharedMediaItemIds.isEmpty) return;
    if (_mediaCache.containsKey(experience.id)) return;

    try {
      final items = await _experienceService
          .getSharedMediaItems(experience.sharedMediaItemIds);
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (mounted) {
        setState(() {
          _mediaCache[experience.id] = items;
        });
      }
    } catch (e) {
      debugPrint('PublicProfileMapScreen: Error prefetching media: $e');
    }
  }

  void _clearSelection() {
    setState(() {
      _tappedExperience = null;
      _tappedCategory = null;
      _selectedMarker = null;
    });
  }

  Future<void> _navigateToExperience() async {
    if (_tappedExperience == null) return;

    final experience = _tappedExperience!;
    final category = _tappedCategory ?? _createFallbackCategory(experience);

    // Use cached media or fetch if needed
    List<SharedMediaItem>? mediaItems = _mediaCache[experience.id];
    if (mediaItems == null && experience.sharedMediaItemIds.isNotEmpty) {
      setState(() => _isLoadingMedia = true);
      try {
        mediaItems = await _experienceService
            .getSharedMediaItems(experience.sharedMediaItemIds);
        mediaItems.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _mediaCache[experience.id] = mediaItems;
      } catch (e) {
        debugPrint('PublicProfileMapScreen: Error fetching media: $e');
      } finally {
        if (mounted) setState(() => _isLoadingMedia = false);
      }
    }

    if (!mounted) return;

    // Clear selection before navigating
    _clearSelection();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExperiencePageScreen(
          experience: experience,
          category: category,
          userColorCategories: widget.colorCategories,
          additionalUserCategories: widget.categories,
          readOnlyPreview: true,
          initialMediaItems: mediaItems,
        ),
      ),
    );
  }

  Future<void> _onPlayExperienceContent() async {
    if (_tappedExperience == null) return;

    final experience = _tappedExperience!;
    List<SharedMediaItem> resolvedItems;

    // Check cache first
    final cachedItems = _mediaCache[experience.id];
    if (cachedItems != null && cachedItems.isNotEmpty) {
      resolvedItems = cachedItems;
    } else {
      // Need to fetch
      if (experience.sharedMediaItemIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'No saved content available yet for this experience.')),
          );
        }
        return;
      }

      setState(() => _isLoadingMedia = true);
      try {
        final fetched = await _experienceService
            .getSharedMediaItems(experience.sharedMediaItemIds);
        fetched.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _mediaCache[experience.id] = fetched;
        resolvedItems = fetched;
      } catch (e) {
        debugPrint('PublicProfileMapScreen: Error fetching media: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error loading media: $e')),
          );
        }
        return;
      } finally {
        if (mounted) setState(() => _isLoadingMedia = false);
      }
    }

    if (!mounted || resolvedItems.isEmpty) return;

    final category = _tappedCategory ?? _createFallbackCategory(experience);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      builder: (modalContext) {
        return SharedMediaPreviewModal(
          experience: experience,
          mediaItem: resolvedItems.first,
          mediaItems: resolvedItems,
          onLaunchUrl: _launchUrl,
          category: category,
          userColorCategories: widget.colorCategories,
          additionalUserCategories: widget.categories,
        );
      },
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launchMapLocation(Location location) async {
    final lat = location.latitude;
    final lng = location.longitude;

    final googleMapsUrl = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng&query_place_id=${location.placeId ?? ''}',
    );

    if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openDirectionsForLocation(Location location) async {
    final url = _mapsService.getDirectionsUrl(location);
    final uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  UserCategory _resolveCategoryForExperience(Experience experience) {
    if (experience.categoryId != null) {
      try {
        final category = widget.categories.firstWhere(
          (c) => c.id == experience.categoryId,
        );
        return category;
      } catch (_) {
        // Category not found
      }
    }
    return _createFallbackCategory(experience);
  }

  UserCategory _createFallbackCategory(Experience experience) {
    final String fallbackIcon = (experience.categoryIconDenorm != null &&
            experience.categoryIconDenorm!.isNotEmpty)
        ? experience.categoryIconDenorm!
        : '📍';
    return UserCategory(
      id: 'uncategorized',
      name: 'Uncategorized',
      icon: fallbackIcon,
      ownerUserId: experience.createdBy ?? '',
    );
  }

  Color _getBackgroundColorForExperience(Experience experience) {
    if (experience.colorHexDenorm != null &&
        experience.colorHexDenorm!.isNotEmpty) {
      return _parseColor(experience.colorHexDenorm!);
    }

    if (experience.colorCategoryId != null &&
        experience.colorCategoryId!.isNotEmpty) {
      try {
        final colorCategory = widget.colorCategories.firstWhere(
          (cc) => cc.id == experience.colorCategoryId,
        );
        return _parseColor(colorCategory.colorHex);
      } catch (_) {}
    }

    return Colors.grey;
  }

  String _getIconTextForExperience(Experience experience) {
    if (experience.categoryIconDenorm != null &&
        experience.categoryIconDenorm!.isNotEmpty) {
      return experience.categoryIconDenorm!;
    }

    if (experience.categoryId != null) {
      try {
        final category = widget.categories.firstWhere(
          (c) => c.id == experience.categoryId,
        );
        return category.icon;
      } catch (_) {}
    }

    return '📍';
  }

  int _getMediaCount(Experience experience) {
    final cached = _mediaCache[experience.id];
    return cached?.length ?? experience.sharedMediaItemIds.length;
  }

  Future<BitmapDescriptor> _getOrCreateIcon(
    String iconText,
    Color backgroundColor, {
    int size = 60,
    double opacity = 0.7,
  }) async {
    final cacheKey = '${iconText}_${backgroundColor.value}_${size}_$opacity';
    if (_iconCache.containsKey(cacheKey)) {
      return _iconCache[cacheKey]!;
    }

    try {
      final icon = await _bitmapDescriptorFromText(
        iconText,
        size: size,
        backgroundColor: backgroundColor,
        backgroundOpacity: opacity,
      );
      _iconCache[cacheKey] = icon;
      return icon;
    } catch (e) {
      debugPrint('PublicProfileMapScreen: Error generating icon: $e');
      return BitmapDescriptor.defaultMarker;
    }
  }

  int _markerSizeForPlatform(int baseSize) {
    if (kIsWeb) {
      final int scaled = (baseSize * 0.32).round();
      return scaled.clamp(18, baseSize);
    }
    return baseSize;
  }

  Future<BitmapDescriptor> _bitmapDescriptorFromText(
    String text, {
    int size = 60,
    required Color backgroundColor,
    double backgroundOpacity = 0.7,
    Color textColor = Colors.black,
    String? fontFamily,
  }) async {
    final int effectiveSize = _markerSizeForPlatform(size);
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final double radius = effectiveSize / 2;

    final Paint circlePaint = Paint()
      ..color = backgroundColor.withOpacity(backgroundOpacity);
    canvas.drawCircle(Offset(radius, radius), radius, circlePaint);

    final ui.ParagraphBuilder paragraphBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.center,
        fontSize: effectiveSize * 0.7,
        fontFamily: fontFamily,
      ),
    );
    paragraphBuilder.pushStyle(ui.TextStyle(
      color: textColor,
      fontFamily: fontFamily,
      fontSize: effectiveSize * 0.7,
    ));
    paragraphBuilder.addText(text);
    paragraphBuilder.pop();
    final ui.Paragraph paragraph = paragraphBuilder.build();
    paragraph.layout(ui.ParagraphConstraints(width: effectiveSize.toDouble()));

    final double textX = (effectiveSize - paragraph.width) / 2;
    final double textY = (effectiveSize - paragraph.height) / 2;
    canvas.drawParagraph(paragraph, Offset(textX, textY));

    final ui.Image image = await pictureRecorder
        .endRecording()
        .toImage(effectiveSize, effectiveSize);

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw Exception('Failed to convert image to byte data');
    }

    return BitmapDescriptor.fromBytes(byteData.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    // Combine regular markers with selected marker
    final Set<Marker> allMarkers = _markers.values.toSet();
    if (_selectedMarker != null && _tappedExperience != null) {
      allMarkers.removeWhere(
        (m) => m.markerId.value == _tappedExperience!.id,
      );
      allMarkers.add(_selectedMarker!);
    }

    final String? selectedIcon = _tappedExperience != null
        ? _getIconTextForExperience(_tappedExperience!)
        : null;
    final String selectedName = _tappedExperience?.name ?? '';
    final int selectedMediaCount =
        _tappedExperience != null ? _getMediaCount(_tappedExperience!) : 0;
    final bool canPreviewContent = selectedMediaCount > 0;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.backgroundColor,
          appBar: AppBar(
            title: Text("${widget.userName}'s Experiences"),
            backgroundColor: AppColors.backgroundColor,
            foregroundColor: Colors.black,
            elevation: 0,
            actions: [_help.buildIconButton(inactiveColor: Colors.black87)],
            bottom: _help.isActive
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(24),
                    child: _help.buildExitBanner(),
                  )
                : null,
          ),
          body: Builder(
            builder: (mapCtx) => GestureDetector(
              behavior: _help.isActive
                  ? HitTestBehavior.opaque
                  : HitTestBehavior.deferToChild,
              onTap: _help.isActive
                  ? () =>
                      _help.tryTap(PublicProfileMapHelpTargetId.mapArea, mapCtx)
                  : null,
              child: IgnorePointer(
                ignoring: _help.isActive,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : widget.experiences.isEmpty
                        ? const Center(
                            child:
                                Text('No experiences to display on the map.'),
                          )
                        : Stack(
                            children: [
                              // Map
                              GoogleMap(
                                initialCameraPosition: CameraPosition(
                                  target: _initialCenter ??
                                      const LatLng(37.7749, -122.4194),
                                  zoom: 12.0,
                                ),
                                markers: allMarkers,
                                myLocationEnabled: true,
                                myLocationButtonEnabled: true,
                                mapToolbarEnabled: false,
                                zoomControlsEnabled: true,
                                onMapCreated: (controller) {
                                  if (!_mapControllerCompleter.isCompleted) {
                                    _mapControllerCompleter
                                        .complete(controller);
                                  }
                                  _fitBoundsToMarkers(controller);
                                },
                                onTap: (_) => _clearSelection(),
                              ),

                              // Bottom panel for tapped experience
                              AnimatedPositioned(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                                left: 0,
                                right: 0,
                                bottom: _tappedExperience != null ? 0 : -300,
                                child: _tappedExperience != null
                                    ? _buildBottomPanel(
                                        selectedIcon,
                                        selectedName,
                                        selectedMediaCount,
                                        canPreviewContent,
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
              ),
            ),
          ),
        ),
        if (_help.isActive && _help.hasActiveTarget) _help.buildOverlay(),
      ],
    );
  }

  Widget _buildBottomPanel(
    String? selectedIcon,
    String selectedName,
    int selectedMediaCount,
    bool canPreviewContent,
  ) {
    final experience = _tappedExperience!;
    final String? additionalNotes = experience.additionalNotes?.trim();
    final bool hasNotes = additionalNotes != null && additionalNotes.isNotEmpty;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        2 + MediaQuery.of(context).padding.bottom / 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.backgroundColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // "Tap to view" hint text
          Positioned(
            top: -12,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Tap to view experience details',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: _isLoadingMedia ? null : _navigateToExperience,
            behavior: HitTestBehavior.translucent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                // Title row with icon, name, and action buttons
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (selectedIcon != null &&
                                selectedIcon.isNotEmpty &&
                                selectedIcon != '*') ...[
                              SizedBox(
                                width: 24,
                                child: Center(
                                  child: Text(
                                    selectedIcon,
                                    style: const TextStyle(fontSize: 16),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                selectedName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Action buttons
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Open in map button
                        IconButton(
                          onPressed: () {
                            _launchMapLocation(experience.location);
                          },
                          icon: const Icon(
                            Icons.map_outlined,
                            color: AppColors.sage,
                            size: 28,
                          ),
                          tooltip: 'Open in map app',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          style: IconButton.styleFrom(
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Directions button
                        IconButton(
                          onPressed: () {
                            _openDirectionsForLocation(experience.location);
                          },
                          icon: const Icon(
                            Icons.directions,
                            color: AppColors.teal,
                            size: 28,
                          ),
                          tooltip: 'Get Directions',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          style: IconButton.styleFrom(
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Close button
                        IconButton(
                          onPressed: _clearSelection,
                          icon: Icon(
                            Icons.close,
                            color: Colors.grey[600],
                            size: 28,
                          ),
                          tooltip: 'Close',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          style: IconButton.styleFrom(
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        if (kIsWeb) const SizedBox(width: 8),
                      ],
                    ),
                  ],
                ),

                // Other categories (if any)
                if (experience.otherCategories.isNotEmpty)
                  _buildOtherCategoriesWidget(experience),

                // Color category widget
                _buildColorCategoryWidget(experience),

                // Address row with play button
                if (experience.location.address != null &&
                    experience.location.address!.isNotEmpty) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          experience.location.address!,
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Play button for media preview
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: OverflowBox(
                          minHeight: 48,
                          maxHeight: 48,
                          alignment: Alignment.center,
                          child: GestureDetector(
                            onTap: _onPlayExperienceContent,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 200),
                              opacity: canPreviewContent ? 1.0 : 0.45,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).primaryColor,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.play_arrow,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                  Positioned(
                                    bottom: -2,
                                    right: -2,
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Theme.of(context).primaryColor,
                                          width: 2,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          selectedMediaCount.toString(),
                                          style: TextStyle(
                                            color:
                                                Theme.of(context).primaryColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                // Additional notes
                if (hasNotes) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.notes,
                        size: 18,
                        color: Colors.grey[700],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          additionalNotes,
                          style: TextStyle(
                            color: Colors.grey[800],
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // Star rating (from location if available)
                if (experience.location.rating != null) ...[
                  Row(
                    children: [
                      ...List.generate(5, (i) {
                        final ratingValue = experience.location.rating!;
                        return Icon(
                          i < ratingValue.floor()
                              ? Icons.star
                              : (i < ratingValue)
                                  ? Icons.star_half
                                  : Icons.star_border,
                          size: 18,
                          color: Colors.amber,
                        );
                      }),
                      const SizedBox(width: 8),
                      if (experience.location.userRatingCount != null &&
                          experience.location.userRatingCount! > 0)
                        Text(
                          '(${experience.location.userRatingCount})',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // Loading indicator
                if (_isLoadingMedia) ...[
                  const SizedBox(height: 8),
                  const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtherCategoriesWidget(Experience experience) {
    final otherCategoryObjects = experience.otherCategories
        .map((id) {
          try {
            return widget.categories.firstWhere((c) => c.id == id);
          } catch (_) {
            return null;
          }
        })
        .whereType<UserCategory>()
        .toList();

    if (otherCategoryObjects.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8.0,
      runSpacing: 4.0,
      children: otherCategoryObjects.asMap().entries.map((entry) {
        final int index = entry.key;
        final UserCategory category = entry.value;

        if (index == 0) {
          return SizedBox(
            width: 24,
            child: Center(
              child: Text(
                category.icon,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return Text(
          category.icon,
          style: const TextStyle(fontSize: 16),
        );
      }).toList(),
    );
  }

  Widget _buildColorCategoryWidget(Experience experience) {
    ColorCategory? primaryColorCategory;
    if (experience.colorCategoryId != null &&
        experience.colorCategoryId!.isNotEmpty) {
      try {
        primaryColorCategory = widget.colorCategories.firstWhere(
          (cc) => cc.id == experience.colorCategoryId,
        );
      } catch (_) {}
    }

    final List<ColorCategory> otherColorCategories =
        experience.otherColorCategoryIds
            .map((id) {
              try {
                return widget.colorCategories.firstWhere((cc) => cc.id == id);
              } catch (_) {
                return null;
              }
            })
            .whereType<ColorCategory>()
            .toList();

    if (primaryColorCategory == null && otherColorCategories.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<Widget> rowChildren = [];

    if (primaryColorCategory != null) {
      rowChildren.add(
        Container(
          padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _parseColor(primaryColorCategory.colorHex),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                primaryColorCategory.name,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    for (final colorCat in otherColorCategories) {
      rowChildren.add(const SizedBox(width: 8));
      rowChildren.add(
        Container(
          padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _parseColor(colorCat.colorHex),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                colorCat.name,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          children: rowChildren,
        ),
      ),
    );
  }

  Future<void> _fitBoundsToMarkers(GoogleMapController controller) async {
    if (_markers.isEmpty) return;

    if (_markers.length == 1) {
      final marker = _markers.values.first;
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(marker.position, 15.0),
      );
      return;
    }

    // If we have cluster bounds (densest area), use those
    if (_clusterBounds != null && _clusterExperienceIds.length > 1) {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(_clusterBounds!, 80.0),
      );
      return;
    }

    // Fallback: show all markers
    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;

    for (final marker in _markers.values) {
      final lat = marker.position.latitude;
      final lng = marker.position.longitude;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 60.0),
    );
  }
}
