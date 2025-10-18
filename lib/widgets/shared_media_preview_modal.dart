import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/experience.dart';
import '../models/shared_media_item.dart';
// Use the same preview widgets as Experience Page content tab
import '../screens/receive_share/widgets/instagram_preview_widget.dart'
    as instagram_widget;
import '../screens/receive_share/widgets/tiktok_preview_widget.dart';
import '../screens/receive_share/widgets/facebook_preview_widget.dart';
import '../screens/receive_share/widgets/youtube_preview_widget.dart';
import '../screens/receive_share/widgets/generic_url_preview_widget.dart';
import '../screens/receive_share/widgets/web_url_preview_widget.dart';
import '../screens/receive_share/widgets/maps_preview_widget.dart';
import '../services/google_maps_service.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class SharedMediaPreviewModal extends StatefulWidget {
  final Experience experience;
  final SharedMediaItem mediaItem;
  final List<SharedMediaItem> mediaItems;
  final Future<void> Function(String url) onLaunchUrl;

  const SharedMediaPreviewModal({
    super.key,
    required this.experience,
    required this.mediaItem,
    required this.mediaItems,
    required this.onLaunchUrl,
  });

  @override
  State<SharedMediaPreviewModal> createState() =>
      _SharedMediaPreviewModalState();
}

class _SharedMediaPreviewModalState extends State<SharedMediaPreviewModal> {
  late SharedMediaItem _activeItem;
  // For Maps preview parity with ExperiencePageScreen
  final GoogleMapsService _mapsService = GoogleMapsService();
  final Map<String, Future<Map<String, dynamic>?>> _mapsPreviewFutures = {};
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
    _activeItem = widget.mediaItem;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = _activeItem;
    final experience = widget.experience;
    final multipleItems = widget.mediaItems.length > 1;

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
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
                            Text(
                              experience.name,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              multipleItems
                                  ? 'Showing newest of ${widget.mediaItems.length} saved items'
                                  : 'Latest shared content',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPreview(context, media),
                        const SizedBox(height: 12),
                        _buildActionButtons(context, media),
                        const SizedBox(height: 12),
                        _buildMetadataSection(theme, media),
                        const SizedBox(height: 16),
                        if (multipleItems) ...[
                          const SizedBox(height: 24),
                          Text(
                            'Other recent links',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: widget.mediaItems
                                .take(6)
                                .map((item) => _buildMediaChip(item))
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

  Widget _buildPreview(BuildContext context, SharedMediaItem mediaItem) {
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
      return TikTokPreviewWidget(
        key: ValueKey(url),
        url: url,
        launchUrlCallback: widget.onLaunchUrl,
        showControls: false,
      );
    }

    if (type == _MediaType.instagram) {
      return instagram_widget.InstagramWebView(
        key: ValueKey(url),
        url: url,
        height: 640.0,
        launchUrlCallback: widget.onLaunchUrl,
        onWebViewCreated: (_) {},
        onPageFinished: (_) {},
      );
    }

    if (type == _MediaType.facebook) {
      return FacebookPreviewWidget(
        key: ValueKey(url),
        url: url,
        height: 500.0,
        onWebViewCreated: (_) {},
        onPageFinished: (_) {},
        launchUrlCallback: widget.onLaunchUrl,
        showControls: false,
      );
    }

    if (type == _MediaType.youtube) {
      return YouTubePreviewWidget(
        key: ValueKey(url),
        url: url,
        launchUrlCallback: widget.onLaunchUrl,
        showControls: false,
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
      return WebUrlPreviewWidget(
        key: ValueKey(url),
        url: url,
        launchUrlCallback: widget.onLaunchUrl,
        showControls: false,
        height: 1000.0,
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


  Widget _buildMediaChip(SharedMediaItem item) {
    final isActive = item.id == _activeItem.id;
    final label = _formatChipTimestamp(item.createdAt);

    return ChoiceChip(
      selected: isActive,
      label: Text(label),
      onSelected: (selected) {
        if (!selected) return;
        setState(() {
          _activeItem = item;
        });
      },
    );
  }

  Widget _buildMetadataSection(ThemeData theme, SharedMediaItem mediaItem) {
    final createdAt = mediaItem.createdAt;
    final formattedDate = _formatFullTimestamp(createdAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Details',
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMetadataRow(
                icon: Icons.schedule,
                label: 'Saved',
                value: formattedDate,
              ),
              const SizedBox(height: 8),
              _buildMetadataRow(
                icon: Icons.public,
                label: 'URL',
                value: mediaItem.path,
                isSelectable: true,
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
  }) {
    final textWidget = isSelectable
        ? SelectableText(
            value,
            style: const TextStyle(fontSize: 13),
          )
        : Text(
            value,
            style: const TextStyle(fontSize: 13),
          );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 18, color: Colors.grey.shade600),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey.shade600,
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
    final isLaunchable =
        url.toLowerCase().startsWith('http://') || url.toLowerCase().startsWith('https://');

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
        iconData = Icons.open_in_new;
        iconColor = Theme.of(context).primaryColor;
        tooltip = 'Open in browser';
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

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: tooltip,
          iconSize: iconSize,
          onPressed: isLaunchable ? () => widget.onLaunchUrl(url) : null,
          icon: Icon(iconData, color: iconColor),
        ),
      ],
    );
  }

  // Removed unused _copyToClipboard helper

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

enum _MediaType { tiktok, instagram, facebook, youtube, yelp, maps, image, generic }
