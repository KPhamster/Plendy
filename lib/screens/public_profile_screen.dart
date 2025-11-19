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

  Widget _buildAvatar(UserProfile profile) {
    final photoURL = profile.photoURL;
    final displayName = profile.displayName?.trim() ?? '';
    String fallbackLetter = '?';
    if (displayName.isNotEmpty) {
      fallbackLetter = displayName[0].toUpperCase();
    } else if (profile.username?.isNotEmpty ?? false) {
      fallbackLetter = profile.username![0].toUpperCase();
    }

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

  Widget _buildCountTile(String label, int count) {
    return Column(
      children: [
        Text(
          '$count',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(color: Colors.grey[600], fontSize: 14),
        ),
      ],
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

    Widget content;
    if (_isLoading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (profile == null) {
      content = const Center(child: Text('This profile is not available.'));
    } else {
      final bool hasDisplayName = profile.displayName?.isNotEmpty ?? false;
      final bool hasUsername = profile.username?.isNotEmpty ?? false;
      content = SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAvatar(profile),
                const SizedBox(width: 16),
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
                      if (hasDisplayName || hasUsername)
                        const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Expanded(
                                child: _buildCountTile(
                                    'Following', _followingCount)),
                            Container(
                              width: 1,
                              height: 32,
                              color: Colors.grey[300],
                            ),
                            Expanded(
                                child: _buildCountTile(
                                    'Followers', _followersCount)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildFollowButton(),
            if (_currentUserId == widget.userId)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(
                  'This is how other users see your public profile.',
                  style: TextStyle(color: theme.hintColor),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Public Profile'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(child: content),
    );
  }
}
