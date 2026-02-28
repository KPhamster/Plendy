import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async'; // For StreamSubscription
import '../config/colors.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart'; // Assuming UserService will provide these counts
import '../services/notification_state_service.dart'; // Import NotificationStateService
import '../services/my_people_preload_service.dart'; // Import preload service
import '../widgets/user_list_tab.dart';
// Import the search delegate
import '../widgets/notification_dot.dart'; // Import NotificationDot
import '../widgets/cached_profile_avatar.dart';
import '../models/user_profile.dart'; // Import UserProfile for search result type
// Reusing for action button logic for now
import 'follow_requests_screen.dart'; // Import FollowRequestsScreen
import 'public_profile_screen.dart';
import 'package:plendy/utils/haptic_feedback.dart';
import '../config/my_people_help_content.dart';
import '../models/my_people_help_target.dart';
import '../widgets/screen_help_controller.dart';

class MyPeopleScreen extends StatefulWidget {
  const MyPeopleScreen({super.key});

  @override
  State<MyPeopleScreen> createState() => _MyPeopleScreenState();
}

class _MyPeopleScreenState extends State<MyPeopleScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final UserService _userService = UserService();
  AuthService? _authService;
  NotificationStateService?
      _notificationService; // Store reference to notification service

  // Track if user has visited the Followers tab
  bool _hasVisitedFollowersTab = false;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<UserProfile> _searchResults = [];
  bool _isSearchLoading = false;
  Map<String, bool> _searchResultIsFollowingStatus = {};
  Map<String, bool> _searchResultButtonLoading = {};

  UserProfile? _currentUserProfile;
  int _pendingRequestCount = 0;
  StreamSubscription? _requestCountSubscription;

  int _friendsCount = 0;
  int _followersCount = 0;
  int _followingCount = 0;

  List<String> _friendIds = [];
  List<String> _followerIds = [];
  List<String> _followingIds = [];

  bool _isLoadingCounts = true;
  late final ScreenHelpController<MyPeopleHelpTargetId> _help;
  final List<GlobalKey> _tabKeys =
      List<GlobalKey>.generate(3, (_) => GlobalKey());

  @override
  void initState() {
    super.initState();
    _help = ScreenHelpController<MyPeopleHelpTargetId>(
      vsync: this,
      content: myPeopleHelpContent,
      setState: setState,
      isMounted: () => mounted,
      defaultFirstTarget: MyPeopleHelpTargetId.helpButton,
    );
    _tabController = TabController(
        length: 3,
        vsync: this,
        initialIndex: 1); // Set Following tab as default
    _tabController.addListener(() {
      // Track when user visits the Followers tab (now at index 2)
      if (_tabController.index == 2) {
        _hasVisitedFollowersTab = true;
      }
    });
    _searchController.addListener(() {
      if (_searchQuery != _searchController.text.trim()) {
        setState(() {
          _searchQuery = _searchController.text.trim();
        });
        if (_searchQuery.isNotEmpty) {
          _performSearch();
        } else {
          setState(() {
            _searchResults = [];
            _searchResultIsFollowingStatus = {};
            _searchResultButtonLoading = {};
            _isSearchLoading = false;
          });
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authService = Provider.of<AuthService>(context);
    final notificationService =
        Provider.of<NotificationStateService>(context, listen: false);

    if (_authService != authService) {
      _authService = authService;
      if (_authService?.currentUser != null) {
        _loadInitialDataAndSubscribe();
      } else {
        // User signed out - cancel subscriptions to prevent permission errors
        _requestCountSubscription?.cancel();
        _requestCountSubscription = null;
        if (mounted) {
          setState(() {
            _pendingRequestCount = 0;
          });
        }
      }
    } else if (_authService?.currentUser != null &&
        _currentUserProfile == null &&
        !_isLoadingCounts) {
      _loadInitialDataAndSubscribe();
    }

    // Store reference to notification service
    if (_notificationService != notificationService) {
      _notificationService = notificationService;
    }
  }

  Future<void> _loadInitialDataAndSubscribe() async {
    setState(() {
      _isLoadingCounts = true;
    }); // Show loading for initial data fetch
    await _loadCurrentUserProfile();
    await _loadSocialCounts(); // This will also call _subscribeToRequestCount if profile is private
    // No need to call _subscribeToRequestCount explicitly here if _loadSocialCounts handles it.
    // However, if _loadSocialCounts might not run (e.g. no current user), ensure subscription starts if profile is loaded.
    if (_currentUserProfile != null &&
        _currentUserProfile!.isPrivate &&
        _requestCountSubscription == null) {
      _subscribeToRequestCount();
    }
    setState(() {
      _isLoadingCounts = false;
    }); // Hide main loading after initial fetches
  }

  Future<void> _loadCurrentUserProfile() async {
    if (_authService?.currentUser == null) return;
    final profile =
        await _userService.getUserProfile(_authService!.currentUser!.uid);
    if (mounted) {
      setState(() {
        _currentUserProfile = profile;
      });
      // If profile is loaded and is private, subscribe to request count
      // This is a good place if _loadInitialDataAndSubscribe doesn't already cover it.
      if (_currentUserProfile?.isPrivate ?? false) {
        _subscribeToRequestCount();
      }
    }
  }

  void _openPublicProfile(String userId) {
    if (!mounted || userId.isEmpty) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(userId: userId),
      ),
    );
  }

  void _subscribeToRequestCount() {
    _requestCountSubscription?.cancel();
    if (_authService?.currentUser == null ||
        !(_currentUserProfile?.isPrivate ?? false)) {
      if (mounted)
        setState(
            () => _pendingRequestCount = 0); // Reset if not private or no user
      return;
    }
    _requestCountSubscription = _userService
        .getFollowRequestsCountStream(_authService!.currentUser!.uid)
        .listen((count) {
      if (mounted) {
        setState(() {
          _pendingRequestCount = count;
        });
      }
    }, onError: (error) {
      // Silently ignore permission errors after logout
      if (error.toString().contains('PERMISSION_DENIED')) {
        print("Follow request count stream: User no longer authenticated");
      } else {
        print("Error listening to follow request count: $error");
      }
      if (mounted) setState(() => _pendingRequestCount = 0); // Reset on error
    });
  }

  Future<void> _loadSocialCounts({bool forceRefresh = false}) async {
    if (_authService?.currentUser == null) {
      if (mounted) setState(() => _isLoadingCounts = false);
      return;
    }
    final userId = _authService!.currentUser!.uid;
    final preloadService = MyPeoplePreloadService();

    // Check if we have valid preloaded data
    if (!forceRefresh && preloadService.isCacheValid(userId)) {
      // Use preloaded data immediately
      if (mounted) {
        setState(() {
          _friendIds = preloadService.friendIds;
          _followerIds = preloadService.followerIds;
          _followingIds = preloadService.followingIds;
          _friendsCount = _friendIds.length;
          _followersCount = _followerIds.length;
          _followingCount = _followingIds.length;
          _isLoadingCounts = false;
        });
      }
      // Handle subscription in finally block equivalent
      _handleRequestCountSubscription();
      return;
    }

    // Do not set _isLoadingCounts to true here if _loadInitialDataAndSubscribe already did.
    // Or, ensure this method is robust to be called independently.
    if (mounted && !_isLoadingCounts)
      setState(() {
        _isLoadingCounts = true;
      });

    try {
      final results = await Future.wait([
        _userService.getFriendIds(userId),
        _userService.getFollowerIds(userId),
        _userService.getFollowingIds(userId),
      ]);
      final friends = results[0];
      final followers = results[1];
      final following = results[2];
      if (mounted) {
        setState(() {
          _friendIds = friends;
          _followerIds = followers;
          _followingIds = following;
          _friendsCount = friends.length;
          _followersCount = followers.length;
          _followingCount = following.length;
          _isLoadingCounts = false;
        });
      }
      // Invalidate preload cache since we have fresh data
      preloadService.invalidateCache();
    } catch (e) {
      if (mounted) setState(() => _isLoadingCounts = false);
      print("Error loading social counts: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load social counts.')),
        );
      }
    } finally {
      _handleRequestCountSubscription();
    }
  }

  void _handleRequestCountSubscription() {
    // Ensure request count subscription is active if profile is private
    // This might be called after _loadCurrentUserProfile so profile should be available
    if (mounted &&
        (_currentUserProfile?.isPrivate ?? false) &&
        _requestCountSubscription == null) {
      _subscribeToRequestCount();
    } else if (mounted &&
        !(_currentUserProfile?.isPrivate ?? false) &&
        _requestCountSubscription != null) {
      _requestCountSubscription?.cancel(); // Cancel if profile becomes public
      setState(() => _pendingRequestCount = 0);
    }
  }

  Future<void> _performSearch() async {
    if (_searchQuery.isEmpty || _authService?.currentUser == null) {
      setState(() {
        _searchResults = [];
        _searchResultIsFollowingStatus = {};
        _searchResultButtonLoading = {};
        _isSearchLoading = false;
      });
      return;
    }
    setState(() {
      _isSearchLoading = true;
      _searchResultButtonLoading = {}; // Clear specific button loading states
    });
    final results = await _userService.searchUsers(_searchQuery);
    Map<String, bool> followingStatus = {};
    if (_authService?.currentUser?.uid != null) {
      for (var profile in results) {
        if (profile.id != _authService!.currentUser!.uid) {
          followingStatus[profile.id] = await _userService.isFollowing(
              _authService!.currentUser!.uid, profile.id);
        }
      }
    }
    if (mounted && _searchQuery == _searchController.text.trim()) {
      // Check if query is still the same
      setState(() {
        _searchResults = results;
        _searchResultIsFollowingStatus = followingStatus;
        _isSearchLoading = false;
      });
    }
  }

  Future<void> _toggleFollowSearchResult(
      String targetUserId, bool currentlyFollowing) async {
    final currentUserId = _authService?.currentUser?.uid;
    if (currentUserId == null) return;

    setState(() {
      _searchResultButtonLoading[targetUserId] = true;
    });

    try {
      final targetUserProfile = await _userService.getUserProfile(targetUserId);
      if (targetUserProfile == null) throw Exception("Target user not found");

      if (currentlyFollowing) {
        await _userService.unfollowUser(currentUserId, targetUserId);
      } else {
        // Use the modified followUser that handles private profiles
        await _userService.followUser(currentUserId, targetUserId);
      }

      // Always toggle the state, just like UserListTab does for consistency
      if (mounted) {
        setState(() {
          _searchResultIsFollowingStatus[targetUserId] = !currentlyFollowing;
          _searchResultButtonLoading[targetUserId] = false;
        });

        // Still reload social counts for the main tabs
        _loadSocialCounts();
        if (_currentUserProfile?.isPrivate ?? false) {
          _subscribeToRequestCount(); // Refresh request count as well
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Action failed: ${e.toString()}')),
        );
        setState(() {
          _searchResultButtonLoading[targetUserId] = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _help.dispose();
    // Mark followers as seen when leaving the screen if user visited the Followers tab
    if (_hasVisitedFollowersTab) {
      // Fire the async operation without awaiting (fire and forget is acceptable here)
      // The _isUpdatingState flag in NotificationStateService prevents race conditions
      _notificationService?.markFollowersAsSeen().catchError((e) {
        print("Error marking followers as seen: $e");
      });
    }

    _tabController.dispose();
    _searchController.dispose(); // Dispose the search controller
    _requestCountSubscription?.cancel(); // Cancel subscription on dispose
    super.dispose();
  }

  MyPeopleHelpTargetId _helpTargetForTab(int index) {
    switch (index) {
      case 0:
        return MyPeopleHelpTargetId.friendsTabSwitch;
      case 1:
        return MyPeopleHelpTargetId.followingTabSwitch;
      case 2:
      default:
        return MyPeopleHelpTargetId.followersTabSwitch;
    }
  }

  MyPeopleHelpTargetId _helpContentTargetForTab(int index) {
    switch (index) {
      case 0:
        return MyPeopleHelpTargetId.friendsTabContent;
      case 1:
        return MyPeopleHelpTargetId.followingTabContent;
      case 2:
      default:
        return MyPeopleHelpTargetId.followersTabContent;
    }
  }

  MyPeopleHelpTargetId _helpTargetForBodyTap() {
    if (_searchQuery.isNotEmpty) {
      return MyPeopleHelpTargetId.currentView;
    }
    return _helpContentTargetForTab(_tabController.index);
  }

  Widget _buildHelpAwareTabContent({
    required MyPeopleHelpTargetId target,
    required Widget child,
  }) {
    return Builder(
      builder: (tabCtx) => GestureDetector(
        behavior: _help.isActive
            ? HitTestBehavior.opaque
            : HitTestBehavior.deferToChild,
        onTap: _help.isActive ? () => _help.tryTap(target, tabCtx) : null,
        child: IgnorePointer(
          ignoring: _help.isActive,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get currentUserId for convenience, though it's also in _authService
    final String? currentUserId = _authService?.currentUser?.uid;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.backgroundColor,
          appBar: AppBar(
            backgroundColor: AppColors.backgroundColor,
            foregroundColor: Colors.black,
            title: const Text('My People'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            actions: [_help.buildIconButton(inactiveColor: Colors.black87)],
            bottom: _help.isActive
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(24),
                    child: _help.buildExitBanner(),
                  )
                : null,
          ),
          body: GestureDetector(
            behavior: _help.isActive
                ? HitTestBehavior.opaque
                : HitTestBehavior.deferToChild,
            onTap: _help.isActive
                ? () => _help.tryTap(_helpTargetForBodyTap(), context)
                : null,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12.0, vertical: 4.0),
                  child: Builder(
                    builder: (searchCtx) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _help.isActive
                          ? () => _help.tryTap(
                              MyPeopleHelpTargetId.searchBar, searchCtx)
                          : null,
                      child: IgnorePointer(
                        ignoring: _help.isActive,
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            labelText: 'Search users...',
                            prefixIcon: Icon(Icons.search,
                                color: Theme.of(context).primaryColor),
                            filled: true,
                            fillColor: AppColors.backgroundColorDark,
                            border: OutlineInputBorder(
                              borderSide: const BorderSide(
                                  color: AppColors.backgroundColorDark),
                              borderRadius: BorderRadius.circular(25.0),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                  color: AppColors.backgroundColorDark),
                              borderRadius: BorderRadius.circular(25.0),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                  color: AppColors.backgroundColorDark),
                              borderRadius: BorderRadius.circular(25.0),
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    tooltip: 'Clear Search',
                                    onPressed: () {
                                      _searchController.clear();
                                    },
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Conditionally show search results or TabBar and TabBarView
                if (_searchQuery.isNotEmpty)
                  Expanded(
                    child: IgnorePointer(
                      ignoring: _help.isActive,
                      child: _isSearchLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _searchResults.isEmpty
                              ? const Center(
                                  child:
                                      Text('No users found for your search.'))
                              : ListView.builder(
                                  itemCount: _searchResults.length,
                                  itemBuilder: (context, index) {
                                    final userProfile = _searchResults[index];
                                    bool isSelf =
                                        userProfile.id == currentUserId;
                                    bool isFollowing =
                                        _searchResultIsFollowingStatus[
                                                userProfile.id] ??
                                            false;
                                    bool isButtonLoading =
                                        _searchResultButtonLoading[
                                                userProfile.id] ??
                                            false;

                                    // Prepare display name and username strings
                                    String displayName = userProfile
                                                .displayName?.isNotEmpty ??
                                            false
                                        ? userProfile.displayName!
                                        : (userProfile.username ??
                                            'Unknown User'); // Fallback for title if display name is empty
                                    String username = userProfile
                                                .username?.isNotEmpty ??
                                            false
                                        ? '@${userProfile.username!}'
                                        : '@unknown'; // Fallback for subtitle if username is empty
                                    bool showUsernameAsSubtitle =
                                        userProfile.displayName?.isNotEmpty ??
                                            false;

                                    return ListTile(
                                      leading: CachedProfileAvatar(
                                        photoUrl: userProfile.photoURL,
                                        fallbackText: displayName.isNotEmpty
                                            ? displayName[0].toUpperCase()
                                            : null,
                                      ),
                                      title: Text(displayName),
                                      subtitle: showUsernameAsSubtitle
                                          ? Text(username)
                                          : null,
                                      trailing: isSelf
                                          ? const Text('(You)',
                                              style:
                                                  TextStyle(color: Colors.grey))
                                          : isButtonLoading
                                              ? const SizedBox(
                                                  width: 24,
                                                  height: 24,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2))
                                              : ElevatedButton(
                                                  onPressed: () =>
                                                      _toggleFollowSearchResult(
                                                          userProfile.id,
                                                          isFollowing),
                                                  child: Text(isFollowing
                                                      ? 'Unfollow'
                                                      : 'Follow'),
                                                ),
                                      onTap: withHeavyTap(isSelf
                                          ? null
                                          : () => _openPublicProfile(
                                              userProfile.id)),
                                    );
                                  },
                                ),
                    ),
                  )
                else ...[
                  if ((_currentUserProfile?.isPrivate ?? false) &&
                      _pendingRequestCount > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      child: Consumer<NotificationStateService>(
                        builder: (context, notificationService, child) {
                          return ElevatedButton.icon(
                            icon: IconNotificationDot(
                              icon: const Icon(
                                  Icons.notification_important_outlined),
                              showDot:
                                  notificationService.hasUnseenFollowRequests,
                            ),
                            label: Text(
                                'View Follow Requests ($_pendingRequestCount)'),
                            onPressed: () async {
                              if (_help.isActive) {
                                _help.tryTap(
                                    MyPeopleHelpTargetId.currentView, context);
                                return;
                              }
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        const FollowRequestsScreen()),
                              );
                              _loadSocialCounts();
                            },
                            style: ElevatedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 36)),
                          );
                        },
                      ),
                    ),
                  TabBar(
                    controller: _tabController,
                    onTap: (index) {
                      if (!_help.isActive) return;
                      final tabCtx = _tabKeys[index].currentContext;
                      if (tabCtx != null) {
                        _help.showTarget(_helpTargetForTab(index), tabCtx,
                            withHaptic: true);
                      }
                    },
                    tabs: _isLoadingCounts
                        ? [
                            Tab(
                                child: CircularProgressIndicator(
                                    key: _tabKeys[0])),
                            Tab(
                                child: CircularProgressIndicator(
                                    key: _tabKeys[1])),
                            Tab(
                                child: CircularProgressIndicator(
                                    key: _tabKeys[2])),
                          ]
                        : [
                            Tab(
                              child: Text('$_friendsCount Friends',
                                  key: _tabKeys[0]),
                            ),
                            Tab(
                              child: Text('$_followingCount Following',
                                  key: _tabKeys[1]),
                            ),
                            Consumer<NotificationStateService>(
                              builder: (context, notificationService, child) {
                                return Tab(
                                  child: TabNotificationDot(
                                    text: '$_followersCount Followers',
                                    key: _tabKeys[2],
                                    showDot:
                                        notificationService.hasUnseenFollowers,
                                  ),
                                );
                              },
                            ),
                          ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      physics: _help.isActive
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      children: [
                        _buildHelpAwareTabContent(
                          target: MyPeopleHelpTargetId.friendsTabContent,
                          child: UserListTab(
                            userIds: _friendIds,
                            userService: _userService,
                            emptyListMessage:
                                "No friends yet. Find and follow users to make friends!",
                            listType: "friends",
                            onActionCompleted: _loadSocialCounts,
                            onUserTap: _openPublicProfile,
                          ),
                        ),
                        _buildHelpAwareTabContent(
                          target: MyPeopleHelpTargetId.followingTabContent,
                          child: UserListTab(
                            userIds: _followingIds,
                            userService: _userService,
                            emptyListMessage:
                                "You are not following anyone yet.",
                            listType: "following",
                            onActionCompleted: _loadSocialCounts,
                            onUserTap: _openPublicProfile,
                          ),
                        ),
                        _buildHelpAwareTabContent(
                          target: MyPeopleHelpTargetId.followersTabContent,
                          child: UserListTab(
                            userIds: _followerIds,
                            userService: _userService,
                            emptyListMessage:
                                "You don't have any followers yet.",
                            listType: "followers",
                            onActionCompleted: _loadSocialCounts,
                            onUserTap: _openPublicProfile,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_help.isActive && _help.hasActiveTarget) _help.buildOverlay(),
      ],
    );
  }
}
