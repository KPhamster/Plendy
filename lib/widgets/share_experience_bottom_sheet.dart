import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_constants.dart';
import '../models/message_thread.dart';
import '../models/share_result.dart';
import '../models/user_profile.dart';
import '../screens/chat_screen.dart';
import '../services/message_service.dart';
import '../services/user_service.dart';
import 'cached_profile_avatar.dart';

/// Shows a snackbar with "Shared with friends!" message and a "View message" action
/// that navigates to the message thread when tapped.
void showSharedWithFriendsSnackbar(
  BuildContext context,
  DirectShareResult? result,
) {
  if (result == null || !result.hasThreads) {
    // Fallback to simple snackbar if no thread info available
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Shared with friends!')),
    );
    return;
  }

  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  if (currentUserId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Shared with friends!')),
    );
    return;
  }

  final threadId = result.firstThreadId!;

  // Use personalized message for single recipient
  final messageText = result.isSingleRecipient && result.singleRecipientDisplayName != null
      ? 'Shared with ${result.singleRecipientDisplayName}!'
      : 'Shared with friends!';

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Expanded(
            child: Text(messageText),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () async {
              // Dismiss the snackbar first
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              
              try {
                // Fetch the thread from Firestore
                final threadDoc = await FirebaseFirestore.instance
                    .collection('message_threads')
                    .doc(threadId)
                    .get();

                if (!threadDoc.exists) {
                  return;
                }

                final thread = MessageThread.fromFirestore(threadDoc);

                if (!context.mounted) return;

                // Navigate to the chat screen
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      thread: thread,
                      currentUserId: currentUserId,
                    ),
                  ),
                );
              } catch (e) {
                debugPrint('Failed to navigate to message thread: $e');
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'View message',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
}

typedef ShareBottomSheetCreateLinkCallback = Future<void> Function({
  required String shareMode,
  required bool giveEditAccess,
});

Future<T?> showShareExperienceBottomSheet<T>({
  required BuildContext context,
  required Future<void> Function() onDirectShare,
  required ShareBottomSheetCreateLinkCallback onCreateLink,
  String titleText = 'Share Experience',
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return ShareExperienceBottomSheetContent(
        onDirectShare: onDirectShare,
        onCreateLink: onCreateLink,
        titleText: titleText,
      );
    },
  );
}

class ShareExperienceBottomSheetContent extends StatefulWidget {
  const ShareExperienceBottomSheetContent({
    super.key,
    required this.onDirectShare,
    required this.onCreateLink,
    required this.titleText,
  });

  final Future<void> Function() onDirectShare;
  final ShareBottomSheetCreateLinkCallback onCreateLink;
  final String titleText;

  @override
  State<ShareExperienceBottomSheetContent> createState() =>
      _ShareExperienceBottomSheetContentState();
}

