import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart'; // Assuming UserService will provide these counts
import '../widgets/user_list_tab.dart';

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

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My People'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        bottom: TabBar(
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
      ),
      body: TabBarView(
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
    );
  }
} 