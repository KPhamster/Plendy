import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user_profile.dart';
import '../services/user_service.dart';
import '../services/auth_service.dart';

class UserSearchDelegate extends SearchDelegate<UserProfile?> {
  final UserService userService;
  String? currentUserId; // Will be fetched via Provider

  // Map to store follow status for each user ID in search results
  Map<String, bool> _isFollowingStatus = {};
  // Map to store loading status for each button in search results
  final Map<String, bool> _isButtonLoading = {};
  // To ensure we only load follow status once per buildResults/Suggestions
  String _lastQueryForFollowStatus = ""; 

  UserSearchDelegate({required this.userService});

  // Helper to load follow status for a list of profiles
  Future<void> _loadFollowStatusForProfiles(BuildContext context, List<UserProfile> profiles) async {
    if (currentUserId == null) return;
    Map<String, bool> newStatus = {};
    for (var profile in profiles) {
      if (profile.id != currentUserId) {
        newStatus[profile.id] = await userService.isFollowing(currentUserId!, profile.id);
      }
    }
    // Check if mounted-like condition before setState
    // SearchDelegate doesn't have a direct 'mounted' but this is a common pattern.
    // If the query changed, the old status is irrelevant.
    if (query == _lastQueryForFollowStatus) {
       _isFollowingStatus = newStatus;
      // This ideally needs a way to trigger a rebuild if async operation completes.
      // For now, buildResults/Suggestions will call this and rebuild.
    }
  }


  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
          showSuggestions(context);
        },
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, null); // Close search, returning null
      },
    );
  }

  Widget _buildResultsOrSuggestions(BuildContext context, bool isResults) {
    // Fetch currentUserId via Provider here as context is available
    currentUserId ??= Provider.of<AuthService>(context, listen: false).currentUser?.uid;

    if (query.isEmpty) {
      return const Center(child: Text('Search for users by username or name.'));
    }
    
    // Update last query
    _lastQueryForFollowStatus = query;

    return FutureBuilder<List<UserProfile>>(
      future: userService.searchUsers(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Error searching users.'));
        }
        final List<UserProfile> users = snapshot.data ?? [];
        if (users.isEmpty) {
          return const Center(child: Text('No users found.'));
        }

        // Load follow status after users are fetched
        // This needs to be handled carefully to avoid multiple calls
        // and to ensure UI updates once status is loaded.
        // For simplicity in this step, we call it and rely on a rebuild.
        // A more robust solution might use a StatefulWidget within the delegate or a Stream.
        _loadFollowStatusForProfiles(context, users);

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            final userProfile = users[index];
            bool isCurrentUser = userProfile.id == currentUserId;
            bool isCurrentlyFollowing = _isFollowingStatus[userProfile.id] ?? false;
            bool isLoadingButton = _isButtonLoading[userProfile.id] ?? false;

            return ListTile(
              leading: CircleAvatar(
                backgroundImage: userProfile.photoURL != null
                    ? NetworkImage(userProfile.photoURL!)
                    : null,
                child: userProfile.photoURL == null
                    ? const Icon(Icons.person)
                    : null,
              ),
              title: Text(userProfile.username ?? 'Unknown Username'),
              subtitle: Text(userProfile.id == currentUserId ? "You" : userProfile.displayName ?? 'No display name'),
              trailing: isCurrentUser
                  ? null
                  : isLoadingButton 
                    ? const SizedBox(width:24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : ElevatedButton(
                        onPressed: () async {
                          if (currentUserId == null) return;
                          
                          // setState equivalent for SearchDelegate to update button loading state
                          // This is tricky as SearchDelegate is not a StatefulWidget.
                          // We might need to call showSuggestions(context) or similar to force rebuild.
                          _isButtonLoading[userProfile.id] = true;
                          (context as Element).markNeedsBuild(); // Force rebuild

                          try {
                            if (isCurrentlyFollowing) {
                              await userService.unfollowUser(currentUserId!, userProfile.id);
                            } else {
                              await userService.followUser(currentUserId!, userProfile.id);
                            }
                            // Update status and trigger rebuild
                            _isFollowingStatus[userProfile.id] = !isCurrentlyFollowing;
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Action failed: ${e.toString()}')),
                            );
                          } finally {
                             _isButtonLoading[userProfile.id] = false;
                             (context).markNeedsBuild(); // Force rebuild
                          }
                        },
                        child: Text(isCurrentlyFollowing ? 'Unfollow' : 'Follow'),
                      ),
              onTap: () {
                if (isResults) {
                 // close(context, userProfile); // Option: return selected user
                }
                // TODO: Navigate to user's profile screen
              },
            );
          },
        );
      },
    );
  }


  @override
  Widget buildResults(BuildContext context) {
    // Called when user submits search (e.g. presses enter)
    return _buildResultsOrSuggestions(context, true);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    // Called on each character change in search query
    return _buildResultsOrSuggestions(context, false);
  }
} 