import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async'; // For StreamSubscription
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/notification_state_service.dart'; // Import NotificationStateService
import '../widgets/notification_dot.dart'; // Import NotificationDot
import 'my_people_screen.dart'; // Import MyPeopleScreen

class FollowRequestsScreen extends StatefulWidget {
  const FollowRequestsScreen({super.key});

  @override
  State<FollowRequestsScreen> createState() => _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends State<FollowRequestsScreen> {
  final UserService _userService = UserService();
  AuthService? _authService;
  NotificationStateService? _notificationService; // Store reference to notification service
  List<UserProfile> _followRequests = [];
  bool _isLoadingInitial = true; // For initial load indicator
  String? _currentUserId;
  StreamSubscription? _requestsSubscription;

  // Keep track of loading state for individual buttons
  final Map<String, bool> _isProcessingRequest = {}; 

  @override
  void initState() {
    super.initState();
    // Mark follow requests as seen when screen opens - will be called in didChangeDependencies
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationService?.markFollowRequestsAsSeen();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authService = Provider.of<AuthService>(context, listen: false);
    final notificationService = Provider.of<NotificationStateService>(context, listen: false);
    
    if (_authService != authService) {
      _authService = authService;
      _currentUserId = _authService?.currentUser?.uid;
      
      if (_currentUserId != null) {
        _subscribeToFollowRequests(); // Re-subscribe with new auth service
      } else {
        // User signed out - cancel subscription to prevent permission errors
        _requestsSubscription?.cancel();
        _requestsSubscription = null;
        if (mounted) {
          setState(() {
            _followRequests = [];
            _isLoadingInitial = false;
          });
        }
      }
    }
    
    // Store reference to notification service
    if (_notificationService != notificationService) {
      _notificationService = notificationService;
    }
  }

  void _subscribeToFollowRequests() {
    _requestsSubscription?.cancel(); // Cancel previous subscription if any
    if (_currentUserId == null) {
      if (mounted) setState(() {_followRequests = []; _isLoadingInitial = false;});
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
        
        // Silently ignore permission errors after logout
        if (error.toString().contains('PERMISSION_DENIED')) {
          print("Follow requests stream: User no longer authenticated");
        } else {
          print("Error listening to follow requests: $error");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not load follow requests: ${error.toString()}')),
            );
          }
        }
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
    // Mark follow requests as seen when screen closes - use stored reference
    _notificationService?.markFollowRequestsAsSeen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Follow Requests'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Navigate back to MyPeopleScreen instead of just popping
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const MyPeopleScreen()),
            );
          },
        ),
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

                    return Consumer<NotificationStateService>(
                      builder: (context, notificationService, child) {
                        bool isUnseen = notificationService.unseenFollowRequestIds.contains(userProfile.id);
                        
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
                    );
                  },
                ),
    );
  }
} 