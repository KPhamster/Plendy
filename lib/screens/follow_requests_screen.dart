import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async'; // For StreamSubscription
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';

class FollowRequestsScreen extends StatefulWidget {
  const FollowRequestsScreen({super.key});

  @override
  State<FollowRequestsScreen> createState() => _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends State<FollowRequestsScreen> {
  final UserService _userService = UserService();
  AuthService? _authService;
  List<UserProfile> _followRequests = [];
  bool _isLoadingInitial = true; // For initial load indicator
  String? _currentUserId;
  StreamSubscription? _requestsSubscription;

  // Keep track of loading state for individual buttons
  Map<String, bool> _isProcessingRequest = {}; 

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authService = Provider.of<AuthService>(context, listen: false);
    if (_authService != authService) {
      _authService = authService;
      _currentUserId = _authService?.currentUser?.uid;
      _subscribeToFollowRequests();
    }
  }

  void _subscribeToFollowRequests() {
    _requestsSubscription?.cancel(); // Cancel previous subscription if any
    if (_currentUserId == null) {
      if (mounted) setState(() => {_followRequests = [], _isLoadingInitial = false});
      return;
    }
    if (mounted) setState(() => _isLoadingInitial = true);

    _requestsSubscription = _userService.getFollowRequestsStream(_currentUserId!).listen(
      (requests) {
        if (mounted) {
          setState(() {
            _followRequests = requests;
            _isLoadingInitial = false; 
          });
        }
      },
      onError: (error) {
        if (mounted) setState(() => _isLoadingInitial = false);
        print("Error listening to follow requests: $error");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load follow requests: ${error.toString()}')),
        );
      },
    );
  }

  Future<void> _handleRequest(String requesterId, bool accept) async {
    if (_currentUserId == null) return;
    setState(() => _isProcessingRequest[requesterId] = true);
    try {
      if (accept) {
        await _userService.acceptFollowRequest(_currentUserId!, requesterId);
      } else {
        await _userService.denyFollowRequest(_currentUserId!, requesterId);
      }
      // No need to call _loadFollowRequests manually, stream will update.
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action failed: ${e.toString()}')),
      );
    } finally {
      if(mounted){
          setState(() => _isProcessingRequest[requesterId] = false);
      }
    }
  }

  @override
  void dispose() {
    _requestsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Follow Requests'),
      ),
      body: _isLoadingInitial
          ? const Center(child: CircularProgressIndicator())
          : _followRequests.isEmpty
              ? const Center(
                  child: Text('No pending follow requests.', style: TextStyle(fontSize: 16)),
                )
              : ListView.builder(
                  itemCount: _followRequests.length,
                  itemBuilder: (context, index) {
                    final userProfile = _followRequests[index];
                    bool isProcessing = _isProcessingRequest[userProfile.id] ?? false;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: userProfile.photoURL != null
                            ? NetworkImage(userProfile.photoURL!)
                            : null,
                        child: userProfile.photoURL == null
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text(userProfile.displayName ?? userProfile.username ?? 'Unknown User'),
                      subtitle: Text('@${userProfile.username ?? 'unknown'}'),
                      trailing: isProcessing 
                        ? const SizedBox(width: 24, height: 24, child:CircularProgressIndicator(strokeWidth: 2.0))
                        : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => _handleRequest(userProfile.id, true),
                              child: const Text('Approve', style: TextStyle(color: Colors.blue)),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () => _handleRequest(userProfile.id, false),
                              child: const Text('Deny', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                    );
                  },
                ),
    );
  }
} 