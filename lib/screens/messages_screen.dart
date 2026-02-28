import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/colors.dart';
import '../models/message_thread.dart';
import '../models/message_thread_participant.dart';
import '../services/auth_service.dart';
import '../services/message_service.dart';
import '../widgets/cached_profile_avatar.dart';
import 'chat_screen.dart';
import 'new_message_thread_screen.dart';
import 'package:plendy/utils/haptic_feedback.dart';
import '../config/messages_help_content.dart';
import '../models/messages_help_target.dart';
import '../widgets/screen_help_controller.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
    with TickerProviderStateMixin {
  late final MessageService _messageService;
  late final ScreenHelpController<MessagesHelpTargetId> _help;
  Stream<List<MessageThread>>? _threadsStream;
  String? _threadsStreamUserId;

  @override
  void initState() {
    super.initState();
    _messageService = MessageService();
    _help = ScreenHelpController<MessagesHelpTargetId>(
      vsync: this,
      content: messagesHelpContent,
      setState: setState,
      isMounted: () => mounted,
      defaultFirstTarget: MessagesHelpTargetId.helpButton,
    );
  }

  @override
  void dispose() {
    _help.dispose();
    super.dispose();
  }

  Future<void> _openNewChat(BuildContext context, String currentUserId) async {
    final thread = await Navigator.push<MessageThread>(
      context,
      MaterialPageRoute(
        builder: (context) => NewMessageThreadScreen(
          messageService: _messageService,
        ),
      ),
    );

    if (!mounted || thread == null) {
      return;
    }

    _openChat(thread, currentUserId);
  }

  void _openChat(MessageThread thread, String currentUserId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          thread: thread,
          currentUserId: currentUserId,
        ),
      ),
    );
  }

  Stream<List<MessageThread>> _watchThreads(String userId) {
    if (_threadsStream == null || _threadsStreamUserId != userId) {
      _threadsStreamUserId = userId;
      _threadsStream = _messageService.watchThreadsForUser(userId);
    }
    return _threadsStream!;
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final currentUser = authService.currentUser;

    if (currentUser == null) {
      return const Scaffold(
        body: Center(
          child: Text('You need to be signed in to view messages.'),
        ),
      );
    }

    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.backgroundColor,
          appBar: AppBar(
            backgroundColor: AppColors.backgroundColor,
            foregroundColor: Colors.black,
            title: const Text('Messages'),
            actions: [_help.buildIconButton(inactiveColor: Colors.black87)],
            bottom: _help.isActive
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(24),
                    child: _help.buildExitBanner(),
                  )
                : null,
          ),
          floatingActionButton: Builder(
            builder: (fabCtx) => FloatingActionButton(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              onPressed: _help.isActive
                  ? () => _help.tryTap(
                      MessagesHelpTargetId.newMessageButton, fabCtx)
                  : () => _openNewChat(context, currentUser.uid),
              child: const Icon(Icons.message),
            ),
          ),
          body: Builder(
            builder: (listCtx) => GestureDetector(
              behavior: _help.isActive
                  ? HitTestBehavior.opaque
                  : HitTestBehavior.deferToChild,
              onTap: _help.isActive
                  ? () =>
                      _help.tryTap(MessagesHelpTargetId.messagesList, listCtx)
                  : null,
              child: IgnorePointer(
                ignoring: _help.isActive,
                child: StreamBuilder<List<MessageThread>>(
                  stream: _watchThreads(currentUser.uid),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Something went wrong: ${snapshot.error}'),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {}); // Trigger a rebuild to retry
                              },
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      );
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final threads = snapshot.data ?? [];
                    if (threads.isEmpty) {
                      return _buildEmptyState(context);
                    }

                    return ListView.separated(
                      itemCount: threads.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final thread = threads[index];
                        return _buildThreadTile(thread, currentUser.uid);
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        if (_help.isActive && _help.hasActiveTarget) _help.buildOverlay(),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.forum_outlined, size: 56, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'Start a conversation with your friends.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildThreadTile(MessageThread thread, String currentUserId) {
    final participants = thread.otherParticipants(currentUserId);
    final title = _buildThreadTitle(thread, participants);
    final subtitle = _buildSubtitle(thread, currentUserId, participants);
    final timestamp = _formatTimestamp(context,
        thread.lastMessageTimestamp ?? thread.updatedAt ?? thread.createdAt);
    final isUnread = thread.hasUnreadMessages(currentUserId);

    return ListTile(
      leading: _buildAvatar(participants),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
              ),
            )
          : null,
      trailing: timestamp != null
          ? Text(
              timestamp,
              style: TextStyle(
                fontSize: 12,
                color: isUnread ? Colors.black : Colors.grey,
                fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
              ),
            )
          : null,
      onTap: withHeavyTap(() => _openChat(thread, currentUserId)),
    );
  }

  Widget _buildAvatar(List<MessageThreadParticipant> participants) {
    if (participants.isEmpty) {
      return const CircleAvatar(child: Icon(Icons.person));
    }

    if (participants.length == 1) {
      final participant = participants.first;
      return CachedProfileAvatar(
        photoUrl: participant.photoUrl,
        fallbackText: _initials(participant.displayLabel(fallback: 'U')),
      );
    }

    return const CircleAvatar(child: Icon(Icons.group));
  }

  String _buildThreadTitle(
    MessageThread thread,
    List<MessageThreadParticipant> participants,
  ) {
    final customTitle = thread.title?.trim();
    if (customTitle != null && customTitle.isNotEmpty) {
      return customTitle;
    }
    if (participants.isEmpty) {
      return 'Just you';
    }
    if (participants.length == 1) {
      return participants.first.displayLabel(fallback: 'Unknown user');
    }
    return participants
        .map((participant) => participant.displayLabel(fallback: 'Unknown'))
        .join(', ');
  }

  String? _buildSubtitle(
    MessageThread thread,
    String currentUserId,
    List<MessageThreadParticipant> participants,
  ) {
    final message = thread.lastMessage;
    if (message == null || message.isEmpty) {
      return participants.isNotEmpty ? 'Tap to start chatting' : null;
    }
    final sender = thread.participant(thread.lastMessageSenderId ?? '');
    final prefix = thread.lastMessageSenderId == currentUserId
        ? 'You: '
        : '${sender?.displayLabel(fallback: 'Someone') ?? 'Someone'}: ';
    return '$prefix$message';
  }

  String? _formatTimestamp(BuildContext context, DateTime? timestamp) {
    if (timestamp == null) {
      return null;
    }
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Now';
    }
    if (difference.inHours < 1) {
      return '${difference.inMinutes}m';
    }
    if (difference.inHours < 24 &&
        timestamp.day == now.day &&
        timestamp.month == now.month &&
        timestamp.year == now.year) {
      final timeOfDay = TimeOfDay.fromDateTime(timestamp);
      return timeOfDay.format(context);
    }
    if (difference.inDays < 7) {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[timestamp.weekday - 1];
    }
    return '${timestamp.month}/${timestamp.day}/${timestamp.year % 100}';
  }

  String _initials(String value) {
    final segments = value.trim().split(' ');
    if (segments.isEmpty) {
      return 'U';
    }
    if (segments.length == 1) {
      return segments.first.substring(0, 1).toUpperCase();
    }
    return (segments[0].isNotEmpty ? segments[0][0].toUpperCase() : '') +
        (segments.length > 1 && segments[1].isNotEmpty
            ? segments[1][0].toUpperCase()
            : '');
  }
}
