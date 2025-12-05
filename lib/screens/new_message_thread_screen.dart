import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/message_thread.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/message_service.dart';
import '../services/user_service.dart';
import '../widgets/cached_profile_avatar.dart';

class NewMessageThreadScreen extends StatefulWidget {
  const NewMessageThreadScreen({
    super.key,
    required this.messageService,
  });

  final MessageService messageService;

  @override
  State<NewMessageThreadScreen> createState() => _NewMessageThreadScreenState();
}

class _NewMessageThreadScreenState extends State<NewMessageThreadScreen> {
  final TextEditingController _searchController = TextEditingController();
  final UserService _userService = UserService();
  final Map<String, UserProfile> _selectedProfiles = {};
  List<UserProfile> _searchResults = [];
  List<UserProfile> _friends = [];
  Timer? _debounce;
  bool _isSearching = false;
  bool _creatingChat = false;
  bool _isLoadingFriends = false;
  String? _friendsError;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadFriends();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;
    if (currentUser == null) {
      return;
    }

    setState(() {
      _isLoadingFriends = true;
      _friendsError = null;
    });

    try {
      final friendIds = await _userService.getFriendIds(currentUser.uid);
      final profiles = await _fetchProfiles(friendIds);
      if (!mounted) return;

      profiles.sort((a, b) {
        final nameA =
            (a.displayName ?? a.username ?? '').toLowerCase().trim();
        final nameB =
            (b.displayName ?? b.username ?? '').toLowerCase().trim();
        return nameA.compareTo(nameB);
      });

      setState(() {
        _friends = profiles;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _friendsError = 'Could not load friends right now.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingFriends = false;
        });
      }
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final query = _searchController.text.trim();
      if (query.isEmpty) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
        return;
      }
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;
    if (currentUser == null) {
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final results = await _userService.searchUsers(query);
      setState(() {
        _searchResults =
            results.where((profile) => profile.id != currentUser.uid).toList();
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not search right now.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  void _toggleSelection(UserProfile profile) {
    setState(() {
      if (_selectedProfiles.containsKey(profile.id)) {
        _selectedProfiles.remove(profile.id);
      } else {
        _selectedProfiles[profile.id] = profile;
      }
    });
  }

  Future<void> _createChat() async {
    if (_selectedProfiles.isEmpty) {
      return;
    }
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('You must be signed in to create a chat.')),
      );
      return;
    }

    setState(() {
      _creatingChat = true;
    });

    try {
      final thread = await widget.messageService.createOrGetThread(
        currentUserId: currentUser.uid,
        participantIds: _selectedProfiles.keys.toList(),
      );
      if (!mounted) {
        return;
      }
      Navigator.pop(context, thread);
    } catch (error) {
      if (mounted) {
        final message = 'Could not start chat: ' + error.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _creatingChat = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectionSuffix = _selectedProfiles.length > 1
        ? ' (' + _selectedProfiles.length.toString() + ' people)'
        : '';
    final canCreate = _selectedProfiles.isNotEmpty && !_creatingChat;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: const Text('New Message'),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ButtonStyle(
                backgroundColor:
                    MaterialStateProperty.resolveWith<Color?>((states) {
                  if (states.contains(MaterialState.disabled)) {
                    return null; // Use default disabled color
                  }
                  return Theme.of(context).primaryColor;
                }),
                foregroundColor:
                    MaterialStateProperty.resolveWith<Color?>((states) {
                  if (states.contains(MaterialState.disabled)) {
                    return null; // Use default disabled color
                  }
                  return Colors.white;
                }),
              ),
              onPressed: canCreate ? _createChat : null,
              child: _creatingChat
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text('Start chat' + selectionSuffix),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by username or name',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchResults = [];
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          if (_selectedProfiles.isNotEmpty)
            SizedBox(
              height: 72,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: _selectedProfiles.values.map((profile) {
                  final name =
                      profile.displayName ?? profile.username ?? 'Friend';
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Chip(
                      label: Text(name),
                      avatar: CachedProfileAvatar(
                        photoUrl: profile.photoURL,
                        radius: 12,
                        fallbackText: name.isNotEmpty ? name[0].toUpperCase() : null,
                      ),
                      deleteIcon: const Icon(Icons.close),
                      onDeleted: () {
                        setState(() {
                          _selectedProfiles.remove(profile.id);
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _buildResultsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    if (_searchController.text.isEmpty) {
      return _buildFriendsList();
    }

    if (_searchResults.isEmpty) {
      return const Center(
        child: Text('No people found.'),
      );
    }

    return _buildProfileList(_searchResults);
  }

  Widget _buildFriendsList() {
    if (_isLoadingFriends) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_friendsError != null) {
      return Center(
        child: Text(_friendsError!),
      );
    }

    if (_friends.isEmpty) {
      return const Center(
        child: Text('Add friends to start a chat.'),
      );
    }

    return _buildProfileList(_friends);
  }

  Widget _buildProfileList(List<UserProfile> profiles) {
    return ListView.separated(
      itemCount: profiles.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final profile = profiles[index];
        final isSelected = _selectedProfiles.containsKey(profile.id);
        final title = profile.displayName ?? profile.username ?? 'Friend';
        final subtitle =
            profile.username != null ? '@' + profile.username! : null;

        return ListTile(
          leading: CachedProfileAvatar(
            photoUrl: profile.photoURL,
            fallbackText: title.isNotEmpty ? title[0].toUpperCase() : '?',
          ),
          title: Text(title),
          subtitle: subtitle != null ? Text(subtitle) : null,
          trailing: Icon(
            isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
          ),
          onTap: () => _toggleSelection(profile),
        );
      },
    );
  }

  Future<List<UserProfile>> _fetchProfiles(List<String> userIds) async {
    if (userIds.isEmpty) return const <UserProfile>[];
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final Map<String, UserProfile> profiles = {};

    for (int i = 0; i < userIds.length; i += 10) {
      final List<String> chunk =
          userIds.sublist(i, min(i + 10, userIds.length));
      final QuerySnapshot<Map<String, dynamic>> snapshot = await firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snapshot.docs) {
        profiles[doc.id] = UserProfile.fromMap(doc.id, doc.data());
      }
    }

    return userIds
        .where(profiles.containsKey)
        .map((id) => profiles[id]!)
        .toList();
  }
}
