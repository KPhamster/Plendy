import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async'; // For StreamSubscription
import '../services/auth_service.dart';
import '../services/user_service.dart'; // Assuming UserService will provide these counts
import '../widgets/user_list_tab.dart';
import '../widgets/user_search_delegate.dart'; // Import the search delegate
import '../models/user_profile.dart';      // Import UserProfile for search result type
import '../widgets/user_list_tab.dart'; // Reusing for action button logic for now
import 'follow_requests_screen.dart'; // Import FollowRequestsScreen

class MyPeopleScreen extends StatefulWidget {
  const MyPeopleScreen({super.key});

  @override
  State<MyPeopleScreen> createState() => _MyPeopleScreenState();
}

class _MyPeopleScreenState extends State<MyPeopleScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final UserService _userService = UserService();
  AuthService? _authService;

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      // Optional: if you want to do something when tab changes, but not strictly needed for the button.
      // setState(() {}); 
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
    if (_authService != authService) {
      _authService = authService;
      if (_authService?.currentUser != null) {
        _loadInitialDataAndSubscribe(); 
      }
    } else if (_authService?.currentUser != null && _currentUserProfile == null && !_isLoadingCounts) {
        _loadInitialDataAndSubscribe(); 
    }
  }

  Future<void> _loadInitialDataAndSubscribe() async {
    setState(() { _isLoadingCounts = true; }); // Show loading for initial data fetch
    await _loadCurrentUserProfile();
    await _loadSocialCounts(); // This will also call _subscribeToRequestCount if profile is private
    // No need to call _subscribeToRequestCount explicitly here if _loadSocialCounts handles it.
    // However, if _loadSocialCounts might not run (e.g. no current user), ensure subscription starts if profile is loaded.
    if (_currentUserProfile != null && _currentUserProfile!.isPrivate && _requestCountSubscription == null) {
       _subscribeToRequestCount();
    }
    setState(() { _isLoadingCounts = false; }); // Hide main loading after initial fetches
  }

  Future<void> _loadCurrentUserProfile() async {
    if (_authService?.currentUser == null) return;
    final profile = await _userService.getUserProfile(_authService!.currentUser!.uid);
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

  void _subscribeToRequestCount() {
    _requestCountSubscription?.cancel();
    if (_authService?.currentUser == null || !(_currentUserProfile?.isPrivate ?? false) ) {
        if(mounted) setState(() => _pendingRequestCount = 0); // Reset if not private or no user
        return;
    }
    _requestCountSubscription = 
        _userService.getFollowRequestsCountStream(_authService!.currentUser!.uid).listen((count) {
      if (mounted) {
        setState(() {
          _pendingRequestCount = count;
        });
      }
    }, onError: (error) {
      print("Error listening to follow request count: $error");
      if (mounted) setState(() => _pendingRequestCount = 0); // Reset on error
    });
  }

  Future<void> _loadSocialCounts() async {
    if (_authService?.currentUser == null) {
      if (mounted) setState(() => _isLoadingCounts = false);
      return;
    }
    final userId = _authService!.currentUser!.uid;
    // Do not set _isLoadingCounts to true here if _loadInitialDataAndSubscribe already did.
    // Or, ensure this method is robust to be called independently.
    if (mounted && !_isLoadingCounts) setState(() { _isLoadingCounts = true; });

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
    } catch (e) {
      if (mounted) setState(() => _isLoadingCounts = false);
      print("Error loading social counts: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load social counts.')),
        );
      }
    } finally {
        // Ensure request count subscription is active if profile is private
        // This might be called after _loadCurrentUserProfile so profile should be available
        if (mounted && (_currentUserProfile?.isPrivate ?? false) && _requestCountSubscription == null){
             _subscribeToRequestCount();
        } else if (mounted && !(_currentUserProfile?.isPrivate ?? false) && _requestCountSubscription != null) {
            _requestCountSubscription?.cancel(); // Cancel if profile becomes public
            setState(() => _pendingRequestCount = 0);
        }
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
          followingStatus[profile.id] = await _userService.isFollowing(_authService!.currentUser!.uid, profile.id);
        }
      }
    }
    if (mounted && _searchQuery == _searchController.text.trim()) { // Check if query is still the same
      setState(() {
        _searchResults = results;
        _searchResultIsFollowingStatus = followingStatus;
        _isSearchLoading = false;
      });
    }
  }

  Future<void> _toggleFollowSearchResult(String targetUserId, bool currentlyFollowing) async {
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
      
      // After action, refresh follow status for this specific user in search results
      // and also reload social counts for the main tabs.
      if (mounted) {
        bool newFollowStatus = await _userService.isFollowing(currentUserId, targetUserId);
        bool newPendingStatus = false;
        if (targetUserProfile.isPrivate && !newFollowStatus) {
           newPendingStatus = await _userService.hasPendingRequest(currentUserId, targetUserId);
        }
        setState(() {
          if (targetUserProfile.isPrivate && !newFollowStatus && newPendingStatus) {
            // If it's private and request was just sent, update status to a conceptual "requested"
            // For simplicity, we might just disable button or change text. 
            // Here, we update the _searchResultIsFollowingStatus to reflect actual follow state (false after sending request)
             _searchResultIsFollowingStatus[targetUserId] = false; 
          } else {
            _searchResultIsFollowingStatus[targetUserId] = newFollowStatus;
          }
          _searchResultButtonLoading[targetUserId] = false;
        });
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
    _tabController.dispose();
    _searchController.dispose(); // Dispose the search controller
    _requestCountSubscription?.cancel(); // Cancel subscription on dispose
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get currentUserId for convenience, though it's also in _authService
    final String? currentUserId = _authService?.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My People'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        actions: [
          // Optional: Keep the icon to open the full SearchDelegate page, or remove it
          IconButton(
            icon: const Icon(Icons.person_search_outlined), // Changed icon slightly
            tooltip: 'Advanced Search Page',
            onPressed: () {
              showSearch<UserProfile?>(
                context: context,
                delegate: UserSearchDelegate(userService: _userService),
              ).then((_) => _loadSocialCounts()); // Refresh on close
            },
          ),
        ],
        // TabBar is now moved into the body
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search users...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25.0),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
              ),
            ),
          ),
          // Conditionally show search results or TabBar and TabBarView
          if (_searchQuery.isNotEmpty)
            Expanded(
              child: _isSearchLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _searchResults.isEmpty
                      ? const Center(child: Text('No users found for your search.'))
                      : ListView.builder(
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final userProfile = _searchResults[index];
                            bool isSelf = userProfile.id == currentUserId;
                            bool isFollowing = _searchResultIsFollowingStatus[userProfile.id] ?? false;
                            bool isButtonLoading = _searchResultButtonLoading[userProfile.id] ?? false;

                            // Prepare display name and username strings
                            String displayName = userProfile.displayName?.isNotEmpty ?? false
                                ? userProfile.displayName!
                                : (userProfile.username ?? 'Unknown User'); // Fallback for title if display name is empty
                            String username = userProfile.username?.isNotEmpty ?? false
                                ? '@${userProfile.username!}'
                                : '@unknown'; // Fallback for subtitle if username is empty
                            bool showUsernameAsSubtitle = userProfile.displayName?.isNotEmpty ?? false; 

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: userProfile.photoURL != null
                                    ? NetworkImage(userProfile.photoURL!)
                                    : null,
                                child: userProfile.photoURL == null
                                    ? const Icon(Icons.person)
                                    : null,
                              ),
                              title: Text(displayName),
                              subtitle: showUsernameAsSubtitle ? Text(username) : null,
                              trailing: isSelf
                                  ? const Text('(You)', style: TextStyle(color: Colors.grey))
                                  : isButtonLoading 
                                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                                    : ElevatedButton(
                                        onPressed: () => _toggleFollowSearchResult(userProfile.id, isFollowing),
                                        child: Text(isFollowing ? 'Unfollow' : 'Follow'),
                                      ),
                              // TODO: onTap to navigate to user profile
                            );
                          },
                        ),
            )
          else ...[
            if ((_currentUserProfile?.isPrivate ?? false) && _pendingRequestCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.notification_important_outlined), 
                  label: Text('View Follow Requests ($_pendingRequestCount)'),
                  onPressed: () async {
                    // No longer need to capture result if FollowRequestScreen manages its own refresh well.
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const FollowRequestsScreen()),
                    );
                    // Stream listeners should handle updates, but an explicit call might be desired
                    // if FollowRequestsScreen doesn't notify parent of changes that affect this screen's data beyond the count.
                    // For count, stream handles it. For social counts, if accept/deny changes them:
                    _loadSocialCounts(); 
                  },
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 36)),
                ),
              ),
            TabBar(
              controller: _tabController,
              tabs: _isLoadingCounts
                  ? [
                      const Tab(child: CircularProgressIndicator()),
                      const Tab(child: CircularProgressIndicator()),
                      const Tab(child: CircularProgressIndicator()),
                    ]
                  : [
                      Tab(text: '$_friendsCount Friends'),
                      Tab(text: '$_followersCount Followers'),
                      Tab(text: '$_followingCount Following'),
                    ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  UserListTab(
                    userIds: _friendIds,
                    userService: _userService,
                    emptyListMessage: "No friends yet. Find and follow users to make friends!",
                    listType: "friends",
                    onActionCompleted: _loadSocialCounts,
                  ),
                  UserListTab(
                    userIds: _followerIds,
                    userService: _userService,
                    emptyListMessage: "You don't have any followers yet.",
                    listType: "followers",
                    onActionCompleted: _loadSocialCounts,
                  ),
                  UserListTab(
                    userIds: _followingIds,
                    userService: _userService,
                    emptyListMessage: "You are not following anyone yet.",
                    listType: "following",
                    onActionCompleted: _loadSocialCounts,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
} 