import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart'; // Assuming UserService will provide these counts
import '../widgets/user_list_tab.dart';
import '../widgets/user_search_delegate.dart'; // Import the search delegate
import '../models/user_profile.dart';      // Import UserProfile for search result type
import '../widgets/user_list_tab.dart'; // Reusing for action button logic for now

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
        _loadSocialCounts();
      }
    } else if (_authService?.currentUser != null && _friendIds.isEmpty && _followerIds.isEmpty && _followingIds.isEmpty && !_isLoadingCounts) {
        _loadSocialCounts();
    }
  }

  Future<void> _loadSocialCounts() async {
    if (_authService?.currentUser == null) {
      if (mounted) {
        setState(() {
          _isLoadingCounts = false;
        });
      }
      return;
    }
    final userId = _authService!.currentUser!.uid;
    if (mounted) {
      setState(() {
        _isLoadingCounts = true; // Set loading to true at the beginning
      });
    }

    try {
      // Fetch all ID lists in parallel for efficiency
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
      if (mounted) {
        setState(() {
          _isLoadingCounts = false;
        });
      }
      print("Error loading social counts: $e");
      // Optionally, show a SnackBar or some error message to the user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load social counts.')),
        );
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
      if (currentlyFollowing) {
        await _userService.unfollowUser(currentUserId, targetUserId);
      } else {
        await _userService.followUser(currentUserId, targetUserId);
      }
      if (mounted) {
        setState(() {
          _searchResultIsFollowingStatus[targetUserId] = !currentlyFollowing;
          _searchResultButtonLoading[targetUserId] = false;
        });
        _loadSocialCounts(); // Refresh tab counts and lists as a follow action occurred
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