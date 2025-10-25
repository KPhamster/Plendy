import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/color_category.dart';
import '../models/experience.dart';
import '../models/public_experience.dart';
import '../models/user_category.dart';
import '../services/experience_service.dart';
import '../services/google_maps_service.dart';
import 'receive_share/widgets/facebook_preview_widget.dart';
import 'receive_share/widgets/generic_url_preview_widget.dart';
import 'receive_share/widgets/maps_preview_widget.dart';
import 'receive_share/widgets/tiktok_preview_widget.dart';
import 'receive_share/widgets/youtube_preview_widget.dart';
import 'receive_share/widgets/instagram_preview_widget.dart'
    as instagram_widget;
import '../widgets/edit_experience_modal.dart';
import 'map_screen.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen>
    with AutomaticKeepAliveClientMixin {
  final ExperienceService _experienceService = ExperienceService();
  final GoogleMapsService _mapsService = GoogleMapsService();
  final Map<String, Future<Map<String, dynamic>?>> _mapsPreviewFutures = {};
  final PageController _pageController = PageController();
  final Random _random = Random();

  final List<PublicExperience> _publicExperiences = [];
  final List<_DiscoveryFeedItem> _feedItems = [];
  final Set<String> _usedMediaKeys = {};

  DocumentSnapshot<Object?>? _lastDocument;
  bool _hasMore = true;
  bool _isFetchingExperiences = false;
  bool _isLoading = true;
  bool _isError = false;
  bool _isPreparingMore = false;
  String? _errorMessage;
  int _currentPage = 0;
  double _dragDistance = 0;
  static const double _dragThreshold = 40;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeFeed();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _initializeFeed() async {
    try {
      await _fetchMoreExperiencesIfNeeded(force: true);
      await _generateFeedItems(count: 5);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isError = true;
        _errorMessage = 'Unable to load discovery feed. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchMoreExperiencesIfNeeded({bool force = false}) async {
    if (!force && (_isFetchingExperiences || !_hasMore)) {
      return;
    }
    _isFetchingExperiences = true;
    try {
      final page = await _experienceService.fetchPublicExperiencesPage(
        startAfter: _lastDocument,
        limit: 50,
      );

      _lastDocument = page.lastDocument;
      _hasMore = page.hasMore;

      if (page.experiences.isNotEmpty) {
        final mediaRichExperiences = page.experiences
            .where((exp) => exp.allMediaPaths.isNotEmpty)
            .toList();
        if (mediaRichExperiences.isNotEmpty) {
          _publicExperiences.addAll(mediaRichExperiences);
        }
      }
    } finally {
      _isFetchingExperiences = false;
    }
  }

  Future<void> _generateFeedItems({int count = 5}) async {
    if (count <= 0) return;

    final List<_DiscoveryFeedItem> newItems = [];
    final int maxAttempts = count * 50;
    int attempts = 0;

    while (newItems.length < count && attempts < maxAttempts) {
      attempts++;

      if (_publicExperiences.isEmpty) {
        if (_hasMore) {
          await _fetchMoreExperiencesIfNeeded(force: true);
          continue;
        } else {
          break;
        }
      }

      final experience =
          _publicExperiences[_random.nextInt(_publicExperiences.length)];

      if (experience.allMediaPaths.isEmpty) {
        continue;
      }

      final mediaUrl = experience
          .allMediaPaths[_random.nextInt(experience.allMediaPaths.length)];

      if (mediaUrl.isEmpty) {
        continue;
      }

      final totalCombos = _calculateTotalAvailableMediaPaths();
      if (totalCombos > 0 && _usedMediaKeys.length >= totalCombos) {
        _usedMediaKeys.clear();
      }

      final key = '${experience.id}::$mediaUrl';
      if (_usedMediaKeys.contains(key)) {
        if (_hasMore && attempts % 20 == 0) {
          await _fetchMoreExperiencesIfNeeded(force: true);
        }
        continue;
      }

      _usedMediaKeys.add(key);
      newItems.add(
        _DiscoveryFeedItem(
          experience: experience,
          mediaUrl: mediaUrl,
        ),
      );
    }

    if (newItems.isNotEmpty && mounted) {
      setState(() {
        _feedItems.addAll(newItems);
      });
    }
  }

  int _calculateTotalAvailableMediaPaths() {
    return _publicExperiences.fold<int>(
      0,
      (runningTotal, experience) =>
          runningTotal + experience.allMediaPaths.length,
    );
  }

  void _handlePageChanged(int index) {
    setState(() {
      _currentPage = index;
    });

    if (_feedItems.length - index <= 2) {
      _prepareMoreItems();
    }
  }

  Future<void> _prepareMoreItems() async {
    if (_isPreparingMore) return;
    _isPreparingMore = true;

    try {
      if (_hasMore) {
        await _fetchMoreExperiencesIfNeeded();
      }
      await _generateFeedItems(count: 3);
    } catch (_) {
      // Intentionally swallow errors for background prefetching.
    } finally {
      _isPreparingMore = false;
    }
  }

  Future<void> _retry() async {
    setState(() {
      _isError = false;
      _errorMessage = null;
      _isLoading = true;
      _publicExperiences.clear();
      _feedItems.clear();
      _usedMediaKeys.clear();
      _lastDocument = null;
      _hasMore = true;
      _currentPage = 0;
      _dragDistance = 0;
    });

    await _initializeFeed();
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('DiscoveryScreen: failed to launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
                _errorMessage ??
                    'Something went wrong while loading the discovery feed.',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _retry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_feedItems.isEmpty) {
      return const Center(
        child: Text(
          'No public experiences to show yet.\nCheck back soon for new recommendations.',
          style: TextStyle(color: Colors.white70, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      );
    }

    return GestureDetector(
      onVerticalDragStart: (_) {
        _dragDistance = 0;
      },
      onVerticalDragUpdate: (details) {
        _dragDistance += details.primaryDelta ?? 0;
      },
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -300 || _dragDistance <= -_dragThreshold) {
          _maybeAnimateToPage(_currentPage + 1);
        } else if (velocity > 300 || _dragDistance >= _dragThreshold) {
          _maybeAnimateToPage(_currentPage - 1);
        }
        _dragDistance = 0;
      },
      child: PageView.builder(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        scrollDirection: Axis.vertical,
        itemCount: _feedItems.length,
        onPageChanged: _handlePageChanged,
        itemBuilder: (context, index) {
          final item = _feedItems[index];
          return _buildFeedPage(item);
        },
      ),
    );
  }

  void _maybeAnimateToPage(int targetPage) {
    if (targetPage < 0 || targetPage >= _feedItems.length) {
      return;
    }
    _pageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Widget _buildFeedPage(_DiscoveryFeedItem item) {
    final preview = _buildPreviewForItem(item);

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        preview,
        Container(
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
        Positioned(
          left: 16,
          right: 96,
          bottom: 32,
          child: _buildMetadata(item.experience),
        ),
        Positioned(
          right: 16,
          bottom: 32,
          child: _buildActionButtons(item),
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

  Widget _buildActionButtons(_DiscoveryFeedItem item) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildActionButton(
          icon: Icons.bookmark_border,
          label: 'Bookmark',
          onPressed: () => _handleBookmarkTapped(item),
        ),
        const SizedBox(height: 16),
        _buildActionButton(
          icon: Icons.place_outlined,
          label: 'Location',
          onPressed: () {
            final location = item.experience.location;
            final locationForMap = (location.displayName != null &&
                    location.displayName!.trim().isNotEmpty)
                ? location
                : location.copyWith(displayName: item.experience.name);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MapScreen(
                  initialExperienceLocation: locationForMap,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        _buildActionButton(
          icon: Icons.ios_share,
          label: 'Share',
          onPressed: () {
            // TODO: Implement share action.
          },
        ),
        const SizedBox(height: 16),
        _buildActionButton(
          icon: Icons.more_vert,
          label: 'More',
          onPressed: () {
            // TODO: Implement more action.
          },
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    VoidCallback? onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: BorderRadius.circular(24),
          ),
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon, color: Colors.white),
            iconSize: 28,
            splashRadius: 28,
          ),
        ),
        const SizedBox(height: 6),
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

  Future<void> _handleBookmarkTapped(_DiscoveryFeedItem item) async {
    final publicExperience = item.experience;
    final Experience draft = _buildExperienceDraft(publicExperience);

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final Experience? editedExperience = await showModalBottomSheet<Experience>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return EditExperienceModal(
          experience: draft,
          userCategories: const <UserCategory>[],
          userColorCategories: const <ColorCategory>[],
          requireCategorySelection: true,
          scaffoldMessenger: messenger,
          enableDuplicatePrompt: true,
        );
      },
    );

    if (editedExperience == null) {
      return;
    }

    try {
      if (editedExperience.id.isNotEmpty) {
        await _experienceService.updateExperience(editedExperience);
      } else {
        await _experienceService.createExperience(editedExperience);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Experience saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save experience: $e')),
      );
    }
  }

  Experience _buildExperienceDraft(PublicExperience publicExperience) {
    final now = DateTime.now();
    final List<String> mediaPaths = publicExperience.allMediaPaths
        .where((path) => path.isNotEmpty)
        .toList();

    return Experience(
      id: '',
      name: publicExperience.name,
      description: '',
      location: publicExperience.location,
      categoryId: null,
      yelpUrl: publicExperience.yelpUrl,
      googleUrl: null,
      plendyRating: 0,
      plendyReviewCount: 0,
      imageUrls: mediaPaths,
      reelIds: const <String>[],
      followerIds: const <String>[],
      rating: 0,
      createdAt: now,
      updatedAt: now,
      website: publicExperience.website,
      phoneNumber: null,
      openingHours: null,
      tags: null,
      priceRange: null,
      sharedMediaItemIds: const <String>[],
      sharedMediaType: null,
      additionalNotes: null,
      editorUserIds: const <String>[],
      colorCategoryId: null,
      otherCategories: const <String>[],
      categoryIconDenorm: null,
      colorHexDenorm: null,
      createdBy: null,
    );
  }

  Widget _buildPreviewForItem(_DiscoveryFeedItem item) {
    final url = item.mediaUrl;

    if (url.isEmpty) {
      return _buildFallbackPreview(
        icon: Icons.link_off,
        label: 'No preview available',
        description: 'This experience does not include a preview link.',
      );
    }

    final type = _classifyUrl(url);
    final mediaSize = MediaQuery.of(context).size;

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
          'location': item.experience.location,
          'placeName': item.experience.name,
          'mapsUrl': url,
          'website': item.experience.website,
        });
        return SizedBox.expand(
          child: MapsPreviewWidget(
            key: ValueKey('maps_$url'),
            mapsUrl: url,
            mapsPreviewFutures: _mapsPreviewFutures,
            getLocationFromMapsUrl: (requestedUrl) async {
              if (requestedUrl == url) {
                return {
                  'location': item.experience.location,
                  'placeName': item.experience.name,
                  'mapsUrl': url,
                  'website': item.experience.website,
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
}

class _DiscoveryFeedItem {
  const _DiscoveryFeedItem({
    required this.experience,
    required this.mediaUrl,
  });

  final PublicExperience experience;
  final String mediaUrl;
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
