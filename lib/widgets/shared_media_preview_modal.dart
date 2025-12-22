import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // ADDED: Import for kIsWeb
import 'package:share_plus/share_plus.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/experience.dart';
import '../models/user_category.dart';
import '../models/color_category.dart';
import '../models/shared_media_item.dart';
import '../config/colors.dart';
// Use the same preview widgets as Experience Page content tab
import '../screens/receive_share/widgets/instagram_preview_widget.dart'
    as instagram_widget;
import '../screens/receive_share/widgets/tiktok_preview_widget.dart';
import '../screens/receive_share/widgets/facebook_preview_widget.dart';
import '../screens/receive_share/widgets/youtube_preview_widget.dart';
import '../screens/receive_share/widgets/generic_url_preview_widget.dart';
import '../screens/receive_share/widgets/maps_preview_widget.dart';
import '../screens/receive_share/widgets/yelp_preview_widget.dart';
import '../services/google_maps_service.dart';
import '../services/experience_share_service.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../screens/experience_page_screen.dart';
import 'web_media_preview_card.dart'; // ADDED: Import for WebMediaPreviewCard
import '../widgets/share_experience_bottom_sheet.dart';

class SharedMediaPreviewModal extends StatefulWidget {
  final Experience experience;
  final SharedMediaItem mediaItem;
  final List<SharedMediaItem> mediaItems;
  final Future<void> Function(String url) onLaunchUrl;
  final UserCategory? category;
  final List<ColorCategory> userColorCategories;
  final List<UserCategory> additionalUserCategories;
  final bool showSavedDate; // Whether to show the "Saved" date/time in metadata
  final bool
      isPublicExperience; // Whether this is a public experience from the community
  final VoidCallback?
      onViewExperience; // Custom handler for viewing the experience

  const SharedMediaPreviewModal({
    super.key,
    required this.experience,
    required this.mediaItem,
    required this.mediaItems,
    required this.onLaunchUrl,
    this.category,
    this.userColorCategories = const <ColorCategory>[],
    this.additionalUserCategories = const <UserCategory>[],
    this.showSavedDate = true, // Default to showing it
    this.isPublicExperience = false, // Default to false (personal experience)
    this.onViewExperience, // Optional custom handler
  });

  @override
  State<SharedMediaPreviewModal> createState() =>
      _SharedMediaPreviewModalState();
}

class _SharedMediaPreviewModalState extends State<SharedMediaPreviewModal> {
  late SharedMediaItem _activeItem;
  late PageController _pageController;
  int _currentIndex = 0;
  bool _isPreviewExpanded = false;
  bool _isShareInProgress = false;
  // For Maps preview parity with ExperiencePageScreen
  final GoogleMapsService _mapsService = GoogleMapsService();
  final Map<String, Future<Map<String, dynamic>?>> _mapsPreviewFutures = {};
  final ExperienceShareService _experienceShareService =
      ExperienceShareService();
  static const double _defaultPreviewHeight = 640.0;
  static const double _maxExpandedPreviewHeight = 845.0;
  static const List<String> _monthAbbreviations = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  void initState() {
    super.initState();
    // Initialize current index based on provided mediaItem
    final initialIdx =
        widget.mediaItems.indexWhere((it) => it.id == widget.mediaItem.id);
    _currentIndex = initialIdx >= 0 ? initialIdx : 0;
    _activeItem = widget.mediaItems.isNotEmpty
        ? widget.mediaItems[_currentIndex]
        : widget.mediaItem;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _formatFullTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    final String month = _monthAbbreviations[local.month - 1];
    final int day = local.day;
    final int year = local.year;
    final int hour24 = local.hour;
    final int hour12 = ((hour24 + 11) % 12) + 1;
    final String minute = local.minute.toString().padLeft(2, '0');
    final String period = hour24 >= 12 ? 'PM' : 'AM';
    return '$month $day, $year • $hour12:$minute $period';
  }

