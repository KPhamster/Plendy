import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';

class PublicProfileScreen extends StatefulWidget {
  final String userId;

  const PublicProfileScreen({super.key, required this.userId});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  final UserService _userService = UserService();

  UserProfile? _profile;
  int _followersCount = 0;
  int _followingCount = 0;
  List<String> _followerIds = [];
  List<String> _followingIds = [];
  bool _isLoading = true;
  bool _isProcessingFollow = false;
  bool _isFollowing = false;
  bool _ownerFollowsViewer = false;
  bool _hasPendingRequest = false;
  String? _currentUserId;
  bool _initialized = false;

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
    final theme = Theme.of(context);
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
}
