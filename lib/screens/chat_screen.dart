import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chat_message.dart';
import '../models/message_thread.dart';
import '../models/message_thread_participant.dart';
import '../services/message_service.dart';
import 'messages_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.thread,
    required this.currentUserId,
  });

  final MessageThread thread;
  final String currentUserId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final MessageService _messageService;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _messageService = MessageService();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) {
      return;
    }

    setState(() {
      _sending = true;
    });

    try {
      await _messageService.sendMessage(
        threadId: widget.thread.id,
        senderId: widget.currentUserId,
        text: text,
      );
      _messageController.clear();
      _scrollToBottom();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send message: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Future<void> _openLink(Uri uri) async {
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link.')),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open link: $error')),
      );
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _handleBackPressed() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const MessagesScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MessageThread?>(
      stream: _messageService.watchThread(widget.thread.id),
      initialData: widget.thread,
      builder: (context, threadSnapshot) {
        final thread = threadSnapshot.data ?? widget.thread;
        final title = _buildTitle(thread);
        return Scaffold(
          appBar: AppBar(
            leading: BackButton(onPressed: _handleBackPressed),
            title: Text(title),
          ),
          body: Column(
            children: [
              Expanded(
                child: StreamBuilder<List<ChatMessage>>(
                  stream: _messageService.watchMessages(thread.id),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text('Something went wrong: ${snapshot.error}'),
                      );
                    }

                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final messages = snapshot.data!;
                    if (messages.isEmpty) {
                      return _buildEmptyThread(thread);
                    }

                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _scrollToBottom());

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        final isMine = message.senderId == widget.currentUserId;
                        final sender = thread.participant(message.senderId);
                        return _buildMessageBubble(message, isMine, sender);
                      },
                    );
                  },
                ),
              ),
              _buildInputArea(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyThread(MessageThread thread) {
    final participants = thread.otherParticipants(widget.currentUserId);
    final intro = participants.isEmpty
        ? 'Say something to yourself...'
        : 'Say hello to ${participants.map((p) => p.displayLabel(fallback: 'a friend')).join(', ')}';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Text(
          intro,
          style: const TextStyle(fontSize: 16, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildMessageBubble(
    ChatMessage message,
    bool isMine,
    MessageThreadParticipant? sender,
  ) {
    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final bubbleColor =
        isMine ? Theme.of(context).primaryColor : Colors.grey.shade200;
    final textColor = isMine ? Colors.white : Colors.black87;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMine ? 18 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 18),
    );

    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: radius,
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMine)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  sender?.displayLabel(fallback: 'Someone') ?? 'Someone',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
              ),
            _buildMessageText(message, textColor, isMine),
            const SizedBox(height: 4),
            Text(
              _formatMessageTime(message.createdAt),
              style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageText(
    ChatMessage message,
    Color textColor,
    bool isMine,
  ) {
    final segments = MessageThread.extractMessageSegments(message.text);
    final baseStyle = TextStyle(color: textColor, fontSize: 16);

    if (segments.isEmpty || segments.every((segment) => !segment.isLink)) {
      return Text(
        message.text,
        style: baseStyle,
      );
    }

    final linkColor = isMine ? Colors.white : Theme.of(context).primaryColor;
    final linkStyle = baseStyle.copyWith(
      color: linkColor,
      decoration: TextDecoration.underline,
    );

    return Text.rich(
      TextSpan(
        children: segments.map((segment) {
          if (segment.isLink && segment.uri != null) {
            return TextSpan(
              text: segment.text,
              style: linkStyle,
              recognizer: TapGestureRecognizer()
                ..onTap = () => _openLink(segment.uri!),
            );
          }
          return TextSpan(text: segment.text);
        }).toList(),
      ),
      style: baseStyle,
    );
  }

  Widget _buildInputArea() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade300)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                decoration: const InputDecoration(
                  hintText: 'Type a message',
                  border: InputBorder.none,
                ),
              ),
            ),
            IconButton(
              icon: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              color: Theme.of(context).primaryColor,
              onPressed: _sending ? null : _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  String _buildTitle(MessageThread thread) {
    final participants = thread.otherParticipants(widget.currentUserId);
    if (participants.isEmpty) {
      return 'Personal Notes';
    }
    if (participants.length == 1) {
      return participants.first.displayLabel(fallback: 'Conversation');
    }
    return participants
        .map((participant) => participant.displayLabel(fallback: 'Friend'))
        .join(', ');
  }

  String _formatMessageTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    if (difference.inMinutes < 1) {
      return 'Now';
    }
    if (difference.inHours < 1) {
      return '${difference.inMinutes}m';
    }
    if (difference.inDays < 1) {
      final timeOfDay = TimeOfDay.fromDateTime(timestamp);
      return timeOfDay.format(context);
    }
    return '${timestamp.month}/${timestamp.day}/${timestamp.year % 100}';
  }
}
