import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/user_service.dart';
import '../services/notification_state_service.dart';
import '../services/my_people_preload_service.dart';
import '../widgets/notification_dot.dart';
import '../widgets/cached_profile_avatar.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'package:plendy/utils/haptic_feedback.dart';

class UserListTab extends StatefulWidget {
  final List<String> userIds;
  final UserService userService;
  final String emptyListMessage;
  final String listType;
  final VoidCallback? onActionCompleted;
  final void Function(String userId)? onUserTap;

  const UserListTab({
    super.key,
    required this.userIds,
    required this.userService,
    this.emptyListMessage = "No users found.",
    required this.listType,
    this.onActionCompleted,
    this.onUserTap,
  });

  @override
  State<UserListTab> createState() => _UserListTabState();
}

class _UserListTabState extends State<UserListTab>
    with AutomaticKeepAliveClientMixin {
  List<UserProfile> _userProfiles = [];
  bool _isLoadingProfiles = true; // Start as true to prevent flash of empty state
  bool _hasInitialized = false;
  String? _currentUserId;

  Map<String, bool> _isFollowingStatus = {};
  Map<String, bool> _isButtonLoading = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Try to populate from cache synchronously to prevent flash of empty state
    _initializeFromCache();
  }
  
  /// Synchronously initialize profiles from cache if available
  void _initializeFromCache() {
    if (widget.userIds.isEmpty) {
      _isLoadingProfiles = false;
      return;
    }
    
    final preloadService = MyPeoplePreloadService();
    final cachedProfiles = preloadService.cachedProfiles;
    
    // Check if all profiles are cached
    bool allCached = widget.userIds.every((id) => cachedProfiles.containsKey(id));
    
    if (allCached && widget.userIds.isNotEmpty) {
      // Populate profiles synchronously from cache
      _userProfiles = widget.userIds
          .map((id) => cachedProfiles[id])
          .whereType<UserProfile>()
          .toList();
      _isLoadingProfiles = false;
    }
    // If not all cached, _isLoadingProfiles stays true until async load completes
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authService = Provider.of<AuthService>(context, listen: false);
    final newUserId = authService.currentUser?.uid;
    if (_currentUserId != newUserId) {
      _currentUserId = newUserId;
      // Load following status (profiles may already be populated from cache)
      _loadUserProfilesAndFollowStatus();
      _hasInitialized = true;
    } else if (!_hasInitialized && widget.userIds.isNotEmpty) {
      // First time initialization - load following status for cached profiles
      _loadUserProfilesAndFollowStatus();
      _hasInitialized = true;
    }
  }

  @override
  void didUpdateWidget(covariant UserListTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool userIdsChanged = widget.userIds.length != oldWidget.userIds.length ||
        !widget.userIds.every((id) => oldWidget.userIds.contains(id));

    if (userIdsChanged) {
      // Try to populate from cache first to prevent flash
      _initializeFromCache();
      _loadUserProfilesAndFollowStatus();
    }
  }

  Future<void> _loadUserProfilesAndFollowStatus() async {
    if (widget.userIds.isEmpty) {
      if (mounted) {
        setState(() {
          _userProfiles = [];
          _isFollowingStatus = {};
          _isLoadingProfiles = false;
        });
      }
      return;
    }

    final preloadService = MyPeoplePreloadService();
    final cachedProfiles = preloadService.cachedProfiles;
    
    // Check which profiles we already have cached
    final cachedUserIds = <String>[];
    final uncachedUserIds = <String>[];
    
    for (final userId in widget.userIds) {
      if (cachedProfiles.containsKey(userId)) {
        cachedUserIds.add(userId);
      } else {
        uncachedUserIds.add(userId);
      }
    }
    
    // If we have all profiles cached (or already loaded from initState), 
    // just load following status without showing loading spinner
    if (uncachedUserIds.isEmpty && (cachedUserIds.isNotEmpty || _userProfiles.isNotEmpty)) {
      // Use existing profiles if already populated, otherwise get from cache
      List<UserProfile> profiles = _userProfiles.isNotEmpty 
          ? _userProfiles 
          : widget.userIds
              .map((id) => cachedProfiles[id])
              .whereType<UserProfile>()
              .toList();
      
      // Load following status in parallel (don't show loading for this)
      Map<String, bool> followingStatus = {};
      if (_currentUserId != null) {
        final followingFutures = widget.userIds
            .where((userId) => userId != _currentUserId)
            .map((userId) async {
              final isFollowing = await widget.userService.isFollowing(_currentUserId!, userId);
              return MapEntry(userId, isFollowing);
            }).toList();
        
        final followingResults = await Future.wait(followingFutures);
        followingStatus = Map.fromEntries(followingResults);
      }
      
      if (mounted) {
        setState(() {
          _userProfiles = profiles;
          _isFollowingStatus = followingStatus;
          _isLoadingProfiles = false;
        });
      }
      return;
    }

    // Show loading only if we need to fetch profiles AND don't have any yet
    if (mounted && _userProfiles.isEmpty) {
      setState(() {
        _isLoadingProfiles = true;
        _isButtonLoading = {};
      });
    }

    // Load uncached profiles in parallel
    List<UserProfile?> uncachedResults = [];
    if (uncachedUserIds.isNotEmpty) {
      final profileFutures = uncachedUserIds.map((userId) => 
        widget.userService.getUserProfile(userId)
      ).toList();
      uncachedResults = await Future.wait(profileFutures);
    }
    
    // Combine cached and newly loaded profiles in original order
    List<UserProfile> profiles = [];
    List<String> validUserIds = [];
    int uncachedIndex = 0;
    
    for (final userId in widget.userIds) {
      UserProfile? profile;
      if (cachedProfiles.containsKey(userId)) {
        profile = cachedProfiles[userId];
      } else if (uncachedIndex < uncachedResults.length) {
        profile = uncachedResults[uncachedIndex];
        uncachedIndex++;
      }
      
      if (profile != null) {
        profiles.add(profile);
        validUserIds.add(userId);
      }
    }

    // Load following status in parallel for all valid users
    Map<String, bool> followingStatus = {};
    if (_currentUserId != null) {
      final followingFutures = validUserIds
          .where((userId) => userId != _currentUserId)
          .map((userId) async {
            final isFollowing = await widget.userService.isFollowing(_currentUserId!, userId);
            return MapEntry(userId, isFollowing);
          }).toList();
      
      final followingResults = await Future.wait(followingFutures);
      followingStatus = Map.fromEntries(followingResults);
    }

    if (mounted) {
      setState(() {
        _userProfiles = profiles;
        _isFollowingStatus = followingStatus;
        _isLoadingProfiles = false;
      });
    }
  }

  Future<void> _toggleFollow(String targetUserId, bool currentlyFollowing) async {
    if (_currentUserId == null) {
      print('DEBUG: _toggleFollow called but _currentUserId is null');
      return;
    }

    print('DEBUG: _toggleFollow called - currentUserId: $_currentUserId, targetUserId: $targetUserId, currentlyFollowing: $currentlyFollowing');

    setState(() {
      _isButtonLoading[targetUserId] = true;
    });

    try {
      if (currentlyFollowing) {
        print('DEBUG: Calling unfollowUser...');
        await widget.userService.unfollowUser(_currentUserId!, targetUserId);
      } else {
        print('DEBUG: Calling followUser...');
        await widget.userService.followUser(_currentUserId!, targetUserId);
      }
      if (mounted) {
        setState(() {
          _isFollowingStatus[targetUserId] = !currentlyFollowing;
        });
      }
      // Invalidate preload cache since follow relationships changed
      MyPeoplePreloadService().invalidateCache();
      widget.onActionCompleted?.call();
      print('DEBUG: _toggleFollow completed successfully');
    } catch (e) {
      print('DEBUG: _toggleFollow failed with error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Action failed: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isButtonLoading[targetUserId] = false;
        });
      }
    }
  }

  Widget _buildActionButton(UserProfile userProfile) {
    if (_currentUserId == null || _currentUserId == userProfile.id) {
      return const SizedBox.shrink();
    }

    if (_isButtonLoading[userProfile.id] == true) {
      return const SizedBox(
          width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2));
    }

    bool isCurrentlyFollowing = _isFollowingStatus[userProfile.id] ?? false;

    if (widget.listType == "friends") {
      return ElevatedButton(
        onPressed: () => _toggleFollow(userProfile.id, true),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[300], foregroundColor: Colors.black),
        child: const Text("Remove"),
      );
    } else if (widget.listType == "followers") {
      if (isCurrentlyFollowing) {
        return ElevatedButton(
          onPressed: () => _toggleFollow(userProfile.id, true),
          child: const Text("Unfollow"),
        );
      } else {
        return ElevatedButton(
          onPressed: () => _toggleFollow(userProfile.id, false),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
          ),
          child: const Text("Follow Back"),
        );
      }
    } else if (widget.listType == "following") {
      return ElevatedButton(
        onPressed: () => _toggleFollow(userProfile.id, true),
        child: const Text("Unfollow"),
      );
    }
    return ElevatedButton(
      onPressed: () => _toggleFollow(userProfile.id, isCurrentlyFollowing),
      child: Text(isCurrentlyFollowing ? "Unfollow" : "Follow"),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    if (_isLoadingProfiles) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_userProfiles.isEmpty) {
      return Center(child: Text(widget.emptyListMessage));
    }

    return Consumer<NotificationStateService>(
      builder: (context, notificationService, child) {
        return ListView.builder(
          itemCount: _userProfiles.length,
          itemBuilder: (context, index) {
            final userProfile = _userProfiles[index];
            
            // Check if this user is unseen (only for followers tab)
            bool isUnseen = widget.listType == "followers" && 
                           notificationService.unseenFollowerIds.contains(userProfile.id);
            
            // Prepare display name and username strings (same as search results)
            String displayName = userProfile.displayName?.isNotEmpty ?? false
                ? userProfile.displayName!
                : (userProfile.username ?? 'Unknown User'); // Fallback for title if display name is empty
            String username = userProfile.username?.isNotEmpty ?? false
                ? '@${userProfile.username!}'
                : '@unknown'; // Fallback for subtitle if username is empty
            bool showUsernameAsSubtitle = userProfile.displayName?.isNotEmpty ?? false; 
            
            return ListTile(
              leading: ProfilePictureNotificationDot(
                profilePicture: CachedProfileAvatar(
                  photoUrl: userProfile.photoURL,
                  fallbackText: displayName.isNotEmpty ? displayName[0].toUpperCase() : null,
                ),
                showDot: isUnseen,
              ),
              title: Text(displayName),
              subtitle: showUsernameAsSubtitle ? Text(username) : null,
              trailing: _buildActionButton(userProfile),
              onTap: withHeavyTap(() => widget.onUserTap?.call(userProfile.id)),
            );
          },
        );
      },
    );
  }
} 
