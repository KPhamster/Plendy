import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/message_thread.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/message_service.dart';
import '../services/user_service.dart';

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
  Timer? _debounce;
  bool _isSearching = false;
  bool _creatingChat = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final query = _searchController.text.trim();
      if (query.isEmpty) {
        setState(() {
          _searchResults = [];
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
      appBar: AppBar(
        title: const Text('New Message'),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
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
                      avatar: profile.photoURL != null
                          ? CircleAvatar(
                              backgroundImage: NetworkImage(profile.photoURL!))
                          : null,
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
      return const Center(
        child: Text('Search for people to start a chat.'),
      );
    }

    if (_searchResults.isEmpty) {
      return const Center(
        child: Text('No people found.'),
      );
    }

    return ListView.separated(
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final profile = _searchResults[index];
        final isSelected = _selectedProfiles.containsKey(profile.id);
        final title = profile.displayName ?? profile.username ?? 'Friend';
        final subtitle =
            profile.username != null ? '@' + profile.username! : null;

        return ListTile(
          leading: profile.photoURL != null && profile.photoURL!.isNotEmpty
              ? CircleAvatar(backgroundImage: NetworkImage(profile.photoURL!))
              : CircleAvatar(
                  child: Text(title.isNotEmpty ? title[0].toUpperCase() : '?')),
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
}
