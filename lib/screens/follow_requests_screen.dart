import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  bool _isLoading = true;
  String? _currentUserId;

  // Keep track of loading state for individual buttons
  Map<String, bool> _isProcessingRequest = {}; 

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authService = Provider.of<AuthService>(context, listen: false);
    if (_authService != authService) {
      _authService = authService;
      _currentUserId = _authService?.currentUser?.uid;
      if (_currentUserId != null) {
        _loadFollowRequests();
      }
    }
  }

  Future<void> _loadFollowRequests() async {
    if (_currentUserId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (mounted) setState(() => _isLoading = true);
    try {
      final requests = await _userService.getFollowRequests(_currentUserId!);
      if (mounted) {
        setState(() {
          _followRequests = requests;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      print("Error loading follow requests: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load follow requests: ${e.toString()}')),
      );
    }
  }

  Future<void> _handleRequest(String requesterId, bool accept) async {
    if (_currentUserId == null) return;

    setState(() {
      _isProcessingRequest[requesterId] = true;
    });

    try {
      if (accept) {
        await _userService.acceptFollowRequest(_currentUserId!, requesterId);
      } else {
        await _userService.denyFollowRequest(_currentUserId!, requesterId);
      }
      // Refresh the list after action
      _loadFollowRequests(); 
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action failed: ${e.toString()}')),
      );
    } finally {
      // Check if mounted before calling setState is good practice, 
      // though in this specific flow, it might be okay.
      if(mounted){
          setState(() {
            _isProcessingRequest[requesterId] = false;
          });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Follow Requests'),
      ),
      body: _isLoading
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