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
    // For experience share messages, use a special card layout
    if (message.isExperienceShare) {
      return _buildExperienceShareCard(message, isMine, sender);
    }

    // Regular text message bubble
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

  Widget _buildExperienceShareCard(
    ChatMessage message,
    bool isMine,
    MessageThreadParticipant? sender,
  ) {
    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final snapshot = message.experienceSnapshot;
    
    if (snapshot == null) {
      // Fallback if snapshot is missing
      return Align(
        alignment: alignment,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('Shared an experience'),
        ),
      );
    }

    final experienceName = snapshot['name'] as String? ?? 'Experience';
    final locationData = snapshot['location'] as Map<String, dynamic>?;
    
    // Check if this is a discovery preview share (has highlightedMediaUrl)
    final highlightedMediaUrl = snapshot['highlightedMediaUrl'] as String?;
    final isDiscoveryPreview = highlightedMediaUrl != null && highlightedMediaUrl.isNotEmpty;
    
    // Use highlighted media URL for discovery shares, otherwise use the main image
    final imageUrl = isDiscoveryPreview ? highlightedMediaUrl : (snapshot['image'] as String?);
    final description = snapshot['description'] as String?;
    
    // Build location subtitle
    final List<String> locationParts = [];
    if (locationData != null) {
      final city = locationData['city'] as String?;
      final state = locationData['state'] as String?;
      if (city != null && city.isNotEmpty) {
        locationParts.add(city);
      }
      if (state != null && state.isNotEmpty) {
        locationParts.add(state);
      }
    }
    final locationText = locationParts.join(', ');

    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMine)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Row(
                  children: [
                    Text(
                      '${sender?.displayLabel(fallback: 'Someone') ?? 'Someone'} shared',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                    if (isDiscoveryPreview) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Discovery',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.purple.shade700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                children: [
                  InkWell(
                    onTap: () => _handleExperienceShareTap(
                      experienceName: experienceName,
                      highlightedMediaUrl: highlightedMediaUrl,
                      snapshot: snapshot,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (imageUrl != null && imageUrl.isNotEmpty)
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(12),
                            ),
                            child: _buildMediaPreview(imageUrl, isDiscoveryPreview),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      experienceName,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                                ],
                              ),
                          if (locationText.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.place_outlined,
                                  size: 14,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    locationText,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (description != null && description.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              description,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                  ),
                  // Play button positioned on the bottom-right
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
              child: Text(
                _formatMessageTime(message.createdAt),
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 11,
                ),
              ),
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

  Future<void> _handleExperienceShareTap({
    required String experienceName,
    required String? highlightedMediaUrl,
    required Map<String, dynamic> snapshot,
  }) async {
    // If it's a discovery preview share with a highlighted media URL, open the URL
    if (highlightedMediaUrl != null && highlightedMediaUrl.isNotEmpty) {
      await _openLink(Uri.parse(highlightedMediaUrl));
      return;
    }

    // Otherwise, show the experience details (TODO: implement full experience view)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opening $experienceName...'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildMediaPreview(String url, bool isDiscoveryPreview) {
    // Check if it's a social media link or regular image
    final lowerUrl = url.toLowerCase();
    final isSocialMedia = lowerUrl.contains('tiktok.com') ||
        lowerUrl.contains('instagram.com') ||
        lowerUrl.contains('facebook.com') ||
        lowerUrl.contains('youtube.com') ||
        lowerUrl.contains('youtu.be');

    if (isSocialMedia && isDiscoveryPreview) {
      // For social media discovery shares, show a preview indicator
      return Container(
        height: 180,
        color: Colors.grey.shade900,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getMediaIcon(lowerUrl),
                    size: 64,
                    color: Colors.white70,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tap to view ${_getMediaType(lowerUrl)}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Discovery Preview',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    // For regular images
    return Image.network(
      url,
      height: 180,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          height: 180,
          color: Colors.grey.shade300,
          child: const Icon(
            Icons.image_not_supported,
            size: 48,
            color: Colors.grey,
          ),
        );
      },
    );
  }

  IconData _getMediaIcon(String url) {
    if (url.contains('tiktok.com')) return Icons.play_circle_outline;
    if (url.contains('instagram.com')) return Icons.camera_alt_outlined;
    if (url.contains('facebook.com')) return Icons.video_library_outlined;
    if (url.contains('youtube.com') || url.contains('youtu.be')) return Icons.play_circle_outline;
    return Icons.link;
  }

  String _getMediaType(String url) {
    if (url.contains('tiktok.com')) return 'TikTok';
    if (url.contains('instagram.com')) return 'Instagram';
    if (url.contains('facebook.com')) return 'Facebook';
    if (url.contains('youtube.com') || url.contains('youtu.be')) return 'YouTube';
    return 'content';
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