class _ShareExperienceBottomSheetContentState
    extends State<ShareExperienceBottomSheetContent> {
  String _shareMode = 'separate_copy'; // 'my_copy' | 'separate_copy'
  bool _giveEditAccess = false;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _loadLastChoice();
  }

  Future<void> _loadLastChoice() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMode = prefs.getString(AppConstants.lastShareModeKey);
    final lastEdit = prefs.getBool(AppConstants.lastShareGiveEditAccessKey);
    if (!mounted) return;
    setState(() {
      _shareMode = lastMode ?? 'separate_copy';
      _giveEditAccess = lastEdit ?? false;
    });
  }

  Future<void> _persistChoice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.lastShareModeKey, _shareMode);
    await prefs.setBool(
        AppConstants.lastShareGiveEditAccessKey, _giveEditAccess);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  widget.titleText,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.send_outlined),
              title: const Text('Share to Plendy friends'),
              onTap: () async {
                await _persistChoice();
                if (!mounted) return;
                Navigator.of(context).pop();
                await widget.onDirectShare();
              },
            ),
            ListTile(
              leading: _creating
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link_outlined),
              title:
                  Text(_creating ? 'Creating link...' : 'Get shareable link'),
              onTap: _creating
                  ? null
                  : () async {
                      setState(() => _creating = true);
                      try {
                        await _persistChoice();
                        await widget.onCreateLink(
                          shareMode: _shareMode,
                          giveEditAccess:
                              _shareMode == 'my_copy' ? _giveEditAccess : false,
                        );
                      } finally {
                        if (mounted) {
                          setState(() => _creating = false);
                        }
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}

typedef ShareToFriendsSubmit = Future<DirectShareResult> Function(List<String> userIds);
typedef ShareToThreadsSubmit = Future<DirectShareResult> Function(List<String> threadIds);
typedef ShareToGroupChatSubmit = Future<DirectShareResult> Function(List<String> userIds);

Future<DirectShareResult?> showShareToFriendsModal({
  required BuildContext context,
  required ShareToFriendsSubmit onSubmit,
  ShareToThreadsSubmit? onSubmitToThreads,
  ShareToGroupChatSubmit? onSubmitToNewGroupChat,
  String? subjectLabel,
  String titleText = 'Share to friends',
  String actionButtonLabel = 'Share',
  List<String> initialSelectedUserIds = const [],
  Map<String, UserProfile> initialSelectedProfiles = const {},
  Map<String, String> disabledUserReasons = const {},
}) {
  return showModalBottomSheet<DirectShareResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => ShareToFriendsSheet(
      onSubmit: onSubmit,
      onSubmitToThreads: onSubmitToThreads,
      onSubmitToNewGroupChat: onSubmitToNewGroupChat,
      subjectLabel: subjectLabel,
      titleText: titleText,
      actionButtonLabel: actionButtonLabel,
      initialSelectedUserIds: initialSelectedUserIds,
      initialSelectedProfiles: initialSelectedProfiles,
      disabledUserReasons: disabledUserReasons,
    ),
  );
}

class ShareToFriendsSheet extends StatefulWidget {
  const ShareToFriendsSheet({
    super.key,
    required this.onSubmit,
    this.onSubmitToThreads,
    this.onSubmitToNewGroupChat,
    this.subjectLabel,
    this.titleText = 'Share to friends',
    this.actionButtonLabel = 'Share',
    this.initialSelectedUserIds = const [],
    this.initialSelectedProfiles = const {},
    this.disabledUserReasons = const {},
  });

  final ShareToFriendsSubmit onSubmit;
  final ShareToThreadsSubmit? onSubmitToThreads;
  final ShareToGroupChatSubmit? onSubmitToNewGroupChat;
  final String? subjectLabel;
  final String titleText;
  final String actionButtonLabel;
  final List<String> initialSelectedUserIds;
  final Map<String, UserProfile> initialSelectedProfiles;
  final Map<String, String> disabledUserReasons;

  @override
  State<ShareToFriendsSheet> createState() => _ShareToFriendsSheetState();
}

class _ShareToFriendsSheetState extends State<ShareToFriendsSheet> {
  final TextEditingController _searchController = TextEditingController();
  final UserService _userService = UserService();
  final MessageService _messageService = MessageService();
  
  // View 1: Friends selection
  final Map<String, UserProfile> _selectedProfiles = {};
  final Map<String, DateTime> _lastSharedAt = {};
  final List<UserProfile> _orderedFriends = [];
  List<UserProfile> _searchResults = [];
  Set<String> _friendIdSet = {};

  // View 2: Existing chats selection
  final Set<String> _selectedThreadIds = {};
  List<MessageThread> _existingThreads = [];
  bool _isLoadingThreads = false;
  String? _threadsError;

  // View toggle
  bool _isViewingExistingChats = false;

  bool _isLoading = true;
  bool _isSearching = false;
  bool _isSubmitting = false;
  String? _initializationError;

  Timer? _debounce;
  late final Set<String> _pendingInitialSelections;

  @override
  void initState() {
    super.initState();
    _selectedProfiles.addAll(widget.initialSelectedProfiles);
    _pendingInitialSelections = widget.initialSelectedUserIds
        .where((id) => !_selectedProfiles.containsKey(id))
        .toSet();
    _searchController.addListener(_onSearchChanged);
    _loadFriends();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      setState(() {
        _isLoading = false;
        _initializationError = 'You must be signed in to share with friends.';
      });
      return;
    }

