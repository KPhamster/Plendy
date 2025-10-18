import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/experience.dart';
import '../models/shared_media_item.dart';

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
                        _buildMetadataSection(theme, media),
                        const SizedBox(height: 16),
                        _buildActionButtons(context, media),
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
    if (type == _MediaType.image) {
      return ClipRRect(
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

    final icon = _iconForType(type);
    final label = _labelForType(type);

    return _buildLinkPreviewCard(
      icon: icon,
      label: label,
      url: url,
    );
  }


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

  Widget _buildLinkPreviewCard({
    required IconData icon,
    required String label,
    required String url,
  }) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.grey.shade100,
              ),
              child: SelectableText(
                url,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => widget.onLaunchUrl(url),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _copyToClipboard(url),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy link'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, SharedMediaItem mediaItem) {
    final url = mediaItem.path;
    final isLaunchable =
        url.toLowerCase().startsWith('http://') || url.toLowerCase().startsWith('https://');

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: isLaunchable
                ? () => widget.onLaunchUrl(url)
                : null,
            icon: const Icon(Icons.play_circle_filled),
            label: const Text('Open in browser'),
          ),
        ),
      ],
    );
  }

  void _copyToClipboard(String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied to clipboard')),
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

  IconData _iconForType(_MediaType type) {
    switch (type) {
      case _MediaType.tiktok:
        return Icons.music_note;
      case _MediaType.instagram:
        return Icons.camera_alt_outlined;
      case _MediaType.facebook:
        return Icons.facebook;
      case _MediaType.youtube:
        return Icons.ondemand_video;
      case _MediaType.yelp:
        return Icons.reviews;
      case _MediaType.maps:
        return Icons.map_outlined;
      case _MediaType.image:
        return Icons.image;
      case _MediaType.generic:
      default:
        return Icons.link;
    }
  }

  String _labelForType(_MediaType type) {
    switch (type) {
      case _MediaType.tiktok:
        return 'TikTok link';
      case _MediaType.instagram:
        return 'Instagram link';
      case _MediaType.facebook:
        return 'Facebook link';
      case _MediaType.youtube:
        return 'YouTube link';
      case _MediaType.yelp:
        return 'Yelp link';
      case _MediaType.maps:
        return 'Maps link';
      case _MediaType.image:
        return 'Image preview';
      case _MediaType.generic:
      default:
        return 'Shared link';
    }
  }
}

enum _MediaType { tiktok, instagram, facebook, youtube, yelp, maps, image, generic }