  String _formatChipTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    final String month = _monthAbbreviations[local.month - 1];
    final int day = local.day;
    final int hour24 = local.hour;
    final int hour12 = ((hour24 + 11) % 12) + 1;
    final String minute = local.minute.toString().padLeft(2, '0');
    final String period = hour24 >= 12 ? 'PM' : 'AM';
    return '$month $day • $hour12:$minute $period';
  }

  double _getPreviewHeight(BuildContext context) {
    if (!_isPreviewExpanded) {
      return _defaultPreviewHeight;
    }
    final double screenHeight = MediaQuery.of(context).size.height;
    final double targetHeight = screenHeight * 1.5;
    final double clampedHeight =
        targetHeight.clamp(_defaultPreviewHeight, _maxExpandedPreviewHeight);
    return clampedHeight.toDouble();
  }

  double _getMinimumPreviewHeightForItem(SharedMediaItem item) {
    final String url = item.path;
    if (url.isEmpty) {
      return 0;
    }
    final _MediaType type = _classifyUrl(url);
    switch (type) {
      case _MediaType.tiktok:
        return 700.0;
      case _MediaType.instagram:
        return 640.0;
      case _MediaType.facebook:
        return 500.0;
      case _MediaType.youtube:
        return 600.0;
      case _MediaType.yelp:
        return 520.0;
      case _MediaType.maps:
        return 520.0;
      case _MediaType.image:
      case _MediaType.generic:
        return 0;
    }
  }

  double _getEffectivePreviewHeight(
      BuildContext context, SharedMediaItem item) {
    final double baseHeight = _getPreviewHeight(context);
    final double minimumHeight = _getMinimumPreviewHeightForItem(item);
    return baseHeight >= minimumHeight ? baseHeight : minimumHeight;
  }

  void _togglePreviewExpansion() {
    setState(() {
      _isPreviewExpanded = !_isPreviewExpanded;
    });
  }

  Future<void> _handleShareButtonPressed(SharedMediaItem mediaItem) async {
    if (!mounted || _isShareInProgress) return;
    await showShareExperienceBottomSheet(
      context: context,
      onDirectShare: () => _shareMediaDirectly(mediaItem),
      onCreateLink: ({
        required String shareMode,
        required bool giveEditAccess,
      }) =>
          _createLinkShareForMedia(
        shareMode: shareMode,
        giveEditAccess: giveEditAccess,
      ),
    );
  }

  Future<void> _shareMediaDirectly(SharedMediaItem mediaItem) async {
    final String? highlightedUrl =
        mediaItem.path.isNotEmpty ? mediaItem.path : null;
    final result = await showShareToFriendsModal(
      context: context,
      subjectLabel: widget.experience.name,
      onSubmit: (recipientIds) async {
        return await _experienceShareService.createDirectShare(
          experience: widget.experience,
          toUserIds: recipientIds,
          highlightedMediaUrl: highlightedUrl,
        );
      },
      onSubmitToThreads: (threadIds) async {
        return await _experienceShareService.createDirectShareToThreads(
          experience: widget.experience,
          threadIds: threadIds,
          highlightedMediaUrl: highlightedUrl,
        );
      },
      onSubmitToNewGroupChat: (participantIds) async {
        return await _experienceShareService.createDirectShareToNewGroupChat(
          experience: widget.experience,
          participantIds: participantIds,
          highlightedMediaUrl: highlightedUrl,
        );
      },
    );
    if (!mounted) return;
    if (result != null) {
      showSharedWithFriendsSnackbar(context, result);
    }
  }

  Future<void> _createLinkShareForMedia({
    required String shareMode,
    required bool giveEditAccess,
  }) async {
    if (_isShareInProgress || !mounted) return;
    setState(() {
      _isShareInProgress = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final DateTime expiresAt = DateTime.now().add(const Duration(days: 30));
      final String url = await _experienceShareService.createLinkShare(
        experience: widget.experience,
        expiresAt: expiresAt,
        linkMode: shareMode,
        grantEdit: giveEditAccess,
      );
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) {
        Navigator.of(context).pop();
      }
      await Share.share('Check out this experience from Plendy! $url');
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Unable to generate a share link. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isShareInProgress = false;
        });
      }
    }
  }

  void _handleViewExperienceNavigation() {
    if (!mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    navigator.pop();
    if (widget.onViewExperience != null) {
      widget.onViewExperience!();
      return;
    }
    navigator.push(
      MaterialPageRoute(
        builder: (_) => ExperiencePageScreen(
          experience: widget.experience,
          category: widget.category ?? _buildFallbackCategory(),
          userColorCategories: widget.userColorCategories,
          additionalUserCategories: widget.additionalUserCategories,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = _activeItem;
    final experience = widget.experience;
    final multipleItems = widget.mediaItems.length > 1;
    final double previewHeight = _getEffectivePreviewHeight(context, media);
    final double? previewHeightOverride =
        _isPreviewExpanded ? previewHeight : null;

    return FractionallySizedBox(
      heightFactor: 0.95,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.backgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 12,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  HapticFeedback.heavyImpact();
                                  _handleViewExperienceNavigation();
                                },
                                child: Text(
                                  experience.name,
                                  style: GoogleFonts.notoSerif(
                                    textStyle: theme.textTheme.titleMedium,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          HapticFeedback.heavyImpact();
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Preview (carousel when multiple items)
                        if (multipleItems)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                            height: previewHeight,
                            child: PageView.builder(
                              controller: _pageController,
                              itemCount: widget.mediaItems.length,
                              onPageChanged: (index) {
                                setState(() {
                                  _currentIndex = index;
                                  _activeItem = widget.mediaItems[index];
                                });
                              },
                              itemBuilder: (context, index) {
                                final item = widget.mediaItems[index];
                                return _buildPreview(
                                  context,
                                  item,
                                  heightOverride: previewHeightOverride,
                                );
                              },
                            ),
                          )
                        else
                          _buildPreview(
                            context,
                            media,
                            heightOverride: previewHeightOverride,
                          ),
                        if (multipleItems) ...[
                          const SizedBox(height: 8),
                          _buildCarouselDots(),
                        ],
                        const SizedBox(height: 12),
                        _buildActionButtons(context, media),
                        const SizedBox(height: 12),
                        _buildMetadataSection(theme, media),
                        const SizedBox(height: 16),
                        if (multipleItems) ...[
                          const SizedBox(height: 24),
                          Text(
                            'Saved links',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: widget.mediaItems
                                .map((item) => _buildMediaChip(context, item))
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(
    BuildContext context,
    SharedMediaItem mediaItem, {
    double? heightOverride,
  }) {
    final url = mediaItem.path;
    if (url.isEmpty) {
      return _buildFallbackPreview(
        icon: Icons.link_off,
        label: 'No preview available',
        description: 'This item does not include a link to preview.',
      );
    }

    final type = _classifyUrl(url);
    // Use parity with ExperiencePageScreen content tab
    if (type == _MediaType.tiktok) {
      return kIsWeb
          ? WebMediaPreviewCard(
              url: url,
              experienceName: widget.experience.name,
              onOpenPressed: () => widget.onLaunchUrl(url),
            )
          : TikTokPreviewWidget(
              key: ValueKey(url),
              url: url,
              launchUrlCallback: widget.onLaunchUrl,
              showControls: false,
            );
    }

    if (type == _MediaType.instagram) {
      final double instagramHeight = heightOverride ?? 640.0;
      return kIsWeb
          ? WebMediaPreviewCard(
              url: url,
              experienceName: widget.experience.name,
              onOpenPressed: () => widget.onLaunchUrl(url),
            )
          : instagram_widget.InstagramWebView(
              key: ValueKey(url),
              url: url,
              height: instagramHeight,
              launchUrlCallback: widget.onLaunchUrl,
              onWebViewCreated: (_) {},
              onPageFinished: (_) {},
            );
    }

    if (type == _MediaType.facebook) {
      final double facebookHeight = heightOverride ?? 500.0;
      return kIsWeb
          ? WebMediaPreviewCard(
              url: url,
              experienceName: widget.experience.name,
              onOpenPressed: () => widget.onLaunchUrl(url),
            )
          : FacebookPreviewWidget(
              key: ValueKey(url),
              url: url,
              height: facebookHeight,
              onWebViewCreated: (_) {},
              onPageFinished: (_) {},
              launchUrlCallback: widget.onLaunchUrl,
              showControls: false,
            );
    }

    if (type == _MediaType.youtube) {
      final double? youtubeHeight = heightOverride;
      return kIsWeb
          ? WebMediaPreviewCard(
              url: url,
              experienceName: widget.experience.name,
              onOpenPressed: () => widget.onLaunchUrl(url),
            )
          : YouTubePreviewWidget(
              key: ValueKey(url),
              url: url,
              launchUrlCallback: widget.onLaunchUrl,
              showControls: false,
              height: youtubeHeight,
              onWebViewCreated: (_) {},
            );
    }

    if (type == _MediaType.maps) {
      // Seed a resolved future using the known experience/location data
      _mapsPreviewFutures[url] = Future.value({
        'location': widget.experience.location,
        'placeName': widget.experience.name,
        'mapsUrl': url,
        'website': widget.experience.location.website,
      });
      return MapsPreviewWidget(
        key: ValueKey(url),
        mapsUrl: url,
        mapsPreviewFutures: _mapsPreviewFutures,
        getLocationFromMapsUrl: (u) async => null,
        launchUrlCallback: widget.onLaunchUrl,
        mapsService: _mapsService,
      );
    }

    if (type == _MediaType.yelp) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: YelpPreviewWidget(
          key: ValueKey(url),
          yelpUrl: url,
          launchUrlCallback: widget.onLaunchUrl,
        ),
      );
    }

    // Image preview for direct and likely image URLs
    if (type == _MediaType.image || _isLikelyImageUrl(url)) {
      return ClipRRect(
        key: ValueKey(url),
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 4 / 5,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                alignment: Alignment.center,
                color: Colors.grey.shade200,
                child: const CircularProgressIndicator(),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return _buildFallbackPreview(
                icon: Icons.broken_image_outlined,
                label: 'Image failed to load',
                description:
                    'We could not load this image. Try opening it in the browser.',
              );
            },
          ),
        ),
      );
    }

    // Generic web URL fallback
    return GenericUrlPreviewWidget(
      key: ValueKey(url),
      url: url,
      launchUrlCallback: widget.onLaunchUrl,
    );
  }

  // Best-effort heuristic to detect image-like URLs without extensions
  bool _isLikelyImageUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('googleusercontent.com') ||
        lower.contains('ggpht.com') ||
        lower.contains('gstatic.com') ||
        lower.contains('firebasestorage.googleapis.com') ||
        lower.contains('cloudfront.net') ||
        lower.contains('amazonaws.com') ||
        lower.contains('imgur.com') ||
        lower.contains('unsplash.com') ||
        lower.contains('pbs.twimg.com') ||
        lower.contains('staticflickr.com');
  }

  // Removed custom YouTube thumbnail helper; using YouTubePreviewWidget instead for parity
  Widget _buildMediaChip(BuildContext context, SharedMediaItem item) {
    final theme = Theme.of(context);
    final isActive = item.id == _activeItem.id;
    final label = _formatChipTimestamp(item.createdAt);
    final defaultTextColor =
        theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurface;

    return ChoiceChip(
      selected: isActive,
      selectedColor: theme.primaryColor,
      checkmarkColor: Colors.white,
      label: Text(
        label,
        style: TextStyle(
          color: isActive ? Colors.white : defaultTextColor,
        ),
      ),
      onSelected: (selected) {
        if (!selected) return;
        final int targetIndex =
            widget.mediaItems.indexWhere((it) => it.id == item.id);
        if (targetIndex >= 0) {
          // Animate the carousel to the selected item
          _pageController.animateToPage(
            targetIndex,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          );
          setState(() {
            _currentIndex = targetIndex;
            _activeItem = widget.mediaItems[targetIndex];
          });
        } else {
          // Fallback: just switch active item
          setState(() {
            _activeItem = item;
          });
        }
      },
    );
  }

  Widget _buildCarouselDots() {
    final total = widget.mediaItems.length;
    final primaryColor = Theme.of(context).primaryColor;
    return RepaintBoundary(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(total, (index) {
          final bool isActive = index == _currentIndex;
          return RepaintBoundary(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: isActive ? 10 : 8,
              height: isActive ? 10 : 8,
              decoration: BoxDecoration(
                color: isActive ? primaryColor : Colors.grey.shade400,
                shape: BoxShape.circle,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildMetadataSection(ThemeData theme, SharedMediaItem mediaItem) {
    final createdAt = mediaItem.createdAt;
    final formattedDate = _formatFullTimestamp(createdAt);

    // For public experiences, show "Shared by community" instead of saved date
    final String dateLabel =
        widget.isPublicExperience ? 'Shared by community' : 'Saved';
    final String dateValue =
        widget.isPublicExperience ? 'Community experience' : formattedDate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Details',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.primaryColor,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: theme.primaryColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showSavedDate) ...[
                _buildMetadataRow(
                  icon:
                      widget.isPublicExperience ? Icons.people : Icons.schedule,
                  label: dateLabel,
                  value: dateValue,
                  iconColor: Colors.white,
                  labelColor: Colors.white,
                  valueColor: Colors.white,
                ),
                const SizedBox(height: 8),
              ],
              _buildMetadataRow(
                icon: Icons.public,
                label: 'URL',
                value: mediaItem.path,
                isSelectable: true,
                iconColor: Colors.white,
                labelColor: Colors.white,
                valueColor: Colors.white,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetadataRow({
    required IconData icon,
    required String label,
    required String value,
    bool isSelectable = false,
    Color? iconColor,
    Color? labelColor,
    Color? valueColor,
  }) {
    final effectiveIconColor = iconColor ?? Colors.grey.shade600;
    final effectiveLabelColor = labelColor ?? Colors.grey.shade600;
    final effectiveValueColor = valueColor ?? Colors.black87;
    final baseValueStyle = TextStyle(
      fontSize: 13,
      color: effectiveValueColor,
    );
    final textWidget = isSelectable
        ? SelectableText(
            value,
            style: baseValueStyle,
          )
        : Text(
            value,
            style: baseValueStyle,
          );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 18, color: effectiveIconColor),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: effectiveLabelColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              textWidget,
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFallbackPreview({
    required IconData icon,
    required String label,
    required String description,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.grey.shade100,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade500),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  // Removed unused _buildLinkPreviewCard (replaced by GenericUrlPreviewWidget)

  Widget _buildActionButtons(BuildContext context, SharedMediaItem mediaItem) {
    final url = mediaItem.path;
    final isLaunchable = url.toLowerCase().startsWith('http://') ||
        url.toLowerCase().startsWith('https://');

    // Choose icon and tooltip based on content type, mirroring ExperiencePageScreen
    final type = _classifyUrl(url);
    IconData iconData = Icons.open_in_new;
    Color? iconColor;
    double iconSize = 28;
    String tooltip = 'Open link';

    switch (type) {
      case _MediaType.tiktok:
        iconData = FontAwesomeIcons.tiktok;
        iconColor = Colors.black;
        tooltip = 'Open in TikTok';
        iconSize = 30;
        break;
      case _MediaType.instagram:
        iconData = FontAwesomeIcons.instagram;
        iconColor = const Color(0xFFE1306C);
        tooltip = 'Open in Instagram';
        iconSize = 30;
        break;
      case _MediaType.facebook:
        iconData = FontAwesomeIcons.facebook;
        iconColor = const Color(0xFF1877F2);
        tooltip = 'Open in Facebook';
        iconSize = 30;
        break;
      case _MediaType.youtube:
        iconData = FontAwesomeIcons.youtube;
        iconColor = Colors.red;
        tooltip = 'Open in YouTube';
        iconSize = 30;
        break;
      case _MediaType.maps:
        iconData = FontAwesomeIcons.google;
        iconColor = const Color(0xFF4285F4);
        tooltip = 'Open in Google Maps';
        iconSize = 30;
        break;
      case _MediaType.yelp:
        iconData = FontAwesomeIcons.yelp;
        iconColor = const Color(0xFFD32323);
        tooltip = 'Open in Yelp';
        iconSize = 28;
        break;
      case _MediaType.image:
      case _MediaType.generic:
        iconData = Icons.open_in_new;
        iconColor = Theme.of(context).primaryColor;
        tooltip = 'Open in browser';
        iconSize = 28;
        break;
    }

    final IconData expansionIcon =
        _isPreviewExpanded ? Icons.fullscreen_exit : Icons.fullscreen;
    final String expansionTooltip =
        _isPreviewExpanded ? 'Collapse preview' : 'Expand preview';
    final Color expansionColor = Colors.blue;
    final Color shareColor = Colors.blue;

    final Widget socialButton = IconButton(
      tooltip: tooltip,
      iconSize: iconSize,
      onPressed: isLaunchable
          ? () {
              HapticFeedback.heavyImpact();
              widget.onLaunchUrl(url);
            }
          : null,
      icon: Icon(iconData, color: iconColor),
    );

    final Widget shareButton = IconButton(
      tooltip: 'Share media',
      iconSize: 26,
      color: shareColor,
      icon: const Icon(Icons.share_outlined),
      onPressed: _isShareInProgress
          ? null
          : () {
              HapticFeedback.heavyImpact();
              _handleShareButtonPressed(mediaItem);
            },
    );

    final Widget expandButton = IconButton(
      tooltip: expansionTooltip,
      iconSize: 26,
      color: expansionColor,
      icon: Icon(expansionIcon),
      onPressed: () {
        HapticFeedback.heavyImpact();
        _togglePreviewExpansion();
      },
    );

    final Widget viewExperienceButton = IconButton(
      tooltip: 'View experience details',
      iconSize: 28,
      icon: Icon(Icons.arrow_forward_rounded,
          color: Theme.of(context).primaryColor),
      onPressed: () {
        HapticFeedback.heavyImpact();
        _handleViewExperienceNavigation();
      },
    );

    return SizedBox(
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(child: socialButton),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                shareButton,
                const SizedBox(width: 4),
                expandButton,
                const SizedBox(width: 4),
                viewExperienceButton,
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Removed unused _copyToClipboard helper

  UserCategory _buildFallbackCategory() {
    final experience = widget.experience;
    final String categoryId = experience.categoryId ?? 'experience';
    final String ownerId = experience.createdBy ?? 'unknown-owner';
    final String icon = experience.categoryIconDenorm ?? '📍';
    const String name = 'Saved Place';
    return UserCategory(
      id: categoryId,
      name: name,
      icon: icon,
      ownerUserId: ownerId,
    );
  }

  _MediaType _classifyUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp')) {
      return _MediaType.image;
    }
    if (lower.contains('tiktok.com') || lower.contains('vm.tiktok.com')) {
      return _MediaType.tiktok;
    }
    if (lower.contains('instagram.com')) {
      return _MediaType.instagram;
    }
    if (lower.contains('facebook.com') ||
        lower.contains('fb.com') ||
        lower.contains('fb.watch')) {
      return _MediaType.facebook;
    }
    if (lower.contains('youtube.com') ||
        lower.contains('youtu.be') ||
        lower.contains('youtube.com/shorts')) {
      return _MediaType.youtube;
    }
    if (lower.contains('yelp.com/biz') || lower.contains('yelp.to/')) {
      return _MediaType.yelp;
    }
    if (lower.contains('google.com/maps') ||
        lower.contains('maps.app.goo.gl') ||
        lower.contains('goo.gl/maps') ||
        lower.contains('g.co/kgs/') ||
        lower.contains('share.google/')) {
      return _MediaType.maps;
    }
    return _MediaType.generic;
  }

  // Removed unused _extractYouTubeId (using YouTubePreviewWidget)

  // Removed unused _iconForType helper

  // Removed unused _labelForType helper
}

enum _MediaType {
  tiktok,
  instagram,
  facebook,
  youtube,
  yelp,
  maps,
  image,
  generic
}
