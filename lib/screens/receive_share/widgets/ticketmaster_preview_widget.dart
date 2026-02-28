import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:plendy/utils/haptic_feedback.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:plendy/models/receive_share_help_target.dart';

/// Displays a branded preview for Ticketmaster links.
///
/// Shows the Ticketmaster logo and branding while event details are being loaded
/// or as a fallback when details cannot be fetched.
class TicketmasterPreviewWidget extends StatelessWidget {
  static const Color _ticketmasterBlue = Color(0xFF026CDF);

  final String ticketmasterUrl;
  final Future<void> Function(String url)? launchUrlCallback;
  final EdgeInsetsGeometry padding;
  final bool isLoading;
  final String? eventName;
  final String? venueName;
  final DateTime? eventDate;
  final String? imageUrl;
  final bool isHelpMode;
  final bool Function(ReceiveShareHelpTargetId id, BuildContext ctx)? onHelpTap;

  const TicketmasterPreviewWidget({
    super.key,
    required this.ticketmasterUrl,
    this.launchUrlCallback,
    this.padding = const EdgeInsets.all(16),
    this.isLoading = false,
    this.eventName,
    this.venueName,
    this.eventDate,
    this.imageUrl,
    this.isHelpMode = false,
    this.onHelpTap,
  });

  bool _helpTap(ReceiveShareHelpTargetId id, BuildContext ctx) {
    if (onHelpTap != null) return onHelpTap!(id, ctx);
    return false;
  }

  Future<void> _handleTap(BuildContext context) async {
    final callback = launchUrlCallback;
    if (callback != null) {
      await callback(ticketmasterUrl);
      return;
    }

    final Uri? uri = Uri.tryParse(ticketmasterUrl.trim());
    if (uri == null) {
      _showLaunchError(context);
      return;
    }

    try {
      bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalNonBrowserApplication,
      );

      if (!launched) {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      }

      if (!launched) {
        _showLaunchError(context);
      }
    } catch (_) {
      _showLaunchError(context);
    }
  }

  void _showLaunchError(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(content: Text('Could not open Ticketmaster link')),
    );
  }

  String _formatEventDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    
    final weekday = weekdays[date.weekday % 7];
    final month = months[date.month - 1];
    final day = date.day;
    final year = date.year;
    
    // Format time
    final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    
    return '$weekday, $month $day, $year at $hour:$minute $period';
  }

  /// Extract a readable event name from the URL slug as a fallback
  String? _extractEventNameFromUrl() {
    try {
      final uri = Uri.parse(ticketmasterUrl);
      final pathSegments = uri.pathSegments;
      
      // Find the segment before "event"
      for (int i = 0; i < pathSegments.length; i++) {
        if (pathSegments[i] == 'event' && i > 0) {
          final slug = pathSegments[i - 1];
          // Convert slug to readable name
          var name = slug
              .split('-')
              .map((word) => word.isNotEmpty 
                  ? '${word[0].toUpperCase()}${word.substring(1)}' 
                  : word)
              .join(' ');
          
          // Remove date patterns at the end
          name = name.replaceAll(RegExp(r'\s+\d{2}\s+\d{2}\s+\d{4}$'), '');
          
          return name.isNotEmpty ? name : null;
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Use API event name, or extract from URL as fallback
    final displayName = eventName ?? (isLoading ? null : _extractEventNameFromUrl());
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final hasDetails = eventDate != null || venueName != null;

    return Semantics(
      button: true,
      label: 'Tap to open Ticketmaster link',
      child: Builder(builder: (ctx) => InkWell(
        onTap: withHeavyTap(() {
          if (_helpTap(ReceiveShareHelpTargetId.previewOpenExternalButton, ctx)) return;
          _handleTap(ctx);
        }),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _ticketmasterBlue.withOpacity(0.3)),
            color: _ticketmasterBlue.withOpacity(0.05),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Event image header (if available)
              if (hasImage && !isLoading) ...[
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(11),
                    topRight: Radius.circular(11),
                  ),
                  child: Stack(
                    children: [
                      CachedNetworkImage(
                        imageUrl: imageUrl!,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          height: 160,
                          color: _ticketmasterBlue.withOpacity(0.1),
                          child: const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _ticketmasterBlue,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          height: 160,
                          color: _ticketmasterBlue.withOpacity(0.1),
                          child: Icon(
                            Icons.confirmation_number,
                            size: 48,
                            color: _ticketmasterBlue.withOpacity(0.5),
                          ),
                        ),
                      ),
                      // Ticketmaster badge on image
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _ticketmasterBlue,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                'assets/icon/misc/ticketmaster_logo.png',
                                height: 14,
                                width: 14,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(
                                    Icons.confirmation_number,
                                    color: Colors.white,
                                    size: 14,
                                  );
                                },
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'Ticketmaster',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Open in new tab icon
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.open_in_new,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // Content section
              Padding(
                padding: padding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header row (logo + title) - only show if no image
                    if (!hasImage || isLoading) ...[
                      Row(
                        children: [
                          // Ticketmaster logo
                          Container(
                            decoration: BoxDecoration(
                              color: _ticketmasterBlue,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.all(8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.asset(
                                'assets/icon/misc/ticketmaster_logo.png',
                                height: 28,
                                width: 28,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(
                                    Icons.confirmation_number,
                                    color: Colors.white,
                                    size: 28,
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isLoading) ...[
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: _ticketmasterBlue,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Loading event details...',
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: _ticketmasterBlue,
                                        ),
                                      ),
                                    ],
                                  ),
                                ] else if (displayName != null) ...[
                                  Text(
                                    displayName,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: _ticketmasterBlue,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ] else ...[
                                  Text(
                                    'Ticketmaster Event',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: _ticketmasterBlue,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                  'Tap to open in Ticketmaster',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.open_in_new, color: _ticketmasterBlue),
                        ],
                      ),
                    ] else ...[
                      // Event name (when image is shown)
                      if (displayName != null) ...[
                        Text(
                          displayName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _ticketmasterBlue,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                      ],
                    ],
                    // Event details (date and venue)
                    if (hasDetails && !isLoading) ...[
                      if (hasImage && displayName != null) const SizedBox(height: 8),
                      if (!hasImage) const Divider(height: 24),
                      if (eventDate != null) ...[
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _formatEventDate(eventDate!),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey[800],
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (venueName != null) const SizedBox(height: 8),
                      ],
                      if (venueName != null) ...[
                        Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 16,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                venueName!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey[800],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                    // "Tap to open" hint when image is shown
                    if (hasImage && !isLoading) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Tap to open in Ticketmaster',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      )),
    );
  }
}

