import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/user_service.dart';
import '../services/notification_state_service.dart';
import '../widgets/notification_dot.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class UserListTab extends StatefulWidget {
  final List<String> userIds;
  final UserService userService;
  final String emptyListMessage;
  final String listType;
  final VoidCallback? onActionCompleted;

  const UserListTab({
    super.key,
    required this.userIds,
    required this.userService,
    this.emptyListMessage = "No users found.",
    required this.listType,
    this.onActionCompleted,
  });

  @override
  State<UserListTab> createState() => _UserListTabState();
}

class _UserListTabState extends State<UserListTab> {
  List<UserProfile> _userProfiles = [];
  bool _isLoadingProfiles = false;
  String? _currentUserId;

  Map<String, bool> _isFollowingStatus = {};
  Map<String, bool> _isButtonLoading = {};

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authService = Provider.of<AuthService>(context, listen: false);
    final newUserId = authService.currentUser?.uid;
    if (_currentUserId != newUserId) {
      _currentUserId = newUserId;
      _loadUserProfilesAndFollowStatus();
    } else if (widget.userIds.isNotEmpty && _userProfiles.isEmpty && !_isLoadingProfiles) {
      _loadUserProfilesAndFollowStatus();
    }
  }

  @override
  void didUpdateWidget(covariant UserListTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool userIdsChanged = widget.userIds.length != oldWidget.userIds.length ||
        !widget.userIds.every((id) => oldWidget.userIds.contains(id));

    if (userIdsChanged) {
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

    if (mounted) {
      setState(() {
        _isLoadingProfiles = true;
        _isButtonLoading = {};
      });
    }

    List<UserProfile> profiles = [];
    Map<String, bool> followingStatus = {};

    for (String userId in widget.userIds) {
      final profile = await widget.userService.getUserProfile(userId);
      if (profile != null) {
        profiles.add(profile);
        if (_currentUserId != null && _currentUserId != userId) {
          followingStatus[userId] = await widget.userService.isFollowing(_currentUserId!, userId);
        }
      }
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
        child: const Text("Remove"),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[300], foregroundColor: Colors.black),
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
          child: const Text("Follow Back"),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
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
                profilePicture: CircleAvatar(
                  backgroundImage: userProfile.photoURL != null
                      ? NetworkImage(userProfile.photoURL!)
                      : null,
                  child: userProfile.photoURL == null
                      ? const Icon(Icons.person)
                      : null,
                ),
                showDot: isUnseen,
              ),
              title: Text(displayName),
              subtitle: showUsernameAsSubtitle ? Text(username) : null,
              trailing: _buildActionButton(userProfile),
            );
          },
        );
      },
    );
  }
} 