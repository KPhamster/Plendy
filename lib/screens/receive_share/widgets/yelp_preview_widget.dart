import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:plendy/utils/haptic_feedback.dart';

/// Displays a lightweight placeholder for Yelp links.
///
/// The widget avoids embedding a web view (which Yelp blocks) and instead
/// prompts the user to open the link directly in the Yelp app or browser.
class YelpPreviewWidget extends StatelessWidget {
  static const Color _yelpRed = Color(0xFFD32323);

  final String yelpUrl;
  final Future<void> Function(String url)? launchUrlCallback;
  final EdgeInsetsGeometry padding;

  const YelpPreviewWidget({
    super.key,
    required this.yelpUrl,
    this.launchUrlCallback,
    this.padding = const EdgeInsets.all(16),
  });

  Future<void> _handleTap(BuildContext context) async {
    final callback = launchUrlCallback;
    if (callback != null) {
      await callback(yelpUrl);
      return;
    }

    final Uri? uri = Uri.tryParse(yelpUrl.trim());
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
      const SnackBar(content: Text('Could not open Yelp link')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: 'Tap to open Yelp link',
      child: InkWell(
        onTap: withHeavyTap(() => _handleTap(context)),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
            color: Colors.grey[50],
          ),
          child: Row(
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: _yelpRed,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(14),
                child: const FaIcon(
                  FontAwesomeIcons.yelp,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Tap to open in Yelp',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: _yelpRed,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Yelp previews open directly in the Yelp app.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new, color: _yelpRed),
            ],
          ),
        ),
      ),
    );
  }
}
