import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../models/public_experience.dart';
import '../services/discovery_share_service.dart';
import 'receive_share/widgets/facebook_preview_widget.dart';
import 'receive_share/widgets/generic_url_preview_widget.dart';
import 'receive_share/widgets/maps_preview_widget.dart';
import 'receive_share/widgets/tiktok_preview_widget.dart';
import 'receive_share/widgets/youtube_preview_widget.dart';
import 'receive_share/widgets/instagram_preview_widget.dart'
    as instagram_widget;
import '../services/google_maps_service.dart';

/// Standalone read-only screen for unauthenticated web visitors opening a shared discovery link.
class DiscoverySharePreviewScreen extends StatefulWidget {
  const DiscoverySharePreviewScreen({super.key, required this.token});

  final String token;

  @override
  State<DiscoverySharePreviewScreen> createState() =>
      _DiscoverySharePreviewScreenState();
}

class _DiscoverySharePreviewScreenState
    extends State<DiscoverySharePreviewScreen> {
  final DiscoveryShareService _discoveryShareService =
      DiscoveryShareService();
  final GoogleMapsService _mapsService = GoogleMapsService();
  final Map<String, Future<Map<String, dynamic>?>> _mapsPreviewFutures = {};

  bool _isLoading = true;
  bool _isError = false;
  String? _errorMessage;
  DiscoverySharePayload? _payload;

  @override
  void initState() {
    super.initState();
    _loadSharedExperience();
  }

  Future<void> _loadSharedExperience() async {
    try {
      final payload = await _discoveryShareService.fetchShare(widget.token);
      if (!mounted) return;
      setState(() {
        _payload = payload;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isError = true;
        _errorMessage =
            'Unable to load the shared experience. This link may have expired.';
        _isLoading = false;
      });
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('DiscoverySharePreviewScreen: failed to launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_isError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage ?? 'Something went wrong.',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _isError = false;
                    _errorMessage = null;
                  });
                  _loadSharedExperience();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_payload == null) {
      return const Center(
        child: Text(
          'Experience not found.',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      );
    }

    return _buildPreviewContent(_payload!);
  }

  Widget _buildPreviewContent(DiscoverySharePayload payload) {
    final experience = payload.experience;
    final mediaUrl = payload.mediaUrl;
    final mediaSize = MediaQuery.of(context).size;

    final preview = _buildPreviewForUrl(mediaUrl, experience, mediaSize);

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        preview,
        IgnorePointer(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black87,
                  Colors.transparent,
                ],
                stops: [0.0, 0.6],
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 96,
          bottom: 32,
          child: _buildMetadata(experience),
        ),
        Positioned(
          right: 16,
          bottom: 32,
          child: _buildActionButtons(mediaUrl),
        ),
      ],
    );
  }

  Widget _buildMetadata(PublicExperience experience) {
    final location = experience.location;
    final details = <String>[];

    if ((location.city ?? '').trim().isNotEmpty) {
      details.add(location.city!.trim());
    }
    if ((location.state ?? '').trim().isNotEmpty) {
      details.add(location.state!.trim());
    }

    final subtitle = details.join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          experience.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              subtitle,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildActionButtons(String mediaUrl) {
    final sourceButton = _buildSourceActionButton(mediaUrl);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (sourceButton != null) ...[
          sourceButton,
          const SizedBox(height: 16),
        ],
        _buildActionButton(
          icon: Icons.open_in_new,
          label: 'Open',
          onPressed: () => _launchUrl(mediaUrl),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    IconData? icon,
    Widget? iconWidget,
    required String label,
    Color? backgroundColor,
    VoidCallback? onPressed,
  }) {
    final Widget iconContent =
        iconWidget ?? Icon(icon, color: Colors.white, size: 28);
    final bool isDisabled = onPressed == null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.black45,
            borderRadius: BorderRadius.circular(24),
          ),
          child: IconButton(
            onPressed: onPressed,
            icon: iconContent,
            iconSize: iconWidget == null ? 28 : 24,
            splashRadius: 28,
            color: Colors.white,
            disabledColor: Colors.white70,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget? _buildSourceActionButton(String url) {
    final config = _resolveSourceButtonConfig(url);
    if (config == null) return null;
    return _buildActionButton(
      icon: config.iconData,
      iconWidget: config.iconWidget,
      label: config.label,
      backgroundColor: config.backgroundColor,
      onPressed: () => _launchUrl(url),
    );
  }

  _SourceButtonConfig? _resolveSourceButtonConfig(String url) {
    if (!_isNetworkUrl(url)) return null;
    final type = _classifyUrl(url);
    switch (type) {
      case _MediaType.instagram:
        return _SourceButtonConfig(
          label: 'Instagram',
          backgroundColor: const Color(0xFFE4405F),
          iconWidget: const FaIcon(
            FontAwesomeIcons.instagram,
            color: Colors.white,
            size: 20,
          ),
        );
      case _MediaType.tiktok:
        return _SourceButtonConfig(
          label: 'TikTok',
          backgroundColor: Colors.black,
          iconWidget: const FaIcon(
            FontAwesomeIcons.tiktok,
            color: Colors.white,
            size: 20,
          ),
        );
      case _MediaType.facebook:
        return _SourceButtonConfig(
          label: 'Facebook',
          backgroundColor: const Color(0xFF1877F2),
          iconWidget: const FaIcon(
            FontAwesomeIcons.facebookF,
            color: Colors.white,
            size: 20,
          ),
        );
      case _MediaType.youtube:
        return _SourceButtonConfig(
          label: 'YouTube',
          backgroundColor: const Color(0xFFFF0000),
          iconWidget: const FaIcon(
            FontAwesomeIcons.youtube,
            color: Colors.white,
            size: 20,
          ),
        );
      case _MediaType.maps:
        return _SourceButtonConfig(
          label: 'Maps',
          backgroundColor: const Color(0xFF4285F4),
          iconWidget: const FaIcon(
            FontAwesomeIcons.google,
            color: Colors.white,
            size: 20,
          ),
        );
      case _MediaType.yelp:
        return _SourceButtonConfig(
          label: 'Yelp',
          backgroundColor: const Color(0xFFD32323),
          iconWidget: const FaIcon(
            FontAwesomeIcons.yelp,
            color: Colors.white,
            size: 20,
          ),
        );
      case _MediaType.image:
      case _MediaType.generic:
        return _SourceButtonConfig(
          label: 'Open Link',
          backgroundColor: Colors.blue.shade700,
          iconData: Icons.open_in_new,
        );
    }
  }

  bool _isNetworkUrl(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  _MediaType _classifyUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        _isLikelyImageUrl(lower)) {
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

  bool _isLikelyImageUrl(String url) {
    final hasImageKeywords = ['img', 'image', 'photo', 'picture', 'media'];
    return hasImageKeywords.any(url.contains);
  }

  Widget _buildPreviewForUrl(
    String url,
    PublicExperience experience,
    Size mediaSize,
  ) {
    if (url.isEmpty) {
      return _buildFallbackPreview(
        icon: Icons.link_off,
        label: 'No preview available',
        description: 'This experience does not include a preview link.',
      );
    }

    final type = _classifyUrl(url);

    switch (type) {
      case _MediaType.tiktok:
        return SizedBox.expand(
          child: TikTokPreviewWidget(
            key: ValueKey('tiktok_$url'),
            url: url,
            launchUrlCallback: _launchUrl,
            showControls: false,
          ),
        );
      case _MediaType.instagram:
        return SizedBox.expand(
          child: instagram_widget.InstagramWebView(
            key: ValueKey('instagram_$url'),
            url: url,
            height: mediaSize.height,
            launchUrlCallback: _launchUrl,
            onWebViewCreated: (_) {},
            onPageFinished: (_) {},
          ),
        );
      case _MediaType.facebook:
        return SizedBox.expand(
          child: FacebookPreviewWidget(
            key: ValueKey('facebook_$url'),
            url: url,
            height: mediaSize.height,
            onWebViewCreated: (_) {},
            onPageFinished: (_) {},
            launchUrlCallback: _launchUrl,
            showControls: false,
          ),
        );
      case _MediaType.youtube:
        return SizedBox.expand(
          child: YouTubePreviewWidget(
            key: ValueKey('youtube_$url'),
            url: url,
            launchUrlCallback: _launchUrl,
            showControls: false,
            onWebViewCreated: (_) {},
            height: mediaSize.height,
          ),
        );
      case _MediaType.maps:
        _mapsPreviewFutures[url] ??= Future.value({
          'location': experience.location,
          'placeName': experience.name,
          'mapsUrl': url,
          'website': experience.website,
        });
        return SizedBox.expand(
          child: MapsPreviewWidget(
            key: ValueKey('maps_$url'),
            mapsUrl: url,
            mapsPreviewFutures: _mapsPreviewFutures,
            getLocationFromMapsUrl: (requestedUrl) async {
              if (requestedUrl == url) {
                return {
                  'location': experience.location,
                  'placeName': experience.name,
                  'mapsUrl': url,
                  'website': experience.website,
                };
              }
              return null;
            },
            launchUrlCallback: _launchUrl,
            mapsService: _mapsService,
          ),
        );
      case _MediaType.image:
        return SizedBox.expand(
          child: Image.network(
            url,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                color: Colors.grey.shade900,
                alignment: Alignment.center,
                child: const CircularProgressIndicator(),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return _buildFallbackPreview(
                icon: Icons.broken_image_outlined,
                label: 'Image failed to load',
                description: 'Try opening this image in your browser.',
              );
            },
          ),
        );
      case _MediaType.generic:
      case _MediaType.yelp:
        return SizedBox.expand(
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: GenericUrlPreviewWidget(
              key: ValueKey('generic_$url'),
              url: url,
              launchUrlCallback: _launchUrl,
            ),
          ),
        );
    }
  }

  Widget _buildFallbackPreview({
    required IconData icon,
    required String label,
    String? description,
  }) {
    return Container(
      width: double.infinity,
      height: 360,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 56),
          const SizedBox(height: 16),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          if (description != null) ...[
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

enum _MediaType {
  tiktok,
  instagram,
  facebook,
  youtube,
  maps,
  image,
  yelp,
  generic,
}

class _SourceButtonConfig {
  const _SourceButtonConfig({
    this.iconData,
    this.iconWidget,
    required this.label,
    required this.backgroundColor,
  }) : assert(iconData != null || iconWidget != null);

  final IconData? iconData;
  final Widget? iconWidget;
  final String label;
  final Color backgroundColor;
}
