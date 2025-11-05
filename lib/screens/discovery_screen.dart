import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/color_category.dart';
import '../models/experience.dart';
import '../models/public_experience.dart';
import '../models/shared_media_item.dart';
import '../models/user_category.dart';
import '../services/experience_service.dart';
import '../services/discovery_share_service.dart';
import '../services/google_maps_service.dart';
import 'receive_share/widgets/facebook_preview_widget.dart';
import 'receive_share/widgets/generic_url_preview_widget.dart';
import 'receive_share/widgets/maps_preview_widget.dart';
import 'receive_share/widgets/tiktok_preview_widget.dart';
import 'receive_share/widgets/youtube_preview_widget.dart';
import 'receive_share/widgets/instagram_preview_widget.dart'
    as instagram_widget;
import '../widgets/save_to_experiences_modal.dart';
import 'experience_page_screen.dart';
import 'map_screen.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({
    super.key,
    this.initialShareToken,
  });

  final String? initialShareToken;

  @override
  State<DiscoveryScreen> createState() => DiscoveryScreenState();
}

class DiscoveryScreenState extends State<DiscoveryScreen>
    with AutomaticKeepAliveClientMixin {
  static const UserCategory _publicReadOnlyCategory = UserCategory(
    id: 'public_readonly_category',
    name: 'Discovery',
    icon: '*',
    ownerUserId: 'public',
  );

  final ExperienceService _experienceService = ExperienceService();
  final GoogleMapsService _mapsService = GoogleMapsService();
  final DiscoveryShareService _discoveryShareService =
      DiscoveryShareService();
  final Map<String, Future<Map<String, dynamic>?>> _mapsPreviewFutures = {};
  final Map<String, Future<List<Experience>>> _linkedExperiencesFutures = {};
  final Map<String, Future<List<Experience>>>
      _accessibleExperiencesFutures = {};
  final Map<String, Future<bool>> _savedMediaByUrlFutures = {};
  final PageController _pageController = PageController();
  final Random _random = Random();

  final List<PublicExperience> _publicExperiences = [];
  final List<_DiscoveryFeedItem> _feedItems = [];
  final Set<String> _usedMediaKeys = {};
  List<UserCategory> _userCategories = [];
  List<ColorCategory> _userColorCategories = [];
  Future<void>? _userCollectionsFuture;

  DocumentSnapshot<Object?>? _lastDocument;
  bool _hasMore = true;
  bool _isFetchingExperiences = false;
  bool _isLoading = true;
  bool _isError = false;
  bool _isPreparingMore = false;
  bool _isShareInProgress = false;
  bool _isLoadingSharedPreview = false;
  String? _errorMessage;
  int _currentPage = 0;
  double _dragDistance = 0;
  static const double _dragThreshold = 40;
  String? _lastDisplayedShareToken;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeFeed();
    final String? initialToken = widget.initialShareToken;
    if (initialToken != null && initialToken.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showSharedPreview(initialToken);
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DiscoveryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String? newToken = widget.initialShareToken;
    if (newToken != null &&
        newToken.isNotEmpty &&
        newToken != oldWidget.initialShareToken) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showSharedPreview(newToken);
      });
    }
  }

  Future<void> refreshFeed() async {
    if (!mounted) return;
    setState(() {
      _publicExperiences.clear();
      _feedItems.clear();
      _mapsPreviewFutures.clear();
      _usedMediaKeys.clear();
      _lastDocument = null;
      _hasMore = true;
      _isFetchingExperiences = false;
      _isLoading = true;
      _isError = false;
      _isPreparingMore = false;
      _errorMessage = null;
      _currentPage = 0;
      _dragDistance = 0;
    });
    await _initializeFeed();
  }

  Future<void> showSharedPreview(String token) async {
    if (!mounted || token.isEmpty) return;
    if (_isLoadingSharedPreview) {
      return;
    }
    if (_lastDisplayedShareToken == token &&
        _pageController.hasClients &&
        _feedItems.isNotEmpty) {
      _maybeAnimateToPage(0);
      return;
    }

    setState(() {
      _isLoadingSharedPreview = true;
    });

    try {
      final DiscoverySharePayload payload =
          await _discoveryShareService.fetchShare(token);
      if (!mounted) return;
      await _integrateSharedPayload(payload);
      _lastDisplayedShareToken = token;
    } catch (e) {
      debugPrint('DiscoveryScreen: Failed to load shared preview ($token): $e');
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Unable to open the shared discovery preview. Please try again.',
          ),
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingSharedPreview = false;
      });
    }
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

  Future<void> _integrateSharedPayload(DiscoverySharePayload payload) async {
    final PublicExperience experience = payload.experience;
    final String mediaUrl = payload.mediaUrl;
    if (mediaUrl.isEmpty) return;

    final _DiscoveryFeedItem newItem = _DiscoveryFeedItem(
      experience: experience,
      mediaUrl: mediaUrl,
    );

    setState(() {
      _feedItems.removeWhere(
        (item) =>
            item.experience.id == experience.id &&
            item.mediaUrl == mediaUrl,
      );
      _feedItems.insert(0, newItem);
      _currentPage = 0;
    });

    await _maybeCheckIfMediaSaved(newItem);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pageController.hasClients &&
          _pageController.position.hasPixels &&
          _pageController.position.haveDimensions) {
        _pageController.jumpToPage(0);
      }
    });
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

      // Skip Yelp, Google Maps, and generic URL previews
      final mediaType = _classifyUrl(mediaUrl);
      if (mediaType == _MediaType.yelp ||
          mediaType == _MediaType.maps ||
          mediaType == _MediaType.generic) {
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

      final _FeedFilterResult filterResult =
          await _evaluateFeedItemVisibility(experience, mediaUrl);

      if (filterResult != _FeedFilterResult.include) {
        if (filterResult == _FeedFilterResult.skipHasAccess) {
          final String? placeId = experience.location.placeId;
          if (placeId != null && placeId.isNotEmpty) {
            _publicExperiences.removeWhere(
              (candidate) => candidate.location.placeId == placeId,
            );
          } else {
            _publicExperiences
                .removeWhere((candidate) => candidate.id == experience.id);
          }
        }
        _usedMediaKeys.add(key);
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

    final feedContent = GestureDetector(
      onVerticalDragStart: (_) {
        _dragDistance = 0;
      },
      onVerticalDragUpdate: (details) {
        final delta = details.primaryDelta ?? 0;
        _dragDistance += delta;
        if (!_pageController.hasClients ||
            !_pageController.position.hasPixels ||
            !_pageController.position.haveDimensions) {
          return;
        }
        final position = _pageController.position;
        final double newOffset = (position.pixels - delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        _pageController.jumpTo(newOffset);
      },
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        final int targetPage = _resolveTargetPageForDragEnd(velocity);
        _maybeAnimateToPage(targetPage);
        _resetDragTracking();
      },
      onVerticalDragCancel: () {
        _maybeAnimateToPage(_currentPage);
        _resetDragTracking();
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

    if (!_isLoadingSharedPreview) {
      return feedContent;
    }

    return Stack(
      children: [
        feedContent,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: true,
            child: Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _maybeAnimateToPage(int targetPage) {
    if (targetPage < 0 || targetPage >= _feedItems.length) {
      return;
    }
    if (!_pageController.hasClients ||
        !_pageController.position.hasPixels ||
        !_pageController.position.haveDimensions) {
      return;
    }
    _pageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  int _resolveTargetPageForDragEnd(double velocity) {
    if (_feedItems.isEmpty) {
      return 0;
    }
    if (velocity < -300 || _dragDistance <= -_dragThreshold) {
      return min(_currentPage + 1, _feedItems.length - 1);
    }
    if (velocity > 300 || _dragDistance >= _dragThreshold) {
      return max(_currentPage - 1, 0);
    }
    return _currentPage;
  }

  void _resetDragTracking() {
    _dragDistance = 0;
  }

  Widget _buildFeedPage(_DiscoveryFeedItem item) {
    final preview = _buildPreviewForItem(item);
    _maybeCheckIfMediaSaved(item);

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
          child: _buildMetadata(item),
        ),
        Positioned(
          right: 16,
          bottom: 32,
          child: _buildActionButtons(item),
        ),
      ],
    );
  }

  Widget _buildMetadata(_DiscoveryFeedItem item) {
    final PublicExperience experience = item.experience;
    final location = experience.location;
    final details = <String>[];

    if ((location.city ?? '').trim().isNotEmpty) {
      details.add(location.city!.trim());
    }
    if ((location.state ?? '').trim().isNotEmpty) {
      details.add(location.state!.trim());
    }

    final subtitle = details.join(', ');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _handleExperienceTap(experience),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  experience.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              FutureBuilder<List<Experience>>(
                future: _getLinkedExperiencesForMedia(item.mediaUrl),
                builder: (context, snapshot) {
                  final experiences = snapshot.data;
                  if (experiences == null || experiences.length <= 1) {
                    return const SizedBox.shrink();
                  }
                  return TextButton(
                    onPressed: () => _showLinkedExperiencesDialog(item),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'and more',
                      style: TextStyle(fontSize: 13),
                    ),
                  );
                },
              ),
            ],
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
      ),
    );
  }

  Widget _buildActionButtons(_DiscoveryFeedItem item) {
    final sourceButton = _buildSourceActionButton(item);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (sourceButton != null) ...[
          sourceButton,
          const SizedBox(height: 16),
        ],
        ValueListenableBuilder<bool?>(
          valueListenable: item.isMediaAlreadySaved,
          builder: (context, isSaved, _) {
            final bool resolvedSaved = isSaved ?? false;
            return _buildActionButton(
              icon: resolvedSaved ? Icons.bookmark : Icons.bookmark_border,
              label: resolvedSaved ? 'Saved' : 'Save',
              onPressed:
                  resolvedSaved ? null : () => _handleBookmarkTapped(item),
            );
          },
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
                  initialPublicExperience: item.experience,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        _buildActionButton(
          icon: Icons.ios_share,
          label: 'Share',
          onPressed:
              _isShareInProgress ? null : () => _handleShareTapped(item),
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
    IconData? icon,
    Widget? iconWidget,
    required String label,
    Color? backgroundColor,
    VoidCallback? onPressed,
  }) {
    assert(icon != null || iconWidget != null,
        '_buildActionButton requires either an IconData or a Widget.');
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

  Future<void> _openReadOnlyExperience(PublicExperience publicExperience) async {
    final Experience draft = _buildExperienceDraft(publicExperience);
    final List<SharedMediaItem> mediaItems =
        publicExperience.buildMediaItemsForPreview();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExperiencePageScreen(
          experience: draft,
          category: _publicReadOnlyCategory,
          userColorCategories: const <ColorCategory>[],
          initialMediaItems: mediaItems,
          readOnlyPreview: true,
        ),
      ),
    );
  }

  Future<void> _handleExperienceTap(PublicExperience publicExperience) async {
    Experience? editableExperience;
    final String? placeId = publicExperience.location.placeId;
    if (placeId != null && placeId.isNotEmpty) {
      editableExperience =
          await _experienceService.findEditableExperienceByPlaceId(placeId);
    }

    if (!mounted) return;

    if (editableExperience != null) {
      await _openEditableExperience(editableExperience);
    } else {
      await _openReadOnlyExperience(publicExperience);
    }
  }

  Future<void> _openEditableExperience(Experience experience) async {
    await _ensureUserCollectionsLoaded();
    final UserCategory category = _resolveCategoryForExperience(experience);
    final List<ColorCategory> colorCategories =
        _userColorCategories.isEmpty
            ? const <ColorCategory>[]
            : _userColorCategories;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExperiencePageScreen(
          experience: experience,
          category: category,
          userColorCategories: colorCategories,
        ),
      ),
    );
  }

  Future<void> _ensureUserCollectionsLoaded() {
    if (_userCollectionsFuture != null) {
      return _userCollectionsFuture!;
    }
    _userCollectionsFuture = _loadUserCollections().whenComplete(() {
      _userCollectionsFuture = null;
    });
    return _userCollectionsFuture!;
  }

  Future<void> _loadUserCollections() async {
    try {
      final categories = await _experienceService.getUserCategories(
        includeSharedEditable: true,
      );
      final colorCategories = await _experienceService.getUserColorCategories(
        includeSharedEditable: true,
      );
      _userCategories = categories;
      _userColorCategories = colorCategories;
    } catch (e) {
      debugPrint('DiscoveryScreen: Failed to load user collections: $e');
    }
  }

  Future<List<Experience>> _getAccessibleExperiencesForPlace(
      String? placeId) {
    if (placeId == null || placeId.isEmpty) {
      return Future.value(const <Experience>[]);
    }

    return _accessibleExperiencesFutures.putIfAbsent(placeId, () async {
      try {
        return await _experienceService.findAccessibleExperiencesByPlaceId(
          placeId,
        );
      } catch (e) {
        debugPrint(
            'DiscoveryScreen: Failed to fetch accessible experiences for $placeId: $e');
        return <Experience>[];
      }
    });
  }

  Future<bool> _userHasViewOrEditAccessToPlace(String? placeId) async {
    final experiences = await _getAccessibleExperiencesForPlace(placeId);
    return experiences.isNotEmpty;
  }

  Future<bool> _hasUserSavedMediaByUrl(String mediaUrl) {
    final String normalizedKey = _normalizeUrlForComparison(mediaUrl);
    if (normalizedKey.isEmpty) {
      return Future.value(false);
    }

    return _savedMediaByUrlFutures.putIfAbsent(normalizedKey, () async {
      try {
        final SharedMediaItem? mediaItem =
            await _experienceService.findSharedMediaItemByPath(mediaUrl);
        if (mediaItem == null || mediaItem.experienceIds.isEmpty) {
          return false;
        }

        final List<Experience> experiences =
            await _experienceService.getExperiencesByIds(
          mediaItem.experienceIds,
        );

        if (experiences.isEmpty) {
          return false;
        }

        for (final experience in experiences) {
          if (_experienceContainsMediaUrl(experience, mediaUrl)) {
            return true;
          }
        }

        return false;
      } catch (e) {
        debugPrint('DiscoveryScreen: Failed to resolve saved media for $mediaUrl: $e');
        return false;
      }
    });
  }

  Future<_FeedFilterResult> _evaluateFeedItemVisibility(
    PublicExperience experience,
    String mediaUrl,
  ) async {
    final bool hasAccess =
        await _userHasViewOrEditAccessToPlace(experience.location.placeId);
    if (hasAccess) {
      return _FeedFilterResult.skipHasAccess;
    }

    final bool alreadySaved = await _hasUserSavedMediaByUrl(mediaUrl);
    if (alreadySaved) {
      return _FeedFilterResult.skipAlreadySaved;
    }

    return _FeedFilterResult.include;
  }

  void _markMediaAsSaved(String mediaUrl) {
    final String normalizedKey = _normalizeUrlForComparison(mediaUrl);
    if (normalizedKey.isEmpty) return;
    _savedMediaByUrlFutures[normalizedKey] = Future.value(true);
  }

  Future<void> _maybeCheckIfMediaSaved(_DiscoveryFeedItem item) async {
    if (item.isMediaAlreadySaved.value != null) {
      return;
    }
    try {
      final bool isSaved = await _hasUserSavedMediaByUrl(item.mediaUrl);
      item.isMediaAlreadySaved.value = isSaved;
    } catch (e) {
      debugPrint('DiscoveryScreen: Failed media check: $e');
      item.isMediaAlreadySaved.value = false;
    }
  }

  bool _experienceContainsMediaUrl(Experience experience, String url) {
    if (url.isEmpty) return false;
    final normalizedUrl = _normalizeUrlForComparison(url);
    if (normalizedUrl.isEmpty) return false;
    if (experience.imageUrls.any((entry) =>
        _normalizeUrlForComparison(entry) == normalizedUrl)) {
      return true;
    }
    // TODO: When shared media metadata includes direct URLs, compare here as well.
    return false;
  }

  String _normalizeUrlForComparison(String? url) {
    if (url == null) return '';
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    final lower = trimmed.toLowerCase();
    final withoutTrailingSlash = lower.endsWith('/')
        ? lower.substring(0, lower.length - 1)
        : lower;
    return withoutTrailingSlash;
  }

  UserCategory _resolveCategoryForExperience(Experience experience) {
    if (experience.categoryId != null) {
      for (final category in _userCategories) {
        if (category.id == experience.categoryId) {
          return category;
        }
      }
    }

    final bool isUncategorized =
        experience.categoryId == null || experience.categoryId!.isEmpty;

    return UserCategory(
      id: experience.categoryId ?? 'uncategorized',
      name: isUncategorized ? 'Uncategorized' : 'Collection',
      icon: '📍',
      ownerUserId: experience.createdBy ?? 'system_default',
    );
  }

  Widget? _buildSourceActionButton(_DiscoveryFeedItem item) {
    final config = _resolveSourceButtonConfig(item.mediaUrl);
    if (config == null) return null;
    return _buildActionButton(
      icon: config.iconData,
      iconWidget: config.iconWidget,
      label: config.label,
      backgroundColor: config.backgroundColor,
      onPressed: () => _launchUrl(item.mediaUrl),
    );
  }

  Future<void> _handleBookmarkTapped(_DiscoveryFeedItem item) async {
    final List<Experience> initialExperiences =
        await _buildInitialExperiencesForSave(item);

    await _openSaveExperiencesSheet(
      initialExperiences: initialExperiences,
      mediaUrl: item.mediaUrl,
      feedItem: item,
    );
  }

  Future<List<Experience>> _buildInitialExperiencesForSave(
    _DiscoveryFeedItem item, {
    List<Experience>? seedExperiences,
  }) async {
    final List<Experience> linkedExperiences =
        List<Experience>.from(seedExperiences ??
            await _getLinkedExperiencesForMedia(item.mediaUrl));

    final List<Experience> dedupedExperiences =
        _dedupeExperiencesById(linkedExperiences);

    if (dedupedExperiences.isEmpty) {
      return [_buildExperienceDraft(item.experience)];
    }

    final bool alreadyContainsPreview = dedupedExperiences.any(
      (exp) => _experienceMatchesPublic(exp, item.experience),
    );
    if (alreadyContainsPreview) {
      return dedupedExperiences;
    }

    final Experience draft = _buildExperienceDraft(item.experience);
    return [...dedupedExperiences, draft];
  }

  Future<void> _openSaveExperiencesSheet({
    required List<Experience> initialExperiences,
    required String mediaUrl,
    _DiscoveryFeedItem? feedItem,
  }) async {
    if (initialExperiences.isEmpty) return;

    final String? resultMessage = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SaveToExperiencesModal(
        initialExperiences: initialExperiences,
        mediaUrl: mediaUrl,
      ),
    );

    if (resultMessage == null || !mounted) return;

    if (feedItem != null) {
      feedItem.isMediaAlreadySaved.value = true;
    }
    _markMediaAsSaved(mediaUrl);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(resultMessage)),
    );
  }

  Future<List<Experience>> _getLinkedExperiencesForMedia(String mediaUrl) {
    if (mediaUrl.isEmpty) {
      return Future.value(const <Experience>[]);
    }

    return _linkedExperiencesFutures.putIfAbsent(mediaUrl, () async {
      try {
        final SharedMediaItem? mediaItem =
            await _experienceService.findSharedMediaItemByPath(mediaUrl);
        if (mediaItem == null || mediaItem.experienceIds.isEmpty) {
          return const <Experience>[];
        }

        final experiences =
            await _experienceService.getExperiencesByIds(mediaItem.experienceIds);
        experiences.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        return experiences;
      } catch (e) {
        debugPrint('Failed to load linked experiences: $e');
        return const <Experience>[];
      }
    });
  }

  Future<void> _showLinkedExperiencesDialog(_DiscoveryFeedItem item) async {
    final mediaUrl = item.mediaUrl;
    if (mediaUrl.isEmpty) return;

    final experiences = await _getLinkedExperiencesForMedia(mediaUrl);
    if (!mounted) return;

    if (experiences.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No additional experiences linked yet.')),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Linked Experiences'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: experiences.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final experience = experiences[index];
                return ListTile(
                  title: Text(experience.name),
                  subtitle: Text(_formatExperienceSubtitle(experience)),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                final initialExperiences =
                    await _buildInitialExperiencesForSave(
                  item,
                  seedExperiences: experiences,
                );
                if (!mounted) return;
                Future.microtask(() {
                  _openSaveExperiencesSheet(
                    initialExperiences: initialExperiences,
                    mediaUrl: mediaUrl,
                    feedItem: item,
                  );
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Save All'),
            ),
          ],
        );
      },
    );
  }

  String _formatExperienceSubtitle(Experience experience) {
    final location = experience.location;
    final parts = <String>[];
    if ((location.city ?? '').trim().isNotEmpty) {
      parts.add(location.city!.trim());
    }
    if ((location.state ?? '').trim().isNotEmpty) {
      parts.add(location.state!.trim());
    }
    if (parts.isEmpty && (location.address ?? '').trim().isNotEmpty) {
      parts.add(location.address!.trim());
    }
    return parts.isNotEmpty ? parts.join(', ') : 'Location details unavailable';
  }

  Experience _buildExperienceDraft(PublicExperience publicExperience) {
    return publicExperience.toExperienceDraft();
  }

  List<Experience> _dedupeExperiencesById(List<Experience> experiences) {
    final Set<String> seen = <String>{};
    final List<Experience> deduped = [];
    for (final exp in experiences) {
      final String key = _experienceCacheKey(exp);
      if (seen.add(key)) {
        deduped.add(exp);
      }
    }
    return deduped;
  }

  String _experienceCacheKey(Experience experience) {
    if (experience.id.isNotEmpty) {
      return experience.id;
    }

    final location = experience.location;
    final buffer = StringBuffer()
      ..write(experience.name.trim().toLowerCase())
      ..write('|')
      ..write(location.placeId?.trim().toLowerCase() ?? '')
      ..write('|')
      ..write((location.address ?? '').trim().toLowerCase());
    return buffer.toString();
  }

  bool _experienceMatchesPublic(
    Experience savedExperience,
    PublicExperience publicExperience,
  ) {
    final String savedPlaceId = savedExperience.location.placeId?.trim() ?? '';
    final String publicPlaceId = publicExperience.placeID.trim();
    if (savedPlaceId.isNotEmpty && publicPlaceId.isNotEmpty) {
      return savedPlaceId == publicPlaceId;
    }

    final String savedName = savedExperience.name.trim().toLowerCase();
    final String publicName = publicExperience.name.trim().toLowerCase();
    if (savedName.isEmpty || publicName.isEmpty) {
      return false;
    }

    final String savedAddress =
        (savedExperience.location.address ?? '').trim().toLowerCase();
    final String publicAddress =
        (publicExperience.location.address ?? '').trim().toLowerCase();

    if (savedAddress.isNotEmpty && publicAddress.isNotEmpty) {
      return savedName == publicName && savedAddress == publicAddress;
    }

    return savedName == publicName;
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

  Future<void> _handleShareTapped(_DiscoveryFeedItem item) async {
    if (_isShareInProgress) return;
    setState(() {
      _isShareInProgress = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final String shareUrl = await _discoveryShareService.createShare(
        experience: item.experience,
        mediaUrl: item.mediaUrl,
      );
      if (!mounted) return;
      final String shareText =
          'Check out this experience from Plendy! $shareUrl';
      await Share.share(shareText);
    } catch (e) {
      debugPrint('DiscoveryScreen: Failed to create share link: $e');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Unable to generate a share link. Please try again.'),
          ),
        );
      }
    } finally {
      if (!mounted) return;
      setState(() {
        _isShareInProgress = false;
      });
    }
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
}

class _DiscoveryFeedItem {
  _DiscoveryFeedItem({
    required this.experience,
    required this.mediaUrl,
  });

  final PublicExperience experience;
  final String mediaUrl;
  final ValueNotifier<bool?> isMediaAlreadySaved = ValueNotifier<bool?>(null);
}

enum _FeedFilterResult {
  include,
  skipHasAccess,
  skipAlreadySaved,
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