    try {
      final List<String> friendIds =
          await _userService.getFriendIds(currentUser.uid);
      final Set<String> friendIdSet = friendIds.toSet();
      final Map<String, DateTime> recency =
          await _fetchRecentShareRecipients(currentUser.uid, friendIdSet);
      final List<UserProfile> profiles = await _fetchProfiles(friendIds);

      profiles.sort(_compareProfilesByRecency);

      if (!mounted) return;
      setState(() {
        _friendIdSet = friendIdSet;
        _lastSharedAt
          ..clear()
          ..addAll(recency);
        _orderedFriends
          ..clear()
          ..addAll(profiles);
        _isLoading = false;
      });
      _applyPendingInitialSelections(profiles);
    } catch (e) {
      debugPrint('ShareToFriendsSheet: Failed to load friends: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _initializationError =
            'Unable to load your friends right now. Please try again.';
      });
    }
  }

  Future<Map<String, DateTime>> _fetchRecentShareRecipients(
    String userId,
    Set<String> allowedIds,
  ) async {
    final Map<String, DateTime> recency = {};
    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('experience_shares')
          .where('fromUserId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(200);

      final QuerySnapshot<Map<String, dynamic>> snapshot = await query.get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final List<dynamic> rawRecipients =
            data['toUserIds'] as List<dynamic>? ?? const [];
        final Timestamp? ts = data['createdAt'] as Timestamp?;
        final DateTime createdAt =
            ts?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);

        for (final dynamic raw in rawRecipients) {
          if (raw is! String || raw.isEmpty) continue;
          if (!allowedIds.contains(raw)) continue;
          final DateTime? existing = recency[raw];
          if (existing == null || createdAt.isAfter(existing)) {
            recency[raw] = createdAt;
          }
        }
      }
    } catch (e) {
      debugPrint('ShareToFriendsSheet: Failed to load recency: $e');
    }
    return recency;
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

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final String query = _searchController.text.trim();
      if (query.isEmpty) {
        if (!mounted) return;
        setState(() {
          _searchResults = [];
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _isSearching = true;
      });

      try {
        final results = await _userService.searchUsers(query);
        final filtered = results
            .where((profile) => _friendIdSet.contains(profile.id))
            .toList()
          ..sort(_compareProfilesByRecency);
        if (!mounted) return;
        setState(() {
          _searchResults = filtered;
        });
      } catch (e) {
        debugPrint('ShareToFriendsSheet: search failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not search right now.')),
          );
        }
      } finally {
        if (!mounted) return;
        setState(() {
          _isSearching = false;
        });
      }
    });
  }

  int _compareProfilesByRecency(UserProfile a, UserProfile b) {
    final DateTime? lastA = _lastSharedAt[a.id];
    final DateTime? lastB = _lastSharedAt[b.id];
    if (lastA != null && lastB != null) {
      final int comparison = lastB.compareTo(lastA);
      if (comparison != 0) {
        return comparison;
      }
    } else if (lastA != null) {
      return -1;
    } else if (lastB != null) {
      return 1;
    }
    final String nameA =
        (a.displayName ?? a.username ?? '').toLowerCase().trim();
    final String nameB =
        (b.displayName ?? b.username ?? '').toLowerCase().trim();
    return nameA.compareTo(nameB);
  }

  void _toggleSelection(UserProfile profile) {
    if (widget.disabledUserReasons.containsKey(profile.id)) {
      return;
    }
    setState(() {
      if (_selectedProfiles.containsKey(profile.id)) {
        _selectedProfiles.remove(profile.id);
      } else {
        _selectedProfiles[profile.id] = profile;
      }
    });
  }

  void _applyPendingInitialSelections(Iterable<UserProfile> profiles) {
    if (_pendingInitialSelections.isEmpty || !mounted) {
      return;
    }
    final Map<String, UserProfile> additions = {};
    for (final profile in profiles) {
      if (_pendingInitialSelections.remove(profile.id)) {
        additions[profile.id] = profile;
      }
      if (_pendingInitialSelections.isEmpty) break;
    }
    if (additions.isEmpty) return;
    setState(() {
      _selectedProfiles.addAll(additions);
    });
  }

  Future<void> _loadExistingThreads() async {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      setState(() {
        _isLoadingThreads = false;
        _threadsError = 'You must be signed in to view chats.';
      });
      return;
    }

    setState(() {
      _isLoadingThreads = true;
      _threadsError = null;
    });

    try {
      // Fetch threads without orderBy to avoid needing a composite index
      // We'll sort client-side instead
      final snapshot = await FirebaseFirestore.instance
          .collection('message_threads')
          .where('participants', arrayContains: currentUser.uid)
          .limit(100)
          .get();

      final threads = snapshot.docs
          .map((doc) => MessageThread.fromFirestore(doc))
          .toList();

      // Sort by lastMessageTimestamp descending (most recent first)
      threads.sort((a, b) {
        final aTime = a.lastMessageTimestamp ?? a.updatedAt ?? a.createdAt;
        final bTime = b.lastMessageTimestamp ?? b.updatedAt ?? b.createdAt;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      if (!mounted) return;
      setState(() {
        _existingThreads = threads;
        _isLoadingThreads = false;
      });
    } catch (e) {
      debugPrint('ShareToFriendsSheet: Failed to load threads: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingThreads = false;
        _threadsError = 'Unable to load your chats right now.';
      });
    }
  }

  void _toggleThreadSelection(String threadId) {
    setState(() {
      if (_selectedThreadIds.contains(threadId)) {
        _selectedThreadIds.remove(threadId);
      } else {
        _selectedThreadIds.add(threadId);
      }
    });
  }

  void _switchToExistingChatsView() {
    setState(() {
      _isViewingExistingChats = true;
    });
    if (_existingThreads.isEmpty && !_isLoadingThreads) {
      _loadExistingThreads();
    }
  }

  void _switchToFriendsView() {
    setState(() {
      _isViewingExistingChats = false;
    });
  }

  Future<void> _submitShare() async {
    if (_isViewingExistingChats) {
      await _submitToThreads();
    } else {
      await _submitToFriends();
    }
  }

  Future<void> _submitToFriends() async {
    if (_selectedProfiles.isEmpty || _isSubmitting) {
      return;
    }
    FocusScope.of(context).unfocus();

    // If multiple friends selected, show dialog to choose individual or group
    if (_selectedProfiles.length > 1) {
      final choice = await _showMultipleFriendsDialog();
      if (choice == null) return; // User cancelled
      
      if (choice == 'group') {
        await _submitAsGroupChat();
        return;
      }
      // Otherwise continue with individual shares
    }

    setState(() {
      _isSubmitting = true;
    });
    try {
      final result = await widget.onSubmit(_selectedProfiles.keys.toList());
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      debugPrint('ShareToFriendsSheet: submit failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to send share. Please try again.'),
          ),
        );
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<String?> _showMultipleFriendsDialog() async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'You selected multiple friends',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'How would you like to share?',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop('individual'),
                  child: const Text('Send to each individually'),
                ),
              ),
              if (widget.onSubmitToNewGroupChat != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop('group'),
                    child: const Text('Create a new group chat'),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitAsGroupChat() async {
    if (widget.onSubmitToNewGroupChat == null) return;
    
    setState(() {
      _isSubmitting = true;
    });
    try {
      final result = await widget.onSubmitToNewGroupChat!(_selectedProfiles.keys.toList());
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      debugPrint('ShareToFriendsSheet: group chat submit failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to create group chat. Please try again.'),
          ),
        );
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _submitToThreads() async {
    if (_selectedThreadIds.isEmpty || _isSubmitting) {
      return;
    }
    if (widget.onSubmitToThreads == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sharing to existing chats is not supported here.'),
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
    });
    try {
      final result = await widget.onSubmitToThreads!(_selectedThreadIds.toList());
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      debugPrint('ShareToFriendsSheet: thread submit failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to send share. Please try again.'),
          ),
        );
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  String? _buildSubtitle(UserProfile profile) {
    final List<String> parts = [];
    if (profile.username != null && profile.username!.isNotEmpty) {
      parts.add('@${profile.username!}');
    }
    final DateTime? lastShared = _lastSharedAt[profile.id];
    if (lastShared != null) {
      parts.add(_formatRelativeTime(lastShared));
    }
    if (parts.isEmpty) return null;
    return parts.join(' • ');
  }

  String _formatRelativeTime(DateTime timestamp) {
    final Duration diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    
    // Determine selection state based on current view
    final bool hasSelection = _isViewingExistingChats
        ? _selectedThreadIds.isNotEmpty
        : _selectedProfiles.isNotEmpty;
    final bool isSearching = _searchController.text.trim().isNotEmpty;
    final List<UserProfile> visibleProfiles =
        isSearching ? _searchResults : _orderedFriends;

    return FractionallySizedBox(
      heightFactor: 0.9,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            children: [
              _buildHeader(context),
              if (!_isViewingExistingChats) _buildSearchField(),
              if (widget.subjectLabel != null &&
                  widget.subjectLabel!.isNotEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.subjectLabel!,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              _buildViewToggleButton(),
              if (!_isViewingExistingChats && _selectedProfiles.isNotEmpty)
                _buildSelectionChips(),
              if (_isViewingExistingChats && _selectedThreadIds.isNotEmpty)
                _buildThreadSelectionChips(),
              Expanded(
                child: _isViewingExistingChats
                    ? _buildExistingChatsContent()
                    : _buildListContent(
                        isSearching: isSearching,
                        visibleProfiles: visibleProfiles,
                      ),
              ),
              _buildShareButton(hasSelection),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.titleText,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(null),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
    );
  }

  Widget _buildViewToggleButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: _isViewingExistingChats
            ? _switchToFriendsView
            : _switchToExistingChatsView,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Icon(
                _isViewingExistingChats
                    ? Icons.person_outline
                    : Icons.forum_outlined,
                size: 20,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isViewingExistingChats
                      ? 'Choose individual friends'
                      : 'Choose existing chats',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: Theme.of(context).primaryColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThreadSelectionChips() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    return SizedBox(
      height: 72,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: _selectedThreadIds.map((threadId) {
          final thread = _existingThreads.firstWhere(
            (t) => t.id == threadId,
            orElse: () => MessageThread(
              id: threadId,
              participantIds: [],
              participantProfiles: {},
              participantsKey: '',
            ),
          );
          final display = _getThreadDisplayName(thread, currentUserId);
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Chip(
              label: Text(display),
              avatar: thread.isGroup
                  ? const CircleAvatar(child: Icon(Icons.group, size: 16))
                  : null,
              deleteIcon: const Icon(Icons.close),
              onDeleted: () {
                setState(() {
                  _selectedThreadIds.remove(threadId);
                });
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  String _getThreadDisplayName(MessageThread thread, String currentUserId) {
    if (thread.title != null && thread.title!.isNotEmpty) {
      return thread.title!;
    }
    final others = thread.otherParticipants(currentUserId);
    if (others.isEmpty) return 'Chat';
    if (others.length == 1) {
      return others.first.displayName ?? others.first.username ?? 'Friend';
    }
    final names = others
        .take(3)
        .map((p) => p.displayName ?? p.username ?? 'Friend')
        .join(', ');
    if (others.length > 3) {
      return '$names +${others.length - 3}';
    }
    return names;
  }

  Widget _buildExistingChatsContent() {
    if (_isLoadingThreads) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_threadsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            _threadsError!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      );
    }

    if (_existingThreads.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'No existing chats found. Start a conversation first!',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return ListView.separated(
      itemCount: _existingThreads.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final thread = _existingThreads[index];
        final bool isSelected = _selectedThreadIds.contains(thread.id);
        final displayName = _getThreadDisplayName(thread, currentUserId);
        final others = thread.otherParticipants(currentUserId);

        return ListTile(
          leading: _buildThreadAvatar(thread, others),
          title: Text(displayName),
          subtitle: thread.lastMessage != null
              ? Text(
                  thread.lastMessage!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                )
              : null,
          trailing: Icon(
            isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
          ),
          onTap: () => _toggleThreadSelection(thread.id),
        );
      },
    );
  }

  Widget _buildThreadAvatar(
    MessageThread thread,
    List<dynamic> others,
  ) {
    if (thread.isGroup) {
      return CircleAvatar(
        child: Icon(
          Icons.group,
          color: Colors.black,
        ),
      );
    }

    if (others.isNotEmpty) {
      final participant = others.first;
      final name = participant.displayName ?? participant.username ?? '';
      return CachedProfileAvatar(
        photoUrl: participant.photoUrl,
        fallbackText: name.isNotEmpty ? name[0].toUpperCase() : '?',
      );
    }

    return const CircleAvatar(child: Icon(Icons.person));
  }

  Widget _buildSelectionChips() {
    return SizedBox(
      height: 72,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: _selectedProfiles.values.map((profile) {
          final String display =
              profile.displayName ?? profile.username ?? 'Friend';
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Chip(
              label: Text(display),
              avatar: CachedProfileAvatar(
                photoUrl: profile.photoURL,
                radius: 12,
                fallbackText: display.isNotEmpty ? display[0].toUpperCase() : null,
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
    );
  }

  Widget _buildListContent({
    required bool isSearching,
    required List<UserProfile> visibleProfiles,
  }) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_initializationError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            _initializationError!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      );
    }

    if (_friendIdSet.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'You have no Plendy friends yet. Follow people back to share with them.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (isSearching) {
      if (_isSearching) {
        return const Center(child: CircularProgressIndicator());
      }
      if (visibleProfiles.isEmpty) {
        return const Center(
          child: Text('No friends found.'),
        );
      }
    } else if (visibleProfiles.isEmpty) {
      return const Center(
        child: Text('No recent friends to show yet.'),
      );
    }

    return ListView.separated(
      itemCount: visibleProfiles.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final profile = visibleProfiles[index];
        final bool isSelected = _selectedProfiles.containsKey(profile.id);
        final String title =
            profile.displayName ?? profile.username ?? 'Friend';
        final String? disabledReason = widget.disabledUserReasons[profile.id];
        final bool isDisabled = disabledReason != null;
        final Widget? subtitle = _buildListTileSubtitle(
          profile,
          disabledReason: disabledReason,
        );
        return ListTile(
          enabled: !isDisabled,
          leading: CachedProfileAvatar(
            photoUrl: profile.photoURL,
            fallbackText: title.isNotEmpty ? title[0].toUpperCase() : '?',
          ),
          title: Text(title),
          subtitle: subtitle,
          trailing: isDisabled
              ? _buildDisabledIndicator(disabledReason)
              : Icon(
                  isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color:
                      isSelected ? Theme.of(context).primaryColor : Colors.grey,
                ),
          onTap: isDisabled ? null : () => _toggleSelection(profile),
        );
      },
    );
  }

  Widget? _buildListTileSubtitle(
    UserProfile profile, {
    String? disabledReason,
  }) {
    final String? subtitleText = _buildSubtitle(profile);
    if (subtitleText == null && disabledReason == null) {
      return null;
    }
    final List<Widget> children = [];
    if (subtitleText != null && subtitleText.isNotEmpty) {
      children.add(Text(subtitleText));
    }
    if (disabledReason != null) {
      children.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline,
              size: 14, color: Colors.grey.withOpacity(0.8)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              disabledReason,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.withOpacity(0.9),
              ),
            ),
          ),
        ],
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildDisabledIndicator(String? reason) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        reason ?? 'Unavailable',
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey.shade700,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildShareButton(bool hasSelection) {
    final String baseLabel = widget.actionButtonLabel;
    final int selectionCount = _isViewingExistingChats
        ? _selectedThreadIds.length
        : _selectedProfiles.length;
    final String label =
        hasSelection ? '$baseLabel ($selectionCount)' : baseLabel;
    
    // Check if the required callback is available for current view
    final bool canSubmit = _isViewingExistingChats
        ? widget.onSubmitToThreads != null
        : true;
    
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: hasSelection && !_isSubmitting && canSubmit
                ? _submitShare
                : null,
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(label),
          ),
        ),
      ),
    );
  }
}
