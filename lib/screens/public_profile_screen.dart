import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';

import '../models/experience.dart';
import '../models/user_category.dart';
import '../models/user_profile.dart';
import '../models/color_category.dart';
import '../models/shared_media_item.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/experience_service.dart';
import '../widgets/shared_media_preview_modal.dart';
import 'experience_page_screen.dart';
import 'package:url_launcher/url_launcher.dart';

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

class PublicProfileScreen extends StatefulWidget {
  final String userId;

  const PublicProfileScreen({super.key, required this.userId});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen>
    with SingleTickerProviderStateMixin {
  final UserService _userService = UserService();
  final ExperienceService _experienceService = ExperienceService();

  UserProfile? _profile;
  int _followersCount = 0;
  int _followingCount = 0;
  List<String> _followerIds = [];
  List<String> _followingIds = [];
  List<UserCategory> _publicCategories = [];
  List<ColorCategory> _publicColorCategories = [];
  Map<String, List<Experience>> _categoryExperiences = {};
  bool _isLoading = true;
  bool _isLoadingCollections = true;
  bool _isProcessingFollow = false;
  bool _isFollowing = false;
  bool _ownerFollowsViewer = false;
  bool _hasPendingRequest = false;
  String? _currentUserId;
  bool _initialized = false;
  late final TabController _tabController;
  UserCategory? _selectedCategory;
  
  // Media cache for experience content previews
  final Map<String, List<SharedMediaItem>> _experienceMediaCache = {};
  final Set<String> _mediaPrefetchInFlight = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authService = Provider.of<AuthService>(context);
    final viewerId = authService.currentUser?.uid;
    final shouldLoad = !_initialized || _currentUserId != viewerId;
    _currentUserId = viewerId;
    if (shouldLoad) {
      _initialized = true;
      _loadProfile();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile({bool showFullPageLoader = true}) async {
    if (showFullPageLoader && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final profile = await _userService.getUserProfile(widget.userId);
      final followers = await _userService.getFollowerIds(widget.userId);
      final following = await _userService.getFollowingIds(widget.userId);

      bool isFollowing = false;
      bool ownerFollowsViewer = false;
      bool hasPendingRequest = false;
      final viewerId = _currentUserId;

      if (viewerId != null && viewerId != widget.userId) {
        isFollowing = await _userService.isFollowing(viewerId, widget.userId);
        ownerFollowsViewer =
            await _userService.isFollowing(widget.userId, viewerId);
        hasPendingRequest =
            await _userService.hasPendingRequest(viewerId, widget.userId);
      }

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _followerIds = followers;
        _followingIds = following;
        _followersCount = followers.length;
        _followingCount = following.length;
        _isFollowing = isFollowing;
        _ownerFollowsViewer = ownerFollowsViewer;
        _hasPendingRequest = hasPendingRequest;
        _isLoading = false;
      });
      await _loadPublicCollections();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to load public profile. Please try again.')),
      );
    }
  }

  Future<void> _loadPublicCollections() async {
    if (!mounted) return;
    setState(() => _isLoadingCollections = true);
    try {
      // Load categories and experiences - color categories may fail due to permissions
      final categoriesSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('categories')
          .get();

      final experiencesSnapshot = await FirebaseFirestore.instance
          .collection('experiences')
          .where('createdBy', isEqualTo: widget.userId)
          .get();

      final List<UserCategory> categories = [];
      for (final doc in categoriesSnapshot.docs) {
        try {
          final category = UserCategory.fromFirestore(doc);
          if (category.isPrivate) continue;
          categories.add(category);
        } catch (e) {
          debugPrint(
              'PublicProfileScreen: skipping invalid category ${doc.id} - $e');
        }
      }

      categories.sort((a, b) {
        final aIndex = a.orderIndex ?? 999999;
        final bIndex = b.orderIndex ?? 999999;
        if (aIndex != bIndex) {
          return aIndex.compareTo(bIndex);
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      // Try to load color categories, but continue if permission denied
      final List<ColorCategory> colorCategories = [];
      try {
        final colorCategoriesSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .collection('colorCategories')
            .get();

        for (final doc in colorCategoriesSnapshot.docs) {
          try {
            final colorCategory = ColorCategory.fromFirestore(doc);
            if (colorCategory.isPrivate) continue;
            colorCategories.add(colorCategory);
          } catch (e) {
            debugPrint(
                'PublicProfileScreen: skipping invalid color category ${doc.id} - $e');
          }
        }
      } catch (e) {
        // Permission denied or other error - just skip color categories
        debugPrint(
            'PublicProfileScreen: Could not load color categories (likely permission denied) - $e');
      }

      final List<Experience> experiences = [];
      for (final doc in experiencesSnapshot.docs) {
        try {
          final experience = Experience.fromFirestore(doc);
          if (experience.isPrivate) continue;
          experiences.add(experience);
        } catch (e) {
          debugPrint(
              'PublicProfileScreen: skipping invalid experience ${doc.id} - $e');
        }
      }

      final Map<String, List<Experience>> catExperiences = {
        for (final category in categories) category.id: []
      };
      final categoryIds = catExperiences.keys.toSet();

      for (final experience in experiences) {
        final Set<String> relevantCategoryIds = {
          if (experience.categoryId != null) experience.categoryId!,
          ...experience.otherCategories,
        };
        for (final categoryId in relevantCategoryIds) {
          if (!categoryIds.contains(categoryId)) continue;
          catExperiences[categoryId]!.add(experience);
        }
      }

      if (!mounted) return;
      setState(() {
        _publicCategories = categories;
        _publicColorCategories = colorCategories;
        _categoryExperiences = catExperiences;
        _isLoadingCollections = false;
      });
    } catch (e) {
      debugPrint('PublicProfileScreen: error loading collections - $e');
      if (!mounted) return;
      setState(() {
        _publicCategories = [];
        _publicColorCategories = [];
        _categoryExperiences = {};
        _isLoadingCollections = false;
      });
    }
  }

  Future<void> _handleFollowButton() async {
    if (_currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to follow users.')),
      );
      return;
    }

    setState(() {
      _isProcessingFollow = true;
    });

    try {
      if (_isFollowing) {
        await _userService.unfollowUser(_currentUserId!, widget.userId);
      } else {
        await _userService.followUser(_currentUserId!, widget.userId);
      }
      await _loadProfile(showFullPageLoader: false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Unable to update follow status. ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingFollow = false;
        });
      }
    }
  }

  Future<void> _prefetchExperienceMedia(Experience experience) async {
    if (experience.sharedMediaItemIds.isEmpty) {
      return;
    }
    if (_experienceMediaCache.containsKey(experience.id)) {
      return;
    }
    if (_mediaPrefetchInFlight.contains(experience.id)) {
      return;
    }
    _mediaPrefetchInFlight.add(experience.id);
    try {
      final items = await _experienceService
          .getSharedMediaItems(experience.sharedMediaItemIds);
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _experienceMediaCache[experience.id] = items;
      });
    } catch (e) {
      debugPrint('Error prefetching media for ${experience.name}: $e');
    } finally {
      _mediaPrefetchInFlight.remove(experience.id);
    }
  }

  Future<void> _navigateToExperience(
      Experience experience, UserCategory category) async {
    // Navigate to experience page in read-only mode
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => ExperiencePageScreen(
          experience: experience,
          category: category,
          userColorCategories: _publicColorCategories,
          readOnlyPreview: true,
        ),
      ),
    );
    
    if (result == true && mounted) {
      // Reload data if changes were made
      await _loadPublicCollections();
    }
  }

  Future<void> _showMediaPreview(
      Experience experience, UserCategory category) async {
    final List<SharedMediaItem>? cachedItems =
        _experienceMediaCache[experience.id];
    late final List<SharedMediaItem> resolvedItems;

    if (cachedItems == null) {
      if (experience.sharedMediaItemIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('No saved content available yet for this experience.')),
          );
        }
        return;
      }
      try {
        final fetched = await _experienceService
            .getSharedMediaItems(experience.sharedMediaItemIds);
        fetched.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        resolvedItems = fetched;
        if (mounted) {
          setState(() {
            _experienceMediaCache[experience.id] = fetched;
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not load content preview: $e')),
          );
        }
        return;
      }
    } else {
      resolvedItems = cachedItems;
    }

    if (resolvedItems.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('No saved content available yet for this experience.')),
        );
      }
      return;
    }

    if (!mounted) return;

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
          userColorCategories: _publicColorCategories,
        );
      },
    );
  }

  Future<void> _launchUrl(String urlString) async {
    // Skip invalid URLs
    if (urlString.isEmpty ||
        urlString == 'about:blank' ||
        urlString == 'https://about:blank') {
      return;
    }

    // Ensure URL starts with http/https
    String launchableUrl = urlString;
    if (!launchableUrl.startsWith('http://') &&
        !launchableUrl.startsWith('https://')) {
      launchableUrl = 'https://$launchableUrl';
    }

    try {
      final Uri uri = Uri.parse(launchableUrl);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open link: $urlString')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid URL: $urlString')),
        );
      }
    }
  }

  String _getProfileInitial(UserProfile profile) {
    final displayName = profile.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName[0].toUpperCase();
    }
    final username = profile.username?.trim();
    if (username != null && username.isNotEmpty) {
      return username[0].toUpperCase();
    }
    return '?';
  }

  Widget _buildAvatar(UserProfile profile) {
    final photoURL = profile.photoURL;
    final fallbackLetter = _getProfileInitial(profile);

    return CircleAvatar(
      radius: 60,
      backgroundImage: (photoURL != null && photoURL.isNotEmpty)
          ? NetworkImage(photoURL)
          : null,
      backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
      child: (photoURL == null || photoURL.isEmpty)
          ? Text(
              fallbackLetter,
              style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
            )
          : null,
    );
  }

  Widget _buildCountTile({
    required String label,
    required int count,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$count',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<UserProfile>> _fetchProfiles(List<String> userIds) async {
    if (userIds.isEmpty) return [];
    final profiles = await Future.wait(
      userIds.map((id) => _userService.getUserProfile(id)),
    );
    return profiles.whereType<UserProfile>().toList();
  }

  Widget _buildProfileAvatar(UserProfile profile, {double size = 40}) {
    final radius = size / 2;
    final photoUrl = profile.photoURL;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(photoUrl),
      );
    }

    final fallbackLetter = _getProfileInitial(profile);

    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey.shade300,
      child: Text(
        fallbackLetter,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Colors.black87,
          fontSize: radius * 0.9,
        ),
      ),
    );
  }

  void _showProfilePhotoDialog(UserProfile profile) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final photoUrl = profile.photoURL;
        final hasPhoto = photoUrl?.isNotEmpty ?? false;
        final fallbackLetter = _getProfileInitial(profile);
        final Widget photoContent = hasPhoto
            ? InteractiveViewer(
                child: Image.network(
                  photoUrl!,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Center(child: CircularProgressIndicator());
                  },
                  errorBuilder: (context, _, __) {
                    return Center(
                      child: Text(
                        fallbackLetter,
                        style: const TextStyle(
                          fontSize: 100,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    );
                  },
                ),
              )
            : Center(
                child: Text(
                  fallbackLetter,
                  style: const TextStyle(
                    fontSize: 100,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              );

        return Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  color: Colors.black,
                  width: double.infinity,
                  height: 320,
                  alignment: Alignment.center,
                  child: photoContent,
                ),
                Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Center(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Theme.of(context).primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        child: Text('Close'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showUserListDialog({
    required String title,
    required List<String> userIds,
    required String emptyMessage,
  }) async {
    final parentContext = context;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final maxHeight = MediaQuery.of(dialogContext).size.height * 0.6;
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: FutureBuilder<List<UserProfile>>(
                future: _fetchProfiles(userIds),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final profiles = snapshot.data ?? [];
                  if (profiles.isEmpty) {
                    return Center(
                      child: Text(
                        emptyMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: profiles.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final profile = profiles[index];
                      final bool hasDisplayName =
                          profile.displayName?.isNotEmpty ?? false;
                      final bool hasUsername =
                          profile.username?.isNotEmpty ?? false;
                      final String titleText = hasDisplayName
                          ? profile.displayName!
                          : (hasUsername
                              ? '@${profile.username!}'
                              : 'Plendy user');
                      final String? subtitleText = hasDisplayName && hasUsername
                          ? '@${profile.username!}'
                          : null;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _buildProfileAvatar(profile),
                        title: Text(titleText),
                        subtitle:
                            subtitleText != null ? Text(subtitleText) : null,
                        onTap: () {
                          Navigator.of(dialogContext).pop();
                          Navigator.of(parentContext).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  PublicProfileScreen(userId: profile.id),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openFollowingDialog() async {
    await _showUserListDialog(
      title: 'Following',
      userIds: _followingIds,
      emptyMessage: 'Not following anyone yet.',
    );
  }

  Future<void> _openFollowersDialog() async {
    await _showUserListDialog(
      title: 'Followers',
      userIds: _followerIds,
      emptyMessage: 'No one follows this profile yet.',
    );
  }

  Widget _buildFollowButton() {
    if (_currentUserId == null || _currentUserId == widget.userId) {
      return const SizedBox.shrink();
    }

    String label;
    Color backgroundColor;
    Color foregroundColor;
    VoidCallback? onPressed = _handleFollowButton;

    if (_isFollowing) {
      label = 'Unfollow';
      backgroundColor = Colors.grey[200]!;
      foregroundColor = Colors.black87;
    } else if (_hasPendingRequest) {
      label = 'Requested';
      backgroundColor = Colors.grey[300]!;
      foregroundColor = Colors.black54;
      onPressed = null;
    } else if (_ownerFollowsViewer) {
      label = 'Follow back';
      backgroundColor = Theme.of(context).primaryColor;
      foregroundColor = Colors.white;
    } else {
      label = 'Follow';
      backgroundColor = Theme.of(context).primaryColor;
      foregroundColor = Colors.white;
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed:
            (_isProcessingFollow || onPressed == null) ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: backgroundColor,
          disabledForegroundColor: foregroundColor,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: _isProcessingFollow
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: foregroundColor),
              )
            : Text(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final bool viewingOwnProfile =
        _currentUserId != null && _currentUserId == widget.userId;

    Widget content;
    if (_isLoading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (profile == null) {
      content = const Center(child: Text('This profile is not available.'));
    } else {
      final bool hasDisplayName = profile.displayName?.isNotEmpty ?? false;
      final bool hasUsername = profile.username?.isNotEmpty ?? false;
      final String? bioText = profile.bio?.trim();
      final bool hasBio = bioText?.isNotEmpty ?? false;
      final bool hasIdentityText = hasDisplayName || hasUsername;
      content = SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _showProfilePhotoDialog(profile),
                  child: _buildAvatar(profile),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasDisplayName)
                        Text(
                          profile.displayName!,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      if (hasDisplayName) const SizedBox(height: 4),
                      if (hasUsername)
                        Text(
                          '@${profile.username!}',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      if (hasIdentityText) const SizedBox(height: 8),
                      if (hasIdentityText) const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildCountTile(
                              label: 'Following',
                              count: _followingCount,
                              onTap: _openFollowingDialog,
                            ),
                          ),
                          Expanded(
                            child: _buildCountTile(
                              label: 'Followers',
                              count: _followersCount,
                              onTap: _openFollowersDialog,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildFollowButton(),
            if (hasBio) ...[
              const SizedBox(height: 24),
              Text(
                bioText!,
                style: const TextStyle(fontSize: 16),
              ),
            ],
            const SizedBox(height: 24),
            _buildProfileTabs(),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: viewingOwnProfile ? const Text('Public Profile') : null,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(child: content),
    );
  }

  Widget _buildProfileTabs() {
    final theme = Theme.of(context);
    final tabBar = TabBar(
      controller: _tabController,
      labelColor: theme.primaryColor,
      unselectedLabelColor: Colors.grey[600],
      indicatorColor: theme.primaryColor,
      tabs: const [
        Tab(
          icon: Icon(Icons.collections_outlined),
          text: 'Collection',
        ),
        Tab(
          icon: Icon(Icons.rate_review_outlined),
          text: 'Reviews',
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tabBar,
        const SizedBox(height: 12),
        SizedBox(
          height: 400,
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildCollectionTab(),
              const Center(child: Text('Reviews coming soon.')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCollectionTab() {
    // Show either categories list OR selected category's experiences
    if (_selectedCategory != null) {
      return _buildSelectedCategoryExperiencesView();
    }

    return _buildPublicCategoriesList();
  }

  Widget _buildPublicCategoriesList() {
    if (_isLoadingCollections) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_publicCategories.isEmpty) {
      return const Center(child: Text('No public categories to share yet.'));
    }

    final bool isDesktopWeb = MediaQuery.of(context).size.width > 600;

    if (isDesktopWeb) {
      // Desktop: Grid view
      final screenWidth = MediaQuery.of(context).size.width;
      const double contentMaxWidth = 1200.0;
      const double defaultPadding = 12.0;

      double horizontalPadding;
      if (screenWidth > contentMaxWidth) {
        horizontalPadding = (screenWidth - contentMaxWidth) / 2;
      } else {
        horizontalPadding = defaultPadding;
      }

      return GridView.builder(
        padding: EdgeInsets.fromLTRB(
            horizontalPadding, defaultPadding, horizontalPadding, defaultPadding),
        itemCount: _publicCategories.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: 10.0,
          crossAxisSpacing: 10.0,
          childAspectRatio: 3 / 3.5,
        ),
        itemBuilder: (context, index) {
          final category = _publicCategories[index];
          final experiences = _categoryExperiences[category.id] ?? [];
          final bool isSelected = _selectedCategory?.id == category.id;

          return Card(
            key: ValueKey('category_grid_${category.id}'),
            clipBehavior: Clip.antiAlias,
            elevation: 2.0,
            color: isSelected ? Theme.of(context).primaryColor.withOpacity(0.1) : null,
            shape: isSelected
                ? RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4.0),
                    side: BorderSide(
                      color: Theme.of(context).primaryColor,
                      width: 2,
                    ),
                  )
                : null,
            child: InkWell(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedCategory = null;
                  } else {
                    _selectedCategory = category;
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      category.icon,
                      style: const TextStyle(fontSize: 32),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      category.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${experiences.length} ${experiences.length == 1 ? "exp" : "exps"}',
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } else {
      // Mobile: List view
      return ListView.separated(
        itemCount: _publicCategories.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final category = _publicCategories[index];
          final experiences = _categoryExperiences[category.id] ?? [];
          final bool isSelected = _selectedCategory?.id == category.id;

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: Padding(
              padding: const EdgeInsets.only(left: 4, right: 8),
              child: Text(
                category.icon,
                style: const TextStyle(fontSize: 24),
              ),
            ),
            title: Text(category.name),
            subtitle: Text(
              '${experiences.length} ${experiences.length == 1 ? 'experience' : 'experiences'}',
            ),
            trailing: isSelected
                ? Icon(Icons.check_circle, color: Theme.of(context).primaryColor)
                : null,
            selected: isSelected,
            onTap: () {
              setState(() {
                if (isSelected) {
                  _selectedCategory = null;
                } else {
                  _selectedCategory = category;
                }
              });
            },
          );
        },
      );
    }
  }

  Widget _buildExperienceListItem(Experience experience, UserCategory category) {
    final categoryIcon = category.icon;

    // Get the full address
    final fullAddress = experience.location.address;
    
    // Determine leading box background color from color category with opacity
    final colorCategoryForBox = _publicColorCategories.firstWhereOrNull(
      (cc) => cc.id == experience.colorCategoryId,
    );
    final Color leadingBoxColor = colorCategoryForBox != null
        ? _parseColor(colorCategoryForBox.colorHex).withOpacity(0.5)
        : Colors.white;

    // Number of related content items
    final int contentCount = experience.sharedMediaItemIds.length;

    const double playButtonDiameter = 36.0;
    const double playIconSize = 20.0;
    const double badgeDiameter = 18.0;
    const double badgeFontSize = 11.0;
    const double badgeBorderWidth = 2.0;
    const double badgeOffset = -3.0;

    final List<ColorCategory> otherColorCategories = experience
        .otherColorCategoryIds
        .map((id) => _publicColorCategories.firstWhereOrNull((cc) => cc.id == id))
        .whereType<ColorCategory>()
        .toList();
    final bool hasOtherCategories = experience.otherCategories.isNotEmpty;
    final bool hasOtherColorCategories = otherColorCategories.isNotEmpty;
    final bool hasNotes = experience.additionalNotes != null &&
        experience.additionalNotes!.isNotEmpty;
    final bool shouldShowSubRow = hasOtherCategories ||
        hasOtherColorCategories ||
        contentCount > 0 ||
        (hasNotes && !hasOtherCategories && !hasOtherColorCategories);

    final Widget leadingWidget = Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: leadingBoxColor,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                categoryIcon,
                style: const TextStyle(fontSize: 28),
              ),
            ],
          ),
        ),
      ),
    );

    return ListTile(
      key: ValueKey(experience.id),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8.0),
      visualDensity: const VisualDensity(horizontal: -4),
      isThreeLine: true,
      titleAlignment: ListTileTitleAlignment.threeLine,
      leading: leadingWidget,
      minLeadingWidth: 56,
      title: Text(
        experience.name,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fullAddress != null && fullAddress.isNotEmpty)
            Text(
              fullAddress,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          // Row for subcategory icons and/or content count
          if (shouldShowSubRow)
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasOtherCategories || hasOtherColorCategories)
                          Wrap(
                            spacing: 6.0,
                            runSpacing: 2.0,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ...experience.otherCategories.map((categoryId) {
                                final otherCategory =
                                    _publicCategories.firstWhereOrNull(
                                  (cat) => cat.id == categoryId,
                                );
                                if (otherCategory != null) {
                                  return Text(
                                    otherCategory.icon,
                                    style: const TextStyle(fontSize: 14),
                                  );
                                }
                                return const SizedBox.shrink();
                              }),
                              ...otherColorCategories.map((colorCategory) {
                                final Color chipColor = colorCategory.color;
                                return Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: chipColor,
                                    shape: BoxShape.circle,
                                  ),
                                );
                              }),
                            ],
                          ),
                        if (experience.additionalNotes != null &&
                            experience.additionalNotes!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(Icons.notes,
                                    size: 14, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    experience.additionalNotes!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(fontStyle: FontStyle.italic),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (contentCount > 0) ...[
                    const SizedBox(width: 12),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () async {
                        // Prefetch media if not cached, then show preview
                        if (!_experienceMediaCache.containsKey(experience.id)) {
                          await _prefetchExperienceMedia(experience);
                        }
                        await _showMediaPreview(experience, category);
                      },
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: playButtonDiameter,
                            height: playButtonDiameter,
                            decoration: BoxDecoration(
                              color: Theme.of(context).primaryColor,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              size: playIconSize,
                            ),
                          ),
                          Positioned(
                            bottom: badgeOffset,
                            right: badgeOffset,
                            child: Container(
                              width: badgeDiameter,
                              height: badgeDiameter,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Theme.of(context).primaryColor,
                                  width: badgeBorderWidth,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  contentCount.toString(),
                                  style: TextStyle(
                                    color: Theme.of(context).primaryColor,
                                    fontSize: badgeFontSize,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
      onTap: () async {
        // Prefetch media in background for faster loading
        if (contentCount > 0 &&
            !_experienceMediaCache.containsKey(experience.id)) {
          unawaited(_prefetchExperienceMedia(experience));
        }
        await _navigateToExperience(experience, category);
      },
    );
  }

  Widget _buildSelectedCategoryExperiencesView() {
    final category = _selectedCategory!;
    final experiences = _categoryExperiences[category.id] ?? <Experience>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row with back button and category name
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to Categories',
                onPressed: () {
                  setState(() {
                    _selectedCategory = null;
                  });
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      child: Center(child: Text(category.icon)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        category.name,
                        style: Theme.of(context).textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // List of experiences for this category
        Expanded(
          child: experiences.isEmpty
              ? Center(
                  child: Text(
                    'No public experiences in "${category.name}" yet.',
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: experiences.length,
                  itemBuilder: (context, index) {
                    final experience = experiences[index];
                    return _buildExperienceListItem(experience, category);
                  },
                ),
        ),
      ],
    );
  }
}
